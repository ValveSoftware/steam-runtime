#!/bin/bash
#
# Script to build and install packages into the Steam runtime

# The top level directory
TOP=$(cd "${0%/*}" && echo "${PWD}")
cd "${TOP}"

# Process command line options
while [ "$1" != "" ]; do
    case "$1" in
    --runtime=*)
        RUNTIME_PATH=$(expr "$1" : '[^=]*=\(.*\)')
        shift
        ;;
    --devmode=*)
        DEVELOPER_MODE=$(expr "$1" : '[^=]*=\(.*\)')
        shift
        ;;
    -*)
        echo "Usage: $0 [--runtime=<path>] [--devmode=<value>] [package] [package...]" >&2
        exit 1
        ;;
    *)
        break
    esac
done

# Set this to "true" to install debug symbols and developer headers
if [ -z "${DEVELOPER_MODE}" ]; then
    DEVELOPER_MODE=false
fi

if [ -z "${ARCHITECTURE}" ]; then
    ARCHITECTURE=$(dpkg --print-architecture)
fi
if [ -z "${RUNTIME_PATH}" ]; then
    RUNTIME_PATH="${TOP}/runtime/"
fi

valid_package()
{
    PACKAGE=$1

    for SOURCE_PACKAGE in $(cat packages.txt | grep -v '^#' | awk '{print $1}'); do
        if [ "${SOURCE_PACKAGE}" = "${PACKAGE}" ]; then
            return 0
        fi
    done

    echo "Couldn't find source package ${PACKAGE} in packages.txt" >&2
    return 1
}

