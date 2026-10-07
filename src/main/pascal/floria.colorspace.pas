unit Floria.ColorSpace;

// Floria.ColorSpace
// =================
// Advanced color management, color spaces, high-precision float pixel formats,
// and linear-light blending pipeline for Florialib.
//
// Key Features:
//   1. Color Spaces:
//      - sRGB (IEC 61966-2-1)
//      - Linear sRGB (Rec. 709 primaries with linear transfer function)
//      - Apple Display P3 (P3 primaries, D65 white point, sRGB transfer function)
//      - ITU-R BT.2020 (Rec. 2020 wide color gamut)
//      - Adobe RGB (1998) (Wide gamut, gamma 2.2)
//   2. Transfer Functions:
//      - Linear: f(x) = x
//      - sRGB piecewise curve (IEC 61966-2-1)
//      - Gamma 2.2 and Gamma 2.8 power curves
//      - SMPTE ST 2084 PQ (Perceptual Quantizer / HDR10)
//      - ITU-R BT.2100 HLG (Hybrid Log-Gamma)
//   3. High-Precision Pixel Records:
//      - TRgbaF32: 128-bit single-precision float (32 bits per channel)
//      - TRgbaF16: 64-bit half-precision float (16 bits per channel IEEE 754 binary16)
//      - Exact IEEE 754 half-precision float conversion (FloatToHalf, HalfToFloat)
//   4. Colorimetric Conversions:
//      - CIE 1931 xy chromaticity coordinates & D65 white point
//      - 3x3 RGB <-> CIE 1931 XYZ conversion matrices
//      - Direct gamut-to-gamut transformations
//   5. Linear-Light Blending & Anti-Aliasing:
//      - All 29 W3C/Skia blend modes evaluated in linear light
//      - Eliminates dark fringing (muddy halo) on anti-aliased edges and text
//      - Fast precomputed sRGB-to-linear LUT (GSRGBToLinearLUT)
//      - High-performance scanline blending

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  Classes, SysUtils, Math,
  Floria.Image.Core,
  Floria.Canvas.Blend;

type
  // Enumeration of supported standard color spaces
  TFloriaColorSpaceType = (
    fcstSRGB,        // Standard sRGB (IEC 61966-2-1)
    fcstLinearSRGB,  // Linear sRGB (Rec. 709 primaries with linear transfer function)
    fcstDisplayP3,   // Apple Display P3 (D65 white point, sRGB transfer curve)
    fcstRec2020,     // ITU-R BT.2020 (UHDTV wide gamut)
    fcstAdobeRGB     // Adobe RGB (1998) (Wide gamut, gamma 2.2)
  );

  // Transfer function enumeration
  TFloriaTransferFunction = (
    ftfLinear,   // Linear: f(x) = x
    ftfSRGB,     // sRGB piecewise curve (IEC 61966-2-1)
    ftfGamma22,  // Pure power curve 2.2
    ftfGamma28,  // Pure power curve 2.8
    ftfPQ,       // Perceptual Quantizer (SMPTE ST 2084 / HDR10)
    ftfHLG       // Hybrid Log-Gamma (ITU-R BT.2100)
  );

  // CIE 1931 2D chromaticity coordinate (x, y)
  TCIEPoint = record
    X: Single;
    Y: Single;
    class function Create(const AX, AY: Single): TCIEPoint; static;
  end;

  // CIE 1931 color primaries (Red, Green, Blue) and White Point
  TColorPrimaries = record
    Red: TCIEPoint;
    Green: TCIEPoint;
    Blue: TCIEPoint;
    White: TCIEPoint;
    class function Create(const ARed, AGreen, ABlue, AWhite: TCIEPoint): TColorPrimaries; static;
  end;

  // CIE 1931 XYZ tristimulus values
  TColorXYZ = record
    X: Single;
    Y: Single;
    Z: Single;
    class function Create(const AX, AY, AZ: Single): TColorXYZ; static;
  end;

  // 3x3 Matrix for color space conversions
  TMatrix3x3 = record
    M: array[0..2, 0..2] of Single;
    class function Identity(): TMatrix3x3; static;
    function Multiply(const B: TMatrix3x3): TMatrix3x3;
    function TransformVector(const X, Y, Z: Single; out OX, OY, OZ: Single): Boolean;
    function Invert(out Inv: TMatrix3x3): Boolean;
  end;

  // 128-bit Single-Precision Float RGBA pixel (32 bits per channel)
  // Channels are normalized 0.0 .. 1.0 (or > 1.0 for HDR / Wide Gamut)
  TRgbaF32 = packed record
    R: Single;
    G: Single;
    B: Single;
    A: Single;
    class function Create(const AR, AG, AB: Single; const AA: Single = 1.0): TRgbaF32; static;
    class function FromBgra(const P: TBgraPixel): TRgbaF32; static;
    class function FromBgraLinear(const P: TBgraPixel): TRgbaF32; static;
    function ToBgra(): TBgraPixel;
    function ToBgraLinear(): TBgraPixel;
    function Premultiply(): TRgbaF32;
    function Demultiply(): TRgbaF32;
    function Clamp(): TRgbaF32;
  end;
  PRgbaF32 = ^TRgbaF32;

  // 64-bit Half-Precision Float RGBA pixel (16 bits per channel IEEE 754 binary16)
  TRgbaF16 = packed record
    R: Word;
    G: Word;
    B: Word;
    A: Word;
    class function Create(const AR, AG, AB: Single; const AA: Single = 1.0): TRgbaF16; static;
    class function FromF32(const P: TRgbaF32): TRgbaF16; static;
    function ToF32(): TRgbaF32;
    class function FromBgra(const P: TBgraPixel): TRgbaF16; static;
    function ToBgra(): TBgraPixel;
  end;
  PRgbaF16 = ^TRgbaF16;

  // TFloriaColorSpace
  // Encapsulates chromaticities, transfer functions, and 3x3 gamut transformation matrices.
  TFloriaColorSpace = class
  private
    FColorSpaceType: TFloriaColorSpaceType;
    FTransferFunc: TFloriaTransferFunction;
    FPrimaries: TColorPrimaries;
    FRGBToXYZ: TMatrix3x3;
    FXYZToRGB: TMatrix3x3;
    FName: string;
    procedure ComputeMatrices();
  public
    constructor Create(AType: TFloriaColorSpaceType; ATransfer: TFloriaTransferFunction; const APrimaries: TColorPrimaries; const AName: string);
    destructor Destroy(); override;

    // Factory methods
    class function CreateSRGB(): TFloriaColorSpace; static;
    class function CreateLinearSRGB(): TFloriaColorSpace; static;
    class function CreateDisplayP3(): TFloriaColorSpace; static;
    class function CreateRec2020(): TFloriaColorSpace; static;
    class function CreateAdobeRGB(): TFloriaColorSpace; static;

    // Transfer function evaluation
    function ApplyTransferToLinear(const V: Single): Single;
    function ApplyTransferFromLinear(const V: Single): Single;

    // XYZ conversions
    function ToXYZ(const Color: TRgbaF32): TColorXYZ;
    function FromXYZ(const XYZ: TColorXYZ; Alpha: Single = 1.0): TRgbaF32;

    // Transform between color spaces
    function Transform(const Color: TRgbaF32; Target: TFloriaColorSpace): TRgbaF32;
    procedure TransformSpan(Src, Dst: PRgbaF32; Count: Integer; Target: TFloriaColorSpace);

    // Properties
    property ColorSpaceType: TFloriaColorSpaceType read FColorSpaceType;
    property TransferFunction: TFloriaTransferFunction read FTransferFunc;
    property Primaries: TColorPrimaries read FPrimaries;
    property RGBToXYZ: TMatrix3x3 read FRGBToXYZ;
    property XYZToRGB: TMatrix3x3 read FXYZToRGB;
    property Name: string read FName;
  end;

