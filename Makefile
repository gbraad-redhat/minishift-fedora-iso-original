BUILD_DIR=$(shell pwd)/build
BIN_DIR=$(BUILD_DIR)/bin
HANDLE_USER_DATA=$(shell base64 -w 0 scripts/handle-user-data)
YUM_WRAPPER=$(shell base64 -w 0 scripts/yum-wrapper)
CERT_GEN=$(shell base64 -w 0 scripts/cert-gen.sh)
VERSION=1.0.0
GITTAG=$(shell git rev-parse --short HEAD)
TODAY=$(shell date +"%d%m%Y%H%M%S")
MINISHIFT_LATEST_URL=$(shell python tests/utils/minishift_latest_version.py)
ARCHIVE_FILE=$(shell echo $(MINISHIFT_LATEST_URL) | rev | cut -d/ -f1 | rev)

ifndef BUILD_ID
    BUILD_ID=local
endif

default: fedora_iso

.PHONY: init
init:
	mkdir -p $(BUILD_DIR)

.PHONY: clean
clean:
	rm -rf $(BUILD_DIR)

.PHONY: fedora_iso
fedora_iso: KICKSTART_FILE=fedora.ks
fedora_iso: KICKSTART_TEMPLATE=fedora.template
fedora_iso: ISO_NAME=minishift-fedora
fedora_iso: RELEASEVER=26
fedora_iso: BASEARCH=x86_64
fedora_iso: iso_creation

.PHONY: iso_creation
iso_creation: init
	@handle_user_data='$(HANDLE_USER_DATA)' yum_wrapper='$(YUM_WRAPPER)' cert_gen='$(CERT_GEN)' \
		version='$(VERSION)' build_id='$(GITTAG)-$(TODAY)-$(BUILD_ID)' \
                releasever='$(RELEASEVER)' basearch='$(BASEARCH)' \
		envsubst < $(KICKSTART_TEMPLATE) > $(BUILD_DIR)/$(KICKSTART_FILE)
	cd $(BUILD_DIR); sudo livecd-creator --config $(BUILD_DIR)/$(KICKSTART_FILE) --logfile=$(BUILD_DIR)/livecd-creator.log --fslabel $(ISO_NAME)
	# http://askubuntu.com/questions/153833/why-cant-i-mount-the-ubuntu-12-04-installer-isos-in-mac-os-x
	# http://www.syslinux.org/wiki/index.php?title=Doc/isolinux#HYBRID_CD-ROM.2FHARD_DISK_MODE
	dd if=/dev/zero bs=2k count=1 of=${BUILD_DIR}/tmp.iso
	dd if=$(BUILD_DIR)/$(ISO_NAME).iso bs=2k skip=1 >> ${BUILD_DIR}/tmp.iso
	mv -f ${BUILD_DIR}/tmp.iso $(BUILD_DIR)/$(ISO_NAME).iso

.PHONY: get_gh-release
get_gh-release: init
	curl -sL https://github.com/progrium/gh-release/releases/download/v2.2.1/gh-release_2.2.1_linux_x86_64.tgz > $(BUILD_DIR)/gh-release_2.2.1_linux_x86_64.tgz
	tar -xvf $(BUILD_DIR)/gh-release_2.2.1_linux_x86_64.tgz -C $(BUILD_DIR)
	rm -fr $(BUILD_DIR)/gh-release_2.2.1_linux_x86_64.tgz

.PHONY: release
release: fedora_iso get_gh-release
	rm -rf release && mkdir -p release
	cp $(BUILD_DIR)/minishift-fedora26.iso release/
	$(BUILD_DIR)/gh-release checksums sha256
	$(BUILD_DIR)/gh-release create minishift/minishift-fedora-iso $(VERSION) master v$(VERSION)

$(BIN_DIR)/minishift:
	@echo "Downloading latest minishift binary..."
	@mkdir -p $(BIN_DIR)
	@cd $(BIN_DIR) && \
	curl -LO --progress-bar $(MINISHIFT_LATEST_URL) && \
	tar xzf $(ARCHIVE_FILE)
	@echo "Done."

.PHONY: test
test: $(BIN_DIR)/minishift
	avocado run $(SHOW_LOG) tests/test.py

