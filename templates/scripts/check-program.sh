#!/bin/bash
#
# This script checks to make sure all library dependencies are in the runtime.

# The top level of the runtime tree
TOP=$(cd "${0%/*}/.." && echo ${PWD})

# Make sure we have something to run
if [ "$1" = "" ]; then
    echo "Usage: $0 executable [executable...]"
fi

STATUS=0
OUTPUT=`mktemp`
for OBJECT in "$@"; do
    "${TOP}/run.sh" ldd "${OBJECT}" | fgrep -v "${TOP}" | fgrep "=>" | egrep '/|not found' >"${OUTPUT}"
    if [ -s "${OUTPUT}" ]; then
        echo "$1 depends on these libraries not in the runtime:"
        cat "${OUTPUT}"
        STATUS=1
    fi
done
rm -f "${OUTPUT}"

exit ${STATUS}

# vi: ts=4 sw=4 expandtab
