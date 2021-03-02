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

Vulkan layers and driver/device selection
-----------------------------------------

Getting Vulkan layers from the host system to work in the container
is complicated, and is still being worked on. In recent versions of
pressure-vessel, *most* Vulkan layers should work, with some exceptions.

If a layer has a separate JSON manifest for 32-bit and 64-bit,
it might only work for 32-bit *or* 64-bit, and not both.
This is fixed in version 0.20210217.0 of both scout and soldier.
However, in some cases this fix exposes other problems with Vulkan
layers (see [above](#issue363)).

The mechanism for selecting the correct Vulkan driver and GPU on Linux
is not fully settled, and the container can interfere with this, resulting
in the wrong GPU or driver being selected, particularly on multi-GPU
systems.

([#312](https://github.com/ValveSoftware/steam-runtime/issues/312),
[#352](https://github.com/ValveSoftware/steam-runtime/issues/352);
maybe also
[#340](https://github.com/ValveSoftware/steam-runtime/issues/340),
[#341](https://github.com/ValveSoftware/steam-runtime/issues/341))

This can also affect system-wide Vulkan layers like MangoHUD and vkBasalt.

([#295](https://github.com/ValveSoftware/steam-runtime/issues/295))

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
