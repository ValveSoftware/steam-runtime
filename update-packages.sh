#!/bin/bash
#
# Script to update packages used by the Steam runtime

# The top level directory
TOP=$(cd "${0%/*}" && echo ${PWD})
cd "${TOP}"

DRY_RUN=0
SECURITY_UPDATES_ONLY=0

# These are custom packages that can't be automatically downloaded
CUSTOM_PACKAGES="dummygl jasper libsdl1.2 libsdl2 libsdl2-image libsdl2-mixer libsdl2-net libsdl2-ttf glew1.10 libxcb"

valid_package()
{
    PACKAGE=$1

    for SOURCE_PACKAGE in $(cat packages.txt | egrep -v '^#' | awk '{print $1}'); do
        if [ "${SOURCE_PACKAGE}" = "${PACKAGE}" ]; then
            return 0
        fi
    done

    echo "Couldn't find source package ${PACKAGE} in packages.txt" >&2
    return 1
}

has_security_update()
{
    PACKAGE=$1
    HAVE_VER=$2
    CANDIDATE_VER=$3

    for BIN_PACKAGE in $(grep ^${PACKAGE} ${TOP}/packages.txt | cut -f 2-); do
        while read line; do
            if [[ $line =~ "${PACKAGE} \(${HAVE_VER}\)" ]]; then
                break
            elif [[ $line =~ "-security;" ]]; then
                return 0
            fi
        done < <(apt-get -qq changelog ${BIN_PACKAGE}=${CANDIDATE_VER} 2>&1)
    done
    return 1
}

update_package()
{
    PACKAGE=$1

    DIR="${TOP}/packages/source/${PACKAGE}"

    # Check for custom packages
    for CUSTOM in ${CUSTOM_PACKAGES}; do
        if [ "${PACKAGE}" = "${CUSTOM}" ]; then
            echo "CUSTOM: ${PACKAGE}"
            return
        fi
    done

    echo "CHECKING: ${PACKAGE}"

    # Download the new dsc file and see if it's a newer version
    TMP="${DIR}/tmp"
    rm -rf "${TMP}"
    mkdir -p "${TMP}"; cd "${TMP}"
    apt-get source -qq --download-only --dsc-only "${PACKAGE}" >/dev/null || exit 3
    DSC=$(echo *.dsc)
    CANDIDATE_VER=$(cat *.dsc | grep "^Version: [[:graph:]]\+$" | awk '{print $2}')
    cd "${DIR}"

    if [ ! -f "${DSC}" ]; then
        HAVE_VER=$(cat *.dsc | grep "^Version: [[:graph:]]\+$" | awk '{print $2}')
        if [ "$HAVE_VER" == "$CANDIDATE_VER" ]; then
            return
        fi

        if has_security_update "$PACKAGE" "$HAVE_VER" "$CANDIDATE_VER"; then
            echo "NOTE: $PACKAGE has security update (${HAVE_VER} -> ${CANDIDATE_VER})"
        else
			if [ $SECURITY_UPDATES_ONLY -eq 1 -o $DRY_RUN -ne 0 ]; then
				echo "NOTE: $PACKAGE has non-security update (${HAVE_VER} -> ${CANDIDATE_VER})"
				return
			fi
        fi

		if [ $DRY_RUN -ne 0 ]; then
			return
		fi

        echo "DOWNLOADING: ${PACKAGE}"

        # Back up old files
        OLD="${DIR}/old-versions"
        mkdir -p "${OLD}"
        for file in *.*; do
            if [ -f "${file}" ]; then
                mv -v "${file}" "${OLD}/"
            fi
        done

        # Download new files
        apt-get source -qq --download-only "${PACKAGE}" || exit 4
        touch .downloaded
    fi
    rm -rf "${TMP}"

    cd "${TOP}"
}

TEMP=$(getopt -o n,s -l dry-run,help,security-only -- "$@")
eval set -- "$TEMP"
while true; do
    case "$1" in
        -n|--dry-run)
            echo "NOTE: simulation - no updates will be downloaded"
            DRY_RUN=1
            shift;;
        -s|--security-only) 
            echo "NOTE: only security updates will be downloaded"
            SECURITY_UPDATES_ONLY=1
            shift;;
        --help)
            echo "usage: $0 [-n/--dry-run] [-s/--security-only]"
            exit 0;;
        --)
            shift;
            break;;
        *) 
            echo "unknown argument"
            exit 1;;
   esac
done

if [ -z $debian_chroot ]; then
  echo running update-packages outside the buildroot is a bad idea.  
  echo run as buildroot.sh $0
  exit 1
fi

# run apt-get update if don't know when we last ran, or haven't run it in the last hour
NEED_APT_UPDATE=1
if [ -f /var/lib/apt/periodic/update-success-stamp ]; then
  if [ $(stat -c "%Y" /var/lib/apt/periodic/update-success-stamp ) -gt $(date -d "1 hour ago" +%s) ]; then
    NEED_APT_UPDATE=0
  fi
else
  sudo apt-get install -qq -y update-notifier-common
fi

if [ $NEED_APT_UPDATE -ne 0 ]; then
  echo updating apt package indexes...
  sudo apt-get -qq update || exit 4
fi

# Update the packages
if [ "$1" != "" ]; then
    for PACKAGE in "$@"; do
        if valid_package "${PACKAGE}"; then
            update_package "${PACKAGE}"
        fi
    done
else
    for SOURCE_PACKAGE in $(cat packages.txt | egrep -v '^#' | awk '{print $1}'); do
        update_package "${SOURCE_PACKAGE}"
    done
fi

# vi: ts=4 sw=4 expandtab
