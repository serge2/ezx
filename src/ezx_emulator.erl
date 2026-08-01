-module(ezx_emulator).

-include("z80_records.hrl").
-include("ezx_emulator.hrl").
-include("lib/sna.hrl").
-include("lib/z80.hrl").
-include("lib/tap.hrl").
-include("input/ezx_keyboard.hrl").

-export([
    init/6,
    step/1,
    run_frame/1,
    render_frame/1,
    render_beeper/1,
    render_ay_channels/1,
    load_sna/2,
    load_z80/2,
    load_tap/2,
    press_key/2,
    release_key/2,
    run_until_tstates/2,
    set_mouse_enabled/2,
    set_mouse_position/3,
    set_mouse_buttons/2,
    read_byte/2,
    write_byte/3,
    read_word/2,
    write_word/3
]).

%% ZX Spectrum frame length in T-states.
-define(DEFAULT_BORDER, 1).

%% @doc Create a new machine state with initialized CPU and memory components.
-spec init(module(), module(), module(), module(), module() | undefined, binary()) -> #machine_state{}.
init(CPUModule, MemModule, KeyboardModule, BeeperModule, AyModule, Rom) ->
    HasAy = AyModule =/= undefined,
    MemReadFun =
        fun(ExtContext, _TState, Addr) ->
            Memory = ExtContext#ext_context.memory,
            Byte = MemModule:read_byte(Memory, Addr),
            {Byte, ExtContext}
        end,
    MemWriteFun =
        fun(ExtContext, _TState, Addr, Byte) ->
            Memory = ExtContext#ext_context.memory,
            NewMem = MemModule:write_byte(Memory, Addr, Byte),
            ExtContext#ext_context{memory = NewMem}
        end,
    PortReadFun =
        fun(ExtContext, _TState, Port) ->
            case Port band 16#FF of
                16#FE ->
                    Keyboard = ExtContext#ext_context.keyboard,
                    UpperByte = (Port bsr 8) band 16#FF,
                    Result = KeyboardModule:decode(Keyboard, UpperByte),
                    {Result bor 16#E0, ExtContext};
                _ ->
                    case read_kempston(ExtContext, Port) of
                        undefined ->
                            case HasAy andalso (Port band 16#8002) =/= 0 of
                                true ->
                                    AY = ExtContext#ext_context.ay,
                                    {AyModule:read(AY), ExtContext};
                                false ->
                                    {16#FF, ExtContext}
                            end;
                        Byte ->
                            {Byte, ExtContext}
                    end
            end
        end,
    PortWriteFun =
        fun(ExtContext, TState, Port, Byte) ->
            case Port band 16#FF of
                16#FE ->
                    BeeperLevel = (Byte bsr 4) band 1,
                    Screen0 = ExtContext#ext_context.screen,
                    Screen1 = ezx_screen:border_set(Screen0, TState, Byte band 16#07),
                    Beeper0 = ExtContext#ext_context.beeper,
                    Beeper1 = BeeperModule:set_level(Beeper0, BeeperLevel, TState),
                    ExtContext#ext_context{
                        screen = Screen1,
                        beeper = Beeper1
                    };
                _ ->
                    case HasAy andalso (Port band 16#8002) =/= 0 of
                        true ->
                            AY = ExtContext#ext_context.ay,
                            case (Port band 16#4000) =:= 0 of
                                true ->
                                    ExtContext#ext_context{ay = AyModule:write(AY, Byte, TState)};
                                false ->
                                    ExtContext#ext_context{ay = AyModule:latch(AY, Byte)}
                            end;
                        false ->
                            ExtContext
                    end
            end
        end,
    BusReadFun = fun() -> 16#FF end,
    Cpu0 = z80_cpu:init_state(MemReadFun, MemWriteFun, PortReadFun, PortWriteFun, BusReadFun),
    #machine_state{
        cpu_module = CPUModule,
        memory_module = MemModule,
        keyboard_module = KeyboardModule,
        beeper_module = BeeperModule,
        ay_module = AyModule,
        cpu = Cpu0,
        memory = MemModule:new(Rom),
        screen = ezx_screen:new(),
        beeper = BeeperModule:init(),
        keyboard = KeyboardModule:default(),
        ay = case HasAy of true -> AyModule:new(); false -> undefined end
    }.

-spec press_key(#machine_state{}, non_neg_integer()) -> #machine_state{}.
press_key(Machine, OrigKey) ->
    KBModule = Machine#machine_state.keyboard_module,
    KB = Machine#machine_state.keyboard,
    Keys = maps:get(OrigKey, key_map(), []),
    NewKB = KBModule:press_keys(KB, Keys),
    Machine#machine_state{keyboard = NewKB}.

-spec release_key(#machine_state{}, non_neg_integer()) -> #machine_state{}.
release_key(Machine, OrigKey) ->
    KBModule = Machine#machine_state.keyboard_module,
    KB = Machine#machine_state.keyboard,
    Keys = maps:get(OrigKey, key_map(), []),
    NewKB = KBModule:release_keys(KB, Keys),
    Machine#machine_state{keyboard = NewKB}.

%% @doc Enable or disable the optional Kempston mouse interface.
-spec set_mouse_enabled(#machine_state{}, boolean()) -> #machine_state{}.
set_mouse_enabled(Machine, true) ->
    Machine#machine_state{kempston_mouse = ezx_kempston_mouse:new()};
set_mouse_enabled(Machine, false) ->
    Machine#machine_state{kempston_mouse = undefined}.

%% @doc Accumulate host mouse deltas into the Kempston X/Y counters.
%% No-op when the mouse is disabled.
-spec set_mouse_position(#machine_state{}, integer(), integer()) -> #machine_state{}.
set_mouse_position(#machine_state{kempston_mouse = undefined} = Machine, _DX, _DY) ->
    Machine;
set_mouse_position(#machine_state{kempston_mouse = Mouse} = Machine, DX, DY) ->
    Machine#machine_state{kempston_mouse = ezx_kempston_mouse:move(Mouse, DX, DY)}.

%% @doc Set the active-low Kempston button mask (bit 0 right, bit 1 left, bit 2 middle).
%% No-op when the mouse is disabled.
-spec set_mouse_buttons(#machine_state{}, non_neg_integer()) -> #machine_state{}.
set_mouse_buttons(#machine_state{kempston_mouse = undefined} = Machine, _Buttons) ->
    Machine;
set_mouse_buttons(#machine_state{kempston_mouse = Mouse} = Machine, Buttons) ->
    Machine#machine_state{kempston_mouse = ezx_kempston_mouse:set_buttons(Mouse, Buttons)}.

%% @doc Load a 48K SNA snapshot.
-spec load_sna(#machine_state{}, binary()) -> {ok, #machine_state{}} | {error, {atom(), binary()}}.
load_sna(Machine, Data) ->
    try ezx_sna:parse(Data) of
        #sna_header{is_128k = true} ->
            {error, {unsupported_version, <<"128K SNA cannot be loaded on a 48K machine">>}};
        H ->
            MemModule = Machine#machine_state.memory_module,
            Mem = Machine#machine_state.memory,

            MemList = binary:bin_to_list(H#sna_header.mem),
            {_FinalOffset, Mem1} = lists:foldl(
                fun(Byte, {Offset, MemAcc}) ->
                    Addr = 16384 + Offset,
                    {Offset + 1, MemModule:write_byte(MemAcc, Addr, Byte)}
                end, {0, Mem}, MemList),

            SP = H#sna_header.sp,
            SP1 = (SP + 2) band 16#FFFF,
            PCL = MemModule:read_byte(Mem1, SP band 16#FFFF),
            PCH = MemModule:read_byte(Mem1, (SP + 1) band 16#FFFF),
            PC = (PCH bsl 8) bor PCL,
            AF = H#sna_header.af,
            BC = H#sna_header.bc,
            DE = H#sna_header.de,
            HL = H#sna_header.hl,
            IX = H#sna_header.ix,
            IY = H#sna_header.iy,
            AFp = H#sna_header.af_alt,
            BCp = H#sna_header.bc_alt,
            DEp = H#sna_header.de_alt,
            HLp = H#sna_header.hl_alt,
            Cpu = Machine#machine_state.cpu,
            IM = H#sna_header.im,
            Cpu1 = Cpu#cpu_state{
                i = H#sna_header.i, r = H#sna_header.r,
                a = AF bsr 8, f = AF band 16#FF,
                b = BC bsr 8, c = BC band 16#FF,
                d = DE bsr 8, e = DE band 16#FF,
                h = HL bsr 8, l = HL band 16#FF,
                sp = SP1, pc = PC,
                ixh = IX bsr 8, ixl = IX band 16#FF,
                iyh = IY bsr 8, iyl = IY band 16#FF,
                iff1 = H#sna_header.iff2, iff2 = H#sna_header.iff2,
                im = IM,
                a_alt = AFp bsr 8, f_alt = AFp band 16#FF,
                b_alt = BCp bsr 8, c_alt = BCp band 16#FF,
                d_alt = DEp bsr 8, e_alt = DEp band 16#FF,
                h_alt = HLp bsr 8, l_alt = HLp band 16#FF,
                pending_interrupt = none
            },
            {ok, Machine#machine_state{
                memory = Mem1,
                cpu = Cpu1,
                screen = ezx_screen:new(H#sna_header.border),
                t_states = 0,
                beeper_pcm = <<>>
            }}
    catch
        error:bad_sna_header ->
            S = byte_size(Data),
            {error, {bad_sna_header,
                     iolist_to_binary(["Expected >= 49179 bytes, got ",
                                       integer_to_binary(S)])}};
        C:E:_S ->
            {error, {sna_load_failed, iolist_to_binary(io_lib:format("~p:~p", [C, E]))}}
    end.

%% @doc Load a Z80 snapshot (v1/v2/v3).
-spec load_z80(#machine_state{}, binary()) -> {ok, #machine_state{}} | {error, {atom(), binary()}}.
load_z80(Machine, Data) ->
    MemModule = Machine#machine_state.memory_module,
    try ezx_z80:parse(Data) of
        #z80_header{is_128k = true} ->
            {error, {unsupported_version, <<"128K Z80 snapshot cannot be loaded on a 48K machine">>}};
        H ->
            Mem = Machine#machine_state.memory,
            MemList = binary:bin_to_list(H#z80_header.mem),
            {_, Mem1} = lists:foldl(
                fun(Byte, {Offset, MemAcc}) ->
                    Addr = 16384 + Offset,
                    {Offset + 1, MemModule:write_byte(MemAcc, Addr, Byte)}
                end, {0, Mem}, MemList),

            Cpu = Machine#machine_state.cpu,
            Cpu1 = Cpu#cpu_state{
                a = H#z80_header.a, f = H#z80_header.f,
                b = H#z80_header.bc bsr 8, c = H#z80_header.bc band 16#FF,
                d = H#z80_header.de bsr 8, e = H#z80_header.de band 16#FF,
                h = H#z80_header.hl bsr 8, l = H#z80_header.hl band 16#FF,
                sp = H#z80_header.sp, pc = H#z80_header.pc,
                ixh = H#z80_header.ix bsr 8, ixl = H#z80_header.ix band 16#FF,
                iyh = H#z80_header.iy bsr 8, iyl = H#z80_header.iy band 16#FF,
                iff1 = H#z80_header.iff1, iff2 = H#z80_header.iff2,
                im = H#z80_header.im,
                i = H#z80_header.i, r = H#z80_header.r,
                a_alt = H#z80_header.a_alt, f_alt = H#z80_header.f_alt,
                b_alt = H#z80_header.bc_alt bsr 8, c_alt = H#z80_header.bc_alt band 16#FF,
                d_alt = H#z80_header.de_alt bsr 8, e_alt = H#z80_header.de_alt band 16#FF,
                h_alt = H#z80_header.hl_alt bsr 8, l_alt = H#z80_header.hl_alt band 16#FF,
                pending_interrupt = none
            },
            {ok, Machine#machine_state{
                memory = Mem1,
                cpu = Cpu1,
                screen = ezx_screen:new(H#z80_header.border),
                t_states = 0,
                beeper_pcm = <<>>
            }}
    catch
        error:bad_z80_header ->
            S = byte_size(Data),
            {error, {bad_z80_header,
                     iolist_to_binary(["Expected valid Z80 snapshot, got ",
                                       integer_to_binary(S), " bytes"])}};
        C:E:_S ->
            {error, {z80_load_failed, iolist_to_binary(io_lib:format("~p:~p", [C, E]))}}
    end.

%% @doc Load a TAP file using tape traps.
-spec load_tap(#machine_state{}, binary()) -> {ok, #machine_state{}} | {error, {atom(), binary()}}.
load_tap(Machine, Data) ->
    try ezx_tap:parse_blocks(Data) of
        Blocks ->
            io:format("TAP: parsed ~p blocks~n", [length(Blocks)]),
            Q = make_load_queue(),
            {ok, Machine#machine_state{
                tape_blocks = Blocks,
                keyboard_queue = Q
            }}
    catch
        C:E:_S ->
            {error, {bad_tap_data,
                     iolist_to_binary(io_lib:format("~p:~p", [C, E]))}}
    end.

%% --- Tape trap: intercept LD-BYTES at PC=0x0556 ---

tape_trap(#machine_state{cpu = Cpu, tape_blocks = [#tap_block{payload = Data} | RestBlocks]} = Machine,
          MachineTStates) ->
    IX = (Cpu#cpu_state.ixh bsl 8) bor Cpu#cpu_state.ixl,
    DE = (Cpu#cpu_state.d bsl 8) bor Cpu#cpu_state.e,
    DataList = binary:bin_to_list(Data),
    WriteLen = min(DE, length(DataList)),
    {WriteData, _} = lists:split(WriteLen, DataList),
    Machine1 = write_block(Machine, IX, WriteData),
    NewIX = (IX + WriteLen) band 16#FFFF,
    Cpu1 = Cpu#cpu_state{
        pc = 16#05E2,
        ixh = (NewIX bsr 8) band 16#FF,
        ixl = NewIX band 16#FF,
        d = 0, e = 0,
        b = 16#B0, a = 0,
        f = 1,  %% carry set = success
        halted = false,
        prefix = none
    },
    TStatesDelta = 1000,
    NewMT = MachineTStates + TStatesDelta,
    io:format("Tape trap: ~p bytes at 0x~.16B (~p left)~n",
              [WriteLen, IX, length(RestBlocks)]),
    Machine1#machine_state{
        cpu = Cpu1#cpu_state{t_states = NewMT},
        t_states = NewMT,
        tape_blocks = RestBlocks
    }.

write_block(Machine, _Addr, []) -> Machine;
write_block(Machine, Addr, [Byte | Rest]) ->
    Machine1 = write_byte(Machine, Addr band 16#FFFF, Byte),
    write_block(Machine1, (Addr + 1) band 16#FFFF, Rest).

%% --- Auto-typing keyboard queue for LOAD "" ---

make_load_queue() ->
     [
        {150, release},
        {3, {set, [?KEY_J]}},                   % LOAD
        {10, release},
        {3, {set, [?KEY_SYMB_SHIFT, ?KEY_P]}},  % "
        {5, release},
        {3, {set, [?KEY_SYMB_SHIFT, ?KEY_P]}},  % "
        {5, release},
        {3, {set, [?KEY_ENTER]}},               % ENTER
        {5, release}
    ].

%% @doc Process one step of the keyboard auto-typing queue (called per frame).
%% Queue elements: {repeat, N, Action} where Action is {set, KB} or release.
%% Each frame consumes one count from the current repeat block.
process_keyboard_queue(#machine_state{keyboard_queue = [{N, Action} | Rest]} = Machine) when N > 0 ->

    KB = Machine#machine_state.keyboard,
    KBModule = Machine#machine_state.keyboard_module,
    KB1 = apply_kb_action(KBModule, KB, Action),
    Machine#machine_state{keyboard = KB1, keyboard_queue = [{N - 1, Action} | Rest]};

process_keyboard_queue(#machine_state{keyboard_queue = [{0, _Action} | Rest]} = Machine) ->
    Machine#machine_state{keyboard_queue = Rest};

process_keyboard_queue(Machine) ->
    Machine.

apply_kb_action(KBModule, KB, release) -> KBModule:release_all(KB);
apply_kb_action(KBModule, KB, {set, Keys}) -> KBModule:press_keys(KB, Keys).


key_map() ->
    #{
        306  => [?KEY_CAPS_SHIFT], %SHIFT
        $Z   => [?KEY_Z],
        $X   => [?KEY_X],
        $C   => [?KEY_C],
        $V   => [?KEY_V],

        $A   => [?KEY_A],
        $S   => [?KEY_S],
        $D   => [?KEY_D],
        $F   => [?KEY_F],
        $G   => [?KEY_G],

        $Q   => [?KEY_Q],
        $W   => [?KEY_W],
        $E   => [?KEY_E],
        $R   => [?KEY_R],
        $T   => [?KEY_T],

        $1   => [?KEY_1],
        $2   => [?KEY_2],
        $3   => [?KEY_3],
        $4   => [?KEY_4],
        $5   => [?KEY_5],

        $0   => [?KEY_0],
        $9   => [?KEY_9],
        $8   => [?KEY_8],
        $7   => [?KEY_7],
        $6   => [?KEY_6],

        $P   => [?KEY_P],
        $O   => [?KEY_O],
        $I   => [?KEY_I],
        $U   => [?KEY_U],
        $Y   => [?KEY_Y],

        13   => [?KEY_ENTER], 370 => [?KEY_ENTER],  %% ENTER
        $L   => [?KEY_L],
        $K   => [?KEY_K],
        $J   => [?KEY_J],
        $H   => [?KEY_H],

        32   => [?KEY_SPACE],
        307  => [?KEY_SYMB_SHIFT], 0 => [?KEY_SYMB_SHIFT], %% ALT
        $M   => [?KEY_M],
        $N   => [?KEY_N],
        $B   => [?KEY_B],

        8    => [?KEY_CAPS_SHIFT, ?KEY_0],   %% BACKSPACE
        314  => [?KEY_CAPS_SHIFT, ?KEY_5],   %% LEFT
        315  => [?KEY_CAPS_SHIFT, ?KEY_7],   %% UP
        316  => [?KEY_CAPS_SHIFT, ?KEY_8],   %% RIGHT
        317  => [?KEY_CAPS_SHIFT, ?KEY_6]    %% DOWN
    }.

-spec read_byte(#machine_state{}, non_neg_integer()) -> {byte(), #machine_state{}}.
read_byte(#machine_state{memory = Mem, memory_module = MemoryModule} = Machine, Addr) ->
    Byte = MemoryModule:read_byte(Mem, Addr),
    {Byte, Machine}.

%% @doc Write a byte into the machine memory.
-spec write_byte(#machine_state{}, non_neg_integer(), byte()) -> #machine_state{}.
write_byte(#machine_state{memory = Mem, memory_module = MemoryModule} = Machine, Addr, Byte) ->
    Mem1 = MemoryModule:write_byte(Mem, Addr, Byte),
    Machine#machine_state{memory = Mem1}.

%% @doc Read a 16-bit word from the machine memory.
-spec read_word(#machine_state{}, non_neg_integer()) -> {non_neg_integer(), #machine_state{}}.
read_word(Machine, Addr) ->
    {ByteL, Machine1} = read_byte(Machine, Addr),
    {ByteH, Machine2} = read_byte(Machine1, Addr + 1),
    {ByteL + (ByteH bsl 8), Machine2}.

%% @doc Write a 16-bit word into the machine memory.
-spec write_word(#machine_state{}, non_neg_integer(), non_neg_integer()) -> #machine_state{}.
write_word(Machine, Addr, Word) ->
    Machine1 = write_byte(Machine, Addr, Word band 16#ff),
    write_byte(Machine1, Addr + 1, (Word bsr 8) band 16#ff).


%% @doc Execute one machine step by advancing the CPU once and updating machine time.
-spec step(#machine_state{}) -> #machine_state{}.
step(#machine_state{t_states = MachineTStates, tape_blocks = [_ | _]} = Machine) ->
    Cpu0 = Machine#machine_state.cpu,
    case Cpu0#cpu_state.pc of
        16#0556 -> tape_trap(Machine, MachineTStates);
        _ -> step_normal(Machine)
    end;
step(Machine) ->
    step_normal(Machine).

step_normal(#machine_state{t_states = MachineTStates} = Machine) ->
    Cpu0 = Machine#machine_state.cpu,
    Memory0 = Machine#machine_state.memory,
    Beeper0 = Machine#machine_state.beeper,
    ExtContext0 = #ext_context{
        memory = Memory0,
        screen = Machine#machine_state.screen,
        keyboard = Machine#machine_state.keyboard,
        beeper = Beeper0,
        ay = Machine#machine_state.ay,
        kempston_mouse = Machine#machine_state.kempston_mouse
    },
    Cpu1 = z80_cpu:step(Cpu0#cpu_state{ext_context = ExtContext0, t_states = MachineTStates}),
    Ticks = Cpu1#cpu_state.t_states - MachineTStates,
    NewMachineTStates = MachineTStates + Ticks,
    ExtCtx = Cpu1#cpu_state.ext_context,
    Memory1 = ExtCtx#ext_context.memory,
    Beeper1 = ExtCtx#ext_context.beeper,
    Machine#machine_state{
        cpu = Cpu1#cpu_state{t_states = NewMachineTStates},
        memory = Memory1,
        t_states = NewMachineTStates,
        screen = ExtCtx#ext_context.screen,
        beeper = Beeper1,
        ay = ExtCtx#ext_context.ay,
        kempston_mouse = ExtCtx#ext_context.kempston_mouse
    }.

%% @doc Execute one complete frame (69888 T-states).
%% Two-phase execution:
%%   Phase 1: 0..31 T-states — normal execution (no interrupt)
%%   Phase 2: 32..69887 T-states — interrupt raised at boundary, then normal execution
%% Frame boundary is ignored mid-instruction (variant A).
%% Closes the frame by rendering the device artifacts (beeper PCM, AY channel
%% PCMs, border changes/color) into the machine state.
-spec run_frame(#machine_state{}) -> #machine_state{}.
run_frame(#machine_state{ay_module = AyModule, beeper_module = BeeperModule} = Machine) ->
    MachineQ = process_keyboard_queue(Machine),
    TStates = MachineQ#machine_state.t_states,
    Beeper = MachineQ#machine_state.beeper,
    Beeper1 = BeeperModule:frame_start(Beeper, TStates),
    Screen = MachineQ#machine_state.screen,
    Screen1 = ezx_screen:frame_start(Screen, TStates),
    MachineQ1 = MachineQ#machine_state{beeper = Beeper1, screen = Screen1},
    Machine1 = case AyModule of
        undefined ->
            run_frame_1(MachineQ1);
        _ ->
            AY = MachineQ1#machine_state.ay,
            AY1 = AyModule:frame_start(AY, TStates),
            run_frame_1(MachineQ1#machine_state{ay = AY1})
    end,
    render_frame_artifacts(Machine1).

%% @doc Produce the frame's output artifacts from the device frame_render
%% callbacks and store them in the machine state, together with the updated
%% device states (which carry the frame-overrun tails into the next frame).
render_frame_artifacts(#machine_state{ay_module = AyModule, beeper_module = BeeperModule} = Machine) ->
    Beeper = Machine#machine_state.beeper,
    {BeeperPcm, Beeper1} = BeeperModule:frame_render(Beeper, ?TSTATES_PER_FRAME),
    Screen = Machine#machine_state.screen,
    {Changes, CB, FlashOn, Screen1} = ezx_screen:frame_render(Screen, ?TSTATES_PER_FRAME),
    Machine1 = Machine#machine_state{
        beeper = Beeper1,
        beeper_pcm = BeeperPcm,
        screen = Screen1,
        screen_changes = Changes,
        screen_color = CB,
        flash_on = FlashOn
    },
    case AyModule of
        undefined ->
            Machine1#machine_state{ay_pcm = undefined};
        _ ->
            AY = Machine1#machine_state.ay,
            {ChA, ChB, ChC, AY1} = AyModule:render_channels(AY, ?TSTATES_PER_FRAME),
            Machine1#machine_state{ay = AY1, ay_pcm = {ChA, ChB, ChC}}
    end.

run_frame_1(#machine_state{t_states = StartT} = Machine) ->
    Cpu0 = Machine#machine_state.cpu,
    Cpu0a = Cpu0#cpu_state{pending_interrupt = none},
    Machine0a = Machine#machine_state{cpu = Cpu0a},

    Machine1 = case StartT < ?INT_TSTATE of
        true ->
            run_until_tstates(Machine0a, ?INT_TSTATE);
        false ->
            Machine0a
    end,

    Cpu1 = Machine1#machine_state.cpu,
    Cpu2 = z80_cpu:request_interrupt(Cpu1, int),
    Machine2 = Machine1#machine_state{cpu = Cpu2},

    Phase2End = StartT + ?TSTATES_PER_FRAME,
    Machine3 = run_until_tstates(Machine2, Phase2End),

    Overshoot = Machine3#machine_state.t_states - Phase2End,

    Cpu3 = Machine3#machine_state.cpu,
    Cpu4 = Cpu3#cpu_state{t_states = Overshoot},

    Machine3#machine_state{
        cpu = Cpu4,
        t_states = Overshoot
    }.

%% @doc Render the current frame to a flat RGB binary (352×288×3 bytes).
%% Extracts screen memory via bulk read_block and passes to ezx_screen.
%% Uses the screen artifacts (border changes/color, flash flag) produced by
%% run_frame/1.
-spec render_frame(#machine_state{}) -> binary().
render_frame(Machine) ->
    MemModule = Machine#machine_state.memory_module,
    FlashOn = Machine#machine_state.flash_on,
    Changes = Machine#machine_state.screen_changes,
    CB = Machine#machine_state.screen_color,
    Mem = Machine#machine_state.memory,
    Videobuffer = MemModule:read_block(Mem, 16384, 6144 + 768),
    ezx_screen:render_screen(Videobuffer, FlashOn, Changes, CB).

%% @doc Beeper PCM (mono S16LE) produced by the last run_frame/1.
-spec render_beeper(#machine_state{}) -> {binary(), #machine_state{}}.
render_beeper(Machine) ->
    {Machine#machine_state.beeper_pcm, Machine}.

%% @doc AY channel PCMs (mono S16LE, one per channel) from the last run_frame/1.
-spec render_ay_channels(#machine_state{}) -> {binary(), binary(), binary(), #machine_state{}}.
render_ay_channels(#machine_state{ay_pcm = undefined} = Machine) ->
    {<<>>, <<>>, <<>>, Machine};
render_ay_channels(#machine_state{ay_pcm = {ChA, ChB, ChC}} = Machine) ->
    {ChA, ChB, ChC, Machine}.


%% @doc Advance the machine until the accumulated T-state budget is reached.
-spec run_until_tstates(#machine_state{}, non_neg_integer()) -> #machine_state{}.
run_until_tstates(Machine, Target) when is_integer(Target), Target =< 0 ->
    Machine;
run_until_tstates(Machine, Target) ->
    case Machine#machine_state.t_states >= Target of
        true -> Machine;
        false -> run_until_tstates(step(Machine), Target)
    end.


%% --- Internal ---

%% Read the Kempston mouse ports if the mouse is present. Returns
%% undefined for any other port so the caller falls back to other hardware.
read_kempston(#ext_context{kempston_mouse = undefined}, _Port) ->
    undefined;
read_kempston(#ext_context{kempston_mouse = Mouse}, Port) ->
    ezx_kempston_mouse:read(Mouse, Port).