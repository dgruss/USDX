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
 * $URL: https://ultrastardx.svn.sourceforge.net/svnroot/ultrastardx/trunk/src/screens/UScreenHighScores.pas $
 * $Id: UScreenHighScores.pas 2548 2010-06-18 11:00:21Z whiteshark0 $
 *}

unit UScreenHighScores;

interface

{$IFDEF FPC}
  {$MODE Delphi}
{$ENDIF}

{$I switches.inc}

uses
  UDisplay,
  UMenu,
  UMusic,
  USongs,
  UThemes,
  sdl2,
  SysUtils;

type
  TScreenHighScores = class(TMenu)
    public
      TextLevel:       integer;
      TextArtistTitle: integer;
      DifficultyShow:  integer;

      StaticNumber:    array[1..5] of integer;
      TextNumber:      array[1..5] of integer;
      TextName:        array[1..5] of integer;
      TextScore:       array[1..5] of integer;
      TextDate:        array[1..5] of integer;

      Fadeout:         boolean;

      constructor Create; override;
      function ParseInput(PressedKey: cardinal; CharCode: UCS4Char; PressedDown: boolean): boolean; override;
      function ParseMouse(MouseButton: integer; BtnDown: boolean; X, Y: integer): boolean; override;
      procedure OnShow; override;
      procedure DrawScores(difficulty: integer);
      function Draw: boolean; override;
  end;

const
  ID='ID_024';   //for help system

implementation

uses
  UDataBase,
  UGraphic,
  UHelp,
  ULog,
  UMain,
  UIni,
  UNote,
  UUnicodeUtils;

function TScreenHighScores.ParseInput(PressedKey: cardinal; CharCode: UCS4Char; PressedDown: boolean): boolean;
begin
  Result := true;
  if PressedDown then
  begin
    // check normal keys
    case PressedKey of
      SDLK_Q:
        begin
          Result := false;
          Exit;
        end;
    end;

    // check special keys
    case PressedKey of
      SDLK_ESCAPE,
      SDLK_BACKSPACE,
      SDLK_RETURN:
        begin
          if (not Fadeout) then
          begin
            FadeTo(@ScreenSong);
            Fadeout := true;
          end;
        end;
      SDLK_TAB:
        begin
          ScreenPopupHelp.ShowPopup();
        end;
      SDLK_RIGHT:
        begin
          inc(DifficultyShow);
          if (DifficultyShow>2) then
            DifficultyShow:=0;
          DrawScores(DifficultyShow);
        end;
      SDLK_LEFT:
        begin
          dec(DifficultyShow);
          if (DifficultyShow<0) then
            DifficultyShow:=2;
          DrawScores(DifficultyShow);
        end;
      SDLK_UP:
        begin
          inc(DifficultyShow);
          if (DifficultyShow>2) then
            DifficultyShow:=0;
          DrawScores(DifficultyShow);
        end;
      SDLK_DOWN:
        begin
          dec(DifficultyShow);
          if (DifficultyShow<0) then
            DifficultyShow:=2;
          DrawScores(DifficultyShow);
        end;
    end;
  end;
end;

function TScreenHighScores.ParseMouse(MouseButton: integer;
                                BtnDown: boolean;
				X, Y: integer): boolean;
begin
  Result := true;
  if (MouseButton = SDL_BUTTON_LEFT) and BtnDown then
    //left-click anywhere sends return
    ParseInput(SDLK_RETURN, 0, true);
end;

constructor TScreenHighScores.Create;
var
  I: integer;
begin
  inherited Create;

  LoadFromTheme(Theme.HighScores);

  TextLevel       := AddText(Theme.HighScores.TextLevel);
  TextArtistTitle := AddText(Theme.HighScores.TextArtistTitle);

  for I := 0 to 4 do
  begin
    StaticNumber[I+1] := AddStatic(Theme.HighScores.StaticNumber[I]);
    TextNumber[I+1]   := AddText  (Theme.HighScores.TextNumber[I]);
    TextName[I+1]     := AddText  (Theme.HighScores.TextName[I]);
    TextScore[I+1]    := AddText  (Theme.HighScores.TextScore[I]);
    TextDate[I+1]     := AddText  (Theme.HighScores.TextDate[I]);
  end;

