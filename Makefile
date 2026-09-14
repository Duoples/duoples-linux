# Duoples Linux Makefile
OUT_DIR = out

.PHONY: all full test clean

all:
	@echo '[*] Duoples Linux build artifacts ready in out/'

full:
	@echo '[*] Building Full Duoples Linux...'
	@bash ./build_duoples_linux.sh

test:
	@qemu-system-aarch64 -M virt -cpu cortex-a57 -m 256M -kernel out/Image.gz -initrd out/rootfs.cpio.gz -append 'console=ttyAMA0 earlycon=pl011,0x09000000 rdinit=/init panic=1 quiet' -nographic
