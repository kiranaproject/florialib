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
  Floria.Image.GIF,
  Floria.Image.JPEG,
  Floria.Image.WebP;

type
  TFakeImageReader = class(TFloriaImageReader)
  public
    class function CanRead(AStream: TStream): Boolean; override;
    class function Format(): TFloriaImageFormat; override;
    procedure ReadImage(AStream: TStream; AImage: TFloriaImage); override;
  end;

  TFloriaImageTest = class(TTestCase)
  published
    procedure TestImageAllocationAndClear();
    procedure TestPixelGetSet();
    procedure TestImageClone();
    procedure TestImageCopyFrom();
    procedure TestImageScaling();
    procedure TestBMPRoundTrip();
    procedure TestPNGRoundTrip();
    procedure TestPNGPalettedTransparency();
    procedure TestFormatAutoDetection();
    procedure TestCodecRegistryRegistration();
    procedure TestJPEGMarkerDetection();
    procedure TestInvalidStreamHandling();
    procedure TestPremultipliedAlpha();
    procedure TestBaselineJPEGDecode();
    procedure TestProgressiveJPEGDecode();
    procedure TestWebPDecode();
    procedure TestWebPRoundTrip();
    procedure TestGIFFormatAutoDetection();
    procedure TestGIFAnimationDecode();
    procedure TestAPNGAnimationDecode();
    procedure TestStaticFallbackOnAnimatedGIF();
    procedure TestStaticFallbackOnAnimatedPNG();
  end;

implementation

class function TFakeImageReader.CanRead(AStream: TStream): Boolean;
var
  B: array[0..3] of Byte;
  OldPos: Int64;
begin
  Result := False;
  if not Assigned(AStream) then Exit;

  OldPos := AStream.Position;
  try
    if (AStream.Size - OldPos) >= 4 then
    begin
      AStream.ReadBuffer(B, 4);
      Result := (B[0] = $AA) and (B[1] = $BB) and (B[2] = $CC) and (B[3] = $DD);
    end;
  finally
    AStream.Position := OldPos;
  end;
end;

class function TFakeImageReader.Format(): TFloriaImageFormat;
begin
  Result := fifBMP;
end;

procedure TFakeImageReader.ReadImage(AStream: TStream; AImage: TFloriaImage);
begin
  // Detection-only test reader.
end;

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
  dy: Integer;
begin
  Img := TFloriaImage.Create(4, 4);
  try
    Img.Clear(255, 0, 0, 255); // Red
    // Fill top-left 2x2 quadrant with Blue
    Img.Pixels[0, 0] := TBgraPixel.Create(0, 0, 255, 255);
    Img.Pixels[1, 0] := TBgraPixel.Create(0, 0, 255, 255);
    Img.Pixels[0, 1] := TBgraPixel.Create(0, 0, 255, 255);
    Img.Pixels[1, 1] := TBgraPixel.Create(0, 0, 255, 255);

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

    // Test symmetry when downscaling 24x24 to 20x20 (e.g. icon downscaling)
    Img.Free();
    Img := TFloriaImage.Create(24, 24);
    Img.Clear(0, 0, 0, 0);
    // Draw a symmetrical border at col 0 and col 23
    for dy := 0 to 23 do
    begin
      Img.Pixels[0, dy] := TBgraPixel.Create(100, 150, 200, 255);
      Img.Pixels[23, dy] := TBgraPixel.Create(100, 150, 200, 255);
    end;
    ScaledSmall := Img.CreateScaled(20, 20, True);
    try
      // Leftmost pixel (col 0) and rightmost pixel (col 19) should have symmetrical alpha/color
      AssertTrue('Symmetrical scaling left/right Alpha', Abs(ScaledSmall.Pixels[0, 10].A - ScaledSmall.Pixels[19, 10].A) <= 1);
      AssertTrue('Symmetrical scaling left/right Blue', Abs(ScaledSmall.Pixels[0, 10].B - ScaledSmall.Pixels[19, 10].B) <= 1);
      AssertTrue('Preserved edge alpha', ScaledSmall.Pixels[19, 10].A > 200);
    finally
      ScaledSmall.Free();
    end;

    // Test large downscaling (e.g. 128x128 to 20x20) preserves high-frequency details smoothly
    Img.Free();
    Img := TFloriaImage.Create(128, 128);
    Img.Clear(0, 0, 0, 0);
    for dy := 32 to 95 do
    begin
      Img.Pixels[32, dy] := TBgraPixel.Create(255, 255, 255, 255);
      Img.Pixels[95, dy] := TBgraPixel.Create(255, 255, 255, 255);
      Img.Pixels[dy, 32] := TBgraPixel.Create(255, 255, 255, 255);
      Img.Pixels[dy, 95] := TBgraPixel.Create(255, 255, 255, 255);
    end;
    ScaledSmall := Img.CreateScaled(20, 20, True);
    try
      AssertEquals('Large downscale Width', 20, ScaledSmall.Width);
      AssertEquals('Large downscale Height', 20, ScaledSmall.Height);
      AssertTrue('Thin feature retained in downsampling', ScaledSmall.Pixels[5, 10].A > 0);
    finally
      ScaledSmall.Free();
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

