
This is a set of tools targeting the Steam Linux Runtime.


Building
--------

shell.sh is a script that runs an arbitrary command with paths set up
for using the cross-compiler and development runtime.
If a command isn't passed to shell.sh, it will run an interactive shell.

For simple builds you can set the path to the bin directory and it will use
the correct compiler for your setup.

For more complex build environments you can either run:
	shell.sh --arch=[i386|amd64] [command]
or you can look at shell.sh and the scripts in the bin directory and set
things up manually.  Using the scripts provided is recommended since they
take care of some surprising edge cases in tool configuration.


Testing
-------

Once you have built a program that targets the runtime, you can verify
that all the dependencies are covered by the runtime with:
	runtime/scripts/check-program.sh <program_or_shared_library>

(note that OpenGL and 3D driver libraries are outside the runtime)

You can run programs in the runtime environment for testing with:
	runtime/run.sh <program> <arguments>


More Info
---------

You can get the scripts used to build these tools and report issues at:
	https://github.com/ValveSoftware/steam-runtime

Enjoy!
