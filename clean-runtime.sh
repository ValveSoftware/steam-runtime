#!/bin/bash
#
# Script to remove all packages from the runtime

ARCHITECTURES="i386 amd64 source"

TOP=$(cd "${0%/*}" && echo ${PWD})
cd "${TOP}"

echo "Removing runtime packages for ${ARCHITECTURES}"

for ARCHITECTURE in ${ARCHITECTURES}; do
    rm -rf "${TOP}/runtime/${ARCHITECTURE}"
done

# vi: ts=4 sw=4 expandtab
