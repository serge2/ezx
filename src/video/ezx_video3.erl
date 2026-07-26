-module(ezx_video3).

%% Line-based segment border renderer.
%%
%% Key optimizations over ezx_video2:
%% 1. Cursor maintained across ALL lines — O(changes) total, not O(lines × changes).
%% 2. Solid-color border lines rendered with a single binary:copy — no per-pixel work.
%% 3. Border segments rendered with binary:copy per segment — O(segments) not O(pixels).
%% 4. Pre-computed color binaries avoid repeated <<R,G,B>> construction.

-export([render_frame/4, border_color/2]).

-define(TSTATES_PER_LINE, 224).
-define(FULL_Y_OFFSET, 16).
-define(FULL_WIDTH, 352).
-define(FULL_HEIGHT, 288).
-define(BORDER_LEFT, 48).
-define(BORDER_RIGHT, 304).
-define(SCREEN_Y_MIN, 48).
-define(SCREEN_Y_MAX, 239).

%% Pre-computed color binaries — 8 colors × normal/bright = 16 binaries.
-define(COLOR_BIN_NORMAL, {
    <<0,0,0>>, <<0,0,215>>, <<215,0,0>>, <<215,0,215>>,
    <<0,215,0>>, <<0,215,215>>, <<215,215,0>>, <<215,215,215>>
}).

-define(COLOR_BIN_BRIGHT, {
    <<0,0,0>>, <<0,0,255>>, <<255,0,0>>, <<255,0,255>>,
    <<0,255,0>>, <<0,255,255>>, <<255,255,0>>, <<255,255,255>>
}).

-define(COLORS_NORMAL, {
    {0, 0, 0}, {0, 0, 215}, {215, 0, 0}, {215, 0, 215},
    {0, 215, 0}, {0, 215, 215}, {215, 215, 0}, {215, 215, 215}
}).

-define(COLORS_BRIGHT, {
    {0, 0, 0}, {0, 0, 255}, {255, 0, 0}, {255, 0, 255},
    {0, 255, 0}, {0, 255, 255}, {255, 255, 0}, {255, 255, 255}
}).

-spec render_frame(binary(), boolean(), list(), non_neg_integer()) -> binary().
render_frame(VideoBuffer, FlashOn, SortedBorderChanges, CurrentBorder) ->
    <<Bitmap:6144/binary, Attrs:768/binary>> = VideoBuffer,
    Lines = render_lines(Bitmap, Attrs, SortedBorderChanges, CurrentBorder, FlashOn, 0, []),
    list_to_binary(Lines).

-spec border_color(list(), non_neg_integer()) -> {byte(), byte(), byte()}.
border_color(BorderChanges, TState) ->
    ColorIndex = find_color(BorderChanges, TState, 1),
    color(ColorIndex, false).

%% --- Line iteration with cursor AND active color maintained across lines ---

render_lines(_Bitmap, _Attrs, _SC, _ActiveColor, _FlashOn, ?FULL_HEIGHT, Acc) ->
    lists:reverse(Acc);
render_lines(Bitmap, Attrs, SC, ActiveColor, FlashOn, Y, Acc) ->
    {Line, SC1, NewActiveColor} = render_line(Bitmap, Attrs, SC, ActiveColor, FlashOn, Y),
    render_lines(Bitmap, Attrs, SC1, NewActiveColor, FlashOn, Y + 1, [Line | Acc]).

render_line(Bitmap, Attrs, SC, ActiveColor, FlashOn, Y) when Y >= ?SCREEN_Y_MIN, Y =< ?SCREEN_Y_MAX ->
    render_screen_line(Bitmap, Attrs, SC, ActiveColor, FlashOn, Y);
render_line(_Bitmap, _Attrs, SC, ActiveColor, _FlashOn, Y) ->
    render_border_only_line(SC, ActiveColor, Y).

%% --- Border-only line (top/bottom borders: Y < 48 or Y > 239) ---
%% Walk cursor, collect changes in this line's T-state range.
%% If no changes: single binary:copy for the whole line.
%% If changes: render segments between changes.

render_border_only_line(SC, ActiveColor, Y) ->
    LineT = (Y + ?FULL_Y_OFFSET) * ?TSTATES_PER_LINE,
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

%% --- Screen line (48 ≤ Y ≤ 239): left border + screen pixels + right border ---

render_screen_line(Bitmap, Attrs, SC, ActiveColor, FlashOn, Y) ->
    LineT = (Y + ?FULL_Y_OFFSET) * ?TSTATES_PER_LINE,
    EndT = LineT + 175,
    {StartColor, LineChanges, SC1} = walk_line(SC, ActiveColor, LineT, EndT),
    EndColor = case LineChanges of
        [] -> StartColor;
        _ -> element(2, lists:last(LineChanges))
    end,

    %% Left border: pixels 0..47, T-states [LineT, LineT+23]
    LeftBin = render_left_border(LineChanges, StartColor, LineT),

    %% Screen pixels: pixels 48..303
    ScreenY = Y - ?SCREEN_Y_MIN,
    Third = ScreenY div 64,
    CharRowInThird = (ScreenY rem 64) div 8,
    PixelRow = ScreenY rem 8,
    CharRow = Third * 8 + CharRowInThird,
    BitmapRowOffset = Third * 2048 + CharRowInThird * 32 + PixelRow * 256,
    AttrRowOffset = CharRow * 32,
    ScreenBin = render_screen_pixels(Bitmap, Attrs, AttrRowOffset, BitmapRowOffset, FlashOn, 0, []),

    %% Right border: pixels 304..351, T-states [LineT+152, LineT+175]
    RightBaseColor = color_at_t(LineChanges, StartColor, LineT + 151),
    RightBin = render_right_border(LineChanges, RightBaseColor, LineT),

    {<<LeftBin/binary, ScreenBin/binary, RightBin/binary>>, SC1, EndColor}.

