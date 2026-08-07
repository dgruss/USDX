// UltraStar Deluxe - Karaoke Game
// SPDX-License-Identifier: GPL-2.0-or-later

unit UAudioInput_SDL;

interface

{$IFDEF FPC}
  {$MODE Delphi}
{$ENDIF}

{$I ../switches.inc}

uses
  Classes,
  SysUtils,
  UMusic;

implementation

uses
  SDL3,
  ctypes,
  math,
  UIni,
  ULog,
  URecord;

type
  TAudioInput_SDL = class(TAudioInputBase)
    private
      Initialized: boolean;
      function EnumDevices(): boolean;
    public
      function GetName: string; override;
      function InitializeRecord(ScanMode: TAudioInputScanMode): boolean; override;
      function FinalizeRecord: boolean; override;
  end;

  TSDLInputDevice = class(TAudioInputDevice)
    private
      DeviceID: TSDL_AudioDeviceID;
      Stream: PSDL_AudioStream;
    public
      function Start(): boolean; override;
      function Stop():  boolean; override;

      function GetVolume(): single;        override;
      procedure SetVolume(Volume: single); override;
  end;

procedure MicrophoneCallback(userdata: Pointer; stream: PSDL_AudioStream;
    additional_amount, total_amount: cint); cdecl;
var
  Buffer: Pointer;
  BytesRead: integer;
begin
  if total_amount <= 0 then
    Exit;
  GetMem(Buffer, total_amount);
  try
    BytesRead := SDL_GetAudioStreamData(stream, Buffer, total_amount);
    if BytesRead > 0 then
      AudioInputProcessor.HandleMicrophoneData(Buffer, BytesRead, TSDLInputDevice(userdata));
  finally
    FreeMem(Buffer);
  end;
end;

function TSDLInputDevice.Start(): boolean;
var
  spec: TSDL_AudioSpec;
  SampleFrames: integer;
begin
  Result := false;

  if Stream = nil then
  begin
    FillChar(spec, SizeOf(spec), 0);
    with spec do
    begin
      freq := Round(AudioFormat.SampleRate);
      format := SDL_AUDIO_S16;
      channels := AudioFormat.Channels;
    end;

    SampleFrames := 0;
    if Ini.InputDeviceConfig[CfgIndex].Latency > 0 then
    begin
      SampleFrames := 1 shl Round(Max(Log2(spec.freq / 1000 *
          Ini.InputDeviceConfig[CfgIndex].Latency), 0));
      SDL_SetHint(SDL_HINT_AUDIO_DEVICE_SAMPLE_FRAMES,
          PChar(IntToStr(SampleFrames)));
    end;

    Stream := SDL_OpenAudioDeviceStream(DeviceID, @spec, @MicrophoneCallback, Self);
    if SampleFrames > 0 then
      SDL_ResetHint(SDL_HINT_AUDIO_DEVICE_SAMPLE_FRAMES);
    if Stream <> nil then
    begin
      if not SDL_ResumeAudioStreamDevice(Stream) then
      begin
        Log.LogError('Could not start input device "' + Name + '": ' + SDL_GetError, 'SDL');
        SDL_DestroyAudioStream(Stream);
        Stream := nil;
      end;
    end
    else
      Log.LogError('Could not open input device "' + Name + '": ' + SDL_GetError, 'SDL');
  end;

  Result := Stream <> nil;
end;

function TSDLInputDevice.Stop(): boolean;
begin
  if Stream <> nil then
  begin
    SDL_DestroyAudioStream(Stream);
    Stream := nil;
  end;
  Result := true;
end;

function TSDLInputDevice.GetVolume(): single;
begin
  Result := 0;
end;

procedure TSDLInputDevice.SetVolume(Volume: single);
begin
end;

function TAudioInput_SDL.GetName: String;
begin
  Result := 'SDL';
  if SDL_WasInit(SDL_INIT_AUDIO) <> 0 then
    Result := Result + ' (' + SDL_GetCurrentAudioDriver + ')';
end;

