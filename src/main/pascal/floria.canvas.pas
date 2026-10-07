unit Floria.Canvas;

// Floria.Canvas
// =============
// Unified abstract 2D drawing canvas interface for Floria.
// All UI widgets and themes render strictly against TFloriaCanvas, making them
// completely decoupled from the underlying rasterization engine (CPU AggPas vs GPU OpenGL).

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Math,
  Floria.Image.Core,
  Floria.Font,
  Floria.Canvas.Blend,
  Floria.SVG.Types,
  Floria.SVG.DOM;

type
  TFtClipRect = record
    X1, Y1, X2, Y2: Integer;
  end;

  TFloriaCanvas = class
  protected
    FWidth       : Integer;
    FHeight      : Integer;
    FCurrentAlpha: Double;
    FBlendMode   : TFloriaBlendMode;

    function GetWidth(): Integer; virtual;
    function GetHeight(): Integer; virtual;
    function GetCurrentAlpha(): Double; virtual;
    function GetBlendMode(): TFloriaBlendMode; virtual;
    procedure SetBlendMode(AMode: TFloriaBlendMode); virtual;
  public
    constructor Create();
    destructor Destroy(); override;

    procedure Resize(AWidth, AHeight: Integer); virtual; abstract;

    procedure Clear(R, G, B: Double); virtual; abstract;
    procedure DrawRect(X, Y, W, H: Integer; R, G, B: Double; A: Double = 1.0); virtual; abstract;
    procedure DrawRoundedRect(X, Y, W, H: Double; Radius: Double; R, G, B: Double; A: Double = 1.0); virtual; abstract;
    procedure DrawRoundedRectOutline(X, Y, W, H: Double; Radius: Double; BorderWidth: Double; R, G, B: Double; A: Double = 1.0); virtual; abstract;
    procedure DrawShadow(X, Y, W, H: Double; Radius: Double; OffsetX, OffsetY: Double; BlurRadius: Double; ShadowR, ShadowG, ShadowB, ShadowOpacity: Double); virtual; abstract;
    procedure BlurRoundedRect(X, Y, W, H: Double; Radius: Double; BlurRadius: Double); virtual;
    procedure BlurRect(X, Y, W, H: Double; BlurRadius: Double); virtual;

    procedure PushClipRect(X, Y, W, H: Integer); virtual; abstract;
    procedure PopClipRect(); virtual; abstract;
    procedure PushClipRoundedRect(X, Y, W, H: Double; Radius: Double); virtual; abstract; overload;
    procedure PushClipRoundedRect(X, Y, W, H: Double; TopRadius, BottomRadius: Double); virtual; abstract; overload;
    procedure PopClipRoundedRect(); virtual; abstract;
    procedure SetClipRect(X, Y, W, H: Integer); virtual; abstract;
    procedure ResetClipRect(); virtual; abstract;
    procedure ResetAllClipping(); virtual; abstract;
    function GetClipRect(out X, Y, W, H: Integer): Boolean; virtual; abstract;
    function IntersectsClip(X, Y, W, H: Integer): Boolean; virtual; abstract;

    procedure PushAlpha(AAlpha: Double); virtual; abstract;
    procedure PopAlpha(); virtual; abstract;
    procedure ResetAlpha(); virtual; abstract;

    procedure DrawText(X, Y: Double; const AText: string; AFont: TFloriaFont; R, G, B: Double); virtual; abstract; overload;
    procedure DrawTextCentered(X, Y, W, H: Integer; const AText: string; AFont: TFloriaFont; R, G, B: Double); virtual; abstract; overload;
    procedure DrawTextLeft(X, Y, W, H: Double; const AText: string; AFont: TFloriaFont; R, G, B: Double); virtual; abstract;

    procedure DrawCheckMark(CX, CY: Double; R, G, B: Double; A: Double = 1.0); virtual; abstract;
    procedure DrawSubMenuArrow(CX, CY: Double; R, G, B: Double; A: Double = 1.0); virtual; abstract;
    procedure DrawCircle(CX, CY, Radius: Double; R, G, B: Double; A: Double = 1.0); virtual; abstract;
    procedure DrawCircleOutline(CX, CY, Radius, BorderWidth: Double; R, G, B: Double; A: Double = 1.0); virtual; abstract;
    procedure DrawLine(X1, Y1, X2, Y2, LineWidth: Double; R, G, B: Double; A: Double = 1.0); virtual; abstract;

    // Image & Bitmap Drawing
    procedure DrawImage(X, Y: Double; AImage: TFloriaImage; AOpacity: Double = 1.0); virtual; abstract;
    procedure DrawImageScaled(X, Y, W, H: Double; AImage: TFloriaImage; AOpacity: Double = 1.0); virtual; abstract;
    procedure DrawImagePart(X, Y, W, H: Double; AImage: TFloriaImage; SrcX, SrcY, SrcW, SrcH: Integer; AOpacity: Double = 1.0); virtual; abstract;

    // SVG Drawing
    procedure DrawSVG(X, Y: Double; ADoc: TSVGDocument); virtual;
    procedure DrawSVGScaled(X, Y, W, H: Double; ADoc: TSVGDocument); virtual;
    procedure DrawSVGFile(X, Y, W, H: Double; const AFileName: string); virtual;
    procedure DrawSVGString(X, Y, W, H: Double; const ASVGContent: string); virtual;

    // Font size convenience overloads
    procedure DrawText(X, Y: Double; const AText: string; ASize: Double; R, G, B: Double); virtual; overload;
    procedure DrawTextCentered(X, Y, W, H: Integer; const AText: string; ASize: Double; R, G, B: Double); virtual; overload;

    property Width       : Integer read GetWidth;
    property Height      : Integer read GetHeight;
    property CurrentAlpha: Double read GetCurrentAlpha;
    property BlendMode   : TFloriaBlendMode read GetBlendMode write SetBlendMode;
  end;

  // Backward-compatibility alias
  TFtCanvas = TFloriaCanvas;

