
This is a set of tools targeting the Steam Linux Runtime.

Setup & Updates
-------------

The first time you install the runtime SDK, you should run the setup
script from the command line to download the set of packages you need
for development:
	setup.sh


Updates
-------------

You can run the setup script at any time to get the latest version of the SDK:
	setup.sh --auto-upgrade

If you need to get an old version, you can get it using --version:
	setup.sh --version=2013-02-21


Simple Builds
-------------

Just add the bin directory to your PATH.

The bin directory contains scripts which wrap the compiler with the
appropriate flags for the runtime, so if your project is already set
up with gcc or g++, all you have to do is add the bin directory to
your path.


Complex Builds
--------------

If your build process uses configure scripts or pkg-config, you can use
shell.sh to set up the environment for building with the runtime, or just
look to see what environment variables it sets and use them directly in
your build process.

For example to run a shell targeting 32-bit architecture:
	shell.sh --arch=i386

For example to run a shell targeting 64-bit architecture:
	shell.sh --arch=amd64


Testing
-------

Once you have built a program that targets the runtime, you can verify
that all the dependencies are covered by the runtime with:
	runtime/scripts/check-program.sh <program_or_shared_library>

(note that OpenGL and 3D driver libraries are outside the runtime)

You can run programs in the runtime environment for testing with:
	runtime/run.sh <program> <arguments>

You can switch between the debug and release runtime environments by
switching the runtime symbolic link to point to the desired directory.
e.g.
	ln -sf runtime-debug runtime
or
	ln -sf runtime-release runtime

The source to the entire runtime is available in runtime-debug/source/


More Info
---------

You can get the scripts used to build these tools and report issues at:
	https://github.com/ValveSoftware/steam-runtime

Enjoy!
