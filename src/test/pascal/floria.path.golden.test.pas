unit Floria.Path.Golden.Test;

// Floria.Path.Golden.Test
// =======================
// Runs the whole path-engine corpus against frozen expected results.
//
// The expectations in Floria.Path.Golden.Data were captured from the reference
// implementation before it was removed. That matters: a test suite that only
// compared the engine against itself would pass through any regression. These
// assertions keep their teeth after the reference engine is gone.
//
// What is asserted:
//   - total absolute area, within each case's tolerance
//   - bounds, but only when the result has non-zero area (an empty result has
//     no meaningful bounds)
//
// What is deliberately not asserted:
//   - contour count. Backends legitimately differ in how they split zero-area
//     remnants, and freezing that would pin an artifact rather than a
//     contract.
//   - exact vertex positions. Arc tessellation step counts differ by a segment
//     or two between implementations; area and bounds absorb that.

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, fpcunit, testregistry,
  Floria.Geometry,
  Floria.Errors,
  Floria.Path.Engine,
  Floria.Path.Corpus,
  Floria.Path.Golden.Data;

type
  TFloriaPathGoldenTest = class(TTestCase)
  private
    FSaved: TFloriaPathEngine;
    procedure RunAndCompare(AIndex: Integer);
  protected
    procedure SetUp(); override;
    procedure TearDown(); override;
  published
    procedure TestGoldenDataIsWellFormed();
    procedure TestCorpusAndGoldenAgreeOnNames();
    procedure TestCorpusAgainstGolden();
  end;

implementation

procedure TFloriaPathGoldenTest.SetUp();
begin
  FSaved := FloriaPathEngine();
  UseFloriaPathEngine('native');
end;

procedure TFloriaPathGoldenTest.TearDown();
begin
  if FSaved <> nil then
    SetFloriaPathEngine(FSaved, False);
end;

function RunCorpusCase(const ACase: TCorpusCase): TPathsD;
begin
  case ACase.Kind of
    ckBoolean:
      if ACase.SelfUnion then
        Result := FloriaPathEngine().UnionSelf(ACase.Subject, ACase.FillRule, 2)
      else
        Result := FloriaPathEngine().BooleanOp(ACase.Op, ACase.Subject,
          ACase.Clip, ACase.FillRule, 2);

    ckOffset:
      Result := FloriaPathEngine().OffsetPaths(ACase.Subject, ACase.Delta,
        ACase.JoinType, ACase.EndType, 2.0, 0.0, 2);

    ckSimplify:
      // Corpus simplify cases exercise both open and closed inputs; the
      // "open-line" case is the only open one.
      Result := FloriaPathEngine().SimplifyPaths(ACase.Subject,
        ACase.Tolerance, Pos('open', ACase.Name) = 0, 2);
  else
    raise EPathEngineError.Create('unhandled corpus kind');
  end;
end;

procedure TFloriaPathGoldenTest.RunAndCompare(AIndex: Integer);
var
  C: TCorpusCase;
  Expected: TGoldenResult;
  Res: TPathsD;
  ActualArea: Double;
  B: TRectD;
begin
  C := CorpusCase(AIndex);
  Expected := GoldenResult(C.Name);
  Res := RunCorpusCase(C);
  ActualArea := Abs(Area(Res));

  AssertTrue(C.Name + ': area expected ' + FormatFloat('0.####', Expected.Area) +
    ' but was ' + FormatFloat('0.####', ActualArea),
    Abs(ActualArea - Expected.Area) <= C.Tolerance);

  // Bounds are only meaningful when there is geometry.
  if Expected.Area > 1e-6 then
  begin
    AssertTrue(C.Name + ': result is not empty', Length(Res) > 0);
    B := GetBounds(Res);
    AssertTrue(C.Name + ': bounds left expected ' +
      FormatFloat('0.####', Expected.Left) + ' but was ' + FormatFloat('0.####', B.Left),
      Abs(B.Left - Expected.Left) <= Max(C.Tolerance, 0.5));
    AssertTrue(C.Name + ': bounds top expected ' +
      FormatFloat('0.####', Expected.Top) + ' but was ' + FormatFloat('0.####', B.Top),
      Abs(B.Top - Expected.Top) <= Max(C.Tolerance, 0.5));
    AssertTrue(C.Name + ': bounds right expected ' +
      FormatFloat('0.####', Expected.Right) + ' but was ' + FormatFloat('0.####', B.Right),
      Abs(B.Right - Expected.Right) <= Max(C.Tolerance, 0.5));
    AssertTrue(C.Name + ': bounds bottom expected ' +
      FormatFloat('0.####', Expected.Bottom) + ' but was ' + FormatFloat('0.####', B.Bottom),
      Abs(B.Bottom - Expected.Bottom) <= Max(C.Tolerance, 0.5));
  end
  else
    AssertTrue(C.Name + ': expected no area but got ' +
      FormatFloat('0.####', ActualArea), ActualArea <= C.Tolerance + 1e-6);
end;

procedure TFloriaPathGoldenTest.TestGoldenDataIsWellFormed();
var
  I: Integer;
  R: TGoldenResult;
begin
  AssertTrue('golden data is not empty', GOLDEN_COUNT > 0);

  for I := 0 to GOLDEN_COUNT - 1 do
  begin
    R := GoldenResult(CorpusCase(I).Name);
    AssertTrue('row ' + IntToStr(I) + ' has a name', R.Name <> '');
    AssertTrue('row ' + IntToStr(I) + ' area is finite', not IsNaN(R.Area));
    AssertTrue('row ' + IntToStr(I) + ' area is non-negative', R.Area >= 0);
  end;
end;

procedure TFloriaPathGoldenTest.TestCorpusAndGoldenAgreeOnNames();
var
  I: Integer;
  C: TCorpusCase;
begin
  // Every corpus case must have a recorded result. This catches a case that
  // was added or renamed without regenerating the golden file, which would
  // otherwise silently reduce coverage.
  AssertEquals('corpus and golden sizes match', CorpusCount(), GOLDEN_COUNT);

  for I := 0 to CorpusCount() - 1 do
  begin
    C := CorpusCase(I);
    AssertEquals('golden row ' + IntToStr(I) + ' matches corpus name',
      C.Name, GoldenResult(C.Name).Name);
  end;
end;

procedure TFloriaPathGoldenTest.TestCorpusAgainstGolden();
var
  I: Integer;
begin
  for I := 0 to CorpusCount() - 1 do
    RunAndCompare(I);
end;

initialization
  RegisterTest(TFloriaPathGoldenTest);

end.
