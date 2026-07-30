-module(ezx_bench_mem128).

-include("ezx_emulator.hrl").
-include("z80_records.hrl").

-export([
    run/0,
    run/1,
    compare/0,
    compare/1
]).

-define(DEFAULT_DURATION_SEC, 30).
-define(MEM_MODS, [
    {ezx_memory_128,            "binary slice (8 banks)"},
    {ezx_memory_128_pages512,   "page map + 512B pages"}
]).

%% --- Public API ---

-spec compare() -> ok.
compare() -> compare(?DEFAULT_DURATION_SEC).

-spec compare(pos_integer()) -> ok.
compare(DurationSec) ->
    {Rom0, Rom1} = load_roms(),
    io:format("~n"),
    io:format("========================================================~n"),
    io:format("  128K Memory Backend Benchmark — ROM boot~n"),
    io:format("  Duration: ~B seconds per backend~n", [DurationSec]),
    io:format("========================================================~n~n"),

    Results = lists:map(fun({Mod, Desc}) ->
        io:format("[~s] ~s ...~n", [Mod, Desc]),
        Data = bench_one(Mod, Rom0, Rom1, DurationSec),
        {Mod, Desc, Data}
    end, ?MEM_MODS),

    print_comparison(Results),
    ok.

-spec run() -> ok.
run() -> run(?DEFAULT_DURATION_SEC).

-spec run(pos_integer()) -> ok.
run(DurationSec) -> compare(DurationSec).

%% --- Benchmark a single backend ---

