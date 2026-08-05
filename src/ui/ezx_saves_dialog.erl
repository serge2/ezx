-module(ezx_saves_dialog).

-include_lib("wx/include/wx.hrl").
-include("menu_ids.hrl").

-export([open/2, refresh/2, update_buttons/5, update_preview/2, selected_entry/2, entry_cells/1]).

-define(PREVIEW_W, 192).
-define(PREVIEW_H, 144).

%% @doc Open the modeless "Load" dialog parented on Frame.
%% Entries are the ezx_saves:list_history/1 result, newest first, shown in a
%% two-column list (Name | Timestamp) with a screenshot preview of the
%% selected save to its right. Returns refs as {Dialog, List, LoadBtn,
%% DeleteBtn, RenameBtn, Preview} so the caller can read the selected entry,
%% refresh the preview, destroy the dialog, and keep the action buttons in
%% sync with the selection. The ?BTN_LOAD / ?BTN_DELETE / ?BTN_RENAME action
%% buttons (ids defined in menu_ids.hrl) and the ?wxID_OK Close button are
%% wired by the caller; Load sits to the right of Close and is the default
%% button (Enter activates it).
-spec open(wxFrame:wxFrame(), [{string(), string(), string(), string(), string()}]) ->
    {wxDialog:wxDialog(), wxListCtrl:wxListCtrl(), wxButton:wxButton(),
     wxButton:wxButton(), wxButton:wxButton(), wxStaticBitmap:wxStaticBitmap()}.
open(Frame, Entries) ->
    Dialog = wxDialog:new(Frame, -1, "Load", [{style, ?wxDEFAULT_DIALOG_STYLE}]),
    MainSizer = wxBoxSizer:new(?wxVERTICAL),

    List = wxListCtrl:new(Dialog, [{winid, ?LIST_SAVES},
                          {style, ?wxLC_REPORT bor ?wxLC_SINGLE_SEL},
                          {size, {600, 360}}]),
    wxListCtrl:insertColumn(List, 0, "Name"),
    wxListCtrl:insertColumn(List, 1, "Timestamp"),
    wxListCtrl:setColumnWidth(List, 0, 430),
    wxListCtrl:setColumnWidth(List, 1, 150),
    Row = wxBoxSizer:new(?wxHORIZONTAL),
    wxSizer:add(Row, List, [{flag, ?wxEXPAND bor ?wxALL}, {border, 10}, {proportion, 1}]),
    Preview = wxStaticBitmap:new(Dialog, -1, placeholder_bitmap(),
                                 [{size, {?PREVIEW_W, ?PREVIEW_H}}]),
    wxSizer:add(Row, Preview, [{flag, ?wxALL bor ?wxALIGN_CENTER}, {border, 10}]),
    wxSizer:add(MainSizer, Row, [{flag, ?wxEXPAND}]),

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

    Refs = {Dialog, List, LoadBtn, DeleteBtn, RenameBtn, Preview},
    refresh(Refs, Entries),

    wxDialog:setSizer(Dialog, MainSizer),
    wxSizer:fit(MainSizer, Dialog),
    wxDialog:centre(Dialog),

    wxDialog:connect(Dialog, command_button_clicked),
    wxDialog:connect(Dialog, command_list_item_selected),
    wxDialog:connect(Dialog, command_list_item_activated),
    wxDialog:connect(Dialog, close_window),

    wxDialog:show(Dialog),
    Refs.

%% @doc Repopulate the list from a fresh ezx_saves:list_history/1 result,
%% select the first entry, sync the action buttons and show its preview.
-spec refresh({wxDialog:wxDialog(), wxListCtrl:wxListCtrl(), wxButton:wxButton(),
               wxButton:wxButton(), wxButton:wxButton(), wxStaticBitmap:wxStaticBitmap()},
              [{string(), string(), string(), string(), string()}]) -> ok.
refresh({_Dialog, List, LoadBtn, DeleteBtn, RenameBtn, Preview}, Entries) ->
    wxListCtrl:deleteAllItems(List),
    lists:foldl(fun(Entry, Idx) ->
        {NameCell, TimestampCell} = entry_cells(Entry),
        wxListCtrl:insertItem(List, Idx, NameCell),
        wxListCtrl:setItem(List, Idx, 1, TimestampCell),
        Idx + 1
    end, 0, Entries),
    case Entries of
        [] -> ok;
        [First | _] ->
            wxListCtrl:setItemState(List, 0, ?wxLIST_STATE_SELECTED, ?wxLIST_STATE_SELECTED),
            update_preview(Preview, First)
    end,
    update_buttons(List, Entries, LoadBtn, DeleteBtn, RenameBtn),
    ok.

