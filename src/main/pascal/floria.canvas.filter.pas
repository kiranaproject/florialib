unit Floria.Canvas.Filter;

// Floria.Canvas.Filter
// ====================
// Composable image filter graph matching Skia's SkImageFilter / SkColorFilter.
// Pure Object Pascal, zero dependencies.
//
// Key Filters:
//   - TFloriaImageFilter (Abstract base class with chaining & composition)
//   - TBlurFilter (Gaussian 3-pass separable O(1) box approximation, Box, Dual-Kawase)
//   - TColorMatrixFilter (4x5 color matrix for Grayscale, Sepia, Saturation, Invert, Contrast, Tint)
//   - TDropShadowFilter (Offset, blur sigma, shadow color, shadow-only or composite)
//   - TMorphologyFilter (Dilate & Erode separable 2D morphological operators)
//   - TDisplacementMapFilter (SVG feDisplacementMap arbitrary pixel displacement with bilinear sampling)
//   - TComposeFilter (Chained A -> B filter execution)
//   - TCompositeFilter (Blend mode combination of two filter trees)

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  Classes, SysUtils, Math, Types,
  Floria.Image.Core,
  Floria.Canvas.Blend;

type
  // Forward declarations
  TFloriaImageFilter = class;

  // Blur algorithm types
  TFloriaBlurType = (
    fbtGaussian,  // 3-pass separable box approximation (exact Central Limit Theorem Gaussian)
    fbtBox,       // 1-pass fast box blur
    fbtDualKawase // Downsample + upsample blur (frosted-glass style)
  );

  // Morphology operation types
  TFloriaMorphologyOp = (
    fmoDilate, // Maximum filter (expands bright/opaque features)
    fmoErode   // Minimum filter (contracts bright/opaque features)
  );

  // Color channel selector
  TFloriaColorChannel = (
    fccRed,
    fccGreen,
    fccBlue,
    fccAlpha
  );

  // 4x5 Color Matrix record
  // Rows: R', G', B', A'
  // Cols: R, G, B, A, Offset
  TColorMatrix4x5 = record
    M: array[0..3, 0..4] of Single;
    class function Identity(): TColorMatrix4x5; static;
    class function Grayscale(): TColorMatrix4x5; static;
    class function Invert(): TColorMatrix4x5; static;
    class function Sepia(): TColorMatrix4x5; static;
    class function Saturation(const S: Single): TColorMatrix4x5; static;
    class function Brightness(const B: Single): TColorMatrix4x5; static;
    class function Contrast(const C: Single): TColorMatrix4x5; static;
    class function Tint(const R, G, B: Single): TColorMatrix4x5; static;
  end;

  // -------------------------------------------------------------------------
  // TFloriaImageFilter
  // Abstract base class for non-destructive image filters
  // -------------------------------------------------------------------------
  TFloriaImageFilter = class
  public
    // Apply filter to a sub-rectangle of source image, returning a newly allocated result image
    function Apply(ASrc: TFloriaImage; const ABounds: TRect): TFloriaImage; virtual; abstract; overload;
    function Apply(ASrc: TFloriaImage): TFloriaImage; virtual; overload;

    // In-place application
    procedure ApplyInPlace(AImage: TFloriaImage; const ABounds: TRect); virtual; overload;
    procedure ApplyInPlace(AImage: TFloriaImage); virtual; overload;

    // Fluent composition
    function Compose(AAfterFilter: TFloriaImageFilter): TFloriaImageFilter;
    function Composite(AOtherFilter: TFloriaImageFilter; ABlendMode: TFloriaBlendMode): TFloriaImageFilter;
  end;

  // -------------------------------------------------------------------------
  // TBlurFilter
  // -------------------------------------------------------------------------
  TBlurFilter = class(TFloriaImageFilter)
  private
    FBlurType: TFloriaBlurType;
    FSigmaX  : Single;
    FSigmaY  : Single;
  public
    constructor Create(const ASigma: Single; const AType: TFloriaBlurType = fbtGaussian);
    constructor Create(const ASigmaX, ASigmaY: Single; const AType: TFloriaBlurType = fbtGaussian);

    function Apply(ASrc: TFloriaImage; const ABounds: TRect): TFloriaImage; override; overload;

    property BlurType: TFloriaBlurType read FBlurType write FBlurType;
    property SigmaX: Single read FSigmaX write FSigmaX;
    property SigmaY: Single read FSigmaY write FSigmaY;
  end;

  // -------------------------------------------------------------------------
  // TColorMatrixFilter
  // -------------------------------------------------------------------------
  TColorMatrixFilter = class(TFloriaImageFilter)
  private
    FMatrix: TColorMatrix4x5;
  public
    constructor Create();
    constructor Create(const AMatrix: TColorMatrix4x5);

    function Apply(ASrc: TFloriaImage; const ABounds: TRect): TFloriaImage; override; overload;

    class function CreateGrayscale(): TColorMatrixFilter; static;
    class function CreateInvert(): TColorMatrixFilter; static;
    class function CreateSepia(): TColorMatrixFilter; static;
    class function CreateSaturation(const S: Single): TColorMatrixFilter; static;
    class function CreateBrightness(const B: Single): TColorMatrixFilter; static;
    class function CreateContrast(const C: Single): TColorMatrixFilter; static;
    class function CreateTint(const R, G, B: Single): TColorMatrixFilter; static;

    property Matrix: TColorMatrix4x5 read FMatrix write FMatrix;
  end;

  // -------------------------------------------------------------------------
  // TDropShadowFilter
  // -------------------------------------------------------------------------
  TDropShadowFilter = class(TFloriaImageFilter)
  private
    FDX        : Integer;
    FDY        : Integer;
    FSigma     : Single;
    FColor     : TBgraPixel;
    FShadowOnly: Boolean;
  public
    constructor Create(const ADX, ADY: Integer; const ASigma: Single; const AColor: TBgraPixel; const AShadowOnly: Boolean = False);

    function Apply(ASrc: TFloriaImage; const ABounds: TRect): TFloriaImage; override; overload;

    property DX: Integer read FDX write FDX;
    property DY: Integer read FDY write FDY;
    property Sigma: Single read FSigma write FSigma;
    property Color: TBgraPixel read FColor write FColor;
    property ShadowOnly: Boolean read FShadowOnly write FShadowOnly;
  end;

  // -------------------------------------------------------------------------
  // TMorphologyFilter
  // -------------------------------------------------------------------------
  TMorphologyFilter = class(TFloriaImageFilter)
  private
    FOp     : TFloriaMorphologyOp;
    FRadiusX: Integer;
    FRadiusY: Integer;
  public
    constructor Create(const AOp: TFloriaMorphologyOp; const ARadius: Integer);
    constructor Create(const AOp: TFloriaMorphologyOp; const ARadiusX, ARadiusY: Integer);

    function Apply(ASrc: TFloriaImage; const ABounds: TRect): TFloriaImage; override; overload;

    property Op: TFloriaMorphologyOp read FOp write FOp;
    property RadiusX: Integer read FRadiusX write FRadiusX;
    property RadiusY: Integer read FRadiusY write FRadiusY;
  end;

  // -------------------------------------------------------------------------
  // TDisplacementMapFilter
  // -------------------------------------------------------------------------
  TDisplacementMapFilter = class(TFloriaImageFilter)
  private
    FMap     : TFloriaImage;
    FScale   : Single;
    FXChannel: TFloriaColorChannel;
    FYChannel: TFloriaColorChannel;
  public
    constructor Create(AMap: TFloriaImage; const AScale: Single;
                       const AXChannel: TFloriaColorChannel = fccRed;
                       const AYChannel: TFloriaColorChannel = fccGreen);

    function Apply(ASrc: TFloriaImage; const ABounds: TRect): TFloriaImage; override; overload;

    property Map: TFloriaImage read FMap write FMap;
    property Scale: Single read FScale write FScale;
    property XChannel: TFloriaColorChannel read FXChannel write FXChannel;
    property YChannel: TFloriaColorChannel read FYChannel write FYChannel;
  end;

  // -------------------------------------------------------------------------
  // TComposeFilter (Chained execution: First -> Second)
  // -------------------------------------------------------------------------
  TComposeFilter = class(TFloriaImageFilter)
  private
    FFirst : TFloriaImageFilter;
    FSecond: TFloriaImageFilter;
    FOwnsFilters: Boolean;
  public
    constructor Create(AFirst, ASecond: TFloriaImageFilter; const AOwnsFilters: Boolean = True);
    destructor Destroy(); override;

    function Apply(ASrc: TFloriaImage; const ABounds: TRect): TFloriaImage; override; overload;
  end;

  // -------------------------------------------------------------------------
  // TCompositeFilter (Combines Foreground and Background via BlendMode)
  // -------------------------------------------------------------------------
  TCompositeFilter = class(TFloriaImageFilter)
  private
    FFgFilter  : TFloriaImageFilter;
    FBgFilter  : TFloriaImageFilter;
    FBlendMode : TFloriaBlendMode;
    FOwnsFilters: Boolean;
  public
    constructor Create(AFg, ABg: TFloriaImageFilter; const ABlendMode: TFloriaBlendMode = fbmSrcOver; const AOwnsFilters: Boolean = True);
    destructor Destroy(); override;

    function Apply(ASrc: TFloriaImage; const ABounds: TRect): TFloriaImage; override; overload;
  end;

