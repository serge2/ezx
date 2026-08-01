-module(ezx_kempston_mouse_tests).

-include("z80_records.hrl").
-include("ezx_emulator.hrl").
-include_lib("eunit/include/eunit.hrl").

%% --- module-level tests ---

default_state_test() ->
    Mouse = ezx_kempston_mouse:new(),
    ?assertEqual(0, ezx_kempston_mouse:read(Mouse, 16#FBDF)),
    ?assertEqual(0, ezx_kempston_mouse:read(Mouse, 16#FFDF)),
    ?assertEqual(16#07, ezx_kempston_mouse:read(Mouse, 16#FADF)).

move_accumulates_deltas_test() ->
    Mouse0 = ezx_kempston_mouse:new(),
    Mouse1 = ezx_kempston_mouse:move(Mouse0, 3, 2),
    Mouse2 = ezx_kempston_mouse:move(Mouse1, 2, 4),
    ?assertEqual(5, ezx_kempston_mouse:read(Mouse2, 16#FBDF)),
    ?assertEqual(6, ezx_kempston_mouse:read(Mouse2, 16#FFDF)).

move_wraps_counters_test() ->
    Mouse0 = ezx_kempston_mouse:new(),
    Mouse1 = ezx_kempston_mouse:move(Mouse0, 300, -5),
    ?assertEqual(44, ezx_kempston_mouse:read(Mouse1, 16#FBDF)),
    ?assertEqual(251, ezx_kempston_mouse:read(Mouse1, 16#FFDF)).

set_buttons_masks_test() ->
    Mouse0 = ezx_kempston_mouse:new(),
    Mouse1 = ezx_kempston_mouse:set_buttons(Mouse0, 16#02),
    ?assertEqual(16#02, ezx_kempston_mouse:read(Mouse1, 16#FADF)).

read_fb_low_byte_variants_test() ->
    Mouse = ezx_kempston_mouse:new(),
    Mouse1 = ezx_kempston_mouse:move(Mouse, 42, 7),
    Mouse2 = ezx_kempston_mouse:set_buttons(Mouse1, 16#05),
    ?assertEqual(16#05, ezx_kempston_mouse:read(Mouse2, 16#FADF)),
    ?assertEqual(16#05, ezx_kempston_mouse:read(Mouse2, 16#FAFB)),
    ?assertEqual(42, ezx_kempston_mouse:read(Mouse2, 16#FBDF)),
    ?assertEqual(42, ezx_kempston_mouse:read(Mouse2, 16#FBFB)),
    ?assertEqual(7, ezx_kempston_mouse:read(Mouse2, 16#FFDF)),
    ?assertEqual(7, ezx_kempston_mouse:read(Mouse2, 16#FFFB)).

non_mouse_port_returns_undefined_test() ->
    Mouse = ezx_kempston_mouse:new(),
    ?assertEqual(undefined, ezx_kempston_mouse:read(Mouse, 16#00FE)),
    ?assertEqual(undefined, ezx_kempston_mouse:read(Mouse, 16#FFFD)).

%% --- machine-level integration tests ---

%% LD BC,0xFADF; IN A,(C); LD D,A; LD BC,0xFBDF; IN A,(C); LD E,A;
%% LD BC,0xFFDF; IN A,(C); LD H,A; HALT
kempston_program() ->
    [16#01, 16#DF, 16#FA,
     16#ED, 16#78,
     16#57,
     16#01, 16#DF, 16#FB,
     16#ED, 16#78,
     16#5F,
     16#01, 16#DF, 16#FF,
     16#ED, 16#78,
     16#67,
     16#76].

machine_reads_kempston_ports_test() ->
    Machine0 = init_machine(),
    Machine1 = ezx_emulator:set_mouse_enabled(Machine0, true),
    Machine2 = ezx_emulator:set_mouse_position(Machine1, 5, -3),
    Machine3 = ezx_emulator:set_mouse_buttons(Machine2, 16#02),
    Machine4 = load_program(Machine3, 16#4000, kempston_program()),
    Machine5 = set_pc(Machine4, 16#4000),
    Machine6 = run_steps(Machine5, 12),
    Cpu = Machine6#machine_state.cpu,
    ?assertEqual(16#02, z80_cpu:get_reg_byte(d, Cpu)),
    ?assertEqual(5, z80_cpu:get_reg_byte(e, Cpu)),
    ?assertEqual(253, z80_cpu:get_reg_byte(h, Cpu)).

machine_128k_reads_kempston_ports_test() ->
    Machine0 = init_machine_128(),
    Machine1 = ezx_emulator:set_mouse_enabled(Machine0, true),
    Machine2 = ezx_emulator:set_mouse_position(Machine1, 9, 1),
    Machine3 = ezx_emulator:set_mouse_buttons(Machine2, 16#01),
    Machine4 = load_program(Machine3, 16#4000, kempston_program()),
    Machine5 = set_pc(Machine4, 16#4000),
    Machine6 = run_steps(Machine5, 12),
    Cpu = Machine6#machine_state.cpu,
    ?assertEqual(16#01, z80_cpu:get_reg_byte(d, Cpu)),
    ?assertEqual(9, z80_cpu:get_reg_byte(e, Cpu)),
    ?assertEqual(1, z80_cpu:get_reg_byte(h, Cpu)).

machine_kempston_disabled_returns_ff_test() ->
    Machine0 = init_machine(),
    Machine1 = load_program(Machine0, 16#4000, kempston_program()),
    Machine2 = set_pc(Machine1, 16#4000),
    Machine3 = run_steps(Machine2, 12),
    Cpu = Machine3#machine_state.cpu,
    ?assertEqual(16#FF, z80_cpu:get_reg_byte(d, Cpu)),
    ?assertEqual(16#FF, z80_cpu:get_reg_byte(e, Cpu)),
    ?assertEqual(16#FF, z80_cpu:get_reg_byte(h, Cpu)).

machine_kempston_disable_after_enable_test() ->
    Machine0 = init_machine(),
    Machine1 = ezx_emulator:set_mouse_enabled(Machine0, true),
    Machine2 = ezx_emulator:set_mouse_enabled(Machine1, false),
    Machine3 = load_program(Machine2, 16#4000, kempston_program()),
    Machine4 = set_pc(Machine3, 16#4000),
    Machine5 = run_steps(Machine4, 12),
    ?assertEqual(16#FF, z80_cpu:get_reg_byte(d, Machine5#machine_state.cpu)).

machine_kempston_state_survives_steps_test() ->
    Machine0 = init_machine(),
    Machine1 = ezx_emulator:set_mouse_enabled(Machine0, true),
    Machine2 = ezx_emulator:set_mouse_position(Machine1, 1, 1),
    Machine3 = load_program(Machine2, 16#4000, [16#00]),
    Machine4 = set_pc(Machine3, 16#4000),
    Machine5 = ezx_emulator:step(Machine4),
    Mouse = Machine5#machine_state.kempston_mouse,
    ?assertEqual(1, ezx_kempston_mouse:read(Mouse, 16#FBDF)),
    ?assertEqual(1, ezx_kempston_mouse:read(Mouse, 16#FFDF)).

%% --- helpers ---

init_machine() ->
    RomPath = try filename:join([code:priv_dir(ezx), "roms", "48.rom"])
    catch error:badarg ->
        BeamDir = filename:dirname(code:which(?MODULE)),
        filename:join([filename:dirname(BeamDir), "priv", "roms", "48.rom"])
    end,
    {ok, Rom} = file:read_file(RomPath),
    ezx_emulator:init(z80_cpu, ezx_memory_48, ezx_keyboard, ezx_beeper2, undefined, Rom).

init_machine_128() ->
    PrivDir = try code:priv_dir(ezx)
    catch error:badarg ->
        BeamDir = filename:dirname(code:which(?MODULE)),
        filename:dirname(BeamDir)
    end,
    Rom0Path = filename:join([PrivDir, "roms", "128-0.rom"]),
    Rom1Path = filename:join([PrivDir, "roms", "128-1.rom"]),
    {ok, Rom0} = file:read_file(Rom0Path),
    {ok, Rom1} = file:read_file(Rom1Path),
    ezx_emulator_128:init(z80_cpu, ezx_memory_128_pages512, ezx_keyboard,
                          ezx_beeper2, ezx_ay38912_seg, {Rom0, Rom1}).

load_program(Machine, BaseAddr, Program) ->
    lists:foldl(fun({Offset, Byte}, M) ->
        ezx_emulator:write_byte(M, BaseAddr + Offset, Byte)
    end, Machine, lists:zip(lists:seq(0, length(Program) - 1), Program)).

set_pc(#machine_state{cpu = Cpu} = Machine, Addr) ->
    Machine#machine_state{cpu = Cpu#cpu_state{pc = Addr}}.

run_steps(Machine, N) ->
    lists:foldl(fun(_, M) -> ezx_emulator:step(M) end, Machine, lists:seq(1, N)).
