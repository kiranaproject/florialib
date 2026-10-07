unit Floria.ColorSpace.Test;

// Floria.ColorSpace.Test
// ======================
// Comprehensive unit tests for Floria.ColorSpace:
//   - Transfer functions (sRGB, Gamma 2.2, Gamma 2.8, PQ ST 2084, HLG BT.2100)
//   - Fast sRGB LUT precomputation and round-trips
//   - IEEE 754 half-precision float (FloatToHalf, HalfToFloat)
//   - High-precision pixel records (TRgbaF32, TRgbaF16, conversions to/from TBgraPixel)
//   - 3x3 matrix math (Invert, Multiply, TransformVector)
//   - Gamut transformations (sRGB, Display P3, Rec. 2020, Adobe RGB)
//   - Linear-light blending eliminating dark fringing on anti-aliased edges

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, fpcunit, testregistry,
  Floria.Image.Core,
  Floria.Canvas.Blend,
  Floria.ColorSpace;

type
  TFloriaColorSpaceTest = class(TTestCase)
  published
    // Transfer function tests
    procedure TestSRGBTransferRoundTrip();
    procedure TestPiecewiseThresholds();
    procedure TestGammaTransferFunctions();
    procedure TestPQTransferFunction();
    procedure TestHLGTransferFunction();
    procedure TestPrecomputedLUT();

    // IEEE 754 Half-Precision Float tests
    procedure TestHalfFloatSpecialValues();
    procedure TestHalfFloatNormalizedValues();
    procedure TestHalfFloatSubnormal();
    procedure TestHalfFloatClampingAndInfinity();

    // Pixel record tests
    procedure TestRgbaF32Basics();
    procedure TestRgbaF32PremultiplyDemultiply();
    procedure TestRgbaF32BgraConversions();
    procedure TestRgbaF16Basics();

    // Matrix and Color Space tests
    procedure TestMatrix3x3Math();
    procedure TestColorSpaceSingletons();
    procedure TestWhitePointPreservation();
    procedure TestGamutRoundTrip();
    procedure TestDisplayP3WideGamut();
    procedure TestTransformSpan();

    // Linear-light blending tests (elimination of dark fringing)
    procedure TestLinearLightEliminatesDarkFringing();
    procedure TestLinearBlendPorterDuff();
    procedure TestLinearBlendSeparable();
    procedure TestLinearBlendScanline();
    procedure TestFloatPixelBlending();
  end;

implementation

const
  FLOAT_TOLERANCE = 0.001;
  MATRIX_TOLERANCE = 0.0001;

// ---------------------------------------------------------------------------
// Transfer function tests
// ---------------------------------------------------------------------------

procedure TFloriaColorSpaceTest.TestSRGBTransferRoundTrip();
var
  Val, Lin, Back: Single;
  I: Integer;
begin
  // Test boundary values
  AssertEquals('0.0 to linear', 0.0, SRGBToLinear(0.0));
  AssertEquals('0.0 from linear', 0.0, LinearToSRGB(0.0));
  AssertTrue('1.0 to linear', Abs(SRGBToLinear(1.0) - 1.0) < FLOAT_TOLERANCE);
  AssertTrue('1.0 from linear', Abs(LinearToSRGB(1.0) - 1.0) < FLOAT_TOLERANCE);

  // Roundtrip across 100 sample steps
  for I := 1 to 99 do
  begin
    Val := I / 100.0;
    Lin := SRGBToLinear(Val);
    Back := LinearToSRGB(Lin);
    AssertTrue(Format('Roundtrip at %f: expected %f, got %f', [Val, Val, Back]),
      Abs(Back - Val) < FLOAT_TOLERANCE);
  end;
end;

procedure TFloriaColorSpaceTest.TestPiecewiseThresholds();
var
  TLinear, TCurve: Single;
