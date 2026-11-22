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
    FAnimatedTransform: TSVGMatrix;
    FHasAnimatedTransform: Boolean;
    FAnimatedOpacity: Double;
    FHasAnimatedOpacity: Boolean;
    FAnimatedFill: TSVGPaint;
    FHasAnimatedFill: Boolean;
    FAnimatedStroke: TSVGPaint;
    FHasAnimatedStroke: Boolean;
    FAnimatedStrokeWidth: Double;
    FHasAnimatedStrokeWidth: Boolean;
  public
    constructor Create(const ATagName: string; ADoc: TSVGDocument = nil); virtual;
    destructor Destroy(); override;

    procedure ComputeStyles(const AParentStyle: TSVGStyleRecord; const AParentMatrix: TSVGMatrix); virtual;
    function GetLocalBoundingBox(): TSVGRect; virtual;
    function GetWorldBoundingBox(): TSVGRect;
    function GetEffectiveTransform(): TSVGMatrix; virtual;
    procedure ResetAnimationState(); virtual;

    property Id: string read FId write FId;
    property TagName: string read FTagName;
    property Parent: TSVGElement read FParent write FParent;
    property Transform: TSVGMatrix read FTransform write FTransform;
    property Style: TSVGStyleRecord read FStyle write FStyle;
    property ComputedStyle: TSVGStyleRecord read FComputedStyle;
    property AccumulatedMatrix: TSVGMatrix read FAccumulatedMatrix;
    property Document: TSVGDocument read FDocument write FDocument;
    property AnimatedTransform: TSVGMatrix read FAnimatedTransform write FAnimatedTransform;
    property HasAnimatedTransform: Boolean read FHasAnimatedTransform write FHasAnimatedTransform;
    property AnimatedOpacity: Double read FAnimatedOpacity write FAnimatedOpacity;
    property HasAnimatedOpacity: Boolean read FHasAnimatedOpacity write FHasAnimatedOpacity;
    property AnimatedFill: TSVGPaint read FAnimatedFill write FAnimatedFill;
    property HasAnimatedFill: Boolean read FHasAnimatedFill write FHasAnimatedFill;
    property AnimatedStroke: TSVGPaint read FAnimatedStroke write FAnimatedStroke;
    property HasAnimatedStroke: Boolean read FHasAnimatedStroke write FHasAnimatedStroke;
    property AnimatedStrokeWidth: Double read FAnimatedStrokeWidth write FAnimatedStrokeWidth;
    property HasAnimatedStrokeWidth: Boolean read FHasAnimatedStrokeWidth write FHasAnimatedStrokeWidth;
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
    procedure ResetAnimationState(); override;

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
    FBaseX, FBaseY, FBaseWidth, FBaseHeight, FBaseRx, FBaseRy: TSVGLength;
    FCachedPath: TSVGPathData;
    procedure SetX(const AVal: TSVGLength);
    procedure SetY(const AVal: TSVGLength);
    procedure SetWidth(const AVal: TSVGLength);
    procedure SetHeight(const AVal: TSVGLength);
    procedure SetRx(const AVal: TSVGLength);
    procedure SetRy(const AVal: TSVGLength);
  public
    constructor Create(ADoc: TSVGDocument = nil); reintroduce;
    destructor Destroy(); override;

    function GetPath(): TSVGPathData; override;
    procedure ResetAnimationState(); override;

    procedure SetAnimatedX(AVal: Double);
    procedure SetAnimatedY(AVal: Double);
    procedure SetAnimatedWidth(AVal: Double);
    procedure SetAnimatedHeight(AVal: Double);
    procedure SetAnimatedRx(AVal: Double);
    procedure SetAnimatedRy(AVal: Double);

    property X: TSVGLength read FX write SetX;
    property Y: TSVGLength read FY write SetY;
    property Width: TSVGLength read FWidth write SetWidth;
    property Height: TSVGLength read FHeight write SetHeight;
    property Rx: TSVGLength read FRx write SetRx;
    property Ry: TSVGLength read FRy write SetRy;
  end;

  TSVGCircleElement = class(TSVGShapeElement)
  private
    FCx, FCy, FR: TSVGLength;
    FBaseCx, FBaseCy, FBaseR: TSVGLength;
    FCachedPath: TSVGPathData;
    procedure SetCx(const AVal: TSVGLength);
    procedure SetCy(const AVal: TSVGLength);
    procedure SetR(const AVal: TSVGLength);
  public
    constructor Create(ADoc: TSVGDocument = nil); reintroduce;
    destructor Destroy(); override;

    function GetPath(): TSVGPathData; override;
    procedure ResetAnimationState(); override;

    procedure SetAnimatedCx(AVal: Double);
    procedure SetAnimatedCy(AVal: Double);
    procedure SetAnimatedR(AVal: Double);

    property Cx: TSVGLength read FCx write SetCx;
    property Cy: TSVGLength read FCy write SetCy;
    property R: TSVGLength read FR write SetR;
  end;

  TSVGEllipseElement = class(TSVGShapeElement)
  private
    FCx, FCy, FRx, FRy: TSVGLength;
    FBaseCx, FBaseCy, FBaseRx, FBaseRy: TSVGLength;
    FCachedPath: TSVGPathData;
    procedure SetCx(const AVal: TSVGLength);
    procedure SetCy(const AVal: TSVGLength);
    procedure SetRx(const AVal: TSVGLength);
    procedure SetRy(const AVal: TSVGLength);
  public
    constructor Create(ADoc: TSVGDocument = nil); reintroduce;
    destructor Destroy(); override;

    function GetPath(): TSVGPathData; override;
    procedure ResetAnimationState(); override;

    procedure SetAnimatedCx(AVal: Double);
    procedure SetAnimatedCy(AVal: Double);
    procedure SetAnimatedRx(AVal: Double);
    procedure SetAnimatedRy(AVal: Double);

    property Cx: TSVGLength read FCx write SetCx;
    property Cy: TSVGLength read FCy write SetCy;
    property Rx: TSVGLength read FRx write SetRx;
    property Ry: TSVGLength read FRy write SetRy;
  end;

  TSVGLineElement = class(TSVGShapeElement)
  private
    FX1, FY1, FX2, FY2: TSVGLength;
    FBaseX1, FBaseY1, FBaseX2, FBaseY2: TSVGLength;
    FCachedPath: TSVGPathData;
    procedure SetX1(const AVal: TSVGLength);
    procedure SetY1(const AVal: TSVGLength);
    procedure SetX2(const AVal: TSVGLength);
    procedure SetY2(const AVal: TSVGLength);
  public
    constructor Create(ADoc: TSVGDocument = nil); reintroduce;
    destructor Destroy(); override;

    function GetPath(): TSVGPathData; override;
    procedure ResetAnimationState(); override;

    procedure SetAnimatedX1(AVal: Double);
    procedure SetAnimatedY1(AVal: Double);
    procedure SetAnimatedX2(AVal: Double);
    procedure SetAnimatedY2(AVal: Double);

    property X1: TSVGLength read FX1 write SetX1;
    property Y1: TSVGLength read FY1 write SetY1;
    property X2: TSVGLength read FX2 write SetX2;
    property Y2: TSVGLength read FY2 write SetY2;
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

  // ── Animation Elements ─────────────────────────────────────────────────────

  TSVGTransformType = (
    attTranslate,
    attScale,
    attRotate,
    attSkewX,
    attSkewY
  );

  TSVGAnimationFillMode = (
    afmRemove,
    afmFreeze
  );

  TSVGAnimationAdditive = (
    ataReplace,
    ataSum
  );

  TSVGAnimationElement = class(TSVGElement)
  protected
    FAttributeName: string;
    FValues: TStringList;
    FFromVal: string;
    FToVal: string;
    FByVal: string;
    FBeginSec: Double;
    FDurSec: Double;
    FRepeatCount: Double;
    FRepeatIndefinite: Boolean;
    FFillMode: TSVGAnimationFillMode;
    FAdditive: TSVGAnimationAdditive;
    FHref: string;
    FTargetElement: TSVGElement;

    function GetNormalizedProgress(CurrentTimeSec: Double; out IsActive: Boolean): Double;
  public
    constructor Create(const ATagName: string; ADoc: TSVGDocument = nil); override;
    destructor Destroy(); override;

    procedure ApplyAtTime(CurrentTimeSec: Double); virtual; abstract;
    function GetEffectiveDuration(): Double; virtual;

    property AttributeName: string read FAttributeName write FAttributeName;
    property FromVal: string read FFromVal write FFromVal;
    property ToVal: string read FToVal write FToVal;
    property ByVal: string read FByVal write FByVal;
    property BeginSec: Double read FBeginSec write FBeginSec;
    property DurSec: Double read FDurSec write FDurSec;
    property RepeatCount: Double read FRepeatCount write FRepeatCount;
    property RepeatIndefinite: Boolean read FRepeatIndefinite write FRepeatIndefinite;
    property FillMode: TSVGAnimationFillMode read FFillMode write FFillMode;
    property Additive: TSVGAnimationAdditive read FAdditive write FAdditive;
    property Href: string read FHref write FHref;
    property TargetElement: TSVGElement read FTargetElement write FTargetElement;
    property Values: TStringList read FValues;
  end;

  TSVGAnimateTransformElement = class(TSVGAnimationElement)
  private
    FTransformType: TSVGTransformType;
  public
    constructor Create(ADoc: TSVGDocument = nil); reintroduce;
    procedure ApplyAtTime(CurrentTimeSec: Double); override;

    property TransformType: TSVGTransformType read FTransformType write FTransformType;
  end;

  TSVGAnimateElement = class(TSVGAnimationElement)
  public
    constructor Create(ADoc: TSVGDocument = nil); reintroduce;
    procedure ApplyAtTime(CurrentTimeSec: Double); override;
  end;

  TSVGSetElement = class(TSVGAnimateElement)
  public
    constructor Create(ADoc: TSVGDocument = nil); reintroduce;
    procedure ApplyAtTime(CurrentTimeSec: Double); override;
  end;

  // ── Complete SVG Document ──────────────────────────────────────────────────

  TSVGDocument = class
  private
    FRoot: TSVGSvgElement;
    FIdMap: TStringList; // Maps ID to TSVGElement
    FStylesheets: TObjectList; // Owns TCSSStylesheet
    FAnimations: TObjectList; // Owns TSVGAnimationElement
    FCurrentTimeSec: Double;
    FLastTargetW: Double;
    FLastTargetH: Double;
  public
    constructor Create();
    destructor Destroy(); override;

    procedure RegisterElement(const AId: string; AElement: TSVGElement);
    function FindElementById(const AId: string): TSVGElement;
    procedure AddStylesheet(ASheet: TCSSStylesheet);

    procedure RegisterAnimation(AAnim: TSVGAnimationElement);
    function HasAnimation(): Boolean;
    function GetAnimationDuration(): Double;
    procedure ResetAnimation();
    procedure ResetElementAnimationState();
    procedure SetCurrentTime(TimeSec: Double);

    procedure ResolveReferences();
    procedure ComputeStyles(TargetW, TargetH: Double);

    function GetIntrinsicWidth(): Double;
    function GetIntrinsicHeight(): Double;

    property Root: TSVGSvgElement read FRoot write FRoot;
    property Stylesheets: TObjectList read FStylesheets;
    property Animations: TObjectList read FAnimations;
    property CurrentTime: Double read FCurrentTimeSec;
  end;

