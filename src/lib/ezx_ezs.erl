-module(ezx_ezs).

%% @doc The ezx state container (.ezs) — the emulator's own, fully
%% self-contained snapshot format. One binary carries the whole machine with
%% no reference to any interchange format and no embedded blobs.
%%
%% == File layout ==
%%
%% Multibyte integer fields are always little-endian (least significant byte
%% first) unless explicitly noted otherwise. All sizes are in bytes.
%%
%% === Fixed header (11 bytes) ===
%%
%% ```
%%   Offset  Size  Field
%%   ──────  ────  ─────
%%     0       4   Magic: the four ASCII characters 'E','Z','X','S' (0x45,0x5A,0x58,0x53)
%%     4       1   Format version (currently 1)
%%     5       1   Machine type code:
%%                   0 = '48k'
%%                   1 = '128k'
%%                   2 = 'pentagon_128'
%%                   3 = 'pentagon_512'
%%                   4 = 'pentagon_1024'
%%     6       1   Port #7FFD latch byte (content is meaningful only for
%%                   128K-family machines; stored as-is for every type)
%%     7       1   Port #EFF7, low byte (meaningful on the Pentagon 1024K only;
%%                   stores bit 0 = 1MB mode, bit 3 = all-RAM overlay)
%%     8       1   Port #EFF7, high byte (always 0 on the 1024K; reserved)
%%     9       1   TR-DOS ROM overlay latch: 0 = overlay off, 1 = overlay on
%%   10       1   Border colour (0..7, ULA ink at frame start)
%% ```
%%
%% === CPU register block (30 bytes, offset 11) ===
%%
%% ```
%%   Offset  Size  Field
%%   ──────  ────  ─────
%%    11       1   A   (main accumulator)
%%    12       1   F   (main flags)
%%    13       1   B
%%    14       1   C
%%    15       1   D
%%    16       1   E
%%    17       1   H
%%    18       1   L
%%    19       1   A'  (shadow accumulator)
%%    20       1   F'  (shadow flags)
%%    21       1   B'
%%    22       1   C'
%%    23       1   D'
%%    24       1   E'
%%    25       1   H'
%%    26       1   L'
%%    27       1   I   (interrupt vector register)
%%    28       1   R   (memory refresh counter)
%%    29       1   IX high byte (IXh)
%%    30       1   IX low byte  (IXl)
%%    31       1   IY high byte (IYh)
%%    32       1   IY low byte  (IYl)
%%    33       2   SP — stack pointer, 16-bit little-endian (byte 33 = low, byte 34 = high)
%%    35       2   PC — program counter, 16-bit little-endian (byte 35 = low, byte 36 = high)
%%    37       1   IFF1: 0 = disabled, 1 = enabled
%%    38       1   IFF2: 0 = disabled, 1 = enabled
%%    39       1   IM  — interrupt mode (0, 1, or 2)
%%    40       1   HALT: 0 = running, 1 = halted
%% ```
%%
%% === AY / YM sound chip block (variable, offset 41) ===
%%
%% ```
%%   Offset  Size  Field
%%   ──────  ────  ─────
%%    41       1   Presence marker:
%%                   0x00 = no AY/YM device in this snapshot;
%%                          the block ends here, RAM banks begin at offset 42
%%                   0x01 = device present; followed by the register block below
%%
%%   When 0x01:
%%    42       1   Selected (latched) register index (0..14; registers 14 and
%%                  15 are the I/O ports, stored but not used by the emulator)
%%    43      16   Register values R0..R15, one byte each, in register order
%%                  (total: tone period R0-R5, noise R6, mixer R7,
%%                   amplitude R8-R10, envelope period R11-R13, I/O R14-R15)
%% ```
%%
%% Total AY block size: 1 byte when absent, 18 bytes when present.
%%
%% === RAM banks (tail, immediately after AY block) ===
%%
%% ```
%%   Offset     Size      Field
%%   ──────     ────      ─────
%%    42 or 59   BANK_SIZE × banks_for_type(Type)  raw RAM contents
%%                (42 = 11 + 30 + 1 when AY absent;
%%                 59 = 11 + 30 + 18 when AY present)
%% ```
%%
%%   banks_for_type(Type):
%%     '48k'           → 3 banks  (pages at 0x4000, 0x8000, 0xC000)
%%     '128k'          → 8 banks  (banks 0..7)
%%     'pentagon_128'  → 8 banks  (banks 0..7)
%%     'pentagon_512'  → 32 banks (banks 0..31)
%%     'pentagon_1024' → 64 banks (banks 0..63)
%%
%%   BANK_SIZE = 16384 bytes (16 KiB per bank)
%%
%%   Each bank is a flat dump of its 16384-byte address space.
%%   Banks are written in ascending order: bank 0 first, bank N-1 last.
%% ```
%%
%% === Determining the total file size ===
%%
%% ```
%%   Total = 11 (header)
%%         + 30 (CPU)
%%         + AY block size   (1 if absent, 18 if present)
%%         + 16384 × banks_for_type(Type)
%%
%%   Example — pentagon_512 with AY present:
%%     11 + 30 + 18 + 16384 × 32 = 524 347 bytes
%% ```
%%
%% == Pure format module ==
%%
%% Like ezx_z80, this module has no machine knowledge: compose/1 and parse/1
%% speak plain maps. The machine bridge lives in ezx_saves
%% (to_ezs_container/1 + apply_container/2).

-export([compose/1, parse/1, is_container/1, banks_for_type/1]).

-define(MAGIC, <<"EZXS">>).
-define(VERSION, 1).
-define(HEADER_SIZE, 11).
-define(CPU_SIZE, 30).
-define(AY_ABSENT_SIZE, 1).
-define(AY_PRESENT_SIZE, 18).  %% presence byte + selected register + 16 regs
-define(BANK_SIZE, 16384).

-type type() :: '48k' | '128k' | 'pentagon_128' | 'pentagon_512' | 'pentagon_1024'.
-type cpu_map() :: #{
    a => byte(), f => byte(), b => byte(), c => byte(),
    d => byte(), e => byte(), h => byte(), l => byte(),
    a_alt => byte(), f_alt => byte(), b_alt => byte(), c_alt => byte(),
    d_alt => byte(), e_alt => byte(), h_alt => byte(), l_alt => byte(),
    i => byte(), r => byte(),
    ixh => byte(), ixl => byte(), iyh => byte(), iyl => byte(),
    sp => non_neg_integer(), pc => non_neg_integer(),
    iff1 => 0 | 1, iff2 => 0 | 1, im => 0 | 1 | 2, halted => 0 | 1
}.
-type ay_map() :: #{selected => byte(), regs => binary()}.
-type container() :: #{
    type => type(),
    p7ffd => byte(),
    eff7 => non_neg_integer(),
    dos_rom => 0 | 1,
    border => byte(),
    cpu => cpu_map(),
    ay => undefined | ay_map(),
    banks => [binary()]
}.

-export_type([container/0, type/0]).

%% @doc Encode a container map (see parse/1 for the fields). banks holds the
%% raw 16KB memory blocks, lowest bank first; their count must match the
%% machine type (compose does not enforce it, parse does).
-spec compose(container()) -> binary().
compose(#{type := Type, p7ffd := P7ffd, eff7 := Eff7, dos_rom := DosRom,
          border := Border, cpu := Cpu, ay := Ay, banks := Banks}) ->
    <<?MAGIC/binary, ?VERSION,
      (type_code(Type)),
      P7ffd,
      Eff7:16/little,
      DosRom,
      Border,
      (cpu_block(Cpu))/binary,
      (ay_block(Ay))/binary,
      (iolist_to_binary(Banks))/binary>>.

%% @doc True when the binary carries the container magic.
-spec is_container(binary()) -> boolean().
is_container(<<Magic:4/binary, _/binary>>) -> Magic =:= ?MAGIC;
is_container(_) -> false.

%% @doc Decode a container binary. Errors: bad_magic (not an .ezs at all),
%% bad_size (truncated header/body, unknown type code, wrong bank count),
%% unsupported_version (a newer container).
-spec parse(binary()) ->
    {ok, container()} | {error, {bad_magic | unsupported_version | bad_size, binary()}}.
parse(<<Magic:4/binary, _/binary>> = Data) when Magic =:= ?MAGIC ->
    case Data of
        <<_:4/binary, Version, TypeCode, P7ffd, Eff7:16/little,
          DosRom, Border, Rest/binary>> ->
            case Version of
                ?VERSION ->
                    decode_body(TypeCode, P7ffd, Eff7, DosRom, Border, Rest);
                _ ->
                    {error, {unsupported_version,
                             iolist_to_binary(io_lib:format("EZXS v~w", [Version]))}}
            end;
        _ ->
            {error, {bad_size, <<"truncated EZXS header">>}}
    end;
parse(_Data) ->
    {error, {bad_magic, <<"EZXS">>}}.

%% @doc How many 16KB banks a machine type carries: the three RAM pages of
%% the flat 48K space, the eight 128K-class banks, or the full wired RAM of
%% the big Pentagons.
-spec banks_for_type(type()) -> pos_integer().
banks_for_type('48k') -> 3;
banks_for_type('128k') -> 8;
banks_for_type('pentagon_128') -> 8;
banks_for_type('pentagon_512') -> 32;
banks_for_type('pentagon_1024') -> 64.

%% --- internal ---

decode_body(TypeCode, P7ffd, Eff7, DosRom, Border, Rest) ->
    case type_from_code(TypeCode) of
        undefined ->
            {error, {bad_size, <<"unknown machine type code ", TypeCode:8>>}};
        Type ->
            BankCount = banks_for_type(Type),
            case split_blocks(Rest) of
                {CpuBlock, AyBlock, BanksTail}
                        when byte_size(BanksTail) =:= BankCount * ?BANK_SIZE ->
                    {ok, #{type => Type,
                           p7ffd => P7ffd,
                           eff7 => Eff7,
                           dos_rom => DosRom,
                           border => Border,
                           cpu => decode_cpu(CpuBlock),
                           ay => decode_ay(AyBlock),
                           banks => split_banks(BanksTail)}};
                {CpuBlock, AyBlock, _BanksTail} ->
                    {error, {bad_size, iolist_to_binary(io_lib:format(
                        "expected ~w banks (~w bytes), got ~w",
                        [BankCount, BankCount * ?BANK_SIZE,
                         byte_size(Rest) - byte_size(CpuBlock)
                             - byte_size(AyBlock)]))}};
                bad_size ->
                    {error, {bad_size, <<"truncated or malformed EZXS body">>}}
            end
    end.

%% Split the body into the fixed CPU block, the variable-length AY block and
%% the bank tail; anything short is reported by the caller's size check.
split_blocks(<<CpuBlock:?CPU_SIZE/binary, AyRest/binary>>) ->
    case AyRest of
        <<0, Tail/binary>> ->
            {CpuBlock, binary:part(AyRest, 0, ?AY_ABSENT_SIZE), Tail};
        <<1, _:17/binary, Tail/binary>> ->
            {CpuBlock, binary:part(AyRest, 0, ?AY_PRESENT_SIZE), Tail};
        _ ->
            bad_size
    end;
split_blocks(_) ->
    bad_size.

decode_cpu(<<A, F, B, C, D, E, H, L,
             Aa, Fa, Ba, Ca, Da, Ea, Ha, La,
             I, R,
             Ixh, Ixl, Iyh, Iyl,
             Sp:16/little, Pc:16/little,
             Iff1, Iff2, Im, Halt>>) ->
    #{a => A, f => F, b => B, c => C, d => D, e => E, h => H, l => L,
      a_alt => Aa, f_alt => Fa, b_alt => Ba, c_alt => Ca,
      d_alt => Da, e_alt => Ea, h_alt => Ha, l_alt => La,
      i => I, r => R,
      ixh => Ixh, ixl => Ixl, iyh => Iyh, iyl => Iyl,
      sp => Sp, pc => Pc,
      iff1 => Iff1 band 1, iff2 => Iff2 band 1, im => Im band 3,
      halted => Halt band 1};
decode_cpu(_) ->
    bad_size.

decode_ay(<<0>>) ->
    undefined;
decode_ay(<<1, Selected, Regs:16/binary>>) ->
    #{selected => Selected, regs => Regs};
decode_ay(_) ->
    bad_size.

split_banks(Bin) ->
    <<Bank:?BANK_SIZE/binary, Rest/binary>> = Bin,
    [Bank | case Rest of <<>> -> []; _ -> split_banks(Rest) end].

cpu_block(#{a := A, f := F, b := B, c := C, d := D, e := E, h := H, l := L,
            a_alt := Aa, f_alt := Fa, b_alt := Ba, c_alt := Ca,
            d_alt := Da, e_alt := Ea, h_alt := Ha, l_alt := La,
            i := I, r := R,
            ixh := Ixh, ixl := Ixl, iyh := Iyh, iyl := Iyl,
            sp := Sp, pc := Pc,
            iff1 := Iff1, iff2 := Iff2, im := Im, halted := Halt}) ->
    <<A, F, B, C, D, E, H, L,
      Aa, Fa, Ba, Ca, Da, Ea, Ha, La,
      I, R,
      Ixh, Ixl, Iyh, Iyl,
      Sp:16/little, Pc:16/little,
      Iff1, Iff2, Im, Halt>>.

ay_block(undefined) ->
    <<0>>;
ay_block(#{selected := Selected, regs := Regs}) when byte_size(Regs) =:= 16 ->
    <<1, Selected, Regs/binary>>.

type_code('48k') -> 0;
type_code('128k') -> 1;
type_code('pentagon_128') -> 2;
type_code('pentagon_512') -> 3;
type_code('pentagon_1024') -> 4.

type_from_code(0) -> '48k';
type_from_code(1) -> '128k';
type_from_code(2) -> 'pentagon_128';
type_from_code(3) -> 'pentagon_512';
type_from_code(4) -> 'pentagon_1024';
type_from_code(_) -> undefined.
