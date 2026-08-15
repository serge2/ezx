-module(ezx_emulator_tests).

-include("z80_records.hrl").
-include("ezx_emulator.hrl").
-include_lib("eunit/include/eunit.hrl").

machine_step_advances_state_test() ->
    Machine0 = init_machine(),
    Program = #{16#4000 => 16#00},
    Machine1 = load_program(Machine0, Program),
    Machine1b = set_pc(Machine1, 16#4000),
    Machine2 = ezx_emulator:step(Machine1b),
    ?assertEqual(16#4001, z80_cpu:pc(Machine2#machine_state.cpu)),
    ?assertEqual(4, z80_cpu:t_states(Machine2#machine_state.cpu)),
    ?assertEqual(4, Machine2#machine_state.t_states).

machine_run_until_tstates_test() ->
    Machine0 = init_machine(),
    Program = #{16#4000 => 16#00, 16#4001 => 16#00, 16#4002 => 16#00},
    Machine1 = load_program(Machine0, Program),
    Machine1b = set_pc(Machine1, 16#4000),
    Machine2 = ezx_emulator:run_until_tstates(Machine1b, 12),
    ?assertEqual(16#4003, z80_cpu:pc(Machine2#machine_state.cpu)),
    ?assertEqual(12, z80_cpu:t_states(Machine2#machine_state.cpu)),
    ?assertEqual(12, Machine2#machine_state.t_states).

machine_128_frame_runs_with_screen_device_test() ->
    %% The UI drives a 128K machine through ezx_emulator:run_frame/1, so the
    %% 128K init must create the screen device too.
    Machine0 = init_machine_128(),
    Machine1 = ezx_emulator:run_frame(Machine0),
    ?assertEqual(screen, element(1, Machine1#machine_state.screen)).

machine_loads_byte_lists_into_memory_test() ->
    Machine0 = init_machine(),
    Machine1 = load_program(Machine0, 16#4000, [16#3E, 16#41]),
    {Byte0, _} = ezx_emulator:read_byte(Machine1, 16#4000),
    ?assertEqual(16#3E, Byte0),
    {Byte1, _} = ezx_emulator:read_byte(Machine1, 16#4001),
    ?assertEqual(16#41, Byte1).

machine_executes_program_from_memory_test() ->
    Machine0 = init_machine(),
    Program = [16#3E, 16#41],
    Machine1 = load_program(Machine0, 16#4000, Program),
    Machine1b = set_pc(Machine1, 16#4000),
    Machine2 = ezx_emulator:step(Machine1b),
    ?assertEqual(16#4002, z80_cpu:pc(Machine2#machine_state.cpu)),
    ?assertEqual(16#41, z80_cpu:get_reg_byte(a, Machine2#machine_state.cpu)).

machine_state_keeps_cpu_and_memory_separate_test() ->
    Machine0 = init_machine(),
    Machine1 = load_program(Machine0, 16#4000, [16#3E, 16#41]),
    ?assertEqual(0, z80_cpu:pc(Machine1#machine_state.cpu)),
    ?assertEqual(16#3E, ezx_memory_48_pages512_tuples:read_byte(Machine1#machine_state.memory, 16#4000)),
    ?assertEqual(16#41, ezx_memory_48_pages512_tuples:read_byte(Machine1#machine_state.memory, 16#4001)).

memory_reset_restores_initial_configuration_test() ->
    State0 = ezx_memory_48_pages512_tuples:new(<<0:65536/unit:8>>),
    _State1 = ezx_memory_48_pages512_tuples:write_byte(State0, 10, 42),
    State2 = ezx_memory_48_pages512_tuples:new(<<0:65536/unit:8>>),
    ?assertEqual(0, ezx_memory_48_pages512_tuples:read_byte(State2, 10)).

memory_reset_to_zero_test() ->
    Memory0 = ezx_memory_48_pages512_tuples:new(<<0:8/unit:8>>),
    _Memory1 = ezx_memory_48_pages512_tuples:write_byte(Memory0, 4, 16#99),
    Memory2 = ezx_memory_48_pages512_tuples:new(<<0:8/unit:8>>),
    ?assertEqual(0, ezx_memory_48_pages512_tuples:read_byte(Memory2, 4)).

%% --- run_frame tests ---

run_frame_completes_one_frame_test() ->
    Machine0 = init_machine(),
    %% NOP loop at RAM address 0x4000.
    Machine1 = load_program(Machine0, #{16#4000 => 16#00}),
    Machine1b = set_pc(Machine1, 16#4000),
    Machine2 = ezx_emulator:run_frame(Machine1b),
    ?assertEqual(0, Machine2#machine_state.t_states).

run_frame_int_fires_test() ->
    Machine0 = init_machine(),
    Machine1 = load_program(Machine0, #{16#4000 => 16#FB, 16#4001 => 16#00, 16#4002 => 16#00}),
    Machine1b = set_pc(Machine1, 16#4000),
    Machine2 = ezx_emulator:run_frame(Machine1b),
    Cpu = Machine2#machine_state.cpu,
    Pc = z80_cpu:pc(Cpu),
    ?assert(Pc >= 16#0038).

run_frame_int_pulse_dropped_when_disabled_test() ->
    %% The ULA asserts INT as a short pulse at the start of the frame; if
    %% interrupts are disabled during the whole pulse, the request is dropped
    %% and does not linger for the rest of the frame.
    Machine0 = init_machine(),
    %% DI, then NOPs long enough to cover the pulse (t in 0..32).
    Machine1 = load_program(Machine0, 16#4000, [16#F3 | lists:duplicate(40, 16#00)]),
    Machine1b = set_pc(Machine1, 16#4000),
    Machine2 = ezx_emulator:run_frame(Machine1b),
    Cpu = Machine2#machine_state.cpu,
    ?assertEqual(none, Cpu#cpu_state.pending_interrupt),
    ?assertEqual(0, Cpu#cpu_state.iff1),
    ?assert(z80_cpu:pc(Cpu) >= 16#4000).

run_frame_ei_after_pulse_does_not_fire_test() ->
    %% Regression test for the frozen-tone bug: the ULA asserts INT only as a
    %% short pulse at the start of the frame. An EI executed mid-frame (after
    %% the pulse has ended) must not fire the request in the same frame; the
    %% interrupt is serviced at the next frame's pulse instead. A custom IM2
    %% handler increments a RAM counter so services are counted precisely.
    Machine0 = init_machine(),
    Main = [16#3E, 16#40,          %% LD A, 0x40
            16#ED, 16#47,          %% LD I, A
            16#ED, 16#5E,          %% IM 2
            16#F3,                 %% DI
            lists:duplicate(20, 16#00),  %% cover the pulse (t in 0..32)
            16#FB,                 %% EI
            16#18, 16#FE],         %% JR $
    Handler = [16#3A, 16#00, 16#43,  %% LD A, (0x4300)
               16#3C,                %% INC A
               16#32, 16#00, 16#43,  %% LD (0x4300), A
               16#FB,                %% EI
               16#C9],               %% RET
    MainBytes = lists:flatten(Main),
    HandlerBytes = Handler,
    Vector = [{16#40FF, 16#00}, {16#4100, 16#42}],  %% IM2 vector -> 0x4200
    MainMap = lists:zip(lists:seq(16#4000, 16#4000 + length(MainBytes) - 1), MainBytes),
    HandlerMap = lists:zip(lists:seq(16#4200, 16#4200 + length(HandlerBytes) - 1), HandlerBytes),
    Prog = maps:from_list(MainMap ++ Vector ++ HandlerMap ++ [{16#4300, 16#00}]),
    Machine1 = load_program(Machine0, Prog),
    Machine1b = set_pc(Machine1, 16#4000),
    Machine2 = ezx_emulator:run_frame(Machine1b),
    %% The mid-frame EI must not have serviced the request in this frame.
    {Counter2, _} = ezx_emulator:read_byte(Machine2, 16#4300),
    ?assertEqual(0, Counter2),
    ?assertEqual(1, (Machine2#machine_state.cpu)#cpu_state.iff1),
    Machine3 = ezx_emulator:run_frame(Machine2),
    %% The next frame's pulse services it exactly once.
    {Counter3, _} = ezx_emulator:read_byte(Machine3, 16#4300),
    ?assertEqual(1, Counter3),
    Machine4 = ezx_emulator:run_frame(Machine3),
    {Counter4, _} = ezx_emulator:read_byte(Machine4, 16#4300),
    ?assertEqual(2, Counter4).

run_frame_ei_after_pulse_with_tail_does_not_fire_test() ->
    %% The pulse is anchored at the nominal frame boundary and ends at the
    %% int_pulse-th T-state of the frame — NOT at StartT + IntPulse. With a
    %% carried tail StartT = 20 < IntPulse the frame-start boundary (t=20)
    %% still falls inside the pulse, so the request IS asserted; but the pulse
    %% window is [0, 32), so an EI whose boundary lands at counter >= 32 must
    %% not fire the stale request in this frame. (Regression: the drop point
    %% used to be StartT + IntPulse = 52, so an EI at counter 40 did fire.)
    %% IFF1 is left 0 via the machine state, not a DI instruction — the
    %% request is set directly by the emulator at the frame boundary and
    %% dropped at pulse end, so only this setup exercises the
    %% drop-at-pulse-end logic.
    Machine0 = init_machine(),
    %% NOP, NOP, NOP, NOP (boundaries 24/28/32/36), EI (40), NOP, HALT.
    Machine1 = load_program(Machine0, 16#4000, [16#00, 16#00, 16#00, 16#00, 16#FB, 16#00, 16#76]),
    Cpu1 = Machine1#machine_state.cpu,
    Machine2 = Machine1#machine_state{
        cpu = Cpu1#cpu_state{pc = 16#4000, iff1 = 0, iff2 = 1, t_states = 20},
        t_states = 20},
    Machine3 = ezx_emulator:run_frame(Machine2),
    {F0, M4} = ezx_emulator:read_byte(Machine3, 16#5C78),
    {F1, M5} = ezx_emulator:read_byte(M4, 16#5C79),
    {F2, _} = ezx_emulator:read_byte(M5, 16#5C7A),
    ?assertEqual(0, F0 + (F1 bsl 8) + (F2 bsl 16)).

run_frame_int_skipped_when_tail_ge_pulse_test() ->
    %% Real hardware: /INT is sampled only at the end of a complete instruction.
    %% A DD/FD prefix chain (the only instructions longer than the pulse)
    %% straddling the frame boundary leaves no sample point inside the
    %% int_pulse-wide pulse window, so that frame's interrupt is suppressed.
    %% With variant-A framing the frame starts at the boundary that overshot it
    %% (the carried tail t_states = StartT), so ezx asserts the request only
    %% when StartT < IntPulse; a tail >= IntPulse means a long instruction ate
    %% the whole pulse and the interrupt must not fire.
    Machine0 = init_machine(),
    Machine1 = load_program(Machine0, 16#4000, [16#FB, 16#00, 16#76]),  %% EI; NOP; HALT
    Cpu1 = Machine1#machine_state.cpu,
    Machine2 = Machine1#machine_state{
        cpu = Cpu1#cpu_state{pc = 16#4000, iff1 = 1, iff2 = 1, t_states = 40},
        t_states = 40},
    Machine3 = ezx_emulator:run_frame(Machine2),
    Cpu2 = Machine3#machine_state.cpu,
    ?assertEqual(none, Cpu2#cpu_state.pending_interrupt),
    ?assertEqual(1, Cpu2#cpu_state.iff1),
    ?assertEqual(16#4003, z80_cpu:pc(Cpu2)).

run_frame_int_fires_when_tail_lt_pulse_test() ->
    %% Control: with a tail smaller than the pulse the frame's first boundary
    %% still falls inside the pulse window, so the interrupt fires as usual.
    %% The ROM's IM1 handler at 0x38 increments the FRAMES counter at 0x5C78
    %% exactly once per serviced interrupt.
    Machine0 = init_machine(),
    Machine1 = load_program(Machine0, 16#4000, [16#FB, 16#00, 16#76]),  %% EI; NOP; HALT
    Cpu1 = Machine1#machine_state.cpu,
    Machine2 = Machine1#machine_state{
        cpu = Cpu1#cpu_state{pc = 16#4000, iff1 = 1, iff2 = 1, t_states = 0},
        t_states = 0},
    Machine3 = ezx_emulator:run_frame(Machine2),
    Cpu2 = Machine3#machine_state.cpu,
    ?assertEqual(none, Cpu2#cpu_state.pending_interrupt),
    {F0, M3a} = ezx_emulator:read_byte(Machine3, 16#5C78),
    {F1, M3b} = ezx_emulator:read_byte(M3a, 16#5C79),
    {F2, _} = ezx_emulator:read_byte(M3b, 16#5C7A),
    ?assertEqual(1, F0 + (F1 bsl 8) + (F2 bsl 16)).

run_frame_int_fires_with_pentagon_tail_in_pulse_window_test() ->
    %% Regression: the fast path (execute_frame_cpu_loop) used to end the INT
    %% pulse at a hardcoded 32 T-states instead of the model's int_pulse. The
    %% 48K model has int_pulse = 32, so the bug was invisible there; on 128K/
    %% Pentagon (int_pulse = 36) a carried tail in [32, 36) asserted the
    %% request but then dropped it unserviced — run_until_tstates from t >= 32
    %% ran zero instructions before clear_interrupt_request — so the frame's
    %% interrupt was silently lost. That is why halving the Pentagon pulse
    %% appeared to "fix" the Action demo: it shrank the asserted window below
    %% 32, hiding the bug. Fuse's model (tstates < interrupt_length at the
    %% frame-boundary sample point, libspectrum interrupt_length = 36 for the
    %% Pentagon) services this interrupt, so the tail must fire it.
    Machine0 = init_machine_pentagon(),
    Machine1 = load_program(Machine0, 16#4000, [16#FB, 16#00, 16#76]),  %% EI; NOP; HALT
    Cpu1 = Machine1#machine_state.cpu,
    Machine2 = Machine1#machine_state{
        cpu = Cpu1#cpu_state{pc = 16#4000, iff1 = 1, iff2 = 1, t_states = 34},
        t_states = 34},
    Machine3 = ezx_emulator:run_frame(Machine2),
    Cpu2 = Machine3#machine_state.cpu,
    ?assertEqual(none, Cpu2#cpu_state.pending_interrupt),
    {F0, M3a} = ezx_emulator:read_byte(Machine3, 16#5C78),
    {F1, M3b} = ezx_emulator:read_byte(M3a, 16#5C79),
    {F2, _} = ezx_emulator:read_byte(M3b, 16#5C7A),
    ?assertEqual(1, F0 + (F1 bsl 8) + (F2 bsl 16)).

run_frame_ei_mid_frame_masks_only_next_instruction_test() ->
    %% Real Z80: EI re-enables interrupts one instruction later, so an EI
    %% executed mid-frame (no request pending) must not suppress the request
    %% asserted at the next frame boundary. The frame closes mid-LDIR-loop with
    %% a carried tail of 15 T-states (the crossing LDIR iteration overshoots to
    %% counter 69903), so the frame-start boundary falls inside the pulse
    %% (15 < 32) and the request is serviced at that boundary, before the first
    %% instruction of the frame. If the EI delay lingered until a request was
    %% pending, the sample would be pushed to the first instruction of the
    %% frame (15 + 21 = 36 >= 32), the request would be dropped at the pulse
    %% end and the frame's interrupt would be lost (the Beach Head II flicker).
    Machine0 = init_machine(),
    %% NOP*7 (cover the pulse with IFF1=0), EI, NOP (the one EI-delayed
    %% instruction), then a long LDIR loop the frame boundary falls into.
    Program = lists:duplicate(7, 16#00) ++ [16#FB, 16#00, 16#ED, 16#B0],
    Machine1 = load_program(Machine0, 16#4000, Program),
    Cpu0 = Machine1#machine_state.cpu,
    Machine2 = Machine1#machine_state{
        cpu = Cpu0#cpu_state{pc = 16#4000, iff1 = 0, iff2 = 0, im = 1,
                             b = 16#80, c = 16#00,
                             d = 16#50, e = 16#00,
                             h = 16#60, l = 16#00},
        t_states = 0},
    Machine3 = ezx_emulator:run_frame(Machine2),
    ?assertEqual(15, Machine3#machine_state.t_states),
    Machine4 = ezx_emulator:run_frame(Machine3),
    {F0, M5} = ezx_emulator:read_byte(Machine4, 16#5C78),
    {F1, M6} = ezx_emulator:read_byte(M5, 16#5C79),
    {F2, _} = ezx_emulator:read_byte(M6, 16#5C7A),
    ?assertEqual(1, F0 + (F1 bsl 8) + (F2 bsl 16)).

run_frame_screen_changes_recorded_test() ->
    Machine0 = init_machine(),
    Machine1 = load_program(Machine0, #{16#4000 => 16#3E, 16#4001 => 16#04, 16#4002 => 16#D3, 16#4003 => 16#FE}),
    Machine1b = set_pc(Machine1, 16#4000),
    Machine2 = ezx_emulator:run_frame(Machine1b),
    %% OUT (0xFE), A records one change to color 4; the artifacts are stored in
    %% the machine state by run_frame. screen_color is the base color for the
    %% frame — the color at the nominal frame boundary (black before the OUT,
    %% which lands at T-state 14), not the live color that ends the frame.
    ?assertEqual([{14, 4}], Machine2#machine_state.screen_changes),
    ?assertEqual(0, Machine2#machine_state.screen_color),
    ?assertEqual(4, ezx_screen:border_get(Machine2#machine_state.screen)).

run_frame_multiple_nops_test() ->
    Machine0 = init_machine(),
    Nops = lists:duplicate(200, 16#00),
    Machine1 = load_program(Machine0, 16#4000, Nops),
    Machine1b = set_pc(Machine1, 16#4000),
    Machine2 = ezx_emulator:run_frame(Machine1b),
    Pc = z80_cpu:pc(Machine2#machine_state.cpu),
    ?assert(Pc >= 16#0038).

run_frame_two_frames_test() ->
    Machine0 = init_machine(),
    Machine1 = load_program(Machine0, #{16#4000 => 16#00}),
    Machine1b = set_pc(Machine1, 16#4000),
    Machine2 = ezx_emulator:run_frame(Machine1b),
    Machine3 = ezx_emulator:run_frame(Machine2),
    ?assertEqual(0, Machine3#machine_state.t_states).

%% --- Border stripe rendering test ---
%%
%% 16-color stripe program using nested loops with NOPs for timing.
%%
%% Visible area: 288 lines × 224 T-states = 64512 T-states (frame lines 16..303).
%% 16 stripes × 18 lines = 288 lines — perfect fit.
%%
%% Z80 program (loaded at 0x8000):
%%   DI                  ; 4T
%%   LD B, 142           ; 7T     — preamble delay counter
%% pre:
%%   NOP × 3             ; 12T
%%   DJNZ pre            ; 13T taken / 8T last
%%   NOP × 3             ; 12T    — alignment after preamble loop
%%   LD B, 16            ; 7T     — outer loop counter
%%   LD A, 0             ; 7T     — first color
%% loop:
%%   OUT (0FEh), A       ; 11T    — border change at start of each stripe
%%   LD C, 110           ; 7T     — inner delay counter
%% delay:
%%   NOP × 5             ; 20T
%%   DEC C               ; 4T
%%   JR NZ, delay        ; 12T taken / 7T last
%%   NOP × 8             ; 32T    — fill after delay loop
%%   INC A               ; 4T
%%   AND 07h             ; 7T     — wrap color: 0..7, 0..7
%%   DJNZ loop           ; 13T taken / 8T last
%%   JR $                ; stop
%%
%% Timing (JR NZ = 12T/7T, DJNZ = 13T/8T):
%%   Preamble: 4 + 7 + 141×25 + 20 + 7 + 7 + 7 + 7 = 3584T (exact)
%%   Stripe interval: 11 + 7 + 109×36 + 31 + 35 + 4 + 7 + 13 = 4032T (exact, 18 lines)
%%   16 × 4032 = 64512 = visible area. Perfect fit.

run_frame_border_stripes_test() ->
    M0 = init_machine(),
    M0r = ezx_emulator:run_frame(M0),

    Pgm = [
        16#F3,                               %% DI
        16#06, 142,                          %% LD B, 142
        16#00, 16#00, 16#00,                 %% pre: NOP × 3
        16#10, -5 band 16#FF,                %% DJNZ pre
        16#0E, 0,                            %% LD C, 0            — fill
        16#0E, 0,                            %% LD C, 0            — fill
        16#06, 16,                           %% LD B, 16
        16#3E, 0,                            %% LD A, 0
        16#D3, 16#FE,                        %% OUT (0FEh), A
        16#0E, 16#6E,                        %% LD C, 110
        16#00, 16#00, 16#00, 16#00, 16#00,   %% delay: NOP × 5
        16#0D,                               %% DEC C
        16#20, -8 band 16#FF,                %% JR NZ, -8
        16#0E, 0,                            %% LD C, 0            — fill
        16#0E, 0,                            %% LD C, 0            — fill
        16#0E, 0,                            %% LD C, 0            — fill
        16#0E, 0,                            %% LD C, 0            — fill
        16#0E, 0,                            %% LD C, 0            — fill
        16#3C,                               %% INC A
        16#E6, 16#07,                        %% AND 07h
        16#10, -27 band 16#FF,               %% DJNZ, -27
        16#18, -2 band 16#FF                 %% JR $
    ],

    M1 = load_program(M0r, 16#8000, Pgm),
    M2 = set_pc(M1, 16#8000),
    M3 = ezx_emulator:run_frame(M2),

    %% run_frame stores the border artifacts (sorted local changes + base
    %% color + flash flag) in the machine state.
    Changes = M3#machine_state.screen_changes,
    CB = M3#machine_state.screen_color,
    ?assertEqual(16, length(Changes)),

    %% Local frame time IS the counter (0 = nominal frame boundary): the frame
    %% starts at the carried tail StartT (the boot frame's overshoot), so the
    %% first border change of the frame lands at StartT + the program's own
    %% timing. A uniform shift by StartT keeps every change inside the same
    %% raster line (4032 = 18 lines exactly), so the rendered stripes are
    %% unaffected.
    StartT = M2#machine_state.t_states,
    FirstT = 3584 + 7,
    Interval = 4032,
    ExpectedColors = [0, 1, 2, 3, 4, 5, 6, 7, 0, 1, 2, 3, 4, 5, 6, 7],
    lists:foreach(fun({K, {T, Color}}) ->
        ?assertEqual(StartT + FirstT + K * Interval, T),
        ?assertEqual(lists:nth(K + 1, ExpectedColors), Color)
    end, lists:zip(lists:seq(0, 15), Changes)),

    %% --- Verify rendered pixel colors ---
    Mem = M3#machine_state.memory,
    VB = ezx_memory_48_pages512_tuples:read_video_block(Mem),
    RGB = ezx_screen:render_screen(VB, M3#machine_state.flash_on, Changes, CB, ?TSTATES_PER_LINE),

    Palette = {
        {0, 0, 0}, {0, 0, 215}, {215, 0, 0}, {215, 0, 215},
        {0, 215, 0}, {0, 215, 215}, {215, 215, 0}, {215, 215, 215}
    },

    %% Each stripe's border change sits 7 T into its line (StartT = 0 here,
    %% verified above via the uniform shift): pixel 14 in the left border
    %% column. The renderer colors pixels before the change with the previous
    %% color (the color carried into the line), pixels from the change onward
    %% with the stripe's own color.
    BorderChangePx = (7 + StartT) * 2,
    lists:foreach(fun(K) ->
        VisY = K * 18,
        ExpectedColor = lists:nth(K + 1, ExpectedColors),
        PrevColor = case K of 0 -> CB; _ -> lists:nth(K, ExpectedColors) end,
        OffPrev = (VisY * 352 + (BorderChangePx - 1)) * 3,
        <<_:OffPrev/binary, RP:8, GP:8, BP:8, _/binary>> = RGB,
        ?assertEqual(element(PrevColor + 1, Palette), {RP, GP, BP}),
        Off = (VisY * 352 + BorderChangePx) * 3,
        <<_:Off/binary, R:8, G:8, B:8, _/binary>> = RGB,
        ?assertEqual(element(ExpectedColor + 1, Palette), {R, G, B})
    end, lists:seq(0, 15)).

%% --- Frame artifact tests ---

run_frame_produces_beeper_pcm_artifact_test() ->
    Machine0 = init_machine(),
    Machine1 = ezx_emulator:run_frame(Machine0),
    PCM = Machine1#machine_state.beeper_pcm,
    ?assertEqual(ezx_emulator:samples_per_frame(Machine1) * 2, byte_size(PCM)),
    {PCM2, Machine2} = ezx_emulator:render_beeper(Machine1),
    ?assertEqual(PCM, PCM2),
    ?assertEqual(Machine1, Machine2).

run_frame_produces_ay_pcm_artifact_test() ->
    Machine0 = init_machine_128(),
    Machine1 = ezx_emulator:run_frame(Machine0),
    {ChA, ChB, ChC} = Machine1#machine_state.ay_pcm,
    ?assertEqual(ezx_emulator:samples_per_frame(Machine1) * 2, byte_size(ChA)),
    ?assertEqual(ezx_emulator:samples_per_frame(Machine1) * 2, byte_size(ChB)),
    ?assertEqual(ezx_emulator:samples_per_frame(Machine1) * 2, byte_size(ChC)),
    {ChA2, ChB2, ChC2, Machine2} = ezx_emulator:render_ay_channels(Machine1),
    ?assertEqual({ChA, ChB, ChC}, {ChA2, ChB2, ChC2}),
    ?assertEqual(Machine1, Machine2).

ay_port_writes_reach_device_test() ->
    %% OUT (C),A register writes through 0xFFFD latch + 0xBFFD data must
    %% reach the AY device: regs set, and the rendered channel is audible
    %% (near full-scale square wave, not silence).
    Machine0 = init_machine_128(),
    Prog = [
        16#01, 16#FD, 16#FF,          %% LD BC,0xFFFD
        16#3E, 16#00,                 %% LD A,0
        16#ED, 16#79,                 %% OUT (C),A       ; R0=0
        16#01, 16#FD, 16#BF,          %% LD BC,0xBFFD
        16#3E, 16#F1,                 %% LD A,0xF1
        16#ED, 16#79,                 %% OUT (C),A       ; tone A period low
        16#01, 16#FD, 16#FF,          %% LD BC,0xFFFD
        16#3E, 16#01,                 %% LD A,1
        16#ED, 16#79,                 %% OUT (C),A       ; R1=1
        16#01, 16#FD, 16#BF,          %% LD BC,0xBFFD
        16#3E, 16#01,                 %% LD A,1
        16#ED, 16#79,                 %% OUT (C),A       ; tone A period high
        16#01, 16#FD, 16#FF,          %% LD BC,0xFFFD
        16#3E, 16#08,                 %% LD A,8
        16#ED, 16#79,                 %% OUT (C),A       ; R8=8 (vol A)
        16#01, 16#FD, 16#BF,          %% LD BC,0xBFFD
        16#3E, 16#0F,                 %% LD A,0x0F
        16#ED, 16#79,                 %% OUT (C),A       ; vol A = max
        16#76                        %% HALT
    ],
    Machine1 = load_program(Machine0, 16#8000, Prog),
    Machine2 = ezx_emulator:run_frame(set_pc(Machine1, 16#8000)),
    AY = Machine2#machine_state.ay,
    ?assertEqual(16#F1, ezx_ay38912_seg:read(ezx_ay38912_seg:latch(AY, 0))),
    ?assertEqual(16#01, ezx_ay38912_seg:read(ezx_ay38912_seg:latch(AY, 1))),
    ?assertEqual(16#0F, ezx_ay38912_seg:read(ezx_ay38912_seg:latch(AY, 8))),
    {ChA, _ChB, _ChC} = Machine2#machine_state.ay_pcm,
    ?assert(max_pcm_sample(ChA) > 1000).

max_pcm_sample(Pcm) ->
    lists:max([abs(X) || <<X:16/little-signed>> <= Pcm]).

run_frame_flash_cadence_test() ->
    %% The flash phase advances once per frame inside the screen device; the
    %% flash flag flips on a 16-frame cadence (phase 16..31 of 32) and the
    %% stored artifact must match the device accessor.
    Machine0 = init_machine(),
    Machine1 = load_program(Machine0, #{16#4000 => 16#00}),
    Machine1b = set_pc(Machine1, 16#4000),
    {_Machine32, Flags} = lists:foldl(fun(_, {M, Acc}) ->
        M2 = ezx_emulator:run_frame(M),
        Artifact = M2#machine_state.flash_on,
        DeviceFlag = ezx_screen:flash_on(M2#machine_state.screen),
        ?assertEqual(DeviceFlag, Artifact),
        {M2, [Artifact | Acc]}
    end, {Machine1b, []}, lists:seq(1, 32)),
    ?assertEqual(lists:duplicate(15, false) ++ lists:duplicate(16, true) ++ [false],
                 lists:reverse(Flags)).

%% --- Machine model timing tests ---

machine_model_48k_defaults_test() ->
    Machine = init_machine(),
    ?assertEqual(#machine_model{cpu_clock = 3500000, base_cpu_clock = 3500000,
                                tstates_per_frame = 69888,
                                tstates_per_line = 224, int_pulse = 32,
                                line_geometry = ?LINE_GEOMETRY_48K,
                                frame_geometry = ?FRAME_GEOMETRY_48K},
                 Machine#machine_state.model).

machine_model_128k_defaults_test() ->
    Machine = init_machine_128(),
    ?assertEqual(#machine_model{cpu_clock = 3546900, base_cpu_clock = 3546900,
                                tstates_per_frame = 70908,
                                tstates_per_line = 228, int_pulse = 36,
                                line_geometry = ?LINE_GEOMETRY_48K,
                                frame_geometry = ?FRAME_GEOMETRY_48K},
                 Machine#machine_state.model).

machine_model_pentagon_defaults_test() ->
    %% Pentagon 128: 3.584 MHz, 224 T-states/line x 320 lines = 71680/frame
    %% (exactly 50.00 Hz, unlike the 48K/128K rasters), INT pulse 36 T like the
    %% 128K (libspectrum timings, as used by Fuse). The line is 32 T retrace +
    %% 36 T left border + 128 T screen + 28 T right border, so the render
    %% window covers the full 384 px visible line ({32, 224, 68, 196}) and the
    %% frame its 304 visible lines ({16, 80, 304}).
    Machine = init_machine_pentagon(),
    ?assertEqual(#machine_model{cpu_clock = 3584000, base_cpu_clock = 3584000,
                                tstates_per_frame = 71680,
                                tstates_per_line = 224, int_pulse = 36,
                                line_geometry = ?LINE_GEOMETRY_PENTAGON,
                                frame_geometry = ?FRAME_GEOMETRY_PENTAGON},
                 Machine#machine_state.model).

machine_model_frame_lengths_test() ->
    %% The 48K raster is 69888 T-states, the 128K raster 70908; the real frame
    %% time is FrameLen / CpuClock (50.08 Hz vs 50.02 Hz). The Pentagon raster
    %% is 71680 T-states at 3.584 MHz — exactly 50.00 Hz.
    M48 = init_machine(),
    M128 = init_machine_128(),
    MPent = init_machine_pentagon(),
    ?assertEqual(69888, (M48#machine_state.model)#machine_model.tstates_per_frame),
    ?assertEqual(70908, (M128#machine_state.model)#machine_model.tstates_per_frame),
    ?assertEqual(71680, (MPent#machine_state.model)#machine_model.tstates_per_frame),
    ?assertEqual(880, ezx_emulator:samples_per_frame(M48)),
    ?assertEqual(881, ezx_emulator:samples_per_frame(M128)),
    ?assertEqual(882, ezx_emulator:samples_per_frame(MPent)).

set_cpu_frequency_scales_raster_keeps_frame_rate_test() ->
    Machine = init_machine(),
    BaseSamples = ezx_emulator:samples_per_frame(Machine),
    Machine1 = ezx_emulator:set_cpu_frequency(Machine, 7000000),
    ?assertEqual(3500000, (Machine#machine_state.model)#machine_model.cpu_clock),
    ?assertEqual(7000000, (Machine1#machine_state.model)#machine_model.cpu_clock),
    %% base_cpu_clock is the AY clock reference and must survive overclocking.
    ?assertEqual(3500000, (Machine1#machine_state.model)#machine_model.base_cpu_clock),
    %% CPU-only overclock: the raster scales with the clock (2x here) so the
    %% real frame time — and thus the frame rate, the interrupt timing and the
    %% audio sample count — stays fixed.
    Model1 = Machine1#machine_state.model,
    ?assertEqual(139776, Model1#machine_model.tstates_per_frame),
    ?assertEqual(448, Model1#machine_model.tstates_per_line),
    ?assertEqual(64, Model1#machine_model.int_pulse),
    ?assertEqual({0, 352, 48, 304}, Model1#machine_model.line_geometry),
    ?assertEqual(BaseSamples, ezx_emulator:samples_per_frame(Machine1)),
    Machine2 = ezx_emulator:run_frame(Machine1),
    ?assertEqual(BaseSamples * 2, byte_size(Machine2#machine_state.beeper_pcm)),
    %% Switching back to the base clock restores the exact base raster
    %% (the scale is idempotent: undo x2, apply x1).
    Machine3 = ezx_emulator:set_cpu_frequency(Machine1, 3500000),
    ?assertEqual(#machine_model{cpu_clock = 3500000, base_cpu_clock = 3500000,
                                tstates_per_frame = 69888,
                                tstates_per_line = 224, int_pulse = 32,
                                line_geometry = ?LINE_GEOMETRY_48K,
                                frame_geometry = ?FRAME_GEOMETRY_48K},
                 Machine3#machine_state.model).

%% CPU overclock is timing-only: the video raster stays base. A border change
%% at scaled stamp 100 on an x2 machine folds back to base stamp 50 and must
%% render byte-identically to an x1 machine carrying the change at stamp 50.
overclocked_render_folds_border_stamps_to_base_domain_test() ->
    Machine = init_machine(),
    VB = ezx_memory_48_pages512_tuples:read_video_block(Machine#machine_state.memory),
    CB = Machine#machine_state.screen_color,
    RGB1 = ezx_screen:render_screen(VB, false, [{50, 2}], CB, ?TSTATES_PER_LINE),
    MachineX2 = ezx_emulator:set_cpu_frequency(Machine, 7000000),
    RGB2 = ezx_emulator:render_frame(
             MachineX2#machine_state{screen_changes = [{100, 2}]}),
    ?assertEqual(RGB1, RGB2).

%% The rendered bitmap is base-sized at any CPU multiplier: the UI assumes the
%% model's base geometry, so a scaled frame would scramble the display.
overclocked_frame_renders_base_size_test() ->
    Machine = init_machine(),
    M1 = ezx_emulator:run_frame(ezx_emulator:set_render_screen(Machine, true)),
    M2 = ezx_emulator:run_frame(ezx_emulator:set_render_screen(
            ezx_emulator:set_cpu_frequency(Machine, 7000000), true)),
    ?assertEqual(352 * 288 * 3, byte_size(M1#machine_state.screen_pixels)),
    ?assertEqual(352 * 288 * 3, byte_size(M2#machine_state.screen_pixels)).

%% --- Helpers ---

init_machine() ->
    RomPath = try filename:join([code:priv_dir(ezx), "roms", "48.rom"])
    catch error:badarg ->
        BeamDir = filename:dirname(code:which(?MODULE)),
        filename:join([filename:dirname(BeamDir), "priv", "roms", "48.rom"])
    end,
    {ok, Rom} = file:read_file(RomPath),
    ezx_emulator:init(?SPECTRUM_48_MODEL, z80_cpu, ezx_memory_48_pages512_tuples, ezx_keyboard, ezx_beeper2, undefined, Rom).

init_machine_128() ->
    RomPath = try filename:join([code:priv_dir(ezx), "roms", "48.rom"])
    catch error:badarg ->
        BeamDir = filename:dirname(code:which(?MODULE)),
        filename:join([filename:dirname(BeamDir), "priv", "roms", "48.rom"])
    end,
    {ok, Rom} = file:read_file(RomPath),
    ezx_emulator_128:init(?SPECTRUM_128_MODEL, z80_cpu, ezx_memory_128_banks_tuples, ezx_keyboard, ezx_beeper2, ezx_ay38912_seg, {Rom, Rom}).

init_machine_pentagon() ->
    RomPath = try filename:join([code:priv_dir(ezx), "roms", "48.rom"])
    catch error:badarg ->
        BeamDir = filename:dirname(code:which(?MODULE)),
        filename:join([filename:dirname(BeamDir), "priv", "roms", "48.rom"])
    end,
    {ok, Rom} = file:read_file(RomPath),
    ezx_emulator_128:init(?PENTAGON_128_MODEL, z80_cpu, ezx_memory_128_banks_tuples, ezx_keyboard, ezx_beeper2, ezx_ay38912_seg, {Rom, Rom}).

%% --- AY chip selection plumbing ---

ay_chip_from_model_test_() ->
    %% The sound chip is taken from the machine model's ay_chip field and
    %% passed to the AY module at init; the module reports it back via chip/1.
    [init_machine(Chip) || Chip <- [ay, ym]].
init_machine(Chip) ->
    fun() ->
        RomPath = try filename:join([code:priv_dir(ezx), "roms", "48.rom"])
        catch error:badarg ->
            BeamDir = filename:dirname(code:which(?MODULE)),
            filename:join([filename:dirname(BeamDir), "priv", "roms", "48.rom"])
        end,
        {ok, Rom} = file:read_file(RomPath),
        BaseModel = ?SPECTRUM_48_MODEL,
        Model = BaseModel#machine_model{ay_chip = Chip},
        Machine = ezx_emulator:init(Model, z80_cpu, ezx_memory_48_pages512_tuples,
                                    ezx_keyboard, ezx_beeper2, ezx_ay38912_seg, Rom),
        ?assertEqual(Chip, ezx_ay38912_seg:chip(Machine#machine_state.ay))
    end.

load_program(Machine, Program) when is_map(Program) ->
    maps:fold(fun(Addr, Byte, M) ->
        ezx_emulator:write_byte(M, Addr, Byte)
    end, Machine, Program);
load_program(Machine, Program) when is_list(Program) ->
    load_program(Machine, 0, Program).

load_program(Machine, BaseAddr, Program) when is_list(Program) ->
    load_program(Machine, maps:from_list(lists:enumerate(BaseAddr, Program))).

set_pc(#machine_state{cpu = Cpu} = Machine, Addr) ->
    Machine#machine_state{cpu = Cpu#cpu_state{pc = Addr}}.

%% --- SNA loading error tests ---

load_sna_empty_binary_test() ->
    Machine = init_machine(),
    {error, {bad_sna_header, _}} = ezx_emulator:load_sna(Machine, <<>>).

load_sna_short_binary_test() ->
    Machine = init_machine(),
    Data = <<0:100/unit:8>>,
    {error, {bad_sna_header, _}} = ezx_emulator:load_sna(Machine, Data).

load_sna_valid_binary_test() ->
    Machine = init_machine(),
    Data = <<0: (27 + 49152)/unit:8>>,
    {ok, _Machine1} = ezx_emulator:load_sna(Machine, Data).

%% --- Z80 loading tests ---

load_z80_empty_binary_test() ->
    Machine = init_machine(),
    {error, {bad_z80_header, _}} = ezx_emulator:load_z80(Machine, <<>>).

load_z80_short_binary_test() ->
    Machine = init_machine(),
    Data = <<0:29/unit:8>>,
    {error, {bad_z80_header, _}} = ezx_emulator:load_z80(Machine, Data).

load_z80_v1_uncompressed_test() ->
    Machine = init_machine(),
    Header = build_v1_header(16#100, 0),
    Data = <<Header/binary, 0:49152/unit:8>>,
    {ok, Machine1} = ezx_emulator:load_z80(Machine, Data),
    ?assertEqual(16#100, z80_cpu:pc(Machine1#machine_state.cpu)).

load_z80_v1_compressed_test() ->
    Machine = init_machine(),
    Header = build_v1_header(16#200, 16#20),
    RleParts = lists:duplicate(192, <<16#ED, 16#ED, 16#FF, 16#00>>) ++
               [<<16#ED, 16#ED, 16#C0, 16#00>>,
                <<16#00, 16#ED, 16#ED, 16#00>>],
    RleData = iolist_to_binary(RleParts),
    Data = <<Header/binary, RleData/binary>>,
    {ok, Machine1} = ezx_emulator:load_z80(Machine, Data),
    ?assertEqual(16#200, z80_cpu:pc(Machine1#machine_state.cpu)).

load_z80_v1_sets_registers_test() ->
    Machine = init_machine(),
    Header = <<16#12:8, 16#34:8,                   %% A=0x12, F=0x34
              16#34, 16#56, 16#12, 16#78,           %% BC=0x5634 (B=0x56, C=0x34), HL=0x7812 (H=0x78, L=0x12)
              16#01, 16#10, 16#00, 16#10,           %% PC=0x1001, SP=0x1000
              16#01, 16#02,                         %% I=0x01, R=0x02
              16#00,                                 %% Flags=0
              16#9A, 16#78,                         %% DE=0x789A (D=0x78, E=0x9A)
              16#00, 16#00, 16#00, 16#00,           %% BC'=0, DE'=0
              16#00, 16#00,                         %% HL'=0
              16#AB, 16#CD,                         %% A'=0xAB, F'=0xCD
              16#F0, 16#DE, 16#00, 16#BC,           %% IY=0xDEF0, IX=0xBC00
              16#01, 16#01, 16#01>>,                %% IFF1=1, IFF2=1, IM=1
    Data = <<Header/binary, 0:49152/unit:8>>,
    {ok, Machine1} = ezx_emulator:load_z80(Machine, Data),
    Cpu = Machine1#machine_state.cpu,
    ?assertEqual(16#12, Cpu#cpu_state.a),
    ?assertEqual(16#34, Cpu#cpu_state.f),
    ?assertEqual(16#56, Cpu#cpu_state.b),
    ?assertEqual(16#34, Cpu#cpu_state.c),
    ?assertEqual(16#78, Cpu#cpu_state.d),
    ?assertEqual(16#9A, Cpu#cpu_state.e),
    ?assertEqual(16#78, Cpu#cpu_state.h),
    ?assertEqual(16#12, Cpu#cpu_state.l),
    ?assertEqual(16#1001, z80_cpu:pc(Cpu)),
    ?assertEqual(16#1000, Cpu#cpu_state.sp),
    ?assertEqual(16#01, Cpu#cpu_state.i),
    ?assertEqual(16#02, Cpu#cpu_state.r),
    ?assertEqual(16#01, Cpu#cpu_state.iff1),
    ?assertEqual(16#01, Cpu#cpu_state.iff2),
    ?assertEqual(16#01, Cpu#cpu_state.im),
    ?assertEqual(16#AB, Cpu#cpu_state.a_alt),
    ?assertEqual(16#CD, Cpu#cpu_state.f_alt),
    ?assertEqual(16#DE, Cpu#cpu_state.iyh),
    ?assertEqual(16#F0, Cpu#cpu_state.iyl),
    ?assertEqual(16#BC, Cpu#cpu_state.ixh),
    ?assertEqual(16#00, Cpu#cpu_state.ixl).

load_z80_v1_compressed_trailing_ed_test() ->
    Machine = init_machine(),
    Header = build_v1_header(16#300, 16#20),
    %% 49151 zeros + trailing ED byte
    %% RLE: 192 × 255 zeros + 191 zeros = 49151 zeros, plus literal ED
    RleParts = lists:duplicate(192, <<16#ED, 16#ED, 16#FF, 16#00>>) ++
               [<<16#ED, 16#ED, 16#BF, 16#00>>,
                <<16#ED, 16#00, 16#00, 16#ED, 16#ED, 16#00>>],
    RleData = iolist_to_binary(RleParts),
    Data = <<Header/binary, RleData/binary>>,
    {ok, Machine1} = ezx_emulator:load_z80(Machine, Data),
    ?assertEqual(16#300, z80_cpu:pc(Machine1#machine_state.cpu)).

load_z80_v2_test() ->
    Machine = init_machine(),
    %% 30-byte header with PC=0 to indicate extended format
    Header = <<0:8, 0:8, 0:16, 0:16, 0:16, 0:16, 0:8, 0:8, 0:8,
              0:16, 0:16, 0:16, 0:16, 0:8, 0:8, 0:16, 0:16, 0:8, 0:8, 0:8>>,
    %% Extended: ExtraLen=23
    ExtraLen = 23,
    %% Extended header: PC=0x1234, HwMode=0 (48K), rest = padding
    ExtHeader = <<16#34, 16#12,  %% PC=0x1234 LE
                  16#00,         %% HwMode=0 (48K)
                  0:20/unit:8>>, %% remaining 20 bytes of extended header
    %% Blocks: 3 raw pages (8, 4, 5) = 0x4000, 0x8000, 0xC000
    Page8 = <<0:16384/unit:8>>,
    Page4 = <<0:16384/unit:8>>,
    Page5 = <<0:16384/unit:8>>,
    Block8 = <<16#FF, 16#FF, 8, Page8/binary>>,
    Block4 = <<16#FF, 16#FF, 4, Page4/binary>>,
    Block5 = <<16#FF, 16#FF, 5, Page5/binary>>,
    Data = <<Header/binary, ExtraLen:16/little, ExtHeader/binary,
             Block8/binary, Block4/binary, Block5/binary>>,
    {ok, Machine1} = ezx_emulator:load_z80(Machine, Data),
    ?assertEqual(16#1234, z80_cpu:pc(Machine1#machine_state.cpu)).

load_z80_v3_48k_test() ->
    Machine = init_machine(),
    Header = <<0:30/unit:8>>,
    ExtraLen = 54,
    ExtHeader = <<16#34, 16#12,
                  16#00,         %% HwMode=0 (48K)
                  16#00,         %% p7FFD=0
                  0:50/unit:8>>, %% remaining padding
    Page8 = <<0:16384/unit:8>>,
    Page4 = <<0:16384/unit:8>>,
    Page5 = <<0:16384/unit:8>>,
    Block8 = <<16#FF, 16#FF, 8, Page8/binary>>,
    Block4 = <<16#FF, 16#FF, 4, Page4/binary>>,
    Block5 = <<16#FF, 16#FF, 5, Page5/binary>>,
    Data = <<Header/binary, ExtraLen:16/little, ExtHeader/binary,
             Block8/binary, Block4/binary, Block5/binary>>,
    {ok, Machine1} = ezx_emulator:load_z80(Machine, Data),
    ?assertEqual(16#1234, z80_cpu:pc(Machine1#machine_state.cpu)).

load_z80_v3_128k_on_48k_rejected_test() ->
    Machine = init_machine(),
    Header = <<0:30/unit:8>>,
    ExtraLen = 54,
    ExtHeader = <<16#00, 16#00,
                  16#03,         %% HwMode=3 (128K)
                  16#10,         %% p7FFD=0x10
                  0:50/unit:8>>,
    Page8 = <<0:16384/unit:8>>,
    Page4 = <<0:16384/unit:8>>,
    Page5 = <<0:16384/unit:8>>,
    Block8 = <<16#FF, 16#FF, 8, Page8/binary>>,
    Block4 = <<16#FF, 16#FF, 4, Page4/binary>>,
    Block5 = <<16#FF, 16#FF, 5, Page5/binary>>,
    Data = <<Header/binary, ExtraLen:16/little, ExtHeader/binary,
             Block8/binary, Block4/binary, Block5/binary>>,
    {error, {unsupported_version, _}} = ezx_emulator:load_z80(Machine, Data).

%% --- TAP loading error tests ---

load_tap_empty_binary_test() ->
    Machine = init_machine(),
    {ok, _Machine1} = ezx_emulator:load_tap(Machine, <<>>).

%% --- Tape trap entries ---
%%
%% LD-BYTES is trapped at three PC entries: 0x0556 (main ROM entry used by
%% LOAD "" and most loaders), 0x0563 (the continuation entry right after the
%% flag-setup prologue) and 0x0562 (the ROM's start-of-block EAR-poll point,
%% IN A,(0xFE)).  Speedloaders such as the 128K Robin of the Wood loader
%% prepare IX/DE themselves, replicate the prologue, then JP 0x0563; the
%% Halaga loader instead CALLs 0x0562 so the ROM reads the block for it.
%% Without these entries the trap never fires and the loader spins in the
%% ROM EAR-polling loop.

tape_trap_main_entry_test() ->
    Machine0 = init_machine(),
    Payload = <<1, 2, 3, 4, 5>>,
    {ok, Machine1} = ezx_emulator:load_tap(Machine0, build_tap([Payload])),
    Dest = 16#8000,
    Machine2 = set_pc(set_ix_de(Machine1, Dest, byte_size(Payload)), 16#0556),
    Machine3 = ezx_emulator:step(Machine2),
    assert_trap_result(Machine3, Dest, Payload).

tape_trap_continuation_entry_test() ->
    Machine0 = init_machine(),
    Payload = <<16#AA, 16#BB, 16#CC, 16#DD>>,
    {ok, Machine1} = ezx_emulator:load_tap(Machine0, build_tap([Payload])),
    Dest = 16#8000,
    Machine2 = set_pc(set_ix_de(Machine1, Dest, byte_size(Payload)), 16#0563),
    Machine3 = ezx_emulator:step(Machine2),
    assert_trap_result(Machine3, Dest, Payload).

tape_trap_ear_entry_test() ->
    %% The Halaga loader enters the ROM at 0x0562 (IN A,(0xFE)) with a
    %% CALL after replicating the flag-setup prologue, so the trap must
    %% serve the block from that entry too.
    Machine0 = init_machine(),
    Payload = <<16#15, 16#39, 16#BD, 16#FF>>,
    {ok, Machine1} = ezx_emulator:load_tap(Machine0, build_tap([Payload])),
    Dest = 16#4000,
    Machine2 = set_pc(set_ix_de(Machine1, Dest, byte_size(Payload)), 16#0562),
    Machine3 = ezx_emulator:step(Machine2),
    assert_trap_result(Machine3, Dest, Payload).

tape_trap_short_block_test() ->
    %% A speedloader may ask for more bytes than the TAP block holds
    %% (e.g. a data block that does not fill the requested length); the
    %% trap must write what is available and not crash.
    Machine0 = init_machine(),
    Payload = <<7, 8, 9>>,
    {ok, Machine1} = ezx_emulator:load_tap(Machine0, build_tap([Payload])),
    Dest = 16#8000,
    Machine2 = set_pc(set_ix_de(Machine1, Dest, 100), 16#0563),
    Machine3 = ezx_emulator:step(Machine2),
    assert_trap_result(Machine3, Dest, Payload).

set_ix_de(#machine_state{cpu = Cpu} = Machine, IX, DE) ->
    Cpu1 = Cpu#cpu_state{
        ixh = (IX bsr 8) band 16#FF,
        ixl = IX band 16#FF,
        d = (DE bsr 8) band 16#FF,
        e = DE band 16#FF
    },
    Machine#machine_state{cpu = Cpu1}.

assert_trap_result(Machine, Dest, Payload) ->
    Cpu = Machine#machine_state.cpu,
    ?assertEqual(16#05E2, z80_cpu:pc(Cpu)),
    ?assertEqual([], Machine#machine_state.tape_blocks),
    ?assertEqual(0, z80_cpu:get_reg_byte(d, Cpu)),
    ?assertEqual(0, z80_cpu:get_reg_byte(e, Cpu)),
    ?assertEqual(1, Cpu#cpu_state.f),  % carry set = success
    Bytes = [begin {B, _} = ezx_emulator:read_byte(Machine, Addr), B end
            || Addr <- lists:seq(Dest, Dest + byte_size(Payload) - 1)],
    ?assertEqual(binary:bin_to_list(Payload), Bytes).

build_tap(Payloads) ->
    iolist_to_binary([begin
        Body = <<16#FF, P/binary>>,
        Checksum = lists:foldl(fun(B, Acc) -> Acc bxor B end, 16#FF, binary:bin_to_list(P)),
        <<(byte_size(Body) + 1):16/little, Body/binary, Checksum>>
    end || P <- Payloads]).

%% --- Helpers ---

build_v1_header(PC, Flags) ->
    <<0:8, 0:8,
      0:16, 0:16,
      PC:16/little,
      16#FF00:16/little,
      0:8, 0:8,
      Flags:8,
      0:16, 0:16, 0:16, 0:16,
      0:8, 0:8,
      0:16, 0:16,
      0:8, 0:8,
      0:8>>.
