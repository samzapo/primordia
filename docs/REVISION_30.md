# Revision 30 — compare chemical neighbor searches

The existing grid remains the gameplay default. Packed indexing reduced index memory but showed no reliable frame-time improvement. This CPU BVH, quadtree and conservative neighbor caching were slower in fixed-horizon comparisons. They remain explicit diagnostic choices, with collisions, oriented reactions and normal density unchanged. This revision establishes measured alternatives; it does not achieve 50k particles at 60 FPS.

## Implemented comparison

- **Legacy grid:** the established 16-unit periodic bins, clearing occupied bins and retaining insertion order.
- **Packed grid:** count, prefix and scatter into contiguous per-bin ID ranges. Authoritative particle slots and stable handles are not reordered. This packs the index, not all hot particle fields.
- **BVH:** radius-expanded AABBs in a flat, Morton-sorted binary hierarchy, with eight-particle leaves and periodic image queries. Candidates are sorted back into the original x-major/y-minor bin traversal and insertion order before chemistry.
- **Quadtree:** a flat bucketed region tree, subdividing occupied quadrants only, with sixteen-particle leaves and at most ten subdivision levels. Nodes use their region bounds plus the largest contained radius. Periodic queries and restored contact order follow the same rules as the BVH.
- **Neighbor cache:** a two-unit Verlet skin, with reuse permitted only while each endpoint's displacement plus positive radius growth stays within half that margin. Changes in ordered identities, handles, membership or newly active particles invalidate reuse. Current species, orientation, acidity, alive/reacted state and velocities are read normally; none is cached as a reaction result. Coarse patches use fresh indices. A bounded cache falls back to ordinary search on overflow, rather than truncating interactions.

The cache works independently with each backend. Seam/bin crossing, compaction, re-import, birth, growth and activation have regression checks, including actual reuse in a quiet cloud. All contacts still use circular geometry; artwork never becomes a fork-shaped collider.

Two additional AABB experiments were rejected and removed: packing circle bounds before pair eligibility checks, and adding bounds checks after eligibility. Neither improved the measured workload. Their authored analysis and traces remain in private task records.

## Fixed-horizon measurements

Godot 4.7.2, Ryzen 9950X, RTX 5080, Mobile renderer, 1440×900, widest playable 80% view. All fixtures retain paid cilia, current fluid, visual effects and music preparation; audio uses the Dummy driver. Counter instrumentation is off in this table. Each run draws 120 frames with one 1/60-second tick per frame, advancing exactly two simulation seconds.

Values are **mean / p95 frame milliseconds**. These are fixed-tick throughput measurements, not live FPS.

| Initial fixture | Current grid | Packed grid | BVH | Packed + cache |
| --- | ---: | ---: | ---: | ---: |
| 20k uniform | 18.01 / 21.06 | 18.32 / 21.47 | 21.26 / 25.56 | 19.14 / 22.39 |
| 50k uniform | 31.60 / 45.47 | 31.38 / 46.38 | 39.89 / 60.10 | 34.93 / 51.84 |
| 50k clustered | 24.78 / 52.20 | 25.94 / 53.47 | 30.01 / 60.48 | 28.51 / 60.95 |
| 20k, large cell, mixed packet sizes | 18.26 / 22.63 | 18.25 / 22.50 | 22.97 / 29.25 | 19.24 / 23.54 |

A second uniform-50k grid pair, measured in reverse order, gave current **32.09 / 46.50** and packed **32.41 / 46.70**. The two-run mean averages are 31.85 and 31.90 ms: there is no demonstrated speed win.

All four backends/cache choices in each fixed fixture preserve identical final chemistry events, material, all three RNG states and pool metrics. Uniform 50k produces 30,972 merges and 299 decays, leaving 639.32362812373 units of packet material.

These are finite clouds that shrink: uniform 50k reaches a minimum observed 19,606 packets; clustered 50k reaches 7,594. They do not establish sustained 50k performance. The mixed-size fixture keeps 85% of each source packet in one copy and distributes its remaining material among smaller copies; amount, product and capacity remain finite. The large cell has about 231 units of radius at the final sample.

## Quadtree comparison

There was no technical restriction against a quadtree; the first comparison was scoped to grid/BVH. The owner's question prompted adding the 2D alternative to the same harness. This is one bucketed region implementation, not a conclusion about every quadtree or incremental/loose-tree design.

A new paired fixed-horizon pass, with counters off, gives:

| Initial fixture | Current grid mean / p95 ms | Quadtree mean / p95 ms |
| --- | ---: | ---: |
| 20k uniform | 18.49 / 23.57 | 20.33 / 23.63 |
| 50k uniform | 31.77 / 46.52 | 38.24 / 55.99 |
| 50k clustered | 24.96 / 52.06 | 32.83 / 89.39 |
| 20k, large cell, mixed packet sizes | 19.69 / 25.56 | 23.40 / 29.74 |

Exact fixed-horizon events, material, random states and pool metrics match the paired grid. The quadtree returns the same 10.98 million AABB candidates and 2.90 million contacts as the BVH, while allocating 2.03 MiB. A later instrumented pass measured 112.23 ms of construction and 870.40 ms of query/preparation/sorting. The concurrently sampled grid construction was 21.37 ms. These later timings were more variable than the earlier pass and are not mixed into the BVH table.

