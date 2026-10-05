# Primordia

A physics and chemistry simulation game about managing one small cell. Eat, grow and survive predation. **You never steer the cell:** its anatomy controls its behavior.

This eighth playable revision uses **Godot 4.7.2**, a fixed-step simulation, deformable membranes, oriented chemical particles and procedural 2D artwork. Its vector artwork is authored in the project; cached particle textures and mipmaps generate automatically at runtime. The default Linux launcher builds a batched C++ GDExtension automatically; the GDScript reference backend remains available.

## Run with Steam Godot on Linux

```sh
./tools/run.sh
```

First launch needs **Git, CMake 3.20+, a C++17 compiler and Python 3**. It fetches a pinned Godot C++ binding revision and builds with two jobs; later launches rebuild only when native source changes. Generated bindings and libraries stay in ignored `build/`. Use `PRIMORDIA_BACKEND=script ./tools/run.sh` for the slower reference backend without native build dependencies. Opening the project directly in Godot uses the native library if it has already been built; otherwise F3 identifies the GDScript fallback.

The launcher finds Godot in standard Steam locations, custom Steam libraries and Flatpak Steam installations. Steam need not be running. Use `./tools/run.sh --editor` to open the editor, then F5 to play. Discovery order is an explicit `GODOT_BIN`, Steam libraries, then `godot4`/`godot` on PATH. `STEAM_DIR` supports a nonstandard Steam client root.

## Controls

- **Tab:** open/close paused organ assembly. Illustrated cards or **1–9 / 0** select organs. Click the membrane to attach; the wheel sizes the selected organ. Existing neighbors move aside to make space and stay anchored afterward. Right-click an installed organ during assembly to recycle it.
- **In the build menu (Tab), drag on your cell:** press the left button for the first microtubule point and release for the second. Endpoints can be on the membrane, on another tube, or inside the cell. Hover a tube and **scroll** to adjust tension; a label shows the current setting. Right-click a tube to remove it. No microtubule build card is needed. During selected-organ placement, left click attaches that organ; close and reopen assembly to clear the selection and draw tubes. Creation, tension changes and removal are available only while the build menu is open.
- **Space:** lock/unlock the camera to your cell's **position**, without changing its rotation or pausing. In free view, drag empty water or middle-drag to pan. Space returns to following the cell.
- **Escape:** settings, including **Quit game**. Settings pause biology. **F11** toggles fullscreen. Fullscreen, **Light bloom** and **85–175% HUD/text scale** persist. Bloom can be disabled in settings.
- **Wheel elsewhere:** microscope zoom. **S:** sensing ranges. **F3:** active backend, FPS and CPU simulation/frame preparation times. **H:** next habitat. **R:** new life.

The world wraps without walls. The microscope center simulates fully, the fringe slows, and offscreen state freezes except for explicit population triggers. The active region follows the actual camera, including free view. Tab/settings remain ways to pause; Space is solely a camera control.

## Anatomy

| Key | Organelle | 1× biomass cost | Role |
| --- | --- | ---: | --- |
| 1 | Flagellum | 8 | Supplies extra thrust and turns the detecting organ toward its target. |
| 2 | Protective cortex | 10 | Absorbs local damage before the membrane. |
| 3 | Hunting spike | 12 | Senses lower **total biomass** cells at long range, pulls toward them and punctures with its tip. |
| 4 | Repair body | 10 | Repairs damage, speeds receptor cleaning and releases acid buffers. |
| 5 | Grazing pore | 8 | Senses nutrients, pumps surrounding fluid, eats particles and secretes reusable digestive enzymes. |
| 6 | Flight receptor | 6 | Faces a sensed threat while requesting travel away. Only this organ triggers flight. |
| 7 | Photosynthesis | 12 | Seeks brighter water, fixes dissolved carbon into organic resources and releases oxygen. |
| 8 | Toxin vesicle | 12 | Fires damaging toxin and receptor-blocking decoy particles toward a chemically sensed cell. |
| 9 | Toxin neutralizer | 10 | Releases particles that bind toxin and make harmless material. |
| 0 | Acid gland | 12 | Releases acidifying particles to change local digestion conditions. |

Proboscis and engulfing pores have been removed. The spike and toxin vesicle are the weapons. Spike target size uses all retained organic material, not just unspent building reserves. A spike or photosynthetic organ can guide and propel a cell; flagella provide additional power. Toxin vesicles use a target found by a spike or flight receptor.

Organ cost, material and most output scale with size squared. Surface area and biomass limit placement. Biomass growth has no arbitrary upper cap, although the finite toroidal habitat remains a geometric limit. Hydrostatic pressure, a soft cortex and the player-authored tension network control shape. Internal unattached junctions move freely; connect them to the membrane/network to transmit useful shape forces.

## Living chemistry

**Cells are the only sources of external particles.** The initial clouds represent products of the existing cells' earlier life, with source-cell identifiers. There is no automatic food/oxygen habitat spawner. Respiration, photosynthesis, secretion, wounds, recycling and death sustain the particle economy. Replacing a dead NPC is an explicit offscreen population event with accounted material input.

Eleven particle types are visible: nutrient, oxygen, waste, cell trace, toxin, dissolved carbon, digestive enzyme, antitoxin, acidifying carrier, buffer and decoy. Forks, hooks, combs and linked lobes distinguish species; their bright tips rotate with the actual particle orientation. Compatible faces must touch and point toward each other to react; there is no additional reaction success roll. Thermal motion tumbles particles, and decay uses a per-second hazard instead of a fixed lifetime. Neighbor searches use spatial grids rather than all-pairs testing.

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

