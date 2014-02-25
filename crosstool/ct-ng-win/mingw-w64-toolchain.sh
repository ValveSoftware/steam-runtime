#!/bin/bash

# Script to download MinGW-w64 compilers and add them to PATH.
# Not for cross compiling at present but entirely possible.
# Values are returned by passing in variable names to assign to.

download_check_sha1()
{
  local _URL="$1"
  local _SHA1="$2"

  local _SHA1EXISTING=""
  local _NEEDDL=no

  local SHA1SUM=sha1sum
  if [ "$OSTYPE" = "darwin" ]; then
    SHA1SUM=shasum
  fi

  if [ -f $(basename ${_URL}) ]; then
    _SHA1EXISTING=$($SHA1SUM $(basename ${_URL}) | cut -d' ' -f 1)
    if [ "$_SHA1" = "$_SHA1EXISTING" ]; then
      return
    fi
    echo "File $(basename ${_URL}) exists but sha1 incorrect, re-downloading."
  fi
  curl -S -L -O ${_URL}
  _SHA1EXISTING=$($SHA1SUM $(basename ${_URL}) | cut -d' ' -f 1)
  if [ ! "$_SHA1" = "$_SHA1EXISTING" ]; then
    echo "sha1 of $(basename ${_URL}) incorrect, exiting."
    exit 1
  fi
}

# <i> $1 is ARCH
# <i> $2 is ROOT
# <o> $3 is PATH to bin folder to be added to PATH
# <o> $4 is HASH is a hash of the compiler version that can be used in folder names to avoid binary incompat issues.
download_install_mingw_w64()
{
  local ARCH=$1; shift
  local ROOT=$1; shift
  local PATH_VAR=$1; shift
  local HASH_VAR=$1; shift

  pushd $ROOT
  local MINGW_GCC_SRC_VER=4.8.2
  local MINGW_GCC_EXC_VAR32=dwarf
  # local MINGW_GCC_EXC_VAR64=seh
  # Dwarf exceptions are only available for 32bit MinGW-w64 GCC.
  # Anyway, Adrien Nader says that Dwarf exceptions are buggy [1] (can't be thrown/caught over fn pointers?)
  # but llvm/clang's lli requires it [2]. The errors you get trying to build with 64bit SEH are:
  # lib/ExecutionEngine/RTDyldMemoryManager.cpp:135: undefined reference to `__deregister_frame'/undefined reference to `__register_frame'
  # [1] http://sourceforge.net/mailarchive/message.php?msg_id=31429682
  # [2] http://clang-developers.42468.n3.nabble.com/clang-3-3-does-not-build-with-gcc-4-8-with-Windows-SEH-exception-td4032754.html
  local MINGW_GCC_EXC_VAR64=sjlj
  local MINGW_GCC_EXC_THREADS=win32
  local MINGW_SF_URL="http://sourceforge.net/projects/mingw-w64/files"
  local   MINGW_GCC_VER32=i686-${MINGW_GCC_SRC_VER}-release-${MINGW_GCC_EXC_THREADS}-${MINGW_GCC_EXC_VAR32}-rt_v3-rev2
  local MINGW_GCC_VER64=x86_64-${MINGW_GCC_SRC_VER}-release-${MINGW_GCC_EXC_THREADS}-${MINGW_GCC_EXC_VAR64}-rt_v3-rev2

  local BITS=32
  if [ "$ARCH" = "i686" ]; then
    local MINGW_GCC_URL="${MINGW_SF_URL}/Toolchains%20targetting%20Win32/Personal%20Builds/mingw-builds/${MINGW_GCC_SRC_VER}/threads-${MINGW_GCC_EXC_THREADS}/${MINGW_GCC_EXC_VAR32}/${MINGW_GCC_VER32}.7z"
#    local MINGW_GCC_SHA1=b57dc5557a5dc18763e76e269082800300e8c286
    local MINGW_GCC_SHA1=9d80ecb4737414dd790204151a2e396ec5b45162
  else
    local MINGW_GCC_URL="${MINGW_SF_URL}/Toolchains%20targetting%20Win64/Personal%20Builds/mingw-builds/${MINGW_GCC_SRC_VER}/threads-${MINGW_GCC_EXC_THREADS}/${MINGW_GCC_EXC_VAR64}/${MINGW_GCC_VER64}.7z"
#    local MINGW_GCC_SHA1=c935f1e890f9b2e339677a9de381c1fb60438019 # seh
#    local MINGW_GCC_SHA1=77de7cdf6f17de557d0ffd619f13cea0fe98dc71 # sjlj
    local MINGW_GCC_SHA1=98eeccf1e2b1e1a26272b8c654f0476280dfe9aa  # sjlj rev2
    local BITS=64
  fi
  if [ "$ARCH" = "i686" ]; then
    local HOST_GCC_VER=${MINGW_GCC_VER32}
  else
    local HOST_GCC_VER=${MINGW_GCC_VER64}
  fi
  local HOST_GCC_TAG=$(echo ${HOST_GCC_VER} | md5sum | cut -f1 -d' ' | cut -c1-8)
  if [ "$HASH_IN_PATH" = "yes" ]; then
    local PATH_VAL=${PWD}/mingw${BITS}-${HOST_GCC_TAG}/bin
  else
    local PATH_VAL=${PWD}/mingw${BITS}/bin
  fi
  eval "$PATH_VAR=\${PATH_VAL}"
  eval "$HASH_VAR=\$HOST_GCC_TAG"
  if [ ! -d ${PATH_VAL} ]; then
    download_check_sha1 $MINGW_GCC_URL $MINGW_GCC_SHA1
    echo "Extracting "$(basename "${MINGW_GCC_URL}") to ${PWD}
    7za -y x $(basename "${MINGW_GCC_URL}") > /dev/null
    echo "The md5sum of compiler version ${HOST_GCC_VER} is: ${HOST_GCC_TAG}"   > ${PWD}/mingw${BITS}/COMPILER_VERSION_INFORMATION
    echo "It was downloaded from: ${MINGW_GCC_URL}"                            >> ${PWD}/mingw${BITS}/COMPILER_VERSION_INFORMATION
    echo "And the sha1sum of that archive was: ${MINGW_GCC_SHA1}"              >> ${PWD}/mingw${BITS}/COMPILER_VERSION_INFORMATION
    if [ "$HASH_IN_PATH" = "yes" ]; then
      mv ${PWD}/mingw${BITS} ${PWD}/mingw${BITS}-${HOST_GCC_TAG}
    fi
  fi
  popd
}

