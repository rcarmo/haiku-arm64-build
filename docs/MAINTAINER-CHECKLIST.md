# Haiku ARM64 Maintainer Checklist

This is the operational checklist for the reproducible ARM64 desktop-validation
lane in this repo.

Use it together with:

- `README.md`
- `AGENTS.md`
- `docs/boot-debug-notes-2026-04-23.md`
- `docs/UBOOT-ASSESSMENT.md`
- `docs/DRIVER-SCAFFOLD-PLAN.md`
- `bootstrap/orangepi6plus/host-efi-2026-04-27/README.md`

## Scope

This checklist covers the current authoritative workflow:

- sync a stock ARM64 nightly base
- validate the stock nightly in QEMU
- rebuild the direct-package overlay image
- validate the rebuilt image in QEMU
- probe the stock/direct overlay matrix
- keep docs aligned with the current observed state

It does **not** assume physical Orange Pi 4 Pro boot is already working.
Physical boot remains a later stage.

## Canonical environment

- host: Orange Pi 6 Plus
- OS: Debian Trixie (aarch64)
- repo: `/workspace/projects/haiku-build`
- main workspace: `/workspace`
- service/runtime context: host-native on the Orange Pi host
- default repo branch: `master`
- main Haiku source branch: `haiku/` on `arm64-bootstrap-fixes`
- first physical target: Orange Pi 4 Pro (`orangepi4pro`, Allwinner A733 / `sun60iw2`)

## Canonical one-command flow

For the normal regression lane, run these in order:

```sh
make bfs-fuse
make full-sync
make full-stock-validate
make full-image
make full-validate
make full-probe-overlays
```

or just:

```sh
make full-check
```

When you need downloadable artifacts, run:

```sh
make validation-artifacts HREV=<hrev-number> HAIKU_REMOTE=https://github.com/rcarmo/haiku.git HAIKU_BRANCH=arm64-bootstrap-fixes
```

If all of those pass, the current lane is healthy. `make full-check` now reaches
`make bfs-fuse` through the validation/image prerequisites, so a cleaned
`/workspace/tmp/bfs_fuse` symlink is recreated from the host-built Haiku
`bfs_fuse` helper before any BFS partition mounting. Use `make validation-artifacts`
when you need the downloadable raw image, qcow2 image, and `SHA256SUMS`. The
older `desktop-*` target names still exist as compatibility aliases.

## Expected current state

As of 2026-04-30, the expected modern overlay state is:

- `make full-check` validates end-to-end in QEMU after `make bfs-fuse` creates
  `/workspace/tmp/bfs_fuse` from the host-built Haiku BFS FUSE helper
- the local arm64 `HAIKU_NO_DOWNLOADS=1` `@minimum-mmc` path builds and passes
  the 30s `make test` smoke target after the `haiku/arm64-bootstrap-fixes`
  branch made `noto`, `ncurses6`, and `zstd` explicit fallback packages in
  `Jamfile`
- default validated image uses:
  - direct `haiku.hpkg`
  - `/workspace/tmp/haiku-build/validated/zstd_runtime-1.5.6-1-arm64.hpkg`
- `expat_bootstrap` is **not** part of the default validated image
- the validated direct package prunes:
  - `demos/Cortex`
  - `data/deskbar/menu/Demos/Cortex`
- the normal local `zstd-1.5.6-1-arm64.hpkg` is currently a stub package and
  does not provide `libzstd.so.1`
- the builder now emits the smaller local `zstd_runtime` package from the
  `zstd_bootstrap` shared-library payload, so the default lane only carries the
  narrower `lib:libzstd` provider it still needs

Current probe expectations use a 300s per-case timeout by default
(hrev59671 stock can miss the Deskbar marker under the older 120s budget):

- `stock` → pass
- `direct_only` → fail
- `direct_plus_expat` → fail
- `direct_plus_zstd` → pass
- `direct_plus_zstd_expat` → pass

## Artifact locations

