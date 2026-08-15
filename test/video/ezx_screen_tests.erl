-module(ezx_screen_tests).

-include("ezx_emulator.hrl").
-include_lib("eunit/include/eunit.hrl").

-define(FULL_Y_OFFSET, 16).

%% ============================================================================
%% Output
%% ============================================================================

output_size_test() ->
    VB = create_video_buffer(16#FF, 16#07),
    RGB = ezx_screen:render_screen(VB, false, [], 1, ?TSTATES_PER_LINE),
    ?assertEqual(352 * 288 * 3, byte_size(RGB)).

%% ============================================================================
%% Screen pixels: solid fill
%% ============================================================================

white_screen_test() ->
    VB = create_video_buffer(16#FF, 16#07),
    RGB = ezx_screen:render_screen(VB, false, [], 1, ?TSTATES_PER_LINE),
    ?assertEqual({215, 215, 215}, read_pixel(RGB, 48, 48)).

black_screen_test() ->
    VB = create_video_buffer(16#00, 16#07),
    RGB = ezx_screen:render_screen(VB, false, [], 1, ?TSTATES_PER_LINE),
    ?assertEqual({0, 0, 0}, read_pixel(RGB, 48, 48)).

%% ============================================================================
%% Screen pixels: single pixel
%% ============================================================================

top_left_pixel_ink_test() ->
    VB = create_video_buffer_with_bitmap(<<16#80, 0:6143/unit:8>>, 16#07),
    RGB = ezx_screen:render_screen(VB, false, [], 1, ?TSTATES_PER_LINE),
    ?assertEqual({215, 215, 215}, read_pixel(RGB, 48, 48)).

top_left_pixel_paper_test() ->
    VB = create_video_buffer_with_bitmap(<<0:6144/unit:8>>, 16#07),
    RGB = ezx_screen:render_screen(VB, false, [], 1, ?TSTATES_PER_LINE),
    ?assertEqual({0, 0, 0}, read_pixel(RGB, 48, 48)).

%% ============================================================================
%% Screen pixels: bitmap patterns
%% ============================================================================

alternating_pixels_test() ->
    VB = create_video_buffer_with_bitmap(<<16#AA, 0:6143/unit:8>>, 16#07),
    RGB = ezx_screen:render_screen(VB, false, [], 1, ?TSTATES_PER_LINE),
    ?assertEqual({215, 215, 215}, read_pixel(RGB, 48, 48)),
    ?assertEqual({0, 0, 0}, read_pixel(RGB, 49, 48)).

inverse_alternating_test() ->
    VB = create_video_buffer_with_bitmap(<<16#55, 0:6143/unit:8>>, 16#07),
    RGB = ezx_screen:render_screen(VB, false, [], 1, ?TSTATES_PER_LINE),
    ?assertEqual({0, 0, 0}, read_pixel(RGB, 48, 48)),
    ?assertEqual({215, 215, 215}, read_pixel(RGB, 49, 48)).

all_bits_set_test() ->
    VB = create_video_buffer_with_bitmap(<<16#FF, 0:6143/unit:8>>, 16#07),
    RGB = ezx_screen:render_screen(VB, false, [], 1, ?TSTATES_PER_LINE),
    [?assertEqual({215, 215, 215}, read_pixel(RGB, X, 48))
     || X <- lists:seq(48, 55)].

no_bits_set_test() ->
    VB = create_video_buffer_with_bitmap(<<16#00, 0:6143/unit:8>>, 16#07),
    RGB = ezx_screen:render_screen(VB, false, [], 1, ?TSTATES_PER_LINE),
    [?assertEqual({0, 0, 0}, read_pixel(RGB, X, 48))
     || X <- lists:seq(48, 55)].

%% ============================================================================
%% Screen pixels: bright
%% ============================================================================

bright_test() ->
    VB = create_video_buffer(16#FF, 16#47),
    RGB = ezx_screen:render_screen(VB, false, [], 1, ?TSTATES_PER_LINE),
    ?assertEqual({255, 255, 255}, read_pixel(RGB, 48, 48)).

bright_plus_bitmap_test() ->
    VB = create_video_buffer_with_bitmap(<<16#80, 0:6143/unit:8>>, 16#47),
    RGB = ezx_screen:render_screen(VB, false, [], 1, ?TSTATES_PER_LINE),
    ?assertEqual({255, 255, 255}, read_pixel(RGB, 48, 48)),
    ?assertEqual({0, 0, 0}, read_pixel(RGB, 49, 48)).

bright_yellow_ink_test() ->
    VB = create_video_buffer_with_bitmap(<<16#80, 0:6143/unit:8>>, 16#46),
    RGB = ezx_screen:render_screen(VB, false, [], 1, ?TSTATES_PER_LINE),
    ?assertEqual({255, 255, 0}, read_pixel(RGB, 48, 48)).

%% ============================================================================
%% Screen pixels: ink/paper colors
%% ============================================================================

blue_ink_on_black_paper_test() ->
    VB = create_video_buffer_with_bitmap(<<16#80, 0:6143/unit:8>>, 16#01),
    RGB = ezx_screen:render_screen(VB, false, [], 1, ?TSTATES_PER_LINE),
    ?assertEqual({0, 0, 215}, read_pixel(RGB, 48, 48)),
    ?assertEqual({0, 0, 0}, read_pixel(RGB, 49, 48)).

red_ink_on_cyan_paper_test() ->
    VB = create_video_buffer_with_bitmap(<<16#FF, 0:6143/unit:8>>, 16#02 bor (5 bsl 3)),
    RGB = ezx_screen:render_screen(VB, false, [], 1, ?TSTATES_PER_LINE),
    ?assertEqual({215, 0, 0}, read_pixel(RGB, 48, 48)).

%% ============================================================================
%% Flash
%% ============================================================================

flash_test() ->
    VB = create_video_buffer(16#FF, 16#87),
    RGB = ezx_screen:render_screen(VB, true, [], 1, ?TSTATES_PER_LINE),
    ?assertEqual({0, 0, 0}, read_pixel(RGB, 48, 48)).

%% ============================================================================
%% Border: default and uniform
%% ============================================================================

border_default_test() ->
    VB = create_video_buffer(16#00, 16#00),
    RGB = ezx_screen:render_screen(VB, false, [], 1, ?TSTATES_PER_LINE),
    ?assertEqual({0, 0, 215}, read_pixel(RGB, 0, 0)).

border_no_changes_test() ->
    VB = create_video_buffer(16#00, 16#00),
    RGB = ezx_screen:render_screen(VB, false, [], 5, ?TSTATES_PER_LINE),
    ?assertEqual({0, 215, 215}, read_pixel(RGB, 0, 0)).

uniform_border_test() ->
    VB = create_video_buffer(16#00, 16#00),
    RGB = ezx_screen:render_screen(VB, false, [], 4, ?TSTATES_PER_LINE),
    C = color(4),
    ?assertEqual(C, read_pixel(RGB, 0, 0)),
    ?assertEqual(C, read_pixel(RGB, 351, 0)),
    ?assertEqual(C, read_pixel(RGB, 0, 287)),
    ?assertEqual(C, read_pixel(RGB, 351, 287)).

%% ============================================================================
%% Border: change and stripes
%% ============================================================================

border_change_test() ->
    VB = create_video_buffer(16#00, 16#00),
    RGB = ezx_screen:render_screen(VB, false, [{0, 2}], 1, ?TSTATES_PER_LINE),
    ?assertEqual({215, 0, 0}, read_pixel(RGB, 0, 0)).

border_stripes_test() ->
    VB = create_video_buffer(16#00, 16#00),
    RGB = ezx_screen:render_screen(VB, false, stripes_changes(), 7, ?TSTATES_PER_LINE),
    lists:foreach(fun({Y, C}) ->
        ?assertEqual(color(C), read_pixel(RGB, 0, Y))
    end, [{10,0},{50,1},{90,2},{120,3},{160,4},{200,5},{240,6},{270,7}]).

stripes_boundary_test() ->
    VB = create_video_buffer(16#00, 16#00),
    RGB = ezx_screen:render_screen(VB, false, stripes_changes(), 7, ?TSTATES_PER_LINE),
    ?assertEqual(color(0), read_pixel(RGB, 0, 35)),
    ?assertEqual(color(1), read_pixel(RGB, 0, 36)),
    ?assertEqual(color(1), read_pixel(RGB, 0, 71)),
    ?assertEqual(color(2), read_pixel(RGB, 0, 72)).

stripes_right_border_test() ->
    VB = create_video_buffer(16#00, 16#00),
    RGB = ezx_screen:render_screen(VB, false, stripes_changes(), 7, ?TSTATES_PER_LINE),
    ?assertEqual(color(0), read_pixel(RGB, 351, 10)),
    ?assertEqual(color(4), read_pixel(RGB, 351, 160)).

screen_unaffected_by_border_test() ->
    VB = create_video_buffer(16#00, 16#00),
    RGB = ezx_screen:render_screen(VB, false, stripes_changes(), 7, ?TSTATES_PER_LINE),
    ?assertEqual({0, 0, 0}, read_pixel(RGB, 100, 100)),
    ?assertEqual({0, 0, 0}, read_pixel(RGB, 200, 200)).

%% ============================================================================
%% Line geometry: Pentagon (32 T retrace + 36 T left border + 128 T screen +
%% 28 T right border; the 384 px wide visible window {32, 224, 68, 196} shows
%% the FULL Pentagon border — 72 px left, 56 px right, screen at pixels
%% 72..327 — in the 304-line frame {16, 80, 304} with the screen at rows
%% 64..255)
%% ============================================================================

line_geometry_48k_default_identity_test() ->
    %% render_screen/5 (no geometry) must equal render_screen/6 with the
    %% explicit 48K geometry — the default path stays byte-identical.
    VB = create_video_buffer(16#00, 16#00),
    Changes = stripes_changes(),
    R5 = ezx_screen:render_screen(VB, false, Changes, 7, ?TSTATES_PER_LINE),
    R6 = ezx_screen:render_screen(VB, false, Changes, 7, ?TSTATES_PER_LINE,
                                  {?LINE_GEOMETRY_48K, ?FRAME_GEOMETRY_48K}),
    ?assertEqual(R5, R6).

pentagon_screen_centered_test() ->
    %% The Pentagon's original geometry: the screen lands at pixels 72..327,
    %% with the full 72 px left + 56 px right border around it.
    VB = create_video_buffer(16#FF, 16#07),
    RGB = ezx_screen:render_screen(VB, false, [], 1, ?TSTATES_PER_LINE,
                                   {?LINE_GEOMETRY_PENTAGON, ?FRAME_GEOMETRY_PENTAGON}),
    ?assertEqual({215, 215, 215}, read_px(RGB, 384, 72, 64)),
    ?assertEqual({0, 0, 215}, read_px(RGB, 384, 71, 64)),
    ?assertEqual({215, 215, 215}, read_px(RGB, 384, 327, 64)),
    ?assertEqual({0, 0, 215}, read_px(RGB, 384, 328, 64)).

pentagon_screen_rows_test() ->
    %% Vertically the screen fills rows 64..255 of the 304 rendered lines (the
    %% window is frame lines 16..319: 64 px top border, 48 px bottom border).
    VB = create_video_buffer(16#FF, 16#07),
    RGB = ezx_screen:render_screen(VB, false, [], 1, ?TSTATES_PER_LINE,
                                   {?LINE_GEOMETRY_PENTAGON, ?FRAME_GEOMETRY_PENTAGON}),
    ?assertEqual({0, 0, 215}, read_px(RGB, 384, 100, 63)),
    ?assertEqual({215, 215, 215}, read_px(RGB, 384, 100, 64)),
    ?assertEqual({215, 215, 215}, read_px(RGB, 384, 100, 255)),
    ?assertEqual({0, 0, 215}, read_px(RGB, 384, 100, 256)),
    ?assertEqual(384 * 304 * 3, byte_size(RGB)).

pentagon_left_border_change_test() ->
    %% A change 50 T into the line (18 T into the 36 T left border, since the
    %% visible window starts at T 32) splits the 72 px left border at pixel 36.
    VB = create_video_buffer(16#00, 16#00),
    LineT = ?FULL_Y_OFFSET * ?TSTATES_PER_LINE,
    RGB = ezx_screen:render_screen(VB, false, [{LineT + 50, 2}], 1, ?TSTATES_PER_LINE,
                                   {?LINE_GEOMETRY_PENTAGON, ?FRAME_GEOMETRY_PENTAGON}),
    ?assertEqual({0, 0, 215}, read_px(RGB, 384, 35, 0)),
    ?assertEqual({215, 0, 0}, read_px(RGB, 384, 36, 0)),
    ?assertEqual({215, 0, 0}, read_px(RGB, 384, 71, 0)).

pentagon_right_border_change_test() ->
    %% A change 200 T into the line (4 T into the 28 T right border) lands at
    %% pixel 328 + (200 - 196) * 2 = 336.
    VB = create_video_buffer(16#00, 16#00),
    LineT = ?FULL_Y_OFFSET * ?TSTATES_PER_LINE,
    RGB = ezx_screen:render_screen(VB, false, [{LineT + 200, 2}], 1, ?TSTATES_PER_LINE,
                                   {?LINE_GEOMETRY_PENTAGON, ?FRAME_GEOMETRY_PENTAGON}),
    ?assertEqual({0, 0, 215}, read_px(RGB, 384, 335, 0)),
    ?assertEqual({215, 0, 0}, read_px(RGB, 384, 336, 0)),
    ?assertEqual({215, 0, 0}, read_px(RGB, 384, 383, 0)).

pentagon_retrace_change_test() ->
    %% A change inside the 32 T retrace (before the window, at T 20) sets the
    %% color the whole visible border line shows (like the real ULA, which
    %% latches the new color before the border output starts), and must not
    %% distort the window geometry (the line stays 384 px wide).
    VB = create_video_buffer(16#00, 16#00),
    LineT = ?FULL_Y_OFFSET * ?TSTATES_PER_LINE,
    RGB = ezx_screen:render_screen(VB, false, [{LineT + 20, 2}], 1, ?TSTATES_PER_LINE,
                                   {?LINE_GEOMETRY_PENTAGON, ?FRAME_GEOMETRY_PENTAGON}),
    ?assertEqual(384 * 304 * 3, byte_size(RGB)),
    ?assertEqual({215, 0, 0}, read_px(RGB, 384, 0, 0)),
    ?assertEqual({215, 0, 0}, read_px(RGB, 384, 383, 0)).

%% ============================================================================
%% Right border of a SCREEN line: a border change in the right border zone
%% (T 152..175 on 48K/128K, T 196..223 on the Pentagon) must land at its own
%% pixel and must NOT grow the line — the old bug passed screen_x (48/72) as
%% the segment start instead of screen_x + 256, so the change emitted a
%% 272-px base run and every line below it shifted sideways by 224 px (the
%% "swimming" display artefact).
%% ============================================================================

screen_line_right_border_change_48k_test() ->
    VB = create_video_buffer(16#00, 16#00),
    %% Y=84 is a screen line (frame line 100); offset 160 is 8 T into the
    %% 48K right border zone (152..175) -> pixel 304 + 16 = 320.
    LineT = line_tstate(84),
    RGB = ezx_screen:render_screen(VB, false, [{LineT + 160, 2}], 1, ?TSTATES_PER_LINE),
    ?assertEqual(352 * 288 * 3, byte_size(RGB)),
    ?assertEqual({0, 0, 215}, read_pixel(RGB, 319, 84)),   %% still base border
    ?assertEqual({215, 0, 0}, read_pixel(RGB, 320, 84)),   %% the change
    ?assertEqual({215, 0, 0}, read_pixel(RGB, 351, 84)),   %% rest of right border
    %% The line below must be aligned again: the carried red border fills
    %% px 0..47, the screen starts at px 48.
    ?assertEqual({215, 0, 0}, read_pixel(RGB, 0, 85)),
    ?assertEqual({215, 0, 0}, read_pixel(RGB, 47, 85)),
    ?assertEqual({0, 0, 0}, read_pixel(RGB, 48, 85)),
    ?assertEqual({215, 0, 0}, read_pixel(RGB, 351, 85)).

screen_line_right_border_change_pentagon_test() ->
    VB = create_video_buffer(16#00, 16#00),
    %% Y=84 screen line; offset 200 is 4 T into the Pentagon right border zone
    %% (196..223) -> pixel 328 + 8 = 336.
    LineT = line_tstate(84),
    RGB = ezx_screen:render_screen(VB, false, [{LineT + 200, 2}], 1, ?TSTATES_PER_LINE,
                                   {?LINE_GEOMETRY_PENTAGON, ?FRAME_GEOMETRY_PENTAGON}),
    ?assertEqual(384 * 304 * 3, byte_size(RGB)),
    ?assertEqual({0, 0, 215}, read_px(RGB, 384, 335, 84)),   %% still base border
    ?assertEqual({215, 0, 0}, read_px(RGB, 384, 336, 84)),   %% the change
    ?assertEqual({215, 0, 0}, read_px(RGB, 384, 383, 84)),
    %% The line below must be aligned again: the carried red border fills
    %% px 0..71, the screen starts at px 72.
    ?assertEqual({215, 0, 0}, read_px(RGB, 384, 0, 85)),
    ?assertEqual({215, 0, 0}, read_px(RGB, 384, 71, 85)),
    ?assertEqual({0, 0, 0}, read_px(RGB, 384, 72, 85)),
    ?assertEqual({215, 0, 0}, read_px(RGB, 384, 383, 85)).

%% ============================================================================
%% Helpers
%% ============================================================================

read_pixel(RGB, X, Y) ->
    Off = (Y * 352 + X) * 3,
    <<_:Off/binary, R:8, G:8, B:8, _/binary>> = RGB,
    {R, G, B}.

read_px(RGB, W, X, Y) ->
    Off = (Y * W + X) * 3,
    <<_:Off/binary, R:8, G:8, B:8, _/binary>> = RGB,
    {R, G, B}.

create_video_buffer(BitmapByte, AttrByte) ->
    Bitmap = << <<BitmapByte>> || _ <- lists:seq(1, 6144) >>,
    Attrs = << <<AttrByte>> || _ <- lists:seq(1, 768) >>,
    <<Bitmap/binary, Attrs/binary>>.

create_video_buffer_with_bitmap(Bitmap, AttrByte) when byte_size(Bitmap) =:= 6144 ->
    Attrs = << <<AttrByte>> || _ <- lists:seq(1, 768) >>,
    <<Bitmap/binary, Attrs/binary>>.

line_tstate(Y) ->
    (Y + ?FULL_Y_OFFSET) * ?TSTATES_PER_LINE.

stripes_changes() ->
    [{line_tstate(N * 36), N} || N <- lists:seq(0, 7)].

color(0) -> {0, 0, 0};
color(1) -> {0, 0, 215};
color(2) -> {215, 0, 0};
color(3) -> {215, 0, 215};
color(4) -> {0, 215, 0};
color(5) -> {0, 215, 215};
color(6) -> {215, 215, 0};
color(7) -> {215, 215, 215}.
