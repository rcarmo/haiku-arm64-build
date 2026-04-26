#!/usr/bin/env bash
set -euo pipefail

BASE_URL=${BASE_URL:-https://download.haiku-os.org/nightly-images/arm64/}
OUT_DIR=${OUT_DIR:-/workspace/tmp/haiku-nightly-arm64}
CURRENT_IMAGE_LINK=${CURRENT_IMAGE_LINK:-$OUT_DIR/haiku-master-arm64-current-mmc.image}
CURRENT_ZIP_LINK=${CURRENT_ZIP_LINK:-$OUT_DIR/haiku-master-arm64-current-mmc.zip}
CURRENT_README_LINK=${CURRENT_README_LINK:-$OUT_DIR/ReadMe-current.md}
HREV=
FORCE=0
PRINT_PATH=0
LIST_ONLY=0

usage() {
  cat <<'EOF'
Fetch a Haiku ARM64 nightly MMC image and update stable local symlinks.

Options:
  --hrev <rev>     Fetch a specific revision (e.g. 59653 or hrev59653)
  --force          Re-download the zip and re-extract the image
  --print-path     Print the resolved image path only
  --list           List available arm64 nightly MMC revisions
  -h, --help       Show this help

Outputs in /workspace/tmp/haiku-nightly-arm64 by default:
  haiku-master-hrevNNNNN-arm64-mmc.zip
  haiku-master-hrevNNNNN-arm64-mmc.image
  haiku-master-arm64-current-mmc.zip      -> latest/specified zip
  haiku-master-arm64-current-mmc.image    -> latest/specified image
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --hrev)
      HREV=${2:?missing value for --hrev}
      shift 2
      ;;
    --force)
      FORCE=1
      shift
      ;;
    --print-path)
      PRINT_PATH=1
      shift
      ;;
    --list)
      LIST_ONLY=1
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

mkdir -p "$OUT_DIR"

fetch_index() {
  curl -fsSL "$BASE_URL"
}

list_zip_names() {
  fetch_index \
    | grep -o 'haiku-master-hrev[0-9]\+-arm64-mmc.zip' \
    | sort -Vu
}

if (( LIST_ONLY )); then
  list_zip_names
  exit 0
fi

if [[ -n "$HREV" ]]; then
  HREV=${HREV#hrev}
  ZIP_NAME="haiku-master-hrev${HREV}-arm64-mmc.zip"
  if ! list_zip_names | grep -qx "$ZIP_NAME"; then
    echo "revision not found in arm64 nightly index: hrev${HREV}" >&2
    exit 1
  fi
else
  ZIP_NAME=$(list_zip_names | tail -n 1)
  [[ -n "$ZIP_NAME" ]] || { echo "no arm64 nightly zip entries found" >&2; exit 1; }
fi

IMAGE_NAME=${ZIP_NAME%.zip}.image
ZIP_PATH="$OUT_DIR/$ZIP_NAME"
IMAGE_PATH="$OUT_DIR/$IMAGE_NAME"
README_PATH="$OUT_DIR/ReadMe.md"
ZIP_URL="https://haiku-nightly.cdn.haiku-os.org/arm64/$ZIP_NAME"

if (( FORCE )) || [[ ! -f "$ZIP_PATH" ]]; then
  echo "== downloading $ZIP_NAME =="
  rm -f "$ZIP_PATH"
  curl -L --fail --progress-bar -o "$ZIP_PATH" "$ZIP_URL"
fi

if (( FORCE )) || [[ ! -f "$IMAGE_PATH" ]]; then
  echo "== extracting $ZIP_NAME =="
  rm -f "$IMAGE_PATH"
  unzip -o "$ZIP_PATH" -d "$OUT_DIR" >/dev/null
fi

ln -sfn "$ZIP_NAME" "$CURRENT_ZIP_LINK"
ln -sfn "$IMAGE_NAME" "$CURRENT_IMAGE_LINK"
if [[ -f "$README_PATH" ]]; then
  ln -sfn "ReadMe.md" "$CURRENT_README_LINK"
fi

if (( PRINT_PATH )); then
  printf '%s\n' "$IMAGE_PATH"
else
  echo "zip:    $ZIP_PATH"
  echo "image:  $IMAGE_PATH"
  echo "active: $CURRENT_IMAGE_LINK"
fi
