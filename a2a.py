#!/usr/bin/env python3
"""a2a - peer-to-peer agent-to-agent messaging.

Agent sessions (Claude Code, Codex CLI) on different machines hold threaded
conversations: messages, task requests with a lifecycle (pending -> working ->
done/failed), results with attached files, and structured metadata. Each
machine runs `a2a daemon` (reachable over Tailscale); `a2a wait` blocks until
delivery so a session gets woken instead of polling. A person can run many
agent sessions at once: the first session to `a2a read` an item claims it
(set A2A_AGENT to name a session; defaults to hostname). See skill/SKILL.md
for the protocol agents follow.

Config in ~/.a2a/config.json:
{
  "me": "jamie",
  "listen": {"host": "0.0.0.0", "port": 8765},
  "token": "secret-others-need-to-send-to-me",
  "peers": {
    "simon": {"url": "http://100.x.y.z:8765", "token": "simons-secret"}
  }
}

Stdlib only. Received tasks are never auto-executed by this tool; the
receiving agent triages them (see AGENTS.md).
"""

import argparse
import base64
import json
import os
import secrets
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

A2A_DIR = Path(os.environ.get("A2A_DIR", Path.home() / ".a2a"))
CONFIG_PATH = A2A_DIR / "config.json"
INBOX_DIR = A2A_DIR / "inbox"
OUTBOX_DIR = A2A_DIR / "outbox"
FILES_DIR = A2A_DIR / "files"
MAX_FILE_BYTES = 100 * 1024 * 1024
KINDS = ("message", "task", "result")
STATUSES = ("accepted", "working", "done", "failed")


def load_config():
    if not CONFIG_PATH.exists():
        sys.exit(f"No config at {CONFIG_PATH}. Run: a2a init --me NAME")
    return json.loads(CONFIG_PATH.read_text())


def ensure_dirs():
    for d in (INBOX_DIR, OUTBOX_DIR, FILES_DIR):
        d.mkdir(parents=True, exist_ok=True)


def new_id():
    return time.strftime("%Y%m%d-%H%M%S") + "-" + secrets.token_hex(3)


def agent_name():
    return os.environ.get("A2A_AGENT", socket.gethostname())


def sanitize_filename(name):
    name = os.path.basename(name.replace("\\", "/"))
    return name.replace("..", "_") or "unnamed"


# ---------------- daemon (receiver) ----------------

class Handler(BaseHTTPRequestHandler):
    token = None
    notify_command = None

    def _json(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/ping":
            self._json(200, {"ok": True})
        else:
            self._json(404, {"error": "not found"})

    def do_POST(self):
        if self.path != "/send":
            self._json(404, {"error": "not found"})
            return
        if self.headers.get("Authorization", "") != f"Bearer {self.token}":
            self._json(401, {"error": "bad token"})
            return
        length = int(self.headers.get("Content-Length", 0))
        if length > MAX_FILE_BYTES * 1.4:
            self._json(413, {"error": "too large"})
            return
        try:
            item = json.loads(self.rfile.read(length))
        except (json.JSONDecodeError, ValueError):
            self._json(400, {"error": "bad json"})
            return
        if item.get("kind") not in KINDS:
            self._json(400, {"error": f"kind must be one of {KINDS}"})
            return

        item_id = new_id()
        stored = {
            "id": item_id,
            "thread": str(item.get("thread") or item_id)[:64],
            "reply_to": str(item.get("reply_to", ""))[:64],
            "from": str(item.get("from", "unknown"))[:64],
            "from_agent": str(item.get("from_agent", ""))[:64],
            "kind": item["kind"],
            "status": item.get("status", ""),
            "text": str(item.get("text", ""))[:200_000],
            "meta": item.get("meta") if isinstance(item.get("meta"), dict) else {},
            "files": [],
            "received": time.strftime("%Y-%m-%d %H:%M:%S"),
            "claimed_by": "",
        }
        if stored["kind"] == "result" and stored["status"] not in STATUSES:
            self._json(400, {"error": f"result status must be one of {STATUSES}"})
            return
        for f in item.get("files", []):
            raw = base64.b64decode(f.get("data_b64", ""))
            if len(raw) > MAX_FILE_BYTES:
                self._json(413, {"error": "file too large"})
                return
            fname = sanitize_filename(f.get("filename", "unnamed"))
            fpath = FILES_DIR / f"{item_id}_{fname}"
            fpath.write_bytes(raw)
            stored["files"].append(
                {"filename": fname, "size": len(raw), "stored_path": str(fpath)})
        (INBOX_DIR / f"{item_id}.json").write_text(json.dumps(stored, indent=2))
        self._json(200, {"ok": True, "id": item_id, "thread": stored["thread"]})
        if self.notify_command:
            summary = f"{stored['from']}: {stored['kind']} - {stored['text'][:120]}"
            try:
                subprocess.Popen(self.notify_command + [summary],
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            except OSError as e:
                sys.stderr.write(f"notify_command failed: {e}\n")

    def log_message(self, fmt, *args):
        sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))


