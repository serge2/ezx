-module(ezx_memory_48_array8).

%% @doc ZX Spectrum 48K memory backend using an Erlang array (8 bytes per element).
%%
%% 8192-element array. Each element packs eight bytes into a 64-bit integer.
%% `read_block/3' reads qwords with 64-bit extraction for the fewest
%% `array:get' calls (864 for 6912 bytes). Best bulk read performance
%% (~47 us) but slightly slower single-byte reads due to larger shifts.

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
    Arr = array:new(8192, [{default, 0}]),
    pack(Rom64, 0, Arr).

pack(<<>>, _I, Arr) -> Arr;
pack(<<A:8, B:8, C:8, D:8, E:8, F:8, G:8, H:8, Rest/binary>>, I, Arr) ->
    Val = (H bsl 56) bor (G bsl 48) bor (F bsl 40) bor (E bsl 32)
          bor (D bsl 24) bor (C bsl 16) bor (B bsl 8) bor A,
    pack(Rest, I + 1, array:set(I, Val, Arr));
pack(<<Rest/binary>>, I, Arr) ->
    pack(<<Rest/binary, 0:(8 - byte_size(Rest))/unit:8>>, I, Arr).

%% @doc Read a single byte at `Addr' (0..65535).
-spec read_byte(state(), non_neg_integer()) -> byte().
read_byte(Arr, Addr) ->
    Value = array:get(Addr bsr 3, Arr),
    (Value bsr ((Addr band 7) * 8)) band 16#FF.

%% @doc Read a contiguous block of `Size' bytes starting at `Addr'.
%% Wraps around at the 64KB boundary.
-spec read_block(state(), non_neg_integer(), non_neg_integer()) -> binary().
read_block(Arr, Addr, Size) ->
    Index = Addr band 16#FFFF,
    First = min(Size, 16#10000 - Index),
    Second = Size - First,
    Part1 = extract(Arr, Index, First),
    case Second of
        0 -> Part1;
        _ ->
            Part2 = extract(Arr, 0, Second),
            <<Part1/binary, Part2/binary>>
    end.

extract(_Arr, _Offset, 0) -> <<>>;
extract(Arr, Offset, Size) ->
    Pad = Offset band 7,
    case Pad of
        0 -> extract_qwords(Arr, Offset, Size, []);
        _ ->
            Value = array:get(Offset bsr 3, Arr),
            Lead = min(Pad, Size),
            LeadBytes = extract_lead(Value, Pad, Lead),
            extract_qwords(Arr, Offset + Lead, Size - Lead, [LeadBytes])
    end.

extract_lead(Value, 0, 1) -> <<(Value band 16#FF):8>>;
extract_lead(Value, 0, 2) -> <<(Value band 16#FFFF):16/little>>;
extract_lead(Value, 0, 4) -> <<(Value band 16#FFFFFFFF):32/little>>;
extract_lead(Value, 0, 6) ->
    Lo = Value band 16#FFFFFFFF,
    Hi = (Value bsr 32) band 16#FFFF,
    <<Lo:32/little, Hi:16/little>>;
extract_lead(Value, 1, 1) -> <<((Value bsr 8) band 16#FF):8>>;
extract_lead(Value, 1, 2) -> <<((Value bsr 8) band 16#FFFF):16/little>>;
extract_lead(Value, 1, 4) -> <<((Value bsr 8) band 16#FFFFFFFF):32/little>>;
extract_lead(Value, 2, 1) -> <<((Value bsr 16) band 16#FF):8>>;
extract_lead(Value, 2, 2) -> <<((Value bsr 16) band 16#FFFF):16/little>>;
extract_lead(Value, 2, 4) -> <<((Value bsr 16) band 16#FFFFFFFF):32/little>>;
extract_lead(Value, 2, 5) ->
    V = Value bsr 16,
    <<(V band 16#FFFFFFFF):32/little, ((V bsr 32) band 16#FF):8>>;
extract_lead(Value, 3, 1) -> <<((Value bsr 24) band 16#FF):8>>;
extract_lead(Value, 3, 2) -> <<((Value bsr 24) band 16#FFFF):16/little>>;
extract_lead(Value, 3, 4) -> <<((Value bsr 24) band 16#FFFFFFFF):32/little>>;
extract_lead(Value, 3, 5) ->
    V = Value bsr 24,
    <<(V band 16#FFFFFFFF):32/little, ((V bsr 32) band 16#FF):8>>;
extract_lead(Value, 4, 1) -> <<((Value bsr 32) band 16#FF):8>>;
extract_lead(Value, 4, 2) -> <<((Value bsr 32) band 16#FFFF):16/little>>;
extract_lead(Value, 4, 4) -> <<((Value bsr 32) band 16#FFFFFFFF):32/little>>;
extract_lead(Value, 5, 1) -> <<((Value bsr 40) band 16#FF):8>>;
extract_lead(Value, 5, 2) -> <<((Value bsr 40) band 16#FFFF):16/little>>;
extract_lead(Value, 6, 1) -> <<((Value bsr 48) band 16#FF):8>>.

extract_qwords(_Arr, _Offset, 0, Acc) -> iolist_to_binary(lists:reverse(Acc));
extract_qwords(Arr, Offset, Size, Acc) when Size >= 8 ->
    Value = array:get(Offset bsr 3, Arr),
    Lo32 = Value band 16#FFFFFFFF,
    Hi32 = Value bsr 32,
    extract_qwords(Arr, Offset + 8, Size - 8,
                   [<<Lo32:32/little, Hi32:32/little>> | Acc]);
extract_qwords(Arr, Offset, Remaining, Acc) ->
    Value = array:get(Offset bsr 3, Arr),
    Bytes = <<(Value band 16#FF):8, ((Value bsr 8) band 16#FF):8,
              ((Value bsr 16) band 16#FF):8, ((Value bsr 24) band 16#FF):8,
              ((Value bsr 32) band 16#FF):8, ((Value bsr 40) band 16#FF):8,
              ((Value bsr 48) band 16#FF):8, ((Value bsr 56) band 16#FF):8>>,
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
            Index = Addr bsr 3,
            Shift = (Addr band 7) * 8,
            Old = array:get(Index, Arr),
            Mask = 16#FF bsl Shift,
            New = (Old band (bnot Mask)) bor ((Byte band 16#FF) bsl Shift),
            array:set(Index, New, Arr)
    end.
