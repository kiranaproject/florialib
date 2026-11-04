unit Floria.XCB.Render.Pictures.Test;

// Tests for Floria.XCB.Render.Pictures.
//
// These run against the real X server, because the thing under test is a server-side
// operation: scaling happens in the server's composite, not in Pascal. A test that did
// not talk to a server would only prove that the arguments were assembled.
//
// The scaling test is designed so a wrong implementation fails in a specific way:
// a 4x4 source of four solid 2x2 quadrants scaled into 2x2 must produce those four
// colours. A composite that crops instead of scaling produces four red pixels, because
// the top-left 2x2 window of the source is entirely red.

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry,
  Floria.XCB,
  Floria.XCB.Render,
  Floria.XCB.Render.Pictures,
  Floria.Image.Core;

type
  TXCBRenderPicturesTest = class(TTestCase)
  private
    FConn: Pxcb_connection_t;
    FRoot: xcb_drawable_t;
    FDepth: Byte;
    function Connect(): Boolean;
    function NewPixmap(AWidth, AHeight: Integer): xcb_pixmap_t;
    function PictureFor(APixmap: xcb_pixmap_t; ADepth: Byte): xcb_render_picture_t;
  published
    procedure TestPictFormatForDepth();
    procedure TestPictFormatForVisual();
    procedure TestUnknownDepthHasNoFormat();
    procedure TestScaleHalvesAQuadrantPattern();
    procedure TestOverKeepsTheDestinationUnderTransparentSource();
    procedure TestUnscaledCompositeIsTheIdentity();
    procedure TestDemultiply();
    procedure TestReadPixmapReturnsRawBgra();
  end;

implementation

function TXCBRenderPicturesTest.Connect(): Boolean;
var
  screenNum: Integer;
  iter: xcb_screen_iterator_t;
begin
  Result := False;
  screenNum := 0;
  FConn := xcb_connect(nil, @screenNum);
  if FConn = nil then Exit;
  if xcb_connection_has_error(FConn) <> 0 then Exit;

  iter := xcb_setup_roots_iterator(xcb_get_setup(FConn));
  if iter.data = nil then Exit;
  FRoot := iter.data^.root;
  FDepth := iter.data^.root_depth;
  Result := True;
end;

function TXCBRenderPicturesTest.NewPixmap(AWidth, AHeight: Integer): xcb_pixmap_t;
begin
  Result := xcb_generate_id(FConn);
  xcb_create_pixmap(FConn, FDepth, Result, FRoot, AWidth, AHeight);
end;

function TXCBRenderPicturesTest.PictureFor(APixmap: xcb_pixmap_t;
  ADepth: Byte): xcb_render_picture_t;
var
  format: xcb_render_pictformat_t;
begin
  Result := 0;
  format := XcbRenderPictFormatForDepth(FConn, ADepth);
  if format = 0 then Exit;
  Result := xcb_generate_id(FConn);
  XcbRenderCreatePicture(FConn, Result, APixmap, format, 0, nil);
end;

procedure TXCBRenderPicturesTest.TestPictFormatForDepth();
var
  format24, format32: xcb_render_pictformat_t;
begin
  if not Connect() then Exit;
  try
    format24 := XcbRenderPictFormatForDepth(FConn, 24);
    AssertTrue('depth 24 has a picture format', format24 <> 0);

    format32 := XcbRenderPictFormatForDepth(FConn, 32);
    AssertTrue('depth 32 has a picture format', format32 <> 0);

    AssertTrue('the two depths do not share a format', format24 <> format32);

    // The cache must return the same answer the query did, not a re-query that drifts.
    AssertEquals('the cache is stable', format24, XcbRenderPictFormatForDepth(FConn, 24));
  finally
    xcb_disconnect(FConn);
  end;
end;

procedure TXCBRenderPicturesTest.TestPictFormatForVisual();
var
  iter: xcb_screen_iterator_t;
  visual: xcb_visualid_t;
  byVisual, byDepth: xcb_render_pictformat_t;
