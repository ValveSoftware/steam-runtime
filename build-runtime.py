#!/usr/bin/env python
#
# Script to build and install packages into the Steam runtime

import os
import re
import sys
import urllib
import gzip
import cStringIO
import shutil
import subprocess
from debian import deb822
import argparse

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
	parser.add_argument("-r", "--runtime", help="specify runtime path", default=os.path.join(top,"runtime"))
	parser.add_argument("-b", "--beta", help="build beta runtime", action="store_true")
	parser.add_argument("-d", "--debug", help="build debug runtime", action="store_true")
	parser.add_argument("--source", help="include sources", action="store_true")
	parser.add_argument("--symbols", help="include debugging symbols", action="store_true")
	parser.add_argument("--repo", help="source repository", default=REPO)
	parser.add_argument("-v", "--verbose", help="verbose", action="store_true")
	return parser.parse_args()

def download_file(file_url, file_path):
	try:
		if os.path.getsize(file_path) > 0:
			return False
	except:
		pass

	urllib.urlretrieve(file_url, file_path)
	return True

def install_sources (sourcelist):
	#
	# Load the Sources file so we can find the location of each source package
	#
	sources_url = "%s/dists/%s/%s/source/Sources.gz" % (REPO, DIST, COMPONENT)
	print("Downloading sources from %s" % sources_url)
	sz = urllib.urlopen(sources_url)
	url_file_handle=cStringIO.StringIO( sz.read() )
	sources = gzip.GzipFile(fileobj=url_file_handle);

	skipped = 0
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
						print("Skipping download of existing deb source file(s): %s", file_path)
					else:
						skipped += 1

			#
			# Unpack the source package into the runtime directory
			#
			dest_dir=os.path.join(args.runtime,"source",p)
			if os.access(dest_dir, os.W_OK):
				shutil.rmtree(dest_dir);
			os.makedirs(dest_dir);
			dsc_file = os.path.join(dir,stanza['files'][0]['name'])
			ver = stanza['files'][0]['name'].split('-')[0]
			p = subprocess.Popen(["dpkg-source", "-x", "--no-copy", dsc_file, os.path.join(dest_dir,ver)], stdout=subprocess.PIPE)
			for line in iter(p.stdout.readline, ""):
				if args.verbose or re.match('dpkg-source: warning: ',line):
					print line,

	if skipped > 0:
		print("Skipped downloading %i deb source file(s) that were already present." % skipped)



def install_binaries (binarylist):
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
		for stanza in deb822.Packages.iter_paragraphs(urllib.urlopen(packages_url)):
			p = stanza['Package']
			if p in installset:
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
	with open(os.path.join(installtag_dir,basename),"w") as f:
		subprocess.check_call(['dpkg-deb', '-c', deb], stdout=f)
	with open(os.path.join(installtag_dir,basename+".md5"),"w") as f:
		os.chdir(os.path.dirname(deb))
		subprocess.check_call(['md5sum', os.path.basename(deb)], stdout=f)

	#
	# Unpack the package into the dest_dir
	#
	os.chdir(top)
	subprocess.check_call(['dpkg-deb', '-x', deb, dest_dir])


def install_symbols (binarylist):
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
		for stanza in deb822.Packages.iter_paragraphs(urllib.urlopen(packages_url)):
			p = stanza['Package']
			m = re.match('([\w\-\.]+)\-dbgsym', p)
			if m and m.group(1) in binarylist:
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

#
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

#
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
				p = subprocess.Popen(["readelf", '-n', os.path.join(dir,file)], stdout=subprocess.PIPE)
				for line in iter(p.stdout.readline, ""):
					m = re.search('Build ID: (\w{2})(\w+)',line)
					if m:
						linkdir = os.path.join(args.runtime,arch,"usr/lib/debug/.build-id",m.group(1))
						if not os.access(linkdir, os.W_OK):
							os.makedirs(linkdir)
						link = os.path.join(linkdir,m.group(2))
						if args.verbose:
							print "SYMLINKING symbol file %s to %s" % (link, os.path.relpath(os.path.join(dir,file),linkdir))
						if os.path.lexists(link):
							os.unlink(link)
						os.symlink(os.path.relpath(os.path.join(dir,file), linkdir),link)


args = parse_args()
if args.verbose:
	for property, value in vars(args).iteritems():
		print "\t", property, ": ", value


REPO=args.repo

if args.beta:
	DIST="scout_beta"

if args.debug:
	COMPONENT = "debug"

# Process packages.txt to get the list of source and binary packages
source_pkgs = set()
binary_pkgs = set()

print ("Creating Steam Runtime in %s" % args.runtime)

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

install_binaries(binary_pkgs)

if args.symbols:
	install_symbols(binary_pkgs)
	fix_debuglinks()

fix_symlinks()

# vi: set noexpandtab:
