# Requirements and goals for the Steam Runtime

This document summarizes actual and potential goals for how the Steam
client uses the Steam Runtime and containers to run itself and/or games.

For details of how the Steam Runtime works and how that influences which
of these goals are achieved, see
[Steam Runtime design models](possible-designs.md).

## Non-regression requirements

These are things that are already more or less true in the
`LD_LIBRARY_PATH` runtime, and need to remain more or less true.

### Old games continue to work

Older games like Half-Life and Portal, developed circa Ubuntu 12.04,
must work on modern systems like Ubuntu 20.04 without needing ongoing
maintenance.

This is particularly important in cases like Torchlight where the
original developer has gone out of business, so there will be no more
updates, however much we might hope there would be.

### i386 games continue to work on i386-capable hosts

Older games were compiled for the IA32 ABI (e.g. Debian i386).
They must work on modern x86-64 systems (e.g. Debian amd64), as long
as the modern system provides basic i386 packages like glibc and
graphics drivers.

### Games are deployed through steampipe

Valve is happy with steampipe as a deployment mechanism. Games will
not switch to some other deployment mechanism, e.g. libostree as used
by Flatpak.

### Games developed in an impure scout environment continue to work

Game developers were always meant to compile their games in a "pure"
scout environment (originally `schroot`, and more recently Docker) but
many did not do so. "Most" of these games should continue to work on
"most" modern host systems.

This is unlikely to be achievable for all games, and is more important
for higher-profile games.

### Host system doesn't need uncommon packages installed

The Steam client should have as few requirements on the host system
as possible.

Note that all modes of operation require udev rules for input devices
and uinput. These affect system security and need root to install, so
the most we can do from unprivileged software is to diagnose the problem.

### Open-source (Mesa) graphics drivers continue to work

If the host system has graphics hardware that is best-supported by
open-source drivers (in practice this normally means Intel iGPUs
or the AMD Radeon series), games should work on it.

For recent GPUs, this means the game must be able to use a suitably
recent driver version that supports the GPU: for example, we cannot
expect a 2021 GPU to be supported by a 2012 version of Mesa.

Meeting this goal is likely to be particularly problematic in designs
that would require us to compile a 2021 graphics driver in the 2012
runtime/SDK environment.

### Proprietary (NVIDIA) graphics drivers continue to work

If the host system has a graphics driver that we cannot legally
distribute, we should be able to keep games working anyway.

Now that AMD are using open-source drivers for the Radeon series,
our main use-case for proprietary graphics drivers is the NVIDIA
driver. This is not redistributable without specific permission
(Debian has permission, but the same is not true for all distributions),
and it must have its user-space part kept in lockstep with the kernel part.
(for example using the v430.40 kernel module with the v430.64 user-space
driver is not supported, and neither is the other way round).

## New goals

These are things that are mostly not true in the `LD_LIBRARY_PATH`
runtime. In some cases, we would like them to *become* true.
In other cases, third-party users and developers have these as goals,
but Valve do not consider them to be a priority.

### New runtimes

The Steam Runtime version 1, 'scout', is based on a 2012 version of
Ubuntu. The open source software stack has moved on since then, and
it should be possible to build new games against a newer runtime.

We already have a partial newer runtime (referred to as Steam Runtime
version 1½, 'heavy') which is used to run the `steamwebhelper`.
However, this is based on Debian 8 'jessie', released in 2015 (SteamOS 2
'brewmaster' is also based on Debian 8); this version was chosen to avoid
increasing the Steam client's minimum glibc requirements further than
was strictly necessary. This is a step forward, but if we are going to
introduce a new runtime for games and support it longer-term, we should
aim higher than 2015.

Steam Runtime version 2, 'soldier', is based on Debian 10 'buster',
released in 2019. It is used to run Proton 5.13 and later versions.
Running native Linux games in a "pure" soldier container is not
currently possible, but would be a good improvement.

Steam Runtime version 3, 'sniper', is based on Debian 11 'bullseye',
released in 2021. It is otherwise similar to soldier.

Similarly, Steam Runtime version 4, 'medic', is likely to be based on
Debian 12 'bookworm', which is expected to be released in 2023.

#### New glibc

One specific aspect of new runtimes that we need to be able to ship is
a newer version of glibc.

The `LD_LIBRARY_PATH` Steam Runtime cannot contain glibc, because:

* The path to [`ld.so(8)`][ld.so] is hard-coded into all executables
    (it is the ELF interpreter, part of the platform ABI), so we
    don't get to change it.

