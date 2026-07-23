-module(ezx_keyboard).

-include("z80_records.hrl").
-include("ezx_emulator.hrl").

-export([
    default/0,
    press/3, release/3,
    press_key/2, release_key/2,
    release_all/0,
    is_pressed/3,
    decode/2
]).

-type key_matrix() :: {byte(), byte(), byte(), byte(), byte(), byte(), byte(), byte()}.
-export_type([key_matrix/0]).

%% @doc Default keyboard state: all keys released.
-spec default() -> key_matrix().
default() -> ?KEYBOARD_DEFAULT.

%% @doc Press a key at the given matrix position (active-low: 0 = pressed).
-spec press(key_matrix(), pos_integer(), non_neg_integer()) -> key_matrix().
press(KB, Row, Bit) ->
    Old = element(Row, KB),
    setelement(Row, KB, Old band (bnot (1 bsl Bit))).

%% @doc Release a key at the given matrix position.
-spec release(key_matrix(), pos_integer(), non_neg_integer()) -> key_matrix().
release(KB, Row, Bit) ->
    Old = element(Row, KB),
    setelement(Row, KB, Old bor (1 bsl Bit)).

%% @doc Release all keys.
-spec release_all() -> key_matrix().
release_all() -> ?KEYBOARD_DEFAULT.

%% @doc Check if a key at the given matrix position is pressed.
-spec is_pressed(key_matrix(), pos_integer(), non_neg_integer()) -> boolean().
is_pressed(KB, Row, Bit) ->
    element(Row, KB) band (1 bsl Bit) =:= 0.

%% @doc Decode keyboard state for ZX Spectrum port I/O (port 0xFE).
%% UpperByte selects half-rows (active low, bit = 0 selects row).
%% Selected rows are ANDed together; bits 5-7 are always 1 (floating bus).
-spec decode(key_matrix(), non_neg_integer()) -> non_neg_integer().
decode(KB, UpperByte) ->
    decode_rows(KB, UpperByte, 16#1F, 0).

%% @doc Press a key by its ZX Spectrum name atom.
%% Key names: space, enter, shift, sym_shift, a-z, 0-9.
-spec press_key(key_matrix(), atom()) -> key_matrix().
press_key(KB, Key) ->
    case key_position(Key) of
        {ok, Row, Bit} -> press(KB, Row, Bit);
        error -> KB
    end.

%% @doc Release a key by its ZX Spectrum name atom.
-spec release_key(key_matrix(), atom()) -> key_matrix().
release_key(KB, Key) ->
    case key_position(Key) of
        {ok, Row, Bit} -> release(KB, Row, Bit);
        error -> KB
    end.

%% --- Internal ---

decode_rows(_KB, _Mask, Acc, 8) ->
    Acc bor 16#E0;
decode_rows(KB, Mask, Acc, N) ->
    case (Mask band 1) of
        0 ->
            RowByte = element(N + 1, KB),
            decode_rows(KB, Mask bsr 1, Acc band RowByte, N + 1);
        1 ->
            decode_rows(KB, Mask bsr 1, Acc, N + 1)
    end.

%% ZX Spectrum keyboard matrix positions.
%% {Row, Bit} — row 1-8, bit 0-4.
key_position(space)       -> {8, 0};
key_position(sym_shift)   -> {8, 1};
key_position(m)           -> {8, 2};
key_position(n)           -> {8, 3};
key_position(b)           -> {8, 4};

key_position(enter)       -> {7, 0};
key_position(l)           -> {7, 1};
key_position(k)           -> {7, 2};
key_position(j)           -> {7, 3};
key_position(h)           -> {7, 4};

key_position(p)           -> {6, 0};
key_position(o)           -> {6, 1};
key_position(i)           -> {6, 2};
key_position(u)           -> {6, 3};
key_position(y)           -> {6, 4};

key_position('0')         -> {5, 0};
key_position('9')         -> {5, 1};
key_position('8')         -> {5, 2};
key_position('7')         -> {5, 3};
key_position('6')         -> {5, 4};

key_position('1')         -> {4, 0};
key_position('2')         -> {4, 1};
key_position('3')         -> {4, 2};
key_position('4')         -> {4, 3};
key_position('5')         -> {4, 4};

key_position(q)           -> {3, 0};
key_position(w)           -> {3, 1};
key_position(e)           -> {3, 2};
key_position(r)           -> {3, 3};
key_position(t)           -> {3, 4};

key_position(a)           -> {2, 0};
key_position(s)           -> {2, 1};
key_position(d)           -> {2, 2};
key_position(f)           -> {2, 3};
key_position(g)           -> {2, 4};

key_position(shift)       -> {1, 0};
key_position(z)           -> {1, 1};
key_position(x)           -> {1, 2};
key_position(c)           -> {1, 3};
key_position(v)           -> {1, 4};

key_position(_)           -> error.
