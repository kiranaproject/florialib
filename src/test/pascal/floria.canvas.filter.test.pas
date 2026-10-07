unit Floria.Canvas.Filter.Test;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Math, fpcunit, testregistry,
  Floria.Image.Core, Floria.Canvas.Blend, Floria.Canvas.Filter;

type
  TFloriaCanvasFilterTest = class(TTestCase)
  published
    // Color matrix filters
    procedure TestColorMatrixIdentity();
    procedure TestColorMatrixGrayscale();
    procedure TestColorMatrixInvert();
    procedure TestColorMatrixSaturation();
    procedure TestColorMatrixContrast();
    procedure TestColorMatrixTint();
    procedure TestColorMatrixBrightness();

    // Blur filters
    procedure TestBlurBox();
    procedure TestBlurGaussian();
    procedure TestBlurDualKawase();

    // Drop shadow
    procedure TestDropShadowComposite();
    procedure TestDropShadowOnly();

    // Morphology
    procedure TestMorphologyDilate();
    procedure TestMorphologyErode();

    // Displacement map
    procedure TestDisplacementMap();

    // Composition & pipeline
    procedure TestComposeChaining();
    procedure TestCompositeBlend();
    procedure TestApplyInPlace();
    procedure TestSubRectBounds();
    procedure TestNilImageSafety();
  end;

implementation

procedure TFloriaCanvasFilterTest.TestColorMatrixIdentity();
var
  Filter: TColorMatrixFilter;
  Src, Dst: TFloriaImage;
  X, Y: Integer;
begin
  Src := TFloriaImage.Create(16, 16, fpfBGRA32);
  try
    for Y := 0 to 15 do
      for X := 0 to 15 do
        Src.Pixels[X, Y] := TBgraPixel.Create(X * 16, Y * 16, (X + Y) * 8, 255);

    Filter := TColorMatrixFilter.Create();
    try
      Dst := Filter.Apply(Src);
      try
        AssertNotNull('Destination image should not be nil', Dst);
        for Y := 0 to 15 do
          for X := 0 to 15 do
          begin
            AssertEquals('Identity Red mismatch at ' + IntToStr(X) + ',' + IntToStr(Y),
              Src.Pixels[X, Y].R, Dst.Pixels[X, Y].R);
            AssertEquals('Identity Green mismatch at ' + IntToStr(X) + ',' + IntToStr(Y),
              Src.Pixels[X, Y].G, Dst.Pixels[X, Y].G);
            AssertEquals('Identity Blue mismatch at ' + IntToStr(X) + ',' + IntToStr(Y),
              Src.Pixels[X, Y].B, Dst.Pixels[X, Y].B);
            AssertEquals('Identity Alpha mismatch at ' + IntToStr(X) + ',' + IntToStr(Y),
              Src.Pixels[X, Y].A, Dst.Pixels[X, Y].A);
          end;
      finally
        Dst.Free();
      end;
    finally
      Filter.Free();
    end;
  finally
    Src.Free();
  end;
end;

procedure TFloriaCanvasFilterTest.TestColorMatrixGrayscale();
var
  Filter: TColorMatrixFilter;
  Src, Dst: TFloriaImage;
  Pix: TBgraPixel;
  ExpectedLuma: Byte;
begin
  Src := TFloriaImage.Create(4, 4, fpfBGRA32);
  try
    Src.Clear(100, 150, 200, 255); // R=100, G=150, B=200, A=255
    // Luminance = Round(0.2126*100 + 0.7152*150 + 0.0722*200) = Round(142.98) = 143
    ExpectedLuma := Round(0.2126 * 100.0 + 0.7152 * 150.0 + 0.0722 * 200.0);

    Filter := TColorMatrixFilter.CreateGrayscale();
    try
      Dst := Filter.Apply(Src);
      try
        Pix := Dst.Pixels[0, 0];
        AssertEquals('Grayscale R channel', ExpectedLuma, Pix.R);
        AssertEquals('Grayscale G channel', ExpectedLuma, Pix.G);
        AssertEquals('Grayscale B channel', ExpectedLuma, Pix.B);
        AssertEquals('Grayscale A preserved', 255, Pix.A);
      finally
        Dst.Free();
      end;
    finally
      Filter.Free();
    end;
  finally
    Src.Free();
  end;
end;

procedure TFloriaCanvasFilterTest.TestColorMatrixInvert();
var
  Filter: TColorMatrixFilter;
  Src, Dst: TFloriaImage;
  Pix: TBgraPixel;
begin
  Src := TFloriaImage.Create(4, 4, fpfBGRA32);
  try
    Src.Clear(50, 100, 200, 255);

    Filter := TColorMatrixFilter.CreateInvert();
    try
      Dst := Filter.Apply(Src);
      try
        Pix := Dst.Pixels[0, 0];
        AssertEquals('Invert R', 205, Pix.R);
        AssertEquals('Invert G', 155, Pix.G);
        AssertEquals('Invert B', 55, Pix.B);
        AssertEquals('Invert A preserved', 255, Pix.A);
      finally
        Dst.Free();
      end;
    finally
      Filter.Free();
    end;
  finally
    Src.Free();
  end;
end;

procedure TFloriaCanvasFilterTest.TestColorMatrixSaturation();
var
  FilterGray, FilterBoost: TColorMatrixFilter;
  Src, DstGray, DstBoost: TFloriaImage;
  PixGray, PixBoost: TBgraPixel;
begin
  Src := TFloriaImage.Create(4, 4, fpfBGRA32);
  try
    Src.Clear(200, 50, 50, 255);

    // Saturation 0 should make R=G=B
    FilterGray := TColorMatrixFilter.CreateSaturation(0.0);
    try
      DstGray := FilterGray.Apply(Src);
      try
        PixGray := DstGray.Pixels[0, 0];
        AssertTrue('Sat=0 R should equal G within 1', Abs(PixGray.R - PixGray.G) <= 1);
        AssertTrue('Sat=0 G should equal B within 1', Abs(PixGray.G - PixGray.B) <= 1);
      finally
        DstGray.Free();
      end;
    finally
      FilterGray.Free();
    end;

    // Saturation 2 should boost chromaticity (R higher, G/B lower or unchanged)
    FilterBoost := TColorMatrixFilter.CreateSaturation(2.0);
    try
      DstBoost := FilterBoost.Apply(Src);
      try
        PixBoost := DstBoost.Pixels[0, 0];
        AssertTrue('Sat=2 R should be higher than original', PixBoost.R >= 200);
      finally
        DstBoost.Free();
      end;
    finally
      FilterBoost.Free();
    end;
  finally
    Src.Free();
  end;
end;

procedure TFloriaCanvasFilterTest.TestColorMatrixContrast();
var
  Filter: TColorMatrixFilter;
  Src, Dst: TFloriaImage;
  PixHigh, PixLow: TBgraPixel;
begin
  Src := TFloriaImage.Create(4, 4, fpfBGRA32);
  try
    Src.Pixels[0, 0] := TBgraPixel.Create(200, 200, 200, 255); // > 128
    Src.Pixels[1, 0] := TBgraPixel.Create(50, 50, 50, 255);    // < 128

    Filter := TColorMatrixFilter.CreateContrast(1.5);
    try
      Dst := Filter.Apply(Src);
      try
        PixHigh := Dst.Pixels[0, 0];
        PixLow := Dst.Pixels[1, 0];
        // High values get brighter, low values get darker
        AssertTrue('High contrast brightened above 200', PixHigh.R > 200);
        AssertTrue('High contrast darkened below 50', PixLow.R < 50);
      finally
        Dst.Free();
      end;
    finally
      Filter.Free();
    end;
  finally
    Src.Free();
  end;
end;

procedure TFloriaCanvasFilterTest.TestColorMatrixTint();
var
  Filter: TColorMatrixFilter;
  Src, Dst: TFloriaImage;
  Pix: TBgraPixel;
begin
  Src := TFloriaImage.Create(4, 4, fpfBGRA32);
  try
    Src.Clear(200, 200, 200, 255);

    Filter := TColorMatrixFilter.CreateTint(1.0, 0.0, 0.0);
    try
      Dst := Filter.Apply(Src);
      try
        Pix := Dst.Pixels[0, 0];
        AssertEquals('Tint preserves Red', 200, Pix.R);
        AssertEquals('Tint zeroes Green', 0, Pix.G);
        AssertEquals('Tint zeroes Blue', 0, Pix.B);
        AssertEquals('Tint preserves Alpha', 255, Pix.A);
      finally
        Dst.Free();
      end;
    finally
      Filter.Free();
    end;
  finally
    Src.Free();
  end;
