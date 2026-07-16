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
    get_hl_mem_addr/2,
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
fetch_opcode(State = #machine_state{cpu = Cpu, memory = Mem}) ->
    Address = ?GET_PC(Cpu),
    Byte = read_byte(Address, Mem),
    NewR = (?GET_R(Cpu) band 16#80) bor ((?GET_R(Cpu) + 1) band 16#7F),
    Cpu1 = ?SET_PC(?SET_R(Cpu, NewR), (Address + 1) band 16#ffff),
    State1 = State#machine_state{cpu = Cpu1},
    {Byte, advance_tstates(State1, 4)}.

%% Regular byte fetch: operands, addresses (does NOT increment R, adds 3 T-states)
fetch_byte(State = #machine_state{cpu = Cpu, memory = Mem}) ->
    Address = ?GET_PC(Cpu),
    Byte = read_byte(Address, Mem),
    Cpu1 = ?SET_PC(Cpu, (Address + 1) band 16#ffff),
    State1 = State#machine_state{cpu = Cpu1},
    {Byte, advance_tstates(State1, 3)}.

fetch_word(State) ->
    {Lo, State1} = fetch_byte(State),
    {Hi, State2} = fetch_byte(State1),
    {?MAKE_PAIR(Hi, Lo), State2}.

read_byte(Address, Mem) ->
    ezx_mem:read_byte(Mem, Address band 16#ffff).

write_byte(Address, Byte, Mem) ->
    ezx_mem:write_byte(Mem, Address band 16#ffff, Byte band 16#ff).

read_word(Address, Mem) ->
    read_byte(Address, Mem) + (read_byte(Address + 1, Mem) bsl 8).

write_word(Address, Word, Mem) ->
    Mem1 = write_byte(Address, Word band 16#ff, Mem),
    write_byte(Address + 1, (Word bsr 8) band 16#ff, Mem1).

push_word(State, Value) ->
    Cpu = State#machine_state.cpu,
    Addr = (?GET_SP(Cpu) - 2) band 16#ffff,
    Mem1 = write_word(Addr, Value, State#machine_state.memory),
    Cpu1 = ?SET_SP(Cpu, Addr),
    State#machine_state{cpu = Cpu1, memory = Mem1}.

pop_word(State) ->
    Cpu = State#machine_state.cpu,
    Value = read_word(?GET_SP(Cpu), State#machine_state.memory),
    Cpu1 = ?SET_SP(Cpu, (?GET_SP(Cpu) + 2) band 16#ffff),
    {Value, State#machine_state{cpu = Cpu1}}.

advance_tstates(State, Extra) ->
    Cpu = State#machine_state.cpu,
    State#machine_state{cpu = ?SET_T_STATES(Cpu, ?GET_T_STATES(Cpu) + Extra)}.

%% Main registers access - simple 2-arity (CPU only, no memory)
get_reg_byte(a, Cpu) -> ?GET_A(Cpu);
get_reg_byte(b, Cpu) -> ?GET_B(Cpu);
get_reg_byte(c, Cpu) -> ?GET_C(Cpu);
get_reg_byte(d, Cpu) -> ?GET_D(Cpu);
get_reg_byte(e, Cpu) -> ?GET_E(Cpu);
get_reg_byte(h, Cpu) -> ?GET_H(Cpu);
get_reg_byte(l, Cpu) -> ?GET_L(Cpu);
get_reg_byte(ixh, Cpu) -> ?GET_IXH(Cpu);
get_reg_byte(ixl, Cpu) -> ?GET_IXL(Cpu);
get_reg_byte(iyh, Cpu) -> ?GET_IYH(Cpu);
get_reg_byte(iyl, Cpu) -> ?GET_IYL(Cpu).

set_reg_byte(a, Value, Cpu) -> ?SET_A(Cpu, Value);
set_reg_byte(b, Value, Cpu) -> ?SET_B(Cpu, Value);
set_reg_byte(c, Value, Cpu) -> ?SET_C(Cpu, Value);
set_reg_byte(d, Value, Cpu) -> ?SET_D(Cpu, Value);
set_reg_byte(e, Value, Cpu) -> ?SET_E(Cpu, Value);
set_reg_byte(h, Value, Cpu) -> ?SET_H(Cpu, Value);
set_reg_byte(l, Value, Cpu) -> ?SET_L(Cpu, Value);
set_reg_byte(ixh, Value, Cpu) -> ?SET_IXH(Cpu, Value);
set_reg_byte(ixl, Value, Cpu) -> ?SET_IXL(Cpu, Value);
set_reg_byte(iyh, Value, Cpu) -> ?SET_IYH(Cpu, Value);
set_reg_byte(iyl, Value, Cpu) -> ?SET_IYL(Cpu, Value).

get_reg_pair(bc, Cpu) -> ?MAKE_PAIR(?GET_B(Cpu), ?GET_C(Cpu));
get_reg_pair(de, Cpu) -> ?MAKE_PAIR(?GET_D(Cpu), ?GET_E(Cpu));
get_reg_pair(hl, Cpu) -> ?MAKE_PAIR(?GET_H(Cpu), ?GET_L(Cpu));
get_reg_pair(af, Cpu) -> ?MAKE_PAIR(?GET_A(Cpu), ?GET_F(Cpu));
get_reg_pair(ix, Cpu) -> ?MAKE_PAIR(?GET_IXH(Cpu), ?GET_IXL(Cpu));
get_reg_pair(iy, Cpu) -> ?MAKE_PAIR(?GET_IYH(Cpu), ?GET_IYL(Cpu));
get_reg_pair(sp, Cpu) -> ?GET_SP(Cpu).

set_reg_pair(bc, Val, Cpu) ->
    ?SET_C(?SET_B(Cpu, ?PAIR_HI(Val)), ?PAIR_LO(Val));
set_reg_pair(de, Val, Cpu) ->
    ?SET_E(?SET_D(Cpu, ?PAIR_HI(Val)), ?PAIR_LO(Val));
set_reg_pair(hl, Val, Cpu) ->
    ?SET_L(?SET_H(Cpu, ?PAIR_HI(Val)), ?PAIR_LO(Val));
set_reg_pair(af, Val, Cpu) ->
    ?SET_F(?SET_A(Cpu, ?PAIR_HI(Val)), ?PAIR_LO(Val));
set_reg_pair(ix, Val, Cpu) ->
    ?SET_IXL(?SET_IXH(Cpu, ?PAIR_HI(Val)), ?PAIR_LO(Val));
set_reg_pair(iy, Val, Cpu) ->
    ?SET_IYL(?SET_IYH(Cpu, ?PAIR_HI(Val)), ?PAIR_LO(Val));
set_reg_pair(sp, Val, Cpu) ->
    ?SET_SP(Cpu, Val).

%% Prefix-aware register pair accessors
get_reg_pair_prefixed(RegPair, Cpu) ->
    ActualPair = map_reg_pair(RegPair, Cpu),
    get_reg_pair(ActualPair, Cpu).

set_reg_pair_prefixed(RegPair, Val, Cpu) ->
    ActualPair = map_reg_pair(RegPair, Cpu),
    set_reg_pair(ActualPair, Val, Cpu).

%% Map register pair based on prefix
map_reg_pair(bc, _Cpu) -> bc;
map_reg_pair(de, _Cpu) -> de;
map_reg_pair(hl, Cpu) ->
    case ?GET_PREFIX(Cpu) of
        dd -> ix;
        fd -> iy;
        _  -> hl
    end;
map_reg_pair(af, _Cpu) -> af;
map_reg_pair(ix, _Cpu) -> ix;
map_reg_pair(iy, _Cpu) -> iy;
map_reg_pair(sp, _Cpu) -> sp.
%% These respect the CPU prefix state for DD/FD prefixes

get_hl_reg(Reg, Cpu) ->
    ActualReg = map_hl_reg(Reg, Cpu),
    get_reg_byte(ActualReg, Cpu).

set_hl_reg(Reg, Value, Cpu) ->
    ActualReg = map_hl_reg(Reg, Cpu),
    set_reg_byte(ActualReg, Value, Cpu).

get_hl_pair(Cpu) ->
    case ?GET_PREFIX(Cpu) of
        dd -> get_reg_pair(ix, Cpu);
        fd -> get_reg_pair(iy, Cpu);
        _  -> get_reg_pair(hl, Cpu)
    end.

set_hl_pair(Val, Cpu) ->
    case ?GET_PREFIX(Cpu) of
        dd -> set_reg_pair(ix, Val, Cpu);
        fd -> set_reg_pair(iy, Val, Cpu);
        _  -> set_reg_pair(hl, Val, Cpu)
    end.

%% Memory address based on HL/IX/IY (with optional displacement for CB prefix or DD/FD indexed addressing)
get_hl_mem_addr(Cpu, Mem) ->
    Base = get_hl_pair(Cpu),
    Disp = ?GET_DISPLACEMENT(Cpu),
    (Base + Disp) band 16#FFFF.

%% Fetch displacement byte for DD/FD indexed addressing if needed
%% The displacement byte follows the opcode in the instruction stream (DD/FD opcode disp)
%% Returns {Addr, State1} where State1 has updated PC and displacement
fetch_indexed_displacement(State) ->
    Cpu = State#machine_state.cpu,
    Prefix = ?GET_PREFIX(Cpu),
    case Prefix of
        dd ->
            case ?GET_DISPLACEMENT(Cpu) of
                0 ->
                    {Disp, State1} = fetch_byte(State),
                    Cpu1 = Cpu#cpu_state{displacement = Disp},
                    State1#machine_state{cpu = Cpu1};
                _ ->
                    State
            end;
        fd ->
            case ?GET_DISPLACEMENT(Cpu) of
                0 ->
                    {Disp, State1} = fetch_byte(State),
                    Cpu1 = Cpu#cpu_state{displacement = Disp},
                    State1#machine_state{cpu = Cpu1};
                _ ->
                    State
            end;
        _ ->
            State
    end.

read_hl_mem(State) ->
    State1 = fetch_indexed_displacement(State),
    Cpu = State1#machine_state.cpu,
    Addr = get_hl_mem_addr(Cpu, State1#machine_state.memory),
    Byte = ezx_mem:read_byte(State1#machine_state.memory, Addr),
    {Byte, State1}.

write_hl_mem(State, Val) ->
    State1 = fetch_indexed_displacement(State),
    Cpu = State1#machine_state.cpu,
    Addr = get_hl_mem_addr(Cpu, State1#machine_state.memory),
    Mem1 = write_byte(Addr, Val band 16#FF, State1#machine_state.memory),
    State1#machine_state{memory = Mem1}.

%% Prefix-aware register mapping for H/L registers
%% When DD prefix: h -> ixh, l -> ixl
%% When FD prefix: h -> iyh, l -> iyl
%% When no prefix: h -> h, l -> l

map_hl_reg(h, Cpu) ->
    case ?GET_PREFIX(Cpu) of
        dd -> ixh;
        fd -> iyh;
        _  -> h
    end;
map_hl_reg(l, Cpu) ->
    case ?GET_PREFIX(Cpu) of
        dd -> ixl;
        fd -> iyl;
        _  -> l
    end;
map_hl_reg(Reg, _Cpu) ->
    Reg.

%% Get register byte with prefix-aware H/L mapping
get_reg_byte_prefixed(Reg, Cpu) ->
    ActualReg = map_hl_reg(Reg, Cpu),
    get_reg_byte(ActualReg, Cpu).

%% Set register byte with prefix-aware H/L mapping
set_reg_byte_prefixed(Reg, Value, Cpu) ->
    ActualReg = map_hl_reg(Reg, Cpu),
    set_reg_byte(ActualReg, Value, Cpu).

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
do_add(State = #machine_state{cpu = Cpu}, Value) ->
    A = ?GET_A(Cpu),
    Sum = A + Value,
    Res = Sum band 16#FF,

    F_S = Res band 16#80,
    F_Z = if Res =:= 0 -> ?FLAG_Z; true -> 0 end,
    F_H = if ((A band 16#0F) + (Value band 16#0F)) > 16#0F -> ?FLAG_H; true -> 0 end,
    F_V = add_overflow(A, Value, Res),
    F_N = 0,
    F_C = if Sum > 16#FF -> ?FLAG_C; true -> 0 end,

    NewFlags = F_S bor F_Z bor F_H bor F_V bor F_N bor F_C,
    State#machine_state{cpu = ?SET_A(?SET_F(Cpu, NewFlags), Res)}.

%% ADC A, r / (HL) / n
do_adc(State = #machine_state{cpu = Cpu}, Value) ->
    A = ?GET_A(Cpu),
    Carry = ?GET_F(Cpu) band ?FLAG_C,
    Sum = A + Value + Carry,
    Res = Sum band 16#FF,

    F_S = Res band 16#80,
    F_Z = if Res =:= 0 -> ?FLAG_Z; true -> 0 end,
    F_H = if ((A band 16#0F) + (Value band 16#0F) + Carry) > 16#0F -> ?FLAG_H; true -> 0 end,
    F_V = add_overflow(A, Value, Res),
    F_N = 0,
    F_C = if Sum > 16#FF -> ?FLAG_C; true -> 0 end,

    NewFlags = F_S bor F_Z bor F_H bor F_V bor F_N bor F_C,
    State#machine_state{cpu = ?SET_A(?SET_F(Cpu, NewFlags), Res)}.

%% SUB A, r / (HL) / n
do_sub(State = #machine_state{cpu = Cpu}, Value) ->
    A = ?GET_A(Cpu),
    Diff = A - Value,
    Res = Diff band 16#FF,

    F_S = Res band 16#80,
    F_Z = if Res =:= 0 -> ?FLAG_Z; true -> 0 end,
    F_H = if (A band 16#0F) < (Value band 16#0F) -> ?FLAG_H; true -> 0 end,
    F_V = sub_overflow(A, Value, Res),
    F_N = ?FLAG_N,
    F_C = if Diff < 0 -> ?FLAG_C; true -> 0 end,

    NewFlags = F_S bor F_Z bor F_H bor F_V bor F_N bor F_C,
    State#machine_state{cpu = ?SET_A(?SET_F(Cpu, NewFlags), Res)}.

%% SBC A, r / (HL) / n
do_sbc(State = #machine_state{cpu = Cpu}, Value) ->
    A = ?GET_A(Cpu),
    Carry = ?GET_F(Cpu) band ?FLAG_C,
    Diff = A - Value - Carry,
    Res = Diff band 16#FF,

    F_S = Res band 16#80,
    F_Z = if Res =:= 0 -> ?FLAG_Z; true -> 0 end,
    F_H = if (A band 16#0F) < ((Value band 16#0F) + Carry) -> ?FLAG_H; true -> 0 end,
    F_V = sub_overflow(A, Value, Res),
    F_N = ?FLAG_N,
    F_C = if Diff < 0 -> ?FLAG_C; true -> 0 end,

    NewFlags = F_S bor F_Z bor F_H bor F_V bor F_N bor F_C,
    State#machine_state{cpu = ?SET_A(?SET_F(Cpu, NewFlags), Res)}.

%% AND r / (HL) / n
do_and(State = #machine_state{cpu = Cpu}, Value) ->
    Res = ?GET_A(Cpu) band Value,

    F_S = Res band 16#80,
    F_Z = if Res =:= 0 -> ?FLAG_Z; true -> 0 end,
    F_H = ?FLAG_H,
    F_V = parity(Res),
    F_N = 0,
    F_C = 0,

    NewFlags = F_S bor F_Z bor F_H bor F_V bor F_N bor F_C,
    State#machine_state{cpu = ?SET_A(?SET_F(Cpu, NewFlags), Res)}.

%% XOR r / (HL) / n
do_xor(State = #machine_state{cpu = Cpu}, Value) ->
    Res = ?GET_A(Cpu) bxor Value,

    F_S = Res band 16#80,
    F_Z = if Res =:= 0 -> ?FLAG_Z; true -> 0 end,
    F_H = 0,
    F_V = parity(Res),
    F_N = 0,
    F_C = 0,

    NewFlags = F_S bor F_Z bor F_H bor F_V bor F_N bor F_C,
    State#machine_state{cpu = ?SET_A(?SET_F(Cpu, NewFlags), Res)}.

%% OR r / (HL) / n
do_or(State = #machine_state{cpu = Cpu}, Value) ->
    Res = ?GET_A(Cpu) bor Value,

    F_S = Res band 16#80,
    F_Z = if Res =:= 0 -> ?FLAG_Z; true -> 0 end,
    F_H = 0,
    F_V = parity(Res),
    F_N = 0,
    F_C = 0,

    NewFlags = F_S bor F_Z bor F_H bor F_V bor F_N bor F_C,
    State#machine_state{cpu = ?SET_A(?SET_F(Cpu, NewFlags), Res)}.

%% CP r / (HL) / n
do_cp(State = #machine_state{cpu = Cpu}, Value) ->
    A = ?GET_A(Cpu),
    Diff = A - Value,
    Res = Diff band 16#FF,

    F_S = Res band 16#80,
    F_Z = if Res =:= 0 -> ?FLAG_Z; true -> 0 end,
    F_H = if (A band 16#0F) < (Value band 16#0F) -> ?FLAG_H; true -> 0 end,
    F_V = sub_overflow(A, Value, Res),
    F_N = ?FLAG_N,
    F_C = if Diff < 0 -> ?FLAG_C; true -> 0 end,

    NewFlags = F_S bor F_Z bor F_H bor F_V bor F_N bor F_C,
    State#machine_state{cpu = ?SET_F(Cpu, NewFlags)}.