#!/bin/bash
#
# Make sure the runtime has all necessary runtime dependencies

# The top level of the runtime tree
TOP=$(cd "${0%/*}/.." && echo ${PWD})

if [ "$1" ]; then
    CHECK_PATH="$1"
else
    CHECK_PATH="${TOP}"
fi

STATUS=0
find "${CHECK_PATH}" -type f | grep -v 'ld.*so' | \
while read file; do
    if ! (file "${file}" | fgrep " ELF " >/dev/null); then
        continue
    fi

    echo "Checking ${file}"
    if ! "${TOP}/scripts/check-program.sh" "${file}"; then
        STATUS=1
    fi
done
exit ${STATUS}

# vi: ts=4 sw=4 expandtab
