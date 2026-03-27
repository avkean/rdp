FROM kalilinux/kali-rolling

ENV DEBIAN_FRONTEND=noninteractive

# ── Layer 1: Desktop + VNC + utilities + ngrok ──────────────────────
# Uses bare xfce4 (not kali-desktop-xfce) to cut ~1GB from image.
# kali-desktop-xfce adds lightdm, kali-themes, 500+ extra packages —
# none needed for VNC.
RUN apt-get update && apt-get install -y --no-install-recommends \
    xfce4 \
    xfce4-terminal \
    firefox-esr \
    tigervnc-standalone-server \
    novnc \
    websockify \
    dbus dbus-x11 \
    fonts-dejavu-core \
    wget curl nano sudo less openssh-client \
    net-tools iproute2 iputils-ping dnsutils traceroute \
    htop lsof zip unzip file \
    ca-certificates locales python3 \
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

# ── Pre-bake VNC config (only password set at runtime) ──────────────
RUN mkdir -p /root/.config/tigervnc \
    && printf '#!/bin/bash\nunset SESSION_MANAGER\nunset DBUS_SESSION_BUS_ADDRESS\nexport XKL_XMODMAP_DISABLE=1\nexec startxfce4\n' \
       > /root/.config/tigervnc/xstartup \
    && chmod +x /root/.config/tigervnc/xstartup

# ── Fix XFCE-in-Docker annoyances ──────────────────────────────────
RUN mkdir -p /etc/polkit-1/localauthority/50-local.d \
    && printf '[Allow Colord]\nIdentity=unix-user:*\nAction=org.freedesktop.color-manager.create-device;org.freedesktop.color-manager.create-profile;org.freedesktop.color-manager.delete-device;org.freedesktop.color-manager.delete-profile;org.freedesktop.color-manager.modify-device;org.freedesktop.color-manager.modify-profile\nResultAny=yes\nResultInactive=yes\nResultActive=yes\n' \
       > /etc/polkit-1/localauthority/50-local.d/45-allow-colord.pkla \
    && rm -f /etc/xdg/autostart/xfce4-power-manager.desktop \
             /etc/xdg/autostart/xscreensaver.desktop \
             /etc/xdg/autostart/light-locker.desktop 2>/dev/null; true

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
