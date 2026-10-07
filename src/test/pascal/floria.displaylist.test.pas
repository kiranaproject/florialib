unit Floria.DisplayList.Test;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, fpcunit, testregistry,
  Floria.Image.Core,
  Floria.Font,
  Floria.Canvas.Agg,
  Floria.Canvas.Blend,
  Floria.Canvas.Filter,
  Floria.Path.Clipper.Core,
  Floria.Path.Ops,
  Floria.Text.Paragraph,
  Floria.DisplayList;

type
  // Mock receiver for verifying visitor pattern dispatch
  TTestMockReceiver = class(TFloriaDisplayListReceiver)
  public
    SaveCount         : Integer;
    RestoreCount      : Integer;
    TransformCount    : Integer;
    PushClipCount     : Integer;
    PopClipCount      : Integer;
    ClearCount        : Integer;
    DrawRectCount     : Integer;
    DrawRRectCount    : Integer;
    DrawCircleCount   : Integer;
    DrawLineCount     : Integer;
    DrawPathCount     : Integer;
    DrawShadowCount   : Integer;
    DrawBorderCount   : Integer;
    DrawGradCount     : Integer;
    DrawTextCount     : Integer;
    DrawParagraphCount: Integer;
    DrawImageCount    : Integer;
    DrawPictureCount  : Integer;
    SaveLayerCount    : Integer;
    RestoreLayerCount : Integer;

    procedure OnSave(); override;
    procedure OnRestore(); override;
    procedure OnTransform(const AMatrix: TFloriaMatrix2D); override;
    procedure OnPushClipRect(const ARect: TRectD; AAntiAlias: Boolean); override;
    procedure OnPopClip(); override;
    procedure OnClear(const AColor: TBgraPixel); override;
    procedure OnDrawRect(const ARect: TRectD; const AFillColor, AStrokeColor: TBgraPixel; AStrokeWidth: Double); override;
    procedure OnDrawRoundedRect(const ARect: TRectD; ARadiusX, ARadiusY: Double; const AFillColor, AStrokeColor: TBgraPixel; AStrokeWidth: Double); override;
    procedure OnDrawCircle(ACenterX, ACenterY, ARadius: Double; const AFillColor, AStrokeColor: TBgraPixel; AStrokeWidth: Double); override;
    procedure OnDrawLine(AX1, AY1, AX2, AY2: Double; const AColor: TBgraPixel; AStrokeWidth: Double); override;
    procedure OnDrawPath(APath: TFloriaPath; const AFillColor, AStrokeColor: TBgraPixel; AStrokeWidth: Double; AFillRule: TFillRule); override;
    procedure OnDrawShadow(const ARect: TRectD; ARadius: Double; const AParams: TFloriaShadowParams); override;
    procedure OnDrawBorder(const ARect: TRectD; const AParams: TFloriaBorderParams); override;
    procedure OnDrawLinearGradient(const ARect: TRectD; const AP1, AP2: TPointD; const AStops: TFloriaGradientStopArray); override;
    procedure OnDrawText(const AText: string; AX, AY: Double; AFont: TFloriaFont; AFontSize: Double; const AColor: TBgraPixel); override;
    procedure OnDrawParagraph(AParagraph: TFloriaParagraph; AX, AY: Double); override;
    procedure OnDrawImage(AImage: TFloriaImage; const ADstRect, ASrcRect: TRectD; AOpacity: Double); override;
    procedure OnDrawPicture(APicture: TFloriaPicture; AX, AY: Double); override;
    procedure OnSaveLayer(const ABounds: TRectD; AOpacity: Double; AFilter: TFloriaImageFilter; ABlendMode: TFloriaBlendMode); override;
    procedure OnRestoreLayer(); override;
  end;

  TFloriaDisplayListTest = class(TTestCase)
  published
    procedure TestPictureCreationAndEmpty();
    procedure TestMatrixTransformations();
    procedure TestDrawPrimitivesRecording();
    procedure TestPathRecording();
    procedure TestTextAndParagraphRecording();
    procedure TestShadowAndBorderRecording();
    procedure TestLinearGradientRecording();
    procedure TestCanvasPlaybackBasic();
    procedure TestCanvasPlaybackRoundedRect();
    procedure TestCanvasPlaybackWithTransforms();
    procedure TestCanvasPlaybackSpatialCulling();
    procedure TestAlphaAndBlendModePlayback();
    procedure TestClipRectPlayback();
    procedure TestNestedPicturePlayback();
    procedure TestSaveLayerOpacityAndFilter();
    procedure TestPictureClone();
    procedure TestDisplayListDump();
    procedure TestCustomReceiverDispatch();
  end;

implementation

