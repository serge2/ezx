-module(ezx_ui_mouse).

-include("ezx_emulator.hrl").

%% Host-side UI state for the optional Kempston mouse: the enable flag,
%% whether the left/right buttons are swapped, the last panel cursor
%% position (to compute motion deltas), the sub-pixel remainder of the
%% display-scale correction and the active-low button mask.
%% Extracting this from ezx_ui keeps the wx event plumbing thin and makes
%% the mouse state transitions testable in isolation.
%%
%% Motion deltas are host panel pixels; at a window scale of N the guest
%% screen is blown up Nx, so each host pixel is only 1/N guest pixels.
%% The caller passes the current display scale and motion divides the
%% deltas by it, keeping the guest cursor matched to the host cursor.
%%
%% Machine interaction is delegated to ezx_emulator:set_mouse_enabled/2,
%% set_mouse_position/3 and set_mouse_buttons/2 (which are no-ops unless
%% the mouse is present in the machine). All functions accept Machine =
%% undefined, so the UI can route events before the emulator exists.

-export([
    new/0,
    new/1,
    new/2,
    enabled/1,
    swap_buttons/1,
    buttons/1,
    last_pos/1,
    apply_to_machine/2,
    set_enabled/3,
    set_swap_buttons/2,
    motion/5,
    button/4,
    reset_baseline/1
]).