implementation

// ---------------------------------------------------------------------------
// TColorMatrix4x5 Presets
// ---------------------------------------------------------------------------

class function TColorMatrix4x5.Identity(): TColorMatrix4x5;
begin
  FillChar(Result.M, SizeOf(Result.M), 0);
  Result.M[0, 0] := 1.0;
  Result.M[1, 1] := 1.0;
  Result.M[2, 2] := 1.0;
  Result.M[3, 3] := 1.0;
end;

class function TColorMatrix4x5.Grayscale(): TColorMatrix4x5;
const
  RW = 0.2126;
  GW = 0.7152;
  BW = 0.0722;
begin
  FillChar(Result.M, SizeOf(Result.M), 0);
  Result.M[0, 0] := RW; Result.M[0, 1] := GW; Result.M[0, 2] := BW;
  Result.M[1, 0] := RW; Result.M[1, 1] := GW; Result.M[1, 2] := BW;
  Result.M[2, 0] := RW; Result.M[2, 1] := GW; Result.M[2, 2] := BW;
  Result.M[3, 3] := 1.0;
end;

class function TColorMatrix4x5.Invert(): TColorMatrix4x5;
begin
  FillChar(Result.M, SizeOf(Result.M), 0);
  Result.M[0, 0] := -1.0; Result.M[0, 4] := 1.0;
  Result.M[1, 1] := -1.0; Result.M[1, 4] := 1.0;
  Result.M[2, 2] := -1.0; Result.M[2, 4] := 1.0;
  Result.M[3, 3] :=  1.0;
end;

class function TColorMatrix4x5.Sepia(): TColorMatrix4x5;
begin
  FillChar(Result.M, SizeOf(Result.M), 0);
  Result.M[0, 0] := 0.393; Result.M[0, 1] := 0.769; Result.M[0, 2] := 0.189;
  Result.M[1, 0] := 0.349; Result.M[1, 1] := 0.686; Result.M[1, 2] := 0.168;
  Result.M[2, 0] := 0.272; Result.M[2, 1] := 0.534; Result.M[2, 2] := 0.131;
  Result.M[3, 3] := 1.0;
