# Haiku ARM64 Build — Reproducible Makefile
# Host: Orange Pi 6 Plus (aarch64 Debian Trixie)

HAIKU_DIR     := $(CURDIR)/haiku
BUILD_DIR     := $(HAIKU_DIR)/generated.arm64
BUILDTOOLS_DIR := $(CURDIR)/buildtools
HAIKU_REMOTE  ?= https://review.haiku-os.org/haiku
HAIKU_BRANCH  ?=
BUILDTOOLS_REMOTE ?= https://review.haiku-os.org/buildtools
BUILDTOOLS_BRANCH ?=
NPROC         := $(shell nproc)
IMAGE         := $(BUILD_DIR)/haiku-mmc.image
HREV          ?=
NIGHTLY_DIR   := /workspace/tmp/haiku-nightly-arm64
NIGHTLY_BASE_IMAGE := $(NIGHTLY_DIR)/haiku-master-arm64-current-mmc.image
NIGHTLY_SYNC_ARGS := $(if $(HREV),--hrev $(HREV),)
DESKTOP_BUILD_IMAGE := /workspace/tmp/haiku-build/validated/haiku-arm64-icu74-desktop.boot.img
DESKTOP_RUN_IMAGE := $(DESKTOP_BUILD_IMAGE)
DESKTOP_VALIDATE_IMAGE := $(DESKTOP_BUILD_IMAGE)
VALIDATION_RAW_IMAGE := $(DESKTOP_BUILD_IMAGE)
VALIDATION_QCOW_IMAGE := /workspace/tmp/haiku-build/validated/haiku-arm64-icu74-desktop.qcow2
FULL_OUTPUT_DIR := /workspace/tmp/haiku-build/full
FULL_BUILD_IMAGE := $(FULL_OUTPUT_DIR)/haiku-arm64-icu74-full.boot.img
FULL_QCOW_IMAGE := $(FULL_OUTPUT_DIR)/haiku-arm64-icu74-full.qcow2
FULL_VALIDATE_TIMEOUT_SECS := 900
UTM_IOS_DIR := /workspace/tmp/haiku-build/utm-ios
UTM_IOS_BOOTSTRAP_QCOW := $(UTM_IOS_DIR)/haiku-arm64-minimum-utm-ios.qcow2
UTM_IOS_BOOTSTRAP_LOG := $(UTM_IOS_DIR)/qemu-minimum-qcow-virtio-smoke.log
DESKTOP_HARNESS_DIR := /workspace/tmp/haiku-boot-harness
DESKTOP_TMUX_SESSION := haiku-desktop
DESKTOP_STATE_FILE := $(DESKTOP_HARNESS_DIR)/$(DESKTOP_TMUX_SESSION).state
DESKTOP_MONITOR_SOCKET := $(DESKTOP_HARNESS_DIR)/$(DESKTOP_TMUX_SESSION).monitor.sock
DESKTOP_SCREENSHOT := $(DESKTOP_HARNESS_DIR)/$(DESKTOP_TMUX_SESSION).ppm
DESKTOP_VALIDATE_TIMEOUT_SECS := 900
BFS_FUSE := /workspace/tmp/bfs_fuse
BFS_FUSE_BUILT := $(BUILD_DIR)/objects/linux/arm64/release/tools/bfs_shell/bfs_fuse
ORANGEPI6PLUS_EFI_SNAPSHOT_DIR := /workspace/tmp/orangepi6plus-efi-snapshot/latest
ORANGEPI6PLUS_EFI_ESP_DEV := /dev/nvme0n1p1

.PHONY: all deps clone jam toolchain direct-package image clean update test help bfs-fuse \
	nightly-arm64-sync stock-validate desktop-refresh desktop-probe-overlays \
	desktop-image desktop-run desktop-stop desktop-status desktop-logs desktop-attach \
	desktop-capture desktop-screenshot desktop-validate \
	validation-image validation-qcow validation-artifacts \
	full-standard-image full-standard-validate full-standard-qcow full-standard-artifacts \
	utm-ios-bootstrap utm-ios-smoke release-audit \
	full-sync full-stock-validate full-image full-refresh full-probe-overlays \
	full-run full-stop full-status full-logs full-attach full-capture \
	full-screenshot full-validate full-check orangepi6plus-efi-snapshot

