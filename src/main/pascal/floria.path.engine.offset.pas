unit Floria.Path.Engine.Offset;

// Floria.Path.Engine.Offset
// =========================
// First-party polygon offsetting (inflate / deflate) and open-path stroking.
//
// Approach
// --------
// Offsetting is done in two stages, the same shape as the classic algorithm:
//
//   1. Build raw offset geometry. Each edge is pushed out by delta along its
//      unit normal, and each corner contributes join geometry chosen by the
//      join type (miter, square, bevel, round). Convex corners need a join to
//      bridge the gap between adjacent offset edges; concave corners instead
//      collapse to the intersection of the two offset lines.
//   2. Clean the result. Raw offset geometry self-intersects wherever delta
//      exceeds the local feature size, so the pieces are unioned to remove the
//      overlaps and keep only the outer boundary.
//
// Open paths are stroked by walking one offset side forward, adding an end
// cap, walking the other side back, and adding a start cap. That produces a
// closed contour which then goes through the same cleanup.
//
// Orientation matters: the outward normal depends on whether a contour winds
// clockwise or counter-clockwise, and so does the sign that identifies a
// convex corner. Both are derived from the contour's signed area.

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Math,
  Floria.Geometry,
  Floria.Errors,
  Floria.Path.Engine;

// Offsets APaths by ADelta. Positive delta inflates, negative deflates.
// Returns freshly allocated geometry owned by the caller.
function FloriaOffsetPaths(const APaths: TPathsD; ADelta: Double;
  AJoinType: TPathJoinType = pjtRound;
  AEndType: TPathEndType = petPolygon;
  AMiterLimit: Double = 2.0;
  AArcTolerance: Double = 0.0;
  APrecision: Integer = 2): TPathsD;

const
  // Relative arc tolerance used when the caller does not supply one: the
  // permitted chord error is 1/500th of the offset distance.
  OFFSET_ARC_CONST = 0.002;

  MAX_OFFSET_PRECISION = 8;
  MAX_OFFSET_COORD = 1000000000;

implementation

uses
  Floria.Path.Engine.Boolean;

type
  TOffsetPt = record
    X, Y: Double;
  end;

  TOffsetPath  = array of TOffsetPt;
  TOffsetPaths = array of TOffsetPath;

// ---------------------------------------------------------------------------
// Vector helpers
// ---------------------------------------------------------------------------

function MakePt(AX, AY: Double): TOffsetPt;
begin
  Result.X := AX;
  Result.Y := AY;
end;

function AddPt(const A, B: TOffsetPt): TOffsetPt;
begin
  Result.X := A.X + B.X;
  Result.Y := A.Y + B.Y;
end;

function SubPt(const A, B: TOffsetPt): TOffsetPt;
begin
  Result.X := A.X - B.X;
  Result.Y := A.Y - B.Y;
end;

function ScalePt(const A: TOffsetPt; AFactor: Double): TOffsetPt;
begin
  Result.X := A.X * AFactor;
  Result.Y := A.Y * AFactor;
end;

function DotPt(const A, B: TOffsetPt): Double;
begin
  Result := A.X * B.X + A.Y * B.Y;
end;

function CrossPt(const A, B: TOffsetPt): Double;
begin
  Result := A.X * B.Y - A.Y * B.X;
end;

function MidPointOf(const A, B: TOffsetPt): TOffsetPt;
begin
  Result.X := (A.X + B.X) * 0.5;
  Result.Y := (A.Y + B.Y) * 0.5;
end;

function LenPt(const A: TOffsetPt): Double;
begin
  Result := Sqrt(A.X * A.X + A.Y * A.Y);
end;

function NormalizePt(const A: TOffsetPt): TOffsetPt;
var
  L: Double;
begin
  L := LenPt(A);
  if L = 0 then
    Exit(MakePt(0, 0));
  Result.X := A.X / L;
  Result.Y := A.Y / L;
end;

// Intersection of two infinite lines, each given as a point plus direction.
// Returns False when the lines are parallel.
function LineIntersect(const P1, D1, P2, D2: TOffsetPt;
  out AResult: TOffsetPt): Boolean;
var
  Denom, T: Double;
