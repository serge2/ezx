-module(ezx_beeper2).

%% ZX Spectrum 1-bit beeper emulation.
%% Uses a changes-list approach: port writes only append {TState, Level}
%% changes. Sample generation happens once per frame in flush_frame.
%% Includes a 1st-order IIR Low-Pass Filter (LPF) to smooth out square waves,
%% removing harsh digital aliasing and emulating speaker/RC-circuit inertia.

-define(CPU_FREQ, 3500000).
-define(SAMPLE_RATE, 44100).
-define(TSTATES_PER_FRAME_AUDIO, 70000).
-define(SAMPLES_PER_FRAME, 882).

-define(AMP_OFF, -8192).
-define(AMP_ON,   8192).

%% Alpha controls cutoff frequency (~5000 Hz cutoff at 44100Hz samplerate)
%% Formula: Alpha = (2 * pi * Fc) / (2 * pi * Fc + Fs)
%-define(LPF_ALPHA, 0.550). % ~8 KHz
-define(LPF_ALPHA, 0.415). % ~5 KHz
%-define(LPF_ALPHA, 0.250). % ~2.5 KHz

-export([init/0, init/1, set_level/3, level/1, flush_frame/1, silence_frame/0]).

-record(beeper, {
    level = 0          :: 0 | 1,
    init_level = 0     :: 0 | 1,
    phase = 0          :: non_neg_integer(),
    changes = []       :: [{non_neg_integer(), 0 | 1}],
    lpf_val = -8192.0  :: float()  %% Smooth state transition across frame boundaries
}).

-type state() :: #beeper{}.
-export_type([state/0]).

-spec init() -> state().
init() ->
    #beeper{}.

%% @doc Init with a known level (used after flush to carry level across frames).
-spec init(0 | 1) -> state().
init(Level) ->
    InitAmp = case Level of 0 -> ?AMP_OFF; 1 -> ?AMP_ON end,
    #beeper{level = Level, init_level = Level, lpf_val = float(InitAmp)}.

%% @doc Record a level change. Only appends to changes list if level differs.
-spec set_level(state(), 0 | 1, non_neg_integer()) -> state().
set_level(#beeper{level = Level} = B, NewLevel, _TState) when NewLevel =:= Level ->
    B;
set_level(#beeper{changes = Changes} = B, NewLevel, TState) ->
    B#beeper{level = NewLevel, changes = [{TState, NewLevel} | Changes]}.

-spec level(state()) -> 0 | 1.
level(#beeper{level = L}) -> L.

-spec flush_frame(state()) -> {binary(), state()}.
flush_frame(#beeper{level = Level, init_level = InitLevel, phase = Phase,
                    changes = Changes, lpf_val = LpfVal}) ->
    Sorted = lists:reverse(Changes),
    {RawRevSamples, FinalPhase} = gen_samples(Sorted, 0, InitLevel, Phase, []),
    
    %% Apply LPF filtering to smooth raw rectangular pulses.
    %% FilteredSamples is returned in chronological order.
    {FilteredSamples, NewLpfVal} = apply_lpf(RawRevSamples, LpfVal),

    Count = length(FilteredSamples),
    case Count =/= ?SAMPLES_PER_FRAME of
        true -> io:format("BEEPER: ~p samples (expected 882)~n", [Count]);
        false -> ok
    end,

    PCM = case Count of
        ?SAMPLES_PER_FRAME ->
            list_to_binary([<<S:16/signed-little>> || S <- FilteredSamples]);
        _ when Count < ?SAMPLES_PER_FRAME ->
            PadAmp = case Level of 0 -> ?AMP_OFF; 1 -> ?AMP_ON end,
            Pad = lists:duplicate(?SAMPLES_PER_FRAME - Count, PadAmp),
            list_to_binary([<<S:16/signed-little>> || S <- FilteredSamples ++ Pad]);
        _ ->
            Trimmed = lists:sublist(FilteredSamples, ?SAMPLES_PER_FRAME),
            list_to_binary([<<S:16/signed-little>> || S <- Trimmed])
    end,

    {PCM, #beeper{level = Level, init_level = Level, phase = FinalPhase, lpf_val = NewLpfVal}}.

-spec silence_frame() -> binary().
silence_frame() ->
    <<0:(?SAMPLES_PER_FRAME * 16)/signed-little>>.

%% --- Internal ---

%% Low-Pass Filter loop
%% Converts raw reversed samples list into filtered chronological list
apply_lpf(RawRevSamples, InitialLpfVal) ->
    apply_lpf_loop(lists:reverse(RawRevSamples), InitialLpfVal, []).

apply_lpf_loop([], LastVal, Acc) ->
    {lists:reverse(Acc), LastVal};
apply_lpf_loop([Sample | Rest], PrevVal, Acc) ->
    NewVal = PrevVal + ?LPF_ALPHA * (Sample - PrevVal),
    IntVal = erlang:round(NewVal),
    apply_lpf_loop(Rest, NewVal, [IntVal | Acc]).

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
