#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd)
BUILD_DIR=${BUILD_DIR:-$REPO_DIR/haiku/generated.arm64}
BFS_FUSE=${BFS_FUSE:-/workspace/tmp/bfs_fuse}
QEMU_BIN=${QEMU_BIN:-qemu-system-aarch64}
QEMU_EFI=${QEMU_EFI:-/usr/share/qemu-efi-aarch64/QEMU_EFI.fd}
OUTPUT_DIR=${OUTPUT_DIR:-/workspace/tmp/haiku-boot-harness}
TIMEOUT_SECS=${TIMEOUT_SECS:-300}
MEMORY_MB=${MEMORY_MB:-2048}
MODE=${MODE:-validate}
KEEP_COPY=${KEEP_COPY:-0}
IMAGE=${IMAGE:-}
TMUX_SESSION=${TMUX_SESSION:-}
STATE_FILE=${STATE_FILE:-}
MONITOR_SOCKET=${MONITOR_SOCKET:-}
SCREENSHOT_OUT=${SCREENSHOT_OUT:-}
WORK_IMAGE=${WORK_IMAGE:-}
LOG_FILE=${LOG_FILE:-}
SERIAL_LOG=${SERIAL_LOG:-}

DEFAULT_RUN_IMAGE=/workspace/tmp/haiku-build/validated/haiku-arm64-icu74-desktop.boot.img
DEFAULT_VALIDATE_IMAGE=/workspace/tmp/haiku-build/validated/haiku-arm64-icu74-desktop.boot.img
FILE_MARKERS=(
  /boot/home/config/settings/marker-app_server-launch
  /boot/home/config/settings/marker-tracker-launch
  /boot/home/config/settings/marker-deskbar-launch
)
MOUNT_POINT=/tmp/haiku-bfs-mount
POLL_SECS=5

usage() {
  cat <<'EOF'
Usage:
  qemu-desktop-harness.sh [run|capture|validate|screenshot|stop] [options]

Modes:
  run         Start the validated desktop image under detached tmux.
  capture     Start under detached tmux, wait for desktop markers, save a screenshot.
  validate    Boot headlessly and verify desktop launch markers.
  screenshot  Save a framebuffer screenshot from a running tmux/QEMU session.
  stop        Stop a detached tmux/QEMU session and clean related sockets.

Options:
  --image PATH            Image to boot.
  --timeout SECONDS       Overall wait timeout (default: 300).
  --memory MB             Guest RAM in MiB (default: 2048).
  --output-dir PATH       Output directory for working copies/logs/state.
  --keep-copy             Keep the writable image copy after validate.
  --tmux-session NAME     tmux session name for run/capture mode.
  --state-file PATH       Harness state file (run/capture writes one; screenshot reads one).
  --monitor-socket PATH   QEMU monitor socket (alternative to --state-file).
  --screenshot-out PATH   Screenshot output path (.ppm by default).
  --help                  Show this help.

Defaults:
  run/capture image: /workspace/tmp/haiku-build/validated/haiku-arm64-icu74-desktop.boot.img
  validate image:    /workspace/tmp/haiku-build/validated/haiku-arm64-icu74-desktop.boot.img
EOF
}

die() {
  echo "error: $*" >&2
  exit 1
}

require_file() {
  local path=$1
  [[ -f "$path" ]] || die "missing file: $path"
}

require_exe() {
  local path=$1
  command -v "$path" >/dev/null 2>&1 || die "missing executable in PATH: $path"
}

cleanup() {
  set +e
  if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
    fusermount -u "$MOUNT_POINT" >/dev/null 2>&1 || true
  fi
  if [[ -n "${BFS_PID:-}" ]]; then
    wait "$BFS_PID" >/dev/null 2>&1 || true
  fi
  if [[ "$MODE" == "validate" && "${KEEP_COPY}" != "1" && -n "${WORK_IMAGE:-}" && -f "${WORK_IMAGE}" ]]; then
    rm -f "$WORK_IMAGE"
  fi
  if [[ -n "${PART_IMAGE:-}" && -f "${PART_IMAGE}" ]]; then
    rm -f "$PART_IMAGE"
  fi
}
trap cleanup EXIT

