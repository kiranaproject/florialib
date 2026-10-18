unit Floria.XCB.WM.Test;

// Floria.XCB.WM.Test
// ==================
// Unit test suite for Floria.XCB.WM Window Manager framework.
// Validates geometry math, frame metrics, client state transitions,
// sizing constraints, virtual desktop visibility, and XCB integration.

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry,
  Floria.XCB,
  Floria.XCB.WM;

type
  TXCBWMTest = class(TTestCase)
  published
    procedure TestPointAndRect();
    procedure TestFrameMetrics();
    procedure TestWindowState();
    procedure TestClientLifecycleOffline();
    procedure TestClientMaximizeAndRestore();
    procedure TestClientTileAndRestore();
    procedure TestClientFullscreen();
    procedure TestClientSizeConstraints();
    procedure TestVirtualDesktops();
    procedure TestWindowFilteringTypes();
    procedure TestTitlebarRect();
    procedure TestInteractiveDrag();
    procedure TestConfigureRequestGeometry();
    procedure TestLiveConnectionIfAvailable();
    procedure TestStrutsAndRecomputeWorkarea();
    procedure TestDynamicWorkareaReflow();
    procedure TestMinimizeAndRestoreOffline();
  end;

implementation

procedure TXCBWMTest.TestPointAndRect();
var
  Pt: TXCBPoint;
  R: TXCBRect;
begin
  Pt := TXCBPoint.Create(10, 20);
  AssertEquals('Point X', 10, Pt.X);
  AssertEquals('Point Y', 20, Pt.Y);

  R := TXCBRect.Create(50, 60, 200, 150);
  AssertEquals('Rect X', 50, R.X);
  AssertEquals('Rect Y', 60, R.Y);
  AssertEquals('Rect Width', 200, R.Width);
  AssertEquals('Rect Height', 150, R.Height);
  AssertEquals('Rect Right', 250, R.Right());
  AssertEquals('Rect Bottom', 210, R.Bottom());

  AssertTrue('Contains point inside', R.Contains(Pt.Create(100, 100)));
  AssertTrue('Contains coords inside', R.Contains(50, 60)); // Top-left boundary
  AssertFalse('Does not contain point outside', R.Contains(49, 60));
  AssertFalse('Does not contain point at right boundary', R.Contains(250, 100));
end;

procedure TXCBWMTest.TestFrameMetrics();
var
  Metrics: TXCBFrameMetrics;
  ClientR, FrameR, InnerR, RootR: TXCBRect;
begin
  Metrics := TXCBFrameMetrics.Create(24, 2);
  AssertEquals('Titlebar height', 24, Metrics.TitlebarHeight);
  AssertEquals('Border width', 2, Metrics.BorderWidth);
  AssertEquals('Insets Left', 2, Metrics.Insets.Left);
  AssertEquals('Insets Top', 26, Metrics.Insets.Top); // 24 + 2
  AssertEquals('Insets Right', 2, Metrics.Insets.Right);
  AssertEquals('Insets Bottom', 2, Metrics.Insets.Bottom);

  ClientR := TXCBRect.Create(100, 100, 400, 300);
  FrameR := Metrics.ClientToFrameRect(ClientR);
  AssertEquals('Frame X', 98, FrameR.X); // 100 - 2
  AssertEquals('Frame Y', 74, FrameR.Y); // 100 - 26
  AssertEquals('Frame Width', 404, FrameR.Width); // 400 + 2 + 2
  AssertEquals('Frame Height', 328, FrameR.Height); // 300 + 26 + 2

  InnerR := Metrics.FrameToClientInnerRect(FrameR);
  AssertEquals('Inner client offset X', 2, InnerR.X);
  AssertEquals('Inner client offset Y', 26, InnerR.Y);
  AssertEquals('Inner client width', 400, InnerR.Width);
  AssertEquals('Inner client height', 300, InnerR.Height);

  RootR := Metrics.FrameToClientRootRect(FrameR);
  AssertEquals('Root client X', 100, RootR.X);
  AssertEquals('Root client Y', 100, RootR.Y);
  AssertEquals('Root client width', 400, RootR.Width);
  AssertEquals('Root client height', 300, RootR.Height);
end;

procedure TXCBWMTest.TestWindowState();
var
  State: TXCBWindowState;
