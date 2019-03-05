#!/bin/bash
# Copyright 2019 Collabora Ltd.
#
# SPDX-License-Identifier: MIT

set -e
set -u
set -o pipefail

pin_newer_runtime_libs ()
{
    echo "TODO: update pins for $1" >&2
    exit 1
}

check_pins ()
{
    echo "TODO: check pins for $1" >&2
    exit 1
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
            echo "$top/$arch/bin:$top/$arch/usr/bin"
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
