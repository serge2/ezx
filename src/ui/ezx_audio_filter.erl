-module(ezx_audio_filter).

%% First-order IIR speaker low-pass + DC-blocking high-pass filters for PCM
%% audio, applied in the UI audio path (outside the emulator state machine).
%% Generic on purpose: the cutoffs are passed in the config, the module knows
%% nothing about what signal it filters and hardcodes no coefficients.  It is
%% mono — one #state{} per audio channel, the caller (UI) keeps a state for
%% each of its output channels and calls filter/2 once per channel.
%%
%% new/1 takes a map with the named cutoffs `lpf' and `hpf' (alpha
%% coefficients; the cutoff-to-alpha mapping is the caller's business).  A
%% missing key means that stage is off, so `#{}' is a pure passthrough.  The
%% filter has no memory of a signal's rest level: state starts at zero.

-export([new/1, filter/2]).

-record(state, {
    lpf = undefined :: float() | undefined,  %% low-pass alpha; undefined = off
    hpf = undefined :: float() | undefined,  %% high-pass alpha; undefined = off
    lpf_val = 0.0    :: float(),
    hp_xprev = 0.0   :: float(),
    hp_yprev = 0.0   :: float()
}).

-type state() :: #state{}.
-export_type([state/0]).

-type cfg() :: #{lpf => float(), hpf => float()}.
-export_type([cfg/0]).

-spec new(cfg()) -> state().
new(Cfg) ->
    #state{lpf = maps:get(lpf, Cfg, undefined),
           hpf = maps:get(hpf, Cfg, undefined)}.

%% @doc Filter one frame of mono S16LE PCM.  Stages with an `undefined' cutoff
%% in the state are skipped.
-spec filter(binary(), state()) -> {binary(), state()}.
filter(PCM, #state{lpf = Lpf, hpf = Hpf, lpf_val = LpfVal,
                   hp_xprev = HpXprev, hp_yprev = HpYprev} = St) ->
    Samples = [S || <<S:16/signed-little>> <= PCM],
    {Samples1, LpfVal1} = lpf_stage(Samples, Lpf, LpfVal),
    {Samples2, HpXprev1, HpYprev1} = hpf_stage(Samples1, Hpf, HpXprev, HpYprev),
    {list_to_binary([<<S:16/signed-little>> || S <- Samples2]),
     St#state{lpf_val = LpfVal1, hp_xprev = HpXprev1, hp_yprev = HpYprev1}}.

lpf_stage(Samples, undefined, LpfVal) -> {Samples, LpfVal};
lpf_stage(Samples, Alpha, LpfVal) -> apply_lpf(Samples, LpfVal, Alpha).

hpf_stage(Samples, undefined, Xp, Yp) -> {Samples, Xp, Yp};
hpf_stage(Samples, Alpha, Xp, Yp) -> apply_hpf(Samples, Xp, Yp, Alpha).

%% --- Stages ---

%% First-order IIR low-pass: y[n] = y[n-1] + a * (x[n] - y[n-1])
apply_lpf(Samples, InitialLpfVal, Alpha) ->
    apply_lpf_loop(Samples, InitialLpfVal, Alpha, []).

apply_lpf_loop([], LastVal, _Alpha, Acc) ->
    {lists:reverse(Acc), LastVal};
apply_lpf_loop([Sample | Rest], PrevVal, Alpha, Acc) ->
    NewVal = PrevVal + Alpha * (Sample - PrevVal),
    apply_lpf_loop(Rest, NewVal, Alpha, [erlang:round(NewVal) | Acc]).

%% First-order IIR high-pass: y[n] = a * (y[n-1] + x[n] - x[n-1])
apply_hpf(Samples, Xprev, Yprev, Alpha) ->
    apply_hpf_loop(Samples, Xprev, Yprev, Alpha, []).

apply_hpf_loop([], Xprev, Yprev, _Alpha, Acc) ->
    {lists:reverse(Acc), float(Xprev), float(Yprev)};
apply_hpf_loop([X | Rest], Xprev, Yprev, Alpha, Acc) ->
    Y = Alpha * (Yprev + X - Xprev),
    apply_hpf_loop(Rest, X, Y, Alpha, [erlang:round(Y) | Acc]).
