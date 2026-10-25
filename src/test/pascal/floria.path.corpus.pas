unit Floria.Path.Corpus;

// Floria.Path.Corpus
// ==================
// Shared definition of the path-engine regression corpus.
//
// Both the golden-data generator (tools/pathgolden) and the golden tests build
// their inputs from this unit, so the two can never drift apart. Each case is
// identified by a stable name; the generated golden file keys expected results
// by that same name.
//
// Inputs are built by functions rather than declared as constants because the
// records contain dynamic arrays, which cannot appear in a typed constant.

{$mode objfpc}{$H+}

interface

uses
  SysUtils,
  Floria.Geometry,
  Floria.Path.Engine;

type
  TCorpusKind = (ckBoolean, ckOffset, ckSimplify);

  TCorpusCase = record
    Name      : string;
    Kind      : TCorpusKind;
    Op        : TPathBooleanOp;
    FillRule  : TFillRule;
    JoinType  : TPathJoinType;
    EndType   : TPathEndType;
    Delta     : Double;
    Tolerance : Double;
    SelfUnion : Boolean;
    Subject   : TPathsD;
    Clip      : TPathsD;
  end;

// Number of cases in the corpus.
function CorpusCount(): Integer;

// Case AIndex, with its inputs already built. Raises on an out-of-range index.
function CorpusCase(AIndex: Integer): TCorpusCase;

implementation

// ---------------------------------------------------------------------------
// Input builders
// ---------------------------------------------------------------------------

function Square(AX1, AY1, AX2, AY2: Double): TPathsD;
begin
  SetLength(Result, 1);
  Result[0] := RectD(AX1, AY1, AX2, AY2).AsPath();
end;

function Triangle(): TPathsD;
begin
  SetLength(Result, 1);
  SetLength(Result[0], 3);
  Result[0][0] := PointD(0, 0);
  Result[0][1] := PointD(100, 0);
  Result[0][2] := PointD(50, 100);
end;

function HorizontalLine(): TPathsD;
begin
  SetLength(Result, 1);
  SetLength(Result[0], 2);
  Result[0][0] := PointD(0, 0);
  Result[0][1] := PointD(100, 0);
end;

// A rectangle whose top and bottom edges carry redundant collinear vertices.
function CollinearRect(): TPathsD;
begin
  SetLength(Result, 1);
  SetLength(Result[0], 9);
  Result[0][0] := PointD(0, 0);
  Result[0][1] := PointD(25, 0);
  Result[0][2] := PointD(50, 0);
  Result[0][3] := PointD(75, 0);
  Result[0][4] := PointD(100, 0);
  Result[0][5] := PointD(100, 50);
  Result[0][6] := PointD(50, 50);
  Result[0][7] := PointD(0, 50);
  Result[0][8] := PointD(0, 0);
end;

function OpenPolyline(): TPathsD;
begin
  SetLength(Result, 1);
  SetLength(Result[0], 5);
  Result[0][0] := PointD(0, 0);
  Result[0][1] := PointD(10, 0);
  Result[0][2] := PointD(20, 0);
  Result[0][3] := PointD(30, 0);
  Result[0][4] := PointD(40, 0);
end;

// ---------------------------------------------------------------------------
// Case constructors
// ---------------------------------------------------------------------------

function BooleanCase(const AName: string; AOp: TPathBooleanOp;
  const ASubject, AClip: TPathsD; ARule: TFillRule = frNonZero): TCorpusCase;
begin
  Result := Default(TCorpusCase);
  Result.Name := AName;
  Result.Kind := ckBoolean;
  Result.Op := AOp;
  Result.FillRule := ARule;
  Result.Tolerance := 2.0;
  Result.SelfUnion := False;
  Result.Subject := ASubject;
  Result.Clip := AClip;
end;

function SelfUnionCase(const AName: string;
  const ASubject: TPathsD; ARule: TFillRule): TCorpusCase;
begin
  Result := Default(TCorpusCase);
  Result.Name := AName;
  Result.Kind := ckBoolean;
  Result.Op := pboUnion;
  Result.FillRule := ARule;
  Result.Tolerance := 2.0;
  Result.SelfUnion := True;
  Result.Subject := ASubject;
end;

function OffsetCase(const AName: string; const APaths: TPathsD;
  ADelta: Double; AJoin: TPathJoinType; AEnd: TPathEndType;
  ATolerance: Double): TCorpusCase;
begin
  Result := Default(TCorpusCase);
  Result.Name := AName;
  Result.Kind := ckOffset;
  Result.Delta := ADelta;
  Result.JoinType := AJoin;
  Result.EndType := AEnd;
  Result.Tolerance := ATolerance;
  Result.Subject := APaths;
end;

function SimplifyCase(const AName: string; const APaths: TPathsD;
  ATolerance: Double): TCorpusCase;
begin
  Result := Default(TCorpusCase);
  Result.Name := AName;
  Result.Kind := ckSimplify;
  Result.Tolerance := ATolerance;
  Result.Subject := APaths;
end;

// ---------------------------------------------------------------------------
// Corpus
// ---------------------------------------------------------------------------

const
  CORPUS_SIZE = 33;

function CorpusCount(): Integer;
begin
  Result := CORPUS_SIZE;
end;

function CorpusCase(AIndex: Integer): TCorpusCase;
var
  NestedDonut: TPathsD;
begin
  case AIndex of
    // --- Boolean operations -------------------------------------------------
    0: Result := BooleanCase('bool.union.overlap', pboUnion,
         Square(0, 0, 100, 100), Square(50, 0, 150, 100));
    1: Result := BooleanCase('bool.difference.overlap', pboDifference,
         Square(0, 0, 100, 100), Square(50, 0, 150, 100));
    2: Result := BooleanCase('bool.intersect.overlap', pboIntersect,
         Square(0, 0, 100, 100), Square(50, 0, 150, 100));
    3: Result := BooleanCase('bool.xor.overlap', pboXor,
         Square(0, 0, 100, 100), Square(50, 0, 150, 100));

    4: Result := BooleanCase('bool.union.disjoint', pboUnion,
         Square(0, 0, 100, 100), Square(200, 0, 300, 100));
    5: Result := BooleanCase('bool.intersect.disjoint', pboIntersect,
         Square(0, 0, 100, 100), Square(200, 0, 300, 100));

    6: Result := BooleanCase('bool.union.nested', pboUnion,
         Square(0, 0, 100, 100), Square(25, 25, 75, 75));
    7: Result := BooleanCase('bool.difference.nested', pboDifference,
         Square(0, 0, 100, 100), Square(25, 25, 75, 75));
    8: Result := BooleanCase('bool.intersect.nested', pboIntersect,
         Square(0, 0, 100, 100), Square(25, 25, 75, 75));

    9: Result := BooleanCase('bool.union.identical', pboUnion,
         Square(0, 0, 100, 100), Square(0, 0, 100, 100));
    10: Result := BooleanCase('bool.intersect.identical', pboIntersect,
         Square(0, 0, 100, 100), Square(0, 0, 100, 100));
    11: Result := BooleanCase('bool.difference.identical', pboDifference,
         Square(0, 0, 100, 100), Square(0, 0, 100, 100));

    12: Result := BooleanCase('bool.union.triangle-square', pboUnion,
         Triangle(), Square(0, 0, 100, 50));
    13: Result := BooleanCase('bool.intersect.triangle-square', pboIntersect,
         Triangle(), Square(0, 0, 100, 50));
    14: Result := BooleanCase('bool.difference.triangle-square', pboDifference,
         Triangle(), Square(0, 0, 100, 50));
    15: Result := BooleanCase('bool.xor.triangle-square', pboXor,
         Triangle(), Square(0, 0, 100, 50));

    16: Result := BooleanCase('bool.union.collinear', pboUnion,
         Square(0, 0, 100, 100), Square(100, 0, 200, 100));

    17: Result := BooleanCase('bool.union.corner-touch', pboUnion,
         Square(0, 0, 100, 100), Square(100, 100, 200, 200));
    18: Result := BooleanCase('bool.intersect.corner-touch', pboIntersect,
         Square(0, 0, 100, 100), Square(100, 100, 200, 200));

    19: begin
      SetLength(NestedDonut, 2);
      NestedDonut[0] := RectD(0, 0, 100, 100).AsPath();
      NestedDonut[1] := RectD(25, 25, 75, 75).AsPath();
      Result := SelfUnionCase('bool.selfunion.nonzero', NestedDonut, frNonZero);
    end;

    20: begin
      SetLength(NestedDonut, 2);
      NestedDonut[0] := RectD(0, 0, 100, 100).AsPath();
      NestedDonut[1] := RectD(25, 25, 75, 75).AsPath();
      Result := SelfUnionCase('bool.selfunion.evenodd', NestedDonut, frEvenOdd);
    end;

    // --- Offsetting ---------------------------------------------------------
    21: Result := OffsetCase('offset.inflate.miter',
          Square(0, 0, 100, 100), 5.0, pjtMiter, petPolygon, 1.0);
    22: Result := OffsetCase('offset.inflate.bevel',
          Square(0, 0, 100, 100), 5.0, pjtBevel, petPolygon, 1.0);
    23: Result := OffsetCase('offset.inflate.square',
          Square(0, 0, 100, 100), 5.0, pjtSquare, petPolygon, 1.0);
    24: Result := OffsetCase('offset.inflate.round',
          Square(0, 0, 100, 100), 5.0, pjtRound, petPolygon, 5.0);

    25: Result := OffsetCase('offset.deflate.miter',
          Square(0, 0, 100, 100), -10.0, pjtMiter, petPolygon, 1.0);
    26: Result := OffsetCase('offset.deflate.deep',
          Square(0, 0, 100, 100), -25.0, pjtMiter, petPolygon, 1.0);
    27: Result := OffsetCase('offset.deflate.collapse',
          Square(0, 0, 100, 100), -60.0, pjtMiter, petPolygon, 0.0);

    28: Result := OffsetCase('offset.stroke.butt',
          HorizontalLine(), 5.0, pjtMiter, petButt, 1.0);
    29: Result := OffsetCase('offset.stroke.square',
          HorizontalLine(), 5.0, pjtMiter, petSquare, 1.0);
    30: Result := OffsetCase('offset.stroke.round',
          HorizontalLine(), 5.0, pjtRound, petRound, 5.0);

    // --- Simplification -----------------------------------------------------
    31: Result := SimplifyCase('simplify.closed-collinear',
          CollinearRect(), 0.5);
    32: Result := SimplifyCase('simplify.open-line',
          OpenPolyline(), 0.5);

  else
    raise EPathEngineError.CreateFmt('corpus index out of range: %d', [AIndex]);
  end;
end;

end.
