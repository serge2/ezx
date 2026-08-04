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
    MemReadFun = fun(ExtContext, _TState, Addr) ->
        z80_cpu_mem:read_byte(ExtContext#ext_context.memory, Addr band 16#ffff)
    end,
    MemWriteFun = fun(ExtContext, _TState, Addr, Byte) ->
        NewMem = z80_cpu_mem:write_byte(ExtContext#ext_context.memory, Addr band 16#ffff, Byte band 16#ff),
        ExtContext#ext_context{memory = NewMem}
    end,
    PortReadFun = fun(ExtContext, _TState, _Port) -> {16#FF, ExtContext} end,
    PortWriteFun = fun(ExtContext, _TState, _Port, _Byte) -> ExtContext end,
    BusReadFun = fun() -> 16#FF end,
    Cpu0 = z80_cpu:init_state(MemReadFun, MemWriteFun, PortReadFun, PortWriteFun, BusReadFun),
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
