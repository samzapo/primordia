# Revision 36 — cell exchange and whole-game matching evaluation

## Decision

Retain the existing engine as the default. The GPU kernel results remain promising, but a complete GPU game port has not demonstrated a substantial improvement with equivalent mechanics. The complete-game CPU mutual-matching comparison improves these short rendered workloads only modestly. The owner's authorization to migrate autonomously if the full result justifies it is retained; no further approval is needed for that evaluated migration.

The GPU cell exchange and CPU matching comparison are implemented and available for continued measurement. Neither raises normal particle density.

## GPU cell exchange

The resident diagnostic accepts actual Cell objects as immutable request snapshots. It uploads their visible and physical membrane contours, placement, shared remaining gut/oxygen/carbon capacities and pore locations.

- Nutrient pores share one gut capacity per body. Overlapping pores and competing cells consume the actual finite packet remainder, in request order.
- Oxygen uses physical membrane support plus the existing 14-unit margin. Photosynthesis carbon uses extent plus 18; nutrient pores retain their existing radius plus 8.
- Three projection passes shunt non-pheromone particles to the deformed visible outline plus 7. They retain material and use periodic coordinates. These are the game's existing visual exclusion rules, not a new hydrodynamic contact solver.
- A bounded emission request supplies already-paid material. Acceptance returns a slot/generation handle; refusal leaves the caller's material in escrow. The bridge itself does not debit a living cell or refund escrow automatically.
- Sparse inspection returns at most 32 requested slots. Generation changes on reuse invalidate stale handles. Dead handles resolve invalid, whole-pool uploads are forbidden after exchange ownership, and exhausted signed generations are not reused.
- Receipts contain intake, per-request consumption, emission acceptance and inspections. They do not export the particle pool. Only one exchange may be outstanding; each serial must be credited once by its caller.
- Close waits for outstanding receipts, including a receipt callback that submits another transaction before requesting close.

Configuration is explicit: configure_interactions("chemistry"), configure_exchange(), then initialize(). exchange(cells, emissions, handles, asynchronous) returns whether the request was accepted for processing and emits exchange_ready with its receipt. It does not mutate the supplied Cell objects. The benchmark credits actual receipts before submitting another snapshot.

Limits are 64 bodies, 256 feeding requests, 256 emissions, 8,960 contour vertices and 32 inspections per exchange. Oversized or invalid requests are rejected before GPU work. Initial owner IDs are unknown (-1); accepted emissions carry their owner. Product reserves are explicitly unsupported. General owner/lineage/pheromone-report import, toxin/decoy exposure, perception, unary chemistry, dynamic acidity and the full live-game bridge remain pending. Positive residual material is retained rather than discarded as sub-micro-unit dust.

The feeding/emission transaction is ordered on the GPU; membrane projection is parallel. Feeding reuses the current periodic grid after particle motion/chemistry; projection, emission and whole-state uploads invalidate it. A fresh grid is built only when required. This is a correctness baseline, not the final parallel body-budget solver.

## Exchange benchmark

Godot 4.7.2 Mobile/Vulkan, RTX 5080, Ryzen 9950X, hardware-rendered headless Weston. Thirty completed steps after one warmup, 50,000 starting slots, eight actual cell objects, one 141-unit membrane radius, paid fixture emissions. The cells are resource consumers, not a full autonomous ecosystem or rendered cell scene. Counts shrink through chemistry.

| Distribution | Immediate receipt, completed step | Async receipt, completed step |
|---|---:|---:|
| Uniform | 4.16 ms | 50.12 ms |
| Clustered | 10.07 ms | 50.10 ms |

These final values follow removal of a redundant grid build. The earlier immediate results were 4.49/10.45 ms. Both paths upload 10,752 bytes and return 640 bytes per step in this fixture. All 2.4 emitted material units are accepted; no capacity refusals occur in this benchmark. The separate capacity test verifies refusal and retained originals.

The asynchronous test waits for each receipt before advancing dependent cell state. Its approximately 50 ms is round-trip dependency latency, not GPU kernel time. Immediate readback blocks the GPU/CPU boundary; asynchronous delivery does not remove the dependency by itself. A production design needs explicit reservations or GPU-owned cell resource accounts before it can safely overlap these operations. Merely crediting stale intake or silently skipping updates is not an optimization.

## Complete-game CPU mutual matching

