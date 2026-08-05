-module(ezx_saves_dialog).

-include_lib("wx/include/wx.hrl").
-include("menu_ids.hrl").

-export([open/2, refresh/2, update_buttons/5, selected_entry/2, entry_label/1]).

%% @doc Open the modeless "Load" dialog parented on Frame.
%% Entries are the ezx_saves:list_history/1 result, newest first. Returns
%% refs as {Dialog, ListBox, LoadBtn, DeleteBtn, RenameBtn} so the caller
%% can read the selected entry, destroy the dialog, and keep the action
%% buttons in sync with the selection. The ?BTN_LOAD / ?BTN_DELETE /
%% ?BTN_RENAME action buttons (ids defined in menu_ids.hrl) and the
%% ?wxID_OK Close button are wired by the caller; Load sits to the right of
%% Close and is the default button (Enter activates it).
-spec open(wxFrame:wxFrame(), [{string(), string(), string(), string()}]) ->
    {wxDialog:wxDialog(), wxListBox:wxListBox(), wxButton:wxButton(),
     wxButton:wxButton(), wxButton:wxButton()}.
open(Frame, Entries) ->
    Dialog = wxDialog:new(Frame, -1, "Load", [{style, ?wxDEFAULT_DIALOG_STYLE}]),
    MainSizer = wxBoxSizer:new(?wxVERTICAL),

    ListBox = wxListBox:new(Dialog, ?LIST_SAVES, [{size, {600, 360}}]),
    wxSizer:add(MainSizer, ListBox, [{flag, ?wxEXPAND bor ?wxALL}, {border, 10}]),

    BtnRow = wxBoxSizer:new(?wxHORIZONTAL),
    DeleteBtn = wxButton:new(Dialog, ?BTN_DELETE, [{label, "Delete"}]),
    wxWindow:setToolTip(DeleteBtn, "Delete the selected save"),
    RenameBtn = wxButton:new(Dialog, ?BTN_RENAME, [{label, "Rename..."}]),
    wxWindow:setToolTip(RenameBtn, "Rename the selected save"),
    wxSizer:add(BtnRow, DeleteBtn, [{flag, ?wxRIGHT}, {border, 5}]),
    wxSizer:add(BtnRow, RenameBtn, [{flag, ?wxRIGHT}, {border, 5}]),
    wxSizer:add(MainSizer, BtnRow, [{flag, ?wxALL}, {border, 10}]),

    BtnBottom = wxBoxSizer:new(?wxHORIZONTAL),
    CloseBtn = wxButton:new(Dialog, ?wxID_OK, [{label, "Close"}]),
    wxSizer:add(BtnBottom, CloseBtn, [{flag, ?wxRIGHT}, {border, 5}]),
    LoadBtn = wxButton:new(Dialog, ?BTN_LOAD, [{label, "Load"}]),
    wxWindow:setToolTip(LoadBtn, "Restore the selected save and close"),
    wxButton:setDefault(LoadBtn),
    wxSizer:add(BtnBottom, LoadBtn, []),
    wxSizer:add(MainSizer, BtnBottom, [{flag, ?wxALL bor ?wxALIGN_RIGHT}, {border, 10}]),

    Refs = {Dialog, ListBox, LoadBtn, DeleteBtn, RenameBtn},
    refresh(Refs, Entries),

    wxDialog:setSizer(Dialog, MainSizer),
    wxSizer:fit(MainSizer, Dialog),
    wxDialog:centre(Dialog),

    wxDialog:connect(Dialog, command_button_clicked),
    wxDialog:connect(Dialog, command_listbox_selected),
    wxDialog:connect(Dialog, command_listbox_doubleclicked),
    wxDialog:connect(Dialog, close_window),

    wxDialog:show(Dialog),
    Refs.

%% @doc Repopulate the list box from a fresh ezx_saves:list_history/1 result,
%% select the first entry and sync the action buttons.
-spec refresh({wxDialog:wxDialog(), wxListBox:wxListBox(), wxButton:wxButton(),
               wxButton:wxButton(), wxButton:wxButton()},
              [{string(), string(), string(), string()}]) -> ok.
refresh({_Dialog, ListBox, LoadBtn, DeleteBtn, RenameBtn}, Entries) ->
    wxListBox:clear(ListBox),
    lists:foreach(fun(Entry) -> wxListBox:append(ListBox, entry_label(Entry)) end, Entries),
    case Entries of
        [] -> ok;
        _ -> wxListBox:setSelection(ListBox, 0)
    end,
    update_buttons(ListBox, Entries, LoadBtn, DeleteBtn, RenameBtn),
    ok.

%% @doc Enable/disable the action buttons for the current selection: Load is
%% enabled when a save is selected; Delete and Rename need a selected save
%% that is not the fixed quick slot ("Last Quicksave", which only Load may
%% touch). Caller hooks this up to the selection-change event.
-spec update_buttons(wxListBox:wxListBox(), [{string(), string(), string(), string()}],
                     wxButton:wxButton(), wxButton:wxButton(), wxButton:wxButton()) -> ok.
update_buttons(ListBox, Entries, LoadBtn, DeleteBtn, RenameBtn) ->
    case selected_entry(ListBox, Entries) of
        undefined ->
            wxWindow:disable(LoadBtn),
            wxWindow:disable(DeleteBtn),
            wxWindow:disable(RenameBtn);
        {Stamp, _Name, _SavePath, _MetaPath} ->
            wxWindow:enable(LoadBtn),
            case ezx_saves:is_quick_slot(Stamp) of
                true ->
                    wxWindow:disable(DeleteBtn),
                    wxWindow:disable(RenameBtn);
                false ->
                    wxWindow:enable(DeleteBtn),
                    wxWindow:enable(RenameBtn)
            end
    end,
    ok.

%% @doc The entry at the current selection, or `undefined' when nothing is
%% selected (or the selection index is out of range).
-spec selected_entry(wxListBox:wxListBox(), [{string(), string(), string(), string()}]) ->
    {string(), string(), string(), string()} | undefined.
selected_entry(ListBox, Entries) ->
    case wxListBox:getSelection(ListBox) of
        -1 -> undefined;
        Idx when Idx >= 0, Idx < length(Entries) -> lists:nth(Idx + 1, Entries);
        _ -> undefined
    end.

%% @doc Display label for a history entry: the human name with the timestamp
%% in parentheses when the entry has a name, otherwise just the timestamp.
-spec entry_label({string(), string(), string(), string()}) -> string().
entry_label({Stamp, "", _Sna, _Meta}) -> Stamp;
entry_label({Stamp, Name, _Sna, _Meta}) -> Name ++ "  (" ++ Stamp ++ ")".
