unit Floria.XCB.WM;

// Floria.XCB.WM
// =============
// High-level Window Manager framework for X11 built upon Floria.XCB,
// Floria.XCB.EWMH, and Floria.XCB.ICCCM.
//
// Supports root window redirection, frame reparenting, client state machines,
// ICCCM protocols, EWMH virtual desktops and synchronization, and interactive
// window operations (moving and resizing).

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  Classes, SysUtils, Contnrs, Math, BaseUnix,
  Floria.XCB,
  Floria.XCB.Cursor,
  Floria.XCB.EWMH,
  Floria.XCB.ICCCM,
  Floria.XCB.RandR,
  Floria.X11.KeySym;

const
  XCB_ALL_DESKTOPS = Cardinal($FFFFFFFF);

  // Upper bound on events handled per pump cycle. Keeps a flood of events from
  // starving the per-cycle tick (and therefore presentation).
  MAX_EVENTS_PER_PUMP = 64;

  // Motif Hints flags
  XCB_MWM_HINTS_FUNCTIONS   = 1 shl 0;
  XCB_MWM_HINTS_DECORATIONS = 1 shl 1;
  XCB_MWM_HINTS_INPUT_MODE  = 1 shl 2;
  XCB_MWM_HINTS_STATUS      = 1 shl 3;

  // Motif Functions
  XCB_MWM_FUNC_ALL          = 1 shl 0;
  XCB_MWM_FUNC_RESIZE       = 1 shl 1;
  XCB_MWM_FUNC_MOVE         = 1 shl 2;
  XCB_MWM_FUNC_MINIMIZE     = 1 shl 3;
  XCB_MWM_FUNC_MAXIMIZE     = 1 shl 4;
  XCB_MWM_FUNC_CLOSE        = 1 shl 5;

  // Motif Decorations
  XCB_MWM_DECOR_ALL         = 1 shl 0;
  XCB_MWM_DECOR_BORDER      = 1 shl 1;
  XCB_MWM_DECOR_RESIZEH     = 1 shl 2;
  XCB_MWM_DECOR_TITLE       = 1 shl 3;
  XCB_MWM_DECOR_MENU        = 1 shl 4;
  XCB_MWM_DECOR_MINIMIZE    = 1 shl 5;
  XCB_MWM_DECOR_MAXIMIZE    = 1 shl 6;

procedure xcb_free(p: Pointer); cdecl; external 'c' name 'free';

type
  // Motif WM hints record
  TXCBMwmHints = record
    flags       : Cardinal;
    functions   : Cardinal;
    decorations : Cardinal;
    input_mode  : Integer;
    status      : Cardinal;
  end;
  PXCBMwmHints = ^TXCBMwmHints;

  // EWMH 12-cardinal partial strut record
  TXCBStrutPartial = record
    Left         : Cardinal;
    Right        : Cardinal;
    Top          : Cardinal;
    Bottom       : Cardinal;
    LeftStartY   : Cardinal;
    LeftEndY     : Cardinal;
    RightStartY  : Cardinal;
    RightEndY    : Cardinal;
    TopStartX    : Cardinal;
    TopEndX      : Cardinal;
    BottomStartX : Cardinal;
    BottomEndX   : Cardinal;
    class function Create(): TXCBStrutPartial; static;
    function HasStrut(): Boolean;
  end;
  PXCBStrutPartial = ^TXCBStrutPartial;

  // Event pointer aliases
  Pxcb_map_request_event_t = ^xcb_map_request_event_t;
  Pxcb_configure_request_event_t = ^xcb_configure_request_event_t;
  Pxcb_unmap_notify_event_t = ^xcb_unmap_notify_event_t;
  Pxcb_destroy_notify_event_t = ^xcb_destroy_notify_event_t;
  Pxcb_button_press_event_t = ^xcb_button_press_event_t;
  Pxcb_button_release_event_t = ^xcb_button_release_event_t;
  Pxcb_motion_notify_event_t = ^xcb_motion_notify_event_t;
  Pxcb_expose_event_t = ^xcb_expose_event_t;
  Pxcb_client_message_event_t = ^xcb_client_message_event_t;
  Pxcb_property_notify_event_t = ^xcb_property_notify_event_t;

  // Cardinal array overlay for xcb_client_message_data_t (data32 format)
  PCardinalArray = ^TCardinalArray;
  TCardinalArray = array[0..4] of Cardinal;

  // Xinerama fallback bindings
  xcb_xinerama_is_active_cookie_t = record
    sequence: Cardinal;
  end;

  Pxcb_xinerama_is_active_reply_t = ^xcb_xinerama_is_active_reply_t;
  xcb_xinerama_is_active_reply_t = record
    response_type: Byte;
    pad0: Byte;
    sequence: Word;
    length: Cardinal;
    state: Cardinal;
  end;

  Pxcb_xinerama_screen_info_t = ^xcb_xinerama_screen_info_t;
  xcb_xinerama_screen_info_t = record
    x_org: SmallInt;
    y_org: SmallInt;
    width: Word;
    height: Word;
  end;

  xcb_xinerama_query_screens_cookie_t = record
    sequence: Cardinal;
  end;

  Pxcb_xinerama_query_screens_reply_t = ^xcb_xinerama_query_screens_reply_t;
  xcb_xinerama_query_screens_reply_t = record
    response_type: Byte;
    pad0: Byte;
    sequence: Word;
    length: Cardinal;
    number: Cardinal;
    pad1: array[0..19] of Byte;
  end;

function xcb_xinerama_is_active(c: Pxcb_connection_t): xcb_xinerama_is_active_cookie_t; cdecl; external 'xcb-xinerama' name 'xcb_xinerama_is_active';
function xcb_xinerama_is_active_reply(c: Pxcb_connection_t; cookie: xcb_xinerama_is_active_cookie_t; e: PPxcb_generic_error_t): Pxcb_xinerama_is_active_reply_t; cdecl; external 'xcb-xinerama' name 'xcb_xinerama_is_active_reply';
function xcb_xinerama_query_screens(c: Pxcb_connection_t): xcb_xinerama_query_screens_cookie_t; cdecl; external 'xcb-xinerama' name 'xcb_xinerama_query_screens';
function xcb_xinerama_query_screens_reply(c: Pxcb_connection_t; cookie: xcb_xinerama_query_screens_cookie_t; e: PPxcb_generic_error_t): Pxcb_xinerama_query_screens_reply_t; cdecl; external 'xcb-xinerama' name 'xcb_xinerama_query_screens_reply';
function xcb_xinerama_query_screens_screen_info(R: Pxcb_xinerama_query_screens_reply_t): Pxcb_xinerama_screen_info_t; cdecl; external 'xcb-xinerama' name 'xcb_xinerama_query_screens_screen_info';
function xcb_xinerama_query_screens_screen_info_length(R: Pxcb_xinerama_query_screens_reply_t): Integer; cdecl; external 'xcb-xinerama' name 'xcb_xinerama_query_screens_screen_info_length';

type
  // Forward declarations
  TXCBMonitor = class;
  TXCBWMClient = class;
  TXCBWindowManager = class;

  // 2D Point record with advanced record constructor
  TXCBPoint = record
    X : Integer;
    Y : Integer;
    class function Create(const AX, AY: Integer): TXCBPoint; static;
  end;

  // 2D Rectangle record with advanced record constructor and geometry math
  TXCBRect = record
    X      : Integer;
    Y      : Integer;
    Width  : Integer;
    Height : Integer;
    class function Create(const AX, AY, AWidth, AHeight: Integer): TXCBRect; static;
    function Contains(const APt: TXCBPoint): Boolean;
    function Contains(const AX, AY: Integer): Boolean;
    function Right(): Integer;
    function Bottom(): Integer;
  end;

  // Window frame decoration insets
  TXCBFrameInsets = record
    Left   : Integer;
    Top    : Integer;
    Right  : Integer;
    Bottom : Integer;
    class function Create(const ALeft, ATop, ARight, ABottom: Integer): TXCBFrameInsets; static;
  end;

  // Configurable frame decoration metrics
  TXCBFrameMetrics = record
    TitlebarHeight : Integer;
    BorderWidth    : Integer;
    Insets         : TXCBFrameInsets;
    class function Create(const ATitlebarHeight: Integer = 24; const ABorderWidth: Integer = 1): TXCBFrameMetrics; static;
    function ClientToFrameRect(const AClientRect: TXCBRect): TXCBRect;
    function FrameToClientInnerRect(const AFrameRect: TXCBRect): TXCBRect;
    function FrameToClientRootRect(const AFrameRect: TXCBRect): TXCBRect;
  end;

  // Window state flags and set
  TXCBWindowStateFlag = (
    wsMinimized,
    wsMaximizedHorz,
    wsMaximizedVert,
    wsFullscreen,
    wsSticky,
    wsAbove,
    wsBelow,
    wsHidden,
    wsFocused,
    wsTiledLeft,
    wsTiledRight
  );
  TXCBWindowState = set of TXCBWindowStateFlag;

  // Window functional types
  TXCBWindowType = (
    wtNormal,
    wtDialog,
    wtDock,
    wtDesktop,
    wtToolbar,
    wtMenu,
    wtDropdownMenu,
    wtPopupMenu,
    wtTooltip,
    wtNotification,
    wtCombo,
    wtDnd,
    wtUtility,
    wtSplash
  );

  // Mouse interactive drag mode
  TXCBDragMode = (
    dmNone,
    dmMove,
    dmResize,
    dmResizeTop,
    dmResizeBottom,
    dmResizeLeft,
    dmResizeRight,
    dmResizeTopLeft,
    dmResizeTopRight,
    dmResizeBottomLeft,
    dmResizeBottomRight
  );

  // Invoked when xcb_grab_pointer refuses a drag, with the XCB_GRAB_STATUS_*
  // value (255 when no reply was received). Lets the shell log or fall back.
  TXCBDragGrabFailureEvent = procedure(const AStatus: Byte) of object;

  // The binding does not declare a pointer type for focus events.
  Pxcb_focus_in_event_t = ^xcb_focus_in_event_t;

  // Frame painting delegate
  TXCBFramePaintEvent = procedure(ASender: TObject; AClient: TXCBWMClient; const ARect: TXCBRect) of object;

  // Compass navigation direction for multi-monitor shifts
  TXCBDirection = (
    dirLeft,
    dirRight,
    dirUp,
    dirDown
  );

  // TXCBMonitor
  // Represents a physical or logical display output
  TXCBMonitor = class
  private
    FName       : AnsiString;
    FRect       : TXCBRect;
    FWorkarea   : TXCBRect;
    FIsPrimary  : Boolean;
    FIndex      : Integer;
    FStrut      : TXCBStrutPartial;
  public
    constructor Create(const AName: AnsiString; const ARect: TXCBRect; const AIsPrimary: Boolean = False; const AIndex: Integer = 0);
    destructor Destroy(); override;

    function Contains(const AX, AY: Integer): Boolean;
    function Contains(const APt: TXCBPoint): Boolean;
    function IntersectionArea(const ARect: TXCBRect): Integer;
    procedure ResetWorkarea();
    procedure ApplyStrut(const AStrut: TXCBStrutPartial; const AScreenWidth, AScreenHeight: Integer);

    property Name       : AnsiString       read FName write FName;
    property Rect       : TXCBRect         read FRect write FRect;
    property Workarea   : TXCBRect         read FWorkarea write FWorkarea;
    property IsPrimary  : Boolean          read FIsPrimary write FIsPrimary;
    property Index      : Integer          read FIndex write FIndex;
    property Strut      : TXCBStrutPartial read FStrut write FStrut;
  end;

  // TXCBWMClient
  // Managed top-level client application window
  TXCBWMClient = class
  private
    FManager             : TXCBWindowManager;
    FClientWindow        : xcb_window_t;
    FFrameWindow         : xcb_window_t;
    FResizeWindow        : xcb_window_t;
    FTitle               : AnsiString;
    FWindowClass         : AnsiString;
    FWindowInstance      : AnsiString;
    FPid                 : Cardinal;
    FDesktop             : Integer;
    FWindowType          : TXCBWindowType;
    FState               : TXCBWindowState;
    FCurrentRect         : TXCBRect;
    FRestoredRect        : TXCBRect;
    FMinSize             : TXCBPoint;
    FMaxSize             : TXCBPoint;
    FBaseSize            : TXCBPoint;
    FSizeInc             : TXCBPoint;
    FSupportsDeleteWindow: Boolean;
    FSupportsTakeFocus   : Boolean;
    FIsReparented        : Boolean;
    FOverrideRedirect    : Boolean;
    FBorderless          : Boolean;
    FTransientFor        : xcb_window_t;
    FHasUserPosition     : Boolean;
    FHasProgramPosition  : Boolean;
    FWinGravity          : Cardinal;
    FStrut               : TXCBStrutPartial;
    FCanResize           : Boolean;
    FCanMaximize         : Boolean;
    FCanMinimize         : Boolean;
    FCanClose            : Boolean;
    FHasMaximizeButton   : Boolean;
    FHasMinimizeButton   : Boolean;
    FHasCloseButton      : Boolean;
  public
    constructor Create(const AClientWin: xcb_window_t; const AManager: TXCBWindowManager);
    destructor Destroy(); override;

    procedure Activate();
    procedure Close();
    procedure Maximize();
    procedure Restore();
    procedure TileLeft();
    procedure TileRight();
    procedure Minimize();
    procedure Unminimize();
    procedure SetFullscreen(const AFullscreen: Boolean);
    procedure Move(const AX, AY: Integer);
    procedure Resize(const AWidth, AHeight: Integer);
    procedure SetGeometry(const AX, AY, AWidth, AHeight: Integer);
    procedure SetDesktop(const ADesktopIndex: Integer);
    procedure SetSticky(const ASticky: Boolean);
    procedure UpdateEWMHState();

    function ConstrainSize(const AWidth, AHeight: Integer): TXCBPoint;
    function ShouldBeVisibleOnDesktop(const ACurrentDesktop: Integer): Boolean;
    function TitlebarRect(): TXCBRect;
    function IsMenu(): Boolean;
    function IsDecorated(): Boolean;
    function CurrentMonitor(): TXCBMonitor;

    property ClientWindow        : xcb_window_t      read FClientWindow;
    property FrameWindow         : xcb_window_t      read FFrameWindow write FFrameWindow;
    property ResizeWindow        : xcb_window_t      read FResizeWindow write FResizeWindow;
    property Title               : AnsiString        read FTitle write FTitle;
    property WindowClass         : AnsiString        read FWindowClass write FWindowClass;
    property WindowInstance      : AnsiString        read FWindowInstance write FWindowInstance;
    property Pid                 : Cardinal          read FPid write FPid;
    property Desktop             : Integer           read FDesktop write FDesktop;
    property WindowType          : TXCBWindowType    read FWindowType write FWindowType;
    property State               : TXCBWindowState   read FState write FState;
    property CurrentRect         : TXCBRect          read FCurrentRect write FCurrentRect;
    property RestoredRect        : TXCBRect          read FRestoredRect write FRestoredRect;
    property MinSize             : TXCBPoint         read FMinSize write FMinSize;
    property MaxSize             : TXCBPoint         read FMaxSize write FMaxSize;
    property BaseSize            : TXCBPoint         read FBaseSize write FBaseSize;
    property SizeInc             : TXCBPoint         read FSizeInc write FSizeInc;
    property SupportsDeleteWindow: Boolean           read FSupportsDeleteWindow write FSupportsDeleteWindow;
    property SupportsTakeFocus   : Boolean           read FSupportsTakeFocus write FSupportsTakeFocus;
    property IsReparented        : Boolean           read FIsReparented write FIsReparented;
    property OverrideRedirect    : Boolean           read FOverrideRedirect write FOverrideRedirect;
    property Borderless          : Boolean           read FBorderless write FBorderless;
    property TransientFor        : xcb_window_t      read FTransientFor write FTransientFor;
    property HasUserPosition     : Boolean           read FHasUserPosition write FHasUserPosition;
    property HasProgramPosition  : Boolean           read FHasProgramPosition write FHasProgramPosition;
    property WinGravity          : Cardinal          read FWinGravity write FWinGravity;
    property Strut               : TXCBStrutPartial  read FStrut write FStrut;
    property CanResize           : Boolean           read FCanResize write FCanResize;
    property CanMaximize         : Boolean           read FCanMaximize write FCanMaximize;
    property CanMinimize         : Boolean           read FCanMinimize write FCanMinimize;
    property CanClose            : Boolean           read FCanClose write FCanClose;
    property HasMaximizeButton   : Boolean           read FHasMaximizeButton write FHasMaximizeButton;
    property HasMinimizeButton   : Boolean           read FHasMinimizeButton write FHasMinimizeButton;
    property HasCloseButton      : Boolean           read FHasCloseButton write FHasCloseButton;
  end;

  // TXCBWindowManager
  // Master controller managing root redirection, client lifecycle, and EWMH synchronization
  TXCBWindowManager = class
  private
    FConn              : Pxcb_connection_t;
    FScreen            : Pxcb_screen_t;
    FScreenNum         : Integer;
    FRootWindow        : xcb_window_t;
    FEwmh              : xcb_ewmh_connection_t;
    FEwmhInitialized   : Boolean;
    FWMCheckWindow     : xcb_window_t;
    FWMName            : AnsiString;
    FFrameMetrics      : TXCBFrameMetrics;
    FClients           : TObjectList;
    FActiveClient      : TXCBWMClient;
    FDesktopCount      : Integer;
    FCurrentDesktop    : Integer;
    FDesktopNames      : TStringList;
    FIsRunning         : Boolean;
    FShutdownRequested : Boolean;
    FWakeupPipe        : array[0..1] of cint;
    FWakeupPipeValid   : Boolean;
    FTickIntervalMs    : Integer;

    // Key bindings, resolved from keysyms and the server's modifier map rather
    // than assumed from evdev/US keycodes. Populated by ResolveKeyBindings.
    FKeycodeTab        : xcb_keycode_t;
    FKeycodeSpace      : xcb_keycode_t;
    FKeycodeLeft       : xcb_keycode_t;
    FKeycodeRight      : xcb_keycode_t;
    FKeycodeUp         : xcb_keycode_t;
    FKeycodeDown       : xcb_keycode_t;
    FKeycodeEscape     : xcb_keycode_t;
    FKeycodeReturn     : xcb_keycode_t;
    FKeycodeAltL       : xcb_keycode_t;
    FKeycodeD          : xcb_keycode_t;
    FKeycodeAltR       : xcb_keycode_t;
    FModAlt            : Word;
    FModSuper          : Word;
    FModNumLock        : Word;
    FModCapsLock       : Word;
    FKeyBindingsValid  : Boolean;
    FSyncingFocus      : Boolean;
    // Most-recently-used order. Front = current active client. This is what makes
    // Alt+Tab mean "the previous window" rather than "the next in creation order".
    FMruClients        : TFPList;
    FWorkarea          : TXCBRect;
    FMonitors          : TObjectList;
    FPrimaryMonitor    : TXCBMonitor;
    FRandRAvailable    : Boolean;
    FRandREventBase    : Byte;
    FRandRErrorBase    : Byte;
    
    // Atoms
    FAtomWMDeleteWindow    : xcb_atom_t;
    FAtomWMTakeFocus       : xcb_atom_t;
    FAtomMotifWmHints      : xcb_atom_t;
    FAtomNetWmStrut        : xcb_atom_t;
    FAtomNetWmStrutPartial : xcb_atom_t;
    FAtomWMChangeState     : xcb_atom_t;
    FAtomWMState           : xcb_atom_t;

    // Interactive Dragging
    FDragClient        : TXCBWMClient;
    FDragMode          : TXCBDragMode;
    FDragStartPointer  : TXCBPoint;
    FDragStartRect     : TXCBRect;
    FDragGrabFailureHook : TXCBDragGrabFailureEvent;

    // Cursors
    FCursorCtx         : Pxcb_cursor_context_t;
    FCursorNormal      : xcb_cursor_t;
    FCursorMove        : xcb_cursor_t;
    FCursorResizeLeft  : xcb_cursor_t;
    FCursorResizeRight : xcb_cursor_t;
    FCursorResizeTop   : xcb_cursor_t;
    FCursorResizeBottom: xcb_cursor_t;
    FCursorResizeTopLeft    : xcb_cursor_t;
    FCursorResizeTopRight   : xcb_cursor_t;
    FCursorResizeBottomLeft : xcb_cursor_t;
    FCursorResizeBottomRight: xcb_cursor_t;
    FCurrentRootCursor : xcb_cursor_t;

    FOnFramePaint      : TXCBFramePaintEvent;

    procedure InitCursors();
    function LoadCursor(const ANames: array of PChar): xcb_cursor_t;
    procedure RefreshEWMHClientList();
    procedure RefreshEWMHActiveWindow();
    procedure RefreshEWMHDesktop();
    procedure RefreshEWMHWorkarea();
    procedure SetWorkarea(const AWorkarea: TXCBRect);
    procedure ReadClientProperties(const AClient: TXCBWMClient);
    function CreateFrameWindow(const AClient: TXCBWMClient; const ARect: TXCBRect): xcb_window_t;
  protected
    procedure DoOnClientMapped(const AClient: TXCBWMClient); virtual;
    procedure DoOnClientUnmapped(const AClient: TXCBWMClient); virtual;
    procedure DoOnClientActivated(const AClient: TXCBWMClient); virtual;
    procedure DoOnClientConfigure(const AClient: TXCBWMClient); virtual;
    procedure DoOnClientMinimized(const AClient: TXCBWMClient); virtual;
    procedure DoOnClientRestored(const AClient: TXCBWMClient); virtual;
    procedure DoOnDesktopChanged(const AOldDesktop, ANewDesktop: Integer); virtual;
    procedure DoOnWorkareaChanged(const AOldWorkarea, ANewWorkarea: TXCBRect); virtual;
    procedure DoOnFramePaint(const AClient: TXCBWMClient; const ARect: TXCBRect); virtual;
    procedure DoOnClientPropertiesChanged(const AClient: TXCBWMClient); virtual;
  public
    constructor Create(AConn: Pxcb_connection_t = nil; const AScreenNum: Integer = 0);
    destructor Destroy(); override;

    function ClaimOwnership(): Boolean; virtual;    procedure InitEWMH();
    procedure UpdateAllowedActions(const AClient: TXCBWMClient);
    procedure ScanWindows();
    function ManageWindow(const AWindow: xcb_window_t): TXCBWMClient;
    procedure UnmanageWindow(const AClient: TXCBWMClient);
    function FindClient(const AWindow: xcb_window_t): TXCBWMClient;
    function FindClientByClientWindow(const AWindow: xcb_window_t): TXCBWMClient;
    function FindClientByFrameWindow(const AWindow: xcb_window_t): TXCBWMClient;
    function FindClientByResizeWindow(const AWindow: xcb_window_t): TXCBWMClient;

    function ProcessEvent(const AEvent: Pxcb_generic_event_t): Boolean; virtual;
    procedure Run(); virtual;
    procedure Stop();
    // Shutdown plumbing. RequestShutdown is async-signal-safe: it only sets a flag
    // and writes one byte to a self-pipe, so it may be called from a signal handler.
    procedure RequestShutdown();
    procedure CreateWakeupPipe();
    procedure CloseWakeupPipe();
    procedure DrainWakeupPipe();
    // One select + drain cycle. Returns True when at least one event was handled.
    function PumpEventsOnce(const ATimeoutMs: Integer): Boolean;
    // Called after each pump cycle, whether or not events arrived. Override for
    // animation ticks and deferred presentation.
    procedure DoOnTick(const AElapsedMs: Integer); virtual;
    property ShutdownRequested : Boolean read FShutdownRequested;
    property TickIntervalMs    : Integer read FTickIntervalMs write FTickIntervalMs;

    // Keyboard binding resolution (WM-06). Keysyms are mapped to the current
    // keycodes and modifier masks on demand, so a layout change does not silently
    // break every grab.
    procedure ResolveKeyBindings();
    function KeysymToKeycode(const AKeysym: Cardinal): xcb_keycode_t;
    function KeycodeToModifierMask(const AKeycode: xcb_keycode_t): Word;
    // Override to re-issue passive grabs after a layout change.
    procedure RebindGlobalKeys(); virtual;
    property KeycodeTab        : xcb_keycode_t read FKeycodeTab;
    property KeycodeSpace      : xcb_keycode_t read FKeycodeSpace;
    property KeycodeLeft       : xcb_keycode_t read FKeycodeLeft;
    property KeycodeRight      : xcb_keycode_t read FKeycodeRight;
    property KeycodeUp         : xcb_keycode_t read FKeycodeUp;
    property KeycodeDown       : xcb_keycode_t read FKeycodeDown;
    property KeycodeEscape     : xcb_keycode_t read FKeycodeEscape;
    property KeycodeReturn     : xcb_keycode_t read FKeycodeReturn;
    property KeycodeAltL       : xcb_keycode_t read FKeycodeAltL;
    property KeycodeD          : xcb_keycode_t read FKeycodeD;
    property KeycodeAltR       : xcb_keycode_t read FKeycodeAltR;
    property ModAlt            : Word          read FModAlt;
    property ModSuper          : Word          read FModSuper;
    property ModNumLock        : Word          read FModNumLock;
    property ModCapsLock       : Word          read FModCapsLock;
    property KeyBindingsValid  : Boolean       read FKeyBindingsValid;

    procedure SwitchDesktop(const ANewDesktop: Integer);
    procedure SetDesktopCount(const ACount: Integer);
    procedure SetActiveClient(const AClient: TXCBWMClient);
    // Adopt focus that arrived from somewhere other than the manager (a client
    // calling XSetInputFocus, or focus reverting). Updates the active client and
    // state without re-raising or re-asserting focus, which would fight the server.
    procedure SyncActiveClientFromFocus(const AClient: TXCBWMClient); virtual;
    property SyncingFocus : Boolean read FSyncingFocus write FSyncingFocus;

    // MRU bookkeeping. TouchMru moves a client to the front; RemoveFromMru drops
    // it. Both are no-ops for nil or for clients that were never activated.
    procedure TouchMru(const AClient: TXCBWMClient);
    procedure RemoveFromMru(const AClient: TXCBWMClient);
    property MruClients : TFPList read FMruClients;
    procedure RecomputeWorkareas();
    procedure RecomputeWorkarea();

    // Multi-Monitor management
    function RefreshMonitors(): Boolean;
    procedure DoOnMonitorsChanged(); virtual;
    function GetMonitorCount(): Integer;
    function GetMonitor(const AIndex: Integer): TXCBMonitor;
    function MonitorForPoint(const AX, AY: Integer): TXCBMonitor;
    function MonitorForRect(const ARect: TXCBRect): TXCBMonitor;
    function MonitorForClient(const AClient: TXCBWMClient): TXCBMonitor;
    function AdjacentMonitor(const ACurrent: TXCBMonitor; const ADirection: TXCBDirection): TXCBMonitor;
    procedure MoveClientToMonitor(const AClient: TXCBWMClient; const ATargetMonitor: TXCBMonitor);

    // Reparenting and framing
    function CreateResizeWindow(const AClient: TXCBWMClient; const ARect: TXCBRect): xcb_window_t;
    procedure ReparentClient(const AClient: TXCBWMClient);
    procedure UnparentClient(const AClient: TXCBWMClient);
    procedure SendSyntheticConfigureNotify(const AClient: TXCBWMClient);

    // Interactive dragging helpers
    procedure BeginDrag(const AClient: TXCBWMClient; const AMode: TXCBDragMode; const ARootX, ARootY: Integer); virtual;
    procedure UpdateDrag(const ARootX, ARootY: Integer); virtual;
    procedure UpdateDragOrigin(const ARootX, ARootY: Integer; const ARect: TXCBRect);
    procedure EndDrag(); virtual;
    property OnDragGrabFailed  : TXCBDragGrabFailureEvent read FDragGrabFailureHook write FDragGrabFailureHook;

    // Cursors
    function CursorForDragMode(const AMode: TXCBDragMode): xcb_cursor_t; virtual;
    procedure SetWindowCursor(const AWindow: xcb_window_t; const ACursor: xcb_cursor_t);

    property Connection        : Pxcb_connection_t   read FConn;
    property Screen            : Pxcb_screen_t       read FScreen;
    property ScreenNum         : Integer             read FScreenNum;
    property RootWindow        : xcb_window_t        read FRootWindow;
    property WMCheckWindow     : xcb_window_t        read FWMCheckWindow;
    property WMName            : AnsiString          read FWMName write FWMName;
    property FrameMetrics      : TXCBFrameMetrics    read FFrameMetrics write FFrameMetrics;
    property Clients           : TObjectList         read FClients;
    property ActiveClient      : TXCBWMClient        read FActiveClient write SetActiveClient;
    property DesktopCount      : Integer             read FDesktopCount write SetDesktopCount;
    property CurrentDesktop    : Integer             read FCurrentDesktop;
    property DesktopNames      : TStringList         read FDesktopNames;
    property Workarea          : TXCBRect            read FWorkarea write SetWorkarea;
    property IsRunning         : Boolean             read FIsRunning;
    property DragMode          : TXCBDragMode        read FDragMode;
    property DragClient        : TXCBWMClient        read FDragClient;
    property AtomWMDeleteWindow    : xcb_atom_t      read FAtomWMDeleteWindow;
    property AtomWMTakeFocus       : xcb_atom_t      read FAtomWMTakeFocus;
    property AtomMotifWmHints      : xcb_atom_t      read FAtomMotifWmHints;
    property AtomNetWmStrut        : xcb_atom_t      read FAtomNetWmStrut;
    property AtomNetWmStrutPartial : xcb_atom_t      read FAtomNetWmStrutPartial;
    property AtomWMChangeState     : xcb_atom_t      read FAtomWMChangeState;
    property AtomWMState           : xcb_atom_t      read FAtomWMState;
    property Ewmh                  : xcb_ewmh_connection_t read FEwmh write FEwmh;
    property EwmhInitialized       : Boolean               read FEwmhInitialized write FEwmhInitialized;
    property Monitors              : TObjectList           read FMonitors;
    property PrimaryMonitor        : TXCBMonitor           read FPrimaryMonitor;
    property MonitorCount          : Integer               read GetMonitorCount;
    property RandRAvailable        : Boolean               read FRandRAvailable;

    property CursorNormal      : xcb_cursor_t        read FCursorNormal;
    property CursorMove        : xcb_cursor_t        read FCursorMove;
    property CursorResizeLeft  : xcb_cursor_t        read FCursorResizeLeft;
    property CursorResizeRight : xcb_cursor_t        read FCursorResizeRight;
    property CursorResizeTop   : xcb_cursor_t        read FCursorResizeTop;
    property CursorResizeBottom: xcb_cursor_t        read FCursorResizeBottom;
    property CursorResizeTopLeft    : xcb_cursor_t   read FCursorResizeTopLeft;
    property CursorResizeTopRight   : xcb_cursor_t   read FCursorResizeTopRight;
    property CursorResizeBottomLeft : xcb_cursor_t   read FCursorResizeBottomLeft;
    property CursorResizeBottomRight: xcb_cursor_t   read FCursorResizeBottomRight;
    property CurrentRootCursor : xcb_cursor_t        read FCurrentRootCursor write FCurrentRootCursor;

    property OnFramePaint      : TXCBFramePaintEvent read FOnFramePaint write FOnFramePaint;
  end;

