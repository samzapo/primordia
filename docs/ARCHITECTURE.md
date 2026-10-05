# Living cell architecture

## Authoritative simulation

`simulation.gd` advances at 60 Hz independently of scene/input code. Player and NPCs share anatomy, resources, pressure membranes, sensing, secretion, feeding, damage and death. Fixed seeds are checked for reproducibility on the same engine/platform.

The 4096 × 2560 torus uses nearest-image offsets. The camera defines the active ellipse, including when unlocked: full activity in the center, reduced activity in the vignette, frozen state beyond it except explicit replacement triggers. A 64-unit persistent spatial grid serves transport, feeding and sensing. A separate 16-unit reaction grid contains only active particles, keeping close-contact candidate sets small. Particle compaction occurs twice per second; it is maintenance, not a timed chemical reaction.

A tick updates fluid, activity and pumps; transports particles; runs decay and orientation-gated chemistry; updates receptor clearance, sensing, feeding, acid stress, photosynthesis, metabolism and repairs; solves membranes; emits cell products; integrates three motion/contact substeps; applies spike, toxin and decoy contact; excludes exterior particles; and handles death/population triggers.

## Materials and anatomy

Retained organic material includes body, build reserves, organs, substrate, waste and dissolved carbon. ATP and oxygen are separate coarse resource ledgers. Construction transfers biomass into anatomy; repair transfers it into body/organ structure. Organic decay is recorded as loss. Dead cells release retained material once; replacement NPC mass is explicit external input. Initial particle clouds are assigned to source cells and debited from their pre-observation stocks. No habitat particle replenishment remains.

Projected radius follows the cube root of body plus reserves without an arbitrary growth cap. Surface area, scaled organ footprints and biomass limit construction; shrinkage can shed organs. Stable material coordinates anchor organs, while insertion displaces neighbors without reordering them. Cost/health scale with area. Effective inertial mass and rotation remain deliberately reduced for responsive motion.

Grazing pores absorb nutrients and pump actual fluid. Spikes use lower total organic biomass as the prey criterion and sense cell traces at long range. A target signal distinguishes facing direction from travel direction: flight faces a threat and retreats; other senses approach. Flagella, an actively pursuing spike, or an active photosynthetic organ generate thrust with opposite fluid impulses. A paired steering impulse rotates the detecting organ toward the target. Toxin vesicles use existing target signals and spend material/ATP on toxin and decoy packets.

Spike collisions use the finite tip segment against a prey's radial support, routing damage through local armor first. They do not engulf or automatically transfer food. Wounds/death make particles for pores to eat. Toxin damage scales with packet amount, and a packet can be consumed only once.

## Shape and direct tension editing

`membrane.gd` solves 28 ordered boundary nodes with compliant edges, enclosed-area pressure, bending, damping, fluid traction and a softly contracting cortex. Polar sector stabilization and positive-radius interpolation prevent self-crossing render polygons. Contact is a swept radial proxy, not a full deformable manifold.

`cytoskeleton.gd` is a tension-only network. Endpoints can use fractional membrane coordinates, free interior points, or junctions created by splitting an existing link. Split segments retain their group/tension. Removing a group retains junctions used by other links. Rest lengths scale with growth. The normalized tension control contracts target span from 100% to 35%; it is not force in newtons.

While the build menu is open, direct left press/release creates endpoints. Creation, tension changes, removal and editing previews are disabled outside build; closing the menu cancels an unfinished drag. Hover-wheel edits tension, with a native hint; right-click removes a group. Anatomy placement takes precedence when an organ is selected. Paused edits run bounded membrane relaxation without advancing biology. There is no microtubule build-menu entry. Interior links affect the membrane only through connected anchors.

## Particle chemistry and orientation

Each external particle stores species, organic amount where relevant, source/owner, position/velocity, orientation, spin, prior transform, activity caches and optional acid/buffer capacity. Translational/rotational thermal noise operates only in active water. Asymmetric glyphs rotate with the interpolated authoritative orientation, and packet size reflects retained amount. Bright terminal marks face along the same +X axis used by the reaction checks.

