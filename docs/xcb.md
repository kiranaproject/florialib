# XCB & Window Manager Subsystem Guide

`florialib` provides a clean, modern Object Pascal binding suite for **XCB (X C Binding)** and the official X11 client & window manager protocols.

Designed specifically to avoid the thread-safety issues, synchronous round-trips, and bloated memory overhead of legacy Xlib, this subsystem provides everything required to create full-featured X11 window managers and high-performance desktop GUI toolkits.

---

## Unit Architecture

| Unit | Underlying Library | Purpose |
|---|---|---|
| [`Floria.XCB`](file:///home/afumi/Documents/projects/kirana/florialib/src/main/pascal/Floria.XCB.pas) | `libxcb` | Core X11 protocol: connections, windows, drawables, GC, atoms, event loop, errors. |
| [`Floria.XCB.ICCCM`](file:///home/afumi/Documents/projects/kirana/florialib/src/main/pascal/Floria.XCB.ICCCM.pas) | `libxcb-icccm` | Standard ICCCM 2.0 protocols (`WM_NAME`, `WM_HINTS`, `WM_NORMAL_HINTS`, `WM_PROTOCOLS`, `WM_DELETE_WINDOW`). |
| [`Floria.XCB.EWMH`](file:///home/afumi/Documents/projects/kirana/florialib/src/main/pascal/Floria.XCB.EWMH.pas) | `libxcb-ewmh` | Extended Window Manager Hints (`_NET_SUPPORTED`, `_NET_CLIENT_LIST`, `_NET_ACTIVE_WINDOW`, window types/states/struts). |
| [`Floria.XCB.RandR`](file:///home/afumi/Documents/projects/kirana/florialib/src/main/pascal/Floria.XCB.RandR.pas) | `libxcb-randr` | Multi-monitor display management: screen resources, CRTCs, outputs, resolutions, refresh rates. |
| [`Floria.XCB.Render`](file:///home/afumi/Documents/projects/kirana/florialib/src/main/pascal/Floria.XCB.Render.pas) | `libxcb-render` | Hardware-accelerated 2D compositing, alpha blending, picture formats, transforms, and glyph sets. |
| [`Floria.XCB.SHM`](file:///home/afumi/Documents/projects/kirana/florialib/src/main/pascal/Floria.XCB.SHM.pas) | `libxcb-shm` | Shared memory extension for ultra-fast software framebuffers and CPU-side blitting. |
| [`Floria.XCB.Shape`](file:///home/afumi/Documents/projects/kirana/florialib/src/main/pascal/Floria.XCB.Shape.pas) | `libxcb-shape` | Non-rectangular window masks (rounded corners, shaped titlebars, custom shadows). |
| [`Floria.XCB.XFixes`](file:///home/afumi/Documents/projects/kirana/florialib/src/main/pascal/Floria.XCB.XFixes.pas) | `libxcb-xfixes` | Modern X11 fixes: invisible cursor, cursor tracking, server-side region manipulation. |
| [`Floria.XCB.Cursor`](file:///home/afumi/Documents/projects/kirana/florialib/src/main/pascal/Floria.XCB.Cursor.pas) | `libxcb-cursor` | Themeable cursor context and shape loading from standard X11 cursor themes. |
| [`Floria.XCB.Keysyms`](file:///home/afumi/Documents/projects/kirana/florialib/src/main/pascal/Floria.XCB.Keysyms.pas) | `libxcb-keysyms` | Translation between hardware keycodes and X11 KeySyms. |
| [`Floria.X11.KeySym`](file:///home/afumi/Documents/projects/kirana/florialib/src/main/pascal/Floria.X11.KeySym.pas) | Header Constants | Comprehensive catalog of X11 KeySym constants (Latin, function keys, keypad, multimedia). |

---

## 1. Connecting & Managing the Event Loop

Connecting to the display server is asynchronous and non-blocking in XCB:

```pascal
uses Floria.XCB;

var
  Conn       : Pxcb_connection_t;
  ScreenNum  : LongInt;
  Setup      : Pxcb_setup_t;
  ScreenIter : xcb_screen_iterator_t;
  Screen     : Pxcb_screen_t;
  Event      : Pxcb_generic_event_t;
begin
  // Connect to default $DISPLAY
  Conn := xcb_connect(nil, @ScreenNum);
  if xcb_connection_has_error(Conn) > 0 then
    raise Exception.Create('Failed to connect to X server');
  try
    // Obtain primary screen
    Setup := xcb_get_setup(Conn);
    ScreenIter := xcb_setup_roots_iterator(Setup);
    Screen := ScreenIter.data;

    // Event loop
    while True do
    begin
      Event := xcb_wait_for_event(Conn);
      if Event = nil then
        Break;
      try
        case (Event^.response_type and $7F) of
          XCB_BUTTON_PRESS:
            WriteLn('Pointer button pressed');
          XCB_KEY_PRESS:
            WriteLn('Key pressed');
        end;
      finally
        FreeMem(Event);
      end;
    end;
  finally
    xcb_disconnect(Conn);
  end;
end;
```

---

## 2. Window Manager Essentials

### Claiming Window Manager Ownership (`SubstructureRedirect`)

An X11 window manager must select `XCB_EVENT_MASK_SUBSTRUCTURE_REDIRECT` on the root window. If another WM is already running, the X server returns a `BadAccess` error.

```pascal
var
  Values : array[0..0] of UInt32;
  Cookie : xcb_void_cookie_t;
  Err    : Pxcb_generic_error_t;
begin
  Values[0] := XCB_EVENT_MASK_SUBSTRUCTURE_REDIRECT or
               XCB_EVENT_MASK_SUBSTRUCTURE_NOTIFY or
               XCB_EVENT_MASK_STRUCTURE_NOTIFY or
               XCB_EVENT_MASK_BUTTON_PRESS;

  Cookie := xcb_change_window_attributes_checked(
    Conn,
    Screen^.root,
    XCB_CW_EVENT_MASK,
    @Values[0]
  );

  Err := xcb_request_check(Conn, Cookie);
  if Err <> nil then
  begin
    FreeMem(Err);
    raise Exception.Create('Another Window Manager is already running!');
  end;
end;
```

### Initializing EWMH (`Floria.XCB.EWMH`)

Modern desktop environments require Extended Window Manager Hints so pagers, taskbars, and client apps know what features the WM supports:

```pascal
uses Floria.XCB, Floria.XCB.EWMH;

var
  Ewmh: xcb_ewmh_connection_t;
begin
  if xcb_ewmh_init_atoms_replies(@Ewmh, xcb_ewmh_init_atoms(Conn, @Ewmh), nil) = 0 then
    raise Exception.Create('Failed to initialize EWMH atoms');
  try
    // Set supported atoms on the root window
    xcb_ewmh_set_supported(@Ewmh, ScreenNum, 7, @Ewmh._NET_SUPPORTED);
    // Notify clients of window manager name
    xcb_ewmh_set_wm_name(@Ewmh, Screen^.root, Length('FloriaWM'), 'FloriaWM');
  finally
    xcb_ewmh_connection_wipe(@Ewmh);
  end;
end;
```

### Graceful Client Exit (`WM_DELETE_WINDOW`)

Using `Floria.XCB.ICCCM`, window managers can request clients to close gracefully instead of forcibly destroying their connection:

```pascal
uses Floria.XCB, Floria.XCB.ICCCM;

procedure SendDeleteWindow(AConn: Pxcb_connection_t; AWindow: xcb_window_t;
  AWMProtocols, AWMDeleteWin: xcb_atom_t);
var
  Ev: xcb_client_message_event_t;
begin
  FillChar(Ev, SizeOf(Ev), 0);
  Ev.response_type  := XCB_CLIENT_MESSAGE;
  Ev.format         := 32;
  Ev.window         := AWindow;
  Ev.type_          := AWMProtocols;
  Ev.data.data32[0] := AWMDeleteWin;
  Ev.data.data32[1] := XCB_CURRENT_TIME;

  xcb_send_event(AConn, 0, AWindow, XCB_EVENT_MASK_NO_EVENT, PAnsiChar(@Ev));
  xcb_flush(AConn);
end;
```

---

## 3. Multi-Monitor Detection (`Floria.XCB.RandR`)

Using `Floria.XCB.RandR`, applications query physical display monitors, geometries, and output layouts:

```pascal
uses Floria.XCB, Floria.XCB.RandR;

var
  Cookie   : xcb_randr_get_screen_resources_current_cookie_t;
  ResReply : Pxcb_randr_get_screen_resources_current_reply_t;
  Outputs  : Pxcb_randr_output_t;
  I        : Integer;
begin
  Cookie := xcb_randr_get_screen_resources_current(Conn, Screen^.root);
  ResReply := xcb_randr_get_screen_resources_current_reply(Conn, Cookie, nil);
  if ResReply <> nil then
  begin
    try
      Outputs := xcb_randr_get_screen_resources_current_outputs(ResReply);
      WriteLn('Number of active outputs: ', ResReply^.num_outputs);
      // Query individual CRTCs and output properties...
    finally
      FreeMem(ResReply);
    end;
  end;
end;
```

---

## 4. Hardware-Accelerated 2D Rendering (`Floria.XCB.Render`)

The XRender extension provides GPU-accelerated compositing and alpha blending directly on the X server:

```pascal
uses Floria.XCB, Floria.XCB.Render;

var
  PictFormat: xcb_render_pictformat_t;
  Picture   : xcb_render_picture_t;
  Color     : xcb_render_color_t;
begin
  // Query 32-bit ARGB picture format
  PictFormat := ...;

  Picture := xcb_generate_id(Conn);
  xcb_render_create_picture(Conn, Picture, MyWindow, PictFormat, 0, nil);

  // Fill with semi-transparent blue (pre-multiplied alpha)
  Color.red   := 0;
  Color.green := $8000;
  Color.blue  := $ffff;
  Color.alpha := $8000; // 50% opacity

  xcb_render_fill_rectangles(
    Conn,
    XCB_RENDER_PICT_OP_SRC,
    Picture,
    Color,
    1,
    @MyRect
  );
  xcb_flush(Conn);
end;
```

---

## 5. Keyboard Handling (`Floria.XCB.Keysyms`, `Floria.X11.KeySym`)

Translates raw hardware keycodes into symbolic keys:

```pascal
uses Floria.XCB, Floria.XCB.Keysyms, Floria.X11.KeySym;

var
  KeySymbols: Pxcb_key_symbols_t;
  KeySym    : xcb_keysym_t;
begin
  KeySymbols := xcb_key_symbols_alloc(Conn);
  try
    // Translate keycode from xcb_key_press_event_t
    KeySym := xcb_key_symbols_get_keysym(KeySymbols, KeyEvent^.detail, 0);

    case KeySym of
      XK_Return: WriteLn('Enter pressed');
      XK_Escape: WriteLn('Escape pressed');
      XK_F1..XK_F12: WriteLn('Function key pressed');
      XK_AudioRaiseVolume: WriteLn('Volume Up pressed');
    end;
  finally
    xcb_key_symbols_free(KeySymbols);
  end;
end;
```
