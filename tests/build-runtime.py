#!/usr/bin/env python
# Copyright (C) 2019 Collabora Ltd.
#
# SPDX-License-Identifier: MIT
# (see COPYING)

from __future__ import print_function

import json
import os
import subprocess
import sys
import unittest

try:
    import typing
    typing      # silence pyflakes
except ImportError:
    pass


BUILD_RUNTIME = os.path.join(
    os.path.dirname(__file__),
    os.pardir,
    'build-runtime.py',
)


class TestBuildRuntime(unittest.TestCase):
    def setUp(self):
        # type: () -> None
        pass

    def test_default(self):
        j = subprocess.check_output([
            BUILD_RUNTIME,
            '--archive=runtime/',
            '--dump-options',
        ])
        o = json.loads(j, encoding='utf-8')
        self.assertEqual(o['architectures'], ['amd64', 'i386'])
        self.assertEqual(o['packages_from'], [])
        self.assertEqual(
            sorted(o['metapackages']),
            sorted(['steamrt-libs', 'steamrt-legacy']))

    def test_architectures(self):
        j = subprocess.check_output([
            BUILD_RUNTIME,
            '--archive=runtime/',
            '--dump-options',
            '--arch', 'mips',
            '--arch', 'mipsel',
        ])
        o = json.loads(j, encoding='utf-8')
        self.assertEqual(o['architectures'], ['mips', 'mipsel'])

    def test_packages_from(self):
        j = subprocess.check_output([
            BUILD_RUNTIME,
            '--archive=runtime/',
            '--dump-options',
            '--packages-from', '/tmp/packages.txt',
            '--packages-from', 'foobar.txt',
        ])
        o = json.loads(j, encoding='utf-8')
        self.assertEqual(
            o['packages_from'],
            ['/tmp/packages.txt', 'foobar.txt'],
        )

    def tearDown(self):
        # type: () -> None
        pass


if __name__ == '__main__':
    sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'third-party'))
    from pycotap import TAPTestRunner
    unittest.main(verbosity=2, testRunner=TAPTestRunner)

# vi: set sw=4 sts=4 et:
