-module(z80_cpu_main_arith_tests).

-include("z80_records.hrl").
-include_lib("eunit/include/eunit.hrl").

%% --- 8-bit Arithmetic Tests ---

%% ADD A, r / n / (HL)

add_a_b_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{a = 16#10, b = 16#20},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#80),  %% ADD A,B
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#30, Machine2#machine_state.cpu#cpu_state.a),
    ?assertEqual(0, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_C).

add_a_c_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{a = 16#10, c = 16#20},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#81),  %% ADD A,C
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#30, Machine2#machine_state.cpu#cpu_state.a).

add_a_d_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{a = 16#10, d = 16#20},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#82),  %% ADD A,D
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#30, Machine2#machine_state.cpu#cpu_state.a).

add_a_e_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{a = 16#10, e = 16#20},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#83),  %% ADD A,E
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#30, Machine2#machine_state.cpu#cpu_state.a).

add_a_h_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{a = 16#10, h = 16#20},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#84),  %% ADD A,H
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#30, Machine2#machine_state.cpu#cpu_state.a).

add_a_l_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{a = 16#10, l = 16#20},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#85),  %% ADD A,L
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#30, Machine2#machine_state.cpu#cpu_state.a).

add_a_a_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{a = 16#40},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#87),  %% ADD A,A
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#80, Machine2#machine_state.cpu#cpu_state.a),
    ?assertEqual(0, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_C).

add_a_n_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{a = 16#10},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#C6),  %% ADD A,n
    Mem2 = z80_mem:write_byte(Mem1, 1, 16#20),
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem2},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#30, Machine2#machine_state.cpu#cpu_state.a),
    ?assertEqual(2, z80_cpu:pc(Machine2)).

add_a_mem_hl_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{a = 16#10, h = 16#40, l = 16#00},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 16#4000, 16#20),
    Mem2 = z80_mem:write_byte(Mem1, 0, 16#86),  %% ADD A,(HL)
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem2},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#30, Machine2#machine_state.cpu#cpu_state.a).

add_a_mem_hl_carry_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{a = 16#FF, h = 16#40, l = 16#00},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 16#4000, 16#01),
    Mem2 = z80_mem:write_byte(Mem1, 0, 16#86),  %% ADD A,(HL)
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem2},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#00, Machine2#machine_state.cpu#cpu_state.a),
    ?assertEqual(?FLAG_C, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_C),
    ?assertEqual(?FLAG_Z, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_Z).

add_a_mem_hl_half_carry_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{a = 16#0F, h = 16#40, l = 16#00},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 16#4000, 16#01),
    Mem2 = z80_mem:write_byte(Mem1, 0, 16#86),  %% ADD A,(HL)
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem2},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#10, Machine2#machine_state.cpu#cpu_state.a),
    ?assertEqual(?FLAG_H, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_H).

%% ADC A, r / n / (HL)

adc_a_b_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{a = 16#10, b = 16#20, f = ?FLAG_C},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#88),  %% ADC A,B
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#31, Machine2#machine_state.cpu#cpu_state.a).

adc_a_n_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{a = 16#10, f = ?FLAG_C},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#CE),  %% ADC A,n
    Mem2 = z80_mem:write_byte(Mem1, 1, 16#20),
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem2},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#31, Machine2#machine_state.cpu#cpu_state.a).

adc_a_mem_hl_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{a = 16#10, f = ?FLAG_C, h = 16#40, l = 16#00},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 16#4000, 16#20),
    Mem2 = z80_mem:write_byte(Mem1, 0, 16#8E),  %% ADC A,(HL)
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem2},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#31, Machine2#machine_state.cpu#cpu_state.a).

%% SUB r / n / (HL)

sub_b_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{a = 16#30, b = 16#10},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#90),  %% SUB B
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#20, Machine2#machine_state.cpu#cpu_state.a),
    ?assertEqual(?FLAG_N, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_N).

sub_a_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{a = 16#30},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#97),  %% SUB A
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#00, Machine2#machine_state.cpu#cpu_state.a),
    ?assertEqual(?FLAG_Z, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_Z).

sub_n_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{a = 16#30},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#D6),  %% SUB n
    Mem2 = z80_mem:write_byte(Mem1, 1, 16#10),
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem2},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#20, Machine2#machine_state.cpu#cpu_state.a).

sub_mem_hl_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{a = 16#30, h = 16#40, l = 16#00},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 16#4000, 16#10),
    Mem2 = z80_mem:write_byte(Mem1, 0, 16#96),  %% SUB (HL)
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem2},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#20, Machine2#machine_state.cpu#cpu_state.a).

sub_mem_hl_borrow_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{a = 16#00, h = 16#40, l = 16#00},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 16#4000, 16#01),
    Mem2 = z80_mem:write_byte(Mem1, 0, 16#96),  %% SUB (HL)
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem2},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#FF, Machine2#machine_state.cpu#cpu_state.a),
    ?assertEqual(?FLAG_C, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_C).

%% SBC A, r / n / (HL)

sbc_a_b_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{a = 16#30, b = 16#10, f = ?FLAG_C},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#98),  %% SBC A,B
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#1F, Machine2#machine_state.cpu#cpu_state.a).

sbc_a_n_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{a = 16#30, f = ?FLAG_C},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#DE),  %% SBC A,n
    Mem2 = z80_mem:write_byte(Mem1, 1, 16#10),
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem2},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#1F, Machine2#machine_state.cpu#cpu_state.a).

sbc_a_mem_hl_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{a = 16#30, f = ?FLAG_C, h = 16#40, l = 16#00},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 16#4000, 16#10),
    Mem2 = z80_mem:write_byte(Mem1, 0, 16#9E),  %% SBC A,(HL)
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem2},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#1F, Machine2#machine_state.cpu#cpu_state.a).

%% INC r / (HL) / rp

inc_b_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{b = 16#10},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#04),  %% INC B
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#11, Machine2#machine_state.cpu#cpu_state.b),
    ?assertEqual(0, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_N).

inc_c_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{c = 16#10},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#0C),  %% INC C
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#11, Machine2#machine_state.cpu#cpu_state.c).

inc_a_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{a = 16#10},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#3C),  %% INC A
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#11, Machine2#machine_state.cpu#cpu_state.a).

inc_mem_hl_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{h = 16#40, l = 16#00},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 16#4000, 16#10),
    Mem2 = z80_mem:write_byte(Mem1, 0, 16#34),  %% INC (HL)
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem2},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#11, z80_emulator:read_byte(Machine2, 16#4000)).

inc_mem_hl_zero_flag_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{h = 16#40, l = 16#00},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 16#4000, 16#FF),
    Mem2 = z80_mem:write_byte(Mem1, 0, 16#34),  %% INC (HL)
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem2},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#00, z80_emulator:read_byte(Machine2, 16#4000)),
    ?assertEqual(?FLAG_Z, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_Z).

inc_bc_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{b = 16#12, c = 16#34},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#03),  %% INC BC
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#1235, z80_cpu:get_reg_pair(bc, Machine2#machine_state.cpu)).

inc_de_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{d = 16#12, e = 16#34},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#13),  %% INC DE
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#1235, z80_cpu:get_reg_pair(de, Machine2#machine_state.cpu)).

inc_hl_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{h = 16#12, l = 16#34},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#23),  %% INC HL
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#1235, z80_cpu:get_reg_pair(hl, Machine2#machine_state.cpu)).

inc_sp_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{sp = 16#1234},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#33),  %% INC SP
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#1235, Machine2#machine_state.cpu#cpu_state.sp).

%% DEC r / (HL) / rp

dec_b_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{b = 16#10},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#05),  %% DEC B
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#0F, Machine2#machine_state.cpu#cpu_state.b),
    ?assertEqual(?FLAG_N, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_N).

dec_a_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{a = 16#10},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#3D),  %% DEC A
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#0F, Machine2#machine_state.cpu#cpu_state.a).

dec_mem_hl_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{h = 16#40, l = 16#00},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 16#4000, 16#10),
    Mem2 = z80_mem:write_byte(Mem1, 0, 16#35),  %% DEC (HL)
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem2},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#0F, z80_emulator:read_byte(Machine2, 16#4000)).

dec_mem_hl_half_carry_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{h = 16#40, l = 16#00},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 16#4000, 16#10),
    Mem2 = z80_mem:write_byte(Mem1, 0, 16#35),  %% DEC (HL)
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem2},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(?FLAG_H, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_H).

dec_bc_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{b = 16#12, c = 16#35},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#0B),  %% DEC BC
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#1234, z80_cpu:get_reg_pair(bc, Machine2#machine_state.cpu)).

dec_de_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{d = 16#12, e = 16#35},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#1B),  %% DEC DE
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#1234, z80_cpu:get_reg_pair(de, Machine2#machine_state.cpu)).

dec_hl_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{h = 16#12, l = 16#35},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#2B),  %% DEC HL
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#1234, z80_cpu:get_reg_pair(hl, Machine2#machine_state.cpu)).

dec_sp_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{sp = 16#1235},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#3B),  %% DEC SP
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#1234, Machine2#machine_state.cpu#cpu_state.sp).

%% ADD HL, rp

add_hl_bc_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{h = 16#10, l = 16#00, b = 16#20, c = 16#00},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#09),  %% ADD HL,BC
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#30, Machine2#machine_state.cpu#cpu_state.h),
    ?assertEqual(16#00, Machine2#machine_state.cpu#cpu_state.l).

add_hl_de_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{h = 16#10, l = 16#00, d = 16#20, e = 16#00},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#19),  %% ADD HL,DE
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#30, Machine2#machine_state.cpu#cpu_state.h).

add_hl_hl_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{h = 16#20, l = 16#00},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#29),  %% ADD HL,HL
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#40, Machine2#machine_state.cpu#cpu_state.h).

add_hl_sp_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{h = 16#10, l = 16#00, sp = 16#2000},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#39),  %% ADD HL,SP
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#30, Machine2#machine_state.cpu#cpu_state.h).

add_hl_carry_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{h = 16#FF, l = 16#FF, b = 16#00, c = 16#01},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#09),  %% ADD HL,BC
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#00, Machine2#machine_state.cpu#cpu_state.h),
    ?assertEqual(16#00, Machine2#machine_state.cpu#cpu_state.l),
    ?assertEqual(?FLAG_C, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_C).

add_hl_half_carry_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{h = 16#0F, l = 16#FF, b = 16#00, c = 16#01},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#09),  %% ADD HL,BC
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(?FLAG_H, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_H).