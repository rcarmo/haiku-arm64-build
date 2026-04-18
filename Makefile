# Haiku ARM64 Build — Reproducible Makefile
# Host: Orange Pi 6 Plus (aarch64 Debian Trixie)

HAIKU_DIR     := $(CURDIR)/haiku
BUILD_DIR     := $(HAIKU_DIR)/generated.arm64
BUILDTOOLS_DIR := $(CURDIR)/buildtools
NPROC         := $(shell nproc)
IMAGE         := $(BUILD_DIR)/haiku-mmc.image

.PHONY: all toolchain image clean update test help

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
