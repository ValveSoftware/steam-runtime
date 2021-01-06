Common issues and workarounds
=============================

Some issues involving the SteamLinuxRuntime framework and the
pressure-vessel container-launcher are not straightforward to fix.
Here are some that are likely to affect multiple users:

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
