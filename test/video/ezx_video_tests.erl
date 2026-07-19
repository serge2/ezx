-module(ezx_video_tests).

-include_lib("eunit/include/eunit.hrl").

%% --- Border color tests ---

border_color_default_test() ->
    %% No changes: default border is blue (1).
    ?assertEqual({0, 0, 215}, ezx_video:border_color([], 0)).

border_color_single_change_test() ->
    %% Set border to red (2) at T=0.
    ?assertEqual({215, 0, 0}, ezx_video:border_color([{0, 2}], 0)).

border_color_change_mid_frame_test() ->
    %% Border is blue initially, changes to green (4) at T=20000.
    Changes = [{20000, 4}, {0, 1}],
    ?assertEqual({0, 215, 0}, ezx_video:border_color(Changes, 20000)),
    ?assertEqual({0, 215, 0}, ezx_video:border_color(Changes, 30000)),
    ?assertEqual({0, 0, 215}, ezx_video:border_color(Changes, 19999)).

border_color_multiple_changes_test() ->
    %% Three color changes during a frame.
    Changes = [{40000, 6}, {20000, 4}, {0, 1}],
    ?assertEqual({0, 0, 215}, ezx_video:border_color(Changes, 0)),
    ?assertEqual({0, 215, 0}, ezx_video:border_color(Changes, 20000)),
    ?assertEqual({215, 215, 0}, ezx_video:border_color(Changes, 40000)),
    ?assertEqual({215, 215, 0}, ezx_video:border_color(Changes, 69887)).


%% --- Screen pixel tests ---

%% Helper to create a ReadByteFun that reads from a flat memory binary.
make_read_fun(Bin) ->
    fun(Addr) ->
        Index = Addr band 16#ffff,
        case Bin of
            <<_:Index/binary, B:8/integer, _/binary>> -> B;
            _ -> 0
        end
    end.

screen_pixel_white_on_black_test() ->
    %% Screen bitmap at 0x4000: all 1s = white pixels on black paper.
    %% Attribute at 0x5800 (char row 0, col 0): INK=7 (white), PAPER=0 (black), BRIGHT=0, FLASH=0.
    %% Pixel (0,0): bitmap byte 0x4000 has bit7=1 -> ink
    %% Pixel (1,0): bitmap byte 0x4000 has bit6=1 -> ink
    Bin = create_test_screen(16#FF, 16#07),  %% bitmap=all ones, attr=ink7/paper0
    ReadFun = make_read_fun(Bin),
    ?assertEqual({215, 215, 215}, ezx_video:screen_pixel(ReadFun, 0, 0, 0)).

screen_pixel_black_on_white_test() ->
    %% Bitmap = 0x00 (all zeros = paper), attribute = ink7/paper0
    Bin = create_test_screen(16#00, 16#07),
    ReadFun = make_read_fun(Bin),
    ?assertEqual({0, 0, 0}, ezx_video:screen_pixel(ReadFun, 0, 0, 0)).

screen_pixel_individual_bits_test() ->
    %% Bitmap byte = 0x80 (bit7=1, rest=0), attribute = ink2(red)/paper4(green)
    %% Pixel (0,0) -> bit7 -> ink -> red
    %% Pixel (1,0) -> bit6=0 -> paper -> green
    Bin = create_test_screen(16#80, 16#22),  %% ink=2, paper=4
    ReadFun = make_read_fun(Bin),
    ?assertEqual({215, 0, 0}, ezx_video:screen_pixel(ReadFun, 0, 0, 0)),
    ?assertEqual({0, 215, 0}, ezx_video:screen_pixel(ReadFun, 0, 1, 0)).

screen_pixel_bright_test() ->
    %% Attribute: ink=1(blue), paper=0, BRIGHT=1 -> bright blue
    Bin = create_test_screen(16#FF, 16#41),  %% BRIGHT=1, ink=1
    ReadFun = make_read_fun(Bin),
    ?assertEqual({0, 0, 255}, ezx_video:screen_pixel(ReadFun, 0, 0, 0)).

screen_pixel_flash_no_effect_test() ->
    %% FLASH bit set, but frame_counter=0 -> no swap
    Bin = create_test_screen(16#FF, 16#87),  %% FLASH=1, ink=7, paper=0
    ReadFun = make_read_fun(Bin),
    ?assertEqual({215, 215, 215}, ezx_video:screen_pixel(ReadFun, 0, 0, 0)).

screen_pixel_flash_active_test() ->
    %% FLASH=1, frame_counter=16 -> flash active, swap ink/paper
    Bin = create_test_screen(16#FF, 16#87),  %% FLASH=1, ink=7, paper=0
    ReadFun = make_read_fun(Bin),
    %% Flash active: ink and paper swap -> pixel is now paper (black)
    ?assertEqual({0, 0, 0}, ezx_video:screen_pixel(ReadFun, 16, 0, 0)).

screen_pixel_flash_period_test() ->
    %% FLASH toggles every 16 frames.
    Bin = create_test_screen(16#00, 16#87),  %% FLASH=1, ink=7, paper=0, bitmap=0(paper)
    ReadFun = make_read_fun(Bin),
    %% frame_counter 0-15: no flash (paper=black, pixel on paper=black)
    ?assertEqual({0, 0, 0}, ezx_video:screen_pixel(ReadFun, 0, 0, 0)),
    %% frame_counter 16-31: flash active (swap: paper=white, pixel on paper=white)
    ?assertEqual({215, 215, 215}, ezx_video:screen_pixel(ReadFun, 16, 0, 0)).


%% --- Frame line mapping tests ---

frame_line_for_screen_y_test() ->
    ?assertEqual(64, ezx_video:frame_line_for_screen_y(0)),
    ?assertEqual(255, ezx_video:frame_line_for_screen_y(191)).

tstate_for_frame_line_test() ->
    ?assertEqual(0, ezx_video:tstate_for_frame_line(0)),
    ?assertEqual(224, ezx_video:tstate_for_frame_line(1)),
    ?assertEqual(14336, ezx_video:tstate_for_frame_line(64)).


%% --- Internal helpers ---

%% Create a minimal test screen binary with a repeating bitmap byte and attribute.
%% The screen area occupies addresses 0x4000-0x57FF (bitmap) and 0x5800-0x5AFF (attributes).
%% We create a 64KB binary with:
%%   - Bitmap area: every byte = BitmapByte
%%   - Attribute area: every byte = AttrByte
%%   - Rest zeros
create_test_screen(BitmapByte, AttrByte) ->
    BitmapSize = 6144,
    Bitmap = <<<<BitmapByte>> || _ <- lists:seq(1, BitmapSize)>>,
    AttrSize = 768,
    Attrs = <<<<AttrByte>> || _ <- lists:seq(1, AttrSize)>>,
    Prefix = <<0:(16#4000)/unit:8>>,
    Between = <<0:(16#5800 - 16#4000 - BitmapSize)/unit:8>>,
    Suffix = <<0:(16#10000 - 16#5800 - AttrSize)/unit:8>>,
    <<Prefix/binary, Bitmap/binary, Between/binary, Attrs/binary, Suffix/binary>>.