def cmd_daemon(cfg, args):
    ensure_dirs()
    listen = cfg.get("listen", {})
    host = listen.get("host", "0.0.0.0")
    port = listen.get("port", 8765)
    Handler.token = cfg["token"]
    Handler.notify_command = cfg.get("notify_command")
    print(f"a2a daemon: {cfg['me']} listening on {host}:{port}, inbox {INBOX_DIR}")
    ThreadingHTTPServer((host, port), Handler).serve_forever()


# ---------------- sending ----------------

def parse_meta(pairs):
    meta = {}
    for pair in pairs or []:
        if "=" not in pair:
            sys.exit(f"--meta must be key=value, got '{pair}'")
        k, v = pair.split("=", 1)
        meta[k] = v
    return meta


def deliver(cfg, peer_name, payload):
    peer = cfg.get("peers", {}).get(peer_name)
    if not peer:
        sys.exit(f"Unknown peer '{peer_name}'. Known: {', '.join(cfg.get('peers', {}))}")
    payload["from"] = cfg["me"]
    payload["from_agent"] = agent_name()
    req = urllib.request.Request(
        peer["url"].rstrip("/") + "/send",
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json",
                 "Authorization": f"Bearer {peer['token']}"},
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            result = json.loads(resp.read())
    except urllib.error.URLError as e:
        sys.exit(f"Send to {peer_name} failed: {e}")

    ensure_dirs()
    record = dict(payload)
    for f in record.get("files", []):
        f.pop("data_b64", None)
    record.update(id=result["id"], thread=result["thread"], to=peer_name,
                  sent=time.strftime("%Y-%m-%d %H:%M:%S"))
    (OUTBOX_DIR / f"{result['id']}.json").write_text(json.dumps(record, indent=2))
    return result


def attach_files(payload, file_args):
    files = []
    for f in file_args or []:
        fpath = Path(f)
        if not fpath.is_file():
            sys.exit(f"No such file: {fpath}")
        raw = fpath.read_bytes()
        if len(raw) > MAX_FILE_BYTES:
            sys.exit(f"{fpath.name} exceeds {MAX_FILE_BYTES // (1024*1024)}MB limit")
        files.append({"filename": fpath.name, "size": len(raw),
                      "data_b64": base64.b64encode(raw).decode()})
    if files:
        payload["files"] = files


def cmd_send(cfg, args):
    if args.task and args.message:
        sys.exit("Use --task (with the request as its text) or --message, not both")
    if not (args.task or args.message or args.file):
        sys.exit("Nothing to send: use --message, --task, and/or --file")
    payload = {
        "kind": "task" if args.task else "message",
        "text": args.task or args.message or "",
        "meta": parse_meta(args.meta),
    }
    if args.task:
        payload["status"] = "pending"
    if args.thread:
        payload["thread"] = args.thread
    attach_files(payload, args.file)
    result = deliver(cfg, args.peer, payload)
    print(f"Delivered to {args.peer}: {payload['kind']} id {result['id']}, thread {result['thread']}")


def find_inbox_item(item_id):
    path = INBOX_DIR / f"{item_id}.json"
    if not path.exists():
        sys.exit(f"No inbox item {item_id}")
    return json.loads(path.read_text())


