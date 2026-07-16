-module(z80_cpu_main_ld_tests).

-include("z80_records.hrl").
-include_lib("eunit/include/eunit.hrl").

%% --- 16-bit LD Tests ---

ld_bc_nn_test() ->
    Machine0 = z80_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#01),
    Mem2 = z80_mem:write_byte(Mem1, 1, 16#34),
    Mem3 = z80_mem:write_byte(Mem2, 2, 16#12),
    Machine1 = Machine0#machine_state{memory = Mem3},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#1234, z80_cpu:get_reg_pair(bc, Machine2#machine_state.cpu)),
    ?assertEqual(3, z80_cpu:pc(Machine2)).

ld_bc_nn_timing_test() ->
    Machine0 = z80_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#01),
    Mem2 = z80_mem:write_byte(Mem1, 1, 16#34),
    Mem3 = z80_mem:write_byte(Mem2, 2, 16#12),
    Machine1 = Machine0#machine_state{memory = Mem3},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(10, z80_cpu:t_states(Machine2)).

ld_de_nn_test() ->
    Machine0 = z80_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#11),
    Mem2 = z80_mem:write_byte(Mem1, 1, 16#56),
    Mem3 = z80_mem:write_byte(Mem2, 2, 16#78),
    Machine1 = Machine0#machine_state{memory = Mem3},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#7856, z80_cpu:get_reg_pair(de, Machine2#machine_state.cpu)),
    ?assertEqual(3, z80_cpu:pc(Machine2)).

ld_hl_nn_test() ->
    Machine0 = z80_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#21),
    Mem2 = z80_mem:write_byte(Mem1, 1, 16#34),
    Mem3 = z80_mem:write_byte(Mem2, 2, 16#12),
    Machine1 = Machine0#machine_state{memory = Mem3},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#1234, z80_cpu:get_reg_pair(hl, Machine2#machine_state.cpu)),
    ?assertEqual(3, z80_cpu:pc(Machine2)).

ld_sp_nn_test() ->
    Machine0 = z80_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#31),
    Mem2 = z80_mem:write_byte(Mem1, 1, 16#00),
    Mem3 = z80_mem:write_byte(Mem2, 2, 16#80),
    Machine1 = Machine0#machine_state{memory = Mem3},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#8000, z80_cpu:get_reg_pair(sp, Machine2#machine_state.cpu)),
    ?assertEqual(3, z80_cpu:pc(Machine2)).

%% --- 8-bit LD r,r Tests ---

ld_b_c_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{c = 16#42},
    Machine1 = Machine0#machine_state{cpu = Cpu0},
    Mem0 = Machine1#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#41),  %% LD B,C
    Machine2 = Machine1#machine_state{memory = Mem1},
    Machine3 = z80_cpu:step(Machine2),
    ?assertEqual(16#42, Machine3#machine_state.cpu#cpu_state.b),
    ?assertEqual(1, z80_cpu:pc(Machine3)).

ld_a_b_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{b = 16#55},
    Machine1 = Machine0#machine_state{cpu = Cpu0},
    Mem0 = Machine1#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#78),  %% LD A,B
    Machine2 = Machine1#machine_state{memory = Mem1},
    Machine3 = z80_cpu:step(Machine2),
    ?assertEqual(16#55, Machine3#machine_state.cpu#cpu_state.a).

ld_a_a_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{a = 16#AA},
    Machine1 = Machine0#machine_state{cpu = Cpu0},
    Mem0 = Machine1#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#7F),  %% LD A,A
    Machine2 = Machine1#machine_state{memory = Mem1},
    Machine3 = z80_cpu:step(Machine2),
    ?assertEqual(16#AA, Machine3#machine_state.cpu#cpu_state.a).

%% --- LD r,n Tests ---

ld_b_n_test() ->
    Machine0 = z80_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#06),  %% LD B,n
    Mem2 = z80_mem:write_byte(Mem1, 1, 16#42),
    Machine1 = Machine0#machine_state{memory = Mem2},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#42, Machine2#machine_state.cpu#cpu_state.b),
    ?assertEqual(2, z80_cpu:pc(Machine2)).

ld_a_n_test() ->
    Machine0 = z80_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#3E),  %% LD A,n
    Mem2 = z80_mem:write_byte(Mem1, 1, 16#77),
    Machine1 = Machine0#machine_state{memory = Mem2},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#77, Machine2#machine_state.cpu#cpu_state.a),
    ?assertEqual(2, z80_cpu:pc(Machine2)).

%% --- LD r,(HL) Tests ---

ld_b_mem_hl_test() ->
    Machine0 = z80_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 16#4000, 16#55),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{h = 16#40, l = 16#00},
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Mem2 = z80_mem:write_byte(Mem1, 0, 16#46),  %% LD B,(HL)
    Machine2 = Machine1#machine_state{memory = Mem2},
    Machine3 = z80_cpu:step(Machine2),
    ?assertEqual(16#55, Machine3#machine_state.cpu#cpu_state.b),
    ?assertEqual(1, z80_cpu:pc(Machine3)).

ld_c_mem_hl_test() ->
    Machine0 = z80_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 16#4000, 16#AA),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{h = 16#40, l = 16#00},
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Mem2 = z80_mem:write_byte(Mem1, 0, 16#4E),  %% LD C,(HL)
    Machine2 = Machine1#machine_state{memory = Mem2},
    Machine3 = z80_cpu:step(Machine2),
    ?assertEqual(16#AA, Machine3#machine_state.cpu#cpu_state.c).

ld_h_mem_hl_test() ->
    Machine0 = z80_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 16#4000, 16#CC),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{h = 16#40, l = 16#00},
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Mem2 = z80_mem:write_byte(Mem1, 0, 16#66),  %% LD H,(HL)
    Machine2 = Machine1#machine_state{memory = Mem2},
    Machine3 = z80_cpu:step(Machine2),
    ?assertEqual(16#CC, Machine3#machine_state.cpu#cpu_state.h).

ld_l_mem_hl_test() ->
    Machine0 = z80_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 16#4000, 16#DD),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{h = 16#40, l = 16#00},
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Mem2 = z80_mem:write_byte(Mem1, 0, 16#6E),  %% LD L,(HL)
    Machine2 = Machine1#machine_state{memory = Mem2},
    Machine3 = z80_cpu:step(Machine2),
    ?assertEqual(16#DD, Machine3#machine_state.cpu#cpu_state.l).

ld_a_mem_hl_test() ->
    Machine0 = z80_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 16#4000, 16#EE),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{h = 16#40, l = 16#00},
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Mem2 = z80_mem:write_byte(Mem1, 0, 16#7E),  %% LD A,(HL)
    Machine2 = Machine1#machine_state{memory = Mem2},
    Machine3 = z80_cpu:step(Machine2),
    ?assertEqual(16#EE, Machine3#machine_state.cpu#cpu_state.a).

%% --- LD (HL),r Tests ---

ld_mem_hl_b_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{h = 16#40, l = 16#00, b = 16#55},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#70),  %% LD (HL),B
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#55, z80_emulator:read_byte(Machine2, 16#4000)),
    ?assertEqual(1, z80_cpu:pc(Machine2)).

ld_mem_hl_a_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{h = 16#40, l = 16#00, a = 16#AA},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#77),  %% LD (HL),A
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#AA, z80_emulator:read_byte(Machine2, 16#4000)).

%% --- LD (HL),n Test ---

ld_mem_hl_n_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{h = 16#40, l = 16#00},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#36),  %% LD (HL),n
    Mem2 = z80_mem:write_byte(Mem1, 1, 16#77),
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem2},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#77, z80_emulator:read_byte(Machine2, 16#4000)),
    ?assertEqual(2, z80_cpu:pc(Machine2)).

%% --- LD (BC),A / LD (DE),A Tests ---

ld_mem_bc_a_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{b = 16#40, c = 16#00, a = 16#55},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#02),  %% LD (BC),A
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#55, z80_emulator:read_byte(Machine2, 16#4000)),
    ?assertEqual(1, z80_cpu:pc(Machine2)).

ld_mem_de_a_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{d = 16#40, e = 16#00, a = 16#AA},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#12),  %% LD (DE),A
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#AA, z80_emulator:read_byte(Machine2, 16#4000)).

%% --- LD A,(BC) / LD A,(DE) Tests ---

ld_a_mem_bc_test() ->
    Machine0 = z80_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 16#4000, 16#55),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{b = 16#40, c = 16#00},
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Mem2 = z80_mem:write_byte(Mem1, 0, 16#0A),  %% LD A,(BC)
    Machine2 = Machine1#machine_state{memory = Mem2},
    Machine3 = z80_cpu:step(Machine2),
    ?assertEqual(16#55, Machine3#machine_state.cpu#cpu_state.a),
    ?assertEqual(1, z80_cpu:pc(Machine3)).

ld_a_mem_de_test() ->
    Machine0 = z80_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 16#4000, 16#AA),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{d = 16#40, e = 16#00},
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Mem2 = z80_mem:write_byte(Mem1, 0, 16#1A),  %% LD A,(DE)
    Machine2 = Machine1#machine_state{memory = Mem2},
    Machine3 = z80_cpu:step(Machine2),
    ?assertEqual(16#AA, Machine3#machine_state.cpu#cpu_state.a).

%% --- LD (nn),HL / LD (nn),A / LD HL,(nn) / LD A,(nn) Tests ---

ld_mem_nn_hl_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{h = 16#12, l = 16#34},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#22),  %% LD (nn),HL
    Mem2 = z80_mem:write_byte(Mem1, 1, 16#00),
    Mem3 = z80_mem:write_byte(Mem2, 2, 16#80),
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem3},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#34, z80_emulator:read_byte(Machine2, 16#8000)),
    ?assertEqual(16#12, z80_emulator:read_byte(Machine2, 16#8001)),
    ?assertEqual(3, z80_cpu:pc(Machine2)).

ld_hl_mem_nn_test() ->
    Machine0 = z80_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 16#8000, 16#34),
    Mem2 = z80_mem:write_byte(Mem1, 16#8001, 16#12),
    Cpu0 = Machine0#machine_state.cpu,
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem2},
    Mem3 = z80_mem:write_byte(Mem2, 0, 16#2A),  %% LD HL,(nn)
    Mem4 = z80_mem:write_byte(Mem3, 1, 16#00),
    Mem5 = z80_mem:write_byte(Mem4, 2, 16#80),
    Machine2 = Machine1#machine_state{memory = Mem5},
    Machine3 = z80_cpu:step(Machine2),
    ?assertEqual(16#12, Machine3#machine_state.cpu#cpu_state.h),
    ?assertEqual(16#34, Machine3#machine_state.cpu#cpu_state.l),
    ?assertEqual(3, z80_cpu:pc(Machine3)).

ld_mem_nn_a_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{a = 16#55},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#32),  %% LD (nn),A
    Mem2 = z80_mem:write_byte(Mem1, 1, 16#00),
    Mem3 = z80_mem:write_byte(Mem2, 2, 16#80),
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem3},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#55, z80_emulator:read_byte(Machine2, 16#8000)),
    ?assertEqual(3, z80_cpu:pc(Machine2)).

ld_a_mem_nn_test() ->
    Machine0 = z80_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 16#8000, 16#AA),
    Cpu0 = Machine0#machine_state.cpu,
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Mem2 = z80_mem:write_byte(Mem1, 0, 16#3A),  %% LD A,(nn)
    Mem3 = z80_mem:write_byte(Mem2, 1, 16#00),
    Mem4 = z80_mem:write_byte(Mem3, 2, 16#80),
    Machine2 = Machine1#machine_state{memory = Mem4},
    Machine3 = z80_cpu:step(Machine2),
    ?assertEqual(16#AA, Machine3#machine_state.cpu#cpu_state.a),
    ?assertEqual(3, z80_cpu:pc(Machine3)).

%% --- LD SP,HL Test ---

ld_sp_hl_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{h = 16#12, l = 16#34},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#F9),  %% LD SP,HL
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#1234, z80_cpu:get_reg_pair(sp, Machine2#machine_state.cpu)),
    ?assertEqual(1, z80_cpu:pc(Machine2)).