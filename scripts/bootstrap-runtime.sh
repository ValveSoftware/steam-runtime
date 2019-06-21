#!/bin/bash

COLOR_OFF='\033[0m'
COLOR_ON='\033[1;93m'

set -eu

steamrt_mirror="http://repo.steampowered.com/steamrt"
ubuntu_mirror="http://us.archive.ubuntu.com/ubuntu"
extra_apt_sources=()

# bootstrap_container <docker | chroot> suite
bootstrap_container()
{
  local container_type="$1"
  local suite="$2"

  #  Need to be inside a chroot
  if [[ $container_type = chroot && $(stat -c %d:%i /) != $(stat -c %d:%i /proc/1/root/.) ]]; then
    echo "Running in chroot environment. Continuing..."
  elif [[ $container_type = chroot && "${container-}" = systemd-nspawn ]]; then
    echo "Running in systemd-nspawn environment. Continuing..."
  elif [[ $container_type = docker && -f /.dockerenv ]]; then
    echo "Running in docker environment. Continuing..."
  else
    echo "Script must be running in a chroot environment. Exiting..."
    exit 1
  fi

  # Load proxy settings, if any
  if [ -f /etc/profile.d/steamrtproj.sh ]; then
    # Read in our envar proxy settings (needed for wget).
    # This is a file inside the container so we can't follow the 'source'
    # for shellcheck:
    # shellcheck disable=SC1091
    source /etc/profile.d/steamrtproj.sh
  fi

  # Setup apt sources
  export DEBIAN_FRONTEND=noninteractive

  #
  # Ubuntu repos if coming from a chroot
  #
  if [[ $container_type = chroot ]]; then
    (cat << heredoc
deb ${ubuntu_mirror} precise main
deb-src ${ubuntu_mirror} precise main
deb ${ubuntu_mirror} precise universe
deb-src ${ubuntu_mirror} precise universe
heredoc
) > /etc/apt/sources.list
  fi

  if ! [ -e /etc/apt/sources.list.d/steamrt.list ]; then
    (cat << heredoc
deb ${steamrt_mirror} ${suite} main
deb-src ${steamrt_mirror} ${suite} main
heredoc
) > /etc/apt/sources.list.d/steamrt.list
  fi

  if [ -n "${extra_apt_sources+set}" ]; then
    for line in "${extra_apt_sources[@]}"; do
      printf '%s\n' "$line"
    done > /etc/apt/sources.list.d/steamrt-extra.list
  fi

  #
  # Install Valve apt repository key
  #
  (cat << heredoc
-----BEGIN PGP PUBLIC KEY BLOCK-----
Version: GnuPG v1.4.11 (GNU/Linux)

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
QpBI5Fwn13V3OM4=
=uSQO
-----END PGP PUBLIC KEY BLOCK-----
heredoc
) | apt-key add -

  if [[ $container_type = chroot ]]; then
    # Before installing any additional packages, neuter upstart.
    # this is done at the docker level for non-chroot setups.
    echo '#!/bin/sh' > /usr/sbin/policy-rc.d
    echo 'exit 101' >> /usr/sbin/policy-rc.d
    chmod +x /usr/sbin/policy-rc.d
    dpkg-divert --local --rename --add /sbin/initctl
    cp -a /usr/sbin/policy-rc.d /sbin/initctl
    sed -i 's/^exit.*/exit 0/' /sbin/initctl
  fi

  # All repos and keys added; update
  apt-get -y update
  apt-get dist-upgrade --force-yes -y

  #
  #  Install compilers and libraries
  #

  apt-get install --force-yes -y install-info
  apt-get install --force-yes -y ubuntu-minimal pkg-config time wget
  apt-get install --force-yes -y build-essential cmake gdb

  apt-get install --force-yes -y steamrt-dev
  apt-get install --force-yes -y gcc-4.8 g++-4.8
  apt-get install --force-yes -y clang-3.4 lldb-3.4
  apt-get install --force-yes -y clang-3.6 lldb-3.6

  # Workaround bug 714890 in 32-bit clang. Gcc 4.8 changed the include paths.
  # http://bugs.debian.org/cgi-bin/bugreport.cgi?bug=714890
  #   /usr/include/c++/4.6/i686-linux-gnu/bits/c++config.h
  #   /usr/include/i386-linux-gnu/c++/4.8/bits/c++config.h
  if [ -d /usr/include/i386-linux-gnu/c++/4.8 ]; then
    ln -s /usr/include/i386-linux-gnu/c++/4.8 /usr/include/c++/4.8/i686-linux-gnu
  fi

  # Setup compiler alternatives
  update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-4.6 50
  update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-4.6 50
  update-alternatives --install /usr/bin/cpp cpp-bin /usr/bin/cpp-4.6 50

  update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-4.8 100
  update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-4.8 100
  update-alternatives --install /usr/bin/cpp cpp-bin /usr/bin/cpp-4.8 100

  if [ -x /usr/bin/g++-5 ]; then
    update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-5 50
    update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-5 50
    update-alternatives --install /usr/bin/cpp cpp-bin /usr/bin/cpp-5 50
  fi

  update-alternatives --install /usr/bin/gcc gcc /usr/bin/clang-3.4 50
  update-alternatives --install /usr/bin/g++ g++ /usr/bin/clang++-3.4 50

  update-alternatives --install /usr/bin/gcc gcc /usr/bin/clang-3.6 50
  update-alternatives --install /usr/bin/g++ g++ /usr/bin/clang++-3.6 50

  if [ -x /usr/bin/clang++-3.8 ]; then
    update-alternatives --install /usr/bin/gcc gcc /usr/bin/clang-3.8 50
    update-alternatives --install /usr/bin/g++ g++ /usr/bin/clang++-3.8 50
  fi

  # gcc-4.8 is the default
  update-alternatives --set gcc /usr/bin/gcc-4.8
  update-alternatives --set g++ /usr/bin/g++-4.8
  update-alternatives --set cpp-bin /usr/bin/cpp-4.8

  # Allow members of sudo group sudo to run in runtime without password prompt
  echo -e "\\n${COLOR_ON}Allow members of sudo group to run sudo in runtime without prompting for password...${COLOR_OFF}"
  echo -e "# Allow members of group sudo to execute any command\\n%sudo   ALL= NOPASSWD: ALL\\n" > /etc/sudoers.d/nopassword
  chmod 440 /etc/sudoers.d/nopassword

  # Remove downloaded packages: we won't need to install them again
  apt-get clean

  echo ""
  echo "#####"
  echo "##### Runtime setup is done!"
  echo "#####"
  echo ""
}

usage ()
{
  if [ "$1" -ne 0 ]; then
    exec >&2
  fi

  echo "!! Usage: ./bootstrap-runtime.sh { --docker | --chroot } [ --ubuntu-mirror MIRROR ] [ --steamrt-mirror MIRROR ] [ --beta | --suite SUITE ] [--extra-apt-source 'deb http://MIRROR SUITE COMPONENT...']"
  echo "!!"
  echo "!! This script to be run in a base container/chroot to finish Steam runtime setup"
  exit "$1"
}

#
# Parse arguments & run
#
mode_arg=""
suite="scout"
invalid_arg=""

getopt_temp="$(getopt -o '' --long \
  'beta,chroot,docker,extra-apt-source:,help,steamrt-mirror:,suite:,ubuntu-mirror:' \
  -n "$0" -- "$@")"
eval set -- "$getopt_temp"
unset getopt_temp

while [[ $# -gt 0 ]]; do
  case "$1" in
    "--docker" )
      [[ -z $mode_arg ]] || invalid_arg=1
      mode_arg=docker
      ;;
    "--chroot" )
      [[ -z $mode_arg ]] || invalid_arg=1
      mode_arg=chroot
      ;;
    "--beta" )
      suite=scout_beta
      ;;
    "--suite" )
      suite="$2"
      shift 2
      continue
      ;;
    "--ubuntu-mirror" )
      ubuntu_mirror="$2"
      shift 2
      continue
      ;;
    "--steamrt-mirror" )
      steamrt_mirror="$2"
      shift 2
      continue
      ;;
    "--extra-apt-source" )
      extra_apt_sources+=("$2")
      shift 2
      continue
      ;;
    "--help" )
      usage 0
      ;;
    "--" )
      # getopt adds this as a separator before any positional arguments
      shift
      break
      ;;
    * )
      echo >&2 "!! Unrecognized argument: $1"
      invalid_arg=1
      ;;
  esac
  shift
done

if [[ $# -gt 0 ]]; then
  echo >&2 "!! Unrecognized argument: $1"
  invalid_arg=1
fi

if [[ -z $invalid_arg && -n $mode_arg && $EUID = 0 ]]; then
  bootstrap_container "$mode_arg" "$suite"
else
  usage 1
fi
