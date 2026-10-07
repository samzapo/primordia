# Revision 26: sharing particle state across phases

The first particle migration stage is enabled in the native backend. Reusable numeric slots carry packet state through transport, grid repair and chemistry, then hand their poses to bulk drawing. In the final 20k fixed-step comparison, mean whole-frame cost falls from **84.53 to 71.82 ms**. The provisional **20k / 60 FPS target remains unmet**.

Ordinary particle density stays unchanged. This revision improves the current CPU path; it does not introduce GPU chemistry or promote either Revision 25 water prototype.

## State and compatibility

Transport imports touched dictionary fields lazily into reusable numeric slots. Grid repair consumes their positions directly, and chemistry reuses their geometry, velocity and orientation. Transport mirrors remain current; changed chemical fields publish before biology. Source metadata and public dictionary identity remain intact.

Drawing consumes numeric poses from the last tick and caches packet facts between display frames. It recomputes interpolation, camera offsets and projection outside the actual deformed membrane each frame. Feeding, toxin/decoy contact, hidden exposure and membrane exclusion invalidate changed slots; spawning, replacement arrays and compaction refresh indices. Paused editing reads fresh dictionaries. Native and reference mutation callers both maintain this contract.

Direct external edits must call `kernels.invalidate_particle_render(index)`, or omit the index to refresh all poses. Scoped chemistry keeps reaction activity/contact radius as private scratch rather than publishing those derived caches. Standalone dictionary kernels retain their established behavior; the original standalone transport is preserved unchanged for comparison.

Allocation persists, but touched fields are still imported and public transport fields still mirrored each tick. This is **not yet an authoritative structure-of-arrays pool, stable global particle handles or GPU-resident chemistry**. Incompatible reference/GPU-transport/barrier diagnostics bypass the scoped path; render handoff also requires the native post-chemistry path. The independent GDScript backend remains available.

## Whole-frame comparison

Measured on **RTX 5080 / Ryzen 9950X, Godot 4.7.2**, Vulkan Mobile through a GPU-rendered headless Weston display, 1440 × 900 at the **80% widest playable view**. Music preparation, bloom, flow streamers, wakes, anatomy and ordinary biology run; audio output uses Dummy. Each fixed-step frame contains exactly one 1/60-second tick.

Baseline disables only `packets` and `render_cache` in the same source. Other native optimizations remain enabled. The 20k baseline/combined rows pool two 120-frame trials in reversed order; other rows use 120 frames. These are **fixed-tick throughput measurements, not live FPS**.

| Initial packets / fixture | Baseline mean / p95 ms | Combined mean / p95 ms |
| --- | ---: | ---: |
| 20k uniform, two trials | 84.53 / 100.87 | 71.82 / 86.82 |
| 50k uniform | 176.32 / 259.40 | 145.47 / 224.76 |
| 100k uniform | 282.40 / 524.58 | 235.83 / 455.16 |
| 20k clustered | 56.75 / 95.72 | 46.11 / 81.60 |
| 20k, large membrane | 69.51 / 93.67 | 60.71 / 80.87 |
| 20k, hunter encounters | 86.60 / 103.28 | 67.56 / 84.16 |

Aggregation/decay reduce counts during each two-second fixture; these are not sustained 20k/50k/100k active populations. Uniform active counts range from 20,000 to 11,854 in the 20k fixture, and 50,000 to 17,067 at 50k. The grown player finishes at radius 231.18 world units; the encounters fixture has nineteen cells and extra nearby hunters. Splitting the finite fixture inventory does not duplicate material.

For every matched fixed-step pair, reaction totals, remaining packet material, player biomass and all three final random states match exactly. At 20k there are 7,352 combinations, 168 decays and one recycling event. This establishes local parity on the tested engine/platform, not cross-platform determinism.

## Separate effects

