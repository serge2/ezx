-module(z80_cpu_index_cb_tests).

-include("z80_records.hrl").
-include_lib("eunit/include/eunit.hrl").

%% ============================================================================
%% DD CB RLC (IX+d) - 0x06
%% ============================================================================
dd_cb_rlc_ix_zero_disp_test() ->
    %% RLC (IX+0): 0x80 -> 0x01, C=1, S=0, Z=0
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_memory_48:cpu_write_byte(Mem0, 16#4000, 16#80),           %% value at (IX+0)
    Mem2 = ezx_memory_48:cpu_write_byte(Mem1, 0, 16#DD),                 %% DD prefix
    Mem3 = ezx_memory_48:cpu_write_byte(Mem2, 1, 16#CB),                 %% CB prefix
    Mem4 = ezx_memory_48:cpu_write_byte(Mem3, 2, 16#00),                 %% displacement 0
    Mem5 = ezx_memory_48:cpu_write_byte(Mem4, 3, 16#06),                 %% RLC (IX+0)
    Machine1 = Machine0#machine_state{memory = Mem5, cpu = Machine0#machine_state.cpu#cpu_state{ixh = 16#40, ixl = 16#00}},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#01, ezx_memory_48:cpu_read_byte(Machine2#machine_state.memory, 16#4000)),
    ?assertEqual(?FLAG_C, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_C),
    ?assertEqual(0, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_Z),
    ?assertEqual(0, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_S),
    ?assertEqual(none, Machine2#machine_state.cpu#cpu_state.prefix).

dd_cb_rlc_ix_pos_disp_test() ->
    %% RLC (IX+5): 0x40 -> 0x80, C=0, S=1, Z=0
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_memory_48:cpu_write_byte(Mem0, 16#4005, 16#40),           %% value at (IX+5)
    Mem2 = ezx_memory_48:cpu_write_byte(Mem1, 0, 16#DD),                 %% DD prefix
    Mem3 = ezx_memory_48:cpu_write_byte(Mem2, 1, 16#CB),                 %% CB prefix
    Mem4 = ezx_memory_48:cpu_write_byte(Mem3, 2, 16#05),                 %% displacement +5
    Mem5 = ezx_memory_48:cpu_write_byte(Mem4, 3, 16#06),                 %% RLC (IX+5)
    Machine1 = Machine0#machine_state{memory = Mem5, cpu = Machine0#machine_state.cpu#cpu_state{ixh = 16#40, ixl = 16#00}},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#80, ezx_memory_48:cpu_read_byte(Machine2#machine_state.memory, 16#4005)),
    ?assertEqual(0, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_C),
    ?assertEqual(?FLAG_S, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_S),
    ?assertEqual(0, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_Z).

dd_cb_rlc_ix_neg_disp_test() ->
    %% RLC (IX-1): 0x01 -> 0x02, C=0, S=0, Z=0
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_memory_48:cpu_write_byte(Mem0, 16#3FFF, 16#01),           %% value at (IX-1)
    Mem2 = ezx_memory_48:cpu_write_byte(Mem1, 0, 16#DD),                 %% DD prefix
    Mem3 = ezx_memory_48:cpu_write_byte(Mem2, 1, 16#CB),                 %% CB prefix
    Mem4 = ezx_memory_48:cpu_write_byte(Mem3, 2, 16#FF),                 %% displacement -1 (0xFF)
    Mem5 = ezx_memory_48:cpu_write_byte(Mem4, 3, 16#06),                 %% RLC (IX-1)
    Machine1 = Machine0#machine_state{memory = Mem5, cpu = Machine0#machine_state.cpu#cpu_state{ixh = 16#40, ixl = 16#00}},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#02, ezx_memory_48:cpu_read_byte(Machine2#machine_state.memory, 16#3FFF)),
    ?assertEqual(0, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_C).

dd_cb_rlc_ix_zero_result_test() ->
    %% RLC (IX+0): 0x00 -> 0x00, C=0, Z=1
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_memory_48:cpu_write_byte(Mem0, 16#4000, 16#00),           %% value at (IX+0)
    Mem2 = ezx_memory_48:cpu_write_byte(Mem1, 0, 16#DD),                 %% DD prefix
    Mem3 = ezx_memory_48:cpu_write_byte(Mem2, 1, 16#CB),                 %% CB prefix
    Mem4 = ezx_memory_48:cpu_write_byte(Mem3, 2, 16#00),                 %% displacement 0
    Mem5 = ezx_memory_48:cpu_write_byte(Mem4, 3, 16#06),                 %% RLC (IX+0)
    Machine1 = Machine0#machine_state{memory = Mem5, cpu = Machine0#machine_state.cpu#cpu_state{ixh = 16#40, ixl = 16#00}},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#00, ezx_memory_48:cpu_read_byte(Machine2#machine_state.memory, 16#4000)),
    ?assertEqual(?FLAG_Z, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_Z),
    ?assertEqual(0, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_C).

%% ============================================================================
%% FD CB RLC (IY+d) - 0x06
%% ============================================================================
fd_cb_rlc_iy_test() ->
    %% RLC (IY+0): 0x80 -> 0x01, C=1
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_memory_48:cpu_write_byte(Mem0, 16#5000, 16#80),           %% value at (IY+0)
    Mem2 = ezx_memory_48:cpu_write_byte(Mem1, 0, 16#FD),                 %% FD prefix
    Mem3 = ezx_memory_48:cpu_write_byte(Mem2, 1, 16#CB),                 %% CB prefix
    Mem4 = ezx_memory_48:cpu_write_byte(Mem3, 2, 16#00),                 %% displacement 0
    Mem5 = ezx_memory_48:cpu_write_byte(Mem4, 3, 16#06),                 %% RLC (IY+0)
    Machine1 = Machine0#machine_state{memory = Mem5, cpu = Machine0#machine_state.cpu#cpu_state{iyh = 16#50, iyl = 16#00}},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#01, ezx_memory_48:cpu_read_byte(Machine2#machine_state.memory, 16#5000)),
    ?assertEqual(?FLAG_C, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_C).

%% ============================================================================
%% DD CB RRC (IX+d) - 0x0E
%% ============================================================================
dd_cb_rrc_ix_test() ->
    %% RRC (IX+0): 0x01 -> 0x80, C=1, S=1
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_memory_48:cpu_write_byte(Mem0, 16#4000, 16#01),           %% value at (IX+0)
    Mem2 = ezx_memory_48:cpu_write_byte(Mem1, 0, 16#DD),                 %% DD prefix
    Mem3 = ezx_memory_48:cpu_write_byte(Mem2, 1, 16#CB),                 %% CB prefix
    Mem4 = ezx_memory_48:cpu_write_byte(Mem3, 2, 16#00),                 %% displacement 0
    Mem5 = ezx_memory_48:cpu_write_byte(Mem4, 3, 16#0E),                 %% RRC (IX+0)
    Machine1 = Machine0#machine_state{memory = Mem5, cpu = Machine0#machine_state.cpu#cpu_state{ixh = 16#40, ixl = 16#00}},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#80, ezx_memory_48:cpu_read_byte(Machine2#machine_state.memory, 16#4000)),
    ?assertEqual(?FLAG_C, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_C),
    ?assertEqual(?FLAG_S, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_S).

dd_cb_rrc_ix_zero_result_test() ->
    %% RRC (IX+0): 0x00 -> 0x00, C=0, Z=1
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_memory_48:cpu_write_byte(Mem0, 16#4000, 16#00),           %% value at (IX+0)
    Mem2 = ezx_memory_48:cpu_write_byte(Mem1, 0, 16#DD),                 %% DD prefix
    Mem3 = ezx_memory_48:cpu_write_byte(Mem2, 1, 16#CB),                 %% CB prefix
    Mem4 = ezx_memory_48:cpu_write_byte(Mem3, 2, 16#00),                 %% displacement 0
    Mem5 = ezx_memory_48:cpu_write_byte(Mem4, 3, 16#0E),                 %% RRC (IX+0)
    Machine1 = Machine0#machine_state{memory = Mem5, cpu = Machine0#machine_state.cpu#cpu_state{ixh = 16#40, ixl = 16#00}},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#00, ezx_memory_48:cpu_read_byte(Machine2#machine_state.memory, 16#4000)),
    ?assertEqual(?FLAG_Z, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_Z).

%% ============================================================================
%% DD CB RL (IX+d) - 0x16
%% ============================================================================
dd_cb_rl_ix_test() ->
    %% RL (IX+0): 0x7F with C=0 -> 0xFE, C=0
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_memory_48:cpu_write_byte(Mem0, 16#4000, 16#7F),           %% value at (IX+0)
    Mem2 = ezx_memory_48:cpu_write_byte(Mem1, 0, 16#DD),                 %% DD prefix
    Mem3 = ezx_memory_48:cpu_write_byte(Mem2, 1, 16#CB),                 %% CB prefix
    Mem4 = ezx_memory_48:cpu_write_byte(Mem3, 2, 16#00),                 %% displacement 0
    Mem5 = ezx_memory_48:cpu_write_byte(Mem4, 3, 16#16),                 %% RL (IX+0)
    Machine1 = Machine0#machine_state{memory = Mem5, cpu = Machine0#machine_state.cpu#cpu_state{ixh = 16#40, ixl = 16#00, f = 0}},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#FE, ezx_memory_48:cpu_read_byte(Machine2#machine_state.memory, 16#4000)),
    ?assertEqual(0, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_C).

dd_cb_rl_ix_with_carry_test() ->
    %% RL (IX+0): 0x7F with C=1 -> 0xFF, C=0
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_memory_48:cpu_write_byte(Mem0, 16#4000, 16#7F),           %% value at (IX+0)
    Mem2 = ezx_memory_48:cpu_write_byte(Mem1, 0, 16#DD),                 %% DD prefix
    Mem3 = ezx_memory_48:cpu_write_byte(Mem2, 1, 16#CB),                 %% CB prefix
    Mem4 = ezx_memory_48:cpu_write_byte(Mem3, 2, 16#00),                 %% displacement 0
    Mem5 = ezx_memory_48:cpu_write_byte(Mem4, 3, 16#16),                 %% RL (IX+0)
    Machine1 = Machine0#machine_state{memory = Mem5, cpu = Machine0#machine_state.cpu#cpu_state{ixh = 16#40, ixl = 16#00, f = ?FLAG_C}},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#FF, ezx_memory_48:cpu_read_byte(Machine2#machine_state.memory, 16#4000)),
    ?assertEqual(0, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_C).

dd_cb_rl_ix_carry_out_test() ->
    %% RL (IX+0): 0x80 with C=1 -> 0x01, C=1 (bit 7 goes to carry, old carry goes to bit 0)
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_memory_48:cpu_write_byte(Mem0, 16#4000, 16#80),           %% value at (IX+0)
    Mem2 = ezx_memory_48:cpu_write_byte(Mem1, 0, 16#DD),                 %% DD prefix
    Mem3 = ezx_memory_48:cpu_write_byte(Mem2, 1, 16#CB),                 %% CB prefix
    Mem4 = ezx_memory_48:cpu_write_byte(Mem3, 2, 16#00),                 %% displacement 0
    Mem5 = ezx_memory_48:cpu_write_byte(Mem4, 3, 16#16),                 %% RL (IX+0)
    Machine1 = Machine0#machine_state{memory = Mem5, cpu = Machine0#machine_state.cpu#cpu_state{ixh = 16#40, ixl = 16#00, f = ?FLAG_C}},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#01, ezx_memory_48:cpu_read_byte(Machine2#machine_state.memory, 16#4000)),
    ?assertEqual(?FLAG_C, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_C).

%% ============================================================================
%% DD CB RR (IX+d) - 0x1E
%% ============================================================================
dd_cb_rr_ix_test() ->
    %% RR (IX+0): 0x01 with C=0 -> 0x00, C=1, Z=1
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_memory_48:cpu_write_byte(Mem0, 16#4000, 16#01),           %% value at (IX+0)
    Mem2 = ezx_memory_48:cpu_write_byte(Mem1, 0, 16#DD),                 %% DD prefix
    Mem3 = ezx_memory_48:cpu_write_byte(Mem2, 1, 16#CB),                 %% CB prefix
    Mem4 = ezx_memory_48:cpu_write_byte(Mem3, 2, 16#00),                 %% displacement 0
    Mem5 = ezx_memory_48:cpu_write_byte(Mem4, 3, 16#1E),                 %% RR (IX+0)
    Machine1 = Machine0#machine_state{memory = Mem5, cpu = Machine0#machine_state.cpu#cpu_state{ixh = 16#40, ixl = 16#00, f = 0}},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#00, ezx_memory_48:cpu_read_byte(Machine2#machine_state.memory, 16#4000)),
    ?assertEqual(?FLAG_C, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_C),
    ?assertEqual(?FLAG_Z, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_Z).

dd_cb_rr_ix_with_carry_test() ->
    %% RR (IX+0): 0x00 with C=1 -> 0x80, C=0, S=1
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_memory_48:cpu_write_byte(Mem0, 16#4000, 16#00),           %% value at (IX+0)
    Mem2 = ezx_memory_48:cpu_write_byte(Mem1, 0, 16#DD),                 %% DD prefix
    Mem3 = ezx_memory_48:cpu_write_byte(Mem2, 1, 16#CB),                 %% CB prefix
    Mem4 = ezx_memory_48:cpu_write_byte(Mem3, 2, 16#00),                 %% displacement 0
    Mem5 = ezx_memory_48:cpu_write_byte(Mem4, 3, 16#1E),                 %% RR (IX+0)
    Machine1 = Machine0#machine_state{memory = Mem5, cpu = Machine0#machine_state.cpu#cpu_state{ixh = 16#40, ixl = 16#00, f = ?FLAG_C}},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#80, ezx_memory_48:cpu_read_byte(Machine2#machine_state.memory, 16#4000)),
    ?assertEqual(?FLAG_S, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_S).

%% ============================================================================
%% DD CB SLA (IX+d) - 0x26
%% ============================================================================
dd_cb_sla_ix_test() ->
    %% SLA (IX+0): 0x40 -> 0x80, C=0, S=1
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_memory_48:cpu_write_byte(Mem0, 16#4000, 16#40),           %% value at (IX+0)
    Mem2 = ezx_memory_48:cpu_write_byte(Mem1, 0, 16#DD),                 %% DD prefix
    Mem3 = ezx_memory_48:cpu_write_byte(Mem2, 1, 16#CB),                 %% CB prefix
    Mem4 = ezx_memory_48:cpu_write_byte(Mem3, 2, 16#00),                 %% displacement 0
    Mem5 = ezx_memory_48:cpu_write_byte(Mem4, 3, 16#26),                 %% SLA (IX+0)
    Machine1 = Machine0#machine_state{memory = Mem5, cpu = Machine0#machine_state.cpu#cpu_state{ixh = 16#40, ixl = 16#00}},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#80, ezx_memory_48:cpu_read_byte(Machine2#machine_state.memory, 16#4000)),
    ?assertEqual(?FLAG_S, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_S).

dd_cb_sla_ix_carry_test() ->
    %% SLA (IX+0): 0x80 -> 0x00, C=1, Z=1
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_memory_48:cpu_write_byte(Mem0, 16#4000, 16#80),           %% value at (IX+0)
    Mem2 = ezx_memory_48:cpu_write_byte(Mem1, 0, 16#DD),                 %% DD prefix
    Mem3 = ezx_memory_48:cpu_write_byte(Mem2, 1, 16#CB),                 %% CB prefix
    Mem4 = ezx_memory_48:cpu_write_byte(Mem3, 2, 16#00),                 %% displacement 0
    Mem5 = ezx_memory_48:cpu_write_byte(Mem4, 3, 16#26),                 %% SLA (IX+0)
    Machine1 = Machine0#machine_state{memory = Mem5, cpu = Machine0#machine_state.cpu#cpu_state{ixh = 16#40, ixl = 16#00}},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#00, ezx_memory_48:cpu_read_byte(Machine2#machine_state.memory, 16#4000)),
    ?assertEqual(?FLAG_C, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_C),
    ?assertEqual(?FLAG_Z, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_Z).

%% ============================================================================
%% DD CB SRA (IX+d) - 0x2E
%% ============================================================================
dd_cb_sra_ix_test() ->
    %% SRA (IX+0): 0x80 -> 0xC0, C=0, S=1 (arithmetic shift preserves sign)
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_memory_48:cpu_write_byte(Mem0, 16#4000, 16#80),           %% value at (IX+0)
    Mem2 = ezx_memory_48:cpu_write_byte(Mem1, 0, 16#DD),                 %% DD prefix
    Mem3 = ezx_memory_48:cpu_write_byte(Mem2, 1, 16#CB),                 %% CB prefix
    Mem4 = ezx_memory_48:cpu_write_byte(Mem3, 2, 16#00),                 %% displacement 0
    Mem5 = ezx_memory_48:cpu_write_byte(Mem4, 3, 16#2E),                 %% SRA (IX+0)
    Machine1 = Machine0#machine_state{memory = Mem5, cpu = Machine0#machine_state.cpu#cpu_state{ixh = 16#40, ixl = 16#00}},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#C0, ezx_memory_48:cpu_read_byte(Machine2#machine_state.memory, 16#4000)),
    ?assertEqual(?FLAG_S, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_S).

dd_cb_sra_ix_positive_test() ->
    %% SRA (IX+0): 0x40 -> 0x20, C=0, S=0
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_memory_48:cpu_write_byte(Mem0, 16#4000, 16#40),
    Mem2 = ezx_memory_48:cpu_write_byte(Mem1, 0, 16#DD),
    Mem3 = ezx_memory_48:cpu_write_byte(Mem2, 1, 16#CB),
    Mem4 = ezx_memory_48:cpu_write_byte(Mem3, 2, 16#00),
    Mem5 = ezx_memory_48:cpu_write_byte(Mem4, 3, 16#2E),
    Machine1 = Machine0#machine_state{memory = Mem5, cpu = Machine0#machine_state.cpu#cpu_state{ixh = 16#40, ixl = 16#00}},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#20, ezx_memory_48:cpu_read_byte(Machine2#machine_state.memory, 16#4000)),
    ?assertEqual(0, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_S).

dd_cb_sra_ix_carry_test() ->
    %% SRA (IX+0): 0x01 -> 0x00, C=1, Z=1
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_memory_48:cpu_write_byte(Mem0, 16#4000, 16#01),
    Mem2 = ezx_memory_48:cpu_write_byte(Mem1, 0, 16#DD),
    Mem3 = ezx_memory_48:cpu_write_byte(Mem2, 1, 16#CB),
    Mem4 = ezx_memory_48:cpu_write_byte(Mem3, 2, 16#00),
    Mem5 = ezx_memory_48:cpu_write_byte(Mem4, 3, 16#2E),
    Machine1 = Machine0#machine_state{memory = Mem5, cpu = Machine0#machine_state.cpu#cpu_state{ixh = 16#40, ixl = 16#00}},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#00, ezx_memory_48:cpu_read_byte(Machine2#machine_state.memory, 16#4000)),
    ?assertEqual(?FLAG_C, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_C),
    ?assertEqual(?FLAG_Z, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_Z).

%% ============================================================================
%% DD CB SLL (IX+d) - 0x36 (undocumented)
%% ============================================================================
dd_cb_sll_ix_test() ->
    %% SLL (IX+0): 0x40 -> 0x81, C=0, S=1
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_memory_48:cpu_write_byte(Mem0, 16#4000, 16#40),
    Mem2 = ezx_memory_48:cpu_write_byte(Mem1, 0, 16#DD),
    Mem3 = ezx_memory_48:cpu_write_byte(Mem2, 1, 16#CB),
    Mem4 = ezx_memory_48:cpu_write_byte(Mem3, 2, 16#00),
    Mem5 = ezx_memory_48:cpu_write_byte(Mem4, 3, 16#36),
    Machine1 = Machine0#machine_state{memory = Mem5, cpu = Machine0#machine_state.cpu#cpu_state{ixh = 16#40, ixl = 16#00}},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#81, ezx_memory_48:cpu_read_byte(Machine2#machine_state.memory, 16#4000)),
    ?assertEqual(?FLAG_S, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_S).

dd_cb_sll_ix_carry_test() ->
    %% SLL (IX+0): 0x80 -> 0x01, C=1
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_memory_48:cpu_write_byte(Mem0, 16#4000, 16#80),
    Mem2 = ezx_memory_48:cpu_write_byte(Mem1, 0, 16#DD),
    Mem3 = ezx_memory_48:cpu_write_byte(Mem2, 1, 16#CB),
    Mem4 = ezx_memory_48:cpu_write_byte(Mem3, 2, 16#00),
    Mem5 = ezx_memory_48:cpu_write_byte(Mem4, 3, 16#36),
    Machine1 = Machine0#machine_state{memory = Mem5, cpu = Machine0#machine_state.cpu#cpu_state{ixh = 16#40, ixl = 16#00}},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#01, ezx_memory_48:cpu_read_byte(Machine2#machine_state.memory, 16#4000)),
    ?assertEqual(?FLAG_C, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_C).

%% ============================================================================
%% DD CB SRL (IX+d) - 0x3E
%% ============================================================================
dd_cb_srl_ix_test() ->
    %% SRL (IX+0): 0x80 -> 0x40, C=0, S=0
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_memory_48:cpu_write_byte(Mem0, 16#4000, 16#80),
    Mem2 = ezx_memory_48:cpu_write_byte(Mem1, 0, 16#DD),
    Mem3 = ezx_memory_48:cpu_write_byte(Mem2, 1, 16#CB),
    Mem4 = ezx_memory_48:cpu_write_byte(Mem3, 2, 16#00),
    Mem5 = ezx_memory_48:cpu_write_byte(Mem4, 3, 16#3E),
    Machine1 = Machine0#machine_state{memory = Mem5, cpu = Machine0#machine_state.cpu#cpu_state{ixh = 16#40, ixl = 16#00}},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#40, ezx_memory_48:cpu_read_byte(Machine2#machine_state.memory, 16#4000)),
    ?assertEqual(0, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_S).

dd_cb_srl_ix_carry_test() ->
    %% SRL (IX+0): 0x01 -> 0x00, C=1, Z=1
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_memory_48:cpu_write_byte(Mem0, 16#4000, 16#01),
    Mem2 = ezx_memory_48:cpu_write_byte(Mem1, 0, 16#DD),
    Mem3 = ezx_memory_48:cpu_write_byte(Mem2, 1, 16#CB),
    Mem4 = ezx_memory_48:cpu_write_byte(Mem3, 2, 16#00),
    Mem5 = ezx_memory_48:cpu_write_byte(Mem4, 3, 16#3E),
    Machine1 = Machine0#machine_state{memory = Mem5, cpu = Machine0#machine_state.cpu#cpu_state{ixh = 16#40, ixl = 16#00}},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#00, ezx_memory_48:cpu_read_byte(Machine2#machine_state.memory, 16#4000)),
    ?assertEqual(?FLAG_C, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_C),
    ?assertEqual(?FLAG_Z, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_Z).

%% ============================================================================
%% DD CB BIT (IX+d) - 0x46-0x7E
%% ============================================================================
dd_cb_bit_0_ix_test() ->
    %% BIT 0,(IX+0): value=0x01 -> bit 0=1, Z=0, S=1, H=1, P/V=0
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_memory_48:cpu_write_byte(Mem0, 16#4000, 16#01),
    Mem2 = ezx_memory_48:cpu_write_byte(Mem1, 0, 16#DD),
    Mem3 = ezx_memory_48:cpu_write_byte(Mem2, 1, 16#CB),
    Mem4 = ezx_memory_48:cpu_write_byte(Mem3, 2, 16#00),
    Mem5 = ezx_memory_48:cpu_write_byte(Mem4, 3, 16#46),
    Machine1 = Machine0#machine_state{memory = Mem5, cpu = Machine0#machine_state.cpu#cpu_state{ixh = 16#40, ixl = 16#00}},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#01, ezx_memory_48:cpu_read_byte(Machine2#machine_state.memory, 16#4000)),
    ?assertEqual(0, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_Z),
    ?assertEqual(?FLAG_S, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_S),
    ?assertEqual(?FLAG_H, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_H),
    ?assertEqual(0, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_V).

dd_cb_bit_7_ix_test() ->
    %% BIT 7,(IX+0): value=0x80 -> bit 7=1, Z=0, S=1
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_memory_48:cpu_write_byte(Mem0, 16#4000, 16#80),
    Mem2 = ezx_memory_48:cpu_write_byte(Mem1, 0, 16#DD),
    Mem3 = ezx_memory_48:cpu_write_byte(Mem2, 1, 16#CB),
    Mem4 = ezx_memory_48:cpu_write_byte(Mem3, 2, 16#00),
    Mem5 = ezx_memory_48:cpu_write_byte(Mem4, 3, 16#7E),
    Machine1 = Machine0#machine_state{memory = Mem5, cpu = Machine0#machine_state.cpu#cpu_state{ixh = 16#40, ixl = 16#00}},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(0, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_Z),
    ?assertEqual(?FLAG_S, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_S).

dd_cb_bit_7_ix_zero_test() ->
    %% BIT 7,(IX+0): value=0x7F -> bit 7=0, Z=1, S=0, P/V=1
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_memory_48:cpu_write_byte(Mem0, 16#4000, 16#7F),
    Mem2 = ezx_memory_48:cpu_write_byte(Mem1, 0, 16#DD),
    Mem3 = ezx_memory_48:cpu_write_byte(Mem2, 1, 16#CB),
    Mem4 = ezx_memory_48:cpu_write_byte(Mem3, 2, 16#00),
    Mem5 = ezx_memory_48:cpu_write_byte(Mem4, 3, 16#7E),
    Machine1 = Machine0#machine_state{memory = Mem5, cpu = Machine0#machine_state.cpu#cpu_state{ixh = 16#40, ixl = 16#00}},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(?FLAG_Z, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_Z),
    ?assertEqual(0, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_S),
    ?assertEqual(?FLAG_V, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_V).

dd_cb_bit_3_ix_test() ->
    %% BIT 3,(IX+2): value=0x08 -> bit 3=1
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_memory_48:cpu_write_byte(Mem0, 16#4002, 16#08),
    Mem2 = ezx_memory_48:cpu_write_byte(Mem1, 0, 16#DD),
    Mem3 = ezx_memory_48:cpu_write_byte(Mem2, 1, 16#CB),
    Mem4 = ezx_memory_48:cpu_write_byte(Mem3, 2, 16#02),
    Mem5 = ezx_memory_48:cpu_write_byte(Mem4, 3, 16#5E),
    Machine1 = Machine0#machine_state{memory = Mem5, cpu = Machine0#machine_state.cpu#cpu_state{ixh = 16#40, ixl = 16#00}},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(0, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_Z).

fd_cb_bit_iy_test() ->
    %% BIT 5,(IY+3): value=0x20 -> bit 5=1
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_memory_48:cpu_write_byte(Mem0, 16#5003, 16#20),
    Mem2 = ezx_memory_48:cpu_write_byte(Mem1, 0, 16#FD),
    Mem3 = ezx_memory_48:cpu_write_byte(Mem2, 1, 16#CB),
    Mem4 = ezx_memory_48:cpu_write_byte(Mem3, 2, 16#03),
    Mem5 = ezx_memory_48:cpu_write_byte(Mem4, 3, 16#6E),
    Machine1 = Machine0#machine_state{memory = Mem5, cpu = Machine0#machine_state.cpu#cpu_state{iyh = 16#50, iyl = 16#00}},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(0, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_Z).

%% ============================================================================
%% DD CB RES (IX+d) - 0x86-0xBE
%% ============================================================================
dd_cb_res_0_ix_test() ->
    %% RES 0,(IX+0): 0xFF -> 0xFE
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_memory_48:cpu_write_byte(Mem0, 16#4000, 16#FF),
    Mem2 = ezx_memory_48:cpu_write_byte(Mem1, 0, 16#DD),
    Mem3 = ezx_memory_48:cpu_write_byte(Mem2, 1, 16#CB),
    Mem4 = ezx_memory_48:cpu_write_byte(Mem3, 2, 16#00),
    Mem5 = ezx_memory_48:cpu_write_byte(Mem4, 3, 16#86),
    Machine1 = Machine0#machine_state{memory = Mem5, cpu = Machine0#machine_state.cpu#cpu_state{ixh = 16#40, ixl = 16#00}},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#FE, ezx_memory_48:cpu_read_byte(Machine2#machine_state.memory, 16#4000)).

dd_cb_res_7_ix_test() ->
    %% RES 7,(IX+0): 0xFF -> 0x7F
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_memory_48:cpu_write_byte(Mem0, 16#4000, 16#FF),
    Mem2 = ezx_memory_48:cpu_write_byte(Mem1, 0, 16#DD),
    Mem3 = ezx_memory_48:cpu_write_byte(Mem2, 1, 16#CB),
    Mem4 = ezx_memory_48:cpu_write_byte(Mem3, 2, 16#00),
    Mem5 = ezx_memory_48:cpu_write_byte(Mem4, 3, 16#BE),
    Machine1 = Machine0#machine_state{memory = Mem5, cpu = Machine0#machine_state.cpu#cpu_state{ixh = 16#40, ixl = 16#00}},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#7F, ezx_memory_48:cpu_read_byte(Machine2#machine_state.memory, 16#4000)).

dd_cb_res_3_ix_test() ->
    %% RES 3,(IX+5): 0xFF -> 0xF7
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_memory_48:cpu_write_byte(Mem0, 16#4005, 16#FF),
    Mem2 = ezx_memory_48:cpu_write_byte(Mem1, 0, 16#DD),
    Mem3 = ezx_memory_48:cpu_write_byte(Mem2, 1, 16#CB),
    Mem4 = ezx_memory_48:cpu_write_byte(Mem3, 2, 16#05),
    Mem5 = ezx_memory_48:cpu_write_byte(Mem4, 3, 16#9E),
    Machine1 = Machine0#machine_state{memory = Mem5, cpu = Machine0#machine_state.cpu#cpu_state{ixh = 16#40, ixl = 16#00}},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#F7, ezx_memory_48:cpu_read_byte(Machine2#machine_state.memory, 16#4005)).

fd_cb_res_iy_test() ->
    %% RES 2,(IY-2): 0xFF -> 0xFB
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_memory_48:cpu_write_byte(Mem0, 16#4FFE, 16#FF),
    Mem2 = ezx_memory_48:cpu_write_byte(Mem1, 0, 16#FD),
    Mem3 = ezx_memory_48:cpu_write_byte(Mem2, 1, 16#CB),
    Mem4 = ezx_memory_48:cpu_write_byte(Mem3, 2, 16#FE),
    Mem5 = ezx_memory_48:cpu_write_byte(Mem4, 3, 16#96),
    Machine1 = Machine0#machine_state{memory = Mem5, cpu = Machine0#machine_state.cpu#cpu_state{iyh = 16#50, iyl = 16#00}},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#FB, ezx_memory_48:cpu_read_byte(Machine2#machine_state.memory, 16#4FFE)).

%% ============================================================================
%% DD CB SET (IX+d) - 0xC6-0xFE
%% ============================================================================
dd_cb_set_0_ix_test() ->
    %% SET 0,(IX+0): 0xFE -> 0xFF
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_memory_48:cpu_write_byte(Mem0, 16#4000, 16#FE),
    Mem2 = ezx_memory_48:cpu_write_byte(Mem1, 0, 16#DD),
    Mem3 = ezx_memory_48:cpu_write_byte(Mem2, 1, 16#CB),
    Mem4 = ezx_memory_48:cpu_write_byte(Mem3, 2, 16#00),
    Mem5 = ezx_memory_48:cpu_write_byte(Mem4, 3, 16#C6),
    Machine1 = Machine0#machine_state{memory = Mem5, cpu = Machine0#machine_state.cpu#cpu_state{ixh = 16#40, ixl = 16#00}},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#FF, ezx_memory_48:cpu_read_byte(Machine2#machine_state.memory, 16#4000)).

dd_cb_set_7_ix_test() ->
    %% SET 7,(IX+0): 0x7F -> 0xFF
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_memory_48:cpu_write_byte(Mem0, 16#4000, 16#7F),
    Mem2 = ezx_memory_48:cpu_write_byte(Mem1, 0, 16#DD),
    Mem3 = ezx_memory_48:cpu_write_byte(Mem2, 1, 16#CB),
    Mem4 = ezx_memory_48:cpu_write_byte(Mem3, 2, 16#00),
    Mem5 = ezx_memory_48:cpu_write_byte(Mem4, 3, 16#FE),
    Machine1 = Machine0#machine_state{memory = Mem5, cpu = Machine0#machine_state.cpu#cpu_state{ixh = 16#40, ixl = 16#00}},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#FF, ezx_memory_48:cpu_read_byte(Machine2#machine_state.memory, 16#4000)).

dd_cb_set_2_ix_test() ->
    %% SET 2,(IX+3): 0xF3 -> 0xF7 (0xD6 = SET 2, reg=6)
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_memory_48:cpu_write_byte(Mem0, 16#4003, 16#F3),
    Mem2 = ezx_memory_48:cpu_write_byte(Mem1, 0, 16#DD),
    Mem3 = ezx_memory_48:cpu_write_byte(Mem2, 1, 16#CB),
    Mem4 = ezx_memory_48:cpu_write_byte(Mem3, 2, 16#03),
    Mem5 = ezx_memory_48:cpu_write_byte(Mem4, 3, 16#D6),
    Machine1 = Machine0#machine_state{memory = Mem5, cpu = Machine0#machine_state.cpu#cpu_state{ixh = 16#40, ixl = 16#00}},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#F7, ezx_memory_48:cpu_read_byte(Machine2#machine_state.memory, 16#4003)).

fd_cb_set_iy_test() ->
    %% SET 4,(IY+1): 0xEF -> 0xFF (0xE6 = SET 4, reg=6)
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_memory_48:cpu_write_byte(Mem0, 16#5001, 16#EF),
    Mem2 = ezx_memory_48:cpu_write_byte(Mem1, 0, 16#FD),
    Mem3 = ezx_memory_48:cpu_write_byte(Mem2, 1, 16#CB),
    Mem4 = ezx_memory_48:cpu_write_byte(Mem3, 2, 16#01),
    Mem5 = ezx_memory_48:cpu_write_byte(Mem4, 3, 16#E6),
    Machine1 = Machine0#machine_state{memory = Mem5, cpu = Machine0#machine_state.cpu#cpu_state{iyh = 16#50, iyl = 16#00}},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#FF, ezx_memory_48:cpu_read_byte(Machine2#machine_state.memory, 16#5001)).

%% ============================================================================
%% Prefix state verification
%% ============================================================================
dd_prefix_state_during_cb_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_memory_48:cpu_write_byte(Mem0, 16#4000, 16#00),
    Mem2 = ezx_memory_48:cpu_write_byte(Mem1, 0, 16#DD),
    Mem3 = ezx_memory_48:cpu_write_byte(Mem2, 1, 16#CB),
    Mem4 = ezx_memory_48:cpu_write_byte(Mem3, 2, 16#00),
    Mem5 = ezx_memory_48:cpu_write_byte(Mem4, 3, 16#06),
    Machine1 = Machine0#machine_state{memory = Mem5, cpu = Machine0#machine_state.cpu#cpu_state{ixh = 16#40, ixl = 16#00}},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(none, Machine2#machine_state.cpu#cpu_state.prefix).

fd_prefix_state_during_cb_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_memory_48:cpu_write_byte(Mem0, 16#5000, 16#00),
    Mem2 = ezx_memory_48:cpu_write_byte(Mem1, 0, 16#FD),
    Mem3 = ezx_memory_48:cpu_write_byte(Mem2, 1, 16#CB),
    Mem4 = ezx_memory_48:cpu_write_byte(Mem3, 2, 16#00),
    Mem5 = ezx_memory_48:cpu_write_byte(Mem4, 3, 16#06),
    Machine1 = Machine0#machine_state{memory = Mem5, cpu = Machine0#machine_state.cpu#cpu_state{iyh = 16#50, iyl = 16#00}},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(none, Machine2#machine_state.cpu#cpu_state.prefix).

%% ============================================================================
%% T-states verification
%% ============================================================================
dd_cb_tstates_test() ->
    %% DD CB takes 23 T-states total
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_memory_48:cpu_write_byte(Mem0, 16#4000, 16#00),
    Mem2 = ezx_memory_48:cpu_write_byte(Mem1, 0, 16#DD),
    Mem3 = ezx_memory_48:cpu_write_byte(Mem2, 1, 16#CB),
    Mem4 = ezx_memory_48:cpu_write_byte(Mem3, 2, 16#00),
    Mem5 = ezx_memory_48:cpu_write_byte(Mem4, 3, 16#06),
    Machine1 = Machine0#machine_state{memory = Mem5, cpu = Machine0#machine_state.cpu#cpu_state{ixh = 16#40, ixl = 16#00}},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(23, z80_cpu:t_states(Machine2)).

fd_cb_tstates_test() ->
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_memory_48:cpu_write_byte(Mem0, 16#5000, 16#00),
    Mem2 = ezx_memory_48:cpu_write_byte(Mem1, 0, 16#FD),
    Mem3 = ezx_memory_48:cpu_write_byte(Mem2, 1, 16#CB),
    Mem4 = ezx_memory_48:cpu_write_byte(Mem3, 2, 16#00),
    Mem5 = ezx_memory_48:cpu_write_byte(Mem4, 3, 16#06),
    Machine1 = Machine0#machine_state{memory = Mem5, cpu = Machine0#machine_state.cpu#cpu_state{iyh = 16#50, iyl = 16#00}},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(23, z80_cpu:t_states(Machine2)).

%% ============================================================================
%% Memory write-back verification
%% ============================================================================
dd_cb_memory_writeback_test() ->
    %% Verify result is written back to memory
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_memory_48:cpu_write_byte(Mem0, 16#4000, 16#01),
    Mem2 = ezx_memory_48:cpu_write_byte(Mem1, 0, 16#DD),
    Mem3 = ezx_memory_48:cpu_write_byte(Mem2, 1, 16#CB),
    Mem4 = ezx_memory_48:cpu_write_byte(Mem3, 2, 16#00),
    Mem5 = ezx_memory_48:cpu_write_byte(Mem4, 3, 16#06),
    Machine1 = Machine0#machine_state{memory = Mem5, cpu = Machine0#machine_state.cpu#cpu_state{ixh = 16#40, ixl = 16#00}},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#02, ezx_memory_48:cpu_read_byte(Machine2#machine_state.memory, 16#4000)).

dd_cb_bit_no_memory_write_test() ->
    %% BIT does not modify memory
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_memory_48:cpu_write_byte(Mem0, 16#4000, 16#55),
    Mem2 = ezx_memory_48:cpu_write_byte(Mem1, 0, 16#DD),
    Mem3 = ezx_memory_48:cpu_write_byte(Mem2, 1, 16#CB),
    Mem4 = ezx_memory_48:cpu_write_byte(Mem3, 2, 16#00),
    Mem5 = ezx_memory_48:cpu_write_byte(Mem4, 3, 16#5E),
    Machine1 = Machine0#machine_state{memory = Mem5, cpu = Machine0#machine_state.cpu#cpu_state{ixh = 16#40, ixl = 16#00}},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#55, ezx_memory_48:cpu_read_byte(Machine2#machine_state.memory, 16#4000)).

%% ============================================================================
%% DD CB register operands (RegField 0-5, 7 = B,C,D,E,H,L,A)
%% These operate on CPU registers, NOT memory at (IX+d)
%% ============================================================================

dd_cb_rlc_b_reg_test() ->
    %% DD CB 00 = RLC B (RegField=0): read (IX+0), RLC, write back, copy to B
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_memory_48:cpu_write_byte(Mem0, 16#4000, 16#81),  %% value at (IX+0)
    Mem2 = ezx_memory_48:cpu_write_byte(Mem1, 0, 16#DD),
    Mem3 = ezx_memory_48:cpu_write_byte(Mem2, 1, 16#CB),
    Mem4 = ezx_memory_48:cpu_write_byte(Mem3, 2, 16#00),      %% displacement 0
    Mem5 = ezx_memory_48:cpu_write_byte(Mem4, 3, 16#00),      %% RLC (IX+0) -> copy to B
    Machine1 = Machine0#machine_state{memory = Mem5, cpu = Machine0#machine_state.cpu#cpu_state{b = 16#00, ixh = 16#40, ixl = 16#00, f = 0}},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#03, Machine2#machine_state.cpu#cpu_state.b),   %% 10000001 RLC = 00000011
    ?assertEqual(?FLAG_C, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_C),
    ?assertEqual(16#03, ezx_memory_48:cpu_read_byte(Machine2#machine_state.memory, 16#4000)).  %% memory also updated

dd_cb_rlc_c_reg_test() ->
    %% DD CB 01 = RLC C (RegField=1): read (IX+0), RLC, write back, copy to C
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_memory_48:cpu_write_byte(Mem0, 16#4000, 16#40),  %% value at (IX+0)
    Mem2 = ezx_memory_48:cpu_write_byte(Mem1, 0, 16#DD),
    Mem3 = ezx_memory_48:cpu_write_byte(Mem2, 1, 16#CB),
    Mem4 = ezx_memory_48:cpu_write_byte(Mem3, 2, 16#00),
    Mem5 = ezx_memory_48:cpu_write_byte(Mem4, 3, 16#01),      %% RLC (IX+0) -> copy to C
    Machine1 = Machine0#machine_state{memory = Mem5, cpu = Machine0#machine_state.cpu#cpu_state{c = 16#00, ixh = 16#40, ixl = 16#00, f = 0}},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#80, Machine2#machine_state.cpu#cpu_state.c),
    ?assertEqual(0, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_C),
    ?assertEqual(?FLAG_S, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_S),
    ?assertEqual(16#80, ezx_memory_48:cpu_read_byte(Machine2#machine_state.memory, 16#4000)).

dd_cb_rlc_a_reg_test() ->
    %% DD CB 07 = RLC A (RegField=7): read (IX+0), RLC, write back, copy to A
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_memory_48:cpu_write_byte(Mem0, 16#4000, 16#FF),  %% value at (IX+0)
    Mem2 = ezx_memory_48:cpu_write_byte(Mem1, 0, 16#DD),
    Mem3 = ezx_memory_48:cpu_write_byte(Mem2, 1, 16#CB),
    Mem4 = ezx_memory_48:cpu_write_byte(Mem3, 2, 16#00),
    Mem5 = ezx_memory_48:cpu_write_byte(Mem4, 3, 16#07),      %% RLC (IX+0) -> copy to A
    Machine1 = Machine0#machine_state{memory = Mem5, cpu = Machine0#machine_state.cpu#cpu_state{a = 16#00, ixh = 16#40, ixl = 16#00, f = 0}},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#FF, Machine2#machine_state.cpu#cpu_state.a),
    ?assertEqual(?FLAG_C, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_C),
    ?assertEqual(16#FF, ezx_memory_48:cpu_read_byte(Machine2#machine_state.memory, 16#4000)).

dd_cb_bit_0_b_reg_test() ->
    %% DD CB 40 = BIT 0,B (RegField=0): read (IX+0), BIT 0, flags set, B UNCHANGED (BIT doesn't copy to reg)
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_memory_48:cpu_write_byte(Mem0, 16#4000, 16#01),  %% value at (IX+0), bit 0 = 1
    Mem2 = ezx_memory_48:cpu_write_byte(Mem1, 0, 16#DD),
    Mem3 = ezx_memory_48:cpu_write_byte(Mem2, 1, 16#CB),
    Mem4 = ezx_memory_48:cpu_write_byte(Mem3, 2, 16#00),
    Mem5 = ezx_memory_48:cpu_write_byte(Mem4, 3, 16#40),      %% BIT 0,(IX+0) - no register copy
    Machine1 = Machine0#machine_state{memory = Mem5, cpu = Machine0#machine_state.cpu#cpu_state{b = 16#00, ixh = 16#40, ixl = 16#00, f = 0}},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(0, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_Z),   %% Z=0 (bit was 1)
    ?assertEqual(?FLAG_S, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_S), %% S=1 (bit 0 = 1)
    ?assertEqual(?FLAG_H, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_H), %% H=1
    ?assertEqual(16#00, Machine2#machine_state.cpu#cpu_state.b).  %% B unchanged

dd_cb_bit_7_a_reg_test() ->
    %% DD CB 7F = BIT 7,A (RegField=7): read (IX+0), BIT 7, flags set, A UNCHANGED
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_memory_48:cpu_write_byte(Mem0, 16#4000, 16#80),  %% value at (IX+0), bit 7 = 1
    Mem2 = ezx_memory_48:cpu_write_byte(Mem1, 0, 16#DD),
    Mem3 = ezx_memory_48:cpu_write_byte(Mem2, 1, 16#CB),
    Mem4 = ezx_memory_48:cpu_write_byte(Mem3, 2, 16#00),
    Mem5 = ezx_memory_48:cpu_write_byte(Mem4, 3, 16#7F),      %% BIT 7,(IX+0) - no register copy
    Machine1 = Machine0#machine_state{memory = Mem5, cpu = Machine0#machine_state.cpu#cpu_state{a = 16#00, ixh = 16#40, ixl = 16#00, f = 0}},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(0, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_Z),
    ?assertEqual(?FLAG_S, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_S),
    ?assertEqual(16#00, Machine2#machine_state.cpu#cpu_state.a).  %% A unchanged

dd_cb_res_3_d_reg_test() ->
    %% DD CB 9A = RES 3,D (RegField=2): read (IX+0), RES 3, write back, copy to D
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_memory_48:cpu_write_byte(Mem0, 16#4000, 16#FF),  %% value at (IX+0)
    Mem2 = ezx_memory_48:cpu_write_byte(Mem1, 0, 16#DD),
    Mem3 = ezx_memory_48:cpu_write_byte(Mem2, 1, 16#CB),
    Mem4 = ezx_memory_48:cpu_write_byte(Mem3, 2, 16#00),
    Mem5 = ezx_memory_48:cpu_write_byte(Mem4, 3, 16#9A),      %% RES 3,(IX+0) -> copy to D
    Machine1 = Machine0#machine_state{memory = Mem5, cpu = Machine0#machine_state.cpu#cpu_state{d = 16#00, ixh = 16#40, ixl = 16#00}},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#F7, Machine2#machine_state.cpu#cpu_state.d),  %% 11111111 -> 11110111
    ?assertEqual(16#F7, ezx_memory_48:cpu_read_byte(Machine2#machine_state.memory, 16#4000)).

dd_cb_set_5_e_reg_test() ->
    %% DD CB EB = SET 5,E (RegField=3): read (IX+0), SET 5, write back, copy to E
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_memory_48:cpu_write_byte(Mem0, 16#4000, 16#00),  %% value at (IX+0)
    Mem2 = ezx_memory_48:cpu_write_byte(Mem1, 0, 16#DD),
    Mem3 = ezx_memory_48:cpu_write_byte(Mem2, 1, 16#CB),
    Mem4 = ezx_memory_48:cpu_write_byte(Mem3, 2, 16#00),
    Mem5 = ezx_memory_48:cpu_write_byte(Mem4, 3, 16#EB),      %% SET 5,(IX+0) -> copy to E
    Machine1 = Machine0#machine_state{memory = Mem5, cpu = Machine0#machine_state.cpu#cpu_state{e = 16#00, ixh = 16#40, ixl = 16#00}},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#20, Machine2#machine_state.cpu#cpu_state.e),  %% 00000000 -> 00100000
    ?assertEqual(16#20, ezx_memory_48:cpu_read_byte(Machine2#machine_state.memory, 16#4000)).

dd_cb_rl_h_reg_test() ->
    %% DD CB 14 = RL H (RegField=4): read (IX+0), RL, write back, copy to H
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_memory_48:cpu_write_byte(Mem0, 16#4000, 16#7F),  %% value at (IX+0)
    Mem2 = ezx_memory_48:cpu_write_byte(Mem1, 0, 16#DD),
    Mem3 = ezx_memory_48:cpu_write_byte(Mem2, 1, 16#CB),
    Mem4 = ezx_memory_48:cpu_write_byte(Mem3, 2, 16#00),
    Mem5 = ezx_memory_48:cpu_write_byte(Mem4, 3, 16#14),      %% RL (IX+0) -> copy to H
    Machine1 = Machine0#machine_state{memory = Mem5, cpu = Machine0#machine_state.cpu#cpu_state{h = 16#00, ixh = 16#40, ixl = 16#00, f = ?FLAG_C}},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#FF, Machine2#machine_state.cpu#cpu_state.h),  %% 01111111 RL with carry=1 = 11111111
    ?assertEqual(0, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_C),
    ?assertEqual(16#FF, ezx_memory_48:cpu_read_byte(Machine2#machine_state.memory, 16#4000)).

fd_cb_sla_l_reg_test() ->
    %% FD CB 25 = SLA L (RegField=5): read (IY+0), SLA, write back, copy to L
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_memory_48:cpu_write_byte(Mem0, 16#5000, 16#40),  %% value at (IY+0)
    Mem2 = ezx_memory_48:cpu_write_byte(Mem1, 0, 16#FD),
    Mem3 = ezx_memory_48:cpu_write_byte(Mem2, 1, 16#CB),
    Mem4 = ezx_memory_48:cpu_write_byte(Mem3, 2, 16#00),
    Mem5 = ezx_memory_48:cpu_write_byte(Mem4, 3, 16#25),      %% SLA (IY+0) -> copy to L
    Machine1 = Machine0#machine_state{memory = Mem5, cpu = Machine0#machine_state.cpu#cpu_state{l = 16#00, iyh = 16#50, iyl = 16#00, f = 0}},
    Machine2 = z80_cpu:step(Machine1),
    ?assertEqual(16#80, Machine2#machine_state.cpu#cpu_state.l),
    ?assertEqual(?FLAG_S, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_S),
    ?assertEqual(16#80, ezx_memory_48:cpu_read_byte(Machine2#machine_state.memory, 16#5000)).

dd_cb_register_ops_read_write_memory_test() ->
    %% Register operands (z!=6): read from (IX+d), apply op, write back to (IX+d), copy to register
    Machine0 = ezx_emulator:init(),
    Mem0 = Machine0#machine_state.memory,
    Mem1 = ezx_memory_48:cpu_write_byte(Mem0, 16#4000, 16#81),  %% value at (IX+0) = 0x81 (10000001)
    Mem2 = ezx_memory_48:cpu_write_byte(Mem1, 0, 16#DD),
    Mem3 = ezx_memory_48:cpu_write_byte(Mem2, 1, 16#CB),
    Mem4 = ezx_memory_48:cpu_write_byte(Mem3, 2, 16#00),
    Mem5 = ezx_memory_48:cpu_write_byte(Mem4, 3, 16#00),  %% RLC (IX+0) -> copy to B
    Machine1 = Machine0#machine_state{memory = Mem5, cpu = Machine0#machine_state.cpu#cpu_state{b = 16#00, ixh = 16#40, ixl = 16#00, f = 0}},
    Machine2 = z80_cpu:step(Machine1),
    %% Memory at (IX+0) should be updated (RLC 0x81 = 0x03, carry=1)
    ?assertEqual(16#03, ezx_memory_48:cpu_read_byte(Machine2#machine_state.memory, 16#4000)),
    %% B register should get the result
    ?assertEqual(16#03, Machine2#machine_state.cpu#cpu_state.b),
    ?assertEqual(?FLAG_C, Machine2#machine_state.cpu#cpu_state.f band ?FLAG_C).