begin
  // At exactly 0.04045, linear portion equals 0.04045 / 12.92 = 0.0031308...
  TLinear := 0.04045 / 12.92;
  TCurve := Power((0.04045 + 0.055) / 1.055, 2.4);
  AssertTrue('Continuity at 0.04045 threshold', Abs(TLinear - TCurve) < 0.0002);

  // Check function evaluation at threshold
  AssertTrue('SRGBToLinear at threshold', Abs(SRGBToLinear(0.04045) - TLinear) < 0.0001);
  AssertTrue('LinearToSRGB at threshold', Abs(LinearToSRGB(TLinear) - 0.04045) < 0.0002);
end;

procedure TFloriaColorSpaceTest.TestGammaTransferFunctions();
var
  V, Lin, Back: Single;
begin
  V := 0.5;
  // Gamma 2.2
  Lin := GammaToLinear(V, 2.2);
  Back := LinearToGamma(Lin, 2.2);
  AssertTrue('Gamma 2.2 roundtrip', Abs(Back - V) < FLOAT_TOLERANCE);

  // Gamma 2.8
  Lin := GammaToLinear(V, 2.8);
  Back := LinearToGamma(Lin, 2.8);
  AssertTrue('Gamma 2.8 roundtrip', Abs(Back - V) < FLOAT_TOLERANCE);
end;

procedure TFloriaColorSpaceTest.TestPQTransferFunction();
var
  V, Lin, Back: Single;
  I: Integer;
begin
  AssertEquals('PQ at 0.0', 0.0, PQToLinear(0.0));
  AssertTrue('PQ at 1.0', Abs(PQToLinear(1.0) - 1.0) < FLOAT_TOLERANCE);

  // Check roundtrip on normalized PQ range
  for I := 1 to 9 do
  begin
    V := I / 10.0;
    Lin := PQToLinear(V);
    Back := LinearToPQ(Lin);
    AssertTrue(Format('PQ roundtrip at %f: expected %f, got %f', [V, V, Back]),
      Abs(Back - V) < FLOAT_TOLERANCE);
  end;
end;

procedure TFloriaColorSpaceTest.TestHLGTransferFunction();
var
  V, Lin, Back: Single;
  I: Integer;
begin
  AssertEquals('HLG at 0.0', 0.0, HLGToLinear(0.0));

  for I := 1 to 9 do
  begin
    V := I / 10.0;
    Lin := HLGToLinear(V);
    Back := LinearToHLG(Lin);
    AssertTrue(Format('HLG roundtrip at %f: expected %f, got %f', [V, V, Back]),
      Abs(Back - V) < 0.005);
  end;
end;

procedure TFloriaColorSpaceTest.TestPrecomputedLUT();
var
  I: Integer;
  Expected: Single;
begin
  AssertEquals('LUT[0] is 0.0', 0.0, GSRGBToLinearLUT[0]);
  AssertTrue('LUT[255] is 1.0', Abs(GSRGBToLinearLUT[255] - 1.0) < 0.00001);

  for I := 0 to 255 do
  begin
    Expected := SRGBToLinear(I / 255.0);
    AssertTrue(Format('LUT[%d] matches direct calculation', [I]),
      Abs(GSRGBToLinearLUT[I] - Expected) < 0.00001);
    // LinearToSRGBByte roundtrip test
    if I in [0, 255] then
      AssertEquals(Format('LinearToSRGBByte roundtrip for %d', [I]), I, LinearToSRGBByte(GSRGBToLinearLUT[I]));
  end;
end;

// ---------------------------------------------------------------------------
// IEEE 754 Half-Precision Float tests
// ---------------------------------------------------------------------------

procedure TFloriaColorSpaceTest.TestHalfFloatSpecialValues();
var
  H: Word;
  Back: Single;