var
  // Precomputed LUT for fast 8-bit sRGB byte to linear Single conversion
  GSRGBToLinearLUT: array[0..255] of Single;

// IEEE 754 half-precision float (16-bit binary16) routines
function FloatToHalf(const V: Single): Word;
function HalfToFloat(const W: Word): Single;

// Standard transfer function routines
function SRGBToLinear(const V: Single): Single;
function LinearToSRGB(const V: Single): Single;
function LinearToSRGBByte(const V: Single): Byte; inline;
function GammaToLinear(const V, Gamma: Single): Single;
function LinearToGamma(const V, Gamma: Single): Single;
function PQToLinear(const N: Single): Single;
function LinearToPQ(const L: Single): Single;
function HLGToLinear(const E: Single): Single;
function LinearToHLG(const L: Single): Single;

// Linear-light blending routines (eliminating dark fringing)
procedure FloriaBlendPixelLinear(ADst: PBgraPixel; const ASrc: TBgraPixel; ABlendMode: TFloriaBlendMode; ACover: Byte = 255);
procedure FloriaBlendScanlineLinear(ADst: PBgraPixel; ASrc: PBgraPixel; AWidth: Integer; ABlendMode: TFloriaBlendMode; ACover: Byte = 255);

// Single-precision float blending routines
procedure FloriaBlendPixelF32(ADst: PRgbaF32; const ASrc: TRgbaF32; ABlendMode: TFloriaBlendMode; ACover: Single = 1.0);
procedure FloriaBlendScanlineF32(ADst: PRgbaF32; ASrc: PRgbaF32; AWidth: Integer; ABlendMode: TFloriaBlendMode; ACover: Single = 1.0);

// Global standard color space singletons
function FloriaColorSpaceSRGB(): TFloriaColorSpace;
function FloriaColorSpaceLinearSRGB(): TFloriaColorSpace;
function FloriaColorSpaceDisplayP3(): TFloriaColorSpace;
function FloriaColorSpaceRec2020(): TFloriaColorSpace;
function FloriaColorSpaceAdobeRGB(): TFloriaColorSpace;

implementation

const
  // D65 Standard Illuminant CIE 1931 Chromaticity Coordinates
  D65_X = 0.3127;
  D65_Y = 0.3290;

  // SMPTE ST 2084 PQ Constants
  PQ_M1 = 2610.0 / 16384.0;
  PQ_M2 = (2523.0 / 4096.0) * 128.0;
  PQ_C1 = 3424.0 / 4096.0;
  PQ_C2 = (2413.0 / 4096.0) * 32.0;
  PQ_C3 = (2392.0 / 4096.0) * 32.0;

  // ITU-R BT.2100 HLG Constants
  HLG_A = 0.17883277;
  HLG_B = 0.28466888; // 1.0 - 4.0 * HLG_A
  HLG_C = 0.55991073; // 0.5 - HLG_A * Ln(4.0 * HLG_A)

var
  GSharedSRGB: TFloriaColorSpace = nil;
  GSharedLinearSRGB: TFloriaColorSpace = nil;
  GSharedDisplayP3: TFloriaColorSpace = nil;
  GSharedRec2020: TFloriaColorSpace = nil;
  GSharedAdobeRGB: TFloriaColorSpace = nil;

// ---------------------------------------------------------------------------
// TCIEPoint & TColorPrimaries
// ---------------------------------------------------------------------------

class function TCIEPoint.Create(const AX, AY: Single): TCIEPoint;
begin
  Result.X := AX;
  Result.Y := AY;
end;

class function TColorPrimaries.Create(const ARed, AGreen, ABlue, AWhite: TCIEPoint): TColorPrimaries;
begin
  Result.Red := ARed;
  Result.Green := AGreen;
  Result.Blue := ABlue;
  Result.White := AWhite;
end;

class function TColorXYZ.Create(const AX, AY, AZ: Single): TColorXYZ;
begin
  Result.X := AX;
  Result.Y := AY;
  Result.Z := AZ;
end;

// ---------------------------------------------------------------------------
// TMatrix3x3 Implementation
// ---------------------------------------------------------------------------

class function TMatrix3x3.Identity(): TMatrix3x3;
begin
  FillChar(Result.M, SizeOf(Result.M), 0);
  Result.M[0, 0] := 1.0;
  Result.M[1, 1] := 1.0;
  Result.M[2, 2] := 1.0;
end;

function TMatrix3x3.Multiply(const B: TMatrix3x3): TMatrix3x3;
var
  I, J, K: Integer;
  Sum: Single;
begin
  for I := 0 to 2 do
    for J := 0 to 2 do
    begin
      Sum := 0.0;
      for K := 0 to 2 do
        Sum := Sum + M[I, K] * B.M[K, J];
      Result.M[I, J] := Sum;
    end;
end;

function TMatrix3x3.TransformVector(const X, Y, Z: Single; out OX, OY, OZ: Single): Boolean;
begin
  OX := M[0, 0] * X + M[0, 1] * Y + M[0, 2] * Z;
  OY := M[1, 0] * X + M[1, 1] * Y + M[1, 2] * Z;
  OZ := M[2, 0] * X + M[2, 1] * Y + M[2, 2] * Z;
  Result := True;
end;

function TMatrix3x3.Invert(out Inv: TMatrix3x3): Boolean;
var
  Det, InvDet: Single;
begin
  Det := M[0, 0] * (M[1, 1] * M[2, 2] - M[1, 2] * M[2, 1]) -
         M[0, 1] * (M[1, 0] * M[2, 2] - M[1, 2] * M[2, 0]) +
         M[0, 2] * (M[1, 0] * M[2, 1] - M[1, 1] * M[2, 0]);

  if Abs(Det) < 1e-12 then
  begin
    Inv := TMatrix3x3.Identity();
    Exit(False);
  end;

  InvDet := 1.0 / Det;

  Inv.M[0, 0] :=  (M[1, 1] * M[2, 2] - M[1, 2] * M[2, 1]) * InvDet;
  Inv.M[0, 1] := -(M[0, 1] * M[2, 2] - M[0, 2] * M[2, 1]) * InvDet;
  Inv.M[0, 2] :=  (M[0, 1] * M[1, 2] - M[0, 2] * M[1, 1]) * InvDet;

  Inv.M[1, 0] := -(M[1, 0] * M[2, 2] - M[1, 2] * M[2, 0]) * InvDet;
  Inv.M[1, 1] :=  (M[0, 0] * M[2, 2] - M[0, 2] * M[2, 0]) * InvDet;
  Inv.M[1, 2] := -(M[0, 0] * M[1, 2] - M[0, 2] * M[1, 0]) * InvDet;

  Inv.M[2, 0] :=  (M[1, 0] * M[2, 1] - M[1, 1] * M[2, 0]) * InvDet;
  Inv.M[2, 1] := -(M[0, 0] * M[2, 1] - M[0, 1] * M[2, 0]) * InvDet;
  Inv.M[2, 2] :=  (M[0, 0] * M[1, 1] - M[0, 1] * M[1, 0]) * InvDet;

  Result := True;
end;

// ---------------------------------------------------------------------------
// IEEE 754 Half-Precision Float (binary16) Routines
// ---------------------------------------------------------------------------

function FloatToHalf(const V: Single): Word;
var
  U: Cardinal;
  Sign, Exp, Mant: Cardinal;
  NewExp, NewMant: Cardinal;
  Shift: Integer;
begin
  U := PCardinal(@V)^;
  Sign := (U shr 31) and 1;
  Exp := (U shr 23) and $FF;
  Mant := U and $7FFFFF;

  // 1. NaN or Infinity (Exp = 255)
  if Exp = 255 then
  begin
    if Mant <> 0 then
    begin
      NewMant := Mant shr 13;
      if NewMant = 0 then NewMant := 1;
      Result := Word((Sign shl 15) or $7C00 or (NewMant and $3FF));
    end
    else
      Result := Word((Sign shl 15) or $7C00);
    Exit;
  end;

  // 2. Zero (Exp = 0 and Mant = 0)
  if (Exp = 0) and (Mant = 0) then
  begin
    Result := Word(Sign shl 15);
    Exit;
  end;

  // 3. Subnormal or Underflow (Exp < 113)
  if Exp < 113 then
  begin
    Shift := 113 - Integer(Exp);
    if Shift > 24 then
    begin
      Result := Word(Sign shl 15);
      Exit;
    end;
    Mant := Mant or $800000;
    NewMant := Mant shr (Shift + 13);
    if ((Mant shr (Shift + 12)) and 1) <> 0 then
      Inc(NewMant);
    Result := Word((Sign shl 15) or (NewMant and $3FF));
    Exit;
  end;

  // 4. Overflow to Infinity (Exp >= 143)
  if Exp >= 143 then
  begin
    Result := Word((Sign shl 15) or $7C00);
    Exit;
  end;

  // 5. Normalized Half Float
  NewExp := Exp - 112;
  NewMant := Mant shr 13;
  if ((Mant shr 12) and 1) <> 0 then
  begin
    Inc(NewMant);
    if NewMant > $3FF then
    begin
      NewMant := 0;
      Inc(NewExp);
      if NewExp >= 31 then
      begin
        Result := Word((Sign shl 15) or $7C00);
        Exit;
      end;
    end;
  end;

  Result := Word((Sign shl 15) or (NewExp shl 10) or (NewMant and $3FF));
end;

function HalfToFloat(const W: Word): Single;
var
  Sign, Exp, Mant: Cardinal;
  NewExp, NewMant, ResU: Cardinal;
begin
  Sign := (W shr 15) and 1;
  Exp := (W shr 10) and $1F;
  Mant := W and $3FF;

  if Exp = 0 then
  begin
    if Mant = 0 then
      ResU := Sign shl 31
    else
    begin
      // Subnormal
      while (Mant and $400) = 0 do
      begin
        Mant := Mant shl 1;
        Dec(Exp);
      end;
      Mant := Mant and $3FF;
      NewExp := Cardinal(Integer(Exp) + 1 + 112);
      NewMant := Mant shl 13;
      ResU := (Sign shl 31) or (NewExp shl 23) or NewMant;
    end;
  end
  else if Exp = 31 then
  begin
    if Mant = 0 then
      ResU := (Sign shl 31) or ($FF shl 23)
    else
      ResU := (Sign shl 31) or ($FF shl 23) or (Mant shl 13);
  end
  else
  begin
    NewExp := Exp + 112;
    NewMant := Mant shl 13;
    ResU := (Sign shl 31) or (NewExp shl 23) or NewMant;
  end;

  Result := PSingle(@ResU)^;
end;

// ---------------------------------------------------------------------------
// Standard Transfer Functions
// ---------------------------------------------------------------------------

function SRGBToLinear(const V: Single): Single;
begin
  if V <= 0.0 then
    Result := 0.0
  else if V <= 0.04045 then
    Result := V / 12.92
  else
    Result := Power((V + 0.055) / 1.055, 2.4);
end;

function LinearToSRGB(const V: Single): Single;
begin
  if V <= 0.0 then
    Result := 0.0
  else if V <= 0.0031308 then
    Result := V * 12.92
  else if V >= 1.0 then
    Result := 1.0
  else
    Result := 1.055 * Power(V, 1.0 / 2.4) - 0.055;
end;

function LinearToSRGBByte(const V: Single): Byte; inline;
begin
  if V <= 0.0 then
    Result := 0
  else if V >= 1.0 then
    Result := 255
  else
    Result := Byte(EnsureRange(Round(LinearToSRGB(V) * 255.0), 0, 255));
end;

function GammaToLinear(const V, Gamma: Single): Single;
begin
  if V <= 0.0 then
    Result := 0.0
  else
    Result := Power(V, Gamma);
end;

function LinearToGamma(const V, Gamma: Single): Single;
begin
  if V <= 0.0 then
    Result := 0.0
  else if Gamma <= 0.0 then
    Result := V
  else
    Result := Power(V, 1.0 / Gamma);
end;

function PQToLinear(const N: Single): Single;
var
  Np, Num, Den: Single;
begin
  if N <= 0.0 then Exit(0.0);
  Np := Power(N, 1.0 / PQ_M2);
  Num := Max(Np - PQ_C1, 0.0);
  Den := PQ_C2 - PQ_C3 * Np;
  if Den <= 0.0 then Exit(1.0);
  Result := Power(Num / Den, 1.0 / PQ_M1);
end;

function LinearToPQ(const L: Single): Single;
var
  Lm, Num, Den: Single;
begin
  if L <= 0.0 then Exit(0.0);
  Lm := Power(L, PQ_M1);
  Num := PQ_C1 + PQ_C2 * Lm;
  Den := 1.0 + PQ_C3 * Lm;
  Result := Power(Num / Den, PQ_M2);
end;

function HLGToLinear(const E: Single): Single;
begin
  if E <= 0.0 then Exit(0.0);
  if E <= 0.5 then
    Result := (E * E) / 3.0
  else
    Result := (Exp((E - HLG_C) / HLG_A) + HLG_B) / 12.0;
end;

function LinearToHLG(const L: Single): Single;
begin
  if L <= 0.0 then Exit(0.0);
  if L <= (1.0 / 12.0) then
    Result := Sqrt(3.0 * L)
  else
    Result := HLG_A * Ln(12.0 * L - HLG_B) + HLG_C;
end;

// ---------------------------------------------------------------------------
// TRgbaF32 Implementation
// ---------------------------------------------------------------------------

