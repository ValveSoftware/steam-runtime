#!/bin/bash
#
# Script to build and install packages into the Steam runtime

# Set this to "true" to install debug symbols and developer headers
DEVELOPER_RUNTIME=true

# This is the distribution on which we're basing this version of the runtime.
DISTRIBUTION=precise

# These are the supported architectures for the runtime.
ARCHITECTURES="i386 amd64"

# The top level directory
TOP=$(cd "${0%/*}" && echo ${PWD})
cd "${TOP}"

apply_patches()
{
    # Apply any patches that aren't already applied
    PACKAGE_DIR=
    for patch in "${TOP}/patches/${PACKAGE}"/*; do
        if [ ! -f "${patch}" ]; then
            continue
        fi

        patchname=`basename "${patch}"`

        # See if we already have the patch
        echo "Checking for patch ${patchname}"
        if tar tf *.debian.tar.* | fgrep "${patchname}" >/dev/null; then
            echo " - already applied, skipping"
            continue
        else
            echo " - applying patch now..."
        fi

        # Extract the source if we need to
        if [ "${PACKAGE_DIR}" = "" ]; then
            PACKAGE_DIR=`tar tf *.orig.tar.* | head -1`
            PACKAGE_DIR=`basename "${PACKAGE_DIR}"`
            dpkg-source -x *.dsc
        fi

        # Apply the patch and commit it to the Debian changes
        cp -v "${patch}" "${patchname}"
        if ! (cd ${PACKAGE_DIR} && patch -p1 <../${patchname}); then
            # Uh oh, patch failed to apply - abort!
            return 1
        fi
        EDITOR=true dpkg-source --commit "${PACKAGE_DIR}" "${patchname}" "${patchname}"
    done

    # Pack up the archive if we made changes
    if [ "${PACKAGE_DIR}" ]; then
        dpkg-source -b "${PACKAGE_DIR}"
        rm -rf "${PACKAGE_DIR}"
    fi
}

build_package()
{
    DISTRIBUTION=$1
    ARCHITECTURE=$2
    PACKAGE=$3

    DIR="${TOP}/packages/${PACKAGE}"
    mkdir -p "${DIR}"; cd "${DIR}"

    # Get the source
    if [ ! -f .downloaded ]; then
        echo "DOWNLOADING: ${PACKAGE}"
        apt-get source --download-only ${PACKAGE} || exit 10
        touch .downloaded
    fi

    # Make sure the package description exists
    DSC=`echo *.dsc`
    if [ ! -f "${DSC}" ]; then
        echo "WARNING: Missing dsc file for ${PACKAGE}"
        return
    fi

    # Apply patches
    apply_patches || exit 20

    # Build
    BUILD="${TOP}/build/${ARCHITECTURE}/${PACKAGE}"
    BUILDTAG="${BUILD}/.built"
    mkdir -p ${BUILD}
    if [ ! -f "${BUILDTAG}" ] || ! cmp "${DSC}" "${BUILDTAG}" 2>/dev/null; then
        echo "BUILDING: ${PACKAGE} for ${ARCHITECTURE}"

        # Back up old files
        OLD="${BUILD}/old-versions"
        mkdir -p "${OLD}"
        for file in "${BUILD}"/*.*; do
            if [ -f "${file}" ]; then
                mv -v "${file}" "${OLD}/"
            fi
        done

        # Build the package
        pbuilder-dist ${DISTRIBUTION} ${ARCHITECTURE} build --buildresult "${BUILD}" "${DSC}" || exit 30
        cp "${DSC}" "${BUILDTAG}"
    else
        echo "${PACKAGE} for ${ARCHITECTURE} is up to date"
    fi

    # Done!
    cd "${TOP}"
}

install_deb()
{
    ARCHIVE=$1
    RUNTIME=$2

    # Install
    RUNTIME_TMP="${RUNTIME}/tmp"
    rm -rf "${RUNTIME_TMP}"
    mkdir -p "${RUNTIME_TMP}"
    cd "${RUNTIME_TMP}"
    ar x "${ARCHIVE}" || exit 40
    tar xf data.tar.* -C .. || exit 40
    cd "${TOP}"
    rm -rf "${RUNTIME_TMP}"
}


# Install build pre-requisites
sudo apt-get install ubuntu-dev-tools

# Set up build environment
NATIVE_ARCH=`dpkg --print-architecture`
for ARCHITECTURE in ${ARCHITECTURES}; do
    if [ "${ARCHITECTURE}" = "${NATIVE_ARCH}" ]; then
        PBUILDER_BASE="${HOME}/pbuilder/${DISTRIBUTION}-base.tgz"
    else
        PBUILDER_BASE="${HOME}/pbuilder/${DISTRIBUTION}-${ARCHITECTURE}-base.tgz"
    fi
    if [ ! -f "${PBUILDER_BASE}" ]; then
        pbuilder-dist ${DISTRIBUTION} ${ARCHITECTURE} create
    fi
done

# Build and install the packages
cat packages.txt | egrep -v '^#' | while read line; do
    if [ "${line}" = "" ]; then
        continue
    fi
    set -- ${line}

    SOURCE_PACKAGE=$1; shift
    echo ""
    echo "Processing ${SOURCE_PACKAGE}..."
    sleep 1
    for ARCHITECTURE in ${ARCHITECTURES}; do
        RUNTIME="${TOP}/runtime/${ARCHITECTURE}"

        build_package ${DISTRIBUTION} ${ARCHITECTURE} ${SOURCE_PACKAGE}
        for PACKAGE in $*; do
            # Skip development packages for end-user runtime
            if (echo "${PACKAGE}" | egrep -- '-dbg$|-dev$' >/dev/null) && [ "${DEVELOPER_RUNTIME}" != "true" ]; then
                continue
            fi

            ARCHIVE=`echo "${TOP}"/build/${ARCHITECTURE}/${SOURCE_PACKAGE}/${PACKAGE}_*_${ARCHITECTURE}.deb`
            if [ ! -f "${ARCHIVE}" ]; then
                echo "WARNING: Missing ${ARCHIVE}" >&2
                continue
            fi

            INSTALLTAG_DIR="${RUNTIME}/installed"
            INSTALLTAG=`basename "${ARCHIVE}" .deb`
            if [ -f "${INSTALLTAG_DIR}/${INSTALLTAG}" ]; then
                echo "INSTALLED: `basename ${ARCHIVE}`"
            else
                echo "INSTALLING: `basename ${ARCHIVE}`"
                install_deb "${ARCHIVE}" "${RUNTIME}"
                mkdir -p "${INSTALLTAG_DIR}"
                touch "${INSTALLTAG_DIR}/${INSTALLTAG}"
            fi
        done
    done
done

# vi: ts=4 sw=4 expandtab
