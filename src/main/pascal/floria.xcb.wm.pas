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
  Classes, SysUtils, Contnrs,
  Floria.XCB,
  Floria.XCB.Cursor,
  Floria.XCB.EWMH,
  Floria.XCB.ICCCM;

const
  XCB_ALL_DESKTOPS = Cardinal($FFFFFFFF);
  XCB_MWM_HINTS_DECORATIONS = 1 shl 1;

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

  // Forward declarations
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

  // Frame painting delegate
  TXCBFramePaintEvent = procedure(ASender: TObject; AClient: TXCBWMClient; const ARect: TXCBRect) of object;

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
    FStrut               : TXCBStrutPartial;
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
    property Strut               : TXCBStrutPartial  read FStrut write FStrut;
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
    FWorkarea          : TXCBRect;
    
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
  public
    constructor Create(AConn: Pxcb_connection_t = nil; const AScreenNum: Integer = 0);
    destructor Destroy(); override;

    function ClaimOwnership(): Boolean; virtual;
    procedure InitEWMH();
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

    procedure SwitchDesktop(const ANewDesktop: Integer);
    procedure SetDesktopCount(const ACount: Integer);
    procedure SetActiveClient(const AClient: TXCBWMClient);
    procedure RecomputeWorkarea();

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
    property Workarea          : TXCBRect            read FWorkarea write FWorkarea;
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
    property Ewmh                  : xcb_ewmh_connection_t read FEwmh;
    property EwmhInitialized       : Boolean               read FEwmhInitialized;

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
  FStrut := TXCBStrutPartial.Create();
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
  OldCli: TXCBWMClient;
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
begin
  if (wsMaximizedHorz in FState) and (wsMaximizedVert in FState) then Exit;

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
  sw, sh: Integer;
begin
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
  sw, sh: Integer;
begin
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
  OtherCli: TXCBWMClient;
begin
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
  W, H: Integer;
begin
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
      if FManager.Screen <> nil then
      begin
        W := FManager.Screen^.width_in_pixels;
        H := FManager.Screen^.height_in_pixels;
      end
      else
      begin
        W := 1920;
        H := 1080;
      end;
      SetGeometry(0, 0, W, H);
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
end;

destructor TXCBWindowManager.Destroy();
begin
  if FCursorCtx <> nil then
  begin
    xcb_cursor_context_free(FCursorCtx);
    FCursorCtx := nil;
  end;
  FClients.Free();
  FDesktopNames.Free();
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

function TXCBWindowManager.ClaimOwnership(): Boolean;
var
  Values: array[0..0] of Cardinal;
  Cookie: xcb_void_cookie_t;
  Err: Pxcb_generic_error_t;
begin
  Result := False;
  if (FConn = nil) or (FRootWindow = 0) then Exit;

  Values[0] := XCB_EVENT_MASK_SUBSTRUCTURE_REDIRECT or
               XCB_EVENT_MASK_SUBSTRUCTURE_NOTIFY or
               XCB_EVENT_MASK_STRUCTURE_NOTIFY or
               XCB_EVENT_MASK_PROPERTY_CHANGE or
               XCB_EVENT_MASK_BUTTON_PRESS or
               XCB_EVENT_MASK_POINTER_MOTION;

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

  Result := True;
end;

procedure TXCBWindowManager.InitEWMH();
var
  Cookies: Pxcb_intern_atom_cookie_t;
  SuppAtoms: array[0..36] of xcb_atom_t;
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

  xcb_change_property(
    FConn,
    XCB_PROP_MODE_REPLACE,
    FRootWindow,
    FEwmh._NET_SUPPORTED,
    XCB_ATOM_ATOM,
    32,
    37,
    @SuppAtoms[0]
  );

  RefreshEWMHDesktop();
  RefreshEWMHClientList();
  xcb_flush(FConn);
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

