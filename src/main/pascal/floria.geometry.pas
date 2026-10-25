unit Floria.Geometry;

// Floria.Geometry
// ===============
// First-party 2D geometry value types shared across the library: points,
// rectangles, polygon paths, and fill rules.
//
// These types used to live in the vendored Clipper2 port. They are declared
// here so that canvases, display lists, the GPU pipeline, and text layout do
// not depend on a clipping engine for their basic geometry.
//
// Layout compatibility note: TPointD and TRectD keep the same field names and
// order the clipping engine historically used, so existing construction code
// and FillChar zero-initialization continue to behave identically.

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  SysUtils, Math;

type
  PPointD = ^TPointD;
  TPointD = record
    X, Y: Double;
    class function Create(const AX, AY: Double): TPointD; static;
  end;

  TPathD = array of TPointD;
  TPathsD = array of TPathD;
  TArrayOfPathsD = array of TPathsD;

  // The most commonly used filling rules for polygons are EvenOdd and NonZero.
  // https://en.wikipedia.org/wiki/Even-odd_rule
  // https://en.wikipedia.org/wiki/Nonzero-rule
  TFillRule = (frEvenOdd, frNonZero, frPositive, frNegative);

  TRectD = record
  private
    function GetWidth(): Double;
    function GetHeight(): Double;
    function GetIsEmpty(): Boolean;
    function GetIsValid(): Boolean;
    function GetMidPoint(): TPointD;
  public
    Left   : Double;
    Top    : Double;
    Right  : Double;
    Bottom : Double;

    class function Create(const ALeft, ATop, ARight, ABottom: Double): TRectD; static;

    function Contains(const APt: TPointD): Boolean; overload;
    function Contains(const ARect: TRectD): Boolean; overload;
    function Intersects(const ARect: TRectD): Boolean;
    function AsPath(): TPathD;

    property Width   : Double  read GetWidth;
    property Height  : Double  read GetHeight;
    property IsEmpty : Boolean read GetIsEmpty;
    property IsValid : Boolean read GetIsValid;
    property MidPoint: TPointD read GetMidPoint;
  end;

const
  invalidD = Infinity;

  NullPointD  : TPointD = (X: 0; Y: 0);
  InvalidPtD  : TPointD = (X: invalidD; Y: invalidD);
  NullRectD   : TRectD = (Left: 0; Top: 0; Right: 0; Bottom: 0);
  InvalidRectD: TRectD =
    (Left: invalidD; Top: invalidD; Right: invalidD; Bottom: invalidD);

// Constructors. The overloads exist so both styles compile:
//   RectD(l, t, r, b) and TRectD.Create(l, t, r, b).
function PointD(const AX, AY: Double): TPointD; overload;
function RectD(const ALeft, ATop, ARight, ABottom: Double): TRectD; overload;

// Polygon helpers used by the path facade.
function GetBounds(const APaths: TPathsD): TRectD; overload;
function GetBounds(const APath: TPathD): TRectD; overload;
function Area(const APath: TPathD): Double; overload;
function Area(const APaths: TPathsD): Double; overload;
function PointInPolygon(const APt: TPointD; const APolygon: TPathD;
  AFillRule: TFillRule = frNonZero): Boolean;
function IsPositivePath(const APath: TPathD): Boolean;

implementation

// ---------------------------------------------------------------------------
// TPointD
// ---------------------------------------------------------------------------

class function TPointD.Create(const AX, AY: Double): TPointD;
begin
  Result.X := AX;
  Result.Y := AY;
end;

// ---------------------------------------------------------------------------
// TRectD
// ---------------------------------------------------------------------------

class function TRectD.Create(const ALeft, ATop, ARight, ABottom: Double): TRectD;
begin
  Result.Left   := ALeft;
  Result.Top    := ATop;
  Result.Right  := ARight;
  Result.Bottom := ABottom;
end;

function TRectD.GetWidth(): Double;
begin
  Result := Right - Left;
end;

function TRectD.GetHeight(): Double;
begin
  Result := Bottom - Top;
end;

function TRectD.GetIsEmpty(): Boolean;
begin
  Result := (Bottom <= Top) or (Right <= Left);
end;

function TRectD.GetIsValid(): Boolean;
begin
  Result := Left <> invalidD;
end;

function TRectD.GetMidPoint(): TPointD;
begin
  Result := PointD((Left + Right) * 0.5, (Top + Bottom) * 0.5);
end;

function TRectD.Contains(const APt: TPointD): Boolean;
begin
  Result := (APt.X > Left) and (APt.X < Right) and
            (APt.Y > Top) and (APt.Y < Bottom);
end;

function TRectD.Contains(const ARect: TRectD): Boolean;
begin
  Result := (ARect.Left >= Left) and (ARect.Right <= Right) and
            (ARect.Top >= Top) and (ARect.Bottom <= Bottom);
end;

function TRectD.Intersects(const ARect: TRectD): Boolean;
begin
  Result := (Max(Left, ARect.Left) <= Min(Right, ARect.Right)) and
            (Max(Top, ARect.Top) <= Min(Bottom, ARect.Bottom));
