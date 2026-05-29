{* UltraStar Deluxe - libmpv video backend *}

unit UVideo_MPV;

{$IFDEF FPC}
  {$MODE Delphi}
{$ENDIF}

interface

{$I switches.inc}

implementation

uses
  SysUtils,
  Math,
  ctypes,
  dglOpenGL,
  mpv,
  UCommon,
  UConfig,
  ULog,
  UMusic,
  UGraphicClasses,
  UGraphic,
  UPath;

const
  ReflectionH = 0.5;
  MPV_SYNC_INTERVAL = 0.5;
  MPV_SYNC_THRESHOLD = 0.050;
  MPV_EXTERNAL_SEEK_THRESHOLD = 1.0;

type
  IVideo_MPV = interface (IVideo)
  ['{66C54DBD-5D4A-4A8D-A4AE-9306718A51B5}']
    function Open(const FileName: IPath): boolean;
  end;

  TVideo_MPV = class(TInterfacedObject, IVideo_MPV)
  private
    fOpened: boolean;
    fPaused: boolean;
    fEOF: boolean;
    fLoop: boolean;

    fHandle: Pmpv_handle;
    fRenderContext: Pmpv_render_context;
    fNeedsRender: boolean;

    fFrameTex: GLuint;
    fFrameFbo: GLuint;
    fFrameTexValid: boolean;
    fTexWidth, fTexHeight: cardinal;
    fScaledWidth, fScaledHeight: cardinal;

    fScreen: integer;
    fPosX: double;
    fPosY: double;
    fPosZ: double;
    fWidth: double;
    fHeight: double;
    fFrameRange: TRectCoords;
    fAlpha: double;
    fReflectionSpacing: double;
    fAspect: real;
    fAspectCorrection: TAspectCorrection;

    fPosition: extended;
    fLoopTime: extended;
    fLastRequestedTime: extended;
    fLastSyncCheck: TDateTime;

    procedure Reset();
    function CreateMpvHandle(): boolean;
    function CreateRenderContext(): boolean;
    function Command(const Args: array of AnsiString): boolean;
    function SetOptionString(const Name, Value: AnsiString; Required: boolean = true): boolean;
    function SetPropertyFlag(const Name: AnsiString; Value: boolean): boolean;
    function SetPropertyDouble(const Name: AnsiString; Value: double): boolean;
    function SetPropertyString(const Name, Value: AnsiString): boolean;
    function GetPropertyInt64(const Name: AnsiString; out Value: Int64): boolean;
    function GetPropertyDouble(const Name: AnsiString; out Value: double): boolean;
    function WaitForFileLoaded(TimeoutSeconds: double): boolean;
    procedure DrainEvents();
    function LoadFile(const FileName: IPath): boolean;
    function UpdateVideoProperties(): boolean;
    function EnsureRenderTarget(): boolean;
    procedure ReleaseRenderTarget();
    function RenderToTexture(): boolean;
    procedure SyncToExternalTime(Time: extended);

    procedure GetVideoRect(var ScreenRect, TexRect: TRectCoords);
    procedure DrawBorders(ScreenRect: TRectCoords);
    procedure DrawBordersReflected(ScreenRect: TRectCoords; AlphaUpper, AlphaLower: double);

  public
    constructor Create;
    destructor Destroy; override;

    function Open(const FileName: IPath): boolean;
    procedure Close;

    procedure Play;
    procedure Pause;
    procedure Stop;

    procedure SetLoop(Enable: boolean);
    function GetLoop(): boolean;

    procedure SetPosition(Time: real);
    function GetPosition: real;

    procedure SetScreen(Screen: integer);
    function GetScreen(): integer;

    procedure SetScreenPosition(X, Y, Z: double);
    procedure GetScreenPosition(var X, Y, Z: double);

    procedure SetWidth(Width: double);
    function GetWidth(): double;

    procedure SetHeight(Height: double);
    function GetHeight(): double;

    procedure SetFrameRange(Range: TRectCoords);
    function GetFrameRange(): TRectCoords;

    function GetFrameAspect(): real;

    procedure SetAspectCorrection(AspectCorrection: TAspectCorrection);
    function GetAspectCorrection(): TAspectCorrection;

    procedure SetAlpha(Alpha: double);
    function GetAlpha(): double;

    procedure SetReflectionSpacing(Spacing: double);
    function GetReflectionSpacing(): double;

    procedure GetFrame(Time: Extended);
    procedure Draw();
    procedure DrawReflection();
  end;

  TVideoPlayback_MPV = class(TInterfacedObject, IVideoPlayback)
  private
    fInitialized: boolean;
  public
    function GetName: String;
    function Init(): boolean;
    function Finalize: boolean;
    function Open(const FileName : IPath): IVideo;
  end;

