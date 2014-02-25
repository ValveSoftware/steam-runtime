#!/usr/bin/env bash

# Problems and related bug reports.
#
# 1. ICU cannot be cross compiled atm:
#    https://bugzilla.mozilla.org/show_bug.cgi?id=912371
#
# 2. On Windows, x86_64 must not use SEH exceptions (in fact it probably must use Dwarf-2 exceptions):
#  2.1.
#    Release+Asserts/lib/libLLVMExecutionEngine.a(RTDyldMemoryManager.o): In function `llvm::RTDyldMemoryManager::registerEHFrames(unsigned char*, unsigned long long, unsigned long long)':
#    lib/ExecutionEngine/RTDyldMemoryManager.cpp:129: undefined reference to `__register_frame'
#    Release+Asserts/lib/libLLVMExecutionEngine.a(RTDyldMemoryManager.o): In function `llvm::RTDyldMemoryManager::deregisterEHFrames(unsigned char*, unsigned long long, unsigned long long)':
#    lib/ExecutionEngine/RTDyldMemoryManager.cpp:135: undefined reference to `__deregister_frame'
#    http://clang-developers.42468.n3.nabble.com/clang-3-3-does-not-build-with-gcc-4-8-with-Windows-SEH-exception-td4032754.html
#    Reid Kleckner:
#    "__register_frame is for registering DWARF unwind info.  It's currently under __GNUC__, since that usually implies linkage of libgcc, which provides that symbol.
#     Patches and bugs for avoiding this under mingw when libgcc is using SEH for unwinding are welcome."
#  2.2
#    http://lists.cs.uiuc.edu/pipermail/llvmdev/2012-August/052339.html (Charles Davis did some work on SEH via DW2, but didn't finish. Wouldn't have worked for MSVC though .. Kai Tietz
#    may have hacked on it some more since then).
#  2.3
#    My recent (17/12/2013) query on #llvm (thanks ki9a) turned up:
#    2.3.1:  [build] http://lists.cs.uiuc.edu/pipermail/llvm-commits/Week-of-Mon-20131209/198327.html  ..  applied already
#    2.3.2: [target] http://lists.cs.uiuc.edu/pipermail/llvm-commits/Week-of-Mon-20131216/198988.html  ..  http://redstar.de/ldc/win64eh_all_20131117.diff .. added to patches/llvm/head
#
# .. I am currently enabling Linux builds, and have run into:
# 3. Clang needs sysroot passing to it as per Darwin (probably; can't find crti.o or some such)
#
# 4. GTK must be built too and lots of other stuff probably: http://joekiller.com/2012/06/03/install-firefox-on-amazon-linux-x86_64-compiling-gtk/
#    I may need to adapt that ..
#    https://gist.github.com/phstc/4121839
#
# 5. I wanted to build Linux -> Linux native compilers but ran into a problem so chatted with Yann Morin:
#     <y_morin> mingwandroid: Building a native toolchain is not supported in ct-ng.
#     <y_morin> mingwandroid: A native toolchain is one without a sysroot. In such a toolchain, gcc (and ld) will search in /usr/include (and /lib and /usr/lib), without prefixing those locations with the sysroot path.
#     <y_morin> mingwandroid: This is a bit complex to set up, so crostool-NG does not support that (for now?)
#     <mingwandroid> y_morin: yeah, I just can't figure out where the config stuff is determining it not to be native is all, I'd be prepared to try to make the rest work if I can get over this initial hump.
#     <y_morin> mingwandroid: I don;t want to discourage you, but that's gonna bea quite a bit of work.
#     <y_morin> mingwandroid: We'd first need to differentiate the build-time sysroot from the runtime sysroot
#     <y_morin> mingwandroid: Then, we need to diferentiate between PREFIX_DIR and DEST_DIR

# Errors are fatal (occasionally this will be temporarily disabled)
set -e

THISDIR="$(dirname $0)"
test "$THISDIR" = "." && THISDIR=${PWD}
OSTYPE=${OSTYPE//[0-9.]/}
HOST_ARCH=$(uname -m)
# Much of the following is NYI (and should
# be done via the options processing anyway)
DEBUG_CTNG=no
DARWINVER=10
# Make this an option (and implement it)
DARWINSDKDIR=MacOSX10.6.sdk
# Absolute filepaths for:
# 1. crosstool-ng's final (i.e. non-sample) .config
CROSSTOOL_CONFIG=
# 2. and Mozilla's .mozconfig
MOZILLA_CONFIG=

# I wolud use associative arrays (declare -A) for this
# but OS X with Bash 3 doesn't support that.
TARGET_TO_PREFIX_osx="o"
TARGET_TO_PREFIX_windows="w"
TARGET_TO_PREFIX_linux="l"
TARGET_TO_PREFIX_ps3="p"
TARGET_TO_PREFIX_raspi="r"

VENDOR_OSES_osx="apple-darwin10"
VENDOR_OSES_windows="x86_64-w64-mingw32"
VENDOR_OSES_linux="unknown-linux-gnu"
VENDOR_OSES_raspi="unknown-linux-gnu"

# Defaults ..
BUILD_DEBUGGABLE_darwin="no"
BUILD_DEBUGGABLE_windows="no"
BUILD_DEBUGGABLE_linux="no"

BUILD_DEBUGGERS_darwin="yes"
BUILD_DEBUGGERS_windows="no"
BUILD_DEBUGGERS_linux="yes"

# Could try the dlfcn_win32 project for Windows support.
# I've not made it error if you try to force the issue
# in-case someone wants to install dlfcn_win32 manually.
HOST_SUPPORTS_PLUGINS_osx="yes"
HOST_SUPPORTS_PLUGINS_windows="no"
HOST_SUPPORTS_PLUGINS_linux="yes"

TARGET_BINUTILS_VERSIONS_osx="none"
TARGET_BINUTILS_VERSIONS_windows="2.24"
TARGET_BINUTILS_VERSIONS_linux="2.24"
TARGET_BINUTILS_VERSIONS_ps3="2.23.2"
TARGET_BINUTILS_VERSIONS_raspi="2.24"

TARGET_GCC_VERSIONS_osx="apple_5666.3"
TARGET_GCC_VERSIONS_windows="4.8.2"
TARGET_GCC_VERSIONS_linux="4.8.2"
TARGET_GCC_VERSIONS_ps3="4.7.0"
TARGET_GCC_VERSIONS_raspi="4.8.2"

TARGET_LLVM_VERSIONS_osx="none"
TARGET_LLVM_VERSIONS_windows="head"
#TARGET_LLVM_VERSIONS_windows="none"
TARGET_LLVM_VERSIONS_linux="none"
#TARGET_LLVM_VERSIONS_linux="head"
TARGET_LLVM_VERSIONS_ps3="none"
TARGET_LLVM_VERSIONS_raspi="none"

TARGET_COMPILER_RT_osx="yes"
TARGET_COMPILER_RT_windows="no"
#TARGET_COMPILER_RT_linux="yes"
TARGET_COMPILER_RT_linux="no"
TARGET_COMPILER_RT_ps3="no"
TARGET_COMPILER_RT_raspi="yes"

TARGET_IS_LINUX_osx="no"
TARGET_IS_LINUX_windows="no"
TARGET_IS_LINUX_linux="yes"
TARGET_IS_LINUX_ps3="no"
TARGET_IS_LINUX_raspi="yes"

TARGET_IS_DARWIN_osx="yes"
TARGET_IS_DARWIN_windows="no"
TARGET_IS_DARWIN_linux="no"
TARGET_IS_DARWIN_ps3="no"
TARGET_IS_DARWIN_raspi="no"

TARGET_LIBC_osx="none"
TARGET_LIBC_windows="none"
#TARGET_LIBC_linux="eglibc_V_2.18"
TARGET_LIBC_linux="glibc_V_2.15"
# This works ok:
#TARGET_LIBC_linux="glibc_V_2.18"
#TARGET_LIBC_linux="glibc_V_2.17"
#TARGET_LIBC_linux="glibc_V_2.16.0"
#TARGET_LIBC_linux="eglibc_V_2.18"
TARGET_LIBC_ps3="newlib"
TARGET_LIBC_raspi="eglibc_V_2.18"

# Stands for associative lookup!
_al()
{
  local _tmp=${1}_${2}
  echo ${!_tmp}
}

#########################################
# Simple option processing and options. #
#########################################
ALL_OPTIONS_TEXT=
ALL_OPTIONS=
option_to_var()
{
  echo $(echo $1 | tr '[a-z]' '[A-Z]' | tr '-' '_')
}
var_to_option()
{
  echo --$(echo $1 | tr '[A-Z]' '[a-z]' | tr '_' '-')
}
option()
{
  OPTION=$(var_to_option $1)
  if [ -n "$3" ]; then
    ALL_OPTIONS_TEXT=$ALL_OPTIONS_TEXT" $OPTION=$2\n $3\n\n"
  else
    ALL_OPTIONS_TEXT=$ALL_OPTIONS_TEXT" $OPTION=$2\n\n"
  fi
  ALL_OPTIONS="$ALL_OPTIONS "$1
  eval $1=$2
}
option_output_all()
{
  for OPTION in $ALL_OPTIONS; do
    OPTION_OUTPUT="$OPTION_OUTPUT $(var_to_option $OPTION)=${!OPTION}"
  done
  if [ ! $1 = "" ]; then
    echo -e "#!/bin/bash\n./$(basename $0)$OPTION_OUTPUT" > $1
  else
    echo -e "#!/bin/bash\n./$(basename $0)$OPTION_OUTPUT"
  fi
}
print_help()
{
  echo    "Simple build script to compile"
  echo    "a crosstool-ng Clang Darwin cross-compiler"
  echo    "and Firefox (ESR24 or mozilla-central)"
  echo    "by Ray Donnelly <mingw.android@gmail.com>"
  echo    ""
  echo -e "Options are (--option=default)\n\n$ALL_OPTIONS_TEXT"
}
##################################
# This set of options are global #
##################################
option TARGET_OS           osx \
"Target OS for the build, valid values are
osx, linux or windows. All toolchains built
are multilib enabled, so the arch is not
selected at the toolchain build stage."
######################################################
# This set of options are for the crosstool-ng build #
######################################################
option CTNG_PACKAGE        no \
"Make a package for the built cross compiler."
option CTNG_CLEAN          no \
"Remove old crosstool-ng build and artefacts
before starting the build, otherwise an old
crosstool-ng may be re-used."
option CTNG_SAVE_STEPS     default \
"Save steps so that they can be restarted
later. This doesn't work well for llvm
and clang unfortunately, but while iterating
on GCC it can save a lot of time.

To restart the build you can use:
 ct-ng STEP_NAME+ -> restart at STEP_NAME and continue
 ct-ng STEP_NAME  -> restart at STEP_NAME and stop just after
 ct-ng +STEP_NAME -> start from scratch, and stop just before STEP_NAME

To see all steps:
 ct-ng list-steps"
option CTNG_DEBUGGABLE     default \
"Do you want the toolchain built with crosstool-ng
to be debuggable? Currently, you can't build a GCC
with old-ish ISLs at -O2 on Windows. This was fixed
about a year ago."
option CTNG_LEGACY         yes \
"Do you want the toolchain built with crosstool-ng
to be built using stable, old compilers so that they
might run on older machines? In some cases, this will
disable 64bit builds - when build/host is OSX. In some
cases (Windows) it has no effect."
option CTNG_DEBUGGERS      default \
"Do you want the toolchain built with crosstool-ng
to include debuggers?"
option LLVM_VERSION        default \
"default, none, head, 3.3, 3.2, 3.1 or 3.0 (I test with 3.3 most,
then next, then the others hardly at all)."
option BINUTILS_VERSION    default \
"default, none, head, or a sensible Binutils version number."
option GCC_VERSION        default \
"default, none, head, or a sensible GCC version number."
option GNU_PLUGINS        default \
"Enable you want Binutils+GCC plugin support? Not available
on Windows hosts"
option COPY_SDK            yes \
"Do you want the MacOSX10.6.sdk copied from
\$HOME/MacOSX10.6.sdk to the sysroot of the
built toolchain?"
option COMPILER_RT         default \
"Compiler-rt allows for profiling, address
sanitization, coverage reporting and other
such runtime nicities, mostly un-tested, and
requires --copy-sdk=yes and (if on x86-64) a
symbolic link to be made from ..
\${HOME}/MacOSX10.6.sdk/usr/lib/gcc/i686-apple-darwin10
.. to ..
\${HOME}/MacOSX10.6.sdk/usr/lib/gcc/x86_64-apple-darwin10
before running this script."
option STATIC_TOOLCHAIN    no \
"Do you want a statically linked toolchain?
Plugins are not available if you say 'yes'.
Also crosstool-ng can't be built on OSX
if you say 'yes' here, though that needs
to be fixed, clearly!"
#################################################
# This set of options are for the Firefox build #
#################################################
option MOZ_CLEAN           no \
"Remove old Mozilla build and artefacts
before starting the build. Otherwise an
old build may be packaged."
option MOZ_VERSION         ESR24 \
"Which version of Firefox would you like?
Valid values are ESR24 or mozilla-central"
option MOZ_DEBUG           yes \
"Do you want to be able to debug the built
Firefox? - you'd need to copy the .o files to
an OS X machine or to run the entire thing on
one for this to be useful."
option MOZ_BUILD_IN_SRCDIR yes ""
option MOZ_TARGET_ARCH     i386 \
"Do you want the built firefox to be i386 or x86_64?
Note: cross compilers built to run on 32bit systems
can still target 64bit OS X and vice-versa, however
with 32bit build compilers, linking failures due to
a lack of address space will probably happen."
option MOZ_COMPILER        clang \
"Which compiler do you want to use, valid options
are clang and gcc"

# Check for command-line modifications to options.
while [ "$#" -gt 0 ]; do
  OPT="$1"
  case "$1" in
    --*=*)
      VAR=$(echo $1 | sed "s,^--\(.*\)=.*,\1,")
      VAL=$(echo $1 | sed "s,^--.*=\(.*\),\1,")
      VAR=$(option_to_var $VAR)
      eval "$VAR=\$VAL"
      ;;
    *help)
      print_help
      exit 0
      ;;
  esac
  shift
done
################################################
# For easier reproduction of the build results #
# and packaging of needed scripts and patches. #
# Includes log files to allow easy comparisons #
################################################
copy_build_scripts()
{
  [ -d $1 ] || mkdir $1
  option_output_all $1/regenerate.sh
  chmod +x $1/regenerate.sh
  cp     ${THISDIR}/build.sh ${THISDIR}/tar-sorted.sh ${THISDIR}/mingw-w64-toolchain.sh $1/
  cp -rf ${THISDIR}/mozilla.configs $1/
  cp -rf ${THISDIR}/crosstool-ng.configs $1/
  cp -rf ${THISDIR}/patches $1/
  [ -d $1/final-configs ] && rm -rf $1/final-configs
  mkdir $1/final-configs
  cp $CROSSTOOL_CONFIG $1/final-configs/.config
  cp $MOZILLA_CONFIG $1/final-configs/.mozconfig
  mkdir $1/logs
  cp ${BUILT_XCOMPILER_PREFIX}/build.log.bz2  $1/logs/
  cp $(dirname $MOZILLA_CONFIG)/configure.log $1/logs/
  cp $(dirname $MOZILLA_CONFIG)/build.log     $1/logs/
  cp $(dirname $MOZILLA_CONFIG)/package.log   $1/logs/
  echo "  ****************************  "        > $1/README
  echo "  * crosstool-ng and Firefox *  "       >> $1/README
  echo "  * build script and patches *  "       >> $1/README
  echo "  ****************************  "       >> $1/README
  echo ""                                       >> $1/README
  echo "To regenerate this Firefox cross"       >> $1/README
  echo "build run regenerate.sh"                >> $1/README
  echo ""                                       >> $1/README
  echo "To see options for making another"      >> $1/README
  echo "build run build.sh --help"              >> $1/README
  echo ""                                       >> $1/README
  echo "Some scripts and patches in this"       >> $1/README
  echo "folder structure won't be needed"       >> $1/README
  echo "to re-generate this exact build,"       >> $1/README
  echo "but may be used by other configs"       >> $1/README
  echo ""                                       >> $1/README
  echo "final-configs/ contains two files:"     >> $1/README
  echo ".config is the crosstool-ng config"     >> $1/README
  echo "after it has been created from one"     >> $1/README
  echo "of the more minimal sample configs"     >> $1/README
  echo ".mozconfig is the configuration of"     >> $1/README
  echo "the Firefox build."                     >> $1/README
  echo ""                                       >> $1/README
  echo "Comments/suggestions to:"               >> $1/README
  echo ""                                       >> $1/README
  echo "Ray Donnelly <mingw.android@gmail.com>" >> $1/README
}

BUILD_OS=
if [ "$OSTYPE" = "linux-gnu" ]; then
  BUILD_OS=linux
elif [ "$OSTYPE" = "msys" ]; then
  BUILD_OS=windows
  # I put a hack into MSYS2 in the interests of pragmatism
  # to allow arguments to be blacklisted from being converted
  # between their MSYS2 and Windows representations:
  export MSYS2_ARG_CONV_EXCL="-DNATIVE_SYSTEM_HEADER_DIR="
elif [ "$OSTYPE" = "darwin" ]; then
  BUILD_OS=darwin
  ulimit -n 4096
else
  echo "Error: I don't know what Operating System you are using."
  exit 1
fi

# Trying to force using old gcc-4.2 on OSX results in:
# /c/ctng-build-x-o-head-apple_5666_3-x86_64-235295c4/.build/src/gmp-5.1.1/configure --build=i686-build_apple-darwin11 --host=i686-build_apple-darwin11 --prefix=/c/ctng-build-x-o-head-apple_5666_3-x86_64-235295c4/.build/x86_64-apple-darwin10/buildtools --enable-fft --enable-mpbsd --enable-cxx --disable-shared --enable-static ABI=64
# ..
# uname -m = x86_64
# ..
# /usr/bin/uname -p = i386
# ..
# User:
# ABI=64
# CC=i686-build_apple-darwin11-gcc
# CFLAGS=-O2 -g -pipe -m64 -isysroot /Users/ray/MacOSX10.6.sdk -mmacosx-version-min=10.5 -DMAXOSX_DEPLOYEMENT_TARGET=10.5 -fexceptions
# CPPFLAGS=(unset)
# MPN_PATH=
# GMP:
# abilist=32
# cclist=gcc icc cc
# configure:5707: error: ABI=64 is not among the following valid choices: 32
# .. so for now, on Darwin
if [ "${HOST_ARCH}" = "i686" ]; then
  BITS=32
else
  if [ "${CTNG_LEGACY}" = "yes" -a "${BUILD_OS}" = "darwin" ]; then
    echo "Warning: You set --ctng-legacy=yes and are building on Darwin, due to GMP configure fail 32bit binaries will be built."
    BITS=32
  else
    BITS=64
  fi
fi

# TODO :: Support canadian cross compiles then remove this
HOST_OS=$BUILD_OS

# Sanitise options and lookup per-target/per-build defaults.
VENDOR_OS=$(_al VENDOR_OSES ${TARGET_OS})
if [ "$BINUTILS_VERSION" = "default" ]; then
  BINUTILS_VERSION=$(_al TARGET_BINUTILS_VERSIONS ${TARGET_OS})
fi
if [ "$GCC_VERSION" = "default" ]; then
  GCC_VERSION=$(_al TARGET_GCC_VERSIONS ${TARGET_OS})
fi
if [ "$LLVM_VERSION" = "default" ]; then
  LLVM_VERSION=$(_al TARGET_LLVM_VERSIONS ${TARGET_OS})
fi
if [ "$COMPILER_RT" = "default" ]; then
  COMPILER_VERSION=$(_al TARGET_COMPILER_RT ${TARGET_OS})
fi
if [ "$GNU_PLUGINS" = "default" ]; then
  GNU_PLUGINS=$(_al HOST_SUPPORTS_PLUGINS ${HOST_OS})
fi
if [ "$LLVM_VERSION" = "none" ]; then
  COMPILER_RT="no"
fi
if [ "$CTNG_SAVE_STEPS" = "default" ]; then
  CTNG_SAVE_STEPS=no
  if [ "$LLVM_VERSION" = "none" ]; then
    CTNG_SAVE_STEPS=yes
  fi
fi

if [ "$STATIC_TOOLCHAIN" = "yes" -a "$BUILD_OS" = "darwin" ]; then
  echo "Error: Crosstool-ng can't be built statically on OSX"
  echo "       You will get the following error message:"
  echo "       Checking that gcc can compile a trivial statically linked program (CT_WANTS_STATIC_LINK)"
  echo "       Fixing this is somewhere on my TODO list."
  exit 1
fi

BINUTILS_VERS_=$(echo $BINUTILS_VERSION  | tr '.' '_')
GCC_VERS_=$(echo $GCC_VERSION  | tr '.' '_')
LLVM_VERS_=$(echo $LLVM_VERSION | tr '.' '_')

if [ "$CTNG_DEBUGGABLE" = "default" ]; then
  CTNG_DEBUGGABLE=$(_al BUILD_DEBUGGABLE ${BUILD_OS})
fi

if [ "$CTNG_DEBUGGERS" = "default" ]; then
  CTNG_DEBUGGERS=$(_al BUILD_DEBUGGERS ${BUILD_OS})
fi

# Error checking
if [ "${MOZ_TARGET_ARCH}" = "i686" -a "${TARGET_OS}" = "osx" ]; then
  echo "Warning: You set --moz-target-arch=i686, but that's not a valid ${TARGET_OS} arch, changing this to i386 for you."
  MOZ_TARGET_ARCH=i386
elif [ "${MOZ_TARGET_ARCH}" = "i386" -a "${TARGET_OS}" != "osx" ]; then
  echo "Warning: You set --moz-target-arch=i386, but that's not a valid ${TARGET_OS} arch, changing this to i686 for you."
  MOZ_TARGET_ARCH=i686
fi

# Check that compiler-rt can be built if requested.
if [ "$COMPILER_RT" = "yes" -a "$TARGET_OS" = "osx" ]; then
  if [ ! -d $HOME/MacOSX10.6.sdk/usr/lib/gcc/x86_64-apple-darwin10 ]; then
    if [ "${BITS}" = "64" ]; then
      echo -n "Error: You are trying to build x86_64 hosted cross compilers. Due to
some host/target confusion you need to make a link from ..
\${HOME}/MacOSX10.6.sdk/usr/lib/gcc/i686-apple-darwin10
.. to ..
\${HOME}/MacOSX10.6.sdk/usr/lib/gcc/x86_64-apple-darwin10
.. please do this and then re-run this script."
      exit 1
    fi
  fi
  if [ "$COPY_SDK" = "no" -a "$TARGET_OS" = "osx" ]; then
    echo "Error: You are trying to build compiler-rt but without --copy-sdk=yes. This is currently broken
as there's no way to pass the SDK's location into the build of compiler-rt."
    exit 1
  fi
fi




LIBC=$(_al TARGET_LIBC ${TARGET_OS})

# The first part of CROSSCC is HOST_ARCH and the compilers are
# built to run on that architecture of the host OS. They will
# generally be multilib though, so MOZ_TARGET_ARCH gets used for
# all target folder names. CROSSCC is *only* used as part of
# the filenames for the compiler components.
CROSSCC=${HOST_ARCH}-${VENDOR_OS}

# Before building compiler-rt with 10.6.sdk, we need to:
# pushd /home/ray/x-tools/x86_64-apple-darwin10/x86_64-apple-darwin10/sysroot/usr/lib
# ln -s i686-apple-darwin10 x86_64-apple-darwin10
# .. as otherwise libstdc++.dylib is not found.

SUDO=sudo
GROUP=$USER
if [ "${OSTYPE}" = "darwin" ]; then
  BREWFIX=/usr/local
  GNUFIX=$BREWFIX/bin/g
  CC=clang
  CXX=clang++
#  CC=llvm-gcc
#  CXX=llvm-g++
  # To install gperf 3.0.4 I did:
  set +e
  if ! which brew; then
    ruby -e "$(curl -fsSL https://raw.github.com/mxcl/homebrew/go/install)"
  fi
  brew tap homebrew/dupes
  brew install homebrew/dupes/gperf
  GPERF=${BREWFIX}/Cellar/gperf/3.0.4/bin/gperf
  brew tap homebrew/versions
  brew install mercurial gnu-sed gnu-tar grep wget gawk binutils libelf coreutils automake gperf yasm homebrew/versions/autoconf213
  set -e
elif [ "${OSTYPE}" = "linux-gnu" -o "${OSTYPE}" = "msys" ]; then
  if [ "${OSTYPE}" = "msys" ]; then
    if [ ! "${MSYSTEM}" = "MSYS" ]; then
      echo "Please use an MSYS shell, not a MinGW one, i.e. \$MSYSTEM should be \"MSYS\""
      exit 1
    fi
    SUDO=
  fi
  CC=gcc
  CXX=g++
  if [ -f /etc/arch-release -o "${OSTYPE}" = "msys" ]; then
    if [ -f /etc/arch-release ]; then
      HOST_MULTILIB="-multilib"
    fi
    PACKAGES="openssh git python2 tar mercurial gcc${HOST_MULTILIB} libtool${HOST_MULTILIB} wget p7zip unzip zip yasm svn"
    # ncurses for Arch Linux vs ncurses-devel for MSYS is Alexey's fault ;-)
    # .. he has split packages up more than Arch does, so there is not a 1:1
    #    relationship between them anymore.
    if [ -f /etc/arch-release ]; then
      PACKAGES=$PACKAGES" ncurses gcc-ada${HOST_MULTILIB} automake"
    else
      PACKAGES=$PACKAGES" ncurses-devel base-devel perl-ack tar"
    fi
    echo "Force intalling $PACKAGES"
    echo "disabling errors as 'automake and automake-wrapper are in conflict' - remove this ASAP."
    set +e
    ${SUDO} pacman -S --force --needed --noconfirm $PACKAGES
    set -e
    GROUP=$(id --group --name)
    if ! which autoconf2.13; then
     (
      pushd /tmp
      curl -SLO http://ftp.gnu.org/gnu/autoconf/autoconf-2.13.tar.gz
      tar -xf autoconf-2.13.tar.gz
      cd autoconf-2.13
      ./configure --prefix=/usr/local --program-suffix=2.13 && make && ${SUDO} make install
     )
    fi
  else
    ${SUDO} apt-get install git mercurial curl bison flex gperf texinfo gawk libtool automake ncurses-dev g++ autoconf2.13 yasm python-dev
  fi
else
  SUDO=
fi

       SED=${GNUFIX}sed
   LIBTOOL=${GNUFIX}libtool
LIBTOOLIZE=${GNUFIX}libtoolize
   OBJCOPY=${GNUFIX}objcopy
   OBJDUMP=${GNUFIX}objdump
   READELF=${GNUFIX}readelf
       TAR=${GNUFIX}tar

firefox_download()
{
  if [ "${MOZ_VERSION}" = "ESR24" ]; then
    FFTARBALLURL=https://ftp.mozilla.org/pub/mozilla.org/firefox/releases/24.1.0esr/source/firefox-24.1.0esr.source.tar.bz2
    FFTRUNKURL=https://hg.mozilla.org/mozilla-central
    FFTARBALL=$(basename "${FFTARBALLURL}")
    [ -f "${FFTARBALL}" ] || curl -SLO "${FFTARBALLURL}"
    [ -d "mozilla-esr24" ] || tar -xf "${FFTARBALL}"
    echo "mozilla-esr24"
  elif [ "${MOZ_VERSION}" = "mozilla-central" ]; then
    [ -d mozilla-central ] || hg clone https://hg.mozilla.org/mozilla-central
    pushd mozilla-central > /dev/null 2>&1
    hg pull > /dev/null 2>&1
    hg update > /dev/null 2>&1
    popd > /dev/null 2>&1
    echo "mozilla-central"
  else
    echo "Error: I don't know what Firefox version ${MOZ_VERSION} is."
    exit 1
  fi
}

firefox_patch()
{
  UNPATCHED=$1
  if [ "${MOZ_CLEAN}" = "yes" ]; then
    [ -d ${UNPATCHED}${BUILDDIRSUFFIX} ] && rm -rf ${UNPATCHED}${BUILDDIRSUFFIX}
  fi
  if [ ! -d ${UNPATCHED}${BUILDDIRSUFFIX} ]; then
    if [ "$MOZ_VERSION" = "mozilla-central" ]; then
      pushd ${UNPATCHED}
      hg archive ../${UNPATCHED}${BUILDDIRSUFFIX}
      popd
    else
      cp -rf ${UNPATCHED} ${UNPATCHED}${BUILDDIRSUFFIX}
    fi
    pushd ${UNPATCHED}${BUILDDIRSUFFIX}
    if [ -d "${THISDIR}/patches/${MOZ_VERSION}" ]; then
      PATCHES=$(find "${THISDIR}/patches/${MOZ_VERSION}" -name "*.patch" | sort)
      for PATCH in $PATCHES; do
        echo "Applying $PATCH"
        patch -p1 < $PATCH
      done
    fi
    popd
  fi
}

do_sed()
{
    if [[ "${OSTYPE}" = "darwin" ]]
    then
        if [[ ! $(which gsed) ]]
        then
            sed -i '.bak' "$1" $2
            rm ${2}.bak
        else
            gsed "$1" -i $2
        fi
    else
        sed "$1" -i $2
    fi
}

#OSXSDKURL="http://packages.siedler25.org/pool/main/a/apple-uni-sdk-10.6/apple-uni-sdk-10.6_20110407.orig.tar.gz"
OSXSDKURL="https://launchpad.net/~flosoft/+archive/cross-apple/+files/apple-uni-sdk-10.6_20110407.orig.tar.gz"

download_sdk()
{
  [ -d "${HOME}"/MacOSX10.6.sdk ] || ( cd "${HOME}"; curl -C - -SLO $OSXSDKURL; tar -xf apple-uni-sdk-10.6_20110407.orig.tar.gz ; mv apple-uni-sdk-10.6.orig/MacOSX10.6.sdk . )
}

MINGW_W64_HASH=
MINGW_W64_PATH=

USED_CC=gcc
USED_CXX=g++
USED_LD=ld
USED_LD_FLAGS=
USED_CPP_FLAGS=
CT_BUILD_SUFFIX=
CT_BUILD_PREFIX=

download_build_compilers()
{
  USED_CPP_FLAGS="-m${BITS}"
  USED_LD_FLAGS="-m${BITS}"

  if [ "$OSTYPE" = "msys" ]; then
    . ${THISDIR}/mingw-w64-toolchain.sh --arch=$HOST_ARCH --root=$PWD --path-out=MINGW_W64_PATH --hash-out=MINGW_W64_HASH --enable-verbose --enable-hash-in-path
  elif [ "$OSTYPE" = "darwin" ]; then
    if [ "${CTNG_LEGACY}" = "yes" ]; then
#    # I'd like to get a hash for all other compilers too .. for now, just so my BeyondCompare sessions are less noisy, pretend they all have the hash I use most often.
#    [ -d $PWD/apple-osx ] ||
#    (
#      wget -c https://mingw-and-ndk.googlecode.com/files/multiarch-darwin11-cctools127.2-gcc42-5666.3-llvmgcc42-2336.1-Darwin-120615.7z
#      7za x multiarch-darwin11-cctools127.2-gcc42-5666.3-llvmgcc42-2336.1-Darwin-120615.7z
#    )
#    MINGW_W64_PATH=$PWD/apple-osx/bin
#    USED_CC=i686-apple-darwin11-gcc
#    USED_CXX=i686-apple-darwin11-g++
#    USED_LD=i686-apple-darwin11-ld
#    MINGW_W64_HASH=tc4-gcc-42
    USED_CC=gcc-4.2
    USED_CXX=g++-4.2
    USED_LD=ld
    CT_BUILD_SUFFIX=-4.2
    # Homebrew's gcc-4.2 doesn't work with MacOSX10.6.sdk, error is: MacOSX10.6.sdk/usr/include/varargs.h:4:26: error: varargs.h: No such file or directory
    # it's an include_next thing, so that GCC has no varargs.h I guess. Trying with 10.7 instead.
    USED_CPP_FLAGS=$USED_CPP_FLAGS" -isysroot $HOME/MacOSX10.7.sdk -mmacosx-version-min=10.5 -DMAXOSX_DEPLOYEMENT_TARGET=10.5"
    USED_LD_FLAGS=$USED_LD_FLAGS" -isysroot $HOME/MacOSX10.7.sdk -mmacosx-version-min=10.5 -DMAXOSX_DEPLOYEMENT_TARGET=10.5"
#    USED_LD_FLAGS=$USED_LD_FLAGS" -syslibroot $HOME/MacOSX10.7.sdk -mmacosx-version-min=10.5"
    MINGW_W64_HASH=hb-gcc-42
    fi
  else
    MINGW_W64_HASH=213be3fb
  fi
  if [ -n "$MINGW_W64_HASH" ]; then
     MINGW_W64_HASH=-${MINGW_W64_HASH}
  fi
}

cross_clang_build()
{
  CTNG_CFG_ARGS=" \
                --disable-local \
                --prefix=$PWD/${INSTALLDIR} \
                --with-libtool=$LIBTOOL \
                --with-libtoolize=$LIBTOOLIZE \
                --with-objcopy=$OBJCOPY \
                --with-objdump=$OBJDUMP \
                --with-readelf=$READELF \
                --with-gperf=$GPERF \
                CC=${USED_CC} CXX=${USED_CXX} LD=${USED_LD}"

  CROSSTOOL_CONFIG=${PWD}/${BUILDDIR}/.config
  if [ "${CTNG_CLEAN}" = "yes" ]; then
    [ -d ${BUILT_XCOMPILER_PREFIX} ] && rm -rf ${BUILT_XCOMPILER_PREFIX}
    [ -d crosstool-ng ]              && rm -rf crosstool-ng
    [ -d ${BUILDDIR} ]               && rm -rf ${BUILDDIR}
  fi
  if [ ! -f ${BUILT_XCOMPILER_PREFIX}/bin/${CROSSCC}-clang ]; then
    [ -d "${HOME}"/src ] || mkdir "${HOME}"/src
    [ -d crosstool-ng ] ||
     (
      git clone https://github.com/diorcety/crosstool-ng.git
      pushd crosstool-ng
      if [ -d "${THISDIR}/patches/crosstool-ng" ]; then
        PATCHES=$(find "${THISDIR}/patches/crosstool-ng" -name "*.patch" | sort)
        for PATCH in $PATCHES; do
          git am $PATCH
#           patch -p1 < $PATCH
        done
      fi
      popd
     ) || ( echo "Error: Failed to clone/patch crosstool-ng" && exit 1 )
    pushd crosstool-ng
    CTNG_SAMPLE=mozbuild-${TARGET_OS}-${BITS}
    CTNG_SAMPLE_CONFIG=samples/${CTNG_SAMPLE}/crosstool.config
    [ -d samples/${CTNG_SAMPLE} ] || mkdir -p samples/${CTNG_SAMPLE}
    cp "${THISDIR}"/crosstool-ng.configs/crosstool.config.${TARGET_OS}.${BITS} ${CTNG_SAMPLE_CONFIG}
    LLVM_VERSION_DOT=$(echo $LLVM_VERSION | tr '_' '.')
    echo "CT_LLVM_V_${LLVM_VERSION}"           >> ${CTNG_SAMPLE_CONFIG}
    if [ -n "$MINGW_W64_PATH" -o -n ${USED_CC} ]; then
      if [ -n "$MINGW_W64_PATH" ]; then
        DUMPEDMACHINE=$(${MINGW_W64_PATH}/${USED_CC} -dumpmachine)
      else
        DUMPEDMACHINE=$(${USED_CC} -dumpmachine)
      fi
      echo "CT_BUILD=\"${DUMPEDMACHINE}\""     >> ${CTNG_SAMPLE_CONFIG}
    fi
    if [ -n "$CT_BUILD_PREFIX" ]; then
      echo "CT_BUILD_PREFIX=\"${CT_BUILD_PREFIX}\"" >> ${CTNG_SAMPLE_CONFIG}
    fi
    if [ -n "$CT_BUILD_SUFFIX" ]; then
      echo "CT_BUILD_SUFFIX=\"${CT_BUILD_SUFFIX}\"" >> ${CTNG_SAMPLE_CONFIG}
    fi

    if [ "$(_al TARGET_IS_DARWIN ${TARGET_OS})" = "yes" ]; then
      if [ "$COPY_SDK" = "yes" ]; then
        echo "CT_DARWIN_COPY_SDK_TO_SYSROOT=y" >> ${CTNG_SAMPLE_CONFIG}
      else
        echo "CT_DARWIN_COPY_SDK_TO_SYSROOT=n" >> ${CTNG_SAMPLE_CONFIG}
      fi
    fi

    if [ "$(_al TARGET_IS_DARWIN ${TARGET_OS})" = "yes" ]; then
      echo "CT_BINUTILS_cctools=y"             >> ${CTNG_SAMPLE_CONFIG}
      echo "CT_CCTOOLS_V_809=y"                >> ${CTNG_SAMPLE_CONFIG}
      if [ ! "$GCC_VERSION" = "none" ]; then
        echo "CT_CC_GCC_APPLE=y"               >> ${CTNG_SAMPLE_CONFIG}
      fi
      # If clang wasn't requested (yeah, LLVM_VERISON is badly named!)
      # then we need to avoid using clang head as it's often broken.
      if [ "$LLVM_VERSION" = "none" ]; then
        echo "CT_LLVM_V_3_4=y"         >> ${CTNG_SAMPLE_CONFIG}
      fi
    else
      echo "CT_BINUTILS_binutils=y"            >> ${CTNG_SAMPLE_CONFIG}
      echo "CT_BINUTILS_V_${BINUTILS_VERS_}=y" >> ${CTNG_SAMPLE_CONFIG}
      echo "CT_BINUTILS_FOR_TARGET=y"          >> ${CTNG_SAMPLE_CONFIG}
      # The following may only work correctly for non-cross builds, but
      # actually it's in GCC that PLUGINS are likely to fail with cross.
      if [ "$STATIC_TOOLCHAIN" = "no" -a "$GNU_PLUGINS" = "yes" ]; then
        echo "CT_BINUTILS_PLUGINS=y"           >> ${CTNG_SAMPLE_CONFIG}
      else
        echo "CT_BINUTILS_PLUGINS=n"           >> ${CTNG_SAMPLE_CONFIG}
      fi
    fi

    if [ ! "$GCC_VERSION" = "none" ]; then
      echo "CT_CC_gcc=y"                       >> ${CTNG_SAMPLE_CONFIG}
      echo "CT_CC_GCC_V_${GCC_VERS_}=y"        >> ${CTNG_SAMPLE_CONFIG}
      echo "CT_CC_LANG_CXX=y"                  >> ${CTNG_SAMPLE_CONFIG}
      echo "CT_CC_LANG_CXX=y"                  >> ${CTNG_SAMPLE_CONFIG}
      echo "CT_CC_LANG_OBJC=y"                 >> ${CTNG_SAMPLE_CONFIG}
      echo "CT_CC_LANG_OBJCXX=y"               >> ${CTNG_SAMPLE_CONFIG}
      if [ "$STATIC_TOOLCHAIN" = "no" -a "$GNU_PLUGINS" = "yes" ]; then
        echo "CT_CC_GCC_ENABLE_PLUGINS=y"      >> ${CTNG_SAMPLE_CONFIG}
      else
        echo "CT_CC_GCC_ENABLE_PLUGINS=n"      >> ${CTNG_SAMPLE_CONFIG}
      fi
    fi

    NATURE="CROSS"
    if [ "${BUILD_OS}" = "linux" -a "${TARGET_OS}" = "linux" ]; then
      NATURE="NATIVE"
    elif  [ "${BUILD_OS}" = "windows" -a "${TARGET_OS}" = "windows" ]; then
      NATURE="NATIVE"
    elif [ "${BUILD_OS}" = "darwin" -a "${TARGET_OS}" = "osx" ]; then
      NATURE="NATIVE"
    fi
    echo "CT_${NATURE}=y"                      >> ${CTNG_SAMPLE_CONFIG}
    echo "CT_TOOLCHAIN_TYPE=\"$(echo $NATURE | tr 'A-Z' 'a-z')\"" >> ${CTNG_SAMPLE_CONFIG}

    # CT_LIBC="eglibc"
    # CT_LIBC_VERSION="2_18"
    # CT_LIBC_eglibc=y

    LIBC_FAMILY=${LIBC%%_*}
    echo "CT_LIBC_${LIBC_FAMILY}=y"                  >> ${CTNG_SAMPLE_CONFIG}
    if [ "$LIBC_FAMILY" = "eglibc" \
      -o "$LIBC_FAMILY" = "glibc" ]; then
      echo "CT_LIBC=\"${LIBC_FAMILY}\""              >> ${CTNG_SAMPLE_CONFIG}
      LIBC_VERS=${LIBC/${LIBC_FAMILY}_V_/}
      # For some reason eglibc versions need _'s instead of .'s
      if [ "$LIBC_FAMILY" = "eglibc" ]; then
        LIBC_VERS=$(echo ${LIBC_VERS} | tr '.' '_')
      fi
      LIBCU_=$(echo ${LIBC} | tr '.' '_' | tr 'a-z' 'A-Z')
      echo "CT_LIBC_${LIBCU_}=y"                     >> ${CTNG_SAMPLE_CONFIG}
      echo "CT_LIBC_VERSION=\"${LIBC_VERS}\""        >> ${CTNG_SAMPLE_CONFIG}
    fi

    if [ ! "$LLVM_VERSION" = "none" ]; then
      echo "CT_LLVM_V_${LLVM_VERS_}=y"         >> ${CTNG_SAMPLE_CONFIG}
      echo "CT_CC_clang=y"                     >> ${CTNG_SAMPLE_CONFIG}
      if [ "$COMPILER_RT" = "yes" ]; then
        echo "CT_LLVM_COMPILER_RT=y"           >> ${CTNG_SAMPLE_CONFIG}
      else
        echo "CT_LLVM_COMPILER_RT=n"           >> ${CTNG_SAMPLE_CONFIG}
      fi
    fi

    if [ -n "$USED_CPP_FLAGS" ]; then
      echo "CT_EXTRA_CFLAGS_FOR_HOST=\"${USED_CPP_FLAGS}\""  >> ${CTNG_SAMPLE_CONFIG}
      echo "CT_EXTRA_CFLAGS_FOR_BUILD=\"${USED_CPP_FLAGS}\"" >> ${CTNG_SAMPLE_CONFIG}
    fi

    if [ -n "$USED_LD_FLAGS" ]; then
      echo "CT_EXTRA_LDFLAGS_FOR_HOST=\"${USED_LD_FLAGS}\""  >> ${CTNG_SAMPLE_CONFIG}
      echo "CT_EXTRA_LDFLAGS_FOR_BUILD=\"${USED_LD_FLAGS}\"" >> ${CTNG_SAMPLE_CONFIG}
    fi

    # Gettext fails to build on Windows at -O0. One of the patches:
    # gettext/0.18.3.1/120-Fix-Woe32-link-errors-when-compiling-with-O0.patch
    # .. should have fixed this but it still doesn't work ..)
    if [ "$CTNG_DEBUGGABLE" = "yes" ]; then
      echo "CT_DEBUGGABLE_TOOLCHAIN=y"     >> ${CTNG_SAMPLE_CONFIG}
    else
      echo "CT_DEBUGGABLE_TOOLCHAIN=n"     >> ${CTNG_SAMPLE_CONFIG}
    fi

    if [ "$CTNG_SAVE_STEPS" = "yes" ]; then
      echo "CT_DEBUG_CT=y"                 >> ${CTNG_SAMPLE_CONFIG}
      echo "CT_DEBUG_CT_SAVE_STEPS=y"      >> ${CTNG_SAMPLE_CONFIG}
      echo "CT_DEBUG_CT_SAVE_STEPS_GZIP=y" >> ${CTNG_SAMPLE_CONFIG}
    fi

#    if [ "$OSTYPE" = "msys" ]; then
    # Verbosity 2 doesn't output anything when installing the kernel headers?!
    echo "CT_KERNEL_LINUX_VERBOSITY_1=y"   >> ${CTNG_SAMPLE_CONFIG}
    echo "CT_KERNEL_LINUX_VERBOSE_LEVEL=1" >> ${CTNG_SAMPLE_CONFIG}
    echo "CT_PARALLEL_JOBS=9"              >> ${CTNG_SAMPLE_CONFIG}
    echo "CT_gettext=y"                    >> ${CTNG_SAMPLE_CONFIG}
    # gettext is needed for {e}glibc-2_18; but not just on Windows!
    echo "CT_gettext_VERSION=0.18.3.1"     >> ${CTNG_SAMPLE_CONFIG}

    if [ "$CTNG_DEBUGGERS" = "yes" ]; then
      echo "CT_DEBUG_gdb=y"                >> ${CTNG_SAMPLE_CONFIG}
      echo "CT_GDB_CROSS=y"                >> ${CTNG_SAMPLE_CONFIG}
      echo "CT_GDB_CROSS_PYTHON=y"         >> ${CTNG_SAMPLE_CONFIG}
      echo "CT_GDB_V_7_6_1=y"              >> ${CTNG_SAMPLE_CONFIG}
    fi

    if [ "$STATIC_TOOLCHAIN" = "no" ]; then
      echo "CT_WANTS_STATIC_LINK=n"        >> ${CTNG_SAMPLE_CONFIG}
      echo "CT_STATIC_TOOLCHAIN=n"         >> ${CTNG_SAMPLE_CONFIG}
      echo "CT_CC_GCC_STATIC_LIBSTDCXX=n"  >> ${CTNG_SAMPLE_CONFIG}
    else
      echo "CT_WANTS_STATIC_LINK=y"        >> ${CTNG_SAMPLE_CONFIG}
      echo "CT_STATIC_TOOLCHAIN=y"         >> ${CTNG_SAMPLE_CONFIG}
      echo "CT_CC_GCC_STATIC_LIBSTDCXX=y"  >> ${CTNG_SAMPLE_CONFIG}
    fi
    echo "CT_PREFIX_DIR=\"${BUILT_XCOMPILER_PREFIX}\""  >> ${CTNG_SAMPLE_CONFIG}
    echo "CT_INSTALL_DIR=\"${BUILT_XCOMPILER_PREFIX}\"" >> ${CTNG_SAMPLE_CONFIG}

    ./bootstrap && ./configure ${CTNG_CFG_ARGS} && make clean && make && make install
    if [ -n "$MINGW_W64_PATH" ]; then
      export PATH="${MINGW_W64_PATH}:${PATH}"
    fi
    export PATH="${PATH}":$ROOT/${INSTALLDIR}/bin
    popd
    [ -d ${BUILDDIR} ] || mkdir ${BUILDDIR}
    pushd ${BUILDDIR}
    # Horrible hack to prevent cctools autoreconf from hanging on
    # Ubuntu 12.04.3 .. Sorry.
    # If you get a freeze at "[EXTRA]    Patching 'cctools-809'" then
    # this *might* fix it!
    if [ -f /etc/debian_version ]; then
     trap 'kill $(jobs -pr)' SIGINT SIGTERM EXIT
     ( while [ 0 ] ; do COLM=$(ps aux | grep libtoolize | grep --invert-match grep | awk '{print $2}'); if [ -n "${COLM}" ]; then kill $COLM; echo $COLM; fi; sleep 10; done ) &
    fi
    ct-ng ${CTNG_SAMPLE}
    ct-ng build
    popd
  else
    if [ -n "$MINGW_W64_PATH" ]; then
      export PATH="${MINGW_W64_PATH}:${PATH}"
    fi
  fi
}

cross_clang_package()
{
  if [ "$CTNG_PACKAGE" = "yes" ]; then
    TARFILE=crosstool-ng-${BUILD_PREFIX}-${OSTYPE}-${HOST_ARCH}${MINGW_W64_HASH}.tar.xz
    if [ ! -f ${THISDIR}/${TARFILE} ]; then
      pushd $(dirname ${BUILT_XCOMPILER_PREFIX}) > /dev/null 2>&1
      ${THISDIR}/tar-sorted.sh -cjf ${TARFILE} $(basename ${BUILT_XCOMPILER_PREFIX}) build-scripts --exclude="lib/*.a"
      mv ${TARFILE} ${THISDIR}
      popd
    fi
  fi
}

firefox_build()
{
  DEST=${SRC}${BUILDDIRSUFFIX}
  # OBJDIR is relative to @TOPSRCDIR@ (which is e.g. mozilla-esr24.patched)
  # so have top level objdir as a sibling of that.
  OBJDIR=../obj-moz-${VENDOR_OS}-${MOZ_TARGET_ARCH}
  MOZILLA_CONFIG=${PWD}/${DEST}/.mozconfig
  if [ "${MOZ_CLEAN}" = "yes" -a "${MOZ_BUILD_IN_SRCDIR}" = "no" ]; then
    [ -d ${DEST} ] && rm -rf ${DEST}
  fi
  if [ ! -d ${DEST}/${OBJDIR}/dist/firefox/Firefox${MOZBUILDSUFFIX}.app ]; then
    [ -d ${DEST} ] || mkdir -p ${DEST}
    pushd ${DEST}
    cp "${THISDIR}"/mozilla.configs/mozconfig.${TARGET_OS}            .mozconfig
    do_sed $"s/TARGET_ARCH=/TARGET_ARCH=${MOZ_TARGET_ARCH}/g"         .mozconfig
    do_sed $"s/HOST_ARCH=/HOST_ARCH=${HOST_ARCH}/g"                   .mozconfig
    do_sed $"s/VENDOR_OS=/VENDOR_OS=${VENDOR_OS}/g"                   .mozconfig
    do_sed $"s#TC_STUB=#TC_STUB=${BUILT_XCOMPILER_PREFIX}/bin/${CROSSCC}#g" .mozconfig
    do_sed $"s#OBJDIR=#OBJDIR=${OBJDIR}#g"                            .mozconfig
    TC_PATH_PREFIX=
    if [ "${MOZ_COMPILER}" = "clang" ]; then
      do_sed $"s/CCOMPILER=/CCOMPILER=clang/g"                        .mozconfig
      do_sed $"s/CXXCOMPILER=/CXXCOMPILER=clang++/g"                  .mozconfig
    else
      do_sed $"s/CCOMPILER=/CCOMPILER=gcc/g"                          .mozconfig
      do_sed $"s/CXXCOMPILER=/CXXCOMPILER=g++/g"                      .mozconfig
    fi

    if [ "$MOZ_DEBUG" = "yes" ]; then
      echo "ac_add_options --enable-debug"          >> .mozconfig
      echo "ac_add_options --disable-optimize"      >> .mozconfig
      echo "ac_add_options --disable-install-strip" >> .mozconfig
      echo "ac_add_options --enable-debug-symbols"  >> .mozconfig
    else
      echo "ac_add_options --disable-debug"         >> .mozconfig
      echo "ac_add_options --enable-optimize"       >> .mozconfig
    fi
    popd

    pushd ${DEST}
      echo "Configuring, to see log, tail -F ${PWD}/configure.log from another terminal"
      time make -f ${PWD}/../${SRC}/client.mk configure > configure.log 2>&1 || ( echo "configure failed, see ${PWD}/configure.log" ; exit 1 )
      echo "Building, to see log, tail -F ${PWD}/build.log from another terminal"
      time make -f ${PWD}/../${SRC}/client.mk build     > build.log 2>&1 || ( echo "build failed, see ${PWD}/build.log" ; exit 1 )
      echo "Packaging, to see log, tail -F ${PWD}/package.log from another terminal"
      time make -C obj-macos package INNER_MAKE_PACKAGE=true > package.log 2>&1 || ( echo "package failed, see ${PWD}/package.log" ; exit 1 )
    popd
  fi
}

firefox_package()
{
  pushd ${DEST}
    pushd obj-macos/dist/firefox
      TARFILE=Firefox${MOZBUILDSUFFIX}-${MOZ_VERSION}-darwin-${MOZ_TARGET_ARCH}.app-built-on-${OSTYPE}-${HOST_ARCH}${MINGW_W64_HASH}-clang-${LLVM_VERSION}-${HOSTNAME}-$(date +%Y%m%d).tar.bz2
      [ -f ${TARFILE} ] && rm -f ${TARFILE}
      REGEN_DIR=$PWD/build-scripts
      copy_build_scripts $REGEN_DIR
      ${THISDIR}/tar-sorted.sh -cjf ${TARFILE} Firefox${MOZBUILDSUFFIX}.app build-scripts
      mv ${TARFILE} ${THISDIR}
      echo "All done!"
      echo "ls -l ${THISDIR}/${TARFILE}"
      ls -l ${THISDIR}/${TARFILE}
    popd
  popd
}

ROOT=$PWD
download_build_compilers

if [ "${OSTYPE}" = "msys" ]; then
  export PYTHON=$MINGW_W64_PATH/../opt/bin/python.exe
else
  export PYTHON=python2
fi

if [ "$CTNG_DEBUGGABLE" = "yes" ]; then
  DEBUG_PREFIX="-d"
else
  DEBUG_PREFIX=""
fi

#BUILD_PREFIX=${LLVM_VERS_}-${GCC_VERS_}-${HOST_ARCH}${MINGW_W64_HASH}${DEBUG_PREFIX}
# While I'm figuring out glibc 2.15 problems with multiarch / stubs installation ..
BUILD_PREFIX=${LIBC}-${HOST_ARCH}${MINGW_W64_HASH}${DEBUG_PREFIX}
if [ "$COMPILER_RT" = "yes" ]; then
  BUILD_PREFIX="${BUILD_PREFIX}-rt"
fi

#STUB=x-$(_al TARGET_TO_PREFIX $TARGET_OS)
STUB=$(_al TARGET_TO_PREFIX $TARGET_OS)
if [ "$OSTYPE" = "msys" ]; then
  # Avoid over-long build paths on Windows, a real-world example:
  # echo "C:/msys64/home/ray/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-gettext-build-x86_64-build_w64-mingw32/gettext-tools/gnulib-lib/.libs/libgettextlib.lax/libcroco_rpl.a/libcroco_rpl_la-cr-additional-sel.o" | wc -c
  # 263.
  BUILDDIR=/c/b${STUB}
else
  BUILDDIR=ctng-build-${STUB}-${BUILD_PREFIX}
fi
#BUILDDIR=/c/ctng-build-${STUB}-${BUILD_PREFIX}
BUILDDIR=/c/b${STUB}
INTALLDIR=ctng-install-${STUB}-${BUILD_PREFIX}
BUILT_XCOMPILER_PREFIX=$PWD/${STUB}-${BUILD_PREFIX}

ROOT=$PWD
#download_sdk
cross_clang_build
cross_clang_package

export PATH="${PATH}":${BUILT_XCOMPILER_PREFIX}/bin

if [ "$MOZ_DEBUG" = "yes" ]; then
  BUILDSUFFIX=${LLVM_VERSION}-${MOZ_TARGET_ARCH}-dbg${MINGW_W64_HASH}
  MOZBUILDSUFFIX=Debug
else
  BUILDSUFFIX=${LLVM_VERSION}-${MOZ_TARGET_ARCH}-rel${MINGW_W64_HASH}
  MOZBUILDSUFFIX=
fi

if [ "$MOZ_BUILD_IN_SRCDIR" = "yes" ]; then
  BUILDDIRSUFFIX=.patched-${BUILDSUFFIX}
else
  BUILDDIRSUFFIX=${BUILDSUFFIX}
fi

exit 0

#echo "About to download Firefox ($MOZ_VERSION)"
#SRC=$(firefox_download)
#echo "About to patch Firefox ($MOZ_VERSION)"
#firefox_patch "${SRC}"
#echo "About to build Firefox ($MOZ_VERSION)"
#firefox_build
#echo "About to package Firefox ($MOZ_VERSION)"
#firefox_package
echo "All done!"
exit 0
















































































































































































































# Here be nonsense; scratch area for things I'd otherwise forget. Ignore.

cd libstuff && /Applications/Xcode.app/Contents/Developer/usr/bin/make

pushd /Users/raydonnelly/tbb-work/ctng-build/.build/x86_64-apple-darwin10/build/build-cctools-host-x86_64-build_apple-darwin13.0.0/libstuff

x86_64-build_apple-darwin13.0.0-gcc   -DHAVE_CONFIG_H    -I../include -I/Users/raydonnelly/tbb-work/ctng-build/.build/src/cctools-809/include -include ../include/config.h  -O2 -g -pipe  -I/Users/raydonnelly/tbb-work/ctng-build/.build/x86_64-apple-darwin10/buildtools/include/ -D__DARWIN_UNIX03 -D__STDC_LIMIT_MACROS -D__STDC_CONSTANT_MACROS -I/Users/raydonnelly/x-tools/x86_64-apple-darwin10/include -fno-builtin-round -fno-builtin-trunc  -DLTO_SUPPORT -DTRIE_SUPPORT -mdynamic-no-pic -DLTO_SUPPORT -c -o allocate.o /Users/raydonnelly/tbb-work/ctng-build/.build/src/cctools-809/libstuff/allocate.c

# I must stop patching the Apple headers
SDKFILES=$(grep +++ crosstool-ng/patches/cctools/809/100-add_sdkroot_headers.patch | sort | cut -d' ' -f2 | cut -f1)
OTHERPATCHES=$(find crosstool-ng/patches/cctools/809/ -name "*.patch" -and -not -name "100-*" | sort)
for SDKFILE in $SDKFILES; do
 for PATCH in $OTHERPATCHES; do
  if grep "+++ $SDKFILE" $PATCH > /dev/null; then
   echo "Found $SDKFILE in $PATCH"
  fi
 done
done

"
Found b/include/ar.h in crosstool-ng/patches/cctools/809/110-import_to_include.patch
Found b/include/objc/List.h in crosstool-ng/patches/cctools/809/110-import_to_include.patch
Found b/include/objc/Object.h in crosstool-ng/patches/cctools/809/110-import_to_include.patch
Found b/include/objc/objc-class.h in crosstool-ng/patches/cctools/809/110-import_to_include.patch
Found b/include/objc/objc-runtime.h in crosstool-ng/patches/cctools/809/110-import_to_include.patch
Found b/include/objc/zone.h in crosstool-ng/patches/cctools/809/110-import_to_include.patch
Found b/ld64/include/mach-o/dyld_images.h in crosstool-ng/patches/cctools/809/280-missing_includes.patch

.. Analysis:
diff -urN a/ld64/include/mach-o/dyld_images.h b/ld64/include/mach-o/dyld_images.h
--- a/ld64/include/mach-o/dyld_images.h 2013-10-07 17:09:15.402543795 +0100
+++ b/ld64/include/mach-o/dyld_images.h 2013-10-07 17:09:15.555879483 +0100
@@ -25,6 +25,9 @@

 #include <stdbool.h>
 #include <unistd.h>
+#ifndef __APPLE__
+#include <uuid/uuid.h>
+#endif
 #include <mach/mach.h>

 #ifdef __cplusplus

# brew install llvm34 --with-clang --with-asan --HEAD

class Llvm34 < Formula
  homepage  'http://llvm.org/'
  head do
    url 'http://llvm.org/git/llvm.git'

    resource 'clang' do
      url 'http://llvm.org/git/clang.git'
    end

    resource 'clang-tools-extra' do
      url 'http://llvm.org/git/clang-tools-extra.git'
    end

    resource 'compiler-rt' do
      url 'http://llvm.org/git/compiler-rt.git'
    end

    resource 'polly' do
      url 'http://llvm.org/git/polly.git'
    end

    resource 'libcxx' do
      url 'http://llvm.org/git/libcxx.git'
    end

    resource 'libcxxabi' do
      url 'http://llvm.org/git/libcxxabi.git'
    end if MacOS.version <= :snow_leopard
  end


pushd /home/ray/tbb-work/ctng-build/.build/x86_64-apple-darwin10/build/build-cc-clang-final/tools/clang/lib/Driver
PATH=$PWD/../../../../../../buildtools/bin:$PATH

pushd /home/ray/tbb-work/ctng-build/.build/x86_64-apple-darwin10/build/build-cc-clang-final/projects/compiler-rt
PATH=$PWD/../../../../buildtools/bin:$PATH
make -j1 -l CFLAGS="-O2 -g -pipe -DCLANG_GCC_VERSION=' '" CXXFLAGS="-O2 -g -pipe" LDFLAGS="-DCLANG_GCC_VERSION=' '" ONLY_TOOLS="clang" ENABLE_OPTIMIZED=1


pushd /home/ray/tbb-work/ctng-build/.build/x86_64-apple-darwin10/build/build-cc-clang-final
PATH=$PWD/../../buildtools/bin:$PATH
make -j1 CFLAGS="-O2 -g -pipe -DCLANG_GCC_VERSION=" CXXFLAGS="-O2 -g -pipe" LDFLAGS="-DCLANG_GCC_VERSION=" ONLY_TOOLS="clang" ENABLE_OPTIMIZED="1"

# Then the following fails:
pushd /home/ray/tbb-work/ctng-build/.build/x86_64-apple-darwin10/build/build-cc-clang-final
/home/ray/tbb-work/ctng-build/.build/x86_64-apple-darwin10/build/build-cc-clang-final/Release+Asserts/bin/clang -arch x86_64 -dynamiclib -o /home/ray/tbb-work/ctng-build/.build/x86_64-apple-darwin10/build/build-cc-clang-final/tools/clang/runtime/compiler-rt/clang_darwin/asan_osx_dynamic/x86_64/libcompiler_rt.dylib /home/ray/tbb-work/ctng-build/.build/x86_64-apple-darwin10/build/build-cc-clang-final/tools/clang/runtime/compiler-rt/clang_darwin/asan_osx_dynamic/x86_64/SubDir.lib__asan/asan_allocator2.o   /home/ray/tbb-work/ctng-build/.build/x86_64-apple-darwin10/build/build-cc-clang-final/tools/clang/runtime/compiler-rt/clang_darwin/asan_osx_dynamic/x86_64/SubDir.lib__asan/asan_dll_thunk.o   /home/ray/tbb-work/ctng-build/.build/x86_64-apple-darwin10/build/build-cc-clang-final/tools/clang/runtime/compiler-rt/clang_darwin/asan_osx_dynamic/x86_64/SubDir.lib__asan/asan_fake_stack.o   /home/ray/tbb-work/ctng-build/.build/x86_64-apple-darwin10/build/build-cc-clang-final/tools/clang/runtime/compiler-rt/clang_darwin/asan_osx_dynamic/x86_64/SubDir.lib__asan/asan_globals.o   /home/ray/tbb-work/ctng-build/.build/x86_64-apple-darwin10/build/build-cc-clang-final/tools/clang/runtime/compiler-rt/clang_darwin/asan_osx_dynamic/x86_64/SubDir.lib__asan/asan_interceptors.o   /home/ray/tbb-work/ctng-build/.build/x86_64-apple-darwin10/build/build-cc-clang-final/tools/clang/runtime/compiler-rt/clang_darwin/asan_osx_dynamic/x86_64/SubDir.lib__asan/asan_linux.o   /home/ray/tbb-work/ctng-build/.build/x86_64-apple-darwin10/build/build-cc-clang-final/tools/clang/runtime/compiler-rt/clang_darwin/asan_osx_dynamic/x86_64/SubDir.lib__asan/asan_mac.o   /home/ray/tbb-work/ctng-build/.build/x86_64-apple-darwin10/build/build-cc-clang-final/tools/clang/runtime/compiler-rt/clang_darwin/asan_osx_dynamic/x86_64/SubDir.lib__asan/asan_malloc_linux.o   /home/ray/tbb-work/ctng-build/.build/x86_64-apple-darwin10/build/build-cc-clang-final/tools/clang/runtime/compiler-rt/clang_darwin/asan_osx_dynamic/x86_64/SubDir.lib__asan/asan_malloc_mac.o   /home/ray/tbb-work/ctng-build/.build/x86_64-apple-darwin10/build/build-cc-clang-final/tools/clang/runtime/compiler-rt/clang_darwin/asan_osx_dynamic/x86_64/SubDir.lib__asan/asan_malloc_win.o   /home/ray/tbb-work/ctng-build/.build/x86_64-apple-darwin10/build/build-cc-clang-final/tools/clang/runtime/compiler-rt/clang_darwin/asan_osx_dynamic/x86_64/SubDir.lib__asan/asan_new_delete.o   /home/ray/tbb-work/ctng-build/.build/x86_64-apple-darwin10/build/build-cc-clang-final/tools/clang/runtime/compiler-rt/clang_darwin/asan_osx_dynamic/x86_64/SubDir.lib__asan/asan_poisoning.o   /home/ray/tbb-work/ctng-build/.build/x86_64-apple-darwin10/build/build-cc-clang-final/tools/clang/runtime/compiler-rt/clang_darwin/asan_osx_dynamic/x86_64/SubDir.lib__asan/asan_posix.o   /home/ray/tbb-work/ctng-build/.build/x86_64-apple-darwin10/build/build-cc-clang-final/tools/clang/runtime/compiler-rt/clang_darwin/asan_osx_dynamic/x86_64/SubDir.lib__asan/asan_preinit.o   /home/ray/tbb-work/ctng-build/.build/x86_64-apple-darwin10/build/build-cc-clang-final/tools/clang/runtime/compiler-rt/clang_darwin/asan_osx_dynamic/x86_64/SubDir.lib__asan/asan_report.o   /home/ray/tbb-work/ctng-build/.build/x86_64-apple-darwin10/build/build-cc-clang-final/tools/clang/runtime/compiler-rt/clang_darwin/asan_osx_dynamic/x86_64/SubDir.lib__asan/asan_rtl.o   /home/ray/tbb-work/ctng-build/.build/x86_64-apple-darwin10/build/build-cc-clang-final/tools/clang/runtime/compiler-rt/clang_darwin/asan_osx_dynamic/x86_64/SubDir.lib__asan/asan_stack.o   /home/ray/tbb-work/ctng-build/.build/x86_64-apple-darwin10/build/build-cc-clang-final/tools/clang/runtime/compiler-rt/clang_darwin/asan_osx_dynamic/x86_64/SubDir.lib__asan/asan_stats.o   /home/ray/tbb-work/ctng-build/.build/x86_64-apple-darwin10/build/build-cc-clang-final/tools/clang/runtime/compiler-rt/clang_darwin/asan_osx_dynamic/x86_64/SubDir.lib__asan/asan_thread.o   /home/ray/tbb-work/ctng-build/.build/x86_64-apple-darwin10/build/build-cc-clang-final/tools/clang/runtime/compiler-rt/clang_darwin/asan_osx_dynamic/x86_64/SubDir.lib__asan/asan_win.o   /home/ray/tbb-work/ctng-build/.build/x86_64-apple-darwin10/build/build-cc-clang-final/tools/clang/runtime/compiler-rt/clang_darwin/asan_osx_dynamic/x86_64/SubDir.lib/int_util.o   /home/ray/tbb-work/ctng-build/.build/x86_64-apple-darwin10/build/build-cc-clang-final/tools/clang/runtime/compiler-rt/clang_darwin/asan_osx_dynamic/x86_64/SubDir.lib__interception/interception_linux.o   /home/ray/tbb-work/ctng-build/.build/x86_64-apple-darwin10/build/build-cc-clang-final/tools/clang/runtime/compiler-rt/clang_darwin/asan_osx_dynamic/x86_64/SubDir.lib__interception/interception_mac.o   /home/ray/tbb-work/ctng-build/.build/x86_64-apple-darwin10/build/build-cc-clang-final/tools/clang/runtime/compiler-rt/clang_darwin/asan_osx_dynamic/x86_64/SubDir.lib__interception/interception_type_test.o   /home/ray/tbb-work/ctng-build/.build/x86_64-apple-darwin10/build/build-cc-clang-final/tools/clang/runtime/compiler-rt/clang_darwin/asan_osx_dynamic/x86_64/SubDir.lib__interception/interception_win.o   /home/ray/tbb-work/ctng-build/.build/x86_64-apple-darwin10/build/build-cc-clang-final/tools/clang/runtime/compiler-rt/clang_darwin/asan_osx_dynamic/x86_64/SubDir.lib__sanitizer_common/sanitizer_allocator.o   /home/ray/tbb-work/ctng-build/.build/x86_64-apple-darwin10/build/build-cc-clang-final/tools/clang/runtime/compiler-rt/clang_darwin/asan_osx_dynamic/x86_64/SubDir.lib__sanitizer_common/sanitizer_common.o   /home/ray/tbb-work/ctng-build/.build/x86_64-apple-darwin10/build/build-cc-clang-final/tools/clang/runtime/compiler-rt/clang_darwin/asan_osx_dynamic/x86_64/SubDir.lib__sanitizer_common/sanitizer_common_libcdep.o   /home/ray/tbb-work/ctng-build/.build/x86_64-apple-darwin10/build/build-cc-clang-final/tools/clang/runtime/compiler-rt/clang_darwin/asan_osx_dynamic/x86_64/SubDir.lib__sanitizer_common/sanitizer_coverage.o   /home/ray/tbb-work/ctng-build/.build/x86_64-apple-darwin10/build/build-cc-clang-final/tools/clang/runtime/compiler-rt/clang_darwin/asan_osx_dynamic/x86_64/SubDir.lib__sanitizer_common/sanitizer_flags.o   /home/ray/tbb-work/ctng-build/.build/x86_64-apple-darwin10/build/build-cc-clang-final/tools/clang/runtime/compiler-rt/clang_darwin/asan_osx_dynamic/x86_64/SubDir.lib__sanitizer_common/sanitizer_libc.o   /home/ray/tbb-work/ctng-build/.build/x86_64-apple-darwin10/build/build-cc-clang-final/tools/clang/runtime/compiler-rt/clang_darwin/asan_osx_dynamic/x86_64/SubDir.lib__sanitizer_common/sanitizer_libignore.o   /home/ray/tbb-work/ctng-build/.build/x86_64-apple-darwin10/build/build-cc-clang-final/tools/clang/runtime/compiler-rt/clang_darwin/asan_osx_dynamic/x86_64/SubDir.lib__sanitizer_common/sanitizer_linux.o   /home/ray/tbb-work/ctng-build/.build/x86_64-apple-darwin10/build/build-cc-clang-final/tools/clang/runtime/compiler-rt/clang_darwin/asan_osx_dynamic/x86_64/SubDir.lib__sanitizer_common/sanitizer_linux_libcdep.o   /home/ray/tbb-work/ctng-build/.build/x86_64-apple-darwin10/build/build-cc-clang-final/tools/clang/runtime/compiler-rt/clang_darwin/asan_osx_dynamic/x86_64/SubDir.lib__sanitizer_common/sanitizer_mac.o   /home/ray/tbb-work/ctng-build/.build/x86_64-apple-darwin10/build/build-cc-clang-final/tools/clang/runtime/compiler-rt/clang_darwin/asan_osx_dynamic/x86_64/SubDir.lib__sanitizer_common/sanitizer_platform_limits_linux.o   /home/ray/tbb-work/ctng-build/.build/x86_64-apple-darwin10/build/build-cc-clang-final/tools/clang/runtime/compiler-rt/clang_darwin/asan_osx_dynamic/x86_64/SubDir.lib__sanitizer_common/sanitizer_platform_limits_posix.o   /home/ray/tbb-work/ctng-build/.build/x86_64-apple-darwin10/build/build-cc-clang-final/tools/clang/runtime/compiler-rt/clang_darwin/asan_osx_dynamic/x86_64/SubDir.lib__sanitizer_common/sanitizer_posix.o   /home/ray/tbb-work/ctng-build/.build/x86_64-apple-darwin10/build/build-cc-clang-final/tools/clang/runtime/compiler-rt/clang_darwin/asan_osx_dynamic/x86_64/SubDir.lib__sanitizer_common/sanitizer_posix_libcdep.o   /home/ray/tbb-work/ctng-build/.build/x86_64-apple-darwin10/build/build-cc-clang-final/tools/clang/runtime/compiler-rt/clang_darwin/asan_osx_dynamic/x86_64/SubDir.lib__sanitizer_common/sanitizer_printf.o   /home/ray/tbb-work/ctng-build/.build/x86_64-apple-darwin10/build/build-cc-clang-final/tools/clang/runtime/compiler-rt/clang_darwin/asan_osx_dynamic/x86_64/SubDir.lib__sanitizer_common/sanitizer_stackdepot.o   /home/ray/tbb-work/ctng-build/.build/x86_64-apple-darwin10/build/build-cc-clang-final/tools/clang/runtime/compiler-rt/clang_darwin/asan_osx_dynamic/x86_64/SubDir.lib__sanitizer_common/sanitizer_stacktrace.o   /home/ray/tbb-work/ctng-build/.build/x86_64-apple-darwin10/build/build-cc-clang-final/tools/clang/runtime/compiler-rt/clang_darwin/asan_osx_dynamic/x86_64/SubDir.lib__sanitizer_common/sanitizer_stacktrace_libcdep.o   /home/ray/tbb-work/ctng-build/.build/x86_64-apple-darwin10/build/build-cc-clang-final/tools/clang/runtime/compiler-rt/clang_darwin/asan_osx_dynamic/x86_64/SubDir.lib__sanitizer_common/sanitizer_stoptheworld_linux_libcdep.o   /home/ray/tbb-work/ctng-build/.build/x86_64-apple-darwin10/build/build-cc-clang-final/tools/clang/runtime/compiler-rt/clang_darwin/asan_osx_dynamic/x86_64/SubDir.lib__sanitizer_common/sanitizer_suppressions.o   /home/ray/tbb-work/ctng-build/.build/x86_64-apple-darwin10/build/build-cc-clang-final/tools/clang/runtime/compiler-rt/clang_darwin/asan_osx_dynamic/x86_64/SubDir.lib__sanitizer_common/sanitizer_symbolizer.o   /home/ray/tbb-work/ctng-build/.build/x86_64-apple-darwin10/build/build-cc-clang-final/tools/clang/runtime/compiler-rt/clang_darwin/asan_osx_dynamic/x86_64/SubDir.lib__sanitizer_common/sanitizer_symbolizer_libcdep.o   /home/ray/tbb-work/ctng-build/.build/x86_64-apple-darwin10/build/build-cc-clang-final/tools/clang/runtime/compiler-rt/clang_darwin/asan_osx_dynamic/x86_64/SubDir.lib__sanitizer_common/sanitizer_symbolizer_posix_libcdep.o   /home/ray/tbb-work/ctng-build/.build/x86_64-apple-darwin10/build/build-cc-clang-final/tools/clang/runtime/compiler-rt/clang_darwin/asan_osx_dynamic/x86_64/SubDir.lib__sanitizer_common/sanitizer_symbolizer_win.o   /home/ray/tbb-work/ctng-build/.build/x86_64-apple-darwin10/build/build-cc-clang-final/tools/clang/runtime/compiler-rt/clang_darwin/asan_osx_dynamic/x86_64/SubDir.lib__sanitizer_common/sanitizer_thread_registry.o   /home/ray/tbb-work/ctng-build/.build/x86_64-apple-darwin10/build/build-cc-clang-final/tools/clang/runtime/compiler-rt/clang_darwin/asan_osx_dynamic/x86_64/SubDir.lib__sanitizer_common/sanitizer_win.o -DCLANG_GCC_VERSION= -B/home/ray/x-tools/x86_64-apple-darwin10/bin/x86_64-apple-darwin10- --sysroot=/home/ray/x-tools/x86_64-apple-darwin10/x86_64-apple-darwin10/sysroot -framework Foundation -L/home/ray/x-tools/x86_64-apple-darwin10/x86_64-apple-darwin10/sysroot/usr/lib/x86_64-apple-darwin10/4.2.1/ -lstdc++ -undefined dynamic_lookup
ld: warning: can't parse dwarf compilation unit info in /home/ray/tbb-work/ctng-build/.build/x86_64-apple-darwin10/build/build-cc-clang-final/tools/clang/runtime/compiler-rt/clang_darwin/asan_osx_dynamic/x86_64/SubDir.lib__asan/asan_allocator2.o

# More failures:
[INFO ]  Installing final clang compiler: done in 1298.48s (at 37:15)
[INFO ]  =================================================================
[INFO ]  Cleaning-up the toolchain's directory
[INFO ]    Stripping all toolchain executables
[37:15] / /usr/bin/sed: can't read /home/ray/tbb-work/ctng-build-3_3/.build/src/gcc-/gcc/version.c: No such file or directory
[ERROR]
"

# Dsymutil not existing rears its ugly head again, this time with ICU as -g is used ..
# configure:2917: /home/ray/tbb-work/dx-HEAD/bin/x86_64-apple-darwin10-clang -arch x86_64 -isysroot /home/ray/MacOSX10.6.sdk -fPIC -Qunused-arguments -Wall -Wpointer-arith -Wdeclaration-after-statement -Werror=return-type -Wtype-limits -Wempty-body -Wsign-compare -Wno-unused -std=gnu99 -fno-common -fno-math-errno -pthread -pipe -g  -DU_USING_ICU_NAMESPACE=0 -DU_NO_DEFAULT_INCLUDE_UTF_HEADERS=1 -DUCONFIG_NO_LEGACY_CONVERSION -DUCONFIG_NO_TRANSLITERATION -DUCONFIG_NO_REGULAR_EXPRESSIONS -DUCONFIG_NO_BREAK_ITERATION -Qunused-arguments   -framework ExceptionHandling   -lobjc conftest.c  >&5
# x86_64-apple-darwin10-clang: error: unable to execute command: Executable "dsymutil" doesn't exist!
# x86_64-apple-darwin10-clang: error: dsymutil command failed with exit code 1 (use -v to see invocation)

# MSYS64 build failure with LLVM Python:
# mkdir /home/ray/tbb-work/ctng-build-HEAD/.build/x86_64-apple-darwin10/build/build-LLVM-host-x86_64-build_w64-mingw32-2
# pushd /home/ray/tbb-work/ctng-build-HEAD/.build/x86_64-apple-darwin10/build/build-LLVM-host-x86_64-build_w64-mingw32-2
# CFLAGS="-O2 -g -pipe -D__USE_MINGW_ANSI_STDIO=1" CXXFLAGS="-O2 -g -pipe  -D__USE_MINGW_ANSI_STDIO=1" ../build-LLVM-host-x86_64-build_w64-mingw32/configure --build=x86_64-build_w64-mingw32 --host=x86_64-build_w64-mingw32 --prefix=/home/ray/tbb-work/dx-HEAD --target=x86_64-apple-darwin10 --enable-optimized=yes


############################################################
# If you ever need to patch llvm/clang configury stuff ... #
# this should fetch, build and path the right autotools ver#
# Build build tools .. only needed when updating autotools #
############################################################

# Versions for llvm
AUTOCONF_VER=2.60
AUTOMAKE_VER=1.9.6
LIBTOOL_VER=1.5.22
# Versions for isl 0.11.1
AUTOCONF_VER=2.68
AUTOMAKE_VER=1.11.3
LIBTOOL_VER=2.4
# Versions for isl 0.12.1
AUTOCONF_VER=2.69
AUTOMAKE_VER=1.11.6
LIBTOOL_VER=2.4
# Versions for GCC 4.8.2
AUTOCONF_VER=2.64
AUTOMAKE_VER=1.11.1
#LIBTOOL_VER=2.2.7a
[ -d tools ] || mkdir tools
pushd tools > /dev/null
if [ ! -f bin/autoconf ]; then
# curl -SLO http://ftp.gnu.org/gnu/autoconf/autoconf-${AUTOCONF_VER}.tar.bz2
 wget -c http://ftp.gnu.org/gnu/autoconf/autoconf-${AUTOCONF_VER}.tar.gz
 tar -xf autoconf-${AUTOCONF_VER}.tar.gz
 cd autoconf-${AUTOCONF_VER}
 wget -O config.guess 'http://git.savannah.gnu.org/gitweb/?p=config.git;a=blob_plain;f=config.guess;hb=HEAD'
 wget -O config.sub 'http://git.savannah.gnu.org/gitweb/?p=config.git;a=blob_plain;f=config.sub;hb=HEAD' 
 cp config.guess build-aux/
 cp config.sub build-aux/
 ./configure --prefix=$PWD/.. && make && make install
 cd ..
fi
if [ ! -f bin/automake ]; then
 wget -c http://ftp.gnu.org/gnu/automake/automake-${AUTOMAKE_VER}.tar.gz
 tar -xf automake-${AUTOMAKE_VER}.tar.gz
 cd automake-${AUTOMAKE_VER}
 wget -O config.guess 'http://git.savannah.gnu.org/gitweb/?p=config.git;a=blob_plain;f=config.guess;hb=HEAD'
 wget -O config.sub 'http://git.savannah.gnu.org/gitweb/?p=config.git;a=blob_plain;f=config.sub;hb=HEAD' 
 ./configure --prefix=$PWD/.. && make && make install
 cd ..
fi
if [ ! -f bin/libtool ]; then
 curl -SLO http://ftp.gnu.org/gnu/libtool/libtool-${LIBTOOL_VER}.tar.gz
 tar -xf libtool-${LIBTOOL_VER}.tar.gz
 cd libtool-${LIBTOOL_VER}
 wget -O config.guess 'http://git.savannah.gnu.org/gitweb/?p=config.git;a=blob_plain;f=config.guess;hb=HEAD'
 wget -O config.sub 'http://git.savannah.gnu.org/gitweb/?p=config.git;a=blob_plain;f=config.sub;hb=HEAD' 
 ./configure --prefix=$PWD/.. && make && make install
 cd ..
fi
# Test re-autoconfigured GCC with my patch ..
export PATH=$PWD/tools/bin:$PATH
popd > /dev/null
pushd /tmp
tar -xf ~/src/gcc-4.8.2.tar.bz2
cp -rf gcc-4.8.2 gcc-4.8.2.orig
pushd gcc-4.8.2
# patch -p1 < ~/ctng-firefox-builds/crosstool-ng/patches/gcc/4.8.2/100-msys-native-paths-gengtype.patch
find ./ -name configure.ac | while read f; do (cd "$(dirname "$f")"/ && [ -f configure ] && autoconf); done
popd
mkdir gcc-build
pushd gcc-build
/tmp/gcc-4.8.2/configure 2>&1 | grep "absolute srcdir"
make 2>&1 | grep "checking the absolute srcdir"
popd
popd

# single liner to iterate quickly on changing configure.ac:
cfg_build()
{
#pushd gcc-4.8.2/gcc
#autoconf
#popd
[ -d gcc-build ] && rm -rf gcc-build
mkdir gcc-build
pushd gcc-build
if [ "$OSTYPE" = "msys" ]; then
  export PATH=/home/ukrdonnell/ctng-firefox-builds/mingw64-235295c4/bin:$PATH
  BHT="--build=x86_64-build_w64-mingw32 --host=x86_64-build_w64-mingw32 --target=x86_64-unknown-linux-gnu \
  --with-gmp=/home/ukrdonnell/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64-235295c4/.build/x86_64-unknown-linux-gnu/buildtools --with-mpfr=/home/ukrdonnell/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64-235295c4/.build/x86_64-unknown-linux-gnu/buildtools --with-mpc=/home/ukrdonnell/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64-235295c4/.build/x86_64-unknown-linux-gnu/buildtools --with-isl=/home/ukrdonnell/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64-235295c4/.build/x86_64-unknown-linux-gnu/buildtools --with-cloog=/home/ukrdonnell/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64-235295c4/.build/x86_64-unknown-linux-gnu/buildtools --with-libelf=/home/ukrdonnell/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64-235295c4/.build/x86_64-unknown-linux-gnu/buildtools \
  --prefix=/home/ukrdonnell/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64-235295c4/.build/x86_64-unknown-linux-gnu/buildtools"
fi
/tmp/gcc-4.8.2/configure $BHT 2>&1 > configure.log # | grep "checking the absolute srcdir"
make 2>&1 > make.log # | grep "checking the absolute srcdir"
popd
}

# Regenerate the patch:
find gcc-4.8.2 \( -name "*.orig" -or -name "*.rej" -or -name "*.old" -or -name "autom4te.cache" -or -name "config.in~" \) -exec rm -rf {} \;
diff -urN gcc-4.8.2.orig gcc-4.8.2 > ~/Dropbox/gcc482.new.patch

# Even with sjlj Windows 64bit has problems:
# [ALL  ]    C:/msys64/home/ray/tbb-work-sjlj/ctng-build-HEAD/.build/x86_64-apple-darwin10/build/build-LLVM-host-x86_64-build_w64-mingw32/Release+Asserts/lib/libgtest.a(gtest-all.o): In function `testing::internal::DefaultDeathTestFactory::~DefaultDeathTestFactory()':
# [ALL  ]    C:/msys64/home/ray/tbb-work-sjlj/ctng-build-HEAD/.build/x86_64-apple-darwin10/build/build-LLVM-host-x86_64-build_w64-mingw32/utils/unittest/googletest/include/gtest/internal/gtest-death-test-internal.h:148: undefined reference to `testing::internal::DeathTestFactory::~DeathTestFactory()'
# [ALL  ]    C:/msys64/home/ray/tbb-work-sjlj/ctng-build-HEAD/.build/x86_64-apple-darwin10/build/build-LLVM-host-x86_64-build_w64-mingw32/Release+Asserts/lib/libgtest.a(gtest-all.o): In function `~DefaultDeathTestFactory':
# [ALL  ]    C:/msys64/home/ray/tbb-work-sjlj/ctng-build-HEAD/.build/x86_64-apple-darwin10/build/build-LLVM-host-x86_64-build_w64-mingw32/utils/unittest/googletest/include/gtest/internal/gtest-death-test-internal.h:148: undefined reference to `testing::internal::DeathTestFactory::~DeathTestFactory()'
# [ERROR]    collect2.exe: error: ld returned 1 exit status
# These errors are all to do with libgtest though so maybe disable that for now?


# Updating all config.sub / .guess for MSYS2:
mkdir -p /tmp/configs/
rm -rf a b
#cp -rf mozilla-esr24 a
pushd mozilla-central
hg archive ../a
popd
cp -rf a b
wget -O /tmp/configs/config.guess 'http://git.savannah.gnu.org/gitweb/?p=config.git;a=blob_plain;f=config.guess;hb=HEAD'
wget -O /tmp/configs/config.sub 'http://git.savannah.gnu.org/gitweb/?p=config.git;a=blob_plain;f=config.sub;hb=HEAD'
pushd b
CONFIG_SUBS=$(find $PWD -name "config.sub")
for CONFIG_SUB in $CONFIG_SUBS; do
  pushd $(dirname $CONFIG_SUB)
  cp -rf /tmp/configs/* .
  popd
done
popd
diff -urN a b > update-config-sub-config-guess-for-MSYS2.patch

# Making a git am'able patch after a merge has happened ( http://stackoverflow.com/questions/2285699/git-how-to-create-patches-for-a-merge )
# git log -p --pretty=email --stat -m --first-parent 7eafc9dce69a184d1b75e4fa26063dd38c863ea4..HEAD


# Compiling libgcc_s.so uses wrong multilib variant by the look of it.
pushd /home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/x86_64-unknown-linux-gnu/build/build-cc-gcc-core-pass-2/x86_64-unknown-linux-gnu/32/libgcc
/home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/x86_64-unknown-linux-gnu/build/build-cc-gcc-core-pass-2/./gcc/xgcc -B/home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/x86_64-unknown-linux-gnu/build/build-cc-gcc-core-pass-2/./gcc/ -B/home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/x86_64-unknown-linux-gnu/buildtools/x86_64-unknown-linux-gnu/bin/ -B/home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/x86_64-unknown-linux-gnu/buildtools/x86_64-unknown-linux-gnu/lib/ -isystem /home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/x86_64-unknown-linux-gnu/buildtools/x86_64-unknown-linux-gnu/include -isystem /home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/x86_64-unknown-linux-gnu/buildtools/x86_64-unknown-linux-gnu/sys-include    -O2  -DIN_GCC -DCROSS_DIRECTORY_STRUCTURE  -W -Wall -Wno-narrowing -Wwrite-strings -Wcast-qual -Wstrict-prototypes -Wmissing-prototypes -Wold-style-definition  -isystem ./include   -fpic -mlong-double-80 -g -DIN_LIBGCC2 -fbuilding-libgcc -fno-stack-protector  -shared -nodefaultlibs -Wl,--soname=libgcc_s.so.1 -Wl,--version-script=libgcc.map -o 32/libgcc_s.so.1.tmp -g -Os -m32 -B./ _muldi3_s.o _negdi2_s.o _lshrdi3_s.o _ashldi3_s.o _ashrdi3_s.o _cmpdi2_s.o _ucmpdi2_s.o _clear_cache_s.o _trampoline_s.o __main_s.o _absvsi2_s.o _absvdi2_s.o _addvsi3_s.o _addvdi3_s.o _subvsi3_s.o _subvdi3_s.o _mulvsi3_s.o _mulvdi3_s.o _negvsi2_s.o _negvdi2_s.o _ctors_s.o _ffssi2_s.o _ffsdi2_s.o _clz_s.o _clzsi2_s.o _clzdi2_s.o _ctzsi2_s.o _ctzdi2_s.o _popcount_tab_s.o _popcountsi2_s.o _popcountdi2_s.o _paritysi2_s.o _paritydi2_s.o _powisf2_s.o _powidf2_s.o _powixf2_s.o _powitf2_s.o _mulsc3_s.o _muldc3_s.o _mulxc3_s.o _multc3_s.o _divsc3_s.o _divdc3_s.o _divxc3_s.o _divtc3_s.o _bswapsi2_s.o _bswapdi2_s.o _clrsbsi2_s.o _clrsbdi2_s.o _fixunssfsi_s.o _fixunsdfsi_s.o _fixunsxfsi_s.o _fixsfdi_s.o _fixdfdi_s.o _fixxfdi_s.o _fixunssfdi_s.o _fixunsdfdi_s.o _fixunsxfdi_s.o _floatdisf_s.o _floatdidf_s.o _floatdixf_s.o _floatundisf_s.o _floatundidf_s.o _floatundixf_s.o _divdi3_s.o _moddi3_s.o _udivdi3_s.o _umoddi3_s.o _udiv_w_sdiv_s.o _udivmoddi4_s.o cpuinfo_s.o tf-signs_s.o sfp-exceptions_s.o addtf3_s.o divtf3_s.o eqtf2_s.o getf2_s.o letf2_s.o multf3_s.o negtf2_s.o subtf3_s.o unordtf2_s.o fixtfsi_s.o fixunstfsi_s.o floatsitf_s.o floatunsitf_s.o fixtfdi_s.o fixunstfdi_s.o floatditf_s.o floatunditf_s.o extendsftf2_s.o extenddftf2_s.o extendxftf2_s.o trunctfsf2_s.o trunctfdf2_s.o trunctfxf2_s.o enable-execute-stack_s.o unwind-dw2_s.o unwind-dw2-fde-dip_s.o unwind-sjlj_s.o unwind-c_s.o emutls_s.o libgcc.a -lc && rm -f 32/libgcc_s.so && if [ -f 32/libgcc_s.so.1 ]; then mv -f 32/libgcc_s.so.1 32/libgcc_s.so.1.backup; else true; fi && mv 32/libgcc_s.so.1.tmp 32/libgcc_s.so.1 && ln -s libgcc_s.so.1 32/libgcc_s.so
/home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/x86_64-unknown-linux-gnu/build/build-cc-gcc-core-pass-2/./gcc/xgcc -B/home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/x86_64-unknown-linux-gnu/build/build-cc-gcc-core-pass-2/./gcc/ -B/home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/x86_64-unknown-linux-gnu/buildtools/x86_64-unknown-linux-gnu/bin/ -B/home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/x86_64-unknown-linux-gnu/buildtools/x86_64-unknown-linux-gnu/lib/ -isystem /home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/x86_64-unknown-linux-gnu/buildtools/x86_64-unknown-linux-gnu/include -isystem /home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/x86_64-unknown-linux-gnu/buildtools/x86_64-unknown-linux-gnu/sys-include    -O2  -DIN_GCC -DCROSS_DIRECTORY_STRUCTURE  -W -Wall -Wno-narrowing -Wwrite-strings -Wcast-qual -Wstrict-prototypes -Wmissing-prototypes -Wold-style-definition  -isystem ./include   -fpic -mlong-double-80 -g -DIN_LIBGCC2 -fbuilding-libgcc -fno-stack-protector  -shared -nodefaultlibs -Wl,--soname=libgcc_s.so.1 -Wl,--version-script=libgcc.map -o 32/libgcc_s.so.1.tmp -g -Os -m32 -B./ _muldi3_s.o _negdi2_s.o _lshrdi3_s.o _ashldi3_s.o _ashrdi3_s.o _cmpdi2_s.o _ucmpdi2_s.o _clear_cache_s.o _trampoline_s.o __main_s.o _absvsi2_s.o _absvdi2_s.o _addvsi3_s.o _addvdi3_s.o _subvsi3_s.o _subvdi3_s.o _mulvsi3_s.o _mulvdi3_s.o _negvsi2_s.o _negvdi2_s.o _ctors_s.o _ffssi2_s.o _ffsdi2_s.o _clz_s.o _clzsi2_s.o _clzdi2_s.o _ctzsi2_s.o _ctzdi2_s.o _popcount_tab_s.o _popcountsi2_s.o _popcountdi2_s.o _paritysi2_s.o _paritydi2_s.o _powisf2_s.o _powidf2_s.o _powixf2_s.o _powitf2_s.o _mulsc3_s.o _muldc3_s.o _mulxc3_s.o _multc3_s.o _divsc3_s.o _divdc3_s.o _divxc3_s.o _divtc3_s.o _bswapsi2_s.o _bswapdi2_s.o _clrsbsi2_s.o _clrsbdi2_s.o _fixunssfsi_s.o _fixunsdfsi_s.o _fixunsxfsi_s.o _fixsfdi_s.o _fixdfdi_s.o _fixxfdi_s.o _fixunssfdi_s.o _fixunsdfdi_s.o _fixunsxfdi_s.o _floatdisf_s.o _floatdidf_s.o _floatdixf_s.o _floatundisf_s.o _floatundidf_s.o _floatundixf_s.o _divdi3_s.o _moddi3_s.o _udivdi3_s.o _umoddi3_s.o _udiv_w_sdiv_s.o _udivmoddi4_s.o cpuinfo_s.o tf-signs_s.o sfp-exceptions_s.o addtf3_s.o divtf3_s.o eqtf2_s.o getf2_s.o letf2_s.o multf3_s.o negtf2_s.o subtf3_s.o unordtf2_s.o fixtfsi_s.o fixunstfsi_s.o floatsitf_s.o floatunsitf_s.o fixtfdi_s.o fixunstfdi_s.o floatditf_s.o floatunditf_s.o extendsftf2_s.o extenddftf2_s.o extendxftf2_s.o trunctfsf2_s.o trunctfdf2_s.o trunctfxf2_s.o enable-execute-stack_s.o unwind-dw2_s.o unwind-dw2-fde-dip_s.o unwind-sjlj_s.o unwind-c_s.o emutls_s.o libgcc.a -lc -v
# So even though -print-multi-lib shows what we expect .. it doesn't seem to be look in that folder.
# but unfortunately, even if it did look in the right place, they contain the wrong stuff.
# [ray@arch-work libgcc]$ file /home/ray/ctng-firefox-builds/x-l-HEAD-x86_64/x86_64-unknown-linux-gnu/sysroot/usr/lib/libc.so
# /home/ray/ctng-firefox-builds/x-l-HEAD-x86_64/x86_64-unknown-linux-gnu/sysroot/usr/lib/libc.so: ELF 64-bit LSB  shared object, x86-64, version 1 (SYSV), dynamically linked, not stripped
# [ray@arch-work libgcc]$ file /home/ray/ctng-firefox-builds/x-l-HEAD-x86_64/x86_64-unknown-linux-gnu/sysroot/usr/lib/32/libc.so
# /home/ray/ctng-firefox-builds/x-l-HEAD-x86_64/x86_64-unknown-linux-gnu/sysroot/usr/lib/32/libc.so: ELF 64-bit LSB  shared object, x86-64, version 1 (SYSV), dynamically linked, not stripped
# [ray@arch-work libgcc]$ ls -l /home/ray/ctng-firefox-builds/x-l-HEAD-x86_64/x86_64-unknown-linux-gnu/sysroot/usr/lib/
# Hmm .. here's how mingw-w64 say to do it:
# http://sourceforge.net/apps/trac/mingw-w64/wiki/Answer%20Multilib%20Toolchain

# pushd /home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/x86_64-unknown-linux-gnu/build/build-cc-gcc-core-pass-2/x86_64-unknown-linux-gnu/32/libgcc
# /home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/x86_64-unknown-linux-gnu/build/build-cc-gcc-core-pass-2/./gcc/xgcc -B/home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/x86_64-unknown-linux-gnu/build/build-cc-gcc-core-pass-2/./gcc/ -B/home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/x86_64-unknown-linux-gnu/buildtools/x86_64-unknown-linux-gnu/bin/ -B/home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/x86_64-unknown-linux-gnu/buildtools/x86_64-unknown-linux-gnu/lib/ -isystem /home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/x86_64-unknown-linux-gnu/buildtools/x86_64-unknown-linux-gnu/include -isystem /home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/x86_64-unknown-linux-gnu/buildtools/x86_64-unknown-linux-gnu/sys-include    -O2  -DIN_GCC -DCROSS_DIRECTORY_STRUCTURE  -W -Wall -Wno-narrowing -Wwrite-strings -Wcast-qual -Wstrict-prototypes -Wmissing-prototypes -Wold-style-definition  -isystem ./include   -fpic -mlong-double-80 -g -DIN_LIBGCC2 -fbuilding-libgcc -fno-stack-protector  -shared -nodefaultlibs -Wl,--soname=libgcc_s.so.1 -Wl,--version-script=libgcc.map -o 32/libgcc_s.so.1.tmp -g -Os -m32 -B./ _muldi3_s.o _negdi2_s.o _lshrdi3_s.o _ashldi3_s.o _ashrdi3_s.o _cmpdi2_s.o _ucmpdi2_s.o _clear_cache_s.o _trampoline_s.o __main_s.o _absvsi2_s.o _absvdi2_s.o _addvsi3_s.o _addvdi3_s.o _subvsi3_s.o _subvdi3_s.o _mulvsi3_s.o _mulvdi3_s.o _negvsi2_s.o _negvdi2_s.o _ctors_s.o _ffssi2_s.o _ffsdi2_s.o _clz_s.o _clzsi2_s.o _clzdi2_s.o _ctzsi2_s.o _ctzdi2_s.o _popcount_tab_s.o _popcountsi2_s.o _popcountdi2_s.o _paritysi2_s.o _paritydi2_s.o _powisf2_s.o _powidf2_s.o _powixf2_s.o _powitf2_s.o _mulsc3_s.o _muldc3_s.o _mulxc3_s.o _multc3_s.o _divsc3_s.o _divdc3_s.o _divxc3_s.o _divtc3_s.o _bswapsi2_s.o _bswapdi2_s.o _clrsbsi2_s.o _clrsbdi2_s.o _fixunssfsi_s.o _fixunsdfsi_s.o _fixunsxfsi_s.o _fixsfdi_s.o _fixdfdi_s.o _fixxfdi_s.o _fixunssfdi_s.o _fixunsdfdi_s.o _fixunsxfdi_s.o _floatdisf_s.o _floatdidf_s.o _floatdixf_s.o _floatundisf_s.o _floatundidf_s.o _floatundixf_s.o _divdi3_s.o _moddi3_s.o _udivdi3_s.o _umoddi3_s.o _udiv_w_sdiv_s.o _udivmoddi4_s.o cpuinfo_s.o tf-signs_s.o sfp-exceptions_s.o addtf3_s.o divtf3_s.o eqtf2_s.o getf2_s.o letf2_s.o multf3_s.o negtf2_s.o subtf3_s.o unordtf2_s.o fixtfsi_s.o fixunstfsi_s.o floatsitf_s.o floatunsitf_s.o fixtfdi_s.o fixunstfdi_s.o floatditf_s.o floatunditf_s.o extendsftf2_s.o extenddftf2_s.o extendxftf2_s.o trunctfsf2_s.o trunctfdf2_s.o trunctfxf2_s.o enable-execute-stack_s.o unwind-dw2_s.o unwind-dw2-fde-dip_s.o unwind-sjlj_s.o unwind-c_s.o emutls_s.o libgcc.a -lc

From: /home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/src/gcc-4.8.2/libgcc/Makefile.in
libgcc_s$(SHLIB_EXT): $(libgcc-s-objects) $(extra-parts) libgcc.a
        # @multilib_flags@ is still needed because this may use
        # $(GCC_FOR_TARGET) and $(LIBGCC2_CFLAGS) directly.
        # @multilib_dir@ is not really necessary, but sometimes it has
        # more uses than just a directory name.
        $(mkinstalldirs) $(MULTIDIR)
        $(subst @multilib_flags@,$(CFLAGS) -B./,$(subst \
                @multilib_dir@,$(MULTIDIR),$(subst \
                @shlib_objs@,$(objects) libgcc.a,$(subst \
                @shlib_base_name@,libgcc_s,$(subst \
                @shlib_map_file@,$(mapfile),$(subst \
                @shlib_slibdir_qual@,$(MULTIOSSUBDIR),$(subst \
                @shlib_slibdir@,$(shlib_slibdir),$(SHLIB_LINK))))))))


/home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/x86_64-unknown-linux-gnu/build/build-cc-gcc-core-pass-2/x86_64-unknown-linux-gnu/libgcc/Makefile

libgcc_s$(SHLIB_EXT): $(libgcc-s-objects) $(extra-parts) libgcc.a
        # @multilib_flags@ is still needed because this may use
        # $(GCC_FOR_TARGET) and $(LIBGCC2_CFLAGS) directly.
        # @multilib_dir@ is not really necessary, but sometimes it has
        # more uses than just a directory name.
        $(mkinstalldirs) $(MULTIDIR)
        $(subst @multilib_flags@,$(CFLAGS) -B./,$(subst \
                @multilib_dir@,$(MULTIDIR),$(subst \
                @shlib_objs@,$(objects) libgcc.a,$(subst \
                @shlib_base_name@,libgcc_s,$(subst \
                @shlib_map_file@,$(mapfile),$(subst \
                @shlib_slibdir_qual@,$(MULTIOSSUBDIR),$(subst \
                @shlib_slibdir@,$(shlib_slibdir),$(SHLIB_LINK))))))))

/home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/x86_64-unknown-linux-gnu/build/build-cc-gcc-core-pass-2/./gcc/xgcc -B/home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/x86_64-unknown-linux-gnu/build/build-cc-gcc-core-pass-2/./gcc/ -B/home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/x86_64-unknown-linux-gnu/buildtools/x86_64-unknown-linux-gnu/bin/ -B/home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/x86_64-unknown-linux-gnu/buildtools/x86_64-unknown-linux-gnu/lib/ -isystem /home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/x86_64-unknown-linux-gnu/buildtools/x86_64-unknown-linux-gnu/include -isystem /home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/x86_64-unknown-linux-gnu/buildtools/x86_64-unknown-linux-gnu/sys-include    -O2  -DIN_GCC -DCROSS_DIRECTORY_STRUCTURE  -W -Wall -Wno-narrowing -Wwrite-strings -Wcast-qual -Wstrict-prototypes -Wmissing-prototypes -Wold-style-definition  -isystem ./include   -fpic -mlong-double-80 -g -DIN_LIBGCC2 -fbuilding-libgcc -fno-stack-protector  -shared -nodefaultlibs -Wl,--soname=libgcc_s.so.1 -Wl,--version-script=libgcc.map -o 32/libgcc_s.so.1.tmp -g -Os -m32 -B./ _muldi3_s.o _negdi2_s.o _lshrdi3_s.o _ashldi3_s.o _ashrdi3_s.o _cmpdi2_s.o _ucmpdi2_s.o _clear_cache_s.o _trampoline_s.o __main_s.o _absvsi2_s.o _absvdi2_s.o _addvsi3_s.o _addvdi3_s.o _subvsi3_s.o _subvdi3_s.o _mulvsi3_s.o _mulvdi3_s.o _negvsi2_s.o _negvdi2_s.o _ctors_s.o _ffssi2_s.o _ffsdi2_s.o _clz_s.o _clzsi2_s.o _clzdi2_s.o _ctzsi2_s.o _ctzdi2_s.o _popcount_tab_s.o _popcountsi2_s.o _popcountdi2_s.o _paritysi2_s.o _paritydi2_s.o _powisf2_s.o _powidf2_s.o _powixf2_s.o _powitf2_s.o _mulsc3_s.o _muldc3_s.o _mulxc3_s.o _multc3_s.o _divsc3_s.o _divdc3_s.o _divxc3_s.o _divtc3_s.o _bswapsi2_s.o _bswapdi2_s.o _clrsbsi2_s.o _clrsbdi2_s.o _fixunssfsi_s.o _fixunsdfsi_s.o _fixunsxfsi_s.o _fixsfdi_s.o _fixdfdi_s.o _fixxfdi_s.o _fixunssfdi_s.o _fixunsdfdi_s.o _fixunsxfdi_s.o _floatdisf_s.o _floatdidf_s.o _floatdixf_s.o _floatundisf_s.o _floatundidf_s.o _floatundixf_s.o _divdi3_s.o _moddi3_s.o _udivdi3_s.o _umoddi3_s.o _udiv_w_sdiv_s.o _udivmoddi4_s.o cpuinfo_s.o tf-signs_s.o sfp-exceptions_s.o addtf3_s.o divtf3_s.o eqtf2_s.o getf2_s.o letf2_s.o multf3_s.o negtf2_s.o subtf3_s.o unordtf2_s.o fixtfsi_s.o fixunstfsi_s.o floatsitf_s.o floatunsitf_s.o fixtfdi_s.o fixunstfdi_s.o floatditf_s.o floatunditf_s.o extendsftf2_s.o extenddftf2_s.o extendxftf2_s.o trunctfsf2_s.o trunctfdf2_s.o trunctfxf2_s.o enable-execute-stack_s.o unwind-dw2_s.o unwind-dw2-fde-dip_s.o unwind-sjlj_s.o unwind-c_s.o emutls_s.o libgcc.a -lc && rm -f 32/libgcc_s.so && if [ -f 32/libgcc_s.so.1 ]; then mv -f 32/libgcc_s.so.1 32/libgcc_s.so.1.backup; else true; fi && mv 32/libgcc_s.so.1.tmp 32/libgcc_s.so.1 && ln -s libgcc_s.so.1 32/libgcc_s.so

Makefiles:
/home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/x86_64-unknown-linux-gnu/build/build-cc-gcc-core-pass-2/x86_64-unknown-linux-gnu/libgcc/Makefile
/home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/x86_64-unknown-linux-gnu/build/build-cc-gcc-core-pass-2/x86_64-unknown-linux-gnu/32/libgcc/Makefile

.. 2nd one has ..

MULTIDIRS =
MULTISUBDIR = /32

.. but why MULTIDIRS when the usages in same file are of MULTIDIR

Failure line is:
/home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/x86_64-unknown-linux-gnu/build/build-cc-gcc-core-pass-2/./gcc/xgcc -B/home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/x86_64-unknown-linux-gnu/build/build-cc-gcc-core-pass-2/./gcc/ -B/home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/x86_64-unknown-linux-gnu/buildtools/x86_64-unknown-linux-gnu/bin/ -B/home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/x86_64-unknown-linux-gnu/buildtools/x86_64-unknown-linux-gnu/lib/ -isystem /home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/x86_64-unknown-linux-gnu/buildtools/x86_64-unknown-linux-gnu/include -isystem /home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/x86_64-unknown-linux-gnu/buildtools/x86_64-unknown-linux-gnu/sys-include    -O2  -DIN_GCC -DCROSS_DIRECTORY_STRUCTURE  -W -Wall -Wno-narrowing -Wwrite-strings -Wcast-qual -Wstrict-prototypes -Wmissing-prototypes -Wold-style-definition  -isystem ./include   -fpic -mlong-double-80 -g -DIN_LIBGCC2 -fbuilding-libgcc -fno-stack-protector  -shared -nodefaultlibs -Wl,--soname=libgcc_s.so.1 -Wl,--version-script=libgcc.map -o 32/libgcc_s.so.1.tmp -g -Os -m32 -B./ _muldi3_s.o _negdi2_s.o _lshrdi3_s.o _ashldi3_s.o _ashrdi3_s.o _cmpdi2_s.o _ucmpdi2_s.o _clear_cache_s.o _trampoline_s.o __main_s.o _absvsi2_s.o _absvdi2_s.o _addvsi3_s.o _addvdi3_s.o _subvsi3_s.o _subvdi3_s.o _mulvsi3_s.o _mulvdi3_s.o _negvsi2_s.o _negvdi2_s.o _ctors_s.o _ffssi2_s.o _ffsdi2_s.o _clz_s.o _clzsi2_s.o _clzdi2_s.o _ctzsi2_s.o _ctzdi2_s.o _popcount_tab_s.o _popcountsi2_s.o _popcountdi2_s.o _paritysi2_s.o _paritydi2_s.o _powisf2_s.o _powidf2_s.o _powixf2_s.o _powitf2_s.o _mulsc3_s.o _muldc3_s.o _mulxc3_s.o _multc3_s.o _divsc3_s.o _divdc3_s.o _divxc3_s.o _divtc3_s.o _bswapsi2_s.o _bswapdi2_s.o _clrsbsi2_s.o _clrsbdi2_s.o _fixunssfsi_s.o _fixunsdfsi_s.o _fixunsxfsi_s.o _fixsfdi_s.o _fixdfdi_s.o _fixxfdi_s.o _fixunssfdi_s.o _fixunsdfdi_s.o _fixunsxfdi_s.o _floatdisf_s.o _floatdidf_s.o _floatdixf_s.o _floatundisf_s.o _floatundidf_s.o _floatundixf_s.o _divdi3_s.o _moddi3_s.o _udivdi3_s.o _umoddi3_s.o _udiv_w_sdiv_s.o _udivmoddi4_s.o cpuinfo_s.o tf-signs_s.o sfp-exceptions_s.o addtf3_s.o divtf3_s.o eqtf2_s.o getf2_s.o letf2_s.o multf3_s.o negtf2_s.o subtf3_s.o unordtf2_s.o fixtfsi_s.o fixunstfsi_s.o floatsitf_s.o floatunsitf_s.o fixtfdi_s.o fixunstfdi_s.o floatditf_s.o floatunditf_s.o extendsftf2_s.o extenddftf2_s.o extendxftf2_s.o trunctfsf2_s.o trunctfdf2_s.o trunctfxf2_s.o enable-execute-stack_s.o unwind-dw2_s.o unwind-dw2-fde-dip_s.o unwind-sjlj_s.o unwind-c_s.o emutls_s.o libgcc.a -lc

.. which contains:  -m32 -B./



From Arch linux:
https://projects.archlinux.org/svntogit/community.git/tree/trunk/PKGBUILD?h=packages/lib32-glibc

${srcdir}/${_pkgbasename}-${pkgver}/configure --prefix=/usr \
     --libdir=/usr/lib32 --libexecdir=/usr/lib32 \
     --with-headers=/usr/include \
     --with-bugurl=https://bugs.archlinux.org/ \
     --enable-add-ons=nptl,libidn \
     --enable-obsolete-rpc \
     --enable-kernel=2.6.32 \
     --enable-bind-now --disable-profile \
     --enable-stackguard-randomization \
     --enable-lock-elision \
     --enable-multi-arch i686-unknown-linux-gnu

# enable-multi-arch is something like Apple's fat binaries I think, so probably not relevant to this, also it doesn't take any option.

from /home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/x86_64-unknown-linux-gnu/build/build-libc-startfiles_32/config.log
Our configure for libc_startfiles_32:
$ /home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/src/glibc-2.18/configure --prefix=/usr \
   --build=x86_64-build_unknown-linux-gnu --host=i686-unknown-linux-gnu --cache-file=/home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/x86_64-unknown-linux-gnu/build/build-libc-startfiles_32/config.cache \
   --without-cvs --disable-profile --without-gd --with-headers=/home/ray/ctng-firefox-builds/x-l-HEAD-x86_64/x86_64-unknown-linux-gnu/sysroot/usr/include \
   --disable-debug --disable-sanity-checks --enable-kernel=2.6.33 --with-__thread --with-tls --enable-shared --enable-add-ons=nptl --with-pkgversion=crosstool-NG hg+unknown-20131121.135846

from /home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/x86_64-unknown-linux-gnu/build/build-libc-startfiles/config.log
Out configure for libc_startfiles:
$ /home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/src/glibc-2.18/configure --prefix=/usr \
  --build=x86_64-build_unknown-linux-gnu --host=x86_64-unknown-linux-gnu --cache-file=/home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/x86_64-unknown-linux-gnu/build/build-libc-startfiles/config.cache \
  --without-cvs --disable-profile --without-gd --with-headers=/home/ray/ctng-firefox-builds/x-l-HEAD-x86_64/x86_64-unknown-linux-gnu/sysroot/usr/include \
  --disable-debug --disable-sanity-checks --enable-kernel=2.6.33 --with-__thread --with-tls --enable-shared --enable-add-ons=nptl --with-pkgversion=crosstool-NG hg+unknown-20131121.135846

.. so      --enable-multi-arch i686-unknown-linux-gnu is not being passed in here?

/home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/src/glibc-2.18/configure --help does not list any arguments for --enable-multi-arch

https://wiki.debian.org/Multiarch/HOWTO

from: https://sourceware.org/glibc/wiki/x32 :

they enable x32 like this:
--target=x86_64-x32-linux --build=x86_64-linux --host=x86_64-x32-linux

From gcc-multilib:
https://projects.archlinux.org/svntogit/community.git/tree/trunk/PKGBUILD?h=packages/gcc-multilib

 ${srcdir}/${_basedir}/configure --prefix=/usr \
      --libdir=/usr/lib --libexecdir=/usr/lib \
      --mandir=/usr/share/man --infodir=/usr/share/info \
      --with-bugurl=https://bugs.archlinux.org/ \
      --enable-languages=c,c++,ada,fortran,go,lto,objc,obj-c++ \
      --enable-shared --enable-threads=posix \
      --with-system-zlib --enable-__cxa_atexit \
      --disable-libunwind-exceptions --enable-clocale=gnu \
      --disable-libstdcxx-pch \
      --enable-gnu-unique-object --enable-linker-build-id \
      --enable-cloog-backend=isl --disable-cloog-version-check \
      --enable-lto --enable-gold --enable-ld=default \
      --enable-plugin --with-plugin-ld=ld.gold \
      --with-linker-hash-style=gnu --disable-install-libiberty \
      --enable-multilib --disable-libssp --disable-werror \
      --enable-checking=release

From /home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/x86_64-unknown-linux-gnu/build/build-cc-gcc-core-pass-2/config.log
$ /home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/src/gcc-4.8.2/configure \
  --build=x86_64-build_unknown-linux-gnu --host=x86_64-build_unknown-linux-gnu --target=x86_64-unknown-linux-gnu \
  --prefix=/home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/x86_64-unknown-linux-gnu/buildtools \
  --with-local-prefix=/home/ray/ctng-firefox-builds/x-l-HEAD-x86_64/x86_64-unknown-linux-gnu/sysroot \
  --disable-libmudflap \
  --with-sysroot=/home/ray/ctng-firefox-builds/x-l-HEAD-x86_64/x86_64-unknown-linux-gnu/sysroot \
  --enable-shared --with-pkgversion=crosstool-NG hg+unknown-20131121.135846 \
  --enable-__cxa_atexit \
  --with-gmp=/home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/x86_64-unknown-linux-gnu/buildtools \
  --with-mpfr=/home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/x86_64-unknown-linux-gnu/buildtools \
  --with-mpc=/home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/x86_64-unknown-linux-gnu/buildtools \
  --with-isl=/home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/x86_64-unknown-linux-gnu/buildtools \
  --with-cloog=/home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/x86_64-unknown-linux-gnu/buildtools \
  --with-libelf=/home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/x86_64-unknown-linux-gnu/buildtools \
  --enable-lto \
  --with-host-libstdcxx=-static-libgcc -Wl,-Bstatic,-lstdc++,-Bdynamic -lm \
  --enable-target-optspace --disable-libgomp --disable-libmudflap --disable-nls --enable-multilib --enable-languages=c

.. Getting to the nuts and bolts of the failure:

pushd /home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/x86_64-unknown-linux-gnu/build/build-cc-gcc-core-pass-2/x86_64-unknown-linux-gnu/32/libgcc
PATH=/home/ray/ctng-firefox-builds/x-l-HEAD-x86_64/bin:/home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/x86_64-unknown-linux-gnu/buildtools/bin:/home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/tools/bin:/home/ray/bin:/usr/local/sbin:/usr/local/bin:/usr/bin:/usr/bin/vendor_perl:/usr/bin/core_perl:/home/ray/ctng-firefox-builds//bin
# /home/ray/ctng-firefox-builds/x-l-HEAD-x86_64/bin *** <- contains binutils install.
# /home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/x86_64-unknown-linux-gnu/buildtools/bin *** <- contains GCC stage 1 and some shell scripts too (x86_64-unknown-linux-gnu-gcc is GCC stage 1, x86_64-build_unknown-linux-gnu-g++ is shell)
# /home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/tools/bin *** <- contains sed awk wrapper scripts etc.
pushd /home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/x86_64-unknown-linux-gnu/build/build-cc-gcc-core-pass-2/x86_64-unknown-linux-gnu/32/libgcc
PATH=/home/ray/ctng-firefox-builds/x-l-HEAD-x86_64/bin:/home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/x86_64-unknown-linux-gnu/buildtools/bin:/home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/tools/bin:/home/ray/bin:/usr/local/sbin:/usr/local/bin:/usr/bin:/usr/bin/vendor_perl:/usr/bin/core_perl:/home/ray/ctng-firefox-builds//bin \
/home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/x86_64-unknown-linux-gnu/build/build-cc-gcc-core-pass-2/./gcc/xgcc -B/home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/x86_64-unknown-linux-gnu/build/build-cc-gcc-core-pass-2/./gcc/ -B/home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/x86_64-unknown-linux-gnu/buildtools/x86_64-unknown-linux-gnu/bin/ -B/home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/x86_64-unknown-linux-gnu/buildtools/x86_64-unknown-linux-gnu/lib/ -isystem /home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/x86_64-unknown-linux-gnu/buildtools/x86_64-unknown-linux-gnu/include -isystem /home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/x86_64-unknown-linux-gnu/buildtools/x86_64-unknown-linux-gnu/sys-include    -O2  -DIN_GCC -DCROSS_DIRECTORY_STRUCTURE  -W -Wall -Wno-narrowing -Wwrite-strings -Wcast-qual -Wstrict-prototypes -Wmissing-prototypes -Wold-style-definition  -isystem ./include   -fpic -mlong-double-80 -g -DIN_LIBGCC2 -fbuilding-libgcc -fno-stack-protector  -shared -nodefaultlibs -Wl,--soname=libgcc_s.so.1 -Wl,--version-script=libgcc.map -o 32/libgcc_s.so.1.tmp -g -Os -m32 -B./ _muldi3_s.o _negdi2_s.o _lshrdi3_s.o _ashldi3_s.o _ashrdi3_s.o _cmpdi2_s.o _ucmpdi2_s.o _clear_cache_s.o _trampoline_s.o __main_s.o _absvsi2_s.o _absvdi2_s.o _addvsi3_s.o _addvdi3_s.o _subvsi3_s.o _subvdi3_s.o _mulvsi3_s.o _mulvdi3_s.o _negvsi2_s.o _negvdi2_s.o _ctors_s.o _ffssi2_s.o _ffsdi2_s.o _clz_s.o _clzsi2_s.o _clzdi2_s.o _ctzsi2_s.o _ctzdi2_s.o _popcount_tab_s.o _popcountsi2_s.o _popcountdi2_s.o _paritysi2_s.o _paritydi2_s.o _powisf2_s.o _powidf2_s.o _powixf2_s.o _powitf2_s.o _mulsc3_s.o _muldc3_s.o _mulxc3_s.o _multc3_s.o _divsc3_s.o _divdc3_s.o _divxc3_s.o _divtc3_s.o _bswapsi2_s.o _bswapdi2_s.o _clrsbsi2_s.o _clrsbdi2_s.o _fixunssfsi_s.o _fixunsdfsi_s.o _fixunsxfsi_s.o _fixsfdi_s.o _fixdfdi_s.o _fixxfdi_s.o _fixunssfdi_s.o _fixunsdfdi_s.o _fixunsxfdi_s.o _floatdisf_s.o _floatdidf_s.o _floatdixf_s.o _floatundisf_s.o _floatundidf_s.o _floatundixf_s.o _divdi3_s.o _moddi3_s.o _udivdi3_s.o _umoddi3_s.o _udiv_w_sdiv_s.o _udivmoddi4_s.o cpuinfo_s.o tf-signs_s.o sfp-exceptions_s.o addtf3_s.o divtf3_s.o eqtf2_s.o getf2_s.o letf2_s.o multf3_s.o negtf2_s.o subtf3_s.o unordtf2_s.o fixtfsi_s.o fixunstfsi_s.o floatsitf_s.o floatunsitf_s.o fixtfdi_s.o fixunstfdi_s.o floatditf_s.o floatunditf_s.o extendsftf2_s.o extenddftf2_s.o extendxftf2_s.o trunctfsf2_s.o trunctfdf2_s.o trunctfxf2_s.o enable-execute-stack_s.o unwind-dw2_s.o unwind-dw2-fde-dip_s.o unwind-sjlj_s.o unwind-c_s.o emutls_s.o libgcc.a -lc


PATH=/home/ray/ctng-firefox-builds/x-l-HEAD-x86_64/bin:/home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/x86_64-unknown-linux-gnu/buildtools/bin:/home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/tools/bin:/home/ray/bin:/usr/local/sbin:/usr/local/bin:/usr/bin:/usr/bin/vendor_perl:/usr/bin/core_perl:/home/ray/ctng-firefox-builds//bin /home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/x86_64-unknown-linux-gnu/build/build-cc-gcc-core-pass-2/./gcc/xgcc -B/home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/x86_64-unknown-linux-gnu/build/build-cc-gcc-core-pass-2/./gcc/ -B/home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/x86_64-unknown-linux-gnu/buildtools/x86_64-unknown-linux-gnu/bin/ -B/home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/x86_64-unknown-linux-gnu/buildtools/x86_64-unknown-linux-gnu/lib/ -isystem /home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/x86_64-unknown-linux-gnu/buildtools/x86_64-unknown-linux-gnu/include -isystem /home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/x86_64-unknown-linux-gnu/buildtools/x86_64-unknown-linux-gnu/sys-include    -O2  -DIN_GCC -DCROSS_DIRECTORY_STRUCTURE  -W -Wall -Wno-narrowing -Wwrite-strings -Wcast-qual -Wstrict-prototypes -Wmissing-prototypes -Wold-style-definition  -isystem ./include   -fpic -mlong-double-80 -g -DIN_LIBGCC2 -fbuilding-libgcc -fno-stack-protector  -shared -nodefaultlibs -Wl,--soname=libgcc_s.so.1 -Wl,--version-script=libgcc.map -o 32/libgcc_s.so.1.tmp -g -Os -m32 -Bm32/ _muldi3_s.o _negdi2_s.o _lshrdi3_s.o _ashldi3_s.o _ashrdi3_s.o _cmpdi2_s.o _ucmpdi2_s.o _clear_cache_s.o _trampoline_s.o __main_s.o _absvsi2_s.o _absvdi2_s.o _addvsi3_s.o _addvdi3_s.o _subvsi3_s.o _subvdi3_s.o _mulvsi3_s.o _mulvdi3_s.o _negvsi2_s.o _negvdi2_s.o _ctors_s.o _ffssi2_s.o _ffsdi2_s.o _clz_s.o _clzsi2_s.o _clzdi2_s.o _ctzsi2_s.o _ctzdi2_s.o _popcount_tab_s.o _popcountsi2_s.o _popcountdi2_s.o _paritysi2_s.o _paritydi2_s.o _powisf2_s.o _powidf2_s.o _powixf2_s.o _powitf2_s.o _mulsc3_s.o _muldc3_s.o _mulxc3_s.o _multc3_s.o _divsc3_s.o _divdc3_s.o _divxc3_s.o _divtc3_s.o _bswapsi2_s.o _bswapdi2_s.o _clrsbsi2_s.o _clrsbdi2_s.o _fixunssfsi_s.o _fixunsdfsi_s.o _fixunsxfsi_s.o _fixsfdi_s.o _fixdfdi_s.o _fixxfdi_s.o _fixunssfdi_s.o _fixunsdfdi_s.o _fixunsxfdi_s.o _floatdisf_s.o _floatdidf_s.o _floatdixf_s.o _floatundisf_s.o _floatundidf_s.o _floatundixf_s.o _divdi3_s.o _moddi3_s.o _udivdi3_s.o _umoddi3_s.o _udiv_w_sdiv_s.o _udivmoddi4_s.o cpuinfo_s.o tf-signs_s.o sfp-exceptions_s.o addtf3_s.o divtf3_s.o eqtf2_s.o getf2_s.o letf2_s.o multf3_s.o negtf2_s.o subtf3_s.o unordtf2_s.o fixtfsi_s.o fixunstfsi_s.o floatsitf_s.o floatunsitf_s.o fixtfdi_s.o fixunstfdi_s.o floatditf_s.o floatunditf_s.o extendsftf2_s.o extenddftf2_s.o extendxftf2_s.o trunctfsf2_s.o trunctfdf2_s.o trunctfxf2_s.o enable-execute-stack_s.o unwind-dw2_s.o unwind-dw2-fde-dip_s.o unwind-sjlj_s.o unwind-c_s.o emutls_s.o libgcc.a -lc -v


/home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/x86_64-unknown-linux-gnu/build/build-cc-gcc-core-pass-2/./gcc/xgcc


PATH=/home/ray/ctng-firefox-builds/x-l-HEAD-x86_64/bin:/home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/x86_64-unknown-linux-gnu/buildtools/bin:/home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/tools/bin:/home/ray/bin:/usr/local/sbin:/usr/local/bin:/usr/bin:/usr/bin/vendor_perl:/usr/bin/core_perl:/home/ray/ctng-firefox-builds//bin 

/home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/x86_64-unknown-linux-gnu/build/build-cc-gcc-core-pass-2/./gcc/xgcc \
  -B/home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/x86_64-unknown-linux-gnu/build/build-cc-gcc-core-pass-2/./gcc/ -B/home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/x86_64-unknown-linux-gnu/buildtools/x86_64-unknown-linux-gnu/bin/ -B/home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/x86_64-unknown-linux-gnu/buildtools/x86_64-unknown-linux-gnu/lib/ \
  -m32 -lc -v -fno-stack-protector  -shared -nodefaultlibs -Wl,--soname=libgcc_s.so.1 -Wl,--version-script=libgcc.map -o 32/libgcc_s.so.1.tmp -g -Os -m32  libgcc.a -lc 

PATH=/home/ray/ctng-firefox-builds/x-l-HEAD-x86_64/bin:/home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/x86_64-unknown-linux-gnu/buildtools/bin:/home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/tools/bin:/home/ray/bin:/usr/local/sbin:/usr/local/bin:/usr/bin:/usr/bin/vendor_perl:/usr/bin/core_perl:/home/ray/ctng-firefox-builds//bin gdbserver 127.0.0.1:6900 /home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/x86_64-unknown-linux-gnu/build/build-cc-gcc-core-pass-2/./gcc/xgcc \
-B/home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/x86_64-unknown-linux-gnu/build/build-cc-gcc-core-pass-2/./gcc/ -B/home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/x86_64-unknown-linux-gnu/buildtools/x86_64-unknown-linux-gnu/bin/ -B/home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/x86_64-unknown-linux-gnu/buildtools/x86_64-unknown-linux-gnu/lib/ \
-m32 -lc -v -fno-stack-protector  -shared -nodefaultlibs -Wl,--soname=libgcc_s.so.1 -Wl,--version-script=libgcc.map -o 32/libgcc_s.so.1.tmp -g -Os -m32  libgcc.a -lc 

Gives:
LIBRARY_PATH=/home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/x86_64-unknown-linux-gnu/build/build-cc-gcc-core-pass-2/./gcc/32/:/home/ray/ctng-firefox-builds/x-l-HEAD-x86_64/x86_64-unknown-linux-gnu/sysroot/lib/../lib/:/home/ray/ctng-firefox-builds/x-l-HEAD-x86_64/x86_64-unknown-linux-gnu/sysroot/usr/lib/../lib/:/home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/x86_64-unknown-linux-gnu/build/build-cc-gcc-core-pass-2/./gcc/:/home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/x86_64-unknown-linux-gnu/buildtools/x86_64-unknown-linux-gnu/bin/:/home/ray/ctng-firefox-builds/x-l-HEAD-x86_64/x86_64-unknown-linux-gnu/sysroot/lib/:/home/ray/ctng-firefox-builds/x-l-HEAD-x86_64/x86_64-unknown-linux-gnu/sysroot/usr/lib/


# Some info from MinGW-w64 about multilib cross compilers: http://sourceforge.net/apps/trac/mingw-w64/wiki/Cross%20Win32%20and%20Win64%20compiler
# Binutils:
../path/to/configure --target=x86_64-w64-mingw32 \
--enable-targets=x86_64-w64-mingw32,i686-w64-mingw32

[DEBUG]    ==> Executing: 'CFLAGS=-O0 -ggdb -pipe ' 'CXXFLAGS=-O0 -ggdb -pipe ' 'LDFLAGS= ' '/home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/src/binutils-2.22/configure' '--build=x86_64-build_unknown-linux-gnu' '--host=x86_64-build_unknown-linux-gnu' '--target=x86_64-unknown-linux-gnu' '--prefix=/home/ray/ctng-firefox-builds/x-l-HEAD-x86_64' '--disable-werror' '--enable-ld=yes' '--enable-gold=no' '--with-pkgversion=crosstool-NG hg+unknown-20131121.233230' '--enable-multilib' '--disable-nls' '--with-sysroot=/home/ray/ctng-firefox-builds/x-l-HEAD-x86_64/x86_64-unknown-linux-gnu/sysroot' 
# Oddly neither --enable-targets nor --enable-multilib show up from configure --help, and --enable-targets doesn't appear in the script either (--enable-multilib does though)
# It seems like binutils targets can be specified as any free parameters on the end due to:
# *) as_fn_append ac_config_targets " $1"


# GCC:
For multilib:
../path/to/configure --target=x86_64-w64-mingw32 --enable-targets=all

.. I added:

    if [ "${CT_MULTILIB}" = "y" ]; then
        extra_config+=("--enable-multilib")
        extra_config+=("--enable-targets=all")
    else
        extra_config+=("--disable-multilib")
    fi

.. to 100-gcc.sh but it made no difference.


# A difference comparer:
export TEHCC=/home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/x86_64-unknown-linux-gnu/build/build-cc-gcc-core-pass-2/./gcc/xgcc ; export OPTS="-isystem arse -B. -B/home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/x86_64-unknown-linux-gnu/build/build-cc-gcc-core-pass-2/./gcc/"; $TEHCC ~/Dropbox/a.c $OPTS -m64 -v > ~/Dropbox/m64.txt 2>&1; $TEHCC ~/Dropbox/a.c $OPTS -m32 -v > ~/Dropbox/m32.txt 2>&1
export TEHCC=gcc ; export OPTS="-isystem arse -B. -B/home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/x86_64-unknown-linux-gnu/build/build-cc-gcc-core-pass-2/./gcc/"; $TEHCC ~/Dropbox/a.c $OPTS -m64 -v > ~/Dropbox/m64.txt 2>&1; $TEHCC ~/Dropbox/a.c $OPTS -m32 -v > ~/Dropbox/m32.txt 2>&1

# bcompare ~/Dropbox/m32.txt ~/Dropbox/m64.txt &

.. At the end of the day, "-B./" is the problem, we got  -m32 -B./ 
and according to:
http://gcc.gnu.org/onlinedocs/gcc/Directory-Options.html
"The runtime support file libgcc.a can also be searched for using the -B prefix, if needed. If it is not found there, the two standard prefixes above are tried, and that is all. The file is left out of the link if it is not found by those means."

# More, so I guess my dummy libc's need to be put in the right folders, which appear to be the stage 2 libgcc folders?
# i.e. /home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/x86_64-unknown-linux-gnu/build/build-cc-gcc-core-pass-2/x86_64-unknown-linux-gnu/32/libgcc
#  and /home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/x86_64-unknown-linux-gnu/build/build-cc-gcc-core-pass-2/x86_64-unknown-linux-gnu/32/libgcc/m32
# http://www.emdebian.org/~zumbi/sysroot/gcc-4.6-arm-sysroot-linux-gnueabihf-0.1/build-sysroot

# Seems like an interesting page:
# http://trac.cross-lfs.org/
# CLFS takes advantage of the target system's capability, by utilizing a multilib capable build system
# CLFS-x86.pdf is a very useful document.

pushd ~/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64/.build/x86_64-unknown-linux-gnu/build/build-cc-gcc-core-pass-1/gcc
build/gengtype.exe                      -S /home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64-235295c4/.build/src/gcc-4.8.2/gcc -I gtyp-input.list -w tmp-gtype.state

isl problems (ffs).
pushd /home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64-235295c4/.build/x86_64-unknown-linux-gnu/build/build-isl-host-x86_64-build_w64-mingw32
rm ./libisl_la-isl_map_simplify.*
export PATH=/home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64-235295c4/.build/x86_64-unknown-linux-gnu/buildtools/bin:$PATH
  make V=1

# Leads to:
x86_64-build_w64-mingw32-gcc -DHAVE_CONFIG_H -I. -I/home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64-235295c4/.build/src/isl-0.11.1 -I/home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64-235295c4/.build/src/isl-0.11.1/include -Iinclude/ -I. -I/home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64-235295c4/.build/src/isl-0.11.1 -I/home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64-235295c4/.build/src/isl-0.11.1/include -Iinclude/ -I/home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64-235295c4/.build/x86_64-unknown-linux-gnu/buildtools/include -O0 -ggdb -pipe -D__USE_MINGW_ANSI_STDIO=1 -MT libisl_la-isl_map_simplify.lo -MD -MP -MF .deps/libisl_la-isl_map_simplify.Tpo -c /home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64-235295c4/.build/src/isl-0.11.1/isl_map_simplify.c -o libisl_la-isl_map_simplify.o


# My old gengtypes patch isn't working?!
export PATH=/home/ray/ctng-firefox-builds/x-l-HEAD-x86_64-235295c4/bin:/home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64-235295c4/.build/x86_64-unknown-linux-gnu/buildtools/bin:$PATH
CC_FOR_BUILD=x86_64-build_w64-mingw32-gcc CFLAGS_FOR_BUILD= CFLAGS="-O0 -ggdb -pipe  -D__USE_MINGW_ANSI_STDIO=1" \
  CXXFLAGS="-O0 -ggdb -pipe  -D__USE_MINGW_ANSI_STDIO=1" LDFLAGS= \
/home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64-235295c4/.build/src/gcc-4.8.2/configure \
  --build=x86_64-build_w64-mingw32 --host=x86_64-build_w64-mingw32 --target=x86_64-unknown-linux-gnu \
  --prefix=/home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64-235295c4/.build/x86_64-unknown-linux-gnu/buildtools \
  --with-local-prefix=/home/ray/ctng-firefox-builds/x-l-HEAD-x86_64-235295c4/x86_64-unknown-linux-gnu/sysroot \
  --disable-libmudflap --with-sysroot=/home/ray/ctng-firefox-builds/x-l-HEAD-x86_64-235295c4/x86_64-unknown-linux-gnu/sysroot \
  --with-newlib --enable-threads=no --disable-shared --with-pkgversion=crosstool-NG hg+unknown-20131201.170407 \
  --enable-__cxa_atexit --with-gmp=/home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64-235295c4/.build/x86_64-unknown-linux-gnu/buildtools \
  --with-mpfr=/home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64-235295c4/.build/x86_64-unknown-linux-gnu/buildtools \
  --with-mpc=/home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64-235295c4/.build/x86_64-unknown-linux-gnu/buildtools \
  --with-isl=/home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64-235295c4/.build/x86_64-unknown-linux-gnu/buildtools \
  --with-cloog=/home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64-235295c4/.build/x86_64-unknown-linux-gnu/buildtools \
  --with-libelf=/home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64-235295c4/.build/x86_64-unknown-linux-gnu/buildtools \
  --enable-lto --with-host-libstdcxx="-static-libgcc -Wl,-Bstatic,-lstdc++,-Bdynamic -lm" \
  --enable-target-optspace --disable-libgomp --disable-libmudflap --disable-nls --enable-multilib --enable-targets=all --enable-languages=c


/home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64-235295c4/.build/src/gcc-4.8.2/gcc/configure \
--cache-file=./config.cache --prefix=/home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64-235295c4/.build/x86_64-unknown-linux-gnu/buildtools \
--with-local-prefix=/home/ray/ctng-firefox-builds/x-l-HEAD-x86_64-235295c4/x86_64-unknown-linux-gnu/sysroot \
--with-sysroot=/home/ray/ctng-firefox-builds/x-l-HEAD-x86_64-235295c4/x86_64-unknown-linux-gnu/sysroot --with-newlib --enable-threads=no \
--disable-shared --with-pkgversion=crosstool-NG hg+unknown-20131201.170407 --enable-__cxa_atexit \
--with-gmp=/home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64-235295c4/.build/x86_64-unknown-linux-gnu/buildtools \
--with-mpfr=/home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64-235295c4/.build/x86_64-unknown-linux-gnu/buildtools \
--with-mpc=/home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64-235295c4/.build/x86_64-unknown-linux-gnu/buildtools \
--with-isl=/home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64-235295c4/.build/x86_64-unknown-linux-gnu/buildtools \
--with-cloog=/home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64-235295c4/.build/x86_64-unknown-linux-gnu/buildtools \
--with-libelf=/home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64-235295c4/.build/x86_64-unknown-linux-gnu/buildtools \
--enable-lto --with-host-libstdcxx="-static-libgcc -Wl,-Bstatic,-lstdc++,-Bdynamic -lm" \
--enable-target-optspace --disable-libgomp --disable-libmudflap --disable-nls --enable-multilib --enable-targets=all --enable-languages=c,lto \
--program-transform-name="s&^&x86_64-unknown-linux-gnu-&" --disable-option-checking \
--build=x86_64-build_w64-mingw32 --host=x86_64-build_w64-mingw32 --target=x86_64-unknown-linux-gnu \
--srcdir=/home/ray/ctng-firefox-builds/ctng-build-x-l-HEAD-x86_64-235295c4/.build/src/gcc-4.8.2/gcc



# Current working directory isn't searched on Windows for cc1; well, it is, but not with .exe extension.
# C:\msys64\home\ukrdonnell\ctng-firefox-builds\ctng-build-x-r-HEAD-x86_64-235295c4\.build\src\gcc-4.8.2\libiberty\pex-win32.c

# Got a potential fix .. maybe not, but it fixed the issue when debugging under QtCreator at least.
cp ~/Dropbox/pex-win32.c C:/msys64/home/ukrdonnell/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/src/gcc-4.8.2/libiberty
pushd C:/msys64/home/ukrdonnell/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-cc-gcc-core-pass-1
export PATH=/home/ukrdonnell/ctng-firefox-builds/x-r-HEAD-x86_64-235295c4/bin:/home/ukrdonnell/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/buildtools/bin:/home/ukrdonnell/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/tools/bin:/home/ukrdonnell/ctng-firefox-builds/mingw64-235295c4/bin:$PATH


# Despite that patch seeming to work (it arguably shouldn't be needed due to -B flag anyway):
[ALL  ]    echo "" | /home/ukrdonnell/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-cc-gcc-core-pass-1/./gcc/xgcc -B/home/ukrdonnell/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-cc-gcc-core-pass-1/./gcc/ -E -dM - |   sed -n -e 's/^#define ([^_][a-zA-Z0-9_]*).*/1/p' 	 -e 's/^#define (_[^_A-Z][a-zA-Z0-9_]*).*/1/p' |   sort -u > tmp-macro_list
[ALL  ]    echo GCC_CFLAGS = '-g -Os -DIN_GCC -DCROSS_DIRECTORY_STRUCTURE  -W -Wall -Wno-narrowing -Wwrite-strings -Wcast-qual -Wstrict-prototypes -Wmissing-prototypes -Wold-style-definition  -isystem ./include ' >> tmp-libgcc.mvars
[ALL  ]    if /home/ukrdonnell/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-cc-gcc-core-pass-1/./gcc/xgcc -B/home/ukrdonnell/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-cc-gcc-core-pass-1/./gcc/ -print-sysroot-headers-suffix > /dev/null 2>&1; then   set -e; for ml in `/home/ukrdonnell/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-cc-gcc-core-pass-1/./gcc/xgcc -B/home/ukrdonnell/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-cc-gcc-core-pass-1/./gcc/ -print-multi-lib`; do     multi_dir=`echo ${ml} | sed -e 's/;.*$//'`;     flags=`echo ${ml} | sed -e 's/^[^;]*;//' -e 's/@/ -/g'`;     sfx=`/home/ukrdonnell/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-cc-gcc-core-pass-1/./gcc/xgcc -B/home/ukrdonnell/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-cc-gcc-core-pass-1/./gcc/ ${flags} -print-sysroot-headers-suffix`;     if [ "${multi_dir}" = "." ];       then multi_dir="";     else       multi_dir=/${multi_dir};     fi;     echo "${sfx};${multi_dir}";   done; else   echo ";"; fi > tmp-fixinc_list
[ALL  ]    echo INHIBIT_LIBC_CFLAGS = '-Dinhibit_libc' >> tmp-libgcc.mvars
[ERROR]    xgcc.exe: error: CreateProcess: No such file or directory
[ALL  ]    /usr/bin/bash /home/ukrdonnell/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/src/gcc-4.8.2/gcc/../move-if-change tmp-macro_list macro_list



.. hmm something in the env is bad, to repro:
pushd $HOME/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/src/linux-3.10.19
. ~/Dropbox/ctng-firefox-builds/env.sh
pushd $HOME/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-kernel-headers
make -C $HOME/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/src/linux-3.10.19 O=$HOME/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-kernel-headers ARCH=arm INSTALL_HDR_PATH=$HOME/ctng-firefox-builds/x-r-HEAD-x86_64-235295c4/armv6hl-unknown-linux-gnueabi/sysroot/usr V=1 headers_install

.. problem is the internal processing in fixdep.exe (or maybe the inputs to it)

pushd C:/msys64/home/ukrdonnell/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-kernel-headers/
C:/msys64/home/ukrdonnell/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-kernel-headers/scripts/basic/fixdep.exe scripts/basic/.fixdep.d scripts/basic/fixdep "gcc -Wp,-MD,scripts/basic/.fixdep.d -Iscripts/basic -Wall -Wmissing-prototypes -Wstrict-prototypes -O2 -fomit-frame-pointer -o scripts/basic/fixdep /home/ukrdonnell/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/src/linux-3.10.19/scripts/basic/fixdep.c  "


# Windows build of unifdef is broken .. here's how to test making a fix for it.
export PATH=~/ctng-firefox-builds/mingw64-235295c4/bin:$PATH

ROOT=/tmp/kern-head
INSTROOT=/tmp/kern-head/install
mkdir -p $INSTROOT
[ -d $ROOT/src ] || (
  mkdir -p $ROOT/src
  pushd $ROOT/src
  tar -xf ~/src/linux-3.10.19.tar.xz
  pushd linux-3.10.19
  patch -p1 < ~/ctng-firefox-builds/crosstool-ng/patches/linux/3.10.19/120-unifdef-win32.patch
  popd
  git clone git://dotat.at/unifdef.git
  popd
)

mkdir -p $ROOT/armv6hl-unknown-linux-gnueabi/build/build-kernel-headers
pushd $ROOT/armv6hl-unknown-linux-gnueabi/build/build-kernel-headers; make -C $ROOT/src/linux-3.10.19 O=$ROOT/armv6hl-unknown-linux-gnueabi/build/build-kernel-headers ARCH=arm INSTALL_HDR_PATH=$INSTROOT/armv6hl-unknown-linux-gnueabi/sysroot/usr V=1 headers_install; popd

# Making new unifdef patches for Linux Kernel headers_install.
# First, remove any existing unifdef patches!
KVER=3.10.19
ROOT=/tmp/kern-head.new
rm -rf $ROOT
INSTROOT=$ROOT/install
mkdir -p $INSTROOT
mkdir -p $ROOT/armv6hl-unknown-linux-gnueabi/build/build-kernel-headers
[ -d $ROOT/src ] || mkdir -p $ROOT/src
  pushd $ROOT/src
   tar -xf ~/src/linux-${KVER}.tar.xz
   # Apply any existing patches.
   pushd linux-${KVER}
   PATCHES=$(find ~/ctng-firefox-builds/crosstool-ng/patches/linux/${KVER} -name "*.patch" | sort)
   for PATCH in $PATCHES; do
#     if [ "${PATCH/unifdef/}" = "$PATCH" ]; then
       echo "Applying pre-existing kernel patch $PATCH"
       patch -p1 < $PATCH
#     fi
   done
   popd
   cp -rf linux-${KVER} linux-${KVER}.orig
   pushd linux-${KVER}/scripts
    pushd /tmp
     [ -d unifdef ] && rm -rf unifdef
     git clone git://dotat.at/unifdef.git
     pushd unifdef
      ./scripts/reversion.sh
     popd
    popd
    mkdir unifdef-upstream
    mkdir unifdef-upstream/FreeBSD
    mkdir unifdef-upstream/win32
    cp -f /tmp/unifdef/COPYING          unifdef-upstream/
    # Duplicate all files into platform specific subdirs.
    cp -f /tmp/unifdef/FreeBSD/err.c    unifdef-upstream/win32/
    cp -f /tmp/unifdef/FreeBSD/getopt.c unifdef-upstream/win32/
    cp -f /tmp/unifdef/win32/win32.c    unifdef-upstream/win32/
    cp -f /tmp/unifdef/win32/unifdef.h  unifdef-upstream/win32/
    cp -f /tmp/unifdef/unifdef.c        unifdef-upstream/win32/
    cp -f /tmp/unifdef/version.h        unifdef-upstream/win32/
   popd
   pushd linux-${KVER}
   # Patch the Makefile.
    patch -p1 <<- "EOF"
	--- linux-3.10.19.orig/scripts/Makefile      2013-11-13 03:05:59.000000000 +0000
	+++ linux-3.10.19.orig/scripts/Makefile   2013-12-06 11:07:46.000000000 +0000
	@@ -26,6 +26,15 @@
	 # The following hostprogs-y programs are only build on demand
	 hostprogs-y += unifdef docproc
	
	+cc_machine := $(shell $(CC) -dumpmachine)
	+ifneq (, $(findstring linux, $(cc_machine)))
	+  unifdef-objs := unifdef.o
	+else
	+  ifneq (, $(findstring mingw, $(cc_machine)))
	+    unifdef-objs := unifdef-upstream/win32/unifdef.o unifdef-upstream/win32/err.o unifdef-upstream/win32/getopt.o unifdef-upstream/win32/win32.o
	+  endif
	+endif
	+
	 # These targets are used internally to avoid "is up to date" messages
	 PHONY += build_unifdef
	 build_unifdef: scripts/unifdef FORCE
	EOF
   popd
  popd

pushd $ROOT/src
find . -type f -and \( -name "*.orig" -or -name "*.rej" \) -exec rm {} \;
[ -d ~/ctng-firefox-builds/crosstool-ng/patches/linux/${KVER} ] || mkdir -p ~/ctng-firefox-builds/crosstool-ng/patches/linux/${KVER}
#diff -urN linux-${KVER}.orig linux-${KVER} > ~/ctng-firefox-builds/crosstool-ng/patches/linux/${KVER}/120-Win32-FreeBSD-use-upstream-unifdef.patch2
diff -urN linux-${KVER}.orig linux-${KVER} > ~/Dropbox/120-Win32-FreeBSD-use-upstream-unifdef.patch.${KVER}
popd

# Testing it:
mkdir -p $ROOT/armv6hl-unknown-linux-gnueabi/build/build-kernel-headers
pushd $ROOT/armv6hl-unknown-linux-gnueabi/build/build-kernel-headers; make -C $ROOT/src/linux-${KVER} O=$ROOT/armv6hl-unknown-linux-gnueabi/build/build-kernel-headers ARCH=arm INSTALL_HDR_PATH=$INSTROOT/armv6hl-unknown-linux-gnueabi/sysroot/usr V=1 headers_install; popd

make install_root=/home/ray/ctng-firefox-builds/x-r-none-4_8_2-x86_64-235295c4/armv6hl-unknown-linux-gnueabi/sysroot install-bootstrap-headers=yes
-C $ROOT/src/linux-${KVER} O=$ROOT/armv6hl-unknown-linux-gnueabi/build/build-kernel-headers ARCH=arm INSTALL_HDR_PATH=$INSTROOT/armv6hl-unknown-linux-gnueabi/sysroot/usr V=1 headers_install; popd

cat ~/Dropbox/ctng-firefox-builds/120-win32-use-upstream-unifdef.patch

pushd armv6hl-unknown-linux-gnueabi/build/build-kernel-headers
gcc -Wp,-MD,scripts/unifdef-upstream/FreeBSD/.err.o.d -Iscripts -Wall -Wmissing-prototypes -Wstrict-prototypes -O2 -fomit-frame-pointer   -I/Users/raydonnelly/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64/.build/src/linux-3.10.19/tools/include -c -o scripts/unifdef-upstream/FreeBSD/err.o /Users/raydonnelly/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64/.build/src/linux-3.10.19/scripts/unifdef-upstream/FreeBSD/err.c


# Hang when --target-os=ps3 during patch cloog-ppl-0.15.11 seems to be from:

EXTRA]    Patching 'cloog-ppl-0.15.11'
[00:30] / /home/ray/ctng-firefox-builds/lib/ct-ng.hg+unknown-20131207.020612/scripts/functions: line 216: 92084 Terminated              ( for i in "$@";
do
    cur_cmd+="'${i}' ";
done; while true; do
    case "${1}" in
        *=*)
            eval export "'${1}'"; shift
        ;;
        *)
            break
        ;;
    esac;
done; while true; do
    rm -f "${CT_BUILD_DIR}/repeat"; CT_DoLog DEBUG "==> Executing: ${cur_cmd}"; "${@}" 2>&1 | CT_DoLog "${level}"; ret="${?}"; if [ -f "${CT_BUILD_DIR}/repeat" ]; then
        rm -f "${CT_BUILD_DIR}/repeat"; continue;
    else
        if [ -f "${CT_BUILD_DIR}/skip" ]; then
            rm -f "${CT_BUILD_DIR}/skip"; ret=0; break;
        else
            break;
        fi;
    fi;
done; exit ${ret} )
[ERROR]  >>
[ERROR]  >>  Build failed in step 'Extracting and patching toolchain components'
[ERROR]  >>        called in step '(top-level)'
[ERROR]  >>
[ERROR]  >>  Error happened in: CT_DoExecLog[scripts/functions@216]
[ERROR]  >>        called from: do_cloog_extract[scripts/build/companion_libs/130-cloog.sh@47]
[ERROR]  >>        called from: do_companion_libs_extract[scripts/build/companion_libs.sh@22]
[ERROR]  >>        called from: main[scripts/crosstool-NG.sh@649]
[ERROR]  >>
[ERROR]  >>  For more info on this error, look at the file: 'build.log'
[ERROR]  >>  There is a list of known issues, some with workarounds, in:
[ERROR]  >>      '/home/ray/ctng-firefox-builds/share/doc/crosstool-ng/ct-ng.hg+unknown-20131207.020612/B - Known issues.txt'
[ERROR]
[ERROR]  (elapsed: 17:29.38)
[17:32] / /home/ray/ctng-firefox-builds//bin/ct-ng:148: recipe for target 'build' failed
make: *** [build] Error 143

# On Linux a hang in the same place seemed to be libtoolize related.

# build.log contains:
[DEBUG]    Entering '/home/ray/ctng-firefox-builds/ctng-build-x-p-HEAD-x86_64-235295c4/.build/src/cloog-ppl-0.15.11'
[DEBUG]    ==> Executing: './autogen.sh'


# CreateProcess error leads to a make error which doesn't propagate
pushd /home/ray/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-cc-gcc-core-pass-1/gcc
if /home/ray/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-cc-gcc-core-pass-1/./gcc/xgcc -B/home/ray/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-cc-gcc-core-pass-1/./gcc/ -print-sysroot-headers-suffix > /dev/null 2>&1; then   set -e; for ml in `/home/ray/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-cc-gcc-core-pass-1/./gcc/xgcc -B/home/ray/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-cc-gcc-core-pass-1/./gcc/ -print-multi-lib`; do     multi_dir=`echo ${ml} | sed -e 's/;.*$//'`;     flags=`echo ${ml} | sed -e 's/^[^;]*;//' -e 's/@/ -/g'`;     sfx=`/home/ray/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-cc-gcc-core-pass-1/./gcc/xgcc -B/home/ray/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-cc-gcc-core-pass-1/./gcc/ ${flags} -print-sysroot-headers-suffix`;     if [ "${multi_dir}" = "." ];       then multi_dir="";     else       multi_dir=/${multi_dir};     fi;     echo "${sfx};${multi_dir}";   done; else   echo ";"; fi > tmp-fixinc_list
[ERROR]    xgcc.exe: error: CreateProcess: No such file or directory
[ALL  ]    make[2]: Leaving directory '/home/ray/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-cc-gcc-core-pass-1/gcc'
[ALL  ]    make[1]: INTERNAL: Exiting with 8 jobserver tokens available; should be 9!


# General flakiness?!
# pushd /home/ray/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-cc-gcc-core-pass-1
# export PATH=~/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/buildtools/bin:$PATH
# /usr/bin/make "DESTDIR=" "RPATH_ENVVAR=PATH" "TARGET_SUBDIR=armv6hl-unknown-linux-gnueabi" "bindir=/home/ray/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/buildtools/bin" "datadir=/home/ray/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/buildtools/share" "exec_prefix=/home/ray/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/buildtools" "includedir=/home/ray/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/buildtools/include" "datarootdir=/home/ray/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/buildtools/share" "docdir=/home/ray/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/buildtools/share/doc/" "infodir=/home/ray/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/buildtools/share/info" "pdfdir=/home/ray/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/buildtools/share/doc/" "htmldir=/home/ray/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/buildtools/share/doc/" "libdir=/home/ray/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/buildtools/lib" "libexecdir=/home/ray/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/buildtools/libexec" "lispdir=" "localstatedir=/home/ray/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/buildtools/var" "mandir=/home/ray/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/buildtools/share/man" "oldincludedir=/usr/include" "prefix=/home/ray/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/buildtools" "sbindir=/home/ray/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/buildtools/sbin" "sharedstatedir=/home/ray/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/buildtools/com" "sysconfdir=/home/ray/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/buildtools/etc" "tooldir=/home/ray/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/buildtools/armv6hl-unknown-linux-gnueabi" "build_tooldir=/home/ray/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/buildtools/armv6hl-unknown-linux-gnueabi" "target_alias=armv6hl-unknown-linux-gnueabi" "AWK=gawk" "BISON=bison" "CC_FOR_BUILD=x86_64-build_w64-mingw32-gcc" "CFLAGS_FOR_BUILD=" "CXX_FOR_BUILD=x86_64-build_w64-mingw32-g++" "EXPECT=expect" "FLEX=flex" "INSTALL=/home/ray/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/tools/bin/install -c" "INSTALL_DATA=/home/ray/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/tools/bin/install -c -m 644" "INSTALL_PROGRAM=/home/ray/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/tools/bin/install -c" "INSTALL_SCRIPT=/home/ray/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/tools/bin/install -c" "LDFLAGS_FOR_BUILD=" "LEX=flex" "M4=m4" "MAKE=/usr/bin/make" "RUNTEST=runtest" "RUNTESTFLAGS=" "SED=/home/ray/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/tools/bin/sed" "SHELL=/usr/bin/bash" "YACC=bison -y" "`echo 'ADAFLAGS=' | sed -e s'/[^=][^=]*=$/XFOO=/'`" "ADA_CFLAGS=" "AR_FLAGS=rc" "`echo 'BOOT_ADAFLAGS=-gnatpg' | sed -e s'/[^=][^=]*=$/XFOO=/'`" "BOOT_CFLAGS=-g -O2 -D__USE_MINGW_ACCESS -Wno-pedantic-ms-format" "BOOT_LDFLAGS= -Wl,--stack,12582912" "CFLAGS=-O0 -ggdb -pipe  -D__USE_MINGW_ANSI_STDIO=1 -D__USE_MINGW_ACCESS" "CXXFLAGS=-O0 -ggdb -pipe  -D__USE_MINGW_ANSI_STDIO=1" "LDFLAGS= -Wl,--stack,12582912" "LIBCFLAGS=-O0 -ggdb -pipe  -D__USE_MINGW_ANSI_STDIO=1 -D__USE_MINGW_ACCESS" "LIBCXXFLAGS=-O0 -ggdb -pipe  -D__USE_MINGW_ANSI_STDIO=1 -fno-implicit-templates" "STAGE1_CHECKING=--enable-checking=yes,types" "STAGE1_LANGUAGES=c,lto" "GNATBIND=x86_64-build_w64-mingw32-gnatbind" "GNATMAKE=x86_64-build_w64-mingw32-gnatmake" "AR_FOR_TARGET=/home/ray/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/buildtools/armv6hl-unknown-linux-gnueabi/bin/ar" "AS_FOR_TARGET=/home/ray/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/buildtools/armv6hl-unknown-linux-gnueabi/bin/as" "CC_FOR_TARGET= $r/./gcc/xgcc -B$r/./gcc/" "CFLAGS_FOR_TARGET=-g -Os" "CPPFLAGS_FOR_TARGET=" "CXXFLAGS_FOR_TARGET=-g -Os" "DLLTOOL_FOR_TARGET=armv6hl-unknown-linux-gnueabi-dlltool" "FLAGS_FOR_TARGET=-B/home/ray/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/buildtools/armv6hl-unknown-linux-gnueabi/bin/ -B/home/ray/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/buildtools/armv6hl-unknown-linux-gnueabi/lib/ -isystem /home/ray/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/buildtools/armv6hl-unknown-linux-gnueabi/include -isystem /home/ray/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/buildtools/armv6hl-unknown-linux-gnueabi/sys-include" "GCJ_FOR_TARGET= armv6hl-unknown-linux-gnueabi-gcj" "GFORTRAN_FOR_TARGET= armv6hl-unknown-linux-gnueabi-gfortran" "GOC_FOR_TARGET= armv6hl-unknown-linux-gnueabi-gccgo" "GOCFLAGS_FOR_TARGET=-O2 -g" "LD_FOR_TARGET=/home/ray/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/buildtools/armv6hl-unknown-linux-gnueabi/bin/ld" "LIPO_FOR_TARGET=armv6hl-unknown-linux-gnueabi-lipo" "LDFLAGS_FOR_TARGET=" "LIBCFLAGS_FOR_TARGET=-g -Os" "LIBCXXFLAGS_FOR_TARGET=-g -Os -fno-implicit-templates" "NM_FOR_TARGET=armv6hl-unknown-linux-gnueabi-nm" "OBJDUMP_FOR_TARGET=armv6hl-unknown-linux-gnueabi-objdump" "RANLIB_FOR_TARGET=/home/ray/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/buildtools/armv6hl-unknown-linux-gnueabi/bin/ranlib" "READELF_FOR_TARGET=armv6hl-unknown-linux-gnueabi-readelf" "STRIP_FOR_TARGET=/home/ray/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/buildtools/armv6hl-unknown-linux-gnueabi/bin/strip" "WINDRES_FOR_TARGET=armv6hl-unknown-linux-gnueabi-windres" "WINDMC_FOR_TARGET=armv6hl-unknown-linux-gnueabi-windmc" "BUILD_CONFIG=" "`echo 'LANGUAGES=' | sed -e s'/[^=][^=]*=$/XFOO=/'`" "LEAN=false" "STAGE1_CFLAGS=-g" "STAGE1_CXXFLAGS=-O0 -ggdb -pipe  -D__USE_MINGW_ANSI_STDIO=1" "STAGE1_TFLAGS=" "STAGE2_CFLAGS=-g -O2 -D__USE_MINGW_ACCESS -Wno-pedantic-ms-format" "STAGE2_CXXFLAGS=-O0 -ggdb -pipe  -D__USE_MINGW_ANSI_STDIO=1" "STAGE2_TFLAGS=" "STAGE3_CFLAGS=-g -O2 -D__USE_MINGW_ACCESS -Wno-pedantic-ms-format" "STAGE3_CXXFLAGS=-O0 -ggdb -pipe  -D__USE_MINGW_ANSI_STDIO=1" "STAGE3_TFLAGS=" "STAGE4_CFLAGS=-g -O2 -D__USE_MINGW_ACCESS -Wno-pedantic-ms-format" "STAGE4_CXXFLAGS=-O0 -ggdb -pipe  -D__USE_MINGW_ANSI_STDIO=1" "STAGE4_TFLAGS=" "STAGEprofile_CFLAGS=-g -O2 -D__USE_MINGW_ACCESS -Wno-pedantic-ms-format -fprofile-generate" "STAGEprofile_CXXFLAGS=-O0 -ggdb -pipe  -D__USE_MINGW_ANSI_STDIO=1" "STAGEprofile_TFLAGS=" "STAGEfeedback_CFLAGS=-g -O2 -D__USE_MINGW_ACCESS -Wno-pedantic-ms-format -fprofile-use" "STAGEfeedback_CXXFLAGS=-O0 -ggdb -pipe  -D__USE_MINGW_ANSI_STDIO=1" "STAGEfeedback_TFLAGS=" "CXX_FOR_TARGET= armv6hl-unknown-linux-gnueabi-c++" "TFLAGS=" "CONFIG_SHELL=/usr/bin/bash" "MAKEINFO=makeinfo --split-size=5000000" 'AR=x86_64-build_w64-mingw32-ar' 'AS=x86_64-build_w64-mingw32-as' 'CC=x86_64-build_w64-mingw32-gcc' 'CXX=x86_64-build_w64-mingw32-g++' 'DLLTOOL=x86_64-build_w64-mingw32-dlltool' 'GCJ=' 'GFORTRAN=' 'GOC=' 'LD=c:/msys64/home/ray/ctng-firefox-builds/mingw64-235295c4/bin/../lib/gcc/x86_64-w64-mingw32/4.8.2/../../../../x86_64-w64-mingw32/bin/ld.exe' 'LIPO=lipo' 'NM=x86_64-build_w64-mingw32-nm' 'OBJDUMP=x86_64-build_w64-mingw32-objdump' 'RANLIB=x86_64-build_w64-mingw32-ranlib' 'READELF=readelf' 'STRIP=x86_64-build_w64-mingw32-strip' 'WINDRES=x86_64-build_w64-mingw32-windres' 'WINDMC=windmc' LDFLAGS="${LDFLAGS}" HOST_LIBS="${HOST_LIBS}" "GCC_FOR_TARGET= $r/./gcc/xgcc -B$r/./gcc/" "`echo 'STMP_FIXPROTO=' | sed -e s'/[^=][^=]*=$/XFOO=/'`" "`echo 'LIMITS_H_TEST=' | sed -e s'/[^=][^=]*=$/XFOO=/'`" all
# ...
# echo "" | "C:/msys64/home/ray/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-cc-gcc-core-pass-1/gcc/cc1.exe" "-E" "-quiet" "-iprefix" "c:\msys64\home\ray\ctng-firefox-builds\ctng-build-x-r-head-x86_64-235295c4\.build\armv6hl-unknown-linux-gnueabi\build\build-cc-gcc-core-pass-1\gcc\../lib/gcc/armv6hl-unknown-linux-gnueabi/4.8.2/" "-" "-march=armv6" "-mtune=arm1176jzf-s" "-mfloat-abi=hard" "-mfpu=vfp" "-mtls-dialect=gnu" "-dM"

.. where its at:

[INFO ]  Installing pass-1 core C gcc compiler
[EXTRA]    Configuring core C gcc compiler
[EXTRA]    Building core C gcc compiler
[ERROR]    cc1.exe: error: no include path in which to search for stdc-predef.h
[EXTRA]    Installing core C gcc compiler
[INFO ]  Installing pass-1 core C gcc compiler: done in 1833.37s (at 72:13)
[EXTRA]  Saving state to restart at step 'kernel_headers'...
[INFO ]  =================================================================
[INFO ]  Installing kernel headers
[EXTRA]    Installing kernel headers
[EXTRA]    Checking installed headers
[INFO ]  Installing kernel headers: done in 192.54s (at 75:35)
[EXTRA]  Saving state to restart at step 'libc_start_files'...
[INFO ]  =================================================================
[INFO ]  Installing C library headers & start files
[EXTRA]    Configuring C library
[EXTRA]    Installing C library headers
[ERROR]    rpc_main.c:41:21: fatal error: libintl.h: No such file or directory
[ERROR]    make[3]: *** [/home/ray/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-startfiles/sunrpc/cross-rpc_main.o] Error 1
[ERROR]    make[2]: *** [sunrpc/install-headers] Error 2
[ERROR]    make[1]: *** [install-headers] Error 2


mkdir /tmp/gettext
pushd /tmp/gettext
CFLAGS= LDFLAGS= /home/ray/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/src/gettext-0.18.3.1/configure --prefix=/home/ray/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/buildtools

pushd /home/ray/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-libiconv-build-x86_64-build_w64-mingw32/lib
/usr/bin/bash ../libtool --mode=compile x86_64-build_w64-mingw32-gcc -O0 -ggdb  -D__USE_MINGW_ANSI_STDIO=1 -I. -I/home/ray/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/src/libiconv-1.14/lib -I../include -I/home/ray/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/src/libiconv-1.14/lib/../include -I.. -I/home/ray/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/src/libiconv-1.14/lib/..  -fvisibility=hidden -DLIBDIR="/home/ray/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/buildtools/lib" -DBUILDING_LIBICONV -DBUILDING_DLL -DENABLE_RELOCATABLE=1 -DIN_LIBRARY -DINSTALLDIR="/home/ray/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/buildtools/lib" -DNO_XMALLOC -Dset_relocation_prefix=libiconv_set_relocation_prefix -Drelocate=libiconv_relocate -DHAVE_CONFIG_H -c /home/ray/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/src/libiconv-1.14/lib/iconv.c


#pushd /home/ray/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-gettext-build-x86_64-build_w64-mingw32
export PATH=/home/ray/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/buildtools/bin:"${PATH}"
mkdir /tmp/gettext-build
pushd /tmp/gettext-build
CFLAGS= LDFLAGS= /home/ray/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/src/gettext-0.18.3.1/configure --prefix=/home/ray/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/buildtools --host=x86_64-build_w64-mingw32 --disable-java --disable-native-java --disable-csharp --enable-static --enable-threads=win32 --without-emacs --disable-openmp



/home/ray/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/src/gettext-0.18.3.1/gettext-runtime/gnulib-lib/lstat.c:67:1: error: conflicting types for ‘rpl_lstat’
 rpl_lstat (const char *file, struct stat *sbuf)
 ^
In file included from /usr/include/time.h:145:0,
                 from ./time.h:39,
                 from /usr/include/sys/stat.h:9,
                 from ./sys/stat.h:32,
                 from /home/ray/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/src/gettext-0.18.3.1/gettext-runtime/gnulib-lib/lstat.c:35:
./sys/stat.h:782:1: note: previous declaration of ‘rpl_lstat’ was here
 _GL_FUNCDECL_RPL (lstat, int, (const char *name, struct stat *buf)
 ^
/home/ray/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/src/gettext-0.18.3.1/gettext-runtime/gnulib-lib/lstat.c: In function ‘rpl_lstat’:
/home/ray/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/src/gettext-0.18.3.1/gettext-runtime/gnulib-lib/lstat.c:70:3: warning: passing argument 2 of ‘orig_lstat’ from incompatible pointer type [enabled by default]
   int lstat_result = orig_lstat (file, sbuf);
   ^
/home/ray/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/src/gettext-0.18.3.1/gettext-runtime/gnulib-lib/lstat.c:39:1: note: expected ‘struct stat *’ but argument is of type ‘struct _stati64 *’
 orig_lstat (const char *filename, struct stat *buf)
 ^
In file included from ./sys/stat.h:32:0,
                 from /home/ray/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/src/gettext-0.18.3.1/gettext-runtime/gnulib-lib/lstat.c:35:
/home/ray/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/src/gettext-0.18.3.1/gettext-runtime/gnulib-lib/lstat.c:81:44: error: dereferencing pointer to incomplete type
   if (file[len - 1] != '/' || S_ISDIR (sbuf->st_mode))
                                            ^
/home/ray/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/src/gettext-0.18.3.1/gettext-runtime/gnulib-lib/lstat.c:89:21: error: dereferencing pointer to incomplete type
   if (!S_ISLNK (sbuf->st_mode))
                     ^
Makefile:1436: recipe for target 'lstat.o' failed


# With ctng:
pushd /home/ray/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-gettext-build-x86_64-build_w64-mingw32/gettext-runtime/libasprintf
/usr/bin/bash ./libtool  --tag=CC   --mode=compile x86_64-build_w64-mingw32-gcc -O0 -ggdb  -D__USE_MINGW_ANSI_STDIO=1 -DIN_LIBASPRINTF -DHAVE_CONFIG_H -I. -I/home/ray/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/src/gettext-0.18.3.1/gettext-runtime/libasprintf      -c -o lib-asprintf.lo lib-asprintf.c

# With Pacman:
pushd /home/ray/MINGW-packages/mingw-w64-gettext/src/build-x86_64/gettext-runtime/libasprintf
libtool: compile:  x86_64-w64-mingw32-gcc -DIN_LIBASPRINTF -DHAVE_CONFIG_H -I. -I../../../gettext-0.18.3.1/gettext-runtime/libasprintf -D_FORTIFY_SOURCE=2 -march=x86-64 -mtune=generic -O2 -pipe -I/mingw64/include -fexceptions --param=ssp-buffer-size=4 -c ../../../gettext-0.18.3.1/gettext-runtime/libasprintf/lib-asprintf.c  -DDLL_EXPORT -DPIC -o .libs/lib-asprintf.o

# It's -D__USE_MINGW_ANSI_STDIO=1 that is killing us here! :-(

# With that 'fixed' we run into link errors:
[ALL  ]    /usr/bin/bash ../libtool  --tag=CXX   --mode=link x86_64-build_w64-mingw32-g++  -g -O2  -no-undefined  -L/home/ray/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/buildtools/lib -liconv -R/home/ray/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/buildtools/lib ../intl/libintl.la -L/home/ray/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/buildtools/lib -liconv -R/home/ray/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/buildtools/lib      -release 0.18.3 -Wl,--export-all-symbols    -L/home/ray/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/buildtools/lib -liconv -R/home/ray/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/buildtools/lib -L/home/ray/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/buildtools/lib -liconv -R/home/ray/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/buildtools/lib   -o libgettextlib.la -rpath /home/ray/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/buildtools/lib copy-acl.lo set-acl.lo allocator.lo areadlink.lo argmatch.lo gl_array_list.lo backupfile.lo addext.lo basename.lo binary-io.lo c-ctype.lo c-strcasecmp.lo c-strncasecmp.lo c-strcasestr.lo c-strstr.lo careadlinkat.lo classpath.lo clean-temp.lo cloexec.lo closeout.lo concat-filename.lo copy-file.lo csharpcomp.lo csharpexec.lo error-progname.lo execute.lo exitfail.lo fatal-signal.lo fd-hook.lo fd-ostream.lo fd-safer-flag.lo dup-safer-flag.lo file-ostream.lo findprog.lo fstrcmp.lo full-write.lo fwriteerror.lo gcd.lo ../woe32dll/gettextlib-exports.lo hash.lo html-ostream.lo  ../woe32dll/c++html-styled-ostream.lo javacomp.lo javaexec.lo javaversion.lo gl_linkedhash_list.lo gl_list.lo localcharset.lo localename.lo glthread/lock.lo malloca.lo mbchar.lo mbiter.lo mbslen.lo mbsstr.lo mbswidth.lo mbuiter.lo ostream.lo pipe-filter-ii.lo pipe-filter-aux.lo pipe2.lo pipe2-safer.lo progname.lo propername.lo acl-errno-valid.lo file-has-acl.lo qcopy-acl.lo qset-acl.lo quotearg.lo safe-read.lo safe-write.lo sh-quote.lo sig-handler.lo spawn-pipe.lo striconv.lo striconveh.lo striconveha.lo strnlen1.lo styled-ostream.lo tempname.lo term-ostream.lo  ../woe32dll/c++term-styled-ostream.lo glthread/threadlib.lo glthread/tls.lo tmpdir.lo trim.lo uniconv/u8-conv-from-enc.lo unilbrk/lbrktables.lo unilbrk/u8-possible-linebreaks.lo unilbrk/u8-width-linebreaks.lo unilbrk/ulc-common.lo unilbrk/ulc-width-linebreaks.lo uniname/uniname.lo unistd.lo dup-safer.lo fd-safer.lo pipe-safer.lo unistr/u16-mbtouc.lo unistr/u16-mbtouc-aux.lo unistr/u8-check.lo unistr/u8-mblen.lo unistr/u8-mbtouc.lo unistr/u8-mbtouc-aux.lo unistr/u8-mbtouc-unsafe.lo unistr/u8-mbtouc-unsafe-aux.lo unistr/u8-mbtoucr.lo unistr/u8-prev.lo unistr/u8-uctomb.lo unistr/u8-uctomb-aux.lo uniwidth/width.lo wait-process.lo wctype-h.lo xmalloc.lo xstrdup.lo xconcat-filename.lo xerror.lo gl_xlist.lo xmalloca.lo xreadlink.lo xsetenv.lo xsize.lo xstriconv.lo xstriconveh.lo xvasprintf.lo xasprintf.lo asnprintf.lo canonicalize-lgpl.lo close.lo dup2.lo error.lo fcntl.lo fnmatch.lo fopen.lo fstat.lo getdelim.lo getdtablesize.lo getline.lo gettimeofday.lo malloc.lo mbrtowc.lo mbsinit.lo mbsrtowcs.lo mbsrtowcs-state.lo mkdtemp.lo msvc-inval.lo msvc-nothrow.lo obstack.lo open.lo printf-args.lo printf-parse.lo raise.lo rawmemchr.lo read.lo readlink.lo realloc.lo rmdir.lo secure_getenv.lo setenv.lo setlocale.lo sigaction.lo sigprocmask.lo snprintf.lo spawn_faction_addclose.lo spawn_faction_adddup2.lo spawn_faction_addopen.lo spawn_faction_destroy.lo spawn_faction_init.lo spawnattr_destroy.lo spawnattr_init.lo spawnattr_setflags.lo spawnattr_setsigmask.lo spawni.lo spawnp.lo stat.lo stdio-write.lo stpcpy.lo stpncpy.lo strchrnul.lo strerror.lo strerror-override.lo strstr.lo tparm.lo tputs.lo unsetenv.lo vasnprintf.lo vsnprintf.lo waitpid.lo wcwidth.lo write.lo libcroco_rpl.la libglib_rpl.la libxml_rpl.la 
[ALL  ]    libtool: link: x86_64-build_w64-mingw32-g++ -shared -nostdlib c:/msys64/home/ray/ctng-firefox-builds/mingw64-235295c4/bin/../lib/gcc/x86_64-w64-mingw32/4.8.2/../../../../x86_64-w64-mingw32/lib/../lib/dllcrt2.o c:/msys64/home/ray/ctng-firefox-builds/mingw64-235295c4/bin/../lib/gcc/x86_64-w64-mingw32/4.8.2/../../../../x86_64-w64-mingw32/lib/../lib/crtbegin.o  .libs/copy-acl.o .libs/set-acl.o .libs/allocator.o .libs/areadlink.o .libs/argmatch.o .libs/gl_array_list.o .libs/backupfile.o .libs/addext.o .libs/basename.o .libs/binary-io.o .libs/c-ctype.o .libs/c-strcasecmp.o .libs/c-strncasecmp.o .libs/c-strcasestr.o .libs/c-strstr.o .libs/careadlinkat.o .libs/classpath.o .libs/clean-temp.o .libs/cloexec.o .libs/closeout.o .libs/concat-filename.o .libs/copy-file.o .libs/csharpcomp.o .libs/csharpexec.o .libs/error-progname.o .libs/execute.o .libs/exitfail.o .libs/fatal-signal.o .libs/fd-hook.o .libs/fd-ostream.o .libs/fd-safer-flag.o .libs/dup-safer-flag.o .libs/file-ostream.o .libs/findprog.o .libs/fstrcmp.o .libs/full-write.o .libs/fwriteerror.o .libs/gcd.o ../woe32dll/.libs/gettextlib-exports.o .libs/hash.o .libs/html-ostream.o ../woe32dll/.libs/c++html-styled-ostream.o .libs/javacomp.o .libs/javaexec.o .libs/javaversion.o .libs/gl_linkedhash_list.o .libs/gl_list.o .libs/localcharset.o .libs/localename.o glthread/.libs/lock.o .libs/malloca.o .libs/mbchar.o .libs/mbiter.o .libs/mbslen.o .libs/mbsstr.o .libs/mbswidth.o .libs/mbuiter.o .libs/ostream.o .libs/pipe-filter-ii.o .libs/pipe-filter-aux.o .libs/pipe2.o .libs/pipe2-safer.o .libs/progname.o .libs/propername.o .libs/acl-errno-valid.o .libs/file-has-acl.o .libs/qcopy-acl.o .libs/qset-acl.o .libs/quotearg.o .libs/safe-read.o .libs/safe-write.o .libs/sh-quote.o .libs/sig-handler.o .libs/spawn-pipe.o .libs/striconv.o .libs/striconveh.o .libs/striconveha.o .libs/strnlen1.o .libs/styled-ostream.o .libs/tempname.o .libs/term-ostream.o ../woe32dll/.libs/c++term-styled-ostream.o glthread/.libs/threadlib.o glthread/.libs/tls.o .libs/tmpdir.o .libs/trim.o uniconv/.libs/u8-conv-from-enc.o unilbrk/.libs/lbrktables.o unilbrk/.libs/u8-possible-linebreaks.o unilbrk/.libs/u8-width-linebreaks.o unilbrk/.libs/ulc-common.o unilbrk/.libs/ulc-width-linebreaks.o uniname/.libs/uniname.o .libs/unistd.o .libs/dup-safer.o .libs/fd-safer.o .libs/pipe-safer.o unistr/.libs/u16-mbtouc.o unistr/.libs/u16-mbtouc-aux.o unistr/.libs/u8-check.o unistr/.libs/u8-mblen.o unistr/.libs/u8-mbtouc.o unistr/.libs/u8-mbtouc-aux.o unistr/.libs/u8-mbtouc-unsafe.o unistr/.libs/u8-mbtouc-unsafe-aux.o unistr/.libs/u8-mbtoucr.o unistr/.libs/u8-prev.o unistr/.libs/u8-uctomb.o unistr/.libs/u8-uctomb-aux.o uniwidth/.libs/width.o .libs/wait-process.o .libs/wctype-h.o .libs/xmalloc.o .libs/xstrdup.o .libs/xconcat-filename.o .libs/xerror.o .libs/gl_xlist.o .libs/xmalloca.o .libs/xreadlink.o .libs/xsetenv.o .libs/xsize.o .libs/xstriconv.o .libs/xstriconveh.o .libs/xvasprintf.o .libs/xasprintf.o .libs/asnprintf.o .libs/canonicalize-lgpl.o .libs/close.o .libs/dup2.o .libs/error.o .libs/fcntl.o .libs/fnmatch.o .libs/fopen.o .libs/fstat.o .libs/getdelim.o .libs/getdtablesize.o .libs/getline.o .libs/gettimeofday.o .libs/malloc.o .libs/mbrtowc.o .libs/mbsinit.o .libs/mbsrtowcs.o .libs/mbsrtowcs-state.o .libs/mkdtemp.o .libs/msvc-inval.o .libs/msvc-nothrow.o .libs/obstack.o .libs/open.o .libs/printf-args.o .libs/printf-parse.o .libs/raise.o .libs/rawmemchr.o .libs/read.o .libs/readlink.o .libs/realloc.o .libs/rmdir.o .libs/secure_getenv.o .libs/setenv.o .libs/setlocale.o .libs/sigaction.o .libs/sigprocmask.o .libs/snprintf.o .libs/spawn_faction_addclose.o .libs/spawn_faction_adddup2.o .libs/spawn_faction_addopen.o .libs/spawn_faction_destroy.o .libs/spawn_faction_init.o .libs/spawnattr_destroy.o .libs/spawnattr_init.o .libs/spawnattr_setflags.o .libs/spawnattr_setsigmask.o .libs/spawni.o .libs/spawnp.o .libs/stat.o .libs/stdio-write.o .libs/stpcpy.o .libs/stpncpy.o .libs/strchrnul.o .libs/strerror.o .libs/strerror-override.o .libs/strstr.o .libs/tparm.o .libs/tputs.o .libs/unsetenv.o .libs/vasnprintf.o .libs/vsnprintf.o .libs/waitpid.o .libs/wcwidth.o .libs/write.o  -Wl,--whole-archive ./.libs/libcroco_rpl.a ./.libs/libglib_rpl.a ./.libs/libxml_rpl.a -Wl,--no-whole-archive  -L/home/ray/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/buildtools/lib ../intl/.libs/libintl.dll.a -Lc:/msys64/home/ray/ctng-firefox-builds/mingw64-235295c4/bin/../lib/gcc/x86_64-w64-mingw32/4.8.2 -Lc:/msys64/home/ray/ctng-firefox-builds/mingw64-235295c4/bin/../lib/gcc -Lc:/msys64/home/ray/ctng-firefox-builds/mingw64-235295c4/bin/../lib/gcc/x86_64-w64-mingw32/4.8.2/../../../../x86_64-w64-mingw32/lib/../lib -Lc:/msys64/home/ray/ctng-firefox-builds/mingw64-235295c4/bin/../lib/gcc/x86_64-w64-mingw32/4.8.2/../../../../lib -Lc:/msys64/home/ray/ctng-firefox-builds/mingw64-235295c4/bin/../lib/gcc/x86_64-w64-mingw32/4.8.2/../../../../x86_64-w64-mingw32/lib -Lc:/msys64/home/ray/ctng-firefox-builds/mingw64-235295c4/bin/../lib/gcc/x86_64-w64-mingw32/4.8.2/../../.. -lstdc++ -lmingw32 -lgcc_s -lgcc -lmoldname -lmingwex -lmsvcrt -ladvapi32 -lshell32 -luser32 -lkernel32 /home/ray/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/buildtools/lib/libiconv.dll.a -lmingw32 -lgcc_s -lgcc -lmoldname -lmingwex -lmsvcrt c:/msys64/home/ray/ctng-firefox-builds/mingw64-235295c4/bin/../lib/gcc/x86_64-w64-mingw32/4.8.2/../../../../x86_64-w64-mingw32/lib/../lib/crtend.o  -O2 -Wl,--export-all-symbols   -o .libs/libgettextlib-0-18-3.dll -Wl,--enable-auto-image-base -Xlinker --out-implib -Xlinker .libs/libgettextlib.dll.a
[ALL  ]    ../woe32dll/.libs/c++html-styled-ostream.o: In function `html_styled_ostream(float, long double,...)(...)':
[ALL  ]    C:msys64homerayctng-firefox-buildsctng-build-x-r-HEAD-x86_64-235295c4.buildarmv6hl-unknown-linux-gnueabibuildbuild-gettext-build-x86_64-build_w64-mingw32gettext-toolsgnulib-lib/html-styled-ostream.oo.c:70: undefined reference to `html_ostream_free(any_ostream_representation*)'
[ALL  ]    ../woe32dll/.libs/c++html-styled-ostream.o: In function `html_styled_ostream_create':
[ALL  ]    C:msys64homerayctng-firefox-buildsctng-build-x-r-HEAD-x86_64-235295c4.buildarmv6hl-unknown-linux-gnueabibuildbuild-gettext-build-x86_64-build_w64-mingw32gettext-toolsgnulib-lib/html-styled-ostream.oo.c:143: undefined reference to `ostream_write_mem(any_ostream_representation*, void const*, unsigned long long)'
..
[ALL  ]    C:msys64homerayctng-firefox-buildsctng-build-x-r-HEAD-x86_64-235295c4.buildarmv6hl-unknown-linux-gnueabibuildbuild-gettext-build-x86_64-build_w64-mingw32gettext-toolsgnulib-lib/term-styled-ostream.oo.c:107: undefined reference to `term_ostream_free(any_ostream_representation*)'
[ALL  ]    ../woe32dll/.libs/c++term-styled-ostream.o: In function `term_styled_ostream__write_mem':
[ALL  ]    C:msys64homerayctng-firefox-buildsctng-build-x-r-HEAD-x86_64-235295c4.buildarmv6hl-unknown-linux-gnueabibuildbuild-gettext-build-x86_64-build_w64-mingw32gettext-toolsgnulib-lib/term-styled-ostream.oo.c:89: undefined reference to `term_ostream_set_color(any_ostream_representation*, int)'


# Stupid gettext bug and broken patch

mkdir /tmp/gettext-bug
pushd /tmp/gettext-bug
AUTOMAKE_VER=1.14.3
if [ ! -f bin/autoconf ]; then
# curl -SLO http://ftp.gnu.org/gnu/autoconf/autoconf-${AUTOCONF_VER}.tar.bz2
 wget -c http://ftp.gnu.org/gnu/autoconf/autoconf-${AUTOCONF_VER}.tar.gz
 tar -xf autoconf-${AUTOCONF_VER}.tar.gz
 cd autoconf-${AUTOCONF_VER}
 wget -O config.guess 'http://git.savannah.gnu.org/gitweb/?p=config.git;a=blob_plain;f=config.guess;hb=HEAD'
 wget -O config.sub 'http://git.savannah.gnu.org/gitweb/?p=config.git;a=blob_plain;f=config.sub;hb=HEAD'
 ./configure --prefix=$PWD/.. && make && make install
 cd ..
fi
export PATH=$PWD/bin:"$PATH"
tar -xf ~/src/gettext-0.18.3.1.tar.gz
mv gettext-0.18.3.1 a
pushd a
patch -p1 < ~/ctng-firefox-builds/crosstool-ng/patches/gettext/0.18.3.1/110-Fix-linker-error-redefinition-of-vasprintf.patch
popd
cp -rf a b
pushd b
patch -p1 < ~/ctng-firefox-builds/crosstool-ng/patches/gettext/0.18.3.1/120-Fix-Woe32-link-errors-when-compiling-with-O0.patch
# Fix the mess made of color.o handling in that patch
pushd b/gettext-tools && /tmp/gettext-bug/b/build-aux/missing automake-1.13 --gnits src/Makefile





# .. with sunrpc test also:

ROOT=/tmp/eglibc-test
CT_BUILDTOOLS_PREFIX_DIR=/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/buildtools
rm -rf $ROOT
mkdir -p $ROOT
pushd $ROOT
# The last GCC under GPLv2 AFAIK.
#wget -c http://ftp.gnu.org/gnu/gcc/gcc-4.2.4/gcc-4.2.4.tar.bz2
#tar -xf gcc-4.2.4.tar.bz2
tar -xf ~/src/eglibc-2_18.tar.bz2
pushd eglibc-2_18
patch -p1 < ~/ctng-firefox-builds/crosstool-ng/patches/eglibc/2_18/100-make-4.patch
patch -p1 < ~/ctng-firefox-builds/crosstool-ng/patches/eglibc/2_18/110-Add-libiberty-pex-for-sunrpc-build.patch
popd
cp -rf eglibc-2_18 eglibc-2_18.orig
#cp -rf gcc-4.2.4/libiberty/pex-common.c eglibc-2_18/sunrpc/
#cp -rf gcc-4.2.4/libiberty/pex-common.h eglibc-2_18/sunrpc/
#cp -rf gcc-4.2.4/libiberty/pex-unix.c   eglibc-2_18/sunrpc/
#cp -rf gcc-4.2.4/libiberty/pex-win32.c  eglibc-2_18/sunrpc/
popd
mkdir -p $ROOT/armv6hl-unknown-linux-gnueabi/build/eglibc
pushd $ROOT/armv6hl-unknown-linux-gnueabi/build/eglibc
echo "libc_cv_forced_unwind=yes" >>config.cache
echo "libc_cv_c_cleanup=yes" >>config.cache
export PATH=/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/buildtools/bin:"$PATH"
BUILD_CC=x86_64-build_w64-mingw32-gcc CFLAGS="-U_FORTIFY_SOURCE  -mlittle-endian -march=armv6   -mtune=arm1176jzf-s -mfpu=vfp -mhard-float -O2" \
      CC=armv6hl-unknown-linux-gnueabi-gcc AR=armv6hl-unknown-linux-gnueabi-ar RANLIB=armv6hl-unknown-linux-gnueabi-ranlib \
      /tmp/eglibc-test/eglibc-2_18/configure --prefix=/usr --build=x86_64-build_w64-mingw32 --host=armv6hl-unknown-linux-gnueabi -without-cvs \
      --disable-profile --without-gd --with-headers=/home/ray/ctng-firefox-builds/x-r-none-4_8_2-x86_64-235295c4/armv6hl-unknown-linux-gnueabi/sysroot/usr/include --libdir=/usr/lib/. --enable-obsolete-rpc --enable-kernel=3.10.19 \
      --with-__thread --with-tls --enable-shared --with-fp --enable-add-ons=nptl,ports \
      --cache-file="$(pwd)/config.cache" CPPFLAGS="-I${CT_BUILDTOOLS_PREFIX_DIR}/include/" LDFLAGS="-L${CT_BUILDTOOLS_PREFIX_DIR}/lib/"

make ${JOBSFLAGS}                                    \
     install_root="/home/ray/ctng-firefox-builds/x-r-none-4_8_2-x86_64-235295c4/armv6hl-unknown-linux-gnueabi/sysroot"           \
     install-bootstrap-headers=yes                   \
     "${extra_make_args[@]}"                         \
     BUILD_CPPFLAGS="-I${CT_BUILDTOOLS_PREFIX_DIR}/include/"  \
     BUILD_LDFLAGS="-L${CT_BUILDTOOLS_PREFIX_DIR}/lib -lintl" \
     sunrpc/install-headers

.. that gets us as far as #include <sys/wait.h> in C:\msys64\tmp\eglibc-test\eglibc-2_18\sunrpc\rpc_main.c

.. commenting that out gets to:

In file included from rpc_parse.c:39:0:
rpc/types.h:73:1: error: unknown type name '__u_char'
 typedef __u_char u_char;
 
for __u_char __u_short __u_int __u_long __quad_t __u_quad_t __fsid_t __daddr_t __caddr_t
that block in types.h is not needed, nor is 
#include <netinet/in.h>

.. and eventually to:

x86_64-build_w64-mingw32-gcc /tmp/eglibc-test/armv6hl-unknown-linux-gnueabi/build/eglibc/sunrpc/cross-rpc_main.o /tmp/eglibc-test/armv6hl-unknown-linux-gnueabi/build/eglibc/sunrpc/cross-rpc_hout.o /tmp/eglibc-test/armv6hl-unknown-linux-gnueabi/build/eglibc/sunrpc/cross-rpc_cout.o /tmp/eglibc-test/armv6hl-unknown-linux-gnueabi/build/eglibc/sunrpc/cross-rpc_parse.o /tmp/eglibc-test/armv6hl-unknown-linux-gnueabi/build/eglibc/sunrpc/cross-rpc_scan.o /tmp/eglibc-test/armv6hl-unknown-linux-gnueabi/build/eglibc/sunrpc/cross-rpc_util.o /tmp/eglibc-test/armv6hl-unknown-linux-gnueabi/build/eglibc/sunrpc/cross-rpc_svcout.o /tmp/eglibc-test/armv6hl-unknown-linux-gnueabi/build/eglibc/sunrpc/cross-rpc_clntout.o /tmp/eglibc-test/armv6hl-unknown-linux-gnueabi/build/eglibc/sunrpc/cross-rpc_tblout.o /tmp/eglibc-test/armv6hl-unknown-linux-gnueabi/build/eglibc/sunrpc/cross-rpc_sample.o -L/c/ctng-build-x-r-HEAD-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/buildtools/lib -lintl -o /tmp/eglibc-test/armv6hl-unknown-linux-gnueabi/build/eglibc/sunrpc/cross-rpcgen
C:/msys64/tmp/eglibc-test/armv6hl-unknown-linux-gnueabi/build/eglibc/sunrpc/cross-rpc_main.o:rpc_main.c:(.text+0x781): undefined reference to `pipe'
C:/msys64/tmp/eglibc-test/armv6hl-unknown-linux-gnueabi/build/eglibc/sunrpc/cross-rpc_main.o:rpc_main.c:(.text+0x7a0): undefined reference to `fork'
C:/msys64/tmp/eglibc-test/armv6hl-unknown-linux-gnueabi/build/eglibc/sunrpc/cross-rpc_main.o:rpc_main.c:(.text+0x952): undefined reference to `waitpid'
C:/msys64/tmp/eglibc-test/armv6hl-unknown-linux-gnueabi/build/eglibc/sunrpc/cross-rpc_main.o:rpc_main.c:(.text+0x971): undefined reference to `WIFSIGNALED'
C:/msys64/tmp/eglibc-test/armv6hl-unknown-linux-gnueabi/build/eglibc/sunrpc/cross-rpc_main.o:rpc_main.c:(.text+0x97f): undefined reference to `WEXITSTATUS'
C:/msys64/tmp/eglibc-test/armv6hl-unknown-linux-gnueabi/build/eglibc/sunrpc/cross-rpc_main.o:rpc_main.c:(.text+0x991): undefined reference to `WIFSIGNALED'
C:/msys64/tmp/eglibc-test/armv6hl-unknown-linux-gnueabi/build/eglibc/sunrpc/cross-rpc_main.o:rpc_main.c:(.text+0x99f): undefined reference to `WTERMSIG'
C:/msys64/tmp/eglibc-test/armv6hl-unknown-linux-gnueabi/build/eglibc/sunrpc/cross-rpc_main.o:rpc_main.c:(.text+0x9d6): undefined reference to `WEXITSTATUS'
C:/msys64/tmp/eglibc-test/armv6hl-unknown-linux-gnueabi/build/eglibc/sunrpc/cross-rpc_main.o:rpc_main.c:(.text+0x1be1): undefined reference to `rindex'
C:/msys64/tmp/eglibc-test/armv6hl-unknown-linux-gnueabi/build/eglibc/sunrpc/cross-rpc_main.o:rpc_main.c:(.text+0x1c3b): undefined reference to `stpncpy'
C:/msys64/tmp/eglibc-test/armv6hl-unknown-linux-gnueabi/build/eglibc/sunrpc/cross-rpc_main.o:rpc_main.c:(.text+0x2a22): undefined reference to `stpcpy'

.. so rpc_main.c calls C-preprocessor:
/*
* Open input file with given define for C-preprocessor
*/

export PATH=/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/buildtools/bin:"$PATH"
pushd /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/src/eglibc-2_18/sunrpc
SUNRPC_CFLAGS="-O0 -g"
x86_64-build_w64-mingw32-gcc $SUNRPC_CFLAGS  -I/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/buildtools/include/ -D_GNU_SOURCE -DIS_IN_build -include /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-startfiles/config.h rpc_main.c 	-o /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-startfiles/sunrpc/cross-rpc_main.o -MMD -MP -MF /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-startfiles/sunrpc/cross-rpc_main.o.dt -MT /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-startfiles/sunrpc/cross-rpc_main.o -c
x86_64-build_w64-mingw32-gcc $SUNRPC_CFLAGS  -I/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/buildtools/include/ -D_GNU_SOURCE -DIS_IN_build -include /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-startfiles/config.h rpc_hout.c 	-o /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-startfiles/sunrpc/cross-rpc_hout.o -MMD -MP -MF /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-startfiles/sunrpc/cross-rpc_hout.o.dt -MT /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-startfiles/sunrpc/cross-rpc_hout.o -c
x86_64-build_w64-mingw32-gcc $SUNRPC_CFLAGS  -I/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/buildtools/include/ -D_GNU_SOURCE -DIS_IN_build -include /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-startfiles/config.h rpc_cout.c 	-o /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-startfiles/sunrpc/cross-rpc_cout.o -MMD -MP -MF /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-startfiles/sunrpc/cross-rpc_cout.o.dt -MT /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-startfiles/sunrpc/cross-rpc_cout.o -c
x86_64-build_w64-mingw32-gcc $SUNRPC_CFLAGS  -I/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/buildtools/include/ -D_GNU_SOURCE -DIS_IN_build -include /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-startfiles/config.h rpc_parse.c 	-o /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-startfiles/sunrpc/cross-rpc_parse.o -MMD -MP -MF /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-startfiles/sunrpc/cross-rpc_parse.o.dt -MT /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-startfiles/sunrpc/cross-rpc_parse.o -c
x86_64-build_w64-mingw32-gcc $SUNRPC_CFLAGS  -I/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/buildtools/include/ -D_GNU_SOURCE -DIS_IN_build -include /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-startfiles/config.h rpc_scan.c 	-o /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-startfiles/sunrpc/cross-rpc_scan.o -MMD -MP -MF /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-startfiles/sunrpc/cross-rpc_scan.o.dt -MT /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-startfiles/sunrpc/cross-rpc_scan.o -c

x86_64-build_w64-mingw32-gcc $SUNRPC_CFLAGS  -I/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/buildtools/include/ -D_GNU_SOURCE -DIS_IN_build -include /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-startfiles/config.h rpc_util.c 	-o /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-startfiles/sunrpc/cross-rpc_util.o -MMD -MP -MF /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-startfiles/sunrpc/cross-rpc_util.o.dt -MT /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-startfiles/sunrpc/cross-rpc_util.o -c
x86_64-build_w64-mingw32-gcc $SUNRPC_CFLAGS  -I/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/buildtools/include/ -D_GNU_SOURCE -DIS_IN_build -include /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-startfiles/config.h rpc_svcout.c 	-o /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-startfiles/sunrpc/cross-rpc_svcout.o -MMD -MP -MF /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-startfiles/sunrpc/cross-rpc_svcout.o.dt -MT /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-startfiles/sunrpc/cross-rpc_svcout.o -c
x86_64-build_w64-mingw32-gcc $SUNRPC_CFLAGS  -I/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/buildtools/include/ -D_GNU_SOURCE -DIS_IN_build -include /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-startfiles/config.h rpc_clntout.c 	-o /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-startfiles/sunrpc/cross-rpc_clntout.o -MMD -MP -MF /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-startfiles/sunrpc/cross-rpc_clntout.o.dt -MT /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-startfiles/sunrpc/cross-rpc_clntout.o -c
x86_64-build_w64-mingw32-gcc $SUNRPC_CFLAGS  -I/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/buildtools/include/ -D_GNU_SOURCE -DIS_IN_build -include /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-startfiles/config.h rpc_tblout.c 	-o /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-startfiles/sunrpc/cross-rpc_tblout.o -MMD -MP -MF /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-startfiles/sunrpc/cross-rpc_tblout.o.dt -MT /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-startfiles/sunrpc/cross-rpc_tblout.o -c
x86_64-build_w64-mingw32-gcc $SUNRPC_CFLAGS  -I/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/buildtools/include/ -D_GNU_SOURCE -DIS_IN_build -include /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-startfiles/config.h rpc_sample.c 	-o /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-startfiles/sunrpc/cross-rpc_sample.o -MMD -MP -MF /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-startfiles/sunrpc/cross-rpc_sample.o.dt -MT /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-startfiles/sunrpc/cross-rpc_sample.o -c
x86_64-build_w64-mingw32-gcc /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-startfiles/sunrpc/cross-rpc_main.o /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-startfiles/sunrpc/cross-rpc_hout.o /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-startfiles/sunrpc/cross-rpc_cout.o /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-startfiles/sunrpc/cross-rpc_parse.o /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-startfiles/sunrpc/cross-rpc_scan.o /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-startfiles/sunrpc/cross-rpc_util.o /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-startfiles/sunrpc/cross-rpc_svcout.o /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-startfiles/sunrpc/cross-rpc_clntout.o /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-startfiles/sunrpc/cross-rpc_tblout.o /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-startfiles/sunrpc/cross-rpc_sample.o -L/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/buildtools/lib  -Wl,-Bstatic -lintl -Wl,-Bdynamic -o /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-startfiles/sunrpc/cross-rpcgen




# Next up:
[ALL  ]    /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-cc-gcc-core-pass-2/./gcc/xgcc -B/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-cc-gcc-core-pass-2/./gcc/ -B/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/buildtools/armv6hl-unknown-linux-gnueabi/bin/ -B/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/buildtools/armv6hl-unknown-linux-gnueabi/lib/ -isystem /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/buildtools/armv6hl-unknown-linux-gnueabi/include -isystem /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/buildtools/armv6hl-unknown-linux-gnueabi/sys-include    -g -Os -O2  -DIN_GCC -DCROSS_DIRECTORY_STRUCTURE  -W -Wall -Wno-narrowing -Wwrite-strings -Wcast-qual -Wstrict-prototypes -Wmissing-prototypes -Wold-style-definition  -isystem ./include   -fPIC -fno-inline -g -DIN_LIBGCC2 -fbuilding-libgcc -fno-stack-protector   -fPIC -fno-inline -I. -I. -I../.././gcc -I/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/src/gcc-4.8.2/libgcc -I/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/src/gcc-4.8.2/libgcc/. -I/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/src/gcc-4.8.2/libgcc/../gcc -I/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/src/gcc-4.8.2/libgcc/../include  -DHAVE_CC_TLS  -o _clear_cache.o -MT _clear_cache.o -MD -MP -MF _clear_cache.dep -DL_clear_cache -xassembler-with-cpp -c /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/src/gcc-4.8.2/libgcc/config/arm/lib1funcs.S -include _clear_cache.vis
[ALL  ]    /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-cc-gcc-core-pass-2/./gcc/xgcc -B/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-cc-gcc-core-pass-2/./gcc/ -B/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/buildtools/armv6hl-unknown-linux-gnueabi/bin/ -B/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/buildtools/armv6hl-unknown-linux-gnueabi/lib/ -isystem /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/buildtools/armv6hl-unknown-linux-gnueabi/include -isystem /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/buildtools/armv6hl-unknown-linux-gnueabi/sys-include    -g -Os -O2  -DIN_GCC -DCROSS_DIRECTORY_STRUCTURE  -W -Wall -Wno-narrowing -Wwrite-strings -Wcast-qual -Wstrict-prototypes -Wmissing-prototypes -Wold-style-definition  -isystem ./include   -fPIC -fno-inline -g -DIN_LIBGCC2 -fbuilding-libgcc -fno-stack-protector   -fPIC -fno-inline -I. -I. -I../.././gcc -I/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/src/gcc-4.8.2/libgcc -I/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/src/gcc-4.8.2/libgcc/. -I/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/src/gcc-4.8.2/libgcc/../gcc -I/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/src/gcc-4.8.2/libgcc/../include  -DHAVE_CC_TLS  -o _muldi3.o -MT _muldi3.o -MD -MP -MF _muldi3.dep -DL_muldi3 -c /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/src/gcc-4.8.2/libgcc/libgcc2.c -fvisibility=hidden -DHIDE_EXPORTS
[ALL  ]    In file included from C:/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/src/gcc-4.8.2/libgcc/libgcc2.c:27:0:
[ERROR]    C:/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/src/gcc-4.8.2/libgcc/../gcc/tsystem.h:87:19: fatal error: stdio.h: No such file or directory
[ALL  ]     #include <stdio.h>
[ALL  ]                       ^
[ALL  ]    compilation terminated.
[ALL  ]    Makefile:465: recipe for target '_muldi3.o' failed
[ERROR]    make[2]: *** [_muldi3.o] Error 1
[ALL  ]    make[2]: Leaving directory '/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-cc-gcc-core-pass-2/armv6hl-unknown-linux-gnueabi/libgcc'



# Still the problems with gettext persist!
# '-O0 -ggdb' fails:
[ALL  ]    ../woe32dll/.libs/c++term-styled-ostream.o: In function `term_styled_ostream__write_mem':
[ALL  ]    C:ctng-build-x-r-none-4_8_2-x86_64-235295c4-d.buildarmv6hl-unknown-linux-gnueabibuildbuild-gettext-build-x86_64-build_w64-mingw32gettext-toolsgnulib-lib/term-styled-ostream.oo.c:89: undefined reference to `term_ostream_set_color(any_ostream_representation*, int)'
[ALL  ]    C:ctng-build-x-r-none-4_8_2-x86_64-235295c4-d.buildarmv6hl-unknown-linux-gnueabibuildbuild-gettext-build-x86_64-build_w64-mingw32gettext-toolsgnulib-lib/term-styled-ostream.oo.c:90: undefined reference to `term_ostream_set_bgcolor(any_ostream_representation*, int)'
[ALL  ]    C:ctng-build-x-r-none-4_8_2-x86_64-235295c4-d.buildarmv6hl-unknown-linux-gnueabibuildbuild-gettext-build-x86_64-build_w64-mingw32gettext-toolsgnulib-lib/term-styled-ostream.oo.c:91: undefined reference to `term_ostream_set_weight(any_ostream_representation*, term_weight_t)'
[ALL  ]    C:ctng-build-x-r-none-4_8_2-x86_64-235295c4-d.buildarmv6hl-unknown-linux-gnueabibuildbuild-gettext-build-x86_64-build_w64-mingw32gettext-toolsgnulib-lib/term-styled-ostream.oo.c:92: undefined reference to `term_ostream_set_posture(any_ostream_representation*, term_posture_t)'
[ALL  ]    C:ctng-build-x-r-none-4_8_2-x86_64-235295c4-d.buildarmv6hl-unknown-linux-gnueabibuildbuild-gettext-build-x86_64-build_w64-mingw32gettext-toolsgnulib-lib/term-styled-ostream.oo.c:93: undefined reference to `term_ostream_set_underline(any_ostream_representation*, term_underline_t)'
[ALL  ]    ../woe32dll/.libs/c++term-styled-ostream.o: In function `term_styled_ostream_create':
[ALL  ]    C:ctng-build-x-r-none-4_8_2-x86_64-235295c4-d.buildarmv6hl-unknown-linux-gnueabibuildbuild-gettext-build-x86_64-build_w64-mingw32gettext-toolsgnulib-lib/term-styled-ostream.oo.c:615: undefined reference to `term_ostream_free(any_ostream_representation*)'
[ALL  ]    ../woe32dll/.libs/c++term-styled-ostream.o: In function `term_styled_ostream__flush':
[ALL  ]    C:ctng-build-x-r-none-4_8_2-x86_64-235295c4-d.buildarmv6hl-unknown-linux-gnueabibuildbuild-gettext-build-x86_64-build_w64-mingw32gettext-toolsgnulib-lib/term-styled-ostream.oo.c:101: undefined reference to `term_ostream_flush(any_ostream_representation*)'
[ALL  ]    ../woe32dll/.libs/c++term-styled-ostream.o: In function `term_styled_ostream__write_mem':
[ALL  ]    C:ctng-build-x-r-none-4_8_2-x86_64-235295c4-d.buildarmv6hl-unknown-linux-gnueabibuildbuild-gettext-build-x86_64-build_w64-mingw32gettext-toolsgnulib-lib/term-styled-ostream.oo.c:95: undefined reference to `term_ostream_write_mem(any_ostream_representation*, void const*, unsigned long long)'
[ERROR]    collect2.exe: error: ld returned 1 exit status
[ALL  ]    Makefile:2507: recipe for target 'libgettextlib.la' failed
[ERROR]    make[5]: *** [libgettextlib.la] Error 1
[ALL  ]    make[5]: Leaving directory '/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-gettext-build-x86_64-build_w64-mingw32/gettext-tools/gnulib-lib'
[ALL  ]    Makefile:2262: recipe for target 'all' failed
[ERROR]    make[4]: *** [all] Error 2
[ALL  ]    make[4]: Leaving directory '/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-gettext-build-x86_64-build_w64-mingw32/gettext-tools/gnulib-lib'
[ALL  ]    Makefile:1711: recipe for target 'all-recursive' failed
[ERROR]    make[3]: *** [all-recursive] Error 1
[ALL  ]    make[3]: Leaving directory '/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-gettext-build-x86_64-build_w64-mingw32/gettext-tools'
[ALL  ]    Makefile:1576: recipe for target 'all' failed
[ERROR]    make[2]: *** [all] Error 2
[ALL  ]    make[2]: Leaving directory '/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-gettext-build-x86_64-build_w64-mingw32/gettext-tools'
[ALL  ]    Makefile:364: recipe for target 'all-recursive' failed
[ERROR]    make[1]: *** [all-recursive] Error 1
[ALL  ]    make[1]: Leaving directory '/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-gettext-build-x86_64-build_w64-mingw32'
# Ignoring, -O2 is now forced instead.

export PATH=/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/bin:"$PATH"
C:/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-cc-gcc-core-pass-2/gcc/cc1.exe -quiet -v -v -iprefix c:/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi../lib/gccarmv6hl-unknown-linux-gnueabi/4.8.2/ -isystem C:/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-cc-gcc-core-pass-2/gcc/include -isystem C:/ctng-build-x-r-none-4_8_2-x86_64-235295ueabi/build/build-cc-gcc-core-pass-2/gcc/include-fixed -isystem C:/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/armv6hl-unknown-linux-gnueabi/include C:/msys64/home/ray/Dropbox/a.c -quietrm1176jzf-s -mfloat-abi=hard -mfpu=vfp -mtls-dialect=gnu -auxbase a -version -o C:/msys64/tmp/ccwAYgUx.s

C:/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-cc-gcc-core-pass-2/gcc/cc1.exe -quiet -v -v -v -iprefix c:/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-cc-gcc-core-pass-2/gcc/../lib/gcc/armv6hl-unknown-linux-gnueabi/4.8.2/ -isystem C:/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-cc-gcc-core-pass-2/gcc/include -isystem C:/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-cc-gcc-core-pass-2/gcc/include-fixed -isystem C:/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/armv6hl-unknown-linux-gnueabi/include C:/msys64/home/ray/Dropbox/a.c -quiet -dumpbase a.c -march=armv6 -mtune=arm1176jzf-s -mfloat-abi=hard -mfpu=vfp -mtls-dialect=gnu -auxbase a -version -o C:/msys64/tmp/cccsYj8S.s


# What's -iprefix about? it's got a value of c:/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-cc-gcc-core-pass-2/gcc/../lib/gcc/armv6hl-unknown-linux-gnueabi/4.8.2/


The exact line that fails is:
/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-cc-gcc-core-pass-2/./gcc/xgcc -B/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-cc-gcc-core-pass-2/./gcc/ -B/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/buildtools/armv6hl-unknown-linux-gnueabi/bin/ -B/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/buildtools/armv6hl-unknown-linux-gnueabi/lib/ -isystem /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/buildtools/armv6hl-unknown-linux-gnueabi/include -isystem /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/buildtools/armv6hl-unknown-linux-gnueabi/sys-include    -g -Os -O2  -DIN_GCC -DCROSS_DIRECTORY_STRUCTURE  -W -Wall -Wno-narrowing -Wwrite-strings -Wcast-qual -Wstrict-prototypes -Wmissing-prototypes -Wold-style-definition  -isystem ./include   -fPIC -fno-inline -g -DIN_LIBGCC2 -fbuilding-libgcc -fno-stack-protector   -fPIC -fno-inline -I. -I. -I../.././gcc -I/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/src/gcc-4.8.2/libgcc -I/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/src/gcc-4.8.2/libgcc/. -I/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/src/gcc-4.8.2/libgcc/../gcc -I/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/src/gcc-4.8.2/libgcc/../include  -DHAVE_CC_TLS  -o _muldi3.o -MT _muldi3.o -MD -MP -MF _muldi3.dep -DL_muldi3 -c /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/src/gcc-4.8.2/libgcc/libgcc2.c -fvisibility=hidden -DHIDE_EXPORTS
adding -v to it gives CC1 execution as of:
C:/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-cc-gcc-core-pass-2/gcc/cc1.exe -quiet -v -I . -I . -I ../.././gcc -I C:/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/src/gcc-4.8.2/libgcc -I C:/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/src/gcc-4.8.2/libgcc -I C:/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/src/gcc-4.8.2/libgcc/../gcc -I C:/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/src/gcc-4.8.2/libgcc/../include -iprefix c:\ctng-build-x-r-none-4_8_2-x86_64-235295c4\.build\armv6hl-unknown-linux-gnueabi\build\build-cc-gcc-core-pass-2\gcc\../lib/gccarmv6hl-unknown-linux-gnueabi/4.8.2/ -isystem C:/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-cc-gcc-core-pass-2/gcc/include -isystem C:/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-cc-gcc-core-pass-2/gcc/include-fixed -MD _muldi3.d -MF _muldi3.dep -MP -MT _muldi3.o -D IN_GCC -D CROSS_DIRECTORY_STRUCTURE -D IN_LIBGCC2 -D HAVE_CC_TLS -D L_muldi3 -D HIDE_EXPORTS -isystem C:/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/buildtools/armv6hl-unknown-linux-gnueabi/include -isystem C:/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/buildtools/armv6hl-unknown-linux-gnueabi/sys-include -isystem ./include C:/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/src/gcc-4.8.2/libgcc/libgcc2.c -quiet -dumpbase libgcc2.c -march=armv6 -mtune=arm1176jzf-s -mfloat-abi=hard -mfpu=vfp -mtls-dialect=gnu -auxbase-strip _muldi3.o -g -g -Os -O2 -Wextra -Wall -Wno-narrowing -Wwrite-strings -Wcast-qual -Wstrict-prototypes -Wmissing-prototypes -Wold-style-definition -version -fbuilding-libgcc -fno-stack-protector -fPIC -fno-inline -fvisibility=hidden -o C:\msys64\tmp\cczvo1dq.s

which has -iprefix c:\ctng-build-x-r-none-4_8_2-x86_64-235295c4\.build\armv6hl-unknown-linux-gnueabi\build\build-cc-gcc-core-pass-2\gcc\../lib/gccarmv6hl-unknown-linux-gnueabi/4.8.2/
.. c:/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-cc-gcc-core-pass-2/gcc/../lib/gccarmv6hl-unknown-linux-gnueabi/4.8.2/

which does not exist ..

.. I think the problem is:

C:/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/src/gcc-4.8.2/gcc/cppdefault.c

#ifdef CROSS_INCLUDE_DIR
    /* One place the target system's headers might be.  */
    { CROSS_INCLUDE_DIR, "GCC", 0, 0, 0, 0 },
#endif
#ifdef TOOL_INCLUDE_DIR
    /* Another place the target system's headers might be.  */
    { TOOL_INCLUDE_DIR, "BINUTILS", 0, 1, 0, 0 },
#endif
#ifdef NATIVE_SYSTEM_HEADER_DIR
    /* /usr/include comes dead last.  */
    { NATIVE_SYSTEM_HEADER_DIR, NATIVE_SYSTEM_HEADER_COMPONENT, 0, 0, 1, 2 },
    { NATIVE_SYSTEM_HEADER_DIR, NATIVE_SYSTEM_HEADER_COMPONENT, 0, 0, 1, 0 },
#endif



.. NATIVE_SYSTEM_HEADER_DIR is probably C:/msys64/include ..
.. even though we are building cross compilers == badness.

C:\ctng-build-x-r-none-4_8_2-x86_64-235295c4-d\.build\armv6hl-unknown-linux-gnueabi\build\build-cc-gcc-core-pass-2

Seems that:
C:\ctng-build-x-r-none-4_8_2-x86_64-235295c4-d\.build\armv6hl-unknown-linux-gnueabi\build\build-cc-gcc-core-pass-2\gcc\Makefile

Has:

# Default native SYSTEM_HEADER_DIR, to be overridden by targets.
NATIVE_SYSTEM_HEADER_DIR = /usr/include
# Default cross SYSTEM_HEADER_DIR, to be overridden by targets.
CROSS_SYSTEM_HEADER_DIR = $(TARGET_SYSTEM_ROOT)$${sysroot_headers_suffix}$(NATIVE_SYSTEM_HEADER_DIR)

# autoconf sets SYSTEM_HEADER_DIR to one of the above.
# Purge it of unnecessary internal relative paths
# to directories that might not exist yet.
# The sed idiom for this is to repeat the search-and-replace until it doesn't match, using :a ... ta.
# Use single quotes here to avoid nested double- and backquotes, this
# macro is also used in a double-quoted context.
SYSTEM_HEADER_DIR = `echo $(CROSS_SYSTEM_HEADER_DIR) | sed -e :a -e 's,[^/]*/\.\.\/,,' -e ta`

C:\ctng-build-x-r-none-4_8_2-x86_64-235295c4-d\.build\armv6hl-unknown-linux-gnueabi\build\build-cc-gcc-core-pass-2\gcc\Makefile
  -DCROSS_INCLUDE_DIR=\"$(CROSS_SYSTEM_HEADER_DIR)\" \

.. so the gist of it is:
The follwing has 1 == add_sysroot (i.e. prefix this with sysroot) and 2 == multilib
    { NATIVE_SYSTEM_HEADER_DIR, NATIVE_SYSTEM_HEADER_COMPONENT, 0, 0, 1, 2 },
.. which works OK natively on Linux since /usr/include is prepended to /blah/blah/sysroot to make a good sysroot.

.. However this falls down due to MSYS path translation (as usual)

.. Now, CROSS_SYSTEM_HEADER_DIR would be the thing that you would think would avoid all this nonsense ...

CROSS_SYSTEM_HEADER_DIR = $(TARGET_SYSTEM_ROOT)$${sysroot_headers_suffix}$(NATIVE_SYSTEM_HEADER_DIR)
TARGET_SYSTEM_ROOT='/home/ray/ctng-firefox-builds/x-r-none-4_8_2-x86_64-235295c4-d/armv6hl-unknown-linux-gnueabi/sysroot'

There could be some issue with $${sysroot_headers_suffix} as the only place that references it in GCC source-code is:
for ml in `cat ${itoolsdatadir}/fixinc_list`; do
  sysroot_headers_suffix=`echo ${ml} | sed -e 's/;.*$//'`

.. so if fixincludes is broken (likely) then sysroot_headers_suffix may be too.

Seems like they are being passed in OK: -DCROSS_INCLUDE_DIR="/home/ray/ctng-firefox-builds/x-r-none-4_8_2-x86_64-235295c4-d/armv6hl-unknown-linux-gnueabi/sysroot${sysroot_headers_suffix}/usr/include"
cpp_include_defaults[6] = FIXED_INCLUDE_DIR, so
cpp_include_defaults[7] = CROSS_INCLUDE_DIR .. but it isn't, it's "BINUTILS".

.. back to cppdefault.c

#if defined (CROSS_DIRECTORY_STRUCTURE) && !defined (TARGET_SYSTEM_ROOT)
# undef LOCAL_INCLUDE_DIR
# undef NATIVE_SYSTEM_HEADER_DIR
#else
# undef CROSS_INCLUDE_DIR
#endif

# Which means we *MUST* be taking the # undef CROSS_INCLUDE_DIR path .. hmm
# -DCROSS_DIRECTORY_STRUCTURE is passed in and ..
# TARGET_SYSTEM_ROOT = /home/ray/ctng-firefox-builds/x-r-none-4_8_2-x86_64-235295c4-d/armv6hl-unknown-linux-gnueabi/sysroot
# .. so it does enter the undef CROSS_INCLUDE_DIR block ..

See also email from Ian Lance Taylor: http://gcc.gnu.org/ml/gcc-patches/2011-10/msg02380.html

x86_64-build_w64-mingw32-g++ -c  -DGCC_INCLUDE_DIR="/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/lib/gcc/armv6hl-unknown-linux-gnueabi/4.8.2/include" -DFIXED_INCLUDE_DIR="/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/lib/gcc/armv6hl-unknown-linux-gnueabi/4.8.2/include-fixed" -DGPLUSPLUS_INCLUDE_DIR="/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/lib/gcc/armv6hl-unknown-linux-gnueabi/4.8.2/../../../../armv6hl-unknown-linux-gnueabi/include/c++/4.8.2" -DGPLUSPLUS_INCLUDE_DIR_ADD_SYSROOT=0 -DGPLUSPLUS_TOOL_INCLUDE_DIR="/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/lib/gcc/armv6hl-unknown-linux-gnueabi/4.8.2/../../../../armv6hl-unknown-linux-gnueabi/include/c++/4.8.2/armv6hl-unknown-linux-gnueabi" -DGPLUSPLUS_BACKWARD_INCLUDE_DIR="/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/lib/gcc/armv6hl-unknown-linux-gnueabi/4.8.2/../../../../armv6hl-unknown-linux-gnueabi/include/c++/4.8.2/backward" -DLOCAL_INCLUDE_DIR="/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/lib/gcc/armv6hl-unknown-linux-gnueabi/4.8.2/../../../..`echo /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/buildtools | sed -e 's|^/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/buildtools||' -e 's|/[^/]*|/..|g'`/include" -DCROSS_INCLUDE_DIR="/home/ray/ctng-firefox-builds/x-r-none-4_8_2-x86_64-235295c4-d/armv6hl-unknown-linux-gnueabi/sysroot${sysroot_headers_suffix}/usr/include" -DTOOL_INCLUDE_DIR="/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/lib/gcc/armv6hl-unknown-linux-gnueabi/4.8.2/../../../../armv6hl-unknown-linux-gnueabi/include" -DNATIVE_SYSTEM_HEADER_DIR="/usr/include" -DPREFIX="/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/" -DSTANDARD_EXEC_PREFIX="/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/lib/gcc/" -DTARGET_SYSTEM_ROOT="/home/ray/ctng-firefox-builds/x-r-none-4_8_2-x86_64-235295c4-d/armv6hl-unknown-linux-gnueabi/sysroot" -DBASEVER=""4.8.2"" -O0 -ggdb -pipe  -D__USE_MINGW_ANSI_STDIO=1 -DIN_GCC -DCROSS_DIRECTORY_STRUCTURE  -fno-exceptions -fno-rtti -fasynchronous-unwind-tables -W -Wall -Wno-narrowing -Wwrite-strings -Wcast-qual -Wmissing-format-attribute -pedantic -Wno-long-long -Wno-variadic-macros -Wno-overlength-strings   -DHAVE_CONFIG_H -I. -I. -I/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/src/gcc-4.8.2/gcc -I/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/src/gcc-4.8.2/gcc/. -I/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/src/gcc-4.8.2/gcc/../include -I/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/src/gcc-4.8.2/gcc/../libcpp/include -I/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/include -I/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/include -I/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/include  -I/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/src/gcc-4.8.2/gcc/../libdecnumber -I/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/src/gcc-4.8.2/gcc/../libdecnumber/dpd -I../libdecnumber -I/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/src/gcc-4.8.2/gcc/../libbacktrace -DCLOOG_INT_GMP -I/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/include -I/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/include  /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/src/gcc-4.8.2/gcc/cppbuiltin.c -o cppbuiltin.o

x86_64-build_w64-mingw32-g++ -c  -DGCC_INCLUDE_DIR="/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/lib/gcc/armv6hl-unknown-linux-gnueabi/4.8.2/include" -DFIXED_INCLUDE_DIR="/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/lib/gcc/armv6hl-unknown-linux-gnueabi/4.8.2/include-fixed" -DGPLUSPLUS_INCLUDE_DIR="/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/lib/gcc/armv6hl-unknown-linux-gnueabi/4.8.2/../../../../armv6hl-unknown-linux-gnueabi/include/c++/4.8.2" -DGPLUSPLUS_INCLUDE_DIR_ADD_SYSROOT=0 -DGPLUSPLUS_TOOL_INCLUDE_DIR="/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/lib/gcc/armv6hl-unknown-linux-gnueabi/4.8.2/../../../../armv6hl-unknown-linux-gnueabi/include/c++/4.8.2/armv6hl-unknown-linux-gnueabi" -DGPLUSPLUS_BACKWARD_INCLUDE_DIR="/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/lib/gcc/armv6hl-unknown-linux-gnueabi/4.8.2/../../../../armv6hl-unknown-linux-gnueabi/include/c++/4.8.2/backward" -DLOCAL_INCLUDE_DIR="/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/lib/gcc/armv6hl-unknown-linux-gnueabi/4.8.2/../../../..`echo /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/buildtools | sed -e 's|^/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/buildtools||' -e 's|/[^/]*|/..|g'`/include" -DCROSS_INCLUDE_DIR="/home/ray/ctng-firefox-builds/x-r-none-4_8_2-x86_64-235295c4-d/armv6hl-unknown-linux-gnueabi/sysroot${sysroot_headers_suffix}/usr/include" -DTOOL_INCLUDE_DIR="/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/lib/gcc/armv6hl-unknown-linux-gnueabi/4.8.2/../../../../armv6hl-unknown-linux-gnueabi/include" -DNATIVE_SYSTEM_HEADER_DIR="/usr/include" -DPREFIX="/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/" -DSTANDARD_EXEC_PREFIX="/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/lib/gcc/" -DTARGET_SYSTEM_ROOT="/home/ray/ctng-firefox-builds/x-r-none-4_8_2-x86_64-235295c4-d/armv6hl-unknown-linux-gnueabi/sysroot" -O0 -ggdb -pipe  -D__USE_MINGW_ANSI_STDIO=1 -DIN_GCC -DCROSS_DIRECTORY_STRUCTURE  -fno-exceptions -fno-rtti -fasynchronous-unwind-tables -W -Wall -Wno-narrowing -Wwrite-strings -Wcast-qual -Wmissing-format-attribute -pedantic -Wno-long-long -Wno-variadic-macros -Wno-overlength-strings   -DHAVE_CONFIG_H -I. -I. -I/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/src/gcc-4.8.2/gcc -I/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/src/gcc-4.8.2/gcc/. -I/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/src/gcc-4.8.2/gcc/../include -I/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/src/gcc-4.8.2/gcc/../libcpp/include -I/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/include -I/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/include -I/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/include  -I/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/src/gcc-4.8.2/gcc/../libdecnumber -I/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/src/gcc-4.8.2/gcc/../libdecnumber/dpd -I../libdecnumber -I/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/src/gcc-4.8.2/gcc/../libbacktrace -DCLOOG_INT_GMP -I/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/include -I/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/include  /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/src/gcc-4.8.2/gcc/cppdefault.c -o cppdefault.o

.. potential fixinclude problems anyway ..
[ALL  ]     Searching /home/ray/ctng-firefox-builds/x-r-none-4_8_2-x86_64-235295c4-d/armv6hl-unknown-linux-gnueabi/sysroot/usr/include/.
[ALL  ]    Fixing directory /home/ray/ctng-firefox-builds/x-r-none-4_8_2-x86_64-235295c4-d/armv6hl-unknown-linux-gnueabi/sysroot/usr/include into /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-cc-gcc-core-pass-2/gcc/include-fixed
[ALL  ]    FS error 2 (No such file or directory) reopening 'drm/drm.h' as stdin
[ALL  ]    FS error 2 (No such file or directory) reopening 'drm/exynos_drm.h' as stdin
[ALL  ]    FS error 2 (No such file or directory) reopening 'drm/i810_drm.h' as stdin
[ALL  ]    FS error 2 (No such file or directory) reopening 'drm/i915_drm.h' as stdin
[ALL  ]    FS error 2 (No such file or directory) reopening 'drm/mga_drm.h' as stdin
[ALL  ]    FS error 2 (No such file or directory) reopening 'drm/nouveau_drm.h' as stdin
[ALL  ]    FS error 2 (No such file or directory) reopening 'drm/r128_drm.h' as stdin
[ALL  ]    FS error 2 (No such file or directory) reopening 'drm/radeon_drm.h' as stdin
[ALL  ]    FS error 2 (No such file or directory) reopening 'drm/savage_drm.h' as stdin
[ALL  ]    FS error 2 (No such file or directory) reopening 'drm/sis_drm.h' as stdin
[ALL  ]    FS error 2 (No such file or directory) reopening 'drm/tegra_drm.h' as stdin
[ALL  ]    FS error 2 (No such file or directory) reopening 'drm/via_drm.h' as stdin
[ALL  ]    FS error 2 (No such file or directory) reopening 'linux/agpgart.h' as stdin


pushd /home/ray/ctng-firefox-builds/ctng-build-x-w-none-4_8_2-x86_64/.build/x86_64-unknown-mingw32/build/build-mingw-w64-crt
export PATH=/home/ray/ctng-firefox-builds/ctng-build-x-w-none-4_8_2-x86_64/.build/x86_64-unknown-mingw32/buildtools/bin:"$PATH"
x86_64-unknown-mingw32-gcc -DHAVE_CONFIG_H -I. -I/home/ray/ctng-firefox-builds/ctng-build-x-w-none-4_8_2-x86_64/.build/src/mingw-w64-v3.0.0/mingw-w64-crt  -m64 -I/home/ray/ctng-firefox-builds/ctng-build-x-w-none-4_8_2-x86_64/.build/src/mingw-w64-v3.0.0/mingw-w64-crt/include -D_CRTBLD -I/usr/include  -pipe -std=gnu99 -Wall -Wextra -Wformat -Wstrict-aliasing -Wshadow -Wpacked -Winline -Wimplicit-function-declaration -Wmissing-noreturn -Wmissing-prototypes -g -O2 -MT intrincs/lib64_libkernel32_a-__movsb.o -MD -MP -MF intrincs/.deps/lib64_libkernel32_a-__movsb.Tpo -c -o intrincs/lib64_libkernel32_a-__movsb.o `test -f 'intrincs/__movsb.c' || echo '/home/ray/ctng-firefox-builds/ctng-build-x-w-none-4_8_2-x86_64/.build/src/mingw-w64-v3.0.0/mingw-w64-crt/'`intrincs/__movsb.c

/home/ray/ctng-firefox-builds/ctng-build-x-w-none-4_8_2-x86_64/.build/src/mingw-w64-v3.0.0/mingw-w64-crt/configure --prefix=/mingw --build=x86_64-build_unknown-linux-gnu --host=x86_64-unknown-mingw32


# ... may want to build fixdeps.exe with debugging info.
PATH=$HOME/ctng-firefox-builds/mingw64-235295c4/bin:$PATH gcc -Wp,-MD,scripts/basic/.fixdep.d -Iscripts/basic -Wall -Wmissing-prototypes -Wstrict-prototypes -O0 -g -fomit-frame-pointer -o scripts/basic/fixdep /home/ray/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/src/linux-3.10.19/scripts/basic/fixdep.c  

pushd $HOME/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-kernel-headers/
$HOME/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-kernel-headers/scripts/basic/fixdep.exe scripts/basic/.fixdep.d scripts/basic/fixdep "gcc -Wp,-MD,scripts/basic/.fixdep.d -Iscripts/basic -Wall -Wmissing-prototypes -Wstrict-prototypes -O2 -fomit-frame-pointer -o scripts/basic/fixdep $HOME/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/src/linux-3.10.19/scripts/basic/fixdep.c  "
$HOME/ctng-firefox-builds/mingw64-235295c4/bin/gdb $HOME/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/build/build-kernel-headers/scripts/basic/fixdep.exe scripts/basic/.fixdep.d scripts/basic/fixdep "gcc -Wp,-MD,scripts/basic/.fixdep.d -Iscripts/basic -Wall -Wmissing-prototypes -Wstrict-prototypes -O2 -fomit-frame-pointer -o scripts/basic/fixdep $HOME/ctng-firefox-builds/ctng-build-x-r-HEAD-x86_64-235295c4/.build/src/linux-3.10.19/scripts/basic/fixdep.c  "


No idea why it fails to build on Windows now .. something to do with the final build ..
export PATH=/home/ray/ctng-firefox-builds/x-w-head-4_8_2-x86_64-235295c4-d/bin:/c/ctng-build-x-w-head-4_8_2-x86_64-235295c4-d/.build/x86_64-unknown-mingw32/buildtools/bin:/c/ctng-build-x-w-head-4_8_2-x86_64-235295c4-d/.build/tools/bin:/home/ray/ctng-firefox-builds/mingw64-235295c4/bin:"${PATH}"
pushd /c/ctng-build-x-w-head-4_8_2-x86_64-235295c4-d/.build/x86_64-unknown-mingw32/build/build-cc-gcc-final
/c/ctng-build-x-w-head-4_8_2-x86_64-235295c4-d/.build/src/gcc-4.8.2/configure --build=x86_64-build_w64-mingw32 --host=x86_64-build_w64-mingw32 --target=x86_64-unknown-mingw32 --prefix=/home/ray/ctng-firefox-builds/x-w-head-4_8_2-x86_64-235295c4-d --with-sysroot=/home/ray/ctng-firefox-builds/x-w-head-4_8_2-x86_64-235295c4-d/x86_64-unknown-mingw32/sysroot --enable-languages=c,c++,objc,obj-c++ --disable-shared --with-pkgversion=crosstool-NG hg+unknown-20131219.194205 --enable-__cxa_atexit --disable-libmudflap --disable-libgomp --disable-libssp --disable-libquadmath --disable-libquadmath-support --with-gmp=/c/ctng-build-x-w-head-4_8_2-x86_64-235295c4-d/.build/x86_64-unknown-mingw32/buildtools --with-mpfr=/c/ctng-build-x-w-head-4_8_2-x86_64-235295c4-d/.build/x86_64-unknown-mingw32/buildtools --with-mpc=/c/ctng-build-x-w-head-4_8_2-x86_64-235295c4-d/.build/x86_64-unknown-mingw32/buildtools --with-isl=/c/ctng-build-x-w-head-4_8_2-x86_64-235295c4-d/.build/x86_64-unknown-mingw32/buildtools --with-cloog=/c/ctng-build-x-w-head-4_8_2-x86_64-235295c4-d/.build/x86_64-unknown-mingw32/buildtools --with-libelf=/c/ctng-build-x-w-head-4_8_2-x86_64-235295c4-d/.build/x86_64-unknown-mingw32/buildtools --enable-threads=win32 --disable-win32-registry --enable-target-optspace --enable-plugin --disable-nls --disable-multilib --with-local-prefix=/home/ray/ctng-firefox-builds/x-w-head-4_8_2-x86_64-235295c4-d/x86_64-unknown-mingw32/sysroot --enable-c99 --enable-long-long


also, builds for raspi are using binutils 2.22 instead of 2.24 for some reason?

export PATH=/home/ray/ctng-firefox-builds/x-r-none-4_8_2-x86_64-235295c4-d/bin:/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/bin:/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/tools/bin:/home/ray/ctng-firefox-builds/mingw64-235295c4/bin:"$PATH"
pushd /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-cc-gcc-core-pass-2/armv6hl-unknown-linux-gnueabi/libgcc

Raspi on Windows fails to build libgcc
[ALL  ]    /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-cc-gcc-core-pass-2/./gcc/xgcc -B/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-cc-gcc-core-pass-2/./gcc/ -B/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/armv6hl-unknown-linux-gnueabi/bin/ -B/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/armv6hl-unknown-linux-gnueabi/lib/ -isystem /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/armv6hl-unknown-linux-gnueabi/include -isystem /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/armv6hl-unknown-linux-gnueabi/sys-include    -g -Os -O2 -DIN_GCC -DCROSS_DIRECTORY_STRUCTURE  -W -Wall -Wno-narrowing -Wwrite-strings -Wcast-qual -Wstrict-prototypes -Wmissing-prototypes -Wold-style-definition  -isystem ./include  -I. -I. -I../.././gcc -I../../../../../src/gcc-4.8.2/libgcc -I../../../../../src/gcc-4.8.2/libgcc/. -I../../../../../src/gcc-4.8.2/libgcc/../gcc -I../../../../../src/gcc-4.8.2/libgcc/../include   -g0 -finhibit-size-directive -fno-inline -fno-exceptions -fno-zero-initialized-in-bss -fno-toplevel-reorder -fno-tree-vectorize -fno-stack-protector  -I. -I. -I../.././gcc -I../../../../../src/gcc-4.8.2/libgcc -I../../../../../src/gcc-4.8.2/libgcc/. -I../../../../../src/gcc-4.8.2/libgcc/../gcc -I../../../../../src/gcc-4.8.2/libgcc/../include  -o crtbegin.o -MT crtbegin.o -MD -MP -MF crtbegin.dep  -c ../../../../../src/gcc-4.8.2/libgcc/crtstuff.c -DCRT_BEGIN
[ALL  ]    In file included from ../../../../../src/gcc-4.8.2/libgcc/crtstuff.c:54:0:
[ERROR]    ../.././gcc/auto-host.h:1928:17: error: two or more data types in declaration specifiers
[ALL  ]     #define caddr_t char *
[ALL  ]                     ^
[ALL  ]    In file included from ../../../../../src/gcc-4.8.2/libgcc/../gcc/tsystem.h:90:0,
[ALL  ]                     from ../../../../../src/gcc-4.8.2/libgcc/crtstuff.c:60:
[ERROR]    C:/msys64/home/ray/ctng-firefox-builds/x-r-none-4_8_2-x86_64-235295c4-d/armv6hl-unknown-linux-gnueabi/sysroot/usr/include/sys/types.h:116:26: error: expected identifier or '(' before ';' token
[ALL  ]     typedef __caddr_t caddr_t;
[ALL  ]                              ^
[ALL  ]    Makefile:962: recipe for target 'crtbegin.o' failed
[ERROR]    make[2]: *** [crtbegin.o] Error 1


/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-cc-gcc-core-pass-2/./gcc/xgcc -B/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-cc-gcc-core-pass-2/./gcc/ -B/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/armv6hl-unknown-linux-gnueabi/bin/ -B/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/armv6hl-unknown-linux-gnueabi/lib/ -isystem /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/armv6hl-unknown-linux-gnueabi/include -isystem /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/armv6hl-unknown-linux-gnueabi/sys-include    -g -Os -O2 -DIN_GCC -DCROSS_DIRECTORY_STRUCTURE  -W -Wall -Wno-narrowing -Wwrite-strings -Wcast-qual -Wstrict-prototypes -Wmissing-prototypes -Wold-style-definition  -isystem ./include  -I. -I. -I../.././gcc -I../../../../../src/gcc-4.8.2/libgcc -I../../../../../src/gcc-4.8.2/libgcc/. -I../../../../../src/gcc-4.8.2/libgcc/../gcc -I../../../../../src/gcc-4.8.2/libgcc/../include   -g0 -finhibit-size-directive -fno-inline -fno-exceptions -fno-zero-initialized-in-bss -fno-toplevel-reorder -fno-tree-vectorize -fno-stack-protector  -I. -I. -I../.././gcc -I../../../../../src/gcc-4.8.2/libgcc -I../../../../../src/gcc-4.8.2/libgcc/. -I../../../../../src/gcc-4.8.2/libgcc/../gcc -I../../../../../src/gcc-4.8.2/libgcc/../include  -o crtbegin.o -MT crtbegin.o -MD -MP -MF crtbegin.dep  -c ../../../../../src/gcc-4.8.2/libgcc/crtstuff.c -DCRT_BEGIN
In file included from ../../../../../src/gcc-4.8.2/libgcc/crtstuff.c:54:0:
../.././gcc/auto-host.h:1928:17: error: two or more data types in declaration specifiers
 #define caddr_t char *
                 ^
In file included from ../../../../../src/gcc-4.8.2/libgcc/../gcc/tsystem.h:90:0,
                 from ../../../../../src/gcc-4.8.2/libgcc/crtstuff.c:60:
C:/msys64/home/ray/ctng-firefox-builds/x-r-none-4_8_2-x86_64-235295c4-d/armv6hl-unknown-linux-gnueabi/sysroot/usr/include/sys/types.h:116:26: error: expected identifier or '(' before ';' token
 typedef __caddr_t caddr_t;
                          ^
Makefile:962: recipe for target 'crtbegin.o' failed
make: *** [crtbegin.o] Error 1

..on Linux:
/home/ray/ctng-firefox-builds/ctng-build-x-r-none-4_8_2-x86_64-d/.build/armv6hl-unknown-linux-gnueabi/build/build-cc-gcc-core-pass-2/./gcc/xgcc -B/home/ray/ctng-firefox-builds/ctng-build-x-r-none-4_8_2-x86_64-d/.build/armv6hl-unknown-linux-gnueabi/build/build-cc-gcc-core-pass-2/./gcc/ -B/home/ray/ctng-firefox-builds/ctng-build-x-r-none-4_8_2-x86_64-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/armv6hl-unknown-linux-gnueabi/bin/ -B/home/ray/ctng-firefox-builds/ctng-build-x-r-none-4_8_2-x86_64-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/armv6hl-unknown-linux-gnueabi/lib/ -isystem /home/ray/ctng-firefox-builds/ctng-build-x-r-none-4_8_2-x86_64-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/armv6hl-unknown-linux-gnueabi/include -isystem /home/ray/ctng-firefox-builds/ctng-build-x-r-none-4_8_2-x86_64-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/armv6hl-unknown-linux-gnueabi/sys-include    -g -Os -O2 -DIN_GCC -DCROSS_DIRECTORY_STRUCTURE  -W -Wall -Wno-narrowing -Wwrite-strings -Wcast-qual -Wstrict-prototypes -Wmissing-prototypes -Wold-style-definition  -isystem ./include  -I. -I. -I../.././gcc -I../../../../../src/gcc-4.8.2/libgcc -I../../../../../src/gcc-4.8.2/libgcc/. -I../../../../../src/gcc-4.8.2/libgcc/../gcc -I../../../../../src/gcc-4.8.2/libgcc/../include   -g0 -finhibit-size-directive -fno-inline -fno-exceptions -fno-zero-initialized-in-bss -fno-toplevel-reorder -fno-tree-vectorize -fno-stack-protector  -I. -I. -I../.././gcc -I../../../../../src/gcc-4.8.2/libgcc -I../../../../../src/gcc-4.8.2/libgcc/. -I../../../../../src/gcc-4.8.2/libgcc/../gcc -I../../../../../src/gcc-4.8.2/libgcc/../include  -o crtbegin.o -MT crtbegin.o -MD -MP -MF crtbegin.dep  -c ../../../../../src/gcc-4.8.2/libgcc/crtstuff.c -DCRT_BEGIN


comparing ~/Dropbox/crtstuff.windows.i and ~/Dropbox/crtstuff.linux.i, they are highly similar, but:
Windows:
typedef __id_t id_t;
# 115 "C:/msys64/home/ray/ctng-firefox-builds/x-r-none-4_8_2-x86_64-235295c4-d/armv6hl-unknown-linux-gnueabi/sysroot/usr/include/sys/types.h" 3 4
typedef __daddr_t daddr_t;
typedef __caddr_t char *;

Linux:
typedef __id_t id_t;
# 115 "/home/ray/ctng-firefox-builds/x-r-none-4_8_2-x86_64-d/armv6hl-unknown-linux-gnueabi/sysroot/usr/include/sys/types.h" 3 4
typedef __daddr_t daddr_t;
typedef __caddr_t caddr_t;


# Still some problem with xgcc doing CreateProcess?
[ALL  ]    /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-cc-gcc-core-pass-2/./gcc/xgcc -B/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-cc-gcc-core-pass-2/./gcc/ -B/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/armv6hl-unknown-linux-gnueabi/bin/ -B/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/armv6hl-unknown-linux-gnueabi/lib/ -isystem /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/armv6hl-unknown-linux-gnueabi/include -isystem /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/armv6hl-unknown-linux-gnueabi/sys-include    -O2  -DIN_GCC -DCROSS_DIRECTORY_STRUCTURE  -W -Wall -Wno-narrowing -Wwrite-strings -Wcast-qual -Wstrict-prototypes -Wmissing-prototypes -Wold-style-definition  -isystem ./include   -fPIC -fno-inline -g -DIN_LIBGCC2 -fbuilding-libgcc -fno-stack-protector  -shared -nodefaultlibs -Wl,--soname=libgcc_s.so.1 -Wl,--version-script=libgcc.map -o ./libgcc_s.so.1.tmp -g -Os -B./ _thumb1_case_sqi_s.o _thumb1_case_uqi_s.o _thumb1_case_shi_s.o _thumb1_case_uhi_s.o _thumb1_case_si_s.o _udivsi3_s.o _divsi3_s.o _umodsi3_s.o _modsi3_s.o _bb_init_func_s.o _call_via_rX_s.o _interwork_call_via_rX_s.o _lshrdi3_s.o _ashrdi3_s.o _ashldi3_s.o _arm_negdf2_s.o _arm_addsubdf3_s.o _arm_muldivdf3_s.o _arm_cmpdf2_s.o _arm_unorddf2_s.o _arm_fixdfsi_s.o _arm_fixunsdfsi_s.o _arm_truncdfsf2_s.o _arm_negsf2_s.o _arm_addsubsf3_s.o _arm_muldivsf3_s.o _arm_cmpsf2_s.o _arm_unordsf2_s.o _arm_fixsfsi_s.o _arm_fixunssfsi_s.o _arm_floatdidf_s.o _arm_floatdisf_s.o _arm_floatundidf_s.o _arm_floatundisf_s.o _clzsi2_s.o _clzdi2_s.o _ctzsi2_s.o _aeabi_lcmp_s.o _aeabi_ulcmp_s.o _aeabi_ldivmod_s.o _aeabi_uldivmod_s.o _dvmd_lnx_s.o _clear_cache_s.o _muldi3_s.o _negdi2_s.o _cmpdi2_s.o _ucmpdi2_s.o _trampoline_s.o __main_s.o _absvsi2_s.o _absvdi2_s.o _addvsi3_s.o _addvdi3_s.o _subvsi3_s.o _subvdi3_s.o _mulvsi3_s.o _mulvdi3_s.o _negvsi2_s.o _negvdi2_s.o _ctors_s.o _ffssi2_s.o _ffsdi2_s.o _clz_s.o _ctzdi2_s.o _popcount_tab_s.o _popcountsi2_s.o _popcountdi2_s.o _paritysi2_s.o _paritydi2_s.o _powisf2_s.o _powidf2_s.o _powixf2_s.o _powitf2_s.o _mulsc3_s.o _muldc3_s.o _mulxc3_s.o _multc3_s.o _divsc3_s.o _divdc3_s.o _divxc3_s.o _divtc3_s.o _bswapsi2_s.o _bswapdi2_s.o _clrsbsi2_s.o _clrsbdi2_s.o _fixunssfsi_s.o _fixunsdfsi_s.o _fixunsxfsi_s.o _fixsfdi_s.o _fixdfdi_s.o _fixxfdi_s.o _fixtfdi_s.o _fixunssfdi_s.o _fixunsdfdi_s.o _fixunsxfdi_s.o _fixunstfdi_s.o _floatdisf_s.o _floatdidf_s.o _floatdixf_s.o _floatditf_s.o _floatundisf_s.o _floatundidf_s.o _floatundixf_s.o _floatunditf_s.o _divdi3_s.o _moddi3_s.o _udivdi3_s.o _umoddi3_s.o _udiv_w_sdiv_s.o _udivmoddi4_s.o _addQQ_s.o _addHQ_s.o _addSQ_s.o _addDQ_s.o _addTQ_s.o _addHA_s.o _addSA_s.o _addDA_s.o _addTA_s.o _addUQQ_s.o _addUHQ_s.o _addUSQ_s.o _addUDQ_s.o _addUTQ_s.o _addUHA_s.o _addUSA_s.o _addUDA_s.o _addUTA_s.o _subQQ_s.o _subHQ_s.o _subSQ_s.o _subDQ_s.o _subTQ_s.o _subHA_s.o _subSA_s.o _subDA_s.o _subTA_s.o _subUQQ_s.o _subUHQ_s.o _subUSQ_s.o _subUDQ_s.o _subUTQ_s.o _subUHA_s.o _subUSA_s.o _subUDA_s.o _subUTA_s.o _negQQ_s.o _negHQ_s.o _negSQ_s.o _negDQ_s.o _negTQ_s.o _negHA_s.o _negSA_s.o _negDA_s.o _negTA_s.o _negUQQ_s.o _negUHQ_s.o _negUSQ_s.o _negUDQ_s.o _negUTQ_s.o _negUHA_s.o _negUSA_s.o _negUDA_s.o _negUTA_s.o _mulQQ_s.o _mulHQ_s.o _mulSQ_s.o _mulDQ_s.o _mulTQ_s.o _mulHA_s.o _mulSA_s.o _mulDA_s.o _mulTA_s.o _mulUQQ_s.o _mulUHQ_s.o _mulUSQ_s.o _mulUDQ_s.o _mulUTQ_s.o _mulUHA_s.o _mulUSA_s.o _mulUDA_s.o _mulUTA_s.o _mulhelperQQ_s.o _mulhelperHQ_s.o _mulhelperSQ_s.o _mulhelperDQ_s.o _mulhelperTQ_s.o _mulhelperHA_s.o _mulhelperSA_s.o _mulhelperDA_s.o _mulhelperTA_s.o _mulhelperUQQ_s.o _mulhelperUHQ_s.o _mulhelperUSQ_s.o _mulhelperUDQ_s.o _mulhelperUTQ_s.o _mulhelperUHA_s.o _mulhelperUSA_s.o _mulhelperUDA_s.o _mulhelperUTA_s.o _divhelperQQ_s.o _divhelperHQ_s.o _divhelperSQ_s.o _divhelperDQ_s.o _divhelperTQ_s.o _divhelperHA_s.o _divhelperSA_s.o _divhelperDA_s.o _divhelperTA_s.o _divhelperUQQ_s.o _divhelperUHQ_s.o _divhelperUSQ_s.o _divhelperUDQ_s.o _divhelperUTQ_s.o _divhelperUHA_s.o _divhelperUSA_s.o _divhelperUDA_s.o _divhelperUTA_s.o _ashlQQ_s.o _ashlHQ_s.o _ashlSQ_s.o _ashlDQ_s.o _ashlTQ_s.o _ashlHA_s.o _ashlSA_s.o _ashlDA_s.o _ashlTA_s.o _ashlUQQ_s.o _ashlUHQ_s.o _ashlUSQ_s.o _ashlUDQ_s.o _ashlUTQ_s.o _ashlUHA_s.o _ashlUSA_s.o _ashlUDA_s.o _ashlUTA_s.o _ashlhelperQQ_s.o _ashlhelperHQ_s.o _ashlhelperSQ_s.o _ashlhelperDQ_s.o _ashlhelperTQ_s.o _ashlhelperHA_s.o _ashlhelperSA_s.o _ashlhelperDA_s.o _ashlhelperTA_s.o _ashlhelperUQQ_s.o _ashlhelperUHQ_s.o _ashlhelperUSQ_s.o _ashlhelperUDQ_s.o _ashlhelperUTQ_s.o _ashlhelperUHA_s.o _ashlhelperUSA_s.o _ashlhelperUDA_s.o _ashlhelperUTA_s.o _cmpQQ_s.o _cmpHQ_s.o _cmpSQ_s.o _cmpDQ_s.o _cmpTQ_s.o _cmpHA_s.o _cmpSA_s.o _cmpDA_s.o _cmpTA_s.o _cmpUQQ_s.o _cmpUHQ_s.o _cmpUSQ_s.o _cmpUDQ_s.o _cmpUTQ_s.o _cmpUHA_s.o _cmpUSA_s.o _cmpUDA_s.o _cmpUTA_s.o _saturate1QQ_s.o _saturate1HQ_s.o _saturate1SQ_s.o _saturate1DQ_s.o _saturate1TQ_s.o _saturate1HA_s.o _saturate1SA_s.o _saturate1DA_s.o _saturate1TA_s.o _saturate1UQQ_s.o _saturate1UHQ_s.o _saturate1USQ_s.o _saturate1UDQ_s.o _saturate1UTQ_s.o _saturate1UHA_s.o _saturate1USA_s.o _saturate1UDA_s.o _saturate1UTA_s.o _saturate2QQ_s.o _saturate2HQ_s.o _saturate2SQ_s.o _saturate2DQ_s.o _saturate2TQ_s.o _saturate2HA_s.o _saturate2SA_s.o _saturate2DA_s.o _saturate2TA_s.o _saturate2UQQ_s.o _saturate2UHQ_s.o _saturate2USQ_s.o _saturate2UDQ_s.o _saturate2UTQ_s.o _saturate2UHA_s.o _saturate2USA_s.o _saturate2UDA_s.o _saturate2UTA_s.o _ssaddQQ_s.o _ssaddHQ_s.o _ssaddSQ_s.o _ssaddDQ_s.o _ssaddTQ_s.o _ssaddHA_s.o _ssaddSA_s.o _ssaddDA_s.o _ssaddTA_s.o _sssubQQ_s.o _sssubHQ_s.o _sssubSQ_s.o _sssubDQ_s.o _sssubTQ_s.o _sssubHA_s.o _sssubSA_s.o _sssubDA_s.o _sssubTA_s.o _ssnegQQ_s.o _ssnegHQ_s.o _ssnegSQ_s.o _ssnegDQ_s.o _ssnegTQ_s.o _ssnegHA_s.o _ssnegSA_s.o _ssnegDA_s.o _ssnegTA_s.o _ssmulQQ_s.o _ssmulHQ_s.o _ssmulSQ_s.o _ssmulDQ_s.o _ssmulTQ_s.o _ssmulHA_s.o _ssmulSA_s.o _ssmulDA_s.o _ssmulTA_s.o _ssdivQQ_s.o _ssdivHQ_s.o _ssdivSQ_s.o _ssdivDQ_s.o _ssdivTQ_s.o _ssdivHA_s.o _ssdivSA_s.o _ssdivDA_s.o _ssdivTA_s.o _divQQ_s.o _divHQ_s.o _divSQ_s.o _divDQ_s.o _divTQ_s.o _divHA_s.o _divSA_s.o _divDA_s.o _divTA_s.o _ssashlQQ_s.o _ssashlHQ_s.o _ssashlSQ_s.o _ssashlDQ_s.o _ssashlTQ_s.o _ssashlHA_s.o _ssashlSA_s.o _ssashlDA_s.o _ssashlTA_s.o _ashrQQ_s.o _ashrHQ_s.o _ashrSQ_s.o _ashrDQ_s.o _ashrTQ_s.o _ashrHA_s.o _ashrSA_s.o _ashrDA_s.o _ashrTA_s.o _usaddUQQ_s.o _usaddUHQ_s.o _usaddUSQ_s.o _usaddUDQ_s.o _usaddUTQ_s.o _usaddUHA_s.o _usaddUSA_s.o _usaddUDA_s.o _usaddUTA_s.o _ussubUQQ_s.o _ussubUHQ_s.o _ussubUSQ_s.o _ussubUDQ_s.o _ussubUTQ_s.o _ussubUHA_s.o _ussubUSA_s.o _ussubUDA_s.o _ussubUTA_s.o _usnegUQQ_s.o _usnegUHQ_s.o _usnegUSQ_s.o _usnegUDQ_s.o _usnegUTQ_s.o _usnegUHA_s.o _usnegUSA_s.o _usnegUDA_s.o _usnegUTA_s.o _usmulUQQ_s.o _usmulUHQ_s.o _usmulUSQ_s.o _usmulUDQ_s.o _usmulUTQ_s.o _usmulUHA_s.o _usmulUSA_s.o _usmulUDA_s.o _usmulUTA_s.o _usdivUQQ_s.o _usdivUHQ_s.o _usdivUSQ_s.o _usdivUDQ_s.o _usdivUTQ_s.o _usdivUHA_s.o _usdivUSA_s.o _usdivUDA_s.o _usdivUTA_s.o _udivUQQ_s.o _udivUHQ_s.o _udivUSQ_s.o _udivUDQ_s.o _udivUTQ_s.o _udivUHA_s.o _udivUSA_s.o _udivUDA_s.o _udivUTA_s.o _usashlUQQ_s.o _usashlUHQ_s.o _usashlUSQ_s.o _usashlUDQ_s.o _usashlUTQ_s.o _usashlUHA_s.o _usashlUSA_s.o _usashlUDA_s.o _usashlUTA_s.o _lshrUQQ_s.o _lshrUHQ_s.o _lshrUSQ_s.o _lshrUDQ_s.o _lshrUTQ_s.o _lshrUHA_s.o _lshrUSA_s.o _lshrUDA_s.o _lshrUTA_s.o _fractQQHQ_s.o _fractQQSQ_s.o _fractQQDQ_s.o _fractQQTQ_s.o _fractQQHA_s.o _fractQQSA_s.o _fractQQDA_s.o _fractQQTA_s.o _fractQQUQQ_s.o _fractQQUHQ_s.o _fractQQUSQ_s.o _fractQQUDQ_s.o _fractQQUTQ_s.o _fractQQUHA_s.o _fractQQUSA_s.o _fractQQUDA_s.o _fractQQUTA_s.o _fractQQQI_s.o _fractQQHI_s.o _fractQQSI_s.o _fractQQDI_s.o _fractQQTI_s.o _fractQQSF_s.o _fractQQDF_s.o _fractHQQQ_s.o _fractHQSQ_s.o _fractHQDQ_s.o _fractHQTQ_s.o _fractHQHA_s.o _fractHQSA_s.o _fractHQDA_s.o _fractHQTA_s.o _fractHQUQQ_s.o _fractHQUHQ_s.o _fractHQUSQ_s.o _fractHQUDQ_s.o _fractHQUTQ_s.o _fractHQUHA_s.o _fractHQUSA_s.o _fractHQUDA_s.o _fractHQUTA_s.o _fractHQQI_s.o _fractHQHI_s.o _fractHQSI_s.o _fractHQDI_s.o _fractHQTI_s.o _fractHQSF_s.o _fractHQDF_s.o _fractSQQQ_s.o _fractSQHQ_s.o _fractSQDQ_s.o _fractSQTQ_s.o _fractSQHA_s.o _fractSQSA_s.o _fractSQDA_s.o _fractSQTA_s.o _fractSQUQQ_s.o _fractSQUHQ_s.o _fractSQUSQ_s.o _fractSQUDQ_s.o _fractSQUTQ_s.o _fractSQUHA_s.o _fractSQUSA_s.o _fractSQUDA_s.o _fractSQUTA_s.o _fractSQQI_s.o _fractSQHI_s.o _fractSQSI_s.o _fractSQDI_s.o _fractSQTI_s.o _fractSQSF_s.o _fractSQDF_s.o _fractDQQQ_s.o _fractDQHQ_s.o _fractDQSQ_s.o _fractDQTQ_s.o _fractDQHA_s.o _fractDQSA_s.o _fractDQDA_s.o _fractDQTA_s.o _fractDQUQQ_s.o _fractDQUHQ_s.o _fractDQUSQ_s.o _fractDQUDQ_s.o _fractDQUTQ_s.o _fractDQUHA_s.o _fractDQUSA_s.o _fractDQUDA_s.o _fractDQUTA_s.o _fractDQQI_s.o _fractDQHI_s.o _fractDQSI_s.o _fractDQDI_s.o _fractDQTI_s.o _fractDQSF_s.o _fractDQDF_s.o _fractTQQQ_s.o _fractTQHQ_s.o _fractTQSQ_s.o _fractTQDQ_s.o _fractTQHA_s.o _fractTQSA_s.o _fractTQDA_s.o _fractTQTA_s.o _fractTQUQQ_s.o _fractTQUHQ_s.o _fractTQUSQ_s.o _fractTQUDQ_s.o _fractTQUTQ_s.o _fractTQUHA_s.o _fractTQUSA_s.o _fractTQUDA_s.o _fractTQUTA_s.o _fractTQQI_s.o _fractTQHI_s.o _fractTQSI_s.o _fractTQDI_s.o _fractTQTI_s.o _fractTQSF_s.o _fractTQDF_s.o _fractHAQQ_s.o _fractHAHQ_s.o _fractHASQ_s.o _fractHADQ_s.o _fractHATQ_s.o _fractHASA_s.o _fractHADA_s.o _fractHATA_s.o _fractHAUQQ_s.o _fractHAUHQ_s.o _fractHAUSQ_s.o _fractHAUDQ_s.o _fractHAUTQ_s.o _fractHAUHA_s.o _fractHAUSA_s.o _fractHAUDA_s.o _fractHAUTA_s.o _fractHAQI_s.o _fractHAHI_s.o _fractHASI_s.o _fractHADI_s.o _fractHATI_s.o _fractHASF_s.o _fractHADF_s.o _fractSAQQ_s.o _fractSAHQ_s.o _fractSASQ_s.o _fractSADQ_s.o _fractSATQ_s.o _fractSAHA_s.o _fractSADA_s.o _fractSATA_s.o _fractSAUQQ_s.o _fractSAUHQ_s.o _fractSAUSQ_s.o _fractSAUDQ_s.o _fractSAUTQ_s.o _fractSAUHA_s.o _fractSAUSA_s.o _fractSAUDA_s.o _fractSAUTA_s.o _fractSAQI_s.o _fractSAHI_s.o _fractSASI_s.o _fractSADI_s.o _fractSATI_s.o _fractSASF_s.o _fractSADF_s.o _fractDAQQ_s.o _fractDAHQ_s.o _fractDASQ_s.o _fractDADQ_s.o _fractDATQ_s.o _fractDAHA_s.o _fractDASA_s.o _fractDATA_s.o _fractDAUQQ_s.o _fractDAUHQ_s.o _fractDAUSQ_s.o _fractDAUDQ_s.o _fractDAUTQ_s.o _fractDAUHA_s.o _fractDAUSA_s.o _fractDAUDA_s.o _fractDAUTA_s.o _fractDAQI_s.o _fractDAHI_s.o _fractDASI_s.o _fractDADI_s.o _fractDATI_s.o _fractDASF_s.o _fractDADF_s.o _fractTAQQ_s.o _fractTAHQ_s.o _fractTASQ_s.o _fractTADQ_s.o _fractTATQ_s.o _fractTAHA_s.o _fractTASA_s.o _fractTADA_s.o _fractTAUQQ_s.o _fractTAUHQ_s.o _fractTAUSQ_s.o _fractTAUDQ_s.o _fractTAUTQ_s.o _fractTAUHA_s.o _fractTAUSA_s.o _fractTAUDA_s.o _fractTAUTA_s.o _fractTAQI_s.o _fractTAHI_s.o _fractTASI_s.o _fractTADI_s.o _fractTATI_s.o _fractTASF_s.o _fractTADF_s.o _fractUQQQQ_s.o _fractUQQHQ_s.o _fractUQQSQ_s.o _fractUQQDQ_s.o _fractUQQTQ_s.o _fractUQQHA_s.o _fractUQQSA_s.o _fractUQQDA_s.o _fractUQQTA_s.o _fractUQQUHQ_s.o _fractUQQUSQ_s.o _fractUQQUDQ_s.o _fractUQQUTQ_s.o _fractUQQUHA_s.o _fractUQQUSA_s.o _fractUQQUDA_s.o _fractUQQUTA_s.o _fractUQQQI_s.o _fractUQQHI_s.o _fractUQQSI_s.o _fractUQQDI_s.o _fractUQQTI_s.o _fractUQQSF_s.o _fractUQQDF_s.o _fractUHQQQ_s.o _fractUHQHQ_s.o _fractUHQSQ_s.o _fractUHQDQ_s.o _fractUHQTQ_s.o _fractUHQHA_s.o _fractUHQSA_s.o _fractUHQDA_s.o _fractUHQTA_s.o _fractUHQUQQ_s.o _fractUHQUSQ_s.o _fractUHQUDQ_s.o _fractUHQUTQ_s.o _fractUHQUHA_s.o _fractUHQUSA_s.o _fractUHQUDA_s.o _fractUHQUTA_s.o _fractUHQQI_s.o _fractUHQHI_s.o _fractUHQSI_s.o _fractUHQDI_s.o _fractUHQTI_s.o _fractUHQSF_s.o _fractUHQDF_s.o _fractUSQQQ_s.o _fractUSQHQ_s.o _fractUSQSQ_s.o _fractUSQDQ_s.o _fractUSQTQ_s.o _fractUSQHA_s.o _fractUSQSA_s.o _fractUSQDA_s.o _fractUSQTA_s.o _fractUSQUQQ_s.o _fractUSQUHQ_s.o _fractUSQUDQ_s.o _fractUSQUTQ_s.o _fractUSQUHA_s.o _fractUSQUSA_s.o _fractUSQUDA_s.o _fractUSQUTA_s.o _fractUSQQI_s.o _fractUSQHI_s.o _fractUSQSI_s.o _fractUSQDI_s.o _fractUSQTI_s.o _fractUSQSF_s.o _fractUSQDF_s.o _fractUDQQQ_s.o _fractUDQHQ_s.o _fractUDQSQ_s.o _fractUDQDQ_s.o _fractUDQTQ_s.o _fractUDQHA_s.o _fractUDQSA_s.o _fractUDQDA_s.o _fractUDQTA_s.o _fractUDQUQQ_s.o _fractUDQUHQ_s.o _fractUDQUSQ_s.o _fractUDQUTQ_s.o _fractUDQUHA_s.o _fractUDQUSA_s.o _fractUDQUDA_s.o _fractUDQUTA_s.o _fractUDQQI_s.o _fractUDQHI_s.o _fractUDQSI_s.o _fractUDQDI_s.o _fractUDQTI_s.o _fractUDQSF_s.o _fractUDQDF_s.o _fractUTQQQ_s.o _fractUTQHQ_s.o _fractUTQSQ_s.o _fractUTQDQ_s.o _fractUTQTQ_s.o _fractUTQHA_s.o _fractUTQSA_s.o _fractUTQDA_s.o _fractUTQTA_s.o _fractUTQUQQ_s.o _fractUTQUHQ_s.o _fractUTQUSQ_s.o _fractUTQUDQ_s.o _fractUTQUHA_s.o _fractUTQUSA_s.o _fractUTQUDA_s.o _fractUTQUTA_s.o _fractUTQQI_s.o _fractUTQHI_s.o _fractUTQSI_s.o _fractUTQDI_s.o _fractUTQTI_s.o _fractUTQSF_s.o _fractUTQDF_s.o _fractUHAQQ_s.o _fractUHAHQ_s.o _fractUHASQ_s.o _fractUHADQ_s.o _fractUHATQ_s.o _fractUHAHA_s.o _fractUHASA_s.o _fractUHADA_s.o _fractUHATA_s.o _fractUHAUQQ_s.o _fractUHAUHQ_s.o _fractUHAUSQ_s.o _fractUHAUDQ_s.o _fractUHAUTQ_s.o _fractUHAUSA_s.o _fractUHAUDA_s.o _fractUHAUTA_s.o _fractUHAQI_s.o _fractUHAHI_s.o _fractUHASI_s.o _fractUHADI_s.o _fractUHATI_s.o _fractUHASF_s.o _fractUHADF_s.o _fractUSAQQ_s.o _fractUSAHQ_s.o _fractUSASQ_s.o _fractUSADQ_s.o _fractUSATQ_s.o _fractUSAHA_s.o _fractUSASA_s.o _fractUSADA_s.o _fractUSATA_s.o _fractUSAUQQ_s.o _fractUSAUHQ_s.o _fractUSAUSQ_s.o _fractUSAUDQ_s.o _fractUSAUTQ_s.o _fractUSAUHA_s.o _fractUSAUDA_s.o _fractUSAUTA_s.o _fractUSAQI_s.o _fractUSAHI_s.o _fractUSASI_s.o _fractUSADI_s.o _fractUSATI_s.o _fractUSASF_s.o _fractUSADF_s.o _fractUDAQQ_s.o _fractUDAHQ_s.o _fractUDASQ_s.o _fractUDADQ_s.o _fractUDATQ_s.o _fractUDAHA_s.o _fractUDASA_s.o _fractUDADA_s.o _fractUDATA_s.o _fractUDAUQQ_s.o _fractUDAUHQ_s.o _fractUDAUSQ_s.o _fractUDAUDQ_s.o _fractUDAUTQ_s.o _fractUDAUHA_s.o _fractUDAUSA_s.o _fractUDAUTA_s.o _fractUDAQI_s.o _fractUDAHI_s.o _fractUDASI_s.o _fractUDADI_s.o _fractUDATI_s.o _fractUDASF_s.o _fractUDADF_s.o _fractUTAQQ_s.o _fractUTAHQ_s.o _fractUTASQ_s.o _fractUTADQ_s.o _fractUTATQ_s.o _fractUTAHA_s.o _fractUTASA_s.o _fractUTADA_s.o _fractUTATA_s.o _fractUTAUQQ_s.o _fractUTAUHQ_s.o _fractUTAUSQ_s.o _fractUTAUDQ_s.o _fractUTAUTQ_s.o _fractUTAUHA_s.o _fractUTAUSA_s.o _fractUTAUDA_s.o _fractUTAQI_s.o _fractUTAHI_s.o _fractUTASI_s.o _fractUTADI_s.o _fractUTATI_s.o _fractUTASF_s.o _fractUTADF_s.o _fractQIQQ_s.o _fractQIHQ_s.o _fractQISQ_s.o _fractQIDQ_s.o _fractQITQ_s.o _fractQIHA_s.o _fractQISA_s.o _fractQIDA_s.o _fractQITA_s.o _fractQIUQQ_s.o _fractQIUHQ_s.o _fractQIUSQ_s.o _fractQIUDQ_s.o _fractQIUTQ_s.o _fractQIUHA_s.o _fractQIUSA_s.o _fractQIUDA_s.o _fractQIUTA_s.o _fractHIQQ_s.o _fractHIHQ_s.o _fractHISQ_s.o _fractHIDQ_s.o _fractHITQ_s.o _fractHIHA_s.o _fractHISA_s.o _fractHIDA_s.o _fractHITA_s.o _fractHIUQQ_s.o _fractHIUHQ_s.o _fractHIUSQ_s.o _fractHIUDQ_s.o _fractHIUTQ_s.o _fractHIUHA_s.o _fractHIUSA_s.o _fractHIUDA_s.o _fractHIUTA_s.o _fractSIQQ_s.o _fractSIHQ_s.o _fractSISQ_s.o _fractSIDQ_s.o _fractSITQ_s.o _fractSIHA_s.o _fractSISA_s.o _fractSIDA_s.o _fractSITA_s.o _fractSIUQQ_s.o _fractSIUHQ_s.o _fractSIUSQ_s.o _fractSIUDQ_s.o _fractSIUTQ_s.o _fractSIUHA_s.o _fractSIUSA_s.o _fractSIUDA_s.o _fractSIUTA_s.o _fractDIQQ_s.o _fractDIHQ_s.o _fractDISQ_s.o _fractDIDQ_s.o _fractDITQ_s.o _fractDIHA_s.o _fractDISA_s.o _fractDIDA_s.o _fractDITA_s.o _fractDIUQQ_s.o _fractDIUHQ_s.o _fractDIUSQ_s.o _fractDIUDQ_s.o _fractDIUTQ_s.o _fractDIUHA_s.o _fractDIUSA_s.o _fractDIUDA_s.o _fractDIUTA_s.o _fractTIQQ_s.o _fractTIHQ_s.o _fractTISQ_s.o _fractTIDQ_s.o _fractTITQ_s.o _fractTIHA_s.o _fractTISA_s.o _fractTIDA_s.o _fractTITA_s.o _fractTIUQQ_s.o _fractTIUHQ_s.o _fractTIUSQ_s.o _fractTIUDQ_s.o _fractTIUTQ_s.o _fractTIUHA_s.o _fractTIUSA_s.o _fractTIUDA_s.o _fractTIUTA_s.o _fractSFQQ_s.o _fractSFHQ_s.o _fractSFSQ_s.o _fractSFDQ_s.o _fractSFTQ_s.o _fractSFHA_s.o _fractSFSA_s.o _fractSFDA_s.o _fractSFTA_s.o _fractSFUQQ_s.o _fractSFUHQ_s.o _fractSFUSQ_s.o _fractSFUDQ_s.o _fractSFUTQ_s.o _fractSFUHA_s.o _fractSFUSA_s.o _fractSFUDA_s.o _fractSFUTA_s.o _fractDFQQ_s.o _fractDFHQ_s.o _fractDFSQ_s.o _fractDFDQ_s.o _fractDFTQ_s.o _fractDFHA_s.o _fractDFSA_s.o _fractDFDA_s.o _fractDFTA_s.o _fractDFUQQ_s.o _fractDFUHQ_s.o _fractDFUSQ_s.o _fractDFUDQ_s.o _fractDFUTQ_s.o _fractDFUHA_s.o _fractDFUSA_s.o _fractDFUDA_s.o _fractDFUTA_s.o _satfractQQHQ_s.o _satfractQQSQ_s.o _satfractQQDQ_s.o _satfractQQTQ_s.o _satfractQQHA_s.o _satfractQQSA_s.o _satfractQQDA_s.o _satfractQQTA_s.o _satfractQQUQQ_s.o _satfractQQUHQ_s.o _satfractQQUSQ_s.o _satfractQQUDQ_s.o _satfractQQUTQ_s.o _satfractQQUHA_s.o _satfractQQUSA_s.o _satfractQQUDA_s.o _satfractQQUTA_s.o _satfractHQQQ_s.o _satfractHQSQ_s.o _satfractHQDQ_s.o _satfractHQTQ_s.o _satfractHQHA_s.o _satfractHQSA_s.o _satfractHQDA_s.o _satfractHQTA_s.o _satfractHQUQQ_s.o _satfractHQUHQ_s.o _satfractHQUSQ_s.o _satfractHQUDQ_s.o _satfractHQUTQ_s.o _satfractHQUHA_s.o _satfractHQUSA_s.o _satfractHQUDA_s.o _satfractHQUTA_s.o _satfractSQQQ_s.o _satfractSQHQ_s.o _satfractSQDQ_s.o _satfractSQTQ_s.o _satfractSQHA_s.o _satfractSQSA_s.o _satfractSQDA_s.o _satfractSQTA_s.o _satfractSQUQQ_s.o _satfractSQUHQ_s.o _satfractSQUSQ_s.o _satfractSQUDQ_s.o _satfractSQUTQ_s.o _satfractSQUHA_s.o _satfractSQUSA_s.o _satfractSQUDA_s.o _satfractSQUTA_s.o _satfractDQQQ_s.o _satfractDQHQ_s.o _satfractDQSQ_s.o _satfractDQTQ_s.o _satfractDQHA_s.o _satfractDQSA_s.o _satfractDQDA_s.o _satfractDQTA_s.o _satfractDQUQQ_s.o _satfractDQUHQ_s.o _satfractDQUSQ_s.o _satfractDQUDQ_s.o _satfractDQUTQ_s.o _satfractDQUHA_s.o _satfractDQUSA_s.o _satfractDQUDA_s.o _satfractDQUTA_s.o _satfractTQQQ_s.o _satfractTQHQ_s.o _satfractTQSQ_s.o _satfractTQDQ_s.o _satfractTQHA_s.o _satfractTQSA_s.o _satfractTQDA_s.o _satfractTQTA_s.o _satfractTQUQQ_s.o _satfractTQUHQ_s.o _satfractTQUSQ_s.o _satfractTQUDQ_s.o _satfractTQUTQ_s.o _satfractTQUHA_s.o _satfractTQUSA_s.o _satfractTQUDA_s.o _satfractTQUTA_s.o _satfractHAQQ_s.o _satfractHAHQ_s.o _satfractHASQ_s.o _satfractHADQ_s.o _satfractHATQ_s.o _satfractHASA_s.o _satfractHADA_s.o _satfractHATA_s.o _satfractHAUQQ_s.o _satfractHAUHQ_s.o _satfractHAUSQ_s.o _satfractHAUDQ_s.o _satfractHAUTQ_s.o _satfractHAUHA_s.o _satfractHAUSA_s.o _satfractHAUDA_s.o _satfractHAUTA_s.o _satfractSAQQ_s.o _satfractSAHQ_s.o _satfractSASQ_s.o _satfractSADQ_s.o _satfractSATQ_s.o _satfractSAHA_s.o _satfractSADA_s.o _satfractSATA_s.o _satfractSAUQQ_s.o _satfractSAUHQ_s.o _satfractSAUSQ_s.o _satfractSAUDQ_s.o _satfractSAUTQ_s.o _satfractSAUHA_s.o _satfractSAUSA_s.o _satfractSAUDA_s.o _satfractSAUTA_s.o _satfractDAQQ_s.o _satfractDAHQ_s.o _satfractDASQ_s.o _satfractDADQ_s.o _satfractDATQ_s.o _satfractDAHA_s.o _satfractDASA_s.o _satfractDATA_s.o _satfractDAUQQ_s.o _satfractDAUHQ_s.o _satfractDAUSQ_s.o _satfractDAUDQ_s.o _satfractDAUTQ_s.o _satfractDAUHA_s.o _satfractDAUSA_s.o _satfractDAUDA_s.o _satfractDAUTA_s.o _satfractTAQQ_s.o _satfractTAHQ_s.o _satfractTASQ_s.o _satfractTADQ_s.o _satfractTATQ_s.o _satfractTAHA_s.o _satfractTASA_s.o _satfractTADA_s.o _satfractTAUQQ_s.o _satfractTAUHQ_s.o _satfractTAUSQ_s.o _satfractTAUDQ_s.o _satfractTAUTQ_s.o _satfractTAUHA_s.o _satfractTAUSA_s.o _satfractTAUDA_s.o _satfractTAUTA_s.o _satfractUQQQQ_s.o _satfractUQQHQ_s.o _satfractUQQSQ_s.o _satfractUQQDQ_s.o _satfractUQQTQ_s.o _satfractUQQHA_s.o _satfractUQQSA_s.o _satfractUQQDA_s.o _satfractUQQTA_s.o _satfractUQQUHQ_s.o _satfractUQQUSQ_s.o _satfractUQQUDQ_s.o _satfractUQQUTQ_s.o _satfractUQQUHA_s.o _satfractUQQUSA_s.o _satfractUQQUDA_s.o _satfractUQQUTA_s.o _satfractUHQQQ_s.o _satfractUHQHQ_s.o _satfractUHQSQ_s.o _satfractUHQDQ_s.o _satfractUHQTQ_s.o _satfractUHQHA_s.o _satfractUHQSA_s.o _satfractUHQDA_s.o _satfractUHQTA_s.o _satfractUHQUQQ_s.o _satfractUHQUSQ_s.o _satfractUHQUDQ_s.o _satfractUHQUTQ_s.o _satfractUHQUHA_s.o _satfractUHQUSA_s.o _satfractUHQUDA_s.o _satfractUHQUTA_s.o _satfractUSQQQ_s.o _satfractUSQHQ_s.o _satfractUSQSQ_s.o _satfractUSQDQ_s.o _satfractUSQTQ_s.o _satfractUSQHA_s.o _satfractUSQSA_s.o _satfractUSQDA_s.o _satfractUSQTA_s.o _satfractUSQUQQ_s.o _satfractUSQUHQ_s.o _satfractUSQUDQ_s.o _satfractUSQUTQ_s.o _satfractUSQUHA_s.o _satfractUSQUSA_s.o _satfractUSQUDA_s.o _satfractUSQUTA_s.o _satfractUDQQQ_s.o _satfractUDQHQ_s.o _satfractUDQSQ_s.o _satfractUDQDQ_s.o _satfractUDQTQ_s.o _satfractUDQHA_s.o _satfractUDQSA_s.o _satfractUDQDA_s.o _satfractUDQTA_s.o _satfractUDQUQQ_s.o _satfractUDQUHQ_s.o _satfractUDQUSQ_s.o _satfractUDQUTQ_s.o _satfractUDQUHA_s.o _satfractUDQUSA_s.o _satfractUDQUDA_s.o _satfractUDQUTA_s.o _satfractUTQQQ_s.o _satfractUTQHQ_s.o _satfractUTQSQ_s.o _satfractUTQDQ_s.o _satfractUTQTQ_s.o _satfractUTQHA_s.o _satfractUTQSA_s.o _satfractUTQDA_s.o _satfractUTQTA_s.o _satfractUTQUQQ_s.o _satfractUTQUHQ_s.o _satfractUTQUSQ_s.o _satfractUTQUDQ_s.o _satfractUTQUHA_s.o _satfractUTQUSA_s.o _satfractUTQUDA_s.o _satfractUTQUTA_s.o _satfractUHAQQ_s.o _satfractUHAHQ_s.o _satfractUHASQ_s.o _satfractUHADQ_s.o _satfractUHATQ_s.o _satfractUHAHA_s.o _satfractUHASA_s.o _satfractUHADA_s.o _satfractUHATA_s.o _satfractUHAUQQ_s.o _satfractUHAUHQ_s.o _satfractUHAUSQ_s.o _satfractUHAUDQ_s.o _satfractUHAUTQ_s.o _satfractUHAUSA_s.o _satfractUHAUDA_s.o _satfractUHAUTA_s.o _satfractUSAQQ_s.o _satfractUSAHQ_s.o _satfractUSASQ_s.o _satfractUSADQ_s.o _satfractUSATQ_s.o _satfractUSAHA_s.o _satfractUSASA_s.o _satfractUSADA_s.o _satfractUSATA_s.o _satfractUSAUQQ_s.o _satfractUSAUHQ_s.o _satfractUSAUSQ_s.o _satfractUSAUDQ_s.o _satfractUSAUTQ_s.o _satfractUSAUHA_s.o _satfractUSAUDA_s.o _satfractUSAUTA_s.o _satfractUDAQQ_s.o _satfractUDAHQ_s.o _satfractUDASQ_s.o _satfractUDADQ_s.o _satfractUDATQ_s.o _satfractUDAHA_s.o _satfractUDASA_s.o _satfractUDADA_s.o _satfractUDATA_s.o _satfractUDAUQQ_s.o _satfractUDAUHQ_s.o _satfractUDAUSQ_s.o _satfractUDAUDQ_s.o _satfractUDAUTQ_s.o _satfractUDAUHA_s.o _satfractUDAUSA_s.o _satfractUDAUTA_s.o _satfractUTAQQ_s.o _satfractUTAHQ_s.o _satfractUTASQ_s.o _satfractUTADQ_s.o _satfractUTATQ_s.o _satfractUTAHA_s.o _satfractUTASA_s.o _satfractUTADA_s.o _satfractUTATA_s.o _satfractUTAUQQ_s.o _satfractUTAUHQ_s.o _satfractUTAUSQ_s.o _satfractUTAUDQ_s.o _satfractUTAUTQ_s.o _satfractUTAUHA_s.o _satfractUTAUSA_s.o _satfractUTAUDA_s.o _satfractQIQQ_s.o _satfractQIHQ_s.o _satfractQISQ_s.o _satfractQIDQ_s.o _satfractQITQ_s.o _satfractQIHA_s.o _satfractQISA_s.o _satfractQIDA_s.o _satfractQITA_s.o _satfractQIUQQ_s.o _satfractQIUHQ_s.o _satfractQIUSQ_s.o _satfractQIUDQ_s.o _satfractQIUTQ_s.o _satfractQIUHA_s.o _satfractQIUSA_s.o _satfractQIUDA_s.o _satfractQIUTA_s.o _satfractHIQQ_s.o _satfractHIHQ_s.o _satfractHISQ_s.o _satfractHIDQ_s.o _satfractHITQ_s.o _satfractHIHA_s.o _satfractHISA_s.o _satfractHIDA_s.o _satfractHITA_s.o _satfractHIUQQ_s.o _satfractHIUHQ_s.o _satfractHIUSQ_s.o _satfractHIUDQ_s.o _satfractHIUTQ_s.o _satfractHIUHA_s.o _satfractHIUSA_s.o _satfractHIUDA_s.o _satfractHIUTA_s.o _satfractSIQQ_s.o _satfractSIHQ_s.o _satfractSISQ_s.o _satfractSIDQ_s.o _satfractSITQ_s.o _satfractSIHA_s.o _satfractSISA_s.o _satfractSIDA_s.o _satfractSITA_s.o _satfractSIUQQ_s.o _satfractSIUHQ_s.o _satfractSIUSQ_s.o _satfractSIUDQ_s.o _satfractSIUTQ_s.o _satfractSIUHA_s.o _satfractSIUSA_s.o _satfractSIUDA_s.o _satfractSIUTA_s.o _satfractDIQQ_s.o _satfractDIHQ_s.o _satfractDISQ_s.o _satfractDIDQ_s.o _satfractDITQ_s.o _satfractDIHA_s.o _satfractDISA_s.o _satfractDIDA_s.o _satfractDITA_s.o _satfractDIUQQ_s.o _satfractDIUHQ_s.o _satfractDIUSQ_s.o _satfractDIUDQ_s.o _satfractDIUTQ_s.o _satfractDIUHA_s.o _satfractDIUSA_s.o _satfractDIUDA_s.o _satfractDIUTA_s.o _satfractTIQQ_s.o _satfractTIHQ_s.o _satfractTISQ_s.o _satfractTIDQ_s.o _satfractTITQ_s.o _satfractTIHA_s.o _satfractTISA_s.o _satfractTIDA_s.o _satfractTITA_s.o _satfractTIUQQ_s.o _satfractTIUHQ_s.o _satfractTIUSQ_s.o _satfractTIUDQ_s.o _satfractTIUTQ_s.o _satfractTIUHA_s.o _satfractTIUSA_s.o _satfractTIUDA_s.o _satfractTIUTA_s.o _satfractSFQQ_s.o _satfractSFHQ_s.o _satfractSFSQ_s.o _satfractSFDQ_s.o _satfractSFTQ_s.o _satfractSFHA_s.o _satfractSFSA_s.o _satfractSFDA_s.o _satfractSFTA_s.o _satfractSFUQQ_s.o _satfractSFUHQ_s.o _satfractSFUSQ_s.o _satfractSFUDQ_s.o _satfractSFUTQ_s.o _satfractSFUHA_s.o _satfractSFUSA_s.o _satfractSFUDA_s.o _satfractSFUTA_s.o _satfractDFQQ_s.o _satfractDFHQ_s.o _satfractDFSQ_s.o _satfractDFDQ_s.o _satfractDFTQ_s.o _satfractDFHA_s.o _satfractDFSA_s.o _satfractDFDA_s.o _satfractDFTA_s.o _satfractDFUQQ_s.o _satfractDFUHQ_s.o _satfractDFUSQ_s.o _satfractDFUDQ_s.o _satfractDFUTQ_s.o _satfractDFUHA_s.o _satfractDFUSA_s.o _satfractDFUDA_s.o _satfractDFUTA_s.o _fractunsQQUQI_s.o _fractunsQQUHI_s.o _fractunsQQUSI_s.o _fractunsQQUDI_s.o _fractunsQQUTI_s.o _fractunsHQUQI_s.o _fractunsHQUHI_s.o _fractunsHQUSI_s.o _fractunsHQUDI_s.o _fractunsHQUTI_s.o _fractunsSQUQI_s.o _fractunsSQUHI_s.o _fractunsSQUSI_s.o _fractunsSQUDI_s.o _fractunsSQUTI_s.o _fractunsDQUQI_s.o _fractunsDQUHI_s.o _fractunsDQUSI_s.o _fractunsDQUDI_s.o _fractunsDQUTI_s.o _fractunsTQUQI_s.o _fractunsTQUHI_s.o _fractunsTQUSI_s.o _fractunsTQUDI_s.o _fractunsTQUTI_s.o _fractunsHAUQI_s.o _fractunsHAUHI_s.o _fractunsHAUSI_s.o _fractunsHAUDI_s.o _fractunsHAUTI_s.o _fractunsSAUQI_s.o _fractunsSAUHI_s.o _fractunsSAUSI_s.o _fractunsSAUDI_s.o _fractunsSAUTI_s.o _fractunsDAUQI_s.o _fractunsDAUHI_s.o _fractunsDAUSI_s.o _fractunsDAUDI_s.o _fractunsDAUTI_s.o _fractunsTAUQI_s.o _fractunsTAUHI_s.o _fractunsTAUSI_s.o _fractunsTAUDI_s.o _fractunsTAUTI_s.o _fractunsUQQUQI_s.o _fractunsUQQUHI_s.o _fractunsUQQUSI_s.o _fractunsUQQUDI_s.o _fractunsUQQUTI_s.o _fractunsUHQUQI_s.o _fractunsUHQUHI_s.o _fractunsUHQUSI_s.o _fractunsUHQUDI_s.o _fractunsUHQUTI_s.o _fractunsUSQUQI_s.o _fractunsUSQUHI_s.o _fractunsUSQUSI_s.o _fractunsUSQUDI_s.o _fractunsUSQUTI_s.o _fractunsUDQUQI_s.o _fractunsUDQUHI_s.o _fractunsUDQUSI_s.o _fractunsUDQUDI_s.o _fractunsUDQUTI_s.o _fractunsUTQUQI_s.o _fractunsUTQUHI_s.o _fractunsUTQUSI_s.o _fractunsUTQUDI_s.o _fractunsUTQUTI_s.o _fractunsUHAUQI_s.o _fractunsUHAUHI_s.o _fractunsUHAUSI_s.o _fractunsUHAUDI_s.o _fractunsUHAUTI_s.o _fractunsUSAUQI_s.o _fractunsUSAUHI_s.o _fractunsUSAUSI_s.o _fractunsUSAUDI_s.o _fractunsUSAUTI_s.o _fractunsUDAUQI_s.o _fractunsUDAUHI_s.o _fractunsUDAUSI_s.o _fractunsUDAUDI_s.o _fractunsUDAUTI_s.o _fractunsUTAUQI_s.o _fractunsUTAUHI_s.o _fractunsUTAUSI_s.o _fractunsUTAUDI_s.o _fractunsUTAUTI_s.o _fractunsUQIQQ_s.o _fractunsUQIHQ_s.o _fractunsUQISQ_s.o _fractunsUQIDQ_s.o _fractunsUQITQ_s.o _fractunsUQIHA_s.o _fractunsUQISA_s.o _fractunsUQIDA_s.o _fractunsUQITA_s.o _fractunsUQIUQQ_s.o _fractunsUQIUHQ_s.o _fractunsUQIUSQ_s.o _fractunsUQIUDQ_s.o _fractunsUQIUTQ_s.o _fractunsUQIUHA_s.o _fractunsUQIUSA_s.o _fractunsUQIUDA_s.o _fractunsUQIUTA_s.o _fractunsUHIQQ_s.o _fractunsUHIHQ_s.o _fractunsUHISQ_s.o _fractunsUHIDQ_s.o _fractunsUHITQ_s.o _fractunsUHIHA_s.o _fractunsUHISA_s.o _fractunsUHIDA_s.o _fractunsUHITA_s.o _fractunsUHIUQQ_s.o _fractunsUHIUHQ_s.o _fractunsUHIUSQ_s.o _fractunsUHIUDQ_s.o _fractunsUHIUTQ_s.o _fractunsUHIUHA_s.o _fractunsUHIUSA_s.o _fractunsUHIUDA_s.o _fractunsUHIUTA_s.o _fractunsUSIQQ_s.o _fractunsUSIHQ_s.o _fractunsUSISQ_s.o _fractunsUSIDQ_s.o _fractunsUSITQ_s.o _fractunsUSIHA_s.o _fractunsUSISA_s.o _fractunsUSIDA_s.o _fractunsUSITA_s.o _fractunsUSIUQQ_s.o _fractunsUSIUHQ_s.o _fractunsUSIUSQ_s.o _fractunsUSIUDQ_s.o _fractunsUSIUTQ_s.o _fractunsUSIUHA_s.o _fractunsUSIUSA_s.o _fractunsUSIUDA_s.o _fractunsUSIUTA_s.o _fractunsUDIQQ_s.o _fractunsUDIHQ_s.o _fractunsUDISQ_s.o _fractunsUDIDQ_s.o _fractunsUDITQ_s.o _fractunsUDIHA_s.o _fractunsUDISA_s.o _fractunsUDIDA_s.o _fractunsUDITA_s.o _fractunsUDIUQQ_s.o _fractunsUDIUHQ_s.o _fractunsUDIUSQ_s.o _fractunsUDIUDQ_s.o _fractunsUDIUTQ_s.o _fractunsUDIUHA_s.o _fractunsUDIUSA_s.o _fractunsUDIUDA_s.o _fractunsUDIUTA_s.o _fractunsUTIQQ_s.o _fractunsUTIHQ_s.o _fractunsUTISQ_s.o _fractunsUTIDQ_s.o _fractunsUTITQ_s.o _fractunsUTIHA_s.o _fractunsUTISA_s.o _fractunsUTIDA_s.o _fractunsUTITA_s.o _fractunsUTIUQQ_s.o _fractunsUTIUHQ_s.o _fractunsUTIUSQ_s.o _fractunsUTIUDQ_s.o _fractunsUTIUTQ_s.o _fractunsUTIUHA_s.o _fractunsUTIUSA_s.o _fractunsUTIUDA_s.o _fractunsUTIUTA_s.o _satfractunsUQIQQ_s.o _satfractunsUQIHQ_s.o _satfractunsUQISQ_s.o _satfractunsUQIDQ_s.o _satfractunsUQITQ_s.o _satfractunsUQIHA_s.o _satfractunsUQISA_s.o _satfractunsUQIDA_s.o _satfractunsUQITA_s.o _satfractunsUQIUQQ_s.o _satfractunsUQIUHQ_s.o _satfractunsUQIUSQ_s.o _satfractunsUQIUDQ_s.o _satfractunsUQIUTQ_s.o _satfractunsUQIUHA_s.o _satfractunsUQIUSA_s.o _satfractunsUQIUDA_s.o _satfractunsUQIUTA_s.o _satfractunsUHIQQ_s.o _satfractunsUHIHQ_s.o _satfractunsUHISQ_s.o _satfractunsUHIDQ_s.o _satfractunsUHITQ_s.o _satfractunsUHIHA_s.o _satfractunsUHISA_s.o _satfractunsUHIDA_s.o _satfractunsUHITA_s.o _satfractunsUHIUQQ_s.o _satfractunsUHIUHQ_s.o _satfractunsUHIUSQ_s.o _satfractunsUHIUDQ_s.o _satfractunsUHIUTQ_s.o _satfractunsUHIUHA_s.o _satfractunsUHIUSA_s.o _satfractunsUHIUDA_s.o _satfractunsUHIUTA_s.o _satfractunsUSIQQ_s.o _satfractunsUSIHQ_s.o _satfractunsUSISQ_s.o _satfractunsUSIDQ_s.o _satfractunsUSITQ_s.o _satfractunsUSIHA_s.o _satfractunsUSISA_s.o _satfractunsUSIDA_s.o _satfractunsUSITA_s.o _satfractunsUSIUQQ_s.o _satfractunsUSIUHQ_s.o _satfractunsUSIUSQ_s.o _satfractunsUSIUDQ_s.o _satfractunsUSIUTQ_s.o _satfractunsUSIUHA_s.o _satfractunsUSIUSA_s.o _satfractunsUSIUDA_s.o _satfractunsUSIUTA_s.o _satfractunsUDIQQ_s.o _satfractunsUDIHQ_s.o _satfractunsUDISQ_s.o _satfractunsUDIDQ_s.o _satfractunsUDITQ_s.o _satfractunsUDIHA_s.o _satfractunsUDISA_s.o _satfractunsUDIDA_s.o _satfractunsUDITA_s.o _satfractunsUDIUQQ_s.o _satfractunsUDIUHQ_s.o _satfractunsUDIUSQ_s.o _satfractunsUDIUDQ_s.o _satfractunsUDIUTQ_s.o _satfractunsUDIUHA_s.o _satfractunsUDIUSA_s.o _satfractunsUDIUDA_s.o _satfractunsUDIUTA_s.o _satfractunsUTIQQ_s.o _satfractunsUTIHQ_s.o _satfractunsUTISQ_s.o _satfractunsUTIDQ_s.o _satfractunsUTITQ_s.o _satfractunsUTIHA_s.o _satfractunsUTISA_s.o _satfractunsUTIDA_s.o _satfractunsUTITA_s.o _satfractunsUTIUQQ_s.o _satfractunsUTIUHQ_s.o _satfractunsUTIUSQ_s.o _satfractunsUTIUDQ_s.o _satfractunsUTIUTQ_s.o _satfractunsUTIUHA_s.o _satfractunsUTIUSA_s.o _satfractunsUTIUDA_s.o _satfractunsUTIUTA_s.o bpabi_s.o unaligned-funcs_s.o addsf3_s.o divsf3_s.o eqsf2_s.o gesf2_s.o lesf2_s.o mulsf3_s.o negsf2_s.o subsf3_s.o unordsf2_s.o fixsfsi_s.o floatsisf_s.o floatunsisf_s.o adddf3_s.o divdf3_s.o eqdf2_s.o gedf2_s.o ledf2_s.o muldf3_s.o negdf2_s.o subdf3_s.o unorddf2_s.o fixdfsi_s.o floatsidf_s.o floatunsidf_s.o extendsfdf2_s.o truncdfsf2_s.o enable-execute-stack_s.o unwind-arm_s.o libunwind_s.o pr-support_s.o unwind-c_s.o emutls_s.o libgcc.a -lc && rm -f ./libgcc_s.so && if [ -f ./libgcc_s.so.1 ]; then mv -f ./libgcc_s.so.1 ./libgcc_s.so.1.backup; else true; fi && mv ./libgcc_s.so.1.tmp ./libgcc_s.so.1 && (echo "/* GNU ld script"; echo "   Use the shared library, but some functions are only in"; echo "   the static library.  */"; echo "GROUP ( libgcc_s.so.1 -lgcc )" ) > ./libgcc_s.so
[ERROR]    xgcc.exe: error: CreateProcess: No such file or directory
[ALL  ]    Makefile:926: recipe for target 'libgcc_s.so' failed
[ERROR]    make[2]: *** [libgcc_s.so] Error 1
[ALL  ]    make[2]: Leaving directory '/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-cc-gcc-core-pass-2/armv6hl-unknown-linux-gnueabi/libgcc'



pushd /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-cc-gcc-core-pass-2/armv6hl-unknown-linux-gnueabi/libgcc
/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-cc-gcc-core-pass-2/./gcc/xgcc -B/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-cc-gcc-core-pass-2/./gcc/ -B/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/armv6hl-unknown-linux-gnueabi/bin/ -B/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/armv6hl-unknown-linux-gnueabi/lib/ -isystem /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/armv6hl-unknown-linux-gnueabi/include -isystem /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/armv6hl-unknown-linux-gnueabi/sys-include    -O2  -DIN_GCC -DCROSS_DIRECTORY_STRUCTURE  -W -Wall -Wno-narrowing -Wwrite-strings -Wcast-qual -Wstrict-prototypes -Wmissing-prototypes -Wold-style-definition  -isystem ./include   -fPIC -fno-inline -g -DIN_LIBGCC2 -fbuilding-libgcc -fno-stack-protector  -shared -nodefaultlibs -Wl,--soname=libgcc_s.so.1 -Wl,--version-script=libgcc.map -o ./libgcc_s.so.1.tmp -g -Os -B./ _thumb1_case_sqi_s.o _thumb1_case_uqi_s.o _thumb1_case_shi_s.o _thumb1_case_uhi_s.o _thumb1_case_si_s.o _udivsi3_s.o _divsi3_s.o _umodsi3_s.o _modsi3_s.o _bb_init_func_s.o _call_via_rX_s.o _interwork_call_via_rX_s.o _lshrdi3_s.o _ashrdi3_s.o _ashldi3_s.o _arm_negdf2_s.o _arm_addsubdf3_s.o _arm_muldivdf3_s.o _arm_cmpdf2_s.o _arm_unorddf2_s.o _arm_fixdfsi_s.o _arm_fixunsdfsi_s.o _arm_truncdfsf2_s.o _arm_negsf2_s.o _arm_addsubsf3_s.o _arm_muldivsf3_s.o _arm_cmpsf2_s.o _arm_unordsf2_s.o _arm_fixsfsi_s.o _arm_fixunssfsi_s.o _arm_floatdidf_s.o _arm_floatdisf_s.o _arm_floatundidf_s.o _arm_floatundisf_s.o _clzsi2_s.o _clzdi2_s.o _ctzsi2_s.o _aeabi_lcmp_s.o _aeabi_ulcmp_s.o _aeabi_ldivmod_s.o _aeabi_uldivmod_s.o _dvmd_lnx_s.o _clear_cache_s.o _muldi3_s.o _negdi2_s.o _cmpdi2_s.o _ucmpdi2_s.o _trampoline_s.o __main_s.o _absvsi2_s.o _absvdi2_s.o _addvsi3_s.o _addvdi3_s.o _subvsi3_s.o _subvdi3_s.o _mulvsi3_s.o _mulvdi3_s.o _negvsi2_s.o _negvdi2_s.o _ctors_s.o _ffssi2_s.o _ffsdi2_s.o _clz_s.o _ctzdi2_s.o _popcount_tab_s.o _popcountsi2_s.o _popcountdi2_s.o _paritysi2_s.o _paritydi2_s.o _powisf2_s.o _powidf2_s.o _powixf2_s.o _powitf2_s.o _mulsc3_s.o _muldc3_s.o _mulxc3_s.o _multc3_s.o _divsc3_s.o _divdc3_s.o _divxc3_s.o _divtc3_s.o _bswapsi2_s.o _bswapdi2_s.o _clrsbsi2_s.o _clrsbdi2_s.o _fixunssfsi_s.o _fixunsdfsi_s.o _fixunsxfsi_s.o _fixsfdi_s.o _fixdfdi_s.o _fixxfdi_s.o _fixtfdi_s.o _fixunssfdi_s.o _fixunsdfdi_s.o _fixunsxfdi_s.o _fixunstfdi_s.o _floatdisf_s.o _floatdidf_s.o _floatdixf_s.o _floatditf_s.o _floatundisf_s.o _floatundidf_s.o _floatundixf_s.o _floatunditf_s.o _divdi3_s.o _moddi3_s.o _udivdi3_s.o _umoddi3_s.o _udiv_w_sdiv_s.o _udivmoddi4_s.o _addQQ_s.o _addHQ_s.o _addSQ_s.o _addDQ_s.o _addTQ_s.o _addHA_s.o _addSA_s.o _addDA_s.o _addTA_s.o _addUQQ_s.o _addUHQ_s.o _addUSQ_s.o _addUDQ_s.o _addUTQ_s.o _addUHA_s.o _addUSA_s.o _addUDA_s.o _addUTA_s.o _subQQ_s.o _subHQ_s.o _subSQ_s.o _subDQ_s.o _subTQ_s.o _subHA_s.o _subSA_s.o _subDA_s.o _subTA_s.o _subUQQ_s.o _subUHQ_s.o _subUSQ_s.o _subUDQ_s.o _subUTQ_s.o _subUHA_s.o _subUSA_s.o _subUDA_s.o _subUTA_s.o _negQQ_s.o _negHQ_s.o _negSQ_s.o _negDQ_s.o _negTQ_s.o _negHA_s.o _negSA_s.o _negDA_s.o _negTA_s.o _negUQQ_s.o _negUHQ_s.o _negUSQ_s.o _negUDQ_s.o _negUTQ_s.o _negUHA_s.o _negUSA_s.o _negUDA_s.o _negUTA_s.o _mulQQ_s.o _mulHQ_s.o _mulSQ_s.o _mulDQ_s.o _mulTQ_s.o _mulHA_s.o _mulSA_s.o _mulDA_s.o _mulTA_s.o _mulUQQ_s.o _mulUHQ_s.o _mulUSQ_s.o _mulUDQ_s.o _mulUTQ_s.o _mulUHA_s.o _mulUSA_s.o _mulUDA_s.o _mulUTA_s.o _mulhelperQQ_s.o _mulhelperHQ_s.o _mulhelperSQ_s.o _mulhelperDQ_s.o _mulhelperTQ_s.o _mulhelperHA_s.o _mulhelperSA_s.o _mulhelperDA_s.o _mulhelperTA_s.o _mulhelperUQQ_s.o _mulhelperUHQ_s.o _mulhelperUSQ_s.o _mulhelperUDQ_s.o _mulhelperUTQ_s.o _mulhelperUHA_s.o _mulhelperUSA_s.o _mulhelperUDA_s.o _mulhelperUTA_s.o _divhelperQQ_s.o _divhelperHQ_s.o _divhelperSQ_s.o _divhelperDQ_s.o _divhelperTQ_s.o _divhelperHA_s.o _divhelperSA_s.o _divhelperDA_s.o _divhelperTA_s.o _divhelperUQQ_s.o _divhelperUHQ_s.o _divhelperUSQ_s.o _divhelperUDQ_s.o _divhelperUTQ_s.o _divhelperUHA_s.o _divhelperUSA_s.o _divhelperUDA_s.o _divhelperUTA_s.o _ashlQQ_s.o _ashlHQ_s.o _ashlSQ_s.o _ashlDQ_s.o _ashlTQ_s.o _ashlHA_s.o _ashlSA_s.o _ashlDA_s.o _ashlTA_s.o _ashlUQQ_s.o _ashlUHQ_s.o _ashlUSQ_s.o _ashlUDQ_s.o _ashlUTQ_s.o _ashlUHA_s.o _ashlUSA_s.o _ashlUDA_s.o _ashlUTA_s.o _ashlhelperQQ_s.o _ashlhelperHQ_s.o _ashlhelperSQ_s.o _ashlhelperDQ_s.o _ashlhelperTQ_s.o _ashlhelperHA_s.o _ashlhelperSA_s.o _ashlhelperDA_s.o _ashlhelperTA_s.o _ashlhelperUQQ_s.o _ashlhelperUHQ_s.o _ashlhelperUSQ_s.o _ashlhelperUDQ_s.o _ashlhelperUTQ_s.o _ashlhelperUHA_s.o _ashlhelperUSA_s.o _ashlhelperUDA_s.o _ashlhelperUTA_s.o _cmpQQ_s.o _cmpHQ_s.o _cmpSQ_s.o _cmpDQ_s.o _cmpTQ_s.o _cmpHA_s.o _cmpSA_s.o _cmpDA_s.o _cmpTA_s.o _cmpUQQ_s.o _cmpUHQ_s.o _cmpUSQ_s.o _cmpUDQ_s.o _cmpUTQ_s.o _cmpUHA_s.o _cmpUSA_s.o _cmpUDA_s.o _cmpUTA_s.o _saturate1QQ_s.o _saturate1HQ_s.o _saturate1SQ_s.o _saturate1DQ_s.o _saturate1TQ_s.o _saturate1HA_s.o _saturate1SA_s.o _saturate1DA_s.o _saturate1TA_s.o _saturate1UQQ_s.o _saturate1UHQ_s.o _saturate1USQ_s.o _saturate1UDQ_s.o _saturate1UTQ_s.o _saturate1UHA_s.o _saturate1USA_s.o _saturate1UDA_s.o _saturate1UTA_s.o _saturate2QQ_s.o _saturate2HQ_s.o _saturate2SQ_s.o _saturate2DQ_s.o _saturate2TQ_s.o _saturate2HA_s.o _saturate2SA_s.o _saturate2DA_s.o _saturate2TA_s.o _saturate2UQQ_s.o _saturate2UHQ_s.o _saturate2USQ_s.o _saturate2UDQ_s.o _saturate2UTQ_s.o _saturate2UHA_s.o _saturate2USA_s.o _saturate2UDA_s.o _saturate2UTA_s.o _ssaddQQ_s.o _ssaddHQ_s.o _ssaddSQ_s.o _ssaddDQ_s.o _ssaddTQ_s.o _ssaddHA_s.o _ssaddSA_s.o _ssaddDA_s.o _ssaddTA_s.o _sssubQQ_s.o _sssubHQ_s.o _sssubSQ_s.o _sssubDQ_s.o _sssubTQ_s.o _sssubHA_s.o _sssubSA_s.o _sssubDA_s.o _sssubTA_s.o _ssnegQQ_s.o _ssnegHQ_s.o _ssnegSQ_s.o _ssnegDQ_s.o _ssnegTQ_s.o _ssnegHA_s.o _ssnegSA_s.o _ssnegDA_s.o _ssnegTA_s.o _ssmulQQ_s.o _ssmulHQ_s.o _ssmulSQ_s.o _ssmulDQ_s.o _ssmulTQ_s.o _ssmulHA_s.o _ssmulSA_s.o _ssmulDA_s.o _ssmulTA_s.o _ssdivQQ_s.o _ssdivHQ_s.o _ssdivSQ_s.o _ssdivDQ_s.o _ssdivTQ_s.o _ssdivHA_s.o _ssdivSA_s.o _ssdivDA_s.o _ssdivTA_s.o _divQQ_s.o _divHQ_s.o _divSQ_s.o _divDQ_s.o _divTQ_s.o _divHA_s.o _divSA_s.o _divDA_s.o _divTA_s.o _ssashlQQ_s.o _ssashlHQ_s.o _ssashlSQ_s.o _ssashlDQ_s.o _ssashlTQ_s.o _ssashlHA_s.o _ssashlSA_s.o _ssashlDA_s.o _ssashlTA_s.o _ashrQQ_s.o _ashrHQ_s.o _ashrSQ_s.o _ashrDQ_s.o _ashrTQ_s.o _ashrHA_s.o _ashrSA_s.o _ashrDA_s.o _ashrTA_s.o _usaddUQQ_s.o _usaddUHQ_s.o _usaddUSQ_s.o _usaddUDQ_s.o _usaddUTQ_s.o _usaddUHA_s.o _usaddUSA_s.o _usaddUDA_s.o _usaddUTA_s.o _ussubUQQ_s.o _ussubUHQ_s.o _ussubUSQ_s.o _ussubUDQ_s.o _ussubUTQ_s.o _ussubUHA_s.o _ussubUSA_s.o _ussubUDA_s.o _ussubUTA_s.o _usnegUQQ_s.o _usnegUHQ_s.o _usnegUSQ_s.o _usnegUDQ_s.o _usnegUTQ_s.o _usnegUHA_s.o _usnegUSA_s.o _usnegUDA_s.o _usnegUTA_s.o _usmulUQQ_s.o _usmulUHQ_s.o _usmulUSQ_s.o _usmulUDQ_s.o _usmulUTQ_s.o _usmulUHA_s.o _usmulUSA_s.o _usmulUDA_s.o _usmulUTA_s.o _usdivUQQ_s.o _usdivUHQ_s.o _usdivUSQ_s.o _usdivUDQ_s.o _usdivUTQ_s.o _usdivUHA_s.o _usdivUSA_s.o _usdivUDA_s.o _usdivUTA_s.o _udivUQQ_s.o _udivUHQ_s.o _udivUSQ_s.o _udivUDQ_s.o _udivUTQ_s.o _udivUHA_s.o _udivUSA_s.o _udivUDA_s.o _udivUTA_s.o _usashlUQQ_s.o _usashlUHQ_s.o _usashlUSQ_s.o _usashlUDQ_s.o _usashlUTQ_s.o _usashlUHA_s.o _usashlUSA_s.o _usashlUDA_s.o _usashlUTA_s.o _lshrUQQ_s.o _lshrUHQ_s.o _lshrUSQ_s.o _lshrUDQ_s.o _lshrUTQ_s.o _lshrUHA_s.o _lshrUSA_s.o _lshrUDA_s.o _lshrUTA_s.o _fractQQHQ_s.o _fractQQSQ_s.o _fractQQDQ_s.o _fractQQTQ_s.o _fractQQHA_s.o _fractQQSA_s.o _fractQQDA_s.o _fractQQTA_s.o _fractQQUQQ_s.o _fractQQUHQ_s.o _fractQQUSQ_s.o _fractQQUDQ_s.o _fractQQUTQ_s.o _fractQQUHA_s.o _fractQQUSA_s.o _fractQQUDA_s.o _fractQQUTA_s.o _fractQQQI_s.o _fractQQHI_s.o _fractQQSI_s.o _fractQQDI_s.o _fractQQTI_s.o _fractQQSF_s.o _fractQQDF_s.o _fractHQQQ_s.o _fractHQSQ_s.o _fractHQDQ_s.o _fractHQTQ_s.o _fractHQHA_s.o _fractHQSA_s.o _fractHQDA_s.o _fractHQTA_s.o _fractHQUQQ_s.o _fractHQUHQ_s.o _fractHQUSQ_s.o _fractHQUDQ_s.o _fractHQUTQ_s.o _fractHQUHA_s.o _fractHQUSA_s.o _fractHQUDA_s.o _fractHQUTA_s.o _fractHQQI_s.o _fractHQHI_s.o _fractHQSI_s.o _fractHQDI_s.o _fractHQTI_s.o _fractHQSF_s.o _fractHQDF_s.o _fractSQQQ_s.o _fractSQHQ_s.o _fractSQDQ_s.o _fractSQTQ_s.o _fractSQHA_s.o _fractSQSA_s.o _fractSQDA_s.o _fractSQTA_s.o _fractSQUQQ_s.o _fractSQUHQ_s.o _fractSQUSQ_s.o _fractSQUDQ_s.o _fractSQUTQ_s.o _fractSQUHA_s.o _fractSQUSA_s.o _fractSQUDA_s.o _fractSQUTA_s.o _fractSQQI_s.o _fractSQHI_s.o _fractSQSI_s.o _fractSQDI_s.o _fractSQTI_s.o _fractSQSF_s.o _fractSQDF_s.o _fractDQQQ_s.o _fractDQHQ_s.o _fractDQSQ_s.o _fractDQTQ_s.o _fractDQHA_s.o _fractDQSA_s.o _fractDQDA_s.o _fractDQTA_s.o _fractDQUQQ_s.o _fractDQUHQ_s.o _fractDQUSQ_s.o _fractDQUDQ_s.o _fractDQUTQ_s.o _fractDQUHA_s.o _fractDQUSA_s.o _fractDQUDA_s.o _fractDQUTA_s.o _fractDQQI_s.o _fractDQHI_s.o _fractDQSI_s.o _fractDQDI_s.o _fractDQTI_s.o _fractDQSF_s.o _fractDQDF_s.o _fractTQQQ_s.o _fractTQHQ_s.o _fractTQSQ_s.o _fractTQDQ_s.o _fractTQHA_s.o _fractTQSA_s.o _fractTQDA_s.o _fractTQTA_s.o _fractTQUQQ_s.o _fractTQUHQ_s.o _fractTQUSQ_s.o _fractTQUDQ_s.o _fractTQUTQ_s.o _fractTQUHA_s.o _fractTQUSA_s.o _fractTQUDA_s.o _fractTQUTA_s.o _fractTQQI_s.o _fractTQHI_s.o _fractTQSI_s.o _fractTQDI_s.o _fractTQTI_s.o _fractTQSF_s.o _fractTQDF_s.o _fractHAQQ_s.o _fractHAHQ_s.o _fractHASQ_s.o _fractHADQ_s.o _fractHATQ_s.o _fractHASA_s.o _fractHADA_s.o _fractHATA_s.o _fractHAUQQ_s.o _fractHAUHQ_s.o _fractHAUSQ_s.o _fractHAUDQ_s.o _fractHAUTQ_s.o _fractHAUHA_s.o _fractHAUSA_s.o _fractHAUDA_s.o _fractHAUTA_s.o _fractHAQI_s.o _fractHAHI_s.o _fractHASI_s.o _fractHADI_s.o _fractHATI_s.o _fractHASF_s.o _fractHADF_s.o _fractSAQQ_s.o _fractSAHQ_s.o _fractSASQ_s.o _fractSADQ_s.o _fractSATQ_s.o _fractSAHA_s.o _fractSADA_s.o _fractSATA_s.o _fractSAUQQ_s.o _fractSAUHQ_s.o _fractSAUSQ_s.o _fractSAUDQ_s.o _fractSAUTQ_s.o _fractSAUHA_s.o _fractSAUSA_s.o _fractSAUDA_s.o _fractSAUTA_s.o _fractSAQI_s.o _fractSAHI_s.o _fractSASI_s.o _fractSADI_s.o _fractSATI_s.o _fractSASF_s.o _fractSADF_s.o _fractDAQQ_s.o _fractDAHQ_s.o _fractDASQ_s.o _fractDADQ_s.o _fractDATQ_s.o _fractDAHA_s.o _fractDASA_s.o _fractDATA_s.o _fractDAUQQ_s.o _fractDAUHQ_s.o _fractDAUSQ_s.o _fractDAUDQ_s.o _fractDAUTQ_s.o _fractDAUHA_s.o _fractDAUSA_s.o _fractDAUDA_s.o _fractDAUTA_s.o _fractDAQI_s.o _fractDAHI_s.o _fractDASI_s.o _fractDADI_s.o _fractDATI_s.o _fractDASF_s.o _fractDADF_s.o _fractTAQQ_s.o _fractTAHQ_s.o _fractTASQ_s.o _fractTADQ_s.o _fractTATQ_s.o _fractTAHA_s.o _fractTASA_s.o _fractTADA_s.o _fractTAUQQ_s.o _fractTAUHQ_s.o _fractTAUSQ_s.o _fractTAUDQ_s.o _fractTAUTQ_s.o _fractTAUHA_s.o _fractTAUSA_s.o _fractTAUDA_s.o _fractTAUTA_s.o _fractTAQI_s.o _fractTAHI_s.o _fractTASI_s.o _fractTADI_s.o _fractTATI_s.o _fractTASF_s.o _fractTADF_s.o _fractUQQQQ_s.o _fractUQQHQ_s.o _fractUQQSQ_s.o _fractUQQDQ_s.o _fractUQQTQ_s.o _fractUQQHA_s.o _fractUQQSA_s.o _fractUQQDA_s.o _fractUQQTA_s.o _fractUQQUHQ_s.o _fractUQQUSQ_s.o _fractUQQUDQ_s.o _fractUQQUTQ_s.o _fractUQQUHA_s.o _fractUQQUSA_s.o _fractUQQUDA_s.o _fractUQQUTA_s.o _fractUQQQI_s.o _fractUQQHI_s.o _fractUQQSI_s.o _fractUQQDI_s.o _fractUQQTI_s.o _fractUQQSF_s.o _fractUQQDF_s.o _fractUHQQQ_s.o _fractUHQHQ_s.o _fractUHQSQ_s.o _fractUHQDQ_s.o _fractUHQTQ_s.o _fractUHQHA_s.o _fractUHQSA_s.o _fractUHQDA_s.o _fractUHQTA_s.o _fractUHQUQQ_s.o _fractUHQUSQ_s.o _fractUHQUDQ_s.o _fractUHQUTQ_s.o _fractUHQUHA_s.o _fractUHQUSA_s.o _fractUHQUDA_s.o _fractUHQUTA_s.o _fractUHQQI_s.o _fractUHQHI_s.o _fractUHQSI_s.o _fractUHQDI_s.o _fractUHQTI_s.o _fractUHQSF_s.o _fractUHQDF_s.o _fractUSQQQ_s.o _fractUSQHQ_s.o _fractUSQSQ_s.o _fractUSQDQ_s.o _fractUSQTQ_s.o _fractUSQHA_s.o _fractUSQSA_s.o _fractUSQDA_s.o _fractUSQTA_s.o _fractUSQUQQ_s.o _fractUSQUHQ_s.o _fractUSQUDQ_s.o _fractUSQUTQ_s.o _fractUSQUHA_s.o _fractUSQUSA_s.o _fractUSQUDA_s.o _fractUSQUTA_s.o _fractUSQQI_s.o _fractUSQHI_s.o _fractUSQSI_s.o _fractUSQDI_s.o _fractUSQTI_s.o _fractUSQSF_s.o _fractUSQDF_s.o _fractUDQQQ_s.o _fractUDQHQ_s.o _fractUDQSQ_s.o _fractUDQDQ_s.o _fractUDQTQ_s.o _fractUDQHA_s.o _fractUDQSA_s.o _fractUDQDA_s.o _fractUDQTA_s.o _fractUDQUQQ_s.o _fractUDQUHQ_s.o _fractUDQUSQ_s.o _fractUDQUTQ_s.o _fractUDQUHA_s.o _fractUDQUSA_s.o _fractUDQUDA_s.o _fractUDQUTA_s.o _fractUDQQI_s.o _fractUDQHI_s.o _fractUDQSI_s.o _fractUDQDI_s.o _fractUDQTI_s.o _fractUDQSF_s.o _fractUDQDF_s.o _fractUTQQQ_s.o _fractUTQHQ_s.o _fractUTQSQ_s.o _fractUTQDQ_s.o _fractUTQTQ_s.o _fractUTQHA_s.o _fractUTQSA_s.o _fractUTQDA_s.o _fractUTQTA_s.o _fractUTQUQQ_s.o _fractUTQUHQ_s.o _fractUTQUSQ_s.o _fractUTQUDQ_s.o _fractUTQUHA_s.o _fractUTQUSA_s.o _fractUTQUDA_s.o _fractUTQUTA_s.o _fractUTQQI_s.o _fractUTQHI_s.o _fractUTQSI_s.o _fractUTQDI_s.o _fractUTQTI_s.o _fractUTQSF_s.o _fractUTQDF_s.o _fractUHAQQ_s.o _fractUHAHQ_s.o _fractUHASQ_s.o _fractUHADQ_s.o _fractUHATQ_s.o _fractUHAHA_s.o _fractUHASA_s.o _fractUHADA_s.o _fractUHATA_s.o _fractUHAUQQ_s.o _fractUHAUHQ_s.o _fractUHAUSQ_s.o _fractUHAUDQ_s.o _fractUHAUTQ_s.o _fractUHAUSA_s.o _fractUHAUDA_s.o _fractUHAUTA_s.o _fractUHAQI_s.o _fractUHAHI_s.o _fractUHASI_s.o _fractUHADI_s.o _fractUHATI_s.o _fractUHASF_s.o _fractUHADF_s.o _fractUSAQQ_s.o _fractUSAHQ_s.o _fractUSASQ_s.o _fractUSADQ_s.o _fractUSATQ_s.o _fractUSAHA_s.o _fractUSASA_s.o _fractUSADA_s.o _fractUSATA_s.o _fractUSAUQQ_s.o _fractUSAUHQ_s.o _fractUSAUSQ_s.o _fractUSAUDQ_s.o _fractUSAUTQ_s.o _fractUSAUHA_s.o _fractUSAUDA_s.o _fractUSAUTA_s.o _fractUSAQI_s.o _fractUSAHI_s.o _fractUSASI_s.o _fractUSADI_s.o _fractUSATI_s.o _fractUSASF_s.o _fractUSADF_s.o _fractUDAQQ_s.o _fractUDAHQ_s.o _fractUDASQ_s.o _fractUDADQ_s.o _fractUDATQ_s.o _fractUDAHA_s.o _fractUDASA_s.o _fractUDADA_s.o _fractUDATA_s.o _fractUDAUQQ_s.o _fractUDAUHQ_s.o _fractUDAUSQ_s.o _fractUDAUDQ_s.o _fractUDAUTQ_s.o _fractUDAUHA_s.o _fractUDAUSA_s.o _fractUDAUTA_s.o _fractUDAQI_s.o _fractUDAHI_s.o _fractUDASI_s.o _fractUDADI_s.o _fractUDATI_s.o _fractUDASF_s.o _fractUDADF_s.o _fractUTAQQ_s.o _fractUTAHQ_s.o _fractUTASQ_s.o _fractUTADQ_s.o _fractUTATQ_s.o _fractUTAHA_s.o _fractUTASA_s.o _fractUTADA_s.o _fractUTATA_s.o _fractUTAUQQ_s.o _fractUTAUHQ_s.o _fractUTAUSQ_s.o _fractUTAUDQ_s.o _fractUTAUTQ_s.o _fractUTAUHA_s.o _fractUTAUSA_s.o _fractUTAUDA_s.o _fractUTAQI_s.o _fractUTAHI_s.o _fractUTASI_s.o _fractUTADI_s.o _fractUTATI_s.o _fractUTASF_s.o _fractUTADF_s.o _fractQIQQ_s.o _fractQIHQ_s.o _fractQISQ_s.o _fractQIDQ_s.o _fractQITQ_s.o _fractQIHA_s.o _fractQISA_s.o _fractQIDA_s.o _fractQITA_s.o _fractQIUQQ_s.o _fractQIUHQ_s.o _fractQIUSQ_s.o _fractQIUDQ_s.o _fractQIUTQ_s.o _fractQIUHA_s.o _fractQIUSA_s.o _fractQIUDA_s.o _fractQIUTA_s.o _fractHIQQ_s.o _fractHIHQ_s.o _fractHISQ_s.o _fractHIDQ_s.o _fractHITQ_s.o _fractHIHA_s.o _fractHISA_s.o _fractHIDA_s.o _fractHITA_s.o _fractHIUQQ_s.o _fractHIUHQ_s.o _fractHIUSQ_s.o _fractHIUDQ_s.o _fractHIUTQ_s.o _fractHIUHA_s.o _fractHIUSA_s.o _fractHIUDA_s.o _fractHIUTA_s.o _fractSIQQ_s.o _fractSIHQ_s.o _fractSISQ_s.o _fractSIDQ_s.o _fractSITQ_s.o _fractSIHA_s.o _fractSISA_s.o _fractSIDA_s.o _fractSITA_s.o _fractSIUQQ_s.o _fractSIUHQ_s.o _fractSIUSQ_s.o _fractSIUDQ_s.o _fractSIUTQ_s.o _fractSIUHA_s.o _fractSIUSA_s.o _fractSIUDA_s.o _fractSIUTA_s.o _fractDIQQ_s.o _fractDIHQ_s.o _fractDISQ_s.o _fractDIDQ_s.o _fractDITQ_s.o _fractDIHA_s.o _fractDISA_s.o _fractDIDA_s.o _fractDITA_s.o _fractDIUQQ_s.o _fractDIUHQ_s.o _fractDIUSQ_s.o _fractDIUDQ_s.o _fractDIUTQ_s.o _fractDIUHA_s.o _fractDIUSA_s.o _fractDIUDA_s.o _fractDIUTA_s.o _fractTIQQ_s.o _fractTIHQ_s.o _fractTISQ_s.o _fractTIDQ_s.o _fractTITQ_s.o _fractTIHA_s.o _fractTISA_s.o _fractTIDA_s.o _fractTITA_s.o _fractTIUQQ_s.o _fractTIUHQ_s.o _fractTIUSQ_s.o _fractTIUDQ_s.o _fractTIUTQ_s.o _fractTIUHA_s.o _fractTIUSA_s.o _fractTIUDA_s.o _fractTIUTA_s.o _fractSFQQ_s.o _fractSFHQ_s.o _fractSFSQ_s.o _fractSFDQ_s.o _fractSFTQ_s.o _fractSFHA_s.o _fractSFSA_s.o _fractSFDA_s.o _fractSFTA_s.o _fractSFUQQ_s.o _fractSFUHQ_s.o _fractSFUSQ_s.o _fractSFUDQ_s.o _fractSFUTQ_s.o _fractSFUHA_s.o _fractSFUSA_s.o _fractSFUDA_s.o _fractSFUTA_s.o _fractDFQQ_s.o _fractDFHQ_s.o _fractDFSQ_s.o _fractDFDQ_s.o _fractDFTQ_s.o _fractDFHA_s.o _fractDFSA_s.o _fractDFDA_s.o _fractDFTA_s.o _fractDFUQQ_s.o _fractDFUHQ_s.o _fractDFUSQ_s.o _fractDFUDQ_s.o _fractDFUTQ_s.o _fractDFUHA_s.o _fractDFUSA_s.o _fractDFUDA_s.o _fractDFUTA_s.o _satfractQQHQ_s.o _satfractQQSQ_s.o _satfractQQDQ_s.o _satfractQQTQ_s.o _satfractQQHA_s.o _satfractQQSA_s.o _satfractQQDA_s.o _satfractQQTA_s.o _satfractQQUQQ_s.o _satfractQQUHQ_s.o _satfractQQUSQ_s.o _satfractQQUDQ_s.o _satfractQQUTQ_s.o _satfractQQUHA_s.o _satfractQQUSA_s.o _satfractQQUDA_s.o _satfractQQUTA_s.o _satfractHQQQ_s.o _satfractHQSQ_s.o _satfractHQDQ_s.o _satfractHQTQ_s.o _satfractHQHA_s.o _satfractHQSA_s.o _satfractHQDA_s.o _satfractHQTA_s.o _satfractHQUQQ_s.o _satfractHQUHQ_s.o _satfractHQUSQ_s.o _satfractHQUDQ_s.o _satfractHQUTQ_s.o _satfractHQUHA_s.o _satfractHQUSA_s.o _satfractHQUDA_s.o _satfractHQUTA_s.o _satfractSQQQ_s.o _satfractSQHQ_s.o _satfractSQDQ_s.o _satfractSQTQ_s.o _satfractSQHA_s.o _satfractSQSA_s.o _satfractSQDA_s.o _satfractSQTA_s.o _satfractSQUQQ_s.o _satfractSQUHQ_s.o _satfractSQUSQ_s.o _satfractSQUDQ_s.o _satfractSQUTQ_s.o _satfractSQUHA_s.o _satfractSQUSA_s.o _satfractSQUDA_s.o _satfractSQUTA_s.o _satfractDQQQ_s.o _satfractDQHQ_s.o _satfractDQSQ_s.o _satfractDQTQ_s.o _satfractDQHA_s.o _satfractDQSA_s.o _satfractDQDA_s.o _satfractDQTA_s.o _satfractDQUQQ_s.o _satfractDQUHQ_s.o _satfractDQUSQ_s.o _satfractDQUDQ_s.o _satfractDQUTQ_s.o _satfractDQUHA_s.o _satfractDQUSA_s.o _satfractDQUDA_s.o _satfractDQUTA_s.o _satfractTQQQ_s.o _satfractTQHQ_s.o _satfractTQSQ_s.o _satfractTQDQ_s.o _satfractTQHA_s.o _satfractTQSA_s.o _satfractTQDA_s.o _satfractTQTA_s.o _satfractTQUQQ_s.o _satfractTQUHQ_s.o _satfractTQUSQ_s.o _satfractTQUDQ_s.o _satfractTQUTQ_s.o _satfractTQUHA_s.o _satfractTQUSA_s.o _satfractTQUDA_s.o _satfractTQUTA_s.o _satfractHAQQ_s.o _satfractHAHQ_s.o _satfractHASQ_s.o _satfractHADQ_s.o _satfractHATQ_s.o _satfractHASA_s.o _satfractHADA_s.o _satfractHATA_s.o _satfractHAUQQ_s.o _satfractHAUHQ_s.o _satfractHAUSQ_s.o _satfractHAUDQ_s.o _satfractHAUTQ_s.o _satfractHAUHA_s.o _satfractHAUSA_s.o _satfractHAUDA_s.o _satfractHAUTA_s.o _satfractSAQQ_s.o _satfractSAHQ_s.o _satfractSASQ_s.o _satfractSADQ_s.o _satfractSATQ_s.o _satfractSAHA_s.o _satfractSADA_s.o _satfractSATA_s.o _satfractSAUQQ_s.o _satfractSAUHQ_s.o _satfractSAUSQ_s.o _satfractSAUDQ_s.o _satfractSAUTQ_s.o _satfractSAUHA_s.o _satfractSAUSA_s.o _satfractSAUDA_s.o _satfractSAUTA_s.o _satfractDAQQ_s.o _satfractDAHQ_s.o _satfractDASQ_s.o _satfractDADQ_s.o _satfractDATQ_s.o _satfractDAHA_s.o _satfractDASA_s.o _satfractDATA_s.o _satfractDAUQQ_s.o _satfractDAUHQ_s.o _satfractDAUSQ_s.o _satfractDAUDQ_s.o _satfractDAUTQ_s.o _satfractDAUHA_s.o _satfractDAUSA_s.o _satfractDAUDA_s.o _satfractDAUTA_s.o _satfractTAQQ_s.o _satfractTAHQ_s.o _satfractTASQ_s.o _satfractTADQ_s.o _satfractTATQ_s.o _satfractTAHA_s.o _satfractTASA_s.o _satfractTADA_s.o _satfractTAUQQ_s.o _satfractTAUHQ_s.o _satfractTAUSQ_s.o _satfractTAUDQ_s.o _satfractTAUTQ_s.o _satfractTAUHA_s.o _satfractTAUSA_s.o _satfractTAUDA_s.o _satfractTAUTA_s.o _satfractUQQQQ_s.o _satfractUQQHQ_s.o _satfractUQQSQ_s.o _satfractUQQDQ_s.o _satfractUQQTQ_s.o _satfractUQQHA_s.o _satfractUQQSA_s.o _satfractUQQDA_s.o _satfractUQQTA_s.o _satfractUQQUHQ_s.o _satfractUQQUSQ_s.o _satfractUQQUDQ_s.o _satfractUQQUTQ_s.o _satfractUQQUHA_s.o _satfractUQQUSA_s.o _satfractUQQUDA_s.o _satfractUQQUTA_s.o _satfractUHQQQ_s.o _satfractUHQHQ_s.o _satfractUHQSQ_s.o _satfractUHQDQ_s.o _satfractUHQTQ_s.o _satfractUHQHA_s.o _satfractUHQSA_s.o _satfractUHQDA_s.o _satfractUHQTA_s.o _satfractUHQUQQ_s.o _satfractUHQUSQ_s.o _satfractUHQUDQ_s.o _satfractUHQUTQ_s.o _satfractUHQUHA_s.o _satfractUHQUSA_s.o _satfractUHQUDA_s.o _satfractUHQUTA_s.o _satfractUSQQQ_s.o _satfractUSQHQ_s.o _satfractUSQSQ_s.o _satfractUSQDQ_s.o _satfractUSQTQ_s.o _satfractUSQHA_s.o _satfractUSQSA_s.o _satfractUSQDA_s.o _satfractUSQTA_s.o _satfractUSQUQQ_s.o _satfractUSQUHQ_s.o _satfractUSQUDQ_s.o _satfractUSQUTQ_s.o _satfractUSQUHA_s.o _satfractUSQUSA_s.o _satfractUSQUDA_s.o _satfractUSQUTA_s.o _satfractUDQQQ_s.o _satfractUDQHQ_s.o _satfractUDQSQ_s.o _satfractUDQDQ_s.o _satfractUDQTQ_s.o _satfractUDQHA_s.o _satfractUDQSA_s.o _satfractUDQDA_s.o _satfractUDQTA_s.o _satfractUDQUQQ_s.o _satfractUDQUHQ_s.o _satfractUDQUSQ_s.o _satfractUDQUTQ_s.o _satfractUDQUHA_s.o _satfractUDQUSA_s.o _satfractUDQUDA_s.o _satfractUDQUTA_s.o _satfractUTQQQ_s.o _satfractUTQHQ_s.o _satfractUTQSQ_s.o _satfractUTQDQ_s.o _satfractUTQTQ_s.o _satfractUTQHA_s.o _satfractUTQSA_s.o _satfractUTQDA_s.o _satfractUTQTA_s.o _satfractUTQUQQ_s.o _satfractUTQUHQ_s.o _satfractUTQUSQ_s.o _satfractUTQUDQ_s.o _satfractUTQUHA_s.o _satfractUTQUSA_s.o _satfractUTQUDA_s.o _satfractUTQUTA_s.o _satfractUHAQQ_s.o _satfractUHAHQ_s.o _satfractUHASQ_s.o _satfractUHADQ_s.o _satfractUHATQ_s.o _satfractUHAHA_s.o _satfractUHASA_s.o _satfractUHADA_s.o _satfractUHATA_s.o _satfractUHAUQQ_s.o _satfractUHAUHQ_s.o _satfractUHAUSQ_s.o _satfractUHAUDQ_s.o _satfractUHAUTQ_s.o _satfractUHAUSA_s.o _satfractUHAUDA_s.o _satfractUHAUTA_s.o _satfractUSAQQ_s.o _satfractUSAHQ_s.o _satfractUSASQ_s.o _satfractUSADQ_s.o _satfractUSATQ_s.o _satfractUSAHA_s.o _satfractUSASA_s.o _satfractUSADA_s.o _satfractUSATA_s.o _satfractUSAUQQ_s.o _satfractUSAUHQ_s.o _satfractUSAUSQ_s.o _satfractUSAUDQ_s.o _satfractUSAUTQ_s.o _satfractUSAUHA_s.o _satfractUSAUDA_s.o _satfractUSAUTA_s.o _satfractUDAQQ_s.o _satfractUDAHQ_s.o _satfractUDASQ_s.o _satfractUDADQ_s.o _satfractUDATQ_s.o _satfractUDAHA_s.o _satfractUDASA_s.o _satfractUDADA_s.o _satfractUDATA_s.o _satfractUDAUQQ_s.o _satfractUDAUHQ_s.o _satfractUDAUSQ_s.o _satfractUDAUDQ_s.o _satfractUDAUTQ_s.o _satfractUDAUHA_s.o _satfractUDAUSA_s.o _satfractUDAUTA_s.o _satfractUTAQQ_s.o _satfractUTAHQ_s.o _satfractUTASQ_s.o _satfractUTADQ_s.o _satfractUTATQ_s.o _satfractUTAHA_s.o _satfractUTASA_s.o _satfractUTADA_s.o _satfractUTATA_s.o _satfractUTAUQQ_s.o _satfractUTAUHQ_s.o _satfractUTAUSQ_s.o _satfractUTAUDQ_s.o _satfractUTAUTQ_s.o _satfractUTAUHA_s.o _satfractUTAUSA_s.o _satfractUTAUDA_s.o _satfractQIQQ_s.o _satfractQIHQ_s.o _satfractQISQ_s.o _satfractQIDQ_s.o _satfractQITQ_s.o _satfractQIHA_s.o _satfractQISA_s.o _satfractQIDA_s.o _satfractQITA_s.o _satfractQIUQQ_s.o _satfractQIUHQ_s.o _satfractQIUSQ_s.o _satfractQIUDQ_s.o _satfractQIUTQ_s.o _satfractQIUHA_s.o _satfractQIUSA_s.o _satfractQIUDA_s.o _satfractQIUTA_s.o _satfractHIQQ_s.o _satfractHIHQ_s.o _satfractHISQ_s.o _satfractHIDQ_s.o _satfractHITQ_s.o _satfractHIHA_s.o _satfractHISA_s.o _satfractHIDA_s.o _satfractHITA_s.o _satfractHIUQQ_s.o _satfractHIUHQ_s.o _satfractHIUSQ_s.o _satfractHIUDQ_s.o _satfractHIUTQ_s.o _satfractHIUHA_s.o _satfractHIUSA_s.o _satfractHIUDA_s.o _satfractHIUTA_s.o _satfractSIQQ_s.o _satfractSIHQ_s.o _satfractSISQ_s.o _satfractSIDQ_s.o _satfractSITQ_s.o _satfractSIHA_s.o _satfractSISA_s.o _satfractSIDA_s.o _satfractSITA_s.o _satfractSIUQQ_s.o _satfractSIUHQ_s.o _satfractSIUSQ_s.o _satfractSIUDQ_s.o _satfractSIUTQ_s.o _satfractSIUHA_s.o _satfractSIUSA_s.o _satfractSIUDA_s.o _satfractSIUTA_s.o _satfractDIQQ_s.o _satfractDIHQ_s.o _satfractDISQ_s.o _satfractDIDQ_s.o _satfractDITQ_s.o _satfractDIHA_s.o _satfractDISA_s.o _satfractDIDA_s.o _satfractDITA_s.o _satfractDIUQQ_s.o _satfractDIUHQ_s.o _satfractDIUSQ_s.o _satfractDIUDQ_s.o _satfractDIUTQ_s.o _satfractDIUHA_s.o _satfractDIUSA_s.o _satfractDIUDA_s.o _satfractDIUTA_s.o _satfractTIQQ_s.o _satfractTIHQ_s.o _satfractTISQ_s.o _satfractTIDQ_s.o _satfractTITQ_s.o _satfractTIHA_s.o _satfractTISA_s.o _satfractTIDA_s.o _satfractTITA_s.o _satfractTIUQQ_s.o _satfractTIUHQ_s.o _satfractTIUSQ_s.o _satfractTIUDQ_s.o _satfractTIUTQ_s.o _satfractTIUHA_s.o _satfractTIUSA_s.o _satfractTIUDA_s.o _satfractTIUTA_s.o _satfractSFQQ_s.o _satfractSFHQ_s.o _satfractSFSQ_s.o _satfractSFDQ_s.o _satfractSFTQ_s.o _satfractSFHA_s.o _satfractSFSA_s.o _satfractSFDA_s.o _satfractSFTA_s.o _satfractSFUQQ_s.o _satfractSFUHQ_s.o _satfractSFUSQ_s.o _satfractSFUDQ_s.o _satfractSFUTQ_s.o _satfractSFUHA_s.o _satfractSFUSA_s.o _satfractSFUDA_s.o _satfractSFUTA_s.o _satfractDFQQ_s.o _satfractDFHQ_s.o _satfractDFSQ_s.o _satfractDFDQ_s.o _satfractDFTQ_s.o _satfractDFHA_s.o _satfractDFSA_s.o _satfractDFDA_s.o _satfractDFTA_s.o _satfractDFUQQ_s.o _satfractDFUHQ_s.o _satfractDFUSQ_s.o _satfractDFUDQ_s.o _satfractDFUTQ_s.o _satfractDFUHA_s.o _satfractDFUSA_s.o _satfractDFUDA_s.o _satfractDFUTA_s.o _fractunsQQUQI_s.o _fractunsQQUHI_s.o _fractunsQQUSI_s.o _fractunsQQUDI_s.o _fractunsQQUTI_s.o _fractunsHQUQI_s.o _fractunsHQUHI_s.o _fractunsHQUSI_s.o _fractunsHQUDI_s.o _fractunsHQUTI_s.o _fractunsSQUQI_s.o _fractunsSQUHI_s.o _fractunsSQUSI_s.o _fractunsSQUDI_s.o _fractunsSQUTI_s.o _fractunsDQUQI_s.o _fractunsDQUHI_s.o _fractunsDQUSI_s.o _fractunsDQUDI_s.o _fractunsDQUTI_s.o _fractunsTQUQI_s.o _fractunsTQUHI_s.o _fractunsTQUSI_s.o _fractunsTQUDI_s.o _fractunsTQUTI_s.o _fractunsHAUQI_s.o _fractunsHAUHI_s.o _fractunsHAUSI_s.o _fractunsHAUDI_s.o _fractunsHAUTI_s.o _fractunsSAUQI_s.o _fractunsSAUHI_s.o _fractunsSAUSI_s.o _fractunsSAUDI_s.o _fractunsSAUTI_s.o _fractunsDAUQI_s.o _fractunsDAUHI_s.o _fractunsDAUSI_s.o _fractunsDAUDI_s.o _fractunsDAUTI_s.o _fractunsTAUQI_s.o _fractunsTAUHI_s.o _fractunsTAUSI_s.o _fractunsTAUDI_s.o _fractunsTAUTI_s.o _fractunsUQQUQI_s.o _fractunsUQQUHI_s.o _fractunsUQQUSI_s.o _fractunsUQQUDI_s.o _fractunsUQQUTI_s.o _fractunsUHQUQI_s.o _fractunsUHQUHI_s.o _fractunsUHQUSI_s.o _fractunsUHQUDI_s.o _fractunsUHQUTI_s.o _fractunsUSQUQI_s.o _fractunsUSQUHI_s.o _fractunsUSQUSI_s.o _fractunsUSQUDI_s.o _fractunsUSQUTI_s.o _fractunsUDQUQI_s.o _fractunsUDQUHI_s.o _fractunsUDQUSI_s.o _fractunsUDQUDI_s.o _fractunsUDQUTI_s.o _fractunsUTQUQI_s.o _fractunsUTQUHI_s.o _fractunsUTQUSI_s.o _fractunsUTQUDI_s.o _fractunsUTQUTI_s.o _fractunsUHAUQI_s.o _fractunsUHAUHI_s.o _fractunsUHAUSI_s.o _fractunsUHAUDI_s.o _fractunsUHAUTI_s.o _fractunsUSAUQI_s.o _fractunsUSAUHI_s.o _fractunsUSAUSI_s.o _fractunsUSAUDI_s.o _fractunsUSAUTI_s.o _fractunsUDAUQI_s.o _fractunsUDAUHI_s.o _fractunsUDAUSI_s.o _fractunsUDAUDI_s.o _fractunsUDAUTI_s.o _fractunsUTAUQI_s.o _fractunsUTAUHI_s.o _fractunsUTAUSI_s.o _fractunsUTAUDI_s.o _fractunsUTAUTI_s.o _fractunsUQIQQ_s.o _fractunsUQIHQ_s.o _fractunsUQISQ_s.o _fractunsUQIDQ_s.o _fractunsUQITQ_s.o _fractunsUQIHA_s.o _fractunsUQISA_s.o _fractunsUQIDA_s.o _fractunsUQITA_s.o _fractunsUQIUQQ_s.o _fractunsUQIUHQ_s.o _fractunsUQIUSQ_s.o _fractunsUQIUDQ_s.o _fractunsUQIUTQ_s.o _fractunsUQIUHA_s.o _fractunsUQIUSA_s.o _fractunsUQIUDA_s.o _fractunsUQIUTA_s.o _fractunsUHIQQ_s.o _fractunsUHIHQ_s.o _fractunsUHISQ_s.o _fractunsUHIDQ_s.o _fractunsUHITQ_s.o _fractunsUHIHA_s.o _fractunsUHISA_s.o _fractunsUHIDA_s.o _fractunsUHITA_s.o _fractunsUHIUQQ_s.o _fractunsUHIUHQ_s.o _fractunsUHIUSQ_s.o _fractunsUHIUDQ_s.o _fractunsUHIUTQ_s.o _fractunsUHIUHA_s.o _fractunsUHIUSA_s.o _fractunsUHIUDA_s.o _fractunsUHIUTA_s.o _fractunsUSIQQ_s.o _fractunsUSIHQ_s.o _fractunsUSISQ_s.o _fractunsUSIDQ_s.o _fractunsUSITQ_s.o _fractunsUSIHA_s.o _fractunsUSISA_s.o _fractunsUSIDA_s.o _fractunsUSITA_s.o _fractunsUSIUQQ_s.o _fractunsUSIUHQ_s.o _fractunsUSIUSQ_s.o _fractunsUSIUDQ_s.o _fractunsUSIUTQ_s.o _fractunsUSIUHA_s.o _fractunsUSIUSA_s.o _fractunsUSIUDA_s.o _fractunsUSIUTA_s.o _fractunsUDIQQ_s.o _fractunsUDIHQ_s.o _fractunsUDISQ_s.o _fractunsUDIDQ_s.o _fractunsUDITQ_s.o _fractunsUDIHA_s.o _fractunsUDISA_s.o _fractunsUDIDA_s.o _fractunsUDITA_s.o _fractunsUDIUQQ_s.o _fractunsUDIUHQ_s.o _fractunsUDIUSQ_s.o _fractunsUDIUDQ_s.o _fractunsUDIUTQ_s.o _fractunsUDIUHA_s.o _fractunsUDIUSA_s.o _fractunsUDIUDA_s.o _fractunsUDIUTA_s.o _fractunsUTIQQ_s.o _fractunsUTIHQ_s.o _fractunsUTISQ_s.o _fractunsUTIDQ_s.o _fractunsUTITQ_s.o _fractunsUTIHA_s.o _fractunsUTISA_s.o _fractunsUTIDA_s.o _fractunsUTITA_s.o _fractunsUTIUQQ_s.o _fractunsUTIUHQ_s.o _fractunsUTIUSQ_s.o _fractunsUTIUDQ_s.o _fractunsUTIUTQ_s.o _fractunsUTIUHA_s.o _fractunsUTIUSA_s.o _fractunsUTIUDA_s.o _fractunsUTIUTA_s.o _satfractunsUQIQQ_s.o _satfractunsUQIHQ_s.o _satfractunsUQISQ_s.o _satfractunsUQIDQ_s.o _satfractunsUQITQ_s.o _satfractunsUQIHA_s.o _satfractunsUQISA_s.o _satfractunsUQIDA_s.o _satfractunsUQITA_s.o _satfractunsUQIUQQ_s.o _satfractunsUQIUHQ_s.o _satfractunsUQIUSQ_s.o _satfractunsUQIUDQ_s.o _satfractunsUQIUTQ_s.o _satfractunsUQIUHA_s.o _satfractunsUQIUSA_s.o _satfractunsUQIUDA_s.o _satfractunsUQIUTA_s.o _satfractunsUHIQQ_s.o _satfractunsUHIHQ_s.o _satfractunsUHISQ_s.o _satfractunsUHIDQ_s.o _satfractunsUHITQ_s.o _satfractunsUHIHA_s.o _satfractunsUHISA_s.o _satfractunsUHIDA_s.o _satfractunsUHITA_s.o _satfractunsUHIUQQ_s.o _satfractunsUHIUHQ_s.o _satfractunsUHIUSQ_s.o _satfractunsUHIUDQ_s.o _satfractunsUHIUTQ_s.o _satfractunsUHIUHA_s.o _satfractunsUHIUSA_s.o _satfractunsUHIUDA_s.o _satfractunsUHIUTA_s.o _satfractunsUSIQQ_s.o _satfractunsUSIHQ_s.o _satfractunsUSISQ_s.o _satfractunsUSIDQ_s.o _satfractunsUSITQ_s.o _satfractunsUSIHA_s.o _satfractunsUSISA_s.o _satfractunsUSIDA_s.o _satfractunsUSITA_s.o _satfractunsUSIUQQ_s.o _satfractunsUSIUHQ_s.o _satfractunsUSIUSQ_s.o _satfractunsUSIUDQ_s.o _satfractunsUSIUTQ_s.o _satfractunsUSIUHA_s.o _satfractunsUSIUSA_s.o _satfractunsUSIUDA_s.o _satfractunsUSIUTA_s.o _satfractunsUDIQQ_s.o _satfractunsUDIHQ_s.o _satfractunsUDISQ_s.o _satfractunsUDIDQ_s.o _satfractunsUDITQ_s.o _satfractunsUDIHA_s.o _satfractunsUDISA_s.o _satfractunsUDIDA_s.o _satfractunsUDITA_s.o _satfractunsUDIUQQ_s.o _satfractunsUDIUHQ_s.o _satfractunsUDIUSQ_s.o _satfractunsUDIUDQ_s.o _satfractunsUDIUTQ_s.o _satfractunsUDIUHA_s.o _satfractunsUDIUSA_s.o _satfractunsUDIUDA_s.o _satfractunsUDIUTA_s.o _satfractunsUTIQQ_s.o _satfractunsUTIHQ_s.o _satfractunsUTISQ_s.o _satfractunsUTIDQ_s.o _satfractunsUTITQ_s.o _satfractunsUTIHA_s.o _satfractunsUTISA_s.o _satfractunsUTIDA_s.o _satfractunsUTITA_s.o _satfractunsUTIUQQ_s.o _satfractunsUTIUHQ_s.o _satfractunsUTIUSQ_s.o _satfractunsUTIUDQ_s.o _satfractunsUTIUTQ_s.o _satfractunsUTIUHA_s.o _satfractunsUTIUSA_s.o _satfractunsUTIUDA_s.o _satfractunsUTIUTA_s.o bpabi_s.o unaligned-funcs_s.o addsf3_s.o divsf3_s.o eqsf2_s.o gesf2_s.o lesf2_s.o mulsf3_s.o negsf2_s.o subsf3_s.o unordsf2_s.o fixsfsi_s.o floatsisf_s.o floatunsisf_s.o adddf3_s.o divdf3_s.o eqdf2_s.o gedf2_s.o ledf2_s.o muldf3_s.o negdf2_s.o subdf3_s.o unorddf2_s.o fixdfsi_s.o floatsidf_s.o floatunsidf_s.o extendsfdf2_s.o truncdfsf2_s.o enable-execute-stack_s.o unwind-arm_s.o libunwind_s.o pr-support_s.o unwind-c_s.o emutls_s.o libgcc.a -lc -v && rm -f ./libgcc_s.so && if [ -f ./libgcc_s.so.1 ]; then mv -f ./libgcc_s.so.1 ./libgcc_s.so.1.backup; else true; fi && mv ./libgcc_s.so.1.tmp ./libgcc_s.so.1 && (echo "/* GNU ld script"; echo "   Use the shared library, but some functions are only in"; echo "   the static library.  */"; echo "GROUP ( libgcc_s.so.1 -lgcc )" ) > ./libgcc_s.so


OBJS="_thumb1_case_shi_s.o _thumb1_case_uhi_s.o _thumb1_case_si_s.o _udivsi3_s.o _divsi3_s.o _umodsi3_s.o _modsi3_s.o _bb_init_func_s.o _call_via_rX_s.o _interwork_call_via_rX_s.o _lshrdi3_s.o _ashrdi3_s.o _ashldi3_s.o _arm_negdf2_s.o _arm_addsubdf3_s.o _arm_muldivdf3_s.o _arm_cmpdf2_s.o _arm_unorddf2_s.o _arm_fixdfsi_s.o _arm_fixunsdfsi_s.o _arm_truncdfsf2_s.o _arm_negsf2_s.o _arm_addsubsf3_s.o _arm_muldivsf3_s.o _arm_cmpsf2_s.o _arm_unordsf2_s.o _arm_fixsfsi_s.o _arm_fixunssfsi_s.o _arm_floatdidf_s.o _arm_floatdisf_s.o _arm_floatundidf_s.o _arm_floatundisf_s.o _clzsi2_s.o _clzdi2_s.o _ctzsi2_s.o _aeabi_lcmp_s.o _aeabi_ulcmp_s.o _aeabi_ldivmod_s.o _aeabi_uldivmod_s.o _dvmd_lnx_s.o _clear_cache_s.o _muldi3_s.o _negdi2_s.o _cmpdi2_s.o _ucmpdi2_s.o _trampoline_s.o __main_s.o _absvsi2_s.o _absvdi2_s.o _addvsi3_s.o _addvdi3_s.o _subvsi3_s.o _subvdi3_s.o _mulvsi3_s.o _mulvdi3_s.o _negvsi2_s.o _negvdi2_s.o _ctors_s.o _ffssi2_s.o _ffsdi2_s.o _clz_s.o _ctzdi2_s.o _popcount_tab_s.o _popcountsi2_s.o _popcountdi2_s.o _paritysi2_s.o _paritydi2_s.o _powisf2_s.o _powidf2_s.o _powixf2_s.o _powitf2_s.o _mulsc3_s.o _muldc3_s.o _mulxc3_s.o _multc3_s.o _divsc3_s.o _divdc3_s.o _divxc3_s.o _divtc3_s.o _bswapsi2_s.o _bswapdi2_s.o _clrsbsi2_s.o _clrsbdi2_s.o _fixunssfsi_s.o _fixunsdfsi_s.o _fixunsxfsi_s.o _fixsfdi_s.o _fixdfdi_s.o _fixxfdi_s.o _fixtfdi_s.o _fixunssfdi_s.o _fixunsdfdi_s.o _fixunsxfdi_s.o _fixunstfdi_s.o _floatdisf_s.o _floatdidf_s.o _floatdixf_s.o _floatditf_s.o _floatundisf_s.o _floatundidf_s.o _floatundixf_s.o _floatunditf_s.o _divdi3_s.o _moddi3_s.o _udivdi3_s.o _umoddi3_s.o _udiv_w_sdiv_s.o _udivmoddi4_s.o _addQQ_s.o _addHQ_s.o _addSQ_s.o _addDQ_s.o _addTQ_s.o _addHA_s.o _addSA_s.o _addDA_s.o _addTA_s.o _addUQQ_s.o _addUHQ_s.o _addUSQ_s.o _addUDQ_s.o _addUTQ_s.o _addUHA_s.o _addUSA_s.o _addUDA_s.o _addUTA_s.o _subQQ_s.o _subHQ_s.o _subSQ_s.o _subDQ_s.o _subTQ_s.o _subHA_s.o _subSA_s.o _subDA_s.o _subTA_s.o _subUQQ_s.o _subUHQ_s.o _subUSQ_s.o _subUDQ_s.o _subUTQ_s.o _subUHA_s.o _subUSA_s.o _subUDA_s.o _subUTA_s.o _negQQ_s.o _negHQ_s.o _negSQ_s.o _negDQ_s.o _negTQ_s.o _negHA_s.o _negSA_s.o _negDA_s.o _negTA_s.o _negUQQ_s.o _negUHQ_s.o _negUSQ_s.o _negUDQ_s.o _negUTQ_s.o _negUHA_s.o _negUSA_s.o _negUDA_s.o _negUTA_s.o _mulQQ_s.o _mulHQ_s.o _mulSQ_s.o _mulDQ_s.o _mulTQ_s.o _mulHA_s.o _mulSA_s.o _mulDA_s.o _mulTA_s.o _mulUQQ_s.o _mulUHQ_s.o _mulUSQ_s.o _mulUDQ_s.o _mulUTQ_s.o _mulUHA_s.o _mulUSA_s.o _mulUDA_s.o _mulUTA_s.o _mulhelperQQ_s.o _mulhelperHQ_s.o _mulhelperSQ_s.o _mulhelperDQ_s.o _mulhelperTQ_s.o _mulhelperHA_s.o _mulhelperSA_s.o _mulhelperDA_s.o _mulhelperTA_s.o _mulhelperUQQ_s.o _mulhelperUHQ_s.o _mulhelperUSQ_s.o _mulhelperUDQ_s.o _mulhelperUTQ_s.o _mulhelperUHA_s.o _mulhelperUSA_s.o _mulhelperUDA_s.o _mulhelperUTA_s.o _divhelperQQ_s.o _divhelperHQ_s.o _divhelperSQ_s.o _divhelperDQ_s.o _divhelperTQ_s.o _divhelperHA_s.o _divhelperSA_s.o _divhelperDA_s.o _divhelperTA_s.o _divhelperUQQ_s.o _divhelperUHQ_s.o _divhelperUSQ_s.o _divhelperUDQ_s.o _divhelperUTQ_s.o _divhelperUHA_s.o _divhelperUSA_s.o _divhelperUDA_s.o _divhelperUTA_s.o _ashlQQ_s.o _ashlHQ_s.o _ashlSQ_s.o _ashlDQ_s.o _ashlTQ_s.o _ashlHA_s.o _ashlSA_s.o _ashlDA_s.o _ashlTA_s.o _ashlUQQ_s.o _ashlUHQ_s.o _ashlUSQ_s.o _ashlUDQ_s.o _ashlUTQ_s.o _ashlUHA_s.o _ashlUSA_s.o _ashlUDA_s.o _ashlUTA_s.o _ashlhelperQQ_s.o _ashlhelperHQ_s.o _ashlhelperSQ_s.o _ashlhelperDQ_s.o _ashlhelperTQ_s.o _ashlhelperHA_s.o _ashlhelperSA_s.o _ashlhelperDA_s.o _ashlhelperTA_s.o _ashlhelperUQQ_s.o _ashlhelperUHQ_s.o _ashlhelperUSQ_s.o _ashlhelperUDQ_s.o _ashlhelperUTQ_s.o _ashlhelperUHA_s.o _ashlhelperUSA_s.o _ashlhelperUDA_s.o _ashlhelperUTA_s.o _cmpQQ_s.o _cmpHQ_s.o _cmpSQ_s.o _cmpDQ_s.o _cmpTQ_s.o _cmpHA_s.o _cmpSA_s.o _cmpDA_s.o _cmpTA_s.o _cmpUQQ_s.o _cmpUHQ_s.o _cmpUSQ_s.o _cmpUDQ_s.o _cmpUTQ_s.o _cmpUHA_s.o _cmpUSA_s.o _cmpUDA_s.o _cmpUTA_s.o _saturate1QQ_s.o _saturate1HQ_s.o _saturate1SQ_s.o _saturate1DQ_s.o _saturate1TQ_s.o _saturate1HA_s.o _saturate1SA_s.o _saturate1DA_s.o _saturate1TA_s.o _saturate1UQQ_s.o _saturate1UHQ_s.o _saturate1USQ_s.o _saturate1UDQ_s.o _saturate1UTQ_s.o _saturate1UHA_s.o _saturate1USA_s.o _saturate1UDA_s.o _saturate1UTA_s.o _saturate2QQ_s.o _saturate2HQ_s.o _saturate2SQ_s.o _saturate2DQ_s.o _saturate2TQ_s.o _saturate2HA_s.o _saturate2SA_s.o _saturate2DA_s.o _saturate2TA_s.o _saturate2UQQ_s.o _saturate2UHQ_s.o _saturate2USQ_s.o _saturate2UDQ_s.o _saturate2UTQ_s.o _saturate2UHA_s.o _saturate2USA_s.o _saturate2UDA_s.o _saturate2UTA_s.o _ssaddQQ_s.o _ssaddHQ_s.o _ssaddSQ_s.o _ssaddDQ_s.o _ssaddTQ_s.o _ssaddHA_s.o _ssaddSA_s.o _ssaddDA_s.o _ssaddTA_s.o _sssubQQ_s.o _sssubHQ_s.o _sssubSQ_s.o _sssubDQ_s.o _sssubTQ_s.o _sssubHA_s.o _sssubSA_s.o _sssubDA_s.o _sssubTA_s.o _ssnegQQ_s.o _ssnegHQ_s.o _ssnegSQ_s.o _ssnegDQ_s.o _ssnegTQ_s.o _ssnegHA_s.o _ssnegSA_s.o _ssnegDA_s.o _ssnegTA_s.o _ssmulQQ_s.o _ssmulHQ_s.o _ssmulSQ_s.o _ssmulDQ_s.o _ssmulTQ_s.o _ssmulHA_s.o _ssmulSA_s.o _ssmulDA_s.o _ssmulTA_s.o _ssdivQQ_s.o _ssdivHQ_s.o _ssdivSQ_s.o _ssdivDQ_s.o _ssdivTQ_s.o _ssdivHA_s.o _ssdivSA_s.o _ssdivDA_s.o _ssdivTA_s.o _divQQ_s.o _divHQ_s.o _divSQ_s.o _divDQ_s.o _divTQ_s.o _divHA_s.o _divSA_s.o _divDA_s.o _divTA_s.o _ssashlQQ_s.o _ssashlHQ_s.o _ssashlSQ_s.o _ssashlDQ_s.o _ssashlTQ_s.o _ssashlHA_s.o _ssashlSA_s.o _ssashlDA_s.o _ssashlTA_s.o _ashrQQ_s.o _ashrHQ_s.o _ashrSQ_s.o _ashrDQ_s.o _ashrTQ_s.o _ashrHA_s.o _ashrSA_s.o _ashrDA_s.o _ashrTA_s.o _usaddUQQ_s.o _usaddUHQ_s.o _usaddUSQ_s.o _usaddUDQ_s.o _usaddUTQ_s.o _usaddUHA_s.o _usaddUSA_s.o _usaddUDA_s.o _usaddUTA_s.o _ussubUQQ_s.o _ussubUHQ_s.o _ussubUSQ_s.o _ussubUDQ_s.o _ussubUTQ_s.o _ussubUHA_s.o _ussubUSA_s.o _ussubUDA_s.o _ussubUTA_s.o _usnegUQQ_s.o _usnegUHQ_s.o _usnegUSQ_s.o _usnegUDQ_s.o _usnegUTQ_s.o _usnegUHA_s.o _usnegUSA_s.o _usnegUDA_s.o _usnegUTA_s.o _usmulUQQ_s.o _usmulUHQ_s.o _usmulUSQ_s.o _usmulUDQ_s.o _usmulUTQ_s.o _usmulUHA_s.o _usmulUSA_s.o _usmulUDA_s.o _usmulUTA_s.o _usdivUQQ_s.o _usdivUHQ_s.o _usdivUSQ_s.o _usdivUDQ_s.o _usdivUTQ_s.o _usdivUHA_s.o _usdivUSA_s.o _usdivUDA_s.o _usdivUTA_s.o _udivUQQ_s.o _udivUHQ_s.o _udivUSQ_s.o _udivUDQ_s.o _udivUTQ_s.o _udivUHA_s.o _udivUSA_s.o _udivUDA_s.o _udivUTA_s.o _usashlUQQ_s.o _usashlUHQ_s.o _usashlUSQ_s.o _usashlUDQ_s.o _usashlUTQ_s.o _usashlUHA_s.o _usashlUSA_s.o _usashlUDA_s.o _usashlUTA_s.o _lshrUQQ_s.o _lshrUHQ_s.o _lshrUSQ_s.o _lshrUDQ_s.o _lshrUTQ_s.o _lshrUHA_s.o _lshrUSA_s.o _lshrUDA_s.o _lshrUTA_s.o _fractQQHQ_s.o _fractQQSQ_s.o _fractQQDQ_s.o _fractQQTQ_s.o _fractQQHA_s.o _fractQQSA_s.o _fractQQDA_s.o _fractQQTA_s.o _fractQQUQQ_s.o _fractQQUHQ_s.o _fractQQUSQ_s.o _fractQQUDQ_s.o _fractQQUTQ_s.o _fractQQUHA_s.o _fractQQUSA_s.o _fractQQUDA_s.o _fractQQUTA_s.o _fractQQQI_s.o _fractQQHI_s.o _fractQQSI_s.o _fractQQDI_s.o _fractQQTI_s.o _fractQQSF_s.o _fractQQDF_s.o _fractHQQQ_s.o _fractHQSQ_s.o _fractHQDQ_s.o _fractHQTQ_s.o _fractHQHA_s.o _fractHQSA_s.o _fractHQDA_s.o _fractHQTA_s.o _fractHQUQQ_s.o _fractHQUHQ_s.o _fractHQUSQ_s.o _fractHQUDQ_s.o _fractHQUTQ_s.o _fractHQUHA_s.o _fractHQUSA_s.o _fractHQUDA_s.o _fractHQUTA_s.o _fractHQQI_s.o _fractHQHI_s.o _fractHQSI_s.o _fractHQDI_s.o _fractHQTI_s.o _fractHQSF_s.o _fractHQDF_s.o _fractSQQQ_s.o _fractSQHQ_s.o _fractSQDQ_s.o _fractSQTQ_s.o _fractSQHA_s.o _fractSQSA_s.o _fractSQDA_s.o _fractSQTA_s.o _fractSQUQQ_s.o _fractSQUHQ_s.o _fractSQUSQ_s.o _fractSQUDQ_s.o _fractSQUTQ_s.o _fractSQUHA_s.o _fractSQUSA_s.o _fractSQUDA_s.o _fractSQUTA_s.o _fractSQQI_s.o _fractSQHI_s.o _fractSQSI_s.o _fractSQDI_s.o _fractSQTI_s.o _fractSQSF_s.o _fractSQDF_s.o _fractDQQQ_s.o _fractDQHQ_s.o _fractDQSQ_s.o _fractDQTQ_s.o _fractDQHA_s.o _fractDQSA_s.o _fractDQDA_s.o _fractDQTA_s.o _fractDQUQQ_s.o _fractDQUHQ_s.o _fractDQUSQ_s.o _fractDQUDQ_s.o _fractDQUTQ_s.o _fractDQUHA_s.o _fractDQUSA_s.o _fractDQUDA_s.o _fractDQUTA_s.o _fractDQQI_s.o _fractDQHI_s.o _fractDQSI_s.o _fractDQDI_s.o _fractDQTI_s.o _fractDQSF_s.o _fractDQDF_s.o _fractTQQQ_s.o _fractTQHQ_s.o _fractTQSQ_s.o _fractTQDQ_s.o _fractTQHA_s.o _fractTQSA_s.o _fractTQDA_s.o _fractTQTA_s.o _fractTQUQQ_s.o _fractTQUHQ_s.o _fractTQUSQ_s.o _fractTQUDQ_s.o _fractTQUTQ_s.o _fractTQUHA_s.o _fractTQUSA_s.o _fractTQUDA_s.o _fractTQUTA_s.o _fractTQQI_s.o _fractTQHI_s.o _fractTQSI_s.o _fractTQDI_s.o _fractTQTI_s.o _fractTQSF_s.o _fractTQDF_s.o _fractHAQQ_s.o _fractHAHQ_s.o _fractHASQ_s.o _fractHADQ_s.o _fractHATQ_s.o _fractHASA_s.o _fractHADA_s.o _fractHATA_s.o _fractHAUQQ_s.o _fractHAUHQ_s.o _fractHAUSQ_s.o _fractHAUDQ_s.o _fractHAUTQ_s.o _fractHAUHA_s.o _fractHAUSA_s.o _fractHAUDA_s.o _fractHAUTA_s.o _fractHAQI_s.o _fractHAHI_s.o _fractHASI_s.o _fractHADI_s.o _fractHATI_s.o _fractHASF_s.o _fractHADF_s.o _fractSAQQ_s.o _fractSAHQ_s.o _fractSASQ_s.o _fractSADQ_s.o _fractSATQ_s.o _fractSAHA_s.o _fractSADA_s.o _fractSATA_s.o _fractSAUQQ_s.o _fractSAUHQ_s.o _fractSAUSQ_s.o _fractSAUDQ_s.o _fractSAUTQ_s.o _fractSAUHA_s.o _fractSAUSA_s.o _fractSAUDA_s.o _fractSAUTA_s.o _fractSAQI_s.o _fractSAHI_s.o _fractSASI_s.o _fractSADI_s.o _fractSATI_s.o _fractSASF_s.o _fractSADF_s.o _fractDAQQ_s.o _fractDAHQ_s.o _fractDASQ_s.o _fractDADQ_s.o _fractDATQ_s.o _fractDAHA_s.o _fractDASA_s.o _fractDATA_s.o _fractDAUQQ_s.o _fractDAUHQ_s.o _fractDAUSQ_s.o _fractDAUDQ_s.o _fractDAUTQ_s.o _fractDAUHA_s.o _fractDAUSA_s.o _fractDAUDA_s.o _fractDAUTA_s.o _fractDAQI_s.o _fractDAHI_s.o _fractDASI_s.o _fractDADI_s.o _fractDATI_s.o _fractDASF_s.o _fractDADF_s.o _fractTAQQ_s.o _fractTAHQ_s.o _fractTASQ_s.o _fractTADQ_s.o _fractTATQ_s.o _fractTAHA_s.o _fractTASA_s.o _fractTADA_s.o _fractTAUQQ_s.o _fractTAUHQ_s.o _fractTAUSQ_s.o _fractTAUDQ_s.o _fractTAUTQ_s.o _fractTAUHA_s.o _fractTAUSA_s.o _fractTAUDA_s.o _fractTAUTA_s.o _fractTAQI_s.o _fractTAHI_s.o _fractTASI_s.o _fractTADI_s.o _fractTATI_s.o _fractTASF_s.o _fractTADF_s.o _fractUQQQQ_s.o _fractUQQHQ_s.o _fractUQQSQ_s.o _fractUQQDQ_s.o _fractUQQTQ_s.o _fractUQQHA_s.o _fractUQQSA_s.o _fractUQQDA_s.o _fractUQQTA_s.o _fractUQQUHQ_s.o _fractUQQUSQ_s.o _fractUQQUDQ_s.o _fractUQQUTQ_s.o _fractUQQUHA_s.o _fractUQQUSA_s.o _fractUQQUDA_s.o _fractUQQUTA_s.o _fractUQQQI_s.o _fractUQQHI_s.o _fractUQQSI_s.o _fractUQQDI_s.o _fractUQQTI_s.o _fractUQQSF_s.o _fractUQQDF_s.o _fractUHQQQ_s.o _fractUHQHQ_s.o _fractUHQSQ_s.o _fractUHQDQ_s.o _fractUHQTQ_s.o _fractUHQHA_s.o _fractUHQSA_s.o _fractUHQDA_s.o _fractUHQTA_s.o _fractUHQUQQ_s.o _fractUHQUSQ_s.o _fractUHQUDQ_s.o _fractUHQUTQ_s.o _fractUHQUHA_s.o _fractUHQUSA_s.o _fractUHQUDA_s.o _fractUHQUTA_s.o _fractUHQQI_s.o _fractUHQHI_s.o _fractUHQSI_s.o _fractUHQDI_s.o _fractUHQTI_s.o _fractUHQSF_s.o _fractUHQDF_s.o _fractUSQQQ_s.o _fractUSQHQ_s.o _fractUSQSQ_s.o _fractUSQDQ_s.o _fractUSQTQ_s.o _fractUSQHA_s.o _fractUSQSA_s.o _fractUSQDA_s.o _fractUSQTA_s.o _fractUSQUQQ_s.o _fractUSQUHQ_s.o _fractUSQUDQ_s.o _fractUSQUTQ_s.o _fractUSQUHA_s.o _fractUSQUSA_s.o _fractUSQUDA_s.o _fractUSQUTA_s.o _fractUSQQI_s.o _fractUSQHI_s.o _fractUSQSI_s.o _fractUSQDI_s.o _fractUSQTI_s.o _fractUSQSF_s.o _fractUSQDF_s.o _fractUDQQQ_s.o _fractUDQHQ_s.o _fractUDQSQ_s.o _fractUDQDQ_s.o _fractUDQTQ_s.o _fractUDQHA_s.o _fractUDQSA_s.o _fractUDQDA_s.o _fractUDQTA_s.o _fractUDQUQQ_s.o _fractUDQUHQ_s.o _fractUDQUSQ_s.o _fractUDQUTQ_s.o _fractUDQUHA_s.o _fractUDQUSA_s.o _fractUDQUDA_s.o _fractUDQUTA_s.o _fractUDQQI_s.o _fractUDQHI_s.o _fractUDQSI_s.o _fractUDQDI_s.o _fractUDQTI_s.o _fractUDQSF_s.o _fractUDQDF_s.o _fractUTQQQ_s.o _fractUTQHQ_s.o _fractUTQSQ_s.o _fractUTQDQ_s.o _fractUTQTQ_s.o _fractUTQHA_s.o _fractUTQSA_s.o _fractUTQDA_s.o _fractUTQTA_s.o _fractUTQUQQ_s.o _fractUTQUHQ_s.o _fractUTQUSQ_s.o _fractUTQUDQ_s.o _fractUTQUHA_s.o _fractUTQUSA_s.o _fractUTQUDA_s.o _fractUTQUTA_s.o _fractUTQQI_s.o _fractUTQHI_s.o _fractUTQSI_s.o _fractUTQDI_s.o _fractUTQTI_s.o _fractUTQSF_s.o _fractUTQDF_s.o _fractUHAQQ_s.o _fractUHAHQ_s.o _fractUHASQ_s.o _fractUHADQ_s.o _fractUHATQ_s.o _fractUHAHA_s.o _fractUHASA_s.o _fractUHADA_s.o _fractUHATA_s.o _fractUHAUQQ_s.o _fractUHAUHQ_s.o _fractUHAUSQ_s.o _fractUHAUDQ_s.o _fractUHAUTQ_s.o _fractUHAUSA_s.o _fractUHAUDA_s.o _fractUHAUTA_s.o _fractUHAQI_s.o _fractUHAHI_s.o _fractUHASI_s.o _fractUHADI_s.o _fractUHATI_s.o _fractUHASF_s.o _fractUHADF_s.o _fractUSAQQ_s.o _fractUSAHQ_s.o _fractUSASQ_s.o _fractUSADQ_s.o _fractUSATQ_s.o _fractUSAHA_s.o _fractUSASA_s.o _fractUSADA_s.o _fractUSATA_s.o _fractUSAUQQ_s.o _fractUSAUHQ_s.o _fractUSAUSQ_s.o _fractUSAUDQ_s.o _fractUSAUTQ_s.o _fractUSAUHA_s.o _fractUSAUDA_s.o _fractUSAUTA_s.o _fractUSAQI_s.o _fractUSAHI_s.o _fractUSASI_s.o _fractUSADI_s.o _fractUSATI_s.o _fractUSASF_s.o _fractUSADF_s.o _fractUDAQQ_s.o _fractUDAHQ_s.o _fractUDASQ_s.o _fractUDADQ_s.o _fractUDATQ_s.o _fractUDAHA_s.o _fractUDASA_s.o _fractUDADA_s.o _fractUDATA_s.o _fractUDAUQQ_s.o _fractUDAUHQ_s.o _fractUDAUSQ_s.o _fractUDAUDQ_s.o _fractUDAUTQ_s.o _fractUDAUHA_s.o _fractUDAUSA_s.o _fractUDAUTA_s.o _fractUDAQI_s.o _fractUDAHI_s.o _fractUDASI_s.o _fractUDADI_s.o _fractUDATI_s.o _fractUDASF_s.o _fractUDADF_s.o _fractUTAQQ_s.o _fractUTAHQ_s.o _fractUTASQ_s.o _fractUTADQ_s.o _fractUTATQ_s.o _fractUTAHA_s.o _fractUTASA_s.o _fractUTADA_s.o _fractUTATA_s.o _fractUTAUQQ_s.o _fractUTAUHQ_s.o _fractUTAUSQ_s.o _fractUTAUDQ_s.o _fractUTAUTQ_s.o _fractUTAUHA_s.o _fractUTAUSA_s.o _fractUTAUDA_s.o _fractUTAQI_s.o _fractUTAHI_s.o _fractUTASI_s.o _fractUTADI_s.o _fractUTATI_s.o _fractUTASF_s.o _fractUTADF_s.o _fractQIQQ_s.o _fractQIHQ_s.o _fractQISQ_s.o _fractQIDQ_s.o _fractQITQ_s.o _fractQIHA_s.o _fractQISA_s.o _fractQIDA_s.o _fractQITA_s.o _fractQIUQQ_s.o _fractQIUHQ_s.o _fractQIUSQ_s.o _fractQIUDQ_s.o _fractQIUTQ_s.o _fractQIUHA_s.o _fractQIUSA_s.o _fractQIUDA_s.o _fractQIUTA_s.o _fractHIQQ_s.o _fractHIHQ_s.o _fractHISQ_s.o _fractHIDQ_s.o _fractHITQ_s.o _fractHIHA_s.o _fractHISA_s.o _fractHIDA_s.o _fractHITA_s.o _fractHIUQQ_s.o _fractHIUHQ_s.o _fractHIUSQ_s.o _fractHIUDQ_s.o _fractHIUTQ_s.o _fractHIUHA_s.o _fractHIUSA_s.o _fractHIUDA_s.o _fractHIUTA_s.o _fractSIQQ_s.o _fractSIHQ_s.o _fractSISQ_s.o _fractSIDQ_s.o _fractSITQ_s.o _fractSIHA_s.o _fractSISA_s.o _fractSIDA_s.o _fractSITA_s.o _fractSIUQQ_s.o _fractSIUHQ_s.o _fractSIUSQ_s.o _fractSIUDQ_s.o _fractSIUTQ_s.o _fractSIUHA_s.o _fractSIUSA_s.o _fractSIUDA_s.o _fractSIUTA_s.o _fractDIQQ_s.o _fractDIHQ_s.o _fractDISQ_s.o _fractDIDQ_s.o _fractDITQ_s.o _fractDIHA_s.o _fractDISA_s.o _fractDIDA_s.o _fractDITA_s.o _fractDIUQQ_s.o _fractDIUHQ_s.o _fractDIUSQ_s.o _fractDIUDQ_s.o _fractDIUTQ_s.o _fractDIUHA_s.o _fractDIUSA_s.o _fractDIUDA_s.o _fractDIUTA_s.o _fractTIQQ_s.o _fractTIHQ_s.o _fractTISQ_s.o _fractTIDQ_s.o _fractTITQ_s.o _fractTIHA_s.o _fractTISA_s.o _fractTIDA_s.o _fractTITA_s.o _fractTIUQQ_s.o _fractTIUHQ_s.o _fractTIUSQ_s.o _fractTIUDQ_s.o _fractTIUTQ_s.o _fractTIUHA_s.o _fractTIUSA_s.o _fractTIUDA_s.o _fractTIUTA_s.o _fractSFQQ_s.o _fractSFHQ_s.o _fractSFSQ_s.o _fractSFDQ_s.o _fractSFTQ_s.o _fractSFHA_s.o _fractSFSA_s.o _fractSFDA_s.o _fractSFTA_s.o _fractSFUQQ_s.o _fractSFUHQ_s.o _fractSFUSQ_s.o _fractSFUDQ_s.o _fractSFUTQ_s.o _fractSFUHA_s.o _fractSFUSA_s.o _fractSFUDA_s.o _fractSFUTA_s.o _fractDFQQ_s.o _fractDFHQ_s.o _fractDFSQ_s.o _fractDFDQ_s.o _fractDFTQ_s.o _fractDFHA_s.o _fractDFSA_s.o _fractDFDA_s.o _fractDFTA_s.o _fractDFUQQ_s.o _fractDFUHQ_s.o _fractDFUSQ_s.o _fractDFUDQ_s.o _fractDFUTQ_s.o _fractDFUHA_s.o _fractDFUSA_s.o _fractDFUDA_s.o _fractDFUTA_s.o _satfractQQHQ_s.o _satfractQQSQ_s.o _satfractQQDQ_s.o _satfractQQTQ_s.o _satfractQQHA_s.o _satfractQQSA_s.o _satfractQQDA_s.o _satfractQQTA_s.o _satfractQQUQQ_s.o _satfractQQUHQ_s.o _satfractQQUSQ_s.o _satfractQQUDQ_s.o _satfractQQUTQ_s.o _satfractQQUHA_s.o _satfractQQUSA_s.o _satfractQQUDA_s.o _satfractQQUTA_s.o _satfractHQQQ_s.o _satfractHQSQ_s.o _satfractHQDQ_s.o _satfractHQTQ_s.o _satfractHQHA_s.o _satfractHQSA_s.o _satfractHQDA_s.o _satfractHQTA_s.o _satfractHQUQQ_s.o _satfractHQUHQ_s.o _satfractHQUSQ_s.o _satfractHQUDQ_s.o _satfractHQUTQ_s.o _satfractHQUHA_s.o _satfractHQUSA_s.o _satfractHQUDA_s.o _satfractHQUTA_s.o _satfractSQQQ_s.o _satfractSQHQ_s.o _satfractSQDQ_s.o _satfractSQTQ_s.o _satfractSQHA_s.o _satfractSQSA_s.o _satfractSQDA_s.o _satfractSQTA_s.o _satfractSQUQQ_s.o _satfractSQUHQ_s.o _satfractSQUSQ_s.o _satfractSQUDQ_s.o _satfractSQUTQ_s.o _satfractSQUHA_s.o _satfractSQUSA_s.o _satfractSQUDA_s.o _satfractSQUTA_s.o _satfractDQQQ_s.o _satfractDQHQ_s.o _satfractDQSQ_s.o _satfractDQTQ_s.o _satfractDQHA_s.o _satfractDQSA_s.o _satfractDQDA_s.o _satfractDQTA_s.o _satfractDQUQQ_s.o _satfractDQUHQ_s.o _satfractDQUSQ_s.o _satfractDQUDQ_s.o _satfractDQUTQ_s.o _satfractDQUHA_s.o _satfractDQUSA_s.o _satfractDQUDA_s.o _satfractDQUTA_s.o _satfractTQQQ_s.o _satfractTQHQ_s.o _satfractTQSQ_s.o _satfractTQDQ_s.o _satfractTQHA_s.o _satfractTQSA_s.o _satfractTQDA_s.o _satfractTQTA_s.o _satfractTQUQQ_s.o _satfractTQUHQ_s.o _satfractTQUSQ_s.o _satfractTQUDQ_s.o _satfractTQUTQ_s.o _satfractTQUHA_s.o _satfractTQUSA_s.o _satfractTQUDA_s.o _satfractTQUTA_s.o _satfractHAQQ_s.o _satfractHAHQ_s.o _satfractHASQ_s.o _satfractHADQ_s.o _satfractHATQ_s.o _satfractHASA_s.o _satfractHADA_s.o _satfractHATA_s.o _satfractHAUQQ_s.o _satfractHAUHQ_s.o _satfractHAUSQ_s.o _satfractHAUDQ_s.o _satfractHAUTQ_s.o _satfractHAUHA_s.o _satfractHAUSA_s.o _satfractHAUDA_s.o _satfractHAUTA_s.o _satfractSAQQ_s.o _satfractSAHQ_s.o _satfractSASQ_s.o _satfractSADQ_s.o _satfractSATQ_s.o _satfractSAHA_s.o _satfractSADA_s.o _satfractSATA_s.o _satfractSAUQQ_s.o _satfractSAUHQ_s.o _satfractSAUSQ_s.o _satfractSAUDQ_s.o _satfractSAUTQ_s.o _satfractSAUHA_s.o _satfractSAUSA_s.o _satfractSAUDA_s.o _satfractSAUTA_s.o _satfractDAQQ_s.o _satfractDAHQ_s.o _satfractDASQ_s.o _satfractDADQ_s.o _satfractDATQ_s.o _satfractDAHA_s.o _satfractDASA_s.o _satfractDATA_s.o _satfractDAUQQ_s.o _satfractDAUHQ_s.o _satfractDAUSQ_s.o _satfractDAUDQ_s.o _satfractDAUTQ_s.o _satfractDAUHA_s.o _satfractDAUSA_s.o _satfractDAUDA_s.o _satfractDAUTA_s.o _satfractTAQQ_s.o _satfractTAHQ_s.o _satfractTASQ_s.o _satfractTADQ_s.o _satfractTATQ_s.o _satfractTAHA_s.o _satfractTASA_s.o _satfractTADA_s.o _satfractTAUQQ_s.o _satfractTAUHQ_s.o _satfractTAUSQ_s.o _satfractTAUDQ_s.o _satfractTAUTQ_s.o _satfractTAUHA_s.o _satfractTAUSA_s.o _satfractTAUDA_s.o _satfractTAUTA_s.o _satfractUQQQQ_s.o _satfractUQQHQ_s.o _satfractUQQSQ_s.o _satfractUQQDQ_s.o _satfractUQQTQ_s.o _satfractUQQHA_s.o _satfractUQQSA_s.o _satfractUQQDA_s.o _satfractUQQTA_s.o _satfractUQQUHQ_s.o _satfractUQQUSQ_s.o _satfractUQQUDQ_s.o _satfractUQQUTQ_s.o _satfractUQQUHA_s.o _satfractUQQUSA_s.o _satfractUQQUDA_s.o _satfractUQQUTA_s.o _satfractUHQQQ_s.o _satfractUHQHQ_s.o _satfractUHQSQ_s.o _satfractUHQDQ_s.o _satfractUHQTQ_s.o _satfractUHQHA_s.o _satfractUHQSA_s.o _satfractUHQDA_s.o _satfractUHQTA_s.o _satfractUHQUQQ_s.o _satfractUHQUSQ_s.o _satfractUHQUDQ_s.o _satfractUHQUTQ_s.o _satfractUHQUHA_s.o _satfractUHQUSA_s.o _satfractUHQUDA_s.o _satfractUHQUTA_s.o _satfractUSQQQ_s.o _satfractUSQHQ_s.o _satfractUSQSQ_s.o _satfractUSQDQ_s.o _satfractUSQTQ_s.o _satfractUSQHA_s.o _satfractUSQSA_s.o _satfractUSQDA_s.o _satfractUSQTA_s.o _satfractUSQUQQ_s.o _satfractUSQUHQ_s.o _satfractUSQUDQ_s.o _satfractUSQUTQ_s.o _satfractUSQUHA_s.o _satfractUSQUSA_s.o _satfractUSQUDA_s.o _satfractUSQUTA_s.o _satfractUDQQQ_s.o _satfractUDQHQ_s.o _satfractUDQSQ_s.o _satfractUDQDQ_s.o _satfractUDQTQ_s.o _satfractUDQHA_s.o _satfractUDQSA_s.o _satfractUDQDA_s.o _satfractUDQTA_s.o _satfractUDQUQQ_s.o _satfractUDQUHQ_s.o _satfractUDQUSQ_s.o _satfractUDQUTQ_s.o _satfractUDQUHA_s.o _satfractUDQUSA_s.o _satfractUDQUDA_s.o _satfractUDQUTA_s.o _satfractUTQQQ_s.o _satfractUTQHQ_s.o _satfractUTQSQ_s.o _satfractUTQDQ_s.o _satfractUTQTQ_s.o _satfractUTQHA_s.o _satfractUTQSA_s.o _satfractUTQDA_s.o _satfractUTQTA_s.o _satfractUTQUQQ_s.o _satfractUTQUHQ_s.o _satfractUTQUSQ_s.o _satfractUTQUDQ_s.o _satfractUTQUHA_s.o _satfractUTQUSA_s.o _satfractUTQUDA_s.o _satfractUTQUTA_s.o _satfractUHAQQ_s.o _satfractUHAHQ_s.o _satfractUHASQ_s.o _satfractUHADQ_s.o _satfractUHATQ_s.o _satfractUHAHA_s.o _satfractUHASA_s.o _satfractUHADA_s.o _satfractUHATA_s.o _satfractUHAUQQ_s.o _satfractUHAUHQ_s.o _satfractUHAUSQ_s.o _satfractUHAUDQ_s.o _satfractUHAUTQ_s.o _satfractUHAUSA_s.o _satfractUHAUDA_s.o _satfractUHAUTA_s.o _satfractUSAQQ_s.o _satfractUSAHQ_s.o _satfractUSASQ_s.o _satfractUSADQ_s.o _satfractUSATQ_s.o _satfractUSAHA_s.o _satfractUSASA_s.o _satfractUSADA_s.o _satfractUSATA_s.o _satfractUSAUQQ_s.o _satfractUSAUHQ_s.o _satfractUSAUSQ_s.o _satfractUSAUDQ_s.o _satfractUSAUTQ_s.o _satfractUSAUHA_s.o _satfractUSAUDA_s.o _satfractUSAUTA_s.o _satfractUDAQQ_s.o _satfractUDAHQ_s.o _satfractUDASQ_s.o _satfractUDADQ_s.o _satfractUDATQ_s.o _satfractUDAHA_s.o _satfractUDASA_s.o _satfractUDADA_s.o _satfractUDATA_s.o _satfractUDAUQQ_s.o _satfractUDAUHQ_s.o _satfractUDAUSQ_s.o _satfractUDAUDQ_s.o _satfractUDAUTQ_s.o _satfractUDAUHA_s.o _satfractUDAUSA_s.o _satfractUDAUTA_s.o _satfractUTAQQ_s.o _satfractUTAHQ_s.o _satfractUTASQ_s.o _satfractUTADQ_s.o _satfractUTATQ_s.o _satfractUTAHA_s.o _satfractUTASA_s.o _satfractUTADA_s.o _satfractUTATA_s.o _satfractUTAUQQ_s.o _satfractUTAUHQ_s.o _satfractUTAUSQ_s.o _satfractUTAUDQ_s.o _satfractUTAUTQ_s.o _satfractUTAUHA_s.o _satfractUTAUSA_s.o _satfractUTAUDA_s.o _satfractQIQQ_s.o _satfractQIHQ_s.o _satfractQISQ_s.o _satfractQIDQ_s.o _satfractQITQ_s.o _satfractQIHA_s.o _satfractQISA_s.o _satfractQIDA_s.o _satfractQITA_s.o _satfractQIUQQ_s.o _satfractQIUHQ_s.o _satfractQIUSQ_s.o _satfractQIUDQ_s.o _satfractQIUTQ_s.o _satfractQIUHA_s.o _satfractQIUSA_s.o _satfractQIUDA_s.o _satfractQIUTA_s.o _satfractHIQQ_s.o _satfractHIHQ_s.o _satfractHISQ_s.o _satfractHIDQ_s.o _satfractHITQ_s.o _satfractHIHA_s.o _satfractHISA_s.o _satfractHIDA_s.o _satfractHITA_s.o _satfractHIUQQ_s.o _satfractHIUHQ_s.o _satfractHIUSQ_s.o _satfractHIUDQ_s.o _satfractHIUTQ_s.o _satfractHIUHA_s.o _satfractHIUSA_s.o _satfractHIUDA_s.o _satfractHIUTA_s.o _satfractSIQQ_s.o _satfractSIHQ_s.o _satfractSISQ_s.o _satfractSIDQ_s.o _satfractSITQ_s.o _satfractSIHA_s.o _satfractSISA_s.o _satfractSIDA_s.o _satfractSITA_s.o _satfractSIUQQ_s.o _satfractSIUHQ_s.o _satfractSIUSQ_s.o _satfractSIUDQ_s.o _satfractSIUTQ_s.o _satfractSIUHA_s.o _satfractSIUSA_s.o _satfractSIUDA_s.o _satfractSIUTA_s.o _satfractDIQQ_s.o _satfractDIHQ_s.o _satfractDISQ_s.o _satfractDIDQ_s.o _satfractDITQ_s.o _satfractDIHA_s.o _satfractDISA_s.o _satfractDIDA_s.o _satfractDITA_s.o _satfractDIUQQ_s.o _satfractDIUHQ_s.o _satfractDIUSQ_s.o _satfractDIUDQ_s.o _satfractDIUTQ_s.o _satfractDIUHA_s.o _satfractDIUSA_s.o _satfractDIUDA_s.o _satfractDIUTA_s.o _satfractTIQQ_s.o _satfractTIHQ_s.o _satfractTISQ_s.o _satfractTIDQ_s.o _satfractTITQ_s.o _satfractTIHA_s.o _satfractTISA_s.o _satfractTIDA_s.o _satfractTITA_s.o _satfractTIUQQ_s.o _satfractTIUHQ_s.o _satfractTIUSQ_s.o _satfractTIUDQ_s.o _satfractTIUTQ_s.o _satfractTIUHA_s.o _satfractTIUSA_s.o _satfractTIUDA_s.o _satfractTIUTA_s.o _satfractSFQQ_s.o _satfractSFHQ_s.o _satfractSFSQ_s.o _satfractSFDQ_s.o _satfractSFTQ_s.o _satfractSFHA_s.o _satfractSFSA_s.o _satfractSFDA_s.o _satfractSFTA_s.o _satfractSFUQQ_s.o _satfractSFUHQ_s.o _satfractSFUSQ_s.o _satfractSFUDQ_s.o _satfractSFUTQ_s.o _satfractSFUHA_s.o _satfractSFUSA_s.o _satfractSFUDA_s.o _satfractSFUTA_s.o _satfractDFQQ_s.o _satfractDFHQ_s.o _satfractDFSQ_s.o _satfractDFDQ_s.o _satfractDFTQ_s.o _satfractDFHA_s.o _satfractDFSA_s.o _satfractDFDA_s.o _satfractDFTA_s.o _satfractDFUQQ_s.o _satfractDFUHQ_s.o _satfractDFUSQ_s.o _satfractDFUDQ_s.o _satfractDFUTQ_s.o _satfractDFUHA_s.o _satfractDFUSA_s.o _satfractDFUDA_s.o _satfractDFUTA_s.o _fractunsQQUQI_s.o _fractunsQQUHI_s.o _fractunsQQUSI_s.o _fractunsQQUDI_s.o _fractunsQQUTI_s.o _fractunsHQUQI_s.o _fractunsHQUHI_s.o _fractunsHQUSI_s.o _fractunsHQUDI_s.o _fractunsHQUTI_s.o _fractunsSQUQI_s.o _fractunsSQUHI_s.o _fractunsSQUSI_s.o _fractunsSQUDI_s.o _fractunsSQUTI_s.o _fractunsDQUQI_s.o _fractunsDQUHI_s.o _fractunsDQUSI_s.o _fractunsDQUDI_s.o _fractunsDQUTI_s.o _fractunsTQUQI_s.o _fractunsTQUHI_s.o _fractunsTQUSI_s.o _fractunsTQUDI_s.o _fractunsTQUTI_s.o _fractunsHAUQI_s.o _fractunsHAUHI_s.o _fractunsHAUSI_s.o _fractunsHAUDI_s.o _fractunsHAUTI_s.o _fractunsSAUQI_s.o _fractunsSAUHI_s.o _fractunsSAUSI_s.o _fractunsSAUDI_s.o _fractunsSAUTI_s.o _fractunsDAUQI_s.o _fractunsDAUHI_s.o _fractunsDAUSI_s.o _fractunsDAUDI_s.o _fractunsDAUTI_s.o _fractunsTAUQI_s.o _fractunsTAUHI_s.o _fractunsTAUSI_s.o _fractunsTAUDI_s.o _fractunsTAUTI_s.o _fractunsUQQUQI_s.o _fractunsUQQUHI_s.o _fractunsUQQUSI_s.o _fractunsUQQUDI_s.o _fractunsUQQUTI_s.o _fractunsUHQUQI_s.o _fractunsUHQUHI_s.o _fractunsUHQUSI_s.o _fractunsUHQUDI_s.o _fractunsUHQUTI_s.o _fractunsUSQUQI_s.o _fractunsUSQUHI_s.o _fractunsUSQUSI_s.o _fractunsUSQUDI_s.o _fractunsUSQUTI_s.o _fractunsUDQUQI_s.o _fractunsUDQUHI_s.o _fractunsUDQUSI_s.o _fractunsUDQUDI_s.o _fractunsUDQUTI_s.o _fractunsUTQUQI_s.o _fractunsUTQUHI_s.o _fractunsUTQUSI_s.o _fractunsUTQUDI_s.o _fractunsUTQUTI_s.o _fractunsUHAUQI_s.o _fractunsUHAUHI_s.o _fractunsUHAUSI_s.o _fractunsUHAUDI_s.o _fractunsUHAUTI_s.o _fractunsUSAUQI_s.o _fractunsUSAUHI_s.o _fractunsUSAUSI_s.o _fractunsUSAUDI_s.o _fractunsUSAUTI_s.o _fractunsUDAUQI_s.o _fractunsUDAUHI_s.o _fractunsUDAUSI_s.o _fractunsUDAUDI_s.o _fractunsUDAUTI_s.o _fractunsUTAUQI_s.o _fractunsUTAUHI_s.o _fractunsUTAUSI_s.o _fractunsUTAUDI_s.o _fractunsUTAUTI_s.o _fractunsUQIQQ_s.o _fractunsUQIHQ_s.o _fractunsUQISQ_s.o _fractunsUQIDQ_s.o _fractunsUQITQ_s.o _fractunsUQIHA_s.o _fractunsUQISA_s.o _fractunsUQIDA_s.o _fractunsUQITA_s.o _fractunsUQIUQQ_s.o _fractunsUQIUHQ_s.o _fractunsUQIUSQ_s.o _fractunsUQIUDQ_s.o _fractunsUQIUTQ_s.o _fractunsUQIUHA_s.o _fractunsUQIUSA_s.o _fractunsUQIUDA_s.o _fractunsUQIUTA_s.o _fractunsUHIQQ_s.o _fractunsUHIHQ_s.o _fractunsUHISQ_s.o _fractunsUHIDQ_s.o _fractunsUHITQ_s.o _fractunsUHIHA_s.o _fractunsUHISA_s.o _fractunsUHIDA_s.o _fractunsUHITA_s.o _fractunsUHIUQQ_s.o _fractunsUHIUHQ_s.o _fractunsUHIUSQ_s.o _fractunsUHIUDQ_s.o _fractunsUHIUTQ_s.o _fractunsUHIUHA_s.o _fractunsUHIUSA_s.o _fractunsUHIUDA_s.o _fractunsUHIUTA_s.o _fractunsUSIQQ_s.o _fractunsUSIHQ_s.o _fractunsUSISQ_s.o _fractunsUSIDQ_s.o _fractunsUSITQ_s.o _fractunsUSIHA_s.o _fractunsUSISA_s.o _fractunsUSIDA_s.o _fractunsUSITA_s.o _fractunsUSIUQQ_s.o _fractunsUSIUHQ_s.o _fractunsUSIUSQ_s.o _fractunsUSIUDQ_s.o _fractunsUSIUTQ_s.o _fractunsUSIUHA_s.o _fractunsUSIUSA_s.o _fractunsUSIUDA_s.o _fractunsUSIUTA_s.o _fractunsUDIQQ_s.o _fractunsUDIHQ_s.o _fractunsUDISQ_s.o _fractunsUDIDQ_s.o _fractunsUDITQ_s.o _fractunsUDIHA_s.o _fractunsUDISA_s.o _fractunsUDIDA_s.o _fractunsUDITA_s.o _fractunsUDIUQQ_s.o _fractunsUDIUHQ_s.o _fractunsUDIUSQ_s.o _fractunsUDIUDQ_s.o _fractunsUDIUTQ_s.o _fractunsUDIUHA_s.o _fractunsUDIUSA_s.o _fractunsUDIUDA_s.o _fractunsUDIUTA_s.o _fractunsUTIQQ_s.o _fractunsUTIHQ_s.o _fractunsUTISQ_s.o _fractunsUTIDQ_s.o _fractunsUTITQ_s.o _fractunsUTIHA_s.o _fractunsUTISA_s.o _fractunsUTIDA_s.o _fractunsUTITA_s.o _fractunsUTIUQQ_s.o _fractunsUTIUHQ_s.o _fractunsUTIUSQ_s.o _fractunsUTIUDQ_s.o _fractunsUTIUTQ_s.o _fractunsUTIUHA_s.o _fractunsUTIUSA_s.o _fractunsUTIUDA_s.o _fractunsUTIUTA_s.o _satfractunsUQIQQ_s.o _satfractunsUQIHQ_s.o _satfractunsUQISQ_s.o _satfractunsUQIDQ_s.o _satfractunsUQITQ_s.o _satfractunsUQIHA_s.o _satfractunsUQISA_s.o _satfractunsUQIDA_s.o _satfractunsUQITA_s.o _satfractunsUQIUQQ_s.o _satfractunsUQIUHQ_s.o _satfractunsUQIUSQ_s.o _satfractunsUQIUDQ_s.o _satfractunsUQIUTQ_s.o _satfractunsUQIUHA_s.o _satfractunsUQIUSA_s.o _satfractunsUQIUDA_s.o _satfractunsUQIUTA_s.o _satfractunsUHIQQ_s.o _satfractunsUHIHQ_s.o _satfractunsUHISQ_s.o _satfractunsUHIDQ_s.o _satfractunsUHITQ_s.o _satfractunsUHIHA_s.o _satfractunsUHISA_s.o _satfractunsUHIDA_s.o _satfractunsUHITA_s.o _satfractunsUHIUQQ_s.o _satfractunsUHIUHQ_s.o _satfractunsUHIUSQ_s.o _satfractunsUHIUDQ_s.o _satfractunsUHIUTQ_s.o _satfractunsUHIUHA_s.o _satfractunsUHIUSA_s.o _satfractunsUHIUDA_s.o _satfractunsUHIUTA_s.o _satfractunsUSIQQ_s.o _satfractunsUSIHQ_s.o _satfractunsUSISQ_s.o _satfractunsUSIDQ_s.o _satfractunsUSITQ_s.o _satfractunsUSIHA_s.o _satfractunsUSISA_s.o _satfractunsUSIDA_s.o _satfractunsUSITA_s.o _satfractunsUSIUQQ_s.o _satfractunsUSIUHQ_s.o _satfractunsUSIUSQ_s.o _satfractunsUSIUDQ_s.o _satfractunsUSIUTQ_s.o _satfractunsUSIUHA_s.o _satfractunsUSIUSA_s.o _satfractunsUSIUDA_s.o _satfractunsUSIUTA_s.o _satfractunsUDIQQ_s.o _satfractunsUDIHQ_s.o _satfractunsUDISQ_s.o _satfractunsUDIDQ_s.o _satfractunsUDITQ_s.o _satfractunsUDIHA_s.o _satfractunsUDISA_s.o _satfractunsUDIDA_s.o _satfractunsUDITA_s.o _satfractunsUDIUQQ_s.o _satfractunsUDIUHQ_s.o _satfractunsUDIUSQ_s.o _satfractunsUDIUDQ_s.o _satfractunsUDIUTQ_s.o _satfractunsUDIUHA_s.o _satfractunsUDIUSA_s.o _satfractunsUDIUDA_s.o _satfractunsUDIUTA_s.o _satfractunsUTIQQ_s.o _satfractunsUTIHQ_s.o _satfractunsUTISQ_s.o _satfractunsUTIDQ_s.o _satfractunsUTITQ_s.o _satfractunsUTIHA_s.o _satfractunsUTISA_s.o _satfractunsUTIDA_s.o _satfractunsUTITA_s.o _satfractunsUTIUQQ_s.o _satfractunsUTIUHQ_s.o _satfractunsUTIUSQ_s.o _satfractunsUTIUDQ_s.o _satfractunsUTIUTQ_s.o _satfractunsUTIUHA_s.o _satfractunsUTIUSA_s.o _satfractunsUTIUDA_s.o _satfractunsUTIUTA_s.o bpabi_s.o unaligned-funcs_s.o addsf3_s.o divsf3_s.o eqsf2_s.o gesf2_s.o lesf2_s.o mulsf3_s.o negsf2_s.o subsf3_s.o unordsf2_s.o fixsfsi_s.o floatsisf_s.o floatunsisf_s.o adddf3_s.o divdf3_s.o eqdf2_s.o gedf2_s.o ledf2_s.o muldf3_s.o negdf2_s.o subdf3_s.o unorddf2_s.o fixdfsi_s.o floatsidf_s.o floatunsidf_s.o extendsfdf2_s.o truncdfsf2_s.o enable-execute-stack_s.o unwind-arm_s.o libunwind_s.o pr-support_s.o unwind-c_s.o emutls_s.o"
OBJS="_thumb1_case_shi_s.o _thumb1_case_uhi_s.o _thumb1_case_si_s.o _udivsi3_s.o _divsi3_s.o _umodsi3_s.o _modsi3_s.o _bb_init_func_s.o _call_via_rX_s.o _interwork_call_via_rX_s.o _lshrdi3_s.o _ashrdi3_s.o _ashldi3_s.o _arm_negdf2_s.o _arm_addsubdf3_s.o _arm_muldivdf3_s.o _arm_cmpdf2_s.o _arm_unorddf2_s.o _arm_fixdfsi_s.o _arm_fixunsdfsi_s.o _arm_truncdfsf2_s.o _arm_negsf2_s.o _arm_addsubsf3_s.o _arm_muldivsf3_s.o _arm_cmpsf2_s.o _arm_unordsf2_s.o _arm_fixsfsi_s.o _arm_fixunssfsi_s.o _arm_floatdidf_s.o _arm_floatdisf_s.o _arm_floatundidf_s.o _arm_floatundisf_s.o _clzsi2_s.o _clzdi2_s.o _ctzsi2_s.o _aeabi_lcmp_s.o _aeabi_ulcmp_s.o _aeabi_ldivmod_s.o _aeabi_uldivmod_s.o _dvmd_lnx_s.o _clear_cache_s.o _muldi3_s.o _negdi2_s.o _cmpdi2_s.o _ucmpdi2_s.o _trampoline_s.o __main_s.o _absvsi2_s.o _absvdi2_s.o _addvsi3_s.o _addvdi3_s.o _subvsi3_s.o _subvdi3_s.o _mulvsi3_s.o _mulvdi3_s.o _negvsi2_s.o _negvdi2_s.o _ctors_s.o _ffssi2_s.o _ffsdi2_s.o _clz_s.o _ctzdi2_s.o _popcount_tab_s.o _popcountsi2_s.o _popcountdi2_s.o _paritysi2_s.o _paritydi2_s.o _powisf2_s.o _powidf2_s.o _powixf2_s.o _powitf2_s.o _mulsc3_s.o _muldc3_s.o _mulxc3_s.o _multc3_s.o _divsc3_s.o _divdc3_s.o _divxc3_s.o _divtc3_s.o _bswapsi2_s.o _bswapdi2_s.o _clrsbsi2_s.o _clrsbdi2_s.o _fixunssfsi_s.o _fixunsdfsi_s.o _fixunsxfsi_s.o _fixsfdi_s.o _fixdfdi_s.o _fixxfdi_s.o _fixtfdi_s.o _fixunssfdi_s.o _fixunsdfdi_s.o _fixunsxfdi_s.o _fixunstfdi_s.o _floatdisf_s.o _floatdidf_s.o _floatdixf_s.o _floatditf_s.o _floatundisf_s.o _floatundidf_s.o _floatundixf_s.o _floatunditf_s.o _divdi3_s.o _moddi3_s.o _udivdi3_s.o _umoddi3_s.o _udiv_w_sdiv_s.o _udivmoddi4_s.o _addQQ_s.o _addHQ_s.o _addSQ_s.o _addDQ_s.o _addTQ_s.o _addHA_s.o _addSA_s.o _addDA_s.o _addTA_s.o _addUQQ_s.o _addUHQ_s.o _addUSQ_s.o _addUDQ_s.o _addUTQ_s.o _addUHA_s.o _addUSA_s.o _addUDA_s.o _addUTA_s.o _subQQ_s.o _subHQ_s.o _subSQ_s.o _subDQ_s.o _subTQ_s.o _subHA_s.o _subSA_s.o _subDA_s.o _subTA_s.o _subUQQ_s.o _subUHQ_s.o _subUSQ_s.o _subUDQ_s.o _subUTQ_s.o _subUHA_s.o _subUSA_s.o _subUDA_s.o _subUTA_s.o _negQQ_s.o _negHQ_s.o _negSQ_s.o _negDQ_s.o _negTQ_s.o _negHA_s.o _negSA_s.o _negDA_s.o _negTA_s.o _negUQQ_s.o _negUHQ_s.o _negUSQ_s.o _negUDQ_s.o _negUTQ_s.o _negUHA_s.o _negUSA_s.o _negUDA_s.o _negUTA_s.o _mulQQ_s.o _mulHQ_s.o _mulSQ_s.o _mulDQ_s.o _mulTQ_s.o _mulHA_s.o _mulSA_s.o _mulDA_s.o _mulTA_s.o _mulUQQ_s.o _mulUHQ_s.o _mulUSQ_s.o _mulUDQ_s.o _mulUTQ_s.o _mulUHA_s.o _mulUSA_s.o _mulUDA_s.o _mulUTA_s.o _mulhelperQQ_s.o _mulhelperHQ_s.o _mulhelperSQ_s.o _mulhelperDQ_s.o _mulhelperTQ_s.o _mulhelperHA_s.o _mulhelperSA_s.o _mulhelperDA_s.o _mulhelperTA_s.o _mulhelperUQQ_s.o _mulhelperUHQ_s.o _mulhelperUSQ_s.o _mulhelperUDQ_s.o _mulhelperUTQ_s.o _mulhelperUHA_s.o _mulhelperUSA_s.o _mulhelperUDA_s.o _mulhelperUTA_s.o _divhelperQQ_s.o _divhelperHQ_s.o _divhelperSQ_s.o _divhelperDQ_s.o _divhelperTQ_s.o _divhelperHA_s.o _divhelperSA_s.o _divhelperDA_s.o _divhelperTA_s.o _divhelperUQQ_s.o _divhelperUHQ_s.o _divhelperUSQ_s.o _divhelperUDQ_s.o _divhelperUTQ_s.o _divhelperUHA_s.o _divhelperUSA_s.o _divhelperUDA_s.o _divhelperUTA_s.o _ashlQQ_s.o _ashlHQ_s.o _ashlSQ_s.o _ashlDQ_s.o _ashlTQ_s.o _ashlHA_s.o _ashlSA_s.o _ashlDA_s.o _ashlTA_s.o _ashlUQQ_s.o _ashlUHQ_s.o _ashlUSQ_s.o _ashlUDQ_s.o _ashlUTQ_s.o _ashlUHA_s.o _ashlUSA_s.o _ashlUDA_s.o _ashlUTA_s.o _ashlhelperQQ_s.o _ashlhelperHQ_s.o _ashlhelperSQ_s.o _ashlhelperDQ_s.o _ashlhelperTQ_s.o _ashlhelperHA_s.o _ashlhelperSA_s.o _ashlhelperDA_s.o _ashlhelperTA_s.o _ashlhelperUQQ_s.o _ashlhelperUHQ_s.o _ashlhelperUSQ_s.o _ashlhelperUDQ_s.o _ashlhelperUTQ_s.o _ashlhelperUHA_s.o _ashlhelperUSA_s.o _ashlhelperUDA_s.o _ashlhelperUTA_s.o _cmpQQ_s.o _cmpHQ_s.o _cmpSQ_s.o _cmpDQ_s.o _cmpTQ_s.o _cmpHA_s.o _cmpSA_s.o _cmpDA_s.o _cmpTA_s.o _cmpUQQ_s.o _cmpUHQ_s.o _cmpUSQ_s.o _cmpUDQ_s.o _cmpUTQ_s.o _cmpUHA_s.o _cmpUSA_s.o _cmpUDA_s.o _cmpUTA_s.o _saturate1QQ_s.o _saturate1HQ_s.o _saturate1SQ_s.o _saturate1DQ_s.o _saturate1TQ_s.o _saturate1HA_s.o _saturate1SA_s.o _saturate1DA_s.o _saturate1TA_s.o _saturate1UQQ_s.o _saturate1UHQ_s.o _saturate1USQ_s.o _saturate1UDQ_s.o _saturate1UTQ_s.o _saturate1UHA_s.o _saturate1USA_s.o _saturate1UDA_s.o _saturate1UTA_s.o _saturate2QQ_s.o _saturate2HQ_s.o _saturate2SQ_s.o _saturate2DQ_s.o _saturate2TQ_s.o _saturate2HA_s.o _saturate2SA_s.o _saturate2DA_s.o _saturate2TA_s.o _saturate2UQQ_s.o _saturate2UHQ_s.o _saturate2USQ_s.o _saturate2UDQ_s.o _saturate2UTQ_s.o _saturate2UHA_s.o _saturate2USA_s.o _saturate2UDA_s.o _saturate2UTA_s.o _ssaddQQ_s.o _ssaddHQ_s.o _ssaddSQ_s.o _ssaddDQ_s.o _ssaddTQ_s.o _ssaddHA_s.o _ssaddSA_s.o _ssaddDA_s.o _ssaddTA_s.o _sssubQQ_s.o _sssubHQ_s.o _sssubSQ_s.o _sssubDQ_s.o _sssubTQ_s.o _sssubHA_s.o _sssubSA_s.o _sssubDA_s.o _sssubTA_s.o _ssnegQQ_s.o _ssnegHQ_s.o _ssnegSQ_s.o _ssnegDQ_s.o _ssnegTQ_s.o _ssnegHA_s.o _ssnegSA_s.o _ssnegDA_s.o _ssnegTA_s.o _ssmulQQ_s.o _ssmulHQ_s.o _ssmulSQ_s.o _ssmulDQ_s.o _ssmulTQ_s.o _ssmulHA_s.o _ssmulSA_s.o _ssmulDA_s.o _ssmulTA_s.o _ssdivQQ_s.o _ssdivHQ_s.o _ssdivSQ_s.o _ssdivDQ_s.o _ssdivTQ_s.o _ssdivHA_s.o _ssdivSA_s.o _ssdivDA_s.o _ssdivTA_s.o _divQQ_s.o _divHQ_s.o _divSQ_s.o _divDQ_s.o _divTQ_s.o _divHA_s.o _divSA_s.o _divDA_s.o _divTA_s.o _ssashlQQ_s.o _ssashlHQ_s.o _ssashlSQ_s.o _ssashlDQ_s.o _ssashlTQ_s.o _ssashlHA_s.o _ssashlSA_s.o _ssashlDA_s.o _ssashlTA_s.o _ashrQQ_s.o _ashrHQ_s.o _ashrSQ_s.o _ashrDQ_s.o _ashrTQ_s.o _ashrHA_s.o _ashrSA_s.o _ashrDA_s.o _ashrTA_s.o _usaddUQQ_s.o _usaddUHQ_s.o _usaddUSQ_s.o _usaddUDQ_s.o _usaddUTQ_s.o _usaddUHA_s.o _usaddUSA_s.o _usaddUDA_s.o _usaddUTA_s.o _ussubUQQ_s.o _ussubUHQ_s.o _ussubUSQ_s.o _ussubUDQ_s.o _ussubUTQ_s.o _ussubUHA_s.o _ussubUSA_s.o _ussubUDA_s.o _ussubUTA_s.o _usnegUQQ_s.o _usnegUHQ_s.o _usnegUSQ_s.o _usnegUDQ_s.o _usnegUTQ_s.o _usnegUHA_s.o _usnegUSA_s.o _usnegUDA_s.o _usnegUTA_s.o _usmulUQQ_s.o _usmulUHQ_s.o _usmulUSQ_s.o _usmulUDQ_s.o _usmulUTQ_s.o _usmulUHA_s.o _usmulUSA_s.o _usmulUDA_s.o _usmulUTA_s.o _usdivUQQ_s.o _usdivUHQ_s.o _usdivUSQ_s.o _usdivUDQ_s.o _usdivUTQ_s.o _usdivUHA_s.o _usdivUSA_s.o _usdivUDA_s.o _usdivUTA_s.o _udivUQQ_s.o _udivUHQ_s.o _udivUSQ_s.o _udivUDQ_s.o _udivUTQ_s.o _udivUHA_s.o _udivUSA_s.o _udivUDA_s.o _udivUTA_s.o _usashlUQQ_s.o _usashlUHQ_s.o _usashlUSQ_s.o _usashlUDQ_s.o _usashlUTQ_s.o _usashlUHA_s.o _usashlUSA_s.o _usashlUDA_s.o _usashlUTA_s.o _lshrUQQ_s.o _lshrUHQ_s.o _lshrUSQ_s.o _lshrUDQ_s.o _lshrUTQ_s.o _lshrUHA_s.o _lshrUSA_s.o _lshrUDA_s.o _lshrUTA_s.o _fractQQHQ_s.o _fractQQSQ_s.o _fractQQDQ_s.o _fractQQTQ_s.o _fractQQHA_s.o _fractQQSA_s.o _fractQQDA_s.o _fractQQTA_s.o _fractQQUQQ_s.o _fractQQUHQ_s.o _fractQQUSQ_s.o _fractQQUDQ_s.o _fractQQUTQ_s.o _fractQQUHA_s.o _fractQQUSA_s.o _fractQQUDA_s.o _fractQQUTA_s.o _fractQQQI_s.o _fractQQHI_s.o _fractQQSI_s.o _fractQQDI_s.o _fractQQTI_s.o _fractQQSF_s.o _fractQQDF_s.o _fractHQQQ_s.o _fractHQSQ_s.o _fractHQDQ_s.o _fractHQTQ_s.o _fractHQHA_s.o _fractHQSA_s.o _fractHQDA_s.o _fractHQTA_s.o _fractHQUQQ_s.o _fractHQUHQ_s.o _fractHQUSQ_s.o _fractHQUDQ_s.o _fractHQUTQ_s.o _fractHQUHA_s.o _fractHQUSA_s.o _fractHQUDA_s.o _fractHQUTA_s.o _fractHQQI_s.o _fractHQHI_s.o _fractHQSI_s.o _fractHQDI_s.o _fractHQTI_s.o _fractHQSF_s.o _fractHQDF_s.o _fractSQQQ_s.o _fractSQHQ_s.o _fractSQDQ_s.o _fractSQTQ_s.o _fractSQHA_s.o _fractSQSA_s.o _fractSQDA_s.o _fractSQTA_s.o _fractSQUQQ_s.o _fractSQUHQ_s.o _fractSQUSQ_s.o _fractSQUDQ_s.o _fractSQUTQ_s.o _fractSQUHA_s.o _fractSQUSA_s.o _fractSQUDA_s.o _fractSQUTA_s.o _fractSQQI_s.o _fractSQHI_s.o _fractSQSI_s.o _fractSQDI_s.o _fractSQTI_s.o _fractSQSF_s.o _fractSQDF_s.o _fractDQQQ_s.o _fractDQHQ_s.o _fractDQSQ_s.o _fractDQTQ_s.o _fractDQHA_s.o _fractDQSA_s.o _fractDQDA_s.o _fractDQTA_s.o _fractDQUQQ_s.o _fractDQUHQ_s.o _fractDQUSQ_s.o _fractDQUDQ_s.o _fractDQUTQ_s.o _fractDQUHA_s.o _fractDQUSA_s.o _fractDQUDA_s.o _fractDQUTA_s.o _fractDQQI_s.o _fractDQHI_s.o _fractDQSI_s.o _fractDQDI_s.o _fractDQTI_s.o _fractDQSF_s.o _fractDQDF_s.o _fractTQQQ_s.o _fractTQHQ_s.o _fractTQSQ_s.o _fractTQDQ_s.o _fractTQHA_s.o _fractTQSA_s.o _fractTQDA_s.o _fractTQTA_s.o _fractTQUQQ_s.o _fractTQUHQ_s.o _fractTQUSQ_s.o _fractTQUDQ_s.o _fractTQUTQ_s.o _fractTQUHA_s.o _fractTQUSA_s.o _fractTQUDA_s.o _fractTQUTA_s.o _fractTQQI_s.o _fractTQHI_s.o _fractTQSI_s.o _fractTQDI_s.o _fractTQTI_s.o _fractTQSF_s.o _fractTQDF_s.o _fractHAQQ_s.o _fractHAHQ_s.o _fractHASQ_s.o _fractHADQ_s.o _fractHATQ_s.o _fractHASA_s.o _fractHADA_s.o _fractHATA_s.o _fractHAUQQ_s.o _fractHAUHQ_s.o _fractHAUSQ_s.o _fractHAUDQ_s.o _fractHAUTQ_s.o _fractHAUHA_s.o _fractHAUSA_s.o _fractHAUDA_s.o _fractHAUTA_s.o _fractHAQI_s.o _fractHAHI_s.o _fractHASI_s.o _fractHADI_s.o _fractHATI_s.o _fractHASF_s.o _fractHADF_s.o _fractSAQQ_s.o _fractSAHQ_s.o _fractSASQ_s.o _fractSADQ_s.o _fractSATQ_s.o _fractSAHA_s.o _fractSADA_s.o _fractSATA_s.o _fractSAUQQ_s.o _fractSAUHQ_s.o _fractSAUSQ_s.o _fractSAUDQ_s.o _fractSAUTQ_s.o _fractSAUHA_s.o _fractSAUSA_s.o _fractSAUDA_s.o _fractSAUTA_s.o _fractSAQI_s.o _fractSAHI_s.o _fractSASI_s.o _fractSADI_s.o _fractSATI_s.o _fractSASF_s.o _fractSADF_s.o _fractDAQQ_s.o _fractDAHQ_s.o _fractDASQ_s.o _fractDADQ_s.o _fractDATQ_s.o _fractDAHA_s.o _fractDASA_s.o _fractDATA_s.o _fractDAUQQ_s.o _fractDAUHQ_s.o _fractDAUSQ_s.o _fractDAUDQ_s.o _fractDAUTQ_s.o _fractDAUHA_s.o _fractDAUSA_s.o _fractDAUDA_s.o _fractDAUTA_s.o _fractDAQI_s.o _fractDAHI_s.o _fractDASI_s.o _fractDADI_s.o _fractDATI_s.o _fractDASF_s.o _fractDADF_s.o _fractTAQQ_s.o _fractTAHQ_s.o _fractTASQ_s.o _fractTADQ_s.o _fractTATQ_s.o _fractTAHA_s.o _fractTASA_s.o _fractTADA_s.o _fractTAUQQ_s.o _fractTAUHQ_s.o _fractTAUSQ_s.o _fractTAUDQ_s.o _fractTAUTQ_s.o _fractTAUHA_s.o _fractTAUSA_s.o _fractTAUDA_s.o _fractTAUTA_s.o _fractTAQI_s.o _fractTAHI_s.o _fractTASI_s.o _fractTADI_s.o _fractTATI_s.o _fractTASF_s.o _fractTADF_s.o _fractUQQQQ_s.o _fractUQQHQ_s.o _fractUQQSQ_s.o _fractUQQDQ_s.o _fractUQQTQ_s.o _fractUQQHA_s.o _fractUQQSA_s.o _fractUQQDA_s.o _fractUQQTA_s.o _fractUQQUHQ_s.o _fractUQQUSQ_s.o _fractUQQUDQ_s.o _fractUQQUTQ_s.o _fractUQQUHA_s.o _fractUQQUSA_s.o _fractUQQUDA_s.o _fractUQQUTA_s.o _fractUQQQI_s.o _fractUQQHI_s.o _fractUQQSI_s.o _fractUQQDI_s.o _fractUQQTI_s.o _fractUQQSF_s.o _fractUQQDF_s.o _fractUHQQQ_s.o _fractUHQHQ_s.o _fractUHQSQ_s.o _fractUHQDQ_s.o _fractUHQTQ_s.o _fractUHQHA_s.o _fractUHQSA_s.o _fractUHQDA_s.o _fractUHQTA_s.o _fractUHQUQQ_s.o _fractUHQUSQ_s.o _fractUHQUDQ_s.o _fractUHQUTQ_s.o _fractUHQUHA_s.o _fractUHQUSA_s.o _fractUHQUDA_s.o _fractUHQUTA_s.o _fractUHQQI_s.o _fractUHQHI_s.o _fractUHQSI_s.o _fractUHQDI_s.o _fractUHQTI_s.o _fractUHQSF_s.o _fractUHQDF_s.o _fractUSQQQ_s.o _fractUSQHQ_s.o _fractUSQSQ_s.o _fractUSQDQ_s.o _fractUSQTQ_s.o _fractUSQHA_s.o _fractUSQSA_s.o _fractUSQDA_s.o _fractUSQTA_s.o _fractUSQUQQ_s.o _fractUSQUHQ_s.o _fractUSQUDQ_s.o _fractUSQUTQ_s.o _fractUSQUHA_s.o _fractUSQUSA_s.o _fractUSQUDA_s.o _fractUSQUTA_s.o _fractUSQQI_s.o _fractUSQHI_s.o _fractUSQSI_s.o _fractUSQDI_s.o _fractUSQTI_s.o _fractUSQSF_s.o _fractUSQDF_s.o _fractUDQQQ_s.o _fractUDQHQ_s.o _fractUDQSQ_s.o _fractUDQDQ_s.o _fractUDQTQ_s.o _fractUDQHA_s.o _fractUDQSA_s.o _fractUDQDA_s.o _fractUDQTA_s.o _fractUDQUQQ_s.o _fractUDQUHQ_s.o _fractUDQUSQ_s.o _fractUDQUTQ_s.o _fractUDQUHA_s.o _fractUDQUSA_s.o _fractUDQUDA_s.o _fractUDQUTA_s.o _fractUDQQI_s.o _fractUDQHI_s.o _fractUDQSI_s.o _fractUDQDI_s.o _fractUDQTI_s.o _fractUDQSF_s.o _fractUDQDF_s.o _fractUTQQQ_s.o _fractUTQHQ_s.o _fractUTQSQ_s.o _fractUTQDQ_s.o _fractUTQTQ_s.o _fractUTQHA_s.o _fractUTQSA_s.o _fractUTQDA_s.o _fractUTQTA_s.o _fractUTQUQQ_s.o _fractUTQUHQ_s.o _fractUTQUSQ_s.o _fractUTQUDQ_s.o _fractUTQUHA_s.o _fractUTQUSA_s.o _fractUTQUDA_s.o _fractUTQUTA_s.o _fractUTQQI_s.o _fractUTQHI_s.o _fractUTQSI_s.o _fractUTQDI_s.o _fractUTQTI_s.o _fractUTQSF_s.o _fractUTQDF_s.o _fractUHAQQ_s.o _fractUHAHQ_s.o _fractUHASQ_s.o _fractUHADQ_s.o _fractUHATQ_s.o _fractUHAHA_s.o _fractUHASA_s.o _fractUHADA_s.o _fractUHATA_s.o _fractUHAUQQ_s.o _fractUHAUHQ_s.o _fractUHAUSQ_s.o _fractUHAUDQ_s.o _fractUHAUTQ_s.o _fractUHAUSA_s.o _fractUHAUDA_s.o _fractUHAUTA_s.o _fractUHAQI_s.o _fractUHAHI_s.o _fractUHASI_s.o _fractUHADI_s.o _fractUHATI_s.o _fractUHASF_s.o _fractUHADF_s.o _fractUSAQQ_s.o _fractUSAHQ_s.o _fractUSASQ_s.o _fractUSADQ_s.o _fractUSATQ_s.o _fractUSAHA_s.o _fractUSASA_s.o _fractUSADA_s.o _fractUSATA_s.o _fractUSAUQQ_s.o _fractUSAUHQ_s.o _fractUSAUSQ_s.o _fractUSAUDQ_s.o _fractUSAUTQ_s.o _fractUSAUHA_s.o _fractUSAUDA_s.o _fractUSAUTA_s.o _fractUSAQI_s.o _fractUSAHI_s.o _fractUSASI_s.o _fractUSADI_s.o _fractUSATI_s.o _fractUSASF_s.o _fractUSADF_s.o _fractUDAQQ_s.o _fractUDAHQ_s.o _fractUDASQ_s.o _fractUDADQ_s.o _fractUDATQ_s.o _fractUDAHA_s.o _fractUDASA_s.o _fractUDADA_s.o _fractUDATA_s.o _fractUDAUQQ_s.o _fractUDAUHQ_s.o _fractUDAUSQ_s.o _fractUDAUDQ_s.o _fractUDAUTQ_s.o _fractUDAUHA_s.o _fractUDAUSA_s.o _fractUDAUTA_s.o _fractUDAQI_s.o _fractUDAHI_s.o _fractUDASI_s.o _fractUDADI_s.o _fractUDATI_s.o _fractUDASF_s.o _fractUDADF_s.o _fractUTAQQ_s.o _fractUTAHQ_s.o _fractUTASQ_s.o _fractUTADQ_s.o _fractUTATQ_s.o _fractUTAHA_s.o _fractUTASA_s.o _fractUTADA_s.o _fractUTATA_s.o _fractUTAUQQ_s.o _fractUTAUHQ_s.o _fractUTAUSQ_s.o _fractUTAUDQ_s.o _fractUTAUTQ_s.o _fractUTAUHA_s.o _fractUTAUSA_s.o _fractUTAUDA_s.o _fractUTAQI_s.o _fractUTAHI_s.o _fractUTASI_s.o _fractUTADI_s.o _fractUTATI_s.o _fractUTASF_s.o _fractUTADF_s.o _fractQIQQ_s.o _fractQIHQ_s.o _fractQISQ_s.o _fractQIDQ_s.o _fractQITQ_s.o _fractQIHA_s.o _fractQISA_s.o _fractQIDA_s.o _fractQITA_s.o _fractQIUQQ_s.o _fractQIUHQ_s.o _fractQIUSQ_s.o _fractQIUDQ_s.o _fractQIUTQ_s.o _fractQIUHA_s.o _fractQIUSA_s.o _fractQIUDA_s.o _fractQIUTA_s.o _fractHIQQ_s.o _fractHIHQ_s.o _fractHISQ_s.o _fractHIDQ_s.o _fractHITQ_s.o _fractHIHA_s.o _fractHISA_s.o _fractHIDA_s.o _fractHITA_s.o _fractHIUQQ_s.o _fractHIUHQ_s.o _fractHIUSQ_s.o _fractHIUDQ_s.o _fractHIUTQ_s.o _fractHIUHA_s.o _fractHIUSA_s.o _fractHIUDA_s.o _fractHIUTA_s.o _fractSIQQ_s.o _fractSIHQ_s.o _fractSISQ_s.o _fractSIDQ_s.o _fractSITQ_s.o _fractSIHA_s.o _fractSISA_s.o _fractSIDA_s.o _fractSITA_s.o _fractSIUQQ_s.o _fractSIUHQ_s.o _fractSIUSQ_s.o _fractSIUDQ_s.o _fractSIUTQ_s.o _fractSIUHA_s.o _fractSIUSA_s.o _fractSIUDA_s.o _fractSIUTA_s.o _fractDIQQ_s.o _fractDIHQ_s.o _fractDISQ_s.o _fractDIDQ_s.o _fractDITQ_s.o _fractDIHA_s.o _fractDISA_s.o _fractDIDA_s.o _fractDITA_s.o _fractDIUQQ_s.o _fractDIUHQ_s.o _fractDIUSQ_s.o _fractDIUDQ_s.o _fractDIUTQ_s.o _fractDIUHA_s.o _fractDIUSA_s.o _fractDIUDA_s.o _fractDIUTA_s.o _fractTIQQ_s.o _fractTIHQ_s.o _fractTISQ_s.o _fractTIDQ_s.o _fractTITQ_s.o _fractTIHA_s.o _fractTISA_s.o _fractTIDA_s.o _fractTITA_s.o _fractTIUQQ_s.o _fractTIUHQ_s.o _fractTIUSQ_s.o _fractTIUDQ_s.o _fractTIUTQ_s.o _fractTIUHA_s.o _fractTIUSA_s.o _fractTIUDA_s.o _fractTIUTA_s.o _fractSFQQ_s.o _fractSFHQ_s.o _fractSFSQ_s.o _fractSFDQ_s.o"

# Full
OBJS2="_fractSFTQ_s.o _fractSFHA_s.o _fractSFSA_s.o _fractSFDA_s.o _fractSFTA_s.o _fractSFUQQ_s.o _fractSFUHQ_s.o _fractSFUSQ_s.o _fractSFUDQ_s.o _fractSFUTQ_s.o _fractSFUHA_s.o _fractSFUSA_s.o _fractSFUDA_s.o _fractSFUTA_s.o _fractDFQQ_s.o _fractDFHQ_s.o _fractDFSQ_s.o _fractDFDQ_s.o _fractDFTQ_s.o _fractDFHA_s.o _fractDFSA_s.o _fractDFDA_s.o _fractDFTA_s.o _fractDFUQQ_s.o _fractDFUHQ_s.o _fractDFUSQ_s.o _fractDFUDQ_s.o _fractDFUTQ_s.o _fractDFUHA_s.o _fractDFUSA_s.o _fractDFUDA_s.o _fractDFUTA_s.o _satfractQQHQ_s.o _satfractQQSQ_s.o _satfractQQDQ_s.o _satfractQQTQ_s.o _satfractQQHA_s.o _satfractQQSA_s.o _satfractQQDA_s.o _satfractQQTA_s.o _satfractQQUQQ_s.o _satfractQQUHQ_s.o _satfractQQUSQ_s.o _satfractQQUDQ_s.o _satfractQQUTQ_s.o _satfractQQUHA_s.o _satfractQQUSA_s.o _satfractQQUDA_s.o _satfractQQUTA_s.o _satfractHQQQ_s.o _satfractHQSQ_s.o _satfractHQDQ_s.o _satfractHQTQ_s.o _satfractHQHA_s.o _satfractHQSA_s.o _satfractHQDA_s.o _satfractHQTA_s.o _satfractHQUQQ_s.o _satfractHQUHQ_s.o _satfractHQUSQ_s.o _satfractHQUDQ_s.o _satfractHQUTQ_s.o _satfractHQUHA_s.o _satfractHQUSA_s.o _satfractHQUDA_s.o _satfractHQUTA_s.o _satfractSQQQ_s.o _satfractSQHQ_s.o _satfractSQDQ_s.o _satfractSQTQ_s.o _satfractSQHA_s.o _satfractSQSA_s.o _satfractSQDA_s.o _satfractSQTA_s.o _satfractSQUQQ_s.o _satfractSQUHQ_s.o _satfractSQUSQ_s.o _satfractSQUDQ_s.o _satfractSQUTQ_s.o _satfractSQUHA_s.o _satfractSQUSA_s.o _satfractSQUDA_s.o _satfractSQUTA_s.o _satfractDQQQ_s.o _satfractDQHQ_s.o _satfractDQSQ_s.o _satfractDQTQ_s.o _satfractDQHA_s.o _satfractDQSA_s.o _satfractDQDA_s.o _satfractDQTA_s.o _satfractDQUQQ_s.o _satfractDQUHQ_s.o _satfractDQUSQ_s.o _satfractDQUDQ_s.o _satfractDQUTQ_s.o _satfractDQUHA_s.o _satfractDQUSA_s.o _satfractDQUDA_s.o _satfractDQUTA_s.o _satfractTQQQ_s.o _satfractTQHQ_s.o _satfractTQSQ_s.o _satfractTQDQ_s.o _satfractTQHA_s.o _satfractTQSA_s.o _satfractTQDA_s.o _satfractTQTA_s.o _satfractTQUQQ_s.o _satfractTQUHQ_s.o _satfractTQUSQ_s.o _satfractTQUDQ_s.o _satfractTQUTQ_s.o _satfractTQUHA_s.o _satfractTQUSA_s.o _satfractTQUDA_s.o _satfractTQUTA_s.o _satfractHAQQ_s.o _satfractHAHQ_s.o _satfractHASQ_s.o _satfractHADQ_s.o _satfractHATQ_s.o _satfractHASA_s.o _satfractHADA_s.o _satfractHATA_s.o _satfractHAUQQ_s.o _satfractHAUHQ_s.o _satfractHAUSQ_s.o _satfractHAUDQ_s.o _satfractHAUTQ_s.o _satfractHAUHA_s.o _satfractHAUSA_s.o _satfractHAUDA_s.o _satfractHAUTA_s.o _satfractSAQQ_s.o _satfractSAHQ_s.o _satfractSASQ_s.o _satfractSADQ_s.o _satfractSATQ_s.o _satfractSAHA_s.o _satfractSADA_s.o _satfractSATA_s.o _satfractSAUQQ_s.o _satfractSAUHQ_s.o _satfractSAUSQ_s.o _satfractSAUDQ_s.o _satfractSAUTQ_s.o _satfractSAUHA_s.o _satfractSAUSA_s.o _satfractSAUDA_s.o _satfractSAUTA_s.o _satfractDAQQ_s.o _satfractDAHQ_s.o _satfractDASQ_s.o _satfractDADQ_s.o _satfractDATQ_s.o _satfractDAHA_s.o _satfractDASA_s.o _satfractDATA_s.o _satfractDAUQQ_s.o _satfractDAUHQ_s.o _satfractDAUSQ_s.o _satfractDAUDQ_s.o _satfractDAUTQ_s.o _satfractDAUHA_s.o _satfractDAUSA_s.o _satfractDAUDA_s.o _satfractDAUTA_s.o _satfractTAQQ_s.o _satfractTAHQ_s.o _satfractTASQ_s.o _satfractTADQ_s.o _satfractTATQ_s.o _satfractTAHA_s.o _satfractTASA_s.o _satfractTADA_s.o _satfractTAUQQ_s.o _satfractTAUHQ_s.o _satfractTAUSQ_s.o _satfractTAUDQ_s.o _satfractTAUTQ_s.o _satfractTAUHA_s.o _satfractTAUSA_s.o _satfractTAUDA_s.o _satfractTAUTA_s.o _satfractUQQQQ_s.o _satfractUQQHQ_s.o _satfractUQQSQ_s.o _satfractUQQDQ_s.o _satfractUQQTQ_s.o _satfractUQQHA_s.o _satfractUQQSA_s.o _satfractUQQDA_s.o _satfractUQQTA_s.o _satfractUQQUHQ_s.o _satfractUQQUSQ_s.o _satfractUQQUDQ_s.o _satfractUQQUTQ_s.o _satfractUQQUHA_s.o _satfractUQQUSA_s.o _satfractUQQUDA_s.o _satfractUQQUTA_s.o _satfractUHQQQ_s.o _satfractUHQHQ_s.o _satfractUHQSQ_s.o _satfractUHQDQ_s.o _satfractUHQTQ_s.o _satfractUHQHA_s.o _satfractUHQSA_s.o _satfractUHQDA_s.o _satfractUHQTA_s.o _satfractUHQUQQ_s.o _satfractUHQUSQ_s.o _satfractUHQUDQ_s.o _satfractUHQUTQ_s.o _satfractUHQUHA_s.o _satfractUHQUSA_s.o _satfractUHQUDA_s.o _satfractUHQUTA_s.o _satfractUSQQQ_s.o _satfractUSQHQ_s.o _satfractUSQSQ_s.o _satfractUSQDQ_s.o _satfractUSQTQ_s.o _satfractUSQHA_s.o _satfractUSQSA_s.o _satfractUSQDA_s.o _satfractUSQTA_s.o _satfractUSQUQQ_s.o _satfractUSQUHQ_s.o _satfractUSQUDQ_s.o _satfractUSQUTQ_s.o _satfractUSQUHA_s.o _satfractUSQUSA_s.o _satfractUSQUDA_s.o _satfractUSQUTA_s.o _satfractUDQQQ_s.o _satfractUDQHQ_s.o _satfractUDQSQ_s.o _satfractUDQDQ_s.o _satfractUDQTQ_s.o _satfractUDQHA_s.o _satfractUDQSA_s.o _satfractUDQDA_s.o _satfractUDQTA_s.o _satfractUDQUQQ_s.o _satfractUDQUHQ_s.o _satfractUDQUSQ_s.o _satfractUDQUTQ_s.o _satfractUDQUHA_s.o _satfractUDQUSA_s.o _satfractUDQUDA_s.o _satfractUDQUTA_s.o _satfractUTQQQ_s.o _satfractUTQHQ_s.o _satfractUTQSQ_s.o _satfractUTQDQ_s.o _satfractUTQTQ_s.o _satfractUTQHA_s.o _satfractUTQSA_s.o _satfractUTQDA_s.o _satfractUTQTA_s.o _satfractUTQUQQ_s.o _satfractUTQUHQ_s.o _satfractUTQUSQ_s.o _satfractUTQUDQ_s.o _satfractUTQUHA_s.o _satfractUTQUSA_s.o _satfractUTQUDA_s.o _satfractUTQUTA_s.o _satfractUHAQQ_s.o _satfractUHAHQ_s.o _satfractUHASQ_s.o _satfractUHADQ_s.o _satfractUHATQ_s.o _satfractUHAHA_s.o _satfractUHASA_s.o _satfractUHADA_s.o _satfractUHATA_s.o _satfractUHAUQQ_s.o _satfractUHAUHQ_s.o _satfractUHAUSQ_s.o _satfractUHAUDQ_s.o _satfractUHAUTQ_s.o _satfractUHAUSA_s.o _satfractUHAUDA_s.o _satfractUHAUTA_s.o _satfractUSAQQ_s.o _satfractUSAHQ_s.o _satfractUSASQ_s.o _satfractUSADQ_s.o _satfractUSATQ_s.o _satfractUSAHA_s.o _satfractUSASA_s.o _satfractUSADA_s.o _satfractUSATA_s.o _satfractUSAUQQ_s.o _satfractUSAUHQ_s.o _satfractUSAUSQ_s.o _satfractUSAUDQ_s.o _satfractUSAUTQ_s.o _satfractUSAUHA_s.o _satfractUSAUDA_s.o _satfractUSAUTA_s.o _satfractUDAQQ_s.o _satfractUDAHQ_s.o _satfractUDASQ_s.o _satfractUDADQ_s.o _satfractUDATQ_s.o _satfractUDAHA_s.o _satfractUDASA_s.o _satfractUDADA_s.o _satfractUDATA_s.o _satfractUDAUQQ_s.o _satfractUDAUHQ_s.o _satfractUDAUSQ_s.o _satfractUDAUDQ_s.o _satfractUDAUTQ_s.o _satfractUDAUHA_s.o _satfractUDAUSA_s.o _satfractUDAUTA_s.o _satfractUTAQQ_s.o _satfractUTAHQ_s.o _satfractUTASQ_s.o _satfractUTADQ_s.o _satfractUTATQ_s.o _satfractUTAHA_s.o _satfractUTASA_s.o _satfractUTADA_s.o _satfractUTATA_s.o _satfractUTAUQQ_s.o _satfractUTAUHQ_s.o _satfractUTAUSQ_s.o _satfractUTAUDQ_s.o _satfractUTAUTQ_s.o _satfractUTAUHA_s.o _satfractUTAUSA_s.o _satfractUTAUDA_s.o _satfractQIQQ_s.o _satfractQIHQ_s.o _satfractQISQ_s.o _satfractQIDQ_s.o _satfractQITQ_s.o _satfractQIHA_s.o _satfractQISA_s.o _satfractQIDA_s.o _satfractQITA_s.o _satfractQIUQQ_s.o _satfractQIUHQ_s.o _satfractQIUSQ_s.o _satfractQIUDQ_s.o _satfractQIUTQ_s.o _satfractQIUHA_s.o _satfractQIUSA_s.o _satfractQIUDA_s.o _satfractQIUTA_s.o _satfractHIQQ_s.o _satfractHIHQ_s.o _satfractHISQ_s.o _satfractHIDQ_s.o _satfractHITQ_s.o _satfractHIHA_s.o _satfractHISA_s.o _satfractHIDA_s.o _satfractHITA_s.o _satfractHIUQQ_s.o _satfractHIUHQ_s.o _satfractHIUSQ_s.o _satfractHIUDQ_s.o _satfractHIUTQ_s.o _satfractHIUHA_s.o _satfractHIUSA_s.o _satfractHIUDA_s.o _satfractHIUTA_s.o _satfractSIQQ_s.o _satfractSIHQ_s.o _satfractSISQ_s.o _satfractSIDQ_s.o _satfractSITQ_s.o _satfractSIHA_s.o _satfractSISA_s.o _satfractSIDA_s.o _satfractSITA_s.o _satfractSIUQQ_s.o _satfractSIUHQ_s.o _satfractSIUSQ_s.o _satfractSIUDQ_s.o _satfractSIUTQ_s.o _satfractSIUHA_s.o _satfractSIUSA_s.o _satfractSIUDA_s.o _satfractSIUTA_s.o _satfractDIQQ_s.o _satfractDIHQ_s.o _satfractDISQ_s.o _satfractDIDQ_s.o _satfractDITQ_s.o _satfractDIHA_s.o _satfractDISA_s.o _satfractDIDA_s.o _satfractDITA_s.o _satfractDIUQQ_s.o _satfractDIUHQ_s.o _satfractDIUSQ_s.o _satfractDIUDQ_s.o _satfractDIUTQ_s.o _satfractDIUHA_s.o _satfractDIUSA_s.o _satfractDIUDA_s.o _satfractDIUTA_s.o _satfractTIQQ_s.o _satfractTIHQ_s.o _satfractTISQ_s.o _satfractTIDQ_s.o _satfractTITQ_s.o _satfractTIHA_s.o _satfractTISA_s.o _satfractTIDA_s.o _satfractTITA_s.o _satfractTIUQQ_s.o _satfractTIUHQ_s.o _satfractTIUSQ_s.o _satfractTIUDQ_s.o _satfractTIUTQ_s.o _satfractTIUHA_s.o _satfractTIUSA_s.o _satfractTIUDA_s.o _satfractTIUTA_s.o _satfractSFQQ_s.o _satfractSFHQ_s.o _satfractSFSQ_s.o _satfractSFDQ_s.o _satfractSFTQ_s.o _satfractSFHA_s.o _satfractSFSA_s.o _satfractSFDA_s.o _satfractSFTA_s.o _satfractSFUQQ_s.o _satfractSFUHQ_s.o _satfractSFUSQ_s.o _satfractSFUDQ_s.o _satfractSFUTQ_s.o _satfractSFUHA_s.o _satfractSFUSA_s.o _satfractSFUDA_s.o _satfractSFUTA_s.o _satfractDFQQ_s.o _satfractDFHQ_s.o _satfractDFSQ_s.o _satfractDFDQ_s.o _satfractDFTQ_s.o _satfractDFHA_s.o _satfractDFSA_s.o _satfractDFDA_s.o _satfractDFTA_s.o _satfractDFUQQ_s.o _satfractDFUHQ_s.o _satfractDFUSQ_s.o _satfractDFUDQ_s.o _satfractDFUTQ_s.o _satfractDFUHA_s.o _satfractDFUSA_s.o _satfractDFUDA_s.o _satfractDFUTA_s.o _fractunsQQUQI_s.o _fractunsQQUHI_s.o _fractunsQQUSI_s.o _fractunsQQUDI_s.o _fractunsQQUTI_s.o _fractunsHQUQI_s.o _fractunsHQUHI_s.o _fractunsHQUSI_s.o _fractunsHQUDI_s.o _fractunsHQUTI_s.o _fractunsSQUQI_s.o _fractunsSQUHI_s.o _fractunsSQUSI_s.o _fractunsSQUDI_s.o _fractunsSQUTI_s.o _fractunsDQUQI_s.o _fractunsDQUHI_s.o _fractunsDQUSI_s.o _fractunsDQUDI_s.o _fractunsDQUTI_s.o _fractunsTQUQI_s.o _fractunsTQUHI_s.o _fractunsTQUSI_s.o _fractunsTQUDI_s.o _fractunsTQUTI_s.o _fractunsHAUQI_s.o _fractunsHAUHI_s.o _fractunsHAUSI_s.o _fractunsHAUDI_s.o _fractunsHAUTI_s.o _fractunsSAUQI_s.o _fractunsSAUHI_s.o _fractunsSAUSI_s.o _fractunsSAUDI_s.o _fractunsSAUTI_s.o _fractunsDAUQI_s.o _fractunsDAUHI_s.o _fractunsDAUSI_s.o _fractunsDAUDI_s.o _fractunsDAUTI_s.o _fractunsTAUQI_s.o _fractunsTAUHI_s.o _fractunsTAUSI_s.o _fractunsTAUDI_s.o _fractunsTAUTI_s.o _fractunsUQQUQI_s.o _fractunsUQQUHI_s.o _fractunsUQQUSI_s.o _fractunsUQQUDI_s.o _fractunsUQQUTI_s.o _fractunsUHQUQI_s.o _fractunsUHQUHI_s.o _fractunsUHQUSI_s.o _fractunsUHQUDI_s.o _fractunsUHQUTI_s.o _fractunsUSQUQI_s.o _fractunsUSQUHI_s.o _fractunsUSQUSI_s.o _fractunsUSQUDI_s.o _fractunsUSQUTI_s.o _fractunsUDQUQI_s.o _fractunsUDQUHI_s.o _fractunsUDQUSI_s.o _fractunsUDQUDI_s.o _fractunsUDQUTI_s.o _fractunsUTQUQI_s.o _fractunsUTQUHI_s.o _fractunsUTQUSI_s.o _fractunsUTQUDI_s.o _fractunsUTQUTI_s.o _fractunsUHAUQI_s.o _fractunsUHAUHI_s.o _fractunsUHAUSI_s.o _fractunsUHAUDI_s.o _fractunsUHAUTI_s.o _fractunsUSAUQI_s.o _fractunsUSAUHI_s.o _fractunsUSAUSI_s.o _fractunsUSAUDI_s.o _fractunsUSAUTI_s.o _fractunsUDAUQI_s.o _fractunsUDAUHI_s.o _fractunsUDAUSI_s.o _fractunsUDAUDI_s.o _fractunsUDAUTI_s.o _fractunsUTAUQI_s.o _fractunsUTAUHI_s.o _fractunsUTAUSI_s.o _fractunsUTAUDI_s.o _fractunsUTAUTI_s.o _fractunsUQIQQ_s.o _fractunsUQIHQ_s.o _fractunsUQISQ_s.o _fractunsUQIDQ_s.o _fractunsUQITQ_s.o _fractunsUQIHA_s.o _fractunsUQISA_s.o _fractunsUQIDA_s.o _fractunsUQITA_s.o _fractunsUQIUQQ_s.o _fractunsUQIUHQ_s.o _fractunsUQIUSQ_s.o _fractunsUQIUDQ_s.o _fractunsUQIUTQ_s.o _fractunsUQIUHA_s.o _fractunsUQIUSA_s.o _fractunsUQIUDA_s.o _fractunsUQIUTA_s.o _fractunsUHIQQ_s.o _fractunsUHIHQ_s.o _fractunsUHISQ_s.o _fractunsUHIDQ_s.o _fractunsUHITQ_s.o _fractunsUHIHA_s.o _fractunsUHISA_s.o _fractunsUHIDA_s.o _fractunsUHITA_s.o _fractunsUHIUQQ_s.o _fractunsUHIUHQ_s.o _fractunsUHIUSQ_s.o _fractunsUHIUDQ_s.o _fractunsUHIUTQ_s.o _fractunsUHIUHA_s.o _fractunsUHIUSA_s.o _fractunsUHIUDA_s.o _fractunsUHIUTA_s.o _fractunsUSIQQ_s.o _fractunsUSIHQ_s.o _fractunsUSISQ_s.o _fractunsUSIDQ_s.o _fractunsUSITQ_s.o _fractunsUSIHA_s.o _fractunsUSISA_s.o _fractunsUSIDA_s.o _fractunsUSITA_s.o _fractunsUSIUQQ_s.o _fractunsUSIUHQ_s.o _fractunsUSIUSQ_s.o _fractunsUSIUDQ_s.o _fractunsUSIUTQ_s.o _fractunsUSIUHA_s.o _fractunsUSIUSA_s.o _fractunsUSIUDA_s.o _fractunsUSIUTA_s.o _fractunsUDIQQ_s.o _fractunsUDIHQ_s.o _fractunsUDISQ_s.o _fractunsUDIDQ_s.o _fractunsUDITQ_s.o _fractunsUDIHA_s.o _fractunsUDISA_s.o _fractunsUDIDA_s.o _fractunsUDITA_s.o _fractunsUDIUQQ_s.o _fractunsUDIUHQ_s.o _fractunsUDIUSQ_s.o _fractunsUDIUDQ_s.o _fractunsUDIUTQ_s.o _fractunsUDIUHA_s.o _fractunsUDIUSA_s.o _fractunsUDIUDA_s.o _fractunsUDIUTA_s.o _fractunsUTIQQ_s.o _fractunsUTIHQ_s.o _fractunsUTISQ_s.o _fractunsUTIDQ_s.o _fractunsUTITQ_s.o _fractunsUTIHA_s.o _fractunsUTISA_s.o _fractunsUTIDA_s.o _fractunsUTITA_s.o _fractunsUTIUQQ_s.o _fractunsUTIUHQ_s.o _fractunsUTIUSQ_s.o _fractunsUTIUDQ_s.o _fractunsUTIUTQ_s.o _fractunsUTIUHA_s.o _fractunsUTIUSA_s.o _fractunsUTIUDA_s.o _fractunsUTIUTA_s.o _satfractunsUQIQQ_s.o _satfractunsUQIHQ_s.o _satfractunsUQISQ_s.o _satfractunsUQIDQ_s.o _satfractunsUQITQ_s.o _satfractunsUQIHA_s.o _satfractunsUQISA_s.o _satfractunsUQIDA_s.o _satfractunsUQITA_s.o _satfractunsUQIUQQ_s.o _satfractunsUQIUHQ_s.o _satfractunsUQIUSQ_s.o _satfractunsUQIUDQ_s.o _satfractunsUQIUTQ_s.o _satfractunsUQIUHA_s.o _satfractunsUQIUSA_s.o _satfractunsUQIUDA_s.o _satfractunsUQIUTA_s.o _satfractunsUHIQQ_s.o _satfractunsUHIHQ_s.o _satfractunsUHISQ_s.o _satfractunsUHIDQ_s.o _satfractunsUHITQ_s.o _satfractunsUHIHA_s.o _satfractunsUHISA_s.o _satfractunsUHIDA_s.o _satfractunsUHITA_s.o _satfractunsUHIUQQ_s.o _satfractunsUHIUHQ_s.o _satfractunsUHIUSQ_s.o _satfractunsUHIUDQ_s.o _satfractunsUHIUTQ_s.o _satfractunsUHIUHA_s.o _satfractunsUHIUSA_s.o _satfractunsUHIUDA_s.o _satfractunsUHIUTA_s.o _satfractunsUSIQQ_s.o _satfractunsUSIHQ_s.o _satfractunsUSISQ_s.o _satfractunsUSIDQ_s.o _satfractunsUSITQ_s.o _satfractunsUSIHA_s.o _satfractunsUSISA_s.o _satfractunsUSIDA_s.o _satfractunsUSITA_s.o _satfractunsUSIUQQ_s.o _satfractunsUSIUHQ_s.o _satfractunsUSIUSQ_s.o _satfractunsUSIUDQ_s.o _satfractunsUSIUTQ_s.o _satfractunsUSIUHA_s.o _satfractunsUSIUSA_s.o _satfractunsUSIUDA_s.o _satfractunsUSIUTA_s.o _satfractunsUDIQQ_s.o _satfractunsUDIHQ_s.o _satfractunsUDISQ_s.o _satfractunsUDIDQ_s.o _satfractunsUDITQ_s.o _satfractunsUDIHA_s.o _satfractunsUDISA_s.o _satfractunsUDIDA_s.o _satfractunsUDITA_s.o _satfractunsUDIUQQ_s.o _satfractunsUDIUHQ_s.o _satfractunsUDIUSQ_s.o _satfractunsUDIUDQ_s.o _satfractunsUDIUTQ_s.o _satfractunsUDIUHA_s.o _satfractunsUDIUSA_s.o _satfractunsUDIUDA_s.o _satfractunsUDIUTA_s.o _satfractunsUTIQQ_s.o _satfractunsUTIHQ_s.o _satfractunsUTISQ_s.o _satfractunsUTIDQ_s.o _satfractunsUTITQ_s.o _satfractunsUTIHA_s.o _satfractunsUTISA_s.o _satfractunsUTIDA_s.o _satfractunsUTITA_s.o _satfractunsUTIUQQ_s.o _satfractunsUTIUHQ_s.o _satfractunsUTIUSQ_s.o _satfractunsUTIUDQ_s.o _satfractunsUTIUTQ_s.o _satfractunsUTIUHA_s.o _satfractunsUTIUSA_s.o _satfractunsUTIUDA_s.o _satfractunsUTIUTA_s.o bpabi_s.o unaligned-funcs_s.o addsf3_s.o divsf3_s.o eqsf2_s.o gesf2_s.o lesf2_s.o mulsf3_s.o negsf2_s.o subsf3_s.o unordsf2_s.o fixsfsi_s.o floatsisf_s.o floatunsisf_s.o adddf3_s.o divdf3_s.o eqdf2_s.o gedf2_s.o ledf2_s.o muldf3_s.o negdf2_s.o subdf3_s.o unorddf2_s.o fixdfsi_s.o floatsidf_s.o floatunsidf_s.o extendsfdf2_s.o truncdfsf2_s.o enable-execute-stack_s.o unwind-arm_s.o libunwind_s.o pr-support_s.o unwind-c_s.o emutls_s.o"

# Works:
OBJS2="_fractSFTQ_s.o _fractSFHA_s.o _fractSFSA_s.o _fractSFDA_s.o _fractSFTA_s.o _fractSFUQQ_s.o _fractSFUHQ_s.o _fractSFUSQ_s.o _fractSFUDQ_s.o _fractSFUTQ_s.o _fractSFUHA_s.o _fractSFUSA_s.o _fractSFUDA_s.o _fractSFUTA_s.o _fractDFQQ_s.o _fractDFHQ_s.o _fractDFSQ_s.o _fractDFDQ_s.o _fractDFTQ_s.o _fractDFHA_s.o _fractDFSA_s.o _fractDFDA_s.o _fractDFTA_s.o _fractDFUQQ_s.o _fractDFUHQ_s.o _fractDFUSQ_s.o _fractDFUDQ_s.o _fractDFUTQ_s.o _fractDFUHA_s.o _fractDFUSA_s.o _fractDFUDA_s.o _fractDFUTA_s.o _satfractQQHQ_s.o _satfractQQSQ_s.o _satfractQQDQ_s.o _satfractQQTQ_s.o _satfractQQHA_s.o _satfractQQSA_s.o _satfractQQDA_s.o _satfractQQTA_s.o _satfractQQUQQ_s.o _satfractQQUHQ_s.o _satfractQQUSQ_s.o _satfractQQUDQ_s.o _satfractQQUTQ_s.o _satfractQQUHA_s.o _satfractQQUSA_s.o _satfractQQUDA_s.o _satfractQQUTA_s.o _satfractHQQQ_s.o _satfractHQSQ_s.o _satfractHQDQ_s.o _satfractHQTQ_s.o _satfractHQHA_s.o _satfractHQSA_s.o _satfractHQDA_s.o _satfractHQTA_s.o _satfractHQUQQ_s.o _satfractHQUHQ_s.o _satfractHQUSQ_s.o _satfractHQUDQ_s.o _satfractHQUTQ_s.o _satfractHQUHA_s.o _satfractHQUSA_s.o _satfractHQUDA_s.o _satfractHQUTA_s.o _satfractSQQQ_s.o _satfractSQHQ_s.o _satfractSQDQ_s.o _satfractSQTQ_s.o _satfractSQHA_s.o _satfractSQSA_s.o _satfractSQDA_s.o _satfractSQTA_s.o _satfractSQUQQ_s.o _satfractSQUHQ_s.o _satfractSQUSQ_s.o _satfractSQUDQ_s.o _satfractSQUTQ_s.o _satfractSQUHA_s.o _satfractSQUSA_s.o _satfractSQUDA_s.o _satfractSQUTA_s.o _satfractDQQQ_s.o _satfractDQHQ_s.o _satfractDQSQ_s.o _satfractDQTQ_s.o _satfractDQHA_s.o _satfractDQSA_s.o _satfractDQDA_s.o _satfractDQTA_s.o _satfractDQUQQ_s.o _satfractDQUHQ_s.o _satfractDQUSQ_s.o _satfractDQUDQ_s.o _satfractDQUTQ_s.o _satfractDQUHA_s.o _satfractDQUSA_s.o _satfractDQUDA_s.o _satfractDQUTA_s.o _satfractTQQQ_s.o _satfractTQHQ_s.o _satfractTQSQ_s.o _satfractTQDQ_s.o _satfractTQHA_s.o _satfractTQSA_s.o _satfractTQDA_s.o _satfractTQTA_s.o _satfractTQUQQ_s.o _satfractTQUHQ_s.o _satfractTQUSQ_s.o _satfractTQUDQ_s.o _satfractTQUTQ_s.o _satfractTQUHA_s.o _satfractTQUSA_s.o _satfractTQUDA_s.o _satfractTQUTA_s.o _satfractHAQQ_s.o _satfractHAHQ_s.o _satfractHASQ_s.o _satfractHADQ_s.o _satfractHATQ_s.o _satfractHASA_s.o _satfractHADA_s.o _satfractHATA_s.o _satfractHAUQQ_s.o _satfractHAUHQ_s.o _satfractHAUSQ_s.o _satfractHAUDQ_s.o _satfractHAUTQ_s.o _satfractHAUHA_s.o _satfractHAUSA_s.o _satfractHAUDA_s.o _satfractHAUTA_s.o _satfractSAQQ_s.o _satfractSAHQ_s.o _satfractSASQ_s.o _satfractSADQ_s.o _satfractSATQ_s.o _satfractSAHA_s.o _satfractSADA_s.o _satfractSATA_s.o _satfractSAUQQ_s.o _satfractSAUHQ_s.o _satfractSAUSQ_s.o _satfractSAUDQ_s.o _satfractSAUTQ_s.o _satfractSAUHA_s.o _satfractSAUSA_s.o _satfractSAUDA_s.o _satfractSAUTA_s.o _satfractDAQQ_s.o _satfractDAHQ_s.o _satfractDASQ_s.o _satfractDADQ_s.o _satfractDATQ_s.o _satfractDAHA_s.o _satfractDASA_s.o _satfractDATA_s.o _satfractDAUQQ_s.o _satfractDAUHQ_s.o _satfractDAUSQ_s.o _satfractDAUDQ_s.o _satfractDAUTQ_s.o _satfractDAUHA_s.o _satfractDAUSA_s.o _satfractDAUDA_s.o _satfractDAUTA_s.o _satfractTAQQ_s.o _satfractTAHQ_s.o _satfractTASQ_s.o _satfractTADQ_s.o _satfractTATQ_s.o _satfractTAHA_s.o _satfractTASA_s.o _satfractTADA_s.o _satfractTAUQQ_s.o _satfractTAUHQ_s.o _satfractTAUSQ_s.o _satfractTAUDQ_s.o _satfractTAUTQ_s.o _satfractTAUHA_s.o _satfractTAUSA_s.o _satfractTAUDA_s.o _satfractTAUTA_s.o _satfractUQQQQ_s.o _satfractUQQHQ_s.o _satfractUQQSQ_s.o _satfractUQQDQ_s.o _satfractUQQTQ_s.o _satfractUQQHA_s.o _satfractUQQSA_s.o _satfractUQQDA_s.o _satfractUQQTA_s.o _satfractUQQUHQ_s.o _satfractUQQUSQ_s.o _satfractUQQUDQ_s.o _satfractUQQUTQ_s.o _satfractUQQUHA_s.o _satfractUQQUSA_s.o _satfractUQQUDA_s.o _satfractUQQUTA_s.o _satfractUHQQQ_s.o _satfractUHQHQ_s.o _satfractUHQSQ_s.o _satfractUHQDQ_s.o _satfractUHQTQ_s.o _satfractUHQHA_s.o _satfractUHQSA_s.o _satfractUHQDA_s.o _satfractUHQTA_s.o _satfractUHQUQQ_s.o _satfractUHQUSQ_s.o _satfractUHQUDQ_s.o _satfractUHQUTQ_s.o _satfractUHQUHA_s.o _satfractUHQUSA_s.o _satfractUHQUDA_s.o _satfractUHQUTA_s.o _satfractUSQQQ_s.o _satfractUSQHQ_s.o _satfractUSQSQ_s.o _satfractUSQDQ_s.o _satfractUSQTQ_s.o _satfractUSQHA_s.o _satfractUSQSA_s.o _satfractUSQDA_s.o _satfractUSQTA_s.o _satfractUSQUQQ_s.o _satfractUSQUHQ_s.o _satfractUSQUDQ_s.o _satfractUSQUTQ_s.o _satfractUSQUHA_s.o _satfractUSQUSA_s.o _satfractUSQUDA_s.o _satfractUSQUTA_s.o _satfractUDQQQ_s.o _satfractUDQHQ_s.o _satfractUDQSQ_s.o _satfractUDQDQ_s.o _satfractUDQTQ_s.o _satfractUDQHA_s.o _satfractUDQSA_s.o _satfractUDQDA_s.o _satfractUDQTA_s.o _satfractUDQUQQ_s.o _satfractUDQUHQ_s.o _satfractUDQUSQ_s.o _satfractUDQUTQ_s.o _satfractUDQUHA_s.o _satfractUDQUSA_s.o _satfractUDQUDA_s.o _satfractUDQUTA_s.o _satfractUTQQQ_s.o _satfractUTQHQ_s.o _satfractUTQSQ_s.o _satfractUTQDQ_s.o _satfractUTQTQ_s.o _satfractUTQHA_s.o _satfractUTQSA_s.o _satfractUTQDA_s.o _satfractUTQTA_s.o _satfractUTQUQQ_s.o _satfractUTQUHQ_s.o _satfractUTQUSQ_s.o _satfractUTQUDQ_s.o _satfractUTQUHA_s.o _satfractUTQUSA_s.o _satfractUTQUDA_s.o _satfractUTQUTA_s.o _satfractUHAQQ_s.o _satfractUHAHQ_s.o _satfractUHASQ_s.o _satfractUHADQ_s.o _satfractUHATQ_s.o _satfractUHAHA_s.o _satfractUHASA_s.o _satfractUHADA_s.o _satfractUHATA_s.o _satfractUHAUQQ_s.o _satfractUHAUHQ_s.o _satfractUHAUSQ_s.o _satfractUHAUDQ_s.o _satfractUHAUTQ_s.o _satfractUHAUSA_s.o _satfractUHAUDA_s.o _satfractUHAUTA_s.o _satfractUSAQQ_s.o _satfractUSAHQ_s.o _satfractUSASQ_s.o _satfractUSADQ_s.o _satfractUSATQ_s.o _satfractUSAHA_s.o _satfractUSASA_s.o _satfractUSADA_s.o _satfractUSATA_s.o _satfractUSAUQQ_s.o _satfractUSAUHQ_s.o _satfractUSAUSQ_s.o _satfractUSAUDQ_s.o _satfractUSAUTQ_s.o _satfractUSAUHA_s.o _satfractUSAUDA_s.o _satfractUSAUTA_s.o _satfractUDAQQ_s.o _satfractUDAHQ_s.o _satfractUDASQ_s.o _satfractUDADQ_s.o _satfractUDATQ_s.o _satfractUDAHA_s.o _satfractUDASA_s.o _satfractUDADA_s.o _satfractUDATA_s.o _satfractUDAUQQ_s.o _satfractUDAUHQ_s.o _satfractUDAUSQ_s.o _satfractUDAUDQ_s.o _satfractUDAUTQ_s.o _satfractUDAUHA_s.o _satfractUDAUSA_s.o _satfractUDAUTA_s.o _satfractUTAQQ_s.o _satfractUTAHQ_s.o _satfractUTASQ_s.o _satfractUTADQ_s.o _satfractUTATQ_s.o _satfractUTAHA_s.o _satfractUTASA_s.o _satfractUTADA_s.o _satfractUTATA_s.o _satfractUTAUQQ_s.o _satfractUTAUHQ_s.o _satfractUTAUSQ_s.o _satfractUTAUDQ_s.o _satfractUTAUTQ_s.o _satfractUTAUHA_s.o _satfractUTAUSA_s.o _satfractUTAUDA_s.o _satfractQIQQ_s.o _satfractQIHQ_s.o _satfractQISQ_s.o _satfractQIDQ_s.o _satfractQITQ_s.o _satfractQIHA_s.o _satfractQISA_s.o _satfractQIDA_s.o _satfractQITA_s.o _satfractQIUQQ_s.o _satfractQIUHQ_s.o _satfractQIUSQ_s.o _satfractQIUDQ_s.o _satfractQIUTQ_s.o _satfractQIUHA_s.o _satfractQIUSA_s.o _satfractQIUDA_s.o _satfractQIUTA_s.o _satfractHIQQ_s.o _satfractHIHQ_s.o _satfractHISQ_s.o _satfractHIDQ_s.o _satfractHITQ_s.o _satfractHIHA_s.o _satfractHISA_s.o _satfractHIDA_s.o _satfractHITA_s.o _satfractHIUQQ_s.o _satfractHIUHQ_s.o _satfractHIUSQ_s.o _satfractHIUDQ_s.o _satfractHIUTQ_s.o _satfractHIUHA_s.o _satfractHIUSA_s.o _satfractHIUDA_s.o _satfractHIUTA_s.o _satfractSIQQ_s.o _satfractSIHQ_s.o _satfractSISQ_s.o _satfractSIDQ_s.o _satfractSITQ_s.o _satfractSIHA_s.o _satfractSISA_s.o _satfractSIDA_s.o _satfractSITA_s.o _satfractSIUQQ_s.o _satfractSIUHQ_s.o _satfractSIUSQ_s.o _satfractSIUDQ_s.o _satfractSIUTQ_s.o _satfractSIUHA_s.o _satfractSIUSA_s.o _satfractSIUDA_s.o _satfractSIUTA_s.o _satfractDIQQ_s.o _satfractDIHQ_s.o _satfractDISQ_s.o _satfractDIDQ_s.o _satfractDITQ_s.o _satfractDIHA_s.o _satfractDISA_s.o _satfractDIDA_s.o _satfractDITA_s.o _satfractDIUQQ_s.o _satfractDIUHQ_s.o _satfractDIUSQ_s.o _satfractDIUDQ_s.o _satfractDIUTQ_s.o _satfractDIUHA_s.o _satfractDIUSA_s.o _satfractDIUDA_s.o _satfractDIUTA_s.o _satfractTIQQ_s.o _satfractTIHQ_s.o _satfractTISQ_s.o _satfractTIDQ_s.o _satfractTITQ_s.o _satfractTIHA_s.o _satfractTISA_s.o _satfractTIDA_s.o _satfractTITA_s.o _satfractTIUQQ_s.o _satfractTIUHQ_s.o _satfractTIUSQ_s.o _satfractTIUDQ_s.o _satfractTIUTQ_s.o _satfractTIUHA_s.o _satfractTIUSA_s.o _satfractTIUDA_s.o _satfractTIUTA_s.o _satfractSFQQ_s.o _satfractSFHQ_s.o _satfractSFSQ_s.o _satfractSFDQ_s.o _satfractSFTQ_s.o _satfractSFHA_s.o _satfractSFSA_s.o _satfractSFDA_s.o _satfractSFTA_s.o _satfractSFUQQ_s.o _satfractSFUHQ_s.o _satfractSFUSQ_s.o _satfractSFUDQ_s.o _satfractSFUTQ_s.o _satfractSFUHA_s.o _satfractSFUSA_s.o _satfractSFUDA_s.o _satfractSFUTA_s.o _satfractDFQQ_s.o _satfractDFHQ_s.o _satfractDFSQ_s.o _satfractDFDQ_s.o _satfractDFTQ_s.o _satfractDFHA_s.o _satfractDFSA_s.o _satfractDFDA_s.o _satfractDFTA_s.o _satfractDFUQQ_s.o _satfractDFUHQ_s.o _satfractDFUSQ_s.o _satfractDFUDQ_s.o _satfractDFUTQ_s.o _satfractDFUHA_s.o _satfractDFUSA_s.o _satfractDFUDA_s.o _satfractDFUTA_s.o _fractunsQQUQI_s.o _fractunsQQUHI_s.o _fractunsQQUSI_s.o _fractunsQQUDI_s.o _fractunsQQUTI_s.o _fractunsHQUQI_s.o _fractunsHQUHI_s.o _fractunsHQUSI_s.o _fractunsHQUDI_s.o _fractunsHQUTI_s.o _fractunsSQUQI_s.o _fractunsSQUHI_s.o _fractunsSQUSI_s.o _fractunsSQUDI_s.o _fractunsSQUTI_s.o _fractunsDQUQI_s.o _fractunsDQUHI_s.o _fractunsDQUSI_s.o _fractunsDQUDI_s.o _fractunsDQUTI_s.o _fractunsTQUQI_s.o _fractunsTQUHI_s.o _fractunsTQUSI_s.o _fractunsTQUDI_s.o _fractunsTQUTI_s.o _fractunsHAUQI_s.o _fractunsHAUHI_s.o _fractunsHAUSI_s.o _fractunsHAUDI_s.o _fractunsHAUTI_s.o _fractunsSAUQI_s.o _fractunsSAUHI_s.o _fractunsSAUSI_s.o _fractunsSAUDI_s.o _fractunsSAUTI_s.o _fractunsDAUQI_s.o _fractunsDAUHI_s.o _fractunsDAUSI_s.o _fractunsDAUDI_s.o _fractunsDAUTI_s.o _fractunsTAUQI_s.o _fractunsTAUHI_s.o _fractunsTAUSI_s.o _fractunsTAUDI_s.o _fractunsTAUTI_s.o _fractunsUQQUQI_s.o _fractunsUQQUHI_s.o _fractunsUQQUSI_s.o _fractunsUQQUDI_s.o _fractunsUQQUTI_s.o _fractunsUHQUQI_s.o _fractunsUHQUHI_s.o _fractunsUHQUSI_s.o _fractunsUHQUDI_s.o _fractunsUHQUTI_s.o _fractunsUSQUQI_s.o _fractunsUSQUHI_s.o _fractunsUSQUSI_s.o _fractunsUSQUDI_s.o _fractunsUSQUTI_s.o _fractunsUDQUQI_s.o _fractunsUDQUHI_s.o _fractunsUDQUSI_s.o _fractunsUDQUDI_s.o _fractunsUDQUTI_s.o _fractunsUTQUQI_s.o _fractunsUTQUHI_s.o _fractunsUTQUSI_s.o _fractunsUTQUDI_s.o _fractunsUTQUTI_s.o _fractunsUHAUQI_s.o _fractunsUHAUHI_s.o _fractunsUHAUSI_s.o _fractunsUHAUDI_s.o _fractunsUHAUTI_s.o _fractunsUSAUQI_s.o _fractunsUSAUHI_s.o _fractunsUSAUSI_s.o _fractunsUSAUDI_s.o _fractunsUSAUTI_s.o _fractunsUDAUQI_s.o _fractunsUDAUHI_s.o _fractunsUDAUSI_s.o _fractunsUDAUDI_s.o _fractunsUDAUTI_s.o _fractunsUTAUQI_s.o _fractunsUTAUHI_s.o _fractunsUTAUSI_s.o _fractunsUTAUDI_s.o _fractunsUTAUTI_s.o _fractunsUQIQQ_s.o _fractunsUQIHQ_s.o _fractunsUQISQ_s.o _fractunsUQIDQ_s.o _fractunsUQITQ_s.o _fractunsUQIHA_s.o _fractunsUQISA_s.o _fractunsUQIDA_s.o _fractunsUQITA_s.o _fractunsUQIUQQ_s.o _fractunsUQIUHQ_s.o _fractunsUQIUSQ_s.o _fractunsUQIUDQ_s.o _fractunsUQIUTQ_s.o _fractunsUQIUHA_s.o _fractunsUQIUSA_s.o _fractunsUQIUDA_s.o _fractunsUQIUTA_s.o _fractunsUHIQQ_s.o _fractunsUHIHQ_s.o _fractunsUHISQ_s.o _fractunsUHIDQ_s.o _fractunsUHITQ_s.o _fractunsUHIHA_s.o _fractunsUHISA_s.o _fractunsUHIDA_s.o _fractunsUHITA_s.o _fractunsUHIUQQ_s.o _fractunsUHIUHQ_s.o _fractunsUHIUSQ_s.o _fractunsUHIUDQ_s.o _fractunsUHIUTQ_s.o _fractunsUHIUHA_s.o _fractunsUHIUSA_s.o _fractunsUHIUDA_s.o _fractunsUHIUTA_s.o _fractunsUSIQQ_s.o _fractunsUSIHQ_s.o _fractunsUSISQ_s.o _fractunsUSIDQ_s.o _fractunsUSITQ_s.o _fractunsUSIHA_s.o _fractunsUSISA_s.o _fractunsUSIDA_s.o _fractunsUSITA_s.o _fractunsUSIUQQ_s.o _fractunsUSIUHQ_s.o _fractunsUSIUSQ_s.o _fractunsUSIUDQ_s.o _fractunsUSIUTQ_s.o _fractunsUSIUHA_s.o _fractunsUSIUSA_s.o _fractunsUSIUDA_s.o _fractunsUSIUTA_s.o _fractunsUDIQQ_s.o _fractunsUDIHQ_s.o _fractunsUDISQ_s.o _fractunsUDIDQ_s.o _fractunsUDITQ_s.o _fractunsUDIHA_s.o _fractunsUDISA_s.o _fractunsUDIDA_s.o _fractunsUDITA_s.o _fractunsUDIUQQ_s.o _fractunsUDIUHQ_s.o _fractunsUDIUSQ_s.o _fractunsUDIUDQ_s.o _fractunsUDIUTQ_s.o _fractunsUDIUHA_s.o _fractunsUDIUSA_s.o _fractunsUDIUDA_s.o _fractunsUDIUTA_s.o _fractunsUTIQQ_s.o _fractunsUTIHQ_s.o _fractunsUTISQ_s.o _fractunsUTIDQ_s.o _fractunsUTITQ_s.o _fractunsUTIHA_s.o _fractunsUTISA_s.o _fractunsUTIDA_s.o _fractunsUTITA_s.o _fractunsUTIUQQ_s.o _fractunsUTIUHQ_s.o _fractunsUTIUSQ_s.o _fractunsUTIUDQ_s.o _fractunsUTIUTQ_s.o _fractunsUTIUHA_s.o _fractunsUTIUSA_s.o _fractunsUTIUDA_s.o _fractunsUTIUTA_s.o _satfractunsUQIQQ_s.o _satfractunsUQIHQ_s.o _satfractunsUQISQ_s.o _satfractunsUQIDQ_s.o _satfractunsUQITQ_s.o _satfractunsUQIHA_s.o _satfractunsUQISA_s.o _satfractunsUQIDA_s.o _satfractunsUQITA_s.o _satfractunsUQIUQQ_s.o _satfractunsUQIUHQ_s.o _satfractunsUQIUSQ_s.o _satfractunsUQIUDQ_s.o _satfractunsUQIUTQ_s.o _satfractunsUQIUHA_s.o _satfractunsUQIUSA_s.o _satfractunsUQIUDA_s.o _satfractunsUQIUTA_s.o _satfractunsUHIQQ_s.o _satfractunsUHIHQ_s.o _satfractunsUHISQ_s.o _satfractunsUHIDQ_s.o _satfractunsUHITQ_s.o _satfractunsUHIHA_s.o _satfractunsUHISA_s.o _satfractunsUHIDA_s.o _satfractunsUHITA_s.o _satfractunsUHIUQQ_s.o _satfractunsUHIUHQ_s.o _satfractunsUHIUSQ_s.o _satfractunsUHIUDQ_s.o _satfractunsUHIUTQ_s.o _satfractunsUHIUHA_s.o _satfractunsUHIUSA_s.o _satfractunsUHIUDA_s.o _satfractunsUHIUTA_s.o _satfractunsUSIQQ_s.o _satfractunsUSIHQ_s.o _satfractunsUSISQ_s.o _satfractunsUSIDQ_s.o _satfractunsUSITQ_s.o _satfractunsUSIHA_s.o _satfractunsUSISA_s.o"
# Doesn't work:
OBJS2="_fractSFTQ_s.o _fractSFHA_s.o _fractSFSA_s.o _fractSFDA_s.o _fractSFTA_s.o _fractSFUQQ_s.o _fractSFUHQ_s.o _fractSFUSQ_s.o _fractSFUDQ_s.o _fractSFUTQ_s.o _fractSFUHA_s.o _fractSFUSA_s.o _fractSFUDA_s.o _fractSFUTA_s.o _fractDFQQ_s.o _fractDFHQ_s.o _fractDFSQ_s.o _fractDFDQ_s.o _fractDFTQ_s.o _fractDFHA_s.o _fractDFSA_s.o _fractDFDA_s.o _fractDFTA_s.o _fractDFUQQ_s.o _fractDFUHQ_s.o _fractDFUSQ_s.o _fractDFUDQ_s.o _fractDFUTQ_s.o _fractDFUHA_s.o _fractDFUSA_s.o _fractDFUDA_s.o _fractDFUTA_s.o _satfractQQHQ_s.o _satfractQQSQ_s.o _satfractQQDQ_s.o _satfractQQTQ_s.o _satfractQQHA_s.o _satfractQQSA_s.o _satfractQQDA_s.o _satfractQQTA_s.o _satfractQQUQQ_s.o _satfractQQUHQ_s.o _satfractQQUSQ_s.o _satfractQQUDQ_s.o _satfractQQUTQ_s.o _satfractQQUHA_s.o _satfractQQUSA_s.o _satfractQQUDA_s.o _satfractQQUTA_s.o _satfractHQQQ_s.o _satfractHQSQ_s.o _satfractHQDQ_s.o _satfractHQTQ_s.o _satfractHQHA_s.o _satfractHQSA_s.o _satfractHQDA_s.o _satfractHQTA_s.o _satfractHQUQQ_s.o _satfractHQUHQ_s.o _satfractHQUSQ_s.o _satfractHQUDQ_s.o _satfractHQUTQ_s.o _satfractHQUHA_s.o _satfractHQUSA_s.o _satfractHQUDA_s.o _satfractHQUTA_s.o _satfractSQQQ_s.o _satfractSQHQ_s.o _satfractSQDQ_s.o _satfractSQTQ_s.o _satfractSQHA_s.o _satfractSQSA_s.o _satfractSQDA_s.o _satfractSQTA_s.o _satfractSQUQQ_s.o _satfractSQUHQ_s.o _satfractSQUSQ_s.o _satfractSQUDQ_s.o _satfractSQUTQ_s.o _satfractSQUHA_s.o _satfractSQUSA_s.o _satfractSQUDA_s.o _satfractSQUTA_s.o _satfractDQQQ_s.o _satfractDQHQ_s.o _satfractDQSQ_s.o _satfractDQTQ_s.o _satfractDQHA_s.o _satfractDQSA_s.o _satfractDQDA_s.o _satfractDQTA_s.o _satfractDQUQQ_s.o _satfractDQUHQ_s.o _satfractDQUSQ_s.o _satfractDQUDQ_s.o _satfractDQUTQ_s.o _satfractDQUHA_s.o _satfractDQUSA_s.o _satfractDQUDA_s.o _satfractDQUTA_s.o _satfractTQQQ_s.o _satfractTQHQ_s.o _satfractTQSQ_s.o _satfractTQDQ_s.o _satfractTQHA_s.o _satfractTQSA_s.o _satfractTQDA_s.o _satfractTQTA_s.o _satfractTQUQQ_s.o _satfractTQUHQ_s.o _satfractTQUSQ_s.o _satfractTQUDQ_s.o _satfractTQUTQ_s.o _satfractTQUHA_s.o _satfractTQUSA_s.o _satfractTQUDA_s.o _satfractTQUTA_s.o _satfractHAQQ_s.o _satfractHAHQ_s.o _satfractHASQ_s.o _satfractHADQ_s.o _satfractHATQ_s.o _satfractHASA_s.o _satfractHADA_s.o _satfractHATA_s.o _satfractHAUQQ_s.o _satfractHAUHQ_s.o _satfractHAUSQ_s.o _satfractHAUDQ_s.o _satfractHAUTQ_s.o _satfractHAUHA_s.o _satfractHAUSA_s.o _satfractHAUDA_s.o _satfractHAUTA_s.o _satfractSAQQ_s.o _satfractSAHQ_s.o _satfractSASQ_s.o _satfractSADQ_s.o _satfractSATQ_s.o _satfractSAHA_s.o _satfractSADA_s.o _satfractSATA_s.o _satfractSAUQQ_s.o _satfractSAUHQ_s.o _satfractSAUSQ_s.o _satfractSAUDQ_s.o _satfractSAUTQ_s.o _satfractSAUHA_s.o _satfractSAUSA_s.o _satfractSAUDA_s.o _satfractSAUTA_s.o _satfractDAQQ_s.o _satfractDAHQ_s.o _satfractDASQ_s.o _satfractDADQ_s.o _satfractDATQ_s.o _satfractDAHA_s.o _satfractDASA_s.o _satfractDATA_s.o _satfractDAUQQ_s.o _satfractDAUHQ_s.o _satfractDAUSQ_s.o _satfractDAUDQ_s.o _satfractDAUTQ_s.o _satfractDAUHA_s.o _satfractDAUSA_s.o _satfractDAUDA_s.o _satfractDAUTA_s.o _satfractTAQQ_s.o _satfractTAHQ_s.o _satfractTASQ_s.o _satfractTADQ_s.o _satfractTATQ_s.o _satfractTAHA_s.o _satfractTASA_s.o _satfractTADA_s.o _satfractTAUQQ_s.o _satfractTAUHQ_s.o _satfractTAUSQ_s.o _satfractTAUDQ_s.o _satfractTAUTQ_s.o _satfractTAUHA_s.o _satfractTAUSA_s.o _satfractTAUDA_s.o _satfractTAUTA_s.o _satfractUQQQQ_s.o _satfractUQQHQ_s.o _satfractUQQSQ_s.o _satfractUQQDQ_s.o _satfractUQQTQ_s.o _satfractUQQHA_s.o _satfractUQQSA_s.o _satfractUQQDA_s.o _satfractUQQTA_s.o _satfractUQQUHQ_s.o _satfractUQQUSQ_s.o _satfractUQQUDQ_s.o _satfractUQQUTQ_s.o _satfractUQQUHA_s.o _satfractUQQUSA_s.o _satfractUQQUDA_s.o _satfractUQQUTA_s.o _satfractUHQQQ_s.o _satfractUHQHQ_s.o _satfractUHQSQ_s.o _satfractUHQDQ_s.o _satfractUHQTQ_s.o _satfractUHQHA_s.o _satfractUHQSA_s.o _satfractUHQDA_s.o _satfractUHQTA_s.o _satfractUHQUQQ_s.o _satfractUHQUSQ_s.o _satfractUHQUDQ_s.o _satfractUHQUTQ_s.o _satfractUHQUHA_s.o _satfractUHQUSA_s.o _satfractUHQUDA_s.o _satfractUHQUTA_s.o _satfractUSQQQ_s.o _satfractUSQHQ_s.o _satfractUSQSQ_s.o _satfractUSQDQ_s.o _satfractUSQTQ_s.o _satfractUSQHA_s.o _satfractUSQSA_s.o _satfractUSQDA_s.o _satfractUSQTA_s.o _satfractUSQUQQ_s.o _satfractUSQUHQ_s.o _satfractUSQUDQ_s.o _satfractUSQUTQ_s.o _satfractUSQUHA_s.o _satfractUSQUSA_s.o _satfractUSQUDA_s.o _satfractUSQUTA_s.o _satfractUDQQQ_s.o _satfractUDQHQ_s.o _satfractUDQSQ_s.o _satfractUDQDQ_s.o _satfractUDQTQ_s.o _satfractUDQHA_s.o _satfractUDQSA_s.o _satfractUDQDA_s.o _satfractUDQTA_s.o _satfractUDQUQQ_s.o _satfractUDQUHQ_s.o _satfractUDQUSQ_s.o _satfractUDQUTQ_s.o _satfractUDQUHA_s.o _satfractUDQUSA_s.o _satfractUDQUDA_s.o _satfractUDQUTA_s.o _satfractUTQQQ_s.o _satfractUTQHQ_s.o _satfractUTQSQ_s.o _satfractUTQDQ_s.o _satfractUTQTQ_s.o _satfractUTQHA_s.o _satfractUTQSA_s.o _satfractUTQDA_s.o _satfractUTQTA_s.o _satfractUTQUQQ_s.o _satfractUTQUHQ_s.o _satfractUTQUSQ_s.o _satfractUTQUDQ_s.o _satfractUTQUHA_s.o _satfractUTQUSA_s.o _satfractUTQUDA_s.o _satfractUTQUTA_s.o _satfractUHAQQ_s.o _satfractUHAHQ_s.o _satfractUHASQ_s.o _satfractUHADQ_s.o _satfractUHATQ_s.o _satfractUHAHA_s.o _satfractUHASA_s.o _satfractUHADA_s.o _satfractUHATA_s.o _satfractUHAUQQ_s.o _satfractUHAUHQ_s.o _satfractUHAUSQ_s.o _satfractUHAUDQ_s.o _satfractUHAUTQ_s.o _satfractUHAUSA_s.o _satfractUHAUDA_s.o _satfractUHAUTA_s.o _satfractUSAQQ_s.o _satfractUSAHQ_s.o _satfractUSASQ_s.o _satfractUSADQ_s.o _satfractUSATQ_s.o _satfractUSAHA_s.o _satfractUSASA_s.o _satfractUSADA_s.o _satfractUSATA_s.o _satfractUSAUQQ_s.o _satfractUSAUHQ_s.o _satfractUSAUSQ_s.o _satfractUSAUDQ_s.o _satfractUSAUTQ_s.o _satfractUSAUHA_s.o _satfractUSAUDA_s.o _satfractUSAUTA_s.o _satfractUDAQQ_s.o _satfractUDAHQ_s.o _satfractUDASQ_s.o _satfractUDADQ_s.o _satfractUDATQ_s.o _satfractUDAHA_s.o _satfractUDASA_s.o _satfractUDADA_s.o _satfractUDATA_s.o _satfractUDAUQQ_s.o _satfractUDAUHQ_s.o _satfractUDAUSQ_s.o _satfractUDAUDQ_s.o _satfractUDAUTQ_s.o _satfractUDAUHA_s.o _satfractUDAUSA_s.o _satfractUDAUTA_s.o _satfractUTAQQ_s.o _satfractUTAHQ_s.o _satfractUTASQ_s.o _satfractUTADQ_s.o _satfractUTATQ_s.o _satfractUTAHA_s.o _satfractUTASA_s.o _satfractUTADA_s.o _satfractUTATA_s.o _satfractUTAUQQ_s.o _satfractUTAUHQ_s.o _satfractUTAUSQ_s.o _satfractUTAUDQ_s.o _satfractUTAUTQ_s.o _satfractUTAUHA_s.o _satfractUTAUSA_s.o _satfractUTAUDA_s.o _satfractQIQQ_s.o _satfractQIHQ_s.o _satfractQISQ_s.o _satfractQIDQ_s.o _satfractQITQ_s.o _satfractQIHA_s.o _satfractQISA_s.o _satfractQIDA_s.o _satfractQITA_s.o _satfractQIUQQ_s.o _satfractQIUHQ_s.o _satfractQIUSQ_s.o _satfractQIUDQ_s.o _satfractQIUTQ_s.o _satfractQIUHA_s.o _satfractQIUSA_s.o _satfractQIUDA_s.o _satfractQIUTA_s.o _satfractHIQQ_s.o _satfractHIHQ_s.o _satfractHISQ_s.o _satfractHIDQ_s.o _satfractHITQ_s.o _satfractHIHA_s.o _satfractHISA_s.o _satfractHIDA_s.o _satfractHITA_s.o _satfractHIUQQ_s.o _satfractHIUHQ_s.o _satfractHIUSQ_s.o _satfractHIUDQ_s.o _satfractHIUTQ_s.o _satfractHIUHA_s.o _satfractHIUSA_s.o _satfractHIUDA_s.o _satfractHIUTA_s.o _satfractSIQQ_s.o _satfractSIHQ_s.o _satfractSISQ_s.o _satfractSIDQ_s.o _satfractSITQ_s.o _satfractSIHA_s.o _satfractSISA_s.o _satfractSIDA_s.o _satfractSITA_s.o _satfractSIUQQ_s.o _satfractSIUHQ_s.o _satfractSIUSQ_s.o _satfractSIUDQ_s.o _satfractSIUTQ_s.o _satfractSIUHA_s.o _satfractSIUSA_s.o _satfractSIUDA_s.o _satfractSIUTA_s.o _satfractDIQQ_s.o _satfractDIHQ_s.o _satfractDISQ_s.o _satfractDIDQ_s.o _satfractDITQ_s.o _satfractDIHA_s.o _satfractDISA_s.o _satfractDIDA_s.o _satfractDITA_s.o _satfractDIUQQ_s.o _satfractDIUHQ_s.o _satfractDIUSQ_s.o _satfractDIUDQ_s.o _satfractDIUTQ_s.o _satfractDIUHA_s.o _satfractDIUSA_s.o _satfractDIUDA_s.o _satfractDIUTA_s.o _satfractTIQQ_s.o _satfractTIHQ_s.o _satfractTISQ_s.o _satfractTIDQ_s.o _satfractTITQ_s.o _satfractTIHA_s.o _satfractTISA_s.o _satfractTIDA_s.o _satfractTITA_s.o _satfractTIUQQ_s.o _satfractTIUHQ_s.o _satfractTIUSQ_s.o _satfractTIUDQ_s.o _satfractTIUTQ_s.o _satfractTIUHA_s.o _satfractTIUSA_s.o _satfractTIUDA_s.o _satfractTIUTA_s.o _satfractSFQQ_s.o _satfractSFHQ_s.o _satfractSFSQ_s.o _satfractSFDQ_s.o _satfractSFTQ_s.o _satfractSFHA_s.o _satfractSFSA_s.o _satfractSFDA_s.o _satfractSFTA_s.o _satfractSFUQQ_s.o _satfractSFUHQ_s.o _satfractSFUSQ_s.o _satfractSFUDQ_s.o _satfractSFUTQ_s.o _satfractSFUHA_s.o _satfractSFUSA_s.o _satfractSFUDA_s.o _satfractSFUTA_s.o _satfractDFQQ_s.o _satfractDFHQ_s.o _satfractDFSQ_s.o _satfractDFDQ_s.o _satfractDFTQ_s.o _satfractDFHA_s.o _satfractDFSA_s.o _satfractDFDA_s.o _satfractDFTA_s.o _satfractDFUQQ_s.o _satfractDFUHQ_s.o _satfractDFUSQ_s.o _satfractDFUDQ_s.o _satfractDFUTQ_s.o _satfractDFUHA_s.o _satfractDFUSA_s.o _satfractDFUDA_s.o _satfractDFUTA_s.o _fractunsQQUQI_s.o _fractunsQQUHI_s.o _fractunsQQUSI_s.o _fractunsQQUDI_s.o _fractunsQQUTI_s.o _fractunsHQUQI_s.o _fractunsHQUHI_s.o _fractunsHQUSI_s.o _fractunsHQUDI_s.o _fractunsHQUTI_s.o _fractunsSQUQI_s.o _fractunsSQUHI_s.o _fractunsSQUSI_s.o _fractunsSQUDI_s.o _fractunsSQUTI_s.o _fractunsDQUQI_s.o _fractunsDQUHI_s.o _fractunsDQUSI_s.o _fractunsDQUDI_s.o _fractunsDQUTI_s.o _fractunsTQUQI_s.o _fractunsTQUHI_s.o _fractunsTQUSI_s.o _fractunsTQUDI_s.o _fractunsTQUTI_s.o _fractunsHAUQI_s.o _fractunsHAUHI_s.o _fractunsHAUSI_s.o _fractunsHAUDI_s.o _fractunsHAUTI_s.o _fractunsSAUQI_s.o _fractunsSAUHI_s.o _fractunsSAUSI_s.o _fractunsSAUDI_s.o _fractunsSAUTI_s.o _fractunsDAUQI_s.o _fractunsDAUHI_s.o _fractunsDAUSI_s.o _fractunsDAUDI_s.o _fractunsDAUTI_s.o _fractunsTAUQI_s.o _fractunsTAUHI_s.o _fractunsTAUSI_s.o _fractunsTAUDI_s.o _fractunsTAUTI_s.o _fractunsUQQUQI_s.o _fractunsUQQUHI_s.o _fractunsUQQUSI_s.o _fractunsUQQUDI_s.o _fractunsUQQUTI_s.o _fractunsUHQUQI_s.o _fractunsUHQUHI_s.o _fractunsUHQUSI_s.o _fractunsUHQUDI_s.o _fractunsUHQUTI_s.o _fractunsUSQUQI_s.o _fractunsUSQUHI_s.o _fractunsUSQUSI_s.o _fractunsUSQUDI_s.o _fractunsUSQUTI_s.o _fractunsUDQUQI_s.o _fractunsUDQUHI_s.o _fractunsUDQUSI_s.o _fractunsUDQUDI_s.o _fractunsUDQUTI_s.o _fractunsUTQUQI_s.o _fractunsUTQUHI_s.o _fractunsUTQUSI_s.o _fractunsUTQUDI_s.o _fractunsUTQUTI_s.o _fractunsUHAUQI_s.o _fractunsUHAUHI_s.o _fractunsUHAUSI_s.o _fractunsUHAUDI_s.o _fractunsUHAUTI_s.o _fractunsUSAUQI_s.o _fractunsUSAUHI_s.o _fractunsUSAUSI_s.o _fractunsUSAUDI_s.o _fractunsUSAUTI_s.o _fractunsUDAUQI_s.o _fractunsUDAUHI_s.o _fractunsUDAUSI_s.o _fractunsUDAUDI_s.o _fractunsUDAUTI_s.o _fractunsUTAUQI_s.o _fractunsUTAUHI_s.o _fractunsUTAUSI_s.o _fractunsUTAUDI_s.o _fractunsUTAUTI_s.o _fractunsUQIQQ_s.o _fractunsUQIHQ_s.o _fractunsUQISQ_s.o _fractunsUQIDQ_s.o _fractunsUQITQ_s.o _fractunsUQIHA_s.o _fractunsUQISA_s.o _fractunsUQIDA_s.o _fractunsUQITA_s.o _fractunsUQIUQQ_s.o _fractunsUQIUHQ_s.o _fractunsUQIUSQ_s.o _fractunsUQIUDQ_s.o _fractunsUQIUTQ_s.o _fractunsUQIUHA_s.o _fractunsUQIUSA_s.o _fractunsUQIUDA_s.o _fractunsUQIUTA_s.o _fractunsUHIQQ_s.o _fractunsUHIHQ_s.o _fractunsUHISQ_s.o _fractunsUHIDQ_s.o _fractunsUHITQ_s.o _fractunsUHIHA_s.o _fractunsUHISA_s.o _fractunsUHIDA_s.o _fractunsUHITA_s.o _fractunsUHIUQQ_s.o _fractunsUHIUHQ_s.o _fractunsUHIUSQ_s.o _fractunsUHIUDQ_s.o _fractunsUHIUTQ_s.o _fractunsUHIUHA_s.o _fractunsUHIUSA_s.o _fractunsUHIUDA_s.o _fractunsUHIUTA_s.o _fractunsUSIQQ_s.o _fractunsUSIHQ_s.o _fractunsUSISQ_s.o _fractunsUSIDQ_s.o _fractunsUSITQ_s.o _fractunsUSIHA_s.o _fractunsUSISA_s.o _fractunsUSIDA_s.o _fractunsUSITA_s.o _fractunsUSIUQQ_s.o _fractunsUSIUHQ_s.o _fractunsUSIUSQ_s.o _fractunsUSIUDQ_s.o _fractunsUSIUTQ_s.o _fractunsUSIUHA_s.o _fractunsUSIUSA_s.o _fractunsUSIUDA_s.o _fractunsUSIUTA_s.o _fractunsUDIQQ_s.o _fractunsUDIHQ_s.o _fractunsUDISQ_s.o _fractunsUDIDQ_s.o _fractunsUDITQ_s.o _fractunsUDIHA_s.o _fractunsUDISA_s.o _fractunsUDIDA_s.o _fractunsUDITA_s.o _fractunsUDIUQQ_s.o _fractunsUDIUHQ_s.o _fractunsUDIUSQ_s.o _fractunsUDIUDQ_s.o _fractunsUDIUTQ_s.o _fractunsUDIUHA_s.o _fractunsUDIUSA_s.o _fractunsUDIUDA_s.o _fractunsUDIUTA_s.o _fractunsUTIQQ_s.o _fractunsUTIHQ_s.o _fractunsUTISQ_s.o _fractunsUTIDQ_s.o _fractunsUTITQ_s.o _fractunsUTIHA_s.o _fractunsUTISA_s.o _fractunsUTIDA_s.o _fractunsUTITA_s.o _fractunsUTIUQQ_s.o _fractunsUTIUHQ_s.o _fractunsUTIUSQ_s.o _fractunsUTIUDQ_s.o _fractunsUTIUTQ_s.o _fractunsUTIUHA_s.o _fractunsUTIUSA_s.o _fractunsUTIUDA_s.o _fractunsUTIUTA_s.o _satfractunsUQIQQ_s.o _satfractunsUQIHQ_s.o _satfractunsUQISQ_s.o _satfractunsUQIDQ_s.o _satfractunsUQITQ_s.o _satfractunsUQIHA_s.o _satfractunsUQISA_s.o _satfractunsUQIDA_s.o _satfractunsUQITA_s.o _satfractunsUQIUQQ_s.o _satfractunsUQIUHQ_s.o _satfractunsUQIUSQ_s.o _satfractunsUQIUDQ_s.o _satfractunsUQIUTQ_s.o _satfractunsUQIUHA_s.o _satfractunsUQIUSA_s.o _satfractunsUQIUDA_s.o _satfractunsUQIUTA_s.o _satfractunsUHIQQ_s.o _satfractunsUHIHQ_s.o _satfractunsUHISQ_s.o _satfractunsUHIDQ_s.o _satfractunsUHITQ_s.o _satfractunsUHIHA_s.o _satfractunsUHISA_s.o _satfractunsUHIDA_s.o _satfractunsUHITA_s.o _satfractunsUHIUQQ_s.o _satfractunsUHIUHQ_s.o _satfractunsUHIUSQ_s.o _satfractunsUHIUDQ_s.o _satfractunsUHIUTQ_s.o _satfractunsUHIUHA_s.o _satfractunsUHIUSA_s.o _satfractunsUHIUDA_s.o _satfractunsUHIUTA_s.o _satfractunsUSIQQ_s.o _satfractunsUSIHQ_s.o _satfractunsUSISQ_s.o _satfractunsUSIDQ_s.o _satfractunsUSITQ_s.o _satfractunsUSIHA_s.o _satfractunsUSISA_s.o _satfractunsUSIDA_s.o"

/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-cc-gcc-core-pass-2/./gcc/xgcc -B/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-cc-gcc-core-pass-2/./gcc/ -B/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/armv6hl-unknown-linux-gnueabi/bin/ -B/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/armv6hl-unknown-linux-gnueabi/lib/ -isystem /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/armv6hl-unknown-linux-gnueabi/include -isystem /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/armv6hl-unknown-linux-gnueabi/sys-include    -O2  -DIN_GCC -DCROSS_DIRECTORY_STRUCTURE  -W -Wall -Wno-narrowing -Wwrite-strings -Wcast-qual -Wstrict-prototypes -Wmissing-prototypes -Wold-style-definition  -isystem ./include   -fPIC -fno-inline -g -DIN_LIBGCC2 -fbuilding-libgcc -fno-stack-protector  -shared -nodefaultlibs -Wl,--soname=libgcc_s.so.1 -Wl,--version-script=libgcc.map -o ./libgcc_s.so.1.tmp -g -Os -B./ $OBJS $OBJS2 libgcc.a -lc 

echo "/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-cc-gcc-core-pass-2/./gcc/xgcc -B/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-cc-gcc-core-pass-2/./gcc/ -B/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/armv6hl-unknown-linux-gnueabi/bin/ -B/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/armv6hl-unknown-linux-gnueabi/lib/ -isystem /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/armv6hl-unknown-linux-gnueabi/include -isystem /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/armv6hl-unknown-linux-gnueabi/sys-include    -O2  -DIN_GCC -DCROSS_DIRECTORY_STRUCTURE  -W -Wall -Wno-narrowing -Wwrite-strings -Wcast-qual -Wstrict-prototypes -Wmissing-prototypes -Wold-style-definition  -isystem ./include   -fPIC -fno-inline -g -DIN_LIBGCC2 -fbuilding-libgcc -fno-stack-protector  -shared -nodefaultlibs -Wl,--soname=libgcc_s.so.1 -Wl,--version-script=libgcc.map -o ./libgcc_s.so.1.tmp -g -Os -B./ _thumb1_case_sqi_s.o _thumb1_case_uqi_s.o _thumb1_case_shi_s.o _thumb1_case_uhi_s.o _thumb1_case_si_s.o _udivsi3_s.o _divsi3_s.o _umodsi3_s.o _modsi3_s.o _bb_init_func_s.o _call_via_rX_s.o _interwork_call_via_rX_s.o _lshrdi3_s.o _ashrdi3_s.o _ashldi3_s.o _arm_negdf2_s.o _arm_addsubdf3_s.o _arm_muldivdf3_s.o _arm_cmpdf2_s.o _arm_unorddf2_s.o _arm_fixdfsi_s.o _arm_fixunsdfsi_s.o _arm_truncdfsf2_s.o _arm_negsf2_s.o _arm_addsubsf3_s.o _arm_muldivsf3_s.o _arm_cmpsf2_s.o _arm_unordsf2_s.o _arm_fixsfsi_s.o _arm_fixunssfsi_s.o _arm_floatdidf_s.o _arm_floatdisf_s.o _arm_floatundidf_s.o _arm_floatundisf_s.o _clzsi2_s.o _clzdi2_s.o _ctzsi2_s.o _aeabi_lcmp_s.o _aeabi_ulcmp_s.o _aeabi_ldivmod_s.o _aeabi_uldivmod_s.o _dvmd_lnx_s.o _clear_cache_s.o _muldi3_s.o _negdi2_s.o _cmpdi2_s.o _ucmpdi2_s.o _trampoline_s.o __main_s.o _absvsi2_s.o _absvdi2_s.o _addvsi3_s.o _addvdi3_s.o _subvsi3_s.o _subvdi3_s.o _mulvsi3_s.o _mulvdi3_s.o _negvsi2_s.o _negvdi2_s.o _ctors_s.o _ffssi2_s.o _ffsdi2_s.o _clz_s.o _ctzdi2_s.o _popcount_tab_s.o _popcountsi2_s.o _popcountdi2_s.o _paritysi2_s.o _paritydi2_s.o _powisf2_s.o _powidf2_s.o _powixf2_s.o _powitf2_s.o _mulsc3_s.o _muldc3_s.o _mulxc3_s.o _multc3_s.o _divsc3_s.o _divdc3_s.o _divxc3_s.o _divtc3_s.o _bswapsi2_s.o _bswapdi2_s.o _clrsbsi2_s.o _clrsbdi2_s.o _fixunssfsi_s.o _fixunsdfsi_s.o _fixunsxfsi_s.o _fixsfdi_s.o _fixdfdi_s.o _fixxfdi_s.o _fixtfdi_s.o _fixunssfdi_s.o _fixunsdfdi_s.o _fixunsxfdi_s.o _fixunstfdi_s.o _floatdisf_s.o _floatdidf_s.o _floatdixf_s.o _floatditf_s.o _floatundisf_s.o _floatundidf_s.o _floatundixf_s.o _floatunditf_s.o _divdi3_s.o _moddi3_s.o _udivdi3_s.o _umoddi3_s.o _udiv_w_sdiv_s.o _udivmoddi4_s.o _addQQ_s.o _addHQ_s.o _addSQ_s.o _addDQ_s.o _addTQ_s.o _addHA_s.o _addSA_s.o _addDA_s.o _addTA_s.o _addUQQ_s.o _addUHQ_s.o _addUSQ_s.o _addUDQ_s.o _addUTQ_s.o _addUHA_s.o _addUSA_s.o _addUDA_s.o _addUTA_s.o _subQQ_s.o _subHQ_s.o _subSQ_s.o _subDQ_s.o _subTQ_s.o _subHA_s.o _subSA_s.o _subDA_s.o _subTA_s.o _subUQQ_s.o _subUHQ_s.o _subUSQ_s.o _subUDQ_s.o _subUTQ_s.o _subUHA_s.o _subUSA_s.o _subUDA_s.o _subUTA_s.o _negQQ_s.o _negHQ_s.o _negSQ_s.o _negDQ_s.o _negTQ_s.o _negHA_s.o _negSA_s.o _negDA_s.o _negTA_s.o _negUQQ_s.o _negUHQ_s.o _negUSQ_s.o _negUDQ_s.o _negUTQ_s.o _negUHA_s.o _negUSA_s.o _negUDA_s.o _negUTA_s.o _mulQQ_s.o _mulHQ_s.o _mulSQ_s.o _mulDQ_s.o _mulTQ_s.o _mulHA_s.o _mulSA_s.o _mulDA_s.o _mulTA_s.o _mulUQQ_s.o _mulUHQ_s.o _mulUSQ_s.o _mulUDQ_s.o _mulUTQ_s.o _mulUHA_s.o _mulUSA_s.o _mulUDA_s.o _mulUTA_s.o _mulhelperQQ_s.o _mulhelperHQ_s.o _mulhelperSQ_s.o _mulhelperDQ_s.o _mulhelperTQ_s.o _mulhelperHA_s.o _mulhelperSA_s.o _mulhelperDA_s.o _mulhelperTA_s.o _mulhelperUQQ_s.o _mulhelperUHQ_s.o _mulhelperUSQ_s.o _mulhelperUDQ_s.o _mulhelperUTQ_s.o _mulhelperUHA_s.o _mulhelperUSA_s.o _mulhelperUDA_s.o _mulhelperUTA_s.o _divhelperQQ_s.o _divhelperHQ_s.o _divhelperSQ_s.o _divhelperDQ_s.o _divhelperTQ_s.o _divhelperHA_s.o _divhelperSA_s.o _divhelperDA_s.o _divhelperTA_s.o _divhelperUQQ_s.o _divhelperUHQ_s.o _divhelperUSQ_s.o _divhelperUDQ_s.o _divhelperUTQ_s.o _divhelperUHA_s.o _divhelperUSA_s.o _divhelperUDA_s.o _divhelperUTA_s.o _ashlQQ_s.o _ashlHQ_s.o _ashlSQ_s.o _ashlDQ_s.o _ashlTQ_s.o _ashlHA_s.o _ashlSA_s.o _ashlDA_s.o _ashlTA_s.o _ashlUQQ_s.o _ashlUHQ_s.o _ashlUSQ_s.o _ashlUDQ_s.o _ashlUTQ_s.o _ashlUHA_s.o _ashlUSA_s.o _ashlUDA_s.o _ashlUTA_s.o _ashlhelperQQ_s.o _ashlhelperHQ_s.o _ashlhelperSQ_s.o _ashlhelperDQ_s.o _ashlhelperTQ_s.o _ashlhelperHA_s.o _ashlhelperSA_s.o _ashlhelperDA_s.o _ashlhelperTA_s.o _ashlhelperUQQ_s.o _ashlhelperUHQ_s.o _ashlhelperUSQ_s.o _ashlhelperUDQ_s.o _ashlhelperUTQ_s.o _ashlhelperUHA_s.o _ashlhelperUSA_s.o _ashlhelperUDA_s.o _ashlhelperUTA_s.o _cmpQQ_s.o _cmpHQ_s.o _cmpSQ_s.o _cmpDQ_s.o _cmpTQ_s.o _cmpHA_s.o _cmpSA_s.o _cmpDA_s.o _cmpTA_s.o _cmpUQQ_s.o _cmpUHQ_s.o _cmpUSQ_s.o _cmpUDQ_s.o _cmpUTQ_s.o _cmpUHA_s.o _cmpUSA_s.o _cmpUDA_s.o _cmpUTA_s.o _saturate1QQ_s.o _saturate1HQ_s.o _saturate1SQ_s.o _saturate1DQ_s.o _saturate1TQ_s.o _saturate1HA_s.o _saturate1SA_s.o _saturate1DA_s.o _saturate1TA_s.o _saturate1UQQ_s.o _saturate1UHQ_s.o _saturate1USQ_s.o _saturate1UDQ_s.o _saturate1UTQ_s.o _saturate1UHA_s.o _saturate1USA_s.o _saturate1UDA_s.o _saturate1UTA_s.o _saturate2QQ_s.o _saturate2HQ_s.o _saturate2SQ_s.o _saturate2DQ_s.o _saturate2TQ_s.o _saturate2HA_s.o _saturate2SA_s.o _saturate2DA_s.o _saturate2TA_s.o _saturate2UQQ_s.o _saturate2UHQ_s.o _saturate2USQ_s.o _saturate2UDQ_s.o _saturate2UTQ_s.o _saturate2UHA_s.o _saturate2USA_s.o _saturate2UDA_s.o _saturate2UTA_s.o _ssaddQQ_s.o _ssaddHQ_s.o _ssaddSQ_s.o _ssaddDQ_s.o _ssaddTQ_s.o _ssaddHA_s.o _ssaddSA_s.o _ssaddDA_s.o _ssaddTA_s.o _sssubQQ_s.o _sssubHQ_s.o _sssubSQ_s.o _sssubDQ_s.o _sssubTQ_s.o _sssubHA_s.o _sssubSA_s.o _sssubDA_s.o _sssubTA_s.o _ssnegQQ_s.o _ssnegHQ_s.o _ssnegSQ_s.o _ssnegDQ_s.o _ssnegTQ_s.o _ssnegHA_s.o _ssnegSA_s.o _ssnegDA_s.o _ssnegTA_s.o _ssmulQQ_s.o _ssmulHQ_s.o _ssmulSQ_s.o _ssmulDQ_s.o _ssmulTQ_s.o _ssmulHA_s.o _ssmulSA_s.o _ssmulDA_s.o _ssmulTA_s.o _ssdivQQ_s.o _ssdivHQ_s.o _ssdivSQ_s.o _ssdivDQ_s.o _ssdivTQ_s.o _ssdivHA_s.o _ssdivSA_s.o _ssdivDA_s.o _ssdivTA_s.o _divQQ_s.o _divHQ_s.o _divSQ_s.o _divDQ_s.o _divTQ_s.o _divHA_s.o _divSA_s.o _divDA_s.o _divTA_s.o _ssashlQQ_s.o _ssashlHQ_s.o _ssashlSQ_s.o _ssashlDQ_s.o _ssashlTQ_s.o _ssashlHA_s.o _ssashlSA_s.o _ssashlDA_s.o _ssashlTA_s.o _ashrQQ_s.o _ashrHQ_s.o _ashrSQ_s.o _ashrDQ_s.o _ashrTQ_s.o _ashrHA_s.o _ashrSA_s.o _ashrDA_s.o _ashrTA_s.o _usaddUQQ_s.o _usaddUHQ_s.o _usaddUSQ_s.o _usaddUDQ_s.o _usaddUTQ_s.o _usaddUHA_s.o _usaddUSA_s.o _usaddUDA_s.o _usaddUTA_s.o _ussubUQQ_s.o _ussubUHQ_s.o _ussubUSQ_s.o _ussubUDQ_s.o _ussubUTQ_s.o _ussubUHA_s.o _ussubUSA_s.o _ussubUDA_s.o _ussubUTA_s.o _usnegUQQ_s.o _usnegUHQ_s.o _usnegUSQ_s.o _usnegUDQ_s.o _usnegUTQ_s.o _usnegUHA_s.o _usnegUSA_s.o _usnegUDA_s.o _usnegUTA_s.o _usmulUQQ_s.o _usmulUHQ_s.o _usmulUSQ_s.o _usmulUDQ_s.o _usmulUTQ_s.o _usmulUHA_s.o _usmulUSA_s.o _usmulUDA_s.o _usmulUTA_s.o _usdivUQQ_s.o _usdivUHQ_s.o _usdivUSQ_s.o _usdivUDQ_s.o _usdivUTQ_s.o _usdivUHA_s.o _usdivUSA_s.o _usdivUDA_s.o _usdivUTA_s.o _udivUQQ_s.o _udivUHQ_s.o _udivUSQ_s.o _udivUDQ_s.o _udivUTQ_s.o _udivUHA_s.o _udivUSA_s.o _udivUDA_s.o _udivUTA_s.o _usashlUQQ_s.o _usashlUHQ_s.o _usashlUSQ_s.o _usashlUDQ_s.o _usashlUTQ_s.o _usashlUHA_s.o _usashlUSA_s.o _usashlUDA_s.o _usashlUTA_s.o _lshrUQQ_s.o _lshrUHQ_s.o _lshrUSQ_s.o _lshrUDQ_s.o _lshrUTQ_s.o _lshrUHA_s.o _lshrUSA_s.o _lshrUDA_s.o _lshrUTA_s.o _fractQQHQ_s.o _fractQQSQ_s.o _fractQQDQ_s.o _fractQQTQ_s.o _fractQQHA_s.o _fractQQSA_s.o _fractQQDA_s.o _fractQQTA_s.o _fractQQUQQ_s.o _fractQQUHQ_s.o _fractQQUSQ_s.o _fractQQUDQ_s.o _fractQQUTQ_s.o _fractQQUHA_s.o _fractQQUSA_s.o _fractQQUDA_s.o _fractQQUTA_s.o _fractQQQI_s.o _fractQQHI_s.o _fractQQSI_s.o _fractQQDI_s.o _fractQQTI_s.o _fractQQSF_s.o _fractQQDF_s.o _fractHQQQ_s.o _fractHQSQ_s.o _fractHQDQ_s.o _fractHQTQ_s.o _fractHQHA_s.o _fractHQSA_s.o _fractHQDA_s.o _fractHQTA_s.o _fractHQUQQ_s.o _fractHQUHQ_s.o _fractHQUSQ_s.o _fractHQUDQ_s.o _fractHQUTQ_s.o _fractHQUHA_s.o _fractHQUSA_s.o _fractHQUDA_s.o _fractHQUTA_s.o _fractHQQI_s.o _fractHQHI_s.o _fractHQSI_s.o _fractHQDI_s.o _fractHQTI_s.o _fractHQSF_s.o _fractHQDF_s.o _fractSQQQ_s.o _fractSQHQ_s.o _fractSQDQ_s.o _fractSQTQ_s.o _fractSQHA_s.o _fractSQSA_s.o _fractSQDA_s.o _fractSQTA_s.o _fractSQUQQ_s.o _fractSQUHQ_s.o _fractSQUSQ_s.o _fractSQUDQ_s.o _fractSQUTQ_s.o _fractSQUHA_s.o _fractSQUSA_s.o _fractSQUDA_s.o _fractSQUTA_s.o _fractSQQI_s.o _fractSQHI_s.o _fractSQSI_s.o _fractSQDI_s.o _fractSQTI_s.o _fractSQSF_s.o _fractSQDF_s.o _fractDQQQ_s.o _fractDQHQ_s.o _fractDQSQ_s.o _fractDQTQ_s.o _fractDQHA_s.o _fractDQSA_s.o _fractDQDA_s.o _fractDQTA_s.o _fractDQUQQ_s.o _fractDQUHQ_s.o _fractDQUSQ_s.o _fractDQUDQ_s.o _fractDQUTQ_s.o _fractDQUHA_s.o _fractDQUSA_s.o _fractDQUDA_s.o _fractDQUTA_s.o _fractDQQI_s.o _fractDQHI_s.o _fractDQSI_s.o _fractDQDI_s.o _fractDQTI_s.o _fractDQSF_s.o _fractDQDF_s.o _fractTQQQ_s.o _fractTQHQ_s.o _fractTQSQ_s.o _fractTQDQ_s.o _fractTQHA_s.o _fractTQSA_s.o _fractTQDA_s.o _fractTQTA_s.o _fractTQUQQ_s.o _fractTQUHQ_s.o _fractTQUSQ_s.o _fractTQUDQ_s.o _fractTQUTQ_s.o _fractTQUHA_s.o _fractTQUSA_s.o _fractTQUDA_s.o _fractTQUTA_s.o _fractTQQI_s.o _fractTQHI_s.o _fractTQSI_s.o _fractTQDI_s.o _fractTQTI_s.o _fractTQSF_s.o _fractTQDF_s.o _fractHAQQ_s.o _fractHAHQ_s.o _fractHASQ_s.o _fractHADQ_s.o _fractHATQ_s.o _fractHASA_s.o _fractHADA_s.o _fractHATA_s.o _fractHAUQQ_s.o _fractHAUHQ_s.o _fractHAUSQ_s.o _fractHAUDQ_s.o _fractHAUTQ_s.o _fractHAUHA_s.o _fractHAUSA_s.o _fractHAUDA_s.o _fractHAUTA_s.o _fractHAQI_s.o _fractHAHI_s.o _fractHASI_s.o _fractHADI_s.o _fractHATI_s.o _fractHASF_s.o _fractHADF_s.o _fractSAQQ_s.o _fractSAHQ_s.o _fractSASQ_s.o _fractSADQ_s.o _fractSATQ_s.o _fractSAHA_s.o _fractSADA_s.o _fractSATA_s.o _fractSAUQQ_s.o _fractSAUHQ_s.o _fractSAUSQ_s.o _fractSAUDQ_s.o _fractSAUTQ_s.o _fractSAUHA_s.o _fractSAUSA_s.o _fractSAUDA_s.o _fractSAUTA_s.o _fractSAQI_s.o _fractSAHI_s.o _fractSASI_s.o _fractSADI_s.o _fractSATI_s.o _fractSASF_s.o _fractSADF_s.o _fractDAQQ_s.o _fractDAHQ_s.o _fractDASQ_s.o _fractDADQ_s.o _fractDATQ_s.o _fractDAHA_s.o _fractDASA_s.o _fractDATA_s.o _fractDAUQQ_s.o _fractDAUHQ_s.o _fractDAUSQ_s.o _fractDAUDQ_s.o _fractDAUTQ_s.o _fractDAUHA_s.o _fractDAUSA_s.o _fractDAUDA_s.o _fractDAUTA_s.o _fractDAQI_s.o _fractDAHI_s.o _fractDASI_s.o _fractDADI_s.o _fractDATI_s.o _fractDASF_s.o _fractDADF_s.o _fractTAQQ_s.o _fractTAHQ_s.o _fractTASQ_s.o _fractTADQ_s.o _fractTATQ_s.o _fractTAHA_s.o _fractTASA_s.o _fractTADA_s.o _fractTAUQQ_s.o _fractTAUHQ_s.o _fractTAUSQ_s.o _fractTAUDQ_s.o _fractTAUTQ_s.o _fractTAUHA_s.o _fractTAUSA_s.o _fractTAUDA_s.o _fractTAUTA_s.o _fractTAQI_s.o _fractTAHI_s.o _fractTASI_s.o _fractTADI_s.o _fractTATI_s.o _fractTASF_s.o _fractTADF_s.o _fractUQQQQ_s.o _fractUQQHQ_s.o _fractUQQSQ_s.o _fractUQQDQ_s.o _fractUQQTQ_s.o _fractUQQHA_s.o _fractUQQSA_s.o _fractUQQDA_s.o _fractUQQTA_s.o _fractUQQUHQ_s.o _fractUQQUSQ_s.o _fractUQQUDQ_s.o _fractUQQUTQ_s.o _fractUQQUHA_s.o _fractUQQUSA_s.o _fractUQQUDA_s.o _fractUQQUTA_s.o _fractUQQQI_s.o _fractUQQHI_s.o _fractUQQSI_s.o _fractUQQDI_s.o _fractUQQTI_s.o _fractUQQSF_s.o _fractUQQDF_s.o _fractUHQQQ_s.o _fractUHQHQ_s.o _fractUHQSQ_s.o _fractUHQDQ_s.o _fractUHQTQ_s.o _fractUHQHA_s.o _fractUHQSA_s.o _fractUHQDA_s.o _fractUHQTA_s.o _fractUHQUQQ_s.o _fractUHQUSQ_s.o _fractUHQUDQ_s.o _fractUHQUTQ_s.o _fractUHQUHA_s.o _fractUHQUSA_s.o _fractUHQUDA_s.o _fractUHQUTA_s.o _fractUHQQI_s.o _fractUHQHI_s.o _fractUHQSI_s.o _fractUHQDI_s.o _fractUHQTI_s.o _fractUHQSF_s.o _fractUHQDF_s.o _fractUSQQQ_s.o _fractUSQHQ_s.o _fractUSQSQ_s.o _fractUSQDQ_s.o _fractUSQTQ_s.o _fractUSQHA_s.o _fractUSQSA_s.o _fractUSQDA_s.o _fractUSQTA_s.o _fractUSQUQQ_s.o _fractUSQUHQ_s.o _fractUSQUDQ_s.o _fractUSQUTQ_s.o _fractUSQUHA_s.o _fractUSQUSA_s.o _fractUSQUDA_s.o _fractUSQUTA_s.o _fractUSQQI_s.o _fractUSQHI_s.o _fractUSQSI_s.o _fractUSQDI_s.o _fractUSQTI_s.o _fractUSQSF_s.o _fractUSQDF_s.o _fractUDQQQ_s.o _fractUDQHQ_s.o _fractUDQSQ_s.o _fractUDQDQ_s.o _fractUDQTQ_s.o _fractUDQHA_s.o _fractUDQSA_s.o _fractUDQDA_s.o _fractUDQTA_s.o _fractUDQUQQ_s.o _fractUDQUHQ_s.o _fractUDQUSQ_s.o _fractUDQUTQ_s.o _fractUDQUHA_s.o _fractUDQUSA_s.o _fractUDQUDA_s.o _fractUDQUTA_s.o _fractUDQQI_s.o _fractUDQHI_s.o _fractUDQSI_s.o _fractUDQDI_s.o _fractUDQTI_s.o _fractUDQSF_s.o _fractUDQDF_s.o _fractUTQQQ_s.o _fractUTQHQ_s.o _fractUTQSQ_s.o _fractUTQDQ_s.o _fractUTQTQ_s.o _fractUTQHA_s.o _fractUTQSA_s.o _fractUTQDA_s.o _fractUTQTA_s.o _fractUTQUQQ_s.o _fractUTQUHQ_s.o _fractUTQUSQ_s.o _fractUTQUDQ_s.o _fractUTQUHA_s.o _fractUTQUSA_s.o _fractUTQUDA_s.o _fractUTQUTA_s.o _fractUTQQI_s.o _fractUTQHI_s.o _fractUTQSI_s.o _fractUTQDI_s.o _fractUTQTI_s.o _fractUTQSF_s.o _fractUTQDF_s.o _fractUHAQQ_s.o _fractUHAHQ_s.o _fractUHASQ_s.o _fractUHADQ_s.o _fractUHATQ_s.o _fractUHAHA_s.o _fractUHASA_s.o _fractUHADA_s.o _fractUHATA_s.o _fractUHAUQQ_s.o _fractUHAUHQ_s.o _fractUHAUSQ_s.o _fractUHAUDQ_s.o _fractUHAUTQ_s.o _fractUHAUSA_s.o _fractUHAUDA_s.o _fractUHAUTA_s.o _fractUHAQI_s.o _fractUHAHI_s.o _fractUHASI_s.o _fractUHADI_s.o _fractUHATI_s.o _fractUHASF_s.o _fractUHADF_s.o _fractUSAQQ_s.o _fractUSAHQ_s.o _fractUSASQ_s.o _fractUSADQ_s.o _fractUSATQ_s.o _fractUSAHA_s.o _fractUSASA_s.o _fractUSADA_s.o _fractUSATA_s.o _fractUSAUQQ_s.o _fractUSAUHQ_s.o _fractUSAUSQ_s.o _fractUSAUDQ_s.o _fractUSAUTQ_s.o _fractUSAUHA_s.o _fractUSAUDA_s.o _fractUSAUTA_s.o _fractUSAQI_s.o _fractUSAHI_s.o _fractUSASI_s.o _fractUSADI_s.o _fractUSATI_s.o _fractUSASF_s.o _fractUSADF_s.o _fractUDAQQ_s.o _fractUDAHQ_s.o _fractUDASQ_s.o _fractUDADQ_s.o _fractUDATQ_s.o _fractUDAHA_s.o _fractUDASA_s.o _fractUDADA_s.o _fractUDATA_s.o _fractUDAUQQ_s.o _fractUDAUHQ_s.o _fractUDAUSQ_s.o _fractUDAUDQ_s.o _fractUDAUTQ_s.o _fractUDAUHA_s.o _fractUDAUSA_s.o _fractUDAUTA_s.o _fractUDAQI_s.o _fractUDAHI_s.o _fractUDASI_s.o _fractUDADI_s.o _fractUDATI_s.o _fractUDASF_s.o _fractUDADF_s.o _fractUTAQQ_s.o _fractUTAHQ_s.o _fractUTASQ_s.o _fractUTADQ_s.o _fractUTATQ_s.o _fractUTAHA_s.o _fractUTASA_s.o _fractUTADA_s.o _fractUTATA_s.o _fractUTAUQQ_s.o _fractUTAUHQ_s.o _fractUTAUSQ_s.o _fractUTAUDQ_s.o _fractUTAUTQ_s.o _fractUTAUHA_s.o _fractUTAUSA_s.o _fractUTAUDA_s.o _fractUTAQI_s.o _fractUTAHI_s.o _fractUTASI_s.o _fractUTADI_s.o _fractUTATI_s.o _fractUTASF_s.o _fractUTADF_s.o _fractQIQQ_s.o _fractQIHQ_s.o _fractQISQ_s.o _fractQIDQ_s.o _fractQITQ_s.o _fractQIHA_s.o _fractQISA_s.o _fractQIDA_s.o _fractQITA_s.o _fractQIUQQ_s.o _fractQIUHQ_s.o _fractQIUSQ_s.o _fractQIUDQ_s.o _fractQIUTQ_s.o _fractQIUHA_s.o _fractQIUSA_s.o _fractQIUDA_s.o _fractQIUTA_s.o _fractHIQQ_s.o _fractHIHQ_s.o _fractHISQ_s.o _fractHIDQ_s.o _fractHITQ_s.o _fractHIHA_s.o _fractHISA_s.o _fractHIDA_s.o _fractHITA_s.o _fractHIUQQ_s.o _fractHIUHQ_s.o _fractHIUSQ_s.o _fractHIUDQ_s.o _fractHIUTQ_s.o _fractHIUHA_s.o _fractHIUSA_s.o _fractHIUDA_s.o _fractHIUTA_s.o _fractSIQQ_s.o _fractSIHQ_s.o _fractSISQ_s.o _fractSIDQ_s.o _fractSITQ_s.o _fractSIHA_s.o _fractSISA_s.o _fractSIDA_s.o _fractSITA_s.o _fractSIUQQ_s.o _fractSIUHQ_s.o _fractSIUSQ_s.o _fractSIUDQ_s.o _fractSIUTQ_s.o _fractSIUHA_s.o _fractSIUSA_s.o _fractSIUDA_s.o _fractSIUTA_s.o _fractDIQQ_s.o _fractDIHQ_s.o _fractDISQ_s.o _fractDIDQ_s.o _fractDITQ_s.o _fractDIHA_s.o _fractDISA_s.o _fractDIDA_s.o _fractDITA_s.o _fractDIUQQ_s.o _fractDIUHQ_s.o _fractDIUSQ_s.o _fractDIUDQ_s.o _fractDIUTQ_s.o _fractDIUHA_s.o _fractDIUSA_s.o _fractDIUDA_s.o _fractDIUTA_s.o _fractTIQQ_s.o _fractTIHQ_s.o _fractTISQ_s.o _fractTIDQ_s.o _fractTITQ_s.o _fractTIHA_s.o _fractTISA_s.o _fractTIDA_s.o _fractTITA_s.o _fractTIUQQ_s.o _fractTIUHQ_s.o _fractTIUSQ_s.o _fractTIUDQ_s.o _fractTIUTQ_s.o _fractTIUHA_s.o _fractTIUSA_s.o _fractTIUDA_s.o _fractTIUTA_s.o _fractSFQQ_s.o _fractSFHQ_s.o _fractSFSQ_s.o _fractSFDQ_s.o _fractSFTQ_s.o _fractSFHA_s.o _fractSFSA_s.o _fractSFDA_s.o _fractSFTA_s.o _fractSFUQQ_s.o _fractSFUHQ_s.o _fractSFUSQ_s.o _fractSFUDQ_s.o _fractSFUTQ_s.o _fractSFUHA_s.o _fractSFUSA_s.o _fractSFUDA_s.o _fractSFUTA_s.o _fractDFQQ_s.o _fractDFHQ_s.o _fractDFSQ_s.o _fractDFDQ_s.o _fractDFTQ_s.o _fractDFHA_s.o _fractDFSA_s.o _fractDFDA_s.o _fractDFTA_s.o _fractDFUQQ_s.o _fractDFUHQ_s.o _fractDFUSQ_s.o _fractDFUDQ_s.o _fractDFUTQ_s.o _fractDFUHA_s.o _fractDFUSA_s.o _fractDFUDA_s.o _fractDFUTA_s.o _satfractQQHQ_s.o _satfractQQSQ_s.o _satfractQQDQ_s.o _satfractQQTQ_s.o _satfractQQHA_s.o _satfractQQSA_s.o _satfractQQDA_s.o _satfractQQTA_s.o _satfractQQUQQ_s.o _satfractQQUHQ_s.o _satfractQQUSQ_s.o _satfractQQUDQ_s.o _satfractQQUTQ_s.o _satfractQQUHA_s.o _satfractQQUSA_s.o _satfractQQUDA_s.o _satfractQQUTA_s.o _satfractHQQQ_s.o _satfractHQSQ_s.o _satfractHQDQ_s.o _satfractHQTQ_s.o _satfractHQHA_s.o _satfractHQSA_s.o _satfractHQDA_s.o _satfractHQTA_s.o _satfractHQUQQ_s.o _satfractHQUHQ_s.o _satfractHQUSQ_s.o _satfractHQUDQ_s.o _satfractHQUTQ_s.o _satfractHQUHA_s.o _satfractHQUSA_s.o _satfractHQUDA_s.o _satfractHQUTA_s.o _satfractSQQQ_s.o _satfractSQHQ_s.o _satfractSQDQ_s.o _satfractSQTQ_s.o _satfractSQHA_s.o _satfractSQSA_s.o _satfractSQDA_s.o _satfractSQTA_s.o _satfractSQUQQ_s.o _satfractSQUHQ_s.o _satfractSQUSQ_s.o _satfractSQUDQ_s.o _satfractSQUTQ_s.o _satfractSQUHA_s.o _satfractSQUSA_s.o _satfractSQUDA_s.o _satfractSQUTA_s.o _satfractDQQQ_s.o _satfractDQHQ_s.o _satfractDQSQ_s.o _satfractDQTQ_s.o _satfractDQHA_s.o _satfractDQSA_s.o _satfractDQDA_s.o _satfractDQTA_s.o _satfractDQUQQ_s.o _satfractDQUHQ_s.o _satfractDQUSQ_s.o _satfractDQUDQ_s.o _satfractDQUTQ_s.o _satfractDQUHA_s.o _satfractDQUSA_s.o _satfractDQUDA_s.o _satfractDQUTA_s.o _satfractTQQQ_s.o _satfractTQHQ_s.o _satfractTQSQ_s.o _satfractTQDQ_s.o _satfractTQHA_s.o _satfractTQSA_s.o _satfractTQDA_s.o _satfractTQTA_s.o _satfractTQUQQ_s.o _satfractTQUHQ_s.o _satfractTQUSQ_s.o _satfractTQUDQ_s.o _satfractTQUTQ_s.o _satfractTQUHA_s.o _satfractTQUSA_s.o _satfractTQUDA_s.o _satfractTQUTA_s.o _satfractHAQQ_s.o _satfractHAHQ_s.o _satfractHASQ_s.o _satfractHADQ_s.o _satfractHATQ_s.o _satfractHASA_s.o _satfractHADA_s.o _satfractHATA_s.o _satfractHAUQQ_s.o _satfractHAUHQ_s.o _satfractHAUSQ_s.o _satfractHAUDQ_s.o _satfractHAUTQ_s.o _satfractHAUHA_s.o _satfractHAUSA_s.o _satfractHAUDA_s.o _satfractHAUTA_s.o _satfractSAQQ_s.o _satfractSAHQ_s.o _satfractSASQ_s.o _satfractSADQ_s.o _satfractSATQ_s.o _satfractSAHA_s.o _satfractSADA_s.o _satfractSATA_s.o _satfractSAUQQ_s.o _satfractSAUHQ_s.o _satfractSAUSQ_s.o _satfractSAUDQ_s.o _satfractSAUTQ_s.o _satfractSAUHA_s.o _satfractSAUSA_s.o _satfractSAUDA_s.o _satfractSAUTA_s.o _satfractDAQQ_s.o _satfractDAHQ_s.o _satfractDASQ_s.o _satfractDADQ_s.o _satfractDATQ_s.o _satfractDAHA_s.o _satfractDASA_s.o _satfractDATA_s.o _satfractDAUQQ_s.o _satfractDAUHQ_s.o _satfractDAUSQ_s.o _satfractDAUDQ_s.o _satfractDAUTQ_s.o _satfractDAUHA_s.o _satfractDAUSA_s.o _satfractDAUDA_s.o _satfractDAUTA_s.o _satfractTAQQ_s.o _satfractTAHQ_s.o _satfractTASQ_s.o _satfractTADQ_s.o _satfractTATQ_s.o _satfractTAHA_s.o _satfractTASA_s.o _satfractTADA_s.o _satfractTAUQQ_s.o _satfractTAUHQ_s.o _satfractTAUSQ_s.o _satfractTAUDQ_s.o _satfractTAUTQ_s.o _satfractTAUHA_s.o _satfractTAUSA_s.o _satfractTAUDA_s.o _satfractTAUTA_s.o _satfractUQQQQ_s.o _satfractUQQHQ_s.o _satfractUQQSQ_s.o _satfractUQQDQ_s.o _satfractUQQTQ_s.o _satfractUQQHA_s.o _satfractUQQSA_s.o _satfractUQQDA_s.o _satfractUQQTA_s.o _satfractUQQUHQ_s.o _satfractUQQUSQ_s.o _satfractUQQUDQ_s.o _satfractUQQUTQ_s.o _satfractUQQUHA_s.o _satfractUQQUSA_s.o _satfractUQQUDA_s.o _satfractUQQUTA_s.o _satfractUHQQQ_s.o _satfractUHQHQ_s.o _satfractUHQSQ_s.o _satfractUHQDQ_s.o _satfractUHQTQ_s.o _satfractUHQHA_s.o _satfractUHQSA_s.o _satfractUHQDA_s.o _satfractUHQTA_s.o _satfractUHQUQQ_s.o _satfractUHQUSQ_s.o _satfractUHQUDQ_s.o _satfractUHQUTQ_s.o _satfractUHQUHA_s.o _satfractUHQUSA_s.o _satfractUHQUDA_s.o _satfractUHQUTA_s.o _satfractUSQQQ_s.o _satfractUSQHQ_s.o _satfractUSQSQ_s.o _satfractUSQDQ_s.o _satfractUSQTQ_s.o _satfractUSQHA_s.o _satfractUSQSA_s.o _satfractUSQDA_s.o _satfractUSQTA_s.o _satfractUSQUQQ_s.o _satfractUSQUHQ_s.o _satfractUSQUDQ_s.o _satfractUSQUTQ_s.o _satfractUSQUHA_s.o _satfractUSQUSA_s.o _satfractUSQUDA_s.o _satfractUSQUTA_s.o _satfractUDQQQ_s.o _satfractUDQHQ_s.o _satfractUDQSQ_s.o _satfractUDQDQ_s.o _satfractUDQTQ_s.o _satfractUDQHA_s.o _satfractUDQSA_s.o _satfractUDQDA_s.o _satfractUDQTA_s.o _satfractUDQUQQ_s.o _satfractUDQUHQ_s.o _satfractUDQUSQ_s.o _satfractUDQUTQ_s.o _satfractUDQUHA_s.o _satfractUDQUSA_s.o _satfractUDQUDA_s.o _satfractUDQUTA_s.o _satfractUTQQQ_s.o _satfractUTQHQ_s.o _satfractUTQSQ_s.o _satfractUTQDQ_s.o _satfractUTQTQ_s.o _satfractUTQHA_s.o _satfractUTQSA_s.o _satfractUTQDA_s.o _satfractUTQTA_s.o _satfractUTQUQQ_s.o _satfractUTQUHQ_s.o _satfractUTQUSQ_s.o _satfractUTQUDQ_s.o _satfractUTQUHA_s.o _satfractUTQUSA_s.o _satfractUTQUDA_s.o _satfractUTQUTA_s.o _satfractUHAQQ_s.o _satfractUHAHQ_s.o _satfractUHASQ_s.o _satfractUHADQ_s.o _satfractUHATQ_s.o _satfractUHAHA_s.o _satfractUHASA_s.o _satfractUHADA_s.o _satfractUHATA_s.o _satfractUHAUQQ_s.o _satfractUHAUHQ_s.o _satfractUHAUSQ_s.o _satfractUHAUDQ_s.o _satfractUHAUTQ_s.o _satfractUHAUSA_s.o _satfractUHAUDA_s.o _satfractUHAUTA_s.o _satfractUSAQQ_s.o _satfractUSAHQ_s.o _satfractUSASQ_s.o _satfractUSADQ_s.o _satfractUSATQ_s.o _satfractUSAHA_s.o _satfractUSASA_s.o _satfractUSADA_s.o _satfractUSATA_s.o _satfractUSAUQQ_s.o _satfractUSAUHQ_s.o _satfractUSAUSQ_s.o _satfractUSAUDQ_s.o _satfractUSAUTQ_s.o _satfractUSAUHA_s.o _satfractUSAUDA_s.o _satfractUSAUTA_s.o _satfractUDAQQ_s.o _satfractUDAHQ_s.o _satfractUDASQ_s.o _satfractUDADQ_s.o _satfractUDATQ_s.o _satfractUDAHA_s.o _satfractUDASA_s.o _satfractUDADA_s.o _satfractUDATA_s.o _satfractUDAUQQ_s.o _satfractUDAUHQ_s.o _satfractUDAUSQ_s.o _satfractUDAUDQ_s.o _satfractUDAUTQ_s.o _satfractUDAUHA_s.o _satfractUDAUSA_s.o _satfractUDAUTA_s.o _satfractUTAQQ_s.o _satfractUTAHQ_s.o _satfractUTASQ_s.o _satfractUTADQ_s.o _satfractUTATQ_s.o _satfractUTAHA_s.o _satfractUTASA_s.o _satfractUTADA_s.o _satfractUTATA_s.o _satfractUTAUQQ_s.o _satfractUTAUHQ_s.o _satfractUTAUSQ_s.o _satfractUTAUDQ_s.o _satfractUTAUTQ_s.o _satfractUTAUHA_s.o _satfractUTAUSA_s.o _satfractUTAUDA_s.o _satfractQIQQ_s.o _satfractQIHQ_s.o _satfractQISQ_s.o _satfractQIDQ_s.o _satfractQITQ_s.o _satfractQIHA_s.o _satfractQISA_s.o _satfractQIDA_s.o _satfractQITA_s.o _satfractQIUQQ_s.o _satfractQIUHQ_s.o _satfractQIUSQ_s.o _satfractQIUDQ_s.o _satfractQIUTQ_s.o _satfractQIUHA_s.o _satfractQIUSA_s.o _satfractQIUDA_s.o _satfractQIUTA_s.o _satfractHIQQ_s.o _satfractHIHQ_s.o _satfractHISQ_s.o _satfractHIDQ_s.o _satfractHITQ_s.o _satfractHIHA_s.o _satfractHISA_s.o _satfractHIDA_s.o _satfractHITA_s.o _satfractHIUQQ_s.o _satfractHIUHQ_s.o _satfractHIUSQ_s.o _satfractHIUDQ_s.o _satfractHIUTQ_s.o _satfractHIUHA_s.o _satfractHIUSA_s.o _satfractHIUDA_s.o _satfractHIUTA_s.o _satfractSIQQ_s.o _satfractSIHQ_s.o _satfractSISQ_s.o _satfractSIDQ_s.o _satfractSITQ_s.o _satfractSIHA_s.o _satfractSISA_s.o _satfractSIDA_s.o _satfractSITA_s.o _satfractSIUQQ_s.o _satfractSIUHQ_s.o _satfractSIUSQ_s.o _satfractSIUDQ_s.o _satfractSIUTQ_s.o _satfractSIUHA_s.o _satfractSIUSA_s.o _satfractSIUDA_s.o _satfractSIUTA_s.o _satfractDIQQ_s.o _satfractDIHQ_s.o _satfractDISQ_s.o _satfractDIDQ_s.o _satfractDITQ_s.o _satfractDIHA_s.o _satfractDISA_s.o _satfractDIDA_s.o _satfractDITA_s.o _satfractDIUQQ_s.o _satfractDIUHQ_s.o _satfractDIUSQ_s.o _satfractDIUDQ_s.o _satfractDIUTQ_s.o _satfractDIUHA_s.o _satfractDIUSA_s.o _satfractDIUDA_s.o _satfractDIUTA_s.o _satfractTIQQ_s.o _satfractTIHQ_s.o _satfractTISQ_s.o _satfractTIDQ_s.o _satfractTITQ_s.o _satfractTIHA_s.o _satfractTISA_s.o _satfractTIDA_s.o _satfractTITA_s.o _satfractTIUQQ_s.o _satfractTIUHQ_s.o _satfractTIUSQ_s.o _satfractTIUDQ_s.o _satfractTIUTQ_s.o _satfractTIUHA_s.o _satfractTIUSA_s.o _satfractTIUDA_s.o _satfractTIUTA_s.o _satfractSFQQ_s.o _satfractSFHQ_s.o _satfractSFSQ_s.o _satfractSFDQ_s.o _satfractSFTQ_s.o _satfractSFHA_s.o _satfractSFSA_s.o _satfractSFDA_s.o _satfractSFTA_s.o _satfractSFUQQ_s.o _satfractSFUHQ_s.o _satfractSFUSQ_s.o _satfractSFUDQ_s.o _satfractSFUTQ_s.o _satfractSFUHA_s.o _satfractSFUSA_s.o _satfractSFUDA_s.o _satfractSFUTA_s.o _satfractDFQQ_s.o _satfractDFHQ_s.o _satfractDFSQ_s.o _satfractDFDQ_s.o _satfractDFTQ_s.o _satfractDFHA_s.o _satfractDFSA_s.o _satfractDFDA_s.o _satfractDFTA_s.o _satfractDFUQQ_s.o _satfractDFUHQ_s.o _satfractDFUSQ_s.o _satfractDFUDQ_s.o _satfractDFUTQ_s.o _satfractDFUHA_s.o _satfractDFUSA_s.o _satfractDFUDA_s.o _satfractDFUTA_s.o _fractunsQQUQI_s.o _fractunsQQUHI_s.o _fractunsQQUSI_s.o _fractunsQQUDI_s.o _fractunsQQUTI_s.o _fractunsHQUQI_s.o _fractunsHQUHI_s.o _fractunsHQUSI_s.o _fractunsHQUDI_s.o _fractunsHQUTI_s.o _fractunsSQUQI_s.o _fractunsSQUHI_s.o _fractunsSQUSI_s.o _fractunsSQUDI_s.o _fractunsSQUTI_s.o _fractunsDQUQI_s.o _fractunsDQUHI_s.o _fractunsDQUSI_s.o _fractunsDQUDI_s.o _fractunsDQUTI_s.o _fractunsTQUQI_s.o _fractunsTQUHI_s.o _fractunsTQUSI_s.o _fractunsTQUDI_s.o _fractunsTQUTI_s.o _fractunsHAUQI_s.o _fractunsHAUHI_s.o _fractunsHAUSI_s.o _fractunsHAUDI_s.o _fractunsHAUTI_s.o _fractunsSAUQI_s.o _fractunsSAUHI_s.o _fractunsSAUSI_s.o _fractunsSAUDI_s.o _fractunsSAUTI_s.o _fractunsDAUQI_s.o _fractunsDAUHI_s.o _fractunsDAUSI_s.o _fractunsDAUDI_s.o _fractunsDAUTI_s.o _fractunsTAUQI_s.o _fractunsTAUHI_s.o _fractunsTAUSI_s.o _fractunsTAUDI_s.o _fractunsTAUTI_s.o _fractunsUQQUQI_s.o _fractunsUQQUHI_s.o _fractunsUQQUSI_s.o _fractunsUQQUDI_s.o _fractunsUQQUTI_s.o _fractunsUHQUQI_s.o _fractunsUHQUHI_s.o _fractunsUHQUSI_s.o _fractunsUHQUDI_s.o _fractunsUHQUTI_s.o _fractunsUSQUQI_s.o _fractunsUSQUHI_s.o _fractunsUSQUSI_s.o _fractunsUSQUDI_s.o _fractunsUSQUTI_s.o _fractunsUDQUQI_s.o _fractunsUDQUHI_s.o _fractunsUDQUSI_s.o _fractunsUDQUDI_s.o _fractunsUDQUTI_s.o _fractunsUTQUQI_s.o _fractunsUTQUHI_s.o _fractunsUTQUSI_s.o _fractunsUTQUDI_s.o _fractunsUTQUTI_s.o _fractunsUHAUQI_s.o _fractunsUHAUHI_s.o _fractunsUHAUSI_s.o _fractunsUHAUDI_s.o _fractunsUHAUTI_s.o _fractunsUSAUQI_s.o _fractunsUSAUHI_s.o _fractunsUSAUSI_s.o _fractunsUSAUDI_s.o _fractunsUSAUTI_s.o _fractunsUDAUQI_s.o _fractunsUDAUHI_s.o _fractunsUDAUSI_s.o _fractunsUDAUDI_s.o _fractunsUDAUTI_s.o _fractunsUTAUQI_s.o _fractunsUTAUHI_s.o _fractunsUTAUSI_s.o _fractunsUTAUDI_s.o _fractunsUTAUTI_s.o _fractunsUQIQQ_s.o _fractunsUQIHQ_s.o _fractunsUQISQ_s.o _fractunsUQIDQ_s.o _fractunsUQITQ_s.o _fractunsUQIHA_s.o _fractunsUQISA_s.o _fractunsUQIDA_s.o _fractunsUQITA_s.o _fractunsUQIUQQ_s.o _fractunsUQIUHQ_s.o _fractunsUQIUSQ_s.o _fractunsUQIUDQ_s.o _fractunsUQIUTQ_s.o _fractunsUQIUHA_s.o _fractunsUQIUSA_s.o _fractunsUQIUDA_s.o _fractunsUQIUTA_s.o _fractunsUHIQQ_s.o _fractunsUHIHQ_s.o _fractunsUHISQ_s.o _fractunsUHIDQ_s.o _fractunsUHITQ_s.o _fractunsUHIHA_s.o _fractunsUHISA_s.o _fractunsUHIDA_s.o _fractunsUHITA_s.o _fractunsUHIUQQ_s.o _fractunsUHIUHQ_s.o _fractunsUHIUSQ_s.o _fractunsUHIUDQ_s.o _fractunsUHIUTQ_s.o _fractunsUHIUHA_s.o _fractunsUHIUSA_s.o _fractunsUHIUDA_s.o _fractunsUHIUTA_s.o _fractunsUSIQQ_s.o _fractunsUSIHQ_s.o _fractunsUSISQ_s.o _fractunsUSIDQ_s.o _fractunsUSITQ_s.o _fractunsUSIHA_s.o _fractunsUSISA_s.o _fractunsUSIDA_s.o _fractunsUSITA_s.o _fractunsUSIUQQ_s.o _fractunsUSIUHQ_s.o _fractunsUSIUSQ_s.o _fractunsUSIUDQ_s.o _fractunsUSIUTQ_s.o _fractunsUSIUHA_s.o _fractunsUSIUSA_s.o _fractunsUSIUDA_s.o _fractunsUSIUTA_s.o _fractunsUDIQQ_s.o _fractunsUDIHQ_s.o _fractunsUDISQ_s.o _fractunsUDIDQ_s.o _fractunsUDITQ_s.o _fractunsUDIHA_s.o _fractunsUDISA_s.o _fractunsUDIDA_s.o _fractunsUDITA_s.o _fractunsUDIUQQ_s.o _fractunsUDIUHQ_s.o _fractunsUDIUSQ_s.o _fractunsUDIUDQ_s.o _fractunsUDIUTQ_s.o _fractunsUDIUHA_s.o _fractunsUDIUSA_s.o _fractunsUDIUDA_s.o _fractunsUDIUTA_s.o _fractunsUTIQQ_s.o _fractunsUTIHQ_s.o _fractunsUTISQ_s.o _fractunsUTIDQ_s.o _fractunsUTITQ_s.o _fractunsUTIHA_s.o _fractunsUTISA_s.o _fractunsUTIDA_s.o _fractunsUTITA_s.o _fractunsUTIUQQ_s.o _fractunsUTIUHQ_s.o _fractunsUTIUSQ_s.o _fractunsUTIUDQ_s.o _fractunsUTIUTQ_s.o _fractunsUTIUHA_s.o _fractunsUTIUSA_s.o _fractunsUTIUDA_s.o _fractunsUTIUTA_s.o _satfractunsUQIQQ_s.o _satfractunsUQIHQ_s.o _satfractunsUQISQ_s.o _satfractunsUQIDQ_s.o _satfractunsUQITQ_s.o _satfractunsUQIHA_s.o _satfractunsUQISA_s.o _satfractunsUQIDA_s.o _satfractunsUQITA_s.o _satfractunsUQIUQQ_s.o _satfractunsUQIUHQ_s.o _satfractunsUQIUSQ_s.o _satfractunsUQIUDQ_s.o _satfractunsUQIUTQ_s.o _satfractunsUQIUHA_s.o _satfractunsUQIUSA_s.o _satfractunsUQIUDA_s.o _satfractunsUQIUTA_s.o _satfractunsUHIQQ_s.o _satfractunsUHIHQ_s.o _satfractunsUHISQ_s.o _satfractunsUHIDQ_s.o _satfractunsUHITQ_s.o _satfractunsUHIHA_s.o _satfractunsUHISA_s.o _satfractunsUHIDA_s.o _satfractunsUHITA_s.o _satfractunsUHIUQQ_s.o _satfractunsUHIUHQ_s.o _satfractunsUHIUSQ_s.o _satfractunsUHIUDQ_s.o _satfractunsUHIUTQ_s.o _satfractunsUHIUHA_s.o _satfractunsUHIUSA_s.o _satfractunsUHIUDA_s.o _satfractunsUHIUTA_s.o _satfractunsUSIQQ_s.o _satfractunsUSIHQ_s.o _satfractunsUSISQ_s.o _satfractunsUSIDQ_s.o _satfractunsUSITQ_s.o _satfractunsUSIHA_s.o _satfractunsUSISA_s.o _satfractunsUSIDA_s.o _satfractunsUSITA_s.o _satfractunsUSIUQQ_s.o _satfractunsUSIUHQ_s.o _satfractunsUSIUSQ_s.o _satfractunsUSIUDQ_s.o _satfractunsUSIUTQ_s.o _satfractunsUSIUHA_s.o _satfractunsUSIUSA_s.o _satfractunsUSIUDA_s.o _satfractunsUSIUTA_s.o _satfractunsUDIQQ_s.o _satfractunsUDIHQ_s.o _satfractunsUDISQ_s.o _satfractunsUDIDQ_s.o _satfractunsUDITQ_s.o _satfractunsUDIHA_s.o _satfractunsUDISA_s.o _satfractunsUDIDA_s.o _satfractunsUDITA_s.o _satfractunsUDIUQQ_s.o _satfractunsUDIUHQ_s.o _satfractunsUDIUSQ_s.o _satfractunsUDIUDQ_s.o _satfractunsUDIUTQ_s.o _satfractunsUDIUHA_s.o _satfractunsUDIUSA_s.o _satfractunsUDIUDA_s.o _satfractunsUDIUTA_s.o _satfractunsUTIQQ_s.o _satfractunsUTIHQ_s.o _satfractunsUTISQ_s.o _satfractunsUTIDQ_s.o _satfractunsUTITQ_s.o _satfractunsUTIHA_s.o _satfractunsUTISA_s.o _satfractunsUTIDA_s.o _satfractunsUTITA_s.o _satfractunsUTIUQQ_s.o _satfractunsUTIUHQ_s.o _satfractunsUTIUSQ_s.o _satfractunsUTIUDQ_s.o _satfractunsUTIUTQ_s.o _satfractunsUTIUHA_s.o _satfractunsUTIUSA_s.o _satfractunsUTIUDA_s.o _satfractunsUTIUTA_s.o bpabi_s.o unaligned-funcs_s.o addsf3_s.o divsf3_s.o eqsf2_s.o gesf2_s.o lesf2_s.o mulsf3_s.o negsf2_s.o subsf3_s.o unordsf2_s.o fixsfsi_s.o floatsisf_s.o floatunsisf_s.o adddf3_s.o divdf3_s.o eqdf2_s.o gedf2_s.o ledf2_s.o muldf3_s.o negdf2_s.o subdf3_s.o unorddf2_s.o fixdfsi_s.o floatsidf_s.o floatunsidf_s.o extendsfdf2_s.o truncdfsf2_s.o enable-execute-stack_s.o unwind-arm_s.o libunwind_s.o pr-support_s.o unwind-c_s.o emutls_s.o libgcc.a -lc -v" | wc -c


# Next problem seems trickier to solve:
[INFO ]  Installing C library
[EXTRA]    Configuring C library
[EXTRA]    Building C library
[ERROR]    ../ports/sysdeps/arm/sysdeps/../nptl/pthread_spin_lock.c:23:47: error: #include nested too deeply
[ERROR]    make[3]: *** [/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/nptl/pthread_spin_lock.o] Error 1
[ERROR]    make[2]: *** [nptl/subdir_lib] Error 2
[ERROR]    make[1]: *** [all] Error 2
[ERROR]  -
[ERROR]  >>
[ERROR]  >>  Build failed in step 'Installing C library'
[ERROR]  >>        called in step '(top-level)'
[ERROR]  >>
[ERROR]  >>  Error happened in: CT_DoExecLog[scripts/functions@257]
[ERROR]  >>        called from: do_libc_backend_once[scripts/build/libc/glibc-eglibc.sh-common@488]
[ERROR]  >>        called from: do_libc_backend[scripts/build/libc/glibc-eglibc.sh-common@158]
[ERROR]  >>        called from: do_libc[scripts/build/libc/glibc-eglibc.sh-common@65]
[ERROR]  >>        called from: main[scripts/crosstool-NG.sh@686]

# .. Pavel Fadin ran into it in Cygwin
# http://cygwin.com/ml/cygwin/2013-05/msg00222.html
# .. but my cross compilers are *not* Cygwin based and this is just the #include path resolve mechanism going bad.

# Trying to get a simple testcase for this is proving a bit tricky .. this isn't right!
cd ~/Dropbox
mkdir include-test
cd include-test
mkdir -p ports/sysdeps/arm
mkdir -p ports/sysdeps/arm/nptl
echo -e "#include <sysdeps/../nptl/test.c>\n" > test.c
echo -e "#error \"good\"" > ports/sysdeps/nptl/test.c
gcc -Iports/sysdeps/arm -Iports/sysdeps test.c


# The error was:
pushd /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/src/eglibc-2_18/nptl
export PATH=/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/bin:"$PATH"
armv6hl-unknown-linux-gnueabi-gcc     ../ports/sysdeps/arm/nptl/pthread_spin_lock.c -c -std=gnu99 -fgnu89-inline  -O2 -U_FORTIFY_SOURCE -Wall -Winline -Wwrite-strings -fmerge-all-constants -frounding-math -march=armv6 -mfpu=vfp -mhard-float -mlittle-endian -mtune=arm1176jzf-s -Wstrict-prototypes         -I../include -I/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/nptl  -I/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final  -I../ports/sysdeps/unix/sysv/linux/arm/nptl  -I../ports/sysdeps/unix/sysv/linux/arm  -I../nptl/sysdeps/unix/sysv/linux  -I../nptl/sysdeps/pthread  -I../sysdeps/pthread  -I../ports/sysdeps/unix/sysv/linux  -I../sysdeps/unix/sysv/linux  -I../sysdeps/gnu  -I../sysdeps/unix/inet  -I../nptl/sysdeps/unix/sysv  -I../ports/sysdeps/unix/sysv  -I../sysdeps/unix/sysv  -I../ports/sysdeps/unix/arm  -I../nptl/sysdeps/unix  -I../ports/sysdeps/unix  -I../sysdeps/unix  -I../sysdeps/posix  -I../ports/sysdeps/arm/armv6  -I../ports/sysdeps/arm/nptl  -I../ports/sysdeps/arm/include -I../ports/sysdeps/arm  -I../ports/sysdeps/arm/soft-fp  -I../sysdeps/wordsize-32  -I../sysdeps/ieee754/flt-32  -I../sysdeps/ieee754/dbl-64  -I../sysdeps/ieee754  -I../sysdeps/generic  -I../nptl  -I../ports  -I.. -I../libio -I. -nostdinc -isystem c:/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/bin/../lib/gcc/armv6hl-unknown-linux-gnueabi/4.8.2/include -isystem c:/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/bin/../lib/gcc/armv6hl-unknown-linux-gnueabi/4.8.2/include-fixed -isystem /home/ray/ctng-firefox-builds/x-r-none-4_8_2-x86_64-235295c4-d/armv6hl-unknown-linux-gnueabi/sysroot/usr/include  -D_LIBC_REENTRANT -include ../include/libc-symbols.h   -DNOT_IN_libc=1 -DIS_IN_libpthread=1 -DIN_LIB=libpthread    -o /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/nptl/pthread_spin_lock.o -MD -MP -MF /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/nptl/pthread_spin_lock.o.dt -MT /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/nptl/pthread_spin_lock.o


# On Windows, adding -v 2>&1 | less gives:
ignoring duplicate directory "."
#include "..." search starts here:
#include <...> search starts here:
 ../include
 C:/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/nptl
 C:/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final
 ../ports/sysdeps/unix/sysv/linux/arm/nptl
 ../ports/sysdeps/unix/sysv/linux/arm
 ../nptl/sysdeps/unix/sysv/linux
 ../nptl/sysdeps/pthread
 ../sysdeps/pthread
 ../ports/sysdeps/unix/sysv/linux
 ../sysdeps/unix/sysv/linux
 ../sysdeps/gnu
 ../sysdeps/unix/inet
 ../nptl/sysdeps/unix/sysv
 ../ports/sysdeps/unix/sysv
 ../sysdeps/unix/sysv
 ../ports/sysdeps/unix/arm
 ../nptl/sysdeps/unix
 ../ports/sysdeps/unix
 ../sysdeps/unix
 ../sysdeps/posix
 ../ports/sysdeps/arm/armv6
 ../ports/sysdeps/arm/nptl
 ../ports/sysdeps/arm/include
 ../ports/sysdeps/arm
 ../ports/sysdeps/arm/soft-fp
 ../sysdeps/wordsize-32
 ../sysdeps/ieee754/flt-32
 ../sysdeps/ieee754/dbl-64
 ../sysdeps/ieee754
 ../sysdeps/generic
 ../nptl
 ../ports
 ..
 ../libio
 c:/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/bin/../lib/gcc/armv6hl-unknown-linux-gnueabi/4.8.2/include
 c:/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/bin/../lib/gcc/armv6hl-unknown-linux-gnueabi/4.8.2/include-fixed
 C:/msys64/home/ray/ctng-firefox-builds/x-r-none-4_8_2-x86_64-235295c4-d/armv6hl-unknown-linux-gnueabi/sysroot/usr/include

# .. So over to Linux:
pushd ~/ctng-firefox-builds/ctng-build-x-r-none-4_8_2-x86_64-d/.build/src/eglibc-2_18/nptl
export PATH=/home/ray/ctng-firefox-builds/ctng-build-x-r-none-4_8_2-x86_64-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/bin:"$PATH"
# Attempting to translate the Windows path directly to linux failed. The only difference is that Linux baked down bin/../lib to /lib whilst Windows hasn't done that .. maybe should fix this to gain more commandline characters?
# armv6hl-unknown-linux-gnueabi-gcc     ../ports/sysdeps/arm/nptl/pthread_spin_lock.c -c -std=gnu99 -fgnu89-inline  -O2 -U_FORTIFY_SOURCE -Wall -Winline -Wwrite-strings -fmerge-all-constants -frounding-math -march=armv6 -mfpu=vfp -mhard-float -mlittle-endian -mtune=arm1176jzf-s -Wstrict-prototypes         -I../include -I/home/ray/ctng-firefox-builds/ctng-build-x-r-none-4_8_2-x86_64-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/nptl  -I/home/ray/ctng-firefox-builds/ctng-build-x-r-none-4_8_2-x86_64-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final  -I../ports/sysdeps/unix/sysv/linux/arm/nptl  -I../ports/sysdeps/unix/sysv/linux/arm  -I../nptl/sysdeps/unix/sysv/linux  -I../nptl/sysdeps/pthread  -I../sysdeps/pthread  -I../ports/sysdeps/unix/sysv/linux  -I../sysdeps/unix/sysv/linux  -I../sysdeps/gnu  -I../sysdeps/unix/inet  -I../nptl/sysdeps/unix/sysv  -I../ports/sysdeps/unix/sysv  -I../sysdeps/unix/sysv  -I../ports/sysdeps/unix/arm  -I../nptl/sysdeps/unix  -I../ports/sysdeps/unix  -I../sysdeps/unix  -I../sysdeps/posix  -I../ports/sysdeps/arm/armv6  -I../ports/sysdeps/arm/nptl  -I../ports/sysdeps/arm/include -I../ports/sysdeps/arm  -I../ports/sysdeps/arm/soft-fp  -I../sysdeps/wordsize-32  -I../sysdeps/ieee754/flt-32  -I../sysdeps/ieee754/dbl-64  -I../sysdeps/ieee754  -I../sysdeps/generic  -I../nptl  -I../ports  -I.. -I../libio -I. -nostdinc -isystem /home/ray/ctng-firefox-builds/ctng-build-x-r-none-4_8_2-x86_64-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/bin/../lib/gcc/armv6hl-unknown-linux-gnueabi/4.8.2/include -isystem /home/ray/ctng-firefox-builds/ctng-build-x-r-none-4_8_2-x86_64-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/bin/../lib/gcc/armv6hl-unknown-linux-gnueabi/4.8.2/include-fixed -isystem /home/ray/ctng-firefox-builds/x-r-none-4_8_2-x86_64-d/armv6hl-unknown-linux-gnueabi/sysroot/usr/include  -D_LIBC_REENTRANT -include ../include/libc-symbols.h   -DNOT_IN_libc=1 -DIS_IN_libpthread=1 -DIN_LIB=libpthread    -o /home/ray/ctng-firefox-builds/ctng-build-x-r-none-4_8_2-x86_64-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/nptl/pthread_spin_lock.o -MD -MP -MF /home/ray/ctng-firefox-builds/ctng-build-x-r-none-4_8_2-x86_64-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/nptl/pthread_spin_lock.o.dt -MT /home/ray/ctng-firefox-builds/ctng-build-x-r-none-4_8_2-x86_64-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/nptl/pthread_spin_lock.o
# A working Linux commandline is:
armv6hl-unknown-linux-gnueabi-gcc     ../ports/sysdeps/arm/nptl/pthread_spin_lock.c -c -std=gnu99 -fgnu89-inline  -O2 -U_FORTIFY_SOURCE -Wall -Winline -Wwrite-strings -fmerge-all-constants -frounding-math -march=armv6 -mfpu=vfp -mhard-float -mlittle-endian -mtune=arm1176jzf-s -Wstrict-prototypes         -I../include -I/home/ray/ctng-firefox-builds/ctng-build-x-r-none-4_8_2-x86_64-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/nptl  -I/home/ray/ctng-firefox-builds/ctng-build-x-r-none-4_8_2-x86_64-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final  -I../ports/sysdeps/unix/sysv/linux/arm/nptl  -I../ports/sysdeps/unix/sysv/linux/arm  -I../nptl/sysdeps/unix/sysv/linux  -I../nptl/sysdeps/pthread  -I../sysdeps/pthread  -I../ports/sysdeps/unix/sysv/linux  -I../sysdeps/unix/sysv/linux  -I../sysdeps/gnu  -I../sysdeps/unix/inet  -I../nptl/sysdeps/unix/sysv  -I../ports/sysdeps/unix/sysv  -I../sysdeps/unix/sysv  -I../ports/sysdeps/unix/arm  -I../nptl/sysdeps/unix  -I../ports/sysdeps/unix  -I../sysdeps/unix  -I../sysdeps/posix  -I../ports/sysdeps/arm/armv6  -I../ports/sysdeps/arm/nptl  -I../ports/sysdeps/arm/include -I../ports/sysdeps/arm  -I../ports/sysdeps/arm/soft-fp  -I../sysdeps/wordsize-32  -I../sysdeps/ieee754/flt-32  -I../sysdeps/ieee754/dbl-64  -I../sysdeps/ieee754  -I../sysdeps/generic  -I../nptl  -I../ports  -I.. -I../libio -I. -nostdinc -isystem /home/ray/ctng-firefox-builds/ctng-build-x-r-none-4_8_2-x86_64-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/lib/gcc/armv6hl-unknown-linux-gnueabi/4.8.2/include        -isystem /home/ray/ctng-firefox-builds/ctng-build-x-r-none-4_8_2-x86_64-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/lib/gcc/armv6hl-unknown-linux-gnueabi/4.8.2/include-fixed        -isystem /home/ray/ctng-firefox-builds/x-r-none-4_8_2-x86_64-d/armv6hl-unknown-linux-gnueabi/sysroot/usr/include  -D_LIBC_REENTRANT -include ../include/libc-symbols.h   -DNOT_IN_libc=1 -DIS_IN_libpthread=1 -DIN_LIB=libpthread    -o /home/ray/ctng-firefox-builds/ctng-build-x-r-none-4_8_2-x86_64-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/nptl/pthread_spin_lock.o -MD -MP -MF /home/ray/ctng-firefox-builds/ctng-build-x-r-none-4_8_2-x86_64-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/nptl/pthread_spin_lock.o.dt -MT /home/ray/ctng-firefox-builds/ctng-build-x-r-none-4_8_2-x86_64-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/nptl/pthread_spin_lock.o

ignoring duplicate directory "."
#include "..." search starts here:
#include <...> search starts here:
 ../include
 /home/ray/ctng-firefox-builds/ctng-build-x-r-none-4_8_2-x86_64-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/nptl
 /home/ray/ctng-firefox-builds/ctng-build-x-r-none-4_8_2-x86_64-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final
 ../ports/sysdeps/unix/sysv/linux/arm/nptl
 ../ports/sysdeps/unix/sysv/linux/arm
 ../nptl/sysdeps/unix/sysv/linux
 ../nptl/sysdeps/pthread
 ../sysdeps/pthread
 ../ports/sysdeps/unix/sysv/linux
 ../sysdeps/unix/sysv/linux
 ../sysdeps/gnu
 ../sysdeps/unix/inet
 ../nptl/sysdeps/unix/sysv
 ../ports/sysdeps/unix/sysv
 ../sysdeps/unix/sysv
 ../ports/sysdeps/unix/arm
 ../nptl/sysdeps/unix
 ../ports/sysdeps/unix
 ../sysdeps/unix
 ../sysdeps/posix
 ../ports/sysdeps/arm/armv6
 ../ports/sysdeps/arm/nptl
 ../ports/sysdeps/arm/include
 ../ports/sysdeps/arm
 ../ports/sysdeps/arm/soft-fp
 ../sysdeps/wordsize-32
 ../sysdeps/ieee754/flt-32
 ../sysdeps/ieee754/dbl-64
 ../sysdeps/ieee754
 ../sysdeps/generic
 ../nptl
 ../ports
 ..
 ../libio
 /home/ray/ctng-firefox-builds/ctng-build-x-r-none-4_8_2-x86_64-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/lib/gcc/armv6hl-unknown-linux-gnueabi/4.8.2/include
 /home/ray/ctng-firefox-builds/ctng-build-x-r-none-4_8_2-x86_64-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/lib/gcc/armv6hl-unknown-linux-gnueabi/4.8.2/include-fixed
 /home/ray/ctng-firefox-builds/x-r-none-4_8_2-x86_64-d/armv6hl-unknown-linux-gnueabi/sysroot/usr/include
 


.. So the include dirs are pretty similar.
--save-temps gives some more info.
From Linux:
# 1 "<command-line>" 2
# 1 "../ports/sysdeps/arm/nptl/pthread_spin_lock.c"
# 23 "../ports/sysdeps/arm/nptl/pthread_spin_lock.c"
# 1 "../sysdeps/../nptl/pthread_spin_lock.c" 1
# 19 "../sysdeps/../nptl/pthread_spin_lock.c"
# 1 "../include/atomic.h" 1
# 48 "../include/atomic.h"
# 1 "../include/stdlib.h" 1

From Windows:
# 1 "<command-line>" 2
# 1 "../ports/sysdeps/arm/nptl/pthread_spin_lock.c"
# 23 "../ports/sysdeps/arm/nptl/pthread_spin_lock.c"
# 1 "../ports/sysdeps/arm/sysdeps/../nptl/pthread_spin_lock.c" 1
# 23 "../ports/sysdeps/arm/sysdeps/../nptl/pthread_spin_lock.c"
# 1 "../ports/sysdeps/arm/sysdeps/../nptl/pthread_spin_lock.c" 1
# 23 "../ports/sysdeps/arm/sysdeps/../nptl/pthread_spin_lock.c"


#include <sysdeps/../nptl/pthread_spin_lock.c>


Then it fails again at:
[ALL  ]    armv6hl-unknown-linux-gnueabi-gcc       -nostdlib -nostartfiles -r -o /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/elf/librtld.map.o '-Wl,-(' /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/elf/dl-allobjs.os /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/libc_pic.a -lgcc '-Wl,-)' -Wl,-Map,/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/elf/librtld.mapT
[ALL  ]    rm -f /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/elf/librtld.map.o
[ALL  ]    mv -f /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/elf/librtld.mapT /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/elf/librtld.map
[ALL  ]    LC_ALL=C sed -n 's@^/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/([^(]*)(([^)]*.os)) *.*$@1 2@p'     /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/elf/librtld.map | while read lib file; do   case $lib in   libc_pic.a)     LC_ALL=C fgrep -l /$file 	  /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/stamp.os /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/*/stamp.os |     LC_ALL=C     sed 's@^/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/([^/]*)/stamp.os$@rtld-1'" +=$file@"    ;;   */*.a)     echo rtld-${lib%%/*} += $file ;;   *) echo "Wasn't expecting $lib($file)" >&2; exit 1 ;;   esac; done > /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/elf/librtld.mkT
[ALL  ]    echo rtld-subdirs = `LC_ALL=C sed 's/^rtld-([^ ]*).*$/1/' /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/elf/librtld.mkT 		     | LC_ALL=C sort -u` >> /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/elf/librtld.mkT
[ALL  ]    mv -f /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/elf/librtld.mkT /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/elf/librtld.mk
[ALL  ]    /usr/bin/make -f /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/elf/librtld.mk -f rtld-Rules
[ALL  ]    make[4]: Entering directory '/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/src/eglibc-2_18/elf'
[ALL  ]    rtld-Rules:40: *** missing separator (did you mean TAB instead of 8 spaces?).  Stop.
[ALL  ]    make[4]: Leaving directory '/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/src/eglibc-2_18/elf'
[ALL  ]    Makefile:310: recipe for target '/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/elf/rtld-libc.a' failed
[ERROR]    make[3]: *** [/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/elf/rtld-libc.a] Error 2
[ALL  ]    make[3]: Leaving directory '/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/src/eglibc-2_18/elf'
[ALL  ]    Makefile:256: recipe for target 'elf/subdir_lib' failed
[ERROR]    make[2]: *** [elf/subdir_lib] Error 2
[ALL  ]    make[2]: Leaving directory '/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/src/eglibc-2_18'
[ALL  ]    Makefile:9: recipe for target 'all' failed
[ERROR]    make[1]: *** [all] Error 2
[ALL  ]    make[1]: Leaving directory '/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final'

Problem is that:
C:\ctng-build-x-r-none-4_8_2-x86_64-235295c4-d\.build\armv6hl-unknown-linux-gnueabi\build\build-libc-final\elf\librtld.mk
Contains only:
rtld-subdirs =

while on Linux it contains:rtld-csu +=check_fds.os
rtld-csu +=errno.os
rtld-csu +=divdi3.os
rtld-setjmp +=setjmp.os
rtld-setjmp +=__longjmp.os
rtld-string +=strchr.os
rtld-string +=strcmp.os
rtld-string +=strcpy.os
..
..
..
..
rtld-subdirs = csu dirent gmon io misc nptl posix setjmp signal stdlib string time



On Linux:
[ALL  ]    armv6hl-unknown-linux-gnueabi-gcc       -nostdlib -nostartfiles -r -o /home/ray/ctng-firefox-builds/ctng-build-x-r-none-4_8_2-x86_64-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/elf/librtld.map.o '-Wl,-(' /home/ray/ctng-firefox-builds/ctng-build-x-r-none-4_8_2-x86_64-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/elf/dl-allobjs.os /home/ray/ctng-firefox-builds/ctng-build-x-r-none-4_8_2-x86_64-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/libc_pic.a -lgcc '-Wl,-)' -Wl,-Map,/home/ray/ctng-firefox-builds/ctng-build-x-r-none-4_8_2-x86_64-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/elf/librtld.mapT
[ALL  ]    rm -f /home/ray/ctng-firefox-builds/ctng-build-x-r-none-4_8_2-x86_64-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/elf/librtld.map.o
[ALL  ]    mv -f /home/ray/ctng-firefox-builds/ctng-build-x-r-none-4_8_2-x86_64-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/elf/librtld.mapT /home/ray/ctng-firefox-builds/ctng-build-x-r-none-4_8_2-x86_64-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/elf/librtld.map
[ALL  ]    LC_ALL=C sed -n 's@^/home/ray/ctng-firefox-builds/ctng-build-x-r-none-4_8_2-x86_64-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/([^(]*)(([^)]*.os)) *.*$@1 2@p'     /home/ray/ctng-firefox-builds/ctng-build-x-r-none-4_8_2-x86_64-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/elf/librtld.map | while read lib file; do   case $lib in   libc_pic.a)     LC_ALL=C fgrep -l /$file 	  /home/ray/ctng-firefox-builds/ctng-build-x-r-none-4_8_2-x86_64-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/stamp.os /home/ray/ctng-firefox-builds/ctng-build-x-r-none-4_8_2-x86_64-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/*/stamp.os |     LC_ALL=C     sed 's@^/home/ray/ctng-firefox-builds/ctng-build-x-r-none-4_8_2-x86_64-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/([^/]*)/stamp.os$@rtld-1'" +=$file@"    ;;   */*.a)     echo rtld-${lib%%/*} += $file ;;   *) echo "Wasn't expecting $lib($file)" >&2; exit 1 ;;   esac; done > /home/ray/ctng-firefox-builds/ctng-build-x-r-none-4_8_2-x86_64-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/elf/librtld.mkT
[ALL  ]    echo rtld-subdirs = `LC_ALL=C sed 's/^rtld-([^ ]*).*$/1/' /home/ray/ctng-firefox-builds/ctng-build-x-r-none-4_8_2-x86_64-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/elf/librtld.mkT 		     | LC_ALL=C sort -u` >> /home/ray/ctng-firefox-builds/ctng-build-x-r-none-4_8_2-x86_64-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/elf/librtld.mkT
[ALL  ]    mv -f /home/ray/ctng-firefox-builds/ctng-build-x-r-none-4_8_2-x86_64-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/elf/librtld.mkT /home/ray/ctng-firefox-builds/ctng-build-x-r-none-4_8_2-x86_64-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/elf/librtld.mk
[ALL  ]    /usr/bin/make -f /home/ray/ctng-firefox-builds/ctng-build-x-r-none-4_8_2-x86_64-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/elf/librtld.mk -f rtld-Rules

On Windows:
[ALL  ]    armv6hl-unknown-linux-gnueabi-gcc       -nostdlib -nostartfiles -r -o /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/elf/librtld.map.o '-Wl,-(' /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/elf/dl-allobjs.os /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/libc_pic.a -lgcc '-Wl,-)' -Wl,-Map,/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/elf/librtld.mapT
[ALL  ]    rm -f /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/elf/librtld.map.o
[ALL  ]    mv -f /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/elf/librtld.mapT /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/elf/librtld.map
[ALL  ]    LC_ALL=C sed -n 's@^/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/([^(]*)(([^)]*.os)) *.*$@1 2@p'     /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/elf/librtld.map | while read lib file; do   case $lib in   libc_pic.a)     LC_ALL=C fgrep -l /$file 	  /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/stamp.os /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/*/stamp.os |     LC_ALL=C     sed 's@^/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/([^/]*)/stamp.os$@rtld-1'" +=$file@"    ;;   */*.a)     echo rtld-${lib%%/*} += $file ;;   *) echo "Wasn't expecting $lib($file)" >&2; exit 1 ;;   esac; done > /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/elf/librtld.mkT
[ALL  ]    echo rtld-subdirs = `LC_ALL=C sed 's/^rtld-([^ ]*).*$/1/' /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/elf/librtld.mkT 		     | LC_ALL=C sort -u` >> /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/elf/librtld.mkT
[ALL  ]    mv -f /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/elf/librtld.mkT /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/elf/librtld.mk
[ALL  ]    /usr/bin/make -f /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/elf/librtld.mk -f rtld-Rules


LC_ALL=C sed -n 's@^/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/([^(]*)(([^)]*.os)) *.*$@1 2@p'     /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/elf/librtld.map | while read lib file; do   case $lib in   libc_pic.a)     LC_ALL=C fgrep -l /$file 	  /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/stamp.os /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/*/stamp.os |     LC_ALL=C     sed 's@^/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/([^/]*)/stamp.os$@rtld-1'" +=$file@"    ;;   */*.a)     echo rtld-${lib%%/*} += $file ;;   *) echo "Wasn't expecting $lib($file)" >&2; exit 1 ;;   esac; done > /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/elf/librtld.mkT
The map file above ( C:\ctng-build-x-r-none-4_8_2-x86_64-235295c4-d\.build\armv6hl-unknown-linux-gnueabi\build\build-libc-final\elf\librtld.map ) has Windows paths, the SED command is expecting MSYS2 paths .. hmm.
.. also, those Windows paths are of form:
C:/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/libc_pic.a(setitimer.os)
                              C:/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/libc_pic.a(profil.os) (__setitimer)
c:/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/bin/../lib/gcc/armv6hl-unknown-linux-gnueabi/4.8.2\libgcc.a(_udivsi3.o)

.. ie both C: and c: are present .. the /..lib/ ones are all c:/

.. there are two problems with this:
1. c:/ is no good.
2. ../lib/ is no good.
If both those were fixed and the sed used Windows paths we'd get further. actually just the sed path needs fixing really.

mkdir /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final-new
export PATH=/home/ray/ctng-firefox-builds/x-r-none-4_8_2-x86_64-235295c4-d/bin:/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/bin:/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/tools/bin:/home/ray/ctng-firefox-builds/mingw64-235295c4/bin:/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/bin:/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/bin:"$PATH"
pushd /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final-new
# --cache-file=/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/config.cache
BUILD_CC=x86_64-build_w64-mingw32-gcc CFLAGS="-U_FORTIFY_SOURCE  -mlittle-endian -march=armv6   -mtune=arm1176jzf-s -mfpu=vfp -mhard-float  -O2" CC=armv6hl-unknown-linux-gnueabi-gcc AR=armv6hl-unknown-linux-gnueabi-ar RANLIB=armv6hl-unknown-linux-gnueabi-ranlib /usr/bin/bash /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/src/eglibc-2_18/configure --prefix=/usr --build=x86_64-build_w64-mingw32 --host=armv6hl-unknown-linux-gnueabi --without-cvs --disable-profile --without-gd --with-headers=/home/ray/ctng-firefox-builds/x-r-none-4_8_2-x86_64-235295c4-d/armv6hl-unknown-linux-gnueabi/sysroot/usr/include --libdir=/usr/lib/. --enable-obsolete-rpc --enable-kernel=3.10.19 --with-__thread --with-tls --enable-shared --with-fp --enable-add-ons=nptl,ports --with-pkgversion=crosstool-NG hg+unknown-20131223.134916
make -j 10

# Okay it is time to normalise all GCC paths.

Some GCC paths are C: and full of /, these are good.
armv6hl-unknown-linux-gnueabi-gcc -print-search-dirs | tr ';' '\n' | grep 'C:'
C:/msys64/home/ray/ctng-firefox-builds/x-r-none-4_8_2-x86_64-235295c4-d/armv6hl-unknown-linux-gnueabi/sysroot/lib/armv6hl-unknown-linux-gnueabi/4.8.2/
C:/msys64/home/ray/ctng-firefox-builds/x-r-none-4_8_2-x86_64-235295c4-d/armv6hl-unknown-linux-gnueabi/sysroot/lib/
C:/msys64/home/ray/ctng-firefox-builds/x-r-none-4_8_2-x86_64-235295c4-d/armv6hl-unknown-linux-gnueabi/sysroot/usr/lib/armv6hl-unknown-linux-gnueabi/4.8.2/
C:/msys64/home/ray/ctng-firefox-builds/x-r-none-4_8_2-x86_64-235295c4-d/armv6hl-unknown-linux-gnueabi/sysroot/usr/lib/

Some GCC paths are c: and mixed with / and \ these are not good.
armv6hl-unknown-linux-gnueabi-gcc -print-search-dirs | tr ';' '\n' | grep 'c:'
install: c:\ctng-build-x-r-none-4_8_2-x86_64-235295c4-d\.build\armv6hl-unknown-linux-gnueabi\buildtools\bin\../lib/gcc/armv6hl-unknown-linux-gnueabi/4.8.2/
programs: =c:/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/bin/../libexec/gcc/armv6hl-unknown-linux-gnueabi/4.8.2/
c:/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/bin/../libexec/gcc/
c:/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/bin/../lib/gcc/armv6hl-unknown-linux-gnueabi/4.8.2/../../../../armv6hl-unknown-linux-gnueabi/bin/armv6hl-unknown-linux-gnueabi/4.8.2/
c:/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/bin/../lib/gcc/armv6hl-unknown-linux-gnueabi/4.8.2/../../../../armv6hl-unknown-linux-gnueabi/bin/
libraries: =c:/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/bin/../lib/gcc/armv6hl-unknown-linux-gnueabi/4.8.2/
c:/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/bin/../lib/gcc/
c:/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/bin/../lib/gcc/armv6hl-unknown-linux-gnueabi/4.8.2/../../../../armv6hl-unknown-linux-gnueabi/lib/armv6hl-unknown-linux-gnueabi/4.8.2/
c:/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/bin/../lib/gcc/armv6hl-unknown-linux-gnueabi/4.8.2/../../../../armv6hl-unknown-linux-gnueabi/lib/

.. We got:
-DSTANDARD_EXEC_PREFIX="/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/lib/gcc/"


.. first problem is:
C:\ctng-build-x-r-none-4_8_2-x86_64-235295c4-d\.build\src\gcc-4.8.2\libiberty\make-relative-prefix.c
if (resolve_links)
  full_progname = lrealpath (progname);
lrealpath turns a nice path - C:/ into horrible - c:\



# From Linux headers:
+cc_machine := $(shell $(CC) -dumpmachine)
+ifneq (, $(findstring linux, $(cc_machine)))
+  ifneq (, $(findstring mingw, $(cc_machine)))
+  endif
+endif

C:\ctng-build-x-r-none-4_8_2-x86_64-235295c4-d\.build\src\eglibc-2_18\elf\Makefile
uname_o := $(shell $(uname -o))
ifneq (, $(findstring Msys, $(uname_o))
endif



.. 

The core shell script that fails (masaged enough to work!) is:
pushd /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final-new

INPUT=/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final-new/elf/librtld.map
common_objpfxh=C:/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final-new/
LC_ALL=C sed -n 's@^'${common_objpfxh}'\([^(]*\)(\([^)]*\.os\)) *.*$@\1 \2@p' ${INPUT} | \
while read lib file; do
    case $lib in
        libc_pic.a)
#            echo LC_ALL=C fgrep -l $file ${common_objpfxh}stamp.os ${common_objpfxh}*/stamp.os \| LC_ALL=C sed 's@^'${common_objpfxh}'\([^.]*\)/stamp\.os$@rtld-\1'
            LC_ALL=C fgrep -l $file ${common_objpfxh}stamp.os ${common_objpfxh}*/stamp.os | LC_ALL=C sed 's@^'${common_objpfxh}'\([^/]*\)/stamp\.os$@rtld-\1'" +=$file@"
            ;;
        */*.a)
            echo rtld-${lib%/*} += $file
            ;;
        *) echo "Wasn't expecting $lib($file)"
    esac;
done


# A working example:
LC_ALL=C fgrep -l munmap.os C:/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final-new/stamp.os C:/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final-new/argp/stamp.os C:/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final-new/assert/stamp.os C:/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final-new/catgets/stamp.os C:/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final-new/conform/stamp.os C:/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final-new/crypt/stamp.os C:/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final-new/csu/stamp.os C:/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final-new/ctype/stamp.os C:/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final-new/debug/stamp.os C:/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final-new/dirent/stamp.os C:/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final-new/dlfcn/stamp.os C:/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final-new/elf/stamp.os C:/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final-new/gmon/stamp.os C:/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final-new/gnulib/stamp.os C:/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final-new/grp/stamp.os C:/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final-new/gshadow/stamp.os C:/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final-new/hesiod/stamp.os C:/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final-new/iconv/stamp.os C:/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final-new/iconvdata/stamp.os C:/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final-new/inet/stamp.os C:/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final-new/intl/stamp.os C:/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final-new/io/stamp.os C:/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final-new/libio/stamp.os C:/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final-new/locale/stamp.os C:/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final-new/localedata/stamp.os C:/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final-new/login/stamp.os C:/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final-new/malloc/stamp.os C:/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final-new/manual/stamp.os C:/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final-new/math/stamp.os C:/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final-new/misc/stamp.os C:/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final-new/nis/stamp.os C:/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final-new/nptl/stamp.os C:/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final-new/nptl_db/stamp.os C:/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final-new/nscd/stamp.os C:/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final-new/nss/stamp.os C:/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final-new/po/stamp.os C:/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final-new/posix/stamp.os C:/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final-new/pwd/stamp.os C:/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final-new/resolv/stamp.os C:/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final-new/resource/stamp.os C:/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final-new/rt/stamp.os C:/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final-new/setjmp/stamp.os C:/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final-new/shadow/stamp.os C:/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final-new/signal/stamp.os C:/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final-new/socket/stamp.os C:/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final-new/stdio-common/stamp.os C:/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final-new/stdlib/stamp.os C:/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final-new/streams/stamp.os C:/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final-new/string/stamp.os C:/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final-new/sunrpc/stamp.os C:/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final-new/sysvipc/stamp.os C:/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final-new/termios/stamp.os C:/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final-new/time/stamp.os C:/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final-new/timezone/stamp.os C:/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final-new/wcsmbs/stamp.os C:/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final-new/wctype/stamp.os | LC_ALL=C sed 's@^C:/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final-new/\([^.]*\)/stamp\.os$@rtld-\1'"@"


# Latest is:

$(objpfx)librtld.mk: $(objpfx)librtld.map Makefile
	LC_ALL=C \
	sed -n 's@^$(common-objpfxh)\([^(]*\)(\([^)]*\.os\)) *.*$$@\1 \2@p' \
	    $< | \
	while read lib file; do \
	  case $$lib in \
	  libc_pic.a) \
	    LC_ALL=C fgrep -l /$$file \
		  $(common-objpfxh)stamp.os $(common-objpfxh)*/stamp.os | \
	    LC_ALL=C \
	    sed 's@^$(common-objpfxh)\([^/]*\)/stamp\.os$$@rtld-\1'" +=$$file@"\
	    ;; \
	  */*.a) \
	    echo rtld-$${lib%%/*} += $$file ;; \
	  *) echo "Wasn't expecting $$lib($$file)" >&2; exit 1 ;; \
	  esac; \
	done > $@T
	echo rtld-subdirs = `LC_ALL=C sed 's/^rtld-\([^ ]*\).*$$/\1/' $@T \
			     | LC_ALL=C sort -u` >> $@T
	mv -f $@T $@


$(objpfx)rtld-libc.a: $(objpfx)librtld.mk FORCE
	$(MAKE) -f $< -f rtld-Rules



push /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final-new
export PATH=/home/ray/ctng-firefox-builds/x-r-none-4_8_2-x86_64-235295c4-d/bin:/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/bin:/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/tools/bin:/home/ray/ctng-firefox-builds/mingw64-235295c4/bin:/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/bin:/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/bin:"$PATH"

# Windows:

armv6hl-unknown-linux-gnueabi-gcc \
-nostdlib -nostartfiles -o /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final-new/iconv/iconvconfig    \
-Wl,-z,combreloc -Wl,-z,relro -Wl,--hash-style=both /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final-new/csu/crt1.o \
/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final-new/csu/crti.o \
`armv6hl-unknown-linux-gnueabi-gcc --print-file-name=crtbegin.o` \
/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final-new/iconv/iconvconfig.o \
/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final-new/iconv/strtab.o \
/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final-new/iconv/xmalloc.o \
/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final-new/iconv/hash-string.o  \
-Wl,-dynamic-linker=/lib/ld-linux-armhf.so.3 \
-Wl,-rpath-link=/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final-new:/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final-new/math:/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final-new/elf:/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final-new/dlfcn:/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final-new/nss:/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final-new/nis:/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final-new/rt:/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final-new/resolv:/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final-new/crypt:/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final-new/nptl \
/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final-new/libc.so.6 \
/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final-new/libc_nonshared.a \
-Wl,--as-needed /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final-new/elf/ld.so -Wl,--no-as-needed \
-lgcc \
/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final-new/elf/libgcc-stubs.a \
`armv6hl-unknown-linux-gnueabi-gcc  --print-file-name=crtend.o` \
/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final-new/csu/crtn.o


# Linux:

armv6hl-unknown-linux-gnueabi-gcc     \
-nostdlib -nostartfiles -o /home/ray/ctng-firefox-builds/ctng-build-x-r-none-4_8_2-x86_64-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/iconv/iconvconfig    \
-Wl,-z,combreloc -Wl,-z,relro -Wl,--hash-style=both /home/ray/ctng-firefox-builds/ctng-build-x-r-none-4_8_2-x86_64-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/csu/crt1.o \
/home/ray/ctng-firefox-builds/ctng-build-x-r-none-4_8_2-x86_64-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/csu/crti.o \
`armv6hl-unknown-linux-gnueabi-gcc --print-file-name=crtbegin.o` \
/home/ray/ctng-firefox-builds/ctng-build-x-r-none-4_8_2-x86_64-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/iconv/iconvconfig.o \
/home/ray/ctng-firefox-builds/ctng-build-x-r-none-4_8_2-x86_64-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/iconv/strtab.o \
/home/ray/ctng-firefox-builds/ctng-build-x-r-none-4_8_2-x86_64-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/iconv/xmalloc.o \
/home/ray/ctng-firefox-builds/ctng-build-x-r-none-4_8_2-x86_64-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/iconv/hash-string.o  \
-Wl,-dynamic-linker=/lib/ld-linux-armhf.so.3 \
-Wl,-rpath-link=/home/ray/ctng-firefox-builds/ctng-build-x-r-none-4_8_2-x86_64-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final:/home/ray/ctng-firefox-builds/ctng-build-x-r-none-4_8_2-x86_64-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/math:/home/ray/ctng-firefox-builds/ctng-build-x-r-none-4_8_2-x86_64-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/elf:/home/ray/ctng-firefox-builds/ctng-build-x-r-none-4_8_2-x86_64-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/dlfcn:/home/ray/ctng-firefox-builds/ctng-build-x-r-none-4_8_2-x86_64-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/nss:/home/ray/ctng-firefox-builds/ctng-build-x-r-none-4_8_2-x86_64-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/nis:/home/ray/ctng-firefox-builds/ctng-build-x-r-none-4_8_2-x86_64-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/rt:/home/ray/ctng-firefox-builds/ctng-build-x-r-none-4_8_2-x86_64-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/resolv:/home/ray/ctng-firefox-builds/ctng-build-x-r-none-4_8_2-x86_64-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/crypt:/home/ray/ctng-firefox-builds/ctng-build-x-r-none-4_8_2-x86_64-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/nptl \
/home/ray/ctng-firefox-builds/ctng-build-x-r-none-4_8_2-x86_64-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/libc.so.6 \
/home/ray/ctng-firefox-builds/ctng-build-x-r-none-4_8_2-x86_64-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/libc_nonshared.a \
-Wl,--as-needed /home/ray/ctng-firefox-builds/ctng-build-x-r-none-4_8_2-x86_64-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/elf/ld.so -Wl,--no-as-needed \
-lgcc \
/home/ray/ctng-firefox-builds/ctng-build-x-r-none-4_8_2-x86_64-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/elf/libgcc-stubs.a \
`armv6hl-unknown-linux-gnueabi-gcc      --print-file-name=crtend.o` \
/home/ray/ctng-firefox-builds/ctng-build-x-r-none-4_8_2-x86_64-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/csu/crtn.o


probably want to figure out the catgets.c warnings:
Windows:
pushd /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/src/eglibc-2_18/catgets
export PATH=/home/ray/ctng-firefox-builds/x-r-none-4_8_2-x86_64-235295c4-d/bin:/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/bin:/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/tools/bin:/home/ray/ctng-firefox-builds/mingw64-235295c4/bin:/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/bin:/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/bin:"$PATH"
armv6hl-unknown-linux-gnueabi-gcc     catgets.c -c -std=gnu99 -fgnu89-inline  -O2 -U_FORTIFY_SOURCE -Wall -Winline -Wwrite-strings -fmerge-all-constants -frounding-math -march=armv6 -mfpu=vfp -mhard-float -mlittle-endian -mtune=arm1176jzf-s -Wstrict-prototypes        -DNLSPATH='"/usr/share/locale/%L/%N:/usr/share/locale/%L/LC_MESSAGES/%N:/usr/share/locale/%l/%N:/usr/share/locale/%l/LC_MESSAGES/%N:"' -DHAVE_CONFIG_H -I../include -I/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/catgets  -I/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final  -I../ports/sysdeps/unix/sysv/linux/arm/nptl  -I../ports/sysdeps/unix/sysv/linux/arm  -I../nptl/sysdeps/unix/sysv/linux  -I../nptl/sysdeps/pthread  -I../sysdeps/pthread  -I../ports/sysdeps/unix/sysv/linux  -I../sysdeps/unix/sysv/linux  -I../sysdeps/gnu  -I../sysdeps/unix/inet  -I../nptl/sysdeps/unix/sysv  -I../ports/sysdeps/unix/sysv  -I../sysdeps/unix/sysv  -I../ports/sysdeps/unix/arm  -I../nptl/sysdeps/unix  -I../ports/sysdeps/unix  -I../sysdeps/unix  -I../sysdeps/posix  -I../ports/sysdeps/arm/armv6  -I../ports/sysdeps/arm/nptl  -I../ports/sysdeps/arm/include -I../ports/sysdeps/arm  -I../ports/sysdeps/arm/soft-fp  -I../sysdeps/wordsize-32  -I../sysdeps/ieee754/flt-32  -I../sysdeps/ieee754/dbl-64  -I../sysdeps/ieee754  -I../sysdeps/generic  -I../nptl  -I../ports  -I.. -I../libio -I. -nostdinc -isystem C:/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/lib/gcc/armv6hl-unknown-linux-gnueabi/4.8.2/include -isystem C:/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/lib/gcc/armv6hl-unknown-linux-gnueabi/4.8.2/include-fixed -isystem /home/ray/ctng-firefox-builds/x-r-none-4_8_2-x86_64-235295c4-d/armv6hl-unknown-linux-gnueabi/sysroot/usr/include  -D_LIBC_REENTRANT -include ../include/libc-symbols.h       -o /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/catgets/catgets.o -MD -MP -MF /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/catgets/catgets.o.dt -MT /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/catgets/catgets.o --save-temps
mv catgets.i ~/Dropbox/catgets.windows.i
popd


Linux:
pushd /home/ray/ctng-firefox-builds/ctng-build-x-r-none-4_8_2-x86_64-d/.build/src/eglibc-2_18/catgets
export PATH=/home/ray/ctng-firefox-builds/x-r-none-4_8_2-x86_64-d/bin:/home/ray/ctng-firefox-builds/ctng-build-x-r-none-4_8_2-x86_64-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/bin:/home/ray/ctng-firefox-builds/ctng-build-x-r-none-4_8_2-x86_64-d/.build/tools/bin:"${PATH}"
armv6hl-unknown-linux-gnueabi-gcc     catgets.c -c -std=gnu99 -fgnu89-inline  -O2 -U_FORTIFY_SOURCE -Wall -Winline -Wwrite-strings -fmerge-all-constants -frounding-math -march=armv6 -mfpu=vfp -mhard-float -mlittle-endian -mtune=arm1176jzf-s -Wstrict-prototypes        -DNLSPATH='"/usr/share/locale/%L/%N:/usr/share/locale/%L/LC_MESSAGES/%N:/usr/share/locale/%l/%N:/usr/share/locale/%l/LC_MESSAGES/%N:"' -DHAVE_CONFIG_H -I../include -I/home/ray/ctng-firefox-builds/ctng-build-x-r-none-4_8_2-x86_64-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/catgets  -I/home/ray/ctng-firefox-builds/ctng-build-x-r-none-4_8_2-x86_64-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final  -I../ports/sysdeps/unix/sysv/linux/arm/nptl  -I../ports/sysdeps/unix/sysv/linux/arm  -I../nptl/sysdeps/unix/sysv/linux  -I../nptl/sysdeps/pthread  -I../sysdeps/pthread  -I../ports/sysdeps/unix/sysv/linux  -I../sysdeps/unix/sysv/linux  -I../sysdeps/gnu  -I../sysdeps/unix/inet  -I../nptl/sysdeps/unix/sysv  -I../ports/sysdeps/unix/sysv  -I../sysdeps/unix/sysv  -I../ports/sysdeps/unix/arm  -I../nptl/sysdeps/unix  -I../ports/sysdeps/unix  -I../sysdeps/unix  -I../sysdeps/posix  -I../ports/sysdeps/arm/armv6  -I../ports/sysdeps/arm/nptl  -I../ports/sysdeps/arm/include -I../ports/sysdeps/arm  -I../ports/sysdeps/arm/soft-fp  -I../sysdeps/wordsize-32  -I../sysdeps/ieee754/flt-32  -I../sysdeps/ieee754/dbl-64  -I../sysdeps/ieee754  -I../sysdeps/generic  -I../nptl  -I../ports  -I.. -I../libio -I. -nostdinc -isystem /home/ray/ctng-firefox-builds/ctng-build-x-r-none-4_8_2-x86_64-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/lib/gcc/armv6hl-unknown-linux-gnueabi/4.8.2/include -isystem /home/ray/ctng-firefox-builds/ctng-build-x-r-none-4_8_2-x86_64-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/lib/gcc/armv6hl-unknown-linux-gnueabi/4.8.2/include-fixed -isystem /home/ray/ctng-firefox-builds/x-r-none-4_8_2-x86_64-d/armv6hl-unknown-linux-gnueabi/sysroot/usr/include  -D_LIBC_REENTRANT -include ../include/libc-symbols.h       -o /home/ray/ctng-firefox-builds/ctng-build-x-r-none-4_8_2-x86_64-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/catgets/catgets.o -MD -MP -MF /home/ray/ctng-firefox-builds/ctng-build-x-r-none-4_8_2-x86_64-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/catgets/catgets.o.dt -MT /home/ray/ctng-firefox-builds/ctng-build-x-r-none-4_8_2-x86_64-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/catgets/catgets.o --save-temps
mv catgets.i ~/Dropbox/catgets.linux.i


.. the difference is:
Linux:
size_t len = strlen (nlspath) + 1 + sizeof "/usr/share/locale/%L/%N:/usr/share/locale/%L/LC_MESSAGES/%N:/usr/share/locale/%l/%N:/usr/share/locale/%l/LC_MESSAGES/%N:";
char *tmp = __builtin_alloca (len);

__builtin_stpcpy (__builtin_stpcpy (__builtin_stpcpy (tmp, nlspath), ":"), "/usr/share/locale/%L/%N:/usr/share/locale/%L/LC_MESSAGES/%N:/usr/share/locale/%l/%N:/usr/share/locale/%l/LC_MESSAGES/%N:");
nlspath = tmp;
}
   else
nlspath = "/usr/share/locale/%L/%N:/usr/share/locale/%L/LC_MESSAGES/%N:/usr/share/locale/%l/%N:/usr/share/locale/%l/LC_MESSAGES/%N:";
 }

Windows:
size_t len = strlen (nlspath) + 1 + sizeof "C:\msys64\share\locale\%L\%N;C:\msys64\share\locale\%L\LC_MESSAGES\%N;C:\msys64\share\locale\%l\%N;C:\msys64\share\locale\%l\LC_MESSAGES\%N";
char *tmp = __builtin_alloca (len);

__builtin_stpcpy (__builtin_stpcpy (__builtin_stpcpy (tmp, nlspath), ":"), "C:\msys64\share\locale\%L\%N;C:\msys64\share\locale\%L\LC_MESSAGES\%N;C:\msys64\share\locale\%l\%N;C:\msys64\share\locale\%l\LC_MESSAGES\%N");
nlspath = tmp;
}
   else
nlspath = "C:\msys64\share\locale\%L\%N;C:\msys64\share\locale\%L\LC_MESSAGES\%N;C:\msys64\share\locale\%l\%N;C:\msys64\share\locale\%l\LC_MESSAGES\%N";
 }



Still missing in build-libc-final/elf/librtld.mk :

rtld-csu +=check_fds.os
rtld-csu +=errno.os
rtld-csu +=divdi3.os

rtld-io +=xstat64.os
rtld-io +=fxstat64.os
rtld-io +=lxstat64.os
rtld-io +=open.os
rtld-io +=read.os
rtld-io +=write.os
rtld-io +=lseek.os
rtld-io +=access.os
rtld-io +=fcntl.os
rtld-io +=close.os

rtld-nptl +=libc-cancellation.os
rtld-nptl +=libc_multiple_threads.os
rtld-csu +=sysdep.os

rtld-nptl +=forward.os
rtld-stdlib +=exit.os
rtld-stdlib +=cxa_atexit.os
rtld-stdlib +=cxa_thread_atexit_impl.os

and finally subdirs:
rtld-subdirs = csu dirent gmon io misc nptl posix setjmp signal stdlib string time (Linux)
rtld-subdirs =     dirent gmon    misc nptl posix setjmp signal        string time (Windows - missing is csu, io, stdlib)


Linux:
[ALL  ]    /usr/bin/make subdir=stdlib -C ../stdlib ..=../ objdir=/home/ray/ctng-firefox-builds/ctng-build-x-r-none-4_8_2-x86_64-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final -f Makefile -f ../elf/rtld-Rules rtld-all rtld-modules='rtld-exit.os rtld-cxa_atexit.os rtld-cxa_thread_atexit_impl.os'
[ALL  ]    /usr/bin/make subdir=stdlib -C ../stdlib ..=../ objdir=/home/ray/ctng-firefox-builds/ctng-build-x-r-none-4_8_2-x86_64-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final -f Makefile -f ../elf/rtld-Rules rtld-all rtld-modules='rtld-exit.os rtld-cxa_atexit.os rtld-cxa_thread_atexit_impl.os'
[ALL  ]    /usr/bin/make subdir=stdlib -C ../stdlib ..=../ objdir=/home/ray/ctng-firefox-builds/ctng-build-x-r-none-4_8_2-x86_64-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final -f Makefile -f ../elf/rtld-Rules rtld-all rtld-modules='rtld-exit.os rtld-cxa_atexit.os rtld-cxa_thread_atexit_impl.os'
[ALL  ]    /usr/bin/make subdir=stdlib -C ../stdlib ..=../ objdir=/home/ray/ctng-firefox-builds/ctng-build-x-r-none-4_8_2-x86_64-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final -f Makefile -f ../elf/rtld-Rules rtld-all rtld-modules='rtld-exit.os rtld-cxa_atexit.os rtld-cxa_thread_atexit_impl.os'
[ALL  ]    /usr/bin/make subdir=stdlib -C ../stdlib ..=../ objdir=/home/ray/ctng-firefox-builds/ctng-build-x-r-none-4_8_2-x86_64-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final -f Makefile -f ../elf/rtld-Rules rtld-all rtld-modules='rtld-exit.os rtld-cxa_atexit.os rtld-cxa_thread_atexit_impl.os'

.. well, that was case sensitivity between .os (shared object) files and .oS (static object) files. Renamed .oS to .oSTATIC

Next failure is:
[ALL  ]    /usr/bin/install -c /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/elf/ld.so /home/ray/ctng-firefox-builds/x-r-none-4_8_2-x86_64-235295c4-d/armv6hl-unknown-linux-gnueabi/sysroot/lib/ld-2.18.so.new
[ALL  ]    mv -f /home/ray/ctng-firefox-builds/x-r-none-4_8_2-x86_64-235295c4-d/armv6hl-unknown-linux-gnueabi/sysroot/lib/ld-2.18.so.new /home/ray/ctng-firefox-builds/x-r-none-4_8_2-x86_64-235295c4-d/armv6hl-unknown-linux-gnueabi/sysroot/lib/ld-2.18.so
[ALL  ]    /usr/bin/install -c /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/libc.so /home/ray/ctng-firefox-builds/x-r-none-4_8_2-x86_64-235295c4-d/armv6hl-unknown-linux-gnueabi/sysroot/lib/libc-2.18.so.new
[ALL  ]    mv -f /home/ray/ctng-firefox-builds/x-r-none-4_8_2-x86_64-235295c4-d/armv6hl-unknown-linux-gnueabi/sysroot/lib/libc-2.18.so.new /home/ray/ctng-firefox-builds/x-r-none-4_8_2-x86_64-235295c4-d/armv6hl-unknown-linux-gnueabi/sysroot/lib/libc-2.18.so
[ALL  ]    rm -f /home/ray/ctng-firefox-builds/x-r-none-4_8_2-x86_64-235295c4-d/armv6hl-unknown-linux-gnueabi/sysroot/lib/ld-linux-armhf.so.3
[ALL  ]    cp -p `../scripts/rellns-sh -p /home/ray/ctng-firefox-builds/x-r-none-4_8_2-x86_64-235295c4-d/armv6hl-unknown-linux-gnueabi/sysroot/lib/ld-2.18.so /home/ray/ctng-firefox-builds/x-r-none-4_8_2-x86_64-235295c4-d/armv6hl-unknown-linux-gnueabi/sysroot/lib/ld-linux-armhf.so.3` /home/ray/ctng-firefox-builds/x-r-none-4_8_2-x86_64-235295c4-d/armv6hl-unknown-linux-gnueabi/sysroot/lib/ld-linux-armhf.so.3
[ALL  ]    cp: cannot stat 'ld-2.18.so': No such file or directory
[ALL  ]    Makefile:376: recipe for target '/home/ray/ctng-firefox-builds/x-r-none-4_8_2-x86_64-235295c4-d/armv6hl-unknown-linux-gnueabi/sysroot/lib/ld-linux-armhf.so.3' failed
[ERROR]    make[3]: *** [/home/ray/ctng-firefox-builds/x-r-none-4_8_2-x86_64-235295c4-d/armv6hl-unknown-linux-gnueabi/sysroot/lib/ld-linux-armhf.so.3] Error 1
[ALL  ]    make[3]: Leaving directory '/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/src/eglibc-2_18/elf'
[ALL  ]    Makefile:104: recipe for target 'elf/ldso_install' failed
[ERROR]    make[2]: *** [elf/ldso_install] Error 2
[ALL  ]    make[2]: Leaving directory '/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/src/eglibc-2_18'
[ALL  ]    Makefile:12: recipe for target 'install' failed
[ERROR]    make[1]: *** [install] Error 2
[ALL  ]    make[1]: Leaving directory '/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final'
[ERROR]  
[ERROR]  >>
[ERROR]  >>  Build failed in step 'Installing C library'
[ERROR]  >>        called in step '(top-level)'
[ERROR]  >>
[ERROR]  >>  Error happened in: CT_DoExecLog[scripts/functions@257]
[ERROR]  >>        called from: do_libc_backend_once[scripts/build/libc/glibc-eglibc.sh-common@495]
[ERROR]  >>        called from: do_libc_backend[scripts/build/libc/glibc-eglibc.sh-common@158]
[ERROR]  >>        called from: do_libc[scripts/build/libc/glibc-eglibc.sh-common@65]
[ERROR]  >>        called from: main[scripts/crosstool-NG.sh@686]

On Linux we got:
[ALL  ]    /home/ray/ctng-firefox-builds/ctng-build-x-r-none-4_8_2-x86_64-d/.build/tools/bin/install -c /home/ray/ctng-firefox-builds/ctng-build-x-r-none-4_8_2-x86_64-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/elf/ld.so /home/ray/ctng-firefox-builds/x-r-none-4_8_2-x86_64-d/armv6hl-unknown-linux-gnueabi/sysroot/lib/ld-2.18.so.new
[ALL  ]    mv -f /home/ray/ctng-firefox-builds/x-r-none-4_8_2-x86_64-d/armv6hl-unknown-linux-gnueabi/sysroot/lib/ld-2.18.so.new /home/ray/ctng-firefox-builds/x-r-none-4_8_2-x86_64-d/armv6hl-unknown-linux-gnueabi/sysroot/lib/ld-2.18.so
[ALL  ]    /home/ray/ctng-firefox-builds/ctng-build-x-r-none-4_8_2-x86_64-d/.build/tools/bin/install -c /home/ray/ctng-firefox-builds/ctng-build-x-r-none-4_8_2-x86_64-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/libc.so /home/ray/ctng-firefox-builds/x-r-none-4_8_2-x86_64-d/armv6hl-unknown-linux-gnueabi/sysroot/lib/libc-2.18.so.new
[ALL  ]    mv -f /home/ray/ctng-firefox-builds/x-r-none-4_8_2-x86_64-d/armv6hl-unknown-linux-gnueabi/sysroot/lib/libc-2.18.so.new /home/ray/ctng-firefox-builds/x-r-none-4_8_2-x86_64-d/armv6hl-unknown-linux-gnueabi/sysroot/lib/libc-2.18.so
[ALL  ]    rm -f /home/ray/ctng-firefox-builds/x-r-none-4_8_2-x86_64-d/armv6hl-unknown-linux-gnueabi/sysroot/lib/ld-linux-armhf.so.3
[ALL  ]    ln -s `../scripts/rellns-sh -p /home/ray/ctng-firefox-builds/x-r-none-4_8_2-x86_64-d/armv6hl-unknown-linux-gnueabi/sysroot/lib/ld-2.18.so /home/ray/ctng-firefox-builds/x-r-none-4_8_2-x86_64-d/armv6hl-unknown-linux-gnueabi/sysroot/lib/ld-linux-armhf.so.3` /home/ray/ctng-firefox-builds/x-r-none-4_8_2-x86_64-d/armv6hl-unknown-linux-gnueabi/sysroot/lib/ld-linux-armhf.so.3
[ALL  ]    make[3]: Leaving directory '/home/ray/ctng-firefox-builds/ctng-build-x-r-none-4_8_2-x86_64-d/.build/src/eglibc-2_18/elf'

.. .. .. 
pushd /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/src/eglibc-2_18/elf
SOURCE=`../scripts/rellns-sh -p /home/ray/ctng-firefox-builds/x-r-none-4_8_2-x86_64-235295c4-d/armv6hl-unknown-linux-gnueabi/sysroot/lib/ld-2.18.so /home/ray/ctng-firefox-builds/x-r-none-4_8_2-x86_64-235295c4-d/armv6hl-unknown-linux-gnueabi/sysroot/lib/ld-linux-armhf.so.3`
DEST=/home/ray/ctng-firefox-builds/x-r-none-4_8_2-x86_64-235295c4-d/armv6hl-unknown-linux-gnueabi/sysroot/lib/ld-linux-armhf.so.3
cp -p $SOURCE $DEST


pushd /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final
make -j1 -l BUILD_CPPFLAGS=-I/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/include/ BUILD_LDFLAGS="-L/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/lib -Wl,-Bstatic -lintl -Wl,-Bdynamic" install_root=/home/ray/ctng-firefox-builds/x-r-none-4_8_2-x86_64-235295c4-d/armv6hl-unknown-linux-gnueabi/sysroot install

# --cache-file=/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-final/config.cache 
# Seems as if if "ln -s" was determined to be ok to use then it would work.

export PATH=/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/buildtools/bin:$HOME/ctng-firefox-builds/x-r-none-4_8_2-x86_64-235295c4-d/bin:"$PATH"

export PATH=/home/ray/ctng-firefox-builds/x-r-none-4_8_2-x86_64-235295c4-d/bin:/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/bin:/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/tools/bin:/home/ray/ctng-firefox-builds/mingw64-235295c4/bin:"${PATH}"

BUILD_CC=x86_64-build_w64-mingw32-gcc CFLAGS="-U_FORTIFY_SOURCE  -mlittle-endian -march=armv6   -mtune=arm1176jzf-s -mfpu=vfp -mhard-float  -O" \
  CC=armv6hl-unknown-linux-gnueabi-gcc AR=armv6hl-unknown-linux-gnueabi-ar RANLIB=armv6hl-unknown-linux-gnueabi-ranlib /usr/bin/bash /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/src/eglibc-2_18/configure \
  --prefix=/usr --build=x86_64-build_w64-mingw32 --host=armv6hl-unknown-linux-gnueabi \
  --without-cvs --disable-profile --without-gd --with-headers=/home/ray/ctng-firefox-builds/x-r-none-4_8_2-x86_64-235295c4-d/armv6hl-unknown-linux-gnueabi/sysroot/usr/include \
  --libdir=/usr/lib/. --enable-obsolete-rpc --enable-kernel=3.10.19 --with-__thread --with-tls --enable-shared --with-fp --enable-add-ons=nptl,ports --with-pkgversion=crosstool-NG hg+unknown-20131228.211220

# Back to Darwin kernel-headers failure.
export PATH=/Users/ray/ctng-firefox-builds/x-r-none-4_8_2-x86_64/bin:/Users/ray/ctng-firefox-builds/ctng-build-x-r-none-4_8_2-x86_64/.build/armv6hl-unknown-linux-gnueabi/buildtools/bin:/Users/ray/ctng-firefox-builds/ctng-build-x-r-none-4_8_2-x86_64/.build/tools/bin:"$PATH"

# Bug is that sh is being used by gnumake, but why, I am not sure.

# Getting this to repeat is not so easy!
pushd /Users/ray/ctng-firefox-builds/ctng-build-x-r-none-4_8_2-x86_64/.build/armv6hl-unknown-linux-gnueabi/build/build-kernel-headers
export PATH=/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4/.build/armv6hl-unknown-linux-gnueabi/buildtools/bin:/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/tools/bin:$HOME/ctng-firefox-builds/x-r-none-4_8_2-x86_64-235295c4-d/bin:"$PATH"
pushd /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/src
if [ -d linux-3.10.19 ]; then
rm -rf linux-3.10.19
fi
tar -xf ~/src/linux-3.10.19.tar.xz
popd
make -C /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/src/linux-3.10.19 O=/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-kernel-headers ARCH=arm INSTALL_HDR_PATH=/Users/ray/ctng-firefox-builds/x-r-none-4_8_2-x86_64-235295c4-d/armv6hl-unknown-linux-gnueabi/sysroot/usr V=1 headers_install




strncpy seems to already exist on OSX
export PATH=/Users/ray/ctng-firefox-builds/x-r-none-4_8_2-x86_64-235295c4-d/bin:/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/buildtools/bin:/c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/tools/bin:"$PATH"
pushd /c/ctng-build-x-r-none-4_8_2-x86_64-235295c4-d/.build/armv6hl-unknown-linux-gnueabi/build/build-libc-startfiles
make -j1 -l install_root=/Users/ray/ctng-firefox-builds/x-r-none-4_8_2-x86_64-235295c4-d/armv6hl-unknown-linux-gnueabi/sysroot install-bootstrap-headers=yes install-headers







export PATH=/home/ray/ctng-firefox-builds/x-o-none-apple_5666_3-x86_64-235295c4/bin:/c/ctng-build-x-o-none-apple_5666_3-x86_64-235295c4/.build/x86_64-apple-darwin10/buildtools/bin:/c/ctng-build-x-o-none-apple_5666_3-x86_64-235295c4/.build/tools/bin:"$PATH"
pushd /c/ctng-build-x-o-none-apple_5666_3-x86_64-235295c4/.build/x86_64-apple-darwin10/build/build-cc-gcc-final/fixincludes

[case $host in
	i?86-*-msdosdjgpp* | \
	i?86-*-mingw32* | \
	*-*-beos* )
		TARGET=twoprocess
		;;

	* )
		TARGET=oneprocess
		;;
esac])

^ simplify that right down!


# To quickly iterate installing kernel headers:
build_for_arch ()
{
ARCH=$1 ; shift
rm -rf linux-3.12
mkdir -p linux-3.12
tar --strip-components=1 -C linux-3.12 -x -f ~/src/linux-3.12.tar.xz
pushd linux-3.12
patch --no-backup-if-mismatch -g0 -F1 -p1 -f -i ~/ctng-firefox-builds/crosstool-ng/patches/linux/3.12/100-fixdep-fixes-for-Windows.patch
patch --no-backup-if-mismatch -g0 -F1 -p1 -f -i ~/ctng-firefox-builds/crosstool-ng/patches/linux/3.12/120-Win32-FreeBSD-use-upstream-unifdef.patch
patch --no-backup-if-mismatch -g0 -F1 -p1 -f -i ~/ctng-firefox-builds/crosstool-ng/patches/linux/3.12/130-disable-archscripts-due-to-elf_h-circular-dep.patch
popd
mkdir linux-3.12-builddir-$ARCH
mkdir linux-3.12-installdir-$ARCH
pushd linux-3.12-builddir-$ARCH
MAKEFLAGS="V=1" PATH=/mingw64/bin:$PATH make -C $PWD/../linux-3.12 O=$PWD ARCH=${ARCH} INSTALL_HDR_PATH=$PWD/../linux-3.12-installdir headers_install > build.log 2>&1 
popd
}

build_for_arch x86
build_for_arch arm

pushd /c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-cc-gcc-core-pass-2/x86_64-unknown-linux-gnu/32/libgcc
/c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-cc-gcc-core-pass-2/./gcc/xgcc \
            -B/c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-cc-gcc-core-pass-2/./gcc/ \
            -B/c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/buildtools/x86_64-unknown-linux-gnu/bin/ \
            -B/c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/buildtools/x86_64-unknown-linux-gnu/lib/ \
            -isystem /c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/buildtools/x86_64-unknown-linux-gnu/include \
            -isystem /c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/buildtools/x86_64-unknown-linux-gnu/sys-include \
            -O2  -DIN_GCC -DCROSS_DIRECTORY_STRUCTURE \
            -W -Wall -Wno-narrowing -Wwrite-strings -Wcast-qual -Wstrict-prototypes -Wmissing-prototypes -Wold-style-definition  -isystem ./include \
            -fpic -mlong-double-80 -g -DIN_LIBGCC2 -fbuilding-libgcc -fno-stack-protector  -shared -nodefaultlibs \
            -Wl,--soname=libgcc_s.so.1 -Wl,--version-script=libgcc.map -o 32/libgcc_s.so.1.tmp \
            -g -Os -m32 -B./ \
            _muldi3_s.o _negdi2_s.o _lshrdi3_s.o _ashldi3_s.o _ashrdi3_s.o _cmpdi2_s.o _ucmpdi2_s.o _clear_cache_s.o _trampoline_s.o __main_s.o _absvsi2_s.o _absvdi2_s.o _addvsi3_s.o _addvdi3_s.o \
            _subvsi3_s.o _subvdi3_s.o _mulvsi3_s.o _mulvdi3_s.o _negvsi2_s.o _negvdi2_s.o _ctors_s.o _ffssi2_s.o _ffsdi2_s.o _clz_s.o _clzsi2_s.o _clzdi2_s.o _ctzsi2_s.o _ctzdi2_s.o _popcount_tab_s.o \
            _popcountsi2_s.o _popcountdi2_s.o _paritysi2_s.o _paritydi2_s.o _powisf2_s.o _powidf2_s.o _powixf2_s.o _powitf2_s.o _mulsc3_s.o _muldc3_s.o _mulxc3_s.o _multc3_s.o _divsc3_s.o _divdc3_s.o \
            _divxc3_s.o _divtc3_s.o _bswapsi2_s.o _bswapdi2_s.o _clrsbsi2_s.o _clrsbdi2_s.o _fixunssfsi_s.o _fixunsdfsi_s.o _fixunsxfsi_s.o _fixsfdi_s.o _fixdfdi_s.o _fixxfdi_s.o _fixunssfdi_s.o \
            _fixunsdfdi_s.o _fixunsxfdi_s.o _floatdisf_s.o _floatdidf_s.o _floatdixf_s.o _floatundisf_s.o _floatundidf_s.o _floatundixf_s.o _divdi3_s.o _moddi3_s.o _udivdi3_s.o _umoddi3_s.o \
            _udiv_w_sdiv_s.o _udivmoddi4_s.o cpuinfo_s.o tf-signs_s.o sfp-exceptions_s.o addtf3_s.o divtf3_s.o eqtf2_s.o getf2_s.o letf2_s.o multf3_s.o negtf2_s.o subtf3_s.o unordtf2_s.o fixtfsi_s.o \
            fixunstfsi_s.o floatsitf_s.o floatunsitf_s.o fixtfdi_s.o fixunstfdi_s.o floatditf_s.o floatunditf_s.o extendsftf2_s.o extenddftf2_s.o extendxftf2_s.o trunctfsf2_s.o trunctfdf2_s.o \
            trunctfxf2_s.o enable-execute-stack_s.o unwind-dw2_s.o unwind-dw2-fde-dip_s.o unwind-sjlj_s.o unwind-c_s.o emutls_s.o libgcc.a -lc \
&& rm -f 32/libgcc_s.so \
&& if [ -f 32/libgcc_s.so.1 ]; then mv -f 32/libgcc_s.so.1 32/libgcc_s.so.1.backup; else true; fi \
&& mv 32/libgcc_s.so.1.tmp 32/libgcc_s.so.1 \
&& cp -p libgcc_s.so.1 32/libgcc_s.so

/c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-cc-gcc-core-pass-2/./gcc/xgcc \
            -B/c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-cc-gcc-core-pass-2/./gcc/ \
            -B/c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/buildtools/x86_64-unknown-linux-gnu/bin/ \
            -B/c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/buildtools/x86_64-unknown-linux-gnu/lib/ \
            -isystem /c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/buildtools/x86_64-unknown-linux-gnu/include \
            -isystem /c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/buildtools/x86_64-unknown-linux-gnu/sys-include \
            -O2  -DIN_GCC -DCROSS_DIRECTORY_STRUCTURE \
            -W -Wall -Wno-narrowing -Wwrite-strings -Wcast-qual -Wstrict-prototypes -Wmissing-prototypes -Wold-style-definition  -isystem ./include \
            -fpic -mlong-double-80 -g -DIN_LIBGCC2 -fbuilding-libgcc -fno-stack-protector  -shared -nodefaultlibs \
            -Wl,--soname=libgcc_s.so.1 -Wl,--version-script=libgcc.map -o 32/libgcc_s.so.1.tmp \
            -g -Os -m32 -B./ \
            _muldi3_s.o _negdi2_s.o _lshrdi3_s.o _ashldi3_s.o _ashrdi3_s.o _cmpdi2_s.o _ucmpdi2_s.o _clear_cache_s.o _trampoline_s.o __main_s.o _absvsi2_s.o _absvdi2_s.o _addvsi3_s.o _addvdi3_s.o \
            _subvsi3_s.o _subvdi3_s.o _mulvsi3_s.o _mulvdi3_s.o _negvsi2_s.o _negvdi2_s.o _ctors_s.o _ffssi2_s.o _ffsdi2_s.o _clz_s.o _clzsi2_s.o _clzdi2_s.o _ctzsi2_s.o _ctzdi2_s.o _popcount_tab_s.o \
            _popcountsi2_s.o _popcountdi2_s.o _paritysi2_s.o _paritydi2_s.o _powisf2_s.o _powidf2_s.o _powixf2_s.o _powitf2_s.o _mulsc3_s.o _muldc3_s.o _mulxc3_s.o _multc3_s.o _divsc3_s.o _divdc3_s.o \
            _divxc3_s.o _divtc3_s.o _bswapsi2_s.o _bswapdi2_s.o _clrsbsi2_s.o _clrsbdi2_s.o _fixunssfsi_s.o _fixunsdfsi_s.o _fixunsxfsi_s.o _fixsfdi_s.o _fixdfdi_s.o _fixxfdi_s.o _fixunssfdi_s.o \
            _fixunsdfdi_s.o _fixunsxfdi_s.o _floatdisf_s.o _floatdidf_s.o _floatdixf_s.o _floatundisf_s.o _floatundidf_s.o _floatundixf_s.o _divdi3_s.o _moddi3_s.o _udivdi3_s.o _umoddi3_s.o \
            _udiv_w_sdiv_s.o _udivmoddi4_s.o cpuinfo_s.o tf-signs_s.o sfp-exceptions_s.o addtf3_s.o divtf3_s.o eqtf2_s.o getf2_s.o letf2_s.o multf3_s.o negtf2_s.o subtf3_s.o unordtf2_s.o fixtfsi_s.o \
            fixunstfsi_s.o floatsitf_s.o floatunsitf_s.o fixtfdi_s.o fixunstfdi_s.o floatditf_s.o floatunditf_s.o extendsftf2_s.o extenddftf2_s.o extendxftf2_s.o trunctfsf2_s.o trunctfdf2_s.o \
            trunctfxf2_s.o enable-execute-stack_s.o unwind-dw2_s.o unwind-dw2-fde-dip_s.o unwind-sjlj_s.o unwind-c_s.o emutls_s.o libgcc.a -lc \
&& rm -f 32/libgcc_s.so \
&& if [ -f 32/libgcc_s.so.1 ]; then mv -f 32/libgcc_s.so.1 32/libgcc_s.so.1.backup; else true; fi \
&& mv 32/libgcc_s.so.1.tmp 32/libgcc_s.so.1 \
&& ln -s libgcc_s.so.1 32/libgcc_s.so


On Linux this creates a link (32/libgcc_s.so) pointing to literally "libgcc_s.so.1". This does not work for us.


.. segfault: /c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-cc-gcc-core-pass-1

PATH=/home/ray/ctng-firefox-builds/x-l-none-4_8_2-x86_64-213be3fb/bin:/c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/buildtools/bin:/c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/tools/bin:/home/ray/ctng-firefox-builds/mingw64-213be3fb/bin:$PATH \
    /usr/bin/make "DESTDIR=" "RPATH_ENVVAR=PATH" "TARGET_SUBDIR=x86_64-unknown-linux-gnu" "bindir=/c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/buildtools/bin" "datadir=/c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/buildtools/share" "exec_prefix=/c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/buildtools" "includedir=/c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/buildtools/include" "datarootdir=/c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/buildtools/share" "docdir=/c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/buildtools/share/doc/" "infodir=/c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/buildtools/share/info" "pdfdir=/c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/buildtools/share/doc/" "htmldir=/c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/buildtools/share/doc/" "libdir=/c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/buildtools/lib" "libexecdir=/c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/buildtools/libexec" "lispdir=" "localstatedir=/c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/buildtools/var" "mandir=/c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/buildtools/share/man" "oldincludedir=/usr/include" "prefix=/c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/buildtools" "sbindir=/c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/buildtools/sbin" "sharedstatedir=/c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/buildtools/com" "sysconfdir=/c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/buildtools/etc" "tooldir=/c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/buildtools/x86_64-unknown-linux-gnu" "build_tooldir=/c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/buildtools/x86_64-unknown-linux-gnu" "target_alias=x86_64-unknown-linux-gnu" "AWK=gawk" "BISON=bison" "CC_FOR_BUILD=x86_64-build_w64-mingw32-gcc" "CFLAGS_FOR_BUILD=-m64" "CXX_FOR_BUILD=x86_64-build_w64-mingw32-g++" "EXPECT=expect" "FLEX=flex" "INSTALL=/usr/bin/install -c" "INSTALL_DATA=/usr/bin/install -c -m 644" "INSTALL_PROGRAM=/usr/bin/install -c" "INSTALL_SCRIPT=/usr/bin/install -c" "LDFLAGS_FOR_BUILD=-m64 -lstdc++ -lm" "LEX=flex" "M4=m4" "MAKE=/usr/bin/make" "RUNTEST=runtest" "RUNTESTFLAGS=" "SED=/c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/tools/bin/sed" "SHELL=/usr/bin/bash" "YACC=bison -y" "`echo 'ADAFLAGS=' | sed -e s'/[^=][^=]*=$/XFOO=/'`" "ADA_CFLAGS=" "AR_FLAGS=rc" "`echo 'BOOT_ADAFLAGS=-gnatpg' | sed -e s'/[^=][^=]*=$/XFOO=/'`" "BOOT_CFLAGS=-g -O2 -D__USE_MINGW_ACCESS -Wno-pedantic-ms-format" "BOOT_LDFLAGS= -Wl,--stack,12582912" "CFLAGS=-O2 -g -pipe -m64 -D__USE_MINGW_ANSI_STDIO=1 -D__USE_MINGW_ACCESS" "CXXFLAGS=-O2 -g -pipe -m64 -D__USE_MINGW_ANSI_STDIO=1" "LDFLAGS=-m64 -lstdc++ -lm -Wl,--stack,12582912" "LIBCFLAGS=-O2 -g -pipe -m64 -D__USE_MINGW_ANSI_STDIO=1 -D__USE_MINGW_ACCESS" "LIBCXXFLAGS=-O2 -g -pipe -m64 -D__USE_MINGW_ANSI_STDIO=1 -fno-implicit-templates" "STAGE1_CHECKING=--enable-checking=yes,types" "STAGE1_LANGUAGES=c,lto" "GNATBIND=x86_64-build_w64-mingw32-gnatbind" "GNATMAKE=x86_64-build_w64-mingw32-gnatmake" "AR_FOR_TARGET=/c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/buildtools/x86_64-unknown-linux-gnu/bin/ar" "AS_FOR_TARGET=/c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/buildtools/x86_64-unknown-linux-gnu/bin/as" "CC_FOR_TARGET= $r/./gcc/xgcc -B$r/./gcc/" "CFLAGS_FOR_TARGET=-g -Os" "CPPFLAGS_FOR_TARGET=" "CXXFLAGS_FOR_TARGET=-g -Os" "DLLTOOL_FOR_TARGET=x86_64-unknown-linux-gnu-dlltool" "FLAGS_FOR_TARGET=-B/c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/buildtools/x86_64-unknown-linux-gnu/bin/ -B/c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/buildtools/x86_64-unknown-linux-gnu/lib/ -isystem /c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/buildtools/x86_64-unknown-linux-gnu/include -isystem /c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/buildtools/x86_64-unknown-linux-gnu/sys-include" "GCJ_FOR_TARGET= x86_64-unknown-linux-gnu-gcj" "GFORTRAN_FOR_TARGET= x86_64-unknown-linux-gnu-gfortran" "GOC_FOR_TARGET= x86_64-unknown-linux-gnu-gccgo" "GOCFLAGS_FOR_TARGET=-O2 -g" "LD_FOR_TARGET=/c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/buildtools/x86_64-unknown-linux-gnu/bin/ld" "LIPO_FOR_TARGET=x86_64-unknown-linux-gnu-lipo" "LDFLAGS_FOR_TARGET=" "LIBCFLAGS_FOR_TARGET=-g -Os" "LIBCXXFLAGS_FOR_TARGET=-g -Os -fno-implicit-templates" "NM_FOR_TARGET=x86_64-unknown-linux-gnu-nm" "OBJDUMP_FOR_TARGET=x86_64-unknown-linux-gnu-objdump" "RANLIB_FOR_TARGET=/c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/buildtools/x86_64-unknown-linux-gnu/bin/ranlib" "READELF_FOR_TARGET=x86_64-unknown-linux-gnu-readelf" "STRIP_FOR_TARGET=/c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/buildtools/x86_64-unknown-linux-gnu/bin/strip" "WINDRES_FOR_TARGET=x86_64-unknown-linux-gnu-windres" "WINDMC_FOR_TARGET=x86_64-unknown-linux-gnu-windmc" "BUILD_CONFIG=" "`echo 'LANGUAGES=' | sed -e s'/[^=][^=]*=$/XFOO=/'`" "LEAN=false" "STAGE1_CFLAGS=-g" "STAGE1_CXXFLAGS=-O2 -g -pipe -m64 -D__USE_MINGW_ANSI_STDIO=1" "STAGE1_TFLAGS=" "STAGE2_CFLAGS=-g -O2 -D__USE_MINGW_ACCESS -Wno-pedantic-ms-format" "STAGE2_CXXFLAGS=-O2 -g -pipe -m64 -D__USE_MINGW_ANSI_STDIO=1" "STAGE2_TFLAGS=" "STAGE3_CFLAGS=-g -O2 -D__USE_MINGW_ACCESS -Wno-pedantic-ms-format" "STAGE3_CXXFLAGS=-O2 -g -pipe -m64 -D__USE_MINGW_ANSI_STDIO=1" "STAGE3_TFLAGS=" "STAGE4_CFLAGS=-g -O2 -D__USE_MINGW_ACCESS -Wno-pedantic-ms-format" "STAGE4_CXXFLAGS=-O2 -g -pipe -m64 -D__USE_MINGW_ANSI_STDIO=1" "STAGE4_TFLAGS=" "STAGEprofile_CFLAGS=-g -O2 -D__USE_MINGW_ACCESS -Wno-pedantic-ms-format -fprofile-generate" "STAGEprofile_CXXFLAGS=-O2 -g -pipe -m64 -D__USE_MINGW_ANSI_STDIO=1" "STAGEprofile_TFLAGS=" "STAGEfeedback_CFLAGS=-g -O2 -D__USE_MINGW_ACCESS -Wno-pedantic-ms-format -fprofile-use" "STAGEfeedback_CXXFLAGS=-O2 -g -pipe -m64 -D__USE_MINGW_ANSI_STDIO=1" "STAGEfeedback_TFLAGS=" "CXX_FOR_TARGET= x86_64-unknown-linux-gnu-c++" "TFLAGS=" "CONFIG_SHELL=/usr/bin/bash" "MAKEINFO=makeinfo --split-size=5000000" 'AR=x86_64-build_w64-mingw32-ar' 'AS=x86_64-build_w64-mingw32-as' 'CC=x86_64-build_w64-mingw32-gcc' 'CXX=x86_64-build_w64-mingw32-g++' 'DLLTOOL=x86_64-build_w64-mingw32-dlltool' 'GCJ=' 'GFORTRAN=' 'GOC=' 'LD=c:/msys64/home/ray/ctng-firefox-builds/mingw64-213be3fb/bin/../lib/gcc/x86_64-w64-mingw32/4.8.2/../../../../x86_64-w64-mingw32/bin/ld.exe' 'LIPO=lipo' 'NM=x86_64-build_w64-mingw32-nm' 'OBJDUMP=x86_64-build_w64-mingw32-objdump' 'RANLIB=x86_64-build_w64-mingw32-ranlib' 'READELF=readelf' 'STRIP=x86_64-build_w64-mingw32-strip' 'WINDRES=x86_64-build_w64-mingw32-windres' 'WINDMC=windmc' LDFLAGS="${LDFLAGS}" HOST_LIBS="${HOST_LIBS}" "GCC_FOR_TARGET= $r/./gcc/xgcc -B$r/./gcc/" "`echo 'STMP_FIXPROTO=' | sed -e s'/[^=][^=]*=$/XFOO=/'`" "`echo 'LIMITS_H_TEST=' | sed -e s'/[^=][^=]*=$/XFOO=/'`" all



.. Ok, seems /usr/bin/locale has been overwritten by a build somewhere along the line!

$ file /usr/bin/locale
/usr/bin/locale: ELF 64-bit LSB executable, x86-64, version 1 (SYSV), dynamically linked (uses shared libs), for GNU/Linux 3.12.0, not stripped

ray@l702x ~
$ ls -l /usr/bin/locale
-rw-r--r-- 1 ray None 46653 Jan 25 03:07 /usr/bin/locale
ok make install of eglibc-2.18, it may be because I did it from the command line without a DESTDIR though, need to check!

Seems MSYS2 does not have locale program:
$ pacman -Qo /usr/bin/locale
error: No package owns /usr/bin/locale

(localedef also is from eglibc-2.18!)



pushd /c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final_32
make -j1 -l BUILD_CPPFLAGS=-I/c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/buildtools/include/ BUILD_LDFLAGS="-L/c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/buildtools/lib -Wl,-Bstatic -lintl -Wl,-Bdynamic" install_root=/home/ray/ctng-firefox-builds/x-l-none-4_8_2-x86_64-213be3fb/x86_64-unknown-linux-gnu/sysroot install

cd build-libc-final_32
make -j1 -l BUILD_CPPFLAGS=-I/c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/buildtools/include/ BUILD_LDFLAGS="-L/c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/buildtools/lib -Wl,-Bstatic -lintl -Wl,-Bdynamic" install_root=/home/ray/ctng-firefox-builds/x-l-none-4_8_2-x86_64-213be3fb/x86_64-unknown-linux-gnu/sysroot install


MAKEFLAGS were rw MAKECMDGOALS ware subdir_install

Makefile:32: SHELLFLAGS are

pushd /c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/src/eglibc-2_18/nis

Makefile:34: BUILD_LDFLAGS is -L/c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/buildtools/lib -Wl,-Bstatic -lintl -Wl,-Bdynamic
Makefile:35: install_root is /home/ray/ctng-firefox-builds/x-l-none-4_8_2-x86_64-213be3fb/x86_64-unknown-linux-gnu/sysroot
Makefile:36: subdir is nis
Makefile:37: OUTPUT_OPTION is -o
Makefile:38: MAKEFILE_LIST is  Makefile
Makefile:39: MAKE_HOST is x86_64-pc-msys
Makefile:40: sysdep_dir is sysdeps
Makefile:41: objdir is /c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final_32
Makefile:42: SYSTEMROOT is C:\Windows
Makefile:43: MFLAGS is -rw
Makefile:44: MAKEFILES is


pushd /c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/src/eglibc-2_18
make -j1 -l install_root=/home/ray/ctng-firefox-builds/x-l-none-4_8_2-x86_64-213be3fb/x86_64-unknown-linux-gnu/sysroot subdir=nis \
  sysdep_dir=sysdeps \
  objdir=/c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final_32 \
  BUILD_LDFLAGS="-L/c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/buildtools/lib -Wl,-Bstatic -lintl -Wl,-Bdynamic" \
  -C nis ..=../ subdir_install 
popd

.. --always-make will force reconfigure and the lot.

pushd /c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/src/eglibc-2_18
PATH=/home/ray/ctng-firefox-builds/x-l-none-4_8_2-x86_64-213be3fb/bin:/c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/buildtools/bin:/c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/tools/bin:/home/ray/ctng-firefox-builds/mingw64-213be3fb/bin:$PATH \
build_alias=x86_64-build_w64-mingw32 \
host_alias=i686-unknown-linux-gnu \
CC="x86_64-unknown-linux-gnu-gcc -m32" \
CFLAGS="-U_FORTIFY_SOURCE -O2" \
make -j1 -l install_root=/home/ray/ctng-firefox-builds/x-l-none-4_8_2-x86_64-213be3fb/x86_64-unknown-linux-gnu/sysroot subdir=nis \
  sysdep_dir=sysdeps \
  objdir=/c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final_32 \
  BUILD_LDFLAGS="-L/c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/buildtools/lib -Wl,-Bstatic -lintl -Wl,-Bdynamic" \
  -C nis ..=../ subdir_install
popd


// To get flags passed above, I edited:

C:\ctng-build-x-l-none-4_8_2-x86_64-213be3fb\.build\src\eglibc-2_18\nis\Makefile

$(warning MAKEFLAGS were $(MAKEFLAGS) MAKECMDGOALS ware $(MAKECMDGOALS))
$(warning MAKEFLAGS were $(MAKEFLAGS) MAKECMDGOALS ware $(MAKECMDGOALS))
$(warning MAKEFLAGS were $(MAKEFLAGS) MAKECMDGOALS ware $(MAKECMDGOALS))
$(warning MAKEFLAGS were $(MAKEFLAGS) MAKECMDGOALS ware $(MAKECMDGOALS))
$(warning MAKEFLAGS were $(MAKEFLAGS) MAKECMDGOALS ware $(MAKECMDGOALS))
$(warning MAKEFLAGS were $(MAKEFLAGS) MAKECMDGOALS ware $(MAKECMDGOALS))
$(warning MAKEFLAGS were $(MAKEFLAGS) MAKECMDGOALS ware $(MAKECMDGOALS))
$(warning MAKEFLAGS were $(MAKEFLAGS) MAKECMDGOALS ware $(MAKECMDGOALS))
$(warning MAKEFLAGS were $(MAKEFLAGS) MAKECMDGOALS ware $(MAKECMDGOALS))
$(warning MAKEFLAGS were $(MAKEFLAGS) MAKECMDGOALS ware $(MAKECMDGOALS))
$(warning VARIABLES are $(.VARIABLES))
$(warning SHELLFLAGS are $(SHELLFLAGS))
$(warning CURDIR is $(CURDIR))
$(warning BUILD_LDFLAGS is $(BUILD_LDFLAGS))
$(warning install_root is $(install_root))
$(warning subdir is $(subdir))
$(warning OUTPUT_OPTION is $(OUTPUT_OPTION))
$(warning MAKEFILE_LIST is $(MAKEFILE_LIST))
$(warning MAKE_HOST is $(MAKE_HOST))
$(warning sysdep_dir is $(sysdep_dir))
$(warning objdir is $(objdir))
$(warning SYSTEMROOT is $(SYSTEMROOT))
$(warning MFLAGS is $(MFLAGS))
$(warning MAKEFILES is $(MAKEFILES))

.. putting those prints in cause the coredump to go away ..

.. so the full repro for this gnumake bug is:

rm -rf ~/ctng-firefox-builds/x-l-none-4_8_2-x86_64-213be3fb/x86_64-unknown-linux-gnu/sysroot/lib/{libnss_compat.so.2,libnss_compat-2.18.so,libnss_nisplus.so.2}
pushd /c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/src/eglibc-2_18
make -j1 -l install_root=/home/ray/ctng-firefox-builds/x-l-none-4_8_2-x86_64-213be3fb/x86_64-unknown-linux-gnu/sysroot subdir=nis \
  sysdep_dir=sysdeps \
  objdir=/c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final_32 \
  BUILD_LDFLAGS="-L/c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/buildtools/lib -Wl,-Bstatic -lintl -Wl,-Bdynamic" \
  -C nis ..=../ subdir_install 
popd

# Debugging this in QtCreator..
set directories C:/repo-MSYS2/make/src/make;C:/repo-MSYS2/msys2-runtime/src/msys2-runtime/winsup/cygwin/lib
b cygwin_exception::open_stackdumpfile


# Crash in gnumake is at:
"bt\n"
"#0  cygwin_exception::open_stackdumpfile (this=this@entry=0x227360) at ../../../../msys2-runtime/winsup/cygwin/exceptions.cc:127\n"
"#1  0x000000018006ee40 in cygwin_exception::dumpstack (this=0x227360) at ../../../../msys2-runtime/winsup/cygwin/exceptions.cc:351\n"
"#2  0x000000018006f547 in signal_exit (sig=134, si=<optimized out>) at ../../../../msys2-runtime/winsup/cygwin/exceptions.cc:1236\n"
"#3  0x0000000180070aba in _cygtls::call_signal_handler (this=0x22ce00) at ../../../../msys2-runtime/winsup/cygwin/exceptions.cc:1454\n"
"#4  0x0000000180119e28 in sig_send (p=0x0, p@entry=0x180000000, si=..., tls=tls@entry=0x0) at ../../../../msys2-runtime/winsup/cygwin/sigproc.cc:687\n"
"#5  0x0000000180116f1e in _pinfo::kill (this=0x180000000, si=...) at ../../../../msys2-runtime/winsup/cygwin/signal.cc:248\n"
"#6  0x00000001801173eb in kill0 (pid=9120, si=...) at ../../../../msys2-runtime/winsup/cygwin/signal.cc:299\n"
"#7  0x00000001801175bc in kill (sig=6, pid=<optimized out>) at ../../../../msys2-runtime/winsup/cygwin/signal.cc:308\n"
"#8  raise (sig=sig@entry=6) at ../../../../msys2-runtime/winsup/cygwin/signal.cc:284\n"
"#9  0x000000018011787f in abort () at ../../../../msys2-runtime/winsup/cygwin/signal.cc:371\n"
"#10 0x00000001801473b5 in internal_realloc (m=0x1802b6e40 <_gm_>, bytes=1248, oldmem=0x600101ab0) at ../../../../msys2-runtime/winsup/cygwin/malloc.cc:3779\n"
"#11 dlrealloc (oldmem=0x600101ab0, bytes=1248) at ../../../../msys2-runtime/winsup/cygwin/malloc.cc:4292\n"
"#12 0x00000001800bf7bf in realloc (p=0x600101ab0, size=1248) at ../../../../msys2-runtime/winsup/cygwin/malloc_wrapper.cc:77\n"
"#13 0x000000018011300b in _sigfe () from C:\\msys64\\bin\\msys-2.0.dll\n"
"#14 0x0000000600502720 in ?? ()\n"
"#15 0x00000001800bf6f3 in free (p=0x1a4) at ../../../../msys2-runtime/winsup/cygwin/malloc_wrapper.cc:47\n"
"#16 0x000000018011300b in _sigfe () from C:\\msys64\\bin\\msys-2.0.dll\n"
"#17 0x0000000000000184 in ?? ()\n"
"#18 0x00000001004125e8 in message (prefix=prefix@entry=0, len=420, fmt=fmt@entry=0x100427506 <__FUNCTION__.5266+2604> \"%s\") at output.c:615\n"
"#19 0x000000010040de7c in start_job_command (child=child@entry=0x600502370) at job.c:1311\n"
"#20 0x000000010040e71e in reap_children (block=block@entry=1, err=err@entry=0) at job.c:915\n"
"#21 0x000000010040f001 in new_job (file=<optimized out>) at job.c:2050\n"
"#22 0x0000000100419ae8 in remake_file (file=0x6002eb9c0) at remake.c:1211\n"
"#23 update_file_1 (depth=<optimized out>, file=0x6002eb9c0) at remake.c:822\n"
"#24 update_file (file=file@entry=0x6002eb9c0, depth=depth@entry=10) at remake.c:316\n"
"#25 0x00000001004188b5 in check_dep (file=0x6002eb9c0, depth=10, depth@entry=9, this_mtime=this_mtime@entry=1493220499318761419, must_make_ptr=must_make_ptr@entry=0x22841c) at remake.c:1011\n"
"#26 0x000000010041908b in update_file_1 (depth=<optimized out>, file=0x6002eb8a0) at remake.c:565\n"
"#27 update_file (file=file@entry=0x6002eb8a0, depth=depth@entry=8) at remake.c:316\n"
"#28 0x00000001004188b5 in check_dep (file=0x6002eb8a0, depth=8, depth@entry=7, this_mtime=this_mtime@entry=1, must_make_ptr=must_make_ptr@entry=0x2285fc) at remake.c:1011\n"
"#29 0x000000010041908b in update_file_1 (depth=<optimized out>, file=0x6002ebc00) at remake.c:565\n"
"#30 update_file (file=file@entry=0x6002ebc00, depth=depth@entry=6) at remake.c:316\n"
"#31 0x00000001004188b5 in check_dep (file=0x6002ebc00, depth=6, depth@entry=5, this_mtime=this_mtime@entry=1, must_make_ptr=must_make_ptr@entry=0x2287dc) at remake.c:1011\n"
"#32 0x000000010041908b in update_file_1 (depth=<optimized out>, file=0x6004c6b50) at remake.c:565\n"
"#33 update_file (file=file@entry=0x6004c6b50, depth=depth@entry=4) at remake.c:316\n"
"#34 0x00000001004188b5 in check_dep (file=0x6004c6b50, depth=4, depth@entry=3, this_mtime=this_mtime@entry=1, must_make_ptr=must_make_ptr@entry=0x2289bc) at remake.c:1011\n"
"#35 0x000000010041908b in update_file_1 (depth=<optimized out>, file=0x6000bb090) at remake.c:565\n"
"#36 update_file (file=file@entry=0x6000bb090, depth=depth@entry=2) at remake.c:316\n"
"#37 0x00000001004188b5 in check_dep (file=0x6000bb090, depth=2, depth@entry=1, this_mtime=this_mtime@entry=1, must_make_ptr=must_make_ptr@entry=0x228b9c) at remake.c:1011\n"
"#38 0x000000010041908b in update_file_1 (depth=<optimized out>, file=0x60006b9a0) at remake.c:565\n"
"#39 update_file (file=file@entry=0x60006b9a0, depth=<optimized out>) at remake.c:316\n"
"#40 0x0000000100419ff3 in update_goal_chain (goals=<optimized out>) at remake.c:155\n"
"#41 0x00000001004232b1 in main (argc=<optimized out>, argv=<optimized out>, envp=<optimized out>) at main.c:2498\n"


"print args\n"
"$1 = (va_list) 0x6004fe68d \"ln -s `../scripts/rellns-sh -p /home/ray/ctng-firefox-builds/x-l-none-4_8_2-x86_64-213be3fb/x86_64-unknown-linux-gnu/sysroot/lib/libnss_nisplus-2.18.so /home/ray/ctng-firefox-builds/x-l-none-4_8_2-x86_64-213be3fb/x86_64-unknown-linux-gnu/sysroot/lib/libnss_nisplus.so.2` /home/ray/ctng-firefox-builds/x-l-none-4_8_2-x86_64-213be3fb/x86_64-unknown-linux-gnu/sysroot/lib/libnss_nisplus.so.2\""
"print fmt\n"
"$2 = 0x100427506 <__FUNCTION__.5266+2604> \"%s\""

  len += strlen (fmt) + strlen (program) + INTSTR_LENGTH + 4 + 1 + 1;
  p = get_buffer (len);

Initial len passed in was 0


// From C:\repo-MSYS2\msys2-runtime\src\msys2-runtime\winsup\cygwin\malloc.cc

DEBUG                    default: NOT defined
  The DEBUG setting is mainly intended for people trying to modify
  this code or diagnose problems when porting to new platforms.
  However, it may also be able to better isolate user errors than just
  using runtime checks.  The assertions in the check routines spell
  out in more detail the assumptions and invariants underlying the
  algorithms.  The checking is fairly extensive, and will slow down
  execution noticeably. Calling malloc_stats or mallinfo with DEBUG
  set will attempt to check every non-mmapped allocated and free chunk
  in the course of computing the summaries.

.. sounds like I want to define DEBUG and call mallinfo everywhere?

Also -DABORT_ON_ASSERT_FAILURE=0


We go wrong when:
p == 0x600101ab0
p->head = 419
p->prev_foot = 48
assert(next_pinuse(p));
#define next_pinuse(p)  ((next_chunk(p)->head) & PINUSE_BIT)
assert( ((next_chunk(p)->head) & PINUSE_BIT) );
#define next_chunk(p) ((mchunkptr)( ((char*)(p)) + ((p)->head & ~INUSE_BITS)))
assert( ((((mchunkptr)( ((char*)(p)) + ((p)->head & ~INUSE_BITS)))->head) & PINUSE_BIT) );
Address thus: (((mchunkptr)( ((char*)(p)) + ((p)->head & ~INUSE_BITS)))->head)
INUSE_BITS = 3

(mchunkptr)(0x600101ab0+418)

so the invalid mchunkptr is 0x6000101c52
 ->head = 10511120055306027008?

mchunkptr = malloc_chunk*

struct malloc_chunk {
  size_t               prev_foot;  /* Size of previous chunk (if free).  */
  size_t               head;       /* Size and inuse bits. */
  struct malloc_chunk* fd;         /* double links -- used only if free. */
  struct malloc_chunk* bk;
};

bad address is  0x600101c5A

print *(size_t*)0x600101c5A == 10511120055306027008

To get the size of fmtbuf->buffer it is:
((mchunkptr)(fmtbuf->buffer-0x10))->head&~3

To get the next_mchunkptr it is then:
(mchunkptr)(fmtbuf->buffer-0x10+(((mchunkptr)(fmtbuf->buffer-0x10))->head&~3))

# eglibc-2.18 (64 bit)
[EXTRA]    Configuring C library
[DEBUG]    Using gcc for target     : '/c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/buildtools/bin/x86_64-unknown-linux-gnu-gcc'
[DEBUG]    Configuring with addons  : 'nptl'
[DEBUG]    Extra config args passed : '--enable-obsolete-rpc --enable-kernel=3.12.0 --with-__thread --with-tls --enable-shared --enable-add-ons=nptl --with-pkgversion=crosstool-NG hg+unknown-20140124.200549'
[DEBUG]    Extra CC args passed     : ' -U_FORTIFY_SOURCE          -O2 '
[DEBUG]    Extra flags (multilib)   : ''
[DEBUG]    Multilib os dir          : '/home/ray/ctng-firefox-builds/x-l-none-4_8_2-x86_64-213be3fb/x86_64-unknown-linux-gnu/sysroot/usr/lib/../lib64'
[DEBUG]    Configuring with --host  : 'x86_64-unknown-linux-gnu'
[DEBUG]    Configuring with --libdir: '/usr/lib/../lib64'
[DEBUG]    ==> Executing: 'BUILD_CC=x86_64-build_unknown-linux-gnu-gcc' 'CFLAGS= -U_FORTIFY_SOURCE          -O2 ' 'CC=x86_64-unknown-linux-gnu-gcc    ' 'AR=x86_64-unknown-linux-gnu-ar' 'RANLIB=x86_64-unknown-linux-gnu-ranlib' '/usr/bin/bash' '/c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/src/eglibc-2_18/configure' '--prefix=/usr' '--build=x86_64-build_unknown-linux-gnu' '--host=x86_64-unknown-linux-gnu' '--cache-file=/c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final/config.cache' '--without-cvs' '--disable-profile' '--without-gd' '--with-headers=/home/ray/ctng-firefox-builds/x-l-none-4_8_2-x86_64-213be3fb/x86_64-unknown-linux-gnu/sysroot/usr/include' '--libdir=/usr/lib/../lib64' '--enable-obsolete-rpc' '--enable-kernel=3.12.0' '--with-__thread' '--with-tls' '--enable-shared' '--enable-add-ons=nptl' '--with-pkgversion=crosstool-NG hg+unknown-20140124.200549'
[CFG  ]    configure: loading cache /c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final/config.cache
[CFG  ]    checking build system type... x86_64-build_unknown-linux-gnu
[CFG  ]    checking host system type... x86_64-unknown-linux-gnu

# eglibc-2.18 (32 bit)
[EXTRA]      Configuring C library
[DEBUG]      Using gcc for target     : '/c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/buildtools/bin/x86_64-unknown-linux-gnu-gcc'
[DEBUG]      Configuring with addons  : 'nptl'
[DEBUG]      Extra config args passed : '--enable-obsolete-rpc --enable-kernel=3.12.0 --with-__thread --with-tls --enable-shared --enable-add-ons=nptl --with-pkgversion=crosstool-NG hg+unknown-20140124.200549'
[DEBUG]      Extra CC args passed     : ' -U_FORTIFY_SOURCE          -O2 '
[DEBUG]      Extra flags (multilib)   : ' -m32'
[DEBUG]      Multilib os dir          : '/home/ray/ctng-firefox-builds/x-l-none-4_8_2-x86_64-213be3fb/x86_64-unknown-linux-gnu/sysroot/usr/lib/../lib'
[DEBUG]      Configuring with --host  : 'i686-unknown-linux-gnu'
[DEBUG]      Configuring with --libdir: '/usr/lib/../lib'
[DEBUG]      ==> Executing: 'BUILD_CC=x86_64-build_unknown-linux-gnu-gcc' 'CFLAGS= -U_FORTIFY_SOURCE          -O2 ' 'CC=x86_64-unknown-linux-gnu-gcc     -m32' 'AR=x86_64-unknown-linux-gnu-ar' 'RANLIB=x86_64-unknown-linux-gnu-ranlib' '/usr/bin/bash' '/c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/src/eglibc-2_18/configure' '--prefix=/usr' '--build=x86_64-build_unknown-linux-gnu' '--host=i686-unknown-linux-gnu' '--cache-file=/c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-startfiles_32/config.cache' '--without-cvs' '--disable-profile' '--without-gd' '--with-headers=/home/ray/ctng-firefox-builds/x-l-none-4_8_2-x86_64-213be3fb/x86_64-unknown-linux-gnu/sysroot/usr/include' '--libdir=/usr/lib/../lib' '--enable-obsolete-rpc' '--enable-kernel=3.12.0' '--with-__thread' '--with-tls' '--enable-shared' '--enable-add-ons=nptl' '--with-pkgversion=crosstool-NG hg+unknown-20140124.200549'
[CFG  ]      configure: loading cache /c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-startfiles_32/config.cache


# glibc-2.15 (64 bit):
[INFO ]  Installing C library
[DEBUG]    Entering '/c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final'
[EXTRA]    Configuring C library
[DEBUG]    Using gcc for target     : '/c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/buildtools/bin/x86_64-unknown-linux-gnu-gcc'
[DEBUG]    Configuring with addons  : 'nptl'
[DEBUG]    Extra config args passed : '--disable-debug --disable-sanity-checks --enable-kernel=3.12.0 --with-__thread --with-tls --enable-shared --enable-add-ons=nptl --with-pkgversion=crosstool-NG hg+unknown-20140126.225515'
[DEBUG]    Extra CC args passed     : ' -U_FORTIFY_SOURCE          -O2 '
[DEBUG]    Extra flags (multilib)   : ''
[DEBUG]    Multilib os dir          : '/home/ray/ctng-firefox-builds/x-l-none-4_8_2-x86_64-213be3fb/x86_64-unknown-linux-gnu/sysroot/usr/lib/../lib64'
[DEBUG]    Configuring with --host  : 'x86_64-unknown-linux-gnu'
[DEBUG]    Configuring with --libdir: '/usr/lib/../lib64'
[DEBUG]    ==> Executing: 'BUILD_CC=x86_64-build_unknown-linux-gnu-gcc' 'CFLAGS= -U_FORTIFY_SOURCE          -O2 ' 'CC=x86_64-unknown-linux-gnu-gcc    ' 'AR=x86_64-unknown-linux-gnu-ar' 'RANLIB=x86_64-unknown-linux-gnu-ranlib' '/usr/bin/bash' '/c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/src/glibc-2.15/configure' '--prefix=/usr' '--build=x86_64-build_unknown-linux-gnu' '--host=x86_64-unknown-linux-gnu' '--cache-file=/c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final/config.cache' '--without-cvs' '--disable-profile' '--without-gd' '--with-headers=/home/ray/ctng-firefox-builds/x-l-none-4_8_2-x86_64-213be3fb/x86_64-unknown-linux-gnu/sysroot/usr/include' '--libdir=/usr/lib/../lib64' '--disable-debug' '--disable-sanity-checks' '--enable-kernel=3.12.0' '--with-__thread' '--with-tls' '--enable-shared' '--enable-add-ons=nptl' '--with-pkgversion=crosstool-NG hg+unknown-20140126.225515'
[CFG  ]    configure: loading cache /c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final/config.cache

# glibc-2.15 (32 bit):
[INFO ]    Building for multilib subdir='32'
[DEBUG]      Entering '/c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final_32'
[EXTRA]      Configuring C library
[DEBUG]      Using gcc for target     : '/c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/buildtools/bin/x86_64-unknown-linux-gnu-gcc'
[DEBUG]      Configuring with addons  : 'nptl'
[DEBUG]      Extra config args passed : '--disable-debug --disable-sanity-checks --enable-kernel=3.12.0 --with-__thread --with-tls --enable-shared --enable-add-ons=nptl --with-pkgversion=crosstool-NG hg+unknown-20140126.225515'
[DEBUG]      Extra CC args passed     : ' -U_FORTIFY_SOURCE          -O2 '
[DEBUG]      Extra flags (multilib)   : ' -m32'
[DEBUG]      Multilib os dir          : '/home/ray/ctng-firefox-builds/x-l-none-4_8_2-x86_64-213be3fb/x86_64-unknown-linux-gnu/sysroot/usr/lib/../lib'
[DEBUG]      Configuring with --host  : 'i686-unknown-linux-gnu'
[DEBUG]      Configuring with --libdir: '/usr/lib/../lib'
[DEBUG]      ==> Executing: 'BUILD_CC=x86_64-build_unknown-linux-gnu-gcc' 'CFLAGS= -U_FORTIFY_SOURCE          -O2 ' 'CC=x86_64-unknown-linux-gnu-gcc     -m32' 'AR=x86_64-unknown-linux-gnu-ar' 'RANLIB=x86_64-unknown-linux-gnu-ranlib' '/usr/bin/bash' '/c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/src/glibc-2.15/configure' '--prefix=/usr' '--build=x86_64-build_unknown-linux-gnu' '--host=i686-unknown-linux-gnu' '--cache-file=/c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final_32/config.cache' '--without-cvs' '--disable-profile' '--without-gd' '--with-headers=/home/ray/ctng-firefox-builds/x-l-none-4_8_2-x86_64-213be3fb/x86_64-unknown-linux-gnu/sysroot/usr/include' '--libdir=/usr/lib/../lib' '--disable-debug' '--disable-sanity-checks' '--enable-kernel=3.12.0' '--with-__thread' '--with-tls' '--enable-shared' '--enable-add-ons=nptl' '--with-pkgversion=crosstool-NG hg+unknown-20140126.225515'
[CFG  ]      configure: loading cache /c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final_32/config.cache

# And now for my next problem:
[ALL  ]    libtool: compile:  /c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-cc-gcc-final/./gcc/xgcc -shared-libgcc -B/c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-cc-gcc-final/./gcc -nostdinc++ -L/c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-cc-gcc-final/x86_64-unknown-linux-gnu/libstdc++-v3/src -L/c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-cc-gcc-final/x86_64-unknown-linux-gnu/libstdc++-v3/src/.libs -B/home/ray/ctng-firefox-builds/x-l-none-4_8_2-x86_64-213be3fb/x86_64-unknown-linux-gnu/bin/ -B/home/ray/ctng-firefox-builds/x-l-none-4_8_2-x86_64-213be3fb/x86_64-unknown-linux-gnu/lib/ -isystem /home/ray/ctng-firefox-builds/x-l-none-4_8_2-x86_64-213be3fb/x86_64-unknown-linux-gnu/include -isystem /home/ray/ctng-firefox-builds/x-l-none-4_8_2-x86_64-213be3fb/x86_64-unknown-linux-gnu/sys-include -I/c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-cc-gcc-final/x86_64-unknown-linux-gnu/libstdc++-v3/include/x86_64-unknown-linux-gnu -I/c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-cc-gcc-final/x86_64-unknown-linux-gnu/libstdc++-v3/include -I/c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/src/gcc-4.8.2/libstdc++-v3/libsupc++ -fPIC -DPIC -Wall -Wextra -Wwrite-strings -Wcast-qual -Wabi -fdiagnostics-show-location=once -ffunction-sections -fdata-sections -frandom-seed=compatibility-atomic-c++0x.lo -g -Os -std=gnu++11 -c ../../../../../../src/gcc-4.8.2/libstdc++-v3/src/c++11/compatibility-atomic-c++0x.cc  -fPIC -DPIC -D_GLIBCXX_SHARED -o .libs/compatibility-atomic-c++0x.o
[ALL  ]    ../../../../../../src/gcc-4.8.2/libstdc++-v3/src/c++11/compatibility-atomic-c++0x.cc: In function 'std::__atomic_flag_base* std::__atomic_flag_for_address(const volatile void*)':
[ERROR]    ../../../../../../src/gcc-4.8.2/libstdc++-v3/src/c++11/compatibility-atomic-c++0x.cc:122:52: error: cast from 'const volatile void*' to 'uintptr_t {aka unsigned int}' loses precision [-fpermissive]
[ALL  ]         uintptr_t __u = reinterpret_cast<uintptr_t>(__z);
[ALL  ]                                                        ^
[ALL  ]    Makefile:843: recipe for target 'compatibility-atomic-c++0x.lo' failed
[ERROR]    make[6]: *** [compatibility-atomic-c++0x.lo] Error 1
[ALL  ]    make[6]: Leaving directory '/c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-cc-gcc-final/x86_64-unknown-linux-gnu/libstdc++-v3/src'
# ^ while that looks like a basic problem, investigation turned up what looks like a libc headers mismatch, testing for sizeof long gives different results on eglibc 2.18 vs glibc 2.15. Test code is (~/Dropbox/ctng-firefox-builds/conftest.cpp)
#include <stdint.h>
	template<typename, typename> struct same { enum { value = -1 }; };
	template<typename Tp> struct same<Tp, Tp> { enum { value = 1 }; };
	int array[same<int64_t, long>::value];
int
main ()
{

  ;
  return 0;
}


# eglibc-2.18:
# From C:\ctng-build-x-l-none-4_8_2-x86_64-213be3fb-eglibc-2.18-good\.build\x86_64-unknown-linux-gnu\build\build-cc-gcc-final\x86_64-unknown-linux-gnu\libstdc++-v3\config.log
configure:18110: checking for int64_t as long
configure:18130:  /c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-cc-gcc-final/./gcc/xgcc -shared-libgcc -B/c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-cc-gcc-final/./gcc -nostdinc++ -L/c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-cc-gcc-final/x86_64-unknown-linux-gnu/libstdc++-v3/src -L/c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-cc-gcc-final/x86_64-unknown-linux-gnu/libstdc++-v3/src/.libs -B/home/ray/ctng-firefox-builds/x-l-none-4_8_2-x86_64-213be3fb/x86_64-unknown-linux-gnu/bin/ -B/home/ray/ctng-firefox-builds/x-l-none-4_8_2-x86_64-213be3fb/x86_64-unknown-linux-gnu/lib/ -isystem /home/ray/ctng-firefox-builds/x-l-none-4_8_2-x86_64-213be3fb/x86_64-unknown-linux-gnu/include -isystem /home/ray/ctng-firefox-builds/x-l-none-4_8_2-x86_64-213be3fb/x86_64-unknown-linux-gnu/sys-include    -c -g -Os  conftest.cpp >&5
configure:18130: $? = 0
configure:18144: result: yes
configure:18148: checking for int64_t as long long
configure:18168:  /c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-cc-gcc-final/./gcc/xgcc -shared-libgcc -B/c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-cc-gcc-final/./gcc -nostdinc++ -L/c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-cc-gcc-final/x86_64-unknown-linux-gnu/libstdc++-v3/src -L/c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-cc-gcc-final/x86_64-unknown-linux-gnu/libstdc++-v3/src/.libs -B/home/ray/ctng-firefox-builds/x-l-none-4_8_2-x86_64-213be3fb/x86_64-unknown-linux-gnu/bin/ -B/home/ray/ctng-firefox-builds/x-l-none-4_8_2-x86_64-213be3fb/x86_64-unknown-linux-gnu/lib/ -isystem /home/ray/ctng-firefox-builds/x-l-none-4_8_2-x86_64-213be3fb/x86_64-unknown-linux-gnu/include -isystem /home/ray/ctng-firefox-builds/x-l-none-4_8_2-x86_64-213be3fb/x86_64-unknown-linux-gnu/sys-include    -c -g -Os  conftest.cpp >&5
conftest.cpp:71:43: error: size of array 'array' is negative
  int array[same<int64_t, long long>::value];
                                           ^
configure:18168: $? = 1

# glibc-2.15:
# From C:\ctng-build-x-l-none-4_8_2-x86_64-213be3fb\.build\x86_64-unknown-linux-gnu\build\build-cc-gcc-final\x86_64-unknown-linux-gnu\libstdc++-v3\config.log
configure:18110: checking for int64_t as long
configure:18130:  /c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-cc-gcc-final/./gcc/xgcc -shared-libgcc -B/c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-cc-gcc-final/./gcc -nostdinc++ -L/c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-cc-gcc-final/x86_64-unknown-linux-gnu/libstdc++-v3/src -L/c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-cc-gcc-final/x86_64-unknown-linux-gnu/libstdc++-v3/src/.libs -B/home/ray/ctng-firefox-builds/x-l-none-4_8_2-x86_64-213be3fb/x86_64-unknown-linux-gnu/bin/ -B/home/ray/ctng-firefox-builds/x-l-none-4_8_2-x86_64-213be3fb/x86_64-unknown-linux-gnu/lib/ -isystem /home/ray/ctng-firefox-builds/x-l-none-4_8_2-x86_64-213be3fb/x86_64-unknown-linux-gnu/include -isystem /home/ray/ctng-firefox-builds/x-l-none-4_8_2-x86_64-213be3fb/x86_64-unknown-linux-gnu/sys-include    -c -g -Os  conftest.cpp >&5
conftest.cpp:70:38: error: size of array 'array' is negative
  int array[same<int64_t, long>::value];
                                      ^
configure:18130: $? = 1

.. code is in ~/Dropbox/ctng-firefox-builds/conftest.cpp

EGLIBC_BUILD=/c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb-eglibc-2.18-good
EGLIBC_INST=~/ctng-firefox-builds/x-l-none-4_8_2-x86_64-213be3fb-eglibc-2.18-good
PATH=$EGLIBC_BUILD/bin:$EGLIBC_BUILD/.build/x86_64-unknown-linux-gnu/buildtools/bin:$EGLIBC_BUILD/.build/tools/bin:/home/ray/ctng-firefox-builds/mingw64-213be3fb/bin:$PATH \
 $EGLIBC_BUILD/.build/x86_64-unknown-linux-gnu/build/build-cc-gcc-final/./gcc/xgcc -shared-libgcc -B$EGLIBC_BUILD/.build/x86_64-unknown-linux-gnu/build/build-cc-gcc-final/./gcc -nostdinc++ -L$EGLIBC_BUILD/.build/x86_64-unknown-linux-gnu/build/build-cc-gcc-final/x86_64-unknown-linux-gnu/libstdc++-v3/src -L$EGLIBC_BUILD/.build/x86_64-unknown-linux-gnu/build/build-cc-gcc-final/x86_64-unknown-linux-gnu/libstdc++-v3/src/.libs -B$EGLIBC_INST/x86_64-unknown-linux-gnu/bin/ -B$EGLIBC_INST/x86_64-unknown-linux-gnu/lib/ -isystem $EGLIBC_INST/x86_64-unknown-linux-gnu/include -isystem $EGLIBC_INST/x86_64-unknown-linux-gnu/sys-include    -c -g -Os  ~/Dropbox/ctng-firefox-builds/conftest.cpp

GLIBC_BUILD=/c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb
GLIBC_INST=~/ctng-firefox-builds/x-l-none-4_8_2-x86_64-213be3fb
PATH=$GLIBC_BUILD/bin:$GLIBC_BUILD/.build/x86_64-unknown-linux-gnu/buildtools/bin:$GLIBC_BUILD/.build/tools/bin:/home/ray/ctng-firefox-builds/mingw64-213be3fb/bin:$PATH \
 $GLIBC_BUILD/.build/x86_64-unknown-linux-gnu/build/build-cc-gcc-final/./gcc/xgcc -shared-libgcc -B$GLIBC_BUILD/.build/x86_64-unknown-linux-gnu/build/build-cc-gcc-final/./gcc -nostdinc++ -L$GLIBC_BUILD/.build/x86_64-unknown-linux-gnu/build/build-cc-gcc-final/x86_64-unknown-linux-gnu/libstdc++-v3/src -L$GLIBC_BUILD/.build/x86_64-unknown-linux-gnu/build/build-cc-gcc-final/x86_64-unknown-linux-gnu/libstdc++-v3/src/.libs -B$GLIBC_INST/x86_64-unknown-linux-gnu/bin/ -B$GLIBC_INST/x86_64-unknown-linux-gnu/lib/ -isystem $GLIBC_INST/x86_64-unknown-linux-gnu/include -isystem $GLIBC_INST/x86_64-unknown-linux-gnu/sys-include    -c -g -Os  ~/Dropbox/ctng-firefox-builds/conftest.cpp

echo "" | PATH=$GLIBC_BUILD/bin:$GLIBC_BUILD/.build/x86_64-unknown-linux-gnu/buildtools/bin:$GLIBC_BUILD/.build/tools/bin:/home/ray/ctng-firefox-builds/mingw64-213be3fb/bin:$GLIBC_BUILD/.build/x86_64-unknown-linux-gnu/build/build-cc-gcc-final/./gcc:$PATH $GLIBC_BUILD/.build/x86_64-unknown-linux-gnu/build/build-cc-gcc-final/./gcc/xgcc -E -dM - | grep 64

... turns out the problem is glibc-2.15:
C:\msys64\home\ray\ctng-firefox-builds\x-l-none-4_8_2-x86_64-213be3fb.215\x86_64-unknown-linux-gnu\sysroot\usr\include\bits\wordsize.h
#define __WORDSIZE	32

vs eglibc-2.15:
C:\msys64\home\ray\ctng-firefox-builds\x-l-none-4_8_2-x86_64-213be3fb\x86_64-unknown-linux-gnu\sysroot\usr\include\bits\wordsize.h
#if defined __x86_64__ && !defined __ILP32__
# define __WORDSIZE	64
#else
# define __WORDSIZE	32
#endif
#ifdef __x86_64__
# define __WORDSIZE_TIME64_COMPAT32	1
/* Both x86-64 and x32 use the 64-bit system call interface.  */
# define __SYSCALL_WORDSIZE		64
#endif

.. hmm!?!

File missing at glibc-2.15 on Windows compared to Linux:
[STATE]      ./x86_64-unknown-linux-gnu/include/include/linux/netfilter/xt_connmark.h
[STATE]      ./x86_64-unknown-linux-gnu/include/include/linux/netfilter/xt_dscp.h
[STATE]      ./x86_64-unknown-linux-gnu/include/include/linux/netfilter/xt_mark.h
[STATE]      ./x86_64-unknown-linux-gnu/include/include/linux/netfilter/xt_rateest.h
[STATE]      ./x86_64-unknown-linux-gnu/include/include/linux/netfilter/xt_tcpmss.h
[STATE]      ./x86_64-unknown-linux-gnu/include/include/linux/netfilter_ipv4/ipt_ecn.h
[STATE]      ./x86_64-unknown-linux-gnu/include/include/linux/netfilter_ipv4/ipt_ttl.h
[STATE]      ./x86_64-unknown-linux-gnu/include/include/linux/netfilter_ipv6/ip6t_hl.h

[STATE]      ./x86_64-unknown-linux-gnu/sysroot/usr/include/linux/netfilter/xt_connmark.h
[STATE]      ./x86_64-unknown-linux-gnu/sysroot/usr/include/linux/netfilter/xt_dscp.h
[STATE]      ./x86_64-unknown-linux-gnu/sysroot/usr/include/linux/netfilter/xt_mark.h
[STATE]      ./x86_64-unknown-linux-gnu/sysroot/usr/include/linux/netfilter/xt_rateest.h
[STATE]      ./x86_64-unknown-linux-gnu/sysroot/usr/include/linux/netfilter/xt_tcpmss.h
[STATE]      ./x86_64-unknown-linux-gnu/sysroot/usr/include/linux/netfilter_ipv4/ipt_ecn.h
[STATE]      ./x86_64-unknown-linux-gnu/sysroot/usr/include/linux/netfilter_ipv4/ipt_ttl.h
[STATE]      ./x86_64-unknown-linux-gnu/sysroot/usr/include/linux/netfilter_ipv6/ip6t_hl.h


.. On Linux, it does not run the make in /c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/src/glibc-2.15/manual :
/usr/bin/make  subdir=manual -C manual ..=../ subdir_install

.. So this does not happen :
[ALL  ]      touch /c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final_32/manual/stubs

[ALL  ]      (sed '/^@/d' include/stubs-prologue.h; LC_ALL=C sort /c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final_32/csu/stubs /c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final_32/iconv/stubs /c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final_32/locale/stubs /c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final_32/localedata/stubs /c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final_32/iconvdata/stubs /c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final_32/assert/stubs /c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final_32/ctype/stubs /c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final_32/intl/stubs /c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final_32/catgets/stubs /c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final_32/math/stubs /c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final_32/setjmp/stubs /c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final_32/signal/stubs /c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final_32/stdlib/stubs /c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final_32/stdio-common/stubs /c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final_32/libio/stubs /c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final_32/dlfcn/stubs /c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final_32/malloc/stubs /c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final_32/string/stubs /c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final_32/wcsmbs/stubs /c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final_32/timezone/stubs /c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final_32/time/stubs /c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final_32/dirent/stubs /c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final_32/grp/stubs /c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final_32/pwd/stubs /c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final_32/posix/stubs /c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final_32/io/stubs /c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final_32/termios/stubs /c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final_32/resource/stubs /c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final_32/misc/stubs /c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final_32/socket/stubs /c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final_32/sysvipc/stubs /c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final_32/gmon/stubs /c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final_32/gnulib/stubs /c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final_32/wctype/stubs /c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-
final_32/manual/stubs /c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final_32/shadow/stubs /c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final_32/gshadow/stubs /c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final_32/po/stubs /c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final_32/argp/stubs /c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final_32/crypt/stubs /c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final_32/nptl/stubs /c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final_32/resolv/stubs /c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final_32/nss/stubs /c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final_32/rt/stubs /c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final_32/conform/stubs /c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final_32/debug/stubs /c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final_32/nptl_db/stubs /c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final_32/inet/stubs /c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final_32/hesiod/stubs /c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final_32/sunrpc/stubs /c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final_32/nis/stubs /c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final_32/nscd/stubs /c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final_32/streams/stubs /c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final_32/login/stubs /c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final_32/elf/stubs) > /c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final_32/stubs.h
[ALL  ]      if test -r /home/ray/ctng-firefox-builds/x-l-none-4_8_2-x86_64-213be3fb/x86_64-unknown-linux-gnu/sysroot/usr/include/gnu/stubs-32.h && cmp -s /c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final_32/stubs.h /home/ray/ctng-firefox-builds/x-l-none-4_8_2-x86_64-213be3fb/x86_64-unknown-linux-gnu/sysroot/usr/include/gnu/stubs-32.h; then echo 'stubs.h unchanged'; else /usr/bin/install -c -m 644 /c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final_32/stubs.h /home/ray/ctng-firefox-builds/x-l-none-4_8_2-x86_64-213be3fb/x86_64-unknown-linux-gnu/sysroot/usr/include/gnu/stubs-32.h; fi
[ALL  ]      rm -f /c/ctng-build-x-l-none-4_8_2-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final_32/stubs.h

# final GCC on eglibc 2.15 has warnings, -Werror trips up.
pushd /c/ctng-build-x-l-glibc_V_2.15-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-cc-gcc-final/x86_64-unknown-linux-gnu/libatomic
/c/ctng-build-x-l-glibc_V_2.15-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-cc-gcc-final/./gcc/xgcc -B/c/ctng-build-x-l-glibc_V_2.15-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-cc-gcc-final/./gcc/ -B/home/ray/ctng-firefox-builds/x-l-glibc_V_2.15-x86_64-213be3fb/x86_64-unknown-linux-gnu/bin/ -B/home/ray/ctng-firefox-builds/x-l-glibc_V_2.15-x86_64-213be3fb/x86_64-unknown-linux-gnu/lib/ -isystem /home/ray/ctng-firefox-builds/x-l-glibc_V_2.15-x86_64-213be3fb/x86_64-unknown-linux-gnu/include -isystem /home/ray/ctng-firefox-builds/x-l-glibc_V_2.15-x86_64-213be3fb/x86_64-unknown-linux-gnu/sys-include    -DHAVE_CONFIG_H -I../../../../../src/gcc-4.8.2/libatomic/config/x86 -I../../../../../src/gcc-4.8.2/libatomic/config/posix -I../../../../../src/gcc-4.8.2/libatomic -I.    -Wall -Werror  -pthread -g -Os -MT gexch.lo -MD -MP -MF .deps/gexch.Tpo -c -o gexch.lo ../../../../../src/gcc-4.8.2/libatomic/gexch.c --save-temps
popd

pushd /c/ctng-build-x-l-glibc_V_2.17-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-cc-gcc-final/x86_64-unknown-linux-gnu/libatomic
/c/ctng-build-x-l-glibc_V_2.17-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-cc-gcc-final/./gcc/xgcc -B/c/ctng-build-x-l-glibc_V_2.17-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-cc-gcc-final/./gcc/ -B/home/ray/ctng-firefox-builds/x-l-glibc_V_2.17-x86_64-213be3fb/x86_64-unknown-linux-gnu/bin/ -B/home/ray/ctng-firefox-builds/x-l-glibc_V_2.17-x86_64-213be3fb/x86_64-unknown-linux-gnu/lib/ -isystem /home/ray/ctng-firefox-builds/x-l-glibc_V_2.17-x86_64-213be3fb/x86_64-unknown-linux-gnu/include -isystem /home/ray/ctng-firefox-builds/x-l-glibc_V_2.17-x86_64-213be3fb/x86_64-unknown-linux-gnu/sys-include    -DHAVE_CONFIG_H -I../../../../../src/gcc-4.8.2/libatomic/config/x86 -I../../../../../src/gcc-4.8.2/libatomic/config/posix -I../../../../../src/gcc-4.8.2/libatomic -I.    -Wall -Werror  -pthread -g -Os -MT gexch.lo -MD -MP -MF .deps/gexch.Tpo -c -o gexch.lo ../../../../../src/gcc-4.8.2/libatomic/gexch.c --save-temps
popd

want to see a byteswap-16.h ...




export PATH=/home/ray/ctng-firefox-builds/x-l-glibc_V_2.15-x86_64-213be3fb/bin:/c/ctng-build-x-l-glibc_V_2.15-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/buildtools/bin:/c/ctng-build-x-l-glibc_V_2.15-x86_64-213be3fb/.build/tools/bin:/home/ray/ctng-firefox-builds/mingw64-213be3fb/bin:$PATH
build_glibc()
{
VERSION=$1; shift
PTRSIZE=$1; shift
BUILDDIR=$1; shift
[ -d glibc-${VERSION} ] && rm -rf glibc-${VERSION}
if [ -f ~/src/glibc-${VERSION}.tar.xz ]; then
  tar -xf ~/src/glibc-${VERSION}.tar.xz
elif [ -f ~/src/glibc-${VERSION}.tar.bz2 ]; then
  tar -xf ~/src/glibc-${VERSION}.tar.bz2
fi
SRCDIR=$PWD/glibc-${VERSION}
pushd $SRCDIR
PATCHES=$(find ~/ctng-firefox-builds/crosstool-ng/patches/glibc/${VERSION} -name "*.patch" | sort)
for PATCH in $PATCHES; do
  echo Patching with $PATCH
  patch -Np1 -i $PATCH
done
popd
export BUILD_CC=x86_64-build_unknown-linux-gnu-gcc
export CFLAGS=" -U_FORTIFY_SOURCE          -O2 "
export AR=x86_64-unknown-linux-gnu-ar
export RANLIB=x86_64-unknown-linux-gnu-ranlib
if [ "$PTRSIZE" = "32" ]; then
  LIBDIR=/usr/lib/../lib
  export CC="x86_64-unknown-linux-gnu-gcc -m32"
  HARCHPREFIX=i686
else
  LIBDIR=/usr/lib/../lib64
  export CC="x86_64-unknown-linux-gnu-gcc"
  HARCHPREFIX=x86_64
fi
[ -d $BUILDDIR ] && rm -rf $BUILDDIR
mkdir $BUILDDIR
pushd $BUILDDIR
$SRCDIR/configure --prefix=/usr --build=x86_64-build_w64-mingw32 --host=$HARCHPREFIX-unknown-linux-gnu \
   --without-cvs --disable-profile --without-gd \
   --with-headers=/home/ray/ctng-firefox-builds/x-l-glibc_V_2.15-x86_64-213be3fb/x86_64-unknown-linux-gnu/sysroot/usr/include \
   --libdir=$LIBDIR \
   --disable-debug \
   --disable-sanity-checks \
   --enable-kernel=3.12.0 \
   --with-__thread --with-tls --enable-shared --enable-add-ons=nptl > configure.log 2>&1

make -j1 > make.log 2>&1
make install DESTDIR=$PWD/../install_${VERSION}_${PTRSIZE} > install.log 2>&1
popd
}

pushd /tmp
build_glibc 2.15 32 $PWD/build_2.15_32
build_glibc 2.16.0 32 $PWD/build_2.16.0_32
bcompare /tmp/build_2.15_32 /tmp/build_2.16.0_32 &
popd

# Another gnumake crash?!?

[ALL  ]      x86_64-unknown-linux-gnu-gcc     svc_udp.c -c -std=gnu99 -fgnu89-inline -O2 -U_FORTIFY_SOURCE -Wall -Winline -Wwrite-strings -fmerge-all-constants -Wstrict-prototypes   -fPIC      -I../include -I/c/ctng-build-x-l-glibc_V_2.15-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final/sunrpc -I/c/ctng-build-x-l-glibc_V_2.15-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final -I../sysdeps/x86_64/elf -I../nptl/sysdeps/unix/sysv/linux/x86_64 -I../sysdeps/unix/sysv/linux/x86_64 -I../sysdeps/unix/sysv/linux/wordsize-64 -I../nptl/sysdeps/unix/sysv/linux -I../nptl/sysdeps/pthread -I../sysdeps/pthread -I../sysdeps/unix/sysv/linux -I../sysdeps/gnu -I../sysdeps/unix/common -I../sysdeps/unix/mman -I../sysdeps/unix/inet -I../nptl/sysdeps/unix/sysv -I../sysdeps/unix/sysv -I../sysdeps/unix/x86_64 -I../nptl/sysdeps/unix -I../sysdeps/unix -I../sysdeps/posix -I../sysdeps/x86_64/fpu/multiarch -I../sysdeps/x86_64/fpu -I../sysdeps/x86_64/multiarch -I../nptl/sysdeps/x86_64 -I../sysdeps/x86_64 -I../sysdeps/wordsize-64 -I../sysdeps/ieee754/ldbl-96 -I../sysdeps/ieee754/dbl-64/wordsize-64 -I../sysdeps/ieee754/dbl-64 -I../sysdeps/ieee754/flt-32 -I../sysdeps/ieee754 -I../sysdeps/generic/elf -I../sysdeps/generic -I../nptl  -I.. -I../libio -I. -nostdinc -isystem C:/ctng-build-x-l-glibc_V_2.15-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/buildtools/lib/gcc/x86_64-unknown-linux-gnu/4.8.2/include -isystem C:/ctng-build-x-l-glibc_V_2.15-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/buildtools/lib/gcc/x86_64-unknown-linux-gnu/4.8.2/include-fixed -isystem /home/ukrdonnell/ctng-firefox-builds/x-l-glibc_V_2.15-x86_64-213be3fb/x86_64-unknown-linux-gnu/sysroot/usr/include -D_LIBC_REENTRANT -include ../include/libc-symbols.h  -DPIC -DSHARED     -D_RPC_THREAD_SAFE_ -o /c/ctng-build-x-l-glibc_V_2.15-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final/sunrpc/svc_udp.os -MD -MP -MF /c/ctng-build-x-l-glibc_V_2.15-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final/sunrpc/svc_udp.os.dt -MT /c/ctng-build-x-l-glibc_V_2.15-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final/sunrpc/svc_udp.os
[ALL  ]      x86_64-unknown-linux-gnu-gcc     xcrypt.c -c -std=gnu99 -fgnu89-inline -O2 -U_FORTIFY_SOURCE -Wall -Winline -Wwrite-strings -fmerge-all-constants -Wstrict-prototypes   -fPIC      -I../include -I/c/ctng-build-x-l-glibc_V_2.15-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final/sunrpc -I/c/ctng-build-x-l-glibc_V_2.15-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final -I../sysdeps/x86_64/elf -I../nptl/sysdeps/unix/sysv/linux/x86_64 -I../sysdeps/unix/sysv/linux/x86_64 -I../sysdeps/unix/sysv/linux/wordsize-64 -I../nptl/sysdeps/unix/sysv/linux -I../nptl/sysdeps/pthread -I../sysdeps/pthread -I../sysdeps/unix/sysv/linux -I../sysdeps/gnu -I../sysdeps/unix/common -I../sysdeps/unix/mman -I../sysdeps/unix/inet -I../nptl/sysdeps/unix/sysv -I../sysdeps/unix/sysv -I../sysdeps/unix/x86_64 -I../nptl/sysdeps/unix -I../sysdeps/unix -I../sysdeps/posix -I../sysdeps/x86_64/fpu/multiarch -I../sysdeps/x86_64/fpu -I../sysdeps/x86_64/multiarch -I../nptl/sysdeps/x86_64 -I../sysdeps/x86_64 -I../sysdeps/wordsize-64 -I../sysdeps/ieee754/ldbl-96 -I../sysdeps/ieee754/dbl-64/wordsize-64 -I../sysdeps/ieee754/dbl-64 -I../sysdeps/ieee754/flt-32 -I../sysdeps/ieee754 -I../sysdeps/generic/elf -I../sysdeps/generic -I../nptl  -I.. -I../libio -I. -nostdinc -isystem C:/ctng-build-x-l-glibc_V_2.15-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/buildtools/lib/gcc/x86_64-unknown-linux-gnu/4.8.2/include -isystem C:/ctng-build-x-l-glibc_V_2.15-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/buildtools/lib/gcc/x86_64-unknown-linux-gnu/4.8.2/include-fixed -isystem /home/ukrdonnell/ctng-firefox-builds/x-l-glibc_V_2.15-x86_64-213be3fb/x86_64-unknown-linux-gnu/sysroot/usr/include -D_LIBC_REENTRANT -include ../include/libc-symbols.h  -DPIC -DSHARED     -D_RPC_THREAD_SAFE_ -o /c/ctng-build-x-l-glibc_V_2.15-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final/sunrpc/xcrypt.os -MD -MP -MF /c/ctng-build-x-l-glibc_V_2.15-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final/sunrpc/xcrypt.os.dt -MT /c/ctng-build-x-l-glibc_V_2.15-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final/sunrpc/xcrypt.os
[ALL  ]      x86_64-unknown-linux-gnu-gcc     xdr_array.c -c -std=gnu99 -fgnu89-inline -O2 -U_FORTIFY_SOURCE -Wall -Winline -Wwrite-strings -fmerge-all-constants -Wstrict-prototypes   -fPIC      -I../include -I/c/ctng-build-x-l-glibc_V_2.15-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final/sunrpc -I/c/ctng-build-x-l-glibc_V_2.15-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final -I../sysdeps/x86_64/elf -I../nptl/sysdeps/unix/sysv/linux/x86_64 -I../sysdeps/unix/sysv/linux/x86_64 -I../sysdeps/unix/sysv/linux/wordsize-64 -I../nptl/sysdeps/unix/sysv/linux -I../nptl/sysdeps/pthread -I../sysdeps/pthread -I../sysdeps/unix/sysv/linux -I../sysdeps/gnu -I../sysdeps/unix/common -I../sysdeps/unix/mman -I../sysdeps/unix/inet -I../nptl/sysdeps/unix/sysv -I../sysdeps/unix/sysv -I../sysdeps/unix/x86_64 -I../nptl/sysdeps/unix -I../sysdeps/unix -I../sysdeps/posix -I../sysdeps/x86_64/fpu/multiarch -I../sysdeps/x86_64/fpu -I../sysdeps/x86_64/multiarch -I../nptl/sysdeps/x86_64 -I../sysdeps/x86_64 -I../sysdeps/wordsize-64 -I../sysdeps/ieee754/ldbl-96 -I../sysdeps/ieee754/dbl-64/wordsize-64 -I../sysdeps/ieee754/dbl-64 -I../sysdeps/ieee754/flt-32 -I../sysdeps/ieee754 -I../sysdeps/generic/elf -I../sysdeps/generic -I../nptl  -I.. -I../libio -I. -nostdinc -isystem C:/ctng-build-x-l-glibc_V_2.15-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/buildtools/lib/gcc/x86_64-unknown-linux-gnu/4.8.2/include -isystem C:/ctng-build-x-l-glibc_V_2.15-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/buildtools/lib/gcc/x86_64-unknown-linux-gnu/4.8.2/include-fixed -isystem /home/ukrdonnell/ctng-firefox-builds/x-l-glibc_V_2.15-x86_64-213be3fb/x86_64-unknown-linux-gnu/sysroot/usr/include -D_LIBC_REENTRANT -include ../include/libc-symbols.h  -DPIC -DSHARED     -D_RPC_THREAD_SAFE_ -o /c/ctng-build-x-l-glibc_V_2.15-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final/sunrpc/xdr_array.os -MD -MP -MF /c/ctng-build-x-l-glibc_V_2.15-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final/sunrpc/xdr_array.os.dt -MT /c/ctng-build-x-l-glibc_V_2.15-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final/sunrpc/xdr_array.os
[ALL  ]      x86_64-unknown-linux-gnu-gcc     xdr.c -c -std=gnu99 -fgnu89-inline -O2 -U_FORTIFY_SOURCE -Wall -Winline -Wwrite-strings -fmerge-all-constants -Wstrict-prototypes   -fPIC      -I../include -I/c/ctng-build-x-l-glibc_V_2.15-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final/sunrpc -I/c/ctng-build-x-l-glibc_V_2.15-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final -I../sysdeps/x86_64/elf -I../nptl/sysdeps/unix/sysv/linux/x86_64 -I../sysdeps/unix/sysv/linux/x86_64 -I../sysdeps/unix/sysv/linux/wordsize-64 -I../nptl/sysdeps/unix/sysv/linux -I../nptl/sysdeps/pthread -I../sysdeps/pthread -I../sysdeps/unix/sysv/linux -I../sysdeps/gnu -I../sysdeps/unix/common -I../sysdeps/unix/mman -I../sysdeps/unix/inet -I../nptl/sysdeps/unix/sysv -I../sysdeps/unix/sysv -I../sysdeps/unix/x86_64 -I../nptl/sysdeps/unix -I../sysdeps/unix -I../sysdeps/posix -I../sysdeps/x86_64/fpu/multiarch -I../sysdeps/x86_64/fpu -I../sysdeps/x86_64/multiarch -I../nptl/sysdeps/x86_64 -I../sysdeps/x86_64 -I../sysdeps/wordsize-64 -I../sysdeps/ieee754/ldbl-96 -I../sysdeps/ieee754/dbl-64/wordsize-64 -I../sysdeps/ieee754/dbl-64 -I../sysdeps/ieee754/flt-32 -I../sysdeps/ieee754 -I../sysdeps/generic/elf -I../sysdeps/generic -I../nptl  -I.. -I../libio -I. -nostdinc -isystem C:/ctng-build-x-l-glibc_V_2.15-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/buildtools/lib/gcc/x86_64-unknown-linux-gnu/4.8.2/include -isystem C:/ctng-build-x-l-glibc_V_2.15-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/buildtools/lib/gcc/x86_64-unknown-linux-gnu/4.8.2/include-fixed -isystem /home/ukrdonnell/ctng-firefox-builds/x-l-glibc_V_2.15-x86_64-213be3fb/x86_64-unknown-linux-gnu/sysroot/usr/include -D_LIBC_REENTRANT -include ../include/libc-symbols.h  -DPIC -DSHARED     -D_RPC_THREAD_SAFE_ -o /c/ctng-build-x-l-glibc_V_2.15-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final/sunrpc/xdr.os -MD -MP -MF /c/ctng-build-x-l-glibc_V_2.15-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final/sunrpc/xdr.os.dt -MT /c/ctng-build-x-l-glibc_V_2.15-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final/sunrpc/xdr.os
[ALL  ]      x86_64-unknown-linux-gnu-gcc     xdr_intXX_t.c -c -std=gnu99 -fgnu89-inline -O2 -U_FORTIFY_SOURCE -Wall -Winline -Wwrite-strings -fmerge-all-constants -Wstrict-prototypes   -fPIC      -I../include -I/c/ctng-build-x-l-glibc_V_2.15-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final/sunrpc -I/c/ctng-build-x-l-glibc_V_2.15-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final -I../sysdeps/x86_64/elf -I../nptl/sysdeps/unix/sysv/linux/x86_64 -I../sysdeps/unix/sysv/linux/x86_64 -I../sysdeps/unix/sysv/linux/wordsize-64 -I../nptl/sysdeps/unix/sysv/linux -I../nptl/sysdeps/pthread -I../sysdeps/pthread -I../sysdeps/unix/sysv/linux -I../sysdeps/gnu -I../sysdeps/unix/common -I../sysdeps/unix/mman -I../sysdeps/unix/inet -I../nptl/sysdeps/unix/sysv -I../sysdeps/unix/sysv -I../sysdeps/unix/x86_64 -I../nptl/sysdeps/unix -I../sysdeps/unix -I../sysdeps/posix -I../sysdeps/x86_64/fpu/multiarch -I../sysdeps/x86_64/fpu -I../sysdeps/x86_64/multiarch -I../nptl/sysdeps/x86_64 -I../sysdeps/x86_64 -I../sysdeps/wordsize-64 -I../sysdeps/ieee754/ldbl-96 -I../sysdeps/ieee754/dbl-64/wordsize-64 -I../sysdeps/ieee754/dbl-64 -I../sysdeps/ieee754/flt-32 -I../sysdeps/ieee754 -I../sysdeps/generic/elf -I../sysdeps/generic -I../nptl  -I.. -I../libio -I. -nostdinc -isystem C:/ctng-build-x-l-glibc_V_2.15-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/buildtools/lib/gcc/x86_64-unknown-linux-gnu/4.8.2/include -isystem C:/ctng-build-x-l-glibc_V_2.15-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/buildtools/lib/gcc/x86_64-unknown-linux-gnu/4.8.2/include-fixed -isystem /home/ukrdonnell/ctng-firefox-builds/x-l-glibc_V_2.15-x86_64-213be3fb/x86_64-unknown-linux-gnu/sysroot/usr/include -D_LIBC_REENTRANT -include ../include/libc-symbols.h  -DPIC -DSHARED     -D_RPC_THREAD_SAFE_ -o /c/ctng-build-x-l-glibc_V_2.15-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final/sunrpc/xdr_intXX_t.os -MD -MP -MF /c/ctng-build-x-l-glibc_V_2.15-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final/sunrpc/xdr_intXX_t.os.dt -MT /c/ctng-build-x-l-glibc_V_2.15-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final/sunrpc/xdr_intXX_t.os
[ALL  ]      x86_64-unknown-linux-gnu-gcc     xdr_mem.c -c -std=gnu99 -fgnu89-inline -O2 -U_FORTIFY_SOURCE -Wall -Winline -Wwrite-strings -fmerge-all-constants -Wstrict-prototypes   -fPIC      -I../include -I/c/ctng-build-x-l-glibc_V_2.15-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final/sunrpc -I/c/ctng-build-x-l-glibc_V_2.15-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final -I../sysdeps/x86_64/elf -I../nptl/sysdeps/unix/sysv/linux/x86_64 -I../sysdeps/unix/sysv/linux/x86_64 -I../sysdeps/unix/sysv/linux/wordsize-64 -I../nptl/sysdeps/unix/sysv/linux -I../nptl/sysdeps/pthread -I../sysdeps/pthread -I../sysdeps/unix/sysv/linux -I../sysdeps/gnu -I../sysdeps/unix/common -I../sysdeps/unix/mman -I../sysdeps/unix/inet -I../nptl/sysdeps/unix/sysv -I../sysdeps/unix/sysv -I../sysdeps/unix/x86_64 -I../nptl/sysdeps/unix -I../sysdeps/unix -I../sysdeps/posix -I../sysdeps/x86_64/fpu/multiarch -I../sysdeps/x86_64/fpu -I../sysdeps/x86_64/multiarch -I../nptl/sysdeps/x86_64 -I../sysdeps/x86_64 -I../sysdeps/wordsize-64 -I../sysdeps/ieee754/ldbl-96 -I../sysdeps/ieee754/dbl-64/wordsize-64 -I../sysdeps/ieee754/dbl-64 -I../sysdeps/ieee754/flt-32 -I../sysdeps/ieee754 -I../sysdeps/generic/elf -I../sysdeps/generic -I../nptl  -I.. -I../libio -I. -nostdinc -isystem C:/ctng-build-x-l-glibc_V_2.15-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/buildtools/lib/gcc/x86_64-unknown-linux-gnu/4.8.2/include -isystem C:/ctng-build-x-l-glibc_V_2.15-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/buildtools/lib/gcc/x86_64-unknown-linux-gnu/4.8.2/include-fixed -isystem /home/ukrdonnell/ctng-firefox-builds/x-l-glibc_V_2.15-x86_64-213be3fb/x86_64-unknown-linux-gnu/sysroot/usr/include -D_LIBC_REENTRANT -include ../include/libc-symbols.h  -DPIC -DSHARED     -D_RPC_THREAD_SAFE_ -o /c/ctng-build-x-l-glibc_V_2.15-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final/sunrpc/xdr_mem.os -MD -MP -MF /c/ctng-build-x-l-glibc_V_2.15-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final/sunrpc/xdr_mem.os.dt -MT /c/ctng-build-x-l-glibc_V_2.15-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final/sunrpc/xdr_mem.os
[ALL  ]      x86_64-unknown-linux-gnu-gcc     xdr_ref.c -c -std=gnu99 -fgnu89-inline -O2 -U_FORTIFY_SOURCE -Wall -Winline -Wwrite-strings -fmerge-all-constants -Wstrict-prototypes   -fPIC      -I../include -I/c/ctng-build-x-l-glibc_V_2.15-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final/sunrpc -I/c/ctng-build-x-l-glibc_V_2.15-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final -I../sysdeps/x86_64/elf -I../nptl/sysdeps/unix/sysv/linux/x86_64 -I../sysdeps/unix/sysv/linux/x86_64 -I../sysdeps/unix/sysv/linux/wordsize-64 -I../nptl/sysdeps/unix/sysv/linux -I../nptl/sysdeps/pthread -I../sysdeps/pthread -I../sysdeps/unix/sysv/linux -I../sysdeps/gnu -I../sysdeps/unix/common -I../sysdeps/unix/mman -I../sysdeps/unix/inet -I../nptl/sysdeps/unix/sysv -I../sysdeps/unix/sysv -I../sysdeps/unix/x86_64 -I../nptl/sysdeps/unix -I../sysdeps/unix -I../sysdeps/posix -I../sysdeps/x86_64/fpu/multiarch -I../sysdeps/x86_64/fpu -I../sysdeps/x86_64/multiarch -I../nptl/sysdeps/x86_64 -I../sysdeps/x86_64 -I../sysdeps/wordsize-64 -I../sysdeps/ieee754/ldbl-96 -I../sysdeps/ieee754/dbl-64/wordsize-64 -I../sysdeps/ieee754/dbl-64 -I../sysdeps/ieee754/flt-32 -I../sysdeps/ieee754 -I../sysdeps/generic/elf -I../sysdeps/generic -I../nptl  -I.. -I../libio -I. -nostdinc -isystem C:/ctng-build-x-l-glibc_V_2.15-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/buildtools/lib/gcc/x86_64-unknown-linux-gnu/4.8.2/include -isystem C:/ctng-build-x-l-glibc_V_2.15-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/buildtools/lib/gcc/x86_64-unknown-linux-gnu/4.8.2/include-fixed -isystem /home/ukrdonnell/ctng-firefox-builds/x-l-glibc_V_2.15-x86_64-213be3fb/x86_64-unknown-linux-gnu/sysroot/usr/include -D_LIBC_REENTRANT -include ../include/libc-symbols.h  -DPIC -DSHARED     -D_RPC_THREAD_SAFE_ -o /c/ctng-build-x-l-glibc_V_2.15-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final/sunrpc/xdr_ref.os -MD -MP -MF /c/ctng-build-x-l-glibc_V_2.15-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final/sunrpc/xdr_ref.os.dt -MT /c/ctng-build-x-l-glibc_V_2.15-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final/sunrpc/xdr_ref.os
[ALL  ]      x86_64-unknown-linux-gnu-gcc     xdr_sizeof.c -c -std=gnu99 -fgnu89-inline -O2 -U_FORTIFY_SOURCE -Wall -Winline -Wwrite-strings -fmerge-all-constants -Wstrict-prototypes   -fPIC      -I../include -I/c/ctng-build-x-l-glibc_V_2.15-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final/sunrpc -I/c/ctng-build-x-l-glibc_V_2.15-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final -I../sysdeps/x86_64/elf -I../nptl/sysdeps/unix/sysv/linux/x86_64 -I../sysdeps/unix/sysv/linux/x86_64 -I../sysdeps/unix/sysv/linux/wordsize-64 -I../nptl/sysdeps/unix/sysv/linux -I../nptl/sysdeps/pthread -I../sysdeps/pthread -I../sysdeps/unix/sysv/linux -I../sysdeps/gnu -I../sysdeps/unix/common -I../sysdeps/unix/mman -I../sysdeps/unix/inet -I../nptl/sysdeps/unix/sysv -I../sysdeps/unix/sysv -I../sysdeps/unix/x86_64 -I../nptl/sysdeps/unix -I../sysdeps/unix -I../sysdeps/posix -I../sysdeps/x86_64/fpu/multiarch -I../sysdeps/x86_64/fpu -I../sysdeps/x86_64/multiarch -I../nptl/sysdeps/x86_64 -I../sysdeps/x86_64 -I../sysdeps/wordsize-64 -I../sysdeps/ieee754/ldbl-96 -I../sysdeps/ieee754/dbl-64/wordsize-64 -I../sysdeps/ieee754/dbl-64 -I../sysdeps/ieee754/flt-32 -I../sysdeps/ieee754 -I../sysdeps/generic/elf -I../sysdeps/generic -I../nptl  -I.. -I../libio -I. -nostdinc -isystem C:/ctng-build-x-l-glibc_V_2.15-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/buildtools/lib/gcc/x86_64-unknown-linux-gnu/4.8.2/include -isystem C:/ctng-build-x-l-glibc_V_2.15-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/buildtools/lib/gcc/x86_64-unknown-linux-gnu/4.8.2/include-fixed -isystem /home/ukrdonnell/ctng-firefox-builds/x-l-glibc_V_2.15-x86_64-213be3fb/x86_64-unknown-linux-gnu/sysroot/usr/include -D_LIBC_REENTRANT -include ../include/libc-symbols.h  -DPIC -DSHARED     -D_RPC_THREAD_SAFE_ -o /c/ctng-build-x-l-glibc_V_2.15-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final/sunrpc/xdr_sizeof.os -MD -MP -MF /c/ctng-build-x-l-glibc_V_2.15-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final/sunrpc/xdr_sizeof.os.dt -MT /c/ctng-build-x-l-glibc_V_2.15-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final/sunrpc/xdr_sizeof.os
[ALL  ]      x86_64-unknown-linux-gnu-gcc     xdr_stdio.c -c -std=gnu99 -fgnu89-inline -O2 -U_FORTIFY_SOURCE -Wall -Winline -Wwrite-strings -fmerge-all-constants -Wstrict-prototypes   -fPIC      -I../include -I/c/ctng-build-x-l-glibc_V_2.15-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final/sunrpc -I/c/ctng-build-x-l-glibc_V_2.15-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final -I../sysdeps/x86_64/elf -I../nptl/sysdeps/unix/sysv/linux/x86_64 -I../sysdeps/unix/sysv/linux/x86_64 -I../sysdeps/unix/sysv/linux/wordsize-64 -I../nptl/sysdeps/unix/sysv/linux -I../nptl/sysdeps/pthread -I../sysdeps/pthread -I../sysdeps/unix/sysv/linux -I../sysdeps/gnu -I../sysdeps/unix/common -I../sysdeps/unix/mman -I../sysdeps/unix/inet -I../nptl/sysdeps/unix/sysv -I../sysdeps/unix/sysv -I../sysdeps/unix/x86_64 -I../nptl/sysdeps/unix -I../sysdeps/unix -I../sysdeps/posix -I../sysdeps/x86_64/fpu/multiarch -I../sysdeps/x86_64/fpu -I../sysdeps/x86_64/multiarch -I../nptl/sysdeps/x86_64 -I../sysdeps/x86_64 -I../sysdeps/wordsize-64 -I../sysdeps/ieee754/ldbl-96 -I../sysdeps/ieee754/dbl-64/wordsize-64 -I../sysdeps/ieee754/dbl-64 -I../sysdeps/ieee754/flt-32 -I../sysdeps/ieee754 -I../sysdeps/generic/elf -I../sysdeps/generic -I../nptl  -I.. -I../libio -I. -nostdinc -isystem C:/ctng-build-x-l-glibc_V_2.15-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/buildtools/lib/gcc/x86_64-unknown-linux-gnu/4.8.2/include -isystem C:/ctng-build-x-l-glibc_V_2.15-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/buildtools/lib/gcc/x86_64-unknown-linux-gnu/4.8.2/include-fixed -isystem /home/ukrdonnell/ctng-firefox-builds/x-l-glibc_V_2.15-x86_64-213be3fb/x86_64-unknown-linux-gnu/sysroot/usr/include -D_LIBC_REENTRANT -include ../include/libc-symbols.h  -DPIC -DSHARED     -D_RPC_THREAD_SAFE_ -o /c/ctng-build-x-l-glibc_V_2.15-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final/sunrpc/xdr_stdio.os -MD -MP -MF /c/ctng-build-x-l-glibc_V_2.15-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final/sunrpc/xdr_stdio.os.dt -MT /c/ctng-build-x-l-glibc_V_2.15-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final/sunrpc/xdr_stdio.os
[ALL  ]      x86_64-unknown-linux-gnu-gcc     svc_run.c -c -std=gnu99 -fgnu89-inline -O2 -U_FORTIFY_SOURCE -Wall -Winline -Wwrite-strings -fmerge-all-constants -Wstrict-prototypes   -fPIC      -I../include -I/c/ctng-build-x-l-glibc_V_2.15-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final/sunrpc -I/c/ctng-build-x-l-glibc_V_2.15-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final -I../sysdeps/x86_64/elf -I../nptl/sysdeps/unix/sysv/linux/x86_64 -I../sysdeps/unix/sysv/linux/x86_64 -I../sysdeps/unix/sysv/linux/wordsize-64 -I../nptl/sysdeps/unix/sysv/linux -I../nptl/sysdeps/pthread -I../sysdeps/pthread -I../sysdeps/unix/sysv/linux -I../sysdeps/gnu -I../sysdeps/unix/common -I../sysdeps/unix/mman -I../sysdeps/unix/inet -I../nptl/sysdeps/unix/sysv -I../sysdeps/unix/sysv -I../sysdeps/unix/x86_64 -I../nptl/sysdeps/unix -I../sysdeps/unix -I../sysdeps/posix -I../sysdeps/x86_64/fpu/multiarch -I../sysdeps/x86_64/fpu -I../sysdeps/x86_64/multiarch -I../nptl/sysdeps/x86_64 -I../sysdeps/x86_64 -I../sysdeps/wordsize-64 -I../sysdeps/ieee754/ldbl-96 -I../sysdeps/ieee754/dbl-64/wordsize-64 -I../sysdeps/ieee754/dbl-64 -I../sysdeps/ieee754/flt-32 -I../sysdeps/ieee754 -I../sysdeps/generic/elf -I../sysdeps/generic -I../nptl  -I.. -I../libio -I. -nostdinc -isystem C:/ctng-build-x-l-glibc_V_2.15-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/buildtools/lib/gcc/x86_64-unknown-linux-gnu/4.8.2/include -isystem C:/ctng-build-x-l-glibc_V_2.15-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/buildtools/lib/gcc/x86_64-unknown-linux-gnu/4.8.2/include-fixed -isystem /home/ukrdonnell/ctng-firefox-builds/x-l-glibc_V_2.15-x86_64-213be3fb/x86_64-unknown-linux-gnu/sysroot/usr/include -D_LIBC_REENTRANT -include ../include/libc-symbols.h  -DPIC -DSHARED     -D_RPC_THREAD_SAFE_ -o /c/ctng-build-x-l-glibc_V_2.15-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final/sunrpc/svc_run.os -MD -MP -MF /c/ctng-build-x-l-glibc_V_2.15-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final/sunrpc/svc_run.os.dt -MT /c/ctng-build-x-l-glibc_V_2.15-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final/sunrpc/svc_run.os
[ALL  ]      Makefile:220: recipe for target 'sunrpc/subdir_lib' failed
[ERROR]      make[2]: *** [sunrpc/subdir_lib] Segmentation fault (core dumped)
[ALL  ]      make[2]: Leaving directory '/c/ctng-build-x-l-glibc_V_2.15-x86_64-213be3fb/.build/src/glibc-2.15'
[ALL  ]      Makefile:7: recipe for target 'all' failed
[ERROR]      make[1]: *** [all] Error 2
[ALL  ]      make[1]: INTERNAL: Exiting with 1 jobserver tokens available; should be 9!
[ALL  ]      make[1]: Leaving directory '/c/ctng-build-x-l-glibc_V_2.15-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final'

[EXTRA]      Building C library
[DEBUG]      ==> Executing: 'make' '-j9' '-l' 'BUILD_CPPFLAGS=-I/c/ctng-build-x-l-glibc_V_2.15-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/buildtools/include/' 'BUILD_LDFLAGS=-L/c/ctng-build-x-l-glibc_V_2.15-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/buildtools/lib -Wl,-Bstatic -lintl -Wl,-Bdynamic' 'all' 

pushd /c/ctng-build-x-l-glibc_V_2.15-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/build/build-libc-final
PATH=/c/ctng-build-x-l-glibc_V_2.15-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/buildtools/bin:$PATH \
make -j9 -l \
  BUILD_CPPFLAGS=-I/c/ctng-build-x-l-glibc_V_2.15-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/buildtools/include/ \
  BUILD_LDFLAGS=-L/c/ctng-build-x-l-glibc_V_2.15-x86_64-213be3fb/.build/x86_64-unknown-linux-gnu/buildtools/lib \
  -Wl,-Bstatic -lintl -Wl,-Bdynamic all 

cd /c/ctng-build-x-l-glibc_V_2.15-x86_64-213be3fb
/c/Users/ukrdonnell/ctng-firefox-builds/bin/ct-ng libc+
