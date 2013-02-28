#!/bin/bash
#
# This is a script which runs programs in the Steam runtime

# The top level of the runtime tree
TOP=$(cd "${0%/*}" && echo ${PWD})

# Make sure we have something to run
if [ "$1" = "" ]; then
    echo "Usage: $0 program [args]"
    exit 1
fi

# Note that we put the Steam runtime first
# If ldd on a program shows any library in the system path, then that program
# may not run in the Steam runtime.
export STEAM_RUNTIME="${TOP}"
export LD_LIBRARY_PATH="${TOP}/amd64/lib/x86_64-linux-gnu:${TOP}/amd64/lib:${TOP}/amd64/usr/lib/x86_64-linux-gnu:${TOP}/amd64/usr/lib:${TOP}/i386/lib/i386-linux-gnu:${TOP}/i386/lib:${TOP}/i386/usr/lib/i386-linux-gnu:${TOP}/i386/usr/lib:${LD_LIBRARY_PATH}"

exec "$@"

# vi: ts=4 sw=4 expandtab
