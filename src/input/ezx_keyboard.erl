-module(ezx_keyboard).

-include("z80_records.hrl").
-include("ezx_keyboard.hrl").

-export([
    default/0,
    set_matrix/2,
    % press/3, release/3,
    press_keys/2, release_keys/2,
    release_all/1,
    is_pressed/3,
    decode/2
]).

-type state() :: #keyboard{}.
-type key_matrix() :: {byte(), byte(), byte(), byte(), byte(), byte(), byte(), byte()}.
-export_type([key_matrix/0]).

%% @doc Default keyboard state: all keys released.
-spec default() -> state().
default() ->
    #keyboard{matrix = ?KEYBOARD_DEFAULT}.

set_matrix(#keyboard{} = State, NewMatrix) when is_tuple(NewMatrix), tuple_size(NewMatrix) =:= 8 ->
    State#keyboard{matrix = NewMatrix}.

% %% @doc Press a key at the given matrix position (active-low: 0 = pressed).
% -spec press(state(), pos_integer(), non_neg_integer()) -> state().
% press(#keyboard{matrix = Matrix}, RowNum, Bit) ->
%     Row = element(RowNum, Matrix),
%     NewMatrix = setelement(RowNum, Matrix, Row band (bnot (1 bsl Bit))),
%     #keyboard{matrix = NewMatrix}.

% %% @doc Release a key at the given matrix position.
% -spec release(state(), pos_integer(), non_neg_integer()) -> state().
% release(#keyboard{matrix = Matrix}, RowNum, Bit) ->
%     Row = element(RowNum, Matrix),
%     NewMatrix = setelement(RowNum, Matrix, Row bor (1 bsl Bit)),
%     #keyboard{matrix = NewMatrix}.


%% @doc Release all keys.
-spec release_all(state()) -> state().
release_all(#keyboard{}) -> default().

%% @doc Check if a key at the given matrix position is pressed.
-spec is_pressed(state(), pos_integer(), non_neg_integer()) -> boolean().
is_pressed(#keyboard{matrix = Matrix}, Row, Bit) ->
    element(Row, Matrix) band (1 bsl Bit) =:= 0.

%% @doc Decode keyboard state for ZX Spectrum port I/O (port 0xFE).
%% UpperByte selects half-rows (active low, bit = 0 selects row).
%% Selected rows are ANDed together; bits 5-7 are always 1 (floating bus).
%% UpperByte bits:
%% bit 7 - (space, sym_shift, m, n, b)
%% bit 6 - (enter, l, k, j, h)
%% bit 5 - (p, o, i, u, y)
%% bit 4 - (0, 9, 8, 7, 6)
%% bit 3 - (1, 2, 3, 4, 5)
%% bit 2 - (q, w, e, r, t)
%% bit 1 - (a, s, d, f, g)
%% bit 0 - (shift, z, x, c, v)
-spec decode(state(), non_neg_integer()) -> non_neg_integer().
decode(#keyboard{matrix = Matrix}, UpperByte) ->
    decode_rows(Matrix, UpperByte, 16#1F, 0).

%% @doc Press a key by its ZX Spectrum name atom.
%% Key names: space, enter, shift, sym_shift, a-z, 0-9.
-spec press_keys(state(), [{RowNum::pos_integer(), Bit::non_neg_integer()}]) -> state().
press_keys(#keyboard{matrix = Matrix} = State, Keys) ->
    NewMatrix = lists:foldl(
        fun({RowNum, Bit}, AccMatrix) ->
            Row = element(RowNum, AccMatrix),
            setelement(RowNum, AccMatrix, Row band (bnot (1 bsl Bit)))
        end, Matrix, Keys),
    State#keyboard{matrix = NewMatrix}.

%% @doc Release a key by its ZX Spectrum name atom.
-spec release_keys(state(), [{RowNum::pos_integer(), Bit::non_neg_integer()}]) -> state().
release_keys(#keyboard{matrix = Matrix} = State, Keys) ->
    NewMatrix = lists:foldl(
        fun({RowNum, Bit}, AccMatrix) ->
            Row = element(RowNum, AccMatrix),
            setelement(RowNum, AccMatrix, Row bor (1 bsl Bit))
        end, Matrix, Keys),
    State#keyboard{matrix = NewMatrix}.

%% --- Internal ---

decode_rows(_KB, _Mask, Acc, 8) ->
    Acc bor 16#E0;
decode_rows(KB, Mask, Acc, N) ->
    NewAcc = case (Mask band 1) of
        0 -> element(N + 1, KB) band Acc;
        1 -> Acc
    end,
    decode_rows(KB, Mask bsr 1, NewAcc, N + 1).
