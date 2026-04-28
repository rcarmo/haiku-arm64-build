# Orange Pi 4 Pro physical bring-up / bootloader assessment

This document assesses how physical bring-up should be approached for the Haiku
ARM64 port now that the first real-board target is **Orange Pi 4 Pro**
(`orangepi4pro`, Allwinner A733 / `sun60iw2`).

The working methodology comes from the local 9front repo:

- `/workspace/projects/9front/README.md`
- `/workspace/projects/9front/AGENTS.md`
- `/workspace/projects/9front/docs/BOARD-NOTES.md`
- `/workspace/projects/9front/docs/BRINGUP-STATUS.md`
- `/workspace/projects/9front/bootstrap/orangepi4pro/vendor-debian-1.0.6/`

## Bottom line

- keep **QEMU `virt` + UEFI** as the authoritative software-validation lane
- treat **Orange Pi 4 Pro** as the first physical board target
- reuse the **9front workflow and board facts**, not its payloads blindly
- let the full-QEMU lane drive the first driver-scaffolding tranche before
  trying to solve all board-specific hardware at once
- when Haiku physical work starts, create explicit Haiku-side artifacts under a
  board-specific tree with provenance

## What the 9front repo already proved

The 9front work already established a useful bring-up pattern for this exact
board family:

- the board identity is pinned and documented as **Orange Pi 4 Pro**
- exact vendor bootstrap blobs are preserved under
  `bootstrap/orangepi4pro/vendor-debian-1.0.6/`
- the working vendor boot chain is extracted, checksummed, and discussed in the
  repo
- board facts like serial setup, boot priority, and offsets are documented in a
  durable way
- serial-first debugging is treated as authoritative
- a board-specific audit trail exists in:
  - `docs/BOARD-NOTES.md`
  - `docs/BRINGUP-STATUS.md`
  - `docs/FIT-GAP-AUDIT.md`
  - `docs/disasm/orangepi4pro/vendor-debian-1.0.6/`

That is the main reusable lesson: **freeze the known-good board boot path, then
iterate around it**.

## Board facts that now matter to Haiku

From the 9front repo and board notes:

- board: **Orange Pi 4 Pro**
- SoC: **Allwinner A733** (`sun60iw2`)
- debug UART: **UART0** at `0x02500000`
- default serial settings: **115200 8N1**
- boot priority: **TF/SD before eMMC**
- vendor DTB reference: `sun60i-a733-orangepi-4-pro.dtb`
- vendor SD layout:
  - 8 KiB: `boot0`
  - 16.8 MiB: `boot_package`
  - 32 MiB+: FAT partition with boot payloads

These facts should anchor the Haiku physical-board plan.

## What does and does not transfer directly

### Transfers directly

- the board identity
- the serial/debug expectations
- the observed vendor boot-chain structure
- the need for provenance, checksums, and pinned artifacts
- the serial-first workflow discipline
- the need for a board-specific audit trail

### Does not transfer directly

Do **not** assume Haiku can just reuse:

- 9front kernel payloads
- 9front wrapper formats as-is
- 9front-specific boot scripts as-is
- 9front-specific source layout
- any 9front payload without an explicit Haiku-side reason and provenance note

The right reuse is **method + board facts**, not blind binary reuse.

## Why full QEMU stays first

The Haiku repo already has a reproducible full-package QEMU lane that can:

- sync a stock ARM64 nightly base
- rebuild a direct-package image
- boot it in QEMU
- verify `app_server`, `Tracker`, and `Deskbar`
- check `/boot/system` solver consistency

That means the current bottleneck is no longer "can the package lane boot at
all?" but rather:

- when can the remaining `zstd_runtime` shim be removed?
- how do we grow validation breadth from the full lane?
- which driver/board scaffolding should be introduced next?

So physical bring-up should be staged **after** the full-QEMU lane remains the
software authority.

## Recommended physical bring-up order

### 1. Keep the full-QEMU lane authoritative

Do not split focus too early.

The working baseline remains:

```sh
make nightly-arm64-sync
make stock-validate
make desktop-image
make desktop-validate
make desktop-probe-overlays
```

### 2. Create Haiku-side Orange Pi 4 Pro artifacts only with provenance

When the first physical Haiku tranche begins, add a board-specific tree such as:

- `bootstrap/orangepi4pro/<vendor-version>/`

Populate it with exact inputs plus provenance/checksums, not guesses.

Likely contents:

- vendor boot blobs actually used for bring-up
- DTBs used for comparison
- manifests/checksums
- notes on how each artifact was obtained

### 3. Keep serial-first tooling mandatory

Before framebuffer or GUI checks on real hardware:

- pin the USB serial adapter path in the workflow when known
- keep the default baud at `115200`
- log to a stable path under `/workspace/tmp/...`
- make UART capture part of the bring-up routine, not an afterthought

### 4. Start from the vendor-style board boot chain

For Orange Pi 4 Pro, the first bootloader question should be:

- can the vendor-style `boot0` + `boot_package` + FAT payload flow hand off to
  Haiku test payloads in a controllable way?

Do **not** start by rewriting the whole boot path if the vendor path can carry a
first test image.

### 5. Only then decide whether U-Boot work is required

A Haiku-owned board bootloader lane becomes worthwhile only if one of these is
true:

1. the vendor-style path cannot hand off to Haiku in a controllable way
2. Haiku needs a different payload/layout contract than the vendor path allows
3. we need a reproducible repo-owned boot chain for long-term work
4. deeper board-handoff debugging requires local bootloader changes

## Driver scaffolding implications

Because Orange Pi 4 Pro is now the first board target, the driver-scaffolding
plan should be informed by its hardware surface, while still being staged from
QEMU first.

Near-term scaffold priorities are captured in:

- `docs/DRIVER-SCAFFOLD-PLAN.md`

At a high level that means:

1. FDT/board hooks
2. early serial + interrupt + timer plumbing
3. clock/reset/pinctrl service stubs
4. storage/network/display-facing skeletons for:
   - MMC/eMMC
   - GMAC ethernet
   - USB XHCI
   - PCIe/NVMe
   - framebuffer/display

## Relationship to the Orange Pi 6 Plus host snapshot

This repo still carries:

- `bootstrap/orangepi6plus/host-efi-2026-04-27/`
- `make orangepi6plus-efi-snapshot`

Those are now **historical local-host references only**.
They are useful for documenting the build host environment, but they are **not**
the first physical Haiku bring-up target anymore.

## Working conclusion

The current plan is:

- stabilize and extend the **full direct-package QEMU lane** first
- use that lane to sketch the first driver-scaffolding tranche
- treat **Orange Pi 4 Pro** as the first physical board target
- ground physical work in the board facts and vendor boot-chain evidence already
  captured in the 9front repo
- create explicit Haiku-side board artifacts only when physical bring-up work
  actually starts
