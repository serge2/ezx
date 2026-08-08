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
-define(SCREEN_WIDTH, 256).                          %% ZX Spectrum playfield, px
-define(SCREEN_HEIGHT, 192).                         %% ZX Spectrum playfield, px
-define(BORDER_FRAME, 8).                            %% border frame kept after crop, px per side
-define(BORDER_TRIM, (((?DEFAULT_WIDTH - ?SCREEN_WIDTH) div 2) - ?BORDER_FRAME)).
-define(CROP_WIDTH, (?SCREEN_WIDTH + 2 * ?BORDER_FRAME)).
-define(CROP_HEIGHT, (?SCREEN_HEIGHT + 2 * ?BORDER_FRAME)).
-define(DEFAULT_SCALE, 2).
-define(FCREPORT_INTERVAL, 100).
-define(MENU_FULLSCREEN, 2001).
-define(MENU_RESET, 3001).
-define(MENU_CROP_EXACT, 4001).
-define(MENU_CROP, 4002).
-define(MENU_MUTE, 3002).
-define(MENU_PAUSE, 3003).
-define(MENUBAR_ACTIONS_INDEX, 4).
-define(TOAST_MS, 1000).
-define(TOAST_BG, {30, 30, 30}).
-define(TOAST_BORDER, {170, 170, 170, 255}).
-define(TOAST_ICON, {240, 240, 240, 255}).
%% Audio filter cutoffs (alpha coefficients for ezx_audio_filter). The filter
%% module is generic; these are the UI's settings for its two uses.
-define(BEEPER_LPF_ALPHA, 0.090).  %% ~700 Hz low-pass (speaker/RC-circuit inertia)
-define(BEEPER_HPF_ALPHA, 0.9887). %% ~80 Hz high-pass (DC / overshoot blocking)
%% Process heap floor for the UI process (which runs the machine and renders
%% the 352×288 frame in place). Per-frame garbage (screen bitmap, audio PCM)
%% would otherwise push the process over its heap threshold and land a full GC
%% inside the ~20 ms frame budget, showing up as spikes in the render phase.
-define(MIN_HEAP_WORDS, 250000).

-record(state, {
    machine   :: #machine_state{} | undefined,
    machine_type = '48k' :: '48k' | '128k',
    current_file = undefined :: string() | undefined,
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
    audio_pacing = undefined :: ezx_audio_pacing:state() | undefined,
    perf_start_us = 0 :: non_neg_integer(),
    muted = false :: boolean(),
    perf_report = false :: boolean(),
    paused = false :: boolean(),
    menu_bar :: wxMenuBar:wxMenuBar(),
    recent_files = [] :: [string()],
    diag_file :: pid() | undefined,
    beeper_vol = 100 :: 0..100,
    ay_master_vol = 100 :: 0..100,
    ay_stereo_mode = acb :: acb | abc | mono,
    ay_chip = ay :: ay | ym | off,
    audio_filter = undefined :: ezx_audio_filter:state() | undefined,
    mix_dc_l = undefined :: ezx_audio_filter:state() | undefined,
    mix_dc_r = undefined :: ezx_audio_filter:state() | undefined,
    sound_dialog_refs = undefined :: {wxDialog:wxDialog(), {wxSlider:wxSlider(), wxSlider:wxSlider(), wxChoice:wxChoice(), wxChoice:wxChoice()}} | undefined,
    mouse_dialog_refs = undefined :: {wxDialog:wxDialog(), {wxCheckBox:wxCheckBox(), wxCheckBox:wxCheckBox()}} | undefined,
    file_dialog_dir = undefined :: string() | undefined,
    saves_dialog_refs = undefined :: {wxDialog:wxDialog(), wxListCtrl:wxListCtrl(),
                                      wxButton:wxButton(), wxButton:wxButton(), wxButton:wxButton(),
                                      wxStaticBitmap:wxStaticBitmap()} | undefined,
    saves_entries = [] :: [{string(), string(), string(), string(), string()}],
    blank_cursor = undefined :: wxCursor:wxCursor() | undefined,
    cursor_hidden = false :: boolean(),
    mouse = undefined :: any(),
    toast = undefined :: {reference(), save | load} | undefined
}).


start() ->
    gen_server:start({local, ?MODULE}, ?MODULE, [], []).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

stop() ->
    gen_server:stop(?MODULE).

init(_Options) ->
    process_flag(trap_exit, true),
    process_flag(min_heap_size, ?MIN_HEAP_WORDS),
    wx:new(),

    %% Pre-load config to get crop setting for initial window size
    Cfg0 = ezx_config:load(),
    CropBorder0 = maps:get(crop_border, Cfg0, true),
    InitScale0 = maps:get(scale, Cfg0, ?DEFAULT_SCALE),
    {InitW, InitH} = windowed_client_size(CropBorder0, InitScale0),
    Frame = wxFrame:new(wx:null(), -1, "ezx - ZX Spectrum emulator",
                        [{size, {InitW, InitH}},
                         {style, ?wxDEFAULT_FRAME_STYLE band (bnot ?wxRESIZE_BORDER)}]),
    set_frame_icon(Frame),
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
    wxMenu:append(SettingsMenu, ?MENU_SETTINGS_SOUND, "Sound...", [{help, "Configure sound settings"}]),
    wxMenu:append(SettingsMenu, ?MENU_SETTINGS_MOUSE, "Mouse...", [{help, "Configure the Kempston mouse"}]),
    wxMenuBar:append(MenuBar, SettingsMenu, "Settings"),
    ActionsMenu = wxMenu:new(),
    wxMenu:append(ActionsMenu, ?MENU_RESET, "Reset\tF7", [{help, "Reset the emulator"}]),
    wxMenu:appendSeparator(ActionsMenu),
    wxMenu:appendCheckItem(ActionsMenu, ?MENU_MUTE, "Mute\tCtrl+M", [{help, "Toggle audio mute"}]),
    wxMenu:appendCheckItem(ActionsMenu, ?MENU_PAUSE, "Pause\tCtrl+P", [{help, "Pause and resume emulation"}]),
    wxMenuBar:append(MenuBar, ActionsMenu, "Actions"),
    DebugMenu = wxMenu:new(),
    wxMenu:appendCheckItem(DebugMenu, ?MENU_DEBUG_PERF, "Performance report",
                           [{help, "Print performance stats to console every 5 seconds"}]),
    wxMenuBar:append(MenuBar, DebugMenu, "Debug"),
    HelpMenu = wxMenu:new(),
    wxMenu:append(HelpMenu, ?MENU_ABOUT, "About ezx...",
                  [{help, "Show information about this emulator"}]),
    wxMenuBar:append(MenuBar, HelpMenu, "Help"),
    wxFrame:setMenuBar(Frame, MenuBar),

    %% Apply saved config to menu checkmarks
    CropBorder = maps:get(crop_border, Cfg0, true),
    IntScaling = maps:get(integer_scaling, Cfg0, false),
    Muted = maps:get(muted, Cfg0, false),
    PerfReport = maps:get(perf_report, Cfg0, false),
    KempstonMouse = maps:get(kempston_mouse, Cfg0, false),
    MouseSwap = maps:get(mouse_swap_buttons, Cfg0, false),
    Mouse = ezx_ui_mouse:new(KempstonMouse, MouseSwap),
    wxMenu:check(EmulatorMenu, ?MENU_MACHINE_BASE + machine_type_offset(MachineType), true),
    wxMenu:check(ViewMenu, ?MENU_CROP, CropBorder),
    wxMenu:check(ViewMenu, ?MENU_CROP_EXACT, IntScaling),
    wxMenu:check(ViewMenu, ?MENU_SCALE_BASE + (InitScale0 - 1), true),
    wxMenu:check(ActionsMenu, ?MENU_MUTE, Muted),
    wxMenu:check(DebugMenu, ?MENU_DEBUG_PERF, PerfReport),
    wxFrame:connect(Frame, command_menu_selected),

    Panel = wxPanel:new(Frame, [{style, ?wxWANTS_CHARS}]),
    wxWindow:setBackgroundStyle(Panel, ?wxBG_STYLE_PAINT),
    wxPanel:connect(Panel, key_down),
    wxPanel:connect(Panel, key_up),
    wxPanel:connect(Panel, motion),
    wxPanel:connect(Panel, left_down),
    wxPanel:connect(Panel, left_up),
    wxPanel:connect(Panel, right_down),
    wxPanel:connect(Panel, right_up),
    wxPanel:connect(Panel, middle_down),
    wxPanel:connect(Panel, middle_up),
    wxPanel:connect(Panel, enter_window),
    wxPanel:connect(Panel, leave_window),
    BlankCursor = wxCursor:new(?wxCURSOR_BLANK),
    wxFrame:connect(Frame, close_window),
    wxFrame:show(Frame),
    {DefW, DefH} = windowed_client_size(CropBorder, InitScale0),
    wxWindow:setClientSize(Frame, DefW, DefH),
    wxWindow:setFocus(Panel),

    AplayPort = open_audio_port(),

    Now = erlang:monotonic_time(microsecond),
    BeeperVol = maps:get(beeper_vol, Cfg0, 100),
    AyVol = maps:get(ay_master_vol, Cfg0, 100),
    Mode = maps:get(ay_stereo_mode, Cfg0, acb),
    AyChip = maps:get(ay_chip, Cfg0, ay),
    State0 = #state{
        machine = undefined,
        machine_type = MachineType,
        frame = Frame,
        panel = Panel,
        blank_cursor = BlankCursor,
        scale = InitScale0,
        option_crop_border = CropBorder,
        option_integer_scaling = IntScaling,
        muted = Muted,
        perf_report = PerfReport,
        beeper_vol = BeeperVol,
        ay_master_vol = AyVol,
        ay_stereo_mode = Mode,
        ay_chip = AyChip,
        audio_filter = new_beeper_filter(),
        mix_dc_l = new_mix_dc_filter(),
        mix_dc_r = new_mix_dc_filter(),
        aplay_port = AplayPort,
        audio_pacing = undefined,
        perf_start_us = Now,
        menu_bar = MenuBar,
        recent_files = RecentFiles0,
        mouse = Mouse
    },
    case ezx_ui_lib:init_virtual_machine(MachineType, AyChip) of
        {ok, Machine} ->
            Machine1 = ezx_ui_mouse:apply_to_machine(Mouse, Machine),
            erlang:send_after(0, self(), frame_tick),
            {ok, State0#state{machine = Machine1,
                              audio_pacing = ezx_audio_pacing:new(audio_bytes_per_frame(Machine1))}};
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

