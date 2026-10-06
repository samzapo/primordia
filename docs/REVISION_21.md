# Revision 21 — live-frame profiling and simulation batching

## Finding

The dense-frame slowdown is chiefly CPU simulation, amplified by fixed-step catch-up. A slow rendered frame causes several 60 Hz updates in the following frame; those updates can then make that frame slower. Membrane depth, streamers, wakes and bloom remain enabled. The repair reduces repeated work instead of reducing simulation frequency, visibility, particle populations or art detail.

The earlier Revision 20 Xvfb numbers are retained as historical evidence, but should not be interpreted as NVIDIA rendering throughput. Compatibility rendering there used llvmpipe software rendering; Vulkan used NVIDIA but carried substantial virtual-display presentation overhead. This investigation uses a private NVIDIA EGL/Wayland compositor and records actual engine GPU timings.

## What changed

- Update moved particle buckets instead of rebuilding every retained packet after transport, stem collisions and membrane exclusion. Buckets retain rebuild identity order; appends and compaction start a new index lifetime.
- Batch hidden, timestamped chemistry in the native backend, including foreground clock marking. Keep the same elapsed unary hazards, oriented contact rules and random draw order. Clear occupied scratch bins and write changed chemical fields only.
- Batch detailed pore feeding, passive oxygen/carbon collection and probabilistic hidden feeding. Consume the same finite packets, enforce the same storage caps and retain accepted-encounter solid-path checks.
- Batch cell contact rejection. Cache positions/envelopes within each pass and refresh both bodies after each contact, preserving pair order, all three motion substeps, five contact passes and the existing narrow solver.
- Reject impossible particle and cell stem contacts with conservative swept bounds. Keep overlap resolution, continuous capsule sweeps, impulses and friction.
- Batch pressure-preserving membrane dents. Search neighboring ordered polar edges for support rays, with a full-search fallback.
- Filter sensing, receptor competition and toxin queries by the packet's current live species inside native queries. Never cache chemical tags across reactions.
- Batch background scheduling, interpolation-history cleanup and survivor compaction. Keep round-robin credit, cursor continuity, timestamps and packet dictionary identity.
- Build the same explicit four-ring membrane mesh in a native batch. Preserve every triangle, boundary UV, normal color and existing LOD.

The reference backend and independent diagnostic switches remain available. Steam discovery, music synthesis/sample clock, biology costs, pheromone-only perception and all shaders are unchanged.

## Measuring a frame

The opt-in tracer holds at most 6,000 rows in memory and writes only after sampling. It is absent during ordinary play. Each row spans post-draw to post-draw and aggregates every physics tick since the previous row, rather than reporting only the last tick.

It records tick count/elapsed simulation time/CPU work; nested simulation phases; fluid/particle/cell view synchronization; membrane mesh generation; UI and inspection; cell/organ draw callbacks; the render boundary; delayed renderer CPU/GPU measurements; music preparation and generator underruns. F3 now labels its existing values as tick and view-sync timings rather than implying whole-frame CPU/GPU measurements.

Counts include stored/active cells, views, stored/active/background particles, retained pheromones, pair checks, body/spike contacts, receptor/pheromone queries and candidates, membrane updates, mesh updates and canvas draw calls. Contact counts include repeated solver passes, not unique physical pairs. Membrane updates count detailed biological steps; mesh updates count presentation rebuilds.

Nested timings must not be added to their parents: geometry is inside cell synchronization, draw callbacks occur inside the render boundary, and music is inside the process callback. Engine render timings are delayed observations rather than an additive GPU fence. The report retains unallocated wall time, p50/p95/max, tick histograms, catch-up/cap percentages, music skips and the correlation between a long frame and next-frame tick count.

## Benchmark conditions and results

Measurements use Godot 4.7.2, 1440 × 900, the 80% widest playable view, uncapped rendering, bloom/wakes/streamers enabled and default music volume. The dense fixture quadruples initial particles; the growth fixture gives the player 256 times its initial biomass; encounters adds three ordinary hunters and a nearby grazer to the dense fixture. Each run starts from the same seed with 60 simulation warm-up ticks and 30 frozen render warm-up frames.

The workstation has a Ryzen 9 9950X and RTX 5080. These are not the player's Threadripper 2990WX/RTX 3090. Headless hardware presentation is also not a monitor/Steam play session. Shared host jobs caused substantial timing variation. Final comparison runs pin only this task's Godot process to ordinary CPUs 14 and 15; host configuration and other jobs are unchanged. Earlier slow busy-host runs remain in private evidence.

Final live-frame samples (music on unless stated):

| Fixture / renderer | Mean frame, ms | Mean FPS | p95 frame, ms | Multiple-tick frames | Music underruns |
| --- | ---: | ---: | ---: | ---: | ---: |
| Dense, old paths / OpenGL | 111.62 | 9.0 | 190.99 | 90.3% | 158 |
| Dense, optimized / OpenGL | 8.96 | 111.6 | 18.07 | 0.0% | 0 |
| Dense, optimized, music off / OpenGL | 7.25 | 137.9 | 16.57 | 0.0% | 0 |
| Dense, optimized / Vulkan Mobile | 14.29 | 70.0 | 35.41 | 11.4% | 0 |
| Hunter encounters, optimized / OpenGL | 19.24 | 52.0 | 34.98 | 15.6% | 0 |
| Hunter encounters, music off / OpenGL | 30.15 | 33.2 | 55.05 | 63.9% | 0 |
| Hunter encounters / Vulkan Mobile | 27.72 | 36.1 | 45.64 | 58.5% | 0 |
| Normal / OpenGL | 2.80 | 357.7 | 8.39 | 0.0% | 0 |
| Grown player / OpenGL | 3.14 | 318.0 | 8.72 | 0.0% | 0 |

The dense old-path run spends 105.75 ms of its 111.62 ms mean frame in simulation. It averages 5.93 ticks per frame, hits the eight-tick cap in 47.2% of frames and advances only 7.12 simulation seconds in 8.04 wall seconds. Previous-frame duration predicts next-frame tick count strongly (correlation 0.917). The optimized dense run advances 8.00 simulation seconds in 8.00 wall seconds, with no multiple-tick frames in that sample.

Frame-phase means, in milliseconds:

| Phase | Dense old paths | Dense optimized | Hunter encounters optimized |
| --- | ---: | ---: | ---: |
| All simulation ticks | 105.75 | 5.32 | 13.67 |
| Field + particle + cell synchronization | 2.06 | 1.18 | 1.43 |
| Membrane mesh generation (inside cell sync) | 0.744 | 0.072 | 0.168 |
| Cell + organ draw callbacks (inside render boundary) | 0.807 | 0.433 | 1.226 |
| Pre/post draw boundary | 1.397 | 1.228 | 1.579 |
| Global engine render setup CPU | 0.065 | 0.052 | 0.061 |
| Delayed engine render CPU | 0.607 | 0.540 | 0.798 |
| Delayed engine render GPU | 0.408 | 0.432 | 0.529 |
| Music preparation | 0.330 | 0.040 | 0.090 |
| Unallocated wall time | 1.792 | 1.028 | 2.246 |

The dense run retains 11,064–14,434 packets with 1,949–3,681 actively transported, 16 cells with 5–6 active, 105–539 retained pheromones and 217–296 canvas draw calls. It has no body/spike contacts or hunting/flight queries during this interval, which is why the encounter fixture is also necessary. Encounters retains 11,340–14,136 packets, 2,618–3,357 active, 19 cells with 7–9 active, 130–677 pheromones and 364–511 draw calls. Per detailed tick it averages 1,814 pair checks, 15.68 body contacts, 1.92 spike contacts, 0.30 pheromone queries, 1.85 receptor queries with 413 candidates, 8.51 membrane updates and 6.52 presentation mesh rebuilds.

