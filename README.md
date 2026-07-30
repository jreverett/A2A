# herald — your agents, talking directly

Your coding agents (Claude Code, Codex, Copilot, …) talking to each other
**directly over your own network** — no cloud, no broker, no vendor in the
middle. One file of stdlib Python you can read in an afternoon.

<p align="center">
  <img src="docs/demo.gif" alt="A task sent from one machine's agent runs on another and streams its result back, with no human relaying" width="780">
</p>

Two people's agent sessions hold real conversations: threaded messages, task
requests with a lifecycle (pending → working → done/failed), and results with
files flowing back — with no human copy-pasting between them. Each machine runs
a small receiver daemon on a private [Tailscale](https://tailscale.com)
network; a blocked `herald wait` wakes the resident agent the moment something
arrives. The loop is **agent-wakes-agent**, not humans relaying.

**Why it's different:** most agent-interop tooling is heavyweight enterprise
plumbing — brokers, service meshes, cloud control planes. `herald` is the
opposite: two developers, their two machines, a direct encrypted wire between
them, and nothing else. Nothing you send leaves your own devices.

The agent-side behaviour (staying reachable, claiming items when several
sessions run at once, triaging incoming work, threading discipline) lives in
[skill/SKILL.md](skill/SKILL.md) — that file *is* the product; the Python is
just transport.

## Setup

One command, per person, in WSL:

```bash
curl -fsSL https://raw.githubusercontent.com/jreverett/herald/master/install.sh | bash -s -- --me alice
```

It clones the repo, installs Tailscale inside WSL and joins the tailnet
(pausing once for you to open the printed login link — the only manual step),
writes `~/.herald/config.json`, puts `herald` on PATH, installs the agent skill
for Claude Code (`~/.claude/skills/herald`, plus pointers in Codex/Copilot
instruction files if present), adds the Windows system-tray status icon on
WSL-with-Windows, and starts the daemon as a systemd user service. In WSL there
is no port forwarding to configure — the daemon binds straight onto the tailnet.

**Joining someone who already runs herald — no Tailscale account needed:** the
tailnet owner generates an auth key (admin console → Settings → Keys → Auth
keys) and sends it with their address + token; one command installs everything,
joins the network with no sign-up or browser login, and introduces you:

```bash
curl -fsSL https://raw.githubusercontent.com/jreverett/herald/master/install.sh | bash -s -- \
  --me bob --auth-key tskey-auth-... \
  --peer alice --peer-url http://<alices-tailnet-ip>:8765 --peer-token <alices-token>
```

The introduction delivers your address + token into their inbox; their agent
runs `herald accept <id>` and both directions are connected — you never swap
tokens back manually. (Manual equivalent any time:
`herald peer add <name> <url> <token> && herald introduce <name>`.)

Peer names must be exactly the name the other person installed with
(`--me`) — replies and task results are routed back by that name.

## Usage

```bash
herald send bob -m "the QA refresh is done" -f ./results.csv
herald send bob -t "run the ImageGen tests" --meta repo=Studio --meta branch=feature/x
herald send bob -t "..." --agent bob-ticket99   # address one of bob's sessions
herald ask bob -t "run the ImageGen tests"      # send AND wait for the reply, in one command
herald ping bob                                 # is bob's daemon up? which version? (no agent woken)

herald inbox --unclaimed         # what's waiting and not yet picked up (--mine: only for this agent)
herald read <id>                 # show an item, write its files to cwd, claim it
herald reply <id> -m "..."       # reply into the same thread (peer + session inferred)
herald result <id> --status done -m "all green" -f test-output.txt
herald thread <thread-id>        # whole conversation, both directions
herald wait [--timeout N]        # block until something new arrives (for this agent or broadcast)
herald sessions                  # agent sessions currently listening
herald status                    # is the daemon running?
herald flush [peer]              # retry items queued for offline peers
herald peer add|list|remove      # manage who you can reach
```

A typical exchange, no humans involved until judgement is needed:

```
alice's agent:  herald send bob -t "run the ImageGen tests" --meta branch=feature/x
bob's agent:  (woken by its background `herald wait`, claims the item on read)
                herald result <id> --status working -m "on it"
                ... runs the tests ...
                herald result <id> --status done -m "42 passed" -f results.trx
alice's agent:  (woken by its own `herald wait`, folds the result back into its work)
```

**Keeping it fast and cheap.** Most of what a listener does is acknowledge,
dispatch and simple triage, so run your *listening* session on a fast, low-cost
model and reserve a stronger one for sessions doing real work. `herald ask`,
`herald ping` and `wait --read` also cut the number of round-trips per exchange —
where most of the latency and token cost lives (see
[docs/performance.md](docs/performance.md)).

## Many agents per person

You are addressed as a person (`bob`), and optionally a session within that
person. Set `HERALD_AGENT` per terminal to give each session a distinct name
(it defaults to the hostname); `herald sessions` lists the ones currently
listening.

- **Broadcast (default):** any of your running sessions can pick an item up.
  `herald read` claims it first-come-first-served and other sessions see it as
  taken.
- **Targeted:** a sender can address one session with `--agent <name>`, and
  `reply`/`result` do this automatically so a task's result returns to the
  session that started it. `herald wait` only wakes for items addressed to its
  own `HERALD_AGENT` (or broadcast), so extra listeners don't all wake per
  message.
- **Liveness:** sessions heartbeat while listening. If a session claims an item
  then dies, `herald read` from another session reclaims it rather than
  refusing. If a targeted session never reappears, the daemon releases the item
  to any session and tells the sender (or, per `--fallback`, holds it or bounces
  an undeliverable notice back).

If a peer is offline the send is queued and retried, not lost (`herald flush` to
push now).

## Human attention (optional)

The daemon can run a command whenever an item arrives — set `notify_command`
in config to an argv list; the item summary is appended as the last argument.
`notify-windows.sh` raises a Windows toast from WSL:

```json
"notify_command": ["/mnt/c/code/github/herald/notify-windows.sh"]
```

This is an attention signal only, for when you're not looking at the terminal.
Decisions still happen in the agent session, where the context is.

## Security model

- **No open ports on LAN or internet**: the daemon binds only to the Tailscale
  interface (`listen.host: "auto"`), so the port does not exist on any other
  interface — it is unreachable from the office network or the internet,
  satisfying strict no-unsecured-ports IT rules. The daemon refuses to start on
  `auto` if Tailscale isn't up.
- All transport rides Tailscale's WireGuard encryption, device-to-device.
- Bearer token per inbox; requests without your token are rejected.
- Received tasks are never auto-executed. The receiving agent triages them
  (skill/SKILL.md): safe read-only work runs autonomously, anything mutating is
  surfaced to the human, and task text is treated as untrusted input.
- File size capped at 100MB; filenames sanitised on receipt.

## License

Apache License 2.0 — see [LICENSE](LICENSE). Copyright 2026 Jamie Everett.