The chemistry pass builds the fine active grid once. Decay uses `1-exp(-rate*local_dt)` and has no fixed age deadline. Pair reactions check distance, binding-face dot products and species/environmental rules. Both faces normally accept a 60-degree half-angle. Successful contact always reacts; no success RNG is consulted. One packet participates in at most one pair reaction per tick. Unsuccessful overlaps receive soft separating velocity impulses.

Waste/oxygen recycling transforms two packets into nutrient/carbon. Enzymes turn waste into food without consuming the catalyst. Antitoxin/toxin sequesters both amounts into waste. Toxins spoil nutrients. Compatible packets can aggregate below a material cap. Reaction/decay accounting is intentionally coarse: oxygen units, water, minerals, ions and full stoichiometry are unresolved. Packet aggregation is not spontaneous polymer synthesis. See `references.md`.

## Light, acidity and receptor competition

Light is a smooth, periodic scalar habitat field used by both gameplay and the background shader. Its gradient guides photosynthetic organs. Carbon-limited fixation events produce retained organic material, secreted nutrient and oxygen; water is implicit. Darker habitats reduce productivity. Photosynthetic emission events remain stochastic biological processes; pairwise chemical reactions are orientation-controlled.

`acidity.gd` holds a bounded acid-equivalent grid. Visible water undergoes coarse semi-Lagrangian transport, diffusion and dilution. Acid carriers release finite capacity; buffers take up available acid, and spent carriers become waste. Compatible acid/buffer contacts also neutralize capacity. This is neither calibrated pH nor a strictly conserved atom/ion field. The shader samples its texture for a pink environmental tint.

An acid-hydrolase-inspired affinity curve favors moderate acidity; the changed angular acceptance is an explicit approximation of pH-dependent activity. Extreme acidity blocks that enzyme. Nutrient aggregation receives no acid bonus. Every cell spends ATP on acidic-environment maintenance; sustained excess exposure or inadequate energy increases stress, reducing metabolism and eventually health. Stress recovers in suitable water.

Foreign decoys bind aligned chemical receptors on contact. Occupancy reduces sensing reach, never below 35% of baseline. It clears passively, with extra ATP-funded clearance and a repair-body multiplier. Consumed decoy material becomes cellular waste. Photosynthetic light sensing is exempt. Rings/status and actual ATP packets make blocking and recovery visible; no permanent disable is possible after the cloud is gone.

## Rendering and controls

Native overlays provide ten illustrated organ cards, health/ATP bars, persistent HUD scaling and fullscreen. Tab pauses assembly; Escape toggles settings with Quit. Space locks/unlocks position-follow camera, never pauses or counter-rotates the world. Free view pans with background drag or middle-drag. Camera transform, active ecology and particle queries use the same center.

Cell drawings cache by render revision and interpolate world poses. Species use bulk MultiMeshes; orientation and amount affect each particle transform. Authored SVG path strings in particle_art.gd rasterize once into 11 cached textures with mipmaps. A shared unshaded material samples them; there are no per-particle nodes or per-frame vector rasterization. The decorative branches remain inside the circular contact envelope and do not add binding sites. The background visualizes light and acidity, with a reversible turquoise-to-rose/magenta color ramp. A separate screen-reading pass gathers nine nearby brightness samples for a small halo, gated by the actual habitat light field. It avoids a full-screen mipmap blur pyramid and skips halo sampling in dark water. It runs before the vignette and HUD; a saved bloom setting can disable the pass. Exterior particle shunting is deliberately nonphysical; both physics and render interpolation avoid drawing them inside cells. ATP/repair travel packets are cosmetic illustrations of already-applied resource debits.

Tests cover geometry, budgets, fluid momentum, stochastic decay statistics, aligned/misaligned contact, catalytic reuse, neutralization, receptor cleanup, source provenance, acid stress, light-seeking fixation, shared combat, dormancy, seeded replay, sustained ecology and actual GUI input. Rendered captures and crowded-contact stress checks cover drawing and quit behavior. Performance figures and limits belong in `REVISION_5.md` and `REVISION_6.md`.
