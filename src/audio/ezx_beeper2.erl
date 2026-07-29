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

%% Fixed-point scaling: 1 T-state = ?SCALE units.
-define(SCALE, 882).
-define(PERIOD_LEN, 70000).  %% One sample period in scaled units: 70000/882 * 882

%% Alpha controls cutoff frequency (~5000 Hz cutoff at 44100Hz samplerate)
%% Formula: Alpha = (2 * pi * Fc) / (2 * pi * Fc + Fs)
%-define(LPF_ALPHA, 0.550). % ~8 KHz
%-define(LPF_ALPHA, 0.415). % ~5 KHz
%-define(LPF_ALPHA, 0.250). % ~2.5 KHz
-define(LPF_ALPHA, 0.090).  % ~700 Hz

%% First-order IIR High-Pass Filter (~80 Hz cutoff at 44100 Hz)
%% y[n] = a * (y[n-1] + x[n] - x[n-1]),  a = exp(-2*pi*fc/Fs)
-define(HPF_ALPHA, 0.9887).

-export([init/0, init/1, set_level/3, level/1, set_offset/2, flush_frame/1, silence_frame/0]).

-record(beeper, {
    level = 0          :: 0 | 1,
    init_level = 0     :: 0 | 1,
    phase = 0          :: non_neg_integer(),
    offset = 0         :: non_neg_integer(),
    changes = []       :: [{non_neg_integer(), 0 | 1}],
    lpf_val = -8192.0  :: float(),  %% Smooth state transition across frame boundaries
    hp_xprev = 0.0    :: float(),
    hp_yprev = 0.0    :: float()
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

-spec set_offset(state(), non_neg_integer()) -> state().
set_offset(#beeper{} = B, Offset) ->
    B#beeper{offset = Offset}.

-spec flush_frame(state()) -> {binary(), state()}.
flush_frame(#beeper{level = Level, init_level = InitLevel, phase = _Phase, offset = Offset,
                    changes = Changes, lpf_val = LpfVal,
                    hp_xprev = HpXprev, hp_yprev = HpYprev}) ->
    Sorted = lists:reverse(Changes),
    {RawRevSamples, FinalPhase} = gen_integrated(Sorted, Offset * ?SCALE, InitLevel, 0, 0, []),
    
    %% Apply LPF filtering to smooth raw rectangular pulses.
    %% FilteredSamples is returned in chronological order.
    {FilteredSamples, NewLpfVal} = apply_lpf(RawRevSamples, LpfVal),

    %% Apply HPF to remove low-frequency noise from Overshoot modulation.
    {HpSamples, NewHpXprev, NewHpYprev} = apply_hpf(FilteredSamples, HpXprev, HpYprev),

    Count = length(HpSamples),
    case Count =/= ?SAMPLES_PER_FRAME of
        true -> io:format("BEEPER: ~p samples (expected 882)~n", [Count]);
        false -> ok
    end,

    PCM = case Count of
        ?SAMPLES_PER_FRAME ->
            list_to_binary([<<S:16/signed-little>> || S <- HpSamples]);
        _ when Count < ?SAMPLES_PER_FRAME ->
            PadAmp = case Level of 0 -> ?AMP_OFF; 1 -> ?AMP_ON end,
            Pad = lists:duplicate(?SAMPLES_PER_FRAME - Count, PadAmp),
            list_to_binary([<<S:16/signed-little>> || S <- HpSamples ++ Pad]);
        _ ->
            Trimmed = lists:sublist(HpSamples, ?SAMPLES_PER_FRAME),
            list_to_binary([<<S:16/signed-little>> || S <- Trimmed])
    end,

    {PCM, #beeper{level = Level, init_level = Level, phase = FinalPhase, offset = 0, lpf_val = NewLpfVal,
                  hp_xprev = NewHpXprev, hp_yprev = NewHpYprev}}.

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

%% gen_integrated(ChangesSorted, TPos, Level, SampleIdx, Integral, Acc) -> {Samples, FinalPhase}
%% Multi-bit integration: for each sample period, outputs a sample proportional
%% to the duty cycle (fraction of time at level 1 vs level 0).
gen_integrated([], _TPos, _Level, ?SAMPLES_PER_FRAME, _Integral, Acc) ->
    {Acc, 0};
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

%% --- High-Pass Filter ---
%% First-order IIR: y[n] = alpha * (y[n-1] + x[n] - x[n-1])
apply_hpf(Samples, Xprev, Yprev) ->
    apply_hpf_loop(Samples, Xprev, Yprev, []).

apply_hpf_loop([], Xprev, Yprev, Acc) ->
    {lists:reverse(Acc), float(Xprev), float(Yprev)};
apply_hpf_loop([X | Rest], Xprev, Yprev, Acc) ->
    Y = ?HPF_ALPHA * (Yprev + X - Xprev),
    IntY = erlang:round(Y),
    apply_hpf_loop(Rest, X, Y, [IntY | Acc]).
