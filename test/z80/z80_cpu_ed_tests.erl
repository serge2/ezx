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
    ?assertEqual(16#84, Cpu4#cpu_state.f),
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
