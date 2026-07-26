-module(ezx_memory_48_array2).

%% @doc ZX Spectrum 48K memory backend using an Erlang array (2 bytes per element).
%%
%% 32768-element array. Each element packs two adjacent bytes into a
%% 16-bit integer. `read_block/3' reads packed pairs for ~2x speedup
%% over byte-at-a-time. Best CPU performance of all backends.

-export([new/1, read_byte/2, read_block/3, write_byte/3]).

-type state() :: array:array(non_neg_integer()).
-export_type([state/0]).

%% @doc Create a new 64KB memory state from a ROM binary.
-spec new(binary()) -> state().
new(Rom) when is_binary(Rom), byte_size(Rom) =< 65536 ->
    Rom64 = case byte_size(Rom) of
        65536 -> Rom;
        N when N < 65536 -> <<Rom/binary, 0:(65536 - N)/unit:8>>
    end,
    %% Pack pairs of bytes into 16-bit integers.
    %% array size = 32768 elements, each holding 2 bytes.
    Arr = array:new(32768, [{default, 0}]),
    pack(Rom64, 0, Arr).

pack(<<>>, _I, Arr) -> Arr;
pack(<<Lo:8, Hi:8, Rest/binary>>, I, Arr) ->
    pack(Rest, I + 1, array:set(I, (Hi bsl 8) bor Lo, Arr));
pack(<<Lo:8>>, I, Arr) ->
    array:set(I, Lo, Arr).

%% @doc Read a single byte at `Addr' (0..65535).
-spec read_byte(state(), non_neg_integer()) -> byte().
read_byte(Arr, Addr) ->
    Index = Addr bsr 1,
    Value = array:get(Index, Arr),
    case Addr band 1 of
        0 -> Value band 16#FF;
        1 -> Value bsr 8
    end.

%% @doc Read a contiguous block of `Size' bytes starting at `Addr'.
%% Wraps around at the 64KB boundary.
-spec read_block(state(), non_neg_integer(), non_neg_integer()) -> binary().
read_block(Arr, Addr, Size) ->
    Index = Addr band 16#FFFF,
    First = min(Size, 16#10000 - Index),
    Second = Size - First,
    Part1 = read_pairs(Arr, Index, First),
    case Second of
        0 -> Part1;
        _ ->
            Part2 = read_pairs(Arr, 0, Second),
            <<Part1/binary, Part2/binary>>
    end.

%% Read a block starting at Offset, returning a binary.
%% Optimized: reads 16-bit values for every pair of bytes.
read_pairs(_Arr, _Offset, 0) -> <<>>;
read_pairs(Arr, Offset, Remaining) ->
    case Offset band 1 of
        0 -> read_even(Arr, Offset, Remaining, []);
        1 ->
            %% Odd start: read first byte alone, then continue even-aligned.
            Value = array:get(Offset bsr 1, Arr),
            Byte = Value bsr 8,
            read_even(Arr, Offset + 1, Remaining - 1, [<<Byte:8>>])
    end.

read_even(_Arr, _Offset, 0, Acc) -> iolist_to_binary(lists:reverse(Acc));
read_even(Arr, Offset, 1, Acc) ->
    %% Last byte: odd address.
    Value = array:get(Offset bsr 1, Arr),
    Byte = Value band 16#FF,
    iolist_to_binary(lists:reverse([<<Byte:8>> | Acc]));
read_even(Arr, Offset, Remaining, Acc) ->
    Value = array:get(Offset bsr 1, Arr),
    Lo = Value band 16#FF,
    Hi = Value bsr 8,
    read_even(Arr, Offset + 2, Remaining - 2, [<<Lo:8, Hi:8>> | Acc]).

%% @doc Write `Byte' to `Addr'. ROM area writes are ignored.
-spec write_byte(state(), non_neg_integer(), byte()) -> state().
write_byte(Arr, Addr, Byte) ->
    Index = Addr bsr 1,
    case Addr < 16#4000 of
        true -> Arr;
        false ->
            Old = array:get(Index, Arr),
            New = case Addr band 1 of
                0 -> (Old band 16#FF00) bor (Byte band 16#FF);
                1 -> (Old band 16#00FF) bor ((Byte band 16#FF) bsl 8)
            end,
            array:set(Index, New, Arr)
    end.
