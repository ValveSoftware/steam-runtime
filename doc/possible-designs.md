# Steam Runtime design models

This document summarizes various models for how the Steam Runtime works,
has worked in the past or could work in the future, together with how
they relate to our [goals](goals.md).

"Host system" refers to the operating system running outside any
containers that might be in use, for example SteamOS or Ubuntu.

Currently, "graphics driver" refers to the GLX graphics driver
(normally either Mesa, NVIDIA proprietary, or GLVND backed by an ICD
from either Mesa or NVIDIA), but in principle it should also refer to
EGL, GLES, Vulkan, VA-API and other similar stacks.

*newest*(x, y, ...) is used as shorthand for looking at the same library
SONAME in each location *x*, *y*, ..., and taking whichever one appears
to be the newest.

*first*(x, y, ...) is used as shorthand for looking at the same library
SONAME in locations *x*, *y*, ..., and taking whichever one is found
first, without checking whether it is older or newer than in subsequent
locations.

## Out of scope

Whether we achieve the following goals is not really affected by how
the Steam Runtime works, so they are not discussed here:

  * Games can be built in a container
  * New runtimes can be supported for multiple years
  * New runtimes do not require rebuilding *everything*

## <a name="ldlp-2018">2018 `LD_LIBRARY_PATH` scout runtime</a>

(Status quo for non-Flatpak users.)

    |----------------------------
    |                    Host system
    |  steam.sh
    |     |
    |  .- \-run.sh- - - - - - - - - -
    |  .    |            steam-runtime (scout)
    |  .    |
    |  .    \- steam binary
    |  .         |
    |  .         \- The game

