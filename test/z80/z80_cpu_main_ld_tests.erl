-module(z80_cpu_main_ld_tests).

-include("z80_records.hrl").
-include_lib("eunit/include/eunit.hrl").

%% --- 16-bit LD Tests ---

ld_bc_nn_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#01),  %% LD BC,nn
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#34),
    Cpu3 = test_helpers:write_mem(Cpu2, 2, 16#12),
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#1234, z80_cpu:get_reg_pair(bc, Cpu4)),
    ?assertEqual(3, z80_cpu:pc(Cpu4)).

ld_bc_nn_timing_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#01),  %% LD BC,nn
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#34),
    Cpu3 = test_helpers:write_mem(Cpu2, 2, 16#12),
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(10, z80_cpu:t_states(Cpu4)).

ld_de_nn_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#11),  %% LD DE,nn
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#56),
    Cpu3 = test_helpers:write_mem(Cpu2, 2, 16#78),
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#7856, z80_cpu:get_reg_pair(de, Cpu4)),
    ?assertEqual(3, z80_cpu:pc(Cpu4)).

ld_hl_nn_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#21),  %% LD HL,nn
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#34),
    Cpu3 = test_helpers:write_mem(Cpu2, 2, 16#12),
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#1234, z80_cpu:get_reg_pair(hl, Cpu4)),
    ?assertEqual(3, z80_cpu:pc(Cpu4)).

ld_sp_nn_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#31),  %% LD SP,nn
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#00),
    Cpu3 = test_helpers:write_mem(Cpu2, 2, 16#80),
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#8000, z80_cpu:get_reg_pair(sp, Cpu4)),
    ?assertEqual(3, z80_cpu:pc(Cpu4)).

%% --- 8-bit LD r,r Tests ---

ld_b_c_test() ->
    Cpu0_init = test_helpers:init_cpu(),
    Cpu0 = Cpu0_init#cpu_state{c = 16#42},
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#41),  %% LD B,C
    Cpu2 = z80_cpu:step(Cpu1),
    ?assertEqual(16#42, Cpu2#cpu_state.b),
    ?assertEqual(1, z80_cpu:pc(Cpu2)).

ld_a_b_test() ->
    Cpu0_init = test_helpers:init_cpu(),
    Cpu0 = Cpu0_init#cpu_state{b = 16#55},
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#78),  %% LD A,B
    Cpu2 = z80_cpu:step(Cpu1),
    ?assertEqual(16#55, Cpu2#cpu_state.a).

ld_a_a_test() ->
    Cpu0_init = test_helpers:init_cpu(),
    Cpu0 = Cpu0_init#cpu_state{a = 16#AA},
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#7F),  %% LD A,A
    Cpu2 = z80_cpu:step(Cpu1),
    ?assertEqual(16#AA, Cpu2#cpu_state.a).

%% --- LD r,n Tests ---

ld_b_n_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#06),  %% LD B,n
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#42),
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(16#42, Cpu3#cpu_state.b),
    ?assertEqual(2, z80_cpu:pc(Cpu3)).

ld_a_n_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#3E),  %% LD A,n
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#77),
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(16#77, Cpu3#cpu_state.a),
    ?assertEqual(2, z80_cpu:pc(Cpu3)).

%% --- LD r,(HL) Tests ---

ld_b_mem_hl_test() ->
    Cpu0_init = test_helpers:init_cpu(),
    Cpu0 = Cpu0_init#cpu_state{h = 16#40, l = 16#00},
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#55),
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#46),  %% LD B,(HL)
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(16#55, Cpu3#cpu_state.b),
    ?assertEqual(1, z80_cpu:pc(Cpu3)).

ld_c_mem_hl_test() ->
    Cpu0_init = test_helpers:init_cpu(),
    Cpu0 = Cpu0_init#cpu_state{h = 16#40, l = 16#00},
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#AA),
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#4E),  %% LD C,(HL)
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(16#AA, Cpu3#cpu_state.c).

ld_h_mem_hl_test() ->
    Cpu0_init = test_helpers:init_cpu(),
    Cpu0 = Cpu0_init#cpu_state{h = 16#40, l = 16#00},
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#CC),
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#66),  %% LD H,(HL)
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(16#CC, Cpu3#cpu_state.h).

ld_l_mem_hl_test() ->
    Cpu0_init = test_helpers:init_cpu(),
    Cpu0 = Cpu0_init#cpu_state{h = 16#40, l = 16#00},
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#DD),
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#6E),  %% LD L,(HL)
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(16#DD, Cpu3#cpu_state.l).

ld_a_mem_hl_test() ->
    Cpu0_init = test_helpers:init_cpu(),
    Cpu0 = Cpu0_init#cpu_state{h = 16#40, l = 16#00},
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#EE),
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#7E),  %% LD A,(HL)
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(16#EE, Cpu3#cpu_state.a).

%% --- LD (HL),r Tests ---

ld_mem_hl_b_test() ->
    Cpu0_init = test_helpers:init_cpu(),
    Cpu0 = Cpu0_init#cpu_state{h = 16#40, l = 16#00, b = 16#55},
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#70),  %% LD (HL),B
    Cpu2 = z80_cpu:step(Cpu1),
    ?assertEqual(16#55, test_helpers:read_mem(Cpu2, 16#4000)),
    ?assertEqual(1, z80_cpu:pc(Cpu2)).

ld_mem_hl_a_test() ->
    Cpu0_init = test_helpers:init_cpu(),
    Cpu0 = Cpu0_init#cpu_state{h = 16#40, l = 16#00, a = 16#AA},
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#77),  %% LD (HL),A
    Cpu2 = z80_cpu:step(Cpu1),
    ?assertEqual(16#AA, test_helpers:read_mem(Cpu2, 16#4000)).

%% --- LD (HL),n Test ---

ld_mem_hl_n_test() ->
    Cpu0_init = test_helpers:init_cpu(),
    Cpu0 = Cpu0_init#cpu_state{h = 16#40, l = 16#00},
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#36),  %% LD (HL),n
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#77),
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(16#77, test_helpers:read_mem(Cpu3, 16#4000)),
    ?assertEqual(2, z80_cpu:pc(Cpu3)).

%% --- LD (BC),A / LD (DE),A Tests ---

ld_mem_bc_a_test() ->
    Cpu0_init = test_helpers:init_cpu(),
    Cpu0 = Cpu0_init#cpu_state{b = 16#40, c = 16#00, a = 16#55},
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#02),  %% LD (BC),A
    Cpu2 = z80_cpu:step(Cpu1),
    ?assertEqual(16#55, test_helpers:read_mem(Cpu2, 16#4000)),
    ?assertEqual(1, z80_cpu:pc(Cpu2)).

ld_mem_de_a_test() ->
    Cpu0_init = test_helpers:init_cpu(),
    Cpu0 = Cpu0_init#cpu_state{d = 16#40, e = 16#00, a = 16#AA},
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#12),  %% LD (DE),A
    Cpu2 = z80_cpu:step(Cpu1),
    ?assertEqual(16#AA, test_helpers:read_mem(Cpu2, 16#4000)).

%% --- LD A,(BC) / LD A,(DE) Tests ---

ld_a_mem_bc_test() ->
    Cpu0_init = test_helpers:init_cpu(),
    Cpu0 = Cpu0_init#cpu_state{b = 16#40, c = 16#00},
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#55),
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#0A),  %% LD A,(BC)
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(16#55, Cpu3#cpu_state.a),
    ?assertEqual(1, z80_cpu:pc(Cpu3)).

ld_a_mem_de_test() ->
    Cpu0_init = test_helpers:init_cpu(),
    Cpu0 = Cpu0_init#cpu_state{d = 16#40, e = 16#00},
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#AA),
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#1A),  %% LD A,(DE)
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(16#AA, Cpu3#cpu_state.a).

%% --- LD (nn),HL / LD (nn),A / LD HL,(nn) / LD A,(nn) Tests ---

ld_mem_nn_hl_test() ->
    Cpu0_init = test_helpers:init_cpu(),
    Cpu0 = Cpu0_init#cpu_state{h = 16#12, l = 16#34},
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#22),  %% LD (nn),HL
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#00),
    Cpu3 = test_helpers:write_mem(Cpu2, 2, 16#80),
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#34, test_helpers:read_mem(Cpu4, 16#8000)),
    ?assertEqual(16#12, test_helpers:read_mem(Cpu4, 16#8001)),
    ?assertEqual(3, z80_cpu:pc(Cpu4)).

ld_hl_mem_nn_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#8000, 16#34),
    Cpu2 = test_helpers:write_mem(Cpu1, 16#8001, 16#12),
    Cpu3 = test_helpers:write_mem(Cpu2, 0, 16#2A),  %% LD HL,(nn)
    Cpu4 = test_helpers:write_mem(Cpu3, 1, 16#00),
    Cpu5 = test_helpers:write_mem(Cpu4, 2, 16#80),
    Cpu6 = z80_cpu:step(Cpu5),
    ?assertEqual(16#12, Cpu6#cpu_state.h),
    ?assertEqual(16#34, Cpu6#cpu_state.l),
    ?assertEqual(3, z80_cpu:pc(Cpu6)).

ld_mem_nn_a_test() ->
    Cpu0_init = test_helpers:init_cpu(),
    Cpu0 = Cpu0_init#cpu_state{a = 16#55},
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#32),  %% LD (nn),A
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#00),
    Cpu3 = test_helpers:write_mem(Cpu2, 2, 16#80),
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#55, test_helpers:read_mem(Cpu4, 16#8000)),
    ?assertEqual(3, z80_cpu:pc(Cpu4)).

ld_a_mem_nn_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#8000, 16#AA),
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#3A),  %% LD A,(nn)
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#00),
    Cpu4 = test_helpers:write_mem(Cpu3, 2, 16#80),
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(16#AA, Cpu5#cpu_state.a),
    ?assertEqual(3, z80_cpu:pc(Cpu5)).

%% --- LD SP,HL Test ---

ld_sp_hl_test() ->
    Cpu0_init = test_helpers:init_cpu(),
    Cpu0 = Cpu0_init#cpu_state{h = 16#12, l = 16#34},
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#F9),  %% LD SP,HL
    Cpu2 = z80_cpu:step(Cpu1),
    ?assertEqual(16#1234, z80_cpu:get_reg_pair(sp, Cpu2)),
    ?assertEqual(1, z80_cpu:pc(Cpu2)).
