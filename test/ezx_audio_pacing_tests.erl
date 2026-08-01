-module(ezx_audio_pacing_tests).

-include_lib("eunit/include/eunit.hrl").

%% ---- new/1 ----

new_does_not_schedule_first_frame_test() ->
    P0 = ezx_audio_pacing:new(3528),
    {0, _P1} = ezx_audio_pacing:advance(P0, 3528, 0).

%% ---- surplus / throttling ----

fast_feeding_builds_surplus_test() ->
    P0 = ezx_audio_pacing:new(3528),
    {0, P1} = ezx_audio_pacing:advance(P0, 3528, 1),    %% frame 1
    {0, P2} = ezx_audio_pacing:advance(P1, 3528, 2),    %% frame 2
    {0, P3} = ezx_audio_pacing:advance(P2, 3528, 3),    %% frame 3
    {20, _P4} = ezx_audio_pacing:advance(P3, 3528, 4).  %% frame 4: surplus > 0

%% ---- real-time feeding stays at delay 0 ----

real_time_feeding_no_surplus_test() ->
    P0 = ezx_audio_pacing:new(3528),
    {0, P1} = ezx_audio_pacing:advance(P0, 3528, 0),
    {0, P2} = ezx_audio_pacing:advance(P1, 3528, 20000),
    {0, _P3} = ezx_audio_pacing:advance(P2, 3528, 40000).

%% ---- clock reset on long gap ----

long_gap_resets_clock_test() ->
    P0 = ezx_audio_pacing:new(3528),
    {0, P1} = ezx_audio_pacing:advance(P0, 3528, 1000),
    %% 5 second gap: buffer level crashes far below -2 frames → clock resets
    {0, P2} = ezx_audio_pacing:advance(P1, 3528, 5000000),
    ?assertEqual(3528, ezx_audio_pacing:bytes(P2)),
    %% Next frame after reset with small elapsed → delay 0
    {0, _P3} = ezx_audio_pacing:advance(P2, 3528, 5002000).

%% ---- bytes/1 tracks total written ----

bytes_tracks_total_test() ->
    P0 = ezx_audio_pacing:new(3528),
    {_, P1} = ezx_audio_pacing:advance(P0, 3528, 0),
    {_, P2} = ezx_audio_pacing:advance(P1, 3528, 20000),
    ?assertEqual(7056, ezx_audio_pacing:bytes(P2)).
