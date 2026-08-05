%% @doc ZX Spectrum Z80 snapshot format: parser and composer.
%%
%% This module is pure format: it only knows the on-disk Z80 layout and the
%% #z80_header{} record. parse/1 decodes a binary into the record and
%% compose/1 encodes the record back into a binary. The bridge between a
%% #machine_state{} and the record lives in ezx_saves.
%%
%% Supports v1 (PC non-zero), v2 (ExtraLen=23), and v3 (ExtraLen=54/55).
%% hw_mode 0/1 = 48K, 2/3 = 128K; 128K files carry their p7ffd in the
%% extended header.
%%
%% Header layout (30 bytes):
%%
%%   Offset  Size  Field
%%   ------  ----  -----
%%    0       1    A register
%%    1       1    F register
%%    2       2    BC (little-endian)
%%    4       2    HL (little-endian)
%%    6       2    PC (little-endian; zero ⇒ extended format)
%%    8       2    SP (little-endian)
%%   10       1    I register
%%   11       1    R register (low 7 bits; bit 7 is in the Flags byte)
%%   12       1    Flags: bit0=R7, bit5=1=compressed, bits[4:3]=border
%%   13       2    DE (little-endian)
%%   15       2    BC' (little-endian)
%%   17       2    DE' (little-endian)
%%   19       2    HL' (little-endian)
%%   21       1    A' register
%%   22       1    F' register
%%   23       2    IY (little-endian)
%%   25       2    IX (little-endian)
%%   27       1    IFF1
%%   28       1    IFF2
%%   29       1    IM (low 2 bits)
%%
%% Extended format (PC == 0, or any 128K file): the 30-byte header carries
%% PC=0, then follows a 2-byte little-endian length (23 for the layout
%% written here) and the extended header:
%%
%%   Offset  Size  Field
%%   ------  ----  -----
%%    0       2    PC (little-endian)
%%    2       1    Hardware mode (0 = 48K, 2 = 128K, 3 = 128K + AY)
%%    3       1    128K paging byte (p7FFD; 0 for 48K)
%%    4      19    Padding (zeros)
%%
%% After that come the memory blocks, each `FF FF <page> <16384 bytes>` for
%% the uncompressed layout written here. Page numbering follows libspectrum:
%% a 48K file uses pages 4 (0x8000), 5 (0xC000) and 8 (0x4000); a 128K file
%% uses pages 3-10 = RAM banks 0-7.
%%
%% RLE compression: ED ED <len> <byte> repeats byte len times.
%% End marker for v1: 00 ED ED 00. compose/1 always writes uncompressed data.
%% @end
-module(ezx_z80).

-include("z80.hrl").

-export([parse/1, compose/1]).

-type z80_header() :: #z80_header{}.
-export_type([z80_header/0]).

