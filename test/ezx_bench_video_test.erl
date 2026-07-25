-module(ezx_bench_video_test).
-include_lib("eunit/include/eunit.hrl").
-include("ezx_emulator.hrl").

bench_test_() ->
    {timeout, 120, fun bench_test/0}.

bench_test() ->
    {ok, SnaData} = file:read_file("/home/serge/Spectrum/Games/s/Saboteur! (1985)(Durell).sna"),
    M0 = ezx_emulator:init(),
    M1 = ezx_emulator:load_sna(M0, SnaData),
    M2 = warmup(M1, 100),

    Mem = M2#machine_state.memory,
    Changes = lists:reverse(M2#machine_state.border_changes),
    CB = M2#machine_state.border_color,

    N = 100,

    %% Warmup
    lists:foreach(fun(I) -> _ = ezx_video:render_frame(Mem, I, Changes, CB) end, lists:seq(0, 9)),

    %% Timed
    T0 = erlang:monotonic_time(microsecond),
    lists:foreach(fun(I) -> _ = ezx_video:render_frame(Mem, I, Changes, CB) end, lists:seq(0, N-1)),
    T1 = erlang:monotonic_time(microsecond),

    UsPerFrame = (T1 - T0) / N,
    io:format(standard_error,
        "~n=== render_frame benchmark (~p iterations, Saboteur SNA) ===~n"
        "Per frame: ~.1f us (~.2f ms)~n",
        [N, UsPerFrame, UsPerFrame / 1000]),

    SampleRGB = ezx_video:render_frame(Mem, 0, Changes, CB),
    ?assertEqual(352 * 288 * 3, byte_size(SampleRGB)),
    ok.

warmup(M, 0) -> M;
warmup(M, N) -> warmup(ezx_emulator:run_frame(M), N - 1).
