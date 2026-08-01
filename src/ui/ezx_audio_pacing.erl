-module(ezx_audio_pacing).

%% Audio buffer pacing for the UI audio sink (aplay).
%% Tracks how many bytes were handed to the sink versus how many the sink
%% consumed in real time, and derives how long to wait before feeding the
%% next frame. Keeps a target surplus of frames in the sink so it does not
%% underrun across GC pauses and delivery jitter.
%% Shared by the running frame loop and the paused loop (which feeds silence),
%% so pause keeps the same pacing and never starves the sink.
%% Pure state machine: no ports, no side effects - unit-testable headlessly.

-define(AUDIO_RATE, 176400).  %% bytes/sec: 44100 Hz * 2 channels * 2 bytes
-define(SURPLUS_FRAMES, 3).

-export([new/1, advance/3, bytes/1]).
-export_type([state/0]).

-record(pacing, {
    frame_bytes :: pos_integer(),
    start_us = 0 :: non_neg_integer(),
    bytes = 0 :: non_neg_integer(),
    clock_set = false :: boolean()
}).

-type state() :: #pacing{}.

%% @doc Create pacing for a sink that is fed one audio frame at a time.
-spec new(pos_integer()) -> state().
new(FrameBytes) ->
    #pacing{frame_bytes = FrameBytes}.

%% @doc Called right after Bytes bytes were handed to the sink at time NowUs
%% (monotonic microseconds). Returns how long (ms) to wait before feeding the
%% next frame, plus the updated pacing state.
-spec advance(state(), non_neg_integer(), non_neg_integer()) -> {non_neg_integer(), state()}.
advance(#pacing{frame_bytes = FB} = P, Bytes, NowUs) ->
    {Written, StartUs} =
        case P#pacing.clock_set of
            false -> {Bytes, NowUs};
            true  -> {P#pacing.bytes + Bytes, P#pacing.start_us}
        end,
    BytesConsumed = (NowUs - StartUs) * ?AUDIO_RATE div 1000000,
    BufferLevel = Written - BytesConsumed,

    %% A long gap (dialog, snapshot load, machine switch) makes the estimate
    %% stale: reset the clock to now.
    case BufferLevel < -(FB * 2) of
        true ->
            {0, #pacing{frame_bytes = FB, start_us = NowUs,
                        bytes = Bytes, clock_set = true}};
        false ->
            Surplus = BufferLevel - (FB * ?SURPLUS_FRAMES),
            DelayMs = case Surplus > 0 of
                true  -> max(1, Surplus * 1000 div ?AUDIO_RATE);
                false -> 0
            end,
            {DelayMs, #pacing{frame_bytes = FB, start_us = StartUs,
                              bytes = Written, clock_set = true}}
    end.

%% @doc Bytes accounted as handed to the sink so far (test/debug helper).
-spec bytes(state()) -> non_neg_integer().
bytes(#pacing{bytes = B}) -> B.
