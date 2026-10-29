program PathBench;

// PathBench
// =========
// Measures the first-party path engine: booleans, offsetting, and
// simplification, across a range of geometry sizes.
//
// Purpose
// -------
// The engine was written for correctness first. The boolean arrangement splits
// every edge against every other, classifies every resulting piece, then chains
// the boundary by scanning for successors — all of which are quadratic in the
// number of edges. This tool measures whether that is actually a problem, and
// where, rather than leaving it as an assumption.
//
// Method
// ------
// Each case is run for REPEATS passes and the total is divided, after a warm-up
// pass that is discarded. Warm-up matters: the first call allocates and grows
// dynamic arrays, which would otherwise be charged to the smallest size.
//
// Scaling is reported as the ratio between consecutive sizes. A quadratic
// operation roughly quadruples when the vertex count doubles; a linear one
// roughly doubles. That comparison is the useful output, not the absolute
// milliseconds, which depend on the machine.
//
// Build and run (from the repository root):
//
//   fpc -Fu"$PWD/target/units" \
//       -Fu"$HOME/.pasbuild/repository/fpgui-framework/2.2.0-SNAPSHOT/x86_64-linux-3.2.3/units" \
//       -FEtarget/tools -O2 -o"$PWD/target/tools/pathbench" \
//       tools/pathbench/pathbench.pas
//   ./target/tools/pathbench

{$mode objfpc}{$H+}

uses
  SysUtils, Math,
  Floria.Geometry,
  Floria.Path.Engine,
  Floria.Path.Engine.Native;

const
  // Enough passes that millisecond clock granularity is not the dominant
  // error term for the smallest sizes.
  REPEATS = 5;

  SIZES: array[0..5] of Integer = (50, 100, 200, 400, 800, 1600);

type
  TBenchProc = procedure();

var
  // Inputs for the case currently being measured.
  GSubject: TPathsD;
  GClip: TPathsD;
  GResult: TPathsD;
  GKeepAlive: Double;

// ---------------------------------------------------------------------------
// Geometry construction
// ---------------------------------------------------------------------------

// A regular ASides-gon, which is the standard stand-in for "a complex path".
function CirclePath(const ACX, ACY, ARadius: Double; ASides: Integer): TPathD;
var
  I: Integer;
  Angle: Double;
begin
  SetLength(Result, ASides);
  for I := 0 to ASides - 1 do
  begin
    Angle := 2 * Pi * I / ASides;
    Result[I] := PointD(ACX + ARadius * Cos(Angle), ACY + ARadius * Sin(Angle));
  end;
end;

// Two overlapping circles: a realistic boolean workload where the result is a
// single merged outline covering a good fraction of every input edge.
procedure BuildOverlappingCircles(ASides: Integer);
begin
  SetLength(GSubject, 1);
  SetLength(GClip, 1);
  GSubject[0] := CirclePath(0, 0, 100, ASides);
  GClip[0] := CirclePath(80, 0, 100, ASides);
end;

// A single circle, for offsetting and simplification.
procedure BuildSingleCircle(ASides: Integer);
begin
  SetLength(GSubject, 1);
  GSubject[0] := CirclePath(0, 0, 100, ASides);
  SetLength(GClip, 0);
end;

// Concentric rings: a stress case where many edges lie close together and the
// result has genuine holes rather than one merged outline.
procedure BuildConcentricRings(ASides: Integer);
var
  I, Ring: Integer;
  Radius: Double;
begin
  Ring := ASides div 50;
  if Ring < 2 then
    Ring := 2;
  SetLength(GSubject, Ring);
  for I := 0 to Ring - 1 do
  begin
    Radius := 100 - I * (80 / Ring);
    GSubject[I] := CirclePath(0, 0, Radius, ASides);
  end;
  SetLength(GClip, 0);
end;

// ---------------------------------------------------------------------------
// Timing
// ---------------------------------------------------------------------------

function NowMs(): Int64;
begin
  Result := GetTickCount64();
end;

// Runs AProc REPEATS times and returns the mean duration in milliseconds.
// One warm-up pass is executed first and discarded.
function Measure(AProc: TBenchProc): Double;
var
  StartMs, EndMs: Int64;
  I: Integer;
begin
  AProc();

  StartMs := NowMs();
  for I := 1 to REPEATS do
    AProc();
  EndMs := NowMs();

  Result := (EndMs - StartMs) / REPEATS;
end;

// ---------------------------------------------------------------------------
// Cases
// ---------------------------------------------------------------------------

procedure BenchUnion();
begin
  GResult := FloriaPathEngine().BooleanOp(pboUnion, GSubject, GClip, frNonZero, 2);
end;

procedure BenchDifference();
begin
  GResult := FloriaPathEngine().BooleanOp(pboDifference, GSubject, GClip, frNonZero, 2);
end;

procedure BenchIntersect();
begin
  GResult := FloriaPathEngine().BooleanOp(pboIntersect, GSubject, GClip, frNonZero, 2);
end;

procedure BenchXor();
begin
  GResult := FloriaPathEngine().BooleanOp(pboXor, GSubject, GClip, frNonZero, 2);
end;

procedure BenchSelfUnion();
begin
  GResult := FloriaPathEngine().UnionSelf(GSubject, frNonZero, 2);
end;

procedure BenchOffsetOut();
begin
  GResult := FloriaPathEngine().OffsetPaths(GSubject, 10.0, pjtRound, petPolygon, 2.0, 0.0, 2);
end;

procedure BenchOffsetIn();
begin
  GResult := FloriaPathEngine().OffsetPaths(GSubject, -5.0, pjtRound, petPolygon, 2.0, 0.0, 2);
end;

procedure BenchSimplify();
begin
  GResult := FloriaPathEngine().SimplifyPaths(GSubject, 0.5, True, 2);
end;

// ---------------------------------------------------------------------------
// Reporting
// ---------------------------------------------------------------------------

type
  TBuildProc = procedure(ASides: Integer);

  TCase = record
    Name : string;
    Build: TBuildProc;
    Run  : TBenchProc;
  end;

function ScalingNote(APrevious, ACurrent: Double): string;
var
  Ratio: Double;
begin
  if APrevious <= 0 then
    Exit('   -   ');
  Ratio := ACurrent / APrevious;
  Result := FormatFloat('0.0"x"', Ratio);
end;

procedure RunTable(const ACase: TCase);
var
  I, J: Integer;
  Times: array[0..5] of Double;
  Prev, Worst: Double;
  AllZero: Boolean;
  VertexCount: Integer;
begin
  WriteLn;
  WriteLn(ACase.Name);
  WriteLn(StringOfChar('-', Length(ACase.Name)));
  WriteLn(Format('  %6s  %8s  %12s  %8s  %10s',
    ['sides', 'verts', 'mean ms', 'scaling', 'area']));

  AllZero := True;
  for I := 0 to High(SIZES) do
  begin
    ACase.Build(SIZES[I]);
    Times[I] := Measure(ACase.Run);

    // Keep a reference to the result so the optimiser cannot elide the call.
    GKeepAlive := GKeepAlive + Abs(Area(GResult));
    if Abs(Area(GResult)) > 1e-9 then
      AllZero := False;

    VertexCount := 0;
    for J := 0 to High(GSubject) do
      Inc(VertexCount, Length(GSubject[J]));
    for J := 0 to High(GClip) do
      Inc(VertexCount, Length(GClip[J]));

    if I = 0 then
      WriteLn(Format('  %6d  %8d  %12.2f  %8s  %10.1f',
        [SIZES[I], VertexCount, Times[I], '   -   ', Abs(Area(GResult))]))
    else
      WriteLn(Format('  %6d  %8d  %12.2f  %8s  %10.1f',
        [SIZES[I], VertexCount, Times[I], ScalingNote(Times[I - 1], Times[I]),
         Abs(Area(GResult))]));
  end;

  // A case that produces nothing is measuring an empty result, not the
  // operation. Say so rather than quietly reporting fast numbers.
  if AllZero then
    WriteLn('  WARNING: every size produced zero area; this case is not measuring work.');

  Prev := Times[0];
  Worst := 0;
  for I := 1 to High(SIZES) do
  begin
    if (Prev > 0) and ((Times[I] / Prev) > Worst) then
      Worst := Times[I] / Prev;
    Prev := Times[I];
  end;
  WriteLn(Format('  peak scaling across a 2x size step: %.1fx', [Worst]));
  if (Times[0] > 0) and (Times[High(SIZES)] > 0) then
    WriteLn(Format('  overall: %.1f ms -> %.1f ms', [Times[0], Times[High(SIZES)]]));
end;

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

var
  C: TCase;
begin
  if not FloriaPathEngineAvailable() then
  begin
    WriteLn(ErrOutput, 'error: no path engine registered');
    Halt(1);
  end;

  WriteLn('Path engine benchmark');
  WriteLn('=====================');
  WriteLn('engine   : ', FloriaPathEngine().Name());
  WriteLn('repeats  : ', REPEATS, ' passes per size (warm-up discarded)');
  WriteLn('clock    : GetTickCount64, millisecond resolution');
  WriteLn;
  WriteLn('Scaling near 4.0x per doubling indicates quadratic cost; near 2.0x');
  WriteLn('indicates linear. Absolute milliseconds are machine-specific.');

  C.Name := 'Boolean union (two overlapping circles)';
  C.Build := @BuildOverlappingCircles;
  C.Run := @BenchUnion;
  RunTable(C);

  C.Name := 'Boolean difference (two overlapping circles)';
  C.Build := @BuildOverlappingCircles;
  C.Run := @BenchDifference;
  RunTable(C);

  C.Name := 'Boolean intersect (two overlapping circles)';
  C.Build := @BuildOverlappingCircles;
  C.Run := @BenchIntersect;
  RunTable(C);

  C.Name := 'Boolean xor (two overlapping circles)';
  C.Build := @BuildOverlappingCircles;
  C.Run := @BenchXor;
  RunTable(C);

  C.Name := 'Boolean self-union (concentric rings)';
  C.Build := @BuildConcentricRings;
  C.Run := @BenchSelfUnion;
  RunTable(C);

  C.Name := 'Offset +10 round joins (single circle)';
  C.Build := @BuildSingleCircle;
  C.Run := @BenchOffsetOut;
  RunTable(C);

  C.Name := 'Offset -5 round joins (single circle)';
  C.Build := @BuildSingleCircle;
  C.Run := @BenchOffsetIn;
  RunTable(C);

  C.Name := 'Simplify, tolerance 0.5 (single circle)';
  C.Build := @BuildSingleCircle;
  C.Run := @BenchSimplify;
  RunTable(C);

  WriteLn;
  WriteLn(Format('checksum: %.1f', [GKeepAlive]));
end.
