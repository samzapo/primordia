# Revision 15 — living edges, varied fractals and steady inspection

The full screen now runs at normal simulation speed. The offscreen activity band replaces the old ellipse that froze visible corners. Reefs gain fern, fan and spiral forms, and the particle lens briefly follows what it selects.

## Simulation boundary

The rectangular view plus 64 world units runs at full speed. The next 64 world units fade smoothly to dormancy; nothing slows merely because it enters the visible edge blur. That full-speed buffer also covers the fluid grid's interpolation neighbors at screen edges.

The same rule applies to native, reference and experimental GPU particle transport, chemistry and the local fluid field. Spatial queries include the offscreen band; rendering still gathers only the actual view and its small drawing margin. Wrapped boundaries and the free camera follow the same rule.

Cell activation includes the membrane extent and the existing 80-unit appendage/drawing allowance. A large cell cannot freeze while its body is still visible just because its center is outside the camera. The whole cell advances together, so this can activate more offscreen biology than the point-particle band.

Distant material and cells remain dormant. Existing global pheromone expiry and explicit population triggers remain exceptions. Settings/editing still pause the simulation. This change increases actual work; it does not reduce physics frequency or discard particles.

## Four plant families

- **Ferns:** a curved central stalk, paired tapered pinnae and recursively smaller leaflets, with green lanceolate blades.
- **Branching fans:** a basal trunk and repeated binary forks with rounded pink/violet buds.
- **Spiral rosettes:** three or four curling arms with smaller golden branchlets.
- **Radial colonies:** retained five- or seven-armed cyan branching forms.

Each family has two forms; eight 512×512 mipmapped textures are generated once per habitat. There are still ten placement attempts/colonies at the default seed, with open starting water and gaps between reefs. The geometry is bounded to 192 branches per form; current forms use 46–172. The default habitat has 318 solid stem capsules.

Main stems remain collision obstacles; the smallest leaves and buds are decorative. There are no per-leaf scene nodes, new food sources or photosynthetic scenery. Botanical inspiration and the distinction from literal microscopic ferns are recorded in [references.md](../references.md#recursive-branching-and-plant-like-obstacles).

Generation uses its own seeded random stream. Layout repeats within this revision; adding forms changes the stream consumption and therefore some layouts compared with revision fourteen.

## Particle tracking

Hover still opens the local 3.5× lens. It now centers on and follows the selected particle, retaining its tooltip for up to **0.9 seconds** after that particle leaves the pointer. Continuing to hover the same particle renews that period.

Small hand movements and nearby rival particles cannot steal the target. Moving the pointer more than 24 screen pixels (scaled with text/UI size) from the acquisition point releases it, allowing another selection. The lens also releases when the packet dies, its signal expires, it leaves the screen, a new world starts or modal interaction suppresses inspection.

Tracking holds the actual packet dictionary, recovers its index from local buckets after compaction, and uses the rendered interpolated position and angle. A chemical conversion updates the displayed species. It never resolves a pheromone's reported source to a live cell, changes particle state or scans the entire ecosystem to recover a target.

## Validation

Godot 4.7.2: the full native suite passed **3,163 assertions** and the independent reference suite passed **2,108**, with zero failures. Four additional inspection checks were added after the native full run; they passed in the final 116-check interface run on both renderers and in the final reference suite. Native production code was unchanged between those checks. Engine import and whitespace validation passed.

The original eight-form plant design sheet was inspected. Geometry tests check seeded repeatability, all four families, bounded extents, rasterization, clear spawn space, wrapped/swept contacts and native/reference agreement. Viewport tests cover all edges/corners, fluid interpolation, wrapped transport, offscreen reactions, far dormancy and a partly visible large cell.

Inspection checks include motion, target competition, small pointer jitter, deliberate release, array compaction, chemical conversion, death, signal expiry, world restart and free-camera wrapping. The rendered interface suite passes **116 checks on each of Vulkan Mobile and OpenGL Compatibility**. Compatibility uses llvmpipe; it is a rendering correctness check, not an NVIDIA OpenGL speed claim.

GPU parity passes, including the new corner/fringe/wrapping fixture: zero measured edge-position discrepancy and less than 0.000001 seconds age discrepancy. The general transport fixture retains less than 0.005 world-unit position error and 0.00001 radians angular tolerance. GPU transport remains opt-in.

## Wide-view cost

Same workstation, Godot 4.7.2, Ryzen 9 9950X / RTX 5080, 1440×900 Xvfb, Vulkan Mobile, native simulation, widest playable **80%** camera. Music is on in the table. Each live case has 12 warm-up frames and 36 measured frames. Dense starts with four times the packets; growth starts with 256 times the player's unspent biomass. These are short whole-frame samples, not a 60 FPS acceptance pass.

“Boundary only” temporarily uses revision fourteen's original plants with the new simulation boundary. It isolates the dominant activity change from the new habitat. Layout and dynamics differ in the final seeded run, so small final-vs-boundary differences are not a controlled pure geometry measurement.

| Fixture | Bloom | Before median ms | Boundary-only median ms | Final median ms | Final p95 ms | Final CPU tick ms |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| Normal | Off | 26.427 | 32.711 | 32.417 | 33.095 | 5.706 |
| Normal | On | 26.439 | 32.419 | 34.164 | 35.477 | 5.678 |
| Dense | Off | 46.777 | 111.809 | 98.575 | 130.902 | 9.583 |
| Dense | On | 54.137 | 99.523 | 111.399 | 132.560 | 9.659 |
| Growth | Off | 32.944 | 46.700 | 46.930 | 48.768 | 5.707 |
| Growth | On | 33.063 | 47.057 | 47.105 | 48.867 | 5.665 |

**The corrected activity region has a significant cost.** Normal and growth fixtures now activate six cells instead of three/two, and roughly twice as many particles. Dense activates five cells instead of two and about 2,400 particles instead of 1,660. Frame stalls remain serious; this revision does not meet 60 FPS or solve the broader performance problem.

With music disabled, final medians are 32.343/32.336 ms (normal, bloom off/on), 99.205/111.640 ms (dense) and 46.763/46.822 ms (growth). The stall remains with audio off. Music-on dense runs report 45/55 buffer skips; normal/growth report zero. Mixer call peaks stay below 0.45 ms, but long frames still starve audio refills. The dummy audio driver detects starvation; these checks do not establish listening quality on a real audio device.

### Separate habitat costs

At 80%, 120 native headless ticks after 30 warm-up ticks give a **5.711 ms median / 6.033 ms p95 with plant contacts**, versus **5.095 / 5.652 ms without**. The difference includes changed trajectories/contact outcomes, not only capsule arithmetic. Drawing is absent from these CPU measurements.

A frozen scene toggles plants and fractal water together, twice, with 60 measured frames per sample. Final off/on medians are **17.903/17.936 ms** and **20.462/24.132 ms**, with 245/247 draw calls. The baseline pairs were 17.936/17.922 and 17.908/20.497 ms. Frame-time drift prevents claiming a precise fixed artwork overhead or an improvement. Eight cached textures replace six; no per-frame fractal generation is added.

The owner's separate Steam/RTX 3090/Threadripper machine was not available. The remaining dense-scene frame stalls, audio starvation and balance changes from additional active biology need further work and owner playtesting.

## Reproduction

Use the Steam-first launchers as usual; the native library rebuilds automatically. Do not copy generated libraries between machines.

~~~sh
./tools/test.sh
PRIMORDIA_BACKEND=script ./tools/test.sh
./tools/run.sh --rendering-method mobile --script tests/visual_benchmark.gd -- --benchmark --hud-scale=1 --mode=live --stage=camera-80 --camera=play --music=on
./tools/run.sh --rendering-method mobile --script tests/habitat_render_benchmark.gd -- --benchmark --hud-scale=1 --camera=play --zooms=0.8
./tools/run.sh --headless --script tests/benchmark.gd -- --cases=all --zooms=0.8 --plants=on --ticks=120 --warmup=30
~~~

Repeat the visual command with music off and the CPU command with plants off. GPU edge parity is included in `tests/gpu_benchmark.gd` and requires a RenderingDevice renderer.
