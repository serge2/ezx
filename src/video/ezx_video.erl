-module(ezx_video).

-export([
    render_frame/4,
    border_color/2,
    frame_line_for_screen_y/1,
    tstate_for_frame_line/1
]).

%% ZX Spectrum display timing
-define(TSTATES_PER_LINE, 224).
-define(SCREEN_START_LINE, 64).

%% Full frame dimensions — visible area only (288 lines, excluding VBI)
-define(FULL_WIDTH, 352).
-define(FULL_HEIGHT, 288).
-define(FULL_Y_OFFSET, 16).
-define(BORDER_LEFT, 48).
-define(BORDER_RIGHT, 304).

%% Screen area boundaries in full-frame coordinates
-define(SCREEN_Y_MIN, 48).
-define(SCREEN_Y_MAX, 239).

%% Memory layout
-define(SCREEN_BITMAP, 16#4000).
-define(SCREEN_ATTRS, 16#5800).

%% Classic ZX Spectrum color palette (RGB values).
-define(COLORS_NORMAL, {
    {0, 0, 0},         {0, 0, 215},       {215, 0, 0},       {215, 0, 215},
    {0, 215, 0},       {0, 215, 215},     {215, 215, 0},     {215, 215, 215}
}).

-define(COLORS_BRIGHT, {
    {0, 0, 0},         {0, 0, 255},       {255, 0, 0},       {255, 0, 255},
    {0, 255, 0},       {0, 255, 255},     {255, 255, 0},     {255, 255, 255}
}).

-define(DEFAULT_BORDER, 1).


%% --- Public API ---

-spec frame_line_for_screen_y(non_neg_integer()) -> non_neg_integer().
frame_line_for_screen_y(ScreenY) ->
    ?SCREEN_START_LINE + ScreenY.

-spec tstate_for_frame_line(non_neg_integer()) -> non_neg_integer().
tstate_for_frame_line(FrameLine) ->
    FrameLine * ?TSTATES_PER_LINE.

%% @doc Look up the border color at a given T-state within a frame.
-spec border_color(list(), non_neg_integer()) -> {byte(), byte(), byte()}.
border_color(BorderChanges, TState) ->
    ColorIndex = find_border_color(BorderChanges, TState, ?DEFAULT_BORDER),
    color(ColorIndex, false).

%% @doc Render full frame to a flat RGB binary (352×288×3 bytes).
%% Uses bulk memory reads via read_block/3 and decodes 8 pixels per bitmap byte.
%% SortedBorderChanges must be ascending by T-state.
-spec render_frame(ezx_memory_48:state(), boolean(), list(), non_neg_integer()) -> binary().
render_frame(VideoBuffer, FlashOn, SortedBorderChanges, CurrentBorder) ->
    <<Bitmap:6144/binary, Attrs:768/binary>> = VideoBuffer,
    list_to_binary([render_frame_line(Bitmap, Attrs, SortedBorderChanges, CurrentBorder, FlashOn, Y)
                    || Y <- lists:seq(0, ?FULL_HEIGHT - 1)]).

%% --- Internal ---

render_frame_line(_Bitmap, _Attrs, SortedChanges, CurrentBorder, _FlashOn, Y) when
        Y < ?SCREEN_Y_MIN; Y > ?SCREEN_Y_MAX ->
    render_border_line(SortedChanges, CurrentBorder, Y);
render_frame_line(Bitmap, Attrs, SortedChanges, CurrentBorder, FlashOn, Y) ->
    render_mixed_line(Bitmap, Attrs, SortedChanges, CurrentBorder, FlashOn, Y).

render_border_line(SortedChanges, CurrentBorder, Y) ->
    render_border_pixels(SortedChanges, CurrentBorder, Y, 0, ?FULL_WIDTH, <<>>).

render_border_pixels(_SC, _CB, _Y, X, X, Acc) -> Acc;
render_border_pixels(SortedChanges, CurrentBorder, Y, X, StopX, Acc) ->
    TState = pixel_tstate(X, Y),
    {R, G, B} = lookup_border_color(SortedChanges, CurrentBorder, TState),
    render_border_pixels(SortedChanges, CurrentBorder, Y, X + 1, StopX, <<Acc/binary, R, G, B>>).

render_mixed_line(Bitmap, Attrs, SortedChanges, CurrentBorder, FlashOn, Y) ->
    ScreenY = Y - ?SCREEN_Y_MIN,
    Third = ScreenY div 64,
    CharRowInThird = (ScreenY rem 64) div 8,
    PixelRow = ScreenY rem 8,
    CharRow = Third * 8 + CharRowInThird,
    BitmapRowOffset = Third * 2048 + CharRowInThird * 32 + PixelRow * 256,
    AttrRowOffset = CharRow * 32,

    LeftBorder = render_border_pixels(SortedChanges, CurrentBorder, Y, 0, ?BORDER_LEFT, <<>>),
    ScreenPixels = render_screen_pixels(Bitmap, Attrs, AttrRowOffset, BitmapRowOffset, FlashOn, 0, <<>>),
    RightBorder = render_border_pixels(SortedChanges, CurrentBorder, Y, ?BORDER_RIGHT, ?FULL_WIDTH, <<>>),

    <<LeftBorder/binary, ScreenPixels/binary, RightBorder/binary>>.

render_screen_pixels(_Bitmap, _Attrs, _AttrRowOffset, _BitmapRowOffset, _FlashOn, CharCol, Acc)
        when CharCol >= 32 ->
    Acc;
render_screen_pixels(Bitmap, Attrs, AttrRowOffset, BitmapRowOffset, FlashOn, CharCol, Acc) ->
    BitmapByteOffset = BitmapRowOffset + CharCol,
    <<_:BitmapByteOffset/binary, BmByte:8, _/binary>> = Bitmap,
    AttrByteOffset = AttrRowOffset + CharCol,
    <<_:AttrByteOffset/binary, AttrByte:8, _/binary>> = Attrs,
    {Ink, Paper, Bright} = attr_colors(AttrByte, FlashOn),
    PixelPixels = render_screen_char_pixels(BmByte, Ink, Paper, Bright, 0, <<>>),
    render_screen_pixels(Bitmap, Attrs, AttrRowOffset, BitmapRowOffset, FlashOn, CharCol + 1, <<Acc/binary, PixelPixels/binary>>).

render_screen_char_pixels(_BmByte, _Ink, _Paper, _Bright, 8, Acc) -> Acc;
render_screen_char_pixels(BmByte, Ink, Paper, Bright, BitPos, Acc) ->
    BitMask = 1 bsl (7 - BitPos),
    ColorIdx = case BmByte band BitMask of
        0 -> Paper;
        _ -> Ink
    end,
    {R, G, B} = color(ColorIdx, Bright),
    render_screen_char_pixels(BmByte, Ink, Paper, Bright, BitPos + 1, <<Acc/binary, R, G, B>>).

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

lookup_border_color([], CurrentBorder, _TState) ->
    color(CurrentBorder, false);
lookup_border_color(Changes, CurrentBorder, TState) ->
    find_border_color_acc(Changes, CurrentBorder, TState, CurrentBorder).

find_border_color_acc([], _CurrentBorder, _TState, Acc) ->
    color(Acc, false);
find_border_color_acc([{T, Color} | Rest], CurrentBorder, TState, Acc) ->
    case T =< TState of
        true -> find_border_color_acc(Rest, CurrentBorder, TState, Color);
        false -> color(Acc, false)
    end.

find_border_color([], _TState, Default) ->
    Default;
find_border_color([{T, Color} | Rest], TState, Default) ->
    case T =< TState of
        true -> Color;
        false -> find_border_color(Rest, TState, Default)
    end.

color(Idx, Bright) ->
    Palette = case Bright of
        true -> ?COLORS_BRIGHT;
        false -> ?COLORS_NORMAL
    end,
    element(Idx + 1, Palette).
