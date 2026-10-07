# Primordia

A physics and chemistry simulation game about managing one small cell. Eat, grow and survive predation. **You never steer the cell:** its anatomy controls its behavior.

This twenty-fourth playable revision uses **Godot 4.7.2**, a fixed-step simulation, deformable membranes, oriented chemical particles and procedural 2D artwork. Its vector artwork is authored in the project; cached particle textures and mipmaps generate automatically at runtime. The default Linux launcher builds a batched C++ GDExtension automatically; the GDScript reference backend remains available.

## Run with Steam Godot on Linux

```sh
./tools/run.sh
```

First launch needs **Git, CMake 3.20+, a C++17 compiler and Python 3**. It fetches a pinned Godot C++ binding revision and builds with two jobs by default; set `PRIMORDIA_BUILD_JOBS=8` for an eight-job build when CPU/RAM are available. Later launches rebuild only when native source changes. Generated bindings and libraries stay in ignored `build/`. Use `PRIMORDIA_BACKEND=script ./tools/run.sh` for the slower reference backend without native build dependencies. Opening the project directly in Godot uses the native library if it has already been built; otherwise F3 identifies the GDScript fallback.

The launcher finds Godot in standard Steam locations, custom Steam libraries and Flatpak Steam installations. Steam need not be running. Use `./tools/run.sh --editor` to open the editor, then F5 to play. Discovery order is an explicit `GODOT_BIN`, Steam libraries, then `godot4`/`godot` on PATH. `STEAM_DIR` supports a nonstandard Steam client root.

## Controls

- **Tab:** pause and zoom inside your cell; press Tab again to keep edits and resume. Enter also resumes when no choice or placement is active. There are no Undo, Apply or Cancel-plan controls. **Escape** opens settings without discarding edits.
- **Click an intracellular factory:** the folded assembly ribbons offer eight physical organs; the chamber cluster offers the four chemistry organs. Choose a picture, then click the membrane. New organs have one fixed size and neighbors move aside. **1–9 / 0** remain construction shortcuts; **V** selects the hunting receptor. Cilia are available in the assembly factory.
- **Click an installed organ:** move, recycle or apply an already-kept matching blueprint. Grazing pores, hunting receptors and photosynthetic organs also offer **Steering**: click to cycle Off, 25%, 50%, 100%, 200% and 400%. This changes directional priority and following time versus exploration; size, power and feeding throughput stay unchanged. There is no resizing during placement or afterward. Recycling returns half the tissue and never refunds AP. Click a damaged attachment scar to restore its original anatomy.
- **Click the nucleus:** choose a blueprint and accept an optional challenge. Hover it for the next objective, crisis progress and forecasts; its family tree also offers known blueprints. **Click the offspring bud:** fund/reclaim reserves, release a juvenile, store a dormant successor or follow a living relative.
- **In edit mode, drag on bare cell surface:** place a microtubule between membrane, interior or existing-link points. Hover within 16 screen pixels of an unobstructed tube (scaled with text size) and scroll to adjust tension; right-click it to remove it. Factories and organ controls take precedence. **Right-click** cancels a held organ/move or closes local choices.
- **Wheel:** zoom around the cell in locked follow mode, or around the cursor in free view, from the 80% widest view to 12×. It never resizes organs. **Middle-drag** pans while editing or in free view. **Space** toggles position-follow without pausing or rotating the world. Leaving edit restores the previous observation view.
- **Hover particles:** a temporary local lens magnifies the surrounding scene and shows the particle's name and role. The sharp enlarged glyph follows its actual orientation. Moving away dismisses the effect; simulation continues. Cell interiors and a UI-scaled 24-pixel margin around every living membrane suppress the lens, including already tracked particles.
- **Keyboard editing:** **[ / ]** cycles cell targets, **Enter** opens/activates a choice, and arrow keys navigate the local choices or position a held organ around the membrane. Microtubules retain their direct mouse gestures.
- **Escape:** settings with Quit, fullscreen, bloom, and persistent **85–175% text/interaction size**. **F11:** fullscreen. **S:** sensing ranges. **F3:** optional backend/FPS/timing diagnostics, without a zoom percentage. **H:** next habitat. **R:** new expedition, retaining family history and discovered blueprints. Settings also opens **Family history**, including after defeat.