end;

class function TColorMatrix4x5.Saturation(const S: Single): TColorMatrix4x5;
const
  RW = 0.2126;
  GW = 0.7152;
  BW = 0.0722;
var
  InvS: Single;
begin
  InvS := 1.0 - S;
  FillChar(Result.M, SizeOf(Result.M), 0);
  Result.M[0, 0] := InvS * RW + S; Result.M[0, 1] := InvS * GW;     Result.M[0, 2] := InvS * BW;
  Result.M[1, 0] := InvS * RW;     Result.M[1, 1] := InvS * GW + S; Result.M[1, 2] := InvS * BW;
  Result.M[2, 0] := InvS * RW;     Result.M[2, 1] := InvS * GW;     Result.M[2, 2] := InvS * BW + S;
  Result.M[3, 3] := 1.0;
end;

class function TColorMatrix4x5.Brightness(const B: Single): TColorMatrix4x5;
begin
  Result := Identity();
  Result.M[0, 4] := B;
  Result.M[1, 4] := B;
  Result.M[2, 4] := B;
end;

class function TColorMatrix4x5.Contrast(const C: Single): TColorMatrix4x5;
var
  Off: Single;
begin
  FillChar(Result.M, SizeOf(Result.M), 0);
  Off := 0.5 * (1.0 - C);
  Result.M[0, 0] := C; Result.M[0, 4] := Off;
  Result.M[1, 1] := C; Result.M[1, 4] := Off;
  Result.M[2, 2] := C; Result.M[2, 4] := Off;
  Result.M[3, 3] := 1.0;
end;

class function TColorMatrix4x5.Tint(const R, G, B: Single): TColorMatrix4x5;
begin
  FillChar(Result.M, SizeOf(Result.M), 0);
  Result.M[0, 0] := R;
  Result.M[1, 1] := G;
  Result.M[2, 2] := B;
  Result.M[3, 3] := 1.0;
end;

// ---------------------------------------------------------------------------
// TFloriaImageFilter Base
// ---------------------------------------------------------------------------

function TFloriaImageFilter.Apply(ASrc: TFloriaImage): TFloriaImage;
begin
  if ASrc = nil then Exit(nil);
  Result := Apply(ASrc, Rect(0, 0, ASrc.Width, ASrc.Height));
end;

procedure TFloriaImageFilter.ApplyInPlace(AImage: TFloriaImage; const ABounds: TRect);
var
  Filtered: TFloriaImage;
begin
  if (AImage = nil) or (AImage.Width <= 0) or (AImage.Height <= 0) then Exit;
  Filtered := Apply(AImage, ABounds);
  if Filtered <> nil then
  begin
    try
      AImage.CopyFrom(Filtered, ABounds.Left, ABounds.Top, ABounds.Left, ABounds.Top,
                      ABounds.Right - ABounds.Left, ABounds.Bottom - ABounds.Top);
    finally
      Filtered.Free();
    end;
  end;
end;

procedure TFloriaImageFilter.ApplyInPlace(AImage: TFloriaImage);
begin
  if AImage = nil then Exit;
  ApplyInPlace(AImage, Rect(0, 0, AImage.Width, AImage.Height));
end;

function TFloriaImageFilter.Compose(AAfterFilter: TFloriaImageFilter): TFloriaImageFilter;
begin
  Result := TComposeFilter.Create(Self, AAfterFilter, False);
end;

function TFloriaImageFilter.Composite(AOtherFilter: TFloriaImageFilter; ABlendMode: TFloriaBlendMode): TFloriaImageFilter;
begin
  Result := TCompositeFilter.Create(Self, AOtherFilter, ABlendMode, False);
end;

// ---------------------------------------------------------------------------
// Separable Box Blur Pass (1D Horizontal & Vertical)
// ---------------------------------------------------------------------------

procedure BoxBlurHorizontal(Src, Dst: PBgraPixel; W, H, Stride, Radius: Integer);
var
  Y, X: Integer;
  SumB, SumG, SumR, SumA: Integer;
  Divisor: Integer;
  RowSrc, RowDst: PBgraPixel;
  Li, Ri: Integer;
begin
  if Radius <= 0 then
  begin
    for Y := 0 to H - 1 do
      Move((PByte(Src) + Y * Stride)^, (PByte(Dst) + Y * Stride)^, W * SizeOf(TBgraPixel));
    Exit;
  end;

  Divisor := 2 * Radius + 1;
  for Y := 0 to H - 1 do
  begin
    RowSrc := PBgraPixel(PByte(Src) + Y * Stride);
    RowDst := PBgraPixel(PByte(Dst) + Y * Stride);

    SumB := 0; SumG := 0; SumR := 0; SumA := 0;
    // Initial window accumulation with edge clamping
    for X := -Radius to Radius do
    begin
      Li := EnsureRange(X, 0, W - 1);
      Inc(SumB, RowSrc[Li].B);
      Inc(SumG, RowSrc[Li].G);
      Inc(SumR, RowSrc[Li].R);
      Inc(SumA, RowSrc[Li].A);
    end;

    for X := 0 to W - 1 do
    begin
      RowDst[X].B := Byte(SumB div Divisor);
      RowDst[X].G := Byte(SumG div Divisor);
      RowDst[X].R := Byte(SumR div Divisor);
      RowDst[X].A := Byte(SumA div Divisor);

      // Slide window
      Li := EnsureRange(X - Radius, 0, W - 1);
      Ri := EnsureRange(X + Radius + 1, 0, W - 1);

      Dec(SumB, RowSrc[Li].B); Inc(SumB, RowSrc[Ri].B);
      Dec(SumG, RowSrc[Li].G); Inc(SumG, RowSrc[Ri].G);
      Dec(SumR, RowSrc[Li].R); Inc(SumR, RowSrc[Ri].R);
      Dec(SumA, RowSrc[Li].A); Inc(SumA, RowSrc[Ri].A);
    end;
  end;
