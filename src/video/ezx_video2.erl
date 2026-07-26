-module(ezx_video2).

%% Optimized video renderer.
%% Two key improvements over ezx_video:
%% 1. Border: maintains a cursor into the sorted changes list,
%%    advancing it as T-state increases — O(pixels + changes) per line
%%    instead of O(pixels × changes).
%% 2. Binary construction: builds iolists, calls list_to_binary once.

-export([render_frame/4, border_color/2]).

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

-spec render_frame(binary(), boolean(), list(), non_neg_integer()) -> binary().
render_frame(VideoBuffer, FlashOn, SortedBorderChanges, CurrentBorder) ->
    <<Bitmap:6144/binary, Attrs:768/binary>> = VideoBuffer,
    Lines = [render_line(Bitmap, Attrs, SortedBorderChanges, CurrentBorder, FlashOn, Y)
             || Y <- lists:seq(0, ?FULL_HEIGHT - 1)],
    list_to_binary(Lines).

-spec border_color(list(), non_neg_integer()) -> {byte(), byte(), byte()}.
border_color(BorderChanges, TState) ->
    ColorIndex = find_color(BorderChanges, TState, 1),
    color(ColorIndex, false).

%% --- Internal ---

render_line(_Bitmap, _Attrs, SC, CB, _FlashOn, Y) when Y < ?SCREEN_Y_MIN; Y > ?SCREEN_Y_MAX ->
    {Bin, _SC2} = render_border_line(SC, CB, Y, 0, ?FULL_WIDTH, []),
    Bin;
render_line(Bitmap, Attrs, SC, CB, FlashOn, Y) ->
    render_screen_line(Bitmap, Attrs, SC, CB, FlashOn, Y).

%% --- Border line: left-to-right scan with cursor ---

render_border_line(SC, _CB, _Y, X, X, Acc) ->
    {list_to_binary(lists:reverse(Acc)), SC};
render_border_line(SC0, CB, Y, X, StopX, Acc) ->
    TState = pixel_tstate(X, Y),
    {Color, SC} = resolve_color(SC0, CB, TState),
    RGB = color_bin(Color, false),
    render_border_line(SC, Color, Y, X + 1, StopX, [RGB | Acc]).

%% --- Screen line: left border + screen pixels + right border ---

render_screen_line(Bitmap, Attrs, SC, CB, FlashOn, Y) ->
    ScreenY = Y - ?SCREEN_Y_MIN,
    Third = ScreenY div 64,
    CharRowInThird = (ScreenY rem 64) div 8,
    PixelRow = ScreenY rem 8,
    CharRow = Third * 8 + CharRowInThird,
    BitmapRowOffset = Third * 2048 + CharRowInThird * 32 + PixelRow * 256,
    AttrRowOffset = CharRow * 32,

    {LeftBorderBin, SC1} = render_border_line(SC, CB, Y, 0, ?BORDER_LEFT, []),
    ScreenPixels = render_screen_pixels(Bitmap, Attrs, AttrRowOffset, BitmapRowOffset, FlashOn, 0, []),
    {RightBorderBin, _SC2} = render_border_line(SC1, CB, Y, ?BORDER_RIGHT, ?FULL_WIDTH, []),

    <<LeftBorderBin/binary, ScreenPixels/binary, RightBorderBin/binary>>.

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

%% --- Cursor-based color resolution ---

%% Walk the sorted changes list, advancing past entries <= TState.
%% Returns {CurrentColor, RemainingChanges}.
resolve_color([], CB, _TState) -> {CB, []};
resolve_color([{T, Color} | Rest], _CB, TState) when T =< TState ->
    resolve_color(Rest, Color, TState);
resolve_color(Changes, CB, _TState) -> {CB, Changes}.

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

pixel_tstate(X, Y) ->
    LineT = (Y + ?FULL_Y_OFFSET) * ?TSTATES_PER_LINE,
    case X of
        LX when LX < ?BORDER_LEFT ->
            LineT + LX div 2;
        MX when MX >= ?BORDER_LEFT andalso MX < ?BORDER_RIGHT ->
            LineT + 24 + (MX - ?BORDER_LEFT) div 2;
        RX when RX >= ?BORDER_RIGHT ->
            LineT + 152 + (RX - ?BORDER_RIGHT) div 2
    end.

color(Idx, Bright) ->
    element(Idx + 1, case Bright of true -> ?COLORS_BRIGHT; false -> ?COLORS_NORMAL end).

color_bin(Idx, Bright) ->
    {R, G, B} = color(Idx, Bright),
    <<R, G, B>>.
