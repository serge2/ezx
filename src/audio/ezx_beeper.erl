-module(ezx_beeper).

%% ZX Spectrum 1-bit beeper emulation.
%% Maps T-state timeline to PCM samples using Bresenham DDA.
%% Exactly matches aplay's expected sample rate by accumulating fractional error.

-define(CPU_FREQ, 3500000).
-define(SAMPLE_RATE, 44100).
%% Use 70000 for audio timing (not 69888) so that
%% 70000 * 44100 / 3500000 = 882 samples per frame exactly.
%% This matches aplay's expected 44100 Hz at 50 fps.
-define(TSTATES_PER_FRAME_AUDIO, 70000).
-define(SAMPLES_PER_FRAME, 882).

%% PCM amplitude: bipolar to avoid DC offset.
-define(AMP_OFF, -8192).
-define(AMP_ON,  8192).

-export([init/0, set_level/3, flush_frame/1, silence_frame/0]).

-record(beeper, {
    level = 0          :: 0 | 1,
    last_t = 0         :: non_neg_integer(),
    samples = []       :: [integer()],
    phase = 0          :: non_neg_integer()
}).

-spec init() -> #beeper{}.
init() ->
    #beeper{}.

-spec set_level(#beeper{}, 0 | 1, non_neg_integer()) -> #beeper{}.
set_level(#beeper{level = _Level, last_t = LastT, samples = Smps, phase = Phase} = B,
          NewLevel, TState) when NewLevel =:= 0; NewLevel =:= 1 ->
    DeltaT = TState - LastT,
    {NewSamples, NewPhase} = emit_samples(Smps, _Level, DeltaT, Phase),
    B#beeper{level = NewLevel, last_t = TState, samples = NewSamples, phase = NewPhase}.

-spec flush_frame(#beeper{}) -> {binary(), #beeper{}}.
flush_frame(#beeper{level = Level, last_t = LastT, samples = Smps, phase = Phase}) ->
    RemainingT = ?TSTATES_PER_FRAME_AUDIO - LastT,
    {Samples, RemPhase} = emit_samples(Smps, Level, RemainingT, Phase),
    Count = length(Samples),
    case Count =/= ?SAMPLES_PER_FRAME of
        true -> io:format("BEEPER: ~p samples (expected 882), LastT=~p~n", [Count, LastT]);
        false -> ok
    end,
    PCM = case Count of
        ?SAMPLES_PER_FRAME ->
            list_to_binary([<<S:16/signed-little>> || S <- lists:reverse(Samples)]);
        _ when Count < ?SAMPLES_PER_FRAME ->
            Pad = lists:duplicate(?SAMPLES_PER_FRAME - Count, case Level of 0 -> ?AMP_OFF; 1 -> ?AMP_ON end),
            list_to_binary([<<S:16/signed-little>> || S <- lists:reverse(Samples ++ Pad)]);
        _ ->
            Trimmed = lists:sublist(lists:reverse(Samples), ?SAMPLES_PER_FRAME),
            list_to_binary([<<S:16/signed-little>> || S <- Trimmed])
    end,
    {PCM, #beeper{level = Level, last_t = 0, samples = [], phase = RemPhase}}.

%% @doc Return exactly one frame of silence (882 samples of 0).
-spec silence_frame() -> binary().
silence_frame() ->
    <<0:(?SAMPLES_PER_FRAME * 16)/signed-little>>.

%% --- Internal ---

emit_samples(Acc, _Level, 0, Phase) ->
    {Acc, Phase};
emit_samples(Acc, Level, DeltaT, Phase) ->
    Amp = case Level of 0 -> ?AMP_OFF; 1 -> ?AMP_ON end,
    NewPhase = Phase + DeltaT * ?SAMPLE_RATE,
    Quot = NewPhase div ?CPU_FREQ,
    Rem = NewPhase rem ?CPU_FREQ,
    case Quot > 0 of
        true ->
            NewAcc = lists:duplicate(Quot, Amp) ++ Acc,
            emit_samples(NewAcc, Level, 0, Rem);
        false ->
            {Acc, NewPhase}
    end.
