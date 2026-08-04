-module(ezx_memory_48_array).

%% @doc ZX Spectrum 48K memory backend using an Erlang array (1 byte per element).
%%
%% 65536-element array where each element stores a single byte.
%% `read_byte/2' is a direct `array:get/2' call. Bulk reads iterate
%% element by element, making `read_block/3' slow (~300 us for 6912 bytes).

-export([new/1, read_byte/2, read_block/3, read_video_block/1, write_byte/3]).

-type state() :: array:array(byte()).

-export_type([state/0]).

-define(VIDEO_SIZE, (6144 + 768)).

%% @doc Create a new 64KB memory state from a ROM binary.
-spec new(binary()) -> state().
new(Rom) when is_binary(Rom), byte_size(Rom) =< 65536 ->
    Arr = array:new(65536, [{default, 0}]),
    load_rom(Rom, 0, Arr).

load_rom(<<>>, _I, Arr) -> Arr;
load_rom(<<Byte:8, Rest/binary>>, I, Arr) ->
    load_rom(Rest, I + 1, array:set(I, Byte, Arr)).

%% @doc Read a single byte at `Addr' (0..65535).
-spec read_byte(state(), non_neg_integer()) -> byte().
read_byte(Arr, Addr) ->
    array:get(Addr band 16#FFFF, Arr).

%% @doc Read a contiguous block of `Size' bytes starting at `Addr'.
%% Wraps around at the 64KB boundary.
-spec read_block(state(), non_neg_integer(), non_neg_integer()) -> binary().
read_block(Arr, Addr, Size) ->
    Index = Addr band 16#FFFF,
    First = min(Size, 16#10000 - Index),
    Second = Size - First,
    Part1 = read_seq(Arr, Index, First, <<>>),
    case Second of
        0 -> Part1;
        _ ->
            Part2 = read_seq(Arr, 0, Second, <<>>),
            <<Part1/binary, Part2/binary>>
    end.

read_seq(_Arr, _Offset, 0, Acc) -> Acc;
read_seq(Arr, Offset, Remaining, Acc) ->
    read_seq(Arr, Offset + 1, Remaining - 1,
             <<Acc/binary, (array:get(Offset, Arr)):8>>).

%% @doc Read the ULA display buffer (first ?VIDEO_SIZE bytes at 0x4000).
%% The size is fixed, so no size argument is needed.
-spec read_video_block(state()) -> binary().
read_video_block(State) -> read_block(State, 16#4000, ?VIDEO_SIZE).

%% @doc Write `Byte' to `Addr'. ROM area writes are ignored.
-spec write_byte(state(), non_neg_integer(), byte()) -> state().
write_byte(Arr, Addr, Byte) ->
    Index = Addr band 16#FFFF,
    case Index < 16#4000 of
        true -> Arr;
        false -> array:set(Index, Byte band 16#FF, Arr)
    end.
