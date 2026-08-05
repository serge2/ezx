-module(ezx_recent_files).

-include("menu_ids.hrl").
-include_lib("wx/include/wx.hrl").

-export([load/0, save/1, update/2,
         build_menu/1, rebuild_menu/2]).

%% --- Persistence ---

recent_config_path() ->
    filename:join(ezx_ui_lib:app_dir(), "recent").

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
    wxMenu:append(FileMenu, ?wxID_OPEN, "Open...\tCtrl+O", [{help, "Load a .sna, .z80 or .tap file"}]),
    wxMenu:append(FileMenu, ?MENU_QUICK_SAVE, "Quick Save\tF5", [{help, "Save the current state to the quick slot"}]),
    wxMenu:append(FileMenu, ?MENU_QUICK_LOAD, "Quick Load\tF9", [{help, "Load the quick-slot save"}]),
    wxMenu:appendSeparator(FileMenu),
    wxMenu:append(FileMenu, ?MENU_SAVE_STATE, "Save\tF2", [{help, "Save the current state under a name"}]),
    wxMenu:append(FileMenu, ?MENU_MANAGE_SAVES, "Load\tF3", [{help, "Load, delete or rename saved states"}]),
    case RecentFiles of
        [] -> ok;
        _ ->
            wxMenu:appendSeparator(FileMenu),
            LabelItem = wxMenu:append(FileMenu, ?MENU_RECENT_LABEL, "Recently Opened:"),
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
