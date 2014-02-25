#!/bin/bash

# Copyright (c) 2013, Ray Donnelly <mingw.android@gmail.com>

# Wrapper script for gnutar which sorts the filenames first.
# This leads to improved compression if using a large
# block-size (input-dependent of course..)

# Test with:
# pushd $HOME; UNIXHOME=$PWD; popd; $UNIXHOME/Dropbox/tar-sorted.sh -cf test.tar $UNIXHOME/Dropbox/tar-work/test-folder
# pushd $HOME; UNIXHOME=$PWD; popd; pushd $HOME/Dropbox/tar-work; $UNIXHOME/Dropbox/tar-sorted.sh -cf test.tar test-folder; popd
# Fancier (compressing i686 darwin cross compilers from ct-ng as tar.xz with max compression, output, and excluding lib/*.a):
# pushd /c/x/dx-i686-3_3; XZ_OPT=-9ev ~/Dropbox/tar-work/tar-sorted.sh -cJf i686-apple-darwin11-linux-x86.tar.xz * --exclude='lib/*.a'
# pushd $HOME; XZ_OPT=-9ev ~/Dropbox/tar-work/tar-sorted.sh -cJhf ~/Dropbox/darwin-compilers-work/MacOSX10.6.sdk.tar.xz MacOSX10.6.sdk

# Options to this scripe are prefixed by --tar-sorted- and the valid ones are
# dedupe|d
# verbose|v

DEDUPE=no
VERBOSE=no

process_tar_sorted_argument ()
{
    echo tar-sorted-arg $1=$2
    case "$1" in
        dedupe|d)
            DEDUPE=yes
            if [ ! `which fdupes` ]; then
                echo "Error: dedupe passed but couldn't find fdupes program. Please install this."
                exit 1
            fi
            ;;
        verbose|v)
            VERBOSE=yes
            ;;
    esac
}

# Tar options that take a second argument:
# From:
# tar --help | grep ", --.*\="
# -g, --listed-incremental=FILE   handle new GNU-format incremental backup
# -f, --file=ARCHIVE         use archive file or device ARCHIVE
# -F, --info-script=NAME, --new-volume-script=NAME
# -L, --tape-length=NUMBER   change tape after writing NUMBER x 1024 bytes
# -b, --blocking-factor=BLOCKS   BLOCKS x 512 bytes per record
# -H, --format=FORMAT        create archive of the given format
# -V, --label=TEXT           create archive with volume name TEXT; at
# -I, --use-compress-program=PROG
# -C, --directory=DIR        change to directory DIR
# -K, --starting-file=MEMBER-NAME
# -N, --newer=DATE-OR-FILE, --after-date=DATE-OR-FILE
# -T, --files-from=FILE      get names to extract or create from FILE
# -X, --exclude-from=FILE    exclude patterns listed in FILE
#     --transform=EXPRESSION, --xform=EXPRESSION

# Find gnu awk and gnutar.
# Prefer gnutar if it exists.
TAR=
type gtar > /dev/null 2>&1 && TAR=gtar
[ "$TAR" = "" ] && type tar > /dev/null 2>&1 && TAR=tar

if [ "$TAR" = "" ]; then
  echo "neither tar nor gtar (OSX: brew install gnu-tar) were found."
  exit 1
fi

# Prefer gawk if it exists.
AWK=
type gawk > /dev/null 2>&1 && AWK=gawk
[ "$AWK" = "" ] && type awk > /dev/null 2>&1 && AWK=awk

if [ "$AWK" = "" ]; then
  echo "neither awk nor gawk were found."
  exit 1
fi

declare -a ARGS_FILE_AND_FOLDER
declare -a ARGS_ALL_OTHERS

# --exclude adds to this:
declare -a EXCLUSION_PATTERNS

