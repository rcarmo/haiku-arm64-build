#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd)
HAIKU_DIR=${HAIKU_DIR:-$REPO_DIR/haiku}
BUILD_DIR=${BUILD_DIR:-$HAIKU_DIR/generated.arm64}
PACKAGE_TOOL=${PACKAGE_TOOL:-$BUILD_DIR/objects/linux/arm64/release/tools/package/package}
BFS_FUSE=${BFS_FUSE:-/workspace/tmp/bfs_fuse}
BASE_IMAGE=${BASE_IMAGE:-/workspace/tmp/haiku-nightly-arm64/haiku-master-hrev59637-arm64-mmc.image}
REPACKED_DIR=${REPACKED_DIR:-/workspace/tmp/repacked-hpkg}
DIRECT_HAIKU_HPKG=${DIRECT_HAIKU_HPKG:-$BUILD_DIR/objects/haiku/arm64/packaging/packages/haiku.hpkg}
DIRECT_HAIKU_CONTENTS_DIR=${DIRECT_HAIKU_CONTENTS_DIR:-$BUILD_DIR/objects/haiku/arm64/packaging/packages_build/regular/hpkg_-haiku.hpkg/contents}
DIRECT_HAIKU_PACKAGE_INFO=${DIRECT_HAIKU_PACKAGE_INFO:-$BUILD_DIR/objects/haiku/arm64/packaging/packages_build/regular/hpkg_-haiku.hpkg/haiku-package-info}
EXPAT_HPKG=${EXPAT_HPKG:-$BUILD_DIR/objects/haiku/arm64/packaging/repositories/HaikuPortsCross-build/packages/expat_bootstrap-2.5.0-1-arm64.hpkg}
OUTPUT_DIR=${OUTPUT_DIR:-/workspace/tmp/haiku-build/validated}
OUTPUT_IMAGE=${OUTPUT_IMAGE:-$OUTPUT_DIR/haiku-arm64-icu74-desktop.boot.img}
OUTPUT_HAIKU_HPKG=${OUTPUT_HAIKU_HPKG:-$OUTPUT_DIR/haiku-direct-icu74.hpkg}
OUTPUT_COMPAT_HPKG=${OUTPUT_COMPAT_HPKG:-$OUTPUT_DIR/compat_bootstrap_runtime-1-2-arm64.hpkg}
MOUNT_POINT=${MOUNT_POINT:-/tmp/haiku-bfs-mount}
STAMP=$(date +%Y%m%d-%H%M%S)
WORK_DIR="$OUTPUT_DIR/work-$STAMP"
PART_IMAGE="$WORK_DIR/system.part.img"
COMPAT_STAGE="$WORK_DIR/compat_bootstrap_runtime-1-2-arm64"
GEN_PACKAGES=${GEN_PACKAGES:-$BUILD_DIR/build_packages}

