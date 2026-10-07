# Revision 24: affordable anatomy, active foraging and cilia

This revision gives the cell more ATP headroom, a choice of locomotion, and tunable following/exploration. A grazing pore approaches useful local food patches instead of letting one nearby speck dominate a large distant clump. Death remains visible before the camera follows a paid successor. Water wakes respond to relative flow.

## Starting anatomy and cilia

The player starts with **one grazing pore and neither cilia nor a flagellum**. Both propulsion organs remain separate fixed-size choices in the cell's assembly factory. Each costs **eight usable tissue and one AP**. Neither replaces the other; both can coexist and offspring inherit purchased anatomy. Existing NPC flagella remain.

A cyan band of short beating cilia supplies axial thrust of 1,800 versus a flagellum's 2,600, at 0.16 ATP/s for movement. It additionally pumps local water toward its membrane attachment at 0.08 ATP/s. Its inflow reaches 170 world units with a target speed of 52, versus a pore's 110-unit reach and speed of 24. These are field targets with distance-dependent relaxation, not guarantees of packet or cell speed.

The inflow is strongest on the side selected by the existing receptor or exploration heading. Cilia add no nutrient or prey senses and do not absorb particles; a pore still consumes food. The current also draws toxins and other chemistry. Fluid and body receive equal/opposite linear and angular momentum. Detailed and coarse simulation call the same pump/motion functions; coarse pore capture also measures local relative water delivery. There is no hidden intake or physiology bonus.

A distinct synthesized flutter-pluck pattern makes cilia audible within the existing original progressive techno arrangement. The generated bank now has seventeen instruments; native and reference mixing retain bounded voices and the independent sample clock.

## ATP headroom

| Shared parameter | Previous | Current |
| --- | ---: | ---: |
| Basal ATP/s × growth scale | 0.264 | 0.18 |
| Flagellum / active pursuit ATP/s | 0.30 | 0.20 |
| Pore pumping ATP/s | 0.18 | 0.10 |
| Secretion ATP per chemical packet | 0.15 | 0.10 |
| Aerobic ATP per substrate unit | 5 | 7 |
| Fermentation ATP per substrate unit | 2 | 3 |
| Emergency tissue mobilization threshold | 20 ATP | 10 ATP |

The upkeep preview and actual resource ledger use these same parameters. Repair, combat, tissue/AP prices, oxygen limits, gut/storage capacity, tissue yields and fermentative material loss remain unchanged. ATP still requires finite fuel. Starvation still hurts, and excessive anatomy still has operating costs. The changes apply to players, NPCs and both simulation tiers.

## Signals compete with exploration

In build mode, click the **nucleus → Behavior** to tune exploration weight and a **2/4/8-second** response cycle. Installed steering organs keep their existing priority weights. For the currently selected drive, following time is:

`signal weight / (signal weight + exploration weight)`

Defaults are signal 100%, exploration 25%, and a four-second cycle: **80% following / 20% exploring** when a valid signal is available. The remaining part follows a persistent seeded wandering heading, independent of body rotation and biological random draws. With no signal the cell explores. Sensing and bounded memory continue throughout; explicit flight overrides the cycle. Zero steering never disables suction, absorption or photosynthesis. Child cells inherit both settings; editing them has no tissue/AP/ATP charge.

Grazing reuses the existing local nutrient query, accumulates wrapped mass moments in bounded spatial bins, and selects a three-by-three-bin neighborhood by mass with a mild distance penalty. It follows that patch's centroid until within an inner threshold, then targets an actual nearby packet. Separate opposing clouds cannot cancel each other into an empty midpoint. This gives no awareness beyond receptor range. Hunting continues to use immutable local pheromone reports and excludes family.

## Death and relative water cues

Actual death immediately releases ordinary lysis resources and activates the ordinary prepaid successor. The presentation snapshots the deformed membrane without new material or random draws. Membrane fragments spread outward and fade for 1.8 seconds. The camera holds the death site for 1.15 seconds, then eases to the successor over 0.65 seconds. Ecology, crisis time and music continue; no invulnerability or reward is added. Settings pause the presentation. Editing and particle magnification wait until the short handoff ends.

Cell wakes sample water outside six points of the deformed membrane, subtract body translation, and rotate that vector once into the membrane frame. Stationary plant wakes use local water minus zero obstacle velocity. Wake travel responds to relative speed; downstream glints disappear under co-moving uniform flow. Wakes remain beneath all cell bodies, with no screen distortion or shake.

## Validation