// -----------------------------------------------------------------------------
// TTestMockReceiver Implementation
// -----------------------------------------------------------------------------
procedure TTestMockReceiver.OnSave(); begin Inc(SaveCount); end;
procedure TTestMockReceiver.OnRestore(); begin Inc(RestoreCount); end;
procedure TTestMockReceiver.OnTransform(const AMatrix: TFloriaMatrix2D); begin Inc(TransformCount); end;
procedure TTestMockReceiver.OnPushClipRect(const ARect: TRectD; AAntiAlias: Boolean); begin Inc(PushClipCount); end;
procedure TTestMockReceiver.OnPopClip(); begin Inc(PopClipCount); end;
procedure TTestMockReceiver.OnClear(const AColor: TBgraPixel); begin Inc(ClearCount); end;
procedure TTestMockReceiver.OnDrawRect(const ARect: TRectD; const AFillColor, AStrokeColor: TBgraPixel; AStrokeWidth: Double); begin Inc(DrawRectCount); end;
procedure TTestMockReceiver.OnDrawRoundedRect(const ARect: TRectD; ARadiusX, ARadiusY: Double; const AFillColor, AStrokeColor: TBgraPixel; AStrokeWidth: Double); begin Inc(DrawRRectCount); end;
procedure TTestMockReceiver.OnDrawCircle(ACenterX, ACenterY, ARadius: Double; const AFillColor, AStrokeColor: TBgraPixel; AStrokeWidth: Double); begin Inc(DrawCircleCount); end;
procedure TTestMockReceiver.OnDrawLine(AX1, AY1, AX2, AY2: Double; const AColor: TBgraPixel; AStrokeWidth: Double); begin Inc(DrawLineCount); end;
procedure TTestMockReceiver.OnDrawPath(APath: TFloriaPath; const AFillColor, AStrokeColor: TBgraPixel; AStrokeWidth: Double; AFillRule: TFillRule); begin Inc(DrawPathCount); end;
procedure TTestMockReceiver.OnDrawShadow(const ARect: TRectD; ARadius: Double; const AParams: TFloriaShadowParams); begin Inc(DrawShadowCount); end;
procedure TTestMockReceiver.OnDrawBorder(const ARect: TRectD; const AParams: TFloriaBorderParams); begin Inc(DrawBorderCount); end;
procedure TTestMockReceiver.OnDrawLinearGradient(const ARect: TRectD; const AP1, AP2: TPointD; const AStops: TFloriaGradientStopArray); begin Inc(DrawGradCount); end;
procedure TTestMockReceiver.OnDrawText(const AText: string; AX, AY: Double; AFont: TFloriaFont; AFontSize: Double; const AColor: TBgraPixel); begin Inc(DrawTextCount); end;
procedure TTestMockReceiver.OnDrawParagraph(AParagraph: TFloriaParagraph; AX, AY: Double); begin Inc(DrawParagraphCount); end;
procedure TTestMockReceiver.OnDrawImage(AImage: TFloriaImage; const ADstRect, ASrcRect: TRectD; AOpacity: Double); begin Inc(DrawImageCount); end;
procedure TTestMockReceiver.OnDrawPicture(APicture: TFloriaPicture; AX, AY: Double); begin Inc(DrawPictureCount); end;
procedure TTestMockReceiver.OnSaveLayer(const ABounds: TRectD; AOpacity: Double; AFilter: TFloriaImageFilter; ABlendMode: TFloriaBlendMode); begin Inc(SaveLayerCount); end;
procedure TTestMockReceiver.OnRestoreLayer(); begin Inc(RestoreLayerCount); end;

// -----------------------------------------------------------------------------
// Tests Implementation
// -----------------------------------------------------------------------------
procedure TFloriaDisplayListTest.TestPictureCreationAndEmpty();
var
  Recorder: TFloriaPictureRecorder;
  Picture: TFloriaPicture;
begin
  Recorder := TFloriaPictureRecorder.Create();
  try
    Recorder.BeginRecording(400.0, 300.0);
    AssertTrue('Recorder is recording', Recorder.IsRecording);

    Picture := Recorder.EndRecording();
    try
      AssertFalse('Recorder is stopped', Recorder.IsRecording);
      AssertEquals('Width matches initial', 400.0, Picture.Width);
      AssertEquals('Height matches initial', 300.0, Picture.Height);
      AssertEquals('Op count is 0', 0, Picture.OpCount);
      AssertEquals('CullRect left', 0.0, Picture.CullRect.Left);
      AssertEquals('CullRect top', 0.0, Picture.CullRect.Top);
      AssertEquals('CullRect width', 400.0, Picture.CullRect.Width);
      AssertEquals('CullRect height', 300.0, Picture.CullRect.Height);
    finally
      Picture.Free();
    end;
  finally
    Recorder.Free();
  end;
end;

