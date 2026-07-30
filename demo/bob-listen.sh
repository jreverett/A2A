#!/usr/bin/env bash
# Terminal B - bob's side, run under your SECOND Claude account.
# Brings up the loopback peers, then launches a real Claude session as bob.
# Tell that session:  "listen on herald and handle any incoming tasks"
# and leave it running while you record alice.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

ensure_up
export CLAUDE_CONFIG_DIR="$B_CC"
export HERALD_DIR="$B_DIR"
export HERALD_AGENT="bob-desktop"

echo "bob is up (herald on 127.0.0.1:$B_PORT). Launching Claude as bob..."
echo "First run logs this config dir into your SECOND account."
echo "Then tell Claude: listen on herald and handle any incoming tasks"
echo
exec claude