usage() {
  cat <<'EOF'
Build a reproducible validated ICU74 desktop boot image for early QEMU testing.

Environment overrides:
  BASE_IMAGE, REPACKED_DIR, DIRECT_HAIKU_HPKG, DIRECT_HAIKU_CONTENTS_DIR,
  DIRECT_HAIKU_PACKAGE_INFO, EXPAT_HPKG, OUTPUT_DIR, OUTPUT_IMAGE,
  OUTPUT_HAIKU_HPKG, OUTPUT_COMPAT_HPKG, BUILD_DIR, PACKAGE_TOOL, BFS_FUSE
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
  if [[ -n "${BFS_PID:-}" ]]; then
    wait "$BFS_PID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

if [[ ${1:-} == --help || ${1:-} == -h ]]; then
  usage
  exit 0
fi

mkdir -p "$OUTPUT_DIR" "$WORK_DIR"

require_file "$PACKAGE_TOOL"
require_file "$BFS_FUSE"
require_file "$BASE_IMAGE"
require_file "$DIRECT_HAIKU_HPKG"
require_file "$DIRECT_HAIKU_PACKAGE_INFO"
[[ -d "$DIRECT_HAIKU_CONTENTS_DIR" ]] || { echo "missing dir: $DIRECT_HAIKU_CONTENTS_DIR" >&2; exit 1; }
require_file "$EXPAT_HPKG"
require_file "$REPACKED_DIR/bash-4.4.023-1-arm64.hpkg"
require_file "$REPACKED_DIR/coreutils-8.22-1-arm64.hpkg"

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

  # Keep the direct package close to the previously validated ICU74 desktop lane
  # until the fuller regular package is boot-stable on arm64.
  rm -f \
    "$stage_dir/servers/bluetooth_server" \
    "$stage_dir/servers/nfs4_idmapper_server" \
    "$stage_dir/apps/ActivityMonitor" \
    "$stage_dir/apps/AutoRaise" \
    "$stage_dir/apps/CodyCam" \
    "$stage_dir/apps/HaikuDepot" \
    "$stage_dir/apps/Icon-O-Matic" \
    "$stage_dir/apps/LegacyPackageInstaller" \
    "$stage_dir/apps/Magnify" \
    "$stage_dir/apps/Mail" \
    "$stage_dir/apps/MediaConverter" \
    "$stage_dir/apps/MediaPlayer" \
    "$stage_dir/apps/MidiPlayer" \
    "$stage_dir/apps/People" \
    "$stage_dir/apps/PoorMan" \
    "$stage_dir/apps/PowerStatus" \
    "$stage_dir/apps/RemoteDesktop" \
    "$stage_dir/apps/Screenshot" \
    "$stage_dir/apps/SerialConnect" \
    "$stage_dir/apps/SoftwareUpdater" \
    "$stage_dir/apps/SoundRecorder" \
    "$stage_dir/preferences/Bluetooth" \
    "$stage_dir/preferences/DataTranslations" \
    "$stage_dir/preferences/E-mail" \
    "$stage_dir/preferences/Printers" \
    "$stage_dir/preferences/Repositories" \
    "$stage_dir/preferences/ScreenSaver" \
    "$stage_dir/preferences/Sounds" \
    "$stage_dir/lib/libbluetooth.so"

  cp "$DIRECT_HAIKU_PACKAGE_INFO" "$package_info_copy"
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
}
lines = p.read_text().splitlines()
filtered = [line for line in lines if line.strip() not in remove]
p.write_text('\n'.join(filtered) + '\n')
PY
  "$PACKAGE_TOOL" create -0 -C "$stage_dir" -i "$package_info_copy" "$OUTPUT_HAIKU_HPKG"
}

assemble_image() {
  cp "$BASE_IMAGE" "$OUTPUT_IMAGE"
  dd if="$OUTPUT_IMAGE" of="$PART_IMAGE" bs=512 skip=65540 count=614400 status=none

  sudo umount -l "$MOUNT_POINT" >/dev/null 2>&1 || true
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
  find "$pkgdir" -maxdepth 1 -type f \
    \( -name 'haiku-*.hpkg' -o -name 'compat_bootstrap_runtime-*.hpkg' \) \
    -delete
  rm -f "$pkgdir/gcc_syslibs-13.2.0_2023_08_10-1-arm64.hpkg" \
        "$pkgdir/icu-67.1-2-arm64.hpkg" \
        "$pkgdir/zlib-1.2.13-1-arm64.hpkg" \
        "$pkgdir/expat_bootstrap-2.5.0-1-arm64.hpkg" \
        "$pkgdir/bash-4.4.023-1-arm64.hpkg" \
        "$pkgdir/coreutils-8.22-1-arm64.hpkg"

  cp "$OUTPUT_HAIKU_HPKG" "$pkgdir/$(basename "$OUTPUT_HAIKU_HPKG")"
  cp "$OUTPUT_COMPAT_HPKG" "$pkgdir/compat_bootstrap_runtime-1-2-arm64.hpkg"
  cp "$EXPAT_HPKG" "$pkgdir/"
  cp "$REPACKED_DIR/bash-4.4.023-1-arm64.hpkg" "$pkgdir/"
  cp "$REPACKED_DIR/coreutils-8.22-1-arm64.hpkg" "$pkgdir/"

  find "$MOUNT_POINT/myfs/system/non-packaged/lib" -maxdepth 1 -type f \
    \( -name 'libstdc++.so*' -o -name 'libgcc_s.so*' -o -name 'libicu*.so*' -o -name 'libzstd.so*' -o -name 'libz.so*' \) \
    -delete 2>/dev/null || true

  sync
  fusermount -u "$MOUNT_POINT" >/dev/null 2>&1 || true
  wait "$BFS_PID" || true
  BFS_PID=

  dd if="$PART_IMAGE" of="$OUTPUT_IMAGE" bs=512 seek=65540 conv=notrunc status=none
}

echo "== building compat runtime package =="
create_compat_package

echo "== building ICU74-consistent haiku package =="
create_haiku_package

echo "== assembling validated boot image =="
assemble_image

echo
ls -lh "$OUTPUT_COMPAT_HPKG" "$OUTPUT_HAIKU_HPKG" "$OUTPUT_IMAGE"
echo
echo "validated image: $OUTPUT_IMAGE"