begin
  State := [];
  AssertFalse('Initially empty', wsMaximizedHorz in State);

  Include(State, wsMaximizedHorz);
  Include(State, wsMaximizedVert);
  AssertTrue('Maximized horz', wsMaximizedHorz in State);
  AssertTrue('Maximized vert', wsMaximizedVert in State);

  Exclude(State, wsMaximizedHorz);
  AssertFalse('Maximized horz excluded', wsMaximizedHorz in State);
  AssertTrue('Maximized vert still present', wsMaximizedVert in State);

  Include(State, wsSticky);
  AssertTrue('Sticky present', wsSticky in State);
end;

procedure TXCBWMTest.TestClientLifecycleOffline();
var
  Mgr: TXCBWindowManager;
  Client: TXCBWMClient;
begin
  Mgr := TXCBWindowManager.Create(nil, 0);
  try
    AssertEquals('Initially zero clients', 0, Mgr.Clients.Count);
    AssertNull('Initially no active client', Mgr.ActiveClient);

    Client := Mgr.ManageWindow(12345);
    AssertNotNull('Client created', Client);
    AssertEquals('Client window ID', 12345, Client.ClientWindow);
    AssertEquals('Client count is 1', 1, Mgr.Clients.Count);
    AssertTrue('Reparented in offline mode', Client.IsReparented);

    AssertSame('Find client by window ID', Client, Mgr.FindClient(12345));

    Mgr.ActiveClient := Client;
    AssertSame('Active client set', Client, Mgr.ActiveClient);
    AssertTrue('Client state has wsFocused', wsFocused in Client.State);

    Mgr.UnmanageWindow(Client);
    AssertEquals('Client count after unmanage', 0, Mgr.Clients.Count);
    AssertNull('Active client cleared after unmanage', Mgr.ActiveClient);
  finally
    Mgr.Free();
  end;
end;

procedure TXCBWMTest.TestClientMaximizeAndRestore();
var
  Mgr: TXCBWindowManager;
  Client: TXCBWMClient;
  InitialR: TXCBRect;
begin
  Mgr := TXCBWindowManager.Create(nil, 0);
  try
    Mgr.Workarea := TXCBRect.Create(0, 30, 1920, 1050); // Simulating panel at top
    Client := Mgr.ManageWindow(999);
    Client.CurrentRect := TXCBRect.Create(100, 100, 500, 400);
    InitialR := Client.CurrentRect;

    Client.Maximize();
    AssertTrue('State has wsMaximizedHorz', wsMaximizedHorz in Client.State);
    AssertTrue('State has wsMaximizedVert', wsMaximizedVert in Client.State);
    AssertEquals('Maximized X', 0, Client.CurrentRect.X);
    AssertEquals('Maximized Y', 30, Client.CurrentRect.Y);
    AssertEquals('Maximized Width', 1920, Client.CurrentRect.Width);
    AssertEquals('Maximized Height', 1050, Client.CurrentRect.Height);
    AssertEquals('RestoredRect X preserved', InitialR.X, Client.RestoredRect.X);
    AssertEquals('RestoredRect Y preserved', InitialR.Y, Client.RestoredRect.Y);

    Client.Restore();
    AssertFalse('State cleared wsMaximizedHorz', wsMaximizedHorz in Client.State);
    AssertFalse('State cleared wsMaximizedVert', wsMaximizedVert in Client.State);
    AssertEquals('Restored X', InitialR.X, Client.CurrentRect.X);
    AssertEquals('Restored Y', InitialR.Y, Client.CurrentRect.Y);
    AssertEquals('Restored Width', InitialR.Width, Client.CurrentRect.Width);
    AssertEquals('Restored Height', InitialR.Height, Client.CurrentRect.Height);
  finally
    Mgr.Free();
  end;
end;

procedure TXCBWMTest.TestClientTileAndRestore();
var
  Mgr: TXCBWindowManager;
  Client: TXCBWMClient;
  InitialR: TXCBRect;
