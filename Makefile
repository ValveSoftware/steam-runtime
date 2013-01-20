
# Makefile to automate the build process for the Steam runtime

all: clean-log amd64 i386

amd64 i386:
	./buildroot.sh --arch=$@ ./build-runtime.sh | tee -a build.log

update:
	./update-packages.sh

clean-log:
	@rm -f build.log

clean-runtime:
	@./clean-runtime.sh

clean: clean-log clean-runtime

distclean: clean
	@rm -rf packages
	@./buildroot.sh --clean
