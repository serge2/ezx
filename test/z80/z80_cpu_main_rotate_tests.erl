-module(z80_cpu_main_rotate_tests).

-include("z80_records.hrl").
-include_lib("eunit/include/eunit.hrl").

%% --- Rotate/Shift Tests (A register) ---

%% RLCA

rlca_test() ->
    Machine0 = ezx_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{a = 16#80},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#07),  %% RLCA
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#01, Machine2#machine_state.cpu#cpu_state.a),
    ?assertEqual(?FLAG_C, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_C).

rlca_no_carry_test() ->
    Machine0 = ezx_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{a = 16#40},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#07),  %% RLCA
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#80, Machine2#machine_state.cpu#cpu_state.a),
    ?assertEqual(0, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_C).

%% RRCA

rrca_test() ->
    Machine0 = ezx_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{a = 16#01},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#0F),  %% RRCA
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#80, Machine2#machine_state.cpu#cpu_state.a),
    ?assertEqual(?FLAG_C, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_C).

rrca_no_carry_test() ->
    Machine0 = ezx_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{a = 16#02},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#0F),  %% RRCA
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#01, Machine2#machine_state.cpu#cpu_state.a),
    ?assertEqual(0, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_C).

%% RLA

rla_test() ->
    Machine0 = ezx_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{a = 16#80, f = ?FLAG_C},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#17),  %% RLA
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#01, Machine2#machine_state.cpu#cpu_state.a),
    ?assertEqual(?FLAG_C, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_C).

rla_no_carry_test() ->
    Machine0 = ezx_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{a = 16#40, f = 0},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#17),  %% RLA
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#80, Machine2#machine_state.cpu#cpu_state.a),
    ?assertEqual(0, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_C).

%% RRA

rra_test() ->
    Machine0 = ezx_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{a = 16#01, f = ?FLAG_C},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#1F),  %% RRA
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#80, Machine2#machine_state.cpu#cpu_state.a),
    ?assertEqual(?FLAG_C, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_C).

rra_no_carry_test() ->
    Machine0 = ezx_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{a = 16#02, f = 0},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#1F),  %% RRA
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#01, Machine2#machine_state.cpu#cpu_state.a),
    ?assertEqual(0, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_C).

%% --- CPL, SCF, CCF Tests ---

cpl_test() ->
    Machine0 = ezx_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{a = 16#55},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#2F),  %% CPL
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#AA, Machine2#machine_state.cpu#cpu_state.a),
    ?assertEqual(?FLAG_H, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_H),
    ?assertEqual(?FLAG_N, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_N).

scf_test() ->
    Machine0 = ezx_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{f = 0},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#37),  %% SCF
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(?FLAG_C, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_C),
    ?assertEqual(0, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_N).

ccf_test() ->
    Machine0 = ezx_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{f = 0},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#3F),  %% CCF
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(?FLAG_C, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_C).

ccf_carry_to_no_carry_test() ->
    Machine0 = ezx_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{f = ?FLAG_C},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#3F),  %% CCF
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(0, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_C).

%% --- DAA Tests ---

daa_after_add_test() ->
    Machine0 = ezx_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{a = 16#15},
    Machine1 = Machine0#machine_state{cpu = Cpu0},
    Machine2 = ezx_emulator:write_byte(Machine1, 0, 16#C6),  %% ADD A,n
    Machine3 = ezx_emulator:write_byte(Machine2, 1, 16#27),
    Machine4 = ezx_emulator:write_byte(Machine3, 2, 16#27),  %% DAA
    Machine5 = z80_cpu:step(Machine4),
    Machine6 = z80_cpu:step(Machine5),
    ?assertEqual(16#42, Machine6#machine_state.cpu#cpu_state.a),
    ?assertEqual(0, Machine6#machine_state.cpu#cpu_state.f band 16#40).

daa_after_sub_test() ->
    Machine0 = ezx_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{a = 16#52},
    Machine1 = Machine0#machine_state{cpu = Cpu0},
    Machine2 = ezx_emulator:write_byte(Machine1, 0, 16#D6),  %% SUB n
    Machine3 = ezx_emulator:write_byte(Machine2, 1, 16#37),
    Machine4 = ezx_emulator:write_byte(Machine3, 2, 16#27),  %% DAA
    Machine5 = z80_cpu:step(Machine4),
    Machine6 = z80_cpu:step(Machine5),
    ?assertEqual(16#15, Machine6#machine_state.cpu#cpu_state.a).

daa_carry_test() ->
    Machine0 = ezx_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{a = 16#99},
    Machine1 = Machine0#machine_state{cpu = Cpu0},
    Machine2 = ezx_emulator:write_byte(Machine1, 0, 16#C6),  %% ADD A,n
    Machine3 = ezx_emulator:write_byte(Machine2, 1, 16#01),
    Machine4 = ezx_emulator:write_byte(Machine3, 2, 16#27),  %% DAA
    Machine5 = z80_cpu:step(Machine4),
    Machine6 = z80_cpu:step(Machine5),
    ?assertEqual(16#00, Machine6#machine_state.cpu#cpu_state.a),
    ?assertEqual(?FLAG_C, Machine6#machine_state.cpu#cpu_state.f band ?FLAG_C),
    ?assertEqual(?FLAG_Z, Machine6#machine_state.cpu#cpu_state.f band ?FLAG_Z).

daa_no_carry_test() ->
    Machine0 = ezx_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{a = 16#19},
    Machine1 = Machine0#machine_state{cpu = Cpu0},
    Machine2 = ezx_emulator:write_byte(Machine1, 0, 16#C6),  %% ADD A,n
    Machine3 = ezx_emulator:write_byte(Machine2, 1, 16#27),
    Machine4 = ezx_emulator:write_byte(Machine3, 2, 16#27),  %% DAA
    Machine5 = z80_cpu:step(Machine4),
    Machine6 = z80_cpu:step(Machine5),
    ?assertEqual(16#46, Machine6#machine_state.cpu#cpu_state.a),
    ?assertEqual(0, Machine6#machine_state.cpu#cpu_state.f band ?FLAG_C).

daa_half_carry_test() ->
    Machine0 = ezx_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{a = 16#09},
    Machine1 = Machine0#machine_state{cpu = Cpu0},
    Machine2 = ezx_emulator:write_byte(Machine1, 0, 16#C6),  %% ADD A,n
    Machine3 = ezx_emulator:write_byte(Machine2, 1, 16#09),
    Machine4 = ezx_emulator:write_byte(Machine3, 2, 16#27),  %% DAA
    Machine5 = z80_cpu:step(Machine4),
    Machine6 = z80_cpu:step(Machine5),
    ?assertEqual(16#18, Machine6#machine_state.cpu#cpu_state.a),
    %% DAA half-carry: 0x12 + 0x06 = 0x18, no half-carry (2+6=8 < 16)
    ?assertEqual(0, Machine6#machine_state.cpu#cpu_state.f band ?FLAG_H).