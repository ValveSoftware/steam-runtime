
This is a set of tools targeting the Steam Linux Runtime.

Setup
-------------

The first time you install the runtime SDK, you should run the setup
script from the command line to download the set of packages you need
for development:
	bash setup.sh

You can pick your target architecture(s) and either the release or debug
version of the runtime.  The debug runtime is built without optimizations
and includes full source code.

You can re-run the script at any time to reconfigure the SDK. There are
a number of command line options for automating the script, which you can
see by running the script with the --help option.


Updates
-------

You can run the setup script at any time to get the latest version of the SDK:
	setup.sh --auto-update

If you need to get an old version, you can specify it with --version:
	setup.sh --version=2013-02-22


Builds
-------

Use the appropriate shell script to set up the environment for building with
the runtime, or just look to see what environment variables it sets and use
them directly in your build process.

For example to run a shell targeting 32-bit architecture:
	shell-i386.sh

For example to run a shell targeting 64-bit architecture:
	shell-amd64.sh


Testing
-------

Once you have built a program that targets the runtime, you can verify
that all the dependencies are covered by the runtime with:
	runtime/scripts/check-program.sh <program_or_shared_library> | grep " /usr"

(note that the C library, OpenGL and 3D drivers are outside the runtime)

You can run programs in the runtime environment for testing with:
	run.sh <program> <arguments>
e.g.
	run.sh ./MyGame -windowed

You can debug your programs in the runtime environment with run.sh as well:
	run.sh gdb MyGame
	(gdb) r -windowed


More Info
---------

You can get the scripts used to build these tools and report issues at:
	https://github.com/ValveSoftware/steam-runtime

Enjoy!
