-module(ezx_memory_48_array4).

%% @doc ZX Spectrum 48K memory backend using an Erlang array (4 bytes per element).
%%
%% 16384-element array. Each element packs four bytes into a 32-bit integer.
%% `read_block/3' reads dwords with 32-bit little-endian extraction for
%% ~4x fewer `array:get' calls than array1. Best total (CPU+video) performance.

-export([new/1, read_byte/2, read_block/3, read_video_block/1, write_byte/3]).

-type state() :: array:array(non_neg_integer()).
-export_type([state/0]).

-define(VIDEO_SIZE, (6144 + 768)).

%% @doc Create a new 64KB memory state from a ROM binary.
-spec new(binary()) -> state().
new(Rom) when is_binary(Rom), byte_size(Rom) =< 65536 ->
    Rom64 = case byte_size(Rom) of
        65536 -> Rom;
        N when N < 65536 -> <<Rom/binary, 0:(65536 - N)/unit:8>>
    end,
    Arr = array:new(16384, [{default, 0}]),
    pack(Rom64, 0, Arr).

pack(<<>>, _I, Arr) -> Arr;
pack(<<A:8, B:8, C:8, D:8, Rest/binary>>, I, Arr) ->
    pack(Rest, I + 1, array:set(I, (D bsl 24) bor (C bsl 16) bor (B bsl 8) bor A, Arr));
pack(<<A:8, B:8, C:8>>, I, Arr) ->
    array:set(I, (C bsl 16) bor (B bsl 8) bor A, Arr);
pack(<<A:8, B:8>>, I, Arr) ->
    array:set(I, (B bsl 8) bor A, Arr);
pack(<<A:8>>, I, Arr) ->
    array:set(I, A, Arr).

%% @doc Read a single byte at `Addr' (0..65535).
-spec read_byte(state(), non_neg_integer()) -> byte().
read_byte(Arr, Addr) ->
    Value = array:get(Addr bsr 2, Arr),
    (Value bsr ((Addr band 3) * 8)) band 16#FF.

%% @doc Read a contiguous block of `Size' bytes starting at `Addr'.
%% Wraps around at the 64KB boundary.
-spec read_block(state(), non_neg_integer(), non_neg_integer()) -> binary().
read_block(Arr, Addr, Size) ->
    Index = Addr band 16#FFFF,
    First = min(Size, 16#10000 - Index),
    Second = Size - First,
    Part1 = read_aligned(Arr, Index, First),
    case Second of
        0 -> Part1;
        _ ->
            Part2 = read_aligned(Arr, 0, Second),
            <<Part1/binary, Part2/binary>>
    end.

read_aligned(_Arr, _Offset, 0) -> <<>>;
read_aligned(Arr, Offset, Remaining) ->
    Pad = Offset band 3,
    case Pad of
        0 -> read_dwords(Arr, Offset, Remaining, []);
        _ ->
            %% Handle leading unaligned bytes.
            Value = array:get(Offset bsr 2, Arr),
            Lead = min(Pad, Remaining),
            LeadBytes = extract_lead(Value, Pad, Lead),
            read_dwords(Arr, Offset + Lead, Remaining - Lead, [LeadBytes])
    end.

extract_lead(Value, 0, 1) -> <<(Value band 16#FF):8>>;
extract_lead(Value, 0, 2) -> <<(Value band 16#FF):8, ((Value bsr 8) band 16#FF):8>>;
extract_lead(Value, 0, 3) -> <<(Value band 16#FF):8, ((Value bsr 8) band 16#FF):8, ((Value bsr 16) band 16#FF):8>>;
extract_lead(Value, 1, 1) -> <<((Value bsr 8) band 16#FF):8>>;
extract_lead(Value, 1, 2) -> <<((Value bsr 8) band 16#FF):8, ((Value bsr 16) band 16#FF):8>>;
extract_lead(Value, 2, 1) -> <<((Value bsr 16) band 16#FF):8>>.

read_dwords(_Arr, _Offset, 0, Acc) -> iolist_to_binary(lists:reverse(Acc));
read_dwords(Arr, Offset, Remaining, Acc) when Remaining >= 4 ->
    Value = array:get(Offset bsr 2, Arr),
    Lo = Value band 16#FFFF,
    Hi = Value bsr 16,
    read_dwords(Arr, Offset + 4, Remaining - 4,
                [<<Lo:16/little, Hi:16/little>> | Acc]);
read_dwords(Arr, Offset, Remaining, Acc) ->
    %% 1-3 remaining bytes.
    Value = array:get(Offset bsr 2, Arr),
    Bytes = <<(Value band 16#FF):8, ((Value bsr 8) band 16#FF):8, ((Value bsr 16) band 16#FF):8>>,
    <<Tail:Remaining/binary, _/binary>> = Bytes,
    iolist_to_binary(lists:reverse([Tail | Acc])).

%% @doc Read the ULA display buffer (first ?VIDEO_SIZE bytes at 0x4000).
%% The size is fixed, so no size argument is needed.
-spec read_video_block(state()) -> binary().
read_video_block(State) -> read_block(State, 16#4000, ?VIDEO_SIZE).

%% @doc Write `Byte' to `Addr'. ROM area writes are ignored.
-spec write_byte(state(), non_neg_integer(), byte()) -> state().
write_byte(Arr, Addr, Byte) ->
    case Addr < 16#4000 of
        true -> Arr;
        false ->
            Index = Addr bsr 2,
            Shift = (Addr band 3) * 8,
            Old = array:get(Index, Arr),
            Mask = 16#FF bsl Shift,
            New = (Old band (bnot Mask)) bor ((Byte band 16#FF) bsl Shift),
            array:set(Index, New, Arr)
    end.
