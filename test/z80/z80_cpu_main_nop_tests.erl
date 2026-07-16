-module(z80_cpu_main_nop_tests).

-include("z80_records.hrl").
-include_lib("eunit/include/eunit.hrl").

%% --- NOP & HALT Tests ---

nop_instruction_test() ->
    Machine0 = ezx_emulator:init(),
    Machine1 = z80_cpu:step(Machine0),
    ?assertEqual(1, z80_cpu:pc(Machine1)),
    ?assertEqual(4, z80_cpu:t_states(Machine1)).

nop_timing_test() ->
    Machine0 = ezx_emulator:init(),
    Machine1 = z80_cpu:step(Machine0),
    ?assertEqual(4, z80_cpu:t_states(Machine1)).

halt_instruction_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#76),
    Machine1 = Machine0#machine_state{memory = Mem1},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(4, z80_cpu:t_states(Machine2)),
    ?assertEqual(true, Machine2#machine_state.cpu#cpu_state.halted).

halt_timing_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#76),
    Machine1 = Machine0#machine_state{memory = Mem1},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(4, z80_cpu:t_states(Machine2)),
    ?assertEqual(true, Machine2#machine_state.cpu#cpu_state.halted).