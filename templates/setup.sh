#!/bin/bash
# Copyright 2012-2019 Valve Software
# Copyright 2019-2021 Collabora Ltd.
#
# SPDX-License-Identifier: MIT

set -e
set -u
set -o pipefail

identify_library_abi=
libcurl_compat_setup=

# Check if set, which is normally done by steam.sh, but will not be set when invoked directly
if [ -z "${STEAM_ZENITY+x}" ]; then
    # We are likely outside of run.sh as well, only use the host zenity
    STEAM_ZENITY="$(command -v zenity || true)"
    export STEAM_ZENITY
fi

# If steam.sh or run.sh doesn't find a system zenity, it sets
# STEAM_ZENITY=zenity, meaning do a PATH search and hope to find the one
# from the Steam Runtime. However, in this script we don't expect the
# Steam Runtime search paths to be available yet, so double-check: we
# might find that no zenity is available.
if ! [ -x "$(command -v "${STEAM_ZENITY}" || true)" ]; then
    STEAM_ZENITY=
fi

log () {
    echo "setup.sh[$$]: $*" >&2 || :
}

debug ()
{
    if [ -n "${STEAM_RUNTIME_VERBOSE-}" ]; then
        log "$@"
    fi
}

progress ()
{
    local percent="$1"
    local zenity_progress="$2"

    # Suppress "broken pipe" error message if any, and fall back to
    # TUI progress reporting on stderr.
    if [ "$zenity_progress" = true ] && echo "$percent" 2>/dev/null; then
        return 0
    elif [ "$percent" = 100 ]; then
        echo " 100%   " >&2 || :
    else
        printf '\r %d%%    \r' "$percent" >&2 || :
    fi
}

