# a2a — peer-to-peer agent-to-agent messaging

Send messages, files, and task requests directly between two people's agent
sessions (Claude Code, Codex CLI) with no human interface in the loop. Each
machine runs a small receiver daemon; agents send with a one-line CLI call.
Single stdlib-only Python file — no dependencies.

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
a2a send simon --message "the QA refresh is done"
a2a send simon --file ./query-results.csv -m "results you asked for"
a2a send simon --task "run the ImageGen tests on your machine"

a2a inbox --unread          # list what's waiting
a2a read <id>               # show item; files are written to cwd
a2a wait [--timeout N]      # block until something new arrives
```

## Agent integration

Add to your agent instructions (CLAUDE.md / AGENTS.md):

> To send anything to Simon (files, messages, task requests), use
> `a2a send simon ...`. To check for incoming items, `a2a inbox --unread`
> then `a2a read <id>`.

**Push into a live session** (Claude Code): run `a2a wait` as a background
Bash task at the start of a session. When an item arrives the command exits,
the harness re-invokes the agent, and it can read the inbox and act — real
push, no polling. Re-start the wait after each delivery.

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
