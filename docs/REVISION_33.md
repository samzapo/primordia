# Revision 33 — eight-thread particle simulation

The native simulation has an eight-lane budget: seven persistent workers plus the submitting thread. Small jobs stay serial. Workers sleep between jobs; multiple kernel instances share one pool. Godot's own rendering/audio threads are outside this simulation budget.

## Pipeline and preserved behavior

1. The submitting thread selects transport jobs and generates x/y/angular random draws in exactly the existing packet order. Workers apply independent advection, diffusion, velocity decay and orientation updates. Array storage is detached/reserved before dispatch; workers neither call engine APIs nor resize shared storage. A barrier completes all particle writes before grid updates or chemistry.
2. Chemistry scratch contains numeric fields and a pointer to cold metadata; it no longer constructs or copies a Dictionary per candidate. Actual metadata stays owned by the particle pool or a separate compatibility array.
3. Workers screen circular contacts against the immutable legacy grid. Each packet retains a bounded, ordered list of geometrically possible partners. The original main-thread loop still performs decay, acidity changes, reaction eligibility, sequential impulses, consumption, event cues and resource changes. A prior reaction can therefore still invalidate a later candidate exactly as before.
4. A list exceeding 128 entries falls back to the full original ordered query. This is a memory/work bound, not a dropped-contact limit. Duplicate diagnostic transport IDs fall back before any RNG draw or mutation. LiquidFun/parcels transport and alternative or instrumented neighbor backends retain their existing serial paths.

Both parallel stages require at least 4,096 input entries. Threads can be set from one through eight for diagnostics. Parallel screening deliberately does not reorder, graph-color or simultaneously commit reactions. It is not a new chemical model or a SIMD contact solver. Pheromone transport remains contact-free, and all finite material, metadata, family rules and camera behavior are retained.

An additional structure-of-arrays geometry copy was evaluated independently. It did not produce a convincing saving and remains an explicit diagnostic, off by default. The useful cold-metadata separation is retained. There is no claim that the entire authoritative packet pool has migrated to a new structure-of-arrays layout.

## Reproduce

```sh
./tools/test.sh
PRIMORDIA_BACKEND=script ./tools/test.sh
./tools/fluid_compare.sh current --threads=1 --neighbor-metrics=off --chemicals=50000 --frames=120 --output=/tmp/serial.json
./tools/fluid_compare.sh current --threads=8 --neighbor-metrics=off --chemicals=50000 --frames=120 --output=/tmp/parallel.json
```

Use `--parallel-transport=off` or `--parallel-contacts=off` for independent ablations, and `--compact-geometry=on` for the geometry-copy trial. `--neighbor-metrics=on` preserves the original detailed counter traversal and therefore disables parallel screening; it does not disable parallel transport. The profiler exports actual dispatch/fallback counts. `tests/thread_benchmark.gd` compares complete CPU simulation ticks in one process, rotating backend order each tick and checking exact outcomes; it is not rendered FPS.

## Compiler experiments

The native build supports explicit `PRIMORDIA_NATIVE_OPT=baseline|lto|pgo-generate|pgo-use` modes. The launcher tracks the mode so a cached experimental library cannot silently become the ordinary build. PGO requires GCC, atomic training counters for worker safety, and locally generated profiles; missing/stale compiler coverage fails explicitly. No fast-math or host-specific instruction-set flags are added. Libraries, profiles and dependency output stay ignored.

## GPU investigation

The existing GPU fluid prototype still synchronizes each solver batch and reads back the field and cell forces before CPU simulation continues (`scripts/fluid_compare.gd`). Making particle motion alone asynchronous cannot remove that dependency. A fully resident pipeline would need authoritative particle storage, spatial indexing, circular screening, ordered conflict resolution, finite feeding/lysis transactions and rendering on the same device, with coherent cell feedback. Merely delaying the readback changes which state feeding sees.

This revision implements the CPU pipeline and compiler experiments; it does not implement that GPU migration. The existing pressure/body feedback and PBF boundary-density validation gaps remain. The safe next GPU experiment is resident geometric screening with measured transfer/synchronization cost, before considering GPU reaction commits. Existing diagnostic GPU engines remain unpromoted.

## Technical references

