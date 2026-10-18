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
  // Represents a managed redirected top-level client window within the compositor scene.
  TXCBCompositedWindow = class
  private
    FCompositor     : TXCBCompositor;
    FWindow         : xcb_window_t;
    FFrameWindow    : xcb_window_t;
    FPixmap         : xcb_pixmap_t;
    FDamage         : xcb_damage_damage_t;
    FFrameDamage    : xcb_damage_damage_t;
    FGeometry       : TXCBRect;
    FOpacity        : Single;
    FShadowConfig   : TXCBWindowShadowConfig;
    FHasBackdropBlur: Boolean;
    FBlurRadius     : Integer;
    FCornerRadius   : Integer;
    FBottomCornerRadius: Integer;
    FIsDirty        : Boolean;
    FIsVisible      : Boolean;
    FImage          : TFloriaImage;
    FHasAlphaChannel: Boolean;
  public
    constructor Create(const ACompositor: TXCBCompositor; const AWindow: xcb_window_t;
                       const AGeometry: TXCBRect; const AFrame: xcb_window_t = 0);
    destructor Destroy(); override;

    procedure UpdateGeometry(const AX, AY, AWidth, AHeight: Integer);
    procedure UpdatePixmap();
    procedure FetchImage();
    procedure MarkDamaged();
    procedure ClearDamage();

    property Window         : xcb_window_t           read FWindow;
    property FrameWindow    : xcb_window_t           read FFrameWindow write FFrameWindow;
    property Pixmap         : xcb_pixmap_t           read FPixmap;
    property Damage         : xcb_damage_damage_t    read FDamage;
    property Geometry       : TXCBRect               read FGeometry write FGeometry;
    property Opacity        : Single                 read FOpacity write FOpacity;
    property ShadowConfig   : TXCBWindowShadowConfig read FShadowConfig write FShadowConfig;
    property HasBackdropBlur: Boolean                read FHasBackdropBlur write FHasBackdropBlur;
    property BlurRadius        : Integer                read FBlurRadius write FBlurRadius;
    property CornerRadius      : Integer                read FCornerRadius write FCornerRadius;
    property BottomCornerRadius: Integer                read FBottomCornerRadius write FBottomCornerRadius;
    property IsDirty           : Boolean                read FIsDirty write FIsDirty;
    property IsVisible      : Boolean                read FIsVisible write FIsVisible;
    property Image          : TFloriaImage           read FImage write FImage;
    property HasAlphaChannel: Boolean                read FHasAlphaChannel write FHasAlphaChannel;
  end;

  // Scene paint notification delegate
  TXCBCompositorPaintEvent = procedure(ASender: TObject; ACanvas: TFloriaCanvasAgg; const ASceneRect: TXCBRect) of object;

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

    function QueryExtensions(): Boolean;
    procedure EnsureGC();
  public
    constructor Create(AConn: Pxcb_connection_t; const ARoot: xcb_window_t;
                       const AWidth: Integer = 1920; const AHeight: Integer = 1080);
    destructor Destroy(); override;

    function EnableCompositing(): Boolean;
    procedure DisableCompositing();

    function RegisterWindow(const AWindow: xcb_window_t; const AGeometry: TXCBRect;
                            const AFrame: xcb_window_t = 0): TXCBCompositedWindow;
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
  end;

implementation

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
                                       const AGeometry: TXCBRect; const AFrame: xcb_window_t);
var
  geomCookie: xcb_get_geometry_cookie_t;
  geomReply: Pxcb_get_geometry_reply_t;
begin
  inherited Create();
  FCompositor := ACompositor;
  FWindow := AWindow;
  FFrameWindow := AFrame;
  FGeometry := AGeometry;
  FOpacity := 1.0;
  FShadowConfig := TXCBWindowShadowConfig.Create(True, 12, 1, 0.22);
  FHasBackdropBlur := False;
  FBlurRadius := 15;
  FCornerRadius := 10;
  FBottomCornerRadius := 10;
  FIsDirty := True;
  FIsVisible := True;
  FHasAlphaChannel := False;
  FPixmap := 0;
  FDamage := 0;
  FFrameDamage := 0;
  FImage := nil;

  if (FCompositor <> nil) and (FCompositor.Connection <> nil) and (FWindow <> 0) then
  begin
    // Check window visual depth to determine if window has a native 32-bit alpha channel
    geomCookie := xcb_get_geometry(FCompositor.Connection, FWindow);
    geomReply := xcb_get_geometry_reply(FCompositor.Connection, geomCookie, nil);
    if geomReply <> nil then
    begin
      FHasAlphaChannel := (geomReply^.depth = 32);
      xcb_free(geomReply);
    end;

    // Create Damage tracking object
    FDamage := xcb_generate_id(FCompositor.Connection);
    xcb_damage_create(FCompositor.Connection, FDamage, FWindow, XCB_DAMAGE_REPORT_LEVEL_NON_EMPTY);

    if (FFrameWindow <> 0) and (FFrameWindow <> FWindow) then
    begin
      FFrameDamage := xcb_generate_id(FCompositor.Connection);
      xcb_damage_create(FCompositor.Connection, FFrameDamage, FFrameWindow, XCB_DAMAGE_REPORT_LEVEL_NON_EMPTY);
    end;

    // Create named window pixmap
    UpdatePixmap();
  end;