begin
  Mgr := TXCBWindowManager.Create(nil, 0);
  try
    Mgr.Workarea := TXCBRect.Create(0, 0, 1920, 1080);
    Client := Mgr.ManageWindow(888);
    Client.CurrentRect := TXCBRect.Create(150, 120, 700, 500);
    InitialR := Client.CurrentRect;

    // Tile Left
    Client.TileLeft();
    AssertTrue('State has wsTiledLeft', wsTiledLeft in Client.State);
    AssertFalse('State does not have wsTiledRight', wsTiledRight in Client.State);
    AssertEquals('Tiled Left X', 0, Client.CurrentRect.X);
    AssertEquals('Tiled Left Width', 1920 div 2, Client.CurrentRect.Width);
    AssertEquals('RestoredRect Width preserved', InitialR.Width, Client.RestoredRect.Width);
    AssertEquals('RestoredRect Height preserved', InitialR.Height, Client.RestoredRect.Height);

    // Restore from Tile Left
    Client.Restore();
    AssertFalse('State cleared wsTiledLeft', wsTiledLeft in Client.State);
    AssertEquals('Restored X', InitialR.X, Client.CurrentRect.X);
    AssertEquals('Restored Width', InitialR.Width, Client.CurrentRect.Width);
    AssertEquals('Restored Height', InitialR.Height, Client.CurrentRect.Height);

    // Tile Right
    Client.TileRight();
    AssertTrue('State has wsTiledRight', wsTiledRight in Client.State);
    AssertEquals('Tiled Right X', 1920 div 2, Client.CurrentRect.X);
    AssertEquals('Tiled Right Width', 1920 div 2, Client.CurrentRect.Width);

    // Maximize while Tiled
    Client.Maximize();
    AssertTrue('State has wsMaximizedHorz', wsMaximizedHorz in Client.State);
    AssertFalse('State cleared wsTiledRight', wsTiledRight in Client.State);
    AssertEquals('Maximized Width', 1920, Client.CurrentRect.Width);
    AssertEquals('RestoredRect still preserved after Maximize', InitialR.Width, Client.RestoredRect.Width);

    // Restore from Maximize
    Client.Restore();
    AssertFalse('State cleared wsMaximizedHorz', wsMaximizedHorz in Client.State);
    AssertEquals('Restored back to initial width', InitialR.Width, Client.CurrentRect.Width);
    AssertEquals('Restored back to initial height', InitialR.Height, Client.CurrentRect.Height);
  finally
    Mgr.Free();
  end;
end;

procedure TXCBWMTest.TestClientFullscreen();
var
  Mgr: TXCBWindowManager;
  Client: TXCBWMClient;
  InitialR: TXCBRect;
begin
  Mgr := TXCBWindowManager.Create(nil, 0);
  try
    Client := Mgr.ManageWindow(777);
    Client.CurrentRect := TXCBRect.Create(200, 150, 640, 480);
    InitialR := Client.CurrentRect;

    Client.SetFullscreen(True);
    AssertTrue('State has wsFullscreen', wsFullscreen in Client.State);
    AssertEquals('Fullscreen X', 0, Client.CurrentRect.X);
    AssertEquals('Fullscreen Y', 0, Client.CurrentRect.Y);

    Client.SetFullscreen(False);
    AssertFalse('State cleared wsFullscreen', wsFullscreen in Client.State);
    AssertEquals('Restored from fullscreen X', InitialR.X, Client.CurrentRect.X);
    AssertEquals('Restored from fullscreen Y', InitialR.Y, Client.CurrentRect.Y);
    AssertEquals('Restored from fullscreen Width', InitialR.Width, Client.CurrentRect.Width);
    AssertEquals('Restored from fullscreen Height', InitialR.Height, Client.CurrentRect.Height);
  finally
    Mgr.Free();
  end;
end;

procedure TXCBWMTest.TestClientSizeConstraints();
var
  Client: TXCBWMClient;
  Pt: TXCBPoint;
begin
  Client := TXCBWMClient.Create(1, nil);
  try
    Client.MinSize := TXCBPoint.Create(200, 150);
    Client.MaxSize := TXCBPoint.Create(800, 600);
    Client.BaseSize := TXCBPoint.Create(200, 150);
    Client.SizeInc := TXCBPoint.Create(50, 25);

    // Below min
    Pt := Client.ConstrainSize(100, 100);
    AssertEquals('Clamped to min width', 200, Pt.X);
    AssertEquals('Clamped to min height', 150, Pt.Y);

    // Above max
    Pt := Client.ConstrainSize(1000, 900);
    AssertEquals('Clamped to max width', 800, Pt.X);
    AssertEquals('Clamped to max height', 600, Pt.Y);

    // Increments (base 200 + 50*N, base 150 + 25*N)
    // 340 width -> 200 + (140 div 50)*50 = 200 + 100 = 300
    // 210 height -> 150 + (60 div 25)*25 = 150 + 50 = 200
    Pt := Client.ConstrainSize(340, 210);
    AssertEquals('Stepped width', 300, Pt.X);
    AssertEquals('Stepped height', 200, Pt.Y);
  finally
    Client.Free();
  end;
end;

