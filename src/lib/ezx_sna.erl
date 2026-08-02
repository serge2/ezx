%% @doc ZX Spectrum SNA file format parser.
%%
%% SNA (Snapshot) format captures the full state of a 48K Spectrum.
%% Total file size: 27 bytes header + 49152 bytes (48K RAM starting at 0x4000).
%%
%% Header layout (27 bytes):
%%
%%   Offset  Size  Field
%%   ------  ----  -----
%%    0       1    I register
%%    1       2    HL' (shadow HL, little-endian)
%%    3       2    DE' (shadow DE)
%%    5       2    BC' (shadow BC)
%%    7       2    AF' (shadow AF)
%%    9       2    HL
%%   11       2    DE
%%   13       2    BC
%%   15       2    IY
%%   17       2    IX
%%   19       1    IFF2 (interrupt flip-flop 2)
%%   20       1    R register
%%   21       2    AF (little-endian)
%%   23       2    SP
%%   25       1    IM mode (0, 1, or 2)
%%   26       1    Border color (0-7)
%%
%% RAM data (49152 bytes):
%%   Bytes 27..49178 contain 48K of RAM from address 0x4000 to 0xBFFF.
%%
%% On load, the emulator reads the return address from [SP] to set PC.
%%
%% 128K extended SNA (used by e.g. Fuse):
%%   The 48KB dump holds the CPU view: bank 5 at 0x4000 (fixed, independent
%%   of p7FFD bit 3), bank 2 at 0x8000, and the slot 3 bank at 0xC000.
%%   After 49152 bytes of RAM:
%%     4 bytes extended header: PC (le), p7FFD, AY flag
%%     5 x 16384 bytes extra pages (the remaining banks, ascending order;
%%     the display bank 5 or 7 per p7FFD bit 3 is among them)
%%
%% @end
-module(ezx_sna).

-include("sna.hrl").

-export([parse/1]).

-type sna_header() :: #sna_header{}.
-export_type([sna_header/0]).

-define(STANDARD_SIZE, 27 + 49152).

%% @doc Parse a SNA snapshot binary into a header record.
%%
%% Returns `#sna_header{is_128k = false}' for standard 48K SNA,
%% `#sna_header{is_128k = true}' for 128K extended SNA.
%% Raises `bad_sna_header' if the binary is smaller than 49179 bytes.
-spec parse(binary()) -> sna_header().
parse(Data) when byte_size(Data) < ?STANDARD_SIZE ->
    error(bad_sna_header);
parse(Data) ->
    <<I:8,
      HLa:16/little, DEa:16/little, BCa:16/little, AFa:16/little,
      HL:16/little, DE:16/little, BC:16/little, IY:16/little, IX:16/little,
      IFF2:8, R:8,
      AF:16/little, SP:16/little,
      IM:8, BorderRaw:8,
      Mem:49152/bytes, Rest/bytes>> = Data,
    Header = #sna_header{
        i = I, r = R,
        af = AF, bc = BC, de = DE, hl = HL,
        ix = IX, iy = IY,
        af_alt = AFa, bc_alt = BCa, de_alt = DEa, hl_alt = HLa,
        sp = SP, iff2 = IFF2, im = IM,
        border = BorderRaw band 16#07,
        mem = Mem,
        is_128k = false
    },
    parse_extended(Header, Rest).

%% @private
parse_extended(Header, <<>>) ->
    Header;
parse_extended(Header, <<PCL:8, PCH:8, P7FFD:8, AYFlag:8, Extra/binary>>)
  when byte_size(Extra) >= 5 * 16384 ->
    PC = (PCH bsl 8) bor PCL,
    Header#sna_header{is_128k = true, pc = PC, p7ffd = P7FFD, ay_flag = AYFlag, raw_extra = Extra};
parse_extended(Header, _Rest) ->
    Header.
