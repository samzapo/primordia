# Revision 32 — current-engine particle loop costs

The established fluid, ordered chemical grid, collisions and population settings remain the gameplay defaults. This revision reduces CPU overhead without changing integration arithmetic, contact or reaction ranges, random draw order, feeding, or offscreen scheduling.

## Retained changes

- Chemistry reuses scratch records rather than constructing and destroying a Godot Dictionary for each candidate on every pass. Foreground and background passes have separate buffers so a small background batch does not discard the foreground records. Every pass-dependent field is refreshed before neighbor traversal; the buffer size remains the exact candidate count. This trades a second tier-specific scratch allocation for less allocation churn.
- Scoped transport reads each particle ID once instead of repeatedly retrieving and converting it through the Godot array. The dictionary reference kernel and all scalar interpolation, midpoint integration, wrapped coordinates, diffusion and angular arithmetic remain unchanged.
- An allocation-heavy scratch ablation remains available for parity and timing comparisons. It shares the inexpensive single-ID lookup, so its timings isolate scratch reuse rather than claiming a separately measured ID-lookup gain.

No extra random numbers, simplified chemistry, skipped contacts, smaller population, or camera-dependent feeding policy are introduced.

## Rejected experiment

Call-scoped raw views of flow and position arrays passed exact packet/RNG comparisons but produced no consistent whole-frame benefit. A paired transport-only test alternated call order at each step, after eight warmup steps, and measured 80 steps per variant. At 20k and 50k packets, raw views saved only 0.4–0.5% in fine transport and 1.4% in half-second coarse transport. The extra pointer/lifetime path was removed. Kernel timings are not rendered FPS.

In the initial shared-load 50k rendered matrix (two reversed-order trials per variant), scratch reuse alone reduced mean chemistry time from 12.85 to 10.00 ms (22%). Mean whole-frame intervals changed from 43.76 to 42.25 ms (3.4%). Adding raw views was not reliably better: the combined mean was 48.67 ms, including a noisy 53.82 ms trial. All fixed trials had exactly matching material, reaction, biomass and three RNG endpoints. These exploratory results are distinct from final-source verification below.

## Reproduce

Use the Steam-discovering launchers; an explicit GODOT_BIN remains optional.

```sh
./tools/test.sh
PRIMORDIA_BACKEND=script ./tools/test.sh
./tools/fluid_compare.sh current --chemicals=50000 --frames=120 --hotpaths=scratch_reuse --output=/tmp/reference.json
./tools/fluid_compare.sh current --chemicals=50000 --frames=120 --hotpaths=all --output=/tmp/optimized.json
```

`--hotpaths` names optimizations to disable. Add `--distribution=clustered`, or `--fixture=growth --particle-sizes=mixed`, for density and body-size stress. Keep 80% zoom and normal visuals/music enabled for acceptance. GPU fluid and LiquidFun modes remain separate diagnostics.

## Final-source measurements

Godot 4.7.2, Ryzen 9950X / RTX 5080, Mobile renderer, NVIDIA GPU-rendered Wayland headless compositor, 1440×900, 80% zoom. Music and visuals stay enabled except the named muted pair; audio output is Dummy. Each fixed trace has 120 displayed frames and exactly two simulated seconds. The reference disables scratch reuse; both sides include single-read transport indexing. Pairs alternate order between fixtures and run serially. The workstation also ran unrelated jobs, so absolute times and small differences remain load-sensitive.

| Initial chemicals / fixture | Reference mean / p95 ms | Reuse mean / p95 ms | Chemistry mean, reference → reuse ms |
| --- | ---: | ---: | ---: |
| 20,000 uniform | 22.97 / 27.75 | 21.43 / 25.33 | 5.09 → 4.09 |
| 50,000 uniform | 37.19 / 61.56 | 39.20 / 59.02 | 11.44 → 9.71 |
| 50,000 clustered | 32.75 / 65.79 | 30.23 / 64.14 | 9.35 → 7.45 |
| 20,000, large cell / mixed packet sizes | 21.93 / 28.30 | 21.43 / 26.50 | 4.33 → 3.77 |
| 20,000 uniform, music off | 21.84 / 25.96 | 20.68 / 25.00 | 4.50 → 3.92 |

Final whole-frame gains are modest and workload-dependent: about 7% at 20k uniform and 8% in 50k clusters. Uniform 50k mean time is slightly worse despite cheaper chemistry, with transport also slower under the changing shared load. This is not a reliable uniform-50k frame-rate improvement.

All five final fixed pairs exactly match packet material, chemical events, player biomass/radius and all three RNG endpoints. Fine packet and full cell-state equality are checked separately by the regression suite. This is fixed-step whole-frame throughput, not live FPS. Clouds shrink through normal chemistry/feeding: the initial packet count is not sustained density. The 50k fixed run ends near 19.8k packets; both live 20k runs end near 7.8k. The native pool retains zero per-tick dictionary mirror writes.

The live 20k reference trace measures 13.84 / 31.31 ms mean/p95, advances 8.00 simulated seconds in 8.00 wall seconds, reaches 3 ticks in its busiest frame, and has 0 eight-tick frames.

The live 20k optimized trace measures 8.24 / 17.38 ms mean/p95, advances 7.98 simulated seconds in 8.00 wall seconds, reaches 4 ticks in its busiest frame, and has 0 eight-tick frames.

Live endpoints are at different horizons and are not asserted equal. A single live pair does not isolate causality from shared-host load. Neither these shrinking clouds nor the isolated chemistry saving establishes sustained 50k/60 FPS, mobile performance, or the owner's RTX 3090 / Threadripper results. Ordered neighbor/contact/reaction work remains a scaling cost.

## Validation

Final native suite: **69,525 assertions**, zero failures. GDScript fallback: **3,291 assertions**, zero failures. New paired regressions cover two seeds, pool and scoped dictionary ownership, camera jumps between broad/narrow/offscreen activity, scratch shrink/growth, compaction, exact particle fields, cell physiology, acidity, finite accounting and all RNG streams. Existing suites retain oriented species-pair, LiquidFun, parcel, rendering and gameplay checks. Editor import and whitespace checks pass. Steam launchers are unchanged. Generated builds and measurement traces remain outside Git.
