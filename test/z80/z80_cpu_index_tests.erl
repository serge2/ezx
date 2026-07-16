-module(z80_cpu_index_tests).

-include("z80_records.hrl").
-include_lib("eunit/include/eunit.hrl").

%% --- DD Prefix (IX) Tests ---

dd_ld_ix_nn_test() ->
    Machine0 = ezx_emulator:init(),
    Machine1 = ezx_emulator:write_byte(Machine0, 0, 16#DD),
    Machine2 = ezx_emulator:write_byte(Machine1, 1, 16#21),
    Machine3 = ezx_emulator:write_byte(Machine2, 2, 16#34),
    Machine4 = ezx_emulator:write_byte(Machine3, 3, 16#12),
    Machine5 = z80_cpu:step(Machine4),
    ?assertEqual(16#12, Machine5#machine_state.cpu#cpu_state.ixh),
    ?assertEqual(16#34, Machine5#machine_state.cpu#cpu_state.ixl),
    ?assertEqual(4, z80_cpu:pc(Machine5)),
    ?assertEqual(14, z80_cpu:t_states(Machine5)).

dd_add_ix_bc_test() ->
    Machine0 = ezx_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{b = 16#10, c = 16#00, ixh = 16#20, ixl = 16#00},
    Machine1 = Machine0#machine_state{cpu = Cpu0},
    Machine2 = ezx_emulator:write_byte(Machine1, 0, 16#DD),
    Machine3 = ezx_emulator:write_byte(Machine2, 1, 16#09),
    Machine4 = z80_cpu:step(Machine3),
    ?assertEqual(16#30, Machine4#machine_state.cpu#cpu_state.ixh),
    ?assertEqual(16#00, Machine4#machine_state.cpu#cpu_state.ixl),
    ?assertEqual(2, z80_cpu:pc(Machine4)),
    ?assertEqual(15, z80_cpu:t_states(Machine4)).

dd_inc_ix_test() ->
    Machine0 = ezx_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{ixh = 16#12, ixl = 16#34},
    Machine1 = Machine0#machine_state{cpu = Cpu0},
    Machine2 = ezx_emulator:write_byte(Machine1, 0, 16#DD),
    Machine3 = ezx_emulator:write_byte(Machine2, 1, 16#23),
    Machine4 = z80_cpu:step(Machine3),
    ?assertEqual(16#12, Machine4#machine_state.cpu#cpu_state.ixh),
    ?assertEqual(16#35, Machine4#machine_state.cpu#cpu_state.ixl),
    ?assertEqual(2, z80_cpu:pc(Machine4)),
    ?assertEqual(10, z80_cpu:t_states(Machine4)).

dd_dec_ix_test() ->
    Machine0 = ezx_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{ixh = 16#12, ixl = 16#34},
    Machine1 = Machine0#machine_state{cpu = Cpu0},
    Machine2 = ezx_emulator:write_byte(Machine1, 0, 16#DD),
    Machine3 = ezx_emulator:write_byte(Machine2, 1, 16#2B),
    Machine4 = z80_cpu:step(Machine3),
    ?assertEqual(16#12, Machine4#machine_state.cpu#cpu_state.ixh),
    ?assertEqual(16#33, Machine4#machine_state.cpu#cpu_state.ixl),
    ?assertEqual(2, z80_cpu:pc(Machine4)),
    ?assertEqual(10, z80_cpu:t_states(Machine4)).

dd_push_ix_test() ->
    Machine0 = ezx_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{ixh = 16#12, ixl = 16#34, sp = 16#FF00},
    Machine1 = Machine0#machine_state{cpu = Cpu0},
    Machine2 = ezx_emulator:write_byte(Machine1, 0, 16#DD),
    Machine3 = ezx_emulator:write_byte(Machine2, 1, 16#E5),
    Machine4 = z80_cpu:step(Machine3),
    ?assertEqual(16#FEFE, Machine4#machine_state.cpu#cpu_state.sp),
    ?assertEqual(16#34, ezx_emulator:read_byte(Machine4, 16#FEFE)),
    ?assertEqual(16#12, ezx_emulator:read_byte(Machine4, 16#FEFF)),
    ?assertEqual(2, z80_cpu:pc(Machine4)),
    ?assertEqual(15, z80_cpu:t_states(Machine4)).

dd_pop_ix_test() ->
    Machine0 = ezx_emulator:init(),
    Machine1 = ezx_emulator:write_byte(Machine0, 16#FEFE, 16#56),
    Machine2 = ezx_emulator:write_byte(Machine1, 16#FEFF, 16#78),
    Cpu0 = Machine2#machine_state.cpu#cpu_state{sp = 16#FEFE},
    Machine3 = Machine2#machine_state{cpu = Cpu0},
    Machine4 = ezx_emulator:write_byte(Machine3, 0, 16#DD),
    Machine5 = ezx_emulator:write_byte(Machine4, 1, 16#E1),
    Machine6 = z80_cpu:step(Machine5),
    ?assertEqual(16#78, Machine6#machine_state.cpu#cpu_state.ixh),
    ?assertEqual(16#56, Machine6#machine_state.cpu#cpu_state.ixl),
    ?assertEqual(16#FF00, Machine6#machine_state.cpu#cpu_state.sp),
    ?assertEqual(2, z80_cpu:pc(Machine6)),
    ?assertEqual(14, z80_cpu:t_states(Machine6)).

dd_ld_sp_ix_test() ->
    Machine0 = ezx_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{ixh = 16#12, ixl = 16#34},
    Machine1 = Machine0#machine_state{cpu = Cpu0},
    Machine2 = ezx_emulator:write_byte(Machine1, 0, 16#DD),
    Machine3 = ezx_emulator:write_byte(Machine2, 1, 16#F9),
    Machine4 = z80_cpu:step(Machine3),
    ?assertEqual(16#1234, Machine4#machine_state.cpu#cpu_state.sp),
    ?assertEqual(2, z80_cpu:pc(Machine4)),
    ?assertEqual(10, z80_cpu:t_states(Machine4)).

%% --- FD Prefix (IY) Tests ---

fd_ld_iy_nn_test() ->
    Machine0 = ezx_emulator:init(),
    Machine1 = ezx_emulator:write_byte(Machine0, 0, 16#FD),
    Machine2 = ezx_emulator:write_byte(Machine1, 1, 16#21),
    Machine3 = ezx_emulator:write_byte(Machine2, 2, 16#56),
    Machine4 = ezx_emulator:write_byte(Machine3, 3, 16#78),
    Machine5 = z80_cpu:step(Machine4),
    ?assertEqual(16#78, Machine5#machine_state.cpu#cpu_state.iyh),
    ?assertEqual(16#56, Machine5#machine_state.cpu#cpu_state.iyl),
    ?assertEqual(4, z80_cpu:pc(Machine5)),
    ?assertEqual(14, z80_cpu:t_states(Machine5)).

fd_add_iy_de_test() ->
    Machine0 = ezx_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{d = 16#10, e = 16#00, iyh = 16#20, iyl = 16#00},
    Machine1 = Machine0#machine_state{cpu = Cpu0},
    Machine2 = ezx_emulator:write_byte(Machine1, 0, 16#FD),
    Machine3 = ezx_emulator:write_byte(Machine2, 1, 16#19),
    Machine4 = z80_cpu:step(Machine3),
    ?assertEqual(16#30, Machine4#machine_state.cpu#cpu_state.iyh),
    ?assertEqual(16#00, Machine4#machine_state.cpu#cpu_state.iyl),
    ?assertEqual(2, z80_cpu:pc(Machine4)),
    ?assertEqual(15, z80_cpu:t_states(Machine4)).

fd_inc_iy_test() ->
    Machine0 = ezx_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{iyh = 16#12, iyl = 16#34},
    Machine1 = Machine0#machine_state{cpu = Cpu0},
    Machine2 = ezx_emulator:write_byte(Machine1, 0, 16#FD),
    Machine3 = ezx_emulator:write_byte(Machine2, 1, 16#23),
    Machine4 = z80_cpu:step(Machine3),
    ?assertEqual(16#12, Machine4#machine_state.cpu#cpu_state.iyh),
    ?assertEqual(16#35, Machine4#machine_state.cpu#cpu_state.iyl),
    ?assertEqual(2, z80_cpu:pc(Machine4)),
    ?assertEqual(10, z80_cpu:t_states(Machine4)).

fd_dec_iy_test() ->
    Machine0 = ezx_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{iyh = 16#12, iyl = 16#34},
    Machine1 = Machine0#machine_state{cpu = Cpu0},
    Machine2 = ezx_emulator:write_byte(Machine1, 0, 16#FD),
    Machine3 = ezx_emulator:write_byte(Machine2, 1, 16#2B),
    Machine4 = z80_cpu:step(Machine3),
    ?assertEqual(16#12, Machine4#machine_state.cpu#cpu_state.iyh),
    ?assertEqual(16#33, Machine4#machine_state.cpu#cpu_state.iyl),
    ?assertEqual(2, z80_cpu:pc(Machine4)),
    ?assertEqual(10, z80_cpu:t_states(Machine4)).

fd_push_iy_test() ->
    Machine0 = ezx_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{iyh = 16#12, iyl = 16#34, sp = 16#FF00},
    Machine1 = Machine0#machine_state{cpu = Cpu0},
    Machine2 = ezx_emulator:write_byte(Machine1, 0, 16#FD),
    Machine3 = ezx_emulator:write_byte(Machine2, 1, 16#E5),
    Machine4 = z80_cpu:step(Machine3),
    ?assertEqual(16#FEFE, Machine4#machine_state.cpu#cpu_state.sp),
    ?assertEqual(16#34, ezx_emulator:read_byte(Machine4, 16#FEFE)),
    ?assertEqual(16#12, ezx_emulator:read_byte(Machine4, 16#FEFF)),
    ?assertEqual(2, z80_cpu:pc(Machine4)),
    ?assertEqual(15, z80_cpu:t_states(Machine4)).

fd_pop_iy_test() ->
    Machine0 = ezx_emulator:init(),
    Machine1 = ezx_emulator:write_byte(Machine0, 16#FEFE, 16#56),
    Machine2 = ezx_emulator:write_byte(Machine1, 16#FEFF, 16#78),
    Cpu0 = Machine2#machine_state.cpu#cpu_state{sp = 16#FEFE},
    Machine3 = Machine2#machine_state{cpu = Cpu0},
    Machine4 = ezx_emulator:write_byte(Machine3, 0, 16#FD),
    Machine5 = ezx_emulator:write_byte(Machine4, 1, 16#E1),
    Machine6 = z80_cpu:step(Machine5),
    ?assertEqual(16#78, Machine6#machine_state.cpu#cpu_state.iyh),
    ?assertEqual(16#56, Machine6#machine_state.cpu#cpu_state.iyl),
    ?assertEqual(16#FF00, Machine6#machine_state.cpu#cpu_state.sp),
    ?assertEqual(2, z80_cpu:pc(Machine6)),
    ?assertEqual(14, z80_cpu:t_states(Machine6)).

fd_ld_sp_iy_test() ->
    Machine0 = ezx_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{iyh = 16#12, iyl = 16#34},
    Machine1 = Machine0#machine_state{cpu = Cpu0},
    Machine2 = ezx_emulator:write_byte(Machine1, 0, 16#FD),
    Machine3 = ezx_emulator:write_byte(Machine2, 1, 16#F9),
    Machine4 = z80_cpu:step(Machine3),
    ?assertEqual(16#1234, Machine4#machine_state.cpu#cpu_state.sp),
    ?assertEqual(2, z80_cpu:pc(Machine4)),
    ?assertEqual(10, z80_cpu:t_states(Machine4)).

%% --- Prefix State Verification Tests ---

dd_prefix_cleared_after_instruction_test() ->
    %% Verify prefix is cleared after DD instruction completes
    Machine0 = ezx_emulator:init(),
    Machine1 = ezx_emulator:write_byte(Machine0, 0, 16#DD),
    Machine2 = ezx_emulator:write_byte(Machine1, 1, 16#21),  %% LD IX,nn
    Machine3 = ezx_emulator:write_byte(Machine2, 2, 16#34),
    Machine4 = ezx_emulator:write_byte(Machine3, 3, 16#12),
    Machine5 = z80_cpu:step(Machine4),
    ?assertEqual(none, Machine5#machine_state.cpu#cpu_state.prefix),
    ?assertEqual(0, Machine5#machine_state.cpu#cpu_state.displacement).

fd_prefix_cleared_after_instruction_test() ->
    Machine0 = ezx_emulator:init(),
    Machine1 = ezx_emulator:write_byte(Machine0, 0, 16#FD),
    Machine2 = ezx_emulator:write_byte(Machine1, 1, 16#21),  %% LD IY,nn
    Machine3 = ezx_emulator:write_byte(Machine2, 2, 16#56),
    Machine4 = ezx_emulator:write_byte(Machine3, 3, 16#78),
    Machine5 = z80_cpu:step(Machine4),
    ?assertEqual(none, Machine5#machine_state.cpu#cpu_state.prefix),
    ?assertEqual(0, Machine5#machine_state.cpu#cpu_state.displacement).

%% --- Multiple Prefix Tests ---

dd_dd_prefix_behavior_test() ->
    %% DD DD 21 nn nn -> second DD acts as prefix for LD IX,nn
    %% First DD sets prefix=dd, second DD with prefix=dd acts as LD IX,nn
    Machine0 = ezx_emulator:init(),
    Machine1 = ezx_emulator:write_byte(Machine0, 0, 16#DD),
    Machine2 = ezx_emulator:write_byte(Machine1, 1, 16#DD),
    Machine3 = ezx_emulator:write_byte(Machine2, 2, 16#21),
    Machine4 = ezx_emulator:write_byte(Machine3, 3, 16#34),
    Machine5 = ezx_emulator:write_byte(Machine4, 4, 16#12),
    Machine6 = z80_cpu:step(Machine5),
    %% Should execute LD IX,1234h
    ?assertEqual(16#12, Machine6#machine_state.cpu#cpu_state.ixh),
    ?assertEqual(16#34, Machine6#machine_state.cpu#cpu_state.ixl),
    ?assertEqual(none, Machine6#machine_state.cpu#cpu_state.prefix).

fd_fd_prefix_behavior_test() ->
    Machine0 = ezx_emulator:init(),
    Machine1 = ezx_emulator:write_byte(Machine0, 0, 16#FD),
    Machine2 = ezx_emulator:write_byte(Machine1, 1, 16#FD),
    Machine3 = ezx_emulator:write_byte(Machine2, 2, 16#21),
    Machine4 = ezx_emulator:write_byte(Machine3, 3, 16#56),
    Machine5 = ezx_emulator:write_byte(Machine4, 4, 16#78),
    Machine6 = z80_cpu:step(Machine5),
    ?assertEqual(16#78, Machine6#machine_state.cpu#cpu_state.iyh),
    ?assertEqual(16#56, Machine6#machine_state.cpu#cpu_state.iyl),
    ?assertEqual(none, Machine6#machine_state.cpu#cpu_state.prefix).

dd_fd_mixed_prefix_test() ->
    %% DD FD 21 nn nn -> FD wins (last prefix)
    Machine0 = ezx_emulator:init(),
    Machine1 = ezx_emulator:write_byte(Machine0, 0, 16#DD),
    Machine2 = ezx_emulator:write_byte(Machine1, 1, 16#FD),
    Machine3 = ezx_emulator:write_byte(Machine2, 2, 16#21),
    Machine4 = ezx_emulator:write_byte(Machine3, 3, 16#56),
    Machine5 = ezx_emulator:write_byte(Machine4, 4, 16#78),
    Machine6 = z80_cpu:step(Machine5),
    ?assertEqual(16#78, Machine6#machine_state.cpu#cpu_state.iyh),
    ?assertEqual(16#56, Machine6#machine_state.cpu#cpu_state.iyl),
    ?assertEqual(none, Machine6#machine_state.cpu#cpu_state.prefix).

fd_dd_mixed_prefix_test() ->
    %% FD DD 21 nn nn -> DD wins
    Machine0 = ezx_emulator:init(),
    Machine1 = ezx_emulator:write_byte(Machine0, 0, 16#FD),
    Machine2 = ezx_emulator:write_byte(Machine1, 1, 16#DD),
    Machine3 = ezx_emulator:write_byte(Machine2, 2, 16#21),
    Machine4 = ezx_emulator:write_byte(Machine3, 3, 16#34),
    Machine5 = ezx_emulator:write_byte(Machine4, 4, 16#12),
    Machine6 = z80_cpu:step(Machine5),
    ?assertEqual(16#12, Machine6#machine_state.cpu#cpu_state.ixh),
    ?assertEqual(16#34, Machine6#machine_state.cpu#cpu_state.ixl),
    ?assertEqual(none, Machine6#machine_state.cpu#cpu_state.prefix).

%% --- Undocumented DD/FD Instructions (IXH, IXL, IYH, IYL) ---

dd_ld_ixh_n_test() ->
    Machine0 = ezx_emulator:init(),
    Machine1 = ezx_emulator:write_byte(Machine0, 0, 16#DD),
    Machine2 = ezx_emulator:write_byte(Machine1, 1, 16#26),  %% LD IXH,n
    Machine3 = ezx_emulator:write_byte(Machine2, 2, 16#42),
    Machine4 = z80_cpu:step(Machine3),
    ?assertEqual(16#42, Machine4#machine_state.cpu#cpu_state.ixh),
    ?assertEqual(0, Machine4#machine_state.cpu#cpu_state.ixl),
    ?assertEqual(none, Machine4#machine_state.cpu#cpu_state.prefix).

dd_ld_ixl_n_test() ->
    Machine0 = ezx_emulator:init(),
    Machine1 = ezx_emulator:write_byte(Machine0, 0, 16#DD),
    Machine2 = ezx_emulator:write_byte(Machine1, 1, 16#2E),  %% LD IXL,n
    Machine3 = ezx_emulator:write_byte(Machine2, 2, 16#37),
    Machine4 = z80_cpu:step(Machine3),
    ?assertEqual(0, Machine4#machine_state.cpu#cpu_state.ixh),
    ?assertEqual(16#37, Machine4#machine_state.cpu#cpu_state.ixl),
    ?assertEqual(none, Machine4#machine_state.cpu#cpu_state.prefix).

fd_ld_iyh_n_test() ->
    Machine0 = ezx_emulator:init(),
    Machine1 = ezx_emulator:write_byte(Machine0, 0, 16#FD),
    Machine2 = ezx_emulator:write_byte(Machine1, 1, 16#26),  %% LD IYH,n
    Machine3 = ezx_emulator:write_byte(Machine2, 2, 16#55),
    Machine4 = z80_cpu:step(Machine3),
    ?assertEqual(16#55, Machine4#machine_state.cpu#cpu_state.iyh),
    ?assertEqual(0, Machine4#machine_state.cpu#cpu_state.iyl),
    ?assertEqual(none, Machine4#machine_state.cpu#cpu_state.prefix).

fd_ld_iyl_n_test() ->
    Machine0 = ezx_emulator:init(),
    Machine1 = ezx_emulator:write_byte(Machine0, 0, 16#FD),
    Machine2 = ezx_emulator:write_byte(Machine1, 1, 16#2E),  %% LD IYL,n
    Machine3 = ezx_emulator:write_byte(Machine2, 2, 16#66),
    Machine4 = z80_cpu:step(Machine3),
    ?assertEqual(0, Machine4#machine_state.cpu#cpu_state.iyh),
    ?assertEqual(16#66, Machine4#machine_state.cpu#cpu_state.iyl),
    ?assertEqual(none, Machine4#machine_state.cpu#cpu_state.prefix).

dd_ld_ixh_ixl_test() ->
    %% LD IXH, IXL (DD 65 = LD H,L -> LD IXH, IXL)
    Machine0 = ezx_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{ixh = 16#12, ixl = 16#34},
    Machine1 = Machine0#machine_state{cpu = Cpu0},
    Machine2 = ezx_emulator:write_byte(Machine1, 0, 16#DD),
    Machine3 = ezx_emulator:write_byte(Machine2, 1, 16#65),  %% LD IXH, IXL (DD 65)
    Machine4 = z80_cpu:step(Machine3),
    ?assertEqual(16#34, Machine4#machine_state.cpu#cpu_state.ixh),
    ?assertEqual(16#34, Machine4#machine_state.cpu#cpu_state.ixl),
    ?assertEqual(none, Machine4#machine_state.cpu#cpu_state.prefix).

dd_ld_ixl_ixh_test() ->
    %% LD IXL, IXH (DD 6D = LD L,L -> LD IXL, IXL - copies IXL to itself, not useful)
    %% For LD IXL, IXH we need a different opcode, but there's no direct opcode
    %% Test LD IXL, IXL instead (copies IXL to itself)
    Machine0 = ezx_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{ixh = 16#12, ixl = 16#34},
    Machine1 = Machine0#machine_state{cpu = Cpu0},
    Machine2 = ezx_emulator:write_byte(Machine1, 0, 16#DD),
    Machine3 = ezx_emulator:write_byte(Machine2, 1, 16#6D),  %% LD IXL, IXL (DD 6D)
    Machine4 = z80_cpu:step(Machine3),
    ?assertEqual(16#12, Machine4#machine_state.cpu#cpu_state.ixh),
    ?assertEqual(16#34, Machine4#machine_state.cpu#cpu_state.ixl),
    ?assertEqual(none, Machine4#machine_state.cpu#cpu_state.prefix).

dd_inc_ixh_test() ->
    Machine0 = ezx_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{ixh = 16#12, ixl = 16#34},
    Machine1 = Machine0#machine_state{cpu = Cpu0},
    Machine2 = ezx_emulator:write_byte(Machine1, 0, 16#DD),
    Machine3 = ezx_emulator:write_byte(Machine2, 1, 16#24),  %% INC IXH
    Machine4 = z80_cpu:step(Machine3),
    ?assertEqual(16#13, Machine4#machine_state.cpu#cpu_state.ixh),
    ?assertEqual(16#34, Machine4#machine_state.cpu#cpu_state.ixl),
    ?assertEqual(none, Machine4#machine_state.cpu#cpu_state.prefix).

dd_inc_ixl_test() ->
    Machine0 = ezx_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{ixh = 16#12, ixl = 16#34},
    Machine1 = Machine0#machine_state{cpu = Cpu0},
    Machine2 = ezx_emulator:write_byte(Machine1, 0, 16#DD),
    Machine3 = ezx_emulator:write_byte(Machine2, 1, 16#2C),  %% INC IXL
    Machine4 = z80_cpu:step(Machine3),
    ?assertEqual(16#12, Machine4#machine_state.cpu#cpu_state.ixh),
    ?assertEqual(16#35, Machine4#machine_state.cpu#cpu_state.ixl),
    ?assertEqual(none, Machine4#machine_state.cpu#cpu_state.prefix).

dd_add_ix_ix_test() ->
    %% ADD IX,IX (undocumented but works)
    Machine0 = ezx_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{ixh = 16#20, ixl = 16#00},
    Machine1 = Machine0#machine_state{cpu = Cpu0},
    Machine2 = ezx_emulator:write_byte(Machine1, 0, 16#DD),
    Machine3 = ezx_emulator:write_byte(Machine2, 1, 16#29),  %% ADD IX,IX
    Machine4 = z80_cpu:step(Machine3),
    ?assertEqual(16#40, Machine4#machine_state.cpu#cpu_state.ixh),
    ?assertEqual(16#00, Machine4#machine_state.cpu#cpu_state.ixl),
    ?assertEqual(none, Machine4#machine_state.cpu#cpu_state.prefix).

fd_add_iy_iy_test() ->
    %% ADD IY,IY (undocumented but works)
    Machine0 = ezx_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{iyh = 16#20, iyl = 16#00},
    Machine1 = Machine0#machine_state{cpu = Cpu0},
    Machine2 = ezx_emulator:write_byte(Machine1, 0, 16#FD),
    Machine3 = ezx_emulator:write_byte(Machine2, 1, 16#29),  %% ADD IY,IY
    Machine4 = z80_cpu:step(Machine3),
    ?assertEqual(16#40, Machine4#machine_state.cpu#cpu_state.iyh),
    ?assertEqual(16#00, Machine4#machine_state.cpu#cpu_state.iyl),
    ?assertEqual(none, Machine4#machine_state.cpu#cpu_state.prefix).

dd_add_ix_sp_test() ->
    %% ADD IX,SP (DD 39)
    Machine0 = ezx_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{ixh = 16#20, ixl = 16#00, sp = 16#1000},
    Machine1 = Machine0#machine_state{cpu = Cpu0},
    Machine2 = ezx_emulator:write_byte(Machine1, 0, 16#DD),
    Machine3 = ezx_emulator:write_byte(Machine2, 1, 16#39),  %% ADD IX,SP
    Machine4 = z80_cpu:step(Machine3),
    ?assertEqual(16#30, Machine4#machine_state.cpu#cpu_state.ixh),  %% 0x2000 + 0x1000 = 0x3000
    ?assertEqual(16#00, Machine4#machine_state.cpu#cpu_state.ixl),
    ?assertEqual(none, Machine4#machine_state.cpu#cpu_state.prefix).

fd_add_iy_sp_test() ->
    %% ADD IY,SP (FD 39)
    Machine0 = ezx_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{iyh = 16#20, iyl = 16#00, sp = 16#1000},
    Machine1 = Machine0#machine_state{cpu = Cpu0},
    Machine2 = ezx_emulator:write_byte(Machine1, 0, 16#FD),
    Machine3 = ezx_emulator:write_byte(Machine2, 1, 16#39),  %% ADD IY,SP
    Machine4 = z80_cpu:step(Machine3),
    ?assertEqual(16#30, Machine4#machine_state.cpu#cpu_state.iyh),
    ?assertEqual(16#00, Machine4#machine_state.cpu#cpu_state.iyl),
    ?assertEqual(none, Machine4#machine_state.cpu#cpu_state.prefix).

dd_ex_de_ix_test() ->
    %% EX DE,IX (DD EB)
    Machine0 = ezx_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{d = 16#12, e = 16#34, ixh = 16#56, ixl = 16#78},
    Machine1 = Machine0#machine_state{cpu = Cpu0},
    Machine2 = ezx_emulator:write_byte(Machine1, 0, 16#DD),
    Machine3 = ezx_emulator:write_byte(Machine2, 1, 16#EB),  %% EX DE,IX
    Machine4 = z80_cpu:step(Machine3),
    ?assertEqual(16#56, Machine4#machine_state.cpu#cpu_state.d),  %% DE gets IX
    ?assertEqual(16#78, Machine4#machine_state.cpu#cpu_state.e),
    ?assertEqual(16#12, Machine4#machine_state.cpu#cpu_state.ixh),  %% IX gets DE
    ?assertEqual(16#34, Machine4#machine_state.cpu#cpu_state.ixl),
    ?assertEqual(none, Machine4#machine_state.cpu#cpu_state.prefix).

fd_ex_de_iy_test() ->
    %% EX DE,IY (FD EB)
    Machine0 = ezx_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{d = 16#12, e = 16#34, iyh = 16#56, iyl = 16#78},
    Machine1 = Machine0#machine_state{cpu = Cpu0},
    Machine2 = ezx_emulator:write_byte(Machine1, 0, 16#FD),
    Machine3 = ezx_emulator:write_byte(Machine2, 1, 16#EB),  %% EX DE,IY
    Machine4 = z80_cpu:step(Machine3),
    ?assertEqual(16#56, Machine4#machine_state.cpu#cpu_state.d),  %% DE gets IY
    ?assertEqual(16#78, Machine4#machine_state.cpu#cpu_state.e),
    ?assertEqual(16#12, Machine4#machine_state.cpu#cpu_state.iyh),  %% IY gets DE
    ?assertEqual(16#34, Machine4#machine_state.cpu#cpu_state.iyl),
    ?assertEqual(none, Machine4#machine_state.cpu#cpu_state.prefix).

dd_jp_ix_test() ->
    %% JP (IX) (DD E9)
    Machine0 = ezx_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{ixh = 16#12, ixl = 16#34},
    Machine1 = Machine0#machine_state{cpu = Cpu0},
    Machine2 = ezx_emulator:write_byte(Machine1, 0, 16#DD),
    Machine3 = ezx_emulator:write_byte(Machine2, 1, 16#E9),  %% JP (IX)
    Machine4 = z80_cpu:step(Machine3),
    ?assertEqual(16#1234, Machine4#machine_state.cpu#cpu_state.pc),
    ?assertEqual(none, Machine4#machine_state.cpu#cpu_state.prefix).

fd_jp_iy_test() ->
    %% JP (IY) (FD E9)
    Machine0 = ezx_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{iyh = 16#56, iyl = 16#78},
    Machine1 = Machine0#machine_state{cpu = Cpu0},
    Machine2 = ezx_emulator:write_byte(Machine1, 0, 16#FD),
    Machine3 = ezx_emulator:write_byte(Machine2, 1, 16#E9),  %% JP (IY)
    Machine4 = z80_cpu:step(Machine3),
    ?assertEqual(16#5678, Machine4#machine_state.cpu#cpu_state.pc),
    ?assertEqual(none, Machine4#machine_state.cpu#cpu_state.prefix).

%% --- DD/FD E3: EX (SP),IX / EX (SP),IY ---

dd_ex_sp_ix_test() ->
    %% EX (SP),IX (DD E3)
    Machine0 = ezx_emulator:init(),
    Machine1 = ezx_emulator:write_byte(Machine0, 16#FF00, 16#12),
    Machine2 = ezx_emulator:write_byte(Machine1, 16#FF01, 16#34),
    Cpu0 = Machine2#machine_state.cpu#cpu_state{ixh = 16#56, ixl = 16#78, sp = 16#FF00},
    Machine3 = Machine2#machine_state{cpu = Cpu0},
    Machine4 = ezx_emulator:write_byte(Machine3, 0, 16#DD),
    Machine5 = ezx_emulator:write_byte(Machine4, 1, 16#E3),  %% EX (SP),IX
    Machine6 = z80_cpu:step(Machine5),
    %% Stack has 0x12 at FF00, 0x34 at FF01 = word 0x3412 (little-endian)
    %% IX should get 0x3412 -> ixh=0x34, ixl=0x12
    ?assertEqual(16#34, Machine6#machine_state.cpu#cpu_state.ixh),
    ?assertEqual(16#12, Machine6#machine_state.cpu#cpu_state.ixl),
    %% Stack should get old IX value (0x5678) -> 0x78 at FF00, 0x56 at FF01
    ?assertEqual(16#78, ezx_emulator:read_byte(Machine6, 16#FF00)),
    ?assertEqual(16#56, ezx_emulator:read_byte(Machine6, 16#FF01)),
    ?assertEqual(none, Machine6#machine_state.cpu#cpu_state.prefix),
    ?assertEqual(23, z80_cpu:t_states(Machine6)).

fd_ex_sp_iy_test() ->
    %% EX (SP),IY (FD E3)
    Machine0 = ezx_emulator:init(),
    Machine1 = ezx_emulator:write_byte(Machine0, 16#FF00, 16#9A),
    Machine2 = ezx_emulator:write_byte(Machine1, 16#FF01, 16#BC),
    Cpu0 = Machine2#machine_state.cpu#cpu_state{iyh = 16#DE, iyl = 16#F0, sp = 16#FF00},
    Machine3 = Machine2#machine_state{cpu = Cpu0},
    Machine4 = ezx_emulator:write_byte(Machine3, 0, 16#FD),
    Machine5 = ezx_emulator:write_byte(Machine4, 1, 16#E3),  %% EX (SP),IY
    Machine6 = z80_cpu:step(Machine5),
    %% Stack has 0x9A at FF00, 0xBC at FF01 = word 0xBC9A (little-endian)
    %% IY should get 0xBC9A -> iyh=0xBC, iyl=0x9A
    ?assertEqual(16#BC, Machine6#machine_state.cpu#cpu_state.iyh),
    ?assertEqual(16#9A, Machine6#machine_state.cpu#cpu_state.iyl),
    %% Stack should get old IY value (0xDEF0) -> 0xF0 at FF00, 0xDE at FF01
    ?assertEqual(16#F0, ezx_emulator:read_byte(Machine6, 16#FF00)),
    ?assertEqual(16#DE, ezx_emulator:read_byte(Machine6, 16#FF01)),
    ?assertEqual(none, Machine6#machine_state.cpu#cpu_state.prefix),
    ?assertEqual(23, z80_cpu:t_states(Machine6)).

%% --- DD/FD with (HL) memory access using IX/IY ---

dd_ld_r_mem_ix_test() ->
    %% LD B,(IX+d) - 16#DD 16#46 dd
    Machine0 = ezx_emulator:init(),
    Machine1 = ezx_emulator:write_byte(Machine0, 16#4000, 16#55),
    Cpu0 = Machine1#machine_state.cpu#cpu_state{ixh = 16#40, ixl = 16#00},
    Machine2 = Machine1#machine_state{cpu = Cpu0},
    Machine3 = ezx_emulator:write_byte(Machine2, 0, 16#DD),
    Machine4 = ezx_emulator:write_byte(Machine3, 1, 16#46),  %% LD B,(IX+0)
    Machine5 = ezx_emulator:write_byte(Machine4, 2, 16#00),  %% displacement 0
    Machine6 = z80_cpu:step(Machine5),
    ?assertEqual(16#55, Machine6#machine_state.cpu#cpu_state.b),
    ?assertEqual(none, Machine6#machine_state.cpu#cpu_state.prefix).

dd_ld_r_mem_ix_disp_test() ->
    %% LD C,(IX+5) - 16#DD 16#4E 05
    Machine0 = ezx_emulator:init(),
    Machine1 = ezx_emulator:write_byte(Machine0, 16#4005, 16#AA),
    Cpu0 = Machine1#machine_state.cpu#cpu_state{ixh = 16#40, ixl = 16#00},
    Machine2 = Machine1#machine_state{cpu = Cpu0},
    Machine3 = ezx_emulator:write_byte(Machine2, 0, 16#DD),
    Machine4 = ezx_emulator:write_byte(Machine3, 1, 16#4E),  %% LD C,(IX+d)
    Machine5 = ezx_emulator:write_byte(Machine4, 2, 16#05),  %% displacement +5
    Machine6 = z80_cpu:step(Machine5),
    ?assertEqual(16#AA, Machine6#machine_state.cpu#cpu_state.c),
    ?assertEqual(none, Machine6#machine_state.cpu#cpu_state.prefix).

fd_ld_r_mem_iy_test() ->
    %% LD D,(IY+0) - 16#FD 16#56 00
    Machine0 = ezx_emulator:init(),
    Machine1 = ezx_emulator:write_byte(Machine0, 16#5000, 16#CC),
    Cpu0 = Machine1#machine_state.cpu#cpu_state{iyh = 16#50, iyl = 16#00},
    Machine2 = Machine1#machine_state{cpu = Cpu0},
    Machine3 = ezx_emulator:write_byte(Machine2, 0, 16#FD),
    Machine4 = ezx_emulator:write_byte(Machine3, 1, 16#56),  %% LD D,(IY+0)
    Machine5 = ezx_emulator:write_byte(Machine4, 2, 16#00),
    Machine6 = z80_cpu:step(Machine5),
    ?assertEqual(16#CC, Machine6#machine_state.cpu#cpu_state.d),
    ?assertEqual(none, Machine6#machine_state.cpu#cpu_state.prefix).

dd_ld_mem_ix_r_test() ->
    %% LD (IX+3),B - 16#DD 16#70 03
    Machine0 = ezx_emulator:init(),
    Cpu0 = Machine0#machine_state.cpu#cpu_state{ixh = 16#40, ixl = 16#00, b = 16#EE},
    Machine1 = Machine0#machine_state{cpu = Cpu0},
    Machine2 = ezx_emulator:write_byte(Machine1, 0, 16#DD),
    Machine3 = ezx_emulator:write_byte(Machine2, 1, 16#70),  %% LD (IX+d),B
    Machine4 = ezx_emulator:write_byte(Machine3, 2, 16#03),  %% displacement +3
    Machine5 = z80_cpu:step(Machine4),
    ?assertEqual(16#EE, ezx_emulator:read_byte(Machine5, 16#4003)),
    ?assertEqual(none, Machine5#machine_state.cpu#cpu_state.prefix).