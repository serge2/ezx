-module(z80_cpu_index_cb_tests).

-include("z80_records.hrl").
-include_lib("eunit/include/eunit.hrl").

%% ============================================================================
%% DD CB RLC (IX+d) - 0x06
%% ============================================================================
dd_cb_rlc_ix_zero_disp_test() ->
    %% RLC (IX+0): 0x80 -> 0x01, C=1, S=0, Z=0
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#80),  %% value at (IX+0)
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#DD),  %% DD prefix
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#CB),  %% CB prefix
    Cpu4 = test_helpers:write_mem(Cpu3, 2, 16#00),  %% displacement 0
    Cpu5 = test_helpers:write_mem(Cpu4, 3, 16#06),  %% RLC (IX+0)
    Cpu6 = Cpu5#cpu_state{ixh = 16#40, ixl = 16#00},
    Cpu7 = z80_cpu:step(Cpu6),
    ?assertEqual(16#01, test_helpers:read_mem(Cpu7, 16#4000)),
    ?assertEqual(?FLAG_C, Cpu7#cpu_state.f band ?FLAG_C),
    ?assertEqual(0, Cpu7#cpu_state.f band ?FLAG_Z),
    ?assertEqual(0, Cpu7#cpu_state.f band ?FLAG_S),
    ?assertEqual(none, Cpu7#cpu_state.prefix).

dd_cb_rlc_ix_pos_disp_test() ->
    %% RLC (IX+5): 0x40 -> 0x80, C=0, S=1, Z=0
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4005, 16#40),  %% value at (IX+5)
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#DD),  %% DD prefix
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#CB),  %% CB prefix
    Cpu4 = test_helpers:write_mem(Cpu3, 2, 16#05),  %% displacement +5
    Cpu5 = test_helpers:write_mem(Cpu4, 3, 16#06),  %% RLC (IX+5)
    Cpu6 = Cpu5#cpu_state{ixh = 16#40, ixl = 16#00},
    Cpu7 = z80_cpu:step(Cpu6),
    ?assertEqual(16#80, test_helpers:read_mem(Cpu7, 16#4005)),
    ?assertEqual(0, Cpu7#cpu_state.f band ?FLAG_C),
    ?assertEqual(?FLAG_S, Cpu7#cpu_state.f band ?FLAG_S),
    ?assertEqual(0, Cpu7#cpu_state.f band ?FLAG_Z).

dd_cb_rlc_ix_neg_disp_test() ->
    %% RLC (IX-1): 0x01 -> 0x02, C=0, S=0, Z=0
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#3FFF, 16#01),  %% value at (IX-1)
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#DD),  %% DD prefix
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#CB),  %% CB prefix
    Cpu4 = test_helpers:write_mem(Cpu3, 2, 16#FF),  %% displacement -1 (0xFF)
    Cpu5 = test_helpers:write_mem(Cpu4, 3, 16#06),  %% RLC (IX-1)
    Cpu6 = Cpu5#cpu_state{ixh = 16#40, ixl = 16#00},
    Cpu7 = z80_cpu:step(Cpu6),
    ?assertEqual(16#02, test_helpers:read_mem(Cpu7, 16#3FFF)),
    ?assertEqual(0, Cpu7#cpu_state.f band ?FLAG_C).

dd_cb_rlc_ix_zero_result_test() ->
    %% RLC (IX+0): 0x00 -> 0x00, C=0, Z=1
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#00),  %% value at (IX+0)
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#DD),  %% DD prefix
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#CB),  %% CB prefix
    Cpu4 = test_helpers:write_mem(Cpu3, 2, 16#00),  %% displacement 0
    Cpu5 = test_helpers:write_mem(Cpu4, 3, 16#06),  %% RLC (IX+0)
    Cpu6 = Cpu5#cpu_state{ixh = 16#40, ixl = 16#00},
    Cpu7 = z80_cpu:step(Cpu6),
    ?assertEqual(16#00, test_helpers:read_mem(Cpu7, 16#4000)),
    ?assertEqual(?FLAG_Z, Cpu7#cpu_state.f band ?FLAG_Z),
    ?assertEqual(0, Cpu7#cpu_state.f band ?FLAG_C).

%% ============================================================================
%% FD CB RLC (IY+d) - 0x06
%% ============================================================================
fd_cb_rlc_iy_test() ->
    %% RLC (IY+0): 0x80 -> 0x01, C=1
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#5000, 16#80),  %% value at (IY+0)
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#FD),  %% FD prefix
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#CB),  %% CB prefix
    Cpu4 = test_helpers:write_mem(Cpu3, 2, 16#00),  %% displacement 0
    Cpu5 = test_helpers:write_mem(Cpu4, 3, 16#06),  %% RLC (IY+0)
    Cpu6 = Cpu5#cpu_state{iyh = 16#50, iyl = 16#00},
    Cpu7 = z80_cpu:step(Cpu6),
    ?assertEqual(16#01, test_helpers:read_mem(Cpu7, 16#5000)),
    ?assertEqual(?FLAG_C, Cpu7#cpu_state.f band ?FLAG_C).

%% ============================================================================
%% DD CB RRC (IX+d) - 0x0E
%% ============================================================================
dd_cb_rrc_ix_test() ->
    %% RRC (IX+0): 0x01 -> 0x80, C=1, S=1
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#01),  %% value at (IX+0)
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#DD),  %% DD prefix
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#CB),  %% CB prefix
    Cpu4 = test_helpers:write_mem(Cpu3, 2, 16#00),  %% displacement 0
    Cpu5 = test_helpers:write_mem(Cpu4, 3, 16#0E),  %% RRC (IX+0)
    Cpu6 = Cpu5#cpu_state{ixh = 16#40, ixl = 16#00},
    Cpu7 = z80_cpu:step(Cpu6),
    ?assertEqual(16#80, test_helpers:read_mem(Cpu7, 16#4000)),
    ?assertEqual(?FLAG_C, Cpu7#cpu_state.f band ?FLAG_C),
    ?assertEqual(?FLAG_S, Cpu7#cpu_state.f band ?FLAG_S).

dd_cb_rrc_ix_zero_result_test() ->
    %% RRC (IX+0): 0x00 -> 0x00, C=0, Z=1
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#00),  %% value at (IX+0)
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#DD),  %% DD prefix
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#CB),  %% CB prefix
    Cpu4 = test_helpers:write_mem(Cpu3, 2, 16#00),  %% displacement 0
    Cpu5 = test_helpers:write_mem(Cpu4, 3, 16#0E),  %% RRC (IX+0)
    Cpu6 = Cpu5#cpu_state{ixh = 16#40, ixl = 16#00},
    Cpu7 = z80_cpu:step(Cpu6),
    ?assertEqual(16#00, test_helpers:read_mem(Cpu7, 16#4000)),
    ?assertEqual(?FLAG_Z, Cpu7#cpu_state.f band ?FLAG_Z).

%% ============================================================================
%% DD CB RL (IX+d) - 0x16
%% ============================================================================
dd_cb_rl_ix_test() ->
    %% RL (IX+0): 0x7F with C=0 -> 0xFE, C=0
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#7F),  %% value at (IX+0)
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#DD),  %% DD prefix
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#CB),  %% CB prefix
    Cpu4 = test_helpers:write_mem(Cpu3, 2, 16#00),  %% displacement 0
    Cpu5 = test_helpers:write_mem(Cpu4, 3, 16#16),  %% RL (IX+0)
    Cpu6 = Cpu5#cpu_state{ixh = 16#40, ixl = 16#00, f = 0},
    Cpu7 = z80_cpu:step(Cpu6),
    ?assertEqual(16#FE, test_helpers:read_mem(Cpu7, 16#4000)),
    ?assertEqual(0, Cpu7#cpu_state.f band ?FLAG_C).

dd_cb_rl_ix_with_carry_test() ->
    %% RL (IX+0): 0x7F with C=1 -> 0xFF, C=0
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#7F),  %% value at (IX+0)
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#DD),  %% DD prefix
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#CB),  %% CB prefix
    Cpu4 = test_helpers:write_mem(Cpu3, 2, 16#00),  %% displacement 0
    Cpu5 = test_helpers:write_mem(Cpu4, 3, 16#16),  %% RL (IX+0)
    Cpu6 = Cpu5#cpu_state{ixh = 16#40, ixl = 16#00, f = ?FLAG_C},
    Cpu7 = z80_cpu:step(Cpu6),
    ?assertEqual(16#FF, test_helpers:read_mem(Cpu7, 16#4000)),
    ?assertEqual(0, Cpu7#cpu_state.f band ?FLAG_C).

dd_cb_rl_ix_carry_out_test() ->
    %% RL (IX+0): 0x80 with C=1 -> 0x01, C=1 (bit 7 goes to carry, old carry goes to bit 0)
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#80),  %% value at (IX+0)
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#DD),  %% DD prefix
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#CB),  %% CB prefix
    Cpu4 = test_helpers:write_mem(Cpu3, 2, 16#00),  %% displacement 0
    Cpu5 = test_helpers:write_mem(Cpu4, 3, 16#16),  %% RL (IX+0)
    Cpu6 = Cpu5#cpu_state{ixh = 16#40, ixl = 16#00, f = ?FLAG_C},
    Cpu7 = z80_cpu:step(Cpu6),
    ?assertEqual(16#01, test_helpers:read_mem(Cpu7, 16#4000)),
    ?assertEqual(?FLAG_C, Cpu7#cpu_state.f band ?FLAG_C).

%% ============================================================================
%% DD CB RR (IX+d) - 0x1E
%% ============================================================================
dd_cb_rr_ix_test() ->
    %% RR (IX+0): 0x01 with C=0 -> 0x00, C=1, Z=1
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#01),  %% value at (IX+0)
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#DD),  %% DD prefix
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#CB),  %% CB prefix
    Cpu4 = test_helpers:write_mem(Cpu3, 2, 16#00),  %% displacement 0
    Cpu5 = test_helpers:write_mem(Cpu4, 3, 16#1E),  %% RR (IX+0)
    Cpu6 = Cpu5#cpu_state{ixh = 16#40, ixl = 16#00, f = 0},
    Cpu7 = z80_cpu:step(Cpu6),
    ?assertEqual(16#00, test_helpers:read_mem(Cpu7, 16#4000)),
    ?assertEqual(?FLAG_C, Cpu7#cpu_state.f band ?FLAG_C),
    ?assertEqual(?FLAG_Z, Cpu7#cpu_state.f band ?FLAG_Z).

dd_cb_rr_ix_with_carry_test() ->
    %% RR (IX+0): 0x00 with C=1 -> 0x80, C=0, S=1
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#00),  %% value at (IX+0)
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#DD),  %% DD prefix
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#CB),  %% CB prefix
    Cpu4 = test_helpers:write_mem(Cpu3, 2, 16#00),  %% displacement 0
    Cpu5 = test_helpers:write_mem(Cpu4, 3, 16#1E),  %% RR (IX+0)
    Cpu6 = Cpu5#cpu_state{ixh = 16#40, ixl = 16#00, f = ?FLAG_C},
    Cpu7 = z80_cpu:step(Cpu6),
    ?assertEqual(16#80, test_helpers:read_mem(Cpu7, 16#4000)),
    ?assertEqual(?FLAG_S, Cpu7#cpu_state.f band ?FLAG_S).

%% ============================================================================
%% DD CB SLA (IX+d) - 0x26
%% ============================================================================
dd_cb_sla_ix_test() ->
    %% SLA (IX+0): 0x40 -> 0x80, C=0, S=1
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#40),  %% value at (IX+0)
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#DD),  %% DD prefix
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#CB),  %% CB prefix
    Cpu4 = test_helpers:write_mem(Cpu3, 2, 16#00),  %% displacement 0
    Cpu5 = test_helpers:write_mem(Cpu4, 3, 16#26),  %% SLA (IX+0)
    Cpu6 = Cpu5#cpu_state{ixh = 16#40, ixl = 16#00},
    Cpu7 = z80_cpu:step(Cpu6),
    ?assertEqual(16#80, test_helpers:read_mem(Cpu7, 16#4000)),
    ?assertEqual(?FLAG_S, Cpu7#cpu_state.f band ?FLAG_S).

dd_cb_sla_ix_carry_test() ->
    %% SLA (IX+0): 0x80 -> 0x00, C=1, Z=1
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#80),  %% value at (IX+0)
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#DD),  %% DD prefix
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#CB),  %% CB prefix
    Cpu4 = test_helpers:write_mem(Cpu3, 2, 16#00),  %% displacement 0
    Cpu5 = test_helpers:write_mem(Cpu4, 3, 16#26),  %% SLA (IX+0)
    Cpu6 = Cpu5#cpu_state{ixh = 16#40, ixl = 16#00},
    Cpu7 = z80_cpu:step(Cpu6),
    ?assertEqual(16#00, test_helpers:read_mem(Cpu7, 16#4000)),
    ?assertEqual(?FLAG_C, Cpu7#cpu_state.f band ?FLAG_C),
    ?assertEqual(?FLAG_Z, Cpu7#cpu_state.f band ?FLAG_Z).

%% ============================================================================
%% DD CB SRA (IX+d) - 0x2E
%% ============================================================================
dd_cb_sra_ix_test() ->
    %% SRA (IX+0): 0x80 -> 0xC0, C=0, S=1 (arithmetic shift preserves sign)
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#80),  %% value at (IX+0)
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#DD),  %% DD prefix
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#CB),  %% CB prefix
    Cpu4 = test_helpers:write_mem(Cpu3, 2, 16#00),  %% displacement 0
    Cpu5 = test_helpers:write_mem(Cpu4, 3, 16#2E),  %% SRA (IX+0)
    Cpu6 = Cpu5#cpu_state{ixh = 16#40, ixl = 16#00},
    Cpu7 = z80_cpu:step(Cpu6),
    ?assertEqual(16#C0, test_helpers:read_mem(Cpu7, 16#4000)),
    ?assertEqual(?FLAG_S, Cpu7#cpu_state.f band ?FLAG_S).

dd_cb_sra_ix_positive_test() ->
    %% SRA (IX+0): 0x40 -> 0x20, C=0, S=0
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#40),
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#DD),  %% DD prefix
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#CB),  %% CB prefix
    Cpu4 = test_helpers:write_mem(Cpu3, 2, 16#00),  %% displacement 0
    Cpu5 = test_helpers:write_mem(Cpu4, 3, 16#2E),  %% SRA (IX+0)
    Cpu6 = Cpu5#cpu_state{ixh = 16#40, ixl = 16#00},
    Cpu7 = z80_cpu:step(Cpu6),
    ?assertEqual(16#20, test_helpers:read_mem(Cpu7, 16#4000)),
    ?assertEqual(0, Cpu7#cpu_state.f band ?FLAG_S).

dd_cb_sra_ix_carry_test() ->
    %% SRA (IX+0): 0x01 -> 0x00, C=1, Z=1
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#01),
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#DD),  %% DD prefix
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#CB),  %% CB prefix
    Cpu4 = test_helpers:write_mem(Cpu3, 2, 16#00),  %% displacement 0
    Cpu5 = test_helpers:write_mem(Cpu4, 3, 16#2E),  %% SRA (IX+0)
    Cpu6 = Cpu5#cpu_state{ixh = 16#40, ixl = 16#00},
    Cpu7 = z80_cpu:step(Cpu6),
    ?assertEqual(16#00, test_helpers:read_mem(Cpu7, 16#4000)),
    ?assertEqual(?FLAG_C, Cpu7#cpu_state.f band ?FLAG_C),
    ?assertEqual(?FLAG_Z, Cpu7#cpu_state.f band ?FLAG_Z).

%% ============================================================================
%% DD CB SLL (IX+d) - 0x36 (undocumented)
%% ============================================================================
dd_cb_sll_ix_test() ->
    %% SLL (IX+0): 0x40 -> 0x81, C=0, S=1
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#40),
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#DD),  %% DD prefix
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#CB),  %% CB prefix
    Cpu4 = test_helpers:write_mem(Cpu3, 2, 16#00),  %% displacement 0
    Cpu5 = test_helpers:write_mem(Cpu4, 3, 16#36),  %% SLL (IX+0)
    Cpu6 = Cpu5#cpu_state{ixh = 16#40, ixl = 16#00},
    Cpu7 = z80_cpu:step(Cpu6),
    ?assertEqual(16#81, test_helpers:read_mem(Cpu7, 16#4000)),
    ?assertEqual(?FLAG_S, Cpu7#cpu_state.f band ?FLAG_S).

dd_cb_sll_ix_carry_test() ->
    %% SLL (IX+0): 0x80 -> 0x01, C=1
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#80),
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#DD),  %% DD prefix
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#CB),  %% CB prefix
    Cpu4 = test_helpers:write_mem(Cpu3, 2, 16#00),  %% displacement 0
    Cpu5 = test_helpers:write_mem(Cpu4, 3, 16#36),  %% SLL (IX+0)
    Cpu6 = Cpu5#cpu_state{ixh = 16#40, ixl = 16#00},
    Cpu7 = z80_cpu:step(Cpu6),
    ?assertEqual(16#01, test_helpers:read_mem(Cpu7, 16#4000)),
    ?assertEqual(?FLAG_C, Cpu7#cpu_state.f band ?FLAG_C).

%% ============================================================================
%% DD CB SRL (IX+d) - 0x3E
%% ============================================================================
dd_cb_srl_ix_test() ->
    %% SRL (IX+0): 0x80 -> 0x40, C=0, S=0
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#80),
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#DD),  %% DD prefix
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#CB),  %% CB prefix
    Cpu4 = test_helpers:write_mem(Cpu3, 2, 16#00),  %% displacement 0
    Cpu5 = test_helpers:write_mem(Cpu4, 3, 16#3E),  %% SRL (IX+0)
    Cpu6 = Cpu5#cpu_state{ixh = 16#40, ixl = 16#00},
    Cpu7 = z80_cpu:step(Cpu6),
    ?assertEqual(16#40, test_helpers:read_mem(Cpu7, 16#4000)),
    ?assertEqual(0, Cpu7#cpu_state.f band ?FLAG_S).

dd_cb_srl_ix_carry_test() ->
    %% SRL (IX+0): 0x01 -> 0x00, C=1, Z=1
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#01),
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#DD),  %% DD prefix
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#CB),  %% CB prefix
    Cpu4 = test_helpers:write_mem(Cpu3, 2, 16#00),  %% displacement 0
    Cpu5 = test_helpers:write_mem(Cpu4, 3, 16#3E),  %% SRL (IX+0)
    Cpu6 = Cpu5#cpu_state{ixh = 16#40, ixl = 16#00},
    Cpu7 = z80_cpu:step(Cpu6),
    ?assertEqual(16#00, test_helpers:read_mem(Cpu7, 16#4000)),
    ?assertEqual(?FLAG_C, Cpu7#cpu_state.f band ?FLAG_C),
    ?assertEqual(?FLAG_Z, Cpu7#cpu_state.f band ?FLAG_Z).

%% ============================================================================
%% DD CB BIT (IX+d) - 0x46-0x7E
%% ============================================================================
dd_cb_bit_0_ix_test() ->
    %% BIT 0,(IX+0): value=0x01 -> bit 0=1, Z=0, S=1, H=1, P/V=0
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#01),
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#DD),  %% DD prefix
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#CB),  %% CB prefix
    Cpu4 = test_helpers:write_mem(Cpu3, 2, 16#00),  %% displacement 0
    Cpu5 = test_helpers:write_mem(Cpu4, 3, 16#46),  %% BIT 0,(IX+0)
    Cpu6 = Cpu5#cpu_state{ixh = 16#40, ixl = 16#00},
    Cpu7 = z80_cpu:step(Cpu6),
    ?assertEqual(16#01, test_helpers:read_mem(Cpu7, 16#4000)),
    ?assertEqual(0, Cpu7#cpu_state.f band ?FLAG_Z),
    ?assertEqual(0, Cpu7#cpu_state.f band ?FLAG_S),
    ?assertEqual(?FLAG_H, Cpu7#cpu_state.f band ?FLAG_H),
    ?assertEqual(0, Cpu7#cpu_state.f band ?FLAG_V).

dd_cb_bit_7_ix_test() ->
    %% BIT 7,(IX+0): value=0x80 -> bit 7=1, Z=0, S=1
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#80),
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#DD),  %% DD prefix
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#CB),  %% CB prefix
    Cpu4 = test_helpers:write_mem(Cpu3, 2, 16#00),  %% displacement 0
    Cpu5 = test_helpers:write_mem(Cpu4, 3, 16#7E),  %% BIT 7,(IX+0)
    Cpu6 = Cpu5#cpu_state{ixh = 16#40, ixl = 16#00},
    Cpu7 = z80_cpu:step(Cpu6),
    ?assertEqual(0, Cpu7#cpu_state.f band ?FLAG_Z),
    ?assertEqual(?FLAG_S, Cpu7#cpu_state.f band ?FLAG_S).

dd_cb_bit_7_ix_zero_test() ->
    %% BIT 7,(IX+0): value=0x7F -> bit 7=0, Z=1, S=0, P/V=1
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#7F),
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#DD),  %% DD prefix
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#CB),  %% CB prefix
    Cpu4 = test_helpers:write_mem(Cpu3, 2, 16#00),  %% displacement 0
    Cpu5 = test_helpers:write_mem(Cpu4, 3, 16#7E),  %% BIT 7,(IX+0)
    Cpu6 = Cpu5#cpu_state{ixh = 16#40, ixl = 16#00},
    Cpu7 = z80_cpu:step(Cpu6),
    ?assertEqual(?FLAG_Z, Cpu7#cpu_state.f band ?FLAG_Z),
    ?assertEqual(0, Cpu7#cpu_state.f band ?FLAG_S),
    ?assertEqual(?FLAG_V, Cpu7#cpu_state.f band ?FLAG_V).

dd_cb_bit_3_ix_test() ->
    %% BIT 3,(IX+2): value=0x08 -> bit 3=1
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4002, 16#08),
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#DD),  %% DD prefix
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#CB),  %% CB prefix
    Cpu4 = test_helpers:write_mem(Cpu3, 2, 16#02),  %% displacement +2
    Cpu5 = test_helpers:write_mem(Cpu4, 3, 16#5E),  %% BIT 3,(IX+2)
    Cpu6 = Cpu5#cpu_state{ixh = 16#40, ixl = 16#00},
    Cpu7 = z80_cpu:step(Cpu6),
    ?assertEqual(0, Cpu7#cpu_state.f band ?FLAG_Z).

fd_cb_bit_iy_test() ->
    %% BIT 5,(IY+3): value=0x20 -> bit 5=1
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#5003, 16#20),
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#FD),  %% FD prefix
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#CB),  %% CB prefix
    Cpu4 = test_helpers:write_mem(Cpu3, 2, 16#03),  %% displacement +3
    Cpu5 = test_helpers:write_mem(Cpu4, 3, 16#6E),  %% BIT 5,(IY+3)
    Cpu6 = Cpu5#cpu_state{iyh = 16#50, iyl = 16#00},
    Cpu7 = z80_cpu:step(Cpu6),
    ?assertEqual(0, Cpu7#cpu_state.f band ?FLAG_Z).

%% ============================================================================
%% DD CB RES (IX+d) - 0x86-0xBE
%% ============================================================================
dd_cb_res_0_ix_test() ->
    %% RES 0,(IX+0): 0xFF -> 0xFE
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#FF),
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#DD),  %% DD prefix
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#CB),  %% CB prefix
    Cpu4 = test_helpers:write_mem(Cpu3, 2, 16#00),  %% displacement 0
    Cpu5 = test_helpers:write_mem(Cpu4, 3, 16#86),  %% RES 0,(IX+0)
    Cpu6 = Cpu5#cpu_state{ixh = 16#40, ixl = 16#00},
    Cpu7 = z80_cpu:step(Cpu6),
    ?assertEqual(16#FE, test_helpers:read_mem(Cpu7, 16#4000)).

dd_cb_res_7_ix_test() ->
    %% RES 7,(IX+0): 0xFF -> 0x7F
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#FF),
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#DD),  %% DD prefix
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#CB),  %% CB prefix
    Cpu4 = test_helpers:write_mem(Cpu3, 2, 16#00),  %% displacement 0
    Cpu5 = test_helpers:write_mem(Cpu4, 3, 16#BE),  %% RES 7,(IX+0)
    Cpu6 = Cpu5#cpu_state{ixh = 16#40, ixl = 16#00},
    Cpu7 = z80_cpu:step(Cpu6),
    ?assertEqual(16#7F, test_helpers:read_mem(Cpu7, 16#4000)).

dd_cb_res_3_ix_test() ->
    %% RES 3,(IX+5): 0xFF -> 0xF7
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4005, 16#FF),
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#DD),  %% DD prefix
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#CB),  %% CB prefix
    Cpu4 = test_helpers:write_mem(Cpu3, 2, 16#05),  %% displacement +5
    Cpu5 = test_helpers:write_mem(Cpu4, 3, 16#9E),  %% RES 3,(IX+5)
    Cpu6 = Cpu5#cpu_state{ixh = 16#40, ixl = 16#00},
    Cpu7 = z80_cpu:step(Cpu6),
    ?assertEqual(16#F7, test_helpers:read_mem(Cpu7, 16#4005)).

fd_cb_res_iy_test() ->
    %% RES 2,(IY-2): 0xFF -> 0xFB
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4FFE, 16#FF),
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#FD),  %% FD prefix
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#CB),  %% CB prefix
    Cpu4 = test_helpers:write_mem(Cpu3, 2, 16#FE),  %% displacement -2 (0xFE)
    Cpu5 = test_helpers:write_mem(Cpu4, 3, 16#96),  %% RES 2,(IY-2)
    Cpu6 = Cpu5#cpu_state{iyh = 16#50, iyl = 16#00},
    Cpu7 = z80_cpu:step(Cpu6),
    ?assertEqual(16#FB, test_helpers:read_mem(Cpu7, 16#4FFE)).

%% ============================================================================
%% DD CB SET (IX+d) - 0xC6-0xFE
%% ============================================================================
dd_cb_set_0_ix_test() ->
    %% SET 0,(IX+0): 0xFE -> 0xFF
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#FE),
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#DD),  %% DD prefix
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#CB),  %% CB prefix
    Cpu4 = test_helpers:write_mem(Cpu3, 2, 16#00),  %% displacement 0
    Cpu5 = test_helpers:write_mem(Cpu4, 3, 16#C6),  %% SET 0,(IX+0)
    Cpu6 = Cpu5#cpu_state{ixh = 16#40, ixl = 16#00},
    Cpu7 = z80_cpu:step(Cpu6),
    ?assertEqual(16#FF, test_helpers:read_mem(Cpu7, 16#4000)).

dd_cb_set_7_ix_test() ->
    %% SET 7,(IX+0): 0x7F -> 0xFF
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#7F),
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#DD),  %% DD prefix
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#CB),  %% CB prefix
    Cpu4 = test_helpers:write_mem(Cpu3, 2, 16#00),  %% displacement 0
    Cpu5 = test_helpers:write_mem(Cpu4, 3, 16#FE),  %% SET 7,(IX+0)
    Cpu6 = Cpu5#cpu_state{ixh = 16#40, ixl = 16#00},
    Cpu7 = z80_cpu:step(Cpu6),
    ?assertEqual(16#FF, test_helpers:read_mem(Cpu7, 16#4000)).

dd_cb_set_2_ix_test() ->
    %% SET 2,(IX+3): 0xF3 -> 0xF7 (0xD6 = SET 2, reg=6)
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4003, 16#F3),
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#DD),  %% DD prefix
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#CB),  %% CB prefix
    Cpu4 = test_helpers:write_mem(Cpu3, 2, 16#03),  %% displacement +3
    Cpu5 = test_helpers:write_mem(Cpu4, 3, 16#D6),  %% SET 2,(IX+3)
    Cpu6 = Cpu5#cpu_state{ixh = 16#40, ixl = 16#00},
    Cpu7 = z80_cpu:step(Cpu6),
    ?assertEqual(16#F7, test_helpers:read_mem(Cpu7, 16#4003)).

fd_cb_set_iy_test() ->
    %% SET 4,(IY+1): 0xEF -> 0xFF (0xE6 = SET 4, reg=6)
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#5001, 16#EF),
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#FD),  %% FD prefix
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#CB),  %% CB prefix
    Cpu4 = test_helpers:write_mem(Cpu3, 2, 16#01),  %% displacement +1
    Cpu5 = test_helpers:write_mem(Cpu4, 3, 16#E6),  %% SET 4,(IY+1)
    Cpu6 = Cpu5#cpu_state{iyh = 16#50, iyl = 16#00},
    Cpu7 = z80_cpu:step(Cpu6),
    ?assertEqual(16#FF, test_helpers:read_mem(Cpu7, 16#5001)).

%% ============================================================================
%% Prefix state verification
%% ============================================================================
dd_prefix_state_during_cb_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#00),
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#DD),  %% DD prefix
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#CB),  %% CB prefix
    Cpu4 = test_helpers:write_mem(Cpu3, 2, 16#00),  %% displacement 0
    Cpu5 = test_helpers:write_mem(Cpu4, 3, 16#06),  %% RLC (IX+0)
    Cpu6 = Cpu5#cpu_state{ixh = 16#40, ixl = 16#00},
    Cpu7 = z80_cpu:step(Cpu6),
    ?assertEqual(none, Cpu7#cpu_state.prefix).

fd_prefix_state_during_cb_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#5000, 16#00),
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#FD),  %% FD prefix
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#CB),  %% CB prefix
    Cpu4 = test_helpers:write_mem(Cpu3, 2, 16#00),  %% displacement 0
    Cpu5 = test_helpers:write_mem(Cpu4, 3, 16#06),  %% RLC (IY+0)
    Cpu6 = Cpu5#cpu_state{iyh = 16#50, iyl = 16#00},
    Cpu7 = z80_cpu:step(Cpu6),
    ?assertEqual(none, Cpu7#cpu_state.prefix).

%% ============================================================================
%% T-states verification
%% ============================================================================
dd_cb_tstates_test() ->
    %% DD CB takes 23 T-states total
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#00),
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#DD),  %% DD prefix
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#CB),  %% CB prefix
    Cpu4 = test_helpers:write_mem(Cpu3, 2, 16#00),  %% displacement 0
    Cpu5 = test_helpers:write_mem(Cpu4, 3, 16#06),  %% RLC (IX+0)
    Cpu6 = Cpu5#cpu_state{ixh = 16#40, ixl = 16#00},
    Cpu7 = z80_cpu:step(Cpu6),
    ?assertEqual(23, z80_cpu:t_states(Cpu7)).

fd_cb_tstates_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#5000, 16#00),
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#FD),  %% FD prefix
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#CB),  %% CB prefix
    Cpu4 = test_helpers:write_mem(Cpu3, 2, 16#00),  %% displacement 0
    Cpu5 = test_helpers:write_mem(Cpu4, 3, 16#06),  %% RLC (IY+0)
    Cpu6 = Cpu5#cpu_state{iyh = 16#50, iyl = 16#00},
    Cpu7 = z80_cpu:step(Cpu6),
    ?assertEqual(23, z80_cpu:t_states(Cpu7)).

%% ============================================================================
%% Memory write-back verification
%% ============================================================================
dd_cb_memory_writeback_test() ->
    %% Verify result is written back to memory
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#01),
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#DD),  %% DD prefix
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#CB),  %% CB prefix
    Cpu4 = test_helpers:write_mem(Cpu3, 2, 16#00),  %% displacement 0
    Cpu5 = test_helpers:write_mem(Cpu4, 3, 16#06),  %% RLC (IX+0)
    Cpu6 = Cpu5#cpu_state{ixh = 16#40, ixl = 16#00},
    Cpu7 = z80_cpu:step(Cpu6),
    ?assertEqual(16#02, test_helpers:read_mem(Cpu7, 16#4000)).

dd_cb_bit_no_memory_write_test() ->
    %% BIT does not modify memory
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#55),
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#DD),  %% DD prefix
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#CB),  %% CB prefix
    Cpu4 = test_helpers:write_mem(Cpu3, 2, 16#00),  %% displacement 0
    Cpu5 = test_helpers:write_mem(Cpu4, 3, 16#5E),  %% BIT 3,(IX+0)
    Cpu6 = Cpu5#cpu_state{ixh = 16#40, ixl = 16#00},
    Cpu7 = z80_cpu:step(Cpu6),
    ?assertEqual(16#55, test_helpers:read_mem(Cpu7, 16#4000)).

%% ============================================================================
%% DD CB register operands (RegField 0-5, 7 = B,C,D,E,H,L,A)
%% These operate on CPU registers, NOT memory at (IX+d)
%% ============================================================================

dd_cb_rlc_b_reg_test() ->
    %% DD CB 00 = RLC B (RegField=0): read (IX+0), RLC, write back, copy to B
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#81),  %% value at (IX+0)
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#DD),  %% DD prefix
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#CB),  %% CB prefix
    Cpu4 = test_helpers:write_mem(Cpu3, 2, 16#00),  %% displacement 0
    Cpu5 = test_helpers:write_mem(Cpu4, 3, 16#00),  %% RLC (IX+0) -> copy to B
    Cpu6 = Cpu5#cpu_state{b = 16#00, ixh = 16#40, ixl = 16#00, f = 0},
    Cpu7 = z80_cpu:step(Cpu6),
    ?assertEqual(16#03, Cpu7#cpu_state.b),   %% 10000001 RLC = 00000011
    ?assertEqual(?FLAG_C, Cpu7#cpu_state.f band ?FLAG_C),
    ?assertEqual(16#03, test_helpers:read_mem(Cpu7, 16#4000)).  %% memory also updated

dd_cb_rlc_c_reg_test() ->
    %% DD CB 01 = RLC C (RegField=1): read (IX+0), RLC, write back, copy to C
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#40),  %% value at (IX+0)
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#DD),  %% DD prefix
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#CB),  %% CB prefix
    Cpu4 = test_helpers:write_mem(Cpu3, 2, 16#00),  %% displacement 0
    Cpu5 = test_helpers:write_mem(Cpu4, 3, 16#01),  %% RLC (IX+0) -> copy to C
    Cpu6 = Cpu5#cpu_state{c = 16#00, ixh = 16#40, ixl = 16#00, f = 0},
    Cpu7 = z80_cpu:step(Cpu6),
    ?assertEqual(16#80, Cpu7#cpu_state.c),
    ?assertEqual(0, Cpu7#cpu_state.f band ?FLAG_C),
    ?assertEqual(?FLAG_S, Cpu7#cpu_state.f band ?FLAG_S),
    ?assertEqual(16#80, test_helpers:read_mem(Cpu7, 16#4000)).

dd_cb_rlc_a_reg_test() ->
    %% DD CB 07 = RLC A (RegField=7): read (IX+0), RLC, write back, copy to A
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#FF),  %% value at (IX+0)
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#DD),  %% DD prefix
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#CB),  %% CB prefix
    Cpu4 = test_helpers:write_mem(Cpu3, 2, 16#00),  %% displacement 0
    Cpu5 = test_helpers:write_mem(Cpu4, 3, 16#07),  %% RLC (IX+0) -> copy to A
    Cpu6 = Cpu5#cpu_state{a = 16#00, ixh = 16#40, ixl = 16#00, f = 0},
    Cpu7 = z80_cpu:step(Cpu6),
    ?assertEqual(16#FF, Cpu7#cpu_state.a),
    ?assertEqual(?FLAG_C, Cpu7#cpu_state.f band ?FLAG_C),
    ?assertEqual(16#FF, test_helpers:read_mem(Cpu7, 16#4000)).

dd_cb_bit_0_b_reg_test() ->
    %% DD CB 40 = BIT 0,B (RegField=0): read (IX+0), BIT 0, flags set, B UNCHANGED (BIT doesn't copy to reg)
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#01),  %% value at (IX+0), bit 0 = 1
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#DD),  %% DD prefix
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#CB),  %% CB prefix
    Cpu4 = test_helpers:write_mem(Cpu3, 2, 16#00),  %% displacement 0
    Cpu5 = test_helpers:write_mem(Cpu4, 3, 16#40),  %% BIT 0,(IX+0) - no register copy
    Cpu6 = Cpu5#cpu_state{b = 16#00, ixh = 16#40, ixl = 16#00, f = 0},
    Cpu7 = z80_cpu:step(Cpu6),
    ?assertEqual(0, Cpu7#cpu_state.f band ?FLAG_Z),   %% Z=0 (bit was 1)
    ?assertEqual(0, Cpu7#cpu_state.f band ?FLAG_S), %% S=0 (only BIT 7 sets S)
    ?assertEqual(?FLAG_H, Cpu7#cpu_state.f band ?FLAG_H), %% H=1
    ?assertEqual(16#00, Cpu7#cpu_state.b).  %% B unchanged

dd_cb_bit_7_a_reg_test() ->
    %% DD CB 7F = BIT 7,A (RegField=7): read (IX+0), BIT 7, flags set, A UNCHANGED
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#80),  %% value at (IX+0), bit 7 = 1
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#DD),  %% DD prefix
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#CB),  %% CB prefix
    Cpu4 = test_helpers:write_mem(Cpu3, 2, 16#00),  %% displacement 0
    Cpu5 = test_helpers:write_mem(Cpu4, 3, 16#7F),  %% BIT 7,(IX+0) - no register copy
    Cpu6 = Cpu5#cpu_state{a = 16#00, ixh = 16#40, ixl = 16#00, f = 0},
    Cpu7 = z80_cpu:step(Cpu6),
    ?assertEqual(0, Cpu7#cpu_state.f band ?FLAG_Z),
    ?assertEqual(?FLAG_S, Cpu7#cpu_state.f band ?FLAG_S),
    ?assertEqual(16#00, Cpu7#cpu_state.a).  %% A unchanged

dd_cb_res_3_d_reg_test() ->
    %% DD CB 9A = RES 3,D (RegField=2): read (IX+0), RES 3, write back, copy to D
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#FF),  %% value at (IX+0)
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#DD),  %% DD prefix
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#CB),  %% CB prefix
    Cpu4 = test_helpers:write_mem(Cpu3, 2, 16#00),  %% displacement 0
    Cpu5 = test_helpers:write_mem(Cpu4, 3, 16#9A),  %% RES 3,(IX+0) -> copy to D
    Cpu6 = Cpu5#cpu_state{d = 16#00, ixh = 16#40, ixl = 16#00},
    Cpu7 = z80_cpu:step(Cpu6),
    ?assertEqual(16#F7, Cpu7#cpu_state.d),  %% 11111111 -> 11110111
    ?assertEqual(16#F7, test_helpers:read_mem(Cpu7, 16#4000)).

dd_cb_set_5_e_reg_test() ->
    %% DD CB EB = SET 5,E (RegField=3): read (IX+0), SET 5, write back, copy to E
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#00),  %% value at (IX+0)
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#DD),  %% DD prefix
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#CB),  %% CB prefix
    Cpu4 = test_helpers:write_mem(Cpu3, 2, 16#00),  %% displacement 0
    Cpu5 = test_helpers:write_mem(Cpu4, 3, 16#EB),  %% SET 5,(IX+0) -> copy to E
    Cpu6 = Cpu5#cpu_state{e = 16#00, ixh = 16#40, ixl = 16#00},
    Cpu7 = z80_cpu:step(Cpu6),
    ?assertEqual(16#20, Cpu7#cpu_state.e),  %% 00000000 -> 00100000
    ?assertEqual(16#20, test_helpers:read_mem(Cpu7, 16#4000)).

dd_cb_rl_h_reg_test() ->
    %% DD CB 14 = RL H (RegField=4): read (IX+0), RL, write back, copy to H
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#7F),  %% value at (IX+0)
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#DD),  %% DD prefix
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#CB),  %% CB prefix
    Cpu4 = test_helpers:write_mem(Cpu3, 2, 16#00),  %% displacement 0
    Cpu5 = test_helpers:write_mem(Cpu4, 3, 16#14),  %% RL (IX+0) -> copy to H
    Cpu6 = Cpu5#cpu_state{h = 16#00, ixh = 16#40, ixl = 16#00, f = ?FLAG_C},
    Cpu7 = z80_cpu:step(Cpu6),
    ?assertEqual(16#FF, Cpu7#cpu_state.h),  %% 01111111 RL with carry=1 = 11111111
    ?assertEqual(0, Cpu7#cpu_state.f band ?FLAG_C),
    ?assertEqual(16#FF, test_helpers:read_mem(Cpu7, 16#4000)).

fd_cb_sla_l_reg_test() ->
    %% FD CB 25 = SLA L (RegField=5): read (IY+0), SLA, write back, copy to L
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#5000, 16#40),  %% value at (IY+0)
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#FD),  %% FD prefix
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#CB),  %% CB prefix
    Cpu4 = test_helpers:write_mem(Cpu3, 2, 16#00),  %% displacement 0
    Cpu5 = test_helpers:write_mem(Cpu4, 3, 16#25),  %% SLA (IY+0) -> copy to L
    Cpu6 = Cpu5#cpu_state{l = 16#00, iyh = 16#50, iyl = 16#00, f = 0},
    Cpu7 = z80_cpu:step(Cpu6),
    ?assertEqual(16#80, Cpu7#cpu_state.l),
    ?assertEqual(?FLAG_S, Cpu7#cpu_state.f band ?FLAG_S),
    ?assertEqual(16#80, test_helpers:read_mem(Cpu7, 16#5000)).

dd_cb_register_ops_read_write_memory_test() ->
    %% Register operands (z!=6): read from (IX+d), apply op, write back to (IX+d), copy to register
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#81),  %% value at (IX+0) = 0x81 (10000001)
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#DD),  %% DD prefix
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#CB),  %% CB prefix
    Cpu4 = test_helpers:write_mem(Cpu3, 2, 16#00),  %% displacement 0
    Cpu5 = test_helpers:write_mem(Cpu4, 3, 16#00),  %% RLC (IX+0) -> copy to B
    Cpu6 = Cpu5#cpu_state{b = 16#00, ixh = 16#40, ixl = 16#00, f = 0},
    Cpu7 = z80_cpu:step(Cpu6),
    %% Memory at (IX+0) should be updated (RLC 0x81 = 0x03, carry=1)
    ?assertEqual(16#03, test_helpers:read_mem(Cpu7, 16#4000)),
    %% B register should get the result
    ?assertEqual(16#03, Cpu7#cpu_state.b),
    ?assertEqual(?FLAG_C, Cpu7#cpu_state.f band ?FLAG_C).

%% ============================================================================
%% BIT b,(IX+d) F3/F5 tests - F3/F5 from address high byte (IXH/IYH)
%% ============================================================================

dd_cb_bit_3_ix_f3f5_test() ->
    %% BIT 3,(IX+0): F3/F5 from address high byte
    %% IX = 0x2800, Addr = 0x2800, AddrHi = 0x28 (bit3=1, bit5=0)
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#2800, 16#FF),
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#DD),
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#CB),
    Cpu4 = test_helpers:write_mem(Cpu3, 2, 16#00),
    Cpu5 = test_helpers:write_mem(Cpu4, 3, 16#5E),  %% BIT 3,(IX+0)
    Cpu6 = Cpu5#cpu_state{ixh = 16#28, ixl = 16#00},
    Cpu7 = z80_cpu:step(Cpu6),
    ?assertEqual(16#28, Cpu7#cpu_state.f band 16#28).

dd_cb_bit_5_ix_f3f5_test() ->
    %% BIT 5,(IX+0): F3/F5 from address high byte
    %% IX = 0x0028, Addr = 0x0028, AddrHi = 0x00 (no F3/F5)
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#0028, 16#20),
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#DD),
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#CB),
    Cpu4 = test_helpers:write_mem(Cpu3, 2, 16#00),
    Cpu5 = test_helpers:write_mem(Cpu4, 3, 16#6E),  %% BIT 5,(IX+0)
    Cpu6 = Cpu5#cpu_state{ixh = 16#00, ixl = 16#28},
    Cpu7 = z80_cpu:step(Cpu6),
    ?assertEqual(0, Cpu7#cpu_state.f band 16#28).

dd_cb_bit_7_ix_f3f5_test() ->
    %% BIT 7,(IX+0): S=1, F3/F5 from address high byte
    %% IX = 0x2A00, Addr = 0x2A00, AddrHi = 0x2A (bit3=1, bit5=1)
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#2A00, 16#80),
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#DD),
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#CB),
    Cpu4 = test_helpers:write_mem(Cpu3, 2, 16#00),
    Cpu5 = test_helpers:write_mem(Cpu4, 3, 16#7E),  %% BIT 7,(IX+0)
    Cpu6 = Cpu5#cpu_state{ixh = 16#2A, ixl = 16#00},
    Cpu7 = z80_cpu:step(Cpu6),
    ?assertEqual(?FLAG_S, Cpu7#cpu_state.f band ?FLAG_S),
    ?assertEqual(16#28, Cpu7#cpu_state.f band 16#28).

fd_cb_bit_5_iy_f3f5_test() ->
    %% BIT 5,(IY+0): F3/F5 from IYH
    %% IY = 0x5028, AddrHi = 0x50 (bit3=0, bit5=0)
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#5028, 16#20),
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#FD),
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#CB),
    Cpu4 = test_helpers:write_mem(Cpu3, 2, 16#00),
    Cpu5 = test_helpers:write_mem(Cpu4, 3, 16#6E),  %% BIT 5,(IY+0)
    Cpu6 = Cpu5#cpu_state{iyh = 16#50, iyl = 16#28},
    Cpu7 = z80_cpu:step(Cpu6),
    ?assertEqual(16#00, Cpu7#cpu_state.f band 16#28).

dd_cb_bit_ix_zero_f3f5_test() ->
    %% BIT 0,(IX+0): Z=1, F3/F5 from address high byte
    %% IX = 0x2800, AddrHi = 0x28 (bit3=1, bit5=1)
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#2800, 16#00),
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#DD),
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#CB),
    Cpu4 = test_helpers:write_mem(Cpu3, 2, 16#00),
    Cpu5 = test_helpers:write_mem(Cpu4, 3, 16#46),  %% BIT 0,(IX+0)
    Cpu6 = Cpu5#cpu_state{ixh = 16#28, ixl = 16#00},
    Cpu7 = z80_cpu:step(Cpu6),
    ?assertEqual(?FLAG_Z, Cpu7#cpu_state.f band ?FLAG_Z),
    ?assertEqual(0, Cpu7#cpu_state.f band ?FLAG_S),
    ?assertEqual(16#28, Cpu7#cpu_state.f band 16#28).
