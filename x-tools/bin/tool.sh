#!/bin/bash
#
# This is a script which runs tools set up for the Steam runtime

PROGRAM=$(basename "$0")

# The top level of the cross-compiler tree
TOP=$(cd "${0%/*}" && echo "${PWD}/..")

if [ -z "${HOST_ARCH}" -o -z "${TARGET_ARCH}" -o -z "${STEAM_RUNTIME}" ]; then
    echo "Missing development environment variables, did you run shell.sh?"
    exit 1
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

# Function to insert an argument into a bash array
function insert_arg()
{
    ARG=$1

    # Shift other elements up
    i=${#ARGS[@]}
    while [ $i -gt 0 ]; do
        ARGS[$i]="${ARGS[$(expr $i - 1)]}"
        i=$(expr $i - 1)
    done

    # Add the new argument
    ARGS[0]="${ARG}"
}

# Add any additional command line parameters
declare -a ARGS
ARGS=("$@")
case "${PROGRAM}" in
    gcc|g++)
        insert_arg "-I${STEAM_RUNTIME}/usr/include"
        insert_arg "-L${STEAM_RUNTIME}/usr/lib"
        insert_arg "-Wl,-rpath-link=${STEAM_RUNTIME}/usr/lib"
        insert_arg "-L${STEAM_RUNTIME}/usr/lib/${CROSSTOOL_LIBPATH}"
        insert_arg "-Wl,-rpath-link=${STEAM_RUNTIME}/usr/lib/${CROSSTOOL_LIBPATH}"
        ;;
esac

# Run the tool...
exec "${CROSSTOOL_PATH}/${CROSSTOOL_PREFIX}-${PROGRAM}" "${ARGS[@]}"

# vi: ts=4 sw=4 expandtab
