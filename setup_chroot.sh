#!/bin/bash

SCRIPT=$(readlink -f "$0")
SCRIPTNAME=$(basename "$SCRIPT")
LOGFILE=/tmp/${SCRIPTNAME%.*}-$(uname -i).log
CHROOT_PREFIX="steamrt_scout_"
CHROOT_DIR="/var/chroots"
INSTALL_FORCE=false
BETA_ARG=""
COLOR_OFF="\033[0m"
COLOR_ON="\033[1;93m"
COLOR_ERROR_ON="\033[0;31m"

# exit on any script line that fails
set -o errexit
# bail on any unitialized variable reads
set -o nounset

prebuild_chroot()
{
	# install some packages
	echo -e "\n${COLOR_ON}Installing debootstrap schroot...${COLOR_OFF}"
	sudo -E apt-get install -y debootstrap schroot

	# Check if there are any active schroot sessions right now and warn if so...
	schroot_list=$(schroot --list --all-sessions | head -n 1)
	if [ $schroot_list ]; then
		echo -e "\n${COLOR_ERROR_ON}WARNING: Schroot says you have a currently active session!${COLOR_OFF}\n"
		echo "  ${schroot_list}"
		echo ""
		if [[ $- == *i* ]]; then
			read -p "Are you sure you want to continue (y/n)? "
			if [[ "$REPLY" != [Yy] ]]; then
				echo -e "Cancelled...\n"
				exit 1
			fi
		else
			>&2 echo -e "${COLOR_ERROR_ON}ERROR: Cannot continue...${COLOR_OFF}"
			exit 1
		fi
	fi

	STEAM_RUNTIME_SPEW_WARNING=
	for var in "$@"; do
		dirname="${CHROOT_DIR}/${CHROOT_PREFIX}${var/--/}"
		if [ -d "${dirname}" ]; then
			STEAM_RUNTIME_SPEW_WARNING=1
			echo -e "${COLOR_ERROR_ON}About to remove ${dirname} and re-install...${COLOR_OFF}"
		fi
	done

	if [[ "$STEAM_RUNTIME_SPEW_WARNING" == "1" ]]; then
		if [[ $- == *i* ]]; then
			read -p "  This ok (y/n)? "
			if [[ "$REPLY" != [Yy] ]]; then
				echo -e "Cancelled...\n"
				exit 1
			fi
		elif [[ "$INSTALL_FORCE" == false ]]; then
			>&2 echo -e "${COLOR_ERROR_ON}ERROR: Please use --force if this is intentional${COLOR_OFF}"
			exit 1
		fi
	fi
}