handle_info({clear_toast, Ref}, #state{toast = {Ref, _}} = State) ->
    {noreply, State#state{toast = undefined}};
handle_info({clear_toast, _}, State) ->
    {noreply, State};

%% The audio player port (aplay/sox) died: its process exited or the pipe
%% broke (epipe). Never crash the UI for that — mute audio and keep running.
handle_info({'EXIT', Port, Reason}, State) when is_port(Port) ->
    case State#state.aplay_port of
        Port ->
            io:format("ezx: audio player port closed (~p) - audio muted~n", [Reason]),
            {noreply, State#state{aplay_port = undefined}};
        _ ->
            {noreply, State}
    end;
handle_info({Port, {exit_status, Status}}, #state{aplay_port = Port} = State) ->
    io:format("ezx: audio player exited with status ~p - audio muted~n", [Status]),
    {noreply, State#state{aplay_port = undefined}};
handle_info({'EXIT', Pid, Reason}, State) when is_pid(Pid) ->
    {stop, Reason, State};

handle_info(frame_tick, #state{machine = undefined} = State) ->
    erlang:send_after(50, self(), frame_tick),
    {noreply, State};

handle_info(frame_tick, #state{paused = true, machine = Machine,
                               aplay_port = Port} = State) ->
    Silence = <<0:(audio_bytes_per_frame(Machine))/unit:8>>,
    port_send(Port, Silence),
    RGB = ezx_emulator:render_frame(Machine),
    draw_frame(State, RGB),
    Now = erlang:monotonic_time(microsecond),
    {DelayMs, Pacing} = ezx_audio_pacing:advance(State#state.audio_pacing,
                                                 byte_size(Silence), Now),
    schedule_frame(DelayMs),
    {noreply, State#state{audio_pacing = Pacing}};

%% While the save/load toast is up the emulation is frozen: no run_frame, no
%% audio, just the last rendered frame with the toast on top. It resumes when
%% the toast clears (clear_toast message).
handle_info(frame_tick, #state{machine = Machine,
                               aplay_port = Port,
                               toast = {_, _}} = State) ->
    Silence = <<0:(audio_bytes_per_frame(Machine))/unit:8>>,
    port_send(Port, Silence),
    RGB = ezx_emulator:render_frame(Machine),
    draw_frame(State, RGB),
    Now = erlang:monotonic_time(microsecond),
    {DelayMs, Pacing} = ezx_audio_pacing:advance(State#state.audio_pacing,
                                                 byte_size(Silence), Now),
    schedule_frame(DelayMs),
    {noreply, State#state{audio_pacing = Pacing}};

handle_info(frame_tick, #state{machine = Machine0,
                                  frame_count = FC0,
                                  aplay_port = Port,
                                  perf_start_us = PerfStart0} = State) ->
    try
        Machine2 = ezx_emulator:run_frame(Machine0),

        {BeeperRawPcm, Machine3a} = ezx_emulator:render_beeper(Machine2),
        {BeeperPcm, AudioFilter1} = ezx_audio_filter:filter(BeeperRawPcm, State#state.audio_filter),
        {ChA, ChB, ChC, Machine3} = ezx_emulator:render_ay_channels(Machine3a),
        PCM0 = mix_ay_stereo(BeeperPcm, ChA, ChB, ChC, State),
        {PCM, MixDcL1, MixDcR1} = dc_block_stereo(PCM0, State#state.mix_dc_l, State#state.mix_dc_r),
        case State#state.diag_file of
            undefined -> ok;
            Fd -> file:write(Fd, PCM)
        end,

        AudioData = case State#state.muted of
            false -> PCM;
            true  -> <<0:(byte_size(PCM))/unit:8>>
        end,
        port_send(Port, AudioData),
        Now = erlang:monotonic_time(microsecond),
        {DelayMs, Pacing} = ezx_audio_pacing:advance(State#state.audio_pacing,
                                                     byte_size(PCM), Now),

        FC = FC0 + 1,
        RGB = ezx_emulator:render_frame(Machine3),
        draw_frame(State, RGB),
        schedule_frame(DelayMs),

        {MachineN, PerfStartN} =
            case Now - PerfStart0 >= 5000000 andalso State#state.perf_report of
                true ->
                    PS = ezx_emulator:read_perf(Machine3),
                    Frames = PS#perf_stats.frames,
                    AvgCpu = PS#perf_stats.cpu_us / Frames,
                    AvgBeeper = PS#perf_stats.beeper_us / Frames,
                    AvgAy = PS#perf_stats.ay_us / Frames,
                    AvgScreen = PS#perf_stats.screen_us / Frames,
                    AvgRender = PS#perf_stats.render_us / Frames,
                    io:format("ezx perf: ~p frames in ~.1f s | emulation ~.2f ms  beeper ~.2f ms  ay ~.2f ms  screen ~.2f ms  render ~.2f ms total ~.2f ms~n",
                              [Frames, (Now - PerfStart0) / 1000000,
                               AvgCpu / 1000, AvgBeeper / 1000, AvgAy / 1000,
                               AvgScreen / 1000, AvgRender / 1000,
                               (AvgCpu + AvgBeeper + AvgAy + AvgScreen + AvgRender) / 1000]),
                    {ezx_emulator:reset_perf(Machine3), Now};
                false ->
                    {Machine3, PerfStart0}
            end,

        {noreply, State#state{machine = MachineN, frame_count = FC,
                              audio_pacing = Pacing,
                              perf_start_us = PerfStartN,
                              audio_filter = AudioFilter1,
                              mix_dc_l = MixDcL1,
                              mix_dc_r = MixDcR1}}
    catch
        C:E:ST ->
            io:format("Frame error: ~p:~p~n~p~n", [C, E, ST]),
            erlang:send_after(20, self(), frame_tick),
            {noreply, State}
    end;

handle_info(#wx{event = #wxClose{}} = Wx, #state{frame = Frame} = State) ->
    case Wx#wx.obj of
        Frame ->
            cleanup_dialogs(State),
            init:stop(),
            {stop, shutdown, State};
        Obj ->
            {noreply, close_dialog(Obj, State)}
    end;

handle_info(#wx{event = #wxKey{type = key_down, keyCode = ?WXK_F11}}, State) ->
    toggle_fullscreen(State);

handle_info(#wx{event = #wxKey{type = key_down, keyCode = ?WXK_ESCAPE}},
            #state{fullscreen = true} = State) ->
    toggle_fullscreen(show_cursor(State));

handle_info(#wx{event = #wxKey{type = key_down, keyCode = ?WXK_ESCAPE}}, State) ->
    {noreply, show_cursor(State)};

handle_info(#wx{event = #wxKey{type = key_down, keyCode = ?WXK_F5}}, #state{machine = undefined} = State) ->
    {noreply, State};
handle_info(#wx{event = #wxKey{type = key_down, keyCode = ?WXK_F5}}, State) ->
    quick_save(State);

handle_info(#wx{event = #wxKey{type = key_down, keyCode = ?WXK_F9}}, #state{machine = undefined} = State) ->
    {noreply, State};
handle_info(#wx{event = #wxKey{type = key_down, keyCode = ?WXK_F9}}, State) ->
    quick_load(State);

handle_info(#wx{event = #wxKey{type = key_down, keyCode = ?WXK_F7}}, #state{machine = undefined} = State) ->
    {noreply, State};
handle_info(#wx{event = #wxKey{type = key_down, keyCode = ?WXK_F7}}, State) ->
    do_reset(State);

handle_info(#wx{event = #wxKey{type = key_down, keyCode = ?WXK_F2}}, #state{machine = undefined} = State) ->
    {noreply, State};
handle_info(#wx{event = #wxKey{type = key_down, keyCode = ?WXK_F2}}, State) ->
    save_state(State);

handle_info(#wx{event = #wxKey{type = key_down, keyCode = ?WXK_F3}}, State) ->
    manage_saves(State);

%% Ctrl-based UI hotkeys require a bare Control (no Alt): on wxGTK the right
%% Alt (AltGr) is reported as Ctrl+Alt on every key typed while it is held, so
%% an AltGr-driven SymbolShift+P would otherwise fire Ctrl+P (pause, mute,
%% quit...) instead of typing the guest symbol. Real Ctrl+letter combos still
%% match because they arrive without Alt.
handle_info(#wx{event = #wxKey{type = key_down, keyCode = $M, controlDown = true, altDown = false}}, State) ->
    NewState = State#state{muted = not State#state.muted},
    ActionsMenu = wxMenuBar:getMenu(State#state.menu_bar, ?MENUBAR_ACTIONS_INDEX),
    wxMenu:check(ActionsMenu, ?MENU_MUTE, NewState#state.muted),
    save_config(NewState),
    {noreply, NewState};

handle_info(#wx{event = #wxKey{type = key_down, keyCode = $P, controlDown = true, altDown = false}}, State) ->
    NewState = toggle_pause(State),
    {noreply, NewState};

handle_info(#wx{event = #wxKey{type = key_down, keyCode = $D, controlDown = true, altDown = false}},
            #state{diag_file = DiagFile} = State) ->
    case DiagFile of
        undefined ->
            DumpPath = filename:join(ezx_ui_lib:app_dir(), "pcm_dump.raw"),
            {ok, Fd} = file:open(DumpPath, [raw, binary, write]),
            io:format("DIAG: recording PCM to ~s~n", [DumpPath]),
            {noreply, State#state{diag_file = Fd}};
        _ ->
            file:close(DiagFile),
            io:format("DIAG: recording stopped~n"),
            {noreply, State#state{diag_file = undefined}}
    end;

handle_info(#wx{event = #wxKey{type = key_down, keyCode = $O, controlDown = true, altDown = false}}, #state{machine = undefined} = State) ->
    {noreply, State};
handle_info(#wx{event = #wxKey{type = key_down, keyCode = $O, controlDown = true, altDown = false}}, State) ->
    handle_open_file(State);

handle_info(#wx{event = #wxKey{type = key_down, keyCode = $Q, controlDown = true, altDown = false}}, State) ->
    init:stop(),
    {stop, shutdown, State};

%% Ctrl+F12: dump the whole machine state (term_to_binary) so a stuck/interesting
%% state can be reproduced headlessly for debugging. The modifier guards against
%% accidental dumps; files land in the app state dir (like recent files), not /tmp.
handle_info(#wx{event = #wxKey{type = key_down, keyCode = ?WXK_F12, controlDown = true, altDown = false}},
            #state{machine = undefined} = State) ->
    {noreply, State};
handle_info(#wx{event = #wxKey{type = key_down, keyCode = ?WXK_F12, controlDown = true, altDown = false}},
            #state{machine = Machine} = State) ->
    DumpDir = filename:join([ezx_ui_lib:app_dir(), "dumps"]),
    filelib:ensure_dir(filename:join(DumpDir, "dummy")),
    Path = filename:join(DumpDir, dump_filename()),
    Bin = term_to_binary(Machine),
    case file:write_file(Path, Bin) of
        ok ->
            io:format("DIAG: machine state dumped to ~s (~p bytes)~n",
                      [Path, byte_size(Bin)]);
        {error, Reason} ->
            io:format("DIAG: failed to dump machine state to ~s: ~p~n", [Path, Reason])
    end,
    {noreply, State};

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

%% --- Kempston mouse events ---

handle_info(#wx{event = #wxMouse{type = motion, x = X, y = Y}},
            #state{machine = Machine, mouse = Mouse, scale = Scale} = State) ->
    {Mouse1, Machine1} = ezx_ui_mouse:motion(Mouse, Machine, X, Y, Scale),
    {noreply, (hide_cursor(State))#state{machine = Machine1, mouse = Mouse1}};

handle_info(#wx{event = #wxMouse{type = left_down}}, State) ->
    mouse_button(State, left, true);
handle_info(#wx{event = #wxMouse{type = left_up}}, State) ->
    mouse_button(State, left, false);
handle_info(#wx{event = #wxMouse{type = right_down}}, State) ->
    mouse_button(State, right, true);
handle_info(#wx{event = #wxMouse{type = right_up}}, State) ->
    mouse_button(State, right, false);
handle_info(#wx{event = #wxMouse{type = middle_down}}, State) ->
    mouse_button(State, middle, true);
handle_info(#wx{event = #wxMouse{type = middle_up}}, State) ->
    mouse_button(State, middle, false);

%% Hide the host cursor while it is over the panel and the Kempston mouse
%% is enabled; show it again on leave or Esc.
handle_info(#wx{event = #wxMouse{type = enter_window}},
            #state{mouse = Mouse, panel = Panel, blank_cursor = Cursor} = State) ->
    case ezx_ui_mouse:enabled(Mouse) of
        true ->
            wxWindow:setCursor(Panel, Cursor),
            {noreply, State#state{cursor_hidden = true}};
        false ->
            {noreply, State}
    end;

handle_info(#wx{event = #wxMouse{type = leave_window}},
            #state{panel = Panel, cursor_hidden = Hidden} = State) ->
    case Hidden of
        true ->
            wxWindow:setCursor(Panel, ?wxNullCursor),
            {noreply, State#state{cursor_hidden = false}};
        false ->
            {noreply, State}
    end;

handle_info(#wx{id = ?wxID_OPEN, event = #wxCommand{type = command_menu_selected}}, #state{machine = undefined} = State) ->
    {noreply, State};
handle_info(#wx{id = ?wxID_OPEN, event = #wxCommand{type = command_menu_selected}}, State) ->
    handle_open_file(State);

handle_info(#wx{id = ?wxID_EXIT, event = #wxCommand{type = command_menu_selected}}, State) ->
    init:stop(),    
    {stop, shutdown, State};

handle_info(#wx{id = Id, event = #wxCommand{type = command_menu_selected}},
            #state{machine = undefined} = State) when Id >= ?MENU_RECENT_BASE, Id < ?MENU_RECENT_BASE + ?MAX_RECENT ->
    {noreply, State};
handle_info(#wx{id = Id, event = #wxCommand{type = command_menu_selected}},
            #state{recent_files = RecentFiles} = State) when Id >= ?MENU_RECENT_BASE, Id < ?MENU_RECENT_BASE + ?MAX_RECENT ->
    Idx = Id - ?MENU_RECENT_BASE + 1,
    case Idx =< length(RecentFiles) of
        true ->
            File = lists:nth(Idx, RecentFiles),
            case ezx_ui_lib:load_emulator_file(File, State#state.machine_type,
                                               State#state.ay_chip) of
                {ok, NewMachine} ->
                    io:format("Loaded: ~s~n", [File]),
                    NewMachine1 = ezx_ui_mouse:apply_to_machine(State#state.mouse, NewMachine),
                    NewRecent = ezx_recent_files:update(File, State#state.recent_files),
                    ezx_recent_files:rebuild_menu(State#state.menu_bar, NewRecent),
                    {noreply, State#state{machine = NewMachine1, recent_files = NewRecent,
                                          current_file = File,
                                          mouse = ezx_ui_mouse:reset_baseline(State#state.mouse),
                                          audio_filter = new_beeper_filter(),
                                          mix_dc_l = new_mix_dc_filter(),
                                          mix_dc_r = new_mix_dc_filter()}};
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

handle_info(#wx{id = ?MENU_PAUSE, event = #wxCommand{type = command_menu_selected}}, State) ->
    {noreply, toggle_pause(State)};

handle_info(#wx{id = ?MENU_DEBUG_PERF, event = #wxCommand{type = command_menu_selected}}, State) ->
    NewState = State#state{perf_report = not State#state.perf_report},
    save_config(NewState),
    {noreply, NewState};

handle_info(#wx{id = ?MENU_QUICK_SAVE, event = #wxCommand{type = command_menu_selected}}, #state{machine = undefined} = State) ->
    {noreply, State};
handle_info(#wx{id = ?MENU_QUICK_SAVE, event = #wxCommand{type = command_menu_selected}}, State) ->
    quick_save(State);

handle_info(#wx{id = ?MENU_QUICK_LOAD, event = #wxCommand{type = command_menu_selected}}, #state{machine = undefined} = State) ->
    {noreply, State};
handle_info(#wx{id = ?MENU_QUICK_LOAD, event = #wxCommand{type = command_menu_selected}}, State) ->
    quick_load(State);

handle_info(#wx{id = ?MENU_SAVE_STATE, event = #wxCommand{type = command_menu_selected}}, #state{machine = undefined} = State) ->
    {noreply, State};
handle_info(#wx{id = ?MENU_SAVE_STATE, event = #wxCommand{type = command_menu_selected}}, State) ->
    save_state(State);

handle_info(#wx{id = ?MENU_MANAGE_SAVES, event = #wxCommand{type = command_menu_selected}}, State) ->
    manage_saves(State);

handle_info(#wx{id = ?MENU_ABOUT, event = #wxCommand{type = command_menu_selected}}, #state{frame = Frame} = State) ->
    ezx_about_dialog:show(Frame),
    {noreply, State};

handle_info(#wx{id = ?MENU_SETTINGS_MOUSE, event = #wxCommand{type = command_menu_selected}},
            #state{frame = Frame, mouse = Mouse} = State) ->
    Refs = ezx_mouse_dialog:open(Frame, ezx_ui_mouse:enabled(Mouse),
                                 ezx_ui_mouse:swap_buttons(Mouse)),
    {noreply, State#state{mouse_dialog_refs = Refs}};

handle_info(#wx{id = ?wxID_OK, event = #wxCommand{type = command_button_clicked}},
            #state{mouse_dialog_refs = {Dialog, {Checkbox, SwapCheckbox}}} = State) ->
    Enabled = ezx_mouse_dialog:enabled_from_checkbox(Checkbox),
    Swap = ezx_mouse_dialog:swap_from_checkbox(SwapCheckbox),
    Mouse1 = ezx_ui_mouse:set_swap_buttons(State#state.mouse, Swap),
    {Mouse2, Machine1} = ezx_ui_mouse:set_enabled(Mouse1, State#state.machine, Enabled),
    wxDialog:destroy(Dialog),
    wxWindow:update(State#state.frame),
    NewState = State#state{mouse = Mouse2, machine = Machine1, mouse_dialog_refs = undefined},
    save_config(NewState),
    {noreply, case Enabled of
        true  -> NewState;
        false -> show_cursor(NewState)
    end};

handle_info(#wx{id = ?wxID_CANCEL, event = #wxCommand{type = command_button_clicked}},
            #state{mouse_dialog_refs = {Dialog, _}} = State) ->
    wxDialog:destroy(Dialog),
    {noreply, State#state{mouse_dialog_refs = undefined}};

handle_info(#wx{id = ?MENU_CROP, event = #wxCommand{type = command_menu_selected}}, State) ->
    NewCrop = not State#state.option_crop_border,
    NewState = State#state{option_crop_border = NewCrop,
                           mouse = ezx_ui_mouse:reset_baseline(State#state.mouse)},
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
    NewState = State#state{scale = NewScale, mouse = ezx_ui_mouse:reset_baseline(State#state.mouse)},
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
            #state{frame = Frame, beeper_vol = BV, ay_master_vol = AV,
                   ay_stereo_mode = Mode, ay_chip = Chip} = State) ->
    Refs = ezx_sound_dialog:open(Frame, BV, AV, Mode, Chip),
    {noreply, State#state{sound_dialog_refs = Refs}};

handle_info(#wx{id = ?wxID_OK, event = #wxCommand{type = command_button_clicked}},
            #state{sound_dialog_refs = {Dialog, {BeeperSlider, AySlider, ModeChoice, ChipChoice}}} = State) ->
    BV = wxSlider:getValue(BeeperSlider),
    AV = wxSlider:getValue(AySlider),
    Mode = ezx_sound_dialog:stereo_mode_from_index(wxChoice:getSelection(ModeChoice)),
    Chip = ezx_sound_dialog:chip_from_index(wxChoice:getSelection(ChipChoice)),
    wxDialog:destroy(Dialog),
    wxWindow:update(State#state.frame),
    NewState = State#state{beeper_vol = BV, ay_master_vol = AV, ay_stereo_mode = Mode,
                           ay_chip = Chip, sound_dialog_refs = undefined},
    save_config(NewState),
    case Chip =:= State#state.ay_chip of
        true ->
            {noreply, NewState};
        false ->
            %% The chip is baked into the AY device state at machine init, so
            %% switching it requires a fresh machine (like a reset).
            recreate_machine(NewState)
    end;

handle_info(#wx{id = ?wxID_CANCEL, event = #wxCommand{type = command_button_clicked}},
            #state{sound_dialog_refs = {Dialog, _}} = State) ->
    wxDialog:destroy(Dialog),
    {noreply, State#state{sound_dialog_refs = undefined}};

handle_info(#wx{id = ?wxID_OK, event = #wxCommand{type = command_button_clicked}},
            #state{saves_dialog_refs = {Dialog, _, _, _, _, _}} = State) ->
    wxDialog:destroy(Dialog),
    {noreply, State#state{saves_dialog_refs = undefined, saves_entries = []}};

handle_info(#wx{id = ?BTN_LOAD, event = #wxCommand{type = command_button_clicked}},
            #state{saves_dialog_refs = {Dialog, List, _, _, _, _}, saves_entries = Entries} = State) ->
    load_selected_save(State, Dialog, List, Entries);

handle_info(#wx{id = ?LIST_SAVES, event = #wxList{type = command_list_item_selected}},
            #state{saves_dialog_refs = {_Dialog, List, LoadBtn, DeleteBtn, RenameBtn, Preview},
                   saves_entries = Entries} = State) ->
    Entry = ezx_saves_dialog:selected_entry(List, Entries),
    ezx_saves_dialog:update_buttons(List, Entries, LoadBtn, DeleteBtn, RenameBtn),
    ezx_saves_dialog:update_preview(Preview, Entry),
    {noreply, State};

handle_info(#wx{id = ?LIST_SAVES, event = #wxList{type = command_list_item_activated}},
            #state{saves_dialog_refs = {Dialog, List, _, _, _, _}, saves_entries = Entries} = State) ->
    load_selected_save(State, Dialog, List, Entries);

handle_info(#wx{id = ?BTN_DELETE, event = #wxCommand{type = command_button_clicked}},
            #state{saves_dialog_refs = {_Dialog, List, _, _, _, _}, saves_entries = Entries} = State) ->
    case ezx_saves_dialog:selected_entry(List, Entries) of
        undefined ->
            {noreply, State};
        {Stamp, _Name, _Timestamp, _SavePath, _MetaPath} ->
            ezx_saves:delete_history(saves_root(), Stamp),
            {noreply, refresh_saves_dialog(State)}
    end;

handle_info(#wx{id = ?BTN_RENAME, event = #wxCommand{type = command_button_clicked}},
            #state{saves_dialog_refs = {Dialog, List, _, _, _, _}, saves_entries = Entries} = State) ->
    case ezx_saves_dialog:selected_entry(List, Entries) of
        undefined ->
            {noreply, State};
        {Stamp, Name, _Timestamp, _SavePath, _MetaPath} ->
            NameDlg = wxTextEntryDialog:new(Dialog, "New name for this save:",
                                            [{caption, "Rename Save"}, {value, Name}]),
            case wxDialog:showModal(NameDlg) of
                ?wxID_OK ->
                    NewName = wxTextEntryDialog:getValue(NameDlg),
                    wxTextEntryDialog:destroy(NameDlg),
                    ezx_saves:rename_history(saves_root(), Stamp, NewName),
                    {noreply, refresh_saves_dialog(State)};
                _ ->
                    wxTextEntryDialog:destroy(NameDlg),
                    {noreply, State}
            end
    end;

handle_info(#wx{id = Id, event = #wxCommand{type = command_menu_selected}},
            #state{machine_type = OldType} = State) when Id >= ?MENU_MACHINE_BASE, Id < ?MENU_MACHINE_BASE + 2 ->
    NewType = machine_type_from_offset(Id - ?MENU_MACHINE_BASE),
    case NewType =/= OldType of
        true ->
            case ezx_ui_lib:init_virtual_machine(NewType, State#state.ay_chip) of
                {ok, Machine} ->
                    MenuBar = State#state.menu_bar,
                    Now = erlang:monotonic_time(microsecond),
                    Machine1 = ezx_ui_mouse:apply_to_machine(State#state.mouse, Machine),
                    wxMenuBar:enableTop(MenuBar, 0, true),
                    wxMenuBar:enableTop(MenuBar, 3, true),
                    NewState = State#state{
                        machine = Machine1,
                        machine_type = NewType,
                        frame_count = 0,
                        current_file = undefined,
                        mouse = ezx_ui_mouse:reset_baseline(State#state.mouse),
                        audio_pacing = ezx_audio_pacing:new(audio_bytes_per_frame(Machine1)),
                        perf_start_us = Now,
                        audio_filter = new_beeper_filter(),
                        mix_dc_l = new_mix_dc_filter(),
                        mix_dc_r = new_mix_dc_filter()
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

schedule_frame(Ms) -> erlang:send_after(Ms, self(), frame_tick).

%% Audio: one frame is Samples * 2 channels * 2 bytes (stereo S16LE), where
%% Samples comes from the machine model (see ezx_emulator:samples_per_frame/1).
audio_bytes_per_frame(Machine) -> ezx_emulator:samples_per_frame(Machine) * 4.

%% @doc Open the raw-PCM player port. On Unix aplay (ALSA) is used; on Windows
%% the sox.exe bundled into the app's priv dir (the Windows release ships one),
%% otherwise sox or ffplay from PATH (all play signed 16-bit stereo raw from
%% stdin). Returns `undefined' when no player is available — the frame pipeline
%% still produces PCM, it is just dropped instead of played.
open_audio_port() ->
    case audio_command() of
        none -> undefined;
        Cmd -> open_port({spawn, Cmd}, [binary, stream, exit_status])
    end.

%% @doc Shell command that plays raw stereo S16LE PCM from stdin, or `none'
%% when no suitable player is installed.
audio_command() ->
    case erlang:system_info(os_type) of
        {win32, _} ->
            case bundled_sox() of
                {ok, Path} ->
                    quote_path(Path) ++ " -q -t raw -r 44100 -c 2 -e signed -b 16 - -t waveaudio default";
                none ->
                    case os:find_executable("sox") of
                        false ->
                            case os:find_executable("ffplay") of
                                false -> none;
                                _ -> "ffplay -f s16le -ar 44100 -ac 2 -nodisp -autoexit -i pipe:0"
                            end;
                        _ ->
                            "sox -q -t raw -r 44100 -c 2 -e signed -b 16 - -t waveaudio default"
                    end
            end;
        {unix, _} ->
            "aplay -t raw -f S16_LE -r 44100 -c 2 --buffer-size=3528 --period-size=441 -q 2>/dev/null"
    end.

%% @doc The sox.exe bundled into the app's priv dir (priv/bin/sox.exe), if the
%% Windows release ships one.
bundled_sox() ->
    Path = filename:join([ezx_ui_lib:priv_dir(), "bin", "sox.exe"]),
    case filelib:is_regular(Path) of
        true -> {ok, Path};
        false -> none
    end.

%% @doc Quote a path for open_port({spawn, Cmd}): the release may live in a
%% directory with spaces.
quote_path(Path) -> "\"" ++ Path ++ "\"".

%% @doc Hand PCM to the audio port, or drop it when there is no player. A port
%% that already exited (badarg race with the {'EXIT', ...} message) is ignored.
port_send(undefined, _Data) -> ok;
port_send(Port, Data) ->
    try port_command(Port, Data)
    catch error:badarg -> ok
    end.

toggle_pause(State) ->
    Paused = not State#state.paused,
    ActionsMenu = wxMenuBar:getMenu(State#state.menu_bar, ?MENUBAR_ACTIONS_INDEX),
    wxMenu:check(ActionsMenu, ?MENU_PAUSE, Paused),
    State#state{paused = Paused}.

do_reset(State) ->
    recreate_machine(State).

%% @doc Recreate the machine from scratch (used by reset and by the sound
%% dialog when the chip changes), keeping the UI audio settings. The loaded
%% game no longer exists in the fresh machine, so the current game (used for
%% save names) is cleared.
recreate_machine(State) ->
    case ezx_ui_lib:init_virtual_machine(State#state.machine_type, State#state.ay_chip) of
        {ok, Machine} ->
            Machine1 = ezx_ui_mouse:apply_to_machine(State#state.mouse, Machine),
            Now = erlang:monotonic_time(microsecond),
            {noreply, State#state{machine = Machine1, frame_count = 0,
                                   current_file = undefined,
                                   mouse = ezx_ui_mouse:reset_baseline(State#state.mouse),
                                   audio_pacing = ezx_audio_pacing:new(audio_bytes_per_frame(Machine1)),
                                   perf_start_us = Now,
                                   audio_filter = new_beeper_filter(),
                                   mix_dc_l = new_mix_dc_filter(),
                                   mix_dc_r = new_mix_dc_filter()}};
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

%% @doc Open the load-file dialog (SNA/Z80/TAP). Shown modally — native file
%% dialogs on Windows only support ShowModal (a modeless show creates no
%% window at all), so the emulation briefly pauses while the dialog is open.
%% Starts in the directory of the last loaded file (held in memory only, not
%% persisted), or the current directory the first time.
-spec handle_open_file(#state{}) -> {noreply, #state{}}.
handle_open_file(#state{frame = Frame, file_dialog_dir = Dir} = State) ->
    Options = [{message, "Load snapshot or tape"},
               {wildCard, "ZX Spectrum files (*.sna,*.z80,*.tap)|*.sna;*.z80;*.tap|SNA files (*.sna)|*.sna|Z80 files (*.z80)|*.z80|TAP files (*.tap)|*.tap"},
               {style, ?wxFD_OPEN bor ?wxFD_FILE_MUST_EXIST}],
    Options1 = case Dir of
                   undefined -> Options;
                   _ -> [{defaultDir, Dir} | Options]
               end,
    Dialog = wxFileDialog:new(Frame, Options1),
    case wxDialog:showModal(Dialog) of
        ?wxID_OK ->
            File = wxFileDialog:getPath(Dialog),
            wxFileDialog:destroy(Dialog),
            load_file_result(File, State);
        _ ->
            wxFileDialog:destroy(Dialog),
            {noreply, State}
    end.

%% @doc Load a snapshot/tape chosen via the file dialog: build the machine,
%% thread the mouse config through, update the recent-files menu and reset the
%% audio filters (stale beeper/DC states must not carry into the new machine).
-spec load_file_result(string(), #state{}) -> {noreply, #state{}}.
load_file_result(File, #state{machine_type = MachineType, ay_chip = AyChip} = State) ->
    case ezx_ui_lib:load_emulator_file(File, MachineType, AyChip) of
        {ok, NewMachine} ->
            io:format("Loaded: ~s~n", [File]),
            NewMachine1 = ezx_ui_mouse:apply_to_machine(State#state.mouse, NewMachine),
            NewRecent = ezx_recent_files:update(File, State#state.recent_files),
            ezx_recent_files:rebuild_menu(State#state.menu_bar, NewRecent),
            {noreply, State#state{machine = NewMachine1, recent_files = NewRecent,
                                   current_file = File,
                                   file_dialog_dir = filename:dirname(File),
                                   mouse = ezx_ui_mouse:reset_baseline(State#state.mouse),
                                   audio_filter = new_beeper_filter(),
                                   mix_dc_l = new_mix_dc_filter(),
                                   mix_dc_r = new_mix_dc_filter()}};
        {error, _Code} = Err ->
            show_load_error(State#state.frame, File, Err),
            {noreply, State}
    end.

%% --- Save / load state ---

saves_root() ->
    filename:join(ezx_ui_lib:app_dir(), "saves").

%% @doc Set the transient save/load toast. The drawing itself is done in
%% draw_frame/2 while the field is set; a timer message clears it after
%% ?TOAST_MS. The ref guards against an old timer clearing a newer toast.
set_toast(State, Icon) ->
    Ref = make_ref(),
    erlang:send_after(?TOAST_MS, self(), {clear_toast, Ref}),
    State#state{toast = {Ref, Icon}}.

%% @doc The source game file that scopes save names; "" when nothing is
%% loaded (saves are then named "Basic").
current_source(State) ->
    case State#state.current_file of
        undefined -> "";
        File -> File
    end.

%% @doc UI sound settings carried into the .meta sidecar under `sound_' keys.
%% @doc Quick save (F5): overwrite the quick slot and append a history entry.
quick_save(State) ->
    case ezx_saves:quick_save(State#state.machine, saves_root(),
                              current_source(State)) of
        {ok, ArchiveZ80} ->
            io:format("Quick save written~n"),
            write_quick_screenshots(State, ArchiveZ80),
            {noreply, set_toast(State, save)};
        {error, Reason} ->
            io:format("Quick save failed: ~p~n", [Reason]),
            {noreply, State}
    end.

%% @doc Write the playfield screenshot sidecars for both files a quick save
%% just wrote: the fixed slot and the archive copy. ArchiveZ80 is the path
%% quick_save actually wrote — the timestamped, uniquified name is only known
%% there, so it is passed back rather than recomputed. Best-effort — a
%% failing screenshot never fails the save itself.
write_quick_screenshots(#state{machine = Machine}, ArchiveZ80) ->
    case ezx_saves:quick_path(saves_root()) of
        {ok, SlotZ80, _} -> write_screenshot(Machine, SlotZ80);
        none -> ok
    end,
    write_screenshot(Machine, ArchiveZ80),
    ok.

%% @doc Quick load (F9): restore the fixed `Last Quicksave` slot, no matter
%% which (if any) game is loaded. No-op when there is no quick save yet.
quick_load(State) ->
    case ezx_saves:quick_path(saves_root()) of
        {ok, SnaPath, MetaPath} -> load_save(State, SnaPath, MetaPath);
        none -> {noreply, State}
    end.

%% @doc Named save (F2): prompt for a name and append a history entry. The
%% dialog pre-fills the loaded game's title (or "Basic" when nothing is
%% loaded) as a suggestion.
save_state(#state{frame = Frame} = State) ->
    Suggested = ezx_saves:program_name(current_source(State)),
    NameDlg = wxTextEntryDialog:new(Frame, "Enter a name for this save:",
                                    [{caption, "Save State"}, {value, Suggested}]),
    case wxDialog:showModal(NameDlg) of
        ?wxID_OK ->
            Name = wxTextEntryDialog:getValue(NameDlg),
            wxTextEntryDialog:destroy(NameDlg),
            do_save_state(State, Name);
        _ ->
            wxTextEntryDialog:destroy(NameDlg),
            {noreply, State}
    end.

do_save_state(State, Name) ->
    case ezx_saves:save_history(State#state.machine, saves_root(),
                                current_source(State), Name) of
        {ok, Path} ->
            io:format("Save state: ~s~n", [Path]),
            write_screenshot(State#state.machine, Path),
            {noreply, set_toast(State, save)};
        {error, Reason} ->
            io:format("Save state failed: ~p~n", [Reason]),
            {noreply, State}
    end.

%% @doc Open the modeless saves-manager dialog. No-op when a manager dialog
%% is already open.
manage_saves(#state{saves_dialog_refs = undefined} = State) ->
    Entries = ezx_saves:list_history(saves_root()),
    Refs = ezx_saves_dialog:open(State#state.frame, Entries),
    {noreply, State#state{saves_dialog_refs = Refs, saves_entries = Entries}};
manage_saves(State) ->
    {noreply, State}.

%% @doc Reload the manager list after a change (load/delete/rename/save) and
%% keep the refs so the dialog stays open. The list always reflects the
%% current game context, which a successful load may have changed.
refresh_saves_dialog(#state{saves_dialog_refs = Refs} = State) ->
    Entries = ezx_saves:list_history(saves_root()),
    ezx_saves_dialog:refresh(Refs, Entries),
    State#state{saves_entries = Entries}.

%% @doc Load the save selected in the manager list box (used by the Load
%% button and by a double click on an entry), then close the dialog.
load_selected_save(State, Dialog, List, Entries) ->
    case ezx_saves_dialog:selected_entry(List, Entries) of
        undefined ->
            {noreply, State};
        {_Stamp, _Name, _Timestamp, SavePath, MetaPath} ->
            wxDialog:destroy(Dialog),
            {noreply, State1} = load_save(State, SavePath, MetaPath),
            {noreply, State1#state{saves_dialog_refs = undefined, saves_entries = []}}
    end.

%% @doc Restore a save: ezx_saves:load_save/3 loads the snapshot, picks the
%% machine of the save's own type/chip, and applies the audio side (beeper/AY
%% regs) from the meta. Here we only reconfigure the UI around the returned
%% machine and metadata: mouse, pacing and the current game (from the save's
%% source). UI settings (sound volumes, stereo mode, ...) stay untouched.
%% Returns {noreply, NewState}; on failure the machine is left untouched.
load_save(State, SavePath, MetaPath) ->
    case ezx_saves:load_save(SavePath, MetaPath,
                             State#state.ay_chip) of
        {ok, NewMachine0, Meta} ->
            io:format("Loaded save: ~s~n", [SavePath]),
            TargetType = meta_atom(Meta, "machine_type", '48k'),
            Chip = meta_atom(Meta, "ay_chip", State#state.ay_chip),
            NewMachine = ezx_ui_mouse:apply_to_machine(State#state.mouse, NewMachine0),
            Now = erlang:monotonic_time(microsecond),
            NewState = State#state{
                machine = NewMachine,
                machine_type = TargetType,
                ay_chip = Chip,
                current_file = meta_source(Meta, State#state.current_file),
                frame_count = 0,
                mouse = ezx_ui_mouse:reset_baseline(State#state.mouse),
                audio_pacing = ezx_audio_pacing:new(audio_bytes_per_frame(NewMachine)),
                perf_start_us = Now,
                audio_filter = new_beeper_filter(),
                mix_dc_l = new_mix_dc_filter(),
                mix_dc_r = new_mix_dc_filter()
            },
            check_machine_type_menu(NewState),
            {noreply, set_toast(NewState, load)};
        {error, _Code} = Err ->
            show_load_error(State#state.frame, SavePath, Err),
            {noreply, State}
    end.

meta_source(undefined, Default) -> Default;
meta_source(Meta, Default) ->
    case maps:get("source", Meta, undefined) of
        undefined -> Default;
        S -> S
    end.

meta_atom(Meta, Key, Default) ->
    case maps:get(Key, Meta, undefined) of
        undefined -> Default;
        Str ->
            try list_to_atom(Str)
            catch _:_ -> Default
            end
    end.

%% @doc Sync the Emulator menu radio with the machine type after a save
%% restored a different machine.
check_machine_type_menu(#state{menu_bar = MenuBar, machine_type = MType}) ->
    EmulatorMenu = wxMenuBar:getMenu(MenuBar, 1),
    wxMenu:check(EmulatorMenu, ?MENU_MACHINE_BASE + machine_type_offset(MType), true),
    ok.

reenter_crop_fullscreen(#state{frame = Frame, fullscreen_size = {SW, SH}} = State) ->
    wxFrame:showFullScreen(Frame, false),
    wxFrame:showFullScreen(Frame, true),
    {NewScale, OffX, OffY} = calc_scale_offset(true, SW, SH),
    ExactScale = case State#state.option_integer_scaling of
        true  ->
            case SW / ?DEFAULT_WIDTH >= SH / ?DEFAULT_HEIGHT of
                true  -> SH / ?CROP_HEIGHT;
                false -> SW / ?CROP_WIDTH
            end;
        false -> 1.0
    end,
    {noreply, State#state{scale = NewScale, crop_off = {OffX, OffY},
                          mouse = ezx_ui_mouse:reset_baseline(State#state.mouse),
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
                true  -> SH / ?CROP_HEIGHT;          %% wide screen: CROP_HEIGHT visible rows (8px border T+B)
                false -> SW / ?CROP_WIDTH            %% tall screen: CROP_WIDTH visible cols (8px border L+R)
            end;
        false -> 1.0
    end,
    {noreply, State#state{fullscreen = true,
                          scale = NewScale, windowed_scale = WindowedScale, crop_off = {OffX, OffY},
                          crop_exact_scale = ExactScale,
                          mouse = ezx_ui_mouse:reset_baseline(State#state.mouse),
                          fullscreen_size = {SW, SH},
                          windowed_size = WinSize}};
toggle_fullscreen(#state{frame = Frame, fullscreen = true, windowed_scale = WindowedScale,
                         windowed_size = {WW, WH}} = State) ->
    wxFrame:showFullScreen(Frame, false),
    wxFrame:setSize(Frame, WW, WH),
    {noreply, State#state{fullscreen = false,
                          scale = WindowedScale, crop_off = {0, 0},
                          mouse = ezx_ui_mouse:reset_baseline(State#state.mouse),
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
        true  -> {?CROP_WIDTH, ?CROP_HEIGHT};
        false -> {?DEFAULT_WIDTH, ?DEFAULT_HEIGHT}
    end,
    {TW * S, TH * S}.

%% @doc Set the app icon on the main window (titlebar/taskbar). The icon file
%% lives in priv/ (bundled into releases); a missing file is not an error.
set_frame_icon(Frame) ->
    case icon_file() of
        {ok, Path} ->
            Icon = wxIcon:new(Path, []),
            wxFrame:setIcon(Frame, Icon),
            wxIcon:destroy(Icon);
        error ->
            ok
    end.

%% @doc Resolve the icon PNG inside the app's priv directory.
icon_file() ->
    Path = filename:join(ezx_ui_lib:priv_dir(), "ezx.png"),
    case filelib:is_file(Path) of
        true -> {ok, Path};
        false -> error
    end.

%% @doc Write the screenshot sidecar for a save just written: the last frame's
%% playfield (256x192, no border) encoded as a PNG next to the `.z80`. The UI
%% captures this, not ezx_saves, which stays free of wx. Best-effort: any
%% failure (no machine, unreadable frame) silently skips the screenshot.
write_screenshot(Machine, Z80Path) when Machine =/= undefined ->
    try
        PngPath = ezx_saves:png_path(Z80Path),
        Image = wxImage:new(?SCREEN_WIDTH, ?SCREEN_HEIGHT,
                            playfield_pixels(ezx_emulator:render_frame(Machine))),
        _ = wxImage:saveFile(Image, PngPath, ?wxBITMAP_TYPE_PNG),
        wxImage:destroy(Image),
        ok
    catch _:_ -> ok end;
write_screenshot(_Machine, _Z80Path) ->
    ok.

%% @doc Crop the border off a 352x288 RGB frame, keeping the 256x192 playfield
%% (48 border pixels per side).
playfield_pixels(RGB) ->
    RowBytes = ?SCREEN_WIDTH * 3,
    BorderCols = (?DEFAULT_WIDTH - ?SCREEN_WIDTH) div 2 * 3,
    BorderRows = (?DEFAULT_HEIGHT - ?SCREEN_HEIGHT) div 2,
    iolist_to_binary(
      [binary:part(RGB, (BorderRows + R) * (?DEFAULT_WIDTH * 3) + BorderCols, RowBytes)
       || R <- lists:seq(0, ?SCREEN_HEIGHT - 1)]).

%% @doc Blit the 352x288 RGB frame onto the panel, honoring crop, scale and
%% fullscreen mode. Used both for running frames and for the frozen display
%% while paused.
draw_frame(State, RGB) ->
    Panel = State#state.panel,
    Scale = State#state.scale,
    Image0 = wxImage:new(?DEFAULT_WIDTH, ?DEFAULT_HEIGHT, RGB),
    ClientDC = wxClientDC:new(Panel),
    {PW0, PH0} = wxWindow:getClientSize(Panel),
    {PW, PH} = case State#state.fullscreen_size of
        {SW, SH} -> {SW, SH};
        undefined -> {PW0, PH0}
    end,
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
            BorderOff = round(?BORDER_TRIM * ES),
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
            BorderOff = ?BORDER_TRIM * Scale,
            DDX = max(0, (PW - ?CROP_WIDTH * Scale) div 2) - BorderOff,
            DDY = max(0, (PH - ?CROP_HEIGHT * Scale) div 2) - BorderOff,
            {B, DDX, DDY, Scale};
        {false, false} ->
            B = wxBitmap:new(Image0),
            wxImage:destroy(Image0),
            {OffX, OffY} = State#state.crop_off,
            DDX = max(0, (PW - ?DEFAULT_WIDTH * Scale) div 2),
            DDY = max(0, (PH - ?DEFAULT_HEIGHT * Scale) div 2),
            {B, DDX - OffX * Scale, DDY - OffY * Scale, Scale}
    end,
    wxDC:setDeviceOrigin(BufDC, DX, DY),
    wxDC:setUserScale(BufDC, UseBmpScale, UseBmpScale),
    wxDC:drawBitmap(BufDC, Bmp, {0, 0}),
    wxDC:setUserScale(BufDC, 1.0, 1.0),
    wxDC:setDeviceOrigin(BufDC, 0, 0),
    draw_toast(State, BufDC, PW, PH),
    wxBufferedDC:destroy(BufDC),
    wxClientDC:destroy(ClientDC),
    wxBitmap:destroy(Bmp).

%% @doc Show the save/load toast icon as a box one third of the panel, centered
%% (see set_toast/2). Drawn with wxDC primitives into the same double-buffered
%% pass as the frame, so it never flickers and stays visible in every mode
%% (crop, scale, fullscreen) without touching the emulated pixels.
draw_toast(#state{toast = {_, Icon}}, DC, PW, PH) ->
    W = PW div 3,
    H = PH div 3,
    X = (PW - W) div 2,
    Y = (PH - H) div 2,
    wxDC:setBrush(DC, wxBrush:new(?TOAST_BG)),
    wxDC:setPen(DC, wxPen:new(?TOAST_BORDER, [{width, 2}])),
    wxDC:drawRoundedRectangle(DC, {X, Y, W, H}, max(6, W div 12)),
    M = W div 6,
    S = (W - 2 * M) / 48.0,
    draw_toast_icon(DC, X + M, Y + (H - round(21 * S)) div 2, S, Icon),
    ok;
draw_toast(#state{toast = undefined}, _DC, _PW, _PH) ->
    ok.

%% @doc The toast pictogram composed of a monitor, a floppy and an arrow
%% between them, drawn with filled shapes scaled by S (base 48x32). Save:
%% monitor -> floppy (screen on the left, arrow pointing right). Load: floppy
%% -> monitor (floppy on the left, arrow pointing right).
draw_toast_icon(DC, X, Y, S, save) ->
    draw_toast_screen(DC, X, Y, S),
    draw_toast_floppy(DC, X + 32 * S, Y, S),
    draw_toast_arrow(DC, X + 19 * S, Y + 7 * S, S),
    ok;
draw_toast_icon(DC, X, Y, S, load) ->
    draw_toast_floppy(DC, X + 1 * S, Y, S),
    draw_toast_screen(DC, X + 30 * S, Y, S),
    draw_toast_arrow(DC, X + 18 * S, Y + 7 * S, S),
    ok.

%% @doc A monitor: bezel with a dark screen, stand and base.
draw_toast_screen(DC, X, Y, S) ->
    wxDC:setBrush(DC, wxBrush:new(?TOAST_ICON)),
    wxDC:setPen(DC, wxPen:new(?TOAST_ICON)),
    wxDC:drawRoundedRectangle(DC, {round(X + 1 * S), round(Y + 2 * S),
                                   round(16 * S), round(12 * S)}, round(2 * S)),
    wxDC:setBrush(DC, wxBrush:new(?TOAST_BG)),
    wxDC:setPen(DC, wxPen:new(?TOAST_BG)),
    wxDC:drawRectangle(DC, {round(X + 3 * S), round(Y + 4 * S),
                            round(12 * S), round(8 * S)}),
    wxDC:setBrush(DC, wxBrush:new(?TOAST_ICON)),
    wxDC:setPen(DC, wxPen:new(?TOAST_ICON)),
    wxDC:drawRectangle(DC, {round(X + 6 * S), round(Y + 14 * S),
                            round(4 * S), round(3 * S)}),
    wxDC:drawRectangle(DC, {round(X + 3 * S), round(Y + 17 * S),
                            round(10 * S), round(2 * S)}),
    ok.

%% @doc A floppy disk: rounded body, dark label band, right shutter strip.
draw_toast_floppy(DC, X, Y, S) ->
    wxDC:setBrush(DC, wxBrush:new(?TOAST_ICON)),
    wxDC:setPen(DC, wxPen:new(?TOAST_ICON)),
    wxDC:drawRoundedRectangle(DC, {round(X), round(Y + 3 * S),
                                   round(15 * S), round(12 * S)}, round(2 * S)),
    wxDC:setBrush(DC, wxBrush:new(?TOAST_BG)),
    wxDC:setPen(DC, wxPen:new(?TOAST_BG)),
    wxDC:drawRectangle(DC, {round(X + 2 * S), round(Y + 4 * S),
                            round(11 * S), round(3 * S)}),
    wxDC:setBrush(DC, wxBrush:new(?TOAST_ICON)),
    wxDC:setPen(DC, wxPen:new(?TOAST_ICON)),
    wxDC:drawRectangle(DC, {round(X + 12 * S), round(Y + 4 * S),
                            round(2 * S), round(10 * S)}),
    wxDC:setBrush(DC, wxBrush:new(?TOAST_BG)),
    wxDC:setPen(DC, wxPen:new(?TOAST_BG)),
    wxDC:drawRectangle(DC, {round(X + 10 * S), round(Y + 13 * S),
                            round(2 * S), round(1 * S)}),
    ok.

%% @doc A right-pointing arrow: shaft plus a filled head.
draw_toast_arrow(DC, X, Y, S) ->
    wxDC:setBrush(DC, wxBrush:new(?TOAST_ICON)),
    wxDC:setPen(DC, wxPen:new(?TOAST_ICON)),
    wxDC:drawRectangle(DC, {round(X), round(Y), round(8 * S), round(2 * S)}),
    wxDC:drawPolygon(DC, [{round(X + 8 * S), round(Y - 2 * S)},
                          {round(X + 13 * S), round(Y + 1 * S)},
                          {round(X + 8 * S), round(Y + 4 * S)}]),
    ok.



save_config(#state{machine_type = MType, option_crop_border = Crop, option_integer_scaling = Exact,
                   muted = Muted, scale = Scale, beeper_vol = BV, ay_master_vol = AV,
                   ay_stereo_mode = Mode, ay_chip = Chip,
                   perf_report = PerfReport, mouse = Mouse}) ->
    ezx_config:save(#{machine_type => MType, crop_border => Crop, integer_scaling => Exact,
                       muted => Muted, scale => Scale,
                       beeper_vol => BV, ay_master_vol => AV, ay_stereo_mode => Mode,
                       ay_chip => Chip,
                       perf_report => PerfReport,
                       kempston_mouse => ezx_ui_mouse:enabled(Mouse),
                       mouse_swap_buttons => ezx_ui_mouse:swap_buttons(Mouse)}).

%% @doc Update the Kempston button mask from a host mouse button event.
%% Buttons are active-low: pressed = bit cleared. Note: motion events
%% during a drag do not feed deltas on Linux/Gtk (the panel is not
%% capturing the mouse); this matches Fuse behaviour and the guest tester.
mouse_button(#state{machine = Machine, mouse = Mouse} = State, Button, Pressed) ->
    {Mouse1, Machine1} = ezx_ui_mouse:button(Mouse, Machine, Button, Pressed),
    {noreply, State#state{machine = Machine1, mouse = Mouse1}}.

%% @doc Restore the default (visible) host cursor over the panel. No-op
%% when it is not currently hidden.
show_cursor(#state{cursor_hidden = true, panel = Panel} = State) ->
    wxWindow:setCursor(Panel, ?wxNullCursor),
    State#state{cursor_hidden = false};
show_cursor(State) ->
    State.

%% @doc Blank the host cursor over the panel while the Kempston mouse is
%% enabled. Called on motion as well as on enter_window: the enter/leave
%% events are swallowed when the pointer returns from a menu (popups grab
%% the pointer), so any motion over the panel re-hides the cursor.
hide_cursor(#state{cursor_hidden = false, mouse = Mouse, panel = Panel, blank_cursor = Cursor} = State) ->
    case ezx_ui_mouse:enabled(Mouse) of
        true ->
            wxWindow:setCursor(Panel, Cursor),
            State#state{cursor_hidden = true};
        false ->
            State
    end;
hide_cursor(State) ->
    State.

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

%% --- Audio filters ---

%% Beeper filter state: full speaker model (LPF + HPF).
new_beeper_filter() ->
    ezx_audio_filter:new(#{lpf => ?BEEPER_LPF_ALPHA, hpf => ?BEEPER_HPF_ALPHA}).

%% Mix DC blocker state: HPF only, one state per output channel.
new_mix_dc_filter() ->
    ezx_audio_filter:new(#{hpf => ?BEEPER_HPF_ALPHA}).

%% @doc AC-couple the stereo mix, one filter call per channel (the filter
%% itself is mono and channel-agnostic).
dc_block_stereo(PCM, StL, StR) ->
    {LB, RB} = deinterleave_stereo(PCM),
    {LB1, StL1} = ezx_audio_filter:filter(LB, StL),
    {RB1, StR1} = ezx_audio_filter:filter(RB, StR),
    {interleave_stereo(LB1, RB1), StL1, StR1}.

deinterleave_stereo(PCM) ->
    Ls = [L || <<L:16/signed-little, _:16/signed-little>> <= PCM],
    Rs = [R || <<_:16/signed-little, R:16/signed-little>> <= PCM],
    {list_to_binary([<<L:16/signed-little>> || L <- Ls]),
     list_to_binary([<<R:16/signed-little>> || R <- Rs])}.

interleave_stereo(LBin, RBin) ->
    Ls = [L || <<L:16/signed-little>> <= LBin],
    Rs = [R || <<R:16/signed-little>> <= RBin],
    list_to_binary([<<L:16/signed-little, R:16/signed-little>> || {L, R} <- lists:zip(Ls, Rs)]).

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

%% @doc Destroy any dialogs still open (the main window is closing).
-spec cleanup_dialogs(#state{}) -> ok.
cleanup_dialogs(#state{sound_dialog_refs = Sound, mouse_dialog_refs = Mouse,
                       saves_dialog_refs = Saves}) ->
    destroy_dialog(Sound),
    destroy_dialog(Mouse),
    destroy_dialog(Saves).

%% @doc Destroy a single open dialog ref ({Dialog, Controls}). `undefined'
%% means no dialog is open.
-spec destroy_dialog(undefined | {wxDialog:wxDialog() | wxFileDialog:wxFileDialog(), any()}) -> ok.
destroy_dialog(undefined) -> ok;
destroy_dialog({Dialog, _}) -> wxDialog:destroy(Dialog).

%% @doc A dialog asked to close (title-bar X or wxClose event). The dialog is
%% identified by its stored reference and destroyed, and the matching state
%% field is cleared. Objects that are not a tracked dialog are ignored.
-spec close_dialog(wxWindow:wxWindow(), #state{}) -> #state{}.
close_dialog(Obj, #state{sound_dialog_refs = {Dialog, _}} = State) when Obj =:= Dialog ->
    wxDialog:destroy(Obj),
    State#state{sound_dialog_refs = undefined};
close_dialog(Obj, #state{mouse_dialog_refs = {Dialog, _}} = State) when Obj =:= Dialog ->
    wxDialog:destroy(Obj),
    State#state{mouse_dialog_refs = undefined};
close_dialog(Obj, #state{saves_dialog_refs = {Dialog, _, _, _, _, _}} = State) when Obj =:= Dialog ->
    wxDialog:destroy(Obj),
    State#state{saves_dialog_refs = undefined, saves_entries = []};
close_dialog(_Obj, State) ->
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

%% Timestamped name for a Ctrl+F12 state dump (one file per dump, no overwrites).
dump_filename() ->
    {{Y, Mo, D}, {H, Mi, S}} = calendar:local_time(),
    io_lib:format("state-~4..0B~2..0B~2..0B-~2..0B~2..0B~2..0B.bin",
                  [Y, Mo, D, H, Mi, S]).