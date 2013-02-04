#!/bin/bash
#
# This script checks to make sure the runtime symlinks are correct

# The top level of the runtime tree
TOP=$(cd "${0%/*}/.." && echo ${PWD})

if [ "$1" ]; then
    ARCHITECTURES="$1"
else
    ARCHITECTURES="amd64 i386"
fi

STATUS=0
for ARCH in ${ARCHITECTURES}; do
    find "${TOP}/${ARCH}" -type l | while read link; do
        target=$(readlink "${link}")
        case "${target}" in
            /*)
                # Fix absolute symbolic links
                base=$(echo "${link}" | sed "s,${TOP}/${ARCH}/,,")
                count=$(echo "${base}" | awk -F/ '{print NF - 1}')
                i=0
                target=$(echo "${target}" | sed 's,/,,')
                while [ "$i" -lt "$count" ]; do
                    target="../${target}"
                    i=$(expr $i + 1)
                done
                #echo "Fixing $link -> $target"
                ln -sf "${target}" "${link}"
                ;;
        esac
    done
done
exit ${STATUS}

# vi: ts=4 sw=4 expandtab