function InternAtom(AConn: Pxcb_connection_t; const AName: AnsiString): xcb_atom_t;

implementation

function InternAtom(AConn: Pxcb_connection_t; const AName: AnsiString): xcb_atom_t;
var
  Cookie: xcb_intern_atom_cookie_t;
  Reply: Pxcb_intern_atom_reply_t;
begin
  Result := 0;
  if AConn = nil then Exit;
  Cookie := xcb_intern_atom(AConn, 0, Length(AName), PAnsiChar(AName));
  Reply := xcb_intern_atom_reply(AConn, Cookie, nil);
  if Reply <> nil then
  begin
    Result := Reply^.atom;
    xcb_free(Reply);
  end;
end;

// ============================================================================
// TXCBStrutPartial
// ============================================================================

class function TXCBStrutPartial.Create(): TXCBStrutPartial;
begin
  FillChar(Result, SizeOf(Result), 0);
end;

function TXCBStrutPartial.HasStrut(): Boolean;
begin
  Result := (Left > 0) or (Right > 0) or (Top > 0) or (Bottom > 0);
end;

// ============================================================================
// TXCBPoint
// ============================================================================

class function TXCBPoint.Create(const AX, AY: Integer): TXCBPoint;
begin
  Result.X := AX;
  Result.Y := AY;
end;

// ============================================================================
// TXCBRect
// ============================================================================

class function TXCBRect.Create(const AX, AY, AWidth, AHeight: Integer): TXCBRect;
begin
  Result.X := AX;
  Result.Y := AY;
  Result.Width := AWidth;
  Result.Height := AHeight;
end;

function TXCBRect.Contains(const APt: TXCBPoint): Boolean;
begin
  Result := (APt.X >= X) and (APt.X < X + Width) and
            (APt.Y >= Y) and (APt.Y < Y + Height);
end;

function TXCBRect.Contains(const AX, AY: Integer): Boolean;
begin
  Result := (AX >= X) and (AX < X + Width) and
            (AY >= Y) and (AY < Y + Height);
end;

function TXCBRect.Right(): Integer;
begin
  Result := X + Width;
end;

function TXCBRect.Bottom(): Integer;
begin
  Result := Y + Height;
end;

// ============================================================================
// TXCBFrameInsets
// ============================================================================

class function TXCBFrameInsets.Create(const ALeft, ATop, ARight, ABottom: Integer): TXCBFrameInsets;
begin
  Result.Left := ALeft;
  Result.Top := ATop;
  Result.Right := ARight;
  Result.Bottom := ABottom;
end;

// ============================================================================
// TXCBFrameMetrics
// ============================================================================

class function TXCBFrameMetrics.Create(const ATitlebarHeight: Integer = 24; const ABorderWidth: Integer = 1): TXCBFrameMetrics;
begin
  Result.TitlebarHeight := ATitlebarHeight;
  Result.BorderWidth := ABorderWidth;
  Result.Insets.Left := ABorderWidth;
  Result.Insets.Top := ATitlebarHeight + ABorderWidth;
  Result.Insets.Right := ABorderWidth;
  Result.Insets.Bottom := ABorderWidth;
end;

function TXCBFrameMetrics.ClientToFrameRect(const AClientRect: TXCBRect): TXCBRect;
begin
  Result.X := AClientRect.X - Insets.Left;
  Result.Y := AClientRect.Y - Insets.Top;
  Result.Width := AClientRect.Width + Insets.Left + Insets.Right;
  Result.Height := AClientRect.Height + Insets.Top + Insets.Bottom;
end;

function TXCBFrameMetrics.FrameToClientInnerRect(const AFrameRect: TXCBRect): TXCBRect;
begin
  Result.X := Insets.Left;
  Result.Y := Insets.Top;
  Result.Width := AFrameRect.Width - (Insets.Left + Insets.Right);
  if Result.Width < 1 then Result.Width := 1;
  Result.Height := AFrameRect.Height - (Insets.Top + Insets.Bottom);
  if Result.Height < 1 then Result.Height := 1;
end;

function TXCBFrameMetrics.FrameToClientRootRect(const AFrameRect: TXCBRect): TXCBRect;
begin
  Result.X := AFrameRect.X + Insets.Left;
  Result.Y := AFrameRect.Y + Insets.Top;
  Result.Width := AFrameRect.Width - (Insets.Left + Insets.Right);
  if Result.Width < 1 then Result.Width := 1;
  Result.Height := AFrameRect.Height - (Insets.Top + Insets.Bottom);
  if Result.Height < 1 then Result.Height := 1;
end;

// ============================================================================
// TXCBMonitor
// ============================================================================

constructor TXCBMonitor.Create(const AName: AnsiString; const ARect: TXCBRect; const AIsPrimary: Boolean = False; const AIndex: Integer = 0);
begin
  inherited Create();
  FName := AName;
  FRect := ARect;
  FWorkarea := ARect;
  FIsPrimary := AIsPrimary;
  FIndex := AIndex;
  FillChar(FStrut, SizeOf(FStrut), 0);
end;

destructor TXCBMonitor.Destroy();
begin
  inherited Destroy();
end;

function TXCBMonitor.Contains(const AX, AY: Integer): Boolean;
begin
  Result := (AX >= FRect.X) and (AX < FRect.Right()) and (AY >= FRect.Y) and (AY < FRect.Bottom());
end;

function TXCBMonitor.Contains(const APt: TXCBPoint): Boolean;
begin
  Result := Contains(APt.X, APt.Y);
end;

function TXCBMonitor.IntersectionArea(const ARect: TXCBRect): Integer;
var
  ix1, iy1, ix2, iy2: Integer;
begin
  ix1 := Max(FRect.X, ARect.X);
  iy1 := Max(FRect.Y, ARect.Y);
  ix2 := Min(FRect.Right(), ARect.Right());
  iy2 := Min(FRect.Bottom(), ARect.Bottom());
  if (ix2 > ix1) and (iy2 > iy1) then
    Result := (ix2 - ix1) * (iy2 - iy1)
  else
    Result := 0;
end;

procedure TXCBMonitor.ResetWorkarea();
begin
  FWorkarea := FRect;
  FillChar(FStrut, SizeOf(FStrut), 0);
end;

procedure TXCBMonitor.ApplyStrut(const AStrut: TXCBStrutPartial; const AScreenWidth, AScreenHeight: Integer);
var
  MonRight, MonBottom: Integer;
  StrutTopH, StrutBottomH, StrutLeftW, StrutRightW: Integer;
  EffTopStartX, EffTopEndX: Cardinal;
  EffBottomStartX, EffBottomEndX: Cardinal;
  EffLeftStartY, EffLeftEndY: Cardinal;
  EffRightStartY, EffRightEndY: Cardinal;
begin
  MonRight := FRect.Right();
  MonBottom := FRect.Bottom();

  // 1. Top Strut
  if AStrut.Top > 0 then
  begin
    EffTopStartX := AStrut.TopStartX;
    EffTopEndX := AStrut.TopEndX;
    if (EffTopStartX = 0) and (EffTopEndX = 0) then
      EffTopEndX := AScreenWidth - 1;

    if (Integer(EffTopStartX) < MonRight) and (Integer(EffTopEndX) >= FRect.X) then
    begin
      if Integer(AStrut.Top) > FRect.Y then
      begin
        StrutTopH := Min(Integer(AStrut.Top) - FRect.Y, FRect.Height);
        if StrutTopH > Integer(FStrut.Top) then
          FStrut.Top := StrutTopH;
      end;
    end;
  end;

  // 2. Bottom Strut
  if AStrut.Bottom > 0 then
  begin
    EffBottomStartX := AStrut.BottomStartX;
    EffBottomEndX := AStrut.BottomEndX;
    if (EffBottomStartX = 0) and (EffBottomEndX = 0) then
      EffBottomEndX := AScreenWidth - 1;

    if (Integer(EffBottomStartX) < MonRight) and (Integer(EffBottomEndX) >= FRect.X) then
    begin
      if (AScreenHeight - Integer(AStrut.Bottom)) < MonBottom then
      begin
        StrutBottomH := Min(MonBottom - Max(FRect.Y, AScreenHeight - Integer(AStrut.Bottom)), FRect.Height);
        if StrutBottomH > Integer(FStrut.Bottom) then
          FStrut.Bottom := StrutBottomH;
      end;
    end;
  end;

  // 3. Left Strut
  if AStrut.Left > 0 then
  begin
    EffLeftStartY := AStrut.LeftStartY;
    EffLeftEndY := AStrut.LeftEndY;
    if (EffLeftStartY = 0) and (EffLeftEndY = 0) then
      EffLeftEndY := AScreenHeight - 1;

    if (Integer(EffLeftStartY) < MonBottom) and (Integer(EffLeftEndY) >= FRect.Y) then
    begin
      if Integer(AStrut.Left) > FRect.X then
      begin
        StrutLeftW := Min(Integer(AStrut.Left) - FRect.X, FRect.Width);
        if StrutLeftW > Integer(FStrut.Left) then
          FStrut.Left := StrutLeftW;
      end;
    end;
  end;

  // 4. Right Strut
  if AStrut.Right > 0 then
  begin
    EffRightStartY := AStrut.RightStartY;
    EffRightEndY := AStrut.RightEndY;
    if (EffRightStartY = 0) and (EffRightEndY = 0) then
      EffRightEndY := AScreenHeight - 1;

    if (Integer(EffRightStartY) < MonBottom) and (Integer(EffRightEndY) >= FRect.Y) then
    begin
      if (AScreenWidth - Integer(AStrut.Right)) < MonRight then
      begin
        StrutRightW := Min(MonRight - Max(FRect.X, AScreenWidth - Integer(AStrut.Right)), FRect.Width);
        if StrutRightW > Integer(FStrut.Right) then
          FStrut.Right := StrutRightW;
      end;
    end;
  end;

  // Recompute workarea from accumulated monitor struts
  FWorkarea.X := FRect.X + FStrut.Left;
  FWorkarea.Y := FRect.Y + FStrut.Top;
  FWorkarea.Width := Max(100, FRect.Width - Integer(FStrut.Left + FStrut.Right));
  FWorkarea.Height := Max(100, FRect.Height - Integer(FStrut.Top + FStrut.Bottom));
end;

// ============================================================================
// TXCBWMClient
// ============================================================================

constructor TXCBWMClient.Create(const AClientWin: xcb_window_t; const AManager: TXCBWindowManager);
begin
  inherited Create();
  FManager := AManager;
  FClientWindow := AClientWin;
  FFrameWindow := 0;
  FTitle := '';
  FWindowClass := '';
  FWindowInstance := '';
  FPid := 0;
  FDesktop := 0;
  FWindowType := wtNormal;
  FState := [];
  FCurrentRect := TXCBRect.Create(0, 0, 100, 100);
  FRestoredRect := FCurrentRect;
  FMinSize := TXCBPoint.Create(0, 0);
  FMaxSize := TXCBPoint.Create(0, 0);
  FBaseSize := TXCBPoint.Create(0, 0);
  FSizeInc := TXCBPoint.Create(1, 1);
  FSupportsDeleteWindow := False;
  FSupportsTakeFocus := False;
  FIsReparented := False;
  FOverrideRedirect := False;
  FBorderless := False;
  FTransientFor := 0;
  FHasUserPosition := False;
  FHasProgramPosition := False;
  FWinGravity := 1;
  FStrut := TXCBStrutPartial.Create();
  FCanResize := True;
  FCanMaximize := True;
  FCanMinimize := True;
  FCanClose := True;
  FHasMaximizeButton := True;
  FHasMinimizeButton := True;
  FHasCloseButton := True;
end;

destructor TXCBWMClient.Destroy();
begin
  if (FManager <> nil) and (FManager.Connection <> nil) and (FResizeWindow <> 0) then
  begin
    xcb_destroy_window(FManager.Connection, FResizeWindow);
    FResizeWindow := 0;
  end;
  inherited Destroy();
end;

procedure TXCBWMClient.UpdateEWMHState();
var
  NetStates: array[0..7] of xcb_atom_t;
  Count: Integer;
  WmStateData: array[0..1] of Cardinal;
begin
  if (FManager = nil) or (FManager.Connection = nil) or (FClientWindow = 0) then Exit;

  // 1. ICCCM WM_STATE (NormalState = 1, IconicState = 3)
  if FManager.AtomWMState <> 0 then
  begin
    if wsMinimized in FState then
      WmStateData[0] := 3 // IconicState
    else
      WmStateData[0] := 1; // NormalState
    WmStateData[1] := 0; // None

    xcb_change_property(
      FManager.Connection,
      XCB_PROP_MODE_REPLACE,
      FClientWindow,
      FManager.AtomWMState,
      FManager.AtomWMState,
      32,
      2,
      @WmStateData[0]
    );
  end;

  // 2. EWMH _NET_WM_STATE
  if FManager.FEwmhInitialized then
  begin
    Count := 0;
    if wsMaximizedHorz in FState then
    begin
      NetStates[Count] := FManager.FEwmh._NET_WM_STATE_MAXIMIZED_HORZ;
      Inc(Count);
    end;
    if wsMaximizedVert in FState then
    begin
      NetStates[Count] := FManager.FEwmh._NET_WM_STATE_MAXIMIZED_VERT;
      Inc(Count);
    end;
    if wsFullscreen in FState then
    begin
      NetStates[Count] := FManager.FEwmh._NET_WM_STATE_FULLSCREEN;
      Inc(Count);
    end;
    if wsMinimized in FState then
    begin
      NetStates[Count] := FManager.FEwmh._NET_WM_STATE_HIDDEN;
      Inc(Count);
    end;
    if wsAbove in FState then
    begin
      NetStates[Count] := FManager.FEwmh._NET_WM_STATE_ABOVE;
      Inc(Count);
    end;

    if Count > 0 then
      xcb_change_property(
        FManager.Connection,
        XCB_PROP_MODE_REPLACE,
        FClientWindow,
        FManager.FEwmh._NET_WM_STATE,
        XCB_ATOM_ATOM,
        32,
        Count,
        @NetStates[0]
      )
    else
      xcb_delete_property(
        FManager.Connection,
        FClientWindow,
        FManager.FEwmh._NET_WM_STATE
      );
  end;
  xcb_flush(FManager.Connection);
end;

procedure TXCBWMClient.Activate();
var
  WinToRaise: xcb_window_t;
  Values: array[0..1] of Cardinal;
  Ev: xcb_client_message_event_t;
  Data32: PCardinalArray;
  OldCli, TransCli: TXCBWMClient;
  WasMinimized: Boolean;
  I: Integer;
begin
  WasMinimized := wsMinimized in FState;
  if WasMinimized then
  begin
    Exclude(FState, wsMinimized);
    if (FManager <> nil) and (FManager.Connection <> nil) then
    begin
      if FIsReparented and (FFrameWindow <> 0) then
        xcb_map_window(FManager.Connection, FFrameWindow);
      xcb_map_window(FManager.Connection, FClientWindow);
      if (FResizeWindow <> 0) and not ((wsMaximizedHorz in FState) or (wsFullscreen in FState)) then
        xcb_map_window(FManager.Connection, FResizeWindow);
    end;
    UpdateEWMHState();
    if (FManager <> nil) and (FManager.Clients <> nil) then
    begin
      for I := 0 to FManager.Clients.Count - 1 do
      begin
        TransCli := TXCBWMClient(FManager.Clients[I]);
        if (TransCli <> Self) and (TransCli.TransientFor = FClientWindow) and
           (wsMinimized in TransCli.State) then
          TransCli.Activate();
      end;
    end;
    if FManager <> nil then
      FManager.DoOnClientRestored(Self);
  end;

  Include(FState, wsFocused);
  if FManager = nil then Exit;

  OldCli := FManager.FActiveClient;
  FManager.FActiveClient := Self;
  if FManager.Connection <> nil then
  begin
    if (OldCli <> nil) and (OldCli <> Self) then
      Exclude(OldCli.FState, wsFocused);

    // Raise frame (or client window if direct/unparented)
    if FIsReparented and (FFrameWindow <> 0) then
      WinToRaise := FFrameWindow
    else
      WinToRaise := FClientWindow;

    if FWindowType = wtDesktop then
      Values[0] := XCB_STACK_MODE_BELOW
    else
      Values[0] := XCB_STACK_MODE_ABOVE;
    xcb_configure_window(FManager.Connection, WinToRaise, XCB_CONFIG_WINDOW_STACK_MODE, @Values[0]);

    if (FResizeWindow <> 0) and (WinToRaise = FFrameWindow) and not ((wsMaximizedHorz in FState) or (wsFullscreen in FState)) then
    begin
      Values[0] := WinToRaise;
      Values[1] := XCB_STACK_MODE_BELOW;
      xcb_configure_window(FManager.Connection, FResizeWindow,
                           XCB_CONFIG_WINDOW_SIBLING or XCB_CONFIG_WINDOW_STACK_MODE,
                           @Values[0]);
    end;

    // Raise transient children to maintain ICCCM transient stacking order
    if FManager.Clients <> nil then
    begin
      for I := 0 to FManager.Clients.Count - 1 do
      begin
        TransCli := TXCBWMClient(FManager.Clients[I]);
        if (TransCli <> Self) and (TransCli.TransientFor = FClientWindow) and
           not (wsMinimized in TransCli.State) and TransCli.IsReparented and (TransCli.FrameWindow <> 0) then
        begin
          Values[0] := XCB_STACK_MODE_ABOVE;
          xcb_configure_window(FManager.Connection, TransCli.FrameWindow, XCB_CONFIG_WINDOW_STACK_MODE, @Values[0]);
        end;
      end;
    end;

    // Set input focus
    xcb_set_input_focus(FManager.Connection, XCB_INPUT_FOCUS_POINTER_ROOT, FClientWindow, XCB_CURRENT_TIME);

    // Send WM_TAKE_FOCUS protocol message if supported
    if FSupportsTakeFocus and (FManager.AtomWMTakeFocus <> 0) then
    begin
      FillChar(Ev, SizeOf(Ev), 0);
      Ev.response_type := XCB_CLIENT_MESSAGE;
      Ev.format := 32;
      Ev.window := FClientWindow;
      Ev.type_ := FManager.FEwmh.WM_PROTOCOLS;
      Data32 := PCardinalArray(@Ev.data.raw[0]);
      Data32^[0] := FManager.AtomWMTakeFocus;
      Data32^[1] := XCB_CURRENT_TIME;
      xcb_send_event(FManager.Connection, 0, FClientWindow, XCB_EVENT_MASK_NO_EVENT, PAnsiChar(@Ev));
    end;

    FManager.RefreshEWMHActiveWindow();
    xcb_flush(FManager.Connection);
  end;

  FManager.DoOnClientActivated(Self);
end;

procedure TXCBWMClient.Close();
var
  Ev: xcb_client_message_event_t;
  Data32: PCardinalArray;
begin
  if not FCanClose then Exit;
  if FManager = nil then Exit;
  if FManager.Connection = nil then Exit;

  if FSupportsDeleteWindow and (FManager.AtomWMDeleteWindow <> 0) then
  begin
    FillChar(Ev, SizeOf(Ev), 0);
    Ev.response_type := XCB_CLIENT_MESSAGE;
    Ev.format := 32;
    Ev.window := FClientWindow;
    Ev.type_ := FManager.FEwmh.WM_PROTOCOLS;
    Data32 := PCardinalArray(@Ev.data.raw[0]);
    Data32^[0] := FManager.AtomWMDeleteWindow;
    Data32^[1] := XCB_CURRENT_TIME;

    xcb_send_event(FManager.Connection, 0, FClientWindow, XCB_EVENT_MASK_NO_EVENT, PAnsiChar(@Ev));
    xcb_flush(FManager.Connection);
  end
  else
  begin
    xcb_kill_client(FManager.Connection, FClientWindow);
    xcb_flush(FManager.Connection);
  end;
end;

procedure TXCBWMClient.Maximize();
var
  TargetRect: TXCBRect;
  TargetMon: TXCBMonitor;
begin
  if not FCanMaximize then Exit;
  // Only update FRestoredRect if not already tiled, maximized, or fullscreen
  if not ((wsMaximizedHorz in FState) or (wsMaximizedVert in FState) or
          (wsTiledLeft in FState) or (wsTiledRight in FState) or
          (wsFullscreen in FState)) then
    FRestoredRect := FCurrentRect;

  Exclude(FState, wsTiledLeft);
  Exclude(FState, wsTiledRight);
  Include(FState, wsMaximizedHorz);
  Include(FState, wsMaximizedVert);

  if FManager <> nil then
  begin
    TargetMon := CurrentMonitor();
    if (TargetMon <> nil) and (TargetMon.Workarea.Width > 0) and (TargetMon.Workarea.Height > 0) then
      TargetRect := TargetMon.Workarea
    else
      TargetRect := FManager.Workarea;

    if (TargetRect.Width <= 0) or (TargetRect.Height <= 0) then
    begin
      if FManager.Screen <> nil then
        TargetRect := TXCBRect.Create(0, 0, FManager.Screen^.width_in_pixels, FManager.Screen^.height_in_pixels)
      else
        TargetRect := TXCBRect.Create(0, 0, 1920, 1080);
    end;
    SetGeometry(TargetRect.X, TargetRect.Y, TargetRect.Width, TargetRect.Height);
    if (FManager.Connection <> nil) and (FResizeWindow <> 0) then
    begin
      xcb_unmap_window(FManager.Connection, FResizeWindow);
      xcb_flush(FManager.Connection);
    end;
  end;

  UpdateEWMHState();
