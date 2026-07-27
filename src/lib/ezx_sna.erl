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
%% @end
-module(ezx_sna).

-include("sna.hrl").

-export([parse/1]).

-type sna_header() :: #sna_header{}.
-export_type([sna_header/0]).

%% @doc Parse a 48K SNA snapshot binary into a header record.
%%
%% Raises `bad_sna_header' if the binary is smaller than 49179 bytes.
-spec parse(binary()) -> sna_header().
parse(Data) when byte_size(Data) < 27 + 49152 ->
    error(bad_sna_header);
parse(Data) ->
    <<I:8,
      HLa:16/little, DEa:16/little, BCa:16/little, AFa:16/little,
      HL:16/little, DE:16/little, BC:16/little, IY:16/little, IX:16/little,
      IFF2:8, R:8,
      AF:16/little, SP:16/little,
      IM:8, Border:8,
      Mem:49152/bytes>> = Data,
    #sna_header{
        i = I, r = R,
        af = AF, bc = BC, de = DE, hl = HL,
        ix = IX, iy = IY,
        af_alt = AFa, bc_alt = BCa, de_alt = DEa, hl_alt = HLa,
        sp = SP, iff2 = IFF2, im = IM,
        border = Border,
        mem = Mem
    }.