build_chroot()
{
	case "$1" in
		"--i386" )
			pkg="i386"
			personality="linux32"
			;;
		"--amd64" )
			pkg="amd64"
			personality="linux"
			;;
		* )
			echo "Error: Unrecognized argument: $1"
			exit 1
			;;
	esac

	CHROOT_NAME=${CHROOT_PREFIX}${pkg}

	# blow away existing directories and recreate empty ones
	echo -e "\n${COLOR_ON}Creating ${CHROOT_DIR}/${CHROOT_NAME}..."  
	sudo rm -rf "${CHROOT_DIR}/${CHROOT_NAME}"
	sudo mkdir -p "${CHROOT_DIR}/${CHROOT_NAME}"

	# Create our schroot .conf file
	echo -e "\n${COLOR_ON}Creating /etc/schroot/chroot.d/${CHROOT_NAME}.conf...${COLOR_OFF}" 
	printf "[${CHROOT_NAME}]\ndescription=Ubuntu 12.04 Precise for ${pkg}\ndirectory=${CHROOT_DIR}/${CHROOT_NAME}\npersonality=${personality}\ngroups=sudo\nroot-groups=sudo\npreserve-environment=true\ntype=directory\n" | sudo tee /etc/schroot/chroot.d/${CHROOT_NAME}.conf

	# Get the Ubuntu GPG key for Precise packages
	PRECISE_KEYRING=/tmp/ubuntu-precise-keyring.gpg
	gpg --keyring=${PRECISE_KEYRING} --no-default-keyring --keyserver keyserver.ubuntu.com --receive-keys 0x40976EAF437D05B5

	# Create our chroot
	echo -e "\n${COLOR_ON}Bootstrap the chroot...${COLOR_OFF}" 
	sudo -E debootstrap --keyring=${PRECISE_KEYRING} --arch=${pkg} --include=wget precise ${CHROOT_DIR}/${CHROOT_NAME} http://archive.ubuntu.com/ubuntu/

	# Copy over proxy settings from host machine
	echo -e "\n${COLOR_ON}Adding proxy info to chroot (if set)...${COLOR_OFF}" 
	env | grep -i "_proxy=" | grep -v PERSISTENT_HISTORY_LAST | xargs -i echo export {} | sudo tee ${CHROOT_DIR}/${CHROOT_NAME}/etc/profile.d/steamrtproj.sh
	env | grep -i "_proxy=" | grep -v PERSISTENT_HISTORY_LAST | xargs -i echo export {} | sudo tee -a ${CHROOT_DIR}/${CHROOT_NAME}/etc/environment
	sudo rm -rf "${CHROOT_DIR}/${CHROOT_NAME}/etc/apt/apt.conf"
	if [ -f /etc/apt/apt.conf ]; then sudo cp "/etc/apt/apt.conf" "${CHROOT_DIR}/${CHROOT_NAME}/etc/apt"; fi  

	echo -e "\n${COLOR_ON}Running ${SCRIPTNAME} ${BETA_ARG} --configure...${COLOR_OFF}" 

	# Touch the logfile first so it has the proper permissions
	rm -f "${LOGFILE}"
	touch "${LOGFILE}"

	# The chroot has access to /tmp so copy the script there and run it with --configure
	TMPNAME="${SCRIPTNAME%.*}-$$.sh"
	cp -f "$0" "/tmp/${TMPNAME}"
	chmod +x "/tmp/${TMPNAME}"
	schroot --chroot ${CHROOT_NAME} -d /tmp --user root -- "/tmp/${TMPNAME}" ${BETA_ARG} --configure
	rm -f "/tmp/${TMPNAME}"
	cp -f "$SCRIPT_DIR/write-manifest" "/tmp/${TMPNAME}"
	chmod +x "/tmp/${TMPNAME}"
	schroot --chroot ${CHROOT_NAME} -d /tmp --user root -- "/tmp/${TMPNAME}" /
	rm -f "/tmp/${TMPNAME}"
}

