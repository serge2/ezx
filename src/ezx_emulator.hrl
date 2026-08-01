%% Machine-level runtime state that keeps CPU, memory, and timing separate.

%% ZX Spectrum frame length in T-states (50 Hz).
-define(TSTATES_PER_FRAME, 69888).
%% Interrupt is raised 32 T-states into the frame.
-define(INT_TSTATE, 32).


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
    kempston_mouse = undefined
}).

-record(ext_context, {
    memory,
    screen,
    keyboard,
    beeper = undefined,
    ay = undefined,
    kempston_mouse = undefined
}).
