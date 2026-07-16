-module(z80_cpu_ed_tests).

-include("z80_records.hrl").
-include_lib("eunit/include/eunit.hrl").

%% --- ED Prefix Tests ---

ed_rrd_test() ->
    Machine0 = z80_emulator:init(),
    Machine1 = z80_emulator:write_byte(Machine0, 0, 16#ED),
    Machine2 = z80_emulator:write_byte(Machine1, 1, 16#67),
    Machine3 = z80_emulator:write_byte(Machine2, 16#4000, 16#34),
    Cpu1 = Machine3#machine_state.cpu#cpu_state{a = 16#00, h = 16#40, l = 16#00},
    Machine4 = Machine3#machine_state{cpu = Cpu1},
    Machine5 = z80_cpu:step(Machine4),
    ?assertEqual(16#04, Machine5#machine_state.cpu#cpu_state.a),
    ?assertEqual(16#03, z80_emulator:read_byte(Machine5, 16#4000)),
    ?assertEqual(18, z80_cpu:t_states(Machine5)).

ed_rld_test() ->
    Machine0 = z80_emulator:init(),
    Machine1 = z80_emulator:write_byte(Machine0, 0, 16#ED),
    Machine2 = z80_emulator:write_byte(Machine1, 1, 16#6F),
    Machine3 = z80_emulator:write_byte(Machine2, 16#4000, 16#34),
    Cpu1 = Machine3#machine_state.cpu#cpu_state{a = 16#00, h = 16#40, l = 16#00},
    Machine4 = Machine3#machine_state{cpu = Cpu1},
    Machine5 = z80_cpu:step(Machine4),
    ?assertEqual(16#03, Machine5#machine_state.cpu#cpu_state.a),
    ?assertEqual(16#40, z80_emulator:read_byte(Machine5, 16#4000)),
    ?assertEqual(18, z80_cpu:t_states(Machine5)).

%% --- ED LD A,I / LD A,R / LD I,A / LD R,A ---

ed_ld_i_a_test() ->
    Machine0 = z80_emulator:init(),
    Machine1 = z80_emulator:write_byte(Machine0, 0, 16#ED), %% LD I,A
    Machine2 = z80_emulator:write_byte(Machine1, 1, 16#47),
    Cpu1 = Machine2#machine_state.cpu#cpu_state{a = 16#42},
    Machine3 = Machine2#machine_state{cpu = Cpu1},
    Machine4 = z80_cpu:step(Machine3),
    ?assertEqual(16#42, Machine4#machine_state.cpu#cpu_state.i),
    ?assertEqual(9, z80_cpu:t_states(Machine4)).

ed_ld_a_i_test() ->
    Machine0 = z80_emulator:init(),
    Machine1 = z80_emulator:write_byte(Machine0, 0, 16#ED), %% LD A,I
    Machine2 = z80_emulator:write_byte(Machine1, 1, 16#57),
    Cpu1 = Machine2#machine_state.cpu#cpu_state{i = 16#42, iff2 = 1},
    Machine3 = Machine2#machine_state{cpu = Cpu1},
    Machine4 = z80_cpu:step(Machine3),
    ?assertEqual(16#42, Machine4#machine_state.cpu#cpu_state.a),
    ?assertEqual(16#04, Machine4#machine_state.cpu#cpu_state.f band 16#04),
    ?assertEqual(9, z80_cpu:t_states(Machine4)).

ed_ld_r_a_test() ->
    Machine0 = z80_emulator:init(),
    Machine1 = z80_emulator:write_byte(Machine0, 0, 16#ED), %% LD R,A
    Machine2 = z80_emulator:write_byte(Machine1, 1, 16#4F),
    Cpu1 = Machine2#machine_state.cpu#cpu_state{a = 16#FF},
    Machine3 = Machine2#machine_state{cpu = Cpu1},
    Machine4 = z80_cpu:step(Machine3),
    ?assertEqual(16#80, Machine4#machine_state.cpu#cpu_state.r),  % The regiter R automatically increased at the end of a command
    ?assertEqual(9, z80_cpu:t_states(Machine4)).

ed_ld_a_r_test() ->
    Machine0 = z80_emulator:init(),
    Machine1 = z80_emulator:write_byte(Machine0, 0, 16#ED), %% LD A,R
    Machine2 = z80_emulator:write_byte(Machine1, 1, 16#5F),
    Cpu1 = Machine2#machine_state.cpu#cpu_state{r = 16#FE, iff2 = 0},
    Machine3 = Machine2#machine_state{cpu = Cpu1},
    Machine4 = z80_cpu:step(Machine3),
    ?assertEqual(16#FF, Machine4#machine_state.cpu#cpu_state.a),
    ?assertEqual(16#80, Machine4#machine_state.cpu#cpu_state.r),
    ?assertEqual(0, Machine4#machine_state.cpu#cpu_state.f band 16#04),
    ?assertEqual(9, z80_cpu:t_states(Machine4)).

%% --- ED NEG ---

ed_neg_test() ->
    Machine0 = z80_emulator:init(),
    Machine1 = z80_emulator:write_byte(Machine0, 0, 16#ED),
    Machine2 = z80_emulator:write_byte(Machine1, 1, 16#44),
    Cpu1 = Machine2#machine_state.cpu#cpu_state{a = 16#40},
    Machine3 = Machine2#machine_state{cpu = Cpu1},
    Machine4 = z80_cpu:step(Machine3),
    ?assertEqual(16#C0, Machine4#machine_state.cpu#cpu_state.a),
    ?assertEqual(16#83, Machine4#machine_state.cpu#cpu_state.f),
    ?assertEqual(8, z80_cpu:t_states(Machine4)).

ed_neg_zero_test() ->
    Machine0 = z80_emulator:init(),
    Machine1 = z80_emulator:write_byte(Machine0, 0, 16#ED),
    Machine2 = z80_emulator:write_byte(Machine1, 1, 16#44),
    Cpu1 = Machine2#machine_state.cpu#cpu_state{a = 0},
    Machine3 = Machine2#machine_state{cpu = Cpu1},
    Machine4 = z80_cpu:step(Machine3),
    ?assertEqual(0, Machine4#machine_state.cpu#cpu_state.a),
    ?assertEqual(16#42, Machine4#machine_state.cpu#cpu_state.f),
    ?assertEqual(8, z80_cpu:t_states(Machine4)).

ed_neg_80_test() ->
    Machine0 = z80_emulator:init(),
    Machine1 = z80_emulator:write_byte(Machine0, 0, 16#ED),
    Machine2 = z80_emulator:write_byte(Machine1, 1, 16#44),
    Cpu1 = Machine2#machine_state.cpu#cpu_state{a = 16#80},
    Machine3 = Machine2#machine_state{cpu = Cpu1},
    Machine4 = z80_cpu:step(Machine3),
    ?assertEqual(16#80, Machine4#machine_state.cpu#cpu_state.a),
    ?assertEqual(16#87, Machine4#machine_state.cpu#cpu_state.f),
    ?assertEqual(8, z80_cpu:t_states(Machine4)).

%% --- ED ADC HL, rr / SBC HL, rr ---

ed_adc_hl_bc_test() ->
    Machine0 = z80_emulator:init(),
    Machine1 = z80_emulator:write_byte(Machine0, 0, 16#ED),
    Machine2 = z80_emulator:write_byte(Machine1, 1, 16#4A),
    Cpu1 = Machine2#machine_state.cpu#cpu_state{h = 16#12, l = 16#34, b = 16#00, c = 16#78, f = 0},
    Machine3 = Machine2#machine_state{cpu = Cpu1},
    Machine4 = z80_cpu:step(Machine3),
    ?assertEqual(16#12AC, z80_cpu_helpers:get_reg_pair(hl, Machine4#machine_state.cpu)),
    ?assertEqual(0, Machine4#machine_state.cpu#cpu_state.f band 16#01),
    ?assertEqual(15, z80_cpu:t_states(Machine4)).

ed_sbc_hl_bc_test() ->
    Machine0 = z80_emulator:init(),
    Machine1 = z80_emulator:write_byte(Machine0, 0, 16#ED),
    Machine2 = z80_emulator:write_byte(Machine1, 1, 16#42),
    Cpu1 = Machine2#machine_state.cpu#cpu_state{h = 16#12, l = 16#34, b = 16#00, c = 16#78, f = 0},
    Machine3 = Machine2#machine_state{cpu = Cpu1},
    Machine4 = z80_cpu:step(Machine3),
    ?assertEqual(16#11BC, z80_cpu_helpers:get_reg_pair(hl, Machine4#machine_state.cpu)),
    ?assertEqual(0, Machine4#machine_state.cpu#cpu_state.f band 16#01),
    ?assertEqual(15, z80_cpu:t_states(Machine4)).

ed_adc_hl_de_test() ->
    Machine0 = z80_emulator:init(),
    Machine1 = z80_emulator:write_byte(Machine0, 0, 16#ED),
    Machine2 = z80_emulator:write_byte(Machine1, 1, 16#5A),
    Cpu1 = Machine2#machine_state.cpu#cpu_state{h = 16#00, l = 16#00, d = 16#00, e = 16#01, f = 0},
    Machine3 = Machine2#machine_state{cpu = Cpu1},
    Machine4 = z80_cpu:step(Machine3),
    ?assertEqual(16#0001, z80_cpu_helpers:get_reg_pair(hl, Machine4#machine_state.cpu)),
    ?assertEqual(15, z80_cpu:t_states(Machine4)).

ed_sbc_hl_de_test() ->
    Machine0 = z80_emulator:init(),
    Machine1 = z80_emulator:write_byte(Machine0, 0, 16#ED),
    Machine2 = z80_emulator:write_byte(Machine1, 1, 16#52),
    Cpu1 = Machine2#machine_state.cpu#cpu_state{h = 16#00, l = 16#01, d = 16#00, e = 16#02, f = 0},
    Machine3 = Machine2#machine_state{cpu = Cpu1},
    Machine4 = z80_cpu:step(Machine3),
    ?assertEqual(16#FFFF, z80_cpu_helpers:get_reg_pair(hl, Machine4#machine_state.cpu)),
    ?assertEqual(15, z80_cpu:t_states(Machine4)).

ed_adc_hl_hl_test() ->
    Machine0 = z80_emulator:init(),
    Machine1 = z80_emulator:write_byte(Machine0, 0, 16#ED),
    Machine2 = z80_emulator:write_byte(Machine1, 1, 16#6A),
    Cpu1 = Machine2#machine_state.cpu#cpu_state{h = 16#12, l = 16#34, f = 0},
    Machine3 = Machine2#machine_state{cpu = Cpu1},
    Machine4 = z80_cpu:step(Machine3),
    ?assertEqual(16#2468, z80_cpu_helpers:get_reg_pair(hl, Machine4#machine_state.cpu)),
    ?assertEqual(15, z80_cpu:t_states(Machine4)).

ed_sbc_hl_hl_test() ->
    Machine0 = z80_emulator:init(),
    Machine1 = z80_emulator:write_byte(Machine0, 0, 16#ED),
    Machine2 = z80_emulator:write_byte(Machine1, 1, 16#62),
    Cpu1 = Machine2#machine_state.cpu#cpu_state{h = 16#12, l = 16#34, f = 0},
    Machine3 = Machine2#machine_state{cpu = Cpu1},
    Machine4 = z80_cpu:step(Machine3),
    ?assertEqual(0, z80_cpu_helpers:get_reg_pair(hl, Machine4#machine_state.cpu)),
    ?assertEqual(15, z80_cpu:t_states(Machine4)).

ed_adc_hl_sp_test() ->
    Machine0 = z80_emulator:init(),
    Machine1 = z80_emulator:write_byte(Machine0, 0, 16#ED),
    Machine2 = z80_emulator:write_byte(Machine1, 1, 16#7A),
    Cpu1 = Machine2#machine_state.cpu#cpu_state{h = 16#00, l = 16#00, sp = 16#1234, f = 0},
    Machine3 = Machine2#machine_state{cpu = Cpu1},
    Machine4 = z80_cpu:step(Machine3),
    ?assertEqual(16#1234, z80_cpu_helpers:get_reg_pair(hl, Machine4#machine_state.cpu)),
    ?assertEqual(15, z80_cpu:t_states(Machine4)).

ed_sbc_hl_sp_test() ->
    Machine0 = z80_emulator:init(),
    Machine1 = z80_emulator:write_byte(Machine0, 0, 16#ED),
    Machine2 = z80_emulator:write_byte(Machine1, 1, 16#72),
    Cpu1 = Machine2#machine_state.cpu#cpu_state{h = 16#12, l = 16#34, sp = 16#1234, f = 0},
    Machine3 = Machine2#machine_state{cpu = Cpu1},
    Machine4 = z80_cpu:step(Machine3),
    ?assertEqual(0, z80_cpu_helpers:get_reg_pair(hl, Machine4#machine_state.cpu)),
    ?assertEqual(15, z80_cpu:t_states(Machine4)).

%% --- ED IN r,(C) / OUT (C),r ---

ed_in_b_c_test() ->
    Machine0 = z80_emulator:init(),
    Machine1 = z80_emulator:write_byte(Machine0, 0, 16#ED),
    Machine2 = z80_emulator:write_byte(Machine1, 1, 16#40),
    Cpu1 = Machine2#machine_state.cpu#cpu_state{b = 0, c = 16#00},
    Machine3 = Machine2#machine_state{cpu = Cpu1},
    Machine4 = z80_cpu:step(Machine3),
    ?assertEqual(16#FF, Machine4#machine_state.cpu#cpu_state.b),
    ?assertEqual(12, z80_cpu:t_states(Machine4)).

ed_in_a_c_test() ->
    Machine0 = z80_emulator:init(),
    Machine1 = z80_emulator:write_byte(Machine0, 0, 16#ED),
    Machine2 = z80_emulator:write_byte(Machine1, 1, 16#78),
    Cpu1 = Machine2#machine_state.cpu#cpu_state{c = 16#FF},
    Machine3 = Machine2#machine_state{cpu = Cpu1},
    Machine4 = z80_cpu:step(Machine3),
    ?assertEqual(16#FF, Machine4#machine_state.cpu#cpu_state.a),
    ?assertEqual(12, z80_cpu:t_states(Machine4)).

ed_in_f_c_test() ->
    Machine0 = z80_emulator:init(),
    Machine1 = z80_emulator:write_byte(Machine0, 0, 16#ED),
    Machine2 = z80_emulator:write_byte(Machine1, 1, 16#70),
    Cpu1 = Machine2#machine_state.cpu#cpu_state{c = 16#10, f = 0},
    Machine3 = Machine2#machine_state{cpu = Cpu1},
    Machine4 = z80_cpu:step(Machine3),
    ?assertEqual(16#84, Machine4#machine_state.cpu#cpu_state.f),
    ?assertEqual(12, z80_cpu:t_states(Machine4)).

ed_out_c_b_test() ->
    Machine0 = z80_emulator:init(),
    Machine1 = z80_emulator:write_byte(Machine0, 0, 16#ED),
    Machine2 = z80_emulator:write_byte(Machine1, 1, 16#41),
    Cpu1 = Machine2#machine_state.cpu#cpu_state{b = 16#42, c = 16#10},
    Machine3 = Machine2#machine_state{cpu = Cpu1},
    Machine4 = z80_cpu:step(Machine3),
    ?assertEqual(12, z80_cpu:t_states(Machine4)).

ed_out_c_a_test() ->
    Machine0 = z80_emulator:init(),
    Machine1 = z80_emulator:write_byte(Machine0, 0, 16#ED),
    Machine2 = z80_emulator:write_byte(Machine1, 1, 16#79),
    Cpu1 = Machine2#machine_state.cpu#cpu_state{a = 16#55, c = 16#20},
    Machine3 = Machine2#machine_state{cpu = Cpu1},
    Machine4 = z80_cpu:step(Machine3),
    ?assertEqual(12, z80_cpu:t_states(Machine4)).

ed_out_c_0_test() ->
    Machine0 = z80_emulator:init(),
    Machine1 = z80_emulator:write_byte(Machine0, 0, 16#ED),
    Machine2 = z80_emulator:write_byte(Machine1, 1, 16#71),
    Cpu1 = Machine2#machine_state.cpu#cpu_state{c = 16#30},
    Machine3 = Machine2#machine_state{cpu = Cpu1},
    Machine4 = z80_cpu:step(Machine3),
    ?assertEqual(12, z80_cpu:t_states(Machine4)).

%% --- ED Block Transfer: LDI, LDD, LDIR, LDDR ---

ed_ldi_test() ->
    Machine0 = z80_emulator:init(),
    Machine1 = z80_emulator:write_byte(Machine0, 0, 16#ED),
    Machine2 = z80_emulator:write_byte(Machine1, 1, 16#A0),
    Cpu1 = Machine2#machine_state.cpu#cpu_state{h = 16#40, l = 16#00, d = 16#50, e = 16#00, b = 0, c = 16#02, a = 16#00},
    Machine3 = Machine2#machine_state{cpu = Cpu1},
    Machine4 = z80_cpu:step(Machine3),
    ?assertEqual(16#4001, z80_cpu_helpers:get_reg_pair(hl, Machine4#machine_state.cpu)),
    ?assertEqual(16#5001, z80_cpu_helpers:get_reg_pair(de, Machine4#machine_state.cpu)),
    ?assertEqual(16#0001, z80_cpu_helpers:get_reg_pair(bc, Machine4#machine_state.cpu)),
    ?assertEqual(16#04, Machine4#machine_state.cpu#cpu_state.f band 16#04),
    ?assertEqual(16, z80_cpu:t_states(Machine4)).

ed_ldd_test() ->
    Machine0 = z80_emulator:init(),
    Machine1 = z80_emulator:write_byte(Machine0, 0, 16#ED),
    Machine2 = z80_emulator:write_byte(Machine1, 1, 16#A8),
    Cpu1 = Machine2#machine_state.cpu#cpu_state{h = 16#40, l = 16#00, d = 16#50, e = 16#00, b = 0, c = 16#02, a = 16#00},
    Machine3 = Machine2#machine_state{cpu = Cpu1},
    Machine4 = z80_cpu:step(Machine3),
    ?assertEqual(16#3FFF, z80_cpu_helpers:get_reg_pair(hl, Machine4#machine_state.cpu)),
    ?assertEqual(16#4FFF, z80_cpu_helpers:get_reg_pair(de, Machine4#machine_state.cpu)),
    ?assertEqual(16#0001, z80_cpu_helpers:get_reg_pair(bc, Machine4#machine_state.cpu)),
    ?assertEqual(16, z80_cpu:t_states(Machine4)).

ed_ldir_test() ->
    Machine0 = z80_emulator:init(),
    Machine1 = z80_emulator:write_byte(Machine0, 0, 16#ED),
    Machine2 = z80_emulator:write_byte(Machine1, 1, 16#B0),
    Machine3 = z80_emulator:write_byte(Machine2, 16#4000, 16#11),
    Machine4 = z80_emulator:write_byte(Machine3, 16#4001, 16#22),
    Cpu1 = Machine4#machine_state.cpu#cpu_state{h = 16#40, l = 16#00, d = 16#50, e = 16#00, b = 0, c = 16#02, a = 16#00},
    Machine5 = Machine4#machine_state{cpu = Cpu1},
    Machine6 = z80_cpu:step(Machine5),
    ?assertEqual(16#4001, z80_cpu_helpers:get_reg_pair(hl, Machine6#machine_state.cpu)),
    ?assertEqual(16#5001, z80_cpu_helpers:get_reg_pair(de, Machine6#machine_state.cpu)),
    ?assertEqual(16#0001, z80_cpu_helpers:get_reg_pair(bc, Machine6#machine_state.cpu)),
    ?assertEqual(16#04, Machine6#machine_state.cpu#cpu_state.f band 16#04),
    ?assertEqual(16#11, z80_emulator:read_byte(Machine6, 16#5000)),
    ?assertEqual(21, z80_cpu:t_states(Machine6)).

ed_lddr_test() ->
    Machine0 = z80_emulator:init(),
    Machine1 = z80_emulator:write_byte(Machine0, 0, 16#ED),
    Machine2 = z80_emulator:write_byte(Machine1, 1, 16#B8),
    Machine3 = z80_emulator:write_byte(Machine2, 16#4000, 16#11),
    Machine4 = z80_emulator:write_byte(Machine3, 16#4001, 16#22),
    Cpu1 = Machine4#machine_state.cpu#cpu_state{h = 16#40, l = 16#01, d = 16#50, e = 16#01, b = 0, c = 16#02, a = 16#00},
    Machine5 = Machine4#machine_state{cpu = Cpu1},
    Machine6 = z80_cpu:step(Machine5),
    ?assertEqual(16#4000, z80_cpu_helpers:get_reg_pair(hl, Machine6#machine_state.cpu)),
    ?assertEqual(16#5000, z80_cpu_helpers:get_reg_pair(de, Machine6#machine_state.cpu)),
    ?assertEqual(16#0001, z80_cpu_helpers:get_reg_pair(bc, Machine6#machine_state.cpu)),
    ?assertEqual(16#22, z80_emulator:read_byte(Machine6, 16#5001)),
    ?assertEqual(21, z80_cpu:t_states(Machine6)).

%% --- ED Block Search: CPI, CPD, CPIR, CPDR ---

ed_cpi_test() ->
    Machine0 = z80_emulator:init(),
    Machine1 = z80_emulator:write_byte(Machine0, 0, 16#ED),
    Machine2 = z80_emulator:write_byte(Machine1, 1, 16#A1),
    Cpu1 = Machine2#machine_state.cpu#cpu_state{h = 16#40, l = 16#00, a = 16#55, b = 0, c = 16#03},
    Machine3 = z80_emulator:write_byte(Machine2, 16#4000, 16#55),
    Machine4 = Machine3#machine_state{cpu = Cpu1},
    Machine5 = z80_cpu:step(Machine4),
    ?assertEqual(16#4001, z80_cpu_helpers:get_reg_pair(hl, Machine5#machine_state.cpu)),
    ?assertEqual(16#0002, z80_cpu_helpers:get_reg_pair(bc, Machine5#machine_state.cpu)),
    ?assertEqual(16#44, Machine5#machine_state.cpu#cpu_state.f band 16#44),
    ?assertEqual(16, z80_cpu:t_states(Machine5)).

ed_cpi_no_match_test() ->
    Machine0 = z80_emulator:init(),
    Machine1 = z80_emulator:write_byte(Machine0, 0, 16#ED),
    Machine2 = z80_emulator:write_byte(Machine1, 1, 16#A1),
    Cpu1 = Machine2#machine_state.cpu#cpu_state{h = 16#40, l = 16#00, a = 16#55, b = 0, c = 16#03},
    Machine3 = z80_emulator:write_byte(Machine2, 16#4000, 16#44),
    Machine4 = Machine3#machine_state{cpu = Cpu1},
    Machine5 = z80_cpu:step(Machine4),
    ?assertEqual(16#4001, z80_cpu_helpers:get_reg_pair(hl, Machine5#machine_state.cpu)),
    ?assertEqual(16#0002, z80_cpu_helpers:get_reg_pair(bc, Machine5#machine_state.cpu)),
    ?assertEqual(16#04, Machine5#machine_state.cpu#cpu_state.f band 16#04),
    ?assertEqual(16, z80_cpu:t_states(Machine5)).

ed_cpir_test() ->
    Machine0 = z80_emulator:init(),
    Machine1 = z80_emulator:write_byte(Machine0, 0, 16#ED),
    Machine2 = z80_emulator:write_byte(Machine1, 1, 16#B1),
    Machine3 = z80_emulator:write_byte(Machine2, 16#4000, 16#11),
    Machine4 = z80_emulator:write_byte(Machine3, 16#4001, 16#55),
    Machine5 = z80_emulator:write_byte(Machine4, 16#4002, 16#22),
    Cpu1 = Machine5#machine_state.cpu#cpu_state{h = 16#40, l = 16#00, a = 16#55, b = 0, c = 16#03},
    Machine6 = Machine5#machine_state{cpu = Cpu1},
    Machine7 = z80_cpu:step(Machine6),
    ?assertEqual(16#4001, z80_cpu_helpers:get_reg_pair(hl, Machine7#machine_state.cpu)),
    ?assertEqual(16#0002, z80_cpu_helpers:get_reg_pair(bc, Machine7#machine_state.cpu)),
    ?assertEqual(16#04, Machine7#machine_state.cpu#cpu_state.f band 16#04),
    ?assertEqual(21, z80_cpu:t_states(Machine7)).

ed_cpdr_test() ->
    Machine0 = z80_emulator:init(),
    Machine1 = z80_emulator:write_byte(Machine0, 0, 16#ED),
    Machine2 = z80_emulator:write_byte(Machine1, 1, 16#B9),
    Machine3 = z80_emulator:write_byte(Machine2, 16#4001, 16#11),
    Machine4 = z80_emulator:write_byte(Machine3, 16#4000, 16#55),
    Cpu1 = Machine4#machine_state.cpu#cpu_state{h = 16#40, l = 16#01, a = 16#55, b = 0, c = 16#02},
    Machine5 = Machine4#machine_state{cpu = Cpu1},
    Machine6 = z80_cpu:step(Machine5),
    ?assertEqual(16#4000, z80_cpu_helpers:get_reg_pair(hl, Machine6#machine_state.cpu)),
    ?assertEqual(16#0001, z80_cpu_helpers:get_reg_pair(bc, Machine6#machine_state.cpu)),
    ?assertEqual(16#04, Machine6#machine_state.cpu#cpu_state.f band 16#04),
    ?assertEqual(21, z80_cpu:t_states(Machine6)).

%% --- ED Block I/O: INI, IND, INIR, INDR, OUTI, OUTD, OTIR, OTDR ---

ed_ini_test() ->
    Machine0 = z80_emulator:init(),
    Machine1 = z80_emulator:write_byte(Machine0, 0, 16#ED),
    Machine2 = z80_emulator:write_byte(Machine1, 1, 16#A2),
    Cpu1 = Machine2#machine_state.cpu#cpu_state{b = 0, c = 16#10, h = 16#40, l = 16#00},
    Machine3 = Machine2#machine_state{cpu = Cpu1},
    Machine4 = z80_cpu:step(Machine3),
    ?assertEqual(16#FF, z80_emulator:read_byte(Machine4, 16#4000)),
    ?assertEqual(16#4001, z80_cpu_helpers:get_reg_pair(hl, Machine4#machine_state.cpu)),
    ?assertEqual(16#FF, Machine4#machine_state.cpu#cpu_state.b),
    ?assertEqual(16, z80_cpu:t_states(Machine4)).

ed_ind_test() ->
    Machine0 = z80_emulator:init(),
    Machine1 = z80_emulator:write_byte(Machine0, 0, 16#ED),
    Machine2 = z80_emulator:write_byte(Machine1, 1, 16#AA),
    Cpu1 = Machine2#machine_state.cpu#cpu_state{b = 0, c = 16#10, h = 16#40, l = 16#01},
    Machine3 = Machine2#machine_state{cpu = Cpu1},
    Machine4 = z80_cpu:step(Machine3),
    ?assertEqual(16#FF, z80_emulator:read_byte(Machine4, 16#4001)),
    ?assertEqual(16#4000, z80_cpu_helpers:get_reg_pair(hl, Machine4#machine_state.cpu)),
    ?assertEqual(16#FF, Machine4#machine_state.cpu#cpu_state.b),
    ?assertEqual(16, z80_cpu:t_states(Machine4)).

ed_inir_test() ->
    Machine0 = z80_emulator:init(),
    Machine1 = z80_emulator:write_byte(Machine0, 0, 16#ED),
    Machine2 = z80_emulator:write_byte(Machine1, 1, 16#B2),
    Cpu1 = Machine2#machine_state.cpu#cpu_state{b = 16#02, c = 16#10, h = 16#40, l = 16#00},
    Machine3 = Machine2#machine_state{cpu = Cpu1},
    Machine4 = z80_cpu:step(Machine3),
    ?assertEqual(16#FF, z80_emulator:read_byte(Machine4, 16#4000)),
    ?assertEqual(16#4001, z80_cpu_helpers:get_reg_pair(hl, Machine4#machine_state.cpu)),
    ?assertEqual(16#01, Machine4#machine_state.cpu#cpu_state.b),
    ?assertEqual(21, z80_cpu:t_states(Machine4)).

ed_outi_test() ->
    Machine0 = z80_emulator:init(),
    Machine1 = z80_emulator:write_byte(Machine0, 0, 16#ED),
    Machine2 = z80_emulator:write_byte(Machine1, 1, 16#A3),
    Machine3 = z80_emulator:write_byte(Machine2, 16#4000, 16#55),
    Cpu1 = Machine3#machine_state.cpu#cpu_state{b = 0, c = 16#10, h = 16#40, l = 16#00},
    Machine4 = Machine3#machine_state{cpu = Cpu1},
    Machine5 = z80_cpu:step(Machine4),
    ?assertEqual(16#4001, z80_cpu_helpers:get_reg_pair(hl, Machine5#machine_state.cpu)),
    ?assertEqual(16#FF, Machine5#machine_state.cpu#cpu_state.b),
    ?assertEqual(16, z80_cpu:t_states(Machine5)).

ed_otir_test() ->
    Machine0 = z80_emulator:init(),
    Machine1 = z80_emulator:write_byte(Machine0, 0, 16#ED),
    Machine2 = z80_emulator:write_byte(Machine1, 1, 16#B3),
    Machine3 = z80_emulator:write_byte(Machine2, 16#4000, 16#11),
    Machine4 = z80_emulator:write_byte(Machine3, 16#4001, 16#22),
    Cpu1 = Machine4#machine_state.cpu#cpu_state{b = 16#02, c = 16#10, h = 16#40, l = 16#00},
    Machine5 = Machine4#machine_state{cpu = Cpu1},
    Machine6 = z80_cpu:step(Machine5),
    ?assertEqual(16#4001, z80_cpu_helpers:get_reg_pair(hl, Machine6#machine_state.cpu)),
    ?assertEqual(16#01, Machine6#machine_state.cpu#cpu_state.b),
    ?assertEqual(21, z80_cpu:t_states(Machine6)).