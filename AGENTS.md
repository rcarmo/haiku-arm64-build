# Haiku ARM64 Repo Notes

This file is the maintainer/operator guide for the repo at:

- `/workspace/projects/haiku-build`

Use it with:

- `README.md`
- `docs/MAINTAINER-CHECKLIST.md`
- `docs/UBOOT-ASSESSMENT.md`
- `docs/DRIVER-SCAFFOLD-PLAN.md`
- `docs/boot-debug-notes-2026-04-23.md`

## Identity / environment guardrail

Keep this repo aligned with the current local machine and workflow.

Current authoritative environment:

- host: Orange Pi 6 Plus
- host SoC: CIX P1 (`CD8180` / `CD8160` family)
- OS: Debian Trixie (aarch64)
- runtime mode: host-native local workspace
- canonical workspace root: `/workspace`
- repo root: `/workspace/projects/haiku-build`
- default repo branch: `master`
- first physical Haiku target: Orange Pi 4 Pro (`orangepi4pro`, Allwinner A733 / `sun60iw2`)

Do not mix this repo's workflow with unrelated boards' boot blobs or offsets.
For the current first physical target, use the Orange Pi 4 Pro / A733 facts from
`/workspace/projects/9front` as the board reference, but do **not** blindly copy
9front kernels, wrappers, or vendor blobs into this repo without provenance and a
clear Haiku-side reason.

## What this repo currently owns

This repo currently owns a **reproducible full-package QEMU validation lane**
for Haiku ARM64.

That lane covers:

- syncing a stock ARM64 nightly MMC image
- validating that stock nightly in QEMU
- rebuilding a direct-package desktop image on top of that base
- validating the rebuilt image in QEMU
- probing the overlay-minimization matrix
- providing the software-side baseline we will use to sketch later driver scaffolding

This repo does **not** yet own a complete physical Orange Pi 4 Pro boot lane.
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

Preferred full-QEMU targets:

```sh
make bfs-fuse
make full-sync
make full-stock-validate
make full-image
make validation-artifacts HREV=<hrev-number> HAIKU_REMOTE=https://github.com/rcarmo/haiku.git HAIKU_BRANCH=arm64-bootstrap-fixes
make full-standard-artifacts HREV=<hrev-number> HAIKU_REMOTE=https://github.com/rcarmo/haiku.git HAIKU_BRANCH=arm64-bootstrap-fixes
make utm-ios-smoke
make release-audit
make full-refresh
make full-probe-overlays
make full-run
make full-status
make full-logs
make full-attach
make full-screenshot
make full-stop
make full-validate
make full-check
```

Legacy compatibility aliases still exist under the older `desktop-*` names.

Historical local-host helper:

```sh
make orangepi6plus-efi-snapshot
```

## Authoritative scripts

- `.github/workflows/validation-image.yml` — tag-only (`hrev*`) GitHub Actions build for core and full-prototype raw+qcow2 artifacts on ARM64 runners
- `make bfs-fuse` / Haiku `src/tools/bfs_shell` — host BFS FUSE helper bootstrap
- `scripts/fetch-latest-arm64-nightly.sh`
- `scripts/build-validated-desktop-image.sh`
- `scripts/probe-direct-package-overlays.sh`
- `scripts/audit-release-package-closure.sh`
- `scripts/qemu-desktop-harness.sh`
- `scripts/snapshot-orangepi6plus-efi.sh` (historical local-host snapshot helper)

When editing workflow behavior, read the relevant script fully before changing
it.

## Current known-good state

As of 2026-04-30:

- `make full-check` validates the core lane end-to-end in QEMU after `make bfs-fuse` creates
  `/workspace/tmp/bfs_fuse` from the host-built Haiku BFS FUSE helper
- `make full-standard-artifacts` builds and validates a full standard-image
  prototype with unpruned regular `haiku.hpkg` contents/metadata; it currently
  carries a temporary local `release_requirements_shim` until the remaining
  ARM64 HaikuPorts providers are real packages
- `make utm-ios-smoke` builds `/workspace/tmp/haiku-build/utm-ios/haiku-arm64-minimum-utm-ios.qcow2`
  and smoke-tests it with QEMU `virt` using USB storage; for UTM/iOS attach the
  qcow2 as USB storage, not VirtIO, because the current minimum image cannot
  rediscover the boot partition via VirtIO
- stock ARM64 nightly validates in QEMU
- the direct-package desktop lane validates in QEMU
- the local arm64 `HAIKU_NO_DOWNLOADS=1` `@minimum-mmc` path builds and passes
  the 30s `make test` smoke target after making `noto`, `ncurses6`, and `zstd`
  explicit fallback packages in `haiku/Jamfile`
- the default modern validated overlay is:
  - direct `haiku.hpkg`
  - `/workspace/tmp/haiku-build/validated/zstd_runtime-1.5.6-1-arm64.hpkg`
- `expat_bootstrap` is no longer part of the default validated image
- the validated direct package now prunes:
  - `demos/Cortex`
  - `data/deskbar/menu/Demos/Cortex`