end;

destructor TXCBCompositedWindow.Destroy();
begin
  if (FCompositor <> nil) and (FCompositor.Connection <> nil) then
  begin
    if FFrameDamage <> 0 then
    begin
      xcb_damage_destroy(FCompositor.Connection, FFrameDamage);
      FFrameDamage := 0;
    end;
    if FDamage <> 0 then
    begin
      xcb_damage_destroy(FCompositor.Connection, FDamage);
      FDamage := 0;
    end;
    if FPixmap <> 0 then
    begin
      xcb_free_pixmap(FCompositor.Connection, FPixmap);
      FPixmap := 0;
    end;
  end;

  if FImage <> nil then
  begin
    FImage.Free();
    FImage := nil;
  end;

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
    UpdatePixmap();
    FIsDirty := True;
  end;
end;

procedure TXCBCompositedWindow.UpdatePixmap();
begin
  if (FCompositor = nil) or (FCompositor.Connection = nil) or (FWindow = 0) then Exit;

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
end;

procedure TXCBCompositedWindow.FetchImage();
var
  cookie: xcb_get_image_cookie_t;
  reply: Pxcb_get_image_reply_t;
  rawBytes: PByte;
  targetW, targetH: Integer;
  x, y: Integer;
  srcRow, dstRow: PByte;
  rowBytes: Integer;
begin
  if (FCompositor = nil) or (FCompositor.Connection = nil) or (FPixmap = 0) then Exit;
  targetW := FGeometry.Width;
  targetH := FGeometry.Height;
  if (targetW <= 0) or (targetH <= 0) then Exit;

  cookie := xcb_get_image(FCompositor.Connection, XCB_IMAGE_FORMAT_Z_PIXMAP, FPixmap,
                          0, 0, targetW, targetH, Cardinal($FFFFFFFF));
  reply := xcb_get_image_reply(FCompositor.Connection, cookie, nil);
  if reply = nil then Exit;

  try
    rawBytes := xcb_get_image_data(reply);
    if rawBytes = nil then Exit;

    if (FImage = nil) or (FImage.Width <> targetW) or (FImage.Height <> targetH) then
    begin
      if FImage <> nil then FImage.Free();
      FImage := TFloriaImage.Create(targetW, targetH);
    end;

    rowBytes := targetW * 4;
    for y := 0 to targetH - 1 do
    begin
      srcRow := rawBytes + (y * rowBytes);
      dstRow := PByte(FImage.Scanline[y]);
      if FHasAlphaChannel then
        Move(srcRow^, dstRow^, rowBytes)
      else
      begin
        for x := 0 to targetW - 1 do
          PDWord(dstRow + (x * 4))^ := PDWord(srcRow + (x * 4))^ or Cardinal($FF000000);
      end;
    end;

    FIsDirty := False;
  finally
    xcb_free(reply);
  end;
end;

procedure TXCBCompositedWindow.MarkDamaged();
begin
  FIsDirty := True;
end;

procedure TXCBCompositedWindow.ClearDamage();
begin
  if (FCompositor <> nil) and (FCompositor.Connection <> nil) then
  begin
    if FDamage <> 0 then
      xcb_damage_subtract(FCompositor.Connection, FDamage, 0, 0);
    if FFrameDamage <> 0 then
      xcb_damage_subtract(FCompositor.Connection, FFrameDamage, 0, 0);
  end;
  FIsDirty := False;
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

  // Query Damage extension
  dmgCookie := xcb_damage_query_version(FConn, 1, 1);
  dmgReply := xcb_damage_query_version_reply(FConn, dmgCookie, nil);
  if dmgReply <> nil then
  begin
    FHasDamage := True;
    FDamageMajor := dmgReply^.major_version;
    FDamageMinor := dmgReply^.minor_version;
    xcb_free(dmgReply);

    extReply := xcb_get_extension_data(FConn, @xcb_damage_id);
    if (extReply <> nil) and (extReply^.present <> 0) then
    begin
      FDamageEventBase := extReply^.first_event;
      FDamageErrorBase := extReply^.first_error;
    end;
  end;

  Result := FHasComposite and FHasDamage;
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
                                      const AFrame: xcb_window_t): TXCBCompositedWindow;