begin
  if not Connect() then Exit;
  try
    iter := xcb_setup_roots_iterator(xcb_get_setup(FConn));
    if iter.data = nil then Exit;
    visual := iter.data^.root_visual;

    byVisual := XcbRenderPictFormatForVisual(FConn, visual);
    AssertTrue('the root visual has a format', byVisual <> 0);

    // For the root visual the two lookups must agree. If they ever disagree, depth alone
    // is picking a format with a different channel layout, which would swap red and blue
    // in every preview.
    byDepth := XcbRenderPictFormatForDepth(FConn, FDepth);
    AssertEquals('the visual and depth lookups agree for the root visual',
                 byDepth, byVisual);

    AssertEquals('the cache is stable', byVisual,
                 XcbRenderPictFormatForVisual(FConn, visual));
    AssertEquals('an unknown visual resolves to nothing', 0,
                 XcbRenderPictFormatForVisual(FConn, $7FFFFFF0));
  finally
    xcb_disconnect(FConn);
  end;
end;

procedure TXCBRenderPicturesTest.TestUnknownDepthHasNoFormat();
begin
  if not Connect() then Exit;
  try
    // No X visual uses depth 7, so the server lists no direct format for it.
    AssertEquals('an unused depth resolves to nothing', 0,
                 XcbRenderPictFormatForDepth(FConn, 7));
  finally
    xcb_disconnect(FConn);
  end;
end;

procedure TXCBRenderPicturesTest.TestScaleHalvesAQuadrantPattern();
const
  RED: TBgraPixel = (B: 0; G: 0; R: 255; A: 255);
  GREEN: TBgraPixel = (B: 0; G: 255; R: 0; A: 255);
  BLUE: TBgraPixel = (B: 255; G: 0; R: 0; A: 255);
  WHITE: TBgraPixel = (B: 255; G: 255; R: 255; A: 255);
var
  src, dst: xcb_pixmap_t;
  srcPic, dstPic: xcb_render_picture_t;
  dstFormat: xcb_render_pictformat_t;
  image: TFloriaImage;
  pixel: TBgraPixel;

  procedure CheckPixel(AX, AY: Integer; const AExpected: TBgraPixel; const ALabel: string);
  begin
    pixel := image.Pixels[AX, AY];
    AssertEquals(ALabel + ' red', AExpected.R, pixel.R);
    AssertEquals(ALabel + ' green', AExpected.G, pixel.G);
    AssertEquals(ALabel + ' blue', AExpected.B, pixel.B);
  end;

begin
  if not Connect() then Exit;
  try
    src := NewPixmap(4, 4);
    dst := NewPixmap(2, 2);
    try
      // Four solid 2x2 quadrants, so each 2x2 region averages to exactly one colour.
      srcPic := PictureFor(src, FDepth);
      try
        XcbRenderFill(FConn, srcPic, 1, 0, 0, 1, 0, 0, 2, 2);   // red
        XcbRenderFill(FConn, srcPic, 0, 1, 0, 1, 2, 0, 2, 2);   // green
        XcbRenderFill(FConn, srcPic, 0, 0, 1, 1, 0, 2, 2, 2);   // blue
        XcbRenderFill(FConn, srcPic, 1, 1, 1, 1, 2, 2, 2, 2);   // white
      finally
        XcbRenderFreePicture(FConn, srcPic);
      end;

      // Black underneath, so a composite that writes nothing is visible as black rather
      // than passing by accident.
      dstFormat := XcbRenderPictFormatForDepth(FConn, FDepth);
      dstPic := PictureFor(dst, FDepth);
      try
        XcbRenderFill(FConn, dstPic, 0, 0, 0, 1, 0, 0, 2, 2);
      finally
        XcbRenderFreePicture(FConn, dstPic);
      end;

      AssertTrue('the scaled composite succeeded',
        XcbRenderCompositeScaled(FConn, src, XcbRenderPictFormatForDepth(FConn, FDepth), 4, 4, dst, dstFormat,
                                 0, 0, 2, 2, XCB_RENDER_PICT_OP_OVER));
      xcb_flush(FConn);

      image := XcbRenderPixmapToImage(FConn, dst, 2, 2, False);
      try
        AssertNotNull('the destination read back', image);
        // A crop instead of a scale would give four red pixels here.
        CheckPixel(0, 0, RED, 'top left');
        CheckPixel(1, 0, GREEN, 'top right');
        CheckPixel(0, 1, BLUE, 'bottom left');
        CheckPixel(1, 1, WHITE, 'bottom right');
      finally
        image.Free();
      end;
    finally
      xcb_free_pixmap(FConn, src);
      xcb_free_pixmap(FConn, dst);
    end;
  finally
    xcb_disconnect(FConn);
  end;
end;

procedure TXCBRenderPicturesTest.TestOverKeepsTheDestinationUnderTransparentSource();
// A 32-bit client's pixmap is premultiplied, so a half-transparent red pixel is stored
// as (0.5, 0, 0, 0.5) and a fully transparent one as (0, 0, 0, 0). Composited OVER a
// blue destination, half red must land on half blue. With SRC the destination is
// replaced outright, which is why the pipeline must not use SRC.
//
// Filling with (1, 0, 0, 0) instead would be invalid premultiplied data, and the server
// composites it as pure red with no coverage: the destination comes out magenta. That
// is worth knowing, because it is exactly the artefact a non-premultiplied source
// produces.
var
  src, dst: xcb_pixmap_t;
  srcPic, dstPic: xcb_render_picture_t;
  dstFormat: xcb_render_pictformat_t;
  image: TFloriaImage;
  pixel: TBgraPixel;

  procedure FillBlue();
  begin
    dstPic := PictureFor(dst, FDepth);
    try
      XcbRenderFill(FConn, dstPic, 0, 0, 1, 1, 0, 0, 2, 2);
    finally
      XcbRenderFreePicture(FConn, dstPic);
    end;
  end;

begin
  if not Connect() then Exit;
  try
    src := xcb_generate_id(FConn);
    xcb_create_pixmap(FConn, 32, src, FRoot, 2, 2);
    dst := NewPixmap(2, 2);
    try
      srcPic := PictureFor(src, 32);
      try
        // Premultiplied 50% red.
        XcbRenderFill(FConn, srcPic, 0.5, 0, 0, 0.5, 0, 0, 2, 2);
      finally
        XcbRenderFreePicture(FConn, srcPic);
      end;

      dstFormat := XcbRenderPictFormatForDepth(FConn, FDepth);

      FillBlue();
      // No operator argument: the default must be OVER.
      AssertTrue('the OVER composite succeeded',
        XcbRenderCompositeScaled(FConn, src, XcbRenderPictFormatForDepth(FConn, 32), 2, 2, dst, dstFormat, 0, 0, 2, 2));
      xcb_flush(FConn);

      image := XcbRenderPixmapToImage(FConn, dst, 2, 2, False);
      try
        AssertNotNull('the destination read back', image);
        pixel := image.Pixels[1, 1];
        AssertTrue('OVER kept the blue underneath: got R=' + IntToStr(pixel.R) +
                   ' B=' + IntToStr(pixel.B),
                   (pixel.B > 90) and (pixel.R > 90));
      finally
        image.Free();
      end;

      // SRC must lose the blue, which is the behaviour the pipeline must avoid.
      FillBlue();
      AssertTrue('the SRC composite succeeded',
        XcbRenderCompositeScaled(FConn, src, XcbRenderPictFormatForDepth(FConn, 32), 2, 2, dst, dstFormat,
                                 0, 0, 2, 2, XCB_RENDER_PICT_OP_SRC));
      xcb_flush(FConn);

      image := XcbRenderPixmapToImage(FConn, dst, 2, 2, False);
      try
        AssertNotNull('the destination read back', image);
        pixel := image.Pixels[1, 1];
        AssertTrue('SRC replaced the destination instead: got B=' + IntToStr(pixel.B),
                   pixel.B < 30);
      finally
        image.Free();
      end;
    finally
      xcb_free_pixmap(FConn, src);
      xcb_free_pixmap(FConn, dst);
    end;
  finally
    xcb_disconnect(FConn);
  end;
end;

procedure TXCBRenderPicturesTest.TestUnscaledCompositeIsTheIdentity();
var
  src, dst: xcb_pixmap_t;
  srcPic, dstPic: xcb_render_picture_t;
  dstFormat: xcb_render_pictformat_t;
  image: TFloriaImage;
  pixel: TBgraPixel;
