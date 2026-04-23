# ARM64 QEMU Boot Debug Notes (2026-04-23)

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

## Latest validated status (2026-04-23)

- `launch_daemon` env tail parsing fix is implemented in `haiku` commit `5059bc3bc8`.
- Clean-package validation has been completed (Case V), not just overlay-lane testing.
- The `Thread 51` / `consoled -4` crash has been traced to ICU67/ICU74 coexistence, and the validated ICU74-only lane no longer reproduces it.
- In the current ICU74-consistent package lane, `app_server`, `Tracker`, and `Deskbar` have all been directly validated as launching.
- The validated ICU74 lane now boots to a visible desktop session in QEMU; a later screenshot with Tracker visible has been added to the README/docs.
- A reproducible local build target now exists for the validated desktop image (`make desktop-image`).
- A detached tmux/QEMU harness exists for later regression work; the harness is useful for unattended boot fishing, but marker validation is still the stronger proof signal than framebuffer screenshots alone.

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

## Additional run set (post-upstream sync)

### Case F: true pristine nightly image baseline (`hrev59637`)

Result:

- Boot reaches mount, then packagefs repeatedly fails loading compressed package chunks:
  - `bash-4.4.023-1-arm64.hpkg`
  - `coreutils-8.22-1-arm64.hpkg`
  - `freetype-2.6.3-1-arm64.hpkg`
  - `gcc_syslibs-13.2.0_2023_08_10-1-arm64.hpkg`
  - `icu-67.1-2-arm64.hpkg`
  - `ncurses6-6.2-1-arm64.hpkg`
  - `zlib-1.2.13-1-arm64.hpkg`
- Follow-on failure:
  - `runtime_loader: Cannot open file libstdc++.so.6 (needed by /boot/system/servers/launch_daemon)`
  - `error starting "/boot/system/servers/launch_daemon"`

Interpretation:

- On a truly pristine image, package chunk decompression failure is a first-order blocker (not an artifact of prior modifications).

---

### Case G: pristine + only the 7 failing dependency packages repacked uncompressed

Result:

- Decompression failures disappear for those packages.
- New first failure becomes:
  - `runtime_loader: /boot/system/lib/libroot.so: Troubles relocating: Bad data`
  - `error starting "/boot/system/servers/launch_daemon" error = -2147483632`

Interpretation:

- Once package decompression is bypassed, the next hard blocker is arm64 relocation/runtime-loader handling for `libroot.so`.

---

### Case H: Case G + non-packaged generated `libroot.so`

Result:

- Relocation `Bad data` is bypassed.
- Failure shifts to:
  - `thread_hit_serious_debug_event(): Failed to install debugger: thread: 26 (launch_daemon): Bad port ID`

Interpretation:

- `libroot` replacement gets past relocation failure but still leaves early `launch_daemon` failure.

---

### Case I: Case H + launch config minimized (registrar-only / empty)

Result:

- Same `launch_daemon` `Bad port ID` failure reproduces even with near-empty launch config.

Interpretation:

- Failure is not caused by normal service/job graph complexity; likely in `launch_daemon` startup path itself (or earliest prerequisites).

---

### Case J: Case G + tiny `runtime_loader_override` package

Result:

- No observable change; still:
  - `runtime_loader: /boot/system/lib/libroot.so: Troubles relocating: Bad data`

Interpretation:

- A separate package carrying `runtime_loader` does not effectively override the active loader in this boot path.

---

### Case K: Case G + repacked `haiku` containing generated `runtime_loader`

Result:

- No observable change versus Case G:
  - `runtime_loader: /boot/system/lib/libroot.so: Troubles relocating: Bad data`

Interpretation:

- Replacing `runtime_loader` with the currently available generated binary had no effect.

---

### Case L: repacked deps + full generated launch/lib stack (libroot/libbe/libnetwork/libbnetapi/libbsd/launch_daemon + ICU74 overlays)

Result:

- Still fails at early userspace with:
  - `thread_hit_serious_debug_event(): Failed to install debugger: thread: 26 (launch_daemon): Bad port ID`

Interpretation:

- Even a largely self-consistent generated stack does not avoid the early `launch_daemon` crash path.

---

### Build-lane note: runtime_loader rebuild currently blocked

- `src/system/runtime_loader/arch/arm64/arch_relocate.cpp` is modified locally, but `generated.arm64/.../runtime_loader` is still byte-identical to stock (`sha256 8c210d01...`).
- Attempting `jam runtime_loader` currently fails due missing C++ header feature setup in this bootstrap configuration (`fatal error: algorithm: No such file or directory`), so source-side runtime_loader changes are not yet reflected in produced binaries.

### Case M: generated stack + core system launch (media/net removed), autologin kept

Result:

- `launch_daemon` no longer fails with `Bad port ID`.
- `Launching x-vnd.haiku-media_server failed` disappears once media service is removed from packaged launch config.
- Still sees userland crash pair:
  - `debug_server: Thread 50/52 entered the debugger: Segment violation`
  - `consoled: error -2/-4 starting console`

Interpretation:

- Media/net launch failures were secondary noise; core crash remains elsewhere.

---

### Case N: same as M but no autologin job

Result:

- Boot reaches mounted system + package daemon activity.
- No debug_server segment violations observed in this run window.

Interpretation:

- Entering user session is a major trigger for the current crash chain.

---

### Case O: same as M, autologin enabled, user launch file reduced to empty `run {}`

Result:

- No debug_server segment violations observed.

Interpretation:

- User session crash is tied to launched user services, not autologin mechanism alone.

---

### Case P: autologin + user launch with only `app_server`

Result:

- Immediate userland crash returns:
  - `debug_server: Thread 51 entered the debugger: Segment violation`
  - `consoled: error -4 starting console`

Interpretation:

- Minimal reproducer currently points at `app_server` path (or components it brings up, e.g. input/console chain).

---

### Case Q: Case P repeated with stock `app_server` binary (generated libs still in use)

Result:

- Same failure signature as Case P (`Thread 51` segfault + `consoled -4`).

Interpretation:

- Not specific to the generated `app_server` binary alone; likely shared runtime/library/adjacent service interaction in user session path.

---

### Case R: remove `env /system/boot/SetupEnvironment` from user-launched services

Result:

- With otherwise equivalent service launches, removing `env` eliminates the immediate crash signature.
- Reproduced for both app and input service variants:
  - no `debug_server ... Segment violation`
  - no `consoled: error -4`

Interpretation:

- Crash trigger is strongly tied to launch-daemon environment source-file processing, not specifically to app_server/input_server binaries.

---

### Case S: `service /bin/true` with `env /system/boot/SetupEnvironment`

Result:

- Even a trivial service binary (`/bin/true`) reproduces the same crash signature when `env` is present:
  - `debug_server: Thread 51 entered the debugger: Segment violation`
  - `consoled: error -4 starting console`

Interpretation:

- Confirms this is not GUI-server specific; `env` handling itself is sufficient to trigger corruption/failure.

---

### Case T: `job app_server` + `env /system/boot/SetupEnvironment`

Result:

- Job mode (non-service) also crashes when `env` is added.

Interpretation:

- Distinguishes issue from service-vs-job semantics; the common factor is `env` source-file resolution path.

---

### Suspected code-level fault (high-confidence)

`src/servers/launch/BaseJob.cpp`, `BaseJob::_GetSourceFileEnvironment()` appears to append the wrong byte count for trailing chunk data:

- in the `separator == NULL` branch it calls `line.Append(chunk, bytesRead)`
- `bytesRead` is for the whole buffer read, not the remaining chunk length

This can over-append stale bytes and plausibly corrupt parsed environment strings/state.

Fix applied in `haiku` branch `arm64-bootstrap-fixes`:

- commit `5059bc3bc8`
- change: use `end - chunk` for the trailing append length in `BaseJob::_GetSourceFileEnvironment()`

Note: runtime validation in guest is now complete for both non-packaged-overlay and clean-package lanes (Cases U and V below).

---

### Case U: post-fix revalidation + `SetupEnvironment` line-by-line bisect

Context:

- Boot image: generated-stack/repacked-deps lane (`..._icu74_gcc133`) where `/boot/system/non-packaged/lib` contains bootstrap compatibility libs.
- `launch_daemon` includes fix commit `5059bc3bc8`.

Observed:

- Full `env /system/boot/SetupEnvironment` still reproduces:
  - `debug_server: Thread 51 entered the debugger: Segment violation`
  - `consoled: error -4 starting console`
- However, targeted script bisect shows this is **not** a generic env parser failure after the tail-length fix:
  - minimal/locale/finddir-only fragments: no crash
  - near-full script without the non-packaged lib-path branch: no crash
  - adding only the SAFEMODE branch that sets extended `PATH`/`LIBRARY_PATH`/`ADDON_PATH` plus `locale` calls: crash returns deterministically
  - same branch + `id`/`finddir` (without `locale`): no crash
  - same `locale` calls but forcing `LIBRARY_PATH="%A/lib:/boot/system/lib"` (no non-packaged lib precedence): no crash
  - full script with `env SAFEMODE yes` (forcing safe branch in `SetupEnvironment`): no crash

Interpretation:

- In this lane, the segfault is consistent with `locale` (invoked by `SetupEnvironment`) loading incompatible compatibility libs through the non-packaged-first `LIBRARY_PATH` branch.

---

### Case V: clean-package validation (no non-packaged compat overlays)

Context:

- Created `haiku-r1~beta5_hrev59637-1-arm64-corelaunch-usersvctrue-fixonly.hpkg` by taking the known-stable `corelaunch-usersvctrue` package and replacing only `servers/launch_daemon` with the post-fix binary.
- Added a packaged compatibility bundle (`compat_bootstrap_runtime-1-1-arm64.hpkg`) for gcc13.3/icu74/zlib/zstd under `/boot/system/packages`.
- Explicitly removed runtime compat libs from `/boot/system/non-packaged/lib`.

Observed:

- Control run (no extra env-sourced service): no `Thread 51` segfault and no `consoled -4`.
- Adding `service test-env { env /system/boot/SetupEnvironment; launch /bin/true; }` reproduces:
  - `debug_server: Thread 51 entered the debugger: Segment violation`
  - `consoled: error -4 starting console`
- Adding `env SAFEMODE yes` before sourcing `SetupEnvironment` removes the crash again.

Interpretation:

- Clean-package confirmation is complete: the crash persists with fixed `launch_daemon` even without non-packaged overlays.
- The remaining trigger is still tied to the non-safe `SetupEnvironment` path (notably `locale` + compatibility runtime mix), not a generic parser-tail corruption symptom.
- Therefore, `5059bc3bc8` remains a valid correctness fix, but it is not sufficient by itself to eliminate this boot-lane crash signature.

---

### Case W: ICU version isolation — direct confirmation

Hypothesis: the `Thread 51` / `consoled -4` crash when sourcing `SetupEnvironment`
is caused by ICU67 and ICU74 coexisting in the package set, with `locale` loading
the wrong version.

Test matrix (all runs: fixed `launch_daemon`, `compat_bootstrap_runtime` = ICU74 +
gcc13.3 + zlib/zstd, no non-packaged overlays, no `gcc_syslibs-13.2` or stock `zlib`):

| Run | `icu-67.1` present | env mode | Result |
|---|---|---|---|
| `caseIcuBisect_noenv_noicu67` | No | none | **OK** |
| `caseIcuBisect_env_noicu67` | No | `SetupEnvironment` | **OK** |
| `caseIcuBisect_env_withicu67` | Yes | `SetupEnvironment` | **CRASH** |
| `caseIcuBisect_safemode_noicu67` | No | `SAFEMODE=yes + SetupEnvironment` | **OK** |

Interpretation:

- **Root cause confirmed: ICU version collision.** The `Thread 51` / `consoled -4`
  crash is fully explained by the simultaneous presence of `icu-67.1-2-arm64.hpkg`
  (ICU67) and `compat_bootstrap_runtime` (ICU74) in the package set.
- When only ICU74 is present, `env /system/boot/SetupEnvironment` with the full
  non-safe branch (including `locale` calls) no longer crashes.
