# Living cell architecture

## Authoritative simulation

`simulation.gd` advances at 60 Hz independently of scenes and UI. Players and NPCs share `cell.gd`, anatomy, resources, damage, sensing, feeding and death. Initial roles choose anatomy; they do not supply invulnerability or separate pursuit logic. Reproducibility is tested on one engine/platform, not promised across platforms.

The 4096 × 2560 torus uses nearest-image offsets throughout physics, sensing and rendering. The microscope defines an active ellipse: full activity centrally, slower at the fringe, frozen outside except explicit triggers. Persistent spatial buckets update when particles cross them; compaction/rebuild occurs twice per second. The tide and bilinear fluid sampler reuse storage. Replacement is deferred if no whole organism fits outside the current view.

A tick updates activity and fluid, pumps through mouths, transports particles, runs chemistry and biology, solves membrane/network constraints, advances three motion/contact substeps, feeds between cells, applies toxin contact and excludes external particles from bodies. Material accounting includes body, biomass, organs, gut substrate and waste. Death transfers material once and records any population replacement as external input.

## Anatomy and movement

Effective volume is body plus available biomass; projected radius follows its cube root without an arbitrary upper cap. Perimeter, scaled organ footprints and available biomass limit anatomy. Food, oxygen and ATP capacity, digestion and basal consumption scale with effective surface area. The finite torus remains a practical geometric limit to extreme growth.

Each organ has a material membrane coordinate, stable ID and linear scale. Cost and maximum health scale with area. Flagellum thrust scales with area. Installation fixes the new anchor and projects neighboring arc intervals in both directions to remove overlaps while preserving their order. Ordinary flow does not slide organs. Shrinking below total occupied surface can shed organs as accounted-for material.

For a more responsive game, effective inertial mass is 0.45 times retained organic mass and rotational inertia is 0.22 times the prior distributed-mass moment (with small positive floors). Material bookkeeping is unaffected. A signal distinguishes the direction to face from the direction to swim. The detecting organ faces food/prey/threat; flagella translate toward food or away during explicit flight. A damped angular controller applies paired steering impulses to the body and medium. Translation and off-center flagellar thrust likewise deposit opposite impulses into the fluid. This is a flexible flagellar steering abstraction, not rigid nozzles or direct player steering.

## Gel membrane and editable cytoskeleton

`membrane.gd` solves 28 ordered boundary nodes with compliant edge constraints, enclosed-area pressure, damping, local fluid traction, and a softly contracting cortex. Local rest lengths vary without an elliptical target. Bending resistance suppresses node-scale wrinkles; area correction preserves the effective volume projection. Membrane contact still uses swept radial body extents and mass-weighted separation, not a full soft-body contact manifold.

`cytoskeleton.gd` implements a tension network. An endpoint can attach to a fractional membrane edge or a free internal junction. Selecting a point along a link splits it into segments and creates a movable junction; the original segments retain one group for tension editing. Connections can join two membrane points, a membrane and a tube, or points on two tubes. Multiple points on the same tube can also be materialized. Removing a group preserves junctions still used by other links and drops unused ones.

The tension slider is a game control, not newtons: 0–100% changes the target length from the original span to 35% of that span. Rest lengths scale with cell growth. Tension-only compliant distance constraints pull weighted membrane anchors and junctions together; enclosed-area pressure resists collapse. The four initial weak links are ordinary editable members of the network. Building and tension adjustment preview membrane relaxation during paused assembly; they currently have no resource cost.

To prevent the reported polygon triangulation failures, boundary nodes stay in ordered angular sectors and rendered outlines interpolate positive radii across those sectors. Cartesian spline overshoot can form loops; the radial spline cannot cross itself under these invariants. Maximum extent is measured from the deformed boundary for broad-phase tests. This stabilized model remains star-shaped: arbitrary folding, holes through the cell, division, and a full cytoskeleton material model are not implemented.

## Fluid, feeding and chemicals

The medium has 64 × 40 velocity nodes, spacing 64, mass 22 per node. Symmetric viscosity conserves linear momentum when external forcing is disabled. Weak relaxation toward a periodic eddy field is an explicit external tide. Six body points exchange implicit drag impulses, including rotational motion. The model is a finite-mass viscous medium, not incompressible Navier–Stokes: no pressure projection or fluid volume exclusion is claimed.

An ATP-funded feeding pump drives local wet nodes toward its opening and returns opposite linear/angular impulses to the pumping body. Nutrients move with the affected medium; other cells are entrained through their normal fluid drag. There is no independent nutrient teleport toward a mouth. Exterior particle/body exclusion is an intentional separate concession: after motion, particles inside a live cell are projected to its visible membrane plus clearance, with spatial buckets and interpolation history updated. Rendering also checks the interpolated pose. This positional shunt preserves material and is not a conservative collision law.

Nutrient, oxygen, waste, cell trace and toxin are authoritative external particles. Pores own their sensing: grazing follows nutrients; engulfing follows compatible prey and nutrients; proboscis follows larger hosts. Only the explicit flight receptor requests retreat, and removing its source cancels queued/remembered signals. Sampled chemical signals still travel inward before changing the target; no wiring editor is introduced.

Grazing and engulfing mouths absorb nutrient packets at the opening. Engulfing computes the actual intersection of a polygonal circular aperture and the prey's rendered outline; coverage must be strictly greater than 50% before damage. Prey death transfers gut-capacity-limited retained material, including contents, and releases the excess. A proboscis pierces its local contact and drains a larger living host only after a local hole exists. A remote puncture does not bypass armor. Feeding grips apply equal/opposite relative-motion damping.

Respiration consumes food and oxygen, yielding ATP, biomass and waste. Decomposition requires local oxygen and returns 60% of organic waste as food; the remainder is a recorded respiration loss. Habitat input explicitly replenishes food/oxygen. Assembly, damage, repair, leakage, feeding and death account for retained or released material; no infinite recycling loop is claimed.

## Rendering and controls

Native overlay controls provide illustrated organ cards, right-click feeding variants, health/ATP bars, scrollable assembly, adjustable HUD size and fullscreen. Tab pauses assembly and restores the prior manual-pause state; 7 selects the microtubule tool. The wheel sizes an organ during placement and zooms during observation. F11 toggles fullscreen, and F3 reports FPS and CPU simulation/preparation costs.

Cached cell drawings interpolate body transforms between ticks. Visible external particles use bulk MultiMesh buffers; actual contour queries for exclusion examine nearby spline segments. Current marks refresh at 15 Hz. Pores pulse on successful consumption; rendered apertures correspond to the area used by engulfing. Yellow ATP and pink repair packets originate at the nucleus when the underlying ledger spends ATP or biomass. These bounded cosmetic packets illustrate resource use; they neither create resources nor delay the authoritative debit. Sensory signal particles remain separate.

Tests exercise conservation, fluid suction and passive-cell entrainment, scaled thrust/cost, bidirectional insertion packing, target-facing retreat, strict engulfing coverage and contents, exterior particle exclusion, graph construction and tension deformation, polygon validity, resource effects, sustained ecology and GUI input. Captures and a crowded rendered stress run validate the drawing path. See [revision four](REVISION_4.md) for observed performance and limits.
