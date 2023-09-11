Common issues and workarounds
=============================

Some issues involving the SteamLinuxRuntime framework and the
pressure-vessel container-launcher are not straightforward to fix.
Here are some that are likely to affect multiple users:

Labelling of Steam Linux Runtime versions
-----------------------------------------

The naming used for the various branches of the Steam Linux Runtime has
not always been obvious.

The term "Steam Play" is used in the Steam user interface to refer to
all compatibility tools, including
the Steam container runtime framework
(a mechanism to run native Linux games on older or newer Linux distributions),
Proton (a mechanism to run Windows games on Linux),
and potentially other compatibility tools in future.

The term "Steam Linux Runtime" is used in the Steam user interface to refer
to the container runtime framework specifically.

The "Steam Linux Runtime 1.0 (scout)" compatibility tool
(application ID 1070560)
combines Steam Runtime 1 libraries with a Steam Runtime 2 container,
and is used to run historical native Linux games.
Before September 2023, this was (confusingly) labelled "Steam Linux Runtime".
The old name might still appear in some contexts.

The "Steam Linux Runtime 2.0 (soldier)" tool (application ID 1391110) is
used to run Proton 5.13 up to 7.0 and is also used internally
by the "Steam Linux Runtime" tool.
Before September 2023, this was labelled "Steam Linux Runtime - soldier".

The "Steam Linux Runtime 3.0 (sniper)" tool (application ID 1628350) is
used to run Proton 8.0 and some newer native Linux games.
Before September 2023, this was labelled "Steam Linux Runtime - sniper".

Disabling Steam Play disables all Steam Linux Runtime tools
-----------------------------------------------------------

In Steam's global settings, there is an option to turn off all Steam Play
compatibility tools.
As well as disabling Proton, this also disables Steam Linux Runtime 3.0
(sniper), which will result in games that require this runtime being
launched in a way that does not work.
This is a Steam client issue: it should not allow launching the affected
games in this configuration.

Games affected by this include Dota 2, Endless Sky and Retroarch.

Workaround: in Steam's global Settings window, go to the Compatibility tab
and ensure that "Enable Steam Play for supported titles" is checked.

