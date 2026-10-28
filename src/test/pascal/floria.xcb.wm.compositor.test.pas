{ Unit Floria.XCB.WM.Compositor.Test — Unit test suite for TXCBCompositor }

unit Floria.XCB.WM.Compositor.Test;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry,
  Floria.XCB,
  Floria.XCB.WM,
  Floria.XCB.Damage,
  Floria.XCB.WM.Compositor,
  Floria.Image.Core,
  Floria.Canvas.Agg;

type
  // Draws an overlay from OnAfterRender, exactly as the shell does, so the
  // compositor's overlay bookkeeping can be exercised.
  TOverlayHarness = class
  public
    Overlay: TXCBRect;
    Draw: Boolean;
    procedure AfterRender(ASender: TObject; ACanvas: TFloriaCanvasAgg; const ASceneRect: TXCBRect);
  end;

  TXCBCompositorTest = class(TTestCase)
  published
    procedure TestCompositorLifecycleOffline();
    procedure TestCompositedWindowShadowConfig();
    procedure TestSceneCompositionOffline();
    procedure TestDamageNotifyRouting();
    procedure TestLiveCompositorIfAvailable();
    procedure TestDamageNotifyNeverAliasesXErrors();
    procedure TestDamageBaseResolvedWhenClaimed();
    procedure TestHiddenWindowsStillSubtractDamage();
    procedure TestContentDamagePresentsPartially();
    procedure TestStructuralChangeForcesFullPresent();
    procedure TestInvalidateForcesFullPresent();
    procedure TestOverlayRectDrivesPartialPresent();
  end;

implementation

procedure TOverlayHarness.AfterRender(ASender: TObject; ACanvas: TFloriaCanvasAgg; const ASceneRect: TXCBRect);
begin
  if not Draw then Exit;
  ACanvas.DrawRoundedRect(Overlay.X, Overlay.Y, Overlay.Width, Overlay.Height,
                          8, 0.1, 0.1, 0.1, 0.9);
  TXCBCompositor(ASender).SetOverlayRect(Overlay);
end;

procedure TXCBCompositorTest.TestCompositorLifecycleOffline();
var
  comp: TXCBCompositor;
  w: TXCBCompositedWindow;
  rect: TXCBRect;
begin
  comp := TXCBCompositor.Create(nil, 0, 800, 600);
  try
    AssertFalse('Compositor active offline', comp.IsActive);
    AssertEquals('Screen width', 800, comp.ScreenWidth);
    AssertEquals('Screen height', 600, comp.ScreenHeight);
    AssertNotNull('Scene image created', comp.SceneImage);
    AssertNotNull('Scene canvas created', comp.SceneCanvas);
    AssertEquals('Zero windows initially', 0, comp.Windows.Count);

    rect := TXCBRect.Create(50, 50, 400, 300);
    w := comp.RegisterWindow(1001, rect);
    AssertNotNull('Window registered', w);
    AssertEquals('Window ID matches', 1001, w.Window);
    AssertEquals('One window in list', 1, comp.Windows.Count);
    AssertSame('FindWindow finds registered window', w, comp.FindWindow(1001));

    // Test geometry update
    w.UpdateGeometry(60, 70, 420, 320);
    AssertEquals('Updated X', 60, w.Geometry.X);
    AssertEquals('Updated Y', 70, w.Geometry.Y);
    AssertEquals('Updated Width', 420, w.Geometry.Width);
    AssertEquals('Updated Height', 320, w.Geometry.Height);

    // Test properties
    comp.SetWindowOpacity(1001, 0.85);
    AssertTrue('Window opacity updated', Abs(w.Opacity - 0.85) < 0.001);

    comp.SetWindowBackdropBlur(1001, True, 20);
    AssertTrue('Window backdrop blur enabled', w.HasBackdropBlur);
    AssertEquals('Window blur radius', 20, w.BlurRadius);

    comp.SetWindowShadow(1001, True, 18, 6, 0.5);
    AssertTrue('Window shadow enabled', w.ShadowConfig.Enabled);
    AssertEquals('Shadow radius', 18, w.ShadowConfig.Radius);
    AssertEquals('Shadow offset Y', 6, w.ShadowConfig.OffsetY);

    comp.UnregisterWindow(1001);
    AssertEquals('Window unregistered', 0, comp.Windows.Count);
    AssertNull('FindWindow returns nil', comp.FindWindow(1001));
  finally
    comp.Free();
  end;
