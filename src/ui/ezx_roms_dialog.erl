-module(ezx_roms_dialog).

-include_lib("wx/include/wx.hrl").
-include("menu_ids.hrl").

-export([open/2, rebuild/2, collect/1, current_type/1,
         type_from_index/1, index_of_type/1, browse_decode/1]).

%% @doc Modeless "ROMs" dialog: per machine type, the file path of every ROM
%% slot (edited paths are persisted into the config by ezx_ui via
%% ezx_ui_lib:set_rom_paths; an empty field restores the bundled default).
%%
%% The dialog shows the rows of ONE machine type at a time (the Choice at the
%% top switches, destroying and rebuilding the row panel). The refs tuple
%% {Dialog, {Choice, Panel, Rows, Type}} carries Rows = #{Slot => TextCtrl}
%% for the currently shown type only — collect/1 therefore returns the paths
%% of that type, which is exactly what one OK applies.
%%
%% All events are connected on the dialog object itself and reach ezx_ui's
%% handle_info through command propagation: command_button_clicked (OK /
%% Cancel / the per-row Browse buttons, identified by their encoded ids),
%% command_choice_selected (type switch) and close_window.

-type refs() :: {wxDialog:wxDialog(), {wxChoice:wxChoice(), wxPanel:wxPanel(),
                                       #{non_neg_integer() => wxTextCtrl:wxTextCtrl()}, atom()}}.

-spec open(wxFrame:wxFrame(), atom()) -> refs().
open(Frame, InitialType) ->
    Dialog = wxDialog:new(Frame, -1, "ROMs", [{style, ?wxDEFAULT_DIALOG_STYLE}]),
    MainSizer = wxBoxSizer:new(?wxVERTICAL),
    wxSizer:add(MainSizer, wxStaticText:new(Dialog, -1, "ROM files (empty = bundled default)"),
                [{flag, ?wxALL}, {border, 10}]),
    TypeChoice = wxChoice:new(Dialog, -1,
                              [{choices, [ezx_ui_lib:machine_type_label(T) ||
                                            T <- ezx_ui_lib:rom_types()]}]),
    wxChoice:setSelection(TypeChoice, index_of_type(InitialType)),
    wxSizer:add(MainSizer, TypeChoice, [{flag, ?wxEXPAND bor ?wxLEFT bor ?wxRIGHT}, {border, 10}]),
    Panel = wxPanel:new(Dialog),
    wxSizer:add(MainSizer, Panel, [{flag, ?wxEXPAND bor ?wxALL}, {border, 10}]),
    BtnSizer = wxDialog:createStdDialogButtonSizer(Dialog, ?wxOK bor ?wxCANCEL),
    wxSizer:add(MainSizer, BtnSizer, [{flag, ?wxALL bor ?wxALIGN_RIGHT}, {border, 10}]),
    wxDialog:setSizer(Dialog, MainSizer),

    %% rebuild returns the refs carrying the freshly built Rows map — the
    %% initial #{} seed would leave Browse with nothing to write into.
    Refs = rebuild({Dialog, {TypeChoice, Panel, #{}, InitialType}}, InitialType),

    wxDialog:connect(Dialog, command_button_clicked),
    wxDialog:connect(Dialog, command_choice_selected),
    wxDialog:connect(Dialog, close_window),
    wxDialog:show(Dialog),
    Refs.

%% @doc Rebuild the row panel for a machine type: one label + text field +
%% Browse button per ROM slot, prefilled from the effective configured paths.
%% The rows share ONE flex grid (label | field | button), so every column is
%% aligned to its widest cell — per-row box sizers would start each input at
%% a different x and give it a leftover width (the pentagon's long optional
%% labels squeezed their fields to a sliver).
-spec rebuild(refs(), atom()) -> refs().
rebuild({Dialog, {Choice, Panel, _OldRows, _OldType}}, NewType) ->
    lists:foreach(fun(W) -> wxWindow:destroy(W) end,
                  wxWindow:getChildren(Panel)),
    Grid = wxFlexGridSizer:new(0, 3, 8, 8),
    wxFlexGridSizer:addGrowableCol(Grid, 1),
    Rows = lists:foldl(fun({Slot, Label}, Acc) ->
        wxSizer:add(Grid, wxStaticText:new(Panel, -1, Label ++ ":"),
                    [{flag, ?wxALIGN_CENTRE_VERTICAL}]),
        Text = wxTextCtrl:new(Panel, -1,
                              [{value, ezx_ui_lib:configured_rom_path(NewType, Slot)},
                               {style, ?wxTE_PROCESS_ENTER}]),
        %% room for a real path: fit() grows the dialog to honour this minimum
        wxTextCtrl:setMinSize(Text, {320, -1}),
        wxSizer:add(Grid, Text, [{flag, ?wxEXPAND bor ?wxALIGN_CENTRE_VERTICAL}]),
        Browse = wxButton:new(Panel, browse_id(NewType, Slot), [{label, "Browse..."}]),
        wxSizer:add(Grid, Browse),
        Acc#{Slot => Text}
    end, #{}, ezx_ui_lib:rom_slots(NewType)),
    PanelSizer = wxBoxSizer:new(?wxVERTICAL),
    wxSizer:add(PanelSizer, Grid, [{flag, ?wxEXPAND}]),
    Reset = wxButton:new(Panel, ?BTN_ROM_RESET, [{label, "Reset to defaults"}]),
    wxSizer:add(PanelSizer, Reset, [{flag, ?wxALL}, {border, 4}]),
    wxPanel:setSizer(Panel, PanelSizer),
    %% replacing the sizer of a SHOWN window leaves its children unplaced
    %% until the next explicit layout pass
    wxWindow:layout(Dialog),
    wxSizer:fit(wxDialog:getSizer(Dialog), Dialog),
    wxDialog:centre(Dialog),
    {Dialog, {Choice, Panel, Rows, NewType}}.

%% @doc The edited paths of the currently shown type: [{Slot, Path}].
-spec collect(refs()) -> [{non_neg_integer(), string()}].
collect({_Dialog, {_Choice, _Panel, Rows, _Type}}) ->
    [{Slot, wxTextCtrl:getValue(Text)} || {Slot, Text} <- maps:to_list(Rows)].

-spec current_type(refs()) -> atom().
current_type({_Dialog, {_Choice, _Panel, _Rows, Type}}) -> Type.

-spec type_from_index(non_neg_integer()) -> atom().
type_from_index(Index) ->
    lists:nth(Index + 1, ezx_ui_lib:rom_types()).

-spec index_of_type(atom()) -> non_neg_integer().
index_of_type(Type) ->
    Types = ezx_ui_lib:rom_types(),
    length(lists:takewhile(fun(T) -> T =/= Type end, Types)).

%% @doc Stable widget id for a (machine type, slot) Browse button:
%% base + type_index * 8 + slot.
-spec browse_id(atom(), non_neg_integer()) -> integer().
browse_id(Type, Slot) -> ?BTN_ROM_BROWSE_BASE + index_of_type(Type) * 8 + Slot.

%% @doc Decode a Browse button id back to its machine type and slot;
%% `error' when the id is not one of ours (e.g. the std OK/Cancel buttons).
-spec browse_decode(integer()) -> {atom(), non_neg_integer()} | error.
browse_decode(Id) when Id >= ?BTN_ROM_BROWSE_BASE, Id < ?BTN_ROM_BROWSE_BASE + 40 ->
    N = Id - ?BTN_ROM_BROWSE_BASE,
    {type_from_index(N div 8), N rem 8};
browse_decode(_) -> error.