procedure TXCBWindowManager.RecomputeWorkarea();
var
  MaxLeft, MaxRight, MaxTop, MaxBottom: Cardinal;
  ScreenWidth, ScreenHeight: Integer;
  NewWorkarea, OldWorkarea: TXCBRect;
  Cli: TXCBWMClient;
  I: Integer;
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

  MaxLeft := 0;
  MaxRight := 0;
  MaxTop := 0;
  MaxBottom := 0;

  for I := 0 to FClients.Count - 1 do
  begin
    Cli := TXCBWMClient(FClients[I]);
    if Cli.Strut.HasStrut() then
    begin
      if Cli.Strut.Left > MaxLeft then MaxLeft := Cli.Strut.Left;
      if Cli.Strut.Right > MaxRight then MaxRight := Cli.Strut.Right;
      if Cli.Strut.Top > MaxTop then MaxTop := Cli.Strut.Top;
      if Cli.Strut.Bottom > MaxBottom then MaxBottom := Cli.Strut.Bottom;
    end;
  end;

  NewWorkarea := TXCBRect.Create(
    MaxLeft,
    MaxTop,
    ScreenWidth - Integer(MaxLeft + MaxRight),
    ScreenHeight - Integer(MaxTop + MaxBottom)
  );
  if NewWorkarea.Width < 100 then NewWorkarea.Width := 100;
  if NewWorkarea.Height < 100 then NewWorkarea.Height := 100;

  if (NewWorkarea.X <> FWorkarea.X) or
     (NewWorkarea.Y <> FWorkarea.Y) or
     (NewWorkarea.Width <> FWorkarea.Width) or
     (NewWorkarea.Height <> FWorkarea.Height) then
  begin
    OldWorkarea := FWorkarea;
    FWorkarea := NewWorkarea;
    RefreshEWMHWorkarea();
    DoOnWorkareaChanged(OldWorkarea, NewWorkarea);
  end;
end;

procedure TXCBWindowManager.DoOnWorkareaChanged(const AOldWorkarea, ANewWorkarea: TXCBRect);
var
  I: Integer;
  Cli: TXCBWMClient;
  HalfW: Integer;
begin
  for I := 0 to FClients.Count - 1 do
  begin
    Cli := TXCBWMClient(FClients[I]);
    if (wsFullscreen in Cli.State) then
      Continue;

    if (wsMaximizedHorz in Cli.State) and (wsMaximizedVert in Cli.State) then
    begin
      Cli.SetGeometry(ANewWorkarea.X, ANewWorkarea.Y, ANewWorkarea.Width, ANewWorkarea.Height);
    end
    else if (wsTiledLeft in Cli.State) then
    begin
      HalfW := ANewWorkarea.Width div 2;
      Cli.SetGeometry(ANewWorkarea.X, ANewWorkarea.Y, HalfW, ANewWorkarea.Height);
    end
    else if (wsTiledRight in Cli.State) then
    begin
      HalfW := ANewWorkarea.Width div 2;
      Cli.SetGeometry(ANewWorkarea.X + HalfW, ANewWorkarea.Y, ANewWorkarea.Width - HalfW, ANewWorkarea.Height);
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
begin
  if (FConn = nil) or (AClient = nil) then Exit;

  // 1. Window Attributes
  AttrCookie := xcb_get_window_attributes(FConn, AClient.ClientWindow);
  AttrReply := xcb_get_window_attributes_reply(FConn, AttrCookie, nil);
  if AttrReply <> nil then
  begin
    AClient.OverrideRedirect := AttrReply^.override_redirect <> 0;
    xcb_free(AttrReply);
  end;

  // 2. Window Geometry
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
              AClient.Borderless := True;
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
begin
  if (AClient = nil) or AClient.IsReparented or (FConn = nil) then Exit;

  // If initial window geometry is minimal (e.g. 1x1 before configure), provide a reasonable default
  if AClient.CurrentRect.Width <= 1 then
    AClient.CurrentRect := TXCBRect.Create(AClient.CurrentRect.X, AClient.CurrentRect.Y, 600, AClient.CurrentRect.Height);
  if AClient.CurrentRect.Height <= 1 then
    AClient.CurrentRect := TXCBRect.Create(AClient.CurrentRect.X, AClient.CurrentRect.Y, AClient.CurrentRect.Width, 400);

  FrameRect := FFrameMetrics.ClientToFrameRect(AClient.CurrentRect);
  // Ensure the frame window is not placed off-screen above the top
  if FrameRect.Y < 0 then
    FrameRect.Y := 0;

  FrameWin := CreateFrameWindow(AClient, FrameRect);
  if FrameWin = 0 then Exit;

  AClient.FrameWindow := FrameWin;
  AClient.ResizeWindow := CreateResizeWindow(AClient, FrameRect);
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

  InnerRect := FFrameMetrics.FrameToClientInnerRect(AClient.CurrentRect);

  FillChar(Ce, SizeOf(Ce), 0);
  Ce.response_type := XCB_CONFIGURE_NOTIFY;
  Ce.event := AClient.ClientWindow;
  Ce.window := AClient.ClientWindow;
  Ce.above_sibling := XCB_NONE;
  // Per ICCCM: coordinates must be in root window coordinate space
  Ce.x := SmallInt(AClient.CurrentRect.X + InnerRect.X);
  Ce.y := SmallInt(AClient.CurrentRect.Y + InnerRect.Y);
  Ce.width := Word(InnerRect.Width);
  Ce.height := Word(InnerRect.Height);
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
        xcb_map_window(FConn, Cli.ClientWindow);
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

    if FConn <> nil then
    begin
      EventMask := XCB_EVENT_MASK_STRUCTURE_NOTIFY or XCB_EVENT_MASK_PROPERTY_CHANGE;
      xcb_change_window_attributes(FConn, Cli.ClientWindow, XCB_CW_EVENT_MASK, @EventMask);
    end;

    Cli.RestoredRect := Cli.CurrentRect;
    FClients.Add(Cli);
    if Cli.Strut.HasStrut() then
      RecomputeWorkarea();
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
    if FEwmhInitialized then
      xcb_delete_property(FConn, AClient.ClientWindow, FEwmh._NET_WM_STATE);
  end;

  if FActiveClient = AClient then
    FActiveClient := nil;

  if FDragClient = AClient then
    EndDrag();

  DoOnClientUnmapped(AClient);

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
  MsgData32: PCardinalArray;
  Cli: TXCBWMClient;
  FrameRect: TXCBRect;
  CfgValues: array[0..6] of Cardinal;
  CfgMask: Cardinal;
  newX, newY, newW, newH: Integer;
  valIdx: Integer;
  I: Integer;
