-module(z80_cpu_main_exchange_tests).

-include("z80_records.hrl").
-include_lib("eunit/include/eunit.hrl").

%% --- Exchange Tests ---

ex_af_af_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#08),  %% EX AF,AF'
    Cpu2 = Cpu1#cpu_state{a = 16#12, f = 16#34, a_alt = 16#56, f_alt = 16#78},
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(16#56, Cpu3#cpu_state.a),
    ?assertEqual(16#78, Cpu3#cpu_state.f),
    ?assertEqual(16#12, Cpu3#cpu_state.a_alt),
    ?assertEqual(16#34, Cpu3#cpu_state.f_alt),
    ?assertEqual(4, z80_cpu:t_states(Cpu3)).

ex_af_af_twice_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#08),  %% EX AF,AF'
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#08),  %% EX AF,AF'
    Cpu3 = Cpu2#cpu_state{a = 16#12, f = 16#34, a_alt = 16#56, f_alt = 16#78},
    Cpu4 = z80_cpu:step(Cpu3),
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(16#12, Cpu5#cpu_state.a),
    ?assertEqual(16#34, Cpu5#cpu_state.f).

ex_de_hl_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#EB),  %% EX DE,HL
    Cpu2 = Cpu1#cpu_state{d = 16#12, e = 16#34, h = 16#56, l = 16#78},
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(16#56, Cpu3#cpu_state.d),
    ?assertEqual(16#78, Cpu3#cpu_state.e),
    ?assertEqual(16#12, Cpu3#cpu_state.h),
    ?assertEqual(16#34, Cpu3#cpu_state.l),
    ?assertEqual(4, z80_cpu:t_states(Cpu3)).

ex_sp_hl_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#FEFE, 16#78),  %% Low byte at SP
    Cpu2 = test_helpers:write_mem(Cpu1, 16#FEFF, 16#56),  %% High byte at SP+1
    Cpu3 = test_helpers:write_mem(Cpu2, 0, 16#E3),  %% EX (SP),HL
    Cpu4 = Cpu3#cpu_state{sp = 16#FEFE, h = 16#12, l = 16#34},
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(16#56, Cpu5#cpu_state.h),
    ?assertEqual(16#78, Cpu5#cpu_state.l),
    ?assertEqual(16#34, test_helpers:read_mem(Cpu5, 16#FEFE)),  %% Low byte = old L
    ?assertEqual(16#12, test_helpers:read_mem(Cpu5, 16#FEFF)),  %% High byte = old H
    ?assertEqual(19, z80_cpu:t_states(Cpu5)).

exx_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#D9),  %% EXX
    Cpu2 = Cpu1#cpu_state{
        b = 16#11, c = 16#22, d = 16#33, e = 16#44, h = 16#55, l = 16#66,
        b_alt = 16#77, c_alt = 16#88, d_alt = 16#99, e_alt = 16#AA, h_alt = 16#BB, l_alt = 16#CC
    },
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(16#77, Cpu3#cpu_state.b),
    ?assertEqual(16#88, Cpu3#cpu_state.c),
    ?assertEqual(16#99, Cpu3#cpu_state.d),
    ?assertEqual(16#AA, Cpu3#cpu_state.e),
    ?assertEqual(16#BB, Cpu3#cpu_state.h),
    ?assertEqual(16#CC, Cpu3#cpu_state.l),
    ?assertEqual(16#11, Cpu3#cpu_state.b_alt),
    ?assertEqual(16#22, Cpu3#cpu_state.c_alt),
    ?assertEqual(16#33, Cpu3#cpu_state.d_alt),
    ?assertEqual(16#44, Cpu3#cpu_state.e_alt),
    ?assertEqual(16#55, Cpu3#cpu_state.h_alt),
    ?assertEqual(16#66, Cpu3#cpu_state.l_alt),
    ?assertEqual(4, z80_cpu:t_states(Cpu3)).

exx_twice_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#D9),  %% EXX
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#D9),  %% EXX
    Cpu3 = Cpu2#cpu_state{
        b = 16#11, c = 16#22, d = 16#33, e = 16#44, h = 16#55, l = 16#66,
        b_alt = 16#77, c_alt = 16#88, d_alt = 16#99, e_alt = 16#AA, h_alt = 16#BB, l_alt = 16#CC
    },
    Cpu4 = z80_cpu:step(Cpu3),
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(16#11, Cpu5#cpu_state.b),
    ?assertEqual(16#22, Cpu5#cpu_state.c).

%% --- PUSH/POP Tests ---

push_bc_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#C5),  %% PUSH BC
    Cpu2 = Cpu1#cpu_state{b = 16#12, c = 16#34, sp = 16#FF00},
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(16#FEFE, Cpu3#cpu_state.sp),
    ?assertEqual(16#34, test_helpers:read_mem(Cpu3, 16#FEFE)),
    ?assertEqual(16#12, test_helpers:read_mem(Cpu3, 16#FEFF)),
    ?assertEqual(11, z80_cpu:t_states(Cpu3)).

push_de_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#D5),  %% PUSH DE
    Cpu2 = Cpu1#cpu_state{d = 16#12, e = 16#34, sp = 16#FF00},
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(16#FEFE, Cpu3#cpu_state.sp),
    ?assertEqual(16#34, test_helpers:read_mem(Cpu3, 16#FEFE)),
    ?assertEqual(16#12, test_helpers:read_mem(Cpu3, 16#FEFF)).

push_hl_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#E5),  %% PUSH HL
    Cpu2 = Cpu1#cpu_state{h = 16#12, l = 16#34, sp = 16#FF00},
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(16#FEFE, Cpu3#cpu_state.sp),
    ?assertEqual(16#34, test_helpers:read_mem(Cpu3, 16#FEFE)),
    ?assertEqual(16#12, test_helpers:read_mem(Cpu3, 16#FEFF)).

push_af_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#F5),  %% PUSH AF
    Cpu2 = Cpu1#cpu_state{a = 16#12, f = 16#34, sp = 16#FF00},
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(16#FEFE, Cpu3#cpu_state.sp),
    ?assertEqual(16#34, test_helpers:read_mem(Cpu3, 16#FEFE)),
    ?assertEqual(16#12, test_helpers:read_mem(Cpu3, 16#FEFF)).

pop_bc_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#FEFE, 16#56),
    Cpu2 = test_helpers:write_mem(Cpu1, 16#FEFF, 16#78),
    Cpu3 = test_helpers:write_mem(Cpu2, 0, 16#C1),  %% POP BC
    Cpu4 = Cpu3#cpu_state{sp = 16#FEFE},
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(16#78, Cpu5#cpu_state.b),
    ?assertEqual(16#56, Cpu5#cpu_state.c),
    ?assertEqual(16#FF00, Cpu5#cpu_state.sp),
    ?assertEqual(10, z80_cpu:t_states(Cpu5)).

pop_de_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#FEFE, 16#56),
    Cpu2 = test_helpers:write_mem(Cpu1, 16#FEFF, 16#78),
    Cpu3 = test_helpers:write_mem(Cpu2, 0, 16#D1),  %% POP DE
    Cpu4 = Cpu3#cpu_state{sp = 16#FEFE},
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(16#78, Cpu5#cpu_state.d),
    ?assertEqual(16#56, Cpu5#cpu_state.e).

pop_hl_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#FEFE, 16#56),
    Cpu2 = test_helpers:write_mem(Cpu1, 16#FEFF, 16#78),
    Cpu3 = test_helpers:write_mem(Cpu2, 0, 16#E1),  %% POP HL
    Cpu4 = Cpu3#cpu_state{sp = 16#FEFE},
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(16#78, Cpu5#cpu_state.h),
    ?assertEqual(16#56, Cpu5#cpu_state.l).

pop_af_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#FEFE, 16#F0),
    Cpu2 = test_helpers:write_mem(Cpu1, 16#FEFF, 16#DE),
    Cpu3 = test_helpers:write_mem(Cpu2, 0, 16#F1),  %% POP AF
    Cpu4 = Cpu3#cpu_state{sp = 16#FEFE},
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(16#DE, Cpu5#cpu_state.a),
    ?assertEqual(16#F0, Cpu5#cpu_state.f).
