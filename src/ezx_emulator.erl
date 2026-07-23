-module(ezx_emulator).

-include("z80_records.hrl").
-include("ezx_emulator.hrl").

-export([
    init/0,
    init/2,
    step/1,
    run_frame/1,
    load_program/2,
    load_program/3,
    load_sna/2,
    load_tap/2,
    reset/1,
    set_pc/2,
    set_keyboard/2,
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
    init(ezx_memory_48, Rom).

%% @doc Create a new machine state with initialized CPU and memory components.
-spec init(module(), binary()) -> #machine_state{}.
init(Mem, Rom) ->
    MemReadFun =
        fun(ExtContext, Addr) ->
            Memory = ExtContext#ext_context.memory,
            Byte = Mem:read_byte(Memory, Addr band 16#ffff),
            {Byte, ExtContext}
        end,
    MemWriteFun =
        fun(ExtContext, Addr, Byte) ->
            Memory = ExtContext#ext_context.memory,
            NewMem = Mem:write_byte(Memory, Addr band 16#ffff, Byte band 16#ff),
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
                    Result = decode_keyboard(Keyboard, UpperByte),
                    {Result, ExtContext};
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
                    Beeper1 = ezx_beeper:set_level(Beeper0, BeeperLevel, TState),
                    ExtContext#ext_context{
                        border_changes = [{TState, BorderColor} | Changes],
                        beeper = Beeper1
                    };
                _ ->
                    ExtContext
            end
        end,
    Cpu0 = z80_cpu:init_state(MemReadFun, MemWriteFun, PortReadFun, PortWriteFun),
    #machine_state{
        cpu = Cpu0,
        memory = Mem:new(Rom),
        mem_read_fun = MemReadFun,
        mem_write_fun = MemWriteFun,
        beeper = ezx_beeper:init()
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

%% @doc Load a 48K SNA snapshot.
-spec load_sna(#machine_state{}, binary()) -> #machine_state{}.
load_sna(Machine, Data) ->
    ezx_sna:load(Machine, Data).

%% @doc Reset machine to a fresh boot state (ROM loaded, memory zeroed).
-spec reset(#machine_state{}) -> #machine_state{}.
reset(_Machine) ->
    init().

%% @doc Load a TAP file using tape traps.
-spec load_tap(#machine_state{}, binary()) -> #machine_state{}.
load_tap(Machine, Data) ->
    ezx_tap:load(Machine, Data).

%% @doc Process one step of the keyboard auto-typing queue (called per frame).
%% Queue elements: {repeat, N, Action} where Action is {set, KB} or release.
%% Each frame consumes one count from the current repeat block.
process_keyboard_queue(#machine_state{keyboard_queue = [{repeat, N, Action} | Rest]} = Machine) when N > 1 ->
    KB = apply_kb_action(Machine#machine_state.keyboard, Action),
    Machine#machine_state{keyboard = KB, keyboard_queue = [{repeat, N - 1, Action} | Rest]};
process_keyboard_queue(#machine_state{keyboard_queue = [{repeat, 1, Action} | Rest]} = Machine) ->
    KB = apply_kb_action(Machine#machine_state.keyboard, Action),
    Machine#machine_state{keyboard = KB, keyboard_queue = Rest};
process_keyboard_queue(Machine) ->
    Machine.

apply_kb_action(_KB, release) -> ?KEYBOARD_DEFAULT;
apply_kb_action(_KB, {set, NewKB}) -> NewKB.

-spec read_byte(#machine_state{}, non_neg_integer()) -> {byte(), #machine_state{}}.
read_byte(#machine_state{memory = Mem, mem_read_fun = MemReadFun} = Machine, Addr) ->
    ExtContext = #ext_context{memory = Mem},
    {Byte, ExtContext2} = MemReadFun(ExtContext, Addr),
    {Byte, Machine#machine_state{memory = ExtContext2#ext_context.memory}}.

%% @doc Write a byte into the machine memory.
-spec write_byte(#machine_state{}, non_neg_integer(), byte()) -> #machine_state{}.
write_byte(#machine_state{memory = Mem, mem_write_fun = MemWriteFun} = Machine, Addr, Byte) ->
    ExtContext = #ext_context{memory = Mem},
    ExtContext2 = MemWriteFun(ExtContext, Addr, Byte),
    Machine#machine_state{memory = ExtContext2#ext_context.memory}.

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
        16#0556 -> ezx_tap:tape_trap(Machine, MachineTStates);
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
        frame_counter = MachineTStates div ?TSTATES_PER_FRAME,
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
    Beeper0 = Machine3#machine_state.beeper,
    {PCM, Beeper1} = ezx_beeper:flush_frame(Beeper0),
    Machine3#machine_state{
        t_states = 0,
        beeper = Beeper1,
        beeper_pcm = PCM
    }.

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

%% Decode ZX Spectrum keyboard state from the keyboard matrix.
%% Keyboard is a tuple of 8 bytes (half-rows 0-7).
%% UpperByte: each bit selects a half-row (active low, 0 = selected).
%% Multiple selected half-rows are ANDed together (open-collector bus).
%% Bits 5-7 of result are always 1 (floating bus).
-spec decode_keyboard(tuple(), non_neg_integer()) -> non_neg_integer().
decode_keyboard(Keyboard, UpperByte) ->
    decode_keyboard_rows(Keyboard, UpperByte, 16#1F, 0).

decode_keyboard_rows(_Keyboard, _UpperByte, Acc, 8) ->
    Acc bor 16#E0;
decode_keyboard_rows(Keyboard, UpperByte, Acc, N) ->
    case (UpperByte band 1) of
        0 ->
            RowByte = element(N + 1, Keyboard),
            decode_keyboard_rows(Keyboard, UpperByte bsr 1, Acc band RowByte, N + 1);
        1 ->
            decode_keyboard_rows(Keyboard, UpperByte bsr 1, Acc, N + 1)
    end.
