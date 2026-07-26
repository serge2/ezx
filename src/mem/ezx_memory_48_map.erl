-module(ezx_memory_48_map).

%% @doc ZX Spectrum 48K memory backend using a map of 4KB pages.
%%
%% 16 pages of 4096 bytes each, indexed by `Addr bsr 12'.
%% Page lookups are map operations. Bulk reads split across page boundaries.

-export([new/1, read_byte/2, read_block/3, write_byte/3]).

-type state() :: #{pages => #{non_neg_integer() => binary()}}.
-export_type([state/0]).

-define(PAGE_SIZE, 4096).
-define(PAGE_BITS, 12).

%% @doc Create a new 64KB memory state from a ROM binary.
-spec new(binary()) -> state().
new(Rom) when is_binary(Rom) ->
    Rom64 = case byte_size(Rom) of
        65536 -> Rom;
        N when N < 65536 -> <<Rom/binary, 0:(65536 - N)/unit:8>>;
        _ -> binary:part(Rom, 0, 65536)
    end,
    Pages = split_pages(Rom64, 0, #{}),
    #{pages => Pages}.

split_pages(<<>>, _I, Acc) -> Acc;
split_pages(<<Page:?PAGE_SIZE/binary, Rest/binary>>, I, Acc) ->
    split_pages(Rest, I + 1, Acc#{I => Page});
split_pages(<<Page/binary>>, I, Acc) ->
    Pad = <<Page/binary, 0:(?PAGE_SIZE - byte_size(Page))/unit:8>>,
    Acc#{I => Pad}.

%% @doc Read a single byte at `Addr' (0..65535).
-spec read_byte(state(), non_neg_integer()) -> byte().
read_byte(#{pages := Pages}, Addr) ->
    Index = Addr band 16#FFFF,
    Page = Index bsr ?PAGE_BITS,
    Offset = Index band (?PAGE_SIZE - 1),
    Bin = maps:get(Page, Pages),
    <<_:Offset/binary, Byte:8/integer, _/binary>> = Bin,
    Byte.

%% @doc Read a contiguous block of `Size' bytes starting at `Addr'.
%% Wraps around at the 64KB boundary.
-spec read_block(state(), non_neg_integer(), non_neg_integer()) -> binary().
read_block(#{pages := Pages}, Addr, Size) ->
    Index = Addr band 16#FFFF,
    read_block_pages(Pages, Index, Size, <<>>).

read_block_pages(_Pages, _Offset, 0, Acc) -> Acc;
read_block_pages(Pages, Offset, Remaining, Acc) ->
    Page = Offset bsr ?PAGE_BITS,
    PageOff = Offset band (?PAGE_SIZE - 1),
    Bin = maps:get(Page, Pages),
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
            #{pages := Pages} = State,
            Page = Index bsr ?PAGE_BITS,
            Offset = Index band (?PAGE_SIZE - 1),
            Bin = maps:get(Page, Pages),
            <<Prefix:Offset/binary, _Old:8/integer, Suffix/binary>> = Bin,
            NewBin = <<Prefix/binary, (Byte band 16#FF):8/integer, Suffix/binary>>,
            State#{pages := Pages#{Page := NewBin}}
    end.
