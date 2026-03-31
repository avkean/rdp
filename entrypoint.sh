#!/bin/bash
set -euo pipefail

ZROK_TOKEN="${ZROK_ENABLE_TOKEN:?ZROK_ENABLE_TOKEN is required}"
VNC_PASS="${VNC_PASSWORD:-abc123}"
DURATION="${SESSION_HOURS:-1}"

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

# ── Launch zrok tunnel ────────────────────────────────────────────
# enable creates a cryptographic identity for this environment
zrok2 enable --headless "$ZROK_TOKEN"
# share public in headless mode (no TUI), logs URL to file
zrok2 share public --headless 6901 > /tmp/zrok.log 2>&1 &

# ── Wait for zrok URL ─────────────────────────────────────────────
# Note: grep returns 1 on no match, which would kill the script
# under set -e. The "|| true" prevents that.
ZROK_URL=""
for i in $(seq 1 30); do
    ZROK_HOST=$(grep -oEm1 '[a-z0-9]+\.shares\.zrok\.io' /tmp/zrok.log 2>/dev/null || true)
    if [ -n "$ZROK_HOST" ]; then
        ZROK_URL="https://${ZROK_HOST}"
        break
    fi
    sleep 0.5
done
[ -z "$ZROK_URL" ] && { echo "[FATAL] zrok failed to start"; cat /tmp/zrok.log 2>/dev/null; exit 1; }

echo ""
echo "============================================"
echo "  KALI LINUX - BROWSER ACCESS READY"
echo "============================================"
echo ""
echo "  URL:      ${ZROK_URL}"
echo "  User:     user"
echo "  Password: ${VNC_PASS}"
DURATION_MINS=$(awk "BEGIN { printf \"%g\", $DURATION * 60 }")
echo "  Expires:  ${DURATION_MINS}min"
echo ""
echo "============================================"

# Sleep in background so trap can catch SIGTERM
# Use awk for fractional hours (e.g. 0.5 = 30 minutes)
SLEEP_SECS=$(awk "BEGIN { printf \"%d\", $DURATION * 3600 }")
sleep "$SLEEP_SECS" &
wait $!