**While editing**, a translucent blob at the top right shows usable biomass. Selecting an organ adds a required-tissue blob on the same area scale. Equal blobs mean exactly enough tissue; pink means a shortfall. Reserved offspring tissue and existing body mass are excluded. The blobs disappear during play. Build mode also compares ATP production/spending sacs per second; hovering an installed organ adds its recent actual drain on the same scale. Construction/upgrade choices show estimated steady upkeep. Hover the internal ATP sac for exact recent income, spending, surplus and overflow; upgrade hover previews the upkeep change. Hovering an upgrade or construction choice also previews its real tissue/AP price; zero-AP restoration shows Free. Small gold blobs beneath the stock show one available adaptation point each; there are no internal coins or coin-transfer animations.

ATP is the fill of an internal sac; AP are small gold blobs beside the build-mode tissue display; biomass is cell size. Hover for resource details or membrane health. Stronger submerged wakes draw below all cells, and slow background water shimmer never distorts the scene (toggle it in Escape settings). Only the micrometer scale remains permanently at the edge; brief cell-local hints replace the screen panels. The scale measures the ordinary view, outside the temporary inspection lens.

Plant stems remain solid to cells and spikes, but all chemical particles permeate them in both visible and distant simulation. Food is no longer held behind a hard plant wall. Current-driven clouds still form; some previously collision-collected patches will disperse. The flow streamers now show three times as much trail history. See [Revision 23](docs/REVISION_23.md).

The world wraps without walls. The entire rectangular view simulates at full speed, including its corners and a short margin outside the screen. Living cells outside that margin advance on staggered one-second schedules: they move, metabolize, repair, photosynthesize and sense real pheromones. Wider statistical absorption consumes actual nearby particles; anatomy-weighted hunting rolls require a received prey cue and a wholly hidden encounter. A killed cell lyses into ordinary particles for predators or scavengers to collect—there is no automatic food award. Particles keep flowing and diffusing throughout the habitat: distant packets advance in staggered half-second steps, with coarse background fluid refresh. Pheromone expiry still uses real elapsed time. Nearby hidden chemistry uses the existing oriented reactions at reduced resolution. See [revision nineteen](docs/REVISION_19.md) for ecology balance and cost, and [revision eighteen](docs/REVISION_18.md) for transport. The active region follows the actual camera, including free view. Tab/settings pause biology; Space is solely a camera control.

## Adapt and establish a lineage

Start with **36 biomass and 3 adaptation points**. New fixed-size anatomy costs biomass and adaptation; existing damage repair, repositioning and microtubules do not cost adaptation. Keep one of three mutation blueprints each tide, then pay to specialize a matching organ. Local choices show costs; hover the ATP sac for stored fuel and an active-upkeep estimate.

The goal is to **establish your lineage through three crises**: Lean Current (2:00–6:00), Chemical Bloom (6:00–10:00), and Long Dusk (10:00–13:30). Each requires 60 observed seconds with at least 50% health, 10 ATP and recent feeding or carbon fixation. The final crisis must be earned by a descendant, who must also be healthy at the finish. The nucleus shows three progress arcs, exact requirements and the next useful action.

Two-minute tides forecast changing light, arrivals and costly opponent adaptations. Gain **2 AP** at each of the first five transitions; a chosen feeding, growth or stability challenge can earn **2 more** at its deadline, including the transition into the finale. There is one blueprint choice per tide, before the finale. Editing, settings and family history pause biology; looking elsewhere with the free camera does not pause the crisis clock or earn observed-cell viability.

Reproduction is available **as soon as you can fund it**. The bud quotes the additional tissue and **60 ATP** needed to inherit the current anatomy. Release a living juvenile or store a dormant successor. You can keep managing the parent or follow a living relative; anatomy still chooses its movement. Up to 12 oxygen transfers if available, and 20 of the reserved ATP pays division.

**Death continues in the same habitat.** Control passes to an existing living family member, or a prepaid dormant body hatches. AP, drafts, crisis progress, enemies and the family melody continue. One generation-zero reserve is included in the initial population; extra reserves cost real resources. There can be four living family members and three dormant reserves. Exhausting them ends the expedition.

Family history records generations and causes of death. Discovered blueprints persist locally and can replace a later expedition's ordinary draft choice; installing them still costs tissue/AP. No permanent stat bonuses are granted. See [revision sixteen](docs/REVISION_16.md) for current rules; [revision nine](docs/REVISION_9.md) preserves the original economy and mutation catalog.