- Native suite: **4,349 assertions, zero failures**. Reference suite: **3,222 assertions, zero failures**. Native-only differential checks account for the count difference.
- Tests cover finite-resource ATP sustainability/starvation, patch choice and periodic seams, weighted response duty, flight priority, inherited settings, real paid locomotion purchases, momentum/ATP accounting, destroyed or depleted cilia, no ciliary sensing/absorption, coarse execution, death framing, presentation-only state, and Galilean/frame invariance of wake inputs.
- Seventeen finite distinct synthesized instruments and native/reference mixer parity pass.
- OpenGL Compatibility and Vulkan Mobile scenes compile and render on the RTX 5080. Assembly and behavior controls are inspected at 175% UI scale; death fragments and relative wakes are inspected at the 80% play limit.

### Controlled economy trials

Before/after fixtures kept the same original pore-plus-flagellum anatomy, seeds 41/846/20261004, and 120 simulated seconds at the 1440×900 viewport's 80% view. These isolate economy and foraging changes; they predate the final bare starter and cilia.

Median approximate ATP spending falls from **101.9 to 66.3** for the original starter and **138.1 to 89.2** for the expanded photo/two-flagellum fixture. The tight hunting seed ends at **85.9 ATP versus 20.0**, while other seeds take different food trajectories. Not every run gains more tissue or food. Integrated rolling-ledger rates are approximate, not an exact transaction sum. All eighteen runs survive the two-minute horizon.

Final opening trials use the actual bare starter, or a real one-AP/eight-tissue cilia or flagellum purchase, for sixty simulated seconds on the same three seeds:

| Opening | Final ATP range | Final usable tissue range | Low ATP / reserve mobilization |
| --- | ---: | ---: | --- |
| Bare pore | 105–108 | 40.5–42.1 | None |
| Purchased cilia | 105–116 | 35.6–37.3 | None |
| Purchased flagellum | 116–119 | 38.5–41.1 | None |

All nine remain alive and retain tissue to buy another organ. These automated openings establish headroom, not long-expedition balance or evidence that one propulsion choice is universally best.

### Live frame measurements

Measured at **80% zoom, 1440×900**, with eight seconds of live wall time per run. The trace excludes its initial boundary sample; 479–480 physics ticks advance 7.98–8.00 simulated seconds. Each frame has at most one tick and no audio skips.

| Fixture | Renderer / music | Mean FPS | Mean frame ms | p95 frame ms |
| --- | --- | ---: | ---: | ---: |
| Dense, paid flagellum | OpenGL / on | 143.9 | 6.948 | 15.867 |
| Dense, paid flagellum | OpenGL / off | 147.5 | 6.778 | 15.649 |
| Dense, paid cilia | OpenGL / on | 158.5 | 6.307 | 15.406 |
| Dense, paid cilia | Vulkan Mobile / on | 147.9 | 6.762 | 16.047 |
| Large cell, paid cilia + flagellum | OpenGL / on | 332.3 | 3.009 | 8.129 |

Dense runs retain sixteen cells, with five to eight active. They store **11,126–14,410 packets** and simulate **2,117–3,674 active packets**, depending on renderer/end-frame sampling and anatomy. Flagellum music-on/off runs have matching simulation counts and trajectories. Cilia changes flow/trajectory, so its higher FPS is **not** an isolated cilia optimization claim. Music preparation averages 0.024 ms/frame in the flagellum run.

The growth fixture uses 9,216 starting usable tissue regardless of its paid locomotion selection. It ends at radius **231.2 world units**, with about 850–950 active packets; its lighter particle load explains why it is faster than the dense fixture. It is not a combined dense/giant-cell result. No particle population or simulation horizon is reduced to produce these timings.

The muted trace completed, then its headless Wayland shutdown stalled. The verified owned process was terminated after capture; the complete measurement was retained. Other final traces and shader captures shut down normally. Weston reports missing FIFO/desktop protocols; these are compositor limitations, not game script/shader errors. No repeatable performance improvement over Revision 23 is claimed from unpaired shared-host runs.

The owner's Steam Godot 4.7.2 / RTX 3090 / Threadripper 2990WX machine remains untested. Workstation measurements use Godot 4.7.2, Ryzen 9950X and RTX 5080 under an owned headless Weston compositor. Dummy audio exercises preparation/mixing without validating physical speaker output. Frame pacing differs from a normal desktop, and shared-host timings are not a hardware guarantee.

## Scientific motivation

[references.md](../references.md) distinguishes ciliary flow/swimming, microbial nutrient-patch exploitation, exploration tradeoffs and competing ATP allocation from the game's numerical balancing and simplified spatial/current rules. Death glints and camera timing are presentation choices.
