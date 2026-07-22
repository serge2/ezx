-module(z80_cpu_main_arith_tests).

-include("z80_records.hrl").
-include_lib("eunit/include/eunit.hrl").

%% --- 8-bit Arithmetic Tests ---

%% ADD A, r / n / (HL)

add_a_b_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{a = 16#10, b = 16#20},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#80),  %% ADD A,B
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(16#30, Cpu3#cpu_state.a),
    ?assertEqual(0, Cpu3#cpu_state.f band ?FLAG_C).

add_a_c_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{a = 16#10, c = 16#20},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#81),  %% ADD A,C
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(16#30, Cpu3#cpu_state.a).

add_a_d_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{a = 16#10, d = 16#20},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#82),  %% ADD A,D
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(16#30, Cpu3#cpu_state.a).

add_a_e_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{a = 16#10, e = 16#20},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#83),  %% ADD A,E
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(16#30, Cpu3#cpu_state.a).

add_a_h_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{a = 16#10, h = 16#20},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#84),  %% ADD A,H
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(16#30, Cpu3#cpu_state.a).

add_a_l_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{a = 16#10, l = 16#20},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#85),  %% ADD A,L
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(16#30, Cpu3#cpu_state.a).

add_a_a_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{a = 16#40},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#87),  %% ADD A,A
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(16#80, Cpu3#cpu_state.a),
    ?assertEqual(0, Cpu3#cpu_state.f band ?FLAG_C).

add_a_n_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{a = 16#10},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#C6),  %% ADD A,n
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#20),
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#30, Cpu4#cpu_state.a),
    ?assertEqual(2, z80_cpu:pc(Cpu4)).

add_a_mem_hl_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#20),
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#86),  %% ADD A,(HL)
    Cpu3 = Cpu2#cpu_state{a = 16#10, h = 16#40, l = 16#00},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#30, Cpu4#cpu_state.a).

add_a_mem_hl_carry_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#01),
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#86),  %% ADD A,(HL)
    Cpu3 = Cpu2#cpu_state{a = 16#FF, h = 16#40, l = 16#00},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#00, Cpu4#cpu_state.a),
    ?assertEqual(?FLAG_C, Cpu4#cpu_state.f band ?FLAG_C),
    ?assertEqual(?FLAG_Z, Cpu4#cpu_state.f band ?FLAG_Z).

add_a_mem_hl_half_carry_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#01),
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#86),  %% ADD A,(HL)
    Cpu3 = Cpu2#cpu_state{a = 16#0F, h = 16#40, l = 16#00},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#10, Cpu4#cpu_state.a),
    ?assertEqual(?FLAG_H, Cpu4#cpu_state.f band ?FLAG_H).

%% ADC A, r / n / (HL)

adc_a_b_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{a = 16#10, b = 16#20, f = ?FLAG_C},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#88),  %% ADC A,B
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(16#31, Cpu3#cpu_state.a).

adc_a_n_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{a = 16#10, f = ?FLAG_C},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#CE),  %% ADC A,n
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#20),
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#31, Cpu4#cpu_state.a).

adc_a_mem_hl_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#20),
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#8E),  %% ADC A,(HL)
    Cpu3 = Cpu2#cpu_state{a = 16#10, f = ?FLAG_C, h = 16#40, l = 16#00},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#31, Cpu4#cpu_state.a).

%% SUB r / n / (HL)

sub_b_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{a = 16#30, b = 16#10},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#90),  %% SUB B
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(16#20, Cpu3#cpu_state.a),
    ?assertEqual(?FLAG_N, Cpu3#cpu_state.f band ?FLAG_N).

sub_a_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{a = 16#30},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#97),  %% SUB A
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(16#00, Cpu3#cpu_state.a),
    ?assertEqual(?FLAG_Z, Cpu3#cpu_state.f band ?FLAG_Z).

sub_n_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{a = 16#30},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#D6),  %% SUB n
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#10),
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#20, Cpu4#cpu_state.a).

sub_mem_hl_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#10),
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#96),  %% SUB (HL)
    Cpu3 = Cpu2#cpu_state{a = 16#30, h = 16#40, l = 16#00},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#20, Cpu4#cpu_state.a).

sub_mem_hl_borrow_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#01),
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#96),  %% SUB (HL)
    Cpu3 = Cpu2#cpu_state{a = 16#00, h = 16#40, l = 16#00},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#FF, Cpu4#cpu_state.a),
    ?assertEqual(?FLAG_C, Cpu4#cpu_state.f band ?FLAG_C).

%% SBC A, r / n / (HL)

sbc_a_b_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{a = 16#30, b = 16#10, f = ?FLAG_C},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#98),  %% SBC A,B
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(16#1F, Cpu3#cpu_state.a).

sbc_a_n_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{a = 16#30, f = ?FLAG_C},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#DE),  %% SBC A,n
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#10),
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#1F, Cpu4#cpu_state.a).

sbc_a_mem_hl_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#10),
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#9E),  %% SBC A,(HL)
    Cpu3 = Cpu2#cpu_state{a = 16#30, f = ?FLAG_C, h = 16#40, l = 16#00},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#1F, Cpu4#cpu_state.a).

%% INC r / (HL) / rp

inc_b_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{b = 16#10},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#04),  %% INC B
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(16#11, Cpu3#cpu_state.b),
    ?assertEqual(0, Cpu3#cpu_state.f band ?FLAG_N).

inc_c_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{c = 16#10},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#0C),  %% INC C
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(16#11, Cpu3#cpu_state.c).

inc_a_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{a = 16#10},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#3C),  %% INC A
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(16#11, Cpu3#cpu_state.a).

inc_mem_hl_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#10),
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#34),  %% INC (HL)
    Cpu3 = Cpu2#cpu_state{h = 16#40, l = 16#00},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#11, test_helpers:read_mem(Cpu4, 16#4000)).

inc_mem_hl_zero_flag_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#FF),
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#34),  %% INC (HL)
    Cpu3 = Cpu2#cpu_state{h = 16#40, l = 16#00},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#00, test_helpers:read_mem(Cpu4, 16#4000)),
    ?assertEqual(?FLAG_Z, Cpu4#cpu_state.f band ?FLAG_Z).

inc_bc_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{b = 16#12, c = 16#34},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#03),  %% INC BC
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(16#1235, z80_cpu:get_reg_pair(bc, Cpu3)).

inc_de_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{d = 16#12, e = 16#34},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#13),  %% INC DE
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(16#1235, z80_cpu:get_reg_pair(de, Cpu3)).

inc_hl_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{h = 16#12, l = 16#34},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#23),  %% INC HL
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(16#1235, z80_cpu:get_reg_pair(hl, Cpu3)).

inc_sp_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{sp = 16#1234},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#33),  %% INC SP
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(16#1235, Cpu3#cpu_state.sp).

%% DEC r / (HL) / rp

dec_b_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{b = 16#10},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#05),  %% DEC B
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(16#0F, Cpu3#cpu_state.b),
    ?assertEqual(?FLAG_N, Cpu3#cpu_state.f band ?FLAG_N).

dec_a_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{a = 16#10},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#3D),  %% DEC A
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(16#0F, Cpu3#cpu_state.a).

dec_mem_hl_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#10),
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#35),  %% DEC (HL)
    Cpu3 = Cpu2#cpu_state{h = 16#40, l = 16#00},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#0F, test_helpers:read_mem(Cpu4, 16#4000)).

dec_mem_hl_half_carry_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#10),
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#35),  %% DEC (HL)
    Cpu3 = Cpu2#cpu_state{h = 16#40, l = 16#00},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(?FLAG_H, Cpu4#cpu_state.f band ?FLAG_H).

dec_bc_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{b = 16#12, c = 16#35},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#0B),  %% DEC BC
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(16#1234, z80_cpu:get_reg_pair(bc, Cpu3)).

dec_de_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{d = 16#12, e = 16#35},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#1B),  %% DEC DE
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(16#1234, z80_cpu:get_reg_pair(de, Cpu3)).

dec_hl_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{h = 16#12, l = 16#35},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#2B),  %% DEC HL
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(16#1234, z80_cpu:get_reg_pair(hl, Cpu3)).

dec_sp_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{sp = 16#1235},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#3B),  %% DEC SP
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(16#1234, Cpu3#cpu_state.sp).

%% ADD HL, rp

add_hl_bc_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{h = 16#10, l = 16#00, b = 16#20, c = 16#00},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#09),  %% ADD HL,BC
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(16#30, Cpu3#cpu_state.h),
    ?assertEqual(16#00, Cpu3#cpu_state.l).

add_hl_de_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{h = 16#10, l = 16#00, d = 16#20, e = 16#00},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#19),  %% ADD HL,DE
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(16#30, Cpu3#cpu_state.h).

add_hl_hl_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{h = 16#20, l = 16#00},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#29),  %% ADD HL,HL
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(16#40, Cpu3#cpu_state.h).

add_hl_sp_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{h = 16#10, l = 16#00, sp = 16#2000},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#39),  %% ADD HL,SP
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(16#30, Cpu3#cpu_state.h).

add_hl_carry_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{h = 16#FF, l = 16#FF, b = 16#00, c = 16#01},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#09),  %% ADD HL,BC
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(16#00, Cpu3#cpu_state.h),
    ?assertEqual(16#00, Cpu3#cpu_state.l),
    ?assertEqual(?FLAG_C, Cpu3#cpu_state.f band ?FLAG_C).

add_hl_half_carry_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{h = 16#0F, l = 16#FF, b = 16#00, c = 16#01},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#09),  %% ADD HL,BC
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(?FLAG_H, Cpu3#cpu_state.f band ?FLAG_H).

%% --- ADD HL,rr F3/F5 from high byte of result ---

add_hl_bc_f3f5_test() ->
    %% ADD HL,BC: HL=0x1000, BC=0x0028 -> Res=0x1028
    %% ResHi = 0x10 -> F3=0, F5=0
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{h = 16#10, l = 16#00, b = 16#00, c = 16#28},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#09),
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(16#1028, z80_cpu:get_reg_pair(hl, Cpu3)),
    ?assertEqual(0, Cpu3#cpu_state.f band 16#28).

add_hl_de_f3f5_both_test() ->
    %% ADD HL,DE: HL=0x2800, DE=0x0028 -> Res=0x2828
    %% ResHi = 0x28 -> F3=1, F5=1
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{h = 16#28, l = 16#00, d = 16#00, e = 16#28},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#19),
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(16#2828, z80_cpu:get_reg_pair(hl, Cpu3)),
    ?assertEqual(16#28, Cpu3#cpu_state.f band 16#28).

add_hl_hl_f3f5_test() ->
    %% ADD HL,HL: HL=0x1400 -> Res=0x2800
    %% ResHi = 0x28 -> F3=1, F5=1 (0x28 & 0x28 = 0x28)
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{h = 16#14, l = 16#00},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#29),
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(16#2800, z80_cpu:get_reg_pair(hl, Cpu3)),
    ?assertEqual(16#28, Cpu3#cpu_state.f band 16#28).

add_hl_sp_f3f5_test() ->
    %% ADD HL,SP: HL=0x0000, SP=0x2800 -> Res=0x2800
    %% ResHi = 0x28 -> F3=1, F5=1 (0x28 & 0x28 = 0x28)
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{h = 16#00, l = 16#00, sp = 16#2800},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#39),
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(16#2800, z80_cpu:get_reg_pair(hl, Cpu3)),
    ?assertEqual(16#28, Cpu3#cpu_state.f band 16#28).

%% ADD HL,rr: N=0, H=0 when no half carry
add_hl_bc_no_h_n_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{h = 16#10, l = 16#00, b = 16#20, c = 16#00},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#09),
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(0, Cpu3#cpu_state.f band (?FLAG_H bor ?FLAG_N)).
