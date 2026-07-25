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
    VB = create_video_buffer(16#FF, 16#07),
    RGB = ezx_video:render_frame(VB, 0, [], 1),
    ?assertEqual(352 * 288 * 3, byte_size(RGB)).

render_frame_white_screen_test() ->
    %% All bitmap=0xFF, attr=ink7/paper0 -> all white pixels
    VB = create_video_buffer(16#FF, 16#07),
    RGB = ezx_video:render_frame(VB, 0, [], 1),
    {R, G, B} = read_pixel(RGB, 48, 48),
    ?assertEqual({215, 215, 215}, {R, G, B}).

render_frame_black_screen_test() ->
    %% All bitmap=0x00 -> all paper pixels
    VB = create_video_buffer(16#00, 16#07),
    RGB = ezx_video:render_frame(VB, 0, [], 1),
    {R, G, B} = read_pixel(RGB, 48, 48),
    ?assertEqual({0, 0, 0}, {R, G, B}).

render_frame_border_default_test() ->
    %% Border area should use default border color (1 = blue)
    VB = create_video_buffer(16#00, 16#00),
    RGB = ezx_video:render_frame(VB, 0, [], 1),
    {R, G, B} = read_pixel(RGB, 0, 0),
    ?assertEqual({0, 0, 215}, {R, G, B}).

render_frame_flash_test() ->
    %% Flash=1, ink=7, paper=0, bitmap=0xFF -> flash active should swap
    VB = create_video_buffer(16#FF, 16#87),
    %% Frame counter 16 -> flash active -> ink/paper swap -> pixel should be paper (black)
    RGB = ezx_video:render_frame(VB, 16, [], 1),
    {R, G, B} = read_pixel(RGB, 48, 48),
    ?assertEqual({0, 0, 0}, {R, G, B}).

render_frame_bright_test() ->
    VB = create_video_buffer(16#FF, 16#47),
    RGB = ezx_video:render_frame(VB, 0, [], 1),
    {R, G, B} = read_pixel(RGB, 48, 48),
    ?assertEqual({255, 255, 255}, {R, G, B}).


%% --- Helpers ---

read_pixel(RGB, X, Y) ->
    Off = (Y * 352 + X) * 3,
    <<_:Off/binary, R:8, G:8, B:8, _/binary>> = RGB,
    {R, G, B}.

%% Create a 6912-byte video buffer: 6144 bytes bitmap + 768 bytes attributes.
%% This matches what ezx_memory_48:read_block(Mem, 16#4000, 6912) returns.
create_video_buffer(BitmapByte, AttrByte) ->
    Bitmap = << <<BitmapByte>> || _ <- lists:seq(1, 6144) >>,
    Attrs = << <<AttrByte>> || _ <- lists:seq(1, 768) >>,
    <<Bitmap/binary, Attrs/binary>>.
