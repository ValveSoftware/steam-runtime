#!/bin/sh

# Get to the script directory
cd "$(dirname "$0")"

# Use root path
export PATH=/sbin:$PATH

# Use the C locale for simplicity
export LC_ALL="C"

# Use proxy environment
. /etc/environment; export http_proxy

# Upgrade environment
sudo apt-get -y update
sudo apt-get -y dist-upgrade

# Install additional packages
arch=`dpkg --print-architecture`
packages=`cat /packages/packages.txt | fgrep -v '#'` 2>/dev/null
if [ "$packages" ]; then
    # This is horrible, but we need to retry until we succeed here...
    while ! sudo apt-get -y install $packages; do
        echo "Retrying..."
        sleep 3
        sudo apt-get -y -f install
    done
fi

# Remove cached binary packages to save space
rm -f /var/cache/apt/archives/*.deb
rm -f /var/cache/apt/archives/partial/*
