-module(ezx_emulator_lib_tests).

-include_lib("eunit/include/eunit.hrl").

%% --- match_port/2 semantics ---

match_zero_bits_must_be_clear_test() ->
    ?assert(ezx_emulator_lib:match_port({16#0001, 16#0000}, 16#00FE)),
    ?assertNot(ezx_emulator_lib:match_port({16#0001, 16#0000}, 16#00FF)).

match_one_bits_must_be_set_test() ->
    ?assert(ezx_emulator_lib:match_port({16#0000, 16#00FE}, 16#00FE)),
    ?assertNot(ezx_emulator_lib:match_port({16#0000, 16#00FE}, 16#00FC)).

match_combines_zero_and_one_test() ->
    ?assert(ezx_emulator_lib:match_port({16#0002, 16#C000}, 16#FFFD)),
    ?assertNot(ezx_emulator_lib:match_port({16#0002, 16#C000}, 16#FFFF)),
    ?assertNot(ezx_emulator_lib:match_port({16#0002, 16#C000}, 16#7FFD)).

match_ignores_unlisted_bits_test() ->
    ?assert(ezx_emulator_lib:match_port({16#0002, 16#8000}, 16#FFFD)),
    ?assertNot(ezx_emulator_lib:match_port({16#0002, 16#8000}, 16#0001)).

%% --- read_port/4 dispatch ---

read_first_match_wins_test() ->
    Table = [
        {16#0001, 16#0000, fun(_Ctx, _TS, _Port) -> {16#AA, first} end},
        {16#0000, 16#0000, fun(_Ctx, _TS, _Port) -> {16#BB, second} end}
    ],
    ?assertEqual({16#AA, first}, ezx_emulator_lib:read_port(Table, ctx, 0, 16#00FE)).

read_nomatch_falls_through_test() ->
    Table = [
        {16#0001, 16#0000, fun(_Ctx, _TS, _Port) -> nomatch end},
        {16#0000, 16#0000, fun(_Ctx, _TS, _Port) -> {16#BB, second} end}
    ],
    ?assertEqual({16#BB, second}, ezx_emulator_lib:read_port(Table, ctx, 0, 16#00FE)).

read_unhandled_returns_ff_test() ->
    ?assertEqual({16#FF, ctx}, ezx_emulator_lib:read_port([], ctx, 0, 16#1234)).

read_single_row_skips_second_on_ok_test() ->
    Table = [
        {16#0001, 16#0000, fun(_Ctx, _TS, _Port) -> {16#AA, first} end},
        {16#0001, 16#0000, fun(_Ctx, _TS, _Port) -> {16#BB, second} end}
    ],
    ?assertEqual({16#AA, first}, ezx_emulator_lib:read_port(Table, ctx, 0, 16#00FE)).

%% --- write_port/5 dispatch ---

write_returns_updated_ctx_test() ->
    Table = [{16#0001, 16#00FE, fun(_Ctx, _TS, _Port, Byte) -> {seen, Byte} end}],
    ?assertEqual({seen, 16#07}, ezx_emulator_lib:write_port(Table, ctx, 0, 16#00FE, 16#07)).

write_unhandled_keeps_ctx_test() ->
    ?assertEqual(ctx, ezx_emulator_lib:write_port([], ctx, 0, 16#1234, 16#07)).

write_nomatch_falls_through_test() ->
    Table = [
        {16#0001, 16#0000, fun(_Ctx, _TS, _Port, _Byte) -> nomatch end},
        {16#0000, 16#0000, fun(_Ctx, _TS, _Port, Byte) -> {seen, Byte} end}
    ],
    ?assertEqual({seen, 16#07}, ezx_emulator_lib:write_port(Table, ctx, 0, 16#00FE, 16#07)).