end;

procedure TXCBCompositorTest.TestCompositedWindowShadowConfig();
var
  cfg: TXCBWindowShadowConfig;
begin
  cfg := TXCBWindowShadowConfig.Create(True, 16, 5, 0.45);
  AssertTrue('Shadow enabled', cfg.Enabled);
  AssertEquals('Shadow radius', 16, cfg.Radius);
  AssertEquals('Shadow offset Y', 5, cfg.OffsetY);
  AssertTrue('Shadow opacity', Abs(cfg.Opacity - 0.45) < 0.001);
end;

procedure TXCBCompositorTest.TestSceneCompositionOffline();
var
  comp: TXCBCompositor;
  w1, w2: TXCBCompositedWindow;
  rect1, rect2: TXCBRect;
  clientImg1, clientImg2: TFloriaImage;
  canvas: TFloriaCanvasAgg;
  pixel: TBgraPixel;
  isCompositedNonBlank: Boolean;
  x, y: Integer;
begin
  comp := TXCBCompositor.Create(nil, 0, 640, 480);
  try
    comp.SetBackgroundColor(30, 30, 46, 255); // Catppuccin Base

    // Create 1st simulated client (Frosted Glass Panel)
    rect1 := TXCBRect.Create(50, 50, 200, 150);
    w1 := comp.RegisterWindow(2001, rect1);
    w1.HasBackdropBlur := True;
    w1.BlurRadius := 10;
    w1.Opacity := 0.9;
    clientImg1 := TFloriaImage.Create(200, 150);
    clientImg1.Clear(60, 60, 80, 220); // Semi-transparent bluish panel
    w1.Image := clientImg1;
    w1.IsDirty := False;

    // Create 2nd simulated client (Foreground dialog with Drop Shadow)
    rect2 := TXCBRect.Create(180, 120, 250, 180);
    w2 := comp.RegisterWindow(2002, rect2);
    w2.ShadowConfig := TXCBWindowShadowConfig.Create(True, 12, 4, 0.4);
    clientImg2 := TFloriaImage.Create(250, 180);
    clientImg2.Clear(240, 240, 250, 255); // Bright card
    w2.Image := clientImg2;
    w2.IsDirty := False;

    // Execute full composite pass
    comp.CompositeScene();

    AssertNotNull('Scene image available', comp.SceneImage);
    AssertEquals('Scene image width', 640, comp.SceneImage.Width);
    AssertEquals('Scene image height', 480, comp.SceneImage.Height);

    // Assert that the composition changed pixels in the window region
    pixel := comp.SceneImage.Pixels[200, 150];
    // Pixel inside w2 (bright card) should be close to 240
    AssertTrue('Foreground window pixel rendered', pixel.R > 200);

    // Pixel in background corner should match background color (30, 30, 46)
    pixel := comp.SceneImage.Pixels[10, 10];
    AssertEquals('Background R', 30, pixel.R);
    AssertEquals('Background G', 30, pixel.G);
    AssertEquals('Background B', 46, pixel.B);
  finally
    comp.Free();
  end;
end;

procedure TXCBCompositorTest.TestDamageNotifyRouting();
var
  comp: TXCBCompositor;
  w: TXCBCompositedWindow;
  rect: TXCBRect;
  dmgEvent: xcb_damage_notify_event_t;
begin
  comp := TXCBCompositor.Create(nil, 0, 800, 600);
  try
    rect := TXCBRect.Create(100, 100, 300, 200);
    w := comp.RegisterWindow(5001, rect);
    w.IsDirty := False;

    FillChar(dmgEvent, SizeOf(dmgEvent), 0);
    dmgEvent.drawable := 5001;
    dmgEvent.area.x := 10;
    dmgEvent.area.y := 10;
    dmgEvent.area.width := 50;
    dmgEvent.area.height := 50;

    AssertTrue('HandleDamageNotify returns True for registered window', comp.HandleDamageNotify(@dmgEvent));
    AssertTrue('Window marked dirty on damage', w.IsDirty);

    // Test unhandled drawable
    dmgEvent.drawable := 9999;
    AssertFalse('HandleDamageNotify returns False for unknown window', comp.HandleDamageNotify(@dmgEvent));
  finally
    comp.Free();
  end;
end;

procedure TXCBCompositorTest.TestLiveCompositorIfAvailable();
var
  conn: Pxcb_connection_t;
  screenNum: Integer;
  screen: Pxcb_screen_t;
  comp: TXCBCompositor;
begin
  screenNum := 0;
  conn := xcb_connect(nil, @screenNum);
  if conn = nil then Exit;
  try
    if xcb_connection_has_error(conn) = 0 then
    begin
      screen := xcb_setup_roots_iterator(xcb_get_setup(conn)).data;
      if screen <> nil then
      begin
        comp := TXCBCompositor.Create(conn, screen^.root, screen^.width_in_pixels, screen^.height_in_pixels);
        try
          AssertTrue('Composite extension detected on live server', comp.HasComposite);
          AssertTrue('Damage extension detected on live server', comp.HasDamage);
        finally
          comp.Free();
        end;
      end;
    end;
  finally
    xcb_disconnect(conn);
  end;
end;

// WM-14: IsDamageNotify compared (response_type and $7F) against
// FDamageEventBase + XCB_DAMAGE_NOTIFY, where XCB_DAMAGE_NOTIFY is 0. If the event
// base was never resolved (0), that expression matched X *error* events — which
// arrive with response_type 0 — and they were fed to HandleDamageNotify as damage
// notifications with garbage drawable ids.
//
// The invariant that prevents this is: HasDamage implies DamageEventBase <> 0.
// QueryExtensions now only claims the extension once the event base is known, and
// IsDamageNotify additionally refuses to match while the base is unresolved.
//
// The second half (the guard) is defence in depth for a state that should now be
// unreachable; it cannot be exercised without a test-only backdoor into the
// private field, which is not worth adding to production code. What is asserted
// here is the invariant itself, plus the observable consequence offline.
procedure TXCBCompositorTest.TestDamageNotifyNeverAliasesXErrors();
var
  comp: TXCBCompositor;
  ev: xcb_generic_event_t;
begin
  comp := TXCBCompositor.Create(nil, 0, 800, 600);
  try
    // Offline the extensions are unresolved: exactly the dangerous state.
    AssertFalse('Damage extension not claimed offline', comp.HasDamage);
    AssertEquals('Event base unresolved', 0, Integer(comp.DamageEventBase));

    FillChar(ev, SizeOf(ev), 0);
    ev.response_type := 0; // X error
    AssertFalse('Error event is not a damage notify', comp.IsDamageNotify(@ev));
    AssertFalse('Error event not consumed as damage', comp.HandleGenericEvent(@ev));
  finally
    comp.Free();
  end;
end;

// WM-14, live half: on a server that does have the Damage extension, the base must
// be resolved. If it were not, every X error would be routed as a damage event.
procedure TXCBCompositorTest.TestDamageBaseResolvedWhenClaimed();
var
  Conn: Pxcb_connection_t;
  ScreenNum: Integer;
  comp: TXCBCompositor;
  XSetup: Pxcb_setup_t;
  It: xcb_screen_iterator_t;
  Root: xcb_window_t;
  Ev: xcb_generic_event_t;
