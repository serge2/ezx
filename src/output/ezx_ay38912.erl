-module(ezx_ay38912).

%% =============================================================================
%% AY-3-8912 / YM2149 programmable sound generator emulation.
%%
%% NOTE: This is a simplified implementation.  write/3 accepts a TState
%% argument for API compatibility but ignores it — register changes are
%% applied immediately and render_channels/2 divides the frame into 882
%% equally-sized steps without considering when writes actually occurred.
%% For correct mid-frame register-change timing use ezx_ay38912_seg.
%%
%% Three independent tone channels (A, B, C), each with:
%%   - a square-wave tone generator (12-bit period, register pair per channel)
%%   - a noise mixer (global 5-bit noise period, 17-bit LFSR: x^17 + x^14 + 1)
%%   - amplitude control: fixed 4-bit level or envelope follower (per channel)
%%
%% Shared global envelope generator with 16 shapes (R13 = %CAHx):
%%   C=CONT (0=freeze at end, 1=continue), A=ATT (0=start 15→0, 1=start 0→15)
%%   H=HOLD (0=loop, 1=freeze), ALT=alternate direction on loop
%%
%%   R13  shape  behaviour
%%   ──────────────────────────────────────────────────────────────────────
%%   0000  \___  single 15→0, freeze at 0
%%   0001  \___  (dup: Cont=0, Att=0 ⇒ \___ regardless of Alt/Hold)
%%   0010  \___  (dup: same)
%%   0011  \___  (dup: same)
%%   ──────────────────────────────────────────────────────────────────────
%%   0100  /‾‾‾  single 0→15, freeze at 15
%%   0101  /‾‾‾  (dup: Cont=0, Att=1 ⇒ /‾‾‾ regardless of Alt/Hold)
%%   0110  /‾‾‾  (dup: same)
%%   0111  /‾‾‾  (dup: same)
%%   ──────────────────────────────────────────────────────────────────────
%%   1000  \/\/  repeating sawtooth 15→0→15→0… (Alt=0: same direction)
%%   1001  \___  (dup: Cont=1, Att=0, Hold=1 ⇒ freeze)
%%   1010  \/\/\ repeating triangle 15↔0↔15…  (Alt=1: alternate)
%%   1011  \___  (dup: same as 1001 — Hold=1 freezes, Alt ignored)
%%   ──────────────────────────────────────────────────────────────────────
%%   1100  /\/\  repeating sawtooth 0→15→0→15… (Alt=0: same direction)
%%   1101  /‾‾‾  (dup: Cont=1, Att=1, Hold=1 ⇒ freeze)
%%   1110  /\/\/\ repeating triangle 0↔15↔0…  (Alt=1: alternate)
%%   1111  /‾‾‾  (dup: same as 1101 — Hold=1 freezes, Alt ignored)
%%
%% Register map (write via latch+data protocol):
%%   0,1  — Channel A tone period  (fine, coarse, 12 bits)
%%   2,3  — Channel B tone period  (fine, coarse)
%%   4,5  — Channel C tone period  (fine, coarse)
%%   6    — Noise period           (5 bits)
%%   7    — Mixer control: bits 0-2 disable tone, bits 3-5 disable noise
%%   8,9,10 — Channel A/B/C amplitude (bit 4 set = use envelope)
%%   11,12 — Envelope period       (fine, coarse, 16 bits)
%%   13   — Envelope shape         (%CAHx, see table above)
%%   14,15 — I/O ports A, B        (not emulated)
%%
%% Output: render_channels/2 returns 3 separate mono PCM binaries (S16LE,
%% -4096..+4096), one per channel. The caller (UI) handles stereo panning,
%% per-channel volume, and mixing with the beeper.
%%
%% Port protocol (ZX Spectrum 128K mapping):
%%   - 0xFFFD: write latch register number  (latch/2)
%%   - 0xBFFD: write data to latched register (write/2)
%%   - 0xFFFD: read data from latched register (read/1)
%% =============================================================================

-export([new/0, latch/2, write/3, read/1, render_channels/2, frame_start/2]).

-define(REG_TONE_A_FINE,    0).
-define(REG_TONE_A_COARSE,  1).
-define(REG_TONE_B_FINE,    2).
-define(REG_TONE_B_COARSE,  3).
-define(REG_TONE_C_FINE,    4).
-define(REG_TONE_C_COARSE,  5).
-define(REG_NOISE_PERIOD,    6).
-define(REG_MIXER,           7).
-define(REG_AMPLITUDE_A,     8).
-define(REG_AMPLITUDE_B,     9).
-define(REG_AMPLITUDE_C,    10).
-define(REG_ENV_PERIOD_FINE,  11).
-define(REG_ENV_PERIOD_COARSE,12).
-define(REG_ENV_SHAPE,       13).
-define(REG_IO_A,           14).
-define(REG_IO_B,           15).

%% AY clock divider: the chip runs at CPU / 2 (~1.77 MHz vs CPU ~3.55 MHz).
%% Internally (matching Fuse sound.c and MAME ay8910.cpp, both verified
%% against real hardware):
%%   - the tone counters tick once per 8 AY clocks (16 CPU T-states) and the
%%     square-wave output toggles after (register_value + 1) ticks, giving a
%%     half period of (reg + 1) * 16 CPU T-states (the classic AY tuning);
%%   - the noise and envelope counters tick once per 16 AY clocks (32 CPU
%%     T-states) and count the register value as-is (0 treated as 1), giving
%%     step intervals of reg * 32 CPU T-states.
-define(TSTATES_PER_AY_CLOCK, 16).
-define(TSTATES_PER_AY_SLOW_CLOCK, 32).

-define(TONES_PER_FRAME, 882).

-record(ay_state, {
    regs :: {byte(),byte(),byte(),byte(),byte(),byte(),byte(),byte(),
             byte(),byte(),byte(),byte(),byte(),byte(),byte(),byte()},
    latch :: byte(),
    tone_phase_a :: non_neg_integer(),
    tone_phase_b :: non_neg_integer(),
    tone_phase_c :: non_neg_integer(),
    noise_counter :: non_neg_integer(),
    noise_lfsr :: non_neg_integer(),
    env_counter :: non_neg_integer(),
    env_pos :: byte(),
    env_dir :: up | down,
    env_hold :: boolean()
}).

-opaque state() :: #ay_state{}.
-export_type([state/0]).

%% @doc Create a new AY-3-8912 state with all registers reset to 0.
-spec new() -> state().
new() ->
    #ay_state{
        regs = {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0},
        latch = 0,
        tone_phase_a = 0,
        tone_phase_b = 0,
        tone_phase_c = 0,
        noise_counter = 0,
        noise_lfsr = 16#10000,
        env_counter = 0,
        env_pos = 0,
        env_dir = down,
        env_hold = false
    }.