while [[ $# -gt 0 ]]; do
  case "$1" in
    run|capture|validate|screenshot|stop)
      MODE=$1
      shift
      ;;
    --image)
      IMAGE=$2
      shift 2
      ;;
    --timeout)
      TIMEOUT_SECS=$2
      shift 2
      ;;
    --memory)
      MEMORY_MB=$2
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR=$2
      shift 2
      ;;
    --keep-copy)
      KEEP_COPY=1
      shift
      ;;
    --tmux-session)
      TMUX_SESSION=$2
      shift 2
      ;;
    --state-file)
      STATE_FILE=$2
      shift 2
      ;;
    --monitor-socket)
      MONITOR_SOCKET=$2
      shift 2
      ;;
    --screenshot-out)
      SCREENSHOT_OUT=$2
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

mkdir -p "$OUTPUT_DIR"

load_state_if_needed() {
  if [[ -n "$STATE_FILE" ]]; then
    require_file "$STATE_FILE"
    # shellcheck disable=SC1090
    source "$STATE_FILE"
  fi
}

if [[ "$MODE" == "screenshot" ]]; then
  require_exe python3
  load_state_if_needed
  [[ -n "$MONITOR_SOCKET" ]] || die "screenshot mode needs --state-file or --monitor-socket"
  [[ -S "$MONITOR_SOCKET" ]] || die "monitor socket not found: $MONITOR_SOCKET"
  if [[ -z "$SCREENSHOT_OUT" ]]; then
    SCREENSHOT_OUT="$OUTPUT_DIR/haiku-screenshot-$(date +%Y%m%d-%H%M%S).ppm"
  fi

  python3 - "$MONITOR_SOCKET" "$SCREENSHOT_OUT" <<'PY'
import socket, sys, time
sock_path, out_path = sys.argv[1], sys.argv[2]
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.connect(sock_path)
s.sendall(f"screendump {out_path}\n".encode())
time.sleep(1.0)
s.close()
PY

  require_file "$SCREENSHOT_OUT"
  echo "screenshot: $SCREENSHOT_OUT"
  exit 0
fi

if [[ "$MODE" == "stop" ]]; then
  load_state_if_needed
  if [[ -n "$TMUX_SESSION" ]]; then
    tmux has-session -t "$TMUX_SESSION" 2>/dev/null && tmux kill-session -t "$TMUX_SESSION" || true
  fi
  if [[ -n "$WORK_IMAGE" ]]; then
    pkill -f "qemu-system-aarch64.*${WORK_IMAGE}" 2>/dev/null || true
  fi
  if [[ -n "$MONITOR_SOCKET" ]]; then
    rm -f "$MONITOR_SOCKET"
  fi
  echo "stopped detached session"
  exit 0
fi

if [[ -z "$IMAGE" ]]; then
  case "$MODE" in
    run|capture) IMAGE=$DEFAULT_RUN_IMAGE ;;
    validate) IMAGE=$DEFAULT_VALIDATE_IMAGE ;;
  esac
fi

require_file "$IMAGE"
require_file "$QEMU_EFI"
require_exe "$QEMU_BIN"
require_exe tmux

STAMP=$(date +%Y%m%d-%H%M%S)
BASENAME=$(basename "$IMAGE" .img)
PREFIX="$OUTPUT_DIR/${BASENAME}.${STAMP}"
WORK_IMAGE="$PREFIX.work.img"
LOG_FILE="$PREFIX.${MODE}.log"
SERIAL_LOG="$PREFIX.serial.log"
MONITOR_SOCKET=${MONITOR_SOCKET:-$PREFIX.monitor.sock}
STATE_FILE=${STATE_FILE:-$PREFIX.state}
TMUX_SESSION=${TMUX_SESSION:-haiku-desktop-$STAMP}
SCREENSHOT_OUT=${SCREENSHOT_OUT:-$PREFIX.ppm}

cp --reflink=auto "$IMAGE" "$WORK_IMAGE"

echo "mode:         $MODE"
echo "image:        $IMAGE"
echo "work image:   $WORK_IMAGE"
echo "log:          $LOG_FILE"
echo "serial log:   $SERIAL_LOG"
echo "memory:       ${MEMORY_MB} MiB"
echo "timeout:      ${TIMEOUT_SECS}s"
[[ "$MODE" == "run" || "$MODE" == "capture" ]] && echo "tmux session: $TMUX_SESSION"