help:
	@echo "Haiku ARM64 Build System"
	@echo ""
	@echo "Targets:"
	@echo "  deps       - Install build dependencies (requires sudo)"
	@echo "  clone      - Clone/update haiku + buildtools repos"
	@echo "  toolchain  - Build cross-compiler toolchain"
	@echo "  bfs-fuse   - Build/link the host BFS FUSE helper used by validation scripts"
	@echo "  direct-package - Build the regular direct haiku.hpkg used by validation images"
	@echo "  image      - Build MMC image (default: @minimum-mmc)"
	@echo "  raw        - Build raw images (esp.image + haiku-minimum.image)"
	@echo "  test       - Quick QEMU smoke test (30s)"
	@echo "  test-long  - Extended QEMU test (120s)"
	@echo "  nightly-arm64-sync   - Download latest arm64 nightly MMC image + update stable symlink"
	@echo "  stock-validate       - Validate the current stock arm64 nightly image"
	@echo "  desktop-image        - Assemble reproducible validated ICU74 desktop image"
	@echo "  desktop-refresh      - Sync nightly base, rebuild direct image, validate it"
	@echo "  desktop-probe-overlays - Validate the stock/direct overlay matrix on current nightly"
	@echo "  desktop-run        - Start validated desktop image under detached tmux"
	@echo "  desktop-status     - Show session, state, and latest serial log lines"
	@echo "  desktop-logs       - Tail the detached session serial log"
	@echo "  desktop-attach     - Attach to the detached tmux session"
	@echo "  desktop-screenshot - Save a framebuffer screenshot from the detached session"
	@echo "  desktop-capture    - Blocking convenience target: run + wait + screenshot"
	@echo "  desktop-stop       - Stop the detached desktop tmux session"
	@echo "  desktop-validate   - Headless marker-based desktop validation harness"
	@echo "  validation-image    - Build the core validation raw image"
	@echo "  validation-qcow     - Build the core validation image and convert it to qcow2"
	@echo "  validation-artifacts - Sync, build, validate, and emit raw+qcow2 artifacts"
	@echo "  full-standard-artifacts - Build full-image prototype raw+qcow2 artifacts"
	@echo "  utm-ios-bootstrap  - Build UTM/iOS-friendly minimum qcow2 image"
	@echo "  utm-ios-smoke      - Smoke-test the UTM/iOS qcow2 via QEMU VirtIO block"
	@echo "  release-audit       - Audit missing providers for a full standard image"
	@echo ""
	@echo "  full-sync           - Alias for nightly-arm64-sync"
	@echo "  full-stock-validate - Alias for stock-validate"
	@echo "  full-image          - Alias for desktop-image"
	@echo "  full-refresh        - Alias for desktop-refresh"
	@echo "  full-probe-overlays - Alias for desktop-probe-overlays"
	@echo "  full-run            - Alias for desktop-run"
	@echo "  full-status         - Alias for desktop-status"
	@echo "  full-logs           - Alias for desktop-logs"
	@echo "  full-attach         - Alias for desktop-attach"
	@echo "  full-screenshot     - Alias for desktop-screenshot"
	@echo "  full-capture        - Alias for desktop-capture"
	@echo "  full-stop           - Alias for desktop-stop"
	@echo "  full-validate       - Alias for desktop-validate"
	@echo "  full-check          - Run the authoritative full-package QEMU regression lane"
	@echo "  orangepi6plus-efi-snapshot - Snapshot the current host EFI/GRUB boot surface"
	@echo "  update     - Git pull both repos"
	@echo "  clean      - Remove generated.arm64"
	@echo "  distclean  - Remove everything (repos + generated)"
	@echo ""
	@echo "Image location: $(IMAGE)"

deps:
	sudo apt-get update -qq
	sudo apt-get install -y \
		git nasm bc autoconf automake texinfo flex bison gawk \
		build-essential unzip wget zip zlib1g-dev libzstd-dev \
		xorriso mtools u-boot-tools python3 attr libfuse-dev fuse \
		qemu-system-arm qemu-efi-aarch64 qemu-system-data qemu-utils ipxe-qemu
	@echo "✅ Dependencies installed"

