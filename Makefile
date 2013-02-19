
# Makefile to automate the build process for the Steam runtime

ifeq "$(ARCHIVE_OUTPUT_DIR)" ""
	ARCHIVE_OUTPUT_DIR := /tmp/steam-runtime
endif
ifeq "$(ARCHIVE_VERSION_TAG)" ""
	ARCHIVE_VERSION_TAG := $(shell date +%F)
endif
ARCHIVE_EXT := tar.bz2

CUSTOMER_RUNTIME := steam-runtime-bin-$(ARCHIVE_VERSION_TAG)
DEVELOPER_RUNTIME := steam-runtime-dev-$(ARCHIVE_VERSION_TAG)
COMPLETE_RUNTIME := steam-runtime-src-$(ARCHIVE_VERSION_TAG)

all: clean-log i386 amd64

amd64 i386:
	./buildroot.sh --arch=$@ ./build-runtime.sh --runtime="$(RUNTIME_PATH)" --devmode="$(DEVELOPER_MODE)" | tee -a build.log

update:
	./buildroot.sh --arch=i386 --update
	./buildroot.sh --arch=amd64 --update
	./update-packages.sh

clean-log:
	@rm -f build.log

clean-runtime:
	@./clean-runtime.sh

clean-buildroot:
	@./buildroot.sh --archive --clean

clean: clean-log clean-runtime clean-buildroot

archives: archive-customer-runtime archive-developer-runtime archive-complete-runtime
	@ls -l "$(ARCHIVE_OUTPUT_DIR)"

archive-customer-runtime:
	@if [ -d tmp ]; then chmod u+w -R tmp; rm -rf tmp; fi
	make clean-runtime
	mkdir -p tmp/$(CUSTOMER_RUNTIME)
	cp -a runtime/* tmp/$(CUSTOMER_RUNTIME)
	chmod u+w tmp/$(CUSTOMER_RUNTIME)/README.txt
	sed "s,http://media.steampowered.com/client/runtime/.*,http://media.steampowered.com/client/runtime/$(COMPLETE_RUNTIME).$(ARCHIVE_EXT)," <runtime/README.txt >tmp/$(CUSTOMER_RUNTIME)/README.txt
	make RUNTIME_PATH="$(CURDIR)/tmp/$(CUSTOMER_RUNTIME)" DEVELOPER_MODE=false || exit 1
	@echo ""
	@echo "Creating $(ARCHIVE_OUTPUT_DIR)/$(CUSTOMER_RUNTIME).$(ARCHIVE_EXT)"
	mkdir -p "$(ARCHIVE_OUTPUT_DIR)"
	(cd tmp; tar acf "$(ARCHIVE_OUTPUT_DIR)/$(CUSTOMER_RUNTIME).$(ARCHIVE_EXT)" $(CUSTOMER_RUNTIME)) || exit 2
	@if [ -d tmp ]; then chmod u+w -R tmp; rm -rf tmp; fi

archive-developer-runtime:
	@if [ -d tmp ]; then chmod u+w -R tmp; rm -rf tmp; fi
	make clean-runtime
	mkdir -p tmp/$(DEVELOPER_RUNTIME)
	cp -a x-tools/* runtime tmp/$(DEVELOPER_RUNTIME)
	chmod u+w tmp/$(DEVELOPER_RUNTIME)/runtime/README.txt
	sed "s,http://media.steampowered.com/client/runtime/.*,http://media.steampowered.com/client/runtime/$(COMPLETE_RUNTIME).$(ARCHIVE_EXT)," <runtime/README.txt >tmp/$(DEVELOPER_RUNTIME)/runtime/README.txt
	make RUNTIME_PATH="$(CURDIR)/tmp/$(DEVELOPER_RUNTIME)/runtime" DEVELOPER_MODE=true || exit 1
	@echo ""
	@echo "Creating $(ARCHIVE_OUTPUT_DIR)/$(DEVELOPER_RUNTIME).$(ARCHIVE_EXT)"
	mkdir -p "$(ARCHIVE_OUTPUT_DIR)"
	(cd tmp; tar acf "$(ARCHIVE_OUTPUT_DIR)/$(DEVELOPER_RUNTIME).$(ARCHIVE_EXT)" $(DEVELOPER_RUNTIME)) || exit 2
	@if [ -d tmp ]; then chmod u+w -R tmp; rm -rf tmp; fi

archive-complete-runtime:
	@if [ -d tmp ]; then chmod u+w -R tmp; rm -rf tmp; fi
	make clean
	@echo ""
	@echo "Creating $(ARCHIVE_OUTPUT_DIR)/$(COMPLETE_RUNTIME).$(ARCHIVE_EXT)"
	mkdir -p "$(ARCHIVE_OUTPUT_DIR)"
	(cd ..; mv steam-runtime $(COMPLETE_RUNTIME))
	(cd ..; tar acf "$(ARCHIVE_OUTPUT_DIR)/$(COMPLETE_RUNTIME).$(ARCHIVE_EXT)" $(COMPLETE_RUNTIME)) || exit 2
	(cd ..; mv $(COMPLETE_RUNTIME) steam-runtime)

distclean: clean
	@rm -rf packages
	@rm -rf buildroot/pbuilder
