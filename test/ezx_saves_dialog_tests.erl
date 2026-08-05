-module(ezx_saves_dialog_tests).

-include_lib("eunit/include/eunit.hrl").

entry_cells_named_save_test() ->
    ?assertEqual({"FistComp3", "20260805-212201"},
                 ezx_saves_dialog:entry_cells(
                   {"FistComp3-20260805-212201", "FistComp3", "20260805-212201", "a", "b"})).

entry_cells_unnamed_save_test() ->
    ?assertEqual({"", "20260805-212201"},
                 ezx_saves_dialog:entry_cells(
                   {"20260805-212201", "20260805-212201", "20260805-212201", "a", "b"})).

entry_cells_no_name_test() ->
    ?assertEqual({"Last Quicksave", "20260805-212201"},
                 ezx_saves_dialog:entry_cells(
                   {"Last Quicksave", "", "20260805-212201", "a", "b"})).

entry_cells_quick_slot_keeps_identity_test() ->
    %% A quick slot whose meta carries a name (written by a buggy build)
    %% still shows its fixed file base, not the game name.
    ?assertEqual({"Last Quicksave", "20260805-212201"},
                 ezx_saves_dialog:entry_cells(
                   {"Last Quicksave", "My Game - Quicksave", "20260805-212201", "a", "b"})).

entry_cells_no_timestamp_test() ->
    ?assertEqual({"FistComp3", ""},
                 ezx_saves_dialog:entry_cells(
                   {"20260805-212201", "FistComp3", "", "a", "b"})).

entry_cells_archive_test() ->
    ?assertEqual({"Game-quicksave-20260805-212201", "20260805-212201"},
                 ezx_saves_dialog:entry_cells(
                   {"Game-quicksave-20260805-212201", "", "20260805-212201", "a", "b"})).
