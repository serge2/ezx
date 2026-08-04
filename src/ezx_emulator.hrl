%% Machine-level runtime state that keeps CPU, memory, and timing separate.

%% Audio output sample rate (Hz) shared by the machine and the audio devices.
-define(SAMPLE_RATE, 44100).

%% Machine timing model: raster geometry (T-states) + CPU clock.
%% The frame length in T-states is fixed by the video raster; the CPU clock
%% determines real frame time (TStatesPerFrame / CpuClock) and thus the number
%% of audio samples per frame.  The AY runs at CpuClock / AyPrescale.
-record(machine_model, {
    cpu_clock :: pos_integer(),          %% CPU clock in Hz (e.g. 3500000)
    tstates_per_frame :: pos_integer(),  %% video frame length in T-states
    tstates_per_line :: pos_integer(),   %% horizontal scanline length in T-states
    int_tstate :: non_neg_integer(),     %% interrupt raised this many T-states into the frame
    ay_prescale :: pos_integer()         %% AY clock = CPU clock / ay_prescale
}).

%% Real hardware: 48K = 3.5 MHz, 224 T-states/line × 312 lines = 69888/frame
%% (50.08 Hz). 128K = 3.5469 MHz, 228 × 311 = 70908/frame (50.02 Hz).
-define(SPECTRUM_48_MODEL, #machine_model{
    cpu_clock = 3500000,
    tstates_per_frame = 69888,
    tstates_per_line = 224,
    int_tstate = 32,
    ay_prescale = 2}).

-define(SPECTRUM_128_MODEL, #machine_model{
    cpu_clock = 3546900,
    tstates_per_frame = 70908,
    tstates_per_line = 228,
    int_tstate = 32,
    ay_prescale = 2}).

%% Per-frame timing accumulators collected by run_frame/1 so the UI can report
%% where time actually goes. cpu = keyboard + frame_start + execution,
%% beeper = beeper PCM render, screen = ULA border/flash artifacts,
%% ay = AY channel render, render = screen bitmap (when render_screen is true).
-record(perf_stats, {
    frames = 0 :: non_neg_integer(),
    cpu_us = 0 :: non_neg_integer(),
    beeper_us = 0 :: non_neg_integer(),
    ay_us = 0 :: non_neg_integer(),
    screen_us = 0 :: non_neg_integer(),
    render_us = 0 :: non_neg_integer()
}).


-record(machine_state, {
    %% Machine timing model (CPU clock + raster geometry).
    model :: #machine_model{},
    cpu_module :: module(),
    cpu,
    memory_module :: module(),
    memory,
    pending_interrupt = none,
    t_states = 0,
    %% ULA screen device (ezx_screen): border color + flash phase.
    screen,
    %% Screen artifacts from the last completed frame: sorted local-time
    %% border changes + current color (base color for the screen) + the
    %% attribute flash phase flag for this frame.
    screen_changes = [],
    screen_color = 0,
    flash_on = false,
    keyboard_module :: module(),
    keyboard,
    %% Tape trap state: list of [{flag :: 0 | 16#FF, data :: binary()}]
    %% served via LD-BYTES (0x0556) trap during execution.
    tape_blocks = [],
    %% Auto-typing queue: [{keyboard_tuple(), frames_to_hold}]
    keyboard_queue = [],
    %% Beeper state for audio generation.
    beeper_module :: module(),
    beeper,
    %% PCM audio output from the last completed frame (binary, S16LE mono).
    beeper_pcm = <<>>,
    %% AY-3-8912 audio state (128K only).
    ay_module = undefined :: module() | undefined,
    ay = undefined,
    %% AY channel PCMs from the last completed frame ({ChA, ChB, ChC}, S16LE mono).
    ay_pcm = undefined,
    %% Optional Kempston mouse state (undefined = mouse not present).
    kempston_mouse = undefined,
    %% Screen RGB pixels (352×288×3) from the last completed frame, rendered
    %% inside run_frame/1 only when render_screen is true (the interactive UI
    %% enables it; headless keeps it off to avoid the per-frame cost).
    screen_pixels = undefined :: undefined | binary(),
    %% When true, run_frame/1 renders the screen bitmap into screen_pixels.
    render_screen = false :: boolean(),
    %% Accumulated per-phase timing of run_frame/1 (see ezx_emulator:read_perf/1).
    perf_stats = #perf_stats{} :: #perf_stats{}
}).

%% Device context threaded through the CPU: the machine-level devices the CPU
%% can touch. Undefined module fields mean the device is absent; port handlers
%% decline with `nomatch` and the port falls through to the 0xFF read /
%% ignore-write default.
-record(ext_context, {
    memory,
    screen,
    keyboard,
    beeper = undefined,
    ay = undefined,
    kempston_mouse = undefined,
    %% Device modules so the shared port handlers (ezx_emulator:read_* /
    %% write_*) can call the configured implementation (undefined = absent).
    memory_module = undefined,
    keyboard_module = undefined,
    beeper_module = undefined,
    ay_module = undefined
}).
