#!/bin/bash
set -euo pipefail

# ── Validate required inputs ────────────────────────────────────────
NGROK_TOKEN="${NGROK_AUTH_TOKEN:?NGROK_AUTH_TOKEN is required}"
VNC_PASS="${VNC_PASSWORD:?VNC_PASSWORD is required}"
DURATION="${SESSION_HOURS:-2}"

echo "[*] Starting Kali Desktop session (${DURATION}h)..."

# ── XDG runtime directory ──────────────────────────────────────────
export XDG_RUNTIME_DIR=/tmp/runtime-root
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

# ── Start system D-Bus ──────────────────────────────────────────────
mkdir -p /run/dbus
dbus-daemon --system --fork 2>/dev/null || true

# ── Configure VNC ───────────────────────────────────────────────────
mkdir -p ~/.vnc
echo "$VNC_PASS" | vncpasswd -f > ~/.vnc/passwd
chmod 600 ~/.vnc/passwd

cat > ~/.vnc/xstartup << 'XEOF'
#!/bin/bash
# Clear stale session variables — required for XFCE under VNC
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
export XKL_XMODMAP_DISABLE=1
exec startxfce4
XEOF
chmod +x ~/.vnc/xstartup

# ── Start VNC server ────────────────────────────────────────────────
vncserver :1 \
    -geometry 1920x1080 \
    -depth 24 \
    -localhost yes \
    -AlwaysShared

# Verify VNC is running
for i in 1 2 3 4 5; do
    [ -e /tmp/.X1-lock ] && break
    sleep 1
done
if [ ! -e /tmp/.X1-lock ]; then
    echo "[FATAL] VNC server failed to start"
    cat ~/.vnc/*.log 2>/dev/null || true
    exit 1
fi
echo "[OK] VNC server running on :1"

# ── Start noVNC ─────────────────────────────────────────────────────
websockify --web /usr/share/novnc 6080 localhost:5901 &
NOVNC_PID=$!
sleep 1
if ! kill -0 "$NOVNC_PID" 2>/dev/null; then
    echo "[FATAL] noVNC failed to start"
    exit 1
fi
echo "[OK] noVNC listening on :6080"

# ── Start ngrok tunnel ──────────────────────────────────────────────
ngrok config add-authtoken "$NGROK_TOKEN"
ngrok http 6080 --log=stdout > /tmp/ngrok.log 2>&1 &

# Wait for ngrok API with retry
NGROK_URL=""
for i in $(seq 1 15); do
    NGROK_URL=$(curl -sf http://localhost:4040/api/tunnels 2>/dev/null \
        | python3 -c "import sys,json; t=json.load(sys.stdin)['tunnels']; print(t[0]['public_url'])" 2>/dev/null) \
        && break
    sleep 2
done

if [ -z "$NGROK_URL" ]; then
    echo "[FATAL] ngrok tunnel failed after 30s"
    echo "        Check NGROK_AUTH_TOKEN — log at /tmp/ngrok.log"
    cat /tmp/ngrok.log 2>/dev/null | tail -20
    exit 1
fi

# ── Ready ───────────────────────────────────────────────────────────
cat << EOF

============================================
  KALI LINUX — BROWSER ACCESS READY
============================================

  URL:      ${NGROK_URL}/vnc.html
  Password: ${VNC_PASS}
  Expires:  ${DURATION}h
  Tools:    kali-tools-top10

============================================

EOF

# Keep container alive for session duration
sleep $(( DURATION * 3600 ))
