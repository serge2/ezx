-module(ezx_emulator_128).

-export([
    init/7,
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
    run_until_tstates/2
]).

-include("z80_records.hrl").
-include("ezx_emulator.hrl").
-include("lib/z80.hrl").
-include("lib/sna.hrl").
-include("input/ezx_keyboard.hrl").

-define(TSTATES_PER_FRAME, 69888).
-define(INT_TSTATE, 32).

%% @doc Create a 128K machine state with 0x7FFD paging support.
-spec init(module(), module(), module(), module(), module(), module(), {binary(), binary()}) -> #machine_state{}.
init(CPUModule, MemModule, VideoModule, KeyboardModule, BeeperModule, AyModule, {Rom0, Rom1}) ->
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
                    case (Port band 16#8002) =:= 0 of
                        true ->
                            Memory = ExtContext#ext_context.memory,
                            {MemModule:get_p7ffd(Memory), ExtContext};
                        false ->
                            AY = ExtContext#ext_context.ay,
                            {AyModule:read(AY), ExtContext}
                    end
            end
        end,
    PortWriteFun =
        fun(ExtContext, TState, Port, Byte) ->
            case Port band 16#FF of
                16#FE ->
                    BorderColor = Byte band 16#07,
                    Changes = ExtContext#ext_context.border_changes,
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
                    case (Port band 16#8002) =:= 0 of
                        true ->
                            Memory = ExtContext#ext_context.memory,
                            NewMem = MemModule:write_port_7ffd(Memory, Byte),
                            ExtContext#ext_context{memory = NewMem};
                        false ->
                            case (Port band 16#4000) =:= 0 of
                                true ->
                                    AY = ExtContext#ext_context.ay,
                                    ExtContext#ext_context{ay = AyModule:write(AY, Byte, TState)};
                                false ->
                                    AY = ExtContext#ext_context.ay,
                                    ExtContext#ext_context{ay = AyModule:latch(AY, Byte)}
                            end
                    end
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
        ay_module = AyModule,
        cpu = Cpu0,
        memory = MemModule:new(Rom0, Rom1),
        beeper = BeeperModule:init(),
        keyboard = KeyboardModule:default(),
        ay = AyModule:new()
    }.

%% @doc Load a Z80 v1/v2/v3 snapshot into 128K memory.
-spec load_z80(#machine_state{}, binary()) -> {ok, #machine_state{}} | {error, {atom(), binary()}}.
load_z80(Machine, Data) ->
    try ezx_z80:parse(Data) of
        #z80_header{is_128k = false} ->
            Mem = Machine#machine_state.memory,
            MemModule = Machine#machine_state.memory_module,

            Mem0 = MemModule:write_port_7ffd(Mem, 16#10),
            ezx_emulator:load_z80(Machine#machine_state{memory = Mem0}, Data);
        #z80_header{is_128k = true} = H ->
            Mem = Machine#machine_state.memory,
            MemModule = Machine#machine_state.memory_module,

            Mem1 = write_128k_pages(MemModule, Mem, H),
            Mem2 = MemModule:write_port_7ffd(Mem1, H#z80_header.p7ffd),

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
                memory = Mem2,
                cpu = Cpu1,
                border_color = H#z80_header.border,
                t_states = 0,
                border_changes = [],
                flash_counter = 0,
                beeper_pcm = <<>>,
                screen = <<>>
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

%% @doc Load a TAP file. In 128K mode the machine boots into the menu,
%% so just press Enter (no need to type LOAD "").
-spec load_tap(#machine_state{}, binary()) -> {ok, #machine_state{}} | {error, {atom(), binary()}}.
load_tap(Machine, Data) ->
    try ezx_tap:parse_blocks(Data) of
        Blocks ->
            io:format("TAP: parsed ~p blocks~n", [length(Blocks)]),
            Q = [
                {80, release},
                {3, {set, [?KEY_ENTER]}},
                {5, release}
            ],
            {ok, Machine#machine_state{
                tape_blocks = Blocks,
                keyboard_queue = Q
            }}
    catch
        C:E:_S ->
            {error, {bad_tap_data, iolist_to_binary(io_lib:format("~p:~p", [C, E]))}}
    end.

%% @doc Load a .sna snapshot (48K or 128K extended).
-spec load_sna(#machine_state{}, binary()) -> {ok, #machine_state{}} | {error, {atom(), binary()}}.
load_sna(Machine, Data) ->
    try ezx_sna:parse(Data) of
        #sna_header{is_128k = false} ->
            MemMod = Machine#machine_state.memory_module,
            Mem = Machine#machine_state.memory,
            Mem0 = MemMod:write_port_7ffd(Mem, 16#10),
            ezx_emulator:load_sna(Machine#machine_state{memory = Mem0}, Data);
        #sna_header{is_128k = true} = H ->
            P7FFD = H#sna_header.p7ffd,
            MemModule = Machine#machine_state.memory_module,
            Mem = Machine#machine_state.memory,

            Mem0 = MemModule:write_port_7ffd(Mem, P7FFD),

            MemList = binary:bin_to_list(H#sna_header.mem),
            {_, Mem1} = lists:foldl(
                fun(Byte, {Offset, MemAcc}) ->
                    Addr = 16384 + Offset,
                    {Offset + 1, MemModule:write_byte(MemAcc, Addr, Byte)}
                end, {0, Mem0}, MemList),

            Mem2 = case H#sna_header.raw_extra of
                undefined -> Mem1;
                Extra -> load_extra_pages(MemModule, Mem1, P7FFD, Extra)
            end,

            SP = H#sna_header.sp,
            {PC, SP_Final} = case H#sna_header.pc of
                undefined ->
                    PCL = MemModule:read_byte(Mem2, SP band 16#FFFF),
                    PCH = MemModule:read_byte(Mem2, (SP + 1) band 16#FFFF),
                    {(PCH bsl 8) bor PCL, (SP + 2) band 16#FFFF};
                P -> {P, SP}
            end,
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
                sp = SP_Final, pc = PC,
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
                memory = Mem2,
                cpu = Cpu1,
                border_color = H#sna_header.border,
                t_states = 0,
                border_changes = [],
                flash_counter = 0,
                beeper_pcm = <<>>,
                screen = <<>>
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

%% --- delegation wrappers ---

%% @doc Execute one CPU instruction.
-spec step(#machine_state{}) -> #machine_state{}.
step(Machine) -> ezx_emulator:step(Machine).

%% @doc Run one full frame (~69888 T-states).
-spec run_frame(#machine_state{}) -> #machine_state{}.
run_frame(Machine) -> ezx_emulator:run_frame(Machine).

%% @doc Render the current frame into a screen bitmap.
-spec render_frame(#machine_state{}) -> #machine_state{}.
render_frame(Machine) -> ezx_emulator:render_frame(Machine).

%% @doc Render accumulated beeper PCM.
-spec render_beeper(#machine_state{}) -> {binary(), #machine_state{}}.
render_beeper(Machine) -> ezx_emulator:render_beeper(Machine).

%% @doc Render 3 separate AY channel PCMs.
-spec render_ay_channels(#machine_state{}) -> {binary(), binary(), binary(), #machine_state{}}.
render_ay_channels(Machine) -> ezx_emulator:render_ay_channels(Machine).

%% @doc Press a keyboard key.
-spec press_key(#machine_state{}, non_neg_integer()) -> #machine_state{}.
press_key(Machine, Key) -> ezx_emulator:press_key(Machine, Key).

%% @doc Release a keyboard key.
-spec release_key(#machine_state{}, non_neg_integer()) -> #machine_state{}.
release_key(Machine, Key) -> ezx_emulator:release_key(Machine, Key).

%% @doc Execute instructions up to a target T-state count.
-spec run_until_tstates(#machine_state{}, non_neg_integer()) -> #machine_state{}.
run_until_tstates(Machine, Target) -> ezx_emulator:run_until_tstates(Machine, Target).

%% --- internal ---

%% @doc Write extra 16KB pages into banks not covered by the 48KB dump.
-spec load_extra_pages(module(), any(), byte(), binary()) -> any().
load_extra_pages(MemModule, Mem, P7FFD, Extra) ->
    ScreenBank = case (P7FFD bsr 3) band 1 of 0 -> 5; 1 -> 7 end,
    Slot3Bank = P7FFD band 16#07,
    Covered = sets:from_list([2, ScreenBank, Slot3Bank]),
    Banks = [B || B <- lists:seq(0, 7), not sets:is_element(B, Covered)],
    load_pages(MemModule, Mem, Banks, Extra).

load_pages(_MemModule, Mem, [], _Extra) -> Mem;
load_pages(MemModule, Mem, [Bank | Banks], Extra) ->
    case Extra of
        <<PageData:16384/binary, Rest/binary>> ->
            Mem1 = MemModule:write_bank_block(Mem, Bank, PageData),
            load_pages(MemModule, Mem1, Banks, Rest);
        _ ->
            Mem
    end.

%% @doc Write Z80 memory pages (3-10) into 128K RAM banks (0-7).
-spec write_128k_pages(module(), any(), #z80_header{}) -> any().
write_128k_pages(MemModule, Mem, H) ->
    Pages = H#z80_header.pages,
    maps:fold(fun
        (Page, Data, Acc) when Page >= 3, Page =< 10 ->
            Bank = Page - 3,
            MemModule:write_bank_block(Acc, Bank, Data);
        (_Page, _Data, Acc) ->
            Acc
    end, Mem, Pages).
