# Revision 18 — currents beyond the camera

Distant particles no longer freeze into clouds around their source cells. The whole habitat keeps transporting its existing material, using reduced update frequency outside the camera. Nothing new is spawned to fill gaps.

## Transport rules

- Visible particles and the existing offscreen halo advance at the full simulation rate. The outer halo no longer reduces elapsed transport time; cell and chemical activity still use their existing fade.
- A rotating cursor visits roughly one thirtieth of the particle array per 60 Hz tick. Far packets usually move once every 0.5 seconds, spread across frames rather than in one burst. Compaction preserves the cursor's next surviving position.
- A timestamp records each packet's last update. Every visit integrates actual elapsed time, and a newly visible packet catches up once. New packets start their clocks at birth; pausing does not accumulate transport debt.
- Coarse motion samples the cached current with bounded midpoint substeps of about 0.25 seconds. Launch velocity decays exponentially, with its displacement integrated analytically. Thermal displacement scales with sqrt(elapsed time), preserving variance 2 D elapsed per coordinate; angular diffusion follows the same rule.
- Far fluid nodes refresh every 0.25 seconds with complementary activity, conservative viscosity and relaxation toward the maintained tide. Cell forcing stays local. The foreground mask is restored before biological interactions.
- Material sweeps against solid plant stems even offscreen. Pheromones still ignore all solids, retain immutable emission metadata, and expire globally on their ordinary exponential lifetimes. Camera catch-up does not draw long interpolation trails.
- Background random draws use a separate seeded stream. Reference GDScript, native CPU and optional GPU foreground paths share the integration formulas. Background GPU-mode work uses the ordinary CPU path.

## Deliberate limits

This is an approximation for transport, not a full distant ecosystem. Offscreen cells, emissions, material chemistry/decay and acidity updates retain their previous activity rules. Dormant cell bodies do not receive far-particle contacts; ordinary membrane exclusion resumes locally. Coarse stem collision sweeps the chord between endpoints, not every bend of a Brownian path.

Half-second updates have bounded positional lag. Very fast camera movement may reveal a caught-up position immediately; normal approach has the existing 128-world-unit halo to prepare it. Up to eight midpoint substeps bound catch-up work. The fluid uses the existing viscous grid and maintained tide, not a new incompressible solver. Its coarse complementary update approximates exchange across the changing activity boundary.

Initial particles still originate around cells, and their clouds disperse over elapsed simulation time rather than being redistributed instantly. Diffusion coefficients, resource sources, particle counts and chemical reaction rules have not been increased to hide gaps.

See [the physical and numerical motivation](../references.md#coarse-offscreen-transport).

## Validation

Final full suites pass **3,527 native assertions** and **2,468 reference assertions**, with zero failures. Focused transport/visibility checks pass **316 assertions on each backend**.

Focused regressions cover elapsed-time accounting across camera promotion, births and compaction; conserved packet identity/material; global pheromone expiry; wrapping; native/reference parity; thin-stem sweeps; interpolation; and coarse field refresh.

In a 2,400-packet constant-current ensemble, measured diffusion variance divided by theoretical 2 D elapsed is 1.007 on x and 0.971 on y; mean drift residual is 0.215 world units. Over ten simulated seconds in a curved current, coarse midpoint transport differs by 0.025 world units from a 0.004-second Euler reference. These seeded checks establish local numerical behavior, not calibrated biological fidelity.

## Performance

Transport-only ablation on eka-workstation-samzapo, Godot 4.7.2, 80% playable camera footprint, native CPU backend. Each case uses the same seed, uniform particle workload, 60 warm-up ticks and 180 measured ticks. Includes transport, spatial-grid rebuilding, distant stem contacts and far fluid refresh; excludes rendering, chemistry and cell biology. “Fine” runs distant particle transport at 60 Hz while keeping the same coarse far-field refresh. “Frozen” disables the background work in this revision.

| Packets | Frozen mean ms/tick | Coarse mean ms/tick | Fine mean ms/tick | Coarse / fine far updates per tick |
| --- | ---: | ---: | ---: | ---: |
| 4,096 | 0.482 | 0.861 | 5.593 | 116 / 3,465 |
| 16,384 | 2.082 | 4.237 | 34.303 | 464 / 13,885 |

Coarse transport adds 0.379 / 2.155 ms over frozen background in these workloads, versus 5.111 / 32.221 ms for fine background transport. It makes about 30 times fewer far-packet updates; total measured transport cost is about 6.5 / 8.1 times lower than the fine alternative. This adds useful work compared with the former freeze; it is not a claim of higher whole-game FPS.

Reproduce with the project Godot executable: --headless --path . --script tests/transport_benchmark.gd. Set PRIMORDIA_BACKEND=script for the fallback. The ordinary suite includes tests/offscreen_transport.gd; tests/gpu_benchmark.gd additionally checks coarse GPU camera promotion. For whole-game ablation, tests/visual_benchmark.gd accepts --camera=play --mode=live --background=off or --background=coarse, independently of music and bloom.


### Reference fallback

The same ablation on the GDScript fallback has these mean transport times. It remains slower than native execution, but reduced-frequency background transport also saves substantial work there.

| Packets | Frozen ms/tick | Coarse ms/tick | Fine ms/tick |
| --- | ---: | ---: | ---: |
| 4,096 | 1.694 | 2.835 | 26.066 |
| 16,384 | 6.519 | 12.843 | 115.265 |

### Rendered wide-view checks

1440×900 Xvfb, Vulkan Mobile on an RTX 5080, 80% effective zoom, native backend, live ecology, 12 warm-up frames and 36 measured frames per case. These are short samples on a shared host with other compilation activity, not target-hardware certification. Cells and particle populations evolve, so the isolated transport table above is the cleaner timing comparison.

| Fixture / bloom | Background off, music off median ms/frame | Coarse, music off median ms/frame | Coarse, music on median / p95 ms/frame | Coarse, music on CPU tick ms | Audio skips |
| --- | ---: | ---: | ---: | ---: | ---: |
| normal / off | 45.931 | 47.022 | 47.405 / 50.519 | 7.545 | 0 |
| normal / on | 48.953 | 50.890 | 51.333 / 58.584 | 7.398 | 0 |
| dense / off | 149.154 | 155.947 | 162.259 / 190.948 | 14.031 | 201 |
| dense / on | 154.916 | 169.741 | 168.669 / 192.187 | 13.693 | 232 |
| growth / off | 64.121 | 64.638 | 64.196 / 65.954 | 7.741 | 0 |
| growth / on | 63.277 | 64.800 | 63.985 / 66.718 | 7.113 | 0 |

Dense scenes remain well below the desired smooth frame rate and can underrun audio, as in prior revisions. Continuous background transport does not solve the existing wide-view rendering/whole-frame bottleneck. Music mixing itself remains bounded; these measurements must not be described as 60 FPS or an overall frame-rate improvement.

GPU parity checks on the same device report at most 0.000122 world-unit foreground position error and 0.000244 world-unit coarse-promotion error versus CPU. The GPU path stays opt-in; its resident-kernel throughput is not the cost of a complete ecological tick.
