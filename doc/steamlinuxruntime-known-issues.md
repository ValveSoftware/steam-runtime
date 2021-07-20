Common issues and workarounds
=============================

Some issues involving the SteamLinuxRuntime framework and the
pressure-vessel container-launcher are not straightforward to fix.
Here are some that are likely to affect multiple users:

Flatpak
-------

Using the Steam container runtimes from inside a Flatpak sandbox requires
features that are not yet available in stable Flatpak releases. To use
the container runtimes, you will need:

* An operating system where unprivileged users can create user
    namespaces (non-setuid bubblewrap)

    * Debian >= 11, but not Debian 10 or older
    * RHEL/CentOS >= 8, but not RHEL/CentOS 7 or older
    * Arch Linux with the default `linux` kernel,
        but not `linux-hardened` and `bubblewrap-suid`
    * Most other recent distributions, e.g. Ubuntu

* Flatpak 1.11.2. This is a development version, so use it at your own risk.

    * Ubuntu users can get this from
        [the PPA](https://launchpad.net/~alexlarsson/+archive/ubuntu/flatpak)
    * Debian users can get this from
        [experimental](https://packages.debian.org/source/experimental/flatpak)

* A fully up-to-date version of the Steam Flatpak app, with the
   `per-app-dev-shm` feature listed in its permissions

* A fully up-to-date version of `SteamLinuxRuntime_soldier`, with
    `pressure-vessel 0.20210430.0` or
    later listed in its `VERSIONS.txt` file

As a workaround, users of older versions of Flatpak can try using
[a community build of Proton](https://github.com/flathub/com.valvesoftware.Steam.CompatibilityTool.Proton)
which uses the freedesktop.org runtime instead of Steam Runtime 2.

([#294](https://github.com/ValveSoftware/steam-runtime/issues/294),
[Proton#4268](https://github.com/ValveSoftware/Proton/issues/4268),
[Proton#4283](https://github.com/ValveSoftware/Proton/issues/4283),
[com.valvesoftware.Steam#642](https://github.com/flathub/com.valvesoftware.Steam/issues/642),
[flatpak#3797](https://github.com/flatpak/flatpak/issues/3797),
[flatpak#4286](https://github.com/flatpak/flatpak/issues/4286))

Non-FHS operating systems
-------------------------

Unusual directory layouts and `ld.so` names are not supported.
The Debian/Ubuntu family, the Fedora/CentOS/Red Hat family, Arch Linux
and openSUSE are most likely to work.

Exherbo and ClearLinux did not work in the past, but recent versions of
SteamLinuxRuntime fix this. Please report any regressions. The changes
made to support these operating systems can be used as a basis to propose
patches to make it work in other "almost-FHS" environments.

NixOS has its own scripts to set up a FHS-compatible environment to
run Steam. As of early 2021, very recent versions of this should be
mostly compatible with pressure-vessel, but some system configurations
are still problematic.

Guix probably does not work for the same reasons as NixOS.

Other non-FHS distributions might also not work.

Workaround: don't enable SteamLinuxRuntime or Proton 5.13 (or newer)
on OSs with unusual directory layouts, or use the unofficial Flatpak app
(requires Flatpak 1.11.2).

kernel.unprivileged\_userns\_clone
----------------------------------

On Debian 10 or older and SteamOS, either the `bubblewrap` package
from the OS must be installed, or the `kernel.unprivileged_userns_clone`
sysctl parameter must be set to 1. Debian 11 will do this by default.

Similarly, on Arch Linux with the non-default `linux-hardened`
kernel, either the `bubblewrap-suid` package must be installed, or the
`kernel.unprivileged_userns_clone` sysctl parameter must be set to 1.

If any other distributions use the `kernel.unprivileged_userns_clone`
patch, they will have similar requirements.

Note that if you are running Steam under Flatpak, a setuid version of
`/usr/bin/bwrap` will not work: the `kernel.unprivileged_userns_clone`
sysctl parameter must be set to 1 instead.

([#342](https://github.com/ValveSoftware/steam-runtime/issues/342),
[#297](https://github.com/ValveSoftware/steam-runtime/issues/297))

<a name="issue363"></a>MangoHUD with Mesa 20.3.4 and 21.0.0.rc5
---------------------------------------------------------------

Mesa version 20.3.4, and Mesa release candidates 21.0.0.rc2 to 21.0.0.rc5
inclusive, have a problematic interaction between Mesa's device selection
layer and other Vulkan layers, causing Proton/DXVK games to crash or hang
on startup. The exact conditions to trigger this are complicated and not
well-understood, but it is known to happen on many systems when Proton/DXVK
games load the MangoHUD Vulkan layer in the Steam Linux Runtime container.

Mesa versions 21.0.0 and 20.3.5 contain a change that avoids this problem.

It is not clear which component is at fault here: it might be a bug in
Vulkan-Loader, MangoHUD, Mesa, pressure-vessel or something else. We're
continuing to investigate.

Workaround: upgrade Mesa to version 20.3.5 or later, or disable MangoHUD
with environment variable `DISABLE_MANGOHUD=1`.

([#363](https://github.com/ValveSoftware/steam-runtime/issues/363),
[#365](https://github.com/ValveSoftware/steam-runtime/issues/365))

vkBasalt with shaders in /usr/share
-----------------------------------

The vkBasalt Vulkan layer crashes if told to load shaders that cannot
be found. Configuring it to load shaders from `/usr/share` is not
compatible with the Steam Linux Runtime container, because the container
uses a different directory to provide its `/usr/share`.

Workaround: copy the required shaders into your home directory and
configure it to use them from that location, or disable vkBasalt with
environment variable `DISABLE_VKBASALT=1`.

([#381](https://github.com/ValveSoftware/steam-runtime/issues/381),
[vkBasalt#146](https://github.com/DadSchoorse/vkBasalt/issues/146))

<a name="issue312"></a> Multiple-GPU systems
--------------------------------------------

Some systems have more than one GPU, typically a slower Intel or AMD
integrated GPU built in to the CPU, and a faster NVIDIA or AMD discrete
GPU as a separate module.

The mechanism for selecting the correct Vulkan driver and GPU on Linux
is not fully settled, and the container can interfere with this, resulting
in the wrong GPU or driver being selected. This can result in the game
either running more slowly than it should, or not running successfully
at all.

On desktop systems, if you intend to use the discrete GPU for everything,
the simplest configuration is to configure the firmware (BIOS/EFI) so the
discrete GPU is used, and connect the display to the discrete GPU.

On laptops where the display is connected to the integrated GPU but a
more powerful discrete GPU is also available (NVIDIA Optimus or AMD
Switchable Graphics), the most reliable configuration seems to be to use
PRIME GPU offloading (NVIDIA Prime Render Offload for NVIDIA devices,
DRI PRIME for AMD devices).

Some systems, such as Ubuntu, provide a graphical user interface for
switching between Intel-only, NVIDIA-on-demand and NVIDIA-only modes on
NVIDIA Optimus laptops. In recent versions this is based on PRIME GPU
offloading, and the most reliable configuration seems to be to
select NVIDIA-on-demand, then use the mechanisms described below to
request that Steam and/or individual games run on the NVIDIA GPU.

Recent versions of GNOME (GNOME Shell 3.38+) and KDE Plasma Desktop
(KDE Frameworks 5.30+) have built-in support for marking applications to
be run using a specific GPU. If Steam is run like this, then most games
should also run on the same GPU, with no further action required.

Marking applications to be run using a specific GPU works by setting the
environment variables described below. If you run Steam from a terminal
for debugging or development, you will need to set those environment
variables manually.

On recent NVIDIA systems, you can request NVIDIA Prime Render Offload
for Vulkan by running either Steam or individual games with the environment
variable `__NV_PRIME_RENDER_OFFLOAD=1` set. It might also be helpful to set
`__VK_LAYER_NV_optimus=NVIDIA_only` (which specifically asks the Vulkan
layer to use only NVIDIA GPUs) and `__GLX_VENDOR_LIBRARY_NAME=nvidia`
(which does the same for OpenGL rather than Vulkan). For example,
[Arch Linux's prime-run script](https://github.com/archlinux/svntogit-packages/tree/packages/nvidia-prime/trunk)
implements this approach.

Similarly, on recent Mesa systems, you can request DRI PRIME offloading by
running Steam or individual games with the environment variable
`DRI_PRIME=1` set.

Using Bumblebee and Primus (`optirun`, `primusrun`, `pvkrun`, `primus_vk`)
adds an extra layer of complexity that does not work reliably with the
container runtime. We recommend using NVIDIA Prime Render Offload or
DRI PRIME offloading instead, if possible.

([#312](https://github.com/ValveSoftware/steam-runtime/issues/312),
[#352](https://github.com/ValveSoftware/steam-runtime/issues/352);
maybe also
[#340](https://github.com/ValveSoftware/steam-runtime/issues/340),
[#341](https://github.com/ValveSoftware/steam-runtime/issues/341))

/usr/local
----------

pressure-vessel does not support having a Steam Library below `/usr`,
including `/usr/local`. For example, `/usr/local/steam-library` will
not work.

Workaround: move the Steam Library to a different directory,
perhaps using bind-mount to make enough space available in a suitable
location.

([#288](https://github.com/ValveSoftware/steam-runtime/issues/288))

Steam Workshop outside the home directory
-----------------------------------------

If a game has Steam Workshop support and is installed outside your
home directory, it will not necessarily find the Steam Workshop content.

Workaround: Move it to your home directory, as above.

([#257](https://github.com/ValveSoftware/steam-runtime/issues/257))

Non-Steam games
---------------

Non-Steam games are not currently supported.

Workaround: don't use SteamLinuxRuntime for those games yet.

([#228](https://github.com/ValveSoftware/steam-runtime/issues/228))

Audio
-----

The recommended audio framework is PulseAudio. Pipewire emulating a
PulseAudio server should also work. Using ALSA or OSS might work, but
is not really supported. JACK is not supported, because its IPC protocol
is not compatible between different JACK versions, so there is no version
of the JACK library that would be suitable for all host OSs.

Workaround: use PulseAudio.

([#307](https://github.com/ValveSoftware/steam-runtime/issues/307),
[#344](https://github.com/ValveSoftware/steam-runtime/issues/344))

Sharing directories with the container
--------------------------------------

By default, most of the directories that might be used by a game are
shared between the real system and the container:

* your home directory
* the Steam library containing the actual game
* the directory containing Proton, if used
* the installation directory for Steam itself
* the shader cache

However, directories outside those areas are usually not shared with
the container. In particular, this affects games that ask you to browse
for a directory to be used for storage, like Microsoft Flight Simulator.

You can force them to be shared by setting the environment variable
`PRESSURE_VESSEL_FILESYSTEMS_RO` and/or `PRESSURE_VESSEL_FILESYSTEMS_RW`
to a colon-separated list of paths. Paths in
`PRESSURE_VESSEL_FILESYSTEMS_RO` are read-only and paths in
`PRESSURE_VESSEL_FILESYSTEMS_RW` are read/write.

Example:

    export PRESSURE_VESSEL_FILESYSTEMS_RO="$MANGOHUD_CONFIGFILE"
    export PRESSURE_VESSEL_FILESYSTEMS_RW="/media/ssd:/media/hdd"
    steam

Symbolic links between directories
----------------------------------

Symbolic links that cross between directories tend to cause trouble for
container frameworks. Consider using bind mounts instead, particularly
for system-level directories (outside the home directory).

If a directory that will be shared with the container is a symbolic link
to some other directory, please make sure that the target of the symbolic
link is also in a directory that is shared with the container.

When using Proton, please avoid using symbolic links to redirect part of
an emulated Windows drive to a different location. This can easily break
assumptions made by Windows games.

([#334](https://github.com/ValveSoftware/steam-runtime/issues/334))

Some directories will cause the container launcher to exit with an error
if they are symbolic links. Please report these as bugs if they have not
already been reported, but they are unlikely to be easy to fix (we already
fixed the easier cases). Workaround: use bind mounts instead.

([#291](https://github.com/ValveSoftware/steam-runtime/issues/291),
[#321](https://github.com/ValveSoftware/steam-runtime/issues/321),
[#368](https://github.com/ValveSoftware/steam-runtime/issues/368))

Common issues and workarounds specific to 'scout'
-------------------------------------------------

Using the Steam Runtime 1 `scout` runtime in a container is considered
experimental, and is not expected to work for all games. Native Linux
games that were compiled for Steam Runtime 1 `scout` are intended to be
run in the older `LD_LIBRARY_PATH`-based Steam Runtime.

### Updating "Steam Linux Runtime" compatibility tool

Due to a Steam limitation, after updating to version 0.20210630.32 or
later, it is necessary to exit from Steam completely and re-launch Steam,
so that the updated compatibility tool configuration will be loaded.
Until Steam has been restarted, trying to launch a game with the
"Steam Linux Runtime" compatibility tool will show an error message
asking for a Steam restart.

### Haxe/HashLink games

Several Haxe games don't start in the `scout` runtime,
because they assume that newer Debian/Ubuntu libraries are available.
Changes made during July 2021 might have resolved this for some or
all of these games.

Games thought to be affected include:

* Dead Cells
* Evoland Legendary Edition

([#224](https://github.com/ValveSoftware/steam-runtime/issues/224))

### various Feral Interactive games

Several Feral Interactive ports crash when launched in a 'scout' container.
Changes made during July 2021 might have resolved this for some or
all of these games.

Games thought to be affected include:

* Dirt 4
* Life is Strange 2
* Shadow of the Tomb Raider

([#202](https://github.com/ValveSoftware/steam-runtime/issues/202),
[#249](https://github.com/ValveSoftware/steam-runtime/issues/249))

Reporting other issues
----------------------

Please report other issues you encounter to
<https://github.com/ValveSoftware/steam-runtime/>, making sure to include
the information described in the
[bug reporting guide](reporting-steamlinuxruntime-bugs.md).
