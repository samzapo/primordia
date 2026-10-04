# Primordia

A physics and chemistry simulation game about managing one small cell. Eat to grow. Adapt to survive predation. **You never steer the cell**: its anatomy controls its behavior.

This third playable revision uses Godot 4.7.2, a fixed-step particle simulation, a deformable membrane, and procedural 2D artwork. It needs no external assets or plugins.

## Play

With **Godot Engine installed through Steam on Linux**, run:

```sh
./tools/run.sh
```

The launcher finds Godot in standard Steam locations, custom libraries listed by Steam, and Flatpak Steam installations. It runs the installed editor binary directly, so Steam does not need to be running. No separate Godot download or PATH setup is required.

To open the project in your Steam-installed editor instead:

```sh
./tools/run.sh --editor
```

Press **F5** in Godot to play. The prototype was validated with Godot 4.7.2; keep the Steam installation on a compatible Godot 4 release.

Discovery order is an explicit `GODOT_BIN`, then Steam libraries, then `godot4` or `godot` on PATH. If the Steam client itself is in a nonstandard location, set `STEAM_DIR` to its root directory (the directory containing `steamapps`). An explicit `GODOT_BIN` remains available for other installations. Both the game and test launchers use the same discovery logic.

The project opens a 1440 × 900 window. The microscope fills the window or screen, with controls overlaid on the world. **F11** toggles fullscreen; **Settings** also provides fullscreen and **85–175% HUD/text size**. Both preferences persist between launches. Rendering uses the Compatibility backend; compute shaders are not required.

## How to play

Your cell moves on its own through a wrapping liquid world. The microscope follows it: there are no walls. Nearby life runs at full speed, activity slows into the vignette, and distant life stays dormant.

1. Press **Tab** or click **Build** to pause and open assembly. **1–6** selects a category.
2. Click a free stretch of membrane to attach it. Biomass and available surface determine capacity; there are no fixed sockets. Organs stay anchored to that membrane location as the cell grows, turns, and deforms.
3. Choose **grazing pore**, **engulfing pore**, or **proboscis** in the feeding menu; **F** cycles them.
4. Choose a **nutrient**, **hunting**, **host**, or **flight** receptor in the receptor menu; **C** cycles them. **Only the flight receptor causes fleeing.**
5. Right-click an organelle to recycle half its remaining material. The rest becomes debris that can recycle chemically. Press **Tab** again to resume.

**Space** pauses observation, **S** shows sensing, **Escape** closes the open panel, **mouse wheel** changes microscope zoom, and **R** starts a new life. **H** starts a new run in the next habitat: balanced, nutrient-poor hunting grounds, or rich waters with armored hunters. **F3** shows FPS, simulation time, frame preparation time, and active populations.

Process **40 food units and survive 90 seconds** to reach the first milestone. Food from grazing, carcasses, engulfment, and parasitism all contributes through the same metabolism. The ecosystem continues afterward.

| Organelle | Biomass | Effect |
| --- | ---: | --- |
| Flagellum | 8 | Applies thrust and torque at its location, with an opposite impulse into the liquid. Internal sensor signals modulate direction. |
| Protective cortex | 10 | Absorbs damage at its own location. Exposed membrane elsewhere remains vulnerable. |
| Toxin vesicle | 12 | Spends ATP and biomass to fire damaging chemical particles toward a sensed organism. |
| Repair body | 10 | Accelerates membrane closure and organelle repair. |
| Feeding organelle | 8 | Graze on nutrient particles, engulf sufficiently smaller cells, or use a proboscis to drain larger living hosts. |
| Receptor | 6 | Nutrient: approach food. Hunting: approach smaller prey. Host: approach larger cells. Flight: flee other cells. Internal particles relay the selected response. |

Engulfing pores and proboscises follow nearby compatible cell traces on their own. Hunting and host receptors extend that detection range. An engulfer needs at least **15% more radius** than its prey; its mouth grips and damages the prey, then consumes biomass on death. A proboscis needs a host with **over 5% more radius**; it pierces the armor at its contact point before draining. Contact links, moving food particles, and status text distinguish seeking, blocked armor, draining, and engulfing. A mouth still needs propulsion to swim toward its target.