* The version of `ld.so` is coupled to `libdl.so.2`:
    they come from the same source package, and are allowed to assume
    that they are installed and upgraded in lockstep.

* Similarly, the version of `libdl.so.2` is coupled to the rest of glibc.

So, everything in the `LD_LIBRARY_PATH` Steam Runtime must be built for
a glibc at least as old as the oldest system that Steam supports. This
makes it difficult to advance beyond the Ubuntu 12.04-based 'scout'
runtime: everything that is updated effectively has to be backported to
Ubuntu 12.04.

To be able to replace glibc, the runtime needs to provide at least
`/usr`, `/lib*`, `/bin` and `/sbin`, like a Flatpak runtime does.

[ld.so]: https://linux.die.net/man/8/ld.so

### Games can be built in a container

It should be straightforward for game developers to build their games
in a "pure" Steam Runtime environment (for scout or any future Steam
Runtime of their choice).

### Games run in a predictable, robust environment

Games should not be broken by unexpected changes to the host system.
After a game works once, it should work essentially forever.

In particular we don't want to spend time debugging conflicts between the
Steam Runtime's idea of what should be in libpcre.so.3 and libcurl.so.4,
and the host system's.

#### Avoiding incompatibilities between libraries

Games can break when libraries claim to be compatible (by having the
same ELF `DT_SONAME`) but are in fact not compatible, for example:


- libcurl.so.4 linked to libssl 1.0 is not completely compatible with
    libcurl.so.4 linked to libssl 1.1

- The history of libcurl.so.4 in Debian/Ubuntu has involved two
   incompatible sets of versioned symbols, due to some decisions
   made in 2005 and 2007 that, with hindsight, were less wise than
   they appeared at the time

- Various libraries can be compiled with or without particular
    features and dependencies; if the version in the Steam Runtime
    has a feature, and the host system version is newer but does not
    have that feature, then games cannot rely on the feature

- In the worst-case, compiling a library without a particular
    feature or dependency can result in symbols disappearing from
    its ABI, resulting in games that reference those symbols crashing

- There is a fairly subtle interaction between libdbus,
    libdbusmenu-gtk, libdbusmenu-glib and Ubuntu's patched GTK 2
    that has resulted in these libraries being forced to be taken
    from the Steam Runtime, to avoid breaking the Unity dock

If we always take these libraries from the runtime, then incompatible
changes on the host system don't affect us.

### Games that inappropriately bundle libraries work anyway

Some games bundle private copies of libraries that also exist in the
Steam Runtime, or libraries that are dependencies of graphics drivers,
or even the graphics drivers themselves. These libraries bypass the
mechanisms that are intended to make sure games keep working.

For example, some games bundle a private copy of `libgcc_s.so.1` or
`libstdc++.so.6`, and Mesa graphics drivers also depend on those
libraries. If the game's bundled copy is older than the version that
the user's Mesa graphics driver requires, the game will crash or
otherwise fail to work.

The unofficial Flatpak Steam app on Flathub has a clever mechanism
involving `LD_AUDIT` that can prevent libraries bundled with games
from taking precedence over newer libraries from the Steam Runtime or
the host system.

### Games don't all have to use the same runtime

We need older games like Torchlight to keep using the old runtime
indefinitely, even if newer/more-updated games like DOTA2 switch to
a new runtime, and even if the Steam client itself switches to a
new runtime.

### Steam client runs in a predictable environment

The Steam client should not be broken by unexpected changes to the
host system.

### Steam client can use a newer runtime

The Steam client and the oldest games currently both use scout, the
oldest Steam Runtime, but I expect we will eventually want the Steam
client to switch to something more modern.

### New runtimes for games can be supported for multiple years

The basis for a new runtime should have upstream security support,
without compatibility breaks, for a few years. For example, Debian 10
or Ubuntu LTS would be suitable (they are supported for multiple years),
but non-LTS Ubuntu releases would not be suitable.

Even after upstream security support ends, we should be able to backport
critical security fixes to our version ourselves.

We do not necessarily require this for the runtime that is used to run
the Steam client itself: the Steam client is frequently updated and
versions older than the current general-availability version are not
supported, so if necessary the Steam client can have a flag-day that
increases its requirements to a newer runtime.

### New runtimes do not require newest host system

Games built for the new runtime might have higher minimum requirements
than Ubuntu 12.04, but they should work on ordinary non-bleeding-edge
distributions like Debian stable and Ubuntu LTS. Ideally they should
also work on Debian oldstable and Ubuntu old-LTS for a reasonable length
of time.

