{ Unit Floria.XCB.WM.Compositor — Modern Compositing Subsystem for Floria XCB Window Manager

  Provides X11 Composite extension redirection, XDamage tracking, scene graph
  layering, soft drop shadows, live frosted glass / backdrop blur, and
  tear-free presentation.
}

unit Floria.XCB.WM.Compositor;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  Classes, SysUtils, Contnrs, Math,
  Floria.XCB,
  Floria.XCB.WM,
  Floria.XCB.Composite,
  Floria.XCB.Damage,
  Floria.XCB.XFixes,
  Floria.Image.Core,
  Floria.Image.Blur,
  Floria.Canvas.Agg;

type
  // Forward declarations
  TXCBCompositedWindow = class;
  TXCBCompositor = class;

  // Window shadow configuration
  TXCBWindowShadowConfig = record
    Enabled  : Boolean;
    Radius   : Integer;
    OffsetY  : Integer;
    Opacity  : Single;
    class function Create(const AEnabled: Boolean = True; const ARadius: Integer = 12;
                          const AOffsetY: Integer = 1; const AOpacity: Single = 0.22): TXCBWindowShadowConfig; static;
  end;

  // TXCBCompositedWindow
  // Represents a managed window in the compositor scene.
  //
  // TWO-SURFACE MODEL (WM-20)
  // -------------------------
  // A decorated window is two independent drawables, and each is captured
  // separately:
  //
  //   Surface 1 ("frame")  - FWindow: the WM's own decorations (titlebar, borders,
  //                          frame background). Always present.
  //   Surface 2 ("client") - FClientWindow: the application's content, reparented
  //                          inside the frame. Absent for undecorated windows.
  //
  // The earlier single-surface model named one pixmap on the frame and relied on
  // the server flattening the client into it. That works only while the server can
  // see the client's pixels; once the client's offscreen content is gone the frame
  // pixmap has a hole and there is no second source to fall back on. See WM-20.
  //
  // Both surfaces are drawn inside ONE rounded clip (see CompositeScene). Clipping
  // each surface separately puts a seam where they meet, because each clip's
  // corner antialiasing blends against whatever is underneath.
  TXCBCompositedWindow = class
  private
    FCompositor     : TXCBCompositor;
    // The registered top-level drawable: the frame when decorated, otherwise the
    // client itself.
    FWindow         : xcb_window_t;
    // The client reparented inside FWindow, or 0 when undecorated. This field was
    // historically called FrameWindow, which was actively misleading: it never
    // held a frame.
    FClientWindow   : xcb_window_t;

    // --- Surface 1: primary (frame) -------------------------------------------
    FPixmap         : xcb_pixmap_t;
    FDamage         : xcb_damage_damage_t;
    FImage          : TFloriaImage;
    FIsDirty        : Boolean;

    // --- Surface 2: client ----------------------------------------------------
    FClientPixmap   : xcb_pixmap_t;
    FClientDamage   : xcb_damage_damage_t;
    FClientImage    : TFloriaImage;
    FClientDirty    : Boolean;
    FClientOffset   : TXCBPoint;
    FClientHasAlpha : Boolean;

    FGeometry       : TXCBRect;
    FOpacity        : Single;
    FShadowConfig   : TXCBWindowShadowConfig;
    FHasBackdropBlur: Boolean;
    FBlurRadius     : Integer;
    FCornerRadius   : Integer;
    FBottomCornerRadius: Integer;
    FIsVisible      : Boolean;
    FHasAlphaChannel: Boolean;

    // Cached drop shadow (WM-18). The shadow's rendered form depends only on
    // width, height, radius, offset, blur and opacity — never on position. It was
    // being re-rasterized as 8 expanded rounded rects on every frame, which
    // measured at 86-91% of total compose time.
    //
    // Validity is decided by comparing a key against the current settings rather
    // than by invalidation calls at every mutation site: a missed invalidation
    // would silently render a stale shadow, and the key check cannot be missed.
    FShadowImage    : TFloriaImage;
    FShadowMargin   : Integer;
    FShadowKeyW     : Integer;
    FShadowKeyH     : Integer;
    FShadowKeyRad   : Integer;
    FShadowKeyOffY  : Integer;
    FShadowKeyBlur  : Integer;
    FShadowKeyOpa   : Single;
    FShadowBuildCount: Integer;

    procedure InvalidateShadowCache();
    function GetHasClient(): Boolean;
    // Fetches one surface from its named pixmap. Shared by both surfaces.
    function FetchSurface(const APixmap: xcb_pixmap_t;
                          const AWidth, AHeight: Integer;
                          const AHasAlpha: Boolean;
                          var AImage: TFloriaImage): Boolean;
  public
    // Builds the cached shadow if the settings changed. Returns False when no
    // shadow should be drawn. Public because the compositor drives the render.
    function EnsureShadowCache(): Boolean;
    property ShadowImage  : TFloriaImage read FShadowImage;
    property ShadowMargin : Integer     read FShadowMargin;
    // Number of times the shadow has been rasterized. Lets a test distinguish a
    // rebuild from a reuse: comparing image pointers is unreliable, because the
    // freed image's address is immediately reused by the replacement.
    property ShadowBuildCount: Integer  read FShadowBuildCount;
    constructor Create(const ACompositor: TXCBCompositor; const AWindow: xcb_window_t;
                       const AGeometry: TXCBRect; const AClientWindow: xcb_window_t = 0);
    destructor Destroy(); override;

    procedure UpdateGeometry(const AX, AY, AWidth, AHeight: Integer);
    // (Re)creates both offscreen surfaces and re-reads where the client sits
    // inside the frame. Called on registration and whenever dimensions change.
    procedure UpdateSurfaces();
    // Fetches whichever surfaces are dirty. Returns True if anything was fetched.
    function FetchImages(): Boolean;
    // Marks the whole window dirty (both surfaces).
    procedure MarkDamaged();
    // Marks one surface dirty. Damage notifications identify which window was
    // damaged, so most updates only need one of these.
    procedure MarkFrameDamaged();
    procedure MarkClientDamaged();
    // Subtracts the accumulated server-side damage regions without touching the
    // local dirty flags. Must be called for every registered window on every pass,
    // including ones that are not rendered, or the server-side damage regions for
    // hidden windows grow without bound.
    procedure SubtractDamage();
    procedure ClearDamage();
    // Screen-space bounds actually painted by this window: geometry plus the
    // shadow margin when a shadow is enabled. Used for damage computation.
    function PaintedRect(): TXCBRect;

    property Window         : xcb_window_t           read FWindow;
    // The reparented client, or 0 when the window is undecorated. Historically
    // exposed as FrameWindow, which never held a frame; renamed for clarity.
    property ClientWindow   : xcb_window_t           read FClientWindow write FClientWindow;
    property HasClient      : Boolean                read GetHasClient;
    property Pixmap         : xcb_pixmap_t           read FPixmap;
    property ClientPixmap   : xcb_pixmap_t           read FClientPixmap;
    property Damage         : xcb_damage_damage_t    read FDamage;
    property ClientDamage   : xcb_damage_damage_t    read FClientDamage;
    property Geometry       : TXCBRect               read FGeometry write FGeometry;
    property Opacity        : Single                 read FOpacity write FOpacity;
    property ShadowConfig   : TXCBWindowShadowConfig read FShadowConfig write FShadowConfig;
    property HasBackdropBlur: Boolean                read FHasBackdropBlur write FHasBackdropBlur;
    property BlurRadius        : Integer                read FBlurRadius write FBlurRadius;
    property CornerRadius      : Integer                read FCornerRadius write FCornerRadius;
    property BottomCornerRadius: Integer                read FBottomCornerRadius write FBottomCornerRadius;
    property IsDirty           : Boolean                read FIsDirty write FIsDirty;
    property ClientIsDirty     : Boolean                read FClientDirty write FClientDirty;
    property IsVisible      : Boolean                read FIsVisible write FIsVisible;
    // Primary (frame) surface image. For an undecorated window this is the whole
    // window; for a decorated one it is the decorations with a hole where the
    // client sits.
    property FrameImage     : TFloriaImage           read FImage write FImage;
    // Client surface image, nil when undecorated.
    property ClientImage    : TFloriaImage           read FClientImage;
    // Where the client surface sits, relative to the frame's top-left.
    property ClientOffset   : TXCBPoint              read FClientOffset;
    property HasAlphaChannel: Boolean                read FHasAlphaChannel write FHasAlphaChannel;
    property ClientHasAlphaChannel: Boolean          read FClientHasAlpha write FClientHasAlpha;
  end;

  // Scene paint notification delegate
  TXCBCompositorPaintEvent = procedure(ASender: TObject; ACanvas: TFloriaCanvasAgg; const ASceneRect: TXCBRect) of object;

  // Diagnostics sink. Wired by the shell so compositor-level problems (failed
  // redirections, surfaces that could not be fetched) are visible instead of
  // silently degrading.
  TXCBCompositorLogEvent = procedure(const AMessage: AnsiString) of object;

  // Snapshot of everything that affects the rendered scene *except* window
  // content. Comparing consecutive snapshots tells the compositor whether the
  // scene changed structurally — stacking order, geometry, visibility, styling —
  // which requires a full present. A content-only change can be presented
  // partially, because every other pixel on screen is already correct.
  //
  // Doing it this way, rather than asking callers to flag structural changes,
  // means a stacking reorder the compositor was never told about still forces a
  // full present. Missing such a notification would otherwise leave stale pixels.
  TXCBSceneEntry = record
    Window             : xcb_window_t;
    ClientWindow       : xcb_window_t;
    ClientOffset       : TXCBPoint;
    Geometry           : TXCBRect;
    Visible            : Boolean;
    Opacity            : Single;
    CornerRadius       : Integer;
    BottomCornerRadius : Integer;
    ShadowEnabled      : Boolean;
    ShadowRadius       : Integer;
    ShadowOffsetY      : Integer;
    ShadowOpacity      : Single;
    BlurEnabled        : Boolean;
    BlurRadius         : Integer;
  end;
  TXCBSceneEntryArray = array of TXCBSceneEntry;

  // TXCBCompositor
  // Master compositor coordinating redirection, damage event routing, scene rendering,
  // backdrop blurring, drop shadows, and presentation.
  TXCBCompositor = class
  private
    FConn                  : Pxcb_connection_t;
    FRootWindow            : xcb_window_t;
    FOverlayWindow         : xcb_window_t;
    FGC                    : xcb_gcontext_t;
    FIsActive              : Boolean;
    FHasComposite          : Boolean;
    FHasDamage             : Boolean;
    FCompositeMajor        : Cardinal;
    FCompositeMinor        : Cardinal;
    FDamageMajor           : Cardinal;
    FDamageMinor           : Cardinal;
    FDamageEventBase       : Byte;
    FDamageErrorBase       : Byte;
    FScreenWidth           : Integer;
    FScreenHeight          : Integer;
    FWindows               : TObjectList;
    FSceneImage            : TFloriaImage;
    FSceneCanvas           : TFloriaCanvasAgg;
    FWallpaper             : TFloriaImage;
    FBgR                   : Byte;
    FBgG                   : Byte;
    FBgB                   : Byte;
    FBgA                   : Byte;
    FOnBeforeRender        : TXCBCompositorPaintEvent;
    FOnAfterRender         : TXCBCompositorPaintEvent;
    FDebugLog              : TXCBCompositorLogEvent;

    // Present-path bookkeeping (WM-12). FDirtyRect is the union of everything
    // known to have changed since the last present; it drives a partial upload.
    FDirtyRect             : TXCBRect;
    FDirtyValid            : Boolean;
    FSceneSnapshot         : TXCBSceneEntryArray;
    FSnapshotValid         : Boolean;
    FStructuralChange      : Boolean;

    // Instrumentation, so the present path can be asserted rather than assumed.
    FLastPresentRect       : TXCBRect;
    FLastPresentBytes      : Cardinal;
    FPresentCount          : Integer;
    FFullPresentCount      : Integer;
    FPartialPresentCount   : Integer;
    FDamageSubtractCount   : Integer;

    // Shell-drawn overlay bounds (HUDs, snap previews) for this and the previous
    // frame. Overlays are painted in OnAfterRender, so they are invisible to the
    // scene snapshot; without tracking them here, dismissing or moving a HUD would
    // produce no dirty rect and leave its pixels on screen.
    FOverlayRect           : TXCBRect;
    FPrevOverlayRect       : TXCBRect;

    // Region the most recent CompositeScene actually rendered (WM-19). Recorded so
    // the partial-compose decision can be asserted without timing it.
    FLastComposeRect       : TXCBRect;

    function QueryExtensions(): Boolean;
    procedure EnsureGC();
    // True when the window's visual is 32-bit, i.e. it has a native alpha channel.
    function WindowHasAlpha(const AWindow: xcb_window_t): Boolean;
    // Enables or disables explicit redirection of a client window.
    //
    // redirect_subwindows(root) only redirects root's direct children, which are
    // the WM's frames. A client reparented inside a frame is a grandchild, so it
    // has no offscreen storage of its own and its content is lost once it is
    // covered on screen. Redirecting it gives it its own storage; the client
    // surface is then fetched from that rather than from the frame's pixmap.
    procedure RedirectClient(const AWindow: xcb_window_t; const AEnable: Boolean);
    procedure AddDirty(const ARect: TXCBRect);
    procedure ClearDirty();
    function BuildSnapshot(): TXCBSceneEntryArray;
    function SnapshotChanged(const ANew: TXCBSceneEntryArray): Boolean;
    procedure UploadRect(const ARect: TXCBRect; const ATarget: xcb_drawable_t);
    // Decides which region the next present must cover and records it. Separated
    // from the upload so the decision is testable without a live connection.
    function ComputePresentRect(): TXCBRect;
  public
    constructor Create(AConn: Pxcb_connection_t; const ARoot: xcb_window_t;
                       const AWidth: Integer = 1920; const AHeight: Integer = 1080);
    destructor Destroy(); override;

    function EnableCompositing(): Boolean;
    procedure DisableCompositing();

    // AWindow is the top-level drawable to composite: the frame when decorated,
    // otherwise the client itself. AClientWindow is the client reparented inside
    // that frame, or 0 when undecorated.
    function RegisterWindow(const AWindow: xcb_window_t; const AGeometry: TXCBRect;
                            const AClientWindow: xcb_window_t = 0): TXCBCompositedWindow;
    procedure UnregisterWindow(const AWindow: xcb_window_t);
    function FindWindow(const AWindow: xcb_window_t): TXCBCompositedWindow;

    function HandleDamageNotify(const AEvent: Pxcb_damage_notify_event_t): Boolean;
    function IsDamageNotify(const AEvent: Pxcb_generic_event_t): Boolean;
    function HandleGenericEvent(const AEvent: Pxcb_generic_event_t): Boolean;
    procedure CompositeScene();
    procedure PresentToScreen(const ATargetDrawable: xcb_drawable_t = 0);
    procedure Resize(const AWidth, AHeight: Integer);

    procedure SetWallpaper(const AImage: TFloriaImage);
    procedure SetBackgroundColor(const R, G, B: Byte; const A: Byte = 255);
    procedure SetWindowOpacity(const AWindow: xcb_window_t; const AOpacity: Single);
    procedure SetWindowBackdropBlur(const AWindow: xcb_window_t; const AEnabled: Boolean; const ARadius: Integer = 15);
    procedure SetWindowShadow(const AWindow: xcb_window_t; const AEnabled: Boolean;
                              const ARadius: Integer = 12; const AOffsetY: Integer = 4; const AOpacity: Single = 0.35);
    procedure SetWindowCornerRadius(const AWindow: xcb_window_t; const ARadius: Integer); overload;
    procedure SetWindowCornerRadius(const AWindow: xcb_window_t; const ATopRadius, ABottomRadius: Integer); overload;

    property Connection     : Pxcb_connection_t       read FConn;
    property RootWindow     : xcb_window_t            read FRootWindow;
    property OverlayWindow  : xcb_window_t            read FOverlayWindow;
    property IsActive       : Boolean                 read FIsActive;
    property HasComposite   : Boolean                 read FHasComposite;
    property HasDamage      : Boolean                 read FHasDamage;
    property DamageEventBase: Byte                    read FDamageEventBase;
    property ScreenWidth    : Integer                 read FScreenWidth write FScreenWidth;
    property ScreenHeight   : Integer                 read FScreenHeight write FScreenHeight;
    property Windows        : TObjectList             read FWindows;
    property SceneImage     : TFloriaImage            read FSceneImage;
    property SceneCanvas    : TFloriaCanvasAgg        read FSceneCanvas;
    property Wallpaper      : TFloriaImage            read FWallpaper;

    property OnBeforeRender : TXCBCompositorPaintEvent read FOnBeforeRender write FOnBeforeRender;
    property OnAfterRender  : TXCBCompositorPaintEvent read FOnAfterRender write FOnAfterRender;
    property OnDebugLog     : TXCBCompositorLogEvent read FDebugLog write FDebugLog;
    // Bounds of the overlay the shell drew in the most recent OnAfterRender call.
    property OverlayRect    : TXCBRect read FOverlayRect;
    property LastComposeRect: TXCBRect read FLastComposeRect;

    // Present-path state and instrumentation.
    property DirtyRect          : TXCBRect  read FDirtyRect;
    property DirtyValid         : Boolean   read FDirtyValid;
    property LastPresentRect    : TXCBRect  read FLastPresentRect;
    property LastPresentBytes   : Cardinal  read FLastPresentBytes;
    property PresentCount       : Integer   read FPresentCount;
    property FullPresentCount   : Integer   read FFullPresentCount;
    property PartialPresentCount: Integer   read FPartialPresentCount;
    // Number of windows whose server-side damage was subtracted. Should equal the
    // registered window count per composite pass, including hidden windows.
    property DamageSubtractCount: Integer   read FDamageSubtractCount;
    // Forces the next present to cover the whole screen (e.g. after a resize or a
    // background change). Content damage alone stays partial.
    procedure Invalidate();
    // Clears the instrumentation counters, so a test can measure one pass.
    procedure ResetPresentStats();
    // Declares the screen area the shell's OnAfterRender overlay covers this frame.
    // Pass a zero rect when nothing is drawn. The compositor unions the previous
    // and current bounds into the dirty region, so a HUD that moves or disappears
    // repaints the pixels it used to occupy. Without this, overlays are invisible
    // to the scene snapshot and leave stale pixels behind under partial present.
    procedure SetOverlayRect(const ARect: TXCBRect);
  end;

implementation

// Union of two rectangles; a zero-sized rectangle is ignored.
function RectUnion(const ARectA, ARectB: TXCBRect): TXCBRect;
var
  l, t, r, bot: Integer;
begin
  if (ARectA.Width <= 0) or (ARectA.Height <= 0) then Exit(ARectB);
  if (ARectB.Width <= 0) or (ARectB.Height <= 0) then Exit(ARectA);

  l := Min(ARectA.X, ARectB.X);
  t := Min(ARectA.Y, ARectB.Y);
  r := Max(ARectA.Right(), ARectB.Right());
  bot := Max(ARectA.Bottom(), ARectB.Bottom());
  Result := TXCBRect.Create(l, t, r - l, bot - t);
end;

// Intersect a rectangle with the screen area. Returns a zero-sized rect when
// there is no overlap.
function RectClampToScreen(const ARect: TXCBRect; const AScreenW, AScreenH: Integer): TXCBRect;
var
  l, t, r, bot: Integer;
begin
  l := ARect.X;
  t := ARect.Y;
  r := ARect.Right();
  bot := ARect.Bottom();

  if l < 0 then l := 0;
  if t < 0 then t := 0;
  if r > AScreenW then r := AScreenW;
  if bot > AScreenH then bot := AScreenH;

  if (r <= l) or (bot <= t) then
    Exit(TXCBRect.Create(0, 0, 0, 0));
  Result := TXCBRect.Create(l, t, r - l, bot - t);
