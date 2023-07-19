Reporting SteamLinuxRuntime bugs
================================

The Steam Linux container runtime runs each game in a container.

It consists of:

* pressure-vessel, a container launching tool
* a *runtime*, providing a set of libraries for games to use

There are currently three runtimes available:

* [Steam Runtime 3 'sniper'](https://gitlab.steamos.cloud/steamrt/steamrt/-/blob/steamrt/sniper/README.md),
    [app ID 1628350](https://steamdb.info/app/1628350/)
    is used to run a few native Linux games such as Battle for Wesnoth
    (1.17.x branch) and Retroarch.
    We expect it to be used for other newer native Linux games in future.

* [Steam Runtime 2 'soldier'](https://gitlab.steamos.cloud/steamrt/steamrt/-/blob/steamrt/soldier/README.md),
    [app ID 1391110](https://steamdb.info/app/1391110/)
    is used to run official releases of Proton 5.13 or newer.

    It is also used to run native Linux games that target
    Steam Runtime 1 'scout', if the "Steam Linux Runtime" compatibility
    tool is selected for them.

* [Steam Runtime 1 'scout'](https://gitlab.steamos.cloud/steamrt/steamrt/-/blob/steamrt/scout/README.md),
    [app ID 1070560](https://steamdb.info/app/1070560/)
    can be used on an opt-in basis to run native Linux games in a
    container. It uses the same libraries as the traditional
    `LD_LIBRARY_PATH` runtime, but instead of using them as an overlay
    over the host machine, they are used as an overlay over a
    Steam Runtime 2 'soldier' container.

Unofficial third-party builds of Proton might use the container runtime
like the official Proton 5.13, or they might use the traditional
`LD_LIBRARY_PATH` runtime like the official Proton 5.0, or they might
do something else entirely. We cannot provide support for unofficial
builds of Proton.

The list of [known issues](steamlinuxruntime-known-issues.md) describes
some issues that cannot be fixed immediately, with workarounds where
available.

If you encounter other issues, please report them to the Steam Runtime's
issue tracker: <https://github.com/ValveSoftware/steam-runtime/issues>.

Essential information
---------------------

We will need to know some information about your system. Please make sure
to include full system information (*Help -> System Information*) in your
report. If the text ends with a line like "The runtime information tool
is preparing a report, please wait...", please wait for it to be
replaced by the full version of the report.

When reporting bugs in the container runtime, please include a debug
log. Since version 0.20210105.0, the easiest way to get this is:

* Completely exit from Steam

* Run a terminal emulator such as GNOME Terminal, Konsole or xterm

* Run Steam with the `STEAM_LINUX_RUNTIME_LOG` environment variable
    set to 1, for example:

        STEAM_LINUX_RUNTIME_LOG=1 steam

    You can leave Steam running with this setting permanently if you're
    testing multiple games.

* Run the game, or do whatever else is necessary to reproduce the bug

* Find the Steam Library directory where the runtime is installed,
    typically `~/.local/share/Steam/steamapps/common/SteamLinuxRuntime_soldier`
    for soldier

* Version numbers for some important runtime components are in `VERSIONS.txt`

* The log file is in the `var/` directory and named `slr-app*-*.log`
    for Steam games, or `slr-non-steam-game-*.log` if we cannot identify
    a Steam app ID for the game.

* For native Linux games that use scout, the version number in
    `~/.steam/root/ubuntu12_32/steam-runtime/version.txt is also important

For Proton games, you can combine this with `PROTON_LOG=1` to capture a
Proton log file too.

For Proton games, putting `STEAM_LINUX_RUNTIME_LOG=1` in the game's
*Launch Options* will not give us all the information we need, so please
set it globally as described here.

You can censor the system information and the log (usernames, directory
names etc.) if you need to, as long as it's obvious what you have
edited. For example, replacing names with `XXX` or `REDACTED` is OK.
If your report contains information about more than one Steam Library
directory, please keep it obvious that they are different - for example
replace one with `/media/REDACTED1` and the other with
`/media/REDACTED2` in a consistent way.

### Older method

If pressure-vessel is crashing on startup and does not produce a log,
please do this instead:

* Completely exit from Steam

* Run a terminal emulator such as GNOME Terminal, Konsole or xterm

* Run Steam with the `PRESSURE_VESSEL_VERBOSE` environment variable
    set to 1

* Capture Steam's output in a file

* Run the game, or do whatever else is necessary to reproduce the bug

* Exit from Steam

For example, this command will leave Steam output in a file named
`pressure-vessel.log` in your home directory:

    PRESSURE_VESSEL_VERBOSE=1 steam 2>&1 | tee ~/pressure-vessel.log

Again, doing this via the *Launch Options* does not provide all the
information we need for Proton games.

Using a beta or an older version
--------------------------------

Several branches of the Steam Linux Runtime are available. You can
select a different branch from your Steam Library, in the same way
you would for a game: follow the same procedure as
<https://support.steampowered.com/kb_article.php?ref=9847-WHXC-7326>,
but instead of the properties of CS:GO, change the properties of the
tool named *Steam Linux Runtime - sniper*, *Steam Linux Runtime - soldier*
or *Steam Linux Runtime*.

The branches that are usually available are:

* The default branch (SteamDB calls this `public`) is the recommended
    version for most people.

* The `client_beta` branch can be used to get a preview of what will
    be in the next update to the default branch. It is either the same
    as the default branch, or a bit newer.

    Please use this in conjunction with the
    [Steam Client beta](https://support.steampowered.com/kb_article.php?ref=7021-eiah-8669),
    because it will sometimes rely on new Steam Client features that are not
    yet available in the non-beta client.

    If this branch doesn't work, please report a bug, then switch to
    the default branch.

* The `previous_release` branch is an older version of the default
    branch. Only use this if the default branch is not working for you,
    and please report it as a bug if that happens.

If something works in one branch but fails in another branch, that's
very useful information to include in issue reports. Please be as clear
as you can about which version works and which version fails. You can
check the current version by looking at
`SteamLinuxRuntime_sniper/VERSIONS.txt`,
`SteamLinuxRuntime_soldier/VERSIONS.txt` or
`SteamLinuxRuntime/VERSIONS.txt`.

It is very useful if you can show us a System Information report and a
log for the version that fails, then switch to the version that works
(without changing anything else!) and capture a new System Information
report and a new log, so that we can compare them.

Common issues and workarounds
-----------------------------

See the list of [known issues](steamlinuxruntime-known-issues.md).

Even more logging
-----------------

Steam and pressure-vessel developers might also ask you to run Steam
with `STEAM_LINUX_RUNTIME_VERBOSE=1`, `PRESSURE_VESSEL_VERBOSE=1`,
`CAPSULE_DEBUG=all` or `G_MESSAGES_DEBUG=all`, which produce
even more debug logging that is sometimes useful.

Advanced debugging
------------------

If you know your way around a Linux system, including using terminal
commands, there are a few things you can try to help us get more
information about games that aren't working.

### <a name="test-ui" id="test-ui">The test-UI (steam-runtime-launch-options)</a>

pressure-vessel has a very basic user interface for testing and debugging.
This is a control panel for advanced options, most of which will break
games - if they were ready for general use, we would have enabled them
for everyone already. Use it at your own risk!

To enable this, install PyGObject and the GLib and GTK 3
GObject-Introspection data (that's `python3-gi` and `gir1.2-gtk-3.0` on
Debian-derived systems), then set a game's launch options to:

    steam-runtime-launch-options -- %command%

This mode does not work in situations where pressure-vessel would have
been run non-interactively, such as for *Help -> System Information*
and Proton games.

### Getting a shell inside the container

pressure-vessel has a mode where it will run an `xterm` instead of the
game, so that you can explore the container interactively. To enable
this, run Steam with the `PRESSURE_VESSEL_SHELL` environment variable
set to `instead`, or set *Run an interactive shell* to
*Instead of running the command* in [the test-UI](#test-ui).

Inside the shell, the special array variable `$@` is set to the command
that would have been used to run the game. You can use `"$@"` (including
the double quotes!) to run the game inside the interactive shell.

This mode does not work in situations where pressure-vessel would have
been run non-interactively, such as for *Help -> System Information*.
It partially works for Proton games: the shell will not open until the
game's setup commands have finished.

### Changing the runtime version

If you download a file named
`com.valvesoftware.SteamRuntime.Platform-amd64,i386-soldier-runtime.tar.gz`
from <https://repo.steampowered.com/steamrt-images-soldier/snapshots/>,
you can use it as a runtime instead of the one provided by Steam.
Create a new directory in `SteamLinuxRuntime_soldier`, for example
`SteamLinuxRuntime_soldier/my_soldier_platform_0.20200604.0`,
and unpack the tarball into that directory so that you have files like
`SteamLinuxRuntime_soldier/my_soldier_platform_0.20200604.0/metadata` and
`SteamLinuxRuntime_soldier/my_soldier_platform_0.20200604.0/files/bin/env`.
Then select it from the list of runtimes in [the test-UI](#test-ui).

For the "Steam Linux Runtime" scout environment, the closest equivalent
is to download a file named `steam-runtime.tar.xz` from
from <https://repo.steampowered.com/steamrt-images-scout/snapshots/>
and unpack it into the `SteamLinuxRuntime` directory, so that you have
files like `SteamLinuxRuntime/steam-runtime/version.txt`. This will be
used in preference to the scout runtime that comes with Steam.

### SDK runtimes

If you download a file named
`com.valvesoftware.SteamRuntime.Sdk-amd64,i386-soldier-runtime.tar.gz`
from <https://repo.steampowered.com/steamrt-images-soldier/snapshots/>,
you can use it as a runtime. Create a new directory in
`SteamLinuxRuntime_soldier`, for example `SteamLinuxRuntime_soldier/my_soldier_sdk_0.20200604.0`,
and unpack the tarball into that directory so that you have files like
`SteamLinuxRuntime_soldier/my_soldier_sdk_0.20200604.0/metadata` and
`SteamLinuxRuntime_soldier/my_soldier_sdk_0.20200604.0/files/bin/env`.
Then select it from the list of runtimes in [the test-UI](#test-ui).

The SDK has some basic debugging tools like `strace`, `gdb` and `busybox`,
as well as development tools like C compilers.

To get detached debugging symbols for `gdb` backtraces, download
`com.valvesoftware.SteamRuntime.Sdk-amd64,i386-soldier-debug.tar.gz` from
the same directory as the SDK runtime. Unpack it in a temporary location,
and rename its `files` directory to be `.../files/lib/debug` inside the
SDK runtime, so that you get a
`SteamLinuxRuntime_soldier/my_soldier_sdk_0.20200604.0/files/lib/debug/.build-id`
directory.

If you have detached debug symbols in `/usr/lib/debug` on your host
system, you can use those to analyze backtraces that involve libraries
that came from the host system, such as glibc and Mesa graphics drivers.
To do that, either merge your host system's `/usr/lib/debug` into the SDK's
`files/lib/debug`, or run `gdb` like this:

    gdb -iex \
    'set debug-file-directory /usr/lib/debug:/run/host/usr/lib/debug' \
    ...

This will work best if the host system also uses
build-ID-based detached debug symbols, like Debian and Fedora.

Alternatively, use versions of glibc and Mesa on the host system that
were built with `gcc -g` and not stripped, such as Debian packages
built with `DEB_BUILD_OPTIONS=nostrip`.
