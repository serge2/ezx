-module(ezx_about_dialog).

-include_lib("wx/include/wx.hrl").

-export([show/1]).

%% @doc Show the modal "About ezx" dialog parented on Frame: app name, version,
%% a short description, copyright and license/ROM notes, laid out like the
%% FUSE about box (plain centered text, no group frames). Modal, so it blocks
%% until the user closes it; nothing else needs to stay in sync.
-spec show(wxFrame:wxFrame()) -> ok.
show(Frame) ->
    Dialog = wxDialog:new(Frame, -1, "About ezx", [{style, ?wxDEFAULT_DIALOG_STYLE}]),
    MainSizer = wxBoxSizer:new(?wxVERTICAL),
    Center = [{flag, ?wxALIGN_CENTER_HORIZONTAL bor ?wxALL}, {border, 2}],

    Title = wxStaticText:new(Dialog, -1, "EZX"),
    wxStaticText:setFont(Title,
        wxFont:new(14, ?wxFONTFAMILY_DEFAULT, ?wxFONTSTYLE_NORMAL, ?wxFONTWEIGHT_BOLD)),
    wxSizer:add(MainSizer, Title, [{flag, ?wxALIGN_CENTER_HORIZONTAL bor ?wxTOP},
                                   {border, 12}]),

    wxSizer:add(MainSizer, wxStaticText:new(Dialog, -1, version_line()), Center),
    wxSizer:add(MainSizer, wxStaticText:new(Dialog, -1,
                 "A ZX Spectrum emulator written in Erlang."), Center),
    wxSizer:add(MainSizer, wxStaticText:new(Dialog, -1,
                 "(c) 2026 Sergii Polkovnikov"), Center),

    LicenseSizer = wxBoxSizer:new(?wxHORIZONTAL),
    wxSizer:add(LicenseSizer, wxStaticText:new(Dialog, -1, "License: MIT  "), []),
    wxSizer:add(LicenseSizer, link_label(Dialog, "LICENSE", license_url()), []),
    wxSizer:add(MainSizer, LicenseSizer, Center),

    wxSizer:add(MainSizer, wxStaticText:new(Dialog, -1,
                 "The ROM files supplied with this application are "
                 "copyright Amstrad plc."), Center),
    wxSizer:add(MainSizer, wxStaticText:new(Dialog, -1,
                 "Amstrad has kindly given written permission for these "
                 "ROMs to be"), Center),
    wxSizer:add(MainSizer, wxStaticText:new(Dialog, -1,
                 "redistributed freely for use with emulators."), Center),
    wxSizer:add(MainSizer, link_label(Dialog, "Amstrad permission letter",
                 "https://worldofspectrum.net/app/themes/wosc-classic/static/legacy/amstrad-roms.txt"),
                 Center),

    BtnSizer = wxDialog:createStdDialogButtonSizer(Dialog, ?wxOK),
    wxSizer:add(MainSizer, BtnSizer, [{flag, ?wxALL bor ?wxALIGN_CENTER}, {border, 10}]),

    wxDialog:setSizer(Dialog, MainSizer),
    wxSizer:fit(MainSizer, Dialog),
    wxDialog:centre(Dialog),
    wxDialog:showModal(Dialog),
    wxDialog:destroy(Dialog),
    ok.

%% @doc A blue underlined clickable label. The callback runs in a spawned
%% process (wx connects it that way), so the link stays clickable while the
%% modal loop blocks the owning process; clicking launches the default browser.
-spec link_label(wxDialog:wxDialog(), string(), string()) -> wxStaticText:wxStaticText().
link_label(Dialog, Text, Url) ->
    Label = wxStaticText:new(Dialog, -1, Text),
    wxStaticText:setForegroundColour(Label, {0, 102, 204}),
    Font = wxStaticText:getFont(Label),
    wxStaticText:setFont(Label,
        wxFont:new(wxFont:getPointSize(Font), ?wxFONTFAMILY_DEFAULT,
                   ?wxFONTSTYLE_NORMAL, ?wxFONTWEIGHT_NORMAL, [{underlined, true}])),
    wxWindow:connect(Label, left_up, [{callback, fun(_, _) ->
        wx_misc:launchDefaultBrowser(Url)
    end}]),
    Label.

%% @doc The URL for the LICENSE reference: a file:// link to the copy bundled
%% in priv (kept in the release), falling back to the canonical MIT text
%% online when the file is missing.
-spec license_url() -> string().
license_url() ->
    LicensePath = filename:join(code:priv_dir(ezx), "LICENSE"),
    case filelib:is_regular(LicensePath) of
        true -> "file://" ++ LicensePath;
        false -> "https://opensource.org/licenses/MIT"
    end.

%% @doc App version from the .app file ("1" in ezx.app.src); "?" when the
%% application is not loaded.
-spec version_line() -> string().
version_line() ->
    Vsn = case application:get_key(ezx, vsn) of
        {ok, V} -> V;
        _ -> "?"
    end,
    lists:flatten(io_lib:format("~s", [Vsn])).
