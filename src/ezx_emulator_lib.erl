-module(ezx_emulator_lib).

-export([match_port/2, read_port/4, write_port/5]).

%% =====================================================================
%% Declarative port dispatch.
%%
%% The ZX Spectrum decodes I/O ports at the hardware level as a
%% conjunction of address lines: some lines must be high, some must be
%% low, the rest are don't-care. A port handler table is a list of such
%% selectors:
%%
%%   {ZeroMask, OneMask, Handler}
%%
%% Port matches when every bit of ZeroMask is clear and every bit of
%% OneMask is set (other bits are ignored). Entries are tried in order,
%% first match wins, so the order is the priority (e.g. keyboard before
%% AY). A handler may decline with `nomatch' to fall through to the next
%% entry (used by optional devices such as the Kempston mouse).
%%
%% Read handlers: fun(ExtContext, TState, Port) -> nomatch | {Byte, ExtContext}
%% Write handlers: fun(ExtContext, TState, Port, Byte) -> nomatch | ExtContext
%%
%% Unhandled ports read 16#FF and ignore writes, matching the floating
%% data bus / unmapped peripheral behaviour.
%% =====================================================================

%% @doc True when Port has every bit of OneMask set and every bit of
%% ZeroMask clear.
-spec match_port({non_neg_integer(), non_neg_integer()}, non_neg_integer()) -> boolean().
match_port({Zero, One}, Port) ->
    Port band Zero =:= 0 andalso Port band One =:= One.

%% @doc Dispatch a port read through the table, returning {Byte, ExtContext}.
-spec read_port([{non_neg_integer(), non_neg_integer(), fun()}], any(), non_neg_integer(),
                non_neg_integer()) -> {0..255, any()}.
read_port(Table, ExtContext, TState, Port) ->
    read_port_1(Table, ExtContext, TState, Port).

read_port_1([], ExtContext, _TState, _Port) ->
    {16#FF, ExtContext};
read_port_1([{Zero, One, Handler} | Rest], ExtContext, TState, Port) ->
    case match_port({Zero, One}, Port) of
        true ->
            case Handler(ExtContext, TState, Port) of
                nomatch -> read_port_1(Rest, ExtContext, TState, Port);
                {Byte, Ctx1} -> {Byte, Ctx1}
            end;
        false ->
            read_port_1(Rest, ExtContext, TState, Port)
    end.

%% @doc Dispatch a port write through the table, returning the updated
%% ExtContext. Unhandled ports are ignored.
-spec write_port([{non_neg_integer(), non_neg_integer(), fun()}], any(), non_neg_integer(),
                 non_neg_integer(), 0..255) -> any().
write_port(Table, ExtContext, TState, Port, Byte) ->
    write_port_1(Table, ExtContext, TState, Port, Byte).

write_port_1([], ExtContext, _TState, _Port, _Byte) ->
    ExtContext;
write_port_1([{Zero, One, Handler} | Rest], ExtContext, TState, Port, Byte) ->
    case match_port({Zero, One}, Port) of
        true ->
            case Handler(ExtContext, TState, Port, Byte) of
                nomatch -> write_port_1(Rest, ExtContext, TState, Port, Byte);
                Ctx1 -> Ctx1
            end;
        false ->
            write_port_1(Rest, ExtContext, TState, Port, Byte)
    end.
