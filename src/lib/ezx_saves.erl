-module(ezx_saves).

%% @doc Quick save / load and save-history support for the ezx emulator.
%%
%% A save is a pair of files with a shared base name:
%%   - a `.z80` snapshot binary (Fuse-compatible) — or, for the machines whose
%%     state exceeds the Z80 format (Pentagon 512K / 1024K), an `.ezs` state
%%     container: the emulator's own, fully self-contained format holding
%%     CPU, border, AY registers, every wired RAM bank and the paging/audio
%%     latches (see ezx_ezs) — and
%%   - a `.meta` sidecar (key=value text, one entry per line) that stores
%%     what the binary does not: the beeper level, the machine type, the
%%     sound chip, the source game file, and the save timestamp (for .z80
%%     saves also the AY registers, which Z80 cannot carry).
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
%% (or "Basic" when nothing is loaded) and <stamp> = YYYYMMDD-HHMMSS. The
%% archive copy carries the human name `<Program> - Quicksave` in its meta
%% (shown by the manager dialog); the fixed slot keeps its `Last Quicksave`
%% identity. F2 named saves are `<Name>-<stamp>` files (the name sanitized to
%% a filesystem-safe form, the stamp keeping them unique), carrying the full
%% human `name` in the meta (shown by the manager dialog). list_history/1
%% lists every `.z80`/`.ezs` save in the root, newest first (the fixed quick
%% slot sorts to the top); older `.sna` saves are ignored.
%%
%% All filesystem functions take the saves root explicitly so tests can point
%% them at a temporary directory; the UI passes ezx_ui_lib:app_dir()/saves.

-export([
    serialize/1,
    serialize_z80/1,
    to_z80_header/1,
    serialize_ezs/1,
    to_ezs_container/1,
    apply_container/2,
    load_container/2,
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
    archive_path/3,
    save_history/4,
    list_history/1,
    delete_history/2,
    rename_history/3,
    png_path/1
]).

-include("z80_records.hrl").
-include("ezx_emulator.hrl").
-include("lib/z80.hrl").
-include_lib("kernel/include/file.hrl").

-define(QUICK_STAMP, "Last Quicksave").
-define(SAVE_EXT, ".z80").
-define(STATE_EXT, ".ezs").
%% Snapshot extensions understood on disk; the extension of a NEW save file
%% follows the machine type (save_ext/1).
-define(SAVE_EXTS, [".z80", ?STATE_EXT]).
-define(DEFAULT_PROGRAM, "Basic").
-define(NAME_MAX_LEN, 60).

