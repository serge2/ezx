-module(z80_cpu_tests).

-include("z80_records.hrl").
-include_lib("eunit/include/eunit.hrl").

%% --- Basic Instructions ---

nop_instruction_test() ->
    Machine0 = ezx_emulator:init(),
    Machine1 = z80_cpu:step(Machine0),
    ?assertEqual(1, z80_cpu:pc(Machine1)),
    ?assertEqual(4, z80_cpu:t_states(Machine1)).

ld_bc_nn_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#01),
    Mem2 = ezx_mem:write_byte(Mem1, 1, 16#34),
    Mem3 = ezx_mem:write_byte(Mem2, 2, 16#12),
    Machine1 = Machine0#machine_state{memory = Mem3},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#1234, z80_cpu:get_reg_pair(bc, Machine2#machine_state.cpu)),
    ?assertEqual(3, z80_cpu:pc(Machine2)).

interrupt_test() ->
    Machine0 = ezx_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu,
    Cpu1 = Cpu0#cpu_state{iff1 = 1, iff2 = 1, pc = 16#1000},
    Machine1 = Machine0#machine_state{cpu = Cpu1},
    Machine2 = z80_cpu:request_interrupt(Machine1, irq),
    Machine3 = z80_cpu:step(Machine2),
    ?assertEqual(16#0038, z80_cpu:pc(Machine3)),
    Cpu3 = Machine3#machine_state.cpu,
    ?assertEqual(0, Cpu3#cpu_state.iff1),
    ?assertEqual(0, Cpu3#cpu_state.iff2).

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
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#CB),
    Mem2 = ezx_mem:write_byte(Mem1, 1, 16#00),
    Machine1 = Machine0#machine_state{memory = Mem2},
    Machine2 = z80_cpu:step(Machine1),
    Cpu2 = Machine2#machine_state.cpu,
    ?assertEqual(2, Cpu2#cpu_state.r),
    ?assertEqual(8, z80_cpu:t_states(Machine2)).

r_register_prefix_ed_increments_twice_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#ED), %% LD I, A
    Mem2 = ezx_mem:write_byte(Mem1, 1, 16#47),
    Machine1 = Machine0#machine_state{memory = Mem2},
    Cpu1 = Machine1#machine_state.cpu#cpu_state{a = 16#42, r = 0},
    Machine2 = Machine1#machine_state{cpu = Cpu1},
    Machine3 = z80_cpu:step(Machine2),
    Cpu3 = Machine3#machine_state.cpu,
    ?assertEqual(2, Cpu3#cpu_state.r),
    ?assertEqual(9, z80_cpu:t_states(Machine3)).


%% --- Timing Tests ---

nop_timing_test() ->
    Machine0 = ezx_emulator:init(),
    Machine1 = z80_cpu:step(Machine0),
    ?assertEqual(4, z80_cpu:t_states(Machine1)).

ld_bc_nn_timing_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#01),
    Mem2 = ezx_mem:write_byte(Mem1, 1, 16#34),
    Mem3 = ezx_mem:write_byte(Mem2, 2, 16#12),
    Machine1 = Machine0#machine_state{memory = Mem3},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(10, z80_cpu:t_states(Machine2)).

jr_timing_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#18),
    Mem2 = ezx_mem:write_byte(Mem1, 1, 16#05),
    Machine1 = Machine0#machine_state{memory = Mem2},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(12, z80_cpu:t_states(Machine2)),
    ?assertEqual(7, z80_cpu:pc(Machine2)).

jr_nz_taken_timing_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#20),
    Mem2 = ezx_mem:write_byte(Mem1, 1, 16#05),
    Machine1 = Machine0#machine_state{memory = Mem2},
    Cpu1 = Machine1#machine_state.cpu#cpu_state{f = 0},
    Machine2 = Machine1#machine_state{cpu = Cpu1},
    Machine3 = z80_cpu:step(Machine2),
    ?assertEqual(12, z80_cpu:t_states(Machine3)),
    ?assertEqual(7, z80_cpu:pc(Machine3)).

jr_nz_not_taken_timing_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#20),
    Mem2 = ezx_mem:write_byte(Mem1, 1, 16#05),
    Machine1 = Machine0#machine_state{memory = Mem2},
    Cpu1 = Machine1#machine_state.cpu#cpu_state{f = 16#40},
    Machine2 = Machine1#machine_state{cpu = Cpu1},
    Machine3 = z80_cpu:step(Machine2),
    ?assertEqual(7, z80_cpu:t_states(Machine3)),
    ?assertEqual(2, z80_cpu:pc(Machine3)).

djnz_timing_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#10),
    Mem2 = ezx_mem:write_byte(Mem1, 1, 16#FC),
    Machine1 = Machine0#machine_state{memory = Mem2},
    Cpu1 = Machine1#machine_state.cpu#cpu_state{b = 2},
    Machine2 = Machine1#machine_state{cpu = Cpu1},
    Machine3 = z80_cpu:step(Machine2),
    ?assertEqual(13, z80_cpu:t_states(Machine3)),
    ?assertEqual(16#FFFE, z80_cpu:pc(Machine3) band 16#FFFF).

djnz_not_taken_timing_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#10),
    Mem2 = ezx_mem:write_byte(Mem1, 1, 16#FC),
    Machine1 = Machine0#machine_state{memory = Mem2},
    Cpu1 = Machine1#machine_state.cpu#cpu_state{b = 1},
    Machine2 = Machine1#machine_state{cpu = Cpu1},
    Machine3 = z80_cpu:step(Machine2),
    ?assertEqual(8, z80_cpu:t_states(Machine3)),
    ?assertEqual(2, z80_cpu:pc(Machine3)).

jp_cc_timing_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#C2),
    Mem2 = ezx_mem:write_byte(Mem1, 1, 16#00),
    Mem3 = ezx_mem:write_byte(Mem2, 2, 16#80),
    Machine1 = Machine0#machine_state{memory = Mem3},
    Cpu1 = Machine1#machine_state.cpu#cpu_state{f = 0},
    Machine2 = Machine1#machine_state{cpu = Cpu1},
    Machine3 = z80_cpu:step(Machine2),
    ?assertEqual(10, z80_cpu:t_states(Machine3)),
    ?assertEqual(16#8000, z80_cpu:pc(Machine3)).

jp_cc_not_taken_timing_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#C2),
    Mem2 = ezx_mem:write_byte(Mem1, 1, 16#00),
    Mem3 = ezx_mem:write_byte(Mem2, 2, 16#80),
    Machine1 = Machine0#machine_state{memory = Mem3},
    Cpu1 = Machine1#machine_state.cpu#cpu_state{f = 16#40},
    Machine2 = Machine1#machine_state{cpu = Cpu1},
    Machine3 = z80_cpu:step(Machine2),
    ?assertEqual(10, z80_cpu:t_states(Machine3)),
    ?assertEqual(3, z80_cpu:pc(Machine3)).

call_cc_timing_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#C4),
    Mem2 = ezx_mem:write_byte(Mem1, 1, 16#00),
    Mem3 = ezx_mem:write_byte(Mem2, 2, 16#80),
    Machine1 = Machine0#machine_state{memory = Mem3},
    Cpu1 = Machine1#machine_state.cpu#cpu_state{f = 0, sp = 16#1000},
    Machine2 = Machine1#machine_state{cpu = Cpu1},
    Machine3 = z80_cpu:step(Machine2),
    ?assertEqual(17, z80_cpu:t_states(Machine3)),
    ?assertEqual(16#8000, z80_cpu:pc(Machine3)).

call_cc_not_taken_timing_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#C4),
    Mem2 = ezx_mem:write_byte(Mem1, 1, 16#00),
    Mem3 = ezx_mem:write_byte(Mem2, 2, 16#80),
    Machine1 = Machine0#machine_state{memory = Mem3},
    Cpu1 = Machine1#machine_state.cpu#cpu_state{f = 16#40},
    Machine2 = Machine1#machine_state{cpu = Cpu1},
    Machine3 = z80_cpu:step(Machine2),
    ?assertEqual(10, z80_cpu:t_states(Machine3)),
    ?assertEqual(3, z80_cpu:pc(Machine3)).

ret_cc_timing_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#C0),
    Mem2 = ezx_mem:write_byte(Mem1, 16#1000, 16#00),
    Mem3 = ezx_mem:write_byte(Mem2, 16#1001, 16#80),
    Machine1 = Machine0#machine_state{memory = Mem3},
    Cpu1 = Machine1#machine_state.cpu#cpu_state{sp = 16#1000, f = 0},
    Machine2 = Machine1#machine_state{cpu = Cpu1},
    Machine3 = z80_cpu:step(Machine2),
    ?assertEqual(11, z80_cpu:t_states(Machine3)),
    ?assertEqual(16#8000, z80_cpu:pc(Machine3)).

ret_cc_not_taken_timing_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#C0),
    Machine1 = Machine0#machine_state{memory = Mem1},
    Cpu1 = Machine1#machine_state.cpu#cpu_state{sp = 16#1000, f = 16#40},
    Machine2 = Machine1#machine_state{cpu = Cpu1},
    Machine3 = z80_cpu:step(Machine2),
    ?assertEqual(5, z80_cpu:t_states(Machine3)),
    ?assertEqual(1, z80_cpu:pc(Machine3)).

cb_rlc_b_timing_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#CB),
    Mem2 = ezx_mem:write_byte(Mem1, 1, 16#00),
    Machine1 = Machine0#machine_state{memory = Mem2},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(8, z80_cpu:t_states(Machine2)).

add_hl_bc_timing_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#09),
    Machine1 = Machine0#machine_state{memory = Mem1},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(11, z80_cpu:t_states(Machine2)).

push_pop_timing_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#C5),
    Mem2 = ezx_mem:write_byte(Mem1, 1, 16#C1),
    Machine1 = Machine0#machine_state{memory = Mem2},
    Cpu1 = Machine1#machine_state.cpu#cpu_state{sp = 16#1000},
    Machine2 = Machine1#machine_state{cpu = Cpu1},
    Machine3 = z80_cpu:step(Machine2),
    ?assertEqual(11, z80_cpu:t_states(Machine3)),
    Machine4 = z80_cpu:step(Machine3),
    ?assertEqual(21, z80_cpu:t_states(Machine4)).

ex_af_af_timing_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#08),
    Machine1 = Machine0#machine_state{memory = Mem1},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(4, z80_cpu:t_states(Machine2)).

ex_de_hl_timing_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#EB),
    Machine1 = Machine0#machine_state{memory = Mem1},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(4, z80_cpu:t_states(Machine2)).

ex_sp_hl_timing_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#E3),
    Machine1 = Machine0#machine_state{memory = Mem1},
    Cpu1 = Machine1#machine_state.cpu#cpu_state{sp = 16#1000, h = 16#12, l = 16#34},
    Mem2 = ezx_mem:write_byte(Mem1, 16#1000, 16#56),
    Mem3 = ezx_mem:write_byte(Mem2, 16#1001, 16#78),
    Machine2 = Machine1#machine_state{cpu = Cpu1, memory = Mem3},
    Machine3 = z80_cpu:step(Machine2),
    ?assertEqual(19, z80_cpu:t_states(Machine3)).

in_out_timing_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#DB),
    Mem2 = ezx_mem:write_byte(Mem1, 1, 16#FF),
    Machine1 = Machine0#machine_state{memory = Mem2},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(11, z80_cpu:t_states(Machine2)).

halt_timing_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#76),
    Machine1 = Machine0#machine_state{memory = Mem1},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(4, z80_cpu:t_states(Machine2)),
    ?assertEqual(true, Machine2#machine_state.cpu#cpu_state.halted).

di_ei_timing_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#F3),
    Mem2 = ezx_mem:write_byte(Mem1, 1, 16#FB),
    Machine1 = Machine0#machine_state{memory = Mem2},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(4, z80_cpu:t_states(Machine2)),
    ?assertEqual(0, Machine2#machine_state.cpu#cpu_state.iff1),
    Machine3 = z80_cpu:step(Machine2),
    ?assertEqual(8, z80_cpu:t_states(Machine3)),
    ?assertEqual(1, Machine3#machine_state.cpu#cpu_state.iff1).

%% --- DAA Tests ---

daa_after_add_test() ->
    Machine0 = ezx_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{a = 16#15},
    Machine1 = Machine0#machine_state{cpu = Cpu0},
    Machine2 = ezx_emulator:write_byte(Machine1, 0, 16#C6),
    Machine3 = ezx_emulator:write_byte(Machine2, 1, 16#27),
    Machine4 = ezx_emulator:write_byte(Machine3, 2, 16#27),
    Machine5 = z80_cpu:step(Machine4),
    Machine6 = z80_cpu:step(Machine5),
    ?assertEqual(16#42, Machine6#machine_state.cpu#cpu_state.a),
    ?assertEqual(0, Machine6#machine_state.cpu#cpu_state.f band 16#40),
    ?assertEqual(11, z80_cpu:t_states(Machine6)).

daa_after_sub_test() ->
    Machine0 = ezx_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{a = 16#52},
    Machine1 = Machine0#machine_state{cpu = Cpu0},
    Machine2 = ezx_emulator:write_byte(Machine1, 0, 16#D6),
    Machine3 = ezx_emulator:write_byte(Machine2, 1, 16#37),
    Machine4 = ezx_emulator:write_byte(Machine3, 2, 16#27),
    Machine5 = z80_cpu:step(Machine4),
    Machine6 = z80_cpu:step(Machine5),
    ?assertEqual(16#15, Machine6#machine_state.cpu#cpu_state.a),
    ?assertEqual(11, z80_cpu:t_states(Machine6)).

daa_carry_test() ->
    Machine0 = ezx_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{a = 16#99},
    Machine1 = Machine0#machine_state{cpu = Cpu0},
    Machine2 = ezx_emulator:write_byte(Machine1, 0, 16#C6),
    Machine3 = ezx_emulator:write_byte(Machine2, 1, 16#01),
    Machine4 = ezx_emulator:write_byte(Machine3, 2, 16#27),
    Machine5 = z80_cpu:step(Machine4),
    Machine6 = z80_cpu:step(Machine5),
    ?assertEqual(16#00, Machine6#machine_state.cpu#cpu_state.a),
    ?assertEqual(?FLAG_C, Machine6#machine_state.cpu#cpu_state.f band ?FLAG_C),
    ?assertEqual(?FLAG_Z, Machine6#machine_state.cpu#cpu_state.f band ?FLAG_Z).