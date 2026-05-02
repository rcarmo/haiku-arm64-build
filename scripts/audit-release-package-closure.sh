#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd)
HAIKU_DIR=${HAIKU_DIR:-$REPO_DIR/haiku}
BUILD_DIR=${BUILD_DIR:-$HAIKU_DIR/generated.arm64}
PACKAGE_TOOL=${PACKAGE_TOOL:-$BUILD_DIR/objects/linux/arm64/release/tools/package/package}
BFS_FUSE=${BFS_FUSE:-/workspace/tmp/bfs_fuse}
DIRECT_HAIKU_PACKAGE_INFO=${DIRECT_HAIKU_PACKAGE_INFO:-$BUILD_DIR/objects/haiku/arm64/packaging/packages_build/regular/hpkg_-haiku.hpkg/haiku-package-info}
BASE_IMAGE=${BASE_IMAGE:-/workspace/tmp/haiku-nightly-arm64/haiku-master-arm64-current-mmc.image}
VALIDATION_DIR=${VALIDATION_DIR:-/workspace/tmp/haiku-build/validated}
LOCAL_REPO_PACKAGES=${LOCAL_REPO_PACKAGES:-$BUILD_DIR/objects/haiku/arm64/packaging/repositories/HaikuPortsCross-build/packages}
OUTPUT_DIR=${OUTPUT_DIR:-/workspace/tmp/haiku-release-audit}

usage() {
  cat <<'EOF'
Audit the package dependency closure needed to stop pruning the regular direct
haiku.hpkg and produce a fuller standard ARM64 image.

The audit compares the regular haiku package requirements against:
  - packages inside the managed stock nightly base image
  - local validation overlay packages
  - locally built HaikuPortsCross packages

It writes summary.md and summary.tsv under /workspace/tmp/haiku-release-audit by default.
EOF
}

if [[ ${1:-} == --help || ${1:-} == -h ]]; then
  usage
  exit 0
fi

require_file() {
  local path=$1
  [[ -f "$path" ]] || { echo "missing file: $path" >&2; exit 1; }
}

require_file "$PACKAGE_TOOL"
require_file "$DIRECT_HAIKU_PACKAGE_INFO"
require_file "$BASE_IMAGE"
require_file "$BFS_FUSE"
mkdir -p "$OUTPUT_DIR"

