-module(ezx_emulator_tests).

-include("z80_records.hrl").
-include("ezx_emulator.hrl").
-include_lib("eunit/include/eunit.hrl").

machine_step_advances_state_test() ->
    Machine0 = ezx_emulator:init(),
    Program = #{16#4000 => 16#00},
    Machine1 = ezx_emulator:load_program(Machine0, Program),
    Machine1b = ezx_emulator:set_pc(Machine1, 16#4000),
    Machine2 = ezx_emulator:step(Machine1b),
    ?assertEqual(16#4001, z80_cpu:pc(Machine2#machine_state.cpu)),
    ?assertEqual(4, z80_cpu:t_states(Machine2#machine_state.cpu)),
    ?assertEqual(4, Machine2#machine_state.t_states).

machine_run_until_tstates_test() ->
    Machine0 = ezx_emulator:init(),
    Program = #{16#4000 => 16#00, 16#4001 => 16#00, 16#4002 => 16#00},
    Machine1 = ezx_emulator:load_program(Machine0, Program),
    Machine1b = ezx_emulator:set_pc(Machine1, 16#4000),
    Machine2 = ezx_emulator:run_until_tstates(Machine1b, 12),
    ?assertEqual(16#4003, z80_cpu:pc(Machine2#machine_state.cpu)),
    ?assertEqual(12, z80_cpu:t_states(Machine2#machine_state.cpu)),
    ?assertEqual(12, Machine2#machine_state.t_states).

machine_loads_byte_lists_into_memory_test() ->
    Machine0 = ezx_emulator:init(),
    Machine1 = ezx_emulator:load_program(Machine0, 16#4000, [16#3E, 16#41]),
    {Byte0, _} = ezx_emulator:read_byte(Machine1, 16#4000),
    ?assertEqual(16#3E, Byte0),
    {Byte1, _} = ezx_emulator:read_byte(Machine1, 16#4001),
    ?assertEqual(16#41, Byte1).

machine_executes_program_from_memory_test() ->
    Machine0 = ezx_emulator:init(),
    Program = [16#3E, 16#41],
    Machine1 = ezx_emulator:load_program(Machine0, 16#4000, Program),
    Machine1b = ezx_emulator:set_pc(Machine1, 16#4000),
    Machine2 = ezx_emulator:step(Machine1b),
    ?assertEqual(16#4002, z80_cpu:pc(Machine2#machine_state.cpu)),
    ?assertEqual(16#41, z80_cpu:get_reg_byte(a, Machine2#machine_state.cpu)).

machine_state_keeps_cpu_and_memory_separate_test() ->
    Machine0 = ezx_emulator:init(),
    Machine1 = ezx_emulator:load_program(Machine0, 16#4000, [16#3E, 16#41]),
    ?assertEqual(0, z80_cpu:pc(Machine1#machine_state.cpu)),
    ?assertEqual(16#3E, ezx_memory_48:read_byte(Machine1#machine_state.memory, 16#4000)),
    ?assertEqual(16#41, ezx_memory_48:read_byte(Machine1#machine_state.memory, 16#4001)).

memory_reset_restores_initial_configuration_test() ->
    State0 = ezx_memory_48:new(<<0:65536/unit:8>>),
    _State1 = ezx_memory_48:write_byte(State0, 10, 42),
    State2 = ezx_memory_48:new(<<0:65536/unit:8>>),
    ?assertEqual(0, ezx_memory_48:read_byte(State2, 10)).

memory_reset_to_zero_test() ->
    Memory0 = ezx_memory_48:new(<<0:8/unit:8>>),
    _Memory1 = ezx_memory_48:write_byte(Memory0, 4, 16#99),
    Memory2 = ezx_memory_48:new(<<0:8/unit:8>>),
    ?assertEqual(0, ezx_memory_48:read_byte(Memory2, 4)).

%% --- run_frame tests ---

run_frame_completes_one_frame_test() ->
    Machine0 = ezx_emulator:init(),
    %% NOP loop at RAM address 0x4000.
    Machine1 = ezx_emulator:load_program(Machine0, #{16#4000 => 16#00}),
    Machine1b = ezx_emulator:set_pc(Machine1, 16#4000),
    Machine2 = ezx_emulator:run_frame(Machine1b),
    ?assertEqual(0, Machine2#machine_state.t_states).

run_frame_int_fires_test() ->
    Machine0 = ezx_emulator:init(),
    Machine1 = ezx_emulator:load_program(Machine0, #{16#4000 => 16#FB, 16#4001 => 16#00, 16#4002 => 16#00}),
    Machine1b = ezx_emulator:set_pc(Machine1, 16#4000),
    Machine2 = ezx_emulator:run_frame(Machine1b),
    Cpu = Machine2#machine_state.cpu,
    Pc = z80_cpu:pc(Cpu),
    ?assert(Pc >= 16#0038).

run_frame_border_changes_cleared_test() ->
    Machine0 = ezx_emulator:init(),
    Machine1 = ezx_emulator:load_program(Machine0, #{16#4000 => 16#3E, 16#4001 => 16#04, 16#4002 => 16#D3, 16#4003 => 16#FE}),
    Machine1b = ezx_emulator:set_pc(Machine1, 16#4000),
    Machine2 = ezx_emulator:run_frame(Machine1b),
    %% border_changes are now preserved after run_frame for rendering.
    %% They should be empty only if no OUT instructions executed.
    %% With the program above (OUT 0xFE, A), there should be one change.
    ?assertEqual([{7, 4}], Machine2#machine_state.border_changes).

run_frame_multiple_nops_test() ->
    Machine0 = ezx_emulator:init(),
    Nops = lists:duplicate(200, 16#00),
    Machine1 = ezx_emulator:load_program(Machine0, 16#4000, Nops),
    Machine1b = ezx_emulator:set_pc(Machine1, 16#4000),
    Machine2 = ezx_emulator:run_frame(Machine1b),
    Pc = z80_cpu:pc(Machine2#machine_state.cpu),
    ?assert(Pc >= 16#0038).

run_frame_two_frames_test() ->
    Machine0 = ezx_emulator:init(),
    Machine1 = ezx_emulator:load_program(Machine0, #{16#4000 => 16#00}),
    Machine1b = ezx_emulator:set_pc(Machine1, 16#4000),
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
    M0 = ezx_emulator:init(),
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

    M1 = ezx_emulator:load_program(M0r, 16#8000, Pgm),
    M2 = ezx_emulator:set_pc(M1, 16#8000),
    M3 = ezx_emulator:run_frame(M2),

    Changes = lists:keysort(1, M3#machine_state.border_changes),
    ?assertEqual(16, length(Changes)),

    FirstT = 3584,
    Interval = 4032,
    ExpectedColors = [0, 1, 2, 3, 4, 5, 6, 7, 0, 1, 2, 3, 4, 5, 6, 7],
    lists:foreach(fun({K, {T, Color}}) ->
        ?assertEqual(FirstT + K * Interval, T),
        ?assertEqual(lists:nth(K + 1, ExpectedColors), Color)
    end, lists:zip(lists:seq(0, 15), Changes)),

    %% --- Verify rendered pixel colors ---
    Mem = M3#machine_state.memory,
    CB = M3#machine_state.border_color,
    ReadFun = fun(Addr) -> ezx_memory_48:read_byte(Mem, Addr band 16#FFFF) end,
    Frame = ezx_video:decode_full_frame(ReadFun, 0, Changes, CB),

    Palette = {
        {0, 0, 0}, {0, 0, 215}, {215, 0, 0}, {215, 0, 215},
        {0, 215, 0}, {0, 215, 215}, {215, 215, 0}, {215, 215, 215}
    },

    lists:foreach(fun(K) ->
        VisY = K * 18,
        {R, G, B} = lists:nth(5, lists:nth(VisY + 1, Frame)),
        ExpectedColor = lists:nth(K + 1, ExpectedColors),
        ?assertEqual(element(ExpectedColor + 1, Palette), {R, G, B})
    end, lists:seq(0, 15)).
