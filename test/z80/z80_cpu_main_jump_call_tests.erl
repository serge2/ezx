-module(z80_cpu_main_jump_call_tests).

-include("z80_records.hrl").
-include_lib("eunit/include/eunit.hrl").

%% --- JR Tests ---

jr_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#18),  %% JR e
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#05),  %% offset +5
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(7, z80_cpu:pc(Cpu3)),
    ?assertEqual(12, z80_cpu:t_states(Cpu3)).

jr_negative_offset_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#18),  %% JR e
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#FC),  %% -4
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(16#FFFE, z80_cpu:pc(Cpu3) band 16#FFFF).

%% JR cc Tests

jr_nz_taken_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#20),  %% JR NZ,e
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#05),  %% offset +5
    Cpu3 = Cpu2#cpu_state{f = 0},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(7, z80_cpu:pc(Cpu4)),
    ?assertEqual(12, z80_cpu:t_states(Cpu4)).

jr_nz_not_taken_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#20),  %% JR NZ,e
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#05),  %% offset +5
    Cpu3 = Cpu2#cpu_state{f = 16#40},  %% Z flag set
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(2, z80_cpu:pc(Cpu4)),
    ?assertEqual(7, z80_cpu:t_states(Cpu4)).

jr_z_taken_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#28),  %% JR Z,e
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#05),  %% offset +5
    Cpu3 = Cpu2#cpu_state{f = 16#40},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(7, z80_cpu:pc(Cpu4)).

jr_z_not_taken_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#28),  %% JR Z,e
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#05),  %% offset +5
    Cpu3 = Cpu2#cpu_state{f = 0},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(2, z80_cpu:pc(Cpu4)).

jr_nc_taken_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#30),  %% JR NC,e
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#05),  %% offset +5
    Cpu3 = Cpu2#cpu_state{f = 0},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(7, z80_cpu:pc(Cpu4)).

jr_nc_not_taken_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#30),  %% JR NC,e
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#05),  %% offset +5
    Cpu3 = Cpu2#cpu_state{f = 1},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(2, z80_cpu:pc(Cpu4)).

jr_c_taken_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#38),  %% JR C,e
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#05),  %% offset +5
    Cpu3 = Cpu2#cpu_state{f = 1},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(7, z80_cpu:pc(Cpu4)).

jr_c_not_taken_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#38),  %% JR C,e
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#05),  %% offset +5
    Cpu3 = Cpu2#cpu_state{f = 0},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(2, z80_cpu:pc(Cpu4)).

%% DJNZ Tests

djnz_taken_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#10),  %% DJNZ e
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#FC),  %% -4
    Cpu3 = Cpu2#cpu_state{b = 2},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#FFFE, z80_cpu:pc(Cpu4) band 16#FFFF),
    ?assertEqual(1, Cpu4#cpu_state.b),
    ?assertEqual(13, z80_cpu:t_states(Cpu4)).

djnz_not_taken_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#10),  %% DJNZ e
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#FC),  %% -4
    Cpu3 = Cpu2#cpu_state{b = 1},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(2, z80_cpu:pc(Cpu4)),
    ?assertEqual(0, Cpu4#cpu_state.b),
    ?assertEqual(8, z80_cpu:t_states(Cpu4)).

djnz_multiple_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#10),  %% DJNZ e
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#FE),  %% -2 (jump back to DJNZ)
    Cpu3 = Cpu2#cpu_state{b = 3},
    %% First DJNZ
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(2, Cpu4#cpu_state.b),
    ?assertEqual(13, z80_cpu:t_states(Cpu4)),
    %% Second DJNZ
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(1, Cpu5#cpu_state.b),
    ?assertEqual(26, z80_cpu:t_states(Cpu5)),
    %% Third DJNZ (not taken)
    Cpu6 = z80_cpu:step(Cpu5),
    ?assertEqual(2, z80_cpu:pc(Cpu6)),
    ?assertEqual(0, Cpu6#cpu_state.b),
    ?assertEqual(34, z80_cpu:t_states(Cpu6)).

%% JP Tests

jp_nn_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#C3),  %% JP nn
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#00),  %% low byte
    Cpu3 = test_helpers:write_mem(Cpu2, 2, 16#80),  %% high byte
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#8000, z80_cpu:pc(Cpu4)),
    ?assertEqual(10, z80_cpu:t_states(Cpu4)).

jp_hl_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{h = 16#80, l = 16#00},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#E9),  %% JP (HL)
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(16#8000, z80_cpu:pc(Cpu3)),
    ?assertEqual(4, z80_cpu:t_states(Cpu3)).

jp_nz_taken_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#C2),  %% JP NZ,nn
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#00),  %% low byte
    Cpu3 = test_helpers:write_mem(Cpu2, 2, 16#80),  %% high byte
    Cpu4 = Cpu3#cpu_state{f = 0},
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(16#8000, z80_cpu:pc(Cpu5)),
    ?assertEqual(10, z80_cpu:t_states(Cpu5)).

jp_nz_not_taken_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#C2),  %% JP NZ,nn
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#00),  %% low byte
    Cpu3 = test_helpers:write_mem(Cpu2, 2, 16#80),  %% high byte
    Cpu4 = Cpu3#cpu_state{f = 16#40},
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(3, z80_cpu:pc(Cpu5)),
    ?assertEqual(10, z80_cpu:t_states(Cpu5)).

jp_z_taken_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#CA),  %% JP Z,nn
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#00),  %% low byte
    Cpu3 = test_helpers:write_mem(Cpu2, 2, 16#80),  %% high byte
    Cpu4 = Cpu3#cpu_state{f = 16#40},
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(16#8000, z80_cpu:pc(Cpu5)).

jp_nc_taken_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#D2),  %% JP NC,nn
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#00),  %% low byte
    Cpu3 = test_helpers:write_mem(Cpu2, 2, 16#80),  %% high byte
    Cpu4 = Cpu3#cpu_state{f = 0},
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(16#8000, z80_cpu:pc(Cpu5)).

jp_c_taken_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#DA),  %% JP C,nn
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#00),  %% low byte
    Cpu3 = test_helpers:write_mem(Cpu2, 2, 16#80),  %% high byte
    Cpu4 = Cpu3#cpu_state{f = 1},
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(16#8000, z80_cpu:pc(Cpu5)).

jp_po_taken_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#E2),  %% JP PO,nn
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#00),  %% low byte
    Cpu3 = test_helpers:write_mem(Cpu2, 2, 16#80),  %% high byte
    Cpu4 = Cpu3#cpu_state{f = 0},
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(16#8000, z80_cpu:pc(Cpu5)).

jp_pe_taken_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#EA),  %% JP PE,nn
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#00),  %% low byte
    Cpu3 = test_helpers:write_mem(Cpu2, 2, 16#80),  %% high byte
    Cpu4 = Cpu3#cpu_state{f = 16#04},
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(16#8000, z80_cpu:pc(Cpu5)).

jp_p_taken_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#F2),  %% JP P,nn
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#00),  %% low byte
    Cpu3 = test_helpers:write_mem(Cpu2, 2, 16#80),  %% high byte
    Cpu4 = Cpu3#cpu_state{f = 0},
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(16#8000, z80_cpu:pc(Cpu5)).

jp_m_taken_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#FA),  %% JP M,nn
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#00),  %% low byte
    Cpu3 = test_helpers:write_mem(Cpu2, 2, 16#80),  %% high byte
    Cpu4 = Cpu3#cpu_state{f = 16#80},
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(16#8000, z80_cpu:pc(Cpu5)).

%% CALL Tests

call_nn_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{sp = 16#1000},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#CD),  %% CALL nn
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#00),  %% low byte
    Cpu4 = test_helpers:write_mem(Cpu3, 2, 16#80),  %% high byte
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(16#8000, z80_cpu:pc(Cpu5)),
    ?assertEqual(16#0FFE, Cpu5#cpu_state.sp),
    ?assertEqual(16#03, z80_cpu_mem:read_byte(Cpu5#cpu_state.ext_context, 16#0FFE)),  %% Low byte of PC=3
    ?assertEqual(16#00, z80_cpu_mem:read_byte(Cpu5#cpu_state.ext_context, 16#0FFF)).  %% High byte of PC=3

call_nz_taken_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{sp = 16#1000, f = 0},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#C4),  %% CALL NZ,nn
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#00),  %% low byte
    Cpu4 = test_helpers:write_mem(Cpu3, 2, 16#80),  %% high byte
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(16#8000, z80_cpu:pc(Cpu5)),
    ?assertEqual(16#0FFE, Cpu5#cpu_state.sp).

call_nz_not_taken_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{sp = 16#1000, f = 16#40},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#C4),  %% CALL NZ,nn
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#00),  %% low byte
    Cpu4 = test_helpers:write_mem(Cpu3, 2, 16#80),  %% high byte
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(3, z80_cpu:pc(Cpu5)),
    ?assertEqual(16#1000, Cpu5#cpu_state.sp).

call_z_taken_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{sp = 16#1000, f = 16#40},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#CC),  %% CALL Z,nn
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#00),  %% low byte
    Cpu4 = test_helpers:write_mem(Cpu3, 2, 16#80),  %% high byte
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(16#8000, z80_cpu:pc(Cpu5)).

call_nc_taken_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{sp = 16#1000, f = 0},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#D4),  %% CALL NC,nn
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#00),  %% low byte
    Cpu4 = test_helpers:write_mem(Cpu3, 2, 16#80),  %% high byte
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(16#8000, z80_cpu:pc(Cpu5)).

call_c_taken_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{sp = 16#1000, f = 1},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#DC),  %% CALL C,nn
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#00),  %% low byte
    Cpu4 = test_helpers:write_mem(Cpu3, 2, 16#80),  %% high byte
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(16#8000, z80_cpu:pc(Cpu5)).

call_po_taken_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{sp = 16#1000, f = 0},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#E4),  %% CALL PO,nn
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#00),  %% low byte
    Cpu4 = test_helpers:write_mem(Cpu3, 2, 16#80),  %% high byte
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(16#8000, z80_cpu:pc(Cpu5)).

call_pe_taken_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{sp = 16#1000, f = 16#04},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#EC),  %% CALL PE,nn
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#00),  %% low byte
    Cpu4 = test_helpers:write_mem(Cpu3, 2, 16#80),  %% high byte
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(16#8000, z80_cpu:pc(Cpu5)).

call_p_taken_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{sp = 16#1000, f = 0},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#F4),  %% CALL P,nn
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#00),  %% low byte
    Cpu4 = test_helpers:write_mem(Cpu3, 2, 16#80),  %% high byte
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(16#8000, z80_cpu:pc(Cpu5)).

call_m_taken_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{sp = 16#1000, f = 16#80},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#FC),  %% CALL M,nn
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#00),  %% low byte
    Cpu4 = test_helpers:write_mem(Cpu3, 2, 16#80),  %% high byte
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(16#8000, z80_cpu:pc(Cpu5)).