- When ICU67 is re-added, the crash immediately returns.
- `SAFEMODE=yes` avoids the crash by skipping the branch that sets the
  non-packaged-first `LIBRARY_PATH` and runs `locale` — consistent with prior
  bisect results.
- The `5059bc3bc8` parser fix, SCSI anti-panic, and TLSDESC relocation fix are all
  still necessary to reach this point; none of them are invalidated by this finding.

**Current status: user session can reach and survive `SetupEnvironment` processing
when the package set contains a consistent single ICU version.**

---

### Case X: metadata-consistent ICU74 desktop lane

To remove remaining package solver noise, two local test packages were created:

- `compat_bootstrap_runtime-1-2-arm64.hpkg`
  - extends the earlier runtime bundle with proper `provides` metadata for
    `libgcc_s`, `libstdc++`, ICU74, zlib, zstd, and related runtime libs
- `haiku-r1~beta5_hrev59637-1-arm64-genservers-corelaunch-icu74meta.hpkg`
  - based on the generated core-launch package
  - includes fixed `launch_daemon`
  - adds generated `libroot-addon-icu.so`, `libmedia.so`, `libgame.so`,
    `libscreensaver.so`
  - updates `.PackageInfo` ICU requirements from `>=67.1` to `>=74.1`

Result:

- `package_daemon` reports `/boot/system` **consistent**.
- No `Thread 51` segfault, no `consoled -4`, and no remaining ICU67 loader errors.

Interpretation:

- The package set is now coherent enough for a real desktop-lane validation.
- The prior failures were not inherent to `SetupEnvironment` or the user session
  graph once package metadata and runtime libs were made version-consistent.

---

### Case Y: wrapped desktop launch confirmation

A final validation run wrapped the user-session launches to drop marker files before
`exec`-ing each program:

- `app_server`
- `Tracker`
- `Deskbar`

Resulting markers after boot:

- `marker-app_server-launch`: present
- `marker-tracker-launch`: present
- `marker-deskbar-launch`: present

Interpretation:

- The validated ICU74 desktop lane now launches the main desktop trio in-guest.
- This is the strongest direct confirmation so far that the current boot lane is
  past the earlier early-userspace blockers and into a functioning desktop session.

---

### Case Z: reproducible ICU74 desktop image target

The ad-hoc local package assembly used for Cases X/Y has now been codified into a
repo-shipped build script and Makefile target:

- script: `scripts/build-validated-desktop-image.sh`
- target: `make desktop-image`
- output image: `/workspace/tmp/haiku-build/validated/haiku-arm64-icu74-desktop.boot.img`

What this target does:

- rebuilds the `compat_bootstrap_runtime-1-2-arm64.hpkg` local runtime bundle
- rebuilds the ICU74-consistent `haiku` package variant from the generated core-launch lane
- assembles a bootable MMC image from the nightly base with the conflicting ICU67/gcc/zlib packages removed and the validated ICU74 packages installed

Interpretation:

- The validated desktop lane is now reproducible from the repo, rather than living only as one-off shell history and temp artifacts.

---

### Case AA: detached tmux harness and screenshot follow-up

The repo now also includes an async QEMU harness for later early-validation work:

- script: `scripts/qemu-desktop-harness.sh`
- Make targets:
  - `make desktop-run`
  - `make desktop-status`
  - `make desktop-logs`
  - `make desktop-attach`
  - `make desktop-screenshot`
  - `make desktop-stop`

Observed behavior:

- detached QEMU/tmux runs are useful for checking logs and grabbing framebuffer dumps without blocking the agent
- the latest framebuffer screenshot added to the README is still black / not a trustworthy proof of desktop usability
- the serial log in that detached run eventually stopped making useful progress, so the screenshot is weaker evidence than the marker-based `app_server`/`Tracker`/`Deskbar` validation from Case Y

Interpretation:

- The harness is good enough for regression fishing and unattended boot checks.
- It should not yet be treated as proof that the visual desktop is stable; for now, the direct marker validation remains authoritative.

## Working conclusions

1. **Do not rely on broad repacks for diagnosis right now**
   - They trigger packagefs decompression errors and add noise.
