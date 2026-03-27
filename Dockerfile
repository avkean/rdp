FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# ── Core packages + KDE Plasma ────────────────────────────────────
RUN apt-get update && apt-get install -y \
    # KDE Plasma desktop
    kde-plasma-desktop \
    kwin-x11 \
    plasma-workspace \
    breeze \
    breeze-gtk-theme \
    breeze-icon-theme \
    # KDE apps
    dolphin \
    konsole \
    kate \
    ark \
    okular \
    gwenview \
    spectacle \
    kcalc \
    # VNC / noVNC
    tigervnc-standalone-server tigervnc-common \
    novnc websockify \
    # Desktop plumbing
    dbus-x11 xfonts-base \
    policykit-1-gnome \
    # Fonts (critical for web rendering)
    fonts-liberation fonts-dejavu-core \
    fonts-noto-color-emoji fonts-noto-core \
    fonts-ubuntu fontconfig \
    # Networking & system utilities
    iputils-ping net-tools iproute2 traceroute dnsutils \
    wget curl nano sudo less openssh-client \
    ca-certificates locales tzdata lsof htop \
    gnupg software-properties-common \
    zip unzip file python3 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# ── Firefox via Mozilla PPA (snap doesn't work in Docker) ─────────
RUN add-apt-repository -y ppa:mozillateam/ppa \
    && printf 'Package: firefox*\nPin: release o=LP-PPA-mozillateam\nPin-Priority: 1001\n' \
       > /etc/apt/preferences.d/mozilla-firefox \
    && apt-get update \
    && apt-get install -y firefox \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# ── ngrok via official apt repo ────────────────────────────────────
RUN curl -sSL https://ngrok-agent.s3.amazonaws.com/ngrok.asc \
       | tee /etc/apt/trusted.gpg.d/ngrok.asc >/dev/null \
    && echo "deb https://ngrok-agent.s3.amazonaws.com buster main" \
       | tee /etc/apt/sources.list.d/ngrok.list \
    && apt-get update \
    && apt-get install -y ngrok \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# ── Generate UTF-8 locale ─────────────────────────────────────────
RUN locale-gen en_US.UTF-8
ENV LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

# Startup script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
