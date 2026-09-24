unit Floria.SVG.Rasterizer;

// Floria.SVG.Rasterizer
// =====================
// High-fidelity SVG DOM document rasterizer using Floria.Canvas.Agg.
// Translates TSVGDocument and TSVGElement trees into AggPas vector paths,
// fill rules, stroke joins/caps, and linear/radial gradient spans.

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, Math,
  agg_basics,
  agg_color,
  agg_path_storage,
  agg_conv_stroke,
  agg_conv_curve,
  agg_rasterizer_scanline_aa,
  agg_scanline_u,
  agg_renderer_scanline,
  agg_render_scanlines,
  agg_renderer_base,
  agg_rendering_buffer,
  agg_pixfmt,
  agg_pixfmt_rgba,
  agg_math_stroke,
  Floria.CSS.Properties,
  Floria.SVG.Types,
  Floria.SVG.Path,
  Floria.SVG.DOM,
  Floria.SVG.Parser,
  Floria.Canvas.Agg,
  Floria.Image.Core;

type
  { TFloriaSVGRenderer }

  TFloriaSVGRenderer = class
  private
    class procedure RenderElement(ACanvas: TFloriaCanvasAgg; ADoc: TSVGDocument; AElem: TSVGElement; const AMatrix: TSVGMatrix; Depth: Integer = 0); static;
    class procedure RenderContainer(ACanvas: TFloriaCanvasAgg; ADoc: TSVGDocument; ACont: TSVGContainerElement; const AMatrix: TSVGMatrix; Depth: Integer); static;
    class procedure RenderShape(ACanvas: TFloriaCanvasAgg; ADoc: TSVGDocument; AShape: TSVGShapeElement; const AMatrix: TSVGMatrix); static;
    class procedure RenderUse(ACanvas: TFloriaCanvasAgg; ADoc: TSVGDocument; AUse: TSVGUseElement; const AMatrix: TSVGMatrix; Depth: Integer); static;
  public
    class procedure Render(ACanvas: TFloriaCanvasAgg; ADoc: TSVGDocument; X, Y, W, H: Double); overload; static;
    class procedure Render(ACanvas: TFloriaCanvasAgg; ADoc: TSVGDocument; X, Y: Double); overload; static;
    class procedure RenderString(ACanvas: TFloriaCanvasAgg; const ASVGContent: string; X, Y, W, H: Double); static;
    class procedure RenderFile(ACanvas: TFloriaCanvasAgg; const AFileName: string; X, Y, W, H: Double); static;

    class function RenderToImage(ADoc: TSVGDocument; AWidth: Integer = 0; AHeight: Integer = 0): TFloriaImage; static;
    class function RenderStringToImage(const ASVGContent: string; AWidth: Integer = 0; AHeight: Integer = 0): TFloriaImage; static;
    class function RenderFileToImage(const AFileName: string; AWidth: Integer = 0; AHeight: Integer = 0): TFloriaImage; static;

    // Backward-compatibility aliases
    class function RenderToBitmap(ADoc: TSVGDocument; AWidth: Integer = 0; AHeight: Integer = 0): TFloriaImage; static;
    class function RenderStringToBitmap(const ASVGContent: string; AWidth: Integer = 0; AHeight: Integer = 0): TFloriaImage; static;
    class function RenderFileToBitmap(const AFileName: string; AWidth: Integer = 0; AHeight: Integer = 0): TFloriaImage; static;
  end;

  // Backward-compatibility alias
  TFtSVGRenderer = TFloriaSVGRenderer;

implementation

class procedure TFloriaSVGRenderer.Render(ACanvas: TFloriaCanvasAgg; ADoc: TSVGDocument; X, Y, W, H: Double);
var
  rootSvg: TSVGSvgElement;
  targetW, targetH: Double;
  translateMat, effectiveMat: TSVGMatrix;
begin
  if not Assigned(ACanvas) or not Assigned(ADoc) or not Assigned(ADoc.Root) then Exit;

  rootSvg := ADoc.Root;
  targetW := W;
  targetH := H;
  if targetW <= 0.0 then targetW := ADoc.GetIntrinsicWidth();
  if targetH <= 0.0 then targetH := ADoc.GetIntrinsicHeight();
  if (targetW <= 0.0) or (targetH <= 0.0) then Exit;

  // Recompute document styles & viewBox transform for target dimensions
  ADoc.ComputeStyles(targetW, targetH);

  translateMat := SVGMatrixTranslate(X, Y);
  effectiveMat := SVGMatrixMultiply(translateMat, rootSvg.ViewBoxTransform);
  effectiveMat := SVGMatrixMultiply(effectiveMat, rootSvg.Transform);

  RenderElement(ACanvas, ADoc, rootSvg, effectiveMat, 0);
end;

class procedure TFloriaSVGRenderer.Render(ACanvas: TFloriaCanvasAgg; ADoc: TSVGDocument; X, Y: Double);
var
  w, h: Double;
begin
  if not Assigned(ADoc) then Exit;
  w := ADoc.GetIntrinsicWidth();
  h := ADoc.GetIntrinsicHeight();
  Render(ACanvas, ADoc, X, Y, w, h);
end;

class procedure TFloriaSVGRenderer.RenderString(ACanvas: TFloriaCanvasAgg; const ASVGContent: string; X, Y, W, H: Double);
var
  doc: TSVGDocument;
begin
  doc := TSVGParser.ParseString(ASVGContent);
  try
    Render(ACanvas, doc, X, Y, W, H);
  finally
    doc.Free();
  end;
end;

class procedure TFloriaSVGRenderer.RenderFile(ACanvas: TFloriaCanvasAgg; const AFileName: string; X, Y, W, H: Double);
var
  doc: TSVGDocument;
begin
  doc := TSVGParser.ParseFile(AFileName);
  try
    Render(ACanvas, doc, X, Y, W, H);
  finally
    doc.Free();
  end;
end;

class function TFloriaSVGRenderer.RenderToImage(ADoc: TSVGDocument; AWidth: Integer = 0; AHeight: Integer = 0): TFloriaImage;
var
  targetW, targetH: Integer;
  canvas: TFloriaCanvasAgg;
begin
  if not Assigned(ADoc) or not Assigned(ADoc.Root) then
    Exit(TFloriaImage.Create(0, 0));

  targetW := AWidth;
  targetH := AHeight;
  if targetW <= 0 then targetW := Round(ADoc.GetIntrinsicWidth());
  if targetH <= 0 then targetH := Round(ADoc.GetIntrinsicHeight());
  if (targetW <= 0) or (targetH <= 0) then
  begin
    targetW := 100;
    targetH := 100;
  end;

  Result := TFloriaImage.Create(targetW, targetH);
  Result.Clear(0, 0, 0, 0);

  canvas := TFloriaCanvasAgg.Create(Result.PixelBuffer, Result.Width, Result.Height);
  try
    Render(canvas, ADoc, 0.0, 0.0, targetW, targetH);
  finally
    canvas.Free();
  end;
end;

class function TFloriaSVGRenderer.RenderStringToImage(const ASVGContent: string; AWidth: Integer = 0; AHeight: Integer = 0): TFloriaImage;
var
  doc: TSVGDocument;
begin
  doc := TSVGParser.ParseString(ASVGContent);
  try
    Result := RenderToImage(doc, AWidth, AHeight);
  finally
    doc.Free();
  end;
end;

class function TFloriaSVGRenderer.RenderFileToImage(const AFileName: string; AWidth: Integer = 0; AHeight: Integer = 0): TFloriaImage;
var
  doc: TSVGDocument;
begin
  doc := TSVGParser.ParseFile(AFileName);
  try
    Result := RenderToImage(doc, AWidth, AHeight);
  finally
    doc.Free();
  end;
end;

class function TFloriaSVGRenderer.RenderToBitmap(ADoc: TSVGDocument; AWidth: Integer = 0; AHeight: Integer = 0): TFloriaImage;
begin
  Result := RenderToImage(ADoc, AWidth, AHeight);
end;

class function TFloriaSVGRenderer.RenderStringToBitmap(const ASVGContent: string; AWidth: Integer = 0; AHeight: Integer = 0): TFloriaImage;
begin
  Result := RenderStringToImage(ASVGContent, AWidth, AHeight);
end;

class function TFloriaSVGRenderer.RenderFileToBitmap(const AFileName: string; AWidth: Integer = 0; AHeight: Integer = 0): TFloriaImage;
begin
  Result := RenderFileToImage(AFileName, AWidth, AHeight);
end;

class procedure TFloriaSVGRenderer.RenderElement(ACanvas: TFloriaCanvasAgg; ADoc: TSVGDocument; AElem: TSVGElement; const AMatrix: TSVGMatrix; Depth: Integer = 0);
var
  elemMatrix: TSVGMatrix;
  pushOpacity: Boolean;
  nestedSvg: TSVGSvgElement;
  nestedW, nestedH: Double;
