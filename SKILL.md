---
name: haiku-arm64-upstream-cherrypick
description: Check Haiku upstream, cherry-pick new upstream commits into rcarmo/haiku arm64-bootstrap-fixes, validate ARM64 VirtIO boot, and push.
---

# Haiku ARM64 upstream cherry-pick procedure

Use this procedure when asked to "check upstream", "cherry-pick upstream", or
refresh the local Haiku ARM64 branch.

## Scope and guardrails

- Operate from `/workspace/projects/haiku-build` on the Orange Pi 6 Plus host.
- Haiku source tree: `/workspace/projects/haiku-build/haiku`.
- Target branch: `arm64-bootstrap-fixes`.
- Upstream remote: `upstream` (`https://review.haiku-os.org/haiku`).
- Push remote: `github` (`https://github.com/rcarmo/haiku.git`).
- Do **not** touch dirty/generated `buildtools/` files unless explicitly asked.
- Use commit identity `Rui Carmo <rui.carmo@gmail.com>`.
- Prefer `make` targets from the wrapper repo for validation.

## 1. Preflight status

```bash
cd /workspace/projects/haiku-build
git status --short --branch
git -C haiku status --short --branch
git -C buildtools status --short --branch | sed -n '1,120p'
git -C haiku log --oneline -5 --decorate
```

Expected:

- wrapper repo may be clean or contain documentation changes you are making.
- `haiku/` should be on `arm64-bootstrap-fixes` and clean before cherry-picking.
- `buildtools/` may show dirty generated/toolchain files; leave them untouched.

## 2. Fetch upstream and identify unapplied commits

```bash
cd /workspace/projects/haiku-build/haiku
git fetch upstream master --tags
git log --oneline -5 --decorate upstream/master
git log --oneline -5 --decorate HEAD

git cherry -v HEAD upstream/master | grep '^+' || true
git cherry -v HEAD upstream/master | grep -c '^+' || true
```

Use `git cherry` rather than only `git log HEAD..upstream/master` because this
branch cherry-picks upstream and therefore has different commit IDs for already
applied changes. Lines beginning with:

- `-` are patch-equivalent and already applied.
- `+` are not yet applied and should be cherry-picked oldest-first.

## 3. Cherry-pick new upstream commits

```bash
cd /workspace/projects/haiku-build/haiku
commits=$(git cherry -v HEAD upstream/master | awk '/^\+/{print $2}')
for c in $commits; do
  echo "== cherry-pick $c $(git log -1 --format=%s "$c") =="
  git cherry-pick "$c"
done
```

If a conflict occurs:

1. inspect the conflicting files;
2. preserve local ARM64-specific changes (`virtio_block`, bootstrap fallbacks,
   PackageInstaller/regular-image ARM64 adjustments);
3. resolve with the smallest change;
4. run `git status --short`;
5. continue with `git cherry-pick --continue`.

After cherry-picking, confirm there are no remaining not-equivalent commits:

```bash
git cherry -v HEAD upstream/master | grep '^+' || true
```

## 4. Choose the validation hrev

Use the latest upstream `hrev*` tag reachable from `upstream/master`:

```bash
git describe --tags --match 'hrev*' upstream/master
```

Strip the `hrev` prefix when passing to `HREV`, for example `hrev59712` ->
`HREV=59712`.

## 5. Validate locally

From the wrapper repo:

```bash
cd /workspace/projects/haiku-build
make test HREV=<latest-hrev-number>
```

Then run an explicit VirtIO boot smoke on the generated image so the boot device
path and `/boot/system` registration are visible in the log:

```bash
set -o pipefail
timeout 60 qemu-system-aarch64 \
  -bios /usr/share/qemu-efi-aarch64/QEMU_EFI.fd \
  -M virt -cpu max -m 2048 \
  -device virtio-blk-device,drive=x0,bus=virtio-mmio-bus.0 \
  -drive file=/workspace/projects/haiku-build/haiku/generated.arm64/haiku-mmc.image,if=none,format=raw,id=x0 \
  -device ramfb -nographic -no-reboot \
  > /workspace/tmp/haiku-cherrypick-hrevNNNNN-smoke.log 2>&1
status=$?
strings /workspace/tmp/haiku-cherrypick-hrevNNNNN-smoke.log \
  | grep -E 'Welcome|kernel|PANIC|Mounted boot|volume at "/boot/system" registered|scheduler' \
  | head -100
# QEMU normally exits by timeout here.
test "$status" -eq 0 -o "$status" -eq 124
```

Required smoke markers:

```text
Mounted boot partition: /dev/disk/virtual/virtio_block/0/1
package_daemon: ... volume at "/boot/system" registered
```

There must be no `PANIC:` in the smoke log.

## 6. Push the Haiku branch

Only push after validation passes:

```bash
cd /workspace/projects/haiku-build/haiku
git push github arm64-bootstrap-fixes
```

## 7. Record the result

Update `/workspace/notes/haiku-arm64-build.md` with:

- date;
- upstream hrev;
- number of commits cherry-picked (or that there were no new commits);
- new branch head;
- validation command and smoke markers;
- push result.

If the wrapper repo changed (for example this `SKILL.md`), commit and push that
separately in `/workspace/projects/haiku-build`.
