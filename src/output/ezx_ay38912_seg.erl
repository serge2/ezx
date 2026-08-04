-module(ezx_ay38912_seg).

%% =============================================================================
%% AY-3-8912 / YM2149 programmable sound generator emulation.
%% 
%% Segmented rendering variant: write/3 records each register write with its
%% T-state timestamp.  At frame end render_channels/3 partitions the frame
%% into Samples (machine-model derived) and applies register changes at the
%% exact sample boundary where they occur, producing correct output when the
%% AY registers are changed mid-frame.
%%
%% Three independent tone channels (A, B, C), each with:
%%   - a square-wave tone generator (12-bit period, register pair per channel)
%%   - a noise mixer (global 5-bit noise period, 17-bit right-shifting LFSR:
%%     feedback = bit0 XOR bit3, output = bit0 — verified on AY-3-8910 and
%%     YM2149 chips)
%%   - amplitude control: fixed 4-bit level or envelope follower (per channel)
%%
%% Shared global envelope generator with 16 shapes (R13 = %CAHx):
%%   C=CONT (0=single cycle, reset to 0 and hold; 1=continue),
%%   A=ATT (0=start 15→0, 1=start 0→15), H=HOLD (1=freeze at boundary),
%%   ALT=alternate (invert direction on each cycle)
%%
%%   R13  shape  behaviour
%%   ----------------------------------------------------------------------------
%%   0000  \___  single 15→0, reset to 0 and hold
%%   0001  \___  (dup: Cont=0, Att=0 => \___ regardless of Alt/Hold)
%%   0010  \___  (dup: same)
%%   0011  \___  (dup: same)
%%   ----------------------------------------------------------------------------
%%   0100  /___  single 0→15, reset to 0 and hold (Cont=0 always resets to 0)
%%   0101  /___  (dup: Cont=0, Att=1 => /___ regardless of Alt/Hold)
%%   0110  /___  (dup: same)
%%   0111  /___  (dup: same)
%%   ----------------------------------------------------------------------------
%%   1000  \/\/  repeating sawtooth 15→0→15→0... (Alt=0: same direction)
%%   1001  \___  single 15→0, hold at 0
%%   1010  \/\/\ repeating triangle 15<->0<->15... (Alt=1: alternate; boundary
%%          value held one extra step, as on real hardware)
%%   1011  \```  single 15→0, reset to 15 and hold (Hold+Alternate reset)
%%   ----------------------------------------------------------------------------
%%   1100  /\/\  repeating sawtooth 0→15→0→15... (Alt=0: same direction)
%%   1101  /"""  single 0→15, hold at 15
%%   1110  /\/\/\ repeating triangle 0<->15<->0... (Alt=1: alternate; boundary
%%          value held one extra step, as on real hardware)
%%   1111  /___  single 0→15, reset to 0 and hold (Hold+Alternate reset)
%%
%% Register map (write via latch+data protocol):
%%   0,1  - Channel A tone period  (fine, coarse, 12 bits)
%%   2,3  - Channel B tone period  (fine, coarse)
%%   4,5  - Channel C tone period  (fine, coarse)
%%   6    - Noise period           (5 bits)
%%   7    - Mixer control: bits 0-2 disable tone, bits 3-5 disable noise
%%   8,9,10 - Channel A/B/C amplitude (bit 4 set = use envelope)
%%   11,12 - Envelope period       (fine, coarse, 16 bits)
%%   13   - Envelope shape         (%CAHx, see table above)
%%   14,15 - I/O ports A, B        (not emulated)
%%
%% Output: render_channels/3 returns 3 separate mono PCM binaries (S16LE,
%% -4096..+4096), one per channel.  The caller (UI) handles stereo panning,
%% per-channel volume, and mixing with the beeper.
%%
%% Port protocol (ZX Spectrum 128K mapping):
%%   0xFFFD: write latch register number  (latch/2)
%%   0xBFFD: write data to latched register (write/3, TState required)
%%   0xFFFD: read data from latched register (read/1)
%%
%% Two chip variants, selected via new/1 ('ay' default, 'ym' for the
%% Yamaha YM2149).  The YM2149 is pin-compatible with the AY-3-8912 and
%% functionally identical except for the envelope generator:
%%   - the envelope counter has 5-bit resolution (32 levels instead of 16),
%%     giving twice as many (smoother) steps per sweep;
%%   - the envelope steps twice as fast (each step interval is halved), so a
%%     full sweep still takes the same time;
%%   - the DAC curve is different (measured YM2149 resistance values, see
%%     ?YM_VOLUME_LEVEL): cleaner but softer than the AY's idealized 3 dB
%%     curve.  Fixed volumes use the even YM taps so volume 0 stays silent.
%%   - unused register bits read back as 0 on the AY but as written on the
%%     YM — the basis of the software AY-vs-YM detection trick (write 31 to
%%     register 1, read back: 15 = AY, 31 = YM).
%%   - the YM2149 checks the programmed code in the latch byte (DA7-DA4 must
%%     be 0000): latching 0x10+ deactivates the chip until the next valid
%%     latch, so reads return 0xFF.  Action's second detection branch does
%%     exactly this (latch 0x10, read: 0xFF = YM, non-0xFF = AY).  The AY
%%     ignores the upper nibble entirely.
%% Tone, noise, and mixer behaviour are identical on both chips.
%%
%% Usage:
%%   1. Call frame_start/2 at the beginning of each video frame (snapshots
%%      current register state for the render pass).
%%   2. During emulation call write/3 with the absolute T-state count.
%%   3. At frame end call render_channels/3 with the frame length in
%%      T-states and the desired sample count - it segments the frame at
%%      sample boundaries, applying logged write events at the correct
%%      sample position.
%% =============================================================================

-export([new/0, new/1, latch/2, write/3, read/1, chip/1, render_channels/3, frame_start/2]).

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
%% Internally (verified against real hardware):
%%   - the tone counters tick once per 8 AY clocks (16 CPU T-states) and the
%%     square-wave output toggles after (register_value + 1) ticks, giving a
%%     half period of (reg + 1) * 16 CPU T-states (the classic AY tuning);
%%   - the noise and envelope counters tick once per 16 AY clocks (32 CPU
%%     T-states) and count the register value as-is (0 treated as 1), giving
%%     step intervals of reg * 32 CPU T-states.
-define(TSTATES_PER_AY_CLOCK, 16).
-define(TSTATES_PER_AY_SLOW_CLOCK, 32).

-record(ay_state_seg, {
    chip :: ay | ym,
    regs :: {byte(),byte(),byte(),byte(),byte(),byte(),byte(),byte(),
             byte(),byte(),byte(),byte(),byte(),byte(),byte(),byte()},
    latch :: byte(),
    active :: boolean(),
    tone_phase_a :: non_neg_integer(),
    tone_phase_b :: non_neg_integer(),
    tone_phase_c :: non_neg_integer(),
    noise_counter :: non_neg_integer(),
    noise_lfsr :: non_neg_integer(),
    env_counter :: non_neg_integer(),
    env_pos :: byte(),
    env_dir :: up | down,
    env_hold :: boolean(),
    frame_offset :: non_neg_integer(),
    frame_regs :: tuple(),
    frame_events :: list()
}).

-opaque state() :: #ay_state_seg{}.
-export_type([state/0]).

%% @doc Create a new AY-3-8912 state with all registers reset to 0.
-spec new() -> state().
new() ->
    new(ay).

%% @doc Create a new sound generator state with all registers reset to 0.
%% The chip is either the General Instrument AY-3-8912 ('ay', the default,
%% used in the ZX Spectrum 128) or the pin-compatible Yamaha YM2149 ('ym').
%% See the module header for the behavioural differences between the two.
-spec new(ay | ym) -> state().
new(Chip) when Chip =:= ay; Chip =:= ym ->
    InitRegs = {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0},
    #ay_state_seg{
        chip = Chip,
        regs = InitRegs,
        latch = 0,
        active = true,
        tone_phase_a = 0,
        tone_phase_b = 0,
        tone_phase_c = 0,
        noise_counter = 0,
        noise_lfsr = 16#10000,
        env_counter = 0,
        env_pos = 0,
        env_dir = down,
        env_hold = false,
        frame_offset = 0,
        frame_regs = InitRegs,
        frame_events = []
    }.

%% @doc Select a register for subsequent write/read.  On the AY-3-8912 the
%% register is selected by the low nibble only (latch = Reg & 0x0F).  The
%% YM2149 additionally checks the programmed code in DA7-DA4 (must be 0000,
%% together with A9/A8): latching a byte with the upper nibble set to
%% anything else drives the data bus high-impedance and deactivates the chip
%% until the next valid latch — reads then return 0xFF and writes are
%% ignored.  This is what demos like Action use to tell the chips apart
%% (latch 0x10, read: 0xFF = YM, non-0xFF = AY).
-spec latch(state(), byte()) -> state().
latch(#ay_state_seg{chip = ay} = AY, Reg) ->
    AY#ay_state_seg{latch = Reg band 16#0F};
latch(#ay_state_seg{chip = ym} = AY, Reg) ->
    case Reg band 16#F0 of
        0 -> AY#ay_state_seg{active = true, latch = Reg band 16#0F};
        _ -> AY#ay_state_seg{active = false}
    end.

%% @doc The chip variant this state was created for ('ay' or 'ym').
-spec chip(state()) -> ay | ym.
chip(#ay_state_seg{chip = Chip}) -> Chip.

%% @doc Write data to the currently latched register.
%% Records the write as a frame event with the given T-state for later
%% segmented rendering.  Immediate side-effects: writing noise period
%% resets the LFSR; writing envelope shape resets the envelope generator.
-spec write(state(), byte(), non_neg_integer()) -> state().
write(#ay_state_seg{active = false} = AY, _Value, _TState) ->
    AY;
write(#ay_state_seg{chip = Chip, regs = Regs, frame_events = Events} = AY, Value, TState) ->
    Latch = AY#ay_state_seg.latch,
    NRegs = setelement(Latch + 1, Regs, Value band 16#FF),
    AY1 = AY#ay_state_seg{
        regs = NRegs,
        frame_events = [{TState, Latch, Value band 16#FF} | Events]
    },
    case Latch of
        ?REG_NOISE_PERIOD -> AY1#ay_state_seg{noise_lfsr = 16#10000};
        ?REG_ENV_SHAPE    ->
            AY1#ay_state_seg{
                env_counter = 0,
                env_pos  = case (Value band 16#04) of 0 -> env_max(Chip); _ -> 0 end,
                env_dir  = case (Value band 16#04) of 0 -> down; _ -> up end,
                env_hold = false
            };
        _ -> AY1
    end.

%% @doc Read the currently latched register value.
%% Unused bits in a register read back as 0 on the AY-3-8912: only the
%% bits the register implements are returned.  The YM2149 returns every
%% bit as written.  This is what makes the software chip-detection trick
%% work (write 31 to the 4-bit coarse tone register 1, read back: 15 = AY,
%% 31 = YM).  While the chip is deactivated (YM, bad programmed-code latch)
%% the bus is high-impedance, i.e. reads return 0xFF.
-spec read(state()) -> byte().
read(#ay_state_seg{active = false}) -> 16#FF;
read(#ay_state_seg{chip = Chip, regs = Regs, latch = Latch}) ->
    element(Latch + 1, Regs) band mask_read(Chip, Latch).

%% @doc Read-back mask for a register, per chip.  The AY-3-8910 mask table
%% is (0xff,0x0f,0xff,0x0f,0xff,0x0f,0x1f,0xff,0x1f,0x1f,0x1f,0xff,0xff,
%% 0x0f,0xff,0xff); the YM2149 has no mask (unused bits read as written).
-spec mask_read(ay | ym, 0..15) -> byte().
mask_read(ym, _Latch) -> 16#FF;
mask_read(ay, ?REG_TONE_A_COARSE) -> 16#0F;
mask_read(ay, ?REG_TONE_B_COARSE) -> 16#0F;
mask_read(ay, ?REG_TONE_C_COARSE) -> 16#0F;
mask_read(ay, ?REG_NOISE_PERIOD)  -> 16#1F;
mask_read(ay, ?REG_AMPLITUDE_A)   -> 16#1F;
mask_read(ay, ?REG_AMPLITUDE_B)   -> 16#1F;
mask_read(ay, ?REG_AMPLITUDE_C)   -> 16#1F;
mask_read(ay, ?REG_ENV_SHAPE)     -> 16#0F;
mask_read(ay, _Latch) -> 16#FF.

%% @doc Mark the start of a new frame at the given T-state counter.
%% Snapshots the current register state for the segmented render pass
%% and clears the accumulated frame-event log.
-spec frame_start(state(), non_neg_integer()) -> state().
frame_start(#ay_state_seg{regs = Regs} = AY, TState) ->
    AY#ay_state_seg{
        frame_offset = TState,
        frame_regs = Regs,
        frame_events = []
    }.

%% @doc Render one frame of audio into Samples mono PCM samples per channel
%% (S16LE, -4096..+4096), one per AY channel A/B/C.  FrameLen defines the
%% number of emulated Z80 T-states in this frame (e.g. 70908 for a 128K
%% frame).  Samples is derived by the emulator from the machine model as
%% trunc(FrameLen * SampleRate / CpuClock).  When frame events are present the
%% frame is segmented at sample boundaries and register changes are applied at
%% the correct sample position.  Without events falls back to the naive
%% equal-step renderer (identical to the simplified implementation).
%% Returns {ChA, ChB, ChC, NewState}.
-spec render_channels(state(), non_neg_integer(), pos_integer()) -> {binary(), binary(), binary(), state()}.
render_channels(#ay_state_seg{frame_events = []} = AY, FrameLen, Samples) ->
    render_channels_naive(AY, FrameLen, Samples);
render_channels(#ay_state_seg{frame_offset = FO, frame_regs = FRegs, frame_events = Events} = AY, FrameLen, Samples) ->
    RelEvents = [{ET - FO, RI, V} || {ET, RI, V} <- Events, ET >= FO, ET < FO + FrameLen],
    Step = FrameLen div Samples,
    Emap = build_event_map(lists:reverse(RelEvents), Step),
    RenderAY = AY#ay_state_seg{regs = FRegs},
    {ChA, ChB, ChC, AY2} = render_samples(RenderAY, 0, Samples, Step, Emap, <<>>, <<>>, <<>>),
    AY3 = AY2#ay_state_seg{
        regs = AY#ay_state_seg.regs,
        frame_events = []
    },
    case FrameLen rem Samples of
        0 -> {ChA, ChB, ChC, AY3};
        Rem -> {_OA, _OB, _OC, AY4} = render_step(AY3, Rem), {ChA, ChB, ChC, AY4}
    end.

%% --- internal ---

%% @doc Build a sample-index-to-events map for segmented rendering.
%% Events arrive in chronological order (oldest first).  Each event is
%% mapped to its sample index (ET div Step).  Multiple events at the
%% same sample are stored newest-first (prepend) so foldr in apply_events
%% applies them in chronological order.
-spec build_event_map(list(), non_neg_integer()) -> map().
build_event_map([], _Step) -> #{};
build_event_map(Events, Step) ->
    lists:foldl(fun({ET, RI, V}, Acc) ->
        SI = ET div Step,
        maps:update_with(SI, fun(L) -> [{RI, V} | L] end, [{RI, V}], Acc)
    end, #{}, Events).

%% @doc Render all samples, applying frame events at the correct boundaries.
%% I iterates from 0 to Samples-1.  At each iteration, events for the
%% current sample index are applied before the sample is rendered.
-spec render_samples(state(), non_neg_integer(), non_neg_integer(),
                     non_neg_integer(), map(), binary(), binary(), binary()) ->
    {binary(), binary(), binary(), state()}.
render_samples(AY, I, I, _Step, _Emap, ChA, ChB, ChC) -> {ChA, ChB, ChC, AY};
render_samples(AY, I, Samples, Step, Emap, ChA, ChB, ChC) ->
    AY1 = apply_events(AY, I, Emap),
    {OutA, OutB, OutC, AY2} = render_step(AY1, Step),
    Chip = AY#ay_state_seg.chip,
    render_samples(AY2, I + 1, Samples, Step, Emap,
        <<ChA/binary, (pcm_scale(Chip, OutA)):16/little-signed>>,
        <<ChB/binary, (pcm_scale(Chip, OutB)):16/little-signed>>,
        <<ChC/binary, (pcm_scale(Chip, OutC)):16/little-signed>>).

%% @doc Apply all pending register writes at the given sample index.
%% Events within a sample are stored newest-first in the map; foldr
%% processes them oldest-first so the newest write wins.
-spec apply_events(state(), non_neg_integer(), map()) -> state().
apply_events(AY, _I, Emap) ->
    case Emap of
        #{_I := Events} ->
            Chip = AY#ay_state_seg.chip,
            lists:foldr(fun({RI, V}, Acc) ->
                Regs = setelement(RI + 1, Acc#ay_state_seg.regs, V),
                Acc1 = Acc#ay_state_seg{regs = Regs},
                case RI of
                    ?REG_NOISE_PERIOD ->
                        Acc1#ay_state_seg{noise_lfsr = 16#10000};
                    ?REG_ENV_SHAPE ->
                        Acc1#ay_state_seg{
                            env_counter = 0,
                            env_pos  = case (V band 16#04) of 0 -> env_max(Chip); _ -> 0 end,
                            env_dir  = case (V band 16#04) of 0 -> down; _ -> up end,
                            env_hold = false
                        };
                    _ -> Acc1
                end
            end, AY, Events);
        _ -> AY
    end.

%% @doc Naive fallback renderer used when no frame events were logged
%% (identical to the simplified ezx_ay38912 implementation).
-spec render_channels_naive(state(), non_neg_integer(), pos_integer()) ->
    {binary(), binary(), binary(), state()}.
render_channels_naive(#ay_state_seg{} = AY, FrameLen, Samples) ->
    Step = FrameLen div Samples,
    Rem = FrameLen rem Samples,
    {ChA, ChB, ChC, AY2} = render_samples_naive(AY, Samples, Step, <<>>, <<>>, <<>>),
    case Rem > 0 of
        true ->
            {_OutA, _OutB, _OutC, AY3} = render_step(AY2, Rem),
            {ChA, ChB, ChC, AY3};
        false ->
            {ChA, ChB, ChC, AY2}
    end.

%% @doc Count down from N samples producing PCM output for each step
%% (naive variant, no frame events).
-spec render_samples_naive(state(), non_neg_integer(), non_neg_integer(),
                           binary(), binary(), binary()) ->
    {binary(), binary(), binary(), state()}.
render_samples_naive(AY, 0, _Step, ChA, ChB, ChC) -> {ChA, ChB, ChC, AY};
render_samples_naive(AY, N, Step, ChA, ChB, ChC) ->
    {OutA, OutB, OutC, AY1} = render_step(AY, Step),
    Chip = AY#ay_state_seg.chip,
    render_samples_naive(AY1, N - 1, Step,
        <<ChA/binary, (pcm_scale(Chip, OutA)):16/little-signed>>,
        <<ChB/binary, (pcm_scale(Chip, OutB)):16/little-signed>>,
        <<ChC/binary, (pcm_scale(Chip, OutC)):16/little-signed>>).

%% @doc Advance all tone, noise, and envelope generators by TStates and
%% produce one 4-bit output value per channel (0-15).
-spec render_step(state(), non_neg_integer()) -> {0..15, 0..15, 0..15, state()}.
render_step(#ay_state_seg{regs = Regs, chip = Chip} = AY, TStates) ->
    PerA = tone_period(Regs, ?REG_TONE_A_FINE, ?REG_TONE_A_COARSE),
    PerB = tone_period(Regs, ?REG_TONE_B_FINE, ?REG_TONE_B_COARSE),
    PerC = tone_period(Regs, ?REG_TONE_C_FINE, ?REG_TONE_C_COARSE),

    {PA, OA} = tone_output(AY#ay_state_seg.tone_phase_a, PerA, TStates),
    {PB, OB} = tone_output(AY#ay_state_seg.tone_phase_b, PerB, TStates),
    {PC, OC} = tone_output(AY#ay_state_seg.tone_phase_c, PerC, TStates),

    NPer = noise_period(Regs),
    NTotal = AY#ay_state_seg.noise_counter + TStates,
    NSteps = NTotal div NPer,
    NCounter = NTotal rem NPer,
    LFSR0 = AY#ay_state_seg.noise_lfsr,
    LFSR1 = advance_lfsr(LFSR0, NSteps),
    Noise = LFSR1 band 1,

    EPer = env_period(Chip, Regs),
    ETotal = AY#ay_state_seg.env_counter + TStates,
    ESteps = ETotal div EPer,
    ECounter = ETotal rem EPer,
    {EPos, EDir, EHold} = advance_env(Chip, AY#ay_state_seg.env_pos, AY#ay_state_seg.env_dir,
                                      AY#ay_state_seg.env_hold, Regs, ESteps),

    EnvLevel = EPos,

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

    AmpA = amplitude(Chip, Regs, ?REG_AMPLITUDE_A, EnvLevel),
    AmpB = amplitude(Chip, Regs, ?REG_AMPLITUDE_B, EnvLevel),
    AmpC = amplitude(Chip, Regs, ?REG_AMPLITUDE_C, EnvLevel),

    OutA = MixA * AmpA,
    OutB = MixB * AmpB,
    OutC = MixC * AmpC,

    AY1 = AY#ay_state_seg{
        tone_phase_a = PA, tone_phase_b = PB, tone_phase_c = PC,
        noise_counter = NCounter, noise_lfsr = LFSR1,
        env_counter = ECounter, env_pos = EPos, env_dir = EDir, env_hold = EHold
    },
    {OutA, OutB, OutC, AY1}.


-define(AY_VOLUME_LEVEL, {
    0,
    64,
    90,
    128,
    181,
    256,
    362,
    512,
    724,
    1024,
    1448,
    2048,
    2896,
    4096,
    5793,
    8192
}).

%% 32-level YM2149 DAC curve.  The table converted to a 0..8192 scale; the
%% YM's internal DAC has 5-bit resolution for the envelope (smoother
%% sweeps than the AY's 16 steps) and a slightly different curve from the
%% AY (cleaner but softer mid levels).
-define(YM_VOLUME_LEVEL, {
    0,
    16,
    39,
    71,
    89,
    111,
    131,
    153,
    185,
    221,
    255,
    293,
    351,
    418,
    483,
    556,
    667,
    798,
    927,
    1073,
    1288,
    1541,
    1788,
    2068,
    2501,
    3004,
    3512,
    4079,
    4982,
    5989,
    7067,
    8192
}).

%% @doc Scale a DAC index to a signed 16-bit PCM sample (-4096..+4096).
%% AY indexes are 0..15 (envelope and fixed volumes share the 16-step DAC);
%% YM envelope indexes are 0..31 (5-bit envelope DAC).  The DAC is
%% logarithmic (3 dB per level for the AY, measured curve for the YM).
-spec pcm_scale(ay | ym, 0..31) -> -4096..4096.
pcm_scale(ay, Index) -> element(Index + 1, ?AY_VOLUME_LEVEL) - 4096;
pcm_scale(ym, Index) -> element(Index + 1, ?YM_VOLUME_LEVEL) - 4096.

%% 12-bit tone period: (Coarse:Fine + 1) * 16 T-states.
%% Output toggles every Period T-states, giving a square wave period of 2*Period.
%% FineReg/CoarseReg select the channel's tone period register pair
%% (channel A: 0/1, B: 2/3, C: 4/5).
-spec tone_period(tuple(), 0..4, 1..5) -> pos_integer().
tone_period(Regs, FineReg, CoarseReg) ->
    Fine = element(FineReg + 1, Regs),
    Coarse = element(CoarseReg + 1, Regs) band 16#0F,
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

-spec env_period(ay | ym, tuple()) -> pos_integer().
env_period(ay, Regs) ->
    env_period_1(Regs, ?TSTATES_PER_AY_SLOW_CLOCK);
env_period(ym, Regs) ->
    %% The YM2149 paces the envelope counter twice as fast as the AY:
    %% each step interval is halved.
    env_period_1(Regs, ?TSTATES_PER_AY_CLOCK).

env_period_1(Regs, SlowClock) ->
    N = (element(?REG_ENV_PERIOD_COARSE + 1, Regs) bsl 8)
        bor element(?REG_ENV_PERIOD_FINE + 1, Regs),
    case N of
        0 -> SlowClock;
        _ -> N * SlowClock
    end.

-spec tone_output(non_neg_integer(), pos_integer(), non_neg_integer()) -> {non_neg_integer(), 0..1}.
tone_output(Phase, Period, TStates) ->
    Full = Period * 2,
    NewPhase = (Phase + TStates) rem Full,
    Out = case NewPhase < Period of true -> 1; false -> 0 end,
    {NewPhase, Out}.

%%--------------------------------------------------------------------
%% @doc Advances the 17-bit Linear Feedback Shift Register (LFSR)
%% by N clock ticks.
%% Taps: Bit 0 and Bit 3 (Feedback = Bit0 XOR Bit3)
%% Shift: Right-shift with Feedback inserted into MSB (Bit 16).
%%--------------------------------------------------------------------
-spec advance_lfsr(non_neg_integer(), non_neg_integer()) -> non_neg_integer().

advance_lfsr(LFSR, 0) ->
    %% Mask state to ensure valid 17-bit bounds [0..131071]
    LFSR band 16#1FFFF;
advance_lfsr(LFSR, N) ->
    %% 1. Extract output tap bits (Bit 0 and Bit 3)
    Bit0 = LFSR band 1,
    Bit3 = (LFSR bsr 3) band 1,
    %% 2. Calculate linear feedback
    Feedback = Bit0 bxor Bit3,
    %% 3. Right shift by 1 bit and insert Feedback into Bit 16 (MSB)
    LFSR1 = ((LFSR bsr 1) bor (Feedback bsl 16)) band 16#1FFFF,
    advance_lfsr(LFSR1, N - 1).

%% @doc Top envelope position for a chip: 15 (4-bit counter) on the AY,
%% 31 (5-bit counter) on the YM.
-spec env_max(ay | ym) -> 15 | 31.
env_max(ay) -> 15;
env_max(ym) -> 31.

-spec advance_env(ay | ym, 0..31, up | down, boolean(), tuple(), non_neg_integer()) ->
    {0..31, up | down, boolean()}.
%% If already in Hold state, remain locked at the held position
advance_env(_Chip, Pos, Dir, true, _Regs, _Steps) ->
    {Pos, Dir, true};
%% Zero steps requested -> return current state unchanged
advance_env(_Chip, Pos, Dir, false, _Regs, 0) ->
    {Pos, Dir, false};
%% Normal step evaluation
advance_env(Chip, Pos, Dir, false, Regs, Steps) ->
    Shape = element(?REG_ENV_SHAPE + 1, Regs),
    %% Extract Register 13 control bits:
    %% Bit 3: Continue (1 = Loop/Continue, 0 = Single cycle then hold 0)
    %% Bit 2: Attack   (1 = Initial direction UP, 0 = Initial DOWN)
    %% Bit 1: Alternate(1 = Invert direction on boundary, 0 = Repeat shape)
    %% Bit 0: Hold     (1 = Freeze envelope at boundary)
    Cont = (Shape bsr 3) band 1,
    Att  = (Shape bsr 2) band 1,
    Alt  = (Shape bsr 1) band 1,
    Hold = Shape band 1,
    step_loop(Chip, Pos, Dir, Steps, Cont, Att, Alt, Hold).

%% Recursive inner step processing
step_loop(_Chip, Pos, Dir, 0, _Cont, _Att, _Alt, _Hold) ->
    {Pos, Dir, false};

step_loop(Chip, Pos, Dir, Steps, Cont, Att, Alt, Hold) ->
    NextPos = case Dir of
        up   -> Pos + 1;
        down -> Pos - 1
    end,
    Top = env_max(Chip),
    if
        NextPos >= 0, NextPos =< Top ->
            %% Within valid DAC range [0..Top]
            step_loop(Chip, NextPos, Dir, Steps - 1, Cont, Att, Alt, Hold);
        true ->
            %% Boundary overflow/underflow occurred (NextPos < 0 or NextPos > Top)
            {BoundaryPos, NewDir, IsHold} = env_boundary(Chip, Cont, Att, Alt, Hold, Dir),
            case IsHold of
                true  -> {BoundaryPos, NewDir, true};
                false -> step_loop(Chip, BoundaryPos, NewDir, Steps - 1, Cont, Att, Alt, Hold)
            end
    end.

%%--------------------------------------------------------------------
%% @doc Handles envelope behavior when reaching boundary limits ([0..Top]).
%%--------------------------------------------------------------------
-spec env_boundary(ay | ym, 0..1, 0..1, 0..1, 0..1, up | down) ->
    {0..31, up | down, boolean()}.

%% 1. Cont = 0: Single cycle mode (decay to 0 and hold)
env_boundary(_Chip, 0, _Att, _Alt, _Hold, _Dir) ->
    {0, down, true};

%% 2. Cont = 1, Hold = 1: Freeze modes (R13 = 11, 13, 15)
%% R13 = 11 (1011b): Att=0, Alt=1 -> Invert at boundary and hold MAX
env_boundary(Chip, 1, 0, 1, 1, down) -> {env_max(Chip), up, true};

%% R13 = 15 (1111b): Att=1, Alt=1 -> Invert at boundary and hold MIN (0)
env_boundary(_Chip, 1, 1, 1, 1, up)   -> {0, down, true};

%% R13 = 9 (1001b) / 13 (1101b): Alt=0 -> Hold at current boundary (Top or 0)
env_boundary(Chip, 1, _Att, 0, 1, up)   -> {env_max(Chip), up, true};
env_boundary(_Chip, 1, _Att, 0, 1, down) -> {0, down, true};

%% 3. Cont = 1, Hold = 0, Alt = 0: Repeating Sawtooth (R13 = 8, 12)
%% Top reached (Top UP) -> Reset to bottom (0)
env_boundary(_Chip, 1, _Att, 0, 0, up)   -> {0, up, false};

%% Bottom reached (0 DOWN) -> Reset to top
env_boundary(Chip, 1, _Att, 0, 0, down) -> {env_max(Chip), down, false};

%% 4. Cont = 1, Hold = 0, Alt = 1: Repeating Triangle (R13 = 10, 14)
%% Top reached (Top UP) -> hold the boundary value one extra step, then reverse
env_boundary(Chip, 1, _Att, 1, 0, up)   -> {env_max(Chip), down, false};

%% Bottom reached (0 DOWN) -> hold the boundary value one extra step, then reverse
env_boundary(_Chip, 1, _Att, 1, 0, down) -> {0, up, false};

%% Fallback for any other unexpected combination (should not occur)
env_boundary(_Chip, _Cont, _Att, _Alt, _Hold, _Dir) ->
    {0, down, true}.

%% @doc Amplitude DAC index for a channel: the fixed 4-bit volume (mapped to
%% the even YM taps so volume 0 is silence) or the current envelope position.
-spec amplitude(ay | ym, tuple(), 8..10, 0..31) -> 0..31.
amplitude(ay, Regs, RegIdx, EnvLevel) ->
    amplitude_1(Regs, RegIdx, EnvLevel, 0);
amplitude(ym, Regs, RegIdx, EnvLevel) ->
    amplitude_1(Regs, RegIdx, EnvLevel, 1).

amplitude_1(Regs, RegIdx, EnvLevel, YmShift) ->
    V = element(RegIdx + 1, Regs),
    case (V bsr 4) band 1 of
        0 -> (V band 16#0F) bsl YmShift;
        1 -> EnvLevel
    end.