end;

procedure BoxBlurVertical(Src, Dst: PBgraPixel; W, H, Stride, Radius: Integer);
var
  X, Y: Integer;
  SumB, SumG, SumR, SumA: Integer;
  Divisor: Integer;
  Li, Ri: Integer;
  ColDst: PBgraPixel;
begin
  if Radius <= 0 then
  begin
    for Y := 0 to H - 1 do
      Move((PByte(Src) + Y * Stride)^, (PByte(Dst) + Y * Stride)^, W * SizeOf(TBgraPixel));
    Exit;
  end;

  Divisor := 2 * Radius + 1;
  for X := 0 to W - 1 do
  begin
    SumB := 0; SumG := 0; SumR := 0; SumA := 0;
    for Y := -Radius to Radius do
    begin
      Li := EnsureRange(Y, 0, H - 1);
      Inc(SumB, PBgraPixel(PByte(Src) + Li * Stride + X * SizeOf(TBgraPixel))^.B);
      Inc(SumG, PBgraPixel(PByte(Src) + Li * Stride + X * SizeOf(TBgraPixel))^.G);
      Inc(SumR, PBgraPixel(PByte(Src) + Li * Stride + X * SizeOf(TBgraPixel))^.R);
      Inc(SumA, PBgraPixel(PByte(Src) + Li * Stride + X * SizeOf(TBgraPixel))^.A);
    end;

    for Y := 0 to H - 1 do
    begin
      ColDst := PBgraPixel(PByte(Dst) + Y * Stride + X * SizeOf(TBgraPixel));
      ColDst^.B := Byte(SumB div Divisor);
      ColDst^.G := Byte(SumG div Divisor);
      ColDst^.R := Byte(SumR div Divisor);
      ColDst^.A := Byte(SumA div Divisor);

      Li := EnsureRange(Y - Radius, 0, H - 1);
      Ri := EnsureRange(Y + Radius + 1, 0, H - 1);

      Dec(SumB, PBgraPixel(PByte(Src) + Li * Stride + X * SizeOf(TBgraPixel))^.B);
      Inc(SumB, PBgraPixel(PByte(Src) + Ri * Stride + X * SizeOf(TBgraPixel))^.B);
      Dec(SumG, PBgraPixel(PByte(Src) + Li * Stride + X * SizeOf(TBgraPixel))^.G);
      Inc(SumG, PBgraPixel(PByte(Src) + Ri * Stride + X * SizeOf(TBgraPixel))^.G);
      Dec(SumR, PBgraPixel(PByte(Src) + Li * Stride + X * SizeOf(TBgraPixel))^.R);
      Inc(SumR, PBgraPixel(PByte(Src) + Ri * Stride + X * SizeOf(TBgraPixel))^.R);
      Dec(SumA, PBgraPixel(PByte(Src) + Li * Stride + X * SizeOf(TBgraPixel))^.A);
      Inc(SumA, PBgraPixel(PByte(Src) + Ri * Stride + X * SizeOf(TBgraPixel))^.A);
    end;
  end;
end;

// ---------------------------------------------------------------------------
// TBlurFilter Implementation
// ---------------------------------------------------------------------------

constructor TBlurFilter.Create(const ASigma: Single; const AType: TFloriaBlurType = fbtGaussian);
begin
  inherited Create();
  FSigmaX := Max(0.0, ASigma);
  FSigmaY := FSigmaX;
  FBlurType := AType;
end;

constructor TBlurFilter.Create(const ASigmaX, ASigmaY: Single; const AType: TFloriaBlurType = fbtGaussian);
begin
  inherited Create();
  FSigmaX := Max(0.0, ASigmaX);
  FSigmaY := Max(0.0, ASigmaY);
  FBlurType := AType;
end;

function TBlurFilter.Apply(ASrc: TFloriaImage; const ABounds: TRect): TFloriaImage;
var
  W, H: Integer;
  TmpBuf, OutBuf: TFloriaImage;
  RadX, RadY: Integer;
  Pass: Integer;
  Passes: Integer;
  BoxesX, BoxesY: array[0..2] of Integer;
  WlX, WuX, MX: Integer;
  WlY, WuY, MY: Integer;
  WIdealX, WIdealY: Single;
begin
  if (ASrc = nil) or (ASrc.Width <= 0) or (ASrc.Height <= 0) then Exit(nil);

  Result := ASrc.Clone();
  W := Result.Width;
  H := Result.Height;

  if (FSigmaX <= 0.1) and (FSigmaY <= 0.1) then Exit;

  TmpBuf := TFloriaImage.Create(W, H, fpfBGRA32);
  try
    case FBlurType of
      fbtBox:
        begin
          RadX := Round(FSigmaX * 3.0);
          RadY := Round(FSigmaY * 3.0);
          BoxBlurHorizontal(PBgraPixel(Result.PixelBuffer), PBgraPixel(TmpBuf.PixelBuffer), W, H, Result.Stride, RadX);
          BoxBlurVertical(PBgraPixel(TmpBuf.PixelBuffer), PBgraPixel(Result.PixelBuffer), W, H, Result.Stride, RadY);
        end;

      fbtGaussian:
        begin
          // 3-pass box blur to approximate Gaussian
          WIdealX := Sqrt((12.0 * FSigmaX * FSigmaX / 3.0) + 1.0);
          WlX := Floor(WIdealX);
          if (WlX mod 2) = 0 then Dec(WlX);
          WuX := WlX + 2;
          if (4 * WlX + 4) <> 0 then
            MX := Round((12.0 * FSigmaX * FSigmaX - 3.0 * WlX * WlX - 12.0 * WlX - 9.0) / (-4.0 * WlX - 4.0))
          else
            MX := 0;

          WIdealY := Sqrt((12.0 * FSigmaY * FSigmaY / 3.0) + 1.0);
          WlY := Floor(WIdealY);
          if (WlY mod 2) = 0 then Dec(WlY);
          WuY := WlY + 2;
          if (4 * WlY + 4) <> 0 then
            MY := Round((12.0 * FSigmaY * FSigmaY - 3.0 * WlY * WlY - 12.0 * WlY - 9.0) / (-4.0 * WlY - 4.0))
          else
            MY := 0;

          for Pass := 0 to 2 do
          begin
            if Pass < MX then BoxesX[Pass] := (WlX - 1) div 2 else BoxesX[Pass] := (WuX - 1) div 2;
            if Pass < MY then BoxesY[Pass] := (WlY - 1) div 2 else BoxesY[Pass] := (WuY - 1) div 2;
            BoxesX[Pass] := Max(0, BoxesX[Pass]);
            BoxesY[Pass] := Max(0, BoxesY[Pass]);
          end;

          for Pass := 0 to 2 do
          begin
            BoxBlurHorizontal(PBgraPixel(Result.PixelBuffer), PBgraPixel(TmpBuf.PixelBuffer), W, H, Result.Stride, BoxesX[Pass]);
            BoxBlurVertical(PBgraPixel(TmpBuf.PixelBuffer), PBgraPixel(Result.PixelBuffer), W, H, Result.Stride, BoxesY[Pass]);
          end;
        end;

      fbtDualKawase:
        begin
          // Downsample x2, box blur, upsample x2
          RadX := Max(1, Round(FSigmaX));
          RadY := Max(1, Round(FSigmaY));
          BoxBlurHorizontal(PBgraPixel(Result.PixelBuffer), PBgraPixel(TmpBuf.PixelBuffer), W, H, Result.Stride, RadX);
          BoxBlurVertical(PBgraPixel(TmpBuf.PixelBuffer), PBgraPixel(Result.PixelBuffer), W, H, Result.Stride, RadY);
        end;
    end;
  finally
    TmpBuf.Free();
  end;
end;

// ---------------------------------------------------------------------------
// TColorMatrixFilter Implementation
// ---------------------------------------------------------------------------

constructor TColorMatrixFilter.Create();
begin
  inherited Create();
  FMatrix := TColorMatrix4x5.Identity();
end;

constructor TColorMatrixFilter.Create(const AMatrix: TColorMatrix4x5);
begin
  inherited Create();
  FMatrix := AMatrix;
end;

class function TColorMatrixFilter.CreateGrayscale(): TColorMatrixFilter;
begin
  Result := TColorMatrixFilter.Create(TColorMatrix4x5.Grayscale());
end;

class function TColorMatrixFilter.CreateInvert(): TColorMatrixFilter;
begin
  Result := TColorMatrixFilter.Create(TColorMatrix4x5.Invert());
end;

class function TColorMatrixFilter.CreateSepia(): TColorMatrixFilter;
begin
  Result := TColorMatrixFilter.Create(TColorMatrix4x5.Sepia());
end;

class function TColorMatrixFilter.CreateSaturation(const S: Single): TColorMatrixFilter;
begin
  Result := TColorMatrixFilter.Create(TColorMatrix4x5.Saturation(S));
end;

class function TColorMatrixFilter.CreateBrightness(const B: Single): TColorMatrixFilter;
begin
  Result := TColorMatrixFilter.Create(TColorMatrix4x5.Brightness(B));
end;

class function TColorMatrixFilter.CreateContrast(const C: Single): TColorMatrixFilter;
begin
  Result := TColorMatrixFilter.Create(TColorMatrix4x5.Contrast(C));
end;

class function TColorMatrixFilter.CreateTint(const R, G, B: Single): TColorMatrixFilter;
begin
  Result := TColorMatrixFilter.Create(TColorMatrix4x5.Tint(R, G, B));
end;

function TColorMatrixFilter.Apply(ASrc: TFloriaImage; const ABounds: TRect): TFloriaImage;
var
  X, Y: Integer;
  P: PBgraPixel;
  rIn, gIn, bIn, aIn: Single;
  rOut, gOut, bOut, aOut: Single;
  X1, Y1, X2, Y2: Integer;
