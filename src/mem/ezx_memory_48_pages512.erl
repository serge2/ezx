-module(ezx_memory_48_pages512).

%% @doc ZX Spectrum 48K memory backend using a tuple of 512-byte pages.
%%
%% 128 pages of 512 bytes each. Fastest tuple variant for CPU work
%% (smallest page index), but bulk reads cross many more page boundaries.

-export([new/1, read_byte/2, read_block/3, read_video_block/1, write_byte/3]).

-type state() :: {Pages :: tuple(), RomMask :: integer()}.
-export_type([state/0]).

-define(PAGE_SIZE, 512).
-define(PAGE_BITS, 9).
-define(NUM_PAGES, 128).
-define(VIDEO_SIZE, (6144 + 768)).

%% @doc Create a new 64KB memory state from a ROM binary.
-spec new(binary()) -> state().
new(Rom) when is_binary(Rom) ->
    Rom64 = case byte_size(Rom) of
        65536 -> Rom;
        N when N < 65536 -> <<Rom/binary, 0:(65536 - N)/unit:8>>;
        _ -> binary:part(Rom, 0, 65536)
    end,
    Pages = split_pages(Rom64, 1, erlang:make_tuple(?NUM_PAGES, <<0:?PAGE_SIZE/unit:8>>)),
    {Pages, 16#01FF}.

split_pages(<<>>, _I, Acc) -> Acc;
split_pages(<<Page:?PAGE_SIZE/binary, Rest/binary>>, I, Acc) ->
    split_pages(Rest, I + 1, setelement(I, Acc, Page));
split_pages(<<Page/binary>>, I, Acc) ->
    Pad = <<Page/binary, 0:(?PAGE_SIZE - byte_size(Page))/unit:8>>,
    setelement(I, Acc, Pad).

%% @doc Read a single byte at `Addr' (0..65535).
-spec read_byte(state(), non_neg_integer()) -> byte().
read_byte({Pages, _}, Addr) ->
    Index = Addr band 16#FFFF,
    Page = (Index bsr ?PAGE_BITS) + 1,
    Offset = Index band (?PAGE_SIZE - 1),
    Bin = element(Page, Pages),
    <<_:Offset/binary, Byte:8, _/binary>> = Bin,
    Byte.

%% @doc Read a contiguous block of `Size' bytes starting at `Addr'.
%% Wraps around at the 64KB boundary.
-spec read_block(state(), non_neg_integer(), non_neg_integer()) -> binary().
read_block({Pages, _}, Addr, Size) ->
    Index = Addr band 16#FFFF,
    read_block_pages(Pages, Index, Size, <<>>).

read_block_pages(_Pages, _Offset, 0, Acc) -> Acc;
read_block_pages(Pages, Offset, Remaining, Acc) ->
    Page = (Offset bsr ?PAGE_BITS) + 1,
    PageOff = Offset band (?PAGE_SIZE - 1),
    Bin = element(Page, Pages),
    Available = ?PAGE_SIZE - PageOff,
    Take = min(Remaining, Available),
    <<_:PageOff/binary, Chunk:Take/binary, _/binary>> = Bin,
    read_block_pages(Pages, (Offset + Take) band 16#FFFF, Remaining - Take, <<Acc/binary, Chunk/binary>>).

%% @doc Read the ULA display buffer (first ?VIDEO_SIZE bytes at 0x4000).
%% The size is fixed, so no size argument is needed.
-spec read_video_block(state()) -> binary().
read_video_block(State) -> read_block(State, 16#4000, ?VIDEO_SIZE).

%% @doc Write `Byte' to `Addr'. ROM area writes are ignored.
-spec write_byte(state(), non_neg_integer(), byte()) -> state().
write_byte(State, Addr, Byte) ->
    Index = Addr band 16#FFFF,
    case Index < 16#4000 of
        true -> State;
        false ->
            {Pages, RomMask} = State,
            PageIdx = (Index bsr ?PAGE_BITS) + 1,
            Offset = Index band (?PAGE_SIZE - 1),
            Bin = element(PageIdx, Pages),
            <<Prefix:Offset/binary, _Old:8, Suffix/binary>> = Bin,
            NewBin = <<Prefix/binary, (Byte band 16#FF):8, Suffix/binary>>,
            {setelement(PageIdx, Pages, NewBin), RomMask}
    end.