begin
  ScreenNum := 0;
  Conn := xcb_connect(nil, @ScreenNum);
  if Conn = nil then Exit;

  try
    if xcb_connection_has_error(Conn) <> 0 then Exit;

    XSetup := xcb_get_setup(Conn);
    It := xcb_setup_roots_iterator(XSetup);
    if It.data = nil then Exit;
    Root := It.data^.root;

    comp := TXCBCompositor.Create(Conn, Root, 800, 600);
    try
      if comp.HasDamage then
      begin
        AssertTrue('HasDamage implies a resolved event base',
                   comp.DamageEventBase <> 0);

        // An error event must not be mistaken for damage even when the extension
        // is fully active.
        FillChar(Ev, SizeOf(Ev), 0);
        Ev.response_type := 0;
        AssertFalse('Error event is not a damage notify on a live server',
                    comp.IsDamageNotify(@Ev));
      end;
    finally
      comp.Free();
    end;
  finally
    xcb_disconnect(Conn);
  end;
end;

// WM-13: damage must be subtracted for every registered window on every pass,
// including ones that are hidden, zero-sized or have no pixmap. Subtracting only
// for rendered windows let the server-side damage region grow without bound.
procedure TXCBCompositorTest.TestHiddenWindowsStillSubtractDamage();
var
  comp: TXCBCompositor;
  visible, hidden, zeroSized: TXCBCompositedWindow;
begin
  comp := TXCBCompositor.Create(nil, 0, 800, 600);
  try
    visible := comp.RegisterWindow(2001, TXCBRect.Create(10, 10, 200, 150));
    hidden := comp.RegisterWindow(2002, TXCBRect.Create(220, 10, 200, 150));
    zeroSized := comp.RegisterWindow(2003, TXCBRect.Create(440, 10, 0, 0));
    AssertEquals('Three windows registered', 3, comp.Windows.Count);

    hidden.IsVisible := False;

    comp.ResetPresentStats();
    comp.CompositeScene();
    AssertEquals('Every window subtracted, including hidden and zero-sized',
                 3, comp.DamageSubtractCount);

    // A second pass must subtract again rather than only on the first frame.
    comp.ResetPresentStats();
    comp.CompositeScene();
    AssertEquals('Subtraction happens every pass', 3, comp.DamageSubtractCount);

    // The local dirty flag must survive for a window that was skipped, so it is
    // re-fetched when it becomes visible again.
    hidden.MarkDamaged();
    comp.CompositeScene();
    AssertTrue('Hidden window stays dirty for its next appearance', hidden.IsDirty);
  finally
    comp.Free();
  end;
end;

// WM-12: content-only damage may be presented as a sub-rectangle. The scene image
// is fully re-rendered, so only the changed area needs to reach the screen.
procedure TXCBCompositorTest.TestContentDamagePresentsPartially();
var
  comp: TXCBCompositor;
  w: TXCBCompositedWindow;
begin
  comp := TXCBCompositor.Create(nil, 0, 800, 600);
  try
    w := comp.RegisterWindow(3001, TXCBRect.Create(100, 50, 300, 200));

    // First present establishes the snapshot and must cover the whole screen.
    comp.CompositeScene();
    comp.PresentToScreen(1);
    AssertEquals('First present is full', 1, comp.FullPresentCount);
    AssertEquals('No partial present yet', 0, comp.PartialPresentCount);
    AssertEquals('Full present rect width', 800, comp.LastPresentRect.Width);

    // Content damage only: same geometry, same styling.
    w.MarkDamaged();
    comp.CompositeScene();
    comp.PresentToScreen(1);
    AssertEquals('Content damage presented partially', 1, comp.PartialPresentCount);
    AssertEquals('Partial rect matches the window X', 100, comp.LastPresentRect.X);
    AssertEquals('Partial rect matches the window Y', 50, comp.LastPresentRect.Y);
    AssertEquals('Partial rect matches the window width', 300, comp.LastPresentRect.Width);
    AssertEquals('Partial rect matches the window height', 200, comp.LastPresentRect.Height);

    // The partial upload must be far smaller than a full-screen one.
    AssertTrue('Partial present uploaded fewer bytes than full screen (' +
               IntToStr(comp.LastPresentBytes) + ')',
               comp.LastPresentBytes < Cardinal(800 * 600 * 4));

    // Two damaged windows union into one rect.
    w.MarkDamaged();
    comp.RegisterWindow(3002, TXCBRect.Create(500, 400, 100, 100)).MarkDamaged();
    comp.CompositeScene();
    comp.PresentToScreen(1);
    AssertTrue('Union covers the left edge', comp.LastPresentRect.X <= 100);
    AssertTrue('Union covers the bottom edge', comp.LastPresentRect.Bottom() >= 500);
  finally
    comp.Free();
  end;