clone:
	@if [ ! -d $(HAIKU_DIR)/.git ]; then \
		echo "Cloning haiku from $(HAIKU_REMOTE)..."; \
		git clone $(if $(HAIKU_BRANCH),--branch $(HAIKU_BRANCH),) $(HAIKU_REMOTE) $(HAIKU_DIR); \
	fi
	@if [ ! -d $(BUILDTOOLS_DIR)/.git ]; then \
		echo "Cloning buildtools from $(BUILDTOOLS_REMOTE)..."; \
		git clone $(if $(BUILDTOOLS_BRANCH),--branch $(BUILDTOOLS_BRANCH),) $(BUILDTOOLS_REMOTE) $(BUILDTOOLS_DIR); \
	fi
	@echo "✅ Repos ready"
	@echo "  haiku:      $$(cd $(HAIKU_DIR) && git log -1 --oneline)"
	@echo "  buildtools: $$(cd $(BUILDTOOLS_DIR) && git log -1 --oneline)"

jam: clone
	@if ! command -v jam >/dev/null 2>&1; then \
		echo "Building jam..."; \
		cd $(BUILDTOOLS_DIR)/jam && make -j$(NPROC) && sudo ./jam0 install; \
	else \
		echo "✅ jam already exists"; \
	fi

update:
	cd $(HAIKU_DIR) && git pull --ff-only
	cd $(BUILDTOOLS_DIR) && git pull --ff-only
	@echo "✅ Updated"

toolchain: jam
	@if [ ! -f $(BUILD_DIR)/cross-tools-arm64/bin/aarch64-unknown-haiku-gcc ]; then \
		echo "Building ARM64 cross-toolchain..."; \
		mkdir -p $(BUILD_DIR); \
		cd $(BUILD_DIR) && ../configure -j$(NPROC) \
			--cross-tools-source $(BUILDTOOLS_DIR) \
			--build-cross-tools arm64; \
		echo "✅ Toolchain built"; \
	else \
		echo "✅ Toolchain already exists"; \
	fi

bfs-fuse: toolchain
	cd $(BUILD_DIR) && jam -j$(NPROC) -q '<build>bfs_fuse'
	@mkdir -p "$$(dirname "$(BFS_FUSE)")"
	ln -sf "$(BFS_FUSE_BUILT)" "$(BFS_FUSE)"
	@test -x "$(BFS_FUSE)"
	@echo "✅ BFS FUSE helper linked: $(BFS_FUSE) -> $(BFS_FUSE_BUILT)"

direct-package: toolchain
	cd $(BUILD_DIR) && jam -j$(NPROC) -q haiku.hpkg
	@test -f "$(BUILD_DIR)/objects/haiku/arm64/packaging/packages/haiku.hpkg"
	@echo "✅ Direct haiku package built: $(BUILD_DIR)/objects/haiku/arm64/packaging/packages/haiku.hpkg"

image: toolchain
	cd $(BUILD_DIR) && jam -j$(NPROC) -q @minimum-mmc
	@echo "✅ Image built: $(IMAGE)"
	@ls -lh $(IMAGE)

raw: toolchain
	cd $(BUILD_DIR) && jam -j$(NPROC) -q @minimum-raw esp.image haiku-minimum.image
	@echo "✅ Raw images built"
	@ls -lh $(BUILD_DIR)/esp.image $(BUILD_DIR)/haiku-minimum.image

test: image
	@echo "QEMU smoke test (30s)..."
	@timeout 30 qemu-system-aarch64 \
		-bios /usr/share/qemu-efi-aarch64/QEMU_EFI.fd \
		-M virt -cpu max -m 2048 \
		-device virtio-blk-device,drive=x0,bus=virtio-mmio-bus.0 \
		-drive file=$(IMAGE),if=none,format=raw,id=x0 \
		-device ramfb -nographic -no-reboot 2>&1 | \
		strings | grep -E 'Welcome|kernel|PANIC|scheduler|boot' | head -n 20
	@echo "Done"

