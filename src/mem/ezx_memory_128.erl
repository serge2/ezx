-module(ezx_memory_128).

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

-record(mem128, {
    ram  :: binary(),
    rom0 :: binary(),
    rom1 :: binary(),
    p7ffd :: byte()
}).

-opaque state() :: #mem128{}.
-export_type([state/0]).

%% @doc 128K memory backend: binary slice of 8 RAM banks + 2 ROMs.
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
%% The CPU view is exposed via read_byte/read_block/write_byte; the display
%% bank (5 or 7 per bit 3) is exposed separately via read_video_block/2.
%% @end

-define(ROM0_IDX, 0).
-define(ROM1_IDX, 1).
-define(BANK_SIZE, 16384).

-spec new(binary(), binary()) -> state().
new(Rom0, Rom1) ->
    Ram = <<0:(8 * ?BANK_SIZE)/unit:8>>,
    R0 = pad_16k(Rom0),
    R1 = pad_16k(Rom1),
    #mem128{ram = Ram, rom0 = R0, rom1 = R1, p7ffd = 0}.

pad_16k(Bin) when byte_size(Bin) >= ?BANK_SIZE -> binary:part(Bin, 0, ?BANK_SIZE);
pad_16k(Bin) -> <<Bin/binary, 0:(?BANK_SIZE - byte_size(Bin))/unit:8>>.

-spec read_byte(state(), non_neg_integer()) -> byte().
read_byte(#mem128{ram = Ram, rom0 = R0, rom1 = R1, p7ffd = P}, Addr) ->
    Slot = Addr band 16#C000,
    Off = Addr band 16#3FFF,
    case Slot of
        16#0000 ->
            case (P bsr 4) band 1 of
                0 -> binary:at(R0, Off);
                1 -> binary:at(R1, Off)
            end;
        16#4000 ->
            binary:at(Ram, 5 * ?BANK_SIZE + Off);
        16#8000 ->
            binary:at(Ram, 2 * ?BANK_SIZE + Off);
        16#C000 ->
            binary:at(Ram, (P band 16#07) * ?BANK_SIZE + Off)
    end.

-spec read_block(state(), non_neg_integer(), non_neg_integer()) -> binary().
read_block(State, Addr, Size) ->
    read_block_1(State, Addr band 16#FFFF, Size, <<>>).

read_block_1(_State, _Addr, 0, Acc) -> Acc;
read_block_1(State, Addr, Remaining, Acc) ->
    Slot = Addr band 16#C000,
    Off = Addr band 16#3FFF,
    Available = ?BANK_SIZE - Off,
    Take = min(Remaining, Available),
    Chunk = case Slot of
        16#0000 -> read_rom_chunk(State, Off, Take);
        16#4000 -> read_ram_chunk(State, 5, Off, Take);
        16#8000 -> read_ram_chunk(State, 2, Off, Take);
        16#C000 -> read_ram_chunk(State, slot3_bank(State), Off, Take)
    end,
    read_block_1(State, (Addr + Take) band 16#FFFF, Remaining - Take, <<Acc/binary, Chunk/binary>>).

-spec write_byte(state(), non_neg_integer(), byte()) -> state().
write_byte(#mem128{ram = Ram, p7ffd = P} = State, Addr, Byte) ->
    Slot = Addr band 16#C000,
    Off = Addr band 16#3FFF,
    case Slot of
        16#0000 -> State;
        16#4000 ->
            State#mem128{ram = write_at(Ram, 5 * ?BANK_SIZE + Off, Byte)};
        16#8000 ->
            State#mem128{ram = write_at(Ram, 2 * ?BANK_SIZE + Off, Byte)};
        16#C000 ->
            State#mem128{ram = write_at(Ram, (P band 16#07) * ?BANK_SIZE + Off, Byte)}
    end.

-spec write_port_7ffd(state(), byte()) -> state().
write_port_7ffd(#mem128{} = State, Value) ->
    State#mem128{p7ffd = Value band 16#FF}.

%% @doc Read the display (ULA video) buffer. p7FFD bit 3 selects whether the
%% screen is drawn from bank 5 or bank 7, independently of the CPU's 0x4000
%% mapping (which is always bank 5). `Size' must not exceed 16384.
-spec read_video_block(state(), non_neg_integer()) -> binary().
read_video_block(#mem128{ram = Ram} = State, Size) ->
    binary:part(Ram, screen_bank(State) * ?BANK_SIZE, Size).

-spec get_p7ffd(state()) -> byte().
get_p7ffd(#mem128{p7ffd = P}) -> P.

%% @doc Write a 16384-byte block into a specific RAM bank.
-spec write_bank_block(state(), non_neg_integer(), binary()) -> state().
write_bank_block(#mem128{ram = Ram} = State, Bank, Data) when byte_size(Data) =< ?BANK_SIZE ->
    Off = Bank * ?BANK_SIZE,
    PadSize = ?BANK_SIZE - byte_size(Data),
    Data1 = case PadSize of 0 -> Data; _ -> <<Data/binary, 0:PadSize/unit:8>> end,
    <<Prefix:Off/binary, _Old:?BANK_SIZE/binary, Suffix/binary>> = Ram,
    State#mem128{ram = <<Prefix/binary, Data1/binary, Suffix/binary>>}.

%% --- internal ---

read_rom_chunk(#mem128{rom0 = R0, rom1 = R1, p7ffd = P}, Off, Take) ->
    Rom = case (P bsr 4) band 1 of 0 -> R0; 1 -> R1 end,
    binary:part(Rom, Off, Take).

read_ram_chunk(#mem128{ram = Ram}, Bank, Off, Take) ->
    binary:part(Ram, Bank * ?BANK_SIZE + Off, Take).

screen_bank(#mem128{p7ffd = P}) ->
    case (P bsr 3) band 1 of 0 -> 5; 1 -> 7 end.

slot3_bank(#mem128{p7ffd = P}) ->
    P band 16#07.

write_at(Ram, Offset, Byte) ->
    <<Prefix:Offset/binary, _Old:8, Suffix/binary>> = Ram,
    <<Prefix/binary, Byte:8, Suffix/binary>>.
