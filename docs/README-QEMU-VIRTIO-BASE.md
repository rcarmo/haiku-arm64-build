# Haiku ARM64 QEMU/UTM VirtIO base desktop image

Images:

- `haiku-arm64-icu74-desktop.qcow2`
- `haiku-arm64-icu74-desktop.boot.img`

This is our upstream-matching ARM64 base desktop image. It starts from the
selected official Haiku ARM64 nightly MMC image for the requested `hrev`, keeps
the same basic desktop setup and minimal package set, then overlays our rebuilt
`haiku.hpkg` from `rcarmo/haiku:arm64-bootstrap-fixes`.

The overlay is intentionally minimal:

- direct rebuilt `haiku.hpkg`
- `zstd_runtime` compatibility package for the current ARM64 package closure
- optional/full-release package requirements pruned from this base lane

The rebuilt `haiku.hpkg` includes `virtio_block`, so the image is intended to
boot with VirtIO block storage rather than relying on USB storage.

## QEMU settings

```sh
qemu-system-aarch64 \
  -bios /usr/share/qemu-efi-aarch64/QEMU_EFI.fd \
  -M virt -cpu max -m 2048 \
  -device virtio-blk-device,drive=x0,bus=virtio-mmio-bus.0 \
  -drive file=haiku-arm64-icu74-desktop.qcow2,if=none,format=qcow2,id=x0 \
  -device ramfb -nographic -no-reboot
```

## UTM settings

Use an **ARM64/aarch64 emulated VM** with:

- Architecture: ARM64 / aarch64
- Machine: `virt`
- Boot firmware: UEFI
- Memory: 2048 MiB or more
- Display: RAM framebuffer / simple framebuffer if available
- Disk image: `haiku-arm64-icu74-desktop.qcow2`
- Disk format: qcow2
- Disk interface: **VirtIO** storage
- Network: VirtIO, optional

UTM on stock iOS may run without JIT, so expect slow boot/performance.
