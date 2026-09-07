-module(ezx_ezs_tests).

-include_lib("eunit/include/eunit.hrl").

%% --- compose / parse round trip ---

round_trip_test() ->
    Map = container_map(),
    Bin = ezx_ezs:compose(Map),
    ?assert(byte_size(Bin) =:= 11 + 30 + 18 + 32 * 16384),
    ?assert(ezx_ezs:is_container(Bin)),
    ?assertEqual({ok, Map}, ezx_ezs:parse(Bin)).

absent_ay_test() ->
    %% A chip-less machine stores a one-byte empty AY block.
    Z80less = (container_map())#{type => 'pentagon_128', ay => undefined,
                                 banks => banks(8)},
    Bin = ezx_ezs:compose(Z80less),
    ?assert(byte_size(Bin) =:= 11 + 30 + 1 + 8 * 16384),
    ?assertEqual({ok, Z80less}, ezx_ezs:parse(Bin)).

flat_48k_layout_test() ->
    %% A 48K container carries its three RAM pages in address order.
    Map = (container_map())#{type => '48k', banks => banks(3)},
    ?assertEqual({ok, Map}, ezx_ezs:parse(ezx_ezs:compose(Map))).

%% --- errors ---

bad_magic_test() ->
    ?assertEqual({error, {bad_magic, <<"EZXS">>}}, ezx_ezs:parse(<<"NOPE">>)),
    ?assertNot(ezx_ezs:is_container(<<"NOPE">>)),
    %% Exactly the magic and nothing else: recognized as ours but truncated.
    ?assert(ezx_ezs:is_container(<<"EZXS">>)),
    ?assertMatch({error, {bad_size, _}}, ezx_ezs:parse(<<"EZXS">>)).

unsupported_version_test() ->
    Bin = ezx_ezs:compose(container_map()),
    <<Magic:4/binary, _V:8, Rest/binary>> = Bin,
    Future = <<Magic/binary, 99, Rest/binary>>,
    ?assertMatch({error, {unsupported_version, <<"EZXS v99">>}},
                 ezx_ezs:parse(Future)).

bad_type_code_test() ->
    Bin = ezx_ezs:compose(container_map()),
    <<Magic:4/binary, V:8, _T:8, Rest/binary>> = Bin,
    Broken = <<Magic/binary, V, 15, Rest/binary>>,
    ?assertMatch({error, {bad_size, _}}, ezx_ezs:parse(Broken)).

wrong_bank_count_test() ->
    %% Declared pentagon_512 (32 banks) but one bank short in the tail.
    Map = (container_map())#{banks => lists:nthtail(1, banks(32))},
    ?assertMatch({error, {bad_size, _}}, ezx_ezs:parse(ezx_ezs:compose(Map))).

truncated_body_test() ->
    Bin = ezx_ezs:compose(container_map()),
    ?assertMatch({error, {bad_size, _}},
                 ezx_ezs:parse(binary:part(Bin, 0, byte_size(Bin) - 1))),
    %% Header complete, body missing entirely.
    ?assertMatch({error, {bad_size, _}}, ezx_ezs:parse(binary:part(Bin, 0, 11))),
    %% Header plus a partial CPU block.
    ?assertMatch({error, {bad_size, _}},
                 ezx_ezs:parse(binary:part(Bin, 0, 11 + 10))).

bad_ay_marker_test() ->
    Bin = ezx_ezs:compose(container_map()),
    %% Byte 41 is the AY presence marker; anything but 0/1 is invalid.
    <<Head:41/binary, _:8, Tail/binary>> = Bin,
    ?assertMatch({error, {bad_size, _}},
                 ezx_ezs:parse(<<Head/binary, 9, Tail/binary>>)).

%% --- helpers ---

container_map() ->
    #{type => 'pentagon_512',
      p7ffd => 16#07, eff7 => 16#08, dos_rom => 1, border => 4,
      cpu => cpu_map(),
      ay => #{selected => 7, regs => ay_regs()},
      banks => banks(32)}.

cpu_map() ->
    #{a => 16#11, f => 16#22, b => 16#33, c => 16#44,
      d => 16#55, e => 16#66, h => 16#77, l => 16#88,
      a_alt => 16#99, f_alt => 16#AA, b_alt => 16#BB, c_alt => 16#CC,
      d_alt => 16#DD, e_alt => 16#EE, h_alt => 16#10, l_alt => 16#20,
      i => 16#75, r => 16#86,
      ixh => 16#31, ixl => 16#42, iyh => 16#53, iyl => 16#64,
      sp => 16#A000, pc => 16#5678,
      iff1 => 1, iff2 => 0, im => 2, halted => 0}.

ay_regs() ->
    << <<(16 + N)>> || N <- lists:seq(0, 15) >>.

banks(N) ->
    [binary:copy(<<(B band 16#FF)>>, 16384) || B <- lists:seq(0, N - 1)].
