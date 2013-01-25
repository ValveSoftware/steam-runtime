steam-runtime
=============

An experimental runtime environment for Steam applications

This directory contains scripts for building a Steam runtime environment
and tools to target that environment.

The typical flow would be to just type 'make' in this directory to build
the runtime environment.

Makefile
--------

The Makefile is included to make it easy to do common tasks.

To build amd64 and i386 packages:
> make 

To update the source packages from the distribution repository:
> make update

To wipe the runtime environment and archive the build environment:
> make clean

To completely clean so you have to rebuild everything:
> make distclean


buildroot.sh
------------

buildroot.sh is automatically run by the Makefile.

buildroot.sh is a script to build and use a chroot environment for creating
the runtime packages and other software.

When run with no arguments, it will run a login shell in the chroot.

Usage: ./buildroot.sh [--create|--update|--unmount|--clean] [--arch=arch] [command] [arguments...]

buildroot/content is a directory containing files that go into the chroot environment.

buildroot/content/packages/packages.txt is a file containing a list of packages that are installed when the chroot environment is first created.

buildroot/mounts is a file containing a list of directories that are automatically mounted inside the chroot environment.

buildroot/[arch] is a directory containing the actual chroot environment for the specified architecture.


build-runtime.sh
----------------

build-runtime.sh is automatically run by the Makefile.

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

clean-runtime.sh is automatically run by the Makefile.

clean-runtime.sh wipes clean the runtime environment.


build-crosstool.sh
------------------

build-crosstool.sh builds a cross-compiler targeting the Steam runtime.

x-tools/shell.sh is a script that runs an arbitrary command with paths
set up for using the cross-compiler and development runtime.
If a command isn't passed to shell.sh, it will run an interactive shell.

For simple builds you can set the path to x-tools/bin and it will use
the correct compiler for your setup.

For more complex build environments you can either run:
	x-tools/shell.sh --arch=[i386|amd64] [command]
or set up environment variables yourself by looking at x-tools/shell.sh
