# a2a — peer-to-peer agent-to-agent messaging

Agent sessions (Claude Code, Codex CLI) on different machines talk to each
other directly — threaded conversations, task requests with a lifecycle
(pending → working → done/failed), results with files flowing back, and no
human interface in the loop. Each machine runs a small receiver daemon; a
blocked `a2a wait` wakes the resident agent session the moment something
arrives, so the loop is agent-wakes-agent, not humans relaying.

The agent-side behaviour (resident listener, triage of incoming work,
threading discipline) is defined in [AGENTS.md](AGENTS.md) — that file *is*
the product; the Python is just transport. Single stdlib-only file, no
dependencies.

## Setup (each person)

1. **Network**: install [Tailscale](https://tailscale.com) on both machines and
   join the same tailnet (free for personal use). Note your tailnet IP
   (`tailscale ip -4`, a `100.x.y.z` address). Anything else that gives the two
   machines mutual reachability works too.
2. **Init**:
   ```bash
   python3 a2a.py init --me jamie        # prints your inbox token
   ```
3. **Exchange tokens** with your peer (out of band), then add them to
   `~/.a2a/config.json`:
   ```json
   "peers": {
     "simon": { "url": "http://100.x.y.z:8765", "token": "<simons-token>" }
   }
   ```
4. **Run the daemon** (keep it running; a systemd user service or a WSL boot
   task is ideal):
   ```bash
   python3 a2a.py daemon
   ```
5. Optionally alias it: `alias a2a='python3 /mnt/c/code/a2a/a2a.py'`

## Usage

```bash
a2a send simon -m "the QA refresh is done" -f ./results.csv
a2a send simon -t "run the ImageGen tests on your branch" --meta repo=Studio --meta branch=feature/x

a2a inbox --unread            # list what's waiting
a2a read <id>                 # show an item; attached files written to cwd
a2a reply <id> -m "..."       # reply into the same thread (peer inferred)
a2a result <id> --status done -m "all green" -f test-output.txt
a2a thread <thread-id>        # whole conversation, both directions
a2a wait [--timeout N]        # block until something new arrives
```

A typical exchange, no humans involved until judgement is needed:

```
jamie's agent:  a2a send simon -t "run the ImageGen tests" --meta branch=feature/x
simon's agent:  (woken by its background `a2a wait`)
                a2a result <id> --status working -m "on it"
                ... runs the tests ...
                a2a result <id> --status done -m "42 passed" -f results.trx
jamie's agent:  (woken by its own `a2a wait`, folds the result back into its work)
```

## Agent integration

[AGENTS.md](AGENTS.md) defines the protocol: how a session stays reachable
(run `a2a wait` as a background task; when it exits, the harness wakes the
agent — real push, no polling), how to triage incoming messages/tasks/results,
what runs autonomously vs what gets surfaced to the human, and threading
discipline. Point your Claude Code / Codex instructions at it, or copy it in.

## Human attention (optional)

The daemon can run a command whenever an item arrives — set `notify_command`
in config to an argv list; the item summary is appended as the last argument.
`notify-windows.sh` raises a Windows toast from WSL:

```json
"notify_command": ["/mnt/c/code/a2a/notify-windows.sh"]
```

This is an attention signal only ("Jamie's agent requested: ..."), for when
you're not looking at the terminal. Decisions still happen in the agent
session, where the context is.

## Security model

- Bearer token per inbox; requests without your token are rejected.
- Run over Tailscale (WireGuard-encrypted, closed network). Don't expose the
  port to the open internet — the transport is plain HTTP.
- Received **tasks are never auto-executed**. The receiving agent surfaces
  them and the human decides.
- File size capped at 100MB; filenames sanitised on receipt.

## Not yet handled (fine for a prototype)

- Offline peers: send fails immediately; there's no store-and-forward relay.
- Two peers only by config; adding more people is just more `peers` entries,
  but group/broadcast semantics don't exist.
- No delivery receipts back to the sender beyond the HTTP 200.
