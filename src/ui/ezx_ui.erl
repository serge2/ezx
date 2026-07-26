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
-define(MENU_RESET, 3001).
-define(MENU_CROP_EXACT, 4001).
-define(MENU_CROP, 4002).

%% Audio: 44100 Hz * 2 bytes = 88200 bytes/sec
-define(AUDIO_RATE, 88200).
-define(BYTES_PER_FRAME, 1764).  %% 882 samples * 2 bytes

-record(state, {
    machine   :: #machine_state{},
    frame     :: wxFrame:wxFrame(),
    panel     :: wxPanel:wxPanel(),
    scale = ?DEFAULT_SCALE :: pos_integer(),
    fullscreen = false :: boolean(),
    option_crop_border = true :: boolean(),
    crop_off = {0, 0} :: {integer(), integer()},
    option_integer_scaling = false :: boolean(),
    crop_exact_scale = 1.0 :: float(),
    fullscreen_size = undefined :: {pos_integer(), pos_integer()} | undefined,
    windowed_size = undefined :: {pos_integer(), pos_integer()} | undefined,
    frame_count = 0 :: non_neg_integer(),
    aplay_port :: port() | undefined,
    audio_start_us = 0 :: non_neg_integer(),
    audio_bytes = 0 :: non_neg_integer(),
    perf_acc_us = 0 :: non_neg_integer(),
    render_acc_us = 0 :: non_neg_integer(),
    beeper_acc_us = 0 :: non_neg_integer(),
    perf_frames = 0 :: non_neg_integer(),
    perf_start_us = 0 :: non_neg_integer()
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
                        [{size, {272 * ?DEFAULT_SCALE, 208 * ?DEFAULT_SCALE}},
                         {style, ?wxDEFAULT_FRAME_STYLE band (bnot ?wxRESIZE_BORDER)}]),
    MenuBar = wxMenuBar:new(),
    FileMenu = wxMenu:new(),
    wxMenu:append(FileMenu, ?wxID_OPEN, "Load file\tCtrl+O", [{help, "Load a .sna or .tap file"}]),
    wxMenu:appendSeparator(FileMenu),
    wxMenu:append(FileMenu, ?wxID_EXIT, "Quit\tCtrl+Q", [{help, "Exit emulator"}]),
    wxMenuBar:append(MenuBar, FileMenu, "File"),
    ViewMenu = wxMenu:new(),
    wxMenu:append(ViewMenu, ?MENU_FULLSCREEN, "Fullscreen\tF11", [{help, "Toggle fullscreen mode"}]),
    wxMenuBar:append(MenuBar, ViewMenu, "View"),
    ActionsMenu = wxMenu:new(),
    wxMenu:append(ActionsMenu, ?MENU_RESET, "Reset\tF5", [{help, "Reset the emulator"}]),
    wxMenuBar:append(MenuBar, ActionsMenu, "Actions"),
    OptionsMenu = wxMenu:new(),
    wxMenu:appendCheckItem(OptionsMenu, ?MENU_CROP, "Crop borders", [{help, "Crop display borders in fullscreen mode"}]),
    wxMenu:check(OptionsMenu, ?MENU_CROP, true),
    wxMenu:appendCheckItem(OptionsMenu, ?MENU_CROP_EXACT, "Exact crop scaling", [{help, "Use fractional scale with bilinear smoothing in crop mode"}]),
    wxMenuBar:append(MenuBar, OptionsMenu, "Options"),
    wxFrame:setMenuBar(Frame, MenuBar),
    wxFrame:connect(Frame, command_menu_selected),

    Panel = wxPanel:new(Frame),
    wxWindow:setBackgroundStyle(Panel, ?wxBG_STYLE_PAINT),
    wxPanel:connect(Panel, key_down),
    wxPanel:connect(Panel, key_up),
    wxFrame:connect(Frame, close_window),
    wxFrame:show(Frame),
    wxWindow:setClientSize(Frame, 272 * ?DEFAULT_SCALE, 208 * ?DEFAULT_SCALE),
    wxWindow:setFocus(Panel),

    Cmd = "aplay -t raw -f S16_LE -r 44100 -c 1 --buffer-size=441 -q",
    AplayPort = open_port({spawn, Cmd}, [binary, stream, exit_status]),

    Machine0 = init_virtual_machine(),
    Machine1 = run_initial_frames(Machine0, 50),

    Now = erlang:monotonic_time(microsecond),
    State = #state{
        machine = Machine1,
        frame = Frame,
        panel = Panel,
        frame_count = 50,
        aplay_port = AplayPort,
        audio_start_us = Now,
        perf_start_us = Now
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
                                  aplay_port = Port, audio_start_us = StartUs0,
                                  perf_acc_us = PerfAcc0, render_acc_us = RenderAcc0, beeper_acc_us = BeeperAcc0,
                                  perf_frames = PerfFrames0, perf_start_us = PerfStart0} = State) ->
    try
        PerfT0 = erlang:monotonic_time(microsecond),
        Machine2 = ezx_emulator:run_frame(Machine0),
        PerfT1 = erlang:monotonic_time(microsecond),


        BeepT0 = erlang:monotonic_time(microsecond),
        {PCM, Machine3} = ezx_emulator:render_beeper(Machine2),
        BeepT1 = erlang:monotonic_time(microsecond),
        % Machine3 = Machine2,
        % PCM = Machine3#machine_state.beeper_pcm,


        %% Write audio to port
        port_command(Port, PCM),
        ByteSize = byte_size(PCM),
        Now = erlang:monotonic_time(microsecond),

       
        FC = FC0 + 1,
        RenderT0 = erlang:monotonic_time(microsecond),
        RGB = ezx_emulator:render_frame(Machine3),
        % RGB = Machine3#machine_state.screen,
        RenderT1 = erlang:monotonic_time(microsecond),

        Image0 = wxImage:new(352, 288, RGB),

        ClientDC = wxClientDC:new(Panel),
        {PW0, PH0} = wxWindow:getClientSize(Panel),
        {PW, PH} = case State#state.fullscreen_size of
            {SW, SH} -> {SW, SH};
            undefined -> {PW0, PH0}
        end,
        BmpDC = wxMemoryDC:new(),
        BufDC = wxBufferedDC:new(ClientDC, {PW, PH}),
        wxDC:setBackground(BufDC, wxBrush:new({0, 0, 0})),
        wxDC:clear(BufDC),

        UseExact = State#state.fullscreen andalso State#state.option_crop_border andalso State#state.option_integer_scaling,
        WindowedCrop = not State#state.fullscreen andalso State#state.option_crop_border,
        {Bmp, DX, DY, UseBmpScale} = case {UseExact, WindowedCrop} of
            {true, _} ->
                ES = State#state.crop_exact_scale,
                B = wxBitmap:new(Image0),
                wxImage:destroy(Image0),
                BorderOff = round(40 * ES),
                {FSW, FSH} = State#state.fullscreen_size,
                case FSW / ?DEFAULT_WIDTH >= FSH / ?DEFAULT_HEIGHT of
                    true  ->
                        DDX = (PW - round(?DEFAULT_WIDTH * ES)) div 2,
                        {B, DDX, -BorderOff, ES};
                    false ->
                        DDY = (PH - round(?DEFAULT_HEIGHT * ES)) div 2,
                        {B, -BorderOff, DDY, ES}
                end;
            {_, true} ->
                B = wxBitmap:new(Image0),
                wxImage:destroy(Image0),
                BorderOff = 40 * Scale,
                {B, -BorderOff, -BorderOff, Scale};
            {false, false} ->
                B = wxBitmap:new(Image0),
                wxImage:destroy(Image0),
                {OffX, OffY} = State#state.crop_off,
                DDX = max(0, (PW - ?DEFAULT_WIDTH * Scale) div 2),
                DDY = max(0, (PH - ?DEFAULT_HEIGHT * Scale) div 2),
                {B, DDX - OffX * Scale, DDY - OffY * Scale, Scale}
        end,
        wxMemoryDC:selectObject(BmpDC, Bmp),
        wxDC:setDeviceOrigin(BufDC, DX, DY),
        wxDC:setUserScale(BufDC, UseBmpScale, UseBmpScale),
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

        PerfAcc = PerfAcc0 + (PerfT1 - PerfT0),
        RenderAcc = RenderAcc0 + (RenderT1 - RenderT0),
        BeeperAcc = BeeperAcc0 + (BeepT1 - BeepT0),
        PerfFrames = PerfFrames0 + 1,
        {PerfFramesN, PerfAccN, RenderAccN, BeeperAccN, PerfStartN} =
            case Now - PerfStart0 >= 5000000 of
                true ->
                    AvgPerf = PerfAcc / PerfFrames,
                    AvgRender = RenderAcc / PerfFrames,
                    AvgBeeper = BeeperAcc / PerfFrames,
                    io:format("ezx perf: ~p frames in ~.1f s | emulation ~.2f ms  render ~.2f ms  beeper ~.2f ms total ~.2f ms~n",
                              [PerfFrames, (Now - PerfStart0) / 1000000,
                               AvgPerf / 1000, AvgRender / 1000, AvgBeeper / 1000, (AvgPerf + AvgRender + AvgBeeper) / 1000]),
                    {0, 0, 0, 0, Now};
                false ->
                    {PerfFrames, PerfAcc, RenderAcc, BeeperAcc, PerfStart0}
            end,

        {noreply, State#state{machine = Machine3, frame_count = FC,
                              audio_start_us = StartUs, audio_bytes = Written,
                              perf_acc_us = PerfAccN, render_acc_us = RenderAccN, beeper_acc_us = BeeperAccN,
                              perf_frames = PerfFramesN, perf_start_us = PerfStartN}}
    catch
        C:E:ST ->
            io:format("Frame error: ~p:~p~n~p~n", [C, E, ST]),
            erlang:send_after(20, self(), frame_tick),
            {noreply, State}
    end;

