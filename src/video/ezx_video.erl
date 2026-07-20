-module(ezx_video).

-export([
    decode_screen_line/3,
    decode_screen/2,
    decode_full_frame/4,
    border_color/2,
    screen_pixel/4,
    frame_line_for_screen_y/1,
    tstate_for_frame_line/1
]).

%% ZX Spectrum display timing
-define(TSTATES_PER_LINE, 224).
-define(SCREEN_START_LINE, 64).
-define(SCREEN_HEIGHT, 192).
-define(SCREEN_WIDTH, 256).

%% Full frame dimensions (visible area, excluding blanking)
-define(FULL_WIDTH, 352).
-define(FULL_HEIGHT, 288).
-define(BORDER_LEFT, 48).
-define(BORDER_TOP, 48).
-define(BORDER_RIGHT, 304).
-define(BORDER_BOTTOM, 240).

%% Screen area boundaries in full-frame coordinates
-define(SCREEN_X_MIN, 48).
-define(SCREEN_X_MAX, 303).
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
%% BorderChanges is a list of {TState, ColorIndex} sorted newest-first.
-spec border_color(list(), non_neg_integer()) -> {byte(), byte(), byte()}.
border_color(BorderChanges, TState) ->
    ColorIndex = find_border_color(BorderChanges, TState, ?DEFAULT_BORDER),
    color(ColorIndex, false).

%% @doc Decode a single screen pixel. X = 0..255, Y = 0..191.
%% ReadByteFun is fun(Addr :: non_neg_integer()) -> byte().
%% FrameCounter is the current frame number (for FLASH).
-spec screen_pixel(function(), non_neg_integer(), non_neg_integer(), non_neg_integer()) ->
    {byte(), byte(), byte()}.
screen_pixel(ReadByteFun, FrameCounter, X, Y) ->
    CharCol = X div 8,
    Third = Y div 64,
    CharRowInThird = (Y rem 64) div 8,
    PixelRow = Y rem 8,

    BitmapAddr = ?SCREEN_BITMAP + (Third * 2048) + (CharRowInThird * 32) + (PixelRow * 256) + CharCol,
    BitmapByte = ReadByteFun(BitmapAddr),

    AttrAddr = ?SCREEN_ATTRS + ((Third * 8 + CharRowInThird) * 32) + CharCol,
    AttrByte = ReadByteFun(AttrAddr),

    BitPos = 7 - (X rem 8),
    PixelOn = (BitmapByte bsr BitPos) band 1 =:= 1,

    Ink = AttrByte band 16#07,
    Paper = (AttrByte bsr 3) band 16#07,
    Bright = (AttrByte bsr 6) band 1 =:= 1,
    Flash = (AttrByte bsr 7) band 1 =:= 1,

    {FinalInk, FinalPaper} = case Flash andalso flash_active(FrameCounter) of
        true -> {Paper, Ink};
        false -> {Ink, Paper}
    end,

    ColorIndex = case PixelOn of
        true -> FinalInk;
        false -> FinalPaper
    end,
    color(ColorIndex, Bright).

%% @doc Decode one screen line (Y = 0..191).
%% Returns a list of 256 {R, G, B} tuples.
-spec decode_screen_line(function(), non_neg_integer(), non_neg_integer()) -> list().
decode_screen_line(ReadByteFun, FrameCounter, ScreenY) ->
    [screen_pixel(ReadByteFun, FrameCounter, X, ScreenY) || X <- lists:seq(0, ?SCREEN_WIDTH - 1)].

%% @doc Decode all 192 screen lines.
-spec decode_screen(function(), non_neg_integer()) -> list().
decode_screen(ReadByteFun, FrameCounter) ->
    [decode_screen_line(ReadByteFun, FrameCounter, Y) ||
     Y <- lists:seq(0, ?SCREEN_HEIGHT - 1)].

%% @doc Decode the full frame including border (352 x 288 pixels).
%% BorderChanges is a list of {TState, ColorIndex} (newest-first from machine_state).
%% CurrentBorder is the persistent border color (last known value).
%% Returns a list of 288 rows, each row a list of 352 {R, G, B} tuples.
-spec decode_full_frame(function(), non_neg_integer(), list(), non_neg_integer()) -> list().
decode_full_frame(ReadByteFun, FrameCounter, BorderChanges, CurrentBorder) ->
    Sorted = lists:reverse(lists:keysort(1, BorderChanges)),
    [decode_full_line(ReadByteFun, FrameCounter, Sorted, CurrentBorder, Y) ||
     Y <- lists:seq(0, ?FULL_HEIGHT - 1)].


%% --- Internal ---

%% Decode one full-frame line (Y = 0..287), 352 pixels wide.
decode_full_line(ReadByteFun, FrameCounter, SortedChanges, CurrentBorder, Y) ->
    IsScreenLine = Y >= ?SCREEN_Y_MIN andalso Y =< ?SCREEN_Y_MAX,
    [full_frame_pixel(ReadByteFun, FrameCounter, SortedChanges, CurrentBorder, IsScreenLine, X, Y) ||
     X <- lists:seq(0, ?FULL_WIDTH - 1)].

%% Render a single pixel in the full frame.
full_frame_pixel(_ReadByteFun, _FrameCounter, SortedChanges, CurrentBorder, false, X, Y) ->
    TState = pixel_tstate(X, Y),
    lookup_border_color(SortedChanges, CurrentBorder, TState);
full_frame_pixel(ReadByteFun, FrameCounter, _SortedChanges, _CurrentBorder, true, X, Y) when
        X >= ?SCREEN_X_MIN andalso X =< ?SCREEN_X_MAX ->
    ScreenX = X - ?SCREEN_X_MIN,
    ScreenY = Y - ?SCREEN_Y_MIN,
    screen_pixel(ReadByteFun, FrameCounter, ScreenX, ScreenY);
full_frame_pixel(_ReadByteFun, _FrameCounter, SortedChanges, CurrentBorder, true, X, Y) ->
    TState = pixel_tstate(X, Y),
    lookup_border_color(SortedChanges, CurrentBorder, TState).

%% Map pixel (X, Y) to the T-state within the frame where its color is determined.
%% Uses the exact ZX Spectrum 48K timing:
%%   Left border:  T-states 0..23 per line  (2 px per T-state → 48 px)
%%   Screen area:  T-states 24..151 per line (2 px per T-state → 256 px)
%%   Right border: T-states 152..175 per line (2 px per T-state → 48 px)
-spec pixel_tstate(non_neg_integer(), non_neg_integer()) -> non_neg_integer().
pixel_tstate(X, Y) ->
    LineT = Y * ?TSTATES_PER_LINE,
    case X of
        LX when LX < ?BORDER_LEFT ->
            LineT + LX div 2;
        MX when MX >= ?SCREEN_X_MIN andalso MX =< ?SCREEN_X_MAX ->
            LineT + 24 + (MX - ?SCREEN_X_MIN) div 2;
        RX when RX >= ?BORDER_RIGHT ->
            LineT + 152 + (RX - ?BORDER_RIGHT) div 2
    end.

%% Look up border color from a sorted (ascending) changes list.
%% Falls back to CurrentBorder when no change applies.
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

flash_active(FrameCounter) ->
    (FrameCounter div 16) rem 2 =:= 1.

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