begin
  Denom := CrossPt(D1, D2);
  if Abs(Denom) < 1e-12 then
  begin
    AResult := P1;
    Exit(False);
  end;
  T := CrossPt(SubPt(P2, P1), D2) / Denom;
  AResult := AddPt(P1, ScalePt(D1, T));
  Result := True;
end;

// ---------------------------------------------------------------------------
// Contour helpers
// ---------------------------------------------------------------------------

function SignedArea(const APath: TOffsetPath): Double;
var
  I, N, Prev: Integer;
begin
  Result := 0.0;
  N := Length(APath);
  if N < 3 then
    Exit;
  Prev := N - 1;
  for I := 0 to N - 1 do
  begin
    Result := Result + (APath[Prev].X * APath[I].Y - APath[I].X * APath[Prev].Y);
    Prev := I;
  end;
  Result := Result * 0.5;
end;

function CentroidOf(const APath: TOffsetPath): TOffsetPt;
var
  I: Integer;
begin
  Result := MakePt(0, 0);
  if Length(APath) = 0 then
    Exit;
  for I := 0 to High(APath) do
  begin
    Result.X := Result.X + APath[I].X;
    Result.Y := Result.Y + APath[I].Y;
  end;
  Result.X := Result.X / Length(APath);
  Result.Y := Result.Y / Length(APath);
end;

// Distance from APt to the segment A..B.
function DistToSegment(const APt, A, B: TOffsetPt): Double;
var
  DX, DY, LenSqrd, T: Double;
begin
  DX := B.X - A.X;
  DY := B.Y - A.Y;
  LenSqrd := DX * DX + DY * DY;
  if LenSqrd <= 0 then
    Exit(Sqrt(Sqr(APt.X - A.X) + Sqr(APt.Y - A.Y)));

  T := ((APt.X - A.X) * DX + (APt.Y - A.Y) * DY) / LenSqrd;
  if T < 0 then
    T := 0
  else if T > 1 then
    T := 1;

  Result := Sqrt(Sqr(APt.X - (A.X + T * DX)) + Sqr(APt.Y - (A.Y + T * DY)));
end;

// True when a deflated contour has folded through itself.
//
// A valid deflated contour sits at least |delta| away from the original
// boundary everywhere. Once delta exceeds the inradius the raw offset folds
// over: a 100x100 square deflated by 60 yields a 20x20 island whose corners
// are only 40 units from the original edges, so the invariant catches it.
//
// Winding sign is not usable as the test, because a folded contour can come
// out with the same orientation as the original.
function DeflateCollapsed(const AOriginal, AOffset: TOffsetPath;
  ADelta: Double): Boolean;
var
  I, J, N: Integer;
  Nearest, D: Double;
begin
  Result := False;
  if Length(AOffset) = 0 then
    Exit(True);
  if Length(AOriginal) < 2 then
    Exit(False);

  N := Length(AOriginal);
  for I := 0 to High(AOffset) do
  begin
    Nearest := Infinity;
    for J := 0 to N - 1 do
    begin
      if J = N - 1 then
        D := DistToSegment(AOffset[I], AOriginal[J], AOriginal[0])
      else
        D := DistToSegment(AOffset[I], AOriginal[J], AOriginal[J + 1]);
      if D < Nearest then
        Nearest := D;
    end;

    // Half a grid unit of slack absorbs rounding at the offset precision.
    if Nearest < Abs(ADelta) - 0.5 then
      Exit(True);
  end;
end;

// Removes consecutive duplicates and a redundant closing point.
function CleanOffsetPath(const APath: TOffsetPath): TOffsetPath;
var
  I, Count: Integer;
begin
  SetLength(Result, Length(APath));
  Count := 0;
  for I := 0 to High(APath) do
  begin
    if (Count > 0) and
       (Abs(Result[Count - 1].X - APath[I].X) < 1e-9) and
       (Abs(Result[Count - 1].Y - APath[I].Y) < 1e-9) then
      Continue;
    Result[Count] := APath[I];
    Inc(Count);
  end;

  if (Count > 1) and
     (Abs(Result[Count - 1].X - Result[0].X) < 1e-9) and
     (Abs(Result[Count - 1].Y - Result[0].Y) < 1e-9) then
    Dec(Count);

  SetLength(Result, Count);
