#!/bin/bash
#
# This is a script which runs tools set up for the Steam runtime

PROGRAM=$(basename "$0")

# The top level of the cross-compiler tree
TOP=$(cd "${0%/*}" && echo "${PWD}/..")

if [ -z "${STEAM_RUNTIME_HOST_ARCH}" ]; then
    export STEAM_RUNTIME_HOST_ARCH=$(dpkg --print-architecture)
fi

for arg in "$@"; do
    if [ "${arg}" = "-m32" ]; then
        STEAM_RUNTIME_TARGET_ARCH="i386"
        break
    elif [ "${arg}" = "-m64" ]; then
        STEAM_RUNTIME_TARGET_ARCH="amd64"
        break
    fi
done
if [ -z "${STEAM_RUNTIME_TARGET_ARCH}" ]; then
    export STEAM_RUNTIME_TARGET_ARCH="${STEAM_RUNTIME_HOST_ARCH}"
fi
            
case "${STEAM_RUNTIME_TARGET_ARCH}" in
i386)
    CROSSTOOL_PREFIX="i686-unknown-linux-gnu"
    CROSSTOOL_LIBPATH="i386-linux-gnu"
    ;;
amd64)
    CROSSTOOL_PREFIX="x86_64-unknown-linux-gnu"
    CROSSTOOL_LIBPATH="x86_64-linux-gnu"
    ;;
*)
    echo "Unknown target architecture: ${STEAM_RUNTIME_TARGET_ARCH}"
    exit 1
    ;;
esac
CROSSTOOL_PATH="${TOP}/${STEAM_RUNTIME_HOST_ARCH}/${CROSSTOOL_PREFIX}/bin"

# Function to insert an argument into a bash array
function insert_arg()
{
    INDEX=$1
    ARG=$2

    # Shift other elements up
    i=${#ARGS[@]}
    while [ $i -gt ${INDEX} ]; do
        ARGS[$i]="${ARGS[$(($i - 1))]}"
        i=$(($i - 1))
    done

    # Add the new argument
    ARGS[${INDEX}]="${ARG}"
}

# Function to append an argument to the end of a bash array
function append_arg()
{
    ARGS+=("$1")
}

# Update include and library paths
declare -A INCLUDE_PATHS
declare -A LIBRARY_PATHS

function check_runtime_root()
{
    if [ -z "${STEAM_RUNTIME_ROOT}" ]; then
        if [ -d "${TOP}/runtime/${STEAM_RUNTIME_TARGET_ARCH}" ]; then
            STEAM_RUNTIME_ROOT="${TOP}/runtime/${STEAM_RUNTIME_TARGET_ARCH}"
        fi
        if [ ! -d "${STEAM_RUNTIME_ROOT}" ]; then
            echo "$0: ERROR: Couldn't find steam runtime directory, do you need to run the setup script?" >&2
            realpath "${TOP}/setup.sh" >&2
            exit 2
        fi
        export STEAM_RUNTIME_ROOT
    fi
}

function update_includes()
{
    check_runtime_root

    i=${#ARGS[@]}
    while [ $i -gt 0 ]; do
        i=$(($i - 1))
        case "${ARGS[$i]}" in
        -I)
            path="${ARGS[$(($i + 1))]}"
            case "${path}" in
            /usr/include*|/usr/lib*)
                ARGS[$(($i + 1))]="${STEAM_RUNTIME_ROOT}${path}"
                ;;
            esac
            INCLUDE_PATHS["${path}"]=true
            ;;
        -I*)
            path="$(expr "${ARGS[$i]}" : "-I\(.*\)")"
            case "${path}" in
            /usr/include*|/usr/lib*)
                ARGS[$i]="-I${STEAM_RUNTIME_ROOT}${path}"
                ;;
            esac
            INCLUDE_PATHS["${path}"]=true
            ;;
        esac
    done

    if [ "${INCLUDE_PATHS["/usr/include"]}" = "" ]; then
        append_arg "-I${STEAM_RUNTIME_ROOT}/usr/include"
    fi
}

