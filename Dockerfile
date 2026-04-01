# syntax=docker/dockerfile:1
FROM kalilinux/kali-rolling

ENV DEBIAN_FRONTEND=noninteractive
# Firefox's content sandbox uses CLONE_NEWUSER which Docker's default
# seccomp profile blocks → content processes crash with I/O errors.
ENV MOZ_DISABLE_CONTENT_SANDBOX=1
# Prevent GTK apps from connecting to the accessibility D-Bus
# (no screen readers in a container — saves startup time & error spam)
ENV NO_AT_BRIDGE=1
# Disable overlay scrollbar animations (less rendering overhead)
ENV GTK_OVERLAY_SCROLLING=0

# Skip downloading apt translation files (faster apt-get update)
RUN echo 'Acquire::Languages "none";' > /etc/apt/apt.conf.d/99no-translations

# ── Layer 1: Minimal XFCE desktop + essentials ─────────────────────
# Hand-picked instead of kali-desktop-xfce (saves ~1.5GB of bloat:
# games, accessibility, printing, redundant plugins).
# Cache mount keeps downloaded .debs across rebuilds.
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    # Core XFCE
    xfce4 xfce4-terminal thunar xfce4-appfinder xfce4-notifyd \
    # All 6 panel plugins referenced by kali-themes default panel config
    # (missing any one of these causes a "Plugin loading failure" dialog)
    xfce4-whiskermenu-plugin xfce4-cpugraph-plugin xfce4-genmon-plugin \
    xfce4-pulseaudio-plugin xfce4-power-manager-plugins \
    # Kali look & feel (kali-themes pulls wallpapers as a dependency)
    kali-themes kali-menu \
    # Desktop infrastructure (dbus session bus, PolicyKit, xdg-open)
    dbus dbus-x11 dbus-user-session x11-xserver-utils \
    xdg-utils mate-polkit \
    # Browser
    firefox-esr \
    # Fonts (Hack Nerd Font symbols, general coverage)
    fonts-hack fonts-noto-color-emoji fonts-wqy-zenhei \
    # CLI essentials
    wget curl nano sudo less openssh-client \
    net-tools iproute2 iputils-ping dnsutils traceroute \
    htop lsof zip unzip file jq \
    ca-certificates locales python3 gnupg xz-utils \
    && rm -rf /usr/share/doc/* /usr/share/man/* /usr/share/info/* \
    && find /usr/share/locale -mindepth 1 -maxdepth 1 ! -name 'en*' -exec rm -rf {} + 2>/dev/null; true

# ── Layer 2: KasmVNC ───────────────────────────────────────────────
# Single .deb replaces tigervnc + novnc + websockify.
# Built-in WebSocket server, web client, WebP encoding.
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    wget -q https://github.com/kasmtech/KasmVNC/releases/download/v1.4.0/kasmvncserver_kali-rolling_1.4.0_amd64.deb \
       -O /tmp/kasmvnc.deb \
    && apt-get update \
    && apt-get install -y /tmp/kasmvnc.deb \
    && rm /tmp/kasmvnc.deb

# Default the KasmVNC web client to "High" quality preset (60fps, quality 7-9)
# instead of "Medium" (24fps, quality 4). Preset values are hardcoded in ui.js.
# The initSetting call sets the default for first-time visitors (persists in
# browser localStorage after that).
RUN sed -i "s/\(UI\.\(init\|update\)Setting('video_quality',\) 2)/\1 3)/g" \
    /usr/share/kasmvnc/www/app/ui.js

# ── Layer 3: zrok tunnel ───────────────────────────────────────────
RUN curl -sSf https://get.openziti.io/install.bash | bash -s zrok2

# ── Layer 4: Pentesting tools (heaviest, changes least often) ──────
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    kali-tools-top10 \
    && rm -rf /usr/share/doc/* /usr/share/man/* /usr/share/info/*

# ── Locale ──────────────────────────────────────────────────────────
RUN sed -i 's/# en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

# ── Pre-bake KasmVNC + XFCE config ─────────────────────────────────
# Bypass KasmVNC's 3 interactive TTY prompts + pre-configure Kali dark theme
RUN mkdir -p /root/.vnc /root/.config/xfce4/xfconf/xfce-perchannel-xml \
    && printf '#!/bin/sh\nexec xfce4-session\n' > /root/.vnc/xstartup \
    && chmod +x /root/.vnc/xstartup \
    && touch /root/.vnc/.de-was-selected /root/.Xauthority

# Font rendering: Hack Nerd Font as monospace + anti-aliasing + hinting.
# fontconfig applies to all apps. Using grayscale AA (rgba=none) because
# subpixel rendering causes color fringing over VNC (unknown client LCD layout).
RUN cat > /etc/fonts/local.conf << 'FONTCONF'
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <alias>
    <family>monospace</family>
    <prefer><family>Hack Nerd Font Mono</family></prefer>
  </alias>
  <match target="font">
    <edit mode="assign" name="antialias"><bool>true</bool></edit>
    <edit mode="assign" name="hinting"><bool>true</bool></edit>
    <edit mode="assign" name="hintstyle"><const>hintslight</const></edit>
    <edit mode="assign" name="rgba"><const>none</const></edit>
    <edit mode="assign" name="lcdfilter"><const>lcddefault</const></edit>
    <edit mode="assign" name="embeddedbitmap"><bool>false</bool></edit>
  </match>
</fontconfig>
FONTCONF
RUN fc-cache -f

# KasmVNC YAML config — optimized for tunneled WebSocket access
# Written to BOTH /etc/kasmvnc/ (system) AND /root/.vnc/ (per-user).
# KasmVNC reads the per-user file (~/.vnc/kasmvnc.yaml) if it exists,
# otherwise creates one from built-in defaults — ignoring /etc/kasmvnc/.
# Pre-creating the per-user file ensures our settings actually apply.
RUN cat > /tmp/kasmvnc.yaml << 'YAML'
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
  max_frame_rate: 60
  rect_encoding_mode:
    min_quality: 7
    max_quality: 9
    consider_lossless_quality: 7
    rectangle_compress_threads: auto
  # Optimized encoding for rapid screen changes (scrolling, video)
  video_encoding_mode:
    jpeg_quality: -1
    webp_quality: -1
    enter_video_encoding_mode:
      time_threshold: 5
      area_threshold: "45%"
    exit_video_encoding_mode:
      time_threshold: 3
    scaling_algorithm: progressive_bilinear
  # Skip sending unchanged pixels (reduces bandwidth)
  compare_framebuffer: auto
  hextile_improved_compression: true
runtime_configuration:
  allow_client_to_override_kasm_server_settings: true
  allow_override_standard_vnc_server_settings: true
data_loss_prevention:
  clipboard:
    delay_between_operations: none
    allow_mimetypes:
      - chromium/x-web-custom-data
      - text/html
      - image/png
command_line:
  prompt: false
YAML
RUN cp /tmp/kasmvnc.yaml /etc/kasmvnc/kasmvnc.yaml \
    && cp /tmp/kasmvnc.yaml /root/.vnc/kasmvnc.yaml \
    && rm /tmp/kasmvnc.yaml

# XFCE dark theme: GTK + icons + window manager + wallpaper
RUN cat > /root/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml << 'XML'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xsettings" version="1.0">
  <property name="Net" type="empty">
    <property name="ThemeName" type="string" value="Kali-Dark"/>
    <property name="IconThemeName" type="string" value="Flat-Remix-Blue-Dark"/>
    <property name="CursorThemeName" type="string" value="Adwaita"/>
    <!-- No audio device in container -->
    <property name="EnableEventSounds" type="bool" value="false"/>
    <property name="EnableInputFeedbackSounds" type="bool" value="false"/>
  </property>
  <property name="Gtk" type="empty">
    <property name="FontName" type="string" value="Cantarell 10"/>
  </property>
  <property name="Xft" type="empty">
    <property name="DPI" type="int" value="96"/>
    <property name="Antialias" type="int" value="1"/>
    <property name="Hinting" type="int" value="1"/>
    <property name="HintStyle" type="string" value="hintslight"/>
    <property name="RGBA" type="string" value="none"/>
  </property>
</channel>
XML

RUN cat > /root/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml << 'XML'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfwm4" version="1.0">
  <property name="general" type="empty">
    <property name="theme" type="string" value="Kali-Dark"/>
    <property name="title_font" type="string" value="Cantarell Bold 10"/>
    <property name="title_alignment" type="string" value="center"/>
    <!-- Disable compositor: tries GPU ops that fail in containers, wastes CPU -->
    <property name="use_compositing" type="bool" value="false"/>
    <!-- Disable vsync: meaningless in VNC, just adds latency -->
    <property name="vblank_mode" type="string" value="off"/>
    <property name="sync_to_vblank" type="bool" value="false"/>
    <property name="box_move" type="bool" value="false"/>
    <property name="box_resize" type="bool" value="false"/>
    <!-- Disable unnecessary visual effects -->
    <property name="cycle_preview" type="bool" value="false"/>
    <property name="zoom_desktop" type="bool" value="false"/>
    <property name="zoom_pointer" type="bool" value="false"/>
    <!-- No shadows (waste CPU cycles encoding pixels VNC must send) -->
    <property name="show_dock_shadow" type="bool" value="false"/>
    <property name="show_frame_shadow" type="bool" value="false"/>
    <property name="show_popup_shadow" type="bool" value="false"/>
    <!-- No transparency (100% = fully opaque, nothing to composite) -->
    <property name="frame_opacity" type="int" value="100"/>
    <property name="inactive_opacity" type="int" value="100"/>
    <property name="move_opacity" type="int" value="100"/>
    <property name="popup_opacity" type="int" value="100"/>
    <property name="resize_opacity" type="int" value="100"/>
    <!-- Single workspace: less WM state to manage -->
    <property name="workspace_count" type="int" value="1"/>
  </property>
</channel>
XML

RUN cat > /root/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml << 'XML'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-desktop" version="1.0">
  <!-- Disable desktop icons (prevents xfdesktop file monitoring overhead) -->
  <property name="desktop-icons" type="empty">
    <property name="style" type="int" value="0"/>
  </property>
  <property name="backdrop" type="empty">
    <property name="screen0" type="empty">
      <property name="monitorVNC-0" type="empty">
        <property name="workspace0" type="empty">
          <property name="last-image" type="string" value="/usr/share/backgrounds/kali-16x9/default"/>
          <property name="image-style" type="int" value="5"/>
        </property>
      </property>
    </property>
  </property>
</channel>
XML

# Disable Thunar thumbnail generation (saves CPU + I/O)
RUN cat > /root/.config/xfce4/xfconf/xfce-perchannel-xml/thunar.xml << 'XML'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="thunar" version="1.0">
  <property name="misc-thumbnail-mode" type="string" value="THUNAR_THUMBNAIL_MODE_NEVER"/>
  <property name="misc-thumbnail-draw-frames" type="bool" value="false"/>
</channel>
XML

# ── Firefox: suppress first-run warnings and telemetry ─────────────
RUN mkdir -p /usr/lib/firefox-esr/distribution \
    && cat > /usr/lib/firefox-esr/distribution/policies.json << 'JSON'
{
  "policies": {
    "DisableTelemetry": true,
    "DontCheckDefaultBrowser": true,
    "OverrideFirstRunPage": "",
    "OverridePostUpdatePage": "",
    "UserMessaging": {
      "ExtensionRecommendations": false,
      "FeatureRecommendations": false,
      "UrlbarInterventions": false,
      "SkipOnboarding": true,
      "MoreFromMozilla": false
    },
    "Preferences": {
      "datareporting.policy.dataSubmissionEnabled": { "Value": false, "Status": "locked" },
      "toolkit.telemetry.reportingpolicy.firstRun": { "Value": false, "Status": "locked" },
      "browser.shell.checkDefaultBrowser": { "Value": false, "Status": "locked" },
      "app.shield.optoutstudies.enabled": { "Value": false, "Status": "locked" },
      "app.normandy.enabled": { "Value": false, "Status": "locked" }
    }
  }
}
JSON

# ── XFCE: set default terminal emulator ───────────────────────────
RUN mkdir -p /etc/xdg/xfce4 \
    && printf 'TerminalEmulator=xfce4-terminal\nTerminalEmulatorDismissed=true\n' \
       > /etc/xdg/xfce4/helpers.rc

# ── Install Hack Nerd Font (powerline/devicon symbols) ─────────────
RUN mkdir -p /usr/share/fonts/truetype/hack-nerd \
    && curl -fsSL https://github.com/ryanoasis/nerd-fonts/releases/latest/download/Hack.tar.xz \
       | tar -xJ -C /usr/share/fonts/truetype/hack-nerd \
    && fc-cache -f

# ── Fix XFCE-in-Docker annoyances ──────────────────────────────────
RUN mkdir -p /etc/polkit-1/localauthority/50-local.d \
    && printf '[Allow Colord]\nIdentity=unix-user:*\nAction=org.freedesktop.color-manager.create-device;org.freedesktop.color-manager.create-profile;org.freedesktop.color-manager.delete-device;org.freedesktop.color-manager.delete-profile;org.freedesktop.color-manager.modify-device;org.freedesktop.color-manager.modify-profile\nResultAny=yes\nResultInactive=yes\nResultActive=yes\n' \
       > /etc/polkit-1/localauthority/50-local.d/45-allow-colord.pkla \
    && rm -f /etc/xdg/autostart/xfce4-power-manager.desktop \
             /etc/xdg/autostart/xscreensaver.desktop \
             /etc/xdg/autostart/light-locker.desktop \
             /etc/xdg/autostart/at-spi-dbus-bus.desktop 2>/dev/null; true

# Disable tumbler thumbnail daemon (all thumbnailer plugins)
RUN if [ -f /etc/xdg/tumbler/tumbler.rc ]; then \
      sed -i 's/^Disabled=false/Disabled=true/' /etc/xdg/tumbler/tumbler.rc; \
    fi

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 6901

HEALTHCHECK --interval=10s --timeout=5s --start-period=30s --retries=3 \
  CMD curl -sf http://localhost:6901/ > /dev/null 2>&1 || exit 1

ENTRYPOINT ["/entrypoint.sh"]