function TAudioInput_SDL.EnumDevices(): boolean;
type
  TAudioDeviceIDArray = array[0..0] of TSDL_AudioDeviceID;
  PAudioDeviceIDArray = ^TAudioDeviceIDArray;
var
  i:            integer;
  deviceIndex:  integer;
  maxDevices:   integer;
  name:         PAnsiChar;
  deviceIDs:    PSDL_AudioDeviceID;
  device:       TSDLInputDevice;
  spec:         TSDL_AudioSpec;
  sampleFrames: integer;
  deviceName:   UTF8String;
begin
  Result := false;

  Log.LogInfo('Using ' + SDL_GetCurrentAudioDriver + ' driver', 'SDL');

  deviceIDs := SDL_GetAudioRecordingDevices(@maxDevices);
  if maxDevices < 1 then
    maxDevices := 1;

  // init array-size to max. input-devices count
  SetLength(AudioInputProcessor.DeviceList, maxDevices);

  deviceIndex := 0;
  for i := 0 to High(AudioInputProcessor.DeviceList) do
  begin
    if deviceIDs <> nil then
      name := SDL_GetAudioDeviceName(PAudioDeviceIDArray(deviceIDs)^[i])
    else
      name := nil;

    deviceName := DEFAULT_SOURCE_NAME;
    if (name <> nil) then
      deviceName := name;
    deviceName := UnifyDeviceName(deviceName, i);
    if not ShouldProbeDevice(deviceName) then
      continue;

    FillChar(spec, SizeOf(spec), 0);
    with spec do
    begin
      freq := 44100;
      format := SDL_AUDIO_S16;
      channels := 1;
    end;

    sampleFrames := 0;
    if deviceIDs <> nil then
      SDL_GetAudioDeviceFormat(PAudioDeviceIDArray(deviceIDs)^[i], @spec, @sampleFrames);
    spec.format := SDL_AUDIO_S16;

    device := TSDLInputDevice.Create();
    device.Name := deviceName;
    if deviceIDs <> nil then
      device.DeviceID := PAudioDeviceIDArray(deviceIDs)^[i]
    else
      device.DeviceID := SDL_AUDIO_DEVICE_DEFAULT_RECORDING;

    device.MicSource := -1;
    device.SourceRestore := -1;
    SetLength(device.Source, 1);
    device.Source[0].Name := DEFAULT_SOURCE_NAME;

    // create audio-format info and resize capture-buffer array
    device.AudioFormat := TAudioFormatInfo.Create(
        spec.channels,
        spec.freq,
        asfS16
    );
    SetLength(device.CaptureChannel, device.AudioFormat.Channels);

    Log.LogStatus('InputDevice "' + device.Name + '"@' +
        IntToStr(device.AudioFormat.Channels) + 'x' +
        FloatToStr(device.AudioFormat.SampleRate) + 'Hz ' +
        'defaults to ' + IntToStr(sampleFrames) + ' samples buffer',
        'SDL');

    AudioInputProcessor.DeviceList[deviceIndex] := device;
    Inc(deviceIndex);
  end;
  SDL_free(deviceIDs);

  // adjust size to actual input-device count
  SetLength(AudioInputProcessor.DeviceList, deviceIndex);
  Log.LogStatus('#Input-Devices: ' + IntToStr(deviceIndex), 'SDL');
  Result := (deviceIndex > 0) or (ScanMode = aimFast);
end;

function TAudioInput_SDL.InitializeRecord(ScanMode: TAudioInputScanMode): boolean;
begin
  Result := false;

  if not SDL_InitSubSystem(SDL_INIT_AUDIO) then
    Exit;

  Initialized := true;
  PrepareDeviceScan(ScanMode);
  Result := EnumDevices();
end;

function TAudioInput_SDL.FinalizeRecord: boolean;
begin
  CaptureStop;
  if Initialized then
  begin
    SDL_QuitSubSystem(SDL_INIT_AUDIO);
    Initialized := false;
  end;
  Result := inherited FinalizeRecord();
end;

initialization
  MediaManager.add(TAudioInput_SDL.Create);

end.
