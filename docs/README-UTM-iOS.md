# Haiku ARM64 minimum image for UTM on iOS

Image:

- `haiku-arm64-minimum-utm-ios.qcow2`

This is the practical minimum/bootstrap-style ARM64 Haiku image for UTM/iOS. It
is built from the local `@minimum-mmc` target and includes the `virtio_block`
kernel driver in `haiku.hpkg`, allowing the kernel to rediscover and mount the
boot partition after UEFI loader handoff.

## Important UTM settings

Use an **ARM64/aarch64 emulated VM** with:

- Architecture: ARM64 / aarch64
- Machine: `virt`
- Boot firmware: UEFI
- Memory: 2048 MiB or more
- Display: RAM framebuffer if available
- Disk image: `haiku-arm64-minimum-utm-ios.qcow2`
- Disk interface: **VirtIO** storage

USB storage should still work as a fallback, but VirtIO is the intended path for
this image.

## Local smoke test used by CI

VirtIO-MMIO equivalent:

```sh
qemu-system-aarch64 \
  -bios /usr/share/qemu-efi-aarch64/QEMU_EFI.fd \
  -M virt -cpu max -m 2048 \
  -device virtio-blk-device,drive=x0,bus=virtio-mmio-bus.0 \
  -drive file=haiku-arm64-minimum-utm-ios.qcow2,if=none,format=qcow2,id=x0 \
  -device ramfb -nographic -no-reboot
```

The smoke log must reach package_daemon registration for `/boot/system` with no
`PANIC:` signature.

Note: UTM on stock iOS may run without JIT, so expect slow boot/performance.