**Shared biology, player-specific expedition:** other cells use the same physiology, particle interactions, anatomical costs and pheromone perception. AP, blueprint drafts, family management, dormant reserves and persistent discoveries are player-lineage systems. NPCs do not reproduce or maintain seed banks in this revision; bounded habitat arrivals/replacements maintain their population. They do not have a reproductive behavior tree.

## Anatomy

| Key | Organelle | Biomass cost | Role |
| --- | --- | ---: | --- |
| 1 | Flagellum | 8 | Supplies extra thrust and turns the detecting organ toward its target. |
| 2 | Protective cortex | 10 | Absorbs local damage before the membrane. |
| 3 | Hunting spike | 12 | Physical contact weapon. Strong impacts puncture hard; slow pressure causes smaller ATP-funded wounds. No detection or steering. |
| 4 | Repair body | 10 | Repairs damage, speeds receptor cleaning and releases acid buffers. |
| 5 | Grazing pore | 8 | Senses nutrients, pumps surrounding fluid, eats particles and secretes reusable digestive enzymes. |
| 6 | Flight receptor | 6 | Reads pheromones reporting larger or armed cells, faces their reported location and requests travel away. Only this organ triggers flight. |
| 7 | Photosynthesis | 12 | Seeks brighter water, fixes dissolved carbon into organic resources and releases oxygen. |
| 8 | Toxin vesicle | 12 | Fires damaging toxin and receptor-blocking decoy particles toward a chemically sensed cell. |
| 9 | Toxin neutralizer | 10 | Releases particles that bind toxin and make harmless material. |
| 0 | Acid gland | 12 | Releases acidifying particles to change local digestion conditions. |
| V | Hunting receptor | 6 | Reads local pheromones from smaller **or undefended** prey; faces and pursues the reported location. |

Proboscis and engulfing pores have been removed. The spike and toxin vesicle are the weapons. The hunting receptor compares reported total organic material with its own cell. “Undefended” means no working spike, toxin vesicle or protective cortex at emission; it never checks the live source. A hunting receptor or photosynthetic organ can guide pursuit; flagella provide additional power. Toxin vesicles use a report received by a hunting or flight receptor, and flight takes priority when both senses respond.

New player organs have a fixed size. Surface area, biomass and adaptation constrain new construction; existing NPC/inherited anatomy keeps its physical dimensions. Biomass growth has no arbitrary upper cap, although the finite toroidal habitat remains a geometric limit. Hydrostatic pressure, a soft cortex and the player-authored tension network control shape. New cells start with 0–4 seeded, randomly tensioned links; later links can branch from earlier ones. Offspring inherit edited networks. Internal unattached junctions move freely; connect them to the membrane/network to transmit useful shape forces.

Larger cells have proportionally greater membrane drag: doubling radius roughly halves swimming speed at equal propulsion. Currents can still carry them, and more propulsion still helps. Cells push, spin and slide against one another and solid plant stems. Membranes compress locally and recover under pressure; spikes physically catch cells and stems before the body reaches them. Impact damage depends on actual impulse, so a few strong hits can kill exposed prey; armor still takes damage first. Place spikes around a hunting receptor and invest in propulsion to line up repeated strikes. A poorly aligned or slow hunter may only push prey away. See [revision seventeen](docs/REVISION_17.md) for the contact model and evidence.

## Membranes and visible flow

Cells have rounded, shaded membrane lips and a soft gel interior that follow their actual deformed outline. Lineage colors remain independent of diet or occupation. Pale animated streamers replace the background flow vectors; longer trails show faster current and their bright ends show direction. Faint downstream glints appear around cells moving relative to the water and around sturdy plant stems. These are bounded presentation effects, not extra chemical particles or new fluid forces. [Revision twenty](docs/REVISION_20.md) records the implementation and wide-view rendering checks.

## Living techno

Music is a core design element. An original 128 BPM progressive score gives each organelle type a distinct rhythm and register; hunting and flight share the receptor timbre. Nearby anatomy becomes louder and busier; larger cells sound lower, with an approaching giant announcing itself as a quiet bass presence. A longer arrangement supplies breakdowns, builds and melodic returns.

