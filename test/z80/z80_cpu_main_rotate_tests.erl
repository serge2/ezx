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

%% --- SCF flag tests ---

scf_f3f5_from_a_test() ->
    %% SCF: F3/F5 come from A, H=0, N=0, C=1, S/Z/PV preserved
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{a = 16#28, f = ?FLAG_Z bor ?FLAG_S},  %% A has bit3=1, bit5=1
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#37),  %% SCF
    Cpu3 = z80_cpu:step(Cpu2),
    %% Expected: C=1, H=0, N=0, F3=1 (from A bit3), F5=1 (from A bit5), Z=1, S=1 preserved
    ?assertEqual(?FLAG_C bor ?FLAG_Z bor ?FLAG_S bor 16#28, Cpu3#cpu_state.f).

scf_clears_h_n_test() ->
    %% SCF must clear H and N even if they were set before
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{a = 16#00, f = ?FLAG_H bor ?FLAG_N bor ?FLAG_C},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#37),  %% SCF
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(?FLAG_C, Cpu3#cpu_state.f band (?FLAG_C bor ?FLAG_H bor ?FLAG_N)).

%% --- CCF flag tests ---

ccf_h_from_old_carry_test() ->
    %% CCF: H gets old carry, C gets flipped
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{a = 16#00, f = ?FLAG_C},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#3F),  %% CCF
    Cpu3 = z80_cpu:step(Cpu2),
    %% Old C=1, so H=1. New C=0. N=0.
    ?assertEqual(?FLAG_H, Cpu3#cpu_state.f band (?FLAG_H bor ?FLAG_C bor ?FLAG_N)).

ccf_no_carry_sets_c_test() ->
    %% CCF with C=0: H=0, C=1
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{a = 16#00, f = 0},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#3F),  %% CCF
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(?FLAG_C, Cpu3#cpu_state.f band (?FLAG_H bor ?FLAG_C)).

ccf_f3f5_from_a_test() ->
    %% CCF: F3/F5 come from A
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{a = 16#28, f = 0},  %% A bit3=1, bit5=1
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#3F),  %% CCF
    Cpu3 = z80_cpu:step(Cpu2),
    %% C=1, H=0 (old C was 0), N=0, F3=1, F5=1
    ?assertEqual(?FLAG_C bor 16#28, Cpu3#cpu_state.f).

%% --- RLCA/RRCA/RLA/RRA flag tests ---

rlca_flags_test() ->
    %% RLCA: A=0x88 (bit3=0, bit5=0, bit7=1), C=1
    %% Result: A=0x11, C=1, H=0, N=0, F3=0, F5=0 (from result 0x11)
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{a = 16#88, f = ?FLAG_C},  %% old carry set, should be ignored
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#07),  %% RLCA
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(16#11, Cpu3#cpu_state.a),
    ?assertEqual(?FLAG_C, Cpu3#cpu_state.f).

rrca_flags_test() ->
    %% RRCA: A=0x03 (bit0=1, bit1=1), C=0
    %% Result: A=0x81, C=1, H=0, N=0, F3=0, F5=0
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{a = 16#03},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#0F),  %% RRCA
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(16#81, Cpu3#cpu_state.a),
    ?assertEqual(?FLAG_C, Cpu3#cpu_state.f band (?FLAG_C bor ?FLAG_H bor ?FLAG_N)).

rla_flags_test() ->
    %% RLA: A=0x84, C=0 -> A=0x08, C=1, H=0, N=0
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{a = 16#84, f = 0},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#17),  %% RLA
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(16#08, Cpu3#cpu_state.a),
    ?assertEqual(?FLAG_C, Cpu3#cpu_state.f band (?FLAG_C bor ?FLAG_H bor ?FLAG_N)).

rra_flags_test() ->
    %% RRA: A=0x01, C=0 -> A=0x00, C=1, H=0, N=0
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{a = 16#01, f = 0},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#1F),  %% RRA
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(16#00, Cpu3#cpu_state.a),
    ?assertEqual(?FLAG_C, Cpu3#cpu_state.f band (?FLAG_C bor ?FLAG_H bor ?FLAG_N)).
