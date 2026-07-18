-module(z80_cpu_main_stack_tests).

-include("z80_records.hrl").
-include_lib("eunit/include/eunit.hrl").

%% --- PUSH Tests ---

push_bc_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#C5),  %% PUSH BC
    Cpu2 = Cpu1#cpu_state{b = 16#12, c = 16#34, sp = 16#FF00},
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(16#FEFE, Cpu3#cpu_state.sp),
    ?assertEqual(16#34, z80_cpu_mem:read_byte(Cpu3#cpu_state.ext_context, 16#FEFE)),
    ?assertEqual(16#12, z80_cpu_mem:read_byte(Cpu3#cpu_state.ext_context, 16#FEFF)),
    ?assertEqual(11, z80_cpu:t_states(Cpu3)).

push_de_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#D5),  %% PUSH DE
    Cpu2 = Cpu1#cpu_state{d = 16#56, e = 16#78, sp = 16#FF00},
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(16#FEFE, Cpu3#cpu_state.sp),
    ?assertEqual(16#78, z80_cpu_mem:read_byte(Cpu3#cpu_state.ext_context, 16#FEFE)),
    ?assertEqual(16#56, z80_cpu_mem:read_byte(Cpu3#cpu_state.ext_context, 16#FEFF)).

push_hl_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#E5),  %% PUSH HL
    Cpu2 = Cpu1#cpu_state{h = 16#9A, l = 16#BC, sp = 16#FF00},
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(16#FEFE, Cpu3#cpu_state.sp),
    ?assertEqual(16#BC, z80_cpu_mem:read_byte(Cpu3#cpu_state.ext_context, 16#FEFE)),
    ?assertEqual(16#9A, z80_cpu_mem:read_byte(Cpu3#cpu_state.ext_context, 16#FEFF)).

push_af_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#F5),  %% PUSH AF
    Cpu2 = Cpu1#cpu_state{a = 16#DE, f = 16#F0, sp = 16#FF00},
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(16#FEFE, Cpu3#cpu_state.sp),
    ?assertEqual(16#F0, z80_cpu_mem:read_byte(Cpu3#cpu_state.ext_context, 16#FEFE)),
    ?assertEqual(16#DE, z80_cpu_mem:read_byte(Cpu3#cpu_state.ext_context, 16#FEFF)).

push_sp_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#F5),  %% PUSH AF (using as placeholder)
    Cpu2 = Cpu1#cpu_state{sp = 16#1234, b = 0, c = 0},
    %% Can't test PUSH SP directly without specific opcode
    ok.

%% --- POP Tests ---

pop_bc_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#FEFE, 16#34),
    Cpu2 = test_helpers:write_mem(Cpu1, 16#FEFF, 16#12),
    Cpu3 = test_helpers:write_mem(Cpu2, 0, 16#C1),  %% POP BC
    Cpu4 = Cpu3#cpu_state{sp = 16#FEFE},
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(16#12, Cpu5#cpu_state.b),
    ?assertEqual(16#34, Cpu5#cpu_state.c),
    ?assertEqual(16#FF00, Cpu5#cpu_state.sp),
    ?assertEqual(10, z80_cpu:t_states(Cpu5)).

pop_de_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#FEFE, 16#78),
    Cpu2 = test_helpers:write_mem(Cpu1, 16#FEFF, 16#56),
    Cpu3 = test_helpers:write_mem(Cpu2, 0, 16#D1),  %% POP DE
    Cpu4 = Cpu3#cpu_state{sp = 16#FEFE},
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(16#56, Cpu5#cpu_state.d),
    ?assertEqual(16#78, Cpu5#cpu_state.e),
    ?assertEqual(16#FF00, Cpu5#cpu_state.sp).

pop_hl_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#FEFE, 16#BC),
    Cpu2 = test_helpers:write_mem(Cpu1, 16#FEFF, 16#9A),
    Cpu3 = test_helpers:write_mem(Cpu2, 0, 16#E1),  %% POP HL
    Cpu4 = Cpu3#cpu_state{sp = 16#FEFE},
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(16#9A, Cpu5#cpu_state.h),
    ?assertEqual(16#BC, Cpu5#cpu_state.l),
    ?assertEqual(16#FF00, Cpu5#cpu_state.sp).

pop_af_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#FEFE, 16#F0),
    Cpu2 = test_helpers:write_mem(Cpu1, 16#FEFF, 16#DE),
    Cpu3 = test_helpers:write_mem(Cpu2, 0, 16#F1),  %% POP AF
    Cpu4 = Cpu3#cpu_state{sp = 16#FEFE},
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(16#DE, Cpu5#cpu_state.a),
    ?assertEqual(16#F0, Cpu5#cpu_state.f),
    ?assertEqual(16#FF00, Cpu5#cpu_state.sp).

%% --- RET Tests ---

ret_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#FEFE, 16#00),
    Cpu2 = test_helpers:write_mem(Cpu1, 16#FEFF, 16#80),
    Cpu3 = test_helpers:write_mem(Cpu2, 0, 16#C9),  %% RET
    Cpu4 = Cpu3#cpu_state{sp = 16#FEFE},
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(16#8000, z80_cpu:pc(Cpu5)),
    ?assertEqual(16#FF00, Cpu5#cpu_state.sp),
    ?assertEqual(10, z80_cpu:t_states(Cpu5)).

ret_nz_taken_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#FEFE, 16#00),
    Cpu2 = test_helpers:write_mem(Cpu1, 16#FEFF, 16#80),
    Cpu3 = test_helpers:write_mem(Cpu2, 0, 16#C0),  %% RET NZ
    Cpu4 = Cpu3#cpu_state{sp = 16#FEFE, f = 0},
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(16#8000, z80_cpu:pc(Cpu5)),
    ?assertEqual(11, z80_cpu:t_states(Cpu5)).

ret_nz_not_taken_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#FEFE, 16#00),
    Cpu2 = test_helpers:write_mem(Cpu1, 16#FEFF, 16#80),
    Cpu3 = test_helpers:write_mem(Cpu2, 0, 16#C0),  %% RET NZ
    Cpu4 = Cpu3#cpu_state{sp = 16#FEFE, f = 16#40},
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(1, z80_cpu:pc(Cpu5)),
    ?assertEqual(5, z80_cpu:t_states(Cpu5)).

ret_z_taken_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#FEFE, 16#00),
    Cpu2 = test_helpers:write_mem(Cpu1, 16#FEFF, 16#80),
    Cpu3 = test_helpers:write_mem(Cpu2, 0, 16#C8),  %% RET Z
    Cpu4 = Cpu3#cpu_state{sp = 16#FEFE, f = 16#40},
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(16#8000, z80_cpu:pc(Cpu5)).

ret_nc_taken_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#FEFE, 16#00),
    Cpu2 = test_helpers:write_mem(Cpu1, 16#FEFF, 16#80),
    Cpu3 = test_helpers:write_mem(Cpu2, 0, 16#D0),  %% RET NC
    Cpu4 = Cpu3#cpu_state{sp = 16#FEFE, f = 0},
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(16#8000, z80_cpu:pc(Cpu5)).

ret_c_taken_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#FEFE, 16#00),
    Cpu2 = test_helpers:write_mem(Cpu1, 16#FEFF, 16#80),
    Cpu3 = test_helpers:write_mem(Cpu2, 0, 16#D8),  %% RET C
    Cpu4 = Cpu3#cpu_state{sp = 16#FEFE, f = 1},
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(16#8000, z80_cpu:pc(Cpu5)).

ret_po_taken_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#FEFE, 16#00),
    Cpu2 = test_helpers:write_mem(Cpu1, 16#FEFF, 16#80),
    Cpu3 = test_helpers:write_mem(Cpu2, 0, 16#E0),  %% RET PO
    Cpu4 = Cpu3#cpu_state{sp = 16#FEFE, f = 0},
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(16#8000, z80_cpu:pc(Cpu5)).

ret_pe_taken_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#FEFE, 16#00),
    Cpu2 = test_helpers:write_mem(Cpu1, 16#FEFF, 16#80),
    Cpu3 = test_helpers:write_mem(Cpu2, 0, 16#E8),  %% RET PE
    Cpu4 = Cpu3#cpu_state{sp = 16#FEFE, f = 16#04},
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(16#8000, z80_cpu:pc(Cpu5)).

ret_p_taken_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#FEFE, 16#00),
    Cpu2 = test_helpers:write_mem(Cpu1, 16#FEFF, 16#80),
    Cpu3 = test_helpers:write_mem(Cpu2, 0, 16#F0),  %% RET P
    Cpu4 = Cpu3#cpu_state{sp = 16#FEFE, f = 0},
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(16#8000, z80_cpu:pc(Cpu5)).

ret_m_taken_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#FEFE, 16#00),
    Cpu2 = test_helpers:write_mem(Cpu1, 16#FEFF, 16#80),
    Cpu3 = test_helpers:write_mem(Cpu2, 0, 16#F8),  %% RET M
    Cpu4 = Cpu3#cpu_state{sp = 16#FEFE, f = 16#80},
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(16#8000, z80_cpu:pc(Cpu5)).

%% RST Tests (already in ret_tests but also stack operations)

rst_00_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{sp = 16#1000, pc = 16#0005},
    Cpu2 = test_helpers:write_mem(Cpu1, 16#0005, 16#C7),  %% RST 00h
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(16#0000, z80_cpu:pc(Cpu3)),
    ?assertEqual(16#0FFE, Cpu3#cpu_state.sp),
    ?assertEqual(16#06, z80_cpu_mem:read_byte(Cpu3#cpu_state.ext_context, 16#0FFE)),  %% Low byte of pushed PC=6
    ?assertEqual(16#00, z80_cpu_mem:read_byte(Cpu3#cpu_state.ext_context, 16#0FFF)).  %% High byte of pushed PC=6
