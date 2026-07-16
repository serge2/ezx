-module(z80_cpu_main_exchange_tests).

-include("z80_records.hrl").
-include_lib("eunit/include/eunit.hrl").

%% --- Exchange Tests ---

ex_af_af_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{a = 16#12, f = 16#34, a_alt = 16#56, f_alt = 16#78},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#08),  %% EX AF,AF'
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#56, Machine2#machine_state.cpu#cpu_state.a),
    ?assertEqual(16#78, Machine2#machine_state.cpu#cpu_state.f),
    ?assertEqual(16#12, Machine2#machine_state.cpu#cpu_state.a_alt),
    ?assertEqual(16#34, Machine2#machine_state.cpu#cpu_state.f_alt),
    ?assertEqual(4, z80_cpu:t_states(Machine2)).

ex_af_af_twice_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{a = 16#12, f = 16#34, a_alt = 16#56, f_alt = 16#78},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#08),  %% EX AF,AF'
    Mem2 = z80_mem:write_byte(Mem1, 1, 16#08),  %% EX AF,AF'
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem2},
    Machine2 = z80_cpu:step(Machine1),
    Machine3 = z80_cpu:step(Machine2),
    ?assertEqual(16#12, Machine3#machine_state.cpu#cpu_state.a),
    ?assertEqual(16#34, Machine3#machine_state.cpu#cpu_state.f).

ex_de_hl_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{d = 16#12, e = 16#34, h = 16#56, l = 16#78},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#EB),  %% EX DE,HL
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#56, Machine2#machine_state.cpu#cpu_state.d),
    ?assertEqual(16#78, Machine2#machine_state.cpu#cpu_state.e),
    ?assertEqual(16#12, Machine2#machine_state.cpu#cpu_state.h),
    ?assertEqual(16#34, Machine2#machine_state.cpu#cpu_state.l),
    ?assertEqual(4, z80_cpu:t_states(Machine2)).

ex_sp_hl_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{sp = 16#FEFE, h = 16#12, l = 16#34},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 16#FEFE, 16#78),  %% Low byte at SP
    Mem2 = z80_mem:write_byte(Mem1, 16#FEFF, 16#56),  %% High byte at SP+1
    Mem3 = z80_mem:write_byte(Mem2, 0, 16#E3),  %% EX (SP),HL
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem3},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#56, Machine2#machine_state.cpu#cpu_state.h),
    ?assertEqual(16#78, Machine2#machine_state.cpu#cpu_state.l),
    ?assertEqual(16#34, z80_emulator:read_byte(Machine2, 16#FEFE)),  %% Low byte = old L
    ?assertEqual(16#12, z80_emulator:read_byte(Machine2, 16#FEFF)),  %% High byte = old H
    ?assertEqual(19, z80_cpu:t_states(Machine2)).

exx_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{
        b = 16#11, c = 16#22, d = 16#33, e = 16#44, h = 16#55, l = 16#66,
        b_alt = 16#77, c_alt = 16#88, d_alt = 16#99, e_alt = 16#AA, h_alt = 16#BB, l_alt = 16#CC
    },
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#D9),  %% EXX
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#77, Machine2#machine_state.cpu#cpu_state.b),
    ?assertEqual(16#88, Machine2#machine_state.cpu#cpu_state.c),
    ?assertEqual(16#99, Machine2#machine_state.cpu#cpu_state.d),
    ?assertEqual(16#AA, Machine2#machine_state.cpu#cpu_state.e),
    ?assertEqual(16#BB, Machine2#machine_state.cpu#cpu_state.h),
    ?assertEqual(16#CC, Machine2#machine_state.cpu#cpu_state.l),
    ?assertEqual(16#11, Machine2#machine_state.cpu#cpu_state.b_alt),
    ?assertEqual(16#22, Machine2#machine_state.cpu#cpu_state.c_alt),
    ?assertEqual(16#33, Machine2#machine_state.cpu#cpu_state.d_alt),
    ?assertEqual(16#44, Machine2#machine_state.cpu#cpu_state.e_alt),
    ?assertEqual(16#55, Machine2#machine_state.cpu#cpu_state.h_alt),
    ?assertEqual(16#66, Machine2#machine_state.cpu#cpu_state.l_alt),
    ?assertEqual(4, z80_cpu:t_states(Machine2)).

exx_twice_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{
        b = 16#11, c = 16#22, d = 16#33, e = 16#44, h = 16#55, l = 16#66,
        b_alt = 16#77, c_alt = 16#88, d_alt = 16#99, e_alt = 16#AA, h_alt = 16#BB, l_alt = 16#CC
    },
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#D9),  %% EXX
    Mem2 = z80_mem:write_byte(Mem1, 1, 16#D9),  %% EXX
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem2},
    Machine2 = z80_cpu:step(Machine1),
    Machine3 = z80_cpu:step(Machine2),
    ?assertEqual(16#11, Machine3#machine_state.cpu#cpu_state.b),
    ?assertEqual(16#22, Machine3#machine_state.cpu#cpu_state.c).

%% --- PUSH/POP Tests ---

push_bc_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{b = 16#12, c = 16#34, sp = 16#FF00},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#C5),  %% PUSH BC
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#FEFE, Machine2#machine_state.cpu#cpu_state.sp),
    ?assertEqual(16#34, z80_emulator:read_byte(Machine2, 16#FEFE)),
    ?assertEqual(16#12, z80_emulator:read_byte(Machine2, 16#FEFF)),
    ?assertEqual(11, z80_cpu:t_states(Machine2)).

push_de_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{d = 16#12, e = 16#34, sp = 16#FF00},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#D5),  %% PUSH DE
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#FEFE, Machine2#machine_state.cpu#cpu_state.sp),
    ?assertEqual(16#34, z80_emulator:read_byte(Machine2, 16#FEFE)),
    ?assertEqual(16#12, z80_emulator:read_byte(Machine2, 16#FEFF)).

push_hl_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{h = 16#12, l = 16#34, sp = 16#FF00},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#E5),  %% PUSH HL
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#FEFE, Machine2#machine_state.cpu#cpu_state.sp),
    ?assertEqual(16#34, z80_emulator:read_byte(Machine2, 16#FEFE)),
    ?assertEqual(16#12, z80_emulator:read_byte(Machine2, 16#FEFF)).

push_af_test() ->
    Machine0 = z80_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{a = 16#12, f = 16#34, sp = 16#FF00},
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 0, 16#F5),  %% PUSH AF
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem1},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#FEFE, Machine2#machine_state.cpu#cpu_state.sp),
    ?assertEqual(16#34, z80_emulator:read_byte(Machine2, 16#FEFE)),
    ?assertEqual(16#12, z80_emulator:read_byte(Machine2, 16#FEFF)).

pop_bc_test() ->
    Machine0 = z80_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 16#FEFE, 16#56),
    Mem2 = z80_mem:write_byte(Mem1, 16#FEFF, 16#78),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{sp = 16#FEFE},
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem2},
    Mem3 = z80_mem:write_byte(Mem2, 0, 16#C1),  %% POP BC
    Machine2 = Machine1#machine_state{memory = Mem3},
    Machine3 = z80_cpu:step(Machine2),
    ?assertEqual(16#78, Machine3#machine_state.cpu#cpu_state.b),
    ?assertEqual(16#56, Machine3#machine_state.cpu#cpu_state.c),
    ?assertEqual(16#FF00, Machine3#machine_state.cpu#cpu_state.sp),
    ?assertEqual(10, z80_cpu:t_states(Machine3)).

pop_de_test() ->
    Machine0 = z80_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 16#FEFE, 16#56),
    Mem2 = z80_mem:write_byte(Mem1, 16#FEFF, 16#78),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{sp = 16#FEFE},
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem2},
    Mem3 = z80_mem:write_byte(Mem2, 0, 16#D1),  %% POP DE
    Machine2 = Machine1#machine_state{memory = Mem3},
    Machine3 = z80_cpu:step(Machine2),
    ?assertEqual(16#78, Machine3#machine_state.cpu#cpu_state.d),
    ?assertEqual(16#56, Machine3#machine_state.cpu#cpu_state.e).

pop_hl_test() ->
    Machine0 = z80_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 16#FEFE, 16#56),
    Mem2 = z80_mem:write_byte(Mem1, 16#FEFF, 16#78),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{sp = 16#FEFE},
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem2},
    Mem3 = z80_mem:write_byte(Mem2, 0, 16#E1),  %% POP HL
    Machine2 = Machine1#machine_state{memory = Mem3},
    Machine3 = z80_cpu:step(Machine2),
    ?assertEqual(16#78, Machine3#machine_state.cpu#cpu_state.h),
    ?assertEqual(16#56, Machine3#machine_state.cpu#cpu_state.l).

pop_af_test() ->
    Machine0 = z80_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = z80_mem:write_byte(Mem0, 16#FEFE, 16#F0),
    Mem2 = z80_mem:write_byte(Mem1, 16#FEFF, 16#DE),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{sp = 16#FEFE},
    Machine1 = Machine0#machine_state{cpu = Cpu0, memory = Mem2},
    Mem3 = z80_mem:write_byte(Mem2, 0, 16#F1),  %% POP AF
    Machine2 = Machine1#machine_state{memory = Mem3},
    Machine3 = z80_cpu:step(Machine2),
    ?assertEqual(16#DE, Machine3#machine_state.cpu#cpu_state.a),
    ?assertEqual(16#F0, Machine3#machine_state.cpu#cpu_state.f).