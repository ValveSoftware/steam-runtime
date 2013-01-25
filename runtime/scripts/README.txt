
check-program.sh
----------------

Usage: check-program.sh executable [executable...]

This is a script to check to see if an executable or shared library has all
of its runtime dependencies met by the Steam Linux Runtime.

Note that the runtime does not provide an OpenGL implementation, so any
warnings about OpenGL or 3D hardware libraries can be ignored.


check-runtime-consistency.sh
----------------------------

Usage: check-runtime-consistency.sh

This is a script to make sure that all of the libraries included in the
runtime have their dependencies in the runtime. You can safely ignore
any warnings about OpenGL or 3D hardware libraries.


check-runtime-conflicts.sh
--------------------------

Usage: check-runtime-conflicts.sh

This is a script to look for multi-arch conflicts between packages included
in the runtime. These warnings are not a problem, they're just a sanity check
to see if the authors of the packages have completed the multi-arch process.