end;

procedure TXCBWMClient.TileLeft();
var
  TargetRect: TXCBRect;
  TargetMon: TXCBMonitor;
  sw, sh: Integer;
begin
  if not FCanResize then Exit;
  if (wsTiledLeft in FState) then Exit;

  // Only update FRestoredRect if not already tiled, maximized, or fullscreen
  if not ((wsMaximizedHorz in FState) or (wsMaximizedVert in FState) or
          (wsTiledLeft in FState) or (wsTiledRight in FState) or
          (wsFullscreen in FState)) then
    FRestoredRect := FCurrentRect;

  Exclude(FState, wsMaximizedHorz);
  Exclude(FState, wsMaximizedVert);
  Exclude(FState, wsFullscreen);
  Exclude(FState, wsTiledRight);
  Include(FState, wsTiledLeft);

  if FManager <> nil then
  begin
    TargetMon := CurrentMonitor();
    if (TargetMon <> nil) and (TargetMon.Workarea.Width > 0) and (TargetMon.Workarea.Height > 0) then
      TargetRect := TargetMon.Workarea
    else
      TargetRect := FManager.Workarea;

    if (TargetRect.Width > 0) and (TargetRect.Height > 0) then
    begin
      sw := TargetRect.Width;
      sh := TargetRect.Height;
      SetGeometry(TargetRect.X, TargetRect.Y, sw div 2, sh);
      UpdateEWMHState();
      Exit;
    end;

    if FManager.Screen <> nil then
    begin
      sw := FManager.Screen^.width_in_pixels;
      sh := FManager.Screen^.height_in_pixels;
    end
    else
    begin
      sw := 1920;
      sh := 1080;
    end;
    SetGeometry(0, 0, sw div 2, sh);
  end;

  UpdateEWMHState();
end;

procedure TXCBWMClient.TileRight();
var
  TargetRect: TXCBRect;
  TargetMon: TXCBMonitor;
  sw, sh: Integer;
begin
  if not FCanResize then Exit;
  if (wsTiledRight in FState) then Exit;

  // Only update FRestoredRect if not already tiled, maximized, or fullscreen
  if not ((wsMaximizedHorz in FState) or (wsMaximizedVert in FState) or
          (wsTiledLeft in FState) or (wsTiledRight in FState) or
          (wsFullscreen in FState)) then
    FRestoredRect := FCurrentRect;

  Exclude(FState, wsMaximizedHorz);
  Exclude(FState, wsMaximizedVert);
  Exclude(FState, wsFullscreen);
  Exclude(FState, wsTiledLeft);
  Include(FState, wsTiledRight);

  if FManager <> nil then
  begin
    TargetMon := CurrentMonitor();
    if (TargetMon <> nil) and (TargetMon.Workarea.Width > 0) and (TargetMon.Workarea.Height > 0) then
      TargetRect := TargetMon.Workarea
    else
      TargetRect := FManager.Workarea;

    if (TargetRect.Width > 0) and (TargetRect.Height > 0) then
    begin
      sw := TargetRect.Width;
      sh := TargetRect.Height;
      SetGeometry(TargetRect.X + (sw div 2), TargetRect.Y, sw - (sw div 2), sh);
      UpdateEWMHState();
      Exit;
    end;

    if FManager.Screen <> nil then
    begin
      sw := FManager.Screen^.width_in_pixels;
      sh := FManager.Screen^.height_in_pixels;
    end
    else
    begin
      sw := 1920;
      sh := 1080;
    end;
    SetGeometry(sw div 2, 0, sw - (sw div 2), sh);
  end;

  UpdateEWMHState();
end;

procedure TXCBWMClient.Restore();
var
  Values: array[0..1] of Cardinal;
  WasMinimized: Boolean;
begin
  WasMinimized := wsMinimized in FState;
  if WasMinimized then
  begin
    Exclude(FState, wsMinimized);
    if (FManager <> nil) and (FManager.Connection <> nil) then
    begin
      if FIsReparented and (FFrameWindow <> 0) then
        xcb_map_window(FManager.Connection, FFrameWindow);
      xcb_map_window(FManager.Connection, FClientWindow);
      if (FResizeWindow <> 0) and not ((wsMaximizedHorz in FState) or (wsFullscreen in FState)) then
        xcb_map_window(FManager.Connection, FResizeWindow);
    end;
    UpdateEWMHState();
    if FManager <> nil then
      FManager.DoOnClientRestored(Self);
  end;

  if (wsMaximizedHorz in FState) or (wsMaximizedVert in FState) or (wsFullscreen in FState) or
     (wsTiledLeft in FState) or (wsTiledRight in FState) then
  begin
    Exclude(FState, wsMaximizedHorz);
    Exclude(FState, wsMaximizedVert);
    Exclude(FState, wsFullscreen);
    Exclude(FState, wsTiledLeft);
    Exclude(FState, wsTiledRight);

    if (FRestoredRect.Width > 0) and (FRestoredRect.Height > 0) then
      SetGeometry(FRestoredRect.X, FRestoredRect.Y, FRestoredRect.Width, FRestoredRect.Height);

    if (FManager <> nil) and (FManager.Connection <> nil) and (FResizeWindow <> 0) then
    begin
      xcb_map_window(FManager.Connection, FResizeWindow);
      if FFrameWindow <> 0 then
      begin
        Values[0] := FFrameWindow;
        Values[1] := XCB_STACK_MODE_BELOW;
        xcb_configure_window(FManager.Connection, FResizeWindow,
                             XCB_CONFIG_WINDOW_SIBLING or XCB_CONFIG_WINDOW_STACK_MODE,
                             @Values[0]);
      end;
      xcb_flush(FManager.Connection);
    end;
    UpdateEWMHState();
  end
  else if WasMinimized and (FManager <> nil) and (FManager.Connection <> nil) and (FResizeWindow <> 0) then
  begin
    xcb_map_window(FManager.Connection, FResizeWindow);
    if FFrameWindow <> 0 then
    begin
      Values[0] := FFrameWindow;
      Values[1] := XCB_STACK_MODE_BELOW;
      xcb_configure_window(FManager.Connection, FResizeWindow,
                           XCB_CONFIG_WINDOW_SIBLING or XCB_CONFIG_WINDOW_STACK_MODE,
                           @Values[0]);
    end;
    xcb_flush(FManager.Connection);
  end;
end;

procedure TXCBWMClient.Minimize();
var
  I: Integer;
  OtherCli, TransCli: TXCBWMClient;
begin
  if not FCanMinimize then Exit;
  if wsMinimized in FState then Exit;

  Include(FState, wsMinimized);
  Exclude(FState, wsFocused);

  if (FManager <> nil) and (FManager.Connection <> nil) then
  begin
    if FIsReparented and (FFrameWindow <> 0) then
      xcb_unmap_window(FManager.Connection, FFrameWindow);
    xcb_unmap_window(FManager.Connection, FClientWindow);
    if FResizeWindow <> 0 then
      xcb_unmap_window(FManager.Connection, FResizeWindow);
    xcb_flush(FManager.Connection);
  end;

  UpdateEWMHState();

  if FManager <> nil then
  begin
    // Minimize transient children belonging to this client
    if FManager.Clients <> nil then
    begin
      for I := 0 to FManager.Clients.Count - 1 do
      begin
        TransCli := TXCBWMClient(FManager.Clients[I]);
        if (TransCli <> Self) and (TransCli.TransientFor = FClientWindow) and
           not (wsMinimized in TransCli.State) then
          TransCli.Minimize();
      end;
    end;

    if FManager.ActiveClient = Self then
    begin
      FManager.ActiveClient := nil;
      for I := FManager.Clients.Count - 1 downto 0 do
      begin
        OtherCli := TXCBWMClient(FManager.Clients[I]);
        if (OtherCli <> Self) and not (wsMinimized in OtherCli.State) and OtherCli.IsReparented then
        begin
          OtherCli.Activate();
          Break;
        end;
      end;
    end;
    FManager.DoOnClientMinimized(Self);
  end;
end;

procedure TXCBWMClient.Unminimize();
begin
  if not (wsMinimized in FState) then Exit;
  Activate();
end;

procedure TXCBWMClient.SetFullscreen(const AFullscreen: Boolean);
var
  TargetMon: TXCBMonitor;
  X, Y, W, H: Integer;
begin
  if AFullscreen and not FCanMaximize then Exit;
  if AFullscreen = (wsFullscreen in FState) then Exit;

  if AFullscreen then
  begin
    if not ((wsMaximizedHorz in FState) or (wsMaximizedVert in FState) or
            (wsTiledLeft in FState) or (wsTiledRight in FState) or
            (wsFullscreen in FState)) then
      FRestoredRect := FCurrentRect;

    Include(FState, wsFullscreen);
    if FManager <> nil then
    begin
      TargetMon := CurrentMonitor();
      if TargetMon <> nil then
      begin
        X := TargetMon.Rect.X;
        Y := TargetMon.Rect.Y;
        W := TargetMon.Rect.Width;
        H := TargetMon.Rect.Height;
      end
      else if FManager.Screen <> nil then
      begin
        X := 0;
        Y := 0;
        W := FManager.Screen^.width_in_pixels;
        H := FManager.Screen^.height_in_pixels;
      end
      else
      begin
        X := 0;
        Y := 0;
        W := 1920;
        H := 1080;
      end;
      SetGeometry(X, Y, W, H);
      if (FManager.Connection <> nil) and (FResizeWindow <> 0) then
      begin
        xcb_unmap_window(FManager.Connection, FResizeWindow);
        xcb_flush(FManager.Connection);
      end;
    end;
    UpdateEWMHState();
  end
  else
    Restore();
end;

procedure TXCBWMClient.Move(const AX, AY: Integer);
begin
  SetGeometry(AX, AY, FCurrentRect.Width, FCurrentRect.Height);
end;

procedure TXCBWMClient.Resize(const AWidth, AHeight: Integer);
begin
  SetGeometry(FCurrentRect.X, FCurrentRect.Y, AWidth, AHeight);
end;

procedure TXCBWMClient.SetGeometry(const AX, AY, AWidth, AHeight: Integer);
var
  Values: array[0..3] of Cardinal;
  InnerRect: TXCBRect;
begin
  FCurrentRect.X := AX;
  FCurrentRect.Y := AY;
  FCurrentRect.Width := AWidth;
  FCurrentRect.Height := AHeight;

  // Keep FRestoredRect updated whenever the window is in normal (floating) state
  if not ((wsMaximizedHorz in FState) or (wsMaximizedVert in FState) or
          (wsFullscreen in FState) or (wsTiledLeft in FState) or (wsTiledRight in FState)) then
    FRestoredRect := FCurrentRect;

  if FManager = nil then Exit;
  if FManager.Connection = nil then Exit;

  if FIsReparented and (FFrameWindow <> 0) then
  begin
    // Outer frame geometry
    Values[0] := AX;
    Values[1] := AY;
    Values[2] := AWidth;
    Values[3] := AHeight;
    xcb_configure_window(
      FManager.Connection,
      FFrameWindow,
      XCB_CONFIG_WINDOW_X or XCB_CONFIG_WINDOW_Y or
      XCB_CONFIG_WINDOW_WIDTH or XCB_CONFIG_WINDOW_HEIGHT,
      @Values[0]
    );

    // Inner client geometry
    InnerRect := FManager.FrameMetrics.FrameToClientInnerRect(FCurrentRect);
    Values[0] := InnerRect.X;
    Values[1] := InnerRect.Y;
    Values[2] := InnerRect.Width;
    Values[3] := InnerRect.Height;
    xcb_configure_window(
      FManager.Connection,
      FClientWindow,
      XCB_CONFIG_WINDOW_X or XCB_CONFIG_WINDOW_Y or
      XCB_CONFIG_WINDOW_WIDTH or XCB_CONFIG_WINDOW_HEIGHT,
      @Values[0]
    );

    // Outer input-only resize frame geometry
    if FResizeWindow <> 0 then
    begin
      Values[0] := AX - 8;
      Values[1] := AY - 8;
      Values[2] := AWidth + 16;
      Values[3] := AHeight + 16;
      xcb_configure_window(
        FManager.Connection,
        FResizeWindow,
        XCB_CONFIG_WINDOW_X or XCB_CONFIG_WINDOW_Y or
        XCB_CONFIG_WINDOW_WIDTH or XCB_CONFIG_WINDOW_HEIGHT,
        @Values[0]
      );
    end;
  end
  else
  begin
    Values[0] := AX;
    Values[1] := AY;
    Values[2] := AWidth;
    Values[3] := AHeight;
    xcb_configure_window(
      FManager.Connection,
      FClientWindow,
      XCB_CONFIG_WINDOW_X or XCB_CONFIG_WINDOW_Y or
      XCB_CONFIG_WINDOW_WIDTH or XCB_CONFIG_WINDOW_HEIGHT,
      @Values[0]
    );
  end;

  xcb_flush(FManager.Connection);
  FManager.DoOnClientConfigure(Self);
end;

procedure TXCBWMClient.SetDesktop(const ADesktopIndex: Integer);
begin
  FDesktop := ADesktopIndex;
  if FManager = nil then Exit;

  if ShouldBeVisibleOnDesktop(FManager.CurrentDesktop) then
  begin
    if (not (wsMinimized in FState)) and (FManager.Connection <> nil) then
    begin
      if FIsReparented and (FFrameWindow <> 0) then
        xcb_map_window(FManager.Connection, FFrameWindow);
      xcb_map_window(FManager.Connection, FClientWindow);
      xcb_flush(FManager.Connection);
    end;
  end
  else
  begin
    if FManager.Connection <> nil then
    begin
      if FIsReparented and (FFrameWindow <> 0) then
        xcb_unmap_window(FManager.Connection, FFrameWindow);
      xcb_flush(FManager.Connection);
    end;
    if FManager.ActiveClient = Self then
      FManager.ActiveClient := nil;
  end;
end;

procedure TXCBWMClient.SetSticky(const ASticky: Boolean);
begin
  if ASticky then
  begin
    Include(FState, wsSticky);
    FDesktop := Integer(XCB_ALL_DESKTOPS);
  end
  else
  begin
    Exclude(FState, wsSticky);
    if FManager <> nil then
      FDesktop := FManager.CurrentDesktop
    else
      FDesktop := 0;
  end;
end;

function TXCBWMClient.ConstrainSize(const AWidth, AHeight: Integer): TXCBPoint;
var
  W, H: Integer;
begin
  if not FCanResize then
  begin
    Result.X := FCurrentRect.Width;
    Result.Y := FCurrentRect.Height;
    Exit;
  end;

  W := AWidth;
  H := AHeight;

  // Min dimensions
  if (FMinSize.X > 0) and (W < FMinSize.X) then W := FMinSize.X;
  if (FMinSize.Y > 0) and (H < FMinSize.Y) then H := FMinSize.Y;

  // Max dimensions
  if (FMaxSize.X > 0) and (W > FMaxSize.X) then W := FMaxSize.X;
  if (FMaxSize.Y > 0) and (H > FMaxSize.Y) then H := FMaxSize.Y;

  // Increments
  if FSizeInc.X > 1 then
    W := FBaseSize.X + ((W - FBaseSize.X) div FSizeInc.X) * FSizeInc.X;
  if FSizeInc.Y > 1 then
    H := FBaseSize.Y + ((H - FBaseSize.Y) div FSizeInc.Y) * FSizeInc.Y;

  Result.X := W;
  Result.Y := H;
end;

function TXCBWMClient.ShouldBeVisibleOnDesktop(const ACurrentDesktop: Integer): Boolean;
begin
  Result := (wsSticky in FState) or
            (Cardinal(FDesktop) = XCB_ALL_DESKTOPS) or
            (FDesktop = ACurrentDesktop);
end;

function TXCBWMClient.TitlebarRect(): TXCBRect;
begin
  Result := TXCBRect.Create(0, 0, 0, 0);
  if not FIsReparented then Exit;
  if FManager = nil then Exit;

  Result.X := 0;
  Result.Y := 0;
  Result.Width := FCurrentRect.Width;
  Result.Height := FManager.FrameMetrics.TitlebarHeight + FManager.FrameMetrics.BorderWidth;
end;

function TXCBWMClient.IsMenu(): Boolean;
begin
  Result := FWindowType in [wtMenu, wtDropdownMenu, wtPopupMenu, wtCombo];
end;

function TXCBWMClient.IsDecorated(): Boolean;
begin
  Result := FIsReparented and not FBorderless and (FWindowType in [wtNormal, wtDialog]);
end;

function TXCBWMClient.CurrentMonitor(): TXCBMonitor;
begin
  if FManager <> nil then
    Result := FManager.MonitorForClient(Self)
  else
    Result := nil;
end;

// ============================================================================
// TXCBWindowManager
// ============================================================================

constructor TXCBWindowManager.Create(AConn: Pxcb_connection_t = nil; const AScreenNum: Integer = 0);
var
  Setup: Pxcb_setup_t;
  ScreenIter: xcb_screen_iterator_t;
  I: Integer;
begin
  inherited Create();
  FConn := AConn;
  FScreenNum := AScreenNum;
  FScreen := nil;
  FRootWindow := 0;
  FEwmhInitialized := False;
  FWMCheckWindow := 0;
  FWMName := 'FloriaWM';
  FFrameMetrics := TXCBFrameMetrics.Create(24, 1);
  FClients := TObjectList.Create(True);
  FActiveClient := nil;
  FDesktopCount := 4;
  FCurrentDesktop := 0;
  FDesktopNames := TStringList.Create();
  FDesktopNames.Add('1');
  FDesktopNames.Add('2');
  FDesktopNames.Add('3');
  FDesktopNames.Add('4');
  FIsRunning := False;
  FShutdownRequested := False;
  FWakeupPipe[0] := -1;
  FWakeupPipe[1] := -1;
  FWakeupPipeValid := False;
  FTickIntervalMs := 16;
  FKeycodeTab := 0;
  FKeycodeSpace := 0;
  FKeycodeLeft := 0;
  FKeycodeRight := 0;
  FKeycodeUp := 0;
  FKeycodeDown := 0;
  FKeycodeEscape := 0;
  FKeycodeReturn := 0;
  FKeycodeAltL := 0;
  FKeycodeAltR := 0;
  FKeycodeD := 0;
  FModAlt := 0;
  FModSuper := 0;
  FModNumLock := 0;
  FModCapsLock := 0;
  FKeyBindingsValid := False;
  FSyncingFocus := False;
  FMruClients := TFPList.Create();
  FWorkarea := TXCBRect.Create(0, 0, 1920, 1080);
  FAtomWMDeleteWindow := 0;
  FAtomWMTakeFocus := 0;
  FAtomMotifWmHints := 0;
  FAtomNetWmStrut := 0;
  FAtomNetWmStrutPartial := 0;
  FAtomWMChangeState := 0;
  FAtomWMState := 0;
  FDragClient := nil;
  FDragMode := dmNone;
  FDragStartPointer := TXCBPoint.Create(0, 0);
  FDragStartRect := TXCBRect.Create(0, 0, 0, 0);
  FDragGrabFailureHook := nil;
  FOnFramePaint := nil;

  FCursorCtx := nil;
  FCursorNormal := 0;
  FCursorMove := 0;
  FCursorResizeLeft := 0;
  FCursorResizeRight := 0;
  FCursorResizeTop := 0;
  FCursorResizeBottom := 0;
  FCursorResizeTopLeft := 0;
  FCursorResizeTopRight := 0;
  FCursorResizeBottomLeft := 0;
  FCursorResizeBottomRight := 0;
  FCurrentRootCursor := 0;

  FMonitors := TObjectList.Create(True);
  FPrimaryMonitor := nil;
  FRandRAvailable := False;
  FRandREventBase := 0;
  FRandRErrorBase := 0;

  if FConn <> nil then
  begin
    Setup := xcb_get_setup(FConn);
    if Setup <> nil then
    begin
      ScreenIter := xcb_setup_roots_iterator(Setup);
      for I := 0 to FScreenNum - 1 do
      begin
        if ScreenIter.rem > 0 then
          xcb_screen_next(@ScreenIter);
      end;
      if ScreenIter.data <> nil then
      begin
        FScreen := ScreenIter.data;
        FRootWindow := FScreen^.root;
        FWorkarea := TXCBRect.Create(0, 0, FScreen^.width_in_pixels, FScreen^.height_in_pixels);
      end;
    end;

    FAtomWMDeleteWindow := InternAtom(FConn, 'WM_DELETE_WINDOW');
    FAtomWMTakeFocus := InternAtom(FConn, 'WM_TAKE_FOCUS');
    FAtomMotifWmHints := InternAtom(FConn, '_MOTIF_WM_HINTS');
    FAtomNetWmStrut := InternAtom(FConn, '_NET_WM_STRUT');
    FAtomNetWmStrutPartial := InternAtom(FConn, '_NET_WM_STRUT_PARTIAL');
    FAtomWMChangeState := InternAtom(FConn, 'WM_CHANGE_STATE');
    FAtomWMState := InternAtom(FConn, 'WM_STATE');
    InitCursors();
  end;

  // Populate the binding table immediately so an offline manager (unit tests)
  // has a usable, documented default; a live one re-resolves in ClaimOwnership.
  ResolveKeyBindings();

  RefreshMonitors();
end;

destructor TXCBWindowManager.Destroy();
var
  I: Integer;
  Cli: TXCBWMClient;
  SyncReply: Pxcb_get_input_focus_reply_t;
begin
  // Hand clients back to the root window before tearing anything down. Frame
  // windows are children of root and belong to this connection, so letting the
  // server reap them destroys every application reparented inside them. A window
  // manager must be restartable without taking the user's session with it.
  if (FConn <> nil) and (FClients <> nil) then
  begin
    for I := 0 to FClients.Count - 1 do
    begin
      Cli := TXCBWMClient(FClients[I]);
      if (Cli <> nil) and Cli.IsReparented then
      begin
        UnparentClient(Cli);
        // Minimized clients stay unmapped; everything else is visible again.
        if not (wsMinimized in Cli.State) then
          xcb_map_window(FConn, Cli.ClientWindow);
      end;
    end;

    // Force the server to process every teardown request before this connection
    // closes. Without the round-trip the reparents can still be sitting in the
    // outgoing buffer when xcb_disconnect runs; the server then frees the
    // connection-owned frame windows with the clients still inside them, killing
    // every application. The round-trip is the whole point, not a formality.
    xcb_flush(FConn);
    SyncReply := xcb_get_input_focus_reply(FConn, xcb_get_input_focus(FConn), nil);
    if SyncReply <> nil then
      xcb_free(SyncReply);
  end;

  if FCursorCtx <> nil then
  begin
    xcb_cursor_context_free(FCursorCtx);
    FCursorCtx := nil;
  end;
  FMruClients.Free();
  FClients.Free();
  FDesktopNames.Free();
  FMonitors.Free();
  inherited Destroy();
end;

procedure TXCBWindowManager.InitCursors();
begin
  if (FConn = nil) or (FScreen = nil) then Exit;

  FCursorCtx := nil;
  if xcb_cursor_context_new(FConn, FScreen, @FCursorCtx) = 0 then
  begin
    FCursorNormal := LoadCursor(['left_ptr', 'default']);
    FCursorMove := LoadCursor(['fleur', 'grabbing', 'move']);
    FCursorResizeLeft := LoadCursor(['left_side', 'sb_h_double_arrow', 'w-resize', 'ew-resize']);
    FCursorResizeRight := LoadCursor(['right_side', 'sb_h_double_arrow', 'e-resize', 'ew-resize']);
    FCursorResizeTop := LoadCursor(['top_side', 'sb_v_double_arrow', 'n-resize', 'ns-resize']);
    FCursorResizeBottom := LoadCursor(['bottom_side', 'sb_v_double_arrow', 's-resize', 'ns-resize']);
    FCursorResizeTopLeft := LoadCursor(['top_left_corner', 'nw-resize', 'nwse-resize']);
    FCursorResizeTopRight := LoadCursor(['top_right_corner', 'ne-resize', 'nesw-resize']);
    FCursorResizeBottomLeft := LoadCursor(['bottom_left_corner', 'sw-resize', 'nesw-resize']);
    FCursorResizeBottomRight := LoadCursor(['bottom_right_corner', 'se-resize', 'nwse-resize']);
  end;
end;

function TXCBWindowManager.LoadCursor(const ANames: array of PChar): xcb_cursor_t;
var
  i: Integer;
begin
  Result := 0;
  if FCursorCtx = nil then Exit;
  for i := Low(ANames) to High(ANames) do
  begin
    if ANames[i] <> nil then
    begin
      Result := xcb_cursor_load_cursor(FCursorCtx, ANames[i]);
      if Result <> 0 then Break;
    end;
  end;
end;

function TXCBWindowManager.CursorForDragMode(const AMode: TXCBDragMode): xcb_cursor_t;
begin
  case AMode of
    dmMove: Result := FCursorMove;
    dmResizeLeft: Result := FCursorResizeLeft;
    dmResizeRight: Result := FCursorResizeRight;
    dmResizeTop: Result := FCursorResizeTop;
    dmResizeBottom: Result := FCursorResizeBottom;
    dmResizeTopLeft: Result := FCursorResizeTopLeft;
    dmResizeTopRight: Result := FCursorResizeTopRight;
    dmResizeBottomLeft: Result := FCursorResizeBottomLeft;
    dmResizeBottomRight: Result := FCursorResizeBottomRight;
    dmResize: Result := FCursorResizeBottomRight;
  else
    Result := FCursorNormal;
  end;
  if Result = 0 then
    Result := FCursorNormal;
end;

procedure TXCBWindowManager.SetWindowCursor(const AWindow: xcb_window_t; const ACursor: xcb_cursor_t);
var
  Values: array[0..0] of Cardinal;
begin
  if (FConn = nil) or (AWindow = 0) or (ACursor = 0) then Exit;
  Values[0] := ACursor;
  xcb_change_window_attributes(FConn, AWindow, XCB_CW_CURSOR, @Values[0]);
  xcb_flush(FConn);
end;

