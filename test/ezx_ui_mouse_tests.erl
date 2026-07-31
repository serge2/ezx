-module(ezx_ui_mouse_tests).

-include("ezx_emulator.hrl").
-include_lib("eunit/include/eunit.hrl").

%% --- state accessors ---

new_disabled_test() ->
    Mouse = ezx_ui_mouse:new(),
    ?assertEqual(false, ezx_ui_mouse:enabled(Mouse)),
    ?assertEqual(16#07, ezx_ui_mouse:buttons(Mouse)),
    ?assertEqual(undefined, ezx_ui_mouse:last_pos(Mouse)).
new_with_enabled_test() ->
    Mouse = ezx_ui_mouse:new(true),
    ?assertEqual(true, ezx_ui_mouse:enabled(Mouse)),
    ?assertEqual(false, ezx_ui_mouse:swap_buttons(Mouse)).

new_with_swap_test() ->
    Mouse = ezx_ui_mouse:new(true, true),
    ?assertEqual(true, ezx_ui_mouse:enabled(Mouse)),
    ?assertEqual(true, ezx_ui_mouse:swap_buttons(Mouse)).

%% --- enabling / applying to a machine ---

set_enabled_toggles_machine_test() ->
    Machine0 = init_machine(),
    {Mouse1, Machine1} = ezx_ui_mouse:set_enabled(ezx_ui_mouse:new(), Machine0, true),
    ?assert(ezx_ui_mouse:enabled(Mouse1)),
    ?assertNotEqual(undefined, Machine1#machine_state.kempston_mouse),
    {Mouse2, Machine2} = ezx_ui_mouse:set_enabled(Mouse1, Machine1, false),
    ?assertEqual(false, ezx_ui_mouse:enabled(Mouse2)),
    ?assertEqual(undefined, Machine2#machine_state.kempston_mouse).

apply_to_machine_enables_when_ui_enabled_test() ->
    Machine0 = init_machine(),
    Machine1 = ezx_ui_mouse:apply_to_machine(ezx_ui_mouse:new(true), Machine0),
    ?assertNotEqual(undefined, Machine1#machine_state.kempston_mouse),
    Machine2 = ezx_ui_mouse:apply_to_machine(ezx_ui_mouse:new(false), Machine0),
    ?assertEqual(undefined, Machine2#machine_state.kempston_mouse).

apply_to_machine_undefined_machine_test() ->
    {M1, U1} = {ezx_ui_mouse:apply_to_machine(ezx_ui_mouse:new(true), undefined), undefined},
    ?assertEqual(undefined, M1),
    ?assertEqual(undefined, U1).

set_enabled_undefined_machine_test() ->
    {Mouse1, Machine1} = ezx_ui_mouse:set_enabled(ezx_ui_mouse:new(), undefined, true),
    ?assert(ezx_ui_mouse:enabled(Mouse1)),
    ?assertEqual(undefined, Machine1).

%% --- motion ---

motion_feeds_deltas_when_enabled_test() ->
    Machine0 = init_machine(),
    Mouse0 = ezx_ui_mouse:new(true),
    Machine0a = ezx_ui_mouse:apply_to_machine(Mouse0, Machine0),
    {Mouse1, Machine1} = ezx_ui_mouse:motion(Mouse0, Machine0a, 100, 100, 1),
    ?assertEqual({100, 100}, ezx_ui_mouse:last_pos(Mouse1)),
    {Mouse2, Machine2} = ezx_ui_mouse:motion(Mouse1, Machine1, 105, 98, 1),
    ?assertEqual({105, 98}, ezx_ui_mouse:last_pos(Mouse2)),
    MouseRec = Machine2#machine_state.kempston_mouse,
    ?assertEqual(5, ezx_kempston_mouse:read(MouseRec, 16#FBDF)),
    ?assertEqual(2, ezx_kempston_mouse:read(MouseRec, 16#FFDF)).

motion_y_up_is_positive_test() ->
    Machine0 = init_machine(),
    Mouse0 = ezx_ui_mouse:new(true),
    Machine0a = ezx_ui_mouse:apply_to_machine(Mouse0, Machine0),
    {Mouse1, Machine1} = ezx_ui_mouse:motion(Mouse0, Machine0a, 50, 50, 1),
    {Mouse2, Machine2} = ezx_ui_mouse:motion(Mouse1, Machine1, 50, 40, 1),
    ?assertEqual(0, ezx_kempston_mouse:read(
        Machine2#machine_state.kempston_mouse, 16#FBDF)),
    ?assertEqual(10, ezx_kempston_mouse:read(
        Machine2#machine_state.kempston_mouse, 16#FFDF)),
    {_Mouse3, Machine3} = ezx_ui_mouse:motion(Mouse2, Machine2, 50, 45, 1),
    ?assertEqual(5, ezx_kempston_mouse:read(
        Machine3#machine_state.kempston_mouse, 16#FFDF)).

%% --- window-scale correction ---

motion_scales_deltas_by_window_scale_test() ->
    Machine0 = init_machine(),
    Mouse0 = ezx_ui_mouse:new(true),
    Machine0a = ezx_ui_mouse:apply_to_machine(Mouse0, Machine0),
    {Mouse1, Machine1} = ezx_ui_mouse:motion(Mouse0, Machine0a, 100, 100, 2),
    {Mouse2, Machine2} = ezx_ui_mouse:motion(Mouse1, Machine1, 104, 100, 2),
    ?assertEqual(2, read_x(Machine2)),
    {Mouse3, Machine3} = ezx_ui_mouse:motion(Mouse2, Machine2, 110, 100, 3),
    ?assertEqual(4, read_x(Machine3)),
    ?assertEqual(0, read_y(Machine3)).

motion_accumulates_remainder_at_scale_test() ->
    Machine0 = init_machine(),
    Mouse0 = ezx_ui_mouse:new(true),
    Machine0a = ezx_ui_mouse:apply_to_machine(Mouse0, Machine0),
    {_MouseA, MachineA} = move_n(Mouse0, Machine0a, 3, 3),
    ?assertEqual(1, read_x(MachineA)),
    {_MouseB, MachineB} = move_n(Mouse0, Machine0a, 6, 3),
    ?assertEqual(2, read_x(MachineB)).

reset_baseline_drops_remainder_test() ->
    Machine0 = init_machine(),
    Mouse0 = ezx_ui_mouse:new(true),
    Machine0a = ezx_ui_mouse:apply_to_machine(Mouse0, Machine0),
    {Mouse1, Machine1} = ezx_ui_mouse:motion(Mouse0, Machine0a, 100, 100, 3),
    {Mouse2, Machine2} = ezx_ui_mouse:motion(Mouse1, Machine1, 101, 100, 3),
    ?assertEqual(0, read_x(Machine2)),
    {Mouse3, Machine3} = ezx_ui_mouse:motion(
        ezx_ui_mouse:reset_baseline(Mouse2), Machine2, 201, 100, 3),
    {Mouse4, Machine4} = ezx_ui_mouse:motion(Mouse3, Machine3, 204, 100, 3),
    ?assertEqual(1, read_x(Machine4)).

motion_tracks_position_when_disabled_test() ->
    Machine0 = init_machine(),
    Mouse0 = ezx_ui_mouse:new(false),
    {Mouse1, Machine1} = ezx_ui_mouse:motion(Mouse0, Machine0, 10, 20, 1),
    ?assertEqual({10, 20}, ezx_ui_mouse:last_pos(Mouse1)),
    ?assertEqual(undefined, Machine1#machine_state.kempston_mouse).

motion_with_undefined_machine_test() ->
    {Mouse1, Machine1} = ezx_ui_mouse:motion(ezx_ui_mouse:new(true), undefined, 7, 9, 1),
    ?assertEqual({7, 9}, ezx_ui_mouse:last_pos(Mouse1)),
    ?assertEqual(undefined, Machine1).

reset_baseline_clears_pos_test() ->
    Mouse0 = ezx_ui_mouse:new(true),
    Mouse1 = ezx_ui_mouse:reset_baseline(Mouse0),
    ?assertEqual(undefined, ezx_ui_mouse:last_pos(Mouse1)),
    {Mouse2, Machine2} = ezx_ui_mouse:motion(Mouse1, undefined, 5, 5, 1),
    ?assertEqual(undefined, Machine2),
    Mouse3 = ezx_ui_mouse:reset_baseline(Mouse2),
    ?assertEqual(undefined, ezx_ui_mouse:last_pos(Mouse3)).

%% --- buttons ---

button_updates_active_low_mask_test() ->
    Mouse0 = ezx_ui_mouse:new(),
    Mouse1 = button(Mouse0, left, true),
    ?assertEqual(16#05, ezx_ui_mouse:buttons(Mouse1)),
    Mouse2 = button(Mouse1, right, true),
    ?assertEqual(16#04, ezx_ui_mouse:buttons(Mouse2)),
    Mouse3 = button(Mouse2, middle, true),
    ?assertEqual(16#00, ezx_ui_mouse:buttons(Mouse3)),
    Mouse4 = button(Mouse3, left, false),
    ?assertEqual(16#02, ezx_ui_mouse:buttons(Mouse4)),
    Mouse5 = button(Mouse4, right, false),
    ?assertEqual(16#03, ezx_ui_mouse:buttons(Mouse5)),
    Mouse6 = button(Mouse5, middle, false),
    ?assertEqual(16#07, ezx_ui_mouse:buttons(Mouse6)).

button_feeds_mask_to_machine_when_enabled_test() ->
    Machine0 = init_machine(),
    {Mouse1, Machine1} = ezx_ui_mouse:set_enabled(ezx_ui_mouse:new(), Machine0, true),
    {Mouse2, Machine2} = ezx_ui_mouse:button(Mouse1, Machine1, left, true),
    ?assertEqual(16#05, ezx_ui_mouse:buttons(Mouse2)),
    ?assertEqual(16#05, read_buttons(Machine2)),
    {_Mouse3, Machine3} = ezx_ui_mouse:button(Mouse2, Machine2, right, true),
    ?assertEqual(16#04, read_buttons(Machine3)).

button_tracks_mask_when_disabled_test() ->
    Machine0 = init_machine(),
    {Mouse1, Machine1} = ezx_ui_mouse:button(ezx_ui_mouse:new(), Machine0, left, true),
    ?assertEqual(16#05, ezx_ui_mouse:buttons(Mouse1)),
    ?assertEqual(undefined, Machine1#machine_state.kempston_mouse).

button_with_undefined_machine_test() ->
    {Mouse1, Machine1} = ezx_ui_mouse:button(ezx_ui_mouse:new(), undefined, middle, true),
    ?assertEqual(16#03, ezx_ui_mouse:buttons(Mouse1)),
    ?assertEqual(undefined, Machine1).

button_swap_flips_left_right_test() ->
    Mouse0 = ezx_ui_mouse:set_swap_buttons(ezx_ui_mouse:new(), true),
    Mouse1 = button(Mouse0, left, true),
    ?assertEqual(16#06, ezx_ui_mouse:buttons(Mouse1)),
    Mouse2 = button(Mouse1, right, true),
    ?assertEqual(16#04, ezx_ui_mouse:buttons(Mouse2)),
    Mouse3 = button(Mouse2, left, false),
    ?assertEqual(16#05, ezx_ui_mouse:buttons(Mouse3)),
    Mouse4 = button(Mouse3, right, false),
    ?assertEqual(16#07, ezx_ui_mouse:buttons(Mouse4)).

button_swap_preserves_middle_test() ->
    Mouse0 = ezx_ui_mouse:set_swap_buttons(ezx_ui_mouse:new(), true),
    Mouse1 = button(Mouse0, middle, true),
    ?assertEqual(16#03, ezx_ui_mouse:buttons(Mouse1)),
    Mouse2 = button(Mouse1, middle, false),
    ?assertEqual(16#07, ezx_ui_mouse:buttons(Mouse2)).

button_swap_feeds_machine_test() ->
    Machine0 = init_machine(),
    {Mouse1, Machine1} = ezx_ui_mouse:set_enabled(ezx_ui_mouse:new(true, true), Machine0, true),
    {_Mouse2, Machine2} = ezx_ui_mouse:button(Mouse1, Machine1, left, true),
    ?assertEqual(16#06, read_buttons(Machine2)).

%% --- helpers ---

move_n(Mouse, Machine, N, Scale) ->
    {Mouse1, Machine1} = ezx_ui_mouse:motion(Mouse, Machine, 100, 100, Scale),
    lists:foldl(fun(Step, {M, Ma}) ->
        ezx_ui_mouse:motion(M, Ma, 100 + Step, 100, Scale)
    end, {Mouse1, Machine1}, lists:seq(1, N)).

read_x(Machine) ->
    ezx_kempston_mouse:read(Machine#machine_state.kempston_mouse, 16#FBDF).

read_y(Machine) ->
    ezx_kempston_mouse:read(Machine#machine_state.kempston_mouse, 16#FFDF).

button(Mouse, Button, Pressed) ->
    {Mouse1, _} = ezx_ui_mouse:button(Mouse, undefined, Button, Pressed),
    Mouse1.

read_buttons(Machine) ->
    ezx_kempston_mouse:read(Machine#machine_state.kempston_mouse, 16#FADF).

init_machine() ->
    RomPath = try filename:join([code:priv_dir(ezx), "roms", "48.rom"])
    catch error:badarg ->
        BeamDir = filename:dirname(code:which(?MODULE)),
        filename:join([filename:dirname(BeamDir), "priv", "roms", "48.rom"])
    end,
    {ok, Rom} = file:read_file(RomPath),
    ezx_emulator:init(z80_cpu, ezx_memory_48, ezx_screen, ezx_keyboard, ezx_beeper, undefined, Rom).
