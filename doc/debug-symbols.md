# Using debug symbols in the Steam Runtime

If your game runs in the `LD_LIBRARY_PATH`-based Steam Runtime
environment, it is likely to be loading a mixture of libraries from the
host system and libraries from the Steam Runtime. In this situation,
debugging with tools like `gdb` benefits from having
[debug symbols][].

Like typical Linux operating system library stacks, the Steam Runtime
libraries do not contain debug symbols, to keep their size small; however,
they were compiled with debug symbols included, so we can make their
corresponding [detached debug symbols][] available for download.

The steps to attach a debugger to a game apply can in fact apply equally
to the Steam client itself.

[debug symbols]: https://en.wikipedia.org/wiki/Debug_symbol
[detached debug symbols]: https://sourceware.org/gdb/onlinedocs/gdb/Separate-Debug-Files.html

## Example scenario

Suppose you are using a SteamOS 2 'brewmaster' host system, and you are
having difficulty with the PulseAudio libraries, similar to
[steam-for-linux#4753][].

* Use a SteamOS 2 'brewmaster' host system
* Ensure that your Steam client is up to date
* Do not have `libpulse0:i386` or `libopenal1:i386` installed, so that
    the 32-bit `libpulse.so.0` and `libopenal.so.1` from the Steam Runtime
    will be used
* Run the Steam client in "desktop mode", from a terminal
* Put the Steam client in Big Picture mode, which makes it initialize
    PulseAudio
* Run a 32-bit game like [Floating Point][]
* Alt-tab to a terminal
* Locate the main Steam process with `pgrep steam | xargs ps`,
    or locate the main Floating Point process with `pgrep Float | xargs ps`.
    Let's say the process you are interested in is process 12345.
* Run a command like
    `gdb ~/.steam/root/ubuntu12_32/steam 12345` (for the Steam client)
    or `gdb ~/.steam/steam/steamapps/common/"Floating Point"/"Floating Point.x86" 12345`
    (for the game).
* In gdb: `set pagination off`
* In gdb: `thread apply all bt` to see a backtrace of each thread.
* At the time of writing, the Steam client has two threads that are
    calling `pa_mainloop_run()`, while Floating Point has one such thread.
    Because you don't have debug symbols for `libpulse.so.0`, these
    backtraces are quite vague, with no information about the source
    code file/line or about the function arguments.
* Exit from gdb so that the Steam client or the game can continue to run.

[Floating Point]: https://store.steampowered.com/app/302380
[steam-for-linux#4753]: https://github.com/ValveSoftware/steam-for-linux/issues/4753#issuecomment-280920124

## Getting the debug symbols for the host system

This is the same as it would be without Steam. For a Debian, Ubuntu or
SteamOS 2 host, `apt install libc6-dbg:i386` is a good start. For
non-Debian-derived OSs, use whatever is the OS's usual mechanism to get
detached debug symbols.

More OS-specific information:

* [Debian](https://wiki.debian.org/HowToGetABacktrace#Installing_the_debugging_symbols)
* [Ubuntu](https://wiki.ubuntu.com/Debug%20Symbol%20Packages)

## Getting the debug symbols for the Steam Runtime

Look in `~/.steam/root/ubuntu12_32/steam-runtime/version.txt` to see
which Steam Runtime you have. These instructions assume you are using
at least version 0.20190716.1. At the time of writing, the public stable
release is version 0.20191024.0.

Look in <https://repo.steampowered.com/steamrt-images-scout/snapshots/>
for a corresponding version of the Steam Runtime container builds.

Download
`com.valvesoftware.SteamRuntime.Sdk-amd64,i386-scout-debug.tar.gz` from
the matching build. Create a directory, for example
`/tmp/scout-dbgsym-0.20191024.0`, and untar the debug symbols tarball
into that directory.

The `/tmp/scout-dbgsym-0.20191024.0/files` directory is actually the
`/usr/lib/debug` from the SDK container, and has most of the debug
symbols that you will need.

## Re-running gdb

Run gdb the same as you did before, but this time use the `-iex` option
to tell it to set the new debug symbols directory before loading the
executable, for example:

    gdb -iex \
    'set debug-file-directory /tmp/scout-debug-0.20191024.0/files:/usr/lib/debug' \
    ~/.steam/root/ubuntu12_32/steam 12345

You will get some warnings about CRC mismatches, because gdb can now
see two versions of the debug symbols for some libraries. Those warnings
can safely be ignored: gdb does the right thing.

## Example scenario revisited

* Do the setup above
* Run a command like
    `gdb ~/.steam/root/ubuntu12_32/steam 12345` (for the Steam client)
    or `gdb ~/.steam/steam/steamapps/common/"Floating Point"/"Floating Point.x86" 12345`
    (for the game).
* In gdb: `set pagination off`
* In gdb: `thread apply all bt` to see a backtrace of each thread.
* At the time of writing, the Steam client has two threads that are
    calling `pa_mainloop_run()`, while Floating Point has one such thread.
    Now that you have debug symbols for `libpulse.so.0`, these backtraces
    are more specific, with the source file, line number and function
    arguments for calls into `libpulse.so.0`, and details of functions
    that are internal to `libpulse.so.0`.
* Similarly, for `start_thread()` in `libc.so.6` (which came from the host
    system), you should see file and line information from `libc6-dbg:i386`.
* If you use `info locals` or `thread apply all bt full`, you'll also see
    that you can even get information about local variables.