class function TRgbaF32.Create(const AR, AG, AB: Single; const AA: Single = 1.0): TRgbaF32;
begin
  Result.R := AR;
  Result.G := AG;
  Result.B := AB;
  Result.A := AA;
end;

class function TRgbaF32.FromBgra(const P: TBgraPixel): TRgbaF32;
begin
  Result.R := P.R / 255.0;
  Result.G := P.G / 255.0;
  Result.B := P.B / 255.0;
  Result.A := P.A / 255.0;
end;

class function TRgbaF32.FromBgraLinear(const P: TBgraPixel): TRgbaF32;
begin
  Result.R := GSRGBToLinearLUT[P.R];
  Result.G := GSRGBToLinearLUT[P.G];
  Result.B := GSRGBToLinearLUT[P.B];
  Result.A := P.A / 255.0;
end;

function TRgbaF32.ToBgra(): TBgraPixel;
begin
  Result.B := Byte(EnsureRange(Round(B * 255.0), 0, 255));
  Result.G := Byte(EnsureRange(Round(G * 255.0), 0, 255));
  Result.R := Byte(EnsureRange(Round(R * 255.0), 0, 255));
  Result.A := Byte(EnsureRange(Round(A * 255.0), 0, 255));
end;

function TRgbaF32.ToBgraLinear(): TBgraPixel;
begin
  Result.B := LinearToSRGBByte(B);
  Result.G := LinearToSRGBByte(G);
  Result.R := LinearToSRGBByte(R);
  Result.A := Byte(EnsureRange(Round(A * 255.0), 0, 255));
end;

function TRgbaF32.Premultiply(): TRgbaF32;
begin
  Result.R := R * A;
  Result.G := G * A;
  Result.B := B * A;
  Result.A := A;
end;

function TRgbaF32.Demultiply(): TRgbaF32;
var
  InvA: Single;
begin
  if A > 0.000001 then
  begin
    InvA := 1.0 / A;
    Result.R := R * InvA;
    Result.G := G * InvA;
    Result.B := B * InvA;
    Result.A := A;
  end
  else
  begin
    Result.R := 0.0;
    Result.G := 0.0;
    Result.B := 0.0;
    Result.A := 0.0;
  end;
end;

function TRgbaF32.Clamp(): TRgbaF32;
begin
  Result.R := EnsureRange(R, 0.0, 1.0);
  Result.G := EnsureRange(G, 0.0, 1.0);
  Result.B := EnsureRange(B, 0.0, 1.0);
  Result.A := EnsureRange(A, 0.0, 1.0);
end;

// ---------------------------------------------------------------------------
// TRgbaF16 Implementation
// ---------------------------------------------------------------------------

class function TRgbaF16.Create(const AR, AG, AB: Single; const AA: Single = 1.0): TRgbaF16;
begin
  Result.R := FloatToHalf(AR);
  Result.G := FloatToHalf(AG);
  Result.B := FloatToHalf(AB);
  Result.A := FloatToHalf(AA);
end;

class function TRgbaF16.FromF32(const P: TRgbaF32): TRgbaF16;
begin
  Result.R := FloatToHalf(P.R);
  Result.G := FloatToHalf(P.G);
  Result.B := FloatToHalf(P.B);
  Result.A := FloatToHalf(P.A);
end;

function TRgbaF16.ToF32(): TRgbaF32;
begin
  Result.R := HalfToFloat(R);
  Result.G := HalfToFloat(G);
  Result.B := HalfToFloat(B);
  Result.A := HalfToFloat(A);
end;

class function TRgbaF16.FromBgra(const P: TBgraPixel): TRgbaF16;
begin
  Result.R := FloatToHalf(P.R / 255.0);
  Result.G := FloatToHalf(P.G / 255.0);
  Result.B := FloatToHalf(P.B / 255.0);
  Result.A := FloatToHalf(P.A / 255.0);
end;

function TRgbaF16.ToBgra(): TBgraPixel;
begin
  Result := ToF32().ToBgra();
end;

// ---------------------------------------------------------------------------
// TFloriaColorSpace Implementation
// ---------------------------------------------------------------------------

constructor TFloriaColorSpace.Create(AType: TFloriaColorSpaceType; ATransfer: TFloriaTransferFunction; const APrimaries: TColorPrimaries; const AName: string);
begin
  inherited Create();
  FColorSpaceType := AType;
  FTransferFunc := ATransfer;
  FPrimaries := APrimaries;
  FName := AName;
  ComputeMatrices();
end;

destructor TFloriaColorSpace.Destroy();
begin
  inherited Destroy();
end;

procedure TFloriaColorSpace.ComputeMatrices();
var
  Xr, Yr, Zr: Single;
  Xg, Yg, Zg: Single;
  Xb, Yb, Zb: Single;
  Xw, Yw, Zw: Single;
  M_P, InvM_P: TMatrix3x3;
  Sr, Sg, Sb: Single;
begin
  // Convert chromaticity coordinates to normalized XYZ
  Xr := FPrimaries.Red.X / FPrimaries.Red.Y;
  Yr := 1.0;
  Zr := (1.0 - FPrimaries.Red.X - FPrimaries.Red.Y) / FPrimaries.Red.Y;

  Xg := FPrimaries.Green.X / FPrimaries.Green.Y;
  Yg := 1.0;
  Zg := (1.0 - FPrimaries.Green.X - FPrimaries.Green.Y) / FPrimaries.Green.Y;

  Xb := FPrimaries.Blue.X / FPrimaries.Blue.Y;
  Yb := 1.0;
  Zb := (1.0 - FPrimaries.Blue.X - FPrimaries.Blue.Y) / FPrimaries.Blue.Y;

  Xw := FPrimaries.White.X / FPrimaries.White.Y;
  Yw := 1.0;
  Zw := (1.0 - FPrimaries.White.X - FPrimaries.White.Y) / FPrimaries.White.Y;

  M_P.M[0, 0] := Xr; M_P.M[0, 1] := Xg; M_P.M[0, 2] := Xb;
  M_P.M[1, 0] := Yr; M_P.M[1, 1] := Yg; M_P.M[1, 2] := Yb;
  M_P.M[2, 0] := Zr; M_P.M[2, 1] := Zg; M_P.M[2, 2] := Zb;

  if not M_P.Invert(InvM_P) then
  begin
    FRGBToXYZ := TMatrix3x3.Identity();
    FXYZToRGB := TMatrix3x3.Identity();
    Exit;
  end;

  InvM_P.TransformVector(Xw, Yw, Zw, Sr, Sg, Sb);

  FRGBToXYZ.M[0, 0] := Sr * Xr; FRGBToXYZ.M[0, 1] := Sg * Xg; FRGBToXYZ.M[0, 2] := Sb * Xb;
  FRGBToXYZ.M[1, 0] := Sr * Yr; FRGBToXYZ.M[1, 1] := Sg * Yg; FRGBToXYZ.M[1, 2] := Sb * Yb;
  FRGBToXYZ.M[2, 0] := Sr * Zr; FRGBToXYZ.M[2, 1] := Sg * Zg; FRGBToXYZ.M[2, 2] := Sb * Zb;

  if not FRGBToXYZ.Invert(FXYZToRGB) then
    FXYZToRGB := TMatrix3x3.Identity();
