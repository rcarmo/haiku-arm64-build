# Haiku ARM64 Build — Reproducible Makefile
# Host: Orange Pi 6 Plus (aarch64 Debian Trixie)

HAIKU_DIR     := $(CURDIR)/haiku
BUILD_DIR     := $(HAIKU_DIR)/generated.arm64
BUILDTOOLS_DIR := $(CURDIR)/buildtools
NPROC         := $(shell nproc)
IMAGE         := $(BUILD_DIR)/haiku-mmc.image
NIGHTLY_DIR   := /workspace/tmp/haiku-nightly-arm64
NIGHTLY_BASE_IMAGE := $(NIGHTLY_DIR)/haiku-master-arm64-current-mmc.image
DESKTOP_BUILD_IMAGE := /workspace/tmp/haiku-build/validated/haiku-arm64-icu74-desktop.boot.img
DESKTOP_RUN_IMAGE := $(DESKTOP_BUILD_IMAGE)
DESKTOP_VALIDATE_IMAGE := $(DESKTOP_BUILD_IMAGE)
DESKTOP_HARNESS_DIR := /workspace/tmp/haiku-boot-harness
DESKTOP_TMUX_SESSION := haiku-desktop
DESKTOP_STATE_FILE := $(DESKTOP_HARNESS_DIR)/$(DESKTOP_TMUX_SESSION).state
DESKTOP_MONITOR_SOCKET := $(DESKTOP_HARNESS_DIR)/$(DESKTOP_TMUX_SESSION).monitor.sock
DESKTOP_SCREENSHOT := $(DESKTOP_HARNESS_DIR)/$(DESKTOP_TMUX_SESSION).ppm
ORANGEPI6PLUS_EFI_SNAPSHOT_DIR := /workspace/tmp/orangepi6plus-efi-snapshot/latest
ORANGEPI6PLUS_EFI_ESP_DEV := /dev/nvme0n1p1

.PHONY: all toolchain image clean update test help \
	nightly-arm64-sync stock-validate desktop-refresh desktop-probe-overlays \
	desktop-image desktop-run desktop-stop desktop-status desktop-logs desktop-attach \
	desktop-capture desktop-screenshot desktop-validate orangepi6plus-efi-snapshot

help:
	@echo "Haiku ARM64 Build System"
	@echo ""
	@echo "Targets:"
	@echo "  deps       - Install build dependencies (requires sudo)"
	@echo "  clone      - Clone/update haiku + buildtools repos"
	@echo "  toolchain  - Build cross-compiler toolchain"
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
		xorriso mtools u-boot-tools python3 attr \
		qemu-system-arm qemu-efi-aarch64 qemu-system-data ipxe-qemu
	@# Build jam if not present
	@if ! command -v jam >/dev/null 2>&1; then \
		echo "Building jam..."; \
		cd $(BUILDTOOLS_DIR)/jam && make -j$(NPROC) && sudo ./jam0 install; \
	fi
	@echo "✅ Dependencies installed"

clone:
	@if [ ! -d $(HAIKU_DIR)/.git ]; then \
		echo "Cloning haiku..."; \
		git clone https://review.haiku-os.org/haiku $(HAIKU_DIR); \
	fi
	@if [ ! -d $(BUILDTOOLS_DIR)/.git ]; then \
		echo "Cloning buildtools..."; \
		git clone https://review.haiku-os.org/buildtools $(BUILDTOOLS_DIR); \
	fi
	@echo "✅ Repos ready"
	@echo "  haiku:      $$(cd $(HAIKU_DIR) && git log -1 --oneline)"
	@echo "  buildtools: $$(cd $(BUILDTOOLS_DIR) && git log -1 --oneline)"

update:
	cd $(HAIKU_DIR) && git pull --ff-only
	cd $(BUILDTOOLS_DIR) && git pull --ff-only
	@echo "✅ Updated"

toolchain: clone
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
	@$(CURDIR)/scripts/fetch-latest-arm64-nightly.sh

stock-validate: nightly-arm64-sync
	@chmod +x $(CURDIR)/scripts/qemu-desktop-harness.sh
	$(CURDIR)/scripts/qemu-desktop-harness.sh validate --image "$(NIGHTLY_BASE_IMAGE)"

desktop-image:
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

desktop-validate:
	@chmod +x $(CURDIR)/scripts/qemu-desktop-harness.sh
	$(CURDIR)/scripts/qemu-desktop-harness.sh validate --image "$(DESKTOP_VALIDATE_IMAGE)"

orangepi6plus-efi-snapshot:
	@chmod +x $(CURDIR)/scripts/snapshot-orangepi6plus-efi.sh
	ESP_DEV="$(ORANGEPI6PLUS_EFI_ESP_DEV)" OUTPUT_DIR="$(ORANGEPI6PLUS_EFI_SNAPSHOT_DIR)" \
		$(CURDIR)/scripts/snapshot-orangepi6plus-efi.sh $(if $(filter 1 yes true,$(INCLUDE_LARGE)),--include-large,)
