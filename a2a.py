#!/usr/bin/env python3
"""a2a - peer-to-peer agent-to-agent messaging.

Each machine runs `a2a daemon` (reachable over Tailscale). Agents send
messages, files, and task requests with `a2a send`, and receive with
`a2a inbox` / `a2a read`. `a2a wait` blocks until a new item arrives,
so an agent session can run it in the background and get woken on delivery.

Config lives in ~/.a2a/config.json:
{
  "me": "jamie",
  "listen": {"host": "0.0.0.0", "port": 8765},
  "token": "secret-others-need-to-send-to-me",
  "peers": {
    "simon": {"url": "http://simon-machine:8765", "token": "simons-secret"}
  }
}

Stdlib only. No auto-execution of received tasks: the receiving agent
surfaces them and the human decides.
"""

import argparse
import base64
import json
import os
import secrets
import sys
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

A2A_DIR = Path(os.environ.get("A2A_DIR", Path.home() / ".a2a"))
CONFIG_PATH = A2A_DIR / "config.json"
INBOX_DIR = A2A_DIR / "inbox"
FILES_DIR = A2A_DIR / "files"
MAX_FILE_BYTES = 100 * 1024 * 1024


def load_config():
    if not CONFIG_PATH.exists():
        sys.exit(f"No config at {CONFIG_PATH}. Run: a2a init --me NAME")
    return json.loads(CONFIG_PATH.read_text())


def ensure_dirs():
    INBOX_DIR.mkdir(parents=True, exist_ok=True)
    FILES_DIR.mkdir(parents=True, exist_ok=True)


def new_id():
    return time.strftime("%Y%m%d-%H%M%S") + "-" + secrets.token_hex(3)


def sanitize_filename(name):
    name = os.path.basename(name.replace("\\", "/"))
    return name.replace("..", "_") or "unnamed"


# ---------------- daemon (receiver) ----------------

class Handler(BaseHTTPRequestHandler):
    token = None

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
        auth = self.headers.get("Authorization", "")
        if auth != f"Bearer {self.token}":
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
        kind = item.get("kind")
        if kind not in ("message", "file", "task"):
            self._json(400, {"error": "kind must be message|file|task"})
            return

        item_id = new_id()
        stored = {
            "id": item_id,
            "from": str(item.get("from", "unknown"))[:64],
            "kind": kind,
            "text": str(item.get("text", ""))[:100_000],
            "received": time.strftime("%Y-%m-%d %H:%M:%S"),
            "read": False,
        }
        if kind == "file":
            data = item.get("data_b64", "")
            raw = base64.b64decode(data)
            if len(raw) > MAX_FILE_BYTES:
                self._json(413, {"error": "file too large"})
                return
            fname = sanitize_filename(item.get("filename", "unnamed"))
            fpath = FILES_DIR / f"{item_id}_{fname}"
            fpath.write_bytes(raw)
            stored["filename"] = fname
            stored["stored_path"] = str(fpath)
            stored["size"] = len(raw)
        (INBOX_DIR / f"{item_id}.json").write_text(json.dumps(stored, indent=2))
        self._json(200, {"ok": True, "id": item_id})

    def log_message(self, fmt, *args):
        sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))


def cmd_daemon(cfg, args):
    ensure_dirs()
    listen = cfg.get("listen", {})
    host = listen.get("host", "0.0.0.0")
    port = listen.get("port", 8765)
    Handler.token = cfg["token"]
    print(f"a2a daemon: {cfg['me']} listening on {host}:{port}, inbox {INBOX_DIR}")
    ThreadingHTTPServer((host, port), Handler).serve_forever()


# ---------------- sender ----------------

def cmd_send(cfg, args):
    peer = cfg.get("peers", {}).get(args.peer)
    if not peer:
        sys.exit(f"Unknown peer '{args.peer}'. Known: {', '.join(cfg.get('peers', {}))}")
    payload = {"from": cfg["me"]}
    if args.file:
        fpath = Path(args.file)
        if not fpath.is_file():
            sys.exit(f"No such file: {fpath}")
        raw = fpath.read_bytes()
        if len(raw) > MAX_FILE_BYTES:
            sys.exit(f"File exceeds {MAX_FILE_BYTES // (1024*1024)}MB limit")
        payload.update(kind="file", filename=fpath.name,
                       data_b64=base64.b64encode(raw).decode(),
                       text=args.message or "")
    elif args.task:
        payload.update(kind="task", text=args.task)
    elif args.message:
        payload.update(kind="message", text=args.message)
    else:
        sys.exit("Nothing to send: use --message, --file, and/or --task")

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
        sys.exit(f"Send failed: {e}")
    print(f"Delivered to {args.peer} ({payload['kind']}, id {result['id']})")


# ---------------- inbox ----------------

def load_items():
    ensure_dirs()
    items = [json.loads(p.read_text()) for p in sorted(INBOX_DIR.glob("*.json"))]
    return items


def cmd_inbox(cfg, args):
    items = load_items()
    if args.unread:
        items = [i for i in items if not i["read"]]
    if not items:
        print("Inbox empty" if not args.unread else "No unread items")
        return
    for i in items:
        flag = " " if i["read"] else "*"
        extra = f" [{i['filename']}, {i['size']}b]" if i["kind"] == "file" else ""
        preview = i["text"][:80].replace("\n", " ")
        print(f"{flag} {i['id']}  {i['kind']:<7} from {i['from']}  {i['received']}{extra}  {preview}")


def cmd_read(cfg, args):
    path = INBOX_DIR / f"{args.id}.json"
    if not path.exists():
        sys.exit(f"No item {args.id}")
    item = json.loads(path.read_text())
    print(json.dumps({k: v for k, v in item.items() if k != "stored_path"}, indent=2))
    if item["kind"] == "file":
        out = Path(args.out or ".") / item["filename"]
        out.write_bytes(Path(item["stored_path"]).read_bytes())
        print(f"File written to {out.resolve()}")
    item["read"] = True
    path.write_text(json.dumps(item, indent=2))


def cmd_wait(cfg, args):
    ensure_dirs()
    known = {p.name for p in INBOX_DIR.glob("*.json")}
    deadline = time.time() + args.timeout if args.timeout else None
    while True:
        new = {p.name for p in INBOX_DIR.glob("*.json")} - known
        if new:
            for name in sorted(new):
                item = json.loads((INBOX_DIR / name).read_text())
                print(f"NEW {item['kind']} from {item['from']}: id {item['id']}")
            return
        if deadline and time.time() > deadline:
            print("Timed out with no new items")
            sys.exit(2)
        time.sleep(1)


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

    sp = sub.add_parser("send", help="send to a peer")
    sp.add_argument("peer")
    sp.add_argument("--message", "-m")
    sp.add_argument("--file", "-f")
    sp.add_argument("--task", "-t")

    sp = sub.add_parser("inbox", help="list received items")
    sp.add_argument("--unread", action="store_true")

    sp = sub.add_parser("read", help="show an item (writes file to cwd), mark read")
    sp.add_argument("id")
    sp.add_argument("--out")

    sp = sub.add_parser("wait", help="block until a new item arrives")
    sp.add_argument("--timeout", type=int, default=0)

    args = p.parse_args()
    cfg = None if args.cmd == "init" else load_config()
    {"init": cmd_init, "daemon": cmd_daemon, "send": cmd_send,
     "inbox": cmd_inbox, "read": cmd_read, "wait": cmd_wait}[args.cmd](cfg, args)


if __name__ == "__main__":
    main()
