# Primordia — core design

Established by the project owner on October 4, 2026. These requirements persist across implementation iterations.

- This is a physics- and chemistry-based simulation game with particle-based triggers and rendering.
- The player manages a cell. The cell stage of Spore is a gameplay reference.
- Eat to grow and survive predation.
- The player has no direct control over cell movement or actions.
- The player may add propulsion, protection, offensive, regenerative, feeding, and sensing organelles.
- Organelle composition and placement determine cell motion and behavior.
- Procedural generation and finite fractals are major visual design elements: seeded branching colonies, radial repetition, nested detail and varied habitat color fields. Geometry must remain readable and affordable at wide zoom.
- The visual reference is Kurzgesagt's immune-system and cellular-biology videos: bright, cartoony, vectorized graphics throughout. Primordia uses its own procedural shapes, palettes, and characters.

## First playable interpretation (revision 1)

A 2D desktop prototype in Godot, with CPU simulation and GPU rendering. This direction was proposed and approved as a starting point, not as a permanent restriction on platforms or scientific fidelity.

The player pauses for anatomical assembly, chooses an organelle, and attaches it to one of eight membrane sockets. There are no movement keys, click-to-move commands, or player-aimed attacks. Observation and anatomy are the player's inputs.

Gameplay particles are authoritative: their positions and species determine absorption, chemical signaling, and toxin contact. Cosmetic effects may supplement them but may not replace the interaction system.

## Revision 2 direction

The owner's first playtest established the next design: floating membrane organelles limited by physical surface area, biomass-dependent volume and inertia, internal tension elements supporting noncircular pressure-driven shapes, organelle damage and biomass repair, significant two-way fluid interaction, and an invisible wrapping map viewed through a following microscope camera.

The visible center simulates fully, the vignette fringe slows, and offscreen state is dormant except for explicit game triggers. Other organisms use the same rules; hunters can die, release nutrients, and be replaced. Waste participates in chemistry. Grazing, predation, engulfment, and parasitism are important feeding paths, including a proboscis specialization within the existing feeding category. Keep innate behavior and assembly pause; defer metagame decisions.

See [the revision-two specification](REVISION_2.md) for requirements, implementation sequence, acceptance evidence, and confirmed decisions. The specification also records validation and the numerical limits of the current revision.

## Revision 3 direction

The second playtest superseded floating attachments: organelles are now anchored to a chosen material location on the membrane, following growth and deformation without tangential drift. Biomass and radius have no arbitrary upper cap; metabolic throughput and storage scale with growth.

Engulfing mouths and proboscises pursue nearby compatible cells through particle signals. Dedicated hunting/host receptors extend their reach. A separate, explicit flight receptor is the only source of fleeing; feeding and nutrient sensing never silently add avoidance. Show contact and feeding progress clearly.

Preserve the observed current-driven nutrient patterns and substantial two-way cell/fluid interaction while reducing frame cost. Fill the screen with the world and overlay the HUD. Tab toggles paused assembly; settings provide persistent text/HUD scaling and fullscreen (also F11). The six categories, indirect control, shared NPC rules, and deferred metagame remain unchanged.

See [revision three](REVISION_3.md) for behavior, controls, and validation.

## Revision 4 direction

Feeding pores now own their food/prey/host sensing and pump the surrounding finite-mass fluid. Keep only flight as a separate receptor. The detecting pore/receptor faces its target; translation approaches food or retreats from a threat. A pore visibly pulses on consumption. External particles must be excluded from the cell interior, with nonphysical shunting allowed.

During placement the wheel changes organ size, cost grows with area, and a larger flagellum produces more thrust. Inserting an organ anywhere on the membrane pushes neighbors aside; anchoring resumes afterward. Engulfing pores also graze and require more than 50% coverage of the prey body before damage. Restore illustrated build cards with right-click variant cycling, health/ATP bars, and visible nucleus-to-organelle/membrane resource spending.

Lower inertia and replace the ellipse tendency with a softer, amorphous pressure membrane. The owner can place microtubules between arbitrary membrane points or points on other microtubules, including tube-to-tube connections, and adjust their tension to control shape. Branch points are simulated junctions. Preserve valid render polygons under this deformation; reported CanvasItem triangulation failures are a defect to fix.

See [revision four](REVISION_4.md) for controls, implementation boundaries and validation. These requirements supersede separate pursuit receptors and strict no-displacement insertion from earlier revisions.

## Revision 5 direction

Escape opens settings with Quit. Space toggles position-follow camera lock without pausing; free view can pan. With the build menu open, direct left drag on the cell places a microtubule, with membrane, existing-link or interior endpoints; hover and scroll adjusts tension. There is no microtubule build card. Creation, tension adjustment and removal are restricted to the build menu; closing it cancels pending placement.

Remove proboscis and engulfing pores. Grazing pores remain. Spikes sense and pursue lower total biomass at long range and puncture on contact. The owner clarified that toxin vesicles remain too. Photosynthesis adds light-seeking behavior, carbon fixation and oxygen release. All external particles originate in cells; remove automatic habitat particle replenishment.

The owner replaced the initial probabilistic-reaction proposal with orientation-controlled contact reactions. Compatible binding faces react deterministically. Decay remains probabilistic and thermal motion rotates particles. Add reusable digestive enzymes, nutrient aggregation, toxin-neutralizing particles/organs, acid-secreting organs and buffering particles. Moderate acidity favors digestive enzymes; maintenance costs and accumulating internal stress provide the downside. Nutrient aggregation stays separate from acidity. The owner approved this scientifically motivated alternative.

Receptor competition is approved for playtesting: decoys temporarily weaken chemical sensing; automatic ATP-funded cleaning, faster repair-body cleaning and energy-independent release prevent permanent blockage. Keep visible status and recovery feedback.

Maintain at least one reference to a real motivating phenomenon for biological/physical mechanics in [references.md](../references.md), with explicit game approximations. These latest instructions supersede previous restrictions on anatomy expansion and feeding specialization. See [revision five](REVISION_5.md) for controls and evidence.

## Revision 6 graphics direction

The owner requested visible particle orientation using branched, forked and rounded shapes, with complement illustrations as a visual reference, then requested a brighter graphics revision. Keep original vector artwork, species readability, particle-authoritative orientation and batched rendering. The owner selected luminous colors like a bright coral reef: blue/teal water and vivid coral/gold/violet/green anatomy, with colorful shadows. The owner explicitly rejected occupation-based body colors: cell bodies share a consistent palette; organelles and their produced particles communicate function. The owner requested bloom in lit areas and water color driven by acidity; bloom remains a presentation effect and buffering reverses the acid tint. New complement mechanics remain suggestions in [the proposal](COMPLEMENT_PROPOSAL.md), not approved gameplay requirements.

## Revision 7 performance direction

The owner reports that normal play requires a wider view than the earlier benchmarks, and that wider views have serious performance problems. All five proposed efficiency approaches are approved targets, with independent measurements of gains and losses. Prioritize compiled simulation kernels, GPU computation experiments and efficient fluid work; also improve spatial query coverage and slower/less detailed updates where behavior permits. Preserve visible oriented chemistry, fluid/cell interaction, indirect control and uncapped growth. Do not hide scaling problems by reducing the active habitat or silently deleting particles. See [revision seven](REVISION_7.md) for implementation, ablations and limits.

## Revision 8 procedural habitat direction

The owner selected the large plant obstacles and varied water colors in the supplied Spore cell-stage reference. Add original, seeded, rotationally symmetric branching colonies that affect the playing field. Make procedural generation and fractals a persistent visual design principle, rather than a one-off decoration. Preserve luminous vector-style art, functional organelle/particle colors, light and acid meaning, and the existing anatomy-driven cell control.

