unit Floria.EGL;

// Floria.EGL
// ==========
// Khronos EGL 1.4 & 1.5 bindings and dynamic loader for modern Pascal.
//
// Capabilities:
// - Dynamic loading of libEGL via dynlibs (zero hard binary dependency;
//   falls back gracefully if EGL/GPU drivers are unavailable).
// - Complete EGL 1.4/1.5 types, constants, and function pointer signatures.
// - TEGLEngine loader class with query properties (Vendor, Version, Extensions).
// - FloriaEGLErrorString helper mapping error codes to human-readable names.
// - Standard procedural wrapper functions for idiomatic, seamless C-style usage.

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, dynlibs;

const
  // Boolean values
  EGL_FALSE = 0;
  EGL_TRUE  = 1;

  // Null handles & special constants
  EGL_DEFAULT_DISPLAY = Pointer(0);
  EGL_NO_CONTEXT       = Pointer(0);
  EGL_NO_DISPLAY       = Pointer(0);
  EGL_NO_SURFACE       = Pointer(0);
  EGL_NO_IMAGE         = Pointer(0);
  EGL_NO_SYNC          = Pointer(0);
  EGL_DONT_CARE        = -1;

  // Error codes
  EGL_SUCCESS             = $3000;
  EGL_NOT_INITIALIZED     = $3001;
  EGL_BAD_ACCESS          = $3002;
  EGL_BAD_ALLOC           = $3003;
  EGL_BAD_ATTRIBUTE       = $3004;
  EGL_BAD_CONFIG          = $3005;
  EGL_BAD_CONTEXT         = $3006;
  EGL_BAD_CURRENT_SURFACE = $3007;
  EGL_BAD_DISPLAY         = $3008;
  EGL_BAD_MATCH           = $3009;
  EGL_BAD_NATIVE_PIXMAP   = $300A;
  EGL_BAD_NATIVE_WINDOW   = $300B;
  EGL_BAD_PARAMETER       = $300C;
  EGL_BAD_SURFACE         = $300D;
  EGL_CONTEXT_LOST        = $300E; // EGL 1.1

  // Config attributes
  EGL_BUFFER_SIZE             = $3020;
  EGL_ALPHA_SIZE              = $3021;
  EGL_BLUE_SIZE               = $3022;
  EGL_GREEN_SIZE              = $3023;
  EGL_RED_SIZE                = $3024;
  EGL_DEPTH_SIZE              = $3025;
  EGL_STENCIL_SIZE            = $3026;
  EGL_CONFIG_CAVEAT           = $3027;
  EGL_CONFIG_ID               = $3028;
  EGL_LEVEL                   = $3029;
  EGL_MAX_PBUFFER_HEIGHT      = $302A;
  EGL_MAX_PBUFFER_PIXELS      = $302B;
  EGL_MAX_PBUFFER_WIDTH       = $302C;
  EGL_NATIVE_RENDERABLE       = $302D;
  EGL_NATIVE_VISUAL_ID        = $302E;
  EGL_NATIVE_VISUAL_TYPE      = $302F;
  EGL_SAMPLES                 = $3031;
  EGL_SAMPLE_BUFFERS          = $3032;
  EGL_SURFACE_TYPE            = $3033;
  EGL_TRANSPARENT_TYPE        = $3034;
  EGL_TRANSPARENT_BLUE_VALUE  = $3035;
  EGL_TRANSPARENT_GREEN_VALUE = $3036;
  EGL_TRANSPARENT_RED_VALUE   = $3037;
  EGL_NONE                    = $3038;
  EGL_BIND_TO_TEXTURE_RGB     = $3039;
  EGL_BIND_TO_TEXTURE_RGBA    = $303A;
  EGL_MIN_SWAP_INTERVAL       = $303B;
  EGL_MAX_SWAP_INTERVAL       = $303C;
  EGL_LUMINANCE_SIZE          = $303D;
  EGL_ALPHA_MASK_SIZE         = $303E;
  EGL_COLOR_BUFFER_TYPE       = $303F;
  EGL_RENDERABLE_TYPE         = $3040;
  EGL_MATCH_NATIVE_PIXMAP     = $3041;
  EGL_CONFORMANT              = $3042;

  // Config caveats & buffer types
  EGL_SLOW_CONFIG             = $3050;
  EGL_NON_CONFORMANT_CONFIG   = $3051;
  EGL_TRANSPARENT_RGB         = $3052;
  EGL_RGB_BUFFER              = $308E;
  EGL_LUMINANCE_BUFFER        = $308F;

  // Surface types
  EGL_PBUFFER_BIT                 = $0001;
  EGL_PIXMAP_BIT                  = $0002;
  EGL_WINDOW_BIT                  = $0004;
  EGL_VG_COLORSPACE_LINEAR_BIT    = $0020;
  EGL_VG_ALPHA_FORMAT_PRE_BIT     = $0040;
  EGL_MULTISAMPLE_RESOLVE_BOX_BIT = $0200;
  EGL_SWAP_BEHAVIOR_PRESERVED_BIT = $0400;

  // Renderable types
  EGL_OPENGL_ES_BIT  = $0001;
  EGL_OPENVG_BIT     = $0002;
  EGL_OPENGL_ES2_BIT = $0004;
  EGL_OPENGL_BIT     = $0008;
  EGL_OPENGL_ES3_BIT = $0040;

  // QueryString targets
  EGL_VENDOR      = $3053;
  EGL_VERSION     = $3054;
  EGL_EXTENSIONS  = $3055;
  EGL_CLIENT_APIS = $308D;

  // Client APIs
  EGL_OPENGL_ES_API = $30A0;
  EGL_OPENVG_API    = $30A1;
  EGL_OPENGL_API    = $30A2;

  // Surface attributes
  EGL_HEIGHT                = $3056;
  EGL_WIDTH                 = $3057;
  EGL_LARGEST_PBUFFER       = $3058;
  EGL_DRAW                  = $3059;
  EGL_READ                  = $305A;
  EGL_TEXTURE_FORMAT        = $3080;
  EGL_TEXTURE_TARGET        = $3081;
  EGL_MIPMAP_TEXTURE        = $3082;
  EGL_MIPMAP_LEVEL          = $3083;
  EGL_BACK_BUFFER           = $3084;
  EGL_VG_COLORSPACE         = $3087;
  EGL_VG_ALPHA_FORMAT       = $3088;
  EGL_HORIZONTAL_RESOLUTION = $3090;
  EGL_VERTICAL_RESOLUTION   = $3091;
  EGL_PIXEL_ASPECT_RATIO    = $3092;
  EGL_SWAP_BEHAVIOR         = $3093;
  EGL_BUFFER_PRESERVED      = $3094;
  EGL_BUFFER_DESTROYED      = $3095;
  EGL_MULTISAMPLE_RESOLVE   = $3099;
  EGL_MULTISAMPLE_RESOLVE_DEFAULT = $309A;
  EGL_MULTISAMPLE_RESOLVE_BOX     = $309B;
  EGL_GL_COLORSPACE         = $309D;

  // Context attributes
  EGL_CONTEXT_CLIENT_VERSION          = $3098;
  EGL_CONTEXT_MAJOR_VERSION           = $3098;
  EGL_CONTEXT_MINOR_VERSION           = $30FB;
  EGL_CONTEXT_OPENGL_PROFILE_MASK     = $30FD;
  EGL_CONTEXT_OPENGL_CORE_PROFILE_BIT = $00000001;
  EGL_CONTEXT_OPENGL_COMPATIBILITY_PROFILE_BIT = $00000002;
  EGL_CONTEXT_OPENGL_DEBUG_BIT        = $00000001;
  EGL_CONTEXT_OPENGL_FORWARD_COMPATIBLE_BIT = $00000002;
  EGL_CONTEXT_OPENGL_ROBUST_ACCESS_BIT = $00000004;

  // Platform extensions (EGL 1.5 & EGL_EXT_platform_base)
  EGL_PLATFORM_X11_KHR        = $31D5;
  EGL_PLATFORM_X11_SCREEN_KHR = $31D6;
  EGL_PLATFORM_GBM_KHR        = $31D7;

  // Sync objects
  EGL_SYNC_FENCE              = $30F9;
  EGL_SYNC_TYPE               = $30F7;
  EGL_SYNC_STATUS             = $30F6;
  EGL_SYNC_CONDITION          = $30F8;
  EGL_SIGNALED                = $30F2;
  EGL_UNSIGNALED              = $30F3;
  EGL_TIMEOUT_EXPIRED         = $30F5;
  EGL_CONDITION_SATISFIED     = $30F6;
  EGL_FOREVER                 = High(QWord);

