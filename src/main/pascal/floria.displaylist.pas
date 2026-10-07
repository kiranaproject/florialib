unit Floria.DisplayList;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  Classes, SysUtils, Math,
  agg_basics, agg_color, agg_trans_affine, agg_path_storage,
  Floria.Image.Core,
  Floria.Font,
  Floria.Canvas.Blend,
  Floria.Canvas.Filter,
  Floria.Canvas.Agg,
  Floria.SVG.Types,
  Floria.SVG.DOM,
  Floria.Path.Clipper.Core,
  Floria.Path.Ops,
  Floria.Text.Paragraph;

type
  // Forward declarations
  TFloriaPicture = class;
  TFloriaPictureRecorder = class;

  // ---------------------------------------------------------------------------
  // 2D Affine Transformation Matrix
  // ---------------------------------------------------------------------------
  // Represents the 2D affine transformation:
  //   [ x' ]   [ A  C  Tx ] [ x ]
  //   [ y' ] = [ B  D  Ty ] [ y ]
  //   [ 1  ]   [ 0  0  1  ] [ 1 ]
  // ---------------------------------------------------------------------------
  TFloriaMatrix2D = record
    A, B, C, D: Double;
    Tx, Ty    : Double;

    class function Identity(): TFloriaMatrix2D; static;
    class function Translation(DX, DY: Double): TFloriaMatrix2D; static;
    class function Scaling(SX, SY: Double): TFloriaMatrix2D; static;
    class function Rotation(AngleRad: Double): TFloriaMatrix2D; static;
    class function RotationDeg(AngleDeg: Double; CX: Double = 0.0; CY: Double = 0.0): TFloriaMatrix2D; static;

    function Multiply(const Other: TFloriaMatrix2D): TFloriaMatrix2D;
    function TransformPoint(const Pt: TPointD): TPointD;
    function TransformRect(const Rect: TRectD): TRectD;
    function IsIdentity(): Boolean;
    function IsTranslationOnly(): Boolean;
    function Invert(out Inv: TFloriaMatrix2D): Boolean;
    function Determinant(): Double;
  end;

  // ---------------------------------------------------------------------------
  // UI Display Types & Parameters
  // ---------------------------------------------------------------------------
  TFloriaGradientStop = record
    Offset: Double;      // 0.0 .. 1.0
    Color : TBgraPixel;
  end;

  TFloriaGradientStopArray = array of TFloriaGradientStop;

  TFloriaShadowParams = record
    OffsetX     : Double;
    OffsetY     : Double;
    BlurRadius  : Double;
    SpreadRadius: Double;
    Color       : TBgraPixel;
    Inset       : Boolean;
  end;

  TFloriaBorderSide = record
    Width: Double;
    Color: TBgraPixel;
  end;

  TFloriaBorderParams = record
    Top   : TFloriaBorderSide;
    Right : TFloriaBorderSide;
    Bottom: TFloriaBorderSide;
    Left  : TFloriaBorderSide;
    RadiusX, RadiusY: Double;
  end;

  // ---------------------------------------------------------------------------
  // Display Operation Types
  // ---------------------------------------------------------------------------
  TFloriaDisplayOpType = (
    dopSave,
    dopRestore,
    dopSetTransform,
    dopTranslate,
    dopScale,
    dopRotate,
    dopPushAlpha,
    dopPopAlpha,
    dopSetBlendMode,
    dopPushClipRect,
    dopPushClipRoundedRect,
    dopPopClip,
    dopClear,
    dopDrawRect,
    dopDrawRoundedRect,
    dopDrawCircle,
    dopDrawLine,
    dopDrawPath,
    dopDrawShadow,
    dopDrawBorder,
    dopDrawLinearGradient,
    dopDrawText,
    dopDrawParagraph,
    dopDrawImage,
    dopDrawPicture,
    dopSaveLayer,
    dopRestoreLayer
  );

  // ---------------------------------------------------------------------------
  // Single Recorded Display Operation Record
  // ---------------------------------------------------------------------------
  TFloriaDisplayOp = record
    OpType        : TFloriaDisplayOpType;
    Matrix        : TFloriaMatrix2D;
    Bounds        : TRectD;  // Conservative visual bounding box in root picture space

    // Primitives & Geometry
    Rect          : TRectD;
    Pt1, Pt2      : TPointD;
    RadiusX       : Double;
    RadiusY       : Double;
    Radius        : Double;
    StrokeWidth   : Double;
    HasFill       : Boolean;
    HasStroke     : Boolean;
    FillColor     : TBgraPixel;
    StrokeColor   : TBgraPixel;

    // State & Modes
    Alpha         : Double;
    BlendMode     : TFloriaBlendMode;
    AntiAlias     : Boolean;
    FillRule      : TFillRule;

    // High-Level UI Elements
    ShadowParams  : TFloriaShadowParams;
    BorderParams  : TFloriaBorderParams;
    GradientStops : TFloriaGradientStopArray;
    GradAngle     : Double;
    GradP1, GradP2: TPointD;

    // Typography
    Text          : string;
    Font          : TFloriaFont;
    FontSize      : Double;

    // Resources & References
    Path          : TFloriaPath;
    Paragraph     : TFloriaParagraph;
    OwnsParagraph : Boolean;
    Image         : TFloriaImage;
    Picture       : TFloriaPicture;
    Filter        : TFloriaImageFilter;
    SrcRect       : TRectD;
    DstRect       : TRectD;
    Opacity       : Double;
  end;

  TFloriaDisplayOpArray = array of TFloriaDisplayOp;

  // ---------------------------------------------------------------------------
  // IFloriaDisplayListReceiver Interface
  // ---------------------------------------------------------------------------
  // Allows visitors, GPU compilers, scene graph builders, or analyzers
  // to intercept each recorded command.
  // ---------------------------------------------------------------------------
  IFloriaDisplayListReceiver = interface
    ['{7A88A1F1-23B6-4E15-9BE2-43645A95CE01}']
    procedure OnSave();
    procedure OnRestore();
    procedure OnTransform(const AMatrix: TFloriaMatrix2D);
    procedure OnPushClipRect(const ARect: TRectD; AAntiAlias: Boolean);
    procedure OnPushClipRoundedRect(const ARect: TRectD; ARadiusX, ARadiusY: Double; AAntiAlias: Boolean);
    procedure OnPopClip();
    procedure OnSetAlpha(AAlpha: Double);
    procedure OnSetBlendMode(AMode: TFloriaBlendMode);
    procedure OnClear(const AColor: TBgraPixel);
    procedure OnDrawRect(const ARect: TRectD; const AFillColor, AStrokeColor: TBgraPixel; AStrokeWidth: Double);
    procedure OnDrawRoundedRect(const ARect: TRectD; ARadiusX, ARadiusY: Double; const AFillColor, AStrokeColor: TBgraPixel; AStrokeWidth: Double);
    procedure OnDrawCircle(ACenterX, ACenterY, ARadius: Double; const AFillColor, AStrokeColor: TBgraPixel; AStrokeWidth: Double);
    procedure OnDrawLine(AX1, AY1, AX2, AY2: Double; const AColor: TBgraPixel; AStrokeWidth: Double);
    procedure OnDrawPath(APath: TFloriaPath; const AFillColor, AStrokeColor: TBgraPixel; AStrokeWidth: Double; AFillRule: TFillRule);
    procedure OnDrawShadow(const ARect: TRectD; ARadius: Double; const AParams: TFloriaShadowParams);
    procedure OnDrawBorder(const ARect: TRectD; const AParams: TFloriaBorderParams);
    procedure OnDrawLinearGradient(const ARect: TRectD; const AP1, AP2: TPointD; const AStops: TFloriaGradientStopArray);
    procedure OnDrawText(const AText: string; AX, AY: Double; AFont: TFloriaFont; AFontSize: Double; const AColor: TBgraPixel);
    procedure OnDrawParagraph(AParagraph: TFloriaParagraph; AX, AY: Double);
    procedure OnDrawImage(AImage: TFloriaImage; const ADstRect, ASrcRect: TRectD; AOpacity: Double);
    procedure OnDrawPicture(APicture: TFloriaPicture; AX, AY: Double);
    procedure OnSaveLayer(const ABounds: TRectD; AOpacity: Double; AFilter: TFloriaImageFilter; ABlendMode: TFloriaBlendMode);
    procedure OnRestoreLayer();
  end;

  // ---------------------------------------------------------------------------
  // Base Receiver Adapter (Virtual stubs for convenience, non-refcounted)
  // ---------------------------------------------------------------------------
  TFloriaDisplayListReceiver = class(TObject, IFloriaDisplayListReceiver)
  protected
    function QueryInterface({$IFDEF FPC_HAS_CONSTREF}constref{$ELSE}const{$ENDIF} IID: TGUID; out Obj): HResult; virtual; {$IFNDEF WINDOWS}cdecl{$ELSE}stdcall{$ENDIF};
    function _AddRef(): LongInt; virtual; {$IFNDEF WINDOWS}cdecl{$ELSE}stdcall{$ENDIF};
    function _Release(): LongInt; virtual; {$IFNDEF WINDOWS}cdecl{$ELSE}stdcall{$ENDIF};
  public
    procedure OnSave(); virtual;
    procedure OnRestore(); virtual;
    procedure OnTransform(const AMatrix: TFloriaMatrix2D); virtual;
    procedure OnPushClipRect(const ARect: TRectD; AAntiAlias: Boolean); virtual;
    procedure OnPushClipRoundedRect(const ARect: TRectD; ARadiusX, ARadiusY: Double; AAntiAlias: Boolean); virtual;
    procedure OnPopClip(); virtual;
    procedure OnSetAlpha(AAlpha: Double); virtual;
    procedure OnSetBlendMode(AMode: TFloriaBlendMode); virtual;
    procedure OnClear(const AColor: TBgraPixel); virtual;
    procedure OnDrawRect(const ARect: TRectD; const AFillColor, AStrokeColor: TBgraPixel; AStrokeWidth: Double); virtual;
    procedure OnDrawRoundedRect(const ARect: TRectD; ARadiusX, ARadiusY: Double; const AFillColor, AStrokeColor: TBgraPixel; AStrokeWidth: Double); virtual;
    procedure OnDrawCircle(ACenterX, ACenterY, ARadius: Double; const AFillColor, AStrokeColor: TBgraPixel; AStrokeWidth: Double); virtual;
    procedure OnDrawLine(AX1, AY1, AX2, AY2: Double; const AColor: TBgraPixel; AStrokeWidth: Double); virtual;
    procedure OnDrawPath(APath: TFloriaPath; const AFillColor, AStrokeColor: TBgraPixel; AStrokeWidth: Double; AFillRule: TFillRule); virtual;
    procedure OnDrawShadow(const ARect: TRectD; ARadius: Double; const AParams: TFloriaShadowParams); virtual;
    procedure OnDrawBorder(const ARect: TRectD; const AParams: TFloriaBorderParams); virtual;
    procedure OnDrawLinearGradient(const ARect: TRectD; const AP1, AP2: TPointD; const AStops: TFloriaGradientStopArray); virtual;
    procedure OnDrawText(const AText: string; AX, AY: Double; AFont: TFloriaFont; AFontSize: Double; const AColor: TBgraPixel); virtual;
    procedure OnDrawParagraph(AParagraph: TFloriaParagraph; AX, AY: Double); virtual;
    procedure OnDrawImage(AImage: TFloriaImage; const ADstRect, ASrcRect: TRectD; AOpacity: Double); virtual;
    procedure OnDrawPicture(APicture: TFloriaPicture; AX, AY: Double); virtual;
    procedure OnSaveLayer(const ABounds: TRectD; AOpacity: Double; AFilter: TFloriaImageFilter; ABlendMode: TFloriaBlendMode); virtual;
    procedure OnRestoreLayer(); virtual;
  end;

  // ---------------------------------------------------------------------------
  // TFloriaPicture / TFloriaDisplayList (Retained Display List Container)
  // ---------------------------------------------------------------------------
  TFloriaPicture = class
  private
    FWidth      : Double;
    FHeight     : Double;
    FCullRect   : TRectD;
    FOperations : TFloriaDisplayOpArray;
    FOpCount    : Integer;

    function GetOp(AIndex: Integer): TFloriaDisplayOp;
  public
    constructor Create(AWidth, AHeight: Double; const ACullRect: TRectD;
                       const AOps: TFloriaDisplayOpArray; ACount: Integer);
    destructor Destroy(); override;

    function Clone(): TFloriaPicture;
    procedure Playback(ACanvas: TFloriaCanvasAgg); overload;
    procedure Playback(ACanvas: TFloriaCanvasAgg; const AClipBounds: TRectD); overload;
    procedure Playback(ACanvas: TFloriaCanvasAgg; const AClipBounds: TRectD; const AInitialMatrix: TFloriaMatrix2D); overload;
    procedure Playback(AReceiver: IFloriaDisplayListReceiver); overload;

    function Dump(): string;

    property Width     : Double read FWidth;
    property Height    : Double read FHeight;
    property CullRect  : TRectD read FCullRect;
    property OpCount   : Integer read FOpCount;
    property Op[Index: Integer]: TFloriaDisplayOp read GetOp;
  end;

  // Backward-compatibility and WebRender-aligned aliases
  TFloriaDisplayList = TFloriaPicture;

  // ---------------------------------------------------------------------------
  // TFloriaPictureRecorder (Display List Builder)
  // ---------------------------------------------------------------------------
  TFloriaPictureRecorder = class
  private
    FRecording    : Boolean;
    FInitialBounds: TRectD;
    FCullRect     : TRectD;
    FHasContent   : Boolean;

    FOperations   : TFloriaDisplayOpArray;
    FOpCount      : Integer;
    FCapacity     : Integer;

    FCurrentMatrix: TFloriaMatrix2D;
    FMatrixStack  : array of TFloriaMatrix2D;
    FMatrixDepth  : Integer;

    procedure EnsureCapacity(AAdditional: Integer = 1);
    procedure AppendOp(const AOp: TFloriaDisplayOp);
    procedure UpdateCullRect(const ABounds: TRectD);
    function TransformCurrent(const ARect: TRectD): TRectD;
  public
    constructor Create();
    destructor Destroy(); override;

    procedure BeginRecording(const ABounds: TRectD); overload;
    procedure BeginRecording(AWidth, AHeight: Double); overload;
    function EndRecording(): TFloriaPicture;

    // --- Canvas State & Transforms ---
    procedure Save();
    procedure Restore();
    procedure SetTransform(const AMatrix: TFloriaMatrix2D);
    procedure Translate(DX, DY: Double);
    procedure Scale(SX, SY: Double);
    procedure Rotate(AngleDeg: Double; CX: Double = 0.0; CY: Double = 0.0);
    procedure PushAlpha(AAlpha: Double);
    procedure PopAlpha();
    procedure SetBlendMode(AMode: TFloriaBlendMode);

    // --- Clipping ---
    procedure PushClipRect(const ARect: TRectD; AAntiAlias: Boolean = True); overload;
    procedure PushClipRect(X, Y, W, H: Double; AAntiAlias: Boolean = True); overload;
    procedure PushClipRoundedRect(const ARect: TRectD; ARadiusX, ARadiusY: Double; AAntiAlias: Boolean = True); overload;
    procedure PushClipRoundedRect(X, Y, W, H, ARadius: Double; AAntiAlias: Boolean = True); overload;
    procedure PopClip();

    // --- Shapes & Fills ---
    procedure Clear(const AColor: TBgraPixel); overload;
    procedure Clear(R, G, B: Double; A: Double = 1.0); overload;

    procedure DrawRect(const ARect: TRectD; const AFillColor: TBgraPixel); overload;
    procedure DrawRect(const ARect: TRectD; const AFillColor, AStrokeColor: TBgraPixel; AStrokeWidth: Double); overload;
    procedure DrawRect(X, Y, W, H: Double; const AFillColor: TBgraPixel); overload;

    procedure DrawRoundedRect(const ARect: TRectD; ARadiusX, ARadiusY: Double; const AFillColor: TBgraPixel); overload;
    procedure DrawRoundedRect(const ARect: TRectD; ARadiusX, ARadiusY: Double; const AFillColor, AStrokeColor: TBgraPixel; AStrokeWidth: Double); overload;
    procedure DrawRoundedRect(X, Y, W, H, ARadius: Double; const AFillColor: TBgraPixel); overload;
    procedure DrawRoundedRectOutline(X, Y, W, H, ARadius, AStrokeWidth: Double; const AStrokeColor: TBgraPixel);

    procedure DrawCircle(ACenterX, ACenterY, ARadius: Double; const AFillColor: TBgraPixel); overload;
    procedure DrawCircle(ACenterX, ACenterY, ARadius: Double; const AFillColor, AStrokeColor: TBgraPixel; AStrokeWidth: Double); overload;

    procedure DrawLine(AX1, AY1, AX2, AY2: Double; const AColor: TBgraPixel; AStrokeWidth: Double = 1.0);

    procedure DrawPath(APath: TFloriaPath; const AFillColor: TBgraPixel; AFillRule: TFillRule = frNonZero); overload;
    procedure DrawPath(APath: TFloriaPath; const AFillColor, AStrokeColor: TBgraPixel; AStrokeWidth: Double; AFillRule: TFillRule = frNonZero); overload;

    // --- Semantic UI Elements ---
    procedure DrawShadow(const ARect: TRectD; ARadius: Double; const AParams: TFloriaShadowParams); overload;
    procedure DrawShadow(X, Y, W, H, ARadius, AOffsetX, AOffsetY, ABlurRadius: Double; const AColor: TBgraPixel); overload;
    procedure DrawShadow(X, Y, W, H, ARadius, AOffsetX, AOffsetY, ABlurRadius, ASpreadRadius: Double; const AColor: TBgraPixel; AInset: Boolean = False); overload;

    procedure DrawBorder(const ARect: TRectD; const ATop, ARight, ABottom, ALeft: TFloriaBorderSide; ARadiusX: Double = 0.0; ARadiusY: Double = 0.0); overload;
    procedure DrawBorder(const ARect: TRectD; ABorderWidth: Double; const ABorderColor: TBgraPixel; ARadius: Double = 0.0); overload;
    procedure DrawBorder(X, Y, W, H, ABorderWidth: Double; const ABorderColor: TBgraPixel; ARadius: Double = 0.0); overload;

    procedure DrawLinearGradient(const ARect: TRectD; const AP1, AP2: TPointD; const AStops: array of TFloriaGradientStop); overload;
    procedure DrawLinearGradient(const ARect: TRectD; AAngleDeg: Double; const AStops: array of TFloriaGradientStop); overload;

    // --- Typography ---
    procedure DrawText(const AText: string; AX, AY: Double; AFont: TFloriaFont; const AColor: TBgraPixel); overload;
    procedure DrawText(const AText: string; AX, AY: Double; AFontSize: Double; const AColor: TBgraPixel); overload;
    procedure DrawParagraph(AParagraph: TFloriaParagraph; AX, AY: Double; AOwnsParagraph: Boolean = False);

    // --- Images & Sub-Pictures ---
    procedure DrawImage(AImage: TFloriaImage; AX, AY: Double; AOpacity: Double = 1.0); overload;
    procedure DrawImage(AImage: TFloriaImage; const ADstRect: TRectD; AOpacity: Double = 1.0); overload;
    procedure DrawImage(AImage: TFloriaImage; const ADstRect, ASrcRect: TRectD; AOpacity: Double = 1.0); overload;

    procedure DrawPicture(APicture: TFloriaPicture; AX, AY: Double);

    // --- Layer Compositing ---
    procedure SaveLayer(const ABounds: TRectD; AOpacity: Double = 1.0; AFilter: TFloriaImageFilter = nil; ABlendMode: TFloriaBlendMode = fbmSrcOver);
    procedure RestoreLayer();

    property IsRecording  : Boolean read FRecording;
    property CurrentMatrix: TFloriaMatrix2D read FCurrentMatrix;
  end;

  TFloriaDisplayListBuilder = TFloriaPictureRecorder;

