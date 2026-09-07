-module(ezx_ui_lib).

-include("ezx_emulator.hrl").

-export([init_virtual_machine/1, init_virtual_machine/2, load_emulator_file/3,
         app_dir/0, priv_dir/0,
         rom_types/0, machine_type_label/1, rom_slots/1,
         configured_rom_path/2, default_rom_path/2, set_rom_paths/2]).

%% @doc App state directory for persistent per-user data (recent files, dumps).
%% Follows the XDG state dir on Unix and LocalAppData/AppData on Windows, so
%% dumps land in a real per-user location instead of /tmp.
-spec app_dir() -> string().
app_dir() ->
    Dir = case erlang:system_info(os_type) of
        {unix, _} ->
            case os:getenv("XDG_STATE_HOME") of
                false ->
                    filename:join([os:getenv("HOME"), ".local", "state", "ezx"]);
                Xdg ->
                    filename:join(Xdg, "ezx")
            end;
        {win32, _} ->
            case os:getenv("LOCALAPPDATA") of
                false ->
                    case os:getenv("APPDATA") of
                        false -> filename:join([os:getenv("USERPROFILE"), "AppData", "Local", "ezx"]);
                        AppData -> filename:join(AppData, "ezx")
                    end;
                Local -> filename:join(Local, "ezx")
            end
    end,
    filelib:ensure_dir(filename:join(Dir, "dummy")),
    Dir.