end;

// WM-12: any structural change — geometry, stacking order, visibility, styling —
// forces a full present, because it can alter pixels outside the damage rects.
//
// Every case also marks content damage, so a dirty rectangle IS pending. Without
// that, the present would be full simply because nothing was dirty, and the test
// would pass even if the structural check were removed entirely.
procedure TXCBCompositorTest.TestStructuralChangeForcesFullPresent();
var
  comp: TXCBCompositor;
  w1, w2: TXCBCompositedWindow;
  before: Integer;
begin
  comp := TXCBCompositor.Create(nil, 0, 800, 600);
  try
    w1 := comp.RegisterWindow(4001, TXCBRect.Create(10, 10, 200, 150));
    w2 := comp.RegisterWindow(4002, TXCBRect.Create(220, 10, 200, 150));
    comp.CompositeScene();
    comp.PresentToScreen(1);

    // Control: content damage alone is partial. This proves the dirty-rect path is
    // active, so the full presents below are caused by the structural change and
    // not by the absence of damage.
    w1.MarkDamaged();
    comp.CompositeScene();
    comp.PresentToScreen(1);
    AssertEquals('Control: content-only is partial', 1, comp.PartialPresentCount);

    // Geometry change.
    before := comp.FullPresentCount;
    w1.MarkDamaged();
    w1.UpdateGeometry(30, 40, 250, 180);
    comp.CompositeScene();
    comp.PresentToScreen(1);
    AssertEquals('Geometry change forces a full present', before + 1, comp.FullPresentCount);

    // Stacking order change: same windows, reordered. w1 is currently first;
    // moving it to the end genuinely changes the order (moving w2 to the end
    // would leave it where it already was).
    before := comp.FullPresentCount;
    w1.MarkDamaged();
    comp.Windows.Extract(w1);
    comp.Windows.Add(w1);
    comp.CompositeScene();
    comp.PresentToScreen(1);
    AssertEquals('Reorder forces a full present', before + 1, comp.FullPresentCount);

    // Visibility change.
    before := comp.FullPresentCount;
    w1.MarkDamaged();
    w1.IsVisible := False;
    comp.CompositeScene();
    comp.PresentToScreen(1);
    AssertEquals('Visibility change forces a full present', before + 1, comp.FullPresentCount);

    // Styling change.
    before := comp.FullPresentCount;
    w2.MarkDamaged();
    w2.CornerRadius := 24;
    comp.CompositeScene();
    comp.PresentToScreen(1);
    AssertEquals('Corner radius change forces a full present', before + 1, comp.FullPresentCount);

    // Unregistering a window.
    before := comp.FullPresentCount;
    comp.UnregisterWindow(4002);
    comp.CompositeScene();
    comp.PresentToScreen(1);
    AssertEquals('Window removal forces a full present', before + 1, comp.FullPresentCount);
  finally
    comp.Free();
  end;
end;

// WM-12: Invalidate() covers changes the snapshot cannot see — the background,
// the wallpaper, or a resize.
procedure TXCBCompositorTest.TestInvalidateForcesFullPresent();
var
  comp: TXCBCompositor;
  before: Integer;