// Helper constructors
function BgraPixel(AR, AG, AB: Byte; AA: Byte = 255): TBgraPixel; inline;
function FloriaGradientStop(AOffset: Double; const AColor: TBgraPixel): TFloriaGradientStop;
function FloriaShadowParams(AOffX, AOffY, ABlur, ASpread: Double; const AColor: TBgraPixel; AInset: Boolean = False): TFloriaShadowParams;
function FloriaBorderSide(AWidth: Double; const AColor: TBgraPixel): TFloriaBorderSide;
function FloriaBorderParams(const ATop, ARight, ABottom, ALeft: TFloriaBorderSide; ARadiusX: Double = 0.0; ARadiusY: Double = 0.0): TFloriaBorderParams;

// Gradient interpolation helper
function FloriaInterpolateGradient(const AStops: TFloriaGradientStopArray; AT: Double): TBgraPixel;

implementation

// -----------------------------------------------------------------------------
// Helper Constructors
// -----------------------------------------------------------------------------
function BgraPixel(AR, AG, AB: Byte; AA: Byte = 255): TBgraPixel; inline;
begin
  Result := TBgraPixel.Create(AR, AG, AB, AA);
end;

function FloriaGradientStop(AOffset: Double; const AColor: TBgraPixel): TFloriaGradientStop;
begin
  Result.Offset := AOffset;
  Result.Color  := AColor;
end;

function FloriaShadowParams(AOffX, AOffY, ABlur, ASpread: Double; const AColor: TBgraPixel; AInset: Boolean = False): TFloriaShadowParams;
begin
  Result.OffsetX      := AOffX;
  Result.OffsetY      := AOffY;
  Result.BlurRadius   := ABlur;
  Result.SpreadRadius := ASpread;
  Result.Color        := AColor;
  Result.Inset        := AInset;
end;

function FloriaBorderSide(AWidth: Double; const AColor: TBgraPixel): TFloriaBorderSide;
begin
  Result.Width := AWidth;
  Result.Color := AColor;
end;

function FloriaBorderParams(const ATop, ARight, ABottom, ALeft: TFloriaBorderSide; ARadiusX: Double = 0.0; ARadiusY: Double = 0.0): TFloriaBorderParams;
begin
  Result.Top     := ATop;
  Result.Right   := ARight;
  Result.Bottom  := ABottom;
  Result.Left    := ALeft;
  Result.RadiusX := ARadiusX;
  Result.RadiusY := ARadiusY;
end;

function FloriaInterpolateGradient(const AStops: TFloriaGradientStopArray; AT: Double): TBgraPixel;
var
  I: Integer;
  S0, S1: TFloriaGradientStop;
  Factor: Double;
  R, G, B, A: Byte;
