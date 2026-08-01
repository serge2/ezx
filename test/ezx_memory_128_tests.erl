-module(ezx_memory_128_tests).

-include_lib("eunit/include/eunit.hrl").

%% The two 128K backends must agree on the 0x7FFD paging semantics:
%% 0x4000-0x7FFF is always bank 5 for the CPU; bit 3 only selects the bank
%% (5 or 7) that read_video_block/2 returns for the ULA display.
-define(MODULES, [ezx_memory_128, ezx_memory_128_pages512]).

cpu_view_4000_always_bank5_test_() ->
    [{lists:flatten(io_lib:format("~p", [Mod])),
      fun() -> cpu_view_4000_always_bank5(Mod) end}
     || Mod <- ?MODULES].

cpu_view_4000_always_bank5(Mod) ->
    Rom0 = binary:copy(<<16#11>>, 16384),
    Rom1 = binary:copy(<<16#22>>, 16384),
    S0 = Mod:new(Rom0, Rom1),

    %% Writes at 0x4000-0x7FFF land in bank 5.
    S1 = Mod:write_byte(S0, 16#4000, 16#AA),
    S2 = Mod:write_byte(S1, 16#7FFF, 16#BB),

    %% Screen bit 3 set (display bank 7), slot 3 = 0, ROM1.
    S3 = Mod:write_port_7ffd(S2, 16#18),
    ?assertEqual(16#AA, Mod:read_byte(S3, 16#4000)),
    ?assertEqual(16#BB, Mod:read_byte(S3, 16#7FFF)),
    ?assertEqual(16#22, Mod:read_byte(S3, 16#0000)),

    %% The display bank is now 7: bank 5's content is not what is shown.
    VB7 = Mod:read_video_block(S3, 16#4000),
    ?assertEqual(16#00, binary:at(VB7, 0)),
    ?assertEqual(16#00, binary:at(VB7, 16#3FFF)),

    %% Selecting bank 5 for display brings back the CPU-written bytes.
    S4 = Mod:write_port_7ffd(S3, 16#10),
    VB5 = Mod:read_video_block(S4, 16#4000),
    ?assertEqual(16#AA, binary:at(VB5, 0)),
    ?assertEqual(16#BB, binary:at(VB5, 16#3FFF)).

display_bank_written_via_slot3_test_() ->
    [{lists:flatten(io_lib:format("~p", [Mod])),
      fun() -> display_bank_written_via_slot3(Mod) end}
     || Mod <- ?MODULES].

display_bank_written_via_slot3(Mod) ->
    Rom = <<0:16384/unit:8>>,
    S0 = Mod:new(Rom, Rom),

    %% CPU writes while the display is bank 7 must not touch bank 7.
    S1 = Mod:write_port_7ffd(S0, 16#18),
    S2 = Mod:write_byte(S1, 16#4000, 16#AA),
    ?assertEqual(16#00, binary:at(Mod:read_video_block(S2, 16384), 0)),

    %% Bank 7 is reachable by paging it into slot 3 (0xC000).
    S3 = Mod:write_port_7ffd(S2, 16#07),  %% slot 3 = 7, display = 5
    S4 = Mod:write_byte(S3, 16#C000, 16#CC),
    S5 = Mod:write_port_7ffd(S4, 16#0F),  %% slot 3 = 7, display = 7
    ?assertEqual(16#CC, Mod:read_byte(S5, 16#C000)),
    ?assertEqual(16#CC, binary:at(Mod:read_video_block(S5, 16384), 0)).

slot3_paging_unchanged_test_() ->
    [{lists:flatten(io_lib:format("~p", [Mod])),
      fun() -> slot3_paging_unchanged(Mod) end}
     || Mod <- ?MODULES].

slot3_paging_unchanged(Mod) ->
    Rom = <<0:16384/unit:8>>,
    S0 = Mod:new(Rom, Rom),

    %% Each slot-3 bank holds distinct data; paging must keep working.
    lists:foreach(fun(Bank) ->
        S1 = Mod:write_port_7ffd(S0, Bank),
        S2 = Mod:write_byte(S1, 16#C000, Bank + 1),
        S3 = Mod:write_port_7ffd(S2, Bank),
        ?assertEqual(Bank + 1, Mod:read_byte(S3, 16#C000))
    end, lists:seq(0, 7)).
