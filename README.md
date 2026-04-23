# Haiku ARM64 Build Environment

![Haiku ARM64 Build icon](docs/icon-256.png)

Reproducible build setup for Haiku OS ARM64 on Orange Pi 6 Plus.

## Status: desktop session now launches in the validated ICU74 lane (2026-04-22)

The kernel loads, BFS mounts, `launch_daemon` starts, and the desktop user-session
path now launches successfully in the current validated QEMU lane.

Directly validated in-guest:

- `SetupEnvironment` completes without crashing when the package set is ICU-consistent
  (ICU74 only)
- `app_server` launches
- `Tracker` launches
- `Deskbar` launches
- `package_daemon` reports `/boot/system` consistent with the current ICU74 metadata-fixed test packages

Confirmed causes of prior boot failures, in resolution order:

1. SCSI CCB panic on USB storage emulation → fixed (`a0ee6cf196`)
2. packagefs zstd decompression → worked around with uncompressed repacks
3. `libroot.so` TLSDESC relocation → partially fixed (`daa993f414`, binary unverified)
4. `launch_daemon` env tail parsing → fixed (`5059bc3bc8`)
5. `Thread 51` / `consoled -4` crash on `SetupEnvironment` → **ICU version collision**
   (icu-67.1 + ICU74 coexistence); resolved by using an ICU74-consistent package set

Detailed experiment matrix: [`docs/boot-debug-notes-2026-04-22.md`](docs/boot-debug-notes-2026-04-22.md)

## Quick Start

```sh
make deps        # install prerequisites (once)
make clone       # clone haiku + buildtools repos
make toolchain   # build cross-compiler (~15 min)
make image       # build minimum MMC image (~5 min)
make test        # QEMU smoke test (30s)
```

## Early Validation Harness

For later regression work, the repo now includes a small QEMU desktop harness:

```sh
make desktop-run         # start the validated desktop image under detached tmux
make desktop-capture     # start detached, wait for desktop markers, save screenshot
make desktop-screenshot  # save a framebuffer screenshot from the detached run
make desktop-stop        # stop the detached tmux session
make desktop-validate    # headless validation using injected marker jobs
```

The harness script is:

- `scripts/qemu-desktop-harness.sh`

Current defaults:

- graphical run image: `/workspace/tmp/caseFullDesktop_icu74meta.boot.img`
- validation image: `/workspace/tmp/caseFullDesktop_icu74meta.boot.img`

`make desktop-run` writes a stable tmux/state/monitor setup under:

- `/workspace/tmp/haiku-boot-harness/`

The validation mode boots headlessly, injects a temporary `user_launch` wrapper into a
writable copy of the image, captures the serial log, and verifies launch markers for:

- `app_server`
- `Tracker`
- `Deskbar`

## QEMU Boot (working)

```sh
qemu-system-aarch64 \
  -bios /usr/share/qemu-efi-aarch64/QEMU_EFI.fd \
  -M virt -cpu max -m 2048 \
  -device virtio-scsi-pci \
  -device scsi-hd,drive=x0 \
  -drive file=haiku-mmc.image,if=none,format=raw,id=x0 \
  -device virtio-keyboard-device \
  -device virtio-tablet-device \
  -device ramfb -serial stdio
```

**Note:** Must use `virtio-scsi-pci`, not `virtio-blk-device`.

## Build Host

- Orange Pi 6 Plus (CIX P1, 12 cores, 14 GiB RAM)
- Debian Trixie (aarch64), kernel 6.6.89-cix
- GCC 14.2.0 (host) / 13.3.0 (cross-compiler)

## Repos

- `haiku/` — Haiku source (from review.haiku-os.org)
- `buildtools/` — Cross-compiler + jam
- `haikuporter/` — Package build tool
- `haikuports/` — smrobtzz arm64-fixes branch
- `haikuports.cross/` — smrobtzz update-everything branch
