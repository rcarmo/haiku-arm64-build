# Zstd runtime replacement validation (2026-04-27)

## Goal

Check whether the remaining ARM64 direct-package desktop blocker is specifically
`libzstd.so.1`, and whether a smaller runtime-only package can replace the
current `zstd_bootstrap` overlay in validation.

## What was verified

- the normal local ARM64 package `zstd-1.5.6-1-arm64.hpkg` is still a **stub**
- its extracted `.PackageInfo` only provides `zstd = 1.5.6-1`
- it does **not** ship `libzstd.so.1`
- the locally built `zstd_bootstrap-1.5.6-1-arm64.hpkg` does contain the real
  shared library payload (`lib/libzstd.so.1.5.6`)
- a smaller local package was built from that payload:
  - `/workspace/tmp/zstd-runtime-proto/zstd_runtime-1.5.6-1-arm64.hpkg`
  - provides `lib:libzstd = 1.5.6 compat >= 1`

## Validation matrix

Validated with `scripts/qemu-desktop-harness.sh validate --timeout 120` on top
of the managed stock ARM64 nightly base image.

| Case | Result | Evidence |
|---|---|---|
| `stock` | pass | desktop markers present; `desktop validation passed` |
| `direct_only` | fail | `runtime_loader: Cannot open file libzstd.so.1` |
| `direct_plus_expat` | fail | same `libzstd.so.1` failure |
| `direct_plus_zstd_runtime` | pass | desktop markers present; `desktop validation passed` |
| `direct_plus_zstd_runtime_plus_expat` | pass | desktop markers present; `desktop validation passed` |

## Interpretation

- the current remaining blocker is the shared zstd runtime, not `expat`
- `expat_bootstrap` is no longer needed in the modern validated lane
- the direct-package desktop lane does **not** require the full broader
  `zstd_bootstrap` package payload for validation; it only needs a package that
  satisfies `lib:libzstd`
- the builder still defaults to `zstd_bootstrap` today, but the repo now has a
  validated smaller replacement candidate

## Artifact paths

- prototype package:
  `/workspace/tmp/zstd-runtime-proto/zstd_runtime-1.5.6-1-arm64.hpkg`
- focused validation stdout captures:
  - `/workspace/tmp/zstd-runtime-manual/stock.stdout`
  - `/workspace/tmp/zstd-runtime-manual/direct_only.stdout`
  - `/workspace/tmp/zstd-runtime-manual/direct_plus_expat.stdout`
  - `/workspace/tmp/zstd-runtime-manual/direct_plus_zstd.stdout`
  - `/workspace/tmp/zstd-runtime-manual/direct_plus_zstd_expat.stdout`

## Bottom line

The modern ARM64 direct desktop lane is blocked by missing `libzstd.so.1`, not
by `expat`. A minimal runtime-only replacement has now been validated locally,
even though the checked-in builder still points at `zstd_bootstrap` by default.