function MpvProcAddress(ctx: Pointer; name: PAnsiChar): Pointer; cdecl;
begin
  Result := dglGetProcAddress(name);
end;

procedure MpvRenderUpdateCallback(cb_ctx: Pointer); cdecl;
begin
  if cb_ctx <> nil then
    TVideo_MPV(cb_ctx).fNeedsRender := true;
end;

function MpvError(ErrorNumber: cint): string;
begin
  if Assigned(mpv_error_string) then
    Result := StrPas(mpv_error_string(ErrorNumber))
  else
    Result := IntToStr(ErrorNumber);
end;

{ TVideoPlayback_MPV }

function TVideoPlayback_MPV.GetName: String;
begin
  Result := 'MPV_Video';
end;

function TVideoPlayback_MPV.Init(): boolean;
begin
  fInitialized := LoadMpv();
  if not fInitialized then
    Log.LogWarn('libmpv not loaded; MPV video backend disabled: ' + MpvLoadError(), 'TVideoPlayback_MPV.Init')
  else
    Log.LogInfo('Using libmpv client API ' + IntToStr(mpv_client_api_version()), 'TVideoPlayback_MPV.Init');
  Result := fInitialized;
end;

function TVideoPlayback_MPV.Finalize: boolean;
begin
  fInitialized := false;
  UnloadMpv();
  Result := true;
end;

function TVideoPlayback_MPV.Open(const FileName : IPath): IVideo;
var
  Video: IVideo_MPV;
begin
  Result := nil;
  Video := TVideo_MPV.Create;
  if Video.Open(FileName) then
    Result := Video;
end;

{ TVideo_MPV }

constructor TVideo_MPV.Create;
begin
  inherited;
  Reset();
end;

destructor TVideo_MPV.Destroy;
begin
  Close();
  inherited;
end;

procedure TVideo_MPV.Reset();
begin
  Close();

  fOpened := false;
  fPaused := true;
  fEOF := false;
  fLoop := false;
  fNeedsRender := false;
  fFrameTexValid := false;

  fScreen := 1;
  fPosX := 0;
  fPosY := 0;
  fPosZ := 0;
  fWidth := RenderW;
  fHeight := RenderH;

  fFrameRange.Left := 0;
  fFrameRange.Right := 1;
  fFrameRange.Upper := 0;
  fFrameRange.Lower := 1;

  fAlpha := 1;
  fReflectionSpacing := 0;
  fAspect := 4/3;
  fAspectCorrection := acoLetterBox;

  fPosition := 0;
  fLoopTime := 0;
  fLastRequestedTime := -1;
  fLastSyncCheck := 0;
end;

function TVideo_MPV.SetOptionString(const Name, Value: AnsiString; Required: boolean): boolean;
var
  ErrorNumber: cint;
begin
  ErrorNumber := mpv_set_option_string(fHandle, PAnsiChar(Name), PAnsiChar(Value));
  Result := ErrorNumber >= 0;
  if (not Result) and Required then
    Log.LogError('Failed to set mpv option ' + string(Name) + ': ' + MpvError(ErrorNumber), 'TVideo_MPV.Open');
end;

function TVideo_MPV.SetPropertyFlag(const Name: AnsiString; Value: boolean): boolean;
var
  Flag: cint;
  ErrorNumber: cint;
begin
  Flag := Ord(Value);
  ErrorNumber := mpv_set_property(fHandle, PAnsiChar(Name), MPV_FORMAT_FLAG, @Flag);
  Result := ErrorNumber >= 0;
end;

function TVideo_MPV.SetPropertyDouble(const Name: AnsiString; Value: double): boolean;
var
  DoubleValue: cdouble;
  ErrorNumber: cint;
begin
  DoubleValue := Value;
  ErrorNumber := mpv_set_property(fHandle, PAnsiChar(Name), MPV_FORMAT_DOUBLE, @DoubleValue);
  Result := ErrorNumber >= 0;
end;

function TVideo_MPV.SetPropertyString(const Name, Value: AnsiString): boolean;
var
  ErrorNumber: cint;
begin
  ErrorNumber := mpv_set_property_string(fHandle, PAnsiChar(Name), PAnsiChar(Value));
  Result := ErrorNumber >= 0;
end;

function TVideo_MPV.GetPropertyInt64(const Name: AnsiString; out Value: Int64): boolean;
var
  ErrorNumber: cint;
begin
  ErrorNumber := mpv_get_property(fHandle, PAnsiChar(Name), MPV_FORMAT_INT64, @Value);
  Result := ErrorNumber >= 0;
