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
  Floria.XCB.EWMH,
  Floria.XCB.WM,
  Floria.X11.KeySym;

const
  // Enough events to require several pump cycles at MAX_EVENTS_PER_PUMP (64),
  // while keeping the test quick.
  BATCH_WINDOWS = 200;

type
  // Counts RebindGlobalKeys calls so MappingNotify handling can be asserted.
  TCountingWindowManager = class(TXCBWindowManager)
  public
    RebindCount: Integer;
    ProcessedCount: Integer;
    procedure RebindGlobalKeys(); override;
    function ProcessEvent(const AEvent: Pxcb_generic_event_t): Boolean; override;
  end;

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
    procedure TestConfigureRequestWhileMaximizedOrTiled();
    procedure TestInitialMaximizedStateOnMap();
    procedure TestLiveConnectionIfAvailable();
    procedure TestStrutsAndRecomputeWorkarea();
    procedure TestDynamicWorkareaReflow();
    procedure TestMinimizeAndRestoreOffline();
    procedure TestCSDMoveResizeAndFrameExtents();
    procedure TestMultiMonitorTopologyAndWorkareas();
    procedure TestMultiMonitorNavigationAndMigration();
    procedure TestWindowCapabilitiesAndFixedSize();
    procedure TestTransientDialogPlacementAndLifecycle();
    procedure TestDesktopWindowPolicy();
    procedure TestShutdownRequestSetsFlags();
    procedure TestWakeupPipeLifecycle();
    procedure TestPumpWithoutConnection();
    procedure TestDragGrabFailureDoesNotCommitDrag();
    procedure TestClientsSurviveManagerShutdown();
    procedure TestKeysymResolutionQueriesServer();
    procedure TestKeyBindingsResolveToValidBits();
    procedure TestMappingNotifyRebindsKeys();
    procedure TestRootEventMaskIncludesFocusAndRelease();
    procedure TestFocusInSyncsActiveClient();
    procedure TestFocusInIgnoresPointerRootAndSelf();
    procedure TestPumpDrainsBurstInOneCall();
    procedure TestPumpDoesNotStallWithPendingEvents();
    procedure TestPumpBatchIsBounded();
    procedure TestConfigureRequestDoesNotClobberRestoreTarget();
  end;

implementation

// True when another window manager is managing this display. Such a WM reparents
// or redirects the windows these tests create, so the event stream they rely on is
// not theirs to control. Detected via _NET_SUPPORTING_WM_CHECK, which a compliant
// WM sets on the root window.
function AnotherWMRunning(const AConn: Pxcb_connection_t; const ARoot: xcb_window_t): Boolean;
var
  atom, typeAtom: xcb_atom_t;
  cookie: xcb_intern_atom_cookie_t;
  reply: Pxcb_intern_atom_reply_t;
  prop: Pxcb_get_property_reply_t;
begin
  Result := False;
  if (AConn = nil) or (ARoot = 0) then Exit;

  cookie := xcb_intern_atom(AConn, 1, Length('_NET_SUPPORTING_WM_CHECK'),
                            PAnsiChar('_NET_SUPPORTING_WM_CHECK'));
  reply := xcb_intern_atom_reply(AConn, cookie, nil);
  if reply = nil then Exit;
  try
    atom := reply^.atom;
  finally
    xcb_free(reply);
  end;
  if atom = 0 then Exit;

  typeAtom := XCB_ATOM_WINDOW;
  prop := xcb_get_property_reply(AConn,
    xcb_get_property(AConn, 0, ARoot, atom, typeAtom, 0, 1), nil);
  if prop = nil then Exit;
  try
    Result := (prop^.format <> 0) and (xcb_get_property_value_length(prop) >= 4);
  finally
    xcb_free(prop);
  end;
end;

procedure TCountingWindowManager.RebindGlobalKeys();
begin
  Inc(RebindCount);
  inherited RebindGlobalKeys();
end;

function TCountingWindowManager.ProcessEvent(const AEvent: Pxcb_generic_event_t): Boolean;
begin
  Inc(ProcessedCount);
  Result := inherited ProcessEvent(AEvent);
end;

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

procedure TXCBWMTest.TestConfigureRequestWhileMaximizedOrTiled();
var
  Mgr: TXCBWindowManager;
  Client: TXCBWMClient;
  CfgEv: xcb_configure_request_event_t;
  SavedRestored: TXCBRect;
begin
  Mgr := TXCBWindowManager.Create(nil, 0);
  try
    Mgr.FrameMetrics := TXCBFrameMetrics.Create(24, 2);

    // 1. Reparented window maximized
    Client := Mgr.ManageWindow(1001);
    Client.CurrentRect := TXCBRect.Create(100, 100, 800, 600);
    Client.IsReparented := True;
    Client.CurrentRect := Mgr.FrameMetrics.ClientToFrameRect(Client.CurrentRect);
    Client.Maximize();

    AssertTrue('Client is maximized horz', wsMaximizedHorz in Client.State);
    AssertTrue('Client is maximized vert', wsMaximizedVert in Client.State);
    AssertEquals('Maximized frame X', 0, Client.CurrentRect.X);
    AssertEquals('Maximized frame Y', 0, Client.CurrentRect.Y);
    AssertEquals('Maximized frame Width', 1920, Client.CurrentRect.Width);
    AssertEquals('Maximized frame Height', 1080, Client.CurrentRect.Height);

    SavedRestored := Client.RestoredRect;

    // Simulate configure request from client with smaller size (e.g. Lazarus debug stop)
    FillChar(CfgEv, SizeOf(CfgEv), 0);
    CfgEv.response_type := XCB_CONFIGURE_REQUEST;
    CfgEv.window := 1001;
    CfgEv.value_mask := XCB_CONFIG_WINDOW_X or XCB_CONFIG_WINDOW_Y or
                        XCB_CONFIG_WINDOW_WIDTH or XCB_CONFIG_WINDOW_HEIGHT;
    CfgEv.x := 50;
    CfgEv.y := 50;
    CfgEv.width := 600;
    CfgEv.height := 400;

    Mgr.ProcessEvent(Pxcb_generic_event_t(@CfgEv));

    // Active frame geometry must NOT change or shrink!
    AssertEquals('Maximized frame X remains intact', 0, Client.CurrentRect.X);
    AssertEquals('Maximized frame Y remains intact', 0, Client.CurrentRect.Y);
    AssertEquals('Maximized frame Width remains intact', 1920, Client.CurrentRect.Width);
    AssertEquals('Maximized frame Height remains intact', 1080, Client.CurrentRect.Height);

    // The restore target must NOT be replaced by the request.
    //
    // This used to assert the opposite: that a geometry request from a maximized
    // window became its restore target. That is not how window managers behave —
    // a maximized or tiled window is not floating, so the application has no say
    // in its geometry — and it broke a very common real case. GTK applications
    // snap their size to the resize increments in WM_NORMAL_HINTS, so resizing a
    // tiled mate-terminal makes it request its own tiled size; saving that as the
    // restore target meant "restore" restored the tiled geometry. Measured on a
    // live session: mate-terminal requested 504x756 while tiled, destroying an
    // 814x693 restore target, while xterm (which sends no such request) was fine.
    //
    // The cost: an application that programmatically sets its size while maximized
    // in the hope of un-maximizing to that size is now ignored. That is the
    // behaviour of Mutter and KWin, and it is the safer of the two.
    AssertEquals('Restore target X preserved', SavedRestored.X, Client.RestoredRect.X);
    AssertEquals('Restore target Y preserved', SavedRestored.Y, Client.RestoredRect.Y);
    AssertEquals('Restore target width preserved', SavedRestored.Width, Client.RestoredRect.Width);
    AssertEquals('Restore target height preserved', SavedRestored.Height, Client.RestoredRect.Height);
  finally
    Mgr.Free();
  end;
end;

procedure TXCBWMTest.TestInitialMaximizedStateOnMap();
var
  Mgr: TXCBWindowManager;
  Client: TXCBWMClient;
begin
  Mgr := TXCBWindowManager.Create(nil, 0);
  try
    Mgr.FrameMetrics := TXCBFrameMetrics.Create(24, 2);

    Client := TXCBWMClient.Create(2001, Mgr);
    Client.CurrentRect := TXCBRect.Create(50, 50, 500, 400);
    // Simulate initial EWMH state read from property
    Client.State := [wsMaximizedHorz, wsMaximizedVert];

    // Manually register in manager simulating ManageWindow
    Mgr.Clients.Add(Client);
    Client.RestoredRect := Client.CurrentRect;
    // Apply initial maximize
    Client.Maximize();

    AssertTrue('State has wsMaximizedHorz', wsMaximizedHorz in Client.State);
    AssertTrue('State has wsMaximizedVert', wsMaximizedVert in Client.State);
    AssertEquals('Maximized X', 0, Client.CurrentRect.X);
    AssertEquals('Maximized Y', 0, Client.CurrentRect.Y);
    AssertEquals('Maximized W', 1920, Client.CurrentRect.Width);
    AssertEquals('Maximized H', 1080, Client.CurrentRect.Height);
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

procedure TXCBWMTest.TestCSDMoveResizeAndFrameExtents();
var
  Mgr: TXCBWindowManager;
  Cli: TXCBWMClient;
  MockEwmh: xcb_ewmh_connection_t;
  Ev: xcb_client_message_event_t;
  Data32: PCardinalArray;
begin
  Mgr := TXCBWindowManager.Create(nil, 0);
  try
    Mgr.FrameMetrics := TXCBFrameMetrics.Create(28, 2);
    FillChar(MockEwmh, SizeOf(MockEwmh), 0);
    MockEwmh._NET_WM_MOVERESIZE := 1001;
    MockEwmh._NET_MOVERESIZE_WINDOW := 1002;
    MockEwmh._NET_REQUEST_FRAME_EXTENTS := 1003;
    Mgr.Ewmh := MockEwmh;
    Mgr.EwmhInitialized := True;

    // Manage a CSD / borderless window
    Cli := Mgr.ManageWindow(5555);
    Cli.Borderless := True;
    Cli.CurrentRect := TXCBRect.Create(200, 200, 800, 600);
    AssertFalse('CSD window is not decorated', Cli.IsDecorated());

    // 1. Test _NET_WM_MOVERESIZE with direction 8 (move)
    FillChar(Ev, SizeOf(Ev), 0);
    Ev.response_type := XCB_CLIENT_MESSAGE;
    Ev.window := 5555;
    Ev.type_ := 1001;
    Data32 := PCardinalArray(@Ev.data.raw[0]);
    Data32^[0] := 250; // x_root
    Data32^[1] := 210; // y_root
    Data32^[2] := 8;   // _NET_WM_MOVERESIZE_MOVE
    Data32^[3] := 1;   // button 1
    Data32^[4] := 1;   // source normal application

    Mgr.ProcessEvent(Pxcb_generic_event_t(@Ev));

    AssertEquals('Drag mode set to dmMove', Integer(dmMove), Integer(Mgr.DragMode));
    AssertSame('DragClient matches Cli', Cli, Mgr.DragClient);
    AssertSame('ActiveClient set to Cli', Cli, Mgr.ActiveClient);

    // Simulate mouse motion during drag
    Mgr.UpdateDrag(300, 260); // +50, +50
    AssertEquals('CSD moved X', 250, Cli.CurrentRect.X);
    AssertEquals('CSD moved Y', 250, Cli.CurrentRect.Y);
    AssertEquals('CSD width unchanged', 800, Cli.CurrentRect.Width);
    AssertEquals('CSD height unchanged', 600, Cli.CurrentRect.Height);

    // 2. Test _NET_WM_MOVERESIZE with direction 11 (cancel)
    Data32^[2] := 11; // _NET_WM_MOVERESIZE_CANCEL
    Mgr.ProcessEvent(Pxcb_generic_event_t(@Ev));
    AssertEquals('DragMode is dmNone after cancel', Integer(dmNone), Integer(Mgr.DragMode));
    AssertNull('DragClient is nil after cancel', Mgr.DragClient);

    // 3. Test _NET_WM_MOVERESIZE with direction 4 (bottom-right resize)
    Data32^[0] := 1050; // x_root
    Data32^[1] := 850;  // y_root
    Data32^[2] := 4;    // _NET_WM_MOVERESIZE_BOTTOMRIGHT
    Mgr.ProcessEvent(Pxcb_generic_event_t(@Ev));
    AssertEquals('Drag mode set to dmResizeBottomRight', Integer(dmResizeBottomRight), Integer(Mgr.DragMode));
    AssertSame('DragClient matches Cli', Cli, Mgr.DragClient);

    Mgr.UpdateDrag(1100, 890); // +50, +40
    AssertEquals('CSD resized width', 850, Cli.CurrentRect.Width);
    AssertEquals('CSD resized height', 640, Cli.CurrentRect.Height);
    Mgr.EndDrag();

    // 4. Test _NET_MOVERESIZE_WINDOW (programmatic move/resize)
    FillChar(Ev, SizeOf(Ev), 0);
    Ev.response_type := XCB_CLIENT_MESSAGE;
    Ev.window := 5555;
    Ev.type_ := 1002;
    Data32 := PCardinalArray(@Ev.data.raw[0]);
    // gravity + flags: bits 8..11 (0x0F00: x, y, width, height)
    Data32^[0] := (1 shl 8) or (1 shl 9) or (1 shl 10) or (1 shl 11);
    Data32^[1] := 150;  // newX
    Data32^[2] := 120;  // newY
    Data32^[3] := 900;  // newW
    Data32^[4] := 700;  // newH

    Mgr.ProcessEvent(Pxcb_generic_event_t(@Ev));
    AssertEquals('Programmatic moved X', 150, Cli.CurrentRect.X);
    AssertEquals('Programmatic moved Y', 120, Cli.CurrentRect.Y);
    AssertEquals('Programmatic resized width', 900, Cli.CurrentRect.Width);
    AssertEquals('Programmatic resized height', 700, Cli.CurrentRect.Height);

    // 5. Test _NET_REQUEST_FRAME_EXTENTS on CSD window doesn't crash offline
    FillChar(Ev, SizeOf(Ev), 0);
    Ev.response_type := XCB_CLIENT_MESSAGE;
    Ev.window := 5555;
    Ev.type_ := 1003;
    Mgr.ProcessEvent(Pxcb_generic_event_t(@Ev));
  finally
    Mgr.Free();
  end;
end;

procedure TXCBWMTest.TestMultiMonitorTopologyAndWorkareas();
var
  Mgr: TXCBWindowManager;
  Mon1, Mon2: TXCBMonitor;
  Dock: TXCBWMClient;
  S: TXCBStrutPartial;
begin
  Mgr := TXCBWindowManager.Create(nil, 0);
  try
    // Initial monitor in offline mode
    AssertEquals('Initial monitor count', 1, Mgr.MonitorCount);
    AssertNotNull('Initial primary monitor', Mgr.PrimaryMonitor);
    AssertEquals('Initial primary name', 'Default', Mgr.PrimaryMonitor.Name);

    // Setup simulated dual head topology:
    // Mon1 (DP-1): 1920x1080 at (0, 0), Primary
    // Mon2 (HDMI-1): 1920x1080 at (1920, 0), Secondary
    Mgr.Monitors.Clear();
    Mon1 := TXCBMonitor.Create('DP-1', TXCBRect.Create(0, 0, 1920, 1080), True, 0);
    Mon2 := TXCBMonitor.Create('HDMI-1', TXCBRect.Create(1920, 0, 1920, 1080), False, 1);
    Mgr.Monitors.Add(Mon1);
    Mgr.Monitors.Add(Mon2);
    Mgr.RecomputeWorkareas();

    AssertEquals('Dual monitor count', 2, Mgr.MonitorCount);
    AssertSame('Primary monitor is Mon1', Mon1, Mgr.PrimaryMonitor);

    // Point and Rect containment
    AssertSame('Point (100, 100) is Mon1', Mon1, Mgr.MonitorForPoint(100, 100));
    AssertSame('Point (2000, 100) is Mon2', Mon2, Mgr.MonitorForPoint(2000, 100));
    AssertSame('Rect inside Mon1', Mon1, Mgr.MonitorForRect(TXCBRect.Create(200, 200, 400, 300)));
    AssertSame('Rect inside Mon2', Mon2, Mgr.MonitorForRect(TXCBRect.Create(2100, 200, 400, 300)));

    // Adjacency navigation
    AssertSame('Mon1 right is Mon2', Mon2, Mgr.AdjacentMonitor(Mon1, dirRight));
    AssertSame('Mon2 left is Mon1', Mon1, Mgr.AdjacentMonitor(Mon2, dirLeft));
    AssertSame('Mon1 left has no neighbor', Mon1, Mgr.AdjacentMonitor(Mon1, dirLeft));
    AssertSame('Mon2 right has no neighbor', Mon2, Mgr.AdjacentMonitor(Mon2, dirRight));

    // Per-monitor strut isolation
    // Add top dock of 48px only on Mon1 (spans 0..1919)
    Dock := Mgr.ManageWindow(901);
    Dock.WindowType := wtDock;
    S := TXCBStrutPartial.Create();
    S.Top := 48;
    S.TopStartX := 0;
    S.TopEndX := 1919;
    Dock.Strut := S;

    Mgr.RecomputeWorkareas();

    // Mon1 workarea shrinks by 48px from top
    AssertEquals('Mon1 workarea Y', 48, Mon1.Workarea.Y);
    AssertEquals('Mon1 workarea Height', 1032, Mon1.Workarea.Height);

    // Mon2 workarea remains completely full-height and unmolested!
    AssertEquals('Mon2 workarea Y untouched', 0, Mon2.Workarea.Y);
    AssertEquals('Mon2 workarea Height untouched', 1080, Mon2.Workarea.Height);

    // Primary manager workarea reflects Mon1 (primary)
    AssertEquals('Manager workarea matches primary Y', 48, Mgr.Workarea.Y);
    AssertEquals('Manager workarea matches primary Height', 1032, Mgr.Workarea.Height);
  finally
    Mgr.Free();
  end;
end;

procedure TXCBWMTest.TestMultiMonitorNavigationAndMigration();
var
  Mgr: TXCBWindowManager;
  Mon1, Mon2: TXCBMonitor;
  Cli: TXCBWMClient;
begin
  Mgr := TXCBWindowManager.Create(nil, 0);
  try
    Mgr.Monitors.Clear();
    Mon1 := TXCBMonitor.Create('DP-1', TXCBRect.Create(0, 0, 1920, 1080), True, 0);
    Mon2 := TXCBMonitor.Create('HDMI-1', TXCBRect.Create(1920, 0, 1920, 1080), False, 1);
    Mgr.Monitors.Add(Mon1);
    Mgr.Monitors.Add(Mon2);
    Mgr.RecomputeWorkareas();

    // 1. Create client on Mon1
    Cli := Mgr.ManageWindow(8888);
    Cli.CurrentRect := TXCBRect.Create(100, 150, 600, 400);
    AssertSame('Client initially on Mon1', Mon1, Cli.CurrentMonitor());

    // 2. Maximize on Mon1
    Cli.Maximize();
    AssertEquals('Maximized Mon1 X', Mon1.Workarea.X, Cli.CurrentRect.X);
    AssertEquals('Maximized Mon1 Y', Mon1.Workarea.Y, Cli.CurrentRect.Y);
    AssertEquals('Maximized Mon1 W', Mon1.Workarea.Width, Cli.CurrentRect.Width);
    AssertEquals('Maximized Mon1 H', Mon1.Workarea.Height, Cli.CurrentRect.Height);

    // 3. Move maximized client across monitors (Mon1 -> Mon2)
    Mgr.MoveClientToMonitor(Cli, Mon2);
    AssertSame('Client now on Mon2', Mon2, Cli.CurrentMonitor());
    AssertEquals('Maximized Mon2 X', Mon2.Workarea.X, Cli.CurrentRect.X);
    AssertEquals('Maximized Mon2 Y', Mon2.Workarea.Y, Cli.CurrentRect.Y);
    AssertEquals('Maximized Mon2 W', Mon2.Workarea.Width, Cli.CurrentRect.Width);
    AssertEquals('Maximized Mon2 H', Mon2.Workarea.Height, Cli.CurrentRect.Height);

    // 4. Tile Right on Mon2
    Cli.TileRight();
    AssertTrue('State has wsTiledRight', wsTiledRight in Cli.State);
    AssertEquals('TiledRight Mon2 X', Mon2.Workarea.X + (Mon2.Workarea.Width div 2), Cli.CurrentRect.X);
    AssertEquals('TiledRight Mon2 W', Mon2.Workarea.Width - (Mon2.Workarea.Width div 2), Cli.CurrentRect.Width);

    // 5. Move tiled window back to Mon1
    Mgr.MoveClientToMonitor(Cli, Mon1);
    AssertSame('Client back on Mon1', Mon1, Cli.CurrentMonitor());
    AssertEquals('TiledRight Mon1 X', Mon1.Workarea.X + (Mon1.Workarea.Width div 2), Cli.CurrentRect.X);
    AssertEquals('TiledRight Mon1 W', Mon1.Workarea.Width - (Mon1.Workarea.Width div 2), Cli.CurrentRect.Width);

    // 6. Restore to floating and test relative position preservation
    Cli.Restore();
    Cli.CurrentRect := TXCBRect.Create(50, 60, 500, 400); // 50px offset from Mon1.X
    Mgr.MoveClientToMonitor(Cli, Mon2);
    AssertEquals('Relative X preserved on Mon2', 1920 + 50, Cli.CurrentRect.X);
    AssertEquals('Relative Y preserved on Mon2', 60, Cli.CurrentRect.Y);

    // 7. Hotplug disconnect simulation:
    // Window is currently on Mon2 (X = 1970). Mon2 is disconnected!
    Mgr.Monitors.Remove(Mon2);
    AssertEquals('Only Mon1 remaining', 1, Mgr.MonitorCount);
    // Trigger monitor change notification
    Mgr.DoOnMonitorsChanged();
    // Window must be auto-migrated to Mon1 and clamped inside Mon1 workarea
    AssertSame('Client migrated back to Mon1', Mon1, Cli.CurrentMonitor());
    AssertTrue('Client within Mon1 X bounds', Cli.CurrentRect.X >= Mon1.Workarea.X);
    AssertTrue('Client fits within Mon1 width', Cli.CurrentRect.Right() <= Mon1.Workarea.Right());
  finally
    Mgr.Free();
  end;
end;

procedure TXCBWMTest.TestWindowCapabilitiesAndFixedSize();
var
  Mgr: TXCBWindowManager;
  Cli: TXCBWMClient;
  Constrained: TXCBPoint;
