unit Floria.GL;

// Floria.GL
// =========
// Pure Object Pascal OpenGL & OpenGL ES dynamic loader and function table.
//
// Capabilities:
// - Dynamic loading of OpenGL / GLES 2.0+ via dynlibs and eglGetProcAddress
//   with zero hard link-time dependencies.
// - Supports desktop OpenGL (libGL.so.1) and OpenGL ES 2.0/3.0 (libGLESv2.so.2).
// - Comprehensive function pointer table for shaders, VBOs, textures, FBOs,
//   and rasterization state.
// - TGLEngine loader class and FloriaGL() singleton.

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, ctypes, dynlibs,
  Floria.EGL;

const
  // Boolean
  GL_FALSE                = 0;
  GL_TRUE                 = 1;

  // Primitives
  GL_POINTS               = $0000;
  GL_LINES                = $0001;
  GL_LINE_LOOP            = $0002;
  GL_LINE_STRIP           = $0003;
  GL_TRIANGLES            = $0004;
  GL_TRIANGLE_STRIP       = $0005;
  GL_TRIANGLE_FAN         = $0006;

  // Data Types
  GL_BYTE                 = $1400;
  GL_UNSIGNED_BYTE        = $1401;
  GL_SHORT                = $1402;
  GL_UNSIGNED_SHORT       = $1403;
  GL_INT                  = $1404;
  GL_UNSIGNED_INT         = $1405;
  GL_FLOAT                = $1406;

  // State Enable/Disable
  GL_BLEND                = $0BE2;
  GL_SCISSOR_TEST         = $0C11;
  GL_CULL_FACE            = $0B44;
  GL_DEPTH_TEST           = $0B71;

  // Blending
  GL_ZERO                 = 0;
  GL_ONE                  = 1;
  GL_SRC_COLOR            = $0300;
  GL_ONE_MINUS_SRC_COLOR  = $0301;
  GL_SRC_ALPHA            = $0302;
  GL_ONE_MINUS_SRC_ALPHA  = $0303;
  GL_DST_ALPHA            = $0304;
  GL_ONE_MINUS_DST_ALPHA  = $0305;
  GL_DST_COLOR            = $0306;
  GL_ONE_MINUS_DST_COLOR  = $0307;
  GL_SRC_ALPHA_SATURATE   = $0308;
  GL_FUNC_ADD             = $8006;
  GL_FUNC_SUBTRACT        = $800A;
  GL_FUNC_REVERSE_SUBTRACT= $800B;

  // Clear Mask
  GL_COLOR_BUFFER_BIT     = $00004000;
  GL_DEPTH_BUFFER_BIT     = $00000100;
  GL_STENCIL_BUFFER_BIT   = $00000400;

  // Textures
  GL_TEXTURE_2D           = $0DE1;
  GL_NEAREST              = $2600;
  GL_LINEAR               = $2601;
  GL_NEAREST_MIPMAP_NEAREST = $2700;
  GL_LINEAR_MIPMAP_NEAREST  = $2701;
  GL_NEAREST_MIPMAP_LINEAR  = $2702;
  GL_LINEAR_MIPMAP_LINEAR   = $2703;
  GL_TEXTURE_MAG_FILTER   = $2800;
  GL_TEXTURE_MIN_FILTER   = $2801;
  GL_TEXTURE_WRAP_S       = $2802;
  GL_TEXTURE_WRAP_T       = $2803;
  GL_CLAMP_TO_EDGE        = $812F;
  GL_REPEAT               = $2901;
  GL_MIRRORED_REPEAT      = $8370;

  // Pixel Formats
  GL_ALPHA                = $1906;
  GL_RGB                  = $1907;
  GL_RGBA                 = $1908;
  GL_LUMINANCE            = $1909;
  GL_LUMINANCE_ALPHA      = $190A;
  GL_BGRA_EXT             = $80E1;

  // Pixel Store
  GL_UNPACK_ALIGNMENT     = $0CF5;
  GL_UNPACK_ROW_LENGTH    = $0CF2;
  GL_UNPACK_SKIP_ROWS     = $0CF3;
  GL_UNPACK_SKIP_PIXELS   = $0CF4;

  // Texture Units
  GL_TEXTURE0             = $84C0;
  GL_TEXTURE1             = $84C1;
  GL_TEXTURE2             = $84C2;
  GL_TEXTURE3             = $84C3;

  // Buffers
  GL_ARRAY_BUFFER         = $8892;
  GL_ELEMENT_ARRAY_BUFFER = $8893;
  GL_STATIC_DRAW          = $88E4;
  GL_DYNAMIC_DRAW         = $88E8;
  GL_STREAM_DRAW          = $88E0;

  // Shaders
  GL_FRAGMENT_SHADER      = $8B30;
  GL_VERTEX_SHADER        = $8B31;
  GL_COMPILE_STATUS       = $8B81;
  GL_LINK_STATUS          = $8B82;
  GL_INFO_LOG_LENGTH      = $8B84;
  GL_ACTIVE_UNIFORMS      = $8B86;
  GL_ACTIVE_ATTRIBUTES    = $8B89;

  // Framebuffers
  GL_FRAMEBUFFER          = $8D40;
  GL_RENDERBUFFER         = $8D41;
  GL_COLOR_ATTACHMENT0    = $8CE0;
  GL_DEPTH_ATTACHMENT     = $8D00;
  GL_STENCIL_ATTACHMENT   = $8D20;
  GL_FRAMEBUFFER_COMPLETE = $8CD5;

  // Query String
  GL_VENDOR               = $1F00;
  GL_RENDERER             = $1F01;
  GL_VERSION              = $1F02;
  GL_EXTENSIONS           = $1F03;
  GL_SHADING_LANGUAGE_VERSION = $8B8C;

  // Errors
  GL_NO_ERROR             = 0;
  GL_INVALID_ENUM         = $0500;
  GL_INVALID_VALUE        = $0501;
  GL_INVALID_OPERATION    = $0502;
  GL_OUT_OF_MEMORY        = $0505;
  GL_INVALID_FRAMEBUFFER_OPERATION = $0506;

