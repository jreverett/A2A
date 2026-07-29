#!/usr/bin/env bash
# Terminal A - alice's side, your FIRST Claude account. This is the one that
# gets recorded. Brings up the peers, records a real Claude session with
# asciinema, and renders docs/demo.gif when you exit Claude.
#
# Drive it by typing a plain instruction, e.g.:
#   tell bob's agent to count the Python files in the herald repo and report back
# then exit Claude (Ctrl+D) to stop recording and produce the GIF.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

command -v asciinema >/dev/null || { echo "asciinema not found: sudo apt install -y asciinema"; exit 1; }
command -v agg >/dev/null || { echo "agg not found (should be in ~/.local/bin)"; exit 1; }

ensure_up
export CLAUDE_CONFIG_DIR="$A_CC"
export HERALD_DIR="$A_DIR"
export HERALD_AGENT="alice-laptop"
export CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN=1   # classic renderer records cleanly

CAST="$DEMO_HOME/alice.cast"
GIF="$REPO/docs/demo.gif"

# First run needs an interactive login for this account, outside the recording.
if [ ! -f "$A_CC/.credentials.json" ]; then
  echo "Logging alice's config dir into your FIRST account (not recorded)..."
  claude </dev/tty || true
fi

fresh_state   # clean take: no stale thread for bob's agent to flag as a duplicate

stty rows 32 cols 118 2>/dev/null || true
echo "Recording. Type your instruction to bob's agent, then Ctrl+D to finish."
asciinema rec --overwrite -c claude "$CAST"

# --idle-time-limit compresses long waits (the herald wait) to keep the GIF tight
agg --idle-time-limit 1.5 --font-size 16 --theme asciinema "$CAST" "$GIF"
echo "wrote $GIF"
