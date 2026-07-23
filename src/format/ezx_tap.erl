-module(ezx_tap).

-include("z80_records.hrl").
-include("ezx_emulator.hrl").

-export([load/2, tape_trap/2]).

%% @doc Load a TAP file using tape traps.
%% Parses TAP into {flag, data} block list, resets machine, lets ROM boot,
%% then stores blocks for interception at LD-BYTES (0x0556).
%% A keyboard queue types LOAD "" automatically.
-spec load(#machine_state{}, binary()) -> #machine_state{}.
load(_Machine, Data) when is_binary(Data) ->
    Blocks = parse_blocks(Data),
    io:format("TAP: parsed ~p blocks~n", [length(Blocks)]),
    FreshMachine = ezx_emulator:init(),
    InitMachine = ezx_emulator:run_until_tstates(FreshMachine, 4000000),
    Q = make_load_queue(),
    InitMachine#machine_state{
        tape_blocks = Blocks,
        keyboard_queue = Q,
        beeper = ezx_beeper:init()
    }.

%% @doc Tape trap: intercept LD-BYTES at PC=0x0556.
%% Copies block data to memory at IX, sets registers for success, jumps to RET (0x05E2).
tape_trap(#machine_state{cpu = Cpu, tape_blocks = [{_Flag, Data} | RestBlocks]} = Machine,
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

%% --- Internal ---

parse_blocks(<<>>) -> [];
parse_blocks(<<Len:16/little, Flag:8, PayloadAndChecksum/binary>>) when byte_size(PayloadAndChecksum) >= Len - 1 ->
    PayloadLen = Len - 2,
    <<Payload:PayloadLen/binary, _Checksum:8, Remaining/binary>> = PayloadAndChecksum,
    [{Flag, Payload} | parse_blocks(Remaining)];
parse_blocks(_) -> [].

write_block(Machine, _Addr, []) -> Machine;
write_block(Machine, Addr, [Byte | Rest]) ->
    Machine1 = ezx_emulator:write_byte(Machine, Addr band 16#FFFF, Byte),
    write_block(Machine1, (Addr + 1) band 16#FFFF, Rest).

%% --- Auto-typing keyboard queue for LOAD "" ---

make_load_queue() ->
    D = ?KEYBOARD_DEFAULT,
    J = key_pressed(D, {7, 3}),
    Quote = key_pressed(key_pressed(D, {8, 1}), {6, 0}),
    Enter = key_pressed(D, {7, 0}),
    [
        {repeat, 50, release},
        {repeat, 3, {set, J}},
        {repeat, 10, release},
        {repeat, 3, {set, Quote}},
        {repeat, 5, release},
        {repeat, 3, {set, Quote}},
        {repeat, 5, release},
        {repeat, 3, {set, Enter}},
        {repeat, 5, release}
    ].

key_pressed(KB, {Row, Bit}) ->
    Old = element(Row, KB),
    setelement(Row, KB, Old band (bnot (1 bsl Bit))).
