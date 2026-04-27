# Haiku ARM64 Maintainer Checklist

This is the operational checklist for the reproducible ARM64 desktop-validation
lane in this repo.

Use it together with:

- `README.md`
- `AGENTS.md`
- `docs/boot-debug-notes-2026-04-23.md`
- `docs/UBOOT-ASSESSMENT.md`
- `bootstrap/orangepi6plus/host-efi-2026-04-27/README.md`

## Scope

This checklist covers the current authoritative workflow:

- sync a stock ARM64 nightly base
- validate the stock nightly in QEMU
- rebuild the direct-package overlay image
- validate the rebuilt image in QEMU
- probe the stock/direct overlay matrix
- keep docs aligned with the current observed state

It does **not** assume physical Orange Pi 6 Plus boot is already working.
Physical boot remains a later stage.

## Canonical environment

- host: Orange Pi 6 Plus
- OS: Debian Trixie (aarch64)
- repo: `/workspace/projects/haiku-build`
- main workspace: `/workspace`
- service/runtime context: host-native on the Orange Pi host
- default repo branch: `master`
- main Haiku source branch: `haiku/` on `arm64-bootstrap-fixes`

## Canonical one-command flow

For the normal regression lane, run these in order:

```sh
make nightly-arm64-sync
make stock-validate
make desktop-image
make desktop-validate
make desktop-probe-overlays
```

If all of those pass, the current lane is healthy.

## Expected current state

As of 2026-04-27, the expected modern overlay state is:

- default validated image uses:
  - direct `haiku.hpkg`
  - `zstd_bootstrap-1.5.6-1-arm64.hpkg`
- `expat_bootstrap` is **not** part of the default validated image
- the validated direct package prunes:
  - `demos/Cortex`
  - `data/deskbar/menu/Demos/Cortex`
- the normal local `zstd-1.5.6-1-arm64.hpkg` is currently a stub package and
  does not provide `libzstd.so.1`

Current probe expectations:

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

- validated desktop image:
  `/workspace/tmp/haiku-build/validated/haiku-arm64-icu74-desktop.boot.img`
- rebuilt direct package:
  `/workspace/tmp/haiku-build/validated/haiku-direct-icu74.hpkg`
- legacy fallback compat package:
  `/workspace/tmp/haiku-build/validated/compat_bootstrap_runtime-1-2-arm64.hpkg`

### Harness output

- run/validate logs:
  `/workspace/tmp/haiku-boot-harness/`
- overlay probe summaries:
  - `/workspace/tmp/haiku-overlay-probe/summary.md`
  - `/workspace/tmp/haiku-overlay-probe/summary.tsv`
- overlay probe logs:
  - `/workspace/tmp/haiku-overlay-probe/*.validate.log`

### Physical boot baseline

- pinned repo snapshot:
  `/workspace/projects/haiku-build/bootstrap/orangepi6plus/host-efi-2026-04-27/`
- refreshable working snapshot:
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
make desktop-image
make desktop-validate
```

Also run `make desktop-probe-overlays` if the change affects:

- package composition
- solver metadata
- pruned contents
- partition sizing
- legacy vs modern overlay behavior

### If you change `scripts/qemu-desktop-harness.sh`

Run:

```sh
make stock-validate
make desktop-validate
```

If you touched marker logic, log parsing, crash detection, or screenshot/run
mode, also exercise:

```sh
make desktop-run
make desktop-status
make desktop-stop
```

### If you change `scripts/probe-direct-package-overlays.sh`

Run:

```sh
make desktop-probe-overlays
```

and verify `summary.md` matches the intended expectation matrix.

### If you change `scripts/snapshot-orangepi6plus-efi.sh` or physical boot assumptions

Run:

```sh
make orangepi6plus-efi-snapshot
```

Then verify:

- `/workspace/tmp/orangepi6plus-efi-snapshot/latest/METADATA.txt`
- `/workspace/tmp/orangepi6plus-efi-snapshot/latest/SHA256SUMS`
- `/workspace/tmp/orangepi6plus-efi-snapshot/latest/GRUB/GRUB.CFG`

If the observed board boot surface changed materially, update:

- `docs/UBOOT-ASSESSMENT.md`
- `AGENTS.md`
- the pinned repo baseline under `bootstrap/orangepi6plus/`

### If you change direct package contents or package metadata

Examples:

- pruning files from the validated package
- editing generated package-info handling
- changing bootstrap package selection
- changing direct/legacy overlay rules

Run the full lane:

```sh
make nightly-arm64-sync
make stock-validate
make desktop-image
make desktop-validate
make desktop-probe-overlays
```

## Pass/fail criteria

### `make stock-validate`

Expected:

- boots in QEMU
- marker files for `app_server`, `Tracker`, `Deskbar` are present
- no fatal crash signature in validate logs

### `make desktop-validate`

Expected:

- boots in QEMU
- marker files for `app_server`, `Tracker`, `Deskbar` are present
- `package_daemon` reports `/boot/system` consistent

### `make desktop-probe-overlays`

Expected summary:

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
- `docs/MAINTAINER-CHECKLIST.md`
- `docs/UBOOT-ASSESSMENT.md` if the board-boot strategy changes
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

1. remove the remaining `zstd_bootstrap` dependency, or ensure the stock base
   carries `libzstd.so.1`
2. collapse the extra `expat_bootstrap` control cases from the probe when they
   stop being useful
3. decide when to retire the older legacy fallback path
4. only after the QEMU lane is pared down, move on to physical Orange Pi 6 Plus
   bring-up

## Physical boot / U-Boot guardrail

Do **not** import the Orange Pi 4 Pro / Allwinner A733 9front boot blobs or sunxi
packaging assumptions into this repo.

For Orange Pi 6 Plus boot strategy, see:

- `docs/UBOOT-ASSESSMENT.md`

That document is the canonical place for the current U-Boot/UEFI assessment.