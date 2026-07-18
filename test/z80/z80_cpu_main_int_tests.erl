-module(z80_cpu_main_int_tests).

-include("z80_records.hrl").
-include_lib("eunit/include/eunit.hrl").

%% --- Interrupt / DI / EI Tests ---

interrupt_test() ->
    Machine0 = ezx_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{iff1 = 1, iff2 = 1, pc = 16#1000},
    Machine1 = Machine0#machine_state{cpu = Cpu0},
    Machine2 = z80_cpu:request_interrupt(Machine1, irq),
    Machine3 = z80_cpu:step(Machine2),
    ?assertEqual(16#0038, z80_cpu:pc(Machine3)),
    Cpu3 = Machine3#machine_state.cpu,
    ?assertEqual(0, Cpu3#cpu_state.iff1),
    ?assertEqual(0, Cpu3#cpu_state.iff2),
    ?assertEqual(13, z80_cpu:t_states(Machine3)).

nmi_test() ->
    Machine0 = ezx_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{iff1 = 1, iff2 = 1, pc = 16#1000},
    Machine1 = Machine0#machine_state{cpu = Cpu0},
    Machine2 = z80_cpu:request_interrupt(Machine1, nmi),
    Machine3 = z80_cpu:step(Machine2),
    ?assertEqual(16#0066, z80_cpu:pc(Machine3)),
    Cpu3 = Machine3#machine_state.cpu,
    ?assertEqual(0, Cpu3#cpu_state.iff1),
    ?assertEqual(1, Cpu3#cpu_state.iff2),
    ?assertEqual(11, z80_cpu:t_states(Machine3)).

nmi_does_not_require_iff1_test() ->
    Machine0 = ezx_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{iff1 = 0, iff2 = 0, pc = 16#1000},
    Machine1 = Machine0#machine_state{cpu = Cpu0},
    Machine2 = z80_cpu:request_interrupt(Machine1, nmi),
    Machine3 = z80_cpu:step(Machine2),
    ?assertEqual(16#0066, z80_cpu:pc(Machine3)).

irq_ignored_when_iff1_zero_test() ->
    Machine0 = ezx_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{iff1 = 0, iff2 = 0, pc = 16#1000},
    Machine1 = Machine0#machine_state{cpu = Cpu0},
    Machine2 = z80_cpu:request_interrupt(Machine1, irq),
    Machine3 = z80_cpu:step(Machine2),
    %% IRQ should be ignored, continue with next instruction (NOP at 0x1000)
    ?assertEqual(16#1001, z80_cpu:pc(Machine3)),
    ?assertEqual(4, z80_cpu:t_states(Machine3)).

di_test() ->
    Machine0 = ezx_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{iff1 = 1, iff2 = 1},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_memory_48:cpu_write_byte(Mem0, 0, 16#F3),  %% DI
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(0, Machine2#machine_state.cpu#cpu_state.iff1),
    ?assertEqual(0, Machine2#machine_state.cpu#cpu_state.iff2),
    ?assertEqual(4, z80_cpu:t_states(Machine2)).

ei_test() ->
    Machine0 = ezx_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{iff1 = 0, iff2 = 0},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_memory_48:cpu_write_byte(Mem0, 0, 16#FB),  %% EI
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(1, Machine2#machine_state.cpu#cpu_state.iff1),
    ?assertEqual(1, Machine2#machine_state.cpu#cpu_state.iff2),
    ?assertEqual(4, z80_cpu:t_states(Machine2)).

ei_blocks_interrupt_until_next_instruction_test() ->
    Machine0 = ezx_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{iff1 = 0, iff2 = 0, pc = 16#1000},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_memory_48:cpu_write_byte(Mem0, 16#1000, 16#FB),  %% EI
    Mem2 = ezx_memory_48:cpu_write_byte(Mem1, 16#1001, 16#00),  %% NOP
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem2},
    Machine2 = z80_cpu:request_interrupt(Machine1, irq),
    Machine3 = z80_cpu:step(Machine2),
    %% EI executed, interrupt should be pending but blocked until next instruction
    ?assertEqual(16#1001, z80_cpu:pc(Machine3)),
    Machine4 = z80_cpu:step(Machine3),
    %% NOP executes, ei_block cleared, interrupt still pending
    ?assertEqual(16#1002, z80_cpu:pc(Machine4)),
    Machine5 = z80_cpu:step(Machine4),
    %% Interrupt fires before next instruction fetch
    ?assertEqual(16#0038, z80_cpu:pc(Machine5)).

di_ei_timing_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_memory_48:cpu_write_byte(Mem0, 0, 16#F3),  %% DI
    Mem2 = ezx_memory_48:cpu_write_byte(Mem1, 1, 16#FB),  %% EI
    Machine1 = Machine0#machine_state{memory = Mem2},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(4, z80_cpu:t_states(Machine2)),
    ?assertEqual(0, Machine2#machine_state.cpu#cpu_state.iff1),
    Machine3 = z80_cpu:step(Machine2),
    ?assertEqual(8, z80_cpu:t_states(Machine3)),
    ?assertEqual(1, Machine3#machine_state.cpu#cpu_state.iff1).

%% --- R Register Tests ---

r_register_increments_on_m1_test() ->
    Machine0 = ezx_emulator:init(),
    Machine1 = z80_cpu:step(Machine0),
    Cpu1 = Machine1#machine_state.cpu,
    ?assertEqual(1, Cpu1#cpu_state.r).

r_register_preserves_bit7_test() ->
    Machine0 = ezx_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{r = 16#80},
    Machine1 = Machine0#machine_state{cpu = Cpu0},
    Machine2 = z80_cpu:step(Machine1),
    Cpu2 = Machine2#machine_state.cpu,
    ?assertEqual(16#81, Cpu2#cpu_state.r).

r_register_wraps_at_7bits_test() ->
    Machine0 = ezx_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{r = 16#FF},
    Machine1 = Machine0#machine_state{cpu = Cpu0},
    Machine2 = z80_cpu:step(Machine1),
    Cpu2 = Machine2#machine_state.cpu,
    ?assertEqual(16#80, Cpu2#cpu_state.r).

r_register_prefix_cb_increments_twice_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_memory_48:cpu_write_byte(Mem0, 0, 16#CB),
    Mem2 = ezx_memory_48:cpu_write_byte(Mem1, 1, 16#00),  %% RLC B
    Machine1 = Machine0#machine_state{memory = Mem2},
    Machine2 = z80_cpu:step(Machine1),
    Cpu2 = Machine2#machine_state.cpu,
    ?assertEqual(2, Cpu2#cpu_state.r),
    ?assertEqual(8, z80_cpu:t_states(Machine2)).

r_register_prefix_ed_increments_twice_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_memory_48:cpu_write_byte(Mem0, 0, 16#ED),
    Mem2 = ezx_memory_48:cpu_write_byte(Mem1, 1, 16#47),  %% LD I,A
    Machine1 = Machine0#machine_state{memory = Mem2},
    Cpu1 = Machine1#machine_state.cpu#cpu_state{a = 16#42, r = 0},
    Machine2 = Machine1#machine_state{cpu = Cpu1},
    Machine3 = z80_cpu:step(Machine2),
    Cpu3 = Machine3#machine_state.cpu,
    ?assertEqual(2, Cpu3#cpu_state.r),
    ?assertEqual(9, z80_cpu:t_states(Machine3)).

r_register_dd_fd_prefix_increments_once_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_memory_48:cpu_write_byte(Mem0, 0, 16#DD),
    Mem2 = ezx_memory_48:cpu_write_byte(Mem1, 1, 16#21),  %% LD IX,nn
    Mem3 = ezx_memory_48:cpu_write_byte(Mem2, 2, 16#00),
    Mem4 = ezx_memory_48:cpu_write_byte(Mem3, 3, 16#40),
    Machine1 = Machine0#machine_state{memory = Mem4},
    Cpu1 = Machine1#machine_state.cpu#cpu_state{r = 0},
    Machine2 = Machine1#machine_state{cpu = Cpu1},
    Machine3 = z80_cpu:step(Machine2),
    Cpu3 = Machine3#machine_state.cpu,
    %% DD prefix fetches 2 opcodes (0xDD then 0x21), so R increments twice
    ?assertEqual(2, Cpu3#cpu_state.r).

%% --- Flag Tests ---

flag_s_test() ->
    Machine0 = ezx_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{a = 16#80},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_memory_48:cpu_write_byte(Mem0, 0, 16#3C),  %% INC A (16#80 -> 16#81)
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(?FLAG_S, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_S).

flag_z_test() ->
    Machine0 = ezx_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{a = 16#FF},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_memory_48:cpu_write_byte(Mem0, 0, 16#3C),  %% INC A (16#FF -> 16#00)
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(?FLAG_Z, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_Z).

flag_h_add_test() ->
    Machine0 = ezx_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{a = 16#0F},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_memory_48:cpu_write_byte(Mem0, 0, 16#C6),  %% ADD A,n
    Mem2 = ezx_memory_48:cpu_write_byte(Mem1, 1, 16#01),
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem2},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(?FLAG_H, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_H).

flag_h_sub_test() ->
    Machine0 = ezx_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{a = 16#10},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_memory_48:cpu_write_byte(Mem0, 0, 16#D6),  %% SUB n
    Mem2 = ezx_memory_48:cpu_write_byte(Mem1, 1, 16#01),
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem2},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(?FLAG_H, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_H).

flag_pv_overflow_add_test() ->
    Machine0 = ezx_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{a = 16#7F},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_memory_48:cpu_write_byte(Mem0, 0, 16#C6),  %% ADD A,n
    Mem2 = ezx_memory_48:cpu_write_byte(Mem1, 1, 16#01),  %% 7F + 01 = 80 -> overflow
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem2},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(?FLAG_V, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_V).

flag_pv_overflow_sub_test() ->
    Machine0 = ezx_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{a = 16#80},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_memory_48:cpu_write_byte(Mem0, 0, 16#D6),  %% SUB n
    Mem2 = ezx_memory_48:cpu_write_byte(Mem1, 1, 16#01),  %% 80 - 01 = 7F -> overflow
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem2},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(?FLAG_V, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_V).

flag_n_test() ->
    Machine0 = ezx_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{a = 16#10},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_memory_48:cpu_write_byte(Mem0, 0, 16#3D),  %% DEC A
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(?FLAG_N, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_N).

flag_c_add_test() ->
    Machine0 = ezx_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{a = 16#FF},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_memory_48:cpu_write_byte(Mem0, 0, 16#C6),  %% ADD A,n
    Mem2 = ezx_memory_48:cpu_write_byte(Mem1, 1, 16#01),
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem2},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(?FLAG_C, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_C).

flag_c_adc_test() ->
    Machine0 = ezx_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{a = 16#FF, f = ?FLAG_C},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_memory_48:cpu_write_byte(Mem0, 0, 16#CE),  %% ADC A,n
    Mem2 = ezx_memory_48:cpu_write_byte(Mem1, 1, 16#00),
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem2},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(?FLAG_C, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_C).

flag_c_sub_test() ->
    Machine0 = ezx_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{a = 16#00},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_memory_48:cpu_write_byte(Mem0, 0, 16#D6),  %% SUB n
    Mem2 = ezx_memory_48:cpu_write_byte(Mem1, 1, 16#01),
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem2},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(?FLAG_C, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_C).

flag_c_sbc_test() ->
    Machine0 = ezx_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{a = 16#00, f = ?FLAG_C},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_memory_48:cpu_write_byte(Mem0, 0, 16#DE),  %% SBC A,n
    Mem2 = ezx_memory_48:cpu_write_byte(Mem1, 1, 16#00),
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem2},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(?FLAG_C, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_C).

%% --- CP Tests ---

cp_sets_flags_correctly_test() ->
    Machine0 = ezx_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{a = 16#30, b = 16#10},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_memory_48:cpu_write_byte(Mem0, 0, 16#B8),  %% CP B
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#30, Machine2#machine_state.cpu#cpu_state.a),
    ?assertEqual(0, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_Z),
    ?assertEqual(?FLAG_N, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_N),
    ?assertEqual(0, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_C).

cp_equal_sets_zero_test() ->
    Machine0 = ezx_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{a = 16#55, b = 16#55},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_memory_48:cpu_write_byte(Mem0, 0, 16#B8),  %% CP B
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(?FLAG_Z, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_Z).

cp_carry_test() ->
    Machine0 = ezx_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{a = 16#10, b = 16#20},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_memory_48:cpu_write_byte(Mem0, 0, 16#B8),  %% CP B
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(?FLAG_C, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_C).