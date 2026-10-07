unit Floria.GPU.Context;

// Floria.GPU.Context
// ==================
// Cross-Platform Hardware GPU Context & Presentation Abstraction Layer.
//
// Capabilities:
// - Universal IFloriaGPUContext / TFloriaGPUContext interface: abstracts display server
//   and presentation mechanics across target platforms.
// - Native Linux X11/XCB + EGL 1.4/1.5 & OpenGL ES 2.0/3.0 implementation (TFloriaEGLContext).
// - Offscreen PBuffer creation for headless vector rasterization and unit testing.
// - Hardware VSync synchronization control (SwapInterval).
// - Clean extensible architecture for non-Linux platform bindings (Win32/WGL/ANGLE, Cocoa/CGL/Metal).

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  ctypes, Classes, SysUtils, Math,
  Floria.EGL,
  Floria.GL;

type
  // GPU Driver / Platform Backend Type
  TFloriaGPUBackendType = (
    gbeEGL,      // Linux Native X11/XCB via Khronos EGL
    gbeWGL,      // Windows Native Win32 / WGL or ANGLE
    gbeCGL,      // macOS Cocoa / CGL or MoltenVK
    gbeSoftware  // Software fallback / Mock
  );

  // ---------------------------------------------------------------------------
  // TFloriaGPUContext (Abstract Base Class)
  // ---------------------------------------------------------------------------
  TFloriaGPUContext = class
  protected
    FGL          : TGLEngine;
    FWidth       : Integer;
    FHeight      : Integer;
    FSwapInterval: Integer;
    FIsOffscreen : Boolean;
    FInitialized : Boolean;
  public
    constructor Create();
    destructor Destroy(); override;

    function MakeCurrent(): Boolean; virtual; abstract;
    procedure ReleaseCurrent(); virtual; abstract;
    function SwapBuffers(): Boolean; virtual; abstract;
    procedure SetSwapInterval(AInterval: Integer); virtual; abstract;
    procedure GetSurfaceSize(out AWidth, AHeight: Integer); virtual;
    procedure Resize(AWidth, AHeight: Integer); virtual;

    property GL          : TGLEngine read FGL;
    property Width       : Integer   read FWidth;
    property Height      : Integer   read FHeight;
    property SwapInterval: Integer   read FSwapInterval write SetSwapInterval;
    property IsOffscreen : Boolean   read FIsOffscreen;
    property Initialized : Boolean   read FInitialized;
    function BackendType(): TFloriaGPUBackendType; virtual; abstract;
    function IsCurrent(): Boolean; virtual; abstract;
  end;

  // ---------------------------------------------------------------------------
  // TFloriaEGLContext (Linux X11/XCB Native Presentation Context)
  // ---------------------------------------------------------------------------
  TFloriaEGLContext = class(TFloriaGPUContext)
  private
    FEGL         : TEGLEngine;
    FEGLDisplay  : EGLDisplay;
    FEGLConfig   : EGLConfig;
    FEGLContext  : EGLContext;
    FEGLSurface  : EGLSurface;
    FNativeDisplay: Pointer;
    FNativeWindow : PtrUInt;

    function ChooseConfig(AOffscreen: Boolean): Boolean;
    function CreateInternalContext(): Boolean;
  public
    // Constructors for Windowed Presentation and Offscreen PBuffers
    constructor CreateForWindow(ANativeDisplay: Pointer; ANativeWindow: PtrUInt;
                                AWidth, AHeight: Integer; ASwapInterval: Integer = 1);
    constructor CreateOffscreen(AWidth, AHeight: Integer);
    destructor Destroy(); override;

    function MakeCurrent(): Boolean; override;
    procedure ReleaseCurrent(); override;
    function SwapBuffers(): Boolean; override;
    procedure SetSwapInterval(AInterval: Integer); override;
    procedure GetSurfaceSize(out AWidth, AHeight: Integer); override;
    procedure Resize(AWidth, AHeight: Integer); override;

    function BackendType(): TFloriaGPUBackendType; override;
    function IsCurrent(): Boolean; override;

    // Direct access to EGL handles
    property EGL       : TEGLEngine read FEGL;
    property EGLDisplay: EGLDisplay read FEGLDisplay;
    property EGLConfig : EGLConfig  read FEGLConfig;
    property EGLContext: EGLContext read FEGLContext;
    property EGLSurface: EGLSurface read FEGLSurface;
  end;