type
  // Function pointer types
  TglViewport = procedure(x, y, width, height: cint); cdecl;
  TglClear = procedure(mask: cuint); cdecl;
  TglClearColor = procedure(red, green, blue, alpha: cfloat); cdecl;
  TglEnable = procedure(cap: cuint); cdecl;
  TglDisable = procedure(cap: cuint); cdecl;
  TglBlendFunc = procedure(sfactor, dfactor: cuint); cdecl;
  TglBlendFuncSeparate = procedure(srcRGB, dstRGB, srcAlpha, dstAlpha: cuint); cdecl;
  TglBlendEquation = procedure(mode: cuint); cdecl;
  TglBlendEquationSeparate = procedure(modeRGB, modeAlpha: cuint); cdecl;
  TglScissor = procedure(x, y, width, height: cint); cdecl;
  TglGetError = function(): cuint; cdecl;
  TglGetString = function(name: cuint): PChar; cdecl;
  TglGetIntegerv = procedure(pname: cuint; params: Pcint); cdecl;

  TglGenBuffers = procedure(n: cint; buffers: Pcuint); cdecl;
  TglBindBuffer = procedure(target: cuint; buffer: cuint); cdecl;
  TglBufferData = procedure(target: cuint; size: csize_t; const data: Pointer; usage: cuint); cdecl;
  TglBufferSubData = procedure(target: cuint; offset: csize_t; size: csize_t; const data: Pointer); cdecl;
  TglDeleteBuffers = procedure(n: cint; const buffers: Pcuint); cdecl;

  TglGenTextures = procedure(n: cint; textures: Pcuint); cdecl;
  TglBindTexture = procedure(target: cuint; texture: cuint); cdecl;
  TglTexParameteri = procedure(target, pname: cuint; param: cint); cdecl;
  TglTexImage2D = procedure(target: cuint; level, internalformat, width, height, border: cint; format, type_: cuint; const pixels: Pointer); cdecl;
  TglTexSubImage2D = procedure(target: cuint; level, xoffset, yoffset, width, height: cint; format, type_: cuint; const pixels: Pointer); cdecl;
  TglDeleteTextures = procedure(n: cint; const textures: Pcuint); cdecl;
  TglActiveTexture = procedure(texture: cuint); cdecl;
  TglPixelStorei = procedure(pname: cuint; param: cint); cdecl;

  TglCreateShader = function(type_: cuint): cuint; cdecl;
  TglShaderSource = procedure(shader: cuint; count: cint; const strings: PPChar; const length: Pcint); cdecl;
  TglCompileShader = procedure(shader: cuint); cdecl;
  TglGetShaderiv = procedure(shader, pname: cuint; params: Pcint); cdecl;
  TglGetShaderInfoLog = procedure(shader: cuint; bufsize: cint; length: Pcint; infolog: PChar); cdecl;
  TglDeleteShader = procedure(shader: cuint); cdecl;

  TglCreateProgram = function(): cuint; cdecl;
  TglAttachShader = procedure(program_, shader: cuint); cdecl;
  TglLinkProgram = procedure(program_: cuint); cdecl;
  TglGetProgramiv = procedure(program_, pname: cuint; params: Pcint); cdecl;
  TglGetProgramInfoLog = procedure(program_: cuint; bufsize: cint; length: Pcint; infolog: PChar); cdecl;
  TglUseProgram = procedure(program_: cuint); cdecl;
  TglDeleteProgram = procedure(program_: cuint); cdecl;

  TglGetAttribLocation = function(program_: cuint; const name: PChar): cint; cdecl;
  TglGetUniformLocation = function(program_: cuint; const name: PChar): cint; cdecl;
  TglEnableVertexAttribArray = procedure(index: cuint); cdecl;
  TglDisableVertexAttribArray = procedure(index: cuint); cdecl;
  TglVertexAttribPointer = procedure(index: cuint; size: cint; type_: cuint; normalized: cbool; stride: cint; const pointer_: Pointer); cdecl;

  TglUniform1i = procedure(location: cint; v0: cint); cdecl;
  TglUniform1f = procedure(location: cint; v0: cfloat); cdecl;
  TglUniform2f = procedure(location: cint; v0, v1: cfloat); cdecl;
  TglUniform3f = procedure(location: cint; v0, v1, v2: cfloat); cdecl;
  TglUniform4f = procedure(location: cint; v0, v1, v2, v3: cfloat); cdecl;
  TglUniform4fv = procedure(location: cint; count: cint; const value: Pcfloat); cdecl;
  TglUniformMatrix3fv = procedure(location: cint; count: cint; transpose: cbool; const value: Pcfloat); cdecl;
  TglUniformMatrix4fv = procedure(location: cint; count: cint; transpose: cbool; const value: Pcfloat); cdecl;

  TglDrawArrays = procedure(mode: cuint; first: cint; count: cint); cdecl;
  TglDrawElements = procedure(mode: cuint; count: cint; type_: cuint; const indices: Pointer); cdecl;

  TglGenFramebuffers = procedure(n: cint; framebuffers: Pcuint); cdecl;
  TglBindFramebuffer = procedure(target: cuint; framebuffer: cuint); cdecl;
  TglFramebufferTexture2D = procedure(target, attachment, textarget, texture: cuint; level: cint); cdecl;
  TglCheckFramebufferStatus = function(target: cuint): cuint; cdecl;
  TglDeleteFramebuffers = procedure(n: cint; const framebuffers: Pcuint); cdecl;

  TglGenRenderbuffers = procedure(n: cint; renderbuffers: Pcuint); cdecl;
  TglBindRenderbuffer = procedure(target: cuint; renderbuffer: cuint); cdecl;
  TglRenderbufferStorage = procedure(target, internalformat: cuint; width, height: cint); cdecl;
  TglFramebufferRenderbuffer = procedure(target, attachment, renderbuffertarget, renderbuffer: cuint); cdecl;
  TglDeleteRenderbuffers = procedure(n: cint; const renderbuffers: Pcuint); cdecl;

  // ---------------------------------------------------------------------------
  // TGLEngine
  // ---------------------------------------------------------------------------
  TGLEngine = class
  private
    FLibHandle     : TLibHandle;
    FAvailable     : Boolean;
    FLibraryPath   : string;
    FIsGLES        : Boolean;

    function LoadSymbol(const AName: string): Pointer;
    procedure LoadAllSymbols();
  public
    // Function table
    Viewport               : TglViewport;
    Clear                  : TglClear;
    ClearColor             : TglClearColor;
    Enable                 : TglEnable;
    Disable                : TglDisable;
    BlendFunc              : TglBlendFunc;
    BlendFuncSeparate      : TglBlendFuncSeparate;
    BlendEquation          : TglBlendEquation;
    BlendEquationSeparate  : TglBlendEquationSeparate;
    Scissor                : TglScissor;
    GetError               : TglGetError;
    GetString              : TglGetString;
    GetIntegerv            : TglGetIntegerv;

    GenBuffers             : TglGenBuffers;
    BindBuffer             : TglBindBuffer;
    BufferData             : TglBufferData;
    BufferSubData          : TglBufferSubData;
    DeleteBuffers          : TglDeleteBuffers;

    GenTextures            : TglGenTextures;
    BindTexture            : TglBindTexture;
    TexParameteri          : TglTexParameteri;
    TexImage2D             : TglTexImage2D;
    TexSubImage2D          : TglTexSubImage2D;
    DeleteTextures         : TglDeleteTextures;
    ActiveTexture          : TglActiveTexture;
    PixelStorei            : TglPixelStorei;

    CreateShader           : TglCreateShader;
    ShaderSource           : TglShaderSource;
    CompileShader          : TglCompileShader;
    GetShaderiv            : TglGetShaderiv;
    GetShaderInfoLog       : TglGetShaderInfoLog;
    DeleteShader           : TglDeleteShader;

    CreateProgram          : TglCreateProgram;
    AttachShader           : TglAttachShader;
    LinkProgram            : TglLinkProgram;
    GetProgramiv           : TglGetProgramiv;
    GetProgramInfoLog      : TglGetProgramInfoLog;
    UseProgram             : TglUseProgram;
    DeleteProgram          : TglDeleteProgram;

    GetAttribLocation      : TglGetAttribLocation;
    GetUniformLocation     : TglGetUniformLocation;
    EnableVertexAttribArray: TglEnableVertexAttribArray;
    DisableVertexAttribArray: TglDisableVertexAttribArray;
    VertexAttribPointer    : TglVertexAttribPointer;

    Uniform1i              : TglUniform1i;
    Uniform1f              : TglUniform1f;
    Uniform2f              : TglUniform2f;
    Uniform3f              : TglUniform3f;
    Uniform4f              : TglUniform4f;
    Uniform4fv             : TglUniform4fv;
    UniformMatrix3fv       : TglUniformMatrix3fv;
    UniformMatrix4fv       : TglUniformMatrix4fv;

    DrawArrays             : TglDrawArrays;
    DrawElements           : TglDrawElements;

    GenFramebuffers        : TglGenFramebuffers;
    BindFramebuffer        : TglBindFramebuffer;
    FramebufferTexture2D   : TglFramebufferTexture2D;
    CheckFramebufferStatus : TglCheckFramebufferStatus;
    DeleteFramebuffers     : TglDeleteFramebuffers;

    GenRenderbuffers       : TglGenRenderbuffers;
    BindRenderbuffer       : TglBindRenderbuffer;
    RenderbufferStorage    : TglRenderbufferStorage;
    FramebufferRenderbuffer: TglFramebufferRenderbuffer;
    DeleteRenderbuffers    : TglDeleteRenderbuffers;

    constructor Create();
    destructor Destroy(); override;

    function Load(): Boolean;
    procedure Unload();

    // Query helpers
    function Vendor(): string;
    function Renderer(): string;
    function Version(): string;
    function Extensions(): string;

    property Available  : Boolean read FAvailable;
    property LibraryPath: string read FLibraryPath;
    property IsGLES      : Boolean read FIsGLES;
  end;

