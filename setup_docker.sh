#!/bin/bash

# Helper script to invoke docker_fetch_base_cloudimage.sh and start a docker build.
#
# The included docker file can be invoked directly, this script is meant as a friendly error-checked
# interface to quickly execute the right steps.
#
# The ultimate effect of this script, modulo error and sanity checking, is:
#   ./docker_fetch_base_cloudimg.sh
#   sudo docker build -f steam-runtime.docker .
set -eu

# Cloud image script should lvie next to us
SCRIPT_RELDIR="$(dirname "$0")"
CLOUDIMAGE_SCRIPT="$SCRIPT_RELDIR/docker_fetch_base_cloudimg.sh"
DOCKERFILE="$SCRIPT_RELDIR/steam-runtime.docker"

# Output helpers
COLOR_ERR=""
COLOR_STAT=""
COLOR_CMD=""
COLOR_CLEAR=""
if [[ $(tput colors 2>/dev/null || echo 0) -gt 0 ]]; then
  COLOR_ERR=$'\e[31;1m'
  COLOR_STAT=$'\e[32;1m'
  COLOR_CMD=$'\e[93;1m'
  COLOR_CLEAR=$'\e[0m'
fi

sh_quote ()
{
  if [ $# -gt 0 ]; then
    printf '%q ' "$@"
  fi
}

err()      { echo >&2 "${COLOR_ERR}!!${COLOR_CLEAR} $*"; }
stat()     { echo >&2 "${COLOR_STAT}::${COLOR_CLEAR} $*"; }
showcmd()  { echo >&2 "+ ${COLOR_CMD}$(sh_quote "$@")${COLOR_CLEAR}"; }
die()      { err "$@"; exit 1; }
finish()   { stat "$@"; exit 0; }
cmd()      { showcmd "$@"; "$@"; }

#
# How to run docker commands
#

# Check if an image exists
docker_haveimage() {
  local image="$1"
  stat "Checking for existing docker image"
  showcmd sudo docker inspect "$1"
  # Echo y/n based on docker return, so we don't interpret the sudo command failing as the
  # docker-inspect returning negatively
  local ret
  ret=$(sudo sh -c "$(sh_quote docker inspect "$1") &>/dev/null && echo y || echo n")
  [[ -n $ret ]] || die "sudo failure"
  [[ $ret = y ]] || return 1
}

docker_run() { cmd sudo docker "$@"; }

#
# Build the docker image
#
build_docker() # build_docker <imagename> <arch> [beta]
{
  local image="$1"
  local arch="$2"
  local beta="$3"
  local extra_bootstrap="$4"

  # Specified extra_bootstrap exists?
  if [[ -n $extra_bootstrap && ! -f $extra_bootstrap ]]; then
    die "Extra bootstrap file does not exist ($extra_bootstrap)"
  fi

  # Cloud image script is here?
  if [[ -z $CLOUDIMAGE_SCRIPT || ! -x $CLOUDIMAGE_SCRIPT ]]; then
    die "Required cloud image fetching script not found ($CLOUDIMAGE_SCRIPT)"
  fi

  # Image already exists?
  if docker_haveimage "$image"; then
    die "Image \"$image\" already exists." \
        "Remove existing image first or specify an alternative name."
  fi

  # Run cloud image fetch
  stat "Fetching cloud image"
  cmd "$CLOUDIMAGE_SCRIPT" "$arch" || die "Cloud image fetch failed, see above"

  # Copy external extra bootstrap script in.  If you put your own file named
  # scripts/bootstrap-extra.sh in there this will fail, and don't do that.
  if [[ -n $extra_bootstrap ]]; then
    stat "Copying extra bootstrap script to scripts/bootstrap-extra.sh"
    bootstrap_temp="$(readlink -f "$SCRIPT_RELDIR"/scripts)/bootstrap-extra.sh"
    [[ ! -e $bootstrap_temp ]] || die "Stale scripts/bootstrap-extra.sh exists, not clobbering"
    cleanup_bootstrap() { [[ -z $bootstrap_temp || ! -f $bootstrap_temp ]] || rm "$bootstrap_temp"; }
    trap cleanup_bootstrap EXIT
    cmd cp "$extra_bootstrap" "$bootstrap_temp"
  fi

  # Run build
  stat "Building docker image"
  docker_run build --build-arg=arch="$arch" ${beta:+--build-arg=beta=1} \
             ${extra_bootstrap:+"--build-arg=extra_bootstrap=scripts/bootstrap-extra.sh"} \
             ${proxy:+"--build-arg=proxy=${proxy}"} \
             ${no_proxy:+"--build-arg=no_proxy=${no_proxy}"} \
             -t "$image" -f "$DOCKERFILE" "$SCRIPT_RELDIR"

  stat "Successfully built docker image: $image"
  stat "  See README.md for usage"
}

# Argument
#
# Parse arguments & run

usage () {
  if [ "$1" = 0 ]; then
    say=stat
  else
    say=err
  fi

  "$say" "Usage: $0 [--beta] [--extra-bootstrap FILE] [--proxy=URI] [--no-proxy=HOSTNAME[,HOSTNAME...]] -- {amd64|i386} [IMAGE]"
  exit "$1"
}

beta_arg="" # --beta?
arch_arg="" # arch argument
name_arg="" # name argument
extra_bootstrap_arg="" # extra-bootstrap argument
proxy="${http_proxy:-}"
no_proxy="${no_proxy:-}"

getopt_temp="$(getopt -o '' --long \
'beta,extra-bootstrap:,help,proxy:,no-proxy:' \
-n "$0" -- "$@")"
eval set -- "$getopt_temp"
unset getopt_temp

while [ "$#" -gt 0 ]; do
  case "$1" in
    (--beta)
      beta_arg=1
      shift
      ;;

    (--extra-bootstrap)
      if [ -z "$2" ]; then
        err "--extra-bootstrap cannot be empty"
        usage 2
      fi

      extra_bootstrap_arg="$2"
      shift 2
      ;;

    (--proxy)
      proxy="$2"
      shift 2
      ;;

    (--no-proxy)
      no_proxy="${no_proxy:+"${no_proxy},"}$2"
      shift 2
      ;;

    (--help)
      usage 0
      ;;

    (--)
      shift
      break
      ;;

    (-*)
      err "Unknown option $1"
      usage 2
      ;;

    (*)
      break
      ;;
  esac
done

while [ "$#" -gt 0 ]; do
  if [ -z "$arch_arg" ]; then # Positional argument: architecture
    arch_arg="$1"
  elif [ -z "$name_arg" ]; then # Name argument
    name_arg="$1"
  else
    # Some other thing
    err "Unexpected argument: \"$1\""
    usage 2
  fi
  shift
done

# Valid arguments?
[[ ( $arch_arg = i386 || $arch_arg = amd64 ) ]] || usage 2

# Default image name steam-runtime-{arch}-{beta}
[[ -n $name_arg ]] || name_arg="steam-runtime-${arch_arg}${beta_arg:+-beta}"

# Looks good, proceed
build_docker "$name_arg" "$arch_arg" "$beta_arg" "$extra_bootstrap_arg"
