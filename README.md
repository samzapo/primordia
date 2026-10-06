# Primordia

A physics and chemistry simulation game about managing one small cell. Eat, grow and survive predation. **You never steer the cell:** its anatomy controls its behavior.

This thirteenth playable revision uses **Godot 4.7.2**, a fixed-step simulation, deformable membranes, oriented chemical particles and procedural 2D artwork. Its vector artwork is authored in the project; cached particle textures and mipmaps generate automatically at runtime. The default Linux launcher builds a batched C++ GDExtension automatically; the GDScript reference backend remains available.

## Run with Steam Godot on Linux

```sh
./tools/run.sh
```

First launch needs **Git, CMake 3.20+, a C++17 compiler and Python 3**. It fetches a pinned Godot C++ binding revision and builds with two jobs; later launches rebuild only when native source changes. Generated bindings and libraries stay in ignored `build/`. Use `PRIMORDIA_BACKEND=script ./tools/run.sh` for the slower reference backend without native build dependencies. Opening the project directly in Godot uses the native library if it has already been built; otherwise F3 identifies the GDScript fallback.

The launcher finds Godot in standard Steam locations, custom Steam libraries and Flatpak Steam installations. Steam need not be running. Use `./tools/run.sh --editor` to open the editor, then F5 to play. Discovery order is an explicit `GODOT_BIN`, Steam libraries, then `godot4`/`godot` on PATH. `STEAM_DIR` supports a nonstandard Steam client root.

## Controls

- **Tab:** pause and zoom inside your cell; press Tab again to keep edits and resume. Enter also resumes when no choice or placement is active. There are no Undo, Apply or Cancel-plan controls. **Escape** opens settings without discarding edits.
- **Click an intracellular factory:** the folded assembly ribbons offer six physical organs; the chamber cluster offers the four chemistry organs. Choose a picture, then click the membrane. New organs have one fixed size and neighbors move aside. **1–9 / 0** remain construction shortcuts.
- **Click an installed organ:** move, recycle or apply an already-kept matching blueprint. There is no resizing during placement or afterward. Recycling returns half the tissue and never refunds AP. Click a damaged attachment scar to restore its original anatomy.
- **Click the nucleus:** choose a blueprint and accept an optional challenge. Hover it for tide timing and forecasts. **Click the offspring bud:** fund or reclaim reproductive reserves; after division it reports viability.
- **In edit mode, drag on bare cell surface:** place a microtubule between membrane, interior or existing-link points. Hover an unobstructed tube and scroll to adjust tension; right-click it to remove it. Factories and organ controls take precedence. **Right-click** cancels a held organ/move or closes local choices.
- **Wheel:** zoom around the cursor, from the 80% widest view to 12×. It never resizes organs. **Middle-drag** pans while editing or in free view. **Space** toggles position-follow without pausing or rotating the world. Leaving edit restores the previous observation view.
- **Hover particles:** a temporary local lens magnifies the surrounding scene and shows the particle's name and role. The sharp enlarged glyph follows its actual orientation. Moving away dismisses the effect; simulation continues.
- **Keyboard editing:** **[ / ]** cycles cell targets, **Enter** opens/activates a choice, and arrow keys navigate the local choices or position a held organ around the membrane. Microtubules retain their direct mouse gestures.
- **Escape:** settings with Quit, fullscreen, bloom, and persistent **85–175% text/interaction size**. **F11:** fullscreen. **S:** sensing ranges. **F3:** optional backend/FPS/timing diagnostics, without a zoom percentage. **H:** next habitat. **R:** new life.

ATP is the fill of an internal sac; AP are spinning coins; biomass is cell size. Hover for resource details or membrane health. Only the micrometer scale remains permanently at the edge; brief cell-local hints replace the screen panels. The scale measures the ordinary view, outside the temporary inspection lens.

The world wraps without walls. The microscope center simulates fully, the fringe slows, and offscreen state freezes except for explicit population triggers. The active region follows the actual camera, including free view. Tab/settings pause biology; Space is solely a camera control.

## Adapt and establish a lineage

Start with **36 biomass and 3 adaptation points**. New fixed-size anatomy costs biomass and adaptation; existing damage repair, repositioning and microtubules do not cost adaptation. Keep one of three mutation blueprints each tide, then pay to specialize a matching organ. Local choices show costs; hover the ATP sac for stored fuel and an active-upkeep estimate.

Six two-minute tides forecast changing light, population pressure and costly opponent adaptations. Gain 3 AP per transition before the finale; optional risks can earn at most one extra. The clock pauses during cell editing or settings, but continues when the free camera looks elsewhere.

Fund an offspring's quoted additional tissue and **60 ATP** before **12:00**. Up to **12 oxygen** transfers if available; fermentation permits oxygen-poor reproduction. Division partitions existing body tissue and transfers real reproductive reserves and the camera follows the offspring. Sustain it for at least 60 healthy, metabolically active seconds through the **13:30** finale to establish a lineage. Death or missing the objective ends the run; **R** restarts. [Revision 9](docs/REVISION_9.md) lists every cost, mutation, counter and victory rule.

## Anatomy

| Key | Organelle | Biomass cost | Role |
| --- | --- | ---: | --- |
| 1 | Flagellum | 8 | Supplies extra thrust and turns the detecting organ toward its target. |
| 2 | Protective cortex | 10 | Absorbs local damage before the membrane. |
| 3 | Hunting spike | 12 | Reads local pheromones from lower **total biomass** cells, pursues their reported location and punctures with its tip. |
| 4 | Repair body | 10 | Repairs damage, speeds receptor cleaning and releases acid buffers. |
| 5 | Grazing pore | 8 | Senses nutrients, pumps surrounding fluid, eats particles and secretes reusable digestive enzymes. |
| 6 | Flight receptor | 6 | Reads pheromones reporting larger or armed cells, faces their reported location and requests travel away. Only this organ triggers flight. |
| 7 | Photosynthesis | 12 | Seeks brighter water, fixes dissolved carbon into organic resources and releases oxygen. |
| 8 | Toxin vesicle | 12 | Fires damaging toxin and receptor-blocking decoy particles toward a chemically sensed cell. |
| 9 | Toxin neutralizer | 10 | Releases particles that bind toxin and make harmless material. |
| 0 | Acid gland | 12 | Releases acidifying particles to change local digestion conditions. |

Proboscis and engulfing pores have been removed. The spike and toxin vesicle are the weapons. Spike target size uses all retained organic material, not just unspent building reserves. A spike or photosynthetic organ can guide and propel a cell; flagella provide additional power. Toxin vesicles use a target found by a spike or flight receptor.

New player organs have a fixed size. Surface area, biomass and adaptation constrain new construction; existing NPC/inherited anatomy keeps its physical dimensions. Biomass growth has no arbitrary upper cap, although the finite toroidal habitat remains a geometric limit. Hydrostatic pressure, a soft cortex and the player-authored tension network control shape. New cells start with 0–4 seeded, randomly tensioned links; later links can branch from earlier ones. Offspring inherit edited networks. Internal unattached junctions move freely; connect them to the membrane/network to transmit useful shape forces.

## Living techno

Music is a core design element. An original 128 BPM progressive score gives each organelle type a distinct instrument and rhythm. Nearby anatomy becomes louder and busier; larger cells sound lower, with an approaching giant announcing itself as a quiet bass presence. A longer arrangement supplies breakdowns, builds and melodic returns.

Escape settings offer independent **Music volume** and **Particle beat response** controls. Particle glyphs breathe locally with the beat without changing their chemistry or motion. Editing keeps a quieter groove. The soundtrack uses generated, cached instruments and a bounded native mixer, with a GDScript fallback; no soundtrack downloads are required. [Revision twelve](docs/REVISION_12.md) describes the instruments, performance measurements and further immersion ideas.

## Living chemistry

**Cells are the only sources of external particles.** The initial clouds represent products of the existing cells' earlier life, with source-cell identifiers. There is no automatic food/oxygen habitat spawner. Respiration, lower-yield fermentation, photosynthesis, secretion, wounds, recycling and death sustain the particle economy. Replacing a dead NPC is an explicit population event with accounted material input. Hidden replacement remains preferred; forecasted tides can admit a bounded number of arrivals into safe visible space when wide zoom leaves no hidden habitat.