begin
  if Length(AStops) = 0 then
    Exit(BgraPixel(0, 0, 0, 0));
  if Length(AStops) = 1 then
    Exit(AStops[0].Color);

  if AT <= AStops[0].Offset then
    Exit(AStops[0].Color);
  if AT >= AStops[High(AStops)].Offset then
    Exit(AStops[High(AStops)].Color);

  for I := 0 to High(AStops) - 1 do
  begin
    if (AT >= AStops[I].Offset) and (AT <= AStops[I + 1].Offset) then
    begin
      S0 := AStops[I];
      S1 := AStops[I + 1];
      if Abs(S1.Offset - S0.Offset) < 1e-6 then
        Exit(S0.Color);

      Factor := (AT - S0.Offset) / (S1.Offset - S0.Offset);
      Factor := EnsureRange(Factor, 0.0, 1.0);

      B := Round(S0.Color.B + (S1.Color.B - S0.Color.B) * Factor);
      G := Round(S0.Color.G + (S1.Color.G - S0.Color.G) * Factor);
      R := Round(S0.Color.R + (S1.Color.R - S0.Color.R) * Factor);
      A := Round(S0.Color.A + (S1.Color.A - S0.Color.A) * Factor);
      Exit(BgraPixel(R, G, B, A));
    end;
  end;

  Result := AStops[High(AStops)].Color;
end;

// -----------------------------------------------------------------------------
// TFloriaMatrix2D Implementation
// -----------------------------------------------------------------------------
class function TFloriaMatrix2D.Identity(): TFloriaMatrix2D;
begin
  Result.A  := 1.0; Result.B  := 0.0;
  Result.C  := 0.0; Result.D  := 1.0;
  Result.Tx := 0.0; Result.Ty := 0.0;
end;

class function TFloriaMatrix2D.Translation(DX, DY: Double): TFloriaMatrix2D;
begin
  Result.A  := 1.0; Result.B  := 0.0;
  Result.C  := 0.0; Result.D  := 1.0;
  Result.Tx := DX;  Result.Ty := DY;
end;

class function TFloriaMatrix2D.Scaling(SX, SY: Double): TFloriaMatrix2D;
begin
  Result.A  := SX;  Result.B  := 0.0;
  Result.C  := 0.0; Result.D  := SY;
  Result.Tx := 0.0; Result.Ty := 0.0;
end;

class function TFloriaMatrix2D.Rotation(AngleRad: Double): TFloriaMatrix2D;
var
  SinV, CosV: Double;
begin
  SinCos(AngleRad, SinV, CosV);
  Result.A  := CosV;  Result.B  := SinV;
  Result.C  := -SinV; Result.D  := CosV;
  Result.Tx := 0.0;   Result.Ty := 0.0;
end;

class function TFloriaMatrix2D.RotationDeg(AngleDeg: Double; CX: Double = 0.0; CY: Double = 0.0): TFloriaMatrix2D;
var
  T1, R, T2: TFloriaMatrix2D;
begin
  if (CX = 0.0) and (CY = 0.0) then
    Exit(Rotation(AngleDeg * (Pi / 180.0)));

  T1 := Translation(-CX, -CY);
  R  := Rotation(AngleDeg * (Pi / 180.0));
  T2 := Translation(CX, CY);
  Result := T2.Multiply(R.Multiply(T1));
end;

function TFloriaMatrix2D.Multiply(const Other: TFloriaMatrix2D): TFloriaMatrix2D;
begin
  Result.A  := A * Other.A + C * Other.B;
  Result.B  := B * Other.A + D * Other.B;
  Result.C  := A * Other.C + C * Other.D;
  Result.D  := B * Other.C + D * Other.D;
  Result.Tx := A * Other.Tx + C * Other.Ty + Tx;
  Result.Ty := B * Other.Tx + D * Other.Ty + Ty;
end;

function TFloriaMatrix2D.TransformPoint(const Pt: TPointD): TPointD;
begin
  Result.X := A * Pt.X + C * Pt.Y + Tx;
  Result.Y := B * Pt.X + D * Pt.Y + Ty;
end;

function TFloriaMatrix2D.TransformRect(const Rect: TRectD): TRectD;
var
  P1, P2, P3, P4: TPointD;
  MinX, MaxX, MinY, MaxY: Double;
begin
  if IsTranslationOnly() then
    Exit(RectD(Rect.Left + Tx, Rect.Top + Ty, Rect.Right + Tx, Rect.Bottom + Ty));

  P1 := TransformPoint(PointD(Rect.Left, Rect.Top));
  P2 := TransformPoint(PointD(Rect.Right, Rect.Top));
  P3 := TransformPoint(PointD(Rect.Right, Rect.Bottom));
  P4 := TransformPoint(PointD(Rect.Left, Rect.Bottom));

  MinX := Min(Min(P1.X, P2.X), Min(P3.X, P4.X));
  MaxX := Max(Max(P1.X, P2.X), Max(P3.X, P4.X));
  MinY := Min(Min(P1.Y, P2.Y), Min(P3.Y, P4.Y));
  MaxY := Max(Max(P1.Y, P2.Y), Max(P3.Y, P4.Y));

  Result := RectD(MinX, MinY, MaxX, MaxY);
end;

function TFloriaMatrix2D.IsIdentity(): Boolean;
begin
  Result := (Abs(A - 1.0) < 1e-9) and (Abs(B) < 1e-9) and
            (Abs(C) < 1e-9) and (Abs(D - 1.0) < 1e-9) and
            (Abs(Tx) < 1e-9) and (Abs(Ty) < 1e-9);
end;

function TFloriaMatrix2D.IsTranslationOnly(): Boolean;
begin
  Result := (Abs(A - 1.0) < 1e-9) and (Abs(B) < 1e-9) and
            (Abs(C) < 1e-9) and (Abs(D - 1.0) < 1e-9);
end;

function TFloriaMatrix2D.Determinant(): Double;
begin
  Result := A * D - B * C;
end;

function TFloriaMatrix2D.Invert(out Inv: TFloriaMatrix2D): Boolean;
var
  Det: Double;
begin
  Det := Determinant();
  if Abs(Det) < 1e-12 then
  begin
    Inv := Identity();
    Exit(False);
  end;

  Inv.A  := D / Det;
  Inv.B  := -B / Det;
  Inv.C  := -C / Det;
  Inv.D  := A / Det;
  Inv.Tx := (C * Ty - D * Tx) / Det;
  Inv.Ty := (B * Tx - A * Ty) / Det;
  Result := True;
end;

// -----------------------------------------------------------------------------
// TFloriaDisplayListReceiver Base Adapter (Non-refcounted)
// -----------------------------------------------------------------------------
function TFloriaDisplayListReceiver.QueryInterface({$IFDEF FPC_HAS_CONSTREF}constref{$ELSE}const{$ENDIF} IID: TGUID; out Obj): HResult; {$IFNDEF WINDOWS}cdecl{$ELSE}stdcall{$ENDIF};
begin
  if GetInterface(IID, Obj) then
    Result := S_OK
  else
    Result := HResult($80004002); // E_NOINTERFACE
end;

function TFloriaDisplayListReceiver._AddRef(): LongInt; {$IFNDEF WINDOWS}cdecl{$ELSE}stdcall{$ENDIF};
begin
  Result := -1;
end;

function TFloriaDisplayListReceiver._Release(): LongInt; {$IFNDEF WINDOWS}cdecl{$ELSE}stdcall{$ENDIF};
begin
  Result := -1;
end;

procedure TFloriaDisplayListReceiver.OnSave(); begin end;
procedure TFloriaDisplayListReceiver.OnRestore(); begin end;
procedure TFloriaDisplayListReceiver.OnTransform(const AMatrix: TFloriaMatrix2D); begin end;
procedure TFloriaDisplayListReceiver.OnPushClipRect(const ARect: TRectD; AAntiAlias: Boolean); begin end;
procedure TFloriaDisplayListReceiver.OnPushClipRoundedRect(const ARect: TRectD; ARadiusX, ARadiusY: Double; AAntiAlias: Boolean); begin end;
procedure TFloriaDisplayListReceiver.OnPopClip(); begin end;
procedure TFloriaDisplayListReceiver.OnSetAlpha(AAlpha: Double); begin end;
procedure TFloriaDisplayListReceiver.OnSetBlendMode(AMode: TFloriaBlendMode); begin end;
procedure TFloriaDisplayListReceiver.OnClear(const AColor: TBgraPixel); begin end;
procedure TFloriaDisplayListReceiver.OnDrawRect(const ARect: TRectD; const AFillColor, AStrokeColor: TBgraPixel; AStrokeWidth: Double); begin end;
procedure TFloriaDisplayListReceiver.OnDrawRoundedRect(const ARect: TRectD; ARadiusX, ARadiusY: Double; const AFillColor, AStrokeColor: TBgraPixel; AStrokeWidth: Double); begin end;
procedure TFloriaDisplayListReceiver.OnDrawCircle(ACenterX, ACenterY, ARadius: Double; const AFillColor, AStrokeColor: TBgraPixel; AStrokeWidth: Double); begin end;
procedure TFloriaDisplayListReceiver.OnDrawLine(AX1, AY1, AX2, AY2: Double; const AColor: TBgraPixel; AStrokeWidth: Double); begin end;
procedure TFloriaDisplayListReceiver.OnDrawPath(APath: TFloriaPath; const AFillColor, AStrokeColor: TBgraPixel; AStrokeWidth: Double; AFillRule: TFillRule); begin end;
procedure TFloriaDisplayListReceiver.OnDrawShadow(const ARect: TRectD; ARadius: Double; const AParams: TFloriaShadowParams); begin end;
procedure TFloriaDisplayListReceiver.OnDrawBorder(const ARect: TRectD; const AParams: TFloriaBorderParams); begin end;
procedure TFloriaDisplayListReceiver.OnDrawLinearGradient(const ARect: TRectD; const AP1, AP2: TPointD; const AStops: TFloriaGradientStopArray); begin end;
procedure TFloriaDisplayListReceiver.OnDrawText(const AText: string; AX, AY: Double; AFont: TFloriaFont; AFontSize: Double; const AColor: TBgraPixel); begin end;
procedure TFloriaDisplayListReceiver.OnDrawParagraph(AParagraph: TFloriaParagraph; AX, AY: Double); begin end;
procedure TFloriaDisplayListReceiver.OnDrawImage(AImage: TFloriaImage; const ADstRect, ASrcRect: TRectD; AOpacity: Double); begin end;
procedure TFloriaDisplayListReceiver.OnDrawPicture(APicture: TFloriaPicture; AX, AY: Double); begin end;
procedure TFloriaDisplayListReceiver.OnSaveLayer(const ABounds: TRectD; AOpacity: Double; AFilter: TFloriaImageFilter; ABlendMode: TFloriaBlendMode); begin end;
procedure TFloriaDisplayListReceiver.OnRestoreLayer(); begin end;

// -----------------------------------------------------------------------------
// TFloriaPicture Implementation
// -----------------------------------------------------------------------------
constructor TFloriaPicture.Create(AWidth, AHeight: Double; const ACullRect: TRectD;
                                  const AOps: TFloriaDisplayOpArray; ACount: Integer);
var
  I: Integer;
begin
  inherited Create();
  FWidth    := AWidth;
  FHeight   := AHeight;
  FCullRect := ACullRect;
  FOpCount  := ACount;
  SetLength(FOperations, FOpCount);
  for I := 0 to FOpCount - 1 do
    FOperations[I] := AOps[I];
end;

destructor TFloriaPicture.Destroy();
var
  I: Integer;
begin
  for I := 0 to FOpCount - 1 do
  begin
    if Assigned(FOperations[I].Path) then
      FreeAndNil(FOperations[I].Path);
    if Assigned(FOperations[I].Paragraph) and FOperations[I].OwnsParagraph then
      FreeAndNil(FOperations[I].Paragraph);
    if Assigned(FOperations[I].Picture) then
      FreeAndNil(FOperations[I].Picture);
    SetLength(FOperations[I].GradientStops, 0);
  end;
  SetLength(FOperations, 0);
  inherited Destroy();
end;

