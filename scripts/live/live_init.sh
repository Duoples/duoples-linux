#!/bin/sh
# Duoples Linux live-boot init
export PATH=/bin:/sbin:/usr/bin:/usr/sbin

mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev
mkdir -p /dev/pts /dev/shm /run /tmp /mnt /live/rootfs /live/overlay /live/ro
mount -t devpts devpts /dev/pts
mount -t tmpfs tmpfs /run
mount -t tmpfs tmpfs /tmp

echo "Duoples Linux: searching for live medium..."

LIVE=""
for dev in /dev/sr0 /dev/sr1 /dev/sda /dev/sdb /dev/vda /dev/vdb /dev/sda1 /dev/sdb1 /dev/vda1 /dev/vdb1; do
    [ -b "$dev" ] || continue
    mount -t iso9660 -o ro "$dev" /mnt 2>/dev/null || continue
    if [ -f /mnt/live/filesystem.squashfs ]; then
        LIVE="$dev"
        break
    fi
    umount /mnt 2>/dev/null
done

if [ -z "$LIVE" ]; then
    echo "Duoples Linux: live medium not found. Dropping to emergency shell."
    exec /bin/sh
fi

echo "Duoples Linux: live medium found on $LIVE"

mount -t squashfs -o ro /mnt/live/filesystem.squashfs /live/rootfs || {
    echo "Duoples Linux: failed to mount root filesystem."
    exec /bin/sh
}

mount -t tmpfs -o mode=0755 tmpfs /live/overlay
mkdir -p /live/overlay/upper /live/overlay/work
mount -t overlay -o lowerdir=/live/rootfs,upperdir=/live/overlay/upper,workdir=/live/overlay/work overlay /live/ro || {
    echo "Duoples Linux: failed to create writable overlay."
    exec /bin/sh
}

mkdir -p /live/ro/proc /live/ro/sys /live/ro/dev /live/ro/run /live/ro/tmp /live/ro/mnt/cdrom
mount --bind /proc /live/ro/proc
mount --bind /sys /live/ro/sys
mount --bind /dev /live/ro/dev
mount --bind /run /live/ro/run
mount --bind /mnt /live/ro/mnt/cdrom

echo "Duoples Linux: starting system..."
exec switch_root /live/ro /sbin/init
