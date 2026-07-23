-module(ezx_sna).

-include("z80_records.hrl").
-include("ezx_emulator.hrl").

-export([load/2]).

%% @doc Load a 48K SNA snapshot into a machine state.
-spec load(#machine_state{}, binary()) -> #machine_state{}.
load(Machine, Data) when is_binary(Data) ->
    case byte_size(Data) of
        Sz when Sz < 27 + 49152 ->
            error(bad_sna_header);
        _ ->
            load_do(Machine, Data)
    end.

load_do(Machine, Data) ->
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
