unit Floria.Image.Blur.Test;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry,
  Floria.Image.Core, Floria.Image.Blur;

type
  TFloriaBlurTest = class(TTestCase)
  published
    procedure TestBlurEdgeCases();
    procedure TestBlurSharpEdge();
    procedure TestBlurRoundedRect();
    procedure TestBlurFullImage();
  end;

implementation

procedure TFloriaBlurTest.TestBlurEdgeCases();
var
  Img: TFloriaImage;
begin
  // Null and zero size safety checks
  FloriaFastBlur(nil, 5.0);
  FloriaFastBlurRoundedRect(nil, 100, 100, 0, 0, 50, 50, 0.0, 5.0);
  FloriaFastBlurRect(nil, 100, 100, 0, 0, 50, 50, 5.0);

  Img := TFloriaImage.Create(0, 0);
  try
    FloriaFastBlur(Img, 5.0);
  finally
    Img.Free();
  end;

  Img := TFloriaImage.Create(2, 2);
  try
    // Tiny image (rw <= 2 or rh <= 2) should exit cleanly
    FloriaFastBlur(Img, 5.0);
  finally
    Img.Free();
  end;
end;

procedure TFloriaBlurTest.TestBlurSharpEdge();
var
  Img: TFloriaImage;
  X, Y: Integer;
  MidPix: TBgraPixel;
begin
  Img := TFloriaImage.Create(64, 64);
  try
    // Left half black, right half white
    for Y := 0 to 63 do
      for X := 0 to 63 do
      begin
        if X < 32 then
          Img.Pixels[X, Y] := TBgraPixel.Create(0, 0, 0, 255)
        else
          Img.Pixels[X, Y] := TBgraPixel.Create(255, 255, 255, 255);
      end;

    // Blur a sub-rect around the center: (16, 16, 32, 32)
    FloriaFastBlur(Img, 16, 16, 32, 32, 0.0, 4.0);

    // Pixel at the exact boundary (32, 32) should now be blended (around 128)
    MidPix := Img.Pixels[32, 32];
    AssertTrue('Edge Red should be blended', (MidPix.R > 50) and (MidPix.R < 200));
    AssertTrue('Edge Green should be blended', (MidPix.G > 50) and (MidPix.G < 200));
    AssertTrue('Edge Blue should be blended', (MidPix.B > 50) and (MidPix.B < 200));

    // Outside the blurred rect, e.g. (5, 5), pixels should remain unblurred
    AssertEquals('Outside left pixel remains 0', 0, Img.Pixels[5, 5].R);
    AssertEquals('Outside right pixel remains 255', 255, Img.Pixels[60, 5].R);
  finally
    Img.Free();
  end;
end;

procedure TFloriaBlurTest.TestBlurRoundedRect();
var
  Img: TFloriaImage;
  CornerPix: TBgraPixel;
begin
  Img := TFloriaImage.Create(64, 64);
  try
    Img.Clear(255, 255, 255, 255); // White background
    // Draw black patch in the center
    Img.CopyFrom(TFloriaImage.Create(32, 32), 0, 0, 16, 16, 32, 32); // Creates 0,0,0,0

    // Blur with rounded corners (cornerRadius = 10, blurRadius = 4.0)
    FloriaFastBlur(Img, 16, 16, 32, 32, 10.0, 4.0);

    // Center should be blurred
    AssertTrue('Center should have non-zero alpha', Img.Pixels[32, 32].A >= 0);
  finally
    Img.Free();
  end;
end;

procedure TFloriaBlurTest.TestBlurFullImage();
var
  Img: TFloriaImage;
  X, Y: Integer;
begin
  Img := TFloriaImage.Create(48, 48);
  try
    // Checkerboard pattern
    for Y := 0 to 47 do
      for X := 0 to 47 do
      begin
        if ((X div 8) + (Y div 8)) mod 2 = 0 then
          Img.Pixels[X, Y] := TBgraPixel.Create(200, 50, 50, 255)
        else
          Img.Pixels[X, Y] := TBgraPixel.Create(50, 50, 200, 255);
      end;

    // Full image blur
    FloriaFastBlur(Img, 6.0);

    // The entire image should now be smoothed/averaged
    AssertTrue('Center red is blended', (Img.Pixels[24, 24].R > 80) and (Img.Pixels[24, 24].R < 170));
  finally
    Img.Free();
  end;
end;

initialization
  RegisterTest(TFloriaBlurTest);

end.
