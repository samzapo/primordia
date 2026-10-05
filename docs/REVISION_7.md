# Revision 7 — wide-view simulation efficiency

The owner approved five performance targets, prioritizing compiled CPU execution, GPU experiments and fluid work. Every item has an independent benchmark or ablation. Close-view timing is no longer performance acceptance. This revision improves current CPU costs substantially, but does **not** establish smooth 60 FPS at every zoom or future particle density.

## Delivered and retained

1. **Compiled batches:** C++ transport, orientation chemistry, particle grid, visible-membrane exclusion, particle rendering buffers, and membrane edge/pressure constraints. Chemistry uses reusable contiguous scratch records and local bins; field-key and particle-identity caching avoid repeated conversions in tight loops. Cell orchestration, the tension network and most biology remain in GDScript, and particle dictionaries still bridge those systems. This is not a complete native rewrite.
2. **GPU experiment:** a RenderingDevice compute shader advances particle position, rotation and fluid sampling. Persistent buffers support a transport-only throughput experiment. An optional gameplay bridge feeds results back to CPU chemistry. That bridge measured slower and is **not the default**. GPU chemistry, cell contacts and GPU-direct drawing remain future work.
3. **Fluid:** native conservative viscosity and acidity transport, plus local suction-node queries. Finite mass, equal/opposite cell impulses, currents and dormant-water rules remain. The fluid is still a 64 × 40 grid, not SPH or a new incompressible solver.
4. **Spatial coverage:** a conservative periodic cell index replaces repeated full-cell scans for exterior particles and toxins. Native exclusion and rendering use corresponding local cell candidates and visible outline intersections. The existing swept cell-cell solver remains.
5. **Scheduling/detail:** NPC sensing starts are staggered while the existing 0.15-second sensing cadence remains. Tiny NPC drawings omit decorative vesicles/resource dots and refresh every second tick. Player/build anatomy and chemical/contact physics remain full-rate. Scheduling alone produced no meaningful overall speed gain; visual detail reduction had mixed results in repeated drawing fixtures.

The Linux launcher and test launcher automatically build the extension from pinned godot-cpp source. CMake, a C++17 compiler, Git and Python 3 are prerequisites. Two compile jobs are the default. `PRIMORDIA_BACKEND=script` selects the independent fallback. F3 identifies the active backend. Generated dependencies, bindings and binaries are ignored and rebuilt automatically.

## Correctness findings

The native suite passes **1,180 assertions**, including 726 ordered species-pair/acidity/orientation comparisons, thermal transport, periodic boundaries, field transport and all earlier gameplay/interface checks. Tests also cover native particle rendering orientation and agreement between native and reference membrane constraints. The reference-only suite passes 446 assertions, and all seven Steam launcher fixtures pass. A clean Godot editor import and real launcher smoke run pass too. A redraw regression verifies that small cells refresh after even-numbered catch-up batches; throttling measures elapsed ticks rather than tick parity.

A longer whole-habitat run found an existing numerical weakness in packet aggregation: a tiny photosynthetic remainder can be below float32 range. Multiplying vector velocities by tiny material amounts before dividing produced non-finite velocities. Both backends now normalize weights first and use a convex velocity blend, preserving material. A regression fixture uses 1e-60-scale packets. The full habitat subsequently completed **3,600 ticks / 60 simulated seconds** with all cell, fluid and particle motion finite. `tests/stress.gd` retains that check.

## CPU results

Godot 4.7.2, Ryzen 9 9950X workstation, no competing build jobs. Each case starts from seed 20261004 and the same habitat: 30 warmup ticks plus 120 measured 1/60-second ticks. These are simulation-throughput measurements, **not FPS**. The camera changes which organisms advance. Different native arithmetic/query order can change subsequent encounter histories; this is a same-seed workload comparison, not bitwise trajectory identity. No cross-backend or cross-platform determinism claim is made.

| View | Reference median / p95 | Final combined median / p95 |
| --- | ---: | ---: |
| Default | 7.25 / 7.77 ms | 2.65 / 3.08 ms |
| Half zoom (4× area) | 18.40 / 20.61 ms | 5.52 / 5.82 ms |
| Quarter zoom (16× area) | 64.69 / 67.17 ms | 13.97 / 14.95 ms |
| Minimum zoom (0.15) | 76.78 / 80.14 ms | 15.50 / 16.29 ms |

Quarter zoom averages approximately 16 active cells and 3,600 active particles; minimum zoom activates all 19 starting cells and about 4,100 particles. A 60 FPS frame has 16.67 ms for simulation, preparation and drawing together: the maximum-view simulation alone nearly consumes that budget.

Independent quarter-zoom changes relative to the 64.69 ms reference:

| Change enabled alone | Median / p95 tick | Interpretation |
| --- | ---: | --- |
| Native kernels/grid/exclusion | 19.34 / 21.55 ms | Largest current gain; compiled render preparation is measured separately. |
| Native fluid/acid + local suction | 59.88 / 61.35 ms | Fluid phase falls from approximately 6.2 ms to 0.9 ms in the combined fixture. |
| Script cell spatial queries | 44.01 / 46.36 ms | Removes much of the particle-by-cell scanning. |
| Stagger sensing starts | 64.34 / 66.96 ms | No meaningful overall improvement in this workload. |
| All retained CPU changes | 13.97 / 14.95 ms | Effects overlap; isolated savings must not be added together. |

An intermediate native build measured 17.99 ms combined. Caching native field keys and candidate identities reduced it to 14.50 ms. Native edge/pressure constraint batches then reduced it to 13.97 ms, a small additional gain. These optimizations are included in the final native rows above; unchanged reference/fluid/spatial/scheduling rows come from the preceding isolated run.