end;

procedure TFloriaCanvasFilterTest.TestColorMatrixBrightness();
var
  Filter: TColorMatrixFilter;
  Src, Dst: TFloriaImage;
  Pix: TBgraPixel;
begin
  Src := TFloriaImage.Create(4, 4, fpfBGRA32);
  try
    Src.Clear(100, 100, 100, 255);

    Filter := TColorMatrixFilter.CreateBrightness(0.2); // +51
    try
      Dst := Filter.Apply(Src);
      try
        Pix := Dst.Pixels[0, 0];
        AssertTrue('Brightness increased by approx 51', Abs(Pix.R - 151) <= 2);
      finally
        Dst.Free();
      end;
    finally
      Filter.Free();
    end;
  finally
    Src.Free();
  end;
end;

procedure TFloriaCanvasFilterTest.TestBlurBox();
var
  Filter: TBlurFilter;
  Src, Dst: TFloriaImage;
  X, Y: Integer;
  EdgePix: TBgraPixel;
begin
  Src := TFloriaImage.Create(32, 32, fpfBGRA32);
  try
    for Y := 0 to 31 do
      for X := 0 to 31 do
      begin
        if X < 16 then
          Src.Pixels[X, Y] := TBgraPixel.Create(0, 0, 0, 255)
        else
          Src.Pixels[X, Y] := TBgraPixel.Create(255, 255, 255, 255);
      end;

    Filter := TBlurFilter.Create(3.0, fbtBox);
    try
      Dst := Filter.Apply(Src);
      try
        EdgePix := Dst.Pixels[16, 16];
        AssertTrue('Box blur smooths boundary', (EdgePix.R > 30) and (EdgePix.R < 225));
        // Boundary left should be blended
        AssertTrue('Left near edge blended', Dst.Pixels[15, 16].R > 0);
        // Boundary right should be blended
        AssertTrue('Right near edge blended', Dst.Pixels[17, 16].R < 255);
      finally
        Dst.Free();
      end;
    finally
      Filter.Free();
    end;
  finally
    Src.Free();
  end;
end;

procedure TFloriaCanvasFilterTest.TestBlurGaussian();
var
  Filter: TBlurFilter;
  Src, Dst: TFloriaImage;
  X, Y: Integer;
  PrevR: Byte;
begin
  Src := TFloriaImage.Create(32, 32, fpfBGRA32);
  try
    for Y := 0 to 31 do
      for X := 0 to 31 do
      begin
        if X < 16 then
          Src.Pixels[X, Y] := TBgraPixel.Create(0, 0, 0, 255)
        else
          Src.Pixels[X, Y] := TBgraPixel.Create(255, 255, 255, 255);
      end;

    Filter := TBlurFilter.Create(4.0, fbtGaussian);
    try
      Dst := Filter.Apply(Src);
      try
        // Verify smooth monotonic ramp across the boundary in row 16
        PrevR := Dst.Pixels[0, 16].R;
        for X := 1 to 31 do
        begin
          AssertTrue('Gaussian blur monotonic progression at X=' + IntToStr(X),
            Dst.Pixels[X, 16].R >= PrevR);
          PrevR := Dst.Pixels[X, 16].R;
        end;

        // The edge at 16 should be close to mid-gray 128
        AssertTrue('Gaussian edge near 128', Abs(Dst.Pixels[16, 16].R - 128) < 35);
      finally
        Dst.Free();
      end;
    finally
      Filter.Free();
    end;
  finally
    Src.Free();
  end;
end;

procedure TFloriaCanvasFilterTest.TestBlurDualKawase();
var
  Filter: TBlurFilter;
  Src, Dst: TFloriaImage;
  X, Y: Integer;
begin
  Src := TFloriaImage.Create(32, 32, fpfBGRA32);
  try
    for Y := 0 to 31 do
      for X := 0 to 31 do
      begin
        if X < 16 then
          Src.Pixels[X, Y] := TBgraPixel.Create(0, 0, 0, 255)
        else
          Src.Pixels[X, Y] := TBgraPixel.Create(255, 255, 255, 255);
      end;

    Filter := TBlurFilter.Create(2.0, fbtDualKawase);
    try
      Dst := Filter.Apply(Src);
      try
        AssertTrue('DualKawase smooths edge',
          (Dst.Pixels[16, 16].R > 40) and (Dst.Pixels[16, 16].R < 215));
      finally
        Dst.Free();
      end;
    finally
      Filter.Free();
    end;
  finally
    Src.Free();
  end;
end;

procedure TFloriaCanvasFilterTest.TestDropShadowComposite();
var
  Filter: TDropShadowFilter;
  Src, Dst: TFloriaImage;
  X, Y: Integer;
begin
  Src := TFloriaImage.Create(32, 32, fpfBGRA32);
  try
    Src.Clear(0, 0, 0, 0);
    // Draw 8x8 white square in the center (12..19, 12..19)
    for Y := 12 to 19 do
      for X := 12 to 19 do
        Src.Pixels[X, Y] := TBgraPixel.Create(255, 255, 255, 255);

    // Drop shadow: DX=4, DY=4, Sigma=0, ShadowColor=Black (0,0,0,255)
    Filter := TDropShadowFilter.Create(4, 4, 0.0, TBgraPixel.Create(0, 0, 0, 255), False);
    try
      Dst := Filter.Apply(Src);
      try
        // Source object is present at (16, 16) -> White
        AssertEquals('Source object visible at center', 255, Dst.Pixels[16, 16].R);
        AssertEquals('Source object alpha at center', 255, Dst.Pixels[16, 16].A);

        // Shadow offset at (22, 22) -> Black shadow with alpha > 0
        AssertTrue('Shadow visible at offset position', Dst.Pixels[22, 22].A > 0);
        AssertEquals('Shadow color is black', 0, Dst.Pixels[22, 22].R);

        // Blank area at (2, 2) has no shadow or source
        AssertEquals('Blank area transparent', 0, Dst.Pixels[2, 2].A);
      finally
        Dst.Free();
      end;
    finally
      Filter.Free();
    end;
  finally
    Src.Free();
  end;
end;

procedure TFloriaCanvasFilterTest.TestDropShadowOnly();
var
  Filter: TDropShadowFilter;
  Src, Dst: TFloriaImage;
  X, Y: Integer;
begin
  Src := TFloriaImage.Create(32, 32, fpfBGRA32);
  try
    Src.Clear(0, 0, 0, 0);
    for Y := 12 to 19 do
      for X := 12 to 19 do
        Src.Pixels[X, Y] := TBgraPixel.Create(255, 255, 255, 255);

    Filter := TDropShadowFilter.Create(4, 4, 0.0, TBgraPixel.Create(0, 0, 0, 255), True);
    try
      Dst := Filter.Apply(Src);
      try
        // In shadow-only mode, the source white block at (12, 12) is NOT drawn
        // Only the shadow offset (16..23, 16..23) should exist
        AssertEquals('Source top-left not drawn in shadow-only', 0, Dst.Pixels[12, 12].A);
        // Shadow offset is drawn
        AssertTrue('Shadow offset exists', Dst.Pixels[20, 20].A > 0);
        AssertEquals('Shadow color R is 0', 0, Dst.Pixels[20, 20].R);
      finally
        Dst.Free();
      end;
    finally
      Filter.Free();
    end;
  finally
    Src.Free();
  end;
end;

procedure TFloriaCanvasFilterTest.TestMorphologyDilate();
var
  Filter: TMorphologyFilter;
  Src, Dst: TFloriaImage;
begin
  Src := TFloriaImage.Create(16, 16, fpfBGRA32);
  try
    Src.Clear(0, 0, 0, 255);
    // Single white pixel at (8, 8)
    Src.Pixels[8, 8] := TBgraPixel.Create(255, 255, 255, 255);

    Filter := TMorphologyFilter.Create(fmoDilate, 2);
    try
      Dst := Filter.Apply(Src);
      try
        // Dilate expands the single pixel into a 5x5 square (from 6 to 10)
        AssertEquals('Dilate center', 255, Dst.Pixels[8, 8].R);
        AssertEquals('Dilate corner 6,6', 255, Dst.Pixels[6, 6].R);
        AssertEquals('Dilate corner 10,10', 255, Dst.Pixels[10, 10].R);
        // Outside 5x5 square remains black
        AssertEquals('Outside dilate X=5', 0, Dst.Pixels[5, 8].R);
        AssertEquals('Outside dilate X=11', 0, Dst.Pixels[11, 8].R);
        AssertEquals('Outside dilate Y=5', 0, Dst.Pixels[8, 5].R);
        AssertEquals('Outside dilate Y=11', 0, Dst.Pixels[8, 11].R);
      finally
        Dst.Free();
      end;
    finally
      Filter.Free();
    end;
  finally
    Src.Free();
  end;
end;

procedure TFloriaCanvasFilterTest.TestMorphologyErode();
var
  Filter: TMorphologyFilter;
  Src, Dst: TFloriaImage;
  X, Y: Integer;
begin
  Src := TFloriaImage.Create(16, 16, fpfBGRA32);
  try
    Src.Clear(0, 0, 0, 255);
    // 5x5 white square at (6..10, 6..10)
    for Y := 6 to 10 do
      for X := 6 to 10 do
        Src.Pixels[X, Y] := TBgraPixel.Create(255, 255, 255, 255);

    Filter := TMorphologyFilter.Create(fmoErode, 1);
    try
      Dst := Filter.Apply(Src);
      try
        // Erode contracts by 1 pixel on all sides, leaving a 3x3 square (7..9, 7..9)
        AssertEquals('Erode center 8,8', 255, Dst.Pixels[8, 8].R);
        AssertEquals('Erode inner corner 7,7', 255, Dst.Pixels[7, 7].R);
        AssertEquals('Erode inner corner 9,9', 255, Dst.Pixels[9, 9].R);
        // Perimeter at 6 and 10 must now be eroded away to 0
        AssertEquals('Eroded border 6,8', 0, Dst.Pixels[6, 8].R);
        AssertEquals('Eroded border 10,8', 0, Dst.Pixels[10, 8].R);
        AssertEquals('Eroded border 8,6', 0, Dst.Pixels[8, 6].R);
        AssertEquals('Eroded border 8,10', 0, Dst.Pixels[8, 10].R);
      finally
        Dst.Free();
      end;
    finally
      Filter.Free();
    end;
  finally
    Src.Free();
  end;
end;

procedure TFloriaCanvasFilterTest.TestDisplacementMap();
var
  Src, MapImg, Dst: TFloriaImage;
  Filter: TDisplacementMapFilter;
  X, Y: Integer;
begin
  Src := TFloriaImage.Create(16, 16, fpfBGRA32);
  MapImg := TFloriaImage.Create(16, 16, fpfBGRA32);
  try
    // Source: horizontal gradient where Red increases with X
    for Y := 0 to 15 do
      for X := 0 to 15 do
        Src.Pixels[X, Y] := TBgraPixel.Create(X * 16, 0, 0, 255);

    // Map: Red channel = 255 (value = 1.0 - 0.5 = +0.5 shift), Green = 128 (0 shift)
    MapImg.Clear(255, 128, 0, 255);

    // Scale = 4: DX = 0.5 * 4 = +2.0 pixels
    Filter := TDisplacementMapFilter.Create(MapImg, 4.0, fccRed, fccGreen);
    try
      Dst := Filter.Apply(Src);
      try
        AssertNotNull('Displaced image should exist', Dst);
        // Pixel at X=5 should sample from X=5 + 2 = 7
        // Src at X=7 has R = 7 * 16 = 112
        AssertTrue('Pixel at X=5 displaced to sample X=7',
          Abs(Dst.Pixels[5, 5].R - Src.Pixels[7, 5].R) <= 8);
      finally
        Dst.Free();
      end;
    finally
      Filter.Free();
    end;
  finally
    MapImg.Free();
    Src.Free();
  end;
end;

procedure TFloriaCanvasFilterTest.TestComposeChaining();
var
  Invert1, Invert2: TFloriaImageFilter;
  Composed: TFloriaImageFilter;
  Src, Dst: TFloriaImage;
  X, Y: Integer;
