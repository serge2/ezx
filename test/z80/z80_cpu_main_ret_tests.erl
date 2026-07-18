-module(z80_cpu_main_ret_tests).

-include("z80_records.hrl").
-include_lib("eunit/include/eunit.hrl").

%% --- RET Tests ---

ret_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_memory_48:cpu_write_byte(Mem0, 0, 16#C9),  %% RET
    Mem2 = ezx_memory_48:cpu_write_byte(Mem1, 16#1000, 16#00),
    Mem3 = ezx_memory_48:cpu_write_byte(Mem2, 16#1001, 16#80),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{sp = 16#1000},
    Machine1 = Machine0#machine_state{memory = Mem3, cpu = Cpu0},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#8000, z80_cpu:pc(Machine2)),
    ?assertEqual(16#1002, Machine2#machine_state.cpu#cpu_state.sp),
    ?assertEqual(10, z80_cpu:t_states(Machine2)).

ret_nz_taken_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_memory_48:cpu_write_byte(Mem0, 0, 16#C0),  %% RET NZ
    Mem2 = ezx_memory_48:cpu_write_byte(Mem1, 16#1000, 16#00),
    Mem3 = ezx_memory_48:cpu_write_byte(Mem2, 16#1001, 16#80),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{sp = 16#1000, f = 0},
    Machine1 = Machine0#machine_state{memory = Mem3, cpu = Cpu0},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#8000, z80_cpu:pc(Machine2)),
    ?assertEqual(11, z80_cpu:t_states(Machine2)).

ret_nz_not_taken_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_memory_48:cpu_write_byte(Mem0, 0, 16#C0),  %% RET NZ
    Cpu0 = Machine0#machine_state.cpu#cpu_state{sp = 16#1000, f = 16#40},
    Machine1 = Machine0#machine_state{memory = Mem1, cpu = Cpu0},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(1, z80_cpu:pc(Machine2)),
    ?assertEqual(5, z80_cpu:t_states(Machine2)).

ret_z_taken_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_memory_48:cpu_write_byte(Mem0, 0, 16#C8),  %% RET Z
    Mem2 = ezx_memory_48:cpu_write_byte(Mem1, 16#1000, 16#00),
    Mem3 = ezx_memory_48:cpu_write_byte(Mem2, 16#1001, 16#80),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{sp = 16#1000, f = 16#40},
    Machine1 = Machine0#machine_state{memory = Mem3, cpu = Cpu0},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#8000, z80_cpu:pc(Machine2)).

ret_nc_taken_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_memory_48:cpu_write_byte(Mem0, 0, 16#D0),  %% RET NC
    Mem2 = ezx_memory_48:cpu_write_byte(Mem1, 16#1000, 16#00),
    Mem3 = ezx_memory_48:cpu_write_byte(Mem2, 16#1001, 16#80),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{sp = 16#1000, f = 0},
    Machine1 = Machine0#machine_state{memory = Mem3, cpu = Cpu0},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#8000, z80_cpu:pc(Machine2)).

ret_c_taken_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_memory_48:cpu_write_byte(Mem0, 0, 16#D8),  %% RET C
    Mem2 = ezx_memory_48:cpu_write_byte(Mem1, 16#1000, 16#00),
    Mem3 = ezx_memory_48:cpu_write_byte(Mem2, 16#1001, 16#80),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{sp = 16#1000, f = 1},
    Machine1 = Machine0#machine_state{memory = Mem3, cpu = Cpu0},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#8000, z80_cpu:pc(Machine2)).

ret_po_taken_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_memory_48:cpu_write_byte(Mem0, 0, 16#E0),  %% RET PO
    Mem2 = ezx_memory_48:cpu_write_byte(Mem1, 16#1000, 16#00),
    Mem3 = ezx_memory_48:cpu_write_byte(Mem2, 16#1001, 16#80),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{sp = 16#1000, f = 0},
    Machine1 = Machine0#machine_state{memory = Mem3, cpu = Cpu0},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#8000, z80_cpu:pc(Machine2)).

ret_pe_taken_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_memory_48:cpu_write_byte(Mem0, 0, 16#E8),  %% RET PE
    Mem2 = ezx_memory_48:cpu_write_byte(Mem1, 16#1000, 16#00),
    Mem3 = ezx_memory_48:cpu_write_byte(Mem2, 16#1001, 16#80),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{sp = 16#1000, f = 16#04},
    Machine1 = Machine0#machine_state{memory = Mem3, cpu = Cpu0},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#8000, z80_cpu:pc(Machine2)).

ret_p_taken_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_memory_48:cpu_write_byte(Mem0, 0, 16#F0),  %% RET P
    Mem2 = ezx_memory_48:cpu_write_byte(Mem1, 16#1000, 16#00),
    Mem3 = ezx_memory_48:cpu_write_byte(Mem2, 16#1001, 16#80),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{sp = 16#1000, f = 0},
    Machine1 = Machine0#machine_state{memory = Mem3, cpu = Cpu0},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#8000, z80_cpu:pc(Machine2)).

ret_m_taken_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_memory_48:cpu_write_byte(Mem0, 0, 16#F8),  %% RET M
    Mem2 = ezx_memory_48:cpu_write_byte(Mem1, 16#1000, 16#00),
    Mem3 = ezx_memory_48:cpu_write_byte(Mem2, 16#1001, 16#80),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{sp = 16#1000, f = 16#80},
    Machine1 = Machine0#machine_state{memory = Mem3, cpu = Cpu0},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#8000, z80_cpu:pc(Machine2)).

%% --- RST Tests ---

rst_00_test() ->
    Machine0 = ezx_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{sp = 16#1000},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_memory_48:cpu_write_byte(Mem0, 0, 16#C7),  %% RST 00h
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#0000, z80_cpu:pc(Machine2)),
    ?assertEqual(16#0FFE, Machine2#machine_state.cpu#cpu_state.sp),
    ?assertEqual(16#01, ezx_emulator:read_byte(Machine2, 16#0FFE)),  %% Low byte of pushed PC=1
    ?assertEqual(16#00, ezx_emulator:read_byte(Machine2, 16#0FFF)).  %% High byte of pushed PC=1

rst_08_test() ->
    Machine0 = ezx_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{sp = 16#1000},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_memory_48:cpu_write_byte(Mem0, 0, 16#CF),  %% RST 08h
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#0008, z80_cpu:pc(Machine2)).

rst_10_test() ->
    Machine0 = ezx_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{sp = 16#1000},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_memory_48:cpu_write_byte(Mem0, 0, 16#D7),  %% RST 10h
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#0010, z80_cpu:pc(Machine2)).

rst_18_test() ->
    Machine0 = ezx_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{sp = 16#1000},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_memory_48:cpu_write_byte(Mem0, 0, 16#DF),  %% RST 18h
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#0018, z80_cpu:pc(Machine2)).

rst_20_test() ->
    Machine0 = ezx_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{sp = 16#1000},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_memory_48:cpu_write_byte(Mem0, 0, 16#E7),  %% RST 20h
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#0020, z80_cpu:pc(Machine2)).

rst_28_test() ->
    Machine0 = ezx_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{sp = 16#1000},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_memory_48:cpu_write_byte(Mem0, 0, 16#EF),  %% RST 28h
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#0028, z80_cpu:pc(Machine2)).

rst_30_test() ->
    Machine0 = ezx_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{sp = 16#1000},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_memory_48:cpu_write_byte(Mem0, 0, 16#F7),  %% RST 30h
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#0030, z80_cpu:pc(Machine2)).

rst_38_test() ->
    Machine0 = ezx_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{sp = 16#1000},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_memory_48:cpu_write_byte(Mem0, 0, 16#FF),  %% RST 38h
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#0038, z80_cpu:pc(Machine2)).