function TFloriaPicture.GetOp(AIndex: Integer): TFloriaDisplayOp;
begin
  if (AIndex < 0) or (AIndex >= FOpCount) then
    raise Exception.CreateFmt('TFloriaPicture.GetOp: Index %d out of bounds (0..%d)', [AIndex, FOpCount - 1]);
  Result := FOperations[AIndex];
end;

function TFloriaPicture.Clone(): TFloriaPicture;
var
  ClonedOps: TFloriaDisplayOpArray;
  I, J: Integer;
begin
  SetLength(ClonedOps, FOpCount);
  for I := 0 to FOpCount - 1 do
  begin
    ClonedOps[I] := FOperations[I];
    if Assigned(FOperations[I].Path) then
      ClonedOps[I].Path := FOperations[I].Path.Clone();
    if Assigned(FOperations[I].Picture) then
      ClonedOps[I].Picture := FOperations[I].Picture.Clone();
    if Length(FOperations[I].GradientStops) > 0 then
    begin
      SetLength(ClonedOps[I].GradientStops, Length(FOperations[I].GradientStops));
      for J := 0 to High(FOperations[I].GradientStops) do
        ClonedOps[I].GradientStops[J] := FOperations[I].GradientStops[J];
    end;
  end;
  Result := TFloriaPicture.Create(FWidth, FHeight, FCullRect, ClonedOps, FOpCount);
end;

procedure TFloriaPicture.Playback(ACanvas: TFloriaCanvasAgg);
begin
  Playback(ACanvas, RectD(-1e9, -1e9, 1e9, 1e9), TFloriaMatrix2D.Identity());
end;

procedure TFloriaPicture.Playback(ACanvas: TFloriaCanvasAgg; const AClipBounds: TRectD);
begin
  Playback(ACanvas, AClipBounds, TFloriaMatrix2D.Identity());
end;

procedure TFloriaPicture.Playback(ACanvas: TFloriaCanvasAgg; const AClipBounds: TRectD; const AInitialMatrix: TFloriaMatrix2D);
var
  I, K: Integer;
  CurOp: TFloriaDisplayOp;
  TransRect, TransBounds: TRectD;
  TransP, TransP1, TransP2: TPointD;
  SubMatrix: TFloriaMatrix2D;
  ScaleVal: Double;
  MatrixStack: array of TFloriaMatrix2D;
  MatrixDepth: Integer;
  CurMatrix: TFloriaMatrix2D;
  AggPath: path_storage;
  AggStyle: TSVGStyleRecord;
  IsDrawOp: Boolean;
  TotalW, TotalH: Integer;
  RowY, ColX: Integer;
  TVal: Double;
  GradPix: TBgraPixel;
  ClipTypeStack: array of Boolean; // True = Rounded, False = Rect
  ClipTypeDepth: Integer;
