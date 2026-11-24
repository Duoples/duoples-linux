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

# Disk installer + passwordless sudo inside the live session only
install -m 0755 "$(cd "$(dirname "$0")" && pwd)/duoples-install.sh" "$R/usr/local/bin/duoples-install"
cat > "$R/etc/sudoers.d/90-duoples-live" << 'EOF'
Defaults:duoples env_keep += "DISPLAY XAUTHORITY"
duoples ALL=(ALL) NOPASSWD: ALL
EOF
chmod 0440 "$R/etc/sudoers.d/90-duoples-live"

mkdir -p "$R/usr/share/applications" "$R/home/duoples/Desktop"
cat > "$R/usr/share/applications/duoples-install.desktop" << 'EOF'
[Desktop Entry]
Type=Application
Name=Install Duoples Linux
Comment=Install Duoples Linux onto this computer's disk
Exec=sudo -E /usr/local/bin/duoples-install
Icon=drive-harddisk
Terminal=false
Categories=System;
EOF
cp "$R/usr/share/applications/duoples-install.desktop" "$R/home/duoples/Desktop/install-duoples.desktop"
chmod +x "$R/home/duoples/Desktop/install-duoples.desktop"
chown -R 1000:27 "$R/home/duoples/Desktop"

# Autostart the installer when booted from the "Install Duoples Linux" GRUB entry
mkdir -p "$R/etc/xdg/autostart"
cat > "$R/etc/xdg/autostart/duoples-installer.desktop" << 'EOF'
[Desktop Entry]
Type=Application
Name=Duoples Linux Installer
Comment=Start the installer when the live session was booted for installation
Exec=sh -c "grep -q duoples.installer=1 /proc/cmdline && exec sudo -E /usr/local/bin/duoples-install"
OnlyShowIn=XFCE;
X-GNOME-Autostart-enabled=true
NoDisplay=true
EOF

# Pick the largest mode the virtio GPU offers, so the desktop fills the display
cat > "$R/etc/xdg/autostart/duoples-display.desktop" << 'EOF'
[Desktop Entry]
Type=Application
Name=Duoples Display Setup
Comment=Use the largest available screen mode
Exec=sh -c "command -v xrandr >/dev/null && out=$(xrandr | awk '/ connected/{print $1; exit}') && mode=$(xrandr | awk -v o=\"$out\" '$0 ~ o\" \" {f=1} f && /^[ ]+[0-9]+x[0-9]+/{print $1}' | sort -t x -k1,1n -k2,2n | tail -1) && [ -n \"$mode\" ] && xrandr --output \"$out\" --mode \"$mode\""
OnlyShowIn=XFCE;
NoDisplay=true
EOF

# Enable graphical stack, disable slow cloud-init/network wait
chroot "$R" systemctl enable lightdm >/dev/null 2>&1 || true
chroot "$R" systemctl enable NetworkManager >/dev/null 2>&1 || true
chroot "$R" systemctl enable spice-vdagentd >/dev/null 2>&1 || true
chroot "$R" systemctl set-default graphical.target >/dev/null 2>&1 || true
chroot "$R" systemctl disable cloud-init cloud-init-local cloud-config cloud-final >/dev/null 2>&1 || true
chroot "$R" systemctl disable systemd-networkd-wait-online >/dev/null 2>&1 || true
# NetworkManager owns eth0; a second DHCP client on the same link can leave the
# live session with no address at all.
chroot "$R" systemctl disable systemd-networkd systemd-networkd.socket >/dev/null 2>&1 || true
rm -f "$R"/etc/systemd/system/multi-user.target.wants/systemd-networkd.service \
      "$R"/etc/systemd/system/multi-user.target.wants/systemd-networkd.socket \
      "$R"/etc/systemd/network/20-wired.network 2>/dev/null || true
# Make sure DNS resolves inside the live session even without systemd-resolved
if [ -L "$R/etc/resolv.conf" ] && [ ! -e "$R/run/systemd/resolve/stub-resolv.conf" ]; then
    rm -f "$R/etc/resolv.conf"
    echo "nameserver 1.1.1.1" > "$R/etc/resolv.conf"
fi

# Clean caches so the squashfs stays small
rm -rf "$R"/var/cache/apt/archives/*.deb "$R"/var/lib/apt/lists/* 2>/dev/null || true

echo "[*] Live rootfs ready."