// Resolve a keysym to a keycode using the server's current keyboard mapping.
// Xlib's XKeysymToKeycode scans every keysym column, not just the first, because
// a keysym may only be reachable through a shift level. Returns 0 when unmapped.
function TXCBWindowManager.KeysymToKeycode(const AKeysym: Cardinal): xcb_keycode_t;
var
  Cookie: xcb_get_keyboard_mapping_cookie_t;
  Reply: Pxcb_get_keyboard_mapping_reply_t;
  Syms: Pxcb_keysym_t;
  Setup: Pxcb_setup_t;
  MinKc, MaxKc, Kc: Integer;
  PerKeycode, Col, Idx: Integer;
begin
  Result := 0;
  if (FConn = nil) or (AKeysym = 0) then Exit;

  Setup := xcb_get_setup(FConn);
  if Setup = nil then Exit;

  MinKc := Setup^.min_keycode;
  MaxKc := Setup^.max_keycode;
  if (MaxKc < MinKc) then Exit;

  Cookie := xcb_get_keyboard_mapping(FConn, MinKc, Byte(MaxKc - MinKc + 1));
  Reply := xcb_get_keyboard_mapping_reply(FConn, Cookie, nil);
  if Reply = nil then Exit;

  try
    PerKeycode := Reply^.keysyms_per_keycode;
    if PerKeycode <= 0 then Exit;

    Syms := xcb_get_keyboard_mapping_keysyms(Reply);
    if Syms = nil then Exit;

    for Kc := MinKc to MaxKc do
    begin
      for Col := 0 to PerKeycode - 1 do
      begin
        Idx := (Kc - MinKc) * PerKeycode + Col;
        if Pxcb_keysym_t(PByte(Syms) + Idx * SizeOf(xcb_keysym_t))^ = AKeysym then
        begin
          Result := xcb_keycode_t(Kc);
          Exit;
        end;
      end;
    end;
  finally
    xcb_free(Reply);
  end;
end;

// Which modifier bit (Mod1..Mod5 / Shift / Lock / Control) carries this keycode.
// Returns 0 when the keycode is not part of any modifier set.
function TXCBWindowManager.KeycodeToModifierMask(const AKeycode: xcb_keycode_t): Word;
var
  Cookie: xcb_get_modifier_mapping_cookie_t;
  Reply: Pxcb_get_modifier_mapping_reply_t;
  Keycodes: Pxcb_keycode_t;
  PerModifier: Integer;
  ModIdx, Slot: Integer;
begin
  Result := 0;
  if (FConn = nil) or (AKeycode = 0) then Exit;

  Cookie := xcb_get_modifier_mapping(FConn);
  Reply := xcb_get_modifier_mapping_reply(FConn, Cookie, nil);
  if Reply = nil then Exit;

  try
    PerModifier := Reply^.keycodes_per_modifier;
    if PerModifier <= 0 then Exit;

    Keycodes := xcb_get_modifier_mapping_keycodes(Reply);
    if Keycodes = nil then Exit;

    // 8 modifier rows: Shift, Lock, Control, Mod1..Mod5
    for ModIdx := 0 to 7 do
    begin
      for Slot := 0 to PerModifier - 1 do
      begin
        if PByte(Keycodes)[ModIdx * PerModifier + Slot] = AKeycode then
        begin
          Result := Word(1) shl ModIdx;
          Exit;
        end;
      end;
    end;
  finally
    xcb_free(Reply);
  end;
end;

// Rebuild the binding table from the server. Safe to call repeatedly; used both
// at startup and after XCB_MAPPING_NOTIFY.
procedure TXCBWindowManager.ResolveKeyBindings();
var
  AltKc, SuperKc, NumKc, CapsKc: xcb_keycode_t;
begin
  FKeycodeTab := 0;
  FKeycodeSpace := 0;
  FKeycodeLeft := 0;
  FKeycodeRight := 0;
  FKeycodeUp := 0;
  FKeycodeDown := 0;
  FKeycodeEscape := 0;
  FKeycodeReturn := 0;
  FKeycodeAltL := 0;
  FKeycodeAltR := 0;
  FModAlt := 0;
  FModSuper := 0;
  FModNumLock := 0;
  FModCapsLock := 0;
  FKeyBindingsValid := False;

  if FConn = nil then
  begin
    // No server to query (headless unit tests, or before xcb_connect). Fall back
    // to the standard evdev/US table so the binding state machine is testable.
    // This is the only place these constants are allowed to appear: on a live
    // connection everything below is resolved from the server.
    FKeycodeTab := 23;      // XK_Tab
    FKeycodeSpace := 65;    // XK_space
    FKeycodeLeft := 113;
    FKeycodeRight := 114;
    FKeycodeUp := 111;
    FKeycodeDown := 116;
    FKeycodeEscape := 9;
    FKeycodeReturn := 36;
    FKeycodeAltL := 64;
    FKeycodeAltR := 108;
    FKeycodeD := 40;
    FModAlt := XCB_MOD_MASK_1;
    FModSuper := XCB_MOD_MASK_4;
    FModNumLock := XCB_MOD_MASK_2;
    FModCapsLock := XCB_MOD_MASK_LOCK;
    FKeyBindingsValid := True;
    Exit;
  end;

  FKeycodeTab := KeysymToKeycode(XK_Tab);
  FKeycodeSpace := KeysymToKeycode(XK_space);
  FKeycodeLeft := KeysymToKeycode(XK_Left);
  FKeycodeRight := KeysymToKeycode(XK_Right);
  FKeycodeUp := KeysymToKeycode(XK_Up);
  FKeycodeDown := KeysymToKeycode(XK_Down);
  FKeycodeEscape := KeysymToKeycode(XK_Escape);
  FKeycodeReturn := KeysymToKeycode(XK_Return);
  FKeycodeAltL := KeysymToKeycode(XK_Alt_L);
  FKeycodeAltR := KeysymToKeycode(XK_Alt_R);
  FKeycodeD := KeysymToKeycode(XK_d_);

  // Alt is conventionally Mod1 and Super Mod4, but neither is guaranteed: a user
  // can remap them, and on some layouts Alt lives on Mod5. Ask the server.
  AltKc := KeysymToKeycode(XK_Alt_L);
  if AltKc = 0 then AltKc := KeysymToKeycode(XK_Alt_R);
  FModAlt := KeycodeToModifierMask(AltKc);

  SuperKc := KeysymToKeycode(XK_Super_L);
  if SuperKc = 0 then SuperKc := KeysymToKeycode(XK_Super_R);
  FModSuper := KeycodeToModifierMask(SuperKc);

  NumKc := KeysymToKeycode(XK_Num_Lock);
  FModNumLock := KeycodeToModifierMask(NumKc);

  CapsKc := KeysymToKeycode(XK_Caps_Lock);
  FModCapsLock := KeycodeToModifierMask(CapsKc);

  // Fall back to the historical constants when the map cannot be read (for
  // example a server that reports no Alt_L keysym at all).
  if FModAlt = 0 then FModAlt := XCB_MOD_MASK_1;
  if FModSuper = 0 then FModSuper := XCB_MOD_MASK_4;
  if FModNumLock = 0 then FModNumLock := XCB_MOD_MASK_2;

  FKeyBindingsValid := (FKeycodeTab <> 0);
end;

procedure TXCBWindowManager.RebindGlobalKeys();
begin
  // Default: nothing to re-grab. Shells override.
end;

function TXCBWindowManager.ClaimOwnership(): Boolean;
var
  Values: array[0..0] of Cardinal;
  Cookie: xcb_void_cookie_t;
  Err: Pxcb_generic_error_t;
  extReply: Pxcb_query_extension_reply_t;
begin
  Result := False;
  if (FConn = nil) or (FRootWindow = 0) then Exit;

  Values[0] := XCB_EVENT_MASK_SUBSTRUCTURE_REDIRECT or
               XCB_EVENT_MASK_SUBSTRUCTURE_NOTIFY or
               XCB_EVENT_MASK_STRUCTURE_NOTIFY or
               XCB_EVENT_MASK_PROPERTY_CHANGE or
               XCB_EVENT_MASK_BUTTON_PRESS or
               XCB_EVENT_MASK_BUTTON_RELEASE or
               XCB_EVENT_MASK_POINTER_MOTION or
               XCB_EVENT_MASK_ENTER_WINDOW or
               XCB_EVENT_MASK_LEAVE_WINDOW or
               XCB_EVENT_MASK_FOCUS_CHANGE;

  Cookie := xcb_change_window_attributes_checked(
    FConn,
    FRootWindow,
    XCB_CW_EVENT_MASK,
    @Values[0]
  );

  Err := xcb_request_check(FConn, Cookie);
  if Err <> nil then
  begin
    xcb_free(Err);
    Result := False;
    Exit;
  end;

  if FCursorNormal <> 0 then
  begin
    SetWindowCursor(FRootWindow, FCursorNormal);
    FCurrentRootCursor := FCursorNormal;
  end;

  // Resolve keycodes and modifier masks from the live server. Doing this here
  // rather than at construction means a layout already in effect is honoured,
  // and a later XCB_MAPPING_NOTIFY re-runs it.
  ResolveKeyBindings();

  // RandR extension initialization
  extReply := xcb_get_extension_data(FConn, @xcb_randr_id);
  if (extReply <> nil) and (extReply^.present <> 0) then
  begin
    FRandRAvailable := True;
    FRandREventBase := extReply^.first_event;
    FRandRErrorBase := extReply^.first_error;

    xcb_randr_select_input(
      FConn,
      FRootWindow,
      XCB_RANDR_NOTIFY_MASK_SCREEN_CHANGE or
      XCB_RANDR_NOTIFY_MASK_CRTC_CHANGE or
      XCB_RANDR_NOTIFY_MASK_OUTPUT_CHANGE
    );
  end;

  RefreshMonitors();

  Result := True;
end;

procedure TXCBWindowManager.InitEWMH();
var
  Cookies: Pxcb_intern_atom_cookie_t;
  SuppAtoms: array[0..51] of xcb_atom_t;
begin
  if (FConn = nil) or (FRootWindow = 0) then Exit;

  Cookies := xcb_ewmh_init_atoms(FConn, @FEwmh);
  if Cookies <> nil then
  begin
    if xcb_ewmh_init_atoms_replies(@FEwmh, Cookies, nil) = 1 then
      FEwmhInitialized := True;
  end;

  if not FEwmhInitialized then Exit;

  // Create supporting WM check window
  FWMCheckWindow := xcb_generate_id(FConn);
  xcb_create_window(
    FConn,
    XCB_COPY_FROM_PARENT,
    FWMCheckWindow,
    FRootWindow,
    -1, -1, 1, 1, 0,
    XCB_WINDOW_CLASS_INPUT_ONLY,
    XCB_COPY_FROM_PARENT,
    0,
    nil
  );

  // Set _NET_SUPPORTING_WM_CHECK on root window and check window
  xcb_change_property(
    FConn,
    XCB_PROP_MODE_REPLACE,
    FRootWindow,
    FEwmh._NET_SUPPORTING_WM_CHECK,
    XCB_ATOM_WINDOW,
    32,
    1,
    @FWMCheckWindow
  );

  xcb_change_property(
    FConn,
    XCB_PROP_MODE_REPLACE,
    FWMCheckWindow,
    FEwmh._NET_SUPPORTING_WM_CHECK,
    XCB_ATOM_WINDOW,
    32,
    1,
    @FWMCheckWindow
  );

  // Set _NET_WM_NAME on check window
  if Length(FWMName) > 0 then
  begin
    xcb_change_property(
      FConn,
      XCB_PROP_MODE_REPLACE,
      FWMCheckWindow,
      FEwmh._NET_WM_NAME,
      FEwmh.UTF8_STRING,
      8,
      Length(FWMName),
      PAnsiChar(FWMName)
    );
  end;

  // Publish _NET_SUPPORTED
  SuppAtoms[0] := FEwmh._NET_SUPPORTED;
  SuppAtoms[1] := FEwmh._NET_SUPPORTING_WM_CHECK;
  SuppAtoms[2] := FEwmh._NET_WM_NAME;
  SuppAtoms[3] := FEwmh._NET_CLIENT_LIST;
  SuppAtoms[4] := FEwmh._NET_CLIENT_LIST_STACKING;
  SuppAtoms[5] := FEwmh._NET_ACTIVE_WINDOW;
  SuppAtoms[6] := FEwmh._NET_NUMBER_OF_DESKTOPS;
  SuppAtoms[7] := FEwmh._NET_CURRENT_DESKTOP;
  SuppAtoms[8] := FEwmh._NET_DESKTOP_NAMES;
  SuppAtoms[9] := FEwmh._NET_WORKAREA;
  SuppAtoms[10] := FEwmh._NET_WM_WINDOW_TYPE;
  SuppAtoms[11] := FEwmh._NET_WM_STATE;
  SuppAtoms[12] := FEwmh._NET_CLOSE_WINDOW;
  SuppAtoms[13] := FEwmh._NET_WM_MOVERESIZE;
  SuppAtoms[14] := FEwmh._NET_WM_PID;
  SuppAtoms[15] := FEwmh._NET_WM_DESKTOP;
  SuppAtoms[16] := FEwmh._NET_WM_STRUT;
  SuppAtoms[17] := FEwmh._NET_WM_STRUT_PARTIAL;
  SuppAtoms[18] := FEwmh._NET_WM_STATE_MAXIMIZED_HORZ;
  SuppAtoms[19] := FEwmh._NET_WM_STATE_MAXIMIZED_VERT;
  SuppAtoms[20] := FEwmh._NET_WM_STATE_FULLSCREEN;
  SuppAtoms[21] := FEwmh._NET_WM_STATE_HIDDEN;
  SuppAtoms[22] := FEwmh._NET_WM_STATE_ABOVE;
  SuppAtoms[23] := FEwmh._NET_SHOWING_DESKTOP;
  SuppAtoms[24] := FEwmh._NET_WM_WINDOW_TYPE_NORMAL;
  SuppAtoms[25] := FEwmh._NET_WM_WINDOW_TYPE_DIALOG;
  SuppAtoms[26] := FEwmh._NET_WM_WINDOW_TYPE_DOCK;
  SuppAtoms[27] := FEwmh._NET_WM_WINDOW_TYPE_DESKTOP;
  SuppAtoms[28] := FEwmh._NET_WM_WINDOW_TYPE_TOOLBAR;
  SuppAtoms[29] := FEwmh._NET_WM_WINDOW_TYPE_MENU;
  SuppAtoms[30] := FEwmh._NET_WM_WINDOW_TYPE_POPUP_MENU;
  SuppAtoms[31] := FEwmh._NET_WM_WINDOW_TYPE_DROPDOWN_MENU;
  SuppAtoms[32] := FEwmh._NET_WM_WINDOW_TYPE_TOOLTIP;
  SuppAtoms[33] := FEwmh._NET_WM_WINDOW_TYPE_NOTIFICATION;
  SuppAtoms[34] := FEwmh._NET_WM_WINDOW_TYPE_COMBO;
  SuppAtoms[35] := FEwmh._NET_WM_WINDOW_TYPE_UTILITY;
  SuppAtoms[36] := FEwmh._NET_WM_WINDOW_TYPE_SPLASH;
  SuppAtoms[37] := FEwmh._NET_MOVERESIZE_WINDOW;
  SuppAtoms[38] := FEwmh._NET_FRAME_EXTENTS;
  SuppAtoms[39] := FEwmh._NET_REQUEST_FRAME_EXTENTS;
  SuppAtoms[40] := FEwmh._NET_WM_ALLOWED_ACTIONS;
  SuppAtoms[41] := FEwmh._NET_WM_ACTION_MOVE;
  SuppAtoms[42] := FEwmh._NET_WM_ACTION_RESIZE;
  SuppAtoms[43] := FEwmh._NET_WM_ACTION_MINIMIZE;
  SuppAtoms[44] := FEwmh._NET_WM_ACTION_SHADE;
  SuppAtoms[45] := FEwmh._NET_WM_ACTION_STICK;
  SuppAtoms[46] := FEwmh._NET_WM_ACTION_MAXIMIZE_HORZ;
  SuppAtoms[47] := FEwmh._NET_WM_ACTION_MAXIMIZE_VERT;
  SuppAtoms[48] := FEwmh._NET_WM_ACTION_FULLSCREEN;
  SuppAtoms[49] := FEwmh._NET_WM_ACTION_CHANGE_DESKTOP;
  SuppAtoms[50] := FEwmh._NET_WM_ACTION_CLOSE;
  SuppAtoms[51] := FEwmh._NET_WM_ACTION_ABOVE;

  xcb_change_property(
    FConn,
    XCB_PROP_MODE_REPLACE,
    FRootWindow,
    FEwmh._NET_SUPPORTED,
    XCB_ATOM_ATOM,
    32,
    52,
    @SuppAtoms[0]
  );

  RefreshEWMHDesktop();
  RefreshEWMHClientList();
  xcb_flush(FConn);
end;

procedure TXCBWindowManager.UpdateAllowedActions(const AClient: TXCBWMClient);
var
  Actions: array[0..11] of xcb_atom_t;
  Count: Integer;
begin
  if (FConn = nil) or (AClient = nil) or (not FEwmhInitialized) then Exit;

  Count := 0;
  // Move is always supported for normal managed windows
  Actions[Count] := FEwmh._NET_WM_ACTION_MOVE;
  Inc(Count);

  if AClient.CanResize then
  begin
    Actions[Count] := FEwmh._NET_WM_ACTION_RESIZE;
    Inc(Count);
  end;

  if AClient.CanMinimize then
  begin
    Actions[Count] := FEwmh._NET_WM_ACTION_MINIMIZE;
    Inc(Count);
  end;

  if AClient.CanMaximize then
  begin
    Actions[Count] := FEwmh._NET_WM_ACTION_MAXIMIZE_HORZ;
    Inc(Count);
    Actions[Count] := FEwmh._NET_WM_ACTION_MAXIMIZE_VERT;
    Inc(Count);
    Actions[Count] := FEwmh._NET_WM_ACTION_FULLSCREEN;
    Inc(Count);
  end;

  Actions[Count] := FEwmh._NET_WM_ACTION_CHANGE_DESKTOP;
  Inc(Count);
  Actions[Count] := FEwmh._NET_WM_ACTION_STICK;
  Inc(Count);
  Actions[Count] := FEwmh._NET_WM_ACTION_ABOVE;
  Inc(Count);

  if AClient.CanClose then
  begin
    Actions[Count] := FEwmh._NET_WM_ACTION_CLOSE;
    Inc(Count);
  end;

  xcb_change_property(
    FConn,
    XCB_PROP_MODE_REPLACE,
    AClient.ClientWindow,
    FEwmh._NET_WM_ALLOWED_ACTIONS,
    XCB_ATOM_ATOM,
    32,
    Count,
    @Actions[0]
  );
end;

procedure TXCBWindowManager.RefreshEWMHClientList();
var
  WinList: array of xcb_window_t;
  I, Count: Integer;
begin
  if (FConn = nil) or (not FEwmhInitialized) then Exit;

  Count := FClients.Count;
  SetLength(WinList, Count);
  for I := 0 to Count - 1 do
    WinList[I] := TXCBWMClient(FClients[I]).ClientWindow;

  if Count > 0 then
    xcb_change_property(
      FConn,
      XCB_PROP_MODE_REPLACE,
      FRootWindow,
      FEwmh._NET_CLIENT_LIST,
      XCB_ATOM_WINDOW,
      32,
      Count,
      @WinList[0]
    )
  else
    xcb_change_property(
      FConn,
      XCB_PROP_MODE_REPLACE,
      FRootWindow,
      FEwmh._NET_CLIENT_LIST,
      XCB_ATOM_WINDOW,
      32,
      0,
      nil
    );
end;

procedure TXCBWindowManager.RefreshEWMHActiveWindow();
var
  Win: xcb_window_t;
begin
  if (FConn = nil) or (not FEwmhInitialized) then Exit;

  if FActiveClient <> nil then
    Win := FActiveClient.ClientWindow
  else
    Win := XCB_NONE;

  xcb_change_property(
    FConn,
    XCB_PROP_MODE_REPLACE,
    FRootWindow,
    FEwmh._NET_ACTIVE_WINDOW,
    XCB_ATOM_WINDOW,
    32,
    1,
    @Win
  );
end;

procedure TXCBWindowManager.RefreshEWMHDesktop();
var
  Num, Cur: Cardinal;
  NamesData: AnsiString;
  I: Integer;
  Geom: array[0..3] of Cardinal;
begin
  if (FConn = nil) or (not FEwmhInitialized) then Exit;

  Num := FDesktopCount;
  Cur := FCurrentDesktop;

  // _NET_NUMBER_OF_DESKTOPS
  xcb_change_property(
    FConn,
    XCB_PROP_MODE_REPLACE,
    FRootWindow,
    FEwmh._NET_NUMBER_OF_DESKTOPS,
    XCB_ATOM_CARDINAL,
    32,
    1,
    @Num
  );

  // _NET_CURRENT_DESKTOP
  xcb_change_property(
    FConn,
    XCB_PROP_MODE_REPLACE,
    FRootWindow,
    FEwmh._NET_CURRENT_DESKTOP,
    XCB_ATOM_CARDINAL,
    32,
    1,
    @Cur
  );

  // _NET_DESKTOP_NAMES (null-separated strings)
  NamesData := '';
  for I := 0 to FDesktopNames.Count - 1 do
    NamesData := NamesData + FDesktopNames[I] + #0;

  if Length(NamesData) > 0 then
    xcb_change_property(
      FConn,
      XCB_PROP_MODE_REPLACE,
      FRootWindow,
      FEwmh._NET_DESKTOP_NAMES,
      FEwmh.UTF8_STRING,
      8,
      Length(NamesData),
      PAnsiChar(NamesData)
    );

  RefreshEWMHWorkarea();
end;

procedure TXCBWindowManager.RefreshEWMHWorkarea();
var
  WorkareaData: array of Cardinal;
  I: Integer;
begin
  if (FConn = nil) or (FRootWindow = 0) or (not FEwmhInitialized) then Exit;
  if FDesktopCount <= 0 then Exit;

  SetLength(WorkareaData, FDesktopCount * 4);
  for I := 0 to FDesktopCount - 1 do
  begin
    WorkareaData[I * 4 + 0] := Cardinal(FWorkarea.X);
    WorkareaData[I * 4 + 1] := Cardinal(FWorkarea.Y);
    WorkareaData[I * 4 + 2] := Cardinal(FWorkarea.Width);
    WorkareaData[I * 4 + 3] := Cardinal(FWorkarea.Height);
  end;

  xcb_change_property(
    FConn,
    XCB_PROP_MODE_REPLACE,
    FRootWindow,
    FEwmh._NET_WORKAREA,
    XCB_ATOM_CARDINAL,
    32,
    FDesktopCount * 4,
    @WorkareaData[0]
  );
  xcb_flush(FConn);
end;

procedure TXCBWindowManager.SetWorkarea(const AWorkarea: TXCBRect);
begin
  FWorkarea := AWorkarea;
  if FPrimaryMonitor <> nil then
    FPrimaryMonitor.Workarea := AWorkarea;
end;

procedure TXCBWindowManager.RecomputeWorkareas();
var
  ScreenWidth, ScreenHeight: Integer;
  NewWorkarea, OldWorkarea: TXCBRect;
  Cli: TXCBWMClient;
  Mon: TXCBMonitor;
  I, M: Integer;
  AnyWorkareaChanged: Boolean;
  PrevMonWorkareas: array of TXCBRect;
begin
  if FScreen <> nil then
  begin
    ScreenWidth := FScreen^.width_in_pixels;
    ScreenHeight := FScreen^.height_in_pixels;
  end
  else
  begin
    ScreenWidth := 1920;
    ScreenHeight := 1080;
  end;

  AnyWorkareaChanged := False;
  SetLength(PrevMonWorkareas, FMonitors.Count);

  // Reset workareas to full physical rects
  for M := 0 to FMonitors.Count - 1 do
  begin
    Mon := TXCBMonitor(FMonitors[M]);
    PrevMonWorkareas[M] := Mon.Workarea;
    Mon.ResetWorkarea();
  end;

  // Apply all client struts against each monitor
  for I := 0 to FClients.Count - 1 do
  begin
    Cli := TXCBWMClient(FClients[I]);
    if Cli.Strut.HasStrut() then
    begin
      for M := 0 to FMonitors.Count - 1 do
      begin
        Mon := TXCBMonitor(FMonitors[M]);
        Mon.ApplyStrut(Cli.Strut, ScreenWidth, ScreenHeight);
      end;
    end;
  end;

  // Check if any monitor workarea changed
  for M := 0 to FMonitors.Count - 1 do
  begin
    Mon := TXCBMonitor(FMonitors[M]);
    if (Mon.Workarea.X <> PrevMonWorkareas[M].X) or
       (Mon.Workarea.Y <> PrevMonWorkareas[M].Y) or
       (Mon.Workarea.Width <> PrevMonWorkareas[M].Width) or
       (Mon.Workarea.Height <> PrevMonWorkareas[M].Height) then
      AnyWorkareaChanged := True;
  end;

  // Global EWMH workarea corresponds to Primary monitor's workarea
  if FPrimaryMonitor <> nil then
    NewWorkarea := FPrimaryMonitor.Workarea
  else if FMonitors.Count > 0 then
    NewWorkarea := TXCBMonitor(FMonitors[0]).Workarea
  else
    NewWorkarea := TXCBRect.Create(0, 0, ScreenWidth, ScreenHeight);

  if (NewWorkarea.X <> FWorkarea.X) or
     (NewWorkarea.Y <> FWorkarea.Y) or
     (NewWorkarea.Width <> FWorkarea.Width) or
     (NewWorkarea.Height <> FWorkarea.Height) or
     AnyWorkareaChanged then
  begin
    OldWorkarea := FWorkarea;
    FWorkarea := NewWorkarea;
    RefreshEWMHWorkarea();
    DoOnWorkareaChanged(OldWorkarea, NewWorkarea);
  end;
end;

procedure TXCBWindowManager.RecomputeWorkarea();
begin
  RecomputeWorkareas();
end;

procedure TXCBWindowManager.DoOnWorkareaChanged(const AOldWorkarea, ANewWorkarea: TXCBRect);
var
  I: Integer;
  Cli: TXCBWMClient;
  TargetMon: TXCBMonitor;
  MonWorkarea: TXCBRect;
  HalfW: Integer;
