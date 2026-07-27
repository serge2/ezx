-module(ezx_ui_lib).

-export([init_virtual_machine/0, run_initial_frames/2, load_emulator_file/2]).

init_virtual_machine() ->
    RomPath = try filename:join([code:priv_dir(ezx), "roms", "48.rom"])
    catch error:badarg ->
        BeamDir = filename:dirname(code:which(?MODULE)),
        filename:join([filename:dirname(BeamDir), "priv", "roms", "48.rom"])
    end,
    {ok, Rom} = file:read_file(RomPath),
    ezx_emulator:init(z80_cpu, ezx_memory_48_pages512, ezx_screen, ezx_keyboard, ezx_beeper, Rom).

run_initial_frames(Machine, 0) -> Machine;
run_initial_frames(Machine, N) ->
    Machine2 = ezx_emulator:run_frame(Machine),
    run_initial_frames(Machine2, N - 1).

load_emulator_file(Machine, FilePath) ->
    case file:read_file(FilePath) of
        {ok, Data} ->
            Ext = string:lowercase(filename:extension(FilePath)),
            try
                NewMachine = case Ext of
                    ".sna" ->
                        ezx_emulator:load_sna(Machine, Data);
                    ".tap" ->
                        Machine0 = init_virtual_machine(),
                        Machine1 = run_initial_frames(Machine0, 50),
                        ezx_emulator:load_tap(Machine1, Data);
                    _ ->
                        {error, {unknown_type, Ext}}
                end,
                case NewMachine of
                    {error, _} = Err -> Err;
                    _ -> {ok, NewMachine}
                end
            catch
                C:E:S ->
                    {error, {C, E, S}}
            end;
        {error, Reason} ->
            {error, {read_failed, Reason}}
    end.
