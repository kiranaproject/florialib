unit Floria.Canvas.Agg.Test;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry,
  Floria.Image.Core, Floria.Canvas.Agg, Floria.SVG.DOM, Floria.SVG.Parser, Floria.SVG.Rasterizer;

type
  TFloriaCanvasAggTest = class(TTestCase)
  published
    procedure TestCanvasCreationAndClear();
    procedure TestDrawRectAndRoundedRect();
    procedure TestDrawCircleAndLine();
    procedure TestClippingRect();
    procedure TestDrawImageBlit();
    procedure TestDrawImageScaled();
    procedure TestAlphaStack();
    procedure TestHersheyText();
    procedure TestSVGRasterizer();
  end;

implementation

procedure TFloriaCanvasAggTest.TestCanvasCreationAndClear();
var
  Img: TFloriaImage;
  Canvas: TFloriaCanvasAgg;
  Pix: TBgraPixel;
begin
  Img := TFloriaImage.Create(50, 50);
  try
    Canvas := TFloriaCanvasAgg.Create(Img);
    try
      AssertEquals('Canvas Width', 50, Canvas.Width);
      AssertEquals('Canvas Height', 50, Canvas.Height);

      // Clear to Cornflower Blue
      Canvas.Clear(100.0 / 255.0, 149.0 / 255.0, 237.0 / 255.0);

      Pix := Img.Pixels[25, 25];
      AssertEquals('Cleared Red', 100, Pix.R);
      AssertEquals('Cleared Green', 149, Pix.G);
      AssertEquals('Cleared Blue', 237, Pix.B);
      AssertEquals('Cleared Alpha', 255, Pix.A);
    finally
      Canvas.Free();
    end;
  finally
    Img.Free();
  end;
end;

procedure TFloriaCanvasAggTest.TestDrawRectAndRoundedRect();
var
  Img: TFloriaImage;
  Canvas: TFloriaCanvasAgg;
  Pix: TBgraPixel;
begin
  Img := TFloriaImage.Create(60, 60);
  try
    Canvas := TFloriaCanvasAgg.Create(Img);
    try
      Canvas.Clear(0.0, 0.0, 0.0); // Black

      // Draw red solid rect at (10, 10, 20, 20)
      Canvas.DrawRect(10, 10, 20, 20, 1.0, 0.0, 0.0);

      Pix := Img.Pixels[15, 15];
      AssertEquals('Inside rect Red', 255, Pix.R);
      AssertEquals('Inside rect Green', 0, Pix.G);
      AssertEquals('Inside rect Blue', 0, Pix.B);

      Pix := Img.Pixels[5, 5];
      AssertEquals('Outside rect Red', 0, Pix.R);

      // Draw green rounded rect at (35, 10, 20, 20, radius 5)
      Canvas.DrawRoundedRect(35.0, 10.0, 20.0, 20.0, 5.0, 0.0, 1.0, 0.0);
      Pix := Img.Pixels[45, 20];
      AssertEquals('Inside rounded rect Green', 255, Pix.G);
    finally
      Canvas.Free();
    end;
  finally
    Img.Free();
  end;
end;

procedure TFloriaCanvasAggTest.TestDrawCircleAndLine();
var
  Img: TFloriaImage;
  Canvas: TFloriaCanvasAgg;
  Pix: TBgraPixel;
begin
  Img := TFloriaImage.Create(60, 60);
  try
    Canvas := TFloriaCanvasAgg.Create(Img);
    try
      Canvas.Clear(0.0, 0.0, 0.0); // Black

      // Draw blue circle at (30, 30) with radius 10
      Canvas.DrawCircle(30.0, 30.0, 10.0, 0.0, 0.0, 1.0);
      Pix := Img.Pixels[30, 30];
      AssertEquals('Center circle Blue', 255, Pix.B);

      // Draw horizontal white line across top
      Canvas.DrawLine(5.0, 5.0, 55.0, 5.0, 2.0, 1.0, 1.0, 1.0);
      Pix := Img.Pixels[30, 5];
      AssertTrue('Line is bright', (Pix.R > 200) and (Pix.G > 200) and (Pix.B > 200));
    finally
      Canvas.Free();
    end;
  finally
    Img.Free();
  end;
end;

procedure TFloriaCanvasAggTest.TestClippingRect();
var
  Img: TFloriaImage;
  Canvas: TFloriaCanvasAgg;
begin
  Img := TFloriaImage.Create(60, 60);
  try
    Canvas := TFloriaCanvasAgg.Create(Img);
    try
      Canvas.Clear(0.0, 0.0, 0.0); // Black

      // Push clip rect to [20, 20, 20, 20]
      Canvas.PushClipRect(20, 20, 20, 20);

      // Draw large red rect over the entire canvas (0, 0, 60, 60)
      Canvas.DrawRect(0, 0, 60, 60, 1.0, 0.0, 0.0);

      Canvas.PopClipRect();

      // Outside clip rect should still be black
      AssertEquals('Outside clip (10, 10) Red is 0', 0, Img.Pixels[10, 10].R);
      AssertEquals('Outside clip (50, 50) Red is 0', 0, Img.Pixels[50, 50].R);

      // Inside clip rect should be red
      AssertEquals('Inside clip (25, 25) Red is 255', 255, Img.Pixels[25, 25].R);
    finally
      Canvas.Free();
    end;
  finally
    Img.Free();
  end;
end;

procedure TFloriaCanvasAggTest.TestDrawImageBlit();
var
  DestImg, SrcImg: TFloriaImage;
  Canvas: TFloriaCanvasAgg;
  Pix: TBgraPixel;
begin
  DestImg := TFloriaImage.Create(60, 60);
  SrcImg := TFloriaImage.Create(16, 16);
  try
    DestImg.Clear(0, 0, 0, 255);
    SrcImg.Clear(255, 200, 50, 255); // Orange

    Canvas := TFloriaCanvasAgg.Create(DestImg);
    try
      Canvas.DrawImage(10.0, 10.0, SrcImg, 1.0);

      Pix := DestImg.Pixels[18, 18];
      AssertEquals('Blitted pixel Red', 255, Pix.R);
      AssertEquals('Blitted pixel Green', 200, Pix.G);
      AssertEquals('Blitted pixel Blue', 50, Pix.B);

      Pix := DestImg.Pixels[5, 5];
      AssertEquals('Untouched pixel Red', 0, Pix.R);
    finally
      Canvas.Free();
    end;
  finally
    DestImg.Free();
    SrcImg.Free();
  end;
end;

procedure TFloriaCanvasAggTest.TestDrawImageScaled();
var
  DestImg, SrcImg: TFloriaImage;
  Canvas: TFloriaCanvasAgg;
  Pix: TBgraPixel;
begin
  DestImg := TFloriaImage.Create(80, 80);
  SrcImg := TFloriaImage.Create(10, 10);
  try
    DestImg.Clear(0, 0, 0, 255);
    SrcImg.Clear(50, 150, 250, 255);

    Canvas := TFloriaCanvasAgg.Create(DestImg);
    try
      Canvas.DrawImageScaled(10.0, 10.0, 40.0, 40.0, SrcImg, 1.0);

      Pix := DestImg.Pixels[30, 30];
      AssertTrue('Scaled pixel Red around 50', Abs(Pix.R - 50) <= 3);
      AssertTrue('Scaled pixel Green around 150', Abs(Pix.G - 150) <= 5);
      AssertTrue('Scaled pixel Blue around 250', Abs(Pix.B - 250) <= 5);
    finally
      Canvas.Free();
    end;
  finally
    DestImg.Free();
    SrcImg.Free();
  end;
end;

procedure TFloriaCanvasAggTest.TestAlphaStack();
var
  Img: TFloriaImage;
  Canvas: TFloriaCanvasAgg;
begin
  Img := TFloriaImage.Create(40, 40);
  try
    Canvas := TFloriaCanvasAgg.Create(Img);
    try
      AssertEquals('Initial alpha is 1.0', 1.0, Canvas.CurrentAlpha);

      Canvas.PushAlpha(0.5);
      AssertEquals('Pushed alpha 0.5', 0.5, Canvas.CurrentAlpha);

      Canvas.PushAlpha(0.5);
      AssertEquals('Nested alpha 0.25', 0.25, Canvas.CurrentAlpha);

      Canvas.PopAlpha();
      AssertEquals('Popped alpha back to 0.5', 0.5, Canvas.CurrentAlpha);

      Canvas.ResetAlpha();
      AssertEquals('Reset alpha back to 1.0', 1.0, Canvas.CurrentAlpha);
    finally
      Canvas.Free();
    end;
  finally
    Img.Free();
  end;
end;

procedure TFloriaCanvasAggTest.TestHersheyText();
var
  Img: TFloriaImage;
  Canvas: TFloriaCanvasAgg;
  FoundPixel: Boolean;
  X, Y: Integer;
begin
  Img := TFloriaImage.Create(100, 40);
  try
    Canvas := TFloriaCanvasAgg.Create(Img);
    try
      Canvas.Clear(0.0, 0.0, 0.0); // Black
      Canvas.DrawText(10.0, 10.0, 'OK', 14.0, 1.0, 1.0, 1.0); // Hershey or FreeType fallback

      FoundPixel := False;
      for Y := 0 to 39 do
        for X := 0 to 99 do
          if Img.Pixels[X, Y].R > 100 then
          begin
            FoundPixel := True;
            Break;
          end;

      AssertTrue('Text glyph pixels were rendered', FoundPixel);
    finally
      Canvas.Free();
    end;
  finally
    Img.Free();
  end;
end;

procedure TFloriaCanvasAggTest.TestSVGRasterizer();
var
  SVGStr: string;
  Img: TFloriaImage;
  Pix: TBgraPixel;
begin
  SVGStr := '<svg width="40" height="40">' +
            '  <rect x="5" y="5" width="30" height="30" fill="#FF0000"/>' +
            '</svg>';

  Img := TFloriaSVGRenderer.RenderStringToImage(SVGStr, 40, 40);
  try
    AssertEquals('Rendered Width', 40, Img.Width);
    AssertEquals('Rendered Height', 40, Img.Height);

    // Center of rectangle should be pure Red
    Pix := Img.Pixels[20, 20];
    AssertEquals('SVG rect Red is 255', 255, Pix.R);
    AssertEquals('SVG rect Green is 0', 0, Pix.G);
    AssertEquals('SVG rect Blue is 0', 0, Pix.B);
    AssertEquals('SVG rect Alpha is 255', 255, Pix.A);

    // Outside rect (0, 0) should be transparent (0)
    Pix := Img.Pixels[0, 0];
    AssertEquals('Outside rect Alpha is 0', 0, Pix.A);
  finally
    Img.Free();
  end;
end;

initialization
  RegisterTest(TFloriaCanvasAggTest);

end.
