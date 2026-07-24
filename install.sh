#!/bin/bash
# a2a installer for WSL. One command does everything, including Tailscale:
#   curl -fsSL https://raw.githubusercontent.com/jreverett/A2A/master/install.sh | bash -s -- --me simon
# Or from a clone: ./install.sh --me simon
set -e
ME=""; PORT=8765; DIR="$HOME/a2a"; SKIP_NETWORK=""
while [ $# -gt 0 ]; do
  case "$1" in
    --me) ME="$2"; shift 2 ;;
    --port) PORT="$2"; shift 2 ;;
    --dir) DIR="$2"; shift 2 ;;
    --skip-network) SKIP_NETWORK=1; shift ;;
    *) echo "Unknown option $1"; exit 1 ;;
  esac
done
[ -n "$ME" ] || { echo "Usage: install.sh --me <name> [--port 8765] [--dir <clone-dir>] [--skip-network]"; exit 1; }

command -v python3 >/dev/null || { echo "python3 is required"; exit 1; }

# 0. locate or fetch the repo (supports curl | bash)
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
if [ -f "$SELF_DIR/a2a.py" ]; then
  REPO_DIR="$SELF_DIR"
elif [ -f "$DIR/a2a.py" ]; then
  REPO_DIR="$DIR"
else
  echo "Cloning a2a to $DIR"
  git clone -q https://github.com/jreverett/A2A.git "$DIR"
  REPO_DIR="$DIR"
fi

# 0.5 network: Tailscale inside WSL (skippable)
if [ -z "$SKIP_NETWORK" ]; then
  if ! command -v tailscale >/dev/null; then
    echo "Installing Tailscale (needs sudo)..."
    curl -fsSL https://tailscale.com/install.sh | sh
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
    echo "Joining the tailnet - a login link will be printed, open it in your browser:"
    sudo tailscale up
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

TOKEN=$(python3 -c "import json,os;print(json.load(open(os.path.expanduser('~/.a2a/config.json')))['token'])")
IP=$(tailscale ip -4 2>/dev/null | head -1 || true)
echo
echo "Done. Give your peers these two lines:"
echo "  address: http://${IP:-<your-tailnet-ip>}:$PORT"
echo "  token:   $TOKEN"
echo "Add a peer with: a2a peer add <name> <their-address> <their-token>"