begin
  Result := FindWindow(AWindow);
  if Result <> nil then
  begin
    Result.UpdateGeometry(AGeometry.X, AGeometry.Y, AGeometry.Width, AGeometry.Height);
    Result.FrameWindow := AFrame;
    Exit;
  end;

  Result := TXCBCompositedWindow.Create(Self, AWindow, AGeometry, AFrame);
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
    if (w.Window = AWindow) or (w.FrameWindow = AWindow) then
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
    if (w.Window = AWindow) or (w.FrameWindow = AWindow) then
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
  if w <> nil then
  begin
    w.MarkDamaged();
    Result := True;
  end;
end;

function TXCBCompositor.IsDamageNotify(const AEvent: Pxcb_generic_event_t): Boolean;
begin
  Result := False;
  if (AEvent = nil) or not FHasDamage then Exit;
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
end;

procedure TXCBCompositor.SetBackgroundColor(const R, G, B: Byte; const A: Byte);
begin
  FBgR := R;
  FBgG := G;
  FBgB := B;
  FBgA := A;
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
begin
  if (FSceneImage = nil) or (FSceneCanvas = nil) then Exit;

  // 1. Render Wallpaper or Solid Desktop Background
  if FWallpaper <> nil then
    FSceneCanvas.DrawImage(0, 0, FWallpaper)
  else
    FSceneImage.Clear(FBgR, FBgG, FBgB, FBgA);

  rect := TXCBRect.Create(0, 0, FScreenWidth, FScreenHeight);
  if Assigned(FOnBeforeRender) then
    FOnBeforeRender(Self, FSceneCanvas, rect);

  // 2. Render Windows in stacking order (bottom to top)
  for i := 0 to FWindows.Count - 1 do
  begin
    w := TXCBCompositedWindow(FWindows[i]);
    if not w.IsVisible or (w.Geometry.Width <= 0) or (w.Geometry.Height <= 0) then
      Continue;

    // Fetch damaged/dirty client pixmap pixels
    if w.IsDirty and (w.Pixmap <> 0) then
    begin
      w.FetchImage();
      w.ClearDamage();
    end;

    // A. Render Soft Gaussian Drop Shadow via AggPas
    if w.ShadowConfig.Enabled then
    begin
      FSceneCanvas.DrawShadow(w.Geometry.X, w.Geometry.Y,
                              w.Geometry.Width, w.Geometry.Height,
                              w.CornerRadius,
                              0, w.ShadowConfig.OffsetY,
                              w.ShadowConfig.Radius,
                              0.0, 0.0, 0.0, w.ShadowConfig.Opacity);
    end;

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

    // C. Render Window Surface (Client Image) with Opacity and Rounded Corners
    if w.Image <> nil then
    begin
      if ((w.CornerRadius > 0) or (w.BottomCornerRadius > 0)) and
         (w.Geometry.Width > Max(w.CornerRadius, w.BottomCornerRadius) * 2) and
         (w.Geometry.Height > Max(w.CornerRadius, w.BottomCornerRadius) * 2) then
      begin
        FSceneCanvas.PushClipRoundedRect(w.Geometry.X, w.Geometry.Y, w.Geometry.Width, w.Geometry.Height,
                                         w.CornerRadius, w.BottomCornerRadius);
        FSceneCanvas.DrawImage(w.Geometry.X, w.Geometry.Y, w.Image, w.Opacity);
        FSceneCanvas.PopClipRoundedRect();
      end
      else
        FSceneCanvas.DrawImage(w.Geometry.X, w.Geometry.Y, w.Image, w.Opacity);
    end;
  end;

  if Assigned(FOnAfterRender) then
    FOnAfterRender(Self, FSceneCanvas, rect);
end;

procedure TXCBCompositor.PresentToScreen(const ATargetDrawable: xcb_drawable_t);
var
  target: xcb_drawable_t;
  dataLen: Cardinal;
begin
  if (FConn = nil) or (FSceneImage = nil) then Exit;

  if ATargetDrawable <> 0 then
    target := ATargetDrawable
  else if FOverlayWindow <> 0 then
    target := FOverlayWindow
  else
    target := FRootWindow;

  EnsureGC();
  dataLen := Cardinal(FScreenWidth * FScreenHeight * 4);

  xcb_put_image(FConn, XCB_IMAGE_FORMAT_Z_PIXMAP, target, FGC,
                FScreenWidth, FScreenHeight, 0, 0, 0, 24,
                dataLen, PByte(FSceneImage.Data));
  xcb_flush(FConn);
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
end;

end.