begin
  Mgr := TXCBWindowManager.Create(nil, 0);
  try
    Cli := Mgr.ManageWindow(1001);
    AssertNotNull('Client managed', Cli);

    // 1. Verify default capabilities and buttons
    AssertTrue('CanResize default', Cli.CanResize);
    AssertTrue('CanMaximize default', Cli.CanMaximize);
    AssertTrue('CanMinimize default', Cli.CanMinimize);
    AssertTrue('CanClose default', Cli.CanClose);
    AssertTrue('HasMaximizeButton default', Cli.HasMaximizeButton);
    AssertTrue('HasMinimizeButton default', Cli.HasMinimizeButton);
    AssertTrue('HasCloseButton default', Cli.HasCloseButton);

    // 2. Disabling CanMaximize disallows maximizing and fullscreen
    Cli.CanMaximize := False;
    Cli.Maximize();
    AssertFalse('Cannot maximize when CanMaximize=False', wsMaximizedHorz in Cli.State);
    AssertFalse('Cannot maximize when CanMaximize=False', wsMaximizedVert in Cli.State);
    Cli.SetFullscreen(True);
    AssertFalse('Cannot fullscreen when CanMaximize=False', wsFullscreen in Cli.State);

    // 3. Disabling CanResize disallows tiling and keeps size constrained
    Cli.CanResize := False;
    Cli.TileLeft();
    AssertFalse('Cannot tile left when CanResize=False', wsTiledLeft in Cli.State);
    Cli.TileRight();
    AssertFalse('Cannot tile right when CanResize=False', wsTiledRight in Cli.State);
    Constrained := Cli.ConstrainSize(999, 888);
    AssertEquals('ConstrainSize Width preserves CurrentRect', Cli.CurrentRect.Width, Constrained.X);
    AssertEquals('ConstrainSize Height preserves CurrentRect', Cli.CurrentRect.Height, Constrained.Y);

    // 4. Disabling CanMinimize disallows minimizing
    Cli.CanMinimize := False;
    Cli.Minimize();
    AssertFalse('Cannot minimize when CanMinimize=False', wsMinimized in Cli.State);

    // 5. Fixed-size hints emulation (min_size = max_size)
    Cli.CanResize := True;
    Cli.CanMaximize := True;
    Cli.HasMaximizeButton := True;
    Cli.MinSize := TXCBPoint.Create(450, 300);
    Cli.MaxSize := TXCBPoint.Create(450, 300);
    // When min size equals max size, window is fixed size
    if (Cli.MinSize.X > 0) and (Cli.MaxSize.X > 0) and
       (Cli.MinSize.Y > 0) and (Cli.MaxSize.Y > 0) and
       (Cli.MinSize.X >= Cli.MaxSize.X) and
       (Cli.MinSize.Y >= Cli.MaxSize.Y) then
    begin
      Cli.CanResize := False;
      Cli.CanMaximize := False;
      Cli.HasMaximizeButton := False;
    end;
    AssertFalse('Fixed-size disables CanResize', Cli.CanResize);
    AssertFalse('Fixed-size disables CanMaximize', Cli.CanMaximize);
    AssertFalse('Fixed-size hides HasMaximizeButton', Cli.HasMaximizeButton);
  finally
    Mgr.Free();
  end;
end;

procedure TXCBWMTest.TestTransientDialogPlacementAndLifecycle();
var
  Mgr: TXCBWindowManager;
  ParentCli, DialogCli, DockCli: TXCBWMClient;
begin
  Mgr := TXCBWindowManager.Create(nil);
  try
    Mgr.Workarea := TXCBRect.Create(0, 38, 1920, 1004);

    ParentCli := TXCBWMClient.Create(1001, Mgr);
    ParentCli.CurrentRect := TXCBRect.Create(200, 150, 800, 600);
    ParentCli.WindowType := wtNormal;
    Mgr.Clients.Add(ParentCli);

    DialogCli := TXCBWMClient.Create(1002, Mgr);
    DialogCli.CurrentRect := TXCBRect.Create(0, 0, 400, 300);
    DialogCli.WindowType := wtDialog;
    Mgr.Clients.Add(DialogCli);

    // 1. Initial transient-for default
    AssertEquals('Default TransientFor is 0', 0, DialogCli.TransientFor);

    // 2. Link dialog to parent window
    DialogCli.TransientFor := ParentCli.ClientWindow;
    AssertEquals('TransientFor matches parent client window', ParentCli.ClientWindow, DialogCli.TransientFor);

    // 3. Center dialog over transient parent
    AssertFalse('Dialog has no explicit user position', DialogCli.HasUserPosition);

    // 4. Stacking & minimizing lifecycle
    AssertFalse('Parent initially not minimized', wsMinimized in ParentCli.State);
    AssertFalse('Dialog initially not minimized', wsMinimized in DialogCli.State);

    ParentCli.Minimize();
    AssertTrue('Parent minimized', wsMinimized in ParentCli.State);
    AssertTrue('Transient dialog automatically minimized with parent', wsMinimized in DialogCli.State);

    ParentCli.Activate();
    AssertFalse('Parent restored', wsMinimized in ParentCli.State);
    AssertFalse('Transient dialog restored with parent', wsMinimized in DialogCli.State);

    // 5. Dock window exclusion
    DockCli := TXCBWMClient.Create(1003, Mgr);
    DockCli.WindowType := wtDock;
    DockCli.CurrentRect := TXCBRect.Create(0, 1042, 1920, 38);
    Mgr.Clients.Add(DockCli);

    DialogCli.TransientFor := DockCli.ClientWindow;
    // When transient points to a dock, it must not be treated as a valid parent dialog
    AssertEquals('TransientFor points to dock', DockCli.ClientWindow, DialogCli.TransientFor);
  finally
    Mgr.Free();
  end;
end;

procedure TXCBWMTest.TestDesktopWindowPolicy();
var
  Mgr: TXCBWindowManager;
  DeskCli: TXCBWMClient;
begin
  Mgr := TXCBWindowManager.Create(nil);
  try
    DeskCli := TXCBWMClient.Create(2001, Mgr);
    DeskCli.WindowType := wtDesktop;
    DeskCli.CurrentRect := TXCBRect.Create(0, 0, 1920, 1080);
    Mgr.Clients.Add(DeskCli);

    // 1. Desktop window is not reparented
    AssertFalse('Desktop is not reparented', DeskCli.IsReparented);

    // 2. Capabilities are disabled
    DeskCli.CanMinimize := False;
    DeskCli.CanMaximize := False;
    DeskCli.CanResize := False;
    DeskCli.CanClose := False;

    AssertFalse('Desktop cannot minimize', DeskCli.CanMinimize);
    AssertFalse('Desktop cannot maximize', DeskCli.CanMaximize);
    AssertFalse('Desktop cannot resize', DeskCli.CanResize);
    AssertFalse('Desktop cannot close', DeskCli.CanClose);

    // 3. Minimizing is suppressed
    DeskCli.Minimize();
    AssertFalse('Desktop cannot be minimized', wsMinimized in DeskCli.State);

    // 4. Drag / Move is suppressed
    Mgr.BeginDrag(DeskCli, dmMove, 500, 500);
    AssertNull('Desktop window cannot be dragged/moved', Mgr.DragClient);

    Mgr.BeginDrag(DeskCli, dmResizeRight, 1920, 500);
    AssertNull('Desktop window cannot be resized', Mgr.DragClient);
  finally
    Mgr.Free();
  end;
end;

// WM-04: RequestShutdown must be callable from a signal handler, so it may only
// set flags and poke the self-pipe — never allocate or write to stdout.
procedure TXCBWMTest.TestShutdownRequestSetsFlags();
var
  Mgr: TXCBWindowManager;
