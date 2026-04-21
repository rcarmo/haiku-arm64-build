# ARM64 QEMU Boot Debug Notes (2026-04-21)

## Scope

These are in-repo engineering notes for the current ARM64 QEMU bring-up state, replacing out-of-repo references.

Focus of this cycle:

1. Keep boot progressing past kernel + packagefs mount.
2. Stabilize early userspace startup (`launch_daemon`, core servers).
3. Minimize package churn while testing runtime loader fixes.

## Current headline status

- Kernel boots in QEMU (`virt` machine), BFS mounts correctly.
- Boot partition is detected and mounted consistently in successful-path runs.
- Main blockers are now **package/runtime loader failures** and early userspace crash cascades.

Observed recurring failure signatures:

- `Failed to decompress chunk data: Operation not supported`
- `thread_hit_serious_debug_event(): Failed to install debugger: thread: 26 (launch_daemon): Bad port ID`
- `runtime_loader: ... Troubles relocating: Bad data`
- `debug_server: Thread <id> entered the debugger: Segment violation`

## Repositories and branches

### `haiku` repository

- Branch: `arm64-bootstrap-fixes`
- Upstream sync performed from `upstream/master` to include latest changes.
- Merge commit on branch: `e225951dd9`
- Previously landed local fix on this branch: `a0ee6cf196`
  - `scsi: avoid panic when requeue/resubmit sees unsent ccb`

### `haiku-arm64-build` repository (this repo)

- README updated to remove reference to non-shipped notes.
- This file added as shipped, detailed status notes.

## Experiment matrix (latest)

### Case A: pristine base + launch config override

Result:

- Boot reaches partition mount.
- Immediate early failure:
  - `thread_hit_serious_debug_event(): Failed to install debugger: thread: 26 (launch_daemon): Bad port ID`

Interpretation:

- Changing launch ordering/config alone does not solve the failure path.

---

### Case B: pristine base + non-packaged runtime/library stack overlays

Injected non-packaged libs/bin to satisfy loader deps (libroot/libstdc++/libgcc/libbe/network/bsd/icu/zlib/zstd etc.).

Result:

- Boot reaches mount.
- Failures include:
  - `Launching x-vnd.haiku-media_server failed: No such file or directory`
  - `could not fork: No such file or directory`
  - missing ICU soname path (`libicudata.so.67`) for `libbe.so` and `libroot-addon-icu.so`
  - thread segfaults (`debug_server: Thread 68 ... Segment violation`)
  - `consoled: error -4 starting console`

Interpretation:

- Dependency closure is still incomplete and/or ABI-incompatible in this configuration.

---

### Case C: Case B + explicit ICU67 overlays

Added ICU67 compatibility files (`libicu*.so.67`) and zlib compat.

Result:

- Some missing-ICU errors removed.
- New hard failures appear:
  - `runtime_loader: /boot/system/lib/libroot.so: Troubles relocating: Bad data`
  - additional segfault threads (`Thread 74`, `Thread 78`)
  - continuing service startup failures

Interpretation:

- This points to relocation/runtime-loader correctness issues, not just missing files.

---

### Case D: repacked `haiku` package (only `libroot.so` replaced)

Result:

- Widespread packagefs decompression failures begin:
  - multiple packages fail with `Failed to decompress chunk data: Operation not supported`
  - then `launch_daemon` fails due to unresolved deps (`libstdc++.so.6` etc.)

Interpretation:

- Broad repack/replacement of core package remains high-risk/noisy for root-cause isolation.

---

### Case E: repacked `haiku` with generated core libs + compatibility overlays

Result:

- Same decompression failures for key packages.
- `launch_daemon` `Bad port ID` still reproduced.

Interpretation:

- Repacking is not currently a stable path for isolating early-userspace crashes.

## Working conclusions

1. **Do not rely on broad repacks for diagnosis right now**
   - They trigger packagefs decompression errors and add noise.
2. **Keep SCSI anti-panic fix**
   - Prevents dead-end panic loops and allows deeper boot diagnostics.
3. **Primary blocker has moved to runtime loader + early service startup stability**
   - Missing dependencies and relocation faults combine into service crash cascades.

## Known recurring missing components in logs

- `libgame.so` (input_server shortcut catcher)
- `libscreensaver.so` (input_server screen saver filter)
- `x-vnd.haiku-media_server` launch target not found in failing path

These should be validated against the active package set in mounted `/boot/system` during failing boots.

## Immediate next steps

1. Run with the most pristine package set possible (no broad repack).
2. Add only minimal, auditable overlays needed for single-hypothesis tests.
3. Instrument `launch_daemon` startup sequence and correlate thread IDs to binary/service names.
4. Re-validate ARM64 relocation/TLS handling in runtime loader against current failing binaries.
5. Keep test output logs per case under `/workspace/tmp/` with stable naming for diffing.

## Reference log files (session)

- `/workspace/tmp/casePristine_np_libs_launchcfg.usb.log`
- `/workspace/tmp/casePristine_genstack.usb.log`
- `/workspace/tmp/casePristine_genstack_plus67.usb.log`
- `/workspace/tmp/caseOnlyRootPkg.usb.log`
- `/workspace/tmp/caseOnlyRootPkg_plusgcc.usb.log`
- `/workspace/tmp/caseOnlyRootPkg_plusgcc_icu.usb.log`
- `/workspace/tmp/caseHaikuGenlibs.usb.log`