The lower FPS with music disabled in one encounter run reflects uncontrolled shared-host variation; it is not evidence that music accelerates the game. Its directly measured preparation cost is small. Earlier optimized dense samples ranged from 37 FPS during substantial shared build activity to 75–91 FPS in quieter runs. The repair is a substantial gain, but crowded encounters still miss a steady 60 FPS and p95 stalls remain. A hardware/Steam playtest is still needed; no claim is made that the player's older CPU achieves these rates.

Equal-horizon CPU comparisons (240 ticks, ABBA means; positive delta means the optimized path saved time):

| Path | Enabled tick, ms | Disabled tick, ms | Delta, ms/tick | Interpretation |
| --- | ---: | ---: | ---: | --- |
| All revision paths | 14.16 | 25.55 | +11.39 | Large combined saving |
| Incremental grids | 12.97 | 18.90 | +5.93 | Largest individual saving |
| Native hidden chemistry/clocks | 13.37 | 14.90 | +1.52 | Measured saving |
| Detailed/coarse feeding | 14.56 | 17.98 | +3.41 | Measured saving |
| Contact broad phase | 15.29 | 14.61 | −0.69 | Whole-tick result inconclusive |
| Conservative stem bounds | 15.61 | 16.46 | +0.85 | Measured saving |
| Current-species queries | 24.90 | 14.84 | −10.06 | Control run suffered broad host slowdown |
| Background/history batching | 18.41 | 17.35 | −1.06 | Whole-tick result inconclusive |
| Dirty chemical writes | 14.64 | 15.59 | +0.95 | Chemical phase also improved |
| Native survivor compaction | 13.35 | 15.34 | +1.99 | Variable control timing; magnitude uncertain |
| Neighbor support rays, encounters | 15.24 | 15.56 | +0.32 | Small overall saving |
| Native dents, encounters | 15.11 | 15.68 | +0.56 | Small overall saving |

The contact phase itself drops from about 0.92 to 0.15 ms/tick despite the noisy total. In the species-query comparison, the first adjacent pair improves from 14.37 to 13.27 ms, but the final enabled control takes 36.54 ms with unrelated transport and chemistry also nearly tripling. It is therefore inappropriate to attribute the −10.06 ms aggregate to filtering. Background batching also overlaps a changing host load. These paths are retained for their direct batching/phase benefits and equivalent rules; no isolated whole-frame gain is claimed for them. Compaction's disabled repeats vary from 12.78 to 17.90 ms, so its +1.99 ms estimate is particularly uncertain.

Native mesh generation reduces the measured dense presentation phase from 0.744 to 0.072 ms/frame and the earlier encounter mesh phase from roughly 1.01 to 0.168 ms/frame. That phase comparison is indicative rather than an isolated ABBA frame-rate claim. Both full and reduced mesh topology are checked against reference arrays.

Live runs sample eight wall-clock seconds and expose catch-up and any time lost at the eight-step cap. Fixed-tick comparisons run the same 240 simulation steps after warm-up, with music disabled. Each item uses enabled/disabled/disabled/enabled ordering to reduce serial host-load drift. Per-item CPU deltas are not additive, and a live FPS change cannot be attributed directly to one nested timer.

## Validation

The final native suite passes **3,638 assertions** and the GDScript suite passes **2,525**, with zero failures or script errors. The 90-second native ecosystem fixture takes 45.84 wall seconds (maximum individual tick 28.58 ms); the reference takes 161.17 seconds (maximum tick 100.10 ms). These are headless CPU simulation measurements, not rendered FPS.

