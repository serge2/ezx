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

%% Audio: 44100 Hz * 2 bytes = 88200 bytes/sec
-define(AUDIO_RATE, 88200).
-define(BYTES_PER_FRAME, 1764).  %% 882 samples * 2 bytes

-record(state, {
    machine   :: #machine_state{},
    frame     :: wxFrame:wxFrame(),
    panel     :: wxPanel:wxPanel(),
    bitmap    :: wxBitmap:wxBitmap() | undefined,
    scale = ?DEFAULT_SCALE :: pos_integer(),
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
                                  bitmap = OldBitmap, frame_count = FC0,
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
        W = ?DEFAULT_WIDTH * Scale,
        H = ?DEFAULT_HEIGHT * Scale,
        ScaledImage = wxImage:scale(Image, W, H),
        NewBitmap = wxBitmap:new(ScaledImage),
        wxImage:destroy(ScaledImage),
        case OldBitmap of undefined -> ok; _ -> wxBitmap:destroy(OldBitmap) end,
        DC = wxClientDC:new(Panel),
        wxDC:drawBitmap(DC, NewBitmap, {0, 0}),
        wxClientDC:destroy(DC),

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