begin
  Result := False;
  if AEvent = nil then Exit;

  EvType := AEvent^.response_type and $7F;
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
          Cli.SetGeometry(FrameRect.X, FrameRect.Y, FrameRect.Width, FrameRect.Height);
          SendSyntheticConfigureNotify(Cli);
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

          Cli.SetGeometry(newX, newY, newW, newH);
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
        else if FEwmhInitialized and ((PropEv^.atom = FEwmh._NET_WM_NAME) or (PropEv^.atom = XCB_ATOM_WM_NAME)) then
          ReadClientProperties(Cli);
      end;
      Result := True;
    end;
  end;
end;

procedure TXCBWindowManager.Run();
var
  Event: Pxcb_generic_event_t;
begin
  if FConn = nil then Exit;
  FIsRunning := True;
  while FIsRunning do
  begin
    Event := xcb_wait_for_event(FConn);
    if Event = nil then
      Break;
    try
      ProcessEvent(Event);
    finally
      xcb_free(Event);
    end;
  end;
  FIsRunning := False;
end;

procedure TXCBWindowManager.Stop();
begin
  FIsRunning := False;
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

procedure TXCBWindowManager.SetActiveClient(const AClient: TXCBWMClient);
begin
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
begin
  if (AClient = nil) or (AMode = dmNone) then Exit;

  FDragClient := AClient;
  FDragMode := AMode;
  FDragStartPointer := TXCBPoint.Create(ARootX, ARootY);
  FDragStartRect := AClient.CurrentRect;

  dragCursor := CursorForDragMode(AMode);
  if dragCursor = 0 then dragCursor := XCB_NONE;

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
    if Reply <> nil then
      xcb_free(Reply);
  end;
end;

procedure TXCBWindowManager.UpdateDrag(const ARootX, ARootY: Integer);
var
  DeltaX, DeltaY: Integer;
  NewX, NewY, NewW, NewH: Integer;
  MinW, MinH: Integer;
begin
  if (FDragClient = nil) or (FDragMode = dmNone) then Exit;

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

procedure TXCBWindowManager.DoOnClientActivated(const AClient: TXCBWMClient);
begin
  // Subclasses override
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

end.
