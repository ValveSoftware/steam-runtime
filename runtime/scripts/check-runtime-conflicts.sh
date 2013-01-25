#!/bin/sh
#
# This script checks for file conflicts between runtime architectures
#
# If this script ever returns no output, it's safe to merge the architecture
# directories into a single runtime.

# The top level of the runtime tree
TOP=$(cd "${0%/*}/.." && echo ${PWD})
cd "${TOP}"

ARCHITECTURES="i386 amd64"
OUTPUT="`mktemp`"

echo "Checking for conflicts in $ARCHITECTURES"
for arch in $ARCHITECTURES; do
    cd $arch
    for other in $ARCHITECTURES; do
        if [ "$arch" = "$other" ]; then
            continue
        fi

        find . -type f | while read file; do
            if [ -f "../$other/$file" ] && ! cmp "$file" "../$other/$file" >/dev/null; then
                echo "CONFLICT: $file" >>"$OUTPUT"
            fi
        done
    done
    cd ..
done
sort "$OUTPUT" | uniq
rm -f "$OUTPUT"
echo "Done!"
