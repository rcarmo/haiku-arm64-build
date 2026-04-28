# Bootstrap artifacts

This tree holds pinned board-boot artifacts and baseline boot-surface snapshots
used for physical bring-up work.

Rules:

- keep artifacts board-specific
- preserve provenance and checksums
- prefer exact known-good inputs over regenerated guesses
- do not mix unrelated board families in the same subtree

Current entries:

- `bootstrap/orangepi6plus/host-efi-2026-04-27/` — historical EFI/GRUB
  boot-surface snapshot from the current Orange Pi 6 Plus build host

Planned active board-specific bring-up tree:

- `bootstrap/orangepi4pro/` — reserved for future Haiku-side Orange Pi 4 Pro
  (`sun60iw2`) bring-up artifacts once they are copied in with explicit
  provenance instead of ad-hoc reuse from the 9front repo