end;

function TVideo_MPV.GetPropertyDouble(const Name: AnsiString; out Value: double): boolean;
var
  DoubleValue: cdouble;
  ErrorNumber: cint;
begin
  ErrorNumber := mpv_get_property(fHandle, PAnsiChar(Name), MPV_FORMAT_DOUBLE, @DoubleValue);
  Result := ErrorNumber >= 0;
  if Result then
    Value := DoubleValue;
end;

function TVideo_MPV.Command(const Args: array of AnsiString): boolean;
var
  ArgPointers: array of PAnsiChar;
  I: integer;
  ErrorNumber: cint;
begin
  SetLength(ArgPointers, Length(Args) + 1);
  for I := 0 to High(Args) do
    ArgPointers[I] := PAnsiChar(Args[I]);
  ArgPointers[High(ArgPointers)] := nil;

  ErrorNumber := mpv_command(fHandle, @ArgPointers[0]);
  Result := ErrorNumber >= 0;
  if not Result then
    Log.LogError('mpv command failed: ' + MpvError(ErrorNumber), 'TVideo_MPV');
end;

function TVideo_MPV.CreateMpvHandle(): boolean;
var
  ErrorNumber: cint;
begin
  Result := false;
  fHandle := mpv_create();
  if fHandle = nil then
  begin
    Log.LogError('Failed to create mpv handle', 'TVideo_MPV.Open');
    Exit;
  end;

  if not SetOptionString('vo', 'libmpv') then
    Exit;
  if not SetOptionString('audio', 'no') then
    Exit;
  if not SetOptionString('config', 'no') then
    Exit;
  if not SetOptionString('terminal', 'no') then
    Exit;
  if not SetOptionString('pause', 'yes') then
    Exit;

  SetOptionString('osc', 'no', false);
  SetOptionString('osd-level', '0', false);
  SetOptionString('input-default-bindings', 'no', false);
  SetOptionString('input-vo-keyboard', 'no', false);
  SetOptionString('load-scripts', 'no', false);
  SetOptionString('keep-open', 'yes', false);
  SetOptionString('hwdec', 'auto', false);

  ErrorNumber := mpv_initialize(fHandle);
  if ErrorNumber < 0 then
  begin
    Log.LogError('Failed to initialize mpv: ' + MpvError(ErrorNumber), 'TVideo_MPV.Open');
    Exit;
  end;

  Result := CreateRenderContext();
end;

function TVideo_MPV.CreateRenderContext(): boolean;
var
  ApiType: AnsiString;
  InitParams: Tmpv_opengl_init_params;
  AdvancedControl: cint;
  Params: array[0..3] of Tmpv_render_param;
  ErrorNumber: cint;
begin
  Result := false;
  if not Assigned(glBindFramebuffer) or
     not Assigned(glGenFramebuffers) or
     not Assigned(glFramebufferTexture2D) or
     not Assigned(glCheckFramebufferStatus) then
  begin
    Log.LogError('OpenGL framebuffer support is required for libmpv video', 'TVideo_MPV.Open');
    Exit;
  end;

  ApiType := 'opengl';
  InitParams.get_proc_address := MpvProcAddress;
  InitParams.get_proc_address_ctx := nil;
  AdvancedControl := 1;

  Params[0].ParamType := MPV_RENDER_PARAM_API_TYPE;
  Params[0].data := PAnsiChar(ApiType);
  Params[1].ParamType := MPV_RENDER_PARAM_OPENGL_INIT_PARAMS;
  Params[1].data := @InitParams;
  Params[2].ParamType := MPV_RENDER_PARAM_ADVANCED_CONTROL;
  Params[2].data := @AdvancedControl;
  Params[3].ParamType := MPV_RENDER_PARAM_INVALID;
  Params[3].data := nil;

  ErrorNumber := mpv_render_context_create(fRenderContext, fHandle, @Params[0]);
  if ErrorNumber < 0 then
  begin
    Log.LogError('Failed to create mpv OpenGL renderer: ' + MpvError(ErrorNumber), 'TVideo_MPV.Open');
    Exit;
  end;

  mpv_render_context_set_update_callback(fRenderContext, MpvRenderUpdateCallback, Self);
  Result := true;
end;

function TVideo_MPV.WaitForFileLoaded(TimeoutSeconds: double): boolean;
var
  Event: Pmpv_event;
  Deadline: TDateTime;