%% @doc Select a register for subsequent write/read (latch = Reg & 0x0F).
-spec latch(state(), byte()) -> state().
latch(#ay_state{} = AY, Reg) ->
    AY#ay_state{latch = Reg band 16#0F}.

%% @doc Write data to the currently latched register.
%% Special side-effects: writing noise period resets the LFSR;
%% writing envelope shape resets the envelope generator.
-spec write(state(), byte(), non_neg_integer()) -> state().
write(#ay_state{regs = Regs} = AY, Value, _TState) ->
    Latch = AY#ay_state.latch,
    NRegs = setelement(Latch + 1, Regs, Value band 16#FF),
    AY1 = AY#ay_state{regs = NRegs},
    case Latch of
        ?REG_NOISE_PERIOD -> AY1#ay_state{noise_lfsr = 16#10000};
        ?REG_ENV_SHAPE    ->
            AY1#ay_state{
                env_pos  = case (Value band 16#04) of 0 -> 15; _ -> 0 end,
                env_dir  = case (Value band 16#04) of 0 -> down; _ -> up end,
                env_hold = false
            };
        _ -> AY1
    end.

%% @doc Read the currently latched register value.
-spec read(state()) -> byte().
read(#ay_state{regs = Regs, latch = Latch}) ->
    element(Latch + 1, Regs).

%% @doc Mark the start of a new frame at the given T-state counter.
-spec frame_start(state(), non_neg_integer()) -> state().
frame_start(#ay_state{} = AY, _TState) ->
    AY.

%% @doc Render one frame of audio (882 samples per channel) into 3 separate
%% mono PCM binaries (S16LE, 0..+32767), one per AY channel A/B/C.
%% TStates defines the number of emulated Z80 T-states in this frame (typically
%% 69888 for a 50 Hz frame). The frame is divided into 882 equal steps; leftover
%% T-states advance the internal phase counters but produce no extra sample.
%% Returns {ChA, ChB, ChC, NewState}.
-spec render_channels(state(), non_neg_integer()) -> {binary(), binary(), binary(), state()}.
render_channels(#ay_state{} = AY, TStates) ->
    Samples = ?TONES_PER_FRAME,
    Step = TStates div Samples,
    Rem = TStates rem Samples,
    {ChA, ChB, ChC, AY2} = render_samples(AY, Samples, Step, <<>>, <<>>, <<>>),
    case Rem > 0 of
        true ->
            {_OutA, _OutB, _OutC, AY3} = render_step(AY2, Rem),
            {ChA, ChB, ChC, AY3};
        false ->
            {ChA, ChB, ChC, AY2}
    end.

%% --- internal ---

-spec render_samples(state(), non_neg_integer(), non_neg_integer(), binary(), binary(), binary()) ->
    {binary(), binary(), binary(), state()}.
render_samples(AY, 0, _Step, ChA, ChB, ChC) -> {ChA, ChB, ChC, AY};
render_samples(AY, N, Step, ChA, ChB, ChC) ->
    {OutA, OutB, OutC, AY1} = render_step(AY, Step),
    render_samples(AY1, N - 1, Step,
        <<ChA/binary, (pcm_scale(OutA)):16/little-signed>>,
        <<ChB/binary, (pcm_scale(OutB)):16/little-signed>>,
        <<ChC/binary, (pcm_scale(OutC)):16/little-signed>>).

-spec render_step(state(), non_neg_integer()) -> {0..15, 0..15, 0..15, state()}.
render_step(#ay_state{regs = Regs} = AY, TStates) ->
    PerA = tone_period(Regs),
    PerB = tone_period2(Regs),
    PerC = tone_period3(Regs),

    {PA, OA} = tone_output(AY#ay_state.tone_phase_a, PerA, TStates),
    {PB, OB} = tone_output(AY#ay_state.tone_phase_b, PerB, TStates),
    {PC, OC} = tone_output(AY#ay_state.tone_phase_c, PerC, TStates),

    NPer = noise_period(Regs),
    NTotal = AY#ay_state.noise_counter + TStates,
    NSteps = NTotal div NPer,
    NCounter = NTotal rem NPer,
    LFSR0 = AY#ay_state.noise_lfsr,
    LFSR1 = advance_lfsr(LFSR0, NSteps),
    Noise = LFSR1 band 1,

    EPer = env_period(Regs),
    ETotal = AY#ay_state.env_counter + TStates,
    ESteps = ETotal div EPer,
    ECounter = ETotal rem EPer,
    {EPos, EDir, EHold} = advance_env(AY#ay_state.env_pos, AY#ay_state.env_dir,
                                       AY#ay_state.env_hold, Regs, ESteps),

    EnvLevel = case EHold of
        true -> AY#ay_state.env_pos;
        false -> EPos
    end,

    Mixer = element(?REG_MIXER + 1, Regs),
    MuteToneA = (Mixer bsr 0) band 1,
    MuteToneB = (Mixer bsr 1) band 1,
    MuteToneC = (Mixer bsr 2) band 1,
    MuteNoiseA = (Mixer bsr 3) band 1,
    MuteNoiseB = (Mixer bsr 4) band 1,
    MuteNoiseC = (Mixer bsr 5) band 1,

    MixA = (MuteToneA bor OA) band (MuteNoiseA bor Noise),
    MixB = (MuteToneB bor OB) band (MuteNoiseB bor Noise),
    MixC = (MuteToneC bor OC) band (MuteNoiseC bor Noise),

    AmpA = amplitude(Regs, ?REG_AMPLITUDE_A, EnvLevel),
    AmpB = amplitude(Regs, ?REG_AMPLITUDE_B, EnvLevel),
    AmpC = amplitude(Regs, ?REG_AMPLITUDE_C, EnvLevel),

    OutA = MixA * AmpA,
    OutB = MixB * AmpB,
    OutC = MixC * AmpC,

    AY1 = AY#ay_state{
        tone_phase_a = PA, tone_phase_b = PB, tone_phase_c = PC,
        noise_counter = NCounter, noise_lfsr = LFSR1,
        env_counter = ECounter, env_pos = EPos, env_dir = EDir, env_hold = EHold
    },
    {OutA, OutB, OutC, AY1}.

-spec pcm_scale(0..15) -> -4096..4096.
pcm_scale(0) -> -4096;
pcm_scale(Sum) ->
    (Sum * 8192) div 15 - 4096.

%% 12-bit tone period: (Coarse:Fine + 1) * 16 T-states.
%% Output toggles every Period T-states, giving a square wave period of 2*Period.
-spec tone_period(tuple()) -> pos_integer().
tone_period(Regs) ->
    Fine = element(?REG_TONE_A_FINE + 1, Regs),
    Coarse = element(?REG_TONE_A_COARSE + 1, Regs) band 16#0F,
    (((Coarse bsl 8) bor Fine) + 1) * ?TSTATES_PER_AY_CLOCK.

-spec tone_period2(tuple()) -> pos_integer().
tone_period2(Regs) ->
    Fine = element(?REG_TONE_B_FINE + 1, Regs),
    Coarse = element(?REG_TONE_B_COARSE + 1, Regs) band 16#0F,
    (((Coarse bsl 8) bor Fine) + 1) * ?TSTATES_PER_AY_CLOCK.

-spec tone_period3(tuple()) -> pos_integer().
tone_period3(Regs) ->
    Fine = element(?REG_TONE_C_FINE + 1, Regs),
    Coarse = element(?REG_TONE_C_COARSE + 1, Regs) band 16#0F,
    (((Coarse bsl 8) bor Fine) + 1) * ?TSTATES_PER_AY_CLOCK.

%% @doc Noise LFSR step interval: the noise counter ticks once per 16 AY
%% clocks (32 CPU T-states) and counts the 5-bit register value as-is
%% (0 = 1).  Step interval = reg * 32 CPU T-states.
-spec noise_period(tuple()) -> pos_integer().
noise_period(Regs) ->
    N = element(?REG_NOISE_PERIOD + 1, Regs) band 16#1F,
    case N of
        0 -> ?TSTATES_PER_AY_SLOW_CLOCK;
        _ -> N * ?TSTATES_PER_AY_SLOW_CLOCK
    end.

-spec env_period(tuple()) -> pos_integer().
env_period(Regs) ->
    N = (element(?REG_ENV_PERIOD_COARSE + 1, Regs) bsl 8)
        bor element(?REG_ENV_PERIOD_FINE + 1, Regs),
    case N of
        0 -> ?TSTATES_PER_AY_SLOW_CLOCK;
        _ -> N * ?TSTATES_PER_AY_SLOW_CLOCK
    end.

-spec tone_output(non_neg_integer(), pos_integer(), non_neg_integer()) -> {non_neg_integer(), 0..1}.
tone_output(Phase, Period, TStates) ->
    Full = Period * 2,
    NewPhase = (Phase + TStates) rem Full,
    Out = case NewPhase < Period of true -> 1; false -> 0 end,
    {NewPhase, Out}.

-spec advance_lfsr(non_neg_integer(), non_neg_integer()) -> non_neg_integer().
advance_lfsr(LFSR, 0) -> LFSR;
advance_lfsr(LFSR, N) ->
    Feedback = ((LFSR bsr 16) bxor (LFSR bsr 13)) band 1,
    LFSR1 = ((LFSR bsl 1) bor Feedback) band 16#1FFFF,
    advance_lfsr(LFSR1, N - 1).

-spec advance_env(0..15, up | down, boolean(), tuple(), non_neg_integer()) ->
    {0..15, up | down, boolean()}.
advance_env(_Pos, _Dir, true, _Regs, _Steps) ->
    {0, down, true};
advance_env(Pos, Dir, false, Regs, Steps) ->
    Shape = element(?REG_ENV_SHAPE + 1, Regs),
    Cont = (Shape bsr 3) band 1,
    Att = (Shape bsr 2) band 1,
    Alt = (Shape bsr 1) band 1,
    Hold = Shape band 1,
    Inner = Att,
    advance_env_1(Pos, Dir, Steps, Cont, Alt, Hold, Inner).

-spec advance_env_1(0..15, up | down, non_neg_integer(), 0..1, 0..1, 0..1, 0..1) ->
    {0..15, up | down, boolean()}.
advance_env_1(Pos, _Dir, 0, _Cont, _Alt, _Hold, _Inner) ->
    {Pos, down, false};
advance_env_1(Pos, Dir, Steps, Cont, Alt, Hold, Inner) ->
    {Pos1, Dir1, Hold1} = case Dir of
        up ->
            P = Pos + 1,
            if P > 15 ->
                env_boundary(Cont, Alt, Hold, Inner, up);
               true -> {P, up, false}
            end;
        down ->
            P = Pos - 1,
            if P < 0 ->
                env_boundary(Cont, Alt, Hold, Inner, down);
               true -> {P, down, false}
            end
    end,
    case Hold1 of
        true -> {Pos1, Dir1, true};
        false -> advance_env_1(Pos1, Dir1, Steps - 1, Cont, Alt, Hold, Inner bxor 1)
    end.

-spec env_boundary(0..1, 0..1, 0..1, 0..1, up | down) -> {0..15, up | down, boolean()}.
env_boundary(0, _Alt, _Hold, _Inner, Dir) ->
    {case Dir of up -> 15; down -> 0 end, Dir, true};
env_boundary(1, 0, _Hold, _Inner, Dir) ->
    {case Dir of up -> 0; down -> 15 end, Dir, false};
env_boundary(1, 1, 0, _Inner, up) -> {15, down, false};
env_boundary(1, 1, 0, _Inner, down) -> {0, up, false};
env_boundary(1, _Alt, 1, _Inner, Dir) ->
    {case Dir of up -> 15; down -> 0 end, Dir, true}.

-spec amplitude(tuple(), 8..10, 0..15) -> 0..15.
amplitude(Regs, RegIdx, EnvLevel) ->
    V = element(RegIdx + 1, Regs),
    case (V bsr 4) band 1 of
        0 -> V band 16#0F;
        1 -> EnvLevel
    end.
