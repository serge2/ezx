-module(ezx_recent_files).

-include("menu_ids.hrl").
-include_lib("wx/include/wx.hrl").

-export([load/0, save/1, update/2,
         build_menu/1, rebuild_menu/2]).

%% --- Persistence ---

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

recent_config_path() ->
    filename:join(app_dir(), "recent").

load() ->
    Path = recent_config_path(),
    case file:read_file(Path) of
        {ok, Bin} ->
            Lines = [string:trim(L) || L <- string:split(Bin, "\n", all), L =/= <<>>],
            [binary_to_list(L) || L <- Lines];
        _ -> []
    end.

save(Files) ->
    Bin = iolist_to_binary([[list_to_binary(F), "\n"] || F <- Files]),
    file:write_file(recent_config_path(), Bin).

%% --- List operations ---

update(File, RecentFiles) ->
    Updated = lists:sublist([File | lists:delete(File, RecentFiles)], ?MAX_RECENT),
    save(Updated),
    Updated.

%% --- Menu building ---

build_menu(RecentFiles) ->
    FileMenu = wxMenu:new(),
    wxMenu:append(FileMenu, ?wxID_OPEN, "Load file\tCtrl+O", [{help, "Load a .sna or .tap file"}]),
    case RecentFiles of
        [] -> ok;
        _ ->
            wxMenu:appendSeparator(FileMenu),
            LabelItem = wxMenu:append(FileMenu, ?MENU_RECENT_LABEL, "Recent:"),
            wxMenuItem:enable(LabelItem, [{enable, false}]),
            lists:foreach(fun({Idx, Path}) ->
                Name = filename:basename(Path),
                wxMenu:append(FileMenu, ?MENU_RECENT_BASE + Idx, Name)
            end, lists:zip(lists:seq(0, length(RecentFiles) - 1), RecentFiles))
    end,
    wxMenu:appendSeparator(FileMenu),
    wxMenu:append(FileMenu, ?wxID_EXIT, "Quit\tCtrl+Q", [{help, "Exit emulator"}]),
    FileMenu.

rebuild_menu(MenuBar, RecentFiles) ->
    OldFileMenu = wxMenuBar:remove(MenuBar, 0),
    wxMenu:destroy(OldFileMenu),
    NewFileMenu = build_menu(RecentFiles),
    wxMenuBar:insert(MenuBar, 0, NewFileMenu, "File"),
    ok.
