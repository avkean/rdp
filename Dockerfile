FROM kalilinux/kali-rolling

ENV DEBIAN_FRONTEND=noninteractive

# ── Layer 1: Full Kali XFCE desktop + KasmVNC + utilities + ngrok ──
# KasmVNC replaces tigervnc + novnc + websockify with a single binary.
# Built-in WebSocket server, web client, WebP encoding, content-aware
# updates → ~2x better responsiveness than traditional VNC+noVNC.
RUN apt-get update && apt-get install -y \
    kali-desktop-xfce \
    dbus dbus-x11 \
    wget curl nano sudo less openssh-client \
    net-tools iproute2 iputils-ping dnsutils traceroute \
    htop lsof zip unzip file \
    ca-certificates locales python3 \
    # KasmVNC: single .deb replaces tigervnc + novnc + websockify
    && wget -q https://github.com/kasmtech/KasmVNC/releases/download/v1.4.0/kasmvncserver_kali-rolling_1.4.0_amd64.deb \
       -O /tmp/kasmvnc.deb \
    && apt-get install -y /tmp/kasmvnc.deb \
    && rm /tmp/kasmvnc.deb \
    # ngrok tunnel
    && curl -sSL https://ngrok-agent.s3.amazonaws.com/ngrok.asc \
       | tee /etc/apt/trusted.gpg.d/ngrok.asc >/dev/null \
    && echo "deb https://ngrok-agent.s3.amazonaws.com buster main" \
       | tee /etc/apt/sources.list.d/ngrok.list \
    && apt-get update && apt-get install -y ngrok \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* \
              /usr/share/doc/* /usr/share/man/* /usr/share/info/*

# ── Layer 2: Pentesting tools (separate for independent cache) ──────
RUN apt-get update && apt-get install -y --no-install-recommends \
    kali-tools-top10 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* \
              /usr/share/doc/* /usr/share/man/* /usr/share/info/*

# ── Locale ──────────────────────────────────────────────────────────
RUN sed -i 's/# en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

# ── Pre-bake KasmVNC config ─────────────────────────────────────────
# KasmVNC has THREE interactive prompts that fail without a TTY:
#   1. DE selection (select-de.sh) -- bypassed by .de-was-selected sentinel + xstartup
#   2. User creation wizard -- bypassed by command_line.prompt: false + pre-created .kasmpasswd
#   3. xstartup overwrite confirmation -- bypassed by pre-creating xstartup + .de-was-selected
#
# xstartup: tells KasmVNC how to launch the desktop environment
# .de-was-selected: sentinel file that skips the DE selection prompt entirely
# .Xauthority: pre-created to suppress "file does not exist" warning (not fatal, but noisy)
RUN mkdir -p /root/.vnc \
    && printf '#!/bin/sh\nset -x\nexec xfce4-session\n' > /root/.vnc/xstartup \
    && chmod +x /root/.vnc/xstartup \
    && touch /root/.vnc/.de-was-selected \
    && touch /root/.Xauthority

# KasmVNC YAML config:
#   command_line.prompt: false -- CRITICAL: disables all interactive prompts
#     (user creation, DE selection fallback). Without this, vncserver exits
#     with "No users configured and prompting is prohibited" or hangs waiting
#     for input that never comes in a Docker container.
#   ssl.require_ssl: false -- ngrok handles TLS termination
RUN cat > /etc/kasmvnc/kasmvnc.yaml << 'YAML'
network:
  protocol: http
  interface: 0.0.0.0
  websocket_port: 6901
  ssl:
    require_ssl: false
    pem_certificate:
    pem_key:
  udp:
    public_ip: auto
desktop:
  resolution:
    width: 1920
    height: 1080
  allow_resize: true
encoding:
  rect_encoding_mode:
    min_quality: 7
    max_quality: 7
    consider_lossless_quality: 10
    rectangle_compress_threads: 0
runtime_configuration:
  allow_client_to_override_kasm_server_settings: true
  allow_override_standard_vnc_server_settings: true
command_line:
  prompt: false
YAML

# ── Fix XFCE-in-Docker annoyances ──────────────────────────────────
RUN mkdir -p /etc/polkit-1/localauthority/50-local.d \
    && printf '[Allow Colord]\nIdentity=unix-user:*\nAction=org.freedesktop.color-manager.create-device;org.freedesktop.color-manager.create-profile;org.freedesktop.color-manager.delete-device;org.freedesktop.color-manager.delete-profile;org.freedesktop.color-manager.modify-device;org.freedesktop.color-manager.modify-profile\nResultAny=yes\nResultInactive=yes\nResultActive=yes\n' \
       > /etc/polkit-1/localauthority/50-local.d/45-allow-colord.pkla \
    && rm -f /etc/xdg/autostart/xfce4-power-manager.desktop \
             /etc/xdg/autostart/xscreensaver.desktop \
             /etc/xdg/autostart/light-locker.desktop 2>/dev/null; true

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 6901
ENTRYPOINT ["/entrypoint.sh"]
