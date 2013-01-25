#!/bin/bash
#
# Make sure the runtime has all necessary runtime dependencies

# The top level of the runtime tree
TOP=$(cd "${0%/*}/.." && echo ${PWD})

STATUS=0
find "${TOP}" -name 'lib*.so.[0-9]' | fgrep -v libGL.so | while read file; do
    if ! "${TOP}/scripts/check-program.sh" "$file"; then
        STATUS=1
    fi
done
exit ${STATUS}

# vi: ts=4 sw=4 expandtab
