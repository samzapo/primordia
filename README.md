# Primordia

A physics and chemistry simulation game about managing one small cell. Eat to grow. Adapt to survive predation. **You never steer the cell**: its anatomy controls its behavior.

This first playable prototype uses Godot 4.7.2, a fixed-step particle simulation, a deformable membrane, and procedural 2D artwork. It needs no external assets or plugins.

## Play

Install the standard [Godot 4.7.2 editor](https://godotengine.org/download/archive/4.7.2-stable/), import `project.godot`, and press **F6** with `scenes/pond.tscn` open, or **F5** to run the project.

With Godot on your PATH:

```sh
./tools/run.sh
```

Alternatively, set `GODOT_BIN` to the absolute path of the executable. The project opens a 1440 × 900 window and scales with its aspect ratio preserved. Rendering uses the Compatibility backend; compute shaders are not required.

## How to play

Your starting cell has a feeding pore, chemoreceptor, and flagellum. It seeks green nutrient particles and avoids pink predator traces. Blue oxygen particles diffuse through its membrane. Metabolism turns the absorbed resources into ATP and biomass.

1. Choose an organelle card, or press **1–6**. The pond pauses for assembly.
2. Click a glowing empty membrane socket to attach the organelle. It costs biomass.
3. Watch the new anatomy change your cell's behavior. **Escape** cancels placement.
4. Right-click an occupied socket to recycle it for half its biomass cost.

**Space** pauses observation, **S** shows receptor ranges and preferred direction, and **R** starts a new life. The first milestone is to metabolize 40 nutrient units and survive 90 seconds. The ecosystem continues after the milestone. On death, restart and try a different anatomy.

| Organelle | Cost | Effect |
| --- | ---: | --- |
| Flagellum | 8 | Produces thrust at its attachment point; receptor signals modulate its direction. Placement can help or hinder movement. |
| Protective cortex | 10 | Reduces bite damage. Multiple cortices stack with diminishing absolute benefit. |
| Toxin vesicle | 12 | Uses ATP to launch particles along a detected predator-trace gradient. Contact damages and temporarily repels the hunter. Requires a chemoreceptor signal. |
| Repair body | 10 | Converts ATP and a little biomass into membrane repair. |
| Feeding pore | 8 | Converts contact with external nutrient particles into internal substrate. |
| Chemoreceptor | 6 | Reads local nutrient and predator-trace particles; also relays boundary proximity. |

A useful first experiment is to add a toxin vesicle, then spend acquired biomass on repair and protection. Remove a sensor or move a flagellum to see how much behavior depends on the anatomy.

## Verify

```sh
./tools/test.sh
```

The headless suite checks chemistry budgets, contact-triggered feeding, receptor dependence, propulsion, installation and recycling, defenses, membrane constraints, seeded replay, a complete autonomous survival strategy, and interface input. It exits nonzero on a failed assertion or a Godot script error. No third-party test framework is required.

For a rendered capture, run with a real or virtual display:

```sh
GODOT_BIN=/path/to/godot ./tools/run.sh -- --capture=/absolute/path/primordia.png
```

Optional capture arguments: `--advance=600` advances 600 simulation ticks, `--assembly` selects a protective organelle, and `--senses` shows receptor ranges. Capture outputs belong outside source control.

## Scope of this prototype

The core loop and all six organelle categories work. Chemistry uses coarse game quantities rather than real molecular stoichiometry. The pool has a bounded particle population and one hunter with a simple pursuit controller. The membrane uses XPBD edge and area constraints; collision response currently uses a circular body approximation with local membrane deformation. Swimming is a force-and-drag model, not a full fluid solver.

The initial dense simulation is GDScript so behavior can be iterated quickly. A native C++ extension or GPU simulation is an option if profiling justifies it. There are no saves, audio, progression beyond the first milestone, or packaged releases yet. Same-seed reproducibility is tested within one engine/platform; cross-platform bitwise determinism is not promised.

Core design requirements are in [docs/DESIGN.md](docs/DESIGN.md). Implementation boundaries and next steps are in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Source and generated files

Only authored project files and Godot's stable resource identifiers are tracked. Godot imports and caches live under ignored `.godot/` and are generated automatically on import/run. Build output belongs under ignored `build/`. Engine downloads, screenshots, logs, and exports are not committed. No license has been granted for redistribution of this private project's source.
