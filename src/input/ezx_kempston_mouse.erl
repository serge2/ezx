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
%% mouse. Its only output is a handful of read-only I/O ports — it
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
%%   2. Three read-only ports, decoded on the FULL 16-bit address:
%%        - 0xFADF : buttons (active-low, see below)
%%        - 0xFBDF : X counter (0..255)
%%        - 0xFFDF : Y counter (0..255)
%%      Reading is normally done with `IN r,(C)' after loading the port
%%      into BC. Because A2/A5 are not decoded on the real hardware, the
%%      same registers also answer on the 0xFB low byte
%%      (0xFAFB / 0xFBFB / 0xFFFB); we accept both sets.
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
%% wiring it into the emulator (ports 0xFADF/0xFBDF/0xFFDF via
%% PortReadFun, optional/enabled-not-default) lives in ezx_emulator and
%% ezx_emulator_128.
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

%% @doc Read one of the Kempston mouse ports. Returns undefined for any
%% other port so the caller can fall back to other peripherals.
%% Ports: 0xFADF buttons, 0xFBDF X, 0xFFDF Y. The interface also
%% responds with the 0xFB low byte (A2/A5 not decoded on real hardware).
-spec read(#kempston_mouse{}, non_neg_integer()) -> 0..255 | undefined.
read(#kempston_mouse{buttons = Buttons, x = X, y = Y}, Port) ->
    case Port of
        16#FADF -> Buttons;
        16#FAFB -> Buttons;
        16#FBDF -> X;
        16#FBFB -> X;
        16#FFDF -> Y;
        16#FFFB -> Y;
        _ -> undefined
    end.