### Managed nightly base

- image symlink: `/workspace/tmp/haiku-nightly-arm64/haiku-master-arm64-current-mmc.image`
- zip symlink: `/workspace/tmp/haiku-nightly-arm64/haiku-master-arm64-current-mmc.zip`

### Built validated outputs

- validated desktop raw image:
  `/workspace/tmp/haiku-build/validated/haiku-arm64-icu74-desktop.boot.img`
- validated desktop qcow2 image:
  `/workspace/tmp/haiku-build/validated/haiku-arm64-icu74-desktop.qcow2`
- validation artifact checksums:
  `/workspace/tmp/haiku-build/validated/SHA256SUMS`
- rebuilt direct package:
  `/workspace/tmp/haiku-build/validated/haiku-direct-icu74.hpkg`
- legacy fallback compat package:
  `/workspace/tmp/haiku-build/validated/compat_bootstrap_runtime-1-2-arm64.hpkg`
- generated zstd runtime package:
  `/workspace/tmp/haiku-build/validated/zstd_runtime-1.5.6-1-arm64.hpkg`

### Harness output

- run/validate logs:
  `/workspace/tmp/haiku-boot-harness/`
- overlay probe summaries:
  - `/workspace/tmp/haiku-overlay-probe/summary.md`
  - `/workspace/tmp/haiku-overlay-probe/summary.tsv`
- overlay probe logs:
  - `/workspace/tmp/haiku-overlay-probe/*.validate.log`

### Physical bring-up references

- first target board reference blobs:
  `/workspace/projects/9front/bootstrap/orangepi4pro/vendor-debian-1.0.6/`
- first target board notes:
  `/workspace/projects/9front/docs/BOARD-NOTES.md`
- first target board bring-up status:
  `/workspace/projects/9front/docs/BRINGUP-STATUS.md`
- historical local-host snapshot:
  `/workspace/projects/haiku-build/bootstrap/orangepi6plus/host-efi-2026-04-27/`
- refreshable historical local-host snapshot:
  `/workspace/tmp/orangepi6plus-efi-snapshot/latest`

## What to run after each class of change

### If you change `scripts/fetch-latest-arm64-nightly.sh`

Run:

```sh
make nightly-arm64-sync
make stock-validate
```

Confirm the stable symlink still points to a valid extracted image.

### If you change `scripts/build-validated-desktop-image.sh`

Run:

```sh
make full-image
make full-validate
```

Also run `make full-probe-overlays` if the change affects:

- package composition
- solver metadata
- pruned contents
- partition sizing
- legacy vs modern overlay behavior

### If you change `scripts/qemu-desktop-harness.sh`

Run:

```sh
make full-stock-validate
make full-validate
```

If you touched marker logic, log parsing, crash detection, or screenshot/run
mode, also exercise:

```sh
make full-run
make full-status
make full-stop
```

### If you change `scripts/probe-direct-package-overlays.sh`

Run:

```sh
make full-probe-overlays
```

and verify `summary.md` matches the intended expectation matrix.

### If you change `scripts/snapshot-orangepi6plus-efi.sh` or local host boot-reference assumptions

Run:

```sh
make orangepi6plus-efi-snapshot
```

Then verify:

- `/workspace/tmp/orangepi6plus-efi-snapshot/latest/METADATA.txt`
- `/workspace/tmp/orangepi6plus-efi-snapshot/latest/SHA256SUMS`
- `/workspace/tmp/orangepi6plus-efi-snapshot/latest/GRUB/GRUB.CFG`

If the observed local-host boot surface changed materially, update:

- `docs/UBOOT-ASSESSMENT.md`
- `AGENTS.md`
- the pinned repo baseline under `bootstrap/orangepi6plus/`

If the Orange Pi 4 Pro bring-up assumptions changed materially, update:

- `docs/UBOOT-ASSESSMENT.md`
- `docs/DRIVER-SCAFFOLD-PLAN.md`
- `AGENTS.md`

