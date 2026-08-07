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
 * $URL: svn://basisbit@svn.code.sf.net/p/ultrastardx/svn/trunk/src/media/UMediaCore_SDL.pas $
 * $Id: UMediaCore_SDL.pas 2475 2010-06-10 18:27:53Z brunzelchen $
 *}

unit UMediaCore_SDL;

interface

{$IFDEF FPC}
  {$MODE Delphi}
{$ENDIF}

{$I switches.inc}

uses
  UMusic,
  SDL3;

function ConvertAudioFormatToSDL(Format: TAudioSampleFormat; out SDLFormat: UInt16): boolean;
function ConvertAudioFormatFromSDL(SDLFormat: UInt16; out Format: TAudioSampleFormat): boolean;

implementation

function ConvertAudioFormatToSDL(Format: TAudioSampleFormat; out SDLFormat: UInt16): boolean;
begin
  case Format of
    asfU8:     SDLFormat := UInt16(SDL_AUDIO_U8);
    asfS8:     SDLFormat := UInt16(SDL_AUDIO_S8);
    asfS16LSB: SDLFormat := UInt16(SDL_AUDIO_S16LE);
    asfS16MSB: SDLFormat := UInt16(SDL_AUDIO_S16BE);
    asfS16:    SDLFormat := UInt16(SDL_AUDIO_S16);
    asfS32:    SDLFormat := UInt16(SDL_AUDIO_S32);
    asfFloat:  SDLFormat := UInt16(SDL_AUDIO_F32);
    else begin
      Result := false;
      Exit;
    end;
  end;
  Result := true;
end;

function ConvertAudioFormatFromSDL(SDLFormat: UInt16; out Format: TAudioSampleFormat): boolean;
begin
  case SDLFormat of
    UInt16(SDL_AUDIO_U8):    Format := asfU8;
    UInt16(SDL_AUDIO_S8):    Format := asfS8;
    UInt16(SDL_AUDIO_S16LE): Format := asfS16LSB;
    UInt16(SDL_AUDIO_S16BE): Format := asfS16MSB;
    UInt16(SDL_AUDIO_S32):   Format := asfS32;
    UInt16(SDL_AUDIO_F32):   Format := asfFloat;
    else begin
      Result := false;
      Exit;
    end;
  end;
  Result := true;
end;

end.
