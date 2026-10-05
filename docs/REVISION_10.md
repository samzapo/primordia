# Revision 10 — luminous vector anatomy and fractal reefs

The owner approved three visual passes based on the supplied cellular illustration: stronger water/anatomy contrast, bolder functional shapes, then reef composition and restrained animation. This revision uses original procedural/vector artwork. Run economy and victory rules remain in [revision nine](REVISION_9.md).

## Appearance

- **Water:** deep indigo, blue and petrol with broad turquoise light pools. The existing periodic noise remains anchored in world coordinates. The existing acidity field still shifts water toward magenta and buffering reverses that tint.
- **Cell identity:** six saturated palette families, six seeded vesicles, and oval, bean-like or lobed nuclei. A private visual random generator uses the habitat seed and lineage identity. Appearance never reads occupation, feeding strategy or equipped organs; offspring inherit the parent's palette and pattern through their existing lineage identity.
- **Membranes:** a dark underside, broad colored band and short bright contour highlights. The surface follows the existing pressure membrane and microtubules. The decorative band does not add armor, size or collision geometry.
- **Anatomy:** thick feeding lips, layered cortex plates, rooted flagella, tapered spikes, rounded glands with nozzles, and readable chloroplast/flight silhouettes. The build-menu pictures use the same drawing functions as live organs. Existing organ sizes, costs and attachment positions remain authoritative.
- **Chemistry:** thicker forks, hooks and combs; saturated species colors and contrasting front tips. Two cached texture levels share the same forward axis. Small packets lose underside shading and fine branch detail, while their instance transform continues to use the interpolated reaction orientation. No packets are removed, enlarged or added by artwork LOD.
- **Motion:** bounded nucleus lag follows existing acceleration and turns. Feeding apertures contract on real consumption; secretory glands respond to charge/output flashes, and toxin sacs swell as a funded, targeted volley recovers. Existing membrane deformation supplies body recoil. These effects do not apply forces or alter ATP/biomass.
- **Bloom:** peak brightness and luminance select highlight pixels in light-rich regions. Ordinary water remains below the threshold. This is a shared screen-space effect, not a light per particle. It can be switched off in settings. Peripheral blur remains, with no dark vignette; HUD controls stay sharp.

At a projected cell radius below 18 pixels, the renderer uses fewer contour samples, a simpler nucleus and fewer organ details. Build mode keeps full detail. Player resource-spending packets remain visible at wide zoom; NPC decorative detail is reduced. Glyph texture selection uses each species' nominal projected diameter, so packet amounts do not require per-particle texture changes. Subpixel chemistry cannot display every branch at minimum zoom; facing is retained rather than inventing a larger physical particle.

## Fractal habitat

The habitat still contains ten attempted colonies and six cached forms with five-, six- and sevenfold symmetry. Placement now favors loose groups of three, rejects overlap with initial cells, and leaves explicit corridors between colony envelopes. Bounded retries fall back to independent placement when needed.

Primary stem radius increases from 6 to 7 units in the normalized form. The artwork's main stroke and collision capsules use that same radius; thicker stems are real obstacles. Rounded terminal bracts are permeable fine foliage. These are static scenery, not new food or oxygen sources.