type
  // Standard EGL Types
  EGLint          = LongInt;
  PEGLint         = ^EGLint;
  EGLBoolean      = Cardinal;
  PEGLBoolean     = ^EGLBoolean;
  EGLenum         = Cardinal;
  PEGLenum        = ^EGLenum;
  EGLDisplay      = Pointer;
  PEGLDisplay     = ^EGLDisplay;
  EGLConfig       = Pointer;
  PEGLConfig      = ^EGLConfig;
  EGLContext      = Pointer;
  PEGLContext     = ^EGLContext;
  EGLSurface      = Pointer;
  PEGLSurface     = ^EGLSurface;
  EGLClientBuffer = Pointer;
  EGLImage        = Pointer;
  EGLSync         = Pointer;
  EGLAttrib       = PtrInt;
  PEGLAttrib      = ^EGLAttrib;
  EGLTime         = QWord;

  // Native platform types (Linux X11 defaults)
  EGLNativeDisplayType = Pointer;
  EGLNativeWindowType  = PtrUInt;
  EGLNativePixmapType  = PtrUInt;

  // Function pointer signatures for EGL 1.4 & 1.5
  TeglGetError = function(): EGLint; cdecl;
  TeglGetDisplay = function(display_id: EGLNativeDisplayType): EGLDisplay; cdecl;
  TeglInitialize = function(dpy: EGLDisplay; major: PEGLint; minor: PEGLint): EGLBoolean; cdecl;
  TeglTerminate = function(dpy: EGLDisplay): EGLBoolean; cdecl;
  TeglQueryString = function(dpy: EGLDisplay; name: EGLint): PChar; cdecl;
  TeglGetConfigs = function(dpy: EGLDisplay; configs: PEGLConfig; config_size: EGLint; num_config: PEGLint): EGLBoolean; cdecl;
  TeglChooseConfig = function(dpy: EGLDisplay; attrib_list: PEGLint; configs: PEGLConfig; config_size: EGLint; num_config: PEGLint): EGLBoolean; cdecl;
  TeglGetConfigAttrib = function(dpy: EGLDisplay; config: EGLConfig; attribute: EGLint; value: PEGLint): EGLBoolean; cdecl;
  TeglCreateWindowSurface = function(dpy: EGLDisplay; config: EGLConfig; win: EGLNativeWindowType; attrib_list: PEGLint): EGLSurface; cdecl;
  TeglCreatePbufferSurface = function(dpy: EGLDisplay; config: EGLConfig; attrib_list: PEGLint): EGLSurface; cdecl;
  TeglCreatePixmapSurface = function(dpy: EGLDisplay; config: EGLConfig; pixmap: EGLNativePixmapType; attrib_list: PEGLint): EGLSurface; cdecl;
  TeglDestroySurface = function(dpy: EGLDisplay; surface: EGLSurface): EGLBoolean; cdecl;
  TeglQuerySurface = function(dpy: EGLDisplay; surface: EGLSurface; attribute: EGLint; value: PEGLint): EGLBoolean; cdecl;
  TeglBindAPI = function(api: EGLenum): EGLBoolean; cdecl;
  TeglQueryAPI = function(): EGLenum; cdecl;
  TeglWaitClient = function(): EGLBoolean; cdecl;
  TeglReleaseThread = function(): EGLBoolean; cdecl;
  TeglCreatePbufferFromClientBuffer = function(dpy: EGLDisplay; buftype: EGLenum; buffer: EGLClientBuffer; config: EGLConfig; attrib_list: PEGLint): EGLSurface; cdecl;
  TeglSurfaceAttrib = function(dpy: EGLDisplay; surface: EGLSurface; attribute: EGLint; value: EGLint): EGLBoolean; cdecl;
  TeglBindTexImage = function(dpy: EGLDisplay; surface: EGLSurface; buffer: EGLint): EGLBoolean; cdecl;
  TeglReleaseTexImage = function(dpy: EGLDisplay; surface: EGLSurface; buffer: EGLint): EGLBoolean; cdecl;
  TeglSwapInterval = function(dpy: EGLDisplay; interval: EGLint): EGLBoolean; cdecl;
  TeglCreateContext = function(dpy: EGLDisplay; config: EGLConfig; share_context: EGLContext; attrib_list: PEGLint): EGLContext; cdecl;
  TeglDestroyContext = function(dpy: EGLDisplay; ctx: EGLContext): EGLBoolean; cdecl;
  TeglMakeCurrent = function(dpy: EGLDisplay; draw: EGLSurface; read: EGLSurface; ctx: EGLContext): EGLBoolean; cdecl;
  TeglGetCurrentContext = function(): EGLContext; cdecl;
  TeglGetCurrentSurface = function(readdraw: EGLint): EGLSurface; cdecl;
  TeglGetCurrentDisplay = function(): EGLDisplay; cdecl;
  TeglQueryContext = function(dpy: EGLDisplay; ctx: EGLContext; attribute: EGLint; value: PEGLint): EGLBoolean; cdecl;
  TeglWaitGL = function(): EGLBoolean; cdecl;
  TeglWaitNative = function(engine: EGLint): EGLBoolean; cdecl;
  TeglSwapBuffers = function(dpy: EGLDisplay; surface: EGLSurface): EGLBoolean; cdecl;
  TeglCopyBuffers = function(dpy: EGLDisplay; surface: EGLSurface; target: EGLNativePixmapType): EGLBoolean; cdecl;
  TeglGetProcAddress = function(procname: PChar): Pointer; cdecl;

  // EGL 1.5 / Modern additions
  TeglGetPlatformDisplay = function(platform: EGLenum; native_display: Pointer; attrib_list: PEGLAttrib): EGLDisplay; cdecl;
  TeglCreatePlatformWindowSurface = function(dpy: EGLDisplay; config: EGLConfig; native_window: Pointer; attrib_list: PEGLAttrib): EGLSurface; cdecl;
  TeglCreatePlatformPixmapSurface = function(dpy: EGLDisplay; config: EGLConfig; native_pixmap: Pointer; attrib_list: PEGLAttrib): EGLSurface; cdecl;
  TeglCreateSync = function(dpy: EGLDisplay; type_: EGLenum; attrib_list: PEGLAttrib): EGLSync; cdecl;
  TeglDestroySync = function(dpy: EGLDisplay; sync: EGLSync): EGLBoolean; cdecl;
  TeglClientWaitSync = function(dpy: EGLDisplay; sync: EGLSync; flags: EGLint; timeout: EGLTime): EGLint; cdecl;
  TeglGetSyncAttrib = function(dpy: EGLDisplay; sync: EGLSync; attribute: EGLint; value: PEGLAttrib): EGLBoolean; cdecl;
  TeglCreateImage = function(dpy: EGLDisplay; ctx: EGLContext; target: EGLenum; buffer: EGLClientBuffer; attrib_list: PEGLAttrib): EGLImage; cdecl;
  TeglDestroyImage = function(dpy: EGLDisplay; image: EGLImage): EGLBoolean; cdecl;

  // TEGLEngine: Dynamic library loader and runtime manager
  TEGLEngine = class
  private
    FLibHandle   : TLibHandle;
    FAvailable   : Boolean;
    FLibPath     : string;
    FVersionMajor: Integer;
    FVersionMinor: Integer;
    FVendor      : string;
    FVersion     : string;
    FExtensions  : string;
    FClientAPIs  : string;
    FDefaultDpy  : EGLDisplay;
    FInitialized : Boolean;
    procedure LoadSymbols();
  public
    // EGL 1.4 Function pointers
    eglGetError             : TeglGetError;
    eglGetDisplay           : TeglGetDisplay;
    eglInitialize          : TeglInitialize;
    eglTerminate            : TeglTerminate;
    eglQueryString          : TeglQueryString;
    eglGetConfigs           : TeglGetConfigs;
    eglChooseConfig         : TeglChooseConfig;
    eglGetConfigAttrib      : TeglGetConfigAttrib;
    eglCreateWindowSurface  : TeglCreateWindowSurface;
    eglCreatePbufferSurface : TeglCreatePbufferSurface;
    eglCreatePixmapSurface  : TeglCreatePixmapSurface;
    eglDestroySurface       : TeglDestroySurface;
    eglQuerySurface         : TeglQuerySurface;
    eglBindAPI              : TeglBindAPI;
    eglQueryAPI             : TeglQueryAPI;
    eglWaitClient           : TeglWaitClient;
    eglReleaseThread        : TeglReleaseThread;
    eglCreatePbufferFromClientBuffer: TeglCreatePbufferFromClientBuffer;
    eglSurfaceAttrib        : TeglSurfaceAttrib;
    eglBindTexImage         : TeglBindTexImage;
    eglReleaseTexImage      : TeglReleaseTexImage;
    eglSwapInterval         : TeglSwapInterval;
    eglCreateContext        : TeglCreateContext;
    eglDestroyContext       : TeglDestroyContext;
    eglMakeCurrent          : TeglMakeCurrent;
    eglGetCurrentContext    : TeglGetCurrentContext;
    eglGetCurrentSurface    : TeglGetCurrentSurface;
    eglGetCurrentDisplay    : TeglGetCurrentDisplay;
    eglQueryContext         : TeglQueryContext;
    eglWaitGL               : TeglWaitGL;
    eglWaitNative           : TeglWaitNative;
    eglSwapBuffers          : TeglSwapBuffers;
    eglCopyBuffers          : TeglCopyBuffers;
    eglGetProcAddress       : TeglGetProcAddress;

    // EGL 1.5 Function pointers (optional/nil if on older driver)
    eglGetPlatformDisplay          : TeglGetPlatformDisplay;
    eglCreatePlatformWindowSurface  : TeglCreatePlatformWindowSurface;
    eglCreatePlatformPixmapSurface  : TeglCreatePlatformPixmapSurface;
    eglCreateSync                  : TeglCreateSync;
    eglDestroySync                 : TeglDestroySync;
    eglClientWaitSync              : TeglClientWaitSync;
    eglGetSyncAttrib               : TeglGetSyncAttrib;
    eglCreateImage                 : TeglCreateImage;
    eglDestroyImage                : TeglDestroyImage;

    constructor Create();
    destructor Destroy(); override;

    // Initialize and query default display
    function InitializeDefaultDisplay(): Boolean;
    function GetProc(const AProcName: string): Pointer;

    property Available   : Boolean    read FAvailable;
    property LibraryPath : string     read FLibPath;
    property VersionMajor: Integer    read FVersionMajor;
    property VersionMinor: Integer    read FVersionMinor;
    property Vendor      : string     read FVendor;
    property Version     : string     read FVersion;
    property Extensions  : string     read FExtensions;
    property ClientAPIs  : string     read FClientAPIs;
    property DefaultDisplay: EGLDisplay read FDefaultDpy;
    property IsInitialized: Boolean   read FInitialized;
  end;

