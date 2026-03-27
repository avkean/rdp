#!/bin/bash
set -euo pipefail

NGROK_TOKEN="${NGROK_AUTH_TOKEN:?NGROK_AUTH_TOKEN is required}"
VNC_PASS="${VNC_PASSWORD:?VNC_PASSWORD is required}"
DURATION="${SESSION_HOURS:-2}"

# ── Minimal runtime setup ──────────────────────────────────────────
export XDG_RUNTIME_DIR=/tmp/runtime-root
mkdir -p "$XDG_RUNTIME_DIR" && chmod 700 "$XDG_RUNTIME_DIR"
mkdir -p /run/dbus && dbus-daemon --system --fork 2>/dev/null || true

# ── Set KasmVNC password ───────────────────────────────────────────
# Write .kasmpasswd directly — kasmvncpasswd requires a TTY which
# doesn't exist in non-interactive Docker containers.
#
# Format: username:hash:permissions  (one per line)
#   - hash is SHA-256 crypt: $5$kasm$<hash> (the exact format KasmVNC uses)
#   - permissions: r=read, w=write, o=owner
#
# KasmVNC validates passwords by calling crypt(input, "$5$kasm$") and
# comparing the result to the stored hash. We use `openssl passwd`
# which is available on Kali (and most Linux) without extra packages.
# This avoids Python's `crypt` module (removed in 3.13).
VNC_PW_HASH=$(openssl passwd -5 -salt kasm "${VNC_PASS}")
echo "user:${VNC_PW_HASH}:ow" > /root/.kasmpasswd
chmod 600 /root/.kasmpasswd

# ── Launch KasmVNC ─────────────────────────────────────────────────
# Single process: VNC server + WebSocket server + web client
# No websockify or noVNC needed — all built into KasmVNC
vncserver :1 -geometry 1920x1080 -depth 24

echo "[*] KasmVNC started on port 6901"

# ── Launch ngrok tunnel ────────────────────────────────────────────
ngrok config add-authtoken "$NGROK_TOKEN"
ngrok http 6901 --log=stdout > /tmp/ngrok.log 2>&1 &

# ── Wait for ngrok URL ─────────────────────────────────────────────
NGROK_URL=""
for i in $(seq 1 15); do
    NGROK_URL=$(curl -sf http://localhost:4040/api/tunnels 2>/dev/null \
        | python3 -c "import sys,json; t=json.load(sys.stdin)['tunnels']; print(t[0]['public_url'])" 2>/dev/null) \
        && break
    sleep 1
done
[ -z "$NGROK_URL" ] && { echo "[FATAL] ngrok failed"; tail -20 /tmp/ngrok.log 2>/dev/null; exit 1; }

echo ""
echo "============================================"
echo "  KALI LINUX - BROWSER ACCESS READY"
echo "============================================"
echo ""
echo "  URL:      ${NGROK_URL}"
echo "  User:     user"
echo "  Password: ${VNC_PASS}"
echo "  Expires:  ${DURATION}h"
echo ""
echo "============================================"

sleep $(( DURATION * 3600 ))
