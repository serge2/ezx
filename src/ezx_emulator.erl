-module(ezx_emulator).

-include("z80_records.hrl").
-include("ezx_emulator.hrl").
-include("format/sna.hrl").
-include("format/tap.hrl").
-include("input/ezx_keyboard.hrl").

-export([
    init/0,
    init/6,
    step/1,
    run_frame/1,
    render_frame/2,
    load_program/2,
    load_program/3,
    load_sna/2,
    load_tap/2,
    reset/1,
    set_pc/2,
    set_keyboard/2,
    press_key/2,
    release_key/2,
    run_until_tstates/2,
    read_byte/2,
    write_byte/3,
    read_word/2,
    write_word/3
]).

%% ZX Spectrum frame length in T-states.
-define(TSTATES_PER_FRAME, 69888).
-define(INT_TSTATE, 32).
-define(DEFAULT_BORDER, 1).

init() ->
    RomPath = try filename:join([code:priv_dir(ezx), "roms", "48.rom"])
    catch error:badarg ->
        %% Fallback: priv is a sibling of ebin in the OTP lib structure
        BeamDir = filename:dirname(code:which(?MODULE)),
        filename:join([filename:dirname(BeamDir), "priv", "roms", "48.rom"])
    end,
    {ok, Rom} = file:read_file(RomPath),
    init(z80_cpu, ezx_memory_48, ezx_video2, ezx_keyboard, ezx_beeper, Rom).

