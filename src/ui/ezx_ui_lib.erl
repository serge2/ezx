-module(ezx_ui_lib).

-include("ezx_emulator.hrl").

-export([init_virtual_machine/1, load_emulator_file/3]).

-spec init_virtual_machine(atom()) -> {ok, #machine_state{}} | {error, {atom(), binary()}}.
init_virtual_machine('128k') ->
    case catch read_roms("128-0.rom", "128-1.rom") of
        {Rom0, Rom1} when byte_size(Rom0) =:= 16384, byte_size(Rom1) =:= 16384 ->
            M = ezx_emulator_128:init(?SPECTRUM_128_MODEL, z80_cpu, ezx_memory_128_pages512, ezx_keyboard, ezx_beeper2, ezx_ay38912_seg, {Rom0, Rom1}),
            {ok, ezx_emulator:set_render_screen(M, true)};
        {'EXIT', _} ->
            {error, {rom_not_found, <<"128K ROMs not found (128-0.rom, 128-1.rom)">>}};
        _ ->
            {error, {rom_bad_size, <<"128K ROMs must be exactly 16384 bytes each">>}}
    end;
init_virtual_machine('48k') ->
    case catch read_rom("48.rom") of
        Rom when byte_size(Rom) =:= 16384 ->
            M = ezx_emulator:init(?SPECTRUM_48_MODEL, z80_cpu, ezx_memory_48_pages512, ezx_keyboard, ezx_beeper2, ezx_ay38912_seg, Rom),
            {ok, ezx_emulator:set_render_screen(M, true)};
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

read_roms(File0, File1) ->
    PrivDir = priv_dir(),
    R0 = try {ok, R0b} = file:read_file(filename:join([PrivDir, "roms", File0])), R0b
        catch _:_ -> error(roms_not_found) end,
    R1 = try {ok, R1b} = file:read_file(filename:join([PrivDir, "roms", File1])), R1b
        catch _:_ -> error(roms_not_found) end,
    {R0, R1}.

priv_dir() ->
    try code:priv_dir(ezx)
    catch error:badarg ->
        filename:dirname(filename:dirname(code:which(?MODULE)))
    end.

-spec load_emulator_file(#machine_state{}, string(), atom()) -> {ok, #machine_state{}} | {error, {atom(), binary()}}.
load_emulator_file(_Machine, FilePath, MachineType) ->
    Mod = emulator_module(MachineType),
    case file:read_file(FilePath) of
        {ok, Data} ->
            Ext = string:lowercase(filename:extension(FilePath)),
            case Ext of
                ".sna" ->
                    case init_virtual_machine(MachineType) of
                        {ok, Machine0} ->
                            Mod:load_sna(Machine0, Data);
                        Error ->
                            Error
                    end;
                ".z80" ->
                    case init_virtual_machine(MachineType) of
                        {ok, Machine0} ->
                            Mod:load_z80(Machine0, Data);
                        Error ->
                            Error
                    end;
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