configure_chroot()
{
	# Need to run as root
	if [ $EUID -eq 0 ]; then
		echo "Running as root, continuing..."
	else
		echo "Script must be running as root. Exiting..."
		exit
	fi

	#  Need to be inside a chroot
	if [ "$(stat -c %d:%i /)" != "$(stat -c %d:%i /proc/1/root/.)" ]; then
		echo "Running in chroot environment. Continuing..."
	else
		echo "Script must be running in a chroot environment. Exiting..."
		exit
	fi

	# Launch ourselves with script so we can time this and get a log file
	if [[ ! -v IN_CHROOT_CONFIGURE ]]; then
		export IN_CHROOT_CONFIGURE=1
        export SHELL=/bin/bash
		script --return --command "time $SCRIPT ${BETA_ARG} --configure" "${LOGFILE}"
		exit $?
	fi

	# Allow members of sudo group sudo to run in chroot without password prompt
	echo -e "\n${COLOR_ON}Allow members of sudo group to run sudo in chroot without prompting for password...${COLOR_OFF}" 
	echo -e "# Allow members of group sudo to execute any command\n%sudo   ALL= NOPASSWD: ALL\n" > /etc/sudoers.d/nopassword
	chmod 440 /etc/sudoers.d/nopassword

	# Load proxy settings, if any
	if [ -f /etc/profile.d/steamrtproj.sh ]; then
		# Read in our envar proxy settings (needed for wget).
		source /etc/profile.d/steamrtproj.sh
	fi

	# Setup apt sources
	export DEBIAN_FRONTEND=noninteractive

	#
	# Ubuntu repos
	#
	(cat << heredoc
deb http://us.archive.ubuntu.com/ubuntu precise main
deb-src http://us.archive.ubuntu.com/ubuntu precise main
deb http://us.archive.ubuntu.com/ubuntu precise universe
deb-src http://us.archive.ubuntu.com/ubuntu precise universe
heredoc
) > /etc/apt/sources.list

	#
	# steamrt - beta or non-beta repo?
	#
	if [[ "${BETA_ARG}" == "--beta" ]]; then
		(cat << heredoc
deb http://repo.steampowered.com/steamrt/ scout_beta main
deb-src http://repo.steampowered.com/steamrt/ scout_beta main
heredoc
) > /etc/apt/sources.list.d/steamrt.list
	else
		(cat << heredoc
deb http://repo.steampowered.com/steamrt/ scout main
deb-src http://repo.steampowered.com/steamrt/ scout main
heredoc
) > /etc/apt/sources.list.d/steamrt.list
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

    # Before installing any additional packages, neuter upstart.
    # Otherwise on Ubuntu 12.04, when dbus is installed it starts
    # a new dbus-daemon outside the chroot which locks files 
    # inside the chroot, preventing those directories from
    # getting unmounted when the chroot exits.
    dpkg-divert --local --rename --add /sbin/initctl
    ln -s /bin/true /sbin/initctl

	# All repos and keys added; update
	apt-get -y update

	#
	#  Install compilers and libraries
	#
	apt-get install --force-yes -y ubuntu-minimal pkg-config time
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

	update-alternatives --install /usr/bin/gcc gcc /usr/bin/clang-3.4 50
	update-alternatives --install /usr/bin/g++ g++ /usr/bin/clang++-3.4 50

	update-alternatives --install /usr/bin/gcc gcc /usr/bin/clang-3.6 50
	update-alternatives --install /usr/bin/g++ g++ /usr/bin/clang++-3.6 50	

	# gcc-4.8 is the default
	update-alternatives --set gcc /usr/bin/gcc-4.8
	update-alternatives --set g++ /usr/bin/g++-4.8
	update-alternatives --set cpp-bin /usr/bin/cpp-4.8

	echo ""
	echo "#####"
	echo "##### Chroot setup is done!"
	echo "#####"
	echo ""
}

# http://stackoverflow.com/questions/64786/error-handling-in-bash
function cleanup()
{
	echo -e "\nenv is:\n$(env)\n"
	echo "ERROR: ${SCRIPTNAME} just hit error handler."
	echo "  BASH_COMMAND is \"${BASH_COMMAND}\""
	echo "  BASH_VERSION is $BASH_VERSION"
	echo "  pwd is \"$(pwd)\""
	echo "  PATH is \"$PATH\""
	echo ""

	echo -e "${COLOR_ERROR_ON}A command returned error. See the logfile: ${LOGFILE}${COLOR_OFF}"
}

main()
{
	# Check if we have any arguments.
	if [[ $# == 0 ]]; then
		echo "Usage: $0 [--force] [--beta] [--output-dir <DIRNAME>] [--prefix <PREFIX>] --i386 | --amd64"
		exit 1
	fi

	if [[ "$1" == "--force" ]]; then
		INSTALL_FORCE=true
		shift
	fi

	# Beta repo or regular repo?
	if [[ "$1" == "--beta" ]]; then
		BETA_ARG="--beta"
		CHROOT_PREFIX=${CHROOT_PREFIX}beta_
		shift
	fi

	if [[ "$1" == "--output-dir" ]]; then
		CHROOT_DIR=$2
		shift;shift
	fi

	if [[ "$1" == "--prefix" ]]; then
		CHROOT_PREFIX=$2
		shift;shift
	fi

	# Configuring root?
	if [[ "$1" == "--configure" ]]; then
		configure_chroot
		exit 0
	fi

	# Building root(s)
	prebuild_chroot $@
	trap cleanup EXIT
	for var in "$@"; do
		build_chroot $var
	done
	trap - EXIT

	echo -e "\n${COLOR_ON}Done...${COLOR_OFF}"
}

main $@

# vi: ts=4 sw=4 expandtab