end;

class function TFloriaColorSpace.CreateSRGB(): TFloriaColorSpace;
var
  P: TColorPrimaries;
begin
  P.Red := TCIEPoint.Create(0.640, 0.330);
  P.Green := TCIEPoint.Create(0.300, 0.600);
  P.Blue := TCIEPoint.Create(0.150, 0.060);
  P.White := TCIEPoint.Create(D65_X, D65_Y);
  Result := TFloriaColorSpace.Create(fcstSRGB, ftfSRGB, P, 'sRGB');
end;

class function TFloriaColorSpace.CreateLinearSRGB(): TFloriaColorSpace;
var
  P: TColorPrimaries;
begin
  P.Red := TCIEPoint.Create(0.640, 0.330);
  P.Green := TCIEPoint.Create(0.300, 0.600);
  P.Blue := TCIEPoint.Create(0.150, 0.060);
  P.White := TCIEPoint.Create(D65_X, D65_Y);
  Result := TFloriaColorSpace.Create(fcstLinearSRGB, ftfLinear, P, 'Linear sRGB');
end;

class function TFloriaColorSpace.CreateDisplayP3(): TFloriaColorSpace;
var
  P: TColorPrimaries;
begin
  P.Red := TCIEPoint.Create(0.680, 0.320);
  P.Green := TCIEPoint.Create(0.265, 0.690);
  P.Blue := TCIEPoint.Create(0.150, 0.060);
  P.White := TCIEPoint.Create(D65_X, D65_Y);
  Result := TFloriaColorSpace.Create(fcstDisplayP3, ftfSRGB, P, 'Display P3');
end;

class function TFloriaColorSpace.CreateRec2020(): TFloriaColorSpace;
var
  P: TColorPrimaries;
begin
  P.Red := TCIEPoint.Create(0.708, 0.292);
  P.Green := TCIEPoint.Create(0.170, 0.797);
  P.Blue := TCIEPoint.Create(0.131, 0.046);
  P.White := TCIEPoint.Create(D65_X, D65_Y);
  Result := TFloriaColorSpace.Create(fcstRec2020, ftfLinear, P, 'Rec. 2020');
end;

class function TFloriaColorSpace.CreateAdobeRGB(): TFloriaColorSpace;
var
  P: TColorPrimaries;
begin
  P.Red := TCIEPoint.Create(0.640, 0.330);
  P.Green := TCIEPoint.Create(0.210, 0.710);
  P.Blue := TCIEPoint.Create(0.150, 0.060);
  P.White := TCIEPoint.Create(D65_X, D65_Y);
  Result := TFloriaColorSpace.Create(fcstAdobeRGB, ftfGamma22, P, 'Adobe RGB (1998)');
end;

function TFloriaColorSpace.ApplyTransferToLinear(const V: Single): Single;
begin
  case FTransferFunc of
    ftfLinear:   Result := V;
    ftfSRGB:     Result := SRGBToLinear(V);
    ftfGamma22:  Result := GammaToLinear(V, 2.2);
    ftfGamma28:  Result := GammaToLinear(V, 2.8);
    ftfPQ:       Result := PQToLinear(V);
    ftfHLG:      Result := HLGToLinear(V);
  else
    Result := V;
  end;
end;

function TFloriaColorSpace.ApplyTransferFromLinear(const V: Single): Single;
begin
  case FTransferFunc of
    ftfLinear:   Result := V;
    ftfSRGB:     Result := LinearToSRGB(V);
    ftfGamma22:  Result := LinearToGamma(V, 2.2);
    ftfGamma28:  Result := LinearToGamma(V, 2.8);
    ftfPQ:       Result := LinearToPQ(V);
    ftfHLG:      Result := LinearToHLG(V);
  else
    Result := V;
  end;
end;

function TFloriaColorSpace.ToXYZ(const Color: TRgbaF32): TColorXYZ;
var
  LinR, LinG, LinB: Single;
  X, Y, Z: Single;
begin
  LinR := ApplyTransferToLinear(Color.R);
  LinG := ApplyTransferToLinear(Color.G);
  LinB := ApplyTransferToLinear(Color.B);

  FRGBToXYZ.TransformVector(LinR, LinG, LinB, X, Y, Z);
  Result := TColorXYZ.Create(X, Y, Z);
end;

function TFloriaColorSpace.FromXYZ(const XYZ: TColorXYZ; Alpha: Single = 1.0): TRgbaF32;
var
  LinR, LinG, LinB: Single;
begin
  FXYZToRGB.TransformVector(XYZ.X, XYZ.Y, XYZ.Z, LinR, LinG, LinB);
  Result.R := ApplyTransferFromLinear(LinR);
  Result.G := ApplyTransferFromLinear(LinG);
  Result.B := ApplyTransferFromLinear(LinB);
  Result.A := Alpha;
end;

function TFloriaColorSpace.Transform(const Color: TRgbaF32; Target: TFloriaColorSpace): TRgbaF32;
var
  LinR, LinG, LinB: Single;
  TargetLinR, TargetLinG, TargetLinB: Single;
  DirectMat: TMatrix3x3;
begin
  if (Target = nil) or (Target = Self) then
    Exit(Color);

  // 1. Linearize source
  LinR := ApplyTransferToLinear(Color.R);
  LinG := ApplyTransferToLinear(Color.G);
  LinB := ApplyTransferToLinear(Color.B);

  // 2. Gamut conversion if primaries differ
  if (FPrimaries.Red.X = Target.FPrimaries.Red.X) and
     (FPrimaries.Red.Y = Target.FPrimaries.Red.Y) and
     (FPrimaries.Green.X = Target.FPrimaries.Green.X) and
     (FPrimaries.Green.Y = Target.FPrimaries.Green.Y) and
     (FPrimaries.Blue.X = Target.FPrimaries.Blue.X) and
     (FPrimaries.Blue.Y = Target.FPrimaries.Blue.Y) then
  begin
    TargetLinR := LinR;
    TargetLinG := LinG;
    TargetLinB := LinB;
  end
  else
  begin
    DirectMat := Target.FXYZToRGB.Multiply(FRGBToXYZ);
    DirectMat.TransformVector(LinR, LinG, LinB, TargetLinR, TargetLinG, TargetLinB);
  end;

  // 3. Apply target transfer function
  Result.R := Target.ApplyTransferFromLinear(TargetLinR);
  Result.G := Target.ApplyTransferFromLinear(TargetLinG);
  Result.B := Target.ApplyTransferFromLinear(TargetLinB);
  Result.A := Color.A;
end;

procedure TFloriaColorSpace.TransformSpan(Src, Dst: PRgbaF32; Count: Integer; Target: TFloriaColorSpace);
var
  I: Integer;
begin
  if (Count <= 0) or (Src = nil) or (Dst = nil) then Exit;
  for I := 0 to Count - 1 do
  begin
    Dst^ := Transform(Src^, Target);
    Inc(Src);
    Inc(Dst);
  end;
end;

// ---------------------------------------------------------------------------
// Linear Blending Helper Math (Float 0.0..1.0)
// ---------------------------------------------------------------------------

