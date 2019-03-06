#!/bin/sh
# Copyright © 2018-2019 Collabora Ltd
#
# SPDX-License-Identifier: MIT
# (See build-runtime.py)

set -e
set -u

if ! command -v shellcheck >/dev/null 2>&1; then
    echo "1..0 # SKIP shellcheck not available"
    exit 0
fi

n=0
for shell_script in \
        scripts/*.sh \
        tests/*.sh \
        templates/*.sh \
        ; do
    n=$((n + 1))
    if shellcheck "$shell_script"; then
        echo "ok $n - $shell_script"
    else
        echo "not ok $n # TODO - $shell_script"
    fi
done

echo "1..$n"
