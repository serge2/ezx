-module(ezx_ui_lib).

-export([init_virtual_machine/0, run_initial_frames/2, load_emulator_file/2]).

init_virtual_machine() ->
    RomPath = try filename:join([code:priv_dir(ezx), "roms", "48.rom"])
    catch error:badarg ->
        BeamDir = filename:dirname(code:which(?MODULE)),
        filename:join([filename:dirname(BeamDir), "priv", "roms", "48.rom"])
    end,
    {ok, Rom} = file:read_file(RomPath),
    ezx_emulator:init(z80_cpu, ezx_memory_48_pages512, ezx_screen, ezx_keyboard, ezx_beeper2, Rom).

run_initial_frames(Machine, 0) -> Machine;
run_initial_frames(Machine, N) ->
    Machine2 = ezx_emulator:run_frame(Machine),
    {_PCM, Machine3} = ezx_emulator:render_beeper(Machine2),
    run_initial_frames(Machine3, N - 1).

load_emulator_file(Machine, FilePath) ->
    case file:read_file(FilePath) of
        {ok, Data} ->
            Ext = string:lowercase(filename:extension(FilePath)),
            case Ext of
                ".sna" ->
                    ezx_emulator:load_sna(Machine, Data);
                ".tap" ->
                    Machine0 = init_virtual_machine(),
                    Machine1 = run_initial_frames(Machine0, 50),
                    ezx_emulator:load_tap(Machine1, Data);
                _ ->
                    Detail = iolist_to_binary(Ext),
                    {error, {unsupported_format, Detail}}
            end;
        {error, Reason} ->
            Detail = atom_to_binary(Reason),
            {error, {file_not_found, Detail}}
    end.