%% @doc Create a new machine state with initialized CPU and memory components.
-spec init(module(), module(), module(), module(), module(), binary()) -> #machine_state{}.
init(CPUModule, MemModule, VideoModule, KeyboardModule, BeeperModule, Rom) ->
    MemReadFun =
        fun(ExtContext, Addr) ->
            Memory = ExtContext#ext_context.memory,
            Byte = MemModule:read_byte(Memory, Addr band 16#ffff),
            {Byte, ExtContext}
        end,
    MemWriteFun =
        fun(ExtContext, Addr, Byte) ->
            Memory = ExtContext#ext_context.memory,
            NewMem = MemModule:write_byte(Memory, Addr band 16#ffff, Byte band 16#ff),
            ExtContext#ext_context{memory = NewMem}
        end,
    PortReadFun =
        fun(ExtContext, Port) ->
            case Port band 16#FF of
                16#FE ->
                    %% Keyboard: upper byte selects half-rows (active low).
                    %% Multiple half-rows can be selected; results are ANDed.
                    Keyboard = ExtContext#ext_context.keyboard,
                    UpperByte = (Port bsr 8) band 16#FF,
                    Result = KeyboardModule:decode(Keyboard, UpperByte),
                    {Result bor 16#E0, ExtContext}; % Set high bits 5-7 to 1 (floating bus)
                _ ->
                    {16#FF, ExtContext}
            end
        end,
    PortWriteFun =
        fun(ExtContext, Port, Byte) ->
            case Port band 16#FF of
                16#FE ->
                    BorderColor = Byte band 16#07,
                    TState = ExtContext#ext_context.t_states,
                    Changes = ExtContext#ext_context.border_changes,
                    %% Bit 4: beeper speaker output.
                    BeeperLevel = (Byte bsr 4) band 1,
                    Beeper0 = ExtContext#ext_context.beeper,
                    Beeper1 = BeeperModule:set_level(Beeper0, BeeperLevel, TState),
                    NewChanges = case Changes of
                        [{_, BorderColor} | _] -> Changes;
                        _ -> [{TState, BorderColor} | Changes]
                    end,
                    ExtContext#ext_context{
                        border_changes = NewChanges,
                        beeper = Beeper1
                    };
                _ ->
                    ExtContext
            end
        end,
    BusReadFun = fun() -> 16#FF end,
    Cpu0 = z80_cpu:init_state(MemReadFun, MemWriteFun, PortReadFun, PortWriteFun, BusReadFun),
    #machine_state{
        cpu_module = CPUModule,
        memory_module = MemModule,
        video_module = VideoModule,
        keyboard_module = KeyboardModule,
        beeper_module = BeeperModule,
        cpu = Cpu0,
        memory = MemModule:new(Rom),
        % mem_read_fun = MemReadFun,
        % mem_write_fun = MemWriteFun,
        beeper = BeeperModule:init(),
        keyboard = KeyboardModule:default()
    }.

%% @doc Load a program into memory starting at address 0.
-spec load_program(#machine_state{}, [byte()] | map()) -> #machine_state{}.
load_program(Machine, Program) when is_list(Program) ->
    load_program(Machine, 0, Program);
load_program(Machine, Program) when is_map(Program) ->
    maps:fold(fun(Addr, Byte, M) ->
        write_byte(M, Addr, Byte)
    end, Machine, Program).

-spec load_program(#machine_state{}, non_neg_integer(), [byte()]) -> #machine_state{}.
load_program(Machine, BaseAddr, Program) when is_list(Program) ->
    load_program(Machine, maps:from_list(lists:enumerate(BaseAddr, Program))).

-spec set_pc(#machine_state{}, non_neg_integer()) -> #machine_state{}.
set_pc(#machine_state{cpu = Cpu} = Machine, Addr) ->
    Machine#machine_state{cpu = Cpu#cpu_state{pc = Addr}}.

%% @doc Update the keyboard matrix state.
-spec set_keyboard(#machine_state{}, tuple()) -> #machine_state{}.
set_keyboard(Machine, Keyboard) ->
    Machine#machine_state{keyboard = Keyboard}.

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

%% @doc Load a 48K SNA snapshot.
-spec load_sna(#machine_state{}, binary()) -> #machine_state{}.
load_sna(Machine, Data) ->
    H = ezx_sna:parse(Data),
    MemModule = Machine#machine_state.memory_module,
    Mem = Machine#machine_state.memory,

    MemList = binary:bin_to_list(H#sna_header.mem),
    {_FinalOffset, Mem1} = lists:foldl(
        fun(Byte, {Offset, MemAcc}) ->
            Addr = 16384 + Offset,
            {Offset + 1, MemModule:write_byte(MemAcc, Addr, Byte)}
        end, {0, Mem}, MemList),

    SP = H#sna_header.sp,
    PCL = MemModule:read_byte(Mem1, SP band 16#FFFF),
    PCH = MemModule:read_byte(Mem1, (SP + 1) band 16#FFFF),
    PC = (PCH bsl 8) bor PCL,
    AF = H#sna_header.af,
    BC = H#sna_header.bc,
    DE = H#sna_header.de,
    HL = H#sna_header.hl,
    IX = H#sna_header.ix,
    IY = H#sna_header.iy,
    AFp = H#sna_header.af_prime,
    BCp = H#sna_header.bc_prime,
    DEp = H#sna_header.de_prime,
    HLp = H#sna_header.hl_prime,
    Cpu = Machine#machine_state.cpu,
    Cpu1 = Cpu#cpu_state{
        i = H#sna_header.i, r = H#sna_header.r,
        a = AF bsr 8, f = AF band 16#FF,
        b = BC bsr 8, c = BC band 16#FF,
        d = DE bsr 8, e = DE band 16#FF,
        h = HL bsr 8, l = HL band 16#FF,
        sp = SP, pc = PC,
        ixh = IX bsr 8, ixl = IX band 16#FF,
        iyh = IY bsr 8, iyl = IY band 16#FF,
        iff1 = H#sna_header.iff2, iff2 = H#sna_header.iff2,
        a_alt = AFp bsr 8, f_alt = AFp band 16#FF,
        b_alt = BCp bsr 8, c_alt = BCp band 16#FF,
        d_alt = DEp bsr 8, e_alt = DEp band 16#FF,
        h_alt = HLp bsr 8, l_alt = HLp band 16#FF
    },
    Machine#machine_state{
        memory = Mem1,
        cpu = Cpu1,
        border_color = H#sna_header.border
    }.

%% @doc Reset machine to a fresh boot state (ROM loaded, memory zeroed).
-spec reset(#machine_state{}) -> #machine_state{}.
reset(_Machine) ->
    init().

%% @doc Load a TAP file using tape traps.
-spec load_tap(#machine_state{}, binary()) -> #machine_state{}.
load_tap(Machine, Data) ->
    Blocks = ezx_tap:parse_blocks(Data),
    io:format("TAP: parsed ~p blocks~n", [length(Blocks)]),
    Q = make_load_queue(),
    Machine#machine_state{
        tape_blocks = Blocks,
        keyboard_queue = Q
    }.

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
        {50, release},
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
    %% Build ext_context with current frame position so port callbacks can timestamp events.
    ExtContext0 = #ext_context{
        memory = Memory0,
        t_states = MachineTStates,
        % frame_counter = MachineTStates div ?TSTATES_PER_FRAME,
        border_changes = [],
        keyboard = Machine#machine_state.keyboard,
        beeper = Beeper0
    },
    Cpu1 = z80_cpu:step(Cpu0#cpu_state{ext_context = ExtContext0, t_states = 0}),
    Ticks = Cpu1#cpu_state.t_states,
    NewMachineTStates = MachineTStates + Ticks,
    Memory1 = Cpu1#cpu_state.ext_context#ext_context.memory,
    %% Propagate border_changes accumulated during this step.
    StepChanges = Cpu1#cpu_state.ext_context#ext_context.border_changes,
    MergedChanges = merge_border_changes(Machine#machine_state.border_changes, StepChanges),
    NewBorder = case StepChanges of
        [{_, Color} | _] -> Color;
        [] -> Machine#machine_state.border_color
    end,
    Beeper1 = Cpu1#cpu_state.ext_context#ext_context.beeper,
    Machine#machine_state{
        cpu = Cpu1#cpu_state{t_states = NewMachineTStates},
        memory = Memory1,
        t_states = NewMachineTStates,
        border_color = NewBorder,
        border_changes = MergedChanges,
        beeper = Beeper1
    }.

%% @doc Execute one complete frame (69888 T-states).
%% Two-phase execution:
%%   Phase 1: 0..31 T-states — normal execution (no interrupt)
%%   Phase 2: 32..69887 T-states — interrupt raised at boundary, then normal execution
%% Frame boundary is ignored mid-instruction (variant A).
-spec run_frame(#machine_state{}) -> #machine_state{}.
run_frame(Machine) ->
    %% Process auto-typing keyboard queue (overrides user keyboard while active).
    MachineQ = process_keyboard_queue(Machine),
    run_frame_1(MachineQ).

run_frame_1(#machine_state{t_states = StartT} = Machine) ->
    %% Clear border_changes at the start of a new frame so they are
    %% available after run_frame returns (for the renderer).
    Machine0 = Machine#machine_state{border_changes = []},

    %% Phase 1: run to interrupt point (T = StartT + 32).
    Phase1End = StartT + ?INT_TSTATE,
    Machine1 = run_until_tstates(Machine0, Phase1End),

    %% Raise INT at the boundary.
    Cpu1 = Machine1#machine_state.cpu,
    Cpu2 = z80_cpu:request_interrupt(Cpu1, int),
    Machine2 = Machine1#machine_state{cpu = Cpu2},

    %% Phase 2: run to end of frame (T = StartT + 69888).
    Phase2End = StartT + ?TSTATES_PER_FRAME,
    Machine3 = run_until_tstates(Machine2, Phase2End),

    %% Reset T-states to 0 (start of next frame).
    %% border_changes are preserved for the renderer.
    %% Flush beeper to generate PCM audio for this frame.
    BeeperModule = Machine3#machine_state.beeper_module,
    Beeper0 = Machine3#machine_state.beeper,
    {PCM, Beeper1} = BeeperModule:flush_frame(Beeper0),
    Machine3#machine_state{
        t_states = 0,
        beeper = Beeper1,
        beeper_pcm = PCM
    }.

%% @doc Render the current frame to a flat RGB binary (352×288×3 bytes).
%% Extracts screen memory via bulk read_block and passes to a video module.
-spec render_frame(#machine_state{}, non_neg_integer()) -> binary().
render_frame(Machine, FrameCounter) ->
    MemModule = Machine#machine_state.memory_module,
    VideoModule = Machine#machine_state.video_module,
    Changes = lists:reverse(Machine#machine_state.border_changes),
    CB = Machine#machine_state.border_color,
    Mem = Machine#machine_state.memory,
    Videobuffer = MemModule:read_block(Mem, 16384, 6144 + 768),
    VideoModule:render_frame(Videobuffer, FrameCounter, Changes, CB).

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

%% Merge border changes from a step into the accumulated list.
%% Both lists are newest-first (prepended). We append step changes to the front.
merge_border_changes(Existing, []) ->
    Existing;
merge_border_changes(Existing, StepChanges) ->
    %% StepChanges are in reverse order (newest first within the step).
    %% We want to prepend them so the combined list remains newest-first.
    StepChanges ++ Existing.
