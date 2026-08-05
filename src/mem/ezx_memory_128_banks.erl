-module(ezx_memory_128_banks).

%% @doc 128K memory backend: record-based state, a 4-slot routing tuple, and
%% a banks tuple of 16KB banks (each a tuple of 512-byte binary pages).
%%
%% == Memory map (CPU view) ==
%% 0x0000-0x3FFF: ROM (0 = editor, 1 = 48K BASIC, selected by p7FFD bit 4)
%% 0x4000-0x7FFF: RAM (bank 5, always)
%% 0x8000-0xBFFF: RAM (bank 2, always)
%% 0xC000-0xFFFF: RAM (bank 0-7, selected by p7FFD bits 0-2)
%%
%% == Port 0x7FFD ==
%%   bits 0-2:  slot 3 (0xC000) bank select 0-7
%%   bit  3:    ULA display bank (5 or 7) — NOT a CPU mapping change
%%   bit  4:    ROM select (0 = editor, 1 = 48K BASIC)
%% The bits are independent. Bit 3 never changes what the CPU sees at
%% 0x4000-0x7FFF; it only tells the ULA which bank to draw the screen from.
%%
%% == Structure ==
%% state() is a record (readability over the tuple states; same performance).
%% The banks live in a plain 10-element tuple (2 ROM banks + 8 RAM banks);
%% each bank is 16KB stored as a 32-element tuple of 512-byte binary pages
%% (same page geometry as the other page-based backends), so a page rewrite
%% is a setelement on a 32-element tuple. Variants of per-bank storage could
%% be plugged in later without touching the routing logic.
%%
%% Bank indices: 0 = ROM0, 1 = ROM1, 2-9 = RAM banks 0-7. The routing tuple
%% {Rom, Screen, Bank2, Slot3} holds the ready-made element position of the
%% bank inside the banks tuple (logical index + ?BANK_INDEX_OFFSET), so the
%% hot read/write path indexes directly with element(BankSlot, Banks) — no
%% offset arithmetic per access. It is rebuilt only by write_port_7ffd/2
%% (rare). Reads/writes resolve the slot from the address and take the bank
%% position from the routing tuple, so writes never need to touch the routing
%% table (positions stay valid while the p7FFD value is unchanged).
%%
%% read_video_block/1 reads the bank selected by p7FFD bit 3 (5 or 7).

-export([
    new/2,
    read_byte/2,
    read_block/3,
    read_video_block/1,
    read_bank_block/2,
    write_byte/3,
    write_port_7ffd/2,
    get_p7ffd/1,
    write_bank_block/3
]).

-record(mem128, {
    routing :: {bank_slot(), bank_slot(), bank_slot(), bank_slot()},
    banks :: banks(),
    p7ffd :: byte()
}).

-opaque state() :: #mem128{}.
-export_type([state/0]).

-type banks() :: tuple().         %% 10-element tuple of bank() (2 ROM + 8 RAM).
-type bank_slot() :: 1..10.       %% element position in banks() (offset baked in).

-define(PAGE_SIZE, 512).
-define(PAGE_BITS, 9).
-define(BANK_PAGES, 32).
-define(BANK_SIZE, 16384).
-define(VIDEO_SIZE, (6144 + 768)).
-define(VIDEO_FULL_PAGES, ?VIDEO_SIZE div ?PAGE_SIZE).   %% 13 full 512-byte pages.
-define(VIDEO_TAIL, ?VIDEO_SIZE rem ?PAGE_SIZE).         %% 256 bytes of the 14th.
-define(RAM_BASE_IDX, 2).         %% first RAM bank index.

%% Bank index B -> element(B + 1, Banks): banks is a plain 10-element tuple,
%% element 1 = ROM0, element 2 = ROM1, elements 3-10 = RAM banks 0-7.
-define(BANK_INDEX_OFFSET, 1).

-spec new(binary(), binary()) -> state().
new(Rom0, Rom1) ->
    R0 = make_bank(pad(Rom0, ?BANK_SIZE)),
    R1 = make_bank(pad(Rom1, ?BANK_SIZE)),
    RamBank = make_bank(pad(<<>>, ?BANK_SIZE)),
    Banks = {R0, R1, RamBank, RamBank, RamBank, RamBank,
             RamBank, RamBank, RamBank, RamBank},
    #mem128{routing = build_routing(0), banks = Banks, p7ffd = 0}.