### New runtimes do not require rebuilding *everything*

We should be able to produce a new runtime reasonably often, for example
once per 2-4 years (1-2 Debian stable releases). To make this scale,
we should only need to build and maintain selected packages that we
are actively patching, but take unmodified packages directly from the
base distribution.

### New runtimes do not require extensive patching

To minimize the cost of maintaining a runtime, we shouldn't need to
patch a lot of packages (for example libraries that dlopen modules, like
GTK) to make them suitable for the Steam Runtime.

### New runtimes work on future hardware

When a now-new (let's say 2020) runtime has become outdated (let's say
2025 or 2030), games built against it must still work. This means it
must have access to graphics drivers for 2025 GPUs that had not yet been
invented when the runtime's base distribution was released.

### i386 games work on non-i386 hosts

Older games were compiled for the IA32 ABI (e.g. Debian i386).
They should work on modern x86-64 systems (e.g. Debian amd64) even
if the modern system *does not* provide basic i386 packages like
glibc and graphics drivers, as long as the container runtime *does*.

In particular, Canonical briefly planned to remove the i386 (IA32)
ABI from Ubuntu host systems, recommending use of Snap or LXD.
This would have meant that we could no longer rely on the host
system to give us i386 glibc and graphics drivers. Their plan has
now changed to reducing i386 to be a partial architecture
("second-class citizen" status), similar to the way 32-bit libraries
are handled in Arch Linux, which is good enough for our current needs.
However, it seems likely that other distributions will want to do
similarly in future.

### Game data is easy to sync and delete

If we restrict each game so it can only write to a finite number of
well-known locations, it's easy to upload all files from those
locations for Steam Cloud Sync, and/or delete them when the game is
uninstalled.

### Steam can be installed in a cross-distro way

Installing the Steam client should not be OS-specific:
we don't want to have to build `.deb` packages for Debian, Ubuntu
and SteamOS 2, `.rpm` packages for Fedora, *different* `.rpm` packages
for openSUSE, Pacman packages for Arch Linux and SteamOS 3, and so on.

### Steam can be installed unprivileged

Installing the Steam client should not require OS-level privileges,
and some users do not believe it should be able to run arbitrary code
as an administrator at all. If it does run arbitrary code, ideally they
should not be required to trust Valve: the privileged code that they
run should have been audited by someone who the user already has no
choice but to trust, such as their OS vendor.

For example, the maintainer scripts (preinst and postinst) in Debian
packages, and the scriptlets in RPM packages, run arbitrary code as root.

### Steam client cannot accidentally break the system

Some users want the Steam client to run in a "least-privilege" sandbox
so that bugs are mitigated. For example, if a shell script in the
Steam client accidentally runs `rm -fr /`, it should not be able to
delete the user's documents.

(This is weaker than a security boundary: it guards against mistakes,
not against malice.)

### Games cannot accidentally break the system

Some users want the games to run in a "least-privilege" sandbox
so that bugs are mitigated. For example, if a shell script in a game
accidentally runs `rm -fr /`, it should not be able to delete the
user's documents.

(This is weaker than a security boundary: it guards against mistakes,
not against malice.)

### Games cannot accidentally break the Steam client

Some users want the games to run in a "least-privilege" sandbox
so that bugs are mitigated. For example, if a shell script in a game
accidentally runs `rm -fr /`, it should only be able to delete that
game's data, not Steam client data.

(This is weaker than a security boundary: it guards against mistakes,
not against malice.)

### Security boundary between desktop and Steam client

Some users want the Steam client to run in a "least-privilege" sandbox
so that if it gets compromised, the impact is mitigated. For example,
they do not want it to be possible for the Steam client to read personal
documents, or execute arbitrary code that can do so.

This is not the same as saying that *games* are untrusted, although
the same people probably want both.

### Security boundary between desktop and games

Some users want Steam games to run in a "least-privilege" sandbox so
that if they are malicious or compromised, the impact is mitigated. For
example, they do not want it to be possible for Steam games to read
personal documents, or execute arbitrary code that can do so.

This is particularly interesting if game mods are installed.

This is not the same as saying that the *Steam client* is untrusted,
although the same people probably want both.

### Security boundary between Steam client and games

While we're thinking about least-privilege, it also seems desirable
that if Steam games are malicious or compromised, the impact is mitigated.
For example, a malicious game should not be able to spend money via the
Steam client.

Again, this is particularly interesting if game mods are installed.
