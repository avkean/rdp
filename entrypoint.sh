#!/bin/bash
set -e

VNC_PASS="${VNC_PASSWORD:-rdp123}"
DURATION="${SESSION_HOURS:-2}"
NGROK_TOKEN="${NGROK_AUTH_TOKEN}"

# Configure VNC
mkdir -p ~/.vnc
echo "$VNC_PASS" | vncpasswd -f > ~/.vnc/passwd
chmod 600 ~/.vnc/passwd

cat > ~/.vnc/xstartup << 'EOF'
#!/bin/bash
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
export XDG_SESSION_TYPE=x11
exec startxfce4
EOF
chmod +x ~/.vnc/xstartup

# Start VNC
vncserver :1 -geometry 1920x1080 -depth 24 -localhost yes
echo "[OK] VNC server started"

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