begin
  if not Assigned(ACanvas) or (FOpCount = 0) then Exit;

  CurMatrix := AInitialMatrix;
  MatrixDepth := 0;
  SetLength(MatrixStack, 16);

  ClipTypeDepth := 0;
  SetLength(ClipTypeStack, 32);

  for I := 0 to FOpCount - 1 do
  begin
    CurOp := FOperations[I];

    // Spatial culling check: transform local bounds by CurMatrix to root canvas space
    IsDrawOp := CurOp.OpType in [dopDrawRect, dopDrawRoundedRect, dopDrawCircle, dopDrawLine,
                                 dopDrawPath, dopDrawShadow, dopDrawBorder, dopDrawLinearGradient,
                                 dopDrawText, dopDrawParagraph, dopDrawImage, dopDrawPicture];

    TransBounds := CurMatrix.TransformRect(CurOp.Bounds);
    if IsDrawOp and not TransBounds.IsEmpty and not TransBounds.Intersects(AClipBounds) then
      Continue;

    case CurOp.OpType of
      dopSave:
      begin
        if MatrixDepth >= Length(MatrixStack) then
          SetLength(MatrixStack, Length(MatrixStack) * 2);
        MatrixStack[MatrixDepth] := CurMatrix;
        Inc(MatrixDepth);
      end;

      dopRestore:
      begin
        if MatrixDepth > 0 then
        begin
          Dec(MatrixDepth);
          CurMatrix := MatrixStack[MatrixDepth];
        end;
      end;

      dopSetTransform:
        CurMatrix := CurOp.Matrix;

      dopTranslate:
        CurMatrix := CurMatrix.Multiply(TFloriaMatrix2D.Translation(CurOp.Pt1.X, CurOp.Pt1.Y));

      dopScale:
        CurMatrix := CurMatrix.Multiply(TFloriaMatrix2D.Scaling(CurOp.Pt1.X, CurOp.Pt1.Y));

      dopRotate:
        CurMatrix := CurMatrix.Multiply(TFloriaMatrix2D.RotationDeg(CurOp.GradAngle, CurOp.Pt1.X, CurOp.Pt1.Y));

      dopPushAlpha:
        ACanvas.PushAlpha(CurOp.Alpha);

      dopPopAlpha:
        ACanvas.PopAlpha();

      dopSetBlendMode:
        ACanvas.BlendMode := CurOp.BlendMode;

      dopPushClipRect:
      begin
        TransRect := CurMatrix.TransformRect(CurOp.Rect);
        ACanvas.PushClipRect(Round(TransRect.Left), Round(TransRect.Top),
                             Round(TransRect.Width), Round(TransRect.Height));
        if ClipTypeDepth >= Length(ClipTypeStack) then
          SetLength(ClipTypeStack, Length(ClipTypeStack) * 2);
        ClipTypeStack[ClipTypeDepth] := False;
        Inc(ClipTypeDepth);
      end;

      dopPushClipRoundedRect:
      begin
        TransRect := CurMatrix.TransformRect(CurOp.Rect);
        ACanvas.PushClipRoundedRect(TransRect.Left, TransRect.Top,
                                    TransRect.Width, TransRect.Height,
                                    CurOp.RadiusX, CurOp.RadiusY);
        if ClipTypeDepth >= Length(ClipTypeStack) then
          SetLength(ClipTypeStack, Length(ClipTypeStack) * 2);
        ClipTypeStack[ClipTypeDepth] := True;
        Inc(ClipTypeDepth);
      end;

      dopPopClip:
      begin
        if ClipTypeDepth > 0 then
        begin
          Dec(ClipTypeDepth);
          if ClipTypeStack[ClipTypeDepth] then
            ACanvas.PopClipRoundedRect()
          else
            ACanvas.PopClipRect();
        end
        else
          ACanvas.PopClipRect();
      end;

      dopClear:
        ACanvas.Clear(CurOp.FillColor.R / 255.0, CurOp.FillColor.G / 255.0, CurOp.FillColor.B / 255.0);

      dopDrawRect:
      begin
        TransRect := CurMatrix.TransformRect(CurOp.Rect);
        if CurOp.HasFill then
          ACanvas.DrawRect(Round(TransRect.Left), Round(TransRect.Top),
                           Round(TransRect.Width), Round(TransRect.Height),
                           CurOp.FillColor.R / 255.0, CurOp.FillColor.G / 255.0,
                           CurOp.FillColor.B / 255.0, CurOp.FillColor.A / 255.0);
        if CurOp.HasStroke and (CurOp.StrokeWidth > 0.0) then
        begin
          ACanvas.DrawLine(TransRect.Left, TransRect.Top, TransRect.Right, TransRect.Top,
                           CurOp.StrokeWidth, CurOp.StrokeColor.R / 255.0, CurOp.StrokeColor.G / 255.0, CurOp.StrokeColor.B / 255.0, CurOp.StrokeColor.A / 255.0);
          ACanvas.DrawLine(TransRect.Right, TransRect.Top, TransRect.Right, TransRect.Bottom,
                           CurOp.StrokeWidth, CurOp.StrokeColor.R / 255.0, CurOp.StrokeColor.G / 255.0, CurOp.StrokeColor.B / 255.0, CurOp.StrokeColor.A / 255.0);
          ACanvas.DrawLine(TransRect.Right, TransRect.Bottom, TransRect.Left, TransRect.Bottom,
                           CurOp.StrokeWidth, CurOp.StrokeColor.R / 255.0, CurOp.StrokeColor.G / 255.0, CurOp.StrokeColor.B / 255.0, CurOp.StrokeColor.A / 255.0);
          ACanvas.DrawLine(TransRect.Left, TransRect.Bottom, TransRect.Left, TransRect.Top,
                           CurOp.StrokeWidth, CurOp.StrokeColor.R / 255.0, CurOp.StrokeColor.G / 255.0, CurOp.StrokeColor.B / 255.0, CurOp.StrokeColor.A / 255.0);
        end;
      end;

      dopDrawRoundedRect:
      begin
        TransRect := CurMatrix.TransformRect(CurOp.Rect);
        if CurOp.HasFill then
          ACanvas.DrawRoundedRect(TransRect.Left, TransRect.Top,
                                  TransRect.Width, TransRect.Height,
                                  CurOp.RadiusX,
                                  CurOp.FillColor.R / 255.0, CurOp.FillColor.G / 255.0,
                                  CurOp.FillColor.B / 255.0, CurOp.FillColor.A / 255.0);
        if CurOp.HasStroke and (CurOp.StrokeWidth > 0.0) then
          ACanvas.DrawRoundedRectOutline(TransRect.Left, TransRect.Top,
                                         TransRect.Width, TransRect.Height,
                                         CurOp.RadiusX, CurOp.StrokeWidth,
                                         CurOp.StrokeColor.R / 255.0, CurOp.StrokeColor.G / 255.0,
                                         CurOp.StrokeColor.B / 255.0, CurOp.StrokeColor.A / 255.0);
      end;

      dopDrawCircle:
      begin
        TransP := CurMatrix.TransformPoint(PointD(CurOp.Pt1.X, CurOp.Pt1.Y));
        ScaleVal := Sqrt(Abs(CurMatrix.Determinant()));
        if ScaleVal <= 0.0 then ScaleVal := 1.0;
        if CurOp.HasFill then
          ACanvas.DrawCircle(TransP.X, TransP.Y, CurOp.Radius * ScaleVal,
                             CurOp.FillColor.R / 255.0, CurOp.FillColor.G / 255.0,
                             CurOp.FillColor.B / 255.0, CurOp.FillColor.A / 255.0);
        if CurOp.HasStroke and (CurOp.StrokeWidth > 0.0) then
          ACanvas.DrawCircleOutline(TransP.X, TransP.Y, CurOp.Radius * ScaleVal,
                                    CurOp.StrokeWidth,
                                    CurOp.StrokeColor.R / 255.0, CurOp.StrokeColor.G / 255.0,
                                    CurOp.StrokeColor.B / 255.0, CurOp.StrokeColor.A / 255.0);
      end;

      dopDrawLine:
      begin
        TransP1 := CurMatrix.TransformPoint(CurOp.Pt1);
        TransP2 := CurMatrix.TransformPoint(CurOp.Pt2);
        ACanvas.DrawLine(TransP1.X, TransP1.Y, TransP2.X, TransP2.Y,
                         CurOp.StrokeWidth,
                         CurOp.StrokeColor.R / 255.0, CurOp.StrokeColor.G / 255.0,
                         CurOp.StrokeColor.B / 255.0, CurOp.StrokeColor.A / 255.0);
      end;

      dopDrawPath:
      begin
        if Assigned(CurOp.Path) and not CurOp.Path.IsEmpty then
        begin
          AggPath.Construct();
          try
            CurOp.Path.ExportToAggPath(AggPath);
            FillChar(AggStyle, SizeOf(AggStyle), 0);
            if CurOp.HasFill then
            begin
              AggStyle.Fill.Kind := pkColor;
              AggStyle.Fill.Color.R := CurOp.FillColor.R;
              AggStyle.Fill.Color.G := CurOp.FillColor.G;
              AggStyle.Fill.Color.B := CurOp.FillColor.B;
              AggStyle.Fill.Color.A := CurOp.FillColor.A;
              AggStyle.FillOpacity := CurOp.FillColor.A / 255.0;
              if CurOp.FillRule = frEvenOdd then
                AggStyle.FillRule := sfrEvenOdd
              else
                AggStyle.FillRule := sfrNonZero;
            end
            else
              AggStyle.Fill.Kind := pkNone;

            if CurOp.HasStroke and (CurOp.StrokeWidth > 0.0) then
            begin
              AggStyle.Stroke.Kind := pkColor;
              AggStyle.Stroke.Color.R := CurOp.StrokeColor.R;
              AggStyle.Stroke.Color.G := CurOp.StrokeColor.G;
              AggStyle.Stroke.Color.B := CurOp.StrokeColor.B;
              AggStyle.Stroke.Color.A := CurOp.StrokeColor.A;
              AggStyle.StrokeWidth := CurOp.StrokeWidth;
              AggStyle.StrokeOpacity := CurOp.StrokeColor.A / 255.0;
              AggStyle.StrokeLineCap := slcRound;
              AggStyle.StrokeLineJoin := sljRound;
              AggStyle.StrokeMiterLimit := 4.0;
            end
            else
              AggStyle.Stroke.Kind := pkNone;

            ACanvas.RenderPath(AggPath, AggStyle);
          finally
            AggPath.Destruct();
          end;
        end;
      end;

      dopDrawShadow:
      begin
        TransRect := CurMatrix.TransformRect(CurOp.Rect);
        ACanvas.DrawShadow(TransRect.Left - CurOp.ShadowParams.SpreadRadius,
                           TransRect.Top - CurOp.ShadowParams.SpreadRadius,
                           TransRect.Width + CurOp.ShadowParams.SpreadRadius * 2.0,
                           TransRect.Height + CurOp.ShadowParams.SpreadRadius * 2.0,
                           CurOp.RadiusX,
                           CurOp.ShadowParams.OffsetX, CurOp.ShadowParams.OffsetY,
                           CurOp.ShadowParams.BlurRadius,
                           CurOp.ShadowParams.Color.R / 255.0,
                           CurOp.ShadowParams.Color.G / 255.0,
                           CurOp.ShadowParams.Color.B / 255.0,
                           CurOp.ShadowParams.Color.A / 255.0);
      end;

      dopDrawBorder:
      begin
        TransRect := CurMatrix.TransformRect(CurOp.Rect);
        // If uniform border with radius
        if (CurOp.BorderParams.Top.Width = CurOp.BorderParams.Bottom.Width) and
           (CurOp.BorderParams.Top.Width = CurOp.BorderParams.Left.Width) and
           (CurOp.BorderParams.Top.Width = CurOp.BorderParams.Right.Width) and
           (CurOp.BorderParams.RadiusX > 0.0) then
        begin
          ACanvas.DrawRoundedRectOutline(TransRect.Left, TransRect.Top,
                                         TransRect.Width, TransRect.Height,
                                         CurOp.BorderParams.RadiusX,
                                         CurOp.BorderParams.Top.Width,
                                         CurOp.BorderParams.Top.Color.R / 255.0,
                                         CurOp.BorderParams.Top.Color.G / 255.0,
                                         CurOp.BorderParams.Top.Color.B / 255.0,
                                         CurOp.BorderParams.Top.Color.A / 255.0);
        end
        else
        begin
          // Top
          if CurOp.BorderParams.Top.Width > 0.0 then
            ACanvas.DrawRect(Round(TransRect.Left), Round(TransRect.Top),
                             Round(TransRect.Width), Round(CurOp.BorderParams.Top.Width),
                             CurOp.BorderParams.Top.Color.R / 255.0, CurOp.BorderParams.Top.Color.G / 255.0,
                             CurOp.BorderParams.Top.Color.B / 255.0, CurOp.BorderParams.Top.Color.A / 255.0);
          // Bottom
          if CurOp.BorderParams.Bottom.Width > 0.0 then
            ACanvas.DrawRect(Round(TransRect.Left), Round(TransRect.Bottom - CurOp.BorderParams.Bottom.Width),
                             Round(TransRect.Width), Round(CurOp.BorderParams.Bottom.Width),
                             CurOp.BorderParams.Bottom.Color.R / 255.0, CurOp.BorderParams.Bottom.Color.G / 255.0,
                             CurOp.BorderParams.Bottom.Color.B / 255.0, CurOp.BorderParams.Bottom.Color.A / 255.0);
          // Left
          if CurOp.BorderParams.Left.Width > 0.0 then
            ACanvas.DrawRect(Round(TransRect.Left), Round(TransRect.Top + CurOp.BorderParams.Top.Width),
                             Round(CurOp.BorderParams.Left.Width), Round(TransRect.Height - CurOp.BorderParams.Top.Width - CurOp.BorderParams.Bottom.Width),
                             CurOp.BorderParams.Left.Color.R / 255.0, CurOp.BorderParams.Left.Color.G / 255.0,
                             CurOp.BorderParams.Left.Color.B / 255.0, CurOp.BorderParams.Left.Color.A / 255.0);
          // Right
          if CurOp.BorderParams.Right.Width > 0.0 then
            ACanvas.DrawRect(Round(TransRect.Right - CurOp.BorderParams.Right.Width), Round(TransRect.Top + CurOp.BorderParams.Top.Width),
                             Round(CurOp.BorderParams.Right.Width), Round(TransRect.Height - CurOp.BorderParams.Top.Width - CurOp.BorderParams.Bottom.Width),
                             CurOp.BorderParams.Right.Color.R / 255.0, CurOp.BorderParams.Right.Color.G / 255.0,
                             CurOp.BorderParams.Right.Color.B / 255.0, CurOp.BorderParams.Right.Color.A / 255.0);
        end;
      end;

      dopDrawLinearGradient:
      begin
        TransRect := CurMatrix.TransformRect(CurOp.Rect);
        TotalW := Round(TransRect.Width);
        TotalH := Round(TransRect.Height);
        if (TotalW > 0) and (TotalH > 0) and (Length(CurOp.GradientStops) > 0) then
        begin
          // Vertical gradient fast path
          if Abs(CurOp.GradP1.X - CurOp.GradP2.X) < 1e-4 then
          begin
            for RowY := 0 to TotalH - 1 do
            begin
              TVal := RowY / Max(1, TotalH - 1);
              GradPix := FloriaInterpolateGradient(CurOp.GradientStops, TVal);
              ACanvas.DrawRect(Round(TransRect.Left), Round(TransRect.Top) + RowY,
                               TotalW, 1,
                               GradPix.R / 255.0, GradPix.G / 255.0, GradPix.B / 255.0, GradPix.A / 255.0);
            end;
          end
          else
          begin
            // Horizontal gradient
            for ColX := 0 to TotalW - 1 do
            begin
              TVal := ColX / Max(1, TotalW - 1);
              GradPix := FloriaInterpolateGradient(CurOp.GradientStops, TVal);
              ACanvas.DrawRect(Round(TransRect.Left) + ColX, Round(TransRect.Top),
                               1, TotalH,
                               GradPix.R / 255.0, GradPix.G / 255.0, GradPix.B / 255.0, GradPix.A / 255.0);
            end;
          end;
        end;
      end;

      dopDrawText:
      begin
        TransP := CurMatrix.TransformPoint(PointD(CurOp.Pt1.X, CurOp.Pt1.Y));
        if Assigned(CurOp.Font) then
          ACanvas.DrawText(TransP.X, TransP.Y, CurOp.Text, CurOp.Font,
                           CurOp.FillColor.R / 255.0, CurOp.FillColor.G / 255.0, CurOp.FillColor.B / 255.0)
        else
          ACanvas.DrawText(TransP.X, TransP.Y, CurOp.Text, CurOp.FontSize,
                           CurOp.FillColor.R / 255.0, CurOp.FillColor.G / 255.0, CurOp.FillColor.B / 255.0);
      end;

      dopDrawParagraph:
      begin
        if Assigned(CurOp.Paragraph) then
        begin
          TransP := CurMatrix.TransformPoint(PointD(CurOp.Pt1.X, CurOp.Pt1.Y));
          CurOp.Paragraph.Paint(ACanvas, TransP.X, TransP.Y);
        end;
      end;

      dopDrawImage:
      begin
        if Assigned(CurOp.Image) then
        begin
          TransRect := CurMatrix.TransformRect(CurOp.DstRect);
          if CurOp.SrcRect.IsEmpty then
            ACanvas.DrawImageScaled(TransRect.Left, TransRect.Top, TransRect.Width, TransRect.Height, CurOp.Image, CurOp.Opacity)
          else
            ACanvas.DrawImagePart(TransRect.Left, TransRect.Top, TransRect.Width, TransRect.Height,
                                  CurOp.Image,
                                  Round(CurOp.SrcRect.Left), Round(CurOp.SrcRect.Top),
                                  Round(CurOp.SrcRect.Width), Round(CurOp.SrcRect.Height),
                                  CurOp.Opacity);
        end;
      end;

      dopDrawPicture:
      begin
        if Assigned(CurOp.Picture) then
        begin
          SubMatrix := CurMatrix.Multiply(TFloriaMatrix2D.Translation(CurOp.Pt1.X, CurOp.Pt1.Y));
          CurOp.Picture.Playback(ACanvas, AClipBounds, SubMatrix);
        end;
      end;

      dopSaveLayer:
      begin
        if CurOp.Opacity < 1.0 then
          ACanvas.PushAlpha(CurOp.Opacity);
        if CurOp.BlendMode <> fbmSrcOver then
          ACanvas.BlendMode := CurOp.BlendMode;
      end;

      dopRestoreLayer:
      begin
        ACanvas.BlendMode := fbmSrcOver;
        ACanvas.PopAlpha();
      end;
    end;
  end;
end;

procedure TFloriaPicture.Playback(AReceiver: IFloriaDisplayListReceiver);
var
  I: Integer;
  CurOp: TFloriaDisplayOp;
