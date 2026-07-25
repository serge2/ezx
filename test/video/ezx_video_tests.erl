-module(ezx_video_tests).

-include_lib("eunit/include/eunit.hrl").

%% --- Border color tests ---

border_color_default_test() ->
    ?assertEqual({0, 0, 215}, ezx_video:border_color([], 0)).

border_color_single_change_test() ->
    ?assertEqual({215, 0, 0}, ezx_video:border_color([{0, 2}], 0)).

border_color_change_mid_frame_test() ->
    Changes = [{20000, 4}, {0, 1}],
    ?assertEqual({0, 215, 0}, ezx_video:border_color(Changes, 20000)),
    ?assertEqual({0, 215, 0}, ezx_video:border_color(Changes, 30000)),
    ?assertEqual({0, 0, 215}, ezx_video:border_color(Changes, 19999)).

border_color_multiple_changes_test() ->
    Changes = [{40000, 6}, {20000, 4}, {0, 1}],
    ?assertEqual({0, 0, 215}, ezx_video:border_color(Changes, 0)),
    ?assertEqual({0, 215, 0}, ezx_video:border_color(Changes, 20000)),
    ?assertEqual({215, 215, 0}, ezx_video:border_color(Changes, 40000)),
    ?assertEqual({215, 215, 0}, ezx_video:border_color(Changes, 69887)).


%% --- Frame line mapping tests ---

frame_line_for_screen_y_test() ->
    ?assertEqual(64, ezx_video:frame_line_for_screen_y(0)),
    ?assertEqual(255, ezx_video:frame_line_for_screen_y(191)).

tstate_for_frame_line_test() ->
    ?assertEqual(0, ezx_video:tstate_for_frame_line(0)),
    ?assertEqual(224, ezx_video:tstate_for_frame_line(1)),
    ?assertEqual(14336, ezx_video:tstate_for_frame_line(64)).


%% --- render_frame tests ---

render_frame_output_size_test() ->
    Bin = create_test_screen(16#FF, 16#07),
    Mem = #{size => 65536, data => Bin},
    RGB = ezx_video:render_frame(Mem, 0, [], 1),
    ?assertEqual(352 * 288 * 3, byte_size(RGB)).

render_frame_white_screen_test() ->
    %% All bitmap=0xFF, attr=ink7/paper0 -> all white pixels
    Bin = create_test_screen(16#FF, 16#07),
    Mem = #{size => 65536, data => Bin},
    RGB = ezx_video:render_frame(Mem, 0, [], 1),
    %% Screen area pixel at (48, 48) = first screen pixel
    {R, G, B} = read_pixel(RGB, 48, 48),
    ?assertEqual({215, 215, 215}, {R, G, B}).

render_frame_black_screen_test() ->
    %% All bitmap=0x00 -> all paper pixels
    Bin = create_test_screen(16#00, 16#07),
    Mem = #{size => 65536, data => Bin},
    RGB = ezx_video:render_frame(Mem, 0, [], 1),
    {R, G, B} = read_pixel(RGB, 48, 48),
    ?assertEqual({0, 0, 0}, {R, G, B}).

render_frame_border_default_test() ->
    %% Border area should use default border color (1 = blue)
    Bin = create_test_screen(16#00, 16#00),
    Mem = #{size => 65536, data => Bin},
    RGB = ezx_video:render_frame(Mem, 0, [], 1),
    %% Top-left pixel (0, 0) is border
    {R, G, B} = read_pixel(RGB, 0, 0),
    ?assertEqual({0, 0, 215}, {R, G, B}).

render_frame_flash_test() ->
    %% Flash=1, ink=7, paper=0, bitmap=0xFF -> flash active should swap
    Bin = create_test_screen(16#FF, 16#87),
    Mem = #{size => 65536, data => Bin},
    %% Frame counter 16 -> flash active -> ink/paper swap -> pixel should be paper (black)
    RGB = ezx_video:render_frame(Mem, 16, [], 1),
    {R, G, B} = read_pixel(RGB, 48, 48),
    ?assertEqual({0, 0, 0}, {R, G, B}).

render_frame_bright_test() ->
    Bin = create_test_screen(16#FF, 16#47),
    Mem = #{size => 65536, data => Bin},
    RGB = ezx_video:render_frame(Mem, 0, [], 1),
    {R, G, B} = read_pixel(RGB, 48, 48),
    ?assertEqual({255, 255, 255}, {R, G, B}).


%% --- Helpers ---

read_pixel(RGB, X, Y) ->
    Off = (Y * 352 + X) * 3,
    <<_:Off/binary, R:8, G:8, B:8, _/binary>> = RGB,
    {R, G, B}.

create_test_screen(BitmapByte, AttrByte) ->
    BitmapSize = 6144,
    Bitmap = <<<<BitmapByte>> || _ <- lists:seq(1, BitmapSize)>>,
    AttrSize = 768,
    Attrs = <<<<AttrByte>> || _ <- lists:seq(1, AttrSize)>>,
    Prefix = <<0:(16#4000)/unit:8>>,
    Between = <<0:(16#5800 - 16#4000 - BitmapSize)/unit:8>>,
    Suffix = <<0:(16#10000 - 16#5800 - AttrSize)/unit:8>>,
    <<Prefix/binary, Bitmap/binary, Between/binary, Attrs/binary, Suffix/binary>>.
