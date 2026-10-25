unit Floria.Path.Engine.Boolean;

// Floria.Path.Engine.Boolean
// ==========================
// First-party boolean operations on polygon sets: union, difference,
// intersection, and exclusive-or, under all four fill rules.
//
// Strategy
// --------
// This is a planar-arrangement approach rather than a Vatti-style sweep:
//
//   1. Snap every input to a fixed integer grid (10^precision).
//   2. Split every edge at each intersection with any other edge, so the
//      resulting segments never cross except at shared endpoints.
//   3. For each candidate segment, sample a point just off each side and
//      evaluate the fill rule of the original subject and clip contours
//      there. The segment is part of the result boundary only when the
//      "inside" verdict differs across it.
//   4. Keep boundary segments oriented with the interior on their left, then
//      chain them into closed contours.
//
// Classifying against the *original* contours (not the split ones) keeps the
// winding computation exact and independent of the splitting step. The only
// approximation is the perpendicular sampling distance, which is half a grid
// unit — well below the resolution the grid already imposes.
//
// Complexity is O(n^2) in the edge count for the intersection pass. That is
// deliberate: it is simple enough to verify, and adequate for UI-scale paths.
// A sweep-line broadphase is the obvious next optimisation if profiling
// demands it.

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Math,
  Floria.Geometry,
  Floria.Errors,
  Floria.Path.Engine;

// Applies AOp to ASubject and AClip. Returns freshly allocated geometry owned
// by the caller. Never returns a partially computed result.
function FloriaBooleanOp(AOp: TPathBooleanOp;
  const ASubject, AClip: TPathsD;
  AFillRule: TFillRule = frNonZero;
  APrecision: Integer = 2): TPathsD;

// Normalises a path set: resolves self-intersections and applies the fill
// rule. This is what a self-union does.
function FloriaNormalizePaths(const APaths: TPathsD;
  AFillRule: TFillRule = frNonZero;
  APrecision: Integer = 2): TPathsD;

const
  // Perpendicular sampling distance, in grid units. Inputs live on an integer
  // grid, so any distinct edges are at least one unit apart; half a unit keeps
  // the sample strictly inside the thinner of two adjacent regions.
  BOOLEAN_SAMPLE_OFFSET = 0.5;

  MAX_PATH_PRECISION = 8;
  MAX_PATH_COORD = 1000000000;

implementation

type
  TGridPt = record
    X, Y: Int64;
  end;

  TGridPath  = array of TGridPt;
  TGridPaths = array of TGridPath;

  TSegment = record
    A, B: TGridPt;
  end;

  TSegmentArray = array of TSegment;

  TPointArray = array of TGridPt;

// ---------------------------------------------------------------------------
// Grid conversion
// ---------------------------------------------------------------------------

procedure ValidatePrecision(APrecision: Integer);
begin
  if (APrecision < 0) or (APrecision > MAX_PATH_PRECISION) then
    raise EPathEngineError.CreateFmt('precision out of range: %d', [APrecision]);
end;

function ScaleToGrid(const APaths: TPathsD; AScale: Double): TGridPaths;
var
  I, J: Integer;
  V: Double;
begin
  SetLength(Result, Length(APaths));
  for I := 0 to High(APaths) do
  begin
    SetLength(Result[I], Length(APaths[I]));
    for J := 0 to High(APaths[I]) do
    begin
      V := APaths[I][J].X * AScale;
      if (V > MAX_PATH_COORD) or (V < -MAX_PATH_COORD) then
        raise EPathEngineError.CreateFmt(
          'coordinate out of range after scaling: %f', [APaths[I][J].X]);
      Result[I][J].X := Round(V);

      V := APaths[I][J].Y * AScale;
      if (V > MAX_PATH_COORD) or (V < -MAX_PATH_COORD) then
        raise EPathEngineError.CreateFmt(
          'coordinate out of range after scaling: %f', [APaths[I][J].Y]);
      Result[I][J].Y := Round(V);
    end;
  end;
end;

