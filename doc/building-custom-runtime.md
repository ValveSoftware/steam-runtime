# Building your own version of the Steam Runtime

Steam ships with a copy of the Steam Runtime, and all Steam Applications
are launched within the runtime environment.

For some scenarios, you
may want to test an application with a different build of the runtime.
This is unsupported: the only build of the runtime that is available
for Steam users is the one in `~/.steam/root/ubuntu12_32`.

## Downloading a Steam Runtime

Current and past versions of the Steam Runtime are available from
<https://repo.steampowered.com/steamrt-images-scout/snapshots/>.
Beta builds, newer than the one included with Steam, are sometimes
available from the same location. The versioned directory names correspond
to the `version.txt` found in official Steam Runtime builds, typically
`ubuntu12_32/steam-runtime/version.txt` in a Steam installation.
The file `steam-runtime.tar.xz` in each directory contains the Steam
Runtime. It unpacks into a directory named `steam-runtime/`.

Each directory also contains various other archive and metadata files,
and a `sources/` subdirectory with source code for all the packages that
went into this Steam Runtime release.

## Building your own Steam Runtime variant

For advanced use, you can use the **build-runtime.py** script to build
your own runtime. To get a Steam Runtime in a directory, run a command
like:

    ./build-runtime.py --output=$(pwd)/runtime

The resulting directory is similar to the `ubuntu12_32/steam-runtime`
directory in a Steam installation.

To get a Steam Runtime in a compressed tar archive for easy transfer to
other systems, similar to the official runtime deployed with the
Steam client, use a command like:

    ./build-runtime.py --archive=$(pwd)/steam-runtime.tar.xz

To output a tarball and metadata files with automatically-generated
names in a directory, specify the name of an existing directory, or a
directory to be created with a `/` suffix:

    ./build-runtime.py --archive=$(pwd)/archives/

or to force a particular basename to be used for the tar archive and all
associated metadata files, end with `.*`, which will usually need to be
quoted to protect it from shell interpretation:

    ./build-runtime.py --archive="$(pwd)/archives/steam-runtime.*"

The archive will unpack into a directory named `steam-runtime`.

The `--archive` and `--output` options can be combined, but at least one
is required.

Run `./build-runtime.py --help` for more options.

## Using a Steam Runtime

Once the runtime is downloaded (and unpacked into a directory, if you used
an archive), you can set up library pinning by running the **setup.sh** script,
then you can use the **run.sh** script to launch any program within that
runtime environment.

For example, to get diagnostic information using the same tool used to get
what appears in Help -> System Information in Steam, if your runtime is in
'~/rttest', you could run:

    ~/rttest/setup.sh
    ~/rttest/run.sh ~/rttest/usr/bin/steam-runtime-system-info

Or to launch Steam itself (and any Steam applications) within your runtime,
set the `STEAM_RUNTIME` environment variable to point to your runtime directory;

    ~/.local/share/Steam$ STEAM_RUNTIME=~/rttest ./steam.sh
    Running Steam on ubuntu 14.04 64-bit
    STEAM_RUNTIME has been set by the user to: /home/username/rttest
