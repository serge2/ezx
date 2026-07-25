-module(ezx_beeper).

%% ZX Spectrum 1-bit beeper emulation.
%% Uses a changes-list approach: port writes only append {TState, Level}
%% changes. Sample generation happens once per frame in flush_frame.
%% This avoids per-write emit_samples overhead.

-define(CPU_FREQ, 3500000).
-define(SAMPLE_RATE, 44100).
-define(TSTATES_PER_FRAME_AUDIO, 70000).
-define(SAMPLES_PER_FRAME, 882).

-define(AMP_OFF, -8192).
-define(AMP_ON,  8192).

-export([init/0, init/1, set_level/3, level/1, flush_frame/1, silence_frame/0]).

-record(beeper, {
    level = 0          :: 0 | 1,
    init_level = 0     :: 0 | 1,
    phase = 0          :: non_neg_integer(),
    changes = []       :: [{non_neg_integer(), 0 | 1}]
}).


-type state() :: #beeper{}.
-export_type([state/0]).


-spec init() -> state().
init() ->
    #beeper{}.

%% @doc Init with a known level (used after flush to carry level across frames).
-spec init(0 | 1) -> #beeper{}.
init(Level) ->
    #beeper{level = Level, init_level = Level}.

%% @doc Record a level change. Only appends to changes list if level differs.
-spec set_level(state(), 0 | 1, non_neg_integer()) -> state().
set_level(#beeper{level = Level} = B, NewLevel, _TState) when NewLevel =:= Level ->
    B;
set_level(#beeper{changes = Changes} = B, NewLevel, TState) ->
    B#beeper{level = NewLevel, changes = [{TState, NewLevel} | Changes]}.

-spec level(state()) -> 0 | 1.
level(#beeper{level = L}) -> L.

-spec flush_frame(state()) -> {binary(), state()}.
flush_frame(#beeper{level = Level, init_level = InitLevel, phase = Phase, changes = Changes}) ->
    Sorted = lists:reverse(Changes),
    {Samples, FinalPhase} = gen_samples(Sorted, 0, InitLevel, Phase, []),
    Count = length(Samples),
    case Count =/= ?SAMPLES_PER_FRAME of
        true -> io:format("BEEPER: ~p samples (expected 882)~n", [Count]);
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
    {PCM, #beeper{level = Level, init_level = Level, phase = FinalPhase}}.

-spec silence_frame() -> binary().
silence_frame() ->
    <<0:(?SAMPLES_PER_FRAME * 16)/signed-little>>.

%% --- Internal ---

%% gen_samples(ChangesSortedAsc, StartT, LevelAtStartT, Phase, Acc) -> {Samples, FinalPhase}
%% Iterates through changes, emitting samples for each interval at the
%% level that was active during that interval.
gen_samples([], StartT, Level, Phase, Acc) ->
    RemainingT = ?TSTATES_PER_FRAME_AUDIO - StartT,
    emit_samples(Acc, Level, RemainingT, Phase);
gen_samples([{T, NewLevel} | Rest], StartT, Level, Phase, Acc) ->
    DeltaT = T - StartT,
    {Acc1, Phase1} = emit_samples(Acc, Level, DeltaT, Phase),
    gen_samples(Rest, T, NewLevel, Phase1, Acc1).

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