([steam-for-linux#9852](https://github.com/ValveSoftware/steam-for-linux/issues/9852))

Switching Steam Linux Runtime branch sometimes requires a Steam restart
-----------------------------------------------------------------------

When a game that was previously using an older runtime environment switches
to Steam Linux Runtime 3.0 (sniper), sometimes the Steam client will
continue to run that game in the older runtime until it is restarted.
This is a Steam client issue: it should switch to the new runtime
automatically.

Games affected by this include Dota 2, Endless Sky and Retroarch.

Workaround: allow Steam to download the updated game, then completely exit
from Steam, and launch Steam again. This will only need to be done once:
all subsequent game launches should work correctly.

([steam-for-linux#9835](https://github.com/ValveSoftware/steam-for-linux/issues/9835))

Forcing use of Steam Linux Runtime 1.0 (scout) for games requiring SLR 3
------------------------------------------------------------------------

It is currently possible for users to configure games to be run
under Steam Linux Runtime 1.0 (scout), even if the game requires
Steam Linux Runtime 3.0 (sniper), which often will not work.
This is a Steam client issue: it should not allow this configuration.

Games affected by this include Dota 2, Endless Sky and Retroarch.

Workaround: in the game's Properties, go to the Compatibility tab and
ensure that "Force the use of a specific compatibility tool" is unchecked.

([steam-for-linux#9844](https://github.com/ValveSoftware/steam-for-linux/issues/9844))

Flatpak app limitations
-----------------------

Steam has been packaged as a Flatpak app by the Flathub community, but
this Flatpak app is not officially supported by Valve.

Using the Steam container runtimes from inside a Flatpak sandbox requires
features that are not yet available in all Linux distributions. To use
the container runtimes, you will need:

* An operating system where
    [unprivileged users can create user namespaces](https://github.com/flatpak/flatpak/wiki/User-namespace-requirements#unprivileged-bubblewrap)
    (non-setuid bubblewrap)

    * Debian >= 11, but not Debian 10 or older
    * RHEL/CentOS >= 8, but not RHEL/CentOS 7 or older
    * Arch Linux with the default `linux` kernel,
        but not `linux-hardened` and `bubblewrap-suid`
    * Most other recent distributions, e.g. Ubuntu

* Flatpak 1.12 or later

    * Ubuntu 18.04 and 20.04 users can get this from
        [the PPA](https://launchpad.net/~flatpak/+archive/ubuntu/stable/),
        and it is included in Ubuntu 22.04 LTS
    * Debian 11 users can get this from
        [official backports](https://backports.debian.org/Instructions/),
        and it is included in Debian 12

As a workaround, users of older versions of Flatpak can try using
[a community build of Proton](https://github.com/flathub/com.valvesoftware.Steam.CompatibilityTool.Proton)
which uses the freedesktop.org runtime instead of Steam Runtime 2.

([#294](https://github.com/ValveSoftware/steam-runtime/issues/294),
[Proton#4268](https://github.com/ValveSoftware/Proton/issues/4268),
[Proton#4283](https://github.com/ValveSoftware/Proton/issues/4283),
[com.valvesoftware.Steam#642](https://github.com/flathub/com.valvesoftware.Steam/issues/642),
[flatpak#3797](https://github.com/flatpak/flatpak/issues/3797),
[flatpak#4286](https://github.com/flatpak/flatpak/issues/4286))

Snap app limitations
--------------------

Steam has been packaged as a Snap app by Canonical, but this Snap app is
not officially supported by Valve.

Using the Steam container runtimes from inside a Snap sandbox is
relatively fragile, because its AppArmor profile depends on specific
paths and operations. Some of the paths used are implementation details
of Steam which can change over time, and some are likely to be different
for different user configurations.

In particular, installing the container runtimes into a Steam library
outside `/home` is known not to work in the Snap app.

([#586](https://github.com/ValveSoftware/steam-runtime/issues/586),
[#602](https://github.com/ValveSoftware/steam-runtime/issues/602),
[steam-snap#27](https://github.com/canonical/steam-snap/issues/27),
[steam-snap#126](https://github.com/canonical/steam-snap/issues/126),
[steam-snap#289](https://github.com/canonical/steam-snap/issues/289))

Non-FHS operating systems
-------------------------

Unusual directory layouts and `ld.so` names are not supported.
The Debian/Ubuntu family, the Fedora/CentOS/Red Hat family, Arch Linux
and openSUSE are most likely to work.

Exherbo and ClearLinux have had issues in the past, but are currently
believed to work successfully. The changes
made to support these operating systems can be used as a basis to propose
patches to make pressure-vessel work in other "almost-FHS" environments.

NixOS has its own scripts to set up a FHS-compatible environment to run
Steam. As of 2022, this should generally be compatible with pressure-vessel.
Guix is in the same situation as NixOS.

Other non-FHS distributions might also not work.
We have prepared a document listing
[assumptions made about the distribution][distro assumptions], which
distribution developers might find useful.

Workaround: don't enable Steam Linux Runtime or Proton 5.13 (or newer)
on OSs with unusual directory layouts, or use the unofficial Flatpak app
(requires Flatpak 1.12).

[distro assumptions]: https://gitlab.steamos.cloud/steamrt/steam-runtime-tools/-/blob/main/docs/distro-assumptions.md

kernel.unprivileged\_userns\_clone
----------------------------------

The container runtime has the same
[user namespace requirements](https://github.com/flatpak/flatpak/wiki/User-namespace-requirements)
as Flatpak.
Modern operating systems in their default configuration usually meet these
requirements.

On Debian 10 or older and SteamOS 2, either the `bubblewrap` package
from the OS must be installed, or the `kernel.unprivileged_userns_clone`
sysctl parameter must be set to 1. Debian 11 sets
`kernel.unprivileged_userns_clone` to 1 by default.

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

Older NVIDIA drivers
--------------------

Older versions of the proprietary NVIDIA drivers are incompatible with
Proton, and have been observed to trigger crashes in the container runtime
even when not using Proton.

The 390.x drivers are known **not** to work with the container runtime.
Unfortunately, this is the newest series supporting
[GPUs based on the Fermi microarchitecture][fermi] (GFxxx, NVC0, 2010-2012),
such as the GeForce GTX 470 and GTX 590, so users of Fermi or older GPUs
will be unable to use the container runtime.

[fermi]: https://sources.debian.org/src/nvidia-graphics-drivers/470.129.06-6~deb11u1/debian/end-of-life-390.list/

If your GPU is supported by a later NVIDIA driver version, please upgrade
to the newer driver.
For users of [GPUs based on the Kepler microarchitecture][kepler]
(GKxxx, NVE0, 2012-2014), the [470.x legacy drivers][nvidia-archive] are
recommended.
For users of newer GPUs, either 470.x or a newer version is recommended.

[kepler]: https://sources.debian.org/src/nvidia-graphics-drivers/470.129.06-6~deb11u1/debian/end-of-life-470.list/
[nvidia-archive]: https://www.nvidia.com/en-us/drivers/unix/

([#420](https://github.com/ValveSoftware/steam-runtime/issues/420))

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

Workaround: don't use Steam Linux Runtime for those games yet.

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
* `/home`
* `/media`
* `/mnt`
* `/opt`
* `/run/media`
* `/srv`

Directories outside those areas are usually not shared with
the container. In particular, this can affect games that ask you to browse
for a directory to be used for storage, like Microsoft Flight Simulator,
if your large storage directory is mounted at a custom location such
as `/hdd`.

You can force them to be shared by setting the environment variable
`PRESSURE_VESSEL_FILESYSTEMS_RO` and/or `PRESSURE_VESSEL_FILESYSTEMS_RW`
to a colon-separated list of paths. Paths in
`PRESSURE_VESSEL_FILESYSTEMS_RO` are read-only and paths in
`PRESSURE_VESSEL_FILESYSTEMS_RW` are read/write.

Example:

    export PRESSURE_VESSEL_FILESYSTEMS_RO="$MANGOHUD_CONFIGFILE"
    export PRESSURE_VESSEL_FILESYSTEMS_RW="/hdd:/archival:/stuff/games"
    steam

Symbolic links between directories
----------------------------------

Symbolic links that cross between directories tend to cause trouble for
container frameworks. Consider using bind mounts instead, particularly
for system-level directories (outside the home directory).

If a directory that will be shared with the container is a symbolic link
to some other directory, please make sure that the target of the symbolic
link is also in a directory that is
[shared with the container](#sharing-directories-with-the-container).

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

### Updating "Steam Linux Runtime 1.0 (scout)" compatibility tool

Due to a Steam limitation, after updating to version 0.20210630.32 or
later, it is necessary to exit from Steam completely and re-launch Steam,
so that the updated compatibility tool configuration will be loaded.
Until Steam has been restarted, trying to launch a game with the
"Steam Linux Runtime 1.0 (scout)" compatibility tool will show an error message
asking for a Steam restart.

Reporting other issues
----------------------

Please report other issues you encounter to
<https://github.com/ValveSoftware/steam-runtime/>, making sure to include
the information described in the
[bug reporting guide](reporting-steamlinuxruntime-bugs.md).