function FloriaGL(): TGLEngine;
function FloriaGLIsAvailable(): Boolean;
function FloriaGLErrorString(AErrorCode: Cardinal): string;

implementation

var
  GGLEngine: TGLEngine = nil;

function FloriaGL(): TGLEngine;
begin
  if not Assigned(GGLEngine) then
    GGLEngine := TGLEngine.Create();
  Result := GGLEngine;
end;

function FloriaGLIsAvailable(): Boolean;
begin
  Result := FloriaGL().Available;
end;

function FloriaGLErrorString(AErrorCode: Cardinal): string;
begin
  case AErrorCode of
    GL_NO_ERROR:                      Result := 'GL_NO_ERROR';
    GL_INVALID_ENUM:                  Result := 'GL_INVALID_ENUM';
    GL_INVALID_VALUE:                 Result := 'GL_INVALID_VALUE';
    GL_INVALID_OPERATION:             Result := 'GL_INVALID_OPERATION';
    GL_OUT_OF_MEMORY:                 Result := 'GL_OUT_OF_MEMORY';
    GL_INVALID_FRAMEBUFFER_OPERATION: Result := 'GL_INVALID_FRAMEBUFFER_OPERATION';
  else
    Result := Format('GL_UNKNOWN_ERROR ($%x)', [AErrorCode]);
  end;