render_left_border(LineChanges, StartColor, LineT) ->
    Changes = filter_range(LineChanges, LineT, LineT + 23),
    case Changes of
        [] ->
            color_copy(StartColor, ?BORDER_LEFT);
        _ ->
            list_to_binary(build_segments(Changes, StartColor, 0, ?BORDER_LEFT, LineT, []))
    end.

render_right_border(LineChanges, BaseColor, LineT) ->
    Changes = filter_range(LineChanges, LineT + 152, LineT + 175),
    Width = ?FULL_WIDTH - ?BORDER_RIGHT,
    case Changes of
        [] ->
            color_copy(BaseColor, Width);
        _ ->
            list_to_binary(build_segments(Changes, BaseColor, ?BORDER_RIGHT, ?FULL_WIDTH, LineT, []))
    end.

%% --- Cursor walk (maintained across lines) ---
%% walk_line returns {ActiveColorAtLineStart, ChangesInLine, RemainingCursor}.

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

%% --- Segment building ---
%% Given changes in a line, build a list of binaries (one per constant-color run).

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

%% --- T-state offset to pixel X ---

tstate_to_pixel(Offset) when Offset < 24 ->
    Offset * 2;
tstate_to_pixel(Offset) when Offset < 152 ->
    48 + (Offset - 24) * 2;
tstate_to_pixel(Offset) ->
    304 + (Offset - 152) * 2.

%% --- Filter changes to a T-state range ---

filter_range(Changes, MinT, MaxT) ->
    [{T, C} || {T, C} <- Changes, T >= MinT, T =< MaxT].

%% --- Color at a specific T-state ---

color_at_t([], Default, _T) -> Default;
color_at_t([{T, Color} | Rest], _Default, TState) when T =< TState ->
    color_at_t(Rest, Color, TState);
color_at_t(_, Default, _T) -> Default.

%% --- Screen pixels (same as video2 — bitmap + attr decode) ---

render_screen_pixels(_Bitmap, _Attrs, _ARO, _BRO, _FlashOn, 32, Acc) ->
    list_to_binary(lists:reverse(Acc));
render_screen_pixels(Bitmap, Attrs, AttrRowOffset, BitmapRowOffset, FlashOn, CharCol, Acc) ->
    BitmapByteOffset = BitmapRowOffset + CharCol,
    <<_:BitmapByteOffset/binary, BmByte:8, _/binary>> = Bitmap,
    AttrByteOffset = AttrRowOffset + CharCol,
    <<_:AttrByteOffset/binary, AttrByte:8, _/binary>> = Attrs,
    {Ink, Paper, Bright} = attr_colors(AttrByte, FlashOn),
    CharPixels = render_char_pixels(BmByte, Ink, Paper, Bright, 0, []),
    render_screen_pixels(Bitmap, Attrs, AttrRowOffset, BitmapRowOffset, FlashOn, CharCol + 1, [CharPixels | Acc]).

render_char_pixels(_BmByte, _Ink, _Paper, _Bright, 8, Acc) ->
    list_to_binary(lists:reverse(Acc));
render_char_pixels(BmByte, Ink, Paper, Bright, BitPos, Acc) ->
    BitMask = 1 bsl (7 - BitPos),
    ColorIdx = case BmByte band BitMask of
        0 -> Paper;
        _ -> Ink
    end,
    render_char_pixels(BmByte, Ink, Paper, Bright, BitPos + 1, [color_bin(ColorIdx, Bright) | Acc]).

%% --- Utilities ---

find_color([], _TState, Default) -> Default;
find_color([{T, Color} | _Rest], TState, _Default) when T =< TState -> Color;
find_color([_ | Rest], TState, Default) -> find_color(Rest, TState, Default).

attr_colors(AttrByte, FlashOn) ->
    Ink = AttrByte band 16#07,
    Paper = (AttrByte bsr 3) band 16#07,
    Bright = (AttrByte bsr 6) band 1 =:= 1,
    Flash = (AttrByte bsr 7) band 1 =:= 1,
    case Flash andalso FlashOn of
        true  -> {Paper, Ink, Bright};
        false -> {Ink, Paper, Bright}
    end.

color(Idx, Bright) ->
    element(Idx + 1, case Bright of true -> ?COLORS_BRIGHT; false -> ?COLORS_NORMAL end).

color_bin(Idx, Bright) ->
    element(Idx + 1, case Bright of true -> ?COLOR_BIN_BRIGHT; false -> ?COLOR_BIN_NORMAL end).

color_copy(Idx, Count) ->
    binary:copy(color_bin(Idx, false), Count).
