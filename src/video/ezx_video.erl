-module(ezx_video).

-export([
    decode_screen_line/3,
    decode_screen/2,
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
    CharRow = Y div 8,
    PixelRow = Y rem 8,

    BitmapAddr = ?SCREEN_BITMAP + (CharRow * 2048) + (PixelRow * 256) + CharCol,
    BitmapByte = ReadByteFun(BitmapAddr),

    AttrAddr = ?SCREEN_ATTRS + (CharRow * 32) + CharCol,
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


%% --- Internal ---

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
