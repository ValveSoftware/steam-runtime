#!/usr/bin/env python
#
# Script to build and install packages into the Steam runtime

from __future__ import print_function
import errno
import os
import re
import sys
import gzip
import shutil
import subprocess
import time
from debian import deb822
import argparse

try:
	from io import BytesIO
except ImportError:
	from cStringIO import StringIO as BytesIO

try:
	from urllib.request import (urlopen, urlretrieve)
except ImportError:
	from urllib import (urlopen, urlretrieve)

destdir="newpkg"
arches=["amd64", "i386"]

REPO="http://repo.steampowered.com/steamrt"
DIST="scout"
COMPONENT="main"

# The top level directory
top = sys.path[0]


def str2bool (b):
	return b.lower() in ("yes", "true", "t", "1")


def parse_args():
	parser = argparse.ArgumentParser()
	parser.add_argument(
		"--templates",
		help="specify template files to include in runtime",
		default=os.path.join(top, "templates"))
	parser.add_argument("-r", "--runtime", help="specify runtime path", default=os.path.join(top,"runtime"))
	parser.add_argument("--suite", help="specify apt suite", default=DIST)
	parser.add_argument("-b", "--beta", help="build beta runtime", dest='suite', action="store_const", const='scout_beta')
	parser.add_argument("-d", "--debug", help="build debug runtime", action="store_true")
	parser.add_argument("--source", help="include sources", action="store_true")
	parser.add_argument("--symbols", help="include debugging symbols", action="store_true")
	parser.add_argument("--repo", help="source repository", default=REPO)
	parser.add_argument("-v", "--verbose", help="verbose", action="store_true")
	parser.add_argument("--official", help="mark this as an official runtime", action="store_true")
	parser.add_argument("--set-name", help="set name for this runtime", default=None)
	parser.add_argument("--set-version", help="set version number for this runtime", default=None)
	parser.add_argument("--debug-url", help="set URL for debug/source version", default=None)
	parser.add_argument("--archive", help="pack Steam Runtime into a tarball", default=None)
	parser.add_argument(
		"--compression", help="set compression [xz|gx|bz2|none]",
		choices=('xz', 'gz', 'bz2', 'none'),
		default='xz')
	return parser.parse_args()


def download_file(file_url, file_path):
	try:
		if os.path.getsize(file_path) > 0:
			return False
	except OSError:
		pass

	urlretrieve(file_url, file_path)
	return True


