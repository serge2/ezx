-module(ezx_memory_128_pages512).

%% @doc 128K memory backend using 512-byte page tuples.
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
%% == Shadow screen (bank 7) ==
%% The CPU cannot reach bank 7 through 0x4000. To draw the shadow screen it
%% pages bank 7 into slot 3 (bits 0-2 = 7) and writes to 0xC000-0xFFFF; the
%% display only switches to bank 7 when bit 3 is set. The typical double
%% buffer: draw into the non-displayed bank via slot 3, then flip bit 3.
%% Because 0x4000-0x7FFF is fixed at bank 5, the stack (usually kept there,
%% e.g. 0x7FFx) survives any paging and display flips.
%%
%% == Structure ==
%% The 64KB address space is split into 128 pages of 512 bytes each.
%% A page map (128-element tuple) stores the currently visible 512-byte
%% binary for each address range. This gives read_byte a hot path of
%% one element() lookup + binary pattern match — the same cost as the
%% 48K pages512 backend.
%%
%% Physical memory is stored separately in PhysPages (320-element tuple):
%%   2 ROM banks × 32 pages + 8 RAM banks × 32 pages = 320 pages.
%% PhysPages is the authoritative backing store; writes go to both
%% the page map (live view) and PhysPages (preserved across bank switches).
%%
%% == Paging ==
%% Port 0x7FFD controls three address regions:
%%   - 0x0000 (ROM):  selects ROM0 (pages 1-32) or ROM1 (pages 33-64)
%%   - 0x4000 (CPU):  always RAM bank 5; p7FFD bit 3 only selects the
%%                    display bank (5 or 7) for the ULA, not the CPU view
%%   - 0x8000 (bank 2): fixed at RAM bank 2 (pages 129-160)
%%   - 0xC000 (slot 3): selects RAM bank 0-7
%% On write_port_7ffd/2 the page map is rebuilt from PhysPages for
%% the affected slots.
%%
%% == Snapshot loading ==
%% write_bank_block/3 writes only to PhysPages (no page map update).
%% The caller (snapshot loader) then calls write_port_7ffd/2, which
%% rebuilds the page map from PhysPages, making the new banks visible.

-export([
    new/2,
    read_byte/2,
    read_block/3,
    read_video_block/2,
    write_byte/3,
    write_port_7ffd/2,
    get_p7ffd/1,
    write_bank_block/3
]).

-opaque state() :: {PageMap :: tuple(), PhysPages :: tuple(), P7ffd :: byte()}.
-export_type([state/0]).

-define(PAGE_SIZE,  512).
-define(PAGE_BITS,  9).
-define(BANK_PAGES, 32).

-spec new(binary(), binary()) -> state().
new(Rom0, Rom1) ->
    R0 = pad(Rom0, ?PAGE_SIZE * 32),
    R1 = pad(Rom1, ?PAGE_SIZE * 32),
    Ram = pad(<<>>, ?PAGE_SIZE * 8 * 32),
    PhysPages = list_to_tuple(split_512(R0) ++ split_512(R1) ++ split_512(Ram)),
    PageMap = build_page_map(PhysPages, 0),
    {PageMap, PhysPages, 0}.