begin
  if not Connect() then Exit;
  try
    // Same size in and out: the transform must be the identity, so the result is a copy.
    // This catches a transform that is off by the fixed-point scale.
    src := NewPixmap(2, 2);
    dst := NewPixmap(2, 2);
    try
      srcPic := PictureFor(src, FDepth);
      try
        XcbRenderFill(FConn, srcPic, 0, 1, 0, 1, 0, 0, 2, 2);   // green
      finally
        XcbRenderFreePicture(FConn, srcPic);
      end;

      dstFormat := XcbRenderPictFormatForDepth(FConn, FDepth);
      dstPic := PictureFor(dst, FDepth);
      try
        XcbRenderFill(FConn, dstPic, 0, 0, 0, 1, 0, 0, 2, 2);
      finally
        XcbRenderFreePicture(FConn, dstPic);
      end;

      AssertTrue('the 1:1 composite succeeded',
        XcbRenderCompositeScaled(FConn, src, XcbRenderPictFormatForDepth(FConn, FDepth), 2, 2, dst, dstFormat,
                                 0, 0, 2, 2, XCB_RENDER_PICT_OP_OVER));
      xcb_flush(FConn);

      image := XcbRenderPixmapToImage(FConn, dst, 2, 2, False);
      try
        AssertNotNull('the destination read back', image);
        pixel := image.Pixels[1, 1];
        AssertEquals('green survived', 255, pixel.G);
        AssertEquals('red did not appear', 0, pixel.R);
        AssertEquals('blue did not appear', 0, pixel.B);
      finally
        image.Free();
      end;
    finally
      xcb_free_pixmap(FConn, src);
      xcb_free_pixmap(FConn, dst);
    end;
  finally
    xcb_disconnect(FConn);
  end;
end;

procedure TXCBRenderPicturesTest.TestDemultiply();
var
  px: array[0..3] of TBgraPixel;
begin
  // Premultiplied 50% red is (0, 0, 128, 128); straight is (0, 0, 255, 128).
  px[0].B := 0; px[0].G := 0; px[0].R := 128; px[0].A := 128;
  // Opaque is untouched.
  px[1].B := 10; px[1].G := 20; px[1].R := 30; px[1].A := 255;
  // Fully transparent has no colour to recover.
  px[2].B := 0; px[2].G := 0; px[2].R := 0; px[2].A := 0;
  // Quarter alpha: premultiplied 64 becomes 255 when straightened.
  px[3].B := 0; px[3].G := 0; px[3].R := 64; px[3].A := 64;

  XcbDemultiplyBgra(@px[0], 4, 1);

  AssertEquals('half alpha red recovers fully', 255, px[0].R);
  AssertEquals('and alpha is left alone', 128, px[0].A);
  AssertEquals('opaque red is untouched', 30, px[1].R);
  AssertEquals('transparent stays black', 0, px[2].R);
  AssertEquals('quarter alpha recovers fully', 255, px[3].R);
end;

procedure TXCBRenderPicturesTest.TestReadPixmapReturnsRawBgra();
var
  pm: xcb_pixmap_t;
  pic: xcb_render_picture_t;
  buf: array of Byte;
  ok: Boolean;
begin
  if not Connect() then Exit;
  try
    pm := NewPixmap(4, 4);
    try
      pic := PictureFor(pm, FDepth);
      try
        XcbRenderFill(FConn, pic, 1, 0, 0, 1, 0, 0, 4, 4);
      finally
        XcbRenderFreePicture(FConn, pic);
      end;
      xcb_flush(FConn);

      SetLength(buf, 4 * 4 * 4);
      ok := XcbRenderReadPixmap(FConn, pm, 4, 4, @buf[0], Length(buf));
      AssertTrue('the read succeeded', ok);
      AssertEquals('red channel', 255, buf[2]);
      AssertEquals('green channel', 0, buf[1]);
      AssertEquals('blue channel', 0, buf[0]);

      // A buffer that is too small must be refused rather than overrun.
      AssertFalse('a short buffer is refused',
        XcbRenderReadPixmap(FConn, pm, 4, 4, @buf[0], Length(buf) - 1));
    finally
      xcb_free_pixmap(FConn, pm);
    end;
  finally
    xcb_disconnect(FConn);
  end;
end;

initialization
  RegisterTest(TXCBRenderPicturesTest);

end.