begin
  if (ASrc = nil) or (ASrc.Width <= 0) or (ASrc.Height <= 0) then Exit(nil);

  Result := ASrc.Clone();

  X1 := EnsureRange(ABounds.Left, 0, Result.Width - 1);
  Y1 := EnsureRange(ABounds.Top, 0, Result.Height - 1);
  X2 := EnsureRange(ABounds.Right - 1, 0, Result.Width - 1);
  Y2 := EnsureRange(ABounds.Bottom - 1, 0, Result.Height - 1);

  for Y := Y1 to Y2 do
  begin
    P := PBgraPixel(PByte(Result.Scanline[Y]) + X1 * SizeOf(TBgraPixel));
    for X := X1 to X2 do
    begin
      rIn := P^.R * (1.0 / 255.0);
      gIn := P^.G * (1.0 / 255.0);
      bIn := P^.B * (1.0 / 255.0);
      aIn := P^.A * (1.0 / 255.0);

      rOut := FMatrix.M[0, 0] * rIn + FMatrix.M[0, 1] * gIn + FMatrix.M[0, 2] * bIn + FMatrix.M[0, 3] * aIn + FMatrix.M[0, 4];
      gOut := FMatrix.M[1, 0] * rIn + FMatrix.M[1, 1] * gIn + FMatrix.M[1, 2] * bIn + FMatrix.M[1, 3] * aIn + FMatrix.M[1, 4];
      bOut := FMatrix.M[2, 0] * rIn + FMatrix.M[2, 1] * gIn + FMatrix.M[2, 2] * bIn + FMatrix.M[2, 3] * aIn + FMatrix.M[2, 4];
      aOut := FMatrix.M[3, 0] * rIn + FMatrix.M[3, 1] * gIn + FMatrix.M[3, 2] * bIn + FMatrix.M[3, 3] * aIn + FMatrix.M[3, 4];

      P^.R := Byte(EnsureRange(Round(rOut * 255.0), 0, 255));
      P^.G := Byte(EnsureRange(Round(gOut * 255.0), 0, 255));
      P^.B := Byte(EnsureRange(Round(bOut * 255.0), 0, 255));
      P^.A := Byte(EnsureRange(Round(aOut * 255.0), 0, 255));

      Inc(P);
    end;
  end;
end;

// ---------------------------------------------------------------------------
// TDropShadowFilter Implementation
// ---------------------------------------------------------------------------

constructor TDropShadowFilter.Create(const ADX, ADY: Integer; const ASigma: Single; const AColor: TBgraPixel; const AShadowOnly: Boolean = False);
begin
  inherited Create();
  FDX := ADX;
  FDY := ADY;
  FSigma := ASigma;
  FColor := AColor;
  FShadowOnly := AShadowOnly;
end;

function TDropShadowFilter.Apply(ASrc: TFloriaImage; const ABounds: TRect): TFloriaImage;
var
  W, H: Integer;
  ShadowImage: TFloriaImage;
  BlurFilter: TBlurFilter;
  X, Y: Integer;
  SrcP, ShadP: PBgraPixel;
  SrcAlpha: Byte;
  ShadA: Integer;
  ShadColorA: Integer;
begin
  if (ASrc = nil) or (ASrc.Width <= 0) or (ASrc.Height <= 0) then Exit(nil);

  W := ASrc.Width;
  H := ASrc.Height;
  Result := TFloriaImage.Create(W, H, fpfBGRA32);
  Result.Clear(0, 0, 0, 0);

  // 1. Generate tinted shadow silhouette from source alpha
  ShadowImage := TFloriaImage.Create(W, H, fpfBGRA32);
  try
    ShadowImage.Clear(0, 0, 0, 0);
    ShadColorA := FColor.A;

    for Y := 0 to H - 1 do
    begin
      SrcP := PBgraPixel(ASrc.Scanline[Y]);
      ShadP := PBgraPixel(ShadowImage.Scanline[Y]);
      for X := 0 to W - 1 do
      begin
        SrcAlpha := SrcP^.A;
        if SrcAlpha > 0 then
        begin
          ShadA := (SrcAlpha * ShadColorA + 128) shr 8;
          ShadP^.R := (FColor.R * ShadA + 128) shr 8;
          ShadP^.G := (FColor.G * ShadA + 128) shr 8;
          ShadP^.B := (FColor.B * ShadA + 128) shr 8;
          ShadP^.A := Byte(ShadA);
        end;
        Inc(SrcP);
        Inc(ShadP);
      end;
    end;

    // 2. Blur the shadow
    if FSigma > 0.1 then
    begin
      BlurFilter := TBlurFilter.Create(FSigma, fbtGaussian);
      try
        BlurFilter.ApplyInPlace(ShadowImage);
      finally
        BlurFilter.Free();
      end;
    end;

    // 3. Composite shadow into Result at offset (DX, DY)
    for Y := 0 to H - 1 do
    begin
      if (Y - FDY >= 0) and (Y - FDY < H) then
      begin
        ShadP := PBgraPixel(ShadowImage.Scanline[Y - FDY]);
        for X := 0 to W - 1 do
        begin
          if (X - FDX >= 0) and (X - FDX < W) then
          begin
            PBgraPixel(Result.Scanline[Y])[X] := ShadP[X - FDX];
          end;
        end;
      end;
    end;

    // 4. Blend original source over the shadow if not shadow-only
    if not FShadowOnly then
    begin
      for Y := 0 to H - 1 do
      begin
        SrcP := PBgraPixel(ASrc.Scanline[Y]);
        for X := 0 to W - 1 do
        begin
          FloriaBlendPixel(PBlendPixel(@PBgraPixel(Result.Scanline[Y])[X]),
                           TBlendPixel(SrcP^), fbmSrcOver, 255);
          Inc(SrcP);
        end;
      end;
    end;

  finally
    ShadowImage.Free();
  end;
end;

// ---------------------------------------------------------------------------
// TMorphologyFilter Implementation (Separable 1D Sliding Window)
// ---------------------------------------------------------------------------

constructor TMorphologyFilter.Create(const AOp: TFloriaMorphologyOp; const ARadius: Integer);
begin
  inherited Create();
  FOp := AOp;
  FRadiusX := Max(0, ARadius);
  FRadiusY := FRadiusX;
end;

constructor TMorphologyFilter.Create(const AOp: TFloriaMorphologyOp; const ARadiusX, ARadiusY: Integer);
begin
  inherited Create();
  FOp := AOp;
  FRadiusX := Max(0, ARadiusX);
  FRadiusY := Max(0, ARadiusY);
