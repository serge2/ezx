-module(ezx_emulator_tests).

-include("z80_records.hrl").
-include("ezx_emulator.hrl").
-include_lib("eunit/include/eunit.hrl").

machine_step_advances_state_test() ->
    Machine0 = ezx_emulator:init(),
    Program = #{16#4000 => 16#00},
    Machine1 = ezx_emulator:load_program(Machine0, Program),
    Machine1b = ezx_emulator:set_pc(Machine1, 16#4000),
    Machine2 = ezx_emulator:step(Machine1b),
    ?assertEqual(16#4001, z80_cpu:pc(Machine2#machine_state.cpu)),
    ?assertEqual(4, z80_cpu:t_states(Machine2#machine_state.cpu)),
    ?assertEqual(4, Machine2#machine_state.t_states).

machine_run_until_tstates_test() ->
    Machine0 = ezx_emulator:init(),
    Program = #{16#4000 => 16#00, 16#4001 => 16#00, 16#4002 => 16#00},
    Machine1 = ezx_emulator:load_program(Machine0, Program),
    Machine1b = ezx_emulator:set_pc(Machine1, 16#4000),
    Machine2 = ezx_emulator:run_until_tstates(Machine1b, 12),
    ?assertEqual(16#4003, z80_cpu:pc(Machine2#machine_state.cpu)),
    ?assertEqual(12, z80_cpu:t_states(Machine2#machine_state.cpu)),
    ?assertEqual(12, Machine2#machine_state.t_states).

machine_loads_byte_lists_into_memory_test() ->
    Machine0 = ezx_emulator:init(),
    Machine1 = ezx_emulator:load_program(Machine0, 16#4000, [16#3E, 16#41]),
    {Byte0, _} = ezx_emulator:read_byte(Machine1, 16#4000),
    ?assertEqual(16#3E, Byte0),
    {Byte1, _} = ezx_emulator:read_byte(Machine1, 16#4001),
    ?assertEqual(16#41, Byte1).

machine_executes_program_from_memory_test() ->
    Machine0 = ezx_emulator:init(),
    Program = [16#3E, 16#41],
    Machine1 = ezx_emulator:load_program(Machine0, 16#4000, Program),
    Machine1b = ezx_emulator:set_pc(Machine1, 16#4000),
    Machine2 = ezx_emulator:step(Machine1b),
    ?assertEqual(16#4002, z80_cpu:pc(Machine2#machine_state.cpu)),
    ?assertEqual(16#41, z80_cpu:get_reg_byte(a, Machine2#machine_state.cpu)).

machine_state_keeps_cpu_and_memory_separate_test() ->
    Machine0 = ezx_emulator:init(),
    Machine1 = ezx_emulator:load_program(Machine0, 16#4000, [16#3E, 16#41]),
    ?assertEqual(0, z80_cpu:pc(Machine1#machine_state.cpu)),
    ?assertEqual(16#3E, ezx_memory_48:read_byte(Machine1#machine_state.memory, 16#4000)),
    ?assertEqual(16#41, ezx_memory_48:read_byte(Machine1#machine_state.memory, 16#4001)).

memory_reset_restores_initial_configuration_test() ->
    State0 = ezx_memory_48:new(<<0:65536/unit:8>>),
    _State1 = ezx_memory_48:write_byte(State0, 10, 42),
    State2 = ezx_memory_48:new(<<0:65536/unit:8>>),
    ?assertEqual(0, ezx_memory_48:read_byte(State2, 10)).

memory_reset_to_zero_test() ->
    Memory0 = ezx_memory_48:new(<<0:8/unit:8>>),
    _Memory1 = ezx_memory_48:write_byte(Memory0, 4, 16#99),
    Memory2 = ezx_memory_48:new(<<0:8/unit:8>>),
    ?assertEqual(0, ezx_memory_48:read_byte(Memory2, 4)).

%% --- run_frame tests ---

run_frame_completes_one_frame_test() ->
    Machine0 = ezx_emulator:init(),
    %% NOP loop at RAM address 0x4000.
    Machine1 = ezx_emulator:load_program(Machine0, #{16#4000 => 16#00}),
    Machine1b = ezx_emulator:set_pc(Machine1, 16#4000),
    Machine2 = ezx_emulator:run_frame(Machine1b),
    ?assertEqual(0, Machine2#machine_state.t_states).

run_frame_int_fires_test() ->
    Machine0 = ezx_emulator:init(),
    Machine1 = ezx_emulator:load_program(Machine0, #{16#4000 => 16#FB, 16#4001 => 16#00, 16#4002 => 16#00}),
    Machine1b = ezx_emulator:set_pc(Machine1, 16#4000),
    Machine2 = ezx_emulator:run_frame(Machine1b),
    Cpu = Machine2#machine_state.cpu,
    Pc = z80_cpu:pc(Cpu),
    ?assert(Pc >= 16#0038).

run_frame_border_changes_cleared_test() ->
    Machine0 = ezx_emulator:init(),
    Machine1 = ezx_emulator:load_program(Machine0, #{16#4000 => 16#3E, 16#4001 => 16#04, 16#4002 => 16#D3, 16#4003 => 16#FE}),
    Machine1b = ezx_emulator:set_pc(Machine1, 16#4000),
    Machine2 = ezx_emulator:run_frame(Machine1b),
    %% border_changes are now preserved after run_frame for rendering.
    %% They should be empty only if no OUT instructions executed.
    %% With the program above (OUT 0xFE, A), there should be one change.
    ?assertEqual([{7, 4}], Machine2#machine_state.border_changes).

run_frame_multiple_nops_test() ->
    Machine0 = ezx_emulator:init(),
    Nops = lists:duplicate(200, 16#00),
    Machine1 = ezx_emulator:load_program(Machine0, 16#4000, Nops),
    Machine1b = ezx_emulator:set_pc(Machine1, 16#4000),
    Machine2 = ezx_emulator:run_frame(Machine1b),
    Pc = z80_cpu:pc(Machine2#machine_state.cpu),
    ?assert(Pc >= 16#0038).

run_frame_two_frames_test() ->
    Machine0 = ezx_emulator:init(),
    Machine1 = ezx_emulator:load_program(Machine0, #{16#4000 => 16#00}),
    Machine1b = ezx_emulator:set_pc(Machine1, 16#4000),
    Machine2 = ezx_emulator:run_frame(Machine1b),
    Machine3 = ezx_emulator:run_frame(Machine2),
    ?assertEqual(0, Machine3#machine_state.t_states).