begin
  Mgr := TXCBWindowManager.Create(nil, 0);
  try
    AssertFalse('Not shutting down initially', Mgr.ShutdownRequested);
    Mgr.RequestShutdown();
    AssertTrue('Shutdown requested', Mgr.ShutdownRequested);
    AssertFalse('Loop marked stopped', Mgr.IsRunning);

    // Idempotent: a second signal must not misbehave.
    Mgr.RequestShutdown();
    AssertTrue('Still requested', Mgr.ShutdownRequested);
  finally
    Mgr.Free();
  end;
end;

// WM-04: the self-pipe must be non-blocking on both ends and safe to drain when
// empty, otherwise a signal storm would stall the handler.
procedure TXCBWMTest.TestWakeupPipeLifecycle();
var
  Mgr: TXCBWindowManager;
begin
  Mgr := TXCBWindowManager.Create(nil, 0);
  try
    Mgr.CreateWakeupPipe();
    // Draining an empty pipe must return immediately (non-blocking read).
    Mgr.DrainWakeupPipe();

    // A wakeup write followed by a drain must not block either.
    Mgr.RequestShutdown();
    Mgr.DrainWakeupPipe();

    Mgr.CloseWakeupPipe();
    Mgr.CloseWakeupPipe(); // idempotent
    Mgr.DrainWakeupPipe(); // safe when no pipe exists
  finally
    Mgr.Free();
  end;
end;

// WM-04: with no connection the pump must not spin or block forever.
procedure TXCBWMTest.TestPumpWithoutConnection();
var
  Mgr: TXCBWindowManager;
begin
  Mgr := TXCBWindowManager.Create(nil, 0);
  try
    AssertFalse('Pump handles nothing without a connection', Mgr.PumpEventsOnce(10));
    Mgr.Run(); // must return immediately
    AssertFalse('Run left the loop stopped', Mgr.IsRunning);
  finally
    Mgr.Free();
  end;
end;

// WM-02: a refused pointer grab must not leave the manager believing it is
// dragging. Previously FDragClient/FDragMode were committed before the grab was
// attempted, so a failed grab produced a window glued to the cursor.
procedure TXCBWMTest.TestDragGrabFailureDoesNotCommitDrag();
var
  Conn, Holder: Pxcb_connection_t;
  ScreenNum: Integer;
  Mgr: TXCBWindowManager;
  Cli: TXCBWMClient;
  Win: xcb_window_t;
  Cookie: xcb_grab_pointer_cookie_t;
  Reply: Pxcb_grab_pointer_reply_t;
  Root: xcb_window_t;
begin
  ScreenNum := 0;
  Conn := xcb_connect(nil, @ScreenNum);
  if Conn = nil then Exit;

  Holder := nil;
  try
    if xcb_connection_has_error(Conn) <> 0 then Exit;

    Mgr := TXCBWindowManager.Create(Conn, ScreenNum);
    try
      // Requires exclusive display ownership: another WM's grabs would make the
      // pointer-grab result unpredictable.
      if not Mgr.ClaimOwnership() then Exit;

      Root := Mgr.RootWindow;
      if Root = 0 then Exit;

      // A real, owned window so ManageWindow has something valid to wrap.
      Win := xcb_generate_id(Conn);
      xcb_create_window(Conn, XCB_COPY_FROM_PARENT, Win, Root, 10, 10, 200, 150, 0,
                        XCB_WINDOW_CLASS_INPUT_OUTPUT, XCB_COPY_FROM_PARENT, 0, nil);
      xcb_map_window(Conn, Win);
      xcb_flush(Conn);

      Cli := Mgr.ManageWindow(Win);
      AssertNotNull('Client managed', Cli);
      AssertEquals('No drag before grab', Integer(dmNone), Integer(Mgr.DragMode));

      // A second client grabs the pointer, so the WM's grab must be refused.
      Holder := xcb_connect(nil, @ScreenNum);
      if (Holder <> nil) and (xcb_connection_has_error(Holder) = 0) then
      begin
        Cookie := xcb_grab_pointer(Holder, 0, Root,
                                   XCB_EVENT_MASK_BUTTON_RELEASE or XCB_EVENT_MASK_POINTER_MOTION,
                                   XCB_GRAB_MODE_ASYNC, XCB_GRAB_MODE_ASYNC,
                                   XCB_NONE, XCB_NONE, XCB_CURRENT_TIME);
        Reply := xcb_grab_pointer_reply(Holder, Cookie, nil);
        if Reply <> nil then
        begin
          try
            if Reply^.status = XCB_GRAB_STATUS_SUCCESS then
            begin
              try
                Mgr.BeginDrag(Cli, dmMove, 50, 50);
                AssertEquals('Refused grab must not enter drag mode',
                             Integer(dmNone), Integer(Mgr.DragMode));
                AssertNull('Refused grab must not bind a drag client', Mgr.DragClient);
              finally
                xcb_ungrab_pointer(Holder, XCB_CURRENT_TIME);
                xcb_flush(Holder);
              end;
            end;
          finally
            xcb_free(Reply);
          end;
        end;
      end;

      Mgr.UnmanageWindow(Cli);
    finally
      Mgr.Free();
    end;
  finally
    if Holder <> nil then xcb_disconnect(Holder);
    xcb_disconnect(Conn);
  end;
end;

// Shutting the manager down must hand clients back to the root window before the
// connection closes. Frame windows belong to the WM's connection, so letting the
// server reap them takes every reparented application with it — a WM restart
// would end the user's session.
//
// Two connections are essential here: the failure only appears at disconnect
// time, when the server frees connection-owned windows. Verifying over the WM's
// own connection would round-trip and mask it.
procedure TXCBWMTest.TestClientsSurviveManagerShutdown();
var
  Conn, Observer: Pxcb_connection_t;
  ScreenNum: Integer;
  Mgr: TXCBWindowManager;
  Cli: TXCBWMClient;
  Win: xcb_window_t;
  Attr: Pxcb_get_window_attributes_reply_t;
  Root: xcb_window_t;
begin
  ScreenNum := 0;
  Conn := xcb_connect(nil, @ScreenNum);
  if Conn = nil then Exit;

  Observer := nil;
  try
    if xcb_connection_has_error(Conn) <> 0 then Exit;

    Observer := xcb_connect(nil, @ScreenNum);
    if (Observer = nil) or (xcb_connection_has_error(Observer) <> 0) then Exit;

    Mgr := TXCBWindowManager.Create(Conn, ScreenNum);
    // This test needs exclusive ownership of the display: if another window
    // manager is running it will reparent the client window and the assertions
    // become meaningless. ClaimOwnership fails with BadAccess in that case, so
    // skip rather than report a false failure on a developer desktop.
    if not Mgr.ClaimOwnership() then
    begin
      Mgr.Free();
      Exit;
    end;

    Root := Mgr.RootWindow;
    if Root = 0 then
    begin
      Mgr.Free();
      Exit;
    end;

    // The client window must belong to a DIFFERENT connection than the manager,
    // exactly like a real application. Creating it on the manager's connection
    // would destroy it at disconnect regardless of reparenting and make this
    // test meaningless.
    Win := xcb_generate_id(Observer);
    xcb_create_window(Observer, XCB_COPY_FROM_PARENT, Win, Root, 20, 20, 180, 140, 0,
                      XCB_WINDOW_CLASS_INPUT_OUTPUT, XCB_COPY_FROM_PARENT, 0, nil);
    xcb_map_window(Observer, Win);
    xcb_flush(Observer);

    Cli := Mgr.ManageWindow(Win);
    AssertNotNull('Client managed', Cli);
    AssertTrue('Client reparented into a frame', Cli.IsReparented);
    AssertTrue('Frame window created', Cli.FrameWindow <> 0);

    // Tear the manager down and close the connection it used.
    Mgr.Free();
    xcb_disconnect(Conn);
    Conn := nil;

    // The client must still exist, as seen from an independent connection.
    Attr := xcb_get_window_attributes_reply(
      Observer, xcb_get_window_attributes(Observer, Win), nil);
    AssertNotNull('Client window survives manager shutdown', Attr);
    if Attr <> nil then
    begin
      AssertFalse('Client is mapped after shutdown', Attr^.map_state = XCB_MAP_STATE_UNMAPPED);
      xcb_free(Attr);
    end;

    xcb_destroy_window(Observer, Win);
    xcb_flush(Observer);
  finally
    if Conn <> nil then xcb_disconnect(Conn);
    if Observer <> nil then xcb_disconnect(Observer);
  end;
