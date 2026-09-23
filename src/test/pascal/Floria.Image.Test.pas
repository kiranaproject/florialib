unit Floria.Image.Test;

// Floria.Image.Test
// =================
// Comprehensive unit test suite for Floria.Image subsystem (Core, BMP, PNG, JPEG).
// Validates raster buffer allocation, stride math, pixel getters/setters,
// sub-rect blitting, scaling, format auto-detection, and lossless BMP/PNG round-trips.

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry,
  Floria.Image.Core,
  Floria.Image.BMP,
  Floria.Image.PNG,
  Floria.Image.JPEG;

type
  TFloriaImageTest = class(TTestCase)
  published
    procedure TestImageAllocationAndClear();
    procedure TestPixelGetSet();
    procedure TestImageClone();
    procedure TestImageCopyFrom();
    procedure TestImageScaling();
    procedure TestBMPRoundTrip();
    procedure TestPNGRoundTrip();
    procedure TestFormatAutoDetection();
    procedure TestJPEGMarkerDetection();
    procedure TestInvalidStreamHandling();
  end;

implementation

procedure TFloriaImageTest.TestImageAllocationAndClear();
var
  Img: TFloriaImage;
  Pix: TBgraPixel;
begin
  Img := TFloriaImage.Create(100, 50, fpfBGRA32);
  try
    AssertEquals('Width', 100, Img.Width);
    AssertEquals('Height', 50, Img.Height);
    AssertEquals('Stride (100 * 4)', 400, Img.Stride);
    AssertNotNull('PixelBuffer allocated', Img.PixelBuffer);

    // Initial allocation is 0
    Pix := Img.Pixels[0, 0];
    AssertEquals('Initial Alpha 0', 0, Pix.A);

    // Clear to Cornflower Blue with Alpha 200
    Img.Clear(100, 149, 237, 200);
    Pix := Img.Pixels[50, 25];
    AssertEquals('Cleared Red', 100, Pix.R);
    AssertEquals('Cleared Green', 149, Pix.G);
    AssertEquals('Cleared Blue', 237, Pix.B);
    AssertEquals('Cleared Alpha', 200, Pix.A);

    // Scanline pointer check
    AssertNotNull('Scanline 0', Img.Scanline[0]);
    AssertNotNull('Scanline 49', Img.Scanline[49]);
    AssertNull('Scanline 50 out of bounds', Img.Scanline[50]);

    // AggPas buffer check
    AssertNotNull('Rendering buffer pointer', Img.RenderingBufPtr());
    AssertNotNull('Pixel format pointer', Img.PixFormatPtr());
  finally
    Img.Free();
  end;
end;

procedure TFloriaImageTest.TestPixelGetSet();
var
  Img: TFloriaImage;
  Pix: TBgraPixel;
begin
  Img := TFloriaImage.Create(20, 20);
  try
    Img.Pixels[10, 15] := TBgraPixel.Create(255, 128, 64, 250);
    Pix := Img.Pixels[10, 15];

    AssertEquals('Pixel Red', 255, Pix.R);
    AssertEquals('Pixel Green', 128, Pix.G);
    AssertEquals('Pixel Blue', 64, Pix.B);
    AssertEquals('Pixel Alpha', 250, Pix.A);

    // Out of bounds get returns 0
    Pix := Img.Pixels[99, 99];
    AssertEquals('Out of bounds Red', 0, Pix.R);
    AssertEquals('Out of bounds Alpha', 0, Pix.A);

    // Out of bounds set does not crash
    Img.Pixels[-1, -1] := TBgraPixel.Create(1, 2, 3, 4);
  finally
    Img.Free();
  end;
end;

procedure TFloriaImageTest.TestImageClone();
var
  Img1, Img2: TFloriaImage;
  Pix: TBgraPixel;
