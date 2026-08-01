-module(sna_load_test).
-include_lib("eunit/include/eunit.hrl").
-include("lib/sna.hrl").
-include("z80_records.hrl").
-include("ezx_emulator.hrl").

parse_48k_sna_test() ->
    Data = <<0:(27 + 49152)/unit:8>>,
    #sna_header{is_128k = false, p7ffd = undefined, pc = undefined} = ezx_sna:parse(Data),
    ok.

parse_128k_sna_test() ->
    Data = <<0:(27 + 49152)/unit:8,
             16#3A, 16#00,   %% PC = 0x003A
             16#10,           %% p7FFD = 0x10
             16#00,           %% AY flag = 0
             0:(5*16384)/unit:8>>,
    #sna_header{is_128k = true, pc = 16#003A, p7ffd = 16#10, ay_flag = 16#00} = ezx_sna:parse(Data),
    ok.

parse_128k_sna_pc_override_test() ->
    Data = <<0:23/unit:8,
             16#40, 16#FF,          %% SP = 0xFF40
             16#00, 16#00,          %% IM=0, Border=0
             0:49152/unit:8,
             16#3A, 16#00,          %% PC = 0x003A
             16#10,                 %% p7FFD = 0x10
             16#00,                 %% AY flag
             0:(5*16384)/unit:8>>,
    H = ezx_sna:parse(Data),
    ?assertEqual(true, H#sna_header.is_128k),
    ?assertEqual(16#003A, H#sna_header.pc),
    ?assertEqual(16#10, H#sna_header.p7ffd),
    ok.

parse_48k_sna_with_trailing_garbage_test() ->
    Data = <<0:(27 + 49152 + 3)/unit:8>>,
    #sna_header{is_128k = false} = ezx_sna:parse(Data),
    ok.

load_128k_sna_verify_banks_test() ->
    Rom = binary:copy(<<0>>, 16384),
    MemMod = ezx_memory_128,
    Mem0 = MemMod:new(Rom, Rom),

    Bank5 = lists:duplicate(16384, 16#05),
    Bank2 = lists:duplicate(16384, 16#02),
    Bank0 = lists:duplicate(16384, 16#00),
    Mem48 = list_to_binary(Bank5 ++ Bank2 ++ Bank0),

    ExtraPages = list_to_binary([
        lists:duplicate(16384, 16#01),
        lists:duplicate(16384, 16#03),
        lists:duplicate(16384, 16#04),
        lists:duplicate(16384, 16#06),
        lists:duplicate(16384, 16#07)
    ]),

    ExtHeader = <<16#00, 16#00, 16#10, 16#00>>,
    SnaData = <<0:27/unit:8, Mem48/binary, ExtHeader/binary, ExtraPages/binary>>,
    ?assertEqual(131103, byte_size(SnaData)),

    Machine = #machine_state{
        memory = Mem0, memory_module = MemMod,
        cpu = #cpu_state{}, cpu_module = undefined,
        keyboard_module = undefined,
        beeper_module = undefined, beeper = undefined, keyboard = undefined
    },
    {ok, M1} = ezx_emulator_128:load_sna(Machine, SnaData),
    Mem1 = M1#machine_state.memory,

    lists:foreach(fun({Bank, Expected}) ->
        Tmp = MemMod:write_port_7ffd(Mem1, Bank),
        Byte = MemMod:read_byte(Tmp, 16#C000),
        ?assertEqual(Expected, Byte),
        io:format("Bank ~w[0] = ~.16B ✓~n", [Bank, Byte])
    end, [{0, 16#00}, {1, 16#01}, {2, 16#02}, {3, 16#03},
          {4, 16#04}, {5, 16#05}, {6, 16#06}, {7, 16#07}]),

    ok.

load_128k_sna_screen_bank7_test() ->
    Rom0 = <<0:16384/unit:8>>,
    Rom1 = binary:copy(<<16#22>>, 16384),
    MemMod = ezx_memory_128,
    Mem0 = MemMod:new(Rom0, Rom1),

    %% p7FFD = 0x1B: ROM1 (bit 4), display bank 7 (bit 3), slot 3 = bank 3.
    %% The 48K dump holds: display bank 7, bank 2, slot 3 bank 3.
    Screen16 = binary:copy(<<16#07>>, 16384),
    Bank2_16 = binary:copy(<<16#02>>, 16384),
    Slot3_16 = binary:copy(<<16#03>>, 16384),
    Mem48 = <<Screen16/binary, Bank2_16/binary, Slot3_16/binary>>,

    %% Banks not covered by the 48K dump: {2, 7, 3} -> [0, 1, 4, 5, 6].
    ExtraPages = iolist_to_binary([
        binary:copy(<<16#00>>, 16384),
        binary:copy(<<16#01>>, 16384),
        binary:copy(<<16#04>>, 16384),
        binary:copy(<<16#05>>, 16384),
        binary:copy(<<16#06>>, 16384)
    ]),

    ExtHeader = <<16#00, 16#00, 16#1B, 16#00>>,
    SnaData = <<0:27/unit:8, Mem48/binary, ExtHeader/binary, ExtraPages/binary>>,

    Machine = #machine_state{
        memory = Mem0, memory_module = MemMod,
        cpu = #cpu_state{}, cpu_module = undefined,
        keyboard_module = undefined,
        beeper_module = undefined, beeper = undefined, keyboard = undefined
    },
    {ok, M1} = ezx_emulator_128:load_sna(Machine, SnaData),
    Mem1 = M1#machine_state.memory,

    ?assertEqual(16#1B, MemMod:get_p7ffd(Mem1)),
    %% ROM1 selected by bit 4.
    ?assertEqual(16#22, MemMod:read_byte(Mem1, 16#0000)),
    %% CPU view of 0x4000-0x7FFF is bank 5, not the display bank 7.
    ?assertEqual(16#05, MemMod:read_byte(Mem1, 16#4000)),
    ?assertEqual(16#05, MemMod:read_byte(Mem1, 16#7FFF)),
    ?assertEqual(16#02, MemMod:read_byte(Mem1, 16#8000)),
    ?assertEqual(16#03, MemMod:read_byte(Mem1, 16#C000)),
    %% The ULA display reads bank 7.
    VB = MemMod:read_video_block(Mem1, 16384),
    ?assertEqual(16#07, binary:at(VB, 0)),
    ?assertEqual(16#07, binary:at(VB, 16#3FFF)),
    %% Paging bank 7 into slot 3 reveals the same data.
    Mem2 = MemMod:write_port_7ffd(Mem1, 16#07),
    ?assertEqual(16#07, MemMod:read_byte(Mem2, 16#C000)),

    ok.

load_128k_sna_on_48k_emulator_rejected_test() ->
    MemMod = ezx_memory_48_pages512,
    Rom = <<0:16384/unit:8>>,
    Mem0 = MemMod:new(Rom),

    SnaData = <<0:(27 + 49152)/unit:8,
                16#00, 16#00, 16#10, 16#00,
                0:(5*16384)/unit:8>>,

    Machine = #machine_state{
        memory = Mem0, memory_module = MemMod,
        cpu = #cpu_state{}, cpu_module = undefined,
        keyboard_module = undefined,
        beeper_module = undefined, beeper = undefined, keyboard = undefined
    },
    {error, {unsupported_version, _}} = ezx_emulator:load_sna(Machine, SnaData),
    ok.

load_48k_sna_on_128k_keeps_initial_paging_test() ->
    MemMod = ezx_memory_128,
    Rom0 = binary:copy(<<16#00>>, 16384),
    Rom1 = binary:copy(<<16#C3>>, 16384),
    Mem0 = MemMod:new(Rom0, Rom1),

    %% Sanity: p7FFD=0 initially → ROM0 → reads 0x00
    ?assertEqual(16#00, MemMod:read_byte(Mem0, 16#0000)),
    %% Sanity: force p7FFD=0x10 → ROM1 → should read 0xC3
    MemTmp = MemMod:write_port_7ffd(Mem0, 16#10),
    ?assertEqual(16#C3, MemMod:read_byte(MemTmp, 16#0000)),

    %% A 48K SNA carries no 128K paging info, so the machine's paging
    %% must remain untouched: p7FFD stays 0, ROM0 is still paged.
    SnaData = <<0:(27 + 49152)/unit:8>>,

    Machine = #machine_state{
        memory = Mem0, memory_module = MemMod,
        cpu = #cpu_state{}, cpu_module = undefined,
        keyboard_module = undefined,
        beeper_module = undefined, beeper = undefined, keyboard = undefined
    },
    {ok, M1} = ezx_emulator_128:load_sna(Machine, SnaData),
    Mem1 = M1#machine_state.memory,
    P7 = MemMod:get_p7ffd(Mem1),
    ?assertEqual(16#00, P7),
    ?assertEqual(16#00, MemMod:read_byte(Mem1, 16#0000)),
    ok.

%% --- Z80 tests ---

load_48k_z80_on_128k_keeps_initial_paging_test() ->
    MemMod = ezx_memory_128,
    Rom0 = binary:copy(<<16#00>>, 16384),
    Rom1 = binary:copy(<<16#C3>>, 16384),
    Mem0 = MemMod:new(Rom0, Rom1),

    Machine = #machine_state{
        memory = Mem0, memory_module = MemMod,
        cpu = #cpu_state{}, cpu_module = undefined,
        keyboard_module = undefined,
        beeper_module = undefined, beeper = undefined, keyboard = undefined
    },
    %% v1 Z80 with PC=0x100, flags=0 (uncompressed), 49152 zero bytes.
    %% A v1 file carries no 128K paging info, so paging stays untouched:
    %% p7FFD remains 0 and ROM0 is still paged.
    Header = <<0:8, 0:8,
               0:16, 0:16,
               16#00, 16#01,  %% PC=0x0100
               16#00, 16#10,  %% SP=0x1000
               0:8, 0:8, 0:8,
               0:16, 0:16, 0:16, 0:16,
               0:8, 0:8,
               0:16, 0:16,
               0:8, 0:8, 0:8>>,
    Data = <<Header/binary, 0:49152/unit:8>>,
    {ok, M1} = ezx_emulator_128:load_z80(Machine, Data),
    Mem1 = M1#machine_state.memory,
    P7 = MemMod:get_p7ffd(Mem1),
    ?assertEqual(16#00, P7),
    ?assertEqual(16#00, MemMod:read_byte(Mem1, 16#0000)),
    ok.
