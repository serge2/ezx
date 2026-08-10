-module(ezx_beeper2).

%% ZX Spectrum 1-bit beeper emulation.
%% Uses a changes-list approach: port writes only append {TState, Level}
%% changes. Sample generation happens once per frame in frame_render/3.
%% Produces raw duty-cycle-integrated samples.
%%
%% Frame contract (shared with the other devices, physical-overrun model):
%%   frame_start(Beeper, StartTState)   — begin a frame; events recorded
%%                                        below carry absolute counter stamps
%%                                        (machine t_states, 0 = nominal frame
%%                                        boundary)
%%   set_level(Beeper, Level, TState)   — record a level change
%%   frame_render(Beeper, FrameLen, Samples) — render exactly FrameLen
%%                                        T-states into Samples mono S16LE
%%                                        samples; events with counter < FrameLen
%%                                        belong to this frame (local time =
%%                                        counter), events with counter >=
%%                                        FrameLen belong to the NEXT frame and
%%                                        are carried over — rebased by
%%                                        -FrameLen into the next frame's
%%                                        counter domain — never dropped. The
%%                                        carried tail plus #beeper.init_level
%%                                        (the level at the nominal boundary)
%%                                        start the next frame exactly where the
%%                                        ULA timeline puts them.

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
%% live level across frames, and by snapshot load). frame_start/2 keeps
%% init_level; frame_render/3 advances it to the level at the nominal
%% frame boundary.
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

%% @doc Mark the start of a new frame. In the physical-overrun model the
%% previous frame_render/3 already carried the tail events over (rebased into
%% this frame's counter domain) and set init_level to the level at the nominal
%% boundary, so there is nothing to reset: this frame simply keeps recording
%% level changes with absolute counter stamps. StartTState is recorded for
%% reference only.
-spec frame_start(state(), non_neg_integer()) -> state().
frame_start(#beeper{} = B, StartTState) ->
    B#beeper{frame_offset = StartTState}.

%% @doc Render one frame of audio: exactly FrameLen T-states (e.g. 69888 for
%% a 48K frame) into Samples mono S16LE samples.  Samples is derived by the
%% emulator from the machine model as trunc(FrameLen * SampleRate / CpuClock).
%% Events with counter < FrameLen belong to this frame (local time = counter)
%% and are rendered; events with counter >= FrameLen belong to the next frame
%% and are carried over in the returned state, rebased by -FrameLen into the
%% next frame's counter domain.  The returned init_level is the level at the
%% nominal frame boundary (after the last rendered change), which is the level
%% at local time 0 of the next frame.  The live level — which already reflects
%% the tail changes — stays in #beeper.level.
-spec frame_render(state(), non_neg_integer(), pos_integer()) -> {binary(), state()}.
frame_render(#beeper{level = Level, init_level = InitLevel, changes = Changes},
             FrameLen, Samples) ->
    Sorted = lists:reverse(Changes),
    Local = [{ET, L} || {ET, L} <- Sorted, ET < FrameLen],
    Tail = [{ET - FrameLen, L} || {ET, L} <- Sorted, ET >= FrameLen],
    SampleList = gen_integrated(Local, 0, InitLevel, 0, Samples, 0, FrameLen, []),
    PCM = list_to_binary([<<S:16/signed-little>> || S <- SampleList]),
    {PCM, #beeper{level = Level, init_level = level_after(Local, InitLevel), changes = Tail}}.

-spec silence_frame(pos_integer()) -> binary().
silence_frame(Samples) ->
    <<0:(Samples * 16)/signed-little>>.

%% --- Internal ---

%% The level at the end of the render window (the nominal frame boundary):
%% the last rendered change's level, or the initial level when nothing
%% changed in the window.  This is the level at local time 0 of the next frame.
level_after([], InitLevel) -> InitLevel;
level_after(Local, _InitLevel) -> element(2, lists:last(Local)).

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
