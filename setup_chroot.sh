#!/usr/bin/env bash

SCRIPT="$(readlink -f "$0")"
SCRIPTNAME="$(basename "$SCRIPT")"
SCRIPT_DIR="$(dirname "$SCRIPT")"
LOGFILE=""
CHROOT_PREFIX="steamrt_"
CHROOT_DIR="/var/chroots"
CHROOT_NAME=""

# exit on any script line that fails
set -o errexit
# bail on any unitialized variable reads
set -o nounset
# bail on failing commands before last pipe
set -o pipefail

# Output helpers
COLOR_OFF=""
COLOR_ON=""
if [[ $(tput colors 2>/dev/null || echo 0) -gt 0 ]]; then
  COLOR_ON=$'\e[93;1m'
  COLOR_OFF=$'\e[0m'
fi

FORCE=0

sh_quote ()
{
  local quoted
  if [ $# -gt 0 ]; then
    quoted="$(printf '%q ' "$@")"
    echo "${quoted:0:-1}"
  fi
}

prebuild_chroot()
{
	local name

	# install some packages
	echo -e "\\n${COLOR_ON}Installing schroot...${COLOR_OFF}"
	sudo -E apt-get install -y schroot

	# Check if there are any active schroot sessions right now and warn if so...
	schroot_list=$(schroot --list --all-sessions | head -n 1)
	if [ -n "$schroot_list" ]; then
		tput setaf 3
		echo -e "\\nWARNING: Schroot says you have a currently active session!\\n"
		tput sgr0
		echo "  ${schroot_list}"
		echo ""
		if [ ${FORCE} -eq 0 ]; then
			read -r -p "Are you sure you want to continue (y/n)? "
			if [[ "$REPLY" != [Yy] ]]; then
				echo -e "Cancelled...\\n"
				exit 1
			fi
		fi
	fi

	STEAM_RUNTIME_SPEW_WARNING=
	for var in "$@"; do
		if [ -n "$CHROOT_NAME" ]; then
			name="$CHROOT_NAME"
		else
			name="${CHROOT_PREFIX}${var/--/}"
		fi

		dirname="${CHROOT_DIR}/${name}"
		if [ -d "${dirname}" ]; then
			tput setaf 3
			STEAM_RUNTIME_SPEW_WARNING=1
			echo -e "About to remove ${dirname} and re-install..."
			tput sgr0
		fi
	done

	if [[ "$STEAM_RUNTIME_SPEW_WARNING" == "1" ]]; then
		if [ ${FORCE} -eq 0 ]; then
			read -r -p "  This ok (y/n)? "
			if [[ "$REPLY" != [Yy] ]]; then
				echo -e "Cancelled...\\n"
				exit 1
			fi
		fi
	fi
}

copy_apt_settings ()
{
	local sysroot="$1"

	if [ "$1/" -ef / ]; then
		echo "Internal error: sysroot $1 is the same file as the real root" >&2
		exit 1
	fi

	# Copy over proxy settings from host machine
	echo -e "\\n${COLOR_ON}Adding proxy info to chroot (if set)...${COLOR_OFF}"
	set +o pipefail
	env | grep -i "_proxy=" | grep -v PERSISTENT_HISTORY_LAST | xargs -i echo export {} | sudo tee "$sysroot/etc/profile.d/steamrtproj.sh"
	env | grep -i "_proxy=" | grep -v PERSISTENT_HISTORY_LAST | xargs -i echo export {} | sudo tee -a "$sysroot/etc/environment"
	set -o pipefail
	sudo rm -rf "$sysroot/etc/apt/apt.conf"
	if [ -f /etc/apt/apt.conf ]; then sudo cp "/etc/apt/apt.conf" "$sysroot/etc/apt"; fi
}

untar_chroot ()
{
	# untar_chroot {--amd64 | --i386} TARBALL
	# Unpack a sysroot tarball for the specified architecture.

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

	shift

	local tarball="$1"
	local name

	if [ -n "$CHROOT_NAME" ]; then
		name="$CHROOT_NAME"
	else
		name="${CHROOT_PREFIX}${pkg}"
	fi

	local sysroot="${CHROOT_DIR}/${name}"

	# blow away existing directories and recreate empty ones
	echo -e "\\n${COLOR_ON}Creating $sysroot..."
	sudo rm -rf "$sysroot"
	sudo mkdir -p "$sysroot"

	# Create our schroot .conf file
	echo -e "\\n${COLOR_ON}Creating /etc/schroot/chroot.d/${name}.conf...${COLOR_OFF}"
	printf '[%s]\ndescription=%s\ndirectory=%s\npersonality=%s\ngroups=sudo\nroot-groups=sudo\npreserve-environment=true\ntype=directory\n' "${name}" "${tarball##*/}" "${sysroot}" "${personality}" | sudo tee "/etc/schroot/chroot.d/${name}.conf"

	# Create our chroot
	echo -e "\\n${COLOR_ON}Unpacking the chroot...${COLOR_OFF}"
	sudo tar --auto-compress -C "$sysroot" -xf "$tarball"

	copy_apt_settings "$sysroot"

	# Implement --extra-apt-source
	if [ -n "${extra_apt_sources+set}" ]; then
		for line in "${extra_apt_sources[@]}"; do
			printf '%s\n' "$line"
		done > "$sysroot/etc/apt/sources.list.d/steamrt-extra.list"
	fi

	if [ -n "$(sudo find "$sysroot" -xdev '(' -uid +99 -o -gid +99 ')' -ls)" ]; then
		echo -e "\\n${COLOR_ON}Warning: these files might have incorrect uid mapping${COLOR_OFF}" >&2
		sudo find "$sysroot" -xdev '(' -uid +99 -o -gid +99 ')' -ls >&2
	fi
}

# https://stackoverflow.com/questions/64786/error-handling-in-bash
function cleanup()
{
	echo -e "\\nenv is:\\n$(env)\\n"
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

usage()
{
	if [ "$1" -ne 0 ]; then
		exec >&2
	fi

	echo "Usage: $0 [--beta | --suite SUITE] [--name NAME] [--extra-apt-source 'deb http://MIRROR SUITE COMPONENT...'] [--output-dir <DIRNAME>] [--logfile FILE] --tarball TARBALL --i386|--amd64"
	exit "$1"
}

main()
{
	local getopt_temp
	getopt_temp="$(getopt -o '' --long \
	'force,amd64,beta,extra-apt-source:,i386,name:,output-dir:,logfile:,suite:,tarball:,help' \
	-n "$0" -- "$@")"
	eval set -- "$getopt_temp"
	unset getopt_temp

	local arch=
	local -a setup_arguments=()
	local suite=scout
	local suite_suffix=
	local tarball=

	# Create a copy of the arguments
	local args=("$@")

	while [ "$#" -gt 0 ]; do
		case "$1" in
			(--force)
				FORCE=1
				shift
				;;

			(--amd64|--i386)
				if [ -n "$arch" ] && [ "$arch" != "$1" ]; then
					echo "Error: $1 conflicts with $arch" >&2
					usage 2
				fi
				arch="$1"
				shift
				;;

			(--beta)
				setup_arguments+=(--beta)
				suite_suffix=_beta
				shift
				;;

			(--name)
				CHROOT_NAME="$2"
				shift 2
				;;

			(--extra-apt-source)
				setup_arguments+=("$1" "$2")
				shift 2
				;;

			(--help)
				usage 0
				;;

			(--logfile)
				LOGFILE="$2"
				shift 2
				;;

			(--output-dir)
				CHROOT_DIR="$2"
				shift 2
				;;

			(--suite)
				suite="$2"
				setup_arguments+=(--suite "$2")
				shift 2
				;;

			(--tarball)
				tarball="$2"
				shift 2
				;;

			(--)
				shift
				break
				;;

			(-*)
				usage 2
				;;

			(*)
				# no non-option arguments are currently allowed
				usage 2
				break
				;;
		esac
	done

	# Launch ourselves with script so we can time this and get a log file
	if [[ ! -v SETUP_CHROOT_LOGGING_STARTED ]]; then
		if command -v script >/dev/null; then
			export SETUP_CHROOT_LOGGING_STARTED=1
			export SHELL=/bin/bash
			if [ -z "$LOGFILE" ]; then
				LOGFILE="$(mktemp --tmpdir steam-runtime-setup-chroot-XXX.log)"
			fi
			script --return --command "time $SCRIPT $(sh_quote "${args[@]}")" "${LOGFILE}"
			exit $?
		else
			echo >&2 "!! 'script' command not found, will not auto-generate a log file"
			# Continue
		fi
	fi

	CHROOT_PREFIX="${CHROOT_PREFIX}${suite}${suite_suffix}_"

	if [ -z "$tarball" ]; then
		echo "This script no longer bootstraps chroots from first principles." >&2
		echo "Use --tarball to provide a pre-prepared sysroot." >&2
		usage 2
	fi

	if [ -z "$arch" ]; then
		usage 2
	fi

	# Building root(s)
	prebuild_chroot "$arch"
	trap cleanup EXIT
	untar_chroot "$arch" "$tarball"
	trap - EXIT

	echo -e "\\n${COLOR_ON}Done...${COLOR_OFF}"
}

main "$@"

# vi: ts=4 sw=4 noexpandtab
