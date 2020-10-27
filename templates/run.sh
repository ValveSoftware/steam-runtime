#!/bin/bash
#
# This is a script which runs programs in the Steam runtime

set -e
set -u
set -o pipefail

# The top level of the runtime tree
STEAM_RUNTIME=$(cd "${0%/*}" && pwd)
# Note that we put the Steam runtime first
# If ldd on a program shows any library in the system path, then that program
# may not run in the Steam runtime.
export STEAM_RUNTIME

# Make sure we have something to run
if [ "$1" = "" ]; then
    echo "Usage: $0 program [args]"
    exit 1
fi

# Save the system paths, they might be useful later
if [ -z "${SYSTEM_PATH-}" ]; then
    export SYSTEM_PATH="${PATH-}"
fi
if [ -z "${SYSTEM_LD_LIBRARY_PATH-}" ]; then
    export SYSTEM_LD_LIBRARY_PATH="${LD_LIBRARY_PATH-}"
fi

if [ -z "${SYSTEM_ZENITY-}" ]; then
    # Prefer host zenity binary if available
    SYSTEM_ZENITY="$(command -v zenity || true)"
    export SYSTEM_ZENITY
    if [ -z "${SYSTEM_ZENITY}" ]; then
        export STEAM_ZENITY="zenity"
    else
        export STEAM_ZENITY="${SYSTEM_ZENITY}"
    fi
fi

set_bin_path()
{
    local arch
    local unique_steam_runtime_paths

    unique_steam_runtime_paths=

    case "$(uname -m)" in
        (*64)
            arch=amd64
            ;;
        (*)
            arch=i386
            ;;
    esac

    # Keep this in sync with setup.sh
    for rt_path in "$STEAM_RUNTIME/$arch/bin" "$STEAM_RUNTIME/$arch/usr/bin" "$STEAM_RUNTIME/usr/bin"; do
        case ":${PATH}:" in
            (*:${rt_path}:*)
                # rt_path is already in PATH, ignore
                ;;

            (*)
                # rt_path is not in PATH, save it and then prepend it to PATH
                unique_steam_runtime_paths="${unique_steam_runtime_paths}${rt_path}:"
                ;;
        esac
    done

    # Prepend the Steam Runtime's paths
    export PATH="${unique_steam_runtime_paths}${PATH}"
}

host_library_paths=

if [[ "${STEAM_RUNTIME_PREFER_HOST_LIBRARIES-}" == "0" ]]; then
    echo "STEAM_RUNTIME_PREFER_HOST_LIBRARIES=0 is deprecated, and no longer has an effect." >&2
fi

exit_status=0
ldconfig_output=$(/sbin/ldconfig -XNv 2> /dev/null; exit $?) || exit_status=$?
if [[ $exit_status != 0 ]]; then
    echo "Warning: An unexpected error occurred while executing \"/sbin/ldconfig -XNv\", the exit status was $exit_status" >&2
fi

# Always prefer host libraries over non-pinned Runtime libraries.
# (In older versions this was conditional, but if we don't do this,
# it usually breaks Mesa drivers' dependencies.)
while read -r line; do
    # If line starts with a leading / and contains :, it's a new path prefix
    if [[ "$line" =~ ^/.*: ]]
    then
        library_path_prefix=$(echo "$line" | cut -d: -f1)

        host_library_paths=$host_library_paths$library_path_prefix:
    fi
done <<< "$ldconfig_output"

host_library_paths="${LD_LIBRARY_PATH:+"${LD_LIBRARY_PATH}:"}$host_library_paths"

host_library_paths="$STEAM_RUNTIME/pinned_libs_32:$STEAM_RUNTIME/pinned_libs_64:$host_library_paths"

steam_runtime_library_paths="$host_library_paths$STEAM_RUNTIME/lib/i386-linux-gnu:$STEAM_RUNTIME/usr/lib/i386-linux-gnu:$STEAM_RUNTIME/lib/x86_64-linux-gnu:$STEAM_RUNTIME/usr/lib/x86_64-linux-gnu:$STEAM_RUNTIME/lib:$STEAM_RUNTIME/usr/lib"

if [ "$1" = "--print-steam-runtime-library-paths" ]; then
    echo "$steam_runtime_library_paths"
    exit 0
fi

export LD_LIBRARY_PATH="$steam_runtime_library_paths"

set_bin_path

exec "$@"

# vi: ts=4 sw=4 expandtab
