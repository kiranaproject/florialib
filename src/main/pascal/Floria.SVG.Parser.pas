unit Floria.SVG.Parser;

// Floria.SVG.Parser
// =================
// High-level SVG document parser converting SVG XML markup into a typed
// TSVGDocument scene graph with full CSS stylesheet cascade and reference resolution.
//
// Highlights:
//   - ParseString, ParseFile, ParseStream convenience methods
//   - Built directly on top of Floria.XML.DOM and Floria.XML.Parser
//   - Maps standard SVG tags (<svg>, <g>, <defs>, <use>, <path>, <rect>, <circle>,
//     <ellipse>, <line>, <polyline>, <polygon>, <linearGradient>, <radialGradient>, <stop>)
//   - Seamless Floria.CSS stylesheet cascade integration via ICSSElement
//   - Resolves inline style="..." declarations on top of stylesheet rules
//   - W3C href and xlink:href reference resolution for <use> and gradients

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, Contnrs, Math,
  Floria.CSS.Types, Floria.CSS.Values, Floria.CSS.Properties, Floria.CSS.Cascade, Floria.CSS.Parser,
  Floria.XML.DOM, Floria.XML.Parser,
  Floria.SVG.Types, Floria.SVG.Path, Floria.SVG.DOM;

type
  { TSVGParser }

  TSVGParser = class
  private
    FDoc: TSVGDocument;
    FResolver: TCSSStyleResolver;
    procedure ParseElement(AXMLElem: TXMLElement; AParentContainer: TSVGContainerElement);
    procedure ApplyStyles(AXMLElem: TXMLElement; ASVGElem: TSVGElement);
    function ParseStopElement(AXMLElem: TXMLElement): TSVGStopElement;
  public
    constructor Create();
    destructor Destroy(); override;

    function ParseDocument(AXMLDoc: TXMLDocument): TSVGDocument;
    class function ParseString(const AXMLString: string): TSVGDocument; static;
    class function ParseFile(const AFileName: string): TSVGDocument; static;
    class function ParseStream(AStream: TStream): TSVGDocument; static;
  end;

implementation

constructor TSVGParser.Create();
begin
  inherited Create();
  FDoc := nil;
  FResolver := TCSSStyleResolver.Create();
end;

destructor TSVGParser.Destroy();
begin
  FResolver.Free();
  inherited Destroy();
end;

procedure TSVGParser.ApplyStyles(AXMLElem: TXMLElement; ASVGElem: TSVGElement);
var
  ResolvedBlock, InlineBlock: TCSSStyleBlock;
  I: Integer;
  Attr: TXMLAttribute;
  AttrName: string;
begin
  // 1. Apply presentation attributes directly
  for I := 0 to AXMLElem.AttributeCount - 1 do
  begin
    Attr := AXMLElem.Attributes[I];
    AttrName := LowerCase(Attr.Name);
    if (AttrName = 'id') or (AttrName = 'class') or (AttrName = 'style') or
       (AttrName = 'transform') or (AttrName = 'd') or (AttrName = 'points') or
       (AttrName = 'viewbox') or (AttrName = 'preserveaspectratio') then
      Continue;

    ASVGElem.Style.ApplyPresentationAttribute(AttrName, Attr.Value);
  end;

  // 2. Apply resolved CSS styles from <style> blocks
  ResolvedBlock := FResolver.ResolveStyle(AXMLElem);
  if Assigned(ResolvedBlock) then
  begin
    try
      ASVGElem.Style.ApplyCSSBlock(ResolvedBlock);
    finally
      ResolvedBlock.Free();
    end;
  end;

  // 3. Apply inline style="..." attribute (highest precedence)
  if AXMLElem.HasAttribute('style') then
  begin
    InlineBlock := TCSSStyleBlock.FromCSS(AXMLElem.GetAttribute('style'));
    if Assigned(InlineBlock) then
    begin
      try
        ASVGElem.Style.ApplyCSSBlock(InlineBlock);
      finally
        InlineBlock.Free();
      end;
    end;
  end;
end;

function TSVGParser.ParseStopElement(AXMLElem: TXMLElement): TSVGStopElement;
var
  StopElem: TSVGStopElement;
  OffStr, ColStr, OpStr: string;
  OffVal, OpVal: Double;
  Code: Integer;
  Col: TCSSColor;
begin
  StopElem := TSVGStopElement.Create(FDoc);
  if AXMLElem.HasAttribute('id') then
  begin
    StopElem.Id := AXMLElem.GetAttribute('id');
    FDoc.RegisterElement(StopElem.Id, StopElem);
  end;

  // Offset
  if AXMLElem.HasAttribute('offset') then
  begin
    OffStr := Trim(AXMLElem.GetAttribute('offset'));
    if (Length(OffStr) > 0) and (OffStr[Length(OffStr)] = '%') then
    begin
      Delete(OffStr, Length(OffStr), 1);
      OffVal := 0.0;
      System.Val(OffStr, OffVal, Code);
      if Code = 0 then StopElem.Offset := OffVal * 0.01;
    end
    else
    begin
      OffVal := 0.0;
      System.Val(OffStr, OffVal, Code);
      if Code = 0 then StopElem.Offset := OffVal;
    end;
  end;

  // Stop color and opacity
  ColStr := AXMLElem.GetAttribute('stop-color');
  if (ColStr <> '') and TCSSColor.TryParse(ColStr, Col) then
    StopElem.Color := Col;

  OpStr := AXMLElem.GetAttribute('stop-opacity');
  if OpStr <> '' then
  begin
    OpVal := 1.0;
    System.Val(OpStr, OpVal, Code);
    if Code = 0 then
    begin
      Col := StopElem.Color;
      Col.A := Round(Max(0.0, Min(1.0, OpVal)) * 255);
      StopElem.Color := Col;
    end;
  end;

  Result := StopElem;
end;

procedure TSVGParser.ParseElement(AXMLElem: TXMLElement; AParentContainer: TSVGContainerElement);
var
  Tag: string;
  I: Integer;
  ChildNode: TXMLNode;

  PathElem: TSVGPathElement;
  RectElem: TSVGRectElement;
  CircleElem: TSVGCircleElement;
  EllipseElem: TSVGEllipseElement;
  LineElem: TSVGLineElement;
  PolylineElem: TSVGPolylineElement;
  PolygonElem: TSVGPolygonElement;
  GroupElem: TSVGGroupElement;
  DefsElem: TSVGDefsElement;
  UseElem: TSVGUseElement;
  LinGrad: TSVGLinearGradientElement;
  RadGrad: TSVGRadialGradientElement;
  CreatedElem: TSVGElement;
  HrefVal: string;
begin
  Tag := LowerCase(AXMLElem.TagName);
  CreatedElem := nil;

  if Tag = 'path' then
  begin
    PathElem := TSVGPathElement.Create(FDoc);
    if AXMLElem.HasAttribute('d') then
      PathElem.SetPathData(AXMLElem.GetAttribute('d'));
    CreatedElem := PathElem;
  end
  else if Tag = 'rect' then
  begin
    RectElem := TSVGRectElement.Create(FDoc);
    if AXMLElem.HasAttribute('x') then RectElem.X := SVGParseLength(AXMLElem.GetAttribute('x'));
    if AXMLElem.HasAttribute('y') then RectElem.Y := SVGParseLength(AXMLElem.GetAttribute('y'));
    if AXMLElem.HasAttribute('width') then RectElem.Width := SVGParseLength(AXMLElem.GetAttribute('width'));
    if AXMLElem.HasAttribute('height') then RectElem.Height := SVGParseLength(AXMLElem.GetAttribute('height'));
    if AXMLElem.HasAttribute('rx') then RectElem.Rx := SVGParseLength(AXMLElem.GetAttribute('rx'));
    if AXMLElem.HasAttribute('ry') then RectElem.Ry := SVGParseLength(AXMLElem.GetAttribute('ry'));
    CreatedElem := RectElem;
  end
  else if Tag = 'circle' then
  begin
    CircleElem := TSVGCircleElement.Create(FDoc);
    if AXMLElem.HasAttribute('cx') then CircleElem.Cx := SVGParseLength(AXMLElem.GetAttribute('cx'));
    if AXMLElem.HasAttribute('cy') then CircleElem.Cy := SVGParseLength(AXMLElem.GetAttribute('cy'));
    if AXMLElem.HasAttribute('r') then CircleElem.R := SVGParseLength(AXMLElem.GetAttribute('r'));
    CreatedElem := CircleElem;
  end
  else if Tag = 'ellipse' then
  begin
    EllipseElem := TSVGEllipseElement.Create(FDoc);
    if AXMLElem.HasAttribute('cx') then EllipseElem.Cx := SVGParseLength(AXMLElem.GetAttribute('cx'));
    if AXMLElem.HasAttribute('cy') then EllipseElem.Cy := SVGParseLength(AXMLElem.GetAttribute('cy'));
    if AXMLElem.HasAttribute('rx') then EllipseElem.Rx := SVGParseLength(AXMLElem.GetAttribute('rx'));
    if AXMLElem.HasAttribute('ry') then EllipseElem.Ry := SVGParseLength(AXMLElem.GetAttribute('ry'));
    CreatedElem := EllipseElem;
  end
  else if Tag = 'line' then
  begin
    LineElem := TSVGLineElement.Create(FDoc);
    if AXMLElem.HasAttribute('x1') then LineElem.X1 := SVGParseLength(AXMLElem.GetAttribute('x1'));
    if AXMLElem.HasAttribute('y1') then LineElem.Y1 := SVGParseLength(AXMLElem.GetAttribute('y1'));
    if AXMLElem.HasAttribute('x2') then LineElem.X2 := SVGParseLength(AXMLElem.GetAttribute('x2'));
    if AXMLElem.HasAttribute('y2') then LineElem.Y2 := SVGParseLength(AXMLElem.GetAttribute('y2'));
    CreatedElem := LineElem;
  end
  else if Tag = 'polyline' then
  begin
    PolylineElem := TSVGPolylineElement.Create(FDoc);
    if AXMLElem.HasAttribute('points') then
      PolylineElem.SetPointsString(AXMLElem.GetAttribute('points'));
    CreatedElem := PolylineElem;
  end
  else if Tag = 'polygon' then
  begin
    PolygonElem := TSVGPolygonElement.Create(FDoc);
    if AXMLElem.HasAttribute('points') then
      PolygonElem.SetPointsString(AXMLElem.GetAttribute('points'));
    CreatedElem := PolygonElem;
  end
  else if Tag = 'g' then
  begin
    GroupElem := TSVGGroupElement.Create(FDoc);
    CreatedElem := GroupElem;
    // Recurse children
    for I := 0 to AXMLElem.ChildCount - 1 do
    begin
      ChildNode := AXMLElem.Children[I];
      if ChildNode is TXMLElement then
        ParseElement(TXMLElement(ChildNode), GroupElem);
    end;
  end
  else if Tag = 'defs' then
  begin
    DefsElem := TSVGDefsElement.Create(FDoc);
    CreatedElem := DefsElem;
    for I := 0 to AXMLElem.ChildCount - 1 do
    begin
      ChildNode := AXMLElem.Children[I];
      if ChildNode is TXMLElement then
        ParseElement(TXMLElement(ChildNode), DefsElem);
    end;
  end
  else if Tag = 'use' then
  begin
    UseElem := TSVGUseElement.Create(FDoc);
    if AXMLElem.HasAttribute('href') then
      UseElem.Href := AXMLElem.GetAttribute('href')
    else if AXMLElem.HasAttribute('xlink:href') then
      UseElem.Href := AXMLElem.GetAttribute('xlink:href');

    if AXMLElem.HasAttribute('x') then UseElem.X := SVGParseLength(AXMLElem.GetAttribute('x'));
    if AXMLElem.HasAttribute('y') then UseElem.Y := SVGParseLength(AXMLElem.GetAttribute('y'));
    if AXMLElem.HasAttribute('width') then UseElem.Width := SVGParseLength(AXMLElem.GetAttribute('width'));
    if AXMLElem.HasAttribute('height') then UseElem.Height := SVGParseLength(AXMLElem.GetAttribute('height'));
    CreatedElem := UseElem;
  end
  else if Tag = 'lineargradient' then
  begin
    LinGrad := TSVGLinearGradientElement.Create(FDoc);
    if AXMLElem.HasAttribute('x1') then LinGrad.X1 := SVGParseLength(AXMLElem.GetAttribute('x1'), suPercent);
    if AXMLElem.HasAttribute('y1') then LinGrad.Y1 := SVGParseLength(AXMLElem.GetAttribute('y1'), suPercent);
    if AXMLElem.HasAttribute('x2') then LinGrad.X2 := SVGParseLength(AXMLElem.GetAttribute('x2'), suPercent);
    if AXMLElem.HasAttribute('y2') then LinGrad.Y2 := SVGParseLength(AXMLElem.GetAttribute('y2'), suPercent);
    if AXMLElem.HasAttribute('gradientTransform') then
      LinGrad.GradientTransform := SVGParseTransform(AXMLElem.GetAttribute('gradientTransform'));

    HrefVal := AXMLElem.GetAttribute('href');
    if HrefVal = '' then HrefVal := AXMLElem.GetAttribute('xlink:href');
    LinGrad.Href := HrefVal;

    for I := 0 to AXMLElem.ChildCount - 1 do
    begin
      ChildNode := AXMLElem.Children[I];
      if (ChildNode is TXMLElement) and (LowerCase(TXMLElement(ChildNode).TagName) = 'stop') then
        LinGrad.AddStop(ParseStopElement(TXMLElement(ChildNode)));
    end;
    CreatedElem := LinGrad;
  end
  else if Tag = 'radialgradient' then
  begin
    RadGrad := TSVGRadialGradientElement.Create(FDoc);
    if AXMLElem.HasAttribute('cx') then RadGrad.Cx := SVGParseLength(AXMLElem.GetAttribute('cx'), suPercent);
    if AXMLElem.HasAttribute('cy') then RadGrad.Cy := SVGParseLength(AXMLElem.GetAttribute('cy'), suPercent);
    if AXMLElem.HasAttribute('r') then RadGrad.R := SVGParseLength(AXMLElem.GetAttribute('r'), suPercent);
    if AXMLElem.HasAttribute('fx') then RadGrad.Fx := SVGParseLength(AXMLElem.GetAttribute('fx'), suPercent);
    if AXMLElem.HasAttribute('fy') then RadGrad.Fy := SVGParseLength(AXMLElem.GetAttribute('fy'), suPercent);
    if AXMLElem.HasAttribute('gradientTransform') then
      RadGrad.GradientTransform := SVGParseTransform(AXMLElem.GetAttribute('gradientTransform'));

    HrefVal := AXMLElem.GetAttribute('href');
    if HrefVal = '' then HrefVal := AXMLElem.GetAttribute('xlink:href');
    RadGrad.Href := HrefVal;

    for I := 0 to AXMLElem.ChildCount - 1 do
    begin
      ChildNode := AXMLElem.Children[I];
      if (ChildNode is TXMLElement) and (LowerCase(TXMLElement(ChildNode).TagName) = 'stop') then
        RadGrad.AddStop(ParseStopElement(TXMLElement(ChildNode)));
    end;
    CreatedElem := RadGrad;
  end
  else
  begin
    // Unknown or container element (like <a>): process children
    for I := 0 to AXMLElem.ChildCount - 1 do
    begin
      ChildNode := AXMLElem.Children[I];
      if ChildNode is TXMLElement then
        ParseElement(TXMLElement(ChildNode), AParentContainer);
    end;
    Exit;
  end;

  if Assigned(CreatedElem) then
  begin
    if AXMLElem.HasAttribute('id') then
    begin
      CreatedElem.Id := AXMLElem.GetAttribute('id');
      FDoc.RegisterElement(CreatedElem.Id, CreatedElem);
    end;

    if AXMLElem.HasAttribute('transform') then
      CreatedElem.Transform := SVGParseTransform(AXMLElem.GetAttribute('transform'));

    ApplyStyles(AXMLElem, CreatedElem);

    if Assigned(AParentContainer) then
      AParentContainer.AddChild(CreatedElem);
  end;
end;

function TSVGParser.ParseDocument(AXMLDoc: TXMLDocument): TSVGDocument;
var
  RootElem: TXMLElement;
  StyleNodes: TObjectList;
  I: Integer;
  StyleElem: TXMLElement;
  ChildNode: TXMLNode;
begin
  if not Assigned(AXMLDoc) or not Assigned(AXMLDoc.DocumentElement) then
    Exit(nil);

  RootElem := AXMLDoc.DocumentElement;
  if LowerCase(RootElem.TagName) <> 'svg' then
    Exit(nil);

  FDoc := TSVGDocument.Create();
  FResolver.Clear();

  // 1. Collect all <style> elements and parse stylesheets
  StyleNodes := AXMLDoc.GetElementsByTagName('style');
  try
    for I := 0 to StyleNodes.Count - 1 do
    begin
      StyleElem := TXMLElement(StyleNodes[I]);
      if StyleElem.TextContent <> '' then
      begin
        FResolver.AddCSS(StyleElem.TextContent);
      end;
    end;
  finally
    StyleNodes.Free();
  end;

  // 2. Configure Root <svg> attributes
  if RootElem.HasAttribute('id') then
  begin
    FDoc.Root.Id := RootElem.GetAttribute('id');
    FDoc.RegisterElement(FDoc.Root.Id, FDoc.Root);
  end;

  if RootElem.HasAttribute('x') then FDoc.Root.X := SVGParseLength(RootElem.GetAttribute('x'));
  if RootElem.HasAttribute('y') then FDoc.Root.Y := SVGParseLength(RootElem.GetAttribute('y'));
  if RootElem.HasAttribute('width') then FDoc.Root.Width := SVGParseLength(RootElem.GetAttribute('width'));
  if RootElem.HasAttribute('height') then FDoc.Root.Height := SVGParseLength(RootElem.GetAttribute('height'));
  if RootElem.HasAttribute('viewBox') then FDoc.Root.ViewBox := SVGParseViewBox(RootElem.GetAttribute('viewBox'));
  if RootElem.HasAttribute('preserveAspectRatio') then
    FDoc.Root.PreserveAspectRatio := SVGParsePreserveAspectRatio(RootElem.GetAttribute('preserveAspectRatio'));

  if RootElem.HasAttribute('transform') then
    FDoc.Root.Transform := SVGParseTransform(RootElem.GetAttribute('transform'));

  ApplyStyles(RootElem, FDoc.Root);

  // 3. Recursively build child elements
  for I := 0 to RootElem.ChildCount - 1 do
  begin
    ChildNode := RootElem.Children[I];
    if ChildNode is TXMLElement then
    begin
      if LowerCase(TXMLElement(ChildNode).TagName) <> 'style' then
        ParseElement(TXMLElement(ChildNode), FDoc.Root);
    end;
  end;

  // 4. Resolve references (use, gradients)
  FDoc.ResolveReferences();

  // 5. Compute styles and viewport transforms
  FDoc.ComputeStyles(0.0, 0.0);

  Result := FDoc;
  FDoc := nil;
end;

class function TSVGParser.ParseString(const AXMLString: string): TSVGDocument;
var
  XMLDoc: TXMLDocument;
  Parser: TSVGParser;
begin
  XMLDoc := TXMLParser.ParseString(AXMLString);
  if not Assigned(XMLDoc) then Exit(nil);

  try
    Parser := TSVGParser.Create();
    try
      Result := Parser.ParseDocument(XMLDoc);
    finally
      Parser.Free();
    end;
  finally
    XMLDoc.Free();
  end;
end;

class function TSVGParser.ParseFile(const AFileName: string): TSVGDocument;
var
  XMLDoc: TXMLDocument;
  Parser: TSVGParser;
begin
  XMLDoc := TXMLParser.ParseFile(AFileName);
  if not Assigned(XMLDoc) then Exit(nil);

  try
    Parser := TSVGParser.Create();
    try
      Result := Parser.ParseDocument(XMLDoc);
    finally
      Parser.Free();
    end;
  finally
    XMLDoc.Free();
  end;
end;

class function TSVGParser.ParseStream(AStream: TStream): TSVGDocument;
var
  XMLDoc: TXMLDocument;
  Parser: TSVGParser;
begin
  XMLDoc := TXMLParser.ParseStream(AStream);
  if not Assigned(XMLDoc) then Exit(nil);

  try
    Parser := TSVGParser.Create();
    try
      Result := Parser.ParseDocument(XMLDoc);
    finally
      Parser.Free();
    end;
  finally
    XMLDoc.Free();
  end;
end;

end.
