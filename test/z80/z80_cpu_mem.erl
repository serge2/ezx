-module(z80_cpu_mem).

-export([
    new/0,
    read_byte/2,
    write_byte/3
]).

new() ->
    #{size => 65536,
      data => <<0:65536/unit:8>>
    }.


read_byte(State, Addr) ->
    %% Read a byte from memory at the given address.
    Index = Addr band 16#ffff,
    Data = maps:get(data, State),
    case Data of
        <<_:Index/binary, Byte:8/integer, _/binary>> -> Byte;
        _ -> 0
    end.

write_byte(State, Addr, Byte) ->
    %% Write a byte to memory at the given address.
    Index = Addr band 16#ffff,
    Size = maps:get(size, State),
    if
        Index < Size ->
            <<Prefix:Index/binary, _Old:8/integer, Suffix/binary>> = maps:get(data, State),
            Data1 = <<Prefix/binary, (Byte band 16#ff):8/integer, Suffix/binary>>,
            maps:put(data, Data1, State);
        true ->
            State
    end.

