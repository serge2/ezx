-module(ezx_bench_mem).

-include("ezx_emulator.hrl").
-include("z80_records.hrl").

-export([
    run/0,
    run/1,
    run/2,
    compare/0,
    compare/1
]).

-define(DEFAULT_DURATION_SEC, 30).
-define(MEM_MODS, [
    {ezx_memory_48,       "flat binary (64KB)"},
    {ezx_memory_48_map,   "map of 4KB pages"},
    {ezx_memory_48_pages, "tuple of 4KB pages"},
    {ezx_memory_48_pages1k, "tuple of 1KB pages"},
    {ezx_memory_48_pages2k, "tuple of 2KB pages"},
    {ezx_memory_48_pages512, "tuple of 512B pages"},
    {ezx_memory_48_array, "erlang array (1 byte)"},
    {ezx_memory_48_array2, "erlang array (2 bytes)"},
    {ezx_memory_48_array4, "erlang array (4 bytes)"},
    {ezx_memory_48_array8, "erlang array (8 bytes)"}
]).

%% --- Public API ---

%% @doc Run benchmark for default 30 seconds on all memory backends.
-spec compare() -> ok.
compare() -> compare(?DEFAULT_DURATION_SEC).

%% @doc Run benchmark for N seconds on all memory backends.
-spec compare(pos_integer()) -> ok.
compare(DurationSec) ->
    Rom = load_rom(),
    SnaPath = default_sna_path(),
    case filelib:is_file(SnaPath) of
        false ->
            io:format("SNA not found: ~s~nUsing ROM-only mode.~n~n", [SnaPath]),
            run_rom_only(Rom, DurationSec);
        true ->
            {ok, SnaData} = file:read_file(SnaPath),
            run_with_sna(Rom, SnaData, SnaPath, DurationSec)
    end.

%% @doc Quick run with default settings (for erlang shell).
-spec run() -> ok.
run() -> run(?DEFAULT_DURATION_SEC).

%% @doc Quick run for N seconds.
-spec run(pos_integer()) -> ok.
run(DurationSec) -> compare(DurationSec).

%% @doc Quick run for N seconds with explicit SNA path.
-spec run(pos_integer(), string()) -> ok.
run(DurationSec, SnaPath) ->
    Rom = load_rom(),
    {ok, SnaData} = file:read_file(SnaPath),
    run_with_sna(Rom, SnaData, SnaPath, DurationSec).

%% --- Internal: ROM-only mode ---

run_rom_only(Rom, DurationSec) ->
    io:format("~n"),
    io:format("========================================================~n"),
    io:format("  Memory Backend Benchmark — ROM boot (no SNA)~n"),
    io:format("  Duration: ~B seconds per backend~n", [DurationSec]),
    io:format("========================================================~n~n"),

    Results = lists:map(fun({Mod, Desc}) ->
        io:format("[~s] ~s ...~n", [Mod, Desc]),
        Data = bench_one(Mod, Rom, undefined, DurationSec),
        {Mod, Desc, Data}
    end, ?MEM_MODS),

    print_comparison(Results),
    ok.

%% --- Internal: SNA mode ---

run_with_sna(Rom, SnaData, SnaPath, DurationSec) ->
    io:format("~n"),
    io:format("========================================================~n"),
    io:format("  Memory Backend Benchmark — ~s~n", [filename:basename(SnaPath)]),
    io:format("  Duration: ~B seconds per backend~n", [DurationSec]),
    io:format("========================================================~n~n"),

    Results = lists:map(fun({Mod, Desc}) ->
        io:format("[~s] ~s ...~n", [Mod, Desc]),
        Data = bench_one(Mod, Rom, SnaData, DurationSec),
        {Mod, Desc, Data}
    end, ?MEM_MODS),

    print_comparison(Results),
    ok.

%% --- Benchmark a single backend ---