type
  TDoubleArray = array of Double;

function ParseSVGDuration(const S: string): Double;
function ParseFloatList(const S: string): TDoubleArray;
procedure ParseSemicolonList(const S: string; AList: TStrings);
function InterpolateColor(const C1, C2: TCSSColor; U: Double): TCSSColor;

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
  FAnimatedTransform := SVGMatrixIdentity();
  FHasAnimatedTransform := False;
  FAnimatedOpacity := 1.0;
  FHasAnimatedOpacity := False;
  FAnimatedFill.Kind := pkNone;
  FHasAnimatedFill := False;
  FAnimatedStroke.Kind := pkNone;
  FHasAnimatedStroke := False;
  FAnimatedStrokeWidth := 0.0;
  FHasAnimatedStrokeWidth := False;
end;

destructor TSVGElement.Destroy();
begin
  inherited Destroy();
end;

function TSVGElement.GetEffectiveTransform(): TSVGMatrix;
begin
  if FHasAnimatedTransform then
    Result := FAnimatedTransform
  else
    Result := FTransform;
end;

procedure TSVGElement.ResetAnimationState();
begin
  FHasAnimatedTransform := False;
  FAnimatedTransform := SVGMatrixIdentity();
  FHasAnimatedOpacity := False;
  FAnimatedOpacity := 1.0;
  FHasAnimatedFill := False;
  FHasAnimatedStroke := False;
  FHasAnimatedStrokeWidth := False;
  FAnimatedStrokeWidth := 0.0;
