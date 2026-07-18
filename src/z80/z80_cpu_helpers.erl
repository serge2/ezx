-module(z80_cpu_helpers).

-include("z80_records.hrl").

-export([
    fetch_opcode/1,
    fetch_byte/1,
    fetch_word/1,
    read_byte/2,
    write_byte/3,
    read_word/2,
    write_word/3,
    push_word/2,
    pop_word/1,
    advance_tstates/2,
    get_reg_byte/2,
    set_reg_byte/3,
    get_reg_pair/2,
    set_reg_pair/3,
    dec_byte/1,
    inc_byte/1,
    pair/2,
    signed_byte/1,
    set_carry/2,
    parity/1,
    add_overflow/3,
    sub_overflow/3,
    check_condition/2,
    do_add/2,
    do_adc/2,
    do_sub/2,
    do_sbc/2,
    do_and/2,
    do_xor/2,
    do_or/2,
    do_cp/2,
    %% Unified prefix-aware register accessors
    get_hl_reg/2,
    set_hl_reg/3,
    get_hl_pair/1,
    set_hl_pair/2,
    get_hl_mem_addr/1,
    read_hl_mem/1,
    write_hl_mem/2,
    fetch_indexed_displacement/1,
    %% Prefix-aware register pair accessors
    get_reg_pair_prefixed/2,
    set_reg_pair_prefixed/3,
    map_reg_pair/2,
    %% Prefix-aware H/L mapping
    map_hl_reg/2,
    get_reg_byte_prefixed/2,
    set_reg_byte_prefixed/3
]).

