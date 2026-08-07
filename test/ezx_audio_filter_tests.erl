-module(ezx_audio_filter_tests).

-include_lib("eunit/include/eunit.hrl").

dc_st() -> ezx_audio_filter:new(#{hpf => 0.9887}).

silence_in_silence_out_test() ->
    In = zeros(100),
    {Out, _} = ezx_audio_filter:filter(In, dc_st()),
    ?assertEqual(In, Out).

constant_dc_decays_to_silence_test() ->
    In = dc_mono(4096),
    {Out, _} = ezx_audio_filter:filter(In, dc_st()),
    ?assertEqual(0, last_sample(Out)).

ac_signal_survives_test() ->
    In = list_to_binary([<<(case N rem 2 of 0 -> 4096; 1 -> -4096 end):16/signed-little>>
                         || N <- lists:seq(1, 2000)]),
    {Out, _} = ezx_audio_filter:filter(In, dc_st()),
    ?assert(abs(last_sample(Out)) > 3000).

stages_skippable_test() ->
    In = dc_mono(100),
    {Out, _} = ezx_audio_filter:filter(In, ezx_audio_filter:new(#{})),
    ?assertEqual(In, Out).

lpf_only_settles_at_dc_test() ->
    In = dc_mono(2000),
    {Out, _} = ezx_audio_filter:filter(In, ezx_audio_filter:new(#{lpf => 0.090})),
    ?assertEqual(-4096, last_sample(Out)).

full_filter_kills_dc_test() ->
    In = dc_mono(4096),
    {Out, _} = ezx_audio_filter:filter(In, ezx_audio_filter:new(#{lpf => 0.090, hpf => 0.9887})),
    ?assertEqual(0, last_sample(Out)).

zeros(N) -> <<0:(16 * N)>>.

dc_mono(N) -> list_to_binary([<<-4096:16/signed-little>> || _ <- lists:seq(1, N)]).

last_sample(Bin) ->
    Size = byte_size(Bin),
    <<_:(Size - 2)/binary, S:16/signed-little>> = Bin,
    S.
