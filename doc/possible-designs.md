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
    |  .         \- Proton, if used
    |  .            \- The game

For both the `steam` binary and games:

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
        why this behaviour is no longer offered. For example, the graphics
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
    |  |    |            org.freedesktop.Platform//20.08
    |  |    |
    |  |    \-steam.sh
    |  |         |
    |  |      .- \-run.sh- - - - - - - - - -
    |  |      .    |            steam-runtime (scout)
    |  |      .    |
    |  |      .    \- steam binary
    |  |      .         |
    |  |      .         \- Proton (if used)
    |  |      .            \- The game

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
would have to adopt a more complicated solution, for example putting the
[Layered `LD_LIBRARY_PATH` runtime](#layered-ldlp) inside the Flatpak
container.

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

## <a name="pressure-vessel-2019">2018 `LD_LIBRARY_PATH` scout runtime + pressure-vessel container</a>

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
    |  .  |       |      container runtime (scout, soldier, sniper etc.)
    |  .  |       |
    |  .  |       \- Proton (if used)
    |  .  |          \- The game

This design is used by the "Steam Linux Runtime - soldier" compatibility
tool, currently used to run Proton 5.13 or later. It could potentially be
used to run native Linux games in future, if Steam gains a way to mark
games as targeting scout rather than soldier.

This is also what the "Steam Linux Runtime" compatibility tool did
until mid July 2021, but with a scout container instead of a soldier
container. Since mid July 2021,
[a different design](#pressure-vessel-scout-on-srt2)
has been used for native Linux games running in a scout environment.

The libraries used for the Steam binary are the same as in the
[2018 `LD_LIBRARY_PATH` Steam runtime](#ldlp-2018).

However, games run in a container via the pressure-vessel tool:

  * glibc comes from: *newest*(host system, container runtime)
  * Graphics driver comes from: host system
  * Libraries used by graphics driver come from:
    *newest*(host system, container runtime)
  * Other libraries come from: container runtime
  * User's home directory comes from one of:
      - host system, unrestricted
      - a private directory like ~/.var/app/com.steampowered.App440 per game

As currently deployed, the container runtime is soldier, but it could
be anything.

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
      - Not true (somewhat by design), which is why we no longer use
        this design for scout games
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
    |  .  |       \- Proton (if used)
    |  .  |          \- The game

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
[2018 `LD_LIBRARY_PATH` scout runtime + pressure-vessel container](#pressure-vessel-2019)
on a per-game basis.

Entirely solves:

  * Games don't all have to use the same runtime
       - Not directly, but we can choose between this and other modes like
         [2018 `LD_LIBRARY_PATH` scout runtime + pressure-vessel container](#pressure-vessel-2019)
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
      - To achieve this, the newer runtimes must use
         [2018 `LD_LIBRARY_PATH` scout runtime + pressure-vessel container](#pressure-vessel-2019)
         instead
  * New runtimes do not require extensive patching
      - To achieve this, the newer runtimes must use
         [2018 `LD_LIBRARY_PATH` scout runtime + pressure-vessel container](#pressure-vessel-2019)
         instead
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

## <a name="layered-ldlp">Layered `LD_LIBRARY_PATH` runtime</a>

(This is theoretical, and has not been deployed in practice.)

    |----------------------------
    |                    Host system
    |    steam.sh
    |     |
    |  .- \-run.sh- - - - - - - - - -
    |  .    |            steam-runtime (A)
    |  .    |
    |  .    \- steam binary
    |  .       |
    |  .  .- - \-unruntime.sh - - - - - - - - - -
    |  .  .       |       Back to host system!
    |  .  .       |
    |  .  .   .- -\-run.sh- - - - - - - - - -
    |  .  .   .      |     steam-runtime (B)
    |  .  .   .      |
    |  .  .   .      \- Proton (if used)
    |  .  .   .         \- The game

The Steam client could use an as yet hypothetical `unruntime.sh` to undo
what `run.sh` did, wrapping a *different* Steam Runtime's `run.sh`,
which would redo the Steam Runtime setup for the game. Alternatively,
we could have a command-line option for `run.sh` to undo and redo the
Steam Runtime environment variables in a single operation, which would
be functionally equivalent but would make for a more confusing diagram.

Prior art: `pressure-vessel-unruntime` already does this, as a way to
"escape from" the Steam Runtime environment to run `pressure-vessel-wrap`
in a more predictable way.

For the `steam` binary:

  * glibc comes from: host system
  * Graphics driver comes from: host system
  * Libraries used by graphics driver come from:
    *newest*(host system, A)
  * Other libraries come from: *newest*(host system, A),
    except in a few cases where (A) libraries are preferred
    due to known incompatibilities between the same SONAME in the
    (A) Steam Runtime and host systems
  * User's home directory comes from: host system, unrestricted

For games:

  * glibc comes from: host system
  * Graphics driver comes from: host system
  * Libraries used by graphics driver come from:
    *newest*(host system, B)
  * Other libraries come from: *newest*(host system, B),
    except in a few cases where (B) libraries are preferred
    due to known incompatibilities between the same SONAME in the
    (B) Steam Runtime and host systems
  * User's home directory comes from: host system, unrestricted

This decouples the Steam Runtime library stacks A and B, and could be
used to run the game in an older or newer Steam Runtime than the
Steam client.

It could also be combined with Flatpak in the obvious way.

For newer runtimes (Steam Runtime 2), we would simply choose A != B.

Entirely solves:

  * Open-source (Mesa) graphics drivers continue to work
  * Proprietary (NVIDIA) graphics drivers continue to work
  * Games don't all have to use the same runtime
  * Steam client can use a newer runtime
  * New runtimes work on future hardware
      - The host graphics driver is used, so this is a non-issue

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
      - No better or worse than single-layer `LD_LIBRARY_PATH`
  * Steam can be installed unprivileged
      - No better or worse than single-layer `LD_LIBRARY_PATH`

Does not solve:

  * Games run in a predictable, robust environment
      - Could get broken by just about anything, particularly in
        development or rolling-release distros
  * Games that inappropriately bundle libraries work anyway
  * New runtimes do not require extensive patching
  * i386 games work on non-i386 hosts
  * Game data is easy to sync and delete
  * Steam client cannot accidentally break the system
  * Games cannot accidentally break the system
  * Games cannot accidentally break the Steam client

## <a name="pressure-vessel-scout-on-srt2">2018 `LD_LIBRARY_PATH` scout runtime + newer Platform + scout again</a>

This design is used by the "Steam Linux Runtime" compatibility
tool since mid July 2021.

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
    |  .  |       |       Steam Runtime 2 Platform
    |  .  |       |       (soldier, based on Debian 10)
    |  .  |       |
    |  .  |   .- -\-run.sh- - - - - - - - - -
    |  .  |   .      |     steam-runtime (scout)
    |  .  |   .      |
    |  .  |   .      \- The game

The libraries used for the Steam binary are the same as in the 2018
`LD_LIBRARY_PATH` Steam Runtime.

Games run in a container via the pressure-vessel tool:

  * glibc comes from: *newest*(host system, Steam Runtime 2)
  * Graphics driver comes from: host system
  * Libraries used by graphics driver come from:
    *newest*(scout, host system, Steam Runtime 2)
  * Other libraries come from: *newest*(scout, Steam Runtime 2)
  * User's home directory comes from one of:
      - host system, unrestricted
      - a private directory like ~/.var/app/com.steampowered.App440 per game

The diagram and text above uses Steam Runtime v2 'soldier' for brevity,
but this could equally well be done with a future runtime.

Entirely solves:

  * Games don't all have to use the same runtime
       - Not directly, but we can choose between this and other modes like
         [2018 `LD_LIBRARY_PATH` scout runtime + pressure-vessel container](#pressure-vessel-2019)
         on a per-game basis

Mostly solves:

  * Old games continue to work
      - Expected to be fewer regressions than with the
        [pure scout container](#pressure-vessel-2019)
  * i386 games continue to work on i386-capable hosts
      - Expected to be fewer regressions than with pure scout container
  * Open-source (Mesa) graphics drivers continue to work
  * Proprietary (NVIDIA) graphics drivers continue to work
  * Games developed in an impure scout environment continue to work
      - Games confirmed to work in this configuration but not in the
        pure scout container include:
          + Shadow of the Tomb Raider (750920)
          + Life is Strange 2 (532210)
          + Danger Gazers (1043150), Demetrios (451570),
            The Swords of Ditto (619780) and other Game Maker titles
  * Game data is easy to sync and delete
      - Only if the private home directory is used
  * Games cannot accidentally break the system
      - Only with `--unshare-home`
  * Games run in a predictable, robust environment

Only partially solves:

  * Steam client runs in a predictable environment
  * Steam can be installed in a cross-distro way
  * Steam can be installed unprivileged

Does not solve:

  * Games that inappropriately bundle libraries work anyway
  * Steam client can use a newer runtime
  * i386 games work on non-i386 hosts
  * Steam client cannot accidentally break the system
  * Games cannot accidentally break the Steam client
      - Could be solved by more selective sharing in `--unshare-home`
  * Security boundary between desktop and Steam client
  * Security boundary between desktop and games
  * Security boundary between Steam client and games

## Flatpak + pressure-vessel in parallel

This is implemented when using Flatpak 1.11.1 or later.

    |----------------------------
    |                    Host system
    |    flatpak run
    |     |
    |  |--\-bwrap------------------|
    |  |    |        o.fd.P//20.08 |
    |  |    |                      |
    |  |    \-steam.sh             |
    |  |         |                 |
    |  |      .- \-run.sh- - - - - |
    |  |      .    |    s-rt scout |
    |  |      .    |               |
    |  |      .    \- steam binary |
    |  |      .         \- pv-wrap |
    |  |      .             \==IPC===> flatpak-portal service
    |  |---------------------------|     |
    |                                 |--\-bwrap--------------------|
    |                                 |     |             A runtime |
    |                                 |     \- The game             |
    |                                 |-----------------------------|

For the `steam` binary:

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

For the game, there are several options for what the runtime could be
and how it would work. For old (scout) games, it could be:

  * a pure Steam Runtime 1 'scout' container, similar to
    [2018 `LD_LIBRARY_PATH` scout runtime + pressure-vessel container](#pressure-vessel-2019)
    above, with graphics drivers from the host system or a Flatpak runtime
    (presumably the same one the Steam client uses)
  * a Steam Runtime 2 container with the `LD_LIBRARY_PATH`
    scout runtime inside, similar to
    [2018 `LD_LIBRARY_PATH` scout runtime + newer Platform + scout again](#pressure-vessel-scout-on-srt2)
    above, with graphics drivers from the host system or a Flatpak runtime
    (as of mid July 2021, this is what is implemented in practice)
  * a Flatpak runtime with the `LD_LIBRARY_PATH`
    scout runtime inside, similar to
    [2018 `LD_LIBRARY_PATH` scout runtime + newer Platform + scout again](#pressure-vessel-scout-on-srt2)
    above but using a Flatpak runtime instead of Steam Runtime 2, with
    graphics drivers from the host system or that same Flatpak runtime

and for new (Steam Runtime 2) games, it could be:

  * a pure Steam Runtime 2 container,
    [2018 `LD_LIBRARY_PATH` scout runtime + pressure-vessel container](#pressure-vessel-2019),
    with graphics drivers from the host system or a Flatpak runtime
    (as of mid July 2021, this is what is implemented in practice)
  * a Flatpak runtime with an `LD_LIBRARY_PATH`
    Steam Runtime 2 runtime inside, analogous to
    [Layered `LD_LIBRARY_PATH` runtime](#layered-ldlp) above,
    with graphics drivers from the host system or that same
    Flatpak runtime

We do not even necessarily have to choose the same option for each game.

Any of these options has some shared properties, regardless of the
runtime we choose for the game:

Entirely solves:

  * Steam can be installed in a cross-distro way
  * Steam can be installed unprivileged
  * Steam client cannot accidentally break the system
  * Steam client can use a newer runtime
  * Games don't all have to use the same runtime

Mostly solves:

  * Steam client runs in a predictable environment
  * Game data is easy to sync and delete
      - Only if the private home directory is used
  * Games cannot accidentally break the system
      - Only with `--unshare-home`
  * Security boundary between desktop and Steam client

Only partially solves:

  * Host system doesn't need uncommon packages installed
      - Flatpak 1.11.1, which is not yet a stable release, is required

### Pure Steam Runtime container for game

This is implemented in pressure-vessel >= 0.20210430.0 when used with
Flatpak 1.11.1 or later.

    |----------------------------
    |                    Host system
    |
    |  flatpak-portal service <===== IPC from pressure-vessel-wrap
    |       |
    |  |----\-bwrap-----
    |  |       |      Steam Runtime 2
    |  |       |
    |  |       \- Proton, if used
    |  |          \- The game

  * Graphics driver comes from one of:
      - the Flatpak runtime (this is what is implemented so far)
      - the host system
  * glibc comes from:
    *newest*(where graphics driver comes from, Steam Runtime)
  * Libraries used by graphics driver come from:
    *newest*(where graphics driver comes from, Steam Runtime)
  * Other libraries come from: Steam Runtime
  * User's home directory comes from one of:
      - host system, unrestricted
      - ~/.var/app/com.valvesoftware.Steam (this is what is implemented so far)
      - a private directory like ~/.var/app/com.steampowered.App440 per game

Entirely solves:

  * i386 games work on non-i386 hosts
      - If the graphics driver comes from the Flatpak runtime
  * i386 games continue to work on i386-capable hosts
      - If the graphics driver comes from the Flatpak runtime

Mostly solves:

  * Old games continue to work
      - If graphics driver comes from the Flatpak runtime
  * New runtimes do not require newest host system
  * Open-source (Mesa) graphics drivers continue to work
  * Proprietary (NVIDIA) graphics drivers continue to work
  * New runtimes do not require extensive patching
  * New runtimes work on future hardware
  * Security boundary between desktop and games
      - Dependent on sandboxing parameters

Only partially solves:

  * Games run in a predictable, robust environment
  * Old games continue to work
      - If graphics driver comes from the host system
  * i386 games continue to work on i386-capable hosts
      - If graphics driver comes from the host system

Does not solve:

  * Games developed in an impure scout environment continue to work
  * Games that inappropriately bundle libraries work anyway
  * i386 games work on non-i386 hosts
      - If the graphics driver comes from the host system
  * Security boundary between Steam client and games
      - Dependent on sandboxing parameters, but a security boundary is
        not currently implemented

### Steam Runtime 2 container with `LD_LIBRARY_PATH` runtime inside

This design is used by the "Steam Linux Runtime" compatibility
tool since mid July 2021, when combined with Flatpak 1.11.1 or later.

    |----------------------------
    |                    Host system
    |
    |  flatpak-portal service <===== IPC from pressure-vessel-wrap
    |       |
    |  |----\-bwrap-----
    |  |       |      Steam Runtime 2
    |  |       |
    |  |   |- -\-run.sh - - - - - - - - - - - -
    |  |   .      |   steam-runtime scout
    |  |   .      |
    |  |   .      \- Proton, if used
    |  |   .         \- The game

  * Graphics driver comes from one of:
      - the Flatpak runtime (this is what is implemented so far)
      - the host system
  * glibc comes from:
      - *newest*(where graphics driver came from, Steam Runtime 2)
  * Libraries used by graphics driver come from:
      - *newest*(where graphics driver came from, Steam Runtime 2, scout)
  * Other libraries come from:
    *newest*(Steam Runtime 2, scout)
    (in practice this is Steam Runtime 2, except when a SONAME no longer
    exists, in which case we use the scout version)
  * User's home directory comes from one of:
      - host system, unrestricted
      - ~/.var/app/com.valvesoftware.Steam (this is what is implemented so far)
      - a private directory like ~/.var/app/com.steampowered.App440 per game

Entirely solves:

  * i386 games work on non-i386 hosts
      - If the graphics driver comes from the Flatpak runtime

Mostly solves:

  * Old games continue to work
      - Expected to be fewer regressions than with pure scout container
  * i386 games continue to work on i386-capable hosts
      - Expected to be fewer regressions than with pure scout container
  * Games developed in an impure scout environment continue to work
  * Open-source (Mesa) graphics drivers continue to work
  * Proprietary (NVIDIA) graphics drivers continue to work
  * Games run in a predictable, robust environment
  * Security boundary between desktop and games
      - Dependent on sandboxing parameters

Does not solve:

  * Games that inappropriately bundle libraries work anyway
  * i386 games work on non-i386 hosts
      - If the graphics driver comes from the host system
  * Security boundary between Steam client and games
      - Dependent on sandboxing parameters, but a security boundary is
        not currently implemented

### Flatpak runtime container with `LD_LIBRARY_PATH` runtime inside

Flatpak can theoretically support this, but pressure-vessel does not
currently implement this mode, because using the Steam Runtime 2 container
is expected to have better compatibility.

    |----------------------------
    |                    Host system
    |
    |  flatpak-portal service <===== IPC from pressure-vessel
    |       |
    |  |----\-Flatpak/bwrap--------------------
    |  |       |      org.freedesktop.Platform//20.08
    |  |       |
    |  |   |- -\-run.sh - - - - - - - - - - - -
    |  |   .      |   Steam Runtime 1
    |  |   .      |
    |  |   .      \- The game

  * glibc comes from: org.freedesktop.Platform
  * Graphics driver comes from: org.freedesktop.Platform extensions
  * Libraries used by graphics driver come from:
    *newest*(org.freedesktop.Platform, Steam Runtime)
  * Other libraries come from:
    *newest*(org.freedesktop.Platform, Steam Runtime),
    except in a few cases where Steam Runtime libraries might be preferred
    due to known incompatibilities between the same SONAME in the
    Steam Runtime and org.freedesktop.Platform
  * User's home directory comes from one of:
      - host system, unrestricted
      - ~/.var/app/com.valvesoftware.Steam
      - a private directory like ~/.var/app/com.steampowered.App440 per game

Entirely solves:

  * i386 games work on non-i386 hosts
  * i386 games continue to work on i386-capable hosts
  * Games cannot accidentally break the Steam client

Mostly solves:

  * Old games continue to work
      - There can be regressions if library behaviour in o.fd.Platform changes
  * Games developed in an impure scout environment continue to work
      - We can use the same workarounds as the Flatpak Steam app
  * Open-source (Mesa) graphics drivers continue to work
  * Proprietary (NVIDIA) graphics drivers continue to work
  * Games run in a predictable, robust environment
      - Could get broken once a year by a new Flatpak Platform, but if so,
        it will be broken for everyone (easier to diagnose)
      - Could get broken by updated graphics driver extension
  * New runtimes do not require newest host system
  * New runtimes work on future hardware
  * Security boundary between desktop and games
      - Dependent on sandboxing parameters

Only partially solves:

  * Games that inappropriately bundle libraries work anyway
  * Security boundary between Steam client and games
      - Dependent on sandboxing parameters

Does not solve:

  * New runtimes do not require extensive patching

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
      - In practice this is a losing battle, because 2021 Arch and
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
