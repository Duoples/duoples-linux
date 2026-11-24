#!/bin/bash
# ==============================================================================
# Duoples Linux disk installer
# Deploys the running live system onto a local disk and installs GRUB (ARM64 UEFI).
# ==============================================================================
set -euo pipefail

TITLE="Duoples Linux Installer"
SQUASH="/mnt/cdrom/live/filesystem.squashfs"
KERNEL="/mnt/cdrom/live/vmlinuz"
TARGET="/target"
LOG="/var/log/duoples-install.log"

export DISPLAY="${DISPLAY:-:0}"
export XAUTHORITY="${XAUTHORITY:-/home/duoples/.Xauthority}"

err() { zenity --error --width=520 --title="$TITLE" --text="$1" 2>/dev/null || echo "ERROR: $1" >&2; }
info() { zenity --info --width=520 --title="$TITLE" --text="$1" 2>/dev/null || echo "$1"; }

if [ "$(id -u)" -ne 0 ]; then
    exec sudo -E "$0" "$@"
fi

exec > >(tee -a "$LOG") 2>&1
echo "=== Duoples install started $(date -Is) ==="

[ -f "$SQUASH" ] || { err "Live medium not found at $SQUASH."; exit 1; }
[ -f "$KERNEL" ] || { err "Live kernel not found at $KERNEL."; exit 1; }

# --- disk selection -----------------------------------------------------------
ARGS=()
while read -r name size ro type model; do
    [ "$ro" = "0" ] || continue
    [ "$type" = "disk" ] || continue
    case "$name" in
        /dev/loop*|/dev/zram*|/dev/sr*) continue ;;
    esac
    ARGS+=(FALSE "$name" "$size" "${model:-disk}")
done < <(lsblk -dpno NAME,SIZE,RO,TYPE,MODEL 2>/dev/null)

if [ ${#ARGS[@]} -eq 0 ]; then
    err "No writable disks were found."
    exit 1
fi

SELECTED=$(zenity --list --radiolist --width=760 --height=380 \
    --title="$TITLE" \
    --text="Select the disk to install Duoples Linux onto.\n\nWARNING: everything on this disk will be erased." \
    --column="" --column="Device" --column="Size" --column="Model" \
    "${ARGS[@]}") || exit 0

DISK=$(echo "$SELECTED" | cut -d'|' -f2)
[ -b "$DISK" ] || { err "Invalid disk selection."; exit 1; }

CONFIRM=$(zenity --entry --width=520 --title="$TITLE" \
    --text="Type ERASE (in capitals) to permanently erase $DISK:") || exit 0
if [ "$CONFIRM" != "ERASE" ]; then
    info "Installation cancelled. Nothing was changed."
    exit 0
fi

HOSTNAME_NEW=$(zenity --entry --width=520 --title="$TITLE" \
    --text="Computer name:" --entry-text="duoples-linux") || exit 0
[ -n "$HOSTNAME_NEW" ] || HOSTNAME_NEW="duoples-linux"

PASS1=$(zenity --password --width=520 --title="$TITLE" --text="New password for user duoples (leave empty to keep current):") || exit 0
if [ -n "$PASS1" ]; then
    PASS2=$(zenity --password --width=520 --title="$TITLE" --text="Repeat the password:") || exit 0
    if [ "$PASS1" != "$PASS2" ]; then
        err "Passwords do not match. Installation cancelled."
        exit 1
    fi
fi

# --- partitioning -------------------------------------------------------------
if [[ "$DISK" =~ [0-9]$ ]]; then
    P1="${DISK}p1"; P2="${DISK}p2"
else
    P1="${DISK}1"; P2="${DISK}2"
fi

echo "Target disk: $DISK ($P1, $P2)"
(
    set -x
    swapoff -a || true
    umount "${DISK}"* 2>/dev/null || true
    parted -s "$DISK" mklabel gpt
    parted -s "$DISK" mkpart ESP fat32 1MiB 513MiB
    parted -s "$DISK" set 1 esp on
    parted -s "$DISK" mkpart root ext4 513MiB 100%
    partprobe "$DISK" || true
    udevadm settle || true
    sleep 1
    mkfs.fat -F32 -n DUOPLES_EFI "$P1"
    mkfs.ext4 -F -L DUOPLES "$P2"
) 2>&1 | zenity --progress --pulsate --auto-close --no-cancel --width=520 \
    --title="$TITLE" --text="Partitioning and formatting $DISK..."

# --- deploy root filesystem ---------------------------------------------------
mkdir -p "$TARGET"
mount "$P2" "$TARGET"
mkdir -p "$TARGET/boot/efi"
mount "$P1" "$TARGET/boot/efi"
rm -rf "$TARGET/lost+found"

unsquashfs -f -d "$TARGET" "$SQUASH" 2>&1 | zenity --progress --pulsate --auto-close --no-cancel --width=520 \
    --title="$TITLE" --text="Copying the Duoples Linux system to disk..."

cp "$KERNEL" "$TARGET/boot/vmlinuz-6.6.80-duoples"

ROOT_UUID=$(blkid -s UUID -o value "$P2")
EFI_UUID=$(blkid -s UUID -o value "$P1")

cat > "$TARGET/etc/fstab" << EOF
UUID=$ROOT_UUID / ext4 defaults 0 1
UUID=$EFI_UUID /boot/efi vfat umask=0077 0 1
EOF

: > "$TARGET/etc/machine-id"
echo "$HOSTNAME_NEW" > "$TARGET/etc/hostname"
cat > "$TARGET/etc/hosts" << EOF
127.0.0.1 localhost
127.0.1.1 $HOSTNAME_NEW
EOF

if [ -n "$PASS1" ]; then
    echo "duoples:$PASS1" | chroot "$TARGET" chpasswd
fi

# --- bootloader ---------------------------------------------------------------
for d in dev proc sys run; do
    mount --bind "/$d" "$TARGET/$d"
done

# The installed system must not keep the live session's passwordless sudo
rm -f "$TARGET/etc/sudoers.d/90-duoples-live"

mkdir -p "$TARGET/boot/grub"
cat > "$TARGET/boot/grub/grub.cfg" << EOF
set default=0
set timeout=5

menuentry "Duoples Linux 1.1 LTS" {
    search --no-floppy --fs-uuid --set=root $ROOT_UUID
    linux /boot/vmlinuz-6.6.80-duoples root=UUID=$ROOT_UUID rw console=tty0 console=ttyAMA0
}

menuentry "Duoples Linux 1.1 LTS (console)" {
    search --no-floppy --fs-uuid --set=root $ROOT_UUID
    linux /boot/vmlinuz-6.6.80-duoples root=UUID=$ROOT_UUID rw console=tty0 console=ttyAMA0 systemd.unit=multi-user.target
}
EOF

if ! chroot "$TARGET" grub-install --target=arm64-efi \
        --efi-directory=/boot/efi --boot-directory=/boot \
        --removable --no-nvram 2>&1 | zenity --progress --pulsate --auto-close --no-cancel --width=520 \
        --title="$TITLE" --text="Installing the GRUB bootloader..."; then
    err "GRUB installation failed. The system may not boot. See $LOG."
fi

for d in run sys proc dev; do
    umount "$TARGET/$d" 2>/dev/null || true
done
umount "$TARGET/boot/efi" 2>/dev/null || true
umount "$TARGET" 2>/dev/null || true
sync

echo "=== Duoples install finished $(date -Is) ==="

if zenity --question --width=520 --title="$TITLE" \
    --text="Duoples Linux has been installed to $DISK.\n\nRemove the ISO from the virtual machine, then click Reboot." \
    --ok-label="Reboot" --cancel-label="Close"; then
    reboot
fi
