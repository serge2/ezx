-module(z80_cpu_main_logic_tests).

-include("z80_records.hrl").
-include_lib("eunit/include/eunit.hrl").

%% --- 8-bit Logic Tests ---

%% AND r / n / (HL)

and_b_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{a = 16#FF, b = 16#0F},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#A0),  %% AND B
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(16#0F, Cpu3#cpu_state.a),
    ?assertEqual(?FLAG_H, Cpu3#cpu_state.f band ?FLAG_H).

and_a_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{a = 16#55},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#A7),  %% AND A
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(16#55, Cpu3#cpu_state.a).

and_n_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{a = 16#FF},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#E6),  %% AND n
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#0F),
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#0F, Cpu4#cpu_state.a),
    ?assertEqual(2, z80_cpu:pc(Cpu4)).

and_mem_hl_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#0F),
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#A6),  %% AND (HL)
    Cpu3 = Cpu2#cpu_state{a = 16#FF, h = 16#40, l = 16#00},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#0F, Cpu4#cpu_state.a).

and_zero_flag_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{a = 16#0F},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#E6),  %% AND n
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#F0),
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#00, Cpu4#cpu_state.a),
    ?assertEqual(?FLAG_Z, Cpu4#cpu_state.f band ?FLAG_Z).

and_sign_flag_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{a = 16#FF},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#E6),  %% AND n
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#80),
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#80, Cpu4#cpu_state.a),
    ?assertEqual(?FLAG_S, Cpu4#cpu_state.f band ?FLAG_S).

and_parity_flag_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{a = 16#FF},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#E6),  %% AND n
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#55),  %% 0x55 has even parity (4 bits set)
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#55, Cpu4#cpu_state.a),
    ?assertEqual(?FLAG_V, Cpu4#cpu_state.f band ?FLAG_V).

%% OR r / n / (HL)

or_b_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{a = 16#0F, b = 16#F0},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#B0),  %% OR B
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(16#FF, Cpu3#cpu_state.a),
    ?assertEqual(0, Cpu3#cpu_state.f band ?FLAG_H).

or_n_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{a = 16#0F},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#F6),  %% OR n
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#F0),
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#FF, Cpu4#cpu_state.a).

or_mem_hl_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#F0),
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#B6),  %% OR (HL)
    Cpu3 = Cpu2#cpu_state{a = 16#0F, h = 16#40, l = 16#00},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#FF, Cpu4#cpu_state.a).

or_zero_flag_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{a = 16#00},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#F6),  %% OR n
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#00),
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#00, Cpu4#cpu_state.a),
    ?assertEqual(?FLAG_Z, Cpu4#cpu_state.f band ?FLAG_Z).

%% XOR r / n / (HL)

xor_b_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{a = 16#55, b = 16#AA},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#A8),  %% XOR B
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(16#FF, Cpu3#cpu_state.a),
    ?assertEqual(0, Cpu3#cpu_state.f band ?FLAG_H).

xor_a_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{a = 16#55},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#AF),  %% XOR A
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(16#00, Cpu3#cpu_state.a),
    ?assertEqual(?FLAG_Z, Cpu3#cpu_state.f band ?FLAG_Z).

xor_n_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{a = 16#55},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#EE),  %% XOR n
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#AA),
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#FF, Cpu4#cpu_state.a).

xor_mem_hl_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#AA),
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#AE),  %% XOR (HL)
    Cpu3 = Cpu2#cpu_state{a = 16#55, h = 16#40, l = 16#00},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#FF, Cpu4#cpu_state.a).

%% CP r / n / (HL)

cp_b_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{a = 16#30, b = 16#10},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#B8),  %% CP B
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(16#30, Cpu3#cpu_state.a),
    ?assertEqual(?FLAG_N, Cpu3#cpu_state.f band ?FLAG_N),
    ?assertEqual(0, Cpu3#cpu_state.f band ?FLAG_Z).

cp_a_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{a = 16#55},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#BF),  %% CP A
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(16#55, Cpu3#cpu_state.a),
    ?assertEqual(?FLAG_Z, Cpu3#cpu_state.f band ?FLAG_Z).

cp_n_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{a = 16#30},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#FE),  %% CP n
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#10),
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#30, Cpu4#cpu_state.a),
    ?assertEqual(0, Cpu4#cpu_state.f band ?FLAG_Z).

cp_mem_hl_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#10),
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#BE),  %% CP (HL)
    Cpu3 = Cpu2#cpu_state{a = 16#30, h = 16#40, l = 16#00},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#30, Cpu4#cpu_state.a).

cp_carry_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{a = 16#10, b = 16#20},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#B8),  %% CP B (A < B -> carry)
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(?FLAG_C, Cpu3#cpu_state.f band ?FLAG_C).

cp_no_carry_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{a = 16#30, b = 16#10},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#B8),  %% CP B (A > B -> no carry)
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(0, Cpu3#cpu_state.f band ?FLAG_C).

cp_half_carry_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{a = 16#10, b = 16#01},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#B8),  %% CP B
    Cpu3 = z80_cpu:step(Cpu2),
    %% 0x10 - 0x01 = 0x0F: borrow from bit 4 (0x10 & 0x0F = 0, 0x01 & 0x0F = 1, 0 < 1)
    ?assertEqual(?FLAG_H, Cpu3#cpu_state.f band ?FLAG_H).