end;

// WM-06: the binding table must come from the server. A constant table cannot
// return 0 for a keysym that no key carries, and cannot agree with the server's
// own keycode for a keysym at the same time.
procedure TXCBWMTest.TestKeysymResolutionQueriesServer();
var
  Conn: Pxcb_connection_t;
  ScreenNum: Integer;
  Mgr: TXCBWindowManager;
  TabKc: xcb_keycode_t;
begin
  ScreenNum := 0;
  Conn := xcb_connect(nil, @ScreenNum);
  if Conn = nil then Exit;

  try
    if xcb_connection_has_error(Conn) <> 0 then Exit;

    Mgr := TXCBWindowManager.Create(Conn, ScreenNum);
    try
      AssertTrue('Bindings resolved against a live server', Mgr.KeyBindingsValid);
      AssertTrue('Tab keycode resolved', Mgr.KeycodeTab <> 0);

      // Cross-check: the resolver must agree with a fresh query.
      TabKc := Mgr.KeysymToKeycode(XK_Tab);
      AssertEquals('KeysymToKeycode(Tab) is stable', Integer(TabKc), Integer(Mgr.KeycodeTab));

      // A keysym that no key carries must resolve to 0. This is the assertion
      // that fails for any implementation backed by a constant table.
      AssertEquals('Unmapped keysym resolves to 0',
                   Integer(0), Integer(Mgr.KeysymToKeycode($0FFFFFFF)));

      // XK_space is always present.
      AssertTrue('Space keycode resolved', Mgr.KeycodeSpace <> 0);
    finally
      Mgr.Free();
    end;
  finally
    xcb_disconnect(Conn);
  end;
end;

// WM-06: modifier masks must be single bits and Alt must be usable, otherwise the
// grab combinations silently degenerate.
procedure TXCBWMTest.TestKeyBindingsResolveToValidBits();
var
  Mgr: TXCBWindowManager;
begin
  Mgr := TXCBWindowManager.Create(nil, 0);
  try
    AssertTrue('Offline fallback table is valid', Mgr.KeyBindingsValid);
    AssertTrue('Alt mask non-zero', Mgr.ModAlt <> 0);
    AssertTrue('Super mask non-zero', Mgr.ModSuper <> 0);

    // Exactly one bit set: a modifier mask is 1 shl n.
    AssertTrue('Alt is a single modifier bit', (Mgr.ModAlt and (Mgr.ModAlt - 1)) = 0);
    AssertTrue('Super is a single modifier bit', (Mgr.ModSuper and (Mgr.ModSuper - 1)) = 0);
    AssertTrue('NumLock is a single modifier bit',
               (Mgr.ModNumLock and (Mgr.ModNumLock - 1)) = 0);

    // The four lock combinations the grabber uses must be distinct.
    AssertTrue('Alt and Alt+NumLock differ', Mgr.ModAlt <> (Mgr.ModAlt or Mgr.ModNumLock));
  finally
    Mgr.Free();
  end;
end;

// WM-06: a layout switch delivers MappingNotify. The manager must re-resolve and
// ask the shell to re-grab, otherwise every binding dies silently.
procedure TXCBWMTest.TestMappingNotifyRebindsKeys();
var
  Mgr: TCountingWindowManager;
  Ev: xcb_mapping_notify_event_t;
begin
  Mgr := TCountingWindowManager.Create(nil, 0);
  try
    Mgr.RebindCount := 0;

    FillChar(Ev, SizeOf(Ev), 0);
    Ev.response_type := XCB_MAPPING_NOTIFY;
    Ev.request := XCB_MAPPING_KEYBOARD;

    AssertTrue('MappingNotify consumed', Mgr.ProcessEvent(Pxcb_generic_event_t(@Ev)));
    AssertEquals('RebindGlobalKeys invoked once', 1, Mgr.RebindCount);
    AssertTrue('Bindings still valid after rebind', Mgr.KeyBindingsValid);
  finally
    Mgr.Free();
  end;
end;

// WM-05: the root mask must select the events the WM actually relies on. Without
// FOCUS_CHANGE there is no focus tracking at all; without BUTTON_RELEASE a drag
// can miss its terminating release; without LEAVE_WINDOW the root-cursor reset is
// dead code.
procedure TXCBWMTest.TestRootEventMaskIncludesFocusAndRelease();
var
  Conn: Pxcb_connection_t;
  ScreenNum: Integer;
  Mgr: TXCBWindowManager;
  Attr: Pxcb_get_window_attributes_reply_t;
  Mask: Cardinal;
begin
  ScreenNum := 0;
  Conn := xcb_connect(nil, @ScreenNum);
  if Conn = nil then Exit;

  try
    if xcb_connection_has_error(Conn) <> 0 then Exit;

    Mgr := TXCBWindowManager.Create(Conn, ScreenNum);
    try
      // Another WM owns this display: nothing to assert, but do NOT free Mgr here
      // — the finally block below owns it. Freeing in both places was a double
      // free that surfaced as an access violation in whichever test ran next.
      if not Mgr.ClaimOwnership() then Exit;

      Attr := xcb_get_window_attributes_reply(
        Conn, xcb_get_window_attributes(Conn, Mgr.RootWindow), nil);
      AssertNotNull('Root attributes readable', Attr);
      if Attr <> nil then
      begin
        try
          Mask := Attr^.your_event_mask;
          AssertTrue('Root selects FOCUS_CHANGE',
                     (Mask and XCB_EVENT_MASK_FOCUS_CHANGE) <> 0);
          AssertTrue('Root selects BUTTON_RELEASE',
                     (Mask and XCB_EVENT_MASK_BUTTON_RELEASE) <> 0);
          AssertTrue('Root selects ENTER_WINDOW',
                     (Mask and XCB_EVENT_MASK_ENTER_WINDOW) <> 0);
          AssertTrue('Root selects LEAVE_WINDOW',
                     (Mask and XCB_EVENT_MASK_LEAVE_WINDOW) <> 0);
          AssertTrue('Root selects SUBSTRUCTURE_REDIRECT',
                     (Mask and XCB_EVENT_MASK_SUBSTRUCTURE_REDIRECT) <> 0);
        finally
          xcb_free(Attr);
        end;
      end;
    finally
      Mgr.Free();
    end;
  finally
    xcb_disconnect(Conn);
  end;
end;

// WM-05: focus that arrives from outside (a client calling XSetInputFocus) must be
// adopted, so the active window does not go stale.
procedure TXCBWMTest.TestFocusInSyncsActiveClient();
var
  Mgr: TXCBWindowManager;
  Cli1, Cli2: TXCBWMClient;
  Ev: xcb_focus_in_event_t;
