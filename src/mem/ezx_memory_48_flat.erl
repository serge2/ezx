-module(ezx_memory_48_flat).

%% @doc ZX Spectrum 48K memory backend (flat binary, alternate implementation).
%%
%% Similar to `ezx_memory_48' but uses a stricter binary pattern-match
%% approach for `read_byte'. Functionally identical, kept as a reference
%% implementation for benchmarking.

-export([new/1, read_byte/2, read_block/3, write_byte/3]).

-type state() :: #{size => pos_integer(), data => binary()}.
-export_type([state/0]).

%% @doc Create a new 64KB memory state from a ROM binary.
-spec new(binary()) -> state().
new(Rom) when is_binary(Rom) ->
    #{size => 65536,
      data => <<Rom/binary, 0:(65536-byte_size(Rom))/unit:8>>
    }.

%% @doc Read a single byte at `Addr' (0..65535).
-spec read_byte(state(), non_neg_integer()) -> byte().
read_byte(State, Addr) ->
    Index = Addr band 16#ffff,
    Data = maps:get(data, State),
    <<_:Index/binary, Byte:8/integer, _/binary>> = Data,
    Byte.

%% @doc Read a contiguous block of `Size' bytes starting at `Addr'.
%% Wraps around at the 64KB boundary.
-spec read_block(state(), non_neg_integer(), non_neg_integer()) -> binary().
read_block(State, Addr, Size) ->
    Index = Addr band 16#ffff,
    Data = maps:get(data, State),
    First = min(Size, 16#10000 - Index),
    Second = Size - First,
    <<_:Index/binary, Part1:First/binary, _/binary>> = Data,
    case Second of
        0 -> Part1;
        _ ->
            <<Part2:Second/binary, _/binary>> = Data,
            <<Part1/binary, Part2/binary>>
    end.

%% @doc Write `Byte' to `Addr'. ROM area writes are ignored.
-spec write_byte(state(), non_neg_integer(), byte()) -> state().
write_byte(State, Addr, Byte) ->
    Index = Addr band 16#ffff,
    case Index < 16#4000 of
        true  -> State;
        false ->
            <<Prefix:Index/binary, _Old:8/integer, Suffix/binary>> = maps:get(data, State),
            Data1 = <<Prefix/binary, (Byte band 16#ff):8/integer, Suffix/binary>>,
            maps:put(data, Data1, State)
    end.
