FROM kalilinux/kali-rolling

ENV DEBIAN_FRONTEND=noninteractive

# ── Layer 1: Desktop environment (largest, changes least) ───────────
# No --no-install-recommends here — XFCE needs recommended deps for
# themes, icons, and session components to work properly in VNC.
RUN apt-get update && apt-get install -y \
    kali-desktop-xfce \
    tigervnc-standalone-server \
    novnc \
    websockify \
    dbus dbus-x11 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# ── Layer 2: Pentesting tools (separate layer for caching) ──────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    kali-tools-top10 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# ── Layer 3: System utilities ───────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    wget curl nano sudo less openssh-client \
    net-tools iproute2 iputils-ping dnsutils traceroute \
    htop lsof zip unzip file \
    ca-certificates locales \
    python3 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# ── Layer 4: ngrok ──────────────────────────────────────────────────
RUN curl -sSL https://ngrok-agent.s3.amazonaws.com/ngrok.asc \
       | tee /etc/apt/trusted.gpg.d/ngrok.asc >/dev/null \
    && echo "deb https://ngrok-agent.s3.amazonaws.com buster main" \
       | tee /etc/apt/sources.list.d/ngrok.list \
    && apt-get update && apt-get install -y ngrok \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# ── Locale ──────────────────────────────────────────────────────────
RUN sed -i 's/# en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

# ── Fix known XFCE-in-Docker issues ────────────────────────────────

# Suppress PolicyKit "color managed device" auth popup
RUN mkdir -p /etc/polkit-1/localauthority/50-local.d \
    && printf '%s\n' \
       '[Allow Colord]' \
       'Identity=unix-user:*' \
       'Action=org.freedesktop.color-manager.create-device;org.freedesktop.color-manager.create-profile;org.freedesktop.color-manager.delete-device;org.freedesktop.color-manager.delete-profile;org.freedesktop.color-manager.modify-device;org.freedesktop.color-manager.modify-profile' \
       'ResultAny=yes' \
       'ResultInactive=yes' \
       'ResultActive=yes' \
       > /etc/polkit-1/localauthority/50-local.d/45-allow-colord.pkla

# Disable power manager and screensaver (meaningless in container;
# screensaver/light-locker will lock you out of VNC)
RUN rm -f /etc/xdg/autostart/xfce4-power-manager.desktop 2>/dev/null; \
    rm -f /etc/xdg/autostart/xscreensaver.desktop 2>/dev/null; \
    rm -f /etc/xdg/autostart/light-locker.desktop 2>/dev/null; \
    true

# ── Entrypoint ──────────────────────────────────────────────────────
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