end;

function ClampVal(const v, minv, maxv: Double): Double; inline;
begin
  if v < minv then Exit(minv);
  if v > maxv then Exit(maxv);
  Result := v;
end;

// -----------------------------------------------------------------------------
// TXCBWindowShadowConfig
// -----------------------------------------------------------------------------

class function TXCBWindowShadowConfig.Create(const AEnabled: Boolean; const ARadius: Integer;
                                             const AOffsetY: Integer; const AOpacity: Single): TXCBWindowShadowConfig;
begin
  Result.Enabled := AEnabled;
  Result.Radius := ARadius;
  Result.OffsetY := AOffsetY;
  Result.Opacity := AOpacity;
end;

// -----------------------------------------------------------------------------
// TXCBCompositedWindow
// -----------------------------------------------------------------------------

constructor TXCBCompositedWindow.Create(const ACompositor: TXCBCompositor; const AWindow: xcb_window_t;
                                       const AGeometry: TXCBRect; const AClientWindow: xcb_window_t);
begin
  inherited Create();
  FCompositor := ACompositor;
  FWindow := AWindow;
  FClientWindow := AClientWindow;
  FGeometry := AGeometry;
  FOpacity := 1.0;
  FShadowConfig := TXCBWindowShadowConfig.Create(True, 12, 1, 0.22);
  FHasBackdropBlur := False;
  FBlurRadius := 15;
  FCornerRadius := 10;
  FBottomCornerRadius := 10;
  FIsDirty := True;
  FClientDirty := True;
  FIsVisible := True;
  FHasAlphaChannel := False;
  FPixmap := 0;
  FDamage := 0;
  FImage := nil;

  FClientPixmap := 0;
  FClientDamage := 0;
  FClientImage := nil;
  FClientOffset := TXCBPoint.Create(0, 0);
  FClientHasAlpha := False;

  FShadowImage := nil;
  FShadowMargin := 0;
  FShadowKeyW := -1;
  FShadowKeyH := -1;
  FShadowKeyRad := -1;
  FShadowKeyOffY := 0;
  FShadowKeyBlur := -1;
  FShadowKeyOpa := -1.0;
  FShadowBuildCount := 0;

  if (FCompositor <> nil) and (FCompositor.Connection <> nil) and (FWindow <> 0) then
  begin
    // Check window visual depth to determine if window has a native 32-bit alpha channel
    FHasAlphaChannel := FCompositor.WindowHasAlpha(FWindow);

    // Damage tracking for the primary surface.
    FDamage := xcb_generate_id(FCompositor.Connection);
    xcb_damage_create(FCompositor.Connection, FDamage, FWindow, XCB_DAMAGE_REPORT_LEVEL_NON_EMPTY);

    if (FClientWindow <> 0) and (FClientWindow <> FWindow) then
    begin
      FClientHasAlpha := FCompositor.WindowHasAlpha(FClientWindow);

      // The client must be redirected in its own right to have offscreen content.
      // redirect_subwindows(root) only covers root's direct children (the frames);
      // a client reparented inside a frame is a grandchild with no storage of its
      // own, and its content is lost once it is covered on screen. This is the
      // core of WM-20.
      FCompositor.RedirectClient(FClientWindow, True);

      FClientDamage := xcb_generate_id(FCompositor.Connection);
      xcb_damage_create(FCompositor.Connection, FClientDamage, FClientWindow,
                        XCB_DAMAGE_REPORT_LEVEL_NON_EMPTY);
    end;

    // Create both named window pixmaps.
    UpdateSurfaces();
  end;
end;

destructor TXCBCompositedWindow.Destroy();
begin
  if (FCompositor <> nil) and (FCompositor.Connection <> nil) then
  begin
    if FClientDamage <> 0 then
    begin
      xcb_damage_destroy(FCompositor.Connection, FClientDamage);
      FClientDamage := 0;
    end;
    if FDamage <> 0 then
    begin
      xcb_damage_destroy(FCompositor.Connection, FDamage);
      FDamage := 0;
    end;
    if FClientPixmap <> 0 then
    begin
      xcb_free_pixmap(FCompositor.Connection, FClientPixmap);
      FClientPixmap := 0;
    end;
    if FPixmap <> 0 then
    begin
      xcb_free_pixmap(FCompositor.Connection, FPixmap);
      FPixmap := 0;
    end;

    // Give the client back to the server's normal drawing path.
    if (FClientWindow <> 0) and (FClientWindow <> FWindow) then
      FCompositor.RedirectClient(FClientWindow, False);
  end;

  if FClientImage <> nil then
  begin
    FClientImage.Free();
    FClientImage := nil;
  end;

  if FImage <> nil then
  begin
    FImage.Free();
    FImage := nil;
  end;

  InvalidateShadowCache();

  inherited Destroy();
