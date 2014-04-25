#!/bin/bash
#
# Script to build the set of runtime archives for distribution

# The top level directory
TOP=$(cd "${0%/*}" && echo "${PWD}")
cd "${TOP}"

# We'll compress with xz
# If this changes you need to update sdk/setup.sh
ARCHIVE_EXT="tar.xz"
# exported so it's noticed by tar
export XZ_OPT="-v"

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

# Figure out our runtime name
SDK_NAME="steam-runtime-sdk_${VERSION}"

# Create the temporary output path
WORKDIR=tmp/${SDK_NAME}
rm -rf ${WORKDIR}
mkdir -p ${WORKDIR}
cp -a sdk/* ${WORKDIR}
chmod u+w -R ${WORKDIR}

# Pack it up!
ARCHIVE_NAME="${SDK_NAME}.${ARCHIVE_EXT}"
ARCHIVE="${ARCHIVE_OUTPUT_DIR}/${ARCHIVE_NAME}"
echo "Creating ${ARCHIVE}"
mkdir -p "${ARCHIVE_OUTPUT_DIR}"
(cd tmp; tar caf "${ARCHIVE}" ${SDK_NAME}) || exit 4
(cd "${ARCHIVE_OUTPUT_DIR}"; md5sum "${ARCHIVE_NAME}" >"${ARCHIVE}.md5")
(cd "${ARCHIVE_OUTPUT_DIR}"; ln -sf "${ARCHIVE_NAME}" $(echo "${ARCHIVE_NAME}" | sed "s,${VERSION},latest,"))
(cd "${ARCHIVE_OUTPUT_DIR}"; ln -sf "${ARCHIVE_NAME}.md5" $(echo "${ARCHIVE_NAME}" | sed "s,${VERSION},latest,").md5)
ls -l "${ARCHIVE}"
rm -rf ${WORKDIR}

# vi: ts=4 sw=4 expandtab
