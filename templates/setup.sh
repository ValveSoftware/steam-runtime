#!/bin/bash
# Copyright 2012-2019 Valve Software
# Copyright 2019 Collabora Ltd.
#
# SPDX-License-Identifier: MIT

set -e
set -u
set -o pipefail

# Check if set, which is normally done by steam.sh, but will not be set when invoked directly
if [ -z "${STEAM_ZENITY+x}" ]; then
    # We are likely outside of run.sh as well, only use the host zenity
    STEAM_ZENITY="$(command -v zenity || true)"
    export STEAM_ZENITY
fi

pin_newer_runtime_libs ()
{
    # Set separator to newline just for this function
    local IFS
    IFS=$(echo -en '\n\b')

    local steam_runtime_path
    local zenity_progress=true

    # First argument is the runtime path
    steam_runtime_path=$(realpath "$1")

    if [[ ! -d "$steam_runtime_path" ]]; then return; fi

    # Second optional argument is the zenity print progress flag
    if [[ "$#" -gt 1 ]]; then
        zenity_progress=$2
    fi

    # Associative array; indices are the SONAME, values are final path
    local -A host_libraries_32
    local -A host_libraries_64

    local bitness
    local final_library
    local find_num
    local find_output
    local find_output_array
    local h_lib_major
    local h_lib_minor
    local h_lib_third
    local host_library
    local host_soname_symlink
    local ldconfig_num
    local ldconfig_output
    local ldconfig_output_array
    local leftside
    local library_path_prefix
    local n_done
    local r_lib_major
    local r_lib_minor
    local r_lib_third
    local runtime_version_newer
    local soname
    local soname_fullpath
    local soname_symlink

    rm -rf "$steam_runtime_path/pinned_libs_32"
    rm -rf "$steam_runtime_path/pinned_libs_64"

    # By roughly timing the average execution time we divided the progress in three parts:
    # The setup, 4% of the total
    # The ldconfig, 60% of the total
    # The pinning, 35% of the total
    # And at the end we just print 100%
    if [ "$zenity_progress" = true ]; then
        echo 4
    else
        printf '\r 4%%    \r'
    fi

    # First, grab the list of system libraries from ldconfig and put them in the arrays
    shopt -s lastpipe
    if /sbin/ldconfig -XNv 2> /dev/null | mapfile -t ldconfig_output_array; then
        true  # OK
    else
        >&2 echo "Warning: An unexpected error occurred while executing \"/sbin/ldconfig -XNv\", the exit status was $?"
    fi

    ldconfig_num=${#ldconfig_output_array[@]}
    n_done=0

    for ldconfig_output in "${ldconfig_output_array[@]}"
    do
        if [ "$zenity_progress" = true ]; then
            echo $(( ( 60 * n_done ) / ldconfig_num + 4 ))
        else
            printf '\r %d%%    \r' $(( ( 60 * n_done ) / ldconfig_num + 4 ))
        fi
        (( n_done=n_done+1 ))
        # If line starts with a leading / and contains :, it's a new path prefix
        if [[ "$ldconfig_output" =~ ^/.*: ]]
        then
            library_path_prefix=$(echo "$ldconfig_output" | cut -d: -f1)
        else
            # Otherwise it's a soname symlink -> library pair, build a full path to the soname link
            leftside=${ldconfig_output% -> *}
            soname=$(echo "$leftside" | tr -d '[:space:]')
            soname_fullpath=$library_path_prefix/$soname

            # Left side better be a symlink
            if [[ ! -L $soname_fullpath ]]; then continue; fi

            # Left-hand side of soname symlink should be *.so.%d
            if [[ ! $soname_fullpath =~ .*\.so.[[:digit:]]+$ ]]; then continue; fi

            if ! final_library=$(readlink -f "$soname_fullpath")
            then
                continue
            fi

            # Target library must be named *.so.%d.%d.%d
            if [[ ! $final_library =~ .*\.so.[[:digit:]]+.[[:digit:]]+.[[:digit:]]+$ ]]; then continue; fi

            # If it doesn't exist, skip as well
            if [[ ! -f $final_library ]]; then continue; fi

            # Save into bitness-specific associative array with only SONAME as left-hand
            if [[ $(file -L "$final_library") == *"32-bit"* ]]
            then
                host_libraries_32[$soname]=$soname_fullpath
            elif [[ $(file -L "$final_library") == *"64-bit"* ]]
            then
                host_libraries_64[$soname]=$soname_fullpath
            fi
        fi
    done

    if [ "$zenity_progress" = true ]; then
        echo 64
    else
        printf '\r 64%%    \r'
    fi

    mkdir "$steam_runtime_path/pinned_libs_32"
    mkdir "$steam_runtime_path/pinned_libs_64"

    mapfile -t find_output_array < <(find "$steam_runtime_path" -type l | grep \\\.so)
    find_num=${#find_output_array[@]}
    n_done=0

    for find_output in "${find_output_array[@]}"
    do
        if [ "$zenity_progress" = true ]; then
            echo $(( ( 35 * n_done ) / find_num + 64 ))
        else
            printf '\r %d%%    \r' $(( ( 35 * n_done ) / find_num + 64 ))
        fi
        (( n_done=n_done+1 ))
        # Left-hand side of soname symlink should be *.so.%d
        if [[ ! $find_output =~ .*\.so.[[:digit:]]+$ ]]; then continue; fi

        soname_symlink=$find_output

        if ! final_library=$(readlink -f "$soname_symlink")
        then
            continue
        fi

        # Target library must be named *.so.%d.%d.%d
        if [[ ! $final_library =~ .*\.so.([[:digit:]]+).([[:digit:]]+).([[:digit:]]+)$ ]]; then continue; fi

        # This pattern strips leading zeroes, which could otherwise cause bash to interpret the value as binary/octal below
        r_lib_major=$((10#${BASH_REMATCH[1]}))
        r_lib_minor=$((10#${BASH_REMATCH[2]}))
        r_lib_third=$((10#${BASH_REMATCH[3]}))

        # If it doesn't exist, skip as well
        if [[ ! -f $final_library ]]; then continue; fi

        host_library=""
        host_soname_symlink=""
        bitness="unknown"

        soname=$(basename "$soname_symlink")

        # If we had entries in our arrays, get them
        if [[ $(file -L "$final_library") == *"32-bit"* ]]
        then
            if [ -n "${host_libraries_32[$soname]+isset}" ]
            then
                host_soname_symlink=${host_libraries_32[$soname]}
            fi
            bitness="32"
        elif [[ $(file -L "$final_library") == *"64-bit"* ]]
        then
            if [ -n "${host_libraries_64[$soname]+isset}" ]
            then
                host_soname_symlink=${host_libraries_64[$soname]}
            fi
            bitness="64"
        fi

        # Do we have a host library found for the same SONAME?
        if [[ ! -f $host_soname_symlink || $bitness == "unknown" ]]; then continue; fi

        host_library=$(readlink -f "$host_soname_symlink")

        if [[ ! -f $host_library ]]; then continue; fi

        #echo $soname ${host_libraries[$soname]} $r_lib_major $r_lib_minor $r_lib_third

        # Pretty sure the host library already matches, but we need the rematch anyway
        if [[ ! $host_library =~ .*\.so.([[:digit:]]+).([[:digit:]]+).([[:digit:]]+)$ ]]; then continue; fi

        h_lib_major=$((10#${BASH_REMATCH[1]}))
        h_lib_minor=$((10#${BASH_REMATCH[2]}))
        h_lib_third=$((10#${BASH_REMATCH[3]}))

        runtime_version_newer="no"

        if [[ $h_lib_major -lt $r_lib_major ]]; then
            runtime_version_newer="yes"
        fi

        if [[ $h_lib_major -eq $r_lib_major && $h_lib_minor -lt $r_lib_minor ]]; then
            runtime_version_newer="yes"
        fi

        if [[ $h_lib_major -eq $r_lib_major && $h_lib_minor -eq $r_lib_minor && $h_lib_third -lt $r_lib_third ]]; then
            runtime_version_newer="yes"
        fi

        # There's a set of libraries that have to work together to yield a working dock
        # We're reasonably convinced our set works well, and only pinning a handful would
        # induce a mismatch and break the dock, so always pin all of these for Steam (32-bit)
        if [[ $bitness == "32" ]]
        then
            if [[     "$soname" == "libgtk-x11-2.0.so.0"  || \
                    "$soname" == "libdbusmenu-gtk.so.4"  || \
                    "$soname" == "libdbusmenu-glib.so.4" || \
                    "$soname" == "libdbus-1.so.3" ]]
            then
                runtime_version_newer="forced"
            fi
        fi

        case "$soname" in
            (libcurl.so.4)
                # libcurl in the Steam Runtime is internally identified
                # as libcurl.so.4, but with a symlink at libcurl.so.3
                # as a result of some unfortunate ABI weirdness back in
                # 2007. It also has Debian-specific symbol versioning as a
                # result of the versioned symbols introduced as a
                # Debian-specific change in 2005-2006, which were preserved
                # across the rename from libcurl.so.3 to libcurl.so.4, not
                # matching the versioned symbols that upstream subsequently
                # added to libcurl.so.4; as a result, a system libcurl.so.4
                # probably isn't going to be a drop-in replacement for our
                # libcurl.
                #
                # Debian/Ubuntu subsequently (in 2018) switched to a SONAME
                # and versioning that match upstream, but the Steam Runtime
                # is based on a version that is older than that, so anything
                # built against the Steam Runtime will expect the old SONAME
                # and versioned symbols; make sure we use the Steam Runtime
                # version.
                runtime_version_newer="forced"
                ;;
        esac

        # Print to stderr because zenity is consuming stdout
        if [[ $runtime_version_newer == "yes" ]]; then
            >&2 echo "Found newer runtime version for $bitness-bit $soname. Host: $h_lib_major.$h_lib_minor.$h_lib_third Runtime: $r_lib_major.$r_lib_minor.$r_lib_third"
        elif [[ $runtime_version_newer == "forced" ]]; then
            >&2 echo "Forced use of runtime version for $bitness-bit $soname. Host: $h_lib_major.$h_lib_minor.$h_lib_third Runtime: $r_lib_major.$r_lib_minor.$r_lib_third"
        fi

        if [[ $runtime_version_newer == "yes" \
              || $runtime_version_newer == "forced" ]]; then
            ln -s "$final_library" "$steam_runtime_path/pinned_libs_$bitness/$soname"
            # Keep track of the exact version name we saw on the system at pinning time to check later
            >&2 echo "$host_soname_symlink" > "$steam_runtime_path/pinned_libs_$bitness/system_$soname"
            >&2 echo "$host_library" >> "$steam_runtime_path/pinned_libs_$bitness/system_$soname"
            touch "$steam_runtime_path/pinned_libs_$bitness/has_pins"
        fi
    done

    for bitness in 32 64; do
        if [ -L "$steam_runtime_path/pinned_libs_$bitness/libcurl.so.4" ]; then
            # The version of libcurl.so.4 in the Steam Runtime is actually
            # binary-compatible with the older libcurl.so.3 in Debian/Ubuntu,
            # so pin it under both names.
            ln -fns libcurl.so.4 "$steam_runtime_path/pinned_libs_$bitness/libcurl.so.3"
        fi

        if [ -L "$steam_runtime_path/pinned_libs_$bitness/libcurl-gnutls.so.4" ]; then
            # Similarly, libcurl-gnutls.so.4 is actually binary-compatible
            # with libcurl-gnutls.so.3, so pin it under both names.
            ln -fns libcurl-gnutls.so.4 "$steam_runtime_path/pinned_libs_$bitness/libcurl-gnutls.so.3"
        fi
    done

    if [ "$zenity_progress" = true ]; then
        echo 100
    else
        echo " 100%   "
    fi
}

check_pins ()
{
    # Set separator to newline just for this function
    local IFS
    IFS=$(echo -en '\n\b')

    local host_actual_library
    local host_library
    local host_sonamesymlink
    local pins_need_redoing
    local steam_runtime_path

    # First argument is the runtime path
    steam_runtime_path=$(realpath "$1")

    if [[ ! -d "$steam_runtime_path" ]]; then return; fi

    pins_need_redoing="no"

    # If we had the runtime previously unpacked but never ran the pin code, do it now
    if [[ ! -d "$steam_runtime_path/pinned_libs_32" ]]
    then
        pins_need_redoing="yes"
    fi

    if [[ -f "$steam_runtime_path/pinned_libs_32/has_pins" || -f "$steam_runtime_path/pinned_libs_64/has_pins" ]]
    then
        for pin in "$steam_runtime_path"/pinned_libs_*/system_*
        do
            host_sonamesymlink=$(head -1 "$pin")
            host_library=$(tail -1 "$pin")

            # Follow the host SONAME symlink we saved in the first line of the pin entry
            if ! host_actual_library=$(readlink -f "$host_sonamesymlink")
            then
                pins_need_redoing="yes"
                break
            fi

            # It might not exist anymore if it got uninstalled or upgraded to a different major version
            if [[ ! -f $host_actual_library ]]
            then
                pins_need_redoing="yes"
                break
            fi

            # We should end up at the same lib we saved in the second line
            if [[ "$host_actual_library" != "$host_library" ]]
            then
                # Mismatch, it could have gotten upgraded
                pins_need_redoing="yes"
                break
            fi
        done
    fi

    if [[ $pins_need_redoing == "yes" ]]
    then
        echo Pins potentially out-of-date, rebuilding...
        # Is always set at this point, but may be empty if the host lacks zenity
        if [ -n "${STEAM_ZENITY}" ]; then
            pin_newer_runtime_libs "$steam_runtime_path" | "${STEAM_ZENITY}" --progress --auto-close --percentage=0 --no-cancel --width 400 --text="Pins potentially out-of-date, rebuilding..."
        else
            pin_newer_runtime_libs "$steam_runtime_path" "false"
        fi
    else
        echo Pins up-to-date!
    fi
}

usage ()
{
    local status="${1:-2}"

    if [ "${status}" -gt 0 ]; then
        exec >&2
    fi

    cat << EOF
Usage: $me [OPTIONS...] [ACTION]

Set up the Steam Runtime in preparation for running games or other
programs using its libraries.

Options:
--force                         Always update pinned libraries from the
                                host system, even if it does not appear
                                necessary.

Actions:
--help                          Print this help
--print-bin-path                Print the entries to prepend to PATH when
                                running in this Steam Runtime
EOF

    exit "$status"
}

main ()
{
    local me="$0"
    local top
    top="$(cd "${0%/*}"; pwd)"
    local arch
    local getopt_temp

    local action="setup"
    local opt_force=

    getopt_temp="help"
    getopt_temp="${getopt_temp},force"
    getopt_temp="${getopt_temp},print-bin-path"

    getopt_temp="$(getopt -o '' --long "$getopt_temp" -n "$me" -- "$@")"
    eval "set -- $getopt_temp"
    unset getopt_temp

    while [ "$#" -gt 0 ]
    do
        case "$1" in
            (--help)
                usage 0
                ;;

            (--force)
                opt_force=yes
                shift
                ;;

            (--print-bin-path)
                action="$1"
                shift
                ;;

            (--print-lib-paths)
                action="$1"
                shift
                ;;

            (--)
                shift
                break
                ;;

            (-*)
                echo "$me: unknown option: $1" >&2
                usage 2
                ;;

            (*)
                break
                ;;
        esac
    done

    if [ "$#" -gt 0 ]
    then
        echo "$me does not have positional parameters" >&2
        usage 2
    fi

    case "$action" in
        (--print-bin-path)
            # Keep this in sync with run.sh
            case "$(uname -m)" in
                (*64)
                    arch=amd64
                    ;;
                (*)
                    arch=i386
                    ;;
            esac
            echo "$top/$arch/bin:$top/$arch/usr/bin:$top/usr/bin"
            ;;

        (setup)
            if [ -n "$opt_force" ]
            then
                # Is always set at this point, but may be empty if the host lacks zenity
                if [ -n "${STEAM_ZENITY}" ]; then
                    pin_newer_runtime_libs "$top" | "${STEAM_ZENITY}" --progress --auto-close --percentage=0 --no-cancel --width 400 --text="Forcing rebuild of pins..."
                else
                    pin_newer_runtime_libs "$top" "false"
                fi
            else
                check_pins "$top"
            fi
            ;;
    esac
}

main "$@"

# vim:set sw=4 sts=4 et:
