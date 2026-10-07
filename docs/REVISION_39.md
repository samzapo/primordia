# Revision 39 — playable desktop resident particles

The complete game can now run with authoritative GPU particles, mutual-best reactions, and the existing CPU cell biology and finite-mass fluid. This is an **explicit desktop playtest backend**. Ordinary Steam launches retain the established CPU backend.

## Launch and compare

~~~sh
./tools/playtest.sh resident
./tools/playtest.sh cpu-matching
./tools/playtest.sh cpu
~~~

The first is also the default for tools/playtest.sh. All three preserve Steam Godot discovery and the native build recipe, and use the Mobile renderer. CPU matching enables native mutual-best reactions; CPU retains ordered chemistry. The ordinary tools/run.sh launch keeps Compatibility rendering.

F3 identifies **Resident GPU** while active. Tab, cell-local editing, settings, music, inspection, and family succession retain their controls. Initialization pauses gameplay; restart cancels stale callbacks and closes old device resources.

Normal starting density and cell-only particle sources are unchanged. The 50k fixtures below split existing finite material; they are not an extra gameplay source of food.

## Complete coupling

- The GPU owns chemical position, velocity, orientation, species, amount, charge, generation handles, and immutable emitted reports. CPU particle dictionaries remain empty; one MultiMesh reads the resident texture directly.
- Transport follows the changing 64×40 fluid field, random-walk diffusion, and soft circular collisions. Orientation controls binding and drawing, never noncircular collision geometry.
- Spatial acidity, finite acid/buffer exchange, probabilistic unary decay, and one-round mutual-best reactions now run on the pool. Products wait until the next update before another pair reaction. Receipts account for decay losses and recycled material.
- Grazing patches, hunting, flight, and secretion-demand queries inspect actual local packets. Hunting uses only emitted pheromones and excludes family; neutralizers ignore family toxins.
- The CPU cleans receptors, queries, delivers signals using pre-feeding mass, credits intake once, and runs shared photosynthesis, metabolism, upkeep, repair, membrane, and secretion functions. Existing CPU movement, cell/spike/plant contacts, evolution, and succession remain authoritative.
- Toxins and correctly oriented decoys nominate one recipient. Overlapping cells cannot consume a packet twice. More than 128 toxin contacts on a body are drained through additional receipts **before** exclusion.
- Paid emissions remain escrowed until accepted, including multi-batch lysis. Sub-float photosynthetic remainders accumulate without creating a minimum dose or discarding material.
- Bounded reaction sparks, feeding/neutralization music cues, and sparse particle picking/tracking operate without full downloads. Inspection preserves cell-adjacent suppression, zoom-dependent hit areas, generation safety, and immutable pheromone tooltips. It does not advance ecology.

The desktop resident path advances the **whole habitat** at detailed cadence: every living cell, fluid node, and particle. There is no offscreen biological freeze or resource multiplier. Recruitment uses a fixed footprint independent of display zoom/pan. CPU play retains its existing detailed/coarse ecology. Future phone coarsening must retain finite accounting.

Compact synchronous receipts deliberately avoid the previous dependent asynchronous path's queued-frame latency. Cells spend completed intake, never stale or invented reserves.

## Desktop measurements

Godot 4.7.2, Ryzen 9 9950X, RTX 5080, Vulkan Mobile, 1440×900, **80% playable zoom**, through a task-owned hardware-rendered Weston output. Synthesis/mixing runs with Dummy audio output. These results do not establish RTX 3090, phone, thermal, or battery performance. The compositor lacks FIFO frame pacing; frame intervals include scheduling/presentation jitter.

Live tests cap rendering at 60 FPS and aggregate all catch-up ticks. Initialization/music-bank warmup and the first five recorded frame intervals are excluded from timing statistics. Each is one exploratory run, not a confidence interval.

| Resident workload | Duration | Mean FPS | p95 frame interval | Final particles |
| --- | ---: | ---: | ---: | ---: |
| Ordinary population, music on | 60 s | 60.0 | 17.85 ms | 4,245 |
| 50k habitat-wide start, music on | 12 s | 60.0 | 18.30 ms | 36,166 |
| 50k clustered start, music on | 12 s | 59.4 | 18.28 ms | 3,718 |
| 50k clustered start, music off | 12 s | 60.1 | 18.15 ms | 3,716 |
| Large cell, approximately 231-unit radius | 10 s | 60.0 | 17.75 ms | 3,818 |

