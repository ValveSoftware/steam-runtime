#!/bin/bash
# Copyright 2012-2019 Valve Software
# Copyright 2019 Collabora Ltd.
#
# SPDX-License-Identifier: MIT

set -e
set -u
set -o pipefail

pin_newer_runtime_libs ()
{
    # Set separator to newline just for this function
    local IFS
    IFS=$(echo -en '\n\b')

    local steam_runtime_path

    # First argument is the runtime path
    steam_runtime_path=$(realpath "$1")

    if [[ ! -d "$steam_runtime_path" ]]; then return; fi

    # Associative array; indices are the SONAME, values are final path
    local -A host_libraries_32
    local -A host_libraries_64

    local bitness
    local final_library
    local find_output
    local h_lib_major
    local h_lib_minor
    local h_lib_third
    local host_library
    local host_soname_symlink
    local ldconfig_output
    local leftside
    local library_path_prefix
    local r_lib_major
    local r_lib_minor
    local r_lib_third
    local runtime_version_newer
    local soname
    local soname_fullpath
    local soname_symlink

    rm -rf "$steam_runtime_path/pinned_libs_32"
    rm -rf "$steam_runtime_path/pinned_libs_64"

    # First, grab the list of system libraries from ldconfig and put them in the arrays
    for ldconfig_output in $(/sbin/ldconfig -XNv 2> /dev/null)
    do
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

    mkdir "$steam_runtime_path/pinned_libs_32"
    mkdir "$steam_runtime_path/pinned_libs_64"

    for find_output in $(find "$steam_runtime_path" -type l | grep \\\.so)
    do
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
            if [ ! -z "${host_libraries_32[$soname]+isset}" ]
            then
                host_soname_symlink=${host_libraries_32[$soname]}
            fi
            bitness="32"
        elif [[ $(file -L "$final_library") == *"64-bit"* ]]
        then
            if [ ! -z "${host_libraries_64[$soname]+isset}" ]
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
            (libSDL2-2.0.so.0)
                # We know the Steam Runtime has an up-to-date SDL2.
                runtime_version_newer="forced"
                ;;

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


        if [[ $runtime_version_newer == "yes" ]]; then
            echo "Found newer runtime version for $bitness-bit $soname. Host: $h_lib_major.$h_lib_minor.$h_lib_third Runtime: $r_lib_major.$r_lib_minor.$r_lib_third"
        elif [[ $runtime_version_newer == "forced" ]]; then
            echo "Forced use of runtime version for $bitness-bit $soname. Host: $h_lib_major.$h_lib_minor.$h_lib_third Runtime: $r_lib_major.$r_lib_minor.$r_lib_third"
        fi

        if [[ $runtime_version_newer == "yes" \
              || $runtime_version_newer == "forced" ]]; then
            ln -s "$final_library" "$steam_runtime_path/pinned_libs_$bitness/$soname"
            # Keep track of the exact version name we saw on the system at pinning time to check later
            echo "$host_soname_symlink" > "$steam_runtime_path/pinned_libs_$bitness/system_$soname"
            echo "$host_library" >> "$steam_runtime_path/pinned_libs_$bitness/system_$soname"
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
        pin_newer_runtime_libs "$steam_runtime_path"
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
                pin_newer_runtime_libs "$top"
            else
                check_pins "$top"
            fi
            ;;
    esac
}

main "$@"

# vim:set sw=4 sts=4 et:
