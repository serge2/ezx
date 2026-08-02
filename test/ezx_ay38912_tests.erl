-module(ezx_ay38912_tests).

-include_lib("eunit/include/eunit.hrl").

-define(MODULES, [ezx_ay38912, ezx_ay38912_seg]).

%% ---------------------------------------------------------------------------
%% Timing model under test (matches Fuse sound.c and MAME ay8910.cpp):
%%   - tone:    (reg + 1) * 16 CPU T-states per half square-wave period
%%   - noise:   reg * 32 CPU T-states per LFSR step      (0 treated as 1)
%%   - envelope: reg * 32 CPU T-states per level step    (0 treated as 1)
%% Mixing formula (MAME): (ToneOn | ToneDisable) & (NoiseOn | NoiseDisable).
%% ---------------------------------------------------------------------------

%% ---- helpers ----

setup(M, Writes) ->
    lists:foldl(fun({Reg, Val}, AY) ->
        M:write(M:latch(AY, Reg), Val, 0)
    end, M:new(), Writes).

%% Render one frame of TStates T-states; return channel A samples as a list.
render_ch_a(M, AY, TStates) ->
    AY1 = M:frame_start(AY, 0),
    {ChA, _, _, _} = M:render_channels(AY1, TStates),
    [V || <<V:16/little-signed>> <= ChA].

pcm(Level) ->
    (Level * 8192) div 15 - 4096.

%% ---- envelope step rate: reg * 32 T-states per level step ----

envelope_step_rate_test_() ->
    %% shape 0x00 = single 15->0 decay; N = 14 -> one level step per 448
    %% T-states.  Over 882 T-states the envelope steps exactly once (15->14)
    %% at T-state 448, i.e. at sample index 447.
    Writes = [{7, 16#FF}, {8, 16#10}, {11, 14}, {12, 0}, {13, 0}],
    [run_each(M, Writes,
        fun(Samples) ->
            ?assertEqual(pcm(15), hd(Samples)),
            ?assertEqual([pcm(15)], lists:usort(lists:sublist(Samples, 447))),
            ?assertEqual(pcm(14), lists:nth(448, Samples)),
            ?assertEqual([pcm(14)], lists:usort(lists:sublist(Samples, 448, 435)))
        end) || M <- ?MODULES].

%% ---- noise LFSR step rate: reg * 32 T-states per step ----

noise_step_rate_test_() ->
    %% R6 = 14 -> one LFSR step per 448 T-states.  Writing R6 resets the LFSR
    %% to 0x10000 (bit 0 = 0); one step yields bit 0 = 1.  Over 882 T-states
    %% the LFSR steps exactly once, at sample index 447.
    Writes = [{7, 16#F7}, {6, 14}, {8, 16#0F}],
    [run_each(M, Writes,
        fun(Samples) ->
            ?assertEqual([pcm(0)], lists:usort(lists:sublist(Samples, 447))),
            ?assertEqual(pcm(15), lists:nth(448, Samples)),
            ?assertEqual([pcm(15)], lists:usort(lists:sublist(Samples, 448, 435)))
        end) || M <- ?MODULES].

%% ---- tone half period: (reg + 1) * 16 T-states ----

tone_half_period_test_() ->
    %% Tone register 0 -> half period 16 T-states: square wave 1/0 every 16
    %% samples starting high.
    Writes = [{7, 16#3E}, {0, 0}, {1, 0}, {8, 16#0F}],
    [run_each(M, Writes,
        fun(Samples) ->
            ?assertEqual(pcm(15), lists:nth(1, Samples)),
            ?assertEqual(pcm(0), lists:nth(17, Samples)),
            ?assertEqual(pcm(15), lists:nth(33, Samples)),
            ?assertEqual(pcm(0), lists:nth(49, Samples))
        end) || M <- ?MODULES].

%% ---- mixer AND quirk: tone+noise both disabled -> level passes through ----

mixer_both_disabled_passes_level_test_() ->
    Writes = [{7, 16#FF}, {8, 7}],
    [run_each(M, Writes,
        fun(Samples) ->
            ?assertEqual([pcm(7)], lists:usort(Samples))
        end) || M <- ?MODULES].

%% ---- mixer AND: tone+noise both enabled -> output is the AND ----

mixer_tone_and_noise_are_anded_test_() ->
    %% Tone register 0 gives a half period of 16 T-states (tone high for the
    %% first 16 samples of each 32-sample cycle).  Noise is enabled with a
    %% period of 31*32 = 992 T-states (never steps within 64 T-states), so
    %% the noise bit stays at the post-reset value 0.  Channel output =
    %% tone & noise = 0 throughout, i.e. the noise gates the tone off.
    Writes = [{7, 16#F6}, {0, 0}, {1, 0}, {6, 31}, {8, 16#0F}],
    [run_each(M, Writes,
        fun(Samples) ->
            ?assertEqual([pcm(0)], lists:usort(Samples))
        end) || M <- ?MODULES].

%% Run one render (882 T-states) and apply the per-module assertions.
run_each(M, Writes, Assert) ->
    fun() ->
        Samples = render_ch_a(M, setup(M, Writes), 882),
        Assert(Samples)
    end.
