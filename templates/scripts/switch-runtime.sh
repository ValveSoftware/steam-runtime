#!/bin/bash

# Copyright © 2021 Collabora Ltd.
#
# SPDX-License-Identifier: MIT
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be included
# in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
# IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
# CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
# TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
# SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

set -e
set -o pipefail
set -u
shopt -s nullglob

me="$(readlink -f "$0")"
here="${me%/*}"
me="${me##*/}"

log () {
    echo "${me}[$$]: $*" >&2 || :
}

undo_steamrt () {
    # Undo the Steam Runtime environment, but only if it's already in use.
    case "${STEAM_RUNTIME-}" in
        (/*)
            ;;
        (*)
            return
            ;;
    esac

    local default_path="/usr/local/sbin:/usr/sbin:/sbin:/usr/local/bin:/usr/bin:/bin:/usr/local/games:/usr/games"
    unset LD_LIBRARY_PATH

    # Try not to fall back to the default_path if we don't have to
    case ":$PATH:" in
        (*:$STEAM_RUNTIME*)
            export PATH="$default_path"
            ;;
    esac

    case "$STEAM_ZENITY" in
        ($STEAM_RUNTIME/*)
            unset STEAM_ZENITY
            ;;
    esac

    unset STEAM_RUNTIME

    if [ -n "${SYSTEM_LD_LIBRARY_PATH+set}" ]; then
        export LD_LIBRARY_PATH="$SYSTEM_LD_LIBRARY_PATH"
    fi

    if [ -n "${SYSTEM_PATH+set}" ]; then
        export PATH="$SYSTEM_PATH"
    fi

    # Removing the Steam Runtime from the PATH might have eliminated our
    # ability to run zenity via PATH search, if the host system doesn't
    # have it
    if [ "${STEAM_ZENITY-}" = zenity ] && ! command -v zenity >/dev/null; then
        unset STEAM_ZENITY
    fi
}

# see sysexits.h
EX_SOFTWARE () {
    exit 70
}
EX_USAGE () {
    exit 64
}

bootstrap () {
    local unpack_dir="$1"
    local steamrt="$2"

    case "$steamrt" in
        (.)
            log "--runtime with --unpack-dir must not start with a dot"
            EX_USAGE
            ;;

        ("")
            log "--runtime with --unpack-dir must be non-empty"
            EX_USAGE
            ;;

        (*/*)
            log "--runtime with --unpack-dir must be a single path component"
            EX_USAGE
            ;;
    esac

    # :? to make sure we error out if unpack_dir is somehow empty
    local tarball="${unpack_dir:?}/$steamrt.tar.xz"
    local reference="${unpack_dir:?}/$steamrt.tar.xz.checksum"
    local available="${unpack_dir:?}/$steamrt/checksum"
    local tmpdir="${unpack_dir:?}/$steamrt.new"

    if [ -e "$available" ] && cmp -s "$reference" "$available"; then
        # Runtime is unpacked and up to date, use it as-is
        "${unpack_dir:?}/$steamrt/setup.sh" >&2
        return 0
    fi

    # Compare strings instead of using md5sum -c, because older versions
    # of md5sum interpret a CRLF (DOS) line-ending as though the filename
    # to be checked was "steam-runtime.tar.xz\r"
    local expected actual
    expected="$(cat "$reference")"
    expected="${expected%% *}"
    actual="$(md5sum "$tarball")"
    actual="${actual%% *}"

    if [ "$expected" != "$actual" ]; then
        log "error: integrity check for $tarball failed"
        EX_SOFTWARE
    fi

    rm -fr "$tmpdir"
    mkdir "$tmpdir"
    # No progress bar here yet... we just assume the runtime is not too big
    tar -C "$tmpdir" -xf "$tarball"
    cp "$reference" "$tmpdir/$steamrt/checksum"
    rm -f "$available"
    rm -fr "${unpack_dir:?}/$steamrt"
    mv "${tmpdir:?}/$steamrt" "$unpack_dir"
    rmdir "$tmpdir"

    if ! cmp -s "$0" "${unpack_dir:?}/$steamrt/scripts/switch-runtime.sh"; then
        log "WARNING: $0 is out of sync. Update from $steamrt/scripts/switch-runtime.sh"
    fi

    "${unpack_dir:?}/$steamrt/setup.sh" --force >&2
}

usage () {
    local status="${1:-64}"     # EX_USAGE by default

    if [ "${status}" -gt 0 ]; then
        exec >&2
    fi

    cat << EOF
Usage: $me [OPTIONS...] [--] COMMAND [ARGUMENTS]

Set up the LD_LIBRARY_PATH-based Steam Runtime and run COMMAND in it.

Options:
--runtime=RUNTIME                       Name or path of a runtime.
                                        If not an absolute path, taken to be
                                        relative to DIRECTORY if given, or
                                        relative to $me.
                                        [default: "steam-runtime"]
--unpack-dir=DIRECTORY                  Unpack DIRECTORY/RUNTIME.tar.xz
                                        into DIRECTORY/RUNTIME if
                                        necessary, then use it. RUNTIME
                                        must be a single path component
                                        in this case.
EOF
    exit "$status"
}

main () {
    local getopt_temp="help"
    local runtime=steam-runtime
    local unpack_dir=

    getopt_temp="$getopt_temp,runtime:"
    getopt_temp="$getopt_temp,unpack-dir:"
    getopt_temp="$(getopt -o '' --long "$getopt_temp" -n "$me" -- "$@")"
    eval "set -- $getopt_temp"
    unset getopt_temp

    while [ "$#" -gt 0 ]
    do
        case "$1" in
            (--help)
                usage 0
                ;;

            (--runtime)
                runtime="$2"
                shift 2
                ;;

            (--unpack-dir)
                if ! [ -d "$2" ]; then
                    log "'$2' is not a directory"
                    usage
                fi
                unpack_dir="$(readlink -f "$2")"
                shift 2
                ;;

            (--)
                shift
                break
                ;;

            (-*)
                log "unknown option: $1"
                usage
                ;;

            (*)
                break
                ;;
        esac
    done

    if [ "$#" -lt 1 ]
    then
        log "this script requires positional parameters"
        usage
    fi

    if [ -n "$unpack_dir" ]; then
        bootstrap "$unpack_dir" "$runtime"
        STEAM_RUNTIME="$unpack_dir/$runtime"
    else
        case "$runtime" in
            ("")
                exec "$@"
                # not reached
                ;;

            (/*)
                STEAM_RUNTIME="$runtime"
                ;;
            (*)
                STEAM_RUNTIME="$here/$runtime"
                ;;
        esac
    fi

    exec "$STEAM_RUNTIME/run.sh" "$@"
}

undo_steamrt
main "$@"

# vim:set sw=4 sts=4 et:
