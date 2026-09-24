unit Floria.XCB.Test;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry,
  Floria.XCB,
  Floria.XCB.ICCCM,
  Floria.XCB.EWMH,
  Floria.XCB.Keysyms,
  Floria.XCB.Cursor,
  Floria.XCB.Render,
  Floria.XCB.RandR,
  Floria.XCB.SHM,
  Floria.XCB.Shape,
  Floria.XCB.XFixes,
  Floria.X11.KeySym;

procedure libc_free(p: Pointer); cdecl; external 'c' name 'free';

type
  TXCBTest = class(TTestCase)
  published
    procedure TestConstants();
    procedure TestKeySymConstants();
    procedure TestParseDisplay();
    procedure TestConnectAndDisconnect();
    procedure TestICCCMSizeHints();
    procedure TestEWMHInitAndWipe();
    procedure TestKeysymsAllocAndFree();
    procedure TestCursorContext();
    procedure TestExtensionsQuery();
  end;

implementation

procedure TXCBTest.TestConstants();
begin
  AssertEquals('X_PROTOCOL version', 11, X_PROTOCOL);
  AssertEquals('X_PROTOCOL_REVISION', 0, X_PROTOCOL_REVISION);
  AssertEquals('X_TCP_PORT', 6000, X_TCP_PORT);
  AssertEquals('XCB_CONN_ERROR', 1, XCB_CONN_ERROR);
  AssertEquals('XCB_NONE', 0, XCB_NONE);
  AssertEquals('XCB_COPY_FROM_PARENT', 0, XCB_COPY_FROM_PARENT);
end;

procedure TXCBTest.TestKeySymConstants();
begin
  AssertEquals('XK_BackSpace', $FF08, XK_BackSpace);
  AssertEquals('XK_Tab', $FF09, XK_Tab);
  AssertEquals('XK_Return', $FF0D, XK_Return);
  AssertEquals('XK_Escape', $FF1B, XK_Escape);
  AssertEquals('XK_space', $0020, XK_space);
  AssertEquals('XK_F1', $FFBE, XK_F1);
  AssertEquals('XK_F12', $FFC9, XK_F12);
  AssertEquals('XK_Shift_L', $FFE1, XK_Shift_L);
  AssertEquals('XK_Control_L', $FFE3, XK_Control_L);
end;

procedure TXCBTest.TestParseDisplay();
var
  Host: PChar;
  Disp: Integer;
  Screen: Integer;
  Res: Integer;
begin
  Host := nil;
  Disp := -1;
  Screen := -1;
  Res := xcb_parse_display(':0.0', @Host, @Disp, @Screen);
  AssertEquals('Parse success', 1, Res);
  AssertEquals('Display number', 0, Disp);
  AssertEquals('Screen number', 0, Screen);
end;

procedure TXCBTest.TestConnectAndDisconnect();
var
  Conn: Pxcb_connection_t;
  ScreenNum: Integer;
  Fd: Integer;
  Id: Cardinal;
begin
  ScreenNum := 0;
  Conn := xcb_connect(nil, @ScreenNum);
  AssertNotNull('Connection handle should not be nil', Conn);
  try
    if xcb_connection_has_error(Conn) = 0 then
    begin
      Fd := xcb_get_file_descriptor(Conn);
      AssertTrue('File descriptor should be valid', Fd >= 0);

      Id := xcb_generate_id(Conn);
      AssertTrue('Generated XID should be non-zero', Id > 0);

      AssertTrue('Flush should return positive status', xcb_flush(Conn) >= 0);
    end;
  finally
    xcb_disconnect(Conn);
  end;
end;

procedure TXCBTest.TestICCCMSizeHints();
var
  Hints: xcb_size_hints_t;
begin
  FillChar(Hints, SizeOf(Hints), 0);
  xcb_icccm_size_hints_set_min_size(@Hints, 100, 200);
  xcb_icccm_size_hints_set_max_size(@Hints, 800, 600);
  AssertEquals('Min width', 100, Hints.min_width);
  AssertEquals('Min height', 200, Hints.min_height);
  AssertEquals('Max width', 800, Hints.max_width);
  AssertEquals('Max height', 600, Hints.max_height);
end;

procedure TXCBTest.TestEWMHInitAndWipe();
var
  Conn: Pxcb_connection_t;
  ScreenNum: Integer;
  EWMH: xcb_ewmh_connection_t;
  Cookie: Pxcb_intern_atom_cookie_t;
begin
  ScreenNum := 0;
  Conn := xcb_connect(nil, @ScreenNum);
  if Conn = nil then Exit;
  try
    if xcb_connection_has_error(Conn) = 0 then
    begin
      Cookie := xcb_ewmh_init_atoms(Conn, @EWMH);
      AssertNotNull('EWMH cookies returned', Cookie);
      if xcb_ewmh_init_atoms_replies(@EWMH, Cookie, nil) = 1 then
      begin
        AssertTrue('EWMH _NET_SUPPORTED atom populated', EWMH._NET_SUPPORTED <> 0);
        libc_free(EWMH.screens);
        libc_free(EWMH._NET_WM_CM_Sn);
      end;
    end;
  finally
    xcb_disconnect(Conn);
  end;
end;

procedure TXCBTest.TestKeysymsAllocAndFree();
var
  Conn: Pxcb_connection_t;
  ScreenNum: Integer;
  Syms: Pxcb_key_symbols_t;
begin
  ScreenNum := 0;
  Conn := xcb_connect(nil, @ScreenNum);
  if Conn = nil then Exit;
  try
    if xcb_connection_has_error(Conn) = 0 then
    begin
      Syms := xcb_key_symbols_alloc(Conn);
      AssertNotNull('Key symbols allocated', Syms);
      xcb_key_symbols_free(Syms);
    end;
  finally
    xcb_disconnect(Conn);
  end;
end;

procedure TXCBTest.TestCursorContext();
var
  Conn: Pxcb_connection_t;
  ScreenNum: Integer;
  LSetup: Pxcb_setup_t;
  ScreenIter: xcb_screen_iterator_t;
  Ctx: Pxcb_cursor_context_t;
  Res: Integer;
begin
  ScreenNum := 0;
  Conn := xcb_connect(nil, @ScreenNum);
  if Conn = nil then Exit;
  try
    if xcb_connection_has_error(Conn) = 0 then
    begin
      LSetup := xcb_get_setup(Conn);
      AssertNotNull('Setup should not be nil', LSetup);
      ScreenIter := xcb_setup_roots_iterator(LSetup);
      Ctx := nil;
      Res := xcb_cursor_context_new(Conn, ScreenIter.data, @Ctx);
      if Res = 0 then
      begin
        AssertNotNull('Cursor context created', Ctx);
        xcb_cursor_context_free(Ctx);
      end;
    end;
  finally
    xcb_disconnect(Conn);
  end;
end;

procedure TXCBTest.TestExtensionsQuery();
var
  Conn: Pxcb_connection_t;
  ScreenNum: Integer;
  RandRCookie: xcb_randr_query_version_cookie_t;
  RandRReply: Pxcb_randr_query_version_reply_t;
  RenderCookie: xcb_render_query_version_cookie_t;
  RenderReply: Pxcb_render_query_version_reply_t;
  ShmCookie: xcb_shm_query_version_cookie_t;
  ShmReply: Pxcb_shm_query_version_reply_t;
begin
  ScreenNum := 0;
  Conn := xcb_connect(nil, @ScreenNum);
  if Conn = nil then Exit;
  try
    if xcb_connection_has_error(Conn) = 0 then
    begin
      // Query RandR extension
      RandRCookie := xcb_randr_query_version(Conn, 1, 4);
      RandRReply := xcb_randr_query_version_reply(Conn, RandRCookie, nil);
      if RandRReply <> nil then
      begin
        AssertTrue('RandR major version >= 1', RandRReply^.major_version >= 1);
        libc_free(RandRReply);
      end;

      // Query Render extension
      RenderCookie := xcb_render_query_version(Conn, 0, 11);
      RenderReply := xcb_render_query_version_reply(Conn, RenderCookie, nil);
      if RenderReply <> nil then
      begin
        AssertTrue('Render supported', RenderReply^.major_version >= 0);
        libc_free(RenderReply);
      end;

      // Query SHM extension
      ShmCookie := xcb_shm_query_version(Conn);
      ShmReply := xcb_shm_query_version_reply(Conn, ShmCookie, nil);
      if ShmReply <> nil then
      begin
        AssertTrue('SHM supported', ShmReply^.major_version >= 1);
        libc_free(ShmReply);
      end;
    end;
  finally
    xcb_disconnect(Conn);
  end;
end;

initialization
  RegisterTest(TXCBTest);

end.
