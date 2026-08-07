{* UltraStar Deluxe - Karaoke Game
 *
 * UltraStar Deluxe is the legal property of its developers, whose names
 * are too numerous to list here. Please refer to the COPYRIGHT
 * file distributed with this source distribution.
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; see the file COPYING. If not, write to
 * the Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
 * Boston, MA 02110-1301, USA.
 *
 * $URL: https://ultrastardx.svn.sourceforge.net/svnroot/ultrastardx/trunk/src/base/UMain.pas $
 * $Id: UMain.pas 2631 2010-09-05 15:26:08Z tobigun $
 *}

unit UMain;

interface

{$IFDEF FPC}
  {$MODE Delphi}
{$ENDIF}

{$I switches.inc}

uses
  SysUtils,
  SDL3;

var
  CheckMouseButton: boolean; // for checking mouse motion
  MAX_FPS: Byte; // 0 to 255 is enough


procedure Main;
procedure MainLoop;
procedure CheckEvents;
procedure StartTextInput;
procedure StopTextInput;
procedure SetTextInput(enabled: boolean);

type
  TMainThreadExecProc = procedure(Data: Pointer);

const
  MAINTHREAD_EXEC_EVENT = SDL_EVENT_USER + 2;

{*
 * Delegates execution of procedure Proc to the main thread.
 * The Data pointer is passed to the procedure when it is called.
 * The main thread is notified by signaling a MAINTHREAD_EXEC_EVENT which
 * is handled in CheckEvents.
 * Note that Data must not be a pointer to local data. If you want to pass local
 * data, use Getmem() or New() or create a temporary object.
 *}
procedure MainThreadExec(Proc: TMainThreadExecProc; Data: Pointer);

implementation

uses
  math,
  UCommandLine,
  UCommon,
  UConfig,
  UDataBase,
  UDllManager,
  UDisplay,
  UGraphic,
  UGraphicClasses,
  UHelp,
  UIni,
  UJoystick,
  ULanguage,
  ULog,
  UPathUtils,
  UPlaylist,
  UMusic,
  URecord,
  UBeatTimer,
  UPlatform,
  URenderer,
  USkins,
  UThemes,
  UParty,
  UPartyTournament,
  ULuaCore,
  ULuaRenderer,
  ULuaLog,
  ULuaTexture,
  ULuaText,
  ULuaParty,
  ULuaScreenSing,
  UTime,
  UWebcam;
  //UVideoAcinerella;

procedure Main;
var
  WindowTitle: string;
