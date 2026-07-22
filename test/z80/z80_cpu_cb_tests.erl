-module(z80_cpu_cb_tests).

-include("z80_records.hrl").
-include_lib("eunit/include/eunit.hrl").

%% --- CB Prefix Tests ---

%% ============================================================================
%% RLC (Rotate Left Circular) - 0x00-0x07
%% ============================================================================

cb_rlc_b_timing_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#CB),  %% CB prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#00),  %% RLC B
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(8, z80_cpu:t_states(Cpu3)).

cb_rlc_b_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#CB),  %% CB prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#00),  %% RLC B
    Cpu3 = Cpu2#cpu_state{b = 16#81, f = 0},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#03, Cpu4#cpu_state.b),        %% 10000001 -> 00000011 (carry=1)
    ?assertEqual(?FLAG_C, Cpu4#cpu_state.f band ?FLAG_C),
    ?assertEqual(0, Cpu4#cpu_state.f band ?FLAG_Z),
    ?assertEqual(8, z80_cpu:t_states(Cpu4)).

cb_rlc_c_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#CB),  %% CB prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#01),  %% RLC C
    Cpu3 = Cpu2#cpu_state{c = 16#40, f = 0},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#80, Cpu4#cpu_state.c),        %% 01000000 -> 10000000
    ?assertEqual(0, Cpu4#cpu_state.f band ?FLAG_C),
    ?assertEqual(?FLAG_S, Cpu4#cpu_state.f band ?FLAG_S),
    ?assertEqual(8, z80_cpu:t_states(Cpu4)).

cb_rlc_d_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#CB),  %% CB prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#02),  %% RLC D
    Cpu3 = Cpu2#cpu_state{d = 16#FF, f = 0},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#FF, Cpu4#cpu_state.d),        %% 11111111 -> 11111111 (carry=1)
    ?assertEqual(?FLAG_C, Cpu4#cpu_state.f band ?FLAG_C),
    ?assertEqual(8, z80_cpu:t_states(Cpu4)).

cb_rlc_e_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#CB),  %% CB prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#03),  %% RLC E
    Cpu3 = Cpu2#cpu_state{e = 16#01, f = 0},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#02, Cpu4#cpu_state.e),
    ?assertEqual(8, z80_cpu:t_states(Cpu4)).

cb_rlc_h_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#CB),  %% CB prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#04),  %% RLC H
    Cpu3 = Cpu2#cpu_state{h = 16#80, f = 0},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#01, Cpu4#cpu_state.h),
    ?assertEqual(?FLAG_C, Cpu4#cpu_state.f band ?FLAG_C),
    ?assertEqual(8, z80_cpu:t_states(Cpu4)).

cb_rlc_l_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#CB),  %% CB prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#05),  %% RLC L
    Cpu3 = Cpu2#cpu_state{l = 16#55, f = 0},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#AA, Cpu4#cpu_state.l),        %% 01010101 -> 10101010
    ?assertEqual(0, Cpu4#cpu_state.f band ?FLAG_C),
    ?assertEqual(8, z80_cpu:t_states(Cpu4)).

cb_rlc_a_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#CB),  %% CB prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#07),  %% RLC A
    Cpu3 = Cpu2#cpu_state{a = 16#C0, f = 0},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#81, Cpu4#cpu_state.a),        %% 11000000 -> 10000001 (carry=1)
    ?assertEqual(?FLAG_C, Cpu4#cpu_state.f band ?FLAG_C),
    ?assertEqual(8, z80_cpu:t_states(Cpu4)).

cb_rlc_hl_test() ->
    %% RLC (HL) - 0x06: read (HL), RLC, write back, 15 T-states
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#80),  %% value at HL
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#CB),  %% CB prefix
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#06),  %% RLC (HL)
    Cpu4 = Cpu3#cpu_state{h = 16#40, l = 16#00},
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(16#01, test_helpers:read_mem(Cpu5, 16#4000)),  %% 10000000 -> 00000001
    ?assertEqual(?FLAG_C, Cpu5#cpu_state.f band ?FLAG_C),
    ?assertEqual(15, z80_cpu:t_states(Cpu5)).

cb_rlc_hl_zero_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#00),  %% 0x00 -> 0x00, Z=1
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#CB),  %% CB prefix
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#06),  %% RLC (HL)
    Cpu4 = Cpu3#cpu_state{h = 16#40, l = 16#00},
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(16#00, test_helpers:read_mem(Cpu5, 16#4000)),
    ?assertEqual(?FLAG_Z, Cpu5#cpu_state.f band ?FLAG_Z),
    ?assertEqual(0, Cpu5#cpu_state.f band ?FLAG_C).

%% ============================================================================
%% RRC (Rotate Right Circular) - 0x08-0x0F
%% ============================================================================

cb_rrc_b_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#CB),  %% CB prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#08),  %% RRC B
    Cpu3 = Cpu2#cpu_state{b = 16#01, f = 0},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#80, Cpu4#cpu_state.b),        %% 00000001 -> 10000000 (carry=1)
    ?assertEqual(?FLAG_C, Cpu4#cpu_state.f band ?FLAG_C),
    ?assertEqual(?FLAG_S, Cpu4#cpu_state.f band ?FLAG_S),
    ?assertEqual(8, z80_cpu:t_states(Cpu4)).

cb_rrc_c_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#CB),  %% CB prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#09),  %% RRC C
    Cpu3 = Cpu2#cpu_state{c = 16#02, f = 0},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#01, Cpu4#cpu_state.c),
    ?assertEqual(0, Cpu4#cpu_state.f band ?FLAG_C),
    ?assertEqual(8, z80_cpu:t_states(Cpu4)).

cb_rrc_a_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#CB),  %% CB prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#0F),  %% RRC A
    Cpu3 = Cpu2#cpu_state{a = 16#80, f = 0},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#40, Cpu4#cpu_state.a),        %% 10000000 -> 01000000 (carry=0)
    ?assertEqual(0, Cpu4#cpu_state.f band ?FLAG_C),
    ?assertEqual(8, z80_cpu:t_states(Cpu4)).

cb_rrc_hl_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#01),  %% Memory at HL = 0x01
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#CB),  %% CB prefix
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#0E),  %% RRC (HL)
    Cpu4 = Cpu3#cpu_state{h = 16#40, l = 16#00},
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(16#80, test_helpers:read_mem(Cpu5, 16#4000)),  %% RRC 0x01 = 0x80, carry=1
    ?assertEqual(?FLAG_C, Cpu5#cpu_state.f band ?FLAG_C),
    ?assertEqual(?FLAG_S, Cpu5#cpu_state.f band ?FLAG_S),
    ?assertEqual(15, z80_cpu:t_states(Cpu5)).

%% ============================================================================
%% RL (Rotate Left through Carry) - 0x10-0x17
%% ============================================================================

cb_rl_b_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#CB),  %% CB prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#10),  %% RL B
    Cpu3 = Cpu2#cpu_state{b = 16#81, f = 0},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#02, Cpu4#cpu_state.b),        %% 10000001 -> 00000010 (carry=1)
    ?assertEqual(?FLAG_C, Cpu4#cpu_state.f band ?FLAG_C),
    ?assertEqual(8, z80_cpu:t_states(Cpu4)).

cb_rl_b_carry_set_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#CB),  %% CB prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#10),  %% RL B
    Cpu3 = Cpu2#cpu_state{b = 16#40, f = 16#01},  %% Carry=1
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#81, Cpu4#cpu_state.b),        %% 01000000 + carry=1 -> 10000001
    ?assertEqual(0, Cpu4#cpu_state.f band ?FLAG_C),
    ?assertEqual(8, z80_cpu:t_states(Cpu4)).

cb_rl_c_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#CB),  %% CB prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#11),  %% RL C
    Cpu3 = Cpu2#cpu_state{c = 16#80, f = 16#01},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#01, Cpu4#cpu_state.c),        %% 10000000 + carry=1 -> 00000001
    ?assertEqual(?FLAG_C, Cpu4#cpu_state.f band ?FLAG_C),
    ?assertEqual(8, z80_cpu:t_states(Cpu4)).

cb_rl_a_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#CB),  %% CB prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#17),  %% RL A
    Cpu3 = Cpu2#cpu_state{a = 16#FF, f = 0},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#FE, Cpu4#cpu_state.a),        %% 11111111 -> 11111110 (carry=1)
    ?assertEqual(?FLAG_C, Cpu4#cpu_state.f band ?FLAG_C),
    ?assertEqual(8, z80_cpu:t_states(Cpu4)).

cb_rl_hl_test() ->
    %% RL (HL) - 0x16: read (HL), RL, write back, 15 T-states
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#7F),  %% 01111111
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#CB),  %% CB prefix
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#16),  %% RL (HL)
    Cpu4 = Cpu3#cpu_state{h = 16#40, l = 16#00, f = 16#01},  %% carry=1
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(16#FF, test_helpers:read_mem(Cpu5, 16#4000)),  %% 01111111 + carry=1 = 11111111
    ?assertEqual(0, Cpu5#cpu_state.f band ?FLAG_C),
    ?assertEqual(15, z80_cpu:t_states(Cpu5)).

cb_rl_hl_no_carry_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#7F),  %% 01111111
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#CB),  %% CB prefix
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#16),  %% RL (HL)
    Cpu4 = Cpu3#cpu_state{h = 16#40, l = 16#00, f = 0},  %% carry=0
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(16#FE, test_helpers:read_mem(Cpu5, 16#4000)),  %% 01111111 + carry=0 = 11111110
    ?assertEqual(0, Cpu5#cpu_state.f band ?FLAG_C).

%% ============================================================================
%% RR (Rotate Right through Carry) - 0x18-0x1F
%% ============================================================================

cb_rr_b_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#CB),  %% CB prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#18),  %% RR B
    Cpu3 = Cpu2#cpu_state{b = 16#01, f = 0},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#00, Cpu4#cpu_state.b),        %% 00000001 -> 00000000 (carry=1)
    ?assertEqual(?FLAG_C, Cpu4#cpu_state.f band ?FLAG_C),
    ?assertEqual(?FLAG_Z, Cpu4#cpu_state.f band ?FLAG_Z),
    ?assertEqual(8, z80_cpu:t_states(Cpu4)).

cb_rr_b_carry_set_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#CB),  %% CB prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#18),  %% RR B
    Cpu3 = Cpu2#cpu_state{b = 16#02, f = 16#01},  %% Carry=1
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#81, Cpu4#cpu_state.b),        %% 00000010 + carry=1 -> 10000001
    ?assertEqual(0, Cpu4#cpu_state.f band ?FLAG_C),
    ?assertEqual(8, z80_cpu:t_states(Cpu4)).

cb_rr_c_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#CB),  %% CB prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#19),  %% RR C
    Cpu3 = Cpu2#cpu_state{c = 16#80, f = 0},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#40, Cpu4#cpu_state.c),        %% 10000000 -> 01000000 (carry=0)
    ?assertEqual(0, Cpu4#cpu_state.f band ?FLAG_C),
    ?assertEqual(8, z80_cpu:t_states(Cpu4)).

cb_rr_a_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#CB),  %% CB prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#1F),  %% RR A
    Cpu3 = Cpu2#cpu_state{a = 16#02, f = 0},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#01, Cpu4#cpu_state.a),        %% 00000010 -> 00000001 (carry=0)
    ?assertEqual(0, Cpu4#cpu_state.f band ?FLAG_C),
    ?assertEqual(8, z80_cpu:t_states(Cpu4)).

cb_rr_hl_test() ->
    %% RR (HL) - 0x1E: read (HL), RR, write back, 15 T-states
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#02),  %% 00000010
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#CB),  %% CB prefix
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#1E),  %% RR (HL)
    Cpu4 = Cpu3#cpu_state{h = 16#40, l = 16#00, f = 16#01},  %% carry=1
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(16#81, test_helpers:read_mem(Cpu5, 16#4000)),  %% 00000010 + carry=1 = 10000001
    ?assertEqual(0, Cpu5#cpu_state.f band ?FLAG_C),
    ?assertEqual(15, z80_cpu:t_states(Cpu5)).

cb_rr_hl_no_carry_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#80),  %% 10000000
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#CB),  %% CB prefix
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#1E),  %% RR (HL)
    Cpu4 = Cpu3#cpu_state{h = 16#40, l = 16#00, f = 0},  %% carry=0
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(16#40, test_helpers:read_mem(Cpu5, 16#4000)),  %% 10000000 + carry=0 = 01000000
    ?assertEqual(0, Cpu5#cpu_state.f band ?FLAG_C).

%% ============================================================================
%% SLA (Shift Left Arithmetic) - 0x20-0x27
%% ============================================================================

cb_sla_b_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#CB),  %% CB prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#20),  %% SLA B
    Cpu3 = Cpu2#cpu_state{b = 16#40, f = 0},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#80, Cpu4#cpu_state.b),        %% 01000000 -> 10000000
    ?assertEqual(0, Cpu4#cpu_state.f band ?FLAG_C),
    ?assertEqual(?FLAG_S, Cpu4#cpu_state.f band ?FLAG_S),
    ?assertEqual(0, Cpu4#cpu_state.f band ?FLAG_Z),
    ?assertEqual(8, z80_cpu:t_states(Cpu4)).

cb_sla_b_carry_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#CB),  %% CB prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#20),  %% SLA B
    Cpu3 = Cpu2#cpu_state{b = 16#80, f = 0},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#00, Cpu4#cpu_state.b),        %% 10000000 -> 00000000 (carry=1)
    ?assertEqual(?FLAG_C, Cpu4#cpu_state.f band ?FLAG_C),
    ?assertEqual(?FLAG_Z, Cpu4#cpu_state.f band ?FLAG_Z),
    ?assertEqual(8, z80_cpu:t_states(Cpu4)).

cb_sla_c_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#CB),  %% CB prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#21),  %% SLA C
    Cpu3 = Cpu2#cpu_state{c = 16#55, f = 0},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#AA, Cpu4#cpu_state.c),        %% 01010101 -> 10101010
    ?assertEqual(0, Cpu4#cpu_state.f band ?FLAG_C),
    ?assertEqual(8, z80_cpu:t_states(Cpu4)).

cb_sla_d_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#CB),  %% CB prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#22),  %% SLA D
    Cpu3 = Cpu2#cpu_state{d = 16#01, f = 0},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#02, Cpu4#cpu_state.d),
    ?assertEqual(8, z80_cpu:t_states(Cpu4)).

cb_sla_a_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#CB),  %% CB prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#27),  %% SLA A
    Cpu3 = Cpu2#cpu_state{a = 16#FF, f = 0},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#FE, Cpu4#cpu_state.a),        %% 11111111 -> 11111110 (carry=1)
    ?assertEqual(?FLAG_C, Cpu4#cpu_state.f band ?FLAG_C),
    ?assertEqual(8, z80_cpu:t_states(Cpu4)).

cb_sla_hl_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#40),  %% 01000000 -> 10000000, carry=0
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#CB),  %% CB prefix
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#26),  %% SLA (HL)
    Cpu4 = Cpu3#cpu_state{h = 16#40, l = 16#00},
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(16#80, test_helpers:read_mem(Cpu5, 16#4000)),
    ?assertEqual(?FLAG_S, Cpu5#cpu_state.f band ?FLAG_S),
    ?assertEqual(0, Cpu5#cpu_state.f band ?FLAG_C),  %% carry from bit 7 = 0
    ?assertEqual(15, z80_cpu:t_states(Cpu5)).

cb_sla_hl_carry_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#80),  %% 10000000 -> 00000000, carry=1
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#CB),  %% CB prefix
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#26),  %% SLA (HL)
    Cpu4 = Cpu3#cpu_state{h = 16#40, l = 16#00},
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(16#00, test_helpers:read_mem(Cpu5, 16#4000)),
    ?assertEqual(?FLAG_C, Cpu5#cpu_state.f band ?FLAG_C),
    ?assertEqual(?FLAG_Z, Cpu5#cpu_state.f band ?FLAG_Z).

%% ============================================================================
%% SRA (Shift Right Arithmetic) - 0x28-0x2F
%% ============================================================================

cb_sra_b_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#CB),  %% CB prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#28),  %% SRA B
    Cpu3 = Cpu2#cpu_state{b = 16#81, f = 0},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#C0, Cpu4#cpu_state.b),        %% 10000001 -> 11000000 (carry=1, sign preserved)
    ?assertEqual(?FLAG_C, Cpu4#cpu_state.f band ?FLAG_C),
    ?assertEqual(?FLAG_S, Cpu4#cpu_state.f band ?FLAG_S),
    ?assertEqual(8, z80_cpu:t_states(Cpu4)).

cb_sra_b_positive_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#CB),  %% CB prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#28),  %% SRA B
    Cpu3 = Cpu2#cpu_state{b = 16#40, f = 0},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#20, Cpu4#cpu_state.b),        %% 01000000 -> 00100000
    ?assertEqual(0, Cpu4#cpu_state.f band ?FLAG_C),
    ?assertEqual(0, Cpu4#cpu_state.f band ?FLAG_S),
    ?assertEqual(8, z80_cpu:t_states(Cpu4)).

cb_sra_c_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#CB),  %% CB prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#29),  %% SRA C
    Cpu3 = Cpu2#cpu_state{c = 16#FF, f = 0},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#FF, Cpu4#cpu_state.c),        %% 11111111 -> 11111111 (carry=1, sign preserved)
    ?assertEqual(?FLAG_C, Cpu4#cpu_state.f band ?FLAG_C),
    ?assertEqual(8, z80_cpu:t_states(Cpu4)).

cb_sra_a_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#CB),  %% CB prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#2F),  %% SRA A
    Cpu3 = Cpu2#cpu_state{a = 16#02, f = 0},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#01, Cpu4#cpu_state.a),        %% 00000010 -> 00000001
    ?assertEqual(0, Cpu4#cpu_state.f band ?FLAG_C),
    ?assertEqual(8, z80_cpu:t_states(Cpu4)).

cb_sra_hl_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#80),  %% 10000000 -> 11000000 (preserve sign)
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#CB),  %% CB prefix
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#2E),  %% SRA (HL)
    Cpu4 = Cpu3#cpu_state{h = 16#40, l = 16#00},
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(16#C0, test_helpers:read_mem(Cpu5, 16#4000)),
    ?assertEqual(?FLAG_S, Cpu5#cpu_state.f band ?FLAG_S),
    ?assertEqual(15, z80_cpu:t_states(Cpu5)).

cb_sra_hl_positive_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#40),  %% 01000000 -> 00100000
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#CB),  %% CB prefix
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#2E),  %% SRA (HL)
    Cpu4 = Cpu3#cpu_state{h = 16#40, l = 16#00},
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(16#20, test_helpers:read_mem(Cpu5, 16#4000)),
    ?assertEqual(0, Cpu5#cpu_state.f band ?FLAG_S),
    ?assertEqual(0, Cpu5#cpu_state.f band ?FLAG_C).

cb_sra_hl_carry_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#01),  %% 00000001 -> 00000000, carry=1
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#CB),  %% CB prefix
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#2E),  %% SRA (HL)
    Cpu4 = Cpu3#cpu_state{h = 16#40, l = 16#00},
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(16#00, test_helpers:read_mem(Cpu5, 16#4000)),
    ?assertEqual(?FLAG_C, Cpu5#cpu_state.f band ?FLAG_C),
    ?assertEqual(?FLAG_Z, Cpu5#cpu_state.f band ?FLAG_Z).

%% ============================================================================
%% SLL (Shift Left Logical, undocumented) - 0x30-0x37
%% ============================================================================

cb_sll_b_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#CB),  %% CB prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#30),  %% SLL B (undocumented)
    Cpu3 = Cpu2#cpu_state{b = 16#80, f = 0},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#01, Cpu4#cpu_state.b),        %% 10000000 -> 00000001 (bit 0 set to 1)
    ?assertEqual(?FLAG_C, Cpu4#cpu_state.f band ?FLAG_C),
    ?assertEqual(8, z80_cpu:t_states(Cpu4)).

cb_sll_c_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#CB),  %% CB prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#31),  %% SLL C
    Cpu3 = Cpu2#cpu_state{c = 16#40, f = 0},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#81, Cpu4#cpu_state.c),        %% 01000000 -> 10000001
    ?assertEqual(0, Cpu4#cpu_state.f band ?FLAG_C),
    ?assertEqual(8, z80_cpu:t_states(Cpu4)).

cb_sll_a_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#CB),  %% CB prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#37),  %% SLL A
    Cpu3 = Cpu2#cpu_state{a = 16#55, f = 0},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#AB, Cpu4#cpu_state.a),        %% 01010101 -> 10101011
    ?assertEqual(0, Cpu4#cpu_state.f band ?FLAG_C),
    ?assertEqual(8, z80_cpu:t_states(Cpu4)).

cb_sll_hl_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#40),  %% 01000000 -> 10000001
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#CB),  %% CB prefix
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#36),  %% SLL (HL)
    Cpu4 = Cpu3#cpu_state{h = 16#40, l = 16#00},
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(16#81, test_helpers:read_mem(Cpu5, 16#4000)),
    ?assertEqual(?FLAG_S, Cpu5#cpu_state.f band ?FLAG_S),
    ?assertEqual(0, Cpu5#cpu_state.f band ?FLAG_C),  %% carry from bit 7 = 0
    ?assertEqual(15, z80_cpu:t_states(Cpu5)).

cb_sll_hl_carry_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#80),  %% 10000000 -> 00000001, carry=1
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#CB),  %% CB prefix
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#36),  %% SLL (HL)
    Cpu4 = Cpu3#cpu_state{h = 16#40, l = 16#00},
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(16#01, test_helpers:read_mem(Cpu5, 16#4000)),
    ?assertEqual(?FLAG_C, Cpu5#cpu_state.f band ?FLAG_C).

%% ============================================================================
%% SRL (Shift Right Logical) - 0x38-0x3F
%% ============================================================================

cb_srl_b_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#CB),  %% CB prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#38),  %% SRL B
    Cpu3 = Cpu2#cpu_state{b = 16#81, f = 0},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#40, Cpu4#cpu_state.b),        %% 10000001 -> 01000000 (carry=1, sign cleared)
    ?assertEqual(?FLAG_C, Cpu4#cpu_state.f band ?FLAG_C),
    ?assertEqual(0, Cpu4#cpu_state.f band ?FLAG_S),
    ?assertEqual(8, z80_cpu:t_states(Cpu4)).

cb_srl_c_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#CB),  %% CB prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#39),  %% SRL C
    Cpu3 = Cpu2#cpu_state{c = 16#02, f = 0},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#01, Cpu4#cpu_state.c),        %% 00000010 -> 00000001
    ?assertEqual(0, Cpu4#cpu_state.f band ?FLAG_C),
    ?assertEqual(8, z80_cpu:t_states(Cpu4)).

cb_srl_d_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#CB),  %% CB prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#3A),  %% SRL D
    Cpu3 = Cpu2#cpu_state{d = 16#FF, f = 0},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#7F, Cpu4#cpu_state.d),        %% 11111111 -> 01111111 (carry=1)
    ?assertEqual(?FLAG_C, Cpu4#cpu_state.f band ?FLAG_C),
    ?assertEqual(0, Cpu4#cpu_state.f band ?FLAG_S),
    ?assertEqual(8, z80_cpu:t_states(Cpu4)).

cb_srl_a_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#CB),  %% CB prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#3F),  %% SRL A
    Cpu3 = Cpu2#cpu_state{a = 16#01, f = 0},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#00, Cpu4#cpu_state.a),        %% 00000001 -> 00000000 (carry=1)
    ?assertEqual(?FLAG_C, Cpu4#cpu_state.f band ?FLAG_C),
    ?assertEqual(?FLAG_Z, Cpu4#cpu_state.f band ?FLAG_Z),
    ?assertEqual(8, z80_cpu:t_states(Cpu4)).

cb_srl_hl_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#81),  %% 10000001 -> 01000000
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#CB),  %% CB prefix
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#3E),  %% SRL (HL)
    Cpu4 = Cpu3#cpu_state{h = 16#40, l = 16#00},
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(16#40, test_helpers:read_mem(Cpu5, 16#4000)),
    ?assertEqual(0, Cpu5#cpu_state.f band ?FLAG_S),
    ?assertEqual(?FLAG_C, Cpu5#cpu_state.f band ?FLAG_C),
    ?assertEqual(15, z80_cpu:t_states(Cpu5)).

cb_srl_hl_carry_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#01),  %% 00000001 -> 00000000
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#CB),  %% CB prefix
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#3E),  %% SRL (HL)
    Cpu4 = Cpu3#cpu_state{h = 16#40, l = 16#00},
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(16#00, test_helpers:read_mem(Cpu5, 16#4000)),
    ?assertEqual(?FLAG_C, Cpu5#cpu_state.f band ?FLAG_C),
    ?assertEqual(?FLAG_Z, Cpu5#cpu_state.f band ?FLAG_Z).

%% ============================================================================
%% BIT b,r - 0x40-0x7F
%% ============================================================================

cb_bit_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#CB),  %% CB prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#40),  %% BIT 0,B
    Cpu3 = Cpu2#cpu_state{b = 16#01},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#01, Cpu4#cpu_state.b),
    ?assertEqual(0, Cpu4#cpu_state.f band ?FLAG_Z),
    ?assertEqual(?FLAG_H, Cpu4#cpu_state.f band ?FLAG_H),
    ?assertEqual(0, Cpu4#cpu_state.f band ?FLAG_V),
    ?assertEqual(0, Cpu4#cpu_state.f band ?FLAG_N),
    ?assertEqual(8, z80_cpu:t_states(Cpu4)).

cb_bit_zero_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#CB),  %% CB prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#40),  %% BIT 0,B
    Cpu3 = Cpu2#cpu_state{b = 16#00},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(?FLAG_Z, Cpu4#cpu_state.f band ?FLAG_Z),
    ?assertEqual(?FLAG_V, Cpu4#cpu_state.f band ?FLAG_V),
    ?assertEqual(8, z80_cpu:t_states(Cpu4)).

cb_bit_1_b_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#CB),  %% CB prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#48),  %% BIT 1,B
    Cpu3 = Cpu2#cpu_state{b = 16#02},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(0, Cpu4#cpu_state.f band ?FLAG_Z),
    ?assertEqual(8, z80_cpu:t_states(Cpu4)).

cb_bit_7_b_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#CB),  %% CB prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#78),  %% BIT 7,B
    Cpu3 = Cpu2#cpu_state{b = 16#80},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(0, Cpu4#cpu_state.f band ?FLAG_Z),
    ?assertEqual(?FLAG_S, Cpu4#cpu_state.f band ?FLAG_S),
    ?assertEqual(8, z80_cpu:t_states(Cpu4)).

cb_bit_7_b_zero_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#CB),  %% CB prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#78),  %% BIT 7,B
    Cpu3 = Cpu2#cpu_state{b = 16#7F},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(?FLAG_Z, Cpu4#cpu_state.f band ?FLAG_Z),
    ?assertEqual(0, Cpu4#cpu_state.f band ?FLAG_S),
    ?assertEqual(8, z80_cpu:t_states(Cpu4)).

cb_bit_0_c_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#CB),  %% CB prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#41),  %% BIT 0,C
    Cpu3 = Cpu2#cpu_state{c = 16#01},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(0, Cpu4#cpu_state.f band ?FLAG_Z),
    ?assertEqual(8, z80_cpu:t_states(Cpu4)).

cb_bit_3_d_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#CB),  %% CB prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#5A),  %% BIT 3,D
    Cpu3 = Cpu2#cpu_state{d = 16#08},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(0, Cpu4#cpu_state.f band ?FLAG_Z),
    ?assertEqual(8, z80_cpu:t_states(Cpu4)).

cb_bit_hl_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#01),
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#CB),  %% CB prefix
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#46),  %% BIT 0,(HL)
    Cpu4 = Cpu3#cpu_state{h = 16#40, l = 16#00},
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(12, z80_cpu:t_states(Cpu5)).

cb_bit_5_hl_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#20),
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#CB),  %% CB prefix
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#6E),  %% BIT 5,(HL)
    Cpu4 = Cpu3#cpu_state{h = 16#40, l = 16#00},
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(12, z80_cpu:t_states(Cpu5)).

cb_bit_7_a_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#CB),  %% CB prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#7F),  %% BIT 7,A
    Cpu3 = Cpu2#cpu_state{a = 16#80},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(0, Cpu4#cpu_state.f band ?FLAG_Z),
    ?assertEqual(?FLAG_S, Cpu4#cpu_state.f band ?FLAG_S),
    ?assertEqual(8, z80_cpu:t_states(Cpu4)).

%% ============================================================================
%% RES b,r - 0x80-0xBF
%% ============================================================================

cb_res_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#CB),  %% CB prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#80),  %% RES 0,B
    Cpu3 = Cpu2#cpu_state{b = 16#03},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#02, Cpu4#cpu_state.b),
    ?assertEqual(8, z80_cpu:t_states(Cpu4)).

cb_res_1_b_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#CB),  %% CB prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#88),  %% RES 1,B
    Cpu3 = Cpu2#cpu_state{b = 16#06},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#04, Cpu4#cpu_state.b),
    ?assertEqual(8, z80_cpu:t_states(Cpu4)).

cb_res_7_b_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#CB),  %% CB prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#B8),  %% RES 7,B
    Cpu3 = Cpu2#cpu_state{b = 16#FF},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#7F, Cpu4#cpu_state.b),
    ?assertEqual(8, z80_cpu:t_states(Cpu4)).

cb_res_0_c_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#CB),  %% CB prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#81),  %% RES 0,C
    Cpu3 = Cpu2#cpu_state{c = 16#FF},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#FE, Cpu4#cpu_state.c),
    ?assertEqual(8, z80_cpu:t_states(Cpu4)).

cb_res_3_e_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#CB),  %% CB prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#9B),  %% RES 3,E
    Cpu3 = Cpu2#cpu_state{e = 16#F8},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#F0, Cpu4#cpu_state.e),
    ?assertEqual(8, z80_cpu:t_states(Cpu4)).

cb_res_hl_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#03),
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#CB),  %% CB prefix
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#86),  %% RES 0,(HL)
    Cpu4 = Cpu3#cpu_state{h = 16#40, l = 16#00},
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(16#02, test_helpers:read_mem(Cpu5, 16#4000)),
    ?assertEqual(15, z80_cpu:t_states(Cpu5)).

cb_res_4_hl_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#FF),
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#CB),  %% CB prefix
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#A6),  %% RES 4,(HL)
    Cpu4 = Cpu3#cpu_state{h = 16#40, l = 16#00},
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(16#EF, test_helpers:read_mem(Cpu5, 16#4000)),
    ?assertEqual(15, z80_cpu:t_states(Cpu5)).

cb_res_7_a_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#CB),  %% CB prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#BF),  %% RES 7,A
    Cpu3 = Cpu2#cpu_state{a = 16#FF},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#7F, Cpu4#cpu_state.a),
    ?assertEqual(8, z80_cpu:t_states(Cpu4)).

%% ============================================================================
%% SET b,r - 0xC0-0xFF
%% ============================================================================

cb_set_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#CB),  %% CB prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#C0),  %% SET 0,B
    Cpu3 = Cpu2#cpu_state{b = 16#02},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#03, Cpu4#cpu_state.b),
    ?assertEqual(8, z80_cpu:t_states(Cpu4)).

cb_set_1_b_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#CB),  %% CB prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#C8),  %% SET 1,B
    Cpu3 = Cpu2#cpu_state{b = 16#01},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#03, Cpu4#cpu_state.b),
    ?assertEqual(8, z80_cpu:t_states(Cpu4)).

cb_set_7_b_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#CB),  %% CB prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#F8),  %% SET 7,B
    Cpu3 = Cpu2#cpu_state{b = 16#00},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#80, Cpu4#cpu_state.b),
    ?assertEqual(8, z80_cpu:t_states(Cpu4)).

cb_set_0_c_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#CB),  %% CB prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#C1),  %% SET 0,C
    Cpu3 = Cpu2#cpu_state{c = 16#FE},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#FF, Cpu4#cpu_state.c),
    ?assertEqual(8, z80_cpu:t_states(Cpu4)).

cb_set_5_d_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#CB),  %% CB prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#EA),  %% SET 5,D
    Cpu3 = Cpu2#cpu_state{d = 16#00},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#20, Cpu4#cpu_state.d),
    ?assertEqual(8, z80_cpu:t_states(Cpu4)).

cb_set_hl_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#02),
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#CB),  %% CB prefix
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#C6),  %% SET 0,(HL)
    Cpu4 = Cpu3#cpu_state{h = 16#40, l = 16#00},
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(16#03, test_helpers:read_mem(Cpu5, 16#4000)),
    ?assertEqual(15, z80_cpu:t_states(Cpu5)).

cb_set_2_hl_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#F3),
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#CB),  %% CB prefix
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#D6),  %% SET 2,(HL)
    Cpu4 = Cpu3#cpu_state{h = 16#40, l = 16#00},
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(16#F7, test_helpers:read_mem(Cpu5, 16#4000)),
    ?assertEqual(15, z80_cpu:t_states(Cpu5)).

cb_set_7_a_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#CB),  %% CB prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#FF),  %% SET 7,A
    Cpu3 = Cpu2#cpu_state{a = 16#00},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#80, Cpu4#cpu_state.a),
    ?assertEqual(8, z80_cpu:t_states(Cpu4)).

%% ============================================================================
%% F3/F5 Flag Tests for CB Shift/Rotate ops
%% ============================================================================

%% RLC: F3/F5 from result
cb_rlc_b_f3f5_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#CB),
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#00),  %% RLC B
    %% B = 0x28 -> result 0x50, 0x50 & 0x28 = 0x00 (bit3=0, bit5=0)
    Cpu3 = Cpu2#cpu_state{b = 16#28, f = 0},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#50, Cpu4#cpu_state.b),
    ?assertEqual(16#00, Cpu4#cpu_state.f band 16#28).

cb_rlc_a_f3f5_both_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#CB),
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#07),  %% RLC A
    %% A = 0x01 -> result 0x02, no F3/F5 set
    Cpu3 = Cpu2#cpu_state{a = 16#01, f = 0},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(0, Cpu4#cpu_state.f band 16#28).

%% RRC: F3/F5 from result
cb_rrc_b_f3f5_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#CB),
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#08),  %% RRC B
    %% B = 0xA0 -> result 0x50, 0x50 & 0x28 = 0x00
    Cpu3 = Cpu2#cpu_state{b = 16#A0, f = 0},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#50, Cpu4#cpu_state.b),
    ?assertEqual(16#00, Cpu4#cpu_state.f band 16#28).

%% SLA: F3/F5 from result
cb_sla_b_f3f5_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#CB),
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#20),  %% SLA B
    %% B = 0x14 -> result 0x28, 0x28 & 0x28 = 0x28
    Cpu3 = Cpu2#cpu_state{b = 16#14, f = 0},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#28, Cpu4#cpu_state.b),
    ?assertEqual(16#28, Cpu4#cpu_state.f band 16#28).

%% SRA: F3/F5 from result
cb_sra_b_f3f5_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#CB),
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#28),  %% SRA B
    %% B = 0xA8 -> result 0xD4, 0xD4 & 0x28 = 0x00
    Cpu3 = Cpu2#cpu_state{b = 16#A8, f = 0},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#D4, Cpu4#cpu_state.b),
    ?assertEqual(16#00, Cpu4#cpu_state.f band 16#28).

%% BIT b,r: F3/F5 from register value
cb_bit_3_b_f3f5_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#CB),
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#58),  %% BIT 3,B
    Cpu3 = Cpu2#cpu_state{b = 16#28},  %% B has bit3=1, bit5=1
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#28, Cpu4#cpu_state.f band 16#28).  %% F3=1, F5=1

cb_bit_5_b_f3f5_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#CB),
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#68),  %% BIT 5,B
    Cpu3 = Cpu2#cpu_state{b = 16#20},  %% B has bit3=0, bit5=1
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#20, Cpu4#cpu_state.f band 16#28).  %% F3=0, F5=1

cb_bit_7_s_flag_only_test() ->
    %% BIT 7: S flag set only for BIT 7 (already tested above, but confirm other bits don't set S)
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#CB),
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#78),  %% BIT 7,B
    Cpu3 = Cpu2#cpu_state{b = 16#80},  %% B has bit7=1
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(?FLAG_S, Cpu4#cpu_state.f band ?FLAG_S),
    ?assertEqual(0, Cpu4#cpu_state.f band ?FLAG_Z).

%% BIT b,(HL): F3/F5 from H register
cb_bit_3_hl_f3f5_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#FF),
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#CB),
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#5E),  %% BIT 3,(HL)
    %% H=0x40 (bit3=0, bit5=0), (HL)=0xFF
    Cpu4 = Cpu3#cpu_state{h = 16#40, l = 16#00},
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(16#00, Cpu5#cpu_state.f band 16#28).  %% F3=0, F5=0 from H

%% RL: F3/F5 from result
cb_rl_b_f3f5_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#CB),
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#10),  %% RL B
    %% B = 0x14 -> result 0x28 (bit3=1, bit5=1), carry=0
    Cpu3 = Cpu2#cpu_state{b = 16#14, f = 0},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#28, Cpu4#cpu_state.b),
    ?assertEqual(16#28, Cpu4#cpu_state.f band 16#28).

%% RR: F3/F5 from result
cb_rr_b_f3f5_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#CB),
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#18),  %% RR B
    %% B = 0x05 -> result 0x02 (no F3/F5), carry=1
    Cpu3 = Cpu2#cpu_state{b = 16#05, f = 0},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#02, Cpu4#cpu_state.b),
    ?assertEqual(0, Cpu4#cpu_state.f band 16#28).

%% SRL: F3/F5 from result
cb_srl_b_f3f5_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#CB),
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#38),  %% SRL B
    %% B = 0x50 -> result 0x28 (bit3=1, bit5=1), carry=0
    Cpu3 = Cpu2#cpu_state{b = 16#50, f = 0},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#28, Cpu4#cpu_state.b),
    ?assertEqual(16#28, Cpu4#cpu_state.f band 16#28).

%% SLL: F3/F5 from result
cb_sll_b_f3f5_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#CB),
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#30),  %% SLL B
    %% B = 0x0A -> result 0x15 (no F3/F5), carry=0
    Cpu3 = Cpu2#cpu_state{b = 16#0A, f = 0},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#15, Cpu4#cpu_state.b),
    ?assertEqual(0, Cpu4#cpu_state.f band 16#28).

%% CB ops: verify N=0, H=0 for all shift/rotate types
cb_rlc_h_n_zero_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#CB),
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#00),  %% RLC B
    Cpu3 = Cpu2#cpu_state{b = 16#80, f = ?FLAG_H bor ?FLAG_N},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(0, Cpu4#cpu_state.f band (?FLAG_H bor ?FLAG_N)).

cb_sla_h_n_zero_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#CB),
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#20),  %% SLA B
    Cpu3 = Cpu2#cpu_state{b = 16#40, f = ?FLAG_H bor ?FLAG_N},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(0, Cpu4#cpu_state.f band (?FLAG_H bor ?FLAG_N)).

%% CB BIT: verify N=0, H=1
cb_bit_h_n_flag_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#CB),
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#40),  %% BIT 0,B
    Cpu3 = Cpu2#cpu_state{b = 16#01, f = ?FLAG_N},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(?FLAG_H, Cpu4#cpu_state.f band ?FLAG_H),
    ?assertEqual(0, Cpu4#cpu_state.f band ?FLAG_N).
