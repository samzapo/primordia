# Revision 25: comparing GPU water solvers

The approved comparison now has two opt-in Godot compute prototypes: a pressure-projected velocity grid and Position Based Fluids (PBF). **Ordinary gameplay still uses the existing CPU medium.** Neither prototype meets the combined stability and dense-scene performance requirements for becoming the default.

At 20,000 initial chemical packets, full frames cost 70–74 ms; at 50,000 they cost 145–147 ms. Replacing water alone does not make the particle soup playable. Packed chemical storage, transport/reaction batching and rendering preparation are the next priorities. Keep the grid as the provisional architecture for the submerged habitat, while retaining PBF as its experimental rival. This is an architecture recommendation, not a measured production-quality winner.

## Implemented comparison

| Property | GPU grid | GPU PBF |
| --- | --- | --- |
| Water representation | Staggered MAC velocity grid | Explicit solvent particles |
| Default resolution | 256 × 160 nodes, spacing 16 | Spacing 16, support radius 32 |
| Solve | 80 weighted Jacobi pressure iterations | 8 compression-only density iterations |
| Advection / viscosity | Midpoint backtrace, explicit diffusion | Position prediction, density correction, XSPH-style smoothing |
| Body feedback | Integrated pressure impulses | Incoming wall-contact impulses |

Both cover the entire 4,096 × 2,560 wrapped habitat every tick, use nominal density `22 / 64²` and viscosity 40, and rasterize actual rotated, deformed membranes and solid fractal stems. A common four-unit solvent exclusion layer is included. Nominal viscosity coefficients are shared; equivalent drag and rheology have **not** been calibrated between methods. This is a coarse 2D game medium, not molecular water or a strict microscale Stokes solver.

Chemistry remains separate from solvent. Existing finite chemical packets, oriented binding, plant permeability, pheromone snapshots, ATP costs, ciliary pumping, offscreen ecology and native/reference paths remain. No new gameplay source, free tissue, hidden cell mass bonus, particle cap or default backend switch is added. The benchmark splits the initial cell-produced packet inventory without duplicating amount, stored product or capacity. Finer packet contact/absorption rates are not yet calibrated for resolution-independent balance.

GPU water stays resident between ticks. The comparison bridge uploads cell/plant geometry and a 64 × 40 impulse field, then synchronously reads a sampled velocity field and body impulses. Its round trip is roughly 100 KiB/tick including geometry in the ordinary fixture. It does **not** read back every solvent particle during gameplay; full-state quality snapshots run outside the timing window. The final particle-soup design should avoid this per-tick synchronous bridge and dictionary-based chemical state.

The prototypes explicitly reject unsupported renderers/displays, invalid options and exceeded body/geometry capacities. They currently support at most 32 live bodies; exceeding that limit reports an error rather than silently omitting cells. That experimental capacity is not a gameplay restriction.

## Reproduce on the Steam machine

These commands use the existing Steam discovery, including custom libraries/Flatpak; `GODOT_BIN` remains an optional override. Run with a GPU display and Mobile/Forward+ support, not `--headless` or Compatibility rendering.

```sh
./tools/fluid_compare.sh validate --output=/tmp/fluid-validation.json
./tools/fluid_compare.sh resident --output=/tmp/fluid-resident.json

for fluid in current grid pbf; do
  ./tools/fluid_compare.sh "$fluid" --frames=120 --chemicals=20000 \
    --output="/tmp/$fluid-20k.json"
done
python3 tools/fluid_report.py /tmp/current-20k.json /tmp/grid-20k.json /tmp/pbf-20k.json
```

Use `--chemicals=50000`, `--distribution=clustered`, or `--fixture=growth` for the other workloads. `--fluid-dx=16|32` controls the boundary/grid resolution; PBF solvent spacing remains 16. `--fluid-iterations=N` accepts even counts from 2 to 256, with zero selecting the model default.

The default comparison has one 1/60-second simulation tick per rendered frame (`--frame-step=fixed`). Its frame rate is **fixed-tick throughput**, not normal live FPS. For live catch-up:

```sh
./tools/fluid_compare.sh grid --frame-step=live --seconds=3 \
  --output=/tmp/grid-live.json
```

`--fluid-feedback=off` is an intentionally incomplete diagnostic: it removes the added pressure/contact impulse applied to cells. Do not use it as a production mode or a successful physics result. Existing membrane exchange still runs. Reports/logs belong outside Git.

## Resident solver cost

Measured on **RTX 5080 / Ryzen 9950X, Godot 4.7.2**, using a GPU-rendered headless Weston display. The fixture has sixteen cells, a 94.6-unit large-cell radius and 318 fractal plant segments. There are 40,960 grid nodes or 39,381 solvent particles.

Each row has six warmup ticks followed by twelve batches of four ticks. Times include CPU command recording and the GPU completion fence, with static geometry and no chemistry, body feedback, field export or rendering in the timed region. These are **not isolated GPU timestamps or game FPS**.

| Solver / iterations | Mean ms/tick | p95 batch-average ms/tick |
| --- | ---: | ---: |
| Grid / 40 | 0.296 | 0.303 |
| Grid / 80 | 0.582 | 0.640 |
| Grid / 160 | 1.164 | 1.197 |
| PBF / 4 | 0.264 | 0.279 |
| PBF / 8 | 0.484 | 0.543 |
| PBF / 16 | 0.951 | 1.025 |

Different iteration counts and error measures are not equivalent accuracy. PBF's smaller resident time does not establish it as the better water model.

## Full rendered frames