2. **Keep SCSI anti-panic fix**
   - Prevents dead-end panic loops and allows deeper boot diagnostics.
3. **The desktop lane now genuinely launches**
   - With the ICU74-consistent package set, `app_server`, `Tracker`, and `Deskbar`
     are all directly observed launching in-guest.
4. **The validated desktop lane is now reproducible from the repo**
   - `make desktop-image` assembles the current ICU74 desktop test image from the nightly base plus the validated local runtime/package overlays.
5. **`env /system/boot/SetupEnvironment` crash is an ICU version collision, confirmed**
   - Presence of both ICU67 (`icu-67.1-2-arm64.hpkg`) and ICU74 (`compat_bootstrap_runtime`)
     is the direct and sufficient trigger.
   - With a single consistent ICU version (ICU74 only), `SetupEnvironment` survives
     including `locale` calls under the full non-safe branch.
6. **`5059bc3bc8` is a valid correctness fix**
   - The `_GetSourceFileEnvironment()` tail-length bug is fixed and runtime-tested.
   - It does not interact with the ICU collision; both fixes are independently necessary.
7. **Package metadata consistency matters, not just file presence**
   - A runtime bundle without matching `provides` metadata still leaves `package_daemon`
     reporting an inconsistent volume.
   - Updating both runtime package `provides` and `haiku` ICU requirements was necessary
     for a clean desktop-lane validation.
8. **TLSDESC relocation support (`daa993f414`) is committed but not yet binary-verified**
   - `runtime_loader` rebuild is blocked by the bootstrap toolchain header gap.
   - Verification should be done once the full build chain can be assembled.

## Known recurring missing components in logs

- `libgame.so` (input_server shortcut catcher)
- `libscreensaver.so` (input_server screen saver filter)
- `x-vnd.haiku-media_server` launch target not found in failing path

These should be validated against the active package set in mounted `/boot/system` during failing boots.

## Immediate next steps

1. Turn the validated local ICU74 desktop lane into a cleaner packaged solution:
   either proper ICU74 packages for Haiku ARM64 or a reduced set of local runtime
   packages with correct metadata and minimal divergence.
2. Re-enable and validate more of the stock desktop/service graph beyond the
   current core-launch lane (media stack, input add-ons, mail/network adjuncts).
3. Improve the detached tmux harness so desktop-readiness detection is more robust
   than the current combination of serial-log heuristics and framebuffer dumps.
4. Unblock `runtime_loader` rebuild to verify the TLSDESC implementation
   (`daa993f414`) in-guest with a real TLS-using shared library.
5. Reduce remaining boot noise (`activated-packages` warnings, `/etc/shadow`
   warning) so the log surface is dominated by real blockers rather than image
   assembly artifacts.
6. Continue storing per-case logs under `/workspace/tmp/` with stable names for
   deterministic diffs.

## Reference log files (session)

