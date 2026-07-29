-module(z80_cpu_ed).

-include("z80_records.hrl").

-export([
    execute_ed_opcode/2
]).

%% @doc Execute an ED prefix opcode.
%% 8 T-states accumulated so far (4 from prefix + 4 from inner opcode fetch).
%% Returns updated cpu_state.
execute_ed_opcode(Opcode, State) ->
    case Opcode of
        %% LD I, A: 9 T-states total (8 + 1)
        16#47 ->
            execute_ed_ld_i_a(State);

        %% LD R, A: 9 T-states total (8 + 1)
        16#4F ->
            execute_ed_ld_r_a(State);

        %% LD A, I: 9 T-states total (8 + 1)
        16#57 ->
            execute_ed_ld_a_i(State);

        %% LD A, R: 9 T-states total (8 + 1)
        16#5F ->
            execute_ed_ld_a_r(State);

        %% NEG: 8 T-states total (8 + 0)
        16#44 ->
            execute_ed_neg(State);

        %% RETN: 14 T-states total (8 + 6)
        16#45 ->
            execute_ed_retn(State);

        %% RETI: 14 T-states total (8 + 6)
        16#4D ->
            execute_ed_reti(State);

        %% IM 0: 8 T-states total (8 + 0)
        16#46 ->
            execute_ed_im(State, 0);

        %% IM 1: 8 T-states total (8 + 0)
        16#56 ->
            execute_ed_im(State, 1);

        %% IM 2: 8 T-states total (8 + 0)
        16#5E ->
            execute_ed_im(State, 2);

        %% NEG* (undocumented): same as NEG
        Op when Op =:= 16#4C; Op =:= 16#54; Op =:= 16#5C; Op =:= 16#64;
             Op =:= 16#6C; Op =:= 16#74; Op =:= 16#7C ->
            execute_ed_neg(State);

        %% RETN* (undocumented): ED 55, 65, 75 - same as RETN
        Op when Op =:= 16#55; Op =:= 16#65; Op =:= 16#75 ->
            execute_ed_retn(State);

        %% RETI* (undocumented): ED 5D, 6D, 7D - functionally same as RETN
        Op when Op =:= 16#5D; Op =:= 16#6D; Op =:= 16#7D ->
            execute_ed_retn(State);

        %% RRD: 18 T-states total (8 + 10)
        16#67 ->
            execute_ed_rrd(State);

        %% RLD: 18 T-states total (8 + 10)
        16#6F ->
            execute_ed_rld(State);

        %% LD (nn),rr / LD rr,(nn) - 20T total (8 + 12) - specific opcodes only
        Op when Op =:= 16#43; Op =:= 16#4B; Op =:= 16#53; Op =:= 16#5B;
             Op =:= 16#63; Op =:= 16#6B; Op =:= 16#73; Op =:= 16#7B ->
            execute_ed_ld_mem_reg(Op, State);

        %% IN/OUT r,(C) - specific opcodes
        Op when Op =:= 16#40; Op =:= 16#41; Op =:= 16#48; Op =:= 16#49;
             Op =:= 16#50; Op =:= 16#51; Op =:= 16#58; Op =:= 16#59;
             Op =:= 16#60; Op =:= 16#61; Op =:= 16#68; Op =:= 16#69;
             Op =:= 16#70; Op =:= 16#71; Op =:= 16#78; Op =:= 16#79 ->
            execute_ed_in_out(Op, State);

        %% ADC HL,rr / SBC HL,rr / NEG / RETN / RETI / IM
        Op when Op =:= 16#42; Op =:= 16#44; Op =:= 16#45; Op =:= 16#46; Op =:= 16#4A;
             Op =:= 16#4D; Op =:= 16#52; Op =:= 16#56; Op =:= 16#5A; Op =:= 16#5E;
             Op =:= 16#62; Op =:= 16#66; Op =:= 16#6A; Op =:= 16#6E; Op =:= 16#72;
             Op =:= 16#76; Op =:= 16#7A; Op =:= 16#7E ->
            execute_ed_adc_sbc_hl(Op, State);

        %% Block transfer/search/I/O - 0xA0-0xAF, 0xB0-0xBF
        Op when Op >= 16#A0, Op =< 16#AF ->
            execute_ed_block(Op, State);
        Op when Op >= 16#B0, Op =< 16#BF ->
            execute_ed_block(Op, State);

        _ ->
            %% General baseline alignment for basic ED instructions (normally 12 cycles total, so add remaining 4)
            z80_cpu_helpers:advance_tstates(State, 4)
    end.

%% --- Individual ED Instruction Implementations ---

