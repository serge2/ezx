-module(z80_cpu_main_rotate_tests).

-include("z80_records.hrl").
-include_lib("eunit/include/eunit.hrl").

%% --- Rotate/Shift Tests (A register) ---

%% RLCA

rlca_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{a = 16#80},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#07),  %% RLCA
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(16#01, Cpu3#cpu_state.a),
    ?assertEqual(?FLAG_C, Cpu3#cpu_state.f band ?FLAG_C).

rlca_no_carry_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{a = 16#40},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#07),  %% RLCA
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(16#80, Cpu3#cpu_state.a),
    ?assertEqual(0, Cpu3#cpu_state.f band ?FLAG_C).

%% RRCA

rrca_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{a = 16#01},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#0F),  %% RRCA
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(16#80, Cpu3#cpu_state.a),
    ?assertEqual(?FLAG_C, Cpu3#cpu_state.f band ?FLAG_C).

rrca_no_carry_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{a = 16#02},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#0F),  %% RRCA
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(16#01, Cpu3#cpu_state.a),
    ?assertEqual(0, Cpu3#cpu_state.f band ?FLAG_C).

%% RLA

rla_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{a = 16#80, f = ?FLAG_C},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#17),  %% RLA
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(16#01, Cpu3#cpu_state.a),
    ?assertEqual(?FLAG_C, Cpu3#cpu_state.f band ?FLAG_C).

rla_no_carry_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{a = 16#40, f = 0},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#17),  %% RLA
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(16#80, Cpu3#cpu_state.a),
    ?assertEqual(0, Cpu3#cpu_state.f band ?FLAG_C).

%% RRA

rra_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{a = 16#01, f = ?FLAG_C},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#1F),  %% RRA
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(16#80, Cpu3#cpu_state.a),
    ?assertEqual(?FLAG_C, Cpu3#cpu_state.f band ?FLAG_C).

rra_no_carry_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{a = 16#02, f = 0},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#1F),  %% RRA
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(16#01, Cpu3#cpu_state.a),
    ?assertEqual(0, Cpu3#cpu_state.f band ?FLAG_C).

%% --- CPL, SCF, CCF Tests ---

cpl_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{a = 16#55},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#2F),  %% CPL
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(16#AA, Cpu3#cpu_state.a),
    ?assertEqual(?FLAG_H, Cpu3#cpu_state.f band ?FLAG_H),
    ?assertEqual(?FLAG_N, Cpu3#cpu_state.f band ?FLAG_N).

scf_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{f = 0},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#37),  %% SCF
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(?FLAG_C, Cpu3#cpu_state.f band ?FLAG_C),
    ?assertEqual(0, Cpu3#cpu_state.f band ?FLAG_N).

ccf_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{f = 0},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#3F),  %% CCF
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(?FLAG_C, Cpu3#cpu_state.f band ?FLAG_C).

ccf_carry_to_no_carry_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{f = ?FLAG_C},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#3F),  %% CCF
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(0, Cpu3#cpu_state.f band ?FLAG_C).

%% --- DAA Tests ---

daa_after_add_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{a = 16#15},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#C6),  %% ADD A,n
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#27),  %% operand 0x27
    Cpu4 = test_helpers:write_mem(Cpu3, 2, 16#27),  %% DAA
    Cpu5 = z80_cpu:step(Cpu4),
    Cpu6 = z80_cpu:step(Cpu5),
    ?assertEqual(16#42, Cpu6#cpu_state.a),
    ?assertEqual(0, Cpu6#cpu_state.f band 16#40).

daa_after_sub_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{a = 16#52},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#D6),  %% SUB n
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#37),  %% operand 0x37
    Cpu4 = test_helpers:write_mem(Cpu3, 2, 16#27),  %% DAA
    Cpu5 = z80_cpu:step(Cpu4),
    Cpu6 = z80_cpu:step(Cpu5),
    ?assertEqual(16#15, Cpu6#cpu_state.a).

daa_carry_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{a = 16#99},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#C6),  %% ADD A,n
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#01),  %% operand 0x01
    Cpu4 = test_helpers:write_mem(Cpu3, 2, 16#27),  %% DAA
    Cpu5 = z80_cpu:step(Cpu4),
    Cpu6 = z80_cpu:step(Cpu5),
    ?assertEqual(16#00, Cpu6#cpu_state.a),
    ?assertEqual(?FLAG_C, Cpu6#cpu_state.f band ?FLAG_C),
    ?assertEqual(?FLAG_Z, Cpu6#cpu_state.f band ?FLAG_Z).

daa_no_carry_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{a = 16#19},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#C6),  %% ADD A,n
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#27),  %% operand 0x27
    Cpu4 = test_helpers:write_mem(Cpu3, 2, 16#27),  %% DAA
    Cpu5 = z80_cpu:step(Cpu4),
    Cpu6 = z80_cpu:step(Cpu5),
    ?assertEqual(16#46, Cpu6#cpu_state.a),
    ?assertEqual(0, Cpu6#cpu_state.f band ?FLAG_C).

daa_half_carry_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{a = 16#09},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#C6),  %% ADD A,n
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#09),  %% operand 0x09
    Cpu4 = test_helpers:write_mem(Cpu3, 2, 16#27),  %% DAA
    Cpu5 = z80_cpu:step(Cpu4),
    Cpu6 = z80_cpu:step(Cpu5),
    ?assertEqual(16#18, Cpu6#cpu_state.a),
    %% DAA half-carry: 0x12 + 0x06 = 0x18, no half-carry (2+6=8 < 16)
    ?assertEqual(0, Cpu6#cpu_state.f band ?FLAG_H).