-spec read_byte(state(), non_neg_integer()) -> byte().
read_byte(#mem128{routing = Routing, banks = Banks}, Addr) ->
    BankSlot = element(((Addr bsr 14) band 3) + 1, Routing),
    Bank = element(BankSlot, Banks),
    PageIdx = ((Addr bsr ?PAGE_BITS) band (?BANK_PAGES - 1)) + 1,
    Off = Addr band (?PAGE_SIZE - 1),
    <<_:Off/binary, Byte:8, _/binary>> = element(PageIdx, Bank),
    Byte.

-spec read_block(state(), non_neg_integer(), non_neg_integer()) -> binary().
read_block(State, Addr, Size) ->
    read_block_1(State, Addr band 16#FFFF, Size, []).

read_block_1(_State, _Addr, 0, Acc) -> list_to_binary(lists:reverse(Acc));
read_block_1(#mem128{routing = Routing, banks = Banks} = State, Addr, Remaining, Acc) ->
    BankSlot = element(((Addr bsr 14) band 3) + 1, Routing),
    Bank = element(BankSlot, Banks),
    PageIdx = ((Addr bsr ?PAGE_BITS) band (?BANK_PAGES - 1)) + 1,
    Off = Addr band (?PAGE_SIZE - 1),
    Avail = ?PAGE_SIZE - Off,
    Take = min(Remaining, Avail),
    <<_:Off/binary, Chunk:Take/binary, _/binary>> = element(PageIdx, Bank),
    read_block_1(State, (Addr + Take) band 16#FFFF, Remaining - Take, [Chunk | Acc]).

-spec write_byte(state(), non_neg_integer(), byte()) -> state().
write_byte(State, Addr, _Byte) when Addr < 16#4000 -> State;
write_byte(#mem128{routing = Routing, banks = Banks} = State, Addr, Byte) ->
    BankSlot = element(((Addr bsr 14) band 3) + 1, Routing),
    Bank = element(BankSlot, Banks),
    PageIdx = ((Addr bsr ?PAGE_BITS) band (?BANK_PAGES - 1)) + 1,
    Off = Addr band (?PAGE_SIZE - 1),
    <<Prefix:Off/binary, _:8, Suffix/binary>> = element(PageIdx, Bank),
    NewPage = <<Prefix/binary, Byte:8, Suffix/binary>>,
    State#mem128{banks = setelement(BankSlot, Banks,
                                    setelement(PageIdx, Bank, NewPage))}.

-spec write_port_7ffd(state(), byte()) -> state().
write_port_7ffd(#mem128{} = State, Value) ->
    NewP7 = Value band 16#FF,
    State#mem128{routing = build_routing(NewP7), p7ffd = NewP7}.

%% @doc Read the ULA display buffer (first ?VIDEO_SIZE bytes of the bank
%% selected by p7FFD bit 3 — the 6144-byte bitmap + 768 attribute bytes).
%% The buffer size is fixed, so no size argument is needed; only the pages
%% that intersect the screen region are collected, not the whole 16KB bank.
-spec read_video_block(state()) -> binary().
read_video_block(#mem128{banks = Banks, p7ffd = P7ffd}) ->
    Bank = element(screen_slot(P7ffd), Banks),
    Full = [element(I, Bank) || I <- lists:seq(1, ?VIDEO_FULL_PAGES)],
    Tail = element(?VIDEO_FULL_PAGES + 1, Bank),
    iolist_to_binary([Full, binary:part(Tail, 0, ?VIDEO_TAIL)]).

-spec get_p7ffd(state()) -> byte().
get_p7ffd(#mem128{p7ffd = P7ffd}) -> P7ffd.

%% @doc Read a whole 16KB RAM bank (index 0-7) as a binary. Used by snapshot
%% save to dump the 128K RAM image.
-spec read_bank_block(state(), 0..7) -> binary().
read_bank_block(#mem128{banks = Banks}, Bank) ->
    iolist_to_binary(tuple_to_list(element(Bank + ?RAM_BASE_IDX + ?BANK_INDEX_OFFSET,
                                           Banks))).

-spec write_bank_block(state(), non_neg_integer(), binary()) -> state().
write_bank_block(#mem128{banks = Banks} = State, Bank, Data) ->
    NewBank = make_bank(pad(Data, ?BANK_SIZE)),
    State#mem128{banks = setelement(Bank + ?RAM_BASE_IDX + ?BANK_INDEX_OFFSET,
                                   Banks, NewBank)}.

%% --- internal ---

build_routing(P7ffd) ->
    {rom_select(P7ffd) + ?BANK_INDEX_OFFSET,
     5 + ?RAM_BASE_IDX + ?BANK_INDEX_OFFSET,
     2 + ?RAM_BASE_IDX + ?BANK_INDEX_OFFSET,
     (P7ffd band 7) + ?RAM_BASE_IDX + ?BANK_INDEX_OFFSET}.

%% element position in banks() of the RAM bank used for the ULA display.
screen_slot(P7ffd) -> screen_bank(P7ffd) + ?RAM_BASE_IDX + ?BANK_INDEX_OFFSET.

screen_bank(P7ffd) -> case (P7ffd bsr 3) band 1 of 0 -> 5; 1 -> 7 end.
rom_select(P7ffd)  -> case (P7ffd bsr 4) band 1 of 0 -> 0; 1 -> 1 end.

make_bank(Bin) -> list_to_tuple(split_512(Bin)).

split_512(<<>>) -> [];
split_512(Bin) ->
    <<Page:512/binary, Rest/binary>> = Bin,
    [Page | split_512(Rest)].

pad(Bin, Size) when byte_size(Bin) >= Size -> binary:part(Bin, 0, Size);
pad(Bin, Size) -> <<Bin/binary, 0:(Size - byte_size(Bin))/unit:8>>.