// Singleton accessor
function FloriaEGL(): TEGLEngine;
function FloriaEGLIsAvailable(): Boolean;

// Error code to string helper
function FloriaEGLErrorString(AError: EGLint): string;

// Standard C-style procedural wrappers (forwarding to FloriaEGL)
function eglGetError(): EGLint;
function eglGetDisplay(display_id: EGLNativeDisplayType): EGLDisplay;
function eglInitialize(dpy: EGLDisplay; major: PEGLint; minor: PEGLint): EGLBoolean;
function eglTerminate(dpy: EGLDisplay): EGLBoolean;
function eglQueryString(dpy: EGLDisplay; name: EGLint): PChar;
function eglGetConfigs(dpy: EGLDisplay; configs: PEGLConfig; config_size: EGLint; num_config: PEGLint): EGLBoolean;
function eglChooseConfig(dpy: EGLDisplay; attrib_list: PEGLint; configs: PEGLConfig; config_size: EGLint; num_config: PEGLint): EGLBoolean;
function eglGetConfigAttrib(dpy: EGLDisplay; config: EGLConfig; attribute: EGLint; value: PEGLint): EGLBoolean;
function eglCreateWindowSurface(dpy: EGLDisplay; config: EGLConfig; win: EGLNativeWindowType; attrib_list: PEGLint): EGLSurface;
function eglCreatePbufferSurface(dpy: EGLDisplay; config: EGLConfig; attrib_list: PEGLint): EGLSurface;
function eglCreatePixmapSurface(dpy: EGLDisplay; config: EGLConfig; pixmap: EGLNativePixmapType; attrib_list: PEGLint): EGLSurface;
function eglDestroySurface(dpy: EGLDisplay; surface: EGLSurface): EGLBoolean;
function eglQuerySurface(dpy: EGLDisplay; surface: EGLSurface; attribute: EGLint; value: PEGLint): EGLBoolean;
function eglBindAPI(api: EGLenum): EGLBoolean;
function eglQueryAPI(): EGLenum;
function eglWaitClient(): EGLBoolean;
function eglReleaseThread(): EGLBoolean;
function eglCreatePbufferFromClientBuffer(dpy: EGLDisplay; buftype: EGLenum; buffer: EGLClientBuffer; config: EGLConfig; attrib_list: PEGLint): EGLSurface;
function eglSurfaceAttrib(dpy: EGLDisplay; surface: EGLSurface; attribute: EGLint; value: EGLint): EGLBoolean;
function eglBindTexImage(dpy: EGLDisplay; surface: EGLSurface; buffer: EGLint): EGLBoolean;
function eglReleaseTexImage(dpy: EGLDisplay; surface: EGLSurface; buffer: EGLint): EGLBoolean;
function eglSwapInterval(dpy: EGLDisplay; interval: EGLint): EGLBoolean;
function eglCreateContext(dpy: EGLDisplay; config: EGLConfig; share_context: EGLContext; attrib_list: PEGLint): EGLContext;
function eglDestroyContext(dpy: EGLDisplay; ctx: EGLContext): EGLBoolean;
function eglMakeCurrent(dpy: EGLDisplay; draw: EGLSurface; read: EGLSurface; ctx: EGLContext): EGLBoolean;
function eglGetCurrentContext(): EGLContext;
function eglGetCurrentSurface(readdraw: EGLint): EGLSurface;
function eglGetCurrentDisplay(): EGLDisplay;
function eglQueryContext(dpy: EGLDisplay; ctx: EGLContext; attribute: EGLint; value: PEGLint): EGLBoolean;
function eglWaitGL(): EGLBoolean;
function eglWaitNative(engine: EGLint): EGLBoolean;
function eglSwapBuffers(dpy: EGLDisplay; surface: EGLSurface): EGLBoolean;
function eglCopyBuffers(dpy: EGLDisplay; surface: EGLSurface; target: EGLNativePixmapType): EGLBoolean;
function eglGetProcAddress(procname: PChar): Pointer;

