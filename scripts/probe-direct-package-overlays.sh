#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd)
HAIKU_DIR=${HAIKU_DIR:-$REPO_DIR/haiku}
BUILD_DIR=${BUILD_DIR:-$HAIKU_DIR/generated.arm64}
BFS_FUSE=${BFS_FUSE:-/workspace/tmp/bfs_fuse}
BASE_IMAGE=${BASE_IMAGE:-/workspace/tmp/haiku-nightly-arm64/haiku-master-arm64-current-mmc.image}
DIRECT_HAIKU_HPKG=${DIRECT_HAIKU_HPKG:-/workspace/tmp/haiku-build/validated/haiku-direct-icu74.hpkg}
EXPAT_HPKG=${EXPAT_HPKG:-$BUILD_DIR/objects/haiku/arm64/packaging/repositories/HaikuPortsCross-build/packages/expat_bootstrap-2.5.0-1-arm64.hpkg}
ZSTD_HPKG=${ZSTD_HPKG:-/workspace/tmp/haiku-build/validated/zstd_runtime-1.5.6-1-arm64.hpkg}
HARNESS=${HARNESS:-$SCRIPT_DIR/qemu-desktop-harness.sh}
OUTPUT_DIR=${OUTPUT_DIR:-/workspace/tmp/haiku-overlay-probe}
MOUNT_POINT=${MOUNT_POINT:-/tmp/haiku-bfs-overlay-probe}
TIMEOUT_SECS=${TIMEOUT_SECS:-120}
KEEP_IMAGES=${KEEP_IMAGES:-0}

usage() {
  cat <<'EOF'
Probe the current direct-package overlay matrix on top of the stock ARM64 nightly.

Cases:
  - stock
  - direct_only
  - direct_plus_expat
  - direct_plus_zstd
  - direct_plus_zstd_expat

The script validates each case with qemu-desktop-harness.sh, writes per-case logs,
and generates summary.md + summary.tsv in the output directory.

The validated direct package currently prunes the optional Cortex demo so the
probe can distinguish the remaining mandatory zstd dependency from the now-
removed libexpat package-level dependency.

Environment overrides:
  BASE_IMAGE, DIRECT_HAIKU_HPKG, EXPAT_HPKG, ZSTD_HPKG, HARNESS,
  OUTPUT_DIR, BUILD_DIR, BFS_FUSE, TIMEOUT_SECS, KEEP_IMAGES
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

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)
      usage
      exit 0
      ;;
    --keep-images)
      KEEP_IMAGES=1
      shift
      ;;
    --timeout)
      TIMEOUT_SECS=${2:?missing value for --timeout}
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR=${2:?missing value for --output-dir}
      shift 2
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

mkdir -p "$OUTPUT_DIR"
require_file "$BASE_IMAGE"
require_file "$DIRECT_HAIKU_HPKG"
require_file "$EXPAT_HPKG"
require_file "$ZSTD_HPKG"
require_file "$HARNESS"
require_file "$BFS_FUSE"