- [Godot thread-safe APIs](https://docs.godotengine.org/en/stable/tutorials/performance/thread_safe_apis.html): scene/resource operations have thread restrictions. Primordia confines workers to native numeric data and joins before publication.
- [Box2D SIMD and independent contact work](https://box2d.org/posts/2024/08/simd-matters/): motivates separating independent calculations from conflicting writes. Primordia keeps its existing sequential reaction commit instead of adopting graph-colored solver semantics.
- [GCC optimization options](https://gcc.gnu.org/onlinedocs/gcc/Optimize-Options.html): basis for the explicit LTO/PGO build trials.
- [Godot compute shaders](https://docs.godotengine.org/en/stable/tutorials/shaders/compute_shaders.html): synchronization waits can erase gains from offloading a small isolated stage.

## CPU simulation measurements

Godot 4.7.2, Ryzen 9950X. Each backend runs 120 complete simulation ticks in one process, with execution order rotated every tick. Fixtures split finite cell-produced inventory and use the 80% activity footprint. These are CPU tick times, not rendered FPS; particle populations shrink normally. All configurations finish with identical particle fields, cell physiology, acidity, reactions and three RNG streams.

| Fixture | One lane mean / p95 ms | Eight lanes mean / p95 ms |
| --- | ---: | ---: |
| Initial 50k uniform | 24.03 / 42.33 | 18.94 / 33.52 |
| Initial 50k clustered | 18.86 / 47.90 | 16.12 / 39.73 |
| Initial 20k, large cell / mixed packet sizes | 12.55 / 17.86 | 11.19 / 15.82 |
| Initial 5k | 5.49 / 7.22 | 5.25 / 6.76 |

Uniform 50k means at 1/2/4/8 lanes are **24.03 / 22.19 / 20.09 / 18.94 ms**, a 21% reduction from serial to eight. Transport-only and screening-only parallelism measure **21.55** and **21.31 ms**. The numeric geometry-copy trial measures 18.94 ms enabled versus **18.72 ms disabled**, which does not justify retaining the copy by default. Other rows in this exploratory table have the copy enabled; final default-rendered confirmation follows below.

The same rotating CPU benchmark with LTO measures uniform 50k serial/eight-lane means of **23.77 / 18.22 ms**; PGO+LTO measures **23.19 / 18.64 ms**. PGO is not consistently better than LTO across uniform, clustered, grown and small fixtures. Separate compiler runs also see shared-load variation. Both remain explicit experiments; the ordinary build retains baseline compiler settings. Correctly built LTO and PGO rendered captures match baseline material/events/RNG/biomass endpoints. Instrumented training time is excluded from performance claims.

## Final rendered confirmation

Final defaults: eight lanes, geometry copy off, baseline compiler. Godot 4.7.2 Mobile renderer, RTX 5080 / Ryzen 9950X, 1440×900 headless Wayland GL output, 80% zoom, Dummy audio. Fixed captures run 120 frames at 1/60 simulation seconds each. All fixed pairs match material, reaction events, three RNG streams, player biomass/radius and simulation horizon exactly. The separate CPU harness verifies full packet/cell equality.

| Fixture | One lane mean / p95 frame ms | Eight lanes mean / p95 frame ms |
| --- | ---: | ---: |
| Initial 50k uniform, first pair | 28.73 / 41.41 | 24.67 / 35.47 |
| Initial 50k uniform, reversed-order pair | 28.29 / 43.64 | 24.98 / 37.51 |
| Initial 20k uniform | 19.25 / 39.70 | 16.71 / 21.70 |
| Initial 50k clustered | 23.14 / 49.10 | 21.10 / 43.65 |
| Initial 20k, large cell / mixed sizes | 16.97 / 21.32 | 16.56 / 20.01 |
| Initial 20k, music muted | 16.64 / 19.47 | 15.63 / 18.82 |

The repeated uniform 50k runs average approximately **13% lower frame time**; their simulation phase falls from roughly 19.0 to 15.4 ms. Both parallel stages dispatched on every fixed tick. The clustered fixture exercised one full serial overflow fallback. Pool mirror writes and exports stayed zero.

These are finite-inventory fixtures, not sustained-density claims: uniform 50k ends at 19,794 packets; clustered 50k ends at 7,787; uniform 20k ends at 13,208. Shared host activity caused substantial variance in earlier exploratory captures, including regressions in some configurations. The repeated final pair and rotating CPU benchmark support the retained optimization, but owner hardware and phones remain untested.

An eight-second live 20k run measures serial/eight-lane mean frame times of 6.68/5.80 ms and p95 of 15.90/14.84 ms. Many rendered frames contain no simulation tick, so these numbers cannot be compared directly with fixed-step timings. Live endpoints differ slightly in elapsed simulation time and are not used for equivalence. Neither this run nor the fixed captures establishes sustained 50k at 60 FPS.

## Validation

- Native suite: **69,693 assertions, zero failures**.
- Script fallback: **3,291 assertions, zero failures**.
- Launcher checks: **10 passed**.
- Standalone worker scheduler passed ThreadSanitizer, including repeated ranges, concurrent submissions and shutdown. This is not a full-engine race-detector run.
- Godot editor import and whitespace checks passed.

New regression coverage includes 1/2/4/8 lanes and independent-stage configurations, dense contact overflow, wraparound contacts, duplicate transport IDs, coarse timestamps, copy-on-write position snapshots, and exact particle/cell/RNG outcomes through camera transitions.