Acidity is a local transported field: increasing acidity shifts water from turquoise toward rose/magenta; buffering restores its normal color. Moderate acidity favors the modeled digestive enzyme. Excess acidity raises maintenance ATP costs, accumulates internal stress, slows metabolism and eventually damages cells. Buffers have finite capacity. The secreting cell is also exposed. Nutrient assembly does **not** gain an automatic acid bonus.

Decoys temporarily reduce chemical sensing range. Every affected receptor automatically spends a little ATP to clean itself, repair bodies accelerate clearance, and passive release still works with no ATP. Purple rings and the **RECEPTORS CLEARING** status show the effect. Light sensing is unaffected.

Pores pulse on consumption. Health/ATP bars show actual resources. Yellow nucleus-to-surface packets illustrate ATP spending; pink packets illustrate biomass-funded repair. External particles are shunted to the membrane edge instead of rendering underneath cells.

Process **40 food units and survive 90 seconds** for the first milestone. The ecosystem continues afterward. The starting grazing anatomy is a starting point for adaptation, not a guaranteed unattended win in the cell-sourced ecosystem.

## Performance revision

Revision seven adds compiled particle transport, orientation chemistry, spatial grids, membrane exclusion, edge/pressure constraints and particle drawing buffers. Fluid viscosity and acidity transport run in native batches, and feeding pumps visit only nearby fluid nodes. Tiny distant cells use less decorative drawing; contact and chemistry still advance at the fixed simulation rate.

A Vulkan compute transport experiment is included, but **is not enabled by default**: measurements found that the current CPU/GPU transfer bridge costs more than native CPU transport. It can be tried with `./tools/run.sh --rendering-method mobile -- --gpu-transport`. It does not move chemistry or the entire game onto the GPU. See the [benchmark results and remaining limits](docs/REVISION_7.md).

## Procedural habitat

Procedural generation and fractals are now a core visual direction. Large radial plant-like colonies grow from a seeded recursive branching grammar, with five-, six- and sevenfold symmetry. Their stout stems obstruct cells and drifting particles; contact slides along branches without consuming material. Fine fronds are decorative, and the scenery does not add food or oxygen sources.

Water gains broad blue, teal, jade and violet regions from seamless multiscale noise. These patterns stay fixed in world space, with existing light, acidity tint and bloom layered over them. Plant art is cached in six mipmapped textures per habitat. See [revision eight](docs/REVISION_8.md) for collision scope and wide-view benchmarks. These additions do not solve the remaining whole-game frame-rate problem documented in revision seven.

## Graphics and proposed chemistry

Revision six uses the requested luminous coral-reef palette: blue/teal water, shared periwinkle cell bodies, layered nuclei and clearer membrane rims. Functional colors live on the organelles and emitted particles; cells are not colored by occupation. Brighter presentation preserves the actual light resource and shaded habitat regions. A restrained bloom follows light-rich water and bright world details, while the HUD stays sharp.

[Complement-inspired mechanics](docs/COMPLEMENT_PROPOSAL.md) are proposed next: surface tags, cooperative pore assembly and protective inhibitors. They are not enabled in this graphics revision.

## Science and scope

[references.md](references.md) records a real phenomenon and source for each biological/physical mechanic, plus the differences between evidence and game rules. Maintain it as mechanics evolve.

This is a coarse 2D game, not molecular dynamics or a full biochemical network. “Microtubules” are generic tension links; real microtubules also bear compression. The membrane remains star-shaped for stable rendering. Fluid is a finite-mass viscous grid, not an incompressible Navier–Stokes solver. Acidity is an acid-equivalent field, not calibrated pH. Growth, repair, metabolism and reactions use explicit coarse material accounting rather than atom-by-atom stoichiometry.

There are no saves, audio, permanent progression or packaged releases yet. Same-seed reproducibility is checked on one engine/platform, not promised across platforms. Diet balance, dense chemistry and long authored networks need playtesting.

## Verification

```sh
./tools/test.sh
python3 tests/test_launchers.py
```

The test launcher uses the same Steam discovery and fails on assertions or Godot script errors. Native tests build the extension first. Run `PRIMORDIA_BACKEND=script ./tools/test.sh` to verify the independent fallback too. Wide-view performance checks and per-item ablations are described in [revision seven](docs/REVISION_7.md) and [revision eight](docs/REVISION_8.md). `tests/profile.gd` is a historical close-view diagnostic, not performance acceptance. F3 during play measures the real frame rate.

For a rendered capture with a display:

```sh
./tools/run.sh -- --capture=/absolute/path/primordia.png
```

Optional capture flags include `--habitat=0`, `--advance=600`, `--assembly`, `--settings`, `--hud-scale=1.75` and `--senses`. Put habitat selection before advance. Capture output belongs outside source control.

The owner's separate Linux **Steam Godot 4.7.2 / RTX 3090 / Threadripper 2990WX** machine remains unavailable to this task. It is an upper-capacity reference, not minimum hardware. See [revision-seven performance results](docs/REVISION_7.md), [revision-six graphics notes](docs/REVISION_6.md), [architecture](docs/ARCHITECTURE.md) and [persistent design](docs/DESIGN.md).

Only authored source and stable Godot `.uid` identifiers are tracked. `.godot/` imports and caches regenerate automatically. Engine downloads, captures, logs and exports are not committed. No redistribution license has been granted for this private project.
