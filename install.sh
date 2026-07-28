#!/bin/bash
# a2a installer for WSL. One command does everything, including Tailscale:
#   curl -fsSL https://raw.githubusercontent.com/jreverett/A2A/master/install.sh | bash -s -- --me alice
# Or from a clone: ./install.sh --me alice
set -e
ME=""; PORT=8765; DIR="$HOME/a2a"; SKIP_NETWORK=""; AUTH_KEY=""
PEER_NAME=""; PEER_URL=""; PEER_TOKEN=""
while [ $# -gt 0 ]; do
  case "$1" in
    --me) ME="$2"; shift 2 ;;
    --port) PORT="$2"; shift 2 ;;
    --dir) DIR="$2"; shift 2 ;;
    --auth-key) AUTH_KEY="$2"; shift 2 ;;
    --peer) PEER_NAME="$2"; shift 2 ;;
    --peer-url) PEER_URL="$2"; shift 2 ;;
    --peer-token) PEER_TOKEN="$2"; shift 2 ;;
    --skip-network) SKIP_NETWORK=1; shift ;;
    *) echo "Unknown option $1"; exit 1 ;;
  esac
done
[ -n "$ME" ] || { echo "Usage: install.sh --me <name> [--auth-key tskey-...] [--peer <name> --peer-url <url> --peer-token <token>] [--port 8765] [--dir <clone-dir>] [--skip-network]"; exit 1; }

command -v python3 >/dev/null || { echo "python3 is required"; exit 1; }

banner() {
  echo
  echo "  +--------------------------------------------------------------------+"
  printf '  | %-66s |\n' "$@"
  echo "  +--------------------------------------------------------------------+"
}

TTY=""; [ -t 1 ] && TTY=1
STEP_LOG="${TMPDIR:-/tmp}/a2a-install-step.log"

# spin "label" cmd...  - animated spinner on a TTY, plain line otherwise
spin() {
  local label="$1"; shift
  if [ -z "$TTY" ]; then
    echo "  $label..."
    "$@"
    return
  fi
  "$@" >"$STEP_LOG" 2>&1 &
  local pid=$! frames='|/-\' i=0
  while kill -0 "$pid" 2>/dev/null; do
    i=$(( (i+1) % 4 ))
    printf '\r  [%s] %s ' "${frames:$i:1}" "$label"
    sleep 0.15
  done
  local rc=0; wait "$pid" || rc=$?
  if [ "$rc" -eq 0 ]; then
    printf '\r  [ok] %s\n' "$label"
  else
    printf '\r  [!!] %s failed:\n' "$label"
    cat "$STEP_LOG"
  fi
  return "$rc"
}

banner "a2a setup - agent-to-agent messaging" \
       "" \
       "This installer will:" \
       "  1. Install Tailscale (private mesh VPN) and join your tailnet" \
       "  2. Write ~/.a2a/config.json and put 'a2a' on your PATH" \
       "  3. Teach your agents the a2a protocol (skill / instructions)" \
       "  4. Start the a2a receiver daemon" \
       "  5. (On Windows) Add a system-tray status icon" \
       "" \
       "Security - nothing is exposed outside your private network:" \
       "  - The daemon binds ONLY to the Tailscale interface. No port is" \
       "    opened on your LAN, office network, or the internet." \
       "  - All traffic is WireGuard-encrypted, device-to-device." \
       "  - Senders must present your inbox token; strangers are rejected." \
       "  - Incoming tasks are never auto-executed by your agents."

# 0. locate or fetch the repo (supports curl | bash)
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
if [ -f "$SELF_DIR/a2a.py" ]; then
  REPO_DIR="$SELF_DIR"
elif [ -f "$DIR/a2a.py" ]; then
  REPO_DIR="$DIR"
else
  spin "Fetching a2a" git clone -q https://github.com/jreverett/A2A.git "$DIR"
  REPO_DIR="$DIR"
fi

# 0.5 network: Tailscale inside WSL (skippable)
if [ -z "$SKIP_NETWORK" ]; then
  if ! command -v tailscale >/dev/null; then
    banner "PROMPT COMING UP: your sudo password" \
           "" \
           "Why: installing Tailscale, the private VPN a2a runs over." \
           "It creates an encrypted device-to-device network; a2a will only" \
           "ever listen inside it, so no port is opened to your LAN or the" \
           "internet."
    sudo -v
    spin "Installing Tailscale" sh -c 'curl -fsSL https://tailscale.com/install.sh | sh'
  fi
  if ! pgrep -x tailscaled >/dev/null; then
    if command -v systemctl >/dev/null && systemctl is-system-running >/dev/null 2>&1; then
      sudo systemctl enable --now tailscaled
    else
      echo "Starting tailscaled (no systemd)..."
      sudo nohup tailscaled >/var/tmp/tailscaled.log 2>&1 &
      sleep 2
    fi
  fi
  if [ -z "$(tailscale ip -4 2>/dev/null)" ]; then
    if [ -n "$AUTH_KEY" ]; then
      banner "Joining the shared private network" \
             "" \
             "Using the auth key you were given - no account or sign-up" \
             "needed. Your machine joins your peer's tailnet so their a2a" \
             "daemon can reach yours; traffic stays inside the encrypted" \
             "mesh."
      sudo -v
      spin "Joining the private network" sudo tailscale up --auth-key "$AUTH_KEY"
    else
      banner "PROMPT COMING UP: Tailscale login link" \
             "" \
             "Why: this authenticates your machine into the shared tailnet so" \
             "your peer's machine can reach your a2a inbox (and only that -" \
             "traffic stays inside the encrypted mesh). Open the printed link" \
             "in your browser and sign in." \
             "" \
             "(No account? Ask your peer for an auth key and rerun with" \
             " --auth-key tskey-... to skip sign-in entirely.)"
      sudo tailscale up
    fi
  fi
fi

# 1. config + inbox
if [ -f "$HOME/.a2a/config.json" ]; then
  echo "~/.a2a/config.json already exists, keeping it"
else
  python3 "$REPO_DIR/a2a.py" init --me "$ME" --port "$PORT"
fi

# 2. a2a on PATH
mkdir -p "$HOME/.local/bin"
printf '#!/bin/bash\nexec python3 "%s/a2a.py" "$@"\n' "$REPO_DIR" > "$HOME/.local/bin/a2a"
chmod +x "$HOME/.local/bin/a2a"
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *)
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
  echo "Added ~/.local/bin to PATH in ~/.bashrc (open a new shell)" ;;
esac

# 3. agent skill/instructions
if [ -d "$HOME/.claude" ]; then
  mkdir -p "$HOME/.claude/skills"
  ln -sfn "$REPO_DIR/skill" "$HOME/.claude/skills/a2a"
  echo "Claude Code skill installed (~/.claude/skills/a2a)"
fi
for f in "$HOME/.codex/AGENTS.md" "$HOME/.copilot/copilot-instructions.md"; do
  if [ -f "$f" ] && ! grep -q "a2a agent protocol pointer" "$f"; then
    printf '\n# a2a agent protocol pointer\nFor messaging other people'"'"'s agents (a2a), follow %s/skill/SKILL.md\n' "$REPO_DIR" >> "$f"
    echo "Added a2a pointer to $f"
  fi
done

# 4. daemon as a systemd user service (falls back to instructions if no systemd)
if command -v systemctl >/dev/null && systemctl --user show-environment >/dev/null 2>&1; then
  mkdir -p "$HOME/.config/systemd/user"
  cat > "$HOME/.config/systemd/user/a2a-daemon.service" <<EOF
[Unit]
Description=a2a receiver daemon
[Service]
ExecStart=/usr/bin/python3 $REPO_DIR/a2a.py daemon
Restart=on-failure
[Install]
WantedBy=default.target
EOF
  systemctl --user daemon-reload
  if systemctl --user enable --now a2a-daemon.service 2>/dev/null; then
    echo "Daemon running (systemd user service a2a-daemon)"
  else
    echo "Could not start the systemd service; start the daemon manually:"
    echo "  nohup a2a daemon >~/.a2a/daemon.log 2>&1 &"
  fi
else
  echo "No systemd; start the daemon manually: nohup a2a daemon >~/.a2a/daemon.log 2>&1 &"
fi

# 4.5 Windows tray indicator (only on WSL-with-Windows; skipped cleanly elsewhere)
if grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null && command -v powershell.exe >/dev/null 2>&1; then
  TRAY_SETUP_WIN=$(wslpath -w "$REPO_DIR/tray/setup-tray.ps1" 2>/dev/null || true)
  if [ -n "$TRAY_SETUP_WIN" ]; then
    spin "Adding Windows tray indicator" \
      powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$TRAY_SETUP_WIN" enable || true
    echo "  Tray icon starts at login (and now, if a desktop is available)."
  fi
fi

# 5. connect to a peer and introduce myself (their side runs `a2a accept`)
if [ -n "$PEER_NAME" ]; then
  if [ -n "$PEER_URL" ] && [ -n "$PEER_TOKEN" ]; then
    python3 "$REPO_DIR/a2a.py" peer add "$PEER_NAME" "$PEER_URL" "$PEER_TOKEN"
    if spin "Connecting to $PEER_NAME" python3 "$REPO_DIR/a2a.py" introduce "$PEER_NAME"; then
      banner "Introduced yourself to $PEER_NAME" \
             "" \
             "  you ---------------> $PEER_NAME     delivered" \
             "  you <--------------- $PEER_NAME     once they run: a2a accept" \
             "" \
             "Their agent will accept and confirm; then you're connected" \
             "both ways."
    fi
  else
    echo "--peer needs --peer-url and --peer-token too; skipping connect"
  fi
fi

TOKEN=$(python3 -c "import json,os;print(json.load(open(os.path.expanduser('~/.a2a/config.json')))['token'])")
IP=$(tailscale ip -4 2>/dev/null | head -1 || true)
echo
echo "Done. Your details, should a peer need to add you manually:"
echo "  address: http://${IP:-<your-tailnet-ip>}:$PORT"
echo "  token:   $TOKEN"
echo "Connect to someone: a2a peer add <name> <their-address> <their-token> && a2a introduce <name>"
