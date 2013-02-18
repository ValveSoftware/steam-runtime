#!/bin/bash
#
# Script to update packages used by the Steam runtime

# The top level directory
TOP=$(cd "${0%/*}" && echo ${PWD})
cd "${TOP}"

# These are custom packages that can't be automatically downloaded
CUSTOM_PACKAGES="dummygl jasper libsdl2"

valid_package()
{
    PACKAGE=$1

    for SOURCE_PACKAGE in $(cat packages.txt | egrep -v '^#' | awk '{print $1}'); do
        if [ "${SOURCE_PACKAGE}" = "${PACKAGE}" ]; then
            return 0
        fi
    done

    echo "Couldn't find source package ${PACKAGE} in packages.txt" >&2
    return 1
}

update_package()
{
    PACKAGE=$1

    DIR="${TOP}/packages/source/${PACKAGE}"

    # Check for custom packages
    for CUSTOM in ${CUSTOM_PACKAGES}; do
        if [ "${PACKAGE}" = "${CUSTOM}" ]; then
            echo "CUSTOM: ${PACKAGE}"
            return
        fi
    done

    echo "CHECKING: ${PACKAGE}"

    # Download the new dsc file and see if it's a newer version
    TMP="${DIR}/tmp"
    rm -rf "${TMP}"
    mkdir -p "${TMP}"; cd "${TMP}"
    apt-get source --download-only --dsc-only "${PACKAGE}" >/dev/null || exit 3
    DSC=$(echo *.dsc)
    cd "${DIR}"

    if [ ! -f "${DSC}" ]; then
        echo "DOWNLOADING: ${PACKAGE}"

        # Back up old files
        OLD="${DIR}/old-versions"
        mkdir -p "${OLD}"
        for file in *.*; do
            if [ -f "${file}" ]; then
                mv -v "${file}" "${OLD}/"
            fi
        done

        # Download new files
        apt-get source --download-only "${PACKAGE}" || exit 4
        touch .downloaded
    fi
    rm -rf "${TMP}"

    cd "${TOP}"
}

# Update the packages
if [ "$1" != "" ]; then
    for PACKAGE in "$@"; do
        if valid_package "${PACKAGE}"; then
            update_package "${PACKAGE}"
        fi
    done
else
    for SOURCE_PACKAGE in $(cat packages.txt | egrep -v '^#' | awk '{print $1}'); do
        update_package "${SOURCE_PACKAGE}"
    done
fi

# vi: ts=4 sw=4 expandtab
