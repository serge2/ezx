-module(ezx_saves_tests).

-include("z80_records.hrl").
-include("lib/z80.hrl").
-include("ezx_emulator.hrl").
-include_lib("eunit/include/eunit.hrl").

%% --- 48K Z80 serialization ---

z80_48k_round_trip_test() ->
    Machine0 = init_machine(),
    Cpu = Machine0#machine_state.cpu,
    Cpu1 = Cpu#cpu_state{
        a = 16#11, f = 16#22, b = 16#33, c = 16#44, d = 16#55, e = 16#66,
        h = 16#77, l = 16#88,
        a_alt = 16#99, f_alt = 16#AA, b_alt = 16#BB, c_alt = 16#CC,
        d_alt = 16#DD, e_alt = 16#EE, h_alt = 16#10, l_alt = 16#20,
        ixh = 16#31, ixl = 16#42, iyh = 16#53, iyl = 16#64,
        i = 16#75, r = 16#86, im = 2, iff1 = 1, iff2 = 0,
        pc = 16#8000, sp = 16#A000},
    M0 = Machine0#machine_state{cpu = Cpu1},
    M1 = write_prog(M0, #{16#4000 => 16#EF, 16#8000 => 16#AB, 16#C000 => 16#CD}),
    Screen0 = ezx_screen:border_set(M1#machine_state.screen, 0, 5),
    Machine = M1#machine_state{screen = Screen0},

    {ok, Z80} = ezx_saves:serialize_z80(Machine),
    %% PC != 0 -> v1: 30-byte header + the 49152-byte image, RLE-compressed
    %% (with the compressed flag and end marker) because the memory is sparse.
    ?assert(byte_size(Z80) < 30 + 49152),
    %% The compressed flag must be set so load_z80 decompresses it.
    ?assertEqual(1, (binary:at(Z80, 12) band 16#20) bsr 5),

    {ok, Loaded} = ezx_emulator:load_z80(init_machine(), Z80),
    Cpu2 = Loaded#machine_state.cpu,
    ?assertEqual(16#8000, Cpu2#cpu_state.pc),
    ?assertEqual(16#A000, Cpu2#cpu_state.sp),
    ?assertEqual(16#11, Cpu2#cpu_state.a),
    ?assertEqual(16#22, Cpu2#cpu_state.f),
    ?assertEqual(16#33, Cpu2#cpu_state.b),
    ?assertEqual(16#44, Cpu2#cpu_state.c),
    ?assertEqual(16#55, Cpu2#cpu_state.d),
    ?assertEqual(16#66, Cpu2#cpu_state.e),
    ?assertEqual(16#77, Cpu2#cpu_state.h),
    ?assertEqual(16#88, Cpu2#cpu_state.l),
    ?assertEqual(16#99, Cpu2#cpu_state.a_alt),
    ?assertEqual(16#AA, Cpu2#cpu_state.f_alt),
    ?assertEqual(16#BB, Cpu2#cpu_state.b_alt),
    ?assertEqual(16#CC, Cpu2#cpu_state.c_alt),
    ?assertEqual(16#DD, Cpu2#cpu_state.d_alt),
    ?assertEqual(16#EE, Cpu2#cpu_state.e_alt),
    ?assertEqual(16#10, Cpu2#cpu_state.h_alt),
    ?assertEqual(16#20, Cpu2#cpu_state.l_alt),
    ?assertEqual(16#31, Cpu2#cpu_state.ixh),
    ?assertEqual(16#42, Cpu2#cpu_state.ixl),
    ?assertEqual(16#53, Cpu2#cpu_state.iyh),
    ?assertEqual(16#64, Cpu2#cpu_state.iyl),
    ?assertEqual(16#75, Cpu2#cpu_state.i),
    ?assertEqual(16#86, Cpu2#cpu_state.r),
    ?assertEqual(2, Cpu2#cpu_state.im),
    %% The Z80 header stores IFF1 and IFF2 independently (unlike SNA).
    ?assertEqual(1, Cpu2#cpu_state.iff1),
    ?assertEqual(0, Cpu2#cpu_state.iff2),
    %% No SP-stacking: the memory at SP-2/SP-1 is untouched.
    ?assertNotEqual({16#00, 16#80}, {mem_byte(Loaded, 16#9FFE), mem_byte(Loaded, 16#9FFF)}),
    ?assertEqual(16#EF, mem_byte(Loaded, 16#4000)),
    ?assertEqual(16#AB, mem_byte(Loaded, 16#8000)),
    ?assertEqual(16#CD, mem_byte(Loaded, 16#C000)),
    ?assertEqual(5, ezx_screen:border_get(Loaded#machine_state.screen)).

%% PC == 0 forces the extended format even for 48K: header PC=0, the 2-byte
%% length, the extended header, and the page blocks.
z80_48k_pc_zero_extended_test() ->
    Machine0 = init_machine(),
    Cpu = Machine0#machine_state.cpu,
    M = Machine0#machine_state{cpu = Cpu#cpu_state{pc = 0, sp = 16#A000, iff1 = 1}},
    {ok, Z80} = ezx_saves:serialize_z80(M),
    %% Extended format, but the all-zero pages compress, so it is smaller
    %% than the raw 30 + 2 + 23 + 3 * 16387 bytes.
    ?assert(byte_size(Z80) < 30 + 2 + 23 + 3 * 16387),
    {ok, Loaded} = ezx_emulator:load_z80(init_machine(), Z80),
    Cpu2 = Loaded#machine_state.cpu,
    ?assertEqual(0, Cpu2#cpu_state.pc),
    ?assertEqual(16#A000, Cpu2#cpu_state.sp),
    ?assertEqual(1, Cpu2#cpu_state.iff1).

%% --- 128K Z80 serialization ---

z80_128k_round_trip_test() ->
    M0 = init_machine_128(),
    MemModule = M0#machine_state.memory_module,
    Mem1 = MemModule:write_port_7ffd(M0#machine_state.memory, 16#11),
    BankData = [{B, fill(16#A0 + B * 16#11)} || B <- lists:seq(0, 7)],
    Mem2 = lists:foldl(fun({B, D}, Acc) ->
        MemModule:write_bank_block(Acc, B, D)
    end, Mem1, BankData),
    Cpu = M0#machine_state.cpu,
    Cpu1 = Cpu#cpu_state{pc = 16#5678, sp = 16#1234, a = 16#AB, iff1 = 1, iff2 = 1},
    M1 = M0#machine_state{memory = Mem2, cpu = Cpu1},

    {ok, Z80} = ezx_saves:serialize_z80(M1),
    %% 128K always uses the extended format: header PC=0, length, extended
    %% header, and one block per bank (8 pages, 3-10). Each bank is filled
    %% with a single byte, so the blocks compress to a few dozen bytes.
    ?assert(byte_size(Z80) < 30 + 2 + 23 + 8 * 16387),

    {ok, Loaded} = ezx_emulator_128:load_z80(init_machine_128(), Z80),
    Cpu2 = Loaded#machine_state.cpu,
    ?assertEqual(16#5678, Cpu2#cpu_state.pc),
    ?assertEqual(16#1234, Cpu2#cpu_state.sp),
    ?assertEqual(16#AB, Cpu2#cpu_state.a),
    ?assertEqual(1, Cpu2#cpu_state.iff1),
    ?assertEqual(1, Cpu2#cpu_state.iff2),
    ?assertEqual(16#11, MemModule:get_p7ffd(Loaded#machine_state.memory)),
    [ ?assertEqual(D, MemModule:read_bank_block(Loaded#machine_state.memory, B))
      || {B, D} <- BankData ],
    %% The CPU view: bank 5 at 0x4000, bank 2 at 0x8000, slot-3 bank 1 at 0xC000.
    ?assertEqual(fill(16#F5), MemModule:read_block(Loaded#machine_state.memory, 16#4000, 16384)),
    ?assertEqual(fill(16#C2), MemModule:read_block(Loaded#machine_state.memory, 16#8000, 16384)),
    ?assertEqual(fill(16#B1), MemModule:read_block(Loaded#machine_state.memory, 16#C000, 16384)).

%% --- machine type detection ---

machine_type_48k_test() ->
    ?assertEqual('48k', ezx_saves:machine_type(init_machine())).

machine_type_128k_test() ->
    ?assertEqual('128k', ezx_saves:machine_type(init_machine_128())).

%% --- meta sidecar ---

meta_round_trip_test() ->
    Machine = init_machine_128(),
    Meta = ezx_saves:build_meta(Machine, "/path/game.tap"),
    ?assertEqual("128k", maps:get("machine_type", Meta)),
    ?assertEqual("ay", maps:get("ay_chip", Meta)),
    ?assertEqual("/path/game.tap", maps:get("source", Meta)),
    %% UI settings stay out of saves: no sound_* keys.
    ?assertNot(lists:any(fun(K) -> string:prefix(K, "sound_") =/= nomatch end,
                         maps:keys(Meta))),
    ?assertEqual(16, length(string:split(maps:get("ay_regs", Meta), ",", all))),
    Bin = iolist_to_binary(ezx_saves:meta_to_iodata(Meta)),
    ?assertEqual(Meta, ezx_saves:parse_meta(Bin)).

meta_parse_skips_junk_test() ->
    ?assertEqual(#{}, ezx_saves:parse_meta(<<"not a meta file\n\njust text\n">>)),
    ?assertEqual(#{"a" => "1", "b" => "2"}, ezx_saves:parse_meta(<<"a=1\njunk line\n\nb=2\n">>)).

apply_meta_restores_audio_test() ->
    Machine0 = init_machine_128(),
    Cpu0 = Machine0#machine_state.cpu,
    NewRegs = lists:seq(16#10, 16#1F),
    Meta = #{
        "beeper_level" => "5",
        "ay_regs" => string:join([integer_to_list(R) || R <- NewRegs], ",")
    },
    Machine1 = ezx_saves:apply_meta(Machine0, Meta),
    Cpu1 = Machine1#machine_state.cpu,
    %% The CPU (IFF1/IFF2/PC) is restored by the Z80 snapshot itself, so
    %% apply_meta must leave it untouched.
    ?assertEqual(Cpu0#cpu_state.iff1, Cpu1#cpu_state.iff1),
    ?assertEqual(Cpu0#cpu_state.iff2, Cpu1#cpu_state.iff2),
    ?assertEqual(5, ezx_beeper2:level(Machine1#machine_state.beeper)),
    ?assertEqual(NewRegs, ezx_ay38912_seg:regs(Machine1#machine_state.ay)).

apply_meta_no_ay_unchanged_test() ->
    Machine0 = init_machine(),
    Cpu = Machine0#machine_state.cpu,
    Machine1 = ezx_saves:apply_meta(Machine0, #{"beeper_level" => "1"}),
    ?assertEqual(Cpu#cpu_state.pc, (Machine1#machine_state.cpu)#cpu_state.pc).

%% --- loading a save from disk ---

load_save_round_trip_test() ->
    Root = temp_root(),
    file:del_dir_r(Root),
    try
        Machine0 = init_machine(),
        Cpu = Machine0#machine_state.cpu,
        Machine1 = Machine0#machine_state{cpu = Cpu#cpu_state{pc = 16#8000, iff1 = 1}},
        {ok, _} = ezx_saves:save_history(Machine1, Root, "g.tap", "level 1"),
        [{_Stamp, _, _, SavePath, MetaPath}] = ezx_saves:list_history(Root),
        %% One call loads the snapshot, resolves the machine type/chip from the
        %% meta, and applies the audio side; the caller gets the ready machine
        %% plus the meta it can reconfigure the UI from.
        {ok, Loaded, Meta} = ezx_saves:load_save(SavePath, MetaPath, ay),
        ?assertEqual("48k", maps:get("machine_type", Meta)),
        %% init_machine() has no AY device, so the save records the chip as
        %% off and loading reproduces a chip-less machine.
        ?assertEqual("off", maps:get("ay_chip", Meta)),
        ?assertEqual(undefined, Loaded#machine_state.ay_module),
        ?assertEqual("g.tap", maps:get("source", Meta)),
        Cpu2 = Loaded#machine_state.cpu,
        ?assertEqual(16#8000, Cpu2#cpu_state.pc),
        ?assertEqual(1, Cpu2#cpu_state.iff1)
    after
        file:del_dir_r(Root)
    end.

load_save_without_meta_test() ->
    Root = temp_root(),
    file:del_dir_r(Root),
    try
        Machine0 = init_machine(),
        Cpu = Machine0#machine_state.cpu,
        Machine1 = Machine0#machine_state{cpu = Cpu#cpu_state{pc = 16#8000}},
        {ok, Z80} = ezx_saves:serialize_z80(Machine1),
        filelib:ensure_dir(filename:join(Root, "dummy")),
        Z80Path = filename:join(Root, "no-meta.z80"),
        ok = file:write_file(Z80Path, Z80),
        %% No sidecar: the machine type falls back to parsing the snapshot and
        %% the returned meta is synthesized with the resolved values.
        {ok, Loaded, Meta} = ezx_saves:load_save(Z80Path,
                                                 filename:rootname(Z80Path) ++ ".meta", ym),
        ?assertEqual("48k", maps:get("machine_type", Meta)),
        ?assertEqual("ym", maps:get("ay_chip", Meta)),
        ?assertNot(maps:is_key("source", Meta)),
        ?assertEqual(16#8000, (Loaded#machine_state.cpu)#cpu_state.pc)
    after
        file:del_dir_r(Root)
    end.

%% The chip in the meta is authoritative: an "ay" save restores ay even when
%% the UI is set to ym, and a save recorded with the chip off reloads as a
%% machine without an AY device. The DefaultChip is used only when the meta
%% carries no "ay_chip" key at all.
load_save_chip_from_meta_test() ->
    Root = temp_root(),
    file:del_dir_r(Root),
    try
        filelib:ensure_dir(filename:join(Root, "dummy")),
        Machine0 = init_machine(),
        Cpu = Machine0#machine_state.cpu,
        Machine1 = Machine0#machine_state{cpu = Cpu#cpu_state{pc = 16#8000}},
        {ok, Z80} = ezx_saves:serialize_z80(Machine1),
        Z80Path = filename:join(Root, "chip.z80"),
        ok = file:write_file(Z80Path, Z80),
        MetaPath = filename:rootname(Z80Path) ++ ".meta",
        ok = file:write_file(MetaPath, ezx_saves:meta_to_iodata(#{"ay_chip" => "ay"})),
        {ok, LoadedAy, MetaAy} = ezx_saves:load_save(Z80Path, MetaPath, ym),
        ?assertEqual("ay", maps:get("ay_chip", MetaAy)),
        ?assertNotEqual(undefined, LoadedAy#machine_state.ay_module),
        ?assertEqual(ay, ezx_ay38912_seg:chip(LoadedAy#machine_state.ay)),
        ok = file:write_file(MetaPath, ezx_saves:meta_to_iodata(#{"ay_chip" => "off"})),
        {ok, LoadedOff, MetaOff} = ezx_saves:load_save(Z80Path, MetaPath, ym),
        ?assertEqual("off", maps:get("ay_chip", MetaOff)),
        ?assertEqual(undefined, LoadedOff#machine_state.ay_module)
    after
        file:del_dir_r(Root)
    end.

%% --- program name (used for save file names) ---

program_name_test() ->
    ?assertEqual("Basic", ezx_saves:program_name("")),
    ?assertEqual("Basic", ezx_saves:program_name("/")),
    ?assertEqual("My Game", ezx_saves:program_name("/some/dir/My Game.tap")),
    ?assertEqual("Game (1985)", ezx_saves:program_name("Game (1985).sna")),
    ?assertEqual("a__b__c", ezx_saves:program_name("a__b__c.tap")),
    ?assertEqual("Игра 1", ezx_saves:program_name("Игра 1.tap")).

is_quick_slot_test() ->
    ?assert(ezx_saves:is_quick_slot("Last Quicksave")),
    ?assertNot(ezx_saves:is_quick_slot("20240805-120000")),
    ?assertNot(ezx_saves:is_quick_slot("")).

%% --- quick save / load ---

quick_save_and_path_test() ->
    Root = temp_root(),
    file:del_dir_r(Root),
    try
        Machine = init_machine(),
        ?assertEqual(none, ezx_saves:quick_path(Root)),
        {ok, WrittenArchive} = ezx_saves:quick_save(Machine, Root, "g.tap"),
        ?assert(filelib:is_regular(WrittenArchive)),
        %% F9 slot: the fixed "Last Quicksave" pair in the root.
        {ok, Z80Path, MetaPath} = ezx_saves:quick_path(Root),
        ?assertEqual(filename:join(Root, "Last Quicksave.z80"), Z80Path),
        ?assert(filelib:is_regular(Z80Path)),
        ?assert(filelib:is_regular(MetaPath)),
        {ok, Z80} = file:read_file(Z80Path),
        %% Fresh machine: pc = 0 -> extended format; the sparse (mostly
        %% zeroed) pages compress, so the file is far smaller than the raw
        %% 30 + 2 + 23 + 3 * 16387 bytes.
        ?assert(byte_size(Z80) < 30 + 2 + 23 + 3 * 16387),
        #z80_header{is_128k = false} = ezx_z80:parse(Z80),
        %% The fixed slot is always listed first and keeps its bare identity
        %% (no name in its meta); the archive copy carries the human
        %% quick-save name "<Program> - Quicksave".
        [{Quick, "", _, QuickPath, _QuickMeta} | _] = ezx_saves:list_history(Root),
        ?assertEqual("Last Quicksave", Quick),
        ?assertEqual(Z80Path, QuickPath),
        %% A quick save also writes an archive copy <Program>-quicksave-<stamp>
        %% (same name in its meta); both live flat in the root.
        [{ArchiveStamp, "g - Quicksave", _, ArchivePath, _ArchiveMeta} | _]
            = [E || E = {S, _, _, _, _} <- ezx_saves:list_history(Root),
                    S =/= "Last Quicksave"],
        ?assertEqual("g", string:left(ArchiveStamp, 1)),
        ?assertNotEqual(nomatch, string:find(ArchiveStamp, "-quicksave-")),
        ?assert(filelib:is_regular(ArchivePath)),
        %% The returned archive path is the one listed — the timestamped,
        %% uniquified name is only known at save time, so a recomputed name
        %% would not address the file that was written.
        ?assertEqual(ArchivePath, WrittenArchive),
        ?assertEqual(Root, filename:dirname(Z80Path)),
        ?assertEqual(Root, filename:dirname(ArchivePath))
    after
        file:del_dir_r(Root)
    end.

%% --- named history entries ---

history_named_save_test() ->
    Root = temp_root(),
    file:del_dir_r(Root),
    try
        Machine = init_machine(),
        {ok, Path} = ezx_saves:save_history(Machine, Root, "g.tap", "level 1"),
        ?assert(filelib:is_regular(Path)),
        [{Stamp, "level 1", Timestamp, _S, _M}] = ezx_saves:list_history(Root),
        %% The file is named <name>-<stamp>.z80 so it can be found on disk.
        ?assert(lists:prefix("level 1-", Stamp)),
        ?assert(lists:suffix(Timestamp, Stamp)),
        ?assertEqual(Stamp, filename:basename(Path, ".z80")),
        ok = ezx_saves:rename_history(Root, Stamp, "level 1 hard"),
        [{Stamp2, "level 1 hard", Timestamp, _S2, _M2}] = ezx_saves:list_history(Root),
        %% Rename moved the pair: the old base is gone, the new one exists,
        %% and the stamp (the save's identity) carried over.
        ?assert(lists:prefix("level 1 hard-", Stamp2)),
        ?assertNot(filelib:is_regular(filename:join(Root, Stamp ++ ".z80"))),
        ?assert(filelib:is_regular(filename:join(Root, Stamp2 ++ ".z80"))),
        ok = ezx_saves:delete_history(Root, Stamp2),
        ?assertEqual([], ezx_saves:list_history(Root))
    after
        file:del_dir_r(Root)
    end.

png_sidecar_handling_test() ->
    Root = temp_root(),
    file:del_dir_r(Root),
    try
        Machine = init_machine(),
        {ok, Path} = ezx_saves:save_history(Machine, Root, "g.tap", "lvl"),
        Png = ezx_saves:png_path(Path),
        ?assertEqual(filename:rootname(Path) ++ ".png", Png),
        %% The UI writes the screenshot sidecar; the bookkeeping functions
        %% must treat it as part of the save (rename moves it, delete removes
        %% it), and a save without one still renames/deletes cleanly.
        ok = file:write_file(Png, <<"png">>),
        [{Stamp, _, _, _, _}] = ezx_saves:list_history(Root),
        ok = ezx_saves:rename_history(Root, Stamp, "renamed"),
        [{Stamp2, "renamed", _, _, _}] = ezx_saves:list_history(Root),
        ?assert(filelib:is_regular(filename:join(Root, Stamp2 ++ ".png"))),
        ?assertNot(filelib:is_regular(Png)),
        ok = ezx_saves:delete_history(Root, Stamp2),
        ?assertEqual([], ezx_saves:list_history(Root)),
        ?assertNot(filelib:is_regular(filename:join(Root, Stamp2 ++ ".png"))),
        {ok, _} = ezx_saves:save_history(Machine, Root, "g.tap", "noimg"),
        [{Stamp3, _, _, _, _}] = ezx_saves:list_history(Root),
        ok = ezx_saves:rename_history(Root, Stamp3, "noimg2"),
        [{Stamp4, "noimg2", _, _, _}] = ezx_saves:list_history(Root),
        ok = ezx_saves:delete_history(Root, Stamp4)
    after
        file:del_dir_r(Root)
    end.

history_name_is_sanitized_in_filename_test() ->
    Root = temp_root(),
    file:del_dir_r(Root),
    try
        Machine = init_machine(),
        %% Filesystem-hostile chars become spaces and Unicode letters survive,
        %% so the file is still findable by the typed name.
        {ok, Path} = ezx_saves:save_history(Machine, Root, "g.tap", "save/1: уровень"),
        Base = filename:basename(Path, ".z80"),
        ?assert(lists:prefix("save 1 уровень-", Base)),
        ?assertNotEqual(nomatch, string:find(Base, "уровень")),
        ?assertEqual(0, length([C || C <- Base, C =:= $/])),
        [{Stamp, "save/1: уровень", _, _, _}] = ezx_saves:list_history(Root),
        ?assertEqual(Stamp, filename:basename(Path, ".z80"))
    after
        file:del_dir_r(Root)
    end.

history_name_falls_back_to_stamp_test() ->
    Root = temp_root(),
    file:del_dir_r(Root),
    try
        Machine = init_machine(),
        %% A name that sanitizes to nothing (only hostile chars) leaves a
        %% plain <stamp> file, like an empty name.
        {ok, Path} = ezx_saves:save_history(Machine, Root, "g.tap", "/:"),
        Base = filename:basename(Path, ".z80"),
        [{Stamp, Name, _, _, _}] = ezx_saves:list_history(Root),
        ?assertEqual(Base, Stamp),
        ?assertEqual(Stamp, Name),
        ?assertNotEqual(nomatch, string:find(Stamp, "-"))
    after
        file:del_dir_r(Root)
    end.

history_ordering_test() ->
    Root = temp_root(),
    file:del_dir_r(Root),
    try
        Machine = init_machine(),
        {ok, _} = ezx_saves:save_history(Machine, Root, "g.tap", "first"),
        {ok, _} = ezx_saves:save_history(Machine, Root, "g.tap", "second"),
        Names = [N || {_, N, _, _, _} <- ezx_saves:list_history(Root)],
        ?assertEqual(lists:sort(["first", "second"]), lists:sort(Names)),
        ?assertEqual(2, length(Names))
    after
        file:del_dir_r(Root)
    end.

history_default_name_is_stamp_test() ->
    Root = temp_root(),
    file:del_dir_r(Root),
    try
        Machine = init_machine(),
        {ok, _} = ezx_saves:save_history(Machine, Root, "g.tap", ""),
        [{Stamp, Name, _T, _S, _M}] = ezx_saves:list_history(Root),
        ?assertEqual(Stamp, Name),
        ?assertNotEqual(nomatch, string:find(Stamp, "-"))
    after
        file:del_dir_r(Root)
    end.

%% --- ordering ---

list_history_sorts_by_mtime_test() ->
    Root = temp_root(),
    file:del_dir_r(Root),
    try
        Machine = init_machine(),
        {ok, _} = ezx_saves:save_history(Machine, Root, "g.tap", "old"),
        timer:sleep(1100),
        {ok, _} = ezx_saves:save_history(Machine, Root, "g.tap", "new"),
        {ok, _} = ezx_saves:quick_save(Machine, Root, "g.tap"),
        [{Quick, _, _, _, _} | Rest] = ezx_saves:list_history(Root),
        ?assertEqual("Last Quicksave", Quick),
        %% Newest first by mtime: "new" precedes "old" (the quicksave archive
        %% copy has no name and is filtered out of the order check).
        Ordered = [N || {_, N, _, _, _} <- Rest, N =:= "new" orelse N =:= "old"],
        ?assertEqual(["new", "old"], Ordered)
    after
        file:del_dir_r(Root)
    end.

%% --- Helpers ---

init_machine() ->
    RomPath = rom_path("48.rom"),
    {ok, Rom} = file:read_file(RomPath),
    ezx_emulator:init(?SPECTRUM_48_MODEL, z80_cpu, ezx_memory_48_pages512_tuples,
                      ezx_keyboard, ezx_beeper2, undefined, Rom).

init_machine_128() ->
    RomPath = rom_path("48.rom"),
    {ok, Rom} = file:read_file(RomPath),
    ezx_emulator_128:init(?SPECTRUM_128_MODEL, z80_cpu, ezx_memory_128_banks_tuples,
                          ezx_keyboard, ezx_beeper2, ezx_ay38912_seg, {Rom, Rom}).

rom_path(File) ->
    try filename:join([code:priv_dir(ezx), "roms", File])
    catch error:badarg ->
        BeamDir = filename:dirname(code:which(?MODULE)),
        filename:join([filename:dirname(BeamDir), "priv", "roms", File])
    end.

write_prog(Machine, Prog) ->
    maps:fold(fun(Addr, Byte, M) -> ezx_emulator:write_byte(M, Addr, Byte) end,
              Machine, Prog).

mem_byte(Machine, Addr) ->
    {Byte, _} = ezx_emulator:read_byte(Machine, Addr),
    Byte.

fill(Byte) -> binary:copy(<<Byte>>, 16384).

temp_root() ->
    Unique = erlang:unique_integer([positive]),
    filename:join("/tmp", "ezx_saves_tests_" ++ integer_to_list(Unique)).