handle_info(#wx{event = #wxClose{}}, State) ->
    init:stop(),
    {stop, normal, State};

handle_info(#wx{event = #wxKey{type = key_down, keyCode = ?WXK_F11}}, State) ->
    toggle_fullscreen(State);

handle_info(#wx{event = #wxKey{type = key_down, keyCode = ?WXK_ESCAPE}},
            #state{fullscreen = true} = State) ->
    toggle_fullscreen(State);

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
                            ".sna" ->
                                ezx_emulator:load_sna(State#state.machine, Data);
                            ".tap" -> 
                                Machine0 = init_virtual_machine(),
                                Machine1 = run_initial_frames(Machine0, 50),
                                ezx_emulator:load_tap(Machine1, Data);
                            _ ->
                                io:format("Unknown file type: ~s~n", [File]),
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
    toggle_fullscreen(State);

handle_info(#wx{id = ?MENU_RESET, event = #wxCommand{type = command_menu_selected}}, State) ->
    do_reset(State);

handle_info(#wx{id = ?MENU_CROP, event = #wxCommand{type = command_menu_selected}}, State) ->
    NewCrop = not State#state.option_crop_border,
    NewState = State#state{option_crop_border = NewCrop},
    case NewState#state.fullscreen of
        true  -> reenter_crop_fullscreen(NewState);
        false ->
            Frame = NewState#state.frame,
            S = NewState#state.scale,
            {W, H} = windowed_client_size(NewCrop, S),
            wxWindow:setClientSize(Frame, W, H),
            {noreply, NewState}
    end;

handle_info(#wx{id = ?MENU_CROP_EXACT, event = #wxCommand{type = command_menu_selected}}, State) ->
    NewExact = not State#state.option_integer_scaling,
    NewState = State#state{option_integer_scaling = NewExact},
    case NewState#state.fullscreen of
        true  -> reenter_crop_fullscreen(NewState);
        false -> {noreply, NewState}
    end;

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, #state{frame = Frame, aplay_port = Port}) ->
    catch port_close(Port),
    wxFrame:destroy(Frame),
    ok.

%% --- Internal ---

do_reset(State) ->
    Machine0 = init_virtual_machine(),
    Machine1 = run_initial_frames(Machine0, 50),
    Now = erlang:monotonic_time(microsecond),
    {noreply, State#state{machine = Machine1, frame_count = 50,
                          audio_start_us = Now, audio_bytes = 0,
                          perf_acc_us = 0, render_acc_us = 0,
                          perf_frames = 0, perf_start_us = Now}}.

reenter_crop_fullscreen(#state{frame = Frame, fullscreen_size = {SW, SH}} = State) ->
    wxFrame:showFullScreen(Frame, false),
    wxFrame:showFullScreen(Frame, true),
    {NewScale, OffX, OffY} = calc_scale_offset(true, SW, SH),
    ExactScale = case State#state.option_integer_scaling of
        true  ->
            case SW / ?DEFAULT_WIDTH >= SH / ?DEFAULT_HEIGHT of
                true  -> SH / (?DEFAULT_HEIGHT - 80);
                false -> SW / (?DEFAULT_WIDTH - 80)
            end;
        false -> 1.0
    end,
    {noreply, State#state{scale = NewScale, crop_off = {OffX, OffY},
                          crop_exact_scale = ExactScale}}.

toggle_fullscreen(#state{frame = Frame, fullscreen = false, option_crop_border = Crop} = State) ->
    WinSize = wxWindow:getSize(Frame),
    wxFrame:showFullScreen(Frame, true),
    Display = wxDisplay:new(),
    {_, _, SW, SH} = wxDisplay:getGeometry(Display),
    wxDisplay:destroy(Display),
    {NewScale, OffX, OffY} = calc_scale_offset(Crop, SW, SH),
    ExactScale = case Crop andalso State#state.option_integer_scaling of
        true  ->
            case SW / ?DEFAULT_WIDTH >= SH / ?DEFAULT_HEIGHT of
                true  -> SH / (?DEFAULT_HEIGHT - 80);   %% wide screen: 208 visible rows (8px border T+B)
                false -> SW / (?DEFAULT_WIDTH - 80)     %% tall screen: 272 visible cols (8px border L+R)
            end;
        false -> 1.0
    end,
    {noreply, State#state{fullscreen = true,
                          scale = NewScale, crop_off = {OffX, OffY},
                          crop_exact_scale = ExactScale,
                          fullscreen_size = {SW, SH},
                          windowed_size = WinSize}};
toggle_fullscreen(#state{frame = Frame, fullscreen = true,
                         windowed_size = {WW, WH}} = State) ->
    wxFrame:showFullScreen(Frame, false),
    wxFrame:setSize(Frame, WW, WH),
    {noreply, State#state{fullscreen = false,
                          scale = ?DEFAULT_SCALE, crop_off = {0, 0},
                          fullscreen_size = undefined,
                          windowed_size = undefined}}.

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

%% Client area size for windowed mode.
windowed_client_size(Crop, S) ->
    {TW, TH} = case Crop of
        true  -> {272, 208};
        false -> {?DEFAULT_WIDTH, ?DEFAULT_HEIGHT}
    end,
    {TW * S, TH * S}.

run_initial_frames(Machine, 0) -> Machine;
run_initial_frames(Machine, N) ->
    Machine2 = ezx_emulator:run_frame(Machine),
    run_initial_frames(Machine2, N - 1).

init_virtual_machine() ->
    RomPath = try filename:join([code:priv_dir(ezx), "roms", "48.rom"])
    catch error:badarg ->
        %% Fallback: priv is a sibling of ebin in the OTP lib structure
        BeamDir = filename:dirname(code:which(?MODULE)),
        filename:join([filename:dirname(BeamDir), "priv", "roms", "48.rom"])
    end,
    {ok, Rom} = file:read_file(RomPath),
    ezx_emulator:init(z80_cpu, ezx_memory_48_array4, ezx_video2, ezx_keyboard, ezx_beeper, Rom).