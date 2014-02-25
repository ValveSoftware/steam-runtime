steam-runtime
=============

A runtime environment for Steam applications

Developing against or shipping with the runtime
-----------------------------------------------

Grab the latest runtime SDK from there:

http://media.steampowered.com/client/runtime/steam-runtime-sdk_latest.tar.xz

Read this to get started:

https://github.com/ValveSoftware/steam-runtime/blob/master/sdk/README.txt


Modifying or contributing to the runtime
----------------------------------------

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

build-crosstool.sh builds a cross-compiler targeting the Steam runtime
and puts it in x-tools.

The file README.txt in the x-tools directory has more information about
how to use the Steam runtime development environment.

