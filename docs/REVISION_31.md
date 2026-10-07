# Revision 31 — original LiquidFun and conservative transport parcels

The original Google LiquidFun adapter and a conservative parcel transport trial are available explicitly. The current particle/medium implementation remains the default: LiquidFun does not yet improve dense whole-game performance, and parcel coverage is too low under the existing background scheduler to help ordinary frames. Zoom-independent feeding is a tested requirement for both trials.

## Native particle comparison

The build automatically fetches the original Google source at `7f20402173fd143a3988c921bc384459c6a858f2`, verifies archive SHA-256 `40e6233b644f8c8ce23b92033546bed45a446b17f892c9170ffe8c9c205fab7f`, and compiles only the library. Downloaded sources, bindings and binaries remain in ignored `build/`. The original Box2D/LiquidFun source notices and `License.txt` are preserved; this is third-party code, with an original Primordia adapter. A fresh native build requires these public dependencies.

The existing cached neighbor lists do not certify a second physical radius. Uniform/LiquidFun trials reject combining them with neighbor caching explicitly; uncached grid/tree diagnostics remain available.

Three diagnostic modes are available:

- `current`: existing circular separation and species/amount-dependent encounter radii.
- `uniform`: existing separation with one physical radius, retaining independent chemical binding ranges.
- `liquidfun`: original LiquidFun water-particle contacts/pressure for fine foreground motion, with the same uniform physical radius. Default radius is four world units, one solver iteration; profiler options allow radius 1–8 and iterations 1–4.

All glyphs still render their individual orientations. Branches/forks are never physical collision shapes. Metadata, finite material, products/capacities, angular binding, consumption and stable handles remain in the authoritative native Primordia pool. No per-tick dictionary mirror is introduced. Pheromones never enter LiquidFun.

Periodic images provide seam contacts but carry no chemical material and cannot feed a cell. Solver slots are reused through chemistry compaction and rebuilt after a substantial reduction; unused slots are isolated wall points. Solver coordinates use an internal metre conversion, separate from the game's μm scale. LiquidFun's own diameter/timestep velocity limit remains part of this candidate's numerical behavior.

Coarse hidden and camera catch-up intervals retain circular separation because the adapter is stepped only for fine foreground intervals. Chemistry keeps its conservative grid: LiquidFun contacts are computed during solver stepping and do not automatically cover all post-step chemical encounter ranges. Fine chemistry omits the additional physical search radius when LiquidFun already handled those contacts; catch-up/coarse passes retain both ranges.

This is a **particle motion/contact trial**, not a complete replacement solvent engine. The established fluid grid, membrane exclusion, chemical-permeable plants and cell/cilia momentum coupling remain. LiquidFun contact-pressure feedback into deforming membranes and replacing the solvent grid are unimplemented promotion gates.

## Zoom and parcel rules

Both experimental engines and parcels pin their simulation footprint at configuration, centered on the followed cell. Ordinary scene setup uses the widest 80% footprint. Display zoom and free pan do not change integration, chemistry, feeding or random draws. Regression trials cycle between 80% and 12×, pan elsewhere, and compare packet states, cell physiology, material, acidity, events and all three random streams.

This domain rule is diagnostic; the current engine without parcels retains its existing camera activity policy. Remote free-view areas or a resized viewport can exceed the trial's pinned footprint. It cannot replace ordinary full-viewport activity without resolving that presentation/coverage gate. Zoom creates no particles, tissue, energy or currency; configuring/disabling a trial grants no resources.

The parcel stage shares **distant advection calculations only**:

- Every child remains an individual native packet with its own amount, product, capacity, identity, metadata, pose, velocity and orientation. No merging, splitting, reconstruction or new particles occur.
- Groups share species, a 64-unit bin and compatible elapsed-time cohorts; chunks contain 4–32 children. Mean flow integration is shared, with individual damped velocity differences retained.
- Cell extent plus a conservative 384-unit protected margin disables grouping. Large cells may protect the whole habitat; invalid protection data falls back to individual work.
- Sharp flow variation, incompatible elapsed times or divergent velocities also use individual integration. Only coarse intervals over 0.05 and up to two seconds qualify.
- Independent translational/rotational diffusion and RNG order are unchanged. Pheromones are always individual.
- Collisions, chemistry and absorption still act on fine children. This stage does not average angles, source/family reports or reaction eligibility.

Shared advection is an approximation in varying flow; zoom-independent outcomes do not imply exact parity with individual transport. Long-horizon feeding/chemistry balance must be calibrated before default adoption.

## Fixed-horizon rendered comparison

Godot 4.7.2, Ryzen 9950X, RTX 5080, Mobile renderer, 1440×900, 80% view. Paid cilia, water effects, bloom, sparks and music preparation are enabled; audio uses the Dummy driver. Each capture draws 120 frames with one 1/60-second tick per frame, exactly two simulated seconds. These are **mean / p95 frame milliseconds**, not live FPS.

| Initial fixture | Current | Original LiquidFun |
| --- | ---: | ---: |
| 5k uniform | 10.66 / 12.34 | 10.88 / 12.59 |
| 20k uniform | 18.44 / 21.42 | 21.21 / 24.23 |
| 50k uniform | 32.27 / 47.69 | 43.52 / 54.80 |
| 50k clustered | 24.92 / 52.56 | 32.62 / 63.48 |
| 20k, large cell, mixed sizes | 18.45 / 22.99 | 20.72 / 24.48 |

A second final-code LiquidFun 50k capture gives **44.03 / 54.38 ms**. Uniform-radius separation in an earlier independent pass gives **19.00 / 22.11 ms** at 20k and **33.15 / 50.66 ms** at 50k; it establishes no clear performance advantage.

The models change ecology, so their final states are not presented as identical. At 50k uniform, the current engine reaches a minimum 19,606 packets and finishes at 19,794; LiquidFun reaches 30,711 and finishes at 30,917. Their merge counts are 30,972 and 16,945. LiquidFun changes encounter motion and retains more individual packets, increasing later transport, chemistry and rendering work. Neither fixture sustains 50k.

The final 50k mean simulation tick is **22.16 ms current / 31.19 ms LiquidFun**. Transport is **6.05 / 11.69**, chemistry **8.63 / 10.90**, membrane exclusion **2.31 / 2.85**, particle synchronization **2.72 / 3.06**, and music preparation **0.10 / 0.14**. These are nested phase timings, not additive independent frame costs.

LiquidFun's own solve averages **2.86 ms**; preparation/application together about **0.25 ms**. Total transport includes ordinary flow/diffusion, gather, slot rebuilding and publication. Replacing contacts alone leaves substantial custom chemistry and body/render work.

Removing unnecessary physical candidates from fine chemistry reduces the two-run mean chemistry phase **13.71 → 10.80 ms** (about 21%), and whole-frame mean **48.05 → 43.77 ms** (about 9%) in the captured passes. Chemistry events, remaining material, biomass/radius and all three RNG endpoints match exactly before/after this culling. Local inspection snapshot counts vary with display timing. Shared host/driver load affects absolute times; these are limited trials, not confidence intervals or phone results.

## Parcel transport measurements

A transport-only native benchmark uses half-second steps, uniform finite clouds, the same child RNG sequence and reversed-order repetitions. It excludes biology, contacts, drawing and whole-frame cost.

| Packets / flow | Individual mean ms | Shared mean ms | Result |
| --- | ---: | ---: | --- |
| 5k / constant | 1.305 | 1.462 | Slower |
| 5k / eddies | 1.302 | 1.543 | Slower |
| 20k / constant | 5.138 | 4.043 | About 21% less |
| 20k / eddies | 5.160 | 5.062 | About 2% less |
| 50k / constant | 12.845 | 8.979 | About 30% less |
| 50k / eddies | 12.864 | 12.131 | About 6% less |

A habitat-wide 50k whole-game fixture spreads the same finite initial material across the wrapping world. Parcels off/on measure **12.74 / 16.54 → 12.70 / 16.45 ms** mean/p95: essentially no demonstrated frame gain. Only **378 child updates** form **92 groups** across 120 ticks. Staggered scheduling, species/time cohorts, cell protection and shear leave little compatible work per batch. Most of these 50k particles are outside the fine view; this is not a 50k fully active result.