procedure TFloriaDisplayListTest.TestMatrixTransformations();
var
  M, T, S, R, Inv: TFloriaMatrix2D;
  Pt: TPointD;
  RIn, ROut: TRectD;
begin
  M := TFloriaMatrix2D.Identity();
  AssertTrue('Identity is identity', M.IsIdentity());
  AssertEquals('Determinant of identity is 1', 1.0, M.Determinant());

  // Translation
  T := TFloriaMatrix2D.Translation(50.0, 25.0);
  AssertTrue('Translation only', T.IsTranslationOnly());
  Pt := T.TransformPoint(PointD(10.0, 10.0));
  AssertEquals('Translated X', 60.0, Pt.X);
  AssertEquals('Translated Y', 35.0, Pt.Y);

  // Scaling
  S := TFloriaMatrix2D.Scaling(2.0, 3.0);
  Pt := S.TransformPoint(PointD(10.0, 10.0));
  AssertEquals('Scaled X', 20.0, Pt.X);
  AssertEquals('Scaled Y', 30.0, Pt.Y);

  // Composition: Translate then Scale
  M := T.Multiply(S);
  Pt := M.TransformPoint(PointD(10.0, 10.0));
  AssertEquals('Composed X', 70.0, Pt.X); // (10 * 2) + 50 = 70
  AssertEquals('Composed Y', 55.0, Pt.Y); // (10 * 3) + 25 = 55

  // Rotation 90 degrees about origin
  R := TFloriaMatrix2D.RotationDeg(90.0);
  Pt := R.TransformPoint(PointD(10.0, 0.0));
  AssertTrue('Rotated 90 deg X near 0', Abs(Pt.X) < 1e-4);
  AssertTrue('Rotated 90 deg Y near 10', Abs(Pt.Y - 10.0) < 1e-4);

  // Invert
  AssertTrue('Matrix is invertible', M.Invert(Inv));
  Pt := Inv.TransformPoint(PointD(70.0, 55.0));
  AssertTrue('Inverted X back to 10', Abs(Pt.X - 10.0) < 1e-4);
  AssertTrue('Inverted Y back to 10', Abs(Pt.Y - 10.0) < 1e-4);

  // TransformRect
  RIn := RectD(10.0, 20.0, 30.0, 40.0);
  ROut := T.TransformRect(RIn);
  AssertEquals('Transformed rect left', 60.0, ROut.Left);
  AssertEquals('Transformed rect top', 45.0, ROut.Top);
  AssertEquals('Transformed rect right', 80.0, ROut.Right);
  AssertEquals('Transformed rect bottom', 65.0, ROut.Bottom);
end;

procedure TFloriaDisplayListTest.TestDrawPrimitivesRecording();
var
  Recorder: TFloriaPictureRecorder;
  Picture: TFloriaPicture;
begin
  Recorder := TFloriaPictureRecorder.Create();
  try
    Recorder.BeginRecording(500.0, 500.0);

    Recorder.DrawRect(RectD(10.0, 10.0, 100.0, 80.0), BgraPixel(255, 0, 0, 255), BgraPixel(0, 0, 0, 255), 2.0);
    Recorder.DrawRoundedRect(RectD(150.0, 20.0, 250.0, 120.0), 8.0, 8.0, BgraPixel(0, 255, 0, 255));
    Recorder.DrawCircle(350.0, 70.0, 40.0, BgraPixel(0, 0, 255, 255), BgraPixel(255, 255, 0, 255), 4.0);
    Recorder.DrawLine(50.0, 200.0, 300.0, 200.0, BgraPixel(128, 128, 128, 255), 6.0);

    Picture := Recorder.EndRecording();
    try
      AssertEquals('Recorded 4 ops', 4, Picture.OpCount);

      AssertTrue('Op #0 is dopDrawRect', Picture.Op[0].OpType = dopDrawRect);
      AssertTrue('Op #0 has stroke', Picture.Op[0].HasStroke);
      AssertEquals('Op #0 stroke width', 2.0, Picture.Op[0].StrokeWidth);

      AssertTrue('Op #1 is dopDrawRoundedRect', Picture.Op[1].OpType = dopDrawRoundedRect);
      AssertEquals('Op #1 radius', 8.0, Picture.Op[1].RadiusX);

      AssertTrue('Op #2 is dopDrawCircle', Picture.Op[2].OpType = dopDrawCircle);
      AssertEquals('Op #2 radius', 40.0, Picture.Op[2].Radius);

      AssertTrue('Op #3 is dopDrawLine', Picture.Op[3].OpType = dopDrawLine);
      AssertEquals('Op #3 stroke width', 6.0, Picture.Op[3].StrokeWidth);

      // CullRect envelopes all items
      AssertTrue('CullRect encompasses rect left (with stroke expansion)', Picture.CullRect.Left <= 9.0);
      AssertTrue('CullRect encompasses circle right (with stroke)', Picture.CullRect.Right >= 392.0);
    finally
      Picture.Free();
    end;
  finally
    Recorder.Free();
  end;
end;

procedure TFloriaDisplayListTest.TestPathRecording();
var
  Recorder: TFloriaPictureRecorder;
  Picture: TFloriaPicture;
  Path: TFloriaPath;
begin
  Path := TFloriaPath.Create();
  try
    Path.AddRoundedRect(20.0, 20.0, 100.0, 60.0, 5.0, 5.0);

    Recorder := TFloriaPictureRecorder.Create();
    try
      Recorder.BeginRecording(400.0, 400.0);
      Recorder.DrawPath(Path, BgraPixel(200, 100, 50, 255), BgraPixel(0, 0, 0, 255), 2.0, frNonZero);
      Picture := Recorder.EndRecording();
      try
        AssertEquals('Recorded 1 path op', 1, Picture.OpCount);
        AssertTrue('Op is dopDrawPath', Picture.Op[0].OpType = dopDrawPath);
        AssertNotNull('Path instance exists', Picture.Op[0].Path);
        AssertFalse('Path is not empty', Picture.Op[0].Path.IsEmpty);
        AssertEquals('Subpath count preserved', 1, Picture.Op[0].Path.SubpathCount);
        AssertTrue('Bounds calculated', Picture.Op[0].Bounds.Width > 90.0);
      finally
        Picture.Free();
      end;
    finally
      Recorder.Free();
    end;
  finally
    Path.Free();
  end;
end;

procedure TFloriaDisplayListTest.TestTextAndParagraphRecording();
var
  Recorder: TFloriaPictureRecorder;
  Picture: TFloriaPicture;
  PBuilder: TFloriaParagraphBuilder;
  Paragraph: TFloriaParagraph;
begin
  Recorder := TFloriaPictureRecorder.Create();
  try
    Recorder.BeginRecording(600.0, 400.0);
    Recorder.DrawText('Floria Display List', 30.0, 50.0, 16.0, BgraPixel(0, 0, 0, 255));

    PBuilder := TFloriaParagraphBuilder.Create(TFloriaParagraphStyle.Default());
    try
      PBuilder.AddText('Rich multiline text inside picture');
      Paragraph := PBuilder.Build();
      Paragraph.Layout(200.0);
      Recorder.DrawParagraph(Paragraph, 30.0, 100.0, True); // Owned by picture
    finally
      PBuilder.Free();
    end;

    Picture := Recorder.EndRecording();
    try
      AssertEquals('Recorded 2 text ops', 2, Picture.OpCount);
      AssertTrue('Op #0 is dopDrawText', Picture.Op[0].OpType = dopDrawText);
      AssertEquals('Op #0 text matches', 'Floria Display List', Picture.Op[0].Text);

      AssertTrue('Op #1 is dopDrawParagraph', Picture.Op[1].OpType = dopDrawParagraph);
      AssertNotNull('Op #1 paragraph exists', Picture.Op[1].Paragraph);
      AssertTrue('Op #1 paragraph height > 0', Picture.Op[1].Paragraph.Height > 0.0);
    finally
      Picture.Free();
    end;
  finally
    Recorder.Free();
  end;
end;

procedure TFloriaDisplayListTest.TestShadowAndBorderRecording();
var
  Recorder: TFloriaPictureRecorder;
  Picture: TFloriaPicture;
begin
  Recorder := TFloriaPictureRecorder.Create();
  try
    Recorder.BeginRecording(400.0, 400.0);
    // Box shadow with offset (5, 5), blur 10, spread 2
    Recorder.DrawShadow(50.0, 50.0, 200.0, 100.0, 12.0, 5.0, 5.0, 10.0, 2.0, BgraPixel(0, 0, 0, 100));
    // Uniform border
    Recorder.DrawBorder(50.0, 50.0, 200.0, 100.0, 2.0, BgraPixel(60, 60, 60, 255), 12.0);

    Picture := Recorder.EndRecording();
    try
      AssertEquals('Recorded 2 ops', 2, Picture.OpCount);
      AssertTrue('Op #0 is dopDrawShadow', Picture.Op[0].OpType = dopDrawShadow);
      AssertEquals('Blur radius stored', 10.0, Picture.Op[0].ShadowParams.BlurRadius);
      AssertEquals('Spread radius stored', 2.0, Picture.Op[0].ShadowParams.SpreadRadius);

      // Shadow bounds must dilate by blur * 3 + spread = 32px
      AssertTrue('Shadow bounds dilated left', Picture.Op[0].Bounds.Left <= 50.0 + 5.0 - 32.0);

      AssertTrue('Op #1 is dopDrawBorder', Picture.Op[1].OpType = dopDrawBorder);
      AssertEquals('Border radius stored', 12.0, Picture.Op[1].BorderParams.RadiusX);
    finally
      Picture.Free();
    end;
  finally
    Recorder.Free();
  end;
end;

procedure TFloriaDisplayListTest.TestLinearGradientRecording();
var
  Recorder: TFloriaPictureRecorder;
  Picture: TFloriaPicture;
  Stops: array[0..1] of TFloriaGradientStop;
begin
  Stops[0] := FloriaGradientStop(0.0, BgraPixel(255, 0, 0, 255));
  Stops[1] := FloriaGradientStop(1.0, BgraPixel(0, 0, 255, 255));

  Recorder := TFloriaPictureRecorder.Create();
  try
    Recorder.BeginRecording(300.0, 300.0);
    Recorder.DrawLinearGradient(RectD(20.0, 20.0, 180.0, 100.0), 90.0, Stops);
    Picture := Recorder.EndRecording();
    try
      AssertEquals('Recorded 1 gradient op', 1, Picture.OpCount);
      AssertTrue('Op is dopDrawLinearGradient', Picture.Op[0].OpType = dopDrawLinearGradient);
      AssertEquals('Gradient stops count', 2, Length(Picture.Op[0].GradientStops));
      AssertEquals('Stop 0 offset', 0.0, Picture.Op[0].GradientStops[0].Offset);
      AssertEquals('Stop 1 offset', 1.0, Picture.Op[0].GradientStops[1].Offset);
    finally
      Picture.Free();
    end;
  finally
    Recorder.Free();
  end;
end;

procedure TFloriaDisplayListTest.TestCanvasPlaybackBasic();
var
  Img: TFloriaImage;
  Canvas: TFloriaCanvasAgg;
  Recorder: TFloriaPictureRecorder;
  Picture: TFloriaPicture;
  Pix: TBgraPixel;
begin
  Img := TFloriaImage.Create(100, 100);
  try
    Canvas := TFloriaCanvasAgg.Create(Img);
    try
      Canvas.Clear(1.0, 1.0, 1.0); // White background

      Recorder := TFloriaPictureRecorder.Create();
      try
        Recorder.BeginRecording(100.0, 100.0);
        // Fill blue rectangle in the center [25..75, 25..75]
        Recorder.DrawRect(RectD(25.0, 25.0, 75.0, 75.0), BgraPixel(0, 0, 255, 255));
        Picture := Recorder.EndRecording();
        try
          // Playback onto canvas
          Picture.Playback(Canvas);

          // Test center pixel is blue
          Pix := Img.Pixels[50, 50];
          AssertEquals('Red is 0', 0, Pix.R);
          AssertEquals('Green is 0', 0, Pix.G);
          AssertEquals('Blue is 255', 255, Pix.B);
          AssertEquals('Alpha is 255', 255, Pix.A);

          // Test corner pixel is still white
          Pix := Img.Pixels[5, 5];
          AssertEquals('Corner Red is 255', 255, Pix.R);
          AssertEquals('Corner Green is 255', 255, Pix.G);
          AssertEquals('Corner Blue is 255', 255, Pix.B);
        finally
          Picture.Free();
        end;
      finally
        Recorder.Free();
      end;
    finally
      Canvas.Free();
    end;
  finally
    Img.Free();
  end;
end;

procedure TFloriaDisplayListTest.TestCanvasPlaybackRoundedRect();
var
  Img: TFloriaImage;
  Canvas: TFloriaCanvasAgg;
  Recorder: TFloriaPictureRecorder;
  Picture: TFloriaPicture;
  Pix: TBgraPixel;
begin
  Img := TFloriaImage.Create(100, 100);
  try
    Canvas := TFloriaCanvasAgg.Create(Img);
    try
      Canvas.Clear(1.0, 1.0, 1.0);

      Recorder := TFloriaPictureRecorder.Create();
      try
        Recorder.BeginRecording(100.0, 100.0);
        Recorder.DrawRoundedRect(RectD(10.0, 10.0, 90.0, 90.0), 15.0, 15.0, BgraPixel(0, 180, 0, 255));
        Picture := Recorder.EndRecording();
        try
          Picture.Playback(Canvas);

          Pix := Img.Pixels[50, 50];
          AssertEquals('Center Green is 180', 180, Pix.G);
        finally
          Picture.Free();
        end;
      finally
        Recorder.Free();
      end;
    finally
      Canvas.Free();
    end;
  finally
    Img.Free();
  end;
end;

procedure TFloriaDisplayListTest.TestCanvasPlaybackWithTransforms();
var
  Img: TFloriaImage;
  Canvas: TFloriaCanvasAgg;
  Recorder: TFloriaPictureRecorder;
  Picture: TFloriaPicture;
  Pix: TBgraPixel;
begin
  Img := TFloriaImage.Create(100, 100);
  try
    Canvas := TFloriaCanvasAgg.Create(Img);
    try
      Canvas.Clear(0.0, 0.0, 0.0); // Black

      Recorder := TFloriaPictureRecorder.Create();
      try
        Recorder.BeginRecording(100.0, 100.0);
        Recorder.Save();
        Recorder.Translate(40.0, 30.0);
        // Draw 20x20 rect at local (0, 0) -> should appear at canvas (40..60, 30..50)
        Recorder.DrawRect(RectD(0.0, 0.0, 20.0, 20.0), BgraPixel(255, 255, 0, 255));
        Recorder.Restore();
        Picture := Recorder.EndRecording();
        try
          Picture.Playback(Canvas);

          // Transformed rect center: (50, 40)
          Pix := Img.Pixels[50, 40];
          AssertEquals('Translated pixel Red', 255, Pix.R);
          AssertEquals('Translated pixel Green', 255, Pix.G);

          // Outside at (10, 10) must remain black
          Pix := Img.Pixels[10, 10];
          AssertEquals('Untouched pixel Red', 0, Pix.R);
          AssertEquals('Untouched pixel Green', 0, Pix.G);
        finally
          Picture.Free();
        end;
      finally
        Recorder.Free();
      end;
    finally
      Canvas.Free();
    end;
  finally
    Img.Free();
  end;
end;

procedure TFloriaDisplayListTest.TestCanvasPlaybackSpatialCulling();
var
  Img: TFloriaImage;
  Canvas: TFloriaCanvasAgg;
  Recorder: TFloriaPictureRecorder;
  Picture: TFloriaPicture;
  Pix: TBgraPixel;
begin
  Img := TFloriaImage.Create(100, 100);
  try
    Canvas := TFloriaCanvasAgg.Create(Img);
    try
      Canvas.Clear(0.0, 0.0, 0.0);

      Recorder := TFloriaPictureRecorder.Create();
      try
        Recorder.BeginRecording(100.0, 100.0);
        // Box A on left: (10, 10) to (30, 30) - Red
        Recorder.DrawRect(RectD(10.0, 10.0, 30.0, 30.0), BgraPixel(255, 0, 0, 255));
        // Box B on right: (70, 70) to (90, 90) - Blue
        Recorder.DrawRect(RectD(70.0, 70.0, 90.0, 90.0), BgraPixel(0, 0, 255, 255));
        Picture := Recorder.EndRecording();
        try
          // Cull viewport: only encompasses Box A on left [0..40, 0..40]
          Picture.Playback(Canvas, RectD(0.0, 0.0, 40.0, 40.0));

          // Box A must be painted Red
          Pix := Img.Pixels[20, 20];
          AssertEquals('Box A painted Red', 255, Pix.R);

          // Box B was culled and must remain black (0, 0, 0)
          Pix := Img.Pixels[80, 80];
          AssertEquals('Box B was culled (Red=0)', 0, Pix.R);
          AssertEquals('Box B was culled (Blue=0)', 0, Pix.B);
        finally
          Picture.Free();
        end;
      finally
        Recorder.Free();
      end;
    finally
      Canvas.Free();
    end;
  finally
    Img.Free();
  end;
end;

procedure TFloriaDisplayListTest.TestAlphaAndBlendModePlayback();
var
  Recorder: TFloriaPictureRecorder;
  Picture: TFloriaPicture;
  Img: TFloriaImage;
  Canvas: TFloriaCanvasAgg;
begin
  Img := TFloriaImage.Create(50, 50);
  try
    Canvas := TFloriaCanvasAgg.Create(Img);
    try
      Recorder := TFloriaPictureRecorder.Create();
      try
        Recorder.BeginRecording(50.0, 50.0);
        Recorder.PushAlpha(0.5);
        Recorder.SetBlendMode(fbmMultiply);
        Recorder.DrawRect(RectD(0.0, 0.0, 50.0, 50.0), BgraPixel(100, 100, 100, 255));
        Recorder.PopAlpha();
        Picture := Recorder.EndRecording();
        try
          AssertEquals('Recorded 4 ops', 4, Picture.OpCount);
          Picture.Playback(Canvas);
          // Canvas blend mode restored or set during execution
          AssertTrue('Canvas executed without error', Canvas.Width = 50);
        finally
          Picture.Free();
        end;
      finally
        Recorder.Free();
      end;
    finally
      Canvas.Free();
    end;
  finally
    Img.Free();
  end;
end;

procedure TFloriaDisplayListTest.TestClipRectPlayback();
var
  Img: TFloriaImage;
  Canvas: TFloriaCanvasAgg;
  Recorder: TFloriaPictureRecorder;
  Picture: TFloriaPicture;
  Pix: TBgraPixel;
begin
  Img := TFloriaImage.Create(100, 100);
  try
    Canvas := TFloriaCanvasAgg.Create(Img);
    try
      Canvas.Clear(0.0, 0.0, 0.0);

      Recorder := TFloriaPictureRecorder.Create();
      try
        Recorder.BeginRecording(100.0, 100.0);
        // Push clip rect to [30, 30, 70, 70]
        Recorder.PushClipRect(RectD(30.0, 30.0, 70.0, 70.0));
        // Draw huge rect covering entire [0..100, 0..100] in Green
        Recorder.DrawRect(RectD(0.0, 0.0, 100.0, 100.0), BgraPixel(0, 255, 0, 255));
        Recorder.PopClip();
        Picture := Recorder.EndRecording();
        try
          Picture.Playback(Canvas);

          // Inside clip [50, 50] must be Green
          Pix := Img.Pixels[50, 50];
          AssertEquals('Inside clip is Green', 255, Pix.G);

          // Outside clip [10, 10] must remain Black
          Pix := Img.Pixels[10, 10];
          AssertEquals('Outside clip remains Black', 0, Pix.G);
        finally
          Picture.Free();
        end;
      finally
        Recorder.Free();
      end;
    finally
      Canvas.Free();
    end;
  finally
    Img.Free();
  end;
end;

procedure TFloriaDisplayListTest.TestNestedPicturePlayback();
var
  Img: TFloriaImage;
  Canvas: TFloriaCanvasAgg;
  SubRec, ParentRec: TFloriaPictureRecorder;
  SubPic, ParentPic: TFloriaPicture;
  Pix: TBgraPixel;
begin
  Img := TFloriaImage.Create(100, 100);
  try
    Canvas := TFloriaCanvasAgg.Create(Img);
    try
      Canvas.Clear(0.0, 0.0, 0.0);

      // Record child sub-picture (e.g. an icon): 20x20 cyan square
      SubRec := TFloriaPictureRecorder.Create();
      try
        SubRec.BeginRecording(20.0, 20.0);
        SubRec.DrawRect(RectD(0.0, 0.0, 20.0, 20.0), BgraPixel(0, 255, 255, 255));
        SubPic := SubRec.EndRecording();
      finally
        SubRec.Free();
      end;

      try
        // Record parent picture containing child at offset (60, 60)
        ParentRec := TFloriaPictureRecorder.Create();
        try
          ParentRec.BeginRecording(100.0, 100.0);
          ParentRec.DrawPicture(SubPic, 60.0, 60.0);
          ParentPic := ParentRec.EndRecording();
          try
            ParentPic.Playback(Canvas);

            // Sub-picture center: (70, 70) should be cyan
            Pix := Img.Pixels[70, 70];
            AssertEquals('SubPicture Cyan G', 255, Pix.G);
            AssertEquals('SubPicture Cyan B', 255, Pix.B);
            AssertEquals('SubPicture Cyan R', 0, Pix.R);

            // Origin (10, 10) untouched
            Pix := Img.Pixels[10, 10];
            AssertEquals('Origin untouched', 0, Pix.B);
          finally
            ParentPic.Free();
          end;
        finally
          ParentRec.Free();
        end;
      finally
        SubPic.Free();
      end;
    finally
      Canvas.Free();
    end;
  finally
    Img.Free();
  end;
end;

procedure TFloriaDisplayListTest.TestSaveLayerOpacityAndFilter();
var
  Recorder: TFloriaPictureRecorder;
  Picture: TFloriaPicture;
  Img: TFloriaImage;
  Canvas: TFloriaCanvasAgg;
begin
  Img := TFloriaImage.Create(80, 80);
  try
    Canvas := TFloriaCanvasAgg.Create(Img);
    try
      Canvas.Clear(1.0, 1.0, 1.0);

      Recorder := TFloriaPictureRecorder.Create();
      try
        Recorder.BeginRecording(80.0, 80.0);
        Recorder.SaveLayer(RectD(10.0, 10.0, 70.0, 70.0), 0.7);
        Recorder.DrawRect(RectD(10.0, 10.0, 70.0, 70.0), BgraPixel(200, 0, 0, 255));
        Recorder.RestoreLayer();
        Picture := Recorder.EndRecording();
        try
          Picture.Playback(Canvas);
          AssertTrue('Layer executed cleanly', Picture.OpCount = 3);
        finally
          Picture.Free();
        end;
      finally
        Recorder.Free();
      end;
    finally
      Canvas.Free();
    end;
  finally
    Img.Free();
  end;
end;

procedure TFloriaDisplayListTest.TestPictureClone();
var
  Recorder: TFloriaPictureRecorder;
  Original, Cloned: TFloriaPicture;
begin
  Recorder := TFloriaPictureRecorder.Create();
  try
    Recorder.BeginRecording(300.0, 200.0);
    Recorder.DrawRect(RectD(10.0, 10.0, 50.0, 50.0), BgraPixel(255, 0, 0, 255));
    Recorder.DrawCircle(100.0, 100.0, 25.0, BgraPixel(0, 255, 0, 255));
    Original := Recorder.EndRecording();
    try
      Cloned := Original.Clone();
      try
        AssertEquals('Cloned OpCount equals original', Original.OpCount, Cloned.OpCount);
        AssertEquals('Cloned Width equals original', Original.Width, Cloned.Width);
        AssertEquals('Cloned Height equals original', Original.Height, Cloned.Height);
        AssertEquals('Cloned CullRect Left', Original.CullRect.Left, Cloned.CullRect.Left);
        AssertEquals('Cloned CullRect Right', Original.CullRect.Right, Cloned.CullRect.Right);
        AssertTrue('Cloned Op 0 matches', Cloned.Op[0].OpType = dopDrawRect);
        AssertTrue('Cloned Op 1 matches', Cloned.Op[1].OpType = dopDrawCircle);
      finally
        Cloned.Free();
      end;
    finally
      Original.Free();
    end;
  finally
    Recorder.Free();
  end;
end;

procedure TFloriaDisplayListTest.TestDisplayListDump();
var
  Recorder: TFloriaPictureRecorder;
  Picture: TFloriaPicture;
  DumpStr: string;
begin
  Recorder := TFloriaPictureRecorder.Create();
  try
    Recorder.BeginRecording(500.0, 500.0);
    Recorder.Save();
    Recorder.Translate(20.0, 20.0);
    Recorder.DrawRect(RectD(0.0, 0.0, 100.0, 50.0), BgraPixel(255, 0, 0, 255));
    Recorder.DrawText('Diagnostic Dump', 10.0, 20.0, 14.0, BgraPixel(0, 0, 0, 255));
    Recorder.Restore();
    Picture := Recorder.EndRecording();
    try
      DumpStr := Picture.Dump();
      AssertTrue('Dump contains Picture header', Pos('Picture [0.0, 0.0, 500.0, 500.0]', DumpStr) > 0);
      AssertTrue('Dump contains dopSave', Pos('dopSave', DumpStr) > 0);
      AssertTrue('Dump contains dopTranslate', Pos('dopTranslate', DumpStr) > 0);
      AssertTrue('Dump contains dopDrawRect', Pos('dopDrawRect', DumpStr) > 0);
      AssertTrue('Dump contains dopDrawText', Pos('dopDrawText', DumpStr) > 0);
      AssertTrue('Dump contains text string', Pos('Diagnostic Dump', DumpStr) > 0);
      AssertTrue('Dump contains dopRestore', Pos('dopRestore', DumpStr) > 0);
    finally
      Picture.Free();
    end;
  finally
    Recorder.Free();
  end;
end;

procedure TFloriaDisplayListTest.TestCustomReceiverDispatch();
var
  Recorder: TFloriaPictureRecorder;
  Picture: TFloriaPicture;
  Receiver: TTestMockReceiver;
begin
  Receiver := TTestMockReceiver.Create();
  try
    Recorder := TFloriaPictureRecorder.Create();
    try
      Recorder.BeginRecording(400.0, 400.0);
      Recorder.Save();
      Recorder.PushClipRect(RectD(10.0, 10.0, 100.0, 100.0));
      Recorder.DrawRect(RectD(20.0, 20.0, 50.0, 50.0), BgraPixel(255, 0, 0, 255));
      Recorder.DrawCircle(60.0, 60.0, 15.0, BgraPixel(0, 255, 0, 255));
      Recorder.DrawLine(10.0, 10.0, 90.0, 90.0, BgraPixel(0, 0, 255, 255));
      Recorder.PopClip();
      Recorder.Restore();

      Picture := Recorder.EndRecording();
      try
        Picture.Playback(Receiver);

        AssertEquals('Save dispatched', 1, Receiver.SaveCount);
        AssertEquals('PushClip dispatched', 1, Receiver.PushClipCount);
        AssertEquals('DrawRect dispatched', 1, Receiver.DrawRectCount);
        AssertEquals('DrawCircle dispatched', 1, Receiver.DrawCircleCount);
        AssertEquals('DrawLine dispatched', 1, Receiver.DrawLineCount);
        AssertEquals('PopClip dispatched', 1, Receiver.PopClipCount);
        AssertEquals('Restore dispatched', 1, Receiver.RestoreCount);
      finally
        Picture.Free();
      end;
    finally
      Recorder.Free();
    end;
  finally
    Receiver.Free();
  end;
end;

initialization
  RegisterTest(TFloriaDisplayListTest);

end.
