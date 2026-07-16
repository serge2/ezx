-module(z80_cpu_main_jump_call_tests).

-include("z80_records.hrl").
-include_lib("eunit/include/eunit.hrl").

%% --- JR Tests ---

jr_test() ->
    Machine0 = z80_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#18),  %% JR e
    Mem2 = z80_mem:write_byte(Mem1, 1, 16#05),
    Machine1 = Machine0#machine_state{memory = Mem2},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(7, z80_cpu:pc(Machine2)),
    ?assertEqual(12, z80_cpu:t_states(Machine2)).

jr_negative_offset_test() ->
    Machine0 = z80_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#18),  %% JR e
    Mem2 = z80_mem:write_byte(Mem1, 1, 16#FC),  %% -4
    Machine1 = Machine0#machine_state{memory = Mem2},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#FFFE, z80_cpu:pc(Machine2) band 16#FFFF).

%% JR cc Tests

jr_nz_taken_test() ->
    Machine0 = z80_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#20),  %% JR NZ,e
    Mem2 = z80_mem:write_byte(Mem1, 1, 16#05),
    Machine1 = Machine0#machine_state{memory = Mem2},
    Cpu1 = Machine1#machine_state.cpu#cpu_state{f = 0},
    Machine2 = Machine1#machine_state{cpu = Cpu1},
    Machine3 = z80_cpu:step(Machine2),
    ?assertEqual(7, z80_cpu:pc(Machine3)),
    ?assertEqual(12, z80_cpu:t_states(Machine3)).

jr_nz_not_taken_test() ->
    Machine0 = z80_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#20),  %% JR NZ,e
    Mem2 = z80_mem:write_byte(Mem1, 1, 16#05),
    Machine1 = Machine0#machine_state{memory = Mem2},
    Cpu1 = Machine1#machine_state.cpu#cpu_state{f = 16#40},  %% Z flag set
    Machine2 = Machine1#machine_state{cpu = Cpu1},
    Machine3 = z80_cpu:step(Machine2),
    ?assertEqual(2, z80_cpu:pc(Machine3)),
    ?assertEqual(7, z80_cpu:t_states(Machine3)).

jr_z_taken_test() ->
    Machine0 = z80_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#28),  %% JR Z,e
    Mem2 = z80_mem:write_byte(Mem1, 1, 16#05),
    Machine1 = Machine0#machine_state{memory = Mem2},
    Cpu1 = Machine1#machine_state.cpu#cpu_state{f = 16#40},
    Machine2 = Machine1#machine_state{cpu = Cpu1},
    Machine3 = z80_cpu:step(Machine2),
    ?assertEqual(7, z80_cpu:pc(Machine3)).

jr_z_not_taken_test() ->
    Machine0 = z80_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#28),  %% JR Z,e
    Mem2 = z80_mem:write_byte(Mem1, 1, 16#05),
    Machine1 = Machine0#machine_state{memory = Mem2},
    Cpu1 = Machine1#machine_state.cpu#cpu_state{f = 0},
    Machine2 = Machine1#machine_state{cpu = Cpu1},
    Machine3 = z80_cpu:step(Machine2),
    ?assertEqual(2, z80_cpu:pc(Machine3)).

jr_nc_taken_test() ->
    Machine0 = z80_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#30),  %% JR NC,e
    Mem2 = z80_mem:write_byte(Mem1, 1, 16#05),
    Machine1 = Machine0#machine_state{memory = Mem2},
    Cpu1 = Machine1#machine_state.cpu#cpu_state{f = 0},
    Machine2 = Machine1#machine_state{cpu = Cpu1},
    Machine3 = z80_cpu:step(Machine2),
    ?assertEqual(7, z80_cpu:pc(Machine3)).

jr_nc_not_taken_test() ->
    Machine0 = z80_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#30),  %% JR NC,e
    Mem2 = z80_mem:write_byte(Mem1, 1, 16#05),
    Machine1 = Machine0#machine_state{memory = Mem2},
    Cpu1 = Machine1#machine_state.cpu#cpu_state{f = 1},
    Machine2 = Machine1#machine_state{cpu = Cpu1},
    Machine3 = z80_cpu:step(Machine2),
    ?assertEqual(2, z80_cpu:pc(Machine3)).

jr_c_taken_test() ->
    Machine0 = z80_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#38),  %% JR C,e
    Mem2 = z80_mem:write_byte(Mem1, 1, 16#05),
    Machine1 = Machine0#machine_state{memory = Mem2},
    Cpu1 = Machine1#machine_state.cpu#cpu_state{f = 1},
    Machine2 = Machine1#machine_state{cpu = Cpu1},
    Machine3 = z80_cpu:step(Machine2),
    ?assertEqual(7, z80_cpu:pc(Machine3)).

jr_c_not_taken_test() ->
    Machine0 = z80_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#38),  %% JR C,e
    Mem2 = z80_mem:write_byte(Mem1, 1, 16#05),
    Machine1 = Machine0#machine_state{memory = Mem2},
    Cpu1 = Machine1#machine_state.cpu#cpu_state{f = 0},
    Machine2 = Machine1#machine_state{cpu = Cpu1},
    Machine3 = z80_cpu:step(Machine2),
    ?assertEqual(2, z80_cpu:pc(Machine3)).

%% DJNZ Tests

djnz_taken_test() ->
    Machine0 = z80_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#10),  %% DJNZ e
    Mem2 = z80_mem:write_byte(Mem1, 1, 16#FC),  %% -4
    Machine1 = Machine0#machine_state{memory = Mem2},
    Cpu1 = Machine1#machine_state.cpu#cpu_state{b = 2},
    Machine2 = Machine1#machine_state{cpu = Cpu1},
    Machine3 = z80_cpu:step(Machine2),
    ?assertEqual(16#FFFE, z80_cpu:pc(Machine3) band 16#FFFF),
    ?assertEqual(1, Machine3#machine_state.cpu#cpu_state.b),
    ?assertEqual(13, z80_cpu:t_states(Machine3)).

djnz_not_taken_test() ->
    Machine0 = z80_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#10),  %% DJNZ e
    Mem2 = z80_mem:write_byte(Mem1, 1, 16#FC),  %% -4
    Machine1 = Machine0#machine_state{memory = Mem2},
    Cpu1 = Machine1#machine_state.cpu#cpu_state{b = 1},
    Machine2 = Machine1#machine_state{cpu = Cpu1},
    Machine3 = z80_cpu:step(Machine2),
    ?assertEqual(2, z80_cpu:pc(Machine3)),
    ?assertEqual(0, Machine3#machine_state.cpu#cpu_state.b),
    ?assertEqual(8, z80_cpu:t_states(Machine3)).

djnz_multiple_test() ->
    Machine0 = z80_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#10),  %% DJNZ e
    Mem2 = z80_mem:write_byte(Mem1, 1, 16#FE),  %% -2 (jump back to DJNZ)
    Machine1 = Machine0#machine_state{memory = Mem2},
    Cpu1 = Machine1#machine_state.cpu#cpu_state{b = 3},
    Machine2 = Machine1#machine_state{cpu = Cpu1},
    %% First DJNZ
    Machine3 = z80_cpu:step(Machine2),
    ?assertEqual(2, Machine3#machine_state.cpu#cpu_state.b),
    ?assertEqual(13, z80_cpu:t_states(Machine3)),
    %% Second DJNZ
    Machine4 = z80_cpu:step(Machine3),
    ?assertEqual(1, Machine4#machine_state.cpu#cpu_state.b),
    ?assertEqual(26, z80_cpu:t_states(Machine4)),
    %% Third DJNZ (not taken)
    Machine5 = z80_cpu:step(Machine4),
    ?assertEqual(2, z80_cpu:pc(Machine5)),
    ?assertEqual(0, Machine5#machine_state.cpu#cpu_state.b),
    ?assertEqual(34, z80_cpu:t_states(Machine5)).

%% JP Tests

jp_nn_test() ->
    Machine0 = z80_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#C3),  %% JP nn
    Mem2 = z80_mem:write_byte(Mem1, 1, 16#00),
    Mem3 = z80_mem:write_byte(Mem2, 2, 16#80),
    Machine1 = Machine0#machine_state{memory = Mem3},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#8000, z80_cpu:pc(Machine2)),
    ?assertEqual(10, z80_cpu:t_states(Machine2)).

jp_hl_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{h = 16#80, l = 16#00},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#E9),  %% JP (HL)
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#8000, z80_cpu:pc(Machine2)),
    ?assertEqual(4, z80_cpu:t_states(Machine2)).

jp_nz_taken_test() ->
    Machine0 = z80_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#C2),  %% JP NZ,nn
    Mem2 = z80_mem:write_byte(Mem1, 1, 16#00),
    Mem3 = z80_mem:write_byte(Mem2, 2, 16#80),
    Machine1 = Machine0#machine_state{memory = Mem3},
    Cpu1 = Machine1#machine_state.cpu#cpu_state{f = 0},
    Machine2 = Machine1#machine_state{cpu = Cpu1},
    Machine3 = z80_cpu:step(Machine2),
    ?assertEqual(16#8000, z80_cpu:pc(Machine3)),
    ?assertEqual(10, z80_cpu:t_states(Machine3)).

jp_nz_not_taken_test() ->
    Machine0 = z80_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#C2),  %% JP NZ,nn
    Mem2 = z80_mem:write_byte(Mem1, 1, 16#00),
    Mem3 = z80_mem:write_byte(Mem2, 2, 16#80),
    Machine1 = Machine0#machine_state{memory = Mem3},
    Cpu1 = Machine1#machine_state.cpu#cpu_state{f = 16#40},
    Machine2 = Machine1#machine_state{cpu = Cpu1},
    Machine3 = z80_cpu:step(Machine2),
    ?assertEqual(3, z80_cpu:pc(Machine3)),
    ?assertEqual(10, z80_cpu:t_states(Machine3)).

jp_z_taken_test() ->
    Machine0 = z80_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#CA),  %% JP Z,nn
    Mem2 = z80_mem:write_byte(Mem1, 1, 16#00),
    Mem3 = z80_mem:write_byte(Mem2, 2, 16#80),
    Machine1 = Machine0#machine_state{memory = Mem3},
    Cpu1 = Machine1#machine_state.cpu#cpu_state{f = 16#40},
    Machine2 = Machine1#machine_state{cpu = Cpu1},
    Machine3 = z80_cpu:step(Machine2),
    ?assertEqual(16#8000, z80_cpu:pc(Machine3)).

jp_nc_taken_test() ->
    Machine0 = z80_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#D2),  %% JP NC,nn
    Mem2 = z80_mem:write_byte(Mem1, 1, 16#00),
    Mem3 = z80_mem:write_byte(Mem2, 2, 16#80),
    Machine1 = Machine0#machine_state{memory = Mem3},
    Cpu1 = Machine1#machine_state.cpu#cpu_state{f = 0},
    Machine2 = Machine1#machine_state{cpu = Cpu1},
    Machine3 = z80_cpu:step(Machine2),
    ?assertEqual(16#8000, z80_cpu:pc(Machine3)).

jp_c_taken_test() ->
    Machine0 = z80_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#DA),  %% JP C,nn
    Mem2 = z80_mem:write_byte(Mem1, 1, 16#00),
    Mem3 = z80_mem:write_byte(Mem2, 2, 16#80),
    Machine1 = Machine0#machine_state{memory = Mem3},
    Cpu1 = Machine1#machine_state.cpu#cpu_state{f = 1},
    Machine2 = Machine1#machine_state{cpu = Cpu1},
    Machine3 = z80_cpu:step(Machine2),
    ?assertEqual(16#8000, z80_cpu:pc(Machine3)).

jp_po_taken_test() ->
    Machine0 = z80_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#E2),  %% JP PO,nn
    Mem2 = z80_mem:write_byte(Mem1, 1, 16#00),
    Mem3 = z80_mem:write_byte(Mem2, 2, 16#80),
    Machine1 = Machine0#machine_state{memory = Mem3},
    Cpu1 = Machine1#machine_state.cpu#cpu_state{f = 0},
    Machine2 = Machine1#machine_state{cpu = Cpu1},
    Machine3 = z80_cpu:step(Machine2),
    ?assertEqual(16#8000, z80_cpu:pc(Machine3)).

jp_pe_taken_test() ->
    Machine0 = z80_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#EA),  %% JP PE,nn
    Mem2 = z80_mem:write_byte(Mem1, 1, 16#00),
    Mem3 = z80_mem:write_byte(Mem2, 2, 16#80),
    Machine1 = Machine0#machine_state{memory = Mem3},
    Cpu1 = Machine1#machine_state.cpu#cpu_state{f = 16#04},
    Machine2 = Machine1#machine_state{cpu = Cpu1},
    Machine3 = z80_cpu:step(Machine2),
    ?assertEqual(16#8000, z80_cpu:pc(Machine3)).

jp_p_taken_test() ->
    Machine0 = z80_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#F2),  %% JP P,nn
    Mem2 = z80_mem:write_byte(Mem1, 1, 16#00),
    Mem3 = z80_mem:write_byte(Mem2, 2, 16#80),
    Machine1 = Machine0#machine_state{memory = Mem3},
    Cpu1 = Machine1#machine_state.cpu#cpu_state{f = 0},
    Machine2 = Machine1#machine_state{cpu = Cpu1},
    Machine3 = z80_cpu:step(Machine2),
    ?assertEqual(16#8000, z80_cpu:pc(Machine3)).

jp_m_taken_test() ->
    Machine0 = z80_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#FA),  %% JP M,nn
    Mem2 = z80_mem:write_byte(Mem1, 1, 16#00),
    Mem3 = z80_mem:write_byte(Mem2, 2, 16#80),
    Machine1 = Machine0#machine_state{memory = Mem3},
    Cpu1 = Machine1#machine_state.cpu#cpu_state{f = 16#80},
    Machine2 = Machine1#machine_state{cpu = Cpu1},
    Machine3 = z80_cpu:step(Machine2),
    ?assertEqual(16#8000, z80_cpu:pc(Machine3)).

%% CALL Tests

call_nn_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{sp = 16#1000},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#CD),  %% CALL nn
    Mem2 = z80_mem:write_byte(Mem1, 1, 16#00),
    Mem3 = z80_mem:write_byte(Mem2, 2, 16#80),
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem3},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#8000, z80_cpu:pc(Machine2)),
    ?assertEqual(16#0FFE, Machine2#machine_state.cpu#cpu_state.sp),
    ?assertEqual(16#03, z80_emulator:read_byte(Machine2, 16#0FFE)),  %% Low byte of PC=3
    ?assertEqual(16#00, z80_emulator:read_byte(Machine2, 16#0FFF)).  %% High byte of PC=3

call_nz_taken_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{sp = 16#1000, f = 0},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#C4),  %% CALL NZ,nn
    Mem2 = z80_mem:write_byte(Mem1, 1, 16#00),
    Mem3 = z80_mem:write_byte(Mem2, 2, 16#80),
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem3},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#8000, z80_cpu:pc(Machine2)),
    ?assertEqual(16#0FFE, Machine2#machine_state.cpu#cpu_state.sp).

call_nz_not_taken_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{sp = 16#1000, f = 16#40},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#C4),  %% CALL NZ,nn
    Mem2 = z80_mem:write_byte(Mem1, 1, 16#00),
    Mem3 = z80_mem:write_byte(Mem2, 2, 16#80),
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem3},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(3, z80_cpu:pc(Machine2)),
    ?assertEqual(16#1000, Machine2#machine_state.cpu#cpu_state.sp).

call_z_taken_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{sp = 16#1000, f = 16#40},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#CC),  %% CALL Z,nn
    Mem2 = z80_mem:write_byte(Mem1, 1, 16#00),
    Mem3 = z80_mem:write_byte(Mem2, 2, 16#80),
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem3},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#8000, z80_cpu:pc(Machine2)).

call_nc_taken_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{sp = 16#1000, f = 0},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#D4),  %% CALL NC,nn
    Mem2 = z80_mem:write_byte(Mem1, 1, 16#00),
    Mem3 = z80_mem:write_byte(Mem2, 2, 16#80),
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem3},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#8000, z80_cpu:pc(Machine2)).

call_c_taken_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{sp = 16#1000, f = 1},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#DC),  %% CALL C,nn
    Mem2 = z80_mem:write_byte(Mem1, 1, 16#00),
    Mem3 = z80_mem:write_byte(Mem2, 2, 16#80),
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem3},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#8000, z80_cpu:pc(Machine2)).

call_po_taken_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{sp = 16#1000, f = 0},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#E4),  %% CALL PO,nn
    Mem2 = z80_mem:write_byte(Mem1, 1, 16#00),
    Mem3 = z80_mem:write_byte(Mem2, 2, 16#80),
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem3},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#8000, z80_cpu:pc(Machine2)).

call_pe_taken_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{sp = 16#1000, f = 16#04},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#EC),  %% CALL PE,nn
    Mem2 = z80_mem:write_byte(Mem1, 1, 16#00),
    Mem3 = z80_mem:write_byte(Mem2, 2, 16#80),
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem3},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#8000, z80_cpu:pc(Machine2)).

call_p_taken_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{sp = 16#1000, f = 0},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#F4),  %% CALL P,nn
    Mem2 = z80_mem:write_byte(Mem1, 1, 16#00),
    Mem3 = z80_mem:write_byte(Mem2, 2, 16#80),
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem3},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#8000, z80_cpu:pc(Machine2)).

call_m_taken_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{sp = 16#1000, f = 16#80},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#FC),  %% CALL M,nn
    Mem2 = z80_mem:write_byte(Mem1, 1, 16#00),
    Mem3 = z80_mem:write_byte(Mem2, 2, 16#80),
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem3},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#8000, z80_cpu:pc(Machine2)).