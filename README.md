# Haiku ARM64 Build Environment

> [!IMPORTANT]
> **Disclaimer:** this is not an official effort to get Haiku up and running on Orange Pi hardware — this is a personal effort, and judging by [the Haiku project's reaction](https://discuss.haiku-os.org/t/ai-build-harness-for-arm/19142), it will remain just that. After this scaffolding is finished and I have [`rcarmo/9front`](https://github.com/rcarmo/9front) booting on the target hardware, I will try to build an equivalent U-Boot path for Haiku and publish it as MIT — and if nobody takes it, that is perfectly fine with me.

![Haiku ARM64 Build icon](docs/icon-256.png)

Reproducible build setup for Haiku OS ARM64 with a full-package QEMU validation lane and early Orange Pi 4 Pro bring-up planning.

## Status: Boots to Desktop from the Full Direct Package Lane (2026-04-27)

Haiku ARM64 now **boots to a desktop session in QEMU** from the validated
full direct-package lane. The kernel loads, BFS mounts, `launch_daemon` starts,
`package_daemon` reports `/boot/system` consistent, and the desktop user-session
comes up far enough to launch `app_server`, `Tracker`, and `Deskbar`.

Latest reduction (2026-04-27): the default validated overlay dropped
`expat_bootstrap`. The validated direct package now prunes the optional Cortex
demo and its Deskbar entry, so the modern default overlay is down to a local
`zstd_runtime` package only.

Focused follow-up validation on 2026-04-27 confirmed that the normal local
ARM64 `zstd-1.5.6-1-arm64.hpkg` is still only a stub package, while a minimal
local `zstd_runtime-1.5.6-1-arm64.hpkg` built from the `zstd_bootstrap` library
payload validates cleanly as a replacement. The checked-in builder now emits
that smaller runtime package by default, so the remaining requirement is now
known to be the shared zstd runtime itself, not the broader bootstrap package.

The automation lane now also covers:

- syncing the latest stock ARM64 nightly base image
- validating that stock nightly directly
- rebuilding the direct-package overlay image on top of the managed base
- probing the current overlay-minimization matrix (`stock`, `direct_only`,
  `direct_plus_expat`, `direct_plus_zstd`, `direct_plus_zstd_expat`)

2026-04-30 follow-up: the `haiku/arm64-bootstrap-fixes` branch also restores the
local `HAIKU_NO_DOWNLOADS=1` `@minimum-mmc` path by making the arm64 fallback
packages explicit (`noto`, `ncurses6`, and `zstd`). `make image` and the 30s
`make test` QEMU smoke target pass again on the Orange Pi 6 Plus build host.

![QEMU desktop capture with Tracker visible](docs/haiku-desktop-tracker-qemu-2026-04-23.png)

_This screenshot shows the current validated boot lane with Tracker visible. The
current image now uses the full direct `haiku.hpkg` package on a grown system
partition and now rides on top of the newer rebootstrapped stock arm64
nightly bootstrap package set. The current overlay is now down to a generated
local `zstd_runtime` package only; the validated direct package also prunes the
optional Cortex demo so it no longer needs `lib:libexpat` just to keep
`/boot/system` solver-consistent. The older `compat_bootstrap_runtime` and
repacked shell-package workarounds are no longer part of the default validated
image._

Directly validated in-guest:

- `SetupEnvironment` completes without crashing when the package set is ICU-consistent
  (ICU74 only)
- `app_server` launches
- `Tracker` launches
- `Deskbar` launches
- `package_daemon` reports `/boot/system` consistent with the current direct-package test image

Confirmed causes of prior boot failures, in resolution order:

1. SCSI CCB panic on USB storage emulation → fixed (`a0ee6cf196`)
2. packagefs zstd decompression → worked around with uncompressed repacks
3. `libroot.so` TLSDESC relocation → partially fixed (`daa993f414`, binary unverified)
4. `launch_daemon` env tail parsing → fixed (`5059bc3bc8`)
5. `Thread 51` / `consoled -4` crash on `SetupEnvironment` → **ICU version collision**
   (icu-67.1 + ICU74 coexistence); resolved by using an ICU74-consistent package set

Detailed experiment matrix: [`docs/boot-debug-notes-2026-04-23.md`](docs/boot-debug-notes-2026-04-23.md)

Focused zstd follow-up: [`docs/ZSTD-RUNTIME-VALIDATION-2026-04-27.md`](docs/ZSTD-RUNTIME-VALIDATION-2026-04-27.md)

Maintainer docs:

- [`docs/MAINTAINER-CHECKLIST.md`](docs/MAINTAINER-CHECKLIST.md)
- [`docs/UBOOT-ASSESSMENT.md`](docs/UBOOT-ASSESSMENT.md)
- [`docs/DRIVER-SCAFFOLD-PLAN.md`](docs/DRIVER-SCAFFOLD-PLAN.md)
- [`AGENTS.md`](AGENTS.md)

Current targeting split:

- authoritative software target: the full direct-package QEMU lane
- first physical target: **Orange Pi 4 Pro** (`orangepi4pro`, Allwinner A733 / `sun60iw2`)
- the local Orange Pi 6 Plus remains the build host and a historical host-boot
  reference only; it is **not** the first physical Haiku target anymore

Historical local-host boot snapshot still checked into the repo:

- [`bootstrap/orangepi6plus/host-efi-2026-04-27/`](bootstrap/orangepi6plus/host-efi-2026-04-27/)

## Quick Start

```sh
make deps        # install prerequisites (once)
make clone       # clone haiku + buildtools repos
make toolchain   # build cross-compiler (~15 min)
make bfs-fuse    # build/link host BFS FUSE helper for validation scripts
make nightly-arm64-sync  # fetch latest stock arm64 nightly base image
make image       # build minimum MMC image (~5 min)
make test        # QEMU smoke test (30s)
make full-image  # alias for desktop-image; full direct-package QEMU image
```

## Early Validation Harness

For later regression work, the repo now includes a small QEMU desktop harness.
The new `full-*` targets are the preferred names for the authoritative full-QEMU
lane; the older `desktop-*` names remain as compatibility aliases.

The core validation image can also be emitted as both raw and qcow2 artifacts:

```sh
make validation-artifacts HREV=59671 \
  HAIKU_REMOTE=https://github.com/rcarmo/haiku.git \
  HAIKU_BRANCH=arm64-bootstrap-fixes
```

This writes:

- `/workspace/tmp/haiku-build/validated/haiku-arm64-icu74-desktop.boot.img`
- `/workspace/tmp/haiku-build/validated/haiku-arm64-icu74-desktop.qcow2`
- `/workspace/tmp/haiku-build/validated/SHA256SUMS`

GitHub Actions runs the image flow for pushed tags matching `hrev*` (for
example `hrev59677`) or via manual `workflow_dispatch` on GitHub-hosted ARM64
Linux runners. It uploads three downloadable workflow artifacts:

- `haiku-arm64-validation-hrevNNNNN` — core raw/qcow2 validation image plus checksums
- `haiku-arm64-full-prototype-hrevNNNNN` — full prototype raw/qcow2 image plus checksums
- `haiku-arm64-utm-ios-virtio-hrevNNNNN` — UTM/iOS VirtIO minimum qcow2, README, checksums, and smoke log

For a UTM/iOS-friendly minimum bootstrap-style qcow2, run:

```sh
make utm-ios-smoke
```

This writes `/workspace/tmp/haiku-build/utm-ios/haiku-arm64-minimum-utm-ios.qcow2`
and smoke-tests it with QEMU `virt` using a VirtIO block disk. In UTM for iOS,
attach it as a **VirtIO** disk. The minimum image includes `virtio_block` in
`haiku.hpkg` so the kernel can rediscover and mount the boot partition after the
UEFI loader hands off.

For the full standard-image prototype, run:

```sh
make full-standard-artifacts HREV=59671 \
  HAIKU_REMOTE=https://github.com/rcarmo/haiku.git \
  HAIKU_BRANCH=arm64-bootstrap-fixes
```

This writes:

- `/workspace/tmp/haiku-build/full/haiku-arm64-icu74-full.boot.img`
- `/workspace/tmp/haiku-build/full/haiku-arm64-icu74-full.qcow2`
- `/workspace/tmp/haiku-build/full/SHA256SUMS`

The prototype keeps the regular direct `haiku.hpkg` package contents/metadata
and validates in QEMU, but still carries a temporary local
`release_requirements_shim` package until the remaining ARM64 HaikuPorts
providers are built or imported. Audit that closure with:

```sh
make release-audit
```

This writes `/workspace/tmp/haiku-release-audit/summary.md` and records which
regular-package requirements are already satisfied by the stock base/local
packages and which ARM64 providers still need real packages.

```sh
make bfs-fuse             # build/link host BFS FUSE helper at /workspace/tmp/bfs_fuse
make full-sync            # alias for nightly-arm64-sync
make full-stock-validate  # alias for stock-validate
make full-image           # alias for desktop-image
make validation-artifacts # build + validate core raw image and emit qcow2 + SHA256SUMS
make full-standard-artifacts # build + validate full prototype raw/qcow2 + SHA256SUMS
make full-validate        # alias for desktop-validate
make full-probe-overlays  # alias for desktop-probe-overlays
make full-check           # run the full regression lane above in order
make full-run             # alias for desktop-run
make full-status          # alias for desktop-status
make full-logs            # alias for desktop-logs
make full-attach          # alias for desktop-attach
make full-screenshot      # alias for desktop-screenshot
make full-stop            # alias for desktop-stop
make orangepi6plus-efi-snapshot # historical local-host EFI/GRUB snapshot helper
```

Key automation scripts:

- `make bfs-fuse` ensures `/workspace/tmp/bfs_fuse` points at the host-built
  `bfs_fuse` helper before the image/harness/probe scripts mount BFS partitions.
- `scripts/fetch-latest-arm64-nightly.sh`
- `scripts/build-validated-desktop-image.sh`
- `scripts/probe-direct-package-overlays.sh`
- `scripts/qemu-desktop-harness.sh`
- `scripts/snapshot-orangepi6plus-efi.sh` (historical local-host snapshot helper)

Current defaults:

- managed base nightly symlink: `/workspace/tmp/haiku-nightly-arm64/haiku-master-arm64-current-mmc.image`
- built desktop image: `/workspace/tmp/haiku-build/validated/haiku-arm64-icu74-desktop.boot.img`
- direct package: `/workspace/tmp/haiku-build/validated/haiku-direct-icu74.hpkg`
- compat package artifact (legacy fallback only): `/workspace/tmp/haiku-build/validated/compat_bootstrap_runtime-1-2-arm64.hpkg`
- generated zstd runtime package: `/workspace/tmp/haiku-build/validated/zstd_runtime-1.5.6-1-arm64.hpkg`
- graphical run image: same as above
- validation image: same as above

`make full-image` (alias: `make desktop-image`) now assembles the reproducible local ICU74 desktop image from:

- the generated direct `haiku.hpkg` contents
- a grown system partition (currently 512 MiB)
- the stock rebootstrapped arm64 nightly bootstrap package set from the base image
- `/workspace/tmp/haiku-build/validated/zstd_runtime-1.5.6-1-arm64.hpkg`

That local `zstd_runtime` artifact is generated from the `zstd_bootstrap`
shared-library payload so the modern lane carries only the narrower runtime
provider that desktop validation actually needs.

The validated direct package also prunes the optional `demos/Cortex` binary and
its Deskbar symlink so the package no longer advertises a hard `lib:libexpat`
requirement for desktop validation.

For older base images, the script still has a legacy fallback path that injects
`compat_bootstrap_runtime` plus sanitized bootstrap `bash`/`coreutils` packages.

`make full-run` (alias: `make desktop-run`) is the primary async path. It returns immediately and writes a
stable tmux/state/monitor setup under:

- `/workspace/tmp/haiku-boot-harness/`

For interactive follow-up after `make full-run`:

- `make full-status`
- `make full-logs`
- `make full-attach`
- `make full-screenshot`

`make full-capture` (alias: `make desktop-capture`) still exists as a blocking
convenience target, but it is not required for the normal async workflow.

The validation mode boots headlessly, injects additive temporary `user_launch` jobs into a
writable copy of the image, captures the serial log, and verifies launch markers for:

- `app_server`
- `Tracker`
- `Deskbar`

`make nightly-arm64-sync` is now the canonical way to keep the base image current.
It downloads the newest available ARM64 nightly MMC zip, extracts it under
`/workspace/tmp/haiku-nightly-arm64/`, and updates a stable symlink that the
image-builder consumes by default.

`make full-probe-overlays` (alias: `make desktop-probe-overlays`) automates the current overlay-minimization matrix.
It now uses a 300s per-case validation timeout by default because the hrev59671
stock ARM64 nightly can launch Deskbar too late for the older 120s probe budget.
It validates:

- stock nightly
- direct package only
- direct + `expat_bootstrap`
- direct + current zstd overlay (`zstd_runtime` by default)
- direct + current zstd overlay + `expat_bootstrap`

The current expected outcomes are:

- `stock` → pass
- `direct_only` → fail
- `direct_plus_expat` → fail
- `direct_plus_zstd` → pass
- `direct_plus_zstd_expat` → pass

This keeps `expat_bootstrap` in the probe as a control case even though it is no
longer part of the default validated image.

The checked-in probe now defaults `ZSTD_HPKG` to the generated local
`zstd_runtime` package, matching the builder's modern default:
[`docs/ZSTD-RUNTIME-VALIDATION-2026-04-27.md`](docs/ZSTD-RUNTIME-VALIDATION-2026-04-27.md).

and writes both per-case validation logs and a Markdown/TSV summary under:

- `/workspace/tmp/haiku-overlay-probe/summary.md`
- `/workspace/tmp/haiku-overlay-probe/summary.tsv`
- `/workspace/tmp/haiku-overlay-probe/*.validate.log`

## Current priorities

1. keep the core validation QEMU lane authoritative and boring
2. replace the full standard prototype's temporary `release_requirements_shim`
   by building/importing the missing ARM64 providers reported by `make release-audit`
3. retire the remaining local `zstd_runtime` shim when upstream/local package
   coverage grows a real `libzstd` provider
4. use the full-QEMU lane to sketch the driver scaffolding we will eventually
   need for Orange Pi 4 Pro bring-up, starting with:
   - FDT/board hooks
   - early serial + interrupt + timer plumbing
   - clock/reset/pinctrl stubs
   - MMC/eMMC, GMAC ethernet, USB XHCI, PCIe/NVMe, and framebuffer/display paths

See also:

- [`docs/DRIVER-SCAFFOLD-PLAN.md`](docs/DRIVER-SCAFFOLD-PLAN.md)
- [`docs/UBOOT-ASSESSMENT.md`](docs/UBOOT-ASSESSMENT.md)

## Target Hardware / Validation Profiles

### Current automated validation target: QEMU `virt` ARM64 machine

The current reproducible validation lane targets QEMU's generic ARM64 `virt`
platform with the following effective hardware profile:

- machine: `virt`
- CPU model: `max`
- architecture: AArch64 / ARMv8+
- RAM: 2048 MiB during automated validation
- firmware: `QEMU_EFI.fd` (AArch64 UEFI)
- primary boot medium: USB-attached raw MMC-style disk image in QEMU
- display device: `ramfb`
- input devices: virtio keyboard + tablet for interactive runs
- network device: virtio-net
- storage/controller path used by validation: USB storage view of the raw image
- interrupt controller discovered in guest logs: GICv2
- serial console path: PL011 UART via QEMU `-nographic`

This is the current authoritative hardware profile for CI-like desktop boot
validation.

### Build host

The build and automation environment currently runs on an Orange Pi 6 Plus.
That host remains the local machine for reproducible builds, but it is no longer
our first physical Haiku bring-up target.

Current local hardware profile:

- board: Orange Pi 6 Plus
- SoC: CIX P1 (`CD8180` / `CD8160` family)
- CPU topology: 12 CPU cores
- RAM class: 16 GB (about 14 GiB visible to Linux)
- primary storage: NVMe (`/dev/nvme0n1`)
  - EFI: `/dev/nvme0n1p1`
  - root: `/dev/nvme0n1p2`
  - swap: `/dev/nvme0n1p3`
- primary LAN interface: `enP1p49s0`
- OS: Debian Trixie (aarch64)

Historical local-host EFI/GRUB snapshot:

- [`bootstrap/orangepi6plus/host-efi-2026-04-27/`](bootstrap/orangepi6plus/host-efi-2026-04-27/)

### First physical bring-up target: Orange Pi 4 Pro

The first real-board target is now **Orange Pi 4 Pro**, matching the board under
active bring-up in the local 9front repo.

Board identity and currently relevant facts:

- board: Orange Pi 4 Pro
- SoC: Allwinner A733 (`sun60iw2`)
- debug UART: UART0 at `0x02500000`
- expected serial settings: `115200` 8N1
- boot priority: SD/TF card before eMMC
- vendor DTB reference: `sun60i-a733-orangepi-4-pro.dtb`
- known-good vendor boot-chain layout from the 9front repo:
  - 8 KiB: `boot0`
  - 16.8 MiB: `boot_package`
  - 32 MiB+: FAT partition with boot payloads

Reference material currently lives in the 9front repo:

- `/workspace/projects/9front/README.md`
- `/workspace/projects/9front/docs/BOARD-NOTES.md`
- `/workspace/projects/9front/docs/BRINGUP-STATUS.md`
- `/workspace/projects/9front/bootstrap/orangepi4pro/vendor-debian-1.0.6/`

For the current Haiku-side physical boot strategy and the driver-scaffold plan,
see:

- [`docs/UBOOT-ASSESSMENT.md`](docs/UBOOT-ASSESSMENT.md)
- [`docs/DRIVER-SCAFFOLD-PLAN.md`](docs/DRIVER-SCAFFOLD-PLAN.md)

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

- board: Orange Pi 6 Plus
- SoC: CIX P1 (`CD8180` / `CD8160` family)
- CPU: 12 cores
- RAM: ~14 GiB visible to Linux
- storage: NVMe root on `/dev/nvme0n1p2`
- OS: Debian Trixie (aarch64), kernel 6.6.89-cix
- compiler toolchain: GCC 14.2.0 (host) / 13.3.0 (cross-compiler)

## Repos

- `haiku/` — Haiku source (from review.haiku-os.org)
- `buildtools/` — Cross-compiler + jam
- `haikuporter/` — Package build tool
- `haikuports/` — smrobtzz arm64-fixes branch
- `haikuports.cross/` — smrobtzz update-everything branch

## Current Caveats

The direct package lane now validates end-to-end, but it is not fully de-hacked yet.
The remaining deliberate shim in the current default validated lane is:

- `/workspace/tmp/haiku-build/validated/zstd_runtime-1.5.6-1-arm64.hpkg`

That package is generated locally from the `zstd_bootstrap` shared-library
payload so the modern lane carries only the narrower runtime provider it still
needs.

`expat_bootstrap` is no longer part of the default validated image. The current
validated package instead prunes the optional Cortex demo to avoid carrying a
package-level `lib:libexpat` dependency that only mattered for that demo.

The remaining zstd issue is currently structural, not just documentation debt:

- the current stock nightly base still does not carry `libzstd.so.1`
- the locally available normal `zstd-1.5.6-1-arm64.hpkg` is only a stub package
  and does **not** provide the shared library
- so the validated direct lane still needs the generated local `zstd_runtime`
  package (or some other `lib:libzstd` provider) until the stock base or the
  normal arm64 package set changes

A legacy fallback path is still kept in the builder for older base images, where
it can inject `compat_bootstrap_runtime` plus sanitized bootstrap shell packages.

For the current modern lane, the builder has now been switched to the smaller
`zstd_runtime` package by default. The remaining open decision is when that
local generation step can be retired in favor of the stock base / normal arm64
package path growing a proper `libzstd` provider.

The `haiku/` branch `arm64-bootstrap-fixes` also now includes a merge of current
`upstream/master`, but still keeps an arm64 `HAIKU_NO_DOWNLOADS=1` fallback to
`HaikuPortsCross` because the newer upstream remote package set is not yet fully
available in this local workspace.