def install_sources (sourcelist):
	#
	# Load the Sources file so we can find the location of each source package
	#
	sources_url = "%s/dists/%s/%s/source/Sources.gz" % (REPO, DIST, COMPONENT)
	print("Downloading sources from %s" % sources_url)
	sz = urlopen(sources_url)
	url_file_handle=BytesIO(sz.read())
	sources = gzip.GzipFile(fileobj=url_file_handle)

	skipped = 0
	unpacked = []
	manifest_lines = set()
	#
	# Walk through the Sources file and process any requested packages
	#
	for stanza in deb822.Sources.iter_paragraphs(sources):
		p = stanza['package']
		if p in sourcelist:
			if args.verbose:
				print("DOWNLOADING SOURCE: %s" % p)

			#
			# Create the destination directory if necessary
			#
			dir = os.path.join(top, destdir, "source", p)
			if not os.access(dir, os.W_OK):
				os.makedirs(dir)

			#
			# Download each file
			#
			for file in stanza['files']:
				file_path = os.path.join(dir, file['name'])
				file_url = "%s/%s/%s" % (REPO, stanza['directory'], file['name'])
				if not download_file(file_url, file_path):
					if args.verbose:
						print("Skipping download of existing deb source file(s): %s" % file_path)
					else:
						skipped += 1

			#
			# Unpack the source package into the runtime directory
			#
			dest_dir=os.path.join(args.runtime,"source",p)
			if os.access(dest_dir, os.W_OK):
				shutil.rmtree(dest_dir)
			os.makedirs(dest_dir)
			dsc_file = os.path.join(dir,stanza['files'][0]['name'])
			ver = stanza['files'][0]['name'].split('-')[0]
			process = subprocess.Popen(["dpkg-source", "-x", "--no-copy", dsc_file, os.path.join(dest_dir,ver)], stdout=subprocess.PIPE, universal_newlines=True)
			for line in iter(process.stdout.readline, ""):
				if args.verbose or re.match(r'dpkg-source: warning: ',line):
					print(line, end='')

			unpacked.append((p, stanza['Version'], stanza))
			manifest_lines.add(
				'%s\t%s\t%s\n' % (
					p, stanza['Version'],
					stanza['files'][0]['name']))

	# sources.txt: Tab-separated table of source packages, their
	# versions, and the corresponding .dsc file.
	with open(os.path.join(args.runtime, 'source', 'sources.txt'), 'w') as writer:
		writer.write('#Source\t#Version\t#dsc\n')

		for line in sorted(manifest_lines):
			writer.write(line)

	# sources.deb822.gz: The full Sources stanza for each included source
	# package, suitable for later analysis.
	with open(
		os.path.join(args.runtime, 'source', 'sources.deb822.gz'), 'wb'
	) as gz_writer:
		with gzip.GzipFile(
			filename='', fileobj=gz_writer, mtime=0
		) as stanza_writer:
			done_one = False

			for source in sorted(unpacked):
				if done_one:
					stanza_writer.write(b'\n')

				source[2].dump(stanza_writer)
				done_one = True

	if skipped > 0:
		print("Skipped downloading %i deb source file(s) that were already present." % skipped)


class Binary:
	def __init__(self, stanza):
		self.stanza = stanza
		self.name = stanza['Package']
		self.arch = stanza['Architecture']
		self.version = stanza['Version']
		source = stanza.get('Source', self.name)

		if ' (' in source:
			self.source, tmp = source.split(' (', 1)
			self.source_version = tmp.rstrip(')')
		else:
			self.source = source
			self.source_version = self.version


def install_binaries (binarylist, manifest):
	skipped = 0
	for arch in arches:
		installset = binarylist.copy()
		#
		# Create the destination directory if necessary
		#
		dir = os.path.join(top,destdir,"binary" if not args.debug else "debug", arch)
		if not os.access(dir, os.W_OK):
			os.makedirs(dir)

		#
		# Load the Packages file so we can find the location of each binary package
		#
		packages_url = "%s/dists/%s/%s/binary-%s/Packages" % (REPO, DIST, COMPONENT, arch)
		print("Downloading %s binaries from %s" % (arch, packages_url))
		url_file_handle = BytesIO(urlopen(packages_url).read())
		for stanza in deb822.Packages.iter_paragraphs(url_file_handle):
			p = stanza['Package']

			if p in installset:
				manifest.append(Binary(stanza))
				if args.verbose:
					print("DOWNLOADING BINARY: %s" % p)

				#
				# Download the package and install it
				#
				file_url="%s/%s" % (REPO,stanza['Filename'])
				dest_deb=os.path.join(dir, os.path.basename(stanza['Filename']))
				if not download_file(file_url, dest_deb):
					if args.verbose:
						print("Skipping download of existing deb: %s", dest_deb)
					else:
						skipped += 1
				install_deb(os.path.splitext(os.path.basename(stanza['Filename']))[0], dest_deb, os.path.join(args.runtime, arch))
				installset.remove(p)

		for p in installset:
			#
			# There was a binary package in the list to be installed that is not in the repo
			#
			e = "ERROR: Package %s not found in Packages file %s\n" % (p, packages_url)
			sys.stderr.write(e)

	if skipped > 0:
		print("Skipped downloading %i file(s) that were already present." % skipped)