end;

procedure TXCBCompositedWindow.UpdateGeometry(const AX, AY, AWidth, AHeight: Integer);
var
  dimsChanged: Boolean;
begin
  dimsChanged := (FGeometry.Width <> AWidth) or (FGeometry.Height <> AHeight);
  FGeometry.X := AX;
  FGeometry.Y := AY;
  FGeometry.Width := AWidth;
  FGeometry.Height := AHeight;

  if dimsChanged then
  begin
    UpdateSurfaces();
    FIsDirty := True;
    FClientDirty := True;
  end;
end;

// (Re)creates both offscreen surfaces.
//
// The client's position inside the frame is read from the server rather than
// assumed from frame insets: the WM owns the geometry, and asking avoids the
// compositor having to duplicate that knowledge (and get it wrong when insets
// change).
procedure TXCBCompositedWindow.UpdateSurfaces();
var
  geom: Pxcb_get_geometry_reply_t;
begin
  if (FCompositor = nil) or (FCompositor.Connection = nil) or (FWindow = 0) then Exit;

  // --- Surface 1: primary (frame) -------------------------------------------
  if FPixmap <> 0 then
  begin
    xcb_free_pixmap(FCompositor.Connection, FPixmap);
    FPixmap := 0;
  end;

  if (FGeometry.Width > 0) and (FGeometry.Height > 0) then
  begin
    FPixmap := xcb_generate_id(FCompositor.Connection);
    xcb_composite_name_window_pixmap(FCompositor.Connection, FWindow, FPixmap);
  end;

  // --- Surface 2: client ----------------------------------------------------
  if FClientPixmap <> 0 then
  begin
    xcb_free_pixmap(FCompositor.Connection, FClientPixmap);
    FClientPixmap := 0;
  end;

  if (FClientWindow = 0) or (FClientWindow = FWindow) then Exit;

  geom := xcb_get_geometry_reply(FCompositor.Connection,
                                 xcb_get_geometry(FCompositor.Connection, FClientWindow), nil);
  if geom = nil then Exit;
  try
    // x/y are relative to the parent, which is the frame.
    FClientOffset := TXCBPoint.Create(geom^.x, geom^.y);
    if (geom^.width > 0) and (geom^.height > 0) then
    begin
      FClientPixmap := xcb_generate_id(FCompositor.Connection);
      xcb_composite_name_window_pixmap(FCompositor.Connection, FClientWindow, FClientPixmap);
    end;
  finally
    xcb_free(geom);
  end;
end;

// Fetches one surface from its named pixmap into a TFloriaImage.
// Shared by both surfaces; returns False when there is nothing to fetch.
function TXCBCompositedWindow.FetchSurface(const APixmap: xcb_pixmap_t;
                                           const AWidth, AHeight: Integer;
                                           const AHasAlpha: Boolean;
                                           var AImage: TFloriaImage): Boolean;
var
  cookie: xcb_get_image_cookie_t;
  reply: Pxcb_get_image_reply_t;
  rawBytes: PByte;
  x, y: Integer;
  srcRow, dstRow: PByte;
  rowBytes: Integer;
begin
  Result := False;
  if (FCompositor = nil) or (FCompositor.Connection = nil) or (APixmap = 0) then Exit;
  if (AWidth <= 0) or (AHeight <= 0) then Exit;

  cookie := xcb_get_image(FCompositor.Connection, XCB_IMAGE_FORMAT_Z_PIXMAP, APixmap,
                          0, 0, AWidth, AHeight, Cardinal($FFFFFFFF));
  reply := xcb_get_image_reply(FCompositor.Connection, cookie, nil);
  if reply = nil then Exit;

  try
    rawBytes := xcb_get_image_data(reply);
    if rawBytes = nil then Exit;

    if (AImage = nil) or (AImage.Width <> AWidth) or (AImage.Height <> AHeight) then
    begin
      if AImage <> nil then AImage.Free();
      AImage := TFloriaImage.Create(AWidth, AHeight);
    end;

    rowBytes := AWidth * 4;
    for y := 0 to AHeight - 1 do
    begin
      srcRow := rawBytes + (y * rowBytes);
      dstRow := PByte(AImage.Scanline[y]);
      if AHasAlpha then
        Move(srcRow^, dstRow^, rowBytes)
      else
      begin
        for x := 0 to AWidth - 1 do
          PDWord(dstRow + (x * 4))^ := PDWord(srcRow + (x * 4))^ or Cardinal($FF000000);
      end;
    end;

    Result := True;
  finally
    xcb_free(reply);
  end;
end;

// Fetches whichever surfaces are dirty. Returns True when anything was fetched,
// so the caller knows the scene changed.
function TXCBCompositedWindow.FetchImages(): Boolean;
var
  geom: Pxcb_get_geometry_reply_t;
  cw, ch: Integer;
begin
  Result := False;

  if FIsDirty and (FPixmap <> 0) then
  begin
    if FetchSurface(FPixmap, FGeometry.Width, FGeometry.Height, FHasAlphaChannel, FImage) then
      Result := True;
    FIsDirty := False;
  end;

  if FClientDirty and (FClientPixmap <> 0) and (FClientWindow <> 0) then
  begin
    // The client's size can differ from the frame's, and can change without the
    // frame changing (shading, for example), so ask rather than assume.
    cw := 0;
    ch := 0;
    geom := xcb_get_geometry_reply(FCompositor.Connection,
                                   xcb_get_geometry(FCompositor.Connection, FClientWindow), nil);
    if geom <> nil then
    begin
      cw := geom^.width;
      ch := geom^.height;
      FClientOffset := TXCBPoint.Create(geom^.x, geom^.y);
      xcb_free(geom);
    end;

    if (cw > 0) and (ch > 0) then
    begin
      if (FClientImage = nil) or (FClientImage.Width <> cw) or (FClientImage.Height <> ch) then
      begin
        // The pixmap was named at the old size; re-name it for the new one.
        xcb_free_pixmap(FCompositor.Connection, FClientPixmap);
        FClientPixmap := xcb_generate_id(FCompositor.Connection);
        xcb_composite_name_window_pixmap(FCompositor.Connection, FClientWindow, FClientPixmap);
      end;
      if FetchSurface(FClientPixmap, cw, ch, FClientHasAlpha, FClientImage) then
        Result := True;
    end;
    FClientDirty := False;
  end;
end;

procedure TXCBCompositedWindow.MarkDamaged();
begin
  FIsDirty := True;
  FClientDirty := True;
  // Content changed inside the window: only that area of the scene needs
  // presenting. Structural changes are detected separately via the scene
  // snapshot, so this stays conservative.
  if FCompositor <> nil then
    FCompositor.AddDirty(FGeometry);
end;

procedure TXCBCompositedWindow.MarkFrameDamaged();
begin
  FIsDirty := True;
  if FCompositor <> nil then
    FCompositor.AddDirty(FGeometry);
end;

procedure TXCBCompositedWindow.MarkClientDamaged();
begin
  FClientDirty := True;
  if FCompositor <> nil then
    FCompositor.AddDirty(FGeometry);
end;

procedure TXCBCompositedWindow.SubtractDamage();
begin
  if FCompositor <> nil then
    Inc(FCompositor.FDamageSubtractCount);
  if (FCompositor <> nil) and (FCompositor.Connection <> nil) then
  begin
    if FDamage <> 0 then
      xcb_damage_subtract(FCompositor.Connection, FDamage, 0, 0);
    if FClientDamage <> 0 then
      xcb_damage_subtract(FCompositor.Connection, FClientDamage, 0, 0);
  end;
end;

procedure TXCBCompositedWindow.ClearDamage();
begin
  SubtractDamage();
  FIsDirty := False;
  FClientDirty := False;
end;

function TXCBCompositedWindow.GetHasClient(): Boolean;
begin
  Result := (FClientWindow <> 0) and (FClientWindow <> FWindow);
end;

procedure TXCBCompositedWindow.InvalidateShadowCache();
begin
  if FShadowImage <> nil then
  begin
    FShadowImage.Free();
    FShadowImage := nil;
  end;
  FShadowMargin := 0;
  FShadowKeyW := -1;
  FShadowKeyH := -1;
  FShadowKeyRad := -1;
  FShadowKeyOffY := 0;
  FShadowKeyBlur := -1;
  FShadowKeyOpa := -1.0;
end;

// Build (or reuse) the shadow image. The rendered shadow depends only on the
// window's size, corner radius, shadow offset/radius/opacity — all of which change
// rarely. Rasterizing it per frame cost 86-91% of compose time.
function TXCBCompositedWindow.EnsureShadowCache(): Boolean;
var
  need: Boolean;
  w, h, rad, offY, blur, margin: Integer;
  opa: Single;
  shadowCanvas: TFloriaCanvasAgg;
begin
  Result := False;
  if not FShadowConfig.Enabled then Exit;
  if (FGeometry.Width <= 0) or (FGeometry.Height <= 0) then Exit;

  w := FGeometry.Width;
  h := FGeometry.Height;
  rad := FCornerRadius;
  offY := FShadowConfig.OffsetY;
  blur := FShadowConfig.Radius;
  opa := FShadowConfig.Opacity;

  if blur <= 0 then Exit;
  if opa <= 0 then Exit;

  // DrawShadow expands each of its passes by up to BlurRadius/2 beyond the window
  // edge, then offsets vertically.
  margin := (blur div 2) + 2 + Abs(offY);

  need := (FShadowImage = nil) or
          (FShadowKeyW <> w) or (FShadowKeyH <> h) or
          (FShadowKeyRad <> rad) or (FShadowKeyOffY <> offY) or
          (FShadowKeyBlur <> blur) or (FShadowKeyOpa <> opa) or
          (FShadowMargin <> margin);

  if need then
  begin
    InvalidateShadowCache();

    FShadowImage := TFloriaImage.Create(w + margin * 2, h + margin * 2);
    FShadowImage.Clear(0, 0, 0, 0);
    shadowCanvas := TFloriaCanvasAgg.Create(FShadowImage);
    try
      // Drawn at the margin offset so the blit can be placed at (X - margin,
      // Y - margin) and land exactly under the window.
      shadowCanvas.DrawShadow(margin, margin, w, h, rad, 0, offY, blur,
                              0.0, 0.0, 0.0, opa);
    finally
      shadowCanvas.Free();
    end;

    Inc(FShadowBuildCount);
    FShadowMargin := margin;
    FShadowKeyW := w;
    FShadowKeyH := h;
    FShadowKeyRad := rad;
    FShadowKeyOffY := offY;
    FShadowKeyBlur := blur;
    FShadowKeyOpa := opa;
  end;

  Result := FShadowImage <> nil;
end;

function TXCBCompositedWindow.PaintedRect(): TXCBRect;
var
  margin: Integer;
begin
  margin := 0;
  if FShadowConfig.Enabled and (FShadowConfig.Radius > 0) then
    margin := (FShadowConfig.Radius div 2) + 2 + Abs(FShadowConfig.OffsetY);

  Result := TXCBRect.Create(FGeometry.X - margin,
                            FGeometry.Y - margin,
                            FGeometry.Width + margin * 2,
                            FGeometry.Height + margin * 2);
end;

// -----------------------------------------------------------------------------
// TXCBCompositor
// -----------------------------------------------------------------------------

constructor TXCBCompositor.Create(AConn: Pxcb_connection_t; const ARoot: xcb_window_t;
                                  const AWidth: Integer; const AHeight: Integer);
begin
  inherited Create();
  FConn := AConn;
  FRootWindow := ARoot;
  FOverlayWindow := 0;
  FGC := 0;
  FIsActive := False;
  FHasComposite := False;
  FHasDamage := False;
  FCompositeMajor := 0;
  FCompositeMinor := 0;
  FDamageMajor := 0;
  FDamageMinor := 0;
  FScreenWidth := Max(1, AWidth);
  FScreenHeight := Max(1, AHeight);
  FWindows := TObjectList.Create(True);
  FWallpaper := nil;
  FBgR := $1E;
  FBgG := $1E;
  FBgB := $2E;
  FBgA := $FF; // Modern dark slate ($FF1E1E2E)

  FSceneImage := TFloriaImage.Create(FScreenWidth, FScreenHeight);
  FSceneImage.Clear(FBgR, FBgG, FBgB, FBgA);
  FSceneCanvas := TFloriaCanvasAgg.Create(FSceneImage);

  FDirtyRect := TXCBRect.Create(0, 0, 0, 0);
  FDirtyValid := False;
  FLastComposeRect := TXCBRect.Create(0, 0, 0, 0);
  SetLength(FSceneSnapshot, 0);
  FSnapshotValid := False;
  FStructuralChange := True;
  FLastPresentRect := TXCBRect.Create(0, 0, 0, 0);
  FLastPresentBytes := 0;
  FPresentCount := 0;
  FFullPresentCount := 0;
  FPartialPresentCount := 0;
  FDamageSubtractCount := 0;

  QueryExtensions();
end;

destructor TXCBCompositor.Destroy();
begin
  DisableCompositing();

  if FWindows <> nil then
  begin
    FWindows.Free();
    FWindows := nil;
  end;

  if FSceneCanvas <> nil then
  begin
    FSceneCanvas.Free();
    FSceneCanvas := nil;
  end;

  if FSceneImage <> nil then
  begin
    FSceneImage.Free();
    FSceneImage := nil;
  end;

  if FWallpaper <> nil then
  begin
    FWallpaper.Free();
    FWallpaper := nil;
  end;

  if (FConn <> nil) and (FGC <> 0) then
  begin
    xcb_free_gc(FConn, FGC);
    FGC := 0;
  end;

  inherited Destroy();
end;

function TXCBCompositor.QueryExtensions(): Boolean;
var
  compCookie: xcb_composite_query_version_cookie_t;
  compReply: Pxcb_composite_query_version_reply_t;
  dmgCookie: xcb_damage_query_version_cookie_t;
  dmgReply: Pxcb_damage_query_version_reply_t;
  extReply: Pxcb_query_extension_reply_t;
begin
  Result := False;
  if FConn = nil then Exit;

  // Query Composite extension
  compCookie := xcb_composite_query_version(FConn, 0, 4);
  compReply := xcb_composite_query_version_reply(FConn, compCookie, nil);
  if compReply <> nil then
  begin
    FHasComposite := True;
    FCompositeMajor := compReply^.major_version;
    FCompositeMinor := compReply^.minor_version;
    xcb_free(compReply);
  end;

  // Query Damage extension. The version reply succeeding is not sufficient: the
  // extension may still be absent, in which case FDamageEventBase would stay 0
  // and event-type matching would alias X errors. Only claim the extension once
  // the event base is known.
  dmgCookie := xcb_damage_query_version(FConn, 1, 1);
  dmgReply := xcb_damage_query_version_reply(FConn, dmgCookie, nil);
  if dmgReply <> nil then
  begin
    FDamageMajor := dmgReply^.major_version;
    FDamageMinor := dmgReply^.minor_version;
    xcb_free(dmgReply);

    extReply := xcb_get_extension_data(FConn, @xcb_damage_id);
    if (extReply <> nil) and (extReply^.present <> 0) then
    begin
      FDamageEventBase := extReply^.first_event;
      FDamageErrorBase := extReply^.first_error;
      FHasDamage := True;
    end;
  end;

  Result := FHasComposite and FHasDamage;
end;

function TXCBCompositor.WindowHasAlpha(const AWindow: xcb_window_t): Boolean;
var
  geom: Pxcb_get_geometry_reply_t;
begin
  Result := False;
  if (FConn = nil) or (AWindow = 0) then Exit;
  geom := xcb_get_geometry_reply(FConn, xcb_get_geometry(FConn, AWindow), nil);
  if geom = nil then Exit;
  try
    Result := geom^.depth = 32;
  finally
    xcb_free(geom);
  end;
end;

procedure TXCBCompositor.RedirectClient(const AWindow: xcb_window_t; const AEnable: Boolean);
var
  cookie: xcb_void_cookie_t;
  err: Pxcb_generic_error_t;
