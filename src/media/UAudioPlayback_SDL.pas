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
 * $URL: svn://basisbit@svn.code.sf.net/p/ultrastardx/svn/trunk/src/media/UAudioPlayback_SDL.pas $
 * $Id: UAudioPlayback_SDL.pas 2475 2010-06-10 18:27:53Z brunzelchen $
 *}

unit UAudioPlayback_SDL;

interface

{$IFDEF FPC}
  {$MODE Delphi}
{$ENDIF}

{$I switches.inc}

implementation

uses
  Classes,
  SDL3,
  SysUtils,
  UAudioPlayback_SoftMixer,
  UMediaCore_SDL,
  UMusic,
  ULog,
  UIni,
  UMain;

type
  TAudioPlayback_SDL = class(TAudioPlayback_SoftMixer)
    private
      Latency: double;
      Stream: PSDL_AudioStream;
      function EnumDevices(): boolean;
    protected
      function InitializeAudioPlaybackEngine(): boolean; override;
      function StartAudioPlaybackEngine(): boolean;      override;
      procedure StopAudioPlaybackEngine();               override;
      function FinalizeAudioPlaybackEngine(): boolean;   override;
      function GetLatency(): double;                     override;
    public
      function GetName: String;                          override;
      procedure MixBuffers(dst, src: PByteArray; size: Cardinal; volume: Single); override;
  end;

  
{ TAudioPlayback_SDL }

procedure SDLAudioCallback(userdata: Pointer; stream: PSDL_AudioStream;
    additional_amount, total_amount: integer); cdecl;
var
  Engine: TAudioPlayback_SDL;
  Buffer: PByteArray;
begin
  if additional_amount <= 0 then
    Exit;
  Engine := TAudioPlayback_SDL(userdata);
  GetMem(Buffer, additional_amount);
  try
    Engine.AudioCallback(Buffer, additional_amount);
    SDL_PutAudioStreamData(stream, Buffer, additional_amount);
  finally
    FreeMem(Buffer);
  end;
end;

function TAudioPlayback_SDL.GetName: String;
begin
  Result := 'SDL_Playback';
end;

function TAudioPlayback_SDL.EnumDevices(): boolean;
begin
  // Note: SDL does not provide Device-Selection capabilities (will be introduced in 1.3)
  ClearOutputDeviceList();
  SetLength(OutputDeviceList, 1);
  OutputDeviceList[0] := TAudioOutputDevice.Create();
  OutputDeviceList[0].Name := '[SDL Default-Device]';
  Result := true;
end;

function TAudioPlayback_SDL.InitializeAudioPlaybackEngine(): boolean;
var
  DesiredAudioSpec, DeviceAudioSpec: TSDL_AudioSpec;
  SampleBufferSize: integer;
  DeviceSampleFrames: integer;
begin
  Result := false;

  EnumDevices();

  if not SDL_InitSubSystem(SDL_INIT_AUDIO) then
  begin
    Log.LogError('SDL_InitSubSystem failed!', 'TAudioPlayback_SDL.InitializeAudioPlaybackEngine');
    Exit;
  end;

  SampleBufferSize := IAudioOutputBufferSizeVals[Ini.AudioOutputBufferSizeIndex];
  if (SampleBufferSize <= 0) then
  begin
    // Automatic setting default
    // FIXME: too much glitches with 1024 samples
    SampleBufferSize := 2048; //1024;
  end;

  FillChar(DesiredAudioSpec, SizeOf(DesiredAudioSpec), 0);
  with DesiredAudioSpec do
  begin
    freq := 44100;
    format := SDL_AUDIO_S16;
    channels := 2;
  end;

  // Preserve the user-facing buffer-size setting. SDL3 moved this from the
  // audio specification to a hint that is consumed while opening the device.
  SDL_SetHint(SDL_HINT_AUDIO_DEVICE_SAMPLE_FRAMES, PChar(IntToStr(SampleBufferSize)));
  Stream := SDL_OpenAudioDeviceStream(SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK,
      @DesiredAudioSpec, @SDLAudioCallback, Self);
  SDL_ResetHint(SDL_HINT_AUDIO_DEVICE_SAMPLE_FRAMES);
  if Stream = nil then
  begin
    Log.LogStatus('SDL_OpenAudioDeviceStream: ' + SDL_GetError(), 'TAudioPlayback_SDL.InitializeAudioPlaybackEngine');
    Exit;
  end;

  FormatInfo := TAudioFormatInfo.Create(
    DesiredAudioSpec.channels,
    DesiredAudioSpec.freq,
    asfS16
  );

  DeviceSampleFrames := SampleBufferSize;
  if SDL_GetAudioDeviceFormat(SDL_GetAudioStreamDevice(Stream),
      @DeviceAudioSpec, @DeviceSampleFrames) and (DeviceAudioSpec.freq > 0) then
    // Keep the historical average-buffer latency estimate used by USDX.
    Latency := (DeviceSampleFrames / 2) / DeviceAudioSpec.freq
  else
    Latency := (SampleBufferSize / 2) / FormatInfo.SampleRate;

  Log.LogStatus('Opened audio device', 'TAudioPlayback_SDL.InitializeAudioPlaybackEngine');

  Result := true;
end;

function TAudioPlayback_SDL.StartAudioPlaybackEngine(): boolean;
begin
  Result := (Stream <> nil) and SDL_ResumeAudioStreamDevice(Stream);
end;

procedure TAudioPlayback_SDL.StopAudioPlaybackEngine();
begin
  if Stream <> nil then
    SDL_PauseAudioStreamDevice(Stream);
end;

function TAudioPlayback_SDL.FinalizeAudioPlaybackEngine(): boolean;
begin
  if Stream <> nil then
  begin
    SDL_DestroyAudioStream(Stream);
    Stream := nil;
  end;
  SDL_QuitSubSystem(SDL_INIT_AUDIO);
  Result := true;
end;

function TAudioPlayback_SDL.GetLatency(): double;
begin
  Result := Latency;
end;

procedure TAudioPlayback_SDL.MixBuffers(dst, src: PByteArray; size: Cardinal; volume: Single);
begin
  SDL_MixAudio(PUInt8(dst), PUInt8(src), SDL_AUDIO_S16, size, volume);
end;


initialization
  MediaManager.add(TAudioPlayback_SDL.Create);

end.
