-module(ezx_frame_contract_tests).

-include_lib("eunit/include/eunit.hrl").

%% ---------------------------------------------------------------------------
%% Device frame contract under the physical-overrun model (shared by the
%% beeper, the ULA screen device and the AY):
%%
%%   - The frame spans the nominal boundary interval (counter 0..FrameLen);
%%     devices record events with absolute machine-counter stamps.
%%   - frame_render splits events at FrameLen: events with a counter below
%%     FrameLen belong to this frame, events at/above it belong to the NEXT
%%     frame and are carried over in the returned state, rebased by
%%     -FrameLen into the next frame's counter domain — never dropped.
%%   - The boundary level/color/regs (the value at the nominal frame
%%     boundary, after the last rendered change) is carried into the next
%%     frame's baseline, so the next frame starts exactly where the ULA
%%     timeline puts the carried events.
%%
%% These tests drive two consecutive frames and check that a change made in
%% the overrun zone of frame 1 lands at the start of frame 2.
%% ---------------------------------------------------------------------------

-define(LEVEL0, -4096).
-define(LEVEL1, 4096).

%% ---------------------------------------------------------------------------
%% Beeper
%% ---------------------------------------------------------------------------

beeper_tail_carries_level_change_test_() ->
    FrameLen = 1000,
    Samples = 100,
    fun() ->
        %% Frame 1: a level change inside the window (T=400, sample 40) and
        %% one past the nominal boundary (T=1010): the overrun change must
        %% NOT be rendered this frame, but carried over rebased by -FrameLen.
        B0 = ezx_beeper2:init(0),
        B1 = ezx_beeper2:set_level(B0, 1, 400),
        B2 = ezx_beeper2:set_level(B1, 0, 1010),
        {PCM, B3} = ezx_beeper2:frame_render(B2, FrameLen, Samples),
        S = [V || <<V:16/signed-little>> <= PCM],
        ?assertEqual([?LEVEL0], lists:usort(lists:sublist(S, 40))),
        ?assertEqual([?LEVEL1], lists:usort(lists:nthtail(40, S))),
        %% live level already reflects the tail change to 0
        ?assertEqual(0, ezx_beeper2:level(B3)),
        %% Frame 2: the carried tail starts the frame at the boundary level 1
        %% and applies the overrun change at its (rebased) position, then a
        %% new mid-frame change takes effect as usual.
        B4 = ezx_beeper2:frame_start(B3, 0),
        B5 = ezx_beeper2:set_level(B4, 1, 200),
        {PCM2, _} = ezx_beeper2:frame_render(B5, FrameLen, Samples),
        S2 = [V || <<V:16/signed-little>> <= PCM2],
        ?assertEqual(?LEVEL1, hd(S2)),
        ?assertEqual([?LEVEL0], lists:usort(lists:sublist(S2, 2, 19))),
        ?assertEqual([?LEVEL1], lists:usort(lists:nthtail(20, S2)))
    end.

%% ---------------------------------------------------------------------------
%% ULA screen device
%% ---------------------------------------------------------------------------

screen_tail_carries_border_change_test_() ->
    FrameLen = 1000,
    fun() ->
        %% Frame 1: a border change inside the window (T=300) and one past
        %% the nominal boundary (T=1020).  The frame returns the local change,
        %% the base color at the boundary (0), and carries the tail over.
        S0 = ezx_screen:new(),
        S1 = ezx_screen:border_set(S0, 300, 2),
        S2 = ezx_screen:border_set(S1, 1020, 5),
        {Local1, Base1, _Flash1, S3} = ezx_screen:frame_render(S2, FrameLen),
        ?assertEqual([{300, 2}], Local1),
        ?assertEqual(0, Base1),
        %% live color already reflects the tail change
        ?assertEqual(5, ezx_screen:border_get(S3)),
        %% Frame 2: the carried tail change appears at the start of the local
        %% timeline and the base color is the boundary color carried from
        %% frame 1 (the color after frame 1's window = 2).
        S4 = ezx_screen:frame_start(S3, 0),
        S5 = ezx_screen:border_set(S4, 700, 4),
        {Local2, Base2, _Flash2, S6} = ezx_screen:frame_render(S5, FrameLen),
        ?assertEqual([{20, 5}, {700, 4}], Local2),
        ?assertEqual(2, Base2),
        ?assertEqual(4, ezx_screen:border_get(S6))
    end.

%% ---------------------------------------------------------------------------
%% AY-3-8912 (segmented)
%% ---------------------------------------------------------------------------

ay_tail_carries_register_write_test_() ->
    M = ezx_ay38912_seg,
    FrameLen = 882,
    Samples = 882,
    fun() ->
        %% Frame 1: tone A at period 1, mixer with noise disabled on A,
        %% volume 15 — audible — plus a mute past the nominal boundary.
        AY1 = ay_write_setup(M, [{0, 0}, {1, 0}, {7, 8}, {8, 15}]),
        AY2 = M:write(M:latch(AY1, 8), 0, FrameLen + 50),
        {ChA1, _, _, AY3} = M:render_channels(AY2, FrameLen, Samples),
        S1 = [V || <<V:16/little-signed>> <= ChA1],
        ?assert(lists:any(fun(X) -> X =/= ?LEVEL0 end, S1)),
        %% the live register state reflects the tail write (mute), while the
        %% boundary state rendered from does not
        ?assertEqual(0, element(9, list_to_tuple(M:regs(AY3)))),
        %% Frame 2: the carried mute lands at its rebased sample position —
        %% audible at the start (tone still sounding from the boundary
        %% state), then constant silence from sample 50 on.
        AY4 = M:frame_start(AY3, 0),
        {ChA2, _, _, _} = M:render_channels(AY4, FrameLen, Samples),
        S2 = [V || <<V:16/little-signed>> <= ChA2],
        ?assert(lists:any(fun(X) -> X =/= ?LEVEL0 end, lists:sublist(S2, 50))),
        ?assertEqual([?LEVEL0], lists:usort(lists:nthtail(50, S2)))
    end.

%% --- helpers ---

%% Writes at TState 0, newest-first log order like the emulator's port writes.
ay_write_setup(M, Writes) ->
    lists:foldl(fun({Reg, Val}, AY) ->
        M:write(M:latch(AY, Reg), Val, 0)
    end, M:new(ay), Writes).