begin
  {$IFNDEF Debug}
  try
  {$ENDIF}
    SetMultiByteConversionCodePage(CP_UTF8);
    WindowTitle := USDXVersionStr;

    Platform.Init;
    Log.Title := WindowTitle;
    Log.FileOutputEnabled := true;
    
    // Commandline Parameter Parser
    Params := TCMDParams.Create;

    if Platform.TerminateIfAlreadyRunning(WindowTitle) then
      Exit;

    // fix floating-point exceptions (FPE)
    DisableFloatingPointExceptions();
    // fix the locale for string-to-float parsing in C-libs
    SetDefaultNumericLocale();

    // setup separators for parsing
    // Note: ThousandSeparator must be set because of a bug in TIniFile.ReadFloat
    DefaultFormatSettings.ThousandSeparator := ',';
    DefaultFormatSettings.DecimalSeparator := '.';

    //------------------------------
    // StartUp - create classes and load files
    //------------------------------

    // initialize SDL
    SDL_Init(SDL_INIT_VIDEO);
    //SDL_EnableUnicode(1);  //not necessary in SDL3 any more

    // create luacore first so other classes can register their events
    LuaCore := TLuaCore.Create;


    USTime := TTime.Create;
    VideoBGTimer := TRelativeTimer.Create;

    // Language
    Log.LogStatus('Initialize Paths', 'Initialization');
    InitializePaths;
    Log.SetLogFileLevel(50);
    Log.LogStatus('Load Language', 'Initialization');
    Language := TLanguage.Create;

    // add const values:
    Language.AddConst('US_VERSION', USDXVersionStr);

    // Skin
    Log.BenchmarkStart(1);
    Log.LogStatus('Loading Skin List', 'Initialization');
    Skin := TSkin.Create;

    Log.LogStatus('Loading Theme List', 'Initialization');
    Theme := TTheme.Create;
    Log.LogStatus('Website-Manager', 'Initialization');
    DLLMan := TDLLMan.Create;   // Load WebsiteList
    Log.LogStatus('DataBase System', 'Initialization');
    DataBase := TDataBaseSystem.Create;

    if (Params.ScoreFile.IsUnset) then
      DataBase.Init(Platform.GetGameUserPath.Append('Ultrastar.db'))
    else
      DataBase.Init(Params.ScoreFile);

    // Ini + Paths
    Log.LogStatus('Load Ini', 'Initialization');
    Ini := TIni.Create;
    Ini.Load;

    // Help
    Log.LogStatus('Load Help', 'Initialization');
    Help := THelp.Create;

    // it is possible that this is the first run, create a .ini file if neccessary
    Log.LogStatus('Write Ini', 'Initialization');
    Ini.Save;

    // Theme
    Theme.LoadTheme(Ini.Theme, Ini.Color);

    // Sound
    InitializeSound();

    // Lyrics-engine with media reference timer
    LyricsState := TLyricsState.Create();

    // Graphics
    Initialize3D(WindowTitle);

    // Playlist Manager
    Log.LogStatus('Playlist Manager', 'Initialization');
    PlaylistMan := TPlaylistManager.Create;

    // GoldenStarsTwinkleMod
    Log.LogStatus('Effect Manager', 'Initialization');
    GoldenRec := TEffectManager.Create;

    // Joypad
    if (Ini.Joypad = 1) or (Params.Joypad) then
    begin
      InitializeJoystick;
    end;
    
    // Webcam
    //Log.LogStatus('WebCam', 'Initialization');
    Webcam := TWebcam.Create;

    // Lua
    Party := TPartyGame.Create;
    PartyTournament := TPartyTournament.Create;

    LuaCore.RegisterModule('Log', ULuaLog_Lib_f);
    LuaCore.RegisterModule('Renderer', ULuaRenderer_Lib_f);
    LuaCore.RegisterModule('Text', ULuaText_Lib_f);
    LuaCore.RegisterModule('Party', ULuaParty_Lib_f);
    LuaCore.RegisterModule('ScreenSing', ULuaScreenSing_Lib_f);

    LuaCore.LoadPlugins;

    LuaCore.DumpPlugins;

    { prepare software cursor }
    Display.SetCursor;

    {**
      * Start background music
      *}
    SoundLib.StartBgMusic;

    //------------------------------
    // Start Mainloop
    //------------------------------
    Log.LogStatus('Main Loop', 'Initialization');
    MainLoop;

  {$IFNDEF Debug}
  finally
  {$ENDIF}
    //------------------------------
    // Finish Application
    //------------------------------

    // TODO:
    // call an uninitialize routine for every initialize step
    // or at least use the corresponding Free methods

    Log.LogStatus('Closing DB file', 'Finalization');
    if (DataBase <> nil) then
    begin
         DataBase.Destroy();
    end;

    Log.LogStatus('Finalize Media', 'Finalization');
    FinalizeMedia();

    FinalizeJoyStick;

    Log.LogStatus('Uninitialize 3D', 'Finalization');
    Finalize3D();

    Log.LogStatus('Finalize SDL', 'Finalization');
    SDL_Quit();

    Log.LogStatus('Finalize Log', 'Finalization');
  {$IFNDEF Debug}
  end;
  {$ENDIF}
end;

procedure StartTextInput;
begin
  SDL_StartTextInput(Screen);
end;

procedure StopTextInput;
begin
  SDL_StopTextInput(Screen);
end;

procedure SetTextInput(enabled: boolean);
begin
  if enabled then StartTextInput else StopTextInput;
end;

procedure MainLoop;
var
  Delay:            integer;
  TicksCurrent:     cardinal;
  TicksBeforeFrame: cardinal;
  Done:             boolean;
  Report: string;
  I,J: Integer;
begin
  Max_FPS := Ini.MaxFramerateGet;
  // need to explicitly stop this because it appears to be started by default
  SDL_StopTextInput(Screen);
  Done := false;
  J := 1;
  CountSkipTime();
  repeat
    try
    begin
      TicksBeforeFrame := SDL_GetTicks;

      // keyboard/mouse/joystick events
      CheckEvents;

      // display
      Done := not Display.Draw;
      Renderer.SwapBuffers;

      // FPS limiter
      TicksCurrent := SDL_GetTicks;
      Delay := 1000 div MAX_FPS - (TicksCurrent - TicksBeforeFrame);

      if Delay >= 1 then
        SDL_Delay(Delay);

      CountSkipTime;
      J:=1;
    end
    except
      on E : Exception do
      begin
        J := J+1;
        if J > 1 then
        begin
          Report := 'Sorry, an error ocurred! Please report this error to the game-developers. Also check the Error.log file in the game folder.' + LineEnding +
            'Stacktrace:' + LineEnding;
          if E <> nil then begin
            Report := Report + 'Exception class: ' + E.ClassName + LineEnding +
            'Message: ' + E.Message + LineEnding;
          end;
          Report := Report + BackTraceStrFunc(ExceptAddr);
          for I := 0 to ExceptFrameCount - 1 do
            Report := Report + LineEnding + BackTraceStrFunc(ExceptFrames[I]);
          ShowMessage(Report);
          done := true;
        end
        else
        begin
          done := false;
        end;
      end;
    end;
  until Done;

