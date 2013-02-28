#!/bin/bash
#
# This is a script which runs programs in the Steam runtime

# The top level of the cross-compiler tree
TOP=$(cd "${0%/*}" && echo "${PWD}/..")

# Make sure we have something to run
if [ "$1" = "" ]; then
    echo "Usage: $0 program [args]"
    exit 1
fi

if [ -z "${STEAM_RUNTIME}" ]; then
    if [ -d "${TOP}/runtime" ]; then
        STEAM_RUNTIME="${TOP}/runtime"
    elif [ -d "${TOP}/../runtime" ]; then
        STEAM_RUNTIME="${TOP}/../runtime"
    fi
    if [ ! -d "${STEAM_RUNTIME}" ]; then
        echo "Couldn't find runtime directory ${STEAM_RUNTIME}" >&2
        exit 2
    fi
    export STEAM_RUNTIME
fi

# Note that we put the Steam runtime first
# If ldd on a program shows any library in the system path, then that program
# may not run in the Steam runtime.
export LD_LIBRARY_PATH="${STEAM_RUNTIME}/amd64/lib/x86_64-linux-gnu:${STEAM_RUNTIME}/amd64/lib:${STEAM_RUNTIME}/amd64/usr/lib/x86_64-linux-gnu:${STEAM_RUNTIME}/amd64/usr/lib:${STEAM_RUNTIME}/i386/lib/i386-linux-gnu:${STEAM_RUNTIME}/i386/lib:${STEAM_RUNTIME}/i386/usr/lib/i386-linux-gnu:${STEAM_RUNTIME}/i386/usr/lib:${LD_LIBRARY_PATH}"

exec "$@"

# vi: ts=4 sw=4 expandtab
