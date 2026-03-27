#!/bin/bash
set -e

VNC_PASS="${VNC_PASSWORD:-rdp123}"
DURATION="${SESSION_HOURS:-2}"
NGROK_TOKEN="${NGROK_AUTH_TOKEN}"

# ── XDG runtime directory (KDE requires this) ─────────────────────
export XDG_RUNTIME_DIR=/tmp/runtime-root
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

# ── Start system D-Bus daemon (KDE components need it) ────────────
mkdir -p /run/dbus
dbus-daemon --system --fork 2>/dev/null || true

# ── Pre-configure KDE settings ────────────────────────────────────
# Disable compositing (no GPU available in VNC)
mkdir -p /root/.config
cat > /root/.config/kwinrc << 'KWINEOF'
[Compositing]
Enabled=false
Backend=XRender
OpenGLIsUnsafe=true
KWINEOF

# ── Configure VNC ─────────────────────────────────────────────────
mkdir -p ~/.vnc
echo "$VNC_PASS" | vncpasswd -f > ~/.vnc/passwd
chmod 600 ~/.vnc/passwd

cat > ~/.vnc/xstartup << 'XEOF'
#!/bin/bash

# XDG environment — KDE uses these to identify the session
export XDG_SESSION_TYPE=x11
export XDG_RUNTIME_DIR=/tmp/runtime-root
export XDG_SESSION_CLASS=user
export XDG_SESSION_DESKTOP=KDE
export XDG_CURRENT_DESKTOP=KDE
export DESKTOP_SESSION=plasma

# Disable KWin compositing for VNC (no GPU)
export KWIN_COMPOSE=N

# Launch KDE Plasma with a D-Bus session bus
# dbus-launch starts the bus, sets DBUS_SESSION_BUS_ADDRESS, then execs plasma
exec dbus-launch --exit-with-session startplasma-x11
XEOF
chmod +x ~/.vnc/xstartup

# Start VNC server
vncserver :1 -geometry 1920x1080 -depth 24 -localhost yes
echo "[OK] VNC server started"

# Give KDE a moment to fully initialize
sleep 3

# Start noVNC
websockify --web /usr/share/novnc 6080 localhost:5901 &
sleep 1
echo "[OK] noVNC started on port 6080"

# Start ngrok
ngrok config add-authtoken "$NGROK_TOKEN"
ngrok http 6080 --log=stdout > /tmp/ngrok.log 2>&1 &
sleep 5

NGROK_URL=$(curl -s http://localhost:4040/api/tunnels | python3 -c "import sys,json; print(json.load(sys.stdin)['tunnels'][0]['public_url'])")

echo "============================================"
echo "  BROWSER RDP READY"
echo "============================================"
echo ""
echo "  ${NGROK_URL}/vnc.html"
echo ""
echo "  Password: ${VNC_PASS}"
echo "  Expires in ${DURATION}h"
echo "============================================"

# Keep alive
sleep $(( DURATION * 3600 ))