QEMU_COMMON=(
  -bios "$QEMU_EFI"
  -M virt
  -cpu max
  -m "$MEMORY_MB"
  -device qemu-xhci
  -device usb-storage,drive=x0
  -drive "file=$WORK_IMAGE,if=none,format=raw,id=x0"
  -device ramfb
  -no-reboot
)

mount_bfs_partition() {
  require_file "$BFS_FUSE"
  [[ -d "$BUILD_DIR" ]] || die "missing build dir: $BUILD_DIR"

  PART_IMAGE="$PREFIX.part.img"
  rm -f "$PART_IMAGE"
  dd if="$WORK_IMAGE" of="$PART_IMAGE" bs=512 skip=65540 count=614400 status=none

  sudo umount -l "$MOUNT_POINT" >/dev/null 2>&1 || true
  sudo rm -rf "$MOUNT_POINT"
  mkdir -p "$MOUNT_POINT"

  (
    cd "$BUILD_DIR"
    export LD_LIBRARY_PATH="$BUILD_DIR/objects/linux/lib"
    "$BFS_FUSE" "$PART_IMAGE" "$MOUNT_POINT" >"$PREFIX.bfs-fuse.log" 2>&1
  ) &
  BFS_PID=$!
  sleep 2
}

unmount_bfs_partition() {
  if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
    fusermount -u "$MOUNT_POINT" >/dev/null 2>&1 || true
  fi
  if [[ -n "${BFS_PID:-}" ]]; then
    wait "$BFS_PID" >/dev/null 2>&1 || true
    BFS_PID=
  fi
}

sync_partition_back_to_work_image() {
  [[ -n "${PART_IMAGE:-}" && -f "$PART_IMAGE" ]] || die "missing partition image to sync back"
  dd if="$PART_IMAGE" of="$WORK_IMAGE" bs=512 seek=65540 conv=notrunc status=none
}

inject_marker_user_launch() {
  local user_launch_file="$PREFIX.user_launch"
  cat >"$user_launch_file" <<'EOF'
service x-vnd.Haiku-app_server {
	env /system/boot/SetupEnvironment
	launch /system/servers/app_server
}

target desktop {
	env /system/boot/SetupEnvironment

	service x-vnd.Be-TRAK {
		launch /system/Tracker
		legacy
		on initial_volumes_mounted
	}

	service x-vnd.Be-TSKB {
		launch /bin/sh -c 'echo deskbar >/boot/home/config/settings/marker-deskbar-launch; sync; exec /system/Deskbar'
		on initial_volumes_mounted
	}

	job open-home-window {
		launch /system/Tracker /boot/home
		requires x-vnd.Be-TRAK
		on initial_volumes_mounted
	}

	job harness-marker-app_server {
		launch /bin/sh -c 'echo app_server >/boot/home/config/settings/marker-app_server-launch; sync'
		requires x-vnd.Haiku-app_server
	}

	job harness-marker-tracker {
		launch /bin/sh -c 'echo tracker >/boot/home/config/settings/marker-tracker-launch; sync'
		requires x-vnd.Be-TRAK
	}
}

run {
	desktop
}
EOF

  mount_bfs_partition
  mkdir -p "$MOUNT_POINT/myfs/system/settings/user_launch" "$MOUNT_POINT/myfs/home/config/settings"
  cp "$user_launch_file" "$MOUNT_POINT/myfs/system/settings/user_launch/user"
  for marker in "${FILE_MARKERS[@]}"; do
    rm -f "$MOUNT_POINT/myfs${marker}"
  done
  sync
  unmount_bfs_partition
  sync_partition_back_to_work_image
}

write_state_file() {
  cat >"$STATE_FILE" <<EOF
TMUX_SESSION=$TMUX_SESSION
WORK_IMAGE=$WORK_IMAGE
LOG_FILE=$LOG_FILE
SERIAL_LOG=$SERIAL_LOG
MONITOR_SOCKET=$MONITOR_SOCKET
SCREENSHOT_OUT=$SCREENSHOT_OUT
IMAGE=$IMAGE
EOF
}