TMP=$(mktemp -d /workspace/tmp/haiku-release-audit.XXXXXX)
MOUNT_POINT="$TMP/mnt"
mkdir -p "$MOUNT_POINT"
BFS_PID=
cleanup() {
  set +e
  if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
    fusermount -u "$MOUNT_POINT" >/dev/null 2>&1 || true
  fi
  if [[ -n "$BFS_PID" ]]; then
    wait "$BFS_PID" >/dev/null 2>&1 || true
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT

read -r SYSTEM_START SYSTEM_SIZE < <(
  sfdisk -d "$BASE_IMAGE" | awk -F'[ ,=]+' '/ : start=/{n++; if(n==2){for(i=1;i<=NF;i++){if($i=="start") s=$(i+1); else if($i=="size") z=$(i+1)} print s" "z; exit}}'
)
[[ -n "${SYSTEM_START:-}" && -n "${SYSTEM_SIZE:-}" ]] || { echo "failed to find system partition geometry" >&2; exit 1; }

dd if="$BASE_IMAGE" of="$TMP/system.part.img" bs=512 skip="$SYSTEM_START" count="$SYSTEM_SIZE" status=none
(
  cd "$BUILD_DIR"
  export LD_LIBRARY_PATH="$BUILD_DIR/objects/linux/lib"
  "$BFS_FUSE" "$TMP/system.part.img" "$MOUNT_POINT" >"$TMP/bfs-fuse.log" 2>&1
) &
BFS_PID=$!
sleep 2

collect_requirements() {
  awk '
    /^requires[[:space:]]*\{/ { inreq=1; next }
    inreq && /^}/ { inreq=0 }
    inreq {
      gsub(/^[ \t]+|[ \t]+$/, "")
      if (length($0) && $0 !~ /^#/) print $0
    }
  ' "$DIRECT_HAIKU_PACKAGE_INFO" | sort -u
}

normalize_requirement() {
  local req=$1
  req=${req%% *}
  printf '%s\n' "$req"
}

provider_key_from_line() {
  local line=$1 key
  line=${line#provides: }
  line=${line#provides[[:space:]]}
  key=${line%% =*}
  key=${key%% *}
  printf '%s\n' "$key"
}

PROVIDERS_TSV="$TMP/providers.tsv"
: > "$PROVIDERS_TSV"
add_package_providers() {
  local hpkg=$1 source=$2 base line key
  base=$(basename "$hpkg")
  "$PACKAGE_TOOL" list "$hpkg" 2>/dev/null \
    | while IFS= read -r line; do
        line=${line#[$'\t ']}
        if [[ "$line" == provides:* ]]; then
          key=$(provider_key_from_line "$line")
          [[ -n "$key" ]] && printf '%s\t%s\t%s\n' "$key" "$base" "$source"
        fi
      done >> "$PROVIDERS_TSV"
}

# Stock nightly packages.
while IFS= read -r -d '' hpkg; do
  add_package_providers "$hpkg" stock-nightly
 done < <(find "$MOUNT_POINT/myfs/system/packages" -maxdepth 1 -type f -name '*.hpkg' -print0 | sort -z)

# Validation/generated overlays.
if [[ -d "$VALIDATION_DIR" ]]; then
  while IFS= read -r -d '' hpkg; do
    add_package_providers "$hpkg" validation-overlay
  done < <(find "$VALIDATION_DIR" -maxdepth 1 -type f -name '*.hpkg' -print0 | sort -z)
fi

# Local HaikuPortsCross packages.
if [[ -d "$LOCAL_REPO_PACKAGES" ]]; then
  while IFS= read -r -d '' hpkg; do
    add_package_providers "$hpkg" local-haikuports-cross
  done < <(find "$LOCAL_REPO_PACKAGES" -maxdepth 1 -type f -name '*.hpkg' -print0 | sort -z)
fi

SUMMARY_TSV="$OUTPUT_DIR/summary.tsv"
SUMMARY_MD="$OUTPUT_DIR/summary.md"
: > "$SUMMARY_TSV"
{
  echo "# ARM64 standard image package-closure audit"
  echo
  echo "- Direct package info: \`$DIRECT_HAIKU_PACKAGE_INFO\`"
  echo "- Base image: \`$BASE_IMAGE\`"
  echo "- Validation overlays: \`$VALIDATION_DIR\`"
  echo "- Local package repo: \`$LOCAL_REPO_PACKAGES\`"
  echo
  echo "| Requirement | Status | Provider | Source |"
  echo "|---|---|---|---|"
} > "$SUMMARY_MD"

missing=0
while IFS= read -r req; do
  key=$(normalize_requirement "$req")
  provider=$(awk -F '\t' -v key="$key" '$1 == key { print $2 "\t" $3; exit }' "$PROVIDERS_TSV")
  if [[ -n "$provider" ]]; then
    package=${provider%%$'\t'*}
    source=${provider#*$'\t'}
    status=available
  else
    package=""
    source=""
    status=missing
    missing=$((missing + 1))
  fi
  printf '%s\t%s\t%s\t%s\n' "$req" "$status" "$package" "$source" >> "$SUMMARY_TSV"
  printf '| `%s` | `%s` | `%s` | `%s` |\n' "$req" "$status" "$package" "$source" >> "$SUMMARY_MD"
done < <(collect_requirements)

cat <<EOF >> "$SUMMARY_MD"

## Result

Missing requirements: $missing
EOF

if (( missing > 0 )); then
  cat <<'EOF' >> "$SUMMARY_MD"

The validation image remains intentionally pruned until these missing providers
are built or imported for ARM64. Once all rows are available, the full-image lane
can stop removing regular-package requirements and add the provider packages to
the system package set.
EOF
fi

cat "$SUMMARY_MD"
exit 0