New differential checks cover incremental/full grid order across seams, appends and compaction; hybrid reference moves; current live species filtering; capped feeding across deformed membranes; hidden feeding randomness and material accounting; elapsed oriented chemistry and inactive-halo timestamps; sequential crowded contact impulses; repeated pressure-preserving dents; 600 swept particle/stem paths and 40 cell/stem paths; background scheduling/history; consecutive dirty chemical batches; survivor cursor/identity; and exact colors/UVs/indices for both membrane mesh LODs. Profiler checks verify multiple-tick aggregation, explicit zero counts, idempotent lifecycle and unchanged ecology.

All final hardware runs exit successfully and are scanned for script/engine errors. The benchmark harness now waits for music-bank readiness with biology frozen before its render warm-up; startup synthesis must not seed a measured catch-up spiral. The reporter exposes the ready percentage. The earlier table retains first-series measurements, which include a few initial bank-loading frames; the steady-repeat result is given below.

A repeat with music ready for **100% of measured frames**, on the final code:

| Fixture / renderer | Mean frame, ms | FPS | p95 frame, ms | Multiple-tick frames | Music underruns |
| --- | ---: | ---: | ---: | ---: | ---: |
| Dense, old paths / OpenGL | 146.45 | 6.8 | 212.86 | 85.5% | 233 |
| Dense, optimized / OpenGL | 11.93 | 83.8 | 21.75 | 3.3% | 0 |
| Dense, optimized / Vulkan Mobile | 15.74 | 63.5 | 29.16 | 8.9% | 0 |
| Hunter encounters / OpenGL | 37.24 | 26.9 | 55.65 | 90.3% | 0 |
| Hunter encounters / Vulkan Mobile | 25.20 | 39.7 | 36.63 | 47.5% | 0 |

The old-path repeat hits the catch-up cap in 76.4% of frames; optimized repeats never hit it. Host load rose during the repeat. The encounter range across final samples is roughly 27–52 FPS, so the remaining crowded-scene limit is material and not hidden behind the best result. The next bottlenecks are packet dictionary handling in transport/chemistry and detailed body/fluid/spike work, rather than shader throughput.

Raw traces, logs, compositor wrappers and intermediate results live in the owning task's private revision21 validation directory. Generated libraries, imports, bindings and captures remain outside source control.

## Reproduce on the play machine

Use the ordinary Steam-discovering launcher. The profiler disables vsync only for its own benchmark process:

~~~sh
./tools/run.sh --rendering-method gl_compatibility --audio-driver Dummy --script tests/frame_profile.gd -- --benchmark --fixture=dense --seconds=8 --music=on --output=/tmp/primordia-frame.json
python3 tools/frame_report.py /tmp/primordia-frame.json
~~~

Repeat with the mobile rendering method, music=off, and fixture=normal, growth or encounters. Mode=frozen isolates presentation after the same warm-up. Dummy exercises synthesis/buffering without speaker output; real-device listening still belongs in the playtest.

~~~sh
./tools/run.sh --headless --script tests/frame_profile.gd -- --benchmark --fixture=dense --mode=ticks --ticks=240 --music=off --hotpaths=all --output=/tmp/primordia-ticks.json
~~~

Fixed-tick output is already a summary, not input for frame_report.py. Hotpaths=all is the optimized default; legacy disables this revision's paths. Individual names disable only that path: grid, chemistry, feeding, contacts, obstacles, surface, dents, kinds, bookkeeping, writes, compact and geometry. Comma-separated combinations are supported. Geometry affects rendered runs rather than simulation-only timings. Max-steps is a diagnostic process option; the game's 60 Hz/eight-step defaults are unchanged.

## Technical references

- [Godot Engine timing controls](https://docs.godotengine.org/en/stable/classes/class_engine.html): fixed physics frequency and catch-up limits.
- [Godot RenderingServer](https://docs.godotengine.org/en/stable/classes/class_renderingserver.html): frame signals, viewport render timing and canvas counters.

The actual APIs were also checked against the installed 4.7.2 engine. This revision introduces no new biological model; the motivating phenomena and simplifications in references.md remain applicable.