# Avoid name clashes using eval "$(this_file)_VAR=blah"
this_file()
{
  echo $(basename "$0") | tr '-' '_' | tr '[a-z]' '[A-Z]' | tr '.' '_'
}

OSTYPE=${OSTYPE//[0-9.]/}

if [ "$OSTYPE" != "msys" -a "$OSTYPE" != "linux-gnu" -a "$OSTYPE" != "darwin" ]; then
  echo "Error: $(basename $0) doesn't know what OS $OSTYPE is"
  exit 1
fi

#if [ "$OSTYPE" != "msys" ]; then
#  echo "Error: $(basename $0) doesn't currently support cross compilation, maybe one day."
#  exit 1
#fi

ARCH=$(uname -m)
ROOT=/tmp
PATH_OUT=PATH_OUT
HASH_OUT=HASH_OUT
TAG=
VERBOSE=no
HASH_IN_PATH=no

while [ "$#" -gt 0 ]; do
  OPT="$1"
  case "$1" in
        --enable-*)
            VAR=$(echo $1 | sed "s,^--enable-\(.*\),\1," | tr '-' '_')
            VAL=yes
            ;;
        --disable-*)
            VAR=$(echo $1 | sed "s,^--disable-\(.*\),\1,")
            VAL=no
            ;;
        --*=*)
            VAR=$(echo $1 | sed "s,^--\(.*\)=.*,\1," | tr '-' '_')
            VAL=$(echo $1 | sed "s,^--.*=\(.*\),\1,")
            ;;
        *)
            echo "Unrecognised option '$1'"
            exit 1
            ;;
    esac
    VAR=$(echo "$VAR" | tr '[a-z]' '[A-Z]')
    case "$VAR" in
        sources)
            if [ "$VAL" = "local" -o "$VAL" = "remote" ]; then
                eval "$VAR=\$VAL"
            else
                echo "$VAL can only be 'local' or 'remote'"
                exit 1
            fi
            ;;
        *)
            eval "${VAR}=\$VAL"
            ;;
    esac
    shift
    OPTIONS_DEBUG=$OPTIONS_DEBUG" ${VAR}=$VAL"
done

if [ "$DL_MINGW_W64_VERBOSE" = "yes" ]; then
  echo $OPTIONS_DEBUG
fi

# <i> $1 is ARCH
# <i> $2 is ROOT
# <o> $3 is TAG_VAR (an md5sum)
download_install_mingw_w64 $ARCH $ROOT $PATH_OUT $HASH_OUT
