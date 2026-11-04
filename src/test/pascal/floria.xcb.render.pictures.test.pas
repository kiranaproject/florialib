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
    procedure TestUnknownDepthHasNoFormat();
    procedure TestScaleHalvesAQuadrantPattern();
    procedure TestOverKeepsTheDestinationUnderTransparentSource();
    procedure TestUnscaledCompositeIsTheIdentity();
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
        XcbRenderCompositeScaled(FConn, src, FDepth, 4, 4, dst, dstFormat,
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
        XcbRenderCompositeScaled(FConn, src, 32, 2, 2, dst, dstFormat, 0, 0, 2, 2));
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
        XcbRenderCompositeScaled(FConn, src, 32, 2, 2, dst, dstFormat,
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
        XcbRenderCompositeScaled(FConn, src, FDepth, 2, 2, dst, dstFormat,
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

initialization
  RegisterTest(TXCBRenderPicturesTest);

end.