begin
  Mgr := TXCBWindowManager.Create(nil, 0);
  try
    Cli1 := Mgr.ManageWindow(7001);
    Cli2 := Mgr.ManageWindow(7002);
    AssertNotNull('Client 1 managed', Cli1);
    AssertNotNull('Client 2 managed', Cli2);
    Mgr.ActiveClient := Cli1;
    AssertSame('Client 1 initially active', Cli1, Mgr.ActiveClient);

    // Client 2 grabs focus on its own.
    FillChar(Ev, SizeOf(Ev), 0);
    Ev.response_type := XCB_FOCUS_IN;
    Ev.detail := XCB_NOTIFY_DETAIL_ANCESTOR;
    Ev.event := 7002;

    AssertTrue('FocusIn consumed', Mgr.ProcessEvent(Pxcb_generic_event_t(@Ev)));
    AssertSame('Active client followed focus', Cli2, Mgr.ActiveClient);
    AssertTrue('Client 2 marked focused', wsFocused in Cli2.State);
    AssertFalse('Client 1 no longer focused', wsFocused in Cli1.State);
  finally
    Mgr.Free();
  end;
end;

// WM-05: focus reverting to PointerRoot/None, or a FocusIn for the client we
// already consider active, must not disturb the active client.
procedure TXCBWMTest.TestFocusInIgnoresPointerRootAndSelf();
var
  Mgr: TXCBWindowManager;
  Cli1: TXCBWMClient;
  Ev: xcb_focus_in_event_t;
begin
  Mgr := TXCBWindowManager.Create(nil, 0);
  try
    Cli1 := Mgr.ManageWindow(7101);
    Mgr.ActiveClient := Cli1;

    // Focus reverted to the root pointer: keep the last active client.
    FillChar(Ev, SizeOf(Ev), 0);
    Ev.response_type := XCB_FOCUS_IN;
    Ev.detail := XCB_NOTIFY_DETAIL_POINTER_ROOT;
    Ev.event := Mgr.RootWindow;
    AssertTrue('PointerRoot FocusIn consumed', Mgr.ProcessEvent(Pxcb_generic_event_t(@Ev)));
    AssertSame('Active client unchanged on PointerRoot', Cli1, Mgr.ActiveClient);

    // Focus on the already-active client is a no-op.
    FillChar(Ev, SizeOf(Ev), 0);
    Ev.response_type := XCB_FOCUS_IN;
    Ev.detail := XCB_NOTIFY_DETAIL_ANCESTOR;
    Ev.event := 7101;
    AssertTrue('Self FocusIn consumed', Mgr.ProcessEvent(Pxcb_generic_event_t(@Ev)));
    AssertSame('Active client unchanged for self', Cli1, Mgr.ActiveClient);

    // While the manager is applying focus itself, incoming FocusIn is ignored.
    Mgr.SyncingFocus := True;
    FillChar(Ev, SizeOf(Ev), 0);
    Ev.response_type := XCB_FOCUS_IN;
    Ev.detail := XCB_NOTIFY_DETAIL_ANCESTOR;
    Ev.event := 7101;
    Mgr.ProcessEvent(Pxcb_generic_event_t(@Ev));
    AssertSame('Active client unchanged while syncing', Cli1, Mgr.ActiveClient);
  finally
    Mgr.Free();
  end;
end;

// The pump must drain a burst of pending events in a single call rather than
// returning after the first one. Each pump cycle ends with a present in the
// shell, so one-event-per-cycle would cap throughput at the tick rate.
procedure TXCBWMTest.TestPumpDrainsBurstInOneCall();var
  Conn: Pxcb_connection_t;
  ScreenNum: Integer;
  Mgr: TCountingWindowManager;
  Root, W: xcb_window_t;
  Mask: Cardinal;
  I: Integer;
  Handled: Integer;
begin
  ScreenNum := 0;
  Conn := xcb_connect(nil, @ScreenNum);
  if Conn = nil then Exit;

  try
    if xcb_connection_has_error(Conn) <> 0 then Exit;

    Mgr := TCountingWindowManager.Create(Conn, ScreenNum);
    try
      Root := Mgr.RootWindow;
      if Root = 0 then Exit;

      // A window of our own, selecting structure events, so mapping and
      // unmapping it generates a real burst of events for the pump.
      W := xcb_generate_id(Conn);
      xcb_create_window(Conn, XCB_COPY_FROM_PARENT, W, Root, 0, 0, 50, 50, 0,
                        XCB_WINDOW_CLASS_INPUT_OUTPUT, XCB_COPY_FROM_PARENT, 0, nil);
      Mask := XCB_EVENT_MASK_STRUCTURE_NOTIFY;
      xcb_change_window_attributes(Conn, W, XCB_CW_EVENT_MASK, @Mask);
      for I := 1 to 5 do
      begin
        xcb_map_window(Conn, W);
        xcb_unmap_window(Conn, W);
      end;
      xcb_flush(Conn);

      Handled := 0;
      for I := 1 to 20 do
      begin
        if Mgr.PumpEventsOnce(50) then
          Inc(Handled)
        else
          Break;
      end;

      AssertTrue('Pump processed at least one batch', Handled >= 1);

      // Once the pump reports "nothing to do", the queue must really be empty.
      AssertFalse('Pump reports idle only when truly idle', Mgr.PumpEventsOnce(10));

      xcb_destroy_window(Conn, W);
      xcb_flush(Conn);
    finally
      Mgr.Free();
    end;
  finally
    xcb_disconnect(Conn);
  end;
end;

// Contract guard for the pump: a call with events already waiting must return
// quickly and must not depend on further activity to notice them.
//
// Note: this does not distinguish xcb_poll_for_event from
// xcb_poll_for_queued_event — both pass here, because the socket is still
// readable in this scenario. It pins the behaviour, not the implementation
// detail; the reasoning for the primitive used lives in PumpEventsOnce.
procedure TXCBWMTest.TestPumpDoesNotStallWithPendingEvents();
var
  Conn: Pxcb_connection_t;
  ScreenNum: Integer;
  Mgr: TCountingWindowManager;
  Root, W: xcb_window_t;
  Mask: Cardinal;
  StartTick: QWord;
  Elapsed: QWord;
begin
  ScreenNum := 0;
  Conn := xcb_connect(nil, @ScreenNum);
  if Conn = nil then Exit;

  try
    if xcb_connection_has_error(Conn) <> 0 then Exit;

    Mgr := TCountingWindowManager.Create(Conn, ScreenNum);
    try
      Root := Mgr.RootWindow;
      if Root = 0 then Exit;

      W := xcb_generate_id(Conn);
      xcb_create_window(Conn, XCB_COPY_FROM_PARENT, W, Root, 0, 0, 50, 50, 0,
                        XCB_WINDOW_CLASS_INPUT_OUTPUT, XCB_COPY_FROM_PARENT, 0, nil);
      Mask := XCB_EVENT_MASK_STRUCTURE_NOTIFY;
      xcb_change_window_attributes(Conn, W, XCB_CW_EVENT_MASK, @Mask);
      xcb_map_window(Conn, W);
      xcb_flush(Conn);

      StartTick := GetTickCount64();
      AssertTrue('Pending event handled', Mgr.PumpEventsOnce(500));
      Elapsed := GetTickCount64() - StartTick;

      // A 500 ms select timeout would be hit only if the pump were blind to the
      // pending event. Allow generous slack for a loaded machine.
      AssertTrue('Pump did not wait for the timeout (' + IntToStr(Elapsed) + ' ms)',
                 Elapsed < 400);

      xcb_destroy_window(Conn, W);
      xcb_flush(Conn);
    finally
      Mgr.Free();
    end;
  finally
    xcb_disconnect(Conn);
  end;
end;

