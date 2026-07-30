#!/usr/bin/env bash
# Shared setup for the two-agent demo: two herald identities (alice + bob) on
# one machine over loopback, each with its own Claude config dir (so two
# accounts can run at once) and the herald skill linked in. Sourced by the
# launchers; not run directly.

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEMO_HOME="${HERALD_DEMO_HOME:-$HOME/.herald-demo}"
A_DIR="$DEMO_HOME/alice";  B_DIR="$DEMO_HOME/bob"
A_CC="$DEMO_HOME/claude-alice"; B_CC="$DEMO_HOME/claude-bob"
A_PORT=8765; B_PORT=8766

H() { python3 "$REPO/herald.py" "$@"; }

mkcfg() {  # dir me port peer peerport
  [ -f "$1/config.json" ] && return 0
  mkdir -p "$1"
  HERALD_DIR="$1" python3 "$REPO/herald.py" init --me "$2" --port "$3" >/dev/null
  python3 - "$1/config.json" "$3" "$4" "$5" <<'PY'
import json, sys
f, port, peer, pport = sys.argv[1], int(sys.argv[2]), sys.argv[3], int(sys.argv[4])
d = json.load(open(f))
d["token"] = "DEMO"
d["listen"] = {"host": "127.0.0.1", "port": port}      # loopback: no Tailscale needed
d.setdefault("peers", {})[peer] = {"url": f"http://127.0.0.1:{pport}", "token": "DEMO"}
json.dump(d, open(f, "w"), indent=2)
PY
}

start_daemon() {  # dir port
  local pid="$1/daemon.pid"
  if [ -f "$pid" ] && kill -0 "$(cat "$pid")" 2>/dev/null; then return 0; fi
  HERALD_DIR="$1" nohup python3 "$REPO/herald.py" daemon >"$1/daemon.log" 2>&1 & echo $! >"$pid"
}

link_skill() {  # claude-config-dir
  mkdir -p "$1/skills"
  ln -sfn "$REPO/skill" "$1/skills/herald"
}

ensure_up() {
  mkdir -p "$DEMO_HOME"
  mkcfg "$A_DIR" alice "$A_PORT" bob "$B_PORT"
  mkcfg "$B_DIR" bob "$B_PORT" alice "$A_PORT"
  start_daemon "$A_DIR" "$A_PORT"
  start_daemon "$B_DIR" "$B_PORT"
  link_skill "$A_CC"; link_skill "$B_CC"
  # a herald wrapper on PATH; per-session HERALD_DIR is set by the launchers
  mkdir -p "$HOME/.local/bin"
  printf '#!/bin/bash\nexec python3 "%s/herald.py" "$@"\n' "$REPO" > "$HOME/.local/bin/herald"
  chmod +x "$HOME/.local/bin/herald"
  sleep 1
}

teardown() {
  for p in "$A_DIR/daemon.pid" "$B_DIR/daemon.pid"; do
    [ -f "$p" ] && kill "$(cat "$p")" 2>/dev/null; rm -f "$p"
  done
}

# Clear message/session history so each recording is a clean take - otherwise a
# repeat run looks like a duplicate request and the receiving agent flags it.
fresh_state() {
  for d in "$A_DIR" "$B_DIR"; do
    rm -rf "$d"/inbox "$d"/outbox "$d"/queue "$d"/sessions "$d"/activity "$d"/files "$d"/status.json 2>/dev/null
  done
}