function UnscaleFromGrid(const APaths: TGridPaths; AInvScale: Double): TPathsD;
var
  I, J: Integer;
begin
  SetLength(Result, Length(APaths));
  for I := 0 to High(APaths) do
  begin
    SetLength(Result[I], Length(APaths[I]));
    for J := 0 to High(APaths[I]) do
    begin
      Result[I][J].X := APaths[I][J].X * AInvScale;
      Result[I][J].Y := APaths[I][J].Y * AInvScale;
    end;
  end;
end;

// Drops consecutive duplicates, including a duplicate closing point. A closing
// point is implicit, so keeping it would create a zero-length edge.
function CleanGridPath(const APath: TGridPath): TGridPath;
var
  I, Count: Integer;
begin
  SetLength(Result, Length(APath));
  Count := 0;
  for I := 0 to High(APath) do
  begin
    if (Count > 0) and
       (Result[Count - 1].X = APath[I].X) and
       (Result[Count - 1].Y = APath[I].Y) then
      Continue;
    Result[Count] := APath[I];
    Inc(Count);
  end;

  // Drop a closing point identical to the start.
  if (Count > 1) and
     (Result[Count - 1].X = Result[0].X) and
     (Result[Count - 1].Y = Result[0].Y) then
    Dec(Count);

  SetLength(Result, Count);
end;

function CleanGridPaths(const APaths: TGridPaths): TGridPaths;
var
  I, Count: Integer;
begin
  SetLength(Result, Length(APaths));
  Count := 0;
  for I := 0 to High(APaths) do
  begin
    Result[Count] := CleanGridPath(APaths[I]);
    if Length(Result[Count]) >= 3 then
      Inc(Count);
  end;
  SetLength(Result, Count);
end;

// ---------------------------------------------------------------------------
// Winding and crossing counts
// ---------------------------------------------------------------------------

function IsLeft(const A, B, P: TGridPt): Double;
begin
  Result := (B.X - A.X) * (P.Y - A.Y) - (P.X - A.X) * (B.Y - A.Y);
end;

// Accumulates winding number and ray-crossing count of APt over every contour.
// APt is expected to lie strictly off any edge.
procedure WindingOf(const APaths: TGridPaths; const APt: TGridPt;
  out AWinding, ACrossings: Integer);
var
  I, J, N, Prev: Integer;
  A, B: TGridPt;
  XIntersect: Double;
begin
  AWinding := 0;
  ACrossings := 0;

  for I := 0 to High(APaths) do
  begin
    N := Length(APaths[I]);
    if N < 3 then
      Continue;

    Prev := N - 1;
    for J := 0 to N - 1 do
    begin
      A := APaths[I][Prev];
      B := APaths[I][J];

      // Even-odd: count crossings of a ray towards +X.
      if ((A.Y <= APt.Y) and (B.Y > APt.Y)) or
         ((B.Y <= APt.Y) and (A.Y > APt.Y)) then
      begin
        XIntersect := A.X + (APt.Y - A.Y) * (B.X - A.X) / (B.Y - A.Y);
        if XIntersect > APt.X then
          Inc(ACrossings);
      end;

      // Nonzero: signed crossings.
      if A.Y <= APt.Y then
      begin
        if (B.Y > APt.Y) and (IsLeft(A, B, APt) > 0) then
          Inc(AWinding);
      end
      else
      begin
        if (B.Y <= APt.Y) and (IsLeft(A, B, APt) < 0) then
          Dec(AWinding);
      end;

      Prev := J;
    end;
  end;
end;

function InsideByRule(AWinding, ACrossings: Integer; ARule: TFillRule): Boolean;
begin
  case ARule of
    frEvenOdd : Result := (ACrossings mod 2) <> 0;
    frNonZero : Result := AWinding <> 0;
    frPositive: Result := AWinding > 0;
    frNegative: Result := AWinding < 0;
  else
    Result := AWinding <> 0;
  end;
end;

function IsInside(const APaths: TGridPaths; const APt: TGridPt;
  ARule: TFillRule): Boolean;
