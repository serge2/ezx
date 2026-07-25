-module(ezx_memory_48).

-export([
    new/1,
    read_byte/2,
    read_block/3,
    write_byte/3
]).

-type state() :: #{size => pos_integer(), data => binary()}.

-export_type([state/0]).


new(Rom) when is_binary(Rom), byte_size(Rom) =< 65536 ->
    %% Create a new memory state with 64KB. Pad ROM with zeros if needed.
    #{size => 65536,
      data => <<Rom/binary, 0:(65536-byte_size(Rom))/unit:8>>
    }.

read_byte(State, Addr) ->
    Index = Addr band 16#ffff,
    Data = maps:get(data, State),
    case Data of
        <<_:Index/binary, Byte:8/integer, _/binary>> -> Byte;
        _ -> 0
    end.

read_block(State, Addr, Size) ->
    Index = Addr band 16#ffff,
    Data = maps:get(data, State),
    case Data of
        <<_:Index/binary, Block:Size/binary, _/binary>> -> Block;
        _ -> <<0:Size/unit:8>>
    end.

write_byte(State, Addr, Byte) ->
    Index = Addr band 16#ffff,
    %% ROM area (0x0000-0x3FFF) is write-protected on ZX Spectrum 48K.
    case Index < 16#4000 of
        true  -> State;
        false ->
            <<Prefix:Index/binary, _Old:8/integer, Suffix/binary>> = maps:get(data, State),
            Data1 = <<Prefix/binary, (Byte band 16#ff):8/integer, Suffix/binary>>,
            maps:put(data, Data1, State)
    end.