begin
  if not Assigned(AElem) or (Depth > 32) then Exit;

  if (AElem.ComputedStyle.Display = sdNone) or
     (AElem.ComputedStyle.Visibility = svHidden) or
     (AElem.ComputedStyle.Visibility = svCollapse) then
    Exit;

  if AElem is TSVGDefsElement then
    Exit;

  pushOpacity := (AElem.ComputedStyle.Opacity < 0.9999);
  if pushOpacity then
    ACanvas.PushAlpha(AElem.ComputedStyle.Opacity);

  try
    if AElem is TSVGSvgElement then
    begin
      nestedSvg := TSVGSvgElement(AElem);
      if nestedSvg = ADoc.Root then
      begin
        RenderContainer(ACanvas, ADoc, nestedSvg, AMatrix, Depth + 1);
      end
      else
      begin
        nestedW := SVGLengthToPixels(nestedSvg.Width);
        nestedH := SVGLengthToPixels(nestedSvg.Height);
        nestedSvg.ComputeViewBox(nestedW, nestedH);
        elemMatrix := SVGMatrixMultiply(AMatrix, SVGMatrixTranslate(SVGLengthToPixels(nestedSvg.X), SVGLengthToPixels(nestedSvg.Y)));
        elemMatrix := SVGMatrixMultiply(elemMatrix, nestedSvg.ViewBoxTransform);
        elemMatrix := SVGMatrixMultiply(elemMatrix, nestedSvg.Transform);
        RenderContainer(ACanvas, ADoc, nestedSvg, elemMatrix, Depth + 1);
      end;
    end
    else if AElem is TSVGGroupElement then
    begin
      elemMatrix := SVGMatrixMultiply(AMatrix, AElem.Transform);
      RenderContainer(ACanvas, ADoc, TSVGContainerElement(AElem), elemMatrix, Depth + 1);
    end
    else if AElem is TSVGUseElement then
    begin
      RenderUse(ACanvas, ADoc, TSVGUseElement(AElem), AMatrix, Depth + 1);
    end
    else if AElem is TSVGShapeElement then
    begin
      elemMatrix := SVGMatrixMultiply(AMatrix, AElem.Transform);
      RenderShape(ACanvas, ADoc, TSVGShapeElement(AElem), elemMatrix);
    end
    else if AElem is TSVGContainerElement then
    begin
      elemMatrix := SVGMatrixMultiply(AMatrix, AElem.Transform);
      RenderContainer(ACanvas, ADoc, TSVGContainerElement(AElem), elemMatrix, Depth + 1);
    end;
  finally
    if pushOpacity then
      ACanvas.PopAlpha();
  end;
end;

class procedure TFloriaSVGRenderer.RenderContainer(ACanvas: TFloriaCanvasAgg; ADoc: TSVGDocument; ACont: TSVGContainerElement; const AMatrix: TSVGMatrix; Depth: Integer);
var
  i: Integer;
begin
  for i := 0 to ACont.ChildCount() - 1 do
    RenderElement(ACanvas, ADoc, ACont.GetChild(i), AMatrix, Depth);
end;

class procedure TFloriaSVGRenderer.RenderUse(ACanvas: TFloriaCanvasAgg; ADoc: TSVGDocument; AUse: TSVGUseElement; const AMatrix: TSVGMatrix; Depth: Integer);
var
  useMat: TSVGMatrix;
  offsetX, offsetY: Double;
  targetId: string;
  refElem: TSVGElement;
begin
  refElem := AUse.ReferencedElement;
  if not Assigned(refElem) and Assigned(ADoc) and (AUse.Href <> '') then
  begin
    targetId := AUse.Href;
    if (Length(targetId) > 0) and (targetId[1] = '#') then
      Delete(targetId, 1, 1);
    refElem := ADoc.FindElementById(targetId);
  end;

  if not Assigned(refElem) then Exit;

  offsetX := SVGLengthToPixels(AUse.X);
  offsetY := SVGLengthToPixels(AUse.Y);
  useMat := SVGMatrixMultiply(AMatrix, AUse.Transform);
  useMat := SVGMatrixMultiply(useMat, SVGMatrixTranslate(offsetX, offsetY));

  RenderElement(ACanvas, ADoc, refElem, useMat, Depth + 1);
end;

class procedure TFloriaSVGRenderer.RenderShape(ACanvas: TFloriaCanvasAgg; ADoc: TSVGDocument; AShape: TSVGShapeElement; const AMatrix: TSVGMatrix);
var
  pathData: TSVGPathData;
  pathStorage: path_storage;
  normSegs: TSVGNormalizedSegmentArray;
  seg: TSVGNormalizedSegment;
  pt, pt1, pt2: TSVGPoint;
  i: Integer;
  scaleX, scaleY, avgScale: Double;
  style, fillStyle, strokeStyle: TSVGStyleRecord;
  serverId: string;
  gradElem: TSVGElement;
  fillGrad, strokeGrad: TSVGGradientElement;
  localBBox: TSVGRect;
begin
  pathData := AShape.GetPath();
  if not Assigned(pathData) then Exit;

  normSegs := pathData.ToNormalized(True);
  if Length(normSegs) = 0 then Exit;

  pathStorage.Construct();
  try
    for i := 0 to High(normSegs) do
    begin
      seg := normSegs[i];
      case seg.Command of
        sncMoveTo:
        begin
          pt := SVGMatrixTransformPoint(AMatrix, SVGPoint(seg.Params[0], seg.Params[1]));
          pathStorage.move_to(pt.X, pt.Y);
        end;
        sncLineTo:
        begin
          pt := SVGMatrixTransformPoint(AMatrix, SVGPoint(seg.Params[0], seg.Params[1]));
          pathStorage.line_to(pt.X, pt.Y);
        end;
        sncCubicTo:
        begin
          pt1 := SVGMatrixTransformPoint(AMatrix, SVGPoint(seg.Params[0], seg.Params[1]));
          pt2 := SVGMatrixTransformPoint(AMatrix, SVGPoint(seg.Params[2], seg.Params[3]));
          pt := SVGMatrixTransformPoint(AMatrix, SVGPoint(seg.Params[4], seg.Params[5]));
          pathStorage.curve4(pt1.X, pt1.Y, pt2.X, pt2.Y, pt.X, pt.Y);
        end;
        sncQuadTo:
        begin
          pt1 := SVGMatrixTransformPoint(AMatrix, SVGPoint(seg.Params[0], seg.Params[1]));
          pt := SVGMatrixTransformPoint(AMatrix, SVGPoint(seg.Params[2], seg.Params[3]));
          pathStorage.curve3(pt1.X, pt1.Y, pt.X, pt.Y);
        end;
        sncClosePath:
        begin
          pathStorage.close_polygon();
        end;
      end;
    end;

    scaleX := Sqrt(AMatrix.A * AMatrix.A + AMatrix.B * AMatrix.B);
    scaleY := Sqrt(AMatrix.C * AMatrix.C + AMatrix.D * AMatrix.D);
    avgScale := (scaleX + scaleY) * 0.5;

    localBBox := AShape.GetLocalBoundingBox();
    style := AShape.ComputedStyle;
    fillGrad := nil;
    strokeGrad := nil;

    if (style.Fill.Kind = pkUri) and Assigned(ADoc) then
    begin
      serverId := style.Fill.UriId;
      if (Length(serverId) > 0) and (serverId[1] = '#') then
        Delete(serverId, 1, 1);
      gradElem := ADoc.FindElementById(serverId);
      if Assigned(gradElem) and (gradElem is TSVGGradientElement) then
        fillGrad := TSVGGradientElement(gradElem);
    end;

    if (style.Stroke.Kind = pkUri) and Assigned(ADoc) then
    begin
      serverId := style.Stroke.UriId;
      if (Length(serverId) > 0) and (serverId[1] = '#') then
        Delete(serverId, 1, 1);
      gradElem := ADoc.FindElementById(serverId);
      if Assigned(gradElem) and (gradElem is TSVGGradientElement) then
        strokeGrad := TSVGGradientElement(gradElem);
    end;

    // 1. Fill pass
    if Assigned(fillGrad) then
    begin
      ACanvas.RenderPathGradient(pathStorage, style, fillGrad, localBBox, AMatrix, False, avgScale);
    end
    else if (style.Fill.Kind <> pkNone) and (style.FillOpacity > 0.0) then
    begin
      fillStyle := style;
      fillStyle.Stroke.Kind := pkNone;
      ACanvas.RenderPath(pathStorage, fillStyle, avgScale);
    end;

    // 2. Stroke pass
    if Assigned(strokeGrad) and (style.StrokeWidth > 0.0) and (style.StrokeOpacity > 0.0) then
    begin
      ACanvas.RenderPathGradient(pathStorage, style, strokeGrad, localBBox, AMatrix, True, avgScale);
    end
    else if (style.Stroke.Kind <> pkNone) and (style.StrokeWidth > 0.0) and (style.StrokeOpacity > 0.0) then
    begin
      strokeStyle := style;
      strokeStyle.Fill.Kind := pkNone;
      ACanvas.RenderPath(pathStorage, strokeStyle, avgScale);
    end;
  finally
    pathStorage.Destruct();
  end;
end;

end.
