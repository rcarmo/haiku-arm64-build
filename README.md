# Haiku ARM64 Build Environment

Local build environment for Haiku OS ARM64 on Orange Pi 6 Plus.

## Quick Start

```sh
make deps      # install prerequisites (once)
make clone     # clone haiku + buildtools repos
make toolchain # build cross-compiler (~15 min)
make image     # build MMC image (~5 min)
make test      # QEMU smoke test (30s)
```

## Status

- Build: ✅ working (native aarch64 cross-compile)
- QEMU boot: kernel loads, panics on disk init (upstream ARM64 limitation)
- Bare metal: untested (target: Orange Pi 6 Plus / CIX P1)

## Build Host

- Orange Pi 6 Plus (CIX P1, 12 cores, 14 GiB RAM)
- Debian Trixie (aarch64), kernel 6.6.89-cix
- Bun runtime, GCC 14.2.0

## Files

- `Makefile` — reproducible build targets
- `haiku/` — Haiku source (git submodule, not tracked)
- `buildtools/` — Haiku build tools (git submodule, not tracked)

## Notes

- ext4 doesn't support xattr properly; build uses fallback (slightly slower)
- ARM64 port is upstream "extremely early" status
- Cross-toolchain is `aarch64-unknown-haiku-gcc 13.3.0`