begin
  Result := false;
  Deadline := Now + TimeoutSeconds / 86400.0;
  repeat
    Event := mpv_wait_event(fHandle, 0.05);
    if Event = nil then
      Continue;

    case Event^.event_id of
      MPV_EVENT_FILE_LOADED:
        Exit(true);
      MPV_EVENT_END_FILE:
        Exit(false);
      MPV_EVENT_SHUTDOWN:
        Exit(false);
    end;
  until Now >= Deadline;
end;

procedure TVideo_MPV.DrainEvents();
var
  Event: Pmpv_event;
begin
  if fHandle = nil then
    Exit;

  repeat
    Event := mpv_wait_event(fHandle, 0);
    if Event = nil then
      Exit;

    case Event^.event_id of
      MPV_EVENT_END_FILE:
        fEOF := true;
      MPV_EVENT_SHUTDOWN:
        fOpened := false;
    end;
  until Event^.event_id = MPV_EVENT_NONE;
end;

function TVideo_MPV.LoadFile(const FileName: IPath): boolean;
var
  FileNameUTF8: AnsiString;
begin
  FileNameUTF8 := FileName.ToUTF8();
  Result := Command(['loadfile', FileNameUTF8, 'replace']) and WaitForFileLoaded(5.0);
  if not Result then
    Log.LogError('Failed to load video with libmpv: "' + FileName.ToNative + '"', 'TVideo_MPV.Open');
end;

function TVideo_MPV.UpdateVideoProperties(): boolean;
var
  DisplayWidth, DisplayHeight: Int64;
  StorageWidth, StorageHeight: Int64;
  Aspect: double;
begin
  Result := false;
  DisplayWidth := 0;
  DisplayHeight := 0;
  StorageWidth := 0;
  StorageHeight := 0;

  GetPropertyInt64('dwidth', DisplayWidth);
  GetPropertyInt64('dheight', DisplayHeight);
  GetPropertyInt64('width', StorageWidth);
  GetPropertyInt64('height', StorageHeight);

  if (DisplayWidth <= 0) or (DisplayHeight <= 0) then
  begin
    DisplayWidth := StorageWidth;
    DisplayHeight := StorageHeight;
  end;

  if (DisplayWidth <= 0) or (DisplayHeight <= 0) then
  begin
    Log.LogError('libmpv did not report usable video dimensions', 'TVideo_MPV.Open');
    Exit;
  end;

  fTexWidth := DisplayWidth;
  fTexHeight := DisplayHeight;
  fScaledWidth := fTexWidth;
  fScaledHeight := fTexHeight;

  if GetPropertyDouble('video-params/aspect', Aspect) and (Aspect > 0) then
    fAspect := Aspect
  else
    fAspect := fTexWidth / fTexHeight;

  Result := true;
end;

procedure TVideo_MPV.ReleaseRenderTarget();
begin
  if fFrameFbo <> 0 then
  begin
    glDeleteFramebuffers(1, @fFrameFbo);
    fFrameFbo := 0;
  end;

  if fFrameTex <> 0 then
  begin
    glDeleteTextures(1, @fFrameTex);
    fFrameTex := 0;
  end;

  fFrameTexValid := false;
end;

function TVideo_MPV.EnsureRenderTarget(): boolean;
var
  OldTexture: GLint;
  OldFbo: GLint;
  Status: GLenum;
begin
  Result := false;
  if (fFrameTex <> 0) and (fFrameFbo <> 0) then
    Exit(true);

  if (fTexWidth = 0) or (fTexHeight = 0) then
    Exit;

  glGetIntegerv(GL_TEXTURE_BINDING_2D, @OldTexture);
  glGetIntegerv(GL_FRAMEBUFFER_BINDING, @OldFbo);

  glGenTextures(1, @fFrameTex);
  glBindTexture(GL_TEXTURE_2D, fFrameTex);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, fTexWidth, fTexHeight, 0, GL_RGBA, GL_UNSIGNED_BYTE, nil);

  glGenFramebuffers(1, @fFrameFbo);
  glBindFramebuffer(GL_FRAMEBUFFER, fFrameFbo);
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, fFrameTex, 0);

  Status := glCheckFramebufferStatus(GL_FRAMEBUFFER);
  glBindFramebuffer(GL_FRAMEBUFFER, OldFbo);
  glBindTexture(GL_TEXTURE_2D, OldTexture);

  if Status <> GL_FRAMEBUFFER_COMPLETE then
  begin
    Log.LogError('Failed to create libmpv video framebuffer: $' + IntToHex(Status, 4), 'TVideo_MPV.Open');
    ReleaseRenderTarget();
    Exit;
  end;

  Result := true;
end;

