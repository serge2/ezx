-module(z80_cpu_cb_tests).

-include("z80_records.hrl").
-include_lib("eunit/include/eunit.hrl").

%% --- CB Prefix Tests ---

%% ============================================================================
%% RLC (Rotate Left Circular) - 0x00-0x07
%% ============================================================================

cb_rlc_b_timing_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#CB),  %% CB prefix
    Mem2 = ezx_mem:write_byte(Mem1, 1, 16#00),  %% RLC B
    Machine1 = Machine0#machine_state{memory = Mem2},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(8, z80_cpu:t_states(Machine2)).

cb_rlc_b_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#CB),  %% CB prefix
    Mem2 = ezx_mem:write_byte(Mem1, 1, 16#00),  %% RLC B
    Machine1 = Machine0#machine_state{memory = Mem2},
    Cpu1 = Machine1#machine_state.cpu#cpu_state{b = 16#81, f = 0},
    Machine2 = Machine1#machine_state{cpu = Cpu1},
    Machine3 = z80_cpu:step(Machine2),
    Cpu3 = Machine3#machine_state.cpu,
    ?assertEqual(16#03, Cpu3#cpu_state.b),        %% 10000001 -> 00000011 (carry=1)
    ?assertEqual(?FLAG_C, Cpu3#cpu_state.f band ?FLAG_C),
    ?assertEqual(0, Cpu3#cpu_state.f band ?FLAG_Z),
    ?assertEqual(8, z80_cpu:t_states(Machine3)).

cb_rlc_c_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#CB),  %% CB prefix
    Mem2 = ezx_mem:write_byte(Mem1, 1, 16#01),  %% RLC C
    Machine1 = Machine0#machine_state{memory = Mem2},
    Cpu1 = Machine1#machine_state.cpu#cpu_state{c = 16#40, f = 0},
    Machine2 = Machine1#machine_state{cpu = Cpu1},
    Machine3 = z80_cpu:step(Machine2),
    Cpu3 = Machine3#machine_state.cpu,
    ?assertEqual(16#80, Cpu3#cpu_state.c),        %% 01000000 -> 10000000
    ?assertEqual(0, Cpu3#cpu_state.f band ?FLAG_C),
    ?assertEqual(?FLAG_S, Cpu3#cpu_state.f band ?FLAG_S),
    ?assertEqual(8, z80_cpu:t_states(Machine3)).

cb_rlc_d_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#CB),  %% CB prefix
    Mem2 = ezx_mem:write_byte(Mem1, 1, 16#02),  %% RLC D
    Machine1 = Machine0#machine_state{memory = Mem2},
    Cpu1 = Machine1#machine_state.cpu#cpu_state{d = 16#FF, f = 0},
    Machine2 = Machine1#machine_state{cpu = Cpu1},
    Machine3 = z80_cpu:step(Machine2),
    Cpu3 = Machine3#machine_state.cpu,
    ?assertEqual(16#FF, Cpu3#cpu_state.d),        %% 11111111 -> 11111111 (carry=1)
    ?assertEqual(?FLAG_C, Cpu3#cpu_state.f band ?FLAG_C),
    ?assertEqual(8, z80_cpu:t_states(Machine3)).

cb_rlc_e_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#CB),  %% CB prefix
    Mem2 = ezx_mem:write_byte(Mem1, 1, 16#03),  %% RLC E
    Machine1 = Machine0#machine_state{memory = Mem2},
    Cpu1 = Machine1#machine_state.cpu#cpu_state{e = 16#01, f = 0},
    Machine2 = Machine1#machine_state{cpu = Cpu1},
    Machine3 = z80_cpu:step(Machine2),
    Cpu3 = Machine3#machine_state.cpu,
    ?assertEqual(16#02, Cpu3#cpu_state.e),
    ?assertEqual(8, z80_cpu:t_states(Machine3)).

cb_rlc_h_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#CB),  %% CB prefix
    Mem2 = ezx_mem:write_byte(Mem1, 1, 16#04),  %% RLC H
    Machine1 = Machine0#machine_state{memory = Mem2},
    Cpu1 = Machine1#machine_state.cpu#cpu_state{h = 16#80, f = 0},
    Machine2 = Machine1#machine_state{cpu = Cpu1},
    Machine3 = z80_cpu:step(Machine2),
    Cpu3 = Machine3#machine_state.cpu,
    ?assertEqual(16#01, Cpu3#cpu_state.h),
    ?assertEqual(?FLAG_C, Cpu3#cpu_state.f band ?FLAG_C),
    ?assertEqual(8, z80_cpu:t_states(Machine3)).

cb_rlc_l_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#CB),  %% CB prefix
    Mem2 = ezx_mem:write_byte(Mem1, 1, 16#05),  %% RLC L
    Machine1 = Machine0#machine_state{memory = Mem2},
    Cpu1 = Machine1#machine_state.cpu#cpu_state{l = 16#55, f = 0},
    Machine2 = Machine1#machine_state{cpu = Cpu1},
    Machine3 = z80_cpu:step(Machine2),
    Cpu3 = Machine3#machine_state.cpu,
    ?assertEqual(16#AA, Cpu3#cpu_state.l),        %% 01010101 -> 10101010
    ?assertEqual(0, Cpu3#cpu_state.f band ?FLAG_C),
    ?assertEqual(8, z80_cpu:t_states(Machine3)).

cb_rlc_a_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#CB),  %% CB prefix
    Mem2 = ezx_mem:write_byte(Mem1, 1, 16#07),  %% RLC A
    Machine1 = Machine0#machine_state{memory = Mem2},
    Cpu1 = Machine1#machine_state.cpu#cpu_state{a = 16#C0, f = 0},
    Machine2 = Machine1#machine_state{cpu = Cpu1},
    Machine3 = z80_cpu:step(Machine2),
    Cpu3 = Machine3#machine_state.cpu,
    ?assertEqual(16#81, Cpu3#cpu_state.a),        %% 11000000 -> 10000001 (carry=1)
    ?assertEqual(?FLAG_C, Cpu3#cpu_state.f band ?FLAG_C),
    ?assertEqual(8, z80_cpu:t_states(Machine3)).

cb_rlc_hl_test() ->
    %% RLC (HL) - 0x06: read (HL), RLC, write back, 15 T-states
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#CB),  %% CB prefix
    Mem2 = ezx_mem:write_byte(Mem1, 1, 16#06),  %% RLC (HL)
    Mem3 = ezx_mem:write_byte(Mem2, 16#4000, 16#80),  %% value at HL
    Machine1 = Machine0#machine_state{memory = Mem3, cpu = Machine0#machine_state.cpu#cpu_state{h = 16#40, l = 16#00}},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#01, ezx_emulator:read_byte(Machine2, 16#4000)),  %% 10000000 -> 00000001
    ?assertEqual(?FLAG_C, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_C),
    ?assertEqual(15, z80_cpu:t_states(Machine2)).

cb_rlc_hl_zero_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#CB),
    Mem2 = ezx_mem:write_byte(Mem1, 1, 16#06),
    Mem3 = ezx_mem:write_byte(Mem2, 16#4000, 16#00),  %% 0x00 -> 0x00, Z=1
    Machine1 = Machine0#machine_state{memory = Mem3, cpu = Machine0#machine_state.cpu#cpu_state{h = 16#40, l = 16#00}},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#00, ezx_emulator:read_byte(Machine2, 16#4000)),
    ?assertEqual(?FLAG_Z, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_Z),
    ?assertEqual(0, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_C).

%% ============================================================================
%% RRC (Rotate Right Circular) - 0x08-0x0F
%% ============================================================================

cb_rrc_b_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#CB),  %% CB prefix
    Mem2 = ezx_mem:write_byte(Mem1, 1, 16#08),  %% RRC B
    Machine1 = Machine0#machine_state{memory = Mem2},
    Cpu1 = Machine1#machine_state.cpu#cpu_state{b = 16#01, f = 0},
    Machine2 = Machine1#machine_state{cpu = Cpu1},
    Machine3 = z80_cpu:step(Machine2),
    Cpu3 = Machine3#machine_state.cpu,
    ?assertEqual(16#80, Cpu3#cpu_state.b),        %% 00000001 -> 10000000 (carry=1)
    ?assertEqual(?FLAG_C, Cpu3#cpu_state.f band ?FLAG_C),
    ?assertEqual(?FLAG_S, Cpu3#cpu_state.f band ?FLAG_S),
    ?assertEqual(8, z80_cpu:t_states(Machine3)).

cb_rrc_c_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#CB),  %% CB prefix
    Mem2 = ezx_mem:write_byte(Mem1, 1, 16#09),  %% RRC C
    Machine1 = Machine0#machine_state{memory = Mem2},
    Cpu1 = Machine1#machine_state.cpu#cpu_state{c = 16#02, f = 0},
    Machine2 = Machine1#machine_state{cpu = Cpu1},
    Machine3 = z80_cpu:step(Machine2),
    Cpu3 = Machine3#machine_state.cpu,
    ?assertEqual(16#01, Cpu3#cpu_state.c),
    ?assertEqual(0, Cpu3#cpu_state.f band ?FLAG_C),
    ?assertEqual(8, z80_cpu:t_states(Machine3)).

cb_rrc_a_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#CB),  %% CB prefix
    Mem2 = ezx_mem:write_byte(Mem1, 1, 16#0F),  %% RRC A
    Machine1 = Machine0#machine_state{memory = Mem2},
    Cpu1 = Machine1#machine_state.cpu#cpu_state{a = 16#80, f = 0},
    Machine2 = Machine1#machine_state{cpu = Cpu1},
    Machine3 = z80_cpu:step(Machine2),
    Cpu3 = Machine3#machine_state.cpu,
    ?assertEqual(16#40, Cpu3#cpu_state.a),        %% 10000000 -> 01000000 (carry=0)
    ?assertEqual(0, Cpu3#cpu_state.f band ?FLAG_C),
    ?assertEqual(8, z80_cpu:t_states(Machine3)).

cb_rrc_hl_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#CB),  %% CB prefix
    Mem2 = ezx_mem:write_byte(Mem1, 1, 16#0E),  %% RRC (HL)
    Mem3 = ezx_mem:write_byte(Mem2, 16#4000, 16#01),  %% Memory at HL = 0x01
    Machine1 = Machine0#machine_state{memory = Mem3, cpu = Machine0#machine_state.cpu#cpu_state{h = 16#40, l = 16#00}},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#80, ezx_emulator:read_byte(Machine2, 16#4000)),  %% RRC 0x01 = 0x80, carry=1
    ?assertEqual(?FLAG_C, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_C),
    ?assertEqual(?FLAG_S, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_S),
    ?assertEqual(15, z80_cpu:t_states(Machine2)).

%% ============================================================================
%% RL (Rotate Left through Carry) - 0x10-0x17
%% ============================================================================

cb_rl_b_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#CB),  %% CB prefix
    Mem2 = ezx_mem:write_byte(Mem1, 1, 16#10),  %% RL B
    Machine1 = Machine0#machine_state{memory = Mem2},
    Cpu1 = Machine1#machine_state.cpu#cpu_state{b = 16#81, f = 0},
    Machine2 = Machine1#machine_state{cpu = Cpu1},
    Machine3 = z80_cpu:step(Machine2),
    Cpu3 = Machine3#machine_state.cpu,
    ?assertEqual(16#02, Cpu3#cpu_state.b),        %% 10000001 -> 00000010 (carry=1)
    ?assertEqual(?FLAG_C, Cpu3#cpu_state.f band ?FLAG_C),
    ?assertEqual(8, z80_cpu:t_states(Machine3)).

cb_rl_b_carry_set_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#CB),  %% CB prefix
    Mem2 = ezx_mem:write_byte(Mem1, 1, 16#10),  %% RL B
    Machine1 = Machine0#machine_state{memory = Mem2},
    Cpu1 = Machine1#machine_state.cpu#cpu_state{b = 16#40, f = 16#01},  %% Carry=1
    Machine2 = Machine1#machine_state{cpu = Cpu1},
    Machine3 = z80_cpu:step(Machine2),
    Cpu3 = Machine3#machine_state.cpu,
    ?assertEqual(16#81, Cpu3#cpu_state.b),        %% 01000000 + carry=1 -> 10000001
    ?assertEqual(0, Cpu3#cpu_state.f band ?FLAG_C),
    ?assertEqual(8, z80_cpu:t_states(Machine3)).

cb_rl_c_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#CB),  %% CB prefix
    Mem2 = ezx_mem:write_byte(Mem1, 1, 16#11),  %% RL C
    Machine1 = Machine0#machine_state{memory = Mem2},
    Cpu1 = Machine1#machine_state.cpu#cpu_state{c = 16#80, f = 16#01},
    Machine2 = Machine1#machine_state{cpu = Cpu1},
    Machine3 = z80_cpu:step(Machine2),
    Cpu3 = Machine3#machine_state.cpu,
    ?assertEqual(16#01, Cpu3#cpu_state.c),        %% 10000000 + carry=1 -> 00000001
    ?assertEqual(?FLAG_C, Cpu3#cpu_state.f band ?FLAG_C),
    ?assertEqual(8, z80_cpu:t_states(Machine3)).

cb_rl_a_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#CB),  %% CB prefix
    Mem2 = ezx_mem:write_byte(Mem1, 1, 16#17),  %% RL A
    Machine1 = Machine0#machine_state{memory = Mem2},
    Cpu1 = Machine1#machine_state.cpu#cpu_state{a = 16#FF, f = 0},
    Machine2 = Machine1#machine_state{cpu = Cpu1},
    Machine3 = z80_cpu:step(Machine2),
    Cpu3 = Machine3#machine_state.cpu,
    ?assertEqual(16#FE, Cpu3#cpu_state.a),        %% 11111111 -> 11111110 (carry=1)
    ?assertEqual(?FLAG_C, Cpu3#cpu_state.f band ?FLAG_C),
    ?assertEqual(8, z80_cpu:t_states(Machine3)).

cb_rl_hl_test() ->
    %% RL (HL) - 0x16: read (HL), RL, write back, 15 T-states
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#CB),
    Mem2 = ezx_mem:write_byte(Mem1, 1, 16#16),  %% RL (HL)
    Mem3 = ezx_mem:write_byte(Mem2, 16#4000, 16#7F),  %% 01111111
    Machine1 = Machine0#machine_state{memory = Mem3, cpu = Machine0#machine_state.cpu#cpu_state{h = 16#40, l = 16#00, f = 16#01}},  %% carry=1
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#FF, ezx_emulator:read_byte(Machine2, 16#4000)),  %% 01111111 + carry=1 = 11111111
    ?assertEqual(0, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_C),
    ?assertEqual(15, z80_cpu:t_states(Machine2)).

cb_rl_hl_no_carry_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#CB),
    Mem2 = ezx_mem:write_byte(Mem1, 1, 16#16),
    Mem3 = ezx_mem:write_byte(Mem2, 16#4000, 16#7F),  %% 01111111
    Machine1 = Machine0#machine_state{memory = Mem3, cpu = Machine0#machine_state.cpu#cpu_state{h = 16#40, l = 16#00, f = 0}},  %% carry=0
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#FE, ezx_emulator:read_byte(Machine2, 16#4000)),  %% 01111111 + carry=0 = 11111110
    ?assertEqual(0, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_C).

%% ============================================================================
%% RR (Rotate Right through Carry) - 0x18-0x1F
%% ============================================================================

cb_rr_b_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#CB),  %% CB prefix
    Mem2 = ezx_mem:write_byte(Mem1, 1, 16#18),  %% RR B
    Machine1 = Machine0#machine_state{memory = Mem2},
    Cpu1 = Machine1#machine_state.cpu#cpu_state{b = 16#01, f = 0},
    Machine2 = Machine1#machine_state{cpu = Cpu1},
    Machine3 = z80_cpu:step(Machine2),
    Cpu3 = Machine3#machine_state.cpu,
    ?assertEqual(16#00, Cpu3#cpu_state.b),        %% 00000001 -> 00000000 (carry=1)
    ?assertEqual(?FLAG_C, Cpu3#cpu_state.f band ?FLAG_C),
    ?assertEqual(?FLAG_Z, Cpu3#cpu_state.f band ?FLAG_Z),
    ?assertEqual(8, z80_cpu:t_states(Machine3)).

cb_rr_b_carry_set_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#CB),  %% CB prefix
    Mem2 = ezx_mem:write_byte(Mem1, 1, 16#18),  %% RR B
    Machine1 = Machine0#machine_state{memory = Mem2},
    Cpu1 = Machine1#machine_state.cpu#cpu_state{b = 16#02, f = 16#01},  %% Carry=1
    Machine2 = Machine1#machine_state{cpu = Cpu1},
    Machine3 = z80_cpu:step(Machine2),
    Cpu3 = Machine3#machine_state.cpu,
    ?assertEqual(16#81, Cpu3#cpu_state.b),        %% 00000010 + carry=1 -> 10000001
    ?assertEqual(0, Cpu3#cpu_state.f band ?FLAG_C),
    ?assertEqual(8, z80_cpu:t_states(Machine3)).

cb_rr_c_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#CB),  %% CB prefix
    Mem2 = ezx_mem:write_byte(Mem1, 1, 16#19),  %% RR C
    Machine1 = Machine0#machine_state{memory = Mem2},
    Cpu1 = Machine1#machine_state.cpu#cpu_state{c = 16#80, f = 0},
    Machine2 = Machine1#machine_state{cpu = Cpu1},
    Machine3 = z80_cpu:step(Machine2),
    Cpu3 = Machine3#machine_state.cpu,
    ?assertEqual(16#40, Cpu3#cpu_state.c),        %% 10000000 -> 01000000 (carry=0)
    ?assertEqual(0, Cpu3#cpu_state.f band ?FLAG_C),
    ?assertEqual(8, z80_cpu:t_states(Machine3)).

cb_rr_a_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#CB),  %% CB prefix
    Mem2 = ezx_mem:write_byte(Mem1, 1, 16#1F),  %% RR A
    Machine1 = Machine0#machine_state{memory = Mem2},
    Cpu1 = Machine1#machine_state.cpu#cpu_state{a = 16#02, f = 0},
    Machine2 = Machine1#machine_state{cpu = Cpu1},
    Machine3 = z80_cpu:step(Machine2),
    Cpu3 = Machine3#machine_state.cpu,
    ?assertEqual(16#01, Cpu3#cpu_state.a),        %% 00000010 -> 00000001 (carry=0)
    ?assertEqual(0, Cpu3#cpu_state.f band ?FLAG_C),
    ?assertEqual(8, z80_cpu:t_states(Machine3)).

cb_rr_hl_test() ->
    %% RR (HL) - 0x1E: read (HL), RR, write back, 15 T-states
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#CB),
    Mem2 = ezx_mem:write_byte(Mem1, 1, 16#1E),  %% RR (HL)
    Mem3 = ezx_mem:write_byte(Mem2, 16#4000, 16#02),  %% 00000010
    Machine1 = Machine0#machine_state{memory = Mem3, cpu = Machine0#machine_state.cpu#cpu_state{h = 16#40, l = 16#00, f = 16#01}},  %% carry=1
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#81, ezx_emulator:read_byte(Machine2, 16#4000)),  %% 00000010 + carry=1 = 10000001
    ?assertEqual(0, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_C),
    ?assertEqual(15, z80_cpu:t_states(Machine2)).

cb_rr_hl_no_carry_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#CB),
    Mem2 = ezx_mem:write_byte(Mem1, 1, 16#1E),
    Mem3 = ezx_mem:write_byte(Mem2, 16#4000, 16#80),  %% 10000000
    Machine1 = Machine0#machine_state{memory = Mem3, cpu = Machine0#machine_state.cpu#cpu_state{h = 16#40, l = 16#00, f = 0}},  %% carry=0
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#40, ezx_emulator:read_byte(Machine2, 16#4000)),  %% 10000000 + carry=0 = 01000000
    ?assertEqual(0, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_C).

%% ============================================================================
%% SLA (Shift Left Arithmetic) - 0x20-0x27
%% ============================================================================

cb_sla_b_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#CB),  %% CB prefix
    Mem2 = ezx_mem:write_byte(Mem1, 1, 16#20),  %% SLA B
    Machine1 = Machine0#machine_state{memory = Mem2},
    Cpu1 = Machine1#machine_state.cpu#cpu_state{b = 16#40, f = 0},
    Machine2 = Machine1#machine_state{cpu = Cpu1},
    Machine3 = z80_cpu:step(Machine2),
    Cpu3 = Machine3#machine_state.cpu,
    ?assertEqual(16#80, Cpu3#cpu_state.b),        %% 01000000 -> 10000000
    ?assertEqual(0, Cpu3#cpu_state.f band ?FLAG_C),
    ?assertEqual(?FLAG_S, Cpu3#cpu_state.f band ?FLAG_S),
    ?assertEqual(0, Cpu3#cpu_state.f band ?FLAG_Z),
    ?assertEqual(8, z80_cpu:t_states(Machine3)).

cb_sla_b_carry_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#CB),  %% CB prefix
    Mem2 = ezx_mem:write_byte(Mem1, 1, 16#20),  %% SLA B
    Machine1 = Machine0#machine_state{memory = Mem2},
    Cpu1 = Machine1#machine_state.cpu#cpu_state{b = 16#80, f = 0},
    Machine2 = Machine1#machine_state{cpu = Cpu1},
    Machine3 = z80_cpu:step(Machine2),
    Cpu3 = Machine3#machine_state.cpu,
    ?assertEqual(16#00, Cpu3#cpu_state.b),        %% 10000000 -> 00000000 (carry=1)
    ?assertEqual(?FLAG_C, Cpu3#cpu_state.f band ?FLAG_C),
    ?assertEqual(?FLAG_Z, Cpu3#cpu_state.f band ?FLAG_Z),
    ?assertEqual(8, z80_cpu:t_states(Machine3)).

cb_sla_c_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#CB),  %% CB prefix
    Mem2 = ezx_mem:write_byte(Mem1, 1, 16#21),  %% SLA C
    Machine1 = Machine0#machine_state{memory = Mem2},
    Cpu1 = Machine1#machine_state.cpu#cpu_state{c = 16#55, f = 0},
    Machine2 = Machine1#machine_state{cpu = Cpu1},
    Machine3 = z80_cpu:step(Machine2),
    Cpu3 = Machine3#machine_state.cpu,
    ?assertEqual(16#AA, Cpu3#cpu_state.c),        %% 01010101 -> 10101010
    ?assertEqual(0, Cpu3#cpu_state.f band ?FLAG_C),
    ?assertEqual(8, z80_cpu:t_states(Machine3)).

cb_sla_d_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#CB),  %% CB prefix
    Mem2 = ezx_mem:write_byte(Mem1, 1, 16#22),  %% SLA D
    Machine1 = Machine0#machine_state{memory = Mem2},
    Cpu1 = Machine1#machine_state.cpu#cpu_state{d = 16#01, f = 0},
    Machine2 = Machine1#machine_state{cpu = Cpu1},
    Machine3 = z80_cpu:step(Machine2),
    Cpu3 = Machine3#machine_state.cpu,
    ?assertEqual(16#02, Cpu3#cpu_state.d),
    ?assertEqual(8, z80_cpu:t_states(Machine3)).

cb_sla_a_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#CB),  %% CB prefix
    Mem2 = ezx_mem:write_byte(Mem1, 1, 16#27),  %% SLA A
    Machine1 = Machine0#machine_state{memory = Mem2},
    Cpu1 = Machine1#machine_state.cpu#cpu_state{a = 16#FF, f = 0},
    Machine2 = Machine1#machine_state{cpu = Cpu1},
    Machine3 = z80_cpu:step(Machine2),
    Cpu3 = Machine3#machine_state.cpu,
    ?assertEqual(16#FE, Cpu3#cpu_state.a),        %% 11111111 -> 11111110 (carry=1)
    ?assertEqual(?FLAG_C, Cpu3#cpu_state.f band ?FLAG_C),
    ?assertEqual(8, z80_cpu:t_states(Machine3)).

cb_sla_hl_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#CB),  %% CB prefix
    Mem2 = ezx_mem:write_byte(Mem1, 1, 16#26),  %% SLA (HL)
    Mem3 = ezx_mem:write_byte(Mem2, 16#4000, 16#40),  %% 01000000 -> 10000000, carry=0
    Machine1 = Machine0#machine_state{memory = Mem3, cpu = Machine0#machine_state.cpu#cpu_state{h = 16#40, l = 16#00}},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#80, ezx_emulator:read_byte(Machine2, 16#4000)),
    ?assertEqual(?FLAG_S, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_S),
    ?assertEqual(0, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_C),  %% carry from bit 7 = 0
    ?assertEqual(15, z80_cpu:t_states(Machine2)).

cb_sla_hl_carry_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#CB),
    Mem2 = ezx_mem:write_byte(Mem1, 1, 16#26),
    Mem3 = ezx_mem:write_byte(Mem2, 16#4000, 16#80),  %% 10000000 -> 00000000, carry=1
    Machine1 = Machine0#machine_state{memory = Mem3, cpu = Machine0#machine_state.cpu#cpu_state{h = 16#40, l = 16#00}},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#00, ezx_emulator:read_byte(Machine2, 16#4000)),
    ?assertEqual(?FLAG_C, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_C),
    ?assertEqual(?FLAG_Z, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_Z).

%% ============================================================================
%% SRA (Shift Right Arithmetic) - 0x28-0x2F
%% ============================================================================

cb_sra_b_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#CB),  %% CB prefix
    Mem2 = ezx_mem:write_byte(Mem1, 1, 16#28),  %% SRA B
    Machine1 = Machine0#machine_state{memory = Mem2},
    Cpu1 = Machine1#machine_state.cpu#cpu_state{b = 16#81, f = 0},
    Machine2 = Machine1#machine_state{cpu = Cpu1},
    Machine3 = z80_cpu:step(Machine2),
    Cpu3 = Machine3#machine_state.cpu,
    ?assertEqual(16#C0, Cpu3#cpu_state.b),        %% 10000001 -> 11000000 (carry=1, sign preserved)
    ?assertEqual(?FLAG_C, Cpu3#cpu_state.f band ?FLAG_C),
    ?assertEqual(?FLAG_S, Cpu3#cpu_state.f band ?FLAG_S),
    ?assertEqual(8, z80_cpu:t_states(Machine3)).

cb_sra_b_positive_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#CB),  %% CB prefix
    Mem2 = ezx_mem:write_byte(Mem1, 1, 16#28),  %% SRA B
    Machine1 = Machine0#machine_state{memory = Mem2},
    Cpu1 = Machine1#machine_state.cpu#cpu_state{b = 16#40, f = 0},
    Machine2 = Machine1#machine_state{cpu = Cpu1},
    Machine3 = z80_cpu:step(Machine2),
    Cpu3 = Machine3#machine_state.cpu,
    ?assertEqual(16#20, Cpu3#cpu_state.b),        %% 01000000 -> 00100000
    ?assertEqual(0, Cpu3#cpu_state.f band ?FLAG_C),
    ?assertEqual(0, Cpu3#cpu_state.f band ?FLAG_S),
    ?assertEqual(8, z80_cpu:t_states(Machine3)).

cb_sra_c_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#CB),  %% CB prefix
    Mem2 = ezx_mem:write_byte(Mem1, 1, 16#29),  %% SRA C
    Machine1 = Machine0#machine_state{memory = Mem2},
    Cpu1 = Machine1#machine_state.cpu#cpu_state{c = 16#FF, f = 0},
    Machine2 = Machine1#machine_state{cpu = Cpu1},
    Machine3 = z80_cpu:step(Machine2),
    Cpu3 = Machine3#machine_state.cpu,
    ?assertEqual(16#FF, Cpu3#cpu_state.c),        %% 11111111 -> 11111111 (carry=1, sign preserved)
    ?assertEqual(?FLAG_C, Cpu3#cpu_state.f band ?FLAG_C),
    ?assertEqual(8, z80_cpu:t_states(Machine3)).

cb_sra_a_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#CB),  %% CB prefix
    Mem2 = ezx_mem:write_byte(Mem1, 1, 16#2F),  %% SRA A
    Machine1 = Machine0#machine_state{memory = Mem2},
    Cpu1 = Machine1#machine_state.cpu#cpu_state{a = 16#02, f = 0},
    Machine2 = Machine1#machine_state{cpu = Cpu1},
    Machine3 = z80_cpu:step(Machine2),
    Cpu3 = Machine3#machine_state.cpu,
    ?assertEqual(16#01, Cpu3#cpu_state.a),        %% 00000010 -> 00000001
    ?assertEqual(0, Cpu3#cpu_state.f band ?FLAG_C),
    ?assertEqual(8, z80_cpu:t_states(Machine3)).

cb_sra_hl_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#CB),  %% CB prefix
    Mem2 = ezx_mem:write_byte(Mem1, 1, 16#2E),  %% SRA (HL)
    Mem3 = ezx_mem:write_byte(Mem2, 16#4000, 16#80),  %% 10000000 -> 11000000 (preserve sign)
    Machine1 = Machine0#machine_state{memory = Mem3, cpu = Machine0#machine_state.cpu#cpu_state{h = 16#40, l = 16#00}},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#C0, ezx_emulator:read_byte(Machine2, 16#4000)),
    ?assertEqual(?FLAG_S, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_S),
    ?assertEqual(15, z80_cpu:t_states(Machine2)).

cb_sra_hl_positive_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#CB),
    Mem2 = ezx_mem:write_byte(Mem1, 1, 16#2E),
    Mem3 = ezx_mem:write_byte(Mem2, 16#4000, 16#40),  %% 01000000 -> 00100000
    Machine1 = Machine0#machine_state{memory = Mem3, cpu = Machine0#machine_state.cpu#cpu_state{h = 16#40, l = 16#00}},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#20, ezx_emulator:read_byte(Machine2, 16#4000)),
    ?assertEqual(0, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_S),
    ?assertEqual(0, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_C).

cb_sra_hl_carry_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#CB),
    Mem2 = ezx_mem:write_byte(Mem1, 1, 16#2E),
    Mem3 = ezx_mem:write_byte(Mem2, 16#4000, 16#01),  %% 00000001 -> 00000000, carry=1
    Machine1 = Machine0#machine_state{memory = Mem3, cpu = Machine0#machine_state.cpu#cpu_state{h = 16#40, l = 16#00}},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#00, ezx_emulator:read_byte(Machine2, 16#4000)),
    ?assertEqual(?FLAG_C, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_C),
    ?assertEqual(?FLAG_Z, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_Z).

%% ============================================================================
%% SLL (Shift Left Logical, undocumented) - 0x30-0x37
%% ============================================================================

cb_sll_b_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#CB),  %% CB prefix
    Mem2 = ezx_mem:write_byte(Mem1, 1, 16#30),  %% SLL B (undocumented)
    Machine1 = Machine0#machine_state{memory = Mem2},
    Cpu1 = Machine1#machine_state.cpu#cpu_state{b = 16#80, f = 0},
    Machine2 = Machine1#machine_state{cpu = Cpu1},
    Machine3 = z80_cpu:step(Machine2),
    Cpu3 = Machine3#machine_state.cpu,
    ?assertEqual(16#01, Cpu3#cpu_state.b),        %% 10000000 -> 00000001 (bit 0 set to 1)
    ?assertEqual(?FLAG_C, Cpu3#cpu_state.f band ?FLAG_C),
    ?assertEqual(8, z80_cpu:t_states(Machine3)).

cb_sll_c_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#CB),  %% CB prefix
    Mem2 = ezx_mem:write_byte(Mem1, 1, 16#31),  %% SLL C
    Machine1 = Machine0#machine_state{memory = Mem2},
    Cpu1 = Machine1#machine_state.cpu#cpu_state{c = 16#40, f = 0},
    Machine2 = Machine1#machine_state{cpu = Cpu1},
    Machine3 = z80_cpu:step(Machine2),
    Cpu3 = Machine3#machine_state.cpu,
    ?assertEqual(16#81, Cpu3#cpu_state.c),        %% 01000000 -> 10000001
    ?assertEqual(0, Cpu3#cpu_state.f band ?FLAG_C),
    ?assertEqual(8, z80_cpu:t_states(Machine3)).

cb_sll_a_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#CB),  %% CB prefix
    Mem2 = ezx_mem:write_byte(Mem1, 1, 16#37),  %% SLL A
    Machine1 = Machine0#machine_state{memory = Mem2},
    Cpu1 = Machine1#machine_state.cpu#cpu_state{a = 16#55, f = 0},
    Machine2 = Machine1#machine_state{cpu = Cpu1},
    Machine3 = z80_cpu:step(Machine2),
    Cpu3 = Machine3#machine_state.cpu,
    ?assertEqual(16#AB, Cpu3#cpu_state.a),        %% 01010101 -> 10101011
    ?assertEqual(0, Cpu3#cpu_state.f band ?FLAG_C),
    ?assertEqual(8, z80_cpu:t_states(Machine3)).

cb_sll_hl_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#CB),  %% CB prefix
    Mem2 = ezx_mem:write_byte(Mem1, 1, 16#36),  %% SLL (HL)
    Mem3 = ezx_mem:write_byte(Mem2, 16#4000, 16#40),  %% 01000000 -> 10000001
    Machine1 = Machine0#machine_state{memory = Mem3, cpu = Machine0#machine_state.cpu#cpu_state{h = 16#40, l = 16#00}},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#81, ezx_emulator:read_byte(Machine2, 16#4000)),
    ?assertEqual(?FLAG_S, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_S),
    ?assertEqual(0, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_C),  %% carry from bit 7 = 0
    ?assertEqual(15, z80_cpu:t_states(Machine2)).

cb_sll_hl_carry_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#CB),
    Mem2 = ezx_mem:write_byte(Mem1, 1, 16#36),
    Mem3 = ezx_mem:write_byte(Mem2, 16#4000, 16#80),  %% 10000000 -> 00000001, carry=1
    Machine1 = Machine0#machine_state{memory = Mem3, cpu = Machine0#machine_state.cpu#cpu_state{h = 16#40, l = 16#00}},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#01, ezx_emulator:read_byte(Machine2, 16#4000)),
    ?assertEqual(?FLAG_C, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_C).

%% ============================================================================
%% SRL (Shift Right Logical) - 0x38-0x3F
%% ============================================================================

cb_srl_b_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#CB),  %% CB prefix
    Mem2 = ezx_mem:write_byte(Mem1, 1, 16#38),  %% SRL B
    Machine1 = Machine0#machine_state{memory = Mem2},
    Cpu1 = Machine1#machine_state.cpu#cpu_state{b = 16#81, f = 0},
    Machine2 = Machine1#machine_state{cpu = Cpu1},
    Machine3 = z80_cpu:step(Machine2),
    Cpu3 = Machine3#machine_state.cpu,
    ?assertEqual(16#40, Cpu3#cpu_state.b),        %% 10000001 -> 01000000 (carry=1, sign cleared)
    ?assertEqual(?FLAG_C, Cpu3#cpu_state.f band ?FLAG_C),
    ?assertEqual(0, Cpu3#cpu_state.f band ?FLAG_S),
    ?assertEqual(8, z80_cpu:t_states(Machine3)).

cb_srl_c_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#CB),  %% CB prefix
    Mem2 = ezx_mem:write_byte(Mem1, 1, 16#39),  %% SRL C
    Machine1 = Machine0#machine_state{memory = Mem2},
    Cpu1 = Machine1#machine_state.cpu#cpu_state{c = 16#02, f = 0},
    Machine2 = Machine1#machine_state{cpu = Cpu1},
    Machine3 = z80_cpu:step(Machine2),
    Cpu3 = Machine3#machine_state.cpu,
    ?assertEqual(16#01, Cpu3#cpu_state.c),        %% 00000010 -> 00000001
    ?assertEqual(0, Cpu3#cpu_state.f band ?FLAG_C),
    ?assertEqual(8, z80_cpu:t_states(Machine3)).

cb_srl_d_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#CB),  %% CB prefix
    Mem2 = ezx_mem:write_byte(Mem1, 1, 16#3A),  %% SRL D
    Machine1 = Machine0#machine_state{memory = Mem2},
    Cpu1 = Machine1#machine_state.cpu#cpu_state{d = 16#FF, f = 0},
    Machine2 = Machine1#machine_state{cpu = Cpu1},
    Machine3 = z80_cpu:step(Machine2),
    Cpu3 = Machine3#machine_state.cpu,
    ?assertEqual(16#7F, Cpu3#cpu_state.d),        %% 11111111 -> 01111111 (carry=1)
    ?assertEqual(?FLAG_C, Cpu3#cpu_state.f band ?FLAG_C),
    ?assertEqual(0, Cpu3#cpu_state.f band ?FLAG_S),
    ?assertEqual(8, z80_cpu:t_states(Machine3)).

cb_srl_a_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#CB),  %% CB prefix
    Mem2 = ezx_mem:write_byte(Mem1, 1, 16#3F),  %% SRL A
    Machine1 = Machine0#machine_state{memory = Mem2},
    Cpu1 = Machine1#machine_state.cpu#cpu_state{a = 16#01, f = 0},
    Machine2 = Machine1#machine_state{cpu = Cpu1},
    Machine3 = z80_cpu:step(Machine2),
    Cpu3 = Machine3#machine_state.cpu,
    ?assertEqual(16#00, Cpu3#cpu_state.a),        %% 00000001 -> 00000000 (carry=1)
    ?assertEqual(?FLAG_C, Cpu3#cpu_state.f band ?FLAG_C),
    ?assertEqual(?FLAG_Z, Cpu3#cpu_state.f band ?FLAG_Z),
    ?assertEqual(8, z80_cpu:t_states(Machine3)).

cb_srl_hl_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#CB),  %% CB prefix
    Mem2 = ezx_mem:write_byte(Mem1, 1, 16#3E),  %% SRL (HL)
    Mem3 = ezx_mem:write_byte(Mem2, 16#4000, 16#81),  %% 10000001 -> 01000000
    Machine1 = Machine0#machine_state{memory = Mem3, cpu = Machine0#machine_state.cpu#cpu_state{h = 16#40, l = 16#00}},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#40, ezx_emulator:read_byte(Machine2, 16#4000)),
    ?assertEqual(0, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_S),
    ?assertEqual(?FLAG_C, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_C),
    ?assertEqual(15, z80_cpu:t_states(Machine2)).

cb_srl_hl_carry_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#CB),
    Mem2 = ezx_mem:write_byte(Mem1, 1, 16#3E),
    Mem3 = ezx_mem:write_byte(Mem2, 16#4000, 16#01),  %% 00000001 -> 00000000
    Machine1 = Machine0#machine_state{memory = Mem3, cpu = Machine0#machine_state.cpu#cpu_state{h = 16#40, l = 16#00}},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#00, ezx_emulator:read_byte(Machine2, 16#4000)),
    ?assertEqual(?FLAG_C, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_C),
    ?assertEqual(?FLAG_Z, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_Z).

%% ============================================================================
%% BIT b,r - 0x40-0x7F
%% ============================================================================

cb_bit_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#CB),  %% CB prefix
    Mem2 = ezx_mem:write_byte(Mem1, 1, 16#40),  %% BIT 0,B
    Machine1 = Machine0#machine_state{memory = Mem2},
    Cpu1 = Machine1#machine_state.cpu#cpu_state{b = 16#01},
    Machine2 = Machine1#machine_state{cpu = Cpu1},
    Machine3 = z80_cpu:step(Machine2),
    Cpu3 = Machine3#machine_state.cpu,
    ?assertEqual(16#01, Cpu3#cpu_state.b),
    ?assertEqual(0, Cpu3#cpu_state.f band ?FLAG_Z),
    ?assertEqual(?FLAG_H, Cpu3#cpu_state.f band ?FLAG_H),
    ?assertEqual(0, Cpu3#cpu_state.f band ?FLAG_V),
    ?assertEqual(0, Cpu3#cpu_state.f band ?FLAG_N),
    ?assertEqual(8, z80_cpu:t_states(Machine3)).

cb_bit_zero_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#CB),  %% CB prefix
    Mem2 = ezx_mem:write_byte(Mem1, 1, 16#40),  %% BIT 0,B
    Machine1 = Machine0#machine_state{memory = Mem2},
    Cpu1 = Machine1#machine_state.cpu#cpu_state{b = 16#00},
    Machine2 = Machine1#machine_state{cpu = Cpu1},
    Machine3 = z80_cpu:step(Machine2),
    Cpu3 = Machine3#machine_state.cpu,
    ?assertEqual(?FLAG_Z, Cpu3#cpu_state.f band ?FLAG_Z),
    ?assertEqual(?FLAG_V, Cpu3#cpu_state.f band ?FLAG_V),
    ?assertEqual(8, z80_cpu:t_states(Machine3)).

cb_bit_1_b_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#CB),  %% CB prefix
    Mem2 = ezx_mem:write_byte(Mem1, 1, 16#48),  %% BIT 1,B
    Machine1 = Machine0#machine_state{memory = Mem2},
    Cpu1 = Machine1#machine_state.cpu#cpu_state{b = 16#02},
    Machine2 = Machine1#machine_state{cpu = Cpu1},
    Machine3 = z80_cpu:step(Machine2),
    Cpu3 = Machine3#machine_state.cpu,
    ?assertEqual(0, Cpu3#cpu_state.f band ?FLAG_Z),
    ?assertEqual(8, z80_cpu:t_states(Machine3)).

cb_bit_7_b_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#CB),  %% CB prefix
    Mem2 = ezx_mem:write_byte(Mem1, 1, 16#78),  %% BIT 7,B
    Machine1 = Machine0#machine_state{memory = Mem2},
    Cpu1 = Machine1#machine_state.cpu#cpu_state{b = 16#80},
    Machine2 = Machine1#machine_state{cpu = Cpu1},
    Machine3 = z80_cpu:step(Machine2),
    Cpu3 = Machine3#machine_state.cpu,
    ?assertEqual(0, Cpu3#cpu_state.f band ?FLAG_Z),
    ?assertEqual(?FLAG_S, Cpu3#cpu_state.f band ?FLAG_S),
    ?assertEqual(8, z80_cpu:t_states(Machine3)).

cb_bit_7_b_zero_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#CB),  %% CB prefix
    Mem2 = ezx_mem:write_byte(Mem1, 1, 16#78),  %% BIT 7,B
    Machine1 = Machine0#machine_state{memory = Mem2},
    Cpu1 = Machine1#machine_state.cpu#cpu_state{b = 16#7F},
    Machine2 = Machine1#machine_state{cpu = Cpu1},
    Machine3 = z80_cpu:step(Machine2),
    Cpu3 = Machine3#machine_state.cpu,
    ?assertEqual(?FLAG_Z, Cpu3#cpu_state.f band ?FLAG_Z),
    ?assertEqual(0, Cpu3#cpu_state.f band ?FLAG_S),
    ?assertEqual(8, z80_cpu:t_states(Machine3)).

cb_bit_0_c_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#CB),  %% CB prefix
    Mem2 = ezx_mem:write_byte(Mem1, 1, 16#41),  %% BIT 0,C
    Machine1 = Machine0#machine_state{memory = Mem2},
    Cpu1 = Machine1#machine_state.cpu#cpu_state{c = 16#01},
    Machine2 = Machine1#machine_state{cpu = Cpu1},
    Machine3 = z80_cpu:step(Machine2),
    Cpu3 = Machine3#machine_state.cpu,
    ?assertEqual(0, Cpu3#cpu_state.f band ?FLAG_Z),
    ?assertEqual(8, z80_cpu:t_states(Machine3)).

cb_bit_3_d_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#CB),  %% CB prefix
    Mem2 = ezx_mem:write_byte(Mem1, 1, 16#5A),  %% BIT 3,D
    Machine1 = Machine0#machine_state{memory = Mem2},
    Cpu1 = Machine1#machine_state.cpu#cpu_state{d = 16#08},
    Machine2 = Machine1#machine_state{cpu = Cpu1},
    Machine3 = z80_cpu:step(Machine2),
    Cpu3 = Machine3#machine_state.cpu,
    ?assertEqual(0, Cpu3#cpu_state.f band ?FLAG_Z),
    ?assertEqual(8, z80_cpu:t_states(Machine3)).

cb_bit_hl_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#CB),  %% CB prefix
    Mem2 = ezx_mem:write_byte(Mem1, 1, 16#46),  %% BIT 0,(HL)
    Mem3 = ezx_mem:write_byte(Mem2, 16#4000, 16#01),
    Machine1 = Machine0#machine_state{memory = Mem3},
    Cpu1 = Machine1#machine_state.cpu#cpu_state{h = 16#40, l = 16#00},
    Machine2 = Machine1#machine_state{cpu = Cpu1},
    Machine3 = z80_cpu:step(Machine2),
    ?assertEqual(12, z80_cpu:t_states(Machine3)).

cb_bit_5_hl_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#CB),  %% CB prefix
    Mem2 = ezx_mem:write_byte(Mem1, 1, 16#6E),  %% BIT 5,(HL)
    Mem3 = ezx_mem:write_byte(Mem2, 16#4000, 16#20),
    Machine1 = Machine0#machine_state{memory = Mem3},
    Cpu1 = Machine1#machine_state.cpu#cpu_state{h = 16#40, l = 16#00},
    Machine2 = Machine1#machine_state{cpu = Cpu1},
    Machine3 = z80_cpu:step(Machine2),
    ?assertEqual(12, z80_cpu:t_states(Machine3)).

cb_bit_7_a_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#CB),  %% CB prefix
    Mem2 = ezx_mem:write_byte(Mem1, 1, 16#7F),  %% BIT 7,A
    Machine1 = Machine0#machine_state{memory = Mem2},
    Cpu1 = Machine1#machine_state.cpu#cpu_state{a = 16#80},
    Machine2 = Machine1#machine_state{cpu = Cpu1},
    Machine3 = z80_cpu:step(Machine2),
    Cpu3 = Machine3#machine_state.cpu,
    ?assertEqual(0, Cpu3#cpu_state.f band ?FLAG_Z),
    ?assertEqual(?FLAG_S, Cpu3#cpu_state.f band ?FLAG_S),
    ?assertEqual(8, z80_cpu:t_states(Machine3)).

%% ============================================================================
%% RES b,r - 0x80-0xBF
%% ============================================================================

cb_res_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#CB),  %% CB prefix
    Mem2 = ezx_mem:write_byte(Mem1, 1, 16#80),  %% RES 0,B
    Machine1 = Machine0#machine_state{memory = Mem2},
    Cpu1 = Machine1#machine_state.cpu#cpu_state{b = 16#03},
    Machine2 = Machine1#machine_state{cpu = Cpu1},
    Machine3 = z80_cpu:step(Machine2),
    Cpu3 = Machine3#machine_state.cpu,
    ?assertEqual(16#02, Cpu3#cpu_state.b),
    ?assertEqual(8, z80_cpu:t_states(Machine3)).

cb_res_1_b_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#CB),  %% CB prefix
    Mem2 = ezx_mem:write_byte(Mem1, 1, 16#88),  %% RES 1,B
    Machine1 = Machine0#machine_state{memory = Mem2},
    Cpu1 = Machine1#machine_state.cpu#cpu_state{b = 16#06},
    Machine2 = Machine1#machine_state{cpu = Cpu1},
    Machine3 = z80_cpu:step(Machine2),
    Cpu3 = Machine3#machine_state.cpu,
    ?assertEqual(16#04, Cpu3#cpu_state.b),
    ?assertEqual(8, z80_cpu:t_states(Machine3)).

cb_res_7_b_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#CB),  %% CB prefix
    Mem2 = ezx_mem:write_byte(Mem1, 1, 16#B8),  %% RES 7,B
    Machine1 = Machine0#machine_state{memory = Mem2},
    Cpu1 = Machine1#machine_state.cpu#cpu_state{b = 16#FF},
    Machine2 = Machine1#machine_state{cpu = Cpu1},
    Machine3 = z80_cpu:step(Machine2),
    Cpu3 = Machine3#machine_state.cpu,
    ?assertEqual(16#7F, Cpu3#cpu_state.b),
    ?assertEqual(8, z80_cpu:t_states(Machine3)).

cb_res_0_c_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#CB),  %% CB prefix
    Mem2 = ezx_mem:write_byte(Mem1, 1, 16#81),  %% RES 0,C
    Machine1 = Machine0#machine_state{memory = Mem2},
    Cpu1 = Machine1#machine_state.cpu#cpu_state{c = 16#FF},
    Machine2 = Machine1#machine_state{cpu = Cpu1},
    Machine3 = z80_cpu:step(Machine2),
    Cpu3 = Machine3#machine_state.cpu,
    ?assertEqual(16#FE, Cpu3#cpu_state.c),
    ?assertEqual(8, z80_cpu:t_states(Machine3)).

cb_res_3_e_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#CB),  %% CB prefix
    Mem2 = ezx_mem:write_byte(Mem1, 1, 16#9B),  %% RES 3,E
    Machine1 = Machine0#machine_state{memory = Mem2},
    Cpu1 = Machine1#machine_state.cpu#cpu_state{e = 16#F8},
    Machine2 = Machine1#machine_state{cpu = Cpu1},
    Machine3 = z80_cpu:step(Machine2),
    Cpu3 = Machine3#machine_state.cpu,
    ?assertEqual(16#F0, Cpu3#cpu_state.e),
    ?assertEqual(8, z80_cpu:t_states(Machine3)).

cb_res_hl_test() ->
    Machine0 = ezx_emulator:init(),
    Machine1 = ezx_emulator:write_byte(Machine0, 0, 16#CB),  %% CB prefix
    Machine2 = ezx_emulator:write_byte(Machine1, 1, 16#86),  %% RES 0,(HL)
    Machine3 = ezx_emulator:write_byte(Machine2, 16#4000, 16#03),
    Cpu5 = Machine3#machine_state.cpu#cpu_state{h = 16#40, l = 16#00},
    Machine6 = Machine3#machine_state{cpu = Cpu5},
    Machine7 = z80_cpu:step(Machine6),
    ?assertEqual(16#02, ezx_emulator:read_byte(Machine7, 16#4000)),
    ?assertEqual(15, z80_cpu:t_states(Machine7)).

cb_res_4_hl_test() ->
    Machine0 = ezx_emulator:init(),
    Machine1 = ezx_emulator:write_byte(Machine0, 0, 16#CB),  %% CB prefix
    Machine2 = ezx_emulator:write_byte(Machine1, 1, 16#A6),  %% RES 4,(HL)
    Machine3 = ezx_emulator:write_byte(Machine2, 16#4000, 16#FF),
    Cpu5 = Machine3#machine_state.cpu#cpu_state{h = 16#40, l = 16#00},
    Machine6 = Machine3#machine_state{cpu = Cpu5},
    Machine7 = z80_cpu:step(Machine6),
    ?assertEqual(16#EF, ezx_emulator:read_byte(Machine7, 16#4000)),
    ?assertEqual(15, z80_cpu:t_states(Machine7)).

cb_res_7_a_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#CB),  %% CB prefix
    Mem2 = ezx_mem:write_byte(Mem1, 1, 16#BF),  %% RES 7,A
    Machine1 = Machine0#machine_state{memory = Mem2},
    Cpu1 = Machine1#machine_state.cpu#cpu_state{a = 16#FF},
    Machine2 = Machine1#machine_state{cpu = Cpu1},
    Machine3 = z80_cpu:step(Machine2),
    Cpu3 = Machine3#machine_state.cpu,
    ?assertEqual(16#7F, Cpu3#cpu_state.a),
    ?assertEqual(8, z80_cpu:t_states(Machine3)).

%% ============================================================================
%% SET b,r - 0xC0-0xFF
%% ============================================================================

cb_set_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#CB),  %% CB prefix
    Mem2 = ezx_mem:write_byte(Mem1, 1, 16#C0),  %% SET 0,B
    Machine1 = Machine0#machine_state{memory = Mem2},
    Cpu1 = Machine1#machine_state.cpu#cpu_state{b = 16#02},
    Machine2 = Machine1#machine_state{cpu = Cpu1},
    Machine3 = z80_cpu:step(Machine2),
    Cpu3 = Machine3#machine_state.cpu,
    ?assertEqual(16#03, Cpu3#cpu_state.b),
    ?assertEqual(8, z80_cpu:t_states(Machine3)).

cb_set_1_b_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#CB),  %% CB prefix
    Mem2 = ezx_mem:write_byte(Mem1, 1, 16#C8),  %% SET 1,B
    Machine1 = Machine0#machine_state{memory = Mem2},
    Cpu1 = Machine1#machine_state.cpu#cpu_state{b = 16#01},
    Machine2 = Machine1#machine_state{cpu = Cpu1},
    Machine3 = z80_cpu:step(Machine2),
    Cpu3 = Machine3#machine_state.cpu,
    ?assertEqual(16#03, Cpu3#cpu_state.b),
    ?assertEqual(8, z80_cpu:t_states(Machine3)).

cb_set_7_b_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#CB),  %% CB prefix
    Mem2 = ezx_mem:write_byte(Mem1, 1, 16#F8),  %% SET 7,B
    Machine1 = Machine0#machine_state{memory = Mem2},
    Cpu1 = Machine1#machine_state.cpu#cpu_state{b = 16#00},
    Machine2 = Machine1#machine_state{cpu = Cpu1},
    Machine3 = z80_cpu:step(Machine2),
    Cpu3 = Machine3#machine_state.cpu,
    ?assertEqual(16#80, Cpu3#cpu_state.b),
    ?assertEqual(8, z80_cpu:t_states(Machine3)).

cb_set_0_c_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#CB),  %% CB prefix
    Mem2 = ezx_mem:write_byte(Mem1, 1, 16#C1),  %% SET 0,C
    Machine1 = Machine0#machine_state{memory = Mem2},
    Cpu1 = Machine1#machine_state.cpu#cpu_state{c = 16#FE},
    Machine2 = Machine1#machine_state{cpu = Cpu1},
    Machine3 = z80_cpu:step(Machine2),
    Cpu3 = Machine3#machine_state.cpu,
    ?assertEqual(16#FF, Cpu3#cpu_state.c),
    ?assertEqual(8, z80_cpu:t_states(Machine3)).

cb_set_5_d_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#CB),  %% CB prefix
    Mem2 = ezx_mem:write_byte(Mem1, 1, 16#EA),  %% SET 5,D
    Machine1 = Machine0#machine_state{memory = Mem2},
    Cpu1 = Machine1#machine_state.cpu#cpu_state{d = 16#00},
    Machine2 = Machine1#machine_state{cpu = Cpu1},
    Machine3 = z80_cpu:step(Machine2),
    Cpu3 = Machine3#machine_state.cpu,
    ?assertEqual(16#20, Cpu3#cpu_state.d),
    ?assertEqual(8, z80_cpu:t_states(Machine3)).

cb_set_hl_test() ->
    Machine0 = ezx_emulator:init(),
    Machine1 = ezx_emulator:write_byte(Machine0, 0, 16#CB),  %% CB prefix
    Machine2 = ezx_emulator:write_byte(Machine1, 1, 16#C6),  %% SET 0,(HL)
    Machine3 = ezx_emulator:write_byte(Machine2, 16#4000, 16#02),
    Cpu5 = Machine3#machine_state.cpu#cpu_state{h = 16#40, l = 16#00},
    Machine6 = Machine3#machine_state{cpu = Cpu5},
    Machine7 = z80_cpu:step(Machine6),
    ?assertEqual(16#03, ezx_emulator:read_byte(Machine7, 16#4000)),
    ?assertEqual(15, z80_cpu:t_states(Machine7)).

cb_set_2_hl_test() ->
    Machine0 = ezx_emulator:init(),
    Machine1 = ezx_emulator:write_byte(Machine0, 0, 16#CB),  %% CB prefix
    Machine2 = ezx_emulator:write_byte(Machine1, 1, 16#D6),  %% SET 2,(HL)
    Machine3 = ezx_emulator:write_byte(Machine2, 16#4000, 16#F3),
    Cpu5 = Machine3#machine_state.cpu#cpu_state{h = 16#40, l = 16#00},
    Machine6 = Machine3#machine_state{cpu = Cpu5},
    Machine7 = z80_cpu:step(Machine6),
    ?assertEqual(16#F7, ezx_emulator:read_byte(Machine7, 16#4000)),
    ?assertEqual(15, z80_cpu:t_states(Machine7)).

cb_set_7_a_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_mem:write_byte(Mem0, 0, 16#CB),  %% CB prefix
    Mem2 = ezx_mem:write_byte(Mem1, 1, 16#FF),  %% SET 7,A
    Machine1 = Machine0#machine_state{memory = Mem2},
    Cpu1 = Machine1#machine_state.cpu#cpu_state{a = 16#00},
    Machine2 = Machine1#machine_state{cpu = Cpu1},
    Machine3 = z80_cpu:step(Machine2),
    Cpu3 = Machine3#machine_state.cpu,
    ?assertEqual(16#80, Cpu3#cpu_state.a),
    ?assertEqual(8, z80_cpu:t_states(Machine3)).