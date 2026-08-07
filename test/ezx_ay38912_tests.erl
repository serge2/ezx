-module(ezx_ay38912_tests).

-include_lib("eunit/include/eunit.hrl").

-define(MODULES, [ezx_ay38912, ezx_ay38912_seg]).

%% ---------------------------------------------------------------------------
%% Timing model under test:
%%   - tone:    (reg + 1) * 16 CPU T-states per half square-wave period
%%   - noise:   reg * 32 CPU T-states per LFSR step      (0 treated as 1)
%%   - envelope (AY):  reg * 32 CPU T-states per level step, 4-bit counter
%%     (16 levels)
%%   - envelope (YM):  reg * 16 CPU T-states per level step, 5-bit counter
%%     (32 levels); twice the AY's step rate, same sweep duration
%% Mixing formula: (ToneOn | ToneDisable) & (NoiseOn | NoiseDisable).
%% ---------------------------------------------------------------------------

%% ---- helpers ----

setup(M, Writes) ->
    setup(M, ay, Writes).

setup(M, Chip, Writes) ->
    lists:foldl(fun({Reg, Val}, AY) ->
        M:write(M:latch(AY, Reg), Val, 0)
    end, M:new(Chip), Writes).

%% Render one frame of TStates T-states into one sample per T-state;
%% return channel A samples as a list.
render_ch_a(M, AY, TStates) ->
    AY1 = M:frame_start(AY, 0),
    {ChA, _, _, _} = M:render_channels(AY1, TStates, TStates),
    [V || <<V:16/little-signed>> <= ChA].

%% Expected PCM for a 4-bit level, mirroring the modules' exponential AY DAC
%% curve (level 15 -> +4096, level 0 -> -4096).  The AY DAC is logarithmic
%% (3 dB per level), so levels are NOT equally spaced.
pcm(Level) ->
    element(Level + 1, {0, 64, 90, 128, 181, 256, 362, 512, 724, 1024, 1448,
                        2048, 2896, 4096, 5793, 8192}) - 4096.

