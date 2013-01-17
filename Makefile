
# Makefile to automate the build process for the Steam runtime

all: clean-log amd64 i386

amd64 i386:
	time ./buildroot.sh --arch=$@ ./build-runtime.sh | tee -a build.log

update:
	./update-packages.sh

clean-log:
	@rm -f build.log

clean: clean-log
	@rm -rf packages/binary
	@./clean-runtime.sh

distclean: clean
	@rm -rf packages
	@./buildroot.sh --clean
