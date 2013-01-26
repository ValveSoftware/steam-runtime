
# Makefile to automate the build process for the Steam runtime

ifeq "$(ARCHIVE_OUTPUT_DIR)" ""
	ARCHIVE_OUTPUT_DIR := /tmp/steam-runtime
endif

all: clean-log amd64 i386

amd64 i386:
	./buildroot.sh --arch=$@ ./build-runtime.sh --runtime="$(RUNTIME_PATH)" --devmode="$(DEVELOPER_MODE)" | tee -a build.log

update:
	./update-packages.sh

clean-log:
	@rm -f build.log

clean-runtime:
	@./clean-runtime.sh

clean-buildroot:
	@./buildroot.sh --archive --clean

clean: clean-log clean-runtime clean-buildroot

archive: archive-customer-runtime archive-developer-runtime archive-complete-runtime
	@ls -l "$(ARCHIVE_OUTPUT_DIR)"

archive-customer-runtime:
	@if [ -d tmp ]; then chmod u+w -R tmp; rm -rf tmp; fi
	make clean-runtime
	mkdir -p tmp/steam-runtime
	cp -a runtime/* tmp/steam-runtime
	make RUNTIME_PATH="$(CURDIR)/tmp/steam-runtime" DEVELOPER_MODE=false || exit 1
	@echo ""
	@echo "Creating $(ARCHIVE_OUTPUT_DIR)/steam-runtime.tar.bz2"
	mkdir -p "$(ARCHIVE_OUTPUT_DIR)"
	(cd tmp; tar jcf "$(ARCHIVE_OUTPUT_DIR)"/steam-runtime.tar.bz2 steam-runtime) || exit 2
	@if [ -d tmp ]; then chmod u+w -R tmp; rm -rf tmp; fi

archive-developer-runtime:
	@if [ -d tmp ]; then chmod u+w -R tmp; rm -rf tmp; fi
	make clean-runtime
	mkdir -p tmp/steam-runtime
	cp -a x-tools/* runtime tmp/steam-runtime
	make RUNTIME_PATH="$(CURDIR)/tmp/steam-runtime/runtime" DEVELOPER_MODE=true || exit 1
	@echo ""
	@echo "Creating $(ARCHIVE_OUTPUT_DIR)/steam-runtime-dev.tar.bz2"
	mkdir -p "$(ARCHIVE_OUTPUT_DIR)"
	(cd tmp; tar jcf "$(ARCHIVE_OUTPUT_DIR)"/steam-runtime-dev.tar.bz2 steam-runtime) || exit 2
	@if [ -d tmp ]; then chmod u+w -R tmp; rm -rf tmp; fi

archive-complete-runtime:
	@if [ -d tmp ]; then chmod u+w -R tmp; rm -rf tmp; fi
	make clean
	@echo ""
	@echo "Creating $(ARCHIVE_OUTPUT_DIR)/steam-runtime-src.tar.bz2"
	(cd ..; tar jcf "$(ARCHIVE_OUTPUT_DIR)"/steam-runtime-src.tar.bz2 steam-runtime) || exit 2

distclean: clean
	@rm -rf packages
	@rm -rf buildroot/pbuilder
