-module(ezx_kempston_mouse).

-export([new/0, move/3, set_buttons/2, read/2]).

%% =====================================================================
%% Kempston mouse — what it is and how it works
%% =====================================================================
%%
%% The Kempston mouse is the classic ZX Spectrum mouse interface,
%% produced by Kempston Micro Electronics (the same company behind the
%% Kempston joystick). It is a simple, cheap interface that plugs into
%% the machine and drives a standard two-button (sometimes three-button)
%% mouse. Its only output is a handful of read-only I/O registers — it
%% produces no interrupts and has no write register. Software has to
%% poll the ports.
%%
%% Despite the primitive interface it was used by real software:
%%   - Where Time Stood Still (Ocean) — mouse-driven adventure
%%   - OCP Art Studio — drawing/design program
%%   - "Kempston Wheel Mouse Tester" (Cygnus) — a test utility that
%%     displays the raw X/Y counters and button state
%%
%% Hardware behaviour being emulated here:
%%
%%   1. Two 8-bit counters, one per axis, range 0..255 with wrap-around.
%%      The interface does NOT track an absolute cursor position. Every
%%      mouse movement pulse increments/decrements the matching counter,
%%      so the host must feed it relative deltas and let it roll over
%%      (e.g. moving right by 3 then 300 gives X = 47 = (0 + 3 + 300)
%%      mod 256).
%%
%%   2. Three read-only registers: x and y counters (0..255) and a
%%      buttons register. Which I/O ports select which register is NOT
%%      this module's business: port decoding is owned by the emulator
%%      (ezx_emulator / ezx_emulator_128), so the same interface could
%%      sit on different ports on a different machine.
%%
%%   3. Buttons are active-low: a set bit means "not pressed", a cleared
%%      bit means "pressed". Default (nothing held) reads 0x07.
%%        bit 0 = right button
%%        bit 1 = left button
%%        bit 2 = middle button (present on some clones)
%%      Note: both left/right layouts exist on real hardware (D0/D1
%%      swapped on some clones), so drivers often auto-configure on the
%%      first pressed button. We follow the "D0 = right" layout, which
%%      matches Fuse.
%%
%%   4. Y direction: moving the mouse UP increments the Y counter, moving
%%      DOWN decrements it (same convention as X being positive to the
%%      right). Host screen Y grows downwards, so the host must negate the
%%      screen delta before feeding it in (up = +Y).
%%      The direction is only a convention of the interface: some guest
%%      software still flips it again.
%%
%% Because the counters wrap at 256, a program that wants a cursor keeps
%% its own position and computes movement as
%%     (new_counter - old_counter) mod 256
%% on each poll. This module just provides the counters + button mask;
%% wiring it into the emulator lives in ezx_emulator and ezx_emulator_128.
%% =====================================================================

%% @doc Kempston mouse state: two 8-bit wrap-around counters accumulated
%% from host mouse deltas plus an active-low button mask.
-record(kempston_mouse, {
    x = 0 :: 0..255,
    y = 0 :: 0..255,
    buttons = 16#07 :: 0..16#FF
}).

%% @doc Default mouse state: counters at 0, no buttons pressed.
-spec new() -> #kempston_mouse{}.
new() -> #kempston_mouse{}.

%% @doc Accumulate host mouse deltas into the 8-bit counters (0..255, roll-over).
-spec move(#kempston_mouse{}, integer(), integer()) -> #kempston_mouse{}.
move(#kempston_mouse{x = X, y = Y} = Mouse, DX, DY) ->
    Mouse#kempston_mouse{
        x = (X + DX) band 16#FF,
        y = (Y + DY) band 16#FF
    }.

%% @doc Set the button mask (active-low: bit 0 = right, bit 1 = left,
%% bit 2 = middle, cleared bit = pressed).
-spec set_buttons(#kempston_mouse{}, non_neg_integer()) -> #kempston_mouse{}.
set_buttons(#kempston_mouse{} = Mouse, Buttons) ->
    Mouse#kempston_mouse{buttons = Buttons band 16#FF}.

%% @doc Read one of the mouse registers. Which I/O ports map to a register
%% is decided by the emulator, not by this module.
-spec read(#kempston_mouse{}, x | y | buttons) -> 0..255.
read(#kempston_mouse{x = X}, x) -> X;
read(#kempston_mouse{y = Y}, y) -> Y;
read(#kempston_mouse{buttons = Buttons}, buttons) -> Buttons.