test-long: image
	@echo "QEMU extended test (120s)..."
	timeout 120 qemu-system-aarch64 \
		-bios /usr/share/qemu-efi-aarch64/QEMU_EFI.fd \
		-M virt -cpu max -m 2048 \
		-device virtio-blk-device,drive=x0,bus=virtio-mmio-bus.0 \
		-drive file=$(IMAGE),if=none,format=raw,id=x0 \
		-device virtio-keyboard-device,bus=virtio-mmio-bus.1 \
		-device virtio-tablet-device,bus=virtio-mmio-bus.2 \
		-device ramfb -nographic -no-reboot 2>&1 | tee /tmp/haiku-test.log
	@echo "Done — log at /tmp/haiku-test.log"

clean:
	rm -rf $(BUILD_DIR)

distclean:
	rm -rf $(HAIKU_DIR) $(BUILDTOOLS_DIR) $(BUILD_DIR)

bootstrap: toolchain
	cd $(BUILD_DIR) && jam -j$(NPROC) -q @bootstrap-mmc
	@echo "✅ Bootstrap image built"
	@ls -lh $(BUILD_DIR)/haiku-mmc.image

nightly-arm64-sync:
	@chmod +x $(CURDIR)/scripts/fetch-latest-arm64-nightly.sh
	@$(CURDIR)/scripts/fetch-latest-arm64-nightly.sh $(NIGHTLY_SYNC_ARGS)

stock-validate: nightly-arm64-sync bfs-fuse
	@chmod +x $(CURDIR)/scripts/qemu-desktop-harness.sh
	$(CURDIR)/scripts/qemu-desktop-harness.sh validate --image "$(NIGHTLY_BASE_IMAGE)"

desktop-image: bfs-fuse direct-package
	@chmod +x $(CURDIR)/scripts/build-validated-desktop-image.sh
	BASE_IMAGE="$(NIGHTLY_BASE_IMAGE)" OUTPUT_IMAGE="$(DESKTOP_BUILD_IMAGE)" $(CURDIR)/scripts/build-validated-desktop-image.sh

desktop-refresh: nightly-arm64-sync desktop-image desktop-validate

desktop-probe-overlays: nightly-arm64-sync desktop-image
	@chmod +x $(CURDIR)/scripts/probe-direct-package-overlays.sh
	$(CURDIR)/scripts/probe-direct-package-overlays.sh

desktop-stop:
	@chmod +x $(CURDIR)/scripts/qemu-desktop-harness.sh
	-@$(CURDIR)/scripts/qemu-desktop-harness.sh stop \
		--tmux-session "$(DESKTOP_TMUX_SESSION)" \
		--state-file "$(DESKTOP_STATE_FILE)" \
		--monitor-socket "$(DESKTOP_MONITOR_SOCKET)" >/dev/null 2>&1 || true
	-@python3 -c "import os,signal; needles=['/workspace/tmp/haiku-boot-harness/','tracker-shot-'];\
for pid in [p for p in os.listdir('/proc') if p.isdigit()]:\
\n    cmd=open(f'/proc/{pid}/cmdline','rb').read().replace(b'\\0',b' ').decode('utf-8','ignore') if os.path.exists(f'/proc/{pid}/cmdline') else '';\
\n    (('qemu-system-aarch64' in cmd and any(n in cmd for n in needles)) and os.kill(int(pid), signal.SIGTERM))" 2>/dev/null || true
	@echo "✅ Desktop session stopped (if it was running)"

desktop-run: desktop-stop
	@mkdir -p $(DESKTOP_HARNESS_DIR)
	@chmod +x $(CURDIR)/scripts/qemu-desktop-harness.sh
	$(CURDIR)/scripts/qemu-desktop-harness.sh run \
		--image "$(DESKTOP_RUN_IMAGE)" \
		--tmux-session "$(DESKTOP_TMUX_SESSION)" \
		--state-file "$(DESKTOP_STATE_FILE)" \
		--monitor-socket "$(DESKTOP_MONITOR_SOCKET)"

