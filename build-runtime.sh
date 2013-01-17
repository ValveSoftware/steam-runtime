#!/bin/bash
#
# Script to build and install packages into the Steam runtime

# Set this to "true" to install debug symbols and developer headers
DEVELOPER_RUNTIME=true

# This is the distribution on which we're basing this version of the runtime.
DISTRIBUTION=precise
ARCHITECTURE=$(dpkg --print-architecture)

# The top level directory
TOP=$(cd "${0%/*}" && echo ${PWD})
cd "${TOP}"


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

build_package()
{
    DISTRIBUTION=$1
    ARCHITECTURE=$2
    PACKAGE=$3

    DIR="${TOP}/packages/source/${PACKAGE}"
    mkdir -p "${DIR}"; cd "${DIR}"

    # Get the source
    if [ ! -f .downloaded ]; then
        echo "DOWNLOADING: ${PACKAGE}"
        apt-get source --download-only ${PACKAGE} || exit 10
        touch .downloaded
    fi

    # Make sure the package description exists
    DSC=$(echo *.dsc)
    if [ ! -f "${DSC}" ]; then
        echo "WARNING: Missing dsc file for ${PACKAGE}" >&2
        return
    fi

    # Calculate the checksum for the source
    CHECKSUM=.checksum
    md5sum "${DSC}" >"${CHECKSUM}"
    for patch in "${TOP}/packages/patches/${PACKAGE}"/*; do
        if [ -f "${patch}" ]; then
            md5sum "${patch}" >>"${CHECKSUM}"
        fi
    done

    # Build
    BUILD="${TOP}/packages/binary/${ARCHITECTURE}/${PACKAGE}"
    BUILDTAG="${BUILD}/.built"
    mkdir -p ${BUILD}
    if [ ! -f "${BUILDTAG}" ] || ! cmp "${BUILDTAG}" "${CHECKSUM}" 2>/dev/null; then
        echo "BUILDING: ${PACKAGE} for ${ARCHITECTURE}"

        # Back up old files
        OLD="${BUILD}/old-versions"
        mkdir -p "${OLD}"
        for file in "${BUILD}"/*.*; do
            if [ -f "${file}" ]; then
                mv -v "${file}" "${OLD}/"
            fi
        done

        # Make sure we have build dependencies
        sudo apt-get build-dep -y "${PACKAGE}"

        # Extract the source and apply patches
        PACKAGE_DIR=$(echo "${DSC}" | sed -e 's,-[^-]*$,,' -e 's,_,-,g')
        if [ -d "${PACKAGE_DIR}" ]; then
            echo -n "${PACKAGE_DIR} already exists, remove it? [Y/n]: "
            read answer
            if [ "$answer" = "n" ]; then
                echo "Please create a patch of any local changes and restart." >&2
                exit 20
            fi
            rm -rf "${PACKAGE_DIR}"
        fi

        dpkg-source -x "${DSC}" || exit 20
        for patch in "${TOP}/packages/patches/${PACKAGE}"/*; do
            if [ -f "${patch}" ]; then
                patchname="$(basename "${patch}")"
                echo "APPLYING: ${patchname}"
                (cd "${PACKAGE_DIR}" && patch -p1 <"${patch}") || exit 20
            fi
        done

        # Build the package
        (cd "${PACKAGE_DIR}" && dpkg-buildpackage -b) || exit 30

        # Move the binary packages into place
        for file in *.changes *.deb *.ddeb *.udeb; do
            if [ -f "${file}" ]; then
                mv -v "${file}" "${BUILD}/${file}"
            fi
        done

        # Clean up the source
        rm -rf "${PACKAGE_DIR}"

        # Copy the checksum to mark the build complete
        cp "${CHECKSUM}" "${BUILDTAG}"
    else
        echo "${PACKAGE} for ${ARCHITECTURE} is up to date"
    fi
    rm -f "${CHECKSUM}"

    # Done!
    cd "${TOP}"
}

install_deb()
{
    ARCHIVE=$1
    RUNTIME=$2

    INSTALLTAG_DIR="${RUNTIME}/installed"
    INSTALLTAG="$(basename "${ARCHIVE}" | sed -e 's,\.deb$,,' -e 's,\.ddeb$,,')"
    if [ -f "${INSTALLTAG_DIR}/${INSTALLTAG}" ]; then
        echo "INSTALLED: $(basename ${ARCHIVE})"
    else
        echo "INSTALLING: $(basename ${ARCHIVE})"

        RUNTIME_TMP="${RUNTIME}/tmp"
        rm -rf "${RUNTIME_TMP}"
        mkdir -p "${RUNTIME_TMP}"
        cd "${RUNTIME_TMP}"
        ar x "${ARCHIVE}" || exit 40
        tar xf data.tar.* -C .. || exit 40
        cd "${TOP}"
        rm -rf "${RUNTIME_TMP}"

        mkdir -p "${INSTALLTAG_DIR}"
        touch "${INSTALLTAG_DIR}/${INSTALLTAG}"
    fi
}

process_package()
{
    RUNTIME="${TOP}/runtime/${ARCHITECTURE}"
    SOURCE_PACKAGE=$1

    echo ""
    echo "Processing ${SOURCE_PACKAGE}..."
    shift
    sleep 1

    build_package ${DISTRIBUTION} ${ARCHITECTURE} ${SOURCE_PACKAGE}
    for PACKAGE in $*; do
        # Skip development packages for end-user runtime
        if (echo "${PACKAGE}" | grep -- '-dev$' >/dev/null) && [ "${DEVELOPER_RUNTIME}" != "true" ]; then
            continue
        fi

        ARCHIVE=$(echo "${TOP}"/packages/binary/${ARCHITECTURE}/${SOURCE_PACKAGE}/${PACKAGE}_*_${ARCHITECTURE}.deb)
        if [ -f "${ARCHIVE}" ]; then
            install_deb "${ARCHIVE}" "${RUNTIME}"
        else
            echo "WARNING: Missing ${ARCHIVE}" >&2
            continue
        fi

        if [ "${DEVELOPER_RUNTIME}" = "true" ]; then
            SYMBOL_ARCHIVE=$(echo "${TOP}"/packages/binary/${ARCHITECTURE}/${SOURCE_PACKAGE}/${PACKAGE}-dbgsym_*_${ARCHITECTURE}.ddeb)
            if [ -f "${SYMBOL_ARCHIVE}" ]; then
                install_deb "${SYMBOL_ARCHIVE}" "${RUNTIME}"
            fi
        fi
    done
}

# Make sure we're in the build environment
if [ ! -f "/README.txt" ]; then
    echo "You are not running in the build environment!"
    echo -n "Are you sure you want to continue? [y/N]: "
    read answer
    if [ "$answer" != "y" -a "$answer" != "Y" ]; then
        exit 2
    fi
fi

# Build and install the packages
if [ "$1" != "" ]; then
    for SOURCE_PACKAGE in "$@"; do
        if valid_package "${SOURCE_PACKAGE}"; then
            process_package $(egrep "^${SOURCE_PACKAGE}" packages.txt)
        fi
    done
else
    for SOURCE_PACKAGE in $(cat packages.txt | egrep -v '^#' | awk '{print $1}'); do
        process_package $(egrep "^${SOURCE_PACKAGE}" packages.txt)
    done
fi

# vi: ts=4 sw=4 expandtab
