unit Floria.Text.Emoji.Test;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry,
  Floria.Image.Core,
  Floria.Font,
  Floria.Canvas.Agg,
  Floria.Text.Emoji;

type
  TFloriaEmojiTest = class(TTestCase)
  published
    procedure TestEmojiEngineAvailability;
    procedure TestEmojiDetection;
    procedure TestEmojiImageGeneration;
    procedure TestTextMeasurementWithEmoji;
    procedure TestCanvasDrawTextWithEmoji;
  end;

implementation

procedure TFloriaEmojiTest.TestEmojiEngineAvailability;
var
  engine: TFloriaEmojiEngine;
begin
  engine := FloriaEmojiEngine();
  AssertNotNull('Emoji engine singleton should not be nil', engine);
  if engine.IsAvailable then
    AssertTrue('Emoji font path should not be empty', engine.FontPath <> '');
end;

procedure TFloriaEmojiTest.TestEmojiDetection;
var
  engine: TFloriaEmojiEngine;
begin
  engine := FloriaEmojiEngine();
  // Standard ASCII and navigation arrows should not be emojis
  AssertFalse('ASCII A should not be emoji', engine.HasEmoji(Ord('A')));
  AssertFalse('ASCII space should not be emoji', engine.HasEmoji(Ord(' ')));
  AssertFalse('Triangle arrow ◀ ($25C0) should not be emoji', engine.HasEmoji($25C0));
  AssertFalse('Triangle arrow ▶ ($25B6) should not be emoji', engine.HasEmoji($25B6));

  if engine.IsAvailable then
  begin
    // Supplementary Multilingual Plane emojis
    AssertTrue('Folder emoji 📁 ($1F4C1) should be detected', engine.HasEmoji($1F4C1));
    AssertTrue('Palette emoji 🎨 ($1F3A8) should be detected', engine.HasEmoji($1F3A8));
    AssertTrue('Grinning emoji 😀 ($1F600) should be detected', engine.HasEmoji($1F600));
  end;
end;

procedure TFloriaEmojiTest.TestEmojiImageGeneration;
var
  engine: TFloriaEmojiEngine;
  img1, img2: TFloriaImage;
begin
  engine := FloriaEmojiEngine();
  if not engine.IsAvailable then Exit;

  img1 := engine.GetEmojiImage($1F4C1, 24);
  AssertNotNull('Emoji image for 📁 should be generated', img1);
  AssertEquals('Height should match requested target height', 24, img1.Height);
  AssertTrue('Width should be greater than zero', img1.Width > 0);
  AssertTrue('Pixel buffer should not be nil', img1.PixelBuffer <> nil);
  AssertTrue('Image should be marked as premultiplied', img1.IsPremultiplied);

  // Check caching
  img2 := engine.GetEmojiImage($1F4C1, 24);
  AssertTrue('Subsequent call for same emoji and height should return cached instance', img1 = img2);
end;

procedure TFloriaEmojiTest.TestTextMeasurementWithEmoji;
var
  font: TFloriaFont;
  wTextOnly, wTextWithEmoji: Double;
begin
  font := FloriaGetSystemFont();
  if not Assigned(font) or not font.Loaded then Exit;

  wTextOnly := font.GetTextWidth('Files');
  wTextWithEmoji := font.GetTextWidth('📁 Files');

  if FloriaEmojiEngine().IsAvailable then
    AssertTrue('Text with emoji should be strictly wider than text without emoji', wTextWithEmoji > wTextOnly + 10.0);
end;

procedure TFloriaEmojiTest.TestCanvasDrawTextWithEmoji;
var
  target: TFloriaImage;
  canvas: TFloriaCanvasAgg;
  font: TFloriaFont;
  x, y: Integer;
  pix: TBgraPixel;
  foundColoredPixel: Boolean;
begin
  font := FloriaGetSystemFont();
  if not Assigned(font) or not font.Loaded then Exit;
  if not FloriaEmojiEngine().IsAvailable then Exit;

  target := TFloriaImage.Create(160, 40, fpfBGRA32);
  try
    target.Clear(255, 255, 255, 255); // White background
    canvas := TFloriaCanvasAgg.Create(target);
    try
      // Draw text with folder emoji
      canvas.DrawText(10.0, 26.0, '📁 Files', font, 0.0, 0.0, 0.0);

      // Check that pixels in the emoji area (x: 10..34, y: 8..32) have color (R/G/B difference or non-white)
      foundColoredPixel := False;
      for y := 10 to 30 do
      begin
        for x := 12 to 30 do
        begin
          pix := target.Pixels[x, y];
          // Emojis like folder are yellow/manila (R > 150, B < 150) or have colored non-grayscale pixels
          if (pix.R <> pix.B) or (pix.R <> pix.G) or (pix.A < 255) then
          begin
            foundColoredPixel := True;
            Break;
          end;
        end;
        if foundColoredPixel then Break;
      end;
      AssertTrue('Rendered emoji should contain non-monochrome colored pixels', foundColoredPixel);
    finally
      canvas.Free();
    end;
  finally
    target.Free();
  end;
end;

initialization
  RegisterTest(TFloriaEmojiTest);

end.
