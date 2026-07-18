-module(test_helpers).

-include("z80_records.hrl").

-export([
    init_cpu/0,
    write_mem/3,
    load_program/3
]).

init_cpu() ->
    MemReadFun = fun(ExtContext, Addr) ->
        Byte = z80_cpu_mem:read_byte(ExtContext, Addr band 16#ffff),
        {Byte, ExtContext}
    end,
    MemWriteFun = fun(ExtContext, Addr, Byte) ->
        z80_cpu_mem:write_byte(ExtContext, Addr band 16#ffff, Byte band 16#ff)
    end,
    Cpu0 = z80_cpu:init_state(MemReadFun, MemWriteFun),
    Cpu0#cpu_state{ext_context = z80_cpu_mem:new()}.

write_mem(Cpu, Addr, Byte) ->
    Mem = Cpu#cpu_state.ext_context,
    Cpu#cpu_state{ext_context = z80_cpu_mem:write_byte(Mem, Addr band 16#ffff, Byte band 16#ff)}.

load_program(Cpu, StartAddr, Bytes) ->
    lists:foldl(fun({Offset, Byte}, Acc) -> write_mem(Acc, StartAddr + Offset, Byte) end,
                Cpu, lists:zip(lists:seq(0, length(Bytes) - 1), Bytes)).
