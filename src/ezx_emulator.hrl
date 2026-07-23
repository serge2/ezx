%% Machine-level runtime state that keeps CPU, memory, and timing separate.



-record(machine_state, {
    cpu = undefined :: z80_cpu:state(),
    memory = undefined :: ezx_memory_48:state(),
    mem_read_fun = undefined,
    mem_write_fun = undefined,
    pending_interrupt = none,
    t_states = 0,
    border_color = 0,
    border_changes = [],
    keyboard = undefined :: ezx_keyboard:state(),
    %% Tape trap state: list of [{flag :: 0 | 16#FF, data :: binary()}]
    %% served via LD-BYTES (0x0556) trap during execution.
    tape_blocks = [],
    %% Auto-typing queue: [{keyboard_tuple(), frames_to_hold}]
    keyboard_queue = [],
    %% Beeper state for audio generation.
    beeper = undefined,
    %% PCM audio output from the last completed frame (binary, S16LE mono).
    beeper_pcm = <<>>
}).

-record(ext_context, {
    memory = undefined :: ezx_memory_48:state(),
    t_states = 0,
    % frame_counter = 0,
    border_changes = [],
    keyboard = undefined :: ezx_keyboard:state(),
    beeper = undefined
}).