bench_one(MemMod, Rom0, Rom1, DurationSec) ->
    M0 = ezx_emulator_128:init(z80_cpu, MemMod, ezx_screen, ezx_keyboard, ezx_beeper2, ezx_ay38912, {Rom0, Rom1}),

    M1 = warmup(M0, 100),

    erlang:garbage_collect(),

    CpuStats = bench_cpu_timed(M1, deadline_us(DurationSec), []),

    erlang:garbage_collect(),

    M2 = ezx_emulator_128:init(z80_cpu, MemMod, ezx_screen, ezx_keyboard, ezx_beeper2, ezx_ay38912, {Rom0, Rom1}),
    M3 = warmup(M2, 100),

    erlang:garbage_collect(),

    FullStats = bench_full_timed(MemMod, M3, deadline_us(DurationSec), [], []),

    erlang:garbage_collect(),

    Mem3 = M3#machine_state.memory,
    MemModRef = M3#machine_state.memory_module,
    VideoStats = bench_read_block(MemModRef, Mem3, 16384, 6912, 10000),

    FinalCpu = M3#machine_state.cpu,
    FinalState = #{
        pc   => z80_cpu:pc(FinalCpu),
        sp   => FinalCpu#cpu_state.sp,
        af   => (FinalCpu#cpu_state.a bsl 8) bor FinalCpu#cpu_state.f,
        bc   => (FinalCpu#cpu_state.b bsl 8) bor FinalCpu#cpu_state.c,
        de   => (FinalCpu#cpu_state.d bsl 8) bor FinalCpu#cpu_state.e,
        hl   => (FinalCpu#cpu_state.h bsl 8) bor FinalCpu#cpu_state.l,
        ix   => (FinalCpu#cpu_state.ixh bsl 8) bor FinalCpu#cpu_state.ixl,
        iy   => (FinalCpu#cpu_state.iyh bsl 8) bor FinalCpu#cpu_state.iyl,
        frames => M3#machine_state.flash_counter
    },

    #{cpu_only => CpuStats, full => FullStats, video_read => VideoStats, state => FinalState}.

warmup(M, N) ->
    lists:foldl(fun(_, X) -> ezx_emulator_128:run_frame(X) end, M, lists:seq(1, N)).

bench_cpu_timed(M, DeadlineUs, Acc) ->
    Now = erlang:monotonic_time(microsecond),
    case Now >= DeadlineUs of
        true ->
            finalize_stats(Acc);
        false ->
            T0 = erlang:monotonic_time(microsecond),
            M1 = ezx_emulator_128:run_frame(M),
            T1 = erlang:monotonic_time(microsecond),
            bench_cpu_timed(M1, DeadlineUs, [T1 - T0 | Acc])
    end.

bench_full_timed(MemMod, M, DeadlineUs, CpuAcc, VidAcc) ->
    Now = erlang:monotonic_time(microsecond),
    case Now >= DeadlineUs of
        true ->
            #{cpu => finalize_stats(CpuAcc), video => finalize_stats(VidAcc)};
        false ->
            T0 = erlang:monotonic_time(microsecond),
            M1 = ezx_emulator_128:run_frame(M),
            T1 = erlang:monotonic_time(microsecond),

            MemModule = M1#machine_state.memory_module,
            VideoModule = M1#machine_state.video_module,
            FlashOn = M1#machine_state.flash_counter div 16 =:= 1,
            Changes = lists:reverse(M1#machine_state.border_changes),
            CB = M1#machine_state.border_color,
            Mem = M1#machine_state.memory,
            Videobuffer = MemModule:read_block(Mem, 16384, 6144 + 768),
            VideoModule:render_frame(Videobuffer, FlashOn, Changes, CB),
            T2 = erlang:monotonic_time(microsecond),

            bench_full_timed(MemMod, M1, DeadlineUs,
                             [T1 - T0 | CpuAcc], [T2 - T1 | VidAcc])
    end.

finalize_stats([]) ->
    #{avg => 0, min => 0, max => 0, p95 => 0, p99 => 0, count => 0};
finalize_stats(RawTimes) ->
    Sorted = lists:sort(RawTimes),
    Count = length(Sorted),
    Sum = lists:sum(Sorted),
    Avg = Sum / Count,
    Percentile = fun(P) ->
        Idx = max(1, round(Count * P / 100)),
        lists:nth(Idx, Sorted)
    end,
    #{avg   => Avg,
      min   => hd(Sorted),
      max   => lists:last(Sorted),
      p95   => Percentile(95),
      p99   => Percentile(99),
      count => Count}.

bench_read_block(MemMod, Mem, Addr, Size, N) ->
    _ = [MemMod:read_block(Mem, Addr, Size) || _ <- lists:seq(1, min(1000, N))],
    Times = [begin
        T0 = erlang:monotonic_time(nanosecond),
        _Block = MemMod:read_block(Mem, Addr, Size),
        T1 = erlang:monotonic_time(nanosecond),
        T1 - T0
    end || _ <- lists:seq(1, N)],
    Sorted = lists:sort(Times),
    AvgNs = lists:sum(Sorted) / N,
    #{avg_us => AvgNs / 1000,
      min_us => hd(Sorted) / 1000,
      max_us => lists:last(Sorted) / 1000}.

%% --- Print results ---

find_result(Mod, Results) ->
    case lists:keyfind(Mod, 1, Results) of
        {Mod, _Desc, Data} -> Data;
        false -> #{}
    end.

print_comparison(Results) ->
    io:format("~n"),
    io:format("========================================================~n"),
    io:format("  RESULTS: CPU-only (run_frame)~n"),
    io:format("========================================================~n"),
    io:format("  ~-28s ~-25s ~8s ~8s ~8s ~8s ~8s~n",
              ["Backend", "Module", "Avg", "Min", "Max", "P95", "P99"]),
    io:format("  ~-28s ~-25s ~8s ~8s ~8s ~8s ~8s~n",
              ["----------------------------", "-------------------------", "--------", "--------", "--------", "--------", "--------"]),

    lists:foreach(fun({Mod, Desc, _Data}) ->
        #{cpu_only := CpuStats} = find_result(Mod, Results),
        #{avg := Avg, min := Min, max := Max, p95 := P95, p99 := P99} = CpuStats,
        io:format("  ~-28s ~-25s ~7.1f ~7.1f ~7.1f ~7.1f ~7.1f us~n",
                  [Desc, atom_to_list(Mod), Avg, Min * 1.0, Max * 1.0, P95 * 1.0, P99 * 1.0])
    end, Results),

    CpuAvgs = lists:map(fun({Mod, _, _}) ->
        #{cpu_only := CpuStats} = find_result(Mod, Results),
        maps:get(avg, CpuStats)
    end, Results),
    SlowestAvg = lists:max(CpuAvgs),
    io:format("~n  Relative to slowest:~n"),
    lists:foreach(fun({{_, Desc, _}, Avg}) ->
        Speedup = SlowestAvg / Avg,
        io:format("  ~-28s ~.2fx~n", [Desc, Speedup])
    end, lists:zip(Results, CpuAvgs)),

    io:format("~n"),
    io:format("========================================================~n"),
    io:format("  VIDEO MEMORY READ (read_block 6912 bytes, 10000 iterations)~n"),
    io:format("========================================================~n"),
    io:format("  ~-28s ~-25s ~10s ~10s ~10s~n",
              ["Backend", "Module", "Avg", "Min", "Max"]),
    io:format("  ~-28s ~-25s ~10s ~10s ~10s~n",
              ["----------------------------", "-------------------------", "----------", "----------", "----------"]),

    lists:foreach(fun({Mod, Desc, _Data}) ->
        #{video_read := #{avg_us := Avg, min_us := Min, max_us := Max}} = find_result(Mod, Results),
        io:format("  ~-28s ~-25s ~9.2f ~9.2f ~9.2f us~n",
                  [Desc, atom_to_list(Mod), Avg, Min, Max])
    end, Results),

    io:format("~n"),
    io:format("========================================================~n"),
    io:format("  RESULTS: CPU + Video (run_frame + render_frame)~n"),
    io:format("========================================================~n"),
    io:format("  ~-28s ~-25s ~8s ~8s ~8s~n",
              ["Backend", "Module", "CPU", "Video", "Total"]),
    io:format("  ~-28s ~-25s ~8s ~8s ~8s~n",
              ["----------------------------", "-------------------------", "--------", "--------", "--------"]),

    lists:foreach(fun({Mod, Desc, _Data}) ->
        #{full := #{cpu := CpuS, video := VidS}} = find_result(Mod, Results),
        CpuAvg = maps:get(avg, CpuS),
        VidAvg = maps:get(avg, VidS),
        io:format("  ~-28s ~-25s ~7.1f ~7.1f ~7.1f us~n",
                  [Desc, atom_to_list(Mod), CpuAvg, VidAvg, CpuAvg + VidAvg])
    end, Results),

    BudgetUs = 20000.0,
    io:format("~n"),
    io:format("========================================================~n"),
    io:format("  CPU TIME BUDGET (20ms/frame @ 50fps)~n"),
    io:format("========================================================~n"),
    lists:foreach(fun({Mod, Desc, _Data}) ->
        #{cpu_only := CpuStats} = find_result(Mod, Results),
        AvgUs = maps:get(avg, CpuStats),
        Ratio = AvgUs / BudgetUs,
        Headroom = case Ratio of
            R when R > 0 -> (1.0 / R) - 1.0;
            _ -> 0
        end,
        Status = case Ratio < 1.0 of
            true  -> io_lib:format("~.1f%% headroom", [Headroom * 100]);
            false -> io_lib:format("~.1fx OVER", [Ratio])
        end,
        io:format("  ~-28s ~-25s ~7.1f us  ~.2fx  ~s~n",
                  [Desc, atom_to_list(Mod), AvgUs, Ratio, lists:flatten(Status)])
    end, Results),

    io:format("~n"),
    io:format("========================================================~n"),
    io:format("  CORRECTNESS CHECK~n"),
    io:format("========================================================~n"),

    ReferenceData = find_result(element(1, hd(Results)), Results),
    #{pc := RefPC, sp := RefSP} = maps:get(state, ReferenceData),

    lists:foreach(fun({Mod, Desc, _Data}) ->
        #{state := #{pc := PC, sp := SP, af := AF, bc := BC}} = find_result(Mod, Results),
        Match = case {PC, SP} of
            {RefPC, RefSP} -> "OK";
            _ -> "MISMATCH"
        end,
        io:format("  ~-28s ~-25s PC=~4.16.0B SP=~4.16.0B AF=~4.16.0B BC=~4.16.0B ~s~n",
                  [Desc, atom_to_list(Mod), PC, SP, AF, BC, Match])
    end, Results),

    io:format("~n"),
    ok.

%% --- Helpers ---

deadline_us(DurationSec) ->
    erlang:monotonic_time(microsecond) + DurationSec * 1000000.

load_roms() ->
    PrivDir = try code:priv_dir(ezx)
    catch error:badarg ->
        filename:dirname(filename:dirname(code:which(?MODULE)))
    end,
    {ok, R0} = file:read_file(filename:join([PrivDir, "roms", "128-0.rom"])),
    {ok, R1} = file:read_file(filename:join([PrivDir, "roms", "128-1.rom"])),
    {R0, R1}.
