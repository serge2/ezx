%% Machine-level runtime state that keeps CPU, memory, and timing separate.

-record(machine_state, {
    cpu = #cpu_state{},
    memory = undefined,
    mem_read_fun = undefined,
    mem_write_fun = undefined,
    pending_interrupt = none,
    t_states = 0,
    border_color = 0,
    border_changes = []
}).

-record(ext_context, {
    memory = undefined,
    t_states = 0,
    frame_counter = 0,
    border_changes = []
}).
