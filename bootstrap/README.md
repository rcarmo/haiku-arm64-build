# Bootstrap artifacts

This tree holds pinned board-boot artifacts and baseline boot-surface snapshots
used for physical bring-up work.

Rules:

- keep artifacts board-specific
- preserve provenance and checksums
- prefer exact known-good inputs over regenerated guesses
- do not mix unrelated board families in the same subtree

Current entries:

- `bootstrap/orangepi6plus/host-efi-2026-04-27/` — EFI/GRUB boot-surface snapshot
  from the current Orange Pi 6 Plus host installation
