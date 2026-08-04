-module(ezx_emulator).

-include("z80_records.hrl").
-include("ezx_emulator.hrl").
-include("lib/sna.hrl").
-include("lib/z80.hrl").
-include("lib/tap.hrl").
-include("input/ezx_keyboard.hrl").

-export([
    init/7,
    step/1,
    run_frame/1,
    render_frame/1,
    render_beeper/1,
    render_ay_channels/1,
    set_render_screen/2,
    read_perf/1,
    reset_perf/1,
    load_sna/2,
    load_z80/2,
    load_tap/2,
    press_key/2,
    release_key/2,
    run_until_tstates/2,
    set_mouse_enabled/2,
    set_mouse_position/3,
    set_mouse_buttons/2,
    samples_per_frame/1,
    set_cpu_frequency/2,
    read_byte/2,
    write_byte/3,
    read_word/2,
    write_word/3,
    %% Shared device port handlers, referenced from both machines' port
    %% dispatch tables (48K in init/7, 128K in ezx_emulator_128:init/7).
    read_memory/3,
    write_memory/4,
    read_keyboard/3,
    write_border_beeper/4,
    read_ay/3,
    write_ay/4,
    read_kempston_mouse/3
]).

%% ZX Spectrum frame length in T-states.
-define(DEFAULT_BORDER, 1).