%% @doc Serialize a machine for a save: the Z80 format where it suffices, the
%% ezx state container for the Pentagon models with RAM beyond banks 0-7.
-spec serialize(#machine_state{}) -> {ok, binary()}.
serialize(Machine) ->
    case machine_type(Machine) of
        T when T =:= 'pentagon_512'; T =:= 'pentagon_1024' -> serialize_ezs(Machine);
        _ -> serialize_z80(Machine)
    end.

%% @doc Build an .ezs state container: the emulator's own, fully
%% self-contained snapshot (see ezx_ezs) — CPU, border, the whole AY register
%% file, every wired RAM bank and the #7FFD / #EFF7 / TR-DOS latches.
-spec serialize_ezs(#machine_state{}) -> {ok, binary()}.
serialize_ezs(Machine) ->
    {ok, ezx_ezs:compose(to_ezs_container(Machine))}.

%% @doc Capture a machine state as an .ezs container map, ready for
%% ezx_ezs:compose/1.
-spec to_ezs_container(#machine_state{}) -> ezx_ezs:container().
to_ezs_container(Machine) ->
    #{type => machine_type(Machine),
      p7ffd => p7ffd_or_zero(Machine),
      eff7 => eff7_or_zero(Machine),
      dos_rom => case dos_rom_or_false(Machine) of true -> 1; false -> 0 end,
      border => ezx_screen:border_get(Machine#machine_state.screen),
      cpu => cpu_map(Machine),
      ay => ay_map(Machine),
      banks => ezs_banks(Machine)}.

p7ffd_or_zero(Machine) ->
    case machine_type(Machine) of
        '48k' -> 0;
        _ -> (Machine#machine_state.memory_module):get_p7ffd(
               Machine#machine_state.memory)
    end.

eff7_or_zero(Machine) ->
    case machine_type(Machine) of
        T when T =:= 'pentagon_512'; T =:= 'pentagon_1024' ->
            (Machine#machine_state.memory_module):get_eff7(
              Machine#machine_state.memory);
        _ -> 0
    end.

dos_rom_or_false(Machine) ->
    case machine_type(Machine) of
        T when T =:= 'pentagon_128'; T =:= 'pentagon_512'; T =:= 'pentagon_1024' ->
            (Machine#machine_state.memory_module):get_dos_rom(
              Machine#machine_state.memory);
        _ -> false
    end.

cpu_map(#machine_state{cpu = C}) ->
    #{a => C#cpu_state.a, f => C#cpu_state.f,
      b => C#cpu_state.b, c => C#cpu_state.c,
      d => C#cpu_state.d, e => C#cpu_state.e,
      h => C#cpu_state.h, l => C#cpu_state.l,
      a_alt => C#cpu_state.a_alt, f_alt => C#cpu_state.f_alt,
      b_alt => C#cpu_state.b_alt, c_alt => C#cpu_state.c_alt,
      d_alt => C#cpu_state.d_alt, e_alt => C#cpu_state.e_alt,
      h_alt => C#cpu_state.h_alt, l_alt => C#cpu_state.l_alt,
      i => C#cpu_state.i, r => C#cpu_state.r,
      ixh => C#cpu_state.ixh, ixl => C#cpu_state.ixl,
      iyh => C#cpu_state.iyh, iyl => C#cpu_state.iyl,
      sp => C#cpu_state.sp, pc => C#cpu_state.pc,
      iff1 => C#cpu_state.iff1, iff2 => C#cpu_state.iff2,
      im => C#cpu_state.im,
      halted => case C#cpu_state.halted of true -> 1; false -> 0 end}.

ay_map(#machine_state{ay_module = undefined}) ->
    undefined;
ay_map(#machine_state{ay_module = AyModule, ay = Ay}) ->
    #{selected => AyModule:selected(Ay),
      regs => list_to_binary(AyModule:regs(Ay))}.

%% The bank order matches ezx_ezs:banks_for_type/1: the flat 48K space is
%% stored as its three RAM pages in address order; every other type stores
%% its wired banks 0 upward.
ezs_banks(#machine_state{memory_module = MemModule, memory = Mem} = Machine) ->
    case machine_type(Machine) of
        '48k' ->
            <<P4000:16384/binary, P8000:16384/binary, PC000:16384/binary>> =
                MemModule:read_block(Mem, 16#4000, 49152),
            [P4000, P8000, PC000];
        T ->
            [MemModule:read_bank_block(Mem, B)
             || B <- lists:seq(0, ezx_ezs:banks_for_type(T) - 1)]
    end.

%% @doc Load an .ezs file into a fresh machine: parse plus error mapping
%% around apply_container/2. This is the shared implementation behind the
%% emulators' load_ezs/2 capability.
-spec load_container(#machine_state{}, binary()) ->
    {ok, #machine_state{}} | {error, {Error, Details::binary()}} when
    Error :: unsupported_format | unsupported_version | bad_ezs.
load_container(Machine0, Data) ->
    case ezx_ezs:parse(Data) of
        {ok, Container} ->
            apply_container(Machine0, Container);
        {error, {bad_magic, _}} ->
            {error, {unsupported_format, <<"not an EZS container">>}};
        {error, {unsupported_version, Detail}} ->
            {error, {unsupported_version, Detail}};
        {error, {bad_size, Detail}} ->
            {error, {bad_ezs, Detail}}
    end.

%% @doc Restore a fresh machine of the container's type from a parsed .ezs
%% container map (the inverse of to_ezs_container/1). Banks beyond the
%% model's wired RAM would be ignored by write_bank_block, but a mismatch
%% cannot arise anyway: the loader builds the machine from the container's
%% own type code.
-spec apply_container(#machine_state{}, ezx_ezs:container()) ->
    {ok, #machine_state{}} | {error, {bad_ezs, binary()}}.
apply_container(Machine0, #{type := Type} = Container) ->
    case machine_type(Machine0) of
        Type ->
            Memory = apply_memory(Machine0, Container),
            Screen = ezx_screen:new(maps:get(border, Container)),
            Cpu = apply_cpu(Container, Machine0#machine_state.cpu),
            Machine1 = Machine0#machine_state{
                memory = Memory,
                screen = Screen,
                cpu = Cpu,
                t_states = 0,
                beeper_pcm = <<>>,
                ay = apply_ay_state(Machine0, maps:get(ay, Container))},
            {ok, Machine1};
        Other ->
            {error, {bad_ezs, iolist_to_binary(
                ["container is for ", atom_to_binary(Type),
                 ", machine is ", atom_to_binary(Other)])}}
    end.

apply_memory(Machine0, #{type := Type, p7ffd := P7ffd, eff7 := Eff7,
                         dos_rom := DosRom, banks := Banks}) ->
    MemModule = Machine0#machine_state.memory_module,
    Mem = Machine0#machine_state.memory,
    case Type of
        '48k' ->
            [P4000, P8000, PC000] = Banks,
            M1 = write_flat(MemModule, Mem, 16#4000, P4000),
            M2 = write_flat(MemModule, M1, 16#8000, P8000),
            write_flat(MemModule, M2, 16#C000, PC000);
        T ->
            Banked = lists:foldl(
                fun({Bank, BankBin}, Acc) ->
                    MemModule:write_bank_block(Acc, Bank, BankBin)
                end, Mem, lists:zip(lists:seq(0, length(Banks) - 1), Banks)),
            case T of
                '128k' ->
                    MemModule:write_port_7ffd(Banked, P7ffd);
                'pentagon_128' ->
                    M1 = MemModule:set_dos_rom(Banked, DosRom =:= 1),
                    MemModule:write_port_7ffd(M1, P7ffd);
                Pent when Pent =:= 'pentagon_512'; Pent =:= 'pentagon_1024' ->
                    %% Latches first, #7FFD last: the routing rebuild it
                    %% triggers must see the final #EFF7 value (the D5 page
                    %% bit only counts in 1MB mode).
                    M1 = MemModule:set_dos_rom(Banked, DosRom =:= 1),
                    M2 = MemModule:write_port_eff7(M1, Eff7),
                    MemModule:write_port_7ffd(M2, P7ffd)
            end
    end.

write_flat(MemModule, Mem, Base, Bin) ->
    {_, MemFinal} = lists:foldl(
        fun(Byte, {Offset, Acc}) ->
            {Offset + 1, MemModule:write_byte(Acc, Base + Offset, Byte)}
        end, {0, Mem}, binary:bin_to_list(Bin)),
    MemFinal.

apply_cpu(#{cpu := Map}, Cpu) ->
    Cpu#cpu_state{
        a = m(a, Map), f = m(f, Map), b = m(b, Map), c = m(c, Map),
        d = m(d, Map), e = m(e, Map), h = m(h, Map), l = m(l, Map),
        a_alt = m(a_alt, Map), f_alt = m(f_alt, Map),
        b_alt = m(b_alt, Map), c_alt = m(c_alt, Map),
        d_alt = m(d_alt, Map), e_alt = m(e_alt, Map),
        h_alt = m(h_alt, Map), l_alt = m(l_alt, Map),
        i = m(i, Map), r = m(r, Map),
        ixh = m(ixh, Map), ixl = m(ixl, Map),
        iyh = m(iyh, Map), iyl = m(iyl, Map),
        sp = m(sp, Map), pc = m(pc, Map),
        iff1 = m(iff1, Map), iff2 = m(iff2, Map), im = m(im, Map),
        halted = m(halted, Map) =:= 1,
        pending_interrupt = none}.

m(Key, Map) -> maps:get(Key, Map).

apply_ay_state(#machine_state{ay_module = undefined}, _AyMap) ->
    undefined;
apply_ay_state(_Machine, undefined) ->
    undefined;
apply_ay_state(#machine_state{ay_module = AyModule, ay = Ay},
               #{selected := Selected, regs := Regs}) ->
    AyModule:latch(AyModule:set_regs(Ay, binary_to_list(Regs)), Selected).


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
        T when T =:= '128k'; T =:= 'pentagon_128';
               T =:= 'pentagon_512'; T =:= 'pentagon_1024' ->
            %% Pentagon models share the 128K snapshot layout (banks 0-7 +
            %% the p7FFD byte); their extra RAM banks and #EFF7 state are not
            %% representable in the Z80 format and reset on load.
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

%% The machine carries its identity explicitly (set at creation by the
%% emulator's init), so the save paths never have to guess the type from
%% memory-module capabilities or raster constants.
-spec machine_type(#machine_state{}) -> '48k' | '128k' | 'pentagon_128' | 'pentagon_512' | 'pentagon_1024'.
machine_type(#machine_state{machine_type = Type}) -> Type.

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
%% save without a meta sidecar reads the snapshot itself — an .ezs container
%% declares its type in the header, a Z80 file is detected by its extended
%% header's hw_mode, a SNA file by its size (a 48K SNA is exactly
%% 27 + 49152 bytes; anything larger is a 128K snapshot), matching
%% libspectrum's identify_machine.
save_machine_type(undefined, Path) ->
    case file:read_file(Path) of
        {ok, Data} -> data_machine_type(Data, filename:extension(Path));
        _ -> '48k'
    end;
save_machine_type(Meta, _Path) ->
    case maps:get("machine_type", Meta, undefined) of
        "128k" -> '128k';
        "pentagon_128" -> 'pentagon_128';
        "pentagon_512" -> 'pentagon_512';
        "pentagon_1024" -> 'pentagon_1024';
        _ -> '48k'
    end.

data_machine_type(Data, Ext) ->
    case ezx_ezs:is_container(Data) of
        true ->
            case ezx_ezs:parse(Data) of
                {ok, #{type := Type}} -> Type;
                _ -> '48k'
            end;
        false ->
            case string:lowercase(Ext) of
                ".z80" -> z80_data_type(Data);
                _ -> sna_data_type(Data)
            end
    end.

z80_data_type(Data) ->
    try ezx_z80:parse(Data) of
        #z80_header{is_128k = true} -> '128k';
        _ -> '48k'
    catch
        _:_ -> '48k'
    end.

sna_data_type(Data) when byte_size(Data) > 27 + 49152 -> '128k';
sna_data_type(_Data) -> '48k'.

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
%% an archive copy named <Program>-quicksave-<stamp>. The serializers have no
%% failure case (PC is stored explicitly). The slot keeps the plain machine
%% meta (its fixed file name is its identity, shown by the manager dialog);
%% only the archive copy carries the human name `<Program> - Quicksave`.
%% Returns the path of the archive copy actually written, so the caller can
%% address its sidecars (e.g. the screenshot) without recomputing the
%% timestamped, uniquified file name.
-spec quick_save(#machine_state{}, string(), string()) ->
    {ok, string()} | {error, term()}.
quick_save(Machine, SavesRoot, Source) ->
    Ext = save_ext(Machine),
    SlotMeta = build_meta(Machine, Source),
    ArchiveMeta = SlotMeta#{"name" => quick_name(Source)},
    case write_save(snapshot_path(SavesRoot, ?QUICK_STAMP, Ext), Machine, SlotMeta) of
        ok ->
            Archive = archive_path(SavesRoot, Source, Ext),
            filelib:ensure_dir(filename:join(SavesRoot, "dummy")),
            case write_two(Archive, meta_path(Archive), Machine, ArchiveMeta) of
                ok -> {ok, Archive};
                {error, _} = Err -> Err
            end;
        Err ->
            Err
    end.

%% @doc Human name for the quick-save archive copy.
quick_name(Source) ->
    program_name(Source) ++ " - Quicksave".

%% @doc Paths for the fixed quick slot, or `none' when no quick save exists
%% yet. The slot may exist in either snapshot extension (it follows the last
%% saved machine type); the newest file wins.
-spec quick_path(string()) -> {ok, string(), string()} | none.
quick_path(SavesRoot) ->
    Candidates = [filename:join(SavesRoot, ?QUICK_STAMP ++ Ext)
                  || Ext <- ?SAVE_EXTS, filelib:is_regular(filename:join(SavesRoot,
                                                                          ?QUICK_STAMP ++ Ext))],
    case Candidates of
        [] -> none;
        _ ->
            SnapPath = latest_snapshot(Candidates),
            {ok, SnapPath, meta_path(SnapPath)}
    end.

%% @doc The newest of the existing snapshot paths by modification time; on
%% equal times the later candidate wins (the candidates are ordered .z80
%% before .ezs, so the richer container is preferred deterministically).
latest_snapshot([Best | Rest]) ->
    latest_snapshot(Rest, Best).

latest_snapshot([], Best) ->
    Best;
latest_snapshot([Path | Rest], Best) ->
    case mtime(Path) >= mtime(Best) of
        true -> latest_snapshot(Rest, Path);
        false -> latest_snapshot(Rest, Best)
    end.

mtime(Path) ->
    case file:read_file_info(Path) of
        {ok, Info} -> Info#file_info.mtime;
        _ -> {{0, 0, 0}, {0, 0, 0}}
    end.

%% @doc Append a history entry. The file is named `<name>-<stamp><ext>` (the
%% name sanitized to a filesystem-safe form, the extension following the
%% machine type) so it can be found on disk; the stamp suffix keeps names
%% unique. An empty name falls back to `<stamp><ext>`.
%% The human name is also kept in the meta, where the manager dialog reads it.
-spec save_history(#machine_state{}, string(), string(), string()) ->
    {ok, string()} | {error, term()}.
save_history(Machine, SavesRoot, Source, Name) ->
    filelib:ensure_dir(filename:join(SavesRoot, "dummy")),
    Stamp = stamp_now(),
    SnapPath = history_path(SavesRoot, Name, Stamp, save_ext(Machine)),
    Meta0 = build_meta(Machine, Source),
    Meta = (Meta0#{"name" => case sanitize_filename(Name) of
        "" -> Stamp;
        _ -> Name
    end})#{"timestamp" => Stamp},
    case write_two(SnapPath, meta_path(SnapPath), Machine, Meta) of
        ok -> {ok, SnapPath};
        {error, _} = Err -> Err
    end.

%% @doc Every save in the root, newest first (sorted by file modification
%% time as a proxy for creation time); the fixed quick slot is always listed
%% first. Entries are [{Base, Name, Timestamp, SnapPath, MetaPath}] where Base
%% is the file base (`<name>-<stamp>' for named saves) used to address the
%% files, and Name/Timestamp are the display fields from the save's meta.
%% Both `.z80` and `.ezs` saves are listed; when a base exists in both
%% extensions (a quick slot saved from different machine types), only the
%% newest file is listed. Older `.sna` saves are ignored.
-spec list_history(string()) ->
    [{string(), string(), string(), string(), string()}].
list_history(SavesRoot) ->
    case file:list_dir(SavesRoot) of
        {ok, Names} ->
            Snaps = [N || N <- Names,
                          lists:member(filename:extension(N), ?SAVE_EXTS)],
            Best = newest_per_base(SavesRoot, lists:sort(Snaps)),
            Sorted = sort_newest_first(SavesRoot, Best),
            [history_entry(filename:join(SavesRoot, N)) || N <- Sorted];
        {error, enoent} -> []
    end.

%% @doc One file per base name: when both extensions exist for a base, keep
%% the newest (ties resolved deterministically by name order).
newest_per_base(SavesRoot, Snaps) ->
    Fold = fun(N, Acc) ->
        Base = filename:rootname(N),
        case Acc of
            #{Base := Old} ->
                case newer(SavesRoot, N, Old) of
                    true -> Acc#{Base => N};
                    false -> Acc
                end;
            _ -> Acc#{Base => N}
        end
    end,
    maps:values(lists:foldl(Fold, #{}, Snaps)).

newer(SavesRoot, A, B) ->
    {mtime_name(SavesRoot, A), A} > {mtime_name(SavesRoot, B), B}.

%% @doc Delete a save (the snapshot in either extension, plus its sidecars).
-spec delete_history(string(), string()) -> ok | {error, term()}.
delete_history(SavesRoot, Stamp) ->
    SnapPaths = [filename:join(SavesRoot, Stamp ++ Ext) || Ext <- ?SAVE_EXTS],
    MetaPath = filename:join(SavesRoot, Stamp ++ ".meta"),
    PngPath = png_path(hd(SnapPaths)),
    Results = [file:delete(P) || P <- SnapPaths ++ [MetaPath, PngPath]],
    case [R || R <- Results, R =/= ok, R =/= {error, enoent}] of
        [] -> ok;
        [{error, Reason} | _] -> {error, Reason}
    end.

%% @doc Rename a save: the snapshot (in whatever extension it lives) and its
%% `.meta` pair are moved to the new `<name>-<stamp><ext>` base (same stamp,
%% so the save's identity survives) and the meta `name' field is rewritten.
%% Renaming to the same name only updates the meta.
-spec rename_history(string(), string(), string()) -> ok | {error, term()}.
rename_history(SavesRoot, Stamp, NewName) ->
    MetaPath = filename:join(SavesRoot, Stamp ++ ".meta"),
    case read_meta(MetaPath) of
        undefined ->
            {error, enoent};
        Meta ->
            case newest_snapshot(SavesRoot, Stamp) of
                undefined ->
                    {error, enoent};
                OldSnap ->
                    Timestamp = maps:get("timestamp", Meta, Stamp),
                    Meta1 = Meta#{"name" => case NewName of
                        "" -> Timestamp;
                        _ -> NewName
                    end},
                    OldBase = filename:rootname(filename:basename(OldSnap)),
                    rename_snapshot(OldSnap, OldBase,
                                    history_base(NewName, Timestamp), Meta1)
            end
    end.

%% Same base: only the meta changes.
rename_snapshot(SnapPath, Base, Base, Meta1) ->
    file:write_file(meta_path(SnapPath), meta_to_iodata(Meta1));
rename_snapshot(SnapPath, _OldBase, NewBase, Meta1) ->
    SavesRoot = filename:dirname(SnapPath),
    Ext = filename:extension(SnapPath),
    NewSnap = available_path(filename:join(SavesRoot, NewBase), Ext, 0),
    case file:rename(SnapPath, NewSnap) of
        ok ->
            file:write_file(meta_path(NewSnap), meta_to_iodata(Meta1)),
            file:delete(meta_path(SnapPath)),
            _ = case filelib:is_regular(png_path(SnapPath)) of
                true -> file:rename(png_path(SnapPath), png_path(NewSnap));
                false -> ok
            end,
            ok;
        {error, _} = Err -> Err
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

write_save(Z80Path, Machine, Meta) ->
    filelib:ensure_dir(filename:join(filename:dirname(Z80Path), "dummy")),
    write_two(Z80Path, meta_path(Z80Path), Machine, Meta).

write_two(SnapPath, MetaPath, Machine, Meta) ->
    {ok, Snap} = serialize(Machine),
    %% The .ezs container carries the AY register file itself, so its meta
    %% does not duplicate it (a stale-looking copy would also be re-applied
    %% on load and clobber the container's latched register).
    Meta1 = case save_ext(Machine) of
        ?STATE_EXT -> maps:remove("ay_regs", Meta);
        _ -> Meta
    end,
    case file:write_file(SnapPath, Snap) of
        ok -> file:write_file(MetaPath, meta_to_iodata(Meta1));
        {error, _} = Err -> Err
    end.

meta_path(Z80Path) ->
    filename:rootname(Z80Path) ++ ".meta".

%% @doc The extension a NEW save of this machine gets: the .ezs container for
%% the machines Z80 cannot fully represent, plain .z80 otherwise.
save_ext(Machine) ->
    case machine_type(Machine) of
        T when T =:= 'pentagon_512'; T =:= 'pentagon_1024' -> ?STATE_EXT;
        _ -> ?SAVE_EXT
    end.

snapshot_path(SavesRoot, Base, Ext) ->
    filename:join(SavesRoot, Base ++ Ext).

archive_path(SavesRoot, Source, Ext) ->
    Stamp = stamp_now(),
    Base = filename:join(SavesRoot,
                         program_name(Source) ++ "-quicksave-" ++ Stamp),
    available_path(Base, Ext, 0).

%% @doc The screenshot sidecar for a save: same base as the `.z80`, with a
%% `.png` extension. The file is written by the UI at save time (best-effort);
%% older saves may not have one, so consumers must fall back to a placeholder.
png_path(Z80Path) ->
    filename:rootname(Z80Path) ++ ".png".

%% @doc The file base for a named save: `<sanitized name>-<stamp>`, or just
%% `<stamp>` when the name is empty or sanitizes to nothing.
history_base(Name, Stamp) ->
    case sanitize_filename(Name) of
        "" -> Stamp;
        Clean -> Clean ++ "-" ++ Stamp
    end.

%% @doc The snapshot path for a new named save, uniquified if a file with the
%% same base and extension already exists (same-second saves, same name).
history_path(SavesRoot, Name, Stamp, Ext) ->
    Base = filename:join(SavesRoot, history_base(Name, Stamp)),
    available_path(Base, Ext, 0).

available_path(PathBase, Ext, N) ->
    %% PathBase carries no extension; the uniquifier suffix grows with N.
    Candidate = PathBase ++ suffix(N) ++ Ext,
    case filelib:is_regular(Candidate) of
        false -> Candidate;
        true -> available_path(PathBase, Ext, N + 1)
    end.

suffix(0) -> [];
suffix(N) -> lists:flatten(["-", integer_to_list(N)]).

%% @doc The newest existing snapshot for a base (both extensions considered);
%% `undefined' when none exists.
newest_snapshot(SavesRoot, Base) ->
    Existing = [filename:join(SavesRoot, Base ++ Ext)
                || Ext <- ?SAVE_EXTS,
                   filelib:is_regular(filename:join(SavesRoot, Base ++ Ext))],
    case Existing of
        [] -> undefined;
        _ -> latest_snapshot(Existing)
    end.

history_entry(SnapPath) ->
    Base = filename:rootname(filename:basename(SnapPath)),
    {Name, Timestamp} = case read_meta(meta_path(SnapPath)) of
        undefined -> {"", ""};
        Meta -> {maps:get("name", Meta, ""), maps:get("timestamp", Meta, "")}
    end,
    {Base, Name, Timestamp, SnapPath, meta_path(SnapPath)}.

%% @doc Snapshot file names newest first by modification time, with the fixed
%% quick slot pinned to the front.
sort_newest_first(SavesRoot, Names) ->
    Timed = [{mtime_name(SavesRoot, N), N} || N <- Names],
    Sorted = [N || {_, N} <- lists:reverse(lists:keysort(1, Timed))],
    case lists:splitwith(fun(N) -> filename:rootname(N) =/= ?QUICK_STAMP end,
                         Sorted) of
        {_, []} -> Sorted;
        {Before, [Quick | After]} -> [Quick | Before] ++ After
    end.

mtime_name(SavesRoot, Name) ->
    mtime(filename:join(SavesRoot, Name)).

stamp_now() ->
    {{Y, Mo, D}, {H, Mi, S}} = calendar:local_time(),
    lists:flatten(io_lib:format("~4..0B~2..0B~2..0B-~2..0B~2..0B~2..0B",
                                [Y, Mo, D, H, Mi, S])).