procedure TFloriaImageTest.TestPNGPalettedTransparency();
var
  Img: TFloriaImage;
  Pix: TBgraPixel;
  TestFile: string;
begin
  TestFile := '/usr/share/icons/Yaru/24x24/apps/atril.png';
  if not FileExists(TestFile) then Exit;

  Img := TFloriaImage.Create();
  try
    Img.LoadFromFile(TestFile);
    AssertEquals('Atril width', 24, Img.Width);
    AssertEquals('Atril height', 24, Img.Height);

    // Top-left pixel (0, 0) in atril.png must be transparent (Alpha = 0)
    Pix := Img.Pixels[0, 0];
    AssertEquals('Paletted PNG transparent background Alpha', 0, Pix.A);
  finally
    Img.Free();
  end;
end;

procedure TFloriaImageTest.TestFormatAutoDetection();
var
  MS: TMemoryStream;
  DummyBMP: array[0..1] of Byte = ($42, $4D); // 'BM'
  DummyPNG: array[0..7] of Byte = ($89, $50, $4E, $47, $0D, $0A, $1A, $0A);
  DummyJPEG: array[0..2] of Byte = ($FF, $D8, $FF);
  DummyWebP: array[0..11] of Byte = ($52, $49, $46, $46, $00, $00, $00, $00, $57, $45, $42, $50);
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
    MS.WriteBuffer(DummyWebP[0], 12);
    MS.Position := 0;
    AssertEquals('Autodetect WebP', Integer(fifWebP), Integer(DetectImageFormat(MS)));

    MS.Clear();
    MS.WriteBuffer(DummyRandom[0], 4);
    MS.Position := 0;
    AssertEquals('Autodetect Unknown', Integer(fifUnknown), Integer(DetectImageFormat(MS)));
  finally
    MS.Free();
  end;
end;

procedure TFloriaImageTest.TestCodecRegistryRegistration();
var
  MS: TMemoryStream;
  Magic: array[0..3] of Byte = ($AA, $BB, $CC, $DD);
begin
  RegisterImageReader(TFakeImageReader);

  MS := TMemoryStream.Create();
  try
    MS.WriteBuffer(Magic[0], 4);
    MS.Position := 0;
    AssertEquals('Custom reader participates in auto-detection',
      Integer(fifBMP), Integer(DetectImageFormat(MS)));
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

procedure TFloriaImageTest.TestPremultipliedAlpha();
var
  Img: TFloriaImage;
  Pix: TBgraPixel;
begin
  Img := TFloriaImage.Create(2, 2);
  try
    AssertFalse('Default IsPremultiplied is False', Img.IsPremultiplied);

    // Set a semi-transparent pixel (R=200, G=100, B=50, A=128)
    Img.Pixels[0, 0] := TBgraPixel.Create(200, 100, 50, 128);
    // Set a fully transparent pixel (R=255, G=255, B=255, A=0)
    Img.Pixels[1, 0] := TBgraPixel.Create(255, 255, 255, 0);
    // Set an opaque pixel (R=200, G=100, B=50, A=255)
    Img.Pixels[0, 1] := TBgraPixel.Create(200, 100, 50, 255);

    Img.PremultiplyAlpha();
    AssertTrue('IsPremultiplied after PremultiplyAlpha is True', Img.IsPremultiplied);

    // Semi-transparent pixel: color channels should be scaled by alpha / 256
    Pix := Img.Pixels[0, 0];
    AssertEquals('Premultiplied Alpha channel', 128, Pix.A);
    AssertTrue('Premultiplied Red ~ 100', Abs(Pix.R - 100) <= 2);
    AssertTrue('Premultiplied Green ~ 50', Abs(Pix.G - 50) <= 2);
    AssertTrue('Premultiplied Blue ~ 25', Abs(Pix.B - 25) <= 2);

    // Fully transparent pixel: RGB must be 0
    Pix := Img.Pixels[1, 0];
    AssertEquals('Transparent Red is 0', 0, Pix.R);
    AssertEquals('Transparent Green is 0', 0, Pix.G);
    AssertEquals('Transparent Blue is 0', 0, Pix.B);
    AssertEquals('Transparent Alpha is 0', 0, Pix.A);

    // Opaque pixel: unchanged
    Pix := Img.Pixels[0, 1];
    AssertEquals('Opaque Red unchanged', 200, Pix.R);
    AssertEquals('Opaque Green unchanged', 100, Pix.G);
    AssertEquals('Opaque Blue unchanged', 50, Pix.B);
    AssertEquals('Opaque Alpha unchanged', 255, Pix.A);

    // Demultiply alpha
    Img.DemultiplyAlpha();
    AssertFalse('IsPremultiplied after DemultiplyAlpha is False', Img.IsPremultiplied);

    Pix := Img.Pixels[0, 0];
    AssertTrue('Demultiplied Red restored ~ 200', Abs(Pix.R - 200) <= 2);
    AssertTrue('Demultiplied Green restored ~ 100', Abs(Pix.G - 100) <= 2);
    AssertTrue('Demultiplied Blue restored ~ 50', Abs(Pix.B - 50) <= 2);
    AssertEquals('Demultiplied Alpha', 128, Pix.A);
  finally
    Img.Free();
  end;
end;

procedure TFloriaImageTest.TestBaselineJPEGDecode();
var
  JpegPath: string;
  Img: TFloriaImage;
  Pix: TBgraPixel;
begin
  JpegPath := GetEnvironmentVariable('FLORIA_TEST_JPEG');
  if (JpegPath = '') or not FileExists(JpegPath) then Exit;

  Img := TFloriaImage.CreateFromFile(JpegPath);
  try
    AssertEquals('Decoded Width', 2560, Img.Width);
    AssertEquals('Decoded Height', 3840, Img.Height);
    AssertEquals('Decoded Stride', 2560 * 4, Img.Stride);
    AssertNotNull('PixelBuffer allocated', Img.PixelBuffer);

    Pix := Img.Pixels[1280, 1920];
    AssertEquals('Decoded center pixel alpha is 255', 255, Pix.A);
  finally
    Img.Free();
  end;
end;

procedure TFloriaImageTest.TestProgressiveJPEGDecode();
var
  candidatePaths: array[0..2] of string;
  foundPath: string;
  i: Integer;
  img: TFloriaImage;
begin
  candidatePaths[0] := '/usr/share/backgrounds/ubuntu-mate-common/Grey-Jazz.jpg';
  candidatePaths[1] := '/usr/share/backgrounds/ubuntu-mate-common/Ubuntu-MATE-Splash.jpg';
  candidatePaths[2] := '/usr/share/backgrounds/afumi/wp5327130-winter-alps-wallpapers.jpg';

  foundPath := '';
  for i := 0 to High(candidatePaths) do
  begin
    if FileExists(candidatePaths[i]) then
    begin
      foundPath := candidatePaths[i];
      Break;
    end;
  end;

  if foundPath = '' then Exit;

  img := TFloriaImage.CreateFromFile(foundPath);
  try
    AssertTrue('Decoded width must be > 0', img.Width > 0);
    AssertTrue('Decoded height must be > 0', img.Height > 0);
    AssertNotNull('PixelBuffer must be allocated', img.PixelBuffer);
    AssertEquals('Stride matches 4 bytes per pixel', img.Width * 4, img.Stride);
  finally
    img.Free();
  end;
end;

procedure TFloriaImageTest.TestWebPDecode();
var
  TestPath: string;
  Img: TFloriaImage;
  Pix: TBgraPixel;
  FS: TFileStream;
begin
  if not IsWebPAvailable() then Exit;

  TestPath := '/home/afumi/Documents/projects/kirana/configsama/scratch/cfsettings.webp';
  if not FileExists(TestPath) then Exit;

  FS := TFileStream.Create(TestPath, fmOpenRead or fmShareDenyNone);
  try
    AssertEquals('DetectImageFormat identifies WebP', Integer(fifWebP), Integer(DetectImageFormat(FS)));
  finally
    FS.Free();
  end;

  Img := TFloriaImage.CreateFromFile(TestPath);
  try
    AssertEquals('WebP Decoded Width', 1200, Img.Width);
    AssertEquals('WebP Decoded Height', 675, Img.Height);
    AssertEquals('WebP Decoded Stride', 1200 * 4, Img.Stride);
    AssertNotNull('WebP PixelBuffer allocated', Img.PixelBuffer);

    Pix := Img.Pixels[600, 337];
    AssertEquals('WebP center pixel alpha is 255', 255, Pix.A);
  finally
    Img.Free();
  end;
end;

procedure TFloriaImageTest.TestWebPRoundTrip();
var
  OrigImg, DecodedImg: TFloriaImage;
  MS: TMemoryStream;
  Pix, DecPix: TBgraPixel;
  X, Y: Integer;
begin
  if not IsWebPAvailable() then Exit;

  OrigImg := TFloriaImage.Create(32, 32, fpfBGRA32);
  try
    for Y := 0 to 31 do
      for X := 0 to 31 do
        OrigImg.Pixels[X, Y] := TBgraPixel.Create(Byte(X * 8), Byte(Y * 8), Byte((X + Y) * 4), 255);

    MS := TMemoryStream.Create();
    try
      OrigImg.SaveToStream(MS, fifWebP);
      AssertTrue('WebP stream size > 0', MS.Size > 0);

      MS.Position := 0;
      AssertEquals('DetectImageFormat on encoded WebP', Integer(fifWebP), Integer(DetectImageFormat(MS)));

      MS.Position := 0;
      DecodedImg := TFloriaImage.CreateFromStream(MS);
      try
        AssertEquals('Roundtrip Width', 32, DecodedImg.Width);
        AssertEquals('Roundtrip Height', 32, DecodedImg.Height);
        AssertEquals('Roundtrip Stride', 32 * 4, DecodedImg.Stride);

        // Verify lossless reproduction
        for Y := 0 to 31 do
          for X := 0 to 31 do
          begin
            Pix := OrigImg.Pixels[X, Y];
            DecPix := DecodedImg.Pixels[X, Y];
            AssertEquals(Format('R at %d,%d', [X, Y]), Pix.R, DecPix.R);
            AssertEquals(Format('G at %d,%d', [X, Y]), Pix.G, DecPix.G);
            AssertEquals(Format('B at %d,%d', [X, Y]), Pix.B, DecPix.B);
            AssertEquals(Format('A at %d,%d', [X, Y]), Pix.A, DecPix.A);
          end;
      finally
        DecodedImg.Free();
      end;
    finally
      MS.Free();
    end;
  finally
    OrigImg.Free();
  end;
end;

const
  TEST_ANIM_GIF: array[0..422] of Byte = (
    $47, $49, $46, $38, $39, $61, $20, $00, $20, $00, $81, $00, $00, $FF, $FF, $FF,
    $FF, $00, $00, $00, $00, $00, $00, $00, $00, $21, $FF, $0B, $4E, $45, $54, $53,
    $43, $41, $50, $45, $32, $2E, $30, $03, $01, $00, $00, $00, $21, $F9, $04, $00,
    $0A, $00, $00, $00, $2C, $00, $00, $00, $00, $20, $00, $20, $00, $00, $08, $61,
    $00, $03, $08, $1C, $48, $B0, $A0, $40, $00, $08, $13, $2A, $5C, $68, $B0, $21,
    $C1, $85, $10, $15, $3A, $9C, $18, $B1, $E2, $44, $87, $15, $23, $5E, $6C, $98,
    $11, $E2, $46, $83, $1D, $19, $7E, $7C, $18, $32, $E1, $48, $92, $25, $01, $9C,
    $1C, $98, $12, $E1, $CA, $83, $2D, $5F, $06, $68, $A9, $F2, $25, $4D, $99, $37,
    $6D, $C6, $D4, $99, $12, $E7, $CE, $95, $34, $83, $0A, $1D, $4A, $B4, $A8, $D1,
    $A3, $48, $93, $2A, $5D, $CA, $B4, $A9, $D3, $A7, $50, $A3, $4A, $9D, $BA, $30,
    $20, $00, $21, $F9, $04, $01, $0F, $00, $02, $00, $2C, $00, $00, $00, $00, $19,
    $00, $19, $00, $81, $FF, $FF, $FF, $00, $FF, $00, $00, $00, $00, $00, $00, $00,
    $08, $62, $00, $01, $08, $1C, $48, $B0, $A0, $40, $01, $08, $13, $22, $34, $C8,
    $90, $A0, $42, $85, $0D, $23, $3E, $4C, $18, $B1, $E1, $C4, $85, $15, $0D, $5E,
    $14, $90, $51, $E3, $C5, $8E, $05, $37, $82, $74, $F8, $91, $61, $80, $93, $28,
    $53, $AA, $3C, $D9, $70, $A5, $CB, $94, $2D, $5F, $BE, $8C, $29, $73, $25, $CD,
    $9A, $30, $4D, $E2, $54, $79, $73, $67, $80, $9E, $3B, $81, $E2, $DC, $E8, $33,
    $25, $D1, $A2, $27, $8F, $22, $55, $5A, $94, $A9, $4F, $A7, $3B, $A1, $0E, $BD,
    $88, $F4, $64, $40, $00, $21, $F9, $04, $01, $14, $00, $02, $00, $2C, $08, $00,
    $08, $00, $18, $00, $18, $00, $81, $FF, $FF, $FF, $00, $00, $FF, $00, $00, $00,
    $00, $00, $00, $08, $60, $00, $01, $08, $1C, $48, $B0, $A0, $40, $01, $08, $13,
    $0A, $30, $C8, $90, $A0, $C2, $84, $0D, $23, $3E, $44, $18, $B1, $E1, $C4, $85,
    $15, $0D, $5E, $CC, $A8, $71, $22, $C7, $82, $1B, $3F, $0E, $0C, $69, $30, $80,
    $C9, $93, $28, $53, $06, $68, $A8, $B2, $E5, $49, $96, $2E, $5B, $C2, $8C, $99,
    $72, $26, $CD, $97, $0C, $6F, $D6, $CC, $A9, $13, $67, $C9, $9E, $26, $6D, $EA,
    $BC, $28, $00, $A8, $49, $A2, $46, $03, $20, $35, $BA, $14, $68, $D3, $9E, $4F,
    $87, $5E, $4C, $1A, $10, $00, $3B
  );

  TEST_ANIM_PNG: array[0..359] of Byte = (
    $89, $50, $4E, $47, $0D, $0A, $1A, $0A, $00, $00, $00, $0D, $49, $48, $44, $52,
    $00, $00, $00, $20, $00, $00, $00, $20, $08, $06, $00, $00, $00, $73, $7A, $7A,
    $F4, $00, $00, $00, $08, $61, $63, $54, $4C, $00, $00, $00, $03, $00, $00, $00,
    $00, $CE, $ED, $BA, $C0, $00, $00, $00, $1A, $66, $63, $54, $4C, $00, $00, $00,
    $00, $00, $00, $00, $20, $00, $00, $00, $20, $00, $00, $00, $00, $00, $00, $00,
    $00, $00, $01, $00, $0A, $00, $00, $9A, $27, $23, $EA, $00, $00, $00, $35, $49,
    $44, $41, $54, $78, $9C, $ED, $CE, $B1, $11, $00, $20, $0C, $03, $31, $87, $A9,
    $D8, $BF, $62, $2B, $D8, $81, $14, $69, $A4, $DE, $E7, $AF, $9B, $9C, $34, $55,
    $B2, $7F, $B7, $AB, $7B, $DE, $25, $40, $80, $00, $01, $02, $04, $08, $18, $0F,
    $00, $00, $C6, $3D, $C8, $FB, $02, $22, $8F, $83, $A3, $C5, $00, $00, $00, $1A,
    $66, $63, $54, $4C, $00, $00, $00, $01, $00, $00, $00, $19, $00, $00, $00, $19,
    $00, $00, $00, $00, $00, $00, $00, $00, $00, $03, $00, $14, $00, $00, $3C, $7C,
    $72, $59, $00, $00, $00, $30, $66, $64, $41, $54, $00, $00, $00, $02, $78, $9C,
    $ED, $CD, $31, $11, $00, $00, $08, $C3, $C0, $80, $7F, $61, $B8, $02, $09, $0C,
    $5D, $93, $B9, $D7, $07, $33, $FB, $AA, $77, $B1, $4C, $8A, $74, $7A, $20, $22,
    $22, $22, $22, $22, $02, $1C, $2A, $4B, $01, $E9, $8E, $EE, $66, $76, $00, $00,
    $00, $1A, $66, $63, $54, $4C, $00, $00, $00, $03, $00, $00, $00, $18, $00, $00,
    $00, $18, $00, $00, $00, $08, $00, $00, $00, $08, $00, $01, $00, $05, $00, $00,
    $51, $FB, $CF, $05, $00, $00, $00, $2C, $66, $64, $41, $54, $00, $00, $00, $04,
    $78, $9C, $63, $60, $18, $05, $A3, $60, $14, $30, $12, $56, $F2, $FF, $04, $25,
    $16, $30, $51, $A2, $79, $D4, $82, $51, $0B, $46, $2D, $18, $B5, $60, $D4, $02,
    $7A, $59, $00, $00, $F2, $21, $01, $E7, $97, $54, $63, $55, $00, $00, $00, $00,
    $49, $45, $4E, $44, $AE, $42, $60, $82
  );

procedure TFloriaImageTest.TestGIFFormatAutoDetection();
var
  MS: TMemoryStream;
  Sig89a: array[0..5] of Byte = ($47, $49, $46, $38, $39, $61); // 'GIF89a'
  Sig87a: array[0..5] of Byte = ($47, $49, $46, $38, $37, $61); // 'GIF87a'
begin
  MS := TMemoryStream.Create();
  try
    MS.WriteBuffer(Sig89a[0], 6);
    MS.Position := 0;
    AssertEquals('DetectImageFormat detects GIF89a', Integer(fifGIF), Integer(DetectImageFormat(MS)));

    MS.Clear();
    MS.WriteBuffer(Sig87a[0], 6);
    MS.Position := 0;
    AssertEquals('DetectImageFormat detects GIF87a', Integer(fifGIF), Integer(DetectImageFormat(MS)));
  finally
    MS.Free();
  end;
end;

procedure TFloriaImageTest.TestGIFAnimationDecode();
var
  Anim: TFloriaAnimatedImage;
  FrameImg: TFloriaImage;
begin
  Anim := TFloriaAnimatedImage.CreateFromMemory(@TEST_ANIM_GIF[0], Length(TEST_ANIM_GIF));
  try
    AssertEquals('GIF Width', 32, Anim.Width);
    AssertEquals('GIF Height', 32, Anim.Height);
    AssertEquals('GIF FrameCount', 3, Anim.FrameCount());
    AssertTrue('GIF TotalDurationMs > 0', Anim.TotalDurationMs > 0);

    FrameImg := Anim.GetCompositedFrame(0);
    AssertNotNull('Composited frame 0 not nil', FrameImg);
    AssertEquals('Frame 0 width', 32, FrameImg.Width);
    AssertEquals('Frame 0 height', 32, FrameImg.Height);

    FrameImg := Anim.GetCompositedFrame(1);
    AssertNotNull('Composited frame 1 not nil', FrameImg);

    FrameImg := Anim.GetCompositedFrame(2);
    AssertNotNull('Composited frame 2 not nil', FrameImg);

    AssertEquals('Frame index at t=0', 0, Anim.GetFrameAtTime(0));
  finally
    Anim.Free();
  end;
end;

procedure TFloriaImageTest.TestAPNGAnimationDecode();
var
  Anim: TFloriaAnimatedImage;
  FrameImg: TFloriaImage;
begin
  Anim := TFloriaAnimatedImage.CreateFromMemory(@TEST_ANIM_PNG[0], Length(TEST_ANIM_PNG));
  try
    AssertEquals('APNG Width', 32, Anim.Width);
    AssertEquals('APNG Height', 32, Anim.Height);
    AssertEquals('APNG FrameCount', 3, Anim.FrameCount());
    AssertTrue('APNG TotalDurationMs > 0', Anim.TotalDurationMs > 0);

    FrameImg := Anim.GetCompositedFrame(0);
    AssertNotNull('Composited frame 0 not nil', FrameImg);
    AssertEquals('Frame 0 width', 32, FrameImg.Width);
    AssertEquals('Frame 0 height', 32, FrameImg.Height);

    FrameImg := Anim.GetCompositedFrame(1);
    AssertNotNull('Composited frame 1 not nil', FrameImg);

    FrameImg := Anim.GetCompositedFrame(2);
    AssertNotNull('Composited frame 2 not nil', FrameImg);
  finally
    Anim.Free();
  end;
end;

procedure TFloriaImageTest.TestStaticFallbackOnAnimatedGIF();
var
  Img: TFloriaImage;
begin
  Img := TFloriaImage.CreateFromMemory(@TEST_ANIM_GIF[0], Length(TEST_ANIM_GIF));
  try
    AssertEquals('Static fallback GIF width', 32, Img.Width);
    AssertEquals('Static fallback GIF height', 32, Img.Height);
    AssertNotNull('Static fallback pixel buffer', Img.PixelBuffer);
  finally
    Img.Free();
  end;
end;

procedure TFloriaImageTest.TestStaticFallbackOnAnimatedPNG();
var
  Img: TFloriaImage;
begin
  Img := TFloriaImage.CreateFromMemory(@TEST_ANIM_PNG[0], Length(TEST_ANIM_PNG));
  try
    AssertEquals('Static fallback PNG width', 32, Img.Width);
    AssertEquals('Static fallback PNG height', 32, Img.Height);
    AssertNotNull('Static fallback pixel buffer', Img.PixelBuffer);
  finally
    Img.Free();
  end;
end;

initialization
  RegisterTest(TFloriaImageTest);

end.
