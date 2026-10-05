# Revision 8: procedural fractal habitat

Procedural generation and fractals are a core visual requirement from this revision onward. The owner's Spore reference motivates large branching obstacles and spatial variation in the water. Primordia generates its own artwork.

## What changes

- Up to ten seeded plant-like colonies use five-, six- or sevenfold rotational symmetry and a finite recursive branching rule. A starting colony is placed near the player when initial cell clearance permits.
- Stout stems obstruct cells and drifting particles. Swept capsule contacts catch fast crossings and preserve sliding velocity. Fine fronds and leaf buds are permeable artwork.
- Blue, teal, jade and violet water regions use four octaves of periodic noise. Patterns stay attached to the world across wrapping boundaries. Existing light, warm acidity tint and bloom retain their roles.
- Six mipmapped textures are generated once per habitat and shared by visible colony copies. A persistent spatial index and cached native particle contact batches keep added simulation work bounded.

Existing organelles, chemistry, functional organelle/particle colors, indirect cell control and build-only microtubule editing remain unchanged.

## Scientific motivation and scope

Recursive rules for botanical branching are motivated by [Prusinkiewicz's L-system work](https://algorithmicbotany.org/papers/graphical.gi86.html); see [references.md](../references.md) for the distinction between the phenomenon and the game abstraction.

The colonies are fixed, indestructible scenery. They neither produce food/oxygen nor alter fluid pressure. Only their main stems are solid; plants use rigid capsules and cells use a conservative membrane-extent disc. Six penetration passes and four sliding sweeps bound contact work. Extremely large cells or crowded multi-contact situations can exceed that approximation. The cached neighboring torus images cover ordinary camera zoom ranges, not arbitrarily many repeated world copies after unlimited growth. There is no new growth cap.

## Validation and performance

Measured on October 5, 2026: Godot 4.7.2, Ryzen 9 9950X, RTX 5080. The owner's Steam/RTX 3090/Threadripper machine was not available. Native and GDScript suites pass **1,582 and 528 assertions** respectively, including seeded placement, rotational geometry, initial clearance, SVG rasterization, tunneling, sliding, growth overlap, periodic seams, packet preservation and native/reference agreement.

CPU measurements below use the same seed, 30 warm-up ticks and 120 measured ticks, with the existing combined native backend. Plants can change trajectories and subsequent active counts; these are obstacle-on/off ecosystem runs, not identical frozen states. Values are milliseconds per simulation step, **not rendered frame rate**.

| Manual zoom | Plants off median / p95 | Plants on median / p95 | Median difference |
| --- | ---: | ---: | ---: |
| 0.50 | 5.805 / 6.521 | 6.175 / 6.435 | +0.370 |
| 0.25 | 14.618 / 15.309 | 15.290 / 15.992 | +0.672 |
| 0.15 | 15.953 / 17.057 | 16.861 / 17.690 | +0.908 |

An initial GDScript-only plant-contact implementation added roughly 5 ms at minimum zoom (21.023 versus 15.852 ms). Moving packet contacts into a cached native batch reduced that overhead substantially; the final scene also has a different starting colony placement, so these initial numbers are diagnostic rather than an exact isolated backend comparison.

Additional final native runs, 15 warm-up / 60 measured ticks:

- Four overlapping copies of the initial particle clouds at quarter zoom: 13,375 mean active packets, **43.186 ms median / 48.650 ms p95**.
- Starting player biomass reserves multiplied by 256 at minimum manual zoom, including the game's growth-dependent camera factor: **17.065 / 17.773 ms**. This is a short growth stress sample, not certification of arbitrarily large cells.

The frozen-scene Vulkan rendering benchmark alternates plants plus fractal color off/on/off/on at 1440×900, with 20 warm-up / 60 measured frames in each segment. Ten colonies share six textures.

| Zoom | Off medians (two repeats) | On medians (two repeats) | Added draw calls |
| --- | ---: | ---: | ---: |
| 0.50 | 17.486, 20.012 | 17.446, 23.751 | 4 |
| 0.25 | 25.437, 28.731 | 25.387, 28.768 | 10 |
| 0.15 | 28.706, 28.296 | 28.248, 28.359 | 10 |

These frame intervals include the virtual display and show timing drift. They do not establish a consistent rendering speedup or a precise added GPU cost. Minimum-zoom reported GPU render times were approximately 0.27–0.30 ms in both conditions.

A separate **live whole-game** minimum-zoom run measured **174.580 ms median / 184.101 ms p95**, with 18 active cells and 4,338 active packets. The existing wide-view frame-rate problem remains unresolved; the frozen draw test and CPU tick timings must not be presented as playable FPS. No performance claim is made for the owner's display or machine.

A separate 3,600-tick fully active habitat stress run passed with finite cell, fluid and packet motion throughout. Final rendered captures were inspected for plant visibility, contact/art alignment and HUD legibility.

## Reproduce

Use the Steam-discovering launchers, or supply an explicit Godot executable:

~~~sh
./tools/test.sh
PRIMORDIA_BACKEND=script ./tools/test.sh
godot --headless --path . --script tests/benchmark.gd -- --cases=all --zooms=0.5,0.25,0.15 --plants=off --warmup=30 --ticks=120
godot --headless --path . --script tests/benchmark.gd -- --cases=all --zooms=0.5,0.25,0.15 --plants=on --warmup=30 --ticks=120
godot --headless --path . --script tests/benchmark.gd -- --cases=all --zooms=0.25 --scale=4 --warmup=15 --ticks=60
godot --headless --path . --script tests/benchmark.gd -- --cases=all --zooms=0.15 --growth=256 --warmup=15 --ticks=60
godot --path . --rendering-method mobile --script tests/habitat_render_benchmark.gd -- --benchmark
godot --path . --rendering-method mobile --script tests/render_benchmark.gd -- --benchmark --zooms=0.15
~~~

Direct native benchmark invocations require the extension built by the normal launcher. Rendering tests require a display and compatible Vulkan device. Generated textures, captures, logs and libraries are not source-controlled.