end;

procedure AppendPoint(var APath: TOffsetPath; var ACount: Integer;
  const APt: TOffsetPt);
begin
  if ACount >= Length(APath) then
    SetLength(APath, Max(16, Length(APath) * 2));
  APath[ACount] := APt;
  Inc(ACount);
end;

// ---------------------------------------------------------------------------
// Arc stepping
// ---------------------------------------------------------------------------

// Number of steps per radian, matching the chord-error derivation: pick a
// tolerance, then solve for the step angle whose sagitta fits inside it.
function StepsPerRadian(AbsDelta, AArcTolerance: Double): Double;
var
  ArcTol, StepsPer360, CosArg: Double;
begin
  if AbsDelta <= 0 then
    Exit(1.0);

  if AArcTolerance > 0 then
    ArcTol := Min(AbsDelta, AArcTolerance)
  else
    ArcTol := AbsDelta * OFFSET_ARC_CONST;

  CosArg := 1 - ArcTol / AbsDelta;
  if CosArg <= -1 then
    CosArg := -1;
  if CosArg >= 1 then
    CosArg := 1;

  StepsPer360 := Pi / ArcCos(CosArg);
  if StepsPer360 > AbsDelta * Pi then
    StepsPer360 := AbsDelta * Pi;
  if StepsPer360 < 8 then
    StepsPer360 := 8;

  Result := StepsPer360 / (2 * Pi);
end;

// ---------------------------------------------------------------------------
// Join geometry
// ---------------------------------------------------------------------------

// Emits the corner geometry between the two offset points that meet at
// AVertex. The caller appends into APath starting at ACount.
procedure EmitJoin(var APath: TOffsetPath; var ACount: Integer;
  const AVertex, AFrom, ATo, AFromDir, AToDir: TOffsetPt;
  ADelta, AMiterLimit, AStepsPerRad: Double;
  AJoinType: TPathJoinType);
var
  CosA, Q: Double;
  Steps, I: Integer;
  AngleFrom, AngleTo, Angle, Step: Double;
  MiterPt: TOffsetPt;
  N1, N2, DirTo: TOffsetPt;
  Bisector, BisectorPt, CutDir, CutA, CutB: TOffsetPt;
  HaveA, HaveB: Boolean;
begin
  N1 := NormalizePt(SubPt(AFrom, AVertex));
  N2 := NormalizePt(SubPt(ATo, AVertex));
  CosA := DotPt(N1, N2);
  if CosA > 1 then
    CosA := 1;
  if CosA < -1 then
    CosA := -1;

  case AJoinType of
    pjtBevel:
      begin
        AppendPoint(APath, ACount, AFrom);
        AppendPoint(APath, ACount, ATo);
      end;

    pjtMiter:
      begin
        // A miter is only acceptable while the spike stays within the limit.
        // The squared-cosine test avoids computing the spike length.
        if (AMiterLimit <= 0) or (CosA > 2 / Sqr(AMiterLimit) - 1) then
        begin
          Q := ADelta / (CosA + 1);
          MiterPt := AddPt(AVertex,
            ScalePt(AddPt(N1, N2), Q));
          AppendPoint(APath, ACount, AFrom);
          AppendPoint(APath, ACount, MiterPt);
          AppendPoint(APath, ACount, ATo);
        end
        else
        begin
          // Fall back to a bevel, which is what the limit is protecting.
          AppendPoint(APath, ACount, AFrom);
          AppendPoint(APath, ACount, ATo);
        end;
      end;

    pjtSquare:
      begin
        // A square join is the miter corner cut back to exactly the offset
        // distance. Construction: step |delta| out along the bisector, then
        // cut perpendicular to the bisector; the two offset edge lines meet
        // that cut at the join's corner points.
        //
        // For a right angle this removes a triangle of area
        // (delta*(1-cos45))^2/2 per corner, which is why a square join on a
        // 100x100 square inflated by 5 gives 12082.83 rather than the 12100
        // a miter produces.
        Bisector := AddPt(N1, N2);
        if LenPt(Bisector) < 1e-12 then
        begin
          AppendPoint(APath, ACount, AFrom);
          AppendPoint(APath, ACount, ATo);
          Exit;
        end;

        Bisector := NormalizePt(Bisector);
        BisectorPt := AddPt(AVertex, ScalePt(Bisector, Abs(ADelta)));
        CutDir := MakePt(Bisector.Y, -Bisector.X);

        HaveA := LineIntersect(BisectorPt, CutDir, AFrom, AFromDir, CutA);
        HaveB := LineIntersect(BisectorPt, CutDir, ATo, AToDir, CutB);

        if not (HaveA and HaveB) then
        begin
          AppendPoint(APath, ACount, AFrom);
          AppendPoint(APath, ACount, ATo);
          Exit;
        end;

        AppendPoint(APath, ACount, AFrom);
        AppendPoint(APath, ACount, CutA);
        AppendPoint(APath, ACount, CutB);
        AppendPoint(APath, ACount, ATo);
      end;

    pjtRound:
      begin
        AngleFrom := ArcTan2(AFrom.Y - AVertex.Y, AFrom.X - AVertex.X);
        AngleTo := ArcTan2(ATo.Y - AVertex.Y, ATo.X - AVertex.X);

        Angle := AngleTo - AngleFrom;
        while Angle > Pi do
          Angle := Angle - 2 * Pi;
        while Angle < -Pi do
          Angle := Angle + 2 * Pi;

        Steps := Trunc(Ceil(Abs(Angle) * AStepsPerRad));
        if Steps < 1 then
          Steps := 1;

        Step := Angle / Steps;
        for I := 0 to Steps do
        begin
          if I = 0 then
            AppendPoint(APath, ACount, AFrom)
          else if I = Steps then
            AppendPoint(APath, ACount, ATo)
          else
            AppendPoint(APath, ACount,
              AddPt(AVertex, MakePt(
                Abs(ADelta) * Cos(AngleFrom + Step * I),
                Abs(ADelta) * Sin(AngleFrom + Step * I))));
        end;
      end;
  end;
end;

// ---------------------------------------------------------------------------
// Closed contour offset
// ---------------------------------------------------------------------------

function OffsetClosedPath(const APath: TOffsetPath; ADelta: Double;
  AJoinType: TPathJoinType; AMiterLimit, AStepsPerRad: Double): TOffsetPath;
var
  N, I, Prev, Count: Integer;
  Normals: array of TOffsetPt;
  Dir: TOffsetPt;
  OrientSign: Double;
  DPrev, DCur: TOffsetPt;
  PFrom, PTo: TOffsetPt;
  Cross: Double;
  Convex: Boolean;
  Intersect: TOffsetPt;
  InflateSign: Double;
begin
  SetLength(Result, 0);
  N := Length(APath);
  if N < 3 then
    Exit;

  // Outward direction depends on winding: for a counter-clockwise contour the
  // interior lies to the left, so the outward normal is (dy, -dx).
  if SignedArea(APath) >= 0 then
  begin
    OrientSign := 1.0;
    InflateSign := 1.0;
  end
  else
  begin
    OrientSign := -1.0;
    InflateSign := -1.0;
  end;

  // Unit normal per edge, pointing away from the interior.
  SetLength(Normals, N);
  for I := 0 to N - 1 do
  begin
    if I = N - 1 then
      Dir := SubPt(APath[0], APath[I])
    else
      Dir := SubPt(APath[I + 1], APath[I]);
    Dir := NormalizePt(Dir);
    Normals[I] := MakePt(Dir.Y * InflateSign, -Dir.X * InflateSign);
  end;

  Count := 0;
  SetLength(Result, Max(16, N * 2));

  for I := 0 to N - 1 do
  begin
    if I = 0 then
      Prev := N - 1
    else
      Prev := I - 1;

    // Offset points of the incoming and outgoing edges at this vertex.
    PFrom := AddPt(APath[I], ScalePt(Normals[Prev], ADelta));
    PTo := AddPt(APath[I], ScalePt(Normals[I], ADelta));

    if I = N - 1 then
      DCur := SubPt(APath[0], APath[I])
    else
      DCur := SubPt(APath[I + 1], APath[I]);
    DPrev := SubPt(APath[I], APath[Prev]);

    Cross := CrossPt(DPrev, DCur);
    Convex := (Cross * OrientSign) > 0;

    if Convex and (ADelta > 0) then
      // Growing a convex corner leaves a gap; fill it with join geometry.
      EmitJoin(Result, Count, APath[I], PFrom, PTo, DPrev, DCur,
        ADelta, AMiterLimit, AStepsPerRad, AJoinType)
    else if (not Convex) and (ADelta < 0) then
      // Shrinking a concave corner opens the same kind of gap.
      EmitJoin(Result, Count, APath[I], PFrom, PTo, DPrev, DCur,
        ADelta, AMiterLimit, AStepsPerRad, AJoinType)
    else
    begin
      // The offset edges overlap here. Their intersection is where the two
      // offset lines meet, which removes the self-overlap before it exists.
      // The lines must pass through the offset points, not the original
      // vertex: two lines through the same point always intersect there, so
      // using AVertex would silently return the un-offset corner.
      if LineIntersect(PFrom, DPrev, PTo, DCur, Intersect) then
        AppendPoint(Result, Count, Intersect)
      else
        AppendPoint(Result, Count, PTo);
    end;
  end;

  SetLength(Result, Count);
  Result := CleanOffsetPath(Result);
end;

// ---------------------------------------------------------------------------
// Open path stroking
// ---------------------------------------------------------------------------

// Builds one offset side of an open path, walking it in order.
function OffsetOpenSide(const APath: TOffsetPath; ADelta: Double;
  AJoinType: TPathJoinType; AMiterLimit, AStepsPerRad: Double): TOffsetPath;
var
  N, I, Count: Integer;
  Normals: array of TOffsetPt;
  Dir: TOffsetPt;
  PFrom, PTo: TOffsetPt;
  Cross: Double;
  Intersect: TOffsetPt;
begin
  SetLength(Result, 0);
  N := Length(APath);
  if N < 2 then
    Exit;

  // Left-hand normal for every edge.
  SetLength(Normals, N - 1);
  for I := 0 to N - 2 do
  begin
    Dir := NormalizePt(SubPt(APath[I + 1], APath[I]));
    Normals[I] := MakePt(-Dir.Y, Dir.X);
  end;

  Count := 0;
  SetLength(Result, Max(16, N * 2));

  AppendPoint(Result, Count, AddPt(APath[0], ScalePt(Normals[0], ADelta)));

  for I := 1 to N - 2 do
  begin
    PFrom := AddPt(APath[I], ScalePt(Normals[I - 1], ADelta));
    PTo := AddPt(APath[I], ScalePt(Normals[I], ADelta));

    Dir := SubPt(APath[I + 1], APath[I]);
    Cross := CrossPt(SubPt(APath[I], APath[I - 1]), Dir);

    // On the left side, a right turn (negative cross) opens a gap.
    if Cross < 0 then
      EmitJoin(Result, Count, APath[I], PFrom, PTo,
        SubPt(APath[I], APath[I - 1]), Dir,
        ADelta, AMiterLimit, AStepsPerRad, AJoinType)
    else
    begin
      if LineIntersect(PFrom, SubPt(APath[I], APath[I - 1]),
        PTo, Dir, Intersect) then
        AppendPoint(Result, Count, Intersect)
      else
        AppendPoint(Result, Count, PTo);
    end;
  end;

  AppendPoint(Result, Count, AddPt(APath[N - 1], ScalePt(Normals[N - 2], ADelta)));

  SetLength(Result, Count);
end;

// Appends a cap centred on AVertex, sweeping from AFrom to ATo.
// Emits a cap centred on AVertex, sweeping from AFrom to ATo around the
// outside of the path. AOutward is the unit direction the cap must bulge in;
// without it the sweep is ambiguous whenever the two endpoints sit exactly
// opposite each other, which is the common case for a straight stroke.
procedure EmitCap(var APath: TOffsetPath; var ACount: Integer;
  const AVertex, AFrom, ATo, AOutward: TOffsetPt;
  ADelta, AStepsPerRad: Double; AEndType: TPathEndType);
var
  AngleFrom, AngleTo, AngleMid, Angle, Step: Double;
  Steps, I: Integer;
  DirFrom, DirTo, Corner: TOffsetPt;
begin
  case AEndType of
    petButt:
      begin
        AppendPoint(APath, ACount, AFrom);
        AppendPoint(APath, ACount, ATo);
      end;

    petSquare:
      begin
        // Extend both offset endpoints by delta along the outward tangent, so
        // the stroke is lengthened rather than widened.
        DirFrom := NormalizePt(AOutward);
        Corner := AddPt(AFrom, ScalePt(DirFrom, Abs(ADelta)));
        AppendPoint(APath, ACount, AFrom);
        AppendPoint(APath, ACount, Corner);
        Corner := AddPt(ATo, ScalePt(DirFrom, Abs(ADelta)));
        AppendPoint(APath, ACount, Corner);
        AppendPoint(APath, ACount, ATo);
      end;

    petRound:
      begin
        AngleFrom := ArcTan2(AFrom.Y - AVertex.Y, AFrom.X - AVertex.X);
        AngleTo := ArcTan2(ATo.Y - AVertex.Y, ATo.X - AVertex.X);
        AngleMid := ArcTan2(AOutward.Y, AOutward.X);

        // Choose the sweep that actually passes through the outward
        // direction. Picking the numerically shorter arc is wrong for a
        // straight stroke, where both arcs have the same length.
        Angle := AngleTo - AngleFrom;
        while Angle > 2 * Pi do
          Angle := Angle - 2 * Pi;
        while Angle < -2 * Pi do
          Angle := Angle + 2 * Pi;

        if Cos(AngleFrom + Angle * 0.5 - AngleMid) < 0 then
        begin
          if Angle >= 0 then
            Angle := Angle - 2 * Pi
          else
            Angle := Angle + 2 * Pi;
        end;

        Steps := Trunc(Ceil(Abs(Angle) * AStepsPerRad));
        if Steps < 1 then
          Steps := 1;

        Step := Angle / Steps;
        for I := 0 to Steps do
        begin
          if I = 0 then
            AppendPoint(APath, ACount, AFrom)
          else if I = Steps then
            AppendPoint(APath, ACount, ATo)
          else
            AppendPoint(APath, ACount,
              AddPt(AVertex, MakePt(
                Abs(ADelta) * Cos(AngleFrom + Step * I),
                Abs(ADelta) * Sin(AngleFrom + Step * I))));
        end;
      end;

    else
      // petPolygon / petJoined are not caps; treat them as a flat end.
      begin
        AppendPoint(APath, ACount, AFrom);
        AppendPoint(APath, ACount, ATo);
      end;
  end;
end;

// Strokes an open path by walking one side out, capping, and walking back.
function StrokeOpenPath(const APath: TOffsetPath; ADelta: Double;
  AJoinType: TPathJoinType; AEndType: TPathEndType;
  AMiterLimit, AStepsPerRad: Double): TOffsetPath;
var
  LeftSide, RightPath, RightSide: TOffsetPath;
  I, Count, N: Integer;
  EndTangent, StartTangent: TOffsetPt;
begin
  SetLength(Result, 0);
  N := Length(APath);
  if N < 2 then
    Exit;

  LeftSide := OffsetOpenSide(APath, ADelta, AJoinType, AMiterLimit, AStepsPerRad);

  // The return side is the reversed path offset the other way.
  SetLength(RightPath, N);
  for I := 0 to N - 1 do
    RightPath[I] := APath[N - 1 - I];
  RightSide := OffsetOpenSide(RightPath, ADelta, AJoinType, AMiterLimit, AStepsPerRad);

  Count := 0;
  SetLength(Result, Max(16, Length(LeftSide) + Length(RightSide) + 8));

  for I := 0 to High(LeftSide) do
    AppendPoint(Result, Count, LeftSide[I]);

  // Cap at the far end: bulge along the final tangent.
  EndTangent := NormalizePt(SubPt(APath[N - 1], APath[N - 2]));
  EmitCap(Result, Count, APath[N - 1],
    LeftSide[High(LeftSide)], RightSide[0], EndTangent,
    ADelta, AStepsPerRad, AEndType);

  for I := 0 to High(RightSide) do
    AppendPoint(Result, Count, RightSide[I]);

  // Cap at the near end: bulge against the first tangent.
  StartTangent := NormalizePt(SubPt(APath[0], APath[1]));
  EmitCap(Result, Count, APath[0],
    RightSide[High(RightSide)], LeftSide[0], StartTangent,
    ADelta, AStepsPerRad, AEndType);

  SetLength(Result, Count);
  Result := CleanOffsetPath(Result);
end;

// ---------------------------------------------------------------------------
// Conversion
// ---------------------------------------------------------------------------

function ToOffsetPath(const APath: TPathD): TOffsetPath;
var
  I: Integer;
begin
  SetLength(Result, Length(APath));
  for I := 0 to High(APath) do
  begin
    Result[I].X := APath[I].X;
    Result[I].Y := APath[I].Y;
  end;
end;

function FromOffsetPaths(const APaths: TOffsetPaths): TPathsD;
var
  I, J: Integer;
begin
  SetLength(Result, Length(APaths));
  for I := 0 to High(APaths) do
  begin
    SetLength(Result[I], Length(APaths[I]));
    for J := 0 to High(APaths[I]) do
    begin
      Result[I][J].X := APaths[I][J].X;
      Result[I][J].Y := APaths[I][J].Y;
    end;
  end;
end;

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

function FloriaOffsetPaths(const APaths: TPathsD; ADelta: Double;
  AJoinType: TPathJoinType; AEndType: TPathEndType;
  AMiterLimit: Double; AArcTolerance: Double;
  APrecision: Integer): TPathsD;
var
  Raw: TOffsetPaths;
  I, Count: Integer;
  Path: TOffsetPath;
  Steps: Double;
  MiterLimit: Double;
  OriginalSign: Integer;
  OriginalPath: TOffsetPath;
begin
  if (APrecision < 0) or (APrecision > MAX_OFFSET_PRECISION) then
    raise EPathEngineError.CreateFmt('precision out of range: %d', [APrecision]);

  if IsNaN(ADelta) or IsInfinite(ADelta) then
    raise EPathEngineError.CreateFmt('invalid offset delta: %f', [ADelta]);

  // A zero offset is a no-op; return a clean copy rather than raw geometry.
  if Abs(ADelta) < 1e-12 then
    Exit(Copy(APaths));

  MiterLimit := AMiterLimit;
  if MiterLimit <= 0 then
    MiterLimit := 2.0;

  Steps := StepsPerRadian(Abs(ADelta), AArcTolerance);

  SetLength(Raw, 0);
  Count := 0;

  for I := 0 to High(APaths) do
  begin
    if Length(APaths[I]) = 0 then
      Continue;

    Path := ToOffsetPath(APaths[I]);
    OriginalPath := Path;
    OriginalSign := Sign(SignedArea(Path));

    if (AEndType = petPolygon) or (AEndType = petJoined) then
    begin
      if Length(Path) < 3 then
        Continue;
      Path := OffsetClosedPath(Path, ADelta, AJoinType, MiterLimit, Steps);
    end
    else
    begin
      if Length(Path) < 2 then
        Continue;
      Path := StrokeOpenPath(Path, ADelta, AJoinType, AEndType, MiterLimit, Steps);
    end;

    if Length(Path) < 3 then
      Continue;

    // A deflated contour collapses once the offset exceeds its inradius. The
    // raw geometry then folds through itself and produces a small spurious
    // remnant (a 100x100 square deflated by 60 leaves a 20x20 island).
    //
    // Detect that geometrically rather than by winding sign: the offset
    // contour must shrink toward its centroid. If any vertex ends up further
    // from the centroid than it started, the contour inverted and is dropped.
    if ((AEndType = petPolygon) or (AEndType = petJoined)) and (ADelta < 0) then
      if DeflateCollapsed(OriginalPath, Path, ADelta) then
        Continue;

    SetLength(Raw, Count + 1);
    Raw[Count] := Path;
    Inc(Count);
  end;

  SetLength(Raw, Count);
  if Count = 0 then
    Exit(nil);

  // Raw offset geometry overlaps wherever delta exceeds the local feature
  // size. Unioning removes the self-intersections and keeps the outline.
  Result := FloriaNormalizePaths(FromOffsetPaths(Raw), frNonZero, APrecision);
end;

end.
