# Haiku ARM64 Repo Notes

This file is the maintainer/operator guide for the repo at:

- `/workspace/projects/haiku-build`

Use it with:

- `README.md`
- `docs/MAINTAINER-CHECKLIST.md`
- `docs/UBOOT-ASSESSMENT.md`
- `docs/boot-debug-notes-2026-04-23.md`

## Identity / environment guardrail

Keep this repo aligned with the current local machine and workflow.

Current authoritative environment:

- host: Orange Pi 6 Plus
- SoC: CIX P1 (`CD8180` / `CD8160` family)
- OS: Debian Trixie (aarch64)
- runtime mode: host-native local workspace
- canonical workspace root: `/workspace`
- repo root: `/workspace/projects/haiku-build`
- default repo branch: `master`

Do not mix this repo's workflow with other boards' boot blobs or boot offsets.
In particular, do **not** import the Orange Pi 4 Pro / Allwinner A733 boot chain
from `/workspace/projects/9front` into this repo.

## What this repo currently owns

This repo currently owns a **reproducible QEMU validation lane** for Haiku ARM64.

That lane covers:

- syncing a stock ARM64 nightly MMC image
- validating that stock nightly in QEMU
- rebuilding a direct-package desktop image on top of that base
- validating the rebuilt image in QEMU
- probing the overlay-minimization matrix

This repo does **not** yet own a complete physical Orange Pi 6 Plus boot lane.
That is a later stage.

## Canonical repo layout

- `haiku/` — Haiku source tree
  - canonical local branch: `arm64-bootstrap-fixes`
- `buildtools/` — Haiku build tools
- `haikuporter/` — package build tool
- `haikuports/` — upstream-ish package tree snapshot used here
- `haikuports.cross/` — local arm64-compatible bootstrap package source path
- `scripts/` — authoritative automation scripts
- `docs/` — repo-level technical notes and maintainer docs
- `Makefile` — canonical entrypoint for normal flows

## Canonical entrypoints

Prefer `make` targets over ad-hoc shell pipelines.

Main targets:

```sh
make nightly-arm64-sync
make stock-validate
make desktop-image
make desktop-refresh
make desktop-probe-overlays
make desktop-run
make desktop-status
make desktop-logs
make desktop-attach
make desktop-screenshot
make desktop-stop
make desktop-validate
```

## Authoritative scripts

- `scripts/fetch-latest-arm64-nightly.sh`
- `scripts/build-validated-desktop-image.sh`
- `scripts/probe-direct-package-overlays.sh`
- `scripts/qemu-desktop-harness.sh`

When editing workflow behavior, read the relevant script fully before changing
it.

## Current known-good state

As of 2026-04-27:

- stock ARM64 nightly validates in QEMU
- the direct-package desktop lane validates in QEMU
- the default modern validated overlay is:
  - direct `haiku.hpkg`
  - `zstd_bootstrap-1.5.6-1-arm64.hpkg`
- `expat_bootstrap` is no longer part of the default validated image
- the validated direct package now prunes:
  - `demos/Cortex`
  - `data/deskbar/menu/Demos/Cortex`
- the remaining blocker is `libzstd.so.1`
- the locally available normal `zstd-1.5.6-1-arm64.hpkg` is currently a stub and
  does not provide the runtime library

Current overlay probe expectations:

- `stock` → pass
- `direct_only` → fail
- `direct_plus_expat` → fail
- `direct_plus_zstd` → pass
- `direct_plus_zstd_expat` → pass

## Canonical artifact paths

### Managed nightly base

- `/workspace/tmp/haiku-nightly-arm64/haiku-master-arm64-current-mmc.image`
- `/workspace/tmp/haiku-nightly-arm64/haiku-master-arm64-current-mmc.zip`

### Built outputs

- `/workspace/tmp/haiku-build/validated/haiku-arm64-icu74-desktop.boot.img`
- `/workspace/tmp/haiku-build/validated/haiku-direct-icu74.hpkg`
- `/workspace/tmp/haiku-build/validated/compat_bootstrap_runtime-1-2-arm64.hpkg`