build_package()
{
    ARCHITECTURE=$1
    PACKAGE=$2

    DIR="${TOP}/packages/source/${PACKAGE}"
    mkdir -p "${DIR}"; cd "${DIR}"

    # Get the source
    if [ ! -f downloaded ]; then
        echo "DOWNLOADING: ${PACKAGE}"
        apt-get source --download-only ${PACKAGE} || exit 10
        touch downloaded
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
    for patch in "${TOP}/patches/${PACKAGE}"/*; do
        if [ -f "${patch}" ]; then
            patchpath="$(dirname "${patch}")"
            patchname="$(basename "${patch}")"
            (cd "${patchpath}"; md5sum "${patchname}") >>"${CHECKSUM}"
        fi
    done

    # Build
    BUILD="${TOP}/packages/binary/${ARCHITECTURE}/${PACKAGE}"
    BUILDTAG="${BUILD}/built"
    mkdir -p ${BUILD}
    if [ ! -f "${BUILDTAG}" ] || ! cmp "${BUILDTAG}" "${CHECKSUM}" >/dev/null 2>&1; then
        echo "BUILDING: ${PACKAGE} for ${ARCHITECTURE}"

        # Make sure we have build dependencies
        sudo apt-get build-dep -y "${PACKAGE}"

        # Extract the source and apply patches
        PACKAGE_DIR=$(echo "${DSC}" | sed -e 's,-[^-]*$,,' -e 's,_,-,g' -e 's,.dsc,,')
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
        for patch in "${TOP}/patches/${PACKAGE}"/*; do
            if [ -f "${patch}" ]; then
                patchname="$(basename "${patch}")"
                echo "APPLYING: ${patchname}"
                (cd "${PACKAGE_DIR}" && patch -p1 <"${patch}") || exit 20
            fi
        done

        # Build the package
        (cd "${PACKAGE_DIR}" && dpkg-buildpackage -b -uc) || exit 30

        # Back up any old binary packages
        OLD="${BUILD}/old-versions"
        mkdir -p "${OLD}"
        for file in "${BUILD}"/*.*; do
            if [ -f "${file}" ]; then
                mv -fv "${file}" "${OLD}/"
            fi
        done

        # Move the binary packages into place
        for file in *.changes *.deb *.ddeb *.udeb; do
            if [ -f "${file}" ]; then
                mv -v "${file}" "${BUILD}/${file}" || exit 40
            fi
        done

        # Clean up the source
        rm -rf "${PACKAGE_DIR}"

        # Copy the checksum to mark the build complete
        cp "${CHECKSUM}" "${BUILDTAG}" || exit 40
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
    INSTALL_PATH=$2

    INSTALLTAG_DIR="${INSTALL_PATH}/installed"
    INSTALLTAG="$(basename "${ARCHIVE}" | sed -e 's,\.deb$,,' -e 's,\.ddeb$,,')"

    if [ -f "${INSTALLTAG_DIR}/${INSTALLTAG}.md5" ]; then
        EXISTING="$(cat "${INSTALLTAG_DIR}/${INSTALLTAG}.md5")"
    else
        EXISTING=""
    fi
    CHECKSUM="$(cd "$(dirname "${ARCHIVE}")"; md5sum "$(basename "${ARCHIVE}")")"

    if [ -f "${INSTALLTAG_DIR}/${INSTALLTAG}" -a \
         -f "${INSTALLTAG_DIR}/${INSTALLTAG}.md5" -a \
         "${EXISTING}" = "${CHECKSUM}" ]; then
        echo "INSTALLED: $(basename ${ARCHIVE})"
    else
        echo "INSTALLING: $(basename ${ARCHIVE})"

        mkdir -p "${INSTALLTAG_DIR}"
        INSTALL_TMP="${INSTALL_PATH}/tmp"
        rm -rf "${INSTALL_TMP}"
        mkdir -p "${INSTALL_TMP}"
        cd "${INSTALL_TMP}"
        ar x "${ARCHIVE}" || exit 40
        : >"${INSTALLTAG_DIR}/${INSTALLTAG}"
        (tar xvf data.tar.* -C .. | while read file; do
            if [ -f "../${file}" ]; then
                echo "${file}" >>"${INSTALLTAG_DIR}/${INSTALLTAG}"
            fi
        done) || exit 40
        echo "${CHECKSUM}" >"${INSTALLTAG_DIR}/${INSTALLTAG}.md5" || exit 40
        cd "${TOP}"
        rm -rf "${INSTALL_TMP}"
    fi
}

process_package()
{
    INSTALL_PATH="$(realpath -s "${RUNTIME_PATH}/${ARCHITECTURE}")"
    SOURCE_PACKAGE=$1

    echo ""
    echo "Processing ${SOURCE_PACKAGE}..."
    shift
    #sleep 1

    build_package ${ARCHITECTURE} ${SOURCE_PACKAGE}
    for PACKAGE in $*; do
        # Skip development packages for end-user runtime
        if (echo "${PACKAGE}" | egrep -- '-dev$|-multidev$' >/dev/null) && [ "${DEVELOPER_MODE}" != "true" ]; then
            continue
        fi

        ARCHIVE=$(echo "${TOP}"/packages/binary/${ARCHITECTURE}/${SOURCE_PACKAGE}/${PACKAGE}_*_all.deb)
        if [ -f "${ARCHIVE}" ]; then
            install_deb "${ARCHIVE}" "${INSTALL_PATH}"
        else
            ARCHIVE=$(echo "${TOP}"/packages/binary/${ARCHITECTURE}/${SOURCE_PACKAGE}/${PACKAGE}_*_${ARCHITECTURE}.deb)
            if [ -f "${ARCHIVE}" ]; then
                install_deb "${ARCHIVE}" "${INSTALL_PATH}"
            else
                echo "WARNING: Missing ${ARCHIVE}" >&2
                continue
            fi
        fi

        if [ "${DEVELOPER_MODE}" = "true" ]; then
            SYMBOL_ARCHIVE=$(echo "${TOP}"/packages/binary/${ARCHITECTURE}/${SOURCE_PACKAGE}/${PACKAGE}-dbgsym_*_${ARCHITECTURE}.ddeb)
            if [ -f "${SYMBOL_ARCHIVE}" ]; then
                install_deb "${SYMBOL_ARCHIVE}" "${INSTALL_PATH}"
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
            process_package $(awk '{ if ($1 == "'${SOURCE_PACKAGE}'") print $0 }' <packages.txt)
        fi
    done
else
    echo "======================================================="
    echo "Building runtime for ${ARCHITECTURE}"
    date

    for SOURCE_PACKAGE in $(cat packages.txt | grep -v '^#' | awk '{print $1}'); do
        process_package $(awk '{ if ($1 == "'${SOURCE_PACKAGE}'") print $0 }' <packages.txt)
    done

    echo ""
    date
    echo "======================================================="
    echo ""
fi

# Fix up the runtime
if [ "${DEVELOPER_MODE}" = "true" ]; then
    "${RUNTIME_PATH}/scripts/fix-debuglinks.sh" "${ARCHITECTURE}"
fi
"${RUNTIME_PATH}/scripts/fix-symlinks.sh" "${ARCHITECTURE}"

# vi: ts=4 sw=4 expandtab