%% M1 cycle: opcode fetch (increments R register, adds 4 T-states)
fetch_opcode(State) ->
    Address = ?GET_PC(State),
    {Byte, State1} = read_byte(State, Address),
    R = ?GET_R(State1),
    State2 = ?SET_R(State1, (R band 16#80) bor ((R + 1) band 16#7F)), 
    State3 = ?SET_PC(State2, (Address + 1) band 16#ffff),
    {Byte, advance_tstates(State3, 4)}.

%% Regular byte fetch: operands, addresses (does NOT increment R, adds 3 T-states)
fetch_byte(State) ->
    Address = ?GET_PC(State),
    {Byte, State1} = read_byte(State, Address),
    State2 = ?SET_PC(State1, (Address + 1) band 16#ffff),
    {Byte, advance_tstates(State2, 3)}.

fetch_word(State) ->
    {Lo, State1} = fetch_byte(State),
    {Hi, State2} = fetch_byte(State1),
    {?MAKE_PAIR(Hi, Lo), State2}.

read_byte(State = #cpu_state{mem_read_fun = ReadFun, ext_context = ExtContext}, Address) ->
    {Byte, ExtContext1} = ReadFun(ExtContext, Address band 16#ffff),
    {Byte, State#cpu_state{ext_context = ExtContext1}}.


write_byte(State = #cpu_state{mem_write_fun = WriteFun, ext_context = ExtContext}, Address, Byte) ->
    ExtContext1 = WriteFun(ExtContext, Address band 16#ffff, Byte band 16#ff),
    State#cpu_state{ext_context = ExtContext1}.

read_word(State, Address) ->
    {Lo, State1} = read_byte(State, Address),
    {Hi, State2} = read_byte(State1, Address + 1),
    {?MAKE_PAIR(Hi, Lo), State2}.

write_word(State, Address, Word) ->
    State1 = write_byte(State, Address, Word band 16#ff),
    write_byte(State1, Address + 1, (Word bsr 8) band 16#ff).

push_word(State, Value) ->
    Addr = (?GET_SP(State) - 2) band 16#ffff,
    State1 = write_word(State, Addr, Value),
    ?SET_SP(State1, Addr).

pop_word(State) ->
    {Value, State1} = read_word(State, ?GET_SP(State)),
    State2 = ?SET_SP(State1, (?GET_SP(State1) + 2) band 16#ffff),
    {Value, State2}.

advance_tstates(State, Extra) ->
    ?SET_T_STATES(State, ?GET_T_STATES(State) + Extra).

%% Main registers access - simple 2-arity (CPU only, no memory)
get_reg_byte(a, State) -> ?GET_A(State);
get_reg_byte(b, State) -> ?GET_B(State);
get_reg_byte(c, State) -> ?GET_C(State);
get_reg_byte(d, State) -> ?GET_D(State);
get_reg_byte(e, State) -> ?GET_E(State);
get_reg_byte(h, State) -> ?GET_H(State);
get_reg_byte(l, State) -> ?GET_L(State);
get_reg_byte(ixh, State) -> ?GET_IXH(State);
get_reg_byte(ixl, State) -> ?GET_IXL(State);
get_reg_byte(iyh, State) -> ?GET_IYH(State);
get_reg_byte(iyl, State) -> ?GET_IYL(State).

set_reg_byte(a, Value, State) -> ?SET_A(State, Value);
set_reg_byte(b, Value, State) -> ?SET_B(State, Value);
set_reg_byte(c, Value, State) -> ?SET_C(State, Value);
set_reg_byte(d, Value, State) -> ?SET_D(State, Value);
set_reg_byte(e, Value, State) -> ?SET_E(State, Value);
set_reg_byte(h, Value, State) -> ?SET_H(State, Value);
set_reg_byte(l, Value, State) -> ?SET_L(State, Value);
set_reg_byte(ixh, Value, State) -> ?SET_IXH(State, Value);
set_reg_byte(ixl, Value, State) -> ?SET_IXL(State, Value);
set_reg_byte(iyh, Value, State) -> ?SET_IYH(State, Value);
set_reg_byte(iyl, Value, State) -> ?SET_IYL(State, Value).

get_reg_pair(bc, State) -> ?MAKE_PAIR(?GET_B(State), ?GET_C(State));
get_reg_pair(de, State) -> ?MAKE_PAIR(?GET_D(State), ?GET_E(State));
get_reg_pair(hl, State) -> ?MAKE_PAIR(?GET_H(State), ?GET_L(State));
get_reg_pair(af, State) -> ?MAKE_PAIR(?GET_A(State), ?GET_F(State));
get_reg_pair(ix, State) -> ?MAKE_PAIR(?GET_IXH(State), ?GET_IXL(State));
get_reg_pair(iy, State) -> ?MAKE_PAIR(?GET_IYH(State), ?GET_IYL(State));
get_reg_pair(sp, State) -> ?GET_SP(State).

set_reg_pair(bc, Val, State) ->
    ?SET_C(?SET_B(State, ?PAIR_HI(Val)), ?PAIR_LO(Val));
set_reg_pair(de, Val, State) ->
    ?SET_E(?SET_D(State, ?PAIR_HI(Val)), ?PAIR_LO(Val));
set_reg_pair(hl, Val, State) ->
    ?SET_L(?SET_H(State, ?PAIR_HI(Val)), ?PAIR_LO(Val));
set_reg_pair(af, Val, State) ->
    ?SET_F(?SET_A(State, ?PAIR_HI(Val)), ?PAIR_LO(Val));
set_reg_pair(ix, Val, State) ->
    ?SET_IXL(?SET_IXH(State, ?PAIR_HI(Val)), ?PAIR_LO(Val));
set_reg_pair(iy, Val, State) ->
    ?SET_IYL(?SET_IYH(State, ?PAIR_HI(Val)), ?PAIR_LO(Val));
set_reg_pair(sp, Val, State) ->
    ?SET_SP(State, Val).

%% Prefix-aware register pair accessors
get_reg_pair_prefixed(RegPair, State) ->
    ActualPair = map_reg_pair(RegPair, State),
    get_reg_pair(ActualPair, State).

set_reg_pair_prefixed(RegPair, Val, State) ->
    ActualPair = map_reg_pair(RegPair, State),
    set_reg_pair(ActualPair, Val, State).

%% Map register pair based on prefix
map_reg_pair(bc, _State) -> bc;
map_reg_pair(de, _State) -> de;
map_reg_pair(hl, State) ->
    case ?GET_PREFIX(State) of
        dd -> ix;
        fd -> iy;
        _  -> hl
    end;
map_reg_pair(af, _State) -> af;
map_reg_pair(ix, _State) -> ix;
map_reg_pair(iy, _State) -> iy;
map_reg_pair(sp, _State) -> sp.

%% These respect the CPU prefix state for DD/FD prefixes
get_hl_reg(Reg, State) ->
    ActualReg = map_hl_reg(Reg, State),
    get_reg_byte(ActualReg, State).

set_hl_reg(Reg, Value, State) ->
    ActualReg = map_hl_reg(Reg, State),
    set_reg_byte(ActualReg, Value, State).

get_hl_pair(State) ->
    case ?GET_PREFIX(State) of
        dd -> get_reg_pair(ix, State);
        fd -> get_reg_pair(iy, State);
        _  -> get_reg_pair(hl, State)
    end.

set_hl_pair(Val, State) ->
    case ?GET_PREFIX(State) of
        dd -> set_reg_pair(ix, Val, State);
        fd -> set_reg_pair(iy, Val, State);
        _  -> set_reg_pair(hl, Val, State)
    end.

%% Memory address based on HL/IX/IY (with optional displacement for CB prefix or DD/FD indexed addressing)
get_hl_mem_addr(State) ->
    Base = get_hl_pair(State),
    Disp = ?GET_DISPLACEMENT(State),
    (Base + Disp) band 16#FFFF.

%% Fetch displacement byte for DD/FD indexed addressing if needed
%% The displacement byte follows the opcode in the instruction stream (DD/FD opcode disp)
%% Returns {Addr, State1} where State1 has updated PC and displacement
fetch_indexed_displacement(State) ->
    Prefix = ?GET_PREFIX(State),
    if
        Prefix == dd orelse Prefix == fd ->
            case ?GET_DISPLACEMENT(State) of
                0 ->
                    {Disp, State1} = fetch_byte(State),
                    ?SET_DISPLACEMENT(State1, Disp);
                _ ->
                    State
            end;
        true ->
            State
    end.

read_hl_mem(State) ->
    State1 = fetch_indexed_displacement(State),
    Addr = get_hl_mem_addr(State1),
    {Byte, State2} = read_byte(State1, Addr),
    {Byte, State2}.

write_hl_mem(State, Val) ->
    State1 = fetch_indexed_displacement(State),
    Addr = get_hl_mem_addr(State1),
    State2 = write_byte(State1, Addr, Val band 16#FF),
    State2.

%% Prefix-aware register mapping for H/L registers
%% When DD prefix: h -> ixh, l -> ixl
%% When FD prefix: h -> iyh, l -> iyl
%% When no prefix: h -> h, l -> l

map_hl_reg(h, State) ->
    case ?GET_PREFIX(State) of
        dd -> ixh;
        fd -> iyh;
        _  -> h
    end;
map_hl_reg(l, State) ->
    case ?GET_PREFIX(State) of
        dd -> ixl;
        fd -> iyl;
        _  -> l
    end;
map_hl_reg(Reg, _State) ->
    Reg.

%% Get register byte with prefix-aware H/L mapping
get_reg_byte_prefixed(Reg, State) ->
    ActualReg = map_hl_reg(Reg, State),
    get_reg_byte(ActualReg, State).

%% Set register byte with prefix-aware H/L mapping
set_reg_byte_prefixed(Reg, Value, State) ->
    ActualReg = map_hl_reg(Reg, State),
    set_reg_byte(ActualReg, Value, State).

dec_byte(Byte) ->
    (Byte - 1) band 16#FF.

inc_byte(Byte) ->
    (Byte + 1) band 16#FF.

pair(ByteH, ByteL) ->
    ?MAKE_PAIR(ByteH, ByteL).

signed_byte(Byte) ->
    ?SIGNED_BYTE(Byte).

%% Carry flag helper
set_carry(Flags, Carry) ->
    case Carry of
        0 -> Flags band bnot 1;
        1 -> Flags bor 1
    end.

%% Parity evaluation helper (nibble lookup table + XNOR - faster than bit counting)
parity(Val) ->
    V0 = Val band 16#FF,
    Hi = parity_nibble(V0 bsr 4),
    Lo = parity_nibble(V0 band 16#F),
    %% XNOR: 1 if equal (both even or both odd), 0 if different
    ParityBit = (Hi bxor Lo) bxor 1,
    case ParityBit of
        1 -> ?FLAG_V;
        0 -> 0
    end.

%% Parity table for 0-15 (returns parity bit: 1 for even, 0 for odd)
parity_nibble(N) when N < 16 ->
    element(N + 1, {1,0,0,1,0,1,1,0,0,1,1,0,1,0,0,1}).

%% 8-bit Addition overflow detection helper
add_overflow(A, B, Res) ->
    case ((A bxor Res) band (B bxor Res) band 16#80) of
        0 -> 0;
        _ -> ?FLAG_V
    end.

%% 8-bit Subtraction overflow detection helper
sub_overflow(A, B, Res) ->
    case ((A bxor B) band (A bxor Res) band 16#80) of
        0 -> 0;
        _ -> ?FLAG_V
    end.

%% Condition Evaluation Helper
check_condition(Cond, Flags) ->
    case Cond of
        nz -> (Flags band ?FLAG_Z) =:= 0;
        z  -> (Flags band ?FLAG_Z) =/= 0;
        nc -> (Flags band ?FLAG_C) =:= 0;
        c  -> (Flags band ?FLAG_C) =/= 0;
        po -> (Flags band ?FLAG_V) =:= 0;
        pe -> (Flags band ?FLAG_V) =/= 0;
        p  -> (Flags band ?FLAG_S) =:= 0;
        m  -> (Flags band ?FLAG_S) =/= 0
    end.

%% --- Core Math & Logic Helpers with Flag Management ---

%% ADD A, r / (HL) / n
do_add(State, Value) ->
    A = ?GET_A(State),
    Sum = A + Value,
    Res = Sum band 16#FF,

    F_S = Res band 16#80,
    F_Z = if Res =:= 0 -> ?FLAG_Z; true -> 0 end,
    F_H = if ((A band 16#0F) + (Value band 16#0F)) > 16#0F -> ?FLAG_H; true -> 0 end,
    F_V = add_overflow(A, Value, Res),
    F_N = 0,
    F_C = if Sum > 16#FF -> ?FLAG_C; true -> 0 end,

    NewFlags = F_S bor F_Z bor F_H bor F_V bor F_N bor F_C,
    ?SET_A(?SET_F(State, NewFlags), Res).

%% ADC A, r / (HL) / n
do_adc(State, Value) ->
    A = ?GET_A(State),
    Carry = ?GET_F(State) band ?FLAG_C,
    Sum = A + Value + Carry,
    Res = Sum band 16#FF,

    F_S = Res band 16#80,
    F_Z = if Res =:= 0 -> ?FLAG_Z; true -> 0 end,
    F_H = if ((A band 16#0F) + (Value band 16#0F) + Carry) > 16#0F -> ?FLAG_H; true -> 0 end,
    F_V = add_overflow(A, Value, Res),
    F_N = 0,
    F_C = if Sum > 16#FF -> ?FLAG_C; true -> 0 end,

    NewFlags = F_S bor F_Z bor F_H bor F_V bor F_N bor F_C,
    ?SET_A(?SET_F(State, NewFlags), Res).

%% SUB A, r / (HL) / n
do_sub(State, Value) ->
    A = ?GET_A(State),
    Diff = A - Value,
    Res = Diff band 16#FF,

    F_S = Res band 16#80,
    F_Z = if Res =:= 0 -> ?FLAG_Z; true -> 0 end,
    F_H = if (A band 16#0F) < (Value band 16#0F) -> ?FLAG_H; true -> 0 end,
    F_V = sub_overflow(A, Value, Res),
    F_N = ?FLAG_N,
    F_C = if Diff < 0 -> ?FLAG_C; true -> 0 end,

    NewFlags = F_S bor F_Z bor F_H bor F_V bor F_N bor F_C,
    ?SET_A(?SET_F(State, NewFlags), Res).

%% SBC A, r / (HL) / n
do_sbc(State, Value) ->
    A = ?GET_A(State),
    Carry = ?GET_F(State) band ?FLAG_C,
    Diff = A - Value - Carry,
    Res = Diff band 16#FF,

    F_S = Res band 16#80,
    F_Z = if Res =:= 0 -> ?FLAG_Z; true -> 0 end,
    F_H = if (A band 16#0F) < ((Value band 16#0F) + Carry) -> ?FLAG_H; true -> 0 end,
    F_V = sub_overflow(A, Value, Res),
    F_N = ?FLAG_N,
    F_C = if Diff < 0 -> ?FLAG_C; true -> 0 end,

    NewFlags = F_S bor F_Z bor F_H bor F_V bor F_N bor F_C,
    ?SET_A(?SET_F(State, NewFlags), Res).

%% AND r / (HL) / n
do_and(State, Value) ->
    Res = ?GET_A(State) band Value,

    F_S = Res band 16#80,
    F_Z = if Res =:= 0 -> ?FLAG_Z; true -> 0 end,
    F_H = ?FLAG_H,
    F_V = parity(Res),
    F_N = 0,
    F_C = 0,

    NewFlags = F_S bor F_Z bor F_H bor F_V bor F_N bor F_C,
    ?SET_A(?SET_F(State, NewFlags), Res).

%% XOR r / (HL) / n
do_xor(State, Value) ->
    Res = ?GET_A(State) bxor Value,

    F_S = Res band 16#80,
    F_Z = if Res =:= 0 -> ?FLAG_Z; true -> 0 end,
    F_H = 0,
    F_V = parity(Res),
    F_N = 0,
    F_C = 0,

    NewFlags = F_S bor F_Z bor F_H bor F_V bor F_N bor F_C,
    ?SET_A(?SET_F(State, NewFlags), Res).

%% OR r / (HL) / n
do_or(State, Value) ->
    Res = ?GET_A(State) bor Value,

    F_S = Res band 16#80,
    F_Z = if Res =:= 0 -> ?FLAG_Z; true -> 0 end,
    F_H = 0,
    F_V = parity(Res),
    F_N = 0,
    F_C = 0,

    NewFlags = F_S bor F_Z bor F_H bor F_V bor F_N bor F_C,
    ?SET_A(?SET_F(State, NewFlags), Res).

%% CP r / (HL) / n
do_cp(State, Value) ->
    A = ?GET_A(State),
    Diff = A - Value,
    Res = Diff band 16#FF,

    F_S = Res band 16#80,
    F_Z = if Res =:= 0 -> ?FLAG_Z; true -> 0 end,
    F_H = if (A band 16#0F) < (Value band 16#0F) -> ?FLAG_H; true -> 0 end,
    F_V = sub_overflow(A, Value, Res),
    F_N = ?FLAG_N,
    F_C = if Diff < 0 -> ?FLAG_C; true -> 0 end,

    NewFlags = F_S bor F_Z bor F_H bor F_V bor F_N bor F_C,
    ?SET_F(State, NewFlags).