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
    procedure TestClientFullscreen();
    procedure TestClientSizeConstraints();
    procedure TestVirtualDesktops();
    procedure TestWindowFilteringTypes();
    procedure TestTitlebarRect();
    procedure TestInteractiveDrag();
    procedure TestLiveConnectionIfAvailable();
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
  DockClient, DeskClient: TXCBWMClient;
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

    // Test drag resize
    Mgr.BeginDrag(Client, dmResize, 420, 320);
    Mgr.UpdateDrag(450, 350); // Delta +30, +30
    AssertEquals('Resized Width', 330, Client.CurrentRect.Width);
    AssertEquals('Resized Height', 230, Client.CurrentRect.Height);
    Mgr.EndDrag();
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

initialization
  RegisterTest(TXCBWMTest);

end.
