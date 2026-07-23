%% CPU register file and execution state for the Z80 core.
-record(cpu_state, {
    %% Main registers
    a = 16#FF, f = 16#FF,
    b = 16#FF, c = 16#FF,
    d = 16#FF, e = 16#FF,
    h = 16#FF, l = 16#FF,

    %% Shadow registers (used for EX AF,AF' and EXX)
    a_alt = 16#FF, f_alt = 16#FF,
    b_alt = 16#FF, c_alt = 16#FF,
    d_alt = 16#FF, e_alt = 16#FF,
    h_alt = 16#FF, l_alt = 16#FF,

    %% Index registers
    ixh = 16#FF, ixl = 16#FF,
    iyh = 16#FF, iyl = 16#FF,

    %% Special proposition registers
    pc = 0, %% Program counter register
    sp = 16#FFFF, %% Stack pointer register
    i  = 16#FF, %% Interrupt vector register
    r  = 16#FF, %% Memory refresh register

    %% Prefix state for DD/FD and DD CB/FD CB handling
    prefix = none :: none | dd | fd | dd_cb | fd_cb,
    displacement = 0 :: integer(),  % Signed displacement for DD CB / FD CB
    ei_block = 0 :: non_neg_integer(),  % EI blocks interrupts for N instructions (counter)

    %% Execution state
    iff1 = 0,   %% Interrupt flip-flops 1
    iff2 = 0,   %% Interrupt flip-flops 2
    im = 0,     %% Interrupt mode (0, 1, or 2)
    halted = false,
    t_states = 0,
    ext_context = undefined,
    mem_read_fun = undefined,
    mem_write_fun = undefined,
    port_read_fun = undefined,
    port_write_fun = undefined,
    pending_interrupt = none :: none | nmi | int
}).


%% Flag bitmasks inside the F register
-define(FLAG_C, 16#01). % Carry
-define(FLAG_N, 16#02). % Add/Subtract
-define(FLAG_V, 16#04). % Parity/Overflow
-define(FLAG_H, 16#10). % Half Carry
-define(FLAG_Z, 16#40). % Zero
-define(FLAG_S, 16#80). % Sign

%% Register access macros (CPU record only, no memory)
%% These expand to direct record field access for performance

%% 8-bit register getters
-define(GET_A(Cpu), (Cpu)#cpu_state.a).
-define(GET_F(Cpu), (Cpu)#cpu_state.f).
-define(GET_B(Cpu), (Cpu)#cpu_state.b).
-define(GET_C(Cpu), (Cpu)#cpu_state.c).
-define(GET_D(Cpu), (Cpu)#cpu_state.d).
-define(GET_E(Cpu), (Cpu)#cpu_state.e).
-define(GET_H(Cpu), (Cpu)#cpu_state.h).
-define(GET_L(Cpu), (Cpu)#cpu_state.l).
-define(GET_IXH(Cpu), (Cpu)#cpu_state.ixh).
-define(GET_IXL(Cpu), (Cpu)#cpu_state.ixl).
-define(GET_IYH(Cpu), (Cpu)#cpu_state.iyh).
-define(GET_IYL(Cpu), (Cpu)#cpu_state.iyl).
-define(GET_I(Cpu), (Cpu)#cpu_state.i).
-define(GET_R(Cpu), (Cpu)#cpu_state.r).
-define(GET_PC(Cpu), (Cpu)#cpu_state.pc).
-define(GET_SP(Cpu), (Cpu)#cpu_state.sp).
-define(GET_IFF1(Cpu), (Cpu)#cpu_state.iff1).
-define(GET_IFF2(Cpu), (Cpu)#cpu_state.iff2).
-define(GET_IM(Cpu), (Cpu)#cpu_state.im).
-define(GET_HALTED(Cpu), (Cpu)#cpu_state.halted).
-define(GET_T_STATES(Cpu), (Cpu)#cpu_state.t_states).
-define(GET_PREFIX(Cpu), (Cpu)#cpu_state.prefix).
-define(GET_DISPLACEMENT(Cpu), (Cpu)#cpu_state.displacement).

%% 8-bit register setters
-define(SET_A(Cpu, Val), (Cpu)#cpu_state{a = (Val) band 16#ff}).
-define(SET_F(Cpu, Val), (Cpu)#cpu_state{f = (Val) band 16#ff}).
-define(SET_B(Cpu, Val), (Cpu)#cpu_state{b = (Val) band 16#ff}).
-define(SET_C(Cpu, Val), (Cpu)#cpu_state{c = (Val) band 16#ff}).
-define(SET_D(Cpu, Val), (Cpu)#cpu_state{d = (Val) band 16#ff}).
-define(SET_E(Cpu, Val), (Cpu)#cpu_state{e = (Val) band 16#ff}).
-define(SET_H(Cpu, Val), (Cpu)#cpu_state{h = (Val) band 16#ff}).
-define(SET_L(Cpu, Val), (Cpu)#cpu_state{l = (Val) band 16#ff}).
-define(SET_IXH(Cpu, Val), (Cpu)#cpu_state{ixh = (Val) band 16#ff}).
-define(SET_IXL(Cpu, Val), (Cpu)#cpu_state{ixl = (Val) band 16#ff}).
-define(SET_IYH(Cpu, Val), (Cpu)#cpu_state{iyh = (Val) band 16#ff}).
-define(SET_IYL(Cpu, Val), (Cpu)#cpu_state{iyl = (Val) band 16#ff}).
-define(SET_I(Cpu, Val), (Cpu)#cpu_state{i = (Val) band 16#ff}).
-define(SET_R(Cpu, Val), (Cpu)#cpu_state{r = (Val) band 16#ff}).
-define(SET_PC(Cpu, Val), (Cpu)#cpu_state{pc = (Val) band 16#ffff}).
-define(SET_SP(Cpu, Val), (Cpu)#cpu_state{sp = (Val) band 16#ffff}).
-define(SET_IFF1(Cpu, Val), (Cpu)#cpu_state{iff1 = (Val)}).
-define(SET_IFF2(Cpu, Val), (Cpu)#cpu_state{iff2 = (Val)}).
-define(SET_IM(Cpu, Val), (Cpu)#cpu_state{im = (Val)}).
-define(SET_HALTED(Cpu, Val), (Cpu)#cpu_state{halted = (Val)}).
-define(SET_T_STATES(Cpu, Val), (Cpu)#cpu_state{t_states = (Val)}).
-define(SET_PREFIX(Cpu, Val), (Cpu)#cpu_state{prefix = (Val)}).
-define(SET_DISPLACEMENT(Cpu, Val), (Cpu)#cpu_state{displacement = (Val)}).

%% Pair helper macros
-define(MAKE_PAIR(H, L), (((H) band 16#ff) bsl 8) bor ((L) band 16#ff)).
-define(PAIR_HI(Pair), ((Pair) bsr 8) band 16#ff).
-define(PAIR_LO(Pair), (Pair) band 16#ff).

%% Signed byte conversion
-define(SIGNED_BYTE(B), if ((B) band 16#80) =:= 0 -> (B); true -> (B) - 256 end).