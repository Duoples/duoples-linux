#!/bin/bash
set -e

# ==============================================================================
# Duoples Linux 1.0 LTS - Full-Fledged Distribution Generator
# Builds a complete, standalone Debian-compatible OS with APT, systemd, SSH,
# pre-installed Duoples Appstore, and full Duoples branding from pure scratch.
# ==============================================================================

WORK_DIR="/home/duoples-linux"
ROOTFS_DIR="${WORK_DIR}/full_rootfs"
OUT_DIR="${WORK_DIR}/out"
DASHBOARD_URL="http://192.168.2.90:3780"

report_event() {
    local stage="$1"
    local progress="$2"
    local msg="$3"
    curl -s -X POST "${DASHBOARD_URL}/api/build-event"         -H "Content-Type: application/json"         -d "{\"buildId\":\"build_duoples_linux_1.0\",\"device\":\"generic_arm64\",\"deviceName\":\"Duoples Linux (ARM64)\",\"romName\":\"Duoples Linux 1.0 LTS\",\"version\":\"1.0-LTS\",\"branch\":\"main\",\"status\":\"compiling\",\"stage\":\"${stage}\",\"progress\":${progress},\"cores\":8,\"environment\":\"self_hosted\",\"message\":\"${msg}\"}" >/dev/null 2>&1 || true
}

report_log() {
    local text="$1"
    local level="${2:-stdout}"
    curl -s -X POST "${DASHBOARD_URL}/api/build-log"         -H "Content-Type: application/json"         -d "{\"text\":\"${text}\",\"level\":\"${level}\",\"stage\":\"soong_analysis\"}" >/dev/null 2>&1 || true
}

echo "=================================================="
echo " Building Duoples Linux 1.0 LTS (Full-Fledged OS)"
echo "=================================================="

report_event "repo_sync" 15 "Starting Duoples Linux rootfs bootstrap via debootstrap..."
report_log "[*] Initializing Duoples Linux 1.0 LTS build pipeline..." "info"

mkdir -p "${ROOTFS_DIR}" "${OUT_DIR}"

# Step 1: Bootstrap clean Debian/Ubuntu base
if [ ! -f "${ROOTFS_DIR}/bin/bash" ]; then
    echo "[*] Bootstrapping base system..."
    report_log "[*] Bootstrapping base packages with APT, coreutils, and glibc..." "info"
    debootstrap --arch=arm64 --include=systemd,systemd-sysv,udev,dbus,apt,dpkg,bash,coreutils,sudo,curl,wget,ca-certificates,net-tools,iproute2,openssh-server,nano,locales,kmod,libgtk-3-0,libglib2.0-0 noble "${ROOTFS_DIR}" http://ports.ubuntu.com/ubuntu-ports/
fi

report_event "apply_patches" 40 "Injecting Duoples Linux brand identity, Appstore, and users..."
report_log "[*] Applying Duoples Linux custom branding and pre-installed Appstore..." "info"

# Step 2: Configure Duoples OS Release & Branding
cat << 'BRANDING' > "${ROOTFS_DIR}/etc/os-release"
NAME="Duoples Linux"
VERSION="1.0 LTS"
ID=duoples
ID_LIKE="ubuntu debian"
VERSION_ID="1.0"
PRETTY_NAME="Duoples Linux 1.0 LTS"
HOME_URL="https://duoples.com"
SUPPORT_URL="https://duoples.com/support"
BUG_REPORT_URL="https://github.com/Duoples/duoples-linux/issues"
BRANDING

# Step 3: Hostname & Hosts
echo "duoples-linux" > "${ROOTFS_DIR}/etc/hostname"
cat << 'HOSTS' > "${ROOTFS_DIR}/etc/hosts"
127.0.0.1   localhost
127.0.1.1   duoples-linux
::1         localhost ip6-localhost ip6-loopback
HOSTS

# Step 4: Duoples MOTD Banner
cat << 'MOTD' > "${ROOTFS_DIR}/etc/motd"

  ____                   _           _     _                  
 |  _ \ _   _  ___  _ __| | ___  ___| |   (_)_ __  _   ___  __
 | | | | | | |/ _ \| '_ \ |/ _ \/ __| |   | | '_ \| | | \ \/ /
 | |_| | |_| | (_) | |_) | |  __/\__ \ |___| | | | | |_| |>  < 
 |____/ \__,_|\___/| .__/|_|\___||___/_____|_|_| |_|\__,_/_/\_                   |_|                                        
                 DUOPLES LINUX 1.0 LTS

 Welcome to Duoples Linux! Pre-installed with Duoples Appstore.
 Run 'duoples-appstore' or click the Appstore icon to install applications.
 Run 'sudo apt update && sudo apt install <package>' to install any software.
 Docs & Source: https://github.com/Duoples/duoples-linux

