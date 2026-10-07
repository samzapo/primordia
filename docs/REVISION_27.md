# Revision 27 — native-owned particles

Ordinary native gameplay now owns particle motion, material, chemistry and render poses in a persistent C++ pool. Transport and chemistry no longer import or publish every packet through Godot dictionaries each tick. Feeding, sensing, secretion checks, toxin/decoy contact, offscreen exposure and grid maintenance read the same native state.

This is a CPU ownership migration. It does not add GPU chemistry, change fluid physics, increase normal density, or change resource, sensing or reaction rules.

## Ownership and exchange

`Simulation.enable_particle_pool()` imports initialization/fixture records once, empties the public `particles` and `pheromones` arrays and attaches the spatial wrapper to the pool. Pond enables it by default, including on ordinary restart. Standalone simulation fixtures retain the explicit dictionary interface until enabled, so tests can prepare controlled initial conditions.

New cell products enter through small emission records. Subsequent emission metadata/capacity corrections update just those new records. Hot state stays numeric; source ownership, product bookkeeping and immutable pheromone reports remain sparse metadata. Grazing queries return ordered food-bin masses/moments; hunting and flight queries return received emission snapshots, never live source-cell facts. Script anatomy still chooses among those inputs. Feeding/exposure consumes the actual finite pool packets.

`particle_count()`, native grid rebuild/update/filter, expiry and stable-order compaction avoid pose snapshots. Rendering reads resident poses directly and still recalculates interpolation and projection around current deformed membranes. The old scoped dictionary pipeline/cache remains available for differential testing.

`particle_snapshot(index)`, `particle_snapshots()` and `pool_resolve(handle)` are explicit inspection/debug exports. Native snapshots are detached. Monotonic handles survive slot compaction and are retired when their packet disappears; new imports/emissions cannot reuse a stale handle. The real lens resolves both the handle and current slot, follows orientation/species changes, and retains cell-adjacent suppression. Native picking filters local poses before exporting possible cursor hits.

`disable_particle_pool()` exports current records once and restores the dictionary/grid backend. Unsupported diagnostic switches trigger that transition before the next tick. Prepare direct dictionary fixtures before enabling ownership, or explicitly disable it before editing them; mutating the empty public array is not a native particle edit. GPU transport and legacy solid-packet plant tests stay on dictionaries. Paused scenes read current native poses without stale dictionary mirrors.

Reports expose pool imports, snapshot exports, consumer batches and slot capacity. `numeric_capacity_bytes` is the allocated slot-vector footprint, including compatibility fields, not total process memory: metadata heaps, indices, render batches and engine allocations are additional. The mirror-write value is zero by construction while native ownership is enabled, unavailable when it is disabled. Tests independently verify empty mirror arrays, unchanged export counts during ordinary ticks, and imports matching initialization plus actual emissions.

## Matched whole-frame benchmarks

Godot 4.7.2, Ryzen 9950X / RTX 5080, NVIDIA GPU-rendered Wayland headless compositor, Mobile renderer, 1440×900, 80% widest playable view. Music, bloom, streamers, wakes and reaction sparks remain enabled unless named otherwise. This is a real GPU display path with a virtual output and Dummy audio, not an owner's desktop or speaker playtest. The RTX 3090 / Threadripper 2990WX Steam machine remains untested.

The baseline disables only `pool`, retaining the Revision 26 numeric handoff/render cache. Each fixed trace runs 120 displayed frames with one 1/60-second tick per frame: exactly two simulated seconds. The 20k comparison pools two trials per backend in reversed order; the other fixtures have one matched pair. These are whole-frame intervals, including simulation, synchronization, geometry, drawing and music. Fixed-step throughput is not live FPS.

| Initial chemical packets / fixture | Dictionary mean / p95 ms | Native pool mean / p95 ms |
| --- | ---: | ---: |
| 20,000 uniform, two trials each | 57.97 / 70.33 | 19.87 / 23.47 |
| 50,000 uniform | 126.89 / 195.98 | 38.25 / 56.75 |
| 100,000 uniform | 214.53 / 419.26 | 70.52 / 136.78 |
| 20,000 clustered | 36.68 / 72.74 | 16.35 / 26.08 |
| 20,000, large player | 49.46 / 68.74 | 19.10 / 23.37 |
| 20,000, nearby hunters + paid cilia | 66.41 / 79.66 | 26.28 / 29.88 |
| 20,000 uniform, muted | 57.38 / 69.88 | 19.68 / 23.16 |

The earlier repeated 20k mean improves **65.7%**. Its complete tick mean drops **46.01 → 13.30 ms**; transport **19.52 → 2.92**, chemistry **12.83 → 5.37**, publication **2.36 → 0.00055**, exclusion **5.14 → 1.17**, sensing **0.91 → 0.40**, and particle visual synchronization **2.38 → 1.44 ms**. These phases are nested; do not add them to the whole-frame total. The audio pair shows the pool gain survives muting, but one pair does not establish a reliable causal audio percentage.

All eight fixed pairs exactly match their final three random states, chemical event totals, packet material, player biomass and simulation horizon. Pool runs export **zero** packet snapshots during these fixed captures; imports cover initial inventory plus new cell products. Cluster, growth and contact fixtures retain actual chemistry/material and the existing shared biological rules.

Counts are initial-resolution fixtures, not sustained densities. In the uniform pool traces, active packets fall from 20k → about 12k, 50k → about 17k and 100k → about 20k during aggregation/absorption/decay. Controlled splitting preserves the fixture's finite species/material/capacity inventory; no new gameplay particle source was introduced.