%% Buttons: bit 0 right, bit 1 left, bit 2 middle (active-low, so a
%% cleared bit means "pressed"). Note: both left/right layouts exist on
%% real hardware (D0/D1 swapped on some clones), so drivers often
%% auto-configure on the first pressed button. The default (bit 0 =
%% right) matches Fuse; swap_buttons flips it for clones with the
%% reversed D0/D1 wiring.
-define(BTN_LEFT, 16#02).
-define(BTN_RIGHT, 16#01).
-define(BTN_MIDDLE, 16#04).

-record(ui_mouse, {
    enabled = false :: boolean(),
    swap_buttons = false :: boolean(),
    last_pos = undefined :: {integer(), integer()} | undefined,
    fraction = {0.0, 0.0} :: {float(), float()},
    buttons = 16#07 :: 0..255
}).

%% @doc Default UI mouse state: disabled.
-spec new() -> #ui_mouse{}.
new() -> #ui_mouse{}.

%% @doc UI mouse state with a configured enable flag.
-spec new(boolean()) -> #ui_mouse{}.
new(Enabled) when is_boolean(Enabled) ->
    #ui_mouse{enabled = Enabled}.

%% @doc UI mouse state with a configured enable flag and left/right
%% button swap.
-spec new(boolean(), boolean()) -> #ui_mouse{}.
new(Enabled, SwapButtons) when is_boolean(Enabled), is_boolean(SwapButtons) ->
    #ui_mouse{enabled = Enabled, swap_buttons = SwapButtons}.

-spec enabled(#ui_mouse{}) -> boolean().
enabled(#ui_mouse{enabled = E}) -> E.

-spec swap_buttons(#ui_mouse{}) -> boolean().
swap_buttons(#ui_mouse{swap_buttons = S}) -> S.

-spec buttons(#ui_mouse{}) -> 0..255.
buttons(#ui_mouse{buttons = B}) -> B.

-spec last_pos(#ui_mouse{}) -> {integer(), integer()} | undefined.
last_pos(#ui_mouse{last_pos = P}) -> P.

%% @doc Enable the mouse in a freshly created machine if it is enabled in
%% the UI. Used after machine init/reset/type-switch/file loads.
-spec apply_to_machine(#ui_mouse{}, #machine_state{} | undefined) -> #machine_state{} | undefined.
apply_to_machine(#ui_mouse{enabled = true}, Machine) when Machine =:= undefined ->
    undefined;
apply_to_machine(#ui_mouse{enabled = true}, Machine) ->
    ezx_emulator:set_mouse_enabled(Machine, true);
apply_to_machine(#ui_mouse{enabled = false}, Machine) ->
    Machine.

%% @doc Enable or disable the interface, reflecting the change in the
%% machine and dropping the cursor baseline and scaled-remainder.
-spec set_enabled(#ui_mouse{}, #machine_state{} | undefined, boolean()) ->
    {#ui_mouse{}, #machine_state{} | undefined}.
set_enabled(Mouse, Machine, Enabled) when is_boolean(Enabled) ->
    Machine1 = case Machine of
        undefined -> undefined;
        _ -> ezx_emulator:set_mouse_enabled(Machine, Enabled)
    end,
    {Mouse#ui_mouse{enabled = Enabled, last_pos = undefined, fraction = {0.0, 0.0}}, Machine1}.

%% @doc Swap the left/right button bits (for clones with the D0/D1
%% layout reversed).
-spec set_swap_buttons(#ui_mouse{}, boolean()) -> #ui_mouse{}.
set_swap_buttons(Mouse, SwapButtons) when is_boolean(SwapButtons) ->
    Mouse#ui_mouse{swap_buttons = SwapButtons}.

%% @doc Handle a panel motion event: feed the cursor delta to the machine
%% when enabled, otherwise just track the position for the next enable.
%% Panel Y grows downwards, so the vertical delta is negated before it
%% reaches the machine (Kempston: up = +Y). Deltas are divided by the
%% current window scale so the guest cursor matches the host cursor; the
%% fractional remainder is kept so small movements are not lost.
-spec motion(#ui_mouse{}, #machine_state{} | undefined, integer(), integer(), number()) ->
    {#ui_mouse{}, #machine_state{} | undefined}.
motion(Mouse, Machine, X, Y, _Scale) when Machine =:= undefined ->
    {Mouse#ui_mouse{last_pos = {X, Y}}, undefined};
motion(#ui_mouse{enabled = true, last_pos = LastPos,
                 fraction = {FX, FY}} = Mouse, Machine, X, Y, Scale) ->
    case LastPos of
        {LX, LY} ->
            {DX, FX1} = scale_delta(X - LX, Scale, FX),
            {DY, FY1} = scale_delta(LY - Y, Scale, FY),
            Machine1 = ezx_emulator:set_mouse_position(Machine, DX, DY),
            {Mouse#ui_mouse{last_pos = {X, Y}, fraction = {FX1, FY1}}, Machine1};
        undefined ->
            {Mouse#ui_mouse{last_pos = {X, Y}}, Machine}
    end;
motion(#ui_mouse{enabled = false} = Mouse, Machine, X, Y, _Scale) ->
    {Mouse#ui_mouse{last_pos = {X, Y}}, Machine}.

%% @doc Handle a button down/up event. Updates the active-low mask and
%% feeds it to the machine when enabled.
-spec button(#ui_mouse{}, #machine_state{} | undefined, left | right | middle, boolean()) ->
    {#ui_mouse{}, #machine_state{} | undefined}.
button(Mouse, Machine, Button, Pressed) when Machine =:= undefined ->
    {set_button(Mouse, Button, Pressed), undefined};
button(#ui_mouse{enabled = true} = Mouse, Machine, Button, Pressed) ->
    Mouse1 = set_button(Mouse, Button, Pressed),
    Machine1 = ezx_emulator:set_mouse_buttons(Machine, buttons(Mouse1)),
    {Mouse1, Machine1};
button(Mouse, Machine, Button, Pressed) ->
    {set_button(Mouse, Button, Pressed), Machine}.

%% @doc Drop the cursor baseline (and scaled-remainder) so the next motion
%% event only sets it. Used after window/crop/scale/fullscreen changes
%% where panel coordinates may jump.
-spec reset_baseline(#ui_mouse{}) -> #ui_mouse{}.
reset_baseline(Mouse) -> Mouse#ui_mouse{last_pos = undefined, fraction = {0.0, 0.0}}.

%% --- Internal ---

set_button(#ui_mouse{swap_buttons = Swap, buttons = B0} = Mouse, Button, Pressed) ->
    Bit = button_bit(Swap, Button),
    B1 = case Pressed of
        true -> B0 band (bnot Bit);
        false -> B0 bor Bit
    end,
    Mouse#ui_mouse{buttons = B1}.

button_bit(false, left) -> ?BTN_LEFT;
button_bit(false, right) -> ?BTN_RIGHT;
button_bit(true, left) -> ?BTN_RIGHT;
button_bit(true, right) -> ?BTN_LEFT;
button_bit(_Swap, middle) -> ?BTN_MIDDLE.

%% Divide a raw panel-pixel delta by the window scale, keeping the
%% fractional remainder for the next event (floor keeps it in [0, 1)).
scale_delta(Delta, Scale, Fraction) ->
    Sum = Delta / Scale + Fraction,
    Int = floor(Sum),
    {Int, Sum - Int}.
