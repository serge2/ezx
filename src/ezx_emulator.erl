-module(ezx_emulator).

-include("z80_records.hrl").

-export([
    init/0,
    load_program/2,
    step/1,
    run_until_tstates/2,
    read_byte/2,
    write_byte/3,
    read_word/2,
    write_word/3
]).

%% @doc Create a new machine state with initialized CPU and memory components.
-spec init() -> #machine_state{}.
init() ->
    #machine_state{
        cpu = z80_cpu:init_state(),
        memory = z80_mem:new(65536)
    }.

%% @doc Load a program into the machine memory so the emulator can execute it.
-spec load_program(#machine_state{}, map() | [byte()] | binary()) -> #machine_state{}.
load_program(Machine, Program) ->
    Memory = normalize_program(Program),
    Machine#machine_state{memory = Memory}.

%% @doc Read a byte from the machine memory.
-spec read_byte(#machine_state{}, non_neg_integer()) -> byte().
read_byte(Machine, Addr) ->
    z80_mem:read_byte(Machine#machine_state.memory, Addr band 16#ffff).

%% @doc Write a byte into the machine memory.
-spec write_byte(#machine_state{}, non_neg_integer(), byte()) -> #machine_state{}.
write_byte(Machine, Addr, Byte) ->
    Memory1 = z80_mem:write_byte(Machine#machine_state.memory, Addr band 16#ffff, Byte band 16#ff),
    Machine#machine_state{memory = Memory1}.

%% @doc Read a 16-bit word from the machine memory.
-spec read_word(#machine_state{}, non_neg_integer()) -> non_neg_integer().
read_word(Machine, Addr) ->
    read_byte(Machine, Addr) + (read_byte(Machine, Addr + 1) bsl 8).

%% @doc Write a 16-bit word into the machine memory.
-spec write_word(#machine_state{}, non_neg_integer(), non_neg_integer()) -> #machine_state{}.
write_word(Machine, Addr, Word) ->
    Machine1 = write_byte(Machine, Addr, Word band 16#ff),
    write_byte(Machine1, Addr + 1, (Word bsr 8) band 16#ff).

normalize_program(Program) when is_map(Program) ->
    lists:foldl(
        fun({Addr, Value}, Acc) ->
            z80_mem:write_byte(Acc, Addr, Value)
        end,
        z80_mem:new(65536),
        maps:to_list(Program)
    );
normalize_program(Program) when is_list(Program) ->
    Bytes = [Byte band 16#ff ||
        Byte <- Program],
    lists:foldl(
        fun({Addr, Value}, Acc) ->
            z80_mem:write_byte(Acc, Addr, Value)
        end,
        z80_mem:new(65536),
        lists:zip(lists:seq(0, length(Bytes) - 1), Bytes)
    );
normalize_program(Program) when is_binary(Program) ->
    Bytes = binary_to_list(Program),
    lists:foldl(
        fun({Addr, Value}, Acc) ->
            z80_mem:write_byte(Acc, Addr, Value)
        end,
        z80_mem:new(65536),
        lists:zip(lists:seq(0, length(Bytes) - 1), Bytes)
    ).

%% @doc Execute one machine step by advancing the CPU once and updating machine time.
-spec step(#machine_state{}) -> #machine_state{}.
step(Machine) ->
    Cpu0 = Machine#machine_state.cpu,
    %% Directly invoke z80_cpu:step/1 with the full machine state
    Machine1 = z80_cpu:step(Machine),
    Cpu1 = Machine1#machine_state.cpu,
    Ticks = Cpu1#cpu_state.t_states - Cpu0#cpu_state.t_states,
    %% Synchronize global system T-states counter
    Machine1#machine_state{
        t_states = Machine1#machine_state.t_states + Ticks
    }.

%% @doc Advance the machine until the accumulated T-state budget is reached.
-spec run_until_tstates(#machine_state{}, non_neg_integer()) -> #machine_state{}.
run_until_tstates(Machine, Target) when is_integer(Target), Target =< 0 ->
    Machine;
run_until_tstates(Machine, Target) ->
    case Machine#machine_state.t_states >= Target of
        true -> Machine;
        false -> run_until_tstates(step(Machine), Target)
    end.