// EGL 1.5 / Platform Wrappers
function eglGetPlatformDisplay(platform: EGLenum; native_display: Pointer; attrib_list: PEGLAttrib): EGLDisplay;
function eglCreatePlatformWindowSurface(dpy: EGLDisplay; config: EGLConfig; native_window: Pointer; attrib_list: PEGLAttrib): EGLSurface;
function eglCreatePlatformPixmapSurface(dpy: EGLDisplay; config: EGLConfig; native_pixmap: Pointer; attrib_list: PEGLAttrib): EGLSurface;
function eglCreateSync(dpy: EGLDisplay; type_: EGLenum; attrib_list: PEGLAttrib): EGLSync;
function eglDestroySync(dpy: EGLDisplay; sync: EGLSync): EGLBoolean;
function eglClientWaitSync(dpy: EGLDisplay; sync: EGLSync; flags: EGLint; timeout: EGLTime): EGLint;
function eglGetSyncAttrib(dpy: EGLDisplay; sync: EGLSync; attribute: EGLint; value: PEGLAttrib): EGLBoolean;
function eglCreateImage(dpy: EGLDisplay; ctx: EGLContext; target: EGLenum; buffer: EGLClientBuffer; attrib_list: PEGLAttrib): EGLImage;
function eglDestroyImage(dpy: EGLDisplay; image: EGLImage): EGLBoolean;

implementation

var
  gEGLInstance: TEGLEngine = nil;

function FloriaEGL(): TEGLEngine;
begin
  if not Assigned(gEGLInstance) then
    gEGLInstance := TEGLEngine.Create();
  Result := gEGLInstance;
end;

function FloriaEGLIsAvailable(): Boolean;
begin
  Result := FloriaEGL().Available;
end;

