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
                    ExtContext#ext_context{
                        border_changes = [{TState, BorderColor} | Changes]
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
        mem_write_fun = MemWriteFun
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
load_sna(Machine, Data) when is_binary(Data) ->
    case byte_size(Data) of
        Sz when Sz < 27 + 49152 ->
            error(bad_sna_header);
        _ ->
            load_sna_do(Machine, Data)
    end.

load_sna_do(Machine, Data) ->
    <<I:8,
      HLp:16/little, DEp:16/little, BCp:16/little, AFp:16/little,
      HL:16/little, DE:16/little, BC:16/little, IY:16/little, IX:16/little,
      IFF2:8, R:8,
      AF:16/little, SP:16/little,
      _IM:8, Border:8,
      Mem:49152/bytes>> = Data,
    MemWriteFun = Machine#machine_state.mem_write_fun,
    ExtContext0 = #ext_context{memory = Machine#machine_state.memory},
    MemList = binary:bin_to_list(Mem),
    {_FinalOffset, ExtContext1} = lists:foldl(
        fun(Byte, {Offset, Ctx}) ->
            Addr = 16384 + Offset,
            {Offset + 1, MemWriteFun(Ctx, Addr, Byte)}
        end, {0, ExtContext0}, MemList),
    MemReadFun = Machine#machine_state.mem_read_fun,
    ReadCtx0 = #ext_context{memory = ExtContext1#ext_context.memory},
    {PCL, ReadCtx1} = MemReadFun(ReadCtx0, SP band 16#FFFF),
    {PCH, _ReadCtx2} = MemReadFun(ReadCtx1, (SP + 1) band 16#FFFF),
    PC = (PCH bsl 8) bor PCL,
    Cpu = Machine#machine_state.cpu,
    Cpu1 = Cpu#cpu_state{
        i = I, r = R,
        a = AF bsr 8, f = AF band 16#FF,
        b = BC bsr 8, c = BC band 16#FF,
        d = DE bsr 8, e = DE band 16#FF,
        h = HL bsr 8, l = HL band 16#FF,
        sp = SP, pc = PC,
        ixh = IX bsr 8, ixl = IX band 16#FF,
        iyh = IY bsr 8, iyl = IY band 16#FF,
        iff1 = IFF2, iff2 = IFF2,
        a_alt = AFp bsr 8, f_alt = AFp band 16#FF,
        b_alt = BCp bsr 8, c_alt = BCp band 16#FF,
        d_alt = DEp bsr 8, e_alt = DEp band 16#FF,
        h_alt = HLp bsr 8, l_alt = HLp band 16#FF
    },
    Machine#machine_state{
        memory = ExtContext1#ext_context.memory,
        cpu = Cpu1,
        border_color = Border
    }.

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
step(#machine_state{t_states = MachineTStates} = Machine) ->
    Cpu0 = Machine#machine_state.cpu,
    Memory0 = Machine#machine_state.memory,
    %% Build ext_context with current frame position so port callbacks can timestamp events.
    ExtContext0 = #ext_context{
        memory = Memory0,
        t_states = MachineTStates,
        frame_counter = MachineTStates div ?TSTATES_PER_FRAME,
        border_changes = [],
        keyboard = Machine#machine_state.keyboard
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
    Machine#machine_state{
        cpu = Cpu1#cpu_state{t_states = NewMachineTStates},
        memory = Memory1,
        t_states = NewMachineTStates,
        border_color = NewBorder,
        border_changes = MergedChanges
    }.

%% @doc Execute one complete frame (69888 T-states).
%% Two-phase execution:
%%   Phase 1: 0..31 T-states — normal execution (no interrupt)
%%   Phase 2: 32..69887 T-states — interrupt raised at boundary, then normal execution
%% Frame boundary is ignored mid-instruction (variant A).
-spec run_frame(#machine_state{}) -> #machine_state{}.
run_frame(#machine_state{t_states = StartT} = Machine) ->
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
    Machine3#machine_state{
        t_states = 0
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
