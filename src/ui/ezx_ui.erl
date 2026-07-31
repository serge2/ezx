-module(ezx_ui).

-behaviour(gen_server).

-include_lib("wx/include/wx.hrl").
-include("z80_records.hrl").
-include("ezx_emulator.hrl").
-include("menu_ids.hrl").

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
-define(MENU_MUTE, 3002).

%% Audio: 44100 Hz * 2 channels * 2 bytes = 176400 bytes/sec
-define(AUDIO_RATE, 176400).
-define(BYTES_PER_FRAME, 3528).  %% 882 samples * 2 channels * 2 bytes

-record(state, {
    machine   :: #machine_state{} | undefined,
    machine_type = '48k' :: '48k' | '128k',
    frame     :: wxFrame:wxFrame(),
    panel     :: wxPanel:wxPanel(),
    scale = ?DEFAULT_SCALE :: pos_integer(),
    fullscreen = false :: boolean(),
    option_crop_border = true :: boolean(),
    windowed_scale = ?DEFAULT_SCALE :: pos_integer(),
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
    ay_acc_us = 0 :: non_neg_integer(),
    perf_frames = 0 :: non_neg_integer(),
    perf_start_us = 0 :: non_neg_integer(),
    muted = false :: boolean(),
    perf_report = false :: boolean(),
    menu_bar :: wxMenuBar:wxMenuBar(),
    recent_files = [] :: [string()],
    diag_file :: pid() | undefined,
    beeper_vol = 100 :: 0..100,
    ay_master_vol = 100 :: 0..100,
    ay_stereo_mode = acb :: acb | abc | mono,
    sound_dialog_refs = undefined :: {wxDialog:wxDialog(), wxSlider:wxSlider(), wxSlider:wxSlider(), wxChoice:wxChoice()} | undefined,
    file_dialog = undefined :: wxFileDialog:wxFileDialog() | undefined
}).


start() ->
    gen_server:start({local, ?MODULE}, ?MODULE, [], []).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

stop() ->
    gen_server:stop(?MODULE).

init(_Options) ->
    wx:new(),

    %% Pre-load config to get crop setting for initial window size
    Cfg0 = ezx_config:load(),
    CropBorder0 = maps:get(crop_border, Cfg0, true),
    InitScale0 = maps:get(scale, Cfg0, ?DEFAULT_SCALE),
    {InitW, InitH} = windowed_client_size(CropBorder0, InitScale0),
    Frame = wxFrame:new(wx:null(), -1, "ezx - ZX Spectrum emulator",
                        [{size, {InitW, InitH}},
                         {style, ?wxDEFAULT_FRAME_STYLE band (bnot ?wxRESIZE_BORDER)}]),
    MenuBar = wxMenuBar:new(),
    RecentFiles0 = ezx_recent_files:load(),
    FileMenu0 = ezx_recent_files:build_menu(RecentFiles0),
    wxMenuBar:append(MenuBar, FileMenu0, "File"),
    MachineType = maps:get(machine_type, Cfg0, '128k'),
    EmulatorMenu = wxMenu:new(),
    wxMenu:appendRadioItem(EmulatorMenu, ?MENU_MACHINE_BASE + 0, "ZX Spectrum 48K"),
    wxMenu:appendRadioItem(EmulatorMenu, ?MENU_MACHINE_BASE + 1, "ZX Spectrum 128K"),
    wxMenuBar:append(MenuBar, EmulatorMenu, "Emulator"),
    ViewMenu = wxMenu:new(),
    wxMenu:append(ViewMenu, ?MENU_FULLSCREEN, "Fullscreen\tF11", [{help, "Toggle fullscreen mode"}]),
    wxMenu:appendSeparator(ViewMenu),
    wxMenu:appendCheckItem(ViewMenu, ?MENU_CROP, "Crop borders", [{help, "Crop display borders"}]),
    wxMenu:appendCheckItem(ViewMenu, ?MENU_CROP_EXACT, "Integer scaling", [{help, "Use integer scale"}]),
    wxMenu:appendSeparator(ViewMenu),
    wxMenu:appendRadioItem(ViewMenu, ?MENU_SCALE_BASE + 0, "Scale 1x"),
    wxMenu:appendRadioItem(ViewMenu, ?MENU_SCALE_BASE + 1, "Scale 2x"),
    wxMenu:appendRadioItem(ViewMenu, ?MENU_SCALE_BASE + 2, "Scale 3x"),
    wxMenu:appendRadioItem(ViewMenu, ?MENU_SCALE_BASE + 3, "Scale 4x"),
    wxMenuBar:append(MenuBar, ViewMenu, "View"),
    SettingsMenu = wxMenu:new(),
    wxMenu:append(SettingsMenu, ?MENU_SETTINGS_SOUND, "Sound"),
    wxMenuBar:append(MenuBar, SettingsMenu, "Settings"),
    ActionsMenu = wxMenu:new(),
    wxMenu:append(ActionsMenu, ?MENU_RESET, "Reset\tF5", [{help, "Reset the emulator"}]),
    wxMenu:appendSeparator(ActionsMenu),
    wxMenu:appendCheckItem(ActionsMenu, ?MENU_MUTE, "Mute\tCtrl+M", [{help, "Toggle audio mute"}]),
    wxMenuBar:append(MenuBar, ActionsMenu, "Actions"),
    DebugMenu = wxMenu:new(),
    wxMenu:appendCheckItem(DebugMenu, ?MENU_DEBUG_PERF, "Performance report",
                           [{help, "Print performance stats to console every 5 seconds"}]),
    wxMenuBar:append(MenuBar, DebugMenu, "Debug"),
    wxFrame:setMenuBar(Frame, MenuBar),

    %% Apply saved config to menu checkmarks
    CropBorder = maps:get(crop_border, Cfg0, true),
    IntScaling = maps:get(integer_scaling, Cfg0, false),
    Muted = maps:get(muted, Cfg0, false),
    PerfReport = maps:get(perf_report, Cfg0, false),
    wxMenu:check(EmulatorMenu, ?MENU_MACHINE_BASE + machine_type_offset(MachineType), true),
    wxMenu:check(ViewMenu, ?MENU_CROP, CropBorder),
    wxMenu:check(ViewMenu, ?MENU_CROP_EXACT, IntScaling),
    wxMenu:check(ViewMenu, ?MENU_SCALE_BASE + (InitScale0 - 1), true),
    wxMenu:check(ActionsMenu, ?MENU_MUTE, Muted),
    wxMenu:check(DebugMenu, ?MENU_DEBUG_PERF, PerfReport),
    wxFrame:connect(Frame, command_menu_selected),

    Panel = wxPanel:new(Frame),
    wxWindow:setBackgroundStyle(Panel, ?wxBG_STYLE_PAINT),
    wxPanel:connect(Panel, key_down),
    wxPanel:connect(Panel, key_up),
    wxFrame:connect(Frame, close_window),
    wxFrame:show(Frame),
    {DefW, DefH} = windowed_client_size(CropBorder, InitScale0),
    wxWindow:setClientSize(Frame, DefW, DefH),
    wxWindow:setFocus(Panel),

    Cmd = "aplay -t raw -f S16_LE -r 44100 -c 2 --buffer-size=441 -q",
    AplayPort = open_port({spawn, Cmd}, [binary, stream, exit_status]),

    Now = erlang:monotonic_time(microsecond),
    BeeperVol = maps:get(beeper_vol, Cfg0, 100),
    AyVol = maps:get(ay_master_vol, Cfg0, 100),
    Mode = maps:get(ay_stereo_mode, Cfg0, acb),
    State0 = #state{
        machine = undefined,
        machine_type = MachineType,
        frame = Frame,
        panel = Panel,
        scale = InitScale0,
        option_crop_border = CropBorder,
        option_integer_scaling = IntScaling,
        muted = Muted,
        perf_report = PerfReport,
        beeper_vol = BeeperVol,
        ay_master_vol = AyVol,
        ay_stereo_mode = Mode,
        aplay_port = AplayPort,
        audio_start_us = Now,
        perf_start_us = Now,
        menu_bar = MenuBar,
        recent_files = RecentFiles0
    },
    case ezx_ui_lib:init_virtual_machine(MachineType) of
        {ok, Machine} ->
            erlang:send_after(0, self(), frame_tick),
            {ok, State0#state{machine = Machine}};
        {error, {Code, Detail}} ->
            Title = "ezx - ROM error",
            Msg = case Code of
                rom_not_found -> "ROM files not found.\n\nInstall ROMs in priv/roms/ and restart.";
                _ -> binary_to_list(Detail)
            end,
            Dialog = wxMessageDialog:new(Frame, Msg, [{caption, Title},
                                                       {style, ?wxOK bor ?wxICON_ERROR}]),
            wxDialog:showModal(Dialog),
            wxMessageDialog:destroy(Dialog),
            wxMenuBar:enableTop(MenuBar, 0, false),
            wxMenuBar:enableTop(MenuBar, 3, false),
            erlang:send_after(0, self(), frame_tick),
            {ok, State0}
    end.

handle_call(_Request, _From, State) ->
    {reply, ok, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(frame_tick, #state{machine = undefined} = State) ->
    erlang:send_after(50, self(), frame_tick),
    {noreply, State};

handle_info(frame_tick, #state{machine = Machine0, panel = Panel,
                                  scale = Scale,
                                  frame_count = FC0,
                                  aplay_port = Port, audio_start_us = StartUs0,
                                  perf_acc_us = PerfAcc0, render_acc_us = RenderAcc0,
                                  beeper_acc_us = BeeperAcc0, ay_acc_us = AyAcc0,
                                  perf_frames = PerfFrames0, perf_start_us = PerfStart0} = State) ->
    try
        PerfT0 = erlang:monotonic_time(microsecond),
        Machine2 = ezx_emulator:run_frame(Machine0),
        PerfT1 = erlang:monotonic_time(microsecond),


        BeepT0 = erlang:monotonic_time(microsecond),
        {BeeperPcm, Machine3a} = ezx_emulator:render_beeper(Machine2),
        BeepT1 = erlang:monotonic_time(microsecond),
        AyT0 = erlang:monotonic_time(microsecond),
        {ChA, ChB, ChC, Machine3} = ezx_emulator:render_ay_channels(Machine3a),
        PCM = mix_ay_stereo(BeeperPcm, ChA, ChB, ChC, State),
        AyT1 = erlang:monotonic_time(microsecond),
        case State#state.diag_file of
            undefined -> ok;
            Fd -> file:write(Fd, PCM)
        end,

        %% Write audio to port
        AudioData = case State#state.muted of
            false -> PCM;
            true  -> <<0:(byte_size(PCM))/unit:8>>
        end,
        port_command(Port, AudioData),
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
        AyAcc = AyAcc0 + (AyT1 - AyT0),
        PerfFrames = PerfFrames0 + 1,
        {PerfFramesN, PerfAccN, RenderAccN, BeeperAccN, AyAccN, PerfStartN} =
            case Now - PerfStart0 >= 5000000 andalso State#state.perf_report of
                true ->
                    AvgPerf = PerfAcc / PerfFrames,
                    AvgRender = RenderAcc / PerfFrames,
                    AvgBeeper = BeeperAcc / PerfFrames,
                    AvgAy = AyAcc / PerfFrames,
                    io:format("ezx perf: ~p frames in ~.1f s | emulation ~.2f ms  render ~.2f ms  beeper ~.2f ms  ay ~.2f ms total ~.2f ms~n",
                              [PerfFrames, (Now - PerfStart0) / 1000000,
                               AvgPerf / 1000, AvgRender / 1000, AvgBeeper / 1000, AvgAy / 1000,
                               (AvgPerf + AvgRender + AvgBeeper + AvgAy) / 1000]),
                    {0, 0, 0, 0, 0, Now};
                false ->
                    {PerfFrames, PerfAcc, RenderAcc, BeeperAcc, AyAcc, PerfStart0}
            end,

        {noreply, State#state{machine = Machine3, frame_count = FC,
                              audio_start_us = StartUs, audio_bytes = Written,
                              perf_acc_us = PerfAccN, render_acc_us = RenderAccN,
                              beeper_acc_us = BeeperAccN, ay_acc_us = AyAccN,
                              perf_frames = PerfFramesN, perf_start_us = PerfStartN}}
    catch
        C:E:ST ->
            io:format("Frame error: ~p:~p~n~p~n", [C, E, ST]),
            erlang:send_after(20, self(), frame_tick),
            {noreply, State}
    end;

handle_info(#wx{event = #wxClose{}} = Wx, #state{frame = Frame, sound_dialog_refs = DialRefs, file_dialog = FileDlg} = State) ->
    case Wx#wx.obj of
        Frame ->
            cleanup_dialogs(DialRefs, FileDlg),
            init:stop(),
            {stop, normal, State};
        Obj ->
            {noreply, handle_dialog_close(Obj, DialRefs, FileDlg, State)}
    end;

handle_info(#wx{event = #wxKey{type = key_down, keyCode = ?WXK_F11}}, State) ->
    toggle_fullscreen(State);

handle_info(#wx{event = #wxKey{type = key_down, keyCode = ?WXK_ESCAPE}},
            #state{fullscreen = true} = State) ->
    toggle_fullscreen(State);

handle_info(#wx{event = #wxKey{type = key_down, keyCode = ?WXK_F5}}, #state{machine = undefined} = State) ->
    {noreply, State};
handle_info(#wx{event = #wxKey{type = key_down, keyCode = ?WXK_F5}}, State) ->
    do_reset(State);

handle_info(#wx{event = #wxKey{type = key_down, keyCode = $M, controlDown = true}}, State) ->
    NewState = State#state{muted = not State#state.muted},
    ActionsMenu = wxMenuBar:getMenu(State#state.menu_bar, 2),
    wxMenu:check(ActionsMenu, ?MENU_MUTE, NewState#state.muted),
    save_config(NewState),
    {noreply, NewState};

handle_info(#wx{event = #wxKey{type = key_down, keyCode = $D, controlDown = true}},
            #state{diag_file = DiagFile} = State) ->
    case DiagFile of
        undefined ->
            {ok, Fd} = file:open("/tmp/pcm_dump.raw", [raw, binary, write]),
            io:format("DIAG: recording PCM to /tmp/pcm_dump.raw~n"),
            {noreply, State#state{diag_file = Fd}};
        _ ->
            file:close(DiagFile),
            io:format("DIAG: recording stopped~n"),
            {noreply, State#state{diag_file = undefined}}
    end;

handle_info(#wx{event = #wxKey{type = key_down, keyCode = $O, controlDown = true}}, #state{machine = undefined} = State) ->
    {noreply, State};
handle_info(#wx{event = #wxKey{type = key_down, keyCode = $O, controlDown = true}}, State) ->
    handle_open_file(State);

handle_info(#wx{event = #wxKey{type = key_down, keyCode = $Q, controlDown = true}}, State) ->
    init:stop(),
    {stop, normal, State};

handle_info(#wx{event = #wxKey{type = key_down, keyCode = _Key, rawCode = _RawCode} = _E}, #state{machine = undefined} = State) ->
    {noreply, State};
handle_info(#wx{event = #wxKey{type = key_down, keyCode = Key, rawCode = _RawCode} = _E}, State) ->
    Machine = State#state.machine,
    NewMachine = ezx_emulator:press_key(Machine, Key),
    {noreply, State#state{machine = NewMachine}};

handle_info(#wx{event = #wxKey{type = key_up, keyCode = _Key, rawCode = _RawCode} = _E}, #state{machine = undefined} = State) ->
    {noreply, State};
handle_info(#wx{event = #wxKey{type = key_up, keyCode = Key, rawCode = _RawCode} = _E}, State) ->
    Machine = State#state.machine,
    NewMachine = ezx_emulator:release_key(Machine, Key),
    {noreply, State#state{machine = NewMachine}};

handle_info(#wx{id = ?wxID_OPEN, event = #wxCommand{type = command_menu_selected}}, #state{machine = undefined} = State) ->
    {noreply, State};
handle_info(#wx{id = ?wxID_OPEN, event = #wxCommand{type = command_menu_selected}}, State) ->
    handle_open_file(State);

handle_info(#wx{id = ?wxID_EXIT, event = #wxCommand{type = command_menu_selected}}, State) ->
    init:stop(),    
    {stop, normal, State};

handle_info(#wx{id = Id, event = #wxCommand{type = command_menu_selected}},
            #state{machine = undefined} = State) when Id >= ?MENU_RECENT_BASE, Id < ?MENU_RECENT_BASE + ?MAX_RECENT ->
    {noreply, State};
handle_info(#wx{id = Id, event = #wxCommand{type = command_menu_selected}},
            #state{recent_files = RecentFiles} = State) when Id >= ?MENU_RECENT_BASE, Id < ?MENU_RECENT_BASE + ?MAX_RECENT ->
    Idx = Id - ?MENU_RECENT_BASE + 1,
    case Idx =< length(RecentFiles) of
        true ->
            File = lists:nth(Idx, RecentFiles),
            case ezx_ui_lib:load_emulator_file(State#state.machine, File, State#state.machine_type) of
                {ok, NewMachine} ->
                    io:format("Loaded: ~s~n", [File]),
                    NewRecent = ezx_recent_files:update(File, State#state.recent_files),
                    ezx_recent_files:rebuild_menu(State#state.menu_bar, NewRecent),
                    {noreply, State#state{machine = NewMachine, recent_files = NewRecent}};
                {error, _Code} = Err ->
                    show_load_error(State#state.frame, File, Err),
                    case Err of
                        {error, {file_not_found, _}} ->
                            NewRecent = ezx_recent_files:update(File, State#state.recent_files),
                            ezx_recent_files:rebuild_menu(State#state.menu_bar, NewRecent),
                            {noreply, State#state{recent_files = NewRecent}};
                        _ ->
                            {noreply, State}
                    end
            end;
        false ->
            {noreply, State}
    end;

handle_info(#wx{id = ?MENU_FULLSCREEN, event = #wxCommand{type = command_menu_selected}}, State) ->
    toggle_fullscreen(State);

handle_info(#wx{id = ?MENU_RESET, event = #wxCommand{type = command_menu_selected}}, #state{machine = undefined} = State) ->
    {noreply, State};
handle_info(#wx{id = ?MENU_RESET, event = #wxCommand{type = command_menu_selected}}, State) ->
    do_reset(State);

handle_info(#wx{id = ?MENU_MUTE, event = #wxCommand{type = command_menu_selected}}, State) ->
    NewState = State#state{muted = not State#state.muted},
    save_config(NewState),
    {noreply, NewState};

handle_info(#wx{id = ?MENU_DEBUG_PERF, event = #wxCommand{type = command_menu_selected}}, State) ->
    NewState = State#state{perf_report = not State#state.perf_report},
    save_config(NewState),
    {noreply, NewState};

handle_info(#wx{id = ?MENU_CROP, event = #wxCommand{type = command_menu_selected}}, State) ->
    NewCrop = not State#state.option_crop_border,
    NewState = State#state{option_crop_border = NewCrop},
    save_config(NewState),
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
    save_config(NewState),
    case NewState#state.fullscreen of
        true  -> reenter_crop_fullscreen(NewState);
        false -> {noreply, NewState}
    end;

handle_info(#wx{id = Id, event = #wxCommand{type = command_menu_selected}},
            State) when Id >= ?MENU_SCALE_BASE, Id < ?MENU_SCALE_BASE + 4 ->
    NewScale = (Id - ?MENU_SCALE_BASE) + 1,
    NewState = State#state{scale = NewScale},
    save_config(NewState),
    case NewState#state.fullscreen of
        true  -> reenter_crop_fullscreen(NewState);
        false ->
            Frame = NewState#state.frame,
            {W, H} = windowed_client_size(NewState#state.option_crop_border, NewScale),
            wxWindow:setClientSize(Frame, W, H),
            {noreply, NewState}
    end;

handle_info(#wx{id = ?MENU_SETTINGS_SOUND, event = #wxCommand{type = command_menu_selected}},
            #state{frame = Frame, beeper_vol = BV, ay_master_vol = AV, ay_stereo_mode = Mode} = State) ->
    Refs = ezx_sound_dialog:open(Frame, BV, AV, Mode),
    {noreply, State#state{sound_dialog_refs = Refs}};

handle_info(#wx{id = ?wxID_OK, event = #wxCommand{type = command_button_clicked}},
            #state{sound_dialog_refs = {Dialog, BeeperSlider, AySlider, ModeChoice}} = State) ->
    BV = wxSlider:getValue(BeeperSlider),
    AV = wxSlider:getValue(AySlider),
    Mode = ezx_sound_dialog:stereo_mode_from_index(wxChoice:getSelection(ModeChoice)),
    wxDialog:destroy(Dialog),
    wxWindow:update(State#state.frame),
    NewState = State#state{beeper_vol = BV, ay_master_vol = AV, ay_stereo_mode = Mode,
                           sound_dialog_refs = undefined},
    save_config(NewState),
    {noreply, NewState};

handle_info(#wx{id = ?wxID_CANCEL, event = #wxCommand{type = command_button_clicked}},
            #state{sound_dialog_refs = {Dialog, _, _, _}} = State) ->
    wxDialog:destroy(Dialog),
    {noreply, State#state{sound_dialog_refs = undefined}};

handle_info(#wx{id = ?wxID_OK, event = #wxCommand{type = command_button_clicked}},
            #state{file_dialog = Dialog} = State) when Dialog =/= undefined ->
    File = wxFileDialog:getPath(Dialog),
    wxFileDialog:destroy(Dialog),
    case ezx_ui_lib:load_emulator_file(State#state.machine, File, State#state.machine_type) of
        {ok, NewMachine} ->
            io:format("Loaded: ~s~n", [File]),
            NewRecent = ezx_recent_files:update(File, State#state.recent_files),
            ezx_recent_files:rebuild_menu(State#state.menu_bar, NewRecent),
            {noreply, State#state{machine = NewMachine, recent_files = NewRecent,
                                   file_dialog = undefined}};
        {error, _Code} = Err ->
            show_load_error(State#state.frame, File, Err),
            {noreply, State#state{file_dialog = undefined}}
    end;

handle_info(#wx{id = ?wxID_CANCEL, event = #wxCommand{type = command_button_clicked}},
            #state{file_dialog = Dialog} = State) when Dialog =/= undefined ->
    wxFileDialog:destroy(Dialog),
    {noreply, State#state{file_dialog = undefined}};

handle_info(#wx{id = Id, event = #wxCommand{type = command_menu_selected}},
            #state{machine_type = OldType} = State) when Id >= ?MENU_MACHINE_BASE, Id < ?MENU_MACHINE_BASE + 2 ->
    NewType = machine_type_from_offset(Id - ?MENU_MACHINE_BASE),
    case NewType =/= OldType of
        true ->
            case ezx_ui_lib:init_virtual_machine(NewType) of
                {ok, Machine} ->
                    MenuBar = State#state.menu_bar,
                    Now = erlang:monotonic_time(microsecond),
                    wxMenuBar:enableTop(MenuBar, 0, true),
                    wxMenuBar:enableTop(MenuBar, 3, true),
                    NewState = State#state{
                        machine = Machine,
                        machine_type = NewType,
                        frame_count = 0,
                        audio_start_us = Now, audio_bytes = 0,
                        perf_acc_us = 0, render_acc_us = 0,
                        beeper_acc_us = 0, ay_acc_us = 0,
                        perf_frames = 0, perf_start_us = Now
                    },
                    save_config(NewState),
                    {noreply, NewState};
                {error, {_Code, Detail}} ->
                    EmulatorMenu = wxMenuBar:getMenu(State#state.menu_bar, 1),
                    wxMenu:check(EmulatorMenu, Id, false),
                    wxMenu:check(EmulatorMenu, ?MENU_MACHINE_BASE + machine_type_offset(OldType), true),
                    Dialog = wxMessageDialog:new(State#state.frame, binary_to_list(Detail),
                                                 [{caption, "ezx - cannot switch machine type"},
                                                  {style, ?wxOK bor ?wxICON_ERROR}]),
                    wxDialog:showModal(Dialog),
                    wxMessageDialog:destroy(Dialog),
                    {noreply, State}
            end;
        false ->
            {noreply, State}
    end;

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, #state{frame = Frame, aplay_port = Port}) ->
    catch port_close(Port),
    wxFrame:destroy(Frame),
    ok.

%% --- Internal ---

do_reset(State) ->
    case ezx_ui_lib:init_virtual_machine(State#state.machine_type) of
        {ok, Machine} ->
            Now = erlang:monotonic_time(microsecond),
            {noreply, State#state{machine = Machine, frame_count = 0,
                                  audio_start_us = Now, audio_bytes = 0,
                                  perf_acc_us = 0, render_acc_us = 0,
                                  beeper_acc_us = 0, ay_acc_us = 0,
                                  perf_frames = 0, perf_start_us = Now}};
        {error, {_Code, Detail}} ->
            Frame = State#state.frame,
            Dialog = wxMessageDialog:new(Frame, binary_to_list(Detail),
                                         [{caption, "ezx - reset failed"},
                                          {style, ?wxOK bor ?wxICON_ERROR}]),
            wxDialog:showModal(Dialog),
            wxMessageDialog:destroy(Dialog),
            wxMenuBar:enableTop(State#state.menu_bar, 0, false),
            wxMenuBar:enableTop(State#state.menu_bar, 3, false),
            {noreply, State#state{machine = undefined, frame_count = 0}}
    end.

handle_open_file(#state{file_dialog = undefined} = State) ->
    Dialog = wxFileDialog:new(State#state.frame, [{message, "Load snapshot or tape"},
                                                   {wildCard, "ZX Spectrum files (*.sna,*.z80,*.tap)|*.sna;*.z80;*.tap|SNA files (*.sna)|*.sna|Z80 files (*.z80)|*.z80|TAP files (*.tap)|*.tap"},
                                                   {style, ?wxFD_OPEN bor ?wxFD_FILE_MUST_EXIST}]),
    wxFileDialog:connect(Dialog, command_button_clicked),
    wxDialog:show(Dialog),
    {noreply, State#state{file_dialog = Dialog}};
handle_open_file(State) ->
    {noreply, State}.

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

toggle_fullscreen(#state{frame = Frame, fullscreen = false, scale = WindowedScale, option_crop_border = Crop} = State) ->
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
                          scale = NewScale, windowed_scale = WindowedScale, crop_off = {OffX, OffY},
                          crop_exact_scale = ExactScale,
                          fullscreen_size = {SW, SH},
                          windowed_size = WinSize}};
toggle_fullscreen(#state{frame = Frame, fullscreen = true, windowed_scale = WindowedScale,
                         windowed_size = {WW, WH}} = State) ->
    wxFrame:showFullScreen(Frame, false),
    wxFrame:setSize(Frame, WW, WH),
    {noreply, State#state{fullscreen = false,
                          scale = WindowedScale, crop_off = {0, 0},
                          fullscreen_size = undefined,
                          windowed_size = undefined}}.

%% {Scale, OffX, OffY} for emulated coordinates (352×288).
%% OffX/OffY in emulated pixels: visible window origin within the emulated frame.
%% Multiply by Scale to get screen-pixel shift of the device origin.
machine_type_offset('48k')  -> 0;
machine_type_offset('128k') -> 1.

machine_type_from_offset(0) -> '48k';
machine_type_from_offset(1) -> '128k'.

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



save_config(#state{machine_type = MType, option_crop_border = Crop, option_integer_scaling = Exact,
                   muted = Muted, scale = Scale, beeper_vol = BV, ay_master_vol = AV, ay_stereo_mode = Mode,
                   perf_report = PerfReport}) ->
    ezx_config:save(#{machine_type => MType, crop_border => Crop, integer_scaling => Exact,
                       muted => Muted, scale => Scale,
                       beeper_vol => BV, ay_master_vol => AV, ay_stereo_mode => Mode,
                       perf_report => PerfReport}).

show_load_error(Frame, File, {error, {Code, Detail}}) ->
    Msg = maps:get(Code, #{
        file_not_found       => "File not found or could not be read.",
        unsupported_format   => "Unsupported file format.",
        unsupported_version  => "This snapshot requires a 128K machine.",
        bad_sna_header       => "Invalid or corrupted SNA snapshot.",
        sna_load_failed      => "Unexpected error while loading SNA snapshot.",
        bad_z80_header       => "Invalid or corrupted Z80 snapshot.",
        z80_load_failed      => "Unexpected error while loading Z80 snapshot.",
        bad_tap_data         => "Invalid or corrupted TAP file.",
        tap_load_failed      => "Unexpected error while loading TAP file."
    }, "Unknown error."),
    FullMsg = case Detail of
        <<>> -> Msg;
        _    -> [Msg, "\n\n", Detail]
    end,
    Dialog = wxMessageDialog:new(Frame, FullMsg, [{caption, "ezx: " ++ filename:basename(File)},
                                                  {style, ?wxOK bor ?wxICON_ERROR}]),
    wxDialog:showModal(Dialog),
    wxMessageDialog:destroy(Dialog).

%% @doc Mix mono beeper + 3 mono AY channels into stereo S16LE.
%% Panning and volume derived from stereo mode and master/global volumes.
%% Empty AY channels are padded with silence.
-spec mix_ay_stereo(binary(), binary(), binary(), binary(), #state{}) -> binary().
mix_ay_stereo(BeeperPcm, ChA, ChB, ChC, #state{ay_master_vol = AyVol, ay_stereo_mode = Mode,
                                                 beeper_vol = BeeperVol}) ->
    {PanA, PanB, PanC} = ezx_sound_dialog:stereo_pans(Mode),
    Len = byte_size(BeeperPcm),
    ChA1 = pad_channel(ChA, Len),
    ChB1 = pad_channel(ChB, Len),
    ChC1 = pad_channel(ChC, Len),
    mix_samples(BeeperPcm, ChA1, ChB1, ChC1, PanA, PanB, PanC, AyVol, AyVol, AyVol, BeeperVol, <<>>).

-spec pad_channel(binary(), non_neg_integer()) -> binary().
pad_channel(<<>>, Len) -> <<0:Len/unit:8>>;
pad_channel(Pcm, _Len) -> Pcm.

-spec mix_samples(binary(), binary(), binary(), binary(), left|both|right, left|both|right, left|both|right,
                  0..100, 0..100, 0..100, 0..100, binary()) -> binary().
mix_samples(<<>>, <<>>, <<>>, <<>>, _PanA, _PanB, _PanC, _VA, _VB, _VC, _BV, Acc) -> Acc;
mix_samples(<<B:16/little-signed, BR/binary>>,
            <<A:16/little-signed, AR/binary>>,
            <<B_:16/little-signed, BB/binary>>,
            <<C:16/little-signed, CR/binary>>,
            PanA, PanB, PanC, VA, VB, VC, BV, Acc) ->
    B0 = (B * BV) div 100,
    A0 = (A * VA) div 100,
    B1 = (B_ * VB) div 100,
    C0 = (C * VC) div 100,
    L = clamp16((B0 + pan_left(A0, PanA) + pan_left(B1, PanB) + pan_left(C0, PanC)) div 2),
    R = clamp16((B0 + pan_right(A0, PanA) + pan_right(B1, PanB) + pan_right(C0, PanC)) div 2),
    mix_samples(BR, AR, BB, CR, PanA, PanB, PanC, VA, VB, VC, BV,
                <<Acc/binary, L:16/little-signed, R:16/little-signed>>).

cleanup_dialogs(undefined, undefined) -> ok;
cleanup_dialogs({D, _, _, _}, undefined) -> wxDialog:destroy(D);
cleanup_dialogs(undefined, FD) -> wxFileDialog:destroy(FD);
cleanup_dialogs({D, _, _, _}, FD) -> wxDialog:destroy(D), wxFileDialog:destroy(FD).

handle_dialog_close(Obj, {Obj, _, _, _}, _FileDlg, State) ->
    wxDialog:destroy(Obj),
    State#state{sound_dialog_refs = undefined};
handle_dialog_close(Obj, _DialRefs, Obj, State) ->
    wxFileDialog:destroy(Obj),
    State#state{file_dialog = undefined};
handle_dialog_close(_Obj, _DialRefs, _FileDlg, State) ->
    State.

pan_left(_V, left)  -> _V;
pan_left(_V, both)  -> _V;
pan_left(_V, right) -> 0.

pan_right(_V, left)  -> 0;
pan_right(_V, both)  -> _V;
pan_right(_V, right) -> _V.

-spec clamp16(integer()) -> -32768..32767.
clamp16(S) when S > 32767 -> 32767;
clamp16(S) when S < -32768 -> -32768;
clamp16(S) -> S.