function TVideo_MPV.RenderToTexture(): boolean;
var
  OldFbo: GLint;
  OldViewport: array[0..3] of GLint;
  Fbo: Tmpv_opengl_fbo;
  FlipY: cint;
  Params: array[0..2] of Tmpv_render_param;
  UpdateFlags: QWord;
  ErrorNumber: cint;
begin
  Result := false;
  if (fRenderContext = nil) or not EnsureRenderTarget() then
    Exit;

  UpdateFlags := mpv_render_context_update(fRenderContext);
  if ((UpdateFlags and MPV_RENDER_UPDATE_FRAME) = 0) and
     (not fNeedsRender) and fFrameTexValid then
    Exit(true);

  fNeedsRender := false;

  glGetIntegerv(GL_FRAMEBUFFER_BINDING, @OldFbo);
  glGetIntegerv(GL_VIEWPORT, @OldViewport[0]);

  glBindFramebuffer(GL_FRAMEBUFFER, fFrameFbo);
  glViewport(0, 0, fTexWidth, fTexHeight);

  Fbo.fbo := fFrameFbo;
  Fbo.w := fTexWidth;
  Fbo.h := fTexHeight;
  Fbo.internal_format := GL_RGBA8;
  FlipY := 0;

  Params[0].ParamType := MPV_RENDER_PARAM_OPENGL_FBO;
  Params[0].data := @Fbo;
  Params[1].ParamType := MPV_RENDER_PARAM_FLIP_Y;
  Params[1].data := @FlipY;
  Params[2].ParamType := MPV_RENDER_PARAM_INVALID;
  Params[2].data := nil;

  ErrorNumber := mpv_render_context_render(fRenderContext, @Params[0]);
  mpv_render_context_report_swap(fRenderContext);

  glBindFramebuffer(GL_FRAMEBUFFER, OldFbo);
  glViewport(OldViewport[0], OldViewport[1], OldViewport[2], OldViewport[3]);

  if ErrorNumber < 0 then
  begin
    Log.LogError('libmpv render failed: ' + MpvError(ErrorNumber), 'TVideo_MPV.GetFrame');
    Exit;
  end;

  fFrameTexValid := true;
  Result := true;
end;

procedure TVideo_MPV.SyncToExternalTime(Time: extended);
var
  MpvTime: double;
begin
  if Time < 0 then
    Time := 0;

  if (fLastRequestedTime >= 0) and
     (Abs(Time - fLastRequestedTime) > MPV_EXTERNAL_SEEK_THRESHOLD) then
  begin
    SetPosition(Time);
    Exit;
  end;

  fPosition := Time;
  fLastRequestedTime := Time;

  if (fLastSyncCheck <> 0) and ((Now - fLastSyncCheck) * 86400.0 < MPV_SYNC_INTERVAL) then
    Exit;

  fLastSyncCheck := Now;
  if GetPropertyDouble('time-pos', MpvTime) and (Abs(MpvTime - Time) > MPV_SYNC_THRESHOLD) then
    SetPosition(Time);
end;

function TVideo_MPV.Open(const FileName: IPath): boolean;
begin
  Result := false;
  Reset();

  if not CreateMpvHandle() then
  begin
    Close();
    Exit;
  end;

  if not LoadFile(FileName) or not UpdateVideoProperties() or not EnsureRenderTarget() then
  begin
    Close();
    Exit;
  end;

  fOpened := true;
  fPaused := true;
  fEOF := false;
  SetPropertyFlag('pause', true);
  Log.LogInfo('Using libmpv video backend for "' + FileName.ToNative + '"', 'TVideo_MPV.Open');
  Result := true;
end;

procedure TVideo_MPV.Close;
begin
  ReleaseRenderTarget();

  if fRenderContext <> nil then
  begin
    mpv_render_context_set_update_callback(fRenderContext, nil, nil);
    mpv_render_context_free(fRenderContext);
    fRenderContext := nil;
  end;

  if fHandle <> nil then
  begin
    mpv_terminate_destroy(fHandle);
    fHandle := nil;
  end;

  fOpened := false;
end;

procedure TVideo_MPV.GetFrame(Time: Extended);
var
  CurrentTime: extended;
begin
  if not fOpened then
    Exit;

  DrainEvents();
  if fPaused then
    Exit;

  if fLoop then
    CurrentTime := Time - fLoopTime
  else
    CurrentTime := Time;

  SyncToExternalTime(CurrentTime);
  RenderToTexture();
end;

procedure TVideo_MPV.GetVideoRect(var ScreenRect, TexRect: TRectCoords);
var
  ScreenAspect: double;
  ScaledVideoWidth, ScaledVideoHeight: double;
