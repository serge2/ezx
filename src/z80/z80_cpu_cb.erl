-module(z80_cpu_cb).

-include("z80_records.hrl").

-export([
    execute_cb_opcode/2,
    execute_cb_indexed_opcode/3
]).

%% @doc Execute a CB prefix opcode.
%% 8 T-states accumulated so far (4 from prefix + 4 from inner opcode fetch).
%% Returns updated cpu_state.
execute_cb_opcode(Opcode, State) ->
    case Opcode of
        %% RLC r / (HL) - 0x00-0x07
        16#00 -> {Byte, State1} = rotate_left(State#cpu_state.b, State),  State1#cpu_state{b = Byte};
        16#01 -> {Byte, State1} = rotate_left(State#cpu_state.c, State),  State1#cpu_state{c = Byte};
        16#02 -> {Byte, State1} = rotate_left(State#cpu_state.d, State),  State1#cpu_state{d = Byte};
        16#03 -> {Byte, State1} = rotate_left(State#cpu_state.e, State),  State1#cpu_state{e = Byte};
        16#04 -> {Byte, State1} = rotate_left(State#cpu_state.h, State),  State1#cpu_state{h = Byte};
        16#05 -> {Byte, State1} = rotate_left(State#cpu_state.l, State),  State1#cpu_state{l = Byte};
        16#06 -> State1 = rotate_left_hl(State), z80_cpu_helpers:advance_tstates(State1, 7);
        16#07 -> {Byte, State1} = rotate_left(State#cpu_state.a, State),  State1#cpu_state{a = Byte};

        %% RRC r / (HL) - 0x08-0x0F
        16#08 -> {Byte, State1} = rotate_right(State#cpu_state.b, State),  State1#cpu_state{b = Byte};
        16#09 -> {Byte, State1} = rotate_right(State#cpu_state.c, State),  State1#cpu_state{c = Byte};
        16#0A -> {Byte, State1} = rotate_right(State#cpu_state.d, State),  State1#cpu_state{d = Byte};
        16#0B -> {Byte, State1} = rotate_right(State#cpu_state.e, State),  State1#cpu_state{e = Byte};
        16#0C -> {Byte, State1} = rotate_right(State#cpu_state.h, State),  State1#cpu_state{h = Byte};
        16#0D -> {Byte, State1} = rotate_right(State#cpu_state.l, State),  State1#cpu_state{l = Byte};
        16#0E -> State1 = rotate_right_hl(State), z80_cpu_helpers:advance_tstates(State1, 7);
        16#0F -> {Byte, State1} = rotate_right(State#cpu_state.a, State),  State1#cpu_state{a = Byte};

        %% RL r / (HL) - 0x10-0x17
        16#10 -> {Byte, State1} = rotate_left_c(State#cpu_state.b, State),  State1#cpu_state{b = Byte};
        16#11 -> {Byte, State1} = rotate_left_c(State#cpu_state.c, State),  State1#cpu_state{c = Byte};
        16#12 -> {Byte, State1} = rotate_left_c(State#cpu_state.d, State),  State1#cpu_state{d = Byte};
        16#13 -> {Byte, State1} = rotate_left_c(State#cpu_state.e, State),  State1#cpu_state{e = Byte};
        16#14 -> {Byte, State1} = rotate_left_c(State#cpu_state.h, State),  State1#cpu_state{h = Byte};
        16#15 -> {Byte, State1} = rotate_left_c(State#cpu_state.l, State),  State1#cpu_state{l = Byte};
        16#16 -> State1 = rotate_left_c_hl(State), z80_cpu_helpers:advance_tstates(State1, 7);
        16#17 -> {Byte, State1} = rotate_left_c(State#cpu_state.a, State),  State1#cpu_state{a = Byte};

        %% RR r / (HL) - 0x18-0x1F
        16#18 -> {Byte, State1} = rotate_right_c(State#cpu_state.b, State),  State1#cpu_state{b = Byte};
        16#19 -> {Byte, State1} = rotate_right_c(State#cpu_state.c, State),  State1#cpu_state{c = Byte};
        16#1A -> {Byte, State1} = rotate_right_c(State#cpu_state.d, State),  State1#cpu_state{d = Byte};
        16#1B -> {Byte, State1} = rotate_right_c(State#cpu_state.e, State),  State1#cpu_state{e = Byte};
        16#1C -> {Byte, State1} = rotate_right_c(State#cpu_state.h, State),  State1#cpu_state{h = Byte};
        16#1D -> {Byte, State1} = rotate_right_c(State#cpu_state.l, State),  State1#cpu_state{l = Byte};
        16#1E -> State1 = rotate_right_c_hl(State), z80_cpu_helpers:advance_tstates(State1, 7);
        16#1F -> {Byte, State1} = rotate_right_c(State#cpu_state.a, State),  State1#cpu_state{a = Byte};

        %% SLA r / (HL) - 0x20-0x27
        16#20 -> {Byte, State1} = sla(State#cpu_state.b, State),  State1#cpu_state{b = Byte};
        16#21 -> {Byte, State1} = sla(State#cpu_state.c, State),  State1#cpu_state{c = Byte};
        16#22 -> {Byte, State1} = sla(State#cpu_state.d, State),  State1#cpu_state{d = Byte};
        16#23 -> {Byte, State1} = sla(State#cpu_state.e, State),  State1#cpu_state{e = Byte};
        16#24 -> {Byte, State1} = sla(State#cpu_state.h, State),  State1#cpu_state{h = Byte};
        16#25 -> {Byte, State1} = sla(State#cpu_state.l, State),  State1#cpu_state{l = Byte};
        16#26 -> State1 = sla_hl(State), z80_cpu_helpers:advance_tstates(State1, 7);
        16#27 -> {Byte, State1} = sla(State#cpu_state.a, State),  State1#cpu_state{a = Byte};

        %% SRA r / (HL) - 0x28-0x2F
        16#28 -> {Byte, State1} = sra(State#cpu_state.b, State),  State1#cpu_state{b = Byte};
        16#29 -> {Byte, State1} = sra(State#cpu_state.c, State),  State1#cpu_state{c = Byte};
        16#2A -> {Byte, State1} = sra(State#cpu_state.d, State),  State1#cpu_state{d = Byte};
        16#2B -> {Byte, State1} = sra(State#cpu_state.e, State),  State1#cpu_state{e = Byte};
        16#2C -> {Byte, State1} = sra(State#cpu_state.h, State),  State1#cpu_state{h = Byte};
        16#2D -> {Byte, State1} = sra(State#cpu_state.l, State),  State1#cpu_state{l = Byte};
        16#2E -> State1 = sra_hl(State), z80_cpu_helpers:advance_tstates(State1, 7);
        16#2F -> {Byte, State1} = sra(State#cpu_state.a, State),  State1#cpu_state{a = Byte};

        %% SLL (undocumented) r / (HL) - 0x30-0x37
        16#30 -> {Byte, State1} = sll(State#cpu_state.b, State),  State1#cpu_state{b = Byte};
        16#31 -> {Byte, State1} = sll(State#cpu_state.c, State),  State1#cpu_state{c = Byte};
        16#32 -> {Byte, State1} = sll(State#cpu_state.d, State),  State1#cpu_state{d = Byte};
        16#33 -> {Byte, State1} = sll(State#cpu_state.e, State),  State1#cpu_state{e = Byte};
        16#34 -> {Byte, State1} = sll(State#cpu_state.h, State),  State1#cpu_state{h = Byte};
        16#35 -> {Byte, State1} = sll(State#cpu_state.l, State),  State1#cpu_state{l = Byte};
        16#36 -> State1 = sll_hl(State), z80_cpu_helpers:advance_tstates(State1, 7);
        16#37 -> {Byte, State1} = sll(State#cpu_state.a, State),  State1#cpu_state{a = Byte};

        %% SRL r / (HL) - 0x38-0x3F
        16#38 -> {Byte, State1} = srl(State#cpu_state.b, State),  State1#cpu_state{b = Byte};
        16#39 -> {Byte, State1} = srl(State#cpu_state.c, State),  State1#cpu_state{c = Byte};
        16#3A -> {Byte, State1} = srl(State#cpu_state.d, State),  State1#cpu_state{d = Byte};
        16#3B -> {Byte, State1} = srl(State#cpu_state.e, State),  State1#cpu_state{e = Byte};
        16#3C -> {Byte, State1} = srl(State#cpu_state.h, State),  State1#cpu_state{h = Byte};
        16#3D -> {Byte, State1} = srl(State#cpu_state.l, State),  State1#cpu_state{l = Byte};
        16#3E -> State1 = srl_hl(State), z80_cpu_helpers:advance_tstates(State1, 7);
        16#3F -> {Byte, State1} = srl(State#cpu_state.a, State),  State1#cpu_state{a = Byte};

        %% BIT b,r - 0x40-0x7F
        Op when Op >= 16#40, Op =< 16#7F ->
            execute_cb_bit(Op, State);

        %% RES b,r - 0x80-0xBF
        Op when Op >= 16#80, Op =< 16#BF ->
            execute_cb_res(Op, State);

        %% SET b,r - 0xC0-0xFF
        Op when Op >= 16#C0, Op =< 16#FF ->
            execute_cb_set(Op, State)
    end.

