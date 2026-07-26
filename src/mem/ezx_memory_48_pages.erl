-module(ezx_memory_48_pages).

%% @doc ZX Spectrum 48K memory backend using a tuple of 4KB pages.
%%
%% 16 pages of 4096 bytes each, stored in a tuple for O(1) `element/2' access.
%% Slightly faster than the map-based `ezx_memory_48_map' because tuple
%% indexing avoids hashing overhead.

-export([
    new/1,
    read_byte/2,
    read_block/3,
    write_byte/3
]).

-type state() :: {Pages :: tuple(), RomMask :: integer()}.
-export_type([state/0]).

-define(PAGE_SIZE, 4096).
-define(PAGE_BITS, 12).
-define(NUM_PAGES, 16).

%% @doc Create a new 64KB memory state from a ROM binary.
-spec new(binary()) -> state().
new(Rom) when is_binary(Rom) ->
    Rom64 = case byte_size(Rom) of
        65536 -> Rom;
        N when N < 65536 -> <<Rom/binary, 0:(65536 - N)/unit:8>>;
        _ -> binary:part(Rom, 0, 65536)
    end,
    Pages = split_pages(Rom64, 1, erlang:make_tuple(?NUM_PAGES, <<0:?PAGE_SIZE/unit:8>>)),
    RomMask = 16#3FFF,
    {Pages, RomMask}.

split_pages(<<>>, _I, Acc) -> Acc;
split_pages(<<Page:?PAGE_SIZE/binary, Rest/binary>>, I, Acc) ->
    split_pages(Rest, I + 1, setelement(I, Acc, Page));
split_pages(<<Page/binary>>, I, Acc) ->
    Pad = <<Page/binary, 0:(?PAGE_SIZE - byte_size(Page))/unit:8>>,
    setelement(I, Acc, Pad).

%% @doc Read a single byte at `Addr' (0..65535).
-spec read_byte(state(), non_neg_integer()) -> byte().
read_byte({Pages, _RomMask}, Addr) ->
    Index = Addr band 16#FFFF,
    Page = (Index bsr ?PAGE_BITS) + 1,
    Offset = Index band (?PAGE_SIZE - 1),
    Bin = element(Page, Pages),
    <<_:Offset/binary, Byte:8/integer, _/binary>> = Bin,
    Byte.

%% @doc Read a contiguous block of `Size' bytes starting at `Addr'.
%% Wraps around at the 64KB boundary.
-spec read_block(state(), non_neg_integer(), non_neg_integer()) -> binary().
read_block({Pages, _RomMask}, Addr, Size) ->
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
            <<Prefix:Offset/binary, _Old:8/integer, Suffix/binary>> = Bin,
            NewBin = <<Prefix/binary, (Byte band 16#FF):8/integer, Suffix/binary>>,
            {setelement(PageIdx, Pages, NewBin), RomMask}
    end.
