# Revision 17 — collisions, hunting receptors and impact weapons

Cells now exchange momentum and rotation when they collide, compress against one another and solid stems, and physically catch on spikes. Hunting perception belongs to a separate organ.

## Hunting and flight

The assembly factory offers a **Hunting receptor** for **six tissue and one AP**, also selected with **V** while editing. It uses a coral inward-hooked fork, distinct from the violet flight receptor. Its rhythm and register are distinct while sharing the bounded receptor timbre bank. Ordinary placement, crowding, recycling, damage, repair, inheritance and paid offspring costing apply.

The hunting receptor samples pheromones within **120 world units** of its own location; the flight receptor retains **90**. Traits, scale and decoy occupancy modify those ranges. The sensing overlay now draws those actual radii and no radius around a spike.

A received source is eligible if its **reported total organic mass is smaller**, or its report says **undefended**. At emission, defended means at least one functioning spike, toxin vesicle or protective cortex. This is a coarse anatomical report, not knowledge of armor coverage, an exposed side, intentions or current health. Missing defense fields conservatively mean defended.

Only the newest locally received report from each source participates. Later movement, growth, armoring or death cannot rewrite the snapshot; the existing signal expiry and at-most-1.2-second steering memory still apply. Own-lineage reports are ignored. Flight takes priority when both receptors respond. Destroying/removing a receptor clears its pending signals and steering memory.

The receiving organ faces the reported location. Hunting guidance and flagella provide motion through the existing fluid momentum coupling; spikes provide neither sensing nor steering. Toxin vesicles use hunting/flight reports. NPC hunters carry the same hunting organ; there is no hidden enemy sense or role-based speed/damage bonus.

## Contact response

- Cell contacts use the deformed radial membrane and its local surface normals. Off-center normal forces and tangential friction generate rotation, while equal/opposite impulses transfer motion between fully active cells.
- Restitution is **0.12** for closing speeds above six world units/s; slower resting contacts do not bounce. Coulomb friction is limited to **0.38** of the normal impulse.
- Contact dents spread across nearby membrane nodes, preserving enclosed area by redistributing the displacement. Compression is bounded; polar node ordering and the existing pressure/tension solver keep the membrane renderable and let it recover.
- Stem contact uses the approach-side membrane radius instead of blocking the entire maximum-radius circle. Sweeps stop fast crossings; friction makes a cell rotate and slide along a branch.
- Spikes physically obstruct other cells, including relatives, and catch solid plant stems along their shaft. Sweeps handle translation and sample rotation over the three existing motion substeps. Fine fern foliage remains permeable.
- Position correction is separate from velocity response, so fixing an overlap does not create a launch impulse. Motion then continues to exchange momentum with the surrounding fluid through the existing drag coupling.

This remains a bounded radial/shaft approximation. It is not full concave soft-body contact, deformable plant mechanics or a new fluid solver.

## A few good impacts can kill

The owner explicitly accepts prey bouncing away if a few hits can kill and wants mobility to matter. Spike injury now includes **0.9 × normal impulse / prey mass**, capped at **45 health per impact**, only for contact closing speed of at least six world units/s. This mechanical component works without ATP. Tangential brushing earns less normal impulse; resting overlap alone cannot manufacture impact damage.

Slow pressing retains the existing ATP-funded injury: 1.2 ATP/s for a standard spike and 12 damage per ATP, modified by its ordinary traits. Protection and other contacted organs take damage before exposed membrane, and real tissue loss stays in the material ledger. Relatives are physically obstructed but exempt from spike injury under existing lineage recognition.

Thrust, turning, mass and alignment determine impact opportunities. Spikes placed around a forward hunting receptor can catch prey during repeated approaches; a lone poorly aligned spike may push past it. Stronger impacts do not guarantee every predator a kill. There is no direct steering, auto-aim or automatic charge/backoff behavior.

## Validation

Godot **4.7.2**, Linux: **3,271 native assertions** and **2,212 GDScript reference assertions**, zero failures. Rendered interface checks pass **143 assertions each** on Vulkan Mobile and OpenGL Compatibility; Compatibility uses llvmpipe and is a correctness check. Import and whitespace checks pass. The illustrated hunting choice and tooltip were inspected at 100% and 175% interaction scale.

Coverage includes linear momentum transfer, non-increasing contact kinetic energy, glancing rotation, membrane area/triangulation/recovery, torus seams, dormant boundaries, fast stem and spike crossings, initial overlap on a stem, passive impact injury, local armor, lineage recognition, absent/stale/expired reports, defense snapshots, receptor removal, flight priority and candidate-rejection parity.

A contact fixture kills an exposed cell in **three strong collisions**, despite one second of normal repair between the first two. A separate comparison shows much greater damage at 160 than at 20 world units/s. These fixture speeds are test inputs, not a promise about every natural encounter.

A 30-second autonomous fixture places two spikes around a forward hunting receptor with a flagellum and grazing pore. Both backends kill prey and metabolize its released food. A lone offset spike in an exploratory fixture often shoved past prey without a kill; that tradeoff is intentionally retained rather than corrected through hidden aim or guaranteed kills. These probes do not establish the whole expedition's difficulty balance.

### Wide-view cost

Workstation Ryzen 9 9950X / RTX 5080; 1440×900 Xvfb, native simulation, Vulkan Mobile, Dummy audio. All cases use the **80% widest playable view**, 12 warm-up frames and 36 measured frame intervals. Dense has four times the initial particle packets; growth has 256 times unspent player biomass. CPU tick is the smoothed physics-step measurement, separate from whole-frame intervals. Runs were serial; other host activity still contributes noise.

| Fixture | Bloom | Music-off median ms | Music-on median ms | Music-on p95 ms | CPU tick ms (on) | Audio skips (on) |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| Normal | Off | 33.464 | 33.588 | 34.595 | 6.644 | 0 |
| Normal | On | 33.636 | 33.705 | 35.798 | 6.344 | 0 |
| Dense | Off | 111.176 | 112.080 | 138.454 | 10.228 | 65 |
| Dense | On | 113.833 | 113.570 | 138.802 | 10.182 | 70 |
| Growth | Off | 49.376 | 49.517 | 50.433 | 6.707 | 0 |
| Growth | On | 49.541 | 59.605 | 67.317 | 6.932 | 0 |

**Performance remains inadequate in dense scenes.** Final medians are roughly 34 ms normal, 111–114 ms dense and 49–60 ms growth. Dense audio refills still underrun. Revision sixteen recorded approximately 33, 100 and 47 ms respectively; these short evolving fixtures and changing host load do not isolate the new contact cost, and the measurements do not support a 60 FPS claim. Further rendering/physics optimization remains open.

The first implementation unnecessarily swept distant cells for every spike. Conservative distance rejection and one shared nearby-stem query now avoid that work without changing the tested result. An isolated 19-cell, one-active-spike stationary microbenchmark fell from **85.07 to 10.77 μs per call** with rejection enabled. That fixture excludes terrain and injury and measures only spike queries, not whole-game throughput. The early live run's higher dense times cannot all be credited to this optimization.

The owner's separate RTX 3090 / Threadripper Steam machine and physical audio output remain untested. No new particle caps, in-view dormancy, weaker chemistry or hidden predator bonuses were used to obtain these results.