run_tmux() {
  rm -f "$MONITOR_SOCKET"

  local cmd=(
    "$QEMU_BIN"
    "${QEMU_COMMON[@]}"
    -device usb-kbd
    -device usb-tablet
    -display none
    -serial "file:$SERIAL_LOG"
    -monitor "unix:$MONITOR_SOCKET,server,nowait"
  )

  local cmd_str log_q
  printf -v cmd_str '%q ' "${cmd[@]}"
  printf -v log_q '%q' "$LOG_FILE"

  tmux has-session -t "$TMUX_SESSION" 2>/dev/null && die "tmux session already exists: $TMUX_SESSION"
  tmux new-session -d -s "$TMUX_SESSION" "exec ${cmd_str}>${log_q} 2>&1"

  write_state_file

  echo
  echo "started detached tmux session"
  echo "session:       $TMUX_SESSION"
  echo "state file:    $STATE_FILE"
  echo "monitor:       $MONITOR_SOCKET"
  echo "qemu log:      $LOG_FILE"
  echo "serial log:    $SERIAL_LOG"
}

markers_present() {
  mount_bfs_partition
  local marker missing=0
  for marker in "${FILE_MARKERS[@]}"; do
    if [[ ! -f "$MOUNT_POINT/myfs${marker}" ]]; then
      missing=1
    fi
  done
  unmount_bfs_partition
  [[ $missing -eq 0 ]]
}

crash_detected() {
  [[ -f "$SERIAL_LOG" ]] && strings "$SERIAL_LOG" | rg -q 'debug_server: Thread|Segment violation|consoled: error'
}

desktop_ready() {
  if markers_present; then
    return 0
  fi

  [[ -f "$SERIAL_LOG" ]] && strings "$SERIAL_LOG" | rg -q 'Running first login script /boot/system/boot/first-login/default_deskbar_items.sh|framebuffer: acc: framebuffer\.accelerant'
}

take_screenshot_now() {
  python3 - "$MONITOR_SOCKET" "$SCREENSHOT_OUT" <<'PY'
import socket, sys, time
sock_path, out_path = sys.argv[1], sys.argv[2]
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.connect(sock_path)
s.sendall(f"screendump {out_path}\n".encode())
time.sleep(1.0)
s.close()
PY
  require_file "$SCREENSHOT_OUT"
}

wait_for_markers_and_capture() {
  local deadline=$((SECONDS + TIMEOUT_SECS))

  while (( SECONDS < deadline )); do
    if crash_detected; then
      die "crash signature detected; inspect $SERIAL_LOG"
    fi

    if [[ -S "$MONITOR_SOCKET" ]] && desktop_ready; then
      take_screenshot_now
      echo
      echo "desktop readiness detected"
      echo "screenshot:    $SCREENSHOT_OUT"
      return 0
    fi

    sleep "$POLL_SECS"
  done

  die "timed out waiting for desktop readiness; inspect $LOG_FILE and $SERIAL_LOG"
}

validate_headless() {
  inject_marker_user_launch
  timeout "$TIMEOUT_SECS" "$QEMU_BIN" \
    "${QEMU_COMMON[@]}" \
    -nographic >"$LOG_FILE" 2>&1 || true

  local missing=0 marker
  mount_bfs_partition
  for marker in "${FILE_MARKERS[@]}"; do
    if [[ -f "$MOUNT_POINT/myfs${marker}" ]]; then
      echo "marker: OK  $marker"
    else
      echo "marker: MISS $marker"
      missing=1
    fi
  done
  unmount_bfs_partition

  echo
  echo "key log lines:"
  strings "$LOG_FILE" | rg 'Mounted boot partition|debug_server: Thread|Segment violation|consoled: error|runtime_loader:|nothing provides|Volume::InitialVerify|LDENVDBG' | head -n 120 || true

  if crash_detected; then
    die "desktop validation failed: crash signature detected; inspect $LOG_FILE"
  fi
  if [[ $missing -ne 0 ]]; then
    die "desktop validation failed: missing harness marker(s); inspect $LOG_FILE"
  fi

  echo
  echo "desktop validation passed"
}

case "$MODE" in
  run)
    run_tmux
    ;;
  capture)
    inject_marker_user_launch
    run_tmux
    wait_for_markers_and_capture
    ;;
  validate)
    validate_headless
    ;;
  *)
    die "unsupported mode: $MODE"
    ;;
esac
