%% Machine-level runtime state that keeps CPU, memory, and timing separate.

%% ZX Spectrum keyboard matrix: 8 half-rows, 5 keys each.
%% Each byte has bits 0-4: 0 = key pressed, 1 = not pressed.
%% Half-row selected when corresponding bit in address A8-A12 is 0.
%% Default: all keys released (0x1F = all bits set).
-define(KEYBOARD_DEFAULT, {16#1F, 16#1F, 16#1F, 16#1F, 16#1F, 16#1F, 16#1F, 16#1F}).

-record(machine_state, {
    cpu = #cpu_state{},
    memory = undefined,
    mem_read_fun = undefined,
    mem_write_fun = undefined,
    pending_interrupt = none,
    t_states = 0,
    border_color = 0,
    border_changes = [],
    keyboard = ?KEYBOARD_DEFAULT,
    %% Tape trap state: list of [{flag :: 0 | 16#FF, data :: binary()}]
    %% served via LD-BYTES (0x0556) trap during execution.
    tape_blocks = [],
    %% Auto-typing queue: [{keyboard_tuple(), frames_to_hold}]
    keyboard_queue = []
}).

-record(ext_context, {
    memory = undefined,
    t_states = 0,
    frame_counter = 0,
    border_changes = [],
    keyboard = ?KEYBOARD_DEFAULT
}).