%% @doc Enable/disable the action buttons for the current selection: Load is
%% enabled when a save is selected; Delete and Rename need a selected save
%% that is not the fixed quick slot ("Last Quicksave", which only Load may
%% touch). Caller hooks this up to the selection-change event.
-spec update_buttons(wxListCtrl:wxListCtrl(), [{string(), string(), string(), string(), string()}],
                     wxButton:wxButton(), wxButton:wxButton(), wxButton:wxButton()) -> ok.
update_buttons(List, Entries, LoadBtn, DeleteBtn, RenameBtn) ->
    case selected_entry(List, Entries) of
        undefined ->
            wxWindow:disable(LoadBtn),
            wxWindow:disable(DeleteBtn),
            wxWindow:disable(RenameBtn);
        {Stamp, _Name, _Timestamp, _SavePath, _MetaPath} ->
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
-spec selected_entry(wxListCtrl:wxListCtrl(), [{string(), string(), string(), string(), string()}]) ->
    {string(), string(), string(), string(), string()} | undefined.
selected_entry(List, Entries) ->
    case wxListCtrl:getNextItem(List, -1,
                                [{geometry, ?wxLIST_NEXT_ALL},
                                 {state, ?wxLIST_STATE_SELECTED}]) of
        -1 -> undefined;
        Idx when Idx >= 0, Idx < length(Entries) -> lists:nth(Idx + 1, Entries);
        _ -> undefined
    end.

%% @doc The two list cells for a history entry, derived from the save's%% metadata. The fixed quick slot always shows its file base (`Last
%% Quicksave') in the Name cell — its identity comes from its fixed file
%% name, whatever its meta says. Any other save shows the human name; the
%% Timestamp cell always shows the save timestamp. A save without a name in
%% the meta (legacy archive copies) shows its file base in the Name cell; an
%% unnamed save (name falls back to the timestamp) shows an empty Name cell
%% and the timestamp only.
-spec entry_cells({string(), string(), string(), string(), string()}) ->
    {string(), string()}.
entry_cells(Entry = {Base, _Name, Timestamp, _Sna, _Meta}) ->
    case ezx_saves:is_quick_slot(Base) of
        true -> {Base, Timestamp};
        false -> entry_cells_regular(Entry)
    end.

entry_cells_regular({Base, "", Timestamp, _Sna, _Meta}) -> {Base, Timestamp};
entry_cells_regular({_Base, Name, Timestamp, _Sna, _Meta}) when Name =/= Timestamp -> {Name, Timestamp};
entry_cells_regular({_Base, Name, _Timestamp, _Sna, _Meta}) -> {"", Name}.

%% @doc Show the screenshot of the selected save in the preview pane, scaled
%% to fit. A save without a screenshot sidecar (old saves) falls back to the
%% placeholder icon.
-spec update_preview(wxStaticBitmap:wxStaticBitmap(),
                     {string(), string(), string(), string(), string()} | undefined) -> ok.
update_preview(_Preview, undefined) ->
    ok;
update_preview(Preview, {_Base, _Name, _Timestamp, SavePath, _MetaPath}) ->
    Bmp = case filelib:is_regular(ezx_saves:png_path(SavePath)) of
        true -> load_preview(ezx_saves:png_path(SavePath));
        false -> error
    end,
    case Bmp of
        {ok, Bitmap} -> wxStaticBitmap:setBitmap(Preview, Bitmap);
        error -> wxStaticBitmap:setBitmap(Preview, placeholder_bitmap())
    end,
    ok.

load_preview(PngPath) ->
    try
        Img = wxImage:new(PngPath),
        Scaled = wxImage:scale(Img, ?PREVIEW_W, ?PREVIEW_H),
        Bitmap = wxBitmap:new(Scaled),
        wxImage:destroy(Img),
        wxImage:destroy(Scaled),
        {ok, Bitmap}
    catch _:_ -> error
    end.

%% @doc The placeholder for a save without a screenshot: the app icon scaled
%% into the preview box (a blank bitmap if the icon is missing).
placeholder_bitmap() ->
    try
        Img = wxImage:new(filename:join(ezx_ui_lib:priv_dir(), "ezx.png")),
        Scaled = wxImage:scale(Img, ?PREVIEW_W, ?PREVIEW_H),
        Bitmap = wxBitmap:new(Scaled),
        wxImage:destroy(Img),
        wxImage:destroy(Scaled),
        Bitmap
    catch _:_ ->
        wxBitmap:new({?PREVIEW_W, ?PREVIEW_H})
    end.