begin
  Img1 := TFloriaImage.Create(30, 30);
  try
    Img1.Clear(255, 0, 0, 255); // Red
    Img1.Pixels[5, 5] := TBgraPixel.Create(0, 255, 0, 255); // Green pixel

    Img2 := Img1.Clone();
    try
      AssertEquals('Cloned Width', 30, Img2.Width);
      AssertEquals('Cloned Height', 30, Img2.Height);

      Pix := Img2.Pixels[5, 5];
      AssertEquals('Cloned pixel is Green', 255, Pix.G);

      // Modify original, verify clone unchanged
      Img1.Pixels[5, 5] := TBgraPixel.Create(0, 0, 255, 255);
      Pix := Img2.Pixels[5, 5];
      AssertEquals('Clone preserved Green pixel', 255, Pix.G);
    finally
      Img2.Free();
    end;
  finally
    Img1.Free();
  end;
end;

procedure TFloriaImageTest.TestImageCopyFrom();
var
  SrcImg, DstImg: TFloriaImage;
  Pix: TBgraPixel;
begin
  SrcImg := TFloriaImage.Create(10, 10);
  DstImg := TFloriaImage.Create(40, 40);
  try
    SrcImg.Clear(255, 255, 0, 255); // Yellow
    DstImg.Clear(0, 0, 0, 255);       // Black

    // Blit SrcImg into DstImg at (15, 15)
    DstImg.CopyFrom(SrcImg, 0, 0, 15, 15, 10, 10);

    // Outside blit region remains black
    Pix := DstImg.Pixels[0, 0];
    AssertEquals('Outside blit Red', 0, Pix.R);

    // Inside blit region is yellow
    Pix := DstImg.Pixels[15, 15];
    AssertEquals('Blitted Red', 255, Pix.R);
    AssertEquals('Blitted Green', 255, Pix.G);
    AssertEquals('Blitted Blue', 0, Pix.B);
  finally
    SrcImg.Free();
    DstImg.Free();
  end;
end;

procedure TFloriaImageTest.TestImageScaling();
var
  Img, ScaledSmall, ScaledLarge: TFloriaImage;
  Pix: TBgraPixel;
begin
  Img := TFloriaImage.Create(4, 4);
  try
    Img.Clear(255, 0, 0, 255); // Red
    Img.Pixels[0, 0] := TBgraPixel.Create(0, 0, 255, 255); // Blue in top-left

    // Test nearest neighbor scaling
    ScaledSmall := Img.CreateScaled(2, 2, False);
    try
      AssertEquals('Downscaled Width', 2, ScaledSmall.Width);
      AssertEquals('Downscaled Height', 2, ScaledSmall.Height);
      Pix := ScaledSmall.Pixels[0, 0];
      AssertEquals('Downscaled top-left Blue (Nearest)', 255, Pix.B);
    finally
      ScaledSmall.Free();
    end;

    // Test bilinear scaling
    ScaledSmall := Img.CreateScaled(2, 2, True);
    try
      AssertEquals('Downscaled Width', 2, ScaledSmall.Width);
      AssertEquals('Downscaled Height', 2, ScaledSmall.Height);
      Pix := ScaledSmall.Pixels[0, 0];
      AssertTrue('Downscaled top-left Blue (Bilinear)', Pix.B > 240);
    finally
      ScaledSmall.Free();
    end;

    ScaledLarge := Img.CreateScaled(8, 8, False);
    try
      AssertEquals('Upscaled Width', 8, ScaledLarge.Width);
      AssertEquals('Upscaled Height', 8, ScaledLarge.Height);
      Pix := ScaledLarge.Pixels[0, 0];
      AssertEquals('Upscaled top-left Blue', 255, Pix.B);
      Pix := ScaledLarge.Pixels[4, 4];
      AssertEquals('Upscaled bottom-right Red', 255, Pix.R);
    finally
      ScaledLarge.Free();
    end;
  finally
    Img.Free();
  end;
end;

procedure TFloriaImageTest.TestBMPRoundTrip();
var
  OrigImg, LoadedImg: TFloriaImage;
  MS: TMemoryStream;
  Pix: TBgraPixel;