-spec init_virtual_machine(atom()) -> {ok, #machine_state{}} | {error, {Error, Details::binary()}} when
    Error :: rom_not_found | rom_bad_size | bad_machine_type.
init_virtual_machine(MachineType) ->
    init_virtual_machine(MachineType, ay).

%% @doc Create a fresh machine of the given type using the configured sound
%% chip ('ay' AY-3-8912, 'ym' YM2149, or 'off' for a machine without an AY
%% device).
-spec init_virtual_machine(atom(), ay | ym | off) -> {ok, #machine_state{}} | {error, {Error, Details::binary()}} when
    Error :: rom_not_found | rom_bad_size | bad_machine_type.
init_virtual_machine('128k', Chip) ->
    case catch {read_rom_file(configured_rom_path('128k', 0), 0),
                read_rom_file(configured_rom_path('128k', 1), 1)} of
        {{ok, Rom0}, {ok, Rom1}} ->
            BaseModel = ?SPECTRUM_128_MODEL,
            Model = BaseModel#machine_model{ay_chip = ay_chip_value(Chip)},
            M = ezx_emulator_128:init(Model, z80_cpu, ezx_memory_128_banks_tuples, ezx_keyboard, ezx_beeper2, ay_module(Chip), {Rom0, Rom1}),
            {ok, ezx_emulator:set_render_screen(M, true)};
        {'EXIT', {rom_missing, _}} ->
            {error, {rom_not_found, <<"128K ROMs not found (128-0.rom, 128-1.rom)">>}};
        {'EXIT', {rom_bad_size, _}} ->
            {error, {rom_bad_size, <<"128K ROM images must hold 16384 bytes per slot">>}}
    end;
%% Pentagon 128K/512K/1024K share one timing model and one emulator module;
%% they differ in the wired RAM size (8/32/64 banks) and the ROM set: the two
%% BASICs are required, the TR-DOS ROM is an optional extra mapped through the
%% Pentagon paging (ezx_memory_pentagon).
init_virtual_machine(Type, Chip) when Type =:= 'pentagon_128';
                                      Type =:= 'pentagon_512';
                                      Type =:= 'pentagon_1024' ->
    BaseModel = ?PENTAGON_128_MODEL,
    Model = BaseModel#machine_model{ay_chip = ay_chip_value(Chip)},
    case catch {read_rom_file(configured_rom_path(Type, 0), 0),
                read_rom_file(configured_rom_path(Type, 1), 1)} of
        {{ok, Rom0}, {ok, Rom1}} ->
            Dos = read_optional_rom_file(configured_rom_path(Type, 2), 2),
            M = ezx_emulator_pentagon:init(Model, z80_cpu, ezx_memory_pentagon,
                                           ezx_keyboard, ezx_beeper2, ay_module(Chip),
                                           {Rom0, Rom1, Dos, Type}),
            {ok, ezx_emulator:set_render_screen(M, true)};
        {'EXIT', {rom_missing, _}} ->
            {error, {rom_not_found,
                     iolist_to_binary(["Pentagon ROMs not found (",
                                       configured_rom_path(Type, 0), ", ",
                                       configured_rom_path(Type, 1), ")"])}};
        {'EXIT', {rom_bad_size, _}} ->
            {error, {rom_bad_size, <<"Pentagon ROM images must hold 16384 bytes per slot">>}}
    end;
init_virtual_machine('48k', Chip) ->
    case catch read_rom_file(configured_rom_path('48k', 0), 0) of
        {ok, Rom} ->
            BaseModel = ?SPECTRUM_48_MODEL,
            Model = BaseModel#machine_model{ay_chip = ay_chip_value(Chip)},
            M = ezx_emulator:init(Model, z80_cpu, ezx_memory_48_pages512_tuples, ezx_keyboard, ezx_beeper2, ay_module(Chip), Rom),
            {ok, ezx_emulator:set_render_screen(M, true)};
        {'EXIT', {rom_missing, _}} ->
            {error, {rom_not_found, <<"48K ROM not found (48.rom)">>}};
        {'EXIT', {rom_bad_size, _}} ->
            {error, {rom_bad_size, <<"48K ROM image must hold at least 16384 bytes">>}}
    end;
init_virtual_machine(Bad, _Chip) ->
    {error, {bad_machine_type, iolist_to_binary(io_lib:format("~p", [Bad]))}}.

%% @doc AY device module for the chip choice; 'off' creates a machine without
%% an AY device at all (the port handlers then fall through to the defaults).
-spec ay_module(ay | ym | off) -> module() | undefined.
ay_module(off) -> undefined;
ay_module(_) -> ezx_ay38912_seg.

%% @doc The model's ay_chip field only describes the device variant; a
%% chip-less machine keeps the default (the absent device is the "off" signal).
-spec ay_chip_value(ay | ym | off) -> ay | ym.
ay_chip_value(off) -> ay;
ay_chip_value(Chip) -> Chip.

%% --- ROM paths ---
%%
%% Every machine type owns its ROM slots in the config as `rom_<type>_<slot>'
%% keys (string values). An absent or empty key falls back to the bundled ROM
%% in priv/roms; slots 2/3 of the Pentagon models (TR-DOS, reset service ROM)
%% have no bundled default and stay unmapped until configured. Relative paths
%% resolve against priv/roms, absolute paths are used as-is.

%% @doc Machine types that own ROM slots (the order used by the ROMs dialog).
-spec rom_types() -> ['48k' | '128k' | 'pentagon_128' | 'pentagon_512' | 'pentagon_1024'].
rom_types() -> ['48k', '128k', 'pentagon_128', 'pentagon_512', 'pentagon_1024'].

-spec machine_type_label(atom()) -> string().
machine_type_label('48k')           -> "ZX Spectrum 48K";
machine_type_label('128k')          -> "ZX Spectrum 128K";
machine_type_label('pentagon_128')  -> "Pentagon 128K";
machine_type_label('pentagon_512')  -> "Pentagon 512K";
machine_type_label('pentagon_1024') -> "Pentagon 1024K".

%% @doc The ROM slots of a machine type: {slot number, human label}.
-spec rom_slots(atom()) -> [{non_neg_integer(), string()}].
rom_slots('48k') ->
    [{0, "BASIC 48"}];
rom_slots('128k') ->
    [{0, "BASIC 128"}, {1, "BASIC 48"}];
rom_slots(Type) when Type =:= 'pentagon_128'; Type =:= 'pentagon_512';
                     Type =:= 'pentagon_1024' ->
    [{0, "BASIC 128"}, {1, "BASIC 48"}, {2, "TR-DOS (optional)"}].

-spec rom_key(atom(), non_neg_integer()) -> atom().
rom_key(Type, Slot) ->
    list_to_atom(lists:flatten(io_lib:format("rom_~p_~b", [Type, Slot]))).

-spec default_rom_path(atom(), non_neg_integer()) -> string().
default_rom_path('48k', 0) -> "48.rom";
default_rom_path('128k', Slot) -> element(Slot + 1, {"128-0.rom", "128-1.rom"});
default_rom_path(Type, Slot) when Type =:= 'pentagon_128'; Type =:= 'pentagon_512';
                                  Type =:= 'pentagon_1024' ->
    case Slot of
        0 -> "128-0.rom";
        1 -> "128-1.rom";
        _ -> ""
    end;
default_rom_path(_, _) -> "".

%% @doc The effective ROM path for a slot: the configured value or the
%% bundled default (empty string = nothing configured and no default). Config
%% values round-trip through ezx_config's generic value parser, so every
%% representation it can produce is normalized back to a string here.
-spec configured_rom_path(atom(), non_neg_integer()) -> string().
configured_rom_path(Type, Slot) ->
    Default = default_rom_path(Type, Slot),
    case maps:get(rom_key(Type, Slot), ezx_config:load(), undefined) of
        undefined -> Default;
        "" -> Default;
        V when is_atom(V) -> atom_to_list(V);
        V when is_list(V) -> V;
        V when is_integer(V) -> integer_to_list(V);
        V when is_float(V) -> float_to_list(V, [{decimals, 2}])
    end.

%% @doc Persist the ROM paths edited for one machine type; an empty value
%% removes the key so the bundled default applies again. Merges into the full
%% loaded config so unrelated settings survive.
-spec set_rom_paths(atom(), [{non_neg_integer(), string()}]) -> ok.
set_rom_paths(Type, Paths) ->
    Base = ezx_config:load(),
    Updated = lists:foldl(fun({Slot, Value}, Acc) ->
        Key = rom_key(Type, Slot),
        case string:trim(unicode:characters_to_list(Value)) of
            "" -> maps:remove(Key, Acc);
            Trimmed -> Acc#{Key => Trimmed}
        end
    end, Base, Paths),
    ezx_config:save(Updated).

%% @doc Read a required ROM: {ok, Binary}, or error(rom_missing) /
%% error(rom_bad_size) (the callers wrap the call in `catch').
%%
%% A slot image is one 16K chip. Composite dumps (32K = two chips, 64K = four)
%% are sliced at the slot's 16K offset, so one multi-chip file configured into
%% several slots fills each with its own chip — the file must store the chips
%% in slot order. Files laid out differently must be split beforehand.
-spec read_rom_file(string(), non_neg_integer()) -> {ok, binary()}.
read_rom_file("", _Slot) ->
    erlang:error(rom_missing);
read_rom_file(Path, Slot) ->
    case file:read_file(resolve_rom_path(Path)) of
        {ok, Bin} -> {ok, rom_chip(Bin, Slot)};
        _ -> erlang:error(rom_missing)
    end.

-spec rom_chip(binary(), non_neg_integer()) -> binary().
%% a single-chip image fills its slot as-is whatever the slot number is
rom_chip(Bin, _Slot) when byte_size(Bin) =:= 16384 ->
    Bin;
%% larger composites are cut at the slot's 16K boundary
rom_chip(Bin, Slot) when byte_size(Bin) >= (Slot + 1) * 16384 ->
    binary:part(Bin, Slot * 16384, 16384);
rom_chip(_Bin, _Slot) ->
    erlang:error(rom_bad_size).

%% @doc Read an optional extra ROM (the Pentagon TR-DOS slot): `undefined'
%% when unset or unreadable — the memory backend then leaves the slot zeroed
%% and the paging never selects it.
-spec read_optional_rom_file(string(), non_neg_integer()) -> binary() | undefined.
read_optional_rom_file("" , _Slot) ->
    undefined;
read_optional_rom_file(Path, Slot) ->
    case catch read_rom_file(Path, Slot) of
        {ok, Bin} -> Bin;
        _ -> undefined
    end.

%% @doc Relative names resolve inside priv/roms; anything else is taken
%% literally.
-spec resolve_rom_path(string()) -> string().
resolve_rom_path(Path) ->
    case filename:pathtype(Path) of
        relative -> filename:join([priv_dir(), "roms", Path]);
        _ -> Path
    end.

%% @doc The app's priv directory (code:priv_dir/1, falling back to ../priv
%% relative to this module's beam when the app is not loaded by a release).
-spec priv_dir() -> string().
priv_dir() ->
    try code:priv_dir(ezx)
    catch error:badarg ->
        filename:dirname(filename:dirname(code:which(?MODULE)))
    end.

-spec load_emulator_file(string(), atom(), ay | ym | off) -> {ok, #machine_state{}} | {error, {Error, Details::binary()}} when
    Error :: file_not_found | unsupported_format | rom_not_found | rom_bad_size | bad_machine_type |
        bad_sna_header | unsupported_version | sna_load_failed | bad_z80_header | z80_load_failed |
        bad_ezs | bad_tap_data.
load_emulator_file(FilePath, RequestedType, Chip) ->
    case file:read_file(FilePath) of
        {ok, Data} ->
            %% An .ezs container declares its machine type in the header —
            %% it wins over whatever type the caller guessed (e.g. from a
            %% missing meta sidecar).
            MachineType = ezs_machine_type(Data, RequestedType),
            Mod = emulator_module(MachineType),
            case init_virtual_machine(MachineType, Chip) of
                {ok, Machine0} ->
                    load_data(Mod, Machine0, string:lowercase(filename:extension(FilePath)), Data);
                Error ->
                    Error
            end;
        {error, Reason} ->
            Detail = atom_to_binary(Reason),
            {error, {file_not_found, Detail}}
    end.

%% @doc The machine type an .ezs container carries, or RequestedType for any
%% other file (or an unreadable container, whose loader reports the error).
ezs_machine_type(Data, RequestedType) ->
    case ezx_ezs:is_container(Data) of
        true ->
            case ezx_ezs:parse(Data) of
                {ok, #{type := Type}} -> Type;
                _ -> RequestedType
            end;
        false ->
            RequestedType
    end.

%% @doc Load a snapshot/TAP file into a fresh machine, dispatching on the file
%% extension; the per-format loaders decide the actual error codes.
-spec load_data(module(), #machine_state{}, string(), binary()) ->
    {ok, #machine_state{}} | {error, {Error, Details::binary()}} when
    Error :: unsupported_format | bad_sna_header | unsupported_version | sna_load_failed |
        bad_z80_header | z80_load_failed | bad_ezs | bad_tap_data.
load_data(Mod, Machine0, Ext, Data) ->
    case Ext of
        ".sna" -> Mod:load_sna(Machine0, Data);
        ".z80" -> Mod:load_z80(Machine0, Data);
        ".ezs" -> Mod:load_ezs(Machine0, Data);
        ".tap" -> Mod:load_tap(Machine0, Data);
        _ ->
            Detail = iolist_to_binary(Ext),
            {error, {unsupported_format, Detail}}
    end.

%% @doc Emulator module for the given machine type; unknown types fall back to
%% the 48K module (matching init_virtual_machine's bad_machine_type for the
%% actual machine creation).
-spec emulator_module(atom()) -> module().
emulator_module('128k') -> ezx_emulator_128;
emulator_module(Type) when Type =:= 'pentagon_128'; Type =:= 'pentagon_512';
                           Type =:= 'pentagon_1024' ->
    ezx_emulator_pentagon;
emulator_module(_)      -> ezx_emulator.