begin
  if not Assigned(AReceiver) then Exit;

  for I := 0 to FOpCount - 1 do
  begin
    CurOp := FOperations[I];
    case CurOp.OpType of
      dopSave:                AReceiver.OnSave();
      dopRestore:             AReceiver.OnRestore();
      dopSetTransform:        AReceiver.OnTransform(CurOp.Matrix);
      dopTranslate:           AReceiver.OnTransform(TFloriaMatrix2D.Translation(CurOp.Pt1.X, CurOp.Pt1.Y));
      dopScale:               AReceiver.OnTransform(TFloriaMatrix2D.Scaling(CurOp.Pt1.X, CurOp.Pt1.Y));
      dopRotate:              AReceiver.OnTransform(TFloriaMatrix2D.RotationDeg(CurOp.GradAngle, CurOp.Pt1.X, CurOp.Pt1.Y));
      dopPushAlpha:           AReceiver.OnSetAlpha(CurOp.Alpha);
      dopPopAlpha:            AReceiver.OnSetAlpha(1.0);
      dopSetBlendMode:        AReceiver.OnSetBlendMode(CurOp.BlendMode);
      dopPushClipRect:        AReceiver.OnPushClipRect(CurOp.Rect, CurOp.AntiAlias);
      dopPushClipRoundedRect: AReceiver.OnPushClipRoundedRect(CurOp.Rect, CurOp.RadiusX, CurOp.RadiusY, CurOp.AntiAlias);
      dopPopClip:             AReceiver.OnPopClip();
      dopClear:               AReceiver.OnClear(CurOp.FillColor);
      dopDrawRect:            AReceiver.OnDrawRect(CurOp.Rect, CurOp.FillColor, CurOp.StrokeColor, CurOp.StrokeWidth);
      dopDrawRoundedRect:     AReceiver.OnDrawRoundedRect(CurOp.Rect, CurOp.RadiusX, CurOp.RadiusY, CurOp.FillColor, CurOp.StrokeColor, CurOp.StrokeWidth);
      dopDrawCircle:          AReceiver.OnDrawCircle(CurOp.Pt1.X, CurOp.Pt1.Y, CurOp.Radius, CurOp.FillColor, CurOp.StrokeColor, CurOp.StrokeWidth);
      dopDrawLine:            AReceiver.OnDrawLine(CurOp.Pt1.X, CurOp.Pt1.Y, CurOp.Pt2.X, CurOp.Pt2.Y, CurOp.StrokeColor, CurOp.StrokeWidth);
      dopDrawPath:            AReceiver.OnDrawPath(CurOp.Path, CurOp.FillColor, CurOp.StrokeColor, CurOp.StrokeWidth, CurOp.FillRule);
      dopDrawShadow:          AReceiver.OnDrawShadow(CurOp.Rect, CurOp.RadiusX, CurOp.ShadowParams);
      dopDrawBorder:          AReceiver.OnDrawBorder(CurOp.Rect, CurOp.BorderParams);
      dopDrawLinearGradient:  AReceiver.OnDrawLinearGradient(CurOp.Rect, CurOp.GradP1, CurOp.GradP2, CurOp.GradientStops);
      dopDrawText:            AReceiver.OnDrawText(CurOp.Text, CurOp.Pt1.X, CurOp.Pt1.Y, CurOp.Font, CurOp.FontSize, CurOp.FillColor);
      dopDrawParagraph:       AReceiver.OnDrawParagraph(CurOp.Paragraph, CurOp.Pt1.X, CurOp.Pt1.Y);
      dopDrawImage:           AReceiver.OnDrawImage(CurOp.Image, CurOp.DstRect, CurOp.SrcRect, CurOp.Opacity);
      dopDrawPicture:         AReceiver.OnDrawPicture(CurOp.Picture, CurOp.Pt1.X, CurOp.Pt1.Y);
      dopSaveLayer:           AReceiver.OnSaveLayer(CurOp.Rect, CurOp.Opacity, CurOp.Filter, CurOp.BlendMode);
      dopRestoreLayer:        AReceiver.OnRestoreLayer();
    end;
  end;
end;

function TFloriaPicture.Dump(): string;
var
  I: Integer;
  CurOp: TFloriaDisplayOp;
  OpName: string;
begin
  Result := Format('Picture [%.1f, %.1f, %.1f, %.1f] (%d ops, CullRect: [%.1f, %.1f, %.1f, %.1f])'#10,
                   [0.0, 0.0, FWidth, FHeight, FOpCount,
                    FCullRect.Left, FCullRect.Top, FCullRect.Right, FCullRect.Bottom]);

  for I := 0 to FOpCount - 1 do
  begin
    CurOp := FOperations[I];
    WriteStr(OpName, CurOp.OpType);
    Result := Result + Format('  #%d [%s] Bounds=[%.1f, %.1f, %.1f, %.1f]',
                              [I, OpName, CurOp.Bounds.Left, CurOp.Bounds.Top, CurOp.Bounds.Right, CurOp.Bounds.Bottom]);

    case CurOp.OpType of
      dopTranslate:
        Result := Result + Format(' DX=%.1f, DY=%.1f', [CurOp.Pt1.X, CurOp.Pt1.Y]);
      dopScale:
        Result := Result + Format(' SX=%.2f, SY=%.2f', [CurOp.Pt1.X, CurOp.Pt1.Y]);
      dopRotate:
        Result := Result + Format(' Angle=%.1f deg', [CurOp.GradAngle]);
      dopDrawRect:
        Result := Result + Format(' Rect=[%.1f, %.1f, %.1f, %.1f]', [CurOp.Rect.Left, CurOp.Rect.Top, CurOp.Rect.Right, CurOp.Rect.Bottom]);
      dopDrawRoundedRect:
        Result := Result + Format(' Rect=[%.1f, %.1f, %.1f, %.1f] r=%.1f', [CurOp.Rect.Left, CurOp.Rect.Top, CurOp.Rect.Right, CurOp.Rect.Bottom, CurOp.RadiusX]);
      dopDrawCircle:
        Result := Result + Format(' Center=(%.1f, %.1f) r=%.1f', [CurOp.Pt1.X, CurOp.Pt1.Y, CurOp.Radius]);
      dopDrawLine:
        Result := Result + Format(' (%.1f, %.1f) -> (%.1f, %.1f) w=%.1f', [CurOp.Pt1.X, CurOp.Pt1.Y, CurOp.Pt2.X, CurOp.Pt2.Y, CurOp.StrokeWidth]);
      dopDrawText:
        Result := Result + Format(' Text="%s" at (%.1f, %.1f)', [CurOp.Text, CurOp.Pt1.X, CurOp.Pt1.Y]);
      dopDrawParagraph:
        Result := Result + Format(' Paragraph at (%.1f, %.1f)', [CurOp.Pt1.X, CurOp.Pt1.Y]);
    end;
    Result := Result + #10;
  end;
end;

// -----------------------------------------------------------------------------
// TFloriaPictureRecorder Implementation
// -----------------------------------------------------------------------------
constructor TFloriaPictureRecorder.Create();
begin
  inherited Create();
  FRecording     := False;
  FOpCount       := 0;
  FCapacity      := 0;
  FMatrixDepth   := 0;
  FCurrentMatrix := TFloriaMatrix2D.Identity();
end;

destructor TFloriaPictureRecorder.Destroy();
var
  I: Integer;
begin
  if FRecording then
  begin
    for I := 0 to FOpCount - 1 do
    begin
      if Assigned(FOperations[I].Path) then
        FreeAndNil(FOperations[I].Path);
      if Assigned(FOperations[I].Paragraph) and FOperations[I].OwnsParagraph then
        FreeAndNil(FOperations[I].Paragraph);
      if Assigned(FOperations[I].Picture) then
        FreeAndNil(FOperations[I].Picture);
    end;
  end;
  SetLength(FOperations, 0);
  SetLength(FMatrixStack, 0);
  inherited Destroy();
end;

procedure TFloriaPictureRecorder.EnsureCapacity(AAdditional: Integer = 1);
var
  NewCap: Integer;
begin
  if FOpCount + AAdditional > FCapacity then
  begin
    NewCap := Max(32, FCapacity * 2);
    if NewCap < FOpCount + AAdditional then
      NewCap := FOpCount + AAdditional + 16;
    SetLength(FOperations, NewCap);
    FCapacity := NewCap;
  end;
end;

procedure TFloriaPictureRecorder.AppendOp(const AOp: TFloriaDisplayOp);
begin
  EnsureCapacity(1);
  FOperations[FOpCount] := AOp;
  FOperations[FOpCount].Matrix := FCurrentMatrix;
  Inc(FOpCount);
end;

procedure TFloriaPictureRecorder.UpdateCullRect(const ABounds: TRectD);
begin
  if ABounds.IsEmpty then Exit;

  if not FHasContent then
  begin
    FCullRect := ABounds;
    FHasContent := True;
  end
  else
  begin
    FCullRect.Left   := Min(FCullRect.Left, ABounds.Left);
    FCullRect.Top    := Min(FCullRect.Top, ABounds.Top);
    FCullRect.Right  := Max(FCullRect.Right, ABounds.Right);
    FCullRect.Bottom := Max(FCullRect.Bottom, ABounds.Bottom);
  end;
end;

function TFloriaPictureRecorder.TransformCurrent(const ARect: TRectD): TRectD;
begin
  Result := FCurrentMatrix.TransformRect(ARect);
end;

procedure TFloriaPictureRecorder.BeginRecording(const ABounds: TRectD);
begin
  FRecording     := True;
  FInitialBounds := ABounds;
  FCullRect      := NullRectD;
  FHasContent    := False;
  FOpCount       := 0;
  FCapacity      := 0;
  SetLength(FOperations, 0);

  FCurrentMatrix := TFloriaMatrix2D.Identity();
  FMatrixDepth   := 0;
  SetLength(FMatrixStack, 16);
end;

procedure TFloriaPictureRecorder.BeginRecording(AWidth, AHeight: Double);
begin
  BeginRecording(RectD(0, 0, AWidth, AHeight));
end;

function TFloriaPictureRecorder.EndRecording(): TFloriaPicture;
var
  FinalCull: TRectD;
begin
  if not FRecording then
    raise Exception.Create('TFloriaPictureRecorder.EndRecording: Not currently recording');

  FRecording := False;

  if FHasContent then
    FinalCull := FCullRect
  else
    FinalCull := FInitialBounds;

  Result := TFloriaPicture.Create(FInitialBounds.Width, FInitialBounds.Height,
                                  FinalCull, FOperations, FOpCount);

  // Clear internal array references (ownership transferred to Picture)
  FOpCount  := 0;
  FCapacity := 0;
  SetLength(FOperations, 0);
  SetLength(FMatrixStack, 0);
end;

procedure TFloriaPictureRecorder.Save();
var
  Op: TFloriaDisplayOp;
begin
  if not FRecording then Exit;
  if FMatrixDepth >= Length(FMatrixStack) then
    SetLength(FMatrixStack, Length(FMatrixStack) * 2);
  FMatrixStack[FMatrixDepth] := FCurrentMatrix;
  Inc(FMatrixDepth);

  FillChar(Op, SizeOf(Op), 0);
  Op.OpType := dopSave;
  AppendOp(Op);
end;

procedure TFloriaPictureRecorder.Restore();
var
  Op: TFloriaDisplayOp;
begin
  if not FRecording then Exit;
  if FMatrixDepth > 0 then
  begin
    Dec(FMatrixDepth);
    FCurrentMatrix := FMatrixStack[FMatrixDepth];
  end;

  FillChar(Op, SizeOf(Op), 0);
  Op.OpType := dopRestore;
  AppendOp(Op);
end;

procedure TFloriaPictureRecorder.SetTransform(const AMatrix: TFloriaMatrix2D);
var
  Op: TFloriaDisplayOp;
begin
  if not FRecording then Exit;
  FCurrentMatrix := AMatrix;

  FillChar(Op, SizeOf(Op), 0);
  Op.OpType := dopSetTransform;
  Op.Matrix := AMatrix;
  AppendOp(Op);
end;

procedure TFloriaPictureRecorder.Translate(DX, DY: Double);
var
  Op: TFloriaDisplayOp;
begin
  if not FRecording then Exit;
  FCurrentMatrix := FCurrentMatrix.Multiply(TFloriaMatrix2D.Translation(DX, DY));

  FillChar(Op, SizeOf(Op), 0);
  Op.OpType := dopTranslate;
  Op.Pt1 := PointD(DX, DY);
  AppendOp(Op);
end;

procedure TFloriaPictureRecorder.Scale(SX, SY: Double);
var
  Op: TFloriaDisplayOp;
begin
  if not FRecording then Exit;
  FCurrentMatrix := FCurrentMatrix.Multiply(TFloriaMatrix2D.Scaling(SX, SY));

  FillChar(Op, SizeOf(Op), 0);
  Op.OpType := dopScale;
  Op.Pt1 := PointD(SX, SY);
  AppendOp(Op);
end;

procedure TFloriaPictureRecorder.Rotate(AngleDeg: Double; CX: Double = 0.0; CY: Double = 0.0);
var
  Op: TFloriaDisplayOp;
begin
  if not FRecording then Exit;
  FCurrentMatrix := FCurrentMatrix.Multiply(TFloriaMatrix2D.RotationDeg(AngleDeg, CX, CY));

  FillChar(Op, SizeOf(Op), 0);
  Op.OpType := dopRotate;
  Op.GradAngle := AngleDeg;
  Op.Pt1 := PointD(CX, CY);
  AppendOp(Op);
