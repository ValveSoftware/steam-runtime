
# Makefile to automate the build process for the Steam runtime

all: clean-log i386 amd64

amd64 i386:
	./buildroot.sh --arch=$@ ./build-runtime.sh --runtime="$(RUNTIME_PATH)" --debug="$(DEBUG)" --devmode="$(DEVELOPER_MODE)" | tee -a build.log

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

archives:
	./make-archives.sh

distclean: clean
	@rm -rf packages
	@rm -rf buildroot/pbuilder
