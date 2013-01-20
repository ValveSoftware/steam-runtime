#!/bin/sh
#
# Create a chroot build environment and run commands in it

# Set up useful variables
distribution=precise # Codename for Ubuntu 12.04 LTS
actions=""
host_arch=$(dpkg --print-architecture)

# Get to the script directory
CWD="$(pwd)"
cd "$(dirname "$0")/buildroot" || exit 2

exit_usage()
{
    echo "Usage: $0 [--create|--update|--shell|--unmount|--clean] [--arch=<arch>] [command] [arguments...]" >&2
    exit 1
}

while [ "$1" ]; do
    case "$1" in
    --create|--update|--shell|--unmount|--clean)
        actions="$actions $1"
        ;;
    --arch=*)
        arch=$(expr "$1" : '[^=]*=\(.*\)')
        case "$arch" in
        i386|amd64)
            ;;
        *)
            echo "Unsupported architecture: $arch, valid values are i386, amd64" >&2
            exit 1
            ;;
        esac
        ;;
    -h|--help)
        exit_usage
        ;;
    -*)
        echo "Unknown command line parameter: $1" >&2
        exit_usage
        ;;
    *)
        break
        ;;
    esac

    shift
done
if [ -z "$arch" ]; then
    arch=$host_arch
fi
if [ -z "$actions" ]; then
    actions="--shell"
fi

# Set our root directory (but don't create it yet)
root=$arch
mkdir -p "$root"


check_create()
{
    if check_shell; then
        if [ ! -f "pbuilder/$distribution-$arch-base.tgz" ]; then
            echo "Missing pbuilder/$distribution-$arch-base.tgz, creating..."
            sleep 1
            return 0
        fi

        if [ ! -d "$root" ]; then
            echo "Missing $root, creating..."
            sleep 1
            return 0
        fi
    fi

    if [ "$actions" ]; then
        case "$actions" in
        *--create*)
            return 0;;
        *)
            return 1;;
        esac
    fi

    # Default to not create unless we need to
    return 1
}

action_create()
{
    # Create the initial bootstrap
    bootstrap_archive=pbuilder/$distribution-$arch-base.tgz
    if [ ! -f $bootstrap_archive ]; then
        if [ "$arch" = "$host_arch" ]; then
            pbuilder_archive="$distribution-base.tgz" 
        else
            pbuilder_archive="$distribution-$arch-base.tgz" 
        fi
        if [ ! -f $HOME/pbuilder/$pbuilder_archive ]; then
            pbuilder-dist $distribution $arch create
        fi
        mkdir -p pbuilder
        cp $HOME/pbuilder/$pbuilder_archive $bootstrap_archive || exit 2
    fi

    # Create our chroot directory
    rm -rf "$root"
    mkdir -p "$root"

    # Unpack it into our chroot directory
    tar xf $bootstrap_archive --exclude=dev -C "$root"
    mkdir "$root/dev"
}

extra_mounts()
{
    if [ -f mounts ]; then
        grep '^/' mounts
    fi
}

mount_chroot()
{
    sudo mount -o bind /dev "$root/dev"
    sudo mount -o bind /dev/pts "$root/dev/pts"
    sudo mount -o bind /sys "$root/sys"
    sudo mount -o bind /proc "$root/proc"
    sudo mount -o bind /home "$root/home"

    extra_mounts | while read dir; do
        echo "Mounting $dir"
        mkdir -p "$root/$dir"
        sudo mount -o bind "$dir" "$root/$dir"
    done
}

unmount_chroot()
{
    if ! sudo -nv 2>/dev/null; then
        echo "Please enter your password to unmount chroot environment"
    fi

    sudo umount "$root/dev/pts"
    sudo umount "$root/sys"
    sudo umount "$root/proc"
    sudo umount "$root/home"
    sudo umount "$root/dev"

    extra_mounts | while read dir; do
        sudo umount "$root/$dir"
    done
}

unmount_exit()
{
    unmount_chroot
    exit 2
}

check_update()
{
    if [ "$actions" ]; then
        case "$actions" in
        *--update*)
            return 0;;
        *)
            return 1;;
        esac
    fi

    # Default to always update
    return 0
}

action_update()
{
    # Copy in initial content
    for file in /etc/passwd /etc/group; do
        cp -av "$file" "$root/$file"
    done
    cp -av content/* "$root/"

    # Add sources for apt-get
    APT_SOURCES="${root}/etc/apt/sources.list"
    if grep proposed "${APT_SOURCES}" >/dev/null; then
        grep -v proposed "${APT_SOURCES}" >"${APT_SOURCES}.new"
        mv "${APT_SOURCES}.new" "${APT_SOURCES}"
    fi
    if ! grep '^deb-src ' "${APT_SOURCES}"; then
        grep '^deb ' "${APT_SOURCES}" | sed 's,^deb ,deb-src ,' >>"${APT_SOURCES}"
    fi

    # If sudo doesn't exist, we'll emulate it with fakeroot
    # This is because we don't want the chroot environment to require root
    # permissions for anything, in case normal users want to use it.
    if [ ! -e "$root/usr/bin/sudo" ]; then
        ln -s fakeroot "$root/usr/bin/sudo"
    fi

    # Run the update script in the chroot environment
    trap unmount_exit INT TERM
    mount_chroot
    sudo chroot --userspec="$(id -u):$(id -g)" "$root" /packages/update.sh
    unmount_chroot
    trap '' INT TERM
}

check_unmount()
{
    if [ "$actions" ]; then
        case "$actions" in
        *--unmount*)
            return 0;;
        *)
            return 1;;
        esac
    fi

    # Default not to unmount everything
    return 1
}

action_unmount()
{
    unmount_chroot
}

check_shell()
{
    if [ "$actions" ]; then
        case "$actions" in
        *--shell*)
            return 0;;
        *)
            return 1;;
        esac
    fi

    # Default not to run the shell
    return 1
}

action_shell()
{
    if [ "$*" = "" ]; then
        COMMAND="$SHELL -i"
    else
        COMMAND="$*"
    fi

    cat >"$root/shell.sh" <<__EOF__
#!/bin/sh

# This adds the word "buildroot" to the bash prompt
debian_chroot=buildroot-$arch
export debian_chroot

# Try to go the the current directory
path="$CWD"
if [ -d "\$path" ]; then
    cd "\$path"
fi

# Run the shell!
$COMMAND
__EOF__
    chmod 755 "$root/shell.sh"

    # Run a shell in the chroot environment
    mount_chroot
    sudo chroot --userspec="$(id -u):$(id -g)" "$root" /shell.sh
    unmount_chroot
}

check_clean()
{
    if [ "$actions" ]; then
        case "$actions" in
        *--clean*)
            return 0;;
        *)
            return 1;;
        esac
    fi

    # Default not to clean the directories
    return 1
}

action_clean()
{
    echo "Removing build root directories"
    rm -rf amd64 i386 pbuilder
}

if check_create; then
    action_create
    action_update
fi
if check_update; then
    action_update
fi
if check_unmount; then
    action_unmount
fi
if check_shell; then
    action_shell $*
fi
if check_clean; then
    action_clean
fi

# vi: ts=4 sw=4 expandtab
