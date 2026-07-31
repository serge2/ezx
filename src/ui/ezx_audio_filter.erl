-module(ezx_audio_filter).

%% Speaker/RC-circuit low-pass + DC-blocking high-pass filters for PCM audio,
%% applied in the UI audio path (outside the emulator state machine).
%% Standalone so it can filter any mono S16LE PCM stream (currently the beeper
%% output; later the mixed beeper+AY stream).

-define(LPF_ALPHA, 0.090).  %% ~700 Hz low-pass (speaker/RC-circuit inertia)
-define(HPF_ALPHA, 0.9887). %% ~80 Hz high-pass (DC / overshoot blocking)

-export([new/0, filter/2]).

-record(audio_filter, {
    lpf_val = -8192.0 :: float(),
    hp_xprev = 0.0    :: float(),
    hp_yprev = 0.0    :: float()
}).

-type state() :: #audio_filter{}.
-export_type([state/0]).

-spec new() -> state().
new() -> #audio_filter{}.

%% @doc Apply LPF then HPF to one frame of mono S16LE PCM.
-spec filter(binary(), state()) -> {binary(), state()}.
filter(PCM, #audio_filter{lpf_val = LpfVal, hp_xprev = HpXprev, hp_yprev = HpYprev}) ->
    Samples = [S || <<S:16/signed-little>> <= PCM],
    {Filtered, NewLpfVal} = apply_lpf(Samples, LpfVal),
    {HpSamples, NewHpXprev, NewHpYprev} = apply_hpf(Filtered, HpXprev, HpYprev),
    {list_to_binary([<<S:16/signed-little>> || S <- HpSamples]),
     #audio_filter{lpf_val = NewLpfVal, hp_xprev = NewHpXprev, hp_yprev = NewHpYprev}}.

%% --- Internal ---

%% First-order IIR low-pass: y[n] = y[n-1] + a * (x[n] - y[n-1])
apply_lpf(Samples, InitialLpfVal) ->
    apply_lpf_loop(Samples, InitialLpfVal, []).

apply_lpf_loop([], LastVal, Acc) ->
    {lists:reverse(Acc), LastVal};
apply_lpf_loop([Sample | Rest], PrevVal, Acc) ->
    NewVal = PrevVal + ?LPF_ALPHA * (Sample - PrevVal),
    IntVal = erlang:round(NewVal),
    apply_lpf_loop(Rest, NewVal, [IntVal | Acc]).

%% First-order IIR high-pass: y[n] = a * (y[n-1] + x[n] - x[n-1])
apply_hpf(Samples, Xprev, Yprev) ->
    apply_hpf_loop(Samples, Xprev, Yprev, []).

apply_hpf_loop([], Xprev, Yprev, Acc) ->
    {lists:reverse(Acc), float(Xprev), float(Yprev)};
apply_hpf_loop([X | Rest], Xprev, Yprev, Acc) ->
    Y = ?HPF_ALPHA * (Yprev + X - Xprev),
    IntY = erlang:round(Y),
    apply_hpf_loop(Rest, X, Y, [IntY | Acc]).
