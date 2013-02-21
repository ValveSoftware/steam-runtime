#!/bin/bash

CROSSTOOL_REVISION="crosstool-ng-1.17.0"

set -e

echo -n \
"This will take a long time, do you want to continue? [Y/n]: "
read answer
if [ "$answer" = "n" ]; then
    exit 1
fi

TOP=$(cd "${0%/*}" && echo $PWD)
cd "${TOP}/crosstool" || exit 1

if [ ! -d crosstool-ng -o "$(command -v ct-ng)" = "" ] ; then
    echo "Setting up crosstool-ng..."
    sudo apt-get install autoconf bison flex gcc g++ gperf gawk libtool texinfo libncurses5-dev subversion mercurial wget
    if [ ! -d crosstool-ng ]; then
        hg clone -u $CROSSTOOL_REVISION http://crosstool-ng.org/hg/crosstool-ng || exit 2
    fi
    if [ "$(command -v ct-ng)" = "" ] ; then
        cd crosstool-ng
        (./bootstrap && ./configure && make && sudo make install) || exit 2
        cd ..
    fi
fi

for arch in i386 amd64 ; do
    echo "Building cross compiler for $arch ..."
    cd $arch
    ct-ng build || exit 2
    cd ..
    echo "complete"
done

HOST_ARCH=$(dpkg --print-architecture)
cd "${TOP}/x-tools" || exit 3
chmod u+w -R *
mkdir -p "${HOST_ARCH}"
mv -v *-unknown-linux-gnu "${HOST_ARCH}"

echo "Done. Your compilers are in ${TOP}/x-tools/${HOST_ARCH}"

# vi: ts=4 sw=4 expandtab