The first implementation uses finite recursive branching for plant-like scenery with solid main stems, and periodic fractal noise for water color. Fine fronds are decorative. These are fixed environmental obstacles, not new food sources or organs. See [revision eight](REVISION_8.md) for the collision approximations, performance evidence and remaining limits.

The owner subsequently replaced the dark microscope vignette with a soft peripheral blur. Keep the center and HUD sharp, preserve water brightness at the edges, and retain existing simulation activity falloff.

## Proposed expansion areas

- More varied ecosystems and organisms with their own organelle-derived behavior.
- Richer chemical species and internal signaling, with readable reaction feedback.
- Improved cell-contact mechanics and an explicitly chosen fluid model.
- More attachment geometry, organelle costs, progression, and tradeoffs.
- Further native cell/membrane work and a fully resident GPU chemistry design, guided by wide-view benchmarks on actual target devices.

These are future directions, not features already implemented.


## Revision 9: run economy

The approved first action-economy prototype is implemented in [Revision 9](REVISION_9.md). Adaptation points constrain deliberate anatomy; biomass and ATP remain conserved physical/operational resources. Assembly is transactional, with free positioning and tension changes, paid growth/specialization, partial tissue recycling and zero-AP restoration. The run has seeded mutation drafts, forecasted tides, bounded costly opponent variants and reserve-funded offspring viability as its default win condition. No direct steering, extra organ types or persistent metagame have been added.

The run director tracks a few scalar exposures and events independently of camera dormancy. Particle chemistry remains orientation-based. Build estimates describe current conditions rather than promising future income. Public source motivation and game abstractions are recorded in references.md.

## Revision 10: luminous vector art

The owner approved deeper, spatially varied water beneath saturated anatomy, broad colored membranes, larger simple internals, integrated organ silhouettes, thicker oriented chemistry glyphs, grouped fractal reefs and restrained event-driven animation. Body palettes and internal patterns now vary by seeded lineage, independently of occupation or equipped organs. This supersedes the single shared periwinkle body while preserving the prohibition on occupation-based body colors.

Preserve physical scale, cell-sourced chemistry, existing particle orientation and counts, microtubule-controlled membrane shape, acidity tint, selective light bloom and peripheral blur without a vignette. Wide-view detail reduction is visual only. The art and per-pass measurements are documented in [revision ten](REVISION_10.md); run rules remain in revision nine.

## Camera and cell-centered interface follow-up

The owner set 80% as the widest playable view and removed the zoom-percentage display. Apply that lower bound after growth and build-panel fitting too; do not shrink the view below it to fit a giant cell. Keep a calibrated, adaptive μm marker on the side, with 0.2 μm per world unit. Paused anatomy edits must redraw and relax their geometry before applying.

The owner requested replacing the persistent HUD/build panes with clickable intracellular factories and representing ATP as a sac, biomass as cell size, and AP as spinning tokens. The [structured replacement proposal](CELL_INTERFACE_PROPOSAL.md) covers these controls, closer editing zoom, drafts, offspring reserves and undo. It is proposed, not implemented or an approved change to the resource rules.

## Revision 11: cell-centered controls and particle inspection

The owner approved the cell-interface proposal, then removed Undo controls and all user organ resizing. The implemented interface uses two intracellular factories, direct organ/restore actions, an ATP sac, AP coins, body-size biomass, nucleus drafts/challenges and offspring reserves. Tab commits and resumes; Escape preserves edits while opening settings. Right-click cancels only held construction/movement or local choices. Existing paid blueprint traits remain; no replacement organ-power system was added.

There are no persistent top/bottom/build panes. Editing supports magnification up to 12×, cursor-centered wheel zoom and camera panning, while the widest view remains 80%. Growth remains visible rather than triggering automatic play-camera retreat. Particle hover temporarily magnifies the local scene and names the actual species, retaining displayed orientation without changing chemistry. The micrometer scale measures the surrounding ordinary view. See [revision eleven](REVISION_11.md) for the implemented controls and validation.

## Revision 12: varied starting networks and music as a core feature

The owner made engaging music a core component, naming Crypt of the NecroDancer and Dicey Dungeons as particular favorites, plus Neophyte and Nova Drift. Preserve original progressive-techno composition with anatomy-derived instruments, proximity-driven audibility and density, and lower registers for larger biomass. Large entering organisms announce themselves quietly in bass and become louder as they approach the viewer center. Audio and visual beat response must remain separate from authoritative chemistry and motion.

Starting cells now have 0–4 randomly tensioned original links, constructed sequentially so later links can join earlier ones as well as the membrane. Seeded replay and inherited edited anatomy remain intact. The implemented sound system, visual response and prospective immersion features are documented in [revision twelve](REVISION_12.md).

## Revision 13: pheromones are the sole inter-cell sense

The owner requires every creature to emit short-lived, current-advected and diffusing point pheromones carrying source location, size and hostility metadata. Receptors learn about other creatures exclusively by receiving these particles; no live source lookup may refresh the information. Pheromones ignore other particles and solids. Grazing and light sensing keep their existing resource inputs.

Preserve emitted metadata snapshots, local receptor sampling, explicit flight, independent probabilistic expiry, down-current plumes and pass-through transport in every backend. These points are non-oriented signal tracers, an explicit exception to material-particle exclusion and binding-face graphics. See [revision thirteen](REVISION_13.md).

## Revision 14: inherited and responsive music

The owner approved all three immediate music follow-ups: inherited lineage motifs, environmental timbre and musical event accents. A family's seeded melody survives division; installed organs change its orchestration. Local light opens melodic filters, local acidity adds saturation/ripple, and ordinary buffer chemistry calms that effect. Feeding, toxin neutralization and division trigger bounded, quantized phrases.

The implementation is presentation only. Do not delay actions until the beat, consume ecology randomness, drain gameplay journals or make audio an input to cell AI. Preserve bounded queues, muted-history rejection, local audibility and native/reference parity. See [revision fourteen](REVISION_14.md) for behavior, bounds and measurements.

## Revision 15: active screen edges, varied fractals and stable inspection

The owner reports organisms freezing inside the view. The full rectangular viewport must run at normal speed, including blurred edges and corners. Keep full-speed simulation for a short offscreen margin, fade only farther outside, and account for the visible extent of large cells. This supersedes the historical in-view activity falloff; optical blur remains independent.

Add fern-shaped fractals and other distinct families to the existing radial colonies. Preserve bounded generation, cached vector artwork, solid main stems, permeable fine foliage and cell-only chemical sources.

The owner also requests less flicker from particle inspection. Briefly retain and follow the actual selected particle after activation, keeping its orientation and current identity; intentional pointer movement should release it. Inspection remains presentation-only. See [revision fifteen](REVISION_15.md) for implementation and evidence.

## Revision 16: a continuing lineage with clear crises

The owner approved making the goal clearer, increasing challenge and treating ordinary death as continuation. The implemented objective is to establish a lineage through Lean Current, Chemical Bloom and Long Dusk. Give a concrete immediate goal through the nucleus and temporary cell-local cues, keeping the habitat free of persistent panels.

Allow early resource-funded reproduction, living descendants and a bounded dormant reserve. Prefer an existing living relative on death, otherwise hatch actual prepaid tissue in the same habitat. One founder reserve belongs to the initial inventory; additional reserves cost the quoted material and ATP. Preserve the expedition clock, AP/draft decisions, crisis achievements, ecology and inherited musical motif across succession. Exhaustion can end an expedition, but family history and discovered blueprint choices remain. Recalling knowledge replaces an ordinary draft choice and never grants free organs, currency or permanent stat multipliers.

