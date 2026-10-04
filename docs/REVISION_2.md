# Revision 2 — living cells in a liquid ecosystem

Status: design specification from the owner's playtest feedback, October 4, 2026. This document describes the next revision; these features are not implemented in the current build. Implementation follows resolution of the remaining design questions below.

## Preserve what works

The owner played the first prototype and found that swapping organelles gave substantial control over an autonomous cell. Preserve that indirect control and readable behavior. Keep the existing six organelle categories and assembly pause. Organelles retain innate responses; do not introduce a player-programmed rule editor or wiring system. Preserve the bright, cartoony, vectorized cellular art direction.

The target is Godot installed through Steam on a separate Linux machine unavailable to this task. Shipping platforms and permanent progression are not being expanded in this revision.

## Anatomy, mass, and shape

- Remove the eight-slot limit. Organelles float on the membrane and can move along it, subject to physical packing and available surface area.
- Retain attachment/resource costs, but impose no arbitrary organelle-count cap. Additional mass and inertia are physical tradeoffs.
- Biomass determines internal volume. Growth supplies more membrane surface for organelles, increases inertia, slows response to the same propulsion, and exposes more surface to damage.
- Track mass incorporated in the body, reserves, and organelles consistently. Assembly and repair must not duplicate biomass. Volume must respond to retained biomass rather than only a lifetime food counter.
- Retain hydrostatic pressure as the basis of the membrane shape. Add internal microtubule-inspired tension elements that can support noncircular shapes against that pressure.
- Organelle mass and location affect both translation and rotation. A heavier cell or an asymmetric attachment pattern should have observable consequences.
- Organelle damage precedes body damage. Organelles repair themselves by consuming biomass. The exact spatial damage-routing rule is an open question below.
- Preserve a distinct role for the existing regenerative organelle when baseline organelle self-repair is added; it could accelerate repair or repair the body. The final balance must make its cost meaningful.

The game still presents a 2D world. The implementation must explicitly document how effective volume, surface capacity, mass, and rendered dimensions relate; it must not claim to solve full 3D cell geometry.

## Contact and the liquid medium

The reported clipping/teleportation through a hunter when cornered is a defect. Fix contact handling itself, with regression scenarios for compressed and overlapping cells, independently of removing the walls.

The fluid must carry meaningful mass relative to cells. Cell motion must displace or accelerate surrounding fluid, and the fluid must exert forces back on cells. Local currents and eddies must affect swimming, collisions, and the transport of chemical particles. A passive flow animation does not satisfy this requirement.

Prototype and measure the coupled cell/fluid system before scaling up the ecosystem. Select the numerical method against evidence for stability, momentum exchange, deformation, and performance. Keep externally driven currents, damping, and other modeled momentum/energy sources explicit.

## A continuous microscope view

- The map wraps, with no visible boundary or corner traps.
- The camera follows the player's cell. Crossing a world seam must preserve continuous visible motion and local interactions.
- Use a microscope-like vignette around the camera view.
- Full simulation runs near the center. Activity slows through the darkened fringe.
- Outside the camera's active region, simulation stops. Organisms and resources retain their state rather than continuously advancing offscreen.
- Explicit game triggers may change dormant state, such as population replacement or a habitat event. Record those changes distinctly from simulation ticks.
- Resume nearby state without duplicated resources, time jumps, sudden impulses, or visible spawning. Keep wrapping distance calculations consistent for physics, sensing, feeding, fluid coupling, and rendering.

This supports a larger stored ecosystem while bounding the actively simulated region. Camera framing and any later zoom feature must preserve a useful activity budget and avoid obvious pause/unpause artifacts.

## Shared organisms, damage, and death

Player and non-player cells use the same core organelle, mass, sensing, metabolism, damage, repair, feeding, and death systems. Their anatomy and innate responses can differ; hunters must not receive an invulnerability/reset exception.

A killed hunter yields a substantial nutrient resource appropriate to its biomass. Death removes that individual. Population replacement creates a different individual through an explicit ecosystem rule, preferably beyond the visible region; it must not silently refill the dying hunter's health.

## Chemistry with ecological consequences

Use recognizable substances and consistent reaction rules, with internal particle signals connecting sensing to organelle activity. The player does not configure signal-routing circuitry.