procedure TXCBWMTest.TestVirtualDesktops();
var
  Mgr: TXCBWindowManager;
  Client1, Client2: TXCBWMClient;
begin
  Mgr := TXCBWindowManager.Create(nil, 0);
  try
    AssertEquals('Default 4 desktops', 4, Mgr.DesktopCount);
    AssertEquals('Current desktop 0', 0, Mgr.CurrentDesktop);
    AssertEquals('Desktop name 1', '1', Mgr.DesktopNames[0]);

    Client1 := Mgr.ManageWindow(101);
    Client1.SetDesktop(0);

    Client2 := Mgr.ManageWindow(102);
    Client2.SetDesktop(2);

    AssertTrue('Client 1 visible on desktop 0', Client1.ShouldBeVisibleOnDesktop(0));
    AssertFalse('Client 1 not visible on desktop 2', Client1.ShouldBeVisibleOnDesktop(2));

    AssertFalse('Client 2 not visible on desktop 0', Client2.ShouldBeVisibleOnDesktop(0));
    AssertTrue('Client 2 visible on desktop 2', Client2.ShouldBeVisibleOnDesktop(2));

    // Sticky client
    Client2.SetSticky(True);
    AssertTrue('Sticky client 2 visible on desktop 0', Client2.ShouldBeVisibleOnDesktop(0));
    AssertTrue('Sticky client 2 visible on desktop 1', Client2.ShouldBeVisibleOnDesktop(1));
    AssertTrue('Sticky client 2 visible on desktop 2', Client2.ShouldBeVisibleOnDesktop(2));

    // Switch desktop
    Mgr.SwitchDesktop(2);
    AssertEquals('Current desktop switched to 2', 2, Mgr.CurrentDesktop);

    // Dynamic desktop count resizing
    Mgr.DesktopCount := 6;
    AssertEquals('Desktop count increased to 6', 6, Mgr.DesktopCount);
    AssertEquals('Desktop name 6', '6', Mgr.DesktopNames[5]);
  finally
    Mgr.Free();
  end;
end;

procedure TXCBWMTest.TestWindowFilteringTypes();
var
  Mgr: TXCBWindowManager;
  DockClient, DeskClient, SplashClient, MenuClient, BorderlessClient: TXCBWMClient;
begin
  Mgr := TXCBWindowManager.Create(nil, 0);
  try
    // Dock window bypasses framing
    DockClient := TXCBWMClient.Create(501, Mgr);
    DockClient.WindowType := wtDock;
    Mgr.Clients.Add(DockClient);
    AssertFalse('Dock is not reparented', DockClient.IsReparented);

    // Desktop window bypasses framing
    DeskClient := TXCBWMClient.Create(502, Mgr);
    DeskClient.WindowType := wtDesktop;
    Mgr.Clients.Add(DeskClient);
    AssertFalse('Desktop window is not reparented', DeskClient.IsReparented);

    // Splash window bypasses framing
    SplashClient := TXCBWMClient.Create(503, Mgr);
    SplashClient.WindowType := wtSplash;
    Mgr.Clients.Add(SplashClient);
    AssertFalse('Splash is not reparented', SplashClient.IsReparented);

    // Menu window bypasses framing
    MenuClient := TXCBWMClient.Create(504, Mgr);
    MenuClient.WindowType := wtMenu;
    Mgr.Clients.Add(MenuClient);
    AssertFalse('Menu is not reparented', MenuClient.IsReparented);

    // Borderless client bypasses framing
    BorderlessClient := TXCBWMClient.Create(505, Mgr);
    BorderlessClient.Borderless := True;
    Mgr.Clients.Add(BorderlessClient);
    AssertFalse('Borderless client is not reparented', BorderlessClient.IsReparented);

    // Verify IsMenu and IsDecorated semantics
    AssertFalse('Splash is not decorated', SplashClient.IsDecorated());
    AssertFalse('Splash is not menu', SplashClient.IsMenu());
    AssertFalse('Dock is not decorated', DockClient.IsDecorated());
    AssertFalse('Dock is not menu', DockClient.IsMenu());
    AssertFalse('Borderless is not decorated', BorderlessClient.IsDecorated());
    AssertFalse('Borderless is not menu', BorderlessClient.IsMenu());
    AssertTrue('Menu is menu', MenuClient.IsMenu());
    AssertFalse('Menu is not decorated', MenuClient.IsDecorated());
  finally
    Mgr.Free();
  end;
end;