### If you change direct package contents or package metadata

Examples:

- pruning files from the validated package
- editing generated package-info handling
- changing bootstrap package selection
- changing direct/legacy overlay rules

Run the full lane:

```sh
make full-sync
make full-stock-validate
make full-image
make full-validate
make full-probe-overlays
```

## Pass/fail criteria

### `make stock-validate`

Expected:

- boots in QEMU
- marker files for `app_server`, `Tracker`, `Deskbar` are present
- no fatal crash signature in validate logs

### `make full-validate`

Expected:

- boots in QEMU
- marker files for `app_server`, `Tracker`, `Deskbar` are present
- `package_daemon` reports `/boot/system` consistent

### `make full-probe-overlays`

Expected summary. The probe default timeout is 300s per case; keep that budget
unless a newer nightly consistently validates faster, because hrev59671 stock
can miss the Deskbar marker under the older 120s budget.


- `stock` → `pass`
- `direct_only` → `fail`
- `direct_plus_expat` → `fail`
- `direct_plus_zstd` → `pass`
- `direct_plus_zstd_expat` → `pass`

## Known failure signatures

### Missing zstd runtime

Seen as:

- `runtime_loader: Cannot open file libzstd.so.1 ...`

Meaning:

- direct package still needs `libzstd.so.1`
- stock nightly base still lacks it
- normal local `zstd` package is not yet usable as a replacement
- the default builder now uses a generated local `zstd_runtime` shim until a
  real stock/normal package provider exists

### Package solver inconsistency

Seen as:

- `Volume::InitialVerify(): volume at "/boot/system" has problems:`
- `nothing provides ...`

Meaning:

- overlay package set or direct package metadata is inconsistent
- the validated lane is not acceptable until `/boot/system` is consistent again

### Missing harness markers

Seen as:

- `marker: MISS ...`

Meaning:

- desktop did not come up far enough
- or the harness failed to inject/read the additive marker jobs

## Documentation update checklist

When the observed state changes, update docs in the same tranche as the code:

- `README.md`
- `docs/boot-debug-notes-2026-04-23.md`
- `docs/ZSTD-RUNTIME-VALIDATION-2026-04-27.md` when the zstd-replacement state changes
- `docs/MAINTAINER-CHECKLIST.md`
- `docs/UBOOT-ASSESSMENT.md` if the board-boot strategy changes
- `docs/DRIVER-SCAFFOLD-PLAN.md` if the QEMU→hardware staging or driver plan changes
- `AGENTS.md`
- `/workspace/notes/haiku-arm64-build.md`

At minimum, update:

- current default overlay description
- probe expectation matrix
- known blockers
- next steps
- artifact paths if they changed

## Commit checklist

Before committing:

1. ensure the relevant Make targets passed
2. inspect `git diff`
3. update docs if the workflow or observed truth changed
4. keep commit messages specific to the lane change

Do not claim a packaging or harness change is done unless the relevant
validation targets have passed.

## Current maintainer priorities

1. keep the full direct-package QEMU lane healthy and authoritative
2. remove the remaining local `zstd_runtime` generation step by ensuring the
   stock base or the normal arm64 package set carries `libzstd.so.1`
3. collapse the extra `expat_bootstrap` control cases from the probe when they
   stop being useful and decide when to retire the older legacy fallback path
4. use the full-QEMU lane to sketch the first Orange Pi 4 Pro driver-scaffolding
   tranche
5. only after that, move on to physical Orange Pi 4 Pro bring-up

## Physical boot / U-Boot guardrail

Do **not** blindly copy Orange Pi 4 Pro / Allwinner A733 9front payloads into
this repo.

For the current Orange Pi 4 Pro boot strategy and the QEMU-first driver-scaffold
plan, see:

- `docs/UBOOT-ASSESSMENT.md`
- `docs/DRIVER-SCAFFOLD-PLAN.md`

Those documents are the canonical place for the current hardware-target and
staging assessment.