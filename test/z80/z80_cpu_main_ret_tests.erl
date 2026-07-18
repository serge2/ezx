-module(z80_cpu_main_ret_tests).

-include("z80_records.hrl").
-include_lib("eunit/include/eunit.hrl").

%% --- RET Tests ---

ret_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{sp = 16#1000},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#C9),  %% RET
    Cpu3 = test_helpers:write_mem(Cpu2, 16#1000, 16#00),  %% low byte of return addr
    Cpu4 = test_helpers:write_mem(Cpu3, 16#1001, 16#80),  %% high byte of return addr
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(16#8000, z80_cpu:pc(Cpu5)),
    ?assertEqual(16#1002, Cpu5#cpu_state.sp),
    ?assertEqual(10, z80_cpu:t_states(Cpu5)).

ret_nz_taken_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{sp = 16#1000, f = 0},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#C0),  %% RET NZ
    Cpu3 = test_helpers:write_mem(Cpu2, 16#1000, 16#00),  %% low byte
    Cpu4 = test_helpers:write_mem(Cpu3, 16#1001, 16#80),  %% high byte
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(16#8000, z80_cpu:pc(Cpu5)),
    ?assertEqual(11, z80_cpu:t_states(Cpu5)).

ret_nz_not_taken_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{sp = 16#1000, f = 16#40},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#C0),  %% RET NZ
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(1, z80_cpu:pc(Cpu3)),
    ?assertEqual(5, z80_cpu:t_states(Cpu3)).

ret_z_taken_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{sp = 16#1000, f = 16#40},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#C8),  %% RET Z
    Cpu3 = test_helpers:write_mem(Cpu2, 16#1000, 16#00),  %% low byte
    Cpu4 = test_helpers:write_mem(Cpu3, 16#1001, 16#80),  %% high byte
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(16#8000, z80_cpu:pc(Cpu5)).

ret_nc_taken_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{sp = 16#1000, f = 0},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#D0),  %% RET NC
    Cpu3 = test_helpers:write_mem(Cpu2, 16#1000, 16#00),  %% low byte
    Cpu4 = test_helpers:write_mem(Cpu3, 16#1001, 16#80),  %% high byte
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(16#8000, z80_cpu:pc(Cpu5)).

ret_c_taken_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{sp = 16#1000, f = 1},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#D8),  %% RET C
    Cpu3 = test_helpers:write_mem(Cpu2, 16#1000, 16#00),  %% low byte
    Cpu4 = test_helpers:write_mem(Cpu3, 16#1001, 16#80),  %% high byte
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(16#8000, z80_cpu:pc(Cpu5)).

ret_po_taken_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{sp = 16#1000, f = 0},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#E0),  %% RET PO
    Cpu3 = test_helpers:write_mem(Cpu2, 16#1000, 16#00),  %% low byte
    Cpu4 = test_helpers:write_mem(Cpu3, 16#1001, 16#80),  %% high byte
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(16#8000, z80_cpu:pc(Cpu5)).

ret_pe_taken_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{sp = 16#1000, f = 16#04},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#E8),  %% RET PE
    Cpu3 = test_helpers:write_mem(Cpu2, 16#1000, 16#00),  %% low byte
    Cpu4 = test_helpers:write_mem(Cpu3, 16#1001, 16#80),  %% high byte
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(16#8000, z80_cpu:pc(Cpu5)).

ret_p_taken_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{sp = 16#1000, f = 0},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#F0),  %% RET P
    Cpu3 = test_helpers:write_mem(Cpu2, 16#1000, 16#00),  %% low byte
    Cpu4 = test_helpers:write_mem(Cpu3, 16#1001, 16#80),  %% high byte
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(16#8000, z80_cpu:pc(Cpu5)).

ret_m_taken_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{sp = 16#1000, f = 16#80},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#F8),  %% RET M
    Cpu3 = test_helpers:write_mem(Cpu2, 16#1000, 16#00),  %% low byte
    Cpu4 = test_helpers:write_mem(Cpu3, 16#1001, 16#80),  %% high byte
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(16#8000, z80_cpu:pc(Cpu5)).

%% --- RST Tests ---

rst_00_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{sp = 16#1000},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#C7),  %% RST 00h
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(16#0000, z80_cpu:pc(Cpu3)),
    ?assertEqual(16#0FFE, Cpu3#cpu_state.sp),
    ?assertEqual(16#01, z80_cpu_mem:read_byte(Cpu3#cpu_state.ext_context, 16#0FFE)),  %% Low byte of pushed PC=1
    ?assertEqual(16#00, z80_cpu_mem:read_byte(Cpu3#cpu_state.ext_context, 16#0FFF)).  %% High byte of pushed PC=1

rst_08_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{sp = 16#1000},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#CF),  %% RST 08h
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(16#0008, z80_cpu:pc(Cpu3)).

rst_10_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{sp = 16#1000},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#D7),  %% RST 10h
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(16#0010, z80_cpu:pc(Cpu3)).

rst_18_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{sp = 16#1000},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#DF),  %% RST 18h
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(16#0018, z80_cpu:pc(Cpu3)).

rst_20_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{sp = 16#1000},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#E7),  %% RST 20h
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(16#0020, z80_cpu:pc(Cpu3)).

rst_28_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{sp = 16#1000},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#EF),  %% RST 28h
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(16#0028, z80_cpu:pc(Cpu3)).

rst_30_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{sp = 16#1000},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#F7),  %% RST 30h
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(16#0030, z80_cpu:pc(Cpu3)).

rst_38_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{sp = 16#1000},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#FF),  %% RST 38h
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(16#0038, z80_cpu:pc(Cpu3)).
