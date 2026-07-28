# Changelog

Versioning is `0.MAJOR.MINOR` while pre-1.0. `a2a --version` prints the running version.

## 0.3.4

- Tray "Restart daemon" is now machine-agnostic. It hardcoded one machine's repo
  path (a silent no-op on any other clone) and would spawn a second daemon
  competing for the port on a systemd install rather than restarting the managed
  one. It now restarts the systemd service when present, otherwise falls back to
  the `a2a` PATH wrapper the installer creates - no hardcoded paths.

## 0.3.3

- Fix tray cold-boot: the tray resolved the WSL `~/.a2a` path only once at
  startup, so when it launched at login before WSL was warm the path stayed
  null and the icon pinned to grey "offline" permanently. Resolution is now
  retried lazily in the poll loop, so a cold-boot tray self-heals as soon as
  WSL answers.
- Fix reply mis-targeting: outbound items now stamp `from_agent` only when
  `A2A_AGENT` is explicitly set. Previously it defaulted to the hostname, so a
  sender whose listener ran under a different name (the recommended convention)
  had every reply targeted at a session that never listens - held until the
  give-up window, then broadcast with a spurious "reassigned" notice. Unset now
  means broadcast, so replies reach any of the person's listeners immediately.
  To receive targeted replies, send and listen under the same `A2A_AGENT`.

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

- Session tracking: each `a2a wait` now registers a heartbeat under
  `~/.a2a/sessions/`, and a new `a2a sessions` command lists the agent sessions
  currently listening. Records are pruned when a session exits or stops
  heartbeating. All file-based - no model tokens.
- Targeted delivery: `send`/`reply`/`result` accept `--agent <name>` to address
  a specific session of a peer. `reply`/`result` default to the originating
  session automatically. `a2a wait` only wakes for items addressed to its own
  `A2A_AGENT` (or broadcast), so N listeners no longer all wake per message.
  `a2a inbox --mine` filters to items for this agent or broadcast.
- Claim stealing: `a2a read` reclaims an item whose claiming session has died
  (no heartbeat, or its pid is gone on the same machine) instead of refusing.
- Undeliverable-target handling: if a targeted item's session never reappears,
  the daemon (after a give-up window) either releases it to any session and
  informs the sender (`--fallback broadcast`, default), keeps it pinned
  (`--fallback hold`), or bounces an undeliverable notice back
  (`--fallback bounce`). Reaping pauses for a grace period after the host wakes
  from sleep so sessions can re-check in first.

## 0.2.0

- New `a2a status` command reports whether the daemon is running, its version,
  address, pid, uptime and queue depth (exits non-zero if down or stale).
- The daemon now maintains `~/.a2a/status.json` with a heartbeat every few
  seconds, and touches `~/.a2a/activity/{send,recv}` on each outgoing/incoming
  event, so an external monitor (e.g. a Windows tray icon) can show live
  running/sending/receiving state. The heartbeat and background retry now share
  one maintenance thread.
- Added a Windows system-tray app (`tray/`) that visualises this state: the
  "Two Roofs" chevron icon pivots per state (idle/sending/receiving/down),
  theme-aware for light and dark taskbars, with optional login auto-start.

## 0.1.0

- Offline sends are queued and retried instead of dropped. When a peer is
  unreachable, `send`/`reply`/`result` now report "Peer '<name>' is
  unreachable ... queued for retry" and spool the item under `~/.a2a/queue/`.
- Queued items deliver on the next successful contact with that peer, are
  retried by the sender's daemon in the background, or can be pushed with the
  new `a2a flush [peer]` command.
- Sends the peer actively rejects (bad token/URL) error out and are not queued.
- Added `a2a --version` and a version line in the daemon startup banner.
