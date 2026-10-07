unit Floria.Text.Paragraph.Test;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, fpcunit, testregistry,
  Floria.Image.Core,
  Floria.Font,
  Floria.Canvas.Agg,
  Floria.Path.Clipper.Core,
  Floria.Text.Paragraph;

type
  TFloriaParagraphTest = class(TTestCase)
  published
    procedure TestParagraphCreationAndEmpty();
    procedure TestSingleLineLayout();
    procedure TestMultiStyleSpans();
    procedure TestLineWrappingConstraint();
    procedure TestMandatoryLineBreaks();
    procedure TestTextAlignments();
    procedure TestMaxLinesConstraint();
    procedure TestEllipsisOverflow();
    procedure TestUAX14CJKWordBreaking();
    procedure TestUAX14KinsokuPunctuation();
    procedure TestHyphenBreaking();
    procedure TestTextDecorations();
    procedure TestBackgroundHighlights();
    procedure TestInlinePlaceholders();
    procedure TestHitTestingAndPositionForOffset();
    procedure TestSelectionRectsForRange();
    procedure TestIntrinsicDimensions();
    procedure TestCanvasPainting();
  end;

implementation

procedure TFloriaParagraphTest.TestParagraphCreationAndEmpty();
var
  Builder: TFloriaParagraphBuilder;
  Paragraph: TFloriaParagraph;
begin
  Builder := TFloriaParagraphBuilder.Create(TFloriaParagraphStyle.Default());
  try
    Paragraph := Builder.Build();
    try
      Paragraph.Layout(200.0);
      AssertEquals('Empty paragraph has 0 lines', 0, Paragraph.LineCount);
      AssertTrue('Empty paragraph has 0 height', Paragraph.Height <= 0.001);
      AssertEquals('Plain text is empty', '', Paragraph.PlainText);
    finally
      Paragraph.Free();
    end;
  finally
    Builder.Free();
  end;
end;

procedure TFloriaParagraphTest.TestSingleLineLayout();
var
  Builder: TFloriaParagraphBuilder;
  Paragraph: TFloriaParagraph;
  Metrics: TFloriaLineMetrics;
begin
  Builder := TFloriaParagraphBuilder.Create(TFloriaParagraphStyle.Default());
  try
    Builder.AddText('Hello Floria');
    Paragraph := Builder.Build();
    try
      Paragraph.Layout(500.0);
      AssertEquals('Single line count', 1, Paragraph.LineCount);
      AssertTrue('Width > 0', Paragraph.Width > 0.0);
      AssertTrue('Height > 0', Paragraph.Height > 0.0);

      Metrics := Paragraph.GetLineMetrics(0);
      AssertEquals('Line number is 0', 0, Metrics.LineNumber);
      AssertTrue('Line width > 0', Metrics.Width > 0.0);
      AssertTrue('Line height > 0', Metrics.Height > 0.0);
      AssertTrue('Baseline > 0', Metrics.Baseline > 0.0);
      AssertFalse('Is not hard break', Metrics.IsHardBreak);
      AssertFalse('Is not ellipsized', Metrics.IsEllipsized);
    finally
      Paragraph.Free();
    end;
  finally
    Builder.Free();
  end;
end;

procedure TFloriaParagraphTest.TestMultiStyleSpans();
var
  Builder: TFloriaParagraphBuilder;
  Paragraph: TFloriaParagraph;
  TStyle: TFloriaTextStyle;
begin
  Builder := TFloriaParagraphBuilder.Create(TFloriaParagraphStyle.Default());
  try
    // Span 1: Normal black
    TStyle := TFloriaTextStyle.Create('Sans', 12.0, TBgraPixel.Create(0, 0, 0));
    Builder.PushStyle(TStyle);
    Builder.AddText('Normal ');
    Builder.PopStyle();

    // Span 2: Bold Red
    TStyle := TFloriaTextStyle.Create('Sans', 16.0, TBgraPixel.Create(255, 0, 0), True, False);
    Builder.PushStyle(TStyle);
    Builder.AddText('Bold Red ');
    Builder.PopStyle();

    // Span 3: Italic Blue
    TStyle := TFloriaTextStyle.Create('Sans', 14.0, TBgraPixel.Create(0, 0, 255), False, True);
    Builder.PushStyle(TStyle);
    Builder.AddText('Italic Blue');
    Builder.PopStyle();

    Paragraph := Builder.Build();
    try
      Paragraph.Layout(600.0);
      AssertEquals('All spans fit on 1 line', 1, Paragraph.LineCount);
      AssertEquals('Plain text concatenated properly', 'Normal Bold Red Italic Blue', Paragraph.PlainText);
      AssertTrue('Height accounts for largest font (16pt)', Paragraph.Height >= 16.0);
    finally
      Paragraph.Free();
    end;
  finally
    Builder.Free();
  end;
end;

procedure TFloriaParagraphTest.TestLineWrappingConstraint();
var
  Builder: TFloriaParagraphBuilder;
  Paragraph: TFloriaParagraph;
  Text: string;
begin
  Builder := TFloriaParagraphBuilder.Create(TFloriaParagraphStyle.Default());
  try
    Text := 'Floria Toolkit provides modern pure Object Pascal desktop UI components with high performance vector graphics.';
    Builder.AddText(Text);
    Paragraph := Builder.Build();
    try
      // Unconstrained / wide: 1 line
      Paragraph.Layout(2000.0);
      AssertEquals('Wide constraint gives 1 line', 1, Paragraph.LineCount);

      // Narrow constraint: must wrap into multiple lines
      Paragraph.Layout(200.0);
      AssertTrue('Narrow constraint wraps into at least 3 lines', Paragraph.LineCount >= 3);
      AssertTrue('Total height increases proportionally', Paragraph.Height > 40.0);
    finally
      Paragraph.Free();
    end;
  finally
    Builder.Free();
  end;
end;

procedure TFloriaParagraphTest.TestMandatoryLineBreaks();
var
  Builder: TFloriaParagraphBuilder;
  Paragraph: TFloriaParagraph;
  M1, M2, M3: TFloriaLineMetrics;
begin
  Builder := TFloriaParagraphBuilder.Create(TFloriaParagraphStyle.Default());
  try
    Builder.AddText('Line 1'#10'Line 2'#13#10'Line 3');
    Paragraph := Builder.Build();
    try
      Paragraph.Layout(500.0);
      AssertEquals('Exactly 3 lines from mandatory breaks', 3, Paragraph.LineCount);

      M1 := Paragraph.GetLineMetrics(0);
      M2 := Paragraph.GetLineMetrics(1);
      M3 := Paragraph.GetLineMetrics(2);

      AssertTrue('Line 1 is hard break', M1.IsHardBreak);
      AssertTrue('Line 2 is hard break', M2.IsHardBreak);
      AssertFalse('Line 3 is end of text', M3.IsHardBreak);
      AssertTrue('Line 2 below Line 1', M2.Top >= M1.Top + M1.Height);
      AssertTrue('Line 3 below Line 2', M3.Top >= M2.Top + M2.Height);
    finally
      Paragraph.Free();
    end;
  finally
    Builder.Free();
  end;
end;

procedure TFloriaParagraphTest.TestTextAlignments();
var
  PStyle: TFloriaParagraphStyle;
  Builder: TFloriaParagraphBuilder;
  Paragraph: TFloriaParagraph;
  MLeft, MRight, MCenter: TFloriaLineMetrics;
begin
  // 1. Left
  PStyle := TFloriaParagraphStyle.Default();
  PStyle.Alignment := ftaLeft;
  Builder := TFloriaParagraphBuilder.Create(PStyle);
  try
    Builder.AddText('Aligned Text');
    Paragraph := Builder.Build();
    try
      Paragraph.Layout(400.0);
      MLeft := Paragraph.GetLineMetrics(0);
      AssertTrue('Left aligned starts near 0', Abs(MLeft.Left - 0.0) < 0.1);
    finally
      Paragraph.Free();
    end;
  finally
    Builder.Free();
  end;

  // 2. Right
  PStyle.Alignment := ftaRight;
  Builder := TFloriaParagraphBuilder.Create(PStyle);
  try
    Builder.AddText('Aligned Text');
    Paragraph := Builder.Build();
    try
      Paragraph.Layout(400.0);
      MRight := Paragraph.GetLineMetrics(0);
      AssertTrue('Right aligned starts at 400 - Width', Abs(MRight.Left - (400.0 - MRight.Width)) < 1.0);
    finally
      Paragraph.Free();
    end;
  finally
    Builder.Free();
  end;

  // 3. Center
  PStyle.Alignment := ftaCenter;
  Builder := TFloriaParagraphBuilder.Create(PStyle);
  try
    Builder.AddText('Aligned Text');
    Paragraph := Builder.Build();
    try
      Paragraph.Layout(400.0);
      MCenter := Paragraph.GetLineMetrics(0);
      AssertTrue('Center aligned starts near (400 - Width)/2', Abs(MCenter.Left - ((400.0 - MCenter.Width) * 0.5)) < 1.0);
    finally
      Paragraph.Free();
    end;
  finally
    Builder.Free();
  end;
end;

procedure TFloriaParagraphTest.TestMaxLinesConstraint();
var
  PStyle: TFloriaParagraphStyle;
  Builder: TFloriaParagraphBuilder;
  Paragraph: TFloriaParagraph;
begin
  PStyle := TFloriaParagraphStyle.Default();
  PStyle.MaxLines := 2;
  Builder := TFloriaParagraphBuilder.Create(PStyle);
  try
    Builder.AddText('One'#10'Two'#10'Three'#10'Four'#10'Five');
    Paragraph := Builder.Build();
    try
      Paragraph.Layout(400.0);
      AssertEquals('Line count clamped to MaxLines = 2', 2, Paragraph.LineCount);
      AssertTrue('DidExceedMaxLines is True', Paragraph.DidExceedMaxLines);
    finally
      Paragraph.Free();
    end;
  finally
    Builder.Free();
  end;
end;

procedure TFloriaParagraphTest.TestEllipsisOverflow();
var
  PStyle: TFloriaParagraphStyle;
  Builder: TFloriaParagraphBuilder;
  Paragraph: TFloriaParagraph;
  M: TFloriaLineMetrics;
begin
  PStyle := TFloriaParagraphStyle.Default();
  PStyle.MaxLines := 1;
  PStyle.Overflow := ftoEllipsis;
  PStyle.Ellipsis := '...';

  Builder := TFloriaParagraphBuilder.Create(PStyle);
  try
    Builder.AddText('This is a very long sentence that will certainly exceed the tight constraint width.');
    Paragraph := Builder.Build();
    try
      Paragraph.Layout(120.0);
      AssertEquals('MaxLines 1 enforced', 1, Paragraph.LineCount);
      AssertTrue('Exceeded max lines', Paragraph.DidExceedMaxLines);
      M := Paragraph.GetLineMetrics(0);
      AssertTrue('Last line is marked ellipsized', M.IsEllipsized);
      AssertTrue('Line width fits within constraint', M.Width <= 120.0);
    finally
      Paragraph.Free();
    end;
  finally
    Builder.Free();
  end;
end;

procedure TFloriaParagraphTest.TestUAX14CJKWordBreaking();
var
  Builder: TFloriaParagraphBuilder;
  Paragraph: TFloriaParagraph;
  CJKText: string;
begin
  Builder := TFloriaParagraphBuilder.Create(TFloriaParagraphStyle.Default());
  try
    // Continuous Japanese text without spaces
    CJKText := 'これはテストです。日本語の段落レイアウトエンジンが正常に改行されるか確認します。';
    Builder.AddText(CJKText);
    Paragraph := Builder.Build();
    try
      // In a narrow width, it should break cleanly across multiple lines
      Paragraph.Layout(150.0);
      AssertTrue('CJK text wraps into multiple lines without spaces', Paragraph.LineCount >= 3);
    finally
      Paragraph.Free();
    end;
  finally
    Builder.Free();
  end;
end;

procedure TFloriaParagraphTest.TestUAX14KinsokuPunctuation();
begin
  // Verify classification helpers
  AssertTrue('Full-width comma is closing punctuation', FloriaIsClosingPunctuation($3001));
  AssertTrue('Full-width ideographic full stop is closing punctuation', FloriaIsClosingPunctuation($3002));
  AssertTrue('Japanese right corner bracket is closing punctuation', FloriaIsClosingPunctuation($300D));
  AssertTrue('Japanese left corner bracket is opening punctuation', FloriaIsOpeningPunctuation($300C));
  AssertTrue('Japanese double angle bracket is opening punctuation', FloriaIsOpeningPunctuation($300A));
  AssertFalse('Regular Han character is not punctuation', FloriaIsClosingPunctuation($4E00));
end;

procedure TFloriaParagraphTest.TestHyphenBreaking();
var
  Builder: TFloriaParagraphBuilder;
  Paragraph: TFloriaParagraph;
begin
  Builder := TFloriaParagraphBuilder.Create(TFloriaParagraphStyle.Default());
  try
    Builder.AddText('high-performance multi-platform zero-dependency');
    Paragraph := Builder.Build();
    try
      // Constrained to fit roughly 2 words per line
      Paragraph.Layout(180.0);
      AssertTrue('Hyphenated words wrap into multiple lines', Paragraph.LineCount >= 2);
    finally
      Paragraph.Free();
    end;
  finally
    Builder.Free();
  end;
end;

procedure TFloriaParagraphTest.TestTextDecorations();
var
  Builder: TFloriaParagraphBuilder;
  Paragraph: TFloriaParagraph;
  TStyle: TFloriaTextStyle;
begin
  Builder := TFloriaParagraphBuilder.Create(TFloriaParagraphStyle.Default());
  try
    TStyle := TFloriaTextStyle.Default();
    TStyle.Decorations := [ftdUnderline, ftdLineThrough];
    TStyle.DecorationColor := TBgraPixel.Create(255, 0, 0);
    TStyle.DecorationThickness := 2.0;

    Builder.PushStyle(TStyle);
    Builder.AddText('Underline & Strike');
    Builder.PopStyle();

    Paragraph := Builder.Build();
    try
      Paragraph.Layout(300.0);
      AssertEquals('Line count 1', 1, Paragraph.LineCount);
      AssertTrue('Paragraph has height', Paragraph.Height > 0);
    finally
      Paragraph.Free();
    end;
  finally
    Builder.Free();
  end;
end;

procedure TFloriaParagraphTest.TestBackgroundHighlights();
var
  Builder: TFloriaParagraphBuilder;
  Paragraph: TFloriaParagraph;
  TStyle: TFloriaTextStyle;
begin
  Builder := TFloriaParagraphBuilder.Create(TFloriaParagraphStyle.Default());
  try
    TStyle := TFloriaTextStyle.Default();
    TStyle.HasBackground := True;
    TStyle.BackgroundColor := TBgraPixel.Create(255, 255, 0, 180); // Translucent yellow highlight

    Builder.PushStyle(TStyle);
    Builder.AddText('Highlighted Text');
    Builder.PopStyle();

    Paragraph := Builder.Build();
    try
      Paragraph.Layout(300.0);
      AssertEquals('Line count 1', 1, Paragraph.LineCount);
      AssertTrue('Paragraph height > 0', Paragraph.Height > 0);
    finally
      Paragraph.Free();
    end;
  finally
    Builder.Free();
  end;
end;

procedure TFloriaParagraphTest.TestInlinePlaceholders();
var
  Builder: TFloriaParagraphBuilder;
  Paragraph: TFloriaParagraph;
  Bounds: TRectD;
begin
  Builder := TFloriaParagraphBuilder.Create(TFloriaParagraphStyle.Default());
  try
    Builder.AddText('Status: ');
    // Add inline 24x24 icon badge with ID 101
    Builder.AddPlaceholder(24.0, 24.0, fpaMiddle, 0.0, 101);
    Builder.AddText(' Active');

    Paragraph := Builder.Build();
    try
      Paragraph.Layout(400.0);
      AssertEquals('Single line with placeholder', 1, Paragraph.LineCount);

      Bounds := Paragraph.GetPlaceholderBounds(101);
      AssertTrue('Placeholder Width is 24', Abs((Bounds.Right - Bounds.Left) - 24.0) < 0.1);
      AssertTrue('Placeholder Height is 24', Abs((Bounds.Bottom - Bounds.Top) - 24.0) < 0.1);
      AssertTrue('Placeholder positioned after "Status: "', Bounds.Left > 20.0);
    finally
      Paragraph.Free();
    end;
  finally
    Builder.Free();
  end;
end;

procedure TFloriaParagraphTest.TestHitTestingAndPositionForOffset();
var
  Builder: TFloriaParagraphBuilder;
  Paragraph: TFloriaParagraph;
  PosStart, PosEnd: TFloriaTextPosition;
begin
  Builder := TFloriaParagraphBuilder.Create(TFloriaParagraphStyle.Default());
  try
    Builder.AddText('First Line'#10'Second Line');
    Paragraph := Builder.Build();
    try
      Paragraph.Layout(400.0);
      AssertEquals('2 lines', 2, Paragraph.LineCount);

      // Hit-test near start of line 0
      PosStart := Paragraph.GetPositionForOffset(2.0, 5.0);
      AssertEquals('Line index is 0', 0, PosStart.LineIndex);
      AssertEquals('Byte offset at start is 0', 0, PosStart.TextOffset);

      // Hit-test on line 1
      PosEnd := Paragraph.GetPositionForOffset(20.0, 25.0);
      AssertEquals('Line index is 1', 1, PosEnd.LineIndex);
      AssertTrue('Offset is into second line', PosEnd.TextOffset >= 10);
    finally
      Paragraph.Free();
    end;
  finally
    Builder.Free();
  end;
end;

procedure TFloriaParagraphTest.TestSelectionRectsForRange();
var
  Builder: TFloriaParagraphBuilder;
  Paragraph: TFloriaParagraph;
  Rects: TRectDArray;
begin
  Builder := TFloriaParagraphBuilder.Create(TFloriaParagraphStyle.Default());
  try
    Builder.AddText('Line one text'#10'Line two text');
    Paragraph := Builder.Build();
    try
      Paragraph.Layout(400.0);

      // Select spanning across newline
      Rects := Paragraph.GetRectsForRange(5, 18);
      AssertEquals('Selection spans 2 lines', 2, Length(Rects));
      AssertTrue('First rect width > 0', Rects[0].Right > Rects[0].Left);
      AssertTrue('Second rect width > 0', Rects[1].Right > Rects[1].Left);
      AssertTrue('Second rect below first', Rects[1].Top >= Rects[0].Bottom);
    finally
      Paragraph.Free();
    end;
  finally
    Builder.Free();
  end;
end;

procedure TFloriaParagraphTest.TestIntrinsicDimensions();
var
  Builder: TFloriaParagraphBuilder;
  Paragraph: TFloriaParagraph;
begin
  Builder := TFloriaParagraphBuilder.Create(TFloriaParagraphStyle.Default());
  try
    Builder.AddText('Short line'#10'A much longer second line of text here');
    Paragraph := Builder.Build();
    try
      Paragraph.Layout(500.0);
      AssertTrue('MaxIntrinsicWidth > MinIntrinsicWidth', Paragraph.MaxIntrinsicWidth > Paragraph.MinIntrinsicWidth);
      AssertTrue('MaxIntrinsicWidth > 150', Paragraph.MaxIntrinsicWidth > 150.0);
      AssertTrue('MinIntrinsicWidth > 10', Paragraph.MinIntrinsicWidth > 10.0);
    finally
      Paragraph.Free();
    end;
  finally
    Builder.Free();
  end;
end;

procedure TFloriaParagraphTest.TestCanvasPainting();
var
  Img: TFloriaImage;
  Builder: TFloriaParagraphBuilder;
  Paragraph: TFloriaParagraph;
  Canvas: TFloriaCanvasAgg;
begin
  Img := TFloriaImage.Create(300, 150);
  try
    Canvas := TFloriaCanvasAgg.Create(Img);
    try
      Canvas.Clear(1.0, 1.0, 1.0);

      Builder := TFloriaParagraphBuilder.Create(TFloriaParagraphStyle.Default());
      try
        Builder.AddText('Canvas painting test with rich paragraph');
        Paragraph := Builder.Build();
        try
          Paragraph.Layout(280.0);
          // Paint onto canvas
          Paragraph.Paint(Canvas, 10.0, 10.0);
          AssertTrue('Painted without exception', Paragraph.Height > 0);
        finally
          Paragraph.Free();
        end;
      finally
        Builder.Free();
      end;
    finally
      Canvas.Free();
    end;
  finally
    Img.Free();
  end;
end;

initialization
  RegisterTest(TFloriaParagraphTest);

end.
