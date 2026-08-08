# ezx

ZX Spectrum 48K/128K emulator written in Erlang.

Just for fun and as a proof of concept — exploring how far you can get with a functional language for real-time emulation.

## Features

- Runs both ZX Spectrum models — the classic 48K and the 128K.
- Windowed and fullscreen display, with border cropping if you want a cleaner picture.
- Sound: the iconic beeper plus the AY-3-8912 / YM2149 sound chips.
- Optional Kempston mouse.
- Loads games and snapshots in the common formats: SNA, Z80, TAP.
- Save your place anytime — quick save and named saves, so you can pick up where you left off.

Common shortcuts: `F2` save, `F3` load, `F5` quick save, `F9` quick load,
`F7` reset, `F11` fullscreen, `Ctrl+O` open, `Ctrl+P` pause, `Ctrl+M` mute.

## Build

Requires Erlang/OTP 25+ and rebar3.

```sh
rebar3 compile
```

## Run tests

```sh
rebar3 eunit
```

## Run

```sh
rebar3 shell
```

The `rebar.config` is configured to start the `ezx` application automatically in the shell.

Alternatively, from any Erlang shell:

```erlang
application:ensure_all_started(ezx).
```

## Build a release

A self-contained OTP release (with ERTS and wx bundled) is built with rebar3:

```sh
rebar3 release
```

The assembled release lives in `_build/default/rel/ezx`. Run it as a daemon
and control it with the generated script:

```sh
_build/default/rel/ezx/bin/ezx start
_build/default/rel/ezx/bin/ezx ping   # pong once the VM is up
_build/default/rel/ezx/bin/ezx stop
```

The node runs under the short name `ezx` (see `config/vm.args`); it must be
stopped before starting a second instance. The boot flags in `config/vm.args`
and the empty application config in `config/sys.config` are committed so a
fresh clone builds the same release.

Audio output requires the ALSA `aplay` command-line tool (from the
`alsa-utils` package on most distributions); it is spawned as the sound sink
when the UI starts. If `aplay` is not installed, the emulator still runs but
produces no sound. Install it with e.g. `sudo apt install alsa-utils`
(Debian/Ubuntu) or `sudo dnf install alsa-utils` (Fedora). On Windows the sink
is `sox` or `ffplay` instead — see the Windows notes below.

## Download / Install

Pre-built Linux x86_64 and Windows x86_64 releases are published on GitHub:
a Debian package and a self-contained tarball for Linux, and for Windows both
an installer (`ezx-setup-<version>.exe`) and a portable zip. None of them
needs Erlang/OTP on the target machine — the runtime is bundled.

**Debian/Ubuntu — .deb package:** download `ezx_<version>_amd64.deb` from the
[Releases][] page and install it:

```sh
sudo dpkg -i ezx_0.1.0_amd64.deb
```

This installs the emulator into `/opt/ezx`, adds an `ezx` command to
`/usr/bin`, and registers the `ezx` entry in the applications menu. Remove it
with `sudo apt remove ezx`.

**Other distros — tarball:** download `ezx-<version>-linux-x86_64.tar.gz`,
unpack it and either run it in place (`./ezx`) or install it system-wide:

```sh
tar xzf ezx-<version>-linux-x86_64.tar.gz
cd ezx-<version>-linux-x86_64
sudo ./install.sh      # -> /opt/ezx + menu entry + /usr/local/bin/ezx
sudo ./uninstall.sh    # to remove
```

**Windows — installer (recommended):** download `ezx-setup-<version>.exe`
from the [Releases][] page and run it. It installs into your user folder
(`%LOCALAPPDATA%\Programs\ezx`), adds "ezx" to the Start menu and the desktop
(launching `bin\ezx-launch.vbs` with the app icon), and registers itself in
"Settings → Apps". No administrator rights are needed and the emulator starts
straight from the installer's last page. Remove it via "Settings → Apps" or
`Uninstall.exe` in the install folder — your settings and saves are kept
(they live in `%LOCALAPPDATA%\ezx` and are never touched).

**Windows — portable zip:** download `ezx-<version>-windows-x86_64.zip`,
unpack it and run the emulator like an application — double-click
`bin\ezx-launch.vbs` (or run `bin\ezx-launch.cmd`). Like the Linux
`ezx-launch`, this boots the bundled VM directly into the app
(`nonode@nohost`, embedded mode), so it needs no cookie, no console and no
release-management CLI. To add a Start menu entry manually, run
`bin\install-startmenu.ps1` (remove with `bin\uninstall-startmenu.ps1`).

`bin\ezx.cmd console` also works and shows the VM's console output, which is
useful when debugging a startup problem. Avoid `bin\ezx.cmd start`: on
Windows `start` means "run as an erlsrv Windows service" and fails unless the
service was installed first with `install` — a GUI app does not run that way.

Optional Start menu shortcut: run `bin\install-startmenu.ps1` to add an
"ezx" entry (with the app icon) to the current user's Start menu; run
`bin\uninstall-startmenu.ps1` to remove it. Both touch only the current
user's `%APPDATA%\Microsoft\Windows\Start Menu` and need no administrator
rights. From cmd, prefix with
`powershell -ExecutionPolicy Bypass -File` (ExecutionPolicy only affects
how the script is launched, nothing in the emulator).

Windows requirements:

- Sound: works out of the box — the release bundles `sox` (GPL, its license
  is shipped alongside in `priv/bin/LICENSE.GPL.txt`) and plays through the
  default audio device. If that copy is removed, ezx falls back to a `sox` or
  `ffplay` (FFmpeg) found on `PATH`; without any of them it still runs, just
  silently.
- No Erlang/OTP installation is required — the release carries its own ERTS.

The `.deb` and the tarball are produced from a tagged release by `make` (see
the `Makefile`) and contain identical payloads; the Windows zip and the NSIS
installer (`ezx-setup-<version>.exe`, script in `packaging/ezx.nsi`) are
assembled by the release workflow on GitHub Actions.

What the Linux target machine does need:

- GTK3 / wx libraries (the wx wrapper that ships with OTP links against
  GTK3): on Debian/Ubuntu install `libwxgtk3.2-1`, on Fedora `wxGTK3`.
- ALSA's `aplay` (from `alsa-utils`) for sound — see the note above.

The `ezx` launcher runs without a node name, so any number of instances can
run side by side sharing the user's settings and saves.

[Releases]: https://github.com/serge2/ezx/releases

## License

Copyright (c) 2026 Sergii Polkovnikov

Licensed under the MIT License. See [LICENSE](LICENSE) for details.

## Legal note

The ROM files in `priv/roms/` are copyright Amstrad plc.
Amstrad has kindly given written permission for these ROMs
to be redistributed freely for use with emulators.
See https://worldofspectrum.net/app/themes/wosc-classic/static/legacy/amstrad-roms.txt
for details.

The Windows release bundles the `sox` sound tool (GPL/LGPL; its license is
shipped as `priv/bin/LICENSE.GPL.txt`). It is a separate program ezx talks to
over a pipe, not linked into the emulator. sox is by the SoX project
(https://sox.sourceforge.net/); its source code is available there. The
Windows binaries are vendored in `packaging/sox-win32/` and come from the
official sox-14.4.2-win32 distribution, so the release build does not depend
on an external download.
