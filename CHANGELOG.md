# Changelog

Versioning is `0.MAJOR.MINOR` while pre-1.0. `a2a --version` prints the running version.

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
