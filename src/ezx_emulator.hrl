%% Machine-level runtime state that keeps CPU, memory, and timing separate.

%% ZX Spectrum frame length in T-states (50 Hz).
-define(TSTATES_PER_FRAME, 69888).
%% Interrupt is raised 32 T-states into the frame.
-define(INT_TSTATE, 32).

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

-record(ext_context, {
    memory,
    screen,
    keyboard,
    beeper = undefined,
    ay = undefined,
    kempston_mouse = undefined
}).