var
  W, C: Integer;
begin
  WindingOf(APaths, APt, W, C);
  Result := InsideByRule(W, C, ARule);
end;

// Same accumulation as WindingOf, but the query point may lie between grid
// coordinates. Classification samples must not be rounded onto the integer
// grid: a rounded sample can leave a thin feature and drop it from the result.
procedure WindingOfPoint(const APaths: TGridPaths; const APtX, APtY: Double;
  out AWinding, ACrossings: Integer);
var
  I, J, N, Prev: Integer;
  A, B: TGridPt;
  XIntersect, Side: Double;
begin
  AWinding := 0;
  ACrossings := 0;

  for I := 0 to High(APaths) do
  begin
    N := Length(APaths[I]);
    if N < 3 then
      Continue;

    Prev := N - 1;
    for J := 0 to N - 1 do
    begin
      A := APaths[I][Prev];
      B := APaths[I][J];

      if ((A.Y <= APtY) and (B.Y > APtY)) or
         ((B.Y <= APtY) and (A.Y > APtY)) then
      begin
        XIntersect := A.X + (APtY - A.Y) * (B.X - A.X) / (B.Y - A.Y);
        if XIntersect > APtX then
          Inc(ACrossings);
      end;

      Side := (B.X - A.X) * (APtY - A.Y) - (APtX - A.X) * (B.Y - A.Y);

      if A.Y <= APtY then
      begin
        if (B.Y > APtY) and (Side > 0) then
          Inc(AWinding);
      end
      else
      begin
        if (B.Y <= APtY) and (Side < 0) then
          Dec(AWinding);
      end;

      Prev := J;
    end;
  end;
end;

function IsInsidePoint(const APaths: TGridPaths; APtX, APtY: Double;
  ARule: TFillRule): Boolean;
var
  W, C: Integer;
begin
  WindingOfPoint(APaths, APtX, APtY, W, C);
  Result := InsideByRule(W, C, ARule);
end;


// ---------------------------------------------------------------------------
// Intersections
// ---------------------------------------------------------------------------

// Splits ASeg at any point where another segment crosses or touches it, and at
// any vertex of another segment that lies on it. Appends the pieces.
procedure SplitSegment(const ASeg: TSegment;
  const AAll: TSegmentArray; AOwnIndex: Integer;
  var AOutput: TSegmentArray; var AOutputCount: Integer);
var
  Params: array of Double;
  I, J, Count: Integer;
  P, Q, R, S: TGridPt;
  Denom, T, U: Double;
  Tmp: Double;

  procedure AddParam(AValue: Double);
  var
    K: Integer;
  begin
    if (AValue < -1e-12) or (AValue > 1 + 1e-12) then
      Exit;
    AValue := Min(1.0, Max(0.0, AValue));
    for K := 0 to Count - 1 do
      if Abs(Params[K] - AValue) < 1e-9 then
        Exit;
    SetLength(Params, Count + 1);
    Params[Count] := AValue;
    Inc(Count);
  end;

begin
  P := ASeg.A;
  Q := ASeg.B;
  SetLength(Params, 2);
  Params[0] := 0.0;
  Params[1] := 1.0;
  Count := 2;

  for I := 0 to High(AAll) do
  begin
    if I = AOwnIndex then
      Continue;

    R := AAll[I].A;
    S := AAll[I].B;

    Denom := (Q.X - P.X) * (S.Y - R.Y) - (Q.Y - P.Y) * (S.X - R.X);
    if Abs(Denom) < 1e-12 then
    begin
      // Parallel. Still split at any endpoint of the other segment that lies
      // on this one, which covers collinear overlaps.
      if Abs((R.X - P.X) * (Q.Y - P.Y) - (R.Y - P.Y) * (Q.X - P.X)) < 1e-9 then
      begin
        if (Q.X <> P.X) then
        begin
          AddParam((R.X - P.X) / (Q.X - P.X));
          AddParam((S.X - P.X) / (Q.X - P.X));
        end
        else if (Q.Y <> P.Y) then
        begin
          AddParam((R.Y - P.Y) / (Q.Y - P.Y));
          AddParam((S.Y - P.Y) / (Q.Y - P.Y));
        end;
      end;
      Continue;
    end;

    T := ((R.X - P.X) * (S.Y - R.Y) - (R.Y - P.Y) * (S.X - R.X)) / Denom;
    U := ((R.X - P.X) * (Q.Y - P.Y) - (R.Y - P.Y) * (Q.X - P.X)) / Denom;

    if (T < -1e-12) or (T > 1 + 1e-12) then
      Continue;
    if (U < -1e-12) or (U > 1 + 1e-12) then
      Continue;

    AddParam(T);
  end;

  // Sort parameters so pieces come out in order along the segment.
  for I := 1 to Count - 1 do
  begin
    Tmp := Params[I];
    J := I - 1;
    while (J >= 0) and (Params[J] > Tmp) do
    begin
      Params[J + 1] := Params[J];
      Dec(J);
    end;
    Params[J + 1] := Tmp;
  end;

  for I := 0 to Count - 2 do
  begin
    if Abs(Params[I + 1] - Params[I]) < 1e-12 then
      Continue;

    if AOutputCount >= Length(AOutput) then
      SetLength(AOutput, Max(16, Length(AOutput) * 2));

    AOutput[AOutputCount].A.X := Round(P.X + (Q.X - P.X) * Params[I]);
    AOutput[AOutputCount].A.Y := Round(P.Y + (Q.Y - P.Y) * Params[I]);
    AOutput[AOutputCount].B.X := Round(P.X + (Q.X - P.X) * Params[I + 1]);
    AOutput[AOutputCount].B.Y := Round(P.Y + (Q.Y - P.Y) * Params[I + 1]);
    Inc(AOutputCount);
  end;
end;

// ---------------------------------------------------------------------------
// Boundary extraction
// ---------------------------------------------------------------------------

type
  TOpPredicate = function(AInSubject, AInClip: Boolean): Boolean;

function PredUnion(AInSubject, AInClip: Boolean): Boolean;
begin
  Result := AInSubject or AInClip;
end;

function PredDifference(AInSubject, AInClip: Boolean): Boolean;
begin
  Result := AInSubject and not AInClip;
end;

function PredIntersect(AInSubject, AInClip: Boolean): Boolean;
begin
  Result := AInSubject and AInClip;
end;

function PredXor(AInSubject, AInClip: Boolean): Boolean;
begin
  Result := AInSubject xor AInClip;
end;

function PredicateFor(AOp: TPathBooleanOp): TOpPredicate;
begin
  case AOp of
    pboUnion     : Result := @PredUnion;
    pboDifference: Result := @PredDifference;
    pboIntersect : Result := @PredIntersect;
    pboXor       : Result := @PredXor;
  else
    raise EPathEngineError.Create('unsupported boolean operation');
  end;
end;

// True when the two directed segments are identical.
function SameSegment(const A, B: TSegment): Boolean;
begin
  Result := (A.A.X = B.A.X) and (A.A.Y = B.A.Y) and
            (A.B.X = B.B.X) and (A.B.Y = B.B.Y);
end;

// Chains directed boundary segments into closed contours.
//
// Segments are grouped by their start vertex. At a junction the most clockwise
// outgoing edge is chosen (smallest signed turn), which keeps the filled
// region on the left and traces one region's boundary at a time.
//
// Each iteration appends the start vertex of the segment it consumes, and the
// closing segment is consumed explicitly before the walk ends. Recording the
// final vertex is what makes the contour geometrically closed; exiting the
// loop as soon as the end vertex matched the start used to drop the last
// corner and silently shrink the result.
function ChainSegments(const ASegments: TSegmentArray): TGridPaths;
var
  Used: array of Boolean;
  I, J, Current, NextIdx, Count, OutCount, Steps: Integer;
  Contour: TGridPath;
  BestAngle, Angle: Double;
  DX, DY, EX, EY, Cross, Dot: Double;
  Found, Closed: Boolean;
begin
  SetLength(Result, 0);
  if Length(ASegments) = 0 then
    Exit;

  SetLength(Used, Length(ASegments));
  for I := 0 to High(Used) do
    Used[I] := False;

  OutCount := 0;
  for I := 0 to High(ASegments) do
  begin
    if Used[I] then
      Continue;

    SetLength(Contour, 0);
    Count := 0;
    Current := I;
    Steps := 0;
    Closed := False;

    while True do
    begin
      Used[Current] := True;
      SetLength(Contour, Count + 1);
      Contour[Count] := ASegments[Current].A;
      Inc(Count);
      Inc(Steps);

      if Steps > Length(ASegments) then
        Break;

      DX := ASegments[Current].B.X - ASegments[Current].A.X;
      DY := ASegments[Current].B.Y - ASegments[Current].A.Y;

      NextIdx := -1;
      BestAngle := 0.0;
      Found := False;

      for J := 0 to High(ASegments) do
      begin
        if Used[J] then
          Continue;
        if (ASegments[J].A.X <> ASegments[Current].B.X) or
           (ASegments[J].A.Y <> ASegments[Current].B.Y) then
          Continue;

        EX := ASegments[J].B.X - ASegments[J].A.X;
        EY := ASegments[J].B.Y - ASegments[J].A.Y;
        Cross := DX * EY - DY * EX;
        Dot := DX * EX + DY * EY;
        Angle := ArcTan2(Cross, Dot);

        if (not Found) or (Angle < BestAngle) then
        begin
          NextIdx := J;
          BestAngle := Angle;
          Found := True;
        end;
      end;

      if not Found then
        Break;

      if (ASegments[NextIdx].B.X = ASegments[I].A.X) and
         (ASegments[NextIdx].B.Y = ASegments[I].A.Y) then
      begin
        // Closing segment: record its start vertex, then stop.
        Used[NextIdx] := True;
        SetLength(Contour, Count + 1);
        Contour[Count] := ASegments[NextIdx].A;
        Inc(Count);
        Closed := True;
        Break;
      end;

      Current := NextIdx;
    end;

    if Closed and (Count >= 3) then
    begin
      SetLength(Result, OutCount + 1);
      Result[OutCount] := Contour;
      Inc(OutCount);
    end;
  end;

  SetLength(Result, OutCount);
end;

// ---------------------------------------------------------------------------
// Entry points
// ---------------------------------------------------------------------------

function FloriaNormalizePaths(const APaths: TPathsD;
  AFillRule: TFillRule; APrecision: Integer): TPathsD;
begin
  Result := FloriaBooleanOp(pboUnion, APaths, nil, AFillRule, APrecision);
end;

function FloriaBooleanOp(AOp: TPathBooleanOp;
  const ASubject, AClip: TPathsD;
  AFillRule: TFillRule; APrecision: Integer): TPathsD;
var
  Scale, InvScale: Double;
  SubjGrid, ClipGrid: TGridPaths;
  AllSegments: TSegmentArray;
  SplitSegments: TSegmentArray;
  SplitCount, I, J, K: Integer;
  Boundary: TSegmentArray;
  BoundaryCount: Integer;
  MidX, MidY, NX, NY, Len: Double;
  InSubjL, InClipL, InSubjR, InClipR: Boolean;
  InsideL, InsideR: Boolean;
  Found: Boolean;
  Pred: TOpPredicate;
  Chained: TGridPaths;
  CleanResult: TGridPaths;
begin
  ValidatePrecision(APrecision);

  Scale := Power(10, APrecision);
  InvScale := 1.0 / Scale;

  SubjGrid := CleanGridPaths(ScaleToGrid(ASubject, Scale));
  ClipGrid := CleanGridPaths(ScaleToGrid(AClip, Scale));

  // Collect every edge from both operands.
  SetLength(AllSegments, 0);
  SplitCount := 0;
  for I := 0 to High(SubjGrid) do
    for J := 0 to High(SubjGrid[I]) do
    begin
      if SplitCount >= Length(AllSegments) then
        SetLength(AllSegments, Max(16, Length(AllSegments) * 2));
      AllSegments[SplitCount].A := SubjGrid[I][J];
      if J = High(SubjGrid[I]) then
        AllSegments[SplitCount].B := SubjGrid[I][0]
      else
        AllSegments[SplitCount].B := SubjGrid[I][J + 1];
      Inc(SplitCount);
    end;

  for I := 0 to High(ClipGrid) do
    for J := 0 to High(ClipGrid[I]) do
    begin
      if SplitCount >= Length(AllSegments) then
        SetLength(AllSegments, Max(16, Length(AllSegments) * 2));
      AllSegments[SplitCount].A := ClipGrid[I][J];
      if J = High(ClipGrid[I]) then
        AllSegments[SplitCount].B := ClipGrid[I][0]
      else
        AllSegments[SplitCount].B := ClipGrid[I][J + 1];
      Inc(SplitCount);
    end;

  SetLength(AllSegments, SplitCount);

  // Split at every intersection.
  SetLength(SplitSegments, Max(16, SplitCount * 2));
  SplitCount := 0;
  for I := 0 to High(AllSegments) do
    SplitSegment(AllSegments[I], AllSegments, I, SplitSegments, SplitCount);
  SetLength(SplitSegments, SplitCount);

  // Classify each piece and keep the ones on the result boundary.
  Pred := PredicateFor(AOp);
  SetLength(Boundary, Length(SplitSegments));
  BoundaryCount := 0;

  for I := 0 to High(SplitSegments) do
  begin
    // Skip zero-length pieces.
    if (SplitSegments[I].A.X = SplitSegments[I].B.X) and
       (SplitSegments[I].A.Y = SplitSegments[I].B.Y) then
      Continue;

    // Deduplicate against what we already kept.
    Found := False;
    for K := 0 to BoundaryCount - 1 do
      if SameSegment(Boundary[K], SplitSegments[I]) then
      begin
        Found := True;
        Break;
      end;
    if Found then
      Continue;

    MidX := (SplitSegments[I].A.X + SplitSegments[I].B.X) * 0.5;
    MidY := (SplitSegments[I].A.Y + SplitSegments[I].B.Y) * 0.5;

    NX := -(SplitSegments[I].B.Y - SplitSegments[I].A.Y);
    NY :=  (SplitSegments[I].B.X - SplitSegments[I].A.X);
    Len := Sqrt(NX * NX + NY * NY);
    if Len = 0 then
      Continue;
    NX := NX / Len * BOOLEAN_SAMPLE_OFFSET;
    NY := NY / Len * BOOLEAN_SAMPLE_OFFSET;

    InSubjL := IsInsidePoint(SubjGrid, MidX + NX, MidY + NY, AFillRule);
    InClipL := IsInsidePoint(ClipGrid, MidX + NX, MidY + NY, AFillRule);
    InsideL := Pred(InSubjL, InClipL);

    InSubjR := IsInsidePoint(SubjGrid, MidX - NX, MidY - NY, AFillRule);
    InClipR := IsInsidePoint(ClipGrid, MidX - NX, MidY - NY, AFillRule);
    InsideR := Pred(InSubjR, InClipR);

    if InsideL = InsideR then
      Continue;

    // Orient so the filled side is on the left.
    if InsideL then
      Boundary[BoundaryCount] := SplitSegments[I]
    else
    begin
      Boundary[BoundaryCount].A := SplitSegments[I].B;
      Boundary[BoundaryCount].B := SplitSegments[I].A;
    end;
    Inc(BoundaryCount);
  end;

  SetLength(Boundary, BoundaryCount);
  Chained := ChainSegments(Boundary);
  CleanResult := CleanGridPaths(Chained);

  Result := UnscaleFromGrid(CleanResult, InvScale);
end;

end.