procedure TXCBWMTest.TestTitlebarRect();
var
  Mgr: TXCBWindowManager;
  Client: TXCBWMClient;
  TitleR: TXCBRect;
begin
  Mgr := TXCBWindowManager.Create(nil, 0);
  try
    Mgr.FrameMetrics := TXCBFrameMetrics.Create(28, 2);
    Client := Mgr.ManageWindow(888);
    Client.CurrentRect := TXCBRect.Create(50, 50, 600, 400);

    TitleR := Client.TitlebarRect();
    AssertEquals('Titlebar X', 0, TitleR.X);
    AssertEquals('Titlebar Y', 0, TitleR.Y);
    AssertEquals('Titlebar Width matches frame', 600, TitleR.Width);
    AssertEquals('Titlebar Height matches titlebar + border', 30, TitleR.Height); // 28 + 2
  finally
    Mgr.Free();
  end;
end;

procedure TXCBWMTest.TestInteractiveDrag();
var
  Mgr: TXCBWindowManager;
  Client: TXCBWMClient;
begin
  Mgr := TXCBWindowManager.Create(nil, 0);
  try
    Client := Mgr.ManageWindow(333);
    Client.CurrentRect := TXCBRect.Create(100, 100, 300, 200);

    // Test drag move
    Mgr.BeginDrag(Client, dmMove, 150, 110);
    AssertEquals('Drag mode move', Integer(dmMove), Integer(Mgr.DragMode));
    AssertSame('Drag client matches', Client, Mgr.DragClient);

    Mgr.UpdateDrag(170, 130); // Delta +20, +20
    AssertEquals('Moved X', 120, Client.CurrentRect.X);
    AssertEquals('Moved Y', 120, Client.CurrentRect.Y);
    AssertEquals('Width unchanged', 300, Client.CurrentRect.Width);
    AssertEquals('Height unchanged', 200, Client.CurrentRect.Height);

    Mgr.EndDrag();
    AssertEquals('Drag mode none after end', Integer(dmNone), Integer(Mgr.DragMode));
    AssertNull('Drag client nil after end', Mgr.DragClient);

    // Test drag resize (legacy dmResize)
    Mgr.BeginDrag(Client, dmResize, 420, 320);
    Mgr.UpdateDrag(450, 350); // Delta +30, +30
    AssertEquals('Resized Width', 330, Client.CurrentRect.Width);
    AssertEquals('Resized Height', 230, Client.CurrentRect.Height);
    Mgr.EndDrag();

    // Test dmResizeRight (width only)
    Client.CurrentRect := TXCBRect.Create(100, 100, 300, 200);
    Mgr.BeginDrag(Client, dmResizeRight, 400, 200);
    Mgr.UpdateDrag(440, 250); // DeltaX +40, DeltaY +50 (DeltaY should be ignored)
    AssertEquals('dmResizeRight Width', 340, Client.CurrentRect.Width);
    AssertEquals('dmResizeRight Height unchanged', 200, Client.CurrentRect.Height);
    AssertEquals('dmResizeRight X unchanged', 100, Client.CurrentRect.X);
    AssertEquals('dmResizeRight Y unchanged', 100, Client.CurrentRect.Y);
    Mgr.EndDrag();

    // Test dmResizeBottom (height only)
    Mgr.BeginDrag(Client, dmResizeBottom, 250, 300);
    Mgr.UpdateDrag(300, 360); // DeltaX +50 (ignored), DeltaY +60
    AssertEquals('dmResizeBottom Width unchanged', 340, Client.CurrentRect.Width);
    AssertEquals('dmResizeBottom Height', 260, Client.CurrentRect.Height);
    AssertEquals('dmResizeBottom X unchanged', 100, Client.CurrentRect.X);
    AssertEquals('dmResizeBottom Y unchanged', 100, Client.CurrentRect.Y);
    Mgr.EndDrag();

    // Test dmResizeLeft (width + X moved)
    Mgr.BeginDrag(Client, dmResizeLeft, 100, 200);
    Mgr.UpdateDrag(70, 250); // DeltaX -30 -> Width +30, X moves to 70
    AssertEquals('dmResizeLeft Width', 370, Client.CurrentRect.Width);
    AssertEquals('dmResizeLeft X', 70, Client.CurrentRect.X);
    AssertEquals('dmResizeLeft Height unchanged', 260, Client.CurrentRect.Height);
    AssertEquals('dmResizeLeft Y unchanged', 100, Client.CurrentRect.Y);
    Mgr.EndDrag();

    // Test dmResizeTop (height + Y moved)
    Mgr.BeginDrag(Client, dmResizeTop, 200, 100);
    Mgr.UpdateDrag(250, 60); // DeltaY -40 -> Height +40, Y moves to 60
    AssertEquals('dmResizeTop Height', 300, Client.CurrentRect.Height);
    AssertEquals('dmResizeTop Y', 60, Client.CurrentRect.Y);
    AssertEquals('dmResizeTop Width unchanged', 370, Client.CurrentRect.Width);
    AssertEquals('dmResizeTop X unchanged', 70, Client.CurrentRect.X);
    Mgr.EndDrag();

    // Test dmResizeTopLeft (both width/height and X/Y moved)
    Mgr.BeginDrag(Client, dmResizeTopLeft, 70, 60);
    Mgr.UpdateDrag(90, 80); // DeltaX +20 -> Width -20, DeltaY +20 -> Height -20
    AssertEquals('dmResizeTopLeft Width', 350, Client.CurrentRect.Width);
    AssertEquals('dmResizeTopLeft Height', 280, Client.CurrentRect.Height);
    AssertEquals('dmResizeTopLeft X', 90, Client.CurrentRect.X);
    AssertEquals('dmResizeTopLeft Y', 80, Client.CurrentRect.Y);
    Mgr.EndDrag();

    // Test Tiled Right window width resize with locked height
    Client.TileRight();
    AssertTrue('Client is tiled right', wsTiledRight in Client.State);
    // Initial tiled right rect is (960, 0, 960, 1080) for 1920x1080 default
    Mgr.BeginDrag(Client, dmResizeLeft, 960, 500);
    Mgr.UpdateDrag(860, 550); // Drag divider left by 100px; DeltaY should be locked!
    AssertEquals('Tiled Right Width expanded', 1060, Client.CurrentRect.Width);
    AssertEquals('Tiled Right X moved left', 860, Client.CurrentRect.X);
    AssertEquals('Tiled Right Height locked to 1080', 1080, Client.CurrentRect.Height);
    AssertEquals('Tiled Right Y locked to 0', 0, Client.CurrentRect.Y);
    AssertEquals('Tiled Right right-edge pinned', 1920, Client.CurrentRect.X + Client.CurrentRect.Width);
    Mgr.EndDrag();

    // Test Tiled Left window width resize with locked height
    Client.TileLeft();
    AssertTrue('Client is tiled left', wsTiledLeft in Client.State);
    // Initial tiled left rect is (0, 0, 960, 1080)
    Mgr.BeginDrag(Client, dmResizeRight, 960, 500);
    Mgr.UpdateDrag(800, 550); // Drag divider left by 160px; DeltaY should be locked!
    AssertEquals('Tiled Left Width shrunk', 800, Client.CurrentRect.Width);
    AssertEquals('Tiled Left X pinned to 0', 0, Client.CurrentRect.X);
    AssertEquals('Tiled Left Height locked to 1080', 1080, Client.CurrentRect.Height);
    AssertEquals('Tiled Left Y locked to 0', 0, Client.CurrentRect.Y);
    Mgr.EndDrag();
  finally
    Mgr.Free();
  end;