- the remaining blocker is `libzstd.so.1`
- the locally available normal `zstd-1.5.6-1-arm64.hpkg` is currently a stub and
  does not provide the runtime library
- the builder now emits the smaller local `zstd_runtime` package from the
  `zstd_bootstrap` shared-library payload so the default lane only carries the
  narrower `lib:libzstd` provider it still needs

Current overlay probe expectations use a 300s per-case timeout by default
(hrev59671 stock can miss the Deskbar marker under the older 120s budget):

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
- `/workspace/tmp/haiku-build/validated/haiku-arm64-icu74-desktop.qcow2`
- `/workspace/tmp/haiku-build/validated/SHA256SUMS`
- `/workspace/tmp/haiku-build/validated/haiku-direct-icu74.hpkg`
- `/workspace/tmp/haiku-build/full/haiku-arm64-icu74-full.boot.img`
- `/workspace/tmp/haiku-build/full/haiku-arm64-icu74-full.qcow2`
- `/workspace/tmp/haiku-build/full/SHA256SUMS`
- `/workspace/tmp/haiku-build/validated/compat_bootstrap_runtime-1-2-arm64.hpkg`
- `/workspace/tmp/haiku-build/validated/zstd_runtime-1.5.6-1-arm64.hpkg`

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
- package composition changes must be tested with `make full-validate`
- overlay expectation changes must be tested with `make full-probe-overlays`
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
make full-image
make full-validate
```

Also run `make full-probe-overlays` if package composition or expectations changed.

### `scripts/qemu-desktop-harness.sh`

Run:

```sh
make full-stock-validate
make full-validate
```

And if run/capture/session handling changed:

```sh
make full-run
make full-status
make full-stop
```

### `scripts/probe-direct-package-overlays.sh`

Run:

```sh
make full-probe-overlays
```

## Documentation policy

When state changes, update the matching docs immediately.

Core docs to keep aligned:

- `README.md`
- `docs/boot-debug-notes-2026-04-23.md`
- `docs/MAINTAINER-CHECKLIST.md`
- `docs/UBOOT-ASSESSMENT.md`
- `docs/DRIVER-SCAFFOLD-PLAN.md`
- `AGENTS.md`

Also keep the local workspace note aligned:

- `/workspace/notes/haiku-arm64-build.md`

## Known caveats

- the QEMU lane is authoritative today; physical board boot is not yet the main lane
- the repo still keeps a legacy fallback path for older base images
- a generated local `zstd_runtime` package is now the modern default lane input
- that package is still a local shim until the stock or normal arm64 package
  path grows a real `libzstd` provider
- `HAIKU_NO_DOWNLOADS=1` local fallback behavior still matters because the newer
  full upstream arm64 package set is not yet fully available locally

## Physical Orange Pi 4 Pro bring-up policy

The current recommendation is:

- keep using the full QEMU `virt` + UEFI lane as the software-validation authority
- treat Orange Pi 4 Pro as the first physical board target
- use `/workspace/projects/9front` as the current source of truth for the board
  identity, vendor boot-chain facts, serial setup, and bring-up notes
- do **not** blindly reuse 9front payloads; when Haiku physical work starts,
  create explicit Haiku-side artifacts and provenance under a board-specific tree
- use the full-QEMU lane to sketch the driver scaffolding before trying to solve
  every board-specific hardware path at once

For the reasoning, board facts, and staging plan, read:

- `docs/UBOOT-ASSESSMENT.md`
- `docs/DRIVER-SCAFFOLD-PLAN.md`

## Historical local Orange Pi 6 Plus host boot facts

A pinned EFI/GRUB snapshot baseline still exists at:

- `bootstrap/orangepi6plus/host-efi-2026-04-27/`

Use `make orangepi6plus-efi-snapshot` to refresh a working-tree snapshot under:

- `/workspace/tmp/orangepi6plus-efi-snapshot/latest`

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

Treat that as a build-host reference only. It is **not** the active first-board
Haiku bring-up target anymore.

## Maintainer priorities

1. keep the full direct-package QEMU lane healthy and authoritative
2. remove or replace the remaining local `zstd_runtime` generation step
   by getting a real `libzstd` provider into the stock or normal arm64 package path
3. collapse unnecessary control cases from the overlay probe and decide when to
   retire the legacy fallback path
4. sketch the first Orange Pi 4 Pro driver-scaffolding tranche from the working
   QEMU lane
5. only then push deeper into physical Orange Pi 4 Pro bring-up

## Hard guardrails

- do not delete or corrupt `/workspace/tmp` artifacts that are still being used
  for validation/debugging without good reason
- do not let board names drift: the first physical target is Orange Pi 4 Pro,
  while the local machine is still Orange Pi 6 Plus
- do not blindly copy 9front Orange Pi 4 Pro blobs/payloads into this repo
- do not declare a workflow change complete without rerunning the relevant Make
  targets
- do not let docs drift away from the observed validation state