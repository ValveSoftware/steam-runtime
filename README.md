steam-runtime
=============

A binary compatible runtime environment for Steam applications on Linux.

Introduction
------------

This release of the steam-runtime SDK marks a change to a chroot environment used for building apps. A chroot environment is a standalone Linux environment rooted somewhere in your file system.

[http://en.wikipedia.org/wiki/Chroot](http://en.wikipedia.org/wiki/Chroot "")

All processes that run within the root run relative to that rooted environment. It is possible to install a differently versioned distribution within a root, than the native distribution. For example, it is possible to install an Ubuntu 12.04 chroot environment on an Ubuntu 14.04 system. Tools and utilities for building apps can be installed in the root using standard package management tools, since from the tool's perspective it is running in a native Linux environment. This makes it well suited for an SDK environment.

Steam-runtime Repository
------------------------

The Steam-runtime SDK relies on an APT repository that Valve has created that holds the packages contained within the steam-runtime. A single package, steamrt-dev, lists all the steam-runtime development packages (i.e. packages that contain headers and files required to build software with those libraries, and whose names end in -dev) as dependencies. Conceptually, a base chroot environment is created in the traditional way using debootstrap, steamrt-dev is then installed into this, and then a set of commonly used compilers and build tools are installed. It is expected that after this script sets the environment up, developers may want to install other packages / tools they may need into the chroot environment.
If any of these packages contain runtime dependencies, then you will have to make sure to satisfy these yourself, as only the runtime dependencies of the steamrt-dev packages are included in the steam-runtime. 

Installation
------------
All the software that makes up the Steam Runtime is available in both source and binary form in the Steam Runtime repository [http://repo.steampowered.com/steamrt](http://repo.steampowered.com/steamrt "")

Included in this repository are scripts for building local copies of the Steam Runtime for testing and scripts for building Linux chroot environments suitable for building applications.

Testing or shipping with the runtime
------------------------------------

Steam ships with a copy of the Steam Runtime and all Steam Applications
are launched within the runtime environment. For some scenarios, you
may want to test an application with a different build of the runtime.

### Downloading a Steam Runtime

Current and past versions of the Steam Runtime are available from
<http://repo.steampowered.com/steamrt-images-scout/snapshots/>.
Beta builds, newer than the one included with Steam, are sometimes
available from the same location. The versioned directory names correspond
to the `version.txt` found in official Steam Runtime builds, typically
`ubuntu12_32/steam-runtime/version.txt` in a Steam installation.
The file `steam-runtime.tar.xz` in each directory contains the Steam
Runtime. It unpacks into a directory named `steam-runtime/`.

Each directory also contains various other archive and metadata files,
and a `sources/` subdirectory with source code for all the packages that
went into this Steam Runtime release.

### Building your own Steam Runtime variant

For advanced use, you can use the **build-runtime.py** script to build
your own runtime. To get a Steam Runtime in a directory, run a command
like:

    ./build-runtime.py --output=$(pwd)/runtime

The resulting directory is similar to the `ubuntu12_32/steam-runtime`
directory in a Steam installation.

To get a Steam Runtime in a compressed tar archive for easy transfer to
other systems, similar to the official runtime deployed with the
Steam client, use a command like:

    ./build-runtime.py --archive=$(pwd)/steam-runtime.tar.xz

To output a tarball and metadata files with automatically-generated
names in a directory, specify the name of an existing directory, or a
directory to be created with a `/` suffix:

    ./build-runtime.py --archive=$(pwd)/archives/

or to force a particular basename to be used for the tar archive and all
associated metadata files, end with `.*`, which will usually need to be
quoted to protect it from shell interpretation:

    ./build-runtime.py --archive="$(pwd)/archives/steam-runtime.*"

The archive will unpack into a directory named `steam-runtime`.

The `--archive` and `--output` options can be combined, but at least one
is required.

Run `./build-runtime.py --help` for more options.

### Using a Steam Runtime

Once the runtime is downloaded (and unpacked into a directory, if you used
an archive), you can use the **run.sh** script to launch any program
within that runtime environment.

To launch Steam itself (and any Steam applications) within your runtime, set the STEAM_RUNTIME environment variable to point to your runtime directory;

    ~/.local/share/Steam$ STEAM_RUNTIME=~/rttest ./steam.sh
    Running Steam on ubuntu 14.04 64-bit 
    STEAM_RUNTIME has been set by the user to: /home/username/rttest
    

Building in the runtime
-----------------------

To prevent libraries from development and build machines 'leaking'
into your applications, you should build within a Steam Runtime chroot
environment or container.

To obtain one, first find an appropriate directory in
<http://repo.steampowered.com/steamrt-images-scout/snapshots/>.
The versioned directory names correspond to the
`version.txt` found in official Steam Runtime builds, typically
`ubuntu12_32/steam-runtime/version.txt` in a Steam installation: you
should usually choose a build environment whose version matches the
Steam Runtime bundled with the current Steam release, or a slightly
older version.

To build 64-bit software, download the files named
`com.valvesoftware.SteamRuntime.Sdk-amd64,i386-scout-sysroot.tar.gz` and
`com.valvesoftware.SteamRuntime.Sdk-amd64,i386-scout-sysroot.Dockerfile`. To
build legacy 32-bit software, instead download
`com.valvesoftware.SteamRuntime.Sdk-i386-scout-sysroot.tar.gz` and
`com.valvesoftware.SteamRuntime.Sdk-i386-scout-sysroot.Dockerfile`.

Each directory also contains various other archive and metadata files,
and a `sources/` subdirectory with source code for all the packages that
went into this Steam Runtime release.

### Using Docker

The recommended way to build for the Steam Runtime is in a Docker
container. Put the `-sysroot.tar.gz` and `-sysroot.Dockerfile` files
in an otherwise empty directory, `cd` into that directory, and import
them into Docker with a command like:

    sudo docker build \
    -f com.valvesoftware.SteamRuntime.Sdk-amd64,i386-scout-sysroot.Dockerfile \
    -t steamrt_scout_amd64:latest \
    .

or for a 32-bit environment,

    sudo docker build \
    -f com.valvesoftware.SteamRuntime.Sdk-i386-scout-sysroot.Dockerfile \
    -t steamrt_scout_i386:latest \
    .

Both containers can co-exist side by side. 32 bit steam-runtime libraries
are installed into the i386 root, and 64 bit steam-runtime libraries
are installed into the amd64 root. You can keep old versions of the
container around by tagging them with a version instead of `latest`,
for example `steamrt_scout_amd64:0.20191024.0`.

For historical reasons, it is also possible to run `setup_docker.sh`.
This will download an Ubuntu 12.04 container and convert it into a Steam
Runtime environment. The result does not match the official sysroot
tarball and is not guaranteed to match any specific/identifiable version
of the Steam Runtime, so this approach is not recommended.

### Using schroot

Alternatively, you can use Debian's schroot tool (this is likely to work
best on Debian or Ubuntu machines). `setup_chroot.sh` will create a
Steam Runtime chroot on your machine. This chroot environment contains
the same development libraries and tools as the Docker container. You will
need the 'schroot' tool installed, as well as root access through sudo.

For a 64-bit environment, use a command like:

    ./setup_chroot.sh --amd64 \
    --tarball ~/Downloads/com.valvesoftware.SteamRuntime.Sdk-amd64,i386-scout-sysroot.tar.gz

or for a 32-bit environment,

    ./setup_chroot.sh --i386 \
    --tarball ~/Downloads/com.valvesoftware.SteamRuntime.Sdk-i386-scout-sysroot.tar.gz

Both roots can co-exist side by side. 32 bit steam-runtime libraries are installed into the i386 root, and 64 bit steam-runtime libraries are installed into the amd64 root. 

Once setup-chroot.sh completes, you can use the **schroot** command to execute any build operations within the Steam Runtime environment.

    ~/src/mygame$ schroot --chroot steamrt_scout_i386 -- make -f mygame.mak

The root should be set up so that the path containing the build tree is the same inside as outside the root. If this path is not within the current user's home directory tree, it should be added to `/etc/schroot/default/fstab`

Then the next time the root is entered, this path will be available inside the root.

The setup script can be re-run to re-create the schroot environment.

For historical reasons, it is possible to run `setup_chroot.sh` without
using the `--tarball` option. This will download a minimal Ubuntu 12.04
environment and convert it into a Steam Runtime environment. The result
is not guaranteed to match the official sysroot tarballs, and whether
it succeeds is heavily dependent on the operating system on which you
are running the tool, so this approach is no longer recommended.

### Using a debugger in the build environment

To get the detached debug symbols that are required for `gdb` and
similar tools, you can download the matching
`com.valvesoftware.SteamRuntime.Sdk-amd64,i386-scout-debug.tar.gz`,
unpack it (preserving directory structure), and use its `files/`
directory as the schroot or container's `/usr/lib/debug`.

For example, with Docker, you might unpack the tarball in
`/tmp/scout-dbgsym-0.20191024.0` and use something like:

    sudo docker run \
    --rm \
    --init \
    -v /home:/home \
    -v /tmp/scout-dbgsym-0.20191024.0/files:/usr/lib/debug \
    -e HOME=/home/user \
    -u $(id -u):$(id -g) \
    -h $(hostname) \
    -v /tmp:/tmp \
    -it \
    steamrt_scout_amd64:latest \
    /dev/init -sg -- /bin/bash

or with schroot, you might create
`/var/chroots/steamrt_scout_amd64/usr/lib/debug/` and move the contents
of `files/` into it.

Default Tools
-------------

By default, a build environment is created that contains:

* gcc-4.6
* gcc-4.8 (default)
* gcc-5
* clang-3.4
* clang-3.6
* clang-3.8

Switching default compilers can be done by entering the chroot environment:

    ~$ schroot --chroot steamrt_scout_i386
    
    (steamrt_scout_i386):~$ # for gcc-4.6    
    (steamrt_scout_i386):~$ update-alternatives --auto gcc
    (steamrt_scout_i386):~$ update-alternatives --auto g++
    (steamrt_scout_i386):~$ update-alternatives --auto cpp-bin
    
    (steamrt_scout_i386):~$ # for gcc-4.8
    (steamrt_scout_i386):~$ update-alternatives --set gcc /usr/bin/gcc-4.8
    (steamrt_scout_i386):~$ update-alternatives --set g++ /usr/bin/g++-4.8
    (steamrt_scout_i386):~$ update-alternatives --set cpp-bin /usr/bin/cpp-4.8
    
    (steamrt_scout_i386):~$ # for clang-3.4
    (steamrt_scout_i386):~$ update-alternatives --set gcc /usr/bin/clang-3.4
    (steamrt_scout_i386):~$ update-alternatives --set g++ /usr/bin/clang++-3.4
    (steamrt_scout_i386):~$ update-alternatives --set cpp-bin /usr/bin/cpp-4.8
    
    (steamrt_scout_i386):~$ # for clang-3.6
    (steamrt_scout_i386):~$ update-alternatives --set gcc /usr/bin/clang-3.6
    (steamrt_scout_i386):~$ update-alternatives --set g++ /usr/bin/clang++-3.6
    (steamrt_scout_i386):~$ update-alternatives --set cpp-bin /usr/bin/cpp-4.8

Using detached debug symbols
----------------------------

If your game runs in the `LD_LIBRARY_PATH`-based Steam Runtime
environment, it is likely to be loading a mixture of libraries from the
host system and libraries from the Steam Runtime. In this situation,
debugging with tools like `gdb` benefits from having
[debug symbols][].

Like typical Linux operating system library stacks, the Steam Runtime
libraries do not contain debug symbols, to keep their size small; however,
they were compiled with debug symbols included, so we can make their
corresponding [detached debug symbols][] available for download.

The steps to attach a debugger to a game apply can in fact apply equally
to the Steam client itself.

[debug symbols]: https://en.wikipedia.org/wiki/Debug_symbol
[detached debug symbols]: https://sourceware.org/gdb/onlinedocs/gdb/Separate-Debug-Files.html

### Example scenario

Suppose you are using a SteamOS 2 'brewmaster' host system, and you are
having difficulty with the PulseAudio libraries, similar to
[steam-for-linux#4753][].

* Use a SteamOS 2 'brewmaster' host system
* Ensure that your Steam client is up to date
* Do not have `libpulse0:i386` or `libopenal1:i386` installed, so that
    the 32-bit `libpulse.so.0` and `libopenal.so.1` from the Steam Runtime
    will be used
* Run the Steam client in "desktop mode", from a terminal
* Put the Steam client in Big Picture mode, which makes it initialize
    PulseAudio
* Run a 32-bit game like [Floating Point][]
* Alt-tab to a terminal
* Locate the main Steam process with `pgrep steam | xargs ps`,
    or locate the main Floating Point process with `pgrep Float | xargs ps`.
    Let's say the process you are interested in is process 12345.
* Run a command like
    `gdb ~/.steam/root/ubuntu12_32/steam 12345` (for the Steam client)
    or `gdb ~/.steam/steam/steamapps/common/"Floating Point"/"Floating Point.x86" 12345`
    (for the game).
* In gdb: `set pagination off`
* In gdb: `thread apply all bt` to see a backtrace of each thread.
* At the time of writing, the Steam client has two threads that are
    calling `pa_mainloop_run()`, while Floating Point has one such thread.
    Because you don't have debug symbols for `libpulse.so.0`, these
    backtraces are quite vague, with no information about the source
    code file/line or about the function arguments.
* Exit from gdb so that the Steam client or the game can continue to run.

[Floating Point]: https://store.steampowered.com/app/302380
[steam-for-linux#4753]: https://github.com/ValveSoftware/steam-for-linux/issues/4753#issuecomment-280920124

### Getting the debug symbols for the host system

This is the same as it would be without Steam. For a Debian, Ubuntu or
SteamOS host, `apt install libc6-dbg:i386` is a good start. For
non-Debian-derived OSs, use whatever is the OS's usual mechanism to get
detached debug symbols.

### Getting the debug symbols for the Steam Runtime

Look in `~/.steam/root/ubuntu12_32/steam-runtime/version.txt` to see
which Steam Runtime you have. These instructions assume you are using
at least version 0.20190716.1. At the time of writing, the public stable
release is version 0.20191024.0.

Look in <http://repo.steampowered.com/steamrt-images-scout/snapshots/>
for a corresponding version of the Steam Runtime container builds.

Download
`com.valvesoftware.SteamRuntime.Sdk-amd64,i386-scout-debug.tar.gz` from
the matching build. Create a directory, for example
`/tmp/scout-dbgsym-0.20191024.0`, and untar the debug symbols tarball
into that directory.

The `/tmp/scout-dbgsym-0.20191024.0/files` directory is actually the
`/usr/lib/debug` from the SDK container, and has most of the debug
symbols that you will need.

### Re-running gdb

Run gdb the same as you did before, but this time use the `-iex` option
to tell it to set the new debug symbols directory before loading the
executable, for example:

    gdb -iex \
    'set debug-file-directory /tmp/scout-debug-0.20191024.0/files:/usr/lib/debug' \
    ~/.steam/root/ubuntu12_32/steam 12345

You will get some warnings about CRC mismatches, because gdb can now
see two versions of the debug symbols for some libraries. Those warnings
can safely be ignored: gdb does the right thing.

### Example scenario revisited

* Do the setup above
* Run a command like
    `gdb ~/.steam/root/ubuntu12_32/steam 12345` (for the Steam client)
    or `gdb ~/.steam/steam/steamapps/common/"Floating Point"/"Floating Point.x86" 12345`
    (for the game).
* In gdb: `set pagination off`
* In gdb: `thread apply all bt` to see a backtrace of each thread.
* At the time of writing, the Steam client has two threads that are
    calling `pa_mainloop_run()`, while Floating Point has one such thread.
    Now that you have debug symbols for `libpulse.so.0`, these backtraces
    are more specific, with the source file, line number and function
    arguments for calls into `libpulse.so.0`, and details of functions
    that are internal to `libpulse.so.0`.
* Similarly, for `start_thread()` in `libc.so.6` (which came from the host
    system), you should see file and line information from `libc6-dbg:i386`.
* If you use `info locals` or `thread apply all bt full`, you'll also see
    that you can even get information about local variables.
