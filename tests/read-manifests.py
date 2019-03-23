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
        '--packages-from', metavar='.../packages.txt',
        help=('Assume build-runtime.py was told to include packages '
              'listed in the given file'),
        action='append', default=[],
    )
    parser.add_argument(
        'manifests', metavar='*.deb822.gz', nargs='*',
        help='Manifest files produced by build-runtime.py',
    )
    args = parser.parse_args()

    if not args.packages_from:
        args.packages_from = ['packages.txt']

    # Don't fail if invoked without arguments
    if not args.manifests:
        print('1..0 # SKIP No manifest files provided')
        sys.exit(0)

    test = TapTest()

    source_pkgs = set()
    binary_pkgs = set()
    packages_txt_binary_sources = {}

    for packages_from in args.packages_from:
        with open(packages_from) as reader:
            for line in reader:
                if line[0] != '#':
                    toks = line.split()
                    if len(toks) > 1:
                        source_pkgs.add(toks[0])
                        binary_pkgs.update(toks[1:])

                        for p in toks[1:]:
                            packages_txt_binary_sources[p] = toks[0]
                            # Automatic dbgsym packages are also OK
                            packages_txt_binary_sources[
                                p + '-dbgsym'
                            ] = toks[0]

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

                if binary.source == 'steamrt':
                    # Ignore steamrt metapackage
                    pass
                elif binary.name not in packages_txt_binary_sources:
                    test.not_ok(
                        'Runtime %s contains %s, not listed in packages.txt'
                        % (f, binary.name))
                elif packages_txt_binary_sources[binary.name] != binary.source:
                    test.not_ok(
                        'packages.txt thinks %s is built by source %s, '
                        'but %s_%s_%s was built by %s_%s'
                        % (
                            binary.name,
                            packages_txt_binary_sources[binary.name],
                            binary.name, binary.version, binary.arch,
                            binary.source, binary.source_version))
                else:
                    test.ok('%s in packages.txt' % binary.name)

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