begin
  // +0.0
  H := FloatToHalf(0.0);
  AssertEquals('FloatToHalf(0.0) is $0000', $0000, H);
  Back := HalfToFloat(H);
  AssertEquals('HalfToFloat($0000) is 0.0', 0.0, Back);

  // -0.0
  H := FloatToHalf(-0.0);
  AssertEquals('FloatToHalf(-0.0) is $8000', $8000, H);
  Back := HalfToFloat(H);
  AssertEquals('HalfToFloat($8000) is -0.0', 0.0, Back);

  // +1.0
  H := FloatToHalf(1.0);
  AssertEquals('FloatToHalf(1.0) is $3C00', $3C00, H);
  Back := HalfToFloat(H);
  AssertEquals('HalfToFloat($3C00) is 1.0', 1.0, Back);

  // -1.0
  H := FloatToHalf(-1.0);
  AssertEquals('FloatToHalf(-1.0) is $BC00', $BC00, H);
  Back := HalfToFloat(H);
  AssertEquals('HalfToFloat($BC00) is -1.0', -1.0, Back);
end;

procedure TFloriaColorSpaceTest.TestHalfFloatNormalizedValues();
var
  H: Word;
  Back: Single;
  Vals: array[0..5] of Single = (0.5, 2.0, 1.5, 10.0, 100.0, 65504.0);
  I: Integer;
begin
  for I := 0 to High(Vals) do
  begin
    H := FloatToHalf(Vals[I]);
    Back := HalfToFloat(H);
    AssertTrue(Format('Half-float roundtrip for %f: got %f', [Vals[I], Back]),
      Abs(Back - Vals[I]) / Vals[I] < 0.002);
  end;
end;

procedure TFloriaColorSpaceTest.TestHalfFloatSubnormal();
var
  SmallVal: Single;
  H: Word;
  Back: Single;
begin
  // Smallest normalized half float is 2^(-14) ≈ 6.1035e-5
  // Values below that are subnormal
  SmallVal := 0.00001;
  H := FloatToHalf(SmallVal);
  AssertTrue('Subnormal produces non-zero half', H > 0);
  Back := HalfToFloat(H);
  AssertTrue('Subnormal converts back close to original', Abs(Back - SmallVal) < 0.000005);
end;

procedure TFloriaColorSpaceTest.TestHalfFloatClampingAndInfinity();
var
  HugeVal: Single;
  H: Word;
begin
  // Values above 65504 overflow to infinity ($7C00)
  HugeVal := 100000.0;
  H := FloatToHalf(HugeVal);
  AssertEquals('Overflow maps to infinity $7C00', $7C00, H);
end;

// ---------------------------------------------------------------------------
// Pixel record tests
// ---------------------------------------------------------------------------

procedure TFloriaColorSpaceTest.TestRgbaF32Basics();
var
  P: TRgbaF32;
begin
  P := TRgbaF32.Create(0.2, 0.4, 0.6, 0.8);
  AssertEquals('R channel', 0.2, P.R);
  AssertEquals('G channel', 0.4, P.G);
  AssertEquals('B channel', 0.6, P.B);
  AssertEquals('A channel', 0.8, P.A);

  // Clamp test
  P := TRgbaF32.Create(-0.5, 1.5, 0.5, 2.0).Clamp();
  AssertEquals('Clamped R', 0.0, P.R);
  AssertEquals('Clamped G', 1.0, P.G);
  AssertEquals('Clamped B', 0.5, P.B);
  AssertEquals('Clamped A', 1.0, P.A);
end;

procedure TFloriaColorSpaceTest.TestRgbaF32PremultiplyDemultiply();
var
  P, Premul, Demul: TRgbaF32;
begin
  P := TRgbaF32.Create(0.8, 0.6, 0.4, 0.5);
  Premul := P.Premultiply();

  AssertTrue('Premul R', Abs(Premul.R - 0.4) < 0.0001);
  AssertTrue('Premul G', Abs(Premul.G - 0.3) < 0.0001);
  AssertTrue('Premul B', Abs(Premul.B - 0.2) < 0.0001);
  AssertEquals('Premul A unchanged', 0.5, Premul.A);

  Demul := Premul.Demultiply();
  AssertTrue('Demul R', Abs(Demul.R - 0.8) < 0.0001);
  AssertTrue('Demul G', Abs(Demul.G - 0.6) < 0.0001);
  AssertTrue('Demul B', Abs(Demul.B - 0.4) < 0.0001);
  AssertEquals('Demul A', 0.5, Demul.A);
