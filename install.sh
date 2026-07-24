#!/bin/bash
# a2a installer for WSL. Usage: ./install.sh --me <name> [--port 8765]
set -e
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
ME=""; PORT=8765
while [ $# -gt 0 ]; do
  case "$1" in
    --me) ME="$2"; shift 2 ;;
    --port) PORT="$2"; shift 2 ;;
    *) echo "Unknown option $1"; exit 1 ;;
  esac
done
[ -n "$ME" ] || { echo "Usage: ./install.sh --me <name> [--port 8765]"; exit 1; }

command -v python3 >/dev/null || { echo "python3 is required"; exit 1; }

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
  systemctl --user enable --now a2a-daemon.service
  echo "Daemon running (systemd user service a2a-daemon)"
else
  echo "No systemd; start the daemon manually: nohup a2a daemon >~/.a2a/daemon.log 2>&1 &"
fi

# 5. network
if command -v tailscale >/dev/null; then
  IP=$(tailscale ip -4 2>/dev/null | head -1 || true)
  echo "Tailscale IP: ${IP:-not connected - run: sudo tailscale up}"
else
  cat <<'EOF'
Tailscale not installed in WSL. Install and join the tailnet:
  curl -fsSL https://tailscale.com/install.sh | sh
  sudo tailscale up
Then your address for peers is: http://$(tailscale ip -4):PORT
EOF
fi

TOKEN=$(python3 -c "import json,os;print(json.load(open(os.path.expanduser('~/.a2a/config.json')))['token'])")
echo
echo "Done. Your inbox token (give to peers): $TOKEN"
echo "Add a peer with: a2a peer add <name> http://<their-tailnet-ip>:8765 <their-token>"
