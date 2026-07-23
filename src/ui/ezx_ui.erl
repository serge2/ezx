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
-define(MENU_FULLSCREEN, 2001).
-define(MENU_FULLSCREEN_CROP, 2002).
-define(MENU_RESET, 3001).

%% Audio: 44100 Hz * 2 bytes = 88200 bytes/sec
-define(AUDIO_RATE, 88200).
-define(BYTES_PER_FRAME, 1764).  %% 882 samples * 2 bytes

-record(state, {
    machine   :: #machine_state{},
    frame     :: wxFrame:wxFrame(),
    panel     :: wxPanel:wxPanel(),
    scale = ?DEFAULT_SCALE :: pos_integer(),
    fullscreen = false :: boolean(),
    fullscreen_crop = false :: boolean(),
    crop_off = {0, 0} :: {integer(), integer()},
    fullscreen_size = undefined :: {pos_integer(), pos_integer()} | undefined,
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

    Frame = wxFrame:new(wx:null(), -1, "ezx - ZX Spectrum emulator",
                        [{size, {?DEFAULT_WIDTH * ?DEFAULT_SCALE,
                                 ?DEFAULT_HEIGHT * ?DEFAULT_SCALE}}]),
    MenuBar = wxMenuBar:new(),
    FileMenu = wxMenu:new(),
    wxMenu:append(FileMenu, ?wxID_OPEN, "Load file\tCtrl+O", [{help, "Load a .sna or .tap file"}]),
    wxMenu:appendSeparator(FileMenu),
    wxMenu:append(FileMenu, ?wxID_EXIT, "Quit\tCtrl+Q", [{help, "Exit emulator"}]),
    wxMenuBar:append(MenuBar, FileMenu, "File"),
    ViewMenu = wxMenu:new(),
    wxMenu:append(ViewMenu, ?MENU_FULLSCREEN, "Fullscreen\tF11", [{help, "Toggle fullscreen mode"}]),
    wxMenu:append(ViewMenu, ?MENU_FULLSCREEN_CROP, "Fullscreen (crop borders)\tShift+F11", [{help, "Fullscreen with border crop"}]),
    wxMenuBar:append(MenuBar, ViewMenu, "View"),
    ActionsMenu = wxMenu:new(),
    wxMenu:append(ActionsMenu, ?MENU_RESET, "Reset\tF5", [{help, "Reset the emulator"}]),
    wxMenuBar:append(MenuBar, ActionsMenu, "Actions"),
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

    Machine0 = ezx_emulator:init(),
    {Machine1, FC} = run_initial_frames(Machine0, 50),

    State = #state{
        machine = Machine1,
        frame = Frame,
        panel = Panel,
        frame_count = FC,
        aplay_port = AplayPort,
        audio_start_us = erlang:monotonic_time(microsecond)
    },
    erlang:send_after(0, self(), frame_tick),
    {ok, State}.

handle_call(_Request, _From, State) ->
    {reply, ok, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(frame_tick, #state{machine = Machine0, panel = Panel,
                                  scale = Scale,
                                  frame_count = FC0,
                                  aplay_port = Port, audio_start_us = StartUs0} = State) ->
    try
        Machine2 = ezx_emulator:run_frame(Machine0),
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
        Bmp = wxBitmap:new(Image),
        wxImage:destroy(Image),

        ClientDC = wxClientDC:new(Panel),
        {PW0, PH0} = wxWindow:getClientSize(Panel),
        {PW, PH} = case State#state.fullscreen_size of
            {SW, SH} -> {SW, SH};
            undefined -> {PW0, PH0}
        end,
        BmpDC = wxMemoryDC:new(),
        wxMemoryDC:selectObject(BmpDC, Bmp),
        BufDC = wxBufferedDC:new(ClientDC, {PW, PH}),
        wxDC:setBackground(BufDC, wxBrush:new({0, 0, 0})),
        wxDC:clear(BufDC),
        {OffX, OffY} = State#state.crop_off,
        DX = max(0, (PW - ?DEFAULT_WIDTH * Scale) div 2),
        DY = max(0, (PH - ?DEFAULT_HEIGHT * Scale) div 2),
        wxDC:setDeviceOrigin(BufDC, DX - OffX * Scale, DY - OffY * Scale),
        wxDC:setUserScale(BufDC, Scale, Scale),
        wxDC:drawBitmap(BufDC, Bmp, {0, 0}),
        wxDC:setUserScale(BufDC, 1.0, 1.0),
        wxDC:setDeviceOrigin(BufDC, 0, 0),
        wxBufferedDC:destroy(BufDC),
        wxMemoryDC:destroy(BmpDC),
        wxClientDC:destroy(ClientDC),
        wxBitmap:destroy(Bmp),

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

        % case FC rem ?FCREPORT_INTERVAL of
        %     0 ->
        %         io:format("Frame ~p: buffer_level=~p bytes~n",
        %                   [FC, BufferLevel]);
        %     _ -> ok
        % end,

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

        {noreply, State#state{machine = Machine2, frame_count = FC,
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

handle_info(#wx{event = #wxKey{type = key_down, keyCode = ?WXK_F11, shiftDown = false}}, State) ->
    toggle_fullscreen(false, State);

handle_info(#wx{event = #wxKey{type = key_down, keyCode = ?WXK_F11, shiftDown = true}}, State) ->
    toggle_fullscreen(true, State);

handle_info(#wx{event = #wxKey{type = key_down, keyCode = ?WXK_ESCAPE}},
            #state{fullscreen = true} = State) ->
    toggle_fullscreen(false, State);

handle_info(#wx{event = #wxKey{type = key_down, keyCode = ?WXK_F5}}, State) ->
    do_reset(State);

handle_info(#wx{event = #wxKey{type = key_down, keyCode = Key, rawCode = _RawCode} = _E}, State) ->
    Machine = State#state.machine,
    NewMachine = ezx_emulator:press_key(Machine, Key),
    % io:format("Key down: ~p~n", [_E]),
    {noreply, State#state{machine = NewMachine}};

handle_info(#wx{event = #wxKey{type = key_up, keyCode = Key, rawCode = _RawCode} = _E}, State) ->
    Machine = State#state.machine,
    NewMachine = ezx_emulator:release_key(Machine, Key),
    % io:format("Key up: ~p~n", [_E]),
    {noreply, State#state{machine = NewMachine}};

handle_info(#wx{id = ?wxID_OPEN, event = #wxCommand{type = command_menu_selected}}, State) ->
    Dialog = wxFileDialog:new(State#state.frame, [{message, "Load snapshot or tape"},
                                                   {wildCard, "ZX Spectrum files (*.sna,*.tap)|*.sna;*.tap|SNA files (*.sna)|*.sna|TAP files (*.tap)|*.tap"},
                                                   {style, ?wxFD_OPEN bor ?wxFD_FILE_MUST_EXIST}]),
    case wxFileDialog:showModal(Dialog) of
        ?wxID_OK ->
            File = wxFileDialog:getPath(Dialog),
            wxFileDialog:destroy(Dialog),
            Ext = string:lowercase(filename:extension(File)),
            case file:read_file(File) of
                {ok, Data} ->
                    try
                        NewMachine = case Ext of
                            ".sna" -> ezx_emulator:load_sna(State#state.machine, Data);
                            ".tap" -> ezx_emulator:load_tap(State#state.machine, Data);
                            _ -> io:format("Unknown file type: ~s~n", [File]),
                                 State#state.machine
                        end,
                        io:format("Loaded: ~s~n", [File]),
                        {noreply, State#state{machine = NewMachine}}
                    catch
                        C:E:S ->
                            io:format("Failed to load: ~s~n  ~p:~p~n~p~n", [File, C, E, S]),
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
    init:stop(),    
    {stop, normal, State};

handle_info(#wx{id = ?MENU_FULLSCREEN, event = #wxCommand{type = command_menu_selected}}, State) ->
    toggle_fullscreen(false, State);

handle_info(#wx{id = ?MENU_FULLSCREEN_CROP, event = #wxCommand{type = command_menu_selected}}, State) ->
    toggle_fullscreen(true, State);

handle_info(#wx{id = ?MENU_RESET, event = #wxCommand{type = command_menu_selected}}, State) ->
    do_reset(State);

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, #state{frame = Frame, aplay_port = Port}) ->
    catch port_close(Port),
    wxFrame:destroy(Frame),
    ok.

%% --- Internal ---

do_reset(State) ->
    Machine0 = ezx_emulator:init(),
    {Machine1, FC} = run_initial_frames(Machine0, 50),
    {noreply, State#state{machine = Machine1, frame_count = FC,
                          audio_start_us = erlang:monotonic_time(microsecond),
                          audio_bytes = 0}}.

toggle_fullscreen(Crop, #state{frame = Frame, fullscreen = false} = State) ->
    wxFrame:showFullScreen(Frame, true),
    Display = wxDisplay:new(),
    {_, _, SW, SH} = wxDisplay:getGeometry(Display),
    wxDisplay:destroy(Display),
    {NewScale, OffX, OffY} = calc_scale_offset(Crop, SW, SH),
    {noreply, State#state{fullscreen = true, fullscreen_crop = Crop,
                          scale = NewScale, crop_off = {OffX, OffY},
                          fullscreen_size = {SW, SH}}};
toggle_fullscreen(_Crop, #state{frame = Frame, fullscreen = true} = State) ->
    wxFrame:showFullScreen(Frame, false),
    {noreply, State#state{fullscreen = false, fullscreen_crop = false,
                          scale = ?DEFAULT_SCALE, crop_off = {0, 0},
                          fullscreen_size = undefined}}.

%% {Scale, OffX, OffY} for emulated coordinates (352×288).
%% OffX/OffY in emulated pixels: visible window origin within the emulated frame.
%% Multiply by Scale to get screen-pixel shift of the device origin.
calc_scale_offset(false, SW, SH) ->
    S = max(1, min(SW div ?DEFAULT_WIDTH, SH div ?DEFAULT_HEIGHT)),
    {S, 0, 0};
calc_scale_offset(true, SW, SH) ->
    S = max(1, max(SW div ?DEFAULT_WIDTH, SH div ?DEFAULT_HEIGHT)),
    case SW / ?DEFAULT_WIDTH >= SH / ?DEFAULT_HEIGHT of
        true  -> {S, 0, (288 * S - SH) div (2 * S)};
        false -> {S, (352 * S - SW) div (2 * S), 0}
    end.

run_initial_frames(Machine, 0) -> {Machine, 0};
run_initial_frames(Machine, N) ->
    {M, FC} = run_initial_frames(Machine, N - 1),
    {ezx_emulator:run_frame(M), FC + 1}.

frame_to_image(Frame) ->
    Height = length(Frame),
    Width = length(hd(Frame)),
    RGB = << <<R, G, B>> || Row <- Frame, {R, G, B} <- Row >>,
    wxImage:new(Width, Height, RGB).

