# Generated XCB Bindings

The `Floria.XCB.*` units and `Floria.X11.KeySym` are generated from C headers
with **blaise-bindgen**. Their headers contain a `DO NOT EDIT` marker.

This directory records the mapping and regeneration commands so the generated
code is reproducible. The checked-in units do **not** currently record the exact
generator version; record it here before the next regeneration.

---

## Unit mapping

| Unit | Headers / library | Notes |
|---|---|---|
| `Floria.XCB` | `xcb` | Core protocol |
| `Floria.XCB.ICCCM` | `xcb-icccm` | ICCCM helpers |
| `Floria.XCB.EWMH` | `xcb-ewmh` | EWMH helpers |
| `Floria.XCB.RandR` | `xcb-randr` | Contains a manual union workaround |
| `Floria.XCB.Render` | `xcb-render` | |
| `Floria.XCB.SHM` | `xcb-shm` | |
| `Floria.XCB.Shape` | `xcb-shape` | |
| `Floria.XCB.XFixes` | `xcb-xfixes` | |
| `Floria.XCB.Cursor` | `xcb-cursor` | |
| `Floria.XCB.Keysyms` | `xcb-keysyms` | |
| `Floria.X11.KeySym` | X11 `keysymdef.h` | Constant catalog |
| `Floria.XCB.Composite` | `xcb-composite` | Currently hand-written |
| `Floria.XCB.Damage` | `xcb-damage` | Currently hand-written |

`Floria.XCB.WM`, `Floria.XCB.WM.Compositor`, and the inline Xinerama bindings
in `floria.xcb.wm.pas` are hand-written first-party code, not generated.

---

## Regeneration commands

The generated headers use the following pattern:

```bash
bindgen --header /usr/include/xcb/xcb.h \
        --unit Floria.XCB \
        --lib xcb

bindgen --header /usr/include/xcb/xcb_icccm.h \
        --unit Floria.XCB.ICCCM \
        --lib xcb-icccm
```

Repeat for each row in the table. Record the exact bindgen version used:

```text
blaise-bindgen version: <record here>
```

Suggested pinned workflow:

1. Install the pinned blaise-bindgen release.
2. Run the commands above against a known header set (record the distribution
   and package versions).
3. Regenerate all units in one pass.
4. Run `pasbuild test -p pic`.
5. Review the diff; generated code should change only where the headers or the
   generator changed.

---

## Known limitations

- `floria.xcb.randr.pas` contains a hand-written variant record for
  `xcb_randr_notify_data_t` because the generator did not emit the C union.
  Regenerate once bindgen can represent unions; do not hand-edit other generated
  code.
- `Floria.XCB.Composite` and `Floria.XCB.Damage` are presently hand-written.
  They should move into the generated set when the generator supports their
  request/reply signatures.
- Xinerama is used only as a legacy multi-head fallback and is declared inline
  in `floria.xcb.wm.pas`. It should become a generated `Floria.XCB.Xinerama`
  unit if it becomes a first-class dependency.

---

## Artifact policy

Generated `.ppu`/`.o` files belong in `target/`, never in `src/`. Do not commit
Lazarus `.compiled` caches or unit output directories.
