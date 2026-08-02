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
%% Same algorithm (6x32-bit XOR trick, same tables).
%% Optimizations:
%%   1. Row extraction: extract 32-byte bitmap/attr rows once per line
%%      instead of 32 offset-based byte extractions.
%%   2. Tail-based loop: <<BmByte:8, Tail/binary>> is O(1), no offset
%%      arithmetic needed.
%%   3. FlashMask hoisted out of per-character loop.
%%   4. Simplified flash detection: AttrByte band FlashMask instead of
%%      (AttrByte band 16#80) band (case FlashOn ...).

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
    persistent_term:put(?TABLES_KEY, {Color8px, MaskTab}),
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
    {Color8px, MaskTab} = persistent_term:get(?TABLES_KEY),
    <<Bitmap:6144/binary, Attrs:768/binary>> = VideoBuffer,
    Lines = render_lines(Color8px, MaskTab, FlashOn, Bitmap, Attrs,
                         SortedBorderChanges, CurrentBorder, TStatesPerLine, 0, []),
    list_to_binary(Lines).

%% ============================================================================
%% Line iteration
%% ============================================================================

render_lines(_C8, _MT, _FO, _BM, _AR, _SC, _AC, _TSL, ?FULL_HEIGHT, Acc) ->
    lists:reverse(Acc);
render_lines(C8, MT, FO, BM, AR, SC, AC, TSL, Y, Acc) ->
    {Line, SC1, NewAC} = render_line(C8, MT, FO, BM, AR, SC, AC, TSL, Y),
    render_lines(C8, MT, FO, BM, AR, SC1, NewAC, TSL, Y + 1, [Line | Acc]).

render_line(C8, MT, FO, BM, AR, SC, AC, TSL, Y) when Y >= ?SCREEN_Y_MIN, Y =< ?SCREEN_Y_MAX ->
    render_screen_line(C8, MT, FO, BM, AR, SC, AC, TSL, Y);
render_line(_C8, _MT, _FO, _BM, _AR, SC, AC, TSL, Y) ->
    render_border_only_line(SC, AC, TSL, Y).

%% ============================================================================
%% Border-only line
%% ============================================================================

render_border_only_line(SC, ActiveColor, TStatesPerLine, Y) ->
    LineT = (Y + ?FULL_Y_OFFSET) * TStatesPerLine,
    EndT = LineT + 175,
    {StartColor, LineChanges, SC1} = walk_line(SC, ActiveColor, LineT, EndT),
    EndColor = case LineChanges of
        [] -> StartColor;
        _ -> element(2, lists:last(LineChanges))
    end,
    case LineChanges of
        [] ->
            {color_copy(StartColor, ?FULL_WIDTH), SC1, EndColor};
        _ ->
            Segments = build_segments(LineChanges, StartColor, 0, ?FULL_WIDTH, LineT, []),
            {list_to_binary(Segments), SC1, EndColor}
    end.

%% ============================================================================
%% Screen line
%% ============================================================================

render_screen_line(Color8px, MaskTab, FlashOn, Bitmap, Attrs, SC, ActiveColor, TStatesPerLine, Y) ->
    LineT = (Y + ?FULL_Y_OFFSET) * TStatesPerLine,
    EndT = LineT + 175,
    {StartColor, LineChanges, SC1} = walk_line(SC, ActiveColor, LineT, EndT),
    EndColor = case LineChanges of
        [] -> StartColor;
        _ -> element(2, lists:last(LineChanges))
    end,

    LeftBin = render_left_border(LineChanges, StartColor, LineT),

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
    ScreenBin = render_screen_pixels(Color8px, MaskTab, FlashMask,
                                     BitmapRow, AttrRow, []),

    RightBaseColor = color_at_t(LineChanges, StartColor, LineT + 151),
    RightBin = render_right_border(LineChanges, RightBaseColor, LineT),

    {<<LeftBin/binary, ScreenBin/binary, RightBin/binary>>, SC1, EndColor}.

render_left_border(LineChanges, StartColor, LineT) ->
    Changes = filter_range(LineChanges, LineT, LineT + 23),
    case Changes of
        [] -> color_copy(StartColor, ?BORDER_LEFT);
        _ -> list_to_binary(build_segments(Changes, StartColor, 0, ?BORDER_LEFT, LineT, []))
    end.

render_right_border(LineChanges, BaseColor, LineT) ->
    Changes = filter_range(LineChanges, LineT + 152, LineT + 175),
    Width = ?FULL_WIDTH - ?BORDER_RIGHT,
    case Changes of
        [] -> color_copy(BaseColor, Width);
        _ -> list_to_binary(build_segments(Changes, BaseColor, ?BORDER_RIGHT, ?FULL_WIDTH, LineT, []))
    end.

%% ============================================================================
%% Screen pixels: tail-based loop with mask rendering
%% ============================================================================

render_screen_pixels(_C8, _MT, _FM, <<>>, <<>>, Acc) ->
    list_to_binary(lists:reverse(Acc));
render_screen_pixels(Color8px, MaskTab, FlashMask,
                     <<BmByte:8, BMT/binary>>, <<AttrByte:8, ART/binary>>, Acc) ->
    Ink = AttrByte band 16#07,
    Paper = (AttrByte bsr 3) band 16#07,
    {Ink1, Paper1} = case AttrByte band FlashMask of
        0 -> {Ink, Paper};
        _ -> {Paper, Ink}
    end,
    Bright = (AttrByte bsr 6) band 1,
    Ink8 = element(Bright * 8 + Ink1 + 1, Color8px),
    Paper8 = element(Bright * 8 + Paper1 + 1, Color8px),
    <<M1:32, M2:32, M3:32, M4:32, M5:32, M6:32>> = element(BmByte + 1, MaskTab),
    <<P1:32, P2:32, P3:32, P4:32, P5:32, P6:32>> = Paper8,
    <<I1:32, I2:32, I3:32, I4:32, I5:32, I6:32>> = Ink8,
    %% P bxor ((P bxor I) band M) — faster equivalent of
    %% (M band I) bor ((bnot M) band P):
    %% when M byte = 255 → result = I (ink), M byte = 0 → result = P (paper).
    %% XOR form: 2 bxor + 1 band = 3 ops per chunk,
    %% AND/OR form: 1 bnot + 2 band + 1 bor = 4 ops per chunk.
    D1 = P1 bxor I1, R1 = P1 bxor (D1 band M1),
    D2 = P2 bxor I2, R2 = P2 bxor (D2 band M2),
    D3 = P3 bxor I3, R3 = P3 bxor (D3 band M3),
    D4 = P4 bxor I4, R4 = P4 bxor (D4 band M4),
    D5 = P5 bxor I5, R5 = P5 bxor (D5 band M5),
    D6 = P6 bxor I6, R6 = P6 bxor (D6 band M6),
    CharPixels = <<R1:32, R2:32, R3:32, R4:32, R5:32, R6:32>>,
    render_screen_pixels(Color8px, MaskTab, FlashMask,
                         BMT, ART, [CharPixels | Acc]).

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