| 20k variant | Mean frame ms | Particle visual preparation ms |
| --- | ---: | ---: |
| Both disabled, two trials | 84.53 | 10.97 |
| Numeric pipeline only, one trial | 82.31 | 11.22 |
| Render cache only, one trial | 88.28 | 11.68 |
| Both enabled, two trials | 71.82 | 3.30 |

Packing alone provides a small change within the variation of these runs. A standalone cache has no benefit when every display frame contains a new tick. Sharing the transported numeric state with drawing supplies most of the combined saving. The total tick includes chemical publication; its final combined mean is 3.86 ms/tick. Lazy imports move work between phase timers, so the chemistry timer alone is not a valid speedup claim.

## Genuine live scheduling and audio

At ordinary dense-fixture density (2,117–3,674 active packets), the final eight-second live tests give baseline mean/p95 **8.09 / 17.93 ms** and combined **5.12 / 15.17 ms**. They advance 480 and 479 ticks respectively; most extra rendered frames contain no tick. This is one shared-host comparison, not a guaranteed desktop frame rate.

At 20k, both final live runs advance only **61 ticks / 1.017 simulated seconds in about 3.1 wall seconds**, with seven eight-tick catch-up frames. Baseline/combined p95 is **431 / 456 ms**. Cheaper presentation has not solved the catch-up spiral.

A final muted 20k fixed-step run costs 59.93 ms mean / 71.32 ms p95. Host activity changed between runs, so the difference from the music-on trials cannot be attributed to audio. Music preparation itself is reported separately; audio output/listening was not tested.

Background CPU/build/I/O activity varied during the investigation. Earlier trials, an identical CPU-affinity subset comparison and the final preserved-reference trials all show a combined fixed-step saving, while absolute times and live results vary substantially. No confidence interval or dependable audio percentage is claimed. The owner's RTX 3090 / Threadripper 2990WX Steam machine remains unavailable.

## Validation and reproduction

The native suite passes **5,166 assertions**; the GDScript suite passes **3,250**, both with zero failures. New native checks cover every species pair/order and acid regime, optional timestamp defaults, finite feeding/contact mutations, dictionary identity, camera transitions, compaction, exact random states and cached-versus-fresh drawing. Headless editor import and whitespace checks pass. GPU water and launchers are unchanged; their previous results are recorded in Revision 25, not claimed as new tests here.

Use the Steam-discovering launcher with a GPU display:

```sh
./tools/test.sh
PRIMORDIA_BACKEND=script ./tools/test.sh

./tools/fluid_compare.sh current --frames=120 --chemicals=20000 \
  --hotpaths=packets,render_cache --output=/tmp/particles-baseline.json
./tools/fluid_compare.sh current --frames=120 --chemicals=20000 \
  --hotpaths=all --output=/tmp/particles-combined.json
python3 tools/fluid_report.py /tmp/particles-baseline.json /tmp/particles-combined.json

./tools/fluid_compare.sh current --frame-step=live --seconds=8 \
  --fixture=dense --chemicals=0 --output=/tmp/particles-live.json
```

Disable `render_cache` alone to measure packing, or `packets` alone to measure standalone caching. Use 50,000/100,000 packets, `--distribution=clustered`, `--fixture=growth` or `--fixture=encounters` for stress cases; use `--music=off` for audio ablation. Supply each option once. Reports include packet counts, phase timings, catch-up ticks, reaction totals, material and random-state endpoints.

Generated libraries, imports, traces and captures remain outside Git. Completed traces that stalled during Wayland shutdown were verified before terminating only their owned processes.

## Next scaling gate

Move biological consumers into a native-owned particle pool with compact batch exchange, so ordinary ticks no longer import/mirror every transported packet through Godot dictionaries. Then evaluate resident transport, indexing and oriented chemistry with explicit reaction conflict resolution. Keep material, perception, camera-transition and body-coupling checks alongside whole-frame timing. Increased gameplay density and calibrated smaller packets remain gated on useful live throughput and resolution-independent balance.
