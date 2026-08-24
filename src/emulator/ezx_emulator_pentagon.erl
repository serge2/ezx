-module(ezx_emulator_pentagon).

-export([
    init/7,
    step/1,
    run_frame/1,
    render_frame/1,
    render_beeper/1,
    render_ay_channels/1,
    set_render_screen/2,
    read_perf/1,
    reset_perf/1,
    load_sna/2,
    load_z80/2,
    load_tap/2,
    press_key/2,
    release_key/2,
    run_until_tstates/2,
    samples_per_frame/1,
    set_cpu_frequency/2,
    set_dos_rom/2
]).

-include("z80_records.hrl").
-include("ezx_emulator.hrl").
-include("lib/z80.hrl").
-include("lib/sna.hrl").
-include("input/ezx_keyboard.hrl").

%% @doc Create a Pentagon machine state (128K / 512K / 1024K share one timing
%% model; they differ in the wired RAM, derived from MachineType). The roms
%% tuple carries the three ROM images — BASIC 128, BASIC 48, TR-DOS — any of
%% which may be `undefined' (the two BASICs are required in practice).
-spec init(#machine_model{}, module(), module(), module(), module(), module(),
           {binary() | undefined, binary() | undefined,
            binary() | undefined,
            'pentagon_128' | 'pentagon_512' | 'pentagon_1024'}) ->
    #machine_state{}.
init(Model, CPUModule, MemModule, KeyboardModule, BeeperModule, AyModule,
     {Rom0, Rom1, DosRom, MachineType}) ->
    MemReadFun = fun read_memory/3,
    MemWriteFun = fun write_memory/4,
    PortReadTable =
        [{16#0001, 16#00FE, fun read_keyboard/3},
         {16#0000, 16#FADB, fun read_kempston_mouse/3},
         {16#8002, 16#4000, fun read_p7ffd/3},
         {16#0002, 16#8001, fun read_ay/3}],
    PortWriteTable =
        [{16#0001, 16#00FE, fun write_border_beeper/4},
         %% #1FFD (A12=1, A14=0) before #7FFD (A14=1): the Beta interface
         %% system register must not fall into the paging-port decode.
         {16#C002, 16#1000, fun write_1ffd/4},
         {16#8002, 16#4000, fun write_p7ffd/4},
         {16#1008, 16#EFF7, fun write_eff7/4},
         {16#0002, 16#8001, fun write_ay/4}],
    PortReadFun =
        fun(ExtContext, TState, Port) ->
            ezx_emulator_lib:read_port(PortReadTable, ExtContext, TState, Port)
        end,
    PortWriteFun =
        fun(ExtContext, TState, Port, Byte) ->
            ezx_emulator_lib:write_port(PortWriteTable, ExtContext, TState, Port, Byte)
        end,
    BusReadFun = fun() -> 16#FF end,
    %% The Pentagon Beta interface engages through the opcode-fetch magic
    %% window (#3D00-#3DFF), so M1 reads go through the memory module's
    %% read_opcode/2, which may flip the TR-DOS overlay (see
    %% ezx_memory_pentagon:read_opcode/2). Other machines pass undefined
    %% (opcode fetches read memory like any access).
    Cpu = z80_cpu:init_state(MemReadFun, MemWriteFun, PortReadFun,
                             PortWriteFun, BusReadFun,
                             fun read_opcode_pentagon/3),
    Memory = MemModule:new({Rom0, Rom1, DosRom}, ram_banks_for(MachineType)),
    #machine_state{
        model = Model,
        machine_type = MachineType,
        cpu_module = CPUModule,
        memory_module = MemModule,
        keyboard_module = KeyboardModule,
        beeper_module = BeeperModule,
        ay_module = AyModule,
        cpu = Cpu,
        memory = Memory,
        screen = ezx_screen:new(),
        beeper = BeeperModule:init(),
        keyboard = KeyboardModule:default(),
        ay = case AyModule of
            undefined -> undefined;
            _ -> AyModule:new(Model#machine_model.ay_chip)
        end
    }.

%% @doc Load a Z80 v1/v2/v3 snapshot. The loader dispatches through the
%% machine's own memory module, so the 128K implementation works unchanged.
-spec load_z80(#machine_state{}, binary()) -> {ok, #machine_state{}} | {error, {Error, Details::binary()}} when
    Error :: bad_z80_header | z80_load_failed.
load_z80(Machine, Data) -> ezx_emulator_128:load_z80(Machine, Data).

%% @doc Load a .sna snapshot (48K or extended).
-spec load_sna(#machine_state{}, binary()) -> {ok, #machine_state{}} | {error, {Error, Details::binary()}} when
    Error :: bad_sna_header | sna_load_failed.
load_sna(Machine, Data) -> ezx_emulator_128:load_sna(Machine, Data).

%% @doc Load a TAP file (press Enter for the 128K menu boot).
-spec load_tap(#machine_state{}, binary()) -> {ok, #machine_state{}} | {error, {Error, Details::binary()}} when
    Error :: bad_tap_data.
load_tap(Machine, Data) -> ezx_emulator_128:load_tap(Machine, Data).

%% @doc Drive the stubbed Beta disk interface: map the TR-DOS ROM into the
%% bottom 16K (it stays subject to p7FFD bit 4, like MAME's pentagon model).
-spec set_dos_rom(#machine_state{}, boolean()) -> #machine_state{}.
set_dos_rom(#machine_state{memory_module = MemModule, memory = Memory} = Machine, Enabled) ->
    Machine#machine_state{memory = MemModule:set_dos_rom(Memory, Enabled)}.

%% @doc Wired RAM of each Pentagon model (the models differ only in RAM).
-spec ram_banks_for('pentagon_128' | 'pentagon_512' | 'pentagon_1024') -> 8 | 32 | 64.
ram_banks_for('pentagon_128') -> 8;
ram_banks_for('pentagon_512') -> 32;
ram_banks_for('pentagon_1024') -> 64.

%% --- delegation wrappers (identical to ezx_emulator_128) ---

-spec step(#machine_state{}) -> #machine_state{}.
step(Machine) -> ezx_emulator:step(Machine).

-spec run_frame(#machine_state{}) -> #machine_state{}.
run_frame(Machine) -> ezx_emulator:run_frame(Machine).

-spec render_frame(#machine_state{}) -> binary().
render_frame(Machine) -> ezx_emulator:render_frame(Machine).

-spec set_render_screen(#machine_state{}, boolean()) -> #machine_state{}.
set_render_screen(Machine, Flag) -> ezx_emulator:set_render_screen(Machine, Flag).

-spec read_perf(#machine_state{}) -> #perf_stats{}.
read_perf(Machine) -> ezx_emulator:read_perf(Machine).

-spec reset_perf(#machine_state{}) -> #machine_state{}.
reset_perf(Machine) -> ezx_emulator:reset_perf(Machine).

-spec render_beeper(#machine_state{}) -> {binary(), #machine_state{}}.
render_beeper(Machine) -> ezx_emulator:render_beeper(Machine).

-spec render_ay_channels(#machine_state{}) -> {binary(), binary(), binary(), #machine_state{}}.
render_ay_channels(Machine) -> ezx_emulator:render_ay_channels(Machine).

-spec press_key(#machine_state{}, non_neg_integer()) -> #machine_state{}.
press_key(Machine, Key) -> ezx_emulator:press_key(Machine, Key).

-spec release_key(#machine_state{}, non_neg_integer()) -> #machine_state{}.
release_key(Machine, Key) -> ezx_emulator:release_key(Machine, Key).

-spec run_until_tstates(#machine_state{}, non_neg_integer()) -> #machine_state{}.
run_until_tstates(Machine, Target) -> ezx_emulator:run_until_tstates(Machine, Target).

-spec samples_per_frame(#machine_state{}) -> pos_integer().
samples_per_frame(Machine) -> ezx_emulator:samples_per_frame(Machine).

-spec set_cpu_frequency(#machine_state{}, pos_integer()) -> #machine_state{}.
set_cpu_frequency(Machine, Hz) -> ezx_emulator:set_cpu_frequency(Machine, Hz).

%% --- Device port handlers ---
%%
%% Local copies of the handlers shared with ezx_emulator_128 (each machine
%% references local funs from its dispatch table), plus the Pentagon-only
%% #EFF7 writer. The #EFF7 row {16#1008, 16#EFF7} matches exactly one port:
%% A12=0 and A3=0 (ZeroMask) with every other EFF7-pattern bit set (OneMask).

read_memory(#ext_context{memory = Memory, memory_module = MemModule}, _TState, Addr) ->
    MemModule:read_byte(Memory, Addr).

%% M1-cycle read: routes through the memory module so the Beta-interface
%% magic window can flip the TR-DOS overlay. Returns {Byte, ExtContext} —
%% unchanged ExtContext when the fetch did not toggle the interface, keeping
%% the CPU's pointer-equality fast path.
read_opcode_pentagon(#ext_context{memory = Memory, memory_module = MemModule} = ExtContext,
                     _TState, Addr) ->
    case MemModule:read_opcode(Memory, Addr) of
        {Byte, Memory} -> {Byte, ExtContext};
        {Byte, Memory1} -> {Byte, ExtContext#ext_context{memory = Memory1}}
    end.

write_memory(#ext_context{memory = Memory, memory_module = MemModule} = ExtContext, _TState, Addr, Byte) ->
    case MemModule:write_byte(Memory, Addr, Byte) of
        Memory -> ExtContext;
        Memory1 -> ExtContext#ext_context{memory = Memory1}
    end.

read_keyboard(ExtContext, _TState, Port) ->
    Keyboard = ExtContext#ext_context.keyboard,
    KeyboardModule = ExtContext#ext_context.keyboard_module,
    UpperByte = (Port bsr 8) band 16#FF,
    Result = KeyboardModule:decode(Keyboard, UpperByte),
    {Result bor 16#E0, ExtContext}.

write_border_beeper(ExtContext, TState, _Port, Byte) ->
    BeeperModule = ExtContext#ext_context.beeper_module,
    BeeperLevel = (Byte bsr 4) band 1,
    Screen0 = ExtContext#ext_context.screen,
    Screen1 = ezx_screen:border_set(Screen0, TState, Byte band 16#07),
    Beeper0 = ExtContext#ext_context.beeper,
    Beeper1 = BeeperModule:set_level(Beeper0, BeeperLevel, TState),
    ExtContext#ext_context{screen = Screen1, beeper = Beeper1}.

read_ay(#ext_context{ay = undefined}, _TState, _Port) ->
    nomatch;
read_ay(#ext_context{ay = AY, ay_module = AyModule} = ExtContext, _TState, _Port) ->
    {AyModule:read(AY), ExtContext}.

write_ay(#ext_context{ay = undefined}, _TState, _Port, _Byte) ->
    nomatch;
write_ay(#ext_context{ay = AY, ay_module = AyModule} = ExtContext,
         TState, Port, Byte) ->
    case Port band 16#4000 of
        0 ->
            ExtContext#ext_context{ay = AyModule:write(AY, Byte, TState)};
        _ ->
            ExtContext#ext_context{ay = AyModule:latch(AY, Byte)}
    end.

read_kempston_mouse(#ext_context{kempston_mouse = undefined}, _TState, _Port) ->
    nomatch;
read_kempston_mouse(#ext_context{kempston_mouse = Mouse} = ExtContext, _TState, Port) ->
    case kempston_mouse_register(Port) of
        nomatch -> nomatch;
        Register -> {ezx_kempston_mouse:read(Mouse, Register), ExtContext}
    end.

kempston_mouse_register(Port) ->
    case Port band 16#0500 of
        0 -> buttons;
        16#0100 -> x;
        16#0500 -> y;
        _ -> nomatch
    end.

%% 0x7FFD port read row (A15=0, A1=0, A14=1): returns the current paging byte.
read_p7ffd(#ext_context{memory = Memory, memory_module = MemModule} = ExtContext, _TState, _Port) ->
    {MemModule:get_p7ffd(Memory), ExtContext}.

%% 0x7FFD port write row (A15=0, A1=0, A14=1): applies the paging byte.
write_p7ffd(#ext_context{memory = Memory, memory_module = MemModule} = ExtContext, _TState, _Port, Byte) ->
    ExtContext#ext_context{memory = MemModule:write_port_7ffd(Memory, Byte)}.

%% #1FFD port write row (A15=0, A1=0, A12=1): Beta interface system
%% register; bit 4 (DOSEN) maps the TR-DOS ROM while p7FFD bit 4 is clear.
write_1ffd(#ext_context{memory = Memory, memory_module = MemModule} = ExtContext, _TState, _Port, Byte) ->
    ExtContext#ext_context{memory = MemModule:write_port_1ffd(Memory, Byte)}.

%% #EFF7 port write row: 1MB mapping mode + all-RAM overlay (1024K only).
write_eff7(#ext_context{memory = Memory, memory_module = MemModule} = ExtContext, _TState, _Port, Byte) ->
    ExtContext#ext_context{memory = MemModule:write_port_eff7(Memory, Byte)}.