def install_deb (basename, deb, dest_dir):
	installtag_dir=os.path.join(dest_dir, "installed")
	if not os.access(installtag_dir, os.W_OK):
		os.makedirs(installtag_dir)

	#
	# Write the tag file and checksum to the 'installed' subdirectory
	#
	with open(os.path.join(installtag_dir, basename), "w") as f:
		subprocess.check_call(['dpkg-deb', '-c', deb], stdout=f)
	with open(os.path.join(installtag_dir, basename + ".md5"), "w") as f:
		os.chdir(os.path.dirname(deb))
		subprocess.check_call(['md5sum', os.path.basename(deb)], stdout=f)

	#
	# Unpack the package into the dest_dir
	#
	os.chdir(top)
	subprocess.check_call(['dpkg-deb', '-x', deb, dest_dir])


def install_symbols (binarylist, manifest):
	skipped = 0
	for arch in arches:

		#
		# Create the destination directory if necessary
		#
		dir = os.path.join(top,destdir, "symbols", arch)
		if not os.access(dir, os.W_OK):
			os.makedirs(dir)

		#
		# Load the Packages file to find the location of each symbol package
		#
		packages_url = "%s/dists/%s/%s/debug/binary-%s/Packages" % (REPO, DIST, COMPONENT, arch)
		print("Downloading %s symbols from %s" % (arch, packages_url))
		url_file_handle = BytesIO(urlopen(packages_url).read())
		for stanza in deb822.Packages.iter_paragraphs(url_file_handle):
			p = stanza['Package']
			m = re.match(r'([\w\-\.]+)\-dbgsym', p)
			if m and m.group(1) in binarylist:
				manifest.append(Binary(stanza))
				if args.verbose:
					print("DOWNLOADING SYMBOLS: %s" % p)
				#
				# Download the package and install it
				#
				file_url="%s/%s" % (REPO,stanza['Filename'])
				dest_deb=os.path.join(dir, os.path.basename(stanza['Filename']))
				if not download_file(file_url, dest_deb):
					if args.verbose:
						print("Skipping download of existing symbol deb: %s", dest_deb)
					else:
						skipped += 1
				install_deb(os.path.splitext(os.path.basename(stanza['Filename']))[0], dest_deb, os.path.join(args.runtime, arch))

	if skipped > 0:
		print("Skipped downloading %i symbol deb(s) that were already present." % skipped)


# Walks through the files in the runtime directory and converts any absolute symlinks
# to their relative equivalent
#
def fix_symlinks ():
	for arch in arches:
		for dir, subdirs, files in os.walk(os.path.join(args.runtime,arch)):
			for name in files:
				filepath=os.path.join(dir,name)
				if os.path.islink(filepath):
					target = os.readlink(filepath)
					if os.path.isabs(target):
						#
						# compute the target of the symlink based on the 'root' of the architecture's runtime
						#
						target2 = os.path.join(args.runtime,arch,target[1:])

						#
						# Set the new relative target path
						#
						os.unlink(filepath)
						os.symlink(os.path.relpath(target2,dir), filepath)


# Creates the usr/lib/debug/.build-id/xx/xxxxxxxxx.debug symlink tree for all the debug
# symbols
#
def fix_debuglinks ():
	for arch in arches:
		for dir, subdirs, files in os.walk(os.path.join(args.runtime,arch,"usr/lib/debug")):
			if ".build-id" in subdirs:
				subdirs.remove(".build-id")		# don't recurse into .build-id directory we are creating

			for file in files:

				#
				# scrape the output of readelf to find the buildid for this binary
				#
				p = subprocess.Popen(["readelf", '-n', os.path.join(dir,file)], stdout=subprocess.PIPE, universal_newlines=True)
				for line in iter(p.stdout.readline, ""):
					m = re.search(r'Build ID: (\w{2})(\w+)',line)
					if m:
						linkdir = os.path.join(args.runtime,arch,"usr/lib/debug/.build-id",m.group(1))
						if not os.access(linkdir, os.W_OK):
							os.makedirs(linkdir)
						link = os.path.join(linkdir,m.group(2))
						if args.verbose:
							print("SYMLINKING symbol file %s to %s" % (link, os.path.relpath(os.path.join(dir,file),linkdir)))
						if os.path.lexists(link):
							os.unlink(link)
						os.symlink(os.path.relpath(os.path.join(dir,file), linkdir),link)


