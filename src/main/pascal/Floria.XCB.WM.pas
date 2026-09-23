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
  Floria.XCB.EWMH,
  Floria.XCB.ICCCM;

const
  XCB_ALL_DESKTOPS = Cardinal($FFFFFFFF);

procedure xcb_free(p: Pointer); cdecl; external 'c' name 'free';

type
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
    wsFocused
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
    wtUtility,
    wtSplash
  );

  // Mouse interactive drag mode
  TXCBDragMode = (
    dmNone,
    dmMove,
    dmResize
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
  public
    constructor Create(const AClientWin: xcb_window_t; const AManager: TXCBWindowManager);
    destructor Destroy(); override;

    procedure Activate();
    procedure Close();
    procedure Maximize();
    procedure Restore();
    procedure Minimize();
    procedure SetFullscreen(const AFullscreen: Boolean);
    procedure Move(const AX, AY: Integer);
    procedure Resize(const AWidth, AHeight: Integer);
    procedure SetGeometry(const AX, AY, AWidth, AHeight: Integer);
    procedure SetDesktop(const ADesktopIndex: Integer);
    procedure SetSticky(const ASticky: Boolean);

    function ConstrainSize(const AWidth, AHeight: Integer): TXCBPoint;
    function ShouldBeVisibleOnDesktop(const ACurrentDesktop: Integer): Boolean;
    function TitlebarRect(): TXCBRect;

    property ClientWindow        : xcb_window_t      read FClientWindow;
    property FrameWindow         : xcb_window_t      read FFrameWindow write FFrameWindow;
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
    FAtomWMDeleteWindow: xcb_atom_t;
    FAtomWMTakeFocus   : xcb_atom_t;

    // Interactive Dragging
    FDragClient        : TXCBWMClient;
    FDragMode          : TXCBDragMode;
    FDragStartPointer  : TXCBPoint;
    FDragStartRect     : TXCBRect;

    FOnFramePaint      : TXCBFramePaintEvent;

    procedure RefreshEWMHClientList();
    procedure RefreshEWMHActiveWindow();
    procedure RefreshEWMHDesktop();
    procedure ReadClientProperties(const AClient: TXCBWMClient);
    function CreateFrameWindow(const AClient: TXCBWMClient; const ARect: TXCBRect): xcb_window_t;
  protected
    procedure DoOnClientMapped(const AClient: TXCBWMClient); virtual;
    procedure DoOnClientUnmapped(const AClient: TXCBWMClient); virtual;
    procedure DoOnClientActivated(const AClient: TXCBWMClient); virtual;
    procedure DoOnClientConfigure(const AClient: TXCBWMClient); virtual;
    procedure DoOnDesktopChanged(const AOldDesktop, ANewDesktop: Integer); virtual;
    procedure DoOnFramePaint(const AClient: TXCBWMClient; const ARect: TXCBRect); virtual;
  public
    constructor Create(AConn: Pxcb_connection_t = nil; const AScreenNum: Integer = 0);
    destructor Destroy(); override;

    function ClaimOwnership(): Boolean;
    procedure InitEWMH();
    procedure ScanWindows();
    function ManageWindow(const AWindow: xcb_window_t): TXCBWMClient;
    procedure UnmanageWindow(const AClient: TXCBWMClient);
    function FindClient(const AWindow: xcb_window_t): TXCBWMClient;
    function FindClientByClientWindow(const AWindow: xcb_window_t): TXCBWMClient;
    function FindClientByFrameWindow(const AWindow: xcb_window_t): TXCBWMClient;

    function ProcessEvent(const AEvent: Pxcb_generic_event_t): Boolean;
    procedure Run();
    procedure Stop();

    procedure SwitchDesktop(const ANewDesktop: Integer);
    procedure SetDesktopCount(const ACount: Integer);
    procedure SetActiveClient(const AClient: TXCBWMClient);

    // Reparenting and framing
    procedure ReparentClient(const AClient: TXCBWMClient);
    procedure UnparentClient(const AClient: TXCBWMClient);

    // Interactive dragging helpers
    procedure BeginDrag(const AClient: TXCBWMClient; const AMode: TXCBDragMode; const ARootX, ARootY: Integer);
    procedure UpdateDrag(const ARootX, ARootY: Integer);
    procedure EndDrag();

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
    property AtomWMDeleteWindow: xcb_atom_t          read FAtomWMDeleteWindow;
    property AtomWMTakeFocus   : xcb_atom_t          read FAtomWMTakeFocus;

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
end;

destructor TXCBWMClient.Destroy();
begin
  inherited Destroy();
end;

procedure TXCBWMClient.Activate();
var
  WinToRaise: xcb_window_t;
  Values: array[0..0] of Cardinal;
  Ev: xcb_client_message_event_t;
  Data32: PCardinalArray;
begin
  Include(FState, wsFocused);
  if FManager = nil then Exit;

  FManager.FActiveClient := Self;
  if FManager.Connection = nil then Exit;

  // Raise frame (or client window if direct/unparented)
  if FIsReparented and (FFrameWindow <> 0) then
    WinToRaise := FFrameWindow
  else
    WinToRaise := FClientWindow;

  Values[0] := XCB_STACK_MODE_ABOVE;
  xcb_configure_window(FManager.Connection, WinToRaise, XCB_CONFIG_WINDOW_STACK_MODE, @Values[0]);

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

  FRestoredRect := FCurrentRect;
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
  end;
end;

procedure TXCBWMClient.Restore();
begin
  if (wsMaximizedHorz in FState) or (wsMaximizedVert in FState) or (wsFullscreen in FState) then
  begin
    Exclude(FState, wsMaximizedHorz);
    Exclude(FState, wsMaximizedVert);
    Exclude(FState, wsFullscreen);

    if (FRestoredRect.Width > 0) and (FRestoredRect.Height > 0) then
      SetGeometry(FRestoredRect.X, FRestoredRect.Y, FRestoredRect.Width, FRestoredRect.Height);
  end;
end;

procedure TXCBWMClient.Minimize();
begin
  Include(FState, wsMinimized);
  Exclude(FState, wsFocused);
  if FManager = nil then Exit;

  if FManager.Connection <> nil then
  begin
    if FIsReparented and (FFrameWindow <> 0) then
      xcb_unmap_window(FManager.Connection, FFrameWindow);
    xcb_unmap_window(FManager.Connection, FClientWindow);
    xcb_flush(FManager.Connection);
  end;

  if FManager.ActiveClient = Self then
    FManager.ActiveClient := nil;
end;

procedure TXCBWMClient.SetFullscreen(const AFullscreen: Boolean);
var
  W, H: Integer;
begin
  if AFullscreen = (wsFullscreen in FState) then Exit;

  if AFullscreen then
  begin
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
    end;
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
  FDragClient := nil;
  FDragMode := dmNone;
  FDragStartPointer := TXCBPoint.Create(0, 0);
  FDragStartRect := TXCBRect.Create(0, 0, 0, 0);
  FOnFramePaint := nil;

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
  end;
end;

destructor TXCBWindowManager.Destroy();
begin
  FClients.Free();
  FDesktopNames.Free();
  inherited Destroy();
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
               XCB_EVENT_MASK_BUTTON_PRESS;

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

  Result := True;
end;

procedure TXCBWindowManager.InitEWMH();
var
  Cookies: Pxcb_intern_atom_cookie_t;
  SuppAtoms: array[0..15] of xcb_atom_t;
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

  xcb_change_property(
    FConn,
    XCB_PROP_MODE_REPLACE,
    FRootWindow,
    FEwmh._NET_SUPPORTED,
    XCB_ATOM_ATOM,
    32,
    16,
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

  // _NET_WORKAREA
  Geom[0] := FWorkarea.X;
  Geom[1] := FWorkarea.Y;
  Geom[2] := FWorkarea.Width;
  Geom[3] := FWorkarea.Height;
  xcb_change_property(
    FConn,
    XCB_PROP_MODE_REPLACE,
    FRootWindow,
    FEwmh._NET_WORKAREA,
    XCB_ATOM_CARDINAL,
    32,
    4,
    @Geom[0]
  );
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
    PropCookie := xcb_get_property(FConn, 0, AClient.ClientWindow, FEwmh._NET_WM_WINDOW_TYPE, XCB_ATOM_ATOM, 0, 1);
    PropReply := xcb_get_property_reply(FConn, PropCookie, nil);
    if PropReply <> nil then
    begin
      try
        if xcb_get_property_value_length(PropReply) >= SizeOf(xcb_atom_t) then
        begin
          AtomsPtr := Pxcb_atom_t(xcb_get_property_value(PropReply));
          if AtomsPtr^ = FEwmh._NET_WM_WINDOW_TYPE_DOCK then
            AClient.WindowType := wtDock
          else if AtomsPtr^ = FEwmh._NET_WM_WINDOW_TYPE_DESKTOP then
            AClient.WindowType := wtDesktop
          else if AtomsPtr^ = FEwmh._NET_WM_WINDOW_TYPE_DIALOG then
            AClient.WindowType := wtDialog
          else if AtomsPtr^ = FEwmh._NET_WM_WINDOW_TYPE_TOOLBAR then
            AClient.WindowType := wtToolbar
          else if AtomsPtr^ = FEwmh._NET_WM_WINDOW_TYPE_MENU then
            AClient.WindowType := wtMenu
          else if AtomsPtr^ = FEwmh._NET_WM_WINDOW_TYPE_UTILITY then
            AClient.WindowType := wtUtility
          else if AtomsPtr^ = FEwmh._NET_WM_WINDOW_TYPE_SPLASH then
            AClient.WindowType := wtSplash
          else
            AClient.WindowType := wtNormal;
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
end;

function TXCBWindowManager.CreateFrameWindow(const AClient: TXCBWMClient; const ARect: TXCBRect): xcb_window_t;
var
  FrameWin: xcb_window_t;
  ValueMask: Cardinal;
  ValueList: array[0..2] of Cardinal;
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
                  XCB_EVENT_MASK_ENTER_WINDOW;

  xcb_create_window(
    FConn,
    XCB_COPY_FROM_PARENT,
    FrameWin,
    FRootWindow,
    ARect.X,
    ARect.Y,
    ARect.Width,
    ARect.Height,
    FFrameMetrics.BorderWidth,
    XCB_WINDOW_CLASS_INPUT_OUTPUT,
    XCB_COPY_FROM_PARENT,
    ValueMask,
    @ValueList[0]
  );

  Result := FrameWin;
end;

procedure TXCBWindowManager.ReparentClient(const AClient: TXCBWMClient);
var
  FrameRect, ClientInnerRect: TXCBRect;
  FrameWin: xcb_window_t;
begin
  if (AClient = nil) or AClient.IsReparented or (FConn = nil) then Exit;

  FrameRect := FFrameMetrics.ClientToFrameRect(AClient.CurrentRect);
  FrameWin := CreateFrameWindow(AClient, FrameRect);
  if FrameWin = 0 then Exit;

  AClient.FrameWindow := FrameWin;
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

  AClient.IsReparented := False;
  AClient.CurrentRect := ClientRootRect;
  xcb_flush(FConn);
end;

function TXCBWindowManager.ManageWindow(const AWindow: xcb_window_t): TXCBWMClient;
var
  Cli: TXCBWMClient;
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

    // Bypass docks and desktops from framing
    if (Cli.WindowType = wtDock) or (Cli.WindowType = wtDesktop) then
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

    FClients.Add(Cli);
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
begin
  if AClient = nil then Exit;

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
    if (Cli.ClientWindow = AWindow) or (Cli.FrameWindow = AWindow) then
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
  MsgData32: PCardinalArray;
  Cli: TXCBWMClient;
  CfgValues: array[0..3] of Cardinal;
  CfgMask: Cardinal;
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
      Cli := FindClientByClientWindow(CfgEv^.window);
      if Cli <> nil then
      begin
        Cli.SetGeometry(CfgEv^.x, CfgEv^.y, CfgEv^.width, CfgEv^.height);
      end
      else
      begin
        // Forward configure request for unmanaged window
        if FConn <> nil then
        begin
          CfgMask := 0;
          CfgValues[0] := CfgEv^.x;
          CfgValues[1] := CfgEv^.y;
          CfgValues[2] := CfgEv^.width;
          CfgValues[3] := CfgEv^.height;
          if (CfgEv^.value_mask and XCB_CONFIG_WINDOW_X) <> 0 then CfgMask := CfgMask or XCB_CONFIG_WINDOW_X;
          if (CfgEv^.value_mask and XCB_CONFIG_WINDOW_Y) <> 0 then CfgMask := CfgMask or XCB_CONFIG_WINDOW_Y;
          if (CfgEv^.value_mask and XCB_CONFIG_WINDOW_WIDTH) <> 0 then CfgMask := CfgMask or XCB_CONFIG_WINDOW_WIDTH;
          if (CfgEv^.value_mask and XCB_CONFIG_WINDOW_HEIGHT) <> 0 then CfgMask := CfgMask or XCB_CONFIG_WINDOW_HEIGHT;
          xcb_configure_window(FConn, CfgEv^.window, CfgMask, @CfgValues[0]);
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
          xcb_allow_events(FConn, XCB_ALLOW_REPLAY_POINTER, BtnEv^.time);

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
            end;
          end;
        end;
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
      end;
    end
    else
    begin
      if FConn <> nil then
      begin
        if Cli.IsReparented and (Cli.FrameWindow <> 0) then
          xcb_unmap_window(FConn, Cli.FrameWindow);
        xcb_unmap_window(FConn, Cli.ClientWindow);
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
begin
  if (AClient = nil) or (AMode = dmNone) then Exit;

  FDragClient := AClient;
  FDragMode := AMode;
  FDragStartPointer := TXCBPoint.Create(ARootX, ARootY);
  FDragStartRect := AClient.CurrentRect;

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
      XCB_NONE,
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
  NewW, NewH: Integer;
  Constrained: TXCBPoint;
begin
  if (FDragClient = nil) or (FDragMode = dmNone) then Exit;

  DeltaX := ARootX - FDragStartPointer.X;
  DeltaY := ARootY - FDragStartPointer.Y;

  case FDragMode of
    dmMove:
      FDragClient.Move(FDragStartRect.X + DeltaX, FDragStartRect.Y + DeltaY);

    dmResize:
    begin
      NewW := FDragStartRect.Width + DeltaX;
      NewH := FDragStartRect.Height + DeltaY;
      Constrained := FDragClient.ConstrainSize(NewW, NewH);
      FDragClient.Resize(Constrained.X, Constrained.Y);
    end;
  end;
end;

procedure TXCBWindowManager.EndDrag();
begin
  if FDragMode = dmNone then Exit;

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
