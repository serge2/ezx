-module(ezx_memory_48_pages512_tuples).

%% @doc ZX Spectrum 48K memory backend using 512-byte pages stored as byte
%% tuples (512-element tuples). A variant of ezx_memory_48_pages512 where a
%% byte read is element/2 on the page tuple and a byte write is setelement/2
%% — no binary pattern match / binary rebuild on the hot path.
%%
%% == Structure ==
%% state() is {Pages, RomMask}: a 128-element tuple of 512-element page
%% tuples covering the 64KB address space. read_byte costs element(PageMap)
%% + element(Page) + element(Page); write_byte costs one setelement on the
%% page tuple (128 page slots to choose from, same geometry as the binary
%% pages512 backend).
%%
%% == Video buffer ==
%% read_video_block/1 returns the ULA screen buffer (the first ?VIDEO_SIZE
%% bytes of the 0x4000-0xFFFF region, i.e. 0x4000-0x5AFF: 6144 bitmap bytes +
%% 768 attribute bytes). 0x4000 is page index 33 (offset 0), and 6912 = 27 ×
%% 256 = 13.5 × 512, so the buffer covers 13 full pages + 256 bytes of the
%% 14th. Only those pages are flattened to a binary, never the whole bank.

-export([new/1, read_byte/2, read_block/3, read_video_block/1, write_byte/3]).

-type state() :: {Pages :: tuple(), RomMask :: integer()}.
-export_type([state/0]).

-define(PAGE_SIZE, 512).
-define(PAGE_BITS, 9).
-define(NUM_PAGES, 128).
-define(VIDEO_SIZE, (6144 + 768)).
-define(VIDEO_FULL_PAGES, ?VIDEO_SIZE div ?PAGE_SIZE).   %% 13 full 512-byte pages.
-define(VIDEO_TAIL, ?VIDEO_SIZE rem ?PAGE_SIZE).         %% 256 bytes of the 14th.
-define(VIDEO_START_PAGE, 16#4000 bsr ?PAGE_BITS + 1).   %% page index of 0x4000.

%% @doc Create a new 64KB memory state from a ROM binary.
-spec new(binary()) -> state().
new(Rom) when is_binary(Rom) ->
    Rom64 = case byte_size(Rom) of
        65536 -> Rom;
        N when N < 65536 -> <<Rom/binary, 0:(65536 - N)/unit:8>>;
        _ -> binary:part(Rom, 0, 65536)
    end,
    Pages = split_pages(Rom64, 1, erlang:make_tuple(?NUM_PAGES, list_to_tuple(lists:duplicate(?PAGE_SIZE, 0)))),
    {Pages, 16#01FF}.

split_pages(<<>>, _I, Acc) -> Acc;
split_pages(<<Page:?PAGE_SIZE/binary, Rest/binary>>, I, Acc) ->
    split_pages(Rest, I + 1, setelement(I, Acc, byte_tuple(Page)));
split_pages(<<Page/binary>>, I, Acc) ->
    Pad = <<Page/binary, 0:(?PAGE_SIZE - byte_size(Page))/unit:8>>,
    setelement(I, Acc, byte_tuple(Pad)).

%% @doc Read a single byte at `Addr' (0..65535).
-spec read_byte(state(), non_neg_integer()) -> byte().
read_byte({Pages, _}, Addr) ->
    Index = Addr band 16#FFFF,
    Page = (Index bsr ?PAGE_BITS) + 1,
    Offset = Index band (?PAGE_SIZE - 1),
    element(Offset + 1, element(Page, Pages)).

%% @doc Read a contiguous block of `Size' bytes starting at `Addr'.
%% Wraps around at the 64KB boundary.
-spec read_block(state(), non_neg_integer(), non_neg_integer()) -> binary().
read_block({Pages, _}, Addr, Size) ->
    Index = Addr band 16#FFFF,
    read_block_pages(Pages, Index, Size, []).

read_block_pages(_Pages, _Offset, 0, Acc) -> list_to_binary(lists:reverse(Acc));
read_block_pages(Pages, Offset, Remaining, Acc) ->
    Page = (Offset bsr ?PAGE_BITS) + 1,
    PageOff = Offset band (?PAGE_SIZE - 1),
    PageTuple = element(Page, Pages),
    Available = ?PAGE_SIZE - PageOff,
    Take = min(Remaining, Available),
    Chunk = page_slice(PageTuple, PageOff + 1, Take),
    read_block_pages(Pages, (Offset + Take) band 16#FFFF, Remaining - Take, [Chunk | Acc]).

%% @doc Read the ULA display buffer (first ?VIDEO_SIZE bytes at 0x4000).
%% The size is fixed, so no size argument is needed; only the page tuples
%% that intersect the screen region are flattened to a single binary.
-spec read_video_block(state()) -> binary().
read_video_block({Pages, _}) ->
    First = ?VIDEO_START_PAGE,
    Full = [tuple_to_list(element(I, Pages)) || I <- lists:seq(First, First + ?VIDEO_FULL_PAGES - 1)],
    Tail = lists:sublist(tuple_to_list(element(First + ?VIDEO_FULL_PAGES, Pages)), ?VIDEO_TAIL),
    iolist_to_binary([Full, Tail]).

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
            PageTuple = element(PageIdx, Pages),
            NewPage = setelement(Offset + 1, PageTuple, Byte band 16#FF),
            {setelement(PageIdx, Pages, NewPage), RomMask}
    end.

%% --- internal ---

byte_tuple(Bin) -> list_to_tuple(binary_to_list(Bin)).

%% Elements From..From+Count-1 of a page tuple, as a binary.
page_slice(_Tuple, _From, 0) -> <<>>;
page_slice(Tuple, From, Count) ->
    list_to_binary(take_tuple(Tuple, From, From + Count - 1, [])).

take_tuple(_Tuple, Ix, End, Acc) when Ix > End -> lists:reverse(Acc);
take_tuple(Tuple, Ix, End, Acc) ->
    take_tuple(Tuple, Ix + 1, End, [element(Ix, Tuple) | Acc]).
