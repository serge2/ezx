-module(z80_cpu_main_int_tests).

-include("z80_records.hrl").
-include_lib("eunit/include/eunit.hrl").

%% --- Interrupt / DI / EI Tests ---

interrupt_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{iff1 = 1, iff2 = 1, im = 1, pc = 16#1000},
    Cpu2 = test_helpers:write_mem(Cpu1, 16#0038, 16#00),  %% NOP at IRQ vector
    Cpu3 = z80_cpu:request_interrupt(Cpu2, int),
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#0038, z80_cpu:pc(Cpu4)),
    ?assertEqual(0, Cpu4#cpu_state.iff1),
    ?assertEqual(0, Cpu4#cpu_state.iff2),
    ?assertEqual(13, z80_cpu:t_states(Cpu4)).

nmi_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{iff1 = 1, iff2 = 1, pc = 16#1000},
    Cpu2 = test_helpers:write_mem(Cpu1, 16#0066, 16#00),  %% NOP at NMI vector
    Cpu3 = z80_cpu:request_interrupt(Cpu2, nmi),
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#0066, z80_cpu:pc(Cpu4)),
    ?assertEqual(0, Cpu4#cpu_state.iff1),
    ?assertEqual(1, Cpu4#cpu_state.iff2),
    ?assertEqual(11, z80_cpu:t_states(Cpu4)).

nmi_does_not_require_iff1_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{iff1 = 0, iff2 = 0, pc = 16#1000},
    Cpu2 = test_helpers:write_mem(Cpu1, 16#0066, 16#00),  %% NOP at NMI vector
    Cpu3 = z80_cpu:request_interrupt(Cpu2, nmi),
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#0066, z80_cpu:pc(Cpu4)).

irq_ignored_when_iff1_zero_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{iff1 = 0, iff2 = 0, pc = 16#1000},
    Cpu2 = z80_cpu:request_interrupt(Cpu1, int),
    Cpu3 = z80_cpu:step(Cpu2),
    %% IRQ should be ignored, continue with next instruction (NOP at 0x1000)
    ?assertEqual(16#1001, z80_cpu:pc(Cpu3)),
    ?assertEqual(4, z80_cpu:t_states(Cpu3)).

di_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{iff1 = 1, iff2 = 1},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#F3),  %% DI
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(0, Cpu3#cpu_state.iff1),
    ?assertEqual(0, Cpu3#cpu_state.iff2),
    ?assertEqual(4, z80_cpu:t_states(Cpu3)).

ei_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{iff1 = 0, iff2 = 0},
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#FB),  %% EI
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(1, Cpu3#cpu_state.iff1),
    ?assertEqual(1, Cpu3#cpu_state.iff2),
    ?assertEqual(4, z80_cpu:t_states(Cpu3)).

ei_blocks_interrupt_until_next_instruction_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{iff1 = 0, iff2 = 0, pc = 16#1000},
    Cpu2 = test_helpers:write_mem(Cpu1, 16#0038, 16#00),  %% NOP at IRQ vector
    Cpu3 = test_helpers:write_mem(Cpu2, 16#1000, 16#FB),  %% EI
    Cpu4 = test_helpers:write_mem(Cpu3, 16#1001, 16#00),  %% NOP
    Cpu5 = z80_cpu:request_interrupt(Cpu4, int),
    Cpu6 = z80_cpu:step(Cpu5),
    %% EI executed, interrupt should be pending but blocked until next instruction
    ?assertEqual(16#1001, z80_cpu:pc(Cpu6)),
    Cpu7 = z80_cpu:step(Cpu6),
    %% NOP executes, ei_block cleared, interrupt still pending
    ?assertEqual(16#1002, z80_cpu:pc(Cpu7)),
    Cpu8 = z80_cpu:step(Cpu7),
    %% Interrupt fires before next instruction fetch
    ?assertEqual(16#0038, z80_cpu:pc(Cpu8)).

di_ei_timing_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#F3),  %% DI
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#FB),  %% EI
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(4, z80_cpu:t_states(Cpu3)),
    ?assertEqual(0, Cpu3#cpu_state.iff1),
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(8, z80_cpu:t_states(Cpu4)),
    ?assertEqual(1, Cpu4#cpu_state.iff1).

%% --- R Register Tests ---

r_register_increments_on_m1_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{r = 0},
    Cpu2 = z80_cpu:step(Cpu1),
    ?assertEqual(1, Cpu2#cpu_state.r).

r_register_preserves_bit7_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{r = 16#80},
    Cpu2 = z80_cpu:step(Cpu1),
    ?assertEqual(16#81, Cpu2#cpu_state.r).

r_register_wraps_at_7bits_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{r = 16#FF},
    Cpu2 = z80_cpu:step(Cpu1),
    ?assertEqual(16#80, Cpu2#cpu_state.r).

r_register_prefix_cb_increments_twice_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{r = 0},
    Cpu2 = test_helpers:load_program(Cpu1, 0, [16#CB, 16#00]),  %% RLC B
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(2, Cpu3#cpu_state.r),
    ?assertEqual(8, z80_cpu:t_states(Cpu3)).

r_register_prefix_ed_increments_twice_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:load_program(Cpu0, 0, [16#ED, 16#47]),  %% LD I,A
    Cpu2 = Cpu1#cpu_state{a = 16#42, r = 0},
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(2, Cpu3#cpu_state.r),
    ?assertEqual(9, z80_cpu:t_states(Cpu3)).

r_register_dd_fd_prefix_increments_once_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:load_program(Cpu0, 0, [16#DD, 16#21, 16#00, 16#40]),  %% LD IX,nn
    Cpu2 = Cpu1#cpu_state{r = 0},
    Cpu3 = z80_cpu:step(Cpu2),
    %% DD prefix fetches 2 opcodes (0xDD then 0x21), so R increments twice
    ?assertEqual(2, Cpu3#cpu_state.r).

%% --- Flag Tests ---

flag_s_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#3C),  %% INC A (16#80 -> 16#81)
    Cpu2 = Cpu1#cpu_state{a = 16#80},
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(?FLAG_S, Cpu3#cpu_state.f band ?FLAG_S).

flag_z_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#3C),  %% INC A (16#FF -> 16#00)
    Cpu2 = Cpu1#cpu_state{a = 16#FF},
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(?FLAG_Z, Cpu3#cpu_state.f band ?FLAG_Z).

flag_h_add_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#C6),  %% ADD A,n
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#01),
    Cpu3 = Cpu2#cpu_state{a = 16#0F},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(?FLAG_H, Cpu4#cpu_state.f band ?FLAG_H).

flag_h_sub_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#D6),  %% SUB n
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#01),
    Cpu3 = Cpu2#cpu_state{a = 16#10},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(?FLAG_H, Cpu4#cpu_state.f band ?FLAG_H).

flag_pv_overflow_add_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#C6),  %% ADD A,n
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#01),  %% 7F + 01 = 80 -> overflow
    Cpu3 = Cpu2#cpu_state{a = 16#7F},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(?FLAG_V, Cpu4#cpu_state.f band ?FLAG_V).

flag_pv_overflow_sub_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#D6),  %% SUB n
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#01),  %% 80 - 01 = 7F -> overflow
    Cpu3 = Cpu2#cpu_state{a = 16#80},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(?FLAG_V, Cpu4#cpu_state.f band ?FLAG_V).

flag_n_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#3D),  %% DEC A
    Cpu2 = Cpu1#cpu_state{a = 16#10},
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(?FLAG_N, Cpu3#cpu_state.f band ?FLAG_N).

flag_c_add_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#C6),  %% ADD A,n
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#01),
    Cpu3 = Cpu2#cpu_state{a = 16#FF},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(?FLAG_C, Cpu4#cpu_state.f band ?FLAG_C).

flag_c_adc_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#CE),  %% ADC A,n
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#00),
    Cpu3 = Cpu2#cpu_state{a = 16#FF, f = ?FLAG_C},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(?FLAG_C, Cpu4#cpu_state.f band ?FLAG_C).

flag_c_sub_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#D6),  %% SUB n
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#01),
    Cpu3 = Cpu2#cpu_state{a = 16#00},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(?FLAG_C, Cpu4#cpu_state.f band ?FLAG_C).

flag_c_sbc_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#DE),  %% SBC A,n
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#00),
    Cpu3 = Cpu2#cpu_state{a = 16#00, f = ?FLAG_C},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(?FLAG_C, Cpu4#cpu_state.f band ?FLAG_C).

%% --- CP Tests ---

cp_sets_flags_correctly_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#B8),  %% CP B
    Cpu2 = Cpu1#cpu_state{a = 16#30, b = 16#10},
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(16#30, Cpu3#cpu_state.a),
    ?assertEqual(0, Cpu3#cpu_state.f band ?FLAG_Z),
    ?assertEqual(?FLAG_N, Cpu3#cpu_state.f band ?FLAG_N),
    ?assertEqual(0, Cpu3#cpu_state.f band ?FLAG_C).

cp_equal_sets_zero_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#B8),  %% CP B
    Cpu2 = Cpu1#cpu_state{a = 16#55, b = 16#55},
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(?FLAG_Z, Cpu3#cpu_state.f band ?FLAG_Z).

cp_carry_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#B8),  %% CP B
    Cpu2 = Cpu1#cpu_state{a = 16#10, b = 16#20},
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(?FLAG_C, Cpu3#cpu_state.f band ?FLAG_C).


%% --- HALT Tests ---

halt_sets_halted_flag_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#76),  %% HALT
    Cpu2 = z80_cpu:step(Cpu1),
    ?assertEqual(true, Cpu2#cpu_state.halted).

halt_nop_loops_without_advancing_pc_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#76),  %% HALT
    Cpu2 = z80_cpu:step(Cpu1),  %% Execute HALT
    Cpu3 = z80_cpu:step(Cpu2),  %% NOP loop while halted
    Cpu4 = z80_cpu:step(Cpu3),
    %% PC stays at 1 (after HALT), each loop adds 4 T-states
    ?assertEqual(1, z80_cpu:pc(Cpu4)),
    ?assertEqual(12, z80_cpu:t_states(Cpu4)).

halt_interrupt_wakes_cpu_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{iff1 = 1, iff2 = 1, im = 1, pc = 16#1000},
    Cpu2 = test_helpers:write_mem(Cpu1, 16#1000, 16#76),  %% HALT
    Cpu3 = test_helpers:write_mem(Cpu2, 16#0038, 16#00),  %% NOP at IRQ vector
    Cpu4 = z80_cpu:step(Cpu3),  %% Execute HALT
    ?assertEqual(true, Cpu4#cpu_state.halted),
    Cpu5 = z80_cpu:request_interrupt(Cpu4, int),
    Cpu6 = z80_cpu:step(Cpu5),  %% INT fires, wakes CPU
    ?assertEqual(false, Cpu6#cpu_state.halted),
    ?assertEqual(16#0038, z80_cpu:pc(Cpu6)).


%% --- IM 0 Tests ---

im0_interrupt_executes_bus_instruction_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{iff1 = 1, iff2 = 1, im = 0, pc = 16#1000},
    Cpu2 = test_helpers:write_mem(Cpu1, 16#0038, 16#00),  %% NOP at RST 38h vector
    Cpu3 = z80_cpu:request_interrupt(Cpu2, int),
    Cpu4 = z80_cpu:step(Cpu3),
    %% IM 0 executes bus instruction (RST 38h = 0xFF by default) -> PC = 0x0038
    ?assertEqual(16#0038, z80_cpu:pc(Cpu4)),
    ?assertEqual(0, Cpu4#cpu_state.iff1),
    ?assertEqual(0, Cpu4#cpu_state.iff2).


%% --- IM 2 Tests ---

im2_interrupt_jumps_via_vector_table_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{iff1 = 1, iff2 = 1, im = 2, i = 16#A0, pc = 16#1000},
    %% Vector table at I*256 + 0xFF = 0xA0FF. Put target 0x2000 there.
    Cpu2 = test_helpers:write_mem(Cpu1, 16#A0FF, 16#00),  %% Low byte of target
    Cpu3 = test_helpers:write_mem(Cpu2, 16#A100, 16#20),  %% High byte of target
    Cpu4 = test_helpers:write_mem(Cpu3, 16#2000, 16#00),  %% NOP at target
    Cpu5 = z80_cpu:request_interrupt(Cpu4, int),
    Cpu6 = z80_cpu:step(Cpu5),
    ?assertEqual(16#2000, z80_cpu:pc(Cpu6)),
    ?assertEqual(0, Cpu6#cpu_state.iff1).