end;

// -----------------------------------------------------------------------------
// TGLEngine Implementation
// -----------------------------------------------------------------------------
constructor TGLEngine.Create();
begin
  inherited Create();
  FLibHandle   := NilHandle;
  FAvailable   := False;
  FLibraryPath := '';
  FIsGLES      := False;
  Load();
end;

destructor TGLEngine.Destroy();
begin
  Unload();
  inherited Destroy();
end;

function TGLEngine.LoadSymbol(const AName: string): Pointer;
var
  ProcAddr: Pointer;
begin
  ProcAddr := nil;
  // 1. Try eglGetProcAddress if available
  if FloriaEGLIsAvailable() then
  begin
    try
      ProcAddr := eglGetProcAddress(PChar(AName));
    except
      ProcAddr := nil;
    end;
  end;

  // 2. Fall back to dlsym / GetProcedureAddress on library handle
  if (ProcAddr = nil) and (FLibHandle <> NilHandle) then
    ProcAddr := GetProcedureAddress(FLibHandle, AName);

  Result := ProcAddr;
end;

function TGLEngine.Load(): Boolean;
const
  CandidateLibs: array[0..3] of string = (
    'libGLESv2.so.2',
    'libGL.so.1',
    'libGLESv2.so',
    'libGL.so'
  );
