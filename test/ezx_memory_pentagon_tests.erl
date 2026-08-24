-module(ezx_memory_pentagon_tests).

-include_lib("eunit/include/eunit.hrl").

%% Tests for the Pentagon memory backend. The three models share the module
%% and differ only in the wired RAM size (8 / 32 / 64 banks) and which paging
%% bits the page mask lets through.

-define(R0, binary:copy(<<16#11>>, 16384)).
-define(R1, binary:copy(<<16#22>>, 16384)).

new_128(Mods) -> Mods:new({?R0, ?R1, undefined}, 8).
new_512(Mods) -> Mods:new({?R0, ?R1, undefined}, 32).
new_1024(Mods) -> Mods:new({?R0, ?R1, undefined}, 64).

%% The bottom-16K source follows p7FFD bit 4; ROM0 is element-mapped at reset.
rom_select_test() ->
    S = new_128(ezx_memory_pentagon),
    ?assertEqual(16#11, ezx_memory_pentagon:read_byte(S, 0)),
    S1 = ezx_memory_pentagon:write_port_7ffd(S, 16#10),
    ?assertEqual(16#22, ezx_memory_pentagon:read_byte(S1, 0)),
    ?assertEqual(16#22, ezx_memory_pentagon:read_byte(S1, 16#3FFF)).

%% 0x4000-0x7FFF is always bank 5 for the CPU, bit 3 selects the ULA display
%% bank — same contract as the 128K backends (see ezx_memory_128_tests).
cpu_view_4000_always_bank5_test() ->
    S = new_128(ezx_memory_pentagon),
    S1 = ezx_memory_pentagon:write_byte(S, 16#4000, 16#AA),
    S2 = ezx_memory_pentagon:write_port_7ffd(S1, 16#18),   %% display = 7
    VB7 = ezx_memory_pentagon:read_video_block(S2),
    ?assertEqual(16#00, binary:at(VB7, 0)),
    S3 = ezx_memory_pentagon:write_port_7ffd(S2, 16#10),   %% display = 5
    ?assertEqual(16#AA, binary:at(ezx_memory_pentagon:read_video_block(S3), 0)).

%% Pentagon extension: p7FFD bits 6-7 are RAM page bits 3-4. On a 512K
%% machine they select pages 8-31; on a 128K machine the mask drops them.
extended_page_bits_test() ->
    %% 512K: write a marker into every wired page via slot 3.
    S512 = new_512(ezx_memory_pentagon),
    S512b = lists:foldl(fun(Page, Acc) ->
        P7 = (Page band 16#07) bor ((Page bsr 3) bsl 6),
        A1 = ezx_memory_pentagon:write_port_7ffd(Acc, P7),
        ezx_memory_pentagon:write_byte(A1, 16#C000, Page + 16#40)
    end, S512, lists:seq(0, 31)),
    lists:foreach(fun(Page) ->
        P7 = (Page band 16#07) bor ((Page bsr 3) bsl 6),
        S = ezx_memory_pentagon:write_port_7ffd(S512b, P7),
        ?assertEqual(Page + 16#40, ezx_memory_pentagon:read_byte(S, 16#C000))
    end, lists:seq(0, 31)),
    ?assertEqual(32, ezx_memory_pentagon:ram_banks(S512b)),

    %% 128K: bits 6-7 are masked off — page 8 (P7 = 16#48) reads as page 0.
    S128 = new_128(ezx_memory_pentagon),
    S1 = ezx_memory_pentagon:write_byte(S128, 16#C000, 16#77),
    S2 = ezx_memory_pentagon:write_port_7ffd(S1, 16#48),
    ?assertEqual(16#77, ezx_memory_pentagon:read_byte(S2, 16#C000)).

%% 1024K in 1MB mode (#EFF7 bit 2 clear): bit 5 of #7FFD becomes RAM page
%% bit 5 and no longer locks the port; #EFF7 writes are ignored on smaller
%% models.
eff7_1024_mode_test() ->
    S = new_1024(ezx_memory_pentagon),
    %% Enter 1MB mode and select page 33 = {D5=1} + {bits6-7=0} + {bits0-2=1}.
    S1 = ezx_memory_pentagon:write_port_eff7(S, 16#00),
    S2 = ezx_memory_pentagon:write_port_7ffd(S1, 16#20 bor 16#01),
    S2b = ezx_memory_pentagon:write_byte(S2, 16#C000, 16#EE),
    S3 = ezx_memory_pentagon:write_port_7ffd(S2b, 16#02),   %% page 2
    ?assertEqual(16#00, ezx_memory_pentagon:read_byte(S3, 16#C000)),
    S4 = ezx_memory_pentagon:write_port_7ffd(S3, 16#21),   %% page 33 again
    ?assertEqual(16#EE, ezx_memory_pentagon:read_byte(S4, 16#C000)),
    ?assertEqual(16#EE, binary:at(ezx_memory_pentagon:read_bank_block(S4, 33), 0)),

    %% Back to standard mode: D5 is the lock again, pages clamp to 0-31.
    S5 = ezx_memory_pentagon:write_port_eff7(S4, 16#04),
    S6 = ezx_memory_pentagon:write_port_7ffd(S5, 16#20 bor 16#01),
    ?assertEqual((16#20 bor 16#01), ezx_memory_pentagon:get_p7ffd(S6)),
    ?assertEqual(16#00, ezx_memory_pentagon:read_byte(S6, 16#C000)),  %% page 1, not 33
    S7 = ezx_memory_pentagon:write_port_7ffd(S6, 16#00),
    ?assertEqual((16#20 bor 16#01), ezx_memory_pentagon:get_p7ffd(S7)).  %% locked

%% The all-RAM overlay (#EFF7 bit 3) maps RAM bank 0 over the bottom 16K,
%% overriding both the ROM select and the TR-DOS overlay.
eff7_all_ram_overlay_test() ->
    RomDos = binary:copy(<<16#33>>, 16384),
    S = ezx_memory_pentagon:new({?R0, ?R1, RomDos}, 64),
    %% TR-DOS active would normally show 0x33 at 0x0000...
    S1 = ezx_memory_pentagon:set_dos_rom(S, true),
    ?assertEqual(16#33, ezx_memory_pentagon:read_byte(S1, 0)),
    %% ...but bank 0 written via slot 3 wins once the overlay is enabled.
    S2 = ezx_memory_pentagon:write_byte(S1, 16#C000, 16#99),
    S3 = ezx_memory_pentagon:write_port_eff7(S2, 16#04 bor 16#08),
    ?assertEqual(16#99, ezx_memory_pentagon:read_byte(S3, 0)).

%% TR-DOS overlay: while the Beta interface is latched, TR-DOS wins the
%% bottom 16K regardless of p7FFD bit 4 (the hardware latch gates the chip
%% select); clearing the latch falls back to the bit 4 selection.
dos_rom_overlay_test() ->
    RomDos = binary:copy(<<16#33>>, 16384),
    S = ezx_memory_pentagon:new({?R0, ?R1, RomDos}, 8),
    S1 = ezx_memory_pentagon:set_dos_rom(S, true),
    ?assertEqual(16#33, ezx_memory_pentagon:read_byte(S1, 0)),
    S2 = ezx_memory_pentagon:write_port_7ffd(S1, 16#10),   %% bit 4 set: DOS still wins
    ?assertEqual(16#33, ezx_memory_pentagon:read_byte(S2, 0)),
    S3 = ezx_memory_pentagon:write_port_7ffd(S2, 16#00),
    ?assertEqual(16#33, ezx_memory_pentagon:read_byte(S3, 0)),
    S4 = ezx_memory_pentagon:set_dos_rom(S3, false),       %% latch off -> bit 4 clear -> ROM0
    ?assertEqual(16#11, ezx_memory_pentagon:read_byte(S4, 0)).

%% Data reads never toggle the interface: fetching outside the window with
%% bit 4 clear leaves the mapping alone.
magic_window_no_toggle_test() ->
    RomDos = binary:copy(<<16#33>>, 16384),
    S = ezx_memory_pentagon:new({?R0, ?R1, RomDos}, 8),
    S1 = ezx_memory_pentagon:write_port_7ffd(S, 16#10),
    ?assertEqual(16#22, ezx_memory_pentagon:read_byte(S1, 16#3D00)),
    {16#22, S2} = ezx_memory_pentagon:read_opcode(S1, 16#0100),
    ?assertEqual(16#22, ezx_memory_pentagon:read_byte(S2, 0)).

magic_window_enable_test() ->
    RomDos = binary:copy(<<16#33>>, 16384),
    S = ezx_memory_pentagon:new({?R0, ?R1, RomDos}, 8),
    S1 = ezx_memory_pentagon:write_port_7ffd(S, 16#10),   %% 48 BASIC paged in
    %% Opcode fetch inside the window engages the overlay and the fetch
    %% itself already reads through it.
    ?assertEqual(16#22, ezx_memory_pentagon:read_byte(S1, 16#3D00)),
    {16#33, S2} = ezx_memory_pentagon:read_opcode(S1, 16#3D00),
    ?assertEqual(16#33, ezx_memory_pentagon:read_byte(S2, 0)),
    %% An opcode fetch above #4000 disengages again; the fetch reads RAM
    %% (#8000 = bank 2) and with bit 4 still set the bottom 16K falls back
    %% to 48 BASIC.
    {16#00, S3} = ezx_memory_pentagon:read_opcode(S2, 16#8000),
    ?assertEqual(16#22, ezx_memory_pentagon:read_byte(S3, 0)),
    %% And once disengaged, a window fetch re-engages.
    {16#33, S4} = ezx_memory_pentagon:read_opcode(S3, 16#3D10),
    ?assertEqual(16#33, ezx_memory_pentagon:read_byte(S4, 0)).

%% Bit 5 locks the port on 128K/512K machines: the locking write still
%% applies, later ones are ignored until a fresh state.
p7ffd_lock_test() ->
    S = new_512(ezx_memory_pentagon),
    S1 = ezx_memory_pentagon:write_port_7ffd(S, 16#05 bor 16#20),
    ?assertEqual((16#05 bor 16#20), ezx_memory_pentagon:get_p7ffd(S1)),
    S2 = ezx_memory_pentagon:write_port_7ffd(S1, 16#00),
    ?assertEqual((16#05 bor 16#20), ezx_memory_pentagon:get_p7ffd(S2)).

%% read_block/3 spans page boundaries across the routed banks.
read_block_test() ->
    S = new_128(ezx_memory_pentagon),
    S1 = ezx_memory_pentagon:write_byte(S, 16#BFFF, 16#AA),
    S2 = ezx_memory_pentagon:write_byte(S1, 16#C000, 16#BB),
    Block = ezx_memory_pentagon:read_block(S2, 16#BFFE, 4),
    ?assertEqual(<<0, 16#AA, 16#BB, 0>>, Block).

%% Bank blocks round-trip for the whole wired RAM of each model.
bank_blocks_roundtrip_test_() ->
    [{lists:flatten(io_lib:format("~p_banks", [N])),
      fun() -> bank_blocks_roundtrip(N) end}
     || N <- [8, 32, 64]].

bank_blocks_roundtrip(Banks) ->
    M = ezx_memory_pentagon,
    S0 = M:new({?R0, ?R1, undefined}, Banks),
    S1 = lists:foldl(fun(B, Acc) -> M:write_bank_block(Acc, B, <<B:8>>) end,
                     S0, lists:seq(0, Banks - 1)),
    lists:foreach(fun(B) ->
        ?assertEqual(B, binary:at(M:read_bank_block(S1, B), 0))
    end, lists:seq(0, Banks - 1)),
    %% Out-of-range bank accesses are ignored / empty.
    ?assertEqual(<<>>, M:read_bank_block(S1, Banks)),
    ?assertEqual(S1, M:write_bank_block(S1, Banks, <<16#FF>>)).
