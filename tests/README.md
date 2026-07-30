# Tests

Stdlib `unittest` only — no third-party dependencies, matching herald's design.

```bash
python -m unittest discover -s tests
```

Pure helpers (`sanitize_filename`, `parse_meta`, `new_id`, `agent_name` /
`sender_agent`, `summarise`) run in-process. The protocol is tested end to end by
starting two real daemons on loopback (alice + bob) and driving them through the
CLI, covering: auth rejection, send → inbox → claim, reply auto-targeting back to
the sending session, `--agent` targeting refusal, claim-stealing from a dead
session, queue-on-offline + flush, and the 0.5.0 `ask` / `wait --read` / `ping`.

Each protocol test allocates its own free ports and a temp `HERALD_DIR`, so runs
are isolated and don't touch a real install.
