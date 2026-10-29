# pathbench

Measures the first-party path engine: booleans, offsetting, and simplification
across a range of geometry sizes.

The engine was written for correctness first. This tool exists to check the
performance assumption that went with it rather than leaving it untested.

## Build and run

From the repository root:

```bash
fpc -Fu"$PWD/target/units" \
    -Fu"$HOME/.pasbuild/repository/fpgui-framework/2.2.0-SNAPSHOT/x86_64-linux-3.2.3/units" \
    -FEtarget/tools -O2 -o"$PWD/target/tools/pathbench" \
    tools/pathbench/pathbench.pas

./target/tools/pathbench
```

Build with `-O2`. Comparing an optimised engine against unoptimised benchmark
harness code measures the wrong thing.

## Method

Each size is run for five passes after a discarded warm-up pass, and the mean is
reported. The warm-up matters: the first call allocates and grows dynamic
arrays, which would otherwise be charged to the smallest size and make the
scaling ratios look better than they are.

Scaling is the ratio between consecutive sizes. Doubling the vertex count:

- near **2.0x** means linear
- near **4.0x** means quadratic
- well above 4.0x means the case is also growing its *contour count*, so read
  the `verts` column, not `sides`

Absolute milliseconds are machine-specific. The scaling column is the part that
transfers.

## Results

Recorded on x86-64 Linux, FPC 3.2.3, `-O2`. Times in ms.

### Before optimisation

| case | 100 v | 800 v | 3200 v | scaling |
|---|---|---|---|---|
| Boolean union | 0.4 | 94.4 | 368.6 | 3.9x |
| Boolean difference | 0.4 | 92.2 | 365.6 | 4.0x |
| Boolean intersect | 0.4 | 89.8 | 355.2 | 4.0x |
| Boolean xor | 0.4 | 97.8 | 387.6 | 4.0x |
| Offset +10 | 0.6 | 107.8 | 426.2 | 4.0x |
| Offset -5 | 0.2 | 38.0 | 157.6 | 4.1x |
| Self-union (rings) | – | 5616 (12800 v) | 95305 (51200 v) | 17.0x |

### After optimisation

| case | 100 v | 800 v | 3200 v | scaling |
|---|---|---|---|---|
| Boolean union | 0.2 | 16.2 | 58.6 | 3.6x |
| Boolean difference | 0.2 | 16.2 | 60.4 | 3.7x |
| Boolean intersect | 0.2 | 15.8 | 59.2 | 3.7x |
| Boolean xor | 0.4 | 16.2 | 68.8 | 4.2x |
| Offset +10 | 0.4 | 16.6 | 64.8 | 3.9x |
| Offset -5 | 0.2 | 16.2 | 64.2 | 4.0x |
| Self-union (rings) | – | 936 (12800 v) | 15563 (51200 v) | 16.6x |

Roughly **6x faster** overall, with identical output: the golden corpus in
`floria.path.golden.data.pas` passed unchanged after every change.

## What was slow, and what fixed it

Three quadratic terms were found by measurement, not by inspection.

**1. Boundary chaining scanned all segments per step.** Each step of each walk
looked for a successor by scanning the whole segment array, making chaining
O(n²) on its own. Fixed with an index sorted by start vertex plus a binary
search, so a step examines only the segments beginning at that point.

**2. Edge splitting had no early rejection.** Every segment pair ran the full
intersection computation — a division, a multiply and two more divisions —
before discovering that most pairs are far apart. Fixed with a four-comparison
bounding-box test first.

**3. Classification scanned every vertex per query.** Winding number was
computed by walking the entire operand contour for every candidate segment,
which is O(candidates × vertices). A ray-cast crossing test only ever looks at
edges whose Y range spans the query height, so edges are now bucketed by Y: a
query inspects the handful of edges near that height instead of thousands.

A fourth, subtler term was found afterwards: candidate segments were
deduplicated against everything already kept, another O(n²). Deduplication is
now a sort and a single adjacent-duplicate pass.

## What is still quadratic

Splitting compares every segment against every other segment. Bounding-box
rejection makes each comparison cheap, but the pair count is still O(n²), and
that is now the dominant cost — visible as the remaining ~3.7x scaling.

The fix is a classic sweep-line broadphase: sort events by X, maintain an active
set, and test each segment only against segments whose X range overlaps. That
turns pair generation into O(n log n + k) for k overlapping pairs. It is a
contained change — `SplitSegment` already takes the candidate set implicitly as
"all segments", so it only needs an explicit candidate list.

Not done yet because it was out of scope for a first benchmark, and because the
current numbers are adequate for the intended use (see below).

## Reading the numbers

For UI-scale geometry — a few hundred vertices — every operation is
sub-millisecond and the quadratic term is irrelevant.

It becomes visible on large paths: a 3200-vertex boolean takes ~60 ms, which is
too slow for per-frame work but fine for batch or export paths. The concentric
rings case is a deliberate stress test rather than a realistic input: at 1600
sides it is 32 rings of 1600 vertices, 51200 vertices in total.

If path operations ever land in a per-frame budget, do the sweep-line
broadphase before anything else. It is the only remaining structural cost.
