program PathGolden;

// PathGolden
// ==========
// Regenerates src/test/pascal/floria.path.golden.data.pas from the reference
// clipping backend.
//
// Why a generator instead of hand-written expectations:
//   the golden file freezes the behaviour of the vendored Clipper2 engine so
//   the first-party engine can be checked against it *after* Clipper2 is
//   deleted. Generating it from Clipper2 rather than from the native engine is
//   the whole point: data captured from the implementation under test would
//   only assert that it equals itself.
//
// Run this only while the Clipper2 adapter is still present:
//
//   fpc -Fu../../target/units -Fu../../src/test/pascal \
//       -Fu$HOME/.pasbuild/repository/fpgui-framework/2.2.0-SNAPSHOT/x86_64-linux-3.2.3/units \
//       -FE../../target/tools -o../../target/tools/pathgolden pathgolden.pas
//   ../../target/tools/pathgolden > ../../src/test/pascal/floria.path.golden.data.pas
//
// The generated unit is committed, so normal builds never run this.

{$mode objfpc}{$H+}

uses
  SysUtils, Math,
  Floria.Geometry,
  Floria.Errors,
  Floria.Path.Engine,
  Floria.Path.Engine.Native,
  Floria.Path.Corpus;

const
  REFERENCE_ENGINE = 'clipper2';

type
  TGoldenRow = record
    Name        : string;
    Area        : Double;
    ContourCount: Integer;
    Left, Top, Right, Bottom: Double;
  end;

var
  Rows: array of TGoldenRow;

function ResultArea(const APaths: TPathsD): Double;
begin
  Result := Abs(Area(APaths));
end;

procedure RunCase(const ACase: TCorpusCase; out ARow: TGoldenRow);
var
  Res: TPathsD;
  B: TRectD;
begin
  case ACase.Kind of
    ckBoolean:
      if ACase.SelfUnion then
        Res := FloriaPathEngine().UnionSelf(ACase.Subject, ACase.FillRule, 2)
      else
        Res := FloriaPathEngine().BooleanOp(ACase.Op, ACase.Subject, ACase.Clip,
          ACase.FillRule, 2);

    ckOffset:
      Res := FloriaPathEngine().OffsetPaths(ACase.Subject, ACase.Delta,
        ACase.JoinType, ACase.EndType, 2.0, 0.0, 2);

    ckSimplify:
      Res := FloriaPathEngine().SimplifyPaths(ACase.Subject, ACase.Tolerance,
        ACase.Kind <> ckSimplify, 2);
  else
    raise EPathEngineError.Create('unhandled corpus kind');
  end;

  ARow.Name := ACase.Name;
  ARow.Area := ResultArea(Res);
  ARow.ContourCount := Length(Res);

  // A zero-area result has no meaningful bounds, and the reference backend can
  // return a degenerate zero-area contour (for example "A - A"). Recording
  // MaxDouble sentinels or a contour count there would freeze a backend
  // artifact rather than a contract, so normalise it: no area means no
  // geometry, whatever the contour bookkeeping says.
  if (Length(Res) = 0) or (ARow.Area < 1e-6) then
  begin
    ARow.ContourCount := 0;
    ARow.Left := 0; ARow.Top := 0; ARow.Right := 0; ARow.Bottom := 0;
  end
  else
  begin
    B := GetBounds(Res);
    ARow.Left := B.Left;
    ARow.Top := B.Top;
    ARow.Right := B.Right;
    ARow.Bottom := B.Bottom;
  end;
end;

function FormatDouble(AValue: Double): string;
begin
  if IsNaN(AValue) or IsInfinite(AValue) then
    Exit('0.0');
  // Six decimals is far finer than any tolerance the tests use, and keeps the
  // file readable and diff-stable.
  Result := FormatFloat('0.0######', AValue);
  if Pos('.', Result) = 0 then
    Result := Result + '.0';
end;

function PascalQuote(const AValue: string): string;
begin
  Result := '''' + StringReplace(AValue, '''', '''''', [rfReplaceAll]) + '''';
end;

var
  I: Integer;
  C: TCorpusCase;
  Row: TGoldenRow;
begin
  if not FloriaPathEngineAvailable() then
  begin
    WriteLn(ErrOutput, 'error: no path engine registered');
    Halt(1);
  end;

  try
    UseFloriaPathEngine(REFERENCE_ENGINE);
  except
    on E: Exception do
    begin
      WriteLn(ErrOutput, 'error: reference engine "', REFERENCE_ENGINE,
        '" unavailable: ', E.Message);
      Halt(1);
    end;
  end;

  SetLength(Rows, CorpusCount());
  for I := 0 to CorpusCount() - 1 do
  begin
    C := CorpusCase(I);
    RunCase(C, Row);
    Rows[I] := Row;
    WriteLn(ErrOutput, 'captured ', Row.Name, ' area=', FormatDouble(Row.Area));
  end;

  // Emit the unit on stdout so the caller can redirect it into place.
  WriteLn('unit Floria.Path.Golden.Data;');
  WriteLn;
  WriteLn('// Floria.Path.Golden.Data');
  WriteLn('// =======================');
  WriteLn('// GENERATED FILE - do not edit by hand.');
  WriteLn('//');
  WriteLn('// Frozen expected results for the path-engine regression corpus, captured');
  WriteLn('// from the reference implementation (', REFERENCE_ENGINE, ') before it was removed.');
  WriteLn('// Regenerate with tools/pathgolden while a reference backend still exists.');
  WriteLn('//');
  WriteLn('// Each row records the total absolute area and the bounds of the result.');
  WriteLn('// Area is the primary invariant. Bounds are only meaningful when area is');
  WriteLn('// non-zero, and catch translated or clipped geometry that happens to');
  WriteLn('// preserve area.');
  WriteLn('//');
  WriteLn('// ContourCount is recorded for diagnostics but is NOT asserted: backends');
  WriteLn('// may legitimately differ in how they split zero-area remnants, and the');
  WriteLn('// reference engine sometimes returns a degenerate contour where a');
  WriteLn('// first-party engine returns none.');
  WriteLn;
  WriteLn('{$mode objfpc}{$H+}');
  WriteLn;
  WriteLn('interface');
  WriteLn;
  WriteLn('type');
  WriteLn('  TGoldenResult = record');
  WriteLn('    Name        : string;');
  WriteLn('    Area        : Double;');
  WriteLn('    ContourCount: Integer;');
  WriteLn('    Left        : Double;');
  WriteLn('    Top         : Double;');
  WriteLn('    Right       : Double;');
  WriteLn('    Bottom      : Double;');
  WriteLn('  end;');
  WriteLn;
  WriteLn('const');
  WriteLn('  GOLDEN_COUNT = ', Length(Rows), ';');
  WriteLn;
  WriteLn('// Returns the recorded result for AName. Raises if the name is unknown, so a');
  WriteLn('// renamed or removed corpus case fails loudly instead of silently skipping.');
  WriteLn('function GoldenResult(const AName: string): TGoldenResult;');
  WriteLn;
  WriteLn('implementation');
  WriteLn;
  WriteLn('uses');
  WriteLn('  SysUtils,');
  WriteLn('  Floria.Path.Engine;');
  WriteLn;
  WriteLn('const');
  WriteLn('  GOLDEN: array[0..GOLDEN_COUNT - 1] of TGoldenResult = (');
  for I := 0 to High(Rows) do
  begin
    Write('    (Name: ', PascalQuote(Rows[I].Name));
    Write('; Area: ', FormatDouble(Rows[I].Area));
    Write('; ContourCount: ', Rows[I].ContourCount);
    Write('; Left: ', FormatDouble(Rows[I].Left));
    Write('; Top: ', FormatDouble(Rows[I].Top));
    Write('; Right: ', FormatDouble(Rows[I].Right));
    Write('; Bottom: ', FormatDouble(Rows[I].Bottom));
    if I = High(Rows) then
      WriteLn(')')
    else
      WriteLn('),');
  end;
  WriteLn('  );');
  WriteLn;
  WriteLn('function GoldenResult(const AName: string): TGoldenResult;');
  WriteLn('var');
  WriteLn('  I: Integer;');
  WriteLn('begin');
  WriteLn('  for I := 0 to High(GOLDEN) do');
  WriteLn('    if GOLDEN[I].Name = AName then');
  WriteLn('      Exit(GOLDEN[I]);');
  WriteLn;
  WriteLn('  raise EPathEngineError.CreateFmt(''no golden result recorded for "%s"'', [AName]);');
  WriteLn('end;');
  WriteLn;
  WriteLn('end.');
end.
