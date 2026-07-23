-module(z80_cpu_ed_tests).

-include("z80_records.hrl").
-include_lib("eunit/include/eunit.hrl").

%% --- ED Prefix Tests ---

ed_rrd_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#34),
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#ED),  %% ED prefix
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#67),  %% RRD
    Cpu4 = Cpu3#cpu_state{a = 16#00, h = 16#40, l = 16#00},
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(16#04, Cpu5#cpu_state.a),
    ?assertEqual(16#03, test_helpers:read_mem(Cpu5, 16#4000)),
    ?assertEqual(18, z80_cpu:t_states(Cpu5)).

ed_rld_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#34),
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#ED),  %% ED prefix
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#6F),  %% RLD
    Cpu4 = Cpu3#cpu_state{a = 16#00, h = 16#40, l = 16#00},
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(16#03, Cpu5#cpu_state.a),
    ?assertEqual(16#40, test_helpers:read_mem(Cpu5, 16#4000)),
    ?assertEqual(18, z80_cpu:t_states(Cpu5)).

%% --- ED LD A,I / LD A,R / LD I,A / LD R,A ---

ed_ld_i_a_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#ED),  %% ED prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#47),  %% LD I,A
    Cpu3 = Cpu2#cpu_state{a = 16#42},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#42, Cpu4#cpu_state.i),
    ?assertEqual(9, z80_cpu:t_states(Cpu4)).

ed_ld_a_i_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#ED),  %% ED prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#57),  %% LD A,I
    Cpu3 = Cpu2#cpu_state{i = 16#42, iff2 = 1},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#42, Cpu4#cpu_state.a),
    ?assertEqual(16#04, Cpu4#cpu_state.f band 16#04),
    ?assertEqual(9, z80_cpu:t_states(Cpu4)).

ed_ld_r_a_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#ED),  %% ED prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#4F),  %% LD R,A
    Cpu3 = Cpu2#cpu_state{a = 16#FF},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#80, Cpu4#cpu_state.r),
    ?assertEqual(9, z80_cpu:t_states(Cpu4)).

ed_ld_a_r_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#ED),  %% ED prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#5F),  %% LD A,R
    Cpu3 = Cpu2#cpu_state{r = 16#FE, iff2 = 0},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#FF, Cpu4#cpu_state.a),
    ?assertEqual(16#80, Cpu4#cpu_state.r),
    ?assertEqual(0, Cpu4#cpu_state.f band 16#04),
    ?assertEqual(9, z80_cpu:t_states(Cpu4)).

%% --- ED NEG ---

ed_neg_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#ED),  %% ED prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#44),  %% NEG
    Cpu3 = Cpu2#cpu_state{a = 16#40},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#C0, Cpu4#cpu_state.a),
    ?assertEqual(16#83, Cpu4#cpu_state.f),
    ?assertEqual(8, z80_cpu:t_states(Cpu4)).

ed_neg_zero_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#ED),  %% ED prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#44),  %% NEG
    Cpu3 = Cpu2#cpu_state{a = 0},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(0, Cpu4#cpu_state.a),
    ?assertEqual(16#42, Cpu4#cpu_state.f),
    ?assertEqual(8, z80_cpu:t_states(Cpu4)).

ed_neg_80_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#ED),  %% ED prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#44),  %% NEG
    Cpu3 = Cpu2#cpu_state{a = 16#80},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#80, Cpu4#cpu_state.a),
    ?assertEqual(16#87, Cpu4#cpu_state.f),
    ?assertEqual(8, z80_cpu:t_states(Cpu4)).

%% --- ED ADC HL, rr / SBC HL, rr ---

ed_adc_hl_bc_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#ED),  %% ED prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#4A),  %% ADC HL,BC
    Cpu3 = Cpu2#cpu_state{h = 16#12, l = 16#34, b = 16#00, c = 16#78, f = 0},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#12AC, z80_cpu:get_reg_pair(hl, Cpu4)),
    ?assertEqual(0, Cpu4#cpu_state.f band 16#01),
    ?assertEqual(15, z80_cpu:t_states(Cpu4)).

ed_sbc_hl_bc_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#ED),  %% ED prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#42),  %% SBC HL,BC
    Cpu3 = Cpu2#cpu_state{h = 16#12, l = 16#34, b = 16#00, c = 16#78, f = 0},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#11BC, z80_cpu:get_reg_pair(hl, Cpu4)),
    ?assertEqual(0, Cpu4#cpu_state.f band 16#01),
    ?assertEqual(15, z80_cpu:t_states(Cpu4)).

ed_adc_hl_de_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#ED),  %% ED prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#5A),  %% ADC HL,DE
    Cpu3 = Cpu2#cpu_state{h = 16#00, l = 16#00, d = 16#00, e = 16#01, f = 0},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#0001, z80_cpu:get_reg_pair(hl, Cpu4)),
    ?assertEqual(15, z80_cpu:t_states(Cpu4)).

ed_sbc_hl_de_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#ED),  %% ED prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#52),  %% SBC HL,DE
    Cpu3 = Cpu2#cpu_state{h = 16#00, l = 16#01, d = 16#00, e = 16#02, f = 0},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#FFFF, z80_cpu:get_reg_pair(hl, Cpu4)),
    ?assertEqual(15, z80_cpu:t_states(Cpu4)).

ed_adc_hl_hl_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#ED),  %% ED prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#6A),  %% ADC HL,HL
    Cpu3 = Cpu2#cpu_state{h = 16#12, l = 16#34, f = 0},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#2468, z80_cpu:get_reg_pair(hl, Cpu4)),
    ?assertEqual(15, z80_cpu:t_states(Cpu4)).

ed_sbc_hl_hl_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#ED),  %% ED prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#62),  %% SBC HL,HL
    Cpu3 = Cpu2#cpu_state{h = 16#12, l = 16#34, f = 0},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(0, z80_cpu:get_reg_pair(hl, Cpu4)),
    ?assertEqual(15, z80_cpu:t_states(Cpu4)).

ed_adc_hl_sp_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#ED),  %% ED prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#7A),  %% ADC HL,SP
    Cpu3 = Cpu2#cpu_state{h = 16#00, l = 16#00, sp = 16#1234, f = 0},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#1234, z80_cpu:get_reg_pair(hl, Cpu4)),
    ?assertEqual(15, z80_cpu:t_states(Cpu4)).

ed_sbc_hl_sp_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#ED),  %% ED prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#72),  %% SBC HL,SP
    Cpu3 = Cpu2#cpu_state{h = 16#12, l = 16#34, sp = 16#1234, f = 0},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(0, z80_cpu:get_reg_pair(hl, Cpu4)),
    ?assertEqual(15, z80_cpu:t_states(Cpu4)).

%% --- ED IN r,(C) / OUT (C),r ---

ed_in_b_c_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#ED),  %% ED prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#40),  %% IN B,(C)
    Cpu3 = Cpu2#cpu_state{b = 0, c = 16#00},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#FF, Cpu4#cpu_state.b),
    ?assertEqual(12, z80_cpu:t_states(Cpu4)).

ed_in_a_c_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#ED),  %% ED prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#78),  %% IN A,(C)
    Cpu3 = Cpu2#cpu_state{c = 16#FF},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#FF, Cpu4#cpu_state.a),
    ?assertEqual(12, z80_cpu:t_states(Cpu4)).

ed_in_f_c_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#ED),  %% ED prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#70),  %% IN F,(C) (undocumented)
    Cpu3 = Cpu2#cpu_state{c = 16#10, f = 0},
    Cpu4 = z80_cpu:step(Cpu3),
    %% Port returns 0xFF: S=1, V=parity(0xFF)=1, F3=1, F5=1 -> 0xAC
    ?assertEqual(16#AC, Cpu4#cpu_state.f),
    ?assertEqual(12, z80_cpu:t_states(Cpu4)).

ed_out_c_b_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#ED),  %% ED prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#41),  %% OUT (C),B
    Cpu3 = Cpu2#cpu_state{b = 16#42, c = 16#10},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(12, z80_cpu:t_states(Cpu4)).

ed_out_c_a_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#ED),  %% ED prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#79),  %% OUT (C),A
    Cpu3 = Cpu2#cpu_state{a = 16#55, c = 16#20},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(12, z80_cpu:t_states(Cpu4)).

ed_out_c_0_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#ED),  %% ED prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#71),  %% OUT (C),0 (undocumented)
    Cpu3 = Cpu2#cpu_state{c = 16#30},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(12, z80_cpu:t_states(Cpu4)).

%% --- ED Block Transfer: LDI, LDD, LDIR, LDDR ---

ed_ldi_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#ED),  %% ED prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#A0),  %% LDI
    Cpu3 = Cpu2#cpu_state{h = 16#40, l = 16#00, d = 16#50, e = 16#00, b = 0, c = 16#02, a = 16#00},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#4001, z80_cpu:get_reg_pair(hl, Cpu4)),
    ?assertEqual(16#5001, z80_cpu:get_reg_pair(de, Cpu4)),
    ?assertEqual(16#0001, z80_cpu:get_reg_pair(bc, Cpu4)),
    ?assertEqual(16#04, Cpu4#cpu_state.f band 16#04),
    ?assertEqual(16, z80_cpu:t_states(Cpu4)).

ed_ldd_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#ED),  %% ED prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#A8),  %% LDD
    Cpu3 = Cpu2#cpu_state{h = 16#40, l = 16#00, d = 16#50, e = 16#00, b = 0, c = 16#02, a = 16#00},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#3FFF, z80_cpu:get_reg_pair(hl, Cpu4)),
    ?assertEqual(16#4FFF, z80_cpu:get_reg_pair(de, Cpu4)),
    ?assertEqual(16#0001, z80_cpu:get_reg_pair(bc, Cpu4)),
    ?assertEqual(16, z80_cpu:t_states(Cpu4)).

ed_ldir_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#11),
    Cpu2 = test_helpers:write_mem(Cpu1, 16#4001, 16#22),
    Cpu3 = test_helpers:write_mem(Cpu2, 0, 16#ED),  %% ED prefix
    Cpu4 = test_helpers:write_mem(Cpu3, 1, 16#B0),  %% LDIR
    Cpu5 = Cpu4#cpu_state{h = 16#40, l = 16#00, d = 16#50, e = 16#00, b = 0, c = 16#02, a = 16#00},
    %% LDIR does one iteration per step, repeats via PC-=2
    Cpu6 = z80_cpu:step(Cpu5),
    Cpu7 = z80_cpu:step(Cpu6),
    ?assertEqual(16#4002, z80_cpu:get_reg_pair(hl, Cpu7)),
    ?assertEqual(16#5002, z80_cpu:get_reg_pair(de, Cpu7)),
    ?assertEqual(16#0000, z80_cpu:get_reg_pair(bc, Cpu7)),
    ?assertEqual(0, Cpu7#cpu_state.f band 16#04),
    ?assertEqual(16#11, test_helpers:read_mem(Cpu7, 16#5000)),
    ?assertEqual(16#22, test_helpers:read_mem(Cpu7, 16#5001)).

%% LDIR NOP' skip: BC=0 AND PV=0 → instruction skipped entirely
ed_ldir_nop_skip_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#AA),  %% target memory
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#ED),        %% ED prefix
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#B0),        %% LDIR
    %% BC=0, PV=0 (F=0x00), HL=source, DE=dest
    Cpu4 = Cpu3#cpu_state{h = 16#40, l = 16#00, d = 16#50, e = 16#00,
                           b = 0, c = 0, a = 16#42, f = 16#00},
    Cpu5 = z80_cpu:step(Cpu4),
    %% PC must advance past 2-byte opcode (PC=2)
    ?assertEqual(2, Cpu5#cpu_state.pc),
    %% No registers changed
    ?assertEqual(16#4000, z80_cpu:get_reg_pair(hl, Cpu5)),
    ?assertEqual(16#5000, z80_cpu:get_reg_pair(de, Cpu5)),
    ?assertEqual(16#0000, z80_cpu:get_reg_pair(bc, Cpu5)),
    ?assertEqual(16#42, Cpu5#cpu_state.a),
    %% Flags unchanged (were 0x00)
    ?assertEqual(16#00, Cpu5#cpu_state.f band 16#FF),
    %% Memory unchanged
    ?assertEqual(16#AA, test_helpers:read_mem(Cpu5, 16#4000)),
    ?assertEqual(0, test_helpers:read_mem(Cpu5, 16#5000)),
    %% 16 T-states (8 fetch + 8 skip)
    ?assertEqual(16, z80_cpu:t_states(Cpu5)).

%% LDIR NOP' skip: BC=0 AND PV=1 → NOT skipped, one iteration then loop
ed_ldir_bc0_pv1_runs_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#BB),
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#ED),
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#B0),
    %% BC=0, PV=1 (F has bit2 set = 0x04)
    Cpu4 = Cpu3#cpu_state{h = 16#40, l = 16#00, d = 16#50, e = 16#00,
                           b = 0, c = 0, a = 16#00, f = 16#04},
    Cpu5 = z80_cpu:step(Cpu4),
    %% One iteration runs: byte copied, BC becomes 0xFFFF, HL+1, DE+1
    ?assertEqual(16#4001, z80_cpu:get_reg_pair(hl, Cpu5)),
    ?assertEqual(16#5001, z80_cpu:get_reg_pair(de, Cpu5)),
    ?assertEqual(16#FFFF, z80_cpu:get_reg_pair(bc, Cpu5)),
    ?assertEqual(16#BB, test_helpers:read_mem(Cpu5, 16#5000)),
    %% PV set because BC≠0
    ?assertEqual(?FLAG_V, Cpu5#cpu_state.f band ?FLAG_V),
    %% PC=0 (looped back via PC-=2)
    ?assertEqual(0, Cpu5#cpu_state.pc).

ed_lddr_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#11),
    Cpu2 = test_helpers:write_mem(Cpu1, 16#4001, 16#22),
    Cpu3 = test_helpers:write_mem(Cpu2, 0, 16#ED),  %% ED prefix
    Cpu4 = test_helpers:write_mem(Cpu3, 1, 16#B8),  %% LDDR
    Cpu5 = Cpu4#cpu_state{h = 16#40, l = 16#01, d = 16#50, e = 16#01, b = 0, c = 16#02, a = 16#00},
    %% LDDR does one iteration per step, repeats via PC-=2
    Cpu6 = z80_cpu:step(Cpu5),
    Cpu7 = z80_cpu:step(Cpu6),
    ?assertEqual(16#3FFF, z80_cpu:get_reg_pair(hl, Cpu7)),
    ?assertEqual(16#4FFF, z80_cpu:get_reg_pair(de, Cpu7)),
    ?assertEqual(16#0000, z80_cpu:get_reg_pair(bc, Cpu7)),
    ?assertEqual(16#11, test_helpers:read_mem(Cpu7, 16#5000)),
    ?assertEqual(16#22, test_helpers:read_mem(Cpu7, 16#5001)).

%% --- ED Block Search: CPI, CPD, CPIR, CPDR ---

ed_cpi_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#55),
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#ED),  %% ED prefix
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#A1),  %% CPI
    Cpu4 = Cpu3#cpu_state{h = 16#40, l = 16#00, a = 16#55, b = 0, c = 16#03},
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(16#4001, z80_cpu:get_reg_pair(hl, Cpu5)),
    ?assertEqual(16#0002, z80_cpu:get_reg_pair(bc, Cpu5)),
    ?assertEqual(16#44, Cpu5#cpu_state.f band 16#44),
    ?assertEqual(16, z80_cpu:t_states(Cpu5)).

ed_cpi_no_match_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#44),
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#ED),  %% ED prefix
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#A1),  %% CPI
    Cpu4 = Cpu3#cpu_state{h = 16#40, l = 16#00, a = 16#55, b = 0, c = 16#03},
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(16#4001, z80_cpu:get_reg_pair(hl, Cpu5)),
    ?assertEqual(16#0002, z80_cpu:get_reg_pair(bc, Cpu5)),
    ?assertEqual(16#04, Cpu5#cpu_state.f band 16#04),
    ?assertEqual(16, z80_cpu:t_states(Cpu5)).

ed_cpir_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#11),
    Cpu2 = test_helpers:write_mem(Cpu1, 16#4001, 16#55),
    Cpu3 = test_helpers:write_mem(Cpu2, 16#4002, 16#22),
    Cpu4 = test_helpers:write_mem(Cpu3, 0, 16#ED),  %% ED prefix
    Cpu5 = test_helpers:write_mem(Cpu4, 1, 16#B1),  %% CPIR
    Cpu6 = Cpu5#cpu_state{h = 16#40, l = 16#00, a = 16#55, b = 0, c = 16#03},
    %% Step 1: compare (0x4000)=0x11 vs A=0x55, no match, BC=2, repeat
    Cpu7 = z80_cpu:step(Cpu6),
    %% Step 2: compare (0x4001)=0x55 vs A=0x55, match, BC=1, stop
    Cpu8 = z80_cpu:step(Cpu7),
    ?assertEqual(16#4002, z80_cpu:get_reg_pair(hl, Cpu8)),
    ?assertEqual(16#0001, z80_cpu:get_reg_pair(bc, Cpu8)),
    ?assertEqual(16#44, Cpu8#cpu_state.f band 16#44).

ed_cpdr_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4001, 16#11),
    Cpu2 = test_helpers:write_mem(Cpu1, 16#4000, 16#55),
    Cpu3 = test_helpers:write_mem(Cpu2, 0, 16#ED),  %% ED prefix
    Cpu4 = test_helpers:write_mem(Cpu3, 1, 16#B9),  %% CPDR
    Cpu5 = Cpu4#cpu_state{h = 16#40, l = 16#01, a = 16#55, b = 0, c = 16#02},
    %% Step 1: compare (0x4001)=0x11 vs A=0x55, no match, BC=1, repeat
    Cpu6 = z80_cpu:step(Cpu5),
    %% Step 2: compare (0x4000)=0x55 vs A=0x55, match, BC=0, stop
    Cpu7 = z80_cpu:step(Cpu6),
    ?assertEqual(16#3FFF, z80_cpu:get_reg_pair(hl, Cpu7)),
    ?assertEqual(16#0000, z80_cpu:get_reg_pair(bc, Cpu7)),
    ?assertEqual(16#40, Cpu7#cpu_state.f band 16#44).

%% --- ED Block I/O: INI, IND, INIR, INDR, OUTI, OUTD, OTIR, OTDR ---

ed_ini_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#ED),  %% ED prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#A2),  %% INI
    Cpu3 = Cpu2#cpu_state{b = 0, c = 16#10, h = 16#40, l = 16#00},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#FF, test_helpers:read_mem(Cpu4, 16#4000)),
    ?assertEqual(16#4001, z80_cpu:get_reg_pair(hl, Cpu4)),
    ?assertEqual(16#FF, Cpu4#cpu_state.b),
    ?assertEqual(16, z80_cpu:t_states(Cpu4)).

ed_ind_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#ED),  %% ED prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#AA),  %% IND
    Cpu3 = Cpu2#cpu_state{b = 0, c = 16#10, h = 16#40, l = 16#01},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#FF, test_helpers:read_mem(Cpu4, 16#4001)),
    ?assertEqual(16#4000, z80_cpu:get_reg_pair(hl, Cpu4)),
    ?assertEqual(16#FF, Cpu4#cpu_state.b),
    ?assertEqual(16, z80_cpu:t_states(Cpu4)).

ed_inir_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#ED),  %% ED prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#B2),  %% INIR
    Cpu3 = Cpu2#cpu_state{b = 16#02, c = 16#10, h = 16#40, l = 16#00},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#FF, test_helpers:read_mem(Cpu4, 16#4000)),
    ?assertEqual(16#FF, test_helpers:read_mem(Cpu4, 16#4001)),
    ?assertEqual(16#4002, z80_cpu:get_reg_pair(hl, Cpu4)),
    ?assertEqual(16#00, Cpu4#cpu_state.b),
    ?assertEqual(37, z80_cpu:t_states(Cpu4)).

ed_outi_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#55),
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#ED),  %% ED prefix
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#A3),  %% OUTI
    Cpu4 = Cpu3#cpu_state{b = 0, c = 16#10, h = 16#40, l = 16#00},
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(16#4001, z80_cpu:get_reg_pair(hl, Cpu5)),
    ?assertEqual(16#FF, Cpu5#cpu_state.b),
    ?assertEqual(16, z80_cpu:t_states(Cpu5)).

ed_otir_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#11),
    Cpu2 = test_helpers:write_mem(Cpu1, 16#4001, 16#22),
    Cpu3 = test_helpers:write_mem(Cpu2, 0, 16#ED),  %% ED prefix
    Cpu4 = test_helpers:write_mem(Cpu3, 1, 16#B3),  %% OTIR
    Cpu5 = Cpu4#cpu_state{b = 16#02, c = 16#10, h = 16#40, l = 16#00},
    Cpu6 = z80_cpu:step(Cpu5),
    ?assertEqual(16#4002, z80_cpu:get_reg_pair(hl, Cpu6)),
    ?assertEqual(16#00, Cpu6#cpu_state.b),
    ?assertEqual(37, z80_cpu:t_states(Cpu6)).

%% --- ED RETN/RETI ---

ed_retn_test() ->
    Cpu0 = test_helpers:init_cpu(),
    %% Push return address 0x1234 onto stack at 0x4000-0x4001
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#34),  %% low byte
    Cpu2 = test_helpers:write_mem(Cpu1, 16#4001, 16#12),  %% high byte
    Cpu3 = test_helpers:write_mem(Cpu2, 0, 16#ED),
    Cpu4 = test_helpers:write_mem(Cpu3, 1, 16#45),  %% RETN
    Cpu5 = Cpu4#cpu_state{sp = 16#4000, iff2 = 1, f = 16#FF, a = 16#AA},
    Cpu6 = z80_cpu:step(Cpu5),
    ?assertEqual(16#1234, Cpu6#cpu_state.pc),
    ?assertEqual(16#4002, Cpu6#cpu_state.sp),
    ?assertEqual(1, Cpu6#cpu_state.iff1),
    ?assertEqual(16#FF, Cpu6#cpu_state.f),  %% flags unchanged
    ?assertEqual(16#AA, Cpu6#cpu_state.a),
    ?assertEqual(14, z80_cpu:t_states(Cpu6)).

ed_reti_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#78),
    Cpu2 = test_helpers:write_mem(Cpu1, 16#4001, 16#56),
    Cpu3 = test_helpers:write_mem(Cpu2, 0, 16#ED),
    Cpu4 = test_helpers:write_mem(Cpu3, 1, 16#4D),  %% RETI
    Cpu5 = Cpu4#cpu_state{sp = 16#4000, iff2 = 1, f = 16#FF, a = 16#BB},
    Cpu6 = z80_cpu:step(Cpu5),
    ?assertEqual(16#5678, Cpu6#cpu_state.pc),
    ?assertEqual(16#4002, Cpu6#cpu_state.sp),
    ?assertEqual(1, Cpu6#cpu_state.iff1),
    ?assertEqual(16#FF, Cpu6#cpu_state.f),
    ?assertEqual(16#BB, Cpu6#cpu_state.a),
    ?assertEqual(14, z80_cpu:t_states(Cpu6)).

ed_retn_iff2_zero_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#00),
    Cpu2 = test_helpers:write_mem(Cpu1, 16#4001, 16#80),
    Cpu3 = test_helpers:write_mem(Cpu2, 0, 16#ED),
    Cpu4 = test_helpers:write_mem(Cpu3, 1, 16#45),  %% RETN
    Cpu5 = Cpu4#cpu_state{sp = 16#4000, iff2 = 0, f = 16#00},
    Cpu6 = z80_cpu:step(Cpu5),
    ?assertEqual(16#8000, Cpu6#cpu_state.pc),
    ?assertEqual(0, Cpu6#cpu_state.iff1),
    ?assertEqual(0, Cpu6#cpu_state.iff2).

%% --- ED Undocumented RETN*/RETI* (ED 55,5D,65,6D,75,7D) ---

ed_retn_55_test() -> ed_retn_undoc_test(16#55).
ed_retn_65_test() -> ed_retn_undoc_test(16#65).
ed_retn_75_test() -> ed_retn_undoc_test(16#75).
ed_reti_5d_test() -> ed_retn_undoc_test(16#5D).
ed_reti_6d_test() -> ed_retn_undoc_test(16#6D).
ed_reti_7d_test() -> ed_retn_undoc_test(16#7D).

ed_retn_undoc_test(Opc) ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#56),
    Cpu2 = test_helpers:write_mem(Cpu1, 16#4001, 16#34),
    Cpu3 = test_helpers:write_mem(Cpu2, 0, 16#ED),
    Cpu4 = test_helpers:write_mem(Cpu3, 1, Opc),
    Cpu5 = Cpu4#cpu_state{sp = 16#4000, iff2 = 1, f = 16#FF},
    Cpu6 = z80_cpu:step(Cpu5),
    ?assertEqual(16#3456, Cpu6#cpu_state.pc),
    ?assertEqual(16#4002, Cpu6#cpu_state.sp),
    ?assertEqual(1, Cpu6#cpu_state.iff1),
    ?assertEqual(16#FF, Cpu6#cpu_state.f),
    ?assertEqual(14, z80_cpu:t_states(Cpu6)).

%% --- ED LDI/LDD F3/F5 tests - F3/F5 from (transferred_byte + A) ---

ed_ldi_f3f5_test() ->
    %% LDI: transferred byte + A -> F3/F5 bits
    %% Mem(0x4000) = 0x05, A = 0x03 -> sum = 0x08, F3=1, F5=0
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#05),
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#ED),
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#A0),  %% LDI
    Cpu4 = Cpu3#cpu_state{h = 16#40, l = 16#00, d = 16#50, e = 16#00,
                          b = 0, c = 16#02, a = 16#03},
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(16#08, Cpu5#cpu_state.f band 16#28).

ed_ldi_f3f5_both_test() ->
    %% LDI: transferred byte + A -> F3/F5 both set
    %% Mem(0x4000) = 0x18, A = 0x10 -> sum = 0x28
    %% F3 = V & 0x08 = 0x08, F5 = V & 0x02 mapped to 0x20 = 0 (undocumented: bit1 not bit5)
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#18),
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#ED),
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#A0),  %% LDI
    Cpu4 = Cpu3#cpu_state{h = 16#40, l = 16#00, d = 16#50, e = 16#00,
                          b = 0, c = 16#02, a = 16#10},
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(16#08, Cpu5#cpu_state.f band 16#28).

ed_ldi_pv_zero_test() ->
    %% LDI: P/V=0 when BC=0 after decrement
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#11),
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#ED),
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#A0),  %% LDI
    Cpu4 = Cpu3#cpu_state{h = 16#40, l = 16#00, d = 16#50, e = 16#00,
                          b = 0, c = 16#01, a = 16#00},
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(0, Cpu5#cpu_state.f band ?FLAG_V).

ed_ldd_f3f5_test() ->
    %% LDD: transferred byte + A -> F3/F5 bits
    %% Mem(0x4000) = 0x05, A = 0x03 -> sum = 0x08, F3=1, F5=0
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#05),
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#ED),
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#A8),  %% LDD
    Cpu4 = Cpu3#cpu_state{h = 16#40, l = 16#00, d = 16#50, e = 16#00,
                          b = 0, c = 16#02, a = 16#03},
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(16#08, Cpu5#cpu_state.f band 16#28).

ed_ldd_pv_zero_test() ->
    %% LDD: P/V=0 when BC=0 after decrement
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#11),
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#ED),
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#A8),  %% LDD
    Cpu4 = Cpu3#cpu_state{h = 16#40, l = 16#00, d = 16#50, e = 16#00,
                          b = 0, c = 16#01, a = 16#00},
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(0, Cpu5#cpu_state.f band ?FLAG_V).

%% --- ED CPI/CPD F3/F5 tests - F3/F5 from (A - (HL) - H_flag) ---

ed_cpi_f3f5_test() ->
    %% CPI: temp = A - (HL) - H_flag, F3/F5 from temp
    %% A = 0x55, (HL) = 0x01, H_flag = 0 -> temp = 0x54
    %% F3 = Tmp & 0x08 = 0, F5 = Tmp & 0x02 mapped to 0x20 = 0 (both zero)
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#01),
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#ED),
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#A1),  %% CPI
    Cpu4 = Cpu3#cpu_state{h = 16#40, l = 16#00, a = 16#55, b = 0, c = 16#03},
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(16#00, Cpu5#cpu_state.f band 16#28).

ed_cpi_f3f5_with_h_flag_test() ->
    %% CPI with half-carry: temp = A - (HL) - H
    %% A = 0x10, (HL) = 0x08, H_flag = 1 -> temp = 0x10 - 0x08 - 1 = 0x07
    %% F3 = Tmp & 0x08 = 0, F5 = Tmp & 0x02 mapped to 0x20 = 0x20
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#08),
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#ED),
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#A1),  %% CPI
    Cpu4 = Cpu3#cpu_state{h = 16#40, l = 16#00, a = 16#10, b = 0, c = 16#03},
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(16#20, Cpu5#cpu_state.f band 16#28).

ed_cpi_pv_zero_test() ->
    %% CPI: P/V=0 when BC=0 after decrement (match, BC was 1)
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#55),
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#ED),
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#A1),  %% CPI
    Cpu4 = Cpu3#cpu_state{h = 16#40, l = 16#00, a = 16#55, b = 0, c = 16#01},
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(0, Cpu5#cpu_state.f band ?FLAG_V).

ed_cpd_f3f5_test() ->
    %% CPD: temp = A - (HL) - H_flag, F3/F5 from temp
    %% A = 0x30, (HL) = 0x01, H_flag = 0 -> temp = 0x2F
    %% 0x2F = 0010 1111, F3=1, F5=1
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#01),
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#ED),
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#A9),  %% CPD
    Cpu4 = Cpu3#cpu_state{h = 16#40, l = 16#00, a = 16#30, b = 0, c = 16#03},
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(16#28, Cpu5#cpu_state.f band 16#28).

ed_cpd_pv_zero_test() ->
    %% CPD: P/V=0 when BC=0 after decrement (match, BC was 1)
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#55),
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#ED),
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#A9),  %% CPD
    Cpu4 = Cpu3#cpu_state{h = 16#40, l = 16#00, a = 16#55, b = 0, c = 16#01},
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(0, Cpu5#cpu_state.f band ?FLAG_V).

%% --- NEG undocumented variants ---

ed_neg_4c_test() -> ed_neg_undoc_variant_test(16#4C).
ed_neg_54_test() -> ed_neg_undoc_variant_test(16#54).
ed_neg_5c_test() -> ed_neg_undoc_variant_test(16#5C).
ed_neg_64_test() -> ed_neg_undoc_variant_test(16#64).
ed_neg_6c_test() -> ed_neg_undoc_variant_test(16#6C).
ed_neg_74_test() -> ed_neg_undoc_variant_test(16#74).
ed_neg_7c_test() -> ed_neg_undoc_variant_test(16#7C).

ed_neg_undoc_variant_test(Opc) ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#ED),
    Cpu2 = test_helpers:write_mem(Cpu1, 1, Opc),
    Cpu3 = Cpu2#cpu_state{a = 16#40},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#C0, Cpu4#cpu_state.a),
    ?assertEqual(16#83, Cpu4#cpu_state.f).

%% --- RLD/RRD: only C preserved, N=0, H=0, F3/F5 from result ---

ed_rrd_flags_test() ->
    %% RRD: N=0, H=0, only C preserved from old flags
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#34),
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#ED),
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#67),  %% RRD
    Cpu4 = Cpu3#cpu_state{a = 16#00, h = 16#40, l = 16#00,
                          f = ?FLAG_C bor ?FLAG_N bor ?FLAG_H bor ?FLAG_V bor ?FLAG_Z bor ?FLAG_S},
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(?FLAG_C, Cpu5#cpu_state.f band ?FLAG_C),  %% C preserved
    ?assertEqual(0, Cpu5#cpu_state.f band (?FLAG_N bor ?FLAG_H)).  %% N and H cleared

ed_rld_flags_test() ->
    %% RLD: N=0, H=0, only C preserved
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#34),
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#ED),
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#6F),  %% RLD
    Cpu4 = Cpu3#cpu_state{a = 16#00, h = 16#40, l = 16#00,
                          f = ?FLAG_C bor ?FLAG_N bor ?FLAG_H bor ?FLAG_V bor ?FLAG_Z bor ?FLAG_S},
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(?FLAG_C, Cpu5#cpu_state.f band ?FLAG_C),
    ?assertEqual(0, Cpu5#cpu_state.f band (?FLAG_N bor ?FLAG_H)).

ed_rrd_f3f5_test() ->
    %% RRD: F3/F5 from result A
    %% A = 0x28, (HL) = 0x34 -> A = 0x24, (HL) = 0x43
    %% 0x24: bit5=1, bit3=0 -> F3F5 = 0x20
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#34),
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#ED),
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#67),  %% RRD
    Cpu4 = Cpu3#cpu_state{a = 16#28, h = 16#40, l = 16#00, f = 0},
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(16#24, Cpu5#cpu_state.a),
    ?assertEqual(16#20, Cpu5#cpu_state.f band 16#28).

ed_rld_f3f5_test() ->
    %% RLD: F3/F5 from result A
    %% A = 0x00, (HL) = 0x28 -> temp=0x28, A = 0x02, (HL) = 0x80
    %% 0x02: F3=0, F5=0
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#28),
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#ED),
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#6F),  %% RLD
    Cpu4 = Cpu3#cpu_state{a = 16#00, h = 16#40, l = 16#00, f = 0},
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(16#02, Cpu5#cpu_state.a),
    ?assertEqual(0, Cpu5#cpu_state.f band 16#28).