def cmd_reply(cfg, args):
    orig = find_inbox_item(args.id)
    payload = {
        "kind": "message",
        "text": args.message or "",
        "thread": orig["thread"],
        "reply_to": orig["id"],
        "meta": parse_meta(args.meta),
    }
    attach_files(payload, args.file)
    result = deliver(cfg, orig["from"], payload)
    print(f"Replied to {orig['from']} in thread {orig['thread']} (id {result['id']})")


def cmd_result(cfg, args):
    orig = find_inbox_item(args.id)
    if orig["kind"] != "task":
        sys.exit(f"Item {args.id} is a {orig['kind']}, not a task")
    payload = {
        "kind": "result",
        "status": args.status,
        "text": args.message or "",
        "thread": orig["thread"],
        "reply_to": orig["id"],
        "meta": parse_meta(args.meta),
    }
    attach_files(payload, args.file)
    result = deliver(cfg, orig["from"], payload)
    print(f"Sent {args.status} result to {orig['from']} in thread {orig['thread']} (id {result['id']})")


# ---------------- inbox / threads ----------------

def summarise(i, direction):
    who = f"from {i['from']}" if direction == "in" else f"to {i['to']}"
    status = f" [{i['status']}]" if i.get("status") else ""
    files = f" ({len(i['files'])} file{'s' if len(i['files']) != 1 else ''})" if i.get("files") else ""
    claimed = f" (claimed: {i['claimed_by']})" if i.get("claimed_by") else ""
    preview = i["text"][:80].replace("\n", " ")
    return f"{i['id']}  {i['kind']:<7}{status} {who}{files}{claimed}  {preview}"


def cmd_inbox(cfg, args):
    ensure_dirs()
    items = [json.loads(p.read_text()) for p in sorted(INBOX_DIR.glob("*.json"))]
    if args.unclaimed:
        items = [i for i in items if not i.get("claimed_by")]
    if not items:
        print("No unclaimed items" if args.unclaimed else "Inbox empty")
        return
    for i in items:
        flag = " " if i.get("claimed_by") else "*"
        print(f"{flag} {summarise(i, 'in')}")


def cmd_read(cfg, args):
    path = INBOX_DIR / f"{args.id}.json"
    item = find_inbox_item(args.id)
    me_agent = agent_name()
    if item.get("claimed_by") and item["claimed_by"] != me_agent and not args.force:
        sys.exit(f"Already claimed by agent '{item['claimed_by']}' - it is handling this "
                 f"item (use --force to read anyway without claiming)")
    shown = {k: v for k, v in item.items() if k != "files"}
    shown["files"] = [f["filename"] for f in item["files"]]
    print(json.dumps(shown, indent=2))
    for f in item["files"]:
        out = Path(args.out or ".") / f["filename"]
        out.write_bytes(Path(f["stored_path"]).read_bytes())
        print(f"File written to {out.resolve()}")
    if not item.get("claimed_by"):
        item["claimed_by"] = me_agent
        path.write_text(json.dumps(item, indent=2))


def cmd_thread(cfg, args):
    ensure_dirs()
    entries = []
    for d, direction in ((INBOX_DIR, "in"), (OUTBOX_DIR, "out")):
        for p in d.glob("*.json"):
            i = json.loads(p.read_text())
            if i.get("thread") == args.id:
                entries.append((i.get("received") or i.get("sent"), direction, i))
    if not entries:
        sys.exit(f"No items in thread {args.id}")
    for ts, direction, i in sorted(entries):
        arrow = "<-" if direction == "in" else "->"
        print(f"{ts} {arrow} {summarise(i, direction)}")


def cmd_wait(cfg, args):
    ensure_dirs()
    known = {p.name for p in INBOX_DIR.glob("*.json")}
    deadline = time.time() + args.timeout if args.timeout else None
    while True:
        new = {p.name for p in INBOX_DIR.glob("*.json")} - known
        if new:
            for name in sorted(new):
                item = json.loads((INBOX_DIR / name).read_text())
                status = f" [{item['status']}]" if item.get("status") else ""
                print(f"NEW {item['kind']}{status} from {item['from']}: "
                      f"id {item['id']}, thread {item['thread']}")
            return
        if deadline and time.time() > deadline:
            print("Timed out with no new items")
            sys.exit(2)
        time.sleep(1)


