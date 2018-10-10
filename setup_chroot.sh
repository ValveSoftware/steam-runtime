#!/bin/bash

SCRIPT="$(readlink -f "$0")"
SCRIPTNAME="$(basename "$SCRIPT")"
SCRIPT_DIR=$(dirname "$SCRIPT")
BOOTSTRAP_SCRIPT="$(dirname "$0")"/scripts/bootstrap-runtime.sh
LOGFILE="$(mktemp --tmpdir steam-runtime-setup-chroot-XXX.log)"
CHROOT_PREFIX="steamrt_scout_"
CHROOT_DIR="/var/chroots"
BETA_ARG=""

# exit on any script line that fails
set -o errexit
# bail on any unitialized variable reads
set -o nounset

# Output helpers
COLOR_OFF=""
COLOR_ON=""
if [[ $(tput colors 2>/dev/null || echo 0) -gt 0 ]]; then
  COLOR_ON=$'\e[93;1m'
  COLOR_OFF=$'\e[0m'
fi

sh_quote() { local quoted="$(printf '%q ' "$@")"; [[ $# -eq 0 ]] || echo "${quoted:0:-1}"; }

prebuild_chroot()
{
	# install some packages
	echo -e "\n${COLOR_ON}Installing debootstrap schroot...${COLOR_OFF}"
	sudo -E apt-get install -y debootstrap schroot

	# Check if there are any active schroot sessions right now and warn if so...
	schroot_list=$(schroot --list --all-sessions | head -n 1)
	if [ $schroot_list ]; then
		tput setaf 3
		echo -e "\nWARNING: Schroot says you have a currently active session!\n"
		tput sgr0
		echo "  ${schroot_list}"
		echo ""
		read -p "Are you sure you want to continue (y/n)? "
		if [[ "$REPLY" != [Yy] ]]; then
			echo -e "Cancelled...\n"
			exit 1
		fi
	fi

	STEAM_RUNTIME_SPEW_WARNING=
	for var in "$@"; do
		dirname="${CHROOT_DIR}/${CHROOT_PREFIX}${var/--/}"
		if [ -d "${dirname}" ]; then
			tput setaf 3
			STEAM_RUNTIME_SPEW_WARNING=1
			echo -e "About to remove ${dirname} and re-install..."
			tput sgr0
		fi
	done

	if [[ "$STEAM_RUNTIME_SPEW_WARNING" == "1" ]]; then
		read -p "  This ok (y/n)? "
		if [[ "$REPLY" != [Yy] ]]; then
			echo -e "Cancelled...\n"
			exit 1
		fi
	fi
}

build_chroot()
{
	# Check that we are running in the right environment
	if [[ ! -x $BOOTSTRAP_SCRIPT ]]; then
		echo >&2 "!! Required helper script not found: \"$BOOTSTRAP_SCRIPT\""
	fi

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

	# Create our chroot
	echo -e "\n${COLOR_ON}Bootstrap the chroot...${COLOR_OFF}" 
	sudo -E debootstrap --arch=${pkg} --include=wget --keyring="${SCRIPT_DIR}/ubuntu-archive-keyring.gpg" precise ${CHROOT_DIR}/${CHROOT_NAME} http://archive.ubuntu.com/ubuntu/

	# Copy over proxy settings from host machine
	echo -e "\n${COLOR_ON}Adding proxy info to chroot (if set)...${COLOR_OFF}" 
	env | grep -i "_proxy=" | grep -v PERSISTENT_HISTORY_LAST | xargs -i echo export {} | sudo tee ${CHROOT_DIR}/${CHROOT_NAME}/etc/profile.d/steamrtproj.sh
	env | grep -i "_proxy=" | grep -v PERSISTENT_HISTORY_LAST | xargs -i echo export {} | sudo tee -a ${CHROOT_DIR}/${CHROOT_NAME}/etc/environment
	sudo rm -rf "${CHROOT_DIR}/${CHROOT_NAME}/etc/apt/apt.conf"
	if [ -f /etc/apt/apt.conf ]; then sudo cp "/etc/apt/apt.conf" "${CHROOT_DIR}/${CHROOT_NAME}/etc/apt"; fi  

	echo -e "\n${COLOR_ON}Running ${BOOTSTRAP_SCRIPT} ${BETA_ARG}...${COLOR_OFF}" 

	# Touch the logfile first so it has the proper permissions
	rm -f "${LOGFILE}"
	touch "${LOGFILE}"

	# The chroot has access to /tmp so copy the script there and run it with --configure
	TMPNAME="$(basename "$BOOTSTRAP_SCRIPT")"
	TMPNAME="${TMPNAME%.*}-$$.sh"
	cp -f "$BOOTSTRAP_SCRIPT" "/tmp/${TMPNAME}"
	chmod +x "/tmp/${TMPNAME}"
	schroot --chroot ${CHROOT_NAME} -d /tmp --user root -- "/tmp/${TMPNAME}" --chroot ${BETA_ARG}
	rm -f "/tmp/${TMPNAME}"
	cp -f "$SCRIPT_DIR/write-manifest" "/tmp/${TMPNAME}"
	chmod +x "/tmp/${TMPNAME}"
	schroot --chroot ${CHROOT_NAME} -d /tmp --user root -- "/tmp/${TMPNAME}" /
	rm -f "/tmp/${TMPNAME}"
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

	tput setaf 3
	echo "A command returned error. See the logfile: ${LOGFILE}"
	tput sgr0
}

main()
{
	# Check if we have any arguments.
	if [[ $# == 0 ]]; then
		echo >&2 "Usage: $0 [--beta] [--output-dir <DIRNAME>] --i386 | --amd64"
		exit 1
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

	# Building root(s)
	prebuild_chroot $@
	trap cleanup EXIT
	for var in "$@"; do
		build_chroot $var
	done
	trap - EXIT

	echo -e "\n${COLOR_ON}Done...${COLOR_OFF}"
}

# Launch ourselves with script so we can time this and get a log file
if [[ ! -v SETUP_CHROOT_LOGGING_STARTED ]]; then
	if which script &>/dev/null; then
		export SETUP_CHROOT_LOGGING_STARTED=1
		export SHELL=/bin/bash
		script --return --command "time $SCRIPT $(sh_quote "$@")" "${LOGFILE}"
		exit $?
	else
		echo >&2 "!! 'script' command not found, will not auto-generate a log file"
		# Continue to main
	fi
fi

main $@

# vi: ts=4 sw=4 expandtab