function FloriaEGLErrorString(AError: EGLint): string;
begin
  case AError of
    EGL_SUCCESS:             Result := 'EGL_SUCCESS';
    EGL_NOT_INITIALIZED:     Result := 'EGL_NOT_INITIALIZED';
    EGL_BAD_ACCESS:          Result := 'EGL_BAD_ACCESS';
    EGL_BAD_ALLOC:           Result := 'EGL_BAD_ALLOC';
    EGL_BAD_ATTRIBUTE:       Result := 'EGL_BAD_ATTRIBUTE';
    EGL_BAD_CONFIG:          Result := 'EGL_BAD_CONFIG';
    EGL_BAD_CONTEXT:         Result := 'EGL_BAD_CONTEXT';
    EGL_BAD_CURRENT_SURFACE: Result := 'EGL_BAD_CURRENT_SURFACE';
    EGL_BAD_DISPLAY:         Result := 'EGL_BAD_DISPLAY';
    EGL_BAD_MATCH:           Result := 'EGL_BAD_MATCH';
    EGL_BAD_NATIVE_PIXMAP:   Result := 'EGL_BAD_NATIVE_PIXMAP';
    EGL_BAD_NATIVE_WINDOW:   Result := 'EGL_BAD_NATIVE_WINDOW';
    EGL_BAD_PARAMETER:       Result := 'EGL_BAD_PARAMETER';
    EGL_BAD_SURFACE:         Result := 'EGL_BAD_SURFACE';
    EGL_CONTEXT_LOST:        Result := 'EGL_CONTEXT_LOST';
  else
    Result := 'EGL_UNKNOWN_ERROR_$' + IntToHex(AError, 4);
  end;
end;

// ============================================================================
// TEGLEngine Implementation
// ============================================================================

constructor TEGLEngine.Create();
const
  LIB_CANDIDATES: array[0..3] of string = (
    'libEGL.so.1',
    'libEGL.so',
    'libEGL.dylib',
    'libEGL.dll'
  );
var
  I: Integer;
begin
  inherited Create();
  FLibHandle    := NilHandle;
  FAvailable    := False;
  FLibPath      := '';
  FVersionMajor := 0;
  FVersionMinor := 0;
  FVendor       := '';
  FVersion      := '';
  FExtensions   := '';
  FClientAPIs   := '';
  FDefaultDpy   := EGL_NO_DISPLAY;
  FInitialized  := False;

  for I := Low(LIB_CANDIDATES) to High(LIB_CANDIDATES) do
  begin
    FLibHandle := SafeLoadLibrary(LIB_CANDIDATES[I]);
    if FLibHandle <> NilHandle then
    begin
      FLibPath := LIB_CANDIDATES[I];
      Break;
    end;
  end;

  if FLibHandle <> NilHandle then
    LoadSymbols();
end;

destructor TEGLEngine.Destroy();
begin
  if FInitialized and Assigned(eglTerminate) and (FDefaultDpy <> EGL_NO_DISPLAY) then
  begin
    eglTerminate(FDefaultDpy);
    FDefaultDpy := EGL_NO_DISPLAY;
    FInitialized := False;
  end;

  if FLibHandle <> NilHandle then
  begin
    UnloadLibrary(FLibHandle);
    FLibHandle := NilHandle;
  end;
  inherited Destroy();
end;