begin
  if (FConn = nil) or (AWindow = 0) then Exit;
  if not FHasComposite then Exit;

  if AEnable then
    cookie := xcb_composite_redirect_window_checked(FConn, AWindow,
                                                    XCB_COMPOSITE_REDIRECT_MANUAL)
  else
    cookie := xcb_composite_unredirect_window_checked(FConn, AWindow,
                                                      XCB_COMPOSITE_REDIRECT_MANUAL);

  // A failure here means the client will fall back to being flattened into the
  // frame's pixmap. That still renders, so it is not fatal, but the client surface
  // will be empty and the WM-20 class of artifact can return. Report it rather
  // than failing silently.
  err := xcb_request_check(FConn, cookie);
  if err <> nil then
  begin
    if FDebugLog <> nil then
      FDebugLog(Format('RedirectClient(0x%.x, %s) failed: error %d',
        [AWindow, BoolToStr(AEnable, 'on', 'off'), err^.error_code]));
    xcb_free(err);
  end;

  xcb_flush(FConn);
end;

procedure TXCBCompositor.EnsureGC();
var
  mask: Cardinal;
  values: array[0..0] of Cardinal;
begin
  if (FConn = nil) or (FGC <> 0) or (FRootWindow = 0) then Exit;
  FGC := xcb_generate_id(FConn);
  mask := 0;
  xcb_create_gc(FConn, FGC, FRootWindow, mask, @values[0]);
end;

procedure TXCBCompositor.ResetPresentStats();
begin
  FPresentCount := 0;
  FFullPresentCount := 0;
  FPartialPresentCount := 0;
  FDamageSubtractCount := 0;
  FLastPresentBytes := 0;
  FLastPresentRect := TXCBRect.Create(0, 0, 0, 0);
end;

// The shell declares what its OnAfterRender overlay covers. Called from inside the
// overlay painter, so it describes the frame currently being composed.
procedure TXCBCompositor.SetOverlayRect(const ARect: TXCBRect);
begin
  FOverlayRect := ARect;
end;

// Force the next present to cover the whole screen.
procedure TXCBCompositor.Invalidate();
begin
  FDirtyValid := False;
  FSnapshotValid := False;
end;

// Union a changed region into the pending present area, clamped to the screen.
procedure TXCBCompositor.AddDirty(const ARect: TXCBRect);
var
  l, t, r, b: Integer;
begin
  if (ARect.Width <= 0) or (ARect.Height <= 0) then Exit;

  l := ARect.X;
  t := ARect.Y;
  r := ARect.Right();
  b := ARect.Bottom();

  if l < 0 then l := 0;
  if t < 0 then t := 0;
  if r > FScreenWidth then r := FScreenWidth;
  if b > FScreenHeight then b := FScreenHeight;
  if (r <= l) or (b <= t) then Exit;

  if not FDirtyValid then
  begin
    FDirtyRect := TXCBRect.Create(l, t, r - l, b - t);
    FDirtyValid := True;
    Exit;
  end;

  if l < FDirtyRect.X then FDirtyRect.X := l;
  if t < FDirtyRect.Y then FDirtyRect.Y := t;
  if r > FDirtyRect.Right() then
    FDirtyRect.Width := r - FDirtyRect.X;
  if b > FDirtyRect.Bottom() then
    FDirtyRect.Height := b - FDirtyRect.Y;
end;

procedure TXCBCompositor.ClearDirty();
begin
  FDirtyValid := False;
  FDirtyRect := TXCBRect.Create(0, 0, 0, 0);
end;

function TXCBCompositor.BuildSnapshot(): TXCBSceneEntryArray;
var
  i: Integer;
  w: TXCBCompositedWindow;
begin
  SetLength(Result, FWindows.Count);
  for i := 0 to FWindows.Count - 1 do
  begin
    w := TXCBCompositedWindow(FWindows[i]);
    Result[i].Window := w.Window;
    Result[i].ClientWindow := w.ClientWindow;
    Result[i].ClientOffset := w.ClientOffset;
    Result[i].Geometry := w.Geometry;
    Result[i].Visible := w.IsVisible;
    Result[i].Opacity := w.Opacity;
    Result[i].CornerRadius := w.CornerRadius;
    Result[i].BottomCornerRadius := w.BottomCornerRadius;
    Result[i].ShadowEnabled := w.ShadowConfig.Enabled;
    Result[i].ShadowRadius := w.ShadowConfig.Radius;
    Result[i].ShadowOffsetY := w.ShadowConfig.OffsetY;
    Result[i].ShadowOpacity := w.ShadowConfig.Opacity;
    Result[i].BlurEnabled := w.HasBackdropBlur;
    Result[i].BlurRadius := w.BlurRadius;
  end;
end;

// True when anything other than window *content* changed: order, geometry,
// visibility, opacity, corner radii, shadow or blur settings.
function TXCBCompositor.SnapshotChanged(const ANew: TXCBSceneEntryArray): Boolean;
var
  i: Integer;
  a, b: TXCBSceneEntry;
begin
  Result := True;
  if not FSnapshotValid then Exit;
  if Length(ANew) <> Length(FSceneSnapshot) then Exit;

  for i := 0 to High(ANew) do
  begin
    a := ANew[i];
    b := FSceneSnapshot[i];
    if (a.Window <> b.Window) or
       (a.ClientWindow <> b.ClientWindow) or
       (a.ClientOffset.X <> b.ClientOffset.X) or
       (a.ClientOffset.Y <> b.ClientOffset.Y) or
       (a.Geometry.X <> b.Geometry.X) or
       (a.Geometry.Y <> b.Geometry.Y) or
       (a.Geometry.Width <> b.Geometry.Width) or
       (a.Geometry.Height <> b.Geometry.Height) or
       (a.Visible <> b.Visible) or
       (a.Opacity <> b.Opacity) or
       (a.CornerRadius <> b.CornerRadius) or
       (a.BottomCornerRadius <> b.BottomCornerRadius) or
       (a.ShadowEnabled <> b.ShadowEnabled) or
       (a.ShadowRadius <> b.ShadowRadius) or
       (a.ShadowOffsetY <> b.ShadowOffsetY) or
       (a.ShadowOpacity <> b.ShadowOpacity) or
       (a.BlurEnabled <> b.BlurEnabled) or
       (a.BlurRadius <> b.BlurRadius) then
      Exit;
  end;

  Result := False;
end;

// Upload one rectangle of the scene image to the target drawable. Rows are copied
// into a tight buffer because xcb_put_image expects contiguous rows of exactly
// the requested width, while the scene image has full-screen stride.
procedure TXCBCompositor.UploadRect(const ARect: TXCBRect; const ATarget: xcb_drawable_t);
var
  rowBytes: Cardinal;
  dataLen: Cardinal;
  y: Integer;
  buf: PByte;
  src: PByte;
begin
  if (FSceneImage = nil) or (FConn = nil) or (ATarget = 0) then Exit;
  if (ARect.Width <= 0) or (ARect.Height <= 0) then Exit;

  rowBytes := Cardinal(ARect.Width) * 4;
  dataLen := rowBytes * Cardinal(ARect.Height);

  GetMem(buf, dataLen);
  try
    for y := 0 to ARect.Height - 1 do
    begin
      src := PByte(FSceneImage.Scanline[ARect.Y + y]) + ARect.X * 4;
      Move(src^, (buf + Cardinal(y) * rowBytes)^, rowBytes);
    end;

    xcb_put_image(FConn, XCB_IMAGE_FORMAT_Z_PIXMAP, ATarget, FGC,
                  ARect.Width, ARect.Height, ARect.X, ARect.Y, 0, 24,
                  dataLen, buf);
  finally
    FreeMem(buf);
  end;

  FLastPresentBytes := dataLen;
end;

function TXCBCompositor.EnableCompositing(): Boolean;
begin
  Result := False;
  if FIsActive then Exit(True);
  if (FConn = nil) or (FRootWindow = 0) then Exit;

  if not QueryExtensions() then Exit(False);

  // Redirect all subwindows under the root window to offscreen storage
  xcb_composite_redirect_subwindows(FConn, FRootWindow, XCB_COMPOSITE_REDIRECT_MANUAL);

  FOverlayWindow := 0;

  EnsureGC();
  FIsActive := True;
  Result := True;
end;

procedure TXCBCompositor.DisableCompositing();
begin
  if not FIsActive then Exit;

  if (FConn <> nil) and (FRootWindow <> 0) then
  begin
    if FHasComposite then
      xcb_composite_unredirect_subwindows(FConn, FRootWindow, XCB_COMPOSITE_REDIRECT_MANUAL);

    if (FOverlayWindow <> 0) and (FOverlayWindow <> FRootWindow) and FHasComposite then
    begin
      xcb_composite_release_overlay_window(FConn, FRootWindow);
      FOverlayWindow := 0;
    end;
  end;

  FIsActive := False;
