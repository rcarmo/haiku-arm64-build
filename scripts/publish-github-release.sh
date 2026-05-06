#!/usr/bin/env bash
set -euo pipefail

REPO=${GITHUB_REPOSITORY:-${REPO:-rcarmo/haiku-arm64-build}}
API=${GITHUB_API_URL:-https://api.github.com}
TOKEN=${GITHUB_TOKEN:-${GITHUB_PAT_MACEMU:-}}
HREV_TAG=${HREV_TAG:-}
RUN_ID=${RUN_ID:-${GITHUB_RUN_ID:-}}
TARGET_SHA=${TARGET_SHA:-${GITHUB_SHA:-}}
KEEP_RELEASES=${KEEP_RELEASES:-5}
WORK_DIR=${WORK_DIR:-/workspace/tmp/github-release-artifacts}

if [[ -z "$TOKEN" ]]; then
  echo "missing GITHUB_TOKEN/GITHUB_PAT_MACEMU" >&2
  exit 1
fi
if [[ -z "$HREV_TAG" || -z "$RUN_ID" || -z "$TARGET_SHA" ]]; then
  echo "usage: HREV_TAG=hrevNNNNN RUN_ID=<actions-run-id> TARGET_SHA=<commit> $0" >&2
  exit 1
fi
if ! [[ "$HREV_TAG" =~ ^hrev[0-9]+$ ]]; then
  echo "HREV_TAG must look like hrevNNNNN: $HREV_TAG" >&2
  exit 1
fi

mkdir -p "$WORK_DIR"

api() {
  local method=$1 path=$2 data=${3:-}
  if [[ -n "$data" ]]; then
    curl -fsSL -X "$method" \
      -H "Authorization: Bearer $TOKEN" \
      -H 'Accept: application/vnd.github+json' \
      -H 'Content-Type: application/json' \
      -H 'X-GitHub-Api-Version: 2022-11-28' \
      --data "$data" \
      "$API/repos/$REPO$path"
  else
    curl -fsSL -X "$method" \
      -H "Authorization: Bearer $TOKEN" \
      -H 'Accept: application/vnd.github+json' \
      -H 'X-GitHub-Api-Version: 2022-11-28' \
      "$API/repos/$REPO$path"
  fi
}

api_status() {
  local method=$1 path=$2 out=$3 data=${4:-}
  if [[ -n "$data" ]]; then
    curl -sS -o "$out" -w '%{http_code}' -X "$method" \
      -H "Authorization: Bearer $TOKEN" \
      -H 'Accept: application/vnd.github+json' \
      -H 'Content-Type: application/json' \
      -H 'X-GitHub-Api-Version: 2022-11-28' \
      --data "$data" \
      "$API/repos/$REPO$path"
  else
    curl -sS -o "$out" -w '%{http_code}' -X "$method" \
      -H "Authorization: Bearer $TOKEN" \
      -H 'Accept: application/vnd.github+json' \
      -H 'X-GitHub-Api-Version: 2022-11-28' \
      "$API/repos/$REPO$path"
  fi
}

json_string() {
  jq -Rn --arg v "$1" '$v'
}

ensure_tag() {
  local out="$WORK_DIR/tag.json" code payload
  code=$(api_status GET "/git/ref/tags/$HREV_TAG" "$out") || true
  if [[ "$code" == 200 ]]; then
    local current
    current=$(jq -r '.object.sha' "$out")
    if [[ "$current" != "$TARGET_SHA" ]]; then
      echo "Updating tag $HREV_TAG: $current -> $TARGET_SHA"
      payload=$(jq -cn --arg sha "$TARGET_SHA" '{sha:$sha, force:true}')
      api PATCH "/git/refs/tags/$HREV_TAG" "$payload" >/dev/null
    else
      echo "Tag $HREV_TAG already points to $TARGET_SHA"
    fi
  elif [[ "$code" == 404 ]]; then
    echo "Creating tag $HREV_TAG -> $TARGET_SHA"
    payload=$(jq -cn --arg ref "refs/tags/$HREV_TAG" --arg sha "$TARGET_SHA" '{ref:$ref, sha:$sha}')
    api POST "/git/refs" "$payload" >/dev/null
  else
    echo "failed to inspect tag $HREV_TAG (HTTP $code):" >&2
    cat "$out" >&2
    exit 1
  fi
}

artifact_url_for_name() {
  local name=$1
  jq -r --arg name "$name" '.artifacts[] | select(.name == $name and .expired == false) | .archive_download_url' "$WORK_DIR/run-artifacts.json" | head -1
}

download_run_artifact() {
  local artifact_name=$1 asset_name=$2
  local url
  url=$(artifact_url_for_name "$artifact_name")
  if [[ -z "$url" ]]; then
    echo "missing run artifact: $artifact_name" >&2
    return 1
  fi
  if [[ -s "$WORK_DIR/$asset_name" ]]; then
    echo "Using existing $WORK_DIR/$asset_name"
    return 0
  fi
  echo "Downloading $artifact_name -> $asset_name"
  curl --retry 5 --retry-delay 2 -fsSL -H "Authorization: Bearer $TOKEN" -L "$url" -o "$WORK_DIR/$asset_name"
}

ensure_release() {
  local out="$WORK_DIR/release.json" code payload body
  body=$(cat <<EOF
Automated Haiku ARM64 artifacts for $HREV_TAG.

Source workflow run: https://github.com/$REPO/actions/runs/$RUN_ID
Target commit: $TARGET_SHA

Primary assets:
- haiku-arm64-qemu-virtio-base-$HREV_TAG.zip
- haiku-arm64-utm-ios-virtio-$HREV_TAG.zip

Both image lanes are validated with VirtIO block storage. The log assets include the QEMU smoke logs used for validation.
EOF
)
  code=$(api_status GET "/releases/tags/$HREV_TAG" "$out") || true
  if [[ "$code" == 200 ]]; then
    local id
    id=$(jq -r '.id' "$out")
    echo "Updating existing release $HREV_TAG ($id)"
    payload=$(jq -cn --arg name "Haiku ARM64 $HREV_TAG" --arg body "$body" '{name:$name, body:$body, draft:false, prerelease:false}')
    api PATCH "/releases/$id" "$payload" > "$out"
  elif [[ "$code" == 404 ]]; then
    echo "Creating release $HREV_TAG"
    payload=$(jq -cn --arg tag "$HREV_TAG" --arg target "$TARGET_SHA" --arg name "Haiku ARM64 $HREV_TAG" --arg body "$body" '{tag_name:$tag, target_commitish:$target, name:$name, body:$body, draft:false, prerelease:false}')
    api POST "/releases" "$payload" > "$out"
  else
    echo "failed to inspect release $HREV_TAG (HTTP $code):" >&2
    cat "$out" >&2
    exit 1
  fi
}

delete_existing_asset() {
  local release_json=$1 asset_name=$2
  local asset_id
  asset_id=$(jq -r --arg name "$asset_name" '.assets[]? | select(.name == $name) | .id' "$release_json" | head -1)
  if [[ -n "$asset_id" ]]; then
    echo "Deleting existing release asset $asset_name ($asset_id)"
    api DELETE "/releases/assets/$asset_id" >/dev/null
  fi
}

upload_asset() {
  local release_json=$1 path=$2 name=$3
  local upload_url release_id url
  release_id=$(jq -r '.id' "$release_json")
  # refresh after any deletions
  api GET "/releases/$release_id" > "$release_json"
  delete_existing_asset "$release_json" "$name"
  api GET "/releases/$release_id" > "$release_json"
  upload_url=$(jq -r '.upload_url' "$release_json" | sed 's/{?name,label}//')
  url="$upload_url?name=$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))' "$name")"
  echo "Uploading release asset $name"
  curl -fsSL -X POST \
    -H "Authorization: Bearer $TOKEN" \
    -H 'Accept: application/vnd.github+json' \
    -H 'Content-Type: application/zip' \
    --data-binary "@$path" \
    "$url" >/dev/null
}

cleanup_old_release_generations() {
  echo "Cleaning artifacts/runs older than the latest $KEEP_RELEASES releases"
  api GET "/releases?per_page=100" > "$WORK_DIR/releases.json"
  mapfile -t keep_tags < <(jq -r --argjson keep "$KEEP_RELEASES" 'sort_by(.created_at) | reverse | .[:$keep] | .[].tag_name' "$WORK_DIR/releases.json")
  local cutoff
  # Use the oldest retained release as the cutoff. If there are fewer than
  # KEEP_RELEASES releases, use the oldest available retained release (usually
  # the release just created) so pre-release CI artifacts/runs are still pruned.
  cutoff=$(jq -r --argjson keep "$KEEP_RELEASES" 'sort_by(.created_at) | reverse | (.[($keep - 1)].created_at // .[-1].created_at // empty)' "$WORK_DIR/releases.json")
  printf '%s\n' "Keeping release tags:" "${keep_tags[@]}"

  # Delete releases beyond the retention window. Keep tags intact.
  jq -r --argjson keep "$KEEP_RELEASES" 'sort_by(.created_at) | reverse | .[$keep:][]? | [.id,.tag_name] | @tsv' "$WORK_DIR/releases.json" \
    | while IFS=$'\t' read -r release_id tag; do
        [[ -n "$release_id" ]] || continue
        echo "Deleting old release $tag ($release_id)"
        api DELETE "/releases/$release_id" >/dev/null
      done

  # Delete Actions artifacts older than the retained release window. Release
  # assets are now the durable distribution surface; Actions artifacts are only
  # handoff/staging data.
  api GET "/actions/artifacts?per_page=100" > "$WORK_DIR/actions-artifacts.json"
  jq -r --arg cutoff "$cutoff" '.artifacts[] | select($cutoff == "" or .created_at < $cutoff) | [.id,.name,.created_at] | @tsv' "$WORK_DIR/actions-artifacts.json" \
    | while IFS=$'\t' read -r artifact_id artifact_name created_at; do
        [[ -n "$artifact_id" ]] || continue
        echo "Deleting old Actions artifact $artifact_name ($artifact_id, $created_at)"
        api DELETE "/actions/artifacts/$artifact_id" >/dev/null
      done

  # Delete completed workflow runs older than the oldest retained release.
  if [[ -n "$cutoff" ]]; then
    api GET "/actions/runs?per_page=100&status=completed" > "$WORK_DIR/actions-runs.json"
    jq -r --arg cutoff "$cutoff" '.workflow_runs[] | select(.created_at < $cutoff) | [.id,.display_title,.created_at] | @tsv' "$WORK_DIR/actions-runs.json" \
      | while IFS=$'\t' read -r run_id title created_at; do
          [[ -n "$run_id" ]] || continue
          echo "Deleting old workflow run $run_id ($created_at $title)"
          api DELETE "/actions/runs/$run_id" >/dev/null
        done
  fi
}

ensure_tag
api GET "/actions/runs/$RUN_ID/artifacts?per_page=100" > "$WORK_DIR/run-artifacts.json"

declare -A assets=(
  ["haiku-arm64-qemu-virtio-base-$HREV_TAG"]="haiku-arm64-qemu-virtio-base-$HREV_TAG.zip"
  ["haiku-arm64-utm-ios-virtio-$HREV_TAG"]="haiku-arm64-utm-ios-virtio-$HREV_TAG.zip"
  ["haiku-arm64-qemu-virtio-base-logs-$HREV_TAG"]="haiku-arm64-qemu-virtio-base-logs-$HREV_TAG.zip"
  ["haiku-arm64-utm-ios-virtio-logs-$HREV_TAG"]="haiku-arm64-utm-ios-virtio-logs-$HREV_TAG.zip"
)

for artifact_name in "${!assets[@]}"; do
  download_run_artifact "$artifact_name" "${assets[$artifact_name]}"
done

ensure_release
for artifact_name in "${!assets[@]}"; do
  upload_asset "$WORK_DIR/release.json" "$WORK_DIR/${assets[$artifact_name]}" "${assets[$artifact_name]}"
done

api GET "/releases/tags/$HREV_TAG" > "$WORK_DIR/release.json"
echo "Release ready: $(jq -r '.html_url' "$WORK_DIR/release.json")"

cleanup_old_release_generations
