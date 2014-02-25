# Make sure everything is clean before starting the build.
rm -rf bin crosstool-ng l-glibc_V_2.15-x86_64-213be3fb lib share /c/bl /cygdrive/c/bl

# Do the actual build.  This should take at least an hour even
# with multiprocessor builds.
./build.sh --target-os=linux

# Results will be in l-glibc_V_2.15-x86_64-213be3fb.  The binaries
# you want to use will be under bin and prefixed with x86_64-unknown-linux-gnu.
