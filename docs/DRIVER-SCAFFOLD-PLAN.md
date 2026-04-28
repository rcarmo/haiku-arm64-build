# Full-QEMU-first driver scaffolding plan

This document captures how the current **full direct-package QEMU lane** should
be used to stage the first driver scaffolding for later **Orange Pi 4 Pro**
bring-up.

It is intentionally a staging document, not a claim that these drivers already
exist or are validated on hardware.

## Current baseline

The current authoritative software lane is:

```sh
make nightly-arm64-sync
make stock-validate
make desktop-image
make desktop-validate
make desktop-probe-overlays
```

Current known-good outcome:

- stock ARM64 nightly validates in QEMU
- the direct-package desktop lane validates in QEMU
- the default modern overlay is down to:
  - direct `haiku.hpkg`
  - generated local `zstd_runtime-1.5.6-1-arm64.hpkg`

That full-QEMU lane is the safest place to grow new scaffolding because it keeps
package/runtime churn separate from real-board bootloader churn.

## Goal

Use the working QEMU lane to shape the software-side interfaces we will need for
Orange Pi 4 Pro, without blocking on full board bring-up.

That means:

- keep QEMU boot and validation passing
- add or sketch interfaces behind clean board/FDT hooks
- prefer generic ARM64 or FDT-driven plumbing where possible
- keep board-specific code narrow and explicit

## Board facts that should inform the scaffolding

From the local 9front repo, the first physical target is:

- board: Orange Pi 4 Pro
- SoC: Allwinner A733 (`sun60iw2`)
- debug UART: UART0 at `0x02500000`
- serial settings: `115200` 8N1
- boot priority: TF/SD before eMMC
- vendor DTB reference: `sun60i-a733-orangepi-4-pro.dtb`

These are the hardware-facing constraints the scaffolding should eventually
serve.

## Staging principles

### 1. QEMU stays authoritative

Do not break the working QEMU lane in pursuit of speculative board code.

Every scaffolding step should preserve the ability to validate the full package
flow in QEMU.

### 2. Prefer hooks over hard-coded board forks

Where possible, stage work as:

- FDT parsing helpers
- driver registration points
- board match tables
- clock/reset/pinctrl service interfaces
- device discovery plumbing

rather than giant one-off board hacks.

### 3. Separate scaffolding from implementation completeness

A scaffold can be useful before a driver is feature-complete if it:

- defines the right interfaces
- makes probe/attach order explicit
- provides serial-visible failure points
- does not destabilize the QEMU lane

### 4. Serial-first debugging assumptions must be preserved

Real hardware work should assume serial is the first reliable output path.
So scaffolding should favor:

- early console hooks
- explicit probe logging
- failure modes visible before GUI/display exists

## Suggested scaffolding order

### Stage A — board/FDT groundwork

Target outcomes:

- clearer board identification path from FDT
- a place to register board-specific quirks cleanly
- device discovery helpers that can work both in QEMU and on real hardware

Sketch areas:

- FDT node matching helpers
- interrupt-controller discovery hooks
- memory-map / MMIO description helpers
- board-name / compatible-string matching tables

### Stage B — early console + interrupt + timer path

Target outcomes:

- keep QEMU serial path stable
- define the interface needed for the Orange Pi 4 Pro UART path later
- make interrupt/timer assumptions explicit instead of implicit

Sketch areas:

- early serial abstraction boundary
- PL011/QEMU path retained as validation default
- future sun60iw2 UART0 path documented and stubbed
- interrupt controller selection hooks (`GICv2` in QEMU, `GICv3` on the board)
- timer hookup review points

### Stage C — clock/reset/pinctrl service layer

Target outcomes:

- drivers stop baking in ad-hoc assumptions about always-on hardware
- later board drivers have a place to request clocks, resets, and muxing

Sketch areas:

- clock-provider interface stubs
- reset-controller interface stubs
- pinctrl request/configure hooks
- serial-visible unimplemented-path logging

### Stage D — storage and boot-media-facing scaffolds

Target outcomes:

- define the path for the board's actual boot/storage media
- keep QEMU validation separate from board-storage specifics

Priority devices:

- MMC / SD
- eMMC
- USB storage only as a convenience path where relevant
- later NVMe once PCIe exists

### Stage E — network and USB skeletons

Priority devices:

- GMAC ethernet
- USB XHCI

Target outcomes:

- driver attach/probe order becomes explicit
- dependencies on clocks/resets/interrupts are visible
- real-board debugging can fail loudly and locally instead of silently

### Stage F — PCIe and NVMe path

Priority devices:

- PCIe root-complex scaffolding
- NVMe once PCIe enumeration exists

This should come after the clock/reset/interrupt groundwork is in place.

### Stage G — framebuffer / display path

Target outcomes:

- keep the QEMU-visible display path working
- avoid making early board bring-up depend on a full display stack

Practical sequence:

- preserve QEMU framebuffer expectations first
- keep serial as the authoritative real-board debug channel
- only then sketch the board display path

## What not to do yet

- do not block QEMU packaging work on board-driver completeness
- do not import 9front payloads as if they were Haiku drivers
- do not make the first hardware milestone depend on display working
- do not assume every Orange Pi 4 Pro hardware block must be implemented before
  the first board boot attempt

## Near-term documentation obligations

When the scaffold plan changes, update together:

- `README.md`
- `AGENTS.md`
- `docs/MAINTAINER-CHECKLIST.md`
- `docs/UBOOT-ASSESSMENT.md`
- `/workspace/notes/haiku-arm64-build.md`

## Working next tranche

The next sensible tranche is:

1. keep the full-QEMU lane passing
2. remove or narrow remaining runtime/package shims where possible
3. make the first driver-scaffolding notes explicit in-tree
4. start implementing only the smallest hooks that help both QEMU clarity and
   later Orange Pi 4 Pro bring-up