function LumFloat(const R, G, B: Single): Single; inline;
begin
  // ITU-R BT.709 relative luminance
  Result := 0.2126 * R + 0.7152 * G + 0.0722 * B;
end;

procedure ClipColorFloat(var R, G, B: Single);
var
  L, N, X, D: Single;
begin
  L := LumFloat(R, G, B);
  N := Min(R, Min(G, B));
  X := Max(R, Max(G, B));

  if N < 0.0 then
  begin
    D := L - N;
    if D > 0.00001 then
    begin
      R := L + ((R - L) * L) / D;
      G := L + ((G - L) * L) / D;
      B := L + ((B - L) * L) / D;
    end
    else
    begin
      R := L; G := L; B := L;
    end;
  end;

  if X > 1.0 then
  begin
    D := X - L;
    if D > 0.00001 then
    begin
      R := L + ((R - L) * (1.0 - L)) / D;
      G := L + ((G - L) * (1.0 - L)) / D;
      B := L + ((B - L) * (1.0 - L)) / D;
    end
    else
    begin
      R := L; G := L; B := L;
    end;
  end;
end;

procedure SetLumFloat(var R, G, B: Single; const L: Single);
var
  D: Single;
begin
  D := L - LumFloat(R, G, B);
  R := R + D;
  G := G + D;
  B := B + D;
  ClipColorFloat(R, G, B);
end;

function SatFloat(const R, G, B: Single): Single; inline;
begin
  Result := Max(R, Max(G, B)) - Min(R, Min(G, B));
end;

procedure SetSatFloat(var R, G, B: Single; const S: Single);
var
  MinIdx, MidIdx, MaxIdx: Integer;
  Arr: array[0..2] of Single;
begin
  Arr[0] := R; Arr[1] := G; Arr[2] := B;
  if Arr[0] < Arr[1] then
  begin
    if Arr[1] < Arr[2] then begin MinIdx := 0; MidIdx := 1; MaxIdx := 2; end
    else if Arr[0] < Arr[2] then begin MinIdx := 0; MidIdx := 2; MaxIdx := 1; end
    else begin MinIdx := 2; MidIdx := 0; MaxIdx := 1; end;
  end
  else
  begin
    if Arr[0] < Arr[2] then begin MinIdx := 1; MidIdx := 0; MaxIdx := 2; end
    else if Arr[1] < Arr[2] then begin MinIdx := 1; MidIdx := 2; MaxIdx := 0; end
    else begin MinIdx := 2; MidIdx := 1; MaxIdx := 0; end;
  end;

  if Arr[MaxIdx] > Arr[MinIdx] then
  begin
    Arr[MidIdx] := ((Arr[MidIdx] - Arr[MinIdx]) * S) / (Arr[MaxIdx] - Arr[MinIdx]);
    Arr[MaxIdx] := S;
  end
  else
  begin
    Arr[MidIdx] := 0.0;
    Arr[MaxIdx] := 0.0;
  end;
  Arr[MinIdx] := 0.0;

  R := Arr[0]; G := Arr[1]; B := Arr[2];
end;

// ---------------------------------------------------------------------------
// FloriaBlendPixelF32
// Operates on premultiplied linear TRgbaF32 pixels
// ---------------------------------------------------------------------------

procedure FloriaBlendPixelF32(ADst: PRgbaF32; const ASrc: TRgbaF32; ABlendMode: TFloriaBlendMode; ACover: Single = 1.0);
var
  sR, sG, sB, sA: Single;
  dR, dG, dB, dA: Single;
  sRu, sGu, sBu: Single;
  dRu, dGu, dBu: Single;
  bRu, bGu, bBu: Single;
  r, g, b: Single;
  OutA: Single;
  D: Single;
begin
  if (ACover <= 0.0) and (ABlendMode <> fbmClear) then Exit;

  // Apply coverage to source
  sR := ASrc.R * ACover;
  sG := ASrc.G * ACover;
  sB := ASrc.B * ACover;
  sA := ASrc.A * ACover;

  dR := ADst^.R;
  dG := ADst^.G;
  dB := ADst^.B;
  dA := ADst^.A;

  case ABlendMode of
    fbmClear:
      begin
        ADst^.R := 0.0; ADst^.G := 0.0; ADst^.B := 0.0; ADst^.A := 0.0;
        Exit;
      end;

    fbmSrc:
      begin
        ADst^.R := sR; ADst^.G := sG; ADst^.B := sB; ADst^.A := sA;
        Exit;
      end;

    fbmDst:
      Exit;

    fbmSrcOver:
      begin
        ADst^.R := sR + dR * (1.0 - sA);
        ADst^.G := sG + dG * (1.0 - sA);
        ADst^.B := sB + dB * (1.0 - sA);
        ADst^.A := sA + dA * (1.0 - sA);
        Exit;
      end;

    fbmDstOver:
      begin
        ADst^.R := dR + sR * (1.0 - dA);
        ADst^.G := dG + sG * (1.0 - dA);
        ADst^.B := dB + sB * (1.0 - dA);
        ADst^.A := dA + sA * (1.0 - dA);
        Exit;
      end;

    fbmSrcIn:
      begin
        ADst^.R := sR * dA;
        ADst^.G := sG * dA;
        ADst^.B := sB * dA;
        ADst^.A := sA * dA;
        Exit;
      end;

    fbmDstIn:
      begin
        ADst^.R := dR * sA;
        ADst^.G := dG * sA;
        ADst^.B := dB * sA;
        ADst^.A := dA * sA;
        Exit;
      end;

    fbmSrcOut:
      begin
        ADst^.R := sR * (1.0 - dA);
        ADst^.G := sG * (1.0 - dA);
        ADst^.B := sB * (1.0 - dA);
        ADst^.A := sA * (1.0 - dA);
        Exit;
      end;

    fbmDstOut:
      begin
        ADst^.R := dR * (1.0 - sA);
        ADst^.G := dG * (1.0 - sA);
        ADst^.B := dB * (1.0 - sA);
        ADst^.A := dA * (1.0 - sA);
        Exit;
      end;

    fbmSrcATop:
      begin
        ADst^.R := sR * dA + dR * (1.0 - sA);
        ADst^.G := sG * dA + dG * (1.0 - sA);
        ADst^.B := sB * dA + dB * (1.0 - sA);
        ADst^.A := dA;
        Exit;
      end;

    fbmDstATop:
      begin
        ADst^.R := dR * sA + sR * (1.0 - dA);
        ADst^.G := dG * sA + sG * (1.0 - dA);
        ADst^.B := dB * sA + sB * (1.0 - dA);
        ADst^.A := sA;
        Exit;
      end;

    fbmXor:
      begin
        ADst^.R := sR * (1.0 - dA) + dR * (1.0 - sA);
        ADst^.G := sG * (1.0 - dA) + dG * (1.0 - sA);
        ADst^.B := sB * (1.0 - dA) + dB * (1.0 - sA);
        ADst^.A := sA * (1.0 - dA) + dA * (1.0 - sA);
        Exit;
      end;

    fbmPlus:
      begin
        ADst^.R := sR + dR;
        ADst^.G := sG + dG;
        ADst^.B := sB + dB;
        ADst^.A := Min(1.0, sA + dA);
        Exit;
      end;

    fbmModulate:
      begin
        ADst^.R := sR * dR;
        ADst^.G := sG * dG;
        ADst^.B := sB * dB;
        ADst^.A := sA * dA;
        Exit;
      end;
  end;

  // --- Separable and non-separable blend modes (14..28) ---
  if sA <= 0.000001 then Exit;

  // Demultiply source
  sRu := sR / sA;
  sGu := sG / sA;
  sBu := sB / sA;

  // Demultiply destination
  if dA > 0.000001 then
  begin
    dRu := dR / dA;
    dGu := dG / dA;
    dBu := dB / dA;
  end
  else
  begin
    dRu := 0.0;
    dGu := 0.0;
    dBu := 0.0;
  end;

  case ABlendMode of
    fbmMultiply:
      begin
        bRu := sRu * dRu;
        bGu := sGu * dGu;
        bBu := sBu * dBu;
      end;

    fbmScreen:
      begin
        bRu := sRu + dRu - sRu * dRu;
        bGu := sGu + dGu - sGu * dGu;
        bBu := sBu + dBu - sBu * dBu;
      end;

    fbmOverlay:
      begin
        if dRu <= 0.5 then bRu := 2.0 * sRu * dRu else bRu := 1.0 - 2.0 * (1.0 - sRu) * (1.0 - dRu);
        if dGu <= 0.5 then bGu := 2.0 * sGu * dGu else bGu := 1.0 - 2.0 * (1.0 - sGu) * (1.0 - dGu);
        if dBu <= 0.5 then bBu := 2.0 * sBu * dBu else bBu := 1.0 - 2.0 * (1.0 - sBu) * (1.0 - dBu);
      end;

    fbmDarken:
      begin
        bRu := Min(sRu, dRu);
        bGu := Min(sGu, dGu);
        bBu := Min(sBu, dBu);
      end;

    fbmLighten:
      begin
        bRu := Max(sRu, dRu);
        bGu := Max(sGu, dGu);
        bBu := Max(sBu, dBu);
      end;

    fbmColorDodge:
      begin
        if dRu <= 0.0 then bRu := 0.0 else if sRu >= 1.0 then bRu := 1.0 else bRu := Min(1.0, dRu / (1.0 - sRu));
        if dGu <= 0.0 then bGu := 0.0 else if sGu >= 1.0 then bGu := 1.0 else bGu := Min(1.0, dGu / (1.0 - sGu));
        if dBu <= 0.0 then bBu := 0.0 else if sBu >= 1.0 then bBu := 1.0 else bBu := Min(1.0, dBu / (1.0 - sBu));
      end;

    fbmColorBurn:
      begin
        if dRu >= 1.0 then bRu := 1.0 else if sRu <= 0.0 then bRu := 0.0 else bRu := 1.0 - Min(1.0, (1.0 - dRu) / sRu);
        if dGu >= 1.0 then bGu := 1.0 else if sGu <= 0.0 then bGu := 0.0 else bGu := 1.0 - Min(1.0, (1.0 - dGu) / sGu);
        if dBu >= 1.0 then bBu := 1.0 else if sBu <= 0.0 then bBu := 0.0 else bBu := 1.0 - Min(1.0, (1.0 - dBu) / sBu);
      end;

    fbmHardLight:
      begin
        if sRu <= 0.5 then bRu := 2.0 * sRu * dRu else bRu := 1.0 - 2.0 * (1.0 - sRu) * (1.0 - dRu);
        if sGu <= 0.5 then bGu := 2.0 * sGu * dGu else bGu := 1.0 - 2.0 * (1.0 - sGu) * (1.0 - dGu);
        if sBu <= 0.5 then bBu := 2.0 * sBu * dBu else bBu := 1.0 - 2.0 * (1.0 - sBu) * (1.0 - dBu);
      end;

    fbmSoftLight:
      begin
        if sRu <= 0.5 then bRu := dRu - (1.0 - 2.0 * sRu) * dRu * (1.0 - dRu)
        else begin
          if dRu <= 0.25 then D := ((16.0 * dRu - 12.0) * dRu + 4.0) * dRu else D := Sqrt(Max(dRu, 0.0));
          bRu := dRu + (2.0 * sRu - 1.0) * (D - dRu);
        end;

        if sGu <= 0.5 then bGu := dGu - (1.0 - 2.0 * sGu) * dGu * (1.0 - dGu)
        else begin
          if dGu <= 0.25 then D := ((16.0 * dGu - 12.0) * dGu + 4.0) * dGu else D := Sqrt(Max(dGu, 0.0));
          bGu := dGu + (2.0 * sGu - 1.0) * (D - dGu);
        end;

        if sBu <= 0.5 then bBu := dBu - (1.0 - 2.0 * sBu) * dBu * (1.0 - dBu)
        else begin
          if dBu <= 0.25 then D := ((16.0 * dBu - 12.0) * dBu + 4.0) * dBu else D := Sqrt(Max(dBu, 0.0));
          bBu := dBu + (2.0 * sBu - 1.0) * (D - dBu);
        end;
      end;

    fbmDifference:
      begin
        bRu := Abs(sRu - dRu);
        bGu := Abs(sGu - dGu);
        bBu := Abs(sBu - dBu);
      end;

    fbmExclusion:
      begin
        bRu := sRu + dRu - 2.0 * sRu * dRu;
        bGu := sGu + dGu - 2.0 * sGu * dGu;
        bBu := sBu + dBu - 2.0 * sBu * dBu;
      end;

    fbmHue:
      begin
        r := sRu; g := sGu; b := sBu;
        SetSatFloat(r, g, b, SatFloat(dRu, dGu, dBu));
        SetLumFloat(r, g, b, LumFloat(dRu, dGu, dBu));
        bRu := r; bGu := g; bBu := b;
      end;

    fbmSaturation:
      begin
        r := dRu; g := dGu; b := dBu;
        SetSatFloat(r, g, b, SatFloat(sRu, sGu, sBu));
        SetLumFloat(r, g, b, LumFloat(dRu, dGu, dBu));
        bRu := r; bGu := g; bBu := b;
      end;

    fbmColor:
      begin
        r := sRu; g := sGu; b := sBu;
        SetLumFloat(r, g, b, LumFloat(dRu, dGu, dBu));
        bRu := r; bGu := g; bBu := b;
      end;

    fbmLuminosity:
      begin
        r := dRu; g := dGu; b := dBu;
        SetLumFloat(r, g, b, LumFloat(sRu, sGu, sBu));
        bRu := r; bGu := g; bBu := b;
      end;
  else
    bRu := sRu; bGu := sGu; bBu := sBu;
  end;

  // W3C compositing equation:
  // Co = (1 - αd)*Cs + (1 - αs)*Cd + αs*αd*B(Cs, Cd)
  OutA := sA + dA * (1.0 - sA);
  ADst^.R := sR * (1.0 - dA) + dR * (1.0 - sA) + sA * dA * bRu;
  ADst^.G := sG * (1.0 - dA) + dG * (1.0 - sA) + sA * dA * bGu;
  ADst^.B := sB * (1.0 - dA) + dB * (1.0 - sA) + sA * dA * bBu;
  ADst^.A := OutA;