procedure TEGLEngine.LoadSymbols();
begin
  // EGL 1.4 core procedures
  eglGetError             := TeglGetError(GetProcAddress(FLibHandle, 'eglGetError'));
  eglGetDisplay           := TeglGetDisplay(GetProcAddress(FLibHandle, 'eglGetDisplay'));
  eglInitialize          := TeglInitialize(GetProcAddress(FLibHandle, 'eglInitialize'));
  eglTerminate            := TeglTerminate(GetProcAddress(FLibHandle, 'eglTerminate'));
  eglQueryString          := TeglQueryString(GetProcAddress(FLibHandle, 'eglQueryString'));
  eglGetConfigs           := TeglGetConfigs(GetProcAddress(FLibHandle, 'eglGetConfigs'));
  eglChooseConfig         := TeglChooseConfig(GetProcAddress(FLibHandle, 'eglChooseConfig'));
  eglGetConfigAttrib      := TeglGetConfigAttrib(GetProcAddress(FLibHandle, 'eglGetConfigAttrib'));
  eglCreateWindowSurface  := TeglCreateWindowSurface(GetProcAddress(FLibHandle, 'eglCreateWindowSurface'));
  eglCreatePbufferSurface := TeglCreatePbufferSurface(GetProcAddress(FLibHandle, 'eglCreatePbufferSurface'));
  eglCreatePixmapSurface  := TeglCreatePixmapSurface(GetProcAddress(FLibHandle, 'eglCreatePixmapSurface'));
  eglDestroySurface       := TeglDestroySurface(GetProcAddress(FLibHandle, 'eglDestroySurface'));
  eglQuerySurface         := TeglQuerySurface(GetProcAddress(FLibHandle, 'eglQuerySurface'));
  eglBindAPI              := TeglBindAPI(GetProcAddress(FLibHandle, 'eglBindAPI'));
  eglQueryAPI             := TeglQueryAPI(GetProcAddress(FLibHandle, 'eglQueryAPI'));
  eglWaitClient           := TeglWaitClient(GetProcAddress(FLibHandle, 'eglWaitClient'));
  eglReleaseThread        := TeglReleaseThread(GetProcAddress(FLibHandle, 'eglReleaseThread'));
  eglCreatePbufferFromClientBuffer := TeglCreatePbufferFromClientBuffer(GetProcAddress(FLibHandle, 'eglCreatePbufferFromClientBuffer'));
  eglSurfaceAttrib        := TeglSurfaceAttrib(GetProcAddress(FLibHandle, 'eglSurfaceAttrib'));
  eglBindTexImage         := TeglBindTexImage(GetProcAddress(FLibHandle, 'eglBindTexImage'));
  eglReleaseTexImage      := TeglReleaseTexImage(GetProcAddress(FLibHandle, 'eglReleaseTexImage'));
  eglSwapInterval         := TeglSwapInterval(GetProcAddress(FLibHandle, 'eglSwapInterval'));
  eglCreateContext        := TeglCreateContext(GetProcAddress(FLibHandle, 'eglCreateContext'));
  eglDestroyContext       := TeglDestroyContext(GetProcAddress(FLibHandle, 'eglDestroyContext'));
  eglMakeCurrent          := TeglMakeCurrent(GetProcAddress(FLibHandle, 'eglMakeCurrent'));
  eglGetCurrentContext    := TeglGetCurrentContext(GetProcAddress(FLibHandle, 'eglGetCurrentContext'));
  eglGetCurrentSurface    := TeglGetCurrentSurface(GetProcAddress(FLibHandle, 'eglGetCurrentSurface'));
  eglGetCurrentDisplay    := TeglGetCurrentDisplay(GetProcAddress(FLibHandle, 'eglGetCurrentDisplay'));
  eglQueryContext         := TeglQueryContext(GetProcAddress(FLibHandle, 'eglQueryContext'));
  eglWaitGL               := TeglWaitGL(GetProcAddress(FLibHandle, 'eglWaitGL'));
  eglWaitNative           := TeglWaitNative(GetProcAddress(FLibHandle, 'eglWaitNative'));
  eglSwapBuffers          := TeglSwapBuffers(GetProcAddress(FLibHandle, 'eglSwapBuffers'));
  eglCopyBuffers          := TeglCopyBuffers(GetProcAddress(FLibHandle, 'eglCopyBuffers'));
  eglGetProcAddress       := TeglGetProcAddress(GetProcAddress(FLibHandle, 'eglGetProcAddress'));

  // EGL 1.5 additions
  eglGetPlatformDisplay         := TeglGetPlatformDisplay(GetProcAddress(FLibHandle, 'eglGetPlatformDisplay'));
  eglCreatePlatformWindowSurface := TeglCreatePlatformWindowSurface(GetProcAddress(FLibHandle, 'eglCreatePlatformWindowSurface'));
  eglCreatePlatformPixmapSurface := TeglCreatePlatformPixmapSurface(GetProcAddress(FLibHandle, 'eglCreatePlatformPixmapSurface'));
  eglCreateSync                 := TeglCreateSync(GetProcAddress(FLibHandle, 'eglCreateSync'));
  eglDestroySync                := TeglDestroySync(GetProcAddress(FLibHandle, 'eglDestroySync'));
  eglClientWaitSync             := TeglClientWaitSync(GetProcAddress(FLibHandle, 'eglClientWaitSync'));
  eglGetSyncAttrib              := TeglGetSyncAttrib(GetProcAddress(FLibHandle, 'eglGetSyncAttrib'));
  eglCreateImage                := TeglCreateImage(GetProcAddress(FLibHandle, 'eglCreateImage'));
  eglDestroyImage               := TeglDestroyImage(GetProcAddress(FLibHandle, 'eglDestroyImage'));

  // Essential functions for EGL to be considered available
  FAvailable := Assigned(eglGetDisplay) and
                Assigned(eglInitialize) and
                Assigned(eglTerminate) and
                Assigned(eglChooseConfig) and
                Assigned(eglCreateContext) and
                Assigned(eglDestroyContext) and
                Assigned(eglCreateWindowSurface) and
                Assigned(eglDestroySurface) and
                Assigned(eglMakeCurrent) and
                Assigned(eglSwapBuffers);
end;

function TEGLEngine.InitializeDefaultDisplay(): Boolean;
var
  Major, Minor: EGLint;
  P: PChar;
begin
  if FInitialized then
    Exit(True);

  if not FAvailable then
    Exit(False);

  FDefaultDpy := eglGetDisplay(EGL_DEFAULT_DISPLAY);
  if FDefaultDpy = EGL_NO_DISPLAY then
    Exit(False);

  Major := 0;
  Minor := 0;
  if eglInitialize(FDefaultDpy, @Major, @Minor) = EGL_FALSE then
  begin
    FDefaultDpy := EGL_NO_DISPLAY;
    Exit(False);
  end;

  FVersionMajor := Major;
  FVersionMinor := Minor;
  FInitialized  := True;

  P := eglQueryString(FDefaultDpy, EGL_VENDOR);
  if Assigned(P) then FVendor := StrPas(P);

  P := eglQueryString(FDefaultDpy, EGL_VERSION);
  if Assigned(P) then FVersion := StrPas(P);

  P := eglQueryString(FDefaultDpy, EGL_EXTENSIONS);
  if Assigned(P) then FExtensions := StrPas(P);

  P := eglQueryString(FDefaultDpy, EGL_CLIENT_APIS);
  if Assigned(P) then FClientAPIs := StrPas(P);

  Result := True;
end;

function TEGLEngine.GetProc(const AProcName: string): Pointer;
begin
  Result := nil;
  if Assigned(eglGetProcAddress) then
    Result := eglGetProcAddress(PChar(AProcName));
  if (Result = nil) and (FLibHandle <> NilHandle) then
    Result := GetProcAddress(FLibHandle, PChar(AProcName));
end;

// ============================================================================
// Procedural wrappers
// ============================================================================

function eglGetError(): EGLint;
begin
  if Assigned(FloriaEGL().eglGetError) then
    Result := FloriaEGL().eglGetError()
  else
    Result := EGL_NOT_INITIALIZED;
end;

function eglGetDisplay(display_id: EGLNativeDisplayType): EGLDisplay;
begin
  if Assigned(FloriaEGL().eglGetDisplay) then
    Result := FloriaEGL().eglGetDisplay(display_id)
  else
    Result := EGL_NO_DISPLAY;
end;

function eglInitialize(dpy: EGLDisplay; major: PEGLint; minor: PEGLint): EGLBoolean;
begin
  if Assigned(FloriaEGL().eglInitialize) then
    Result := FloriaEGL().eglInitialize(dpy, major, minor)
  else
    Result := EGL_FALSE;
end;

function eglTerminate(dpy: EGLDisplay): EGLBoolean;
begin
  if Assigned(FloriaEGL().eglTerminate) then
    Result := FloriaEGL().eglTerminate(dpy)
  else
    Result := EGL_FALSE;
end;

function eglQueryString(dpy: EGLDisplay; name: EGLint): PChar;
begin
  if Assigned(FloriaEGL().eglQueryString) then
    Result := FloriaEGL().eglQueryString(dpy, name)
  else
    Result := nil;
end;

