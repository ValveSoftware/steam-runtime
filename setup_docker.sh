#!/bin/bash

# Helper to invoke docker_fetch_base_cloudimage.sh and start a docker build
set -eu

# Output helpers
COLOR_ERR=""
COLOR_STAT=""
COLOR_CLEAR=""
if [[ $(tput colors || echo 0) -gt 0 ]]; then
  COLOR_ERR=$'\e[31;1m'
  COLOR_STAT=$'\e[32;1m'
  COLOR_CLEAR=$'\e[0m'
fi

err() { echo >&2 "${COLOR_ERR}!!${COLOR_CLEAR} $*"; }
stat() { echo >&2 "${COLOR_STAT}::${COLOR_CLEAR} $*"; }
die() { err "$@"; exit 1; }
finish() { stat "$@"; exit 0; }

#
# Build a docker image
#
build_docker() # build_docker <imagename> <arch> [beta]
{
  local image="$1"
  local arch="$2"
  local beta="$3"

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
  if [[ -z $1 ]]; then
    # Sanity
    err "Unexpected empty argument"
    invalid_args=1
  elif [[ $1 = '--beta' ]]; then
    # Known optional argument
    beta_arg=1
  elif [[ -z $end_of_opts && $1 = '--' ]]; then
    # -- means end of options, so e.g. "foo -- -image-name" works.
    end_of_opts=1
  elif [[ -z $end_of_opts && ${1:0:1} = '-' ]]; then
    # Some other option-looking-thing
    err "Unknown option $1"
    invalid_args=1
  elif [[ -z $arch_arg ]]; then
    # Positional argument, no arch
    arch_arg="$1"
  elif [[ -z $name_arg ]]; then
    # Name argument
    name_arg="$1"
  else
    # Some other thing
    err "Unexpected argument: \"$1\""
    invalid_args=1
  fi
  shift
done

[[ -n $arch_arg && -z $invalid_args ]] || die "Usage: $0  [ --beta ] { amd64 | i386 } [ [--] image-name ]"
# Default image name steam-runtime-{arch}-{beta}
[[ -n $name_arg ]] || name_arg="steam-runtime-$ARCH${beta_arg:+-beta}"

build_docker "$name_arg" "$arch_arg" "$beta"