**Cells only learn about other cells through pheromones.** Every active creature releases small signal points that drift with current, diffuse and decay rapidly (mean lifetime 5 seconds). They pass through cells, reefs and other particles. Nearby receptors read the source's location, size and hostile anatomy **as they were at release**; a distant plume may be stale, and losing it ends pursuit. No live target tracking bypasses the trail. Hover a point to inspect its reported size, armed status and age. [Revision 13](docs/REVISION_13.md) describes the rules and validation.

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

The former 90-second food milestone has been replaced by lineage victory. The starting anatomy is a starting point for adaptation, not a guaranteed unattended win. Balanced habitat delays its first three hunter arrivals until Lean Current; lean and rich profiles retain their opening hunters.

## Performance revision

Revision seven adds compiled particle transport, orientation chemistry, spatial grids, membrane exclusion, edge/pressure constraints and particle drawing buffers. Fluid viscosity and acidity transport run in native batches, and feeding pumps visit only nearby fluid nodes. Tiny distant cells use less decorative drawing; contact and chemistry still advance at the fixed simulation rate.

A Vulkan compute transport experiment is included, but **is not enabled by default**: measurements found that the current CPU/GPU transfer bridge costs more than native CPU transport. It can be tried with `./tools/run.sh --rendering-method mobile -- --gpu-transport`. It does not move chemistry or the entire game onto the GPU. See the [benchmark results and remaining limits](docs/REVISION_7.md).

## Procedural habitat

Procedural generation and fractals are now a core visual direction. Large radial plant-like colonies grow from a seeded recursive branching grammar, with five-, six- and sevenfold symmetry. Their stout stems obstruct cells and drifting particles; contact slides along branches without consuming material. Fine fronds are decorative, and the scenery does not add food or oxygen sources.

Water gains broad blue, teal, jade and violet regions from seamless multiscale noise. These patterns stay fixed in world space, with existing light, acidity tint and bloom layered over them. Plant art is cached in six mipmapped textures per habitat. See [revision eight](docs/REVISION_8.md) for collision scope and wide-view benchmarks. These additions do not solve the remaining whole-game frame-rate problem documented in revision seven.

## Graphics and proposed chemistry

[Revision ten](docs/REVISION_10.md) adds deep indigo/petrol water, turquoise light pools, broad colored membranes and seeded lineage palettes. **Body color never depends on occupation:** organelles and emitted particles communicate function. Larger internal shapes, integrated organ bases, rounded secretory glands and cached wide-zoom chemistry silhouettes make the vector artwork clearer. Fractal colonies form loose reefs with thicker, matching solid stems. Highlight-selective bloom follows the actual light resource; soft peripheral blur keeps the center and HUD sharp without a dark vignette. Blur remains active when bloom is disabled.

[Complement-inspired mechanics](docs/COMPLEMENT_PROPOSAL.md) are proposed next: surface tags, cooperative pore assembly and protective inhibitors. They are not enabled in this graphics revision.

[Action economy proposal](docs/ACTION_ECONOMY_PROPOSAL.md) retains the approved design rationale and future alternative endings. Its first prototype is implemented in [Revision 9](docs/REVISION_9.md).

## Science and scope

[references.md](references.md) records a real phenomenon and source for each biological/physical mechanic, plus the differences between evidence and game rules. Maintain it as mechanics evolve.

This is a coarse 2D game, not molecular dynamics or a full biochemical network. “Microtubules” are generic tension links; real microtubules also bear compression. The membrane remains star-shaped for stable rendering. Fluid is a finite-mass viscous grid, not an incompressible Navier–Stokes solver. Acidity is an acid-equivalent field, not calibrated pH. Growth, repair, metabolism and reactions use explicit coarse material accounting rather than atom-by-atom stoichiometry.

There are no saves, permanent progression or packaged releases yet. Same-seed reproducibility is checked on one engine/platform, not promised across platforms. Diet balance, dense chemistry and long authored networks need playtesting.

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
