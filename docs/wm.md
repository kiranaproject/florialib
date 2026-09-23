# Floria.XCB.WM — Window Manager Framework Specification

## 1. Overview & Architecture

`Floria.XCB.WM` is a high-level, Object Pascal window management framework built on top of `Floria.XCB`, `Floria.XCB.EWMH`, and `Floria.XCB.ICCCM`. 

The architecture is designed with a clear separation of concerns to serve two complementary roles in a desktop environment:
1. **Window Manager (`Floria.XCB.WM`)**: Takes ownership of the root window via `SubstructureRedirect`, reparents client windows into decorated frames, manages stacking and focus, coordinates virtual desktops, and publishes EWMH state.
2. **Desktop Shell Components (`Floria.XCB.Desktop`)**: Designed for panels, taskbars, docks, pagers, and system monitors that observe the EWMH state (`_NET_CLIENT_LIST`, `_NET_ACTIVE_WINDOW`, `_NET_WM_PID`, `_NET_CURRENT_DESKTOP`) without claiming WM redirection.

```
                         ┌─────────────────────────────────┐
                         │            X11 Server           │
                         └───────────────┬─────────────────┘
                                         │ libxcb
                                         ▼
                         ┌─────────────────────────────────┐
                         │     Floria.XCB & Extensions     │
                         │    (ICCCM, EWMH, RandR, etc.)   │
                         └───────┬─────────────────┬───────┘
                                 │                 │
            ┌────────────────────┴───┐         ┌───┴────────────────────┐
            ▼                        ▼         ▼                        ▼
  ┌───────────────────┐    ┌─────────────────────────────────┐   ┌───────────────────────┐
  │  Floria.XCB.WM    │    │       Floria.XCB.Desktop        │   │    Floria-Toolkit     │
  ├───────────────────┤    ├─────────────────────────────────┤   ├───────────────────────┤
  │ • SubstructureRedir│   │ • EWMH State Watcher            │   │ • Frame Painters      │
  │ • Frame Reparent  │    │ • Taskbar / Panel Helpers       │   │ • Custom Titlebars    │
  │ • Stack & Focus   │    │ • Process ID (_NET_WM_PID)      │   │ • Widget UI Tree      │
  │ • Workspaces/EWMH │    │ • Strut / Workarea Reservations │   │                       │
  └───────────────────┘    └─────────────────────────────────┘   └───────────────────────┘
```

---

## 2. Core Data Types & Records

### `TXCBFrameMetrics`
Defines the spatial geometry and border insets for client window decoration frames:
```pascal
type
  TXCBFrameInsets = record
    Left   : Integer;
    Top    : Integer;
    Right  : Integer;
    Bottom : Integer;
  end;

  TXCBFrameMetrics = record
    TitlebarHeight : Integer; // Height of the top titlebar (e.g. 24px)
    BorderWidth    : Integer; // Width of surrounding window border (e.g. 1px)
    Insets         : TXCBFrameInsets; // Total frame insets surrounding the client
  end;
```

### `TXCBWindowState` & Flags
Tracks window state transitions and EWMH properties:
```pascal
type
  TXCBWindowStateFlag = (
    wsMinimized,
    wsMaximizedHorz,
    wsMaximizedVert,
    wsFullscreen,
    wsSticky,
    wsAbove,
    wsBelow,
    wsHidden,
    wsFocused
  );
  TXCBWindowState = set of TXCBWindowStateFlag;

  TXCBWindowType = (
    wtNormal,
    wtDialog,
    wtDock,
    wtDesktop,
    wtToolbar,
    wtMenu,
    wtUtility,
    wtSplash
  );
```

---

## 3. Client Representation (`TXCBWMClient`)

The `TXCBWMClient` class represents an actively managed top-level client application window and its surrounding decoration frame.

### Properties
- `ClientWindow`: `xcb_window_t` — The raw client application window ID.
- `FrameWindow`: `xcb_window_t` — The window manager's reparented container frame.
- `Title`: `AnsiString` — Synchronized from `_NET_WM_NAME` or `WM_NAME`.
- `WindowClass`: `AnsiString` — Instance and class names from `WM_CLASS`.
- `Pid`: `Cardinal` — Process ID from `_NET_WM_PID`.
- `Desktop`: `Integer` — Virtual desktop index (or `$FFFFFFFF` for sticky).
- `WindowType`: `TXCBWindowType` — Detected from `_NET_WM_WINDOW_TYPE`.
- `State`: `TXCBWindowState` — Current state set.
- `CurrentRect`: `TRect` — Current frame geometry (X, Y, Width, Height).
- `RestoredRect`: `TRect` — Cached geometry used when unmaximizing or exiting fullscreen.
- `SupportsDeleteWindow`: `Boolean` — `True` if `WM_DELETE_WINDOW` protocol is present.
- `SupportsTakeFocus`: `Boolean` — `True` if `WM_TAKE_FOCUS` protocol is present.