end;

procedure TScreenHighScores.OnShow;
var
  I:    integer;
  Report: string;
begin
  inherited;

  if not Help.SetHelpID(ID) then
    Log.LogWarn('No Entry for Help-ID ' + ID, 'ScreenHighScores');

  Fadeout := false;
  DifficultyShow := Player[0].Level;

  try
    DataBase.ReadScore(CurrentSong);
  except
    on E : Exception do
    begin
      Report := 'Reading songscore failed in Top-5-screen. Faulty database file?' + LineEnding +
      'Stacktrace:' + LineEnding;
      if E <> nil then
      begin
	Report := Report + 'Exception class: ' + E.ClassName + LineEnding +
	'Message: ' + E.Message + LineEnding;
      end;
      Report := Report + BackTraceStrFunc(ExceptAddr);
      for I := 0 to ExceptFrameCount - 1 do
      begin
	Report := Report + LineEnding + BackTraceStrFunc(ExceptFrames[I]);
      end;
      Log.LogWarn(Report, 'UScreenHighScores.OnShow');
    end;
  end;

  Text[TextArtistTitle].Text := CurrentSong.Artist + ' - ' + CurrentSong.Title;

  // TODO: the following loops are really hard to read
  for I := 1 to Length(CurrentSong.Score[Player[0].Level]) do
  begin
    Statics[StaticNumber[I]].Visible := true;
    Text[TextNumber[I]].Visible := true;
    Text[TextName[I]].Visible := true;
    Text[TextScore[I]].Visible := true;
    Text[TextDate[I]].Visible := true;

    Text[TextName[I]].Text := CurrentSong.Score[Player[0].Level, I-1].Name;
    Text[TextScore[I]].Text := IntToStr(CurrentSong.Score[Player[0].Level, I-1].Score);
    Text[TextDate[I]].Text := CurrentSong.Score[Player[0].Level, I-1].Date;
  end;

  If Length(CurrentSong.Score[Player[0].Level])=0 then
    FadeTo(@ScreenSong); //if there are no scores to show, go to next screen
  for I := Length(CurrentSong.Score[Player[0].Level]) + 1 to 5 do
  begin
    Statics[StaticNumber[I]].Visible := false;
    Text[TextNumber[I]].Visible := false;
    Text[TextName[I]].Visible := false;
    Text[TextScore[I]].Visible := false;
    Text[TextDate[I]].Visible := false;
  end;

  Text[TextLevel].Text := IDifficultyTranslated[Player[0].Level];
end;

procedure TScreenHighScores.DrawScores(difficulty: integer);
var
  I:    integer;
begin
  for I := 1 to Length(CurrentSong.Score[difficulty]) do
  begin
    Statics[StaticNumber[I]].Visible := true;
    Text[TextNumber[I]].Visible := true;
    Text[TextName[I]].Visible := true;
    Text[TextScore[I]].Visible := true;
    Text[TextDate[I]].Visible := true;

    Text[TextName[I]].Text := CurrentSong.Score[difficulty, I-1].Name;
    Text[TextScore[I]].Text := IntToStr(CurrentSong.Score[difficulty, I-1].Score);
    Text[TextDate[I]].Text := CurrentSong.Score[difficulty, I-1].Date;
  end;

  for I := Length(CurrentSong.Score[difficulty]) + 1 to 5 do
  begin
    Statics[StaticNumber[I]].Visible := false;
    Text[TextNumber[I]].Visible := false;
    Text[TextName[I]].Visible := false;
    Text[TextScore[I]].Visible := false;
    Text[TextDate[I]].Visible := false;
  end;

  Text[TextLevel].Text := IDifficulty[difficulty];
end;

function TScreenHighScores.Draw: boolean;
begin
  Result := inherited Draw;
end;

end.