end;

function TXCBCompositor.RegisterWindow(const AWindow: xcb_window_t; const AGeometry: TXCBRect;
                                      const AClientWindow: xcb_window_t): TXCBCompositedWindow;
begin
  Result := FindWindow(AWindow);
  if Result <> nil then
  begin
    Result.UpdateGeometry(AGeometry.X, AGeometry.Y, AGeometry.Width, AGeometry.Height);
    Result.ClientWindow := AClientWindow;
    Result.UpdateSurfaces();
    Exit;
  end;

  Result := TXCBCompositedWindow.Create(Self, AWindow, AGeometry, AClientWindow);
  FWindows.Add(Result);
end;

procedure TXCBCompositor.UnregisterWindow(const AWindow: xcb_window_t);
var
  i: Integer;
  w: TXCBCompositedWindow;
begin
  for i := FWindows.Count - 1 downto 0 do
  begin
    w := TXCBCompositedWindow(FWindows[i]);
    if (w.Window = AWindow) or (w.ClientWindow = AWindow) then
    begin
      FWindows.Delete(i);
      Exit;
    end;
  end;
end;

function TXCBCompositor.FindWindow(const AWindow: xcb_window_t): TXCBCompositedWindow;
var
  i: Integer;
  w: TXCBCompositedWindow;
begin
  Result := nil;
  for i := 0 to FWindows.Count - 1 do
  begin
    w := TXCBCompositedWindow(FWindows[i]);
    if (w.Window = AWindow) or (w.ClientWindow = AWindow) then
      Exit(w);
  end;
end;

function TXCBCompositor.HandleDamageNotify(const AEvent: Pxcb_damage_notify_event_t): Boolean;
var
  w: TXCBCompositedWindow;
begin
  Result := False;
  if AEvent = nil then Exit;

  w := FindWindow(AEvent^.drawable);
  if w = nil then Exit;

  // Route to the surface that actually changed. Damage on the client window means
  // only the client image needs re-fetching; damage on the frame means only the
  // decorations do. Marking both would double the round-trips for the common case
  // (typing in a terminal), which is the whole point of tracking them separately.
  if (w.ClientWindow <> 0) and (AEvent^.drawable = w.ClientWindow) then
    w.MarkClientDamaged()
  else
    w.MarkFrameDamaged();

  Result := True;
end;

function TXCBCompositor.IsDamageNotify(const AEvent: Pxcb_generic_event_t): Boolean;
begin
  Result := False;
  if (AEvent = nil) or not FHasDamage then Exit;
  // FDamageEventBase = 0 means the event base was never resolved. Without this
  // guard the comparison degenerates to (response_type and $7F) = 0, which
  // matches X *error* events — they would be handed to HandleDamageNotify and
  // reinterpreted as damage notifications with garbage drawable ids.
  if FDamageEventBase = 0 then Exit;
  Result := ((AEvent^.response_type and $7F) = FDamageEventBase + XCB_DAMAGE_NOTIFY);
end;

function TXCBCompositor.HandleGenericEvent(const AEvent: Pxcb_generic_event_t): Boolean;
begin
  Result := False;
  if IsDamageNotify(AEvent) then
    Result := HandleDamageNotify(Pxcb_damage_notify_event_t(AEvent));
end;

procedure TXCBCompositor.SetWallpaper(const AImage: TFloriaImage);
begin
  if FWallpaper <> nil then
    FWallpaper.Free();
  FWallpaper := AImage;
  // The background is outside the scene snapshot, so a change here must force a
  // full present explicitly.
  Invalidate();
end;

procedure TXCBCompositor.SetBackgroundColor(const R, G, B: Byte; const A: Byte);
begin
  FBgR := R;
  FBgG := G;
  FBgB := B;
  FBgA := A;
  Invalidate();
end;

procedure TXCBCompositor.SetWindowOpacity(const AWindow: xcb_window_t; const AOpacity: Single);
var
  w: TXCBCompositedWindow;
begin
  w := FindWindow(AWindow);
  if w <> nil then
    w.Opacity := ClampVal(AOpacity, 0.0, 1.0);
end;

procedure TXCBCompositor.SetWindowBackdropBlur(const AWindow: xcb_window_t; const AEnabled: Boolean; const ARadius: Integer);
var
  w: TXCBCompositedWindow;
begin
  w := FindWindow(AWindow);
  if w <> nil then
  begin
    w.HasBackdropBlur := AEnabled;
    w.BlurRadius := Max(1, ARadius);
  end;
end;

procedure TXCBCompositor.SetWindowShadow(const AWindow: xcb_window_t; const AEnabled: Boolean;
                                        const ARadius: Integer; const AOffsetY: Integer; const AOpacity: Single);
var
  w: TXCBCompositedWindow;
begin
  w := FindWindow(AWindow);
  if w <> nil then
    w.ShadowConfig := TXCBWindowShadowConfig.Create(AEnabled, ARadius, AOffsetY, AOpacity);
end;

procedure TXCBCompositor.SetWindowCornerRadius(const AWindow: xcb_window_t; const ARadius: Integer);
begin
  SetWindowCornerRadius(AWindow, ARadius, ARadius);
end;

procedure TXCBCompositor.SetWindowCornerRadius(const AWindow: xcb_window_t; const ATopRadius, ABottomRadius: Integer);
var
  w: TXCBCompositedWindow;
begin
  w := FindWindow(AWindow);
  if w <> nil then
  begin
    w.CornerRadius := Max(0, ATopRadius);
    w.BottomCornerRadius := Max(0, ABottomRadius);
  end;
end;

procedure TXCBCompositor.CompositeScene();
var
  i: Integer;
  w: TXCBCompositedWindow;
  rect: TXCBRect;
  backdropImg: TFloriaImage;
  srcX, srcY, bw, bh: Integer;
  newSnapshot: TXCBSceneEntryArray;
  fullRect, composeRect: TXCBRect;