end;

procedure TXCBWMTest.TestConfigureRequestGeometry();
var
  Mgr: TXCBWindowManager;
  Client: TXCBWMClient;
  CfgEv: xcb_configure_request_event_t;
  InitialFrameH: Integer;
begin
  Mgr := TXCBWindowManager.Create(nil, 0);
  try
    Mgr.FrameMetrics := TXCBFrameMetrics.Create(24, 2);
    // Manage normal reparented window in offline mode
    Client := Mgr.ManageWindow(999);
    Client.CurrentRect := TXCBRect.Create(100, 100, 400, 300);
    Client.IsReparented := True;
    // Frame rect is (98, 74, 404, 328)
    Client.CurrentRect := Mgr.FrameMetrics.ClientToFrameRect(Client.CurrentRect);
    InitialFrameH := Client.CurrentRect.Height;

    // Simulate configure request with only X and Y (like SetPosition)
    FillChar(CfgEv, SizeOf(CfgEv), 0);
    CfgEv.response_type := XCB_CONFIGURE_REQUEST;
    CfgEv.window := 999;
    CfgEv.value_mask := XCB_CONFIG_WINDOW_X or XCB_CONFIG_WINDOW_Y;
    CfgEv.x := 150;
    CfgEv.y := 150;

    Mgr.ProcessEvent(Pxcb_generic_event_t(@CfgEv));

    // Height must NOT have grown
    AssertEquals('Frame height must stay constant after position change', InitialFrameH, Client.CurrentRect.Height);
  finally
    Mgr.Free();
  end;
