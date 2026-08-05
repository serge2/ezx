-module(ezx_sound_dialog).

-include_lib("wx/include/wx.hrl").

-export([open/4, open/5, stereo_pans/1, stereo_mode_from_index/1, chip_from_index/1]).

%% @doc Open the modeless "Sound Settings" dialog parented on Frame.
%% Returns refs as {Dialog, {BeeperSlider, AySlider, ModeChoice}} so the
%% caller can read the widget values and destroy the dialog.
-spec open(wxFrame:wxFrame(), 0..100, 0..100, acb | abc | mono) ->
    {wxDialog:wxDialog(), {wxSlider:wxSlider(), wxSlider:wxSlider(), wxChoice:wxChoice()}}.
open(Frame, BeeperVol, AyVol, Mode) ->
    open(Frame, BeeperVol, AyVol, Mode, ay).

%% @doc Open the "Sound Settings" dialog, including the sound chip
%% (AY-3-8912 vs YM2149 vs Off) selection.
-spec open(wxFrame:wxFrame(), 0..100, 0..100, acb | abc | mono, ay | ym | off) ->
    {wxDialog:wxDialog(), {wxSlider:wxSlider(), wxSlider:wxSlider(), wxChoice:wxChoice(), wxChoice:wxChoice()}}.
open(Frame, BeeperVol, AyVol, Mode, Chip) ->
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
    wxStaticBoxSizer:add(AySizer, wxStaticText:new(Dialog, -1, "Chip"), [{flag, ?wxALL}, {border, 5}]),
    ChipChoice = wxChoice:new(Dialog, -1, [{choices, ["AY-3-8912", "YM2149", "Off"]}]),
    wxChoice:setSelection(ChipChoice, chip_index(Chip)),
    wxStaticBoxSizer:add(AySizer, ChipChoice, [{flag, ?wxEXPAND bor ?wxLEFT bor ?wxRIGHT bor ?wxBOTTOM}, {border, 5}]),
    wxSizer:add(MainSizer, AySizer, [{flag, ?wxEXPAND bor ?wxALL}, {border, 10}]),

    BtnSizer = wxDialog:createStdDialogButtonSizer(Dialog, ?wxOK bor ?wxCANCEL),
    wxSizer:add(MainSizer, BtnSizer, [{flag, ?wxALL bor ?wxALIGN_RIGHT}, {border, 10}]),

    wxDialog:setSizer(Dialog, MainSizer),
    wxSizer:fit(MainSizer, Dialog),
    wxDialog:centre(Dialog),

    wxDialog:connect(Dialog, command_button_clicked),
    wxDialog:connect(Dialog, close_window),

    wxDialog:show(Dialog),
    {Dialog, {BeeperSlider, AySlider, ModeChoice, ChipChoice}}.

%% @doc Stereo pan for each AY channel in the given mixing mode.
%% Naming matches Fuse: "ACB" = A left, C centre, B right; "ABC" =
%% A left, B centre, C right. The centre channel plays in both ears.
-spec stereo_pans(acb | abc | mono) -> {left | both | right, left | both | right, left | both | right}.
stereo_pans(acb)  -> {left, right, both};
stereo_pans(abc)  -> {left, both, right};
stereo_pans(mono) -> {both, both, both}.

%% @doc Choice widget index (0..2) for a stereo mode.
-spec stereo_mode_index(acb | abc | mono) -> 0..2.
stereo_mode_index(acb)  -> 0;
stereo_mode_index(abc)  -> 1;
stereo_mode_index(mono) -> 2.

%% @doc Stereo mode for a choice widget index (0..2).
-spec stereo_mode_from_index(0..2) -> acb | abc | mono.
stereo_mode_from_index(0) -> acb;
stereo_mode_from_index(1) -> abc;
stereo_mode_from_index(2) -> mono.

%% @doc Choice widget index for a sound chip.
-spec chip_index(ay | ym | off) -> 0..2.
chip_index(ay)  -> 0;
chip_index(ym)  -> 1;
chip_index(off) -> 2.

%% @doc Sound chip for a choice widget index (0..2).
-spec chip_from_index(0..2) -> ay | ym | off.
chip_from_index(0) -> ay;
chip_from_index(1) -> ym;
chip_from_index(2) -> off.
