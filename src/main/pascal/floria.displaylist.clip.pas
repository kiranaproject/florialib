unit Floria.DisplayList.Clip;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  Classes, SysUtils, Math,
  Floria.Path.Clipper.Core,
  Floria.DisplayList;

type
  // ---------------------------------------------------------------------------
  // Analytical Clip Types
  // ---------------------------------------------------------------------------
  TFloriaClipKind = (
    fckNone,
    fckRect,
    fckRoundedRect
  );

  TFloriaClipTestResult = (
    ctrOutside,     // Completely outside: geometry is 100% culled
    ctrInside,      // Completely inside all clips: geometry needs NO clipping
    ctrIntersecting // Straddles boundary: clipping must be evaluated
  );

  // Corner radii for 4 distinct corners (TopLeft, TopRight, BottomRight, BottomLeft)
  TFloriaClipCornerRadii = record
    TopLeftX, TopLeftY        : Double;
    TopRightX, TopRightY      : Double;
    BottomRightX, BottomRightY: Double;
    BottomLeftX, BottomLeftY  : Double;

    class function Uniform(Radius: Double): TFloriaClipCornerRadii; static;
    class function Rounded(RadiusX, RadiusY: Double): TFloriaClipCornerRadii; static;
    class function TopBottom(TopRad, BottomRad: Double): TFloriaClipCornerRadii; static;
    class function Zero(): TFloriaClipCornerRadii; static;
    function IsUniform(): Boolean;
    function HasRoundedCorners(): Boolean;
  end;

  // Single clip node in analytical chain
  TFloriaClipNode = record
    Kind       : TFloriaClipKind;
    Rect       : TRectD;                // Local rect
    Radii      : TFloriaClipCornerRadii;
    ParentIndex: Integer;               // -1 if root
    AntiAlias  : Boolean;
    Transform  : TFloriaMatrix2D;       // Matrix mapping local to root coordinates
    RootBounds : TRectD;                // Conservative bounding box in root space
  end;

  TFloriaClipNodeArray = array of TFloriaClipNode;

  // ---------------------------------------------------------------------------
  // GPU Uniform Packing (64-byte std140 compatible structure)
  // ---------------------------------------------------------------------------
  TFloriaGPUClipItem = packed record
    // vec4: Rect bounding box (MinX, MinY, MaxX, MaxY)
    RectMinX, RectMinY, RectMaxX, RectMaxY: Single;
    // vec4: Top-Left (X, Y) and Top-Right (X, Y) radii
    RadiiTL_X, RadiiTL_Y, RadiiTR_X, RadiiTR_Y: Single;
    // vec4: Bottom-Right (X, Y) and Bottom-Left (X, Y) radii
    RadiiBR_X, RadiiBR_Y, RadiiBL_X, RadiiBL_Y: Single;
    // vec4: ClipKind (1.0 = Rect, 2.0 = RoundedRect), AntiAlias (1.0 = AA, 0.0 = Non-AA), padding
    ClipKind, AntiAlias, Padding1, Padding2: Single;
  end;

  TFloriaGPUClipItemArray = array of TFloriaGPUClipItem;

  // ---------------------------------------------------------------------------
  // TFloriaClipChain
  // ---------------------------------------------------------------------------
  // Represents a stack of analytical clipping primitives. Evaluates point
  // containment, signed distance fields, conservative intersection,
  // and packs GPU uniform buffers.
  // ---------------------------------------------------------------------------
  TFloriaClipChain = class
  private
    FNodes      : TFloriaClipNodeArray;
    FCount      : Integer;
    FCapacity   : Integer;
    FCurrentNode: Integer; // Index of the top of the stack, -1 if empty

    procedure EnsureCapacity(AAdditional: Integer = 1);
  public
    constructor Create();
    destructor Destroy(); override;

    procedure Clear();
    function PushClipRect(const ARect: TRectD; const ATransform: TFloriaMatrix2D; AAntiAlias: Boolean = True): Integer; overload;
    function PushClipRect(const ARect: TRectD; AAntiAlias: Boolean = True): Integer; overload;
    function PushClipRoundedRect(const ARect: TRectD; const ARadii: TFloriaClipCornerRadii;
                                 const ATransform: TFloriaMatrix2D; AAntiAlias: Boolean = True): Integer; overload;
    function PushClipRoundedRect(const ARect: TRectD; ARadiusX, ARadiusY: Double; AAntiAlias: Boolean = True): Integer; overload;
    function PushClipRoundedRect(const ARect: TRectD; ARadius: Double; AAntiAlias: Boolean = True): Integer; overload;
    procedure PopClip();

    // --- Analytical Evaluation ---
    function ContainsPoint(X, Y: Double): Boolean;
    function SignedDistance(X, Y: Double): Double;
    function TestRect(const ARect: TRectD): TFloriaClipTestResult;
    function GetConservativeBounds(): TRectD;

    // --- GPU Uniform Buffer Packing ---
    function PackGPUUniforms(out AItems: TFloriaGPUClipItemArray): Integer;
    function PackGPUUniformsForNode(ANodeIndex: Integer; out AItems: TFloriaGPUClipItemArray): Integer;

    property Count      : Integer read FCount;
    property CurrentNode: Integer read FCurrentNode;
  end;

// Analytical geometry functions
function ClipCornerRadii(Radius: Double): TFloriaClipCornerRadii; overload;
function ClipCornerRadii(RadiusX, RadiusY: Double): TFloriaClipCornerRadii; overload;
function ClipCornerRadii(TL_X, TL_Y, TR_X, TR_Y, BR_X, BR_Y, BL_X, BL_Y: Double): TFloriaClipCornerRadii; overload;

function AnalyticalPointInRoundedRect(X, Y: Double; const ARect: TRectD; const ARadii: TFloriaClipCornerRadii): Boolean;
function AnalyticalRoundedRectSDF(X, Y: Double; const ARect: TRectD; const ARadii: TFloriaClipCornerRadii): Double;

implementation

// -----------------------------------------------------------------------------
// TFloriaClipCornerRadii Implementation
// -----------------------------------------------------------------------------
class function TFloriaClipCornerRadii.Uniform(Radius: Double): TFloriaClipCornerRadii;
begin
  Result := Rounded(Radius, Radius);
end;

class function TFloriaClipCornerRadii.Rounded(RadiusX, RadiusY: Double): TFloriaClipCornerRadii;
begin
  Result.TopLeftX     := RadiusX; Result.TopLeftY     := RadiusY;
  Result.TopRightX    := RadiusX; Result.TopRightY    := RadiusY;
  Result.BottomRightX := RadiusX; Result.BottomRightY := RadiusY;
  Result.BottomLeftX  := RadiusX; Result.BottomLeftY  := RadiusY;
end;

class function TFloriaClipCornerRadii.TopBottom(TopRad, BottomRad: Double): TFloriaClipCornerRadii;
begin
  Result.TopLeftX     := TopRad;    Result.TopLeftY     := TopRad;
  Result.TopRightX    := TopRad;    Result.TopRightY    := TopRad;
  Result.BottomRightX := BottomRad; Result.BottomRightY := BottomRad;
  Result.BottomLeftX  := BottomRad; Result.BottomLeftY  := BottomRad;
end;

class function TFloriaClipCornerRadii.Zero(): TFloriaClipCornerRadii;
begin
  FillChar(Result, SizeOf(Result), 0);
end;

function TFloriaClipCornerRadii.IsUniform(): Boolean;
begin
  Result := (Abs(TopLeftX - TopLeftY) < 1e-6) and
            (Abs(TopLeftX - TopRightX) < 1e-6) and
            (Abs(TopLeftX - TopRightY) < 1e-6) and
            (Abs(TopLeftX - BottomRightX) < 1e-6) and
            (Abs(TopLeftX - BottomRightY) < 1e-6) and
            (Abs(TopLeftX - BottomLeftX) < 1e-6) and
            (Abs(TopLeftX - BottomLeftY) < 1e-6);
end;

function TFloriaClipCornerRadii.HasRoundedCorners(): Boolean;
begin
  Result := (TopLeftX > 0.0) or (TopLeftY > 0.0) or
            (TopRightX > 0.0) or (TopRightY > 0.0) or
            (BottomRightX > 0.0) or (BottomRightY > 0.0) or
            (BottomLeftX > 0.0) or (BottomLeftY > 0.0);
end;

function ClipCornerRadii(Radius: Double): TFloriaClipCornerRadii;
begin
  Result := TFloriaClipCornerRadii.Uniform(Radius);
end;

function ClipCornerRadii(RadiusX, RadiusY: Double): TFloriaClipCornerRadii;
begin
  Result := TFloriaClipCornerRadii.Rounded(RadiusX, RadiusY);
end;

function ClipCornerRadii(TL_X, TL_Y, TR_X, TR_Y, BR_X, BR_Y, BL_X, BL_Y: Double): TFloriaClipCornerRadii;
begin
  Result.TopLeftX     := TL_X; Result.TopLeftY     := TL_Y;
  Result.TopRightX    := TR_X; Result.TopRightY    := TR_Y;
  Result.BottomRightX := BR_X; Result.BottomRightY := BR_Y;
  Result.BottomLeftX  := BL_X; Result.BottomLeftY  := BL_Y;
end;

// -----------------------------------------------------------------------------
// Analytical Point in Rounded Rect
// -----------------------------------------------------------------------------
function AnalyticalPointInRoundedRect(X, Y: Double; const ARect: TRectD; const ARadii: TFloriaClipCornerRadii): Boolean;
var
  Dx, Dy: Double;
begin
  // 1. Outside outer bounding box
  if (X < ARect.Left) or (X > ARect.Right) or (Y < ARect.Top) or (Y > ARect.Bottom) then
    Exit(False);

  if not ARadii.HasRoundedCorners() then
    Exit(True);

  // 2. Top-Left Corner
  if (X < ARect.Left + ARadii.TopLeftX) and (Y < ARect.Top + ARadii.TopLeftY) then
  begin
    if (ARadii.TopLeftX <= 0.0) or (ARadii.TopLeftY <= 0.0) then Exit(True);
    Dx := (X - (ARect.Left + ARadii.TopLeftX)) / ARadii.TopLeftX;
    Dy := (Y - (ARect.Top + ARadii.TopLeftY)) / ARadii.TopLeftY;
    Exit((Dx * Dx + Dy * Dy) <= 1.0);
  end;

  // 3. Top-Right Corner
  if (X > ARect.Right - ARadii.TopRightX) and (Y < ARect.Top + ARadii.TopRightY) then
  begin
    if (ARadii.TopRightX <= 0.0) or (ARadii.TopRightY <= 0.0) then Exit(True);
    Dx := (X - (ARect.Right - ARadii.TopRightX)) / ARadii.TopRightX;
    Dy := (Y - (ARect.Top + ARadii.TopRightY)) / ARadii.TopRightY;
    Exit((Dx * Dx + Dy * Dy) <= 1.0);
  end;

  // 4. Bottom-Right Corner
  if (X > ARect.Right - ARadii.BottomRightX) and (Y > ARect.Bottom - ARadii.BottomRightY) then
  begin
    if (ARadii.BottomRightX <= 0.0) or (ARadii.BottomRightY <= 0.0) then Exit(True);
    Dx := (X - (ARect.Right - ARadii.BottomRightX)) / ARadii.BottomRightX;
    Dy := (Y - (ARect.Bottom - ARadii.BottomRightY)) / ARadii.BottomRightY;
    Exit((Dx * Dx + Dy * Dy) <= 1.0);
  end;

  // 5. Bottom-Left Corner
  if (X < ARect.Left + ARadii.BottomLeftX) and (Y > ARect.Bottom - ARadii.BottomLeftY) then
  begin
    if (ARadii.BottomLeftX <= 0.0) or (ARadii.BottomLeftY <= 0.0) then Exit(True);
    Dx := (X - (ARect.Left + ARadii.BottomLeftX)) / ARadii.BottomLeftX;
    Dy := (Y - (ARect.Bottom - ARadii.BottomLeftY)) / ARadii.BottomLeftY;
    Exit((Dx * Dx + Dy * Dy) <= 1.0);
  end;

  // Inside the interior central cross
  Result := True;
end;

// -----------------------------------------------------------------------------
// Analytical Rounded Rectangle Signed Distance Field (SDF)
// -----------------------------------------------------------------------------
// Evaluates the exact Euclidean distance from point (X, Y) to the rounded box.
// Negative if inside, zero on boundary, positive if outside.
// -----------------------------------------------------------------------------
function AnalyticalRoundedRectSDF(X, Y: Double; const ARect: TRectD; const ARadii: TFloriaClipCornerRadii): Double;
var
  HalfW, HalfH: Double;
  CenterX, CenterY: Double;
  Px, Py: Double;
  Rx, Ry: Double;
  Qx, Qy: Double;
begin
  HalfW := (ARect.Right - ARect.Left) * 0.5;
  HalfH := (ARect.Bottom - ARect.Top) * 0.5;
  CenterX := ARect.Left + HalfW;
  CenterY := ARect.Top + HalfH;

  Px := X - CenterX;
  Py := Y - CenterY;

  // Select corner radius based on quadrant
  if Px < 0.0 then
  begin
    if Py < 0.0 then
    begin
      Rx := ARadii.TopLeftX; Ry := ARadii.TopLeftY;
    end
    else
    begin
      Rx := ARadii.BottomLeftX; Ry := ARadii.BottomLeftY;
    end;
  end
  else
  begin
    if Py < 0.0 then
    begin
      Rx := ARadii.TopRightX; Ry := ARadii.TopRightY;
    end
    else
    begin
      Rx := ARadii.BottomRightX; Ry := ARadii.BottomRightY;
    end;
  end;

  // Clamp radii to half dimensions
  if Rx > HalfW then Rx := HalfW;
  if Ry > HalfH then Ry := HalfH;

  // Standard 2D box SDF: q = abs(p) - (b - r)
  Qx := Abs(Px) - (HalfW - Rx);
  Qy := Abs(Py) - (HalfH - Ry);

  if (Qx > 0.0) and (Qy > 0.0) then
  begin
    // Corner region: distance to circle arc minus radius
    Result := Sqrt(Qx * Qx + Qy * Qy) - ((Rx + Ry) * 0.5);
  end
  else
  begin
    // Edge / inside region
    Result := Min(Max(Qx, Qy), 0.0) + (Max(Qx, 0.0) + Max(Qy, 0.0)) - ((Rx + Ry) * 0.5);
  end;
end;

// -----------------------------------------------------------------------------
// TFloriaClipChain Implementation
// -----------------------------------------------------------------------------
constructor TFloriaClipChain.Create();
begin
  inherited Create();
  FCount       := 0;
  FCapacity    := 0;
  FCurrentNode := -1;
  SetLength(FNodes, 0);
end;

destructor TFloriaClipChain.Destroy();
begin
  SetLength(FNodes, 0);
  inherited Destroy();
end;

procedure TFloriaClipChain.Clear();
begin
  FCount       := 0;
  FCurrentNode := -1;
end;

procedure TFloriaClipChain.EnsureCapacity(AAdditional: Integer = 1);
var
  NewCap: Integer;
begin
  if FCount + AAdditional > FCapacity then
  begin
    NewCap := Max(16, FCapacity * 2);
    if NewCap < FCount + AAdditional then
      NewCap := FCount + AAdditional + 8;
    SetLength(FNodes, NewCap);
    FCapacity := NewCap;
  end;
end;

function TFloriaClipChain.PushClipRect(const ARect: TRectD; const ATransform: TFloriaMatrix2D; AAntiAlias: Boolean = True): Integer;
var
  Idx: Integer;
begin
  EnsureCapacity(1);
  Idx := FCount;
  Inc(FCount);

  FNodes[Idx].Kind        := fckRect;
  FNodes[Idx].Rect        := ARect;
  FNodes[Idx].Radii       := TFloriaClipCornerRadii.Zero();
  FNodes[Idx].ParentIndex := FCurrentNode;
  FNodes[Idx].AntiAlias   := AAntiAlias;
  FNodes[Idx].Transform   := ATransform;
  FNodes[Idx].RootBounds  := ATransform.TransformRect(ARect);

  FCurrentNode := Idx;
  Result := Idx;
end;

function TFloriaClipChain.PushClipRect(const ARect: TRectD; AAntiAlias: Boolean = True): Integer;
begin
  Result := PushClipRect(ARect, TFloriaMatrix2D.Identity(), AAntiAlias);
end;

function TFloriaClipChain.PushClipRoundedRect(const ARect: TRectD; const ARadii: TFloriaClipCornerRadii;
                                              const ATransform: TFloriaMatrix2D; AAntiAlias: Boolean = True): Integer;
var
  Idx: Integer;
begin
  EnsureCapacity(1);
  Idx := FCount;
  Inc(FCount);

  FNodes[Idx].Kind        := fckRoundedRect;
  FNodes[Idx].Rect        := ARect;
  FNodes[Idx].Radii       := ARadii;
  FNodes[Idx].ParentIndex := FCurrentNode;
  FNodes[Idx].AntiAlias   := AAntiAlias;
  FNodes[Idx].Transform   := ATransform;
  FNodes[Idx].RootBounds  := ATransform.TransformRect(ARect);

  FCurrentNode := Idx;
  Result := Idx;
end;

function TFloriaClipChain.PushClipRoundedRect(const ARect: TRectD; ARadiusX, ARadiusY: Double; AAntiAlias: Boolean = True): Integer;
begin
  Result := PushClipRoundedRect(ARect, TFloriaClipCornerRadii.Rounded(ARadiusX, ARadiusY),
                                TFloriaMatrix2D.Identity(), AAntiAlias);
end;

function TFloriaClipChain.PushClipRoundedRect(const ARect: TRectD; ARadius: Double; AAntiAlias: Boolean = True): Integer;
begin
  Result := PushClipRoundedRect(ARect, ARadius, ARadius, AAntiAlias);
end;

procedure TFloriaClipChain.PopClip();
begin
  if FCurrentNode >= 0 then
    FCurrentNode := FNodes[FCurrentNode].ParentIndex;
end;

function TFloriaClipChain.ContainsPoint(X, Y: Double): Boolean;
var
  CurIdx: Integer;
  InvMat: TFloriaMatrix2D;
  LocalPt: TPointD;
begin
  CurIdx := FCurrentNode;
  while CurIdx >= 0 do
  begin
    // Transform point from root coordinates to local clip node space
    if FNodes[CurIdx].Transform.IsIdentity() then
      LocalPt := PointD(X, Y)
    else if FNodes[CurIdx].Transform.Invert(InvMat) then
      LocalPt := InvMat.TransformPoint(PointD(X, Y))
    else
      LocalPt := PointD(X, Y);

    case FNodes[CurIdx].Kind of
      fckRect:
      begin
        if (LocalPt.X < FNodes[CurIdx].Rect.Left) or (LocalPt.X > FNodes[CurIdx].Rect.Right) or
           (LocalPt.Y < FNodes[CurIdx].Rect.Top) or (LocalPt.Y > FNodes[CurIdx].Rect.Bottom) then
          Exit(False);
      end;

      fckRoundedRect:
      begin
        if not AnalyticalPointInRoundedRect(LocalPt.X, LocalPt.Y, FNodes[CurIdx].Rect, FNodes[CurIdx].Radii) then
          Exit(False);
      end;
    end;

    CurIdx := FNodes[CurIdx].ParentIndex;
  end;

  Result := True;
end;

function TFloriaClipChain.SignedDistance(X, Y: Double): Double;
var
  CurIdx: Integer;
  MaxDist, D: Double;
  InvMat: TFloriaMatrix2D;
  LocalPt: TPointD;
begin
  if FCurrentNode < 0 then
    Exit(-1e9); // No clipping, deeply inside

  MaxDist := -1e9;
  CurIdx := FCurrentNode;
  while CurIdx >= 0 do
  begin
    if FNodes[CurIdx].Transform.IsIdentity() then
      LocalPt := PointD(X, Y)
    else if FNodes[CurIdx].Transform.Invert(InvMat) then
      LocalPt := InvMat.TransformPoint(PointD(X, Y))
    else
      LocalPt := PointD(X, Y);

    case FNodes[CurIdx].Kind of
      fckRect:
        D := AnalyticalRoundedRectSDF(LocalPt.X, LocalPt.Y, FNodes[CurIdx].Rect, TFloriaClipCornerRadii.Zero());
      fckRoundedRect:
        D := AnalyticalRoundedRectSDF(LocalPt.X, LocalPt.Y, FNodes[CurIdx].Rect, FNodes[CurIdx].Radii);
      else
        D := -1e9;
    end;

    // The intersection of multiple clips corresponds to the maximum signed distance
    if D > MaxDist then
      MaxDist := D;

    CurIdx := FNodes[CurIdx].ParentIndex;
  end;

  Result := MaxDist;
end;

function TFloriaClipChain.GetConservativeBounds(): TRectD;
var
  CurIdx: Integer;
  First: Boolean;
begin
  if FCurrentNode < 0 then
    Exit(NullRectD);

  First := True;
  Result := NullRectD;
  CurIdx := FCurrentNode;

  while CurIdx >= 0 do
  begin
    if First then
    begin
      Result := FNodes[CurIdx].RootBounds;
      First := False;
    end
    else
    begin
      Result.Left   := Max(Result.Left, FNodes[CurIdx].RootBounds.Left);
      Result.Top    := Max(Result.Top, FNodes[CurIdx].RootBounds.Top);
      Result.Right  := Min(Result.Right, FNodes[CurIdx].RootBounds.Right);
      Result.Bottom := Min(Result.Bottom, FNodes[CurIdx].RootBounds.Bottom);
    end;
    CurIdx := FNodes[CurIdx].ParentIndex;
  end;
end;

function TFloriaClipChain.TestRect(const ARect: TRectD): TFloriaClipTestResult;
var
  ClipBounds: TRectD;
  CurIdx: Integer;
  P1, P2, P3, P4: Boolean;
begin
  if FCurrentNode < 0 then
    Exit(ctrInside); // No clipping active: 100% inside

  ClipBounds := GetConservativeBounds();
  // 1. Outside check against conservative bounding box
  if not ARect.Intersects(ClipBounds) then
    Exit(ctrOutside);

  // 2. Check 4 corners of ARect
  P1 := ContainsPoint(ARect.Left, ARect.Top);
  P2 := ContainsPoint(ARect.Right, ARect.Top);
  P3 := ContainsPoint(ARect.Right, ARect.Bottom);
  P4 := ContainsPoint(ARect.Left, ARect.Bottom);

  if P1 and P2 and P3 and P4 then
  begin
    // All 4 corners are inside.
    // Check if any clip boundary is inside the rect
    CurIdx := FCurrentNode;
    while CurIdx >= 0 do
    begin
      // If any clip boundary edge penetrates ARect
      if (FNodes[CurIdx].RootBounds.Left > ARect.Left) or
         (FNodes[CurIdx].RootBounds.Right < ARect.Right) or
         (FNodes[CurIdx].RootBounds.Top > ARect.Top) or
         (FNodes[CurIdx].RootBounds.Bottom < ARect.Bottom) then
        Exit(ctrIntersecting);
      CurIdx := FNodes[CurIdx].ParentIndex;
    end;
    Exit(ctrInside);
  end;

  if (not P1) and (not P2) and (not P3) and (not P4) then
  begin
    // Corners are outside, but might straddle
    if ARect.Intersects(ClipBounds) then
      Exit(ctrIntersecting)
    else
      Exit(ctrOutside);
  end;

  Result := ctrIntersecting;
end;

function TFloriaClipChain.PackGPUUniformsForNode(ANodeIndex: Integer; out AItems: TFloriaGPUClipItemArray): Integer;
var
  CurIdx, ItemCount: Integer;
  TempList: array of Integer;
  I, N: Integer;
begin
  if (ANodeIndex < 0) or (ANodeIndex >= FCount) then
  begin
    SetLength(AItems, 0);
    Exit(0);
  end;

  // Collect path from root down to ANodeIndex
  ItemCount := 0;
  SetLength(TempList, 16);
  CurIdx := ANodeIndex;
  while CurIdx >= 0 do
  begin
    if ItemCount >= Length(TempList) then
      SetLength(TempList, Length(TempList) * 2);
    TempList[ItemCount] := CurIdx;
    Inc(ItemCount);
    CurIdx := FNodes[CurIdx].ParentIndex;
  end;

  SetLength(AItems, ItemCount);
  // Pack in root-to-leaf order
  for I := 0 to ItemCount - 1 do
  begin
    N := TempList[ItemCount - 1 - I];
    AItems[I].RectMinX := FNodes[N].RootBounds.Left;
    AItems[I].RectMinY := FNodes[N].RootBounds.Top;
    AItems[I].RectMaxX := FNodes[N].RootBounds.Right;
    AItems[I].RectMaxY := FNodes[N].RootBounds.Bottom;

    AItems[I].RadiiTL_X := FNodes[N].Radii.TopLeftX;
    AItems[I].RadiiTL_Y := FNodes[N].Radii.TopLeftY;
    AItems[I].RadiiTR_X := FNodes[N].Radii.TopRightX;
    AItems[I].RadiiTR_Y := FNodes[N].Radii.TopRightY;

    AItems[I].RadiiBR_X := FNodes[N].Radii.BottomRightX;
    AItems[I].RadiiBR_Y := FNodes[N].Radii.BottomRightY;
    AItems[I].RadiiBL_X := FNodes[N].Radii.BottomLeftX;
    AItems[I].RadiiBL_Y := FNodes[N].Radii.BottomLeftY;

    if FNodes[N].Kind = fckRect then
      AItems[I].ClipKind := 1.0
    else
      AItems[I].ClipKind := 2.0;

    if FNodes[N].AntiAlias then
      AItems[I].AntiAlias := 1.0
    else
      AItems[I].AntiAlias := 0.0;

    AItems[I].Padding1 := 0.0;
    AItems[I].Padding2 := 0.0;
  end;

  Result := ItemCount;
end;

function TFloriaClipChain.PackGPUUniforms(out AItems: TFloriaGPUClipItemArray): Integer;
begin
  Result := PackGPUUniformsForNode(FCurrentNode, AItems);
end;

end.
