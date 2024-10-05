steam runtime SDK
=================

A binary compatible runtime environment for Steam applications on Linux.

Introduction
------------

The Linux version of Steam runs on many Linux distributions, ranging
from the latest rolling-release distributions like Arch Linux to older
LTS distributions like Ubuntu 14.04.
To achieve this, it uses a special library stack, the *Steam Runtime*,
which is installed in `~/.steam/root/ubuntu12_32/steam-runtime`.
This is Steam Runtime version 1, codenamed `scout` after the Team
Fortress 2 character class.

The Steam client itself is run in an environment that adds the shared
libraries from Steam Runtime 1 'scout' to the library loading path,
using the `LD_LIBRARY_PATH` environment variable.
This is referred to as the [`LD_LIBRARY_PATH` runtime][LD_LIBRARY_PATH runtime].
Most native Linux games available through Steam are also run in this
environment.

A newer approach to cross-distribution compatibility is to use Linux
namespace (container) technology, to run games in a more predictable
environment, even when running on an arbitrary Linux distribution which
might be old, new or unusually set up.
This is implemented as a series of Steam Play compatibility tools, and
is referred to as the Steam [container runtime][], or as the
*Steam Linux Runtime*.

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
[steam-runtime-tools documentation]: https://gitlab.steamos.cloud/steamrt/steam-runtime-tools/-/tree/main/docs

## Why to use Steam Runtime SDK?


Ensures your application finds the correct libraries for smooth operation on different Linux systems.
Prevents conflicts between development libraries on your machine and the libraries your application needs.


## Understanding Steam Runtime SDK

The Steam Runtime SDK provides a development environment for building applications that run on Steam for Linux. It ensures compatibility across different Linux distributions.


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

## Installation


1. Download the SDK:

Container-Based:
Podman:

```bash 
sudo podman pull registry.gitlab.steamos.cloud/steamrt/scout/sdk
```

Docker:

```bash
sudo docker pull registry.gitlab.steamos.cloud/steamrt/scout/sdk
```

Chroot-Based:
Download the appropriate chroot image from the Steam Runtime repository: https://repo.steampowered.com/steamrt


2. Create a Container or Chroot Environment:

Podman:

```bash
podman run -it --rm --name steamrt-sdk registry.gitlab.steamos.cloud/steamrt/scout/sdk /bin/bash
```

Docker:

```bash
sudo docker run -it --rm --name steamrt-sdk registry.gitlab.steamos.cloud/steamrt/scout/sdk /bin/bash
```

Chroot: Follow the instructions provided with the downloaded chroot image.

Building in the runtime
-----------------------

To prevent libraries from development and build machines 'leaking'
into your applications, you should build within a Steam Runtime container
or chroot environment.

We recommend using a
[Toolbx](https://containertoolbx.org/),
[rootless Podman](https://github.com/containers/podman/blob/main/docs/tutorials/rootless_tutorial.md)
or [Docker](https://docs.docker.com/get-docker/)
container for this:

    podman pull registry.gitlab.steamos.cloud/steamrt/scout/sdk

or

    sudo docker pull registry.gitlab.steamos.cloud/steamrt/scout/sdk

For more details, please consult the
[Steam Runtime SDK](https://gitlab.steamos.cloud/steamrt/scout/sdk/-/blob/steamrt/scout/README.md)
documentation.

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
