#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd)
HAIKU_DIR=${HAIKU_DIR:-$REPO_DIR/haiku}
BUILD_DIR=${BUILD_DIR:-$HAIKU_DIR/generated.arm64}
PACKAGE_TOOL=${PACKAGE_TOOL:-$BUILD_DIR/objects/linux/arm64/release/tools/package/package}
BFS_SHELL=${BFS_SHELL:-$BUILD_DIR/objects/linux/arm64/release/tools/bfs_shell/bfs_shell}
BFS_FUSE=${BFS_FUSE:-/workspace/tmp/bfs_fuse}
BASE_IMAGE=${BASE_IMAGE:-/workspace/tmp/haiku-nightly-arm64/haiku-master-arm64-current-mmc.image}
DIRECT_HAIKU_HPKG=${DIRECT_HAIKU_HPKG:-$BUILD_DIR/objects/haiku/arm64/packaging/packages/haiku.hpkg}
DIRECT_HAIKU_CONTENTS_DIR=${DIRECT_HAIKU_CONTENTS_DIR:-$BUILD_DIR/objects/haiku/arm64/packaging/packages_build/regular/hpkg_-haiku.hpkg/contents}
DIRECT_HAIKU_PACKAGE_INFO=${DIRECT_HAIKU_PACKAGE_INFO:-$BUILD_DIR/objects/haiku/arm64/packaging/packages_build/regular/hpkg_-haiku.hpkg/haiku-package-info}
OUTPUT_DIR=${OUTPUT_DIR:-/workspace/tmp/haiku-build/validated}
ZSTD_SOURCE_HPKG=${ZSTD_SOURCE_HPKG:-$BUILD_DIR/objects/haiku/arm64/packaging/repositories/HaikuPortsCross-build/packages/zstd_bootstrap-1.5.6-1-arm64.hpkg}
DEFAULT_OUTPUT_ZSTD_HPKG=$OUTPUT_DIR/zstd_runtime-1.5.6-1-arm64.hpkg
ZSTD_HPKG=${ZSTD_HPKG:-$DEFAULT_OUTPUT_ZSTD_HPKG}
BASH_HPKG=${BASH_HPKG:-$BUILD_DIR/objects/haiku/arm64/packaging/repositories/HaikuPortsCross-build/packages/bash_bootstrap-4.4.023-1-arm64.hpkg}
COREUTILS_HPKG=${COREUTILS_HPKG:-$BUILD_DIR/objects/haiku/arm64/packaging/repositories/HaikuPortsCross-build/packages/coreutils_bootstrap-9.9-1-arm64.hpkg}
IMAGE_FLAVOR=${IMAGE_FLAVOR:-validation}
OUTPUT_IMAGE=${OUTPUT_IMAGE:-$OUTPUT_DIR/haiku-arm64-icu74-desktop.boot.img}
OUTPUT_HAIKU_HPKG=${OUTPUT_HAIKU_HPKG:-$OUTPUT_DIR/haiku-direct-icu74.hpkg}
OUTPUT_COMPAT_HPKG=${OUTPUT_COMPAT_HPKG:-$OUTPUT_DIR/compat_bootstrap_runtime-1-2-arm64.hpkg}
EXPAT_HPKG=${EXPAT_HPKG:-$BUILD_DIR/objects/haiku/arm64/packaging/repositories/HaikuPortsCross-build/packages/expat_bootstrap-2.5.0-1-arm64.hpkg}
OUTPUT_RELEASE_SHIM_HPKG=${OUTPUT_RELEASE_SHIM_HPKG:-$OUTPUT_DIR/release_requirements_shim-1-1-arm64.hpkg}
MOUNT_POINT=${MOUNT_POINT:-/tmp/haiku-bfs-mount}
OLD_MOUNT_POINT=${OLD_MOUNT_POINT:-/tmp/haiku-bfs-mount-old}
SYSTEM_PARTITION_MIB=${SYSTEM_PARTITION_MIB:-512}
SECTOR_SIZE=512
EFI_PARTITION_START=4
EFI_PARTITION_SECTORS=65536
SYSTEM_PARTITION_START=65540
BASE_SYSTEM_PARTITION_SECTORS=614400
SYSTEM_PARTITION_SECTORS=$((SYSTEM_PARTITION_MIB * 2048))
OUTPUT_IMAGE_SECTORS=$((SYSTEM_PARTITION_START + SYSTEM_PARTITION_SECTORS))
STAMP=$(date +%Y%m%d-%H%M%S)
WORK_DIR="$OUTPUT_DIR/work-$STAMP"
PART_IMAGE="$WORK_DIR/system.part.img"
COMPAT_STAGE="$WORK_DIR/compat_bootstrap_runtime-1-2-arm64"
GEN_PACKAGES=${GEN_PACKAGES:-$BUILD_DIR/build_packages}

usage() {
  cat <<'EOF'
Build a reproducible validated ICU74 desktop boot image for early QEMU testing.

Current default base image:
  - /workspace/tmp/haiku-nightly-arm64/haiku-master-arm64-current-mmc.image
    (managed by scripts/fetch-latest-arm64-nightly.sh)

Package overlay behavior:
  - IMAGE_FLAVOR=validation (default): add direct haiku + zstd_runtime and
    prune the optional Cortex demo/metadata for the core validation lane.
  - IMAGE_FLAVOR=full: keep the regular direct haiku package contents/metadata
    intact, add zstd_runtime + expat_bootstrap, and add a temporary local
    release_requirements_shim package for ARM64 providers that are still not
    available locally. This is a full-image prototype, not a final upstream
    package-quality release image.
  - legacy base: add direct haiku + compat_bootstrap_runtime
    + sanitized bash/coreutils bootstrap packages

Environment overrides:
  BASE_IMAGE, DIRECT_HAIKU_HPKG, DIRECT_HAIKU_CONTENTS_DIR,
  DIRECT_HAIKU_PACKAGE_INFO, ZSTD_SOURCE_HPKG, ZSTD_HPKG, BASH_HPKG,
  COREUTILS_HPKG, EXPAT_HPKG, OUTPUT_DIR, OUTPUT_IMAGE, OUTPUT_HAIKU_HPKG,
  OUTPUT_COMPAT_HPKG, OUTPUT_RELEASE_SHIM_HPKG, IMAGE_FLAVOR, BUILD_DIR,
  PACKAGE_TOOL, BFS_SHELL, BFS_FUSE, SYSTEM_PARTITION_MIB
EOF
}

require_file() {
  local path=$1
  [[ -f "$path" ]] || { echo "missing file: $path" >&2; exit 1; }
}

cleanup() {
  set +e
  if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
    fusermount -u "$MOUNT_POINT" >/dev/null 2>&1 || true
  fi
  if mountpoint -q "$OLD_MOUNT_POINT" 2>/dev/null; then
    fusermount -u "$OLD_MOUNT_POINT" >/dev/null 2>&1 || true
  fi
  if [[ -n "${BFS_PID:-}" ]]; then
    wait "$BFS_PID" >/dev/null 2>&1 || true
  fi
  if [[ -n "${OLD_BFS_PID:-}" ]]; then
    wait "$OLD_BFS_PID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

if [[ ${1:-} == --help || ${1:-} == -h ]]; then
  usage
  exit 0
fi

mkdir -p "$OUTPUT_DIR" "$WORK_DIR"

require_file "$PACKAGE_TOOL"
require_file "$BFS_SHELL"
require_file "$BFS_FUSE"
require_file "$BASE_IMAGE"
require_file "$DIRECT_HAIKU_HPKG"
require_file "$DIRECT_HAIKU_PACKAGE_INFO"
[[ -d "$DIRECT_HAIKU_CONTENTS_DIR" ]] || { echo "missing dir: $DIRECT_HAIKU_CONTENTS_DIR" >&2; exit 1; }

case "$IMAGE_FLAVOR" in
  validation|full) ;;
  *) echo "unsupported IMAGE_FLAVOR: $IMAGE_FLAVOR" >&2; exit 1 ;;
