# Changelog

Versioning is `0.MAJOR.MINOR` while pre-1.0. `a2a --version` prints the running version.

## 0.1.0

- Offline sends are queued and retried instead of dropped. When a peer is
  unreachable, `send`/`reply`/`result` now report "Peer '<name>' is
  unreachable ... queued for retry" and spool the item under `~/.a2a/queue/`.
- Queued items deliver on the next successful contact with that peer, are
  retried by the sender's daemon in the background, or can be pushed with the
  new `a2a flush [peer]` command.
- Sends the peer actively rejects (bad token/URL) error out and are not queued.
- Added `a2a --version` and a version line in the daemon startup banner.
