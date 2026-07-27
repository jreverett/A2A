# Changelog

Versioning is `0.MAJOR.MINOR` while pre-1.0. `a2a --version` prints the running version.

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