pin_newer_runtime_libs ()
{
    # Set separator to newline just for this function
    local IFS
    IFS=$(echo -en '\n\b')

    local steam_runtime_path
    local zenity_progress=true

    # First argument is the runtime path
    steam_runtime_path=$(readlink -f "$1")

    if [[ ! -d "$steam_runtime_path" ]]; then return; fi

    # Second optional argument is the zenity print progress flag
    if [[ "$#" -gt 1 ]]; then
        zenity_progress=$2
    fi

    if [ "$zenity_progress" = true ]; then
        # Don't get killed by SIGPIPE if zenity has crashed or otherwise
        # failed
        trap '' PIPE || :
    fi

    # Associative array; indices are the SONAME, values are final path
    local -A host_libraries_32
    local -A host_libraries_64

    local bitness
    local soname_details
    local final_library
    local find_num
    local line
    local output_array
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

    rm -rf "$steam_runtime_path/libcurl_compat_32"
    rm -rf "$steam_runtime_path/libcurl_compat_64"
    rm -rf "$steam_runtime_path/pinned_libs_32"
    rm -rf "$steam_runtime_path/pinned_libs_64"

    # By roughly timing the average execution time we divided the progress in three parts:
    # The setup, 4% of the total
    # The ldconfig, 60% of the total
    # The pinning, 35% of the total
    # And at the end we just print 100%
    progress 4 "$zenity_progress"

    if [[ -n "$identify_library_abi" ]]; then
        local executable_output_array
        local line
        local soname_path
        local abi

        # This usually takes only a few dozen milliseconds, there is no need
        # to update the progress bar
        mapfile -t executable_output_array < <($identify_library_abi --ldconfig --skip-unversioned 2>/dev/null)

        for line in "${executable_output_array[@]}"
        do
            soname_path=${line%=*}
            soname=${soname_path##*/}
            abi=${line#*=}

            if [[ ${abi} == "i386-linux-gnu" ]]; then
                if [[ -n "${host_libraries_32[$soname]+isset}" ]]; then
                    debug "Ignoring $soname_path because ${host_libraries_32[$soname]} is higher-precedence"
                else
                    host_libraries_32[$soname]=$soname_path
                fi
            elif [[ ${abi} == "x86_64-linux-gnu" ]]; then
                if [[ -n "${host_libraries_64[$soname]+isset}" ]]; then
                    debug "Ignoring $soname_path because ${host_libraries_64[$soname]} is higher-precedence"
                else
                    host_libraries_64[$soname]=$soname_path
                fi
            fi
            # If it's not i386-linux-gnu nor x86_64-linux-gnu we just skip it
        done
    else
        # Fallback to the older, and slower, method that uses `file -L`

        # First, grab the list of system libraries from ldconfig and put them in the arrays
        shopt -s lastpipe
        if /sbin/ldconfig -XNv 2> /dev/null | mapfile -t ldconfig_output_array; then
            true  # OK
        else
            log "Warning: An unexpected error occurred while executing \"/sbin/ldconfig -XNv\", the exit status was $?"
        fi

        ldconfig_num=${#ldconfig_output_array[@]}
        n_done=0

        for ldconfig_output in "${ldconfig_output_array[@]}"
        do
            progress $(( ( 60 * n_done ) / ldconfig_num + 4 )) "$zenity_progress"
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

                soname_details=$(file -L "$final_library")

                # Save into bitness-specific associative array with only SONAME as left-hand
                if [[ $soname_details == *"32-bit"* ]]
                then
                    if [[ -n "${host_libraries_32[$soname]+isset}" ]]; then
                        debug "Ignoring $soname_fullpath because ${host_libraries_32[$soname]} is higher-precedence"
                    else
                        host_libraries_32[$soname]=$soname_fullpath
                    fi
                elif [[ $soname_details == *"64-bit"* ]]
                then
                    if [[ -n "${host_libraries_64[$soname]+isset}" ]]; then
                        debug "Ignoring $soname_fullpath because ${host_libraries_64[$soname]} is higher-precedence"
                    else
                        host_libraries_64[$soname]=$soname_fullpath
                    fi
                fi
            fi
        done
    fi

    progress 64 "$zenity_progress"

    mkdir "$steam_runtime_path/pinned_libs_32"
    mkdir "$steam_runtime_path/pinned_libs_64"

    # Give steamrt a chance to fix libcurl ABI conflicts in a cleverer way.
    # This will only work for glibc >= 2.30, but if it does work, it will
    # create a libcurl_compat_${bitness}/libcurl.so.4 that is better than
    # anything we can do from this shell script. This relies on tricky
    # implementation details of glibc, so we're not using it by default yet
    # (see run.sh for the opt-in mechanism).
    if [[ -x "$libcurl_compat_setup" ]] && "$libcurl_compat_setup" --runtime-optional "$steam_runtime_path"; then
        debug "run.sh can optionally use shim library to support more than one libcurl ABI"
    fi

    if [[ -n "$identify_library_abi" ]]; then
        mapfile -t output_array < <($identify_library_abi --directory "$steam_runtime_path" --skip-unversioned  2>/dev/null)
    else
        mapfile -t output_array < <(find "$steam_runtime_path" -type l | grep \\\.so)
    fi

    find_num=${#output_array[@]}
    n_done=0

    for line in "${output_array[@]}"
    do
        case "$line" in
            (*/*-linux-gnu/sse2/lib* | */*-linux-gnu/sse/lib* | */*-linux-gnu/i686/cmov/lib*)
                debug "Library in hwcap directory: $line"
                ;;
            (*/*-linux-gnu/lib*)
                debug "Library in base directory: $line"
                ;;
            (*)
                debug "Skip library in subdirectory: $line"
                continue
                ;;
        esac

        progress $(( ( 35 * n_done ) / find_num + 64 )) "$zenity_progress"
        (( n_done=n_done+1 ))

        if [[ -n "$identify_library_abi" ]]; then
            soname_symlink=${line%=*}
            soname_details=${line#*=}
        else
            soname_symlink=$line
            soname_details=
        fi

        # Left-hand side of soname symlink should be *.so.%d
        if [[ ! $soname_symlink =~ .*\.so.[[:digit:]]+$ ]]; then continue; fi

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

        soname=${soname_symlink##*/}

        if [[ -z $soname_details ]]; then
            soname_details=$(file -L "$final_library")
        fi

        if [[ $soname_details == *"32-bit"* || $soname_details == "i386-linux-gnu" ]]
        then
            if [ -n "${host_libraries_32[$soname]+isset}" ]
            then
                host_soname_symlink=${host_libraries_32[$soname]}
            fi
            bitness="32"
        elif [[ $soname_details == *"64-bit"* || $soname_details == "x86_64-linux-gnu" ]]
        then
            if [ -n "${host_libraries_64[$soname]+isset}" ]
            then
                host_soname_symlink=${host_libraries_64[$soname]}
            fi
            bitness="64"
        fi

        if [[ $bitness == "unknown" ]]; then continue; fi

        runtime_version_newer="no"

        case "$soname" in
            (libdbusmenu-glib.so.4 | libdbusmenu-gtk.so.4)
                # These two libraries are built from the same source package
                # and assume that the other library is a matching version.
                # If the host system has a newer 32-bit libdbusmenu-glib.so.4
                # but does not have 32-bit libdbusmenu-gtk.so.4, then our
                # usual pinning logic would result in using the new
                # ldm-glib with the old ldm-gtk, a version mismatch with
                # the symptom of breaking the menu that should appear when
                # you right-click the Steam tray icon. Avoid this mismatch
                # by always using the Steam Runtime's copy for the 32-bit
                # Steam executable.
                # https://github.com/ValveSoftware/steam-for-linux/issues/4795
                if [ "$bitness" = 32 ]; then
                    runtime_version_newer="forced"
                fi
                ;;

            (libgtk-x11-2.0.so.0)
                # This seems to be tied up with #4795 as well.
                # Potentially related:
                # https://github.com/ValveSoftware/steam-for-linux/issues/8577
                # https://github.com/ValveSoftware/steam-for-linux/issues/9324
                if [ "$bitness" = 32 ]; then
                    runtime_version_newer="forced"
                fi
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
                #
                # (If steamrt-libcurl-compat already fixed this for us, then
                # it will have created the libcurl.so.4 symlink and as a
                # result we'll never get here.)
                runtime_version_newer="forced"
                ;;

            (libcurl-gnutls.so.4)
                # Similar to the above, the GNUTLS variant of libcurl has
                # Debian-specific symbol-versioning. We didn't have a
                # problem with this until recently, because most OSs either
                # don't ship a GNUTLS variant at all (Red Hat), ship it
                # without versioned symbols (Arch), or are Debian-derived
                # (Debian/Ubuntu), but apparently OpenMandriva has a
                # non-Debian-compatible GNUTLS variant.
                runtime_version_newer="forced"
                ;;
        esac

        # If the library is one of the ones we force, we need to
        # do that even if we are not aware of an equivalent on the host
        # system, because continuing uncertainty about the ABIs of these
        # libraries means that it might have an unexpected SONAME.
        # For instance, some versions of OpenMandriva's lib64curl-gnutls4
        # contained a libcurl-gnutls.so.4 with SONAME libcurl.so.4.
        if [ "$runtime_version_newer" = forced ]; then
            log "Forced use of runtime version for $bitness-bit $soname"
            ln -fns "$final_library" "$steam_runtime_path/pinned_libs_$bitness/$soname"
            # For similar historical reasons, our libcurl*.so.3 are equivalent
            # to libcurl*.so.4
            case "$soname" in
                (libcurl*.so.4)
                    ln -fns "$final_library" "$steam_runtime_path/pinned_libs_$bitness/${soname%.4}.3"
                    ;;
            esac
            continue
        fi

        # Do we have a host library found for the same SONAME?
        if [[ ! -f $host_soname_symlink ]]; then continue; fi

        host_library=$(readlink -f "$host_soname_symlink")

        if [[ ! -f $host_library ]]; then continue; fi

        #log $soname ${host_libraries[$soname]} $r_lib_major $r_lib_minor $r_lib_third

        if [[ "$soname" = "libcrypt.so.1" \
              && $host_library =~ libcrypt-2\.[[:digit:]]+\.so \
              && $final_library =~ libcrypt\.so\.1\.* ]]
        then
            # Steam Runtime libxcrypt libcrypt.so.1 counts as newer than
            # host glibc libcrypt.so.1, so behave as though the host version
            # was arbitrarily old
            debug "Treating libxcrypt libcrypt.so.1 as newer than host glibc version"
            h_lib_major=0
            h_lib_minor=0
            h_lib_third=0
        elif [[ $host_library =~ .*\.so.([[:digit:]]+).([[:digit:]]+).([[:digit:]]+)$ ]]; then
            h_lib_major=$((10#${BASH_REMATCH[1]}))
            h_lib_minor=$((10#${BASH_REMATCH[2]}))
            h_lib_third=$((10#${BASH_REMATCH[3]}))
        else
            continue
        fi

        if [[ $h_lib_major -lt $r_lib_major ]]; then
            runtime_version_newer="yes"
        fi

        if [[ $h_lib_major -eq $r_lib_major && $h_lib_minor -lt $r_lib_minor ]]; then
            runtime_version_newer="yes"
        fi

        if [[ $h_lib_major -eq $r_lib_major && $h_lib_minor -eq $r_lib_minor && $h_lib_third -lt $r_lib_third ]]; then
            runtime_version_newer="yes"
        fi

        if [[ "$soname" == libudev.so.0 && "$h_lib_major.$h_lib_minor.$h_lib_third" == 0.0.9999 ]]; then
            # Work around https://github.com/archlinux/libudev0-shim/issues/4
            debug "Treating libudev0-shim as newer than runtime version"
            runtime_version_newer="no"
        fi

        # Print to stderr because zenity is consuming stdout
        if [[ $runtime_version_newer == "yes" ]]; then
            log "Found newer runtime version for $bitness-bit $soname. Host: $h_lib_major.$h_lib_minor.$h_lib_third Runtime: $r_lib_major.$r_lib_minor.$r_lib_third"
            ln -fns "$final_library" "$steam_runtime_path/pinned_libs_$bitness/$soname"
            # Keep track of the exact version name we saw on the system at pinning time to check later
            >&2 echo "$host_soname_symlink" > "$steam_runtime_path/pinned_libs_$bitness/system_$soname"
            >&2 echo "$host_library" >> "$steam_runtime_path/pinned_libs_$bitness/system_$soname"
            touch "$steam_runtime_path/pinned_libs_$bitness/has_pins"
        fi
    done

    for bitness in 32 64; do
        touch "$steam_runtime_path/pinned_libs_$bitness/done"
    done

    progress 100 "$zenity_progress"
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
    steam_runtime_path=$(readlink -f "$1")

    if [[ ! -d "$steam_runtime_path" ]]; then return; fi

    pins_need_redoing="no"

    # If we had the runtime previously unpacked but never ran the pin code,
    # or if a previous attempt failed or was cancelled, do it now
    if ! [[ -e "$steam_runtime_path/pinned_libs_32/done" && -e "$steam_runtime_path/pinned_libs_64/done" ]]
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
        log "Updating Steam runtime environment..."
        # Is always set at this point, but may be empty if the host lacks zenity
        if [ -n "${STEAM_ZENITY}" ]; then
            pin_newer_runtime_libs "$steam_runtime_path" | "${STEAM_ZENITY}" --progress --auto-close --percentage=0 --no-cancel --width 400 --title="Steam setup" --text="Updating Steam runtime environment..."
        else
            pin_newer_runtime_libs "$steam_runtime_path" "false"
        fi
    else
        log "Steam runtime environment up-to-date!"
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
                log "unknown option: $1"
                usage 2
                ;;

            (*)
                break
                ;;
        esac
    done

    if [ "$#" -gt 0 ]
    then
        log "$me does not have positional parameters"
        usage 2
    fi

    case "$(uname -m)" in
        (*64)
            arch=amd64
            ;;
        (*)
            arch=i386
            ;;
    esac

    identify_library_abi="$top/$arch/usr/bin/steam-runtime-identify-library-abi"
    libcurl_compat_setup="$top/$arch/usr/bin/steam-runtime-libcurl-compat-setup"

    if [[ ! -x "$identify_library_abi" ]]; then
        identify_library_abi="$top/$arch/bin/steam-runtime-identify-library-abi"
        if [[ ! -x "$identify_library_abi" ]]; then
            identify_library_abi=
        fi
    fi

    case "$action" in
        (--print-bin-path)
            # Keep this in sync with run.sh
            echo "$top/$arch/bin:$top/$arch/usr/bin:$top/usr/bin"
            ;;

        (setup)
            if [ -n "$opt_force" ]
            then
                # Is always set at this point, but may be empty if the host lacks zenity
                if [ -n "${STEAM_ZENITY}" ]; then
                    pin_newer_runtime_libs "$top" | "${STEAM_ZENITY}" --progress --auto-close --percentage=0 --no-cancel --width 400 --title="Steam setup" --text="Reconfiguring Steam runtime environment..."
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