end;

procedure TFloriaPictureRecorder.PushAlpha(AAlpha: Double);
var
  Op: TFloriaDisplayOp;
begin
  if not FRecording then Exit;
  FillChar(Op, SizeOf(Op), 0);
  Op.OpType := dopPushAlpha;
  Op.Alpha  := AAlpha;
  AppendOp(Op);
end;

procedure TFloriaPictureRecorder.PopAlpha();
var
  Op: TFloriaDisplayOp;
begin
  if not FRecording then Exit;
  FillChar(Op, SizeOf(Op), 0);
  Op.OpType := dopPopAlpha;
  AppendOp(Op);
end;

procedure TFloriaPictureRecorder.SetBlendMode(AMode: TFloriaBlendMode);
var
  Op: TFloriaDisplayOp;
begin
  if not FRecording then Exit;
  FillChar(Op, SizeOf(Op), 0);
  Op.OpType    := dopSetBlendMode;
  Op.BlendMode := AMode;
  AppendOp(Op);
end;

procedure TFloriaPictureRecorder.PushClipRect(const ARect: TRectD; AAntiAlias: Boolean = True);
var
  Op: TFloriaDisplayOp;
begin
  if not FRecording then Exit;
  FillChar(Op, SizeOf(Op), 0);
  Op.OpType    := dopPushClipRect;
  Op.Rect      := ARect;
  Op.AntiAlias := AAntiAlias;
  Op.Bounds    := TransformCurrent(ARect);
  AppendOp(Op);
end;

procedure TFloriaPictureRecorder.PushClipRect(X, Y, W, H: Double; AAntiAlias: Boolean = True);
begin
  PushClipRect(RectD(X, Y, X + W, Y + H), AAntiAlias);
end;

procedure TFloriaPictureRecorder.PushClipRoundedRect(const ARect: TRectD; ARadiusX, ARadiusY: Double; AAntiAlias: Boolean = True);
var
  Op: TFloriaDisplayOp;
begin
  if not FRecording then Exit;
  FillChar(Op, SizeOf(Op), 0);
  Op.OpType    := dopPushClipRoundedRect;
  Op.Rect      := ARect;
  Op.RadiusX   := ARadiusX;
  Op.RadiusY   := ARadiusY;
  Op.AntiAlias := AAntiAlias;
  Op.Bounds    := TransformCurrent(ARect);
  AppendOp(Op);
end;

procedure TFloriaPictureRecorder.PushClipRoundedRect(X, Y, W, H, ARadius: Double; AAntiAlias: Boolean = True);
begin
  PushClipRoundedRect(RectD(X, Y, X + W, Y + H), ARadius, ARadius, AAntiAlias);
end;

procedure TFloriaPictureRecorder.PopClip();
var
  Op: TFloriaDisplayOp;
begin
  if not FRecording then Exit;
  FillChar(Op, SizeOf(Op), 0);
  Op.OpType := dopPopClip;
  AppendOp(Op);
end;

procedure TFloriaPictureRecorder.Clear(const AColor: TBgraPixel);
var
  Op: TFloriaDisplayOp;
begin
  if not FRecording then Exit;
  FillChar(Op, SizeOf(Op), 0);
  Op.OpType    := dopClear;
  Op.FillColor := AColor;
  Op.Bounds    := FInitialBounds;
  AppendOp(Op);
  UpdateCullRect(Op.Bounds);
end;

procedure TFloriaPictureRecorder.Clear(R, G, B: Double; A: Double = 1.0);
begin
  Clear(BgraPixel(Round(R * 255), Round(G * 255), Round(B * 255), Round(A * 255)));
end;

procedure TFloriaPictureRecorder.DrawRect(const ARect: TRectD; const AFillColor: TBgraPixel);
begin
  DrawRect(ARect, AFillColor, BgraPixel(0, 0, 0, 0), 0.0);
end;

procedure TFloriaPictureRecorder.DrawRect(const ARect: TRectD; const AFillColor, AStrokeColor: TBgraPixel; AStrokeWidth: Double);
var
  Op: TFloriaDisplayOp;
  InflatedRect: TRectD;
begin
  if not FRecording then Exit;
  FillChar(Op, SizeOf(Op), 0);
  Op.OpType      := dopDrawRect;
  Op.Rect        := ARect;
  Op.FillColor   := AFillColor;
  Op.StrokeColor := AStrokeColor;
  Op.StrokeWidth := AStrokeWidth;
  Op.HasFill     := (AFillColor.A > 0);
  Op.HasStroke   := (AStrokeColor.A > 0) and (AStrokeWidth > 0.0);

  InflatedRect := ARect;
  if Op.HasStroke then
  begin
    InflatedRect.Left   := InflatedRect.Left - AStrokeWidth * 0.5;
    InflatedRect.Top    := InflatedRect.Top - AStrokeWidth * 0.5;
    InflatedRect.Right  := InflatedRect.Right + AStrokeWidth * 0.5;
    InflatedRect.Bottom := InflatedRect.Bottom + AStrokeWidth * 0.5;
  end;

  Op.Bounds := TransformCurrent(InflatedRect);
  AppendOp(Op);
  UpdateCullRect(Op.Bounds);
end;

procedure TFloriaPictureRecorder.DrawRect(X, Y, W, H: Double; const AFillColor: TBgraPixel);
begin
  DrawRect(RectD(X, Y, X + W, Y + H), AFillColor);
end;

procedure TFloriaPictureRecorder.DrawRoundedRect(const ARect: TRectD; ARadiusX, ARadiusY: Double; const AFillColor: TBgraPixel);
begin
  DrawRoundedRect(ARect, ARadiusX, ARadiusY, AFillColor, BgraPixel(0, 0, 0, 0), 0.0);
end;

procedure TFloriaPictureRecorder.DrawRoundedRect(const ARect: TRectD; ARadiusX, ARadiusY: Double;
                                                 const AFillColor, AStrokeColor: TBgraPixel; AStrokeWidth: Double);
var
  Op: TFloriaDisplayOp;
  InflatedRect: TRectD;
begin
  if not FRecording then Exit;
  FillChar(Op, SizeOf(Op), 0);
  Op.OpType      := dopDrawRoundedRect;
  Op.Rect        := ARect;
  Op.RadiusX     := ARadiusX;
  Op.RadiusY     := ARadiusY;
  Op.FillColor   := AFillColor;
  Op.StrokeColor := AStrokeColor;
  Op.StrokeWidth := AStrokeWidth;
  Op.HasFill     := (AFillColor.A > 0);
  Op.HasStroke   := (AStrokeColor.A > 0) and (AStrokeWidth > 0.0);

  InflatedRect := ARect;
  if Op.HasStroke then
  begin
    InflatedRect.Left   := InflatedRect.Left - AStrokeWidth * 0.5;
    InflatedRect.Top    := InflatedRect.Top - AStrokeWidth * 0.5;
    InflatedRect.Right  := InflatedRect.Right + AStrokeWidth * 0.5;
    InflatedRect.Bottom := InflatedRect.Bottom + AStrokeWidth * 0.5;
  end;

  Op.Bounds := TransformCurrent(InflatedRect);
  AppendOp(Op);
  UpdateCullRect(Op.Bounds);
end;

procedure TFloriaPictureRecorder.DrawRoundedRect(X, Y, W, H, ARadius: Double; const AFillColor: TBgraPixel);
begin
  DrawRoundedRect(RectD(X, Y, X + W, Y + H), ARadius, ARadius, AFillColor);
end;

procedure TFloriaPictureRecorder.DrawRoundedRectOutline(X, Y, W, H, ARadius, AStrokeWidth: Double; const AStrokeColor: TBgraPixel);
begin
  DrawRoundedRect(RectD(X, Y, X + W, Y + H), ARadius, ARadius, BgraPixel(0, 0, 0, 0), AStrokeColor, AStrokeWidth);
end;

procedure TFloriaPictureRecorder.DrawCircle(ACenterX, ACenterY, ARadius: Double; const AFillColor: TBgraPixel);
begin
  DrawCircle(ACenterX, ACenterY, ARadius, AFillColor, BgraPixel(0, 0, 0, 0), 0.0);
end;

procedure TFloriaPictureRecorder.DrawCircle(ACenterX, ACenterY, ARadius: Double;
                                           const AFillColor, AStrokeColor: TBgraPixel; AStrokeWidth: Double);
var
  Op: TFloriaDisplayOp;
  TotalR: Double;
  CircleRect: TRectD;
begin
  if not FRecording then Exit;
  FillChar(Op, SizeOf(Op), 0);
  Op.OpType      := dopDrawCircle;
  Op.Pt1         := PointD(ACenterX, ACenterY);
  Op.Radius      := ARadius;
  Op.FillColor   := AFillColor;
  Op.StrokeColor := AStrokeColor;
  Op.StrokeWidth := AStrokeWidth;
  Op.HasFill     := (AFillColor.A > 0);
  Op.HasStroke   := (AStrokeColor.A > 0) and (AStrokeWidth > 0.0);

  TotalR := ARadius;
  if Op.HasStroke then
    TotalR := TotalR + AStrokeWidth * 0.5;

  CircleRect := RectD(ACenterX - TotalR, ACenterY - TotalR, ACenterX + TotalR, ACenterY + TotalR);
  Op.Bounds := TransformCurrent(CircleRect);
  AppendOp(Op);
  UpdateCullRect(Op.Bounds);
end;

procedure TFloriaPictureRecorder.DrawLine(AX1, AY1, AX2, AY2: Double; const AColor: TBgraPixel; AStrokeWidth: Double = 1.0);
var
  Op: TFloriaDisplayOp;
  HalfW: Double;
  LineRect: TRectD;
begin
  if not FRecording then Exit;
  FillChar(Op, SizeOf(Op), 0);
  Op.OpType      := dopDrawLine;
  Op.Pt1         := PointD(AX1, AY1);
  Op.Pt2         := PointD(AX2, AY2);
  Op.StrokeColor := AColor;
  Op.StrokeWidth := AStrokeWidth;
  Op.HasStroke   := True;

  HalfW := AStrokeWidth * 0.5;
  LineRect := RectD(Min(AX1, AX2) - HalfW, Min(AY1, AY2) - HalfW,
                    Max(AX1, AX2) + HalfW, Max(AY1, AY2) + HalfW);

  Op.Bounds := TransformCurrent(LineRect);
  AppendOp(Op);
  UpdateCullRect(Op.Bounds);
end;

procedure TFloriaPictureRecorder.DrawPath(APath: TFloriaPath; const AFillColor: TBgraPixel; AFillRule: TFillRule = frNonZero);
begin
  DrawPath(APath, AFillColor, BgraPixel(0, 0, 0, 0), 0.0, AFillRule);
end;

procedure TFloriaPictureRecorder.DrawPath(APath: TFloriaPath; const AFillColor, AStrokeColor: TBgraPixel;
                                         AStrokeWidth: Double; AFillRule: TFillRule = frNonZero);
var
  Op: TFloriaDisplayOp;
  PBounds: TRectD;