SYSTEM_GEOM=$(sfdisk -d "$BASE_IMAGE" | awk -F'[ ,=]+' '/ : start=/{n++; if(n==2){for(i=1;i<=NF;i++){if($i=="start") s=$(i+1); else if($i=="size") z=$(i+1)} print s" "z; exit}}')
SYSTEM_START=${SYSTEM_GEOM%% *}
SYSTEM_SIZE=${SYSTEM_GEOM##* }
[[ -n "$SYSTEM_START" && -n "$SYSTEM_SIZE" ]] || { echo "failed to determine system partition geometry" >&2; exit 1; }

SUMMARY_TSV="$OUTPUT_DIR/summary.tsv"
SUMMARY_MD="$OUTPUT_DIR/summary.md"
: > "$SUMMARY_TSV"
{
  echo "# Direct package overlay probe"
  echo
  echo "- Base image: \
\`$BASE_IMAGE\`"
  echo "- Direct package: \
\`$DIRECT_HAIKU_HPKG\`"
  echo "- Expat overlay: \
\`$EXPAT_HPKG\`"
  echo "- Zstd overlay: \
\`$ZSTD_HPKG\`"
  echo "- Validation timeout: ${TIMEOUT_SECS}s"
  echo
  echo "| Case | Expected | Actual | Note |"
  echo "|---|---|---|---|"
} > "$SUMMARY_MD"

append_result() {
  local case_name=$1 expected=$2 actual=$3 note=$4
  printf '%s\t%s\t%s\t%s\n' "$case_name" "$expected" "$actual" "$note" >> "$SUMMARY_TSV"
  printf '| `%s` | `%s` | `%s` | %s |\n' "$case_name" "$expected" "$actual" "$note" >> "$SUMMARY_MD"
}

classify_result() {
  local log=$1 raw_status=$2
  local actual note

  if [[ "$raw_status" == "fail" ]]; then
    actual=fail
  else
    actual=pass
  fi

  if grep -q 'Volume::InitialVerify(): volume at "/boot/system" has problems:' "$log"; then
    actual=pass-with-issues
  fi

  if grep -q 'Cannot open file libzstd.so.1' "$log"; then
    note='missing libzstd.so.1'
  elif grep -q 'nothing provides lib:libexpat' "$log"; then
    note='missing lib:libexpat'
  elif [[ "$actual" == "pass-with-issues" ]]; then
    note='validation markers passed, but package_daemon reported /boot/system issues'
  else
    note=''
  fi

  printf '%s\t%s\n' "$actual" "$note"
}

validate_case() {
  local case_name=$1 image=$2 expected=$3
  local log="$OUTPUT_DIR/$case_name.validate.log"
  local raw_status=pass actual note

  if "$HARNESS" validate --timeout "$TIMEOUT_SECS" --image "$image" > "$log" 2>&1; then
    raw_status=pass
  else
    raw_status=fail
  fi

  IFS=$'\t' read -r actual note < <(classify_result "$log" "$raw_status")
  append_result "$case_name" "$expected" "$actual" "$note"

  echo "== $case_name =="
  echo "expected: $expected"
  echo "actual:   $actual"
  [[ -n "$note" ]] && echo "note:     $note"
  tail -n 18 "$log"
  echo

  if [[ "$actual" != "$expected" ]]; then
    echo "unexpected result for $case_name: expected $expected, got $actual" >&2
    return 1
  fi
}

mount_partition_copy() {
  local part_image=$1 bfs_log=$2
  sudo umount -l "$MOUNT_POINT" >/dev/null 2>&1 || true
  sudo rm -rf "$MOUNT_POINT"
  mkdir -p "$MOUNT_POINT"
  (
    cd "$BUILD_DIR"
    export LD_LIBRARY_PATH="$BUILD_DIR/objects/linux/lib"
    "$BFS_FUSE" "$part_image" "$MOUNT_POINT" > "$bfs_log" 2>&1
  ) &
  BFS_PID=$!
  sleep 2
}

flush_partition_copy() {
  local part_image=$1 full_image=$2
  sync
  fusermount -u "$MOUNT_POINT" >/dev/null 2>&1 || true
  wait "$BFS_PID" || true
  BFS_PID=
  dd if="$part_image" of="$full_image" bs=512 seek="$SYSTEM_START" conv=notrunc status=none
}

prepare_overlay_case() {
  local case_name=$1 add_expat=$2 add_zstd=$3
  local image="$OUTPUT_DIR/$case_name.img"
  local part_image="$OUTPUT_DIR/$case_name.part.img"
  local pkgdir

  cp --reflink=auto "$BASE_IMAGE" "$image"
  dd if="$image" of="$part_image" bs=512 skip="$SYSTEM_START" count="$SYSTEM_SIZE" status=none
  mount_partition_copy "$part_image" "$OUTPUT_DIR/$case_name.bfs.log"

  pkgdir="$MOUNT_POINT/myfs/system/packages"
  rm -f "$pkgdir"/haiku-r1~beta5_*-arm64.hpkg \
        "$pkgdir"/haiku-direct-*.hpkg \
        "$pkgdir"/expat_bootstrap-*.hpkg \
        "$pkgdir"/zstd_bootstrap-*.hpkg \
        "$pkgdir"/zstd_runtime-*.hpkg

  cp "$DIRECT_HAIKU_HPKG" "$pkgdir/"
  if (( add_expat )); then
    cp "$EXPAT_HPKG" "$pkgdir/"
  fi
  if (( add_zstd )); then
    cp "$ZSTD_HPKG" "$pkgdir/"
  fi

  flush_partition_copy "$part_image" "$image"

  if (( KEEP_IMAGES == 0 )); then
    rm -f "$part_image"
  fi

  printf '%s\n' "$image"
}

FAILURES=0

validate_case stock "$BASE_IMAGE" pass || FAILURES=$((FAILURES + 1))
validate_case direct_only "$(prepare_overlay_case direct_only 0 0)" fail || FAILURES=$((FAILURES + 1))
validate_case direct_plus_expat "$(prepare_overlay_case direct_plus_expat 1 0)" fail || FAILURES=$((FAILURES + 1))
validate_case direct_plus_zstd "$(prepare_overlay_case direct_plus_zstd 0 1)" pass || FAILURES=$((FAILURES + 1))
validate_case direct_plus_zstd_expat "$(prepare_overlay_case direct_plus_zstd_expat 1 1)" pass || FAILURES=$((FAILURES + 1))

if (( KEEP_IMAGES == 0 )); then
  rm -f "$OUTPUT_DIR"/*.img "$OUTPUT_DIR"/*.part.img 2>/dev/null || true
fi

cat <<EOF >> "$SUMMARY_MD"

## Interpretation

- \`stock\` should already validate on the newer rebootstrapped arm64 nightly.
- \`direct_only\` and \`direct_plus_expat\` should fail because the direct package still needs \`libzstd.so.1\`.
- \`direct_plus_zstd\` should now validate cleanly: the validated direct package prunes the optional Cortex demo and no longer requires \`lib:libexpat\`, and the current default zstd overlay is the smaller local \`zstd_runtime\` package.
- \`direct_plus_zstd_expat\` should also validate cleanly, but the extra expat overlay is now expected to be unnecessary.
EOF

cat "$SUMMARY_MD"

if (( FAILURES > 0 )); then
  exit 1
fi