### Logs / validation products

- `/workspace/tmp/haiku-boot-harness/`
- `/workspace/tmp/haiku-overlay-probe/summary.md`
- `/workspace/tmp/haiku-overlay-probe/summary.tsv`
- `/workspace/tmp/haiku-overlay-probe/*.validate.log`

## Workflow rules

### Before editing

1. read the relevant script(s) and docs first
2. identify whether the change affects:
   - nightly sync
   - image assembly
   - harness validation
   - overlay probe logic
   - docs only
3. keep the simplest working path

### After editing

Run the relevant validation targets.

Minimum expectations:

- script changes must be tested with the corresponding `make` target(s)
- package composition changes must be tested with `make desktop-validate`
- overlay expectation changes must be tested with `make desktop-probe-overlays`
- workflow changes should update docs in the same tranche

### Before declaring done

- inspect `git diff`
- confirm the relevant validation targets passed
- update docs if the observed truth changed

## Validation matrix by change type

### `scripts/fetch-latest-arm64-nightly.sh`

Run:

```sh
make nightly-arm64-sync
make stock-validate
```

### `scripts/build-validated-desktop-image.sh`

Run:

```sh
make desktop-image
make desktop-validate
```

Also run `make desktop-probe-overlays` if package composition or expectations changed.

### `scripts/qemu-desktop-harness.sh`

Run:

```sh
make stock-validate
make desktop-validate
```

And if run/capture/session handling changed:

```sh
make desktop-run
make desktop-status
make desktop-stop
```

### `scripts/probe-direct-package-overlays.sh`

Run:

```sh
make desktop-probe-overlays
```

## Documentation policy

When state changes, update the matching docs immediately.

Core docs to keep aligned:

- `README.md`
- `docs/boot-debug-notes-2026-04-23.md`
- `docs/MAINTAINER-CHECKLIST.md`
- `docs/UBOOT-ASSESSMENT.md`
- `AGENTS.md`

Also keep the local workspace note aligned:

- `/workspace/notes/haiku-arm64-build.md`

## Known caveats

- the QEMU lane is authoritative today; physical board boot is not yet the main lane
- the repo still keeps a legacy fallback path for older base images
- `zstd_bootstrap` remains necessary in the modern default lane
- `HAIKU_NO_DOWNLOADS=1` local fallback behavior still matters because the newer
  full upstream arm64 package set is not yet fully available locally

## Physical Orange Pi 6 Plus bring-up policy

The current recommendation is:

- keep using QEMU `virt` + UEFI as the software-validation authority
- when starting physical board boot, prefer the board's current EFI-facing boot
  surface first
- only create a repo-owned U-Boot lane if the EFI-first path proves inadequate

For the reasoning and the comparison against the local 9front work, read:

- `docs/UBOOT-ASSESSMENT.md`

## Current observed Orange Pi 6 Plus boot facts

Observed on this host:

- `/sys/firmware/efi` exists
- the ESP is `/dev/nvme0n1p1`
- the ESP contains:
  - `EFI/BOOT/BOOTAA64.EFI`
  - `GRUB/GRUB.CFG`
  - `IMAGE`
  - `ROOTFS.CPIO.GZ`
  - `SKY1-ORANGEPI-6-PLUS.DTB`
- the GRUB config includes a serial console setting of `ttyAMA2,115200`

Treat that as the current board-boot observation baseline until a dedicated
Orange Pi 6 Plus Haiku boot path exists.

## Maintainer priorities

1. remove or replace the remaining `zstd_bootstrap` dependency
2. collapse unnecessary control cases from the overlay probe
3. decide when to retire the legacy fallback path
4. only then push deeper into physical Orange Pi 6 Plus bring-up

## Hard guardrails

- do not delete or corrupt `/workspace/tmp` artifacts that are still being used
  for validation/debugging without good reason
- do not mix 9front Orange Pi 4 Pro blobs with this repo's Orange Pi 6 Plus work
- do not declare a workflow change complete without rerunning the relevant Make
  targets
- do not let docs drift away from the observed validation state