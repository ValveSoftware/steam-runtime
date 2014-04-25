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
    --debug=*)
        DEBUG=$(expr "$1" : '[^=]*=\(.*\)')
        shift
        ;;
    --devmode=*)
        DEVELOPER_MODE=$(expr "$1" : '[^=]*=\(.*\)')
        shift
        ;;
    -*)
        echo "Usage: $0 [--runtime=<path>] [--debug=<value>] [--devmode=<value>] [package] [package...]" >&2
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
if [ -z "${DEBUG}" ]; then
    DEBUG=false
fi

if [ -z "${ARCHITECTURE}" ]; then
    ARCHITECTURE=$(dpkg --print-architecture)
fi
if [ -z "${RUNTIME_PATH}" ]; then
    RUNTIME_PATH="${TOP}/runtime/"
fi

valid_package()
{
    local PACKAGE=$1

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
    local ARCHITECTURE=$1
    local PACKAGE=$2

    local DIR="${TOP}/packages/source/${PACKAGE}"
    mkdir -p "${DIR}"; cd "${DIR}"

    # Get the source
    if [ ! -f downloaded ]; then
        echo "DOWNLOADING: ${PACKAGE}"
        apt-get source --download-only ${PACKAGE} || exit 10
        touch downloaded
    fi

    # Make sure the package description exists
    local DSC=$(echo *.dsc)
    if [ ! -f "${DSC}" ]; then
        echo "WARNING: Missing dsc file for ${PACKAGE}" >&2
        return
    fi

    # Calculate the checksum for the source
    local CHECKSUM=.checksum
    md5sum "${DSC}" >"${CHECKSUM}"
    for patch in "${TOP}/patches/${PACKAGE}"/*; do
        if [ -f "${patch}" ]; then
            patchpath="$(dirname "${patch}")"
            patchname="$(basename "${patch}")"
            (cd "${patchpath}"; md5sum "${patchname}") >>"${CHECKSUM}"
        fi
    done

    # Build
    local BUILD="${BINARY_PACKAGE_DIR}/${PACKAGE}"
    local BUILDTAG="${BUILD}/built"
    mkdir -p ${BUILD}
    if [ ! -f "${BUILDTAG}" ] || ! cmp "${BUILDTAG}" "${CHECKSUM}" >/dev/null 2>&1; then
        echo "BUILDING: ${PACKAGE} for ${ARCHITECTURE}"

        # Make sure we have build dependencies
        sudo apt-get build-dep -y --only-source "${PACKAGE}"

        # Extract the source and apply patches
        SOURCE_DIR="/tmp/source/${PACKAGE}"
        PACKAGE_DIR="$(basename "${DSC}" .dsc | sed 's,_\([^-]*\).*,-\1,')"
        if [ -d "${SOURCE_DIR}" ]; then
            # Always start fresh...
            #echo -n "${SOURCE_DIR} already exists, remove it? [Y/n]: "
            #read answer
            #if [ "$answer" = "n" ]; then
            #    echo "Please create a patch of any local changes and restart." >&2
            #    exit 20
            #fi
            rm -rf "${SOURCE_DIR}"
        fi

        mkdir -p "${SOURCE_DIR}"
        dpkg-source -x "${DSC}" "${SOURCE_DIR}/${PACKAGE_DIR}" || exit 20
        for patch in "${TOP}/patches/${PACKAGE}"/*; do
            if [ -f "${patch}" ]; then
                patchname="$(basename "${patch}")"
                echo "APPLYING: ${patchname}"
                (cd "${SOURCE_DIR}/${PACKAGE_DIR}" && patch -p1 <"${patch}") || exit 20
            fi
        done

        # Build the package
        if [ "${DEBUG}" = "true" ]; then
            export DEB_BUILD_OPTIONS="debug noopt nostrip"
            export DPKG_GENSYMBOLS_CHECK_LEVEL=1
        fi
        (cd "${SOURCE_DIR}/${PACKAGE_DIR}" && dpkg-buildpackage -b -uc) || exit 30

        # Back up any old binary packages
        OLD="${BUILD}/old-versions"
        mkdir -p "${OLD}"
        for file in "${BUILD}"/*.*; do
            if [ -f "${file}" ]; then
                mv -fv "${file}" "${OLD}/"
            fi
        done

        # Move the binary packages into place
        pushd "${SOURCE_DIR}"
        for file in *.changes *.deb *.ddeb *.udeb; do
            if [ -f "${file}" ]; then
                mv -v "${file}" "${BUILD}/${file}" || exit 40
            fi
        done
        popd

        # Clean up the source
        rm -rf "${SOURCE_DIR}"

        # Copy the checksum to mark the build complete
        cp "${CHECKSUM}" "${BUILDTAG}" || exit 40
    else
        echo "${PACKAGE} for ${ARCHITECTURE} is up to date"
    fi
    # Don't do this in case there are multiple builds in parallel
    #rm -f "${CHECKSUM}"

    # Done!
    cd "${TOP}"
}

install_source()
{
    local PACKAGE=$1
    local INSTALL_PATH=$2

    local DIR="${TOP}/packages/source/${PACKAGE}"
    mkdir -p "${DIR}"; cd "${DIR}"

    # Make sure the package description exists
    local DSC=$(echo *.dsc)
    if [ ! -f "${DSC}" ]; then
        echo "WARNING: Missing dsc file for ${PACKAGE}" >&2
        return
    fi

    # Extract the source and apply patches
    local SOURCE_DIR="${INSTALL_PATH}/source/${PACKAGE}"
    local PACKAGE_DIR="$(basename "${DSC}" .dsc | sed 's,_\([^-]*\).*,-\1,')"
    rm -rf "${SOURCE_DIR}"

    mkdir -p "${SOURCE_DIR}"
    dpkg-source -x "${DSC}" "${SOURCE_DIR}/${PACKAGE_DIR}" || exit 20
    for patch in "${TOP}/patches/${PACKAGE}"/*; do
        if [ -f "${patch}" ]; then
            patchname="$(basename "${patch}")"
            echo "APPLYING: ${patchname}"
            (cd "${SOURCE_DIR}/${PACKAGE_DIR}" && patch -p1 <"${patch}") || exit 20
        fi
    done
    rm -f "${SOURCE_DIR}"/*.orig.*

    # Done!
    cd "${TOP}"
}

install_compile_path()
{
    local ARCHIVE=$1
    local INSTALL_PATH=$2
    local SOURCE_ROOT=$3

    local INSTALLTAG_DIR="${INSTALL_PATH}/installed"
    local INSTALLTAG="$(basename "${ARCHIVE}" | sed -e 's,\.deb$,,' -e 's,\.ddeb$,,')"

    # Create the compile paths for symbol resolution
    for file in $(cat "${INSTALLTAG_DIR}/${INSTALLTAG}"); do
        readelf --debug-dump=info "${INSTALL_PATH=}/$file" 2>/dev/null | grep DW_AT_comp_dir | sed -e 's,.*: ,,' -e 's,/tmp/,,' | sort | uniq | while read path; do
            if [ ! -e "${SOURCE_ROOT}/${path}" ]; then
                #echo "Adding source path: '/tmp/${path}'"
                mkdir -p "${SOURCE_ROOT}/${path}"
            fi
        done
    done
}

install_deb()
{
    local ARCHIVE=$1
    local INSTALL_PATH=$2

    local INSTALLTAG_DIR="${INSTALL_PATH}/installed"
    local INSTALLTAG="$(basename "${ARCHIVE}" | sed -e 's,\.deb$,,' -e 's,\.ddeb$,,')"

    if [ -f "${INSTALLTAG_DIR}/${INSTALLTAG}.md5" ]; then
        local EXISTING="$(cat "${INSTALLTAG_DIR}/${INSTALLTAG}.md5")"
    else
        local EXISTING=""
    fi
    local CHECKSUM="$(cd "$(dirname "${ARCHIVE}")"; md5sum "$(basename "${ARCHIVE}")")"

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

update_package_index()
{
    # run apt-get update if don't know when we last ran, or haven't run it in the last hour
    NEED_APT_UPDATE=1
    if [ -f /var/lib/apt/periodic/update-success-stamp ]; then
        if [ $(stat -c "%Y" /var/lib/apt/periodic/update-success-stamp ) -gt $(date -d "1 hour ago" +%s) ]; then
            NEED_APT_UPDATE=0
        fi
    else
        sudo apt-get install -qq -y update-notifier-common
    fi
    
    if [ $NEED_APT_UPDATE -ne 0 ]; then
        echo updating apt package indexes...
        sudo apt-get -qq update || exit 4
    fi
}

process_package()
{
    local INSTALL_PATH="${RUNTIME_PATH}/${ARCHITECTURE}"
    local SOURCE_PACKAGE=$1

    echo ""
    echo "Processing ${SOURCE_PACKAGE}..."
    shift

    build_package ${ARCHITECTURE} ${SOURCE_PACKAGE}

    if [ "${DEBUG}" = "true" ]; then
        install_source ${SOURCE_PACKAGE} "${RUNTIME_PATH}"
    fi

    for PACKAGE in $*; do
        # Skip development packages for end-user runtime
        if (echo "${PACKAGE}" | egrep -- '-dbg$|-dev$|-multidev$' >/dev/null) && [ "${DEVELOPER_MODE}" != "true" ]; then
            continue
        fi

        ARCHIVE=$(echo "${BINARY_PACKAGE_DIR}"/${SOURCE_PACKAGE}/${PACKAGE}_*_all.deb)
        if [ -f "${ARCHIVE}" ]; then
            install_deb "${ARCHIVE}" "${INSTALL_PATH}"
        else
            ARCHIVE=$(echo "${BINARY_PACKAGE_DIR}"/${SOURCE_PACKAGE}/${PACKAGE}_*_${ARCHITECTURE}.deb)
            if [ -f "${ARCHIVE}" ]; then
                install_deb "${ARCHIVE}" "${INSTALL_PATH}"
            else
                echo "WARNING: Missing ${ARCHIVE}" >&2
                continue
            fi
        fi

        if [ "${DEVELOPER_MODE}" = "true" -a "${DEBUG}" != "true" ]; then
            SYMBOL_ARCHIVE=$(echo "${BINARY_PACKAGE_DIR}"/${SOURCE_PACKAGE}/${PACKAGE}-dbgsym_*_${ARCHITECTURE}.ddeb)
            if [ -f "${SYMBOL_ARCHIVE}" ]; then
                install_deb "${SYMBOL_ARCHIVE}" "${INSTALL_PATH}"
            fi
        fi

        if [ "${DEBUG}" = "true" ]; then
            install_compile_path "${ARCHIVE}" "${INSTALL_PATH}" "${RUNTIME_PATH}"
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

# Figure out where the runtime path is
RESOLVED_PATH="$(realpath -s "${RUNTIME_PATH}")"
if [ ! -d "${RESOLVED_PATH}" ]; then
    echo "Couldn't resolve path for: ${RUNTIME_PATH}" >&2
    exit 2
fi
RUNTIME_PATH="${RESOLVED_PATH}"

# Figure out where binary packages go
if [ "${DEBUG}" = "true" ]; then
    BINARY_PACKAGE_DIR="${TOP}/packages/debug/${ARCHITECTURE}"
else
    BINARY_PACKAGE_DIR="${TOP}/packages/binary/${ARCHITECTURE}"
fi

update_package_index

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
if [ "${DEVELOPER_MODE}" = "true" -a "${DEBUG}" != "true" ]; then
    "${RUNTIME_PATH}/scripts/fix-debuglinks.sh" "${ARCHITECTURE}"
fi
"${RUNTIME_PATH}/scripts/fix-symlinks.sh" "${ARCHITECTURE}"

# vi: ts=4 sw=4 expandtab