def cmd_peer(cfg, args):
    if args.action == "list":
        for name, peer in cfg.get("peers", {}).items():
            print(f"{name}  {peer['url']}")
        return
    if not args.name:
        sys.exit("peer add/remove needs a name")
    if args.action == "add":
        if not (args.url and args.token):
            sys.exit("Usage: a2a peer add NAME URL TOKEN")
        cfg.setdefault("peers", {})[args.name] = {"url": args.url, "token": args.token}
    elif args.action == "remove":
        if args.name not in cfg.get("peers", {}):
            sys.exit(f"No peer '{args.name}'")
        del cfg["peers"][args.name]
    CONFIG_PATH.write_text(json.dumps(cfg, indent=2))
    print(f"Peer '{args.name}' {'added' if args.action == 'add' else 'removed'}")


def cmd_init(cfg_unused, args):
    A2A_DIR.mkdir(parents=True, exist_ok=True)
    if CONFIG_PATH.exists() and not args.force:
        sys.exit(f"{CONFIG_PATH} already exists (use --force to overwrite)")
    cfg = {
        "me": args.me,
        "listen": {"host": "0.0.0.0", "port": args.port},
        "token": secrets.token_urlsafe(24),
        "peers": {},
    }
    CONFIG_PATH.write_text(json.dumps(cfg, indent=2))
    ensure_dirs()
    print(f"Wrote {CONFIG_PATH}")
    print(f"Your inbox token (give this to peers): {cfg['token']}")
    print('Add peers under "peers", e.g. {"simon": {"url": "http://100.x.y.z:8765", "token": "..."}}')


def main():
    p = argparse.ArgumentParser(prog="a2a", description=__doc__.split("\n")[0])
    sub = p.add_subparsers(dest="cmd", required=True)

    sp = sub.add_parser("init", help="create ~/.a2a/config.json")
    sp.add_argument("--me", required=True)
    sp.add_argument("--port", type=int, default=8765)
    sp.add_argument("--force", action="store_true")

    sub.add_parser("daemon", help="run the receiver")

    sp = sub.add_parser("send", help="start or continue a thread with a peer")
    sp.add_argument("peer")
    sp.add_argument("--message", "-m")
    sp.add_argument("--task", "-t", help="a task request (text is the request)")
    sp.add_argument("--file", "-f", action="append")
    sp.add_argument("--meta", action="append", help="key=value, repeatable")
    sp.add_argument("--thread", help="continue an existing thread")

    sp = sub.add_parser("reply", help="reply to an inbox item (peer/thread inferred)")
    sp.add_argument("id")
    sp.add_argument("--message", "-m", required=True)
    sp.add_argument("--file", "-f", action="append")
    sp.add_argument("--meta", action="append")

    sp = sub.add_parser("result", help="send a task status/result back to its sender")
    sp.add_argument("id", help="the inbox task item id")
    sp.add_argument("--status", required=True, choices=STATUSES)
    sp.add_argument("--message", "-m")
    sp.add_argument("--file", "-f", action="append")
    sp.add_argument("--meta", action="append")

    sp = sub.add_parser("inbox", help="list received items")
    sp.add_argument("--unclaimed", action="store_true")

    sp = sub.add_parser("read", help="show an item (writes files to cwd), claim it for this agent")
    sp.add_argument("id")
    sp.add_argument("--out")
    sp.add_argument("--force", action="store_true", help="read without claiming, even if claimed")

    sp = sub.add_parser("peer", help="manage peers")
    sp.add_argument("action", choices=["add", "list", "remove"])
    sp.add_argument("name", nargs="?")
    sp.add_argument("url", nargs="?")
    sp.add_argument("token", nargs="?")

    sp = sub.add_parser("thread", help="show a whole conversation, both directions")
    sp.add_argument("id")

    sp = sub.add_parser("wait", help="block until a new item arrives")
    sp.add_argument("--timeout", type=int, default=0)

    args = p.parse_args()
    cfg = None if args.cmd == "init" else load_config()
    {"init": cmd_init, "daemon": cmd_daemon, "send": cmd_send, "reply": cmd_reply,
     "result": cmd_result, "inbox": cmd_inbox, "read": cmd_read, "peer": cmd_peer,
     "thread": cmd_thread, "wait": cmd_wait}[args.cmd](cfg, args)


if __name__ == "__main__":
    main()
