-module(ezx_ui_lib).

-include("ezx_emulator.hrl").

-export([init_virtual_machine/1, load_emulator_file/3]).

-spec init_virtual_machine(atom()) -> {ok, #machine_state{}} | {error, {atom(), binary()}}.
init_virtual_machine('128k') ->
    case catch read_rom("128-0.rom", "128-1.rom") of
        Rom when byte_size(Rom) =:= 32768 ->
            {ok, ezx_emulator_128:init(z80_cpu, ezx_memory_128, ezx_screen, ezx_keyboard, ezx_beeper2, Rom)};
        {'EXIT', _} ->
            {error, {rom_not_found, <<"128K ROMs not found (128-0.rom, 128-1.rom)">>}};
        _ ->
            {error, {rom_bad_size, <<"128K ROM must be exactly 32768 bytes">>}}
    end;
init_virtual_machine('48k') ->
    case catch read_rom("48.rom") of
        Rom when byte_size(Rom) =:= 16384 ->
            {ok, ezx_emulator:init(z80_cpu, ezx_memory_48_pages512, ezx_screen, ezx_keyboard, ezx_beeper2, Rom)};
        {'EXIT', _} ->
            {error, {rom_not_found, <<"48K ROM not found (48.rom)">>}};
        _ ->
            {error, {rom_bad_size, <<"48K ROM must be exactly 16384 bytes">>}}
    end;
init_virtual_machine(Bad) ->
    {error, {bad_machine_type, iolist_to_binary(io_lib:format("~p", [Bad]))}}.

read_rom(File) ->
    PrivDir = priv_dir(),
    {ok, R} = file:read_file(filename:join([PrivDir, "roms", File])),
    R.

read_rom(File0, File1) ->
    PrivDir = priv_dir(),
    R0 = try file:read_file(filename:join([PrivDir, "roms", File0]))
        catch _:_ -> {error, enoent} end,
    R1 = try file:read_file(filename:join([PrivDir, "roms", File1]))
        catch _:_ -> {error, enoent} end,
    case {R0, R1} of
        {{ok, A}, {ok, B}} -> <<A/binary, B/binary>>;
        _ -> error(roms_not_found)
    end.

priv_dir() ->
    try code:priv_dir(ezx)
    catch error:badarg ->
        filename:dirname(filename:dirname(code:which(?MODULE)))
    end.

-spec load_emulator_file(#machine_state{}, string(), atom()) -> {ok, #machine_state{}} | {error, {atom(), binary()}}.
load_emulator_file(Machine, FilePath, MachineType) ->
    Mod = emulator_module(MachineType),
    case file:read_file(FilePath) of
        {ok, Data} ->
            Ext = string:lowercase(filename:extension(FilePath)),
            case Ext of
                ".sna" ->
                    Mod:load_sna(Machine, Data);
                ".z80" ->
                    Mod:load_z80(Machine, Data);
                ".tap" ->
                    case init_virtual_machine(MachineType) of
                        {ok, Machine0} ->
                            Mod:load_tap(Machine0, Data);
                        Error ->
                            Error
                    end;
                _ ->
                    Detail = iolist_to_binary(Ext),
                    {error, {unsupported_format, Detail}}
            end;
        {error, Reason} ->
            Detail = atom_to_binary(Reason),
            {error, {file_not_found, Detail}}
    end.

emulator_module('128k') -> ezx_emulator_128;
emulator_module(_)      -> ezx_emulator.
