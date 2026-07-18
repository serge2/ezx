-module(z80_cpu_tests).

-include("z80_records.hrl").
-include_lib("eunit/include/eunit.hrl").

%% --- Basic Instructions ---

nop_instruction_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = z80_cpu:step(Cpu0),
    ?assertEqual(1, z80_cpu:pc(Cpu1)),
    ?assertEqual(4, z80_cpu:t_states(Cpu1)).

ld_bc_nn_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:load_program(Cpu0, 0, [16#01, 16#34, 16#12]),  %% LD BC, #1234
    Cpu2 = z80_cpu:step(Cpu1),
    ?assertEqual(16#1234, z80_cpu:get_reg_pair(bc, Cpu2)),
    ?assertEqual(3, z80_cpu:pc(Cpu2)).

interrupt_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{iff1 = 1, iff2 = 1, pc = 16#1000},
    Cpu2 = z80_cpu:request_interrupt(Cpu1, irq),
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(16#0038, z80_cpu:pc(Cpu3)),
    ?assertEqual(0, Cpu3#cpu_state.iff1),
    ?assertEqual(0, Cpu3#cpu_state.iff2).

%% --- R Register Tests ---

r_register_increments_on_m1_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = z80_cpu:step(Cpu0),
    ?assertEqual(1, Cpu1#cpu_state.r).

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
    Cpu1 = test_helpers:load_program(Cpu0, 0, [16#CB, 16#00]),  %% RLC B
    Cpu2 = z80_cpu:step(Cpu1),
    ?assertEqual(2, Cpu2#cpu_state.r),
    ?assertEqual(8, z80_cpu:t_states(Cpu2)).

r_register_prefix_ed_increments_twice_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:load_program(Cpu0, 0, [16#ED, 16#47]),  %% LD I, A
    Cpu2 = Cpu1#cpu_state{a = 16#42, r = 0},
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(2, Cpu3#cpu_state.r),
    ?assertEqual(9, z80_cpu:t_states(Cpu3)).


%% --- Timing Tests ---

nop_timing_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = z80_cpu:step(Cpu0),
    ?assertEqual(4, z80_cpu:t_states(Cpu1)).

ld_bc_nn_timing_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:load_program(Cpu0, 0, [16#01, 16#34, 16#12]),  %% LD BC, #1234
    Cpu2 = z80_cpu:step(Cpu1),
    ?assertEqual(10, z80_cpu:t_states(Cpu2)).

jr_timing_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:load_program(Cpu0, 0, [16#18, 16#05]),  %% JR $+7
    Cpu2 = z80_cpu:step(Cpu1),
    ?assertEqual(12, z80_cpu:t_states(Cpu2)),
    ?assertEqual(7, z80_cpu:pc(Cpu2)).

jr_nz_taken_timing_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:load_program(Cpu0, 0, [16#20, 16#05]),  %% JR NZ, $+7
    Cpu2 = Cpu1#cpu_state{f = 0},
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(12, z80_cpu:t_states(Cpu3)),
    ?assertEqual(7, z80_cpu:pc(Cpu3)).

jr_nz_not_taken_timing_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:load_program(Cpu0, 0, [16#20, 16#05]),  %% JR NZ, $+7
    Cpu2 = Cpu1#cpu_state{f = 16#40},
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(7, z80_cpu:t_states(Cpu3)),
    ?assertEqual(2, z80_cpu:pc(Cpu3)).

djnz_timing_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:load_program(Cpu0, 0, [16#10, 16#FC]),  %% DJNZ $-2
    Cpu2 = Cpu1#cpu_state{b = 2},
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(13, z80_cpu:t_states(Cpu3)),
    ?assertEqual(16#FFFE, z80_cpu:pc(Cpu3) band 16#FFFF).

djnz_not_taken_timing_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:load_program(Cpu0, 0, [16#10, 16#FC]),  %% DJNZ $-2
    Cpu2 = Cpu1#cpu_state{b = 1},
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(8, z80_cpu:t_states(Cpu3)),
    ?assertEqual(2, z80_cpu:pc(Cpu3)).

jp_cc_timing_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:load_program(Cpu0, 0, [16#C2, 16#00, 16#80]),  %% JP NZ, #8000
    Cpu2 = Cpu1#cpu_state{f = 0},
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(10, z80_cpu:t_states(Cpu3)),
    ?assertEqual(16#8000, z80_cpu:pc(Cpu3)).

jp_cc_not_taken_timing_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:load_program(Cpu0, 0, [16#C2, 16#00, 16#80]),  %% JP NZ, #8000
    Cpu2 = Cpu1#cpu_state{f = 16#40},
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(10, z80_cpu:t_states(Cpu3)),
    ?assertEqual(3, z80_cpu:pc(Cpu3)).

call_cc_timing_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:load_program(Cpu0, 0, [16#C4, 16#00, 16#80]),  %% CALL NZ, #8000
    Cpu2 = Cpu1#cpu_state{f = 0, sp = 16#1000},
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(17, z80_cpu:t_states(Cpu3)),
    ?assertEqual(16#8000, z80_cpu:pc(Cpu3)).

call_cc_not_taken_timing_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:load_program(Cpu0, 0, [16#C4, 16#00, 16#80]),  %% CALL NZ, #8000
    Cpu2 = Cpu1#cpu_state{f = 16#40},
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(10, z80_cpu:t_states(Cpu3)),
    ?assertEqual(3, z80_cpu:pc(Cpu3)).

ret_cc_timing_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:load_program(Cpu0, 0, [16#C0]),                     %% RET NZ
    Cpu1a = test_helpers:load_program(Cpu1, 16#1000, [16#00, 16#80]),       %% return address #8000
    Cpu2 = Cpu1a#cpu_state{sp = 16#1000, f = 0},
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(11, z80_cpu:t_states(Cpu3)),
    ?assertEqual(16#8000, z80_cpu:pc(Cpu3)).

ret_cc_not_taken_timing_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:load_program(Cpu0, 0, [16#C0]),  %% RET NZ
    Cpu2 = Cpu1#cpu_state{sp = 16#1000, f = 16#40},
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(5, z80_cpu:t_states(Cpu3)),
    ?assertEqual(1, z80_cpu:pc(Cpu3)).

cb_rlc_b_timing_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:load_program(Cpu0, 0, [16#CB, 16#00]),  %% RLC B
    Cpu2 = z80_cpu:step(Cpu1),
    ?assertEqual(8, z80_cpu:t_states(Cpu2)).

add_hl_bc_timing_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:load_program(Cpu0, 0, [16#09]),  %% ADD HL, BC
    Cpu2 = z80_cpu:step(Cpu1),
    ?assertEqual(11, z80_cpu:t_states(Cpu2)).

push_pop_timing_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:load_program(Cpu0, 0, [16#C5, 16#C1]),  %% PUSH BC / POP BC
    Cpu2 = Cpu1#cpu_state{sp = 16#1000},
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(11, z80_cpu:t_states(Cpu3)),
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(21, z80_cpu:t_states(Cpu4)).

ex_af_af_timing_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:load_program(Cpu0, 0, [16#08]),  %% EX AF, AF'
    Cpu2 = z80_cpu:step(Cpu1),
    ?assertEqual(4, z80_cpu:t_states(Cpu2)).

ex_de_hl_timing_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:load_program(Cpu0, 0, [16#EB]),  %% EX DE, HL
    Cpu2 = z80_cpu:step(Cpu1),
    ?assertEqual(4, z80_cpu:t_states(Cpu2)).

ex_sp_hl_timing_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:load_program(Cpu0, 0, [16#E3]),                     %% EX (SP), HL
    Cpu1a = test_helpers:load_program(Cpu1, 16#1000, [16#56, 16#78]),       %% stack data
    Cpu2 = Cpu1a#cpu_state{sp = 16#1000, h = 16#12, l = 16#34},
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(19, z80_cpu:t_states(Cpu3)).

in_out_timing_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:load_program(Cpu0, 0, [16#DB, 16#FF]),  %% IN A, (#FF)
    Cpu2 = z80_cpu:step(Cpu1),
    ?assertEqual(11, z80_cpu:t_states(Cpu2)).

halt_timing_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:load_program(Cpu0, 0, [16#76]),  %% HALT
    Cpu2 = z80_cpu:step(Cpu1),
    ?assertEqual(4, z80_cpu:t_states(Cpu2)),
    ?assertEqual(true, Cpu2#cpu_state.halted).

di_ei_timing_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:load_program(Cpu0, 0, [16#F3, 16#FB]),  %% DI / EI
    Cpu2 = z80_cpu:step(Cpu1),
    ?assertEqual(4, z80_cpu:t_states(Cpu2)),
    ?assertEqual(0, Cpu2#cpu_state.iff1),
    Cpu3 = z80_cpu:step(Cpu2),
    ?assertEqual(8, z80_cpu:t_states(Cpu3)),
    ?assertEqual(1, Cpu3#cpu_state.iff1).

%% --- DAA Tests ---

daa_after_add_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{a = 16#15},
    Cpu2 = test_helpers:load_program(Cpu1, 0, [16#C6, 16#27, 16#27]),  %% ADD A, #27 / DAA
    Cpu3 = z80_cpu:step(Cpu2),
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#42, Cpu4#cpu_state.a),
    ?assertEqual(0, Cpu4#cpu_state.f band 16#40),
    ?assertEqual(11, z80_cpu:t_states(Cpu4)).

daa_after_sub_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{a = 16#52},
    Cpu2 = test_helpers:load_program(Cpu1, 0, [16#D6, 16#37, 16#27]),  %% SUB #37 / DAA
    Cpu3 = z80_cpu:step(Cpu2),
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#15, Cpu4#cpu_state.a),
    ?assertEqual(11, z80_cpu:t_states(Cpu4)).

daa_carry_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = Cpu0#cpu_state{a = 16#99},
    Cpu2 = test_helpers:load_program(Cpu1, 0, [16#C6, 16#01, 16#27]),  %% ADD A, #01 / DAA
    Cpu3 = z80_cpu:step(Cpu2),
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#00, Cpu4#cpu_state.a),
    ?assertEqual(?FLAG_C, Cpu4#cpu_state.f band ?FLAG_C),
    ?assertEqual(?FLAG_Z, Cpu4#cpu_state.f band ?FLAG_Z).