begin
  ScreenAspect := fWidth*((ScreenW/Screens)/RenderW)/(fHeight*(ScreenH/RenderH));

  case fAspectCorrection of
    acoCrop: begin
      if ScreenAspect >= fAspect then
      begin
        ScaledVideoWidth  := fWidth;
        ScaledVideoHeight := fHeight * ScreenAspect/fAspect;
      end
      else
      begin
        ScaledVideoHeight := fHeight;
        ScaledVideoWidth  := fWidth * fAspect/ScreenAspect;
      end;
    end;

    acoHalfway: begin
      ScaledVideoWidth  := (fWidth + fWidth * fAspect/ScreenAspect)/2;
      ScaledVideoHeight := (fHeight + fHeight * ScreenAspect/fAspect)/2;
    end;

    acoLetterBox: begin
      if ScreenAspect <= fAspect then
      begin
        ScaledVideoWidth  := fWidth;
        ScaledVideoHeight := fHeight * ScreenAspect/fAspect;
      end
      else
      begin
        ScaledVideoHeight := fHeight;
        ScaledVideoWidth  := fWidth * fAspect/ScreenAspect;
      end;
    end
    else
      raise Exception.Create('Unhandled aspect correction!');
  end;

  ScreenRect.Left  := (fWidth - ScaledVideoWidth) / 2 + fPosX;
  ScreenRect.Right := ScreenRect.Left + ScaledVideoWidth;
  ScreenRect.Upper := (fHeight - ScaledVideoHeight) / 2 + fPosY;
  ScreenRect.Lower := ScreenRect.Upper + ScaledVideoHeight;

  TexRect.Left  := fFrameRange.Left;
  TexRect.Right := fFrameRange.Right;
  TexRect.Upper := fFrameRange.Upper;
  TexRect.Lower := fFrameRange.Lower;
end;

procedure TVideo_MPV.DrawBorders(ScreenRect: TRectCoords);
  procedure DrawRect(left, right, upper, lower: double);
  begin
    glColor4f(0, 0, 0, fAlpha);
    glBegin(GL_QUADS);
      glVertex3f(left, upper, fPosZ);
      glVertex3f(right, upper, fPosZ);
      glVertex3f(right, lower, fPosZ);
      glVertex3f(left, lower, fPosZ);
    glEnd;
  end;
begin
  if ScreenRect.Upper > fPosY then
    DrawRect(fPosX, fPosX+fWidth, fPosY, ScreenRect.Upper);

  if ScreenRect.Lower < fPosY+fHeight then
    DrawRect(fPosX, fPosX+fWidth, ScreenRect.Lower, fPosY+fHeight);

  if ScreenRect.Left > fPosX then
    DrawRect(fPosX, ScreenRect.Left, fPosY, fPosY+fHeight);

  if ScreenRect.Right < fPosX+fWidth then
    DrawRect(ScreenRect.Right, fPosX+fWidth, fPosY, fPosY+fHeight);
end;

procedure TVideo_MPV.DrawBordersReflected(ScreenRect: TRectCoords; AlphaUpper, AlphaLower: double);
var
  rPosUpper, rPosLower: double;

  procedure DrawRect(left, right, upper, lower: double);
  var
    AlphaTop: double;
    AlphaBottom: double;
  begin
    AlphaTop := AlphaUpper+(AlphaLower-AlphaUpper)*(upper-rPosUpper)/(fHeight*ReflectionH);
    AlphaBottom := AlphaLower+(AlphaUpper-AlphaLower)*(rPosLower-lower)/(fHeight*ReflectionH);

    glBegin(GL_QUADS);
      glColor4f(0, 0, 0, AlphaTop);
      glVertex3f(left, upper, fPosZ);
      glVertex3f(right, upper, fPosZ);

      glColor4f(0, 0, 0, AlphaBottom);
      glVertex3f(right, lower, fPosZ);
      glVertex3f(left, lower, fPosZ);
    glEnd;
  end;
begin
  rPosUpper := fPosY+fHeight+fReflectionSpacing;
  rPosLower := rPosUpper+fHeight*ReflectionH;

  if ScreenRect.Upper > rPosUpper then
    DrawRect(fPosX, fPosX+fWidth, rPosUpper, ScreenRect.Upper);

  if ScreenRect.Lower < rPosLower then
    DrawRect(fPosX, fPosX+fWidth, ScreenRect.Lower, rPosLower);

  if ScreenRect.Left > fPosX then
    DrawRect(fPosX, ScreenRect.Left, rPosUpper, rPosLower);

  if ScreenRect.Right < fPosX+fWidth then
    DrawRect(ScreenRect.Right, fPosX+fWidth, rPosUpper, rPosLower);
end;

