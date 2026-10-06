# Revision 13 — pheromone perception

Every active living cell emits dissolved **pheromone points**. These replace the old cell-trace species at particle index 3. No new organ or direct movement control is added.

## The trail is the information

Each point captures source identity/lineage, position, total organic mass, radius, hostile anatomy and emission time. These are values recorded at release, never a reference to a live creature. Hostility means a functional spike or toxin vesicle; it is not inferred from the cell's role or body palette.

Hunting spikes sample pheromones within 120 world units of the organ and pursue a reported smaller creature's last-known location. Flight receptors sample within 90 units and retreat from reports of larger or armed creatures. Existing anatomy size, sensing traits and receptor blockage modify these local sampling radii. The trail can communicate a creature much farther away after the current carries it into reach. No target is discoverable merely because its cell is nearby or visible.

The newest locally received report from each source takes precedence, including news that previously edible prey has grown. In-flight internal signals carry the received location and the pheromone's expiry. Steering memory lasts at most 1.2 seconds without reception and never outlives that expiry. A moved or dead source can leave a misleading trail; there is no live-cell lookup to correct it. Own-lineage recognition also comes from the report.

Grazing pores still sense nutrient particles and photosynthetic organs still sense light. Toxin vesicles aim using a spike/flight report. Physical contact still causes collisions and damage, without granting extra targeting information.

## Transport and decay

- Every active creature emits eight points per local simulated second, including cells without receptors, weapons or ATP.
- Points follow the actual local fluid velocity immediately; they carry no launch velocity or inertia and apply no force back to the medium.
- Positional diffusion uses D = 120 world units²/s per axis, versus 6 for material particles. Each displacement adds normal noise with standard deviation sqrt(2 × D × elapsed time).
- Lifetime is exponentially distributed with a 0.2/s hazard: mean 5 seconds, half-life about 3.47 seconds. Sampling the lifetime once is equivalent to a constant per-second stochastic decay hazard, not a fixed-duration timeout.
- Expiry uses the simulation clock even outside the active view. Dormant movement/emission still pauses, but old offscreen messages cannot revive when the camera returns. Editing/settings pause the simulation clock.
- Pheromones ignore particle chemistry, pair repulsion, cell exclusion and reef collision. They do not feed cells, block receptors, consume toxin or contribute material mass. They have no binding orientation.
- Constant emission and rapid decay give roughly 40 live points per continuously active cell at equilibrium. This is an expectation, not a hard particle cap. Flow and diffusion create a short upstream spread and a long downstream tail; stagnant water instead produces a diffuse cloud.

Native CPU, GDScript and the optional GPU transport experiment use the same motion rule. Pheromones stay out of reaction-neighbor bins. GPU transport remains opt-in.

## Presentation

Small pale-coral points identify pheromones, independently of source occupation. They render at their true transported position even through cells and reefs. The local inspection lens names them and shows reported size, armed/unarmed status and signal age; it never reads updated source state. Existing branch/fork artwork and binding orientation remain for reacting species.

This is inspired by advected chemical cues and microbial chemotaxis. Literal coordinates, size and hostility in one particle, universal signaling, pass-through solids and the chosen lifetimes are deliberate gameplay abstractions. See [references](../references.md#pheromone-plumes-and-chemical-perception).

## Validation

Validation on Godot 4.7.2 / Linux, Ryzen 9 9950X and RTX 5080:

- Full suites: **2,228 native assertions and 1,169 reference assertions, zero failures**. Coverage includes absent/stale/expired reports, received size and hostility changes, no source lookup, own-lineage recognition, receptor competition/cleaning, torus seams, physical pass-through, both rendering paths, inspection and autonomous hunting.
- The 10-second constant-current distribution fixture retained 528 points: 521 downstream, 7 upstream, and 157 more than 150 world units downstream. Mean displacement was about 111 units downstream. Reference results had the same distributional behavior.
- Native/reference transport matches for identical ordered inputs. Incremental versus rebuilt spatial grids may assign diffusion draws to different particles during longer ecological runs; cross-backend trajectory identity is not promised.
- Optional GPU comparison: 3,880 mixed particles including 120 pheromones; maximum position difference 0.000062 world units and angle difference 0.0000011 radians. The GPU experiment remains opt-in.
- Visual inspection covers the 80% play view and local pheromone lens. Source reports are displayed without moving points to the cell boundary.

### Wide-view performance

1440 × 900, Mobile Vulkan, 80% playable view, music enabled, bloom enabled, 12 warm-up frames and 36 measured frames per fixture. Frame times include rendering and live simulation, not just particle kernels.

| Fixture | Previous revision, same busy host (median frame ms) | Pheromones (median frame ms) | Previous / new CPU tick EMA ms |
| --- | ---: | ---: | ---: |
| Normal | 32.79 | 32.71 | 3.99 / 4.32 |
| Dense material particles | 82.59 | 81.92 | 8.93 / 8.71 |
| Large cell | 41.54 | 41.02 | 3.67 / 3.92 |

The initial implementation scanned all material every tick to expire pheromones. It has been replaced with a small reference list containing signals only; expiry also skips reaction-neighbor work. The first scan-based dense/bloom run measured 96.65 ms and 45 audio underruns; the signal-list run measured 81.92 ms and 15 underruns. These are short, noisy runs under other host activity, not a controlled estimate of the optimization's independent benefit.

A previous-revision checkout under the same busy-host conditions measured 82.59 ms and 20 underruns in the dense/bloom case. Earlier, before host activity increased, that revision measured 52.49 ms and no underruns. The evidence supports comparable performance under contention, **not a claim that wide-view performance is solved**. Dense scenes still fall well short of 60 FPS and can starve audio under load. No extrapolation to the owner's RTX 3090/Threadripper machine is claimed.

The same six cases are also exercised with music disabled. Private project records retain all stages, the temporary baseline's identity, GPU output, source hashes and detailed validation.

