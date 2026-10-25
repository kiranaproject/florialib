# pathgolden

Regenerates `src/test/pascal/floria.path.golden.data.pas`, the frozen expected
results for the path-engine regression corpus.

## Why this exists

`Floria.Path.Ops` used to delegate to a vendored Clipper2 port. While that port
was present, the test suite could check the first-party engine against it
directly. Once the vendored code is deleted there is nothing left to compare
against, so the reference behaviour is captured **before** deletion.

Capturing the data from the reference engine — rather than from the engine
under test — is the whole point. Data generated from the implementation being
tested would only assert that it equals itself, and would pass through any
regression introduced at capture time.

## When to run

Only while a reference backend is still registered. After `Floria.Path.Engine.Clipper2`
is removed this tool will refuse to run, which is intended: the golden data is
committed and normal builds never regenerate it.

Run it when:

- a corpus case is added, renamed, or removed
- a behaviour change is deliberate and the expected values must move with it

A deliberate behaviour change should show up as a reviewable diff in
`floria.path.golden.data.pas`. Never regenerate to make a failing test pass
without understanding why the numbers moved.

## How to run

From the repository root:

```bash
mkdir -p target/tools
fpc -Fu"$PWD/target/units" \
    -Fu"$PWD/src/test/pascal" \
    -Fu"$HOME/.pasbuild/repository/fpgui-framework/2.2.0-SNAPSHOT/x86_64-linux-3.2.3/units" \
    -FEtarget/tools -o"$PWD/target/tools/pathgolden" \
    tools/pathgolden/pathgolden.pas

./target/tools/pathgolden > src/test/pascal/floria.path.golden.data.pas
```

Progress goes to stderr; the unit source goes to stdout. Review the diff before
committing.

## What the data records

Per case: total absolute area, contour count, and bounds.

The tests assert **area** and **bounds**. They deliberately do not assert:

- **Contour count.** Backends legitimately differ in how they split zero-area
  remnants. The reference engine returns a degenerate zero-area contour for
  `A - A` where the first-party engine returns none. Freezing that would pin an
  artifact rather than a contract.
- **Exact vertex positions.** Arc tessellation step counts differ by a segment
  or two between implementations. Area and bounds absorb that difference while
  still catching real regressions.

Zero-area results are normalised at capture time: the contour count is recorded
as 0 and bounds as zeros, so the `MaxDouble` sentinels a degenerate `GetBounds`
produces are never frozen into the data.

## Corpus

The inputs live in `src/test/pascal/floria.path.corpus.pas`, shared by this tool
and by `floria.path.golden.test.pas` so the two cannot drift apart. Each case
carries its own tolerance, which the golden test also uses.