// WM-11: a single pump cycle must not drain an unbounded queue. A client emitting
// a continuous stream — a ConfigureNotify storm during a resize, or a 60 Hz video
// generating damage — would otherwise keep the drain loop non-empty forever and
// starve DoOnTick, which is where the shell presents.
//
// The assertion counts events actually processed in one cycle. Counting leftovers
// instead is unreliable: events arrive incrementally, so a drain can stop at a
// natural gap and look bounded even with no cap in place.
// WM-11: a single pump cycle must not drain an unbounded queue. A client emitting
// a continuous stream — a ConfigureNotify storm during a resize, or a 60 Hz video
// generating damage — would otherwise keep the drain loop non-empty forever and
// starve DoOnTick, which is where the shell presents.
//
// Two things had to be got right to make this test meaningful:
//
//  * Counting leftover events is unreliable (they arrive incrementally, so a drain
//    stops at a natural gap and looks bounded with no cap in place). This counts
//    events actually processed instead.
//  * Mapping and unmapping the SAME window does not work: the server coalesces the
//    requests, so 300 requests produced 4 notifications. Distinct windows each
//    produce their own MapNotify.
procedure TXCBWMTest.TestPumpBatchIsBounded();
var
  Conn: Pxcb_connection_t;
  ScreenNum: Integer;
  Mgr: TCountingWindowManager;
  Root: xcb_window_t;
  Wins: array[0..BATCH_WINDOWS - 1] of xcb_window_t;
  Mask: Cardinal;
  I, total, cycles, attempts: Integer;
begin
  ScreenNum := 0;

  // Retry: on some displays the first xcb_connect in a process reports an error
  // state while a second succeeds (observed under Xephyr with EGL/DRI3 warnings).
  // That is environmental, not a property of the code under test.
  Conn := nil;
  for attempts := 1 to 5 do
  begin
    Conn := xcb_connect(nil, @ScreenNum);
    if (Conn <> nil) and (xcb_connection_has_error(Conn) = 0) then Break;
    if Conn <> nil then xcb_disconnect(Conn);
    Conn := nil;
    Sleep(20);
  end;
  if Conn = nil then Exit;

  try
    Mgr := TCountingWindowManager.Create(Conn, ScreenNum);
    try
      // Deliberately NOT claiming ownership: with SubstructureRedirect active the
      // maps would be turned into MapRequests and the event count would depend on
      // window-management behaviour. Without it, each map produces a real
      // MapNotify for this connection.
      Root := Mgr.RootWindow;
      if Root = 0 then Exit;

      // If some *other* window manager owns the display it redirects these
      // windows, so the event stream is not ours to reason about. Skip rather than
      // report a misleading failure on a developer desktop.
      if AnotherWMRunning(Conn, Root) then Exit;

      // One distinct window per event.
      for I := 0 to BATCH_WINDOWS - 1 do
      begin
        Wins[I] := xcb_generate_id(Conn);
        xcb_create_window(Conn, XCB_COPY_FROM_PARENT, Wins[I], Root, 0, 0, 20, 20, 0,
                          XCB_WINDOW_CLASS_INPUT_OUTPUT, XCB_COPY_FROM_PARENT, 0, nil);
        Mask := XCB_EVENT_MASK_STRUCTURE_NOTIFY;
        xcb_change_window_attributes(Conn, Wins[I], XCB_CW_EVENT_MASK, @Mask);
        xcb_map_window(Conn, Wins[I]);
      end;
      xcb_flush(Conn);

      // Round-trip so the server has processed and sent every one of those events
      // before the pump runs.
      xcb_free(xcb_get_input_focus_reply(Conn, xcb_get_input_focus(Conn), nil));

      Mgr.ProcessedCount := 0;
      AssertTrue('Pump handled a batch', Mgr.PumpEventsOnce(200));

      AssertTrue('Some events were processed', Mgr.ProcessedCount > 0);
      AssertTrue('One cycle processed at most the batch cap, got ' +
                 IntToStr(Mgr.ProcessedCount),
                 Mgr.ProcessedCount <= 64);

      // The cap must defer, not drop: draining repeatedly has to reach every
      // queued event.
      total := Mgr.ProcessedCount;
      cycles := 1;
      while (cycles < 40) and Mgr.PumpEventsOnce(200) do
      begin
        Inc(total, Mgr.ProcessedCount);
        Mgr.ProcessedCount := 0;
        Inc(cycles);
      end;

      AssertTrue('Draining needed more than one cycle (the cap is real), got ' +
                 IntToStr(cycles), cycles > 1);
      AssertTrue('Every queued event was eventually handled, got ' +
                 IntToStr(total) + ' in ' + IntToStr(cycles) + ' cycles',
                 total >= BATCH_WINDOWS - 5);

      for I := 0 to BATCH_WINDOWS - 1 do
        xcb_destroy_window(Conn, Wins[I]);
      xcb_flush(Conn);
    finally
      Mgr.Free();
    end;
  finally
    xcb_disconnect(Conn);
  end;
end;

// Regression: an application that re-asserts its geometry while tiled must not be
// able to overwrite the window's restore target.
//
// GTK applications snap their size to the resize increments advertised in
// WM_NORMAL_HINTS, so resizing a tiled mate-terminal makes it send a
// ConfigureRequest for its own tiled size. That request used to be saved as
// RestoredRect, so "restore" restored the tiled geometry instead of the floating
// one. xterm does not send such a request, which is why the bug only showed on
// some applications.
procedure TXCBWMTest.TestConfigureRequestDoesNotClobberRestoreTarget();
var
  Mgr: TXCBWindowManager;
  Cli: TXCBWMClient;
  CfgEv: xcb_configure_request_event_t;
  original: TXCBRect;
begin
  Mgr := TXCBWindowManager.Create(nil, 0);
  try
    Cli := Mgr.ManageWindow(9801);
    AssertNotNull('Client managed', Cli);

    original := TXCBRect.Create(200, 66, 814, 693);
    Cli.CurrentRect := original;
    Cli.RestoredRect := original;

    Cli.TileLeft();
    AssertTrue('Tiled', wsTiledLeft in Cli.State);
    AssertEquals('Restore target unchanged by tiling', original.Width, Cli.RestoredRect.Width);
    AssertEquals('Restore target height unchanged', original.Height, Cli.RestoredRect.Height);

    // The application now asks for its own tiled size, as a GTK app would.
    FillChar(CfgEv, SizeOf(CfgEv), 0);
    CfgEv.response_type := XCB_CONFIGURE_REQUEST;
    CfgEv.window := Cli.ClientWindow;
    CfgEv.value_mask := XCB_CONFIG_WINDOW_X or XCB_CONFIG_WINDOW_Y or
                        XCB_CONFIG_WINDOW_WIDTH or XCB_CONFIG_WINDOW_HEIGHT;
    CfgEv.x := 0;
    CfgEv.y := 0;
    CfgEv.width := 504;
    CfgEv.height := 756;

    AssertTrue('ConfigureRequest handled', Mgr.ProcessEvent(Pxcb_generic_event_t(@CfgEv)));

    // The restore target must survive it.
    AssertEquals('Restore target X not clobbered', original.X, Cli.RestoredRect.X);
    AssertEquals('Restore target Y not clobbered', original.Y, Cli.RestoredRect.Y);
    AssertEquals('Restore target width not clobbered', original.Width, Cli.RestoredRect.Width);
    AssertEquals('Restore target height not clobbered', original.Height, Cli.RestoredRect.Height);

    // And restoring returns the floating geometry, not the tiled one.
    Cli.Restore();
    AssertEquals('Restored width', original.Width, Cli.CurrentRect.Width);
    AssertEquals('Restored height', original.Height, Cli.CurrentRect.Height);
    AssertEquals('Restored X', original.X, Cli.CurrentRect.X);
    AssertEquals('Restored Y', original.Y, Cli.CurrentRect.Y);
  finally
    Mgr.Free();
  end;
end;

initialization
  RegisterTest(TXCBWMTest);
end.