Each lineage has a recognizable melody that offspring inherit; anatomy changes its orchestration. Bright water opens the synth filters, acidity adds grit and instability, and buffering calms it. Eating adds rhythmic fills, toxin neutralization adds answering chimes, and division resolves into a short phrase. Biology remains independent of the beat.

Escape settings offer **Music volume** control. Particle beat pulsing and its slider have been removed; particle glyphs stay steady. Editing keeps a quieter groove. The soundtrack uses generated, cached instruments and a bounded native mixer, with a GDScript fallback; no soundtrack downloads are required. [Revision fourteen](docs/REVISION_14.md) describes the inherited themes, habitat effects, event phrases, listening preview and wide-view measurements; [revision twelve](docs/REVISION_12.md) documents the original instruments.

## Living chemistry

**Cells are the only sources of external particles.** The initial clouds represent products of the existing cells' earlier life, with source-cell identifiers. There is no automatic food/oxygen habitat spawner. Respiration, lower-yield fermentation, photosynthesis, secretion, wounds, recycling and death sustain the particle economy. Replacing a dead NPC is an explicit population event with accounted material input. Hidden replacement remains preferred; forecasted tides can admit a bounded number of arrivals into safe visible space when wide zoom leaves no hidden habitat.

**Combining hunting and grazing:** try hunting at 200% and grazing at 25%. Weights select one organ and direction, with a 20% switching margin to prevent near-tie oscillation. Stronger valid hunting cues retain pursuit even when an older food signal reaches the nucleus later. Once hunting memory expires, grazing can steer toward released nutrients. Grazing steering Off keeps suction, digestion and absorption active, but does not navigate toward food. Explicit flight always wins. Family pheromones, delayed internal family signals and remembered family targets are ignored; parent/offspring spikes still collide physically without tissue injury. See [Revision 22](docs/REVISION_22.md).

Membrane organs, placement previews, pore mouths, weapon shafts and secretion outlets use the local outward membrane normal. Deforming the cell changes their mounting direction. Reversible flagella apply force along their mounted axis, and the selected receptor's normal defines its facing request.

Successful two-particle reactions produce a brief white-gold contact spark. These bounded visual effects do not change chemistry or diffusion.

**Cells only learn about other cells through pheromones.** Every active creature releases small signal points that drift with current, diffuse and decay rapidly (mean lifetime 5 seconds). They pass through cells, reefs and other particles. Nearby receptors read the source's location, size, hostile anatomy and defense status **as they were at release**; a distant plume may be stale, and losing it ends pursuit. No live target tracking bypasses the trail. Hover a point to inspect its reported size, armed/defended status and age. [Revision 13](docs/REVISION_13.md) describes the rules and validation.

Eleven particle types are visible: nutrient, oxygen, waste, pheromone, toxin, dissolved carbon, digestive enzyme, antitoxin, acidifying carrier, buffer and decoy. Forks, hooks, combs and linked lobes distinguish reacting species; their bright tips rotate with the actual particle orientation. Pheromones are non-oriented points. Compatible faces must touch and point toward each other to react; there is no additional reaction success roll. Thermal motion tumbles particles, and decay uses a per-second hazard instead of a fixed lifetime. Neighbor searches use spatial grids rather than all-pairs testing.

| Encounter | Result |
| --- | --- |
| Waste + oxygen | Recycled nutrient and dissolved carbon. |
| Enzyme + waste | Nutrient; the enzyme remains reusable. |
| Antitoxin + toxin | Harmless waste containing both packets' material. |
| Toxin + nutrient | Spoiled nutrient becomes waste. |
| Compatible nutrient packets | A larger edible packet with their combined value. |
| Acid + buffer | Their remaining acid/buffer capacities neutralize. |
| Decoy + chemical receptor | Temporary occupancy reduces sensing range. |

Light varies smoothly across the habitat and is visible in the water. Photosynthesis requires both light and carbon; light supplies energy, while water is an implicit reservoir for oxygen production. Photosynthetic cells release food and oxygen for neighbors.

Acidity is a local transported field: increasing acidity shifts blue/teal water toward rose/magenta; buffering restores its normal color. Moderate acidity favors the modeled digestive enzyme. Excess acidity raises maintenance ATP costs, accumulates internal stress, slows metabolism and eventually damages cells. Buffers have finite capacity. The secreting cell is also exposed. Nutrient assembly does **not** gain an automatic acid bonus.