end;

procedure TXCBWMTest.TestLiveConnectionIfAvailable();
var
  Conn: Pxcb_connection_t;
  ScreenNum: Integer;
  Mgr: TXCBWindowManager;
begin
  ScreenNum := 0;
  Conn := xcb_connect(nil, @ScreenNum);
  if Conn = nil then Exit;

  try
    if xcb_connection_has_error(Conn) = 0 then
    begin
      Mgr := TXCBWindowManager.Create(Conn, ScreenNum);
      try
        AssertTrue('Root window resolved', Mgr.RootWindow <> 0);
        AssertEquals('ScreenNum matches', ScreenNum, Mgr.ScreenNum);
        AssertNotNull('Screen handle resolved', Mgr.Screen);
        AssertTrue('Workarea width > 0', Mgr.Workarea.Width > 0);
        AssertTrue('Workarea height > 0', Mgr.Workarea.Height > 0);
      finally
        Mgr.Free();
      end;
    end;
  finally
    xcb_disconnect(Conn);
  end;
end;

procedure TXCBWMTest.TestStrutsAndRecomputeWorkarea();
var
  Mgr: TXCBWindowManager;
  Dock1, Dock2, Dock3: TXCBWMClient;
  S: TXCBStrutPartial;
begin
  Mgr := TXCBWindowManager.Create(nil, 0);
  try
    // Initial workarea in offline mode (screen is nil -> defaults to 1920x1080)
    AssertEquals('Initial Workarea X', 0, Mgr.Workarea.X);
    AssertEquals('Initial Workarea Y', 0, Mgr.Workarea.Y);
    AssertEquals('Initial Workarea Width', 1920, Mgr.Workarea.Width);
    AssertEquals('Initial Workarea Height', 1080, Mgr.Workarea.Height);

    // Add Top Dock with 38px strut
    Dock1 := Mgr.ManageWindow(101);
    Dock1.WindowType := wtDock;
    S := TXCBStrutPartial.Create();
    S.Top := 38;
    Dock1.Strut := S;
    Mgr.RecomputeWorkarea();

    AssertEquals('Workarea Y with top dock', 38, Mgr.Workarea.Y);
    AssertEquals('Workarea Height with top dock', 1042, Mgr.Workarea.Height);

    // Add Bottom Dock with 40px strut
    Dock2 := Mgr.ManageWindow(102);
    Dock2.WindowType := wtDock;
    S := TXCBStrutPartial.Create();
    S.Bottom := 40;
    Dock2.Strut := S;
    Mgr.RecomputeWorkarea();

    AssertEquals('Workarea Y with top+bottom dock', 38, Mgr.Workarea.Y);
    AssertEquals('Workarea Height with top+bottom dock', 1002, Mgr.Workarea.Height);

    // Add Left Dock with 60px strut
    Dock3 := Mgr.ManageWindow(103);
    Dock3.WindowType := wtDock;
    S := TXCBStrutPartial.Create();
    S.Left := 60;
    Dock3.Strut := S;
    Mgr.RecomputeWorkarea();

    AssertEquals('Workarea X with left dock', 60, Mgr.Workarea.X);
    AssertEquals('Workarea Width with left dock', 1860, Mgr.Workarea.Width);

    // Remove left dock
    Mgr.UnmanageWindow(Dock3);
    // UnmanageWindow calls RecomputeWorkarea when HadStrut is true
    AssertEquals('Workarea X after unmanaging left dock', 0, Mgr.Workarea.X);
    AssertEquals('Workarea Width after unmanaging left dock', 1920, Mgr.Workarea.Width);
    AssertEquals('Workarea Y preserved', 38, Mgr.Workarea.Y);
    AssertEquals('Workarea Height preserved', 1002, Mgr.Workarea.Height);
  finally
    Mgr.Free();
  end;
end;

procedure TXCBWMTest.TestDynamicWorkareaReflow();
var
  Mgr: TXCBWindowManager;
  CliMax, CliTile: TXCBWMClient;
  DockTop, DockLeft: TXCBWMClient;
  S: TXCBStrutPartial;
