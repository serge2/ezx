-module(ezx_screen).

-include("ezx_emulator.hrl").

%% ZX Spectrum ULA screen device: border color changes + attribute flash.
%% Also renders the frame into a flat RGB bitmap (pure, view-optional).
%%
%% Device frame contract (shared with the beeper and AY, physical-overrun
%% model):
%%   border_set(Screen, TState, Color) — record a border color change with an
%%                                       absolute counter stamp (machine
%%                                       t_states, 0 = nominal frame boundary)
%%   frame_render(Screen, FrameLen)   — produce the sorted local-time border
%%                                       changes, the base color, and the flash
%%                                       phase for the screen; advances the
%%                                       flash phase once per frame
%%
%% Border changes are stored newest-first with absolute counter stamps.
%% frame_render/2 splits them at the nominal frame length: changes with
%% counter < FrameLen belong to this frame (local time = counter), changes
%% with counter >= FrameLen belong to the NEXT frame and are carried over in
%% the returned state — rebased by -FrameLen into the next frame's counter
%% domain — never dropped.  The base color returned for this frame is the
%% color at the nominal boundary (#screen.init_color): the color the screen
%% had before the first change of the frame, exactly where the ULA timeline
%% puts it.  The live color — which already reflects the carried tail — is
%% kept in #screen.border_color.
%%
%% The flash phase advances at frame close (32-frame cycle); the FlashOn flag
%% returned by frame_render/2 matches flash_on/1 of the returned device. The
%% emulator stores it as the flash_on artifact alongside the border changes
%% and color, so render_frame/1 does not need to touch the device directly.

-export([new/0, new/1, border_set/3, border_get/1, flash_on/1, frame_render/2]).
-export([init_helper_tables/0, render_screen/5, render_screen/6]).

-on_load(init_helper_tables/0).

%% --- Device ---

-define(FLASH_CYCLE, 32).

-record(screen, {
    border_color = 0    :: 0..7,
    init_color = 0      :: 0..7,
    border_changes = [] :: [{non_neg_integer(), 0..7}],
    flash_phase = 0     :: 0..31
}).

-type state() :: #screen{}.
-export_type([state/0]).

%% @doc New screen device, starting at black, flash phase 0.
-spec new() -> state().
new() ->
    #screen{}.

%% @doc New screen device with a known border color (snapshot load).  The
%% boundary color (used as the base color for the first frame) is that color.
-spec new(0..7) -> state().
new(Color) ->
    #screen{border_color = Color, init_color = Color}.

%% @doc Record a border color change. No-op when the color is unchanged.
-spec border_set(state(), non_neg_integer(), 0..7) -> state().
border_set(#screen{border_color = Color} = S, _TState, Color) ->
    S;
border_set(#screen{border_changes = Changes} = S, TState, NewColor) ->
    S#screen{border_color = NewColor, border_changes = [{TState, NewColor} | Changes]}.

%% @doc Current live border color (already reflects frame-overrun zone writes).
-spec border_get(state()) -> 0..7.
border_get(#screen{border_color = Color}) -> Color.

%% @doc Flash phase flag: attributes with bit 7 set are inverted while true.
-spec flash_on(state()) -> boolean().
flash_on(#screen{flash_phase = Phase}) -> Phase div 16 =:= 1.

%% @doc Produce the screen output for one frame (exactly FrameLen T-states):
%% the sorted local-time border changes (changes with counter < FrameLen,
%% local time = counter; the frame-overrun changes with counter >= FrameLen
%% are carried over in the returned state, rebased by -FrameLen), the base
%% color for the screen (the color at the nominal frame boundary), the flash
%% flag, and the advanced device state (flash phase carried into the next
%% frame; init_color advanced to the color at the end of this frame's render
%% window = the next frame's boundary color).
-spec frame_render(state(), non_neg_integer()) ->
    {[{non_neg_integer(), 0..7}], 0..7, boolean(), state()}.
frame_render(#screen{border_color = Color, init_color = InitColor, border_changes = Changes,
                     flash_phase = Phase}, FrameLen) ->
    NewPhase = (Phase + 1) rem ?FLASH_CYCLE,
    Sorted = lists:reverse(Changes),
    Local = [{ET, C} || {ET, C} <- Sorted, ET < FrameLen],
    Tail = [{ET - FrameLen, C} || {ET, C} <- Sorted, ET >= FrameLen],
    {Local, InitColor, NewPhase div 16 =:= 1,
     #screen{border_color = Color, init_color = color_after(Local, InitColor),
             border_changes = Tail, flash_phase = NewPhase}}.

%% The color at the end of the render window (the nominal frame boundary):
%% the last rendered change's color, or the initial color when nothing
%% changed in the window.  This is the boundary color for the next frame.
color_after([], InitColor) -> InitColor;
color_after(Local, _InitColor) -> element(2, lists:last(Local)).

%% ============================================================================
%% Rendering
%% ============================================================================

%% Optimized renderer.
%%
%% The per-character pixel work is fully precomputed into a persistent_term
%% lookup table: for every (bitmap byte, ink color, paper color) combination —
%% ink/paper already including the brightness bit, 65536 entries — the 24
%% output RGB bytes are pre-blended with the mask XOR trick at load time.
%% Rendering a character is then a single element/2 lookup returning a shared
%% binary, so a frame allocates no per-character binaries at all.
%%
%% The whole frame is assembled through one threaded accumulator: each line
%% prepends its chunks (per-char 24-byte lookup entries, border runs) straight
%% into the same flat list — no per-line lists, no concatenation, no
%% intermediate binaries — and a single lists:reverse + list_to_binary/1
%% produces the bitmap (352×288 for the 48K/128K raster, 384×304 for the
%% Pentagon). Measured ~3.6x faster than the old per-char construction on a
%% real boot frame and roughly halves the GC traffic.

-define(COLORS_NORMAL, {
    {0, 0, 0}, {0, 0, 215}, {215, 0, 0}, {215, 0, 215},
    {0, 215, 0}, {0, 215, 215}, {215, 215, 0}, {215, 215, 215}
}).

-define(COLORS_BRIGHT, {
    {0, 0, 0}, {0, 0, 255}, {255, 0, 0}, {255, 0, 255},
    {0, 255, 0}, {0, 255, 255}, {255, 255, 0}, {255, 255, 255}
}).

-define(TABLES_KEY, ezx_screen_tables).

%% Rendered-frame geometry, precomputed from the model's line/frame geometry.
-record(geo, {
    win_start_t    :: pos_integer(),  %% visible window start T within the line
    win_end_t      :: pos_integer(),  %% visible window end T within the line
    screen_start_t :: pos_integer(),  %% screen start T within the line
    screen_end_t   :: pos_integer(),  %% screen end T within the line
    screen_x       :: pos_integer(),  %% screen x in px (within the window)
    left_width     :: pos_integer(),  %% border px left of the screen
    right_width    :: pos_integer(),  %% border px right of the screen
    window_top     :: pos_integer(),  %% first rendered line of the frame
    screen_y       :: pos_integer(),  %% first screen line (window-relative)
    full_width     :: pos_integer(),  %% window width in px
    full_height    :: pos_integer()   %% number of rendered lines
}).

init_helper_tables() ->
    Color8px = build_color_8px_table(),
    MaskTab = build_mask_table(),
    Lookup = build_lookup_table(Color8px, MaskTab),
    BorderRuns = maps:from_list([{W, build_border_runs(W)} || W <- geometry_widths()]),
    %% Color8px and MaskTab are build-time inputs for Lookup only — the
    %% renderer never reads them, so only the runtime tables are stored.
    persistent_term:put(?TABLES_KEY, {Lookup, BorderRuns}),
    ok.

%% The border-run widths the canonical geometries need: full window + left and
%% right border columns of each line geometry (48K/128K: 352/48/48, Pentagon:
%% 384/72/56).
geometry_widths() ->
    lists:usort(lists:append([begin
        {WinStart, WinEnd, ScreenStart, ScreenEnd} = LG,
        [(WinEnd - WinStart) * 2, (ScreenStart - WinStart) * 2, (WinEnd - ScreenEnd) * 2]
    end || LG <- [?LINE_GEOMETRY_48K, ?LINE_GEOMETRY_PENTAGON]])).

%% @doc Render a frame to a flat RGB binary. TStatesPerLine is the horizontal
%% scanline length in T-states (224 for the 48K/Pentagon raster, 228 for the
%% 128K). Uses the 48K/128K geometry (352×288).
-spec render_screen(binary(), boolean(), list(), non_neg_integer(), pos_integer()) -> binary().
render_screen(VideoBuffer, FlashOn, SortedBorderChanges, CurrentBorder, TStatesPerLine) ->
    render_screen(VideoBuffer, FlashOn, SortedBorderChanges, CurrentBorder,
                  TStatesPerLine, {?LINE_GEOMETRY_48K, ?FRAME_GEOMETRY_48K}).

%% @doc Render a frame to a flat RGB binary. TStatesPerLine is the horizontal
%% scanline length in T-states (224 for the 48K/Pentagon raster, 228 for the
%% 128K). Geometry is the model's {line_geometry, frame_geometry} pair (see
%% ezx_emulator.hrl): the 48K/128K {0, 176, 24, 152} + {16, 64, 288} window
%% (352×288, screen at pixels 48..303 / lines 64..255) or the Pentagon
%% {32, 224, 68, 196} + {16, 80, 304} window (384×304 — the FULL Pentagon
%% border, screen at pixels 72..327 / lines 80..271).
-spec render_screen(binary(), boolean(), list(), non_neg_integer(), pos_integer(),
                    {{pos_integer(), pos_integer(), pos_integer(), pos_integer()},
                     {pos_integer(), pos_integer(), pos_integer()}}) -> binary().
render_screen(VideoBuffer, FlashOn, SortedBorderChanges, CurrentBorder,
              TStatesPerLine, {LineGeometry, FrameGeometry}) ->
    {Lookup, BorderRuns} = persistent_term:get(?TABLES_KEY),
    <<Bitmap:6144/binary, Attrs:768/binary>> = VideoBuffer,
    Geo = make_geo(LineGeometry, FrameGeometry),
    Chunks = render_lines(Lookup, BorderRuns, FlashOn, Bitmap, Attrs,
                          SortedBorderChanges, CurrentBorder, Geo,
                          TStatesPerLine, 0, []),
    list_to_binary(lists:reverse(Chunks)).

make_geo({WinStartT, WinEndT, ScreenStartT, ScreenEndT},
         {WindowTop, ScreenStartLine, FullHeight}) ->
    ScreenX = (ScreenStartT - WinStartT) * 2,
    #geo{
        win_start_t = WinStartT,
        win_end_t = WinEndT,
        screen_start_t = ScreenStartT,
        screen_end_t = ScreenEndT,
        screen_x = ScreenX,
        left_width = ScreenX,
        right_width = (WinEndT - ScreenEndT) * 2,
        window_top = WindowTop,
        screen_y = ScreenStartLine - WindowTop,
        full_width = (WinEndT - WinStartT) * 2,
        full_height = FullHeight
    }.

%% ============================================================================
%% Line iteration
%%
%% The whole frame is assembled through ONE threaded accumulator: every line
%% prepends its chunks in forward order into Acc (reversed-frame order, so the
%% last chunk of the frame ends up at the head), and a single lists:reverse in
%% render_screen/5 turns it into the flat forward-order chunk list for the one
%% list_to_binary/1. No per-line lists, no concatenation, no intermediate
%% binaries — the per-char 24-byte lookup entries and border runs flow straight
%% into the final bitmap.
%% ============================================================================

render_lines(_L, _BR, _FO, _BM, _AR, _SC, _AC, Geo, _TSL, Y, Acc) when Y >= Geo#geo.full_height ->
    Acc;
render_lines(L, BR, FO, BM, AR, SC, AC, Geo, TSL, Y, Acc) ->
    {Acc1, SC1, NewAC} = render_line(L, BR, FO, BM, AR, SC, AC, Geo, TSL, Y, Acc),
    render_lines(L, BR, FO, BM, AR, SC1, NewAC, Geo, TSL, Y + 1, Acc1).

render_line(L, BR, FO, BM, AR, SC, AC, Geo, TSL, Y, Acc) when Y >= Geo#geo.screen_y, Y =< Geo#geo.screen_y + 191 ->
    render_screen_line(L, BR, FO, BM, AR, SC, AC, Geo, TSL, Y, Acc);
render_line(_L, BR, _FO, _BM, _AR, SC, AC, Geo, TSL, Y, Acc) ->
    render_border_only_line(BR, SC, AC, Geo, TSL, Y, Acc).

%% ============================================================================
%% Border-only line: the whole line is one border run (shared binary) unless a
%% border change falls inside, then build segments (rare).
%% ============================================================================

render_border_only_line(BorderRuns, SC, ActiveColor, Geo, TStatesPerLine, Y, Acc) ->
    LineT = (Y + Geo#geo.window_top) * TStatesPerLine,
    VStart = Geo#geo.win_start_t,
    EndT = LineT + Geo#geo.win_end_t - 1,
    {ColorBefore, LineChanges, SC1} = walk_line(SC, ActiveColor, LineT, EndT),
    EndColor = case LineChanges of
        [] -> ColorBefore;
        _ -> element(2, lists:last(LineChanges))
    end,
    %% The window base color is the color at the window start: changes in the
    %% pre-window zone (Pentagon retrace, before VStart) set the border color
    %% the visible window shows. Only the changes inside the visible window
    %% become pixel offsets — the pre-window ones must not.
    BaseColor = color_at_t(LineChanges, ColorBefore, LineT + VStart),
    Changes = filter_range(LineChanges, LineT + VStart, EndT),
    Acc1 = case Changes of
        [] -> [border_run(BorderRuns, Geo#geo.full_width, BaseColor) | Acc];
        _ -> prepend_all(build_segments(Changes, BaseColor, 0, Geo#geo.full_width, LineT, Geo, []), Acc)
    end,
    {Acc1, SC1, EndColor}.

%% ============================================================================
%% Screen line: the left border side, the 32 chars, and the right border side
%% are threaded straight into Acc (forward order) — the chars accumulate via
%% render_screen_pixels, the border sides via prepend_all.
%% ============================================================================

render_screen_line(Lookup, BorderRuns, FlashOn, Bitmap, Attrs, SC, ActiveColor, Geo, TStatesPerLine, Y, Acc) ->
    LineT = (Y + Geo#geo.window_top) * TStatesPerLine,
    VStart = Geo#geo.win_start_t,
    SS = Geo#geo.screen_start_t,
    SE = Geo#geo.screen_end_t,
    EndT = LineT + Geo#geo.win_end_t - 1,
    {ColorBefore, LineChanges, SC1} = walk_line(SC, ActiveColor, LineT, EndT),
    EndColor = case LineChanges of
        [] -> ColorBefore;
        _ -> element(2, lists:last(LineChanges))
    end,

    %% The left side base color is the color at the visible window start:
    %% changes before VStart (Pentagon retrace) still set the border color the
    %% window shows.
    LeftBaseColor = color_at_t(LineChanges, ColorBefore, LineT + VStart),
    Acc1 = prepend_all(border_side(LineChanges, LeftBaseColor, LineT, LineT + VStart,
                                   LineT + SS - 1, 0, Geo#geo.left_width, Geo, BorderRuns), Acc),

    ScreenY = Y - Geo#geo.screen_y,
    Third = ScreenY div 64,
    CharRowInThird = (ScreenY rem 64) div 8,
    PixelRow = ScreenY rem 8,
    CharRow = Third * 8 + CharRowInThird,
    BitmapRowOffset = Third * 2048 + CharRowInThird * 32 + PixelRow * 256,
    AttrRowOffset = CharRow * 32,
    FlashMask = case FlashOn of true -> 16#80; false -> 0 end,
    <<_:BitmapRowOffset/binary, BitmapRow:32/binary, _/binary>> = Bitmap,
    <<_:AttrRowOffset/binary, AttrRow:32/binary, _/binary>> = Attrs,
    Acc2 = render_screen_pixels(Lookup, FlashMask, BitmapRow, AttrRow, Acc1),

    RightBaseColor = color_at_t(LineChanges, ColorBefore, LineT + SE - 1),
    Acc3 = prepend_all(border_side(LineChanges, RightBaseColor, LineT, LineT + SE, EndT,
                                   Geo#geo.screen_x + 256, Geo#geo.right_width, Geo, BorderRuns), Acc2),
    {Acc3, SC1, EndColor}.

%% Border side of a screen line: a flat run of BaseColor (shared binary) unless
%% a border change falls in [MinT, MaxT]; then build segments (rare). Returns
%% the chunks in forward order — the caller threads them into the accumulator.
border_side(LineChanges, BaseColor, LineT, MinT, MaxT, StartPx, Width, Geo, BorderRuns) ->
    Changes = filter_range(LineChanges, MinT, MaxT),
    case Changes of
        [] -> [border_run(BorderRuns, Width, BaseColor)];
        _ -> build_segments(Changes, BaseColor, StartPx, StartPx + Width, LineT, Geo, [])
    end.

%% Shared border run of the given width and color, from the cached runs when
%% available (canonical widths) or built on the fly otherwise (rare).
border_run(BorderRuns, Width, Color) ->
    Runs = case maps:find(Width, BorderRuns) of
        {ok, R} -> R;
        error -> build_border_runs(Width)
    end,
    element(Color + 1, Runs).

%% Prepend a forward-order chunk list into the reversed-frame accumulator.
prepend_all([], Acc) -> Acc;
prepend_all([Chunk | Rest], Acc) -> prepend_all(Rest, [Chunk | Acc]).

%% ============================================================================
%% Screen pixels: per char one shared 24-byte binary via the lookup table.
%% Prepend each char (left to right) into the threaded frame accumulator; the
%% caller handles the border sides around them.
%% ============================================================================

render_screen_pixels(_L, _FM, <<>>, <<>>, Acc) ->
    Acc;
render_screen_pixels(Lookup, FlashMask,
                     <<BmByte:8, BMT/binary>>, <<AttrByte:8, ART/binary>>, Acc) ->
    Ink = AttrByte band 16#07,
    Paper = (AttrByte bsr 3) band 16#07,
    {Ink1, Paper1} = case AttrByte band FlashMask of
        0 -> {Ink, Paper};
        _ -> {Paper, Ink}
    end,
    Bright = (AttrByte bsr 6) band 1,
    Idx = BmByte * 256 + (Bright * 8 + Ink1) * 16 + (Bright * 8 + Paper1),
    render_screen_pixels(Lookup, FlashMask, BMT, ART, [element(Idx + 1, Lookup) | Acc]).

%% ============================================================================
%% Table building
%% ============================================================================

build_color_8px_table() ->
    AllColors = tuple_to_list(?COLORS_NORMAL) ++ tuple_to_list(?COLORS_BRIGHT),
    Entries = [begin
        {R, G, B} = lists:nth(Idx + 1, AllColors),
        <<R, G, B, R, G, B, R, G, B, R, G, B,
          R, G, B, R, G, B, R, G, B, R, G, B>>
    end || Idx <- lists:seq(0, 15)],
    list_to_tuple(Entries).

build_mask_table() ->
    Entries = [build_mask(Bm) || Bm <- lists:seq(0, 255)],
    list_to_tuple(Entries).

build_mask(Bm) ->
    Pixels = [begin
        BitMask = 1 bsl (7 - Pos),
        case Bm band BitMask of
            0 -> <<0, 0, 0>>;
            _ -> <<255, 255, 255>>
        end
    end || Pos <- lists:seq(0, 7)],
    list_to_binary(Pixels).

%% Per (bitmap byte, ink, paper) the 24 pre-blended RGB bytes. Ink/paper are
%% already brightness-combined color indices (Bright*8 + Color). Flash is not
%% baked in: it swaps ink/paper before the lookup, so two flash states share
%% the table.
build_lookup_table(Color8px, MaskTab) ->
    list_to_tuple(
        [begin
            <<M1:32, M2:32, M3:32, M4:32, M5:32, M6:32>> = element(Bm + 1, MaskTab),
            <<P1:32, P2:32, P3:32, P4:32, P5:32, P6:32>> = element(Paper + 1, Color8px),
            <<I1:32, I2:32, I3:32, I4:32, I5:32, I6:32>> = element(Ink + 1, Color8px),
            D1 = P1 bxor I1, R1 = P1 bxor (D1 band M1),
            D2 = P2 bxor I2, R2 = P2 bxor (D2 band M2),
            D3 = P3 bxor I3, R3 = P3 bxor (D3 band M3),
            D4 = P4 bxor I4, R4 = P4 bxor (D4 band M4),
            D5 = P5 bxor I5, R5 = P5 bxor (D5 band M5),
            D6 = P6 bxor I6, R6 = P6 bxor (D6 band M6),
            <<R1:32, R2:32, R3:32, R4:32, R5:32, R6:32>>
        end || Bm <- lists:seq(0, 255),
               Ink <- lists:seq(0, 15),
               Paper <- lists:seq(0, 15)]).

%% A run of each of the 8 border colors, Pixels wide — shared binaries,
%% reused by every line.
build_border_runs(Pixels) ->
    list_to_tuple([begin
        {R, G, B} = element(C + 1, ?COLORS_NORMAL),
        binary:copy(<<R, G, B>>, Pixels)
    end || C <- lists:seq(0, 7)]).

%% ============================================================================
%% Utility functions
%% ============================================================================

color_copy(Idx, Count) ->
    {R, G, B} = element(Idx + 1, ?COLORS_NORMAL),
    binary:copy(<<R, G, B>>, Count).

color_at_t([], Default, _T) -> Default;
color_at_t([{T, Color} | Rest], _Default, TState) when T =< TState ->
    color_at_t(Rest, Color, TState);
color_at_t(_, Default, _T) -> Default.

%% Map a T-state offset within a scanline to the window pixel column, given
%% the line geometry (window/screen regions in #geo{}). The three regions are
%% rendered at 2 px per T-state: the border before the screen, the 128-T
%% screen itself, and the border after it.
tstate_to_pixel(Offset, Geo) when Offset < Geo#geo.screen_start_t ->
    (Offset - Geo#geo.win_start_t) * 2;
tstate_to_pixel(Offset, Geo) when Offset < Geo#geo.screen_end_t ->
    Geo#geo.screen_x + (Offset - Geo#geo.screen_start_t) * 2;
tstate_to_pixel(Offset, Geo) ->
    Geo#geo.screen_x + 256 + (Offset - Geo#geo.screen_end_t) * 2.

filter_range(Changes, MinT, MaxT) ->
    [{T, C} || {T, C} <- Changes, T >= MinT, T =< MaxT].

build_segments([], LastColor, Px, StopPx, _LineT, _Geo, Acc) ->
    Width = StopPx - Px,
    case Width > 0 of
        true -> lists:reverse([color_copy(LastColor, Width) | Acc]);
        false -> lists:reverse(Acc)
    end;
build_segments([{T, NewColor} | Rest], CurColor, Px, StopPx, LineT, Geo, Acc) ->
    ChangePx = tstate_to_pixel(T - LineT, Geo),
    Width = ChangePx - Px,
    NewAcc = case Width > 0 of
        true -> [color_copy(CurColor, Width) | Acc];
        false -> Acc
    end,
    build_segments(Rest, NewColor, ChangePx, StopPx, LineT, Geo, NewAcc).

%% Walk the sorted border changes across one scanline [LineT, EndT]. Returns
%% {ColorBefore, LineChanges, SC1}: ColorBefore is the border color right
%% before LineT (the color the line starts with, with all earlier changes
%% applied), LineChanges the changes inside the line, and SC1 the remaining
%% changes (carried into the next line).
walk_line(SC, CB, LineT, EndT) ->
    walk_before(SC, CB, LineT, EndT).

walk_before([], CC, _LineT, _EndT) ->
    {CC, [], []};
walk_before([{T, Color} | Rest], _CC, LineT, EndT) when T < LineT ->
    walk_before(Rest, Color, LineT, EndT);
walk_before([{T, Color} | Rest], CC, LineT, EndT) when T =< EndT ->
    walk_in_line(Rest, Color, LineT, EndT, [{T, Color}], CC);
walk_before(SC, CC, _LineT, _EndT) ->
    {CC, [], SC}.

walk_in_line([], LastColor, _LineT, _EndT, Acc, ColorBefore) ->
    {ColorBefore, lists:reverse(Acc), []};
walk_in_line([{T, Color} | Rest], _PrevColor, LineT, EndT, Acc, ColorBefore) when T =< EndT ->
    walk_in_line(Rest, Color, LineT, EndT, [{T, Color} | Acc], ColorBefore);
walk_in_line(SC, LastColor, _LineT, _EndT, Acc, ColorBefore) ->
    {ColorBefore, lists:reverse(Acc), SC}.