All modes use the same initial finite chemical inventory, placement seed 25171, world seed 20261004, paid cilia, sixteen cells, **80% view at 1440 × 900**, native CPU chemistry/transport, bloom, streamers, wakes and music. The uniform fixtures run 120 fixed-step frames: exactly two simulated seconds.

| Initial chemistry | Water | Mean frame ms | p95 frame ms | Integrated water ms/tick |
| --- | --- | ---: | ---: | ---: |
| 20,000 | Current | 70.065 | 86.036 | 0.384 |
| 20,000 | Grid | 72.790 | 83.562 | 2.155 |
| 20,000 | PBF | 73.587 | 86.849 | 2.135 |
| 50,000 | Current | 146.455 | 219.517 | 0.389 |
| 50,000 | Grid | 147.429 | 214.600 | 2.525 |
| 50,000 | PBF | 145.343 | 215.521 | 2.369 |

The CPU baseline advances distant water more coarsely; both GPU experiments advance the full torus at 60 Hz. This table measures integration cost, not an equal-accuracy solver contest. No repeated-trial confidence interval is available, and small differences between modes are inconclusive.

At 20k, native transport takes 19–20 ms/tick, chemistry about 18 ms/tick and particle-view synchronization 9–10 ms/frame. At 50k those rise to about 40, 41 and 21 ms. Nested simulation phases must not be added to their parent tick totals. The water solver is not the dominant bottleneck.

Packets merge and decay during the fixture: active counts fall from 20k to roughly 12k, and from 50k to roughly 17k. Uniform runs record 7,275–7,352 nutrient combinations at 20k and 30,779–31,009 at 50k. These are functioning contact reactions, but mostly nutrient aggregation; this is not yet a sustained, emission-balanced, many-species soup. Counts, per-simulated-second events and material endpoints are retained by the report tool. Oxygen/pheromones are separate from its organic packet-material sum; a packet endpoint alone is not a whole-ecosystem conservation test.

Short stress fixtures use sixty fixed ticks / one simulated second:

| 20k fixture | Current mean/p95 ms | Grid mean/p95 ms | PBF mean/p95 ms |
| --- | ---: | ---: | ---: |
| Five clustered clouds | 50.588 / 72.181 | 51.952 / 73.525 | 51.919 / 75.868 |
| Large cell, radius about 231 | 65.396 / 77.740 | 63.160 / 73.901 | 63.233 / 72.452 |

Clusters merge faster, reducing work. These one-second fixtures do not establish long-run stability.

The three-second **live** tests reach seven frames with eight catch-up ticks each. Current/grid/PBF produce only eleven/ten/ten measured frames and advance about **1.017 simulated seconds** in 3.03–3.10 wall seconds. Mean intervals are 275/310/304 ms. Music also skips during this overload. This confirms the catch-up feedback loop; fixed-step throughput must not be presented as normal gameplay FPS.

A serial per-body reduction initially made grid integration cost 19.6 ms/tick. Parallel fixed-order impulse reductions lowered it to 2.15 ms/tick in the same fixture. This removes a prototype bridge bottleneck; it is not an improvement to ordinary gameplay, whose default was never changed.

## Physics findings and promotion gates

Fourteen GPU regression checks pass: periodic translation/momentum, smooth-vortex behavior and static deformed-cell/fractal-stem fixtures. Grid uniform momentum drift is zero in the measured float diagnostic; PBF relative drift is about 0.07%. Grid pressure reduces the smooth fixture's RMS divergence from 0.01087 to 0.00860. These checks validate limited fixtures, not production water.

The moving-cell uniform fixture exposes a grid defect after two seconds: peak water speed reaches **1,781 units/s**, with RMS divergence **0.188**. With added pressure feedback disabled, it falls to **159 units/s** and divergence **0.00343**. That implicates the explicit body-pressure coupling. Added-mass instability is a plausible explanation from fluid–structure literature, **not a proved diagnosis**. A coupled/implicit pressure-body solve and longer momentum/energy checks are required; increasing body mass or capping water speed would hide the problem.

PBF's corresponding peak speed is 372 units/s. It retains about **4.36% RMS density error**, chiefly density deficit around boundaries in this compression-only implementation. It needs boundary-volume/neighbor treatment and calibrated viscosity/drag. The roughly nine-unit nearest-grid-node penetration diagnostic is coarse and is not proof of exact membrane exclusion. It also needs longer moving/deforming-body conservation and contact tests.

Neither solver is promoted. Before a dense-soup playtest, prioritize packed persistent chemical state and batched transport/reactions/render preparation; then repair and compare fluid coupling at matched tolerances. The 100k fixture is supported but **not benchmarked here**, because even 20k misses the 16.67 ms target substantially.

## Validation and limits

Native suite: **4,376 assertions, zero failures**. Independent GDScript suite: **3,249 assertions, zero failures**. Steam-launcher fixtures pass nine checks, including comparison argument forwarding and unknown-solver rejection. GPU validation has fourteen assertions and zero failures; five CLI guard checks reject malformed options, and headless editor import compiles the scripts. Quality failures above remain open even though regression tests pass.

The owner's RTX 3090 / Threadripper 2990WX / Steam machine was unavailable. Workstation figures are not predictions for it. Headless Weston uses the real NVIDIA GPU; it has different frame pacing from a desktop. Dummy audio exercises preparation without validating speaker output. Some earlier timing runs overlapped a one-core reference suite; repeated resident measurements after that suite agree in scale. Low background host load remains, and no unpaired percentage gain is claimed.

Some traces completed but stalled during Wayland shutdown; only their verified task-owned processes were terminated after capture. Initial failed shader/flow checks were repaired and rerun. Generated traces, logs, native libraries and imports are retained privately or ignored rather than committed.

Scientific and numerical motivations are in [references.md](../references.md).
