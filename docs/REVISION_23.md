# Revision 23 — resource budgets, size drag and stronger water cues

Nutrients no longer collide with plant stems, removing hard barriers that held food in spaces a grazer could not enter. Stems remain solid to cells and spikes. All chemical species share this permeability in foreground and staggered offscreen transport; coarse feeding and toxin/decoy exposure no longer add a chemical wall. Hidden spike hunting still requires a clear solid path. Intake consumes the same real finite packets, with unchanged capacity, rates, metabolism and material accounting.

Current-driven clouds remain possible, but patches formerly collected solely by stem collision can disperse. No repulsion, extra food, automatic consumption or surface retention is introduced. Mild reversible retention on exposed fronds remains a possible follow-up. Historical packet-contact helpers are retained only for explicit diagnostic comparisons and default off.

## Presentation and controls

- Flow trails show **8.4 seconds of path history**, up from 2.8 seconds, with a **20-second** fading lifecycle. Their 24-segment strips use 16 bounded midpoint integration steps in the cached signed flow field. Seed coverage extends farther upstream; the limit remains **640 strips**. One periodic image per strip prevents seam-spanning geometry.
- **AP:** small fixed gold blobs beneath the top-right tissue stock in build mode, **one blob per available adaptation point**. Zero shows an empty outline. Internal spinning coins, their invisible click target and transfer animations are removed. ATP remains the internal sac; spending rules are unchanged.
- **Locked follow zoom** always centers on the cell, clearing an earlier wheel/pan offset. **Free view** keeps cursor-centered zoom. Existing 80%–12× limits and pause/edit behavior remain.

Particle beat pulsing, its per-frame source preparation and its settings slider are removed. Oriented particle glyphs keep their steady appearance. Progressive techno and anatomy/lineage/environment/event music remain.

## Price previews

Hovering a construction or organ-upgrade choice (or focusing it with the keyboard) shows its real tissue/AP costs beside available stock. Required AP uses the same one-point gold blobs, with a shortfall tint. Exact tooltips remain; zero-AP restoration is visibly free. Previewing never spends resources.

## Stronger water cues

Cell wake geometry extends to 1.95 times the actual deformed outline (previously 1.42), with slower, broader and brighter bands. A separate lower layer shares the cached mesh and draws beneath every cell body. Plant-stem wakes are wider and longer. Slow periodic caustic brightness patterns cover only the background water; they never sample or warp the rendered cells, particles, interface or camera. Settings can disable **Water shimmer (background only)**. Animation uses simulation time and pauses during editing. These are stylized submerged light/disturbance glints, not a new physical wave solver.

## ATP income, spending and organ upkeep

Build mode shows **ATP in/s** and **ATP out/s** as two translucent sacs on one area scale. Incoming means gross ATP production; outgoing means actual paid expenditure. Surplus/deficit is production minus spending. Hovering an installed organ adds a third **Organ/s** sac for its recent actual drain; hovering a construction/upgrade choice shows a **Steady/s** sac for the proposed upkeep estimate. All three share the same area-per-rate scale. Upgrade tooltips give the change from the existing organ before purchase.

ATP-sac hover gives exact production, spending, production surplus, reserve change and unused production at capacity. Organ hover gives its steady estimate/share and recent actual spending/share. Accounting uses **12 quarter-second bins**, up to three seconds, and pauses with cell time. Repairs, movement, pumping, secretion, combat, acidity and receptor cleaning are attributed separately. Reserve funding/reclaim transfers are excluded from the operating budget. Early averages use a minimum quarter-second observation interval.

Steady estimates include flagellar strokes, pumping and expected secretion at full operation, plus trait upkeep; conditional pursuit, repair and combat costs appear in recent actual expenditure instead. They are not a promise that conditional production/attacks will always occur. Income overflow at a full sac is reported, avoiding confusing gross production with the stored-reserve change. Existing ATP departures remain, with bounded incoming packets to the sac when ATP is actually stored.

The bookkeeping changes no costs, capacity, metabolic yields, reaction rules or random draws.

## Size-dependent drag

Total membrane drag is **90 × radius / 47**, shared across the same six fluid contact points. A baseline-radius cell keeps its previous drag; larger cells encounter greater resistance and a lower top swimming speed at equal propulsion. The implicit equal/opposite impulse still transfers momentum to the finite fluid, and currents can carry cells without an artificial speed cap. Offscreen hunting mobility uses the same drag coefficient in its existing coarse estimate. ATP costs, mass and thrust are unchanged.

## Validation

Godot **4.7.2** passed **4,293 native** and **3,166 GDScript-reference assertions**, zero failures or script errors. Checks cover chemical permeability in both transport tiers/backends, retained cell-solid stems, finite offscreen feeding, follow/free zoom, AP/upgrade prices, bounded pause-stable ATP accounting, capacity overflow, actual limited payments, unchanged RNG/resources with accounting disabled, and conservative size-dependent drag. Both suites include a 90-second ecosystem and autonomous hunting.

In a stationary-water terminal-speed fixture, a baseline cell with one flagellum reached **28.292 world units/s**; doubling radius at equal propulsion gave **14.316**. Two flagella on the larger body gave **28.416**. This isolates swimming from current advection.

**OpenGL Compatibility** and **Vulkan Mobile** rendered the new cues without shader/runtime errors. Inspected tissue/AP prices, ATP expense breakdown, 175% text, long trails and clear cell silhouettes. Native compilation used **eight jobs**, after checking host capacity.

| 80% zoom, music/bloom on, 1440×900 | Mean frame | Mean FPS | p95 frame |
| --- | ---: | ---: | ---: |
| Dense live, 11,160–13,738 stored / 2,440–3,642 active particles | 8.567 ms | 116.72 | 17.648 ms |
| Large-cell live fixture | 3.145 ms | 317.96 | 8.398 ms |

Dense: 480 ticks over 8.002 wall seconds; large-cell: 479 ticks over 8.001 seconds. Neither had catch-up/capped frames or audio skips. Large-cell results use fewer particles and are not a dense-plus-growth combined stress result.

At equal 240-tick dense horizons, ATP bookkeeping off/on measured **9.561 / 9.664 ms per CPU tick** (about **0.103 ms**, 1.1%). Elapsed time, particle count and all three RNG states agreed; this is a CPU comparison, not rendered FPS.

Frozen 14,391-particle comparisons kept seeds, camera, cells and fluid identical. The first short/long-trail means were 3.671/2.988 ms, with clear shared-load noise. Reverse-order repeats measured **2.773 ms short / 2.734 ms long**. Water cues off/on repeated at **2.755 / 2.734 ms**, with **406 / 412 draw calls**. These measurements do not establish a meaningful frame-time penalty or speedup; they show bounded extra geometry/draw work. Frozen results are not playable FPS.

Measurements used a shared **Ryzen 9 9950X / RTX 5080**, NVIDIA 595.91.07, owned headless Wayland compositor and CPU affinity 14/15. Dummy audio exercised music preparation/buffering, not a physical output device. The owner’s Steam RTX 3090 / Threadripper 2990WX machine remains untested. Short fixtures do not establish whole-expedition balance or future crowded-scene performance.

Scientific motivation and game abstractions are recorded in [references.md](../references.md#particle-permeable-plant-like-colonies).
