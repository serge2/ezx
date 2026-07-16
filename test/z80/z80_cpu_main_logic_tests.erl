-module(z80_cpu_main_logic_tests).

-include("z80_records.hrl").
-include_lib("eunit/include/eunit.hrl").

%% --- 8-bit Logic Tests ---

%% AND r / n / (HL)

and_b_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{a = 16#FF, b = 16#0F},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#A0),  %% AND B
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#0F, Machine2#machine_state.cpu#cpu_state.a),
    ?assertEqual(?FLAG_H, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_H).

and_a_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{a = 16#55},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#A7),  %% AND A
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#55, Machine2#machine_state.cpu#cpu_state.a).

and_n_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{a = 16#FF},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#E6),  %% AND n
    Mem2 = z80_mem:write_byte(Mem1, 1, 16#0F),
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem2},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#0F, Machine2#machine_state.cpu#cpu_state.a),
    ?assertEqual(2, z80_cpu:pc(Machine2)).

and_mem_hl_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{a = 16#FF, h = 16#40, l = 16#00},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 16#4000, 16#0F),
    Mem2 = z80_mem:write_byte(Mem1, 0, 16#A6),  %% AND (HL)
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem2},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#0F, Machine2#machine_state.cpu#cpu_state.a).

and_zero_flag_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{a = 16#0F},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#E6),  %% AND n
    Mem2 = z80_mem:write_byte(Mem1, 1, 16#F0),
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem2},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#00, Machine2#machine_state.cpu#cpu_state.a),
    ?assertEqual(?FLAG_Z, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_Z).

and_sign_flag_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{a = 16#FF},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#E6),  %% AND n
    Mem2 = z80_mem:write_byte(Mem1, 1, 16#80),
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem2},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#80, Machine2#machine_state.cpu#cpu_state.a),
    ?assertEqual(?FLAG_S, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_S).

and_parity_flag_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{a = 16#FF},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#E6),  %% AND n
    Mem2 = z80_mem:write_byte(Mem1, 1, 16#55),  %% 0x55 has even parity (4 bits set)
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem2},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#55, Machine2#machine_state.cpu#cpu_state.a),
    ?assertEqual(?FLAG_V, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_V).

%% OR r / n / (HL)

or_b_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{a = 16#0F, b = 16#F0},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#B0),  %% OR B
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#FF, Machine2#machine_state.cpu#cpu_state.a),
    ?assertEqual(0, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_H).

or_n_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{a = 16#0F},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#F6),  %% OR n
    Mem2 = z80_mem:write_byte(Mem1, 1, 16#F0),
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem2},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#FF, Machine2#machine_state.cpu#cpu_state.a).

or_mem_hl_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{a = 16#0F, h = 16#40, l = 16#00},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 16#4000, 16#F0),
    Mem2 = z80_mem:write_byte(Mem1, 0, 16#B6),  %% OR (HL)
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem2},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#FF, Machine2#machine_state.cpu#cpu_state.a).

or_zero_flag_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{a = 16#00},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#F6),  %% OR n
    Mem2 = z80_mem:write_byte(Mem1, 1, 16#00),
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem2},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#00, Machine2#machine_state.cpu#cpu_state.a),
    ?assertEqual(?FLAG_Z, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_Z).

%% XOR r / n / (HL)

xor_b_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{a = 16#55, b = 16#AA},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#A8),  %% XOR B
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#FF, Machine2#machine_state.cpu#cpu_state.a),
    ?assertEqual(0, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_H).

xor_a_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{a = 16#55},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#AF),  %% XOR A
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#00, Machine2#machine_state.cpu#cpu_state.a),
    ?assertEqual(?FLAG_Z, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_Z).

xor_n_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{a = 16#55},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#EE),  %% XOR n
    Mem2 = z80_mem:write_byte(Mem1, 1, 16#AA),
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem2},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#FF, Machine2#machine_state.cpu#cpu_state.a).

xor_mem_hl_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{a = 16#55, h = 16#40, l = 16#00},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 16#4000, 16#AA),
    Mem2 = z80_mem:write_byte(Mem1, 0, 16#AE),  %% XOR (HL)
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem2},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#FF, Machine2#machine_state.cpu#cpu_state.a).

%% CP r / n / (HL)

cp_b_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{a = 16#30, b = 16#10},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#B8),  %% CP B
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#30, Machine2#machine_state.cpu#cpu_state.a),
    ?assertEqual(?FLAG_N, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_N),
    ?assertEqual(0, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_Z).

cp_a_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{a = 16#55},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#BF),  %% CP A
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#55, Machine2#machine_state.cpu#cpu_state.a),
    ?assertEqual(?FLAG_Z, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_Z).

cp_n_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{a = 16#30},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#FE),  %% CP n
    Mem2 = z80_mem:write_byte(Mem1, 1, 16#10),
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem2},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#30, Machine2#machine_state.cpu#cpu_state.a),
    ?assertEqual(0, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_Z).

cp_mem_hl_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{a = 16#30, h = 16#40, l = 16#00},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 16#4000, 16#10),
    Mem2 = z80_mem:write_byte(Mem1, 0, 16#BE),  %% CP (HL)
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem2},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#30, Machine2#machine_state.cpu#cpu_state.a).

cp_carry_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{a = 16#10, b = 16#20},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#B8),  %% CP B (A < B -> carry)
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(?FLAG_C, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_C).

cp_no_carry_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{a = 16#30, b = 16#10},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#B8),  %% CP B (A > B -> no carry)
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(0, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_C).

cp_half_carry_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{a = 16#10, b = 16#01},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#B8),  %% CP B
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Machine2 = z80_cpu:step(Machine1),
    %% 0x10 - 0x01 = 0x0F: borrow from bit 4 (0x10 & 0x0F = 0, 0x01 & 0x0F = 1, 0 < 1)
    ?assertEqual(?FLAG_H, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_H).