Shift some adaptation income from waiting to optional bounded growth, feeding and stability accomplishments. Stage clearly forecasted light/predation/chemistry pressures through existing rules and give a few introduced rivals recognizable paid anatomy. No new sense may bypass pheromones and no rival gains hidden immunity. Grazing, hunting and photosynthetic/hybrid strategies remain intended paths; automated policies do not establish human balance.

The first implementation retains the 13:30 expedition length, three crisis milestones, bounded histories and local discovery persistence. Full habitat save/resume and a larger campaign are deferred. [Revision sixteen](REVISION_16.md) states exact thresholds, controls, scientific abstractions and validation.

The owner explicitly accepts distinguishing player-only progression from shared cell rules, and asks that distinction be clear. NPCs currently share physiology and anatomy-derived behavior, but do not use the player's AP/drafts, succession, dormant bank or persistent knowledge. Their population uses bounded introductions/replacements. NPC reproductive AI is a future feature, not part of revision sixteen.

## Revision 17: contact mechanics and separate hunting perception

The owner requests more physical interaction among cells, plant obstacles and spikes, and explicitly removes sensing from spikes. A new hunting receptor matches the flight receptor: it samples local pheromones, orients toward their reported location and pursues prey that was smaller or undefended at emission. Undefended means no functional spike, toxin vesicle or protective cortex. Defense is an immutable emitted snapshot; no live-cell lookup, attack-direction oracle or role label enters perception. Flight remains the explicit higher-priority avoidance choice.

Contacts transfer linear and angular motion, resist tangential slipping and compress the local pressure membrane. Spikes obstruct cells and stems and puncture on impact. The owner accepts prey bouncing away and requests that a few good hits can kill; damage therefore scales with actual normal impulse. Stronger mobility and useful weapon placement help hunters earn repeated impacts. No special predator speed or damage bonus is introduced. Slow sustained contact retains its small ATP-funded injury.

The factory offers the separate fixed-size receptor for six tissue and one AP; V selects it. Existing NPC hunters receive the same receptor organ. Preserve family-only progression, chemical perception, continuous fluid coupling, finite contact cost and widest-view benchmarking. [Revision seventeen](REVISION_17.md) documents numerical limits and validation.


## Revision 18: transport beyond the camera

The owner reports isolated particle clouds and empty gaps because offscreen motion freezes. Keep current-driven transport and diffusion running over the whole habitat at reduced computational resolution. Visible packets and the existing transport halo use full elapsed time; distant packets are staggered across roughly half-second updates. Coarse steps follow the cached current with midpoint samples, integrate launch drag, and scale Brownian displacement with the square root of elapsed time. Maintain the far fluid field cheaply rather than retaining frozen wakes.

Cell biology, sensing, emission and chemistry retain their local activity rules. Material transport alone must not create resources, refresh emitted metadata or perform live source lookup. Pheromone expiry remains global. Camera entry catches up once, with swept solid-stem contact and no long interpolation trails. [Revision eighteen](REVISION_18.md) documents validation and explicitly limits the model: this is coarse Lagrangian transport, not a full offscreen ecosystem.

## Revision 19: an ecosystem beyond the camera

Living offscreen cells must keep up through real resource encounters, not increased internal parameters. Advance their ordinary physiology, ATP costs, storage limits, repair, production and pheromone-driven behavior on a staggered coarse clock. Use wider, resource-limited absorption and probabilistic hidden predation weighted by actual anatomy, size, mobility and defense. Never grant live target coordinates to perception or roll an instant kill inside the detailed halo.

The owner questioned automatic corpse consumption during implementation. Prefer lysis into actual nutrient/oxygen packets, followed by ordinary absorption: predators and scavengers compete for the same finite material. This removes the extra reward path and keeps feeding organs relevant.

Preserve time across camera transitions, timestep-scaled event hazards, mass accounting and editing pause. Photosynthesis/secretion must count multiple possible events in a coarse interval. Nearby chemistry retains oriented binding, real antitoxin/acid/buffer resources and a per-packet chemical clock; coarse acid-field transport continues globally. Banked successors remain truly dormant, and NPC reproduction/AP/lineage progression remain separate from this change. [Revision nineteen](REVISION_19.md) records paired balance measurements and the remaining spatial/chemical approximations.


## Revision 20: dimensional membranes and visible flow

The owner requests more depth on membranes, ripples/wakes around cells and plants, and animated flow streamers inspired by Earth Nullschool instead of background vectors. Keep luminous lineage colors and the vector reef character. Rounded membrane shading must follow the actual pressure/microtubule outline; it must not replace deformability with an ellipse or imply extra collision coverage.

Streamers read the authoritative fluid cache and move along its bends. Their direction and extent communicate flow; they are presentation geometry, not chemical particles. Subtle downstream glints around slipping cells and stout plant stems help show the medium. Pause them with the simulation. Bound GPU batches and upload frequency, preserve toroidal continuity, and compare rendering ablations at the 80% play limit, including dense particles, large cells and music. These cues do not add obstacle-fluid forces or a water-surface wave simulation. See [revision twenty](REVISION_20.md).


## Revision 21: whole-frame performance

The owner requests phase timings for dense live frames and a frame-rate repair before the next playtest. Measure all catch-up ticks, view synchronization, membrane geometry, draw submission/render and music, with workload counts and audio underruns. Preserve 60 Hz physics, eight-step catch-up, full screen plus margin, finite resource rules, orientation chemistry, pheromone-only perception and the complete Revision 20 visual treatment.

Reduce repeated indexing and script/native crossings through matched native batches. Preserve sequential collision order, packet identity/timestamps and random streams; compare native/reference rules and both backends. Separate equal-simulation-time CPU ablations from wall-clock rendered FPS, test dense/grown/crowded scenes at 80%, and retain shared-host uncertainty. See [revision twenty-one](REVISION_21.md).

## Revision 22: coherent steering and anatomical editing

The owner reports grazing steering interrupting hunting and requests a way to balance the signals. Use adjustable per-organ strength with a coherent selected drive and bounded hysteresis, rather than averaging opposing directions. Grazing, hunting and light steering can be tuned anatomically without resizing or granting more power; disabling steering leaves collection/photosynthesis intact. Explicit flight has priority. Retain pheromone-only discovery and immutable reported coordinates; delayed weak signals must not overwrite a stronger valid target.

The owner requires hunting to avoid offspring. Preserve inherited self-recognition across paid birth, editing and successor adoption. Carry emission-time family signatures through internal signals and remembered targets, reject own-lineage signals at delivery, and retain harmless physical family/spike contacts. Family protection does not grant immunity to environmental hazards or unrelated predators.

In edit mode only, show usable tissue as a translucent top-right blob. A separate selected-organ cost blob uses identical area per tissue unit, updates after purchases/recycling/reserving, and signals a shortfall without a numeric biomass counter. No permanent HUD pane returns. Keep AP affordability distinct from tissue.

Membrane attachments and placement previews face the local outward normal of the rendered deformed outline, including suction/intake offsets, spike shafts, secretion and receptor facing. Flagellar force follows that mounted axis with reversible strokes. Widen microtubule interaction to a UI-scaled 16-pixel tolerance while preserving edit-only gating and factory priority. Suppress particle magnification inside and immediately around all living cells, including tracked particles, without changing simulation or particle visibility.

The owner requests a spark when two particles react. Sample successful pair contacts through both chemistry backends and display brief capped instanced flashes. A rejected collision, unary decay or particle source is not a successful pair reaction. Keep these effects independent of ecology, audio and random streams.

[Revision 22](REVISION_22.md) records controls, regression checks and playtest limits.

## Revision 23: porous colonies and clearer resource/flow cues

The owner approves plant stems being permeable to chemical particles to prevent unreachable food pockets. Keep plant-cell and plant-spike geometry solid. Apply permeability to foreground transport, coarse offscreen transport and coarse chemical absorption/exposure; retain finite resources and solid separation of hidden cell hunting. Do not add food, teleport it to mouths or alter species-specific chemistry. Surface retention/slowing is a possible later refinement, not part of this fix.

The owner asks for substantially longer flow streamers. Use three times the trail duration, a longer fading lifecycle, finer bounded strips and cached-field GPU integration. Preserve simulated flow, world-anchored seeds, RNG, pause behavior and a 640-strip limit. Check the presentation cost at the widest playable view.

The owner replaces internal AP coins with small gold blobs at the top right alongside the build-only biomass display. Each blob is one actual available AP; zero is an empty outline. Remove the old coin node, hit target and transfer animations. This is presentation only and does not alter grant/spending rules.

Locked follow-mode wheel zoom always centers on the cell, even after an editing pan. Free-camera zoom remains cursor-centered. Keep the 80% minimum, 12× maximum and no zoom readout.

Hovering a construction or organ-upgrade choice (or focusing it with the keyboard) shows its real tissue/AP costs beside available stock. Required AP uses the same one-point gold blobs, with a shortfall tint. Exact tooltips remain; zero-AP restoration is visibly free. Previewing never spends resources.

The owner requests the proposed ATP visual comparison, with obvious per-organ upkeep in build hover. Show actual production/spending on a common area scale, an installed/proposed organ's steady estimate, precise recent rates and shares on hover, and pre-purchase upgrade deltas. Keep estimates distinct from recent paid costs and distinguish gross production, stored income and overflow. Use bounded simulation-time averaging, pause-stable readings and presentation-only incoming packets. No economy changes.

The owner requires larger cells to have greater fluid drag and lower swimming top speed at equal propulsion. Scale membrane drag with radius, preserving equal/opposite cell-fluid impulses and ordinary current advection. Use the same size-dependent drag in the coarse hunting mobility estimate. No role-based speed bonus or hard velocity cap.

The owner asks for more pronounced local wakes and broad water ripples without occluding cells or causing dizziness. Extend plant/cell glints, draw every cell wake beneath all cell bodies, and keep broad slow caustic brightness variation in the water background only. No camera motion or full-scene refraction. The background shimmer can be disabled in settings and pauses with simulation time.

The owner removes particle beat pulsing because it was not noticeable. Remove its shader work, per-frame visual preparation, preference and settings control. Preserve original progressive techno, audio timing, anatomy/lineage/proximity/environmental sonification and gameplay event accents. This supersedes earlier requests for beat-responsive particles.

## Revision 24: sustainable operation and patch-aware foraging

The owner reports ATP too tight to support new anatomy and requests signal strengths competing with random exploration. Routine ATP costs are reduced and food ATP yields increased, with unchanged finite material accounting, construction/AP rules, repair and combat. Emergency tissue mobilization starts later. Local grazing follows mass-weighted nutrient neighborhoods before targeting individual particles within a body-sized inner threshold.

An inherited exploration gain competes with the chosen anatomical signal through a tunable response cycle, rather than averaging opposing vectors. Memory and sensing continue during wandering; flight remains explicit and immediate. The nucleus exposes local Behavior controls, without bringing back persistent panes or direct movement.

The owner also requests seeing the death explosion before relocation, and wakes relative to surrounding liquid. Presentation holds the death site briefly before easing to the paid successor; real habitat/succession proceeds without delay. Cell wakes use external water/body slip in the membrane frame; plant wakes use local water flow. See [Revision 24](REVISION_24.md).

The player starts with a grazing pore and **neither cilia nor a flagellum**. Both remain separate fixed-size assembly purchases, each costing eight tissue and one AP. Flagella emphasize thrust; cyan ciliary bands add weaker thrust plus a stronger directional local feeding current. Cilia use the receptor/exploration-selected heading, add no sensing or absorption, and pull hazards along with food. The current acts on the real fluid and returns equal/opposite momentum to the cell in detailed and coarse simulation. NPC flagella remain unchanged; offspring inherit paid anatomy normally. Cilia also contribute their own synthesized flutter-pluck rhythm.

## Revision 25: fluid comparison before particle-soup expansion

The owner approved comparing a Godot-integrated GPU pressure grid and GPU Position Based Fluids. These are experimental water backends with separate finite, oriented chemical packets; LiquidFun was an example, not a selected dependency. The existing medium remains the gameplay default.

[Revision 25](REVISION_25.md) records matched initial 20k/50k chemical workloads at the 80% playable view, plus clustered, large-cell and live catch-up fixtures. Both water options have small resident costs, but existing packet transport/reactions/view preparation dominate whole frames. Grid pressure/body coupling is unstable in a moving fixture; PBF boundary density is incomplete. Neither is promoted. The next implementation priority is packed persistent chemical state and batching, followed by coupling accuracy tests; no hidden mass boosts, free particle material or reduced activity halo are authorized by this comparison.

## Revision 26: continuing the particle migration

The owner requests continuing particle work after the fluid comparison. The first native migration stage shares reusable numeric state across transport, grid repair, chemistry and presentation, with explicit invalidation after biological packet changes. Preserve finite quantities, oriented rules, packet identities, clocks, query/reaction order and all three simulation random streams. Keep ordinary density unchanged until the full soup can meet its frame budget and packet-resolution balance is calibrated.

Public dictionaries remain current for existing biology, fixtures and inspection; this stage does not yet remove per-tick dictionary mirrors, introduce stable global pool handles or move chemistry onto the GPU. [Revision 26](REVISION_26.md) records separate packing/cache ablations, 20k/50k/100k fixed-step workloads, clustering/large membranes and genuine live catch-up. The provisional 20k/60 FPS target remains an acceptance gate, not a completed claim.

## Revision 27: native particle ownership

The authorized particle-soup migration now gives ordinary native gameplay a persistent authoritative CPU pool, removing routine per-tick dictionary pose imports/mirrors. Feeding, sensing, offscreen intake/exposure, contact, expiry, spatial maintenance and rendering consume the same native state. Local inspection uses detached snapshots and stable handles through compaction; the explicit dictionary/GDScript backends remain available.

Preserve unchanged finite material, ordered oriented chemistry, immutable pheromone-only perception, family rules, full visible activity, coarse offscreen progress and the existing fluid/body coupling. Default density and packet calibration remain unchanged. The initial 20k live fixture reaches or approaches real time on the test workstation, depending on shared load, but still exceeds the p95 60 FPS budget; sustained density and larger soups remain future gates. See [Revision 27](REVISION_27.md).

## Revision 28: collision-free chemical particles

The owner requests trying particle clouds without particle–particle collisions, while retaining chemical reactions. Chemical packets now overlap without generic separation impulses by default; current advection and independent random-walk diffusion remain active. Orientation remains a binding/animation parameter, with isotropic encounter radii and no branch/fork collision geometry.

Settings exposes Particle collisions for immediate comparison with the former repulsion. The preference persists across restarts and applies equally to native, reference and coarse chemistry. Cell membrane exclusion, solid cell/spike contacts, plant permeability, feeding, sensing, decay and reaction rules remain. No diffusion coefficient, fluid backend or default density is changed. Dense overlap may change later reaction opportunities and material distribution; this is an authorized gameplay trial, not an exact ecological parity claim against Revision 27.

## Revision 29: retain collisions and optimize exact contacts

The owner rejected the overlap trial after visual and performance comparison. Ordinary gameplay restores particle repulsion and ignores its former saved toggle. Orientation remains a binding/animation parameter; the existing circular contact and material rules remain. Overlap is available only to explicit profiler comparisons.

The native broad phase tightens each particle's grid search to its cached contact radius plus the maximum eligible partner radius, with a conservative float-coordinate margin. The old candidate order remains. Acidity is sampled only when an enzyme/waste binding threshold or aligned waste/oxygen recycling needs it. Reference-wide and eager-acidity ablations remain available for outcome/phase checks. Membership of one static bin does not become a reaction rule; that approximation would change contact reach and boundary behavior while physical repulsion still needs distances.

## Revision 30: measured neighbor-search alternatives

The owner authorizes comparing packed grids, BVHs, quadtrees and buffered neighbor lists. The implementation preserves circular encounters, ordered oriented reactions, finite material and all random streams. Index packing does not reorder authoritative particle slots; BVH/quadtree/cache candidates restore original traversal order. Cache validity includes identities, handles, activation, movement and radius growth; overflowing lists fall back without dropping interactions.

Uniform, clustered, mixed-radius and large-cell benchmarks show no reliable speed gain from packed indexing; this CPU BVH, quadtree and global cache are slower. The established grid remains the ordinary default, with collisions on and unchanged density. Alternatives and counters are explicit profiler options. Fixed-horizon parity and live catch-up are separate checks; shrinking finite clouds do not establish sustained 50k performance. See [Revision 30](REVISION_30.md).

## Revision 31: original LiquidFun and conservative parcels

The owner approves an original Google LiquidFun comparison, uniform physical radii, and a flexible particle-count target for an idle iOS/Android game. Keep finite oriented chemistry, immutable pheromones, family filters, porous plants and paid anatomy. The current implementation is an explicit native particle-motion/contact trial; the established fluid/body coupling remains in place. No mobile export or closed-app world simulation is delivered by this revision.

Zoom must never change feeding effectiveness or generate material. Experimental engines/parcels pin their integration footprint independently of display zoom and free pan. Near-cell transport/chemistry remains individual; distant same-species cohorts may share advection calculations while retaining every child's material, identity, rotational state and independent diffusion.

The first parcel stage shares transport only. True weighted collision/reaction parcels must conserve amount, capacity, product, momentum and cloud/heading distributions, refine before biological contacts, and use separate merge/split thresholds with bounded work. A stock equal-radius LiquidFun point is not an arbitrary weighted parcel. Reaction closure, long-horizon balance, mobile ARM64 builds, full habitat saves and elapsed-time offline ecology remain later gates. See [Revision 31](REVISION_31.md) for the comparison and measured limits.


## Bounded particle simulation and large worlds — owner direction, October 7, 2026

The existing CPU version's appearance and coarse offscreen behavior are the
reference to preserve. The GPU upgrade should make the nearby chemical soup
denser and smoother. A larger world must not require a larger per-frame GPU
particle simulation. This supersedes Revision 39's whole-habitat detailed
backend as the architecture target; offscreen cell coarsening alone is not enough.

Use a hybrid with a bounded GPU simulation window and sparse CPU-managed world
chunks. A halo outside the visible region covers transport, sensing and
interactions before they become visible. Detail is tied to a fixed gameplay
footprint, not display zoom. Distant ecology retains real elapsed time, paid
physiology, family-safe pheromone information, finite resource uptake and lysis.
Do not improve performance by changing stats or removing offscreen competition.

Only resident chunks take fine particle steps. Far chunks use scheduled coarse
updates or timestamped lazy catch-up, with finite material and conservative
boundary transfers. Never traverse every stored chunk or particle each frame.
Unvisited chunks can be generated from their coordinates and seed; persistent
changes belong in an indexed backing store. Finite memory/disk and the amount of
active ecology remain real limits; world dimensions need not determine frame work.

Chunk ownership transfers must be transactional: exactly one authoritative owner
per packet or coarse material parcel, no double feeding at overlaps, no loss at
capacity refusal, preserved chemical species/amounts and secretion metadata.
Inspection handles are generation-safe; stale pheromones expire by world time.
Promotion reconstructs detail from retained state without creating material,
repairing cells, resetting hazards, or letting camera movement farm resources.

Implementation sequence:
1. Retain the working CPU game and measure it as the behavior baseline.
2. Add chunk-local coordinates, an ownership ledger, sparse residency/scheduling
   and a conservative seam-transfer prototype; do not redesign biology.
3. Run the existing GPU particle pipeline only on a bounded local population.
   Keep the existing CPU coarse ecology outside, adapting its storage interface.
4. Validate entry/exit, rapid travel, zoom, save/reload, capacity overflow,
   cross-boundary flow/reactions/feeding and shared material accounting.
5. Compare dense on-screen gameplay at fixed local density while increasing the
   stored world by 10x and 100x. Resident slots, dispatch work, per-frame chunk
   visits and transfer budget must remain bounded; report catch-up latency too.

Current Revision 40 cell tiers are an intermediate performance checkpoint.
The GPU particle and fluid buffers still cover the fixed 4096 x 2560 torus;
streamed ownership and arbitrary-size world support are not implemented yet.

The owner accepts slower zoom/camera transitions when needed to prepare chunk
boundaries. Prefer a resident window sized for the current 80% widest view plus a
halo; zooming in must not evict that window or change feeding rules. If future
zoom-out or camera travel exceeds prepared coverage, prefetch first and ease the
view within available coverage. Rate limits are presentation constraints, never
extra simulated time, refreshed particle hazards, resource gains or visible
freeze/pop-in. Do not slow ordinary zoom merely to hide unbounded transfer work.

## Revision 41 — disjoint nearby and cold particle ownership

The resident desktop option now uses a fixed widest-view GPU window plus a
preparation buffer and sparse CPU chunks beyond it. Keep transfers bounded,
acknowledged and generation-safe. Preserve actual packets and absolute clocks,
including unacknowledged transfer/emission escrow during CPU recovery. Cold
biology uses the established resource-limited feeding, damage and lysis rules.
Merge complete food moments and newest immutable reports before target selection
across execution owners. No camera change creates biomass, ATP or extra time.

Cold chunks borrow/return as units; only moved chunks need particle regrouping.
Do not add a full stored-world scan to tick, draw or sensing. Reuse bounded
background scheduling and local queries, with explicit diagnostic snapshots only.
Presentation waits for both admission and eviction backlogs before advancing the
window. Reversals must remain inside the intersection of prepared/current water.
Display zoom uses the fixed widest footprint and cannot improve feeding.

See [Revision 41](REVISION_41.md) for measurements and remaining limits.
Streaming costs CPU time on the current small world; do not describe it as a
measured speedup over the all-GPU reference or as infinite-world/50k/mobile
completion. Next scaling work includes tiled fields, cell scheduling and smoother
cold preparation. The ordinary CPU game remains the owner's successful reference.

## Revision 42 — built-in oral anatomy and intracellular editing

Paramecium motivates the first anatomy set: a ciliated oral groove is inherent
membrane structure shared by all generated cells, not a purchasable organ.
Preserve paid propulsion choices, actual local membrane normals, shared feeding
and current physics, and exposed-membrane vulnerability. Ciliary and oral pumps
act relative to the moving liquid/body pair with conservative reaction impulses.

Represent retained tissue volume linearly by enclosed 2D area and use the same
unit in build-cost previews. ATP is uncapped, with increasing concentration
turnover and a growing sac rather than a fixed-capacity gauge. AP is represented
by internal gold vacuoles. Build mode freezes outside biology while bounded
internal stock parcels keep circulating; no editor resource generation.

