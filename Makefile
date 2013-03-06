
# Makefile to automate the build process for the Steam runtime

PACKAGES := $(shell sed -e '/^\#/d' -e 's/\s.*//' <packages.txt)

all: clean-log packages

packages:
	if [ "$(ARCH)" = "" ]; then \
		make $@ ARCH=i386; \
		make $@ ARCH=amd64; \
	else \
		./buildroot.sh --arch="$(ARCH)" ./build-runtime.sh --runtime="$(RUNTIME_PATH)" --debug="$(DEBUG)" --devmode="$(DEVELOPER_MODE)" | tee -a build.log; \
	fi

$(PACKAGES):
	if [ "$(ARCH)" = "" ]; then \
		make $@ ARCH=i386; \
		make $@ ARCH=amd64; \
	else \
		./buildroot.sh --arch="$(ARCH)" ./build-runtime.sh --runtime="$(RUNTIME_PATH)" --debug="$(DEBUG)" --devmode="$(DEVELOPER_MODE)" $@ | tee -a build.log; \
	fi

update:
	./buildroot.sh --arch=i386 --update
	./buildroot.sh --arch=amd64 --update
	./buildroot.sh ./update-packages.sh

clean-log:
	@rm -f build.log

clean-runtime:
	@./clean-runtime.sh

clean-buildroot:
	@./buildroot.sh --archive --clean

clean: clean-log clean-runtime clean-buildroot

archives:
	./make-archives.sh

distclean: clean
	@rm -rf packages
	@rm -rf buildroot/pbuilder


.PHONY: all packages $(PACKAGES) update clean-log clean-runtime clean-buildroot clean archives distclean
