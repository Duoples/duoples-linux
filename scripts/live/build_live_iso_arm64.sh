#!/bin/bash
# Build the graphical Duoples Linux ARM64 live ISO.
#
# Prerequisites on an ARM64 build host:
#   - a prepared Ubuntu/Debian rootfs at $ROOTFS_DIR (see prepare_live_rootfs.sh)
#   - a kernel with CONFIG_SQUASHFS, CONFIG_SQUASHFS_XZ, CONFIG_OVERLAY_FS=y
#   - mksquashfs, xorriso, grub-mkstandalone, mtools, cpio, gzip
#
# Environment overrides:
#   WORK_DIR, ROOTFS_DIR, ISO_DIR, OUT_DIR, KERNEL_IMAGE, ARTIFACTS_DIR
set -e

WORK_DIR="${WORK_DIR:-/home/duoples-linux}"
ROOTFS_DIR="${ROOTFS_DIR:-${WORK_DIR}/full_rootfs}"
ISO_DIR="${ISO_DIR:-${WORK_DIR}/iso_arm64}"
OUT_DIR="${OUT_DIR:-${WORK_DIR}/out}"
KERNEL_IMAGE="${KERNEL_IMAGE:-${WORK_DIR}/src/linux-6.6.80/arch/arm64/boot/Image.gz}"
ARTIFACTS_DIR="${ARTIFACTS_DIR:-}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=================================================="
echo " Building Bootable Duoples Linux 1.1 LTS ARM64 ISO"
echo "=================================================="

mkdir -p "${ISO_DIR}/live" "${ISO_DIR}/boot/grub" "${OUT_DIR}"

# 1. Build a fresh compressed SquashFS from the live root filesystem
echo "[*] Building compressed SquashFS filesystem..."
rm -f "${ISO_DIR}/live/filesystem.squashfs"
mksquashfs "${ROOTFS_DIR}" "${ISO_DIR}/live/filesystem.squashfs" \
    -comp gzip -Xcompression-level 6 -b 1048576 -noappend -processors 4 \
    -e dev proc sys run tmp var/tmp var/cache/apt var/lib/apt/lists mnt media lost+found

# 2. Copy Linux kernel
echo "[*] Copying Linux kernel..."
if [ -f "${KERNEL_IMAGE}" ]; then
    cp -v "${KERNEL_IMAGE}" "${OUT_DIR}/Image.gz"
fi
if [ ! -f "${OUT_DIR}/Image.gz" ]; then
    echo "ERROR: no kernel image at ${OUT_DIR}/Image.gz" >&2
    exit 1
fi
cp "${OUT_DIR}/Image.gz" "${ISO_DIR}/live/vmlinuz"

# 3. Build live initramfs (BusyBox base + live-boot init)
#    Reuses the existing initramfs in the ISO tree as the BusyBox base.
echo "[*] Building live initramfs..."
if [ ! -f "${ISO_DIR}/live/initrd.img" ]; then
    echo "ERROR: no base initramfs at ${ISO_DIR}/live/initrd.img" >&2
    exit 1
fi
rm -rf "${WORK_DIR}/initrd_build"
mkdir -p "${WORK_DIR}/initrd_build"
cd "${WORK_DIR}/initrd_build"
zcat "${ISO_DIR}/live/initrd.img" | cpio -idm --quiet
cp "${SCRIPT_DIR}/live_init.sh" init
chmod +x init
find . -print0 | cpio --null -o -H newc --quiet | gzip -9 > "${OUT_DIR}/live_initrd.cpio.gz"
cp "${OUT_DIR}/live_initrd.cpio.gz" "${ISO_DIR}/live/initrd.img"
cd "${WORK_DIR}"

# 4. GRUB EFI boot configuration
cat << GRUB > "${ISO_DIR}/boot/grub/grub.cfg"
insmod efi_gop
insmod font
if loadfont /boot/grub/fonts/unicode.pf2 ; then
    insmod gfxterm
    set gfxmode=auto
    set gfxpayload=keep
    terminal_output gfxterm
fi

search --file --set=root /live/vmlinuz
set default=0
set timeout=5

menuentry "Duoples Linux 1.1 LTS (ARM64 Live)" {
    search --file --set=root /live/vmlinuz
    linux /live/vmlinuz console=tty0 console=ttyAMA0
    initrd /live/initrd.img
}

menuentry "Install Duoples Linux on this computer" {
    search --file --set=root /live/vmlinuz
    linux /live/vmlinuz console=tty0 console=ttyAMA0 duoples.installer=1
    initrd /live/initrd.img
}

menuentry "Duoples Linux 1.1 LTS (ARM64 Console)" {
    search --file --set=root /live/vmlinuz
    linux /live/vmlinuz console=tty0 console=ttyAMA0 systemd.unit=multi-user.target
    initrd /live/initrd.img
}
GRUB

# 5. Generate EFI boot image
echo "[*] Generating UEFI bootloader..."
mkdir -p "${ISO_DIR}/EFI/BOOT"
grub-mkstandalone \
    --format=arm64-efi \
    --output="${ISO_DIR}/EFI/BOOT/BOOTAA64.EFI" \
    --locales="" \
    --fonts="" \
    "boot/grub/grub.cfg=${ISO_DIR}/boot/grub/grub.cfg"

dd if=/dev/zero of="${ISO_DIR}/boot/grub/efi.img" bs=1M count=8 status=none
mkfs.vfat "${ISO_DIR}/boot/grub/efi.img" >/dev/null
mmd -i "${ISO_DIR}/boot/grub/efi.img" ::efi ::efi/boot
mcopy -i "${ISO_DIR}/boot/grub/efi.img" "${ISO_DIR}/EFI/BOOT/BOOTAA64.EFI" ::efi/boot/

# 6. Build Hybrid Bootable ISO with xorriso
echo "[*] Authoring bootable ISO image..."
rm -f "${OUT_DIR}/duoples-linux-1.1-arm64.iso"
xorriso -as mkisofs \
    -r -V "DUOPLES_LINUX_1_1_ARM64" \
    -append_partition 2 0xef "${ISO_DIR}/boot/grub/efi.img" \
    -e --interval:appended_partition_2:all:: \
    -no-emul-boot \
    -o "${OUT_DIR}/duoples-linux-1.1-arm64.iso" \
    "${ISO_DIR}" 2>&1 | tail -n 10

# 7. Optionally publish to an artifacts directory
if [ -n "${ARTIFACTS_DIR}" ] && [ -d "${ARTIFACTS_DIR}" ]; then
    rm -f "${ARTIFACTS_DIR}/duoples-linux-1.1-arm64.iso"
    cp -v "${OUT_DIR}/duoples-linux-1.1-arm64.iso" "${ARTIFACTS_DIR}/duoples-linux-1.1-arm64.iso"
fi

ISO_SIZE=$(du -sh "${OUT_DIR}/duoples-linux-1.1-arm64.iso" | awk '{print $1}')
SHA256=$(sha256sum "${OUT_DIR}/duoples-linux-1.1-arm64.iso" | awk '{print $1}')

echo "=================================================="
echo " Duoples Linux ARM64 Bootable ISO Ready!"
echo " ISO: ${OUT_DIR}/duoples-linux-1.1-arm64.iso (${ISO_SIZE})"
echo " SHA256: ${SHA256}"
echo "=================================================="
