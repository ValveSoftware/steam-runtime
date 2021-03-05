Common issues and workarounds
=============================

Some issues involving the SteamLinuxRuntime framework and the
pressure-vessel container-launcher are not straightforward to fix.
Here are some that are likely to affect multiple users:

Flatpak
-------

SteamLinuxRuntime cannot be used from inside the unofficial Flatpak
version of Steam. We are trying to make this work, but it is going
to need changes to both pressure-vessel and Flatpak.
Workaround: Either don't use the Flatpak version of Steam, or if you
do, don't enable SteamLinuxRuntime or the official builds of
Proton 5.13 (or later).

There is an unsupported community build of Proton 5.13 available that
*does* work in a Flatpak environment.

([#294](https://github.com/ValveSoftware/steam-runtime/issues/294))

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
on OSs with unusual directory layouts.

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

Mesa versions 20.3.5, 21.0.0 and 21.1.0 are expected to contain a change
that avoids this problem, and some Linux distributions such as Arch Linux
have already backported the necessary patch into their packages for older
Mesa releases.

It is not clear which component is at fault here: it might be a bug in
Vulkan-Loader, MangoHUD, Mesa, pressure-vessel or something else. We're
continuing to investigate.

Workaround: disable MangoHUD with environment variable `DISABLE_MANGOHUD=1`.

([#363](https://github.com/ValveSoftware/steam-runtime/issues/363),
[#365](https://github.com/ValveSoftware/steam-runtime/issues/365))

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

Vulkan layers and driver/device selection
-----------------------------------------

Getting Vulkan layers from the host system to work in the container
is complicated, and is still being worked on. In recent versions of
pressure-vessel, *most* Vulkan layers should work, with some exceptions.

This can affect the selection of driver/GPU in multi-GPU systems
(see [Multiple-GPU systems](#issue312)).

This can also affect system-wide Vulkan layers like MangoHUD and vkBasalt.
([#295](https://github.com/ValveSoftware/steam-runtime/issues/295))

Some layers will only work inside the container for 32-bit games *or*
for 64-bit games, and not both on the same system.
This is believed to be fixed in version 0.20210217.0 of both scout and soldier.
However, in some cases this fix exposes other problems with Vulkan
layers, such as [MangoHUD with Mesa 20.3.4 and 21.0.0.rc5](#issue363).

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

Native Wayland graphics are not currently supported in `scout`
(they can work in `soldier`).

Workaround:
Have Xwayland running (or use an environment like GNOME that does this
automatically), and don't set `SDL_VIDEODRIVER`, so that SDL will default
to using X11 via Xwayland.

([#232](https://github.com/ValveSoftware/steam-runtime/issues/232))

Game Maker games such as Undertale and Danger Gazers don't start
in the `scout` runtime,
because they assume that newer Debian/Ubuntu libraries are available.

Workaround: don't use SteamLinuxRuntime for those games yet.

([#216](https://github.com/ValveSoftware/steam-runtime/issues/216),
[#235](https://github.com/ValveSoftware/steam-runtime/issues/235))

Haxe games such as Evoland Legendary Edition don't start in the
`scout` runtime,
because they assume that newer Debian/Ubuntu libraries are available.

Workaround: don't use SteamLinuxRuntime for those games yet.

([#224](https://github.com/ValveSoftware/steam-runtime/issues/224))

Feral Interactive ports such as Shadow of the Tomb Raider and Dirt 4
crash when launched in a 'scout' container.

Workaround: don't use SteamLinuxRuntime for those games yet.

([#202](https://github.com/ValveSoftware/steam-runtime/issues/202),
[#249](https://github.com/ValveSoftware/steam-runtime/issues/249))

Reporting other issues
----------------------

Please report other issues you encounter to
<https://github.com/ValveSoftware/steam-runtime/>, making sure to include
the information described in the
[bug reporting guide](reporting-steamlinuxruntime-bugs.md).
