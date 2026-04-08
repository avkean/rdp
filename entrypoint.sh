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
    # Release the zrok environment so the token can be reused next run
    zrok2 disable 2>/dev/null || true
    exit 0
}
trap cleanup SIGTERM SIGINT EXIT

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
# Clean up any stale environment from a previous run that didn't
# shut down cleanly. This releases the token so enable can succeed.
echo "[*] Disabling any stale zrok environment..."
zrok2 disable 2>/dev/null || true

# enable creates a cryptographic identity for this environment
echo "[*] Enabling zrok (token: ${ZROK_TOKEN:0:8}...)..."
if ! zrok2 enable --headless "$ZROK_TOKEN" 2>&1 | tee /tmp/zrok-enable.log; then
    echo "[FATAL] zrok enable failed:"
    cat /tmp/zrok-enable.log
    exit 1
fi
echo "[*] zrok enabled successfully"

# share public in headless mode (no TUI), logs URL to file
echo "[*] Starting zrok share on port 6901..."
zrok2 share public --headless 6901 > /tmp/zrok.log 2>&1 &
ZROK_PID=$!

# ── Wait for zrok URL ─────────────────────────────────────────────
ZROK_URL=""
for i in $(seq 1 30); do
    # Check if zrok process died
    if ! kill -0 "$ZROK_PID" 2>/dev/null; then
        echo "[FATAL] zrok share exited unexpectedly (attempt $i/30)"
        echo "--- zrok share log ---"
        cat /tmp/zrok.log 2>/dev/null
        exit 1
    fi
    ZROK_HOST=$(grep -oEm1 '[a-z0-9]+\.shares\.zrok\.io' /tmp/zrok.log 2>/dev/null || true)
    if [ -n "$ZROK_HOST" ]; then
        ZROK_URL="https://${ZROK_HOST}"
        break
    fi
    sleep 1
done
if [ -z "$ZROK_URL" ]; then
    echo "[FATAL] zrok share timed out after 30s"
    echo "--- zrok share log ---"
    cat /tmp/zrok.log 2>/dev/null
    echo "--- zrok enable log ---"
    cat /tmp/zrok-enable.log 2>/dev/null
    exit 1
fi

echo ""
echo "============================================"
echo "  KALI LINUX - BROWSER ACCESS READY"
echo "============================================"
echo ""
echo "  URL:      ${ZROK_URL}"
echo "  User:     user"
echo "  Password: ${VNC_PASS}"
DURATION_MINS=$(awk -v dur="$DURATION" 'BEGIN { printf "%g", dur * 60 }')
echo "  Expires:  ${DURATION_MINS}min"
echo ""
echo "============================================"

# Sleep in background so trap can catch SIGTERM
# Use awk for fractional hours (e.g. 0.5 = 30 minutes)
SLEEP_SECS=$(awk -v dur="$DURATION" 'BEGIN { printf "%d", dur * 3600 }')
sleep "$SLEEP_SECS" &
wait $!