// -----------------------------------------------------------------------------
// Global Context Factory Functions
// -----------------------------------------------------------------------------
function FloriaGPUIsBackendAvailable(ABackend: TFloriaGPUBackendType): Boolean;
function FloriaCreateGPUWindowContext(ANativeDisplay: Pointer; ANativeWindow: PtrUInt;
                                     AWidth, AHeight: Integer; ASwapInterval: Integer = 1): TFloriaGPUContext;
function FloriaCreateGPUOffscreenContext(AWidth, AHeight: Integer): TFloriaGPUContext;

implementation

// -----------------------------------------------------------------------------
// Global Factory Functions
// -----------------------------------------------------------------------------
function FloriaGPUIsBackendAvailable(ABackend: TFloriaGPUBackendType): Boolean;
begin
  case ABackend of
    gbeEGL:
      Result := FloriaEGLIsAvailable() and FloriaGLIsAvailable();
    gbeSoftware:
      Result := True;
    else
      Result := False; // WGL and CGL not supported on native Linux platform
  end;
end;

function FloriaCreateGPUWindowContext(ANativeDisplay: Pointer; ANativeWindow: PtrUInt;
                                     AWidth, AHeight: Integer; ASwapInterval: Integer): TFloriaGPUContext;
begin
  if FloriaGPUIsBackendAvailable(gbeEGL) then
    Result := TFloriaEGLContext.CreateForWindow(ANativeDisplay, ANativeWindow, AWidth, AHeight, ASwapInterval)
  else
    Result := nil;
end;

function FloriaCreateGPUOffscreenContext(AWidth, AHeight: Integer): TFloriaGPUContext;
begin
  if FloriaGPUIsBackendAvailable(gbeEGL) then
    Result := TFloriaEGLContext.CreateOffscreen(AWidth, AHeight)
  else
    Result := nil;
end;

// -----------------------------------------------------------------------------
// TFloriaGPUContext Implementation
// -----------------------------------------------------------------------------
constructor TFloriaGPUContext.Create();
begin
  inherited Create();
  FGL           := FloriaGL();
  FWidth        := 0;
  FHeight       := 0;
  FSwapInterval := 1;
  FIsOffscreen  := False;
  FInitialized  := False;
end;

destructor TFloriaGPUContext.Destroy();
begin
  inherited Destroy();
end;

procedure TFloriaGPUContext.GetSurfaceSize(out AWidth, AHeight: Integer);
begin
  AWidth  := FWidth;
  AHeight := FHeight;
end;

procedure TFloriaGPUContext.Resize(AWidth, AHeight: Integer);
begin
  FWidth  := AWidth;
  FHeight := AHeight;
end;

// -----------------------------------------------------------------------------
// TFloriaEGLContext Implementation
// -----------------------------------------------------------------------------
constructor TFloriaEGLContext.CreateForWindow(
  ANativeDisplay: Pointer; ANativeWindow: PtrUInt;
  AWidth, AHeight: Integer; ASwapInterval: Integer);
