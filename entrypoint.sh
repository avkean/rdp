#!/bin/bash
set -euo pipefail

NGROK_TOKEN="${NGROK_AUTH_TOKEN:?NGROK_AUTH_TOKEN is required}"
VNC_PASS="${VNC_PASSWORD:?VNC_PASSWORD is required}"
DURATION="${SESSION_HOURS:-2}"

# ── Minimal runtime setup ──────────────────────────────────────────
export XDG_RUNTIME_DIR=/tmp/runtime-root
mkdir -p "$XDG_RUNTIME_DIR" && chmod 700 "$XDG_RUNTIME_DIR"
mkdir -p /run/dbus && dbus-daemon --system --fork 2>/dev/null || true

# Set VNC password (xstartup is pre-baked in image)
echo "$VNC_PASS" | vncpasswd -f > /root/.config/tigervnc/passwd
chmod 600 /root/.config/tigervnc/passwd

# ── Launch everything ──────────────────────────────────────────────
vncserver :1 -geometry 1920x1080 -depth 24 -localhost yes -AlwaysShared
websockify --web /usr/share/novnc 6080 localhost:5901 &
ngrok config add-authtoken "$NGROK_TOKEN"
ngrok http 6080 --log=stdout > /tmp/ngrok.log 2>&1 &

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
echo "  URL:      ${NGROK_URL}/vnc.html"
echo "  Password: ${VNC_PASS}"
echo "  Expires:  ${DURATION}h"
echo ""

sleep $(( DURATION * 3600 ))
