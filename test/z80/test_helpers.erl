-module(test_helpers).

-include("z80_records.hrl").
-include("ezx_emulator.hrl").

-export([
    init_cpu/0,
    write_mem/3,
    load_program/3,
    read_mem/2
]).

init_cpu() ->
    Mem = z80_cpu_mem:new(),
    MemReadFun = fun(ExtContext, Addr) ->
        Byte = z80_cpu_mem:read_byte(ExtContext#ext_context.memory, Addr band 16#ffff),
        {Byte, ExtContext}
    end,
    MemWriteFun = fun(ExtContext, Addr, Byte) ->
        NewMem = z80_cpu_mem:write_byte(ExtContext#ext_context.memory, Addr band 16#ffff, Byte band 16#ff),
        ExtContext#ext_context{memory = NewMem}
    end,
    PortReadFun = fun(ExtContext, _Port) -> {16#FF, ExtContext} end,
    PortWriteFun = fun(ExtContext, _Port, _Byte) -> ExtContext end,
    Cpu0 = z80_cpu:init_state(MemReadFun, MemWriteFun, PortReadFun, PortWriteFun),
    Cpu0#cpu_state{
        ext_context = #ext_context{memory = Mem}
    }.

write_mem(Cpu, Addr, Byte) ->
    ExtCtx = Cpu#cpu_state.ext_context,
    OldMem = ExtCtx#ext_context.memory,
    NewMem = z80_cpu_mem:write_byte(OldMem, Addr band 16#ffff, Byte band 16#ff),
    Cpu#cpu_state{ext_context = ExtCtx#ext_context{memory = NewMem}}.

load_program(Cpu, StartAddr, Bytes) ->
    lists:foldl(fun({Offset, Byte}, Acc) -> write_mem(Acc, StartAddr + Offset, Byte) end,
                Cpu, lists:zip(lists:seq(0, length(Bytes) - 1), Bytes)).

read_mem(Cpu, Addr) ->
    ExtCtx = Cpu#cpu_state.ext_context,
    z80_cpu_mem:read_byte(ExtCtx#ext_context.memory, Addr band 16#ffff).
