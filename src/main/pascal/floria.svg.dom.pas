unit Floria.SVG.DOM;

// Floria.SVG.DOM
// ==============
// Scene graph and typed DOM model for SVG vector documents following
// standard SVG DOM naming (TSVGElement, TSVGSvgElement, TSVGRectElement, etc.).
//
// Highlights:
//   - TSVGStyleRecord: Presentation styles with inheritance and CSS cascade
//   - TSVGElement hierarchy: TSVGContainerElement, TSVGSvgElement, TSVGGroupElement,
//     TSVGDefsElement, TSVGUseElement
//   - TSVGShapeElement hierarchy: TSVGPathElement, TSVGRectElement, TSVGCircleElement,
//     TSVGEllipseElement, TSVGLineElement, TSVGPolylineElement, TSVGPolygonElement
//     (all convert automatically to TSVGPathData)
//   - Gradients: TSVGLinearGradientElement, TSVGRadialGradientElement, TSVGStopElement
//   - TSVGDocument: Complete SVG document container with ID indexing, reference
//     resolution, CSS cascade application, and viewport matrix calculation

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  SysUtils, Classes, Contnrs, Math,
  Floria.CSS.Types, Floria.CSS.Values, Floria.CSS.Properties, Floria.CSS.AST,
  Floria.SVG.Types, Floria.SVG.Path;

type
  // ── Style Record ───────────────────────────────────────────────────────────

  TSVGStyleProperty = (
    sspFill,
    sspFillOpacity,
    sspFillRule,
    sspStroke,
    sspStrokeWidth,
    sspStrokeOpacity,
    sspStrokeLineCap,
    sspStrokeLineJoin,
    sspStrokeMiterLimit,
    sspOpacity,
    sspVisibility,
    sspDisplay
  );
  TSVGStyleProperties = set of TSVGStyleProperty;

  TSVGStyleRecord = record
    Specified: TSVGStyleProperties;
    Fill: TSVGPaint;
    FillOpacity: Double;
    FillRule: TSVGFillRule;
    Stroke: TSVGPaint;
    StrokeWidth: Double;
    StrokeOpacity: Double;
    StrokeLineCap: TSVGLineCap;
    StrokeLineJoin: TSVGLineJoin;
    StrokeMiterLimit: Double;
    Opacity: Double;
    Visibility: TSVGVisibility;
    Display: TSVGDisplay;

    procedure InitDefaults();
    procedure InheritFrom(const AParent: TSVGStyleRecord);
    procedure ApplyPresentationAttribute(const AName, AValue: string);
    procedure ApplyCSSDeclaration(APropId: TCSSPropertyId; AVal: TCSSPropertyValue);
    procedure ApplyCSSBlock(ABlock: TCSSStyleBlock);
  end;

  TSVGElement = class;
  TSVGContainerElement = class;
  TSVGDocument = class;

  // ── Base SVG Element ───────────────────────────────────────────────────────

  TSVGElement = class
  private
    FId: string;
    FTagName: string;
    FParent: TSVGElement;
    FTransform: TSVGMatrix;
    FStyle: TSVGStyleRecord;
    FComputedStyle: TSVGStyleRecord;
    FAccumulatedMatrix: TSVGMatrix;
    FDocument: TSVGDocument;
  public
    constructor Create(const ATagName: string; ADoc: TSVGDocument = nil); virtual;
    destructor Destroy(); override;

    procedure ComputeStyles(const AParentStyle: TSVGStyleRecord; const AParentMatrix: TSVGMatrix); virtual;
    function GetLocalBoundingBox(): TSVGRect; virtual;
    function GetWorldBoundingBox(): TSVGRect;

    property Id: string read FId write FId;
    property TagName: string read FTagName;
    property Parent: TSVGElement read FParent write FParent;
    property Transform: TSVGMatrix read FTransform write FTransform;
    property Style: TSVGStyleRecord read FStyle write FStyle;
    property ComputedStyle: TSVGStyleRecord read FComputedStyle;
    property AccumulatedMatrix: TSVGMatrix read FAccumulatedMatrix;
    property Document: TSVGDocument read FDocument write FDocument;
  end;

  TSVGNode = TSVGElement; // Alias for flexibility

  // ── Container Elements ─────────────────────────────────────────────────────

  TSVGContainerElement = class(TSVGElement)
  private
    FChildren: TObjectList; // Owns objects
  public
    constructor Create(const ATagName: string; ADoc: TSVGDocument = nil); override;
    destructor Destroy(); override;

    procedure AddChild(AChild: TSVGElement);
    function ChildCount(): Integer;
    function GetChild(AIndex: Integer): TSVGElement;
    function FindById(const AId: string): TSVGElement; virtual;

    procedure ComputeStyles(const AParentStyle: TSVGStyleRecord; const AParentMatrix: TSVGMatrix); override;
    function GetLocalBoundingBox(): TSVGRect; override;

    property Children: TObjectList read FChildren;
  end;

  TSVGGroupElement = class(TSVGContainerElement)
  public
    constructor Create(ADoc: TSVGDocument = nil); reintroduce;
  end;

  TSVGDefsElement = class(TSVGContainerElement)
  public
    constructor Create(ADoc: TSVGDocument = nil); reintroduce;
    procedure ComputeStyles(const AParentStyle: TSVGStyleRecord; const AParentMatrix: TSVGMatrix); override;
  end;

  TSVGSvgElement = class(TSVGContainerElement)
  private
    FX: TSVGLength;
    FY: TSVGLength;
    FWidth: TSVGLength;
    FHeight: TSVGLength;
    FViewBox: TSVGViewBox;
    FPreserveAspectRatio: TSVGPreserveAspectRatio;
    FViewBoxTransform: TSVGMatrix;
  public
    constructor Create(ADoc: TSVGDocument = nil); reintroduce;

    procedure ComputeViewBox(TargetW, TargetH: Double);
    procedure ComputeStyles(const AParentStyle: TSVGStyleRecord; const AParentMatrix: TSVGMatrix); override;

    property X: TSVGLength read FX write FX;
    property Y: TSVGLength read FY write FY;
    property Width: TSVGLength read FWidth write FWidth;
    property Height: TSVGLength read FHeight write FHeight;
    property ViewBox: TSVGViewBox read FViewBox write FViewBox;
    property PreserveAspectRatio: TSVGPreserveAspectRatio read FPreserveAspectRatio write FPreserveAspectRatio;
    property ViewBoxTransform: TSVGMatrix read FViewBoxTransform;
  end;

  TSVGUseElement = class(TSVGElement)
  private
    FHref: string;
    FX: TSVGLength;
    FY: TSVGLength;
    FWidth: TSVGLength;
    FHeight: TSVGLength;
    FReferencedElement: TSVGElement;
  public
    constructor Create(ADoc: TSVGDocument = nil); reintroduce;

    procedure ComputeStyles(const AParentStyle: TSVGStyleRecord; const AParentMatrix: TSVGMatrix); override;
    function GetLocalBoundingBox(): TSVGRect; override;

    property Href: string read FHref write FHref;
    property X: TSVGLength read FX write FX;
    property Y: TSVGLength read FY write FY;
    property Width: TSVGLength read FWidth write FWidth;
    property Height: TSVGLength read FHeight write FHeight;
    property ReferencedElement: TSVGElement read FReferencedElement write FReferencedElement;
  end;

  // ── Shape Elements ─────────────────────────────────────────────────────────

  TSVGShapeElement = class(TSVGElement)
  public
    function GetPath(): TSVGPathData; virtual; abstract;
    function GetLocalBoundingBox(): TSVGRect; override;
  end;

  TSVGPathElement = class(TSVGShapeElement)
  private
    FPathData: TSVGPathData;
  public
    constructor Create(ADoc: TSVGDocument = nil); reintroduce;
    destructor Destroy(); override;

    function GetPath(): TSVGPathData; override;
    procedure SetPathData(const AD: string);

    property PathData: TSVGPathData read FPathData;
  end;

  TSVGRectElement = class(TSVGShapeElement)
  private
    FX, FY, FWidth, FHeight, FRx, FRy: TSVGLength;
    FCachedPath: TSVGPathData;
  public
    constructor Create(ADoc: TSVGDocument = nil); reintroduce;
    destructor Destroy(); override;

    function GetPath(): TSVGPathData; override;

    property X: TSVGLength read FX write FX;
    property Y: TSVGLength read FY write FY;
    property Width: TSVGLength read FWidth write FWidth;
    property Height: TSVGLength read FHeight write FHeight;
    property Rx: TSVGLength read FRx write FRx;
    property Ry: TSVGLength read FRy write FRy;
  end;

  TSVGCircleElement = class(TSVGShapeElement)
  private
    FCx, FCy, FR: TSVGLength;
    FCachedPath: TSVGPathData;
  public
    constructor Create(ADoc: TSVGDocument = nil); reintroduce;
    destructor Destroy(); override;

    function GetPath(): TSVGPathData; override;

    property Cx: TSVGLength read FCx write FCx;
    property Cy: TSVGLength read FCy write FCy;
    property R: TSVGLength read FR write FR;
  end;

  TSVGEllipseElement = class(TSVGShapeElement)
  private
    FCx, FCy, FRx, FRy: TSVGLength;
    FCachedPath: TSVGPathData;
  public
    constructor Create(ADoc: TSVGDocument = nil); reintroduce;
    destructor Destroy(); override;

    function GetPath(): TSVGPathData; override;

    property Cx: TSVGLength read FCx write FCx;
    property Cy: TSVGLength read FCy write FCy;
    property Rx: TSVGLength read FRx write FRx;
    property Ry: TSVGLength read FRy write FRy;
  end;

  TSVGLineElement = class(TSVGShapeElement)
  private
    FX1, FY1, FX2, FY2: TSVGLength;
    FCachedPath: TSVGPathData;
  public
    constructor Create(ADoc: TSVGDocument = nil); reintroduce;
    destructor Destroy(); override;

    function GetPath(): TSVGPathData; override;

    property X1: TSVGLength read FX1 write FX1;
    property Y1: TSVGLength read FY1 write FY1;
    property X2: TSVGLength read FX2 write FX2;
    property Y2: TSVGLength read FY2 write FY2;
  end;

  TSVGPointArray = array of TSVGPoint;

  TSVGPolylineElement = class(TSVGShapeElement)
  private
    FPoints: TSVGPointArray;
    FCachedPath: TSVGPathData;
  public
    constructor Create(ADoc: TSVGDocument = nil); reintroduce;
    destructor Destroy(); override;

    function GetPath(): TSVGPathData; override;
    procedure SetPointsString(const S: string);

    property Points: TSVGPointArray read FPoints write FPoints;
  end;

  TSVGPolygonElement = class(TSVGShapeElement)
  private
    FPoints: TSVGPointArray;
    FCachedPath: TSVGPathData;
  public
    constructor Create(ADoc: TSVGDocument = nil); reintroduce;
    destructor Destroy(); override;

    function GetPath(): TSVGPathData; override;
    procedure SetPointsString(const S: string);

    property Points: TSVGPointArray read FPoints write FPoints;
  end;

  // ── Gradients ──────────────────────────────────────────────────────────────

  TSVGGradientSpread = (sgsPad, sgsReflect, sgsRepeat);
  TSVGGradientUnits = (sguUserSpaceOnUse, sguObjectBoundingBox);

  TSVGStopElement = class(TSVGElement)
  private
    FOffset: Double;
    FColor: TCSSColor;
  public
    constructor Create(ADoc: TSVGDocument = nil); reintroduce;

    property Offset: Double read FOffset write FOffset;
    property Color: TCSSColor read FColor write FColor;
  end;

  TSVGGradientElement = class(TSVGElement)
  private
    FGradientUnits: TSVGGradientUnits;
    FSpreadMethod: TSVGGradientSpread;
    FGradientTransform: TSVGMatrix;
    FStops: TObjectList; // TSVGStopElement
    FHref: string;
  public
    constructor Create(const ATagName: string; ADoc: TSVGDocument = nil); override;
    destructor Destroy(); override;

    procedure AddStop(AStop: TSVGStopElement);
    function StopCount(): Integer;
    function GetStop(AIndex: Integer): TSVGStopElement;
    function GetEffectiveStops(): TObjectList;

    property GradientUnits: TSVGGradientUnits read FGradientUnits write FGradientUnits;
    property SpreadMethod: TSVGGradientSpread read FSpreadMethod write FSpreadMethod;
    property GradientTransform: TSVGMatrix read FGradientTransform write FGradientTransform;
    property Stops: TObjectList read FStops;
    property Href: string read FHref write FHref;
  end;

  TSVGLinearGradientElement = class(TSVGGradientElement)
  private
    FX1, FY1, FX2, FY2: TSVGLength;
  public
    constructor Create(ADoc: TSVGDocument = nil); reintroduce;

    property X1: TSVGLength read FX1 write FX1;
    property Y1: TSVGLength read FY1 write FY1;
    property X2: TSVGLength read FX2 write FX2;
    property Y2: TSVGLength read FY2 write FY2;
  end;

  TSVGRadialGradientElement = class(TSVGGradientElement)
  private
    FCx, FCy, FR, FFx, FFy: TSVGLength;
  public
    constructor Create(ADoc: TSVGDocument = nil); reintroduce;

    property Cx: TSVGLength read FCx write FCx;
    property Cy: TSVGLength read FCy write FCy;
    property R: TSVGLength read FR write FR;
    property Fx: TSVGLength read FFx write FFx;
    property Fy: TSVGLength read FFy write FFy;
  end;

  // ── Complete SVG Document ──────────────────────────────────────────────────

  TSVGDocument = class
  private
    FRoot: TSVGSvgElement;
    FIdMap: TStringList; // Maps ID to TSVGElement
    FStylesheets: TObjectList; // Owns TCSSStylesheet
  public
    constructor Create();
    destructor Destroy(); override;

    procedure RegisterElement(const AId: string; AElement: TSVGElement);
    function FindElementById(const AId: string): TSVGElement;
    procedure AddStylesheet(ASheet: TCSSStylesheet);

    procedure ResolveReferences();
    procedure ComputeStyles(TargetW, TargetH: Double);

    function GetIntrinsicWidth(): Double;
    function GetIntrinsicHeight(): Double;

    property Root: TSVGSvgElement read FRoot write FRoot;
    property Stylesheets: TObjectList read FStylesheets;
  end;

implementation

// ── Points Parser Helper ─────────────────────────────────────────────────────

function ParsePoints(const S: string): TSVGPointArray;
var
  I, Len, StartPos, Count: Integer;
  NumStr: string;
  DVal: Double;
  Code: Integer;
  Coords: array of Double;
  J: Integer;
begin
  SetLength(Result, 0);
  Count := 0;
  I := 1;
  Len := Length(S);
  SetLength(Coords, 16);

  while I <= Len do
  begin
    while (I <= Len) and (S[I] in [' ', #9, #10, #13, ',']) do Inc(I);
    if I > Len then Break;

    StartPos := I;
    if S[I] in ['+', '-'] then Inc(I);
    while (I <= Len) and (S[I] in ['0'..'9']) do Inc(I);
    if (I <= Len) and (S[I] = '.') then
    begin
      Inc(I);
      while (I <= Len) and (S[I] in ['0'..'9']) do Inc(I);
    end;
    if (I <= Len) and (S[I] in ['e', 'E']) then
    begin
      Inc(I);
      if (I <= Len) and (S[I] in ['+', '-']) then Inc(I);
      while (I <= Len) and (S[I] in ['0'..'9']) do Inc(I);
    end;

    if I > StartPos then
    begin
      NumStr := Copy(S, StartPos, I - StartPos);
      DVal := 0.0;
      System.Val(NumStr, DVal, Code);
      if Code = 0 then
      begin
        if Count >= Length(Coords) then
          SetLength(Coords, Length(Coords) * 2);
        Coords[Count] := DVal;
        Inc(Count);
      end;
    end
    else
      Inc(I);
  end;

  SetLength(Result, Count div 2);
  for J := 0 to (Count div 2) - 1 do
  begin
    Result[J].X := Coords[J * 2];
    Result[J].Y := Coords[J * 2 + 1];
  end;
end;

// ── TSVGStyleRecord Implementation ───────────────────────────────────────────

procedure TSVGStyleRecord.InitDefaults();
begin
  Specified := [];
  Fill.Kind := pkColor;
  Fill.Color := TCSSColor.Black();
  Fill.UriId := '';
  FillOpacity := 1.0;
  FillRule := sfrNonZero;

  Stroke.Kind := pkNone;
  Stroke.Color := TCSSColor.Transparent();
  Stroke.UriId := '';
  StrokeWidth := 1.0;
  StrokeOpacity := 1.0;
  StrokeLineCap := slcButt;
  StrokeLineJoin := sljMiter;
  StrokeMiterLimit := 4.0;

  Opacity := 1.0;
  Visibility := svVisible;
  Display := sdInline;
end;

procedure TSVGStyleRecord.InheritFrom(const AParent: TSVGStyleRecord);
begin
  if not (sspFill in Specified) then
    Fill := AParent.Fill;
  if not (sspFillOpacity in Specified) then
    FillOpacity := AParent.FillOpacity;
  if not (sspFillRule in Specified) then
    FillRule := AParent.FillRule;

  if not (sspStroke in Specified) then
    Stroke := AParent.Stroke;
  if not (sspStrokeWidth in Specified) then
    StrokeWidth := AParent.StrokeWidth;
  if not (sspStrokeOpacity in Specified) then
    StrokeOpacity := AParent.StrokeOpacity;
  if not (sspStrokeLineCap in Specified) then
    StrokeLineCap := AParent.StrokeLineCap;
  if not (sspStrokeLineJoin in Specified) then
    StrokeLineJoin := AParent.StrokeLineJoin;
  if not (sspStrokeMiterLimit in Specified) then
    StrokeMiterLimit := AParent.StrokeMiterLimit;

  if not (sspVisibility in Specified) then
    Visibility := AParent.Visibility;

  // Opacity does not inherit directly; it composites through the tree
end;

procedure TSVGStyleRecord.ApplyPresentationAttribute(const AName, AValue: string);
var
  LowName, TrimVal: string;
  DVal: Double;
  Code: Integer;
  LenVal: TSVGLength;
begin
  LowName := LowerCase(Trim(AName));
  TrimVal := Trim(AValue);
  if TrimVal = '' then Exit;

  if LowName = 'fill' then
  begin
    Fill := SVGParsePaint(TrimVal);
    Include(Specified, sspFill);
  end
  else if LowName = 'fill-opacity' then
  begin
    DVal := 1.0;
    System.Val(TrimVal, DVal, Code);
    if Code = 0 then
    begin
      FillOpacity := Max(0.0, Min(1.0, DVal));
      Include(Specified, sspFillOpacity);
    end;
  end
  else if LowName = 'fill-rule' then
  begin
    FillRule := SVGParseFillRule(TrimVal);
    Include(Specified, sspFillRule);
  end
  else if LowName = 'stroke' then
  begin
    Stroke := SVGParsePaint(TrimVal);
    Include(Specified, sspStroke);
  end
  else if LowName = 'stroke-width' then
  begin
    LenVal := SVGParseLength(TrimVal);
    if LenVal.Specified then
    begin
      StrokeWidth := Max(0.0, SVGLengthToPixels(LenVal));
      Include(Specified, sspStrokeWidth);
    end;
  end
  else if LowName = 'stroke-opacity' then
  begin
    DVal := 1.0;
    System.Val(TrimVal, DVal, Code);
    if Code = 0 then
    begin
      StrokeOpacity := Max(0.0, Min(1.0, DVal));
      Include(Specified, sspStrokeOpacity);
    end;
  end
  else if LowName = 'stroke-linecap' then
  begin
    StrokeLineCap := SVGParseLineCap(TrimVal);
    Include(Specified, sspStrokeLineCap);
  end
  else if LowName = 'stroke-linejoin' then
  begin
    StrokeLineJoin := SVGParseLineJoin(TrimVal);
    Include(Specified, sspStrokeLineJoin);
  end
  else if LowName = 'stroke-miterlimit' then
  begin
    DVal := 4.0;
    System.Val(TrimVal, DVal, Code);
    if Code = 0 then
    begin
      StrokeMiterLimit := Max(1.0, DVal);
      Include(Specified, sspStrokeMiterLimit);
    end;
  end
  else if LowName = 'opacity' then
  begin
    DVal := 1.0;
    System.Val(TrimVal, DVal, Code);
    if Code = 0 then
    begin
      Opacity := Max(0.0, Min(1.0, DVal));
      Include(Specified, sspOpacity);
    end;
  end
  else if LowName = 'visibility' then
  begin
    Visibility := SVGParseVisibility(TrimVal);
    Include(Specified, sspVisibility);
  end
  else if LowName = 'display' then
  begin
    Display := SVGParseDisplay(TrimVal);
    Include(Specified, sspDisplay);
  end;
end;

procedure TSVGStyleRecord.ApplyCSSDeclaration(APropId: TCSSPropertyId; AVal: TCSSPropertyValue);
begin
  if AVal.Kind in [cvkUnset, cvkInitial] then Exit;

  case APropId of
    cpiColor:
      ; // Could influence currentColor if needed
    cpiOpacity:
      if AVal.Kind = cvkNumber then
      begin
        Opacity := Max(0.0, Min(1.0, AVal.Number));
        Include(Specified, sspOpacity);
      end;
    cpiVisibility:
      begin
        case AVal.AsVisibility() of
          cvVisible: Visibility := svVisible;
          cvHidden: Visibility := svHidden;
          cvCollapse: Visibility := svCollapse;
        end;
        Include(Specified, sspVisibility);
      end;
    cpiDisplay:
      begin
        case AVal.AsDisplay() of
          cdNone: Display := sdNone;
          cdBlock: Display := sdBlock;
          else Display := sdInline;
        end;
        Include(Specified, sspDisplay);
      end;
  end;
end;

procedure TSVGStyleRecord.ApplyCSSBlock(ABlock: TCSSStyleBlock);
var
  I: Integer;
  Decl: TCSSStyleDeclaration;
  PropName: string;
begin
  if not Assigned(ABlock) then Exit;

  for I := 0 to ABlock.Count - 1 do
  begin
    Decl := ABlock.Items[I];
    if Decl.CustomName <> '' then
    begin
      ApplyPresentationAttribute(Decl.CustomName, Decl.Value.ToString());
    end
    else
    begin
      PropName := CSSPropertyIdToName(Decl.PropertyId);
      if (PropName = 'fill') or (PropName = 'stroke') or (Copy(PropName, 1, 7) = 'stroke-') or
         (Copy(PropName, 1, 5) = 'fill-') then
        ApplyPresentationAttribute(PropName, Decl.Value.ToString())
      else
        ApplyCSSDeclaration(Decl.PropertyId, Decl.Value);
    end;
  end;
end;

// ── TSVGElement Implementation ───────────────────────────────────────────────

constructor TSVGElement.Create(const ATagName: string; ADoc: TSVGDocument = nil);
begin
  inherited Create();
  FTagName := ATagName;
  FId := '';
  FParent := nil;
  FTransform := SVGMatrixIdentity();
  FAccumulatedMatrix := SVGMatrixIdentity();
  FDocument := ADoc;
  FStyle.InitDefaults();
  FComputedStyle.InitDefaults();
end;

destructor TSVGElement.Destroy();
begin
  inherited Destroy();
end;

procedure TSVGElement.ComputeStyles(const AParentStyle: TSVGStyleRecord; const AParentMatrix: TSVGMatrix);
begin
  FComputedStyle := FStyle;
  FComputedStyle.InheritFrom(AParentStyle);
  FComputedStyle.Opacity := FStyle.Opacity * AParentStyle.Opacity;
  FAccumulatedMatrix := SVGMatrixMultiply(AParentMatrix, FTransform);
end;

function TSVGElement.GetLocalBoundingBox(): TSVGRect;
begin
  Result := SVGRect(0.0, 0.0, 0.0, 0.0);
end;

function TSVGElement.GetWorldBoundingBox(): TSVGRect;
var
  LocalBox: TSVGRect;
begin
  LocalBox := GetLocalBoundingBox();
  Result := SVGMatrixTransformRect(FAccumulatedMatrix, LocalBox);
end;

// ── TSVGContainerElement Implementation ──────────────────────────────────────

constructor TSVGContainerElement.Create(const ATagName: string; ADoc: TSVGDocument = nil);
begin
  inherited Create(ATagName, ADoc);
  FChildren := TObjectList.Create(True);
end;

destructor TSVGContainerElement.Destroy();
begin
  FChildren.Free();
  inherited Destroy();
end;

procedure TSVGContainerElement.AddChild(AChild: TSVGElement);
begin
  AChild.Parent := Self;
  AChild.Document := FDocument;
  FChildren.Add(AChild);
end;

function TSVGContainerElement.ChildCount(): Integer;
begin
  Result := FChildren.Count;
end;

function TSVGContainerElement.GetChild(AIndex: Integer): TSVGElement;
begin
  Result := TSVGElement(FChildren[AIndex]);
end;

function TSVGContainerElement.FindById(const AId: string): TSVGElement;
var
  I: Integer;
  Child: TSVGElement;
  Found: TSVGElement;
begin
  Result := nil;
  if FId = AId then Exit(Self);

  for I := 0 to FChildren.Count - 1 do
  begin
    Child := TSVGElement(FChildren[I]);
    if Child.Id = AId then Exit(Child);
    if Child is TSVGContainerElement then
    begin
      Found := TSVGContainerElement(Child).FindById(AId);
      if Assigned(Found) then Exit(Found);
    end;
  end;
end;

procedure TSVGContainerElement.ComputeStyles(const AParentStyle: TSVGStyleRecord; const AParentMatrix: TSVGMatrix);
var
  I: Integer;
  Child: TSVGElement;
begin
  inherited ComputeStyles(AParentStyle, AParentMatrix);

  for I := 0 to FChildren.Count - 1 do
  begin
    Child := TSVGElement(FChildren[I]);
    Child.ComputeStyles(FComputedStyle, FAccumulatedMatrix);
  end;
end;

function TSVGContainerElement.GetLocalBoundingBox(): TSVGRect;
var
  I: Integer;
  Child: TSVGElement;
  ChildBox, TransformedBox: TSVGRect;
  HasBox: Boolean;
  MinX, MaxX, MinY, MaxY: Double;
begin
  HasBox := False;
  MinX := 0.0; MaxX := 0.0;
  MinY := 0.0; MaxY := 0.0;

  for I := 0 to FChildren.Count - 1 do
  begin
    Child := TSVGElement(FChildren[I]);
    if Child.ComputedStyle.Display = sdNone then Continue;

    ChildBox := Child.GetLocalBoundingBox();
    if (ChildBox.Width > 0.0) or (ChildBox.Height > 0.0) then
    begin
      TransformedBox := SVGMatrixTransformRect(Child.Transform, ChildBox);
      if not HasBox then
      begin
        MinX := TransformedBox.X;
        MaxX := TransformedBox.X + TransformedBox.Width;
        MinY := TransformedBox.Y;
        MaxY := TransformedBox.Y + TransformedBox.Height;
        HasBox := True;
      end
      else
      begin
        MinX := Min(MinX, TransformedBox.X);
        MaxX := Max(MaxX, TransformedBox.X + TransformedBox.Width);
        MinY := Min(MinY, TransformedBox.Y);
        MaxY := Max(MaxY, TransformedBox.Y + TransformedBox.Height);
      end;
    end;
  end;

  if HasBox then
    Result := SVGRect(MinX, MinY, MaxX - MinX, MaxY - MinY)
  else
    Result := SVGRect(0.0, 0.0, 0.0, 0.0);
end;

// ── TSVGGroupElement Implementation ──────────────────────────────────────────

constructor TSVGGroupElement.Create(ADoc: TSVGDocument = nil);
begin
  inherited Create('g', ADoc);
end;

// ── TSVGDefsElement Implementation ───────────────────────────────────────────

constructor TSVGDefsElement.Create(ADoc: TSVGDocument = nil);
begin
  inherited Create('defs', ADoc);
end;

procedure TSVGDefsElement.ComputeStyles(const AParentStyle: TSVGStyleRecord; const AParentMatrix: TSVGMatrix);
begin
  // Defs children are not rendered in normal display flow
  inherited ComputeStyles(AParentStyle, AParentMatrix);
end;

// ── TSVGSvgElement Implementation ────────────────────────────────────────────

constructor TSVGSvgElement.Create(ADoc: TSVGDocument = nil);
begin
  inherited Create('svg', ADoc);
  FX := SVGLength(0.0);
  FY := SVGLength(0.0);
  FWidth := SVGLength(0.0);
  FHeight := SVGLength(0.0);
  FViewBox.HasValue := False;
  FPreserveAspectRatio.Align := paraXMidYMid;
  FPreserveAspectRatio.MeetOrSlice := mosMeet;
  FViewBoxTransform := SVGMatrixIdentity();
end;

procedure TSVGSvgElement.ComputeViewBox(TargetW, TargetH: Double);
begin
  if FViewBox.HasValue then
    FViewBoxTransform := SVGCalculateViewBoxTransform(FViewBox, FPreserveAspectRatio, TargetW, TargetH)
  else
    FViewBoxTransform := SVGMatrixIdentity();
end;

procedure TSVGSvgElement.ComputeStyles(const AParentStyle: TSVGStyleRecord; const AParentMatrix: TSVGMatrix);
var
  EffectiveMatrix: TSVGMatrix;
begin
  EffectiveMatrix := SVGMatrixMultiply(AParentMatrix, FTransform);
  EffectiveMatrix := SVGMatrixMultiply(EffectiveMatrix, FViewBoxTransform);
  inherited ComputeStyles(AParentStyle, EffectiveMatrix);
end;

// ── TSVGUseElement Implementation ────────────────────────────────────────────

constructor TSVGUseElement.Create(ADoc: TSVGDocument = nil);
begin
  inherited Create('use', ADoc);
  FHref := '';
  FX := SVGLength(0.0);
  FY := SVGLength(0.0);
  FWidth := SVGLength(0.0);
  FHeight := SVGLength(0.0);
  FReferencedElement := nil;
end;

procedure TSVGUseElement.ComputeStyles(const AParentStyle: TSVGStyleRecord; const AParentMatrix: TSVGMatrix);
var
  TMat, InstMatrix: TSVGMatrix;
begin
  TMat := SVGMatrixTranslate(SVGLengthToPixels(FX), SVGLengthToPixels(FY));
  InstMatrix := SVGMatrixMultiply(FTransform, TMat);
  inherited ComputeStyles(AParentStyle, AParentMatrix);

  if Assigned(FReferencedElement) then
  begin
    FReferencedElement.ComputeStyles(FComputedStyle, SVGMatrixMultiply(FAccumulatedMatrix, InstMatrix));
  end;
end;

function TSVGUseElement.GetLocalBoundingBox(): TSVGRect;
begin
  if Assigned(FReferencedElement) then
    Result := FReferencedElement.GetLocalBoundingBox()
  else
    Result := SVGRect(0.0, 0.0, 0.0, 0.0);
end;

// ── TSVGShapeElement Implementation ──────────────────────────────────────────

function TSVGShapeElement.GetLocalBoundingBox(): TSVGRect;
var
  P: TSVGPathData;
begin
  P := GetPath();
  if Assigned(P) then
    Result := P.GetBoundingBox()
  else
    Result := SVGRect(0.0, 0.0, 0.0, 0.0);
end;

// ── TSVGPathElement Implementation ───────────────────────────────────────────

constructor TSVGPathElement.Create(ADoc: TSVGDocument = nil);
begin
  inherited Create('path', ADoc);
  FPathData := TSVGPathData.Create();
end;

destructor TSVGPathElement.Destroy();
begin
  FPathData.Free();
  inherited Destroy();
end;

function TSVGPathElement.GetPath(): TSVGPathData;
begin
  Result := FPathData;
end;

procedure TSVGPathElement.SetPathData(const AD: string);
begin
  FPathData.Parse(AD);
end;

// ── TSVGRectElement Implementation ───────────────────────────────────────────

constructor TSVGRectElement.Create(ADoc: TSVGDocument = nil);
begin
  inherited Create('rect', ADoc);
  FX := SVGLength(0.0);
  FY := SVGLength(0.0);
  FWidth := SVGLength(0.0);
  FHeight := SVGLength(0.0);
  FRx := SVGLength(0.0);
  FRy := SVGLength(0.0);
  FCachedPath := nil;
end;

destructor TSVGRectElement.Destroy();
begin
  if Assigned(FCachedPath) then FCachedPath.Free();
  inherited Destroy();
end;

function TSVGRectElement.GetPath(): TSVGPathData;
begin
  if Assigned(FCachedPath) then FCachedPath.Free();
  FCachedPath := TSVGPathData.CreateRectPath(
    SVGLengthToPixels(FX), SVGLengthToPixels(FY),
    SVGLengthToPixels(FWidth), SVGLengthToPixels(FHeight),
    SVGLengthToPixels(FRx), SVGLengthToPixels(FRy)
  );
  Result := FCachedPath;
end;

// ── TSVGCircleElement Implementation ─────────────────────────────────────────

constructor TSVGCircleElement.Create(ADoc: TSVGDocument = nil);
begin
  inherited Create('circle', ADoc);
  FCx := SVGLength(0.0);
  FCy := SVGLength(0.0);
  FR := SVGLength(0.0);
  FCachedPath := nil;
end;

destructor TSVGCircleElement.Destroy();
begin
  if Assigned(FCachedPath) then FCachedPath.Free();
  inherited Destroy();
end;

function TSVGCircleElement.GetPath(): TSVGPathData;
begin
  if Assigned(FCachedPath) then FCachedPath.Free();
  FCachedPath := TSVGPathData.CreateCirclePath(
    SVGLengthToPixels(FCx), SVGLengthToPixels(FCy), SVGLengthToPixels(FR)
  );
  Result := FCachedPath;
end;

// ── TSVGEllipseElement Implementation ────────────────────────────────────────

constructor TSVGEllipseElement.Create(ADoc: TSVGDocument = nil);
begin
  inherited Create('ellipse', ADoc);
  FCx := SVGLength(0.0);
  FCy := SVGLength(0.0);
  FRx := SVGLength(0.0);
  FRy := SVGLength(0.0);
  FCachedPath := nil;
end;

destructor TSVGEllipseElement.Destroy();
begin
  if Assigned(FCachedPath) then FCachedPath.Free();
  inherited Destroy();
end;

function TSVGEllipseElement.GetPath(): TSVGPathData;
begin
  if Assigned(FCachedPath) then FCachedPath.Free();
  FCachedPath := TSVGPathData.CreateEllipsePath(
    SVGLengthToPixels(FCx), SVGLengthToPixels(FCy),
    SVGLengthToPixels(FRx), SVGLengthToPixels(FRy)
  );
  Result := FCachedPath;
end;

// ── TSVGLineElement Implementation ───────────────────────────────────────────

constructor TSVGLineElement.Create(ADoc: TSVGDocument = nil);
begin
  inherited Create('line', ADoc);
  FX1 := SVGLength(0.0);
  FY1 := SVGLength(0.0);
  FX2 := SVGLength(0.0);
  FY2 := SVGLength(0.0);
  FCachedPath := nil;
end;

destructor TSVGLineElement.Destroy();
begin
  if Assigned(FCachedPath) then FCachedPath.Free();
  inherited Destroy();
end;

function TSVGLineElement.GetPath(): TSVGPathData;
begin
  if Assigned(FCachedPath) then FCachedPath.Free();
  FCachedPath := TSVGPathData.CreateLinePath(
    SVGLengthToPixels(FX1), SVGLengthToPixels(FY1),
    SVGLengthToPixels(FX2), SVGLengthToPixels(FY2)
  );
  Result := FCachedPath;
end;

// ── TSVGPolylineElement Implementation ───────────────────────────────────────

constructor TSVGPolylineElement.Create(ADoc: TSVGDocument = nil);
begin
  inherited Create('polyline', ADoc);
  FCachedPath := nil;
end;

destructor TSVGPolylineElement.Destroy();
begin
  SetLength(FPoints, 0);
  if Assigned(FCachedPath) then FCachedPath.Free();
  inherited Destroy();
end;

procedure TSVGPolylineElement.SetPointsString(const S: string);
begin
  FPoints := ParsePoints(S);
end;

function TSVGPolylineElement.GetPath(): TSVGPathData;
begin
  if Assigned(FCachedPath) then FCachedPath.Free();
  FCachedPath := TSVGPathData.CreatePolygonPath(FPoints, False);
  Result := FCachedPath;
end;

// ── TSVGPolygonElement Implementation ────────────────────────────────────────

constructor TSVGPolygonElement.Create(ADoc: TSVGDocument = nil);
begin
  inherited Create('polygon', ADoc);
  FCachedPath := nil;
end;

destructor TSVGPolygonElement.Destroy();
begin
  SetLength(FPoints, 0);
  if Assigned(FCachedPath) then FCachedPath.Free();
  inherited Destroy();
end;

procedure TSVGPolygonElement.SetPointsString(const S: string);
begin
  FPoints := ParsePoints(S);
end;

function TSVGPolygonElement.GetPath(): TSVGPathData;
begin
  if Assigned(FCachedPath) then FCachedPath.Free();
  FCachedPath := TSVGPathData.CreatePolygonPath(FPoints, True);
  Result := FCachedPath;
end;

// ── TSVGGradient Implementation ──────────────────────────────────────────────

constructor TSVGStopElement.Create(ADoc: TSVGDocument = nil);
begin
  inherited Create('stop', ADoc);
  FOffset := 0.0;
  FColor := TCSSColor.Black();
end;

constructor TSVGGradientElement.Create(const ATagName: string; ADoc: TSVGDocument = nil);
begin
  inherited Create(ATagName, ADoc);
  FGradientUnits := sguObjectBoundingBox;
  FSpreadMethod := sgsPad;
  FGradientTransform := SVGMatrixIdentity();
  FStops := TObjectList.Create(True);
  FHref := '';
end;

destructor TSVGGradientElement.Destroy();
begin
  FStops.Free();
  inherited Destroy();
end;

procedure TSVGGradientElement.AddStop(AStop: TSVGStopElement);
begin
  AStop.Parent := Self;
  AStop.Document := FDocument;
  FStops.Add(AStop);
end;

function TSVGGradientElement.StopCount(): Integer;
begin
  Result := FStops.Count;
end;

function TSVGGradientElement.GetStop(AIndex: Integer): TSVGStopElement;
begin
  Result := TSVGStopElement(FStops[AIndex]);
end;

function TSVGGradientElement.GetEffectiveStops(): TObjectList;
var
  RefElem: TSVGElement;
  TargetId: string;
  Visited: TStringList;
begin
  if FStops.Count > 0 then
    Exit(FStops);

  if (FHref = '') or not Assigned(FDocument) then
    Exit(FStops);

  Visited := TStringList.Create();
  try
    Visited.Add(FId);
    TargetId := FHref;
    if (Length(TargetId) > 0) and (TargetId[1] = '#') then
      Delete(TargetId, 1, 1);

    while TargetId <> '' do
    begin
      if Visited.IndexOf(TargetId) >= 0 then
        Break;
      Visited.Add(TargetId);

      RefElem := FDocument.FindElementById(TargetId);
      if Assigned(RefElem) and (RefElem is TSVGGradientElement) then
      begin
        if TSVGGradientElement(RefElem).FStops.Count > 0 then
          Exit(TSVGGradientElement(RefElem).FStops);
        TargetId := TSVGGradientElement(RefElem).FHref;
        if (Length(TargetId) > 0) and (TargetId[1] = '#') then
          Delete(TargetId, 1, 1);
      end
      else
        Break;
    end;
  finally
    Visited.Free();
  end;

  Result := FStops;
end;

constructor TSVGLinearGradientElement.Create(ADoc: TSVGDocument = nil);
begin
  inherited Create('linearGradient', ADoc);
  FX1 := SVGLength(0.0, suPercent);
  FY1 := SVGLength(0.0, suPercent);
  FX2 := SVGLength(100.0, suPercent);
  FY2 := SVGLength(0.0, suPercent);
end;

constructor TSVGRadialGradientElement.Create(ADoc: TSVGDocument = nil);
begin
  inherited Create('radialGradient', ADoc);
  FCx := SVGLength(50.0, suPercent);
  FCy := SVGLength(50.0, suPercent);
  FR := SVGLength(50.0, suPercent);
  FFx := SVGLength(50.0, suPercent);
  FFy := SVGLength(50.0, suPercent);
end;

// ── TSVGDocument Implementation ──────────────────────────────────────────────

constructor TSVGDocument.Create();
begin
  inherited Create();
  FRoot := TSVGSvgElement.Create(Self);
  FIdMap := TStringList.Create();
  FIdMap.Sorted := True;
  FIdMap.Duplicates := dupAccept;
  FStylesheets := TObjectList.Create(True);
end;

destructor TSVGDocument.Destroy();
begin
  FStylesheets.Free();
  FIdMap.Free();
  FRoot.Free();
  inherited Destroy();
end;

procedure TSVGDocument.RegisterElement(const AId: string; AElement: TSVGElement);
begin
  if AId <> '' then
    FIdMap.AddObject(AId, AElement);
end;

function TSVGDocument.FindElementById(const AId: string): TSVGElement;
var
  Idx: Integer;
begin
  Result := nil;
  Idx := FIdMap.IndexOf(AId);
  if Idx >= 0 then
    Result := TSVGElement(FIdMap.Objects[Idx]);
end;

procedure TSVGDocument.AddStylesheet(ASheet: TCSSStylesheet);
begin
  FStylesheets.Add(ASheet);
end;

procedure TSVGDocument.ResolveReferences();

  procedure ResolveNode(ANode: TSVGElement);
  var
    K: Integer;
    UseElem: TSVGUseElement;
    TargetId: string;
  begin
    if ANode = nil then Exit;

    if ANode is TSVGUseElement then
    begin
      UseElem := TSVGUseElement(ANode);
      TargetId := UseElem.Href;
      if (Length(TargetId) > 0) and (TargetId[1] = '#') then
        Delete(TargetId, 1, 1);
      UseElem.ReferencedElement := FindElementById(TargetId);
    end;

    if ANode is TSVGContainerElement then
    begin
      for K := 0 to TSVGContainerElement(ANode).ChildCount() - 1 do
        ResolveNode(TSVGContainerElement(ANode).GetChild(K));
    end;
  end;

begin
  ResolveNode(FRoot);
end;

procedure TSVGDocument.ComputeStyles(TargetW, TargetH: Double);
var
  InitialStyle: TSVGStyleRecord;
begin
  if not Assigned(FRoot) then Exit;

  if TargetW <= 0.0 then TargetW := GetIntrinsicWidth();
  if TargetH <= 0.0 then TargetH := GetIntrinsicHeight();

  FRoot.ComputeViewBox(TargetW, TargetH);

  InitialStyle.InitDefaults();
  FRoot.ComputeStyles(InitialStyle, SVGMatrixIdentity());
end;

function TSVGDocument.GetIntrinsicWidth(): Double;
begin
  if Assigned(FRoot) then
  begin
    if FRoot.Width.Specified and (FRoot.Width.Value > 0.0) then
      Exit(SVGLengthToPixels(FRoot.Width))
    else if FRoot.ViewBox.HasValue and (FRoot.ViewBox.Width > 0.0) then
      Exit(FRoot.ViewBox.Width);
  end;
  Result := 300.0; // Default SVG fallback
end;

function TSVGDocument.GetIntrinsicHeight(): Double;
begin
  if Assigned(FRoot) then
  begin
    if FRoot.Height.Specified and (FRoot.Height.Value > 0.0) then
      Exit(SVGLengthToPixels(FRoot.Height))
    else if FRoot.ViewBox.HasValue and (FRoot.ViewBox.Height > 0.0) then
      Exit(FRoot.ViewBox.Height);
  end;
  Result := 150.0; // Default SVG fallback
end;

end.
