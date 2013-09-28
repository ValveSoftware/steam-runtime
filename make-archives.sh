#!/bin/bash
#
# Script to build the set of runtime archives for distribution

# The top level directory
TOP=$(cd "${0%/*}" && echo "${PWD}")
cd "${TOP}"

function ExitUsage()
{
    echo "Usage: $0 [--version=<value>] [<output-path>]" >&2
    exit 1
}

# Process command line options
while [ "$1" != "" ]; do
    case "$1" in
    --version=*)
        VERSION=$(expr "$1" : '[^=]*=\(.*\)')
        shift
        ;;
    *)
        if [ "$ARCHIVE_OUTPUT_DIR" = "" ]; then
            ARCHIVE_OUTPUT_DIR="$1"
        else
            ExitUsage
        fi
        shift
        break
    esac
done

if [ -z "${VERSION}" ]; then
    VERSION="$(date +%F)"
fi
if [ -z "${ARCHIVE_OUTPUT_DIR}" ]; then
    ARCHIVE_OUTPUT_DIR="/tmp/steam-runtime"
fi

# Create all the runtime archives
for DEVELOPER_MODE in false true; do
    for DEBUG in false true; do
        ./make-archive.sh --debug=${DEBUG} --devmode=${DEVELOPER_MODE} --version="${VERSION}" "${ARCHIVE_OUTPUT_DIR}"
    done
done

# vi: ts=4 sw=4 expandtab