end;

procedure TFloriaColorSpaceTest.TestRgbaF32BgraConversions();
var
  Bgra: TBgraPixel;
  F32: TRgbaF32;
  BackBgra: TBgraPixel;
begin
  Bgra := TBgraPixel.Create(100, 150, 200, 255);
  F32 := TRgbaF32.FromBgra(Bgra);
  BackBgra := F32.ToBgra();

  AssertEquals('Bgra R roundtrip', 100, BackBgra.R);
  AssertEquals('Bgra G roundtrip', 150, BackBgra.G);
  AssertEquals('Bgra B roundtrip', 200, BackBgra.B);
  AssertEquals('Bgra A roundtrip', 255, BackBgra.A);

  // Linear conversion roundtrip
  F32 := TRgbaF32.FromBgraLinear(Bgra);
  BackBgra := F32.ToBgraLinear();
  AssertEquals('Linear Bgra R roundtrip', 100, BackBgra.R);
  AssertEquals('Linear Bgra G roundtrip', 150, BackBgra.G);
  AssertEquals('Linear Bgra B roundtrip', 200, BackBgra.B);
  AssertEquals('Linear Bgra A roundtrip', 255, BackBgra.A);
end;

procedure TFloriaColorSpaceTest.TestRgbaF16Basics();
var
  F16: TRgbaF16;
  F32, BackF32: TRgbaF32;
begin
  F32 := TRgbaF32.Create(0.25, 0.5, 0.75, 1.0);
  F16 := TRgbaF16.FromF32(F32);
  BackF32 := F16.ToF32();

  AssertTrue('F16 R roundtrip', Abs(BackF32.R - 0.25) < 0.001);
  AssertTrue('F16 G roundtrip', Abs(BackF32.G - 0.50) < 0.001);
  AssertTrue('F16 B roundtrip', Abs(BackF32.B - 0.75) < 0.001);
  AssertTrue('F16 A roundtrip', Abs(BackF32.A - 1.00) < 0.001);
end;

// ---------------------------------------------------------------------------
// Matrix and Color Space tests
// ---------------------------------------------------------------------------

procedure TFloriaColorSpaceTest.TestMatrix3x3Math();
var
  M, Inv, Prod: TMatrix3x3;
  I, J: Integer;
  OX, OY, OZ: Single;
begin
  // Identity transform
  M := TMatrix3x3.Identity();
  M.TransformVector(1.0, 2.0, 3.0, OX, OY, OZ);
  AssertEquals('Identity X', 1.0, OX);
  AssertEquals('Identity Y', 2.0, OY);
  AssertEquals('Identity Z', 3.0, OZ);

  // Invertible custom matrix
  M.M[0, 0] := 2.0; M.M[0, 1] := 1.0; M.M[0, 2] := 0.0;
  M.M[1, 0] := 0.0; M.M[1, 1] := 1.0; M.M[1, 2] := 2.0;
  M.M[2, 0] := 1.0; M.M[2, 1] := 0.0; M.M[2, 2] := 1.0;

  AssertTrue('Matrix invertible', M.Invert(Inv));
  Prod := M.Multiply(Inv);

  for I := 0 to 2 do
    for J := 0 to 2 do
      if I = J then
        AssertTrue(Format('Diagonal [%d,%d] is 1.0', [I, J]), Abs(Prod.M[I, J] - 1.0) < MATRIX_TOLERANCE)
      else
        AssertTrue(Format('Off-diagonal [%d,%d] is 0.0', [I, J]), Abs(Prod.M[I, J]) < MATRIX_TOLERANCE);
end;

procedure TFloriaColorSpaceTest.TestColorSpaceSingletons();
begin
  AssertNotNull('sRGB singleton', FloriaColorSpaceSRGB());
  AssertNotNull('Linear sRGB singleton', FloriaColorSpaceLinearSRGB());
  AssertNotNull('Display P3 singleton', FloriaColorSpaceDisplayP3());
  AssertNotNull('Rec. 2020 singleton', FloriaColorSpaceRec2020());
  AssertNotNull('Adobe RGB singleton', FloriaColorSpaceAdobeRGB());

  AssertEquals('sRGB type', Ord(fcstSRGB), Ord(FloriaColorSpaceSRGB().ColorSpaceType));
  AssertEquals('Linear sRGB type', Ord(fcstLinearSRGB), Ord(FloriaColorSpaceLinearSRGB().ColorSpaceType));
  AssertEquals('Display P3 type', Ord(fcstDisplayP3), Ord(FloriaColorSpaceDisplayP3().ColorSpaceType));
  AssertEquals('Rec. 2020 type', Ord(fcstRec2020), Ord(FloriaColorSpaceRec2020().ColorSpaceType));
  AssertEquals('Adobe RGB type', Ord(fcstAdobeRGB), Ord(FloriaColorSpaceAdobeRGB().ColorSpaceType));
end;

procedure TFloriaColorSpaceTest.TestWhitePointPreservation();
var
  White, P3White, RecWhite, AdobeWhite: TRgbaF32;
  SRGB, P3, Rec, Adobe: TFloriaColorSpace;
begin
  White := TRgbaF32.Create(1.0, 1.0, 1.0, 1.0);
  SRGB := FloriaColorSpaceSRGB();
  P3 := FloriaColorSpaceDisplayP3();
  Rec := FloriaColorSpaceRec2020();
  Adobe := FloriaColorSpaceAdobeRGB();

  P3White := SRGB.Transform(White, P3);
  AssertTrue('White in Display P3 R is 1.0', Abs(P3White.R - 1.0) < 0.005);
  AssertTrue('White in Display P3 G is 1.0', Abs(P3White.G - 1.0) < 0.005);
  AssertTrue('White in Display P3 B is 1.0', Abs(P3White.B - 1.0) < 0.005);

  RecWhite := SRGB.Transform(White, Rec);
  AssertTrue('White in Rec. 2020 R is 1.0', Abs(RecWhite.R - 1.0) < 0.005);
  AssertTrue('White in Rec. 2020 G is 1.0', Abs(RecWhite.G - 1.0) < 0.005);
  AssertTrue('White in Rec. 2020 B is 1.0', Abs(RecWhite.B - 1.0) < 0.005);

  AdobeWhite := SRGB.Transform(White, Adobe);
  AssertTrue('White in Adobe RGB R is 1.0', Abs(AdobeWhite.R - 1.0) < 0.005);
  AssertTrue('White in Adobe RGB G is 1.0', Abs(AdobeWhite.G - 1.0) < 0.005);
  AssertTrue('White in Adobe RGB B is 1.0', Abs(AdobeWhite.B - 1.0) < 0.005);
end;

procedure TFloriaColorSpaceTest.TestGamutRoundTrip();
var
  Original, Transformed, Restored: TRgbaF32;
  SRGB, P3: TFloriaColorSpace;
begin
  SRGB := FloriaColorSpaceSRGB();
  P3 := FloriaColorSpaceDisplayP3();

  Original := TRgbaF32.Create(0.7, 0.4, 0.2, 0.9);
  Transformed := SRGB.Transform(Original, P3);
  Restored := P3.Transform(Transformed, SRGB);

  AssertTrue('Roundtrip R', Abs(Restored.R - Original.R) < 0.001);
  AssertTrue('Roundtrip G', Abs(Restored.G - Original.G) < 0.001);
  AssertTrue('Roundtrip B', Abs(Restored.B - Original.B) < 0.001);
  AssertEquals('Roundtrip A unchanged', Original.A, Restored.A);
end;