begin
  OrigImg := TFloriaImage.Create(16, 16);
  MS := TMemoryStream.Create();
  LoadedImg := TFloriaImage.Create();
  try
    // Fill test quadrants: Top-Left Red, Top-Right Green, Bottom-Left Blue, Bottom-Right White
    OrigImg.Clear(0, 0, 0, 255);
    OrigImg.Pixels[0, 0] := TBgraPixel.Create(255, 0, 0, 255);
    OrigImg.Pixels[15, 0] := TBgraPixel.Create(0, 255, 0, 255);
    OrigImg.Pixels[0, 15] := TBgraPixel.Create(0, 0, 255, 255);
    OrigImg.Pixels[15, 15] := TBgraPixel.Create(255, 255, 255, 255);

    // Save to BMP
    OrigImg.SaveToStream(MS, fifBMP);
    AssertTrue('BMP stream size > 54', MS.Size > 54);

    // Verify format detection
    MS.Position := 0;
    AssertEquals('Detected BMP format', Integer(fifBMP), Integer(DetectImageFormat(MS)));

    // Load back
    MS.Position := 0;
    LoadedImg.LoadFromStream(MS);

    AssertEquals('Loaded Width', 16, LoadedImg.Width);
    AssertEquals('Loaded Height', 16, LoadedImg.Height);

    // Verify pixel values
    Pix := LoadedImg.Pixels[0, 0];
    AssertEquals('Top-Left Red', 255, Pix.R);
    AssertEquals('Top-Left Green', 0, Pix.G);

    Pix := LoadedImg.Pixels[15, 0];
    AssertEquals('Top-Right Green', 255, Pix.G);
    AssertEquals('Top-Right Red', 0, Pix.R);

    Pix := LoadedImg.Pixels[0, 15];
    AssertEquals('Bottom-Left Blue', 255, Pix.B);

    Pix := LoadedImg.Pixels[15, 15];
    AssertEquals('Bottom-Right White Red', 255, Pix.R);
    AssertEquals('Bottom-Right White Green', 255, Pix.G);
    AssertEquals('Bottom-Right White Blue', 255, Pix.B);
  finally
    OrigImg.Free();
    LoadedImg.Free();
    MS.Free();
  end;
end;

procedure TFloriaImageTest.TestPNGRoundTrip();
var
  OrigImg, LoadedImg: TFloriaImage;
  MS: TMemoryStream;
  Pix: TBgraPixel;
  Sig: array[0..7] of Byte;
begin
  OrigImg := TFloriaImage.Create(8, 8);
  MS := TMemoryStream.Create();
  LoadedImg := TFloriaImage.Create();
  try
    // Semi-transparent colors
    OrigImg.Clear(0, 0, 0, 0); // Fully transparent background
    OrigImg.Pixels[2, 2] := TBgraPixel.Create(200, 100, 50, 128); // 50% opacity
    OrigImg.Pixels[5, 5] := TBgraPixel.Create(255, 255, 255, 255); // Opaque white

    // Save to PNG
    OrigImg.SaveToStream(MS, fifPNG);
    AssertTrue('PNG stream size > 8', MS.Size > 8);

    // Verify PNG signature
    MS.Position := 0;
    MS.ReadBuffer(Sig[0], 8);
    AssertEquals('PNG sig 0', $89, Sig[0]);
    AssertEquals('PNG sig 1', $50, Sig[1]); // 'P'
    AssertEquals('PNG sig 2', $4E, Sig[2]); // 'N'
    AssertEquals('PNG sig 3', $47, Sig[3]); // 'G'

    // Verify format detection
    MS.Position := 0;
    AssertEquals('Detected PNG format', Integer(fifPNG), Integer(DetectImageFormat(MS)));

    // Load back
    MS.Position := 0;
    LoadedImg.LoadFromStream(MS);

    AssertEquals('Loaded PNG Width', 8, LoadedImg.Width);
    AssertEquals('Loaded PNG Height', 8, LoadedImg.Height);

    // Verify transparent pixel
    Pix := LoadedImg.Pixels[0, 0];
    AssertEquals('Background Alpha is 0', 0, Pix.A);

    // Verify semi-transparent pixel
    Pix := LoadedImg.Pixels[2, 2];
    AssertEquals('Pixel Red', 200, Pix.R);
    AssertEquals('Pixel Green', 100, Pix.G);
    AssertEquals('Pixel Blue', 50, Pix.B);
    AssertEquals('Pixel Alpha is 128', 128, Pix.A);

    // Verify opaque white pixel
    Pix := LoadedImg.Pixels[5, 5];
    AssertEquals('Opaque White Red', 255, Pix.R);
    AssertEquals('Opaque White Alpha', 255, Pix.A);
  finally
    OrigImg.Free();
    LoadedImg.Free();
    MS.Free();
  end;
end;

procedure TFloriaImageTest.TestFormatAutoDetection();
var
  MS: TMemoryStream;
  DummyBMP: array[0..1] of Byte = ($42, $4D); // 'BM'
  DummyPNG: array[0..7] of Byte = ($89, $50, $4E, $47, $0D, $0A, $1A, $0A);
  DummyJPEG: array[0..2] of Byte = ($FF, $D8, $FF);
  DummyRandom: array[0..3] of Byte = ($12, $34, $56, $78);
begin
  MS := TMemoryStream.Create();
  try
    MS.WriteBuffer(DummyBMP[0], 2);
    MS.Position := 0;
    AssertEquals('Autodetect BMP', Integer(fifBMP), Integer(DetectImageFormat(MS)));

    MS.Clear();
    MS.WriteBuffer(DummyPNG[0], 8);
    MS.Position := 0;
    AssertEquals('Autodetect PNG', Integer(fifPNG), Integer(DetectImageFormat(MS)));

    MS.Clear();
    MS.WriteBuffer(DummyJPEG[0], 3);
    MS.Position := 0;
    AssertEquals('Autodetect JPEG', Integer(fifJPEG), Integer(DetectImageFormat(MS)));

    MS.Clear();
    MS.WriteBuffer(DummyRandom[0], 4);
    MS.Position := 0;
    AssertEquals('Autodetect Unknown', Integer(fifUnknown), Integer(DetectImageFormat(MS)));
  finally
    MS.Free();
  end;
end;

procedure TFloriaImageTest.TestJPEGMarkerDetection();
var
  MS: TMemoryStream;
  JpegHeader: array[0..3] of Byte = ($FF, $D8, $FF, $E0);
begin
  MS := TMemoryStream.Create();
  try
    MS.WriteBuffer(JpegHeader[0], 4);
    MS.Position := 0;
    AssertTrue('JPEG Reader CanRead identifies SOI marker', TFloriaJPEGReader.CanRead(MS));
  finally
    MS.Free();
  end;
end;

procedure TFloriaImageTest.TestInvalidStreamHandling();
var
  Img: TFloriaImage;
  MS: TMemoryStream;
  Failed: Boolean;
begin
  Img := TFloriaImage.Create();
  MS := TMemoryStream.Create();
  try
    // Empty stream creates 0x0 image
    Img.LoadFromStream(MS);
    AssertEquals('Empty stream width 0', 0, Img.Width);
    AssertEquals('Empty stream height 0', 0, Img.Height);

    // Unrecognized data raises exception
    MS.WriteByte($AA);
    MS.WriteByte($BB);
    MS.Position := 0;
    Failed := False;
    try
      Img.LoadFromStream(MS);
    except
      on E: Exception do
        Failed := True;
    end;
    AssertTrue('Unrecognized image data raised exception', Failed);
  finally
    Img.Free();
    MS.Free();
  end;
end;

initialization
  RegisterTest(TFloriaImageTest);

end.
