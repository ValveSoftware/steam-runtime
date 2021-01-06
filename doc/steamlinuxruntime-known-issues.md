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
Exherbo and NixOS are known not to work at the moment.
Other non-FHS distributions might also not work.

Workaround: don't enable SteamLinuxRuntime or Proton 5.13 (or newer)
on OSs with unusual directory layouts.

([#230](https://github.com/ValveSoftware/steam-runtime/issues/230))

kernel.unprivileged\_userns\_clone
----------------------------------

On Debian 10 or older and SteamOS, either the `bubblewrap` package
from the OS must be installed, or the `kernel.unprivileged_userns_clone`
sysctl parameter must be set to 1. Similarly, on Arch Linux with the
non-default `linux-hardened` kernel, either the `bubblewrap-suid`
package must be installed, or the `kernel.unprivileged_userns_clone`
sysctl parameter must be set to 1. If any other distributions use the
`kernel.unprivileged_userns_clone` patch, they will have similar
requirements.

([#342](https://github.com/ValveSoftware/steam-runtime/issues/342),
[#297](https://github.com/ValveSoftware/steam-runtime/issues/297))

Vulkan layers and driver/device selection
-----------------------------------------

Getting Vulkan layers from the host system to work in the container
is complicated, and is still being worked on. In recent versions of
pressure-vessel, *most* Vulkan layers should work, with some exceptions:

- If a layer lists a filename with no directory separators in its JSON
   manifest, it won't load correctly in the container. This should be
   fixed soon. In particular, this bug affects the Mesa device selection
   layer.

- If a layer has a separate JSON manifest for 32-bit and 64-bit,
    it might only work for 32-bit *or* 64-bit, and not both.
    Fixing this is likely to require changes in the Vulkan loader.

The mechanism for selecting the correct Vulkan driver and GPU on Linux
is not fully settled, and the container can interfere with this, resulting
in the wrong GPU or driver being selected, particularly on multi-GPU
systems.

This can also affect system-wide Vulkan layers like MangoHUD and vkBasalt.

Launch options
--------------

This issue is specific to Proton games.

Using Steam's *Launch Options* feature to set environment variables such
as `LD_PRELOAD` for the game, or wrap the game in an "adverb" command like
`env` or `taskset`, often does not work.

This affects use of a custom per-game driver (like with `VK_ICD_FILENAMES`
or `LIBGL_DRIVERS_PATH`), and user hooks like `LD_PRELOAD` (such as
MangoHUD OpenGL).

Workaround: completely exit from Steam, then run Steam with
`PRESSURE_VESSEL_RELAUNCH_CONTAINER=1` in the environment. This shuts down
the container after the setup commands, and starts a new container (which
uses the launch options) for the actual game. This is slightly slower to
start, but results in the launch options being used for the new container.
It might become the default in a future release.

([#304](https://github.com/ValveSoftware/steam-runtime/issues/304),
[Proton#2330](https://github.com/ValveSoftware/Proton/issues/2330),
probably others)

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
is not really supported. JACK is not supported.

Workaround: use PulseAudio.

([#307](https://github.com/ValveSoftware/steam-runtime/issues/307),
[#344](https://github.com/ValveSoftware/steam-runtime/issues/344))

Sharing PulseAudio with the container doesn't currently work reliably if
you don't have an `XDG_RUNTIME_DIR`. Workaround: use systemd-logind
or elogind.

([#343](https://github.com/ValveSoftware/steam-runtime/issues/343))

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
