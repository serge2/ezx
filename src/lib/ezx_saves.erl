-module(ezx_saves).

%% @doc Quick save / load and save-history support for the ezx emulator.
%%
%% A save is a pair of files with a shared base name:
%%   - a `.z80` snapshot binary (Fuse-compatible), and
%%   - a `.meta` sidecar (key=value text, one entry per line) that stores the
%%     state the Z80 format cannot represent: the beeper level, the AY
%%     registers, the machine type, the sound chip, the source game file, and
%%     the save timestamp.
%%
%% The `.meta` file is optional on load: the Z80 binary alone restores the
%% CPU (PC, IFF1/IFF2, IM included), RAM, paging, border colour and screen.
%% apply_meta/2 restores the audio side from the sidecar when it is present.
%%
%% == Snapshot encoding ==
%% ezx_z80 is a pure format module that knows nothing about the machine
%% state: parse/1 decodes a binary into the #z80_header{} record and
%% compose/1 encodes the record back. The bridge between a machine and the
%% record lives here: to_z80_header/1 + serialize_z80/1. Saves are written
%% as Z80 because its explicit PC field avoids the SNA PC-stacking hack and
%% the sp_too_low restriction, and it stores IFF1/IFF2 directly.
%%
%% The Z80 layout written here is described in ezx_z80: a 48K snapshot with
%% PC != 0 is a v1 file (30-byte header + the 0x4000-0xFFFF image, RLE
%% compressed when that is smaller); a 48K snapshot with PC == 0, and every
%% 128K snapshot, use the extended v2-style format with the 2-byte length,
%% the extended header (real PC, hw_mode, p7ffd) and per-page blocks, each
%% RLE compressed when that is smaller.
%%
%% == Save files ==
%% All saves live flat in SavesRoot (no per-game subdirectories), so a save
%% can be loaded without loading its game first. A save is a pair of files
%% with a shared base name. The F5 quick slot is the fixed file
%% `Last Quicksave`; F9 always loads it, whatever game (if any) is loaded.
%% Each quick save also writes an archive copy named
%% `<Program>-quicksave-<stamp>` where <Program> is the loaded game's title
%% (or "Basic" when nothing is loaded) and <stamp> = YYYYMMDD-HHMMSS. F2
%% named saves are `<Name>-<stamp>` files (the name sanitized to a
%% filesystem-safe form, the stamp keeping them unique), carrying the full
%% human `name` in the meta (shown by the manager dialog). list_history/1
%% lists every `.z80` save in the root, newest first (the fixed quick slot
%% sorts to the top); older `.sna` saves are ignored.
%%
%% All filesystem functions take the saves root explicitly so tests can point
%% them at a temporary directory; the UI passes ezx_ui_lib:app_dir()/saves.

-export([
    serialize_z80/1,
    to_z80_header/1,
    machine_type/1,
    build_meta/2,
    meta_to_iodata/1,
    parse_meta/1,
    apply_meta/2,
    read_meta/1,
    load_save/3,
    program_name/1,
    is_quick_slot/1,
    quick_save/3,
    quick_path/1,
    save_history/4,
    list_history/1,
    delete_history/2,
    rename_history/3
]).

-include("z80_records.hrl").
-include("ezx_emulator.hrl").
-include("lib/z80.hrl").
-include_lib("kernel/include/file.hrl").

-define(QUICK_STAMP, "Last Quicksave").
-define(SAVE_EXT, ".z80").
-define(DEFAULT_PROGRAM, "Basic").
-define(NAME_MAX_LEN, 60).

