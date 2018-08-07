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

sh_quote() { local quoted="$(printf '%q ' "$@")"; [[ $# -eq 0 ]] || echo "${quoted:0:-1}"; }
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
  showcmd sudo docker inspect "$1"
  # Echo y/n based on docker return, so we don't interpret the sudo command failing as the
  # docker-inspect returning negatively
  local ret=$(sudo sh -c "$(sh_quote docker inspect "$1") &>/dev/null && echo y || echo n")
  [[ -n $ret ]] || die "sudo failure"
  [[ $ret = y ]] || return 1
}

#
# Build the docker image
#
build_docker() # build_docker <imagename> <arch> [beta]
{
  local image="$1"
  local arch="$2"
  local beta="$3"

  if docker_haveimage "$image"; then
    die "Image \"$image\" already exists." \
        "Remove existing image first or specify an alternative name."
  fi
  # FIXME WIP
}

# Argument
#
# Parse arguments & run
#
beta_arg="" # --beta?
arch_arg="" # arch argument
name_arg="" # name argument
end_of_opts="" # Saw end of options [--]
invalid_args="" # Invalid arguments?
while [[ $# -gt 0 ]]; do
  if [[ -z $1 ]]; then # Sanity
    err "Unexpected empty argument"
    invalid_args=1
  elif [[ $1 = '--beta' ]]; then # Known optional argument
    beta_arg=1
  elif [[ -z $end_of_opts && $1 = '--' ]]; then # -- as end of options
    end_of_opts=1
  elif [[ -z $end_of_opts && ${1:0:1} = '-' ]]; then # Some other option-looking-thing
    err "Unknown option $1"
    invalid_args=1
  elif [[ -z $arch_arg ]]; then # Positional argument, no arch
    arch_arg="$1"
  elif [[ -z $name_arg ]]; then # Name argument
    name_arg="$1"
  else
    # Some other thing
    err "Unexpected argument: \"$1\""
    invalid_args=1
  fi
  shift
done

# Valid arguments?
[[ -n $arch_arg && -z $invalid_args ]] || die "Usage: $0 [ --beta ] { amd64 | i386 } [ [--] image-name ]"

# Default image name steam-runtime-{arch}-{beta}
[[ -n $name_arg ]] || name_arg="steam-runtime-${arch_arg}${beta_arg:+-beta}"

# Looks good, proceed
build_docker "$name_arg" "$arch_arg" "$beta_arg"