-spec read_byte(state(), non_neg_integer()) -> byte().
read_byte({PageMap, _, _}, Addr) ->
    Page = element(((Addr bsr ?PAGE_BITS) band 16#7F) + 1, PageMap),
    Off = Addr band (?PAGE_SIZE - 1),
    <<_:Off/binary, Byte:8, _/binary>> = Page,
    Byte.

-spec read_block(state(), non_neg_integer(), non_neg_integer()) -> binary().
read_block(State, Addr, Size) ->
    read_block_1(State, Addr band 16#FFFF, Size, []).

read_block_1(_State, _Addr, 0, Acc) -> list_to_binary(lists:reverse(Acc));
read_block_1({PageMap, _, _} = State, Addr, Remaining, Acc) ->
    Page = element(((Addr bsr ?PAGE_BITS) band 16#7F) + 1, PageMap),
    Off = Addr band (?PAGE_SIZE - 1),
    Avail = ?PAGE_SIZE - Off,
    Take = min(Remaining, Avail),
    <<_:Off/binary, Chunk:Take/binary, _/binary>> = Page,
    read_block_1(State, (Addr + Take) band 16#FFFF, Remaining - Take, [Chunk | Acc]).

-spec write_byte(state(), non_neg_integer(), byte()) -> state().
write_byte(State, Addr, _Byte) when Addr < 16#4000 -> State;
write_byte({PageMap, PhysPages, P7ffd}, Addr, Byte) ->
    PMIdx = ((Addr bsr ?PAGE_BITS) band 16#7F) + 1,
    Page = element(PMIdx, PageMap),
    Off = Addr band (?PAGE_SIZE - 1),
    <<Prefix:Off/binary, _:8, Suffix/binary>> = Page,
    NewPage = <<Prefix/binary, Byte:8, Suffix/binary>>,
    PPIdx = page_to_phys(Addr, P7ffd),
    {setelement(PMIdx, PageMap, NewPage), setelement(PPIdx, PhysPages, NewPage), P7ffd}.

-spec write_port_7ffd(state(), byte()) -> state().
write_port_7ffd({_, PhysPages, _}, Value) ->
    NewP7 = Value band 16#FF,
    {build_page_map(PhysPages, NewP7), PhysPages, NewP7}.

%% @doc Read the display (ULA video) buffer. p7FFD bit 3 selects whether the
%% screen is drawn from bank 5 or bank 7, independently of the CPU's 0x4000
%% mapping (which is always bank 5). `Size' must not exceed 16384.
-spec read_video_block(state(), non_neg_integer()) -> binary().
read_video_block({_PageMap, PhysPages, P7ffd}, Size) ->
    Base = 65 + screen_bank(P7ffd) * ?BANK_PAGES,
    Pages = [element(I, PhysPages) || I <- lists:seq(Base, Base + ?BANK_PAGES - 1)],
    binary:part(iolist_to_binary(Pages), 0, Size).

-spec get_p7ffd(state()) -> byte().
get_p7ffd({_, _, P7ffd}) -> P7ffd.

-spec write_bank_block(state(), non_neg_integer(), binary()) -> state().
write_bank_block({PageMap, PhysPages, P7ffd}, Bank, Data) ->
    PhysBase = 65 + Bank * ?BANK_PAGES,
    Pages = split_512(pad(Data, ?PAGE_SIZE * ?BANK_PAGES)),
    Indices = lists:seq(PhysBase, PhysBase + ?BANK_PAGES - 1),
    PhysPages1 = lists:foldl(fun({I, P}, Acc) -> setelement(I, Acc, P) end,
                             PhysPages, lists:zip(Indices, Pages)),
    {PageMap, PhysPages1, P7ffd}.

%% --- internal ---

page_to_phys(Addr, P7ffd) ->
    Slot = (Addr bsr 14) band 3,
    BankPage = (Addr bsr ?PAGE_BITS) band 31,
    Base = case Slot of
        0 -> error(rom_write);
        1 -> 65 + 5 * ?BANK_PAGES;
        2 -> 65 + 2 * ?BANK_PAGES;
        3 -> 65 + slot3_bank(P7ffd) * ?BANK_PAGES
    end,
    Base + BankPage.

screen_bank(P7ffd) -> case (P7ffd bsr 3) band 1 of 0 -> 5; 1 -> 7 end.
slot3_bank(P7ffd)  -> P7ffd band 7.
rom_select(P7ffd)  -> case (P7ffd bsr 4) band 1 of 0 -> 1; 1 -> 33 end.

build_page_map(PhysPages, P7ffd) ->
    RomB  = rom_select(P7ffd),
    ScrB  = 65 + 5 * ?BANK_PAGES,
    B2B   = 65 + 2 * ?BANK_PAGES,
    S3B   = 65 + slot3_bank(P7ffd) * ?BANK_PAGES,
    list_to_tuple(
        [element(I, PhysPages) || I <- lists:seq(RomB,  RomB  + 31)] ++
        [element(I, PhysPages) || I <- lists:seq(ScrB,  ScrB  + 31)] ++
        [element(I, PhysPages) || I <- lists:seq(B2B,   B2B   + 31)] ++
        [element(I, PhysPages) || I <- lists:seq(S3B,   S3B   + 31)]
    ).

pad(Bin, Size) when byte_size(Bin) >= Size -> binary:part(Bin, 0, Size);
pad(Bin, Size) -> <<Bin/binary, 0:(Size - byte_size(Bin))/unit:8>>.

split_512(<<>>) -> [];
split_512(Bin) ->
    <<Page:512/binary, Rest/binary>> = Bin,
    [Page | split_512(Rest)].