This pass changes initial obstacle placement and dimensions. Same-seed trajectories can consequently differ from revision nine; it is not solely a recoloring of the old map. The finite branching grammar and game simplifications retain the [scientific motivation already recorded](../references.md#recursive-branching-and-plant-like-obstacles).

## Validation

Native: **1,802 assertions, zero failures**. Independent GDScript backend: **748 assertions, zero failures**. Checks include seeded habitat layout, clear initial cells, finite rotational geometry, native/reference stem contacts, nucleus triangulation, both glyph levels fitting the circular contact envelope, role-independent body artwork, and unchanged particle state/orientation across visual LOD.

Final UI captures were inspected at 100%/175% HUD scale and with an acidified-water fixture. A focused render check verified bounded nuclear lag without moving the membrane or cell.

The final art was also rendered in the project's default Compatibility mode on software OpenGL (llvmpipe). Timing runs use Godot 4.7.2, Vulkan Mobile, a 1440×900 Xvfb display, Ryzen 9 9950X and RTX 5080. The owner's separate Steam/RTX 3090/Threadripper machine has not been tested.

The anatomy-study capture is an enlarged presentation fixture using the real renderer, not a gameplay population or balance result. Normal captures at 50%, 25% and 15%, with bloom off/on, exercise actual game scale. Cell sizes, minimum zoom, simulation activity distance and packet counts have not been reduced to improve presentation.

## Benchmark method

`tests/visual_benchmark.gd` recreates seeded normal, fourfold-packet and 256×-biomass fixtures at 50%, 25% and 15% selected zoom, with bloom disabled and enabled. It advances 60 fixed ticks, warms the renderer for 12 frames and measures 36 actual frame intervals.

The **frozen** mode stops simulation and measures presentation, including buffer preparation and interpolation of the last simulation poses. Baseline, pass 1, pass 2 and pass 3 were measured serially. Pass 3 includes changed reef geometry, so even its one-second setup can have slightly different contacts and packet totals.

The **live** mode includes normal fixed-step simulation and catch-up. It was measured before and after the revision. Equal frame counts can span different amounts of simulation time, so live populations and packet totals can diverge. These are short workload samples, not proof of a precise causal speedup. CPU tick/prepare timings are recorded separately from whole-frame intervals.

Each cell below is **bloom off / on**, in milliseconds. Lower is better.

### Frozen presentation, median frame interval

| Fixture | Selected zoom | Before | Pass 1: color/rims | Pass 2: anatomy/glyphs | Pass 3: reefs/motion |
| --- | ---: | ---: | ---: | ---: | ---: |
| Normal | 50% | 18.59 / 17.68 | 18.20 / 17.81 | 18.00 / 18.51 | 18.65 / 18.71 |
| Normal | 25% | 18.62 / 18.80 | 18.87 / 18.88 | 20.87 / 21.42 | 20.41 / 23.02 |
| Normal | 15% | 21.96 / 26.12 | 21.86 / 26.75 | 25.41 / 25.61 | 26.79 / 28.38 |
| 4× packets | 50% | 26.29 / 26.76 | 26.58 / 26.47 | 29.09 / 28.37 | 28.19 / 28.11 |
| 4× packets | 25% | 31.92 / 32.17 | 31.87 / 31.20 | 31.25 / 31.21 | 34.31 / 34.03 |
| 4× packets | 15% | 31.66 / 32.00 | 32.11 / 31.65 | 31.20 / 31.43 | 32.89 / 31.54 |
| 256× biomass | 50% | 25.49 / 25.62 | 25.15 / 25.85 | 25.06 / 25.07 | 25.04 / 28.73 |
| 256× biomass | 25% | 26.08 / 26.00 | 25.90 / 26.37 | 25.49 / 25.38 | 28.55 / 27.07 |
| 256× biomass | 15% | 26.07 / 25.99 | 25.82 / 26.66 | 25.34 / 25.58 | 25.58 / 25.34 |

### Live game, median frame interval

| Fixture | Selected zoom | Before, off / on | Final, off / on | Final bloom-on p95 |
| --- | ---: | ---: | ---: | ---: |
| Normal | 50% | 31.85 / 31.97 | 32.81 / 32.55 | 34.12 |
| Normal | 25% | 136.21 / 134.67 | 136.28 / 136.97 | 138.82 |
| Normal | 15% | 145.00 / 145.32 | 140.91 / 141.89 | 149.94 |
| 4× packets | 50% | 127.42 / 131.71 | 116.53 / 132.52 | 143.55 |
| 4× packets | 25% | 279.27 / 279.56 | 281.90 / 283.41 | 328.52 |
| 4× packets | 15% | 284.85 / 290.27 | 280.85 / 282.09 | 364.07 |
| 256× biomass | 50% | 78.30 / 79.98 | 78.72 / 79.10 | 82.05 |
| 256× biomass | 25% | 145.76 / 146.82 | 145.56 / 145.78 | 152.75 |
| 256× biomass | 15% | 146.19 / 146.76 | 146.57 / 147.33 | 153.21 |

The paired frozen median changes span pass1: -0.97 to +0.67 ms; pass2: -1.14 to +3.55 ms; pass3: -0.90 to +3.66 ms across these short samples. The results do not establish a consistent overall speedup. Individual bloom-on samples can be faster because of measurement variation; disabling bloom cannot be credited with a negative cost.

**Wide-view 60 FPS acceptance remains unmet.** Final normal quarter zoom measured 136.97 ms median per frame, and dense quarter zoom 283.41 ms. The art update preserves the existing simulation and view extent; solving its remaining frame-rate bottleneck is separate work.


## Reproduce

Steam discovery remains the default:

```sh
./tools/test.sh
PRIMORDIA_BACKEND=script ./tools/test.sh
./tools/run.sh --rendering-method mobile --script tests/visual_benchmark.gd -- --benchmark --hud-scale=1 --stage=current --mode=frozen
./tools/run.sh --rendering-method mobile --script tests/visual_benchmark.gd -- --benchmark --hud-scale=1 --stage=current --mode=live
```

Optional switches: `--fixtures=normal,dense,growth`, `--frames=36`, and `--output=/absolute/existing/directory` for the six normal frozen screenshots. Outputs, runtime glyph textures, mipmaps and compiled artifacts are not committed. The authored art paths, procedural rules and benchmark generator are retained.