procedure TVideo_MPV.Draw();
var
  ScreenRect: TRectCoords;
  TexRect: TRectCoords;
  HeightFactor: double;
  WidthFactor: double;
begin
  if (not fOpened) or (not fFrameTexValid) then
    Exit;

  GetVideoRect(ScreenRect, TexRect);

  WidthFactor := (ScreenW/Screens) / RenderW;
  HeightFactor := ScreenH / RenderH;

  glScissor(
    round(fPosX*WidthFactor + (ScreenW/Screens)*(fScreen-1)),
    round((RenderH-fPosY-fHeight)*HeightFactor),
    round(fWidth*WidthFactor),
    round(fHeight*HeightFactor)
  );

  glEnable(GL_SCISSOR_TEST);
  glEnable(GL_BLEND);
  glDepthRange(0, 10);
  glDepthFunc(GL_LEQUAL);
  glEnable(GL_DEPTH_TEST);

  glEnable(GL_TEXTURE_2D);
  glBindTexture(GL_TEXTURE_2D, fFrameTex);
  glColor4f(1, 1, 1, fAlpha);
  glBegin(GL_QUADS);
    glTexCoord2f(TexRect.Left, TexRect.Upper);
    glVertex3f(ScreenRect.Left, ScreenRect.Upper, fPosZ);
    glTexCoord2f(TexRect.Left, TexRect.Lower);
    glVertex3f(ScreenRect.Left, ScreenRect.Lower, fPosZ);
    glTexCoord2f(TexRect.Right, TexRect.Lower);
    glVertex3f(ScreenRect.Right, ScreenRect.Lower, fPosZ);
    glTexCoord2f(TexRect.Right, TexRect.Upper);
    glVertex3f(ScreenRect.Right, ScreenRect.Upper, fPosZ);
  glEnd;

  glDisable(GL_TEXTURE_2D);
  glBindTexture(GL_TEXTURE_2D, 0);

  DrawBorders(ScreenRect);

  glDisable(GL_DEPTH_TEST);
  glDisable(GL_BLEND);
  glDisable(GL_SCISSOR_TEST);
end;

procedure TVideo_MPV.DrawReflection();
var
  ScreenRect: TRectCoords;
  TexRect: TRectCoords;
  HeightFactor: double;
  WidthFactor: double;
  AlphaTop: double;
  AlphaBottom: double;
  AlphaUpper: double;
  AlphaLower: double;
begin
  if (not fOpened) or (not fFrameTexValid) then
    Exit;

  GetVideoRect(ScreenRect, TexRect);

  WidthFactor := (ScreenW/Screens) / RenderW;
  HeightFactor := ScreenH / RenderH;

  glScissor(
    round(fPosX*WidthFactor + (ScreenW/Screens)*(fScreen-1)),
    round((RenderH-fPosY-fHeight-fReflectionSpacing-fHeight*ReflectionH)*HeightFactor),
    round(fWidth*WidthFactor),
    round(fHeight*HeightFactor*ReflectionH)
  );

  glEnable(GL_SCISSOR_TEST);
  glEnable(GL_BLEND);
  glDepthRange(0, 10);
  glDepthFunc(GL_LEQUAL);
  glEnable(GL_DEPTH_TEST);

  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
  glEnable(GL_TEXTURE_2D);
  glBindTexture(GL_TEXTURE_2D, fFrameTex);

  ScreenRect.Lower := fPosY + fHeight + fReflectionSpacing
    + (ScreenRect.Upper-fPosY) + (ScreenRect.Lower-ScreenRect.Upper)*ReflectionH;
  ScreenRect.Upper := fPosY + fHeight + fReflectionSpacing
    + (ScreenRect.Upper-fPosY);

  AlphaUpper := fAlpha-0.3;
  AlphaLower := 0;

  AlphaTop := AlphaUpper-(AlphaLower-AlphaUpper)*
    (ScreenRect.Upper-fPosY-fHeight-fReflectionSpacing)/fHeight;
  AlphaBottom := AlphaLower+(AlphaUpper-AlphaLower)*
    (fPosY+fHeight+fReflectionSpacing+fHeight*ReflectionH-ScreenRect.Lower)/fHeight;

  glBegin(GL_QUADS);
    glColor4f(1, 1, 1, AlphaTop);
    glTexCoord2f(TexRect.Left, TexRect.Lower);
    glVertex3f(ScreenRect.Left, ScreenRect.Upper, fPosZ);

    glColor4f(1, 1, 1, AlphaBottom);
    glTexCoord2f(TexRect.Left, (TexRect.Lower-TexRect.Upper)*(1-ReflectionH));
    glVertex3f(ScreenRect.Left, ScreenRect.Lower, fPosZ);

    glColor4f(1, 1, 1, AlphaBottom);
    glTexCoord2f(TexRect.Right, (TexRect.Lower-TexRect.Upper)*(1-ReflectionH));
    glVertex3f(ScreenRect.Right, ScreenRect.Lower, fPosZ);

    glColor4f(1, 1, 1, AlphaTop);
    glTexCoord2f(TexRect.Right, TexRect.Lower);
    glVertex3f(ScreenRect.Right, ScreenRect.Upper, fPosZ);
  glEnd;

  glDisable(GL_TEXTURE_2D);
  glBindTexture(GL_TEXTURE_2D, 0);

  DrawBordersReflected(ScreenRect, AlphaUpper, AlphaLower);

  glDisable(GL_DEPTH_TEST);
  glDisable(GL_BLEND);
  glDisable(GL_SCISSOR_TEST);
