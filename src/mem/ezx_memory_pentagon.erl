-module(ezx_memory_pentagon).

%% @doc Pentagon memory backend (128K / 512K / 1024K): record-based state, a
%% 4-slot routing tuple, and a banks tuple of 16KB banks stored as byte-tuple
%% pages — the winning storage layout of ezx_memory_128_banks_tuples,
%% extended with the Pentagon hardware.
%%
%% == Banks tuple ==
%% Elements 1-3 are ROMs: 0 = BASIC 128, 1 = BASIC 48, 2 = TR-DOS (Beta).
%% The RAM banks follow at element position Bank + 4: 8 banks on the Pentagon
%% 128K, 32 on the 512K, 64 on the 1024K.
%%
%% == Port 0x7FFD (Pentagon wiring) ==
%%   bits 0-2: slot-3 page select (as on the 128K)
%%   bit  3:   ULA display bank (5 or 7)
%%   bit  4:   ROM select (0 = BASIC 128, 1 = BASIC 48)
%%   bit  5:   paging lock — EXCEPT on a 1024K machine while #EFF7 enables
%%             1MB mode (bit 2 clear), where bit 5 is RAM page bit 5 instead
%%             and can never lock
%%   bits 6-7: RAM page bits 3-4 (the Pentagon feeds extra address lines into
%%             the page register; the mask drops them on smaller models)
%%
%% == Port #EFF7 (present on the 1024K only) ==
%%   bit 2: 1 = standard zx128 mapping (reset default), 0 = 1MB paging enabled
%%   bit 3: overlay the bottom 16K with RAM bank 0 (all-RAM mode)
%%
%% == TR-DOS ROM ==
%% The TR-DOS ROM maps in while the Beta interface is latched — the hardware
%% latch gates the chip select, so it wins regardless of p7FFD bit 4. There
%% is no FDC emulation. On real Pentagon hardware the interface engages
%% through the magic window: an opcode fetch from #3D00-#3DFF with 48 BASIC
%% paged in enables it, an opcode fetch at #4000+ disables it again —
%% read_opcode/2 models exactly that, driven by the CPU's M1 cycle. Port
%% #1FFD bit 4 (DOSEN latch) and the emulator API
%% (ezx_emulator_pentagon:set_dos_rom/2) remain as alternate drivers for
%% tests and saves; the flag starts cleared at reset, which is what makes
%% the machine boot into its menu ROM instead of straight into TR-DOS.
%%
%% Like the 128K backend, the routing tuple {Slot0, ScreenSlot, Slot2Slot,
%% Slot3Slot} bakes in element positions: the hot path indexes the banks
%% tuple directly, only the port writers rebuild the routing.

-export([
    new/2,
    read_byte/2,
    read_opcode/2,
    read_block/3,
    read_video_block/1,
    read_bank_block/2,
    write_byte/3,
    write_port_7ffd/2,
    get_p7ffd/1,
    write_port_1ffd/2,
    write_port_eff7/2,
    get_eff7/1,
    set_dos_rom/2,
    ram_banks/1,
    write_bank_block/3
]).

-record(pmem, {
    routing :: {bank_slot(), bank_slot(), bank_slot(), bank_slot()},
    banks :: tuple(),
    p7ffd :: byte(),
    eff7 = 16#0004 :: byte(),        %% bit2 = standard mapping, bit3 = all-RAM
    dos_rom = false :: boolean(),    %% Beta interface active (TR-DOS overlay)
    page_mask :: non_neg_integer()   %% RAM page bits wired on this model
}).

-opaque state() :: #pmem{}.
-export_type([state/0]).

-type bank_slot() :: pos_integer().   %% element position inside banks()
-type roms() :: {binary() | undefined, binary() | undefined,
                 binary() | undefined}.

-define(PAGE_SIZE, 512).
-define(PAGE_BITS, 9).
-define(BANK_PAGES, 32).
-define(BANK_SIZE, 16384).
-define(VIDEO_SIZE, (6144 + 768)).
-define(VIDEO_FULL_PAGES, ?VIDEO_SIZE div ?PAGE_SIZE).   %% 13 full 512-byte pages.
-define(VIDEO_TAIL, ?VIDEO_SIZE rem ?PAGE_SIZE).         %% 256 bytes of the 14th.
-define(ROM_SLOTS, 3).            %% elements 1-3: ROM0, ROM1, TR-DOS