A reverse-order repeat, with before/after CPU samples above 99% idle and an idle GPU before launch, gave quadtree **36.03 / 54.14 ms** versus grid **31.31 / 45.19 ms** at uniform 50k. A repeated eight-second live pair gave quadtree **46.88 / 179.28 ms**, advancing 6.87 simulation seconds, versus grid **26.67 / 86.53 ms**, advancing 7.38 seconds.

An earlier quadtree live-50k pair was substantially more variable (206.87 ms mean versus grid 42.21 ms). It coincided with increased host activity; the raw evidence is retained but is not treated as a stable estimate of the quadtree penalty. The reverse-order repeat and fixed-horizon pairs still support retaining the grid. No other task was stopped or reconfigured.

Quadtree caching also had zero hits and 120 rebuilds. Its correctness checks include actual reuse in quiet clouds, but the live reactive workload did not repay that feature.

## Where the costs went

A separate instrumented uniform-50k pass reports:

| Search | Delivered candidates | Accepted contacts | Index allocation | Index construction, total |
| --- | ---: | ---: | ---: | ---: |
| Current grid | 87.38 million | 2.90 million | 1.26 MiB | 14.68 ms |
| Packed grid | 87.38 million | 2.90 million | 0.66 MiB | 16.37 ms |
| BVH | 10.98 million | 2.90 million | 1.64 MiB | 101.68 ms |

These totals cover 120 detailed and 20 coarse chemistry calls. The packed index uses about 48% less memory; this is index capacity, not total game memory. BVH candidate preparation, traversal and ordering cost another **1,074.27 ms** across the pass. Fewer candidates did not compensate for that work.

Packed caching had **zero hits and 120 foreground rebuilds**, with 583.71 ms spent constructing lists and 3.76 MiB of index/cache allocation. All accepted contacts still match. Global cache validity is too short-lived in this workload to repay construction. This does not prove that smaller regional caches, another skin, a different BVH or a GPU implementation would also lose.

Diagnostics report index builds, cache hits/misses/overflow, candidates, owned candidates, contacts, allocation and construction/search/sort times. Grid walking and physical/reaction work remain combined in the chemistry phase; the zero grid search/sort value does not mean grid queries are free. Cache construction includes its internal search/sort time, so those timer fields must not be added together. Cache candidate totals include list construction as well as encounter delivery. Instrumentation is off in ordinary gameplay.

## Live frames

Eight-second wall-clock runs use real catch-up, with instrumentation off:

| Initial particles | Search | Mean / p95 ms | Simulation seconds |
| --- | --- | ---: | ---: |
| 20k | Current grid | 10.42 / 19.70 | 8.00 |
| 20k | Packed grid | 10.49 / 19.23 | 8.00 |
| 20k | BVH | 15.22 / 30.39 | 8.00 |
| 20k | Packed + cache | 11.01 / 19.87 | 7.98 |
| 50k | Current grid | 24.70 / 59.73 | 7.38 |
| 50k | Packed grid | 26.68 / 76.16 | 7.35 |
| 50k | BVH | 58.09 / 210.91 | 6.60 |
| 50k | Packed + cache | 35.91 / 142.02 | 7.05 |

The 50k current-grid run has ten frames with eight catch-up ticks; BVH has eighteen. These live runs advance different amounts of simulation, so their final inventories cannot be compared as equal-horizon chemistry tests. Even the faster 20k runs exceed the p95 60 FPS budget and shrink to much smaller inventories.

This shared workstation is substantially different from the owner's RTX 3090 / Threadripper 2990WX machine. Short paired measurements do not establish long-session pacing or performance on that Steam installation. Cross-revision timing differences are not attributed to this change.

## Validation and reproduction

**Native: 7,541 assertions, zero failures. Independent script: 3,288 assertions, zero failures.** Script-only profiler smoke and final editor import pass.

Native and independent script suites cover shared biology, finite accounting, original contact arithmetic and all RNG streams. New checks compare every search/cache configuration against the baseline through dense mixed-species/radius seam encounters and full ecology, including membrane exclusion, coarse progress and identity mutations. Editor import and whitespace checks pass.

```sh
./tools/test.sh
PRIMORDIA_BACKEND=script ./tools/test.sh

# Steam discovery remains the default; use the same output/display conditions.
./tools/fluid_compare.sh current --chemicals=50000 --frames=120 --neighbors=legacy --neighbor-metrics=off --output=/tmp/primordia-grid.json
./tools/fluid_compare.sh current --chemicals=50000 --frames=120 --neighbors=packed --neighbor-metrics=off --output=/tmp/primordia-packed.json
./tools/fluid_compare.sh current --chemicals=50000 --frames=120 --neighbors=bvh --neighbor-metrics=off --output=/tmp/primordia-bvh.json
python3 tools/fluid_report.py /tmp/primordia-grid.json /tmp/primordia-packed.json /tmp/primordia-bvh.json
```

Use `--neighbors=quadtree` for the 2D tree, `--neighbor-cache=on` independently, `--neighbor-metrics=on` for counters, `--distribution=clustered`, or `--fixture=growth --particle-sizes=mixed`. Use `--frame-step=live --seconds=8` for live catch-up. The script backend retains default profiling; packed/BVH/quadtree/cache selections require native kernels.

The next useful target is batching hot particle fields and transport/contact arithmetic, while measuring rendering and synchronization too. Index construction already costs little in the current grid; replacing it alone does not remove the remaining work. [references.md](../references.md) retains the motivation and limits of conservative neighbor searches.
