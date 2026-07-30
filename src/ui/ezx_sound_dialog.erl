-module(ezx_sound_dialog).

-include_lib("wx/include/wx.hrl").

-export([open/4, stereo_pans/1, stereo_mode_from_index/1]).

-spec open(wxFrame:wxFrame(), 0..100, 0..100, acb | abc | mono) ->
    {wxDialog:wxDialog(), wxSlider:wxSlider(), wxSlider:wxSlider(), wxChoice:wxChoice()}.
open(Frame, BeeperVol, AyVol, Mode) ->
    Dialog = wxDialog:new(Frame, -1, "Sound Settings", [{style, ?wxDEFAULT_DIALOG_STYLE}]),
    MainSizer = wxBoxSizer:new(?wxVERTICAL),

    BeeperSizer = wxStaticBoxSizer:new(?wxVERTICAL, Dialog, [{label, "Beeper"}]),
    wxStaticBoxSizer:add(BeeperSizer, wxStaticText:new(Dialog, -1, "Volume"), [{flag, ?wxALL}, {border, 5}]),
    BeeperSlider = wxSlider:new(Dialog, -1, BeeperVol, 0, 100, [{style, ?wxSL_HORIZONTAL bor ?wxSL_LABELS}]),
    wxStaticBoxSizer:add(BeeperSizer, BeeperSlider, [{flag, ?wxEXPAND bor ?wxLEFT bor ?wxRIGHT bor ?wxBOTTOM}, {border, 5}]),
    wxSizer:add(MainSizer, BeeperSizer, [{flag, ?wxEXPAND bor ?wxALL}, {border, 10}]),

    AySizer = wxStaticBoxSizer:new(?wxVERTICAL, Dialog, [{label, "AY-3-8912"}]),
    wxStaticBoxSizer:add(AySizer, wxStaticText:new(Dialog, -1, "Volume"), [{flag, ?wxALL}, {border, 5}]),
    AySlider = wxSlider:new(Dialog, -1, AyVol, 0, 100, [{style, ?wxSL_HORIZONTAL bor ?wxSL_LABELS}]),
    wxStaticBoxSizer:add(AySizer, AySlider, [{flag, ?wxEXPAND bor ?wxLEFT bor ?wxRIGHT bor ?wxBOTTOM}, {border, 5}]),
    wxStaticBoxSizer:add(AySizer, wxStaticText:new(Dialog, -1, "Stereo mode"), [{flag, ?wxALL}, {border, 5}]),
    ModeChoice = wxChoice:new(Dialog, -1, [{choices, ["ACB (Spectrum 128K)", "ABC", "Mono"]}]),
    wxChoice:setSelection(ModeChoice, stereo_mode_index(Mode)),
    wxStaticBoxSizer:add(AySizer, ModeChoice, [{flag, ?wxEXPAND bor ?wxLEFT bor ?wxRIGHT bor ?wxBOTTOM}, {border, 5}]),
    wxSizer:add(MainSizer, AySizer, [{flag, ?wxEXPAND bor ?wxALL}, {border, 10}]),

    BtnSizer = wxDialog:createStdDialogButtonSizer(Dialog, ?wxOK bor ?wxCANCEL),
    wxSizer:add(MainSizer, BtnSizer, [{flag, ?wxALL bor ?wxALIGN_RIGHT}, {border, 10}]),

    wxDialog:setSizer(Dialog, MainSizer),
    wxSizer:fit(MainSizer, Dialog),
    wxDialog:centre(Dialog),

    wxDialog:connect(Dialog, command_button_clicked),
    wxDialog:connect(Dialog, close_window),

    wxDialog:show(Dialog),
    {Dialog, BeeperSlider, AySlider, ModeChoice}.

stereo_pans(acb)  -> {left, both, right};
stereo_pans(abc)  -> {left, right, both};
stereo_pans(mono) -> {both, both, both}.

stereo_mode_index(acb)  -> 0;
stereo_mode_index(abc)  -> 1;
stereo_mode_index(mono) -> 2.

stereo_mode_from_index(0) -> acb;
stereo_mode_from_index(1) -> abc;
stereo_mode_from_index(2) -> mono.