%% NEG: A = 0 - A (8 T-states total = 8 base + 0 added)
execute_ed_neg(State) ->
    A = State#cpu_state.a,
    Diff = 0 - A,
    Res = Diff band 16#FF,
    F_S = Res band 16#80,
    F_Z = if Res =:= 0 -> ?FLAG_Z; true -> 0 end,
    F_H = if (A band 16#0F) =/= 0 -> ?FLAG_H; true -> 0 end,
    F_V = if A =:= 16#80 -> ?FLAG_V; true -> 0 end,
    F_N = ?FLAG_N,
    F_C = if A =:= 0 -> 0; true -> ?FLAG_C end,
    F_F3F5 = Res band (?FLAG_F3 bor ?FLAG_F5),
    NewFlags = F_S bor F_Z bor F_H bor F_V bor F_N bor F_C bor F_F3F5,
    State#cpu_state{a = Res, f = NewFlags}.

%% IM 0/1/2: Set interrupt mode (8 T-states total = 8 base + 0 added)
execute_ed_im(State, Mode) ->
    State#cpu_state{im = Mode}.

%% RETI: Return from interrupt (14 T-states total = 8 base + 6 added)
execute_ed_reti(State) ->
    {PC, State1} = z80_cpu_helpers:pop_word(State),
    z80_cpu_helpers:advance_tstates(State1#cpu_state{pc = PC, iff1 = State1#cpu_state.iff2}, 6).

%% RETN: Return from NMI (14 T-states total = 8 base + 6 added)
execute_ed_retn(State) ->
    {PC, State1} = z80_cpu_helpers:pop_word(State),
    z80_cpu_helpers:advance_tstates(State1#cpu_state{pc = PC, iff1 = State1#cpu_state.iff2}, 6).

%% LD I,A (ED 47): 9 T-states total (8 base + 1 added)
execute_ed_ld_i_a(State) ->
    z80_cpu_helpers:advance_tstates(State#cpu_state{i = State#cpu_state.a}, 1).

%% LD R,A (ED 4F): 9 T-states total (8 base + 1 added)
execute_ed_ld_r_a(State) ->
    Val = State#cpu_state.a,
    Val2 = Val band 16#80 bor z80_cpu_helpers:inc_byte(Val band 16#7F) band 16#7F,
    z80_cpu_helpers:advance_tstates(State#cpu_state{r = Val2}, 1).

%% LD A,I (ED 57): 9 T-states total (8 base + 1 added)
execute_ed_ld_a_i(State) ->
    Val = State#cpu_state.i,
    F_S = Val band 16#80,
    F_Z = if Val =:= 0 -> ?FLAG_Z; true -> 0 end,
    F_H = 0,
    F_V = if State#cpu_state.iff2 =/= 0 -> ?FLAG_V; true -> 0 end,
    F_N = 0,
    F_C = State#cpu_state.f band ?FLAG_C,
    F_F3F5 = Val band (?FLAG_F3 bor ?FLAG_F5),
    NewFlags = F_S bor F_Z bor F_H bor F_V bor F_N bor F_C bor F_F3F5,
    z80_cpu_helpers:advance_tstates(State#cpu_state{a = Val, f = NewFlags}, 1).

%% LD A,R (ED 5F): 9 T-states total (8 base + 1 added)
%% NOTE: R is incremented during fetch_opcode (M1 cycle) before execution.
%%       On real Z80, R increments at the END of the instruction, so the value
%%       seen by LD A,R is one less than what our emulator has at this point.
%%       We compensate by decrementing bits 0-6 (bit 7 is not part of the counter).
%%       Flags are based on the compensated value (what actually lands in A).
execute_ed_ld_a_r(State) ->
    Val = State#cpu_state.r,
    CompVal = (Val band 16#80) bor (z80_cpu_helpers:dec_byte(Val band 16#7F) band 16#7F),
    F_S = CompVal band 16#80,
    F_Z = if CompVal =:= 0 -> ?FLAG_Z; true -> 0 end,
    F_H = 0,
    F_V = if State#cpu_state.iff2 =/= 0 -> ?FLAG_V; true -> 0 end,
    F_N = 0,
    F_C = State#cpu_state.f band ?FLAG_C,
    F_F3F5 = CompVal band (?FLAG_F3 bor ?FLAG_F5),
    NewFlags = F_S bor F_Z bor F_H bor F_V bor F_N bor F_C bor F_F3F5,
    z80_cpu_helpers:advance_tstates(State#cpu_state{a = CompVal, f = NewFlags}, 1).

%% RRD: Rotate Right Digit (ED 67) - 18 T-states total (8 base + 10 added)
execute_ed_rrd(State) ->
    Addr = z80_cpu_helpers:pair(State#cpu_state.h, State#cpu_state.l),
    {Byte, State1} = z80_cpu_helpers:read_byte(State, Addr),
    LowNibble = Byte band 16#0F,
    HighNibble = (Byte bsr 4) band 16#0F,
    OldALow = State1#cpu_state.a band 16#0F,
    NewA = (State1#cpu_state.a band 16#F0) bor LowNibble,
    NewMemByte = (OldALow bsl 4) bor HighNibble,
    State2 = z80_cpu_helpers:write_byte(State1, Addr, NewMemByte),
    F_S = NewA band 16#80,
    F_Z = if NewA =:= 0 -> ?FLAG_Z; true -> 0 end,
    F_H = 0,
    F_V = z80_cpu_helpers:parity(NewA),
    F_N = 0,
    F_F3F5 = NewA band (?FLAG_F3 bor ?FLAG_F5),
    NewFlags = (State2#cpu_state.f band ?FLAG_C) bor F_S bor F_Z bor F_H bor F_V bor F_N bor F_F3F5,
    z80_cpu_helpers:advance_tstates(State2#cpu_state{a = NewA, f = NewFlags}, 10).

%% RLD: Rotate Left Digit (ED 6F) - 18 T-states total (8 base + 10 added)
execute_ed_rld(State) ->
    Addr = z80_cpu_helpers:pair(State#cpu_state.h, State#cpu_state.l),
    {Byte, State1} = z80_cpu_helpers:read_byte(State, Addr),
    LowNibble = Byte band 16#0F,
    HighNibble = (Byte bsr 4) band 16#0F,
    OldALow = State1#cpu_state.a band 16#0F,
    NewA = (State1#cpu_state.a band 16#F0) bor HighNibble,
    NewMemByte = (LowNibble bsl 4) bor OldALow,
    State2 = z80_cpu_helpers:write_byte(State1, Addr, NewMemByte),
    F_S = NewA band 16#80,
    F_Z = if NewA =:= 0 -> ?FLAG_Z; true -> 0 end,
    F_H = 0,
    F_V = z80_cpu_helpers:parity(NewA),
    F_N = 0,
    F_F3F5 = NewA band (?FLAG_F3 bor ?FLAG_F5),
    NewFlags = (State2#cpu_state.f band ?FLAG_C) bor F_S bor F_Z bor F_H bor F_V bor F_N bor F_F3F5,
    z80_cpu_helpers:advance_tstates(State2#cpu_state{a = NewA, f = NewFlags}, 10).

%% ADC HL, rr (ED 4A, 5A, 6A, 7A) - 15 T-states total (8 base + 7 added)
execute_ed_adc_hl_rr(State, RegPair) ->
    HL = z80_cpu_helpers:pair(State#cpu_state.h, State#cpu_state.l),
    RR = z80_cpu_helpers:get_reg_pair(RegPair, State),
    Carry = State#cpu_state.f band ?FLAG_C,
    Res = HL + RR + Carry,
    NewVal = Res band 16#FFFF,
    F_S = if (NewVal band 16#8000) =/= 0 -> ?FLAG_S; true -> 0 end,
    F_Z = if NewVal =:= 0 -> ?FLAG_Z; true -> 0 end,
    F_H = if ((HL band 16#FFF) + (RR band 16#FFF) + Carry) > 16#FFF -> ?FLAG_H; true -> 0 end,
    F_V = if ((HL bxor NewVal) band (RR bxor NewVal) band 16#8000) =/= 0 -> ?FLAG_V; true -> 0 end,
    F_N = 0,
    F_C = if Res > 16#FFFF -> ?FLAG_C; true -> 0 end,
    F_F3F5 = (NewVal bsr 8) band (?FLAG_F3 bor ?FLAG_F5),
    NewFlags = F_S bor F_Z bor F_H bor F_V bor F_N bor F_C bor F_F3F5,
    State1 = State#cpu_state{
        h = (NewVal bsr 8) band 16#FF,
        l = NewVal band 16#FF,
        f = NewFlags
    },
    z80_cpu_helpers:advance_tstates(State1, 7).

%% SBC HL, rr (ED 42, 52, 62, 72) - 15 T-states total (8 base + 7 added)
execute_ed_sbc_hl_rr(State, RegPair) ->
    HL = z80_cpu_helpers:pair(State#cpu_state.h, State#cpu_state.l),
    RR = z80_cpu_helpers:get_reg_pair(RegPair, State),
    Carry = State#cpu_state.f band ?FLAG_C,
    Res = HL - RR - Carry,
    NewVal = Res band 16#FFFF,
    F_S = if (NewVal band 16#8000) =/= 0 -> ?FLAG_S; true -> 0 end,
    F_Z = if NewVal =:= 0 -> ?FLAG_Z; true -> 0 end,
    F_H = if ((HL band 16#FFF) - (RR band 16#FFF) - Carry) < 0 -> ?FLAG_H; true -> 0 end,
    F_V = if ((HL bxor NewVal) band (HL bxor RR) band 16#8000) =/= 0 -> ?FLAG_V; true -> 0 end,
    F_N = ?FLAG_N,
    F_C = if Res < 0 -> ?FLAG_C; true -> 0 end,
    F_F3F5 = (NewVal bsr 8) band (?FLAG_F3 bor ?FLAG_F5),
    NewFlags = F_S bor F_Z bor F_H bor F_V bor F_N bor F_C bor F_F3F5,
    State1 = State#cpu_state{
        h = (NewVal bsr 8) band 16#FF,
        l = NewVal band 16#FF,
        f = NewFlags
    },
    z80_cpu_helpers:advance_tstates(State1, 7).

%% LD (nn), rr / LD rr, (nn) dispatcher (0x40-0x7F range)
execute_ed_ld_mem_reg(Opcode, State) ->
    case Opcode of
        16#43 -> execute_ld_mem_nn_rr(State, bc);   %% LD (nn),BC
        16#4B -> execute_ld_rr_mem_nn(State, bc);   %% LD BC,(nn)
        16#53 -> execute_ld_mem_nn_rr(State, de);   %% LD (nn),DE
        16#5B -> execute_ld_rr_mem_nn(State, de);   %% LD DE,(nn)
        16#63 -> execute_ld_mem_nn_rr(State, hl);   %% LD (nn),HL
        16#6B -> execute_ld_rr_mem_nn(State, hl);   %% LD HL,(nn)
        16#73 -> execute_ld_mem_nn_rr(State, sp);   %% LD (nn),SP
        16#7B -> execute_ld_rr_mem_nn(State, sp);   %% LD SP,(nn)
        _ ->
            z80_cpu_helpers:advance_tstates(State, 4)
    end.

%% LD (nn), rr - 20 T-states total (8 base + 6 fetch + 6 mem write)
execute_ld_mem_nn_rr(State, RegPair) ->
    {Addr, State1} = z80_cpu_helpers:fetch_word(State),
    Val = z80_cpu_helpers:get_reg_pair(RegPair, State1),
    State2 = z80_cpu_helpers:write_word(State1, Addr, Val),
    z80_cpu_helpers:advance_tstates(State2, 6).

%% LD rr, (nn) - 20 T-states total (8 base + 6 fetch + 6 mem read)
execute_ld_rr_mem_nn(State, RegPair) ->
    {Addr, State1} = z80_cpu_helpers:fetch_word(State),
    {Val, State2} = z80_cpu_helpers:read_word(State1, Addr),
    State3 = z80_cpu_helpers:set_reg_pair(RegPair, Val, State2),
    z80_cpu_helpers:advance_tstates(State3, 6).

%% Block transfer/search dispatcher (0xA0-0xAF, 0xB0-0xBF)
execute_ed_block(Opcode, State) ->
    case Opcode of
        16#A0 -> execute_ed_ldi(State);
        16#A1 -> execute_ed_cpi(State);
        16#A2 -> execute_ed_ini(State);
        16#A3 -> execute_ed_outi(State);
        16#A8 -> execute_ed_ldd(State);
        16#A9 -> execute_ed_cpd(State);
        16#AA -> execute_ed_ind(State);
        16#AB -> execute_ed_outd(State);
        16#B0 -> execute_ed_ldir(State);
        16#B1 -> execute_ed_cpir(State);
        16#B2 -> execute_ed_inir(State);
        16#B3 -> execute_ed_otir(State);
        16#B8 -> execute_ed_lddr(State);
        16#B9 -> execute_ed_cpdr(State);
        16#BA -> execute_ed_indr(State);
        16#BB -> execute_ed_otdr(State);
        _ -> z80_cpu_helpers:advance_tstates(State, 4)
    end.

%% Block Transfer: LDI/LDD/LDIR/LDDR
execute_ed_ldi(State) -> execute_ldi(State, false).
execute_ed_ldir(State) -> execute_ldir(State).
execute_ed_ldd(State) -> execute_ldd(State, false).
execute_ed_lddr(State) -> execute_lddr(State).

%% LDI: single iteration (16 T-states total = 8 base + 8)
execute_ldi(State, _Repeat) ->
    HL = z80_cpu_helpers:pair(State#cpu_state.h, State#cpu_state.l),
    DE = z80_cpu_helpers:pair(State#cpu_state.d, State#cpu_state.e),
    BC = z80_cpu_helpers:pair(State#cpu_state.b, State#cpu_state.c),
    {Byte, State1} = z80_cpu_helpers:read_byte(State, HL),
    State2 = z80_cpu_helpers:write_byte(State1, DE, Byte),
    NewHL = (HL + 1) band 16#FFFF,
    NewDE = (DE + 1) band 16#FFFF,
    NewBC = (BC - 1) band 16#FFFF,
    V = (Byte + State2#cpu_state.a) band 16#FF,
    OldF = State#cpu_state.f band (?FLAG_C bor ?FLAG_Z bor ?FLAG_S),
    F_PV = if NewBC =:= 0 -> 0; true -> ?FLAG_V end,
    F_F3 = if V band 16#08 =/= 0 -> ?FLAG_F3; true -> 0 end,
    F_F5 = if V band 16#02 =/= 0 -> ?FLAG_F5; true -> 0 end,
    NewFlags = OldF bor F_PV bor F_F3 bor F_F5,
    State3 = State2#cpu_state{
        h = (NewHL bsr 8) band 16#FF, l = (NewHL band 16#FF),
        d = (NewDE bsr 8) band 16#FF, e = (NewDE band 16#FF),
        b = (NewBC bsr 8) band 16#FF, c = (NewBC band 16#FF),
        f = NewFlags
    },
    z80_cpu_helpers:advance_tstates(State3, 8).

%% LDIR: single iteration, repeat by PC-=2 if BC≠0
%% Hardware pre-check: if BC=0 AND PV=0, skip entirely (NOP behavior).
execute_ldir(State) ->
    BC = z80_cpu_helpers:pair(State#cpu_state.b, State#cpu_state.c),
    PV = State#cpu_state.f band ?FLAG_V,
    case BC =:= 0 andalso PV =:= 0 of
        true ->
            %% BC=0, PV=0: instruction terminates immediately, no iteration
            z80_cpu_helpers:advance_tstates(State, 8);
        false ->
            HL = z80_cpu_helpers:pair(State#cpu_state.h, State#cpu_state.l),
            DE = z80_cpu_helpers:pair(State#cpu_state.d, State#cpu_state.e),
            {Byte, State1} = z80_cpu_helpers:read_byte(State, HL),
            State2 = z80_cpu_helpers:write_byte(State1, DE, Byte),
            NewHL = (HL + 1) band 16#FFFF,
            NewDE = (DE + 1) band 16#FFFF,
            NewBC = (BC - 1) band 16#FFFF,
            V = (Byte + State2#cpu_state.a) band 16#FF,
            OldF = State#cpu_state.f band (?FLAG_C bor ?FLAG_Z bor ?FLAG_S),
            F_PV = if NewBC =:= 0 -> 0; true -> ?FLAG_V end,
            F_F3 = if V band 16#08 =/= 0 -> ?FLAG_F3; true -> 0 end,
            F_F5 = if V band 16#02 =/= 0 -> ?FLAG_F5; true -> 0 end,
            NewFlags = OldF bor F_PV bor F_F3 bor F_F5,
            PC = State2#cpu_state.pc,
            NewPC =  PC - 2,       %% Repeat: 21 T-states (PC-2 to re-execute)
            State3 = State2#cpu_state{
                pc = NewPC,
                h = (NewHL bsr 8) band 16#FF, l = (NewHL band 16#FF),
                d = (NewDE bsr 8) band 16#FF, e = (NewDE band 16#FF),
                b = (NewBC bsr 8) band 16#FF, c = (NewBC band 16#FF),
                f = NewFlags
            },
            z80_cpu_helpers:advance_tstates(State3, 13)
    end.

%% LDD: single iteration (16 T-states total = 8 base + 8)
execute_ldd(State, _Repeat) ->
    HL = z80_cpu_helpers:pair(State#cpu_state.h, State#cpu_state.l),
    DE = z80_cpu_helpers:pair(State#cpu_state.d, State#cpu_state.e),
    BC = z80_cpu_helpers:pair(State#cpu_state.b, State#cpu_state.c),
    {Byte, State1} = z80_cpu_helpers:read_byte(State, HL),
    State2 = z80_cpu_helpers:write_byte(State1, DE, Byte),
    NewHL = (HL - 1) band 16#FFFF,
    NewDE = (DE - 1) band 16#FFFF,
    NewBC = (BC - 1) band 16#FFFF,
    V = (Byte + State2#cpu_state.a) band 16#FF,
    OldF = State#cpu_state.f band (?FLAG_C bor ?FLAG_Z bor ?FLAG_S),
    F_PV = if NewBC =:= 0 -> 0; true -> ?FLAG_V end,
    F_F3 = if V band 16#08 =/= 0 -> ?FLAG_F3; true -> 0 end,
    F_F5 = if V band 16#02 =/= 0 -> ?FLAG_F5; true -> 0 end,
    NewFlags = OldF bor F_PV bor F_F3 bor F_F5,
    State3 = State2#cpu_state{
        h = (NewHL bsr 8) band 16#FF, l = (NewHL band 16#FF),
        d = (NewDE bsr 8) band 16#FF, e = (NewDE band 16#FF),
        b = (NewBC bsr 8) band 16#FF, c = (NewBC band 16#FF),
        f = NewFlags
    },
    z80_cpu_helpers:advance_tstates(State3, 8).

%% LDDR: single iteration, repeat by PC-=2 if BC≠0
%% Hardware pre-check: if BC=0 AND PV=0, skip entirely (NOP behavior).
execute_lddr(State) ->
    BC = z80_cpu_helpers:pair(State#cpu_state.b, State#cpu_state.c),
    PV = State#cpu_state.f band ?FLAG_V,
    case BC =:= 0 andalso PV =:= 0 of
        true ->
            z80_cpu_helpers:advance_tstates(State, 8);
        false ->
            HL = z80_cpu_helpers:pair(State#cpu_state.h, State#cpu_state.l),
            DE = z80_cpu_helpers:pair(State#cpu_state.d, State#cpu_state.e),
            {Byte, State1} = z80_cpu_helpers:read_byte(State, HL),
            State2 = z80_cpu_helpers:write_byte(State1, DE, Byte),
            NewHL = (HL - 1) band 16#FFFF,
            NewDE = (DE - 1) band 16#FFFF,
            NewBC = (BC - 1) band 16#FFFF,
            V = (Byte + State2#cpu_state.a) band 16#FF,
            OldF = State#cpu_state.f band (?FLAG_C bor ?FLAG_Z bor ?FLAG_S),
            F_PV = if NewBC =:= 0 -> 0; true -> ?FLAG_V end,
            F_F3 = if V band 16#08 =/= 0 -> ?FLAG_F3; true -> 0 end,
            F_F5 = if V band 16#02 =/= 0 -> ?FLAG_F5; true -> 0 end,
            NewFlags = OldF bor F_PV bor F_F3 bor F_F5,
            PC = State2#cpu_state.pc,
            NewPC = case NewBC of
                0 -> PC;
                _ -> PC - 2
            end,
            TAdd = case NewBC of 0 -> 8; _ -> 13 end,
            State3 = State2#cpu_state{
                pc = NewPC,
                h = (NewHL bsr 8) band 16#FF, l = (NewHL band 16#FF),
                d = (NewDE bsr 8) band 16#FF, e = (NewDE band 16#FF),
                b = (NewBC bsr 8) band 16#FF, c = (NewBC band 16#FF),
                f = NewFlags
            },
            z80_cpu_helpers:advance_tstates(State3, TAdd)
    end.

%% Block Search: CPI/CPD/CPIR/CPDR

%% CPI: Compare A with (HL), increment HL, decrement BC
execute_ed_cpi(State) ->
    HL = z80_cpu_helpers:pair(State#cpu_state.h, State#cpu_state.l),
    BC = z80_cpu_helpers:pair(State#cpu_state.b, State#cpu_state.c),
    {Byte, State1} = z80_cpu_helpers:read_byte(State, HL),
    A = State#cpu_state.a,
    Diff = (A - Byte) band 16#FF,
    HFlag = case (A band 16#0F) < (Byte band 16#0F) of true -> 1; false -> 0 end,
    Tmp = (A - Byte - HFlag) band 16#FF,
    NewHL = (HL + 1) band 16#FFFF,
    NewBC = (BC - 1) band 16#FFFF,
    OldF = State#cpu_state.f band ?FLAG_C,
    F_S = Diff band 16#80,
    F_Z = if Diff =:= 0 -> ?FLAG_Z; true -> 0 end,
    F_H = if HFlag =:= 1 -> ?FLAG_H; true -> 0 end,
    F_PV = if NewBC =:= 0 -> 0; true -> ?FLAG_V end,
    F_N = ?FLAG_N,
    F_F3 = if Tmp band 16#08 =/= 0 -> ?FLAG_F3; true -> 0 end,
    F_F5 = if Tmp band 16#02 =/= 0 -> ?FLAG_F5; true -> 0 end,
    NewFlags = OldF bor F_S bor F_Z bor F_H bor F_PV bor F_N bor F_F3 bor F_F5,
    State2 = State1#cpu_state{
        h = (NewHL bsr 8) band 16#FF, l = (NewHL band 16#FF),
        b = (NewBC bsr 8) band 16#FF, c = (NewBC band 16#FF),
        f = NewFlags
    },
    z80_cpu_helpers:advance_tstates(State2, 8).

%% CPIR: Compare A with (HL), repeat if no match and BC≠0
%% Hardware pre-check: if BC=0 AND PV=0, skip entirely (NOP behavior).
execute_ed_cpir(State) ->
    BC = z80_cpu_helpers:pair(State#cpu_state.b, State#cpu_state.c),
    PV = State#cpu_state.f band ?FLAG_V,
    case BC =:= 0 andalso PV =:= 0 of
        true ->
            z80_cpu_helpers:advance_tstates(State, 8);
        false ->
            HL = z80_cpu_helpers:pair(State#cpu_state.h, State#cpu_state.l),
            {Byte, State1} = z80_cpu_helpers:read_byte(State, HL),
            A = State#cpu_state.a,
            Diff = (A - Byte) band 16#FF,
            HFlag = case (A band 16#0F) < (Byte band 16#0F) of true -> 1; false -> 0 end,
            Tmp = (A - Byte - HFlag) band 16#FF,
            NewHL = (HL + 1) band 16#FFFF,
            NewBC = (BC - 1) band 16#FFFF,
            Match = (Diff =:= 0),
            OldF = State#cpu_state.f band ?FLAG_C,
            F_S = Diff band 16#80,
            F_Z = if Diff =:= 0 -> ?FLAG_Z; true -> 0 end,
            F_H = if HFlag =:= 1 -> ?FLAG_H; true -> 0 end,
            F_PV = if NewBC =:= 0 -> 0; true -> ?FLAG_V end,
            F_N = ?FLAG_N,
            F_F3 = if Tmp band 16#08 =/= 0 -> ?FLAG_F3; true -> 0 end,
            F_F5 = if Tmp band 16#02 =/= 0 -> ?FLAG_F5; true -> 0 end,
            NewFlags = OldF bor F_S bor F_Z bor F_H bor F_PV bor F_N bor F_F3 bor F_F5,
            PC = State1#cpu_state.pc,
            NewPC = case Match orelse NewBC =:= 0 of
                true -> PC;
                _ -> PC - 2
            end,
            TAdd = case Match orelse NewBC =:= 0 of true -> 8; _ -> 13 end,
            State2 = State1#cpu_state{
                pc = NewPC,
                h = (NewHL bsr 8) band 16#FF, l = (NewHL band 16#FF),
                b = (NewBC bsr 8) band 16#FF, c = (NewBC band 16#FF),
                f = NewFlags
            },
            z80_cpu_helpers:advance_tstates(State2, TAdd)
    end.

%% CPD: Compare A with (HL), decrement HL, decrement BC
execute_ed_cpd(State) ->
    HL = z80_cpu_helpers:pair(State#cpu_state.h, State#cpu_state.l),
    BC = z80_cpu_helpers:pair(State#cpu_state.b, State#cpu_state.c),
    {Byte, State1} = z80_cpu_helpers:read_byte(State, HL),
    A = State#cpu_state.a,
    Diff = (A - Byte) band 16#FF,
    HFlag = case (A band 16#0F) < (Byte band 16#0F) of true -> 1; false -> 0 end,
    Tmp = (A - Byte - HFlag) band 16#FF,
    NewHL = (HL - 1) band 16#FFFF,
    NewBC = (BC - 1) band 16#FFFF,
    OldF = State#cpu_state.f band ?FLAG_C,
    F_S = Diff band 16#80,
    F_Z = if Diff =:= 0 -> ?FLAG_Z; true -> 0 end,
    F_H = if HFlag =:= 1 -> ?FLAG_H; true -> 0 end,
    F_PV = if NewBC =:= 0 -> 0; true -> ?FLAG_V end,
    F_N = ?FLAG_N,
    F_F3 = if Tmp band 16#08 =/= 0 -> ?FLAG_F3; true -> 0 end,
    F_F5 = if Tmp band 16#02 =/= 0 -> ?FLAG_F5; true -> 0 end,
    NewFlags = OldF bor F_S bor F_Z bor F_H bor F_PV bor F_N bor F_F3 bor F_F5,
    State2 = State1#cpu_state{
        h = (NewHL bsr 8) band 16#FF, l = (NewHL band 16#FF),
        b = (NewBC bsr 8) band 16#FF, c = (NewBC band 16#FF),
        f = NewFlags
    },
    z80_cpu_helpers:advance_tstates(State2, 8).

%% CPDR: Compare A with (HL), repeat if no match and BC≠0
%% Hardware pre-check: if BC=0 AND PV=0, skip entirely (NOP behavior).
execute_ed_cpdr(State) ->
    BC = z80_cpu_helpers:pair(State#cpu_state.b, State#cpu_state.c),
    PV = State#cpu_state.f band ?FLAG_V,
    case BC =:= 0 andalso PV =:= 0 of
        true ->
            z80_cpu_helpers:advance_tstates(State, 8);
        false ->
            HL = z80_cpu_helpers:pair(State#cpu_state.h, State#cpu_state.l),
            {Byte, State1} = z80_cpu_helpers:read_byte(State, HL),
            A = State#cpu_state.a,
            Diff = (A - Byte) band 16#FF,
            HFlag = case (A band 16#0F) < (Byte band 16#0F) of true -> 1; false -> 0 end,
            Tmp = (A - Byte - HFlag) band 16#FF,
            NewHL = (HL - 1) band 16#FFFF,
            NewBC = (BC - 1) band 16#FFFF,
            Match = (Diff =:= 0),
            OldF = State#cpu_state.f band ?FLAG_C,
            F_S = Diff band 16#80,
            F_Z = if Diff =:= 0 -> ?FLAG_Z; true -> 0 end,
            F_H = if HFlag =:= 1 -> ?FLAG_H; true -> 0 end,
            F_PV = if NewBC =:= 0 -> 0; true -> ?FLAG_V end,
            F_N = ?FLAG_N,
            F_F3 = if Tmp band 16#08 =/= 0 -> ?FLAG_F3; true -> 0 end,
            F_F5 = if Tmp band 16#02 =/= 0 -> ?FLAG_F5; true -> 0 end,
            NewFlags = OldF bor F_S bor F_Z bor F_H bor F_PV bor F_N bor F_F3 bor F_F5,
            PC = State1#cpu_state.pc,
            NewPC = case Match orelse NewBC =:= 0 of
                true -> PC;
                _ -> PC - 2
            end,
            TAdd = case Match orelse NewBC =:= 0 of true -> 8; _ -> 13 end,
            State2 = State1#cpu_state{
                pc = NewPC,
                h = (NewHL bsr 8) band 16#FF, l = (NewHL band 16#FF),
                b = (NewBC bsr 8) band 16#FF, c = (NewBC band 16#FF),
                f = NewFlags
            },
            z80_cpu_helpers:advance_tstates(State2, TAdd)
    end.

%% Undocumented flag helpers for block instructions

%% Flags for LDI/LDD/LDIR/LDDR: V from (Byte+A)&0xFF, F3/F5 from that temp value.
undoc_flags_transfer(Byte, A, OldFlags) ->
    V = (Byte + A) band 16#FF,
    F_F3 = if V band 16#08 =/= 0 -> ?FLAG_F3; true -> 0 end,
    F_F5 = if V band 16#02 =/= 0 -> ?FLAG_F5; true -> 0 end,
    OldFlags bor F_F3 bor F_F5.

%% Flags for OUTI/OUTD/OTIR/OTDR: Temp = Val + ((C±1)&0xFF)
undoc_flags_out(Val, C, Inc) ->
    K = case Inc of
        true  -> (C + 1) band 16#FF;
        false -> (C - 1) band 16#FF
    end,
    Temp = Val + K,
    Temp8 = Temp band 16#FF,
    F_S = Temp8 band 16#80,
    F_H = if ((Val band 16#0F) + (K band 16#0F)) band 16#10 =/= 0 -> ?FLAG_H; true -> 0 end,
    F_V = z80_cpu_helpers:parity(Temp8),
    F_N = Val band 16#80,
    F_C = if Temp > 16#FF -> ?FLAG_C; true -> 0 end,
    F3F5 = Temp8 band (?FLAG_F3 bor ?FLAG_F5),
    F_S bor F_H bor F_V bor F_N bor F_C bor F3F5.

%% Flags for INI/IND/INIR/INDR: Temp = Val + ((C±1)&0xFF)
undoc_flags_in(Val, C, Inc) ->
    K = case Inc of
        true  -> (C + 1) band 16#FF;
        false -> (C - 1) band 16#FF
    end,
    Temp = Val + K,
    Temp8 = Temp band 16#FF,
    F_S = Temp8 band 16#80,
    F_H = if ((Val band 16#0F) + (K band 16#0F)) band 16#10 =/= 0 -> ?FLAG_H; true -> 0 end,
    F_V = z80_cpu_helpers:parity(Temp8),
    F_N = Val band 16#80,
    F_C = if Temp > 16#FF -> ?FLAG_C; true -> 0 end,
    F3F5 = Temp8 band (?FLAG_F3 bor ?FLAG_F5),
    F_S bor F_H bor F_V bor F_N bor F_C bor F3F5.

%% Block I/O: INI/IND/INIR/INDR — single iteration per step, repeat by PC-=2
execute_ed_ini(State) -> execute_ini(State).
execute_ed_inir(State) -> execute_inir(State).
execute_ed_ind(State) -> execute_ind(State).
execute_ed_indr(State) -> execute_indr(State).

%% INI: single iteration, 16 T-states (8 base + 8)
execute_ini(State) ->
    HL = z80_cpu_helpers:pair(State#cpu_state.h, State#cpu_state.l),
    Port = (State#cpu_state.b bsl 8) bor State#cpu_state.c,
    PortReadFun = State#cpu_state.port_read_fun,
    TState = State#cpu_state.t_states,
    ExtCtx = State#cpu_state.ext_context,
    {Val, NewExtCtx} = PortReadFun(ExtCtx, TState, Port),
    Val8 = Val band 16#FF,
    State1 = z80_cpu_helpers:write_byte(State#cpu_state{ext_context = NewExtCtx}, HL, Val8),
    NewB = (State#cpu_state.b - 1) band 16#FF,
    NewHL = (HL + 1) band 16#FFFF,
    UndocF = undoc_flags_in(Val8, State#cpu_state.c, true),
    F_Z = if NewB =:= 0 -> ?FLAG_Z; true -> 0 end,
    NewFlags = UndocF bor F_Z,
    State2 = State1#cpu_state{
        b = NewB, h = (NewHL bsr 8) band 16#FF, l = (NewHL band 16#FF), f = NewFlags
    },
    z80_cpu_helpers:advance_tstates(State2, 8).

%% INIR: single iteration, repeat by PC-=2 if B≠0
execute_inir(State) ->
    B = State#cpu_state.b,
    PV = State#cpu_state.f band ?FLAG_V,
    case B =:= 0 andalso PV =:= 0 of
        true ->
            z80_cpu_helpers:advance_tstates(State, 8);
        false ->
            HL = z80_cpu_helpers:pair(State#cpu_state.h, State#cpu_state.l),
            Port = (B bsl 8) bor State#cpu_state.c,
            PortReadFun = State#cpu_state.port_read_fun,
            TState = State#cpu_state.t_states,
            ExtCtx = State#cpu_state.ext_context,
            {Val, NewExtCtx} = PortReadFun(ExtCtx, TState, Port),
            Val8 = Val band 16#FF,
            State1 = z80_cpu_helpers:write_byte(State#cpu_state{ext_context = NewExtCtx}, HL, Val8),
            NewB = (B - 1) band 16#FF,
            NewHL = (HL + 1) band 16#FFFF,
            UndocF = undoc_flags_in(Val8, State#cpu_state.c, true),
            F_Z = if NewB =:= 0 -> ?FLAG_Z; true -> 0 end,
            NewFlags = UndocF bor F_Z,
            PC = State1#cpu_state.pc,
            {NewPC, IterT} = case NewB of
                0 -> {PC, 8};          %% Terminate: 8+8=16 T-states
                _ -> {PC - 2, 13}      %% Repeat: 8+13=21 T-states
            end,
            State2 = State1#cpu_state{
                pc = NewPC,
                b = NewB, h = (NewHL bsr 8) band 16#FF, l = (NewHL band 16#FF), f = NewFlags
            },
            z80_cpu_helpers:advance_tstates(State2, IterT)
    end.

%% IND: single iteration, 16 T-states (8 base + 8)
execute_ind(State) ->
    HL = z80_cpu_helpers:pair(State#cpu_state.h, State#cpu_state.l),
    Port = (State#cpu_state.b bsl 8) bor State#cpu_state.c,
    PortReadFun = State#cpu_state.port_read_fun,
    TState = State#cpu_state.t_states,
    ExtCtx = State#cpu_state.ext_context,
    {Val, NewExtCtx} = PortReadFun(ExtCtx, TState, Port),
    Val8 = Val band 16#FF,
    State1 = z80_cpu_helpers:write_byte(State#cpu_state{ext_context = NewExtCtx}, HL, Val8),
    NewB = (State#cpu_state.b - 1) band 16#FF,
    NewHL = (HL - 1) band 16#FFFF,
    UndocF = undoc_flags_in(Val8, State#cpu_state.c, false),
    F_Z = if NewB =:= 0 -> ?FLAG_Z; true -> 0 end,
    NewFlags = UndocF bor F_Z,
    State2 = State1#cpu_state{
        b = NewB, h = (NewHL bsr 8) band 16#FF, l = (NewHL band 16#FF), f = NewFlags
    },
    z80_cpu_helpers:advance_tstates(State2, 8).

%% INDR: single iteration, repeat by PC-=2 if B≠0
execute_indr(State) ->
    B = State#cpu_state.b,
    PV = State#cpu_state.f band ?FLAG_V,
    case B =:= 0 andalso PV =:= 0 of
        true ->
            z80_cpu_helpers:advance_tstates(State, 8);
        false ->
            HL = z80_cpu_helpers:pair(State#cpu_state.h, State#cpu_state.l),
            Port = (B bsl 8) bor State#cpu_state.c,
            PortReadFun = State#cpu_state.port_read_fun,
            TState = State#cpu_state.t_states,
            ExtCtx = State#cpu_state.ext_context,
            {Val, NewExtCtx} = PortReadFun(ExtCtx, TState, Port),
            Val8 = Val band 16#FF,
            State1 = z80_cpu_helpers:write_byte(State#cpu_state{ext_context = NewExtCtx}, HL, Val8),
            NewB = (B - 1) band 16#FF,
            NewHL = (HL - 1) band 16#FFFF,
            UndocF = undoc_flags_in(Val8, State#cpu_state.c, false),
            F_Z = if NewB =:= 0 -> ?FLAG_Z; true -> 0 end,
            NewFlags = UndocF bor F_Z,
            PC = State1#cpu_state.pc,
            {NewPC, IterT} = case NewB of
                0 -> {PC, 8};
                _ -> {PC - 2, 13}
            end,
            State2 = State1#cpu_state{
                pc = NewPC,
                b = NewB, h = (NewHL bsr 8) band 16#FF, l = (NewHL band 16#FF), f = NewFlags
            },
            z80_cpu_helpers:advance_tstates(State2, IterT)
    end.

%% Block I/O: OUTI/OUTD/OTIR/OTDR — single iteration per step, repeat by PC-=2
execute_ed_outi(State) -> execute_outi(State).
execute_ed_otir(State) -> execute_otir(State).
execute_ed_outd(State) -> execute_outd(State).
execute_ed_otdr(State) -> execute_otdr(State).

%% OUTI: single iteration, 16 T-states (8 base + 8)
execute_outi(State) ->
    HL = z80_cpu_helpers:pair(State#cpu_state.h, State#cpu_state.l),
    Port = (State#cpu_state.b bsl 8) bor State#cpu_state.c,
    {Val, State1} = z80_cpu_helpers:read_byte(State, HL),
    PortWriteFun = State#cpu_state.port_write_fun,
    TState = State#cpu_state.t_states,
    NewB = (State#cpu_state.b - 1) band 16#FF,
    NewHL = (HL + 1) band 16#FFFF,
    ExtCtx = State1#cpu_state.ext_context,
    NewExtCtx = PortWriteFun(ExtCtx, TState, Port, Val),
    UndocF = undoc_flags_out(Val, State#cpu_state.c, true),
    F_Z = if NewB =:= 0 -> ?FLAG_Z; true -> 0 end,
    NewFlags = UndocF bor F_Z,
    State2 = State1#cpu_state{
        ext_context = NewExtCtx,
        b = NewB, h = (NewHL bsr 8) band 16#FF, l = (NewHL band 16#FF), f = NewFlags
    },
    z80_cpu_helpers:advance_tstates(State2, 8).

%% OTIR: single iteration, repeat by PC-=2 if B≠0
execute_otir(State) ->
    B = State#cpu_state.b,
    PV = State#cpu_state.f band ?FLAG_V,
    case B =:= 0 andalso PV =:= 0 of
        true ->
            z80_cpu_helpers:advance_tstates(State, 8);
        false ->
            HL = z80_cpu_helpers:pair(State#cpu_state.h, State#cpu_state.l),
            Port = (B bsl 8) bor State#cpu_state.c,
            {Val, State1} = z80_cpu_helpers:read_byte(State, HL),
            PortWriteFun = State#cpu_state.port_write_fun,
            TState = State#cpu_state.t_states,
            NewB = (B - 1) band 16#FF,
            NewHL = (HL + 1) band 16#FFFF,
            ExtCtx = State1#cpu_state.ext_context,
            NewExtCtx = PortWriteFun(ExtCtx, TState, Port, Val),
            UndocF = undoc_flags_out(Val, State#cpu_state.c, true),
            F_Z = if NewB =:= 0 -> ?FLAG_Z; true -> 0 end,
            NewFlags = UndocF bor F_Z,
            PC = State1#cpu_state.pc,
            {NewPC, IterT} = case NewB of
                0 -> {PC, 8};
                _ -> {PC - 2, 13}
            end,
            State2 = State1#cpu_state{
                ext_context = NewExtCtx,
                pc = NewPC,
                b = NewB, h = (NewHL bsr 8) band 16#FF, l = (NewHL band 16#FF), f = NewFlags
            },
            z80_cpu_helpers:advance_tstates(State2, IterT)
    end.

%% OUTD: single iteration, 16 T-states (8 base + 8)
execute_outd(State) ->
    HL = z80_cpu_helpers:pair(State#cpu_state.h, State#cpu_state.l),
    Port = (State#cpu_state.b bsl 8) bor State#cpu_state.c,
    {Val, State1} = z80_cpu_helpers:read_byte(State, HL),
    PortWriteFun = State#cpu_state.port_write_fun,
    TState = State#cpu_state.t_states,
    NewB = (State#cpu_state.b - 1) band 16#FF,
    NewHL = (HL - 1) band 16#FFFF,
    ExtCtx = State1#cpu_state.ext_context,
    NewExtCtx = PortWriteFun(ExtCtx, TState, Port, Val),
    UndocF = undoc_flags_out(Val, State#cpu_state.c, false),
    F_Z = if NewB =:= 0 -> ?FLAG_Z; true -> 0 end,
    NewFlags = UndocF bor F_Z,
    State2 = State1#cpu_state{
        ext_context = NewExtCtx,
        b = NewB, h = (NewHL bsr 8) band 16#FF, l = (NewHL band 16#FF), f = NewFlags
    },
    z80_cpu_helpers:advance_tstates(State2, 8).

%% OTDR: single iteration, repeat by PC-=2 if B≠0
execute_otdr(State) ->
    B = State#cpu_state.b,
    PV = State#cpu_state.f band ?FLAG_V,
    case B =:= 0 andalso PV =:= 0 of
        true ->
            z80_cpu_helpers:advance_tstates(State, 8);
        false ->
            HL = z80_cpu_helpers:pair(State#cpu_state.h, State#cpu_state.l),
            Port = (B bsl 8) bor State#cpu_state.c,
            {Val, State1} = z80_cpu_helpers:read_byte(State, HL),
            PortWriteFun = State#cpu_state.port_write_fun,
            TState = State#cpu_state.t_states,
            NewB = (B - 1) band 16#FF,
            NewHL = (HL - 1) band 16#FFFF,
            ExtCtx = State1#cpu_state.ext_context,
            NewExtCtx = PortWriteFun(ExtCtx, TState, Port, Val),
            UndocF = undoc_flags_out(Val, State#cpu_state.c, false),
            F_Z = if NewB =:= 0 -> ?FLAG_Z; true -> 0 end,
            NewFlags = UndocF bor F_Z,
            PC = State1#cpu_state.pc,
            {NewPC, IterT} = case NewB of
                0 -> {PC, 8};
                _ -> {PC - 2, 13}
            end,
            State2 = State1#cpu_state{
                ext_context = NewExtCtx,
                pc = NewPC,
                b = NewB, h = (NewHL bsr 8) band 16#FF, l = (NewHL band 16#FF), f = NewFlags
            },
            z80_cpu_helpers:advance_tstates(State2, IterT)
    end.

%% IN/OUT r,(C) dispatcher (0x40-0x7F range)
execute_ed_in_out(Opcode, State) ->
    case Opcode of
        %% IN r,(C)
        16#40 -> execute_ed_in_r_c(State, b);
        16#48 -> execute_ed_in_r_c(State, c);
        16#50 -> execute_ed_in_r_c(State, d);
        16#58 -> execute_ed_in_r_c(State, e);
        16#60 -> execute_ed_in_r_c(State, h);
        16#68 -> execute_ed_in_r_c(State, l);
        16#70 -> execute_ed_in_f_c(State);
        16#78 -> execute_ed_in_r_c(State, a);
        %% OUT (C),r
        16#41 -> execute_ed_out_c_r(State, b);
        16#49 -> execute_ed_out_c_r(State, c);
        16#51 -> execute_ed_out_c_r(State, d);
        16#59 -> execute_ed_out_c_r(State, e);
        16#61 -> execute_ed_out_c_r(State, h);
        16#69 -> execute_ed_out_c_r(State, l);
        16#71 -> execute_ed_out_c_0(State);
        16#79 -> execute_ed_out_c_r(State, a);
        _ ->
            z80_cpu_helpers:advance_tstates(State, 4)
    end.

%% IN r,(C): read from port BC, store in r - 12 T-states total (8 base + 4 added)
execute_ed_in_r_c(State, Reg) ->
    Port = (State#cpu_state.b bsl 8) bor State#cpu_state.c,
    PortReadFun = State#cpu_state.port_read_fun,
    TState = State#cpu_state.t_states,
    ExtCtx = State#cpu_state.ext_context,
    {Val, NewExtCtx} = PortReadFun(ExtCtx, TState, Port),
    State1 = z80_cpu_helpers:set_reg_byte(Reg, Val band 16#FF, State#cpu_state{ext_context = NewExtCtx}),
    F_C = State#cpu_state.f band ?FLAG_C,
    F_S = Val band 16#80,
    F_Z = if Val =:= 0 -> ?FLAG_Z; true -> 0 end,
    F_H = 0,
    F_V = z80_cpu_helpers:parity(Val),
    F_N = 0,
    F_F3 = Val band 16#08,
    F_F5 = Val band 16#20,
    NewFlags = F_C bor F_S bor F_Z bor F_H bor F_V bor F_N bor F_F3 bor F_F5,
    z80_cpu_helpers:advance_tstates(State1#cpu_state{f = NewFlags}, 4).

%% IN (C) / IN F,(C): 12 T-states (flags affected, result discarded)
execute_ed_in_f_c(State) ->
    Port = (State#cpu_state.b bsl 8) bor State#cpu_state.c,
    PortReadFun = State#cpu_state.port_read_fun,
    TState = State#cpu_state.t_states,
    ExtCtx = State#cpu_state.ext_context,
    {Val, NewExtCtx} = PortReadFun(ExtCtx, TState, Port),
    F_C = State#cpu_state.f band ?FLAG_C,
    F_S = Val band 16#80,
    F_Z = if Val =:= 0 -> ?FLAG_Z; true -> 0 end,
    F_H = 0,
    F_V = z80_cpu_helpers:parity(Val),
    F_N = 0,
    F_F3 = Val band 16#08,
    F_F5 = Val band 16#20,
    NewFlags = F_C bor F_S bor F_Z bor F_H bor F_V bor F_N bor F_F3 bor F_F5,
    z80_cpu_helpers:advance_tstates(State#cpu_state{f = NewFlags, ext_context = NewExtCtx}, 4).

%% OUT (C),r implementation
execute_ed_out_c_r(State, Reg) ->
    Port = (State#cpu_state.b bsl 8) bor State#cpu_state.c,
    Val = z80_cpu_helpers:get_reg_byte(Reg, State),
    PortWriteFun = State#cpu_state.port_write_fun,
    TState = State#cpu_state.t_states,
    ExtCtx = State#cpu_state.ext_context,
    NewExtCtx = PortWriteFun(ExtCtx, TState, Port, Val),
    z80_cpu_helpers:advance_tstates(State#cpu_state{ext_context = NewExtCtx}, 4).

%% OUT (C),0: 12 T-states total (8 base + 4 added)
execute_ed_out_c_0(State) ->
    Port = (State#cpu_state.b bsl 8) bor State#cpu_state.c,
    PortWriteFun = State#cpu_state.port_write_fun,
    TState = State#cpu_state.t_states,
    ExtCtx = State#cpu_state.ext_context,
    NewExtCtx = PortWriteFun(ExtCtx, TState, Port, 0),
    z80_cpu_helpers:advance_tstates(State#cpu_state{ext_context = NewExtCtx}, 4).

%% ADC HL,rr / SBC HL,rr dispatcher
execute_ed_adc_sbc_hl(Opcode, State) ->
    case Opcode of
        16#42 -> execute_ed_sbc_hl_rr(State, bc);
        16#4A -> execute_ed_adc_hl_rr(State, bc);
        16#52 -> execute_ed_sbc_hl_rr(State, de);
        16#5A -> execute_ed_adc_hl_rr(State, de);
        16#62 -> execute_ed_sbc_hl_rr(State, hl);
        16#6A -> execute_ed_adc_hl_rr(State, hl);
        16#72 -> execute_ed_sbc_hl_rr(State, sp);
        16#7A -> execute_ed_adc_hl_rr(State, sp);
        _ ->
            z80_cpu_helpers:advance_tstates(State, 4)
    end.
