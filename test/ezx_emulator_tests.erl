-module(ezx_emulator_tests).

-include("z80_records.hrl").
-include_lib("eunit/include/eunit.hrl").

machine_step_advances_state_test() ->
    Machine0 = z80_emulator:init(),
    Program = #{0 => 16#00},
    Machine1 = z80_emulator:load_program(Machine0, Program),
    Machine2 = z80_emulator:step(Machine1),
    ?assertEqual(1, z80_cpu:pc(Machine2)),
    ?assertEqual(4, z80_cpu:t_states(Machine2)),
    ?assertEqual(4, Machine2#machine_state.t_states).

machine_run_until_tstates_test() ->
    Machine0 = z80_emulator:init(),
    Program = #{0 => 16#00, 1 => 16#00, 2 => 16#00},
    Machine1 = z80_emulator:load_program(Machine0, Program),
    Machine2 = z80_emulator:run_until_tstates(Machine1, 12),
    ?assertEqual(3, z80_cpu:pc(Machine2)),
    ?assertEqual(12, z80_cpu:t_states(Machine2)),
    ?assertEqual(12, Machine2#machine_state.t_states).

machine_loads_byte_lists_into_memory_test() ->
    Machine0 = z80_emulator:init(),
    Machine1 = z80_emulator:load_program(Machine0, [16#3E, 16#41]),
    ?assertEqual(16#3E, z80_emulator:read_byte(Machine1, 0)),
    ?assertEqual(16#41, z80_emulator:read_byte(Machine1, 1)).

machine_executes_program_from_memory_test() ->
    Machine0 = z80_emulator:init(),
    Program = [16#3E, 16#41],
    Machine1 = z80_emulator:load_program(Machine0, Program),
    Machine2 = z80_emulator:step(Machine1),
    ?assertEqual(2, z80_cpu:pc(Machine2)),
    ?assertEqual(16#41, z80_cpu:get_reg_byte(a, Machine2#machine_state.cpu)).

machine_state_keeps_cpu_and_memory_separate_test() ->
    Machine0 = z80_emulator:init(),
    Machine1 = z80_emulator:load_program(Machine0, [16#3E, 16#41]),
    ?assertEqual(0, z80_cpu:pc(Machine1)),
    ?assertEqual(16#3E, z80_mem:read_byte(Machine1#machine_state.memory, 0)),
    ?assertEqual(16#41, z80_mem:read_byte(Machine1#machine_state.memory, 1)).

memory_reset_restores_initial_configuration_test() ->
    State0 = z80_mem:new(65536),
    State1 = z80_mem:write_byte(State0, 10, 42),
    State2 = z80_mem:reset(State1),
    ?assertEqual(0, z80_mem:read_byte(State2, 10)).

memory_reset_to_zero_test() ->
    Memory0 = z80_mem:new(8),
    Memory1 = z80_mem:write_byte(Memory0, 4, 16#99),
    Memory2 = z80_mem:reset(Memory1),
    ?assertEqual(0, z80_mem:read_byte(Memory2, 4)).
