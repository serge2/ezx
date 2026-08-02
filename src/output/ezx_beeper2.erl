-module(ezx_beeper2).

%% ZX Spectrum 1-bit beeper emulation.
%% Uses a changes-list approach: port writes only append {TState, Level}
%% changes. Sample generation happens once per frame in frame_render/3.
%% Produces raw duty-cycle-integrated samples.
%%
%% Frame contract (shared with the other devices):
%%   frame_start(Beeper, StartTState)   — begin a frame; events recorded
%%                                        below carry absolute TState stamps
%%   set_level(Beeper, Level, TState)   — record a level change
%%   frame_render(Beeper, FrameLen, Samples) — render exactly FrameLen
%%                                        T-states into Samples mono S16LE
%%                                        samples; events in the frame-overrun
%%                                        zone (local TState >= FrameLen) are
%%                                        dropped from the audio but their
%%                                        side effect on the live level is
%%                                        kept for the next frame

-define(AMP_ON, 4096).

%% Fixed-point scaling: 1 T-state = Samples units, so one sample period is
%% exactly FrameLen units (the number of samples to emit is the scale).

-export([init/0, init/1, set_level/3, level/1, frame_start/2, frame_render/3, silence_frame/1]).

-record(beeper, {
    level = 0          :: 0 | 1,
    init_level = 0     :: 0 | 1,
    frame_offset = 0   :: non_neg_integer(),
    changes = []       :: [{non_neg_integer(), 0 | 1}]
}).

-type state() :: #beeper{}.
-export_type([state/0]).

-spec init() -> state().
init() ->
    #beeper{}.

%% @doc Init with a known level (used after frame_render to carry the
%% live level across frames; frame_start/2 also snapshots it).
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

%% @doc Mark the start of a new frame. Rebases the event timeline to
%% StartTState: events recorded later carry absolute TState stamps and
%% frame_render/3 converts them to local frame time by subtracting it.
-spec frame_start(state(), non_neg_integer()) -> state().
frame_start(#beeper{level = Level} = B, StartTState) ->
    B#beeper{init_level = Level, frame_offset = StartTState, changes = []}.

%% @doc Render one frame of audio: exactly FrameLen T-states (e.g. 69888 for
%% a 48K frame) into Samples mono S16LE samples.  Samples is derived by the
%% emulator from the machine model as trunc(FrameLen * SampleRate / CpuClock).
%% Events in the frame-overrun zone (local time >= FrameLen) are dropped
%% from the audio; the live level (which already reflects them) is carried
%% into the next frame.
-spec frame_render(state(), non_neg_integer(), pos_integer()) -> {binary(), state()}.
frame_render(#beeper{level = Level, init_level = InitLevel, frame_offset = FO, changes = Changes},
             FrameLen, Samples) ->
    Sorted = lists:reverse(Changes),
    Local = [{ET - FO, L} || {ET, L} <- Sorted, ET >= FO, ET - FO < FrameLen],
    SampleList = gen_integrated(Local, 0, InitLevel, 0, Samples, 0, FrameLen, []),
    PCM = list_to_binary([<<S:16/signed-little>> || S <- SampleList]),
    {PCM, #beeper{level = Level, init_level = Level}}.

-spec silence_frame(pos_integer()) -> binary().
silence_frame(Samples) ->
    <<0:(Samples * 16)/signed-little>>.

%% --- Internal ---

%% gen_integrated(ChangesSorted, TPos, Level, SampleIdx, Samples, Integral,
%%                PeriodLen, Acc) -> Samples
%% Multi-bit integration: for each sample period, outputs a sample proportional
%% to the duty cycle (fraction of time at level 1 vs level 0).
gen_integrated([], _TPos, _Level, Samples, Samples, _Integral, _PeriodLen, Acc) ->
    lists:reverse(Acc);
gen_integrated([], TPos, Level, SampleIdx, Samples, Integral, PeriodLen, Acc) ->
    PeriodEnd = (SampleIdx + 1) * PeriodLen,
    Fill = PeriodEnd - TPos,
    NewIntegral = Integral + sign(Level, Fill),
    Sample = (NewIntegral * ?AMP_ON) div PeriodLen,
    gen_integrated([], PeriodEnd, Level, SampleIdx + 1, Samples, 0, PeriodLen, [Sample | Acc]);
gen_integrated([{T, NewLevel} | Rest], TPos, Level, SampleIdx, Samples, Integral, PeriodLen, Acc) ->
    PeriodEnd = (SampleIdx + 1) * PeriodLen,
    Tsc = T * Samples,
    case Tsc < PeriodEnd of
        true ->
            Fill = Tsc - TPos,
            NewIntegral = Integral + sign(Level, Fill),
            gen_integrated(Rest, Tsc, NewLevel, SampleIdx, Samples, NewIntegral, PeriodLen, Acc);
        false ->
            Fill = PeriodEnd - TPos,
            NewIntegral = Integral + sign(Level, Fill),
            Sample = (NewIntegral * ?AMP_ON) div PeriodLen,
            gen_integrated([{T, NewLevel} | Rest], PeriodEnd, Level, SampleIdx + 1, Samples, 0, PeriodLen, [Sample | Acc])
    end.

sign(0, Fill) -> -Fill;
sign(1, Fill) -> Fill.