The minute-long run advanced 59.93 simulated seconds during 59.93 measured wall seconds, with sixteen cells, no audio underruns, and **zero full-pool readbacks**. A separate uncapped clustered start also stayed resident for 20 seconds. The harness now rejects CPU fallback as a GPU result.

Ordinary CPU and CPU matching clustered starts averaged 57.4 and 58.2 FPS, with p95 intervals of 19.02 and 18.88 ms. Those CPU runs use cheaper offscreen ecology and produce different populations; these frame averages are not an equal-work speedup ratio.

A separate equal-horizon comparison runs 120 detailed steps over the whole habitat for both backends, starting with 50k:

| Distribution | Native CPU matching mean / p95 tick | Resident mean / p95 tick | Final CPU / GPU particles |
| --- | ---: | ---: | ---: |
| Clustered | 16.71 / 36.29 ms | 10.25 / 12.61 ms | 7,962 / 6,731 |
| Habitat-wide | 25.07 / 26.47 ms | 10.02 / 11.27 ms | 46,710 / 45,969 |

These are completed **simulation-step timings, not FPS**, including cell sensing, feeding, physiology, membranes, movement, and contacts. Resident mean time is approximately 39% lower for the clustered start and 60% lower for the habitat-wide start. Random streams, floating-point precision, and pair decisions differ; the displayed final counts rule out claiming exact trajectory equivalence.

Dense clusters merge quickly. These tests do **not** demonstrate sustained 50k live particles or justify silently multiplying normal density.

## Bounds and fallback

The playtest allocates 65,536 slots. Existing limits remain: 64 cells, 256 feeding/query/emission requests per batch, 8,960 outline points, and 1,024 distinct pheromone source IDs over a pool's lifetime. Larger emission queues span consecutive batches. Live-slot compaction and source-table retirement remain future work.

Unsupported initialization keeps the untouched CPU world. A capacity/transaction refusal during play performs one explicit particle/metadata export, combines it with all refused and trace emissions, and resumes CPU ownership in the same habitat. A notification and F3 identify the change. This is not a reset or a performance result. A computer without Vulkan can use the ordinary Compatibility launcher.

GPU quantities use float32, and counter-based noise plus parallel matching differ from the ordered CPU random stream. This is not cross-platform determinism or calibrated molecular kinetics. Long-run ecological balance still needs human playtesting.

## Validation

- **69,807 native + 3,294 script assertions passed.**
- **6,784 GPU/UI checks:** environment 48, exposure/lens geometry 16, full gameplay/accounting 1,474, perception 372, exchange 296, queue reservations 1,111, matching 3,340, radix grid 114, actual Pond editing/restart 13.
- **13 launcher fixtures** and repository/portable benchmark imports passed. Phone packaging retains the new shader/module dependencies; this is not phone execution evidence.
- Camera cycling reproduces ATP, material, movement, chemistry, random stream, and progression. Four-second whole-habitat material error, including reserves and recorded losses, was approximately 0.0000165 units.
- Coverage includes family-safe exposure, oriented blockage, overlapping bodies, overflow draining, paused editing, paid cilia placement/recycling, lysis/prepaid succession, capacity fallback, trace emission escrow, sparse tracking, and initialization cancellation.
- Build-mode and large-cell renders were inspected for oriented glyphs, membrane shape, cell-local controls, and unobscured anatomy.

Run tools/test.sh for CPU regressions. The tests/resident_*_gpu.gd suites need a real Mobile/Forward+ RenderingDevice. tests/frame_profile.gd accepts --particle-backend=resident, --fps-limit=60, and diagnostic --full-habitat=on for CPU comparisons. Existing density, distribution, growth, music, and equal-horizon options remain.

Phone export/performance, sustained high populations, source-table reuse, longer ecological balance tests, and further handoff optimization remain follow-up work. They do not prevent this desktop playtest.
