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

Audio output requires the ALSA `aplay` command-line tool (from the
`alsa-utils` package on most distributions); it is spawned as the sound sink
when the UI starts. If `aplay` is not installed, the emulator still runs but
produces no sound. Install it with e.g. `sudo apt install alsa-utils`
(Debian/Ubuntu) or `sudo dnf install alsa-utils` (Fedora).

## License

Copyright (c) 2026 Sergii Polkovnikov

Licensed under the MIT License. See [LICENSE](LICENSE) for details.

## Legal note

The ROM files in `priv/roms/` are copyright Amstrad plc.
Amstrad has kindly given written permission for these ROMs
to be redistributed freely for use with emulators.
See https://worldofspectrum.net/app/themes/wosc-classic/static/legacy/amstrad-roms.txt
for details.
