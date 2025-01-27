Steam Runtime
=============

A binary compatible runtime environment for Steam applications on Linux.

Introduction
------------

The Linux version of Steam runs on many Linux distributions, ranging
from the latest rolling-release distributions like Arch Linux to older
LTS distributions like Ubuntu 16.04.
To achieve this, it uses a special library stack, the *Steam Runtime*.

The original version of the Steam Runtime is installed in
`~/.steam/root/ubuntu12_32/steam-runtime`.
This is Steam Runtime version 1, codenamed `scout` after the Team
Fortress 2 character class.
The Steam client itself is run in an environment that adds the shared
libraries from Steam Runtime 1 'scout' to the library loading path,
using the `LD_LIBRARY_PATH` environment variable:
this is referred to as the [`LD_LIBRARY_PATH` runtime][LD_LIBRARY_PATH runtime].

A newer approach to cross-distribution compatibility is to use Linux
namespace (container) technology, to run games in a more predictable
environment, even when running on an arbitrary Linux distribution which
might be old, new or unusually set up.
This is implemented as a series of Steam Play compatibility tools, and
is referred to as the Steam [container runtime][], or as the
*Steam Linux Runtime*.

Newer native Linux games such as Counter-Strike 2 and Dota 2
run in an environment referred to as `Steam Linux Runtime 3.0 (sniper)`,
which is a [Steam Runtime 3 'sniper'][sniper] container.
This is the recommended environment for developers of new native Linux games.
To target this environment,
developers should compile their games in the [sniper SDK][],
then set up a Launch Option that supports Linux,
and use the Installation → Linux Runtime menu item in the Steamworks
partner web interface to select the sniper runtime.

Older native Linux games normally run in an environment referred to as
`Steam Linux Runtime 1.0 (scout)`, which is a
[Steam Runtime 2 'soldier'][soldier] container combined with the
Steam Runtime 1 'scout' [`LD_LIBRARY_PATH` runtime][LD_LIBRARY_PATH runtime].
They can also be switched to run in an environment referred to as
`Legacy runtime 1.0`, which is the Steam Runtime 1 'scout' `LD_LIBRARY_PATH`
runtime used on its own.
To target either of these environments,
developers should compile their games in the [scout SDK][].
For backwards compatibility,
this is still the default when a developer publishes a native Linux game,
but we now recommend that developers should target sniper instead.

The Steam Runtime is also used by the [Proton][] Steam Play compatibility
tools, which run Windows games on Linux systems.
Older versions of Proton (5.0 or earlier) use the same 'scout'
[`LD_LIBRARY_PATH` runtime][LD_LIBRARY_PATH runtime] as most native
Linux games.
Newer versions of Proton (5.13 or newer) use a [container runtime][]
with newer library versions: this is Steam Runtime version 2, codenamed
'soldier'.

More information about the
[`LD_LIBRARY_PATH` runtime][LD_LIBRARY_PATH runtime] and
[container runtime][] is available as part of the
[steam-runtime-tools documentation][].

[LD_LIBRARY_PATH runtime]: https://gitlab.steamos.cloud/steamrt/steam-runtime-tools/-/blob/main/docs/ld-library-path-runtime.md
[container runtime]: https://gitlab.steamos.cloud/steamrt/steam-runtime-tools/-/blob/main/docs/container-runtime.md
[Proton]: https://github.com/ValveSoftware/Proton/
[scout SDK]: https://gitlab.steamos.cloud/steamrt/scout/sdk
[sniper]: https://gitlab.steamos.cloud/steamrt/steamrt/-/blob/steamrt/sniper/README.md
[sniper SDK]: https://gitlab.steamos.cloud/steamrt/sniper/sdk
[soldier]: https://gitlab.steamos.cloud/steamrt/steamrt/-/blob/steamrt/soldier/README.md
[steam-runtime-tools documentation]: https://gitlab.steamos.cloud/steamrt/steam-runtime-tools/-/tree/main/docs

Reporting bugs and issues
-------------------------

Please report issues to the [steam-runtime issue tracker][].

The container runtimes have some [known issues][] which do not need to be
reported again.

The container runtime is quite complicated, so we will need
[additional information][reporting bugs] to be able to make progress
on resolving issues.

[steam-runtime issue tracker]: https://github.com/ValveSoftware/steam-runtime
[known issues]: doc/steamlinuxruntime-known-issues.md
[reporting bugs]: doc/reporting-steamlinuxruntime-bugs.md

Steam-runtime Repository
------------------------

The Steam-runtime SDK relies on an APT repository that Valve has created that holds the packages contained within the steam-runtime. A single package, steamrt-dev, lists all the steam-runtime development packages (i.e. packages that contain headers and files required to build software with those libraries, and whose names end in -dev) as dependencies. Conceptually, a base chroot environment is created in the traditional way using debootstrap, steamrt-dev is then installed into this, and then a set of commonly used compilers and build tools are installed. It is expected that after this script sets the environment up, developers may want to install other packages / tools they may need into the chroot environment.
If any of these packages contain runtime dependencies, then you will have to make sure to satisfy these yourself, as only the runtime dependencies of the steamrt-dev packages are included in the steam-runtime. 

Installation
------------

Steam Runtime version 1, 'scout' is automatically installed as part
of the [Steam Client for Linux][].

Each version of the Steam [container runtime][] is automatically
downloaded to your Steam library if you install a game or a version of
Proton that requires it.
They can also be downloaded by opening `steam://` links with Steam:

* Steam Linux Runtime 1.0 (scout): `steam steam://install/1070560`
* Steam Linux Runtime 2.0 (soldier): `steam steam://install/1391110`
* Steam Linux Runtime 3.0 (sniper): `steam steam://install/1628350`

All the software that makes up the Steam Runtime is available in both source and binary form in the Steam Runtime repository [https://repo.steampowered.com/steamrt](https://repo.steampowered.com/steamrt "")

Included in this repository are scripts for building local copies of the Steam Runtime for testing and scripts for building Linux chroot environments suitable for building applications.

[Steam Client for Linux]: https://github.com/ValveSoftware/steam-for-linux/

Building in the runtime
-----------------------

To prevent libraries from development and build machines 'leaking'
into your applications, you should build within a Steam Runtime container.

We recommend using a
[Toolbx](https://containertoolbx.org/),
[Distrobox](https://distrobox.it/),
[rootless Podman](https://github.com/containers/podman/blob/main/docs/tutorials/rootless_tutorial.md)
or [Docker](https://docs.docker.com/get-docker/)
container for this.
All of these environments are compatible with the official Steam Runtime
SDK images,
which we provide in OCI format.

If targeting Steam Linux Runtime 3.0 'sniper',
please consult the
[Steam Runtime 3 'sniper' SDK](https://gitlab.steamos.cloud/steamrt/sniper/sdk/-/blob/steamrt/sniper/README.md)
documentation for details.

If targeting the legacy 'scout' runtime,
please consult the
[Steam Runtime 1 'scout' SDK](https://gitlab.steamos.cloud/steamrt/scout/sdk/-/blob/steamrt/scout/README.md)
documentation instead.

### Using a debugger in the build environment

To get the detached debug symbols that are required for `gdb` and
similar tools, you can download the matching
`com.valvesoftware.SteamRuntime.Sdk-amd64,i386-scout-debug.tar.gz`,
unpack it (preserving directory structure), and use its `files/`
directory as the schroot or container's `/usr/lib/debug`.

For example, with Docker, you might unpack the tarball in
`/tmp/scout-dbgsym-0.20191024.0` and use something like:

    sudo docker run \
    --rm \
    --init \
    -v /home:/home \
    -v /tmp/scout-dbgsym-0.20191024.0/files:/usr/lib/debug \
    -e HOME=/home/user \
    -u $(id -u):$(id -g) \
    -h $(hostname) \
    -v /tmp:/tmp \
    -it \
    steamrt_scout_amd64:latest \
    /dev/init -sg -- /bin/bash

or with schroot, you might create
`/var/chroots/steamrt_scout_amd64/usr/lib/debug/` and move the contents
of `files/` into it.

Using detached debug symbols
----------------------------

Please see [doc/debug-symbols.md](doc/debug-symbols.md).
