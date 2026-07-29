# ezx

ZX Spectrum 48K emulator written in Erlang.

Just for fun and as a proof of concept — exploring how far you can get with a functional language for real-time emulation.

## Status

Working prototype with:
- Z80 CPU (full instruction set)
- 48K memory model
- Screen rendering (352x288 with border)
- Keyboard input
- Beeper audio
- SNA/TAP file loading
- Tape trap emulation for auto-loading

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

## License

Copyright (c) 2026 Sergii Polkovnikov

Licensed under the MIT License. See [LICENSE](LICENSE) for details.

## Legal note

The ROM files in `priv/roms/` are copyright Amstrad plc.
Amstrad has kindly given written permission for these ROMs
to be redistributed freely for use with emulators.
See https://worldofspectrum.net/app/themes/wosc-classic/static/legacy/amstrad-roms.txt
for details.