function eglGetConfigs(dpy: EGLDisplay; configs: PEGLConfig; config_size: EGLint; num_config: PEGLint): EGLBoolean;
begin
  if Assigned(FloriaEGL().eglGetConfigs) then
    Result := FloriaEGL().eglGetConfigs(dpy, configs, config_size, num_config)
  else
    Result := EGL_FALSE;
end;

function eglChooseConfig(dpy: EGLDisplay; attrib_list: PEGLint; configs: PEGLConfig; config_size: EGLint; num_config: PEGLint): EGLBoolean;
begin
  if Assigned(FloriaEGL().eglChooseConfig) then
    Result := FloriaEGL().eglChooseConfig(dpy, attrib_list, configs, config_size, num_config)
  else
    Result := EGL_FALSE;
end;

function eglGetConfigAttrib(dpy: EGLDisplay; config: EGLConfig; attribute: EGLint; value: PEGLint): EGLBoolean;
begin
  if Assigned(FloriaEGL().eglGetConfigAttrib) then
    Result := FloriaEGL().eglGetConfigAttrib(dpy, config, attribute, value)
  else
    Result := EGL_FALSE;
end;

function eglCreateWindowSurface(dpy: EGLDisplay; config: EGLConfig; win: EGLNativeWindowType; attrib_list: PEGLint): EGLSurface;
begin
  if Assigned(FloriaEGL().eglCreateWindowSurface) then
    Result := FloriaEGL().eglCreateWindowSurface(dpy, config, win, attrib_list)
  else
    Result := EGL_NO_SURFACE;
end;

function eglCreatePbufferSurface(dpy: EGLDisplay; config: EGLConfig; attrib_list: PEGLint): EGLSurface;
begin
  if Assigned(FloriaEGL().eglCreatePbufferSurface) then
    Result := FloriaEGL().eglCreatePbufferSurface(dpy, config, attrib_list)
  else
    Result := EGL_NO_SURFACE;
end;

function eglCreatePixmapSurface(dpy: EGLDisplay; config: EGLConfig; pixmap: EGLNativePixmapType; attrib_list: PEGLint): EGLSurface;
begin
  if Assigned(FloriaEGL().eglCreatePixmapSurface) then
    Result := FloriaEGL().eglCreatePixmapSurface(dpy, config, pixmap, attrib_list)
  else
    Result := EGL_NO_SURFACE;
end;

function eglDestroySurface(dpy: EGLDisplay; surface: EGLSurface): EGLBoolean;
begin
  if Assigned(FloriaEGL().eglDestroySurface) then
    Result := FloriaEGL().eglDestroySurface(dpy, surface)
  else
    Result := EGL_FALSE;
end;

function eglQuerySurface(dpy: EGLDisplay; surface: EGLSurface; attribute: EGLint; value: PEGLint): EGLBoolean;
begin
  if Assigned(FloriaEGL().eglQuerySurface) then
    Result := FloriaEGL().eglQuerySurface(dpy, surface, attribute, value)
  else
    Result := EGL_FALSE;
end;

function eglBindAPI(api: EGLenum): EGLBoolean;
begin
  if Assigned(FloriaEGL().eglBindAPI) then
    Result := FloriaEGL().eglBindAPI(api)
  else
    Result := EGL_FALSE;
end;

function eglQueryAPI(): EGLenum;
begin
  if Assigned(FloriaEGL().eglQueryAPI) then
    Result := FloriaEGL().eglQueryAPI()
  else
    Result := EGL_NONE;
end;

function eglWaitClient(): EGLBoolean;
begin
  if Assigned(FloriaEGL().eglWaitClient) then
    Result := FloriaEGL().eglWaitClient()
  else
    Result := EGL_FALSE;
end;

function eglReleaseThread(): EGLBoolean;
begin
  if Assigned(FloriaEGL().eglReleaseThread) then
    Result := FloriaEGL().eglReleaseThread()
  else
    Result := EGL_FALSE;
end;

function eglCreatePbufferFromClientBuffer(dpy: EGLDisplay; buftype: EGLenum; buffer: EGLClientBuffer; config: EGLConfig; attrib_list: PEGLint): EGLSurface;
begin
  if Assigned(FloriaEGL().eglCreatePbufferFromClientBuffer) then
    Result := FloriaEGL().eglCreatePbufferFromClientBuffer(dpy, buftype, buffer, config, attrib_list)
  else
    Result := EGL_NO_SURFACE;
end;

function eglSurfaceAttrib(dpy: EGLDisplay; surface: EGLSurface; attribute: EGLint; value: EGLint): EGLBoolean;
begin
  if Assigned(FloriaEGL().eglSurfaceAttrib) then
    Result := FloriaEGL().eglSurfaceAttrib(dpy, surface, attribute, value)
  else
    Result := EGL_FALSE;
end;

function eglBindTexImage(dpy: EGLDisplay; surface: EGLSurface; buffer: EGLint): EGLBoolean;
begin
  if Assigned(FloriaEGL().eglBindTexImage) then
    Result := FloriaEGL().eglBindTexImage(dpy, surface, buffer)
  else
    Result := EGL_FALSE;
end;

function eglReleaseTexImage(dpy: EGLDisplay; surface: EGLSurface; buffer: EGLint): EGLBoolean;
begin
  if Assigned(FloriaEGL().eglReleaseTexImage) then
    Result := FloriaEGL().eglReleaseTexImage(dpy, surface, buffer)
  else
    Result := EGL_FALSE;
end;

function eglSwapInterval(dpy: EGLDisplay; interval: EGLint): EGLBoolean;
begin
  if Assigned(FloriaEGL().eglSwapInterval) then
    Result := FloriaEGL().eglSwapInterval(dpy, interval)
  else
    Result := EGL_FALSE;
end;

function eglCreateContext(dpy: EGLDisplay; config: EGLConfig; share_context: EGLContext; attrib_list: PEGLint): EGLContext;
begin
  if Assigned(FloriaEGL().eglCreateContext) then
    Result := FloriaEGL().eglCreateContext(dpy, config, share_context, attrib_list)
  else
    Result := EGL_NO_CONTEXT;
end;

function eglDestroyContext(dpy: EGLDisplay; ctx: EGLContext): EGLBoolean;
begin
  if Assigned(FloriaEGL().eglDestroyContext) then
    Result := FloriaEGL().eglDestroyContext(dpy, ctx)
  else
    Result := EGL_FALSE;
end;

