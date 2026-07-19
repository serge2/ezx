-module(z80_cpu).

-include("z80_records.hrl").

-export([
    init_state/4,
    step/1,
    run/2,
    request_interrupt/2,
    pc/1,
    t_states/1,

    get_reg_byte/2,
    set_reg_byte/3,
    get_reg_pair/2,
    set_reg_pair/3
]).

%% @doc Create a fresh CPU state with all callback functions.
-spec init_state(function(), function(), function(), function()) -> #cpu_state{}.
init_state(MemReadFun, MemWriteFun, PortReadFun, PortWriteFun) ->
    #cpu_state{
        mem_read_fun = MemReadFun,
        mem_write_fun = MemWriteFun,
        port_read_fun = PortReadFun,
        port_write_fun = PortWriteFun
    }.

%% @doc Return the current program counter from the machine state.
-spec pc(#cpu_state{}) -> non_neg_integer().
pc(#cpu_state{pc = Pc}) ->
    Pc.

%% @doc Return the accumulated T-state count from the machine state.
-spec t_states(#cpu_state{}) -> non_neg_integer().
t_states(#cpu_state{t_states = TStates}) ->
    TStates.

%% @doc Run a fixed number of CPU steps sequentially.
-spec run(#cpu_state{}, non_neg_integer()) -> #cpu_state{}.
run(State, 0) ->
    State;
run(State, N) ->
    run(step(State), N - 1).

%% @doc Queue an interrupt request for the next CPU step.
-spec request_interrupt(#cpu_state{}, int | nmi) -> #cpu_state{}.
request_interrupt(#cpu_state{} = State, Type) ->
    State#cpu_state{pending_interrupt = Type}.


step(#cpu_state{} = State) ->
    case maybe_handle_interrupt(State) of
        {handled, State1} -> State1;
        {not_handled, State1} ->
            case State1#cpu_state.halted of
                true ->
                    %% CPU is halted: execute NOP cycle (4 T-states) without advancing PC
                    State1#cpu_state{t_states = State1#cpu_state.t_states + 4};
                false ->
                    execute_next_instruction(State1)
            end
    end.

%% @doc Logic to handle pending interrupts.
maybe_handle_interrupt(State = #cpu_state{pending_interrupt = none}) ->
    {not_handled, State};

maybe_handle_interrupt(State = #cpu_state{pending_interrupt = int, iff1 = Iff1})
  when Iff1 =:= 0 ->
    {not_handled, State};

maybe_handle_interrupt(State = #cpu_state{pending_interrupt = int, ei_block = EiBlock})
  when EiBlock > 0 ->
    {not_handled, State#cpu_state{ei_block = EiBlock - 1}}; 

maybe_handle_interrupt(State = #cpu_state{pending_interrupt = int, im = Mode}) ->
    State1 = z80_cpu_helpers:push_word(State, State#cpu_state.pc),
    State2 = State1#cpu_state{
        iff1 = 0,
        iff2 = 0,
        halted = false,
        prefix = none,
        displacement = 0,
        pending_interrupt = none
    },
    case Mode of
        0 ->
            %% IM 0: execute instruction from data bus (default RST 38h = 0xFF)
            BusByte = 16#FF,
            State3 = execute_opcode_base(BusByte, State2#cpu_state{t_states = State1#cpu_state.t_states + 13}),
            {handled, State3};
        1 ->
            %% IM 1: jump to 0x0038
            State3 = State2#cpu_state{
                pc = 16#0038,
                t_states = State1#cpu_state.t_states + 13
            },
            {handled, State3};
        2 ->
            %% IM 2: vector table jump
            %% Bus byte provides low byte of address; high byte from I register.
            %% Read 16-bit pointer from (I*256 + BusByte), jump to it.
            BusByte = 16#FF,
            VectorAddr = (State2#cpu_state.i bsl 8) bor BusByte,
            {Lo, State3a} = z80_cpu_helpers:read_byte(State2, VectorAddr),
            {Hi, State3b} = z80_cpu_helpers:read_byte(State3a, VectorAddr + 1),
            Target = (Hi bsl 8) bor Lo,
            State3 = State3b#cpu_state{
                pc = Target,
                t_states = State1#cpu_state.t_states + 19
            },
            {handled, State3}
    end;

maybe_handle_interrupt(State = #cpu_state{pending_interrupt = nmi}) ->
    State1 = z80_cpu_helpers:push_word(State, State#cpu_state.pc),
    State2 = State1#cpu_state{
        pc = 16#0066,
        iff2 = State1#cpu_state.iff1,
        iff1 = 0,
        halted = false,
        prefix = none,
        displacement = 0,
        t_states = State1#cpu_state.t_states + 11,
        pending_interrupt = none
    },
    {handled, State2}.


execute_next_instruction(State) ->
    {Opcode, State1} = z80_cpu_helpers:fetch_opcode(State),
    State2 = execute_opcode_base(Opcode, State1),
    case Opcode of
         16#DD -> State2;
         16#FD -> State2;
        _     -> State2#cpu_state{prefix = none}
    end.
 

%% @doc Base opcode implementations (no prefix handling)
execute_opcode_base(Opcode, State) ->
    case Opcode of
        16#00 -> State;                             % NOP: total 4
        16#01 -> execute_ld_rr_nn(State, bc);       % LD BC,nn: total 10
        16#02 -> execute_ld_mem_rr_a(State, bc);    % LD (BC),A: total 7
        16#03 -> execute_inc_rr(State, bc);         % INC BC: total 6
        16#04 -> execute_inc_r(State, b);           % INC B: total 4
        16#05 -> execute_dec_r(State, b);           % DEC B: total 4
        16#06 -> execute_ld_r_n(State, b);          % LD B,n: total 7
        16#07 -> execute_rlca(State);               % RLCA: total 4
        16#08 -> execute_ex_af_af(State);           % EX AF,AF': total 4
        16#09 -> execute_add_hl_rr(State, bc);      % ADD HL,BC: total 11
        16#0A -> execute_ld_a_mem_rr(State, bc);    % LD A,(BC): total 7
        16#0B -> execute_dec_rr(State, bc);         % DEC BC: total 6
        16#0C -> execute_inc_r(State, c);           % INC C: total 4
        16#0D -> execute_dec_r(State, c);           % DEC C: total 4
        16#0E -> execute_ld_r_n(State, c);          % LD C,n: total 7
        16#0F -> execute_rrca(State);               % RRCA: total 4
        16#10 -> execute_djnz(State);               % DJNZ e
        16#11 -> execute_ld_rr_nn(State, de);       % LD DE,nn: total 10
        16#12 -> execute_ld_mem_rr_a(State, de);    % LD (DE),A: total 7
        16#13 -> execute_inc_rr(State, de);         % INC DE: total 6
        16#14 -> execute_inc_r(State, d);           % INC D: total 4
        16#15 -> execute_dec_r(State, d);           % DEC D: total 4
        16#16 -> execute_ld_r_n(State, d);          % LD D,n: total 7
        16#17 -> execute_rla(State);                % RLA: total 4
        16#18 -> execute_jr(State);                 % JR e: total 12
        16#19 -> execute_add_hl_rr(State, de);      % ADD HL,DE: total 11
        16#1A -> execute_ld_a_mem_rr(State, de);    % LD A,(DE): total 7
        16#1B -> execute_dec_rr(State, de);         % DEC DE: total 6
        16#1C -> execute_inc_r(State, e);           % INC E: total 4
        16#1D -> execute_dec_r(State, e);           % DEC E: total 4
        16#1E -> execute_ld_r_n(State, e);          % LD E,n: total 7
        16#1F -> execute_rra(State);                % RRA: total 4
        16#20 -> execute_jr_cc(State, nz);          % JR NZ,e
        16#21 -> execute_ld_rr_nn(State, hl);       % LD HL,nn: total 10
        16#22 -> execute_ld_mem_nn_hl(State);       % LD (nn),HL: total 16
        16#23 -> execute_inc_rr(State, hl);         % INC HL: total 6
        16#24 -> execute_inc_r(State, h);           % INC H: total 4
        16#25 -> execute_dec_r(State, h);           % DEC H: total 4
        16#26 -> execute_ld_r_n(State, h);          % LD H,n: total 7
        16#27 -> execute_daa(State);                % DAA: total 4
        16#28 -> execute_jr_cc(State, z);           % JR Z,e
        16#29 -> execute_add_hl_rr(State, hl);      % ADD HL,HL: total 11
        16#2A -> execute_ld_hl_mem_nn(State);       % LD HL,(nn): total 16
        16#2B -> execute_dec_rr(State, hl);         % DEC HL: total 6
        16#2C -> execute_inc_r(State, l);           % INC L: total 4
        16#2D -> execute_dec_r(State, l);           % DEC L: total 4
        16#2E -> execute_ld_r_n(State, l);          % LD L,n: total 7
        16#2F -> execute_cpl(State);                % CPL: total 4
        16#30 -> execute_jr_cc(State, nc);          % JR NC,e
        16#31 -> execute_ld_sp_nn(State);           % LD SP,nn: total 10
        16#32 -> execute_ld_mem_nn_a(State);        % LD (nn),A: total 13
        16#33 -> execute_inc_rr(State, sp);         % INC SP: total 6
        16#34 -> execute_inc_mem_hl(State);         % INC (HL): total 11
        16#35 -> execute_dec_mem_hl(State);         % DEC (HL): total 11
        16#36 -> execute_ld_mem_hl_n(State);        % LD (HL),n: total 10
        16#37 -> execute_scf(State);                % SCF: total 4
        16#38 -> execute_jr_cc(State, c);           % JR C,e
        16#39 -> execute_add_hl_rr(State, sp);      % ADD HL,SP: total 11
        16#3A -> execute_ld_a_mem_nn(State);        % LD A,(nn): total 13
        16#3B -> execute_dec_rr(State, sp);         % DEC SP: total 6
        16#3C -> execute_inc_r(State, a);           % INC A: total 4
        16#3D -> execute_dec_r(State, a);           % DEC A: total 4
        16#3E -> execute_ld_a_n(State);             % LD A,n: total 7
        16#3F -> execute_ccf(State);                % CCF: total 4
        16#40 -> execute_ld_r_r(State, b, b);       % LD B,B: total 4
        16#41 -> execute_ld_r_r(State, b, c);       % LD B,C: total 4
        16#42 -> execute_ld_r_r(State, b, d);       % LD B,D: total 4
        16#43 -> execute_ld_r_r(State, b, e);       % LD B,E: total 4
        16#44 -> execute_ld_r_r(State, b, h);       % LD B,H: total 4
        16#45 -> execute_ld_r_r(State, b, l);       % LD B,L: total 4
        16#46 -> execute_ld_r_mem_hl(State, b);     % LD B,(HL): total 7
        16#47 -> execute_ld_r_r(State, b, a);       % LD B,A: total 4
        16#48 -> execute_ld_r_r(State, c, b);       % LD C,B: total 4
        16#49 -> execute_ld_r_r(State, c, c);       % LD C,C: total 4
        16#4A -> execute_ld_r_r(State, c, d);       % LD C,D: total 4
        16#4B -> execute_ld_r_r(State, c, e);       % LD C,E: total 4
        16#4C -> execute_ld_r_r(State, c, h);       % LD C,H: total 4
        16#4D -> execute_ld_r_r(State, c, l);       % LD C,L: total 4
        16#4E -> execute_ld_r_mem_hl(State, c);     % LD C,(HL): total 7
        16#4F -> execute_ld_r_r(State, c, a);       % LD C,A: total 4
        16#50 -> execute_ld_r_r(State, d, b);       % LD D,B: total 4
        16#51 -> execute_ld_r_r(State, d, c);       % LD D,C: total 4
        16#52 -> execute_ld_r_r(State, d, d);       % LD D,D: total 4
        16#53 -> execute_ld_r_r(State, d, e);       % LD D,E: total 4
        16#54 -> execute_ld_r_r(State, d, h);       % LD D,H: total 4
        16#55 -> execute_ld_r_r(State, d, l);       % LD D,L: total 4
        16#56 -> execute_ld_r_mem_hl(State, d);     % LD D,(HL): total 7
        16#57 -> execute_ld_r_r(State, d, a);       % LD D,A: total 4
        16#58 -> execute_ld_r_r(State, e, b);       % LD E,B: total 4
        16#59 -> execute_ld_r_r(State, e, c);       % LD E,C: total 4
        16#5A -> execute_ld_r_r(State, e, d);       % LD E,D: total 4
        16#5B -> execute_ld_r_r(State, e, e);       % LD E,E: total 4
        16#5C -> execute_ld_r_r(State, e, h);       % LD E,H: total 4
        16#5D -> execute_ld_r_r(State, e, l);       % LD E,L: total 4
        16#5E -> execute_ld_r_mem_hl(State, e);     % LD E,(HL): total 7
        16#5F -> execute_ld_r_r(State, e, a);       % LD E,A: total 4
        16#60 -> execute_ld_r_r(State, h, b);       % LD H,B: total 4
        16#61 -> execute_ld_r_r(State, h, c);       % LD H,C: total 4
        16#62 -> execute_ld_r_r(State, h, d);       % LD H,D: total 4
        16#63 -> execute_ld_r_r(State, h, e);       % LD H,E: total 4
        16#64 -> execute_ld_r_r(State, h, h);       % LD H,H: total 4
        16#65 -> execute_ld_r_r(State, h, l);       % LD H,L: total 4
        16#66 -> execute_ld_r_mem_hl(State, h);     % LD H,(HL): total 7
        16#67 -> execute_ld_r_r(State, h, a);       % LD H,A: total 4
        16#68 -> execute_ld_r_r(State, l, b);       % LD L,B: total 4
        16#69 -> execute_ld_r_r(State, l, c);       % LD L,C: total 4
        16#6A -> execute_ld_r_r(State, l, d);       % LD L,D: total 4
        16#6B -> execute_ld_r_r(State, l, e);       % LD L,E: total 4
        16#6C -> execute_ld_r_r(State, l, h);       % LD L,H: total 4
        16#6D -> execute_ld_r_r(State, l, l);       % LD L,L: total 4
        16#6E -> execute_ld_r_mem_hl(State, l);     % LD L,(HL): total 7
        16#6F -> execute_ld_r_r(State, l, a);       % LD L,A: total 4
        16#70 -> execute_ld_mem_hl_r(State, b);     % LD (HL),B: total 7
        16#71 -> execute_ld_mem_hl_r(State, c);     % LD (HL),C: total 7
        16#72 -> execute_ld_mem_hl_r(State, d);     % LD (HL),D: total 7
        16#73 -> execute_ld_mem_hl_r(State, e);     % LD (HL),E: total 7
        16#74 -> execute_ld_mem_hl_r(State, h);     % LD (HL),H: total 7
        16#75 -> execute_ld_mem_hl_r(State, l);     % LD (HL),L: total 7
        16#76 -> execute_halt(State);               % HALT: total 4
        16#77 -> execute_ld_mem_hl_a(State);        % LD (HL),A: total 7
        16#78 -> execute_ld_r_r(State, a, b);       % LD A,B: total 4
        16#79 -> execute_ld_r_r(State, a, c);       % LD A,C: total 4
        16#7A -> execute_ld_r_r(State, a, d);       % LD A,D: total 4
        16#7B -> execute_ld_r_r(State, a, e);       % LD A,E: total 4
        16#7C -> execute_ld_r_r(State, a, h);       % LD A,H: total 4
        16#7D -> execute_ld_r_r(State, a, l);       % LD A,L: total 4
        16#7E -> execute_ld_a_mem_hl(State);        % LD A,(HL): total 7
        16#7F -> execute_ld_r_r(State, a, a);       % LD A,A: total 4
        16#80 -> execute_add_a_b(State);            % ADD A,B: total 4
        16#81 -> execute_add_a_c(State);            % ADD A,C
        16#82 -> execute_add_a_d(State);            % ADD A,D
        16#83 -> execute_add_a_e(State);            % ADD A,E
        16#84 -> execute_add_a_h(State);            % ADD A,H
        16#85 -> execute_add_a_l(State);            % ADD A,L
        16#86 -> execute_add_a_mem_hl(State);       % ADD A,(HL): total 7
        16#87 -> execute_add_a_a(State);            % ADD A,A
        16#88 -> execute_adc_a_b(State);            % ADC A,B: total 4
        16#89 -> execute_adc_a_c(State);            % ADC A,C
        16#8A -> execute_adc_a_d(State);            % ADC A,D
        16#8B -> execute_adc_a_e(State);            % ADC A,E
        16#8C -> execute_adc_a_h(State);            % ADC A,H
        16#8D -> execute_adc_a_l(State);            % ADC A,L
        16#8E -> execute_adc_a_mem_hl(State);       % ADC A,(HL): total 7
        16#8F -> execute_adc_a_a(State);            % ADC A,A
        16#90 -> execute_sub_b(State);              % SUB B: total 4
        16#91 -> execute_sub_c(State);              % SUB C
        16#92 -> execute_sub_d(State);              % SUB D
        16#93 -> execute_sub_e(State);              % SUB E
        16#94 -> execute_sub_h(State);              % SUB H
        16#95 -> execute_sub_l(State);              % SUB L
        16#96 -> execute_sub_mem_hl(State);         % SUB (HL): total 7
        16#97 -> execute_sub_a(State);              % SUB A
        16#98 -> execute_sbc_a_b(State);            % SBC A,B: total 4
        16#99 -> execute_sbc_a_c(State);            % SBC A,C
        16#9A -> execute_sbc_a_d(State);            % SBC A,D
        16#9B -> execute_sbc_a_e(State);            % SBC A,E
        16#9C -> execute_sbc_a_h(State);            % SBC A,H
        16#9D -> execute_sbc_a_l(State);            % SBC A,L
        16#9E -> execute_sbc_a_mem_hl(State);       % SBC A,(HL): total 7
        16#9F -> execute_sbc_a_a(State);            % SBC A,A
        16#A0 -> execute_and_b(State);              % AND B: total 4
        16#A1 -> execute_and_c(State);              % AND C
        16#A2 -> execute_and_d(State);              % AND D
        16#A3 -> execute_and_e(State);              % AND E
        16#A4 -> execute_and_h(State);              % AND H
        16#A5 -> execute_and_l(State);              % AND L
        16#A6 -> execute_and_mem_hl(State);         % AND (HL): total 7
        16#A7 -> execute_and_a(State);              % AND A
        16#A8 -> execute_xor_b(State);              % XOR B: total 4
        16#A9 -> execute_xor_c(State);              % XOR C
        16#AA -> execute_xor_d(State);              % XOR D
        16#AB -> execute_xor_e(State);              % XOR E
        16#AC -> execute_xor_h(State);              % XOR H
        16#AD -> execute_xor_l(State);              % XOR L
        16#AE -> execute_xor_mem_hl(State);         % XOR (HL): total 7
        16#AF -> execute_xor_a(State);              % XOR A
        16#B0 -> execute_or_b(State);               % OR B: total 4
        16#B1 -> execute_or_c(State);               % OR C
        16#B2 -> execute_or_d(State);               % OR D
        16#B3 -> execute_or_e(State);               % OR E
        16#B4 -> execute_or_h(State);               % OR H
        16#B5 -> execute_or_l(State);               % OR L
        16#B6 -> execute_or_mem_hl(State);          % OR (HL): total 7
        16#B7 -> execute_or_a(State);               % OR A
        16#B8 -> execute_cp_b(State);               % CP B: total 4
        16#B9 -> execute_cp_c(State);               % CP C
        16#BA -> execute_cp_d(State);               % CP D
        16#BB -> execute_cp_e(State);               % CP E
        16#BC -> execute_cp_h(State);               % CP H
        16#BD -> execute_cp_l(State);               % CP L
        16#BE -> execute_cp_mem_hl(State);          % CP (HL): total 7
        16#BF -> execute_cp_a(State);               % CP A
        16#C0 -> execute_ret_cc(State, nz);         % RET NZ
        16#C1 -> execute_pop(State, bc);            % POP BC: total 10
        16#C2 -> execute_jp_cc(State, nz);          % JP NZ,nn
        16#C3 -> execute_jp_nn(State);              % JP nn: total 10
        16#C4 -> execute_call_cc(State, nz);        % CALL NZ,nn
        16#C5 -> execute_push(State, bc);           % PUSH BC: total 11
        16#C6 -> execute_add_a_n(State);            % ADD A,n: total 7
        16#C7 -> execute_rst(State, 16#00);         % RST 00h: total 11
        16#C8 -> execute_ret_cc(State, z);          % RET Z
        16#C9 -> execute_ret(State);                % RET: total 10
        16#CA -> execute_jp_cc(State, z);           % JP Z,nn
        16#CC -> execute_call_cc(State, z);         % CALL Z,nn
        16#CD -> execute_call_nn(State);            % CALL nn: total 17
        16#CE -> execute_adc_a_n(State);            % ADC A,n: total 7
        16#CF -> execute_rst(State, 16#08);         % RST 08h: total 11
        16#D0 -> execute_ret_cc(State, nc);         % RET NC
        16#D1 -> execute_pop(State, de);            % POP DE: total 10
        16#D2 -> execute_jp_cc(State, nc);          % JP NC,nn
        16#D3 -> execute_out_n_a(State);            % OUT (n),A: total 11
        16#D4 -> execute_call_cc(State, nc);        % CALL NC,nn
        16#D5 -> execute_push(State, de);           % PUSH DE: total 11
        16#D6 -> execute_sub_n(State);              % SUB n: total 7
        16#D7 -> execute_rst(State, 16#10);         % RST 10h: total 11
        16#D8 -> execute_ret_cc(State, c);          % RET C
        16#D9 -> execute_exx(State);                % EXX: total 4
        16#DA -> execute_jp_cc(State, c);           % JP C,nn
        16#DB -> execute_in_a_n(State);             % IN A,(n): total 11
        16#DC -> execute_call_cc(State, c);         % CALL C,nn
        16#DE -> execute_sbc_a_n(State);            % SBC A,n: total 7
        16#DF -> execute_rst(State, 16#18);         % RST 18h: total 11
        16#E0 -> execute_ret_cc(State, po);         % RET PO
        16#E1 -> execute_pop(State, hl);            % POP HL: total 10
        16#E2 -> execute_jp_cc(State, po);          % JP PO,nn
        16#E3 -> execute_ex_sp_hl(State);           % EX (SP),HL/IX/IY: total 19
        16#E4 -> execute_call_cc(State, po);        % CALL PO,nn
        16#E5 -> execute_push(State, hl);           % PUSH HL: total 11
        16#E6 -> execute_and_n(State);              % AND n: total 7
        16#E7 -> execute_rst(State, 16#20);         % RST 20h: total 11
        16#E8 -> execute_ret_cc(State, pe);         % RET PE
        16#E9 -> execute_jp_hl(State);              % JP (HL): total 4
        16#EA -> execute_jp_cc(State, pe);          % JP PE,nn
        16#EB -> execute_ex_de_hl(State);           % EX DE,HL: total 4
        16#EC -> execute_call_cc(State, pe);        % CALL PE,nn
        16#EE -> execute_xor_n(State);              % XOR n: total 7
        16#EF -> execute_rst(State, 16#28);         % RST 28h: total 11
        16#F0 -> execute_ret_cc(State, p);          % RET P
        16#F1 -> execute_pop(State, af);            % POP AF: total 10
        16#F2 -> execute_jp_cc(State, p);           % JP P,nn
        16#F3 -> execute_di(State);                 % DI: total 4
        16#F4 -> execute_call_cc(State, p);         % CALL P,nn
        16#F5 -> execute_push(State, af);           % PUSH AF: total 11
        16#F6 -> execute_or_n(State);               % OR n: total 7
        16#F7 -> execute_rst(State, 16#30);         % RST 30h: total 11
        16#F8 -> execute_ret_cc(State, m);          % RET M
        16#F9 -> execute_ld_sp_hl(State);           % LD SP,HL: total 6
        16#FA -> execute_jp_cc(State, m);           % JP M,nn
        16#FB -> execute_ei(State);                 % EI: total 4
        16#FC -> execute_call_cc(State, m);         % CALL M,nn
        16#FE -> execute_cp_n(State);               % CP n: total 7
        16#FF -> execute_rst(State, 16#38);         % RST 38h: total 11

        %% Prefixes
        16#DD ->
            % DD prefix: set prefix, fetch next opcode, execute it with prefix active
            State1 = State#cpu_state{prefix = dd},
            execute_next_instruction(State1);

        16#FD ->
            % FD prefix: set prefix, fetch next opcode, execute it with prefix active
            State1 = State#cpu_state{prefix = fd},
            execute_next_instruction(State1);

        16#CB ->
            Prefix = State#cpu_state.prefix,
            case Prefix of
                dd ->
                    % DD prefix active: execute with prefix, then clear it
                    {Disp, State1} = z80_cpu_helpers:fetch_byte(State),
                    State2 = State1#cpu_state{prefix = dd_cb, displacement = z80_cpu_helpers:signed_byte(Disp)},
                    {Opcode2, State3} = z80_cpu_helpers:fetch_opcode(State2),
                    State4 = State3#cpu_state{prefix = none},
                    z80_cpu_cb:execute_cb_indexed_opcode(Opcode2, ix, State4);
                fd ->
                    % FD prefix active: execute with prefix, then clear it
                    {Disp, State1} = z80_cpu_helpers:fetch_byte(State),
                    State2 = State1#cpu_state{prefix = fd_cb, displacement = z80_cpu_helpers:signed_byte(Disp)},
                    {Opcode2, State3} = z80_cpu_helpers:fetch_opcode(State2),
                    State4 = State3#cpu_state{prefix = none},
                    z80_cpu_cb:execute_cb_indexed_opcode(Opcode2, iy, State4);
                _ ->
                    % CB prefix: 4 T-states already counted, fetch next opcode
                    {Opcode1, State1} = z80_cpu_helpers:fetch_opcode(State),
                    z80_cpu_cb:execute_cb_opcode(Opcode1, State1) 
            end;

        16#ED ->
            % ED prefix: 4 T-states already counted, fetch next opcode
            {Opcode1, State1} = z80_cpu_helpers:fetch_opcode(State),
            z80_cpu_ed:execute_ed_opcode(Opcode1, State1)
    end.


%% --- Base Instruction Implementations ---

execute_ld_rr_nn(State, Reg) ->
    {Word, State1} = z80_cpu_helpers:fetch_word(State),
    case Reg of
        bc ->
            State1#cpu_state{b = (Word bsr 8) band 16#ff, c = Word band 16#ff};
        de ->
            State1#cpu_state{d = (Word bsr 8) band 16#ff, e = Word band 16#ff};
        hl ->
            z80_cpu_helpers:set_hl_pair(Word, State1)
    end.

execute_inc_rr(State, Reg) ->
    case Reg of
        hl ->
            Val = z80_cpu_helpers:get_hl_pair(State),
            NewVal = (Val + 1) band 16#ffff,
            State1 = z80_cpu_helpers:set_hl_pair(NewVal, State),
            z80_cpu_helpers:advance_tstates(State1, 2);
        bc ->
            Val = z80_cpu_helpers:pair(State#cpu_state.b, State#cpu_state.c),
            NewVal = (Val + 1) band 16#ffff,
            State1 = State#cpu_state{b = (NewVal bsr 8) band 16#ff, c = NewVal band 16#ff},
            z80_cpu_helpers:advance_tstates(State1, 2);
        de ->
            Val = z80_cpu_helpers:pair(State#cpu_state.d, State#cpu_state.e),
            NewVal = (Val + 1) band 16#ffff,
            State1 = State#cpu_state{d = (NewVal bsr 8) band 16#ff, e = NewVal band 16#ff},
            z80_cpu_helpers:advance_tstates(State1, 2);
        sp ->
            Val = ?GET_SP(State),
            NewVal = (Val + 1) band 16#FFFF,
            State1 = ?SET_SP(State, NewVal),
            z80_cpu_helpers:advance_tstates(State1, 2)
    end.

execute_dec_rr(State, Reg) ->
    case Reg of
        hl ->
            Val = z80_cpu_helpers:get_hl_pair(State),
            NewVal = (Val - 1) band 16#FFFF,
            State1 = z80_cpu_helpers:set_hl_pair(NewVal, State),
            z80_cpu_helpers:advance_tstates(State1, 2);
        bc ->
            Val = z80_cpu_helpers:pair(State#cpu_state.b, State#cpu_state.c),
            NewVal = (Val - 1) band 16#FFFF,
            State1 = State#cpu_state{b = (NewVal bsr 8) band 16#ff, c = NewVal band 16#ff},
            z80_cpu_helpers:advance_tstates(State1, 2);
        de ->
            Val = z80_cpu_helpers:pair(State#cpu_state.d, State#cpu_state.e),
            NewVal = (Val - 1) band 16#FFFF,
            State1 = State#cpu_state{d = (NewVal bsr 8) band 16#ff, e = NewVal band 16#ff},
            z80_cpu_helpers:advance_tstates(State1, 2);
        sp ->
            Val = ?GET_SP(State),
            NewVal = (Val - 1) band 16#FFFF,
            State1 = ?SET_SP(State, NewVal),
            z80_cpu_helpers:advance_tstates(State1, 2)
    end.

%% INC/DEC r and LD r,n helpers (used by main dispatch table)
%% These use prefix-aware register access for H/L registers when prefix is DD/FD

get_reg_byte_prefixed(Reg, State) ->
    case Reg of
        h -> z80_cpu_helpers:get_hl_reg(h, State);
        l -> z80_cpu_helpers:get_hl_reg(l, State);
        _ -> z80_cpu_helpers:get_reg_byte(Reg, State)
    end.

set_reg_byte_prefixed(Reg, Value, State) ->
    case Reg of
        h -> z80_cpu_helpers:set_hl_reg(h, Value, State);
        l -> z80_cpu_helpers:set_hl_reg(l, Value, State);
        _ -> z80_cpu_helpers:set_reg_byte(Reg, Value, State)
    end.

%% INC/DEC r and LD r,n helpers (used by main dispatch table)
execute_inc_r(State, Reg) ->
    OldVal = get_reg_byte_prefixed(Reg, State),
    NewVal = (OldVal + 1) band 16#ff,

    Flags = State#cpu_state.f,
    F_N = 0,
    F_Z = if NewVal =:= 0 -> ?FLAG_Z; true -> 0 end,
    F_S = NewVal band 16#80,
    F_H = if (OldVal band 16#0F) =:= 16#0F -> ?FLAG_H; true -> 0 end,
    F_V = if OldVal =:= 16#7F -> ?FLAG_V; true -> 0 end,

    NewFlags = (Flags band ?FLAG_C) bor F_N bor F_Z bor F_S bor F_H bor F_V,

    set_reg_byte_prefixed(Reg, NewVal, State#cpu_state{f = NewFlags}).
    

execute_dec_r(State, Reg) ->
    OldVal = get_reg_byte_prefixed(Reg, State),
    NewVal = (OldVal - 1) band 16#ff,

    Flags = State#cpu_state.f,
    F_N = ?FLAG_N,
    F_Z = if NewVal =:= 0 -> ?FLAG_Z; true -> 0 end,
    F_S = NewVal band 16#80,
    F_H = if (OldVal band 16#0F) =:= 0 -> ?FLAG_H; true -> 0 end,
    F_V = if OldVal =:= 16#80 -> ?FLAG_V; true -> 0 end,

    NewFlags = (Flags band ?FLAG_C) bor F_N bor F_Z bor F_S bor F_H bor F_V,

    set_reg_byte_prefixed(Reg, NewVal, State#cpu_state{f = NewFlags}).

execute_ld_r_n(State, Reg) ->
    {Value, State1} = z80_cpu_helpers:fetch_byte(State),
    set_reg_byte_prefixed(Reg, Value, State1).

execute_ld_a_mem_rr(State, Reg) ->
    Addr = case Reg of
        bc -> z80_cpu_helpers:pair(State#cpu_state.b, State#cpu_state.c);
        de -> z80_cpu_helpers:pair(State#cpu_state.d, State#cpu_state.e)
    end,
    {Byte, State1} = z80_cpu_helpers:read_byte(State, Addr),
    z80_cpu_helpers:advance_tstates(State1#cpu_state{a = Byte}, 3).

execute_ld_mem_rr_a(State, Reg) ->
    Addr = case Reg of
        bc -> z80_cpu_helpers:pair(State#cpu_state.b, State#cpu_state.c);
        de -> z80_cpu_helpers:pair(State#cpu_state.d, State#cpu_state.e)
    end,
    State1 = z80_cpu_helpers:write_byte(State, Addr, State#cpu_state.a),
    z80_cpu_helpers:advance_tstates(State1, 3).

execute_ld_mem_nn_hl(State) ->
    {Addr, State1} = z80_cpu_helpers:fetch_word(State),
    State2 = z80_cpu_helpers:write_word(State1, Addr, z80_cpu_helpers:get_hl_pair(State1)),
    z80_cpu_helpers:advance_tstates(State2, 6).

execute_ld_sp_nn(State) ->
    {Word, State1} = z80_cpu_helpers:fetch_word(State),
    State1#cpu_state{sp = Word}.

execute_ld_mem_nn_a(State) ->
    {Addr, State1} = z80_cpu_helpers:fetch_word(State),
    State2 = z80_cpu_helpers:write_byte(State1, Addr, State1#cpu_state.a),
    z80_cpu_helpers:advance_tstates(State2, 3).

execute_ld_a_mem_nn(State) ->
    {Addr, State1} = z80_cpu_helpers:fetch_word(State),
    {Byte, State2} = z80_cpu_helpers:read_byte(State1, Addr),
    z80_cpu_helpers:advance_tstates(State2#cpu_state{a = Byte}, 3).

execute_ld_a_n(State) ->
    {Value, State1} = z80_cpu_helpers:fetch_byte(State),
    State1#cpu_state{a = Value}.

execute_ld_r_r(State, RegDst, RegSrc) ->
    Value = get_reg_byte_prefixed(RegSrc, State),
    set_reg_byte_prefixed(RegDst, Value, State).

execute_ld_r_mem_hl(State, Reg) ->
    {Byte, State1} = z80_cpu_helpers:read_hl_mem(State),
    State2 = set_reg_byte_prefixed(Reg, Byte, State1),
    z80_cpu_helpers:advance_tstates(State2, 3).

execute_ld_mem_hl_r(State, Reg) ->
    Byte = get_reg_byte_prefixed(Reg, State),
    State1 = z80_cpu_helpers:write_hl_mem(State, Byte),
    z80_cpu_helpers:advance_tstates(State1, 3).

execute_ld_mem_hl_a(State) ->
    State1 = z80_cpu_helpers:write_hl_mem(State, State#cpu_state.a),
    z80_cpu_helpers:advance_tstates(State1, 3).

execute_ld_a_mem_hl(State) ->
    {Byte, State1} = z80_cpu_helpers:read_hl_mem(State),
    z80_cpu_helpers:advance_tstates(State1#cpu_state{a = Byte}, 3).

execute_halt(State) ->
    State#cpu_state{halted = true}.

execute_rst(State, Vector) ->
    State1 = z80_cpu_helpers:push_word(State, State#cpu_state.pc),
    State2 = State1#cpu_state{pc = Vector},
    z80_cpu_helpers:advance_tstates(State2, 7).

%% Immediate value instructions (fetch byte then operate)
execute_add_a_n(State) ->
    {Val, State1} = z80_cpu_helpers:fetch_byte(State),
    z80_cpu_helpers:do_add(State1, Val).

execute_adc_a_n(State) ->
    {Val, State1} = z80_cpu_helpers:fetch_byte(State),
    z80_cpu_helpers:do_adc(State1, Val).

execute_sub_n(State) ->
    {Val, State1} = z80_cpu_helpers:fetch_byte(State),
    z80_cpu_helpers:do_sub(State1, Val).

execute_sbc_a_n(State) ->
    {Val, State1} = z80_cpu_helpers:fetch_byte(State),
    z80_cpu_helpers:do_sbc(State1, Val).

execute_and_n(State) ->
    {Val, State1} = z80_cpu_helpers:fetch_byte(State),
    z80_cpu_helpers:do_and(State1, Val).

execute_xor_n(State) ->
    {Val, State1} = z80_cpu_helpers:fetch_byte(State),
    z80_cpu_helpers:do_xor(State1, Val).

execute_or_n(State) ->
    {Val, State1} = z80_cpu_helpers:fetch_byte(State),
    z80_cpu_helpers:do_or(State1, Val).

execute_cp_n(State) ->
    {Val, State1} = z80_cpu_helpers:fetch_byte(State),
    z80_cpu_helpers:do_cp(State1, Val).

execute_exx(State) ->
    State1 = State#cpu_state{
        b = State#cpu_state.b_alt,
        c = State#cpu_state.c_alt,
        d = State#cpu_state.d_alt,
        e = State#cpu_state.e_alt,
        h = State#cpu_state.h_alt,
        l = State#cpu_state.l_alt,
        b_alt = State#cpu_state.b,
        c_alt = State#cpu_state.c,
        d_alt = State#cpu_state.d,
        e_alt = State#cpu_state.e,
        h_alt = State#cpu_state.h,
        l_alt = State#cpu_state.l
    },
    z80_cpu_helpers:advance_tstates(State1, 0).

execute_di(State) ->
    State#cpu_state{iff1 = 0, iff2 = 0}.

execute_ei(State) ->
    State#cpu_state{iff1 = 1, iff2 = 1, ei_block = 1}.

execute_jr(State) ->
    {Offset, State1} = z80_cpu_helpers:fetch_byte(State),
    Signed = z80_cpu_helpers:signed_byte(Offset),
    PC = State1#cpu_state.pc,
    State2 = State1#cpu_state{pc = (PC + Signed) band 16#ffff},
    z80_cpu_helpers:advance_tstates(State2, 5).

execute_djnz(State) ->
    {Offset, State1} = z80_cpu_helpers:fetch_byte(State),
    NewB = (State1#cpu_state.b - 1) band 16#ff,
    State2 = State1#cpu_state{b = NewB},
    if
        NewB =:= 0 ->
            z80_cpu_helpers:advance_tstates(State2, 1);
        true ->
            PC = State2#cpu_state.pc,
            State3 = State2#cpu_state{pc = (PC + z80_cpu_helpers:signed_byte(Offset)) band 16#ffff},
            z80_cpu_helpers:advance_tstates(State3, 6)
    end.

execute_jp_nn(State) ->
    {Addr, State1} = z80_cpu_helpers:fetch_word(State),
    State1#cpu_state{pc = Addr}.

execute_jp_hl(State) ->
    HL = z80_cpu_helpers:get_hl_pair(State),
    State#cpu_state{pc = HL}.

execute_ld_hl_mem_nn(State) ->
    {Addr, State1} = z80_cpu_helpers:fetch_word(State),
    {HL, State2} = z80_cpu_helpers:read_word(State1, Addr),
    State3 = z80_cpu_helpers:set_hl_pair(HL, State2),
    z80_cpu_helpers:advance_tstates(State3, 6).

execute_call_nn(State) ->
    {Addr, State1} = z80_cpu_helpers:fetch_word(State),
    State2 = z80_cpu_helpers:push_word(State1, State1#cpu_state.pc),
    State3 = State2#cpu_state{pc = Addr},
    z80_cpu_helpers:advance_tstates(State3, 7).

execute_ret(State) ->
    {Value, State1} = z80_cpu_helpers:pop_word(State),
    State2 = State1#cpu_state{pc = Value},
    z80_cpu_helpers:advance_tstates(State2, 6).

execute_push(State, RegPair) ->
    Val = case RegPair of
        hl -> z80_cpu_helpers:get_hl_pair(State);
        _ -> z80_cpu_helpers:get_reg_pair(RegPair, State)
    end,
    State2 = z80_cpu_helpers:push_word(State, Val),
    z80_cpu_helpers:advance_tstates(State2, 7).

execute_pop(State, RegPair) ->
    {Val, State1} = z80_cpu_helpers:pop_word(State),
    State2 = case RegPair of
        hl -> z80_cpu_helpers:set_hl_pair(Val, State1);
        _ -> z80_cpu_helpers:set_reg_pair(RegPair, Val, State1)
    end,
    z80_cpu_helpers:advance_tstates(State2, 6).

execute_ld_sp_hl(State) ->
    HL = z80_cpu_helpers:get_hl_pair(State),
    State1 = State#cpu_state{sp = HL},
    z80_cpu_helpers:advance_tstates(State1, 2).

execute_cpl(State) ->
    NewA = State#cpu_state.a bxor 16#FF,
    NewF = (State#cpu_state.f band (?FLAG_C bor ?FLAG_V bor ?FLAG_Z bor ?FLAG_S)) bor ?FLAG_H bor ?FLAG_N,
    State#cpu_state{a = NewA, f = NewF}.

execute_ccf(State) ->
    Carry = State#cpu_state.f band ?FLAG_C,
    NewCarry = Carry bxor ?FLAG_C,
    NewF = (State#cpu_state.f band 16#F0) bor NewCarry bor ?FLAG_H,
    State#cpu_state{f = NewF}.

execute_inc_mem_hl(State) ->
    {Byte, State1} = z80_cpu_helpers:read_hl_mem(State),
    NewByte = (Byte + 1) band 16#ff,
    State2 = z80_cpu_helpers:write_hl_mem(State1, NewByte),
    Flags = State2#cpu_state.f,
    F_N = 0,
    F_Z = if NewByte =:= 0 -> ?FLAG_Z; true -> 0 end,
    F_S = NewByte band 16#80,
    F_H = if (Byte band 16#0F) =:= 16#0F -> ?FLAG_H; true -> 0 end,
    F_V = if Byte =:= 16#7F -> ?FLAG_V; true -> 0 end,
    NewF = (Flags band ?FLAG_C) bor F_N bor F_Z bor F_S bor F_H bor F_V,
    State3 = State2#cpu_state{f = NewF},
    z80_cpu_helpers:advance_tstates(State3, 11).

execute_dec_mem_hl(State) ->
    {Byte, State1} = z80_cpu_helpers:read_hl_mem(State),
    NewByte = (Byte - 1) band 16#ff,
    State2 = z80_cpu_helpers:write_hl_mem(State1, NewByte),
    Flags = State2#cpu_state.f,
    F_N = ?FLAG_N,
    F_Z = if NewByte =:= 0 -> ?FLAG_Z; true -> 0 end,
    F_S = NewByte band 16#80,
    F_H = if (Byte band 16#0F) =:= 0 -> ?FLAG_H; true -> 0 end,
    F_V = if Byte =:= 16#80 -> ?FLAG_V; true -> 0 end,
    NewFlags = (Flags band ?FLAG_C) bor F_N bor F_Z bor F_S bor F_H bor F_V,
    State3 = State2#cpu_state{f = NewFlags},
    z80_cpu_helpers:advance_tstates(State3, 11).

execute_ld_mem_hl_n(State) ->
    {Value, State1} = z80_cpu_helpers:fetch_byte(State),
    State2 = z80_cpu_helpers:write_hl_mem(State1, Value),
    z80_cpu_helpers:advance_tstates(State2, 10).

execute_rla(State) ->
    A = State#cpu_state.a,
    F = State#cpu_state.f,
    OldCarry = F band ?FLAG_C,
    NewCarry = (A band 16#80) bsr 7,
    NewA = ((A bsl 1) band 16#ff) bor OldCarry,
    NewF = (F band 16#28) bor NewCarry,
    State#cpu_state{a = NewA, f = NewF}.

execute_scf(State) ->
    NewF = (State#cpu_state.f band 16#F0) bor ?FLAG_C,
    State#cpu_state{f = NewF}.

execute_ex_af_af(State) ->
    State#cpu_state{
        a = State#cpu_state.a_alt,
        f = State#cpu_state.f_alt,
        a_alt = State#cpu_state.a,
        f_alt = State#cpu_state.f
    }.

execute_add_hl_rr(State, RegPair) ->
    HL = z80_cpu_helpers:get_hl_pair(State),
    RR = z80_cpu_helpers:get_reg_pair_prefixed(RegPair, State),
    Sum = HL + RR,
    Res = Sum band 16#FFFF,
    Carry = if Sum > 16#FFFF -> ?FLAG_C; true -> 0 end,
    HalfCarry = if ((HL band 16#0FFF) + (RR band 16#0FFF)) > 16#0FFF -> ?FLAG_H; true -> 0 end,
    State1 = State#cpu_state{f = (State#cpu_state.f band 16#38) bor Carry bor HalfCarry},
    State2 = z80_cpu_helpers:set_hl_pair(Res, State1),
    z80_cpu_helpers:advance_tstates(State2, 7).

execute_rrca(State) ->
    A = State#cpu_state.a,
    F = State#cpu_state.f,
    NewA = ((A band 1) bsl 7) bor (A bsr 1),
    NewF = (F band 16#28) bor (A band 1),
    State#cpu_state{a = NewA, f = NewF}.

execute_rra(State) ->
    A = State#cpu_state.a,
    F = State#cpu_state.f,
    Carry = F band ?FLAG_C,
    NewA = (Carry bsl 7) bor (A bsr 1),
    NewF = (F band 16#28) bor (A band 1),
    State#cpu_state{a = NewA, f = NewF}.

execute_daa(State) ->
    A = State#cpu_state.a,
    F = State#cpu_state.f,
    N = F band ?FLAG_N,
    H = F band ?FLAG_H,
    C = F band ?FLAG_C,
    {NewA, NewF} = case N of
        0 ->  % Addition
            CarryHigh = (C =/= 0) orelse (A > 16#99),
            CarryLow = (H =/= 0) orelse ((A band 16#0F) > 16#09),
            AdjHigh = if CarryHigh -> 16#60; true -> 0 end,
            AdjLow = if CarryLow -> 16#06; true -> 0 end,
            Sum = (A + AdjHigh + AdjLow) band 16#FF,
            NewC = if CarryHigh -> ?FLAG_C; true -> 0 end,
            NewH = if ((A band 16#0F) + AdjLow) > 16#0F -> ?FLAG_H; true -> 0 end,
            NewF1 = (F band 16#28) bor NewC bor NewH,
            {Sum, NewF1};
        _ ->  % Subtraction (N=1)
            BorrowHigh = (C =/= 0) orelse (A > 16#99),
            BorrowLow = (H =/= 0) orelse ((A band 16#0F) > 16#09),
            AdjHigh = if BorrowHigh -> 16#60; true -> 0 end,
            AdjLow = if BorrowLow -> 16#06; true -> 0 end,
            Diff = (A - AdjHigh - AdjLow) band 16#FF,
            NewC = if BorrowHigh -> ?FLAG_C; true -> 0 end,
            NewH = 0,
            NewF1 = (F band 16#28) bor NewC bor NewH,
            {Diff, NewF1}
    end,
    Parity = z80_cpu_helpers:parity(NewA),
    NewF2 = (NewF band 16#D7) bor
            (if NewA =:= 0 -> ?FLAG_Z; true -> 0 end) bor
            (if NewA band 16#80 =/= 0 -> ?FLAG_S; true -> 0 end) bor
            (if Parity =/= 0 -> ?FLAG_V; true -> 0 end),
    State#cpu_state{a = NewA, f = NewF2}.

execute_ex_de_hl(State) ->
    HL = z80_cpu_helpers:get_hl_pair(State),
    DE = z80_cpu_helpers:get_reg_pair(de, State),
    State1 = State#cpu_state{d = (HL bsr 8) band 16#ff, e = HL band 16#ff},
    z80_cpu_helpers:set_hl_pair(DE, State1).

execute_ex_sp_hl(State) ->
    SP = State#cpu_state.sp,
    HL = z80_cpu_helpers:get_hl_pair(State),
    {Val, State2} = z80_cpu_helpers:read_word(State, SP),
    State3 = z80_cpu_helpers:write_word(State2, SP, HL),
    State4 = z80_cpu_helpers:set_hl_pair(Val, State3),
    z80_cpu_helpers:advance_tstates(State4, 15).

execute_rlca(State) ->
    A = State#cpu_state.a,
    F = State#cpu_state.f,
    Carry = A bsr 7,
    NewA = ((A bsl 1) band 16#FF) bor Carry,
    NewF = (F band 16#28) bor Carry,
    State#cpu_state{a = NewA, f = NewF}.

%% ADD A, r / (HL) group (0x80-0x87)
execute_add_a_b(State) ->
    z80_cpu_helpers:do_add(State, z80_cpu_helpers:get_reg_byte(b, State)).

execute_add_a_c(State) ->
    z80_cpu_helpers:do_add(State, z80_cpu_helpers:get_reg_byte(c, State)).

execute_add_a_d(State) ->
    z80_cpu_helpers:do_add(State, z80_cpu_helpers:get_reg_byte(d, State)).

execute_add_a_e(State) ->
    z80_cpu_helpers:do_add(State, z80_cpu_helpers:get_reg_byte(e, State)).

execute_add_a_h(State) ->
    z80_cpu_helpers:do_add(State, z80_cpu_helpers:get_reg_byte(h, State)).

execute_add_a_l(State) ->
    z80_cpu_helpers:do_add(State, z80_cpu_helpers:get_reg_byte(l, State)).

execute_add_a_mem_hl(State) ->
    {Val, State1} = z80_cpu_helpers:read_byte(State, z80_cpu_helpers:pair(State#cpu_state.h, State#cpu_state.l)),
    z80_cpu_helpers:do_add(State1, Val).

execute_add_a_a(State) ->
    z80_cpu_helpers:do_add(State, z80_cpu_helpers:get_reg_byte(a, State)).

%% ADC A, r / (HL) group (0x88-0x8F)
execute_adc_a_b(State) ->
    z80_cpu_helpers:do_adc(State, z80_cpu_helpers:get_reg_byte(b, State)).

execute_adc_a_c(State) ->
    z80_cpu_helpers:do_adc(State, z80_cpu_helpers:get_reg_byte(c, State)).

execute_adc_a_d(State) ->
    z80_cpu_helpers:do_adc(State, z80_cpu_helpers:get_reg_byte(d, State)).

execute_adc_a_e(State) ->
    z80_cpu_helpers:do_adc(State, z80_cpu_helpers:get_reg_byte(e, State)).

execute_adc_a_h(State) ->
    z80_cpu_helpers:do_adc(State, z80_cpu_helpers:get_reg_byte(h, State)).

execute_adc_a_l(State) ->
    z80_cpu_helpers:do_adc(State, z80_cpu_helpers:get_reg_byte(l, State)).

execute_adc_a_mem_hl(State) ->
    {Val, State1} = z80_cpu_helpers:read_byte(State, z80_cpu_helpers:pair(State#cpu_state.h, State#cpu_state.l)),
    z80_cpu_helpers:do_adc(State1, Val).

execute_adc_a_a(State) ->
    z80_cpu_helpers:do_adc(State, z80_cpu_helpers:get_reg_byte(a, State)).

%% SUB r / (HL) group (0x90-0x97)
execute_sub_b(State) ->
    z80_cpu_helpers:do_sub(State, z80_cpu_helpers:get_reg_byte(b, State)).

execute_sub_c(State) ->
    z80_cpu_helpers:do_sub(State, z80_cpu_helpers:get_reg_byte(c, State)).

execute_sub_d(State) ->
    z80_cpu_helpers:do_sub(State, z80_cpu_helpers:get_reg_byte(d, State)).

execute_sub_e(State) ->
    z80_cpu_helpers:do_sub(State, z80_cpu_helpers:get_reg_byte(e, State)).

execute_sub_h(State) ->
    z80_cpu_helpers:do_sub(State, z80_cpu_helpers:get_reg_byte(h, State)).

execute_sub_l(State) ->
    z80_cpu_helpers:do_sub(State, z80_cpu_helpers:get_reg_byte(l, State)).

execute_sub_mem_hl(State) ->
    {Val, State1} = z80_cpu_helpers:read_byte(State, z80_cpu_helpers:pair(State#cpu_state.h, State#cpu_state.l)),
    z80_cpu_helpers:do_sub(State1, Val).

execute_sub_a(State) ->
    z80_cpu_helpers:do_sub(State, z80_cpu_helpers:get_reg_byte(a, State)).

%% SBC A, r / (HL) group (0x98-0x9F)
execute_sbc_a_b(State) ->
    z80_cpu_helpers:do_sbc(State, z80_cpu_helpers:get_reg_byte(b, State)).

execute_sbc_a_c(State) ->
    z80_cpu_helpers:do_sbc(State, z80_cpu_helpers:get_reg_byte(c, State)).

execute_sbc_a_d(State) ->
    z80_cpu_helpers:do_sbc(State, z80_cpu_helpers:get_reg_byte(d, State)).

execute_sbc_a_e(State) ->
    z80_cpu_helpers:do_sbc(State, z80_cpu_helpers:get_reg_byte(e, State)).

execute_sbc_a_h(State) ->
    z80_cpu_helpers:do_sbc(State, z80_cpu_helpers:get_reg_byte(h, State)).

execute_sbc_a_l(State) ->
    z80_cpu_helpers:do_sbc(State, z80_cpu_helpers:get_reg_byte(l, State)).

execute_sbc_a_mem_hl(State) ->
    {Val, State1} = z80_cpu_helpers:read_byte(State, z80_cpu_helpers:pair(State#cpu_state.h, State#cpu_state.l)),
    z80_cpu_helpers:do_sbc(State1, Val).

execute_sbc_a_a(State) ->
    z80_cpu_helpers:do_sbc(State, z80_cpu_helpers:get_reg_byte(a, State)).

%% AND r / (HL) group (0xA0-0xA7)
execute_and_b(State) ->
    z80_cpu_helpers:do_and(State, z80_cpu_helpers:get_reg_byte(b, State)).

execute_and_c(State) ->
    z80_cpu_helpers:do_and(State, z80_cpu_helpers:get_reg_byte(c, State)).

execute_and_d(State) ->
    z80_cpu_helpers:do_and(State, z80_cpu_helpers:get_reg_byte(d, State)).

execute_and_e(State) ->
    z80_cpu_helpers:do_and(State, z80_cpu_helpers:get_reg_byte(e, State)).

execute_and_h(State) ->
    z80_cpu_helpers:do_and(State, z80_cpu_helpers:get_reg_byte(h, State)).

execute_and_l(State) ->
    z80_cpu_helpers:do_and(State, z80_cpu_helpers:get_reg_byte(l, State)).

execute_and_mem_hl(State) ->
    {Val, State1} = z80_cpu_helpers:read_byte(State, z80_cpu_helpers:pair(State#cpu_state.h, State#cpu_state.l)),
    z80_cpu_helpers:do_and(State1, Val).

execute_and_a(State) ->
    z80_cpu_helpers:do_and(State, z80_cpu_helpers:get_reg_byte(a, State)).

%% XOR r / (HL) group (0xA8-0xAF)
execute_xor_b(State) ->
    z80_cpu_helpers:do_xor(State, z80_cpu_helpers:get_reg_byte(b, State)).

execute_xor_c(State) ->
    z80_cpu_helpers:do_xor(State, z80_cpu_helpers:get_reg_byte(c, State)).

execute_xor_d(State) ->
    z80_cpu_helpers:do_xor(State, z80_cpu_helpers:get_reg_byte(d, State)).

execute_xor_e(State) ->
    z80_cpu_helpers:do_xor(State, z80_cpu_helpers:get_reg_byte(e, State)).

execute_xor_h(State) ->
    z80_cpu_helpers:do_xor(State, z80_cpu_helpers:get_reg_byte(h, State)).

execute_xor_l(State) ->
    z80_cpu_helpers:do_xor(State, z80_cpu_helpers:get_reg_byte(l, State)).

execute_xor_mem_hl(State) ->
    {Val, State1} = z80_cpu_helpers:read_byte(State, z80_cpu_helpers:pair(State#cpu_state.h, State#cpu_state.l)),
    z80_cpu_helpers:do_xor(State1, Val).

execute_xor_a(State) ->
    z80_cpu_helpers:do_xor(State, z80_cpu_helpers:get_reg_byte(a, State)).

%% OR r / (HL) group (0xB0-0xB7)
execute_or_b(State) ->
    z80_cpu_helpers:do_or(State, z80_cpu_helpers:get_reg_byte(b, State)).

execute_or_c(State) ->
    z80_cpu_helpers:do_or(State, z80_cpu_helpers:get_reg_byte(c, State)).

execute_or_d(State) ->
    z80_cpu_helpers:do_or(State, z80_cpu_helpers:get_reg_byte(d, State)).

execute_or_e(State) ->
    z80_cpu_helpers:do_or(State, z80_cpu_helpers:get_reg_byte(e, State)).

execute_or_h(State) ->
    z80_cpu_helpers:do_or(State, z80_cpu_helpers:get_reg_byte(h, State)).

execute_or_l(State) ->
    z80_cpu_helpers:do_or(State, z80_cpu_helpers:get_reg_byte(l, State)).

execute_or_mem_hl(State) ->
    {Val, State1} = z80_cpu_helpers:read_byte(State, z80_cpu_helpers:pair(State#cpu_state.h, State#cpu_state.l)),
    z80_cpu_helpers:do_or(State1, Val).

execute_or_a(State) ->
    z80_cpu_helpers:do_or(State, z80_cpu_helpers:get_reg_byte(a, State)).

%% CP r / (HL) group (0xB8-0xBF)
execute_cp_b(State) ->
    z80_cpu_helpers:do_cp(State, z80_cpu_helpers:get_reg_byte(b, State)).

execute_cp_c(State) ->
    z80_cpu_helpers:do_cp(State, z80_cpu_helpers:get_reg_byte(c, State)).

execute_cp_d(State) ->
    z80_cpu_helpers:do_cp(State, z80_cpu_helpers:get_reg_byte(d, State)).

execute_cp_e(State) ->
    z80_cpu_helpers:do_cp(State, z80_cpu_helpers:get_reg_byte(e, State)).

execute_cp_h(State) ->
    z80_cpu_helpers:do_cp(State, z80_cpu_helpers:get_reg_byte(h, State)).

execute_cp_l(State) ->
    z80_cpu_helpers:do_cp(State, z80_cpu_helpers:get_reg_byte(l, State)).

execute_cp_mem_hl(State) ->
    {Val, State1} = z80_cpu_helpers:read_byte(State, z80_cpu_helpers:pair(State#cpu_state.h, State#cpu_state.l)),
    z80_cpu_helpers:do_cp(State1, Val).

execute_cp_a(State) ->
    z80_cpu_helpers:do_cp(State, z80_cpu_helpers:get_reg_byte(a, State)).

execute_out_n_a(State) ->
    {Port, State1} = z80_cpu_helpers:fetch_byte(State),
    PortWriteFun = State1#cpu_state.port_write_fun,
    ExtCtx = State1#cpu_state.ext_context,
    NewExtCtx = PortWriteFun(ExtCtx, Port, State1#cpu_state.a),
    State2 = State1#cpu_state{ext_context = NewExtCtx},
    z80_cpu_helpers:advance_tstates(State2, 4).

execute_in_a_n(State) ->
    {Port, State1} = z80_cpu_helpers:fetch_byte(State),
    PortReadFun = State1#cpu_state.port_read_fun,
    ExtCtx = State1#cpu_state.ext_context,
    {Val, NewExtCtx} = PortReadFun(ExtCtx, Port),
    State2 = State1#cpu_state{a = Val, ext_context = NewExtCtx},
    z80_cpu_helpers:advance_tstates(State2, 4).

%% --- Core Jump, Call, Return Group Helpers with Timing Control ---

execute_jp_cc(State, Cond) ->
    {Addr, State1} = z80_cpu_helpers:fetch_word(State),
    case z80_cpu_helpers:check_condition(Cond, State1#cpu_state.f) of
        true -> State1#cpu_state{pc = Addr};
        false -> State1
    end.

execute_jr_cc(State, Cond) ->
    {Offset, State1} = z80_cpu_helpers:fetch_byte(State),
    case z80_cpu_helpers:check_condition(Cond, State1#cpu_state.f) of
        true ->
            Signed = z80_cpu_helpers:signed_byte(Offset),
            NewPc = (State1#cpu_state.pc + Signed) band 16#ffff,
            z80_cpu_helpers:advance_tstates(State1#cpu_state{pc = NewPc}, 5);
        false ->
            State1
    end.

execute_call_cc(State, Cond) ->
    {Addr, State1} = z80_cpu_helpers:fetch_word(State),
    case z80_cpu_helpers:check_condition(Cond, State1#cpu_state.f) of
        true ->
            State2 = z80_cpu_helpers:push_word(State1, State1#cpu_state.pc),
            z80_cpu_helpers:advance_tstates(State2#cpu_state{pc = Addr}, 7);
        false ->
            State1
    end.

execute_ret_cc(State, Cond) ->
    case z80_cpu_helpers:check_condition(Cond, State#cpu_state.f) of
        true ->
            {Value, State1} = z80_cpu_helpers:pop_word(State),
            z80_cpu_helpers:advance_tstates(State1#cpu_state{pc = Value}, 7);
        false ->
            z80_cpu_helpers:advance_tstates(State, 1)
    end.

%% Register access wrappers (delegate to helpers) - accept CPU record directly
get_reg_byte(Reg, State) ->
    z80_cpu_helpers:get_reg_byte(Reg, State).

set_reg_byte(Reg, Value, State) ->
    z80_cpu_helpers:set_reg_byte(Reg, Value, State).

get_reg_pair(RegPair, State) ->
    z80_cpu_helpers:get_reg_pair(RegPair, State).

set_reg_pair(RegPair, Value, State) ->
    z80_cpu_helpers:set_reg_pair(RegPair, Value, State).