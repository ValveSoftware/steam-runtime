#!/bin/bash
#
# This is a script which runs tools set up for the Steam runtime

PROGRAM=$(basename "$0")

# The top level of the cross-compiler tree
TOP=$(cd "${0%/*}" && echo "${PWD}/..")

if [ -z "${HOST_ARCH}" ]; then
    export HOST_ARCH=$(dpkg --print-architecture)
fi

if [ -z "${TARGET_ARCH}" ]; then
    for arg in "$@"; do
        if [ "${arg}" = "-m32" ]; then
            TARGET_ARCH="i386"
            break
        elif [ "${arg}" = "-m64" ]; then
            TARGET_ARCH="amd64"
            break
        fi
    done
    if [ -z "${TARGET_ARCH}" ]; then
        TARGET_ARCH="${HOST_ARCH}"
    fi
    export TARGET_ARCH
fi
            
if [ -z "${STEAM_RUNTIME}" ]; then
    if [ -d "${TOP}/runtime/${TARGET_ARCH}" ]; then
        STEAM_RUNTIME="${TOP}/runtime/${TARGET_ARCH}"
    elif [ -d "${TOP}/../runtime/${TARGET_ARCH}" ]; then
        STEAM_RUNTIME="${TOP}/../runtime/${TARGET_ARCH}"
    fi
    if [ ! -d "${STEAM_RUNTIME}" ]; then
        echo "Couldn't find runtime directory ${STEAM_RUNTIME}" >&2
        exit 2
    fi
    export STEAM_RUNTIME
fi

case "${TARGET_ARCH}" in
i386)
    CROSSTOOL_PREFIX="i686-unknown-linux-gnu"
    CROSSTOOL_LIBPATH="i386-linux-gnu"
    ;;
amd64)
    CROSSTOOL_PREFIX="x86_64-unknown-linux-gnu"
    CROSSTOOL_LIBPATH="x86_64-linux-gnu"
    ;;
*)
    echo "Unknown target architecture: ${TARGET_ARCH}"
    exit 1
    ;;
esac
CROSSTOOL_PATH="${TOP}/${HOST_ARCH}/${CROSSTOOL_PREFIX}/bin"

# Function to append an argument to the end of a bash array
function append_arg()
{
    ARGS+=("$1")
}

# Add any additional command line parameters
declare -a ARGS
ARGS=("$@")
case "${PROGRAM}" in
    gcc|g++)
        append_arg "-I${STEAM_RUNTIME}/usr/include"
        append_arg "-L${STEAM_RUNTIME}/usr/lib"
        append_arg "-Wl,-rpath-link=${STEAM_RUNTIME}/usr/lib"
        append_arg "-L${STEAM_RUNTIME}/usr/lib/${CROSSTOOL_LIBPATH}"
        append_arg "-Wl,-rpath-link=${STEAM_RUNTIME}/usr/lib/${CROSSTOOL_LIBPATH}"
        ;;
esac

# Run the tool...
exec "${CROSSTOOL_PATH}/${CROSSTOOL_PREFIX}-${PROGRAM}" "${ARGS[@]}"

# vi: ts=4 sw=4 expandtab