esac

if [[ "$ZSTD_HPKG" == "$DEFAULT_OUTPUT_ZSTD_HPKG" ]]; then
  require_file "$ZSTD_SOURCE_HPKG"
else
  require_file "$ZSTD_HPKG"
fi
if [[ "$IMAGE_FLAVOR" == "full" ]]; then
  require_file "$EXPAT_HPKG"
fi

EFFECTIVE_BASH_HPKG="$BASH_HPKG"

sanitize_bash_package_if_needed() {
  local inspect_dir="$WORK_DIR/bash-package-inspect"
  local stage_dir="$WORK_DIR/bash-package-stage"
  local package_info="$WORK_DIR/bash-package-info"

  rm -rf "$inspect_dir" "$stage_dir"
  mkdir -p "$inspect_dir" "$stage_dir"
  "$PACKAGE_TOOL" extract -C "$inspect_dir" "$BASH_HPKG" >/dev/null

  if ! grep -q 'global-writable-files' "$inspect_dir/.PackageInfo"; then
    return 0
  fi
  if ! grep -q 'settings/bashrc' "$inspect_dir/.PackageInfo"; then
    return 0
  fi

  echo "== sanitizing bash package metadata =="
  cp "$inspect_dir/.PackageInfo" "$package_info"
  python3 - "$package_info" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
text = p.read_text()
old = 'global-writable-files {\n\t"settings/bashrc" keep-old\n}\n'
if old not in text:
    raise SystemExit('expected bash global-writable-files block not found')
p.write_text(text.replace(old, ''))
PY

  cp -a "$inspect_dir/." "$stage_dir/"
  rm -f "$stage_dir/.PackageInfo"
  EFFECTIVE_BASH_HPKG="$WORK_DIR/$(basename "$BASH_HPKG")"
  "$PACKAGE_TOOL" create -0 -C "$stage_dir" -i "$package_info" "$EFFECTIVE_BASH_HPKG" >/dev/null
}

sanitize_bash_package_if_needed

create_zstd_runtime_package() {
  local inspect_dir="$WORK_DIR/zstd-runtime-inspect"
  local stage_dir="$WORK_DIR/zstd-runtime-stage"
  local package_info="$WORK_DIR/zstd-runtime.PackageInfo"
  local source_version source_version_base

  rm -rf "$inspect_dir" "$stage_dir"
  mkdir -p "$inspect_dir" "$stage_dir/lib"
  "$PACKAGE_TOOL" extract -C "$inspect_dir" "$ZSTD_SOURCE_HPKG" >/dev/null

  compgen -G "$inspect_dir/lib/libzstd.so*" >/dev/null \
    || { echo "missing libzstd payload in $ZSTD_SOURCE_HPKG" >&2; exit 1; }
  cp -a "$inspect_dir"/lib/libzstd.so* "$stage_dir/lib/"

  source_version=$(awk '$1 == "version" { print $2; exit }' "$inspect_dir/.PackageInfo")
  [[ -n "$source_version" ]] || { echo "failed to parse zstd version from $ZSTD_SOURCE_HPKG" >&2; exit 1; }
  source_version_base=${source_version%%-*}

  cat > "$package_info" <<EOF
name	zstd_runtime
version	$source_version
summary	"Zstandard runtime compatibility package for ARM64 validation"
description	"Packaged libzstd runtime extracted from the locally built zstd bootstrap package for ARM64 desktop validation."
vendor	"Local"
packager	"Local"
architecture	arm64
copyrights	"2026 Local"
licenses	{
	MIT
}
provides	{
	zstd_runtime=$source_version_base
	lib:libzstd=$source_version_base compat>=1
}
requires	{
	haiku
}
flags	system_package
EOF

  "$PACKAGE_TOOL" create -0 -C "$stage_dir" -i "$package_info" "$ZSTD_HPKG" >/dev/null
}