procedure TFloriaColorSpaceTest.TestDisplayP3WideGamut();
var
  SrgbRed, P3Color: TRgbaF32;
  SRGB, P3: TFloriaColorSpace;
begin
  SRGB := FloriaColorSpaceSRGB();
  P3 := FloriaColorSpaceDisplayP3();

  // Pure sRGB Red is within the Display P3 gamut, so in Display P3
  // its red coordinate is less than 1.0 (~0.917)
  SrgbRed := TRgbaF32.Create(1.0, 0.0, 0.0, 1.0);
  P3Color := SRGB.Transform(SrgbRed, P3);

  AssertTrue('sRGB Red in Display P3 has R < 1.0', P3Color.R < 0.95);
  AssertTrue('sRGB Red in Display P3 has R > 0.85', P3Color.R > 0.85);
end;

procedure TFloriaColorSpaceTest.TestTransformSpan();
var
  Src, Dst: array[0..2] of TRgbaF32;
  SRGB, P3: TFloriaColorSpace;
begin
  SRGB := FloriaColorSpaceSRGB();
  P3 := FloriaColorSpaceDisplayP3();

  Src[0] := TRgbaF32.Create(1.0, 1.0, 1.0, 1.0);
  Src[1] := TRgbaF32.Create(0.5, 0.5, 0.5, 1.0);
  Src[2] := TRgbaF32.Create(0.0, 0.0, 0.0, 1.0);

  SRGB.TransformSpan(@Src[0], @Dst[0], 3, P3);

  AssertTrue('Span item 0 white', Abs(Dst[0].R - 1.0) < 0.005);
  AssertTrue('Span item 2 black', Abs(Dst[2].R - 0.0) < 0.005);
end;

// ---------------------------------------------------------------------------
// Linear-light blending tests (elimination of dark fringing)
// ---------------------------------------------------------------------------

procedure TFloriaColorSpaceTest.TestLinearLightEliminatesDarkFringing();
var
  DstPixel: TBgraPixel;
  SrcPixel: TBgraPixel;
begin
  // The classic color fringe test:
  // Blend pure Red onto pure Green with 50% opacity (coverage = 128 / alpha = 128).
  //
  // In non-linear sRGB (gamma ~2.2) blending:
  //   R = 0.5 * 255 + 0.5 * 0 = 128
  //   G = 0.5 * 0 + 0.5 * 255 = 128
  // Result is (128, 128, 0) which has only 21.6% luminance — a muddy olive-brown fringe!
  //
  // In linear-light blending:
  //   Linear intensities are 50% Red + 50% Green -> (0.502, 0.498, 0.0) in linear.
  //   Converting back to sRGB gives LinearToSRGB(0.502) * 255 ≈ 188!
  // Result is a bright, vibrant, luminous yellow (R ≈ 188, G ≈ 187)!

  DstPixel := TBgraPixel.Create(0, 255, 0, 255); // Pure Green
  SrcPixel := TBgraPixel.Create(255, 0, 0, 255); // Pure Red with 50% coverage
  FloriaBlendPixelLinear(@DstPixel, SrcPixel, fbmSrcOver, 128);

  // Assert that linear blending produces luminous yellow (> 180), NOT the dark muddy 128!
  AssertTrue(Format('Linear Red channel is vibrant yellow: got %d (must be >= 180, not dark 128)', [DstPixel.R]),
    DstPixel.R >= 180);
  AssertTrue(Format('Linear Green channel is vibrant yellow: got %d (must be >= 180, not dark 128)', [DstPixel.G]),
    DstPixel.G >= 180);
  AssertEquals('Blue channel remains 0', 0, DstPixel.B);
  AssertEquals('Alpha channel remains 255', 255, DstPixel.A);
end;

procedure TFloriaColorSpaceTest.TestLinearBlendPorterDuff();
var
  DstPixel, SrcPixel: TBgraPixel;
