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

Steam ships with a copy of the Steam Runtime and all Steam Applications are launched within the runtime environment. For some scenarios, you may want to test an application with a different build of the runtime. You can use the **build-runtime.py** script to download various flavors of the runtime.

To get a Steam Runtime in a directory, run a command like:

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

Once the runtime is downloaded (and unpacked into a directory, if you used
an archive), you can use the **run.sh** script to launch any program
within that runtime environment.

To launch Steam itself (and any Steam applications) within your runtime, set the STEAM_RUNTIME environment variable to point to your runtime directory;

    ~/.local/share/Steam$ STEAM_RUNTIME=~/rttest ./steam.sh
    Running Steam on ubuntu 14.04 64-bit 
    STEAM_RUNTIME has been set by the user to: /home/username/rttest
    

Building in the runtime
-----------------------

To prevent libraries from development and build machines 'leaking' into your applications, you should build within a Steam Runtime chroot environment. **setup_chroot.sh** will create a Steam Runtime chroot on your machine. This chroot environment contains development libraries and tools that match the Steam Runtime.

You will need the 'schroot' tool installed as well as root access through sudo. Run either "setup-chroot.sh --i386" or "setup-chroot.sh --amd64" depending on whether you want to build a 32-bit or 64-bit application.

Both roots can co-exist side by side. 32 bit steam-runtime libraries are installed into the i386 root, and 64 bit steam-runtime libraries are installed into the amd64 root. 

Once setup-chroot.sh completes, you can use the **schroot** command to execute any build operations within the Steam Runtime environment.

    ~/src/mygame$ schroot --chroot steamrt_scout_i386 -- make -f mygame.mak

The root should be set up so that the path containing the build tree is the same inside as outside the root. If this path is not within the current user's home directory tree, it should be added to `/etc/schroot/default/fstab`

Then the next time the root is entered, this path will be available inside the root.

The setup script can be re-run to re-create the schroot environment.

Default Tools
-------------

By default, a build environment is created that contains:

* gcc-4.6 
* gcc-4.8 (default)
* clang-3.4
* clang-3.6

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
    

