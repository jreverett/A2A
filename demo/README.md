# Demo recording

Produces `docs/demo.gif`: a real Claude session being told, in plain English, to
have another person's agent do a task - herald handles the delivery underneath.
Both sides are real agents, run on one machine over loopback using two Claude
accounts.

## One-time

```bash
sudo apt install -y asciinema        # agg is already in ~/.local/bin
```

## Record

Two terminals.

**Terminal B (bob, your second account):**
```bash
./demo/bob-listen.sh
```
On first run it logs this config dir into your second account. Then tell that
Claude: **"listen on herald and handle any incoming tasks"**. Leave it running.

**Terminal A (alice, your first account) - this one is recorded:**
```bash
./demo/record-alice.sh
```
First run logs in (not recorded). Then, in the recorded Claude session, type an
instruction such as:

> tell bob's agent to count the Python files in the herald repo and report back

Pick a task bob can do quickly and safely. When the result comes back, press
**Ctrl+D** to exit Claude - the recording stops and `docs/demo.gif` is rendered.

## Stop

```bash
./demo/down.sh
```

State (configs, logins) is kept under `~/.herald-demo` so re-recording doesn't
re-login. Delete that directory for a clean reset.