begin
  for I := 0 to FClients.Count - 1 do
  begin
    Cli := TXCBWMClient(FClients[I]);
    if (wsFullscreen in Cli.State) then
      Continue;

    TargetMon := MonitorForClient(Cli);
    if (TargetMon <> nil) and (TargetMon.Workarea.Width > 0) and (TargetMon.Workarea.Height > 0) then
      MonWorkarea := TargetMon.Workarea
    else
      MonWorkarea := ANewWorkarea;

    if (wsMaximizedHorz in Cli.State) and (wsMaximizedVert in Cli.State) then
    begin
      Cli.SetGeometry(MonWorkarea.X, MonWorkarea.Y, MonWorkarea.Width, MonWorkarea.Height);
    end
    else if (wsTiledLeft in Cli.State) then
    begin
      HalfW := MonWorkarea.Width div 2;
      Cli.SetGeometry(MonWorkarea.X, MonWorkarea.Y, HalfW, MonWorkarea.Height);
    end
    else if (wsTiledRight in Cli.State) then
    begin
      HalfW := MonWorkarea.Width div 2;
      Cli.SetGeometry(MonWorkarea.X + HalfW, MonWorkarea.Y, MonWorkarea.Width - HalfW, MonWorkarea.Height);
    end;
  end;
end;

function TXCBWindowManager.RefreshMonitors(): Boolean;
var
  MonReply: Pxcb_randr_get_monitors_reply_t;
  MonIter: xcb_randr_monitor_info_iterator_t;
  MonInfo: Pxcb_randr_monitor_info_t;
  Mon: TXCBMonitor;
  MonName: AnsiString;
  AtomNameReply: Pxcb_get_atom_name_reply_t;
  AtomNameCookie: xcb_get_atom_name_cookie_t;
  Idx: Integer;
  XinActiveCookie: xcb_xinerama_is_active_cookie_t;
  XinActiveReply: Pxcb_xinerama_is_active_reply_t;
  XinScreensCookie: xcb_xinerama_query_screens_cookie_t;
  XinScreensReply: Pxcb_xinerama_query_screens_reply_t;
  XinScreensPtr: Pxcb_xinerama_screen_info_t;
  XinScreen: Pxcb_xinerama_screen_info_t;
  XinScreensLen: Integer;
begin
  Result := False;
  FMonitors.Clear();
  FPrimaryMonitor := nil;

  if (FConn <> nil) and (FRootWindow <> 0) and FRandRAvailable then
  begin
    MonReply := xcb_randr_get_monitors_reply(
      FConn,
      xcb_randr_get_monitors(FConn, FRootWindow, 1),
      nil
    );
    if MonReply <> nil then
    begin
      MonIter := xcb_randr_get_monitors_monitors_iterator(MonReply);
      Idx := 0;
      while MonIter.rem > 0 do
      begin
        MonInfo := MonIter.data;
        if MonInfo <> nil then
        begin
          MonName := '';
          if MonInfo^.name <> 0 then
          begin
            AtomNameCookie := xcb_get_atom_name(FConn, MonInfo^.name);
            AtomNameReply := xcb_get_atom_name_reply(FConn, AtomNameCookie, nil);
            if AtomNameReply <> nil then
            begin
              SetString(MonName, PAnsiChar(xcb_get_atom_name_name(AtomNameReply)), xcb_get_atom_name_name_length(AtomNameReply));
              xcb_free(AtomNameReply);
            end;
          end;
          if MonName = '' then
            MonName := 'Monitor-' + IntToStr(Idx + 1);

          Mon := TXCBMonitor.Create(
            MonName,
            TXCBRect.Create(MonInfo^.x, MonInfo^.y, MonInfo^.width, MonInfo^.height),
            MonInfo^.primary <> 0,
            Idx
          );
          FMonitors.Add(Mon);
          if (MonInfo^.primary <> 0) and (FPrimaryMonitor = nil) then
            FPrimaryMonitor := Mon;

          Inc(Idx);
        end;
        xcb_randr_monitor_info_next(@MonIter);
      end;
      xcb_free(MonReply);
    end;
  end;

  // Fallback to Xinerama if RandR returned <= 1 monitor (e.g. Xephyr multi-head or legacy Xinerama)
  if (FMonitors.Count <= 1) and (FConn <> nil) then
  begin
    XinActiveCookie := xcb_xinerama_is_active(FConn);
    XinActiveReply := xcb_xinerama_is_active_reply(FConn, XinActiveCookie, nil);
    if XinActiveReply <> nil then
    begin
      if XinActiveReply^.state <> 0 then
      begin
        XinScreensCookie := xcb_xinerama_query_screens(FConn);
        XinScreensReply := xcb_xinerama_query_screens_reply(FConn, XinScreensCookie, nil);
        if XinScreensReply <> nil then
        begin
          XinScreensLen := xcb_xinerama_query_screens_screen_info_length(XinScreensReply);
          if XinScreensLen > 1 then
          begin
            FMonitors.Clear();
            FPrimaryMonitor := nil;
            XinScreensPtr := xcb_xinerama_query_screens_screen_info(XinScreensReply);
            for Idx := 0 to XinScreensLen - 1 do
            begin
              XinScreen := Pxcb_xinerama_screen_info_t(PByte(XinScreensPtr) + Idx * SizeOf(xcb_xinerama_screen_info_t));
              Mon := TXCBMonitor.Create(
                'Head-' + IntToStr(Idx + 1),
                TXCBRect.Create(XinScreen^.x_org, XinScreen^.y_org, XinScreen^.width, XinScreen^.height),
                Idx = 0,
                Idx
              );
              FMonitors.Add(Mon);
              if (Idx = 0) and (FPrimaryMonitor = nil) then
                FPrimaryMonitor := Mon;
            end;
          end;
          xcb_free(XinScreensReply);
        end;
      end;
      xcb_free(XinActiveReply);
    end;
  end;

  // Fallback if no RandR or no monitors returned
  if FMonitors.Count = 0 then
  begin
    if FScreen <> nil then
      Mon := TXCBMonitor.Create(
        'Default',
        TXCBRect.Create(0, 0, FScreen^.width_in_pixels, FScreen^.height_in_pixels),
        True,
        0
      )
    else
      Mon := TXCBMonitor.Create(
        'Default',
        TXCBRect.Create(0, 0, 1920, 1080),
        True,
        0
      );
    FMonitors.Add(Mon);
    FPrimaryMonitor := Mon;
  end
  else if FPrimaryMonitor = nil then
  begin
    FPrimaryMonitor := TXCBMonitor(FMonitors[0]);
    FPrimaryMonitor.IsPrimary := True;
  end;

  RecomputeWorkareas();
  Result := True;
end;

function TXCBWindowManager.GetMonitorCount(): Integer;
begin
  if FMonitors <> nil then
    Result := FMonitors.Count
  else
    Result := 0;
end;

function TXCBWindowManager.GetMonitor(const AIndex: Integer): TXCBMonitor;
begin
  if (FMonitors <> nil) and (AIndex >= 0) and (AIndex < FMonitors.Count) then
    Result := TXCBMonitor(FMonitors[AIndex])
  else
    Result := nil;
end;

function TXCBWindowManager.MonitorForPoint(const AX, AY: Integer): TXCBMonitor;
var
  I: Integer;
  Mon: TXCBMonitor;
begin
  Result := nil;
  if FMonitors = nil then Exit;
  for I := 0 to FMonitors.Count - 1 do
  begin
    Mon := TXCBMonitor(FMonitors[I]);
    if Mon.Contains(AX, AY) then
    begin
      Result := Mon;
      Exit;
    end;
  end;
  if FPrimaryMonitor <> nil then
    Result := FPrimaryMonitor
  else if FMonitors.Count > 0 then
    Result := TXCBMonitor(FMonitors[0]);
end;

function TXCBWindowManager.MonitorForRect(const ARect: TXCBRect): TXCBMonitor;
var
  I, MaxArea, Area: Integer;
  Mon, BestMon: TXCBMonitor;
  CenterX, CenterY: Integer;
begin
  Result := nil;
  if (FMonitors = nil) or (FMonitors.Count = 0) then Exit;

  MaxArea := 0;
  BestMon := nil;

  for I := 0 to FMonitors.Count - 1 do
  begin
    Mon := TXCBMonitor(FMonitors[I]);
    Area := Mon.IntersectionArea(ARect);
    if Area > MaxArea then
    begin
      MaxArea := Area;
      BestMon := Mon;
    end;
  end;

  if (BestMon <> nil) and (MaxArea > 0) then
  begin
    Result := BestMon;
    Exit;
  end;

  CenterX := ARect.X + (ARect.Width div 2);
  CenterY := ARect.Y + (ARect.Height div 2);
  Result := MonitorForPoint(CenterX, CenterY);
end;

function TXCBWindowManager.MonitorForClient(const AClient: TXCBWMClient): TXCBMonitor;
begin
  Result := nil;
  if AClient = nil then Exit;
  Result := MonitorForRect(AClient.CurrentRect);
end;

function TXCBWindowManager.AdjacentMonitor(const ACurrent: TXCBMonitor; const ADirection: TXCBDirection): TXCBMonitor;
var
  I: Integer;
  Mon, BestMon: TXCBMonitor;
  CurCenterX, CurCenterY: Integer;
  CandCenterX, CandCenterY: Integer;
  Dist, BestDist, DeltaPrimary, DeltaSecondary: Integer;
begin
  Result := ACurrent;
  if (FMonitors = nil) or (FMonitors.Count <= 1) or (ACurrent = nil) then Exit;

  CurCenterX := ACurrent.Rect.X + (ACurrent.Rect.Width div 2);
  CurCenterY := ACurrent.Rect.Y + (ACurrent.Rect.Height div 2);

  BestMon := nil;
  BestDist := High(Integer);

  for I := 0 to FMonitors.Count - 1 do
  begin
    Mon := TXCBMonitor(FMonitors[I]);
    if Mon = ACurrent then Continue;

    CandCenterX := Mon.Rect.X + (Mon.Rect.Width div 2);
    CandCenterY := Mon.Rect.Y + (Mon.Rect.Height div 2);

    case ADirection of
      dirLeft:
      begin
        if CandCenterX < CurCenterX then
        begin
          DeltaPrimary := CurCenterX - CandCenterX;
          DeltaSecondary := Abs(CandCenterY - CurCenterY);
          Dist := DeltaPrimary + (DeltaSecondary * 2);
          if Dist < BestDist then
          begin
            BestDist := Dist;
            BestMon := Mon;
          end;
        end;
      end;
      dirRight:
      begin
        if CandCenterX > CurCenterX then
        begin
          DeltaPrimary := CandCenterX - CurCenterX;
          DeltaSecondary := Abs(CandCenterY - CurCenterY);
          Dist := DeltaPrimary + (DeltaSecondary * 2);
          if Dist < BestDist then
          begin
            BestDist := Dist;
            BestMon := Mon;
          end;
        end;
      end;
      dirUp:
      begin
        if CandCenterY < CurCenterY then
        begin
          DeltaPrimary := CurCenterY - CandCenterY;
          DeltaSecondary := Abs(CandCenterX - CurCenterX);
          Dist := DeltaPrimary + (DeltaSecondary * 2);
          if Dist < BestDist then
          begin
            BestDist := Dist;
            BestMon := Mon;
          end;
        end;
      end;
      dirDown:
      begin
        if CandCenterY > CurCenterY then
        begin
          DeltaPrimary := CandCenterY - CurCenterY;
          DeltaSecondary := Abs(CandCenterX - CurCenterX);
          Dist := DeltaPrimary + (DeltaSecondary * 2);
          if Dist < BestDist then
          begin
            BestDist := Dist;
            BestMon := Mon;
          end;
        end;
      end;
    end;
  end;

  if BestMon <> nil then
    Result := BestMon;
end;

procedure TXCBWindowManager.MoveClientToMonitor(const AClient: TXCBWMClient; const ATargetMonitor: TXCBMonitor);
var
  SrcMon: TXCBMonitor;
  RelX, RelY: Integer;
  NewX, NewY: Integer;
  HalfW: Integer;
begin
  if (AClient = nil) or (ATargetMonitor = nil) then Exit;

  if (wsMaximizedHorz in AClient.State) and (wsMaximizedVert in AClient.State) then
  begin
    AClient.SetGeometry(
      ATargetMonitor.Workarea.X,
      ATargetMonitor.Workarea.Y,
      ATargetMonitor.Workarea.Width,
      ATargetMonitor.Workarea.Height
    );
  end
  else if (wsTiledLeft in AClient.State) then
  begin
    HalfW := ATargetMonitor.Workarea.Width div 2;
    AClient.SetGeometry(
      ATargetMonitor.Workarea.X,
      ATargetMonitor.Workarea.Y,
      HalfW,
      ATargetMonitor.Workarea.Height
    );
  end
  else if (wsTiledRight in AClient.State) then
  begin
    HalfW := ATargetMonitor.Workarea.Width div 2;
    AClient.SetGeometry(
      ATargetMonitor.Workarea.X + HalfW,
      ATargetMonitor.Workarea.Y,
      ATargetMonitor.Workarea.Width - HalfW,
      ATargetMonitor.Workarea.Height
    );
  end
  else
  begin
    SrcMon := MonitorForClient(AClient);
    if SrcMon <> nil then
    begin
      RelX := AClient.CurrentRect.X - SrcMon.Rect.X;
      RelY := AClient.CurrentRect.Y - SrcMon.Rect.Y;
    end
    else
    begin
      RelX := 0;
      RelY := 0;
    end;

    NewX := ATargetMonitor.Rect.X + RelX;
    NewY := ATargetMonitor.Rect.Y + RelY;

    if NewX + AClient.CurrentRect.Width > ATargetMonitor.Rect.Right() then
      NewX := Max(ATargetMonitor.Rect.X, ATargetMonitor.Rect.Right() - AClient.CurrentRect.Width);
    if NewY + AClient.CurrentRect.Height > ATargetMonitor.Rect.Bottom() then
      NewY := Max(ATargetMonitor.Rect.Y, ATargetMonitor.Rect.Bottom() - AClient.CurrentRect.Height);
    if NewX < ATargetMonitor.Rect.X then NewX := ATargetMonitor.Rect.X;
    if NewY < ATargetMonitor.Rect.Y then NewY := ATargetMonitor.Rect.Y;

    AClient.Move(NewX, NewY);
    AClient.RestoredRect := AClient.CurrentRect;
  end;
end;

procedure TXCBWindowManager.DoOnMonitorsChanged();
var
  I: Integer;
  Cli: TXCBWMClient;
  Mon, TargetMon: TXCBMonitor;
begin
  if (FMonitors = nil) or (FMonitors.Count = 0) then Exit;
  TargetMon := FPrimaryMonitor;
  if TargetMon = nil then
    TargetMon := TXCBMonitor(FMonitors[0]);

  for I := 0 to FClients.Count - 1 do
  begin
    Cli := TXCBWMClient(FClients[I]);
    Mon := MonitorForRect(Cli.CurrentRect);
    if (Mon = nil) or (Mon.IntersectionArea(Cli.CurrentRect) = 0) then
    begin
      MoveClientToMonitor(Cli, TargetMon);
    end
    else if (wsMaximizedHorz in Cli.State) and (wsMaximizedVert in Cli.State) then
    begin
      Cli.SetGeometry(Mon.Workarea.X, Mon.Workarea.Y, Mon.Workarea.Width, Mon.Workarea.Height);
    end
    else if (wsTiledLeft in Cli.State) then
    begin
      Cli.SetGeometry(Mon.Workarea.X, Mon.Workarea.Y, Mon.Workarea.Width div 2, Mon.Workarea.Height);
    end
    else if (wsTiledRight in Cli.State) then
    begin
      Cli.SetGeometry(Mon.Workarea.X + (Mon.Workarea.Width div 2), Mon.Workarea.Y, Mon.Workarea.Width - (Mon.Workarea.Width div 2), Mon.Workarea.Height);
    end;
  end;
end;

procedure TXCBWindowManager.ReadClientProperties(const AClient: TXCBWMClient);
var
  AttrCookie: xcb_get_window_attributes_cookie_t;
  AttrReply: Pxcb_get_window_attributes_reply_t;
  GeomCookie: xcb_get_geometry_cookie_t;
  GeomReply: Pxcb_get_geometry_reply_t;
  PropCookie: xcb_get_property_cookie_t;
  PropReply: Pxcb_get_property_reply_t;
  DataPtr: Pointer;
  DataLen: Integer;
  AtomsPtr: Pxcb_atom_t;
  I: Integer;
  ClassStr: AnsiString;
  P1, P2: PAnsiChar;
  MwmHintsPtr: PXCBMwmHints;
  SizeHints: xcb_size_hints_t;