begin
  // Test fbmClear
  DstPixel := TBgraPixel.Create(200, 200, 200, 255);
  SrcPixel := TBgraPixel.Create(100, 100, 100, 255);
  FloriaBlendPixelLinear(@DstPixel, SrcPixel, fbmClear, 255);
  AssertEquals('Clear R', 0, DstPixel.R);
  AssertEquals('Clear A', 0, DstPixel.A);

  // Test fbmSrc
  DstPixel := TBgraPixel.Create(50, 50, 50, 255);
  SrcPixel := TBgraPixel.Create(220, 180, 140, 255);
  FloriaBlendPixelLinear(@DstPixel, SrcPixel, fbmSrc, 255);
  AssertEquals('Src R', 220, DstPixel.R);
  AssertEquals('Src G', 180, DstPixel.G);
  AssertEquals('Src B', 140, DstPixel.B);

  // Test fbmDst (no-op)
  DstPixel := TBgraPixel.Create(50, 60, 70, 255);
  SrcPixel := TBgraPixel.Create(200, 200, 200, 255);
  FloriaBlendPixelLinear(@DstPixel, SrcPixel, fbmDst, 255);
  AssertEquals('Dst R unchanged', 50, DstPixel.R);
  AssertEquals('Dst G unchanged', 60, DstPixel.G);
  AssertEquals('Dst B unchanged', 70, DstPixel.B);
end;

procedure TFloriaColorSpaceTest.TestLinearBlendSeparable();
var
  DstPixel, SrcPixel: TBgraPixel;
begin
  // Test fbmMultiply in linear space
  DstPixel := TBgraPixel.Create(255, 255, 255, 255); // White
  SrcPixel := TBgraPixel.Create(128, 64, 32, 255);
  FloriaBlendPixelLinear(@DstPixel, SrcPixel, fbmMultiply, 255);
  // White multiplied by color equals color
  AssertTrue('Multiply with white preserves R', Abs(DstPixel.R - 128) <= 2);
  AssertTrue('Multiply with white preserves G', Abs(DstPixel.G - 64) <= 2);
  AssertTrue('Multiply with white preserves B', Abs(DstPixel.B - 32) <= 2);
end;

procedure TFloriaColorSpaceTest.TestLinearBlendScanline();
var
  DstRow, SrcRow: array[0..3] of TBgraPixel;
  I: Integer;
begin
  for I := 0 to 3 do
  begin
    DstRow[I] := TBgraPixel.Create(0, 255, 0, 255); // Green
    SrcRow[I] := TBgraPixel.Create(255, 0, 0, 255); // Red
  end;

  FloriaBlendScanlineLinear(@DstRow[0], @SrcRow[0], 4, fbmSrcOver, 128);

  for I := 0 to 3 do
  begin
    AssertTrue(Format('Scanline pixel %d R >= 180', [I]), DstRow[I].R >= 180);
    AssertTrue(Format('Scanline pixel %d G >= 180', [I]), DstRow[I].G >= 180);
    AssertEquals(Format('Scanline pixel %d B = 0', [I]), 0, DstRow[I].B);
  end;
end;

procedure TFloriaColorSpaceTest.TestFloatPixelBlending();
var
  DstF, SrcF: TRgbaF32;
begin
  DstF := TRgbaF32.Create(0.0, 1.0, 0.0, 1.0); // Premultiplied linear Green
  SrcF := TRgbaF32.Create(1.0, 0.0, 0.0, 1.0); // Premultiplied linear Red

  // Blend with 50% coverage
  FloriaBlendPixelF32(@DstF, SrcF, fbmSrcOver, 0.5);

  AssertTrue('Float blend R is 0.5', Abs(DstF.R - 0.5) < 0.01);
  AssertTrue('Float blend G is 0.5', Abs(DstF.G - 0.5) < 0.01);
  AssertEquals('Float blend B is 0.0', 0.0, DstF.B);
  AssertEquals('Float blend A is 1.0', 1.0, DstF.A);
end;

initialization
  RegisterTest(TFloriaColorSpaceTest);

end.
