#!/usr/bin/env bash
set -euo pipefail

ESP_DEV=${ESP_DEV:-/dev/nvme0n1p1}
OUTPUT_DIR=${OUTPUT_DIR:-/workspace/tmp/orangepi6plus-efi-snapshot/latest}
INCLUDE_LARGE=${INCLUDE_LARGE:-0}
MOUNT_POINT=

usage() {
  cat <<'EOF'
Snapshot the current Orange Pi 6 Plus EFI/GRUB boot surface.

By default this copies the smaller boot-surface artifacts plus a complete
manifest/checksum listing for the whole ESP. Large files such as IMAGE and
ROOTFS.CPIO.GZ are only checksummed unless --include-large is used.

Options:
  --esp-dev PATH       ESP block device (default: /dev/nvme0n1p1)
  --output-dir PATH    Snapshot output directory
  --include-large      Also copy IMAGE and ROOTFS.CPIO.GZ into the snapshot
  -h, --help           Show this help

Outputs:
  METADATA.txt
  ESP-TREE.txt
  manifest.tsv
  SHA256SUMS
  copied artifact files under their ESP-relative paths
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --esp-dev)
      ESP_DEV=${2:?missing value for --esp-dev}
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR=${2:?missing value for --output-dir}
      shift 2
      ;;
    --include-large)
      INCLUDE_LARGE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

require_file() {
  local path=$1
  [[ -e "$path" ]] || { echo "missing path: $path" >&2; exit 1; }
}

cleanup() {
  set +e
  if [[ -n "${MOUNT_POINT:-}" ]]; then
    sudo umount "$MOUNT_POINT" >/dev/null 2>&1 || true
    rmdir "$MOUNT_POINT" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

require_file "$ESP_DEV"
mkdir -p "$OUTPUT_DIR"
MOUNT_POINT=$(mktemp -d)
sudo mount -o ro "$ESP_DEV" "$MOUNT_POINT"

blkid_value() {
  local key=$1
  sudo blkid -s "$key" -o value "$ESP_DEV" 2>/dev/null || true
}

UUID=$(blkid_value UUID)
PARTUUID=$(blkid_value PARTUUID)
FSTYPE=$(blkid_value TYPE)

cat > "$OUTPUT_DIR/METADATA.txt" <<EOF
snapshot_time_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
hostname=$(hostname)
source_device=$ESP_DEV
uuid=$UUID
partuuid=$PARTUUID
fstype=$FSTYPE
include_large=$INCLUDE_LARGE
EOF

(
  cd "$MOUNT_POINT"
  find . -maxdepth 3 -type f | sort | sed 's#^\./##'
) > "$OUTPUT_DIR/ESP-TREE.txt"

(
  cd "$MOUNT_POINT"
  find . -maxdepth 3 -type f -printf '%P\t%s\n' | sort
) > "$OUTPUT_DIR/manifest.tsv"

(
  cd "$MOUNT_POINT"
  find . -maxdepth 3 -type f -print0 | sort -z | xargs -0 sha256sum | sed 's# \*\./#  #' | sed 's# \./#  #'
) > "$OUTPUT_DIR/SHA256SUMS"

copy_rel() {
  local rel=$1
  if [[ -f "$MOUNT_POINT/$rel" ]]; then
    mkdir -p "$OUTPUT_DIR/$(dirname "$rel")"
    cp -a "$MOUNT_POINT/$rel" "$OUTPUT_DIR/$rel"
  fi
}

SMALL_FILES=(
  EFI/BOOT/BOOTAA64.EFI
  GRUB/GRUB.CFG
  GRUB/GRUB.CFG.bak-20260308T180151Z
  SKY1-EVB.DTB
  SKY1-EVB-ISO.DTB
  SKY1-ORANGEPI-6-PLUS.DTB
  SKY1-ORANGEPI-6-PLUS-40PIN.DTB
  SKY1-ORANGEPI-6-PLUS-40PIN-PWM.DTB
)

for rel in "${SMALL_FILES[@]}"; do
  copy_rel "$rel"
done

if (( INCLUDE_LARGE )); then
  copy_rel IMAGE
  copy_rel ROOTFS.CPIO.GZ
fi

echo "snapshot: $OUTPUT_DIR"
echo "device:   $ESP_DEV"
echo "uuid:     $UUID"
echo "copied:"
find "$OUTPUT_DIR" -maxdepth 3 -type f | sort | sed "s#^$OUTPUT_DIR/##"
