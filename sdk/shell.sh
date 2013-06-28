#!/bin/bash
#
# This script runs a shell with the environment set up for the Steam runtime 
# development environment.

# The top level of the cross-compiler tree
TOP=$(cd "${0%/*}" && echo "${PWD}")

exit_usage()
{
    echo "Usage: $0 [--arch=<arch>] [command] [arguments...]" >&2
    exit 1
}

while [ "$1" ]; do
    case "$1" in
    --arch=*)
        STEAM_RUNTIME_TARGET_ARCH=$(expr "$1" : '[^=]*=\(.*\)')
        ;;
    -h|--help)
        exit_usage
        ;;
    -*)
        echo "Unknown command line parameter: $1" >&2
        exit_usage
        ;;
    *)
        break
        ;;
    esac

    shift
done

if [ -z "${STEAM_RUNTIME_HOST_ARCH}" ]; then
    STEAM_RUNTIME_HOST_ARCH=$(dpkg --print-architecture)
fi
export STEAM_RUNTIME_HOST_ARCH

if [ -z "${STEAM_RUNTIME_TARGET_ARCH}" ]; then
    case "$(basename "$0")" in
    *i386*)
        STEAM_RUNTIME_TARGET_ARCH=i386
        ;;
    *amd64*)
        STEAM_RUNTIME_TARGET_ARCH=amd64
        ;;
    *)
        STEAM_RUNTIME_TARGET_ARCH="${STEAM_RUNTIME_HOST_ARCH}"
        ;;
    esac
fi
export STEAM_RUNTIME_TARGET_ARCH

case "${STEAM_RUNTIME_TARGET_ARCH}" in
i386|amd64)
    ;;
*)
    echo "Unknown target architecture: ${STEAM_RUNTIME_TARGET_ARCH}"
    exit 1
    ;;
esac

# The top level of the Steam runtime tree
if [ -z "${STEAM_RUNTIME_ROOT}" ]; then
    if [ -d "${TOP}/runtime/${STEAM_RUNTIME_TARGET_ARCH}" ]; then
        STEAM_RUNTIME_ROOT="${TOP}/runtime/${STEAM_RUNTIME_TARGET_ARCH}"
    fi
fi
if [ ! -d "${STEAM_RUNTIME_ROOT}" ]; then
    echo "$0: ERROR: Couldn't find steam runtime directory"
    if [ ! -d "${TOP}/runtime/${STEAM_RUNTIME_TARGET_ARCH}" ]; then
        echo "Do you need to run setup.sh to download the ${STEAM_RUNTIME_TARGET_ARCH} target?" >&2
    fi
    exit 2
fi
export STEAM_RUNTIME_ROOT

export PATH="${TOP}/bin:$PATH"

# Run the shell!
if [ "$*" = "" ]; then
    echo "Setting up for build targeting ${STEAM_RUNTIME_TARGET_ARCH}"
    "${SHELL}" -i
else
    "$@"
fi

# vi: ts=4 sw=4 expandtab