desktop-status:
	@test -f "$(DESKTOP_STATE_FILE)" || { echo "error: missing state file $(DESKTOP_STATE_FILE)"; exit 1; }
	@. "$(DESKTOP_STATE_FILE)"; \
		echo "session:      $$TMUX_SESSION"; \
		echo "state file:   $(DESKTOP_STATE_FILE)"; \
		echo "monitor:      $$MONITOR_SOCKET"; \
		echo "serial log:   $$SERIAL_LOG"; \
		echo "qemu log:     $$LOG_FILE"; \
		echo "work image:   $$WORK_IMAGE"; \
		echo "screenshot:   $$SCREENSHOT_OUT"; \
		echo; \
		echo "tmux:"; \
		tmux list-sessions | grep -F "$$TMUX_SESSION" || true; \
		echo; \
		echo "recent serial log:"; \
		tail -n 30 "$$SERIAL_LOG" 2>/dev/null || true

desktop-logs:
	@test -f "$(DESKTOP_STATE_FILE)" || { echo "error: missing state file $(DESKTOP_STATE_FILE)"; exit 1; }
	@. "$(DESKTOP_STATE_FILE)"; exec tail -f "$$SERIAL_LOG"

desktop-attach:
	@tmux attach -t $(DESKTOP_TMUX_SESSION)

desktop-capture: desktop-stop
	@mkdir -p $(DESKTOP_HARNESS_DIR)
	@chmod +x $(CURDIR)/scripts/qemu-desktop-harness.sh
	$(CURDIR)/scripts/qemu-desktop-harness.sh capture \
		--image "$(DESKTOP_RUN_IMAGE)" \
		--tmux-session "$(DESKTOP_TMUX_SESSION)" \
		--state-file "$(DESKTOP_STATE_FILE)" \
		--monitor-socket "$(DESKTOP_MONITOR_SOCKET)" \
		--screenshot-out "$(DESKTOP_SCREENSHOT)"
	@echo "✅ Screenshot saved: $(DESKTOP_SCREENSHOT)"

desktop-screenshot:
	@chmod +x $(CURDIR)/scripts/qemu-desktop-harness.sh
	$(CURDIR)/scripts/qemu-desktop-harness.sh screenshot \
		--state-file "$(DESKTOP_STATE_FILE)" \
		--screenshot-out "$(DESKTOP_SCREENSHOT)"
	@echo "✅ Screenshot saved: $(DESKTOP_SCREENSHOT)"

desktop-validate: bfs-fuse
	@chmod +x $(CURDIR)/scripts/qemu-desktop-harness.sh
	$(CURDIR)/scripts/qemu-desktop-harness.sh validate --timeout "$(DESKTOP_VALIDATE_TIMEOUT_SECS)" --image "$(DESKTOP_VALIDATE_IMAGE)"

validation-image: desktop-image
	@echo "✅ Core validation raw image: $(VALIDATION_RAW_IMAGE)"

validation-qcow: validation-image
	@mkdir -p "$$(dirname "$(VALIDATION_QCOW_IMAGE)")"
	qemu-img convert -f raw -O qcow2 "$(VALIDATION_RAW_IMAGE)" "$(VALIDATION_QCOW_IMAGE)"
	qemu-img info "$(VALIDATION_QCOW_IMAGE)"
	@echo "✅ Core validation qcow2 image: $(VALIDATION_QCOW_IMAGE)"

validation-artifacts: full-sync validation-image full-validate validation-qcow
	cd "$$(dirname "$(VALIDATION_RAW_IMAGE)")" && sha256sum "$$(basename "$(VALIDATION_RAW_IMAGE)")" "$$(basename "$(VALIDATION_QCOW_IMAGE)")" > SHA256SUMS
	@echo "✅ Validation artifacts ready in $$(dirname "$(VALIDATION_RAW_IMAGE)")"

full-standard-image: bfs-fuse direct-package
	@chmod +x $(CURDIR)/scripts/build-validated-desktop-image.sh
	IMAGE_FLAVOR=full OUTPUT_DIR="$(FULL_OUTPUT_DIR)" OUTPUT_IMAGE="$(FULL_BUILD_IMAGE)" OUTPUT_HAIKU_HPKG="$(FULL_OUTPUT_DIR)/haiku-direct-full.hpkg" $(CURDIR)/scripts/build-validated-desktop-image.sh
	@echo "✅ Full standard prototype raw image: $(FULL_BUILD_IMAGE)"

