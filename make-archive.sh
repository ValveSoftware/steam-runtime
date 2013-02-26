#!/bin/bash
#
# Script to build a runtime archive for distribution

# The top level directory
TOP=$(cd "${0%/*}" && echo "${PWD}")
cd "${TOP}"

# We'll compress with xz
# If this changes you need to update steam.sh when it downloads the runtime
ARCHIVE_EXT="tar.xz"

function ExitUsage()
{
    echo "Usage: $0 --arch=<value> --debug=<true|false> --devmode=<true|false> --version=<value> <output-path>" >&2
    exit 1
}

# Process command line options
while [ "$1" != "" ]; do
    case "$1" in
    --arch=*)
        ARCHITECTURE=$(expr "$1" : '[^=]*=\(.*\)')
        case "${ARCHITECTURE}" in
        i386|amd64)
            ;;
        *)
            echo "Unsupported architecture: ${ARCHITECTURE}" >&2
            exit 2
            ;;
        esac
        shift
        ;;
    --debug=*)
        DEBUG=$(expr "$1" : '[^=]*=\(.*\)')
        case "${DEBUG}" in
        true|false)
            ;;
        *)
            echo "Value for --debug must be true or false" >&2
            exit 2
            ;;
        esac
        shift
        ;;
    --devmode=*)
        DEVELOPER_MODE=$(expr "$1" : '[^=]*=\(.*\)')
        case "${DEVELOPER_MODE}" in
        true|false)
            ;;
        *)
            echo "Value for --devmode must be true or false" >&2
            exit 2
            ;;
        esac
        shift
        ;;
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
if [ -z "${ARCHITECTURE}" -o -z "${DEVELOPER_MODE}" -o -z "${DEBUG}" -o -z "${VERSION}" ]; then
    ExitUsage
fi

# Figure out our runtime name
RUNTIME_NAME="steam-runtime"
if [ "${DEVELOPER_MODE}" = "true" ]; then
    RUNTIME_NAME="${RUNTIME_NAME}-dev"
fi
if [ "${DEBUG}" = "true" ]; then
    RUNTIME_NAME="${RUNTIME_NAME}-debug"
else
    RUNTIME_NAME="${RUNTIME_NAME}-release"
fi
RUNTIME_NAME="${RUNTIME_NAME}-${ARCHITECTURE}_${VERSION}"

# Create the temporary output path
make clean-runtime
WORKDIR=tmp/${RUNTIME_NAME}
rm -rf ${WORKDIR}
mkdir -p ${WORKDIR}
cp -a runtime/* ${WORKDIR}
chmod u+w -R ${WORKDIR}

# Note where people can get the debug version of this runtime
echo "${RUNTIME_NAME}" >"${WORKDIR}/version.txt"
sed "s,http://media.steampowered.com/client/runtime/.*,http://media.steampowered.com/client/runtime/$(echo ${RUNTIME_NAME} | sed 's,-release,-debug,').${ARCHIVE_EXT}," <"${WORKDIR}/README.txt" >"${WORKDIR}/README.txt.new"
mv "${WORKDIR}/README.txt.new" "${WORKDIR}/README.txt"

# Install the runtime packages
make ${ARCHITECTURE} DEVELOPER_MODE=${DEVELOPER_MODE} DEBUG=${DEBUG} RUNTIME_PATH="tmp/${RUNTIME_NAME}" || exit 3

# Publish the symbols if desired
if [ "${DEVELOPER_MODE}" = "true" -a "${DEBUG}" = "false" -a -x publish_symbols.sh ]; then
    ./publish_symbols.sh tmp/${RUNTIME_NAME}/${ARCHITECTURE} | tee /tmp/publish-symbols-${ARCHITECTURE}.log
fi

# Pack it up!
ARCHIVE_NAME="${RUNTIME_NAME}.${ARCHIVE_EXT}"
ARCHIVE="${ARCHIVE_OUTPUT_DIR}/${ARCHIVE_NAME}"
echo ""
echo "Creating ${ARCHIVE}"
mkdir -p "${ARCHIVE_OUTPUT_DIR}"
(cd tmp; tar caf "${ARCHIVE}" ${RUNTIME_NAME}) || exit 4
(cd "${ARCHIVE_OUTPUT_DIR}"; md5sum "${ARCHIVE_NAME}" >"${ARCHIVE}.md5")
(cd "${ARCHIVE_OUTPUT_DIR}"; ln -sf "${ARCHIVE_NAME}" $(echo "${ARCHIVE_NAME}" | sed "s,${VERSION},latest,"))
(cd "${ARCHIVE_OUTPUT_DIR}"; ln -sf "${ARCHIVE_NAME}.md5" $(echo "${ARCHIVE_NAME}" | sed "s,${VERSION},latest,").md5)
ls -l "${ARCHIVE}"
rm -rf ${WORKDIR}

# vi: ts=4 sw=4 expandtab