%% RAM bank B lives at element position B + ?RAM_BASE_SLOT.
-define(RAM_BASE_SLOT, (?ROM_SLOTS + 1)).

-spec new(roms(), 8 | 32 | 64) -> state().
new({Rom0, Rom1, DosRom}, RamBanks) ->
    R0 = make_bank(pad(optional(Rom0), ?BANK_SIZE)),
    R1 = make_bank(pad(optional(Rom1), ?BANK_SIZE)),
    RD = make_bank(pad(optional(DosRom), ?BANK_SIZE)),
    RamBank = make_bank(pad(<<>>, ?BANK_SIZE)),
    Banks = list_to_tuple([R0, R1, RD | lists:duplicate(RamBanks, RamBank)]),
    State = #pmem{banks = Banks,
                  p7ffd = 0,
                  page_mask = ram_page_mask(RamBanks)},
    State#pmem{routing = build_routing(State)}.

-spec read_byte(state(), non_neg_integer()) -> byte().
read_byte(#pmem{routing = Routing, banks = Banks}, Addr) ->
    BankSlot = element(((Addr bsr 14) band 3) + 1, Routing),
    Bank = element(BankSlot, Banks),
    PageIdx = ((Addr bsr ?PAGE_BITS) band (?BANK_PAGES - 1)) + 1,
    Off = Addr band (?PAGE_SIZE - 1),
    element(Off + 1, element(PageIdx, Bank)).

%% @doc Opcode-fetch (M1) read with the Pentagon Beta-interface magic window
%% (MAME pentagon.cpp): an opcode fetch from #3D00-#3DFF while the 48 BASIC
%% ROM is paged in engages the Beta interface (TR-DOS ROM overlay), and any
%% opcode fetch at #4000 and above disengages it again. The triggering fetch
%% itself already sees the new mapping, like MAME's beta_enable_r/
%% beta_disable_r. Data reads never toggle the interface.
-spec read_opcode(state(), non_neg_integer()) -> {byte(), state()}.
read_opcode(State, Addr) ->
    State1 = maybe_toggle_beta(State, Addr),
    {read_byte(State1, Addr), State1}.

maybe_toggle_beta(#pmem{dos_rom = true} = State, Addr) when Addr >= 16#4000 ->
    set_dos_rom(State, false);
maybe_toggle_beta(#pmem{dos_rom = false, p7ffd = P7, eff7 = Eff7} = State, Addr)
        when Addr >= 16#3D00, Addr < 16#3E00,
             P7 band 16#10 =/= 0,   %% 48 BASIC ROM paged in
             Eff7 band 16#08 =:= 0 ->   %% not all-RAM mode
    set_dos_rom(State, true);
maybe_toggle_beta(State, _Addr) ->
    State.

-spec read_block(state(), non_neg_integer(), non_neg_integer()) -> binary().
read_block(State, Addr, Size) ->
    read_block_1(State, Addr band 16#FFFF, Size, []).

read_block_1(_State, _Addr, 0, Acc) -> list_to_binary(lists:reverse(Acc));
read_block_1(#pmem{routing = Routing, banks = Banks} = State, Addr, Remaining, Acc) ->
    BankSlot = element(((Addr bsr 14) band 3) + 1, Routing),
    Bank = element(BankSlot, Banks),
    PageIdx = ((Addr bsr ?PAGE_BITS) band (?BANK_PAGES - 1)) + 1,
    Off = Addr band (?PAGE_SIZE - 1),
    Avail = ?PAGE_SIZE - Off,
    Take = min(Remaining, Avail),
    Page = element(PageIdx, Bank),
    <<_:Off/binary, Chunk:Take/binary, _/binary>> = page_to_binary(Page),
    read_block_1(State, (Addr + Take) band 16#FFFF, Remaining - Take, [Chunk | Acc]).

-spec write_byte(state(), non_neg_integer(), byte()) -> state().
write_byte(State, Addr, _Byte) when Addr < 16#4000 -> State;
write_byte(#pmem{routing = Routing, banks = Banks} = State, Addr, Byte) ->
    BankSlot = element(((Addr bsr 14) band 3) + 1, Routing),
    Bank = element(BankSlot, Banks),
    PageIdx = ((Addr bsr ?PAGE_BITS) band (?BANK_PAGES - 1)) + 1,
    Off = Addr band (?PAGE_SIZE - 1),
    Page = element(PageIdx, Bank),
    case element(Off + 1, Page) of
        Byte ->
            State;
        _ ->
            NewPage = setelement(Off + 1, Page, Byte),
            State#pmem{banks = setelement(BankSlot, Banks,
                                          setelement(PageIdx, Bank, NewPage))}
    end.

-spec write_port_7ffd(state(), byte()) -> state().
write_port_7ffd(#pmem{} = State, Value) ->
    %% Bit 5 locks the port — unless this model reuses bit 5 as a RAM page
    %% address line (1024K in 1MB mode), where it can never lock.
    #pmem{p7ffd = P7, eff7 = Eff7, page_mask = Mask} = State,
    Locked = (P7 band 16#20) =/= 0 andalso not d5_is_page_bit(Mask, Eff7),
    case Locked of
        true -> State;
        false ->
            NewP7 = Value band 16#FF,
            State1 = State#pmem{p7ffd = NewP7},
            State1#pmem{routing = build_routing(State1)}
    end.

-spec get_p7ffd(state()) -> byte().
get_p7ffd(#pmem{p7ffd = P7ffd}) -> P7ffd.

-spec write_port_eff7(state(), byte()) -> state().
write_port_eff7(#pmem{page_mask = Mask} = State, _Value) when Mask =/= 63 ->
    State;  %% Only the 1024K decodes #EFF7.
write_port_eff7(#pmem{} = State, Value) ->
    Eff7 = Value band 16#0C,   %% modeled bits: 2 = mapping mode, 3 = all-RAM
    State1 = State#pmem{eff7 = Eff7},
    State1#pmem{routing = build_routing(State1)}.

-spec get_eff7(state()) -> byte().
get_eff7(#pmem{eff7 = Eff7}) -> Eff7.

%% @doc Drive the (stubbed) Beta disk interface: while enabled and p7FFD bit 4
%% is clear, the TR-DOS ROM occupies the bottom 16K.
-spec set_dos_rom(state(), boolean()) -> state().
set_dos_rom(#pmem{} = State, Enabled) ->
    State1 = State#pmem{dos_rom = Enabled},
    State1#pmem{routing = build_routing(State1)}.

%% @doc Port #1FFD (Beta interface system register): bit 4 = DOSEN, the
%% TR-DOS ROM overlay enable (the latch itself wins over p7FFD bit 4, see
%% rom_slot/3). /RESET clears the register — a fresh state starts with
%% dos_rom = false, which is what makes the machine boot into its menu ROM
%% instead of straight into TR-DOS.
-spec write_port_1ffd(state(), byte()) -> state().
write_port_1ffd(#pmem{} = State, Value) ->
    set_dos_rom(State, (Value band 16#10) =/= 0).

-spec ram_banks(state()) -> 8 | 32 | 64.
ram_banks(#pmem{page_mask = Mask}) -> Mask + 1.

%% @doc Read the ULA display buffer (first ?VIDEO_SIZE bytes of the bank
%% selected by p7FFD bit 3), like the 128K backend.
-spec read_video_block(state()) -> binary().
read_video_block(#pmem{banks = Banks, p7ffd = P7ffd}) ->
    Bank = element(screen_slot(P7ffd), Banks),
    Full = [tuple_to_list(element(I, Bank)) || I <- lists:seq(1, ?VIDEO_FULL_PAGES)],
    Tail = lists:sublist(tuple_to_list(element(?VIDEO_FULL_PAGES + 1, Bank)),
                         ?VIDEO_TAIL),
    iolist_to_binary([Full| Tail]).

%% @doc Read a whole 16KB RAM bank (index within the wired RAM size) as a
%% binary. Used by snapshot save; banks beyond the model's RAM are ignored by
%% the callers' guards.
-spec read_bank_block(state(), non_neg_integer()) -> binary().
read_bank_block(#pmem{page_mask = Mask}, Bank) when Bank > Mask -> <<>>;
read_bank_block(#pmem{banks = Banks}, Bank) ->
    iolist_to_binary([page_to_binary(P) ||
                        P <- tuple_to_list(element(bank_element(Bank), Banks))]).

-spec write_bank_block(state(), non_neg_integer(), binary()) -> state().
write_bank_block(#pmem{page_mask = Mask} = State, Bank, _Data) when Bank > Mask ->
    State;
write_bank_block(#pmem{banks = Banks} = State, Bank, Data) ->
    NewBank = make_bank(pad(Data, ?BANK_SIZE)),
    State#pmem{banks = setelement(bank_element(Bank), Banks, NewBank)}.

%% --- internal ---

optional(undefined) -> <<>>;
optional(Bin) when is_binary(Bin) -> Bin.

ram_page_mask(8)  -> 16#07;
ram_page_mask(32) -> 16#1F;
ram_page_mask(64) -> 16#3F.

d5_is_page_bit(63, Eff7) -> (Eff7 band 16#04) =:= 0;
d5_is_page_bit(_, _) -> false.

bank_element(Bank) -> Bank + ?RAM_BASE_SLOT.

build_routing(#pmem{p7ffd = P7, eff7 = Eff7, dos_rom = Dos,
                    page_mask = Mask}) ->
    {rom_slot(P7, Eff7, Dos),
     %% The CPU window at #4000 is ALWAYS bank 5 — p7FFD bit 3 selects only
     %% the ULA display bank (read_video_block/1), like the 128K backend.
     bank_element(5),
     bank_element(2),
     bank_element(ram_page(P7, Eff7, Mask))}.

%% Bottom-16K source, highest priority first: all-RAM overlay, TR-DOS while
%% the Beta interface is latched (the hardware latch gates the chip select,
%% so it wins regardless of p7FFD bit 4), then the plain p7FFD bit 4
%% selection.
rom_slot(_P7, Eff7, _Dos) when (Eff7 band 16#08) =/= 0 ->
    bank_element(0);                                           %% all-RAM overlay
rom_slot(_P7, _Eff7, true) -> 3;                               %% TR-DOS
rom_slot(P7, _Eff7, _Dos) ->
    case (P7 band 16#10) =/= 0 of true -> 2; false -> 1 end.

%% ULA display bank element position (p7FFD bit 3: 0 = bank 5, 1 = bank 7).
screen_slot(P7ffd) -> bank_element(screen_bank(P7ffd)).

screen_bank(P7ffd) -> case (P7ffd bsr 3) band 1 of 0 -> 5; 1 -> 7 end.

%% Slot-3 RAM page: bits {D2,D1,D0} + {D7,D6}<<3, plus {D5}<<5 when the model
%% is a 1024K running in 1MB mode; finally clamped by the wired page count.
ram_page(P7, Eff7, Mask) ->
    Base = (P7 band 7) bor (((P7 bsr 6) band 3) bsl 3),
    case d5_is_page_bit(Mask, Eff7) of
        true  -> (Base bor (((P7 bsr 5) band 1) bsl 5)) band Mask;
        false -> Base band Mask
    end.

make_bank(Bin) -> list_to_tuple([byte_tuple(P) || P <- split_512(Bin)]).

byte_tuple(Bin) -> list_to_tuple(binary_to_list(Bin)).

page_to_binary(Page) -> list_to_binary(tuple_to_list(Page)).

split_512(<<>>) -> [];
split_512(Bin) ->
    <<Page:512/binary, Rest/binary>> = Bin,
    [Page | split_512(Rest)].

pad(Bin, Size) when byte_size(Bin) >= Size -> binary:part(Bin, 0, Size);
pad(Bin, Size) -> <<Bin/binary, 0:(Size - byte_size(Bin))/unit:8>>.