def write_manifests(manifest):
	done = set()

	# manifest.deb822: The full Packages stanza for each installed package,
	# suitable for later analysis.
	with open(os.path.join(args.runtime, 'manifest.deb822.gz'), 'wb') as out:
		with gzip.GzipFile(filename='', fileobj=out, mtime=0) as writer:
			for binary in sorted(manifest, key=lambda b: b.name + ':' + b.arch):
				key = (binary.name, binary.arch)

				if key in done:
					continue

				if done:
					writer.write(b'\n')

				binary.stanza.dump(writer)
				done.add(key)

	# manifest.txt: A summary of installed binary packages, as
	# a table of tab-separated values.
	lines = set()

	for binary in manifest:
		lines.add('%s:%s\t%s\t%s\t%s\n' % (binary.name, binary.arch, binary.version, binary.stanza.get('Source', binary.name), binary.stanza.get('Installed-Size', '')))

	with open(os.path.join(args.runtime, 'manifest.txt'), 'w') as writer:
		writer.write('#Package[:Architecture]\t#Version\t#Source\t#Installed-Size\n')

		for line in sorted(lines):
			writer.write(line)

	# built-using.txt: A summary of source packages that were embedded in
	# installed binary packages, as a table of tab-separated values.
	lines = set()

	for binary in manifest:
		built_using = binary.stanza.get('Built-Using', '')

		if not built_using:
			continue

		relations = built_using.split(',')

		for relation in relations:
			relation = relation.replace(' ', '')
			assert '(=' in relation, relation
			p, v = relation.split('(=', 1)
			assert v[-1] == ')', relation
			v = v[:-1]
			lines.add('%s\t%s\t%s\n' % (binary.name, p, v))

	with open(os.path.join(args.runtime, 'built-using.txt'), 'w') as writer:
		writer.write('#Built-Binary\t#Built-Using-Source\t#Built-Using-Version\n')

		for line in sorted(lines):
			writer.write(line)


# Create files u=rwX,go=rX by default
os.umask(0o022)

args = parse_args()
if args.verbose:
	for property, value in sorted(vars(args).items()):
		print("\t", property, ": ", value)

REPO=args.repo
DIST = args.suite

if args.debug:
	COMPONENT = "debug"

if args.set_name is not None:
	name = args.set_name
else:
	name = 'steam-runtime'

	if not args.official:
		name = 'unofficial-' + name

	if DIST == 'scout_beta':
		name = '%s-beta' % name
	elif DIST != 'scout':
		name = '%s-%s' % DIST

	if args.symbols:
		name += '-sym'

	if args.source:
		name += '-src'

	if args.debug:
		name += '-debug'
	else:
		name += '-release'

if args.set_version is not None:
	version = args.set_version
else:
	version = time.strftime('snapshot-%Y%m%d-%H%M%SZ', time.gmtime())

name_version = '%s_%s' % (name, version)

# Populate runtime from template if necessary
if not os.path.exists(args.runtime):
	shutil.copytree(args.templates, args.runtime, symlinks=True)

with open(os.path.join(args.runtime, 'version.txt'), 'w') as writer:
	writer.write('%s\n' % name_version)

if args.debug_url:
	# Note where people can get the debug version of this runtime
	with open(
		os.path.join(args.templates, 'README.txt')
	) as reader:
		with open(
			os.path.join(args.runtime, 'README.txt.new'), 'w'
		) as writer:
			for line in reader:
				line = re.sub(
					r'https?://media\.steampowered\.com/client/runtime/.*$',
					args.debug_url, line)
				writer.write(line)

	os.rename(
		os.path.join(args.runtime, 'README.txt.new'),
		os.path.join(args.runtime, 'README.txt'))

