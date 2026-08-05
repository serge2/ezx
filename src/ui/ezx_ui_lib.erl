-module(ezx_ui_lib).

-include("ezx_emulator.hrl").

-export([init_virtual_machine/1, init_virtual_machine/2, load_emulator_file/3,
         app_dir/0, priv_dir/0]).

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
    case catch read_roms("128-0.rom", "128-1.rom") of
        {Rom0, Rom1} when byte_size(Rom0) =:= 16384, byte_size(Rom1) =:= 16384 ->
            BaseModel = ?SPECTRUM_128_MODEL,
            Model = BaseModel#machine_model{ay_chip = ay_chip_value(Chip)},
            M = ezx_emulator_128:init(Model, z80_cpu, ezx_memory_128_banks_tuples, ezx_keyboard, ezx_beeper2, ay_module(Chip), {Rom0, Rom1}),
            {ok, ezx_emulator:set_render_screen(M, true)};
        {'EXIT', _} ->
            {error, {rom_not_found, <<"128K ROMs not found (128-0.rom, 128-1.rom)">>}};
        _ ->
            {error, {rom_bad_size, <<"128K ROMs must be exactly 16384 bytes each">>}}
    end;
init_virtual_machine('48k', Chip) ->
    case catch read_rom("48.rom") of
        Rom when byte_size(Rom) =:= 16384 ->
            BaseModel = ?SPECTRUM_48_MODEL,
            Model = BaseModel#machine_model{ay_chip = ay_chip_value(Chip)},
            M = ezx_emulator:init(Model, z80_cpu, ezx_memory_48_pages512_tuples, ezx_keyboard, ezx_beeper2, ay_module(Chip), Rom),
            {ok, ezx_emulator:set_render_screen(M, true)};
        {'EXIT', _} ->
            {error, {rom_not_found, <<"48K ROM not found (48.rom)">>}};
        _ ->
            {error, {rom_bad_size, <<"48K ROM must be exactly 16384 bytes">>}}
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

%% @doc Read a single ROM from priv/roms as a binary; raises badmatch when the
%% file is missing (the caller wraps the call in `catch').
-spec read_rom(string()) -> binary().
read_rom(File) ->
    PrivDir = priv_dir(),
    {ok, R} = file:read_file(filename:join([PrivDir, "roms", File])),
    R.

%% @doc Read both 128K ROMs as binaries; raises error(roms_not_found) when
%% either file is missing (the caller wraps the call in `catch').
-spec read_roms(string(), string()) -> {binary(), binary()}.
read_roms(File0, File1) ->
    PrivDir = priv_dir(),
    R0 = try {ok, R0b} = file:read_file(filename:join([PrivDir, "roms", File0])), R0b
        catch _:_ -> error(roms_not_found) end,
    R1 = try {ok, R1b} = file:read_file(filename:join([PrivDir, "roms", File1])), R1b
        catch _:_ -> error(roms_not_found) end,
    {R0, R1}.

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
        bad_tap_data.
load_emulator_file(FilePath, MachineType, Chip) ->
    Mod = emulator_module(MachineType),
    case file:read_file(FilePath) of
        {ok, Data} ->
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

%% @doc Load a snapshot/TAP file into a fresh machine, dispatching on the file
%% extension; the per-format loaders decide the actual error codes.
-spec load_data(module(), #machine_state{}, string(), binary()) ->
    {ok, #machine_state{}} | {error, {Error, Details::binary()}} when
    Error :: unsupported_format | bad_sna_header | unsupported_version | sna_load_failed |
        bad_z80_header | z80_load_failed | bad_tap_data.
load_data(Mod, Machine0, Ext, Data) ->
    case Ext of
        ".sna" -> Mod:load_sna(Machine0, Data);
        ".z80" -> Mod:load_z80(Machine0, Data);
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
emulator_module(_)      -> ezx_emulator.
