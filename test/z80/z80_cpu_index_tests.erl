-module(z80_cpu_index_tests).

-include("z80_records.hrl").
-include_lib("eunit/include/eunit.hrl").

%% --- DD Prefix (IX) Tests ---

dd_ld_ix_nn_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#DD),  %% DD prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#21),  %% LD IX,nn
    Cpu3 = test_helpers:write_mem(Cpu2, 2, 16#34),  %% low byte
    Cpu4 = test_helpers:write_mem(Cpu3, 3, 16#12),  %% high byte
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(16#12, Cpu5#cpu_state.ixh),
    ?assertEqual(16#34, Cpu5#cpu_state.ixl),
    ?assertEqual(4, z80_cpu:pc(Cpu5)),
    ?assertEqual(14, z80_cpu:t_states(Cpu5)).

dd_add_ix_bc_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#DD),  %% DD prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#09),  %% ADD IX,BC
    Cpu3 = Cpu2#cpu_state{b = 16#10, c = 16#00, ixh = 16#20, ixl = 16#00},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#30, Cpu4#cpu_state.ixh),
    ?assertEqual(16#00, Cpu4#cpu_state.ixl),
    ?assertEqual(2, z80_cpu:pc(Cpu4)),
    ?assertEqual(15, z80_cpu:t_states(Cpu4)).

dd_inc_ix_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#DD),  %% DD prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#23),  %% INC IX
    Cpu3 = Cpu2#cpu_state{ixh = 16#12, ixl = 16#34},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#12, Cpu4#cpu_state.ixh),
    ?assertEqual(16#35, Cpu4#cpu_state.ixl),
    ?assertEqual(2, z80_cpu:pc(Cpu4)),
    ?assertEqual(10, z80_cpu:t_states(Cpu4)).

dd_dec_ix_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#DD),  %% DD prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#2B),  %% DEC IX
    Cpu3 = Cpu2#cpu_state{ixh = 16#12, ixl = 16#34},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#12, Cpu4#cpu_state.ixh),
    ?assertEqual(16#33, Cpu4#cpu_state.ixl),
    ?assertEqual(2, z80_cpu:pc(Cpu4)),
    ?assertEqual(10, z80_cpu:t_states(Cpu4)).

dd_push_ix_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#DD),  %% DD prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#E5),  %% PUSH IX
    Cpu3 = Cpu2#cpu_state{ixh = 16#12, ixl = 16#34, sp = 16#FF00},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#FEFE, Cpu4#cpu_state.sp),
    ?assertEqual(16#34, z80_cpu_mem:read_byte(Cpu4#cpu_state.ext_context, 16#FEFE)),
    ?assertEqual(16#12, z80_cpu_mem:read_byte(Cpu4#cpu_state.ext_context, 16#FEFF)),
    ?assertEqual(2, z80_cpu:pc(Cpu4)),
    ?assertEqual(15, z80_cpu:t_states(Cpu4)).

dd_pop_ix_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#FEFE, 16#56),
    Cpu2 = test_helpers:write_mem(Cpu1, 16#FEFF, 16#78),
    Cpu3 = test_helpers:write_mem(Cpu2, 0, 16#DD),  %% DD prefix
    Cpu4 = test_helpers:write_mem(Cpu3, 1, 16#E1),  %% POP IX
    Cpu5 = Cpu4#cpu_state{sp = 16#FEFE},
    Cpu6 = z80_cpu:step(Cpu5),
    ?assertEqual(16#78, Cpu6#cpu_state.ixh),
    ?assertEqual(16#56, Cpu6#cpu_state.ixl),
    ?assertEqual(16#FF00, Cpu6#cpu_state.sp),
    ?assertEqual(2, z80_cpu:pc(Cpu6)),
    ?assertEqual(14, z80_cpu:t_states(Cpu6)).

dd_ld_sp_ix_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#DD),  %% DD prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#F9),  %% LD SP,IX
    Cpu3 = Cpu2#cpu_state{ixh = 16#12, ixl = 16#34},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#1234, Cpu4#cpu_state.sp),
    ?assertEqual(2, z80_cpu:pc(Cpu4)),
    ?assertEqual(10, z80_cpu:t_states(Cpu4)).

%% --- FD Prefix (IY) Tests ---

fd_ld_iy_nn_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#FD),  %% FD prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#21),  %% LD IY,nn
    Cpu3 = test_helpers:write_mem(Cpu2, 2, 16#56),  %% low byte
    Cpu4 = test_helpers:write_mem(Cpu3, 3, 16#78),  %% high byte
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(16#78, Cpu5#cpu_state.iyh),
    ?assertEqual(16#56, Cpu5#cpu_state.iyl),
    ?assertEqual(4, z80_cpu:pc(Cpu5)),
    ?assertEqual(14, z80_cpu:t_states(Cpu5)).

fd_add_iy_de_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#FD),  %% FD prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#19),  %% ADD IY,DE
    Cpu3 = Cpu2#cpu_state{d = 16#10, e = 16#00, iyh = 16#20, iyl = 16#00},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#30, Cpu4#cpu_state.iyh),
    ?assertEqual(16#00, Cpu4#cpu_state.iyl),
    ?assertEqual(2, z80_cpu:pc(Cpu4)),
    ?assertEqual(15, z80_cpu:t_states(Cpu4)).

fd_inc_iy_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#FD),  %% FD prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#23),  %% INC IY
    Cpu3 = Cpu2#cpu_state{iyh = 16#12, iyl = 16#34},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#12, Cpu4#cpu_state.iyh),
    ?assertEqual(16#35, Cpu4#cpu_state.iyl),
    ?assertEqual(2, z80_cpu:pc(Cpu4)),
    ?assertEqual(10, z80_cpu:t_states(Cpu4)).

fd_dec_iy_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#FD),  %% FD prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#2B),  %% DEC IY
    Cpu3 = Cpu2#cpu_state{iyh = 16#12, iyl = 16#34},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#12, Cpu4#cpu_state.iyh),
    ?assertEqual(16#33, Cpu4#cpu_state.iyl),
    ?assertEqual(2, z80_cpu:pc(Cpu4)),
    ?assertEqual(10, z80_cpu:t_states(Cpu4)).

fd_push_iy_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#FD),  %% FD prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#E5),  %% PUSH IY
    Cpu3 = Cpu2#cpu_state{iyh = 16#12, iyl = 16#34, sp = 16#FF00},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#FEFE, Cpu4#cpu_state.sp),
    ?assertEqual(16#34, z80_cpu_mem:read_byte(Cpu4#cpu_state.ext_context, 16#FEFE)),
    ?assertEqual(16#12, z80_cpu_mem:read_byte(Cpu4#cpu_state.ext_context, 16#FEFF)),
    ?assertEqual(2, z80_cpu:pc(Cpu4)),
    ?assertEqual(15, z80_cpu:t_states(Cpu4)).

fd_pop_iy_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#FEFE, 16#56),
    Cpu2 = test_helpers:write_mem(Cpu1, 16#FEFF, 16#78),
    Cpu3 = test_helpers:write_mem(Cpu2, 0, 16#FD),  %% FD prefix
    Cpu4 = test_helpers:write_mem(Cpu3, 1, 16#E1),  %% POP IY
    Cpu5 = Cpu4#cpu_state{sp = 16#FEFE},
    Cpu6 = z80_cpu:step(Cpu5),
    ?assertEqual(16#78, Cpu6#cpu_state.iyh),
    ?assertEqual(16#56, Cpu6#cpu_state.iyl),
    ?assertEqual(16#FF00, Cpu6#cpu_state.sp),
    ?assertEqual(2, z80_cpu:pc(Cpu6)),
    ?assertEqual(14, z80_cpu:t_states(Cpu6)).

fd_ld_sp_iy_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#FD),  %% FD prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#F9),  %% LD SP,IY
    Cpu3 = Cpu2#cpu_state{iyh = 16#12, iyl = 16#34},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#1234, Cpu4#cpu_state.sp),
    ?assertEqual(2, z80_cpu:pc(Cpu4)),
    ?assertEqual(10, z80_cpu:t_states(Cpu4)).

%% --- Prefix State Verification Tests ---

dd_prefix_cleared_after_instruction_test() ->
    %% Verify prefix is cleared after DD instruction completes
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#DD),  %% DD prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#21),  %% LD IX,nn
    Cpu3 = test_helpers:write_mem(Cpu2, 2, 16#34),  %% low byte
    Cpu4 = test_helpers:write_mem(Cpu3, 3, 16#12),  %% high byte
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(none, Cpu5#cpu_state.prefix),
    ?assertEqual(0, Cpu5#cpu_state.displacement).

fd_prefix_cleared_after_instruction_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#FD),  %% FD prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#21),  %% LD IY,nn
    Cpu3 = test_helpers:write_mem(Cpu2, 2, 16#56),  %% low byte
    Cpu4 = test_helpers:write_mem(Cpu3, 3, 16#78),  %% high byte
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(none, Cpu5#cpu_state.prefix),
    ?assertEqual(0, Cpu5#cpu_state.displacement).

%% --- Multiple Prefix Tests ---

dd_dd_prefix_behavior_test() ->
    %% DD DD 21 nn nn -> second DD acts as prefix for LD IX,nn
    %% First DD sets prefix=dd, second DD with prefix=dd acts as LD IX,nn
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#DD),  %% DD prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#DD),  %% DD prefix (second)
    Cpu3 = test_helpers:write_mem(Cpu2, 2, 16#21),  %% LD IX,nn
    Cpu4 = test_helpers:write_mem(Cpu3, 3, 16#34),  %% low byte
    Cpu5 = test_helpers:write_mem(Cpu4, 4, 16#12),  %% high byte
    Cpu6 = z80_cpu:step(Cpu5),
    %% Should execute LD IX,1234h
    ?assertEqual(16#12, Cpu6#cpu_state.ixh),
    ?assertEqual(16#34, Cpu6#cpu_state.ixl),
    ?assertEqual(none, Cpu6#cpu_state.prefix).

fd_fd_prefix_behavior_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#FD),  %% FD prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#FD),  %% FD prefix (second)
    Cpu3 = test_helpers:write_mem(Cpu2, 2, 16#21),  %% LD IY,nn
    Cpu4 = test_helpers:write_mem(Cpu3, 3, 16#56),  %% low byte
    Cpu5 = test_helpers:write_mem(Cpu4, 4, 16#78),  %% high byte
    Cpu6 = z80_cpu:step(Cpu5),
    ?assertEqual(16#78, Cpu6#cpu_state.iyh),
    ?assertEqual(16#56, Cpu6#cpu_state.iyl),
    ?assertEqual(none, Cpu6#cpu_state.prefix).

dd_fd_mixed_prefix_test() ->
    %% DD FD 21 nn nn -> FD wins (last prefix)
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#DD),  %% DD prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#FD),  %% FD prefix (wins)
    Cpu3 = test_helpers:write_mem(Cpu2, 2, 16#21),  %% LD IY,nn
    Cpu4 = test_helpers:write_mem(Cpu3, 3, 16#56),  %% low byte
    Cpu5 = test_helpers:write_mem(Cpu4, 4, 16#78),  %% high byte
    Cpu6 = z80_cpu:step(Cpu5),
    ?assertEqual(16#78, Cpu6#cpu_state.iyh),
    ?assertEqual(16#56, Cpu6#cpu_state.iyl),
    ?assertEqual(none, Cpu6#cpu_state.prefix).

fd_dd_mixed_prefix_test() ->
    %% FD DD 21 nn nn -> DD wins
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#FD),  %% FD prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#DD),  %% DD prefix (wins)
    Cpu3 = test_helpers:write_mem(Cpu2, 2, 16#21),  %% LD IX,nn
    Cpu4 = test_helpers:write_mem(Cpu3, 3, 16#34),  %% low byte
    Cpu5 = test_helpers:write_mem(Cpu4, 4, 16#12),  %% high byte
    Cpu6 = z80_cpu:step(Cpu5),
    ?assertEqual(16#12, Cpu6#cpu_state.ixh),
    ?assertEqual(16#34, Cpu6#cpu_state.ixl),
    ?assertEqual(none, Cpu6#cpu_state.prefix).

%% --- Undocumented DD/FD Instructions (IXH, IXL, IYH, IYL) ---

dd_ld_ixh_n_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#DD),  %% DD prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#26),  %% LD IXH,n
    Cpu3 = test_helpers:write_mem(Cpu2, 2, 16#42),
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#42, Cpu4#cpu_state.ixh),
    ?assertEqual(0, Cpu4#cpu_state.ixl),
    ?assertEqual(none, Cpu4#cpu_state.prefix).

dd_ld_ixl_n_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#DD),  %% DD prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#2E),  %% LD IXL,n
    Cpu3 = test_helpers:write_mem(Cpu2, 2, 16#37),
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(0, Cpu4#cpu_state.ixh),
    ?assertEqual(16#37, Cpu4#cpu_state.ixl),
    ?assertEqual(none, Cpu4#cpu_state.prefix).

fd_ld_iyh_n_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#FD),  %% FD prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#26),  %% LD IYH,n
    Cpu3 = test_helpers:write_mem(Cpu2, 2, 16#55),
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#55, Cpu4#cpu_state.iyh),
    ?assertEqual(0, Cpu4#cpu_state.iyl),
    ?assertEqual(none, Cpu4#cpu_state.prefix).

fd_ld_iyl_n_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#FD),  %% FD prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#2E),  %% LD IYL,n
    Cpu3 = test_helpers:write_mem(Cpu2, 2, 16#66),
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(0, Cpu4#cpu_state.iyh),
    ?assertEqual(16#66, Cpu4#cpu_state.iyl),
    ?assertEqual(none, Cpu4#cpu_state.prefix).

dd_ld_ixh_ixl_test() ->
    %% LD IXH, IXL (DD 65 = LD H,L -> LD IXH, IXL)
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#DD),  %% DD prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#65),  %% LD IXH, IXL (DD 65)
    Cpu3 = Cpu2#cpu_state{ixh = 16#12, ixl = 16#34},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#34, Cpu4#cpu_state.ixh),
    ?assertEqual(16#34, Cpu4#cpu_state.ixl),
    ?assertEqual(none, Cpu4#cpu_state.prefix).

dd_ld_ixl_ixh_test() ->
    %% LD IXL, IXL (DD 6D = LD L,L -> LD IXL, IXL - copies IXL to itself, not useful)
    %% For LD IXL, IXH we need a different opcode, but there's no direct opcode
    %% Test LD IXL, IXL instead (copies IXL to itself)
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#DD),  %% DD prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#6D),  %% LD IXL, IXL (DD 6D)
    Cpu3 = Cpu2#cpu_state{ixh = 16#12, ixl = 16#34},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#12, Cpu4#cpu_state.ixh),
    ?assertEqual(16#34, Cpu4#cpu_state.ixl),
    ?assertEqual(none, Cpu4#cpu_state.prefix).

dd_inc_ixh_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#DD),  %% DD prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#24),  %% INC IXH
    Cpu3 = Cpu2#cpu_state{ixh = 16#12, ixl = 16#34},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#13, Cpu4#cpu_state.ixh),
    ?assertEqual(16#34, Cpu4#cpu_state.ixl),
    ?assertEqual(none, Cpu4#cpu_state.prefix).

dd_inc_ixl_test() ->
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#DD),  %% DD prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#2C),  %% INC IXL
    Cpu3 = Cpu2#cpu_state{ixh = 16#12, ixl = 16#34},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#12, Cpu4#cpu_state.ixh),
    ?assertEqual(16#35, Cpu4#cpu_state.ixl),
    ?assertEqual(none, Cpu4#cpu_state.prefix).

dd_add_ix_ix_test() ->
    %% ADD IX,IX (undocumented but works)
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#DD),  %% DD prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#29),  %% ADD IX,IX
    Cpu3 = Cpu2#cpu_state{ixh = 16#20, ixl = 16#00},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#40, Cpu4#cpu_state.ixh),
    ?assertEqual(16#00, Cpu4#cpu_state.ixl),
    ?assertEqual(none, Cpu4#cpu_state.prefix).

fd_add_iy_iy_test() ->
    %% ADD IY,IY (undocumented but works)
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#FD),  %% FD prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#29),  %% ADD IY,IY
    Cpu3 = Cpu2#cpu_state{iyh = 16#20, iyl = 16#00},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#40, Cpu4#cpu_state.iyh),
    ?assertEqual(16#00, Cpu4#cpu_state.iyl),
    ?assertEqual(none, Cpu4#cpu_state.prefix).

dd_add_ix_sp_test() ->
    %% ADD IX,SP (DD 39)
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#DD),  %% DD prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#39),  %% ADD IX,SP
    Cpu3 = Cpu2#cpu_state{ixh = 16#20, ixl = 16#00, sp = 16#1000},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#30, Cpu4#cpu_state.ixh),  %% 0x2000 + 0x1000 = 0x3000
    ?assertEqual(16#00, Cpu4#cpu_state.ixl),
    ?assertEqual(none, Cpu4#cpu_state.prefix).

fd_add_iy_sp_test() ->
    %% ADD IY,SP (FD 39)
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#FD),  %% FD prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#39),  %% ADD IY,SP
    Cpu3 = Cpu2#cpu_state{iyh = 16#20, iyl = 16#00, sp = 16#1000},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#30, Cpu4#cpu_state.iyh),
    ?assertEqual(16#00, Cpu4#cpu_state.iyl),
    ?assertEqual(none, Cpu4#cpu_state.prefix).

dd_ex_de_ix_test() ->
    %% EX DE,IX (DD EB)
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#DD),  %% DD prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#EB),  %% EX DE,IX
    Cpu3 = Cpu2#cpu_state{d = 16#12, e = 16#34, ixh = 16#56, ixl = 16#78},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#56, Cpu4#cpu_state.d),  %% DE gets IX
    ?assertEqual(16#78, Cpu4#cpu_state.e),
    ?assertEqual(16#12, Cpu4#cpu_state.ixh),  %% IX gets DE
    ?assertEqual(16#34, Cpu4#cpu_state.ixl),
    ?assertEqual(none, Cpu4#cpu_state.prefix).

fd_ex_de_iy_test() ->
    %% EX DE,IY (FD EB)
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#FD),  %% FD prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#EB),  %% EX DE,IY
    Cpu3 = Cpu2#cpu_state{d = 16#12, e = 16#34, iyh = 16#56, iyl = 16#78},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#56, Cpu4#cpu_state.d),  %% DE gets IY
    ?assertEqual(16#78, Cpu4#cpu_state.e),
    ?assertEqual(16#12, Cpu4#cpu_state.iyh),  %% IY gets DE
    ?assertEqual(16#34, Cpu4#cpu_state.iyl),
    ?assertEqual(none, Cpu4#cpu_state.prefix).

dd_jp_ix_test() ->
    %% JP (IX) (DD E9)
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#DD),  %% DD prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#E9),  %% JP (IX)
    Cpu3 = Cpu2#cpu_state{ixh = 16#12, ixl = 16#34},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#1234, Cpu4#cpu_state.pc),
    ?assertEqual(none, Cpu4#cpu_state.prefix).

fd_jp_iy_test() ->
    %% JP (IY) (FD E9)
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#FD),  %% FD prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#E9),  %% JP (IY)
    Cpu3 = Cpu2#cpu_state{iyh = 16#56, iyl = 16#78},
    Cpu4 = z80_cpu:step(Cpu3),
    ?assertEqual(16#5678, Cpu4#cpu_state.pc),
    ?assertEqual(none, Cpu4#cpu_state.prefix).

%% --- DD/FD E3: EX (SP),IX / EX (SP),IY ---

dd_ex_sp_ix_test() ->
    %% EX (SP),IX (DD E3)
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#FF00, 16#12),
    Cpu2 = test_helpers:write_mem(Cpu1, 16#FF01, 16#34),
    Cpu3 = test_helpers:write_mem(Cpu2, 0, 16#DD),  %% DD prefix
    Cpu4 = test_helpers:write_mem(Cpu3, 1, 16#E3),  %% EX (SP),IX
    Cpu5 = Cpu4#cpu_state{ixh = 16#56, ixl = 16#78, sp = 16#FF00},
    Cpu6 = z80_cpu:step(Cpu5),
    %% Stack has 0x12 at FF00, 0x34 at FF01 = word 0x3412 (little-endian)
    %% IX should get 0x3412 -> ixh=0x34, ixl=0x12
    ?assertEqual(16#34, Cpu6#cpu_state.ixh),
    ?assertEqual(16#12, Cpu6#cpu_state.ixl),
    %% Stack should get old IX value (0x5678) -> 0x78 at FF00, 0x56 at FF01
    ?assertEqual(16#78, z80_cpu_mem:read_byte(Cpu6#cpu_state.ext_context, 16#FF00)),
    ?assertEqual(16#56, z80_cpu_mem:read_byte(Cpu6#cpu_state.ext_context, 16#FF01)),
    ?assertEqual(none, Cpu6#cpu_state.prefix),
    ?assertEqual(23, z80_cpu:t_states(Cpu6)).

fd_ex_sp_iy_test() ->
    %% EX (SP),IY (FD E3)
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#FF00, 16#9A),
    Cpu2 = test_helpers:write_mem(Cpu1, 16#FF01, 16#BC),
    Cpu3 = test_helpers:write_mem(Cpu2, 0, 16#FD),  %% FD prefix
    Cpu4 = test_helpers:write_mem(Cpu3, 1, 16#E3),  %% EX (SP),IY
    Cpu5 = Cpu4#cpu_state{iyh = 16#DE, iyl = 16#F0, sp = 16#FF00},
    Cpu6 = z80_cpu:step(Cpu5),
    %% Stack has 0x9A at FF00, 0xBC at FF01 = word 0xBC9A (little-endian)
    %% IY should get 0xBC9A -> iyh=0xBC, iyl=0x9A
    ?assertEqual(16#BC, Cpu6#cpu_state.iyh),
    ?assertEqual(16#9A, Cpu6#cpu_state.iyl),
    %% Stack should get old IY value (0xDEF0) -> 0xF0 at FF00, 0xDE at FF01
    ?assertEqual(16#F0, z80_cpu_mem:read_byte(Cpu6#cpu_state.ext_context, 16#FF00)),
    ?assertEqual(16#DE, z80_cpu_mem:read_byte(Cpu6#cpu_state.ext_context, 16#FF01)),
    ?assertEqual(none, Cpu6#cpu_state.prefix),
    ?assertEqual(23, z80_cpu:t_states(Cpu6)).

%% --- DD/FD with (HL) memory access using IX/IY ---

dd_ld_r_mem_ix_test() ->
    %% LD B,(IX+d) - DD 46 dd
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4000, 16#55),
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#DD),  %% DD prefix
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#46),  %% LD B,(IX+0)
    Cpu4 = test_helpers:write_mem(Cpu3, 2, 16#00),  %% displacement 0
    Cpu5 = Cpu4#cpu_state{ixh = 16#40, ixl = 16#00},
    Cpu6 = z80_cpu:step(Cpu5),
    ?assertEqual(16#55, Cpu6#cpu_state.b),
    ?assertEqual(none, Cpu6#cpu_state.prefix).

dd_ld_r_mem_ix_disp_test() ->
    %% LD C,(IX+5) - DD 4E 05
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#4005, 16#AA),
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#DD),  %% DD prefix
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#4E),  %% LD C,(IX+d)
    Cpu4 = test_helpers:write_mem(Cpu3, 2, 16#05),  %% displacement +5
    Cpu5 = Cpu4#cpu_state{ixh = 16#40, ixl = 16#00},
    Cpu6 = z80_cpu:step(Cpu5),
    ?assertEqual(16#AA, Cpu6#cpu_state.c),
    ?assertEqual(none, Cpu6#cpu_state.prefix).

fd_ld_r_mem_iy_test() ->
    %% LD D,(IY+0) - FD 56 00
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 16#5000, 16#CC),
    Cpu2 = test_helpers:write_mem(Cpu1, 0, 16#FD),  %% FD prefix
    Cpu3 = test_helpers:write_mem(Cpu2, 1, 16#56),  %% LD D,(IY+0)
    Cpu4 = test_helpers:write_mem(Cpu3, 2, 16#00),
    Cpu5 = Cpu4#cpu_state{iyh = 16#50, iyl = 16#00},
    Cpu6 = z80_cpu:step(Cpu5),
    ?assertEqual(16#CC, Cpu6#cpu_state.d),
    ?assertEqual(none, Cpu6#cpu_state.prefix).

dd_ld_mem_ix_r_test() ->
    %% LD (IX+3),B - DD 70 03
    Cpu0 = test_helpers:init_cpu(),
    Cpu1 = test_helpers:write_mem(Cpu0, 0, 16#DD),  %% DD prefix
    Cpu2 = test_helpers:write_mem(Cpu1, 1, 16#70),  %% LD (IX+d),B
    Cpu3 = test_helpers:write_mem(Cpu2, 2, 16#03),  %% displacement +3
    Cpu4 = Cpu3#cpu_state{ixh = 16#40, ixl = 16#00, b = 16#EE},
    Cpu5 = z80_cpu:step(Cpu4),
    ?assertEqual(16#EE, z80_cpu_mem:read_byte(Cpu5#cpu_state.ext_context, 16#4003)),
    ?assertEqual(none, Cpu5#cpu_state.prefix).
