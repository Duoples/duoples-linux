# ==============================================================================
# Duoples Linux - Multi-Architecture Distribution Makefile
# ==============================================================================

OUT_DIR = out

.PHONY: all full full-arm64 full-amd64 test clean

all: full-arm64

full: full-arm64

full-arm64:
	@echo '[*] Building Duoples Linux (ARM64)...'
	@bash ./build_duoples_linux.sh arm64

full-amd64:
	@echo '[*] Building Duoples Linux (AMD64 / x86_64) via Rosetta 2...'
	@bash ./build_duoples_linux.sh amd64

test:
	@qemu-system-aarch64 -M virt -cpu cortex-a57 -m 256M -kernel out/Image.gz -initrd out/rootfs.cpio.gz -append 'console=ttyAMA0 earlycon=pl011,0x09000000 rdinit=/init panic=1 quiet' -nographic

clean:
	@rm -rf out/*