function update_libraries()
{
    check_runtime_root

    i=${#ARGS[@]}
    while [ $i -gt 0 ]; do
        i=$(($i - 1))
        case "${ARGS[$i]}" in
        -L)
            path="${ARGS[$(($i + 1))]}"
            case "${path}" in
            /usr/lib*)
                ARGS[$(($i + 1))]="${STEAM_RUNTIME_ROOT}${path}"
                insert_arg $(($i + 2)) "-Wl,-rpath-link=${STEAM_RUNTIME_ROOT}${path}"
                ;;
            esac
            LIBRARY_PATHS["${path}"]=true
            ;;
        -L*)
            path="$(expr "${ARGS[$i]}" : "-L\(.*\)")"
            case "${path}" in
            /usr/lib*)
                ARGS[$i]="-L${STEAM_RUNTIME_ROOT}${path}"
                insert_arg $(($i + 1)) "-Wl,-rpath-link=${STEAM_RUNTIME_ROOT}${path}"
                ;;
            esac
            LIBRARY_PATHS["${path}"]=true
            ;;
        -Wl,-rpath*|-rpath*)
            option="$(expr "${ARGS[$i]}" : "\([^=]*\)=.*")"
            path="$(expr "${ARGS[$i]}" : "[^=]*=\(.*\)")"
            case "${path}" in
            /usr/lib*)
                ARGS[$i]="${option}=${STEAM_RUNTIME_ROOT}${path}"
                ;;
            esac
            ;;
        esac
    done

    if [ "${PROGRAM}" != "ld" ]; then
        LINK_OPTION_PREFIX="-Wl,"
    else
        LINK_OPTION_PREFIX=""
    fi

    # Make sure everything we build has a build id
    append_arg "${LINK_OPTION_PREFIX}--build-id"

    if [ "${LIBRARY_PATHS["/lib"]}" = "" ]; then
        append_arg "-L${STEAM_RUNTIME_ROOT}/lib"
        append_arg "${LINK_OPTION_PREFIX}-rpath-link=${STEAM_RUNTIME_ROOT}/lib"
    fi
    if [ "${LIBRARY_PATHS["/lib/${CROSSTOOL_LIBPATH}"]}" = "" ]; then
        append_arg "-L${STEAM_RUNTIME_ROOT}/lib/${CROSSTOOL_LIBPATH}"
        append_arg "${LINK_OPTION_PREFIX}-rpath-link=${STEAM_RUNTIME_ROOT}/lib/${CROSSTOOL_LIBPATH}"
    fi
    if [ "${LIBRARY_PATHS["/usr/lib"]}" = "" ]; then
        append_arg "-L${STEAM_RUNTIME_ROOT}/usr/lib"
        append_arg "${LINK_OPTION_PREFIX}-rpath-link=${STEAM_RUNTIME_ROOT}/usr/lib"
    fi
    if [ "${LIBRARY_PATHS["/usr/lib/${CROSSTOOL_LIBPATH}"]}" = "" ]; then
        append_arg "-L${STEAM_RUNTIME_ROOT}/usr/lib/${CROSSTOOL_LIBPATH}"
        append_arg "${LINK_OPTION_PREFIX}-rpath-link=${STEAM_RUNTIME_ROOT}/usr/lib/${CROSSTOOL_LIBPATH}"
    fi
}

function print_search_dirs()
{
    check_runtime_root

    EXTRA_LIBRARY_PATHS="${STEAM_RUNTIME_ROOT}/lib:${STEAM_RUNTIME_ROOT}/lib/${CROSSTOOL_LIBPATH}:${STEAM_RUNTIME_ROOT}/usr/lib:${STEAM_RUNTIME_ROOT}/usr/lib/${CROSSTOOL_LIBPATH}"
    "${CROSSTOOL_PATH}/${CROSSTOOL_PREFIX}-${PROGRAM}" "${ARGS[@]}" | sed "s,\(libraries:.*\),\1:${EXTRA_LIBRARY_PATHS},"
}

# Add any additional command line parameters
declare -a ARGS
if [ "$1" = "--disable-runtime-path" ]; then
    shift
    DISABLE_RUNTIME_PATH=true
fi
ARGS=("$@")

if [ -z "${DISABLE_RUNTIME_PATH}" ]; then
    case "${PROGRAM}" in
        ld)
            update_libraries
            ;;
        gcc|g++|cc|c++)
            # Search dirs needs special handling to include runtime paths
            if $(echo "$*" | grep -- "-print-search-dirs" >/dev/null); then
                print_search_dirs
                exit 0
            fi
            update_includes
            update_libraries
            ;;
    esac
fi

# Run the tool...
exec "${CROSSTOOL_PATH}/${CROSSTOOL_PREFIX}-${PROGRAM}" "${ARGS[@]}"

# vi: ts=4 sw=4 expandtab
