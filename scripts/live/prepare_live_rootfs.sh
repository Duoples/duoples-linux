#!/bin/bash
# Prepare a plain Ubuntu/Debian rootfs to boot as the Duoples Linux live desktop.
# Run on the ARM64 build host after installing XFCE/LightDM into $ROOTFS_DIR:
#   chroot $ROOTFS_DIR apt-get install -y --no-install-recommends \
#       xorg xfce4 lightdm lightdm-gtk-greeter dbus-x11 network-manager
set -e

R="${ROOTFS_DIR:-/home/duoples-linux/full_rootfs}"
WALLPAPER="${WALLPAPER:-$(cd "$(dirname "$0")/../../branding" && pwd)/duoples-wallpaper.png}"

echo "[*] Preparing live rootfs at $R..."

# Live identity
: > "$R/etc/machine-id"
echo "duoples-linux" > "$R/etc/hostname"
cat > "$R/etc/hosts" << EOF
127.0.0.1 localhost
127.0.1.1 duoples-linux
EOF

# Branding on the text console
cat > "$R/etc/issue" << EOF
Duoples Linux 1.1 LTS \\n \\l
EOF

# Desktop wallpaper
mkdir -p "$R/usr/share/backgrounds/duoples"
if [ -f "$WALLPAPER" ]; then
    cp "$WALLPAPER" "$R/usr/share/backgrounds/duoples/duoples-default.png"
fi
mkdir -p "$R/etc/xdg/xfce4/xfconf/xfce-perchannel-xml"
cat > "$R/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-desktop" version="1.0">
  <property name="backdrop" type="empty">
    <property name="screen0" type="empty">
      <property name="monitor0" type="empty">
        <property name="image-path" type="string" value="/usr/share/backgrounds/duoples/duoples-default.png"/>
        <property name="image-style" type="int" value="5"/>
      </property>
      <property name="monitor1" type="empty">
        <property name="image-path" type="string" value="/usr/share/backgrounds/duoples/duoples-default.png"/>
        <property name="image-style" type="int" value="5"/>
      </property>
      <property name="monitorVirtual-1" type="empty">
        <property name="image-path" type="string" value="/usr/share/backgrounds/duoples/duoples-default.png"/>
        <property name="image-style" type="int" value="5"/>
      </property>
    </property>
  </property>
</channel>
EOF

# Also seed the live user's config
mkdir -p "$R/home/duoples/.config/xfce4/xfconf/xfce-perchannel-xml"
cp "$R/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml" \
   "$R/home/duoples/.config/xfce4/xfconf/xfce-perchannel-xml/"
chown -R 1000:27 "$R/home/duoples/.config" 2>/dev/null || true

# LightDM greeter
mkdir -p "$R/etc/lightdm/lightdm.conf.d" "$R/etc/lightdm/lightdm-gtk-greeter.conf.d"
cat > "$R/etc/lightdm/lightdm.conf.d/50-duoples-autologin.conf" << EOF
[Seat:*]
autologin-user=duoples
autologin-user-timeout=0
autologin-session=xfce
user-session=xfce
EOF
cat > "$R/etc/lightdm/lightdm-gtk-greeter.conf.d/50-duoples.conf" << EOF
[greeter]
background=/usr/share/backgrounds/duoples/duoples-default.png
theme-name=Adwaita-dark
icon-theme-name=Papirus-Dark
user-background=false
EOF

# Groups
chroot "$R" usermod -aG sudo,video,render,audio,plugdev duoples

# Enable graphical stack, disable slow cloud-init/network wait
chroot "$R" systemctl enable lightdm >/dev/null 2>&1 || true
chroot "$R" systemctl enable NetworkManager >/dev/null 2>&1 || true
chroot "$R" systemctl set-default graphical.target >/dev/null 2>&1 || true
chroot "$R" systemctl disable cloud-init cloud-init-local cloud-config cloud-final >/dev/null 2>&1 || true
chroot "$R" systemctl disable systemd-networkd-wait-online >/dev/null 2>&1 || true

# Clean caches so the squashfs stays small
rm -rf "$R"/var/cache/apt/archives/*.deb "$R"/var/lib/apt/lists/* 2>/dev/null || true

echo "[*] Live rootfs ready."