implementation

constructor TFloriaCanvas.Create();
begin
  inherited Create();
  FWidth := 0;
  FHeight := 0;
  FCurrentAlpha := 1.0;
  FBlendMode := fbmSrcOver;
end;

destructor TFloriaCanvas.Destroy();
begin
  inherited Destroy();
end;

function TFloriaCanvas.GetWidth(): Integer;
begin
  Result := FWidth;
end;

function TFloriaCanvas.GetHeight(): Integer;
begin
  Result := FHeight;
end;

function TFloriaCanvas.GetCurrentAlpha(): Double;
begin
  Result := FCurrentAlpha;
end;

function TFloriaCanvas.GetBlendMode(): TFloriaBlendMode;
begin
  Result := FBlendMode;
end;

procedure TFloriaCanvas.SetBlendMode(AMode: TFloriaBlendMode);
begin
  FBlendMode := AMode;
end;

procedure TFloriaCanvas.BlurRoundedRect(X, Y, W, H: Double; Radius: Double; BlurRadius: Double);
begin
  // Base stub
end;

procedure TFloriaCanvas.BlurRect(X, Y, W, H: Double; BlurRadius: Double);
begin
  // Base stub
end;

procedure TFloriaCanvas.DrawSVG(X, Y: Double; ADoc: TSVGDocument);
begin
  // Base stub
end;

procedure TFloriaCanvas.DrawSVGScaled(X, Y, W, H: Double; ADoc: TSVGDocument);
begin
  // Base stub
end;

procedure TFloriaCanvas.DrawSVGFile(X, Y, W, H: Double; const AFileName: string);
begin
  // Base stub
end;

procedure TFloriaCanvas.DrawSVGString(X, Y, W, H: Double; const ASVGContent: string);
begin
  // Base stub
end;

procedure TFloriaCanvas.DrawText(X, Y: Double; const AText: string; ASize: Double; R, G, B: Double);
var
  f: TFloriaFont;
begin
  f := FloriaFontManager().GetFont('Sans-' + FloatToStr(ASize));
  DrawText(X, Y, AText, f, R, G, B);
end;

procedure TFloriaCanvas.DrawTextCentered(X, Y, W, H: Integer; const AText: string; ASize: Double; R, G, B: Double);
var
  f: TFloriaFont;
begin
  f := FloriaFontManager().GetFont('Sans-' + FloatToStr(ASize));
  DrawTextCentered(X, Y, W, H, AText, f, R, G, B);
end;

end.