Hide explanations behind optional inspection, keep compact cell-local actions,
and preserve necessary affordability feedback. The nucleus supplies the main
beat; other notes must have an actual anatomical source. Remove anonymous
backing music and soften other organisms. Source-local pitch-colored waves
follow audible notes, not chemical-particle behavior. See [Revision 42](REVISION_42.md)
and the biological motivations and explicit abstractions in [references.md](../references.md).

## Revision 43 — particle-mediated intracellular chemistry

The owner removes hunting spikes, requests ten times as many particles and a
richer chemistry sandbox. Chemical transport remains exclusively particle
based inside and outside cells. Named local pathways consume real nearby input
particles and emit products in the cytoplasm. Wiring changes compatibility,
not a stock or a position. Functional digestion/osmosis, finite chemical pore
assemblies, conserved carrier/fuel handling, paid catalyst capacity, configuration
blueprints and the existing CPU/GPU ownership options are covered by
[Revision 43](REVISION_43.md).

This supersedes prior scalar metabolism and editor-only chemical circulation.
ATP sacs are readout metaphors; actual ATP, ADP, cofactors, metabolites and water
are particles. Structural tissue and AP remain their existing distinct resources.
The richer finite initial habitat is authorized independently of historical
density-promotion gates. No new environmental food source, engine optimization
program, world expansion or mobile export is part of this change.

Owner correction, October 13, 2026: disable all tests focusing on gameplay
balance until further notice. Preserve their source behind tests/test_policy.gd,
print explicit skips, and continue conservation, particle/physics, elapsed-time,
UI and backend correctness checks. Do not use a calibration/playthrough
harness to assess survival, yields, kill rates or victory during this hold.

Owner correction, October 14, 2026: temporarily reduce the particle population
to one tenth for multiplayer. The visible density target is approximately 700
chemicals. Larger finite parcels preserve chemical quantities and fuel; they
remain the only transport mechanism. This is a coarser spatial resolution,
not a claim of unchanged reaction distributions or gameplay balance. Existing
shared worlds migrate once during trusted checkpoint loading and retain an
independent pre-conversion checkpoint. See docs/deployment.md.

## October 14 — exteroception and interoception

The owner requests separate internal/external particle simulation interests. Exteroception hides internal packets and uses the existing offscreen cadence for their real transport/reactions. Interoception displays the focused body's internal packets, hides external chemicals and uses existing external offscreen methods; the actual area outside the membrane is grey and dim. These are view/scheduling choices, not pauses, resources or statistical chemistry. Multiplayer takes the union of requested detail for each domain. Preserve finite particle stocks and retained elapsed clocks through switching, promotion and saved restart.

Follow uses one fixed-label highlighted/dim toggle. Camera observation may follow an existing living cell when the account's owned lineage has ended, while ownership and paid commands remain unchanged. [Revision 45](REVISION_45.md) defines the implemented domain and observation contracts.

Revision 46 extends the resident backend to visible intracellular particles. Transport and reactions own finite GPU parcels, while body physiology receives compact paid receipts. Hidden cell interiors retain coarse particle chemistry and elapsed clocks. Internal resolution is coarsened independently of exterior density, with protected spatial seeds and catalyst sites. Native texture drawing and interpolated browser instances share the small particle glyphs. The persistent server's clock is independent of display VSync. Mobile music uses the existing score and generated synthesized samples through Web Audio, with touch sound controls and the observed living cell as the remote musical focus. See `REVISION_46.md` for ownership, migration, numerical and validation limits.

The owner requests automatic reproductive investment and splitting from existing stored reserves. Revision 47 makes this a shared paid cell policy in fine/coarse simulation, independent of client presence. The parent remains selected and ordinary living-family/dormant recovery remains available. Complete lineage exhaustion requires an explicitly chosen new starting population; signing in does not grant a body or reset the pond. See [Revision 47](REVISION_47.md).

## Revision 48 — owner-authorized persistent introductions

The persistent pond now maintains a floor of fifteen living cells. Exhausted accounts receive a new starter cell in a new lineage, keeping their access keys and sign-ins. If all cells die, archive the complete old pond and start a new seeded population automatically. These explicit introductions supersede the previous no-reseed policy; automatic reproduction still consumes real particle reserves. Preserve safe placement, resident capacity, bounded retry and archive-before-reset durability. See [Revision 48](REVISION_48.md).

## Revision 49 — owner-authorized simplification

[Revision 49](REVISION_49.md) supersedes the expanded intracellular model above: ATP, biomass and reserved reproductive ATP are numbers. Finite ingested nutrients circulate in food vacuoles, digest directly into resources, then leave as waste via the cytoproct. There is no seeded internal molecular cloud or active pathway/osmosis network. Preserve resident visible transport, coarse hidden transport, actual membrane masking, named shaped-particle inspection, music, paid reproduction, saved identities and the fifteen-cell population floor. Comparable first-cell performance and real-time authority throughput are acceptance requirements.

## Revision 51 — restored bounded biology and division progression

The owner restores photosynthesis, local oxygen-dependent respiration/fermentation and emergency biomass fuel within the bounded food-vacuole model. ATP and biomass remain numbers. Paid division grants two AP and has a ten percent chance to offer a free mutation; hourly calendar-derived light/current conditions serve the persistent pond. Restore visual contractile vacuoles, shaped ATP/repair feedback and actual-secretion gland bounce. Microtubules are procedural anatomy with faint lines and no editing. Mobile cancellation uses the held organ's top-left circular icon; descriptions occupy a bottom strip and Pause opens settings while freezing only that view. See [Revision 51](REVISION_51.md).

## Persistent pond survival — October 15, 2026

The owner wants players to retain their actual cells across server restarts and
to lose them to starvation only after a sustained shortage. Service restarts
restore saved cells, anatomy, age, reserves, lineage, account identity and pond
time; host downtime does not consume resources. The nutrition upgrade archives
the predecessor and adds one audited physical food/carbon/oxygen cloud around
each living cell once, without changing any body or resetting the pond.

Initial cells and explicit minimum-population/new-lineage introductions carry
the same finite cell-derived exterior inventory. Nutrient parcels contain three
times the previous food quantity at the same packet count. Paid division,
login, camera changes and ordinary service restarts do not add these clouds.
Food/carbon decay is 0.00005/s and oxygen decay is 0.0002/s; other decay rules
remain unchanged. Transport, ingestion, local photosynthesis/respiration and
numeric ATP/biomass accounting remain authoritative.

A cell first reclaims uncommitted daughter ATP and mobilizable daughter tissue
before treating itself as starved. Zero ATP accumulates a saved starvation
clock; the first 300 seconds do no starvation damage, then health declines at
0.1/s. Positive ATP reduces that clock four times as quickly as it accumulated.
These are forgiving game timings, not measured cell starvation kinetics.
Toxins, combat and membrane damage retain their normal consequences.

Multiplayer snapshots carry bounded recent membrane-rupture facts and the dead
body ID. Each session starts at the current death serial. Deaths of the
previously selected/followed body briefly frame the death site before returning
to the replacement; nearby deaths animate without taking over the camera.
Local pause freezes existing fragments and resume does not replay paused-world
deaths. Presentation neither creates lysis material nor delays succession.


### Persistent account names and update retention (October 15, 2026)

Players choose a 1–24 character name from Pause → Player name. The server saves
it with the account before confirming success. Every visible cell in that
account's current lineage carries a nameplate; connected owners are highlighted,
offline owners are dim. Interoception shows only the focused cell's label.
Names carry no authority and never expose account/session keys.

