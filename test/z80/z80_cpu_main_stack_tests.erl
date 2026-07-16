-module(z80_cpu_main_stack_tests).

-include("z80_records.hrl").
-include_lib("eunit/include/eunit.hrl").

%% --- PUSH Tests ---

push_bc_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{b = 16#12, c = 16#34, sp = 16#FF00},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#C5),  %% PUSH BC
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#FEFE, Machine2#machine_state.cpu#cpu_state.sp),
    ?assertEqual(16#34, z80_emulator:read_byte(Machine2, 16#FEFE)),
    ?assertEqual(16#12, z80_emulator:read_byte(Machine2, 16#FEFF)),
    ?assertEqual(11, z80_cpu:t_states(Machine2)).

push_de_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{d = 16#56, e = 16#78, sp = 16#FF00},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#D5),  %% PUSH DE
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#FEFE, Machine2#machine_state.cpu#cpu_state.sp),
    ?assertEqual(16#78, z80_emulator:read_byte(Machine2, 16#FEFE)),
    ?assertEqual(16#56, z80_emulator:read_byte(Machine2, 16#FEFF)).

push_hl_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{h = 16#9A, l = 16#BC, sp = 16#FF00},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#E5),  %% PUSH HL
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#FEFE, Machine2#machine_state.cpu#cpu_state.sp),
    ?assertEqual(16#BC, z80_emulator:read_byte(Machine2, 16#FEFE)),
    ?assertEqual(16#9A, z80_emulator:read_byte(Machine2, 16#FEFF)).

push_af_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{a = 16#DE, f = 16#F0, sp = 16#FF00},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#F5),  %% PUSH AF
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#FEFE, Machine2#machine_state.cpu#cpu_state.sp),
    ?assertEqual(16#F0, z80_emulator:read_byte(Machine2, 16#FEFE)),
    ?assertEqual(16#DE, z80_emulator:read_byte(Machine2, 16#FEFF)).

push_sp_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{sp = 16#1234, b = 0, c = 0},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#F5),  %% PUSH AF (using as placeholder)
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    %% Can't test PUSH SP directly without specific opcode
    ok.

%% --- POP Tests ---

pop_bc_test() ->
    Machine0 = z80_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 16#FEFE, 16#34),
    Mem2 = z80_mem:write_byte(Mem1, 16#FEFF, 16#12),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{sp = 16#FEFE},
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem2},
    Mem3 = z80_mem:write_byte(Mem2, 0, 16#C1),  %% POP BC
    Machine2 = Machine1#machine_state{memory = Mem3},
    Machine3 = z80_cpu:step(Machine2),
    ?assertEqual(16#12, Machine3#machine_state.cpu#cpu_state.b),
    ?assertEqual(16#34, Machine3#machine_state.cpu#cpu_state.c),
    ?assertEqual(16#FF00, Machine3#machine_state.cpu#cpu_state.sp),
    ?assertEqual(10, z80_cpu:t_states(Machine3)).

pop_de_test() ->
    Machine0 = z80_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 16#FEFE, 16#78),
    Mem2 = z80_mem:write_byte(Mem1, 16#FEFF, 16#56),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{sp = 16#FEFE},
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem2},
    Mem3 = z80_mem:write_byte(Mem2, 0, 16#D1),  %% POP DE
    Machine2 = Machine1#machine_state{memory = Mem3},
    Machine3 = z80_cpu:step(Machine2),
    ?assertEqual(16#56, Machine3#machine_state.cpu#cpu_state.d),
    ?assertEqual(16#78, Machine3#machine_state.cpu#cpu_state.e),
    ?assertEqual(16#FF00, Machine3#machine_state.cpu#cpu_state.sp).

pop_hl_test() ->
    Machine0 = z80_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 16#FEFE, 16#BC),
    Mem2 = z80_mem:write_byte(Mem1, 16#FEFF, 16#9A),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{sp = 16#FEFE},
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem2},
    Mem3 = z80_mem:write_byte(Mem2, 0, 16#E1),  %% POP HL
    Machine2 = Machine1#machine_state{memory = Mem3},
    Machine3 = z80_cpu:step(Machine2),
    ?assertEqual(16#9A, Machine3#machine_state.cpu#cpu_state.h),
    ?assertEqual(16#BC, Machine3#machine_state.cpu#cpu_state.l),
    ?assertEqual(16#FF00, Machine3#machine_state.cpu#cpu_state.sp).

pop_af_test() ->
    Machine0 = z80_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 16#FEFE, 16#F0),
    Mem2 = z80_mem:write_byte(Mem1, 16#FEFF, 16#DE),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{sp = 16#FEFE},
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem2},
    Mem3 = z80_mem:write_byte(Mem2, 0, 16#F1),  %% POP AF
    Machine2 = Machine1#machine_state{memory = Mem3},
    Machine3 = z80_cpu:step(Machine2),
    ?assertEqual(16#DE, Machine3#machine_state.cpu#cpu_state.a),
    ?assertEqual(16#F0, Machine3#machine_state.cpu#cpu_state.f),
    ?assertEqual(16#FF00, Machine3#machine_state.cpu#cpu_state.sp).

%% --- RET Tests ---

ret_test() ->
    Machine0 = z80_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 16#FEFE, 16#00),
    Mem2 = z80_mem:write_byte(Mem1, 16#FEFF, 16#80),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{sp = 16#FEFE},
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem2},
    Mem3 = z80_mem:write_byte(Mem2, 0, 16#C9),  %% RET
    Machine2 = Machine1#machine_state{memory = Mem3},
    Machine3 = z80_cpu:step(Machine2),
    ?assertEqual(16#8000, z80_cpu:pc(Machine3)),
    ?assertEqual(16#FF00, Machine3#machine_state.cpu#cpu_state.sp),
    ?assertEqual(10, z80_cpu:t_states(Machine3)).

ret_nz_taken_test() ->
    Machine0 = z80_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 16#FEFE, 16#00),
    Mem2 = z80_mem:write_byte(Mem1, 16#FEFF, 16#80),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{sp = 16#FEFE, f = 0},
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem2},
    Mem3 = z80_mem:write_byte(Mem2, 0, 16#C0),  %% RET NZ
    Machine2 = Machine1#machine_state{memory = Mem3},
    Machine3 = z80_cpu:step(Machine2),
    ?assertEqual(16#8000, z80_cpu:pc(Machine3)),
    ?assertEqual(11, z80_cpu:t_states(Machine3)).

ret_nz_not_taken_test() ->
    Machine0 = z80_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 16#FEFE, 16#00),
    Mem2 = z80_mem:write_byte(Mem1, 16#FEFF, 16#80),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{sp = 16#FEFE, f = 16#40},
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem2},
    Mem3 = z80_mem:write_byte(Mem2, 0, 16#C0),  %% RET NZ
    Machine2 = Machine1#machine_state{memory = Mem3},
    Machine3 = z80_cpu:step(Machine2),
    ?assertEqual(1, z80_cpu:pc(Machine3)),
    ?assertEqual(5, z80_cpu:t_states(Machine3)).

ret_z_taken_test() ->
    Machine0 = z80_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 16#FEFE, 16#00),
    Mem2 = z80_mem:write_byte(Mem1, 16#FEFF, 16#80),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{sp = 16#FEFE, f = 16#40},
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem2},
    Mem3 = z80_mem:write_byte(Mem2, 0, 16#C8),  %% RET Z
    Machine2 = Machine1#machine_state{memory = Mem3},
    Machine3 = z80_cpu:step(Machine2),
    ?assertEqual(16#8000, z80_cpu:pc(Machine3)).

ret_nc_taken_test() ->
    Machine0 = z80_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 16#FEFE, 16#00),
    Mem2 = z80_mem:write_byte(Mem1, 16#FEFF, 16#80),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{sp = 16#FEFE, f = 0},
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem2},
    Mem3 = z80_mem:write_byte(Mem2, 0, 16#D0),  %% RET NC
    Machine2 = Machine1#machine_state{memory = Mem3},
    Machine3 = z80_cpu:step(Machine2),
    ?assertEqual(16#8000, z80_cpu:pc(Machine3)).

ret_c_taken_test() ->
    Machine0 = z80_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 16#FEFE, 16#00),
    Mem2 = z80_mem:write_byte(Mem1, 16#FEFF, 16#80),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{sp = 16#FEFE, f = 1},
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem2},
    Mem3 = z80_mem:write_byte(Mem2, 0, 16#D8),  %% RET C
    Machine2 = Machine1#machine_state{memory = Mem3},
    Machine3 = z80_cpu:step(Machine2),
    ?assertEqual(16#8000, z80_cpu:pc(Machine3)).

ret_po_taken_test() ->
    Machine0 = z80_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 16#FEFE, 16#00),
    Mem2 = z80_mem:write_byte(Mem1, 16#FEFF, 16#80),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{sp = 16#FEFE, f = 0},
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem2},
    Mem3 = z80_mem:write_byte(Mem2, 0, 16#E0),  %% RET PO
    Machine2 = Machine1#machine_state{memory = Mem3},
    Machine3 = z80_cpu:step(Machine2),
    ?assertEqual(16#8000, z80_cpu:pc(Machine3)).

ret_pe_taken_test() ->
    Machine0 = z80_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 16#FEFE, 16#00),
    Mem2 = z80_mem:write_byte(Mem1, 16#FEFF, 16#80),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{sp = 16#FEFE, f = 16#04},
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem2},
    Mem3 = z80_mem:write_byte(Mem2, 0, 16#E8),  %% RET PE
    Machine2 = Machine1#machine_state{memory = Mem3},
    Machine3 = z80_cpu:step(Machine2),
    ?assertEqual(16#8000, z80_cpu:pc(Machine3)).

ret_p_taken_test() ->
    Machine0 = z80_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 16#FEFE, 16#00),
    Mem2 = z80_mem:write_byte(Mem1, 16#FEFF, 16#80),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{sp = 16#FEFE, f = 0},
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem2},
    Mem3 = z80_mem:write_byte(Mem2, 0, 16#F0),  %% RET P
    Machine2 = Machine1#machine_state{memory = Mem3},
    Machine3 = z80_cpu:step(Machine2),
    ?assertEqual(16#8000, z80_cpu:pc(Machine3)).

ret_m_taken_test() ->
    Machine0 = z80_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 16#FEFE, 16#00),
    Mem2 = z80_mem:write_byte(Mem1, 16#FEFF, 16#80),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{sp = 16#FEFE, f = 16#80},
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem2},
    Mem3 = z80_mem:write_byte(Mem2, 0, 16#F8),  %% RET M
    Machine2 = Machine1#machine_state{memory = Mem3},
    Machine3 = z80_cpu:step(Machine2),
    ?assertEqual(16#8000, z80_cpu:pc(Machine3)).

%% RST Tests (already in ret_tests but also stack operations)

rst_00_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{sp = 16#1000, pc = 16#0005},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 16#0005, 16#C7),  %% RST 00h
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#0000, z80_cpu:pc(Machine2)),
    ?assertEqual(16#0FFE, Machine2#machine_state.cpu#cpu_state.sp),
    ?assertEqual(16#06, z80_emulator:read_byte(Machine2, 16#0FFE)),  %% Low byte of pushed PC=6
    ?assertEqual(16#00, z80_emulator:read_byte(Machine2, 16#0FFF)).  %% High byte of pushed PC=6