If `STEAM_RUNTIME_PREFER_HOST_LIBRARIES` is set to 0, then we revert
to the [2013 behaviour](#ldlp-2013).

Otherwise, for both the `steam` binary and games:

  * glibc comes from: host system
  * Graphics driver comes from: host system
  * Libraries used by graphics driver come from:
    *newest*(host system, scout)
  * Other libraries come from: *newest*(host system, scout),
    except in a few cases where scout libraries are preferred
    due to known incompatibilities between the same SONAME in the
    scout Steam Runtime and host systems
  * User's home directory comes from: host system, unrestricted

For newer runtimes (Steam Runtime 2), it is not feasible to do a flag-day
transition that makes the Steam client and all games conform to a new ABI,
so we would have to adopt a more complicated solution.

Entirely solves:

  * Open-source (Mesa) graphics drivers continue to work
  * Proprietary (NVIDIA) graphics drivers continue to work

Mostly solves:

  * Old games continue to work
      - There can be regressions if host system library behaviour changes
  * i386 games continue to work on i386-capable hosts
      - The host system must have basic i386 packages
  * Host system doesn't need uncommon packages installed
      - It needs i386 glibc and graphics drivers, plus unpredictable
        library dependencies where the abstraction leaks (particularly
        around steamwebhelper/CEF)

Only partially solves:

  * Games developed in an impure scout environment continue to work
      - It is anyone's guess whether they will work
  * Steam client runs in a predictable environment
  * New runtimes do not require newest host system
      - We cannot use a glibc newer than the one on the host system
      - Backporting newer everything-except-glibc is possible, but is
        a lot of work when the difference is measured in years
  * Steam can be installed in a cross-distro way
      - The bootstrapper can be downloaded and unpacked by hand, but
        few users do that
  * Steam can be installed unprivileged
      - The udev rules need to be installed by an administrator
        regardless
      - The bootstrapper can be downloaded and unpacked by hand, but
        few users do that
      - `steam-launcher.deb` is OS-specific and needs to be installed
        by an administrator; it can run arbitrary code as root, which
        could be replaced if someone malicious gains access to Valve
        infrastructure
      - Distro packages in Debian, Arch, etc. need to be installed
        by an administrator; they can run arbitrary code as root, but
        the OS vendor has the opportunity and responsibility to audit it,
        and the user must trust their OS vendor anyway; however, these
        packages do not always behave as intended by Valve

Does not solve:

  * Games run in a predictable, robust environment
      - Could get broken by just about anything, particularly in
        development or rolling-release distros
  * Games that inappropriately bundle libraries work anyway
  * Games don't all have to use the same runtime
  * Steam client can use a newer runtime
  * New runtimes do not require extensive patching
  * i386 games work on non-i386 hosts
  * Game data is easy to sync and delete
  * Steam client cannot accidentally break the system
  * Games cannot accidentally break the system
  * Games cannot accidentally break the Steam client
  * Security boundary between desktop and Steam client
  * Security boundary between desktop and games
  * Security boundary between Steam client and games

## <a name="ldlp-2013">2013 `LD_LIBRARY_PATH` scout runtime</a>

See the diagram for the [2018 behaviour](#ldlp-2018); it's the same. Only
the rules for choosing libraries were different.

For both the `steam` binary and games:

  * glibc comes from: host system
  * Graphics driver comes from: host system
  * Libraries used by graphics driver come from:
    *first*(scout, host system)
      - Note that this can easily break the graphics driver, which is
        why the 2018 behaviour is different. For example, the graphics
        driver will often require a newer `libgcc.so.1` than the one
        in scout.
  * Other libraries come from: *first*(scout, host system)
  * User's home directory comes from: host system, unrestricted

Entirely solves:

  * Proprietary (NVIDIA) graphics drivers continue to work

Mostly solves:

  * Old games continue to work
  * i386 games continue to work on i386-capable hosts
      - The host system must have basic i386 packages
  * Host system doesn't need uncommon packages installed

Only partially solves:

  * Open-source (Mesa) graphics drivers continue to work
  * Games run in a predictable, robust environment
  * Games developed in an impure scout environment continue to work
  * Games that inappropriately bundle libraries work anyway
  * Steam client runs in a predictable environment
  * New runtimes do not require newest host system
  * Steam can be installed in a cross-distro way
    - Same as the 2018 `LD_LIBRARY_PATH` runtime
  * Steam can be installed unprivileged
    - Same as the 2018 `LD_LIBRARY_PATH` runtime

Does not solve:

  * Games don't all have to use the same runtime
  * Steam client can use a newer runtime
  * New runtimes do not require extensive patching
  * i386 games work on non-i386 hosts
  * Game data is easy to sync and delete
  * Steam client cannot accidentally break the system
  * Games cannot accidentally break the system
  * Games cannot accidentally break the Steam client
  * Security boundary between desktop and Steam client
  * Security boundary between desktop and games
  * Security boundary between Steam client and games

## <a name="flatpak-2018">Flatpak + 2018 `LD_LIBRARY_PATH` scout runtime</a>

(Status quo for users of the unofficial Flatpak app.)

    |----------------------------
    |                    Host system
    |    flatpak run
    |     |
    |  |--\-bwrap-------------------
    |  |    |            org.freedesktop.Platform//18.08
    |  |    |
    |  |    \-steam.sh
    |  |         |
    |  |      .- \-run.sh- - - - - - - - - -
    |  |      .    |            steam-runtime (scout)
    |  |      .    |
    |  |      .    \- steam binary
    |  |      .         |
    |  |      .         \- The game

This is exactly the [2018 `LD_LIBRARY_PATH` Steam runtime](#ldlp-2018),
but placed inside a Flatpak container.

For both the `steam` binary and games:

  * glibc comes from: org.freedesktop.Platform runtime
  * Graphics driver comes from: org.freedesktop.Platform extensions
      - On systems with NVIDIA proprietary graphics, Flatpak is
        responsible for installing a user-space driver that matches the
        kernel driver
      - On systems with Mesa graphics, the user-space driver used by Flatpak
        might be older or newer than the one used on the host system
        (in practice it will usually be newer)
  * Libraries used by graphics driver come from:
    *newest*(org.freedesktop.Platform, scout)
  * Other libraries come from:
    *newest*(org.freedesktop.Platform, scout),
    except in a few cases where scout libraries are preferred
    due to known incompatibilities between the same SONAME in the
    scout Steam Runtime and host systems
  * User's home directory comes from: ~/.var/app/com.valvesoftware.Steam

For newer runtimes (Steam Runtime 2), we cannot do a flag-day transition
that makes the Steam client and all games conform to a new ABI, so we
would have to adopt a more complicated solution.

Entirely solves:

  * i386 games work on non-i386 hosts
      - i386 glibc and graphics drivers on the host system are not
        required, as long as the Flatpak runtime has them
  * Steam client cannot accidentally break the system
  * Games cannot accidentally break the system
  * Steam can be installed in a cross-distro way

Mostly solves:

  * Old games continue to work
      - There can be regressions if library behaviour in o.fd.Platform changes
  * i386 games continue to work on i386-capable hosts
      - o.fd.Platform must have basic i386 packages
  * Games developed in an impure scout environment continue to work
      - The app has workarounds for known-broken cases
  * Host system doesn't need uncommon packages installed
      - It needs vaguely recent Flatpak and xdg-desktop-portal versions
  * Open-source (Mesa) graphics drivers continue to work
      - org.freedesktop.Platform is regularly updated with new Mesa drivers
  * Proprietary (NVIDIA) graphics drivers continue to work
      - org.freedesktop.Platform is regularly updated with new NVIDIA drivers
  * Games run in a predictable, robust environment
      - Could get broken once a year by a new Flatpak Platform, but if so,
        it will be broken for everyone (easier to diagnose)
      - Could get broken by updated graphics driver extension
  * Steam client runs in a predictable environment
  * New runtimes do not require newest host system
      - As long as a suitably recent Flatpak version can be backported
        to the host system, all is well
  * New runtimes work on future hardware
      - Backported graphics drivers are available in a Flatpak extension
      - This can't save us from incompatibilities like VA-API libva.so.1
        vs. libva.so.2, which have incompatible ICDs
      - The underlying Flatpak Platform must be reasonably new,
        otherwise eventually we will reach the point where the current
        versions of Mesa/LLVM can no longer be backported to it
  * Steam can be installed unprivileged
      - Flatpak and the udev rules need to be installed by hand
  * Security boundary between desktop and Steam client
      - Unclear how well this is solved: there is a sandbox, but it might
        not be an effective security boundary against a knowledgeable
        attacker
  * Security boundary between desktop and games
      - Unclear how well this is solved: there is a sandbox, but it might
        not be an effective security boundary against a knowledgeable
        attacker

Only partially solves:

  * Games that inappropriately bundle libraries work anyway
      - Crowdsourced configuration for the `LD_AUDIT` plugin handles this
  * Steam client can use a newer runtime
      - At the moment it doesn't, but if Flatpak was the official
        distribution mechanism, the Steam client could rely on the Flatpak
        runtime directly

Does not solve:

  * Games don't all have to use the same runtime
  * New runtimes do not require extensive patching
  * Game data is easy to sync and delete
  * Games cannot accidentally break the Steam client
  * Security boundary between Steam client and games

## <a name="pressure-vessel-2019">2018 `LD_LIBRARY_PATH` scout runtime + 2019 pressure-vessel scout Platform</a>

    |----------------------------
    |                    Host system
    |    steam.sh
    |     |
    |  .- \-run.sh- - - - - - - - - -
    |  .    |            steam-runtime (scout)
    |  .    |
    |  .    \- steam binary
    |  .       |
    |  .  |----\-pressure-vessel-wrap, bwrap-----
    |  .  |       |      SteamLinuxRuntime/scout
    |  .  |       |
    |  .  |       \- The game

This is what the Steam container runtime's `run-in-scout` script sets up.

If you are using `pressure-vessel-test-ui` or `PRESSURE_VESSEL_WRAP_GUI=1`,
it's what you get by selecting the scout runtime from the *Runtime*
drop-down list.

The libraries used for the Steam binary are the same as in the
[2018 `LD_LIBRARY_PATH` Steam runtime](#ldlp-2018).

However, games run in a container via the pressure-vessel tool:

  * glibc comes from: *newest*(host system, scout)
  * Graphics driver comes from: host system
  * Libraries used by graphics driver come from:
    *newest*(scout, host system)
  * Other libraries come from: scout
  * User's home directory comes from one of:
      - host system, unrestricted
      - a private directory like ~/.var/app/com.steampowered.App440 per game

For newer runtimes (Steam Runtime 2), we would simply use the new runtime
for individual games instead of using Steam Runtime 1 'scout'.

Entirely solves:

  * Games don't all have to use the same runtime

Mostly solves:

  * Host system doesn't need uncommon packages installed
      - It needs i386 glibc and graphics drivers, plus a vaguely recent
        Flatpak or standalone bubblewrap, or a kernel that allows the
        bundled copy to create user namespaces without being setuid root
  * New runtimes do not require newest host system
      - We use glibc from the container if newer than the host system,
        but a lot of duct tape is involved
  * Open-source (Mesa) graphics drivers continue to work
  * Proprietary (NVIDIA) graphics drivers continue to work
  * New runtimes do not require extensive patching
  * New runtimes work on future hardware
      - This can't save us from incompatibilities like VA-API libva.so.1
        vs. libva.so.2, which have incompatible ICDs
  * Game data is easy to sync and delete
      - Only if the private home directory is used
  * Games cannot accidentally break the system
      - Only with `--unshare-home`

Only partially solves:

  * Old games continue to work
      - There are some regressions
  * i386 games continue to work on i386-capable hosts
      - There are some regressions
  * Games run in a predictable, robust environment
      - Could get broken by updated graphics drivers
      - Could get broken by updated glibc
      - Setting up the container to have the host graphics drivers has
        a lot of moving parts and there are lots of things that can go
        wrong, some of which result in total failure
  * Steam client runs in a predictable environment
      - No better or worse than pure `LD_LIBRARY_PATH`
  * Steam can be installed in a cross-distro way
      - No better or worse than pure `LD_LIBRARY_PATH`
  * Steam can be installed unprivileged
      - No better or worse than pure `LD_LIBRARY_PATH`

Does not solve:

  * Games developed in an impure scout environment continue to work
      - Not true (somewhat by design), so it will have to be opt-in
  * Games that inappropriately bundle libraries work anyway
  * Steam client can use a newer runtime
  * i386 games work on non-i386 hosts
  * Steam client cannot accidentally break the system
  * Games cannot accidentally break the Steam client
      - Could be solved by more selective sharing in `--unshare-home`
  * Security boundary between desktop and Steam client
      - No security boundary at all
  * Security boundary between desktop and games
      - pressure-vessel does not attempt to set up a security boundary
  * Security boundary between Steam client and games
      - pressure-vessel does not attempt to set up a security boundary

## <a name="pressure-vessel-scout-on-host-usr">2018 `LD_LIBRARY_PATH` scout runtime + pressure-vessel with host /usr + scout again</a>

    |----------------------------
    |                    Host system
    |    steam.sh
    |     |
    |  .- \-run.sh- - - - - - - - - -
    |  .    |            steam-runtime (scout)
    |  .    |
    |  .    \- steam binary
    |  .       |
    |  .  |----\-pressure-vessel-wrap, bwrap-----
    |  .  |       |      Host system /usr + steam-runtime libraries,
    |  .  |       |               but in container namespaces
    |  .  |       \- The game

If you are using `pressure-vessel-test-ui` or `PRESSURE_VESSEL_WRAP_GUI=1`,
this is what you get by selecting *None (use host system)* from the
*Runtime* drop-down list.

Games run in a container namespace via the pressure-vessel tool, but
that container imports the `/usr`, `/lib*`, `/bin` and `/sbin` from the
host system (as read-only mounts) instead of using a special runtime,
and sets the same environment variables as the 2018 `LD_LIBRARY_PATH`
Steam Runtime.

As a result, the libraries used for the Steam binary and for games are
the same as in the 2018 `LD_LIBRARY_PATH` Steam Runtime. However, in
this mode, we do have the opportunity to unshare `/home` if we want to.

For newer runtimes (Steam Runtime 2), we could choose other modes like
[2018 `LD_LIBRARY_PATH` scout runtime + 2019 pressure-vessel scout Platform](#pressure-vessel-2019)
on a per-game basis.

Entirely solves:

  * Games don't all have to use the same runtime
       - Not directly, but we can choose between this and other modes like
         [2018 `LD_LIBRARY_PATH` scout runtime + 2019 pressure-vessel scout Platform](#pressure-vessel-2019)
         on a per-game basis

Mostly solves:

  * Open-source (Mesa) graphics drivers continue to work
      - They can break if the host system installs them in unusual locations
  * Proprietary (NVIDIA) graphics drivers continue to work
      - They can break if the host system installs them in unusual locations
  * Old games continue to work
      - There can be regressions if host system library behaviour changes
  * i386 games continue to work on i386-capable hosts
      - The host system must have basic i386 packages
  * Host system doesn't need uncommon packages installed
      - It needs i386 glibc and graphics drivers, plus unpredictable
        library dependencies where the abstraction leaks (particularly
        around steamwebhelper/CEF), and either a vaguely recent
        Flatpak or standalone bubblewrap, or a kernel that allows the
        bundled copy to create user namespaces without being setuid root
  * New runtimes do not require newest host system
      - To achieve this, the newer runtimes would have to behave more like
        [2018 `LD_LIBRARY_PATH` scout runtime + 2019 pressure-vessel scout Platform](#pressure-vessel-2019),
        substituting the new runtime for scout
  * New runtimes do not require extensive patching
      - Again, the newer runtimes would have to behave more like
        the scout Platform to achieve this
  * Game data is easy to sync and delete
      - Only if the private home directory is used
  * Games cannot accidentally break the system
      - Only with `--unshare-home`

Only partially solves:

  * Games developed in an impure scout environment continue to work
  * Steam client runs in a predictable environment
  * Steam can be installed in a cross-distro way
  * Steam can be installed unprivileged

Does not solve:

  * Games run in a predictable, robust environment
  * Games that inappropriately bundle libraries work anyway
  * Steam client can use a newer runtime
  * i386 games work on non-i386 hosts
  * Steam client cannot accidentally break the system
  * Games cannot accidentally break the Steam client
  * Security boundary between desktop and Steam client
  * Security boundary between desktop and games
  * Security boundary between Steam client and games

## Arch Linux steam-native-runtime

(Included for comparison, but not recommended.)

    |----------------------------
    |                    Host system
    |
    |  .- steam-native.sh - - - - - -
    |  .    |            /usr/lib/steam:/usr/lib32/steam
    |  .    |                 (compat libraries)
    |  .    \- steam binary
    |  .         |
    |  .         \- The game

For both the `steam` binary and games:

  * glibc comes from: host system
  * Graphics driver comes from: host system
  * Libraries used by graphics driver come from: host system
  * Other libraries come from: host system, except in a few cases
    where libraries in /usr/lib/steam:/usr/lib32/steam are preferred
      - In theory these can be made compatible with the ones shipped
        in scout
      - In practice this is a losing battle, because 2019 Arch and
        2012 Ubuntu are too different
  * User's home directory comes from: host system, unrestricted

Entirely solves:

  * Open-source (Mesa) graphics drivers continue to work
  * Proprietary (NVIDIA) graphics drivers continue to work

Mostly solves:

  * i386 games continue to work on i386-capable hosts
      - The host system must have basic i386 packages

Only partially solves:

  * Old games continue to work

Does not solve:

  * Host system doesn't need uncommon packages installed
  * Games developed in an impure scout environment continue to work
  * Steam client runs in a predictable environment
  * Steam can be installed in a cross-distro way
  * Steam can be installed unprivileged
  * Games run in a predictable, robust environment
  * Games that inappropriately bundle libraries work anyway
  * Games don't all have to use the same runtime
  * i386 games work on non-i386 hosts
  * Game data is easy to sync and delete
  * Steam client cannot accidentally break the system
  * Games cannot accidentally break the system
  * Games cannot accidentally break the Steam client
  * Security boundary between desktop and Steam client
  * Security boundary between desktop and games
  * Security boundary between Steam client and games
