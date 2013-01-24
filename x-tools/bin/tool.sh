#!/bin/bash
#
# This is a script which runs tools set up for the Steam runtime

PROGRAM=$(basename "$0")

# The top level of the cross-compiler tree
TOP=$(cd "${0%/*}" && echo "${PWD}/..")

if [ -z "${HOST_ARCH}" ]; then
    export HOST_ARCH=$(dpkg --print-architecture)
fi

if [ -z "${TARGET_ARCH}" ]; then
    for arg in "$@"; do
        if [ "${arg}" = "-m32" ]; then
            TARGET_ARCH="i386"
            break
        elif [ "${arg}" = "-m64" ]; then
            TARGET_ARCH="amd64"
            break
        fi
    done
    if [ -z "${TARGET_ARCH}" ]; then
        TARGET_ARCH="${HOST_ARCH}"
    fi
    export TARGET_ARCH
fi
            
if [ -z "${STEAM_RUNTIME}" ]; then
    if [ -d "${TOP}/runtime/${TARGET_ARCH}" ]; then
        STEAM_RUNTIME="${TOP}/runtime/${TARGET_ARCH}"
    elif [ -d "${TOP}/../runtime/${TARGET_ARCH}" ]; then
        STEAM_RUNTIME="${TOP}/../runtime/${TARGET_ARCH}"
    fi
    if [ ! -d "${STEAM_RUNTIME}" ]; then
        echo "Couldn't find runtime directory ${STEAM_RUNTIME}" >&2
        exit 2
    fi
    export STEAM_RUNTIME
fi

case "${TARGET_ARCH}" in
i386)
    CROSSTOOL_PREFIX="i686-unknown-linux-gnu"
    CROSSTOOL_LIBPATH="i386-linux-gnu"
    ;;
amd64)
    CROSSTOOL_PREFIX="x86_64-unknown-linux-gnu"
    CROSSTOOL_LIBPATH="x86_64-linux-gnu"
    ;;
*)
    echo "Unknown target architecture: ${TARGET_ARCH}"
    exit 1
    ;;
esac
CROSSTOOL_PATH="${TOP}/${HOST_ARCH}/${CROSSTOOL_PREFIX}/bin"

# Function to insert an argument into a bash array
function insert_arg()
{
    INDEX=$1
    ARG=$2

    # Shift other elements up
    i=${#ARGS[@]}
    while [ $i -gt ${INDEX} ]; do
        ARGS[$i]="${ARGS[$(expr $i - 1)]}"
        i=$(expr $i - 1)
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

function update_includes()
{
    i=${#ARGS[@]}
    while [ $i -gt 0 ]; do
        i=$(expr $i - 1)
        case "${ARGS[$i]}" in
        -I)
            path="${ARGS[$(expr $i + 1)]}"
            case "${path}" in
            /usr/include*)
                ARGS[$(expr $i + 1)]="${STEAM_RUNTIME}${path}"
                ;;
            esac
            INCLUDE_PATHS["${path}"]=true
            ;;
        -I*)
            path="$(expr "${ARGS[$i]}" : "-I\(.*\)")"
            case "${path}" in
            /usr/include*)
                ARGS[$i]="-I${STEAM_RUNTIME}${path}"
                ;;
            esac
            INCLUDE_PATHS["${path}"]=true
            ;;
        esac
    done

    if [ "${INCLUDE_PATHS["/usr/include"]}" = "" ]; then
        append_arg "-I${STEAM_RUNTIME}/usr/include"
    fi
}

function update_libraries()
{
    i=${#ARGS[@]}
    while [ $i -gt 0 ]; do
        i=$(expr $i - 1)
        case "${ARGS[$i]}" in
        -L)
            path="${ARGS[$(expr $i + 1)]}"
            case "${path}" in
            /usr/lib*)
                ARGS[$(expr $i + 1)]="${STEAM_RUNTIME}${path}"
                insert_arg $(expr $i + 2) "-Wl,-rpath-link=${STEAM_RUNTIME}${path}"
                ;;
            esac
            LIBRARY_PATHS["${path}"]=true
            ;;
        -L*)
            path="$(expr "${ARGS[$i]}" : "-L\(.*\)")"
            case "${path}" in
            /usr/lib*)
                ARGS[$i]="-L${STEAM_RUNTIME}${path}"
                insert_arg $(expr $i + 1) "-Wl,-rpath-link=${STEAM_RUNTIME}${path}"
                ;;
            esac
            LIBRARY_PATHS["${path}"]=true
            ;;
        -Wl,-rpath*|-rpath*)
            option="$(expr "${ARGS[$i]}" : "\([^=]*\)=.*")"
            path="$(expr "${ARGS[$i]}" : "[^=]*=\(.*\)")"
            case "${path}" in
            /usr/lib*)
                ARGS[$i]="${option}=${STEAM_RUNTIME}${path}"
                ;;
            esac
            ;;
        esac
    done

    if [ "${LIBRARY_PATHS["/usr/lib"]}" = "" ]; then
        append_arg "-L${STEAM_RUNTIME}/usr/lib"
        append_arg "-Wl,-rpath-link=${STEAM_RUNTIME}/usr/lib"
    fi
    if [ "${LIBRARY_PATHS["/usr/lib/${CROSSTOOL_LIBPATH}"]}" = "" ]; then
        append_arg "-L${STEAM_RUNTIME}/usr/lib/${CROSSTOOL_LIBPATH}"
        append_arg "-Wl,-rpath-link=${STEAM_RUNTIME}/usr/lib/${CROSSTOOL_LIBPATH}"
    fi
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
        gcc|g++)
            update_includes
            update_libraries
            ;;
    esac
fi

# Run the tool...
exec "${CROSSTOOL_PATH}/${CROSSTOOL_PREFIX}-${PROGRAM}" "${ARGS[@]}"

# vi: ts=4 sw=4 expandtab