begin
  if not FRecording or not Assigned(APath) or APath.IsEmpty then Exit;

  FillChar(Op, SizeOf(Op), 0);
  Op.OpType      := dopDrawPath;
  Op.Path        := APath.Clone(); // Owns a deep clone of the path
  Op.FillColor   := AFillColor;
  Op.StrokeColor := AStrokeColor;
  Op.StrokeWidth := AStrokeWidth;
  Op.FillRule    := AFillRule;
  Op.HasFill     := (AFillColor.A > 0);
  Op.HasStroke   := (AStrokeColor.A > 0) and (AStrokeWidth > 0.0);

  PBounds := APath.GetBounds();
  if Op.HasStroke then
  begin
    PBounds.Left   := PBounds.Left - AStrokeWidth * 0.5;
    PBounds.Top    := PBounds.Top - AStrokeWidth * 0.5;
    PBounds.Right  := PBounds.Right + AStrokeWidth * 0.5;
    PBounds.Bottom := PBounds.Bottom + AStrokeWidth * 0.5;
  end;

  Op.Bounds := TransformCurrent(PBounds);
  AppendOp(Op);
  UpdateCullRect(Op.Bounds);
end;

procedure TFloriaPictureRecorder.DrawShadow(const ARect: TRectD; ARadius: Double; const AParams: TFloriaShadowParams);
var
  Op: TFloriaDisplayOp;
  ShadowRect: TRectD;
  Dilate: Double;
begin
  if not FRecording then Exit;
  FillChar(Op, SizeOf(Op), 0);
  Op.OpType       := dopDrawShadow;
  Op.Rect         := ARect;
  Op.RadiusX      := ARadius;
  Op.RadiusY      := ARadius;
  Op.ShadowParams := AParams;

  Dilate := AParams.SpreadRadius + AParams.BlurRadius * 3.0;
  ShadowRect := RectD(ARect.Left + AParams.OffsetX - Dilate,
                      ARect.Top + AParams.OffsetY - Dilate,
                      ARect.Right + AParams.OffsetX + Dilate,
                      ARect.Bottom + AParams.OffsetY + Dilate);

  Op.Bounds := TransformCurrent(ShadowRect);
  AppendOp(Op);
  UpdateCullRect(Op.Bounds);
end;

procedure TFloriaPictureRecorder.DrawShadow(X, Y, W, H, ARadius, AOffsetX, AOffsetY, ABlurRadius: Double; const AColor: TBgraPixel);
begin
  DrawShadow(RectD(X, Y, X + W, Y + H), ARadius, FloriaShadowParams(AOffsetX, AOffsetY, ABlurRadius, 0.0, AColor));
end;

procedure TFloriaPictureRecorder.DrawShadow(X, Y, W, H, ARadius, AOffsetX, AOffsetY, ABlurRadius, ASpreadRadius: Double;
                                           const AColor: TBgraPixel; AInset: Boolean = False);
begin
  DrawShadow(RectD(X, Y, X + W, Y + H), ARadius, FloriaShadowParams(AOffsetX, AOffsetY, ABlurRadius, ASpreadRadius, AColor, AInset));
end;

procedure TFloriaPictureRecorder.DrawBorder(const ARect: TRectD; const ATop, ARight, ABottom, ALeft: TFloriaBorderSide;
                                           ARadiusX: Double = 0.0; ARadiusY: Double = 0.0);
var
  Op: TFloriaDisplayOp;
  MaxW: Double;
  BorderRect: TRectD;
begin
  if not FRecording then Exit;
  FillChar(Op, SizeOf(Op), 0);
  Op.OpType       := dopDrawBorder;
  Op.Rect         := ARect;
  Op.BorderParams := FloriaBorderParams(ATop, ARight, ABottom, ALeft, ARadiusX, ARadiusY);

  MaxW := Max(Max(ATop.Width, ABottom.Width), Max(ALeft.Width, ARight.Width));
  BorderRect := RectD(ARect.Left - MaxW * 0.5, ARect.Top - MaxW * 0.5,
                      ARect.Right + MaxW * 0.5, ARect.Bottom + MaxW * 0.5);

  Op.Bounds := TransformCurrent(BorderRect);
  AppendOp(Op);
  UpdateCullRect(Op.Bounds);
end;

procedure TFloriaPictureRecorder.DrawBorder(const ARect: TRectD; ABorderWidth: Double; const ABorderColor: TBgraPixel; ARadius: Double = 0.0);
var
  Side: TFloriaBorderSide;
begin
  Side := FloriaBorderSide(ABorderWidth, ABorderColor);
  DrawBorder(ARect, Side, Side, Side, Side, ARadius, ARadius);
end;

procedure TFloriaPictureRecorder.DrawBorder(X, Y, W, H, ABorderWidth: Double; const ABorderColor: TBgraPixel; ARadius: Double = 0.0);
begin
  DrawBorder(RectD(X, Y, X + W, Y + H), ABorderWidth, ABorderColor, ARadius);
end;

procedure TFloriaPictureRecorder.DrawLinearGradient(const ARect: TRectD; const AP1, AP2: TPointD; const AStops: array of TFloriaGradientStop);
var
  Op: TFloriaDisplayOp;
  I: Integer;
begin
  if not FRecording or (Length(AStops) = 0) then Exit;
  FillChar(Op, SizeOf(Op), 0);
  Op.OpType := dopDrawLinearGradient;
  Op.Rect   := ARect;
  Op.GradP1 := AP1;
  Op.GradP2 := AP2;

  SetLength(Op.GradientStops, Length(AStops));
  for I := 0 to High(AStops) do
    Op.GradientStops[I] := AStops[I];

  Op.Bounds := TransformCurrent(ARect);
  AppendOp(Op);
  UpdateCullRect(Op.Bounds);
end;

procedure TFloriaPictureRecorder.DrawLinearGradient(const ARect: TRectD; AAngleDeg: Double; const AStops: array of TFloriaGradientStop);
var
  P1, P2: TPointD;
begin
  // Calculate P1 and P2 based on angle
  if (Abs(AAngleDeg - 90.0) < 1e-4) or (Abs(AAngleDeg) < 1e-4) then
  begin
    // Vertical top-to-bottom
    P1 := PointD(ARect.Left, ARect.Top);
    P2 := PointD(ARect.Left, ARect.Bottom);
  end
  else
  begin
    // Horizontal left-to-right
    P1 := PointD(ARect.Left, ARect.Top);
    P2 := PointD(ARect.Right, ARect.Top);
  end;
  DrawLinearGradient(ARect, P1, P2, AStops);
end;

procedure TFloriaPictureRecorder.DrawText(const AText: string; AX, AY: Double; AFont: TFloriaFont; const AColor: TBgraPixel);
var
  Op: TFloriaDisplayOp;
  EstW, EstH: Double;
begin
  if not FRecording or (AText = '') then Exit;
  FillChar(Op, SizeOf(Op), 0);
  Op.OpType    := dopDrawText;
  Op.Text      := AText;
  Op.Pt1       := PointD(AX, AY);
  Op.Font      := AFont;
  Op.FillColor := AColor;

  if Assigned(AFont) then
  begin
    EstW := AFont.GetTextWidth(AText);
    EstH := AFont.Height;
  end
  else
  begin
    EstW := Length(AText) * 8.0;
    EstH := 14.0;
  end;

  Op.Bounds := TransformCurrent(RectD(AX, AY - EstH * 0.8, AX + EstW, AY + EstH * 0.3));
  AppendOp(Op);
  UpdateCullRect(Op.Bounds);
end;

procedure TFloriaPictureRecorder.DrawText(const AText: string; AX, AY: Double; AFontSize: Double; const AColor: TBgraPixel);
var
  Op: TFloriaDisplayOp;
  EstW, EstH: Double;
begin
  if not FRecording or (AText = '') then Exit;
  FillChar(Op, SizeOf(Op), 0);
  Op.OpType    := dopDrawText;
  Op.Text      := AText;
  Op.Pt1       := PointD(AX, AY);
  Op.FontSize  := AFontSize;
  Op.FillColor := AColor;

  EstW := Length(AText) * AFontSize * 0.6;
  EstH := AFontSize * 1.2;

  Op.Bounds := TransformCurrent(RectD(AX, AY - EstH * 0.8, AX + EstW, AY + EstH * 0.3));
  AppendOp(Op);
  UpdateCullRect(Op.Bounds);
end;

procedure TFloriaPictureRecorder.DrawParagraph(AParagraph: TFloriaParagraph; AX, AY: Double; AOwnsParagraph: Boolean = False);
var
  Op: TFloriaDisplayOp;
  PBounds: TRectD;
begin
  if not FRecording or not Assigned(AParagraph) then Exit;
  FillChar(Op, SizeOf(Op), 0);
  Op.OpType        := dopDrawParagraph;
  Op.Paragraph     := AParagraph;
  Op.OwnsParagraph := AOwnsParagraph;
  Op.Pt1           := PointD(AX, AY);

  PBounds   := RectD(AX, AY, AX + AParagraph.Width, AY + AParagraph.Height);
  Op.Bounds := TransformCurrent(PBounds);
  AppendOp(Op);
  UpdateCullRect(Op.Bounds);
end;

procedure TFloriaPictureRecorder.DrawImage(AImage: TFloriaImage; AX, AY: Double; AOpacity: Double = 1.0);
begin
  if Assigned(AImage) then
    DrawImage(AImage, RectD(AX, AY, AX + AImage.Width, AY + AImage.Height), NullRectD, AOpacity);
end;

procedure TFloriaPictureRecorder.DrawImage(AImage: TFloriaImage; const ADstRect: TRectD; AOpacity: Double = 1.0);
begin
  DrawImage(AImage, ADstRect, NullRectD, AOpacity);
end;

procedure TFloriaPictureRecorder.DrawImage(AImage: TFloriaImage; const ADstRect, ASrcRect: TRectD; AOpacity: Double = 1.0);
var
  Op: TFloriaDisplayOp;
begin
  if not FRecording or not Assigned(AImage) then Exit;
  FillChar(Op, SizeOf(Op), 0);
  Op.OpType  := dopDrawImage;
  Op.Image   := AImage;
  Op.DstRect := ADstRect;
  Op.SrcRect := ASrcRect;
  Op.Opacity := AOpacity;

  Op.Bounds := TransformCurrent(ADstRect);
  AppendOp(Op);
  UpdateCullRect(Op.Bounds);
end;

procedure TFloriaPictureRecorder.DrawPicture(APicture: TFloriaPicture; AX, AY: Double);
var
  Op: TFloriaDisplayOp;
  PicBounds: TRectD;
begin
  if not FRecording or not Assigned(APicture) then Exit;
  FillChar(Op, SizeOf(Op), 0);
  Op.OpType  := dopDrawPicture;
  Op.Picture := APicture.Clone(); // Retains a deep clone of the sub-picture
  Op.Pt1     := PointD(AX, AY);

  PicBounds := RectD(APicture.CullRect.Left + AX, APicture.CullRect.Top + AY,
                     APicture.CullRect.Right + AX, APicture.CullRect.Bottom + AY);

  Op.Bounds := TransformCurrent(PicBounds);
  AppendOp(Op);
  UpdateCullRect(Op.Bounds);
end;

procedure TFloriaPictureRecorder.SaveLayer(const ABounds: TRectD; AOpacity: Double = 1.0;
                                          AFilter: TFloriaImageFilter = nil;
                                          ABlendMode: TFloriaBlendMode = fbmSrcOver);
var
  Op: TFloriaDisplayOp;
begin
  if not FRecording then Exit;
  FillChar(Op, SizeOf(Op), 0);
  Op.OpType    := dopSaveLayer;
  Op.Rect      := ABounds;
  Op.Opacity   := AOpacity;
  Op.Filter    := AFilter;
  Op.BlendMode := ABlendMode;
  Op.Bounds    := TransformCurrent(ABounds);
  AppendOp(Op);
end;

procedure TFloriaPictureRecorder.RestoreLayer();
var
  Op: TFloriaDisplayOp;
begin
  if not FRecording then Exit;
  FillChar(Op, SizeOf(Op), 0);
  Op.OpType := dopRestoreLayer;
  AppendOp(Op);
end;

end.