function eglMakeCurrent(dpy: EGLDisplay; draw: EGLSurface; read: EGLSurface; ctx: EGLContext): EGLBoolean;
begin
  if Assigned(FloriaEGL().eglMakeCurrent) then
    Result := FloriaEGL().eglMakeCurrent(dpy, draw, read, ctx)
  else
    Result := EGL_FALSE;
end;

function eglGetCurrentContext(): EGLContext;
begin
  if Assigned(FloriaEGL().eglGetCurrentContext) then
    Result := FloriaEGL().eglGetCurrentContext()
  else
    Result := EGL_NO_CONTEXT;
end;

function eglGetCurrentSurface(readdraw: EGLint): EGLSurface;
begin
  if Assigned(FloriaEGL().eglGetCurrentSurface) then
    Result := FloriaEGL().eglGetCurrentSurface(readdraw)
  else
    Result := EGL_NO_SURFACE;
end;

function eglGetCurrentDisplay(): EGLDisplay;
begin
  if Assigned(FloriaEGL().eglGetCurrentDisplay) then
    Result := FloriaEGL().eglGetCurrentDisplay()
  else
    Result := EGL_NO_DISPLAY;
end;

function eglQueryContext(dpy: EGLDisplay; ctx: EGLContext; attribute: EGLint; value: PEGLint): EGLBoolean;
begin
  if Assigned(FloriaEGL().eglQueryContext) then
    Result := FloriaEGL().eglQueryContext(dpy, ctx, attribute, value)
  else
    Result := EGL_FALSE;
end;

function eglWaitGL(): EGLBoolean;
begin
  if Assigned(FloriaEGL().eglWaitGL) then
    Result := FloriaEGL().eglWaitGL()
  else
    Result := EGL_FALSE;
end;

function eglWaitNative(engine: EGLint): EGLBoolean;
begin
  if Assigned(FloriaEGL().eglWaitNative) then
    Result := FloriaEGL().eglWaitNative(engine)
  else
    Result := EGL_FALSE;
end;

function eglSwapBuffers(dpy: EGLDisplay; surface: EGLSurface): EGLBoolean;
begin
  if Assigned(FloriaEGL().eglSwapBuffers) then
    Result := FloriaEGL().eglSwapBuffers(dpy, surface)
  else
    Result := EGL_FALSE;
end;

function eglCopyBuffers(dpy: EGLDisplay; surface: EGLSurface; target: EGLNativePixmapType): EGLBoolean;
begin
  if Assigned(FloriaEGL().eglCopyBuffers) then
    Result := FloriaEGL().eglCopyBuffers(dpy, surface, target)
  else
    Result := EGL_FALSE;
end;

function eglGetProcAddress(procname: PChar): Pointer;
begin
  if Assigned(FloriaEGL().eglGetProcAddress) then
    Result := FloriaEGL().eglGetProcAddress(procname)
  else
    Result := nil;
end;

// Platform functions
function eglGetPlatformDisplay(platform: EGLenum; native_display: Pointer; attrib_list: PEGLAttrib): EGLDisplay;
begin
  if Assigned(FloriaEGL().eglGetPlatformDisplay) then
    Result := FloriaEGL().eglGetPlatformDisplay(platform, native_display, attrib_list)
  else
    Result := EGL_NO_DISPLAY;
end;

function eglCreatePlatformWindowSurface(dpy: EGLDisplay; config: EGLConfig; native_window: Pointer; attrib_list: PEGLAttrib): EGLSurface;
begin
  if Assigned(FloriaEGL().eglCreatePlatformWindowSurface) then
    Result := FloriaEGL().eglCreatePlatformWindowSurface(dpy, config, native_window, attrib_list)
  else
    Result := EGL_NO_SURFACE;
end;

function eglCreatePlatformPixmapSurface(dpy: EGLDisplay; config: EGLConfig; native_pixmap: Pointer; attrib_list: PEGLAttrib): EGLSurface;
begin
  if Assigned(FloriaEGL().eglCreatePlatformPixmapSurface) then
    Result := FloriaEGL().eglCreatePlatformPixmapSurface(dpy, config, native_pixmap, attrib_list)
  else
    Result := EGL_NO_SURFACE;
end;

function eglCreateSync(dpy: EGLDisplay; type_: EGLenum; attrib_list: PEGLAttrib): EGLSync;
begin
  if Assigned(FloriaEGL().eglCreateSync) then
    Result := FloriaEGL().eglCreateSync(dpy, type_, attrib_list)
  else
    Result := EGL_NO_SYNC;
end;

function eglDestroySync(dpy: EGLDisplay; sync: EGLSync): EGLBoolean;
begin
  if Assigned(FloriaEGL().eglDestroySync) then
    Result := FloriaEGL().eglDestroySync(dpy, sync)
  else
    Result := EGL_FALSE;
end;

function eglClientWaitSync(dpy: EGLDisplay; sync: EGLSync; flags: EGLint; timeout: EGLTime): EGLint;
begin
  if Assigned(FloriaEGL().eglClientWaitSync) then
    Result := FloriaEGL().eglClientWaitSync(dpy, sync, flags, timeout)
  else
    Result := EGL_FALSE;
end;

function eglGetSyncAttrib(dpy: EGLDisplay; sync: EGLSync; attribute: EGLint; value: PEGLAttrib): EGLBoolean;
begin
  if Assigned(FloriaEGL().eglGetSyncAttrib) then
    Result := FloriaEGL().eglGetSyncAttrib(dpy, sync, attribute, value)
  else
    Result := EGL_FALSE;
end;

function eglCreateImage(dpy: EGLDisplay; ctx: EGLContext; target: EGLenum; buffer: EGLClientBuffer; attrib_list: PEGLAttrib): EGLImage;
begin
  if Assigned(FloriaEGL().eglCreateImage) then
    Result := FloriaEGL().eglCreateImage(dpy, ctx, target, buffer, attrib_list)
  else
    Result := EGL_NO_IMAGE;
end;

function eglDestroyImage(dpy: EGLDisplay; image: EGLImage): EGLBoolean;
begin
  if Assigned(FloriaEGL().eglDestroyImage) then
    Result := FloriaEGL().eglDestroyImage(dpy, image)
  else
    Result := EGL_FALSE;
end;

initialization

finalization
  if Assigned(gEGLInstance) then
  begin
    gEGLInstance.Free();
    gEGLInstance := nil;
  end;

end.