Decoys temporarily reduce chemical sensing range. Every affected receptor automatically spends a little ATP to clean itself, repair bodies accelerate clearance, and passive release still works with no ATP. Purple rings and organ hover descriptions show the effect. Light sensing is unaffected.

Pores pulse on consumption. The ATP sac shows current energy; damaged membranes/organs and hover descriptions show health. Yellow sac-to-surface packets illustrate ATP spending; pink nucleus-to-surface packets illustrate biomass-funded repair. External particles are shunted to the membrane edge instead of rendering underneath cells.

The former 90-second food milestone has been replaced by lineage victory. The starting anatomy is a starting point for adaptation, not a guaranteed unattended win. Balanced habitat stages three reserved hunter arrivals after the first warning in each crisis; lean and rich profiles retain their opening hunters.

## Performance revision

Revision twenty-one profiles complete live frames and batches particle indexing, hidden chemistry, feeding, contact rejection, membrane dents, scheduling and mesh generation. It retains 60 Hz simulation, the full visible halo, particle populations, music and all visual effects. See [whole-frame results and reproducible commands](docs/REVISION_21.md) for dense 80% view, grown-cell and hunter-encounter measurements; F3 labels CPU tick and view-sync costs separately.

Revision seven adds compiled particle transport, orientation chemistry, spatial grids, membrane exclusion, edge/pressure constraints and particle drawing buffers. Fluid viscosity and acidity transport run in native batches, and feeding pumps visit only nearby fluid nodes. Tiny distant cells use less decorative drawing; contact and chemistry still advance at the fixed simulation rate.

A Vulkan compute transport experiment is included, but **is not enabled by default**: measurements found that the current CPU/GPU transfer bridge costs more than native CPU transport. It can be tried with `./tools/run.sh --rendering-method mobile -- --gpu-transport`. It does not move chemistry or the entire game onto the GPU. See the [benchmark results and remaining limits](docs/REVISION_7.md).

## Procedural habitat

Procedural generation and fractals are now a core visual direction. Large plant-like colonies include paired-leaf ferns, branching fans, curled spiral rosettes and radial colonies with five or seven arms. Each family has two seeded procedural variants. Their stout stems obstruct cells; chemical particles permeate them. Contact slides along branches without consuming material. Fine fronds are decorative, and the scenery does not add food or oxygen sources.

Water gains broad blue, teal, jade and violet regions from seamless multiscale noise. These patterns stay fixed in world space, with existing light, acidity tint and bloom layered over them. Plant art is cached in eight mipmapped textures per habitat. See [revision fifteen](docs/REVISION_15.md) for current shapes, the offscreen simulation margin and wide-view measurements, and [revision eight](docs/REVISION_8.md) for the original collision scope. These additions do not solve the remaining whole-game frame-rate problem documented in revision seven.

## Graphics and proposed chemistry

[Revision ten](docs/REVISION_10.md) adds deep indigo/petrol water, turquoise light pools, broad colored membranes and seeded lineage palettes. **Body color never depends on occupation:** organelles and emitted particles communicate function. Larger internal shapes, integrated organ bases, rounded secretory glands and cached wide-zoom chemistry silhouettes make the vector artwork clearer. Fractal colonies form loose reefs with thicker, matching solid stems. Highlight-selective bloom follows the actual light resource; soft peripheral blur keeps the center and HUD sharp without a dark vignette. Blur remains active when bloom is disabled.

[Complement-inspired mechanics](docs/COMPLEMENT_PROPOSAL.md) are proposed next: surface tags, cooperative pore assembly and protective inhibitors. They are not enabled in this graphics revision.

[Action economy proposal](docs/ACTION_ECONOMY_PROPOSAL.md) retains the approved design rationale and future alternative endings. Its first prototype is documented in [Revision 9](docs/REVISION_9.md); [revision sixteen](docs/REVISION_16.md) introduces the current crisis and succession rules.

## Science and scope

[references.md](references.md) records a real phenomenon and source for each biological/physical mechanic, plus the differences between evidence and game rules. Maintain it as mechanics evolve.

This is a coarse 2D game, not molecular dynamics or a full biochemical network. “Microtubules” are generic tension links; real microtubules also bear compression. The membrane remains star-shaped for stable rendering. Fluid is a finite-mass viscous grid, not an incompressible Navier–Stokes solver. Acidity is an acid-equivalent field, not calibrated pH. Growth, repair, metabolism and reactions use explicit coarse material accounting rather than atom-by-atom stoichiometry.

