-module(ezx_beeper2).

%% ZX Spectrum 1-bit beeper emulation.
%% Uses a changes-list approach: port writes only append {TState, Level}
%% changes. Sample generation happens once per frame in flush_frame.
%% Produces raw duty-cycle-integrated samples.

-define(CPU_FREQ, 3500000).
-define(SAMPLE_RATE, 44100).
-define(TSTATES_PER_FRAME_AUDIO, 70000).
-define(SAMPLES_PER_FRAME, 882).

-define(AMP_OFF, -8192).
-define(AMP_ON,   8192).

%% Fixed-point scaling: 1 T-state = ?SCALE units.
-define(SCALE, 882).
-define(PERIOD_LEN, 70000).  %% One sample period in scaled units: 70000/882 * 882

-export([init/0, init/1, set_level/3, level/1, flush_frame/1, silence_frame/0]).

-record(beeper, {
    level = 0          :: 0 | 1,
    init_level = 0     :: 0 | 1,
    changes = []       :: [{non_neg_integer(), 0 | 1}]
}).

-type state() :: #beeper{}.
-export_type([state/0]).

-spec init() -> state().
init() ->
    #beeper{}.

%% @doc Init with a known level (used after flush to carry level across frames).
-spec init(0 | 1) -> state().
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
flush_frame(#beeper{level = Level, init_level = InitLevel, changes = Changes}) ->
    Sorted = lists:reverse(Changes),
    Samples = gen_integrated(Sorted, 0, InitLevel, 0, 0, []),

    Count = length(Samples),
    PCM = case Count of
        ?SAMPLES_PER_FRAME ->
            list_to_binary([<<S:16/signed-little>> || S <- Samples]);
        _ when Count < ?SAMPLES_PER_FRAME ->
            PadAmp = case Level of 0 -> ?AMP_OFF; 1 -> ?AMP_ON end,
            Pad = lists:duplicate(?SAMPLES_PER_FRAME - Count, PadAmp),
            list_to_binary([<<S:16/signed-little>> || S <- Samples ++ Pad]);
        _ ->
            Trimmed = lists:sublist(Samples, ?SAMPLES_PER_FRAME),
            list_to_binary([<<S:16/signed-little>> || S <- Trimmed])
    end,

    {PCM, #beeper{level = Level, init_level = Level}}.

-spec silence_frame() -> binary().
silence_frame() ->
    <<0:(?SAMPLES_PER_FRAME * 16)/signed-little>>.

%% --- Internal ---

%% gen_integrated(ChangesSorted, TPos, Level, SampleIdx, Integral, Acc) -> Samples
%% Multi-bit integration: for each sample period, outputs a sample proportional
%% to the duty cycle (fraction of time at level 1 vs level 0).
gen_integrated([], _TPos, _Level, ?SAMPLES_PER_FRAME, _Integral, Acc) ->
    lists:reverse(Acc);
gen_integrated([], TPos, Level, SampleIdx, Integral, Acc) ->
    PeriodEnd = (SampleIdx + 1) * ?PERIOD_LEN,
    Fill = PeriodEnd - TPos,
    NewIntegral = Integral + sign(Level, Fill),
    Sample = (NewIntegral * ?AMP_ON) div ?PERIOD_LEN,
    gen_integrated([], PeriodEnd, Level, SampleIdx + 1, 0, [Sample | Acc]);
gen_integrated([{T, NewLevel} | Rest], TPos, Level, SampleIdx, Integral, Acc) ->
    PeriodEnd = (SampleIdx + 1) * ?PERIOD_LEN,
    Tsc = T * ?SCALE,
    case Tsc < PeriodEnd of
        true ->
            Fill = Tsc - TPos,
            NewIntegral = Integral + sign(Level, Fill),
            gen_integrated(Rest, Tsc, NewLevel, SampleIdx, NewIntegral, Acc);
        false ->
            Fill = PeriodEnd - TPos,
            NewIntegral = Integral + sign(Level, Fill),
            Sample = (NewIntegral * ?AMP_ON) div ?PERIOD_LEN,
            gen_integrated([{T, NewLevel} | Rest], PeriodEnd, Level, SampleIdx + 1, 0, [Sample | Acc])
    end.

sign(0, Fill) -> -Fill;
sign(1, Fill) -> Fill.
