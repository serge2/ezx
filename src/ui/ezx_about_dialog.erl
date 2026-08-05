-module(ezx_about_dialog).

-include_lib("wx/include/wx.hrl").

-export([show/1]).

%% @doc Show the modal "About ezx" dialog parented on Frame: app name, version,
%% a short description and the runtime the emulator runs under. Modal, so it
%% blocks until the user closes it; nothing else needs to stay in sync.
-spec show(wxFrame:wxFrame()) -> ok.
show(Frame) ->
    Dialog = wxDialog:new(Frame, -1, "About ezx", [{style, ?wxDEFAULT_DIALOG_STYLE}]),
    MainSizer = wxBoxSizer:new(?wxVERTICAL),

    AppSizer = wxStaticBoxSizer:new(?wxVERTICAL, Dialog, [{label, "ezx"}]),
    wxStaticBoxSizer:add(AppSizer, wxStaticText:new(Dialog, -1, "ZX Spectrum emulator"),
                         [{flag, ?wxALL}, {border, 5}]),
    wxStaticBoxSizer:add(AppSizer, wxStaticText:new(Dialog, -1, version_line()),
                         [{flag, ?wxALL}, {border, 5}]),
    wxStaticBoxSizer:add(AppSizer, wxStaticText:new(Dialog, -1,
                         "A ZX Spectrum emulator written in Erlang."),
                         [{flag, ?wxALL}, {border, 5}]),
    wxSizer:add(MainSizer, AppSizer, [{flag, ?wxEXPAND bor ?wxALL}, {border, 10}]),

    TechSizer = wxStaticBoxSizer:new(?wxVERTICAL, Dialog, [{label, "Author"}]),
    wxStaticBoxSizer:add(TechSizer, wxStaticText:new(Dialog, -1, "Sergii Polkovnikov"),
                         [{flag, ?wxALL}, {border, 5}]),
    wxStaticBoxSizer:add(TechSizer, wxStaticText:new(Dialog, -1, "License: MIT"),
                         [{flag, ?wxALL}, {border, 5}]),
    wxSizer:add(MainSizer, TechSizer, [{flag, ?wxEXPAND bor ?wxALL}, {border, 10}]),

    BtnSizer = wxDialog:createStdDialogButtonSizer(Dialog, ?wxOK),
    wxSizer:add(MainSizer, BtnSizer, [{flag, ?wxALL bor ?wxALIGN_CENTER}, {border, 10}]),

    wxDialog:setSizer(Dialog, MainSizer),
    wxSizer:fit(MainSizer, Dialog),
    wxDialog:centre(Dialog),
    wxDialog:showModal(Dialog),
    wxDialog:destroy(Dialog),
    ok.

%% @doc App version from the .app file ("1" in ezx.app.src); "?" when the
%% application is not loaded.
-spec version_line() -> string().
version_line() ->
    Vsn = case application:get_key(ezx, vsn) of
        {ok, V} -> V;
        _ -> "?"
    end,
    lists:flatten(io_lib:format("Version ~s", [Vsn])).
