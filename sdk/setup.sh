#!/bin/bash
#
# This script runs a shell with the environment set up for the Steam runtime 
# development environment.

# The top level of the cross-compiler tree
TOP=$(cd "${0%/*}" && echo "${PWD}")
cd "${TOP}"

CONFIG=.config
ARCHITECTURES="i386 amd64"
ARCHIVE_EXT="tar.xz"
RUNTIME_VERSION=latest

exit_usage()
{
    echo "Usage: $0 [--host=<arch>] [--target=<arch>] [--debug|--release] [--version=<version>] [--depot=<url>] [--perforce] [--auto-upgrade] [--checkonly]" >&2
    exit 1
}

function detect_arch()
{
	case $(uname -m) in
	*64)
		echo "amd64"
		;;
	*)
		echo "i386"
		;;
	esac
}

declare -a ARGS=("$@")
while [ "$1" ]; do
    case "$1" in
    --relaunch)
        RELAUNCHED=true
        ;;
    --host=*)
        HOST_ARCH=$(expr "$1" : '[^=]*=\(.*\)')
        ;;
    --target=*)
        TARGET_ARCH=$(expr "$1" : '[^=]*=\(.*\)')
        ;;
    --debug)
        RUNTIME_FLAVOR="debug"
        ;;
    --release)
        RUNTIME_FLAVOR="release"
        ;;
    --version=*)
        RUNTIME_VERSION=$(expr "$1" : '[^=]*=\(.*\)')
        ;;
    --depot=*)
        URL_PREFIX=$(expr "$1" : '[^=]*=\(.*\)')
        ;;
    --perforce)
        USE_P4=true
        ;;
    --auto-upgrade)
        AUTO_UPGRADE=true
        ;;
    --checkonly)
        CHECK_ONLY=true
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

if [ -z "${HOST_ARCH}" ]; then
    HOST_ARCH=$(grep HOST_ARCH ${CONFIG} 2>/dev/null | awk -F= '{print $2}')
    if [ "${HOST_ARCH}" = "" ]; then
        HOST_ARCH=$(detect_arch)
    fi
fi

DEFAULT_TARGET=$(grep TARGET_ARCH ${CONFIG} 2>/dev/null | awk -F= '{print $2}')
if [ "${DEFAULT_TARGET}" = "" ]; then
    # Most people are targeting i386 (for now!)
    DEFAULT_TARGET=i386
fi
if [ -z "${TARGET_ARCH}" -a "${AUTO_UPGRADE}" = "true" ]; then
    TARGET_ARCH="${DEFAULT_TARGET}"
fi
if [ -z "${TARGET_ARCH}" ]; then
    cat <<__EOF__
======================================
Which architectures would you like to target?
    1) i386 (x86 32-bit)
    2) amd64 (x64 64-bit)
    3) all supported architectures
__EOF__
    read -p "Default ${DEFAULT_TARGET}: " response
    case "${response}" in
    1|i386)
        TARGET_ARCH=i386
        ;;
    2|amd64)
        TARGET_ARCH=amd64
        ;;
    3|all)
        TARGET_ARCH="${ARCHITECTURES}"
        ;;
    *)
        TARGET_ARCH="${DEFAULT_TARGET}"
        ;;
    esac
    echo "Set target architecture to: ${TARGET_ARCH}"
    echo
fi

DEFAULT_FLAVOR=$(grep RUNTIME_FLAVOR ${CONFIG} 2>/dev/null | awk -F= '{print $2}')
if [ "${DEFAULT_FLAVOR}" = "" ]; then
    DEFAULT_FLAVOR=release
fi
if [ -z "${RUNTIME_FLAVOR}" -a "${AUTO_UPGRADE}" = "true" ]; then
    RUNTIME_FLAVOR="${DEFAULT_FLAVOR}"
fi
if [ -z "${RUNTIME_FLAVOR}" ]; then
    cat <<__EOF__
======================================
Which runtime flavor would you like to use?
    1) release
    2) debug
__EOF__
    read -p "Default ${DEFAULT_FLAVOR}: " response
    case "${response}" in
    1)  RUNTIME_FLAVOR=release;;
    2)  RUNTIME_FLAVOR=debug;;
    *)  RUNTIME_FLAVOR="${DEFAULT_FLAVOR}";;
    esac
    echo "Set runtime flavor to: ${RUNTIME_FLAVOR}"
    echo
fi

if [ -z "${URL_PREFIX}" ]; then
    URL_PREFIX="http://media.steampowered.com/client/runtime"
fi

# Save our config
: >${CONFIG}
echo "HOST_ARCH=${HOST_ARCH}" >>${CONFIG}
echo "TARGET_ARCH=${TARGET_ARCH}" >>${CONFIG}
echo "RUNTIME_FLAVOR=${RUNTIME_FLAVOR}" >>${CONFIG}


UPDATED_FILES_RETURNCODE=42

function extract_archive()
{
    case "$1" in
    *.gz)
        BF=$(($(gzip --list "$1" | sed -n -e "s/.*[[:space:]]\+[0-9]\+[[:space:]]\+\([0-9]\+\)[[:space:]].*$/\1/p") / $((512 * 71)) + 1))
        ;;
    *.xz)
        BF=$(($(xz --robot --list "$1" | grep totals | awk '{print $5}') / $((512 * 71)) + 1))
        ;;
    *)
        BF=""
        ;;
    esac
    if [ "${BF}" ]; then
        tar --blocking-factor=${BF} --checkpoint=1 --checkpoint-action="ttyout=#" -xf "$1" -C "$2"
        echo " 100.0%"
    else
        tar -xf "$1" -C "$2"
    fi
}