full-standard-validate: bfs-fuse
	@chmod +x $(CURDIR)/scripts/qemu-desktop-harness.sh
	$(CURDIR)/scripts/qemu-desktop-harness.sh validate --timeout "$(FULL_VALIDATE_TIMEOUT_SECS)" --image "$(FULL_BUILD_IMAGE)"

full-standard-qcow: full-standard-image
	@mkdir -p "$$(dirname "$(FULL_QCOW_IMAGE)")"
	qemu-img convert -f raw -O qcow2 "$(FULL_BUILD_IMAGE)" "$(FULL_QCOW_IMAGE)"
	qemu-img info "$(FULL_QCOW_IMAGE)"
	@echo "✅ Full standard prototype qcow2 image: $(FULL_QCOW_IMAGE)"

full-standard-artifacts: full-sync full-standard-image full-standard-validate full-standard-qcow
	cd "$(FULL_OUTPUT_DIR)" && sha256sum "$$(basename "$(FULL_BUILD_IMAGE)")" "$$(basename "$(FULL_QCOW_IMAGE)")" > SHA256SUMS
	@echo "✅ Full standard prototype artifacts ready in $(FULL_OUTPUT_DIR)"

utm-ios-bootstrap: image
	@mkdir -p "$(UTM_IOS_DIR)"
	qemu-img convert -f raw -O qcow2 "$(IMAGE)" "$(UTM_IOS_BOOTSTRAP_QCOW)"
	cd "$(UTM_IOS_DIR)" && sha256sum "$$(basename "$(UTM_IOS_BOOTSTRAP_QCOW)")" > SHA256SUMS
	qemu-img info "$(UTM_IOS_BOOTSTRAP_QCOW)"
	@echo "✅ UTM/iOS minimum qcow2 image: $(UTM_IOS_BOOTSTRAP_QCOW)"

utm-ios-smoke: utm-ios-bootstrap
	@set -o pipefail; \
	 timeout 90 qemu-system-aarch64 \
		-bios /usr/share/qemu-efi-aarch64/QEMU_EFI.fd \
		-M virt -cpu max -m 2048 \
		-device virtio-blk-device,drive=x0,bus=virtio-mmio-bus.0 \
		-drive file="$(UTM_IOS_BOOTSTRAP_QCOW)",if=none,format=qcow2,id=x0 \
		-device ramfb -nographic -no-reboot >"$(UTM_IOS_BOOTSTRAP_LOG)" 2>&1 || test $$? -eq 124; \
	 strings "$(UTM_IOS_BOOTSTRAP_LOG)" | grep -q 'Welcome to the Haiku boot loader'; \
	 strings "$(UTM_IOS_BOOTSTRAP_LOG)" | grep -q 'volume at "/boot/system" registered'; \
	 ! strings "$(UTM_IOS_BOOTSTRAP_LOG)" | grep -q 'PANIC:'
	@echo "✅ UTM/iOS qcow2 smoke passed: $(UTM_IOS_BOOTSTRAP_LOG)"

release-audit: bfs-fuse direct-package
	@chmod +x $(CURDIR)/scripts/audit-release-package-closure.sh
	$(CURDIR)/scripts/audit-release-package-closure.sh

full-sync: nightly-arm64-sync
full-stock-validate: stock-validate
full-image: desktop-image
full-refresh: desktop-refresh
full-probe-overlays: desktop-probe-overlays
full-run: desktop-run
full-stop: desktop-stop
full-status: desktop-status
full-logs: desktop-logs
full-attach: desktop-attach
full-capture: desktop-capture
full-screenshot: desktop-screenshot
full-validate: desktop-validate
full-check: full-sync full-stock-validate full-image full-validate full-probe-overlays

orangepi6plus-efi-snapshot:
	@chmod +x $(CURDIR)/scripts/snapshot-orangepi6plus-efi.sh
	ESP_DEV="$(ORANGEPI6PLUS_EFI_ESP_DEV)" OUTPUT_DIR="$(ORANGEPI6PLUS_EFI_SNAPSHOT_DIR)" \
		$(CURDIR)/scripts/snapshot-orangepi6plus-efi.sh $(if $(filter 1 yes true,$(INCLUDE_LARGE)),--include-large,)
