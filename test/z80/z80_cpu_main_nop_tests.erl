-module(z80_cpu_main_nop_tests).

-include("z80_records.hrl").
-include_lib("eunit/include/eunit.hrl").

%% --- NOP & HALT Tests ---

nop_instruction_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = z80_cpu:step(Cpu0),
    ?assertEqual(1, z80_cpu:pc(Cpu1)),
    ?assertEqual(4, z80_cpu:t_states(Cpu1)).

nop_timing_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = z80_cpu:step(Cpu0),
    ?assertEqual(4, z80_cpu:t_states(Cpu1)).

halt_instruction_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#76),  %% HALT
    Cpu2 = z80_cpu:step(Cpu1),
    ?assertEqual(4, z80_cpu:t_states(Cpu2)),
    ?assertEqual(true, Cpu2#cpu_state.halted).

halt_timing_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#76),  %% HALT
    Cpu2 = z80_cpu:step(Cpu1),
    ?assertEqual(4, z80_cpu:t_states(Cpu2)),
    ?assertEqual(true, Cpu2#cpu_state.halted).
