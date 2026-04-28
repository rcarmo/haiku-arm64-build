# Orange Pi 6 Plus EFI snapshot (2026-04-27)

This directory preserves the currently observed EFI/GRUB boot surface from the
local Orange Pi 6 Plus host.

Source device:

- `/dev/nvme0n1p1`
- UUID: `7448-7FE4`
- PARTUUID: `efa40ac1-d84a-419e-818d-b5e809684922`
- filesystem: `vfat`
- snapshot time: `2026-04-27T06:06:41Z`

This snapshot was created with:

- `scripts/snapshot-orangepi6plus-efi.sh`

## Included in-repo

Small boot-surface files were copied into this directory:

- `EFI/BOOT/BOOTAA64.EFI`
- `GRUB/GRUB.CFG`
- `GRUB/GRUB.CFG.bak-20260308T180151Z`
- `SKY1-EVB.DTB`
- `SKY1-EVB-ISO.DTB`
- `SKY1-ORANGEPI-6-PLUS.DTB`
- `SKY1-ORANGEPI-6-PLUS-40PIN.DTB`
- `SKY1-ORANGEPI-6-PLUS-40PIN-PWM.DTB`

## Checksummed but not copied

The larger payload files were not copied into git, but they are fully listed in
`manifest.tsv` and `SHA256SUMS`:

- `IMAGE`
- `ROOTFS.CPIO.GZ`

## Manifest files

- `METADATA.txt` — source device and snapshot metadata
- `ESP-TREE.txt` — file list from the ESP root
- `manifest.tsv` — relative path + size for all files seen
- `SHA256SUMS` — checksums for all files seen on the ESP

## Purpose

This is the first pinned Orange Pi 6 Plus boot-surface baseline for the Haiku
repo.

It is now a **historical build-host reference**, not the first physical Haiku
bring-up target.

It exists so that later work can:

- compare against a known-good local host boot surface when host-side questions
  arise
- keep older Orange Pi 6 Plus EFI observations from being lost
- keep those assumptions clearly separate from the current Orange Pi 4 Pro /
  Allwinner A733 physical bring-up plan shared with the 9front board work
