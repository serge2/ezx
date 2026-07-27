-module(ezx_config).

-export([load/0, save/1]).

%% Config dir: $XDG_CONFIG_HOME/ezx (or ~/.config/ezx)
config_dir() ->
    Dir = case erlang:system_info(os_type) of
        {unix, _} ->
            case os:getenv("XDG_CONFIG_HOME") of
                false ->
                    filename:join([os:getenv("HOME"), ".config", "ezx"]);
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

config_path() ->
    filename:join(config_dir(), "config").

%% Load config from file. Returns a map of atom() => term().
%% Defaults are applied by the caller.
load() ->
    Path = config_path(),
    case file:read_file(Path) of
        {ok, Bin} ->
            Lines = [string:trim(L) || L <- string:split(Bin, "\n", all), L =/= <<>>],
            parse_lines(Lines, #{});
        _ ->
            #{}
    end.

%% Save config map to file.
save(Map) ->
    Lines = [[atom_to_list(K), "=", to_string(V), "\n"] || {K, V} <- maps:to_list(Map)],
    file:write_file(config_path(), iolist_to_binary(Lines)).

%% --- Internal ---

parse_lines([], Acc) -> Acc;
parse_lines([Line | Rest], Acc) ->
    case string:split(Line, "=") of
        [Key, Val] ->
            K = list_to_atom(string:trim(binary_to_list(Key))),
            V = parse_value(string:trim(binary_to_list(Val))),
            parse_lines(Rest, Acc#{K => V});
        _ ->
            parse_lines(Rest, Acc)
    end.

parse_value("true")  -> true;
parse_value("false") -> false;
parse_value(S) ->
    try list_to_integer(S)
    catch _:_ ->
        try list_to_float(S)
        catch _:_ -> list_to_atom(S)
        end
    end.

to_string(V) when is_boolean(V) -> atom_to_list(V);
to_string(V) when is_integer(V) -> integer_to_list(V);
to_string(V) when is_float(V)   -> float_to_list(V, [{decimals, 2}]);
to_string(V) when is_atom(V)    -> atom_to_list(V);
to_string(V) when is_list(V)    -> V.
