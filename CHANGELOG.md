# Changelog

Versioning is `0.MAJOR.MINOR` while pre-1.0. `herald --version` prints the running version.

## 0.5.0

- Streamlining to cut latency and token cost, which are dominated by the number
  of LLM round-trips per exchange (see docs/performance.md).
- `herald ask <peer>` sends and blocks for the reply in a single command, so a
  synchronous request/reply is one turn instead of `send` + `wait` + `read`.
  Reachable peers only; an offline peer falls back to the async queue.
- `herald wait --read` prints and claims each item on wake, folding the `read`
  into the same turn.
- `herald ping <peer>` reports whether a peer's daemon is up and its version,
  answered by the daemon itself with no agent woken. The `/ping` endpoint now
  returns version and name.
- Skill guidance: work in as few turns as possible, don't re-verify setup before
  every action, and send a single result for quick tasks.
- Deferred: remote action-handler dispatch (running registered scripts in
  response to a peer's task) is held until the access-control identity and
  sandbox land - it must not ship before its security foundation.

## 0.4.0

- Renamed the project from `a2a` to `herald`. The former name collided with the
  Linux Foundation's Agent2Agent (A2A) protocol, which made the project
  undiscoverable and easy to mistake for that standard. The command is now
  `herald`, the config directory `~/.herald`, the env vars `HERALD_DIR` /
  `HERALD_AGENT`, and the daemon service `herald-daemon`. The installer migrates
  an existing `~/.a2a` install in place: it copies the config aside (token and
  peers preserved), retires the old daemon and command, and removes the legacy
  files only after the new daemon is confirmed running.

## 0.3.4

- Tray "Restart daemon" is now machine-agnostic. It hardcoded one machine's repo
  path (a silent no-op on any other clone) and would spawn a second daemon
  competing for the port on a systemd install rather than restarting the managed
  one. It now restarts the systemd service when present, otherwise falls back to
  the `herald` PATH wrapper the installer creates - no hardcoded paths.

## 0.3.3

- Fix tray cold-boot: the tray resolved the WSL `~/.herald` path only once at
  startup, so when it launched at login before WSL was warm the path stayed
  null and the icon pinned to grey "offline" permanently. Resolution is now
  retried lazily in the poll loop, so a cold-boot tray self-heals as soon as
  WSL answers.
- Fix reply mis-targeting: outbound items now stamp `from_agent` only when
  `HERALD_AGENT` is explicitly set. Previously it defaulted to the hostname, so a
  sender whose listener ran under a different name (the recommended convention)
  had every reply targeted at a session that never listens - held until the
  give-up window, then broadcast with a spurious "reassigned" notice. Unset now
  means broadcast, so replies reach any of the person's listeners immediately.
  To receive targeted replies, send and listen under the same `HERALD_AGENT`.

## 0.3.2

- The installer now sets up the Windows tray indicator automatically on
  WSL-with-Windows (previously a separate manual `setup-tray.ps1` step), so a
  normal install gives you the icon at every login with no extra step.
- `setup-tray.ps1` now installs a hidden VBScript launcher instead of a Startup
  shortcut to `powershell.exe`. A detached/shortcut launch from WSL or a script
  doesn't attach to the interactive desktop and paints its icon invisibly;
  wscript spawns the tray as a child that inherits the visible desktop, so the
  icon appears both at login and immediately on `enable`.

## 0.3.1

- Tray: send/receive arrows now linger ~4s (was 2s) so brief transfers stay
  visible long enough to notice.

## 0.3.0

- Session tracking: each `herald wait` now registers a heartbeat under
  `~/.herald/sessions/`, and a new `herald sessions` command lists the agent sessions
  currently listening. Records are pruned when a session exits or stops
  heartbeating. All file-based - no model tokens.
- Targeted delivery: `send`/`reply`/`result` accept `--agent <name>` to address
  a specific session of a peer. `reply`/`result` default to the originating
  session automatically. `herald wait` only wakes for items addressed to its own
  `HERALD_AGENT` (or broadcast), so N listeners no longer all wake per message.
  `herald inbox --mine` filters to items for this agent or broadcast.
- Claim stealing: `herald read` reclaims an item whose claiming session has died
  (no heartbeat, or its pid is gone on the same machine) instead of refusing.
- Undeliverable-target handling: if a targeted item's session never reappears,
  the daemon (after a give-up window) either releases it to any session and
  informs the sender (`--fallback broadcast`, default), keeps it pinned
  (`--fallback hold`), or bounces an undeliverable notice back
  (`--fallback bounce`). Reaping pauses for a grace period after the host wakes
  from sleep so sessions can re-check in first.

## 0.2.0

- New `herald status` command reports whether the daemon is running, its version,
  address, pid, uptime and queue depth (exits non-zero if down or stale).
- The daemon now maintains `~/.herald/status.json` with a heartbeat every few
  seconds, and touches `~/.herald/activity/{send,recv}` on each outgoing/incoming
  event, so an external monitor (e.g. a Windows tray icon) can show live
  running/sending/receiving state. The heartbeat and background retry now share
  one maintenance thread.
- Added a Windows system-tray app (`tray/`) that visualises this state: the
  "Two Roofs" chevron icon pivots per state (idle/sending/receiving/down),
  theme-aware for light and dark taskbars, with optional login auto-start.

## 0.1.0

- Offline sends are queued and retried instead of dropped. When a peer is
  unreachable, `send`/`reply`/`result` now report "Peer '<name>' is
  unreachable ... queued for retry" and spool the item under `~/.herald/queue/`.
- Queued items deliver on the next successful contact with that peer, are
  retried by the sender's daemon in the background, or can be pushed with the
  new `herald flush [peer]` command.
- Sends the peer actively rejects (bad token/URL) error out and are not queued.
- Added `herald --version` and a version line in the daemon startup banner.