Family history and discovered blueprint options save locally to Godot's user data directory. The live habitat is not saved across application restarts, and there are no permanent stat upgrades or packaged releases yet. Same-seed reproducibility is checked on one engine/platform, not promised across platforms. Diet balance, dense chemistry and long authored networks need playtesting.

## Verification

```sh
./tools/test.sh
python3 tests/test_launchers.py
```

The test launcher uses the same Steam discovery and fails on assertions or Godot script errors. Native tests build the extension first. Run `PRIMORDIA_BACKEND=script ./tools/test.sh` to verify the independent fallback too. Wide-view performance checks and per-item ablations are described in [revision seven](docs/REVISION_7.md) and [revision twelve](docs/REVISION_12.md). `tests/profile.gd` is a historical close-view diagnostic, not performance acceptance. F3 during play measures the real frame rate.

For a rendered capture with a display:

```sh
./tools/run.sh -- --capture=/absolute/path/primordia.png
```

Optional capture flags include `--habitat=0`, `--advance=600`, `--assembly`, `--settings`, `--hud-scale=1.75` and `--senses`. Put habitat selection before advance. Capture output belongs outside source control.

The owner's separate Linux **Steam Godot 4.7.2 / RTX 3090 / Threadripper 2990WX** machine remains unavailable to this task. It is an upper-capacity reference, not minimum hardware. See [revision-seven performance results](docs/REVISION_7.md), [revision-six graphics notes](docs/REVISION_6.md), [architecture](docs/ARCHITECTURE.md) and [persistent design](docs/DESIGN.md).

Only authored source and stable Godot `.uid` identifiers are tracked. `.godot/` imports and caches regenerate automatically. Engine downloads, captures, logs and exports are not committed. No redistribution license has been granted for this private project.

## Cell interface and inspection

[Revision eleven](docs/REVISION_11.md) replaces the screen panels with cell-local construction, resource displays, nucleus/offspring controls and a temporary particle magnifier. The [original proposal](docs/CELL_INTERFACE_PROPOSAL.md) is retained with the owner's amendments; its Undo and resize ideas were rejected.

The magnifier briefly follows the selected particle after it drifts away from the pointer, keeping its tooltip and orientation stable. Deliberate pointer movement releases it. [Revision fifteen](docs/REVISION_15.md) covers tracking, camera-edge simulation and the new plant families.

## Revision 24: food patches and breathing room

ATP from food is more productive and routine operation is cheaper, with the same prices for visible and offscreen cells. Repair/combat, AP, tissue prices, crisis goals and finite fuel remain. See [Revision 24](docs/REVISION_24.md) for parameters and validation.

In build mode, click the **nucleus → Behavior** to cycle **Exploration** (Off / 25 / 50 / 100 / 200 / 400%) and **Cycle** (2 / 4 / 8 seconds). Default exploration is 25% with a four-second cycle. Each organ's steering gain determines its share of following time against this wandering weight: 100% signal versus 25% exploration means 80% following and 20% exploration; 25% versus 25% splits time equally. Flight always takes priority. Hover the organ for its current split. Tuning costs no tissue, ATP or AP and paid offspring inherit it.

Grazing selects a locally sensed nutrient patch by mass, heads toward its centroid at distance, then targets actual particles nearby. A remote patch outside receptor reach is still unknown. No direct movement control or live-cell lookup is added.

Death holds the camera on the membrane rupture for 1.15 seconds, then eases toward the actual successor over 0.65 seconds. Biology continues normally; there is no extra invulnerability or respawn reward. Wakes follow local fluid-relative motion, and a current-carried cell has little directional wake.

The player starts with a grazing pore and **neither cilia nor a flagellum**. Both remain separate fixed-size assembly purchases, each costing eight tissue and one AP. Flagella emphasize thrust; cyan ciliary bands add weaker thrust plus a stronger directional local feeding current. Cilia use the receptor/exploration-selected heading, add no sensing or absorption, and pull hazards along with food. The current acts on the real fluid and returns equal/opposite momentum to the cell in detailed and coarse simulation. NPC flagella remain unchanged; offspring inherit paid anatomy normally. Cilia also contribute their own synthesized flutter-pluck rhythm.
