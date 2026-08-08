-module(ezx_sup).

-behaviour(supervisor).

%% API
-export([start_link/0]).

%% Supervisor callbacks
-export([init/1]).

%% Helper macro for declaring children of supervisor

%% ===================================================================
%% API functions
%% ===================================================================

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%% ===================================================================
%% Supervisor callbacks
%% ===================================================================

init([]) ->
    %% ezx_ui is transient: a normal close (wxClose / menu exit) must shut
    %% down silently, while a crash still restarts the UI. permanent would
    %% print a SUPERVISOR REPORT (child_terminated / restart intensity) on
    %% every app close.
    UiChild = {ezx_ui, {ezx_ui, start_link, []}, transient, 5000, worker, [ezx_ui]},
    Children = [
        UiChild
    ],
    {ok, { {one_for_one, 0, 1}, Children} }.