MOTD

# Step 5: Configure Shell Prompt in /etc/profile
cat << 'PROFILE' >> "${ROOTFS_DIR}/etc/profile"
export PS1='\[\033[01;36m\]\u@duoples-linux\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]$ '
alias ll='ls -la --color=auto'
alias la='ls -A --color=auto'
alias l='ls -CF --color=auto'
alias appstore='duoples-appstore'
PROFILE

# Step 6: Pre-install Duoples Appstore Linux client
echo "[*] Pre-installing Duoples Appstore Linux Client..."
APPSTORE_URL="https://s3storage.duoples.com/duoplesappstore/com.duoples.appstore/com.duoples.appstore_2.0.1%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20.deb"
curl -sL -A "Mozilla/5.0" "${APPSTORE_URL}" -o "${WORK_DIR}/duoples-appstore.deb"
dpkg -x "${WORK_DIR}/duoples-appstore.deb" "${ROOTFS_DIR}/"
chmod +x "${ROOTFS_DIR}/opt/duoples-appstore/duoples_appstore_linux"
ln -sf /opt/duoples-appstore/duoples_appstore_linux "${ROOTFS_DIR}/usr/bin/duoples-appstore"

# Step 7: System Configuration inside Chroot
echo "[*] Configuring users, sudo, and SSH..."
report_event "envsetup_lunch" 65 "Setting up systemd services, sudo permissions, and networking..."

mount --bind /dev "${ROOTFS_DIR}/dev"
mount --bind /dev/pts "${ROOTFS_DIR}/dev/pts"
mount --bind /proc "${ROOTFS_DIR}/proc"
mount --bind /sys "${ROOTFS_DIR}/sys"

chroot "${ROOTFS_DIR}" /bin/bash -c "
export DEBIAN_FRONTEND=noninteractive

# Generate UTF-8 locale
locale-gen en_US.UTF-8
update-locale LANG=en_US.UTF-8

# Create default duoples user with sudo privileges
id -u duoples >/dev/null 2>&1 || useradd -m -s /bin/bash -g sudo duoples
ADMIN_USER='duoples'
INIT_PASS=\${DEFAULT_PASSWORD:-\$(openssl rand -hex 8)}
usermod -p \"\$(openssl passwd -6 \"\${INIT_PASS}\")\" \"\${ADMIN_USER}\" 2>/dev/null || true
usermod -p \"\$(openssl passwd -6 \"\${INIT_PASS}\")\" root 2>/dev/null || true

# Passwordless sudo for duoples user
echo 'duoples ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/99-duoples
chmod 0440 /etc/sudoers.d/99-duoples

# Enable SSH root login and password authentication
mkdir -p /etc/ssh/sshd_config.d
echo 'PermitRootLogin yes' > /etc/ssh/sshd_config.d/duoples-root.conf
echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config.d/duoples-root.conf

# Enable services
systemctl enable systemd-networkd 2>/dev/null || true
systemctl enable systemd-resolved 2>/dev/null || true
systemctl enable ssh 2>/dev/null || true

# Setup DHCP network on all interfaces
mkdir -p /etc/systemd/network
cat << 'NET' > /etc/systemd/network/20-wired.network
[Match]
Name=en* eth*

[Network]
DHCP=yes
NET
"

umount "${ROOTFS_DIR}/sys" || true
umount "${ROOTFS_DIR}/proc" || true
umount "${ROOTFS_DIR}/dev/pts" || true
umount "${ROOTFS_DIR}/dev" || true

# Step 8: Packaging Full RootFS Archive
echo "[*] Creating Duoples Linux deployable rootfs archive..."
report_event "ninja_compilation" 85 "Compressing Duoples Linux full system image..."
report_log "[*] Packaging duoples-linux-rootfs.tar.gz..." "info"

cd "${ROOTFS_DIR}"
tar -czf "${OUT_DIR}/duoples-linux-rootfs.tar.gz" --exclude="./out" .

IMAGE_SIZE=$(du -sh "${OUT_DIR}/duoples-linux-rootfs.tar.gz" | awk '{print $1}')
SHA256=$(sha256sum "${OUT_DIR}/duoples-linux-rootfs.tar.gz" | awk '{print $1}')

echo "=================================================="
echo " Duoples Linux 1.0 LTS Built Successfully!"
echo " Pre-installed: Duoples Appstore Client v2.0.1"
echo " Image Size: ${IMAGE_SIZE}"
echo " SHA256: ${SHA256}"
echo "=================================================="

report_event "completed" 100 "Duoples Linux 1.0 LTS built successfully with pre-installed Appstore! Size: ${IMAGE_SIZE}"
report_log "[+] Duoples Linux 1.0 LTS generated at ${OUT_DIR}/duoples-linux-rootfs.tar.gz (${IMAGE_SIZE})" "info"
