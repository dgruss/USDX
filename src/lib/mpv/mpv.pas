{* Minimal dynamic libmpv binding for UltraStar Deluxe. *}

unit mpv;

{$IFDEF FPC}
  {$MODE Delphi}
{$ENDIF}

interface

uses
  ctypes;

const
  MPV_FORMAT_NONE   = 0;
  MPV_FORMAT_STRING = 1;
  MPV_FORMAT_FLAG   = 3;
  MPV_FORMAT_INT64  = 4;
  MPV_FORMAT_DOUBLE = 5;

  MPV_EVENT_NONE        = 0;
  MPV_EVENT_SHUTDOWN    = 1;
  MPV_EVENT_END_FILE    = 7;
  MPV_EVENT_FILE_LOADED = 8;

  MPV_RENDER_PARAM_INVALID              = 0;
  MPV_RENDER_PARAM_API_TYPE             = 1;
  MPV_RENDER_PARAM_OPENGL_INIT_PARAMS   = 2;
  MPV_RENDER_PARAM_OPENGL_FBO           = 3;
  MPV_RENDER_PARAM_FLIP_Y               = 4;
  MPV_RENDER_PARAM_ADVANCED_CONTROL     = 10;

  MPV_RENDER_UPDATE_FRAME = 1 shl 0;

type
  Pmpv_handle = ^Tmpv_handle;
  Tmpv_handle = record end;

  Pmpv_render_context = ^Tmpv_render_context;
  Tmpv_render_context = record end;

  PPAnsiChar = ^PAnsiChar;

  Pmpv_event = ^Tmpv_event;
  Tmpv_event = record
    event_id: cint;
    error: cint;
    reply_userdata: QWord;
    data: Pointer;
  end;

  Pmpv_render_param = ^Tmpv_render_param;
  Tmpv_render_param = record
    ParamType: cint;
    data: Pointer;
  end;

  Tmpv_opengl_get_proc_address = function(ctx: Pointer; name: PAnsiChar): Pointer; cdecl;

  Pmpv_opengl_init_params = ^Tmpv_opengl_init_params;
  Tmpv_opengl_init_params = record
    get_proc_address: Tmpv_opengl_get_proc_address;
    get_proc_address_ctx: Pointer;
  end;

  Pmpv_opengl_fbo = ^Tmpv_opengl_fbo;
  Tmpv_opengl_fbo = record
    fbo: cint;
    w: cint;
    h: cint;
    internal_format: cint;
  end;

  Tmpv_render_update_fn = procedure(cb_ctx: Pointer); cdecl;

  Tmpv_client_api_version = function(): culong; cdecl;
  Tmpv_error_string = function(error: cint): PAnsiChar; cdecl;
  Tmpv_free = procedure(data: Pointer); cdecl;
  Tmpv_create = function(): Pmpv_handle; cdecl;
  Tmpv_initialize = function(ctx: Pmpv_handle): cint; cdecl;
  Tmpv_destroy = procedure(ctx: Pmpv_handle); cdecl;
  Tmpv_terminate_destroy = procedure(ctx: Pmpv_handle); cdecl;
  Tmpv_set_option_string = function(ctx: Pmpv_handle; name, value: PAnsiChar): cint; cdecl;
  Tmpv_set_property = function(ctx: Pmpv_handle; name: PAnsiChar; format: cint; data: Pointer): cint; cdecl;
  Tmpv_set_property_string = function(ctx: Pmpv_handle; name, value: PAnsiChar): cint; cdecl;
  Tmpv_get_property = function(ctx: Pmpv_handle; name: PAnsiChar; format: cint; data: Pointer): cint; cdecl;
  Tmpv_get_property_string = function(ctx: Pmpv_handle; name: PAnsiChar): PAnsiChar; cdecl;
  Tmpv_command = function(ctx: Pmpv_handle; args: PPAnsiChar): cint; cdecl;
  Tmpv_wait_event = function(ctx: Pmpv_handle; timeout: cdouble): Pmpv_event; cdecl;
  Tmpv_render_context_create = function(var res: Pmpv_render_context; mpv: Pmpv_handle; params: Pmpv_render_param): cint; cdecl;
  Tmpv_render_context_free = procedure(ctx: Pmpv_render_context); cdecl;
  Tmpv_render_context_set_update_callback = procedure(ctx: Pmpv_render_context; callback: Tmpv_render_update_fn; callback_ctx: Pointer); cdecl;
  Tmpv_render_context_update = function(ctx: Pmpv_render_context): QWord; cdecl;
  Tmpv_render_context_render = function(ctx: Pmpv_render_context; params: Pmpv_render_param): cint; cdecl;
  Tmpv_render_context_report_swap = function(ctx: Pmpv_render_context): cint; cdecl;

var
  mpv_client_api_version: Tmpv_client_api_version;
  mpv_error_string: Tmpv_error_string;
  mpv_free: Tmpv_free;
  mpv_create: Tmpv_create;
  mpv_initialize: Tmpv_initialize;
  mpv_destroy: Tmpv_destroy;
  mpv_terminate_destroy: Tmpv_terminate_destroy;
  mpv_set_option_string: Tmpv_set_option_string;
  mpv_set_property: Tmpv_set_property;
  mpv_set_property_string: Tmpv_set_property_string;
  mpv_get_property: Tmpv_get_property;
  mpv_get_property_string: Tmpv_get_property_string;
  mpv_command: Tmpv_command;
  mpv_wait_event: Tmpv_wait_event;

  mpv_render_context_create: Tmpv_render_context_create;
  mpv_render_context_free: Tmpv_render_context_free;
  mpv_render_context_set_update_callback: Tmpv_render_context_set_update_callback;
  mpv_render_context_update: Tmpv_render_context_update;
  mpv_render_context_render: Tmpv_render_context_render;
  mpv_render_context_report_swap: Tmpv_render_context_report_swap;

function LoadMpv(): boolean;
procedure UnloadMpv();
function MpvLoaded(): boolean;
function MpvLoadError(): string;

implementation

uses
  DynLibs,
  SysUtils;

var
  MpvLibHandle: TLibHandle = 0;
  LastMpvLoadError: string = '';

function LoadSymbol(const Name: PAnsiChar): Pointer;
begin
  Result := GetProcedureAddress(MpvLibHandle, Name);
end;

function LoadMpvLibrary(): TLibHandle;
const
{$IFDEF MSWINDOWS}
  LibraryNames: array[0..2] of string = ('libmpv-2.dll', 'mpv-2.dll', 'libmpv.dll');
{$ELSE}
{$IFDEF DARWIN}
  LibraryNames: array[0..1] of string = ('libmpv.2.dylib', 'libmpv.dylib');
{$ELSE}
  LibraryNames: array[0..2] of string = ('libmpv.so.2', 'libmpv.so.1', 'libmpv.so');
{$ENDIF}
{$ENDIF}
var
  LibraryName: string;
begin
  Result := 0;
  LastMpvLoadError := '';
  for LibraryName in LibraryNames do
  begin
    Result := DynLibs.LoadLibrary(LibraryName);
    if Result <> 0 then
    begin
      LastMpvLoadError := '';
      Exit;
    end;

    if LastMpvLoadError <> '' then
      LastMpvLoadError := LastMpvLoadError + '; ';
    LastMpvLoadError := LastMpvLoadError + LibraryName + ': ' + SysErrorMessage(GetLastOSError);
  end;
end;

function LoadMpv(): boolean;
begin
  if MpvLibHandle <> 0 then
    Exit(true);

  MpvLibHandle := LoadMpvLibrary();
  if MpvLibHandle = 0 then
    Exit(false);

  mpv_client_api_version := Tmpv_client_api_version(LoadSymbol('mpv_client_api_version'));
  mpv_error_string := Tmpv_error_string(LoadSymbol('mpv_error_string'));
  mpv_free := Tmpv_free(LoadSymbol('mpv_free'));
  mpv_create := Tmpv_create(LoadSymbol('mpv_create'));
  mpv_initialize := Tmpv_initialize(LoadSymbol('mpv_initialize'));
  mpv_destroy := Tmpv_destroy(LoadSymbol('mpv_destroy'));
  mpv_terminate_destroy := Tmpv_terminate_destroy(LoadSymbol('mpv_terminate_destroy'));
  mpv_set_option_string := Tmpv_set_option_string(LoadSymbol('mpv_set_option_string'));
  mpv_set_property := Tmpv_set_property(LoadSymbol('mpv_set_property'));
  mpv_set_property_string := Tmpv_set_property_string(LoadSymbol('mpv_set_property_string'));
  mpv_get_property := Tmpv_get_property(LoadSymbol('mpv_get_property'));
  mpv_get_property_string := Tmpv_get_property_string(LoadSymbol('mpv_get_property_string'));
  mpv_command := Tmpv_command(LoadSymbol('mpv_command'));
  mpv_wait_event := Tmpv_wait_event(LoadSymbol('mpv_wait_event'));
  mpv_render_context_create := Tmpv_render_context_create(LoadSymbol('mpv_render_context_create'));
  mpv_render_context_free := Tmpv_render_context_free(LoadSymbol('mpv_render_context_free'));
  mpv_render_context_set_update_callback := Tmpv_render_context_set_update_callback(LoadSymbol('mpv_render_context_set_update_callback'));
  mpv_render_context_update := Tmpv_render_context_update(LoadSymbol('mpv_render_context_update'));
  mpv_render_context_render := Tmpv_render_context_render(LoadSymbol('mpv_render_context_render'));
  mpv_render_context_report_swap := Tmpv_render_context_report_swap(LoadSymbol('mpv_render_context_report_swap'));

  Result :=
    Assigned(mpv_client_api_version) and
    Assigned(mpv_error_string) and
    Assigned(mpv_free) and
    Assigned(mpv_create) and
    Assigned(mpv_initialize) and
    Assigned(mpv_destroy) and
    Assigned(mpv_terminate_destroy) and
    Assigned(mpv_set_option_string) and
    Assigned(mpv_set_property) and
    Assigned(mpv_set_property_string) and
    Assigned(mpv_get_property) and
    Assigned(mpv_get_property_string) and
    Assigned(mpv_command) and
    Assigned(mpv_wait_event) and
    Assigned(mpv_render_context_create) and
    Assigned(mpv_render_context_free) and
    Assigned(mpv_render_context_set_update_callback) and
    Assigned(mpv_render_context_update) and
    Assigned(mpv_render_context_render) and
    Assigned(mpv_render_context_report_swap);

  if not Result then
  begin
    LastMpvLoadError := 'loaded libmpv, but one or more required libmpv symbols are missing';
    UnloadMpv();
  end;
end;

procedure UnloadMpv();
begin
  if MpvLibHandle <> 0 then
  begin
    UnloadLibrary(MpvLibHandle);
    MpvLibHandle := 0;
  end;
end;

function MpvLoaded(): boolean;
begin
  Result := MpvLibHandle <> 0;
end;

function MpvLoadError(): string;
begin
  Result := LastMpvLoadError;
  if Result = '' then
    Result := 'unknown error';
end;

end.
