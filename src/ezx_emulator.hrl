%% Machine-level runtime state that keeps CPU, memory, and timing separate.



-record(machine_state, {
    cpu_module :: module(),
    cpu,
    memory_module :: module(),
    memory,
    video_module :: module(),
    pending_interrupt = none,
    t_states = 0,
    border_color = 0,
    border_changes = [],
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
    flash_counter = 0, %Used for flash attribute toggling (0..31)
    screen = <<>>,
    %% AY-3-8912 audio state (128K only).
    ay_module = undefined :: module() | undefined,
    ay = undefined,
    %% Optional Kempston mouse state (undefined = mouse not present).
    kempston_mouse = undefined
}).

-record(ext_context, {
    memory,
    border_changes = [],
    keyboard,
    beeper = undefined,
    ay = undefined,
    kempston_mouse = undefined
}).