create_release_requirements_shim_package() {
  local stage_dir="$WORK_DIR/release-requirements-shim"
  local package_info="$WORK_DIR/release-requirements-shim.PackageInfo"
  rm -rf "$stage_dir"
  mkdir -p "$stage_dir/documentation/packages/release_requirements_shim"
  cat > "$stage_dir/documentation/packages/release_requirements_shim/README" <<'EOF'
Temporary ARM64 full-image dependency shim.

This package exists to let the full-image prototype carry the unpruned regular
haiku.hpkg while the ARM64 HaikuPorts package closure is being completed. Replace
this package with real providers before treating the full image as a final
standard release image.
EOF

  cat > "$package_info" <<'EOF'
name	release_requirements_shim
version	1-1
summary	"Temporary ARM64 full-image dependency shim"
description	"Temporary dependency shim for the ARM64 full-image prototype. Replace with real HaikuPorts providers before a final standard release image."
vendor	"Local"
packager	"Local"
architecture	arm64
copyrights	"2026 Local"
licenses	{
	MIT
}
provides	{
	release_requirements_shim=1
	cmd:bunzip2=1
	cmd:gunzip=1
	cmd:tar=1
	cmd:unzip=1
	intel_wifi_firmwares=1
	noto_sans_cjk_jp=1
	ralink_wifi_firmwares=1
	realtek_wifi_firmwares=1
}
requires	{
	haiku
}
flags	system_package
EOF

  "$PACKAGE_TOOL" create -0 -C "$stage_dir" -i "$package_info" "$OUTPUT_RELEASE_SHIM_HPKG" >/dev/null
}

create_compat_package() {
  rm -rf "$COMPAT_STAGE"
  mkdir -p "$COMPAT_STAGE/lib"

  cp -a "$GEN_PACKAGES/gcc_bootstrap_syslibs-13.3.0_2026_03_29-1-arm64/lib/"*.so* "$COMPAT_STAGE/lib/"
  cp -a "$GEN_PACKAGES/icu74_bootstrap-74.1-1-arm64/lib/libicu"*.so* "$COMPAT_STAGE/lib/"
  cp -a "$GEN_PACKAGES/zlib_bootstrap-1.2.13-1-arm64/lib/"*.so* "$COMPAT_STAGE/lib/"
  cp -a "$GEN_PACKAGES/zstd_bootstrap-1.5.6-1-arm64/lib/"*.so* "$COMPAT_STAGE/lib/"

  cat > "$COMPAT_STAGE/.PackageInfo" <<'EOF'
name	compat_bootstrap_runtime
version	1-2
summary	"Bootstrap runtime compatibility libs for ARM64 bring-up"
description	"Packaged runtime compatibility libraries (gcc13.3, ICU74, zlib, zstd) with proper provides metadata for ARM64 boot validation."
vendor	"Local"
packager	"Local"
architecture	arm64
copyrights	"2026 Local"
licenses	{
	MIT
}
provides	{
	compat_bootstrap_runtime=1
	gcc_bootstrap_syslibs=13.3.0_2026_03_29 compat>=7
	gcc_syslibs=13.3.0_2026_03_29 compat>=7
	lib:libatomic=1.2.0 compat>=1
	lib:libgcc_s=1 compat>=1
	lib:libgomp=1.0.0 compat>=1
	lib:libssp=0.0.0 compat>=0
	lib:libstdc++=6.0.32 compat>=6
	lib:libsupc++=13.3.0_2026_03_29 compat>=7
	lib:libicudata=74.1 compat>=74
	lib:libicui18n=74.1 compat>=74
	lib:libicuio=74.1 compat>=74
	lib:libicuuc=74.1 compat>=74
	lib:libz=1.2.13 compat>=1
	lib:libzstd=1.5.6 compat>=1
}
requires	{
	haiku
}
flags	 system_package
EOF

  "$PACKAGE_TOOL" create -0 -C "$COMPAT_STAGE" -i "$COMPAT_STAGE/.PackageInfo" "$OUTPUT_COMPAT_HPKG"
}