begin
  Mgr := TXCBWindowManager.Create(nil, 0);
  try
    CliMax := Mgr.ManageWindow(201);
    CliMax.Maximize();
    AssertEquals('Maximized window initial Y', 0, CliMax.CurrentRect.Y);
    AssertEquals('Maximized window initial Height', 1080, CliMax.CurrentRect.Height);

    CliTile := Mgr.ManageWindow(202);
    CliTile.TileLeft();
    AssertEquals('Tiled window initial X', 0, CliTile.CurrentRect.X);
    AssertEquals('Tiled window initial Width', 960, CliTile.CurrentRect.Width);
    AssertEquals('Tiled window initial Height', 1080, CliTile.CurrentRect.Height);

    // Add top dock with 48px strut
    DockTop := Mgr.ManageWindow(301);
    DockTop.WindowType := wtDock;
    S := TXCBStrutPartial.Create();
    S.Top := 48;
    DockTop.Strut := S;
    Mgr.RecomputeWorkarea();

    // Verify dynamic reflow of both windows
    AssertEquals('Maximized window reflowed Y', 48, CliMax.CurrentRect.Y);
    AssertEquals('Maximized window reflowed Height', 1032, CliMax.CurrentRect.Height);

    AssertEquals('Tiled window reflowed Y', 48, CliTile.CurrentRect.Y);
    AssertEquals('Tiled window reflowed Height', 1032, CliTile.CurrentRect.Height);

    // Add left dock with 70px strut
    DockLeft := Mgr.ManageWindow(302);
    DockLeft.WindowType := wtDock;
    S := TXCBStrutPartial.Create();
    S.Left := 70;
    DockLeft.Strut := S;
    Mgr.RecomputeWorkarea();

    // Workarea is now (70, 48, 1850, 1032)
    AssertEquals('Maximized window reflowed X', 70, CliMax.CurrentRect.X);
    AssertEquals('Maximized window reflowed Width', 1850, CliMax.CurrentRect.Width);

    AssertEquals('Tiled window reflowed X', 70, CliTile.CurrentRect.X);
    AssertEquals('Tiled window reflowed Width', 925, CliTile.CurrentRect.Width); // 1850 div 2

    // Unmanage left dock
    Mgr.UnmanageWindow(DockLeft);

    // Window reflows back to full width
    AssertEquals('Maximized window restored to full width', 1920, CliMax.CurrentRect.Width);
    AssertEquals('Tiled window restored to half width', 960, CliTile.CurrentRect.Width);
  finally
    Mgr.Free();
  end;
end;

procedure TXCBWMTest.TestMinimizeAndRestoreOffline();
var
  Mgr: TXCBWindowManager;
  Cli1, Cli2: TXCBWMClient;
begin
  Mgr := TXCBWindowManager.Create(nil, 0);
  try
    Cli1 := Mgr.ManageWindow(8001);
    Cli2 := Mgr.ManageWindow(8002);

    Cli1.Activate();
    AssertSame('Cli1 is active', Cli1, Mgr.ActiveClient);
    AssertTrue('Cli1 has focus', wsFocused in Cli1.State);
    AssertFalse('Cli1 not minimized', wsMinimized in Cli1.State);

    // 1. Direct Minimize
    Cli1.Minimize();
    AssertTrue('Cli1 is now minimized', wsMinimized in Cli1.State);
    AssertFalse('Cli1 lost focus', wsFocused in Cli1.State);
    // Next eligible window automatically activated
    AssertSame('Cli2 automatically activated', Cli2, Mgr.ActiveClient);

    // 2. Direct Unminimize
    Cli1.Unminimize();
    AssertFalse('Cli1 is no longer minimized', wsMinimized in Cli1.State);
    AssertTrue('Cli1 regained focus', wsFocused in Cli1.State);
    AssertSame('Cli1 is active again', Cli1, Mgr.ActiveClient);

    // 3. Activate on minimized window automatically unminimizes it
    Cli1.Minimize();
    AssertTrue('Cli1 minimized again', wsMinimized in Cli1.State);
    Cli1.Activate();
    AssertFalse('Cli1 unminimized on Activate', wsMinimized in Cli1.State);
    AssertSame('Cli1 active', Cli1, Mgr.ActiveClient);

    // 4. Restore on minimized window unminimizes it
    Cli1.Minimize();
    AssertTrue('Cli1 minimized', wsMinimized in Cli1.State);
    Cli1.Restore();
    AssertFalse('Cli1 unminimized on Restore', wsMinimized in Cli1.State);
  finally
    Mgr.Free();
  end;
end;

initialization
  RegisterTest(TXCBWMTest);

end.