end;

procedure TVideo_MPV.Play;
begin
  fPaused := false;
  if fHandle <> nil then
    SetPropertyFlag('pause', false);
end;

procedure TVideo_MPV.Pause;
begin
  fPaused := not fPaused;
  if fHandle <> nil then
    SetPropertyFlag('pause', fPaused);
end;

procedure TVideo_MPV.Stop;
begin
  fPaused := true;
  if fHandle <> nil then
    SetPropertyFlag('pause', true);
end;

procedure TVideo_MPV.SetLoop(Enable: boolean);
begin
  fLoop := Enable;
  fLoopTime := 0;
  if fHandle <> nil then
  begin
    if Enable then
      SetPropertyString('loop-file', 'inf')
    else
      SetPropertyString('loop-file', 'no');
  end;
end;

function TVideo_MPV.GetLoop(): boolean;
begin
  Result := fLoop;
end;

procedure TVideo_MPV.SetPosition(Time: real);
begin
  if not fOpened then
  begin
    fPosition := Time;
    Exit;
  end;

  if Time < 0 then
    Time := 0;

  fPosition := Time;
  fLastRequestedTime := Time;
  fLastSyncCheck := Now;
  fFrameTexValid := false;
  fEOF := false;

  if not SetPropertyDouble('time-pos', Time) then
    Log.LogError('Failed to seek libmpv video', 'TVideo_MPV.SetPosition');
end;

function TVideo_MPV.GetPosition: real;
begin
  Result := fPosition;
end;

procedure TVideo_MPV.SetScreen(Screen: integer);
begin
  fScreen := Screen;
end;

function TVideo_MPV.GetScreen(): integer;
begin
  Result := fScreen;
end;

procedure TVideo_MPV.SetScreenPosition(X, Y, Z: double);
begin
  fPosX := X;
  fPosY := Y;
  fPosZ := Z;
end;

procedure TVideo_MPV.GetScreenPosition(var X, Y, Z: double);
begin
  X := fPosX;
  Y := fPosY;
  Z := fPosZ;
end;

procedure TVideo_MPV.SetWidth(Width: double);
begin
  fWidth := Width;
end;

function TVideo_MPV.GetWidth(): double;
begin
  Result := fWidth;
end;

procedure TVideo_MPV.SetHeight(Height: double);
begin
  fHeight := Height;
end;

function TVideo_MPV.GetHeight(): double;
begin
  Result := fHeight;
end;

procedure TVideo_MPV.SetFrameRange(Range: TRectCoords);
begin
  fFrameRange := Range;
end;

function TVideo_MPV.GetFrameRange(): TRectCoords;
begin
  Result := fFrameRange;
end;

function TVideo_MPV.GetFrameAspect(): real;
begin
  Result := fAspect;
end;

procedure TVideo_MPV.SetAspectCorrection(AspectCorrection: TAspectCorrection);
begin
  fAspectCorrection := AspectCorrection;
end;

function TVideo_MPV.GetAspectCorrection(): TAspectCorrection;
begin
  Result := fAspectCorrection;
end;

procedure TVideo_MPV.SetAlpha(Alpha: double);
begin
  fAlpha := Alpha;
  if fAlpha > 1 then
    fAlpha := 1;
  if fAlpha < 0 then
    fAlpha := 0;
end;

function TVideo_MPV.GetAlpha(): double;
begin
  Result := fAlpha;
end;

procedure TVideo_MPV.SetReflectionSpacing(Spacing: double);
begin
  fReflectionSpacing := Spacing;
end;

function TVideo_MPV.GetReflectionSpacing(): double;
begin
  Result := fReflectionSpacing;
end;

initialization
  MediaManager.Insert(0, TVideoPlayback_MPV.Create);

end.