begin
  if (FSceneImage = nil) or (FSceneCanvas = nil) then Exit;

  // Decide the compose region before rendering (WM-19).
  //
  // The snapshot depends only on window state, not on rendering, so it can be
  // evaluated up front. That lets a content-only change recompose just the
  // affected area instead of the whole screen: everything outside it is already
  // correct from the previous frame, because only a structural change can alter
  // pixels elsewhere.
  //
  // FPrevOverlayRect must be included. A HUD that disappeared or moved left pixels
  // at its old position, and those only get erased if the background and windows
  // beneath are re-rendered there.
  newSnapshot := BuildSnapshot();
  FStructuralChange := SnapshotChanged(newSnapshot);

  fullRect := TXCBRect.Create(0, 0, FScreenWidth, FScreenHeight);
  if FStructuralChange or (not FDirtyValid) then
    composeRect := fullRect
  else
  begin
    composeRect := FDirtyRect;
    if FPrevOverlayRect.Width > 0 then
    begin
      composeRect := RectUnion(composeRect, FPrevOverlayRect);
    end;
  end;

  // Clamp to the screen.
  composeRect := RectClampToScreen(composeRect, FScreenWidth, FScreenHeight);
  FLastComposeRect := composeRect;

  // 1. Render Wallpaper or Solid Desktop Background, within the compose region
  //    only. Clear() always covers the whole image and ignores the canvas clip, so
  //    a partial recompose needs the rectangle-aware variant.
  if FWallpaper <> nil then
    FSceneCanvas.DrawImage(0, 0, FWallpaper)
  else
    FSceneImage.ClearRect(composeRect.X, composeRect.Y,
                          composeRect.Width, composeRect.Height,
                          FBgR, FBgG, FBgB, FBgA);

  rect := fullRect;
  if Assigned(FOnBeforeRender) then
    FOnBeforeRender(Self, FSceneCanvas, rect);

  // Reset before the overlay painter runs, so a frame with no overlay reports an
  // empty rect rather than inheriting the previous frame's bounds.
  FOverlayRect := TXCBRect.Create(0, 0, 0, 0);

  // 2. Render Windows in stacking order (bottom to top), clipped to the compose
  //    region. Windows outside it are still walked (their damage must be
  //    subtracted) but their drawing is discarded by the clip.
  FSceneCanvas.PushClipRect(composeRect.X, composeRect.Y,
                            composeRect.Width, composeRect.Height);

  for i := 0 to FWindows.Count - 1 do
  begin
    w := TXCBCompositedWindow(FWindows[i]);

    // Subtract the server-side damage region for EVERY registered window, before
    // any decision to skip it. Doing this only for rendered windows let hidden,
    // shaded and zero-geometry windows accumulate damage regions in the server
    // without bound. The local dirty flag is left alone, so a window that
    // reappears still triggers a fresh fetch.
    w.SubtractDamage();

    if not w.IsVisible or (w.Geometry.Width <= 0) or (w.Geometry.Height <= 0) then
      Continue;

    // Fetch whichever surfaces changed. Each is a separate round-trip, so this
    // only touches the ones actually marked dirty.
    w.FetchImages();

    // A. Render Soft Gaussian Drop Shadow from the cached image (WM-18).
    // Re-rasterizing it per frame measured at 86-91% of compose time; blitting the
    // cached version is ~7x cheaper and the result is identical.
    if w.EnsureShadowCache() then
      FSceneCanvas.DrawImage(w.Geometry.X - w.ShadowMargin,
                             w.Geometry.Y - w.ShadowMargin,
                             w.ShadowImage);

    // B. Render Frosted Glass Backdrop Blur (if enabled)
    if w.HasBackdropBlur and (w.Geometry.Width > 0) and (w.Geometry.Height > 0) then
    begin
      srcX := Max(0, w.Geometry.X);
      srcY := Max(0, w.Geometry.Y);
      bw := Min(w.Geometry.Width, FScreenWidth - srcX);
      bh := Min(w.Geometry.Height, FScreenHeight - srcY);

      if (bw > 0) and (bh > 0) then
      begin
        backdropImg := TFloriaImage.Create(bw, bh);
        try
          backdropImg.CopyFrom(FSceneImage, srcX, srcY, 0, 0, bw, bh);
          FloriaFastBlur(backdropImg, 0, 0, bw, bh, w.CornerRadius, w.BlurRadius);
          FSceneCanvas.DrawImage(srcX, srcY, backdropImg);
        finally
          backdropImg.Free();
        end;
      end;
    end;

    // C. Render the window surfaces: frame first, then the client on top.
    //
    // BOTH draws go inside ONE rounded clip. Clipping each surface separately
    // leaves a visible seam where they meet: each clip's corner antialiasing
    // blends against whatever is underneath, so the client's first row would blend
    // against the frame background instead of against the titlebar. Measured: a
    // 1px seam at the titlebar/client boundary, 122 pixels, up to 63/255 off.
    //
    // Verified pixel-identical to the previous single-surface rendering, including
    // when the corner radius exceeds the titlebar height.
    if (w.FrameImage <> nil) or (w.ClientImage <> nil) then
    begin
      if ((w.CornerRadius > 0) or (w.BottomCornerRadius > 0)) and
         (w.Geometry.Width > Max(w.CornerRadius, w.BottomCornerRadius) * 2) and
         (w.Geometry.Height > Max(w.CornerRadius, w.BottomCornerRadius) * 2) then
      begin
        FSceneCanvas.PushClipRoundedRect(w.Geometry.X, w.Geometry.Y, w.Geometry.Width, w.Geometry.Height,
                                         w.CornerRadius, w.BottomCornerRadius);
        if w.FrameImage <> nil then
          FSceneCanvas.DrawImage(w.Geometry.X, w.Geometry.Y, w.FrameImage, w.Opacity);
        if w.ClientImage <> nil then
          FSceneCanvas.DrawImage(w.Geometry.X + w.ClientOffset.X,
                                 w.Geometry.Y + w.ClientOffset.Y,
                                 w.ClientImage, w.Opacity);
        FSceneCanvas.PopClipRoundedRect();
      end
      else
      begin
        if w.FrameImage <> nil then
          FSceneCanvas.DrawImage(w.Geometry.X, w.Geometry.Y, w.FrameImage, w.Opacity);
        if w.ClientImage <> nil then
          FSceneCanvas.DrawImage(w.Geometry.X + w.ClientOffset.X,
                                 w.Geometry.Y + w.ClientOffset.Y,
                                 w.ClientImage, w.Opacity);
      end;
    end;
  end;

  FSceneCanvas.PopClipRect();

  // Overlays are drawn unclipped: they are small, and a HUD outside the compose
  // region must still be painted into the scene image. Its bounds are added to the
  // dirty region below, so the present covers it.
  if Assigned(FOnAfterRender) then
    FOnAfterRender(Self, FSceneCanvas, rect);

  // Overlay bookkeeping. Overlays are painted after the scene and are not part of
  // the snapshot, so a HUD that appears, moves or disappears would otherwise leave
  // stale pixels on screen: nothing in the dirty region would cover its old
  // position. Unioning the previous and current bounds fixes that, and keeps the
  // present partial rather than forcing a full screen for every HUD change.
  if (FPrevOverlayRect.Width > 0) or (FOverlayRect.Width > 0) then
  begin
    if (FOverlayRect.Width <> FPrevOverlayRect.Width) or
       (FOverlayRect.Height <> FPrevOverlayRect.Height) or
       (FOverlayRect.X <> FPrevOverlayRect.X) or
       (FOverlayRect.Y <> FPrevOverlayRect.Y) then
    begin
      AddDirty(FPrevOverlayRect);
      AddDirty(FOverlayRect);
    end;
  end;
  FPrevOverlayRect := FOverlayRect;

  // Store the snapshot computed at the top of this pass, so the next frame can
  // compare against what was actually rendered.
  FSceneSnapshot := newSnapshot;
  FSnapshotValid := True;
end;

function TXCBCompositor.ComputePresentRect(): TXCBRect;
begin
  // A partial upload is only safe when the only thing that changed since the last
  // present was window content. Any structural change — stacking, geometry,
  // visibility, styling — forces the full screen, because those can alter pixels
  // outside the damage rectangles (a shadow left behind by a moved window, a
  // window uncovered by a reorder).
  //
  // Presenting a sub-rectangle is valid because the scene image is always fully
  // re-rendered: every pixel in it is current, so only the changed area needs to
  // reach the screen.
  if FDirtyValid and (not FStructuralChange) and
     (FDirtyRect.Width > 0) and (FDirtyRect.Height > 0) then
  begin
    Result := FDirtyRect;
    Inc(FPartialPresentCount);
  end
  else
  begin
    Result := TXCBRect.Create(0, 0, FScreenWidth, FScreenHeight);
    Inc(FFullPresentCount);
  end;

  FLastPresentRect := Result;
end;

procedure TXCBCompositor.PresentToScreen(const ATargetDrawable: xcb_drawable_t);
var
  target: xcb_drawable_t;
  presentRect: TXCBRect;
begin
  if FSceneImage = nil then Exit;

  presentRect := ComputePresentRect();
  Inc(FPresentCount);

  if ATargetDrawable <> 0 then
    target := ATargetDrawable
  else if FOverlayWindow <> 0 then
    target := FOverlayWindow
  else
    target := FRootWindow;

  if FConn <> nil then
  begin
    EnsureGC();
    UploadRect(presentRect, target);
    xcb_flush(FConn);
  end;

  ClearDirty();
  FStructuralChange := False;
end;

procedure TXCBCompositor.Resize(const AWidth, AHeight: Integer);
var
  newW, newH: Integer;
begin
  newW := Max(1, AWidth);
  newH := Max(1, AHeight);
  if (FScreenWidth = newW) and (FScreenHeight = newH) then Exit;

  FScreenWidth := newW;
  FScreenHeight := newH;

  if FSceneCanvas <> nil then
  begin
    FSceneCanvas.Free();
    FSceneCanvas := nil;
  end;
  if FSceneImage <> nil then
  begin
    FSceneImage.Free();
    FSceneImage := nil;
  end;

  FSceneImage := TFloriaImage.Create(FScreenWidth, FScreenHeight);
  FSceneImage.Clear(FBgR, FBgG, FBgB, FBgA);
  FSceneCanvas := TFloriaCanvasAgg.Create(FSceneImage);

  // New backing image and new dimensions: nothing from the previous frame can be
  // reused.
  Invalidate();
end;

end.
