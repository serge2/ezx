-module(ezx_emulator_128).

-export([
    init/6,
    step/1,
    run_frame/1,
    render_frame/1,
    render_beeper/1,
    load_sna/2,
    load_z80/2,
    load_tap/2,
    press_key/2,
    release_key/2,
    run_until_tstates/2,
    read_byte/2,
    write_byte/3,
    read_word/2,
    write_word/3
]).

-include("z80_records.hrl").
-include("ezx_emulator.hrl").
-include("lib/z80.hrl").

-define(TSTATES_PER_FRAME, 69888).
-define(INT_TSTATE, 32).

%% @doc Create a 128K machine state with 0x7FFD paging support.
-spec init(module(), module(), module(), module(), module(), binary()) -> #machine_state{}.
init(CPUModule, MemModule, VideoModule, KeyboardModule, BeeperModule, Rom) ->
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
                            {16#FF, ExtContext}
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
                            ExtContext
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
        cpu = Cpu0,
        memory = MemModule:new(Rom),
        beeper = BeeperModule:init(),
        keyboard = KeyboardModule:default()
    }.

-spec load_z80(#machine_state{}, binary()) -> {ok, #machine_state{}} | {error, {atom(), binary()}}.
load_z80(Machine, Data) ->
    try ezx_z80:parse(Data) of
        H ->
            Mem = Machine#machine_state.memory,
            MemModule = ezx_memory_128,

            Mem1 = write_128k_pages(Mem, H),
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

%% --- delegation wrappers ---

step(Machine) -> ezx_emulator:step(Machine).
run_frame(Machine) -> ezx_emulator:run_frame(Machine).
render_frame(Machine) -> ezx_emulator:render_frame(Machine).
render_beeper(Machine) -> ezx_emulator:render_beeper(Machine).
load_sna(Machine, Data) -> ezx_emulator:load_sna(Machine, Data).
load_tap(Machine, Data) -> ezx_emulator:load_tap(Machine, Data).
press_key(Machine, Key) -> ezx_emulator:press_key(Machine, Key).
release_key(Machine, Key) -> ezx_emulator:release_key(Machine, Key).
run_until_tstates(Machine, Target) -> ezx_emulator:run_until_tstates(Machine, Target).
read_byte(Machine, Addr) -> ezx_emulator:read_byte(Machine, Addr).
write_byte(Machine, Addr, Byte) -> ezx_emulator:write_byte(Machine, Addr, Byte).
read_word(Machine, Addr) -> ezx_emulator:read_word(Machine, Addr).
write_word(Machine, Addr, Word) -> ezx_emulator:write_word(Machine, Addr, Word).

%% --- internal ---

write_128k_pages(Mem, H) ->
    Pages = H#z80_header.pages,
    maps:fold(fun
        (Page, Data, Acc) when Page >= 3, Page =< 10 ->
            Bank = Page - 3,
            ezx_memory_128:write_bank_block(Acc, Bank, Data);
        (_Page, _Data, Acc) ->
            Acc
    end, Mem, Pages).
