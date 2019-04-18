#!/usr/bin/env python
# Copyright (C) 2013 Valve Corporation
# Copyright (C) 2018 Collabora Ltd.
#
# SPDX-License-Identifier: MIT
# (see COPYING)

from __future__ import print_function

import sys
from gzip import GzipFile

from debian.deb822 import Packages, Sources
from debian.debian_support import Version

try:
    import typing
    typing      # silence pyflakes
except ImportError:
    pass


class Source:
    def __init__(
        self,
        name,                           # type: str
        version,                        # type: Version
        stanza=None                     # type: typing.Optional[Sources]
    ):
        # type: (...) -> None
        self.name = name
        self.stanza = stanza
        self.version = version


class Binary:
    def __init__(
        self,
        stanza,                         # type: Packages
        binary_version_marker=None      # type: typing.Optional[str]
    ):  # type: (...) -> None
        self.stanza = stanza
        self.name = stanza['package']
        self.arch = stanza['architecture']
        self.multiarch = stanza.get('multi-arch', 'no')
        self.version = Version(stanza['version'])
        source = stanza.get('source', self.name)

        if ' (' in source:
            self.source, tmp = source.split(' (', 1)
            source_version = tmp.rstrip(')')
        else:
            self.source = source
            source_version = str(self.version)

        self.built_source_version = Version(source_version)
        self.source_version = self.built_source_version

        if (binary_version_marker is not None
                and binary_version_marker in source_version):
            left, right = source_version.rsplit(binary_version_marker, 1)
            self.source_version = Version(left)

    def __str__(self):
        return '{}_{}_{}'.format(self.name, self.version, self.arch)

    def __repr__(self):
        return '<{} {}>'.format(self.__class__.__name__, self)


class TapTest:
    def __init__(self):
        self.test_num = 0
        self.failed = False

    def ok(self, desc):
        self.test_num += 1
        print('ok %d - %s' % (self.test_num, desc))

    def diag(self, text):
        print('# %s' % text)

    def not_ok(self, desc):
        self.test_num += 1
        print('not ok %d - %s' % (self.test_num, desc))
        self.failed = True

    def done_testing(self):
        print('1..%d' % self.test_num)

        if self.failed:
            sys.exit(1)


if __name__ == '__main__':
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument(
        # Ignored for backwards compat
        '--packages-from', help=argparse.SUPPRESS,
    )
    parser.add_argument(
        'manifests', metavar='*.deb822.gz', nargs='*',
        help='Manifest files produced by build-runtime.py',
    )
    args = parser.parse_args()

    # Don't fail if invoked without arguments
    if not args.manifests:
        print('1..0 # SKIP No manifest files provided')
        sys.exit(0)

    test = TapTest()

    last = None

    runtime_package_lists = set()
    source_lists = set()
    sdk_package_lists = set()

    for f in args.manifests:
        assert f.endswith('.deb822.gz')

        if '-sdk-chroot-' in f:
            sdk_package_lists.add(f)

        elif (
            f.endswith('/sources.deb822.gz')
            or f.endswith('.sources.deb822.gz')
        ):
            source_lists.add(f)

        else:
            runtime_package_lists.add(f)

    sources = {}    # type: typing.Dict[str, typing.Dict[str, Version]]

    for f in source_lists:
        with GzipFile(f, 'rb') as gzip_reader:
            for source_stanza in Sources.iter_paragraphs(
                sequence=gzip_reader,
                encoding='utf-8',
            ):
                source = Source(
                    source_stanza['package'],
                    Version(source_stanza['version']),
                    stanza=source_stanza,
                )
                sources.setdefault(source.name, {})[source.version] = source

    for f in runtime_package_lists:
        test.diag('Examining runtime %s...' % f)
        with GzipFile(f, 'rb') as gzip_reader:
            for binary_stanza in Packages.iter_paragraphs(
                sequence=gzip_reader,
                encoding='utf-8',
            ):
                binary = Binary(binary_stanza, binary_version_marker='+srt')

                if (
                    binary.source not in sources
                    or binary.source_version not in sources[binary.source]
                ):
                    test.not_ok(
                        'source package %s_%s for %s not found'
                        % (binary.source, binary.source_version, binary.name)
                    )
                else:
                    test.ok(
                        '%s source package in Sources' % binary.name)

    test.done_testing()

# vi: set sw=4 sts=4 et:
