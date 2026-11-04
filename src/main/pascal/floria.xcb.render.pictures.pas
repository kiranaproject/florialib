{ Unit Floria.XCB.Render.Pictures — scaled compositing and pixmap readback.

  The generated Floria.XCB.Render unit covers queries and structs, but the generator
  skipped every request whose return type is xcb_void_cookie_t, because that type lives
  in a header its filter dropped. That is most of the drawing requests: create picture,
  composite, fill, set transform, set filter. They are declared here by hand instead of
  editing generated code, which the bindgen README forbids.

  On top of the bindings this unit provides the two operations a scaled window preview
  needs, which are otherwise easy to get subtly wrong:

    XcbRenderCompositeScaled   scales one pixmap into a rectangle of another
    XcbRenderPixmapToImage     reads a pixmap back as a TFloriaImage, once

  See shellsama/docs/window-previews.md for why the scale happens on the server and the
  readback happens once. }

unit Floria.XCB.Render.Pictures;

{$mode objfpc}{$H+}

interface

uses
  Floria.XCB,
  Floria.XCB.Render,
  Floria.Image.Core;

const
  // 16.16 fixed point, the format Render uses for transforms.
  XCB_RENDER_FIXED_ONE = 65536;

// Bindings the generator skipped. Named with the Xcb prefix rather than the C
// underscore names, so they cannot collide if the generator learns to emit them.
function XcbRenderCreatePicture(AConn: Pxcb_connection_t;
  APicture: xcb_render_picture_t; ADrawable: xcb_drawable_t;
  AFormat: xcb_render_pictformat_t; AValueMask: Cardinal;
  AValueList: Pointer): xcb_void_cookie_t; cdecl;
  external 'xcb-render' name 'xcb_render_create_picture';

function XcbRenderFreePicture(AConn: Pxcb_connection_t;
  APicture: xcb_render_picture_t): xcb_void_cookie_t; cdecl;
  external 'xcb-render' name 'xcb_render_free_picture';

function XcbRenderComposite(AConn: Pxcb_connection_t; AOp: Byte;
  ASrc, AMask, ADst: xcb_render_picture_t;
  ASrcX, ASrcY, AMaskX, AMaskY, ADstX, ADstY: SmallInt;
  AWidth, AHeight: Word): xcb_void_cookie_t; cdecl;
  external 'xcb-render' name 'xcb_render_composite';

function XcbRenderSetPictureFilter(AConn: Pxcb_connection_t;
  APicture: xcb_render_picture_t; AFilterLen: Word; AFilter: PChar;
  AValueMask: Cardinal; AValueList: Pointer): xcb_void_cookie_t; cdecl;
  external 'xcb-render' name 'xcb_render_set_picture_filter';

function XcbRenderSetPictureTransform(AConn: Pxcb_connection_t;
  APicture: xcb_render_picture_t;
  const ATransform: xcb_render_transform_t): xcb_void_cookie_t; cdecl;
  external 'xcb-render' name 'xcb_render_set_picture_transform';

function XcbRenderFillRectangles(AConn: Pxcb_connection_t; AOp: Byte;
  ADestination: xcb_render_picture_t; const AColor: xcb_render_color_t;
  ARectsLen: Word; ARects: Pxcb_rectangle_t): xcb_void_cookie_t; cdecl;
  external 'xcb-render' name 'xcb_render_fill_rectangles';

  { The picture format the server uses for drawables of ADepth, or 0 when there is none.
    Cached per connection: the query is a round-trip and a preview grid asks once per
    window. }
  function XcbRenderPictFormatForDepth(AConn: Pxcb_connection_t;
    ADepth: Byte): xcb_render_pictformat_t;

  { Fills a rectangle of a picture with a solid colour. Components are 0..1. }
  procedure XcbRenderFill(AConn: Pxcb_connection_t;
    ADestination: xcb_render_picture_t; AR, AG, AB, AA: Double;
    AX, AY, AWidth, AHeight: Integer);

  { Composites ASrcPixmap into ADstPixmap, scaled to fit the destination rectangle.

    Both pixmaps need a picture format: ASrcDepth is the depth of the source drawable,
    ADstFormat is the format of the destination picture. AOp is one of the
    XCB_RENDER_PICT_OP_* constants; PICT_OP_OVER is the right choice for window content
    because a 32-bit client's transparent pixels carry arbitrary RGB and OVER against a
    filled destination hides that, while SRC would composite the noise.

    Returns False when either format cannot be resolved, without touching the server. }
  function XcbRenderCompositeScaled(AConn: Pxcb_connection_t;
    ASrcPixmap: xcb_pixmap_t; ASrcDepth: Byte;
    ASrcWidth, ASrcHeight: Integer;
    ADstPixmap: xcb_pixmap_t; ADstFormat: xcb_render_pictformat_t;
    ADstX, ADstY, ADstWidth, ADstHeight: Integer;
    AOp: Byte = XCB_RENDER_PICT_OP_OVER): Boolean;

  { Reads a pixmap back as a TFloriaImage. One server round-trip; do not call this per
    window per refresh. Returns nil on failure. The caller owns the image. }
  function XcbRenderPixmapToImage(AConn: Pxcb_connection_t;
    APixmap: xcb_pixmap_t; AWidth, AHeight: Integer;
    AHasAlpha: Boolean): TFloriaImage;

implementation

uses
  SysUtils, Math;

// XCB allocates reply buffers with malloc, so FreeMem would corrupt the heap.
procedure XcbFreeReply(P: Pointer); cdecl; external 'c' name 'free';

const
  FORMAT_CACHE_DEPTHS = 33;   // depths 0..32, which is every visual depth X allows

var
  GCachedConnection: Pxcb_connection_t = nil;
  GCachedFormat: array[0..FORMAT_CACHE_DEPTHS - 1] of xcb_render_pictformat_t;
  GCachedKnown: array[0..FORMAT_CACHE_DEPTHS - 1] of Boolean;

procedure ResetFormatCache(AConn: Pxcb_connection_t);
begin
  if GCachedConnection = AConn then Exit;
  GCachedConnection := AConn;
  FillChar(GCachedKnown, SizeOf(GCachedKnown), 0);
  FillChar(GCachedFormat, SizeOf(GCachedFormat), 0);
end;

function XcbRenderPictFormatForDepth(AConn: Pxcb_connection_t;
  ADepth: Byte): xcb_render_pictformat_t;
var
  cookie: xcb_render_query_pict_formats_cookie_t;
  reply: Pxcb_render_query_pict_formats_reply_t;
  infos: Pxcb_render_pictforminfo_t;
  count, i: Integer;
begin
  Result := 0;
  if AConn = nil then Exit;

  ResetFormatCache(AConn);
  if ADepth >= FORMAT_CACHE_DEPTHS then
  begin
    // Out of the cache's range; answer without caching rather than grow it for a depth
    // no visual uses.
    GCachedKnown[0] := GCachedKnown[0];
  end
  else if GCachedKnown[ADepth] then
    Exit(GCachedFormat[ADepth]);

  cookie := xcb_render_query_pict_formats(AConn);
  reply := xcb_render_query_pict_formats_reply(AConn, cookie, nil);
  if reply = nil then Exit;
  try
    infos := xcb_render_query_pict_formats_formats(reply);
    count := xcb_render_query_pict_formats_formats_length(reply);
    for i := 0 to count - 1 do
    begin
      if (infos[i].depth = ADepth) and
         (infos[i].type_ = XCB_RENDER_PICT_TYPE_DIRECT) then
      begin
        Result := infos[i].id;
        Break;
      end;
    end;
  finally
    XcbFreeReply(reply);
  end;

  if ADepth < FORMAT_CACHE_DEPTHS then
  begin
    GCachedFormat[ADepth] := Result;
    GCachedKnown[ADepth] := True;
  end;
end;

procedure XcbRenderFill(AConn: Pxcb_connection_t;
  ADestination: xcb_render_picture_t; AR, AG, AB, AA: Double;
  AX, AY, AWidth, AHeight: Integer);
var
  color: xcb_render_color_t;
  rect: xcb_rectangle_t;
begin
  if (AConn = nil) or (ADestination = 0) or (AWidth <= 0) or (AHeight <= 0) then Exit;

  color.red := Round(EnsureRange(AR, 0.0, 1.0) * 65535);
  color.green := Round(EnsureRange(AG, 0.0, 1.0) * 65535);
  color.blue := Round(EnsureRange(AB, 0.0, 1.0) * 65535);
  color.alpha := Round(EnsureRange(AA, 0.0, 1.0) * 65535);

  rect.x := AX;
  rect.y := AY;
  rect.width := AWidth;
  rect.height := AHeight;

  XcbRenderFillRectangles(AConn, XCB_RENDER_PICT_OP_SRC, ADestination, color, 1, @rect);
end;

function XcbRenderCompositeScaled(AConn: Pxcb_connection_t;
  ASrcPixmap: xcb_pixmap_t; ASrcDepth: Byte;
  ASrcWidth, ASrcHeight: Integer;
  ADstPixmap: xcb_pixmap_t; ADstFormat: xcb_render_pictformat_t;
  ADstX, ADstY, ADstWidth, ADstHeight: Integer;
  AOp: Byte): Boolean;
var
  srcFormat: xcb_render_pictformat_t;
  srcPicture, dstPicture: xcb_render_picture_t;
  transform: xcb_render_transform_t;
  filterName: PChar;
  repeatMode: Cardinal;
begin
  Result := False;
  if (AConn = nil) or (ASrcPixmap = 0) or (ADstPixmap = 0) then Exit;
  if (ASrcWidth <= 0) or (ASrcHeight <= 0) then Exit;
  if (ADstWidth <= 0) or (ADstHeight <= 0) then Exit;

  srcFormat := XcbRenderPictFormatForDepth(AConn, ASrcDepth);
  if (srcFormat = 0) or (ADstFormat = 0) then Exit;

  // Repeat is set here rather than with a separate request: this libxcb-render does not
  // export xcb_render_set_picture_repeat. PAD is what stops edge pixels from sampling
  // outside the source and leaving a dark fringe around every preview.
  repeatMode := XCB_RENDER_REPEAT_PAD;
  srcPicture := xcb_generate_id(AConn);
  dstPicture := xcb_generate_id(AConn);
  XcbRenderCreatePicture(AConn, srcPicture, ASrcPixmap, srcFormat,
                         XCB_RENDER_CP_REPEAT, @repeatMode);
  XcbRenderCreatePicture(AConn, dstPicture, ADstPixmap, ADstFormat, 0, nil);

  try
    // 'good' is the driver's best available filter. For a downscale that averages,
    // which is what keeps text from turning into noise at preview size.
    filterName := 'good';
    XcbRenderSetPictureFilter(AConn, srcPicture, 4, filterName, 0, nil);

    // Composite does not scale on its own: it copies a ADstWidth x ADstHeight window of
    // the source at 1:1, which crops instead of shrinking. The transform is what makes
    // destination pixel (x, y) sample the source at (x * srcW / dstW, y * srcH / dstH).
    FillChar(transform, SizeOf(transform), 0);
    transform.matrix11 := Round((ASrcWidth / ADstWidth) * XCB_RENDER_FIXED_ONE);
    transform.matrix22 := Round((ASrcHeight / ADstHeight) * XCB_RENDER_FIXED_ONE);
    transform.matrix33 := XCB_RENDER_FIXED_ONE;
    XcbRenderSetPictureTransform(AConn, srcPicture, transform);

    XcbRenderComposite(AConn, AOp, srcPicture, XCB_NONE, dstPicture,
                       0, 0, 0, 0, ADstX, ADstY, ADstWidth, ADstHeight);
    Result := True;
  finally
    XcbRenderFreePicture(AConn, srcPicture);
    XcbRenderFreePicture(AConn, dstPicture);
  end;
end;

function XcbRenderPixmapToImage(AConn: Pxcb_connection_t;
  APixmap: xcb_pixmap_t; AWidth, AHeight: Integer;
  AHasAlpha: Boolean): TFloriaImage;
var
  cookie: xcb_get_image_cookie_t;
  reply: Pxcb_get_image_reply_t;
  rawBytes: PByte;
  x, y, rowBytes: Integer;
  srcRow, dstRow: PByte;
begin
  Result := nil;
  if (AConn = nil) or (APixmap = 0) then Exit;
  if (AWidth <= 0) or (AHeight <= 0) then Exit;

  cookie := xcb_get_image(AConn, XCB_IMAGE_FORMAT_Z_PIXMAP, APixmap,
                          0, 0, AWidth, AHeight, Cardinal($FFFFFFFF));
  reply := xcb_get_image_reply(AConn, cookie, nil);
  if reply = nil then Exit;

  try
    rawBytes := xcb_get_image_data(reply);
    if rawBytes = nil then Exit;

    Result := TFloriaImage.Create(AWidth, AHeight);
    Result.IsPremultiplied := AHasAlpha;

    rowBytes := AWidth * 4;
    for y := 0 to AHeight - 1 do
    begin
      srcRow := rawBytes + (y * rowBytes);
      dstRow := PByte(Result.Scanline[y]);
      if AHasAlpha then
        Move(srcRow^, dstRow^, rowBytes)
      else
        // A 24-bit drawable returns four bytes per pixel whose unused byte is meant to
        // be ignored. Forcing it to opaque is defensive: this server already returns
        // 255 there, so the line is not observable in the tests, but a server that
        // returned 0 would make every preview fully transparent.
        for x := 0 to AWidth - 1 do
          PDWord(dstRow + (x * 4))^ := PDWord(srcRow + (x * 4))^ or Cardinal($FF000000);
    end;
  finally
    XcbFreeReply(reply);
  end;
end;

initialization
  GCachedConnection := nil;
  FillChar(GCachedKnown, SizeOf(GCachedKnown), 0);

end.
