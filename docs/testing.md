# Testing

`florialib` uses FPCUnit through `src/test/pascal/TestRunner.pas`. The suite
covers CSS, XML, HTML, SVG, image codecs, canvas/graphics, path operations,
text layout, display lists, GPU batching, XCB bindings, and the window manager.

---

## 1. Running the suite

```bash
pasbuild test -p pic
```

`-p pic` enables `-Cg` (Position-Independent Code), matching the units that are
installed for downstream shared libraries.

A clean run:

```bash
rm -rf target
pasbuild test -p pic
```

The runner supports the standard FPCUnit flags; `project.xml` passes
`--all --format=plain`.

---

## 2. Test data and scratch files

Tests must not write into the repository source tree or depend on a writable
`/tmp`. The SVGZ file test uses `target/test-tmp`, created next to the test
runner. If that location is not writable, it falls back to the system temp
directory.

If you add a test that needs a fixture, put it under `src/test/resources/` (or a
dedicated subdirectory) and resolve it relative to the repository root or the
test runner, not by an absolute workstation path.

The optional baseline-JPEG decoding test reads a real image only when
`FLORIA_TEST_JPEG` points to an existing JPEG file:

```bash
FLORIA_TEST_JPEG=/path/to/photo.jpg pasbuild test -p pic
```

Without it, the test skips rather than depending on a developer-specific path.

---

## 3. Headless and GPU requirements

Some XCB and GPU tests are only meaningful with a real display or OpenGL
implementation. They can silently skip otherwise, which makes a green run
misleading. Set these environment variables to turn a missing dependency into a
test failure:

| Variable | Effect |
|---|---|
| `FLORIA_REQUIRE_DISPLAY=1` | Fails if `xcb_connect` cannot reach an X display |
| `FLORIA_REQUIRE_GL=1` | Fails if the OpenGL/GLES loader cannot find a usable library |

Example headless run:

```bash
Xvfb :99 -screen 0 1280x1024x24 &
export DISPLAY=:99
export FLORIA_REQUIRE_DISPLAY=1
export FLORIA_REQUIRE_GL=1
export LIBGL_ALWAYS_SOFTWARE=1
pasbuild test -p pic
```

Mesa's `llvmpipe` provides a software GL implementation suitable for CI.

---

## 4. CI script

`scripts/ci.sh` performs:

1. `pasbuild resolve -p pic` and checks that `-Cg` is present.
2. `scripts/check-repo.py` (unit/package/umbrella links and documentation links).
3. A clean build and full test run (wrapped in `xvfb-run` when no display is set).
4. `pasbuild install -p pic`.
5. `lazbuild src/main/pascal/florialib.lpk`.

CI should set `FLORIA_REQUIRE_DISPLAY=1` and `FLORIA_REQUIRE_GL=1` after
provisioning Xvfb and Mesa. The script assumes FPC, Pasbuild, fpGUI, and its
`extras/aggpas` package are already installed.

---

## 5. Adding tests

1. Create `src/test/pascal/floria.<subsystem>.test.pas` (or add to an existing
   suite).
2. Publish test methods on a `TTestCase` subclass.
3. Call `RegisterTest(TMyTestSuite)` in the unit's `initialization` section.
4. Add the unit to `src/test/pascal/TestRunner.pas`'s `uses` clause.
5. Run `pasbuild test -p pic` and confirm `E:0 F:0`.
6. Run `python3 scripts/check-repo.py` and `pasbuild install -p pic`.

Do not hardcode the total test count in documentation; use the test runner or a
CI badge instead.
