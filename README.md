steam-runtime
=============

An experimental runtime environment for Steam applications

This directory contains scripts for building a Steam runtime environment
and tools to target that environment.

Makefile
--------

The Makefile is included to make it easy to do common tasks.

To build amd64 and i386 packages:
> make 

To update the source packages from the distribution repository:
> make update

To wipe the runtime environment and remove binary packages:
> make clean

Note that building all the packages from source takes a long time,
so only remove binary packages if you are sure you want a clean slate.


buildroot.sh
------------

buildroot.sh is a script to build and use a chroot environment for creating
the runtime packages and other software.

Usage: ./buildroot.sh [--create|--update|--shell|--unmount|--clean] [--arch=arch] [command] [arguments...]

buildroot/content is a directory containing files that go into the chroot environment.

buildroot/content/packages/packages.txt is a file containing a list of packages that are installed when the chroot environment is first created.

buildroot/mounts is a file containing a list of directories that are automatically mounted inside the chroot environment.

buildroot/[arch] is a directory containing the actual chroot environment for the specified architecture.


build-runtime.sh
----------------

build-runtime.sh is a script to download source, patch, build and install
the runtime packages.

Usage: ./build-runtime.sh [package...]

If run with no arguments the script will build and install all the packages
listed in packages.txt.

This script is typically run within the chroot environment for consistent
build output.

packages/source is a directory containing the downloaded source packages.

packages/binary/[arch] is a directory containing built binary packages.

runtime/[arch] is the final install location for the runtime packages.


clean-runtime.sh
----------------

clean-runtime.sh wipes clean the runtime environment.


