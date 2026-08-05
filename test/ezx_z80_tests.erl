-module(ezx_z80_tests).

-include("lib/z80.hrl").
-include_lib("eunit/include/eunit.hrl").

%% Round-trip through compose/parse with data that exercises every corner of
%% the RLE encoder: runs below/at/above the coding thresholds, runs of 0xED,
%% runs longer than 255 (the count-byte cap), literal ED bytes in every
%% position, and the spec's own example.

v1_round_trip_test() ->
    Mem = mem(49152),
    H = (header())#z80_header{pc = 16#8000, hw_mode = 0, mem = Mem},
    Bin = ezx_z80:compose(H),
    %% The sparse memory compresses, so the v1 file shrinks below the raw
    %% 30-byte header + 49152-byte image.
    ?assert(byte_size(Bin) < 30 + 49152),
    ?assertEqual(1, (binary:at(Bin, 12) band 16#20) bsr 5),
    Parsed = ezx_z80:parse(Bin),
    ?assertEqual(Mem, Parsed#z80_header.mem),
    ?assertEqual(16#8000, Parsed#z80_header.pc).

extended_round_trip_test() ->
    Pages = #{8 => page(0), 4 => page(1), 5 => page(2)},
    H = (header())#z80_header{pc = 0, hw_mode = 0, pages = Pages},
    Bin = ezx_z80:compose(H),
    ?assert(byte_size(Bin) < 30 + 2 + 23 + 3 * 16387),
    Parsed = ezx_z80:parse(Bin),
    ?assertEqual(Pages, Parsed#z80_header.pages),
    ?assertEqual(0, Parsed#z80_header.pc).

fill_page_round_trip_test() ->
    %% A single repeating byte: run tokens all the way through.
    Data = <<16#A5:16384/unit:8>>,
    H = (header())#z80_header{pc = 0, pages = #{8 => Data, 4 => Data, 5 => Data}},
    Bin = ezx_z80:compose(H),
    ?assert(byte_size(Bin) < 30 + 2 + 23 + 3 * 16387),
    ?assertEqual(H#z80_header.pages, (ezx_z80:parse(Bin))#z80_header.pages).

ed_fill_round_trip_test() ->
    %% A full page of 0xED: long ED runs that must split at the 255 cap and
    %% never leave a bare ED between markers.
    Data = <<16#ED:16384/unit:8>>,
    H = (header())#z80_header{pc = 0, pages = #{8 => Data, 4 => Data, 5 => Data}},
    Bin = ezx_z80:compose(H),
    ?assert(byte_size(Bin) < 30 + 2 + 23 + 3 * 16387),
    ?assertEqual(H#z80_header.pages, (ezx_z80:parse(Bin))#z80_header.pages).

incompressible_falls_back_test() ->
    %% No repeats and no equal neighbours: RLE cannot shrink the data, so the
    %% blocks fall back to the raw FF FF <page> <16384 bytes> form.
    Data = distinct(16384),
    H = (header())#z80_header{pc = 0, pages = #{8 => Data, 4 => Data, 5 => Data}},
    Bin = ezx_z80:compose(H),
    ?assertEqual(30 + 2 + 23 + 3 * 16387, byte_size(Bin)),
    ?assertEqual(H#z80_header.pages, (ezx_z80:parse(Bin))#z80_header.pages).

%% --- helpers ---

header() ->
    #z80_header{
        a = 16#11, f = 16#22, bc = 16#3344, de = 16#5566, hl = 16#7788,
        sp = 16#A000, i = 16#75, r = 16#86, border = 3,
        bc_alt = 16#BB, de_alt = 16#DD, hl_alt = 16#10, a_alt = 16#99,
        f_alt = 16#AA, ix = 16#3142, iy = 16#5364, iff1 = 1, iff2 = 0,
        im = 2, hw_mode = 0, p7ffd = 0, is_128k = false,
        mem = <<>>, pages = #{}}.

%% A byte sequence that hits every RLE branch: literal single bytes, a run of
%% 4 (below the 5-byte threshold), a run of 5 (coded), a run of 300 (split at
%% the 255 cap), single/twin/five/300 0xED runs, the spec example ED followed
%% by six zeros, an ED-run next to a repeatable byte, an ED escape, and a
%% trailing lone ED at the very end of the block.
tricky() ->
    iolist_to_binary([
        <<16#01>>,
        <<16#02:4/unit:8>>,
        <<16#03:5/unit:8>>,
        <<16#04:300/unit:8>>,
        <<16#ED>>,                       %% lone ED mid-data
        <<16#ED, 16#ED>>,                %% ED run of 2
        <<16#ED:5/unit:8>>,              %% ED run of 5
        <<16#ED:300/unit:8>>,            %% ED run split at the cap
        <<16#ED, 0:6/unit:8>>,           %% spec: ED followed by six zeros
        <<16#12, 16#34, 16#56>>,
        <<16#ED, 16#ED, 16#00>>,         %% ED run of 2 next to a repeatable
        <<16#ED, 16#AB>>,                %% ED escape
        <<16#ED>>                        %% trailing lone ED
    ]).

page(Offset) ->
    Seg = tricky(),
    SegLen = byte_size(Seg),
    Times = 16384 div SegLen,
    Pad = 16384 - Times * SegLen,
    Data = <<(binary:copy(Seg, Times))/binary, 0:(Pad * 8)>>,
    xor_bytes(Data, Offset).

mem(N) ->
    Seg = tricky(),
    SegLen = byte_size(Seg),
    Times = N div SegLen,
    Pad = N - Times * SegLen,
    Data = <<(binary:copy(Seg, Times))/binary, 0:(Pad * 8)>>,
    xor_bytes(Data, 7).

xor_bytes(Bin, 0) -> Bin;
xor_bytes(Bin, N) ->
    << <<(B bxor N):8>> || <<B>> <= Bin >>.

%% 1..251 repeating: no equal neighbours (a lone 0xED at value 237 is handled
%% by the escape and adds no bytes), so RLE has nothing to encode.
distinct(N) ->
    Cycle = << <<B:8>> || B <- lists:seq(1, 251) >>,
    Times = N div 251,
    Pad = N - Times * 251,
    <<(binary:copy(Cycle, Times))/binary, (binary:part(Cycle, 0, Pad))/binary>>.