%% @doc Parse a Z80 snapshot binary into a header record.
%%
%% Detects v1 (PC≠0), v2 (ExtraLen=23), and v3 (ExtraLen=54/55).
%% Raises `bad_z80_header' if the binary is too short or malformed.
-spec parse(binary()) -> z80_header().
parse(Data) when byte_size(Data) < 30 ->
    error(bad_z80_header);
parse(<<A:8, F:8, BC:16/little, HL:16/little, PC:16/little, SP:16/little,
        I:8, R:8, Flags:8,
        DE:16/little, BCa:16/little, DEa:16/little, HLa:16/little,
        Aa:8, Fa:8, IY:16/little, IX:16/little,
        IFF1:8, IFF2:8, Misc:8, Rest/binary>>) ->
    Border = (Flags band 16#0E) bsr 1,
    R_bit7 = (Flags band 16#01) bsl 7,
    R1 = R bor R_bit7,
    IM = Misc band 16#03,
    Common = #z80_header{
        a = A, f = F,
        bc = BC, de = DE, hl = HL,
        pc = PC, sp = SP,
        i = I, r = R1,
        border = Border,
        bc_alt = BCa, de_alt = DEa, hl_alt = HLa,
        a_alt = Aa, f_alt = Fa,
        ix = IX, iy = IY,
        iff1 = IFF1, iff2 = IFF2,
        im = IM,
        p7ffd = 0,
        is_128k = false,
        pages = #{}
    },
    case PC of
        0 -> parse_v2v3(Common, Rest);
        _ -> parse_v1(Common, Flags, Rest)
    end.

%% --- Version 1 ---

%% @doc Parse a v1 Z80 snapshot body (PC != 0, no extended header).
%% Handles both uncompressed (49152 bytes) and RLE-compressed data.
-spec parse_v1(#z80_header{}, byte(), binary()) -> #z80_header{}.
parse_v1(#z80_header{} = H, Flags, Data) ->
    Compressed = (Flags band 16#20) =/= 0,
    case Compressed of
        false ->
            case byte_size(Data) of
                N when N < 49152 -> error(bad_z80_header);
                _ -> ok
            end,
            <<Mem:49152/bytes, _/binary>> = Data,
            H#z80_header{version = 1, hw_mode = 0, mem = Mem};
        true ->
            Mem = decompress(Data),
            H#z80_header{version = 1, hw_mode = 0, mem = Mem}
    end.

%% --- Versions 2 & 3 ---

%% @doc Parse a v2/v3 Z80 snapshot body (PC == 0, extended header present).
%% Determines version from ExtraLen (23 → v2, 54/55 → v3).
-spec parse_v2v3(#z80_header{}, binary()) -> #z80_header{}.
parse_v2v3(#z80_header{} = _H, Data) when byte_size(Data) < 2 ->
    error(bad_z80_header);
parse_v2v3(#z80_header{} = H, <<ExtraLen:16/little, Rest/binary>>) ->
    {H1, BlockData} = parse_extended(H, ExtraLen, Rest),
    Version = case ExtraLen of 23 -> 2; _ -> 3 end,
    Pages = parse_blocks(BlockData),
    Mem = build_48k_memory(Pages),
    Is128K = H1#z80_header.hw_mode >= 2,
    H1#z80_header{version = Version, is_128k = Is128K, mem = Mem, pages = Pages}.

%% @doc Parse the extended header section (v2/v3).
%% Extracts PC, hardware mode, and returns remaining block data.
%% Raises `{unsupported_z80_version, ExtraLen}' if data is too short.
-spec parse_extended(#z80_header{}, non_neg_integer(), binary()) -> {#z80_header{}, binary()}.
parse_extended(#z80_header{} = H, ExtraLen, Data) when byte_size(Data) >= ExtraLen ->
    <<PC:16/little, HwMode:8, P7ffd:8, _Padding:(ExtraLen - 4)/bytes, BlockData/binary>> = Data,
    {H#z80_header{pc = PC, hw_mode = HwMode, p7ffd = P7ffd}, BlockData};
parse_extended(_H, ExtraLen, _Data) ->
    error({unsupported_z80_version, ExtraLen}).

%% --- Memory blocks (v2/v3) ---

%% @doc Parse memory blocks into a page-number-to-data map.
%% Each block is either uncompressed (0xFFFF page marker) or RLE-compressed.
-spec parse_blocks(binary()) -> #{non_neg_integer() => binary()}.
parse_blocks(Rest) ->
    parse_blocks_1(Rest, #{}).

%% @doc Build aflat 48K binary from pages 4, 5, 8.
-spec build_48k_memory(#{non_neg_integer() => binary()}) -> binary().
build_48k_memory(Pages) ->
    Page4 = maps:get(4, Pages, <<0:16384/unit:8>>),
    Page5 = maps:get(5, Pages, <<0:16384/unit:8>>),
    Page8 = maps:get(8, Pages, <<0:16384/unit:8>>),
    <<Page8/binary, Page4/binary, Page5/binary>>.

%% @private
%% @doc Recursively parse memory blocks into a page-number-to-data map.
%% Handles both uncompressed (0xFFFF prefix) and compressed blocks.
-spec parse_blocks_1(binary(), #{non_neg_integer() => binary()}) -> #{non_neg_integer() => binary()}.
parse_blocks_1(<<>>, Pages) -> Pages;
parse_blocks_1(<<16#FF, 16#FF, Page, Data:16384/bytes, Rest/binary>>, Pages) ->
    parse_blocks_1(Rest, Pages#{Page => Data});
parse_blocks_1(<<CompLen:16/little, Page, Rest/binary>>, Pages) ->
    <<CompData:CompLen/binary, Rest1/binary>> = Rest,
    Data = decompress_block(CompData),
    parse_blocks_1(Rest1, Pages#{Page => Data}).

%% --- RLE Decompression ---

%% @doc Decompress a v1 data block into a 49152-byte memory image.
%% RLE: ED ED <len> <byte> repeats byte len times. End marker: 00 ED ED 00.
-spec decompress(binary()) -> binary().
decompress(Data) ->
    {Result, _} = decompress_until_end(Data, <<>>),
    case byte_size(Result) of
        N when N >= 49152 ->
            <<Mem:49152/bytes, _/binary>> = Result,
            Mem;
        _ ->
            error(bad_z80_header)
    end.

%% @private
%% @doc Decompress RLE data until end marker or exhaustion.
%% Returns {decompressed_binary, remaining_input}.
%% Handles: end marker 00 ED ED 00, literal ED escape, RLE ED ED <len> <byte>.
-spec decompress_until_end(binary(), binary()) -> {binary(), binary()}.
decompress_until_end(<<>>, Acc) -> {Acc, <<>>};
decompress_until_end(<<16#00, 16#ED, 16#ED, 16#00, Rest/binary>>, Acc) -> {Acc, Rest};
decompress_until_end(<<16#ED, 16#00, 16#ED, 16#ED, 16#00, Rest/binary>>, Acc) ->
    {<<Acc/binary, 16#ED>>, Rest};
decompress_until_end(<<16#ED, 16#ED, Len, Byte, Rest/binary>>, Acc) ->
    Block = << <<Byte>> || _ <- lists:seq(1, Len) >>,
    decompress_until_end(Rest, <<Acc/binary, Block/binary>>);
decompress_until_end(<<16#ED, Byte, Rest/binary>>, Acc) ->
    decompress_until_end(Rest, <<Acc/binary, 16#ED, Byte>>);
decompress_until_end(<<Byte, Rest/binary>>, Acc) ->
    decompress_until_end(Rest, <<Acc/binary, Byte>>).

%% @private
%% @doc Decompress a single v2/v3 block (no end marker, size-bounded).
-spec decompress_block(binary()) -> binary().
decompress_block(Data) ->
    decompress_block_n(Data, byte_size(Data), <<>>).

%% @private
%% @doc Decompress block data by consuming N input bytes.
%% Tracks remaining input length; no end-marker detection.
-spec decompress_block_n(binary(), non_neg_integer(), binary()) -> binary().
decompress_block_n(<<>>, 0, Acc) -> Acc;
decompress_block_n(<<16#ED, 16#ED, Len, Byte, Rest/binary>>, N, Acc) when N >= 4 ->
    Block = << <<Byte>> || _ <- lists:seq(1, Len) >>,
    decompress_block_n(Rest, N - 4, <<Acc/binary, Block/binary>>);
decompress_block_n(<<16#ED, Byte, Rest/binary>>, N, Acc) when N >= 2 ->
    decompress_block_n(Rest, N - 2, <<Acc/binary, 16#ED, Byte>>);
decompress_block_n(<<Byte, Rest/binary>>, N, Acc) when N >= 1 ->
    decompress_block_n(Rest, N - 1, <<Acc/binary, Byte>>).

%% @doc Serialize a #z80_header{} record into a Z80 snapshot binary.
%%
%% Always writes uncompressed data. A 48K snapshot with PC != 0 becomes a
%% v1 file (30-byte header + the 49152-byte image). A 48K snapshot with
%% PC == 0, and every 128K snapshot, use the extended format: header PC=0,
%% the 2-byte length, the extended header (real PC, hw_mode, p7ffd) and the
%% page blocks from the record's pages map. The inverse of parse/1 in the
%% sense that compose(to_header from ezx_saves) reloads to the same state.
-spec compose(z80_header()) -> binary().
compose(#z80_header{is_128k = false, pc = PC} = H) when PC =/= 0 ->
    <<(base_header(H))/binary, (H#z80_header.mem)/binary>>;
compose(#z80_header{pc = PC} = H) when is_integer(PC) ->
    Base = base_header(H#z80_header{pc = 0}),
    Ext = <<PC:16/little,
            (H#z80_header.hw_mode):8,
            (H#z80_header.p7ffd):8,
            0:19/unit:8>>,
    <<Base/binary, 23:16/little, Ext/binary, (blocks(H))/binary>>.

%% @private The 30-byte base header. R's bit 7 and the border color ride in
%% the Flags byte; IM is stored masked to its low 2 bits.
base_header(#z80_header{a = A, f = F, bc = BC, hl = HL, pc = PC, sp = SP,
                        i = I, r = R, border = Border,
                        de = DE, bc_alt = BCa, de_alt = DEa, hl_alt = HLa,
                        a_alt = Aa, f_alt = Fa, iy = IY, ix = IX,
                        iff1 = IFF1, iff2 = IFF2, im = IM}) ->
    R7 = (R band 16#80) bsr 7,
    Flags = R7 bor ((Border band 16#07) bsl 1),
    <<A:8, F:8, BC:16/little, HL:16/little, PC:16/little, SP:16/little,
      I:8, (R band 16#7F):8, Flags:8,
      DE:16/little, BCa:16/little, DEa:16/little, HLa:16/little,
      Aa:8, Fa:8, IY:16/little, IX:16/little,
      IFF1:8, IFF2:8, (IM band 16#03):8>>.

%% @private The memory blocks, one per page, in ascending page order. The
%% uncompressed form is a literal `FF FF <page> <16384 bytes>' prefix.
blocks(#z80_header{pages = Pages}) ->
    Sorted = lists:sort(maps:to_list(Pages)),
    iolist_to_binary([<<16#FF, 16#FF, Page, Data:16384/bytes>>
                      || {Page, Data} <- Sorted]).