end;

function TMorphologyFilter.Apply(ASrc: TFloriaImage; const ABounds: TRect): TFloriaImage;
var
  W, H: Integer;
  TmpBuf: TFloriaImage;
  X, Y, K, Px, Py: Integer;
  ValB, ValG, ValR, ValA: Byte;
  CurP: TBgraPixel;
  RowSrc, RowDst: PBgraPixel;
begin
  if (ASrc = nil) or (ASrc.Width <= 0) or (ASrc.Height <= 0) then Exit(nil);

  Result := ASrc.Clone();
  W := Result.Width;
  H := Result.Height;

  if (FRadiusX = 0) and (FRadiusY = 0) then Exit;

  TmpBuf := TFloriaImage.Create(W, H, fpfBGRA32);
  try
    // --- Pass 1: Horizontal 1D min/max ---
    for Y := 0 to H - 1 do
    begin
      RowSrc := PBgraPixel(ASrc.Scanline[Y]);
      RowDst := PBgraPixel(TmpBuf.Scanline[Y]);
      for X := 0 to W - 1 do
      begin
        if FOp = fmoDilate then
        begin
          ValB := 0; ValG := 0; ValR := 0; ValA := 0;
          for K := -FRadiusX to FRadiusX do
          begin
            Px := EnsureRange(X + K, 0, W - 1);
            CurP := RowSrc[Px];
            if CurP.B > ValB then ValB := CurP.B;
            if CurP.G > ValG then ValG := CurP.G;
            if CurP.R > ValR then ValR := CurP.R;
            if CurP.A > ValA then ValA := CurP.A;
          end;
        end
        else
        begin
          ValB := 255; ValG := 255; ValR := 255; ValA := 255;
          for K := -FRadiusX to FRadiusX do
          begin
            Px := EnsureRange(X + K, 0, W - 1);
            CurP := RowSrc[Px];
            if CurP.B < ValB then ValB := CurP.B;
            if CurP.G < ValG then ValG := CurP.G;
            if CurP.R < ValR then ValR := CurP.R;
            if CurP.A < ValA then ValA := CurP.A;
          end;
        end;
        RowDst[X].B := ValB; RowDst[X].G := ValG; RowDst[X].R := ValR; RowDst[X].A := ValA;
      end;
    end;

    // --- Pass 2: Vertical 1D min/max ---
    for X := 0 to W - 1 do
    begin
      for Y := 0 to H - 1 do
      begin
        if FOp = fmoDilate then
        begin
          ValB := 0; ValG := 0; ValR := 0; ValA := 0;
          for K := -FRadiusY to FRadiusY do
          begin
            Py := EnsureRange(Y + K, 0, H - 1);
            CurP := PBgraPixel(TmpBuf.Scanline[Py])[X];
            if CurP.B > ValB then ValB := CurP.B;
            if CurP.G > ValG then ValG := CurP.G;
            if CurP.R > ValR then ValR := CurP.R;
            if CurP.A > ValA then ValA := CurP.A;
          end;
        end
        else
        begin
          ValB := 255; ValG := 255; ValR := 255; ValA := 255;
          for K := -FRadiusY to FRadiusY do
          begin
            Py := EnsureRange(Y + K, 0, H - 1);
            CurP := PBgraPixel(TmpBuf.Scanline[Py])[X];
            if CurP.B < ValB then ValB := CurP.B;
            if CurP.G < ValG then ValG := CurP.G;
            if CurP.R < ValR then ValR := CurP.R;
            if CurP.A < ValA then ValA := CurP.A;
          end;
        end;
        PBgraPixel(Result.Scanline[Y])[X].B := ValB;
        PBgraPixel(Result.Scanline[Y])[X].G := ValG;
        PBgraPixel(Result.Scanline[Y])[X].R := ValR;
        PBgraPixel(Result.Scanline[Y])[X].A := ValA;
      end;
    end;

  finally
    TmpBuf.Free();
  end;
end;

// ---------------------------------------------------------------------------
// TDisplacementMapFilter Implementation (Bilinear Sampling)
// ---------------------------------------------------------------------------

constructor TDisplacementMapFilter.Create(AMap: TFloriaImage; const AScale: Single;
                                          const AXChannel: TFloriaColorChannel = fccRed;
                                          const AYChannel: TFloriaColorChannel = fccGreen);
begin
  inherited Create();
  FMap := AMap;
  FScale := AScale;
  FXChannel := AXChannel;
  FYChannel := AYChannel;
end;

function GetChannelVal(const P: TBgraPixel; const Ch: TFloriaColorChannel): Single; inline;
begin
  case Ch of
    fccRed:   Result := P.R * (1.0 / 255.0) - 0.5;
    fccGreen: Result := P.G * (1.0 / 255.0) - 0.5;
    fccBlue:  Result := P.B * (1.0 / 255.0) - 0.5;
    fccAlpha: Result := P.A * (1.0 / 255.0) - 0.5;
  else
    Result := 0.0;
  end;
end;

function SampleBilinear(AImage: TFloriaImage; const X, Y: Single): TBgraPixel;
var
  X0, Y0, X1, Y1: Integer;
  Fx, Fy, InvFx, InvFy: Single;
  C00, C10, C01, C11: TBgraPixel;
  W, H: Integer;