end;

procedure TSVGElement.ComputeStyles(const AParentStyle: TSVGStyleRecord; const AParentMatrix: TSVGMatrix);
begin
  FComputedStyle := FStyle;
  FComputedStyle.InheritFrom(AParentStyle);

  if FHasAnimatedOpacity then
    FComputedStyle.Opacity := FAnimatedOpacity * AParentStyle.Opacity
  else
    FComputedStyle.Opacity := FStyle.Opacity * AParentStyle.Opacity;

  if FHasAnimatedFill then
    FComputedStyle.Fill := FAnimatedFill;

  if FHasAnimatedStroke then
    FComputedStyle.Stroke := FAnimatedStroke;

  if FHasAnimatedStrokeWidth then
    FComputedStyle.StrokeWidth := FAnimatedStrokeWidth;

  FAccumulatedMatrix := SVGMatrixMultiply(AParentMatrix, GetEffectiveTransform());
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

procedure TSVGContainerElement.ResetAnimationState();
var
  I: Integer;
begin
  inherited ResetAnimationState();
  for I := 0 to FChildren.Count - 1 do
    TSVGElement(FChildren[I]).ResetAnimationState();
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
var
  EffectiveBox: TSVGViewBox;
  IW, IH: Double;
begin
  if FViewBox.HasValue then
    FViewBoxTransform := SVGCalculateViewBoxTransform(FViewBox, FPreserveAspectRatio, TargetW, TargetH)
  else
  begin
    IW := 0.0;
    IH := 0.0;
    if FWidth.Specified and (FWidth.Value > 0.0) then
      IW := SVGLengthToPixels(FWidth);
    if FHeight.Specified and (FHeight.Value > 0.0) then
      IH := SVGLengthToPixels(FHeight);

    if (IW <= 0.0) or (IH <= 0.0) then
    begin
      if Assigned(FDocument) then
      begin
        if IW <= 0.0 then IW := FDocument.GetIntrinsicWidth();
        if IH <= 0.0 then IH := FDocument.GetIntrinsicHeight();
      end;
    end;

    if (IW > 0.0) and (IH > 0.0) and (TargetW > 0.0) and (TargetH > 0.0) then
    begin
      EffectiveBox.HasValue := True;
      EffectiveBox.MinX := 0.0;
      EffectiveBox.MinY := 0.0;
      EffectiveBox.Width := IW;
      EffectiveBox.Height := IH;
      FViewBoxTransform := SVGCalculateViewBoxTransform(EffectiveBox, FPreserveAspectRatio, TargetW, TargetH);
    end
    else
      FViewBoxTransform := SVGMatrixIdentity();
  end;
end;

procedure TSVGSvgElement.ComputeStyles(const AParentStyle: TSVGStyleRecord; const AParentMatrix: TSVGMatrix);
var
  EffectiveMatrix: TSVGMatrix;
begin
  EffectiveMatrix := SVGMatrixMultiply(AParentMatrix, GetEffectiveTransform());
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
  InstMatrix := SVGMatrixMultiply(GetEffectiveTransform(), TMat);
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
  FBaseX := FX;
  FBaseY := FY;
  FBaseWidth := FWidth;
  FBaseHeight := FHeight;
  FBaseRx := FRx;
  FBaseRy := FRy;
  FCachedPath := nil;
end;

destructor TSVGRectElement.Destroy();
begin
  if Assigned(FCachedPath) then FCachedPath.Free();
  inherited Destroy();
end;

procedure TSVGRectElement.SetX(const AVal: TSVGLength);
begin
  FX := AVal;
  FBaseX := AVal;
  if Assigned(FCachedPath) then begin FCachedPath.Free(); FCachedPath := nil; end;
end;

procedure TSVGRectElement.SetY(const AVal: TSVGLength);
begin
  FY := AVal;
  FBaseY := AVal;
  if Assigned(FCachedPath) then begin FCachedPath.Free(); FCachedPath := nil; end;
end;

procedure TSVGRectElement.SetWidth(const AVal: TSVGLength);
begin
  FWidth := AVal;
  FBaseWidth := AVal;
  if Assigned(FCachedPath) then begin FCachedPath.Free(); FCachedPath := nil; end;
end;

procedure TSVGRectElement.SetHeight(const AVal: TSVGLength);
begin
  FHeight := AVal;
  FBaseHeight := AVal;
  if Assigned(FCachedPath) then begin FCachedPath.Free(); FCachedPath := nil; end;
end;

procedure TSVGRectElement.SetRx(const AVal: TSVGLength);
begin
  FRx := AVal;
  FBaseRx := AVal;
  if Assigned(FCachedPath) then begin FCachedPath.Free(); FCachedPath := nil; end;
end;

procedure TSVGRectElement.SetRy(const AVal: TSVGLength);
begin
  FRy := AVal;
  FBaseRy := AVal;
  if Assigned(FCachedPath) then begin FCachedPath.Free(); FCachedPath := nil; end;
end;

procedure TSVGRectElement.ResetAnimationState();
begin
  inherited ResetAnimationState();
  FX := FBaseX;
  FY := FBaseY;
  FWidth := FBaseWidth;
  FHeight := FBaseHeight;
  FRx := FBaseRx;
  FRy := FBaseRy;
  if Assigned(FCachedPath) then begin FCachedPath.Free(); FCachedPath := nil; end;
end;

procedure TSVGRectElement.SetAnimatedX(AVal: Double);
begin
  FX := SVGLength(AVal);
  if Assigned(FCachedPath) then begin FCachedPath.Free(); FCachedPath := nil; end;
end;

