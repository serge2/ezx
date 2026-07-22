-module(ezx_ui).

-behaviour(gen_server).

-include_lib("wx/include/wx.hrl").
-include("z80_records.hrl").
-include("ezx_emulator.hrl").

-export([start/0, start_link/0, stop/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-define(DEFAULT_WIDTH, 352).
-define(DEFAULT_HEIGHT, 288).
-define(DEFAULT_SCALE, 2).
-define(FCREPORT_INTERVAL, 100).

-define(wxID_LOAD_TAP, 6000).

%% Audio: 44100 Hz * 2 bytes = 88200 bytes/sec
-define(AUDIO_RATE, 88200).
-define(BYTES_PER_FRAME, 1764).  %% 882 samples * 2 bytes

-record(state, {
    machine   :: #machine_state{},
    frame     :: wxFrame:wxFrame(),
    panel     :: wxPanel:wxPanel(),
    bitmap    :: wxBitmap:wxBitmap() | undefined,
    scale = ?DEFAULT_SCALE :: pos_integer(),
    keyboard  :: tuple(),
    frame_count = 0 :: non_neg_integer(),
    aplay_port :: port() | undefined,
    audio_start_us = 0 :: non_neg_integer(),
    audio_bytes = 0 :: non_neg_integer()
}).


start() ->
    gen_server:start({local, ?MODULE}, ?MODULE, [], []).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

stop() ->
    gen_server:stop(?MODULE).

init(_Options) ->
    wx:new(),
    Machine0 = ezx_emulator:init(),
    {Machine1, FC} = run_initial_frames(Machine0, 50),
    Keyboard = ?KEYBOARD_DEFAULT,
    Machine2 = ezx_emulator:set_keyboard(Machine1, Keyboard),

    Frame = wxFrame:new(wx:null(), -1, "ezx - ZX Spectrum emulator",
                        [{size, {?DEFAULT_WIDTH * ?DEFAULT_SCALE,
                                 ?DEFAULT_HEIGHT * ?DEFAULT_SCALE}}]),
    MenuBar = wxMenuBar:new(),
    FileMenu = wxMenu:new(),
    wxMenu:append(FileMenu, ?wxID_OPEN, "Load SNA\tCtrl+O", [{help, "Load a .sna snapshot"}]),
    wxMenu:append(FileMenu, ?wxID_LOAD_TAP, "Load TAP\tCtrl+T", [{help, "Load a .tap tape file"}]),
    wxMenu:appendSeparator(FileMenu),
    wxMenu:append(FileMenu, ?wxID_EXIT, "Quit\tCtrl+Q", [{help, "Exit emulator"}]),
    wxMenuBar:append(MenuBar, FileMenu, "File"),
    wxFrame:setMenuBar(Frame, MenuBar),
    wxFrame:connect(Frame, command_menu_selected),

    Panel = wxPanel:new(Frame),
    wxWindow:setBackgroundStyle(Panel, ?wxBG_STYLE_PAINT),
    wxPanel:connect(Panel, key_down),
    wxPanel:connect(Panel, key_up),
    wxFrame:connect(Frame, close_window),
    wxFrame:show(Frame),
    wxWindow:setFocus(Panel),

    Cmd = "aplay -t raw -f S16_LE -r 44100 -c 1 --buffer-size=441 -q",
    AplayPort = open_port({spawn, Cmd}, [binary, stream, exit_status]),

    State = #state{
        machine = Machine2,
        frame = Frame,
        panel = Panel,
        keyboard = Keyboard,
        frame_count = FC,
        aplay_port = AplayPort
    },
    erlang:send_after(0, self(), frame_tick),
    {ok, State}.

handle_call(_Request, _From, State) ->
    {reply, ok, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(frame_tick, #state{machine = Machine0, panel = Panel,
                                  scale = Scale, keyboard = Keyboard,
                                  bitmap = OldBitmap, frame_count = FC0,
                                  aplay_port = Port} = State) ->
    try
        Machine1 = ezx_emulator:set_keyboard(Machine0, Keyboard),
        Machine2 = ezx_emulator:run_frame(Machine1),
        PCM = Machine2#machine_state.beeper_pcm,

        %% Write audio to port
        port_command(Port, PCM),
        ByteSize = byte_size(PCM),
        Now = erlang:monotonic_time(microsecond),

       
        FC = FC0 + 1,
        Changes = Machine2#machine_state.border_changes,
        CB = Machine2#machine_state.border_color,
        Mem = Machine2#machine_state.memory,
        ReadFun = fun(Addr) -> ezx_memory_48:read_byte(Mem, Addr band 16#FFFF) end,
        FrameData = ezx_video:decode_full_frame(ReadFun, FC, lists:reverse(Changes), CB),
        Image = frame_to_image(FrameData),
        W = ?DEFAULT_WIDTH * Scale,
        H = ?DEFAULT_HEIGHT * Scale,
        ScaledImage = wxImage:scale(Image, W, H),
        NewBitmap = wxBitmap:new(ScaledImage),
        wxImage:destroy(ScaledImage),
        case OldBitmap of undefined -> ok; _ -> wxBitmap:destroy(OldBitmap) end,
        DC = wxClientDC:new(Panel),
        wxDC:drawBitmap(DC, NewBitmap, {0, 0}),
        wxClientDC:destroy(DC),


        %% Initialize audio clock on first write
        StartUs0 = case State#state.audio_start_us of
            0 -> Now;
            S -> S
        end,

        %% Estimate buffer level: bytes written - bytes consumed
        Written0 = State#state.audio_bytes + ByteSize,
        ElapsedUs = Now - StartUs0,
        BytesConsumed = ElapsedUs * ?AUDIO_RATE div 1000000,
        BufferLevel0 = Written0 - BytesConsumed,

        %% If there was a long gap (dialog/snapshot load), reset the clock.
        %% Buffer going very negative means our estimate is stale.
        {StartUs, Written, BufferLevel} =
            case BufferLevel0 < -(?BYTES_PER_FRAME * 2) of
                true ->
                    {Now, ByteSize, ByteSize};
                false ->
                    {StartUs0, Written0, BufferLevel0}
            end,

        case FC rem ?FCREPORT_INTERVAL of
            0 ->
                io:format("Frame ~p: buffer_level=~p bytes~n",
                          [FC, BufferLevel]);
            _ -> ok
        end,

        %% Schedule next frame: when buffer drops to ~3 frames worth
        %% (absorbs GC pauses and delivery jitter without audible latency)
        Surplus = BufferLevel - (?BYTES_PER_FRAME * 3),
        case Surplus > 0 of
            true ->
                MsUntilLow = Surplus * 1000 div ?AUDIO_RATE,
                erlang:send_after(max(1, MsUntilLow), self(), frame_tick);
            false ->
                erlang:send_after(0, self(), frame_tick)
        end,

        {noreply, State#state{machine = Machine2, bitmap = NewBitmap, frame_count = FC,
                              audio_start_us = StartUs, audio_bytes = Written}}
    catch
        C:E:ST ->
            io:format("Frame error: ~p:~p~n~p~n", [C, E, ST]),
            erlang:send_after(20, self(), frame_tick),
            {noreply, State}
    end;

handle_info(#wx{event = #wxClose{}}, State) ->
    init:stop(),
    {stop, normal, State};

handle_info(#wx{event = #wxKey{type = key_down, keyCode = Key, rawCode = _RawCode} = _E}, State) ->
    Keyboard = press_key(State#state.keyboard, Key),
    {noreply, State#state{keyboard = Keyboard}};

handle_info(#wx{event = #wxKey{type = key_up, keyCode = Key, rawCode = _RawCode} = _E}, State) ->
    Keyboard = release_key(State#state.keyboard, Key),
    {noreply, State#state{keyboard = Keyboard}};

handle_info(#wx{id = ?wxID_OPEN, event = #wxCommand{type = command_menu_selected}}, State) ->
    Dialog = wxFileDialog:new(State#state.frame, [{message, "Load SNA snapshot"},
                                                   {wildCard, "SNA files (*.sna)|*.sna"},
                                                   {style, ?wxFD_OPEN bor ?wxFD_FILE_MUST_EXIST}]),
    case wxFileDialog:showModal(Dialog) of
        ?wxID_OK ->
            File = wxFileDialog:getPath(Dialog),
            wxFileDialog:destroy(Dialog),
            case file:read_file(File) of
                {ok, Data} ->
                    try
                        NewMachine = ezx_emulator:load_sna(State#state.machine, Data),
                        io:format("Loaded snapshot: ~s~n", [File]),
                        {noreply, State#state{machine = NewMachine}}
                    catch
                        C:E:S ->
                            io:format("Failed to load snapshot: ~s~n  ~p:~p~n~p~n", [File, C, E, S]),
                            {noreply, State}
                    end;
                _ ->
                    io:format("Failed to read file: ~s~n", [File]),
                    {noreply, State}
            end;
        _ ->
            wxFileDialog:destroy(Dialog),
            {noreply, State}
    end;

handle_info(#wx{id = ?wxID_EXIT, event = #wxCommand{type = command_menu_selected}}, State) ->
    {stop, normal, State};

handle_info(#wx{id = ?wxID_LOAD_TAP, event = #wxCommand{type = command_menu_selected}}, State) ->
    Dialog = wxFileDialog:new(State#state.frame, [{message, "Load TAP tape file"},
                                                   {wildCard, "TAP files (*.tap)|*.tap"},
                                                   {style, ?wxFD_OPEN bor ?wxFD_FILE_MUST_EXIST}]),
    case wxFileDialog:showModal(Dialog) of
        ?wxID_OK ->
            File = wxFileDialog:getPath(Dialog),
            wxFileDialog:destroy(Dialog),
            case file:read_file(File) of
                {ok, Data} ->
                    try
                        NewMachine = ezx_emulator:load_tap(State#state.machine, Data),
                        io:format("Loaded TAP: ~s~n", [File]),
                        {noreply, State#state{machine = NewMachine}}
                    catch
                        C:E:S ->
                            io:format("Failed to load TAP: ~s~n  ~p:~p~n~p~n", [File, C, E, S]),
                            {noreply, State}
                    end;
                _ ->
                    io:format("Failed to read file: ~s~n", [File]),
                    {noreply, State}
            end;
        _ ->
            wxFileDialog:destroy(Dialog),
            {noreply, State}
    end;

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, #state{frame = Frame, bitmap = Bitmap, aplay_port = Port}) ->
    catch port_close(Port),
    case Bitmap of undefined -> ok; _ -> wxBitmap:destroy(Bitmap) end,
    wxFrame:destroy(Frame),
    ok.

%% --- Internal ---

run_initial_frames(Machine, 0) -> {Machine, 0};
run_initial_frames(Machine, N) ->
    {M, FC} = run_initial_frames(Machine, N - 1),
    {ezx_emulator:run_frame(M), FC + 1}.

frame_to_image(Frame) ->
    Height = length(Frame),
    Width = length(hd(Frame)),
    RGB = << <<R, G, B>> || Row <- Frame, {R, G, B} <- Row >>,
    wxImage:new(Width, Height, RGB).

%% --- ZX Spectrum keyboard matrix ---

key_map() ->
    #{
        306  => {1, 0},
        $Z   => {1, 1},
        $X   => {1, 2},
        $C   => {1, 3},
        $V   => {1, 4},

        $A   => {2, 0},
        $S   => {2, 1},
        $D   => {2, 2},
        $F   => {2, 3},
        $G   => {2, 4},

        $Q   => {3, 0},
        $W   => {3, 1},
        $E   => {3, 2},
        $R   => {3, 3},
        $T   => {3, 4},

        $1   => {4, 0},
        $2   => {4, 1},
        $3   => {4, 2},
        $4   => {4, 3},
        $5   => {4, 4},

        $0   => {5, 0},
        $9   => {5, 1},
        $8   => {5, 2},
        $7   => {5, 3},
        $6   => {5, 4},

        $P   => {6, 0},
        $O   => {6, 1},
        $I   => {6, 2},
        $U   => {6, 3},
        $Y   => {6, 4},

        13   => {7, 0},
        $L   => {7, 1},
        $K   => {7, 2},
        $J   => {7, 3},
        $H   => {7, 4},

        32   => {8, 0},
        307  => {8, 1}, 0 => {8, 1},
        $M   => {8, 2},
        $N   => {8, 3},
        $B   => {8, 4}
    }.

press_key(Keyboard, WxKey) ->
    case maps:find(WxKey, key_map()) of
        {ok, {Row, Bit}} ->
            Old = element(Row, Keyboard),
            setelement(Row, Keyboard, Old band (bnot (1 bsl Bit)));
        error ->
            Keyboard
    end.

release_key(Keyboard, WxKey) ->
    case maps:find(WxKey, key_map()) of
        {ok, {Row, Bit}} ->
            Old = element(Row, Keyboard),
            setelement(Row, Keyboard, Old bor (1 bsl Bit));
        error ->
            Keyboard
    end.