begin
  if (FConn = nil) or (AClient = nil) then Exit;

  // Reset capabilities to defaults
  AClient.CanResize := True;
  AClient.CanMaximize := True;
  AClient.CanMinimize := True;
  AClient.CanClose := True;
  AClient.HasMaximizeButton := True;
  AClient.HasMinimizeButton := True;
  AClient.HasCloseButton := True;

  // 1. Window Attributes
  AttrCookie := xcb_get_window_attributes(FConn, AClient.ClientWindow);
  AttrReply := xcb_get_window_attributes_reply(FConn, AttrCookie, nil);
  if AttrReply <> nil then
  begin
    AClient.OverrideRedirect := AttrReply^.override_redirect <> 0;
    xcb_free(AttrReply);
  end;

  // 2. Window Geometry
  if not AClient.IsReparented then
  begin
    GeomCookie := xcb_get_geometry(FConn, AClient.ClientWindow);
    GeomReply := xcb_get_geometry_reply(FConn, GeomCookie, nil);
    if GeomReply <> nil then
    begin
      AClient.CurrentRect := TXCBRect.Create(
        GeomReply^.x,
        GeomReply^.y,
        GeomReply^.width,
        GeomReply^.height
      );
      xcb_free(GeomReply);
    end;
  end;

  // 3. _NET_WM_WINDOW_TYPE
  if FEwmhInitialized then
  begin
    PropCookie := xcb_get_property(FConn, 0, AClient.ClientWindow, FEwmh._NET_WM_WINDOW_TYPE, XCB_ATOM_ATOM, 0, 8);
    PropReply := xcb_get_property_reply(FConn, PropCookie, nil);
    if PropReply <> nil then
    begin
      try
        DataLen := xcb_get_property_value_length(PropReply) div SizeOf(xcb_atom_t);
        if DataLen > 0 then
        begin
          AtomsPtr := Pxcb_atom_t(xcb_get_property_value(PropReply));
          for I := 0 to DataLen - 1 do
          begin
            if AtomsPtr[I] = FEwmh._NET_WM_WINDOW_TYPE_DOCK then
            begin
              AClient.WindowType := wtDock;
              Break;
            end
            else if AtomsPtr[I] = FEwmh._NET_WM_WINDOW_TYPE_DESKTOP then
            begin
              AClient.WindowType := wtDesktop;
              Break;
            end
            else if AtomsPtr[I] = FEwmh._NET_WM_WINDOW_TYPE_SPLASH then
            begin
              AClient.WindowType := wtSplash;
              Break;
            end
            else if AtomsPtr[I] = FEwmh._NET_WM_WINDOW_TYPE_POPUP_MENU then
            begin
              AClient.WindowType := wtPopupMenu;
              Break;
            end
            else if AtomsPtr[I] = FEwmh._NET_WM_WINDOW_TYPE_DROPDOWN_MENU then
            begin
              AClient.WindowType := wtDropdownMenu;
              Break;
            end
            else if AtomsPtr[I] = FEwmh._NET_WM_WINDOW_TYPE_MENU then
            begin
              AClient.WindowType := wtMenu;
              Break;
            end
            else if AtomsPtr[I] = FEwmh._NET_WM_WINDOW_TYPE_COMBO then
            begin
              AClient.WindowType := wtCombo;
              Break;
            end
            else if AtomsPtr[I] = FEwmh._NET_WM_WINDOW_TYPE_TOOLTIP then
            begin
              AClient.WindowType := wtTooltip;
              Break;
            end
            else if AtomsPtr[I] = FEwmh._NET_WM_WINDOW_TYPE_NOTIFICATION then
            begin
              AClient.WindowType := wtNotification;
              Break;
            end
            else if AtomsPtr[I] = FEwmh._NET_WM_WINDOW_TYPE_DIALOG then
            begin
              AClient.WindowType := wtDialog;
              Break;
            end
            else if AtomsPtr[I] = FEwmh._NET_WM_WINDOW_TYPE_TOOLBAR then
            begin
              AClient.WindowType := wtToolbar;
              Break;
            end
            else if AtomsPtr[I] = FEwmh._NET_WM_WINDOW_TYPE_UTILITY then
            begin
              AClient.WindowType := wtUtility;
              Break;
            end
            else if AtomsPtr[I] = FEwmh._NET_WM_WINDOW_TYPE_DND then
            begin
              AClient.WindowType := wtDnd;
              Break;
            end
            else if AtomsPtr[I] = FEwmh._NET_WM_WINDOW_TYPE_NORMAL then
            begin
              AClient.WindowType := wtNormal;
              Break;
            end;
          end;
        end;
      finally
        xcb_free(PropReply);
      end;
    end;
  end;

  if AClient.WindowType in [wtDialog, wtUtility, wtToolbar] then
  begin
    AClient.CanMaximize := False;
    AClient.HasMaximizeButton := False;
    AClient.CanMinimize := False;
    AClient.HasMinimizeButton := False;
  end
  else if AClient.WindowType in [wtDock, wtDesktop] then
  begin
    AClient.CanMaximize := False;
    AClient.HasMaximizeButton := False;
    AClient.CanMinimize := False;
    AClient.HasMinimizeButton := False;
    AClient.CanClose := False;
    AClient.HasCloseButton := False;
    AClient.CanResize := False;
  end;

  // 4. _NET_WM_PID
  if FEwmhInitialized then
  begin
    PropCookie := xcb_get_property(FConn, 0, AClient.ClientWindow, FEwmh._NET_WM_PID, XCB_ATOM_CARDINAL, 0, 1);
    PropReply := xcb_get_property_reply(FConn, PropCookie, nil);
    if PropReply <> nil then
    begin
      try
        if xcb_get_property_value_length(PropReply) >= SizeOf(Cardinal) then
          AClient.Pid := PCardinal(xcb_get_property_value(PropReply))^;
      finally
        xcb_free(PropReply);
      end;
    end;
  end;

  // 5. _NET_WM_NAME or WM_NAME
  if FEwmhInitialized then
  begin
    PropCookie := xcb_get_property(FConn, 0, AClient.ClientWindow, FEwmh._NET_WM_NAME, FEwmh.UTF8_STRING, 0, 256);
    PropReply := xcb_get_property_reply(FConn, PropCookie, nil);
    if (PropReply <> nil) and (xcb_get_property_value_length(PropReply) > 0) then
    begin
      SetString(AClient.FTitle, PAnsiChar(xcb_get_property_value(PropReply)), xcb_get_property_value_length(PropReply));
      xcb_free(PropReply);
    end
    else
    begin
      if PropReply <> nil then xcb_free(PropReply);
      // Fallback to legacy WM_NAME
      PropCookie := xcb_get_property(FConn, 0, AClient.ClientWindow, XCB_ATOM_WM_NAME, XCB_ATOM_STRING, 0, 256);
      PropReply := xcb_get_property_reply(FConn, PropCookie, nil);
      if (PropReply <> nil) and (xcb_get_property_value_length(PropReply) > 0) then
      begin
        SetString(AClient.FTitle, PAnsiChar(xcb_get_property_value(PropReply)), xcb_get_property_value_length(PropReply));
        xcb_free(PropReply);
      end
      else if PropReply <> nil then
        xcb_free(PropReply);
    end;
  end;

  // 6. WM_CLASS
  PropCookie := xcb_get_property(FConn, 0, AClient.ClientWindow, XCB_ATOM_WM_CLASS, XCB_ATOM_STRING, 0, 256);
  PropReply := xcb_get_property_reply(FConn, PropCookie, nil);
  if PropReply <> nil then
  begin
    try
      DataLen := xcb_get_property_value_length(PropReply);
      if DataLen > 0 then
      begin
        DataPtr := xcb_get_property_value(PropReply);
        SetString(ClassStr, PAnsiChar(DataPtr), DataLen);
        P1 := PAnsiChar(DataPtr);
        AClient.WindowInstance := AnsiString(P1);
        P2 := P1 + Length(AClient.WindowInstance) + 1;
        if P2 < PAnsiChar(DataPtr) + DataLen then
          AClient.WindowClass := AnsiString(P2);
      end;
    finally
      xcb_free(PropReply);
    end;
  end;

  // 7. WM_PROTOCOLS
  if FEwmhInitialized then
  begin
    PropCookie := xcb_get_property(FConn, 0, AClient.ClientWindow, FEwmh.WM_PROTOCOLS, XCB_ATOM_ATOM, 0, 32);
    PropReply := xcb_get_property_reply(FConn, PropCookie, nil);
    if PropReply <> nil then
    begin
      try
        DataLen := xcb_get_property_value_length(PropReply) div SizeOf(xcb_atom_t);
        AtomsPtr := Pxcb_atom_t(xcb_get_property_value(PropReply));
        for I := 0 to DataLen - 1 do
        begin
          if (FAtomWMDeleteWindow <> 0) and (AtomsPtr[I] = FAtomWMDeleteWindow) then
            AClient.SupportsDeleteWindow := True;
          if (FAtomWMTakeFocus <> 0) and (AtomsPtr[I] = FAtomWMTakeFocus) then
            AClient.SupportsTakeFocus := True;
        end;
      finally
        xcb_free(PropReply);
      end;
    end;
  end;

  // 8. _MOTIF_WM_HINTS
  if (FConn <> nil) and (FAtomMotifWmHints <> 0) then
  begin
    PropCookie := xcb_get_property(FConn, 0, AClient.ClientWindow, FAtomMotifWmHints, XCB_ATOM_ANY, 0, 5);
    PropReply := xcb_get_property_reply(FConn, PropCookie, nil);
    if PropReply <> nil then
    begin
      try
        if xcb_get_property_value_length(PropReply) >= (3 * SizeOf(Cardinal)) then
        begin
          MwmHintsPtr := PXCBMwmHints(xcb_get_property_value(PropReply));
          if (MwmHintsPtr^.flags and XCB_MWM_HINTS_DECORATIONS) <> 0 then
          begin
            if MwmHintsPtr^.decorations = 0 then
              AClient.Borderless := True
            else
            begin
              AClient.Borderless := False;
              if (MwmHintsPtr^.decorations and XCB_MWM_DECOR_ALL) <> 0 then
              begin
                // Subtractive mode: bits set are excluded
                if (MwmHintsPtr^.decorations and XCB_MWM_DECOR_MINIMIZE) <> 0 then
                  AClient.HasMinimizeButton := False;
                if (MwmHintsPtr^.decorations and XCB_MWM_DECOR_MAXIMIZE) <> 0 then
                  AClient.HasMaximizeButton := False;
                if (MwmHintsPtr^.decorations and (XCB_MWM_DECOR_TITLE or XCB_MWM_DECOR_MENU)) = (XCB_MWM_DECOR_TITLE or XCB_MWM_DECOR_MENU) then
                  AClient.HasCloseButton := False;
              end
              else
              begin
                // Additive mode: only bits set are included
                AClient.HasMinimizeButton := (MwmHintsPtr^.decorations and XCB_MWM_DECOR_MINIMIZE) <> 0;
                AClient.HasMaximizeButton := (MwmHintsPtr^.decorations and XCB_MWM_DECOR_MAXIMIZE) <> 0;
                AClient.HasCloseButton := (MwmHintsPtr^.decorations and (XCB_MWM_DECOR_TITLE or XCB_MWM_DECOR_MENU)) <> 0;
              end;
            end;
          end;

          if (MwmHintsPtr^.flags and XCB_MWM_HINTS_FUNCTIONS) <> 0 then
          begin
            if (MwmHintsPtr^.functions and XCB_MWM_FUNC_ALL) <> 0 then
            begin
              // Subtractive mode: bits set are excluded
              if (MwmHintsPtr^.functions and XCB_MWM_FUNC_RESIZE) <> 0 then
                AClient.CanResize := False;
              if (MwmHintsPtr^.functions and XCB_MWM_FUNC_MINIMIZE) <> 0 then
                AClient.CanMinimize := False;
              if (MwmHintsPtr^.functions and XCB_MWM_FUNC_MAXIMIZE) <> 0 then
                AClient.CanMaximize := False;
              if (MwmHintsPtr^.functions and XCB_MWM_FUNC_CLOSE) <> 0 then
                AClient.CanClose := False;
            end
            else
            begin
              // Additive mode: only bits set are included
              AClient.CanResize := (MwmHintsPtr^.functions and XCB_MWM_FUNC_RESIZE) <> 0;
              AClient.CanMinimize := (MwmHintsPtr^.functions and XCB_MWM_FUNC_MINIMIZE) <> 0;
              AClient.CanMaximize := (MwmHintsPtr^.functions and XCB_MWM_FUNC_MAXIMIZE) <> 0;
              AClient.CanClose := (MwmHintsPtr^.functions and XCB_MWM_FUNC_CLOSE) <> 0;
            end;
          end;
        end;
      finally
        xcb_free(PropReply);
      end;
    end;
  end;

  // 9. _NET_WM_STRUT_PARTIAL / _NET_WM_STRUT
  AClient.FStrut := TXCBStrutPartial.Create();
  if (FConn <> nil) and (FAtomNetWmStrutPartial <> 0) then
  begin
    PropCookie := xcb_get_property(FConn, 0, AClient.ClientWindow, FAtomNetWmStrutPartial, XCB_ATOM_CARDINAL, 0, 12);
    PropReply := xcb_get_property_reply(FConn, PropCookie, nil);
    if PropReply <> nil then
    begin
      try
        if xcb_get_property_value_length(PropReply) >= (12 * SizeOf(Cardinal)) then
        begin
          Move(xcb_get_property_value(PropReply)^, AClient.FStrut, 12 * SizeOf(Cardinal));
        end;
      finally
        xcb_free(PropReply);
      end;
    end;
  end;

  if (not AClient.Strut.HasStrut()) and (FConn <> nil) and (FAtomNetWmStrut <> 0) then
  begin
    PropCookie := xcb_get_property(FConn, 0, AClient.ClientWindow, FAtomNetWmStrut, XCB_ATOM_CARDINAL, 0, 4);
    PropReply := xcb_get_property_reply(FConn, PropCookie, nil);
    if PropReply <> nil then
    begin
      try
        if xcb_get_property_value_length(PropReply) >= (4 * SizeOf(Cardinal)) then
        begin
          AtomsPtr := Pxcb_atom_t(xcb_get_property_value(PropReply));
          AClient.FStrut.Left := AtomsPtr[0];
          AClient.FStrut.Right := AtomsPtr[1];
          AClient.FStrut.Top := AtomsPtr[2];
          AClient.FStrut.Bottom := AtomsPtr[3];
        end;
      finally
        xcb_free(PropReply);
      end;
    end;
  end;

  // 10. Initial _NET_WM_STATE
  if FEwmhInitialized then
  begin
    PropCookie := xcb_get_property(FConn, 0, AClient.ClientWindow, FEwmh._NET_WM_STATE, XCB_ATOM_ATOM, 0, 32);
    PropReply := xcb_get_property_reply(FConn, PropCookie, nil);
    if PropReply <> nil then
    begin
      try
        DataLen := xcb_get_property_value_length(PropReply) div SizeOf(xcb_atom_t);
        if DataLen > 0 then
        begin
          AtomsPtr := Pxcb_atom_t(xcb_get_property_value(PropReply));
          for I := 0 to DataLen - 1 do
          begin
            if AtomsPtr[I] = FEwmh._NET_WM_STATE_MAXIMIZED_HORZ then
              Include(AClient.FState, wsMaximizedHorz)
            else if AtomsPtr[I] = FEwmh._NET_WM_STATE_MAXIMIZED_VERT then
              Include(AClient.FState, wsMaximizedVert)
            else if AtomsPtr[I] = FEwmh._NET_WM_STATE_FULLSCREEN then
              Include(AClient.FState, wsFullscreen)
            else if AtomsPtr[I] = FEwmh._NET_WM_STATE_HIDDEN then
              Include(AClient.FState, wsMinimized)
            else if AtomsPtr[I] = FEwmh._NET_WM_STATE_ABOVE then
              Include(AClient.FState, wsAbove);
          end;
        end;
      finally
        xcb_free(PropReply);
      end;
    end;
  end;

  // 11. Initial _NET_WM_DESKTOP
  if FEwmhInitialized then
  begin
    PropCookie := xcb_get_property(FConn, 0, AClient.ClientWindow, FEwmh._NET_WM_DESKTOP, XCB_ATOM_CARDINAL, 0, 1);
    PropReply := xcb_get_property_reply(FConn, PropCookie, nil);
    if PropReply <> nil then
    begin
      try
        if xcb_get_property_value_length(PropReply) >= SizeOf(Cardinal) then
          AClient.FDesktop := Integer(PCardinal(xcb_get_property_value(PropReply))^);
      finally
        xcb_free(PropReply);
      end;
    end;
  end;

  // 12. WM_NORMAL_HINTS (Size hints, USPosition, PPosition, WinGravity)
  PropCookie := xcb_get_property(FConn, 0, AClient.ClientWindow, XCB_ATOM_WM_NORMAL_HINTS, XCB_ATOM_WM_SIZE_HINTS, 0, 18);
  PropReply := xcb_get_property_reply(FConn, PropCookie, nil);
  if PropReply <> nil then
  begin
    try
      DataLen := xcb_get_property_value_length(PropReply);
      if DataLen >= SizeOf(Cardinal) then
      begin
        FillChar(SizeHints, SizeOf(SizeHints), 0);
        if DataLen > SizeOf(SizeHints) then
          DataLen := SizeOf(SizeHints);
        Move(xcb_get_property_value(PropReply)^, SizeHints, DataLen);

        if (SizeHints.flags and XCB_ICCCM_SIZE_HINT_US_POSITION) <> 0 then
          AClient.FHasUserPosition := True;
        if (SizeHints.flags and XCB_ICCCM_SIZE_HINT_P_POSITION) <> 0 then
          AClient.FHasProgramPosition := True;
        if (SizeHints.flags and XCB_ICCCM_SIZE_HINT_P_MIN_SIZE) <> 0 then
          AClient.FMinSize := TXCBPoint.Create(SizeHints.min_width, SizeHints.min_height);
        if (SizeHints.flags and XCB_ICCCM_SIZE_HINT_P_MAX_SIZE) <> 0 then
          AClient.FMaxSize := TXCBPoint.Create(SizeHints.max_width, SizeHints.max_height);
        if (SizeHints.flags and XCB_ICCCM_SIZE_HINT_BASE_SIZE) <> 0 then
          AClient.FBaseSize := TXCBPoint.Create(SizeHints.base_width, SizeHints.base_height);
        if (SizeHints.flags and XCB_ICCCM_SIZE_HINT_P_RESIZE_INC) <> 0 then
          AClient.FSizeInc := TXCBPoint.Create(Max(1, SizeHints.width_inc), Max(1, SizeHints.height_inc));
        if (SizeHints.flags and XCB_ICCCM_SIZE_HINT_P_WIN_GRAVITY) <> 0 then
          AClient.FWinGravity := SizeHints.win_gravity;
      end;
    finally
      xcb_free(PropReply);
    end;
  end;

  // 13. WM_TRANSIENT_FOR
  PropCookie := xcb_get_property(FConn, 0, AClient.ClientWindow, XCB_ATOM_WM_TRANSIENT_FOR, XCB_ATOM_WINDOW, 0, 1);
  PropReply := xcb_get_property_reply(FConn, PropCookie, nil);
  if PropReply <> nil then
  begin
    try
      DataLen := xcb_get_property_value_length(PropReply);
      if DataLen >= SizeOf(xcb_window_t) then
        AClient.TransientFor := Pxcb_window_t(xcb_get_property_value(PropReply))^
      else
        AClient.TransientFor := 0;
    finally
      xcb_free(PropReply);
    end;
  end
  else
    AClient.TransientFor := 0;

  // Fixed-size window detection from WM_NORMAL_HINTS
  if (AClient.MinSize.X > 0) and (AClient.MaxSize.X > 0) and
     (AClient.MinSize.Y > 0) and (AClient.MaxSize.Y > 0) and
     (AClient.MinSize.X >= AClient.MaxSize.X) and
     (AClient.MinSize.Y >= AClient.MaxSize.Y) then
  begin
    AClient.CanResize := False;
    AClient.CanMaximize := False;
    AClient.HasMaximizeButton := False;
  end;

  // Reconcile capabilities and decoration buttons
  if not AClient.CanResize then
  begin
    AClient.CanMaximize := False;
    AClient.HasMaximizeButton := False;
  end;

  if not AClient.CanMaximize then
    AClient.HasMaximizeButton := False;

  if not AClient.HasMaximizeButton then
    AClient.CanMaximize := False;

  if not AClient.CanMinimize then
    AClient.HasMinimizeButton := False;

  if not AClient.HasMinimizeButton then
    AClient.CanMinimize := False;

  if not AClient.CanClose then
    AClient.HasCloseButton := False;

  if not AClient.HasCloseButton then
    AClient.CanClose := False;

  if AClient.IsReparented and (FConn <> nil) then
  begin
    if not AClient.CanResize then
    begin
      if AClient.ResizeWindow <> 0 then
      begin
        xcb_destroy_window(FConn, AClient.ResizeWindow);
        AClient.ResizeWindow := 0;
      end;
    end
    else
    begin
      if AClient.ResizeWindow = 0 then
        AClient.ResizeWindow := CreateResizeWindow(AClient, AClient.CurrentRect);
    end;
  end;

  if FEwmhInitialized then
    UpdateAllowedActions(AClient);
end;

function TXCBWindowManager.CreateFrameWindow(const AClient: TXCBWMClient; const ARect: TXCBRect): xcb_window_t;
var
  FrameWin: xcb_window_t;
  ValueMask: Cardinal;
  ValueList: array[0..3] of Cardinal;
begin
  Result := 0;
  if FConn = nil then Exit;

  FrameWin := xcb_generate_id(FConn);
  ValueMask := XCB_CW_BACK_PIXEL or XCB_CW_BORDER_PIXEL or XCB_CW_EVENT_MASK;
  ValueList[0] := $C0C0C0; // Default frame background (light gray)
  ValueList[1] := $404040; // Default frame border (dark gray)
  ValueList[2] := XCB_EVENT_MASK_EXPOSURE or
                  XCB_EVENT_MASK_SUBSTRUCTURE_NOTIFY or
                  XCB_EVENT_MASK_SUBSTRUCTURE_REDIRECT or
                  XCB_EVENT_MASK_BUTTON_PRESS or
                  XCB_EVENT_MASK_BUTTON_RELEASE or
                  XCB_EVENT_MASK_POINTER_MOTION or
                  XCB_EVENT_MASK_ENTER_WINDOW or
                  XCB_EVENT_MASK_LEAVE_WINDOW;

  if FCursorNormal <> 0 then
  begin
    ValueMask := ValueMask or XCB_CW_CURSOR;
    ValueList[3] := FCursorNormal;
  end;

  xcb_create_window(
    FConn,
    XCB_COPY_FROM_PARENT,
    FrameWin,
    FRootWindow,
    ARect.X,
    ARect.Y,
    ARect.Width,
    ARect.Height,
    0, // ICCCM: Frame window has border_width 0 (decorations rendered internally)
    XCB_WINDOW_CLASS_INPUT_OUTPUT,
    XCB_COPY_FROM_PARENT,
    ValueMask,
    @ValueList[0]
  );

  Result := FrameWin;
end;

function TXCBWindowManager.CreateResizeWindow(const AClient: TXCBWMClient; const ARect: TXCBRect): xcb_window_t;
var
  ResizeWin: xcb_window_t;
  ValueMask: Cardinal;
  ValueList: array[0..3] of Cardinal;
  Margin: Integer;
begin
  Result := 0;
  if FConn = nil then Exit;

  Margin := 8;
  ResizeWin := xcb_generate_id(FConn);
  ValueMask := XCB_CW_OVERRIDE_REDIRECT or XCB_CW_EVENT_MASK;
  ValueList[0] := 1;
  ValueList[1] := XCB_EVENT_MASK_BUTTON_PRESS or
                  XCB_EVENT_MASK_BUTTON_RELEASE or
                  XCB_EVENT_MASK_POINTER_MOTION or
                  XCB_EVENT_MASK_ENTER_WINDOW or
                  XCB_EVENT_MASK_LEAVE_WINDOW;

  if FCursorNormal <> 0 then
  begin
    ValueMask := ValueMask or XCB_CW_CURSOR;
    ValueList[2] := FCursorNormal;
  end;

  xcb_create_window(
    FConn,
    0, // depth 0 for InputOnly
    ResizeWin,
    FRootWindow,
    ARect.X - Margin,
    ARect.Y - Margin,
    ARect.Width + (Margin * 2),
    ARect.Height + (Margin * 2),
    0, // border_width
    XCB_WINDOW_CLASS_INPUT_ONLY,
    XCB_COPY_FROM_PARENT,
    ValueMask,
    @ValueList[0]
  );

  Result := ResizeWin;
end;

procedure TXCBWindowManager.ReparentClient(const AClient: TXCBWMClient);
var
  FrameRect, ClientInnerRect: TXCBRect;
  FrameWin: xcb_window_t;
  Values: array[0..3] of Cardinal;
  PtrCookie: xcb_query_pointer_cookie_t;
  PtrReply: Pxcb_query_pointer_reply_t;
  TargetMon: TXCBMonitor;
  PlaceX, PlaceY: Integer;
  ParentCli: TXCBWMClient;
begin
  if (AClient = nil) or AClient.IsReparented or (FConn = nil) then Exit;

  // If initial window geometry is minimal (e.g. 1x1 before configure), provide a reasonable default
  if AClient.CurrentRect.Width <= 1 then
    AClient.CurrentRect := TXCBRect.Create(AClient.CurrentRect.X, AClient.CurrentRect.Y, 600, AClient.CurrentRect.Height);
  if AClient.CurrentRect.Height <= 1 then
    AClient.CurrentRect := TXCBRect.Create(AClient.CurrentRect.X, AClient.CurrentRect.Y, AClient.CurrentRect.Width, 400);

  // New window placement:
  // Case A: Dialog placement (wtDialog or has TransientFor)
  // If the dialog doesn't have an explicit user-set position (HasUserPosition = False),
  // center it over its transient parent window or over the active workarea.
  if ((AClient.WindowType = wtDialog) or (AClient.TransientFor <> 0)) and
     not AClient.HasUserPosition and
     not (wsMaximizedHorz in AClient.State) and not (wsFullscreen in AClient.State) then
  begin
    ParentCli := nil;
    if AClient.TransientFor <> 0 then
    begin
      ParentCli := FindClientByClientWindow(AClient.TransientFor);
      if ParentCli = nil then
        ParentCli := FindClient(AClient.TransientFor);
      // Strictly ignore dock windows as transient parents
      if (ParentCli <> nil) and (ParentCli.WindowType = wtDock) then
        ParentCli := nil;
    end;
    if (ParentCli = nil) and (FActiveClient <> nil) and (FActiveClient <> AClient) and
       (FActiveClient.WindowType in [wtNormal, wtDialog]) then
      ParentCli := FActiveClient;

    if ParentCli <> nil then
    begin
      TargetMon := MonitorForClient(ParentCli);
      if TargetMon = nil then TargetMon := FPrimaryMonitor;
      PlaceX := ParentCli.CurrentRect.X + ((ParentCli.CurrentRect.Width - AClient.CurrentRect.Width) div 2);
      PlaceY := ParentCli.CurrentRect.Y + ((ParentCli.CurrentRect.Height - AClient.CurrentRect.Height) div 2);
    end
    else
    begin
      TargetMon := FPrimaryMonitor;
      if TargetMon <> nil then
      begin
        PlaceX := TargetMon.Workarea.X + ((TargetMon.Workarea.Width - AClient.CurrentRect.Width) div 2);
        PlaceY := TargetMon.Workarea.Y + ((TargetMon.Workarea.Height - AClient.CurrentRect.Height) div 2);
      end
      else
      begin
        PlaceX := 100;
        PlaceY := 100;
      end;
    end;

    if TargetMon <> nil then
    begin
      if PlaceX + AClient.CurrentRect.Width > TargetMon.Workarea.Right() then
        PlaceX := Max(TargetMon.Workarea.X, TargetMon.Workarea.Right() - AClient.CurrentRect.Width);
      if PlaceY + AClient.CurrentRect.Height > TargetMon.Workarea.Bottom() then
        PlaceY := Max(TargetMon.Workarea.Y, TargetMon.Workarea.Bottom() - AClient.CurrentRect.Height);
      if PlaceX < TargetMon.Workarea.X then PlaceX := TargetMon.Workarea.X;
      if PlaceY < TargetMon.Workarea.Y then PlaceY := TargetMon.Workarea.Y;
    end;

    AClient.CurrentRect := TXCBRect.Create(PlaceX, PlaceY, AClient.CurrentRect.Width, AClient.CurrentRect.Height);
  end
  // Case B: Regular windows without explicit coordinates: follow pointer
  else if (AClient.CurrentRect.X = 0) and (AClient.CurrentRect.Y = 0) and
          not AClient.HasUserPosition and not AClient.HasProgramPosition and
          not (wsMaximizedHorz in AClient.State) and not (wsFullscreen in AClient.State) then
  begin
    PtrCookie := xcb_query_pointer(FConn, FRootWindow);
    PtrReply := xcb_query_pointer_reply(FConn, PtrCookie, nil);
    if PtrReply <> nil then
    begin
      TargetMon := MonitorForPoint(PtrReply^.root_x, PtrReply^.root_y);
      if TargetMon = nil then TargetMon := FPrimaryMonitor;

      if TargetMon <> nil then
      begin
        PlaceX := PtrReply^.root_x - 30;
        PlaceY := PtrReply^.root_y - 20;
      end
      else
      begin
        PlaceX := PtrReply^.root_x;
        PlaceY := PtrReply^.root_y;
      end;

      if TargetMon <> nil then
      begin
        if PlaceX + AClient.CurrentRect.Width > TargetMon.Workarea.Right() then
          PlaceX := Max(TargetMon.Workarea.X, TargetMon.Workarea.Right() - AClient.CurrentRect.Width);
        if PlaceY + AClient.CurrentRect.Height > TargetMon.Workarea.Bottom() then
          PlaceY := Max(TargetMon.Workarea.Y, TargetMon.Workarea.Bottom() - AClient.CurrentRect.Height);
        if PlaceX < TargetMon.Workarea.X then PlaceX := TargetMon.Workarea.X;
        if PlaceY < TargetMon.Workarea.Y then PlaceY := TargetMon.Workarea.Y;
      end;

      AClient.CurrentRect := TXCBRect.Create(PlaceX, PlaceY, AClient.CurrentRect.Width, AClient.CurrentRect.Height);
      xcb_free(PtrReply);
    end;
  end;

  FrameRect := FFrameMetrics.ClientToFrameRect(AClient.CurrentRect);
  // Ensure the frame window is not placed off-screen above the top
  if FrameRect.Y < 0 then
    FrameRect.Y := 0;

  FrameWin := CreateFrameWindow(AClient, FrameRect);
  if FrameWin = 0 then Exit;

  AClient.FrameWindow := FrameWin;
  if AClient.CanResize then
    AClient.ResizeWindow := CreateResizeWindow(AClient, FrameRect)
  else
    AClient.ResizeWindow := 0;
  AClient.CurrentRect := FrameRect;
  AClient.IsReparented := True;

  ClientInnerRect := FFrameMetrics.FrameToClientInnerRect(FrameRect);

  xcb_reparent_window(
    FConn,
    AClient.ClientWindow,
    FrameWin,
    ClientInnerRect.X,
    ClientInnerRect.Y
  );

  // Resize client window to match inner frame
  Values[0] := ClientInnerRect.Width;
  Values[1] := ClientInnerRect.Height;
  xcb_configure_window(
    FConn,
    AClient.ClientWindow,
    XCB_CONFIG_WINDOW_WIDTH or XCB_CONFIG_WINDOW_HEIGHT,
    @Values[0]
  );

  // Passive grab on mouse button 1 for click-to-focus
  xcb_grab_button(
    FConn,
    0,
    AClient.ClientWindow,
    XCB_EVENT_MASK_BUTTON_PRESS,
    XCB_GRAB_MODE_SYNC,
    XCB_GRAB_MODE_ASYNC,
    XCB_NONE,
    XCB_NONE,
    XCB_BUTTON_INDEX_1,
    XCB_MOD_MASK_ANY
  );

  xcb_map_window(FConn, FrameWin);
  xcb_map_window(FConn, AClient.ClientWindow);
  if AClient.ResizeWindow <> 0 then
  begin
    xcb_map_window(FConn, AClient.ResizeWindow);
    Values[0] := FrameWin;
    Values[1] := XCB_STACK_MODE_BELOW;
    xcb_configure_window(FConn, AClient.ResizeWindow,
                         XCB_CONFIG_WINDOW_SIBLING or XCB_CONFIG_WINDOW_STACK_MODE,
                         @Values[0]);
  end;

  if FEwmhInitialized then
  begin
    Values[0] := FFrameMetrics.Insets.Left;
    Values[1] := FFrameMetrics.Insets.Right;
    Values[2] := FFrameMetrics.Insets.Top;
    Values[3] := FFrameMetrics.Insets.Bottom;
    xcb_change_property(
      FConn,
      XCB_PROP_MODE_REPLACE,
      AClient.ClientWindow,
      FEwmh._NET_FRAME_EXTENTS,
      XCB_ATOM_CARDINAL,
      32,
      4,
      @Values[0]
    );
  end;

  xcb_flush(FConn);

  // Send synthetic ConfigureNotify per ICCCM 4.1.4
  SendSyntheticConfigureNotify(AClient);
end;

procedure TXCBWindowManager.SendSyntheticConfigureNotify(const AClient: TXCBWMClient);
var
  Ce: xcb_configure_notify_event_t;
  InnerRect: TXCBRect;
begin
  if (FConn = nil) or (AClient = nil) or (AClient.ClientWindow = 0) then Exit;

  FillChar(Ce, SizeOf(Ce), 0);
  Ce.response_type := XCB_CONFIGURE_NOTIFY;
  Ce.event := AClient.ClientWindow;
  Ce.window := AClient.ClientWindow;
  Ce.above_sibling := XCB_NONE;

  if AClient.IsReparented then
  begin
    InnerRect := FFrameMetrics.FrameToClientInnerRect(AClient.CurrentRect);
    // Per ICCCM: coordinates must be in root window coordinate space
    Ce.x := SmallInt(AClient.CurrentRect.X + InnerRect.X);
    Ce.y := SmallInt(AClient.CurrentRect.Y + InnerRect.Y);
    Ce.width := Word(InnerRect.Width);
    Ce.height := Word(InnerRect.Height);
  end
  else
  begin
    Ce.x := SmallInt(AClient.CurrentRect.X);
    Ce.y := SmallInt(AClient.CurrentRect.Y);
    Ce.width := Word(AClient.CurrentRect.Width);
    Ce.height := Word(AClient.CurrentRect.Height);
  end;

  Ce.border_width := 0;
  Ce.override_redirect := 0;

  xcb_send_event(FConn, 0, AClient.ClientWindow,
                 XCB_EVENT_MASK_STRUCTURE_NOTIFY, PAnsiChar(@Ce));
  xcb_flush(FConn);
end;

procedure TXCBWindowManager.UnparentClient(const AClient: TXCBWMClient);
var
  ClientRootRect: TXCBRect;
begin
  if (AClient = nil) or (not AClient.IsReparented) or (FConn = nil) then Exit;

  ClientRootRect := FFrameMetrics.FrameToClientRootRect(AClient.CurrentRect);

  xcb_reparent_window(
    FConn,
    AClient.ClientWindow,
    FRootWindow,
    ClientRootRect.X,
    ClientRootRect.Y
  );

  if AClient.FrameWindow <> 0 then
  begin
    xcb_destroy_window(FConn, AClient.FrameWindow);
    AClient.FrameWindow := 0;
  end;

  if AClient.ResizeWindow <> 0 then
  begin
    xcb_destroy_window(FConn, AClient.ResizeWindow);
    AClient.ResizeWindow := 0;
  end;

  AClient.IsReparented := False;
  AClient.CurrentRect := ClientRootRect;
  xcb_flush(FConn);
