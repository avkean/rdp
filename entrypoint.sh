#!/bin/bash
set -euo pipefail

NGROK_TOKEN="${NGROK_AUTH_TOKEN:?NGROK_AUTH_TOKEN is required}"
VNC_PASS="${VNC_PASSWORD:?VNC_PASSWORD is required}"
DURATION="${SESSION_HOURS:-2}"

# ── Graceful shutdown ─────────────────────────────────────────────
cleanup() {
    echo "[*] Shutting down..."
    vncserver -kill :1 2>/dev/null || true
    kill $(jobs -p) 2>/dev/null || true
    exit 0
}
trap cleanup SIGTERM SIGINT

# ── Minimal runtime setup ─────────────────────────────────────────
export XDG_RUNTIME_DIR=/tmp/runtime-root
mkdir -p "$XDG_RUNTIME_DIR" && chmod 700 "$XDG_RUNTIME_DIR"
mkdir -p /run/dbus && dbus-daemon --system --fork 2>/dev/null || true

# ── Set KasmVNC password ──────────────────────────────────────────
# Use kasmvncpasswd (the official tool) — piped non-interactively.
# -u: username, -w: write (mouse/keyboard), -o: owner
echo -e "${VNC_PASS}\n${VNC_PASS}\n" | kasmvncpasswd -u user -wo
chmod 600 /root/.kasmpasswd

# ── Ensure KasmVNC prerequisite files exist ───────────────────────
mkdir -p /root/.vnc
[ -f /root/.vnc/xstartup ] || printf '#!/bin/sh\nexec xfce4-session\n' > /root/.vnc/xstartup
chmod +x /root/.vnc/xstartup
touch /root/.vnc/.de-was-selected
touch /root/.Xauthority

# ── Launch KasmVNC ────────────────────────────────────────────────
vncserver :1 \
  -select-de manual \
  -geometry 1920x1080 \
  -depth 24 \
  -websocketPort 6901 \
  -interface 0.0.0.0 \
  -BlacklistThreshold=0 \
  -FreeKeyMappings

echo "[*] KasmVNC started on port 6901"

# ── Launch ngrok tunnel ───────────────────────────────────────────
ngrok config add-authtoken "$NGROK_TOKEN"
ngrok http 6901 --log=stdout > /tmp/ngrok.log 2>&1 &

# ── Wait for ngrok URL (fast polling with jq) ─────────────────────
NGROK_URL=""
for i in $(seq 1 30); do
    NGROK_URL=$(curl -sf http://localhost:4040/api/tunnels 2>/dev/null \
        | jq -r '.tunnels[0].public_url // empty' 2>/dev/null) \
        && [ -n "$NGROK_URL" ] && break
    sleep 0.3
done
[ -z "$NGROK_URL" ] && { echo "[FATAL] ngrok failed to start"; tail -20 /tmp/ngrok.log 2>/dev/null; exit 1; }

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

# Sleep in background so trap can catch SIGTERM
sleep $(( DURATION * 3600 )) &
wait $!
