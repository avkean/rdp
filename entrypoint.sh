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
# Write .kasmpasswd directly with a crypt(3) SHA-256 hash.
# Format: username:hash:permissions  (ow = owner+write)
# This must exist BEFORE vncserver starts because command_line.prompt
# is false -- if no users exist, vncserver exits immediately with:
#   "No users configured and prompting is prohibited, exiting."
VNC_PW_HASH=$(openssl passwd -5 -salt kasm "${VNC_PASS}")
echo "user:${VNC_PW_HASH}:ow" > /root/.kasmpasswd
chmod 600 /root/.kasmpasswd

# ── Ensure all KasmVNC prerequisite files exist ────────────────────
# These are baked into the image, but verify at runtime in case
# a volume mount or layer change wiped them.
mkdir -p /root/.vnc
[ -f /root/.vnc/xstartup ] || printf '#!/bin/sh\nset -x\nexec xfce4-session\n' > /root/.vnc/xstartup
chmod +x /root/.vnc/xstartup
touch /root/.vnc/.de-was-selected
touch /root/.Xauthority

# ── Launch KasmVNC ─────────────────────────────────────────────────
# -select-de manual: tells vncserver "xstartup is pre-configured,
#   don't run select-de.sh interactive prompt"
# -websocketPort 6901: built-in WebSocket server for browser access
# -interface 0.0.0.0: listen on all interfaces (behind ngrok)
# -BlacklistThreshold=0: disable brute-force lockout (ngrok is ephemeral)
# -FreeKeyMappings: don't remap special keys
vncserver :1 \
  -select-de manual \
  -geometry 1920x1080 \
  -depth 24 \
  -websocketPort 6901 \
  -interface 0.0.0.0 \
  -BlacklistThreshold=0 \
  -FreeKeyMappings

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
