#!/usr/bin/env python
# Copyright (C) 2013 Valve Corporation
# Copyright (C) 2018 Collabora Ltd.
#
# SPDX-License-Identifier: MIT
# (see COPYING)

from __future__ import print_function

import sys

if __name__ == '__main__':
    source_pkgs = set()
    binary_pkgs = set()
    fail = False

    with open("packages.txt") as f:
        for line in f:
            if line[0] != '#':
                toks = line.split()
                if len(toks) > 1:
                    source_pkgs.add(toks[0])
                    binary_pkgs.update(toks[1:])

    last = None

    with open("sourcepkgs.list") as f:
        for i, line in enumerate(f):
            if line.strip() != '' and line[0] != '#':
                toks = line.split(' ', 1)
                assert toks[1] == 'install\n', repr(line)
                source_pkgs.discard(toks[0])

                if last is not None and line <= last:
                    print(
                        'warning: sourcepkgs.list:%d: not in '
                        '`LC_ALL=C sort -u` order near %r'
                        % (i, line),
                        file=sys.stderr)

                last = line

    if source_pkgs:
        for p in source_pkgs:
            print(
                'error: source package %s is listed in packages.txt '
                'but not in sourcepkgs.list'
                % p,
                file=sys.stderr)
            fail = True

    sys.exit(1 if fail else 0)

# vi: set sw=4 sts=4 et:
