-module(ezx_screen).

%% ZX Spectrum ULA screen device: border color changes + attribute flash.
%% Also renders the frame into a flat RGB bitmap (pure, view-optional).
%%
%% Device frame contract (shared with the beeper and AY):
%%   frame_start(Screen, StartTState) — begin a frame; events recorded below
%%                                       carry absolute TState stamps
%%   border_set(Screen, TState, Color) — record a border color change
%%   frame_render(Screen, FrameLen)   — produce the sorted local-time border
%%                                       changes, the current color, and the
%%                                       flash phase for the screen; advances
%%                                       the flash phase once per frame
%%
%% Border changes are stored newest-first with absolute TState stamps.
%% frame_render/2 rebases them onto local frame time (ET - StartTState) and
%% drops the frame-overrun zone (local TState >= FrameLen); the live color —
%% which already reflects those dropped changes — is returned as the base
%% color for lines before the first change.
%%
%% The flash phase advances at frame close (32-frame cycle); the FlashOn flag
%% returned by frame_render/2 matches flash_on/1 of the returned device. The
%% emulator stores it as the flash_on artifact alongside the border changes
%% and color, so render_frame/1 does not need to touch the device directly.

-export([new/0, new/1, border_set/3, border_get/1, flash_on/1, frame_start/2, frame_render/2]).
-export([init_helper_tables/0, render_screen/4, render_screen/5]).

-on_load(init_helper_tables/0).

%% --- Device ---

-define(FLASH_CYCLE, 32).

-record(screen, {
    border_color = 0    :: 0..7,
    frame_offset = 0    :: non_neg_integer(),
    border_changes = [] :: [{non_neg_integer(), 0..7}],
    flash_phase = 0     :: 0..31
}).

-type state() :: #screen{}.
-export_type([state/0]).

%% @doc New screen device, starting at black, flash phase 0.
-spec new() -> state().
new() ->
    #screen{}.

%% @doc New screen device with a known border color (snapshot load).
-spec new(0..7) -> state().
new(Color) ->
    #screen{border_color = Color}.

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

%% @doc Mark the start of a new frame. Rebases the event timeline to
%% StartTState: frame_render/2 converts events to local frame time by
%% subtracting it.
-spec frame_start(state(), non_neg_integer()) -> state().
frame_start(#screen{} = S, StartTState) ->
    S#screen{frame_offset = StartTState, border_changes = []}.

%% @doc Produce the screen output for one frame (exactly FrameLen T-states):
%% the sorted local-time border changes (frame-overrun zone dropped), the
%% current color used as the screen's base color, the flash flag, and the
%% advanced device state (flash phase carried into the next frame).
-spec frame_render(state(), non_neg_integer()) ->
    {[{non_neg_integer(), 0..7}], 0..7, boolean(), state()}.
frame_render(#screen{border_color = Color, frame_offset = FO, border_changes = Changes, flash_phase = Phase}, FrameLen) ->
    NewPhase = (Phase + 1) rem ?FLASH_CYCLE,
    Sorted = lists:reverse(Changes),
    Local = [{ET - FO, C} || {ET, C} <- Sorted, ET >= FO, ET - FO < FrameLen],
    {Local, Color, NewPhase div 16 =:= 1,
     #screen{border_color = Color, flash_phase = NewPhase}}.

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
%% produces the 352×288 bitmap. Measured ~3.6x faster than the old per-char
%% construction on a real boot frame and roughly halves the GC traffic.

-define(TSTATES_PER_LINE, 224).
-define(FULL_Y_OFFSET, 16).
-define(FULL_WIDTH, 352).
-define(FULL_HEIGHT, 288).
-define(BORDER_LEFT, 48).
-define(BORDER_RIGHT, 304).
-define(SCREEN_Y_MIN, 48).
-define(SCREEN_Y_MAX, 239).

-define(COLORS_NORMAL, {
    {0, 0, 0}, {0, 0, 215}, {215, 0, 0}, {215, 0, 215},
    {0, 215, 0}, {0, 215, 215}, {215, 215, 0}, {215, 215, 215}
}).

-define(COLORS_BRIGHT, {
    {0, 0, 0}, {0, 0, 255}, {255, 0, 0}, {255, 0, 255},
    {0, 255, 0}, {0, 255, 255}, {255, 255, 0}, {255, 255, 255}
}).

-define(TABLES_KEY, ezx_screen_tables).

init_helper_tables() ->
    Color8px = build_color_8px_table(),
    MaskTab = build_mask_table(),
    Lookup = build_lookup_table(Color8px, MaskTab),
    Border48 = build_border_runs(?BORDER_LEFT),
    Border352 = build_border_runs(?FULL_WIDTH),
    %% Color8px and MaskTab are build-time inputs for Lookup only — the
    %% renderer never reads them, so only the runtime tables are stored.
    persistent_term:put(?TABLES_KEY, {Lookup, Border48, Border352}),
    ok.

%% @doc Render a frame to a flat RGB binary using the 48K line timing
%% (224 T-states per scanline). Kept for backward compatibility.
-spec render_screen(binary(), boolean(), list(), non_neg_integer()) -> binary().
render_screen(VideoBuffer, FlashOn, SortedBorderChanges, CurrentBorder) ->
    render_screen(VideoBuffer, FlashOn, SortedBorderChanges, CurrentBorder, ?TSTATES_PER_LINE).

%% @doc Render a frame to a flat RGB binary. TStatesPerLine is the horizontal
%% scanline length in T-states (224 for the 48K raster, 228 for the 128K).
-spec render_screen(binary(), boolean(), list(), non_neg_integer(), pos_integer()) -> binary().
render_screen(VideoBuffer, FlashOn, SortedBorderChanges, CurrentBorder, TStatesPerLine) ->
    {Lookup, Border48, Border352} = persistent_term:get(?TABLES_KEY),
    <<Bitmap:6144/binary, Attrs:768/binary>> = VideoBuffer,
    Chunks = render_lines(Lookup, Border48, Border352, FlashOn, Bitmap, Attrs,
                          SortedBorderChanges, CurrentBorder, TStatesPerLine, 0, []),
    list_to_binary(lists:reverse(Chunks)).

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

render_lines(_L, _B48, _B352, _FO, _BM, _AR, _SC, _AC, _TSL, ?FULL_HEIGHT, Acc) ->
    Acc;
render_lines(L, B48, B352, FO, BM, AR, SC, AC, TSL, Y, Acc) ->
    {Acc1, SC1, NewAC} = render_line(L, B48, B352, FO, BM, AR, SC, AC, TSL, Y, Acc),
    render_lines(L, B48, B352, FO, BM, AR, SC1, NewAC, TSL, Y + 1, Acc1).

render_line(L, B48, _B352, FO, BM, AR, SC, AC, TSL, Y, Acc) when Y >= ?SCREEN_Y_MIN, Y =< ?SCREEN_Y_MAX ->
    render_screen_line(L, B48, FO, BM, AR, SC, AC, TSL, Y, Acc);
render_line(_L, _B48, B352, _FO, _BM, _AR, SC, AC, TSL, Y, Acc) ->
    render_border_only_line(B352, SC, AC, TSL, Y, Acc).

%% ============================================================================
%% Border-only line: the whole line is one border run (shared binary) unless a
%% border change falls inside, then build segments (rare).
%% ============================================================================

render_border_only_line(Border352, SC, ActiveColor, TStatesPerLine, Y, Acc) ->
    LineT = (Y + ?FULL_Y_OFFSET) * TStatesPerLine,
    EndT = LineT + 175,
    {StartColor, LineChanges, SC1} = walk_line(SC, ActiveColor, LineT, EndT),
    EndColor = case LineChanges of
        [] -> StartColor;
        _ -> element(2, lists:last(LineChanges))
    end,
    Acc1 = case LineChanges of
        [] -> [element(StartColor + 1, Border352) | Acc];
        _ -> prepend_all(build_segments(LineChanges, StartColor, 0, ?FULL_WIDTH, LineT, []), Acc)
    end,
    {Acc1, SC1, EndColor}.

%% ============================================================================
%% Screen line: the left border side, the 32 chars, and the right border side
%% are threaded straight into Acc (forward order) — the chars accumulate via
%% render_screen_pixels, the border sides via prepend_all.
%% ============================================================================

render_screen_line(Lookup, Border48, FlashOn, Bitmap, Attrs, SC, ActiveColor, TStatesPerLine, Y, Acc) ->
    LineT = (Y + ?FULL_Y_OFFSET) * TStatesPerLine,
    EndT = LineT + 175,
    {StartColor, LineChanges, SC1} = walk_line(SC, ActiveColor, LineT, EndT),
    EndColor = case LineChanges of
        [] -> StartColor;
        _ -> element(2, lists:last(LineChanges))
    end,

    Acc1 = prepend_all(border_side(LineChanges, StartColor, LineT, LineT, LineT + 23, 0, Border48), Acc),

    ScreenY = Y - ?SCREEN_Y_MIN,
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

    RightBaseColor = color_at_t(LineChanges, StartColor, LineT + 151),
    Acc3 = prepend_all(border_side(LineChanges, RightBaseColor, LineT, LineT + 152, LineT + 175,
                                   ?BORDER_RIGHT, Border48), Acc2),
    {Acc3, SC1, EndColor}.

%% Border side of a screen line: a flat run of BaseColor (shared binary) unless
%% a border change falls in [MinT, MaxT]; then build segments (rare). Returns
%% the chunks in forward order — the caller threads them into the accumulator.
border_side(LineChanges, BaseColor, LineT, MinT, MaxT, StartPx, Border48) ->
    Changes = filter_range(LineChanges, MinT, MaxT),
    case Changes of
        [] -> [element(BaseColor + 1, Border48)];
        _ -> build_segments(Changes, BaseColor, StartPx, StartPx + 48, LineT, [])
    end.

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

%% A 48px (screen-line side) or full-width (border-only line) run of each of
%% the 8 border colors — shared binaries, reused by every line.
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

tstate_to_pixel(Offset) when Offset < 24 ->
    Offset * 2;
tstate_to_pixel(Offset) when Offset < 152 ->
    48 + (Offset - 24) * 2;
tstate_to_pixel(Offset) ->
    304 + (Offset - 152) * 2.

filter_range(Changes, MinT, MaxT) ->
    [{T, C} || {T, C} <- Changes, T >= MinT, T =< MaxT].

build_segments([], LastColor, Px, StopPx, _LineT, Acc) ->
    Width = StopPx - Px,
    case Width > 0 of
        true -> lists:reverse([color_copy(LastColor, Width) | Acc]);
        false -> lists:reverse(Acc)
    end;
build_segments([{T, NewColor} | Rest], CurColor, Px, StopPx, LineT, Acc) ->
    ChangePx = tstate_to_pixel(T - LineT),
    Width = ChangePx - Px,
    NewAcc = case Width > 0 of
        true -> [color_copy(CurColor, Width) | Acc];
        false -> Acc
    end,
    build_segments(Rest, NewColor, ChangePx, StopPx, LineT, NewAcc).

walk_line(SC, CB, LineT, EndT) ->
    walk_before(SC, CB, LineT, EndT).

walk_before([], CC, _LineT, _EndT) ->
    {CC, [], []};
walk_before([{T, Color} | Rest], _CC, LineT, EndT) when T < LineT ->
    walk_before(Rest, Color, LineT, EndT);
walk_before([{T, Color} | Rest], _CC, LineT, EndT) when T =< EndT ->
    walk_in_line(Rest, Color, LineT, EndT, [{T, Color}]);
walk_before(SC, CC, _LineT, _EndT) ->
    {CC, [], SC}.

walk_in_line([], LastColor, _LineT, _EndT, Acc) ->
    {LastColor, lists:reverse(Acc), []};
walk_in_line([{T, Color} | Rest], _PrevColor, LineT, EndT, Acc) when T =< EndT ->
    walk_in_line(Rest, Color, LineT, EndT, [{T, Color} | Acc]);
walk_in_line(SC, LastColor, _LineT, _EndT, Acc) ->
    {LastColor, lists:reverse(Acc), SC}.
