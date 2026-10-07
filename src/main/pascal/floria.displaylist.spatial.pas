unit Floria.DisplayList.Spatial;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  Classes, SysUtils, Math,
  Floria.Path.Clipper.Core,
  Floria.Image.Core,
  Floria.Canvas.Agg,
  Floria.DisplayList,
  Floria.DisplayList.Clip;

const
  RTREE_MAX_ENTRIES = 8;
  RTREE_MIN_ENTRIES = 2;

type
  // Dynamic array of integers
  TIntegerDynArray = array of Integer;

  // Forward declarations
  TFloriaRTreeNode = class;
  TFloriaRTree2D = class;
  TFloriaSpatialDisplayList = class;

  // ---------------------------------------------------------------------------
  // R-Tree Entry Record
  // ---------------------------------------------------------------------------
  TFloriaRTreeEntry = record
    Bounds: TRectD;
    Data  : Integer;          // Payload (e.g. Operation index)
    Child : TFloriaRTreeNode; // Nil if leaf
  end;

  // ---------------------------------------------------------------------------
  // R-Tree Node Class
  // ---------------------------------------------------------------------------
  TFloriaRTreeNode = class
  public
    Entries: array[0..RTREE_MAX_ENTRIES] of TFloriaRTreeEntry;
    Count  : Integer;
    IsLeaf : Boolean;
    Level  : Integer; // 0 for leaf nodes, >0 for internal branches

    constructor Create(AIsLeaf: Boolean; ALevel: Integer);
    destructor Destroy(); override;

    function CalculateBounds(): TRectD;
    procedure AddEntry(const AEntry: TFloriaRTreeEntry);
  end;

  // ---------------------------------------------------------------------------
  // 2D R-Tree Spatial Acceleration Structure
  // ---------------------------------------------------------------------------
  TFloriaRTree2D = class
  private
    FRoot       : TFloriaRTreeNode;
    FItemCount  : Integer;

    function ChooseChildIndex(ANode: TFloriaRTreeNode; const ABounds: TRectD): Integer;
    function InsertRecursive(ANode: TFloriaRTreeNode; const AEntry: TFloriaRTreeEntry; out ASplitChild: TFloriaRTreeNode): Boolean;
    function SplitNode(ANode: TFloriaRTreeNode; out ANewNode: TFloriaRTreeNode): Boolean;
    procedure SearchNode(ANode: TFloriaRTreeNode; const AQueryRect: TRectD; var AResults: TIntegerDynArray; var AResultCount: Integer);
    function GetHeight(): Integer;
    function GetTotalBounds(): TRectD;
  public
    constructor Create();
    destructor Destroy(); override;

    procedure Clear();
    procedure Insert(const ABounds: TRectD; AData: Integer);
    function Search(const AQueryRect: TRectD): TIntegerDynArray;

    // Bulk loading
    class function BuildFromPicture(APicture: TFloriaPicture): TFloriaRTree2D; static;

    property Count      : Integer read FItemCount;
    property Height     : Integer read GetHeight;
    property TotalBounds: TRectD read GetTotalBounds;
    property Root       : TFloriaRTreeNode read FRoot;
  end;

  // ---------------------------------------------------------------------------
  // TFloriaSpatialDisplayList
  // ---------------------------------------------------------------------------
  // Retained picture combined with an R-Tree spatial index for O(log N)
  // damage-region queries and viewport culling.
  // ---------------------------------------------------------------------------
  TFloriaSpatialDisplayList = class
  private
    FPicture    : TFloriaPicture;
    FIndex      : TFloriaRTree2D;
    FOwnsPicture: Boolean;
  public
    constructor Create(APicture: TFloriaPicture; AOwnsPicture: Boolean = False);
    destructor Destroy(); override;

    function QueryVisibleOps(const AViewport: TRectD): TIntegerDynArray;
    procedure PlaybackViewport(ACanvas: TFloriaCanvasAgg; const AViewport: TRectD);

    property Picture: TFloriaPicture read FPicture;
    property Index  : TFloriaRTree2D read FIndex;
  end;

// Rect math helpers
function RTreeRectArea(const R: TRectD): Double;
function RTreeRectUnion(const R1, R2: TRectD): TRectD;
function RTreeEnlargementArea(const RBase, RAdd: TRectD): Double;

implementation

// -----------------------------------------------------------------------------
// Bounding Box Geometry Helpers
// -----------------------------------------------------------------------------
function RTreeRectArea(const R: TRectD): Double;
begin
  if (R.Right <= R.Left) or (R.Bottom <= R.Top) then
    Result := 0.0
  else
    Result := (R.Right - R.Left) * (R.Bottom - R.Top);
end;

function RTreeRectUnion(const R1, R2: TRectD): TRectD;
begin
  if R1.IsEmpty then Exit(R2);
  if R2.IsEmpty then Exit(R1);

  Result.Left   := Min(R1.Left, R2.Left);
  Result.Top    := Min(R1.Top, R2.Top);
  Result.Right  := Max(R1.Right, R2.Right);
  Result.Bottom := Max(R1.Bottom, R2.Bottom);
end;

function RTreeEnlargementArea(const RBase, RAdd: TRectD): Double;
var
  Combined: TRectD;
begin
  if RBase.IsEmpty then
    Exit(RTreeRectArea(RAdd));

  Combined := RTreeRectUnion(RBase, RAdd);
  Result := RTreeRectArea(Combined) - RTreeRectArea(RBase);
  if Result < 0.0 then Result := 0.0;
end;

// -----------------------------------------------------------------------------
// TFloriaRTreeNode Implementation
// -----------------------------------------------------------------------------
constructor TFloriaRTreeNode.Create(AIsLeaf: Boolean; ALevel: Integer);
begin
  inherited Create();
  Count  := 0;
  IsLeaf := AIsLeaf;
  Level  := ALevel;
  FillChar(Entries, SizeOf(Entries), 0);
end;

destructor TFloriaRTreeNode.Destroy();
var
  I: Integer;
begin
  if not IsLeaf then
  begin
    for I := 0 to Count - 1 do
      if Assigned(Entries[I].Child) then
        FreeAndNil(Entries[I].Child);
  end;
  inherited Destroy();
end;

function TFloriaRTreeNode.CalculateBounds(): TRectD;
var
  I: Integer;
begin
  if Count = 0 then
    Exit(NullRectD);

  Result := Entries[0].Bounds;
  for I := 1 to Count - 1 do
    Result := RTreeRectUnion(Result, Entries[I].Bounds);
end;

procedure TFloriaRTreeNode.AddEntry(const AEntry: TFloriaRTreeEntry);
begin
  Entries[Count] := AEntry;
  Inc(Count);
end;

// -----------------------------------------------------------------------------
// TFloriaRTree2D Implementation
// -----------------------------------------------------------------------------
constructor TFloriaRTree2D.Create();
begin
  inherited Create();
  FRoot      := TFloriaRTreeNode.Create(True, 0);
  FItemCount := 0;
end;

destructor TFloriaRTree2D.Destroy();
begin
  if Assigned(FRoot) then
    FreeAndNil(FRoot);
  inherited Destroy();
end;

procedure TFloriaRTree2D.Clear();
begin
  if Assigned(FRoot) then
    FreeAndNil(FRoot);
  FRoot      := TFloriaRTreeNode.Create(True, 0);
  FItemCount := 0;
end;

function TFloriaRTree2D.GetHeight(): Integer;
begin
  if Assigned(FRoot) then
    Result := FRoot.Level + 1
  else
    Result := 0;
end;

function TFloriaRTree2D.GetTotalBounds(): TRectD;
begin
  if Assigned(FRoot) then
    Result := FRoot.CalculateBounds()
  else
    Result := NullRectD;
end;

function TFloriaRTree2D.ChooseChildIndex(ANode: TFloriaRTreeNode; const ABounds: TRectD): Integer;
var
  I: Integer;
  BestIdx: Integer;
  MinEnlargement, Enlargement: Double;
  MinArea, Area: Double;
begin
  BestIdx := 0;
  MinEnlargement := 1e30;
  MinArea := 1e30;

  for I := 0 to ANode.Count - 1 do
  begin
    Enlargement := RTreeEnlargementArea(ANode.Entries[I].Bounds, ABounds);
    Area := RTreeRectArea(ANode.Entries[I].Bounds);

    if (Enlargement < MinEnlargement) or
       ((Abs(Enlargement - MinEnlargement) < 1e-9) and (Area < MinArea)) then
    begin
      MinEnlargement := Enlargement;
      MinArea := Area;
      BestIdx := I;
    end;
  end;

  Result := BestIdx;
end;

function TFloriaRTree2D.SplitNode(ANode: TFloriaRTreeNode; out ANewNode: TFloriaRTreeNode): Boolean;
var
  I, J, K: Integer;
  Seed1, Seed2: Integer;
  MaxWaste, Waste: Double;
  CombinedArea: Double;
  Taken: array[0..RTREE_MAX_ENTRIES] of Boolean;
  TotalEntries: Integer;
  Group1Bounds, Group2Bounds: TRectD;
  G1Count, G2Count: Integer;
  TempEntries: array[0..RTREE_MAX_ENTRIES] of TFloriaRTreeEntry;
  NextIdx: Integer;
  MaxDiff, Diff: Double;
  D1, D2: Double;
begin
  TotalEntries := ANode.Count;
  if TotalEntries <= RTREE_MAX_ENTRIES then
  begin
    ANewNode := nil;
    Exit(False);
  end;

  for I := 0 to TotalEntries - 1 do
    TempEntries[I] := ANode.Entries[I];

  FillChar(Taken, SizeOf(Taken), False);

  // 1. Quadratic PickSeeds
  Seed1 := 0;
  Seed2 := 1;
  MaxWaste := -1e30;

  for I := 0 to TotalEntries - 1 do
  begin
    for J := I + 1 to TotalEntries - 1 do
    begin
      CombinedArea := RTreeRectArea(RTreeRectUnion(TempEntries[I].Bounds, TempEntries[J].Bounds));
      Waste := CombinedArea - RTreeRectArea(TempEntries[I].Bounds) - RTreeRectArea(TempEntries[J].Bounds);
      if Waste > MaxWaste then
      begin
        MaxWaste := Waste;
        Seed1 := I;
        Seed2 := J;
      end;
    end;
  end;

  ANewNode := TFloriaRTreeNode.Create(ANode.IsLeaf, ANode.Level);
  ANode.Count := 0;

  // Add initial seeds
  ANode.AddEntry(TempEntries[Seed1]);
  Group1Bounds := TempEntries[Seed1].Bounds;
  Taken[Seed1] := True;
  G1Count := 1;

  ANewNode.AddEntry(TempEntries[Seed2]);
  Group2Bounds := TempEntries[Seed2].Bounds;
  Taken[Seed2] := True;
  G2Count := 1;

  // 2. Distribute remaining entries
  while (G1Count + G2Count < TotalEntries) do
  begin
    // Check if one group needs all remaining entries to satisfy minimum
    if (TotalEntries - (G1Count + G2Count)) = (RTREE_MIN_ENTRIES - G1Count) then
    begin
      for K := 0 to TotalEntries - 1 do
        if not Taken[K] then
        begin
          ANode.AddEntry(TempEntries[K]);
          Group1Bounds := RTreeRectUnion(Group1Bounds, TempEntries[K].Bounds);
          Taken[K] := True;
          Inc(G1Count);
        end;
      Break;
    end;

    if (TotalEntries - (G1Count + G2Count)) = (RTREE_MIN_ENTRIES - G2Count) then
    begin
      for K := 0 to TotalEntries - 1 do
        if not Taken[K] then
        begin
          ANewNode.AddEntry(TempEntries[K]);
          Group2Bounds := RTreeRectUnion(Group2Bounds, TempEntries[K].Bounds);
          Taken[K] := True;
          Inc(G2Count);
        end;
      Break;
    end;

    // PickNext: find entry with maximum difference in enlargement
    NextIdx := -1;
    MaxDiff := -1.0;

    for K := 0 to TotalEntries - 1 do
    begin
      if not Taken[K] then
      begin
        D1 := RTreeEnlargementArea(Group1Bounds, TempEntries[K].Bounds);
        D2 := RTreeEnlargementArea(Group2Bounds, TempEntries[K].Bounds);
        Diff := Abs(D1 - D2);
        if Diff > MaxDiff then
        begin
          MaxDiff := Diff;
          NextIdx := K;
        end;
      end;
    end;

    if NextIdx >= 0 then
    begin
      D1 := RTreeEnlargementArea(Group1Bounds, TempEntries[NextIdx].Bounds);
      D2 := RTreeEnlargementArea(Group2Bounds, TempEntries[NextIdx].Bounds);

      if D1 < D2 then
      begin
        ANode.AddEntry(TempEntries[NextIdx]);
        Group1Bounds := RTreeRectUnion(Group1Bounds, TempEntries[NextIdx].Bounds);
        Inc(G1Count);
      end
      else if D2 < D1 then
      begin
        ANewNode.AddEntry(TempEntries[NextIdx]);
        Group2Bounds := RTreeRectUnion(Group2Bounds, TempEntries[NextIdx].Bounds);
        Inc(G2Count);
      end
      else
      begin
        // Equal enlargement: choose group with smaller area, then smaller count
        if RTreeRectArea(Group1Bounds) < RTreeRectArea(Group2Bounds) then
        begin
          ANode.AddEntry(TempEntries[NextIdx]);
          Group1Bounds := RTreeRectUnion(Group1Bounds, TempEntries[NextIdx].Bounds);
          Inc(G1Count);
        end
        else
        begin
          ANewNode.AddEntry(TempEntries[NextIdx]);
          Group2Bounds := RTreeRectUnion(Group2Bounds, TempEntries[NextIdx].Bounds);
          Inc(G2Count);
        end;
      end;
      Taken[NextIdx] := True;
    end;
  end;

  Result := True;
end;

function TFloriaRTree2D.InsertRecursive(ANode: TFloriaRTreeNode; const AEntry: TFloriaRTreeEntry; out ASplitChild: TFloriaRTreeNode): Boolean;
var
  BestIdx: Integer;
  ChildSplit: TFloriaRTreeNode;
  NewEntry: TFloriaRTreeEntry;
begin
  if ANode.IsLeaf then
  begin
    ANode.AddEntry(AEntry);
    if ANode.Count > RTREE_MAX_ENTRIES then
      Result := SplitNode(ANode, ASplitChild)
    else
    begin
      ASplitChild := nil;
      Result := False;
    end;
  end
  else
  begin
    BestIdx := ChooseChildIndex(ANode, AEntry.Bounds);
    if InsertRecursive(ANode.Entries[BestIdx].Child, AEntry, ChildSplit) then
    begin
      ANode.Entries[BestIdx].Bounds := ANode.Entries[BestIdx].Child.CalculateBounds();
      NewEntry.Bounds := ChildSplit.CalculateBounds();
      NewEntry.Data   := -1;
      NewEntry.Child  := ChildSplit;
      ANode.AddEntry(NewEntry);

      if ANode.Count > RTREE_MAX_ENTRIES then
        Result := SplitNode(ANode, ASplitChild)
      else
      begin
        ASplitChild := nil;
        Result := False;
      end;
    end
    else
    begin
      ANode.Entries[BestIdx].Bounds := ANode.Entries[BestIdx].Child.CalculateBounds();
      ASplitChild := nil;
      Result := False;
    end;
  end;
end;

procedure TFloriaRTree2D.Insert(const ABounds: TRectD; AData: Integer);
var
  Entry: TFloriaRTreeEntry;
  SplitChild: TFloriaRTreeNode;
  NewRoot: TFloriaRTreeNode;
  E1, E2: TFloriaRTreeEntry;
begin
  Entry.Bounds := ABounds;
  Entry.Data   := AData;
  Entry.Child  := nil;

  if InsertRecursive(FRoot, Entry, SplitChild) then
  begin
    NewRoot := TFloriaRTreeNode.Create(False, FRoot.Level + 1);

    E1.Bounds := FRoot.CalculateBounds();
    E1.Data   := -1;
    E1.Child  := FRoot;
    NewRoot.AddEntry(E1);

    E2.Bounds := SplitChild.CalculateBounds();
    E2.Data   := -1;
    E2.Child  := SplitChild;
    NewRoot.AddEntry(E2);

    FRoot := NewRoot;
  end;

  Inc(FItemCount);
end;

procedure TFloriaRTree2D.SearchNode(ANode: TFloriaRTreeNode; const AQueryRect: TRectD;
                                   var AResults: TIntegerDynArray; var AResultCount: Integer);
var
  I: Integer;
begin
  if not Assigned(ANode) then Exit;

  for I := 0 to ANode.Count - 1 do
  begin
    if ANode.Entries[I].Bounds.Intersects(AQueryRect) then
    begin
      if ANode.IsLeaf then
      begin
        if AResultCount >= Length(AResults) then
          SetLength(AResults, Max(16, Length(AResults) * 2));
        AResults[AResultCount] := ANode.Entries[I].Data;
        Inc(AResultCount);
      end
      else
        SearchNode(ANode.Entries[I].Child, AQueryRect, AResults, AResultCount);
    end;
  end;
end;

function TFloriaRTree2D.Search(const AQueryRect: TRectD): TIntegerDynArray;
var
  ResCount: Integer;
  I, J, Temp: Integer;
begin
  ResCount := 0;
  SetLength(Result, 16);
  SearchNode(FRoot, AQueryRect, Result, ResCount);
  SetLength(Result, ResCount);

  // Sort ascending by operation index to strictly preserve z-order
  for I := 0 to ResCount - 2 do
    for J := I + 1 to ResCount - 1 do
      if Result[I] > Result[J] then
      begin
        Temp := Result[I];
        Result[I] := Result[J];
        Result[J] := Temp;
      end;
end;

class function TFloriaRTree2D.BuildFromPicture(APicture: TFloriaPicture): TFloriaRTree2D;
var
  I: Integer;
  Op: TFloriaDisplayOp;
  IsDraw: Boolean;
begin
  Result := TFloriaRTree2D.Create();
  if not Assigned(APicture) then Exit;

  for I := 0 to APicture.OpCount - 1 do
  begin
    Op := APicture.Op[I];
    IsDraw := Op.OpType in [dopDrawRect, dopDrawRoundedRect, dopDrawCircle, dopDrawLine,
                            dopDrawPath, dopDrawShadow, dopDrawBorder, dopDrawLinearGradient,
                            dopDrawText, dopDrawParagraph, dopDrawImage, dopDrawPicture];

    if IsDraw and not Op.Bounds.IsEmpty then
      Result.Insert(Op.Bounds, I);
  end;
end;

// -----------------------------------------------------------------------------
// TFloriaSpatialDisplayList Implementation
// -----------------------------------------------------------------------------
constructor TFloriaSpatialDisplayList.Create(APicture: TFloriaPicture; AOwnsPicture: Boolean = False);
begin
  inherited Create();
  FPicture     := APicture;
  FOwnsPicture := AOwnsPicture;
  FIndex       := TFloriaRTree2D.BuildFromPicture(APicture);
end;

destructor TFloriaSpatialDisplayList.Destroy();
begin
  if Assigned(FIndex) then
    FreeAndNil(FIndex);
  if FOwnsPicture and Assigned(FPicture) then
    FreeAndNil(FPicture);
  inherited Destroy();
end;

function TFloriaSpatialDisplayList.QueryVisibleOps(const AViewport: TRectD): TIntegerDynArray;
begin
  if Assigned(FIndex) then
    Result := FIndex.Search(AViewport)
  else
    SetLength(Result, 0);
end;

procedure TFloriaSpatialDisplayList.PlaybackViewport(ACanvas: TFloriaCanvasAgg; const AViewport: TRectD);
begin
  if Assigned(FPicture) and Assigned(ACanvas) then
    FPicture.Playback(ACanvas, AViewport);
end;

end.