procedure TSVGRectElement.SetAnimatedY(AVal: Double);
begin
  FY := SVGLength(AVal);
  if Assigned(FCachedPath) then begin FCachedPath.Free(); FCachedPath := nil; end;
end;

procedure TSVGRectElement.SetAnimatedWidth(AVal: Double);
begin
  FWidth := SVGLength(AVal);
  if Assigned(FCachedPath) then begin FCachedPath.Free(); FCachedPath := nil; end;
end;

procedure TSVGRectElement.SetAnimatedHeight(AVal: Double);
begin
  FHeight := SVGLength(AVal);
  if Assigned(FCachedPath) then begin FCachedPath.Free(); FCachedPath := nil; end;
end;

procedure TSVGRectElement.SetAnimatedRx(AVal: Double);
begin
  FRx := SVGLength(AVal);
  if Assigned(FCachedPath) then begin FCachedPath.Free(); FCachedPath := nil; end;
end;

procedure TSVGRectElement.SetAnimatedRy(AVal: Double);
begin
  FRy := SVGLength(AVal);
  if Assigned(FCachedPath) then begin FCachedPath.Free(); FCachedPath := nil; end;
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
  FBaseCx := FCx;
  FBaseCy := FCy;
  FBaseR := FR;
  FCachedPath := nil;
end;

destructor TSVGCircleElement.Destroy();
begin
  if Assigned(FCachedPath) then FCachedPath.Free();
  inherited Destroy();
end;

procedure TSVGCircleElement.SetCx(const AVal: TSVGLength);
begin
  FCx := AVal;
  FBaseCx := AVal;
  if Assigned(FCachedPath) then begin FCachedPath.Free(); FCachedPath := nil; end;
end;

procedure TSVGCircleElement.SetCy(const AVal: TSVGLength);
begin
  FCy := AVal;
  FBaseCy := AVal;
  if Assigned(FCachedPath) then begin FCachedPath.Free(); FCachedPath := nil; end;
end;

procedure TSVGCircleElement.SetR(const AVal: TSVGLength);
begin
  FR := AVal;
  FBaseR := AVal;
  if Assigned(FCachedPath) then begin FCachedPath.Free(); FCachedPath := nil; end;
end;

procedure TSVGCircleElement.ResetAnimationState();
begin
  inherited ResetAnimationState();
  FCx := FBaseCx;
  FCy := FBaseCy;
  FR := FBaseR;
  if Assigned(FCachedPath) then begin FCachedPath.Free(); FCachedPath := nil; end;
end;

procedure TSVGCircleElement.SetAnimatedCx(AVal: Double);
begin
  FCx := SVGLength(AVal);
  if Assigned(FCachedPath) then begin FCachedPath.Free(); FCachedPath := nil; end;
end;

procedure TSVGCircleElement.SetAnimatedCy(AVal: Double);
begin
  FCy := SVGLength(AVal);
  if Assigned(FCachedPath) then begin FCachedPath.Free(); FCachedPath := nil; end;
end;

procedure TSVGCircleElement.SetAnimatedR(AVal: Double);
begin
  FR := SVGLength(AVal);
  if Assigned(FCachedPath) then begin FCachedPath.Free(); FCachedPath := nil; end;
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
  FBaseCx := FCx;
  FBaseCy := FCy;
  FBaseRx := FRx;
  FBaseRy := FRy;
  FCachedPath := nil;
end;

destructor TSVGEllipseElement.Destroy();
begin
  if Assigned(FCachedPath) then FCachedPath.Free();
  inherited Destroy();
end;

procedure TSVGEllipseElement.SetCx(const AVal: TSVGLength);
begin
  FCx := AVal;
  FBaseCx := AVal;
  if Assigned(FCachedPath) then begin FCachedPath.Free(); FCachedPath := nil; end;
end;

procedure TSVGEllipseElement.SetCy(const AVal: TSVGLength);
begin
  FCy := AVal;
  FBaseCy := AVal;
  if Assigned(FCachedPath) then begin FCachedPath.Free(); FCachedPath := nil; end;
end;

procedure TSVGEllipseElement.SetRx(const AVal: TSVGLength);
begin
  FRx := AVal;
  FBaseRx := AVal;
  if Assigned(FCachedPath) then begin FCachedPath.Free(); FCachedPath := nil; end;
end;

procedure TSVGEllipseElement.SetRy(const AVal: TSVGLength);
begin
  FRy := AVal;
  FBaseRy := AVal;
  if Assigned(FCachedPath) then begin FCachedPath.Free(); FCachedPath := nil; end;
end;

procedure TSVGEllipseElement.ResetAnimationState();
begin
  inherited ResetAnimationState();
  FCx := FBaseCx;
  FCy := FBaseCy;
  FRx := FBaseRx;
  FRy := FBaseRy;
  if Assigned(FCachedPath) then begin FCachedPath.Free(); FCachedPath := nil; end;
end;

procedure TSVGEllipseElement.SetAnimatedCx(AVal: Double);
begin
  FCx := SVGLength(AVal);
  if Assigned(FCachedPath) then begin FCachedPath.Free(); FCachedPath := nil; end;
end;

procedure TSVGEllipseElement.SetAnimatedCy(AVal: Double);
begin
  FCy := SVGLength(AVal);
  if Assigned(FCachedPath) then begin FCachedPath.Free(); FCachedPath := nil; end;
end;

procedure TSVGEllipseElement.SetAnimatedRx(AVal: Double);
begin
  FRx := SVGLength(AVal);
  if Assigned(FCachedPath) then begin FCachedPath.Free(); FCachedPath := nil; end;
end;

procedure TSVGEllipseElement.SetAnimatedRy(AVal: Double);
begin
  FRy := SVGLength(AVal);
  if Assigned(FCachedPath) then begin FCachedPath.Free(); FCachedPath := nil; end;
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
  FBaseX1 := FX1;
  FBaseY1 := FY1;
  FBaseX2 := FX2;
  FBaseY2 := FY2;
  FCachedPath := nil;
end;

destructor TSVGLineElement.Destroy();
begin
  if Assigned(FCachedPath) then FCachedPath.Free();
  inherited Destroy();
end;

procedure TSVGLineElement.SetX1(const AVal: TSVGLength);
begin
  FX1 := AVal;
  FBaseX1 := AVal;
  if Assigned(FCachedPath) then begin FCachedPath.Free(); FCachedPath := nil; end;
end;

procedure TSVGLineElement.SetY1(const AVal: TSVGLength);
begin
  FY1 := AVal;
  FBaseY1 := AVal;
  if Assigned(FCachedPath) then begin FCachedPath.Free(); FCachedPath := nil; end;
end;

procedure TSVGLineElement.SetX2(const AVal: TSVGLength);
begin
  FX2 := AVal;
  FBaseX2 := AVal;
  if Assigned(FCachedPath) then begin FCachedPath.Free(); FCachedPath := nil; end;
end;

procedure TSVGLineElement.SetY2(const AVal: TSVGLength);
begin
  FY2 := AVal;
  FBaseY2 := AVal;
  if Assigned(FCachedPath) then begin FCachedPath.Free(); FCachedPath := nil; end;
end;

procedure TSVGLineElement.ResetAnimationState();
begin
  inherited ResetAnimationState();
  FX1 := FBaseX1;
  FY1 := FBaseY1;
  FX2 := FBaseX2;
  FY2 := FBaseY2;
  if Assigned(FCachedPath) then begin FCachedPath.Free(); FCachedPath := nil; end;
end;

procedure TSVGLineElement.SetAnimatedX1(AVal: Double);
begin
  FX1 := SVGLength(AVal);
  if Assigned(FCachedPath) then begin FCachedPath.Free(); FCachedPath := nil; end;
end;

procedure TSVGLineElement.SetAnimatedY1(AVal: Double);
begin
  FY1 := SVGLength(AVal);
  if Assigned(FCachedPath) then begin FCachedPath.Free(); FCachedPath := nil; end;
end;

procedure TSVGLineElement.SetAnimatedX2(AVal: Double);
begin
  FX2 := SVGLength(AVal);
  if Assigned(FCachedPath) then begin FCachedPath.Free(); FCachedPath := nil; end;
end;

procedure TSVGLineElement.SetAnimatedY2(AVal: Double);
begin
  FY2 := SVGLength(AVal);
  if Assigned(FCachedPath) then begin FCachedPath.Free(); FCachedPath := nil; end;
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

// ── Animation Helpers ────────────────────────────────────────────────────────

function ParseSVGDuration(const S: string): Double;
var
  TrimS: string;
  ValD: Double;
  Code: Integer;
begin
  Result := 0.0;
  TrimS := LowerCase(Trim(S));
  if TrimS = '' then Exit;
  if (TrimS = 'indefinite') or (TrimS = 'media') then
    Exit(1e9);

  if (Length(TrimS) > 2) and (Copy(TrimS, Length(TrimS) - 1, 2) = 'ms') then
  begin
    TrimS := Copy(TrimS, 1, Length(TrimS) - 2);
    ValD := 0.0;
    System.Val(TrimS, ValD, Code);
    if Code = 0 then Result := ValD * 0.001;
  end
  else if (Length(TrimS) > 1) and (TrimS[Length(TrimS)] = 's') then
  begin
    TrimS := Copy(TrimS, 1, Length(TrimS) - 1);
    ValD := 0.0;
    System.Val(TrimS, ValD, Code);
    if Code = 0 then Result := ValD;
  end
  else if (Length(TrimS) > 3) and (Copy(TrimS, Length(TrimS) - 2, 3) = 'min') then
  begin
    TrimS := Copy(TrimS, 1, Length(TrimS) - 3);
    ValD := 0.0;
    System.Val(TrimS, ValD, Code);
    if Code = 0 then Result := ValD * 60.0;
  end
  else if (Length(TrimS) > 1) and (TrimS[Length(TrimS)] = 'h') then
  begin
    TrimS := Copy(TrimS, 1, Length(TrimS) - 1);
    ValD := 0.0;
    System.Val(TrimS, ValD, Code);
    if Code = 0 then Result := ValD * 3600.0;
  end
  else
  begin
    ValD := 0.0;
    System.Val(TrimS, ValD, Code);
    if Code = 0 then Result := ValD;
  end;
end;

function ParseFloatList(const S: string): TDoubleArray;
var
  I, Len, StartPos, Count: Integer;
  NumStr: string;
  DVal: Double;
  Code: Integer;
begin
  SetLength(Result, 4);
  Count := 0;
  I := 1;
  Len := Length(S);
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
        if Count >= Length(Result) then
          SetLength(Result, Length(Result) * 2);
        Result[Count] := DVal;
        Inc(Count);
      end;
    end
    else
      Inc(I);
  end;
  SetLength(Result, Count);
end;

procedure ParseSemicolonList(const S: string; AList: TStrings);
var
  I, StartPos, Len: Integer;
  Token: string;
begin
  AList.Clear();
  Len := Length(S);
  StartPos := 1;
  for I := 1 to Len do
  begin
    if S[I] = ';' then
    begin
      Token := Trim(Copy(S, StartPos, I - StartPos));
      if Token <> '' then
        AList.Add(Token);
      StartPos := I + 1;
    end;
  end;
  if StartPos <= Len then
  begin
    Token := Trim(Copy(S, StartPos, Len - StartPos + 1));
    if Token <> '' then
      AList.Add(Token);
  end;
end;

function InterpolateColor(const C1, C2: TCSSColor; U: Double): TCSSColor;
var
  R, G, B, A: Byte;
begin
  R := EnsureRange(Round(C1.R + (C2.R - C1.R) * U), 0, 255);
  G := EnsureRange(Round(C1.G + (C2.G - C1.G) * U), 0, 255);
  B := EnsureRange(Round(C1.B + (C2.B - C1.B) * U), 0, 255);
  A := EnsureRange(Round(C1.A + (C2.A - C1.A) * U), 0, 255);
  Result := TCSSColor.FromRGBA(R, G, B, A);
end;

procedure GetInterpolationEndpoints(Values: TStrings; const FromV, ToV: string;
  Progress: Double; out V1, V2: string; out SubProgress: Double);
var
  N, Idx: Integer;
  D: Double;
begin
  SubProgress := Progress;
  V1 := '';
  V2 := '';
  if Values.Count >= 2 then
  begin
    N := Values.Count;
    if Progress >= 1.0 then
    begin
      V1 := Values[N - 2];
      V2 := Values[N - 1];
      SubProgress := 1.0;
    end
    else
    begin
      D := Progress * (N - 1);
      Idx := Trunc(D);
      if Idx > N - 2 then Idx := N - 2;
      SubProgress := D - Idx;
      V1 := Values[Idx];
      V2 := Values[Idx + 1];
    end;
  end
  else if (FromV <> '') and (ToV <> '') then
  begin
    V1 := FromV;
    V2 := ToV;
    SubProgress := Progress;
  end
  else if ToV <> '' then
  begin
    V1 := '';
    V2 := ToV;
    SubProgress := Progress;
  end;
end;

// ── TSVGAnimationElement Implementation ──────────────────────────────────────

constructor TSVGAnimationElement.Create(const ATagName: string; ADoc: TSVGDocument = nil);
begin
  inherited Create(ATagName, ADoc);
  FAttributeName := '';
  FValues := TStringList.Create();
  FFromVal := '';
  FToVal := '';
  FByVal := '';
  FBeginSec := 0.0;
  FDurSec := 0.0;
  FRepeatCount := 1.0;
  FRepeatIndefinite := False;
  FFillMode := afmRemove;
  FAdditive := ataReplace;
  FHref := '';
  FTargetElement := nil;
end;

destructor TSVGAnimationElement.Destroy();
begin
  FValues.Free();
  inherited Destroy();
end;

function TSVGAnimationElement.GetEffectiveDuration(): Double;
begin
  if FRepeatIndefinite then
    Result := 1e9
  else if FRepeatCount > 0.0 then
    Result := FBeginSec + FDurSec * FRepeatCount
  else
    Result := FBeginSec + FDurSec;
end;

function TSVGAnimationElement.GetNormalizedProgress(CurrentTimeSec: Double; out IsActive: Boolean): Double;
var
  RelTime, ActiveDur, CycleTime: Double;
begin
  IsActive := False;
  Result := 0.0;

  if FDurSec <= 0.000001 then
  begin
    if CurrentTimeSec >= FBeginSec then
    begin
      IsActive := True;
      Result := 1.0;
    end;
    Exit;
  end;

  if CurrentTimeSec < FBeginSec then
    Exit;

  RelTime := CurrentTimeSec - FBeginSec;

  if FRepeatIndefinite then
  begin
    IsActive := True;
    CycleTime := RelTime - (Trunc(RelTime / FDurSec) * FDurSec);
    Result := CycleTime / FDurSec;
    Exit;
  end;

  ActiveDur := FDurSec * Max(1.0, FRepeatCount);
  if RelTime < ActiveDur then
  begin
    IsActive := True;
    CycleTime := RelTime - (Trunc(RelTime / FDurSec) * FDurSec);
    Result := CycleTime / FDurSec;
  end
  else
  begin
    if FFillMode = afmFreeze then
    begin
      IsActive := True;
      Result := 1.0;
    end
    else
      IsActive := False;
  end;
end;

// ── TSVGAnimateTransformElement Implementation ───────────────────────────────

constructor TSVGAnimateTransformElement.Create(ADoc: TSVGDocument = nil);
begin
  inherited Create('animateTransform', ADoc);
  FTransformType := attRotate;
end;

procedure TSVGAnimateTransformElement.ApplyAtTime(CurrentTimeSec: Double);
var
  IsActive: Boolean;
  Progress, SubProgress: Double;
  V1, V2: string;
  P1, P2: TDoubleArray;
  A1, A2, A, CX1, CX2, CX, CY1, CY2, CY: Double;
  TX1, TX2, TX, TY1, TY2, TY: Double;
  SX1, SX2, SX, SY1, SY2, SY: Double;
  Mat: TSVGMatrix;
begin
  if FTargetElement = nil then Exit;

  Progress := GetNormalizedProgress(CurrentTimeSec, IsActive);
  if not IsActive then Exit;

  GetInterpolationEndpoints(FValues, FFromVal, FToVal, Progress, V1, V2, SubProgress);
  if (V1 = '') and (V2 = '') then Exit;

  P1 := ParseFloatList(V1);
  P2 := ParseFloatList(V2);

  Mat := SVGMatrixIdentity();

  case FTransformType of
    attRotate:
    begin
      A1 := 0.0; CX1 := 0.0; CY1 := 0.0;
      if Length(P1) > 0 then A1 := P1[0];
      if Length(P1) > 1 then CX1 := P1[1];
      if Length(P1) > 2 then CY1 := P1[2];

      A2 := 0.0; CX2 := 0.0; CY2 := 0.0;
      if Length(P2) > 0 then A2 := P2[0];
      if Length(P2) > 1 then CX2 := P2[1];
      if Length(P2) > 2 then CY2 := P2[2];

      A := A1 + (A2 - A1) * SubProgress;
      CX := CX1 + (CX2 - CX1) * SubProgress;
      CY := CY1 + (CY2 - CY1) * SubProgress;

      if (CX <> 0.0) or (CY <> 0.0) then
        Mat := SVGMatrixRotateAt(A, CX, CY)
      else
        Mat := SVGMatrixRotate(A);
    end;

    attTranslate:
    begin
      TX1 := 0.0; TY1 := 0.0;
      if Length(P1) > 0 then TX1 := P1[0];
      if Length(P1) > 1 then TY1 := P1[1];

      TX2 := 0.0; TY2 := 0.0;
      if Length(P2) > 0 then TX2 := P2[0];
      if Length(P2) > 1 then TY2 := P2[1];

      TX := TX1 + (TX2 - TX1) * SubProgress;
      TY := TY1 + (TY2 - TY1) * SubProgress;
      Mat := SVGMatrixTranslate(TX, TY);
    end;

    attScale:
    begin
      SX1 := 1.0; SY1 := 1.0;
      if Length(P1) > 0 then begin SX1 := P1[0]; SY1 := P1[0]; end;
      if Length(P1) > 1 then SY1 := P1[1];

      SX2 := 1.0; SY2 := 1.0;
      if Length(P2) > 0 then begin SX2 := P2[0]; SY2 := P2[0]; end;
      if Length(P2) > 1 then SY2 := P2[1];

      SX := SX1 + (SX2 - SX1) * SubProgress;
      SY := SY1 + (SY2 - SY1) * SubProgress;
      Mat := SVGMatrixScale(SX, SY);
    end;

    attSkewX:
    begin
      A1 := 0.0; A2 := 0.0;
      if Length(P1) > 0 then A1 := P1[0];
      if Length(P2) > 0 then A2 := P2[0];
      A := A1 + (A2 - A1) * SubProgress;
      Mat := SVGMatrixSkewX(A);
    end;

    attSkewY:
    begin
      A1 := 0.0; A2 := 0.0;
      if Length(P1) > 0 then A1 := P1[0];
      if Length(P2) > 0 then A2 := P2[0];
      A := A1 + (A2 - A1) * SubProgress;
      Mat := SVGMatrixSkewY(A);
    end;
  end;

  if FAdditive = ataSum then
  begin
    if FTargetElement.HasAnimatedTransform then
      FTargetElement.AnimatedTransform := SVGMatrixMultiply(FTargetElement.AnimatedTransform, Mat)
    else
      FTargetElement.AnimatedTransform := SVGMatrixMultiply(FTargetElement.Transform, Mat);
  end
  else
  begin
    FTargetElement.AnimatedTransform := Mat;
  end;
  FTargetElement.HasAnimatedTransform := True;
end;

// ── TSVGAnimateElement Implementation ────────────────────────────────────────

constructor TSVGAnimateElement.Create(ADoc: TSVGDocument = nil);
begin
  inherited Create('animate', ADoc);
end;

procedure TSVGAnimateElement.ApplyAtTime(CurrentTimeSec: Double);
var
  IsActive: Boolean;
  Progress, SubProgress, D1, D2, InterpD: Double;
  V1, V2, LowAttr: string;
  Code: Integer;
  Paint1, Paint2: TSVGPaint;
  InterpCol: TCSSColor;
begin
  if FTargetElement = nil then Exit;

  Progress := GetNormalizedProgress(CurrentTimeSec, IsActive);
  if not IsActive then Exit;

  GetInterpolationEndpoints(FValues, FFromVal, FToVal, Progress, V1, V2, SubProgress);
  if (V1 = '') and (V2 = '') then Exit;

  LowAttr := LowerCase(Trim(FAttributeName));

  if (LowAttr = 'opacity') or (LowAttr = 'fill-opacity') or (LowAttr = 'stroke-opacity') then
  begin
    D1 := 1.0; D2 := 1.0;
    if V1 <> '' then System.Val(V1, D1, Code);
    if V2 <> '' then System.Val(V2, D2, Code);
    InterpD := D1 + (D2 - D1) * SubProgress;
    FTargetElement.AnimatedOpacity := Max(0.0, Min(1.0, InterpD));
    FTargetElement.HasAnimatedOpacity := True;
  end
  else if LowAttr = 'fill' then
  begin
    Paint1 := SVGParsePaint(V1);
    Paint2 := SVGParsePaint(V2);
    if (Paint1.Kind = pkColor) and (Paint2.Kind = pkColor) then
    begin
      InterpCol := InterpolateColor(Paint1.Color, Paint2.Color, SubProgress);
      Paint1.Kind := pkColor;
      Paint1.Color := InterpCol;
      Paint1.UriId := '';
      FTargetElement.AnimatedFill := Paint1;
      FTargetElement.HasAnimatedFill := True;
    end
    else if Paint2.Kind <> pkNone then
    begin
      FTargetElement.AnimatedFill := Paint2;
      FTargetElement.HasAnimatedFill := True;
    end;
  end
  else if LowAttr = 'stroke' then
  begin
    Paint1 := SVGParsePaint(V1);
    Paint2 := SVGParsePaint(V2);
    if (Paint1.Kind = pkColor) and (Paint2.Kind = pkColor) then
    begin
      InterpCol := InterpolateColor(Paint1.Color, Paint2.Color, SubProgress);
      Paint1.Kind := pkColor;
      Paint1.Color := InterpCol;
      Paint1.UriId := '';
      FTargetElement.AnimatedStroke := Paint1;
      FTargetElement.HasAnimatedStroke := True;
    end
    else if Paint2.Kind <> pkNone then
    begin
      FTargetElement.AnimatedStroke := Paint2;
      FTargetElement.HasAnimatedStroke := True;
    end;
  end
  else if LowAttr = 'stroke-width' then
  begin
    D1 := 1.0; D2 := 1.0;
    if V1 <> '' then System.Val(V1, D1, Code);
    if V2 <> '' then System.Val(V2, D2, Code);
    InterpD := D1 + (D2 - D1) * SubProgress;
    FTargetElement.AnimatedStrokeWidth := Max(0.0, InterpD);
    FTargetElement.HasAnimatedStrokeWidth := True;
  end
  else
  begin
    D1 := 0.0; D2 := 0.0;
    if V1 <> '' then System.Val(V1, D1, Code);
    if V2 <> '' then System.Val(V2, D2, Code);
    InterpD := D1 + (D2 - D1) * SubProgress;

    if FTargetElement is TSVGRectElement then
    begin
      if LowAttr = 'x' then TSVGRectElement(FTargetElement).SetAnimatedX(InterpD)
      else if LowAttr = 'y' then TSVGRectElement(FTargetElement).SetAnimatedY(InterpD)
      else if LowAttr = 'width' then TSVGRectElement(FTargetElement).SetAnimatedWidth(InterpD)
      else if LowAttr = 'height' then TSVGRectElement(FTargetElement).SetAnimatedHeight(InterpD)
      else if LowAttr = 'rx' then TSVGRectElement(FTargetElement).SetAnimatedRx(InterpD)
      else if LowAttr = 'ry' then TSVGRectElement(FTargetElement).SetAnimatedRy(InterpD);
    end
    else if FTargetElement is TSVGCircleElement then
    begin
      if LowAttr = 'cx' then TSVGCircleElement(FTargetElement).SetAnimatedCx(InterpD)
      else if LowAttr = 'cy' then TSVGCircleElement(FTargetElement).SetAnimatedCy(InterpD)
      else if LowAttr = 'r' then TSVGCircleElement(FTargetElement).SetAnimatedR(InterpD);
    end
    else if FTargetElement is TSVGEllipseElement then
    begin
      if LowAttr = 'cx' then TSVGEllipseElement(FTargetElement).SetAnimatedCx(InterpD)
      else if LowAttr = 'cy' then TSVGEllipseElement(FTargetElement).SetAnimatedCy(InterpD)
      else if LowAttr = 'rx' then TSVGEllipseElement(FTargetElement).SetAnimatedRx(InterpD)
      else if LowAttr = 'ry' then TSVGEllipseElement(FTargetElement).SetAnimatedRy(InterpD);
    end
    else if FTargetElement is TSVGLineElement then
    begin
      if LowAttr = 'x1' then TSVGLineElement(FTargetElement).SetAnimatedX1(InterpD)
      else if LowAttr = 'y1' then TSVGLineElement(FTargetElement).SetAnimatedY1(InterpD)
      else if LowAttr = 'x2' then TSVGLineElement(FTargetElement).SetAnimatedX2(InterpD)
      else if LowAttr = 'y2' then TSVGLineElement(FTargetElement).SetAnimatedY2(InterpD);
    end;
  end;
end;

// ── TSVGSetElement Implementation ────────────────────────────────────────────

constructor TSVGSetElement.Create(ADoc: TSVGDocument = nil);
begin
  inherited Create(ADoc);
  FTagName := 'set';
  FDurSec := 0.0;
  FFillMode := afmFreeze;
end;

procedure TSVGSetElement.ApplyAtTime(CurrentTimeSec: Double);
var
  IsActive: Boolean;
begin
  if FTargetElement = nil then Exit;
  GetNormalizedProgress(CurrentTimeSec, IsActive);
  if not IsActive then Exit;

  FFromVal := FToVal;
  inherited ApplyAtTime(CurrentTimeSec);
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
  FAnimations := TObjectList.Create(True);
  FCurrentTimeSec := 0.0;
  FLastTargetW := 0.0;
  FLastTargetH := 0.0;
end;

destructor TSVGDocument.Destroy();
begin
  FAnimations.Free();
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

procedure TSVGDocument.RegisterAnimation(AAnim: TSVGAnimationElement);
begin
  if Assigned(AAnim) and (FAnimations.IndexOf(AAnim) < 0) then
    FAnimations.Add(AAnim);
end;

function TSVGDocument.HasAnimation(): Boolean;
begin
  Result := (FAnimations.Count > 0);
end;

function TSVGDocument.GetAnimationDuration(): Double;
var
  I: Integer;
  Anim: TSVGAnimationElement;
  D: Double;
begin
  Result := 0.0;
  for I := 0 to FAnimations.Count - 1 do
  begin
    Anim := TSVGAnimationElement(FAnimations[I]);
    if Anim.RepeatIndefinite then
      Exit(0.0);
    D := Anim.GetEffectiveDuration();
    if D > Result then
      Result := D;
  end;
end;

procedure TSVGDocument.ResetAnimation();
begin
  SetCurrentTime(0.0);
end;

procedure TSVGDocument.ResetElementAnimationState();
begin
  if Assigned(FRoot) then
    FRoot.ResetAnimationState();
end;

procedure TSVGDocument.SetCurrentTime(TimeSec: Double);
var
  I: Integer;
  Anim: TSVGAnimationElement;
begin
  FCurrentTimeSec := TimeSec;
  if FAnimations.Count = 0 then Exit;

  ResetElementAnimationState();

  for I := 0 to FAnimations.Count - 1 do
  begin
    Anim := TSVGAnimationElement(FAnimations[I]);
    Anim.ApplyAtTime(TimeSec);
  end;

  ComputeStyles(FLastTargetW, FLastTargetH);
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

var
  I: Integer;
  Anim: TSVGAnimationElement;
  TargetId: string;
begin
  ResolveNode(FRoot);

  for I := 0 to FAnimations.Count - 1 do
  begin
    Anim := TSVGAnimationElement(FAnimations[I]);
    if (Anim.TargetElement = nil) and (Anim.Href <> '') then
    begin
      TargetId := Anim.Href;
      if (Length(TargetId) > 0) and (TargetId[1] = '#') then
        Delete(TargetId, 1, 1);
      Anim.TargetElement := FindElementById(TargetId);
    end;
  end;
end;

procedure TSVGDocument.ComputeStyles(TargetW, TargetH: Double);
var
  InitialStyle: TSVGStyleRecord;
begin
  if not Assigned(FRoot) then Exit;

  if TargetW <= 0.0 then TargetW := GetIntrinsicWidth();
  if TargetH <= 0.0 then TargetH := GetIntrinsicHeight();

  FLastTargetW := TargetW;
  FLastTargetH := TargetH;

  FRoot.ComputeViewBox(TargetW, TargetH);

  InitialStyle.InitDefaults();
  FRoot.ComputeStyles(InitialStyle, SVGMatrixIdentity());
end;

function TSVGDocument.GetIntrinsicWidth(): Double;
var
  BBox: TSVGRect;
begin
  if Assigned(FRoot) then
  begin
    if FRoot.Width.Specified and (FRoot.Width.Value > 0.0) then
      Exit(SVGLengthToPixels(FRoot.Width))
    else if FRoot.ViewBox.HasValue and (FRoot.ViewBox.Width > 0.0) then
      Exit(FRoot.ViewBox.Width)
    else
    begin
      BBox := FRoot.GetLocalBoundingBox();
      if BBox.Width > 0.0 then
        Exit(BBox.X + BBox.Width);
    end;
  end;
  Result := 300.0; // Default SVG fallback
end;

function TSVGDocument.GetIntrinsicHeight(): Double;
var
  BBox: TSVGRect;
begin
  if Assigned(FRoot) then
  begin
    if FRoot.Height.Specified and (FRoot.Height.Value > 0.0) then
      Exit(SVGLengthToPixels(FRoot.Height))
    else if FRoot.ViewBox.HasValue and (FRoot.ViewBox.Height > 0.0) then
      Exit(FRoot.ViewBox.Height)
    else
    begin
      BBox := FRoot.GetLocalBoundingBox();
      if BBox.Height > 0.0 then
        Exit(BBox.Y + BBox.Height);
    end;
  end;
  Result := 150.0; // Default SVG fallback
end;

end.