function update_archive()
{
    local NAME=$1
    local DEST=$2

    if [ -z "${NAME}" -o -z "${DEST}" ]; then
        echo "Internal error: update_archive <name> <dest>" 2>&1
        exit 255
    fi

    # Download the latest archive checksum and see if we already have it
    mkdir -p downloads
    local ARCHIVE="${NAME}_${RUNTIME_VERSION}.${ARCHIVE_EXT}"
    local CHECKSUM="${ARCHIVE}.md5"
    (cd downloads; curl -sOf "${URL_PREFIX}/${CHECKSUM}")
    if [ ! -f "downloads/${CHECKSUM}" ]; then
        # No updates available
        return 0
    fi
    if [ -f "checksums/${CHECKSUM}" ] && cmp "checksums/${CHECKSUM}" "downloads/${CHECKSUM}" >/dev/null; then
        # We're all done!
        return 0
    fi

    if [ "$CHECK_ONLY" = "true" ]; then
        echo "Update available: ${URL_PREFIX}/${ARCHIVE}"
        return 1
    fi

    # Download and extract the archive
    echo "Downloading ${URL_PREFIX}/${ARCHIVE}..."
    local WORKDIR="downloads/tmp"
    (cd downloads; curl -#Of "${URL_PREFIX}/${ARCHIVE}") || exit 11
    rm -rf "${WORKDIR}"
    mkdir "${WORKDIR}"
    echo "Extracting downloads/${ARCHIVE}..."
    extract_archive "downloads/${ARCHIVE}" "${WORKDIR}" || exit 12

    # Copy in the new files
    echo "Installing new files..."
    NF=$(cd "${WORKDIR}"/*; find . \( -type f -o -type l \) -print | wc -l)
    BF=$((${NF} / 73 + 1))
    COUNT=0
    (cd "${WORKDIR}"/*; find . \( -type f -o -type l \) -print) | while read file; do
        mkdir -p "$(dirname "${DEST}/${file}")"
        mv -f "${WORKDIR}"/*/"${file}" "${DEST}/${file}" || exit 14

        COUNT=$((${COUNT} + 1))
        if [ $((${COUNT} % ${BF})) -eq 0 ]; then
            echo -n "#"
        fi
    done
    echo " 100.0%"

    # Update the checksum
    mkdir -p checksums
    rm -f checksums/${NAME}_*
    cp "downloads/$CHECKSUM" checksums/ || exit 15

    # All done!
    rm -rf "${WORKDIR}"
    return ${UPDATED_FILES_RETURNCODE}
}

function p4reconcile()
{
    P4LOG=/tmp/p4.log
    p4 reconcile -f ... >"${P4LOG}"
    echo "Perforce log is in ${P4LOG}"
}

# Update SDK files and restart if necessary
if [ "${RELAUNCHED}" = "true" ]; then
    response=n
elif [ "${AUTO_UPGRADE}" = "true" ]; then
    response=y
else
    echo "======================================"
    read -p "Update base SDK? [Y/n]: " response
fi
if [ "${response}" != "n" ]; then
    update_archive steam-runtime-sdk .
    case $? in
    0)
        if [ "${AUTO_UPGRADE}" != "true" ]; then
            echo "No updates available."
        fi
        ;;
    ${UPDATED_FILES_RETURNCODE})
        exec "$0" --relaunch --host="${HOST_ARCH}" --target="${TARGET_ARCH}" --${RUNTIME_FLAVOR} "${ARGS[@]}"
        ;;
    esac
    echo
fi

# Update tools
if [ "${AUTO_UPGRADE}" = "true" ]; then
    response=y
else
    echo "======================================"
    read -p "Update tools? [Y/n]: " response
fi
if [ "${response}" != "n" ]; then
    AVAILABLE_UPDATES=false
    for host_arch in ${HOST_ARCH}; do
        for target_arch in ${TARGET_ARCH}; do
            update_archive x-tools-${host_arch}-${target_arch} .
            case $? in
            0)
                ;;
            *)
                echo
                AVAILABLE_UPDATES=true
                ;;
            esac
        done
    done
    if [ "${AVAILABLE_UPDATES}" != "true" -a "${AUTO_UPGRADE}" != "true" ]; then
        echo "No updates available."
    fi
    echo
fi

# Update runtime
if [ "${AUTO_UPGRADE}" = "true" ]; then
    response=y
else
    echo "======================================"
    read -p "Update runtime? [Y/n]: " response
fi
if [ "${response}" != "n" ]; then
    AVAILABLE_UPDATES=false
    for target_arch in ${TARGET_ARCH}; do
        update_archive steam-runtime-dev-${RUNTIME_FLAVOR}-${target_arch} runtime-${RUNTIME_FLAVOR}
        case $? in
        0)
            ;;
        *)
            echo
            AVAILABLE_UPDATES=true
            ;;
        esac
    done
    if [ "${AVAILABLE_UPDATES}" != "true" -a "${AUTO_UPGRADE}" != "true" ]; then
        echo "No updates available."
    fi
    echo
fi
rm -f runtime || exit 16
ln -s runtime-${RUNTIME_FLAVOR} runtime

# Set up symbolic link to automatically find source when debugging
if [ "${RUNTIME_FLAVOR}" = "debug" ]; then
    ln -sf "${TOP}/runtime-${RUNTIME_FLAVOR}/source" /tmp/source
fi

if [ "${USE_P4}" = "true" ]; then
    echo "======================================"
    echo "Creating Perforce changelist..."
    rm -rf downloads old
    p4reconcile
fi

echo "======================================"
echo "Update complete!"

# vi: ts=4 sw=4 expandtab
