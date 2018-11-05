#!/bin/bash
#
# This script checks to make sure the runtime debug symlinks are correct

# The top level of the runtime tree
TOP=$(cd "${0%/*}/.." && echo ${PWD})

if [ "$1" ]; then
    ARCHITECTURES="$1"
else
    ARCHITECTURES="amd64 i386"
fi

STATUS=0
for ARCH in ${ARCHITECTURES}; do
    if [ ! -d "${TOP}/${ARCH}/usr/lib/debug" ]; then
        continue
    fi
    cd "${TOP}/${ARCH}/usr/lib/debug"
    find . -type f | while read file; do
        file="$(echo $file | sed 's,./,,')"
        buildid="$(readelf -n "${file}" | fgrep "Build ID" | awk '{print $3}')"
        link="$(echo "${buildid}" | sed "s,\(..\)\(.*\),.build-id/\1/\2.debug,")"
        mkdir -p "$(dirname "${link}")"
        ln -sf "../../${file}" "${link}"
    done
done

# vi: ts=4 sw=4 expandtab