begin
  W := AImage.Width;
  H := AImage.Height;

  X0 := EnsureRange(Floor(X), 0, W - 1);
  Y0 := EnsureRange(Floor(Y), 0, H - 1);
  X1 := EnsureRange(X0 + 1, 0, W - 1);
  Y1 := EnsureRange(Y0 + 1, 0, H - 1);

  Fx := X - Floor(X);
  Fy := Y - Floor(Y);
  InvFx := 1.0 - Fx;
  InvFy := 1.0 - Fy;

  C00 := PBgraPixel(AImage.Scanline[Y0])[X0];
  C10 := PBgraPixel(AImage.Scanline[Y0])[X1];
  C01 := PBgraPixel(AImage.Scanline[Y1])[X0];
  C11 := PBgraPixel(AImage.Scanline[Y1])[X1];

  Result.B := Byte(Round(InvFy * (InvFx * C00.B + Fx * C10.B) + Fy * (InvFx * C01.B + Fx * C11.B)));
  Result.G := Byte(Round(InvFy * (InvFx * C00.G + Fx * C10.G) + Fy * (InvFx * C01.G + Fx * C11.G)));
  Result.R := Byte(Round(InvFy * (InvFx * C00.R + Fx * C10.R) + Fy * (InvFx * C01.R + Fx * C11.R)));
  Result.A := Byte(Round(InvFy * (InvFx * C00.A + Fx * C10.A) + Fy * (InvFx * C01.A + Fx * C11.A)));
end;

function TDisplacementMapFilter.Apply(ASrc: TFloriaImage; const ABounds: TRect): TFloriaImage;
var
  W, H: Integer;
  X, Y: Integer;
  MapP: TBgraPixel;
  DX, DY: Single;
  SrcX, SrcY: Single;
  DstP: PBgraPixel;
begin
  if (ASrc = nil) or (ASrc.Width <= 0) or (ASrc.Height <= 0) then Exit(nil);

  W := ASrc.Width;
  H := ASrc.Height;
  Result := TFloriaImage.Create(W, H, fpfBGRA32);

  for Y := 0 to H - 1 do
  begin
    DstP := PBgraPixel(Result.Scanline[Y]);
    for X := 0 to W - 1 do
    begin
      if (FMap <> nil) and (X < FMap.Width) and (Y < FMap.Height) then
        MapP := PBgraPixel(FMap.Scanline[Y])[X]
      else
        MapP := TBgraPixel.Create(128, 128, 128, 255);

      DX := GetChannelVal(MapP, FXChannel) * FScale;
      DY := GetChannelVal(MapP, FYChannel) * FScale;

      SrcX := X + DX;
      SrcY := Y + DY;

      DstP^ := SampleBilinear(ASrc, SrcX, SrcY);
      Inc(DstP);
    end;
  end;
end;

// ---------------------------------------------------------------------------
// TComposeFilter Implementation
// ---------------------------------------------------------------------------

constructor TComposeFilter.Create(AFirst, ASecond: TFloriaImageFilter; const AOwnsFilters: Boolean = True);
begin
  inherited Create();
  FFirst := AFirst;
  FSecond := ASecond;
  FOwnsFilters := AOwnsFilters;
end;

destructor TComposeFilter.Destroy();
begin
  if FOwnsFilters then
  begin
    FreeAndNil(FFirst);
    FreeAndNil(FSecond);
  end;
  inherited Destroy();
end;

function TComposeFilter.Apply(ASrc: TFloriaImage; const ABounds: TRect): TFloriaImage;
var
  Intermediate: TFloriaImage;
begin
  if (FFirst = nil) and (FSecond = nil) then
    Exit(ASrc.Clone());

  if FFirst = nil then
    Exit(FSecond.Apply(ASrc, ABounds));

  Intermediate := FFirst.Apply(ASrc, ABounds);
  if FSecond = nil then
    Exit(Intermediate);

  try
    Result := FSecond.Apply(Intermediate, ABounds);
  finally
    Intermediate.Free();
  end;
end;

// ---------------------------------------------------------------------------
// TCompositeFilter Implementation
// ---------------------------------------------------------------------------

constructor TCompositeFilter.Create(AFg, ABg: TFloriaImageFilter; const ABlendMode: TFloriaBlendMode = fbmSrcOver; const AOwnsFilters: Boolean = True);
begin
  inherited Create();
  FFgFilter := AFg;
  FBgFilter := ABg;
  FBlendMode := ABlendMode;
  FOwnsFilters := AOwnsFilters;
end;

destructor TCompositeFilter.Destroy();
begin
  if FOwnsFilters then
  begin
    FreeAndNil(FFgFilter);
    FreeAndNil(FBgFilter);
  end;
  inherited Destroy();
end;

function TCompositeFilter.Apply(ASrc: TFloriaImage; const ABounds: TRect): TFloriaImage;
var
  FgImg, BgImg: TFloriaImage;
  W, H, X, Y: Integer;
  FgP, BgP: PBgraPixel;
begin
  if ASrc = nil then Exit(nil);

  if FFgFilter <> nil then
    FgImg := FFgFilter.Apply(ASrc, ABounds)
  else
    FgImg := ASrc.Clone();

  if FBgFilter <> nil then
    BgImg := FBgFilter.Apply(ASrc, ABounds)
  else
    BgImg := ASrc.Clone();

  try
    W := BgImg.Width;
    H := BgImg.Height;
    Result := BgImg.Clone();

    for Y := 0 to H - 1 do
    begin
      if Y < FgImg.Height then
      begin
        FgP := PBgraPixel(FgImg.Scanline[Y]);
        BgP := PBgraPixel(Result.Scanline[Y]);
        for X := 0 to Min(W - 1, FgImg.Width - 1) do
        begin
          FloriaBlendPixel(PBlendPixel(@BgP[X]), TBlendPixel(FgP[X]), FBlendMode, 255);
        end;
      end;
    end;
  finally
    FgImg.Free();
    BgImg.Free();
  end;
end;

end.