end;

procedure DoQuit;
begin
  // if question option is enabled then show exit popup
  if (Ini.AskbeforeDel = 1) then
  begin
    Display.CurrentScreen^.CheckFadeTo(nil,'MSG_QUIT_USDX');
  end
  else // if ask-for-exit is disabled then simply exit
  begin
    Display.Fade := 0;
    Display.NextScreenWithCheck := nil;
    Display.CheckOK := true;
  end;
end;

procedure CheckEvents;
var
  Event:     TSDL_event;
  SimEvent:  TSDL_event;
  KeyCharUnicode: UCS4Char;
  SimKey: LongWord;
  mouseDown: boolean;
  mouseBtn:  integer;
  mouseX, mouseY: Single;
  EventX, EventY: integer;
  KeepGoing: boolean;
  SuppressKey: boolean;
  UpdateMouse: boolean;
begin
  KeepGoing := true;
  SuppressKey := false;
  while SDL_PollEvent(@Event) do
  begin
    case Event.type_ of
      SDL_EVENT_QUIT:
      begin
        Display.Fade := 0;
        Display.NextScreenWithCheck := nil;
        Display.CheckOK := true;
      end;

      SDL_EVENT_MOUSE_MOTION, SDL_EVENT_MOUSE_BUTTON_DOWN,
      SDL_EVENT_MOUSE_BUTTON_UP, SDL_EVENT_MOUSE_WHEEL:
      begin
        if (Ini.Mouse > 0) then
        begin
          UpdateMouse := true;
          case Event.type_ of
            SDL_EVENT_MOUSE_BUTTON_DOWN:
            begin
              mouseDown := true;
              mouseBtn  := Event.button.button;
              CheckMouseButton := true;
              if (mouseBtn = SDL_BUTTON_LEFT) or (mouseBtn = SDL_BUTTON_RIGHT) then
                Display.OnMouseButton(true);
              EventX := Round(Event.button.x);
              EventY := Round(Event.button.y);
            end;
            SDL_EVENT_MOUSE_BUTTON_UP:
            begin
              mouseDown := false;
              mouseBtn  := Event.button.button;
              CheckMouseButton := false;
              if (mouseBtn = SDL_BUTTON_LEFT) or (mouseBtn = SDL_BUTTON_RIGHT) then
                Display.OnMouseButton(false);
              EventX := Round(Event.button.x);
              EventY := Round(Event.button.y);
            end;
            SDL_EVENT_MOUSE_MOTION:
            begin
              if (CheckMouseButton) then
                mouseDown := true
              else
                mouseDown := false;
              mouseBtn  := 0;
              EventX := Round(Event.motion.x);
              EventY := Round(Event.motion.y);
            end;
            SDL_EVENT_MOUSE_WHEEL:
            begin
              UpdateMouse := false;
              mouseDown   := (Event.wheel.y <> 0);
              mouseBtn    := SDL_BUTTON_WHEELDOWN;
              if (Event.wheel.y > 0) then mouseBtn := SDL_BUTTON_WHEELUP;

              // some menu buttons require proper mouse location for trying to
              // react to mouse wheel navigation simulation (see UMenu.ParseMouse)
              EventX := Round(Event.wheel.mouse_x);
              EventY := Round(Event.wheel.mouse_y);
            end;
          end;

          if UpdateMouse then
          begin
            // used to update mouse coords and allow the relative mouse emulated by joystick axis motion
            if assigned(Joy) then Joy.OnMouseMove(EnsureRange(EventX, 0, 799),
                                                  EnsureRange(EventY, 0, 599));

            Display.MoveCursor(EventX * 800 * Screens div ScreenW,
                               EventY * 600 div ScreenH);
          end;

          if not Assigned(Display.NextScreen) then
          begin //drop input when changing screens
            if (ScreenPopupError <> nil) and (ScreenPopupError.Visible) then
              KeepGoing := ScreenPopupError.ParseMouse(mouseBtn, mouseDown, EventX, EventY)
            else if (ScreenPopupInfo <> nil) and (ScreenPopupInfo.Visible) then
              KeepGoing := ScreenPopupInfo.ParseMouse(mouseBtn, mouseDown, EventX, EventY)
            else if (ScreenPopupCheck <> nil) and (ScreenPopupCheck.Visible) then
              KeepGoing := ScreenPopupCheck.ParseMouse(mouseBtn, mouseDown, EventX, EventY)
            else if (ScreenPopupInsertUser <> nil) and (ScreenPopupInsertUser.Visible) then
              KeepGoing := ScreenPopupInsertUser.ParseMouse(mouseBtn, mouseDown, EventX, EventY)
            else if (ScreenPopupSendScore <> nil) and (ScreenPopupSendScore.Visible) then
              KeepGoing := ScreenPopupSendScore.ParseMouse(mouseBtn, mouseDown, EventX, EventY)
            else if (ScreenPopupScoreDownload <> nil) and (ScreenPopupScoreDownload.Visible) then
              KeepGoing := ScreenPopupScoreDownload.ParseMouse(mouseBtn, mouseDown, EventX, EventY)
            else if (ScreenPopupHelp <> nil) and (ScreenPopupHelp.Visible) then
              KeepGoing := ScreenPopupHelp.ParseMouse(mouseBtn, mouseDown, EventX, EventY)
            else
            begin
              KeepGoing := Display.ParseMouse(mouseBtn, mouseDown, EventX, EventY);

              // if screen wants to exit
              if not KeepGoing then
                DoQuit;
            end;
          end;
        end;
      end;
      SDL_EVENT_WINDOW_MOVED:
        OnWindowMoved(Event.window.data1, Event.window.data2);
      SDL_EVENT_WINDOW_RESIZED:
        OnWindowResized(Event.window.data1, Event.window.data2);
      SDL_EVENT_KEY_DOWN, SDL_EVENT_TEXT_INPUT:
        begin
          // translate CTRL-A (ASCII 1) - CTRL-Z (ASCII 26) to correct charcodes.
          // keysyms (SDLK_A, ...) could be used instead but they ignore the
          // current key mapping (if 'a' is pressed on a French keyboard the
          // .unicode field will be 'a' and .sym SDLK_Q).
          // IMPORTANT: if CTRL is pressed with a key different than 'A'-'Z' SDL
          // will set .unicode to 0. There is no possibility to obtain a
          // translated charcode. Use keysyms instead.
          //if (Event.key.keysym.unicode in [1 .. 26]) then
          //  Event.key.keysym.unicode := Ord('A') + Event.key.keysym.unicode - 1;

          if (Event.type_ = SDL_EVENT_KEY_DOWN) and (Event.key.key = SDLK_RETURN) then
          begin
            if (SDL_GetModState and (SDL_KMOD_LSHIFT + SDL_KMOD_RSHIFT + SDL_KMOD_LCTRL + SDL_KMOD_RCTRL + SDL_KMOD_LALT  + SDL_KMOD_RALT) = SDL_KMOD_LALT) then
            begin
              if SwitchVideoMode(Mode_Fullscreen) = Mode_Fullscreen then Ini.FullScreen := 1
              else Ini.FullScreen := 0;
              Ini.Save();

              Break;
            end;
          end;

          // remap the "keypad enter" key to the "standard enter" key
          if (Event.type_ = SDL_EVENT_KEY_DOWN) and (Event.key.key = SDLK_KP_ENTER) then
            Event.key.key := SDLK_RETURN;

          if not Assigned(Display.NextScreen) then
          begin //drop input when changing screens
            KeyCharUnicode:=0;
            if (Event.type_ = SDL_EVENT_TEXT_INPUT) and (Event.text.text <> nil) and (Event.text.text^ <> #0) then
            try
              KeyCharUnicode:=UnicodeStringToUCS4String(UnicodeString(UTF8String(Event.text.text)))[0];
              //KeyCharUnicode:=UnicodeStringToUCS4String(UnicodeString(Event.key.keysym.unicode))[1];//Event.text.text)[0];
            except
            end;

            SimKey :=0;
            if (Event.type_ = SDL_EVENT_KEY_DOWN) and
               (Event.key.key > Low(LongWord)) and (Event.key.key < High(LongWord)) then
            begin
              SimKey := Event.key.key;
            end;

            // if print is pressed -> make screenshot and save to screenshot path
            if (SimKey = SDLK_SYSREQ) or (SimKey = SDLK_PRINTSCREEN) then
              Display.SaveScreenShot
            // if there is a visible popup then let it handle input instead of underlying screen
            // shoud be done in a way to be sure the topmost popup has preference (maybe error, then check)
            else if (ScreenPopupError <> nil) and (ScreenPopupError.Visible) then
              KeepGoing := ScreenPopupError.ParseInput(SimKey, KeyCharUnicode, true)
            else if (ScreenPopupInfo <> nil) and (ScreenPopupInfo.Visible) then
              KeepGoing := ScreenPopupInfo.ParseInput(SimKey, KeyCharUnicode, true)
            else if (ScreenPopupCheck <> nil) and (ScreenPopupCheck.Visible) then
              KeepGoing := ScreenPopupCheck.ParseInput(SimKey, KeyCharUnicode, true)
            else if (ScreenPopupInsertUser <> nil) and (ScreenPopupInsertUser.Visible) then
              KeepGoing := ScreenPopupInsertUser.ParseInput(SimKey, KeyCharUnicode, true)
            else if (ScreenPopupSendScore <> nil) and (ScreenPopupSendScore.Visible) then
              KeepGoing := ScreenPopupSendScore.ParseInput(SimKey, KeyCharUnicode, true)
            else if (ScreenPopupScoreDownload <> nil) and (ScreenPopupScoreDownload.Visible) then
              KeepGoing := ScreenPopupScoreDownload.ParseInput(SimKey, KeyCharUnicode, true)
            else if (ScreenPopupHelp <> nil) and (ScreenPopupHelp.Visible) then
              KeepGoing := ScreenPopupHelp.ParseInput(SimKey, KeyCharUnicode, true)
            else if (Display.ShouldHandleInput(LongWord(SimKey), KeyCharUnicode, true, SuppressKey)) then
            begin
              // check if screen wants to exit
              KeepGoing := Display.ParseInput(SimKey, KeyCharUnicode, true);

              // if screen wants to exit
              if not KeepGoing then
                DoQuit;

            end;

            if (not SuppressKey and (Event.type_ = SDL_EVENT_KEY_DOWN) and
                (Event.key.key = SDLK_F11)) then // toggle full screen
            begin
              if (CurrentWindowMode <> Mode_Fullscreen) then // only switch borderless fullscreen in windowed mode
              begin
                if SwitchVideoMode(Mode_Borderless) = Mode_Borderless then
                begin
                  Ini.FullScreen := 2;
                end
                else
                begin
                  Ini.FullScreen := 0;
                end;
                Ini.Save();
              end;

              //Display.SetCursor;

              //glViewPort(0, 0, ScreenW, ScreenH);
            end;
          end;
        end;
      SDL_EVENT_GAMEPAD_ADDED, SDL_EVENT_GAMEPAD_REMOVED, SDL_EVENT_GAMEPAD_REMAPPED,
      SDL_EVENT_GAMEPAD_BUTTON_DOWN, SDL_EVENT_GAMEPAD_BUTTON_UP, SDL_EVENT_GAMEPAD_AXIS_MOTION,
      SDL_EVENT_JOYSTICK_AXIS_MOTION, SDL_EVENT_JOYSTICK_BALL_MOTION,
      SDL_EVENT_JOYSTICK_BUTTON_DOWN, SDL_EVENT_JOYSTICK_BUTTON_UP,
      SDL_EVENT_JOYSTICK_ADDED, SDL_EVENT_JOYSTICK_REMOVED, SDL_EVENT_JOYSTICK_HAT_MOTION:
        begin
          OnJoystickPollEvent(Event);
        end;
      MAINTHREAD_EXEC_EVENT:
        with Event.user do
        begin
          TMainThreadExecProc(data1)(data2);
        end;

      otherwise
      begin
        ;
      end;
    end; // case
  end; // while

  if Display.NeedsCursorUpdate() then
  begin


    // push a generated event onto the queue in order to simulate a mouse movement
    // the next tick will poll the motion event and handle it just like a real input
    FillChar(SimEvent, SizeOf(SimEvent), 0);
    SDL_GetMouseState(@mouseX, @mouseY);
    SimEvent.motion.type_ := SDL_EVENT_MOUSE_MOTION;
    SimEvent.motion.x := mouseX;
    SimEvent.motion.y := mouseY;
    SDL_PushEvent(@SimEvent);
  end;
end;

procedure MainThreadExec(Proc: TMainThreadExecProc; Data: Pointer);
var
  Event: TSDL_Event;
begin
  with Event.user do
  begin
    type_ := MAINTHREAD_EXEC_EVENT;
    code  := 0;     // not used at the moment
    data1 := @Proc;
    data2 := Data;
  end;
  SDL_PushEvent(@Event);
end;

end.