%% --- (HL) Memory Access Variants ---

rotate_left_hl(State) ->
    Addr = z80_cpu_helpers:pair(State#cpu_state.h, State#cpu_state.l),
    {Byte, State1} = z80_cpu_helpers:read_byte(State, Addr),
    {NewByte, State2} = rotate_left(Byte, State1),
    z80_cpu_helpers:write_byte(State2, Addr, NewByte).

rotate_right_hl(State) ->
    Addr = z80_cpu_helpers:pair(State#cpu_state.h, State#cpu_state.l),
    {Byte, State1} = z80_cpu_helpers:read_byte(State, Addr),
    {NewByte, State2} = rotate_right(Byte, State1),
    z80_cpu_helpers:write_byte(State2, Addr, NewByte).

rotate_left_c_hl(State) ->
    Addr = z80_cpu_helpers:pair(State#cpu_state.h, State#cpu_state.l),
    {Byte, State1} = z80_cpu_helpers:read_byte(State, Addr),
    {NewByte, State2} = rotate_left_c(Byte, State1),
    z80_cpu_helpers:write_byte(State2, Addr, NewByte).

rotate_right_c_hl(State) ->
    Addr = z80_cpu_helpers:pair(State#cpu_state.h, State#cpu_state.l),
    {Byte, State1} = z80_cpu_helpers:read_byte(State, Addr),
    {NewByte, State2} = rotate_right_c(Byte, State1),
    z80_cpu_helpers:write_byte(State2, Addr, NewByte).

sla_hl(State) ->
    Addr = z80_cpu_helpers:pair(State#cpu_state.h, State#cpu_state.l),
    {Byte, State1} = z80_cpu_helpers:read_byte(State, Addr),
    {NewByte, State2} = sla(Byte, State1),
    z80_cpu_helpers:write_byte(State2, Addr, NewByte).

sra_hl(State) ->
    Addr = z80_cpu_helpers:pair(State#cpu_state.h, State#cpu_state.l),
    {Byte, State1} = z80_cpu_helpers:read_byte(State, Addr),
    {NewByte, State2} = sra(Byte, State1),
    z80_cpu_helpers:write_byte(State2, Addr, NewByte).

sll_hl(State) ->
    Addr = z80_cpu_helpers:pair(State#cpu_state.h, State#cpu_state.l),
    {Byte, State1} = z80_cpu_helpers:read_byte(State, Addr),
    {NewByte, State2} = sll(Byte, State1),
    z80_cpu_helpers:write_byte(State2, Addr, NewByte).

srl_hl(State) ->
    Addr = z80_cpu_helpers:pair(State#cpu_state.h, State#cpu_state.l),
    {Byte, State1} = z80_cpu_helpers:read_byte(State, Addr),
    {NewByte, State2} = srl(Byte, State1),
    z80_cpu_helpers:write_byte(State2, Addr, NewByte).

%% --- BIT b,r - 0x40-0x7F ---

execute_cb_bit(Opcode, State) ->
    Bit = (Opcode bsr 3) band 7,
    RegIdx = Opcode band 7,
    case RegIdx of
        6 ->  %% (HL) memory access
            Addr = z80_cpu_helpers:pair(State#cpu_state.h, State#cpu_state.l),
            {Byte, State1} = z80_cpu_helpers:read_byte(State, Addr);
        _ ->
            RegAtom = reg_index_to_atom(RegIdx),
            Byte = z80_cpu_helpers:get_reg_byte(RegAtom, State),
            State1 = State
    end,
    %% BIT: Z = ~bit, N = 0, H = 1, P/V = ~bit, S = bit, C = preserved
    TestedBit = (Byte band (1 bsl Bit)) =/= 0,
    Flags = State1#cpu_state.f band ?FLAG_C,  %% Preserve C only
    F_S = if TestedBit -> ?FLAG_S; true -> 0 end,
    F_Z = if TestedBit -> 0; true -> ?FLAG_Z end,
    F_H = ?FLAG_H,
    F_V = if TestedBit -> 0; true -> ?FLAG_V end,
    F_N = 0,
    NewFlags = Flags bor F_S bor F_Z bor F_H bor F_V bor F_N,
    NewState = State1#cpu_state{f = NewFlags},
    %% BIT (HL): 12T total = 8T base + 4T extra
    case RegIdx of
        6 -> z80_cpu_helpers:advance_tstates(NewState, 4);
        _ -> NewState
    end.

%% --- RES b,r - 0x80-0xBF ---

execute_cb_res(Opcode, State) ->
    Bit = (Opcode bsr 3) band 7,
    RegIdx = Opcode band 7,
    case RegIdx of
        6 ->  %% (HL) memory access
            Addr = z80_cpu_helpers:pair(State#cpu_state.h, State#cpu_state.l),
            {Byte, State1} = z80_cpu_helpers:read_byte(State, Addr),
            NewByte = Byte band (bnot (1 bsl Bit)),
            State2 = z80_cpu_helpers:write_byte(State1, Addr, NewByte);
        _ ->
            RegAtom = reg_index_to_atom(RegIdx),
            Byte = z80_cpu_helpers:get_reg_byte(RegAtom, State),
            NewByte = Byte band (bnot (1 bsl Bit)),
            State2 = z80_cpu_helpers:set_reg_byte(RegAtom, NewByte, State)
    end,
    %% RES/SET (HL): 15T total = 8T base + 7T extra
    case RegIdx of
        6 -> z80_cpu_helpers:advance_tstates(State2, 7);
        _ -> State2
    end.

%% --- SET b,r - 0xC0-0xFF ---

execute_cb_set(Opcode, State) ->
    Bit = (Opcode bsr 3) band 7,
    RegIdx = Opcode band 7,
    case RegIdx of
        6 ->  %% (HL) memory access
            Addr = z80_cpu_helpers:pair(State#cpu_state.h, State#cpu_state.l),
            {Byte, State1} = z80_cpu_helpers:read_byte(State, Addr),
            NewByte = Byte bor (1 bsl Bit),
            State2 = z80_cpu_helpers:write_byte(State1, Addr, NewByte);
        _ ->
            RegAtom = reg_index_to_atom(RegIdx),
            Byte = z80_cpu_helpers:get_reg_byte(RegAtom, State),
            NewByte = Byte bor (1 bsl Bit),
            State2 = z80_cpu_helpers:set_reg_byte(RegAtom, NewByte, State)
    end,
    %% RES/SET (HL): 15T total = 8T base + 7T extra
    case RegIdx of
        6 -> z80_cpu_helpers:advance_tstates(State2, 7);
        _ -> State2
    end.

%% Internal register index mapping (matches CB opcode encoding: 0=b,1=c,2=d,3=e,4=h,5=l,6=(HL),7=a)
reg_index_to_atom(0) -> b;
reg_index_to_atom(1) -> c;
reg_index_to_atom(2) -> d;
reg_index_to_atom(3) -> e;
reg_index_to_atom(4) -> h;
reg_index_to_atom(5) -> l;
reg_index_to_atom(6) -> hl_mem;  %% Special: (HL) memory access handled by caller
reg_index_to_atom(7) -> a.

%% --- Core Shift/Rotate Operations ---

rotate_left(Byte, Cpu) ->
    Carry = (Byte band 16#80) bsr 7,
    NewByte = ((Byte bsl 1) band 16#ff) bor Carry,
    Flags = Cpu#cpu_state.f band 16#E4,
    F_S = NewByte band 16#80,
    F_Z = if NewByte =:= 0 -> ?FLAG_Z; true -> 0 end,
    F_H = 0,
    F_V = z80_cpu_helpers:parity(NewByte),
    F_N = 0,
    F_C = Carry,
    NewFlags = Flags bor F_S bor F_Z bor F_H bor F_V bor F_N bor F_C,
    {NewByte, Cpu#cpu_state{f = NewFlags}}.

rotate_right(Byte, Cpu) ->
    Carry = Byte band 1,
    NewByte = (Byte bsr 1) bor (Carry bsl 7),
    Flags = Cpu#cpu_state.f band 16#E4,
    F_S = NewByte band 16#80,
    F_Z = if NewByte =:= 0 -> ?FLAG_Z; true -> 0 end,
    F_H = 0,
    F_V = z80_cpu_helpers:parity(NewByte),
    F_N = 0,
    F_C = Carry,
    NewFlags = Flags bor F_S bor F_Z bor F_H bor F_V bor F_N bor F_C,
    {NewByte, Cpu#cpu_state{f = NewFlags}}.

%% RL (Rotate Left through Carry) - 0x10-0x17
rotate_left_c(Byte, Cpu) ->
    OldCarry = Cpu#cpu_state.f band ?FLAG_C,
    NewCarry = (Byte band 16#80) bsr 7,
    NewByte = ((Byte bsl 1) band 16#ff) bor OldCarry,
    Flags = Cpu#cpu_state.f band 16#E4,
    F_S = NewByte band 16#80,
    F_Z = if NewByte =:= 0 -> ?FLAG_Z; true -> 0 end,
    F_H = 0,
    F_V = z80_cpu_helpers:parity(NewByte),
    F_N = 0,
    F_C = NewCarry,
    NewFlags = Flags bor F_S bor F_Z bor F_H bor F_V bor F_N bor F_C,
    {NewByte, Cpu#cpu_state{f = NewFlags}}.

%% RR (Rotate Right through Carry) - 0x18-0x1F
rotate_right_c(Byte, Cpu) ->
    OldCarry = Cpu#cpu_state.f band ?FLAG_C,
    NewCarry = Byte band 1,
    NewByte = (Byte bsr 1) bor (OldCarry bsl 7),
    Flags = Cpu#cpu_state.f band 16#E4,
    F_S = NewByte band 16#80,
    F_Z = if NewByte =:= 0 -> ?FLAG_Z; true -> 0 end,
    F_H = 0,
    F_V = z80_cpu_helpers:parity(NewByte),
    F_N = 0,
    F_C = NewCarry,
    NewFlags = Flags bor F_S bor F_Z bor F_H bor F_V bor F_N bor F_C,
    {NewByte, Cpu#cpu_state{f = NewFlags}}.

%% SLA (Shift Left Arithmetic) - 0x20-0x27
sla(Byte, Cpu) ->
    NewCarry = (Byte band 16#80) bsr 7,
    NewByte = (Byte bsl 1) band 16#ff,
    Flags = Cpu#cpu_state.f band 16#E4,
    F_S = NewByte band 16#80,
    F_Z = if NewByte =:= 0 -> ?FLAG_Z; true -> 0 end,
    F_H = 0,
    F_V = z80_cpu_helpers:parity(NewByte),
    F_N = 0,
    F_C = NewCarry,
    NewFlags = Flags bor F_S bor F_Z bor F_H bor F_V bor F_N bor F_C,
    {NewByte, Cpu#cpu_state{f = NewFlags}}.

%% SRA (Shift Right Arithmetic) - 0x28-0x2F
sra(Byte, Cpu) ->
    NewCarry = Byte band 1,
    NewByte = (Byte bsr 1) bor (Byte band 16#80),
    Flags = Cpu#cpu_state.f band 16#E4,
    F_S = NewByte band 16#80,
    F_Z = if NewByte =:= 0 -> ?FLAG_Z; true -> 0 end,
    F_H = 0,
    F_V = z80_cpu_helpers:parity(NewByte),
    F_N = 0,
    F_C = NewCarry,
    NewFlags = Flags bor F_S bor F_Z bor F_H bor F_V bor F_N bor F_C,
    {NewByte, Cpu#cpu_state{f = NewFlags}}.

%% SLL (Shift Left Logical, undocumented) - 0x30-0x37
sll(Byte, Cpu) ->
    NewCarry = (Byte band 16#80) bsr 7,
    NewByte = ((Byte bsl 1) band 16#ff) bor 1,
    Flags = Cpu#cpu_state.f band 16#E4,
    F_S = NewByte band 16#80,
    F_Z = if NewByte =:= 0 -> ?FLAG_Z; true -> 0 end,
    F_H = 0,
    F_V = z80_cpu_helpers:parity(NewByte),
    F_N = 0,
    F_C = NewCarry,
    NewFlags = Flags bor F_S bor F_Z bor F_H bor F_V bor F_N bor F_C,
    {NewByte, Cpu#cpu_state{f = NewFlags}}.

%% SRL (Shift Right Logical) - 0x38-0x3F
srl(Byte, Cpu) ->
    NewCarry = Byte band 1,
    NewByte = Byte bsr 1,
    Flags = Cpu#cpu_state.f band 16#E4,
    F_S = NewByte band 16#80,
    F_Z = if NewByte =:= 0 -> ?FLAG_Z; true -> 0 end,
    F_H = 0,
    F_V = z80_cpu_helpers:parity(NewByte),
    F_N = 0,
    F_C = NewCarry,
    NewFlags = Flags bor F_S bor F_Z bor F_H bor F_V bor F_N bor F_C,
    {NewByte, Cpu#cpu_state{f = NewFlags}}.

%% @doc Execute a DD CB / FD CB indexed opcode.
%% Format: DD/FD, CB, displacement, CB_opcode
%% CB_opcode bits: x=bits7-6, y=bits5-3, z=bits2-0
%% Per z80.info spec:
%%   x=0 (ROT): z≠6 -> LD r[z], rot[y](IX+d)  (copy to register)
%%              z=6  -> rot[y](IX+d)           (memory only)
%%   x=1 (BIT): BIT y,(IX+d)                  (memory only, no register copy)
%%   x=2 (RES): z≠6 -> LD r[z], RES y,(IX+d)  (copy to register)
%%              z=6  -> RES y,(IX+d)           (memory only)
%%   x=3 (SET): z≠6 -> LD r[z], SET y,(IX+d)  (copy to register)
%%              z=6  -> SET y,(IX+d)           (memory only)
%% Reg is either 'ix' or 'iy'.
%% Returns updated cpu_state.
execute_cb_indexed_opcode(Opcode, Reg, State) ->
    %% Extract x, y, z from CB opcode
    X = (Opcode bsr 6) band 3,      %% bits 7-6: 0=ROT, 1=BIT, 2=RES, 3=SET
    Y = (Opcode bsr 3) band 7,      %% bits 5-3: bit position or rot type
    Z = Opcode band 7,              %% bits 2-0: register field
    
    %% Memory address = IX/IY + displacement (signed)
    BaseAddr = z80_cpu_helpers:get_reg_pair(Reg, State),
    Disp = ?GET_DISPLACEMENT(State),
    Addr = (BaseAddr + Disp) band 16#FFFF,
    
    %% Read byte from memory at (IX/IY+d)
    {Byte, State1} = z80_cpu_helpers:read_byte(State, Addr),
    
    %% Execute operation based on x and z
    {NewByte, State2, CopyToReg} = case X of
        0 ->  %% ROT: RLC/RRC/RL/RR/SLA/SRA/SLL/SRL
            {Result, NewCpu} = execute_cb_rot(Y, Byte, State1),
            case Z of
                6 -> {Result, NewCpu, false};           %% Memory only
                _ -> {Result, NewCpu, true}             %% Copy to register r[z]
            end;
        1 ->  %% BIT: test bit
            {_, NewCpu} = execute_cb_bit_on_byte(Y, Byte, State1),
            {Byte, NewCpu, false};                       %% Memory only, value unchanged
        2 ->  %% RES: reset bit
            {Result, NewCpu} = execute_cb_res_on_byte(Y, Byte, State1),
            case Z of
                6 -> {Result, NewCpu, false};           %% Memory only
                _ -> {Result, NewCpu, true}             %% Copy to register r[z]
            end;
        3 ->  %% SET: set bit
            {Result, NewCpu} = execute_cb_set_on_byte(Y, Byte, State1),
            case Z of
                6 -> {Result, NewCpu, false};           %% Memory only
                _ -> {Result, NewCpu, true}             %% Copy to register r[z]
            end
    end,
    
    %% Write result back to memory at (IX+d) - State2 already has correct f
    State3 = z80_cpu_helpers:write_byte(State2, Addr, NewByte),
    
    %% Copy to register r[z] if needed (z != 6)
    State4 = case CopyToReg of
        true ->
            case Z of
                0 -> State3#cpu_state{b = NewByte};
                1 -> State3#cpu_state{c = NewByte};
                2 -> State3#cpu_state{d = NewByte};
                3 -> State3#cpu_state{e = NewByte};
                4 -> State3#cpu_state{h = NewByte};
                5 -> State3#cpu_state{l = NewByte};
                7 -> State3#cpu_state{a = NewByte}
            end;
        false ->
            State3
    end,
    
    %% DD CB / FD CB takes 8 additional T-states (total 23)
    z80_cpu_helpers:advance_tstates(State4, 8).

%% ROT operations for indexed (uses Y for rot type)
execute_cb_rot(RotType, Byte, State) ->
    case RotType of
        0 -> rotate_left(Byte, State);      %% RLC
        1 -> rotate_right(Byte, State);     %% RRC
        2 -> rotate_left_c(Byte, State);    %% RL
        3 -> rotate_right_c(Byte, State);   %% RR
        4 -> sla(Byte, State);              %% SLA
        5 -> sra(Byte, State);              %% SRA
        6 -> sll(Byte, State);              %% SLL
        7 -> srl(Byte, State)               %% SRL
    end.

%% BIT operation for indexed (uses Y for bit position)
execute_cb_bit_on_byte(BitPos, Byte, State) ->
    Mask = 1 bsl BitPos,
    TestedBit = (Byte band Mask) =/= 0,
    F_S = if TestedBit -> ?FLAG_S; true -> 0 end,
    F_H = ?FLAG_H,
    F_V = if TestedBit -> 0; true -> ?FLAG_V end,
    F_N = 0,
    F_Z = if TestedBit -> 0; true -> ?FLAG_Z end,
    F = State#cpu_state.f,
    NewF = (F band ?FLAG_C) bor F_S bor F_Z bor F_H bor F_V bor F_N,
    {Byte, State#cpu_state{f = NewF}}.

%% RES operation for indexed (uses Y for bit position)
execute_cb_res_on_byte(BitPos, Byte, State) ->
    Mask = 1 bsl BitPos,
    NewByte = Byte band (bnot Mask),
    {NewByte, State}.

%% SET operation for indexed (uses Y for bit position)
execute_cb_set_on_byte(BitPos, Byte, State) ->
    Mask = 1 bsl BitPos,
    NewByte = Byte bor Mask,
    {NewByte, State}.
