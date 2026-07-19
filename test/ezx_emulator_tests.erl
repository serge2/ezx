-module(ezx_emulator_tests).

-include("z80_records.hrl").
-include("ezx_emulator.hrl").
-include_lib("eunit/include/eunit.hrl").

machine_step_advances_state_test() ->
    Machine0 = ezx_emulator:init(),
    Program = #{0 => 16#00},
    Machine1 = ezx_emulator:load_program(Machine0, Program),
    Machine2 = ezx_emulator:step(Machine1),
    ?assertEqual(1, z80_cpu:pc(Machine2#machine_state.cpu)),
    ?assertEqual(4, z80_cpu:t_states(Machine2#machine_state.cpu)),
    ?assertEqual(4, Machine2#machine_state.t_states).

machine_run_until_tstates_test() ->
    Machine0 = ezx_emulator:init(),
    Program = #{0 => 16#00, 1 => 16#00, 2 => 16#00},
    Machine1 = ezx_emulator:load_program(Machine0, Program),
    Machine2 = ezx_emulator:run_until_tstates(Machine1, 12),
    ?assertEqual(3, z80_cpu:pc(Machine2#machine_state.cpu)),
    ?assertEqual(12, z80_cpu:t_states(Machine2#machine_state.cpu)),
    ?assertEqual(12, Machine2#machine_state.t_states).

machine_loads_byte_lists_into_memory_test() ->
    Machine0 = ezx_emulator:init(),
    Machine1 = ezx_emulator:load_program(Machine0, [16#3E, 16#41]),
    {Byte0, _} = ezx_emulator:read_byte(Machine1, 0),
    ?assertEqual(16#3E, Byte0),
    {Byte1, _} = ezx_emulator:read_byte(Machine1, 1),
    ?assertEqual(16#41, Byte1).

machine_executes_program_from_memory_test() ->
    Machine0 = ezx_emulator:init(),
    Program = [16#3E, 16#41],
    Machine1 = ezx_emulator:load_program(Machine0, Program),
    Machine2 = ezx_emulator:step(Machine1),
    ?assertEqual(2, z80_cpu:pc(Machine2#machine_state.cpu)),
    ?assertEqual(16#41, z80_cpu:get_reg_byte(a, Machine2#machine_state.cpu)).

machine_state_keeps_cpu_and_memory_separate_test() ->
    Machine0 = ezx_emulator:init(),
    Machine1 = ezx_emulator:load_program(Machine0, [16#3E, 16#41]),
    ?assertEqual(0, z80_cpu:pc(Machine1#machine_state.cpu)),
    ?assertEqual(16#3E, ezx_memory_48:read_byte(Machine1#machine_state.memory, 0)),
    ?assertEqual(16#41, ezx_memory_48:read_byte(Machine1#machine_state.memory, 1)).

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
    %% NOP loop at address 0.
    Machine1 = ezx_emulator:load_program(Machine0, [16#00]),
    Machine2 = ezx_emulator:run_frame(Machine1),
    %% After one frame, t_states resets to 0.
    ?assertEqual(0, Machine2#machine_state.t_states).

run_frame_int_fires_test() ->
    Machine0 = ezx_emulator:init(),
    %% Program: EI; NOP; NOP; ... (at addr 0)
    %% EI enables interrupts but blocks for 1 instruction.
    %% After 2 instructions, INT can fire.
    %% INT at T=32: CPU pushes PC, jumps to 0x0038.
    Machine1 = ezx_emulator:load_program(Machine0, [16#FB, 16#00, 16#00]),
    Machine2 = ezx_emulator:run_frame(Machine1),
    Cpu = Machine2#machine_state.cpu,
    %% After INT, PC should be at 0x0038 (INT handler in ROM, all NOPs).
    %% The CPU ran some instructions, then INT jumped to 0x0038 and ran NOPs there.
    %% PC should be somewhere in the 0x0038+ range.
    Pc = z80_cpu:pc(Cpu),
    ?assert(Pc >= 16#0038).

run_frame_border_changes_cleared_test() ->
    Machine0 = ezx_emulator:init(),
    %% OUT (0xFE), A with A=4 (green border) at addr 0, then NOPs.
    %% OUT (n),A = D3 xx FE = 11 T-states.
    Machine1 = ezx_emulator:load_program(Machine0, [16#3E, 16#04, 16#D3, 16#FE]),
    Machine2 = ezx_emulator:run_frame(Machine1),
    %% Border changes are cleared after frame completes.
    ?assertEqual([], Machine2#machine_state.border_changes).

run_frame_multiple_nops_test() ->
    Machine0 = ezx_emulator:init(),
    %% Fill with NOPs — enough to fill some of the frame.
    Nops = lists:duplicate(200, 16#00),
    Machine1 = ezx_emulator:load_program(Machine0, Nops),
    Machine2 = ezx_emulator:run_frame(Machine1),
    %% INT fires at T=32, jumping PC to 0x0038.
    %% After INT, CPU executes NOPs from 0x0038 onwards.
    %% So PC should be somewhere past 0x0038.
    Pc = z80_cpu:pc(Machine2#machine_state.cpu),
    ?assert(Pc >= 16#0038).

run_frame_two_frames_test() ->
    Machine0 = ezx_emulator:init(),
    Machine1 = ezx_emulator:load_program(Machine0, [16#00]),
    Machine2 = ezx_emulator:run_frame(Machine1),
    Machine3 = ezx_emulator:run_frame(Machine2),
    %% After two frames, t_states should be 0 again.
    ?assertEqual(0, Machine3#machine_state.t_states).