The two global trials have 522 versus 519 merges and 661.044 versus 661.688 units of remaining packet material after ordinary ecology. Shared transport may alter later encounters; preservation during transport is tested separately. This short trial does not establish long-run balance.

The original view-confined 50k parcel captures form zero groups; events/material/RNG endpoints remain identical, with added overhead. Parcel timing alone must not be used to justify promotion.

## Live scheduling

Final-code initial-20k runs request eight wall seconds:

| Engine | Mean / p95 frame ms | Simulated / wall seconds | Maximum ticks per frame | Eight-tick frames |
| --- | ---: | ---: | ---: | ---: |
| Current | 25.41 / 102.93 | 7.87 / 8.01 | 8 | 10 |
| LiquidFun | 28.20 / 52.72 | 8.00 / 8.01 | 4 | 0 |

Counts shrink to about 7.8k and 13.8k. The current engine's earlier unchanged-code live pass measured 20.07 / 31.11 ms, showing scheduling/host variability. Both final p95 values exceed the 16.67 ms budget. Fewer catch-up bursts in this LiquidFun pass do not establish sustained 20k/60 FPS or mobile thermal performance.

## Validation and reproduction

The final native suite passes **69,417 assertions** and the script suite **3,291**, with zero failures. Steam launcher fixtures pass ten tests. Focused checks also verify that the habitat-wide fixture preserves its original material. Tests cover zoom/pan equality, finite motion, actual solver contacts/pressure, periodic seams, closed-fixture momentum, contact-free pheromones, stable handles, coarse separation fallback, parcel material/product/capacity preservation, independent diffusion/rotation, large/invalid protection and shear fallback. Editor import and whitespace checks pass.

Steam discovery remains the default:

```sh
./tools/test.sh
PRIMORDIA_BACKEND=script ./tools/test.sh
python3 tests/test_launchers.py

# Explicit play trials; restart retains the command-line selection.
./tools/run.sh -- --particle-engine=liquidfun
./tools/run.sh -- --parcels=on

./tools/fluid_compare.sh current --chemicals=50000 --frames=120 --neighbor-metrics=off
./tools/fluid_compare.sh uniform --chemicals=50000 --frames=120 --neighbor-metrics=off
./tools/fluid_compare.sh liquidfun --chemicals=50000 --frames=120 --neighbor-metrics=off
./tools/fluid_compare.sh current --distribution=habitat --parcels=on --frames=120
```

Use `--physical-radius=2` or `--particle-iterations=2` for calibration, not an assumed speed/quality improvement. Keep collision, chemistry, density and geometry effects explicit. For the transport-only benchmark, run the discovered Godot executable with `--headless --path . --script tests/parcel_benchmark.gd -- --output=/tmp/parcels.json`.

## Next gates

1. Calibrate LiquidFun radius/pressure/transport response and reaction throughput; test conservative reuse of solver contacts only where it covers chemical encounters.
2. Couple deforming cell boundaries and cilia to a candidate solvent model, measuring equal/opposite momentum, drag, wakes and porous plants before replacing the current medium.
3. Schedule background work by compatible spatial/time cohorts, with bounded work and long-horizon feeding/chemistry checks. Current per-slot staggering limits parcel coverage.
4. Add true weighted parcels only with conserved material, momentum, cloud spread and heading distributions, biological refinement independent of zoom, split/merge hysteresis and bounded reconstruction.
5. Add Android/iOS ARM64 builds, full habitat serialization and elapsed-time offline ecology. Measure battery, thermal behavior and sustained density on real devices.

The present build uses portable C++ and 32-bit indices; it does not compile historical 32-bit ARM NEON assembly or deliver mobile exports. **50k at sustained 60 FPS, phone performance, weighted collision/reaction parcels and closed-app idle progress remain unproven or unimplemented.** Scientific motivation and abstractions are recorded in [references.md](../references.md).
