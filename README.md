# Duoples Linux

An ultra-minimal, high-performance, and standalone Linux distribution engineered from scratch by Duoples.

## Flavors
1. **Duoples Linux (RAM Edition):**
   - Total Footprint: Under 14 MB (12 MB custom Linux 6.6 LTS kernel + 1.2 MB rootfs).
   - Boot Time: Under 0.5s into interactive shell running entirely in volatile RAM.

2. **Duoples Linux (Full-Fledged Edition):**
   - Standalone distribution with APT package manager, systemd, and OpenSSH.
   - 100% binary compatible with Debian and Ubuntu package ecosystems.

## Building from Scratch
```bash
# Build full Debian-compatible distribution
make full

# Test RAM edition in QEMU emulator
make test
```

## License
Copyright 2026 Duoples. Licensed under Apache 2.0.