create_haiku_package() {
  local package_info_copy="$WORK_DIR/haiku.package-info"
  local stage_dir="$WORK_DIR/haiku.contents"
  rm -rf "$stage_dir"
  mkdir -p "$stage_dir"
  cp -a "$DIRECT_HAIKU_CONTENTS_DIR/." "$stage_dir/"

  cp "$DIRECT_HAIKU_PACKAGE_INFO" "$package_info_copy"

  if [[ "$IMAGE_FLAVOR" == "validation" ]]; then
    rm -f "$stage_dir/demos/Cortex" "$stage_dir/data/deskbar/menu/Demos/Cortex"
    python3 - "$package_info_copy" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
remove = {
    'noto_sans_cjk_jp',
    'intel_wifi_firmwares',
    'ralink_wifi_firmwares',
    'realtek_wifi_firmwares',
    'cmd:bunzip2',
    'cmd:gunzip',
    'cmd:tar',
    'cmd:unzip',
    'lib:libexpat',
}
lines = p.read_text().splitlines()
filtered = [line for line in lines if line.strip() not in remove]
p.write_text('\n'.join(filtered) + '\n')
PY
  fi
  "$PACKAGE_TOOL" create -0 -C "$stage_dir" -i "$package_info_copy" "$OUTPUT_HAIKU_HPKG"
}