begin
  inherited Create();
  FNativeDisplay := ANativeDisplay;
  FNativeWindow  := ANativeWindow;
  FWidth         := AWidth;
  FHeight        := AHeight;
  FSwapInterval  := ASwapInterval;
  FIsOffscreen   := False;
  FEGL           := FloriaEGL();

  if not FEGL.Available then Exit;

  // Initialize EGL display
  if Assigned(FNativeDisplay) then
    FEGLDisplay := eglGetDisplay(FNativeDisplay)
  else
  begin
    if not FEGL.InitializeDefaultDisplay() then Exit;
    FEGLDisplay := FEGL.DefaultDisplay;
  end;

  if FEGLDisplay = EGL_NO_DISPLAY then Exit;

  if not ChooseConfig(False) then Exit;
  if not CreateInternalContext() then Exit;

  // Create native X11 window EGL surface
  FEGLSurface := eglCreateWindowSurface(FEGLDisplay, FEGLConfig, EGLNativeWindowType(FNativeWindow), nil);
  if FEGLSurface = EGL_NO_SURFACE then
  begin
    eglDestroyContext(FEGLDisplay, FEGLContext);
    FEGLContext := EGL_NO_CONTEXT;
    Exit;
  end;

  // Initial make current to configure swap interval
  if eglMakeCurrent(FEGLDisplay, FEGLSurface, FEGLSurface, FEGLContext) = EGL_TRUE then
  begin
    eglSwapInterval(FEGLDisplay, FSwapInterval);
    eglMakeCurrent(FEGLDisplay, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
  end;

  FInitialized := True;
end;

constructor TFloriaEGLContext.CreateOffscreen(AWidth, AHeight: Integer);
var
  SurfAttribs: array[0..4] of EGLint;
begin
  inherited Create();
  FWidth        := AWidth;
  FHeight       := AHeight;
  FSwapInterval := 0;
  FIsOffscreen  := True;
  FEGL          := FloriaEGL();

  if not FEGL.Available then Exit;
  if not FEGL.InitializeDefaultDisplay() then Exit;
  FEGLDisplay := FEGL.DefaultDisplay;

  if not ChooseConfig(True) then Exit;
  if not CreateInternalContext() then Exit;

  // Create offscreen PBuffer surface
  SurfAttribs[0] := EGL_WIDTH;
  SurfAttribs[1] := Max(1, AWidth);
  SurfAttribs[2] := EGL_HEIGHT;
  SurfAttribs[3] := Max(1, AHeight);
  SurfAttribs[4] := EGL_NONE;

  FEGLSurface := eglCreatePbufferSurface(FEGLDisplay, FEGLConfig, @SurfAttribs[0]);
  if FEGLSurface = EGL_NO_SURFACE then
  begin
    eglDestroyContext(FEGLDisplay, FEGLContext);
    FEGLContext := EGL_NO_CONTEXT;
    Exit;
  end;

  FInitialized := True;
end;

destructor TFloriaEGLContext.Destroy();
begin
  if (FEGLDisplay <> EGL_NO_DISPLAY) then
  begin
    if IsCurrent() then
      ReleaseCurrent();

    if FEGLSurface <> EGL_NO_SURFACE then
    begin
      eglDestroySurface(FEGLDisplay, FEGLSurface);
      FEGLSurface := EGL_NO_SURFACE;
    end;

    if FEGLContext <> EGL_NO_CONTEXT then
    begin
      eglDestroyContext(FEGLDisplay, FEGLContext);
      FEGLContext := EGL_NO_CONTEXT;
    end;
  end;

  inherited Destroy();
end;

function TFloriaEGLContext.ChooseConfig(AOffscreen: Boolean): Boolean;
var
  Attribs: array[0..14] of EGLint;
  NumConfigs: EGLint;
  SurfaceBit: EGLint;
begin
  Result := False;
  if FEGLDisplay = EGL_NO_DISPLAY then Exit;

  if AOffscreen then
    SurfaceBit := EGL_PBUFFER_BIT
  else
    SurfaceBit := EGL_WINDOW_BIT;

  Attribs[0]  := EGL_SURFACE_TYPE;
  Attribs[1]  := SurfaceBit;
  Attribs[2]  := EGL_RED_SIZE;
  Attribs[3]  := 8;
  Attribs[4]  := EGL_GREEN_SIZE;
  Attribs[5]  := 8;
  Attribs[6]  := EGL_BLUE_SIZE;
  Attribs[7]  := 8;
  Attribs[8]  := EGL_ALPHA_SIZE;
  Attribs[9]  := 8;
  Attribs[10] := EGL_RENDERABLE_TYPE;
  Attribs[11] := EGL_OPENGL_ES2_BIT;
  Attribs[12] := EGL_NONE;

  FEGLConfig := nil;
  NumConfigs := 0;
  if eglChooseConfig(FEGLDisplay, @Attribs[0], @FEGLConfig, 1, @NumConfigs) <> EGL_TRUE then Exit;
  Result := (NumConfigs > 0) and (FEGLConfig <> nil);
end;

function TFloriaEGLContext.CreateInternalContext(): Boolean;
var
  CtxAttribs: array[0..2] of EGLint;
begin
  Result := False;
  eglBindAPI(EGL_OPENGL_ES_API);

  CtxAttribs[0] := EGL_CONTEXT_CLIENT_VERSION;
  CtxAttribs[1] := 2; // GLES 2.0 / 3.0 compatible
  CtxAttribs[2] := EGL_NONE;

  FEGLContext := eglCreateContext(FEGLDisplay, FEGLConfig, EGL_NO_CONTEXT, @CtxAttribs[0]);
  Result := (FEGLContext <> EGL_NO_CONTEXT);
end;

function TFloriaEGLContext.MakeCurrent(): Boolean;
begin
  Result := False;
  if not FInitialized or (FEGLDisplay = EGL_NO_DISPLAY) or
     (FEGLSurface = EGL_NO_SURFACE) or (FEGLContext = EGL_NO_CONTEXT) then Exit;

  if eglGetCurrentContext() = FEGLContext then
    Exit(True);

  Result := (eglMakeCurrent(FEGLDisplay, FEGLSurface, FEGLSurface, FEGLContext) = EGL_TRUE);
end;

procedure TFloriaEGLContext.ReleaseCurrent();
begin
  if (FEGLDisplay <> EGL_NO_DISPLAY) then
    eglMakeCurrent(FEGLDisplay, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
end;

function TFloriaEGLContext.SwapBuffers(): Boolean;
begin
  Result := False;
  if not FInitialized or FIsOffscreen or
     (FEGLDisplay = EGL_NO_DISPLAY) or (FEGLSurface = EGL_NO_SURFACE) then Exit;

  Result := (eglSwapBuffers(FEGLDisplay, FEGLSurface) = EGL_TRUE);
end;

procedure TFloriaEGLContext.SetSwapInterval(AInterval: Integer);
begin
  FSwapInterval := AInterval;
  if FInitialized and not FIsOffscreen and (FEGLDisplay <> EGL_NO_DISPLAY) then
    eglSwapInterval(FEGLDisplay, FSwapInterval);
end;

procedure TFloriaEGLContext.GetSurfaceSize(out AWidth, AHeight: Integer);
var
  W, H: EGLint;
begin
  AWidth  := FWidth;
  AHeight := FHeight;
  if FInitialized and (FEGLDisplay <> EGL_NO_DISPLAY) and (FEGLSurface <> EGL_NO_SURFACE) then
  begin
    W := FWidth;
    H := FHeight;
    eglQuerySurface(FEGLDisplay, FEGLSurface, EGL_WIDTH, @W);
    eglQuerySurface(FEGLDisplay, FEGLSurface, EGL_HEIGHT, @H);
    AWidth  := W;
    AHeight := H;
  end;
end;

procedure TFloriaEGLContext.Resize(AWidth, AHeight: Integer);
begin
  FWidth  := AWidth;
  FHeight := AHeight;
  // X11 native window resize automatically updates window surface dimensions in EGL
end;

function TFloriaEGLContext.BackendType(): TFloriaGPUBackendType;
begin
  Result := gbeEGL;
end;

function TFloriaEGLContext.IsCurrent(): Boolean;
begin
  Result := FInitialized and (FEGLContext <> EGL_NO_CONTEXT) and
            (eglGetCurrentContext() = FEGLContext);
end;

end.