end;

procedure FloriaBlendScanlineF32(ADst: PRgbaF32; ASrc: PRgbaF32; AWidth: Integer; ABlendMode: TFloriaBlendMode; ACover: Single = 1.0);
var
  I: Integer;
begin
  if (AWidth <= 0) or (ADst = nil) or (ASrc = nil) then Exit;
  for I := 0 to AWidth - 1 do
  begin
    FloriaBlendPixelF32(ADst, ASrc^, ABlendMode, ACover);
    Inc(ADst);
    Inc(ASrc);
  end;
end;

// ---------------------------------------------------------------------------
// Linear Light Blending on 8-bit BGRA Pixels
// Eliminates dark fringing on anti-aliased boundaries and transparent overlays.
// ---------------------------------------------------------------------------

procedure FloriaBlendPixelLinear(ADst: PBgraPixel; const ASrc: TBgraPixel; ABlendMode: TFloriaBlendMode; ACover: Byte = 255);
var
  SrcF, DstF: TRgbaF32;
  CovF: Single;
  sLinR, sLinG, sLinB: Single;
  dLinR, dLinG, dLinB: Single;
  Alpha, InvAlpha: Single;
  OutLinR, OutLinG, OutLinB, OutLinA: Single;
  InvA: Single;
begin
  if (ACover = 0) and (ABlendMode <> fbmClear) then Exit;

  // Blazingly fast path: Opaque SrcOver onto Opaque Dest (most common GUI blit)
  if (ABlendMode = fbmSrcOver) and (ADst^.A = 255) and (ASrc.A = 255) and (ACover = 255) then
  begin
    ADst^ := ASrc;
    Exit;
  end;

  // Fast path: Semi-transparent SrcOver onto fully opaque Destination in linear light
  if (ABlendMode = fbmSrcOver) and (ADst^.A = 255) then
  begin
    Alpha := (ASrc.A * ACover) * (1.0 / (255.0 * 255.0));
    if Alpha <= 0.00001 then Exit;
    if Alpha >= 0.99999 then
    begin
      ADst^ := ASrc;
      Exit;
    end;
    InvAlpha := 1.0 - Alpha;

    sLinR := GSRGBToLinearLUT[ASrc.R];
    sLinG := GSRGBToLinearLUT[ASrc.G];
    sLinB := GSRGBToLinearLUT[ASrc.B];

    dLinR := GSRGBToLinearLUT[ADst^.R];
    dLinG := GSRGBToLinearLUT[ADst^.G];
    dLinB := GSRGBToLinearLUT[ADst^.B];

    ADst^.R := LinearToSRGBByte(sLinR * Alpha + dLinR * InvAlpha);
    ADst^.G := LinearToSRGBByte(sLinG * Alpha + dLinG * InvAlpha);
    ADst^.B := LinearToSRGBByte(sLinB * Alpha + dLinB * InvAlpha);
    ADst^.A := 255;
    Exit;
  end;

  // General path: Arbitrary blend mode and transparent destination
  CovF := ACover / 255.0;
  SrcF := TRgbaF32.FromBgraLinear(ASrc).Premultiply();
  DstF := TRgbaF32.FromBgraLinear(ADst^).Premultiply();

  FloriaBlendPixelF32(@DstF, SrcF, ABlendMode, CovF);

  OutLinA := DstF.A;
  if OutLinA <= 0.00001 then
  begin
    ADst^.B := 0;
    ADst^.G := 0;
    ADst^.R := 0;
    ADst^.A := 0;
    Exit;
  end;

  InvA := 1.0 / OutLinA;
  OutLinR := DstF.R * InvA;
  OutLinG := DstF.G * InvA;
  OutLinB := DstF.B * InvA;

  ADst^.A := Byte(EnsureRange(Round(OutLinA * 255.0), 0, 255));
  if ADst^.A = 255 then
  begin
    ADst^.R := LinearToSRGBByte(OutLinR);
    ADst^.G := LinearToSRGBByte(OutLinG);
    ADst^.B := LinearToSRGBByte(OutLinB);
  end
  else
  begin
    // Re-premultiply by alpha
    ADst^.R := Byte(EnsureRange((LinearToSRGBByte(OutLinR) * ADst^.A + 128) shr 8, 0, 255));
    ADst^.G := Byte(EnsureRange((LinearToSRGBByte(OutLinG) * ADst^.A + 128) shr 8, 0, 255));
    ADst^.B := Byte(EnsureRange((LinearToSRGBByte(OutLinB) * ADst^.A + 128) shr 8, 0, 255));
  end;
end;

procedure FloriaBlendScanlineLinear(ADst: PBgraPixel; ASrc: PBgraPixel; AWidth: Integer; ABlendMode: TFloriaBlendMode; ACover: Byte = 255);
var
  I: Integer;
begin
  if (AWidth <= 0) or (ADst = nil) or (ASrc = nil) then Exit;
  for I := 0 to AWidth - 1 do
  begin
    FloriaBlendPixelLinear(ADst, ASrc^, ABlendMode, ACover);
    Inc(ADst);
    Inc(ASrc);
  end;
end;

// ---------------------------------------------------------------------------
// Standard Color Space Accessors
// ---------------------------------------------------------------------------

function FloriaColorSpaceSRGB(): TFloriaColorSpace;
begin
  if GSharedSRGB = nil then
    GSharedSRGB := TFloriaColorSpace.CreateSRGB();
  Result := GSharedSRGB;
end;

function FloriaColorSpaceLinearSRGB(): TFloriaColorSpace;
begin
  if GSharedLinearSRGB = nil then
    GSharedLinearSRGB := TFloriaColorSpace.CreateLinearSRGB();
  Result := GSharedLinearSRGB;
end;

function FloriaColorSpaceDisplayP3(): TFloriaColorSpace;
begin
  if GSharedDisplayP3 = nil then
    GSharedDisplayP3 := TFloriaColorSpace.CreateDisplayP3();
  Result := GSharedDisplayP3;
end;

function FloriaColorSpaceRec2020(): TFloriaColorSpace;
begin
  if GSharedRec2020 = nil then
    GSharedRec2020 := TFloriaColorSpace.CreateRec2020();
  Result := GSharedRec2020;
end;

function FloriaColorSpaceAdobeRGB(): TFloriaColorSpace;
begin
  if GSharedAdobeRGB = nil then
    GSharedAdobeRGB := TFloriaColorSpace.CreateAdobeRGB();
  Result := GSharedAdobeRGB;
end;

// ---------------------------------------------------------------------------
// Initialization & Finalization
// ---------------------------------------------------------------------------

procedure InitSRGBToLinearLUT();
var
  I: Integer;
begin
  for I := 0 to 255 do
    GSRGBToLinearLUT[I] := SRGBToLinear(I / 255.0);
end;

initialization
  InitSRGBToLinearLUT();

finalization
  FreeAndNil(GSharedSRGB);
  FreeAndNil(GSharedLinearSRGB);
  FreeAndNil(GSharedDisplayP3);
  FreeAndNil(GSharedRec2020);
  FreeAndNil(GSharedAdobeRGB);

end.