### Operations & State Transitions
- `procedure Activate();` — Raises the frame window, focuses input, and updates `_NET_ACTIVE_WINDOW`.
- `procedure Close();` — Gracefully requests termination via `WM_DELETE_WINDOW` client message (or `xcb_kill_client` fallback).
- `procedure Maximize();` / `procedure Restore();` — Toggles maximization, adjusts to available screen workarea, and preserves restored bounds.
- `procedure Minimize();` — Unmaps the frame and updates state to iconic.
- `procedure SetFullscreen(const AFullscreen: Boolean);` — Removes decoration insets and expands over the entire display monitor.
- `procedure Move(const AX, AY: Integer);` — Moves the frame container.
- `procedure Resize(const AWidth, AHeight: Integer);` — Resizes frame and reposition/resizes child client window according to insets.
- `procedure SetDesktop(const ADesktopIndex: Integer);` — Moves client between virtual workspaces.

---

## 4. Window Manager Core (`TXCBWindowManager`)

`TXCBWindowManager` is the master controller managing root redirection, event routing, and EWMH synchronization.

### Lifecycle & Initialization
1. **Connect**: Connects to the X server or attaches to an existing `Pxcb_connection_t`.
2. **Claim Ownership**: Sets `XCB_EVENT_MASK_SUBSTRUCTURE_REDIRECT` and `XCB_EVENT_MASK_SUBSTRUCTURE_NOTIFY` on the root window using checked requests. Detects `BadAccess` to cleanly abort if another window manager is already running.
3. **EWMH Initialization**: Creates a supporting WM check window, registers `_NET_SUPPORTED` atoms, publishes `_NET_SUPPORTING_WM_CHECK`, and sets `_NET_WM_NAME`.
4. **Initial Window Scan**: Queries existing top-level windows via `xcb_query_tree` and manages windows that were started before the WM launched.

### Window Filtering & Decoration Policy
- **Override-Redirect Bypass**: Windows with `override_redirect = 1` (menus, tooltips, popups) are never reparented or managed.
- **Dock & Desktop Bypass**: Windows with `_NET_WM_WINDOW_TYPE_DOCK` (panels) or `_NET_WM_WINDOW_TYPE_DESKTOP` (wallpaper managers) are mapped directly without frame reparenting or titlebars.
- **Normal & Dialog Windows**: Reparented into frame windows with configured `TXCBFrameMetrics`.

### Virtual Desktops / Workspaces
- `DesktopCount: Integer` — Number of workspaces (advertised via `_NET_NUMBER_OF_DESKTOPS`).
- `CurrentDesktop: Integer` — Active workspace index (advertised via `_NET_CURRENT_DESKTOP`).
- `DesktopNames: TStringList` — Workspace names (`_NET_DESKTOP_NAMES`).
- **Switching Logic**: Unmaps non-sticky clients of the previous desktop and maps clients belonging to the newly selected desktop.

### Interactive Operations
- **Mouse Drag Tracking**: Titlebar drag-to-move and frame border drag-to-resize.
- **EWMH Move/Resize**: Responds to `_NET_WM_MOVERESIZE` client messages triggered by client-side decorated apps.

### Event Processing & Extensibility
- `function ProcessEvent(const AEvent: Pxcb_generic_event_t): Boolean;`
- `procedure Run();` — Main event loop with clean shutdown support.
- **Virtual Hooks & Callbacks**:
  - `DoOnClientMapped(const AClient: TXCBWMClient); virtual;`
  - `DoOnClientUnmapped(const AClient: TXCBWMClient); virtual;`
  - `DoOnClientActivated(const AClient: TXCBWMClient); virtual;`
  - `DoOnClientConfigure(const AClient: TXCBWMClient); virtual;`
  - `DoOnDesktopChanged(const AOldDesktop, ANewDesktop: Integer); virtual;`
  - `property OnFramePaint: TXCBFramePaintEvent read ... write ...;`

---

## 5. Testing & Verification

### Test Suite (`Floria.XCB.WM.Test.pas`)
- **Offline / Mockable Unit Tests**:
  - Frame metrics and geometry calculations.
  - State machine transitions (maximize, restore, fullscreen, minimize).
  - Virtual desktop filtering (which clients map/unmap during desktop switch).
  - ICCCM size constraints and aspect ratio clamping.
- **Live XCB Integration Tests**:
  - EWMH atom initialization and check window creation (safeguarded when running headless or without `$DISPLAY`).
- **Workflow Compliance**:
  - All tests must pass: `pasbuild test` (`E:0 F:0`).
  - Must install to local repository: `pasbuild install`.
