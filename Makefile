
# Makefile to automate the build process for the Steam runtime

PACKAGES := $(shell sed -e '/^\#/d' -e 's/\s.*//' <packages.txt)
ARCH ?= i386 amd64

all: clean-log packages

SHELL := /bin/bash -e -o pipefail

packages:
	$(foreach arch,$(ARCH), \
		./buildroot.sh --arch=$(arch) ./build-runtime.sh --runtime=$(RUNTIME_PATH) --debug=$(DEBUG) --devmode=$(DEVELOPER_MODE) | tee -a build.log;)

$(PACKAGES):
	$(foreach arch,$(ARCH), \
		./buildroot.sh --arch=$(arch) ./build-runtime.sh --runtime=$(RUNTIME_PATH) --debug=$(DEBUG) --devmode=$(DEVELOPER_MODE) $@ | tee -a build.log;)

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
