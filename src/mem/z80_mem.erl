-module(z80_mem).

-export([
    new/1,
    reset/1,
    read_byte/2,
    write_byte/3,
    read_word/2,
    write_word/3,
    read_all/1,
    read_instr/2
]).

-record(memory_state, {
    size = 0,
    initial_data = <<>>,
    data = <<>>
}).

-type memory() :: #memory_state{}.

-spec new(non_neg_integer()) -> memory().
new(MemSize) ->
    Size = max(0, MemSize),
    Data0 = binary:copy(<<0>>, Size),
    #memory_state{size = Size, initial_data = Data0, data = Data0}.

-spec reset(memory()) -> memory().
reset(State) ->
    State#memory_state{data = State#memory_state.initial_data}.

-spec read_byte(memory(), non_neg_integer()) -> byte().
read_byte(State, Addr) ->
    Index = Addr band 16#ffff,
    Data = State#memory_state.data,
    case Data of
        <<_:Index/binary, Byte:8/integer, _/binary>> -> Byte;
        _ -> 0
    end.

-spec write_byte(memory(), non_neg_integer(), byte()) -> memory().
write_byte(State, Addr, Byte) ->
    Index = Addr band 16#ffff,
    Size = byte_size(State#memory_state.data),
    if
        Index < Size ->
            <<Prefix:Index/binary, _Old:8/integer, Suffix/binary>> = State#memory_state.data,
            Data1 = <<Prefix/binary, (Byte band 16#ff):8/integer, Suffix/binary>>,
            State#memory_state{data = Data1};
        true ->
            State
    end.

-spec read_word(memory(), non_neg_integer()) -> non_neg_integer().
read_word(State, Addr) ->
    read_byte(State, Addr) + (read_byte(State, Addr + 1) bsl 8).

-spec write_word(memory(), non_neg_integer(), non_neg_integer()) -> memory().
write_word(State, Addr, Word) ->
    State1 = write_byte(State, Addr, Word band 16#ff),
    write_byte(State1, Addr + 1, (Word bsr 8) band 16#ff).

-spec read_all(memory()) -> memory().
read_all(State) ->
    State.

-spec read_instr(memory(), non_neg_integer()) -> [byte()].
read_instr(State, Addr) ->
    [read_byte(State, Addr), read_byte(State, Addr + 1), read_byte(State, Addr + 2), read_byte(State, Addr + 3)].