end;

function TXCBWindowManager.ManageWindow(const AWindow: xcb_window_t): TXCBWMClient;
var
  Cli: TXCBWMClient;
  EventMask: Cardinal;
  Extents: array[0..3] of Cardinal;
begin
  Result := FindClient(AWindow);
  if Result <> nil then Exit;

  Cli := TXCBWMClient.Create(AWindow, Self);
  try
    if FConn <> nil then
      ReadClientProperties(Cli);

    // Bypass override-redirect
    if Cli.OverrideRedirect then
    begin
      Cli.Free();
      Exit(nil);
    end;

    // Bypass docks, desktops, splashes, menus, tooltips, notifications, and borderless windows from framing
    if (Cli.WindowType in [wtDock, wtDesktop, wtSplash, wtMenu, wtDropdownMenu, wtPopupMenu, wtTooltip, wtNotification, wtCombo, wtDnd]) or Cli.Borderless then
    begin
      Cli.IsReparented := False;
      if FConn <> nil then
      begin
        if FEwmhInitialized then
        begin
          Extents[0] := 0;
          Extents[1] := 0;
          Extents[2] := 0;
          Extents[3] := 0;
          xcb_change_property(
            FConn,
            XCB_PROP_MODE_REPLACE,
            Cli.ClientWindow,
            FEwmh._NET_FRAME_EXTENTS,
            XCB_ATOM_CARDINAL,
            32,
            4,
            @Extents[0]
          );
        end;
        xcb_map_window(FConn, Cli.ClientWindow);
        if Cli.WindowType = wtDesktop then
        begin
          Extents[0] := XCB_STACK_MODE_BELOW;
          xcb_configure_window(FConn, Cli.ClientWindow, XCB_CONFIG_WINDOW_STACK_MODE, @Extents[0]);
        end;
      end;
    end
    else
    begin
      if FConn <> nil then
        ReparentClient(Cli)
      else
      begin
        // In offline/mock mode
        Cli.CurrentRect := FFrameMetrics.ClientToFrameRect(Cli.CurrentRect);
        Cli.IsReparented := True;
      end;
    end;

    if (FConn <> nil) and not (Cli.WindowType in [wtDesktop, wtDock]) then
    begin
      // FOCUS_CHANGE on the client window is what lets the manager notice an
      // application calling XSetInputFocus itself, or focus reverting, instead of
      // trusting its own bookkeeping. Each connection has its own event mask, so
      // this does not interfere with the client's own selection.
      EventMask := XCB_EVENT_MASK_STRUCTURE_NOTIFY or XCB_EVENT_MASK_PROPERTY_CHANGE or
                   XCB_EVENT_MASK_FOCUS_CHANGE;
      xcb_change_window_attributes(FConn, Cli.ClientWindow, XCB_CW_EVENT_MASK, @EventMask);

      // Passive grabs on <Alt> + Button1 (move) and <Alt> + Button3 (resize).
      // The modifier comes from the resolved map, not the hardcoded Mod1, and the
      // NumLock variant is included so a locked keypad does not defeat the grab.
      xcb_grab_button(FConn, 0, Cli.ClientWindow, XCB_EVENT_MASK_BUTTON_PRESS,
                      XCB_GRAB_MODE_SYNC, XCB_GRAB_MODE_ASYNC, XCB_NONE, XCB_NONE,
                      XCB_BUTTON_INDEX_1, FModAlt);
      xcb_grab_button(FConn, 0, Cli.ClientWindow, XCB_EVENT_MASK_BUTTON_PRESS,
                      XCB_GRAB_MODE_SYNC, XCB_GRAB_MODE_ASYNC, XCB_NONE, XCB_NONE,
                      XCB_BUTTON_INDEX_1, FModAlt or FModNumLock);
      xcb_grab_button(FConn, 0, Cli.ClientWindow, XCB_EVENT_MASK_BUTTON_PRESS,
                      XCB_GRAB_MODE_SYNC, XCB_GRAB_MODE_ASYNC, XCB_NONE, XCB_NONE,
                      XCB_BUTTON_INDEX_3, FModAlt);
      xcb_grab_button(FConn, 0, Cli.ClientWindow, XCB_EVENT_MASK_BUTTON_PRESS,
                      XCB_GRAB_MODE_SYNC, XCB_GRAB_MODE_ASYNC, XCB_NONE, XCB_NONE,
                      XCB_BUTTON_INDEX_3, FModAlt or FModNumLock);
    end
    else if FConn <> nil then
    begin
      EventMask := XCB_EVENT_MASK_STRUCTURE_NOTIFY or XCB_EVENT_MASK_PROPERTY_CHANGE or
                   XCB_EVENT_MASK_FOCUS_CHANGE;
      xcb_change_window_attributes(FConn, Cli.ClientWindow, XCB_CW_EVENT_MASK, @EventMask);
    end;

    Cli.RestoredRect := Cli.CurrentRect;
    FClients.Add(Cli);
    if Cli.Strut.HasStrut() then
      RecomputeWorkarea();

    if (wsMaximizedHorz in Cli.State) and (wsMaximizedVert in Cli.State) then
    begin
      if Cli.CanMaximize then
      begin
        Cli.Maximize();
        SendSyntheticConfigureNotify(Cli);
      end
      else
      begin
        Exclude(Cli.FState, wsMaximizedHorz);
        Exclude(Cli.FState, wsMaximizedVert);
      end;
    end
    else if wsFullscreen in Cli.State then
    begin
      Exclude(Cli.FState, wsFullscreen);
      if Cli.CanMaximize then
      begin
        Cli.SetFullscreen(True);
        SendSyntheticConfigureNotify(Cli);
      end;
    end;

    Cli.UpdateEWMHState();
    Result := Cli;

    RefreshEWMHClientList();
    if FConn <> nil then
      xcb_flush(FConn);

    DoOnClientMapped(Cli);
  except
    Cli.Free();
    raise;
  end;
end;

procedure TXCBWindowManager.UnmanageWindow(const AClient: TXCBWMClient);
var
  Idx: Integer;
  HadStrut: Boolean;
  WmStateData: array[0..1] of Cardinal;
begin
  if AClient = nil then Exit;

  HadStrut := AClient.Strut.HasStrut();

  if FConn <> nil then
  begin
    if FAtomWMState <> 0 then
    begin
      WmStateData[0] := 0; // WithdrawnState
      WmStateData[1] := 0;
      xcb_change_property(FConn, XCB_PROP_MODE_REPLACE, AClient.ClientWindow, FAtomWMState, FAtomWMState, 32, 2, @WmStateData[0]);
    end;
  end;

  if FActiveClient = AClient then
    FActiveClient := nil;

  if FDragClient = AClient then
    EndDrag();

  DoOnClientUnmapped(AClient);
  RemoveFromMru(AClient);

  if AClient.IsReparented and (FConn <> nil) then
    UnparentClient(AClient);

  Idx := FClients.IndexOf(AClient);
  if Idx >= 0 then
    FClients.Delete(Idx);

  if HadStrut then
    RecomputeWorkarea();

  RefreshEWMHClientList();
  RefreshEWMHActiveWindow();
  if FConn <> nil then
    xcb_flush(FConn);
end;

function TXCBWindowManager.FindClient(const AWindow: xcb_window_t): TXCBWMClient;
var
  I: Integer;
  Cli: TXCBWMClient;
begin
  Result := nil;
  if AWindow = 0 then Exit;
  for I := 0 to FClients.Count - 1 do
  begin
    Cli := TXCBWMClient(FClients[I]);
    if (Cli.ClientWindow = AWindow) or (Cli.FrameWindow = AWindow) or (Cli.ResizeWindow = AWindow) then
      Exit(Cli);
  end;
end;

function TXCBWindowManager.FindClientByClientWindow(const AWindow: xcb_window_t): TXCBWMClient;
var
  I: Integer;
  Cli: TXCBWMClient;
begin
  Result := nil;
  if AWindow = 0 then Exit;
  for I := 0 to FClients.Count - 1 do
  begin
    Cli := TXCBWMClient(FClients[I]);
    if Cli.ClientWindow = AWindow then
      Exit(Cli);
  end;
end;

function TXCBWindowManager.FindClientByFrameWindow(const AWindow: xcb_window_t): TXCBWMClient;
var
  I: Integer;
  Cli: TXCBWMClient;
begin
  Result := nil;
  if AWindow = 0 then Exit;
  for I := 0 to FClients.Count - 1 do
  begin
    Cli := TXCBWMClient(FClients[I]);
    if Cli.FrameWindow = AWindow then
      Exit(Cli);
  end;
end;

function TXCBWindowManager.FindClientByResizeWindow(const AWindow: xcb_window_t): TXCBWMClient;
var
  I: Integer;
  Cli: TXCBWMClient;
begin
  Result := nil;
  if AWindow = 0 then Exit;
  for I := 0 to FClients.Count - 1 do
  begin
    Cli := TXCBWMClient(FClients[I]);
    if Cli.ResizeWindow = AWindow then
      Exit(Cli);
  end;
end;

procedure TXCBWindowManager.ScanWindows();
var
  Cookie: xcb_query_tree_cookie_t;
  Reply: Pxcb_query_tree_reply_t;
  Children: Pxcb_window_t;
  NumChildren: Integer;
  I: Integer;
  AttrCookie: xcb_get_window_attributes_cookie_t;
  AttrReply: Pxcb_get_window_attributes_reply_t;
begin
  if (FConn = nil) or (FRootWindow = 0) then Exit;

  Cookie := xcb_query_tree(FConn, FRootWindow);
  Reply := xcb_query_tree_reply(FConn, Cookie, nil);
  if Reply = nil then Exit;

  try
    NumChildren := xcb_query_tree_children_length(Reply);
    Children := xcb_query_tree_children(Reply);

    for I := 0 to NumChildren - 1 do
    begin
      if (Children[I] = FWMCheckWindow) or (Children[I] = FRootWindow) then Continue;

      AttrCookie := xcb_get_window_attributes(FConn, Children[I]);
      AttrReply := xcb_get_window_attributes_reply(FConn, AttrCookie, nil);
      if AttrReply <> nil then
      begin
        try
          if (AttrReply^.override_redirect = 0) and
             (AttrReply^.map_state <> XCB_MAP_STATE_UNMAPPED) then
          begin
            ManageWindow(Children[I]);
          end;
        finally
          xcb_free(AttrReply);
        end;
      end;
    end;
  finally
    xcb_free(Reply);
  end;
  RecomputeWorkarea();
end;

function TXCBWindowManager.ProcessEvent(const AEvent: Pxcb_generic_event_t): Boolean;
var
  EvType: Byte;
  MapEv: Pxcb_map_request_event_t;
  CfgEv: Pxcb_configure_request_event_t;
  UnmapEv: Pxcb_unmap_notify_event_t;
  DestroyEv: Pxcb_destroy_notify_event_t;
  BtnEv: Pxcb_button_press_event_t;
  MotionEv: Pxcb_motion_notify_event_t;
  ExposeEv: Pxcb_expose_event_t;
  MsgEv: Pxcb_client_message_event_t;
  PropEv: Pxcb_property_notify_event_t;
  FocusEv: Pxcb_focus_in_event_t;
  MsgData32: PCardinalArray;
  Cli: TXCBWMClient;
  FrameRect: TXCBRect;
  CfgValues: array[0..6] of Cardinal;
  CfgMask: Cardinal;
  newX, newY, newW, newH: Integer;
  valIdx: Integer;
  I: Integer;
  reqDragMode: TXCBDragMode;
  Dir: Cardinal;
  FrameExtentsData: array[0..3] of Cardinal;
  isMaximizedOrTiled: Boolean;
begin
  Result := False;
  if AEvent = nil then Exit;

  EvType := AEvent^.response_type and $7F;
  if FRandRAvailable and (FRandREventBase > 0) then
  begin
    if (EvType = FRandREventBase + XCB_RANDR_SCREEN_CHANGE_NOTIFY) or
       (EvType = FRandREventBase + XCB_RANDR_NOTIFY) then
    begin
      RefreshMonitors();
      DoOnMonitorsChanged();
      Result := True;
      Exit;
    end;
  end;

  case EvType of
    XCB_MAP_REQUEST:
    begin
      MapEv := Pxcb_map_request_event_t(AEvent);
      Cli := ManageWindow(MapEv^.window);
      if Cli <> nil then
        Cli.Activate();
      Result := True;
    end;

    XCB_CONFIGURE_REQUEST:
    begin
      CfgEv := Pxcb_configure_request_event_t(AEvent);
      Cli := FindClient(CfgEv^.window);
      if Cli <> nil then
      begin
        isMaximizedOrTiled := (wsMaximizedHorz in Cli.State) or (wsMaximizedVert in Cli.State) or
                              (wsFullscreen in Cli.State) or (wsTiledLeft in Cli.State) or (wsTiledRight in Cli.State);

        if (CfgEv^.window = Cli.ClientWindow) and Cli.IsReparented then
        begin
          newX := Cli.CurrentRect.X + FFrameMetrics.Insets.Left;
          newY := Cli.CurrentRect.Y + FFrameMetrics.Insets.Top;
          newW := Cli.CurrentRect.Width - FFrameMetrics.Insets.Left - FFrameMetrics.Insets.Right;
          newH := Cli.CurrentRect.Height - FFrameMetrics.Insets.Top - FFrameMetrics.Insets.Bottom;

          if (CfgEv^.value_mask and XCB_CONFIG_WINDOW_X) <> 0 then newX := CfgEv^.x;
          if (CfgEv^.value_mask and XCB_CONFIG_WINDOW_Y) <> 0 then newY := CfgEv^.y;
          if (CfgEv^.value_mask and XCB_CONFIG_WINDOW_WIDTH) <> 0 then newW := CfgEv^.width;
          if (CfgEv^.value_mask and XCB_CONFIG_WINDOW_HEIGHT) <> 0 then newH := CfgEv^.height;

          FrameRect := FFrameMetrics.ClientToFrameRect(TXCBRect.Create(newX, newY, newW, newH));
          if FrameRect.Y < 0 then
            FrameRect.Y := 0;

          if isMaximizedOrTiled then
          begin
            Cli.RestoredRect := FrameRect;
            SendSyntheticConfigureNotify(Cli);
          end
          else
          begin
            Cli.SetGeometry(FrameRect.X, FrameRect.Y, FrameRect.Width, FrameRect.Height);
            SendSyntheticConfigureNotify(Cli);
          end;
        end
        else
        begin
          newX := Cli.CurrentRect.X;
          newY := Cli.CurrentRect.Y;
          newW := Cli.CurrentRect.Width;
          newH := Cli.CurrentRect.Height;

          if (CfgEv^.value_mask and XCB_CONFIG_WINDOW_X) <> 0 then newX := CfgEv^.x;
          if (CfgEv^.value_mask and XCB_CONFIG_WINDOW_Y) <> 0 then newY := CfgEv^.y;
          if (CfgEv^.value_mask and XCB_CONFIG_WINDOW_WIDTH) <> 0 then newW := CfgEv^.width;
          if (CfgEv^.value_mask and XCB_CONFIG_WINDOW_HEIGHT) <> 0 then newH := CfgEv^.height;

          if isMaximizedOrTiled then
          begin
            Cli.RestoredRect := TXCBRect.Create(newX, newY, newW, newH);
            SendSyntheticConfigureNotify(Cli);
          end
          else
          begin
            Cli.SetGeometry(newX, newY, newW, newH);
            SendSyntheticConfigureNotify(Cli);
          end;
        end;

        if (CfgEv^.value_mask and XCB_CONFIG_WINDOW_STACK_MODE) <> 0 then
        begin
          if CfgEv^.stack_mode = XCB_STACK_MODE_ABOVE then
            Cli.Activate();
        end;
      end
      else
      begin
        // Forward configure request for unmanaged window with proper packed value list
        if FConn <> nil then
        begin
          valIdx := 0;
          if (CfgEv^.value_mask and XCB_CONFIG_WINDOW_X) <> 0 then
          begin
            CfgValues[valIdx] := CfgEv^.x;
            Inc(valIdx);
          end;
          if (CfgEv^.value_mask and XCB_CONFIG_WINDOW_Y) <> 0 then
          begin
            CfgValues[valIdx] := CfgEv^.y;
            Inc(valIdx);
          end;
          if (CfgEv^.value_mask and XCB_CONFIG_WINDOW_WIDTH) <> 0 then
          begin
            CfgValues[valIdx] := CfgEv^.width;
            Inc(valIdx);
          end;
          if (CfgEv^.value_mask and XCB_CONFIG_WINDOW_HEIGHT) <> 0 then
          begin
            CfgValues[valIdx] := CfgEv^.height;
            Inc(valIdx);
          end;
          if (CfgEv^.value_mask and XCB_CONFIG_WINDOW_BORDER_WIDTH) <> 0 then
          begin
            CfgValues[valIdx] := CfgEv^.border_width;
            Inc(valIdx);
          end;
          if (CfgEv^.value_mask and XCB_CONFIG_WINDOW_SIBLING) <> 0 then
          begin
            CfgValues[valIdx] := CfgEv^.sibling;
            Inc(valIdx);
          end;
          if (CfgEv^.value_mask and XCB_CONFIG_WINDOW_STACK_MODE) <> 0 then
          begin
            CfgValues[valIdx] := CfgEv^.stack_mode;
            Inc(valIdx);
          end;

          if valIdx > 0 then
            xcb_configure_window(FConn, CfgEv^.window, CfgEv^.value_mask, @CfgValues[0]);
          xcb_flush(FConn);
        end;
      end;
      Result := True;
    end;

    XCB_UNMAP_NOTIFY:
    begin
      UnmapEv := Pxcb_unmap_notify_event_t(AEvent);
      Cli := FindClientByClientWindow(UnmapEv^.window);
      if Cli <> nil then
      begin
        if not (wsMinimized in Cli.State) then
          UnmanageWindow(Cli);
      end;
      Result := True;
    end;

    XCB_DESTROY_NOTIFY:
    begin
      DestroyEv := Pxcb_destroy_notify_event_t(AEvent);
      Cli := FindClientByClientWindow(DestroyEv^.window);
      if Cli <> nil then
        UnmanageWindow(Cli);
      Result := True;
    end;

    XCB_BUTTON_PRESS:
    begin
      BtnEv := Pxcb_button_press_event_t(AEvent);
      Cli := FindClient(BtnEv^.event);
      if Cli <> nil then
      begin
        Cli.Activate();
        if FConn <> nil then
        begin
          if BtnEv^.event = Cli.ClientWindow then
            xcb_allow_events(FConn, XCB_ALLOW_REPLAY_POINTER, BtnEv^.time)
          else
            xcb_allow_events(FConn, XCB_ALLOW_ASYNC_POINTER, BtnEv^.time);
        end;

        // If clicked on frame titlebar
        if BtnEv^.event = Cli.FrameWindow then
        begin
          if BtnEv^.detail = XCB_BUTTON_INDEX_1 then
            BeginDrag(Cli, dmMove, BtnEv^.root_x, BtnEv^.root_y)
          else if BtnEv^.detail = XCB_BUTTON_INDEX_3 then
            BeginDrag(Cli, dmResize, BtnEv^.root_x, BtnEv^.root_y);
        end;
      end;
      Result := True;
    end;

    XCB_BUTTON_RELEASE:
    begin
      if FDragMode <> dmNone then
        EndDrag();
      Result := True;
    end;

    XCB_MOTION_NOTIFY:
    begin
      MotionEv := Pxcb_motion_notify_event_t(AEvent);
      if FDragMode <> dmNone then
        UpdateDrag(MotionEv^.root_x, MotionEv^.root_y);
      Result := True;
    end;

    XCB_MAPPING_NOTIFY:
    begin
      // The keyboard mapping changed (layout switch, remap, xmodmap). Passive
      // grabs on keycodes that no longer exist stop firing, so every binding must
      // be re-resolved and re-grabbed. MappingNotify is delivered to all clients
      // regardless of event mask.
      ResolveKeyBindings();
      RebindGlobalKeys();
      Result := True;
    end;

    XCB_FOCUS_IN:
    begin
      FocusEv := Pxcb_focus_in_event_t(AEvent);
      // Ignore the focus changes we caused ourselves.
      if not FSyncingFocus then
      begin
        // PointerRoot / None mean no client holds focus; keep the last active
        // client for the UI rather than blanking it.
        if (FocusEv^.detail <> XCB_NOTIFY_DETAIL_POINTER_ROOT) and
           (FocusEv^.detail <> XCB_NOTIFY_DETAIL_NONE) then
        begin
          Cli := FindClientByClientWindow(FocusEv^.event);
          if Cli = nil then
            Cli := FindClient(FocusEv^.event);
          if Cli <> nil then
            SyncActiveClientFromFocus(Cli);
        end;
      end;
      Result := True;
    end;

    XCB_FOCUS_OUT:
    begin
      // Focus leaving is not itself meaningful: the FocusIn that follows tells us
      // where it went. Just consume it so the default handler does not react.
      Result := True;
    end;

    XCB_EXPOSE:
    begin
      ExposeEv := Pxcb_expose_event_t(AEvent);
      Cli := FindClientByFrameWindow(ExposeEv^.window);
      if (Cli <> nil) and (ExposeEv^.count = 0) then
        DoOnFramePaint(Cli, Cli.CurrentRect);
      Result := True;
    end;

    XCB_CLIENT_MESSAGE:
    begin
      MsgEv := Pxcb_client_message_event_t(AEvent);
      MsgData32 := PCardinalArray(@MsgEv^.data.raw[0]);
      if FEwmhInitialized then
      begin
        if MsgEv^.type_ = FEwmh._NET_CURRENT_DESKTOP then
          SwitchDesktop(MsgData32^[0])
        else if MsgEv^.type_ = FEwmh._NET_ACTIVE_WINDOW then
        begin
          Cli := FindClientByClientWindow(MsgEv^.window);
          if Cli <> nil then Cli.Activate();
        end
        else if MsgEv^.type_ = FEwmh._NET_CLOSE_WINDOW then
        begin
          Cli := FindClientByClientWindow(MsgEv^.window);
          if Cli <> nil then Cli.Close();
        end
        else if MsgEv^.type_ = FEwmh._NET_WM_STATE then
        begin
          Cli := FindClientByClientWindow(MsgEv^.window);
          if Cli <> nil then
          begin
            if (MsgData32^[1] = FEwmh._NET_WM_STATE_MAXIMIZED_HORZ) or
               (MsgData32^[1] = FEwmh._NET_WM_STATE_MAXIMIZED_VERT) or
               (MsgData32^[2] = FEwmh._NET_WM_STATE_MAXIMIZED_HORZ) or
               (MsgData32^[2] = FEwmh._NET_WM_STATE_MAXIMIZED_VERT) then
            begin
              case MsgData32^[0] of
                0: Cli.Restore();
                1: Cli.Maximize();
                2: if (wsMaximizedHorz in Cli.State) then Cli.Restore() else Cli.Maximize();
              end;
            end
            else if (MsgData32^[1] = FEwmh._NET_WM_STATE_FULLSCREEN) or
                    (MsgData32^[2] = FEwmh._NET_WM_STATE_FULLSCREEN) then
            begin
              case MsgData32^[0] of
                0: Cli.SetFullscreen(False);
                1: Cli.SetFullscreen(True);
                2: Cli.SetFullscreen(not (wsFullscreen in Cli.State));
              end;
            end
            else if (MsgData32^[1] = FEwmh._NET_WM_STATE_HIDDEN) or
                    (MsgData32^[2] = FEwmh._NET_WM_STATE_HIDDEN) then
            begin
              case MsgData32^[0] of
                0: Cli.Unminimize();
                1: Cli.Minimize();
                2: if (wsMinimized in Cli.State) then Cli.Unminimize() else Cli.Minimize();
              end;
            end
            else if (MsgData32^[1] = FEwmh._NET_WM_STATE_ABOVE) or
                    (MsgData32^[2] = FEwmh._NET_WM_STATE_ABOVE) then
            begin
              case MsgData32^[0] of
                0: Exclude(Cli.FState, wsAbove);
                1: Include(Cli.FState, wsAbove);
                2: if (wsAbove in Cli.State) then Exclude(Cli.FState, wsAbove) else Include(Cli.FState, wsAbove);
              end;
              Cli.UpdateEWMHState();
            end;
          end;
        end
        else if MsgEv^.type_ = FEwmh._NET_SHOWING_DESKTOP then
        begin
          if MsgData32^[0] <> 0 then
          begin
            for I := 0 to FClients.Count - 1 do
            begin
              Cli := TXCBWMClient(FClients[I]);
              if not (wsMinimized in Cli.State) and Cli.IsReparented and
                 Cli.ShouldBeVisibleOnDesktop(FCurrentDesktop) then
                Cli.Minimize();
            end;
          end
          else
          begin
            for I := 0 to FClients.Count - 1 do
            begin
              Cli := TXCBWMClient(FClients[I]);
              if (wsMinimized in Cli.State) and Cli.ShouldBeVisibleOnDesktop(FCurrentDesktop) then
                Cli.Unminimize();
            end;
          end;
          xcb_change_property(
            FConn,
            XCB_PROP_MODE_REPLACE,
            FRootWindow,
            FEwmh._NET_SHOWING_DESKTOP,
            XCB_ATOM_CARDINAL,
            32,
            1,
            @MsgData32^[0]
          );
          xcb_flush(FConn);
        end
        else if MsgEv^.type_ = FEwmh._NET_WM_MOVERESIZE then
        begin
          Cli := FindClientByClientWindow(MsgEv^.window);
          if Cli = nil then
            Cli := FindClient(MsgEv^.window);
          if Cli <> nil then
          begin
            Dir := MsgData32^[2];
            if Dir = 11 then // _NET_WM_MOVERESIZE_CANCEL
            begin
              if FDragClient = Cli then
                EndDrag();
            end
            else
            begin
              case Dir of
                0: reqDragMode := dmResizeTopLeft;
                1: reqDragMode := dmResizeTop;
                2: reqDragMode := dmResizeTopRight;
                3: reqDragMode := dmResizeRight;
                4: reqDragMode := dmResizeBottomRight;
                5: reqDragMode := dmResizeBottom;
                6: reqDragMode := dmResizeBottomLeft;
                7: reqDragMode := dmResizeLeft;
                8, 10: reqDragMode := dmMove;
                9: reqDragMode := dmResizeBottomRight;
              else
                reqDragMode := dmNone;
              end;

              if reqDragMode <> dmNone then
              begin
                Cli.Activate();
                BeginDrag(Cli, reqDragMode, Integer(MsgData32^[0]), Integer(MsgData32^[1]));
              end;
            end;
          end;
        end
        else if MsgEv^.type_ = FEwmh._NET_MOVERESIZE_WINDOW then
        begin
          Cli := FindClientByClientWindow(MsgEv^.window);
          if Cli = nil then
            Cli := FindClient(MsgEv^.window);
          if Cli <> nil then
          begin
            isMaximizedOrTiled := (wsMaximizedHorz in Cli.State) or (wsMaximizedVert in Cli.State) or
                                  (wsFullscreen in Cli.State) or (wsTiledLeft in Cli.State) or (wsTiledRight in Cli.State);
            if Cli.IsDecorated() then
            begin
              newX := Cli.CurrentRect.X + FFrameMetrics.Insets.Left;
              newY := Cli.CurrentRect.Y + FFrameMetrics.Insets.Top;
              newW := Cli.CurrentRect.Width - FFrameMetrics.Insets.Left - FFrameMetrics.Insets.Right;
              newH := Cli.CurrentRect.Height - FFrameMetrics.Insets.Top - FFrameMetrics.Insets.Bottom;

              if (MsgData32^[0] and (1 shl 8)) <> 0 then newX := Integer(MsgData32^[1]);
              if (MsgData32^[0] and (1 shl 9)) <> 0 then newY := Integer(MsgData32^[2]);
              if Cli.CanResize then
              begin
                if (MsgData32^[0] and (1 shl 10)) <> 0 then newW := Integer(MsgData32^[3]);
                if (MsgData32^[0] and (1 shl 11)) <> 0 then newH := Integer(MsgData32^[4]);
              end;

              FrameRect := FFrameMetrics.ClientToFrameRect(TXCBRect.Create(newX, newY, newW, newH));
              if FrameRect.Y < 0 then
                FrameRect.Y := 0;

              if isMaximizedOrTiled then
              begin
                Cli.RestoredRect := FrameRect;
                SendSyntheticConfigureNotify(Cli);
              end
              else
              begin
                Cli.SetGeometry(FrameRect.X, FrameRect.Y, FrameRect.Width, FrameRect.Height);
                SendSyntheticConfigureNotify(Cli);
              end;
            end
            else
            begin
              newX := Cli.CurrentRect.X;
              newY := Cli.CurrentRect.Y;
              newW := Cli.CurrentRect.Width;
              newH := Cli.CurrentRect.Height;

              if (MsgData32^[0] and (1 shl 8)) <> 0 then newX := Integer(MsgData32^[1]);
              if (MsgData32^[0] and (1 shl 9)) <> 0 then newY := Integer(MsgData32^[2]);
              if Cli.CanResize then
              begin
                if (MsgData32^[0] and (1 shl 10)) <> 0 then newW := Integer(MsgData32^[3]);
                if (MsgData32^[0] and (1 shl 11)) <> 0 then newH := Integer(MsgData32^[4]);
              end;

              if isMaximizedOrTiled then
              begin
                Cli.RestoredRect := TXCBRect.Create(newX, newY, newW, newH);
                SendSyntheticConfigureNotify(Cli);
              end
              else
              begin
                Cli.SetGeometry(newX, newY, newW, newH);
                SendSyntheticConfigureNotify(Cli);
              end;
            end;
          end;
        end
        else if MsgEv^.type_ = FEwmh._NET_REQUEST_FRAME_EXTENTS then
        begin
          Cli := FindClientByClientWindow(MsgEv^.window);
          if (Cli <> nil) and (not Cli.IsDecorated()) then
          begin
            FrameExtentsData[0] := 0;
            FrameExtentsData[1] := 0;
            FrameExtentsData[2] := 0;
            FrameExtentsData[3] := 0;
          end
          else
          begin
            FrameExtentsData[0] := FFrameMetrics.Insets.Left;
            FrameExtentsData[1] := FFrameMetrics.Insets.Right;
            FrameExtentsData[2] := FFrameMetrics.Insets.Top;
            FrameExtentsData[3] := FFrameMetrics.Insets.Bottom;
          end;
          if FConn <> nil then
          begin
            xcb_change_property(
              FConn,
              XCB_PROP_MODE_REPLACE,
              MsgEv^.window,
              FEwmh._NET_FRAME_EXTENTS,
              XCB_ATOM_CARDINAL,
              32,
              4,
              @FrameExtentsData[0]
            );
            xcb_flush(FConn);
          end;
        end;
      end;

      if (FAtomWMChangeState <> 0) and (MsgEv^.type_ = FAtomWMChangeState) then
      begin
        Cli := FindClient(MsgEv^.window);
        if (Cli <> nil) and (MsgData32^[0] = 3 { IconicState }) then
          Cli.Minimize();
      end;
      Result := True;
    end;

    XCB_PROPERTY_NOTIFY:
    begin
      PropEv := Pxcb_property_notify_event_t(AEvent);
      Cli := FindClient(PropEv^.window);
      if Cli <> nil then
      begin
        if (PropEv^.atom = FAtomNetWmStrut) or (PropEv^.atom = FAtomNetWmStrutPartial) then
        begin
          ReadClientProperties(Cli);
          RecomputeWorkarea();
        end
        else if (PropEv^.atom = FAtomMotifWmHints) or
                (PropEv^.atom = XCB_ATOM_WM_NORMAL_HINTS) or
                (PropEv^.atom = XCB_ATOM_WM_TRANSIENT_FOR) or
                (FEwmhInitialized and (PropEv^.atom = FEwmh._NET_WM_WINDOW_TYPE)) then
        begin
          ReadClientProperties(Cli);
          DoOnClientPropertiesChanged(Cli);
        end
        else if FEwmhInitialized and ((PropEv^.atom = FEwmh._NET_WM_NAME) or (PropEv^.atom = XCB_ATOM_WM_NAME)) then
        begin
          ReadClientProperties(Cli);
          DoOnClientPropertiesChanged(Cli);
        end;
      end;
      Result := True;
    end;
  end;
