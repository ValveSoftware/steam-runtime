#!/bin/bash
#
# This script checks to make sure the runtime symlinks are correct

# The top level of the runtime tree
TOP=$(cd "${0%/*}/.." && echo ${PWD})

ARCHITECTURES="amd64 i386"

STATUS=0
for ARCH in ${ARCHITECTURES}; do
    find "${TOP}/${ARCH}" -type l | (
    while read link; do
        target=$(readlink "${link}")
        case "${target}" in
            /*)
                echo "Absolute symlink: ${link} -> ${target}"
                NEED_FIX_SYMLINKS=true
                STATUS=1
                continue
                ;;
        esac
        if [ ! -e "${link}" ]; then
            echo "Missing link ${link} -> ${target}"
            STATUS=1
        fi
    done
    if [ "${NEED_FIX_SYMLINKS}" ]; then
        echo "You should run fix-symlinks.sh"
    fi
    )
done
exit ${STATUS}

# vi: ts=4 sw=4 expandtab