Flight receptors deliberately prioritize avoidance while another cell is detected, even if a mouth wants to feed. Nutrient receptors and feeding organs never add automatic flight. Recycle the flight receptor to cancel avoidance.

Growth has no arbitrary biomass or radius cap. Digestion and food, oxygen, and ATP storage scale with the growing cell. Growth increases effective volume, membrane capacity, mass, inertia, and exposure. Punctures leak biomass into the medium and close quickly; organelles repair themselves from reserves. A repair body improves both processes. Shrinkage can shed organs when the membrane becomes overcrowded.

Hunters obey the same rules. They can die, release their retained biomass, and be replaced by a different individual outside the view. Waste consumes local oxygen as it recycles into food, with conversion losses. Currents transport chemicals and move cells; cells push back on the fluid.

## Verify

```sh
./tools/test.sh
```

The test launcher automatically uses the same Steam-installed Godot. The headless suite checks material and fluid momentum budgets, membrane packing and tension, punctures and repair, wrapped contacts, dormant state, all feeding interactions, irreversible hunter death, internal signals, seeded replay, crowded encounters, a 90-second autonomous run, and interface input. It exits nonzero on a failed assertion or a Godot script error. No third-party test framework is required. Launcher discovery can also be checked separately with `python3 tests/test_launchers.py`; Python is only needed for those development fixtures, not to launch the game.

For a rendered capture, run with a real or virtual display:

```sh
./tools/run.sh -- --capture=/absolute/path/primordia.png
```

Optional capture arguments: `--habitat=0`, `--habitat=1`, or `--habitat=2` selects conditions; place it before `--advance=600` to advance that world by 600 simulation ticks. `--assembly` opens feeding assembly, `--settings` opens display preferences, `--hud-scale=1.75` previews larger text, and `--senses` shows receptor ranges. Capture outputs belong outside source control.

## Scope and performance

This is a coarse 2D biological simulation, not molecular chemistry or a full 3D cell. The fluid is a finite-mass viscous grid with two-way impulse exchange, local currents, and explicitly driven tides; it does not solve incompressible Navier–Stokes equations. The pressure/tension membrane deforms, while swept body contacts use radial membrane extents rather than a full soft-body manifold.

The default world stores 19 cells and roughly 3,000 chemical particles; the microscope bounds active work. CPU simulation remains in GDScript and rendering uses procedural vector-style shapes plus particle MultiMeshes. No compute-capable GPU is required. Active spatial queries, cached membrane drawings, batched particle uploads, and motion interpolation reduce simulation and rendering work while preserving the fluid model. See [the architecture](docs/ARCHITECTURE.md) for numerical boundaries and [revision-three validation](docs/REVISION_3.md#validation) for measured evidence.

For a repeatable CPU-only profile, run `./tools/run.sh --headless --script res://tests/profile.gd`. Use **F3 during actual play** to measure frame rate; the headless profile does not measure rendering.

The owner's **Steam Godot 4.7.2 / RTX 3090 / Threadripper 2990WX (32 cores)** Linux machine is the high-end reference, not a minimum requirement. It is unavailable to this task, so no frame-rate claim has been made for that machine. Profile before choosing native or GPU acceleration.

There are no saves, audio, permanent progression, or packaged releases yet. Same-seed reproducibility is checked within one engine/platform, not promised across platforms. Long-term balance across habitats and diets needs playtesting.

Core design requirements are in [docs/DESIGN.md](docs/DESIGN.md). The [current revision](docs/REVISION_3.md) records the latest feedback and validation; [revision two](docs/REVISION_2.md) retains earlier design history. Further work should follow playtest findings rather than add organelle categories or a behavior programming system.

## Source and generated files

Only authored project files and Godot's stable resource identifiers are tracked. Godot imports and caches live under ignored `.godot/` and are generated automatically on import/run. Build output belongs under ignored `build/`. Engine downloads, screenshots, logs, and exports are not committed. No license has been granted for redistribution of this private project's source.