begin
  Src := TFloriaImage.Create(8, 8, fpfBGRA32);
  try
    for Y := 0 to 7 do
      for X := 0 to 7 do
        Src.Pixels[X, Y] := TBgraPixel.Create(X * 30, Y * 30, 100, 255);

    Invert1 := TColorMatrixFilter.CreateInvert();
    Invert2 := TColorMatrixFilter.CreateInvert();

    // Invert followed by Invert should restore original pixels
    Composed := TComposeFilter.Create(Invert1, Invert2, True);
    try
      Dst := Composed.Apply(Src);
      try
        for Y := 0 to 7 do
          for X := 0 to 7 do
          begin
            AssertEquals('Double inversion restored R', Src.Pixels[X, Y].R, Dst.Pixels[X, Y].R);
            AssertEquals('Double inversion restored G', Src.Pixels[X, Y].G, Dst.Pixels[X, Y].G);
            AssertEquals('Double inversion restored B', Src.Pixels[X, Y].B, Dst.Pixels[X, Y].B);
          end;
      finally
        Dst.Free();
      end;
    finally
      Composed.Free(); // Destroys owned Invert1 and Invert2
    end;
  finally
    Src.Free();
  end;
end;

procedure TFloriaCanvasFilterTest.TestCompositeBlend();
var
  FilterRed, FilterGreen: TFloriaImageFilter;
  Composite: TFloriaImageFilter;
  Src, Dst: TFloriaImage;
begin
  Src := TFloriaImage.Create(8, 8, fpfBGRA32);
  try
    Src.Clear(255, 255, 255, 255);

    FilterRed := TColorMatrixFilter.CreateTint(1.0, 0.0, 0.0);
    FilterGreen := TColorMatrixFilter.CreateTint(0.0, 1.0, 0.0);

    // Composite Red over Green using Plus blend mode (Red + Green = Yellow)
    Composite := TCompositeFilter.Create(FilterRed, FilterGreen, fbmPlus, True);
    try
      Dst := Composite.Apply(Src);
      try
        AssertEquals('Composite Plus Red', 255, Dst.Pixels[0, 0].R);
        AssertEquals('Composite Plus Green', 255, Dst.Pixels[0, 0].G);
        AssertEquals('Composite Plus Blue', 0, Dst.Pixels[0, 0].B);
      finally
        Dst.Free();
      end;
    finally
      Composite.Free();
    end;
  finally
    Src.Free();
  end;
end;

procedure TFloriaCanvasFilterTest.TestApplyInPlace();
var
  Filter: TColorMatrixFilter;
  Img: TFloriaImage;
begin
  Img := TFloriaImage.Create(4, 4, fpfBGRA32);
  try
    Img.Clear(100, 150, 200, 255);

    Filter := TColorMatrixFilter.CreateInvert();
    try
      Filter.ApplyInPlace(Img);
      AssertEquals('In-place inverted R', 155, Img.Pixels[0, 0].R);
      AssertEquals('In-place inverted G', 105, Img.Pixels[0, 0].G);
      AssertEquals('In-place inverted B', 55, Img.Pixels[0, 0].B);
    finally
      Filter.Free();
    end;
  finally
    Img.Free();
  end;
end;

procedure TFloriaCanvasFilterTest.TestSubRectBounds();
var
  Filter: TColorMatrixFilter;
  Img, Dst: TFloriaImage;
begin
  Img := TFloriaImage.Create(16, 16, fpfBGRA32);
  try
    Img.Clear(100, 100, 100, 255);

    Filter := TColorMatrixFilter.CreateInvert();
    try
      // Apply invert only to sub-rect (4, 4, 12, 12)
      Dst := Filter.Apply(Img, Rect(4, 4, 12, 12));
      try
        // Inside sub-rect: inverted to 155
        AssertEquals('Inside sub-rect inverted', 155, Dst.Pixels[6, 6].R);
        // Outside sub-rect: stays 100
        AssertEquals('Outside sub-rect unchanged', 100, Dst.Pixels[2, 2].R);
      finally
        Dst.Free();
      end;
    finally
      Filter.Free();
    end;
  finally
    Img.Free();
  end;
end;

procedure TFloriaCanvasFilterTest.TestNilImageSafety();
var
  Filter: TColorMatrixFilter;
  Dst: TFloriaImage;
begin
  Filter := TColorMatrixFilter.Create();
  try
    Dst := Filter.Apply(nil);
    AssertNull('Apply on nil returns nil', Dst);

    // Apply in place on nil should not raise exception
    Filter.ApplyInPlace(nil);
  finally
    Filter.Free();
  end;
end;

initialization
  RegisterTest(TFloriaCanvasFilterTest);

end.