var
  I: Integer;
begin
  if FAvailable then Exit(True);

  for I := Low(CandidateLibs) to High(CandidateLibs) do
  begin
    FLibHandle := LoadLibrary(CandidateLibs[I]);
    if FLibHandle <> NilHandle then
    begin
      FLibraryPath := CandidateLibs[I];
      FIsGLES := Pos('GLES', CandidateLibs[I]) > 0;
      Break;
    end;
  end;

  // Even if direct dlopen fails, eglGetProcAddress might work if EGL is loaded
  if (FLibHandle = NilHandle) and not FloriaEGLIsAvailable() then
  begin
    FAvailable := False;
    Exit(False);
  end;

  LoadAllSymbols();
  FAvailable := Assigned(Viewport) and Assigned(Clear) and Assigned(DrawArrays);
  Result := FAvailable;
end;

procedure TGLEngine.Unload();
begin
  if FLibHandle <> NilHandle then
  begin
    UnloadLibrary(FLibHandle);
    FLibHandle := NilHandle;
  end;
  FAvailable := False;
  FLibraryPath := '';
end;

procedure TGLEngine.LoadAllSymbols();
begin
  Pointer(Viewport)                := LoadSymbol('glViewport');
  Pointer(Clear)                   := LoadSymbol('glClear');
  Pointer(ClearColor)              := LoadSymbol('glClearColor');
  Pointer(Enable)                  := LoadSymbol('glEnable');
  Pointer(Disable)                 := LoadSymbol('glDisable');
  Pointer(BlendFunc)               := LoadSymbol('glBlendFunc');
  Pointer(BlendFuncSeparate)       := LoadSymbol('glBlendFuncSeparate');
  Pointer(BlendEquation)           := LoadSymbol('glBlendEquation');
  Pointer(BlendEquationSeparate)   := LoadSymbol('glBlendEquationSeparate');
  Pointer(Scissor)                 := LoadSymbol('glScissor');
  Pointer(GetError)                := LoadSymbol('glGetError');
  Pointer(GetString)               := LoadSymbol('glGetString');
  Pointer(GetIntegerv)             := LoadSymbol('glGetIntegerv');

  Pointer(GenBuffers)              := LoadSymbol('glGenBuffers');
  Pointer(BindBuffer)              := LoadSymbol('glBindBuffer');
  Pointer(BufferData)              := LoadSymbol('glBufferData');
  Pointer(BufferSubData)           := LoadSymbol('glBufferSubData');
  Pointer(DeleteBuffers)           := LoadSymbol('glDeleteBuffers');

  Pointer(GenTextures)             := LoadSymbol('glGenTextures');
  Pointer(BindTexture)             := LoadSymbol('glBindTexture');
  Pointer(TexParameteri)          := LoadSymbol('glTexParameteri');
  Pointer(TexImage2D)              := LoadSymbol('glTexImage2D');
  Pointer(TexSubImage2D)           := LoadSymbol('glTexSubImage2D');
  Pointer(DeleteTextures)          := LoadSymbol('glDeleteTextures');
  Pointer(ActiveTexture)           := LoadSymbol('glActiveTexture');
  Pointer(PixelStorei)            := LoadSymbol('glPixelStorei');

  Pointer(CreateShader)            := LoadSymbol('glCreateShader');
  Pointer(ShaderSource)            := LoadSymbol('glShaderSource');
  Pointer(CompileShader)           := LoadSymbol('glCompileShader');
  Pointer(GetShaderiv)             := LoadSymbol('glGetShaderiv');
  Pointer(GetShaderInfoLog)        := LoadSymbol('glGetShaderInfoLog');
  Pointer(DeleteShader)            := LoadSymbol('glDeleteShader');

  Pointer(CreateProgram)           := LoadSymbol('glCreateProgram');
  Pointer(AttachShader)            := LoadSymbol('glAttachShader');
  Pointer(LinkProgram)             := LoadSymbol('glLinkProgram');
  Pointer(GetProgramiv)            := LoadSymbol('glGetProgramiv');
  Pointer(GetProgramInfoLog)       := LoadSymbol('glGetProgramInfoLog');
  Pointer(UseProgram)              := LoadSymbol('glUseProgram');
  Pointer(DeleteProgram)           := LoadSymbol('glDeleteProgram');

  Pointer(GetAttribLocation)       := LoadSymbol('glGetAttribLocation');
  Pointer(GetUniformLocation)      := LoadSymbol('glGetUniformLocation');
  Pointer(EnableVertexAttribArray) := LoadSymbol('glEnableVertexAttribArray');
  Pointer(DisableVertexAttribArray):= LoadSymbol('glDisableVertexAttribArray');
  Pointer(VertexAttribPointer)     := LoadSymbol('glVertexAttribPointer');

  Pointer(Uniform1i)               := LoadSymbol('glUniform1i');
  Pointer(Uniform1f)               := LoadSymbol('glUniform1f');
  Pointer(Uniform2f)               := LoadSymbol('glUniform2f');
  Pointer(Uniform3f)               := LoadSymbol('glUniform3f');
  Pointer(Uniform4f)               := LoadSymbol('glUniform4f');
  Pointer(Uniform4fv)              := LoadSymbol('glUniform4fv');
  Pointer(UniformMatrix3fv)        := LoadSymbol('glUniformMatrix3fv');
  Pointer(UniformMatrix4fv)        := LoadSymbol('glUniformMatrix4fv');

  Pointer(DrawArrays)              := LoadSymbol('glDrawArrays');
  Pointer(DrawElements)            := LoadSymbol('glDrawElements');

  Pointer(GenFramebuffers)         := LoadSymbol('glGenFramebuffers');
  Pointer(BindFramebuffer)         := LoadSymbol('glBindFramebuffer');
  Pointer(FramebufferTexture2D)    := LoadSymbol('glFramebufferTexture2D');
  Pointer(CheckFramebufferStatus)  := LoadSymbol('glCheckFramebufferStatus');
  Pointer(DeleteFramebuffers)      := LoadSymbol('glDeleteFramebuffers');

  Pointer(GenRenderbuffers)        := LoadSymbol('glGenRenderbuffers');
  Pointer(BindRenderbuffer)        := LoadSymbol('glBindRenderbuffer');
  Pointer(RenderbufferStorage)     := LoadSymbol('glRenderbufferStorage');
  Pointer(FramebufferRenderbuffer) := LoadSymbol('glFramebufferRenderbuffer');
  Pointer(DeleteRenderbuffers)     := LoadSymbol('glDeleteRenderbuffers');
end;

function TGLEngine.Vendor(): string;
var
  P: PChar;
begin
  if Assigned(GetString) then
  begin
    P := GetString(GL_VENDOR);
    if Assigned(P) then Exit(string(P));
  end;
  Result := '';
end;

function TGLEngine.Renderer(): string;
var
  P: PChar;
begin
  if Assigned(GetString) then
  begin
    P := GetString(GL_RENDERER);
    if Assigned(P) then Exit(string(P));
  end;
  Result := '';
end;

function TGLEngine.Version(): string;
var
  P: PChar;
begin
  if Assigned(GetString) then
  begin
    P := GetString(GL_VERSION);
    if Assigned(P) then Exit(string(P));
  end;
  Result := '';
end;

function TGLEngine.Extensions(): string;
var
  P: PChar;
begin
  if Assigned(GetString) then
  begin
    P := GetString(GL_EXTENSIONS);
    if Assigned(P) then Exit(string(P));
  end;
  Result := '';
end;

finalization
  if Assigned(GGLEngine) then
    FreeAndNil(GGLEngine);

end.
