%% Machine-level runtime state that keeps CPU, memory, and timing separate.

%% Audio output sample rate (Hz) shared by the machine and the audio devices.
-define(SAMPLE_RATE, 44100).

%% Horizontal scanline length in T-states for the 48K/Pentagon raster (the
%% 128K model carries 228 in tstates_per_line). Used by the render-only
%% callers that have no machine model at hand (benchmarks, debug tools, tests).
-define(TSTATES_PER_LINE, 224).

%% Horizontal raster geometry within a scanline, in base-clock T-states,
%% relative to the line start: {WinStartT, WinEndT, ScreenStartT, ScreenEndT}.
%% WinStartT/WinEndT delimit the visible window (rendered at 2 px per T-state)
%% and ScreenStartT/ScreenEndT the 128-T screen inside it.  On the 48K and 128K
%% the window covers the first 176 T of the line ({0, 176, 24, 152}: 24 T left
%% border, 128 T screen, 24 T right border; the horizontal retrace after 176 T
%% is not shown).  On the Pentagon the line is 36 T left border + 128 T screen
%% + 28 T right border + 32 T retrace, and the window shows the FULL Pentagon
%% border — 192 T (384 px) from 32 T (retrace end) to 224 T:
%% {32, 224, 68, 196} — 36 T (72 px) of left border, the screen at pixels
%% 72..327, 28 T (56 px) of right border (the original Pentagon geometry, not
%% the 48K-style centered crop).
-define(LINE_GEOMETRY_48K, {0, 176, 24, 152}).
-define(LINE_GEOMETRY_PENTAGON, {32, 224, 68, 196}).

%% Vertical raster geometry within a frame, in lines:
%% {WindowTopLine, ScreenStartLine, WindowHeight}.  WindowTopLine is the first
%% rendered frame line (skips the vertical retrace), ScreenStartLine the first
%% screen line, WindowHeight the number of rendered lines — the visible window
%% is [WindowTopLine, WindowTopLine + WindowHeight), the screen
%% [ScreenStartLine, ScreenStartLine + 192).  48K/128K: 48 top border + 192
%% screen + 48 bottom border (window lines 16..303, screen 64..255, rendered
%% height 288).  Pentagon: 64 top border + 192 screen + 48 bottom border in the
%% 320-line frame (window lines 16..319, screen 80..271, rendered height 304).
-define(FRAME_GEOMETRY_48K, {16, 64, 288}).
-define(FRAME_GEOMETRY_PENTAGON, {16, 80, 304}).

%% Machine timing model: raster geometry (T-states) + CPU clock.
%% The frame length in T-states and the CPU clock together determine the real
%% frame time (TStatesPerFrame / CpuClock) and thus the number of audio samples
%% per frame.  Overclocking (set_cpu_frequency/2) scales the whole raster along
%% with the clock, so the frame rate, interrupt timing and sample count stay
%% fixed and only the CPU executes more T-states per real second.
%% base_cpu_clock is the machine's nominal clock (the CPU clock without an
%% overclock multiplier): it is the reference the AY is clocked from, so the
%% sound chip keeps running at base / 2 regardless of the CPU frequency.  The
%% AY prescale is baked into the audio devices (TStatesPerAyClock constants),
%% not part of the model.
-record(machine_model, {
    cpu_clock :: pos_integer(),          %% CPU clock in Hz (e.g. 3500000)
    base_cpu_clock :: pos_integer(),     %% nominal CPU clock (AY clock reference), unchanged by overclock
    tstates_per_frame :: pos_integer(),  %% video frame length in T-states
    tstates_per_line :: pos_integer(),   %% horizontal scanline length in T-states
    int_pulse :: pos_integer(),          %% INT pulse length in T-states (how long the INT line stays low)
    line_geometry = ?LINE_GEOMETRY_48K :: {pos_integer(), pos_integer(), pos_integer(), pos_integer()},
                                         %% horizontal border/screen geometry (see above)
    frame_geometry = ?FRAME_GEOMETRY_48K :: {pos_integer(), pos_integer(), pos_integer()},
                                         %% vertical border/screen geometry (see above)
    ay_chip = ay :: ay | ym              %% sound chip: AY-3-8912 ('ay') or YM2149 ('ym')
}).