begin
  comp := TXCBCompositor.Create(nil, 0, 800, 600);
  try
    comp.RegisterWindow(5001, TXCBRect.Create(10, 10, 200, 150));
    comp.CompositeScene();
    comp.PresentToScreen(1);

    // Background colour is outside the snapshot.
    before := comp.FullPresentCount;
    comp.SetBackgroundColor(10, 20, 30, 255);
    comp.CompositeScene();
    comp.PresentToScreen(1);
    AssertEquals('Background change forces a full present', before + 1, comp.FullPresentCount);

    // Explicit invalidation.
    before := comp.FullPresentCount;
    comp.Invalidate();
    comp.CompositeScene();
    comp.PresentToScreen(1);
    AssertEquals('Invalidate forces a full present', before + 1, comp.FullPresentCount);

    // Resize rebuilds the backing image.
    before := comp.FullPresentCount;
    comp.Resize(1024, 768);
    comp.CompositeScene();
    comp.PresentToScreen(1);
    AssertEquals('Resize forces a full present', before + 1, comp.FullPresentCount);
    AssertEquals('Present rect follows the new size', 1024, comp.LastPresentRect.Width);
  finally
    comp.Free();
  end;
end;

// WM-12 regression: overlays are drawn in OnAfterRender, after the scene, so they
// are invisible to the scene snapshot. Without the overlay bookkeeping, dismissing
// or moving a HUD produced no dirty rect — the HUD's pixels stayed on screen.
//
// This was a real defect introduced by the partial-present change and caught only
// by screenshotting a live session; the earlier tests all passed while the
// desktop showed ghost HUDs.
procedure TXCBCompositorTest.TestOverlayRectDrivesPartialPresent();
var
  comp: TXCBCompositor;
  w: TXCBCompositedWindow;
  h: TOverlayHarness;
begin
  h := TOverlayHarness.Create();
  try
    h.Draw := False;
    comp := TXCBCompositor.Create(nil, 0, 1280, 800);
    try
      comp.OnAfterRender := @h.AfterRender;
      w := comp.RegisterWindow(6001, TXCBRect.Create(100, 80, 400, 300));

      // Baseline with no overlay.
      comp.CompositeScene();
      comp.PresentToScreen(1);
      AssertEquals('Baseline is a full present', 1, comp.FullPresentCount);

      // A HUD appearing must not force a full-screen present.
      comp.ResetPresentStats();
      h.Draw := True;
      h.Overlay := TXCBRect.Create(400, 300, 300, 120);
      comp.CompositeScene();
      comp.PresentToScreen(1);
      AssertEquals('HUD appearance stays partial', 1, comp.PartialPresentCount);
      AssertEquals('HUD appearance did not go full-screen', 0, comp.FullPresentCount);
      AssertEquals('Dirty rect is the HUD area only', 400, comp.LastPresentRect.X);
      AssertEquals('Dirty rect width is the HUD width', 300, comp.LastPresentRect.Width);

      // A HUD disappearing must repaint the area it used to occupy.
      comp.ResetPresentStats();
      h.Draw := False;
      comp.CompositeScene();
      comp.PresentToScreen(1);
      AssertEquals('HUD dismissal stays partial', 1, comp.PartialPresentCount);
      AssertTrue('Dirty rect covers the dismissed HUD left edge',
                 comp.LastPresentRect.X <= 400);
      AssertTrue('Dirty rect covers the dismissed HUD right edge',
                 comp.LastPresentRect.Right() >= 700);
      AssertTrue('Dirty rect covers the dismissed HUD bottom',
                 comp.LastPresentRect.Bottom() >= 420);

      // A HUD moving must cover both the old and the new position.
      comp.ResetPresentStats();
      h.Draw := True;
      h.Overlay := TXCBRect.Create(500, 400, 200, 100);
      comp.CompositeScene();
      comp.PresentToScreen(1);
      comp.ResetPresentStats();
      h.Overlay := TXCBRect.Create(800, 600, 200, 100);
      comp.CompositeScene();
      comp.PresentToScreen(1);
      AssertEquals('HUD move stays partial', 1, comp.PartialPresentCount);
      AssertTrue('Covers the old HUD position', comp.LastPresentRect.X <= 500);
      AssertTrue('Covers the new HUD position', comp.LastPresentRect.Right() >= 1000);
      AssertTrue('Covers the new HUD bottom', comp.LastPresentRect.Bottom() >= 700);
    finally
      comp.Free();
    end;
  finally
    h.Free();
  end;
end;

initialization
  RegisterTest(TXCBCompositorTest);

end.