Density stress uses the same cell population with translated copies of initial cell-derived clouds; it is synthetic benchmark material, not a gameplay particle source. Fifteen warmup plus 60 measured ticks at quarter zoom:

| Starting particle multiplier | Average active particles | Reference median / p95 | Combined median / p95 |
| --- | ---: | ---: | ---: |
| 4× | approximately 13,400 | 249.99 / 270.53 ms | 39.06 / 48.02 ms |
| 16× | approximately 48,000 | Not rerun at this cost | 187.57 / 240.61 ms |

These dense, overlapping cell-product clouds are still expensive. Native execution does not remove the cost of many genuine close contacts. No particle cap, skipped chemical encounters or smaller active habitat was introduced to improve the figures.

## GPU findings

The workstation now exposes an **RTX 5080**, NVIDIA 595.91.07, Vulkan. This is not the owner's separate RTX 3090 / Threadripper machine.

The transport shader agrees with the CPU fixture to 0.000245 world units and 0.00000109 radians over one step across 4,465 particles. In 60-dispatch batches with state kept on-device, measured amortized transport time was approximately 0.0032 ms for 4,096 particles, 0.0035 ms for 16,384, and 0.0053 ms for 65,536. This fixture excludes chemistry, cells, rendering and per-tick readback, and uses zero thermal noise. It is a throughput ceiling, not expected gameplay performance.

Before the final small membrane-constraint extraction, in the actual quarter-zoom CPU bridge, the full tick was **17.61 ms median / 18.60 ms p95**, versus **14.61 / 15.21 ms** for the native CPU backend in the same comparison. An end-of-run bridge sample spent about 2.78 ms packing, 0.41 ms uploading/executing/downloading, and 1.35 ms unpacking. Therefore the GPU bridge remains opt-in. The next GPU step must keep chemistry/spatial state resident and transfer compact cell events rather than all particles each tick.

## Rendering limits

Rendered checks use a 1440 × 900 Xvfb window with the real RTX 5080 Vulkan renderer and bloom enabled. Xvfb presentation is not the owner's display environment. A cached frozen viewport alone measured about 17.3 ms frame intervals. Cell drawing and repeated catch-up simulation steps make live frame intervals much longer; **the rendered run did not pass a 60 FPS target**.

Before the final small membrane-constraint extraction, after native particle-buffer preparation, live preparation averages were approximately 0.44 ms at half zoom, 1.28 ms at quarter zoom and 1.62 ms at minimum zoom. Reported viewport GPU drawing time was approximately 0.17–0.34 ms. Measured live median / p95 frame intervals were **34.36 / 44.30 ms**, **137.36 / 142.63 ms**, and **169.74 / 178.96 ms**, respectively. These are candid end-to-end measurements, not derived FPS from the much smaller GPU or simulation timings. The earlier non-finite-particle rendering run is excluded from acceptance.

The final-source minimum-zoom run explicitly confirmed VSync disabled and no FPS cap, but still measured **163.51 / 176.60 ms** median / p95 frame intervals (19 active cells, 4,855 active particles). Preparation averaged 1.63 ms, simulation 17.01 ms, reported viewport CPU drawing 1.94 ms and GPU drawing 0.32 ms. The same frozen-state native buffer-preparation comparison alternated script medians 11.771 / 11.846 ms with native medians 1.435 / 1.434 ms. This directly isolates that native rendering gain.

On an identical frozen minimum-zoom state, alternated full-detail versus reduced-detail drawing measured 41.68 / 41.69 ms medians versus 36.20 / 36.28 ms. A later repeat varied more (28.06 / 41.46 ms full detail versus 29.22 / 35.81 ms reduced), so the visual LOD result is less robust than the buffer-preparation gain. It is insufficient to solve whole-game frame pacing. CPU cell/membrane work, drawing cost, presentation and catch-up behavior remain optimization targets; do not infer the exact cause of unaccounted frame time from GPU timing alone.

## Reproduce

```sh
# Default build and complete native correctness suite; independent fallback.
./tools/test.sh
PRIMORDIA_BACKEND=script ./tools/test.sh
python3 tests/test_launchers.py

# Independent CPU cases at all four zooms.
./tools/run.sh --headless --script tests/benchmark.gd
# Larger clustered clouds (synthetic stress fixtures).
./tools/run.sh --headless --script tests/benchmark.gd -- --cases=reference,all --zooms=0.25 --scale=4 --ticks=60 --warmup=15
./tools/run.sh --headless --script tests/benchmark.gd -- --cases=all --zooms=0.25 --scale=16 --ticks=60 --warmup=15
./tools/run.sh --headless --script tests/stress.gd

# A real display/GPU is required for these Vulkan experiments.
./tools/run.sh --rendering-method mobile --script tests/gpu_benchmark.gd
./tools/run.sh --rendering-method mobile --script tests/benchmark.gd -- --cases=all,gpu --zooms=0.25
./tools/run.sh --rendering-method mobile --script tests/render_benchmark.gd
# Optional gameplay experiment; the normal launcher keeps native CPU transport.
./tools/run.sh --rendering-method mobile -- --gpu-transport
```

Benchmarks print structured JSON records with active counts, median/p95/p99, phase times and backend. Keep outputs outside source control. Future acceptance must include maximum zoom, growth-induced zoom, large cells, mixed chemistry clusters and death bursts. The current density matrix does not exhaust those combinations. Further native cell/tension-network execution and a fully resident GPU chemistry/event pipeline are the next substantial opportunities; simply moving more arithmetic into isolated shaders will not remove the CPU bridge.