end;

function TRectD.AsPath(): TPathD;
begin
  SetLength(Result, 4);
  Result[0] := PointD(Left, Top);
  Result[1] := PointD(Right, Top);
  Result[2] := PointD(Right, Bottom);
  Result[3] := PointD(Left, Bottom);
end;

// ---------------------------------------------------------------------------
// Constructors
// ---------------------------------------------------------------------------

function PointD(const AX, AY: Double): TPointD;
begin
  Result.X := AX;
  Result.Y := AY;
end;

function RectD(const ALeft, ATop, ARight, ABottom: Double): TRectD;
begin
  Result.Left   := ALeft;
  Result.Top    := ATop;
  Result.Right  := ARight;
  Result.Bottom := ABottom;
end;

// ---------------------------------------------------------------------------
// Polygon helpers
// ---------------------------------------------------------------------------

function GetBounds(const APaths: TPathsD): TRectD;
var
  I, J: Integer;
begin
  Result := RectD(MaxDouble, MaxDouble, -MaxDouble, -MaxDouble);
  for I := 0 to High(APaths) do
  begin
    if Length(APaths[I]) = 0 then
      Continue;
    for J := 0 to High(APaths[I]) do
    begin
      if APaths[I][J].X < Result.Left then Result.Left := APaths[I][J].X;
      if APaths[I][J].X > Result.Right then Result.Right := APaths[I][J].X;
      if APaths[I][J].Y < Result.Top then Result.Top := APaths[I][J].Y;
      if APaths[I][J].Y > Result.Bottom then Result.Bottom := APaths[I][J].Y;
    end;
  end;
  if Result.Left = MaxDouble then
    Result := NullRectD;
end;

function GetBounds(const APath: TPathD): TRectD;
var
  Paths: TPathsD;
begin
  SetLength(Paths, 1);
  Paths[0] := APath;
  Result := GetBounds(Paths);
end;

function Area(const APath: TPathD): Double;
var
  I, HighI: Integer;
  P1, P2: PPointD;
begin
  // Shoelace formula, evaluated exactly as the clipping engine did so that
  // parity tests compare identical numbers.
  Result := 0.0;
  HighI := High(APath);
  if HighI < 2 then
    Exit;

  P1 := @APath[HighI];
  P2 := @APath[0];
  for I := 0 to HighI do
  begin
    Result := Result + (P1^.Y + P2^.Y) * (P1^.X - P2^.X);
    P1 := P2;
    Inc(P2);
  end;
  Result := Result * 0.5;
end;

function Area(const APaths: TPathsD): Double;
var
  I: Integer;
begin
  Result := 0.0;
  for I := 0 to High(APaths) do
    Result := Result + Area(APaths[I]);
end;

function IsPositivePath(const APath: TPathD): Boolean;
begin
  Result := (Area(APath) >= 0);
end;

// Ray casting for even-odd, plus an independent signed-crossing winding number
// for the nonzero/positive/negative rules. Boundary points count as inside.
function PointInPolygon(const APt: TPointD; const APolygon: TPathD;
  AFillRule: TFillRule): Boolean;
var
  I, J, N: Integer;
  Winding, Crossings: Integer;
  P1, P2: TPointD;
  Cross, XIntersect: Double;
begin
  Result := False;
  N := Length(APolygon);
  if N < 3 then
    Exit;

  Winding := 0;
  Crossings := 0;

  J := N - 1;
  for I := 0 to N - 1 do
  begin
    P1 := APolygon[J];
    P2 := APolygon[I];

    Cross := (P2.X - P1.X) * (APt.Y - P1.Y) - (P2.Y - P1.Y) * (APt.X - P1.X);

    // On-edge test: treat boundary points as inside.
    if Abs(Cross) < 1e-12 then
    begin
      if (APt.X >= Min(P1.X, P2.X)) and (APt.X <= Max(P1.X, P2.X)) and
         (APt.Y >= Min(P1.Y, P2.Y)) and (APt.Y <= Max(P1.Y, P2.Y)) then
      begin
        Result := True;
        Exit;
      end;
    end;

    // Even-odd crossing count: cast a ray towards +X.
    if ((P1.Y <= APt.Y) and (P2.Y > APt.Y)) or
       ((P2.Y <= APt.Y) and (P1.Y > APt.Y)) then
    begin
      XIntersect := P1.X + (APt.Y - P1.Y) * (P2.X - P1.X) / (P2.Y - P1.Y);
      if XIntersect > APt.X then
        Inc(Crossings);
    end;

    // Winding number: signed crossings, counted independently of the ray.
    if P1.Y <= APt.Y then
    begin
      if (P2.Y > APt.Y) and (Cross > 0) then
        Inc(Winding);
    end
    else
    begin
      if (P2.Y <= APt.Y) and (Cross < 0) then
        Dec(Winding);
    end;

    J := I;
  end;

  case AFillRule of
    frEvenOdd : Result := (Crossings mod 2) <> 0;
    frNonZero : Result := Winding <> 0;
    frPositive: Result := Winding > 0;
    frNegative: Result := Winding < 0;
  end;
end;

end.