end;

// Create the self-pipe used to wake the event pump from a signal handler.
// Non-blocking on both ends so a signal storm can never stall the handler.
procedure TXCBWindowManager.CreateWakeupPipe();
var
  fds: array[0..1] of cint;
begin
  if FWakeupPipeValid then Exit;

  if fpPipe(fds) <> 0 then
  begin
    FWakeupPipe[0] := -1;
    FWakeupPipe[1] := -1;
    FWakeupPipeValid := False;
    Exit;
  end;

  FWakeupPipe[0] := fds[0];
  FWakeupPipe[1] := fds[1];
  fpFcntl(FWakeupPipe[0], F_SETFL, O_NONBLOCK);
  fpFcntl(FWakeupPipe[1], F_SETFL, O_NONBLOCK);
  FWakeupPipeValid := True;
end;

procedure TXCBWindowManager.CloseWakeupPipe();
begin
  if not FWakeupPipeValid then Exit;
  if FWakeupPipe[0] >= 0 then fpClose(FWakeupPipe[0]);
  if FWakeupPipe[1] >= 0 then fpClose(FWakeupPipe[1]);
  FWakeupPipe[0] := -1;
  FWakeupPipe[1] := -1;
  FWakeupPipeValid := False;
end;

// Async-signal-safe: only sets flags and writes a single byte. No allocation,
// no stdio, no locks — the previous implementation called WriteLn and Halt from
// the handler, both of which are unsafe while blocked in the event pump.
procedure TXCBWindowManager.RequestShutdown();
var
  b: Byte;
begin
  FShutdownRequested := True;
  FIsRunning := False;
  if FWakeupPipeValid then
  begin
    b := 1;
    fpWrite(FWakeupPipe[1], b, 1);
  end;
end;

procedure TXCBWindowManager.DrainWakeupPipe();
var
  buf: array[0..63] of Byte;
  n: ssize_t;
begin
  if not FWakeupPipeValid then Exit;
  repeat
    n := fpRead(FWakeupPipe[0], buf[0], SizeOf(buf));
  until n <= 0;
end;

// One pump cycle: drain already-queued events, then select() on the X socket and
// the wakeup pipe. Returns True when at least one event was processed.
function TXCBWindowManager.PumpEventsOnce(const ATimeoutMs: Integer): Boolean;
var
  Event: Pxcb_generic_event_t;
  xcbFd: cint;
  readSet: TFDSet;
  timeval: TTimeVal;
  maxFd: cint;
  n: cint;
  drained: Integer;
begin
  Result := False;
  if FConn = nil then Exit;

  // 1. Events already sitting in xcb's internal queue.
  //
  //    xcb_poll_for_event is used deliberately in preference to
  //    xcb_poll_for_queued_event. The "queued" variant never reads the socket: if
  //    xcb has bytes buffered but not yet parsed into events (which can happen
  //    after a request/reply round-trip), the socket is empty, select() below
  //    stays quiet, and poll_for_queued_event reports nothing — the pump would
  //    sleep with events pending. xcb_poll_for_event does a zero-timeout poll on
  //    the fd, so it is still non-blocking and leaves the socket genuinely empty
  //    when it returns nil.
  //
  //    This is a robustness choice, not a fix for an observed stall: an earlier
  //    report of the pump missing events turned out to be stderr buffering in the
  //    diagnostic output, not a stalled queue. See docs/roadmap.md WM-04.
  drained := 0;
  repeat
    Event := xcb_poll_for_event(FConn);
    if Event = nil then Break;
    try
      ProcessEvent(Event);
      Result := True;
    finally
      xcb_free(Event);
    end;
    Inc(drained);
    // Bounded batch (WM-11). A client emitting a continuous stream — a
    // ConfigureNotify storm during a resize, or a 60 Hz video generating damage —
    // would otherwise keep this loop non-empty forever and starve DoOnTick, which
    // is where the shell presents. Leftover events stay queued and are picked up
    // by the next call, whose step 1 drains xcb's queue before selecting.
    if drained >= MAX_EVENTS_PER_PUMP then Break;
  until False;

  if Result then Exit;

  // 2. Wait for X input or a shutdown wakeup.
  xcbFd := xcb_get_file_descriptor(FConn);
  fpFD_ZERO(readSet);
  maxFd := -1;
  if xcbFd >= 0 then
  begin
    fpFD_SET(xcbFd, readSet);
    maxFd := xcbFd;
  end;
  if FWakeupPipeValid and (FWakeupPipe[0] >= 0) then
  begin
    fpFD_SET(FWakeupPipe[0], readSet);
    if FWakeupPipe[0] > maxFd then
      maxFd := FWakeupPipe[0];
  end;

  timeval.tv_sec := ATimeoutMs div 1000;
  timeval.tv_usec := (ATimeoutMs mod 1000) * 1000;

  n := fpSelect(maxFd + 1, @readSet, nil, nil, @timeval);
  if n < 0 then
  begin
    // EINTR is normal (a signal arrived); the loop re-checks the flag next pass.
    Exit;
  end;
  if n = 0 then Exit;

  // 3. Shutdown wakeup?
  if FWakeupPipeValid and (FWakeupPipe[0] >= 0) and (fpFD_ISSET(FWakeupPipe[0], readSet) <> 0) then
  begin
    DrainWakeupPipe();
    if FShutdownRequested then
    begin
      FIsRunning := False;
      Exit;
    end;
  end;

  // 4. Drain X events, bounded by the same batch limit as step 1.
  if (xcbFd >= 0) and (fpFD_ISSET(xcbFd, readSet) <> 0) then
  begin
    drained := 0;
    repeat
      Event := xcb_poll_for_event(FConn);
      if Event = nil then Break;
      try
        ProcessEvent(Event);
        Result := True;
      finally
        xcb_free(Event);
      end;
      Inc(drained);
      if drained >= MAX_EVENTS_PER_PUMP then Break;
    until False;
  end;
end;

procedure TXCBWindowManager.DoOnTick(const AElapsedMs: Integer);
begin
  // Default: no periodic work.
end;

procedure TXCBWindowManager.Run();
var
  started: QWord;
  elapsed: Integer;
begin
  if FConn = nil then Exit;

  CreateWakeupPipe();
  FShutdownRequested := False;
  FIsRunning := True;
  started := GetTickCount64();

  try
    while FIsRunning do
    begin
      PumpEventsOnce(FTickIntervalMs);

      elapsed := Integer(GetTickCount64() - started);
      started := GetTickCount64();
      if FIsRunning then
        DoOnTick(elapsed);
    end;
  finally
    FIsRunning := False;
    CloseWakeupPipe();
  end;
end;

procedure TXCBWindowManager.Stop();
begin
  // Stop() may be called from another thread or from a timer callback, so it must
  // wake the pump rather than merely clearing a flag the pump never re-reads.
  RequestShutdown();
end;

procedure TXCBWindowManager.SwitchDesktop(const ANewDesktop: Integer);
var
  OldDesktop, I: Integer;
  Cli: TXCBWMClient;
begin
  if (ANewDesktop < 0) or (ANewDesktop >= FDesktopCount) or (ANewDesktop = FCurrentDesktop) then Exit;

  OldDesktop := FCurrentDesktop;
  FCurrentDesktop := ANewDesktop;

  for I := 0 to FClients.Count - 1 do
  begin
    Cli := TXCBWMClient(FClients[I]);
    if Cli.ShouldBeVisibleOnDesktop(FCurrentDesktop) then
    begin
      if (not (wsMinimized in Cli.State)) and (FConn <> nil) then
      begin
        if Cli.IsReparented and (Cli.FrameWindow <> 0) then
          xcb_map_window(FConn, Cli.FrameWindow);
        xcb_map_window(FConn, Cli.ClientWindow);
        if Cli.ResizeWindow <> 0 then
          xcb_map_window(FConn, Cli.ResizeWindow);
      end;
    end
    else
    begin
      if FConn <> nil then
      begin
        if Cli.IsReparented and (Cli.FrameWindow <> 0) then
          xcb_unmap_window(FConn, Cli.FrameWindow);
        xcb_unmap_window(FConn, Cli.ClientWindow);
        if Cli.ResizeWindow <> 0 then
          xcb_unmap_window(FConn, Cli.ResizeWindow);
      end;
      if FActiveClient = Cli then
        FActiveClient := nil;
    end;
  end;

  if FConn <> nil then
  begin
    RefreshEWMHDesktop();
    xcb_flush(FConn);
  end;

  DoOnDesktopChanged(OldDesktop, FCurrentDesktop);
end;

procedure TXCBWindowManager.SetDesktopCount(const ACount: Integer);
begin
  if ACount < 1 then Exit;
  FDesktopCount := ACount;
  while FDesktopNames.Count < FDesktopCount do
    FDesktopNames.Add(IntToStr(FDesktopNames.Count + 1));
  while FDesktopNames.Count > FDesktopCount do
    FDesktopNames.Delete(FDesktopNames.Count - 1);

  if FCurrentDesktop >= FDesktopCount then
    SwitchDesktop(FDesktopCount - 1)
  else
    RefreshEWMHDesktop();
end;

// Focus arrived from the server rather than from us. Keep the manager's notion of
// the active client in step, but do not raise or re-assert focus: doing so would
// either fight the client that just took focus or loop through FocusIn.
procedure TXCBWindowManager.SyncActiveClientFromFocus(const AClient: TXCBWMClient);
var
  OldCli: TXCBWMClient;
begin
  if AClient = nil then Exit;
  if AClient = FActiveClient then Exit;

  // Only manage real, visible clients.
  if not AClient.IsReparented and (AClient.WindowType <> wtDesktop) then Exit;
  if wsMinimized in AClient.State then Exit;

  FSyncingFocus := True;
  try
    OldCli := FActiveClient;
    if OldCli <> nil then
      Exclude(OldCli.FState, wsFocused);

    FActiveClient := AClient;
    Include(AClient.FState, wsFocused);

    if FConn <> nil then
    begin
      RefreshEWMHActiveWindow();
      xcb_flush(FConn);
    end;

    DoOnClientActivated(AClient);
  finally
    FSyncingFocus := False;
  end;
end;

procedure TXCBWindowManager.SetActiveClient(const AClient: TXCBWMClient);begin
  if FActiveClient = AClient then Exit;
  if AClient <> nil then
    AClient.Activate()
  else
  begin
    if FActiveClient <> nil then
      Exclude(FActiveClient.FState, wsFocused);
    FActiveClient := nil;
    RefreshEWMHActiveWindow();
  end;
end;

procedure TXCBWindowManager.BeginDrag(const AClient: TXCBWMClient; const AMode: TXCBDragMode; const ARootX, ARootY: Integer);
var
  Cookie: xcb_grab_pointer_cookie_t;
  Reply: Pxcb_grab_pointer_reply_t;
  dragCursor: xcb_cursor_t;
  grabStatus: Byte;
  grabbed: Boolean;
begin
  if (AClient = nil) or (AMode = dmNone) then Exit;
  if AClient.WindowType in [wtDesktop, wtDock] then Exit;
  if (AMode <> dmMove) and (not AClient.CanResize) then Exit;

  dragCursor := CursorForDragMode(AMode);
  if dragCursor = 0 then dragCursor := XCB_NONE;

  // The grab must succeed *before* we enter drag state. Committing FDragClient /
  // FDragMode first meant a refused grab (AlreadyGrabbed after a lost release,
  // or a client already holding the pointer via _NET_WM_MOVERESIZE) left the WM
  // convinced it was dragging while owning nothing — the window then followed the
  // cursor until the next click.
  grabbed := True;
  if FConn <> nil then
  begin
    Cookie := xcb_grab_pointer(
      FConn,
      0,
      FRootWindow,
      XCB_EVENT_MASK_BUTTON_RELEASE or XCB_EVENT_MASK_POINTER_MOTION,
      XCB_GRAB_MODE_ASYNC,
      XCB_GRAB_MODE_ASYNC,
      FRootWindow,
      dragCursor,
      XCB_CURRENT_TIME
    );
    Reply := xcb_grab_pointer_reply(FConn, Cookie, nil);
    grabbed := False;
    if Reply <> nil then
    begin
      try
        grabStatus := Reply^.status;
      finally
        xcb_free(Reply);
      end;

      if grabStatus <> XCB_GRAB_STATUS_SUCCESS then
      begin
        if FDragGrabFailureHook <> nil then
          FDragGrabFailureHook(grabStatus);
        // Do not leave a stale grab behind if the server thinks one exists.
        if grabStatus = XCB_GRAB_STATUS_ALREADY_GRABBED then
          xcb_ungrab_pointer(FConn, XCB_CURRENT_TIME);
        xcb_flush(FConn);
        Exit;
      end;
      grabbed := True;
    end
    else
    begin
      // No reply means the request could not be completed (connection gone).
      if FDragGrabFailureHook <> nil then
        FDragGrabFailureHook(255);
      Exit;
    end;
  end;

  if not grabbed then Exit;

  FDragClient := AClient;
  FDragMode := AMode;
  FDragStartPointer := TXCBPoint.Create(ARootX, ARootY);
  FDragStartRect := AClient.CurrentRect;

  if FConn <> nil then
    xcb_flush(FConn);
end;

procedure TXCBWindowManager.UpdateDrag(const ARootX, ARootY: Integer);
var
  DeltaX, DeltaY: Integer;
  NewX, NewY, NewW, NewH: Integer;
  MinW, MinH: Integer;
begin
  if (FDragClient = nil) or (FDragMode = dmNone) then Exit;
  if (FDragMode <> dmMove) and (not FDragClient.CanResize) then Exit;

  DeltaX := ARootX - FDragStartPointer.X;
  DeltaY := ARootY - FDragStartPointer.Y;

  if FDragMode = dmMove then
  begin
    FDragClient.Move(FDragStartRect.X + DeltaX, FDragStartRect.Y + DeltaY);
    Exit;
  end;

  NewX := FDragStartRect.X;
  NewY := FDragStartRect.Y;
  NewW := FDragStartRect.Width;
  NewH := FDragStartRect.Height;

  MinW := 100;
  MinH := 40;
  if (FDragClient.MinSize.X > 0) and (MinW < FDragClient.MinSize.X) then
    MinW := FDragClient.MinSize.X;
  if (FDragClient.MinSize.Y > 0) and (MinH < FDragClient.MinSize.Y) then
    MinH := FDragClient.MinSize.Y;

  case FDragMode of
    dmResize, dmResizeBottomRight:
    begin
      NewW := FDragStartRect.Width + DeltaX;
      NewH := FDragStartRect.Height + DeltaY;
    end;

    dmResizeRight:
    begin
      NewW := FDragStartRect.Width + DeltaX;
    end;

    dmResizeBottom:
    begin
      NewH := FDragStartRect.Height + DeltaY;
    end;

    dmResizeLeft:
    begin
      NewW := FDragStartRect.Width - DeltaX;
    end;

    dmResizeTop:
    begin
      NewH := FDragStartRect.Height - DeltaY;
    end;

    dmResizeTopLeft:
    begin
      NewW := FDragStartRect.Width - DeltaX;
      NewH := FDragStartRect.Height - DeltaY;
    end;

    dmResizeTopRight:
    begin
      NewW := FDragStartRect.Width + DeltaX;
      NewH := FDragStartRect.Height - DeltaY;
    end;

    dmResizeBottomLeft:
    begin
      NewW := FDragStartRect.Width - DeltaX;
      NewH := FDragStartRect.Height + DeltaY;
    end;
  end;

  // If window is in a tiled state, height and top edge are locked to full screen
  if (wsTiledLeft in FDragClient.State) or (wsTiledRight in FDragClient.State) then
  begin
    NewH := FDragStartRect.Height;
    if (wsTiledRight in FDragClient.State) and (NewW > FDragStartRect.X + FDragStartRect.Width - 50) then
      NewW := FDragStartRect.X + FDragStartRect.Width - 50;
    if (wsTiledLeft in FDragClient.State) and (FScreen <> nil) and (NewW > FScreen^.width_in_pixels - 50) then
      NewW := FScreen^.width_in_pixels - 50;
  end;

  if NewW < MinW then NewW := MinW;
  if NewH < MinH then NewH := MinH;
  if (FDragClient.MaxSize.X > 0) and (NewW > FDragClient.MaxSize.X) then
    NewW := FDragClient.MaxSize.X;
  if (FDragClient.MaxSize.Y > 0) and (NewH > FDragClient.MaxSize.Y) then
    NewH := FDragClient.MaxSize.Y;

  case FDragMode of
    dmResizeLeft, dmResizeTopLeft, dmResizeBottomLeft:
      NewX := FDragStartRect.X + (FDragStartRect.Width - NewW);
  end;

  if not ((wsTiledLeft in FDragClient.State) or (wsTiledRight in FDragClient.State)) then
  begin
    case FDragMode of
      dmResizeTop, dmResizeTopLeft, dmResizeTopRight:
        NewY := FDragStartRect.Y + (FDragStartRect.Height - NewH);
    end;
  end
  else
    NewY := FDragStartRect.Y;

  FDragClient.SetGeometry(NewX, NewY, NewW, NewH);
end;

procedure TXCBWindowManager.UpdateDragOrigin(const ARootX, ARootY: Integer; const ARect: TXCBRect);
begin
  FDragStartPointer := TXCBPoint.Create(ARootX, ARootY);
  FDragStartRect := ARect;
end;

procedure TXCBWindowManager.EndDrag();
begin
  if FDragMode = dmNone then Exit;

  if (FDragClient <> nil) and
     not ((wsMaximizedHorz in FDragClient.State) or (wsMaximizedVert in FDragClient.State) or
          (wsFullscreen in FDragClient.State) or (wsTiledLeft in FDragClient.State) or
          (wsTiledRight in FDragClient.State)) then
  begin
    FDragClient.RestoredRect := FDragClient.CurrentRect;
  end;

  if FConn <> nil then
  begin
    xcb_ungrab_pointer(FConn, XCB_CURRENT_TIME);
    xcb_flush(FConn);
  end;

  FDragClient := nil;
  FDragMode := dmNone;
end;

procedure TXCBWindowManager.DoOnClientMapped(const AClient: TXCBWMClient);
begin
  // Subclasses override
end;

procedure TXCBWindowManager.DoOnClientUnmapped(const AClient: TXCBWMClient);
begin
  // Subclasses override
end;

// Move a client to the front of the MRU order. Called whenever a client becomes
// active, so MRU[0] is always the current window and MRU[1] the previous one.
procedure TXCBWindowManager.TouchMru(const AClient: TXCBWMClient);
var
  Idx: Integer;
begin
  if AClient = nil then Exit;
  Idx := FMruClients.IndexOf(AClient);
  if Idx >= 0 then
    FMruClients.Delete(Idx);
  FMruClients.Insert(0, AClient);
end;

procedure TXCBWindowManager.RemoveFromMru(const AClient: TXCBWMClient);
var
  Idx: Integer;
begin
  if AClient = nil then Exit;
  Idx := FMruClients.IndexOf(AClient);
  if Idx >= 0 then
    FMruClients.Delete(Idx);
end;

procedure TXCBWindowManager.DoOnClientActivated(const AClient: TXCBWMClient);
begin
  // Keep MRU order current; subclasses override for their own bookkeeping.
  TouchMru(AClient);
end;

procedure TXCBWindowManager.DoOnClientConfigure(const AClient: TXCBWMClient);
begin
  // Subclasses override
end;

procedure TXCBWindowManager.DoOnClientMinimized(const AClient: TXCBWMClient);
begin
  // Subclasses override
end;

procedure TXCBWindowManager.DoOnClientRestored(const AClient: TXCBWMClient);
begin
  // Subclasses override
end;

procedure TXCBWindowManager.DoOnDesktopChanged(const AOldDesktop, ANewDesktop: Integer);
begin
  // Subclasses override
end;

procedure TXCBWindowManager.DoOnFramePaint(const AClient: TXCBWMClient; const ARect: TXCBRect);
begin
  if Assigned(FOnFramePaint) then
    FOnFramePaint(Self, AClient, ARect);
end;

procedure TXCBWindowManager.DoOnClientPropertiesChanged(const AClient: TXCBWMClient);
begin
  // Virtual method for subclasses (e.g. TWMSamaCompositingWM) to repaint frame/buttons
end;

end.