%% Real hardware: 48K = 3.5 MHz, 224 T-states/line × 312 lines = 69888/frame
%% (50.08 Hz). 128K = 3.5469 MHz, 228 × 311 = 70908/frame (50.02 Hz).
%% Pentagon 128 = 3.584 MHz, 224 × 320 = 71680/frame (exactly 50.00 Hz):
%% the line is 36 T left border + 128 screen + 28 right border + 32 retrace
%% and the frame is 64 top border + 192 screen + 48 bottom border + 16
%% retrace lines (libspectrum timings, as used by Fuse).  The ULA asserts INT
%% low once per frame as a short pulse: 32 T-states on the
%% 48K, 36 T on the 128K and Pentagon, starting just before the frame boundary
%% (the CPU services it at the first instruction boundaries of the new frame;
%% the ISR entry floats over the first few T-states, since the frame boundary
%% is usually mid-instruction). ezx anchors the pulse to the frame start: the
%% request is asserted at the frame start and dropped after int_pulse
%% T-states, so the ISR runs early in the frame where its port writes stay
%% inside the frame's event window (the frame contract drops overrun-zone
%% events). The real Z80 samples /INT only at instruction ends — a DD/FD
%% prefix chain is one atomic unit (repeated prefixes inhibit interrupt
%% handling), so a chain straddling the frame boundary suppresses that frame's
%% interrupt; ezx models this by asserting the request only when the carried
%% frame-start tail t_states < int_pulse (see int_asserted/2). If the CPU does
%% not acknowledge within the pulse (e.g. interrupts disabled), the request is
%% dropped until the next frame, exactly like the real hardware.
-define(SPECTRUM_48_MODEL, #machine_model{
    cpu_clock = 3500000,
    base_cpu_clock = 3500000,
    tstates_per_frame = 69888,
    tstates_per_line = 224,
    int_pulse = 32,
    line_geometry = ?LINE_GEOMETRY_48K}).

-define(SPECTRUM_128_MODEL, #machine_model{
    cpu_clock = 3546900,
    base_cpu_clock = 3546900,
    tstates_per_frame = 70908,
    tstates_per_line = 228,
    int_pulse = 36,
    line_geometry = ?LINE_GEOMETRY_48K,
    frame_geometry = ?FRAME_GEOMETRY_48K}).

%% Pentagon 512K / 1024K share the Pentagon 128 raster exactly — the models
%% differ only in how much RAM the memory backend wires (the memory module is
%% built with 32 / 64 banks; see ezx_memory_pentagon).
-define(PENTAGON_128_MODEL, #machine_model{
    cpu_clock = 3584000,
    base_cpu_clock = 3584000,
    tstates_per_frame = 71680,
    tstates_per_line = 224,
    int_pulse = 36,
    line_geometry = ?LINE_GEOMETRY_PENTAGON,
    frame_geometry = ?FRAME_GEOMETRY_PENTAGON}).

-define(PENTAGON_512_MODEL, ?PENTAGON_128_MODEL).
-define(PENTAGON_1024_MODEL, ?PENTAGON_128_MODEL).

%% Per-frame timing accumulators collected by run_frame/1 so the UI can report
%% where time actually goes. cpu = keyboard + execution,
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
    %% Machine identity ('48k' | '128k' | 'pentagon_128' | 'pentagon_512' |
    %% 'pentagon_1024'), set at creation — the save paths (ezx_saves) read it
    %% instead of guessing the type from memory-module capabilities.
    machine_type :: atom(),
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
    %% Screen RGB pixels (model geometry, e.g. 352×288×3) from the last
    %% completed frame, rendered inside run_frame/1 only when render_screen is
    %% true (the interactive UI enables it; headless keeps it off to avoid the
    %% per-frame cost).
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