%% @doc Create a new machine state with initialized CPU and memory components
%% using the given timing model.
-spec init(#machine_model{}, module(), module(), module(), module(), module() | undefined, binary()) -> #machine_state{}.
init(Model, CPUModule, MemModule, KeyboardModule, BeeperModule, AyModule, Rom) ->
    MemReadFun = fun ezx_emulator:read_memory/3,
    MemWriteFun = fun ezx_emulator:write_memory/4,
    PortReadTable =
        [{16#0001, 16#00FE, fun ezx_emulator:read_keyboard/3},
         {16#0000, 16#FADB, fun ezx_emulator:read_kempston_mouse/3},
         {16#0002, 16#8001, fun ezx_emulator:read_ay/3}],
    PortWriteTable =
        [{16#0001, 16#00FE, fun ezx_emulator:write_border_beeper/4},
         {16#0002, 16#8001, fun ezx_emulator:write_ay/4}],
    PortReadFun =
        fun(ExtContext, TState, Port) ->
            ezx_emulator_lib:read_port(PortReadTable, ExtContext, TState, Port)
        end,
    PortWriteFun =
        fun(ExtContext, TState, Port, Byte) ->
            ezx_emulator_lib:write_port(PortWriteTable, ExtContext, TState, Port, Byte)
        end,
    BusReadFun = fun() -> 16#FF end,
    Cpu0 = z80_cpu:init_state(MemReadFun, MemWriteFun, PortReadFun, PortWriteFun, BusReadFun),
    #machine_state{
        model = Model,
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
        ay = case AyModule of undefined -> undefined; _ -> AyModule:new() end
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
        kempston_mouse = Machine#machine_state.kempston_mouse,
        memory_module = Machine#machine_state.memory_module,
        keyboard_module = Machine#machine_state.keyboard_module,
        beeper_module = Machine#machine_state.beeper_module,
        ay_module = Machine#machine_state.ay_module
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

%% @doc Execute one complete frame (69888 T-states) and close it: run the
%% CPU, render the device artifacts (beeper PCM, AY channels, ULA border/
%% flash, optionally the screen bitmap), and accumulate per-phase timings
%% into #machine_state.perf_stats. Each phase runs as a named step and is
%% timed independently, so the report shows where time actually goes.
-spec run_frame(#machine_state{}) -> #machine_state{}.
run_frame(Machine) ->
    PS0 = Machine#machine_state.perf_stats,
    {Machine1, CpuUs} = run_frame_execute(Machine),
    {Machine2, BeeperUs} = run_frame_render_beeper(Machine1),
    {Machine3, ScreenUs} = run_frame_render_screen_artifacts(Machine2),
    {Machine4, AyUs} = run_frame_render_ay(Machine3),
    {Machine5, RenderUs} = run_frame_render_screen_bitmap(Machine4),
    Machine5#machine_state{
        perf_stats = add_perf(PS0, CpuUs, BeeperUs, ScreenUs, AyUs, RenderUs)
    }.

%% Phase: input handling, device frame_start, and CPU execution of the frame.
run_frame_execute(Machine) ->
    timed(fun() ->
        MachineQ = process_keyboard_queue(Machine),
        TStates = MachineQ#machine_state.t_states,
        Machine1 = frame_start_devices(MachineQ, TStates),
        execute_frame(Machine1)
    end).

%% Rebase the device event timelines to the start of the frame.
frame_start_devices(#machine_state{ay_module = AyModule, beeper_module = BeeperModule} = Machine, TStates) ->
    Beeper = Machine#machine_state.beeper,
    Beeper1 = BeeperModule:frame_start(Beeper, TStates),
    Screen = Machine#machine_state.screen,
    Screen1 = ezx_screen:frame_start(Screen, TStates),
    MachineQ1 = Machine#machine_state{beeper = Beeper1, screen = Screen1},
    case AyModule of
        undefined ->
            MachineQ1;
        _ ->
            AY = MachineQ1#machine_state.ay,
            AY1 = AyModule:frame_start(AY, TStates),
            MachineQ1#machine_state{ay = AY1}
    end.

%% CPU execution of one frame. Two-phase execution:
%%   Phase 1: 0..IntTState-1 T-states — normal execution (no interrupt)
%%   Phase 2: IntTState..FrameLen-1 T-states — interrupt raised at boundary,
%%            then normal execution; the frame boundary is ignored
%%            mid-instruction (variant A), the overrun is carried as the
%%            new t_states tail.
execute_frame(#machine_state{t_states = StartT} = Machine) ->
    Model = Machine#machine_state.model,
    FrameLen = Model#machine_model.tstates_per_frame,
    IntTState = Model#machine_model.int_tstate,
    Cpu0 = Machine#machine_state.cpu,
    Cpu0a = z80_cpu:clear_interrupt_request(Cpu0),
    Machine0a = Machine#machine_state{cpu = Cpu0a},

    Machine1 = case StartT < IntTState of
        true ->
            run_until_tstates(Machine0a, IntTState);
        false ->
            Machine0a
    end,

    Cpu1 = Machine1#machine_state.cpu,
    Cpu2 = z80_cpu:request_interrupt(Cpu1, int),
    Machine2 = Machine1#machine_state{cpu = Cpu2},

    Phase2End = StartT + FrameLen,
    Machine3 = run_until_tstates(Machine2, Phase2End),

    Overshoot = Machine3#machine_state.t_states - Phase2End,

    Cpu3 = Machine3#machine_state.cpu,
    Cpu4 = Cpu3#cpu_state{t_states = Overshoot},

    Machine3#machine_state{
        cpu = Cpu4,
        t_states = Overshoot
    }.

%% Phase: render the beeper PCM for the frame (Samples S16LE mono samples).
run_frame_render_beeper(#machine_state{beeper_module = BeeperModule} = Machine) ->
    timed(fun() ->
        Beeper = Machine#machine_state.beeper,
        {FrameLen, Samples} = frame_audio_params(Machine),
        {BeeperPcm, Beeper1} = BeeperModule:frame_render(Beeper, FrameLen, Samples),
        Machine#machine_state{beeper = Beeper1, beeper_pcm = BeeperPcm}
    end).

%% Phase: render the ULA screen artifacts — sorted local-time border changes,
%% the base border color, and the attribute flash flag for this frame.
run_frame_render_screen_artifacts(Machine) ->
    timed(fun() ->
        Screen = Machine#machine_state.screen,
        FrameLen = (Machine#machine_state.model)#machine_model.tstates_per_frame,
        {Changes, CB, FlashOn, Screen1} = ezx_screen:frame_render(Screen, FrameLen),
        Machine#machine_state{
            screen = Screen1,
            screen_changes = Changes,
            screen_color = CB,
            flash_on = FlashOn
        }
    end).

%% Phase: render the AY-3-8912 channel PCMs (ChA, ChB, ChC).
run_frame_render_ay(#machine_state{ay_module = undefined} = Machine) ->
    {Machine#machine_state{ay_pcm = undefined}, 0};
run_frame_render_ay(#machine_state{ay_module = AyModule} = Machine) ->
    timed(fun() ->
        AY = Machine#machine_state.ay,
        {FrameLen, Samples} = frame_audio_params(Machine),
        {ChA, ChB, ChC, AY1} = AyModule:render_channels(AY, FrameLen, Samples),
        Machine#machine_state{ay = AY1, ay_pcm = {ChA, ChB, ChC}}
    end).

%% Phase: render the screen bitmap (352×288 RGB). Only when the render_screen
%% flag is set — the interactive UI enables it, headless consumers skip it.
run_frame_render_screen_bitmap(#machine_state{render_screen = false} = Machine) ->
    {Machine#machine_state{screen_pixels = undefined}, 0};
run_frame_render_screen_bitmap(#machine_state{render_screen = true} = Machine) ->
    timed(fun() ->
        Pixels = render_frame_now(Machine),
        Machine#machine_state{screen_pixels = Pixels}
    end).

%% Time a phase: returns {Result, Microseconds}.
timed(Fun) ->
    T0 = mono_us(),
    Result = Fun(),
    T1 = mono_us(),
    {Result, T1 - T0}.

add_perf(#perf_stats{frames = F, cpu_us = C, beeper_us = B, ay_us = A,
                     screen_us = S, render_us = R}, CpuUs, BeeperUs, ScreenUs, AyUs, RenderUs) ->
    #perf_stats{
        frames = F + 1,
        cpu_us = C + CpuUs,
        beeper_us = B + BeeperUs,
        ay_us = A + AyUs,
        screen_us = S + ScreenUs,
        render_us = R + RenderUs
    }.

mono_us() -> erlang:monotonic_time(microsecond).

%% @doc Enable or disable rendering of the screen bitmap inside run_frame/1.
%% The interactive UI enables it (the pixels land in screen_pixels each frame);
%% headless consumers leave it off to skip the per-frame render cost.
-spec set_render_screen(#machine_state{}, boolean()) -> #machine_state{}.
set_render_screen(Machine, true) ->
    Machine#machine_state{render_screen = true};
set_render_screen(Machine, false) ->
    Machine#machine_state{render_screen = false, screen_pixels = undefined}.

%% @doc Return the per-phase timing accumulators collected by run_frame/1.
-spec read_perf(#machine_state{}) -> #perf_stats{}.
read_perf(Machine) -> Machine#machine_state.perf_stats.

%% @doc Zero the timing accumulators (e.g. at the start of a report window).
-spec reset_perf(#machine_state{}) -> #machine_state{}.
reset_perf(Machine) -> Machine#machine_state{perf_stats = #perf_stats{}}.

%% @doc Audio samples produced per frame at the configured sample rate,
%% derived from the machine model: trunc(FrameLen * SampleRate / CpuClock).
%% Overclocking the CPU (set_cpu_frequency/2) shortens the real frame time
%% and thus the sample count.
-spec samples_per_frame(#machine_state{} | #machine_model{}) -> pos_integer().
samples_per_frame(#machine_state{model = Model}) ->
    samples_per_frame(Model);
samples_per_frame(#machine_model{cpu_clock = CpuClock, tstates_per_frame = FrameLen}) ->
    (FrameLen * ?SAMPLE_RATE) div CpuClock.

%% @doc Set an arbitrary CPU clock (overclock). The video raster (frame length
%% in T-states) is unchanged; the real frame time becomes TStatesPerFrame /
%% CpuClock, so the game runs faster (or slower) and the per-frame audio
%% sample count adjusts accordingly.
-spec set_cpu_frequency(#machine_state{}, pos_integer()) -> #machine_state{}.
set_cpu_frequency(#machine_state{model = Model} = Machine, Hz) when is_integer(Hz), Hz > 0 ->
    Machine#machine_state{model = Model#machine_model{cpu_clock = Hz}}.

%% Frame length + per-frame sample count, used by the audio render phases.
frame_audio_params(#machine_state{model = Model}) ->
    {Model#machine_model.tstates_per_frame, samples_per_frame(Model)}.

%% @doc Render the last frame to a flat RGB binary (352×288×3 bytes).
%% Returns the bitmap produced inside run_frame/1 when render_screen is
%% enabled; otherwise falls back to rendering on demand.
-spec render_frame(#machine_state{}) -> binary().
render_frame(#machine_state{screen_pixels = undefined} = Machine) ->
    render_frame_now(Machine);
render_frame(#machine_state{screen_pixels = Pixels}) ->
    Pixels.

render_frame_now(Machine) ->
    MemModule = Machine#machine_state.memory_module,
    FlashOn = Machine#machine_state.flash_on,
    Changes = Machine#machine_state.screen_changes,
    CB = Machine#machine_state.screen_color,
    Mem = Machine#machine_state.memory,
    %% 128K memory modules export read_video_block/1, which returns the first
    %% ?VIDEO_SIZE bytes of the bank selected for the display by p7FFD bit 3
    %% (bank 5 or 7). 48K modules have no paging, so the CPU view of 0x4000
    %% is the video memory itself.
    Videobuffer = case erlang:function_exported(MemModule, read_video_block, 1) of
        true -> MemModule:read_video_block(Mem);
        false -> MemModule:read_block(Mem, 16384, 6144 + 768)
    end,
    Model = Machine#machine_state.model,
    ezx_screen:render_screen(Videobuffer, FlashOn, Changes, CB,
                             Model#machine_model.tstates_per_line).

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

%% --- Shared device port handlers ---
%%
%% These are referenced directly from the port dispatch tables of both
%% machines as {ZeroMask, OneMask, fun Module:handler/N}. They read the
%% configured device module from #ext_context (populated in step_normal),
%% so a machine that lacks a device (AyModule = undefined) leaves the
%% matching state field undefined and the handler declines with nomatch,
%% falling through to the 0xFF read / ignore-write default.

%% CPU memory access. Memory reads are pure (they never mutate the device
%% context), so the handler returns just the byte — no {Byte, ExtContext}
%% round trip on the read path.
read_memory(#ext_context{memory = Memory, memory_module = MemModule}, _TState, Addr) ->
    MemModule:read_byte(Memory, Addr).

write_memory(#ext_context{memory = Memory, memory_module = MemModule} = ExtContext, _TState, Addr, Byte) ->
    case MemModule:write_byte(Memory, Addr, Byte) of
        Memory -> ExtContext;
        Memory1 -> ExtContext#ext_context{memory = Memory1}
    end.

%% Keyboard read row (A0=0): the port low byte selects the half-row, the
%% high byte is the (unused) "menu" bits; unused rows read as 1.
read_keyboard(ExtContext, _TState, Port) ->
    Keyboard = ExtContext#ext_context.keyboard,
    KeyboardModule = ExtContext#ext_context.keyboard_module,
    UpperByte = (Port bsr 8) band 16#FF,
    Result = KeyboardModule:decode(Keyboard, UpperByte),
    {Result bor 16#E0, ExtContext}.

%% Border + beeper write row (A0=0): bits 0-2 border color, bit 4 beeper.
write_border_beeper(ExtContext, TState, _Port, Byte) ->
    BeeperModule = ExtContext#ext_context.beeper_module,
    BeeperLevel = (Byte bsr 4) band 1,
    Screen0 = ExtContext#ext_context.screen,
    Screen1 = ezx_screen:border_set(Screen0, TState, Byte band 16#07),
    Beeper0 = ExtContext#ext_context.beeper,
    Beeper1 = BeeperModule:set_level(Beeper0, BeeperLevel, TState),
    ExtContext#ext_context{screen = Screen1, beeper = Beeper1}.

%% AY read row (A15=1, A1=0, A0=1; A14 is not decoded for reads, so both
%% 0xFFFD and 0xBFFD return the latched register).
read_ay(#ext_context{ay = undefined}, _TState, _Port) ->
    nomatch;
read_ay(#ext_context{ay = AY, ay_module = AyModule} = ExtContext, _TState, _Port) ->
    {AyModule:read(AY), ExtContext}.

%% AY write row (A15=1, A1=0, A0=1 — the only address bits the AY chip
%% select decodes): a single row covers both 0xBFFD data register (A14=0)
%% and 0xFFFD address latch (A14=1); the A14 bit (0x4000) selects which.
write_ay(#ext_context{ay = undefined}, _TState, _Port, _Byte) ->
    nomatch;
write_ay(#ext_context{ay = AY, ay_module = AyModule} = ExtContext, TState, Port, Byte) ->
    case Port band 16#4000 of
        0 -> ExtContext#ext_context{ay = AyModule:write(AY, Byte, TState)};
        _ -> ExtContext#ext_context{ay = AyModule:latch(AY, Byte)}
    end.

%% Kempston mouse port handler. The port → register mapping is owned by the
%% emulator (kempston_mouse_register/1); the device module only exposes its
%% registers. A machine with the mouse disabled keeps
%% #ext_context.kempston_mouse as undefined, so the handler declines with
%% nomatch and the port falls through to the 0xFF default.
read_kempston_mouse(#ext_context{kempston_mouse = undefined}, _TState, _Port) ->
    nomatch;
read_kempston_mouse(#ext_context{kempston_mouse = Mouse} = ExtContext, _TState, Port) ->
    case kempston_mouse_register(Port) of
        nomatch -> nomatch;
        Register -> {ezx_kempston_mouse:read(Mouse, Register), ExtContext}
    end.

%% Kempston mouse registers: buttons 0xFADF/0xFAFB, X 0xFBDF/0xFBFB,
%% Y 0xFFDF/0xFFFB. The register is selected by A8 (0x0100) and A10
%% (0x0400); A2/A5 are not decoded on the hardware, so each register
%% answers on both low-byte variants.
kempston_mouse_register(Port) ->
    case Port band 16#0500 of
        0 -> buttons;        %% A8 = 0, A10 = 0
        16#0100 -> x;        %% A8 = 1, A10 = 0
        16#0500 -> y;        %% A8 = 1, A10 = 1
        _ -> nomatch         %% A8 = 0, A10 = 1: no such register
    end.