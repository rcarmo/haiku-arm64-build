# Orange Pi 6 Plus bootloader / U-Boot assessment

This document assesses how physical Orange Pi 6 Plus boot should be approached
for the Haiku ARM64 port, using the working methodology from the local
`/workspace/projects/9front` repo as a reference.

## Bottom line

The **method** used in the 9front repo is highly reusable.
The **artifacts and packaging details** from that repo are not.

The 9front work proves a good bring-up pattern:

- preserve exact known-good vendor boot artifacts
- extract and document the boot chain instead of guessing
- compare the working vendor path against local bring-up code
- keep serial-first debugging and a maintained audit trail

But the 9front target is:

- Orange Pi 4 Pro
- Allwinner A733
- custom sunxi boot chain (`boot0` + `boot_package` + vendor U-Boot)

while this Haiku effort is targeting:

- Orange Pi 6 Plus
- CIX P1 (`CD8180` / `CD8160` family)
- a board whose currently observable OS-facing boot path is **UEFI/GRUB** on this
  host, not the same Allwinner raw-blob flow

So the correct reuse is **process reuse, not blob reuse**.

## What the 9front repo already demonstrated

From `/workspace/projects/9front`:

- exact vendor blobs were pinned under `bootstrap/<board>/...`
- the working vendor chain was extracted and checksummed
- U-Boot, DTB, and related artifacts were disassembled and documented
- the repo keeps a durable audit trail:
  - `AGENTS.md`
  - `docs/BRINGUP-STATUS.md`
  - `docs/FIT-GAP-AUDIT.md`
  - `docs/disasm/orangepi4pro/vendor-debian-1.0.6/`
- the board image builder (`mksdcard.sh`) encodes exact boot offsets and the
  wrapper format needed by the vendor U-Boot path
- serial-first bring-up was treated as authoritative

That is the main transferable lesson: **freeze the known-good hardware boot path,
then iterate around it**.

## What does *not* transfer directly

The following 9front-specific assumptions should **not** be copied into the
Haiku repo:

- `boot0` / `boot_package` offsets
- Allwinner sunxi pack tooling
- `sun60i-a733-orangepi-4-pro.dtb`
- vendor U-Boot binaries extracted from the Orange Pi 4 Pro Debian image
- the custom `booti` wrapper used there for 9front kernel handoff
- any assumption that Orange Pi 6 Plus needs the same SPL/package layout

Those belong to the Allwinner A733 board only.

## What we can infer on the current Orange Pi 6 Plus host

Observed locally on this host:

- `/sys/firmware/efi` exists
- the ESP is `/dev/nvme0n1p1` (vfat)
- the ESP currently contains:
  - `EFI/BOOT/BOOTAA64.EFI`
  - `GRUB/GRUB.CFG`
  - `IMAGE`
  - `ROOTFS.CPIO.GZ`
  - `SKY1-ORANGEPI-6-PLUS.DTB`
  - related SKY1 DTB variants
- the GRUB config exposes Orange Pi 6 Plus entries and uses:
  - `console=ttyAMA2,115200`
  - a Device Tree path using `SKY1-ORANGEPI-6-PLUS.DTB`

This means the **observable boot interface currently in use by the installed OS**
is EFI/GRUB with a DTB-based Linux boot path.

That does **not** prove U-Boot is absent underneath, but it does mean the first
practical bring-up target for Haiku is likely **not** a raw-blob U-Boot rebuild.

A pinned snapshot of that current boot surface is now checked into this repo at:

- `bootstrap/orangepi6plus/host-efi-2026-04-27/`

## Recommendation: prefer an EFI-first physical bring-up

For the first Orange Pi 6 Plus Haiku boot attempts, prefer this order:

### Stage 1 — reuse the current board boot surface

Treat the currently working board boot surface as:

- existing firmware path
- existing ESP
- existing serial console expectation (`ttyAMA2`, `115200`)
- existing DTB naming/layout conventions

The initial goal should be:

1. preserve the current working ESP contents
2. add the minimum Haiku boot artifacts needed for a test boot
3. attempt boot via the existing EFI/GRUB-style path first
4. capture serial before doing anything more ambitious

Reason:

- it minimizes the unknowns
- it avoids needing a new bootloader port before the OS itself boots
- it matches the successful 9front principle of reusing the known-good vendor
  path instead of replacing it too early

## When a dedicated U-Boot lane becomes worthwhile

A dedicated Orange Pi 6 Plus U-Boot workflow becomes worthwhile only if one of
these becomes true:

1. the existing EFI/GRUB path cannot hand off to Haiku in a controllable way
2. Haiku needs a board boot path that bypasses the current firmware stack
3. we need repeatable removable-media boot independent of the installed OS
4. we want a repo-owned, board-owned hardware boot chain for long-term bring-up

If that happens, the 9front repo gives the right *shape* for the work.

## How to apply the 9front methodology here

If we decide to build a dedicated board-boot lane for Orange Pi 6 Plus, do it in
this order.

### 1. Preserve the known-good board boot artifacts

This work has now started with:

- `bootstrap/orangepi6plus/host-efi-2026-04-27/`

That snapshot preserves the currently observed EFI/GRUB boot surface, including
small copied boot files plus a full manifest/checksum listing for the ESP.

Future snapshots should continue under a board-specific bootstrap tree, e.g.:

- `bootstrap/orangepi6plus/<vendor-version>/`

Populate it with the exact boot artifacts currently used by the board, with
checksums and provenance.

That should include whatever is actually relevant on this board, for example:

- EFI binaries
- GRUB binaries/config
- board DTBs
- vendor kernel image if needed for comparison
- any lower-level bootloader blobs **only if** they are part of the bring-up
  surface we must reproduce

### 2. Capture and document the working boot chain

Mirror the 9front audit approach:

- add a board boot-chain status note
- add a fit-gap / comparison note
- keep extracted artifacts and disassembly snapshots in a reviewable tree

Suggested Haiku-side structure if this becomes necessary:

- `docs/BRINGUP-STATUS.md`
- `docs/FIT-GAP-AUDIT.md`
- `docs/disasm/orangepi6plus/<vendor-version>/`

### 3. Build a serial-first workflow

Before framebuffer or GUI work on real hardware:

- identify the working UART device on the board-facing side
- document cable/adapter assumptions
- create repo-level helper targets or scripts for serial capture
- keep the log path stable under `/workspace/tmp/...`

This is one of the most successful parts of the 9front workflow and should be
copied directly in spirit.

### 4. Only then decide whether U-Boot itself needs modification

Do not start by porting U-Boot blindly.

First determine:

- can existing EFI/GRUB boot Haiku artifacts directly?
- does Haiku need only a different loader handoff?
- is DTB passing the only board-specific issue?
- is a bootloader change actually required, or just a payload/layout change?

If the answer is still "yes, we need board-owned U-Boot work", then the next
step is to pin and analyze the actual Orange Pi 6 Plus bootloader artifacts, not
the Allwinner ones from 9front.

## Practical near-term plan for Haiku

### Recommended immediate path

1. keep QEMU `virt` + UEFI as the authoritative software validation lane
2. do **not** block physical bring-up on a new U-Boot effort
3. refresh and extend the Orange Pi 6 Plus ESP/boot snapshot as needed
   (`make orangepi6plus-efi-snapshot` for the working copy, then promote curated
   results into `bootstrap/orangepi6plus/` when they matter)
4. attempt Haiku physical boot through the existing EFI/GRUB path first
5. only if that fails for structural reasons, branch into a dedicated repo-owned
   board bootloader workflow

### Why this is the best fit so far

Because the current Haiku project has already achieved:

- reproducible package build
- reproducible image assembly
- reproducible QEMU desktop validation

The next unknown is board handoff, not package composition.

Using the board's current EFI-facing boot surface reduces the amount of new boot
infrastructure that must be solved at once.

## Assessment of U-Boot feasibility

### Feasible?

Yes, **methodologically**.

The 9front repo already shows how to make a hardware bring-up repo carry:

- pinned vendor boot artifacts
- extracted reference bootloader pieces
- auditable board boot notes
- repeatable image construction
- serial-first debugging discipline

### Immediately reusable?

No, **not directly**.

The Orange Pi 4 Pro path is an Allwinner-specific raw-blob flow. Orange Pi 6 Plus
work must start from Orange Pi 6 Plus artifacts.

### Should U-Boot be the first Orange Pi 6 Plus bring-up step?

Probably **no**.

The evidence on this host points to a currently working EFI/GRUB boot surface,
so that is the lower-risk first physical boot target.

## Working conclusion

The right plan is:

- copy the **9front workflow style**
- do **not** copy the **9front boot blobs or board assumptions**
- try **EFI-first** for Orange Pi 6 Plus physical Haiku boot
- add a board-specific U-Boot lane only if the EFI-first path proves inadequate

That gives the smallest-risk path from the already-working QEMU lane to real
hardware bring-up.