Successful paid division awards **2 AP**. Toxin damage per delivered unit and
assembled pore damage per second are doubled; newly emitted acid parcels carry
twice the acid capacity. Secretion still spends the same finite tissue/ATP and
requires the same physical transport and contact, with unchanged family immunity.
No update resets or culls the pond to control population.

Every ordinary current-model restart compares all saved cell records, including
NPCs and dormant successors, before the first simulation tick. Anatomy, resources,
membrane state, cytoplasmic parcels and other saved biological fields must match;
only derived rendering/solver caches are excluded. Deployment retains the exact
stopped checkpoint generations and restores them with the previous release if
acceptance fails. An already extinct pond retains its full archive under the
existing explicit extinction rule. Natural evolution continues during builds and
resumes after startup; host downtime does not age cells.

Death facts use a small opt-in WebSocket event independent of GPU pose publication
and snapshot acknowledgement. The client queues and deduplicates these facts so
a later snapshot cannot erase an unseen rupture. A personal rupture briefly fits
the real membrane into the view, including at maximum interoception zoom, and
suppresses the interior mask until the camera returns to the successor. Reconnect
and local Pause do not replay old deaths.


### Slower water and porous vegetation drag (October 15, 2026)

The owner requests slower actual water flow while preserving the full 8.4-second
stream histories and 20-second presentation seed lifecycle. Maintained ambient
current is 35% of the prior target. Existing water relaxes toward that target;
cells and saved velocities are not reset or hard-capped. Calendar conditions retain
their hourly sample; a versioned target refresh applies the new amplitude once.

Plants absorb fluid momentum through a cached drag map built from their existing
stems and fine foliage. Each wet node uses bounded density-dependent linear drag,
integrated exponentially after ordinary viscosity and tide in both native and
reference paths. The offscreen complement receives the same elapsed drag. Fixed
plants are an explicit external momentum sink. This game abstraction does not
add pressure projection or solid barriers for chemical packets. Cells retain
ordinary stem contacts. Trail count/opacity are reduced for readability without
shortening stream history or slowing the simulation clock.


Snapshot encoding runs on a single bounded worker after the main thread captures
a data-only frame. There is at most one queued/encoding snapshot per peer and at
most eight in total. Acknowledgement backpressure begins after delivery, and
small death/authentication messages bypass this queue. No simulation objects or
sockets are accessed by the compression worker. Shutdown joins the owned worker.

Candidate GPU networking and saved-world performance checks run after the live
service has gracefully checkpointed/stopped and its exact generations are backed
up. Source/native/web builds finish beforehand. The single GPU is reserved for
one candidate authority during acceptance, matching the deployed workload. A
failed check restores the saved generations and previous service. The 30 Hz,
real-time ratio and p95 gates are unchanged; updates include this bounded outage.

With explicit PRIMORDIA_LOCAL_NUMA=1, deployment may restrict the authority and
its candidate checks to
the selected GPU's RAM-backed CPU node, intersected with the caller's allowed
CPU set. Missing topology, a memoryless GPU node or no eligible CPUs retains the
ordinary scheduler. This per-process placement changes no clock, power or boot
policy and uses the same performance thresholds. The previous service unit is
restored on rejection.

Snapshot/checkpoint capture reuses only property-name schemas of the fixed script
allowlist. Every graph still reads current values and object identities; no cell
state is cached. An uncached reference path checks byte-identical full saves and
both compact client formats, including overrides and changes between captures.

Candidate authority fixtures use the deployed 64x64, disabled-vsync, 60 FPS
presentation settings. Uncapped test rendering is a different CPU/GPU workload,
even without world artwork. The 30 Hz simulation and all latency/real-time gates
remain unchanged. During candidate checks a bounded read-only sampler records
GPU clocks/load and only the owned process tree's thread runtime/runqueue delay;
idle snapshots alone cannot diagnose active simulation stalls.


The owner authorizes shipping the current update while monitoring its known
timing shortfalls. The deployment's explicit performance-warning mode records
ratio/p95 misses without rejecting this rollout; it does not claim those targets
passed. The configured 30 Hz cadence, finite measurements, real progress,
hardware GPU, particle correctness, cell-retention and checkpoint checks remain
required. A manual workflow input or the exact head commit's
[allow-performance-warnings] marker selects the exception. Later unmarked
pushes are strict again; no exception is added to the running service environment.


### Oral-groove artwork and overlapping controls (October 16, 2026)

The inherent mouth traces the actual deformed oral membrane rather than a
fixed crescent. Lip thickness and cilia shrink with the body, preserving the
factory space in small cells without changing feeding geometry or rates.
The selected cell's local factories draw above membrane appendages. A tap or
click shared by several controls offers each overlapping structure, using the
mobile top tray or compact desktop choices, so drawing order cannot prevent
access. Selecting one opens its existing actions; no paid action happens during
selection. Keyboard target cycling remains available. Existing cells, anatomy,
resource rules and saved-world formats are unchanged.


The currently controlled cell draws above other cells and their appendages;
other living cells in the player's lineage draw above uncontrolled lineages.
Double-tapping a living family member (desktop: double-clicking) adopts that
existing body through the same server-validated family command as the family
menu. It grants no cells or resources and keeps completed edits. Pinch/drag
sequences and held organ placement cannot switch control accidentally.

Photosynthesis always offers Sun specialist and Shade specialist without a
random blueprint prerequisite. These existing adaptations remain free, mutually
exclusive and replaceable; the active choice is marked. Other specializations
retain their existing discovery and one-mutation rules. Actual light-dependent
fixation effects, carbon inputs and resource accounting are unchanged.


Acidic water uses a stronger magenta response and a bounded nine-sample visual
footprint spanning neighboring field nodes. Buffer neutralization visibly
restores the same blue water over that footprint. This expands the readable
color patch without inventing a buffer concentration, changing physical acid
capacity, advection/diffusion or cell damage, or revealing private particles.


October 16 owner correction: restore the original ambient current amplitude,
superseding the 35% reduction. Flow target version 2 refreshes an older saved
target even within the same calendar hour, using that hour's existing seeded
weather choices. Actual water and all cell velocities remain saved and relax
normally; plant damping, full stream history and the stronger chemistry tint
remain enabled.


### AP-only construction and unmanaged anatomy (October 16, 2026)

Installing a standard organelle costs one AP, with no biomass or ATP construction
charge; restoring a lost organelle also costs one AP. Mutations remain free.
Membrane space still limits construction, and operating energy, repair, growth
and paid reproduction continue to use the existing finite cell resources.
The AP purchase explicitly introduces the organ's represented construction
tissue into the existing external-input ledger. Recycling and lysis conserve
that material; cancelling a local draft rolls back its introduced input too.
Saved existing anatomy is untouched by loading an update.

Persistent unmanaged lineages spend their existing AP on random fitting organs,
at most one purchase per lineage every two simulation seconds. Each lineage
uses its retained progression RNG and shared AP balance; failed fits cost
nothing. Every account-owned lineage remains managed, including disconnected
players. The authority excludes those roots before purchases. Division continues
to award two AP. Sun/Shade choices no longer occupy new random mutation slots;
previously offered and learned choices remain saved.



### Per-organelle output (October 16, 2026)

Each organelle's local menu has a saved Output setting cycling through 100,
150, 200, 300 and 400 percent. Steering is separate. Shared work-rate factors
scale thrust, pumping, gland throughput, repair and fixation. ATP costs scale
with work and a penalty of 5% per additional 100% output (200% work costs 210%
ATP for ordinary paid actions). Emissions still consume proportional biomass;
local carbon and light limit fixation. The setting itself is free and defaults
to100% for existing organs.

Receptors pay for expanded sampling reach and fall back to ordinary sensing
without ATP. GPU queries retain their prepared output; a range the body can no
longer fund supplies no new result. Protective cortex overdrive spends ATP to
reduce tissue damage; an unfunded hit uses ordinary armor. Photosynthesis pays
for additional fixation beyond baseline, so an empty ATP reserve can recover
normally. These are shared game abstractions, not universal cellular power laws.
The same physiology runs visible, resident and offscreen bodies.

### Acid-assisted nutrient binding (October 16, 2026)

Existing nutrient joining now accepts parcels up to200 units, rather than the
legacy5-unit limit used by the other small molecules. Local contact and facing
are still required. Mild acid broadens eligible facing alignment, with the same
0.4 optimum used by the existing acid-dependent enzyme rule; excess acid narrows
it again. Acid gland emissions feed the real local acidity field. Existing ATP
stress and sustained membrane damage from excessive acidity remain unchanged.

Binding carries a bounded, amount-weighted ATP-allocation benefit: each contact
adds0.4 times the smaller parcel's mass, capped at50% of food mass. Thus equally
sized fresh parcels gain20% ATP yield on their first join, with further joins
increasing the benefit. This is not extra chemical fuel. Digestion recovers
otherwise dissipated heat first, then allocates some tissue-producing fuel to
ATP; aerobic food therefore produces somewhat less biomass for its higher ATP
yield. Material becomes ordinary waste/carbon, and total fuel still pays for ATP,
retained biomass and heat. Depleted salvaged nutrients cannot refuel by joining.

External nutrient capacity below amount retains its original finite fuel meaning.
Above amount it encodes fully fueled food plus this allocation bonus; acid/buffer
capacity semantics are untouched. Uptake transfers it proportionally. Internal
food stores additive nutrition alongside unchanged fuel; the resident component
uses its previously unused clock.y without a pose mirror or a larger allocation.
Coalescing only mixes the benefit; resolution conversion itself never awards it.
Old packets default to zero bonus and loading an update does not alter saved
cells. Save/restore, partial intake, resident handoff and lysis retain the benefit.


### Clear sun/shade and caustics (October 16, 2026)

The owner rejected Revision 55's muted light and remaining repeated glow spots.
Revision 56 removes the independent fractal highlight pass. Strong deep-indigo
shade and turquoise sunlight follow the existing continuous light field, with
weather-aware visual exposure so dim conditions retain spatial contrast.
Irregular animated caustic curves appear only in lit water, follow world time
and respect the water-ripple setting. They add no energy, chemistry, fluid force
or camera displacement. See [Revision 56](REVISION_56.md).

### Investment and protected-cell options (October17,2026)
Revision59 supersedes random NPC buying:10%hunter assignments (rounded down), remaining bodies evenly producer/grazer. Policies override catalog randomness; preserve existing anatomy and all AP prices. Players may opt unattended relatives into saved family/cell strategies from the nucleus. Selected connected bodies remain manual.
New photosynthate keeps75% of the food inside and releases25% outside; all output debits real local carbon. Internal mitochondria redirect finite food fuel toward ATP when oxygen is present. Counterattack responds to local chemical warnings and spares unarmed bodies at contact.
The fictional Sanctuary prevents death/organ destruction, blocks offspring and awards2AP only after a full paid growth investment. Its toxin/pore material cannot harm player lineages; area-acid secretion/combat decoys are disabled. These are explicit game rules, not biological claims. See [Revision59](REVISION_59.md).

### Shade preference and normal organ activity (October17,2026)
Revision60 makes Shade leaves seek the darker local direction above0.45 light and brighter water below0.35; the middle band has no light drive. Sun/ordinary leaves retain light seeking. In-flight and held light intentions cannot override a changed preference. Steering and flight rules remain. Per-organelle Output/overdrive is retired: normal work/ATP rates apply, and saved percentages are retained but ignored. No saved cell is rewritten. See [Revision60](REVISION_60.md).

October17 continuation: [Revision60](REVISION_60.md) replaces manual Exploration/duty cycles and organ Steering percentages with one local-signal behavior tree for all cells. Survive harm, recover ATP, rebuild biomass, then hunt/explore; anatomy supplies abilities. Investment roles develop diverse complementary builds using actual anatomy and own condition, with the same AP/physiology rules. Future organs must review both systems, their tests and simple player guide. This supersedes earlier manual-gain instructions; retain legacy saved fields inert, all cells and both independent ponds.

Final Revision60 correction: Sanctuary is withdrawn entirely. Family retains current relatives/reserves plus lifetime total and highest generation, without deceased cards. The owner explicitly authorizes a fresh experimental pond for this large revision, with accounts/keys/private feedback retained and stable untouched; future ordinary updates remain persistent.

### Division inherits investment rather than anatomy (October17,2026)
[Revision61](REVISION_61.md) replaces cloned daughter builds with a new basic oral-groove body. Only the effective investment strategy is inherited; Manual selects Hunter, Producer or Grazer uniformly at successful birth. New anatomy and its lower reproduction quote use the ordinary finite material/ATP transfer. Daughter body overrides survive checkpointing and NPC assignment; reproductive success may change the population strategy mix. Parent organs and existing saved/dormant cells remain unchanged.

Revision61 AP continuation: each cell's next added/restored organ costs its current installed non-inherent organ count:0,1,2,...AP. Selling lowers the next price and refunds the actual AP paid minus1, floored at0. Oral anatomy is excluded. Shared price calculation covers manual, unattended, desktop and mobile building; existing anatomy determines cost without migration.

### Quarter-capacity low-power organs (October17,2026)
[Revision62](REVISION_62.md) replaces ATP-based shutdowns with a25% activity floor for functional movement, pumping, secretion, weapon recharge and active gland repair/cleaning. Full operation returns after ATP recovers, with separate entry/recovery thresholds to prevent flicker. Material, target and health prerequisites remain; no ATP is created, and unpaid residual work is an explicit gameplay rule. Passive energy recovery/senses/protection remain unchanged. Shared behavior allows low-power pursuit as a last locally cued option and investment favors feasible mitochondrial recovery.

### Family portraits (October 17, 2026)

The family menu pictures each current relative or dormant reserve with its actual membrane shape, lineage color, nucleus and installed organs. A tiny generation number sits in the bottom corner, like a factory badge, and the selected body stays marked. Pictures update while the menu is open; deceased relatives leave it. Off-camera owned anatomy is a compact presentation snapshot, separate from simulation models and camera interests. Rendering does not advance biology, grant resources or consume ecology RNG. Existing lineage counters, follow validation and ordinary persistent updates remain.

October 17 family-menu continuation: all current relatives and reserves appear in one responsive portrait grid on desktop and touch. The standalone G-generation tile and More pages are removed. Small header text keeps highest generation and lifetime total; each portrait keeps its tiny corner generation badge. The panel grows up to the screen bounds and scrolls only when needed, with Close fixed above the scrolling portraits. This changes presentation only.

### Direct living division (October 17, 2026)

Banked offspring are removed. A founder has no free hidden backup. Surplus
tissue and ATP still fund growth; a ready cell divides directly into a living
daughter when space and population limits allow. The growing bud has only
Divide now, with no fund/reclaim/store menu. A failed birth retains its numeric
growth investment and does not create a separate body. Basic daughter anatomy,
investment inheritance, 2AP per birth and living-family succession remain.
The owner waives old reserve/history retention for this revision: previously
stored bodies are discarded during ordinary authority ticking, with tissue
recorded in build_waste, rather than hatched or migrated. Save/reload boundaries
still preserve all actual living cells and both pond identities. The retired
checkpoint array is readable only to discard it; it has no gameplay use.