# Process packages.txt to get the list of source and binary packages
source_pkgs = set()
binary_pkgs = set()

print("Creating Steam Runtime in %s" % args.runtime)

with open("packages.txt") as f:
	for line in f:
		if line[0] != '#':
			toks = line.split()
			if len(toks) > 1:
				source_pkgs.add(toks[0])
				binary_pkgs.update(toks[1:])

# remove development packages for end-user runtime
if not args.debug:
	binary_pkgs -= {x for x in binary_pkgs if re.search('-dbg$|-dev$|-multidev$',x)}

if args.source:
	install_sources(source_pkgs)

manifest = []
install_binaries(binary_pkgs, manifest)

if args.symbols:
	install_symbols(binary_pkgs, manifest)
	fix_debuglinks()

fix_symlinks()

write_manifests(manifest)

print("Normalizing permissions...")
subprocess.check_call([
	'chmod', '--changes', 'u=rwX,go=rX', '--', args.runtime,
])

if args.archive is not None:
	if args.archive.endswith('/'):
		try:
			os.makedirs(args.archive, 0o755)
		except OSError as e:
			if e.errno != errno.EEXIST:
				raise

	if args.compression == 'none':
		ext = '.tar'
	else:
		ext = '.tar.' + args.compression

	if os.path.isdir(args.archive):
		archive = os.path.join(args.archive, name_version + ext)
		archive_dir = args.archive
	else:
		archive = args.archive
		archive_dir = None

	print("Creating archive %s..." % archive)
	subprocess.check_call([
		'tar',
		'cvf', archive,
		'--auto-compress',
		'--owner=nobody:65534',
		'--group=nogroup:65534',
		'-C', args.runtime,
		# Transform regular archive members, but not symlinks
		'--transform', 's,^[.]/,steam-runtime/,S',
		'--show-transformed',
		'.'
	])

	print("Creating archive checksum %s.checksum..." % archive)
	with open(archive + '.checksum', 'w') as writer:
		subprocess.check_call(
			[
				'md5sum',
				os.path.basename(archive),
			],
			cwd=os.path.dirname(archive),
			stdout=writer,
		)

	if archive_dir is not None:
		print("Copying manifest files to %s..." % archive_dir)
		shutil.copy(
			os.path.join(args.runtime, 'manifest.txt'),
			os.path.join(
				archive_dir, name_version + '.manifest.txt'),
		)
		shutil.copy(
			os.path.join(args.runtime, 'built-using.txt'),
			os.path.join(
				archive_dir, name_version + '.built-using.txt'),
		)
		shutil.copy(
			os.path.join(args.runtime, 'manifest.deb822.gz'),
			os.path.join(
				archive_dir,
				name_version + '.manifest.deb822.gz'),
		)
		if args.source:
			shutil.copy(
				os.path.join(
					args.runtime,
					'source',
					'sources.txt'),
				os.path.join(
					archive_dir,
					name_version + '.sources.txt'),
			)
			shutil.copy(
				os.path.join(
					args.runtime,
					'source',
					'sources.deb822.gz'),
				os.path.join(
					archive_dir,
					name_version + '.sources.deb822.gz'),
			)

	if archive_dir is not None and version != 'latest':
		print("Creating symlink %s_latest%s..." % (name, ext))
		symlink = os.path.join(archive_dir, name + '_latest' + ext)

		try:
			os.remove(symlink)
		except OSError as e:
			if e.errno != errno.ENOENT:
				raise

		try:
			os.remove(symlink + '.checksum')
		except OSError as e:
			if e.errno != errno.ENOENT:
				raise

		os.symlink(os.path.basename(archive), symlink)
		os.symlink(
			os.path.basename(archive) + '.checksum',
			symlink + '.checksum')

# vi: set noexpandtab:
