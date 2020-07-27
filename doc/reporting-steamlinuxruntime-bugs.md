Reporting SteamLinuxRuntime bugs
================================

The Steam Linux container runtime (SteamLinuxRuntime, app ID 1070560)
runs each game in a container. It is under development, and probably
has bugs.

It consists of:

* pressure-vessel, a container launching tool
* the scout runtime, a set of libraries for games to use

Essential information
---------------------

We will need to know some information about your system. Please make sure
to include full system information (*Help -> System Information*) in your
report. Wait for the extended system infomation to be collected by Steam.

When reporting bugs in the container runtime, please include a debug
log:

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

You can censor the system information and the log (usernames, directory
names etc.) if you need to, as long as it's obvious what you have
edited. For example, replacing names with `XXX` or `REDACTED` is OK.
If your report contains information about more than one Steam Library
directory, please keep it obvious that they are different - for example
replace one with `/media/REDACTED1` and the other with
`/media/REDACTED2` in a consistent way.

Common issues and workarounds
-----------------------------

SteamLinuxRuntime cannot be used from inside the unofficial Flatpak
version of Steam. We hope to make this work in future, but it is likely
to need changes to both pressure-vessel and Flatpak.
Workaround: Don't use the Flatpak version of Steam, or if you do,
don't enable SteamLinuxRuntime.

pressure-vessel does not always do the right thing if games are
installed in different Steam Library directories. Workaround: if you
have enough disk space in your home directory, you could try
[moving games](https://www.howtogeek.com/269515/how-to-move-a-steam-game-to-another-drive-without-re-downloading-it/)
into Steam's default library directory, `~/.steam/steam/steamapps`,
or another library directory that is mounted inside your home directory.
If that workaround is successful, please say so in your issue report.

If a game has Steam Workshop support and is installed outside your
home directory, it will not find the Steam Workshop content.
Workaround: Move it to your home directory, as above.
([#257](https://github.com/ValveSoftware/steam-runtime/issues/257))

Native Wayland graphics are not currently supported. Workaround:
Have Xwayland running (or use an environment like GNOME that does this
automatically), and don't set `SDL_VIDEODRIVER`, so that SDL will default
to using X11 via Xwayland.
([#232](https://github.com/ValveSoftware/steam-runtime/issues/232))

Non-Steam games are not currently supported.
Workaround: don't use SteamLinuxRuntime for those games yet.
([#228](https://github.com/ValveSoftware/steam-runtime/issues/228))

Unusual directory layouts and `ld.so` names are not supported.
SteamOS, the Debian/Ubuntu family, the Fedora/CentOS/Red Hat family,
Arch Linux and openSUSE are most likely to work.
Exherbo is known not to work.
Workaround: don't enable SteamLinuxRuntime on OSs with unusual
directory layouts.
([#230](https://github.com/ValveSoftware/steam-runtime/issues/230))

Games that put their content in a subdirectory, like *Estranged: Act I*,
don't currently start.
Workaround: don't use SteamLinuxRuntime for those games yet.
([#236](https://github.com/ValveSoftware/steam-runtime/issues/236))

Game Maker games such as Undertale and Danger Gazers don't start,
because they assume that newer Debian/Ubuntu libraries are available.
Workaround: don't use SteamLinuxRuntime for those games yet.
([#216](https://github.com/ValveSoftware/steam-runtime/issues/216),
[#235](https://github.com/ValveSoftware/steam-runtime/issues/235))

Haxe games such as Evoland Legendary Edition don't start,
because they assume that newer Debian/Ubuntu libraries are available.
Workaround: don't use SteamLinuxRuntime for those games yet.
([#224](https://github.com/ValveSoftware/steam-runtime/issues/224))

Feral Interactive ports such as Shadow of the Tomb Raider and Dirt 4
don't start, because they assume that the original `LD_LIBRARY_PATH`
version of the runtime is used, and try to re-launch themselves in that
environment. These games are likely to need modification to detect the
SteamLinuxRuntime and work normally there.
Workaround: don't use SteamLinuxRuntime for those games yet.
([#202](https://github.com/ValveSoftware/steam-runtime/issues/202),
[#249](https://github.com/ValveSoftware/steam-runtime/issues/249))

Even more logging
-----------------

Steam and pressure-vessel developers might also ask you to run Steam
with `CAPSULE_DEBUG=all` or `G_MESSAGES_DEBUG=all`, which produce
even more debug logging that is sometimes useful.

Advanced debugging
------------------

If you know your way around a Linux system, including using terminal
commands, there are a few things you can try to help us get more
information about games that aren't working.

### <a name="test-ui" id="test-ui">The test-UI</a>

pressure-vessel has a very basic user interface for testing and debugging.
This is a control panel for advanced options, most of which will break
games - if they were ready for general use, we would have enabled them
for everyone already. Use it at your own risk!

To enable this, install PyGObject and the GLib and GTK 3
GObject-Introspection data (that's `python3-gi` and `gir1.2-gtk-3.0` on
Debian-derived systems), then run Steam with the `PRESSURE_VESSEL_WRAP_GUI`
environment variable set to `1`.

This mode does not work in situations where pressure-vessel would have
been run non-interactively, such as for *Help -> System Information*.

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

### Copying the runtime

pressure-vessel has a mode where it copies the runtime, using hard
links for efficiency, and then modifies the copy in-place to have the
contents we need. This is not the default yet, but it might be in future.

You can try this by creating a directory `.../SteamLinuxRuntime/var`,
and running Steam with the `PRESSURE_VESSEL_COPY_RUNTIME_INTO`
environment variable set to the absolute path to `.../SteamLinuxRuntime/var`.
The temporary runtimes will be in `.../SteamLinuxRuntime/var/tmp-*`,
and will be deleted the next time you run pressure-vessel (so there
will normally only be one at a time).

If your pressure-vessel version has this feature, [the test-UI](#test-ui)
will have a checkbox labelled *Create temporary runtime copy on disk*.

This mode allows the temporary runtime to be modified in-place. Be
careful to break the hard links (delete files and replace them), instead
of editing them in-place. (If you don't understand what that means, don't
modify the temporary runtime!)

### Changing the runtime version

If you download a file named
`com.valvesoftware.SteamRuntime.Platform-amd64,i386-scout-runtime.tar.gz`
from <https://repo.steampowered.com/steamrt-images-scout/snapshots/>,
you can use it as a runtime instead of the one provided by Steam.
Create a new directory in `SteamLinuxRuntime`, for example
`SteamLinuxRuntime/my_scout_platform_0.20200604.0`,
and unpack the tarball into that directory so that you have files like
`SteamLinuxRuntime/my_scout_platform_0.20200604.0/metadata` and
`SteamLinuxRuntime/my_scout_platform_0.20200604.0/files/bin/env`.
Then select it from the list of runtimes in [the test-UI](#test-ui).

### SDK runtimes

If you download a file named
`com.valvesoftware.SteamRuntime.Sdk-amd64,i386-scout-runtime.tar.gz`
from <https://repo.steampowered.com/steamrt-images-scout/snapshots/>,
you can use it as a runtime. Create a new directory in
`SteamLinuxRuntime`, for example `SteamLinuxRuntime/my_scout_sdk_0.20200604.0`,
and unpack the tarball into that directory so that you have files like
`SteamLinuxRuntime/my_scout_sdk_0.20200604.0/metadata` and
`SteamLinuxRuntime/my_scout_sdk_0.20200604.0/files/bin/env`.
Then select it from the list of runtimes in [the test-UI](#test-ui).

The SDK has some basic debugging tools like `strace`, `gdb` and `busybox`,
as well as development tools like C compilers.

To get detached debugging symbols for `gdb` backtraces, download
`com.valvesoftware.SteamRuntime.Sdk-amd64,i386-scout-debug.tar.gz` from
the same directory as the SDK runtime. Unpack it in a temporary location,
and rename its `files` directory to be `.../files/lib/debug` inside the
SDK runtime, so that you get a
`SteamLinuxRuntime/my_scout_sdk_0.20200604.0/files/lib/debug/.build-id`
directory.

If you have detached debug symbols in `/usr/lib/debug` on your host
system, you can use those to analyze backtraces that involve libraries
that came from the host system, such as glibc and Mesa graphics drivers.
To do that, merge your host system's `/usr/lib/debug` into the SDK's
`files/lib/debug`. This will work best if the host system also uses
build-ID-based detached debug symbols, like Debian and Fedora.
Alternatively, use versions of glibc and Mesa on the host system that
were built with `gcc -g` and not stripped, such as Debian packages
built with `DEB_BUILD_OPTIONS=nostrip`.