## Final source confirmation

After the last metadata, diagnostic-query and toxin-debit corrections, two reversed-order 20k trials per backend measure **71.34 / 86.03 ms** mean/p95 on dictionaries versus **23.47 / 29.32 ms** in the pool: **67.1% less mean frame time**. Transport is **22.29 → 3.49 ms**, chemistry **15.03 → 6.19**, publication **3.86 → 0.0011**, exclusion **7.76 → 1.26**, sensing **1.20 → 0.47**, and particle synchronization **3.25 → 1.56 ms**. Final hunters/paid-cilia means/p95 are **79.56 / 94.20 → 33.84 / 39.17 ms**.

All three final-source fixed pairs retain exact material, biomass, chemical-event and random-state endpoints. The shared host grew busier; both backends slowed compared with the earlier captures, while the relative saving remained similar. Keep the earlier full density matrix distinct from these final source measurements.

## Live catch-up

Live tests use the engine's ordinary 60 Hz physics scheduling, with every catch-up tick included in frame timing.

- Ordinary inventory over eight wall seconds: dictionary mean/p95 **2.19 / 7.61 ms**, pool **1.93 / 6.44 ms**; 480 versus 479 ticks. These unlocked traces contain many zero-tick display frames.
- Initial 20k, eight-second request: dictionary **237.97 / 433.12 ms**, 236 ticks / **3.93 simulated seconds** in **8.09 wall seconds**, including **29 eight-tick frames**. Pool **11.40 / 20.86 ms**, 480 ticks / **8.00 simulated seconds** in **8.00 wall seconds**, with **zero eight-tick frames** and at most four ticks in a frame.
- Initial 50k, three-second request: dictionary **594.83 / 1337.88 ms**, 25 ticks / **0.42 simulated seconds** in **4.16 wall seconds**. Pool **169.62 / 352.25 ms**, 109 ticks / **1.82 simulated seconds** in **3.05 wall seconds**. Both still fall behind; slow frames can overrun the requested wall duration.

The earlier live 20k trace includes **1,298 local inspection snapshots** as the cursor finds/tracks nearby packets, compared with 22,212 total imported initialization/emission records. These are on-demand reads, not whole-pool mirrors, and their cost is included in inspection/whole-frame timing. Over its eight simulated seconds, stored packets shrink to roughly 8k. Live backends therefore have different ecological horizons/densities; their endpoints are not presented as matching.

A final-source 20k live confirmation records dictionary **378.30 / 549.62 ms**, **2.48 simulated seconds** in **8.32 wall seconds** with **18 eight-tick frames**; pool **25.67 / 60.37 ms**, **7.97 simulated seconds** in **8.01 wall seconds**, including **six eight-tick frames**. It exports **616** local inspection snapshots. This nearly keeps up with simulated time, but still has visible stalls under the increased shared load.

The earlier 20k run advances in real time, but its p95 exceeds the 16.67 ms frame budget and the population shrinks. **Sustained 20k at 60 FPS remains unproven; 50k live still fails.** Shared host/compositor/driver load can change absolute times; no confidence interval or target-hardware guarantee is claimed. The earlier full-matrix and live captures preceded final inspection-slot metadata, diagnostic filtering and toxin-debit arithmetic corrections. Final dense/contact reruns verify unchanged gameplay endpoints; the corrections preserve reference addition/event ordering. The earlier measurements remain attributed to their captured revision.

## Validation

The native suite passes **6,187 assertions** and GDScript passes **3,251**, with zero failures. New checks cover all 726 oriented species/order/acidity cases, 720 complete ticks across three seeds with packet/physiology/RNG checkpoints, real finite foreground/coarse intake and toxin/decoy exposure, native/rendered interpolation parity, optional timestamp defaults, no tick mirrors, exact import accounting, detached snapshots, handle retirement and actual lens tracking through compaction/restart. Headless editor import and whitespace checks pass.

GPU water/transport implementations and Steam launchers are unchanged; their earlier validation remains in Revision 25. Their old test counts are not claimed as rerun here. Generated libraries, caches, traces and logs stay outside Git.

## Reproduce and next gate

Use the Steam-discovering launchers:

```sh
./tools/test.sh
PRIMORDIA_BACKEND=script ./tools/test.sh

./tools/fluid_compare.sh current --frames=120 --chemicals=20000 \
  --hotpaths=pool --output=/tmp/particles-dictionaries.json
./tools/fluid_compare.sh current --frames=120 --chemicals=20000 \
  --hotpaths=all --output=/tmp/particles-pool.json
python3 tools/fluid_report.py /tmp/particles-dictionaries.json /tmp/particles-pool.json

./tools/fluid_compare.sh current --frame-step=live --seconds=8 \
  --fixture=normal --chemicals=20000 --output=/tmp/particles-live.json
```

Supply each option once. Use 50k/100k, clustered distribution, growth/encounter fixtures and music off for stress comparisons. `--hotpaths=pool` independently disables native ownership; combine it with the older `packets` / `render_cache` switches when investigating the retained compatibility pipeline. Reports include pool state/counters and full catch-up counts.

The next scaling work should address chemistry candidate work and persistent transport/index/reaction buffers, with explicit conflict ownership and full body/biological coupling. This revision provides authoritative CPU state for that work; it does not promote either diagnostic GPU fluid engine or increase default packet density. Smaller calibrated packets and resolution-independent resource balance remain separate gates.