%% @doc Build a Fuse-compatible Z80 binary from a machine state (the format
%% used for saves). Unlike SNA there is no error case: the Z80 format stores
%% PC explicitly, so any SP works.
-spec serialize_z80(#machine_state{}) -> {ok, binary()}.
serialize_z80(Machine) ->
    {ok, ezx_z80:compose(to_z80_header(Machine))}.

%% @doc Capture a machine state as a #z80_header{} record, ready for
%% ezx_z80:compose/1. 48K fills mem plus the 48K pages (8, 4, 5); 128K sets
%% hw_mode 2 (no AY) or 3 (AY) and the p7ffd byte, with every RAM bank as a
%% page (page = bank + 3, per libspectrum's 128K numbering).
-spec to_z80_header(#machine_state{}) -> #z80_header{}.
to_z80_header(#machine_state{cpu = Cpu, screen = Screen} = Machine) ->
    MemModule = Machine#machine_state.memory_module,
    Mem0 = Machine#machine_state.memory,
    Common = #z80_header{
        a = Cpu#cpu_state.a, f = Cpu#cpu_state.f,
        bc = pair(Cpu#cpu_state.b, Cpu#cpu_state.c),
        de = pair(Cpu#cpu_state.d, Cpu#cpu_state.e),
        hl = pair(Cpu#cpu_state.h, Cpu#cpu_state.l),
        pc = Cpu#cpu_state.pc, sp = Cpu#cpu_state.sp,
        i = Cpu#cpu_state.i, r = Cpu#cpu_state.r,
        border = ezx_screen:border_get(Screen),
        bc_alt = pair(Cpu#cpu_state.b_alt, Cpu#cpu_state.c_alt),
        de_alt = pair(Cpu#cpu_state.d_alt, Cpu#cpu_state.e_alt),
        hl_alt = pair(Cpu#cpu_state.h_alt, Cpu#cpu_state.l_alt),
        a_alt = Cpu#cpu_state.a_alt, f_alt = Cpu#cpu_state.f_alt,
        ix = pair(Cpu#cpu_state.ixh, Cpu#cpu_state.ixl),
        iy = pair(Cpu#cpu_state.iyh, Cpu#cpu_state.iyl),
        iff1 = Cpu#cpu_state.iff1, iff2 = Cpu#cpu_state.iff2,
        im = Cpu#cpu_state.im
    },
    case machine_type(Machine) of
        '48k' ->
            Mem = MemModule:read_block(Mem0, 16#4000, 49152),
            <<Page8:16384/binary, Page4:16384/binary, Page5:16384/binary>> = Mem,
            Common#z80_header{
                hw_mode = 0,
                is_128k = false,
                mem = Mem,
                pages = #{8 => Page8, 4 => Page4, 5 => Page5}
            };
        '128k' ->
            P7 = MemModule:get_p7ffd(Mem0) band 16#FF,
            Banks = [{B, MemModule:read_bank_block(Mem0, B)} || B <- lists:seq(0, 7)],
            HwMode = case Machine#machine_state.ay_module of
                undefined -> 2;
                _ -> 3
            end,
            Common#z80_header{
                hw_mode = HwMode,
                p7ffd = P7,
                is_128k = true,
                pages = maps:from_list([{B + 3, D} || {B, D} <- Banks])
            }
    end.

%% @doc '48k' for a linear-memory machine, '128k' for a paged one (detected by
%% the memory backend's read_bank_block/2 export).
-spec machine_type(#machine_state{}) -> '48k' | '128k'.
machine_type(#machine_state{memory_module = MemModule}) ->
    case erlang:function_exported(MemModule, read_bank_block, 2) of
        true -> '128k';
        false -> '48k'
    end.

%% @doc Build the meta map for a machine. Only state the Z80 snapshot cannot
%% carry is stored (the binary already holds the CPU, RAM, paging, border and
%% PC): the beeper level, the AY registers, the machine type, the sound chip,
%% the source game file and a timestamp. UI preferences (sound volume, stereo
%% mode, ...) deliberately stay out of saves — they are the user's settings,
%% not the machine's state.
-spec build_meta(#machine_state{}, string()) -> #{string() => string()}.
build_meta(#machine_state{} = Machine, Source) ->
    #{
        "machine_type" => atom_to_list(machine_type(Machine)),
        "ay_chip" => ay_chip_str(Machine),
        "beeper_level" => integer_to_list(beeper_level(Machine)),
        "ay_regs" => ay_regs_str(Machine),
        "source" => Source,
        "timestamp" => stamp_now()
    }.

%% @doc Serialize a meta map to key=value lines (one per line, \n-terminated).
%% Values are written as UTF-8, so Unicode names survive the round trip (raw
%% codepoints above 255 are not valid iodata and would fail the write).
-spec meta_to_iodata(#{string() => string()}) -> iodata().
meta_to_iodata(Meta) ->
    [[K, "=", unicode:characters_to_binary(V), "\n"] || {K, V} <- maps:to_list(Meta)].

%% @doc Parse a .meta file binary into a string() => string() map.
%% Unknown lines are skipped; the first "=" on a line separates key from value.
-spec parse_meta(binary()) -> #{string() => string()}.
parse_meta(Bin) ->
    Lines = [string:trim(L) || L <- string:split(Bin, "\n", all), L =/= <<>>],
    lists:foldl(fun(Line, Acc) ->
        case string:split(Line, "=") of
            [K, V] ->
                Acc#{unicode:characters_to_list(string:trim(K)) =>
                     unicode:characters_to_list(string:trim(V))};
            _ ->
                Acc
        end
    end, #{}, Lines).

%% @doc Restore the state the Z80 snapshot cannot carry: the beeper level and
%% the AY registers (when the meta keys and the device are present). The CPU
%% side (IFF1/IFF2, PC, IM) is restored by the snapshot itself. A missing
%% sidecar (`undefined') is a no-op — the snapshot alone still restores the
%% CPU, RAM, paging, border and screen.
-spec apply_meta(#machine_state{}, #{string() => string()} | undefined) -> #machine_state{}.
apply_meta(Machine, undefined) -> Machine;
apply_meta(Machine, Meta) ->
    apply_beeper(apply_ay(Machine, Meta), Meta).

%% @doc Read a .meta sidecar from disk; `undefined' when missing/unreadable.
-spec read_meta(string()) -> #{string() => string()} | undefined.
read_meta(MetaPath) ->
    case file:read_file(MetaPath) of
        {ok, Bin} -> parse_meta(Bin);
        _ -> undefined
    end.

%% @doc Load a save from disk in one step: read the meta sidecar, resolve the
%% target machine type and chip (the meta is authoritative; a save without a
%% meta falls back to parsing the snapshot itself), load the snapshot through
%% the file loader, and restore the audio state (beeper/AY regs) from the
%% meta. Returns the ready machine plus the meta for the UI to reconfigure
%% itself from: the sidecar (or a synthesized map when it is missing) always
%% carrying the resolved `machine_type` and `ay_chip`, plus `source` and the
%% other sidecar keys when the sidecar exists.
-spec load_save(string(), string(), ay | ym | off) ->
    {ok, #machine_state{}, #{string() => string()}} | {error, {Error, Details::binary()}} when
    Error :: file_not_found | unsupported_format | rom_not_found | rom_bad_size | bad_machine_type |
        bad_sna_header | unsupported_version | sna_load_failed | bad_z80_header | z80_load_failed |
        bad_tap_data.
load_save(SavePath, MetaPath, DefaultChip) ->
    RawMeta = read_meta(MetaPath),
    TargetType = save_machine_type(RawMeta, SavePath),
    Chip = meta_chip(RawMeta, DefaultChip),
    case ezx_ui_lib:load_emulator_file(SavePath, TargetType, Chip) of
        {ok, Machine0} ->
            Meta = complete_meta(RawMeta, TargetType, Chip),
            {ok, apply_meta(Machine0, RawMeta), Meta};
        {error, _Code} = Err ->
            Err
    end.

%% @doc The meta handed to the caller: the raw sidecar (or an empty map when
%% it is missing) always carrying the resolved machine type and chip, so the
%% caller never has to re-run the fallback resolution.
complete_meta(Meta, TargetType, Chip) ->
    Base = case Meta of undefined -> #{}; _ -> Meta end,
    Base#{"machine_type" => atom_to_list(TargetType),
          "ay_chip" => atom_to_list(Chip)}.

%% @doc Machine type for a save: the meta is authoritative. The fallback for a
%% save without a meta sidecar parses the snapshot itself — a Z80 file is
%% detected by its extended header's hw_mode, a SNA file by its size (a 48K
%% SNA is exactly 27 + 49152 bytes; anything larger is a 128K snapshot),
%% matching libspectrum's identify_machine.
save_machine_type(undefined, Path) ->
    case filename:extension(Path) of
        ".z80" -> z80_machine_type(Path);
        _ -> sna_machine_type(Path)
    end;
save_machine_type(Meta, _Path) ->
    case maps:get("machine_type", Meta, undefined) of
        "128k" -> '128k';
        _ -> '48k'
    end.

z80_machine_type(Path) ->
    case file:read_file(Path) of
        {ok, Data} ->
            try ezx_z80:parse(Data) of
                #z80_header{is_128k = true} -> '128k';
                _ -> '48k'
            catch
                _:_ -> '48k'
            end;
        _ -> '48k'
    end.

sna_machine_type(Path) ->
    case file:read_file(Path) of
        {ok, Data} when byte_size(Data) > 27 + 49152 -> '128k';
        _ -> '48k'
    end.

%% @doc The chip a save was written with, read from the meta as-is: "ym" -> ym,
%% "ay" -> ay, "off" -> off (a machine with no AY device). The default applies
%% only when the meta is missing or carries no "ay_chip" key (e.g. a save
%% without a sidecar) — never to an explicit value, so an "ay" save restores
%% ay even when the UI is set to ym, and a chip-less machine stays off.
meta_chip(undefined, Default) -> Default;
meta_chip(Meta, Default) ->
    case maps:get("ay_chip", Meta, undefined) of
        "ym" -> ym;
        "ay" -> ay;
        "off" -> off;
        _ -> Default
    end.

%% @doc Human title of the loaded game, used for save file names: the source
%% file's base name with the extension stripped and sanitized to a
%% filesystem-safe form (see sanitize_filename/1); "Basic" when nothing is
%% loaded or the sanitized result is empty.
-spec program_name(string()) -> string().
program_name(Source) ->
    case sanitize_filename(filename:rootname(filename:basename(Source))) of
        "" -> ?DEFAULT_PROGRAM;
        S -> S
    end.

%% @doc True for the fixed quick slot stamp ("Last Quicksave"). The dialog
%% uses this to protect the slot from rename/delete.
-spec is_quick_slot(string()) -> boolean().
is_quick_slot(Stamp) ->
    Stamp =:= ?QUICK_STAMP.

%% @doc Quick save (F5): overwrite the fixed `Last Quicksave` slot and write
%% an archive copy named <Program>-quicksave-<stamp>. The Z80 serializer has
%% no failure case (PC is stored explicitly); both files share the save's meta.
-spec quick_save(#machine_state{}, string(), string()) ->
    ok | {error, term()}.
quick_save(Machine, SavesRoot, Source) ->
    case write_save(quick_path_z80(SavesRoot), Machine, Source) of
        ok ->
            Archive = archive_path(SavesRoot, Source),
            Meta = build_meta(Machine, Source),
            filelib:ensure_dir(filename:join(SavesRoot, "dummy")),
            write_two(Archive, meta_path(Archive), Machine, Meta);
        Err ->
            Err
    end.

%% @doc Paths for the fixed quick slot, or `none' when no quick save exists yet.
-spec quick_path(string()) -> {ok, string(), string()} | none.
quick_path(SavesRoot) ->
    Z80Path = quick_path_z80(SavesRoot),
    case filelib:is_regular(Z80Path) of
        true -> {ok, Z80Path, meta_path(Z80Path)};
        false -> none
    end.

%% @doc Append a history entry. The file is named `<name>-<stamp>.z80` (the
%% name sanitized to a filesystem-safe form) so it can be found on disk; the
%% stamp suffix keeps names unique. An empty name falls back to `<stamp>.z80`.
%% The human name is also kept in the meta, where the manager dialog reads it.
-spec save_history(#machine_state{}, string(), string(), string()) ->
    {ok, string()} | {error, term()}.
save_history(Machine, SavesRoot, Source, Name) ->
    filelib:ensure_dir(filename:join(SavesRoot, "dummy")),
    Stamp = stamp_now(),
    Z80Path = history_path(SavesRoot, Name, Stamp),
    Meta0 = build_meta(Machine, Source),
    Meta = (Meta0#{"name" => case sanitize_filename(Name) of
        "" -> Stamp;
        _ -> Name
    end})#{"timestamp" => Stamp},
    case write_two(Z80Path, meta_path(Z80Path), Machine, Meta) of
        ok -> {ok, Z80Path};
        {error, _} = Err -> Err
    end.

%% @doc Every save in the root, newest first (sorted by file modification
%% time as a proxy for creation time); the fixed quick slot is always listed
%% first. Entries are [{Stamp, Name, Z80Path, MetaPath}]. Only `.z80` saves
%% are listed; older `.sna` saves are ignored.
-spec list_history(string()) -> [{string(), string(), string(), string()}].
list_history(SavesRoot) ->
    case file:list_dir(SavesRoot) of
        {ok, Names} ->
            Z80s = [N || N <- Names, filename:extension(N) =:= ".z80"],
            Stamps = [filename:basename(N, ".z80") || N <- Z80s],
            Sorted = sort_by_mtime(SavesRoot, Stamps),
            [{St, history_name(SavesRoot, St), filename:join(SavesRoot, St ++ ".z80"),
              filename:join(SavesRoot, St ++ ".meta")} || St <- Sorted];
        {error, enoent} -> []
    end.

%% @doc Delete a save (both files).
-spec delete_history(string(), string()) -> ok | {error, term()}.
delete_history(SavesRoot, Stamp) ->
    Z80 = filename:join(SavesRoot, Stamp ++ ".z80"),
    R1 = file:delete(Z80),
    R2 = file:delete(meta_path(Z80)),
    case {R1, R2} of
        {ok, ok} -> ok;
        {ok, {error, enoent}} -> ok;
        {{error, enoent}, ok} -> ok;
        {_, {error, R}} -> {error, R};
        {{error, R}, _} -> {error, R}
    end.

%% @doc Rename a save: the `.z80`/`.meta` pair is moved to the new
%% `<name>-<stamp>.z80` base (same stamp, so the save's identity survives)
%% and the meta `name' field is rewritten. Renaming to the same name only
%% updates the meta.
-spec rename_history(string(), string(), string()) -> ok | {error, term()}.
rename_history(SavesRoot, Stamp, NewName) ->
    MetaPath = filename:join(SavesRoot, Stamp ++ ".meta"),
    case read_meta(MetaPath) of
        undefined ->
            {error, enoent};
        Meta ->
            OldZ80 = filename:join(SavesRoot, Stamp ++ ".z80"),
            Timestamp = maps:get("timestamp", Meta, Stamp),
            Meta1 = Meta#{"name" => case NewName of
                "" -> Timestamp;
                _ -> NewName
            end},
            NewBase = history_base(NewName, Timestamp),
            case NewBase of
                Stamp ->
                    file:write_file(MetaPath, meta_to_iodata(Meta1));
                _ ->
                    NewZ80 = available_path(
                        filename:join(SavesRoot, NewBase ++ ?SAVE_EXT), 0),
                    case file:rename(OldZ80, NewZ80) of
                        ok ->
                            file:write_file(meta_path(NewZ80),
                                            meta_to_iodata(Meta1)),
                            file:delete(MetaPath);
                        {error, _} = Err -> Err
                    end
            end
    end.

%% --- internal ---

pair(Hi, Lo) -> ((Hi band 16#FF) bsl 8) bor (Lo band 16#FF).

beeper_level(#machine_state{beeper_module = BeeperModule, beeper = Beeper}) ->
    BeeperModule:level(Beeper).

%% @doc The chip a machine's AY device uses, or "off" when the machine has no
%% AY device at all (ay_module = undefined).
ay_chip_str(#machine_state{ay_module = undefined}) -> "off";
ay_chip_str(#machine_state{model = Model}) -> atom_to_list(Model#machine_model.ay_chip).

ay_regs_str(#machine_state{ay_module = undefined}) -> "";
ay_regs_str(#machine_state{ay_module = AyModule, ay = Ay}) ->
    string:join([integer_to_list(B) || B <- AyModule:regs(Ay)], ",").

meta_int(Str, Default) ->
    try list_to_integer(Str)
    catch _:_ -> Default
    end.

apply_beeper(Machine, Meta) ->
    case maps:get("beeper_level", Meta, undefined) of
        undefined -> Machine;
        L ->
            BeeperModule = Machine#machine_state.beeper_module,
            Machine#machine_state{beeper = BeeperModule:init(meta_int(L, 0))}
    end.

apply_ay(Machine, Meta) ->
    case {Machine#machine_state.ay_module, maps:get("ay_regs", Meta, undefined)} of
        {undefined, _} -> Machine;
        {_, undefined} -> Machine;
        {AyModule, RegsStr} ->
            Regs = parse_regs(RegsStr),
            case length(Regs) of
                16 -> Machine#machine_state{ay = AyModule:set_regs(
                    Machine#machine_state.ay, Regs)};
                _ -> Machine
            end
    end.

parse_regs(Str) ->
    [begin
        try list_to_integer(string:trim(S))
        catch _:_ -> 0
        end
     end || S <- string:split(Str, ",", all), S =/= <<>>].

%% @doc Turn a human-facing name into a filesystem-safe file base name.
%% Printable characters survive (Unicode included); control characters and
%% the filesystem-hostile set `/\:*?"<>|` become spaces; whitespace collapses;
%% leading dots (hidden files) and trailing dots/spaces (Windows quirk) are
%% dropped; the result is capped so a stamp suffix always fits. An input that
%% sanitizes to nothing stays empty so callers can fall back to a pure stamp.
sanitize_filename(S) ->
    Clean = [sanitize_char(C) || C <- S],
    Collapsed = collapse_spaces(string:trim(Clean)),
    Safe = strip_dots(Collapsed),
    case Safe of
        [] -> "";
        _ -> lists:sublist(Safe, ?NAME_MAX_LEN)
    end.

sanitize_char(C) when C < 16#20; C =:= 16#7F -> $\s;
sanitize_char($/) -> $\s;
sanitize_char($\\) -> $\s;
sanitize_char($:) -> $\s;
sanitize_char($*) -> $\s;
sanitize_char($?) -> $\s;
sanitize_char($") -> $\s;
sanitize_char($<) -> $\s;
sanitize_char($>) -> $\s;
sanitize_char($|) -> $\s;
sanitize_char(C) -> C.

collapse_spaces(S) ->
    lists:reverse(collapse_spaces_1(S, [])).

collapse_spaces_1([], Acc) -> Acc;
collapse_spaces_1([$\s, $\s | Rest], Acc) -> collapse_spaces_1([$\s | Rest], Acc);
collapse_spaces_1([C | Rest], Acc) -> collapse_spaces_1(Rest, [C | Acc]).

strip_dots(S) ->
    NoLeading = lists:dropwhile(fun(C) -> C =:= $. end, S),
    lists:reverse(lists:dropwhile(fun(C) -> C =:= $. orelse C =:= $\s end,
                                  lists:reverse(NoLeading))).

write_save(Z80Path, Machine, Source) ->
    Meta = build_meta(Machine, Source),
    filelib:ensure_dir(filename:join(filename:dirname(Z80Path), "dummy")),
    write_two(Z80Path, meta_path(Z80Path), Machine, Meta).

write_two(Z80Path, MetaPath, Machine, Meta) ->
    {ok, Z80} = serialize_z80(Machine),
    case file:write_file(Z80Path, Z80) of
        ok -> file:write_file(MetaPath, meta_to_iodata(Meta));
        {error, _} = Err -> Err
    end.

meta_path(Z80Path) ->
    filename:rootname(Z80Path) ++ ".meta".

quick_path_z80(SavesRoot) ->
    filename:join(SavesRoot, ?QUICK_STAMP ++ ?SAVE_EXT).

archive_path(SavesRoot, Source) ->
    Stamp = stamp_now(),
    available_path(filename:join(SavesRoot,
                                 program_name(Source) ++ "-quicksave-" ++ Stamp ++ ?SAVE_EXT),
                   0).

%% @doc The file base for a named save: `<sanitized name>-<stamp>`, or just
%% `<stamp>` when the name is empty or sanitizes to nothing.
history_base(Name, Stamp) ->
    case sanitize_filename(Name) of
        "" -> Stamp;
        Clean -> Clean ++ "-" ++ Stamp
    end.

%% @doc The `.z80` path for a new named save, uniquified if a file with the
%% same base already exists (same-second saves with the same name).
history_path(SavesRoot, Name, Stamp) ->
    available_path(filename:join(SavesRoot,
                                 history_base(Name, Stamp) ++ ?SAVE_EXT), 0).

available_path(Z80, N) ->
    case filelib:is_regular(Z80) of
        false -> Z80;
        true ->
            Base = filename:rootname(filename:basename(Z80)),
            available_path(filename:join(filename:dirname(Z80),
                                         Base ++ "-" ++ integer_to_list(N + 1) ++ ?SAVE_EXT),
                           N + 1)
    end.

history_name(SavesRoot, Stamp) ->
    case read_meta(filename:join(SavesRoot, Stamp ++ ".meta")) of
        undefined -> "";
        Meta -> maps:get("name", Meta, "")
    end.

%% @doc Stamps newest first by modification time, with the fixed quick slot
%% pinned to the front.
sort_by_mtime(SavesRoot, Stamps) ->
    Timed = [{mtime(SavesRoot, St), St} || St <- Stamps],
    Sorted = [St || {_, St} <- lists:reverse(lists:keysort(1, Timed))],
    case lists:delete(?QUICK_STAMP, Sorted) of
        Sorted -> Sorted;
        Rest -> [?QUICK_STAMP | Rest]
    end.

mtime(SavesRoot, Stamp) ->
    case file:read_file_info(filename:join(SavesRoot, Stamp ++ ".z80")) of
        {ok, Info} -> Info#file_info.mtime;
        _ -> {{0, 0, 0}, {0, 0, 0}}
    end.

stamp_now() ->
    {{Y, Mo, D}, {H, Mi, S}} = calendar:local_time(),
    lists:flatten(io_lib:format("~4..0B~2..0B~2..0B-~2..0B~2..0B~2..0B",
                                [Y, Mo, D, H, Mi, S])).
