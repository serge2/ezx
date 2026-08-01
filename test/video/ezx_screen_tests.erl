-module(ezx_screen_tests).

-include_lib("eunit/include/eunit.hrl").

-define(TSTATES_PER_LINE, 224).
-define(FULL_Y_OFFSET, 16).

%% ============================================================================
%% Output
%% ============================================================================

output_size_test() ->
    VB = create_video_buffer(16#FF, 16#07),
    RGB = ezx_screen:render_screen(VB, false, [], 1),
    ?assertEqual(352 * 288 * 3, byte_size(RGB)).

%% ============================================================================
%% Screen pixels: solid fill
%% ============================================================================

white_screen_test() ->
    VB = create_video_buffer(16#FF, 16#07),
    RGB = ezx_screen:render_screen(VB, false, [], 1),
    ?assertEqual({215, 215, 215}, read_pixel(RGB, 48, 48)).

black_screen_test() ->
    VB = create_video_buffer(16#00, 16#07),
    RGB = ezx_screen:render_screen(VB, false, [], 1),
    ?assertEqual({0, 0, 0}, read_pixel(RGB, 48, 48)).

%% ============================================================================
%% Screen pixels: single pixel
%% ============================================================================

top_left_pixel_ink_test() ->
    VB = create_video_buffer_with_bitmap(<<16#80, 0:6143/unit:8>>, 16#07),
    RGB = ezx_screen:render_screen(VB, false, [], 1),
    ?assertEqual({215, 215, 215}, read_pixel(RGB, 48, 48)).

top_left_pixel_paper_test() ->
    VB = create_video_buffer_with_bitmap(<<0:6144/unit:8>>, 16#07),
    RGB = ezx_screen:render_screen(VB, false, [], 1),
    ?assertEqual({0, 0, 0}, read_pixel(RGB, 48, 48)).

%% ============================================================================
%% Screen pixels: bitmap patterns
%% ============================================================================

alternating_pixels_test() ->
    VB = create_video_buffer_with_bitmap(<<16#AA, 0:6143/unit:8>>, 16#07),
    RGB = ezx_screen:render_screen(VB, false, [], 1),
    ?assertEqual({215, 215, 215}, read_pixel(RGB, 48, 48)),
    ?assertEqual({0, 0, 0}, read_pixel(RGB, 49, 48)).

inverse_alternating_test() ->
    VB = create_video_buffer_with_bitmap(<<16#55, 0:6143/unit:8>>, 16#07),
    RGB = ezx_screen:render_screen(VB, false, [], 1),
    ?assertEqual({0, 0, 0}, read_pixel(RGB, 48, 48)),
    ?assertEqual({215, 215, 215}, read_pixel(RGB, 49, 48)).

all_bits_set_test() ->
    VB = create_video_buffer_with_bitmap(<<16#FF, 0:6143/unit:8>>, 16#07),
    RGB = ezx_screen:render_screen(VB, false, [], 1),
    [?assertEqual({215, 215, 215}, read_pixel(RGB, X, 48))
     || X <- lists:seq(48, 55)].

no_bits_set_test() ->
    VB = create_video_buffer_with_bitmap(<<16#00, 0:6143/unit:8>>, 16#07),
    RGB = ezx_screen:render_screen(VB, false, [], 1),
    [?assertEqual({0, 0, 0}, read_pixel(RGB, X, 48))
     || X <- lists:seq(48, 55)].

%% ============================================================================
%% Screen pixels: bright
%% ============================================================================

bright_test() ->
    VB = create_video_buffer(16#FF, 16#47),
    RGB = ezx_screen:render_screen(VB, false, [], 1),
    ?assertEqual({255, 255, 255}, read_pixel(RGB, 48, 48)).

bright_plus_bitmap_test() ->
    VB = create_video_buffer_with_bitmap(<<16#80, 0:6143/unit:8>>, 16#47),
    RGB = ezx_screen:render_screen(VB, false, [], 1),
    ?assertEqual({255, 255, 255}, read_pixel(RGB, 48, 48)),
    ?assertEqual({0, 0, 0}, read_pixel(RGB, 49, 48)).

bright_yellow_ink_test() ->
    VB = create_video_buffer_with_bitmap(<<16#80, 0:6143/unit:8>>, 16#46),
    RGB = ezx_screen:render_screen(VB, false, [], 1),
    ?assertEqual({255, 255, 0}, read_pixel(RGB, 48, 48)).

%% ============================================================================
%% Screen pixels: ink/paper colors
%% ============================================================================

blue_ink_on_black_paper_test() ->
    VB = create_video_buffer_with_bitmap(<<16#80, 0:6143/unit:8>>, 16#01),
    RGB = ezx_screen:render_screen(VB, false, [], 1),
    ?assertEqual({0, 0, 215}, read_pixel(RGB, 48, 48)),
    ?assertEqual({0, 0, 0}, read_pixel(RGB, 49, 48)).

red_ink_on_cyan_paper_test() ->
    VB = create_video_buffer_with_bitmap(<<16#FF, 0:6143/unit:8>>, 16#02 bor (5 bsl 3)),
    RGB = ezx_screen:render_screen(VB, false, [], 1),
    ?assertEqual({215, 0, 0}, read_pixel(RGB, 48, 48)).

%% ============================================================================
%% Flash
%% ============================================================================

flash_test() ->
    VB = create_video_buffer(16#FF, 16#87),
    RGB = ezx_screen:render_screen(VB, true, [], 1),
    ?assertEqual({0, 0, 0}, read_pixel(RGB, 48, 48)).

%% ============================================================================
%% Border: default and uniform
%% ============================================================================

border_default_test() ->
    VB = create_video_buffer(16#00, 16#00),
    RGB = ezx_screen:render_screen(VB, false, [], 1),
    ?assertEqual({0, 0, 215}, read_pixel(RGB, 0, 0)).

border_no_changes_test() ->
    VB = create_video_buffer(16#00, 16#00),
    RGB = ezx_screen:render_screen(VB, false, [], 5),
    ?assertEqual({0, 215, 215}, read_pixel(RGB, 0, 0)).

uniform_border_test() ->
    VB = create_video_buffer(16#00, 16#00),
    RGB = ezx_screen:render_screen(VB, false, [], 4),
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
    RGB = ezx_screen:render_screen(VB, false, [{0, 2}], 1),
    ?assertEqual({215, 0, 0}, read_pixel(RGB, 0, 0)).

border_stripes_test() ->
    VB = create_video_buffer(16#00, 16#00),
    RGB = ezx_screen:render_screen(VB, false, stripes_changes(), 7),
    lists:foreach(fun({Y, C}) ->
        ?assertEqual(color(C), read_pixel(RGB, 0, Y))
    end, [{10,0},{50,1},{90,2},{120,3},{160,4},{200,5},{240,6},{270,7}]).

stripes_boundary_test() ->
    VB = create_video_buffer(16#00, 16#00),
    RGB = ezx_screen:render_screen(VB, false, stripes_changes(), 7),
    ?assertEqual(color(0), read_pixel(RGB, 0, 35)),
    ?assertEqual(color(1), read_pixel(RGB, 0, 36)),
    ?assertEqual(color(1), read_pixel(RGB, 0, 71)),
    ?assertEqual(color(2), read_pixel(RGB, 0, 72)).

stripes_right_border_test() ->
    VB = create_video_buffer(16#00, 16#00),
    RGB = ezx_screen:render_screen(VB, false, stripes_changes(), 7),
    ?assertEqual(color(0), read_pixel(RGB, 351, 10)),
    ?assertEqual(color(4), read_pixel(RGB, 351, 160)).

screen_unaffected_by_border_test() ->
    VB = create_video_buffer(16#00, 16#00),
    RGB = ezx_screen:render_screen(VB, false, stripes_changes(), 7),
    ?assertEqual({0, 0, 0}, read_pixel(RGB, 100, 100)),
    ?assertEqual({0, 0, 0}, read_pixel(RGB, 200, 200)).

%% ============================================================================
%% Helpers
%% ============================================================================

read_pixel(RGB, X, Y) ->
    Off = (Y * 352 + X) * 3,
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
