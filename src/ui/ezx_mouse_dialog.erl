-module(ezx_mouse_dialog).

-include_lib("wx/include/wx.hrl").

-export([open/3, enabled_from_checkbox/1, swap_from_checkbox/1]).

-spec open(wxFrame:wxFrame(), boolean(), boolean()) ->
    {wxDialog:wxDialog(), wxCheckBox:wxCheckBox(), wxCheckBox:wxCheckBox()}.
open(Frame, Enabled, SwapButtons) ->
    Dialog = wxDialog:new(Frame, -1, "Mouse", [{style, ?wxDEFAULT_DIALOG_STYLE}]),
    MainSizer = wxBoxSizer:new(?wxVERTICAL),

    Checkbox = wxCheckBox:new(Dialog, -1, "Kempston mouse"),
    wxCheckBox:setValue(Checkbox, Enabled),
    wxWindow:setToolTip(Checkbox, "Emulates the Kempston mouse interface "
                                  "(ports 0xFADF/0xFBDF/0xFFDF)"),
    wxSizer:add(MainSizer, Checkbox, [{flag, ?wxALL}, {border, 10}]),

    SwapCheckbox = wxCheckBox:new(Dialog, -1, "Swap left/right buttons"),
    wxCheckBox:setValue(SwapCheckbox, SwapButtons),
    wxWindow:setToolTip(SwapCheckbox, "Some Kempston mouse clones use the "
                                      "reverse D0/D1 button layout"),
    wxSizer:add(MainSizer, SwapCheckbox, [{flag, ?wxALL}, {border, 10}]),

    BtnSizer = wxDialog:createStdDialogButtonSizer(Dialog, ?wxOK bor ?wxCANCEL),
    wxSizer:add(MainSizer, BtnSizer, [{flag, ?wxALL bor ?wxALIGN_RIGHT}, {border, 10}]),

    wxDialog:setSizer(Dialog, MainSizer),
    wxSizer:fit(MainSizer, Dialog),
    wxDialog:centre(Dialog),

    wxDialog:connect(Dialog, command_button_clicked),
    wxDialog:connect(Dialog, close_window),

    wxDialog:show(Dialog),
    {Dialog, Checkbox, SwapCheckbox}.

enabled_from_checkbox(Checkbox) ->
    wxCheckBox:getValue(Checkbox).

swap_from_checkbox(Checkbox) ->
    wxCheckBox:getValue(Checkbox).