A numeric native implementation ports the same two-pass principle into the current game, retaining ordinary CPU feeding, sensing, emissions, biology and rendering:

1. Existing ordered unary decay and acid/buffer field updates run first.
2. Workers evaluate compatible neighbors against immutable state, accumulate collision impulses and choose symmetric alignment ranks with tick-dependent tie-breaking.
3. Disjoint pairs commit in parallel. Event totals and bounded visual/music cues publish afterward on the submitting thread.

Both partners must have positive elapsed chemistry time and activity. Products wait for the next update; stable particle handles seed ranking across compaction. Collision impulses include reacting contacts. These choices intentionally change the old sequential chemistry trajectory and random draw consumption. Exact equality to ordered gameplay is not claimed. Within matching, one and eight lanes have identical packets, cell states, acidity and event totals in the four full-simulation fixtures.

Default remains ordered. Matching requires native pool ownership and the existing grid without neighbor caching or LiquidFun. Unsupported kernel diagnostics use the ordered path; the frame profiler rejects incompatible requested combinations. Duplicate IDs trigger a complete ordered fallback. Per-mode job/fallback counters identify actual use.

For an explicit interactive comparison with the usual Steam-discovering launcher:

~~~sh
PRIMORDIA_PAIR_MATCHING=1 ./tools/run.sh
~~~

For rendered comparisons:

~~~sh
./tools/fluid_compare.sh current --chemicals=50000 --frames=120 --frame-step=fixed --neighbor-metrics=off --pair-matching=on --output=/tmp/primordia-matching.json
~~~

Omit the environment variable or use --pair-matching=off for the existing method.

## Rendered measurements

Full game, 1440 by 900, 80% view, music/bloom/wakes enabled, hardware-rendered headless Weston and Dummy audio. Each capture has 120 frames and exactly two simulated seconds; these are whole-frame intervals, not GPU kernel timings. Uniform runs use ordered then matching; clustered runs reverse that order.

| Initial workload | Ordered mean / p95 | Matching mean / p95 |
|---|---:|---:|
| 50k uniform | 27.85 / 43.37 ms | 27.00 / 37.92 ms |
| 50k clustered | 21.05 / 44.37 ms | 20.57 / 41.29 ms |
| 20k mixed sizes, large cell | 16.14 / 19.75 ms | 15.90 / 19.79 ms |

Mean savings are about 3.1%, 2.3% and 1.5%; the large-cell p95 is slightly worse. End counts differ (18,672 versus 18,514 uniform; 7,270 versus 7,225 clustered), because matching changes chemistry and ecology. These are short single paired captures with no confidence interval. They do not establish sustained 50k, 60 FPS, a GPU-game speedup or phone performance.

Separate CPU-only, rotating-order comparisons cover 50k uniform/clustered, 20k mixed sizes with a large cell, and 5k particles. Their lane-parity assertions are correctness evidence; they exclude drawing and must not be reported as FPS. A first exploratory CPU pass overlapped the script regression suite and is not used as an uncontended performance claim.

## Validation

- 296 GPU exchange assertions: finite shared budgets, native intake agreement, periodic deformed outline projection, pheromone exemption, refused emissions, generation reuse, sparse owner inspection and close during asynchronous readback.
- 3,340 GPU reaction assertions and six existing GPU/native transport comparisons.
- Four seeded closed-ecosystem matching checks account for feeding, damage, death, repair, recycling and recorded losses.
- 96 new native pair assertions compare species, alive state, material and charge against legacy outcomes for isolated transformations across order/acidity cases.
- 69,807 native regression assertions, 3,294 script-fallback assertions, 11 launcher tests, imported source and generated portable export manifest are checked separately.

Android export, the Pixel 9 Pro XL, Samsung Galaxy Z Flip7, iOS and sustained thermal behavior are still untested. No device is accessible from this task.

## References and next gate

Godot documents that asynchronous buffer readbacks arrive after a number of frames, whereas immediate readback blocks work: [RenderingDevice buffer readback](https://docs.godotengine.org/en/4.4/classes/class_renderingdevice.html#class-renderingdevice-method-buffer-get-data-async). The test here measures that architectural consequence directly.

The next GPU migration gate is a coherent resource/sensing exchange without per-step dependent readback, plus the remaining chemistry and ownership metadata. Require equivalent whole-game workloads and material/latency checks before changing the default. CPU matching is retained as a reference and opt-in experiment, not promoted on a small timing difference.