%% Expected PCM for a YM2149 DAC level (0..31), mirroring the modules' YM
%% curve (the measured YM2149 DAC resistances on a 0..8192 scale).
pcm_ym(Level) ->
    element(Level + 1, {0, 16, 39, 71, 89, 111, 131, 153, 185, 221, 255, 293,
                        351, 418, 483, 556, 667, 798, 927, 1073, 1288, 1541,
                        1788, 2068, 2501, 3004, 3512, 4079, 4982, 5989, 7067,
                        8192}) - 4096.

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
    %% R6 = 1 -> one LFSR step per 32 T-states.  Writing R6 resets the LFSR
    %% to 0x10000 (bit 0 = 0).  The AY noise generator is a 17-bit
    %% RIGHT-shifting LFSR (feedback = bit0 XOR bit3 inserted at bit 16,
    %% output = bit 0), so the single 1 at bit 16
    %% reaches bit 0 after exactly 16 steps = 512 T-states.  Over 882
    %% T-states the noise output stays 0 up to sample 511 and turns on at
    %% sample 512.
    Writes = [{7, 16#F7}, {6, 1}, {8, 16#0F}],
    [run_each(M, Writes,
        fun(Samples) ->
            ?assertEqual([pcm(0)], lists:usort(lists:sublist(Samples, 511))),
            ?assertEqual(pcm(15), lists:nth(512, Samples))
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

%% ---- YM2149: envelope counter is 5-bit and steps twice as fast ----

ym_envelope_step_rate_test_() ->
    %% Same write setup as envelope_step_rate_test_ (N = 14) but on the YM
    %% each level step takes 14 * 16 = 224 T-states: 31 -> 30 at sample 224,
    %% 30 -> 29 at sample 448, 29 -> 28 at sample 672.
    Writes = [{7, 16#FF}, {8, 16#10}, {11, 14}, {12, 0}, {13, 0}],
    [run_each_ym(M, Writes,
        fun(Samples) ->
            ?assertEqual(pcm_ym(31), hd(Samples)),
            ?assertEqual([pcm_ym(31)], lists:usort(lists:sublist(Samples, 223))),
            ?assertEqual(pcm_ym(30), lists:nth(224, Samples)),
            ?assertEqual(pcm_ym(29), lists:nth(448, Samples)),
            ?assertEqual(pcm_ym(28), lists:nth(672, Samples)),
            ?assertEqual([pcm_ym(28)], lists:usort(lists:sublist(Samples, 672, 211)))
        end) || M <- ?MODULES].

ym_envelope_32_levels_test_() ->
    %% N = 1 -> one level step per 16 T-states on the YM (32 steps within
    %% 882 T-states): the full 5-bit sweep 31..0 then hold at 0.  The AY
    %% (step = 32 T-states) only sweeps its 16 levels.
    Writes = [{7, 16#FF}, {8, 16#10}, {11, 1}, {12, 0}, {13, 0}],
    YmAssert = fun(Samples) -> ?assertEqual(32, length(lists:usort(Samples))) end,
    AyAssert = fun(Samples) -> ?assertEqual(16, length(lists:usort(Samples))) end,
    [run_each_ym(M, Writes, YmAssert) || M <- ?MODULES] ++
    [run_each(M, Writes, AyAssert) || M <- ?MODULES].

ym_fixed_volume_even_taps_test_() ->
    %% On the YM the 4-bit fixed volume drives the 5-bit DAC at the even
    %% taps (volume V -> level 2V), so volume 3 -> level 6.  The AY uses its
    %% own 16-level curve.
    Writes = [{7, 16#FF}, {8, 3}],
    YmAssert = fun(Samples) -> ?assertEqual([pcm_ym(6)], lists:usort(Samples)) end,
    AyAssert = fun(Samples) -> ?assertEqual([pcm(3)], lists:usort(Samples)) end,
    [run_each_ym(M, Writes, YmAssert) || M <- ?MODULES] ++
    [run_each(M, Writes, AyAssert) || M <- ?MODULES].

%% ---- AY-vs-YM chip detection: unused bits read back differently ----

chip_detect_readback_test_() ->
    %% Detection trick: write 31 to the 4-bit coarse tone register 1 and
    %% read it back.  The AY-3-8912 zeroes the unused upper bits (reads 15);
    %% the YM2149 returns every bit as written (reads 31).  The same applies
    %% to the other partial-width registers (R6 noise = 5 bits, R13 envelope
    %% shape = 4 bits).
    [run_readback(M, ay, 1, 16#1F, 16#0F) || M <- ?MODULES] ++
    [run_readback(M, ym, 1, 16#1F, 16#1F) || M <- ?MODULES] ++
    [run_readback(M, ay, 6, 16#FF, 16#1F) || M <- ?MODULES] ++
    [run_readback(M, ym, 6, 16#FF, 16#FF) || M <- ?MODULES] ++
    [run_readback(M, ay, 13, 16#FF, 16#0F) || M <- ?MODULES] ++
    [run_readback(M, ym, 13, 16#FF, 16#FF) || M <- ?MODULES].

run_readback(M, Chip, Reg, WriteVal, Expected) ->
    fun() ->
        AY = M:write(M:latch(M:new(Chip), Reg), WriteVal, 0),
        ?assertEqual(Expected, M:read(AY))
    end.

%% ---- AY-vs-YM chip detection: latch with upper nibble set (Action intro) ----
%%
%% Action latches 0x10 and reads back: the YM2149 checks the programmed
%% code DA7-DA4 (must be 0000) and drives the bus high-impedance on a
%% mismatch, so the read returns 0xFF; the AY-3-8912 selects the register by
%% the low nibble only and reads back the previously written register 0
%% value (0x40).  The chip stays deactivated until the next valid latch, and
%% data writes while deactivated are ignored.

chip_detect_latch_upper_nibble_test_() ->
    [fun() ->
        AY = M:write(M:latch(M:new(ay), 0), 16#40, 0),
        AY1 = M:latch(AY, 16#10),
        ?assertEqual(16#40, M:read(AY1))
     end || M <- ?MODULES] ++
    [fun() ->
        AY = M:write(M:latch(M:new(ym), 0), 16#40, 0),
        AY1 = M:latch(AY, 16#10),
        ?assertEqual(16#FF, M:read(AY1)),
        AY2 = M:write(AY1, 16#20, 0),
        ?assertEqual(16#FF, M:read(AY2)),
        AY3 = M:latch(AY2, 0),
        ?assertEqual(16#40, M:read(AY3))
     end || M <- ?MODULES].

%% ---- silent fast path (ezx_ay38912_seg only) ----
%%
%% A frame whose three volume registers (R8/R9/R10) stay at fixed-volume 0
%% is silent: every sample is level 0 (-4096) no matter how the tone/noise/
%% envelope generators run.  The segmented module renders such frames through
%% a fast path that skips the per-sample loop (one shared silence binary +
%% one bulk generator advance); ezx_ay38912 always renders, so it acts as a
%% cross-check on the PCM contract and the generator phase.

%% A freshly created chip (or a game that never touches the AY ports) with
%% generator registers configured but all volumes 0: constant -4096 on all
%% three channels, identical output from both modules.
silent_frame_is_constant_silence_test_() ->
    [fun() ->
        AY = gen_setup(M, ay, 0, 0, 0),
        AY1 = M:frame_start(AY, 0),
        {ChA, ChB, ChC, _} = M:render_channels(AY1, 882, 882),
        ?assertEqual([pcm(0)], lists:usort([V || <<V:16/little-signed>> <= ChA])),
        ?assertEqual([pcm(0)], lists:usort([V || <<V:16/little-signed>> <= ChB])),
        ?assertEqual([pcm(0)], lists:usort([V || <<V:16/little-signed>> <= ChC]))
     end || M <- ?MODULES] ++
    [fun() ->
        %% The YM2149 with all volumes 0 is silent too.
        AY = gen_setup(M, ym, 0, 0, 0),
        AY1 = M:frame_start(AY, 0),
        {ChA, _ChB, _ChC, _} = M:render_channels(AY1, 882, 882),
        ?assertEqual([pcm(0)], lists:usort([V || <<V:16/little-signed>> <= ChA]))
     end || M <- ?MODULES].

%% The fast path must actually be selected for silent frames and rejected
%% when ANY register is written mid-frame (a mid-frame change would make the
%% bulk generator advance differ from the per-sample one, e.g. an envelope
%% shape write resets the generator at its sample position).
silent_fast_path_selection_test_() ->
    M = ezx_ay38912_seg,
    fun() ->
        AY0 = gen_setup(M, ay, 0, 0, 0),
        AY1 = M:frame_start(AY0, 0),
        ?assert(M:silent_frame(AY1, [])),
        AY2 = M:write(M:latch(AY1, 8), 5, 100),
        ?assertNot(M:silent_frame(AY1, [{100, 8, 5}])),
        %% envelope-mode volume (bit 4) makes the channel audible too
        ?assertNot(M:silent_frame(AY1, [{100, 9, 16#10}])),
        %% even a non-audible register (mixer) blocks the fast path
        ?assertNot(M:silent_frame(AY1, [{100, 7, 0}]))
    end.

%% A volume written to a nonzero value mid-frame takes the audio path:
%% silence up to the write, sound after it.
nonzero_volume_mid_frame_takes_audio_path_test_() ->
    M = ezx_ay38912_seg,
    fun() ->
        AY0 = gen_setup(M, ay, 0, 0, 0),
        AY1 = M:frame_start(AY0, 0),
        AY2 = M:write(M:latch(AY1, 8), 15, 441),
        {ChA, _ChB, _ChC, _} = M:render_channels(AY2, 882, 882),
        Samples = [V || <<V:16/little-signed>> <= ChA],
        ?assert(lists:all(fun(X) -> X =:= pcm(0) end, lists:sublist(Samples, 441))),
        ?assert(lists:any(fun(X) -> X =/= pcm(0) end, lists:nthtail(441, Samples)))
    end.

%% The fast path advances the generators by FrameLen in one step instead of
%% per-sample.  A silent frame followed by an audible frame must land on the
%% exact same generator phase as the always-naive simplified module: play
%% both frames through each module and compare the combined PCM.
silent_fast_path_keeps_generator_phase_test_() ->
    fun() ->
        SegOut = silent_then_audible(ezx_ay38912_seg),
        SimpOut = silent_then_audible(ezx_ay38912),
        ?assertEqual(SimpOut, SegOut)
    end.

silent_then_audible(M) ->
    AY0 = gen_setup(M, ay, 0, 0, 0),
    {S1, M1} = render_frame(M, AY0),
    AY1 = lists:foldl(fun({R, V}, A) -> M:write(M:latch(A, R), V, 0) end,
                      M1, [{8, 15}]),
    {S2, _M2} = render_frame(M, AY1),
    S1 ++ S2.

render_frame(M, AY) ->
    AY1 = M:frame_start(AY, 0),
    {ChA, _, _, M2} = M:render_channels(AY1, 882, 882),
    {[V || <<V:16/little-signed>> <= ChA], M2}.

%% Configure the tone/noise/envelope generators and set the three volumes.
gen_setup(M, Chip, VolA, VolB, VolC) ->
    Gen = [{0, 0}, {1, 0}, {6, 1}, {11, 14}, {12, 0}, {13, 16#08}, {7, 0}],
    lists:foldl(fun({R, V}, A) ->
        M:write(M:latch(A, R), V, 0)
    end, M:new(Chip), Gen ++ [{8, VolA}, {9, VolB}, {10, VolC}]).

%% Run one render (882 T-states) and apply the per-module assertions.
run_each(M, Writes, Assert) ->
    fun() ->
        Samples = render_ch_a(M, setup(M, Writes), 882),
        Assert(Samples)
    end.

%% Same but on the YM2149 variant.
run_each_ym(M, Writes, Assert) ->
    fun() ->
        Samples = render_ch_a(M, setup(M, ym, Writes), 882),
        Assert(Samples)
    end.