# ARGS_NEEDED is the number of arguments needed by the
# last processed option. It is always 0 or 1.
ARGS_NEEDED=0
PROBABLE_FILENAME=
EXCLUSION_FILENAME=
LATCHED_VARIABLE=
while [ "$#" -gt 0 ]; do
    while [ $ARGS_NEEDED -gt 0 ]; do
        ARGS_ALL_OTHERS[${#ARGS_ALL_OTHERS[*]}]="$1"
        eval $LATCHED_VARIABLE="$1"
        ARGS_NEEDED=$(expr $ARGS_NEEDED - 1)
        shift
    done
    case "$1" in
        --tar-sorted-*=*)
            VAR=$(echo $1 | sed "s,^--tar-sorted-\(.*\)=.*,\1,")
            VAL=$(echo $1 | sed "s,^--tar-sorted-.*=\(.*\),\1,")
            process_tar_sorted_argument "$VAR" "$VAL"
            ;;
        --tar-sorted-*)
            VAR=$(echo $1 | sed "s,^--tar-sorted-\(.*\),\1,")
            process_tar_sorted_argument "$VAR"
            ;;
        --exclude=*)
            EXCLUSION_PATTERNS[${#EXCLUSION_PATTERNS[*]}]="$(echo $1 | sed "s,^--exclude=\(.*\),\1,")"
            ;;
        --*=*)
            ARGS_ALL_OTHERS[${#ARGS_ALL_OTHERS[*]}]="$1"
            ;;
        -X)
            ARGS_NEEDED=1
            LATCHED_VARIABLE=EXCLUSION_FILENAME
            ;;
        -*[gfFLbHVICKNT]*)
            ARGS_ALL_OTHERS[${#ARGS_ALL_OTHERS[*]}]="$1"
            ARGS_NEEDED=1
            LATCHED_VARIABLE=PROBABLE_FILENAME
            ;;
        -[a-zA-Z]*)
            ARGS_ALL_OTHERS[${#ARGS_ALL_OTHERS[*]}]="$1"
            ;;
        *)
            ARGS_FILE_AND_FOLDER[${#ARGS_FILE_AND_FOLDER[*]}]="$1"
            ;;
    esac
    shift
done

if [ $ARGS_NEEDED -gt 0 ]; then
    echo "Error :: Couldn't parse tar command line, argument missing?"
    exit 1
fi

if [ "$VERBOSE" = "yes" ]; then
    echo Input file/folder arguments: ${ARGS_FILE_AND_FOLDER[*]}
    echo Input other arguments:       ${ARGS_ALL_OTHERS[*]}
    echo Input exclusion file:        ${EXCLUSION_FILENAME}
    echo Input exclusion patterns:    ${EXCLUSION_PATTERNS[*]}
fi

TMPEXCLUSION=$(mktemp tar-sorted.XXXXX)
if [ ! "${EXCLUSION_FILENAME}" = "" ]; then
    cp -f "${EXCLUSION_FILENAME}" ${TMPEXCLUSION}
fi

for PATTERN in ${EXCLUSION_PATTERNS[*]}; do
    echo $PATTERN >> ${TMPEXCLUSION}
done

declare -a ALL_FILES
for FILE_OR_FOLDER in ${ARGS_FILE_AND_FOLDER[*]}; do
    if [ -d "$FILE_OR_FOLDER" ]; then
        IFS=$'\n' NEW_FILES=($(find $FILE_OR_FOLDER \( -type f -or -type l \)))
        for NEW_FILE in ${NEW_FILES[*]}; do
            ALL_FILES[${#ALL_FILES[*]}]="$NEW_FILE"
        done
    elif [ -e "$FILE_OR_FOLDER" ]; then
        ALL_FILES[${#ALL_FILES[*]}]="$FILE_OR_FOLDER"
    fi
done
TMPFILE=$(mktemp tar-sorted.XXXXX)
for FILE in ${ALL_FILES[*]}; do
    SORTNAME=$(echo $(basename "$FILE") | $AWK '{ FS="."; n=split($0,arr); printf("%s", arr[n]); for(i = n-1; i > 0; i--) printf(".%s", arr[i]);}')
    echo $SORTNAME\:"$FILE" >> $TMPFILE
done
TMPFILE2=$(mktemp tar-sorted.XXXXX)
cat $TMPFILE | sort | $AWK 'BEGIN { FS = ":" } ; { print $2 }' > $TMPFILE2
rm -f $TMPFILE
$TAR ${ARGS_ALL_OTHERS[*]} --files-from=${TMPFILE2} -X ${TMPEXCLUSION}
if [ -f "$PROBABLE_FILENAME" ]; then
    ls -l "$PROBABLE_FILENAME"
fi
rm ${TMPFILE2} ${TMPEXCLUSION}