assemble_image() {
  local old_part_image="$WORK_DIR/system.base.part.img"
  local partition_table="$WORK_DIR/partition-table.sfdisk"

  cp "$BASE_IMAGE" "$OUTPUT_IMAGE"
  truncate -s $((OUTPUT_IMAGE_SECTORS * SECTOR_SIZE)) "$OUTPUT_IMAGE"

  cat > "$partition_table" <<EOF
label: dos
label-id: 0x00000000
device: $OUTPUT_IMAGE
unit: sectors
sector-size: $SECTOR_SIZE

$OUTPUT_IMAGE"1 : start=$EFI_PARTITION_START, size=$EFI_PARTITION_SECTORS, type=ef
$OUTPUT_IMAGE"2 : start=$SYSTEM_PARTITION_START, size=$SYSTEM_PARTITION_SECTORS, type=eb
EOF
  python3 - "$partition_table" "$OUTPUT_IMAGE" "$SYSTEM_PARTITION_START" "$SYSTEM_PARTITION_SECTORS" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
image = sys.argv[2]
start = sys.argv[3]
size = sys.argv[4]
path.write_text(
    f"label: dos\n"
    f"label-id: 0x00000000\n"
    f"device: {image}\n"
    f"unit: sectors\n"
    f"sector-size: 512\n\n"
    f"{image}1 : start=4, size=65536, type=ef\n"
    f"{image}2 : start={start}, size={size}, type=eb\n"
)
PY
  sfdisk --force "$OUTPUT_IMAGE" < "$partition_table" >/dev/null

  dd if="$BASE_IMAGE" of="$old_part_image" bs=$SECTOR_SIZE \
    skip=$SYSTEM_PARTITION_START count=$BASE_SYSTEM_PARTITION_SECTORS status=none
  truncate -s $((SYSTEM_PARTITION_SECTORS * SECTOR_SIZE)) "$PART_IMAGE"

  (
    cd "$BUILD_DIR"
    export LD_LIBRARY_PATH="$BUILD_DIR/objects/linux/lib"
    "$BFS_SHELL" --initialize "$PART_IMAGE" Haiku >/dev/null
  )

  sudo umount -l "$OLD_MOUNT_POINT" >/dev/null 2>&1 || true
  sudo umount -l "$MOUNT_POINT" >/dev/null 2>&1 || true
  sudo rm -rf "$OLD_MOUNT_POINT" "$MOUNT_POINT"
  mkdir -p "$OLD_MOUNT_POINT" "$MOUNT_POINT"

  (
    cd "$BUILD_DIR"
    export LD_LIBRARY_PATH="$BUILD_DIR/objects/linux/lib"
    "$BFS_FUSE" "$old_part_image" "$OLD_MOUNT_POINT" >"$WORK_DIR/bfs-fuse-old.log" 2>&1
  ) &
  OLD_BFS_PID=$!
  (
    cd "$BUILD_DIR"
    export LD_LIBRARY_PATH="$BUILD_DIR/objects/linux/lib"
    "$BFS_FUSE" "$PART_IMAGE" "$MOUNT_POINT" >"$WORK_DIR/bfs-fuse.log" 2>&1
  ) &
  BFS_PID=$!
  sleep 2

  cp -a --no-preserve=timestamps "$OLD_MOUNT_POINT/myfs/." "$MOUNT_POINT/myfs/"
  sync
  fusermount -u "$OLD_MOUNT_POINT" >/dev/null 2>&1 || true
  wait "$OLD_BFS_PID" || true
  OLD_BFS_PID=
  fusermount -u "$MOUNT_POINT" >/dev/null 2>&1 || true
  wait "$BFS_PID" || true
  BFS_PID=

  sudo rm -rf "$MOUNT_POINT"
  mkdir -p "$MOUNT_POINT"
  (
    cd "$BUILD_DIR"
    export LD_LIBRARY_PATH="$BUILD_DIR/objects/linux/lib"
    "$BFS_FUSE" "$PART_IMAGE" "$MOUNT_POINT" >"$WORK_DIR/bfs-fuse.log" 2>&1
  ) &
  BFS_PID=$!
  sleep 2

  local pkgdir="$MOUNT_POINT/myfs/system/packages"
  local modern_base_deps=0
  if ls "$pkgdir"/bash-*_bootstrap-*-arm64.hpkg >/dev/null 2>&1 \
      && ls "$pkgdir"/coreutils-*_bootstrap-*-arm64.hpkg >/dev/null 2>&1 \
      && ls "$pkgdir"/gcc_syslibs-*_bootstrap-*-arm64.hpkg >/dev/null 2>&1 \
      && ls "$pkgdir"/icu74-*_bootstrap-*-arm64.hpkg >/dev/null 2>&1 \
      && ls "$pkgdir"/zlib-*_bootstrap-*-arm64.hpkg >/dev/null 2>&1; then
    modern_base_deps=1
    echo "== detected modern bootstrap base package set =="
  else
    echo "== detected legacy base package set =="
    require_file "$BASH_HPKG"
    require_file "$COREUTILS_HPKG"
    echo "== sanitizing/creating legacy compatibility packages =="
    sanitize_bash_package_if_needed
    create_compat_package
  fi

  find "$pkgdir" -maxdepth 1 -type f \
    \( -name 'haiku-*.hpkg' -o -name 'compat_bootstrap_runtime-*.hpkg' -o -name 'expat_bootstrap-*.hpkg' -o -name 'release_requirements_shim-*.hpkg' -o -name 'zstd_bootstrap-*.hpkg' -o -name 'zstd_runtime-*.hpkg' \) \
    -delete

  if (( modern_base_deps )); then
    rm -f "$pkgdir/bash_bootstrap-4.4.023-1-arm64.hpkg" \
          "$pkgdir/coreutils_bootstrap-9.9-1-arm64.hpkg"
    cp "$OUTPUT_HAIKU_HPKG" "$pkgdir/$(basename "$OUTPUT_HAIKU_HPKG")"
    cp "$ZSTD_HPKG" "$pkgdir/"
    if [[ "$IMAGE_FLAVOR" == "full" ]]; then
      cp "$EXPAT_HPKG" "$pkgdir/"
      cp "$OUTPUT_RELEASE_SHIM_HPKG" "$pkgdir/"
      # The regular package set includes FirstBootPrompt. In unattended QEMU
      # validation it races with the marker launch jobs and can trip
      # "Can't reconnect to app server!" debugger calls. Seed the normal locale
      # settings sentinel so the standard image boots directly to the desktop.
      mkdir -p "$MOUNT_POINT/myfs/home/config/settings"
      : > "$MOUNT_POINT/myfs/home/config/settings/Locale settings"
    fi
  else
    rm -f "$pkgdir/gcc_syslibs-13.2.0_2023_08_10-1-arm64.hpkg" \
          "$pkgdir/icu-67.1-2-arm64.hpkg" \
          "$pkgdir/zlib-1.2.13-1-arm64.hpkg" \
          "$pkgdir/bash-4.4.023-1-arm64.hpkg" \
          "$pkgdir/bash_bootstrap-4.4.023-1-arm64.hpkg" \
          "$pkgdir/coreutils-8.22-1-arm64.hpkg" \
          "$pkgdir/coreutils_bootstrap-9.9-1-arm64.hpkg"

    cp "$OUTPUT_HAIKU_HPKG" "$pkgdir/$(basename "$OUTPUT_HAIKU_HPKG")"
    cp "$OUTPUT_COMPAT_HPKG" "$pkgdir/compat_bootstrap_runtime-1-2-arm64.hpkg"
    cp "$EFFECTIVE_BASH_HPKG" "$pkgdir/"
    cp "$COREUTILS_HPKG" "$pkgdir/"
  fi

  find "$MOUNT_POINT/myfs/system/non-packaged/lib" -maxdepth 1 -type f \
    \( -name 'libstdc++.so*' -o -name 'libgcc_s.so*' -o -name 'libicu*.so*' -o -name 'libzstd.so*' -o -name 'libz.so*' \) \
    -delete 2>/dev/null || true

  sync
  fusermount -u "$MOUNT_POINT" >/dev/null 2>&1 || true
  wait "$BFS_PID" || true
  BFS_PID=

  dd if="$PART_IMAGE" of="$OUTPUT_IMAGE" bs=$SECTOR_SIZE \
    seek=$SYSTEM_PARTITION_START conv=notrunc status=none
}

echo "== building zstd runtime package =="
if [[ "$ZSTD_HPKG" == "$DEFAULT_OUTPUT_ZSTD_HPKG" ]]; then
  create_zstd_runtime_package
else
  echo "== using provided zstd package: $ZSTD_HPKG =="
fi

if [[ "$IMAGE_FLAVOR" == "full" ]]; then
  echo "== building full-image release requirements shim package =="
  create_release_requirements_shim_package
fi

echo "== building ICU74-consistent haiku package ($IMAGE_FLAVOR) =="
create_haiku_package

echo "== assembling validated boot image =="
assemble_image

echo
if [[ "$IMAGE_FLAVOR" == "full" ]]; then
  ls -lh "$ZSTD_HPKG" "$OUTPUT_RELEASE_SHIM_HPKG" "$OUTPUT_HAIKU_HPKG" "$OUTPUT_IMAGE"
else
  ls -lh "$ZSTD_HPKG" "$OUTPUT_HAIKU_HPKG" "$OUTPUT_IMAGE"
fi
if [[ -f "$OUTPUT_COMPAT_HPKG" ]]; then
  ls -lh "$OUTPUT_COMPAT_HPKG"
fi
echo
echo "validated zstd package: $ZSTD_HPKG"
echo "validated image: $OUTPUT_IMAGE"