- `/workspace/tmp/casePristine_np_libs_launchcfg.usb.log`
- `/workspace/tmp/casePristine_genstack.usb.log`
- `/workspace/tmp/casePristine_genstack_plus67.usb.log`
- `/workspace/tmp/caseOnlyRootPkg.usb.log`
- `/workspace/tmp/caseOnlyRootPkg_plusgcc.usb.log`
- `/workspace/tmp/caseOnlyRootPkg_plusgcc_icu.usb.log`
- `/workspace/tmp/caseHaikuGenlibs.usb.log`
- `/workspace/tmp/caseBaseline_pristine_hrev59637.usb.log`
- `/workspace/tmp/casePristine_repackDepsOnly.usb.log`
- `/workspace/tmp/casePristine_repackDeps_librootNP.usb.log`
- `/workspace/tmp/casePristine_repackDeps_rtldNP.usb.log`
- `/workspace/tmp/casePristine_repackDeps_rtldTopNP.usb.log`
- `/workspace/tmp/casePristine_repackDeps_librootNP_launchNP.usb.log`
- `/workspace/tmp/casePristine_repackDeps_librootNP_launchMinReg.usb.log`
- `/workspace/tmp/casePristine_repackDeps_librootNP_launchEmpty.usb.log`
- `/workspace/tmp/casePristine_pkgHaikuLaunchlibroot_repackDeps.usb.log`
- `/workspace/tmp/casePristine_repackDeps_rtldPkg.usb.log`
- `/workspace/tmp/casePristine_pkgHaikuRtld_repackDeps.usb.log`
- `/workspace/tmp/caseRepackDeps_genstack74.usb.log`
- `/workspace/tmp/casePkgGenLaunchStack_repackDeps_icu74_gcc133.usb.log`
- `/workspace/tmp/casePkgGenServersStack_repackDeps_icu74_gcc133.usb.log`
- `/workspace/tmp/casePkgGenServersStack_disableMediaNet.usb.log`
- `/workspace/tmp/casePkgGenServersCoreLaunch_repackDeps_icu74_gcc133.usb.log`
- `/workspace/tmp/casePkgGenServersCoreNoLogin_repackDeps_icu74_gcc133.usb.log`
- `/workspace/tmp/casePkgGenServersCoreLaunchUserMin_repackDeps_icu74_gcc133.usb.log`
- `/workspace/tmp/casePkgGenServersCoreLaunchUserApp_repackDeps_icu74_gcc133.usb.log`
- `/workspace/tmp/casePkgCoreLaunchUserApp_stockapp_repackDeps_icu74_gcc133.usb.log`
- `/workspace/tmp/caseSvcAppAltName.usb.log`
- `/workspace/tmp/caseSvcAppNoEnv.usb.log`
- `/workspace/tmp/caseSvcInputNoEnv.usb.log`
- `/workspace/tmp/caseJobAppEnv.usb.log`
- `/workspace/tmp/caseSvcTrueEnv.usb.log`
- `/workspace/tmp/caseBisect_inputsvc_plus_game_screensaver.usb.log`
- `/workspace/tmp/caseFull_r1.usb.log`
- `/workspace/tmp/caseFull_r2.usb.log`
- `/workspace/tmp/caseCombo3_r1.usb.log`
- `/workspace/tmp/caseCombo3_r2.usb.log`
- `/workspace/tmp/caseProbeA.usb.log`
- `/workspace/tmp/caseProbeA0.usb.log`
- `/workspace/tmp/caseProbeA_locale.usb.log`
- `/workspace/tmp/caseProbeA_locale_syslib.usb.log`
- `/workspace/tmp/caseCleanLane_envfix_noNP.usb.log`
- `/workspace/tmp/caseCleanLane_envfix_pkgcompat.usb.log`
- `/workspace/tmp/caseCleanLane_fixonly_pkgcompat_noenv.usb.log`
- `/workspace/tmp/caseCleanLane_fixonly_pkgcompat_env.usb.log`
- `/workspace/tmp/caseCleanLane_fixonly_pkgcompat_env_safemode.usb.log`
- `/workspace/tmp/caseIcuBisect_noenv_noicu67.usb.log`
- `/workspace/tmp/caseIcuBisect_env_noicu67.usb.log`
- `/workspace/tmp/caseIcuBisect_env_withicu67.usb.log`
- `/workspace/tmp/caseIcuBisect_safemode_noicu67.usb.log`
- `/workspace/tmp/caseFullDesktop_icu74only.usb.log`
- `/workspace/tmp/caseFullDesktop_icu74kits_v2.usb.log`
- `/workspace/tmp/caseFullDesktop_icu74meta.usb.log`
- `/workspace/tmp/caseFullDesktop_icu74meta_markers.usb.log`
- `/workspace/tmp/caseFullDesktop_icu74meta_wrapped.usb.log`
- `/workspace/tmp/haiku-boot-harness/caseFullDesktop_icu74meta.boot.20260423-070055.serial.log`
- `/workspace/tmp/haiku-boot-harness/caseFullDesktop_icu74meta.boot.20260423-070055.capture.log`
- `/workspace/tmp/haiku-boot-harness/haiku-desktop.ppm`
- `/workspace/tmp/haiku-boot-harness/haiku-desktop.png`
- `/workspace/tmp/haiku-build/validated/haiku-arm64-icu74-desktop.boot.img`
