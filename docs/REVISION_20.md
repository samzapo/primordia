# Revision 20: membrane depth and flow streamers

Cells now have a rounded, shaded membrane lip and softer gel interior. Their surface follows the same irregular pressure/microtubule outline used by existing geometry; lineage colors still do not encode occupation. Animated pale streamers replace the short background flow vectors. Faint downstream disturbance glints appear beside slipping cells and sturdy plant stems.

## Presentation and simulation

- Explicit mesh rings preserve the deformed membrane boundary, including dents and large growth, without passing that surface through polygon triangulation. Shading uses a fixed viewing light; turning a cell changes its highlight direction. Nucleus, functional organs, resource sacks, microtubules and local controls retain their artwork.
- Streamers integrate the actual cached fluid field. Their bright end travels with flow, curvature follows bends, and a faster field produces a longer trail. Periodic world-anchored seeds remain stable while the camera crosses the habitat seam. Birth/expiry fades replace sudden trail resets.
- Two bounded GPU batches cap work at 640 strips and 30 plant anchors. Signed 64×40 field textures update at 15 Hz or less and interpolate between updates. There are no per-tracer scene nodes, CPU trail histories, collision passes or ecological particles.
- Cell glints brighten with body/fluid slip. Plant contours sample a few stout branch segments, leaving fine foliage permeable. Existing fluid forces and plant contacts are unchanged.
- Simulation time drives every new animation. Editing and settings pause both flow trails and disturbance effects. Presentation neither consumes resources nor draws from ecological RNG streams.

The underwater rings are stylized optical cues, not a literal free-surface ripple model, turbulent wake simulation or new obstacle boundary condition. [References](../references.md#membrane-depth-and-flow-presentation) distinguish Earth Nullschool's visual inspiration from Purcell's viscosity-dominated microscale motivation.

## Validation

Final suites pass **3,581 native assertions and 2,522 reference-backend assertions, zero failures**. New coverage checks exact membrane boundaries under compression/growth, valid indexed geometry, bounded periodic streamer seeds, stout-stem anchor limits, signed field texture fidelity, paused animation, same-clock restart and no changes to ecological random streams, fluid or particles. Existing suites exercise contacts, chemistry, music, succession and editing. Vulkan Mobile and OpenGL Compatibility captures complete without script/shader errors. Compatibility reports an Xvfb-driver warning about unsupported V-sync changes, unrelated to the new shaders. Capture and benchmark logs remain in private task records, outside Git. No player-machine measurements are available.

## Rendering measurements

Final-source checks use Godot 4.7.2 on the shared Linux workstation (Ryzen 9 9950X / RTX 5080), at 1440×900 and **80% effective play zoom**. Each case has 60 sampled frame intervals after 60 simulation warmup ticks and 12 render warmup frames. Ranges cover bloom off/on. Cases ran serially; unrelated host activity contributes variance. These are not RTX 3090 / Threadripper 2990WX measurements.

Frozen scenes isolate the new presentation:

| Presentation | Normal median frame ms | Dense median frame ms | Growth median frame ms |
| --- | ---: | ---: | ---: |
| flat / vectors / no wakes | 19.66–20.75 | 26.57–28.42 | 26.79–27.04 |
| depth / vectors / no wakes | 18.56–18.78 | 26.18–26.41 | 25.40–25.50 |
| depth / streamers / no wakes | 18.07–18.15 | 21.61–25.34 | 25.81–26.32 |
| depth / streamers / wakes | 18.32–18.36 | 25.38–25.72 | 24.21–24.24 |

The full presentation is comparable to the legacy cost in these fixtures. Some cases get cheaper, but small differences and the inconsistent dense streamer-only result should not be read as a portable speedup. Depth shading does not introduce a clear regression here; streamers replace many cached line commands with one bounded batch. Wakes remain a small incremental visual effect. Whole rendered frames still exceed 16.7 ms.

Live scenes include ordinary ecology and audio preparation:

| Music | Normal median frame ms | Dense median frame ms | Growth median frame ms | Dense audio skips |
| --- | ---: | ---: | ---: | ---: |
| off | 38.82–48.53 | 144.76–149.96 | 54.27–57.03 | 0.00–0.00 |
| on | 40.57–49.04 | 148.38–150.54 | 53.99–57.08 | 246.00–261.00 |

Dense p95 frame intervals reach about 190 ms. The final-frame simulation-time EMA is about 7.2–8.8 ms for normal/growth and 12.5–15.9 ms for dense scenes; it is reported separately from frame intervals and is not an independently sampled median CPU tick benchmark. Flow presentation preparation measures roughly 0.004–0.015 ms in normal/growth and up to 0.21 ms on the final dense upload frames. No authoritative simulation kernel changed.

Dense live scenes continue to underrun audio. This art revision does not solve the existing dense simulation/rendering bottleneck. Audio-on/off comparisons are short shared-host workloads, not a claim about listening quality or sustained campaign performance.

OpenGL Compatibility renders the full effects without script/shader errors at 80%, including the growth fixture. Vulkan captures at 3× additionally check membrane highlights, gel shading and interior readability; a plant-centered 80% capture checks fern stems and their streamers. The closer capture is visual evidence only.

## Benchmark reproduction

Use a real display and the same engine/renderer for each comparison:

~~~sh
/path/to/godot --path . --rendering-method mobile --audio-driver Dummy --script tests/visual_benchmark.gd -- --benchmark --camera=play --zooms=0.8 --mode=frozen --frames=60 --membrane=flat --flow=arrows --wakes=off
~~~

For the shading-only case use membrane=depth with arrows/wakes off. Then use flow=streamers, followed by wakes=on. These are benchmark arguments, not player settings. The game defaults to depth, streamers and wakes.

Repeat the full case with mode=live and music=off/on. The harness runs normal, fourfold initial particle density and 256× starting biomass, each with bloom off/on. The 80% play camera stays fixed after growth. Use rendering-method gl_compatibility for the fallback check. Frozen mode isolates presentation cost; live frames include simulation catch-up and audio preparation. Neither is an isolated CPU tick benchmark. Close 3× captures check shading/readability only and do not count as performance acceptance.
