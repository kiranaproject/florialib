unit Floria.Text.HarfBuzz.Test;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry,
  Floria.Font,
  Floria.Unicode.BiDi,
  Floria.Text.HarfBuzz;

type
  TFloriaHarfBuzzTest = class(TTestCase)
  published
    procedure TestHarfBuzzAvailability();
    procedure TestShapeLatin();
    procedure TestShapeArabic();
    procedure TestShapeBiDiMixed();
    procedure TestRunWidthCalculation();
    procedure TestNilFontSafety();
  end;

implementation

procedure TFloriaHarfBuzzTest.TestHarfBuzzAvailability();
var
  hb: THarfBuzzEngine;
begin
  hb := FloriaHarfBuzz();
  // libharfbuzz.so.0 should be present on standard Linux installations
  AssertTrue('HarfBuzz available', hb.Available);
  AssertTrue('Version not empty', Length(hb.Version) > 0);
end;

procedure TFloriaHarfBuzzTest.TestShapeLatin();
var
  fnt: TFloriaFont;
  shaped: TFloriaShapedRun;
begin
  // Create system font via font manager
  fnt := FloriaFontManager().GetFont('Sans-12');
  try
    AssertNotNull('Font loaded', fnt);
    shaped := FloriaShapeRun(fnt, 'Hello World', fbdLTR);
    AssertTrue('Shaped glyphs produced', Length(shaped) > 0);
    AssertTrue('First glyph has advance', shaped[0].XAdvance > 0.0);
    AssertTrue('Positive total width', FloriaShapedRunWidth(shaped) > 0.0);
  finally
    // font is managed by manager cache, do not free
  end;
end;

procedure TFloriaHarfBuzzTest.TestShapeArabic();
var
  fnt: TFloriaFont;
  shaped: TFloriaShapedRun;
begin
  fnt := FloriaFontManager().GetFont('Sans-12');
  try
    AssertNotNull('Font loaded', fnt);
    shaped := FloriaShapeRun(fnt, 'مرحبا', fbdRTL);
    AssertTrue('Arabic glyphs produced', Length(shaped) > 0);
    AssertTrue('Total width positive', FloriaShapedRunWidth(shaped) > 0.0);
  finally
  end;
end;

procedure TFloriaHarfBuzzTest.TestShapeBiDiMixed();
var
  fnt: TFloriaFont;
  shaped: TFloriaShapedRun;
begin
  fnt := FloriaFontManager().GetFont('Sans-12');
  try
    AssertNotNull('Font loaded', fnt);
    shaped := FloriaShapeText(fnt, 'Hello مرحبا world');
    AssertTrue('Mixed BiDi glyphs produced', Length(shaped) > 0);
    AssertTrue('Positive total width', FloriaShapedRunWidth(shaped) > 0.0);
  finally
  end;
end;

procedure TFloriaHarfBuzzTest.TestRunWidthCalculation();
var
  shaped: TFloriaShapedRun;
  w: Double;
begin
  SetLength(shaped, 3);
  shaped[0].XAdvance := 10.5;
  shaped[1].XAdvance := 20.0;
  shaped[2].XAdvance := 5.5;
  w := FloriaShapedRunWidth(shaped);
  AssertEquals('Sum of advances', 36.0, w);
end;

procedure TFloriaHarfBuzzTest.TestNilFontSafety();
var
  shaped: TFloriaShapedRun;
begin
  shaped := FloriaShapeRun(nil, 'test', fbdLTR);
  AssertEquals('Nil font returns empty run', 0, Length(shaped));

  shaped := FloriaShapeText(nil, 'test');
  AssertEquals('Nil font returns empty run', 0, Length(shaped));
end;

initialization
  RegisterTest(TFloriaHarfBuzzTest);

end.