bench_one(MemMod, Rom, SnaData, DurationSec) ->
    %% Initialize with real ROM, default video/beeper/keyboard.
    M0 = ezx_emulator:init(z80_cpu, MemMod, ezx_screen, ezx_keyboard, ezx_beeper, Rom),

    %% Optionally load SNA snapshot.
    M1 = case SnaData of
        undefined -> M0;
        _ -> ezx_emulator:load_sna(M0, SnaData)
    end,

    %% Warm up: run 100 frames so CPU reaches steady-state code paths.
    M2 = warmup(M1, 100),

    %% Force GC to get clean baselines.
    erlang:garbage_collect(),

    %% === Phase 1: CPU-only (run_frame) ===
    CpuStats = bench_cpu_timed(M2, deadline_us(DurationSec), []),

    %% Force GC between phases.
    erlang:garbage_collect(),

    %% === Phase 2: CPU + render_frame ===
    %% Reset state for fair comparison.
    M3 = case SnaData of
        undefined -> ezx_emulator:init(z80_cpu, MemMod, ezx_screen, ezx_keyboard, ezx_beeper, Rom);
        _ -> ezx_emulator:load_sna(ezx_emulator:init(z80_cpu, MemMod, ezx_screen, ezx_keyboard, ezx_beeper, Rom), SnaData)
    end,
    M4 = warmup(M3, 100),

    %% Force GC before full-phase timing.
    erlang:garbage_collect(),

    FullStats = bench_full_timed(MemMod, M4, deadline_us(DurationSec), [], []),

    %% Force GC before read_block benchmark.
    erlang:garbage_collect(),

    %% === Phase 3: Video memory read_block throughput ===
    Mem4 = M4#machine_state.memory,
    MemModRef = M4#machine_state.memory_module,
    VideoStats = bench_read_block(MemModRef, Mem4, 16384, 6912, 10000),

    %% Collect final CPU state for correctness check.
    FinalCpu = M2#machine_state.cpu,
    FinalState = #{
        pc   => z80_cpu:pc(FinalCpu),
        sp   => FinalCpu#cpu_state.sp,
        af   => (FinalCpu#cpu_state.a bsl 8) bor FinalCpu#cpu_state.f,
        bc   => (FinalCpu#cpu_state.b bsl 8) bor FinalCpu#cpu_state.c,
        de   => (FinalCpu#cpu_state.d bsl 8) bor FinalCpu#cpu_state.e,
        hl   => (FinalCpu#cpu_state.h bsl 8) bor FinalCpu#cpu_state.l,
        ix   => (FinalCpu#cpu_state.ixh bsl 8) bor FinalCpu#cpu_state.ixl,
        iy   => (FinalCpu#cpu_state.iyh bsl 8) bor FinalCpu#cpu_state.iyl,
        frames => M2#machine_state.flash_counter
    },

    #{cpu_only => CpuStats, full => FullStats, video_read => VideoStats, state => FinalState}.

warmup(M, N) ->
    lists:foldl(fun(_, X) -> ezx_emulator:run_frame(X) end, M, lists:seq(1, N)).

%% CPU-only timed loop: measure run_frame only.
bench_cpu_timed(M, DeadlineUs, Acc) ->
    Now = erlang:monotonic_time(microsecond),
    case Now >= DeadlineUs of
        true ->
            finalize_stats(Acc);
        false ->
            T0 = erlang:monotonic_time(microsecond),
            M1 = ezx_emulator:run_frame(M),
            T1 = erlang:monotonic_time(microsecond),
            bench_cpu_timed(M1, DeadlineUs, [T1 - T0 | Acc])
    end.

%% Full timed loop: measure run_frame + render_frame.
bench_full_timed(MemMod, M, DeadlineUs, CpuAcc, VidAcc) ->
    Now = erlang:monotonic_time(microsecond),
    case Now >= DeadlineUs of
        true ->
            #{cpu => finalize_stats(CpuAcc), video => finalize_stats(VidAcc)};
        false ->
            T0 = erlang:monotonic_time(microsecond),
            M1 = ezx_emulator:run_frame(M),
            T1 = erlang:monotonic_time(microsecond),

            %% Render video (same as ezx_ui does it).
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

%% Benchmark read_block: measure average time over N iterations.
bench_read_block(MemMod, Mem, Addr, Size, N) ->
    %% Warmup
    _ = [MemMod:read_block(Mem, Addr, Size) || _ <- lists:seq(1, min(1000, N))],
    %% Timed
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

%% Look up a result by module name.
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

    %% Speedup relative to slowest.
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

    %% Video memory read_block (6912 bytes at 0x4000).
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

    %% CPU + Video.
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

    %% CPU time budget analysis.
    BudgetUs = 20000.0,  %% 20ms per frame at 50fps
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

    %% Correctness check: all backends should reach same PC/SP.
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

load_rom() ->
    RomPath = try filename:join([code:priv_dir(ezx), "roms", "48.rom"])
    catch error:badarg ->
        BeamDir = filename:dirname(code:which(?MODULE)),
        filename:join([filename:dirname(BeamDir), "priv", "roms", "48.rom"])
    end,
    {ok, Rom} = file:read_file(RomPath),
    Rom.

default_sna_path() ->
    %% Try relative to project root first, then common locations.
    Candidates = [
        filename:join(["..", "Spectrum", "Games", "s",
                       "Saboteur! (1985)(Durell).sna"]),
        filename:join([os:getenv("HOME"), "Spectrum", "Games", "s",
                       "Saboteur! (1985)(Durell).sna"])
    ],
    case [P || P <- Candidates, filelib:is_file(P)] of
        [Found | _] -> Found;
        [] -> "Saboteur! (1985)(Durell).sna"
    end.
