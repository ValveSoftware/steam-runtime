#!/bin/sh
# Copyright © 2016-2018 Simon McVittie
# Copyright © 2018 Collabora Ltd.
#
# SPDX-License-Identifier: MIT
# (See build-runtime.py)

set -e
set -u

if [ "x${PYCODESTYLE:=pycodestyle}" = xfalse ] || \
        [ -z "$(command -v "$PYCODESTYLE")" ]; then
    echo "1..0 # SKIP pycodestyle not found"
    exit 0
fi

echo "1..2"

# E117: over-indented
# W191: indentation contains tabs
# E211: whitespace before ‘(‘
# E225: missing whitespace around operator
# E231: missing whitespace after ‘,’, ‘;’, or ‘:’
# E501: line too long (82 > 79 characters)
# W503: line break before binary operator
if "${PYCODESTYLE}" \
    --ignore=E117,W191,E211,E225,E231,E501,W503 \
    build-runtime.py \
    >&2; then
    echo "ok 1 - $PYCODESTYLE reported no issues"
else
    echo "not ok 1 # TODO $PYCODESTYLE issues reported"
fi

if "${PYCODESTYLE}" \
    debian/tests/*.py \
    tests/*.py \
    >&2; then
    echo "ok 2 - $PYCODESTYLE reported no issues"
else
    echo "not ok 2 # TODO $PYCODESTYLE issues reported"
fi

# vim:set sw=4 sts=4 et:
