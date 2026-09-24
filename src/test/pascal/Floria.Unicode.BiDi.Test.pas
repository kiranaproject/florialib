unit Floria.Unicode.BiDi.Test;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry,
  Floria.Unicode.BiDi;

type
  TFloriaBiDiTest = class(TTestCase)
  published
    procedure TestBidiClassClassification();
    procedure TestHasRTL();
    procedure TestBracketMirroring();
    procedure TestPureLTR();
    procedure TestPureRTL();
    procedure TestMixedBiDiRuns();
    procedure TestNumbersInRTL();
    procedure TestReorderToVisualString();
  end;

implementation

procedure TFloriaBiDiTest.TestBidiClassClassification();
begin
  // Latin -> fbcL
  AssertTrue('A is L', TFloriaBiDi.GetBidiClass(Ord('A')) = fbcL);
  AssertTrue('z is L', TFloriaBiDi.GetBidiClass(Ord('z')) = fbcL);

  // Hebrew -> fbcR
  AssertTrue('Alef is R', TFloriaBiDi.GetBidiClass($05D0) = fbcR);

  // Arabic -> fbcAL
  AssertTrue('Meem is AL', TFloriaBiDi.GetBidiClass($0645) = fbcAL);

  // Digits -> fbcEN
  AssertTrue('0 is EN', TFloriaBiDi.GetBidiClass(Ord('0')) = fbcEN);
  AssertTrue('9 is EN', TFloriaBiDi.GetBidiClass(Ord('9')) = fbcEN);

  // Arabic-Indic Digits -> fbcAN
  AssertTrue('Arabic 0 is AN', TFloriaBiDi.GetBidiClass($0660) = fbcAN);

  // Separators & Whitespace
  AssertTrue('Space is WS', TFloriaBiDi.GetBidiClass(Ord(' ')) = fbcWS);
  AssertTrue('Plus is ES', TFloriaBiDi.GetBidiClass(Ord('+')) = fbcES);
  AssertTrue('Comma is CS', TFloriaBiDi.GetBidiClass(Ord(',')) = fbcCS);
end;

procedure TFloriaBiDiTest.TestHasRTL();
begin
  AssertFalse('Latin only', TFloriaBiDi.HasRTL('Hello, World! 123'));
  AssertFalse('CJK', TFloriaBiDi.HasRTL('你好世界'));
  AssertTrue('Arabic', TFloriaBiDi.HasRTL('مرحبا'));
  AssertTrue('Hebrew', TFloriaBiDi.HasRTL('שלום'));
  AssertTrue('Mixed', TFloriaBiDi.HasRTL('Hello مرحبا world'));
end;

procedure TFloriaBiDiTest.TestBracketMirroring();
begin
  AssertEquals('Open paren mirrors', Ord(')'), TFloriaBiDi.GetMirroredChar(Ord('(')));
  AssertEquals('Close paren mirrors', Ord('('), TFloriaBiDi.GetMirroredChar(Ord(')')));
  AssertEquals('Open bracket mirrors', Ord(']'), TFloriaBiDi.GetMirroredChar(Ord('[')));
  AssertEquals('Close bracket mirrors', Ord('['), TFloriaBiDi.GetMirroredChar(Ord(']')));
  AssertEquals('Less than mirrors', Ord('>'), TFloriaBiDi.GetMirroredChar(Ord('<')));
  AssertEquals('Greater than mirrors', Ord('<'), TFloriaBiDi.GetMirroredChar(Ord('>')));
  AssertEquals('Letter does not mirror', Ord('A'), TFloriaBiDi.GetMirroredChar(Ord('A')));
end;

procedure TFloriaBiDiTest.TestPureLTR();
var
  runs: TFloriaBiDiRunArray;
begin
  runs := TFloriaBiDi.GetVisualRuns('Floria Toolkit');
  AssertEquals('Run count', 1, Length(runs));
  AssertTrue('Direction is LTR', runs[0].Direction = fbdLTR);
  AssertEquals('Text matches', 'Floria Toolkit', runs[0].Text);
end;

procedure TFloriaBiDiTest.TestPureRTL();
var
  runs: TFloriaBiDiRunArray;
begin
  runs := TFloriaBiDi.GetVisualRuns('مرحبا');
  AssertEquals('Run count', 1, Length(runs));
  AssertTrue('Direction is RTL', runs[0].Direction = fbdRTL);
  AssertEquals('Text matches in logical order', 'مرحبا', runs[0].Text);
end;

procedure TFloriaBiDiTest.TestMixedBiDiRuns();
var
  runs: TFloriaBiDiRunArray;
begin
  runs := TFloriaBiDi.GetVisualRuns('Hello مرحبا world');
  AssertTrue('Multiple runs', Length(runs) >= 3);
  AssertTrue('First run is LTR', runs[0].Direction = fbdLTR);
  AssertTrue('Second run is RTL', runs[1].Direction = fbdRTL);
  AssertTrue('Third run is LTR', runs[2].Direction = fbdLTR);
end;

procedure TFloriaBiDiTest.TestNumbersInRTL();
var
  runs: TFloriaBiDiRunArray;
begin
  // Arabic text with European numbers: "مرحبا 123"
  runs := TFloriaBiDi.GetVisualRuns('مرحبا 123');
  AssertTrue('Has runs', Length(runs) > 0);
  AssertTrue('Has RTL component', TFloriaBiDi.HasRTL('مرحبا 123'));
end;

procedure TFloriaBiDiTest.TestReorderToVisualString();
var
  res: string;
begin
  // LTR stays identical
  res := TFloriaBiDi.ReorderToVisualString('Hello World');
  AssertEquals('LTR visual reorder', 'Hello World', res);

  // Mirrored characters in RTL context
  res := TFloriaBiDi.ReorderToVisualString('(مرحبا)', fbbRTL);
  AssertTrue('Has output', Length(res) > 0);
end;

initialization
  RegisterTest(TFloriaBiDiTest);

end.