Waste must participate in the ecosystem rather than only disappear as a visual effect. Proposed first role: waste/debris enters a resource-limited decomposition and recycling chain, influencing local nutrient availability and oxygen demand. Specify the energy input and conversion losses so recycling cannot create unlimited food or energy.

Transport food, oxygen, waste, signals, and offensive chemicals through the same local fluid environment where appropriate. Make chemical differences readable without requiring the player to manage a molecular inventory manually.

## Several viable ways to thrive

This is a central design requirement, not an optional later polish item:

- Environmental feeding: consume resources available in the medium.
- Carnivory: damage or kill other cells and obtain their biomass.
- Engulfment: sufficient size and feeding capability allow consumption of smaller cells.
- Parasitism: extract resources from a larger living host using a proboscis-like feeding adaptation.

The scope and presentation of specialized feeding adaptations within the fixed organelle list is an open question below. Do not silently add a seventh organelle.

Use a common survival/growth objective that can be reached with different diets. Avoid a victory counter that only credits environmental nutrient particles. Costs, anatomy, risk, and resource conversion should distinguish feeding strategies.

## External pressures

Introduce understandable run/habitat conditions that encourage adaptation:

- Scarce environmental nutrients make predation or parasitism valuable.
- Abundant nutrients with heavily armored, difficult-to-kill hunters reward protection and sustained repair.
- Local chemistry and currents can alter which anatomy is effective.

Dangerous hunters remain governed by the shared rules. Near-invulnerability should arise from their build and available resources. The goal is several viable strategies across different conditions; no single mandatory anatomy should solve every run.

Persistent campaigns, roguelike unlocks, inheritance, and other metagame decisions are deferred. They are not prerequisites for this revision.

## Proposed implementation sequence

1. **Physical foundation and continuous view:** replace wall-bound contact with wrapping coordinates, a following microscope view, and an explicit active region. Build and validate significant two-way cell/fluid coupling and stable cell contacts.
2. **Living anatomy:** free membrane placement and packing, biomass-dependent volume/mass/inertia, pressure plus internal tension, and organelle damage/self-repair. Preserve the ease of paused anatomical changes.
3. **Shared ecology and resource cycles:** migrate other organisms to the same systems, implement actual hunter death and replacement, make waste consequential, and extend particle signaling.
4. **Feeding strategies and environmental pressures:** implement the agreed feeding scope, vary habitat conditions, and demonstrate contrasting viable builds. Profile on the target Linux machine before choosing native/GPU acceleration.

Each step should remain playable and have focused behavioral and numerical checks. The fluid/body coupling experiment is the main technical feasibility step; do not postpone it until after building a large ecosystem on an unsuitable motion model.

## Acceptance evidence

- Organelle capacity follows available membrane surface; motion responds to added mass and asymmetric inertia.
- Pressure and internal tension support stable noncircular cells through growth, contact, and fluid forces.
- Contact stress does not teleport a cell through another cell.
- Currents move cells, and moving cells measurably move the surrounding medium.
- World seams are visually continuous and preserve interactions.
- Dormant state is unchanged by ordinary ticks; explicit triggers are the only offscreen changes. Waking preserves state and resource accounting.
- Local particle interactions cause feeding, signaling, offensive effects, and chemical transformations.
- Organelles take damage and spend biomass on repair under the agreed rule; regenerative organelles remain useful.
- Hunters can die once, release accounted-for nutrients, and be replaced without a health-reset loophole.
- Different diets/builds can reach the same growth/survival objective under suitable environmental conditions.
- Performance evidence includes active organism/particle counts and target-machine CPU/GPU/frame timing. No unmeasured scale or frame-rate guarantee.

## Remaining questions

1. **Damage routing:** Does an attack damage organelles at its contact location, allowing exposed membrane to be hurt while other organelles survive elsewhere, or do all organelles collectively protect the body until they are depleted? The proposed default is local contact-based damage because it makes placement matter.
2. **Feeding scope:** Should proboscis/parasitic feeding arrive now as a specialization of the existing feeding organelle, or remain a planned path while this revision establishes grazing, hunting, and engulfment with the current set? Do not infer permission for additional organelle categories.
3. **Performance target:** The CPU, GPU, RAM, and installed Steam Godot version of the player's separate Linux machine are still unknown. These inform the coupled-fluid budget and playtest instructions.
