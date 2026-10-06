# Primordia development

## Project isolation

Explicit owner instruction, October 5, 2026: Primordia is isolated from all other chats and projects, including Deployment and Weft. Do not list, read, search, import, reuse or send context across that boundary in either direction. Keep Primordia decisions and memory inside its project directories; never write them into global memory or unrelated projects. Earlier external-project references in historical chat text do not authorize access.

Never access the Eka-Robotics GitHub organization through any tool, browser, API, CLI or local checkout, including read-only operations and discovery. The only project repository is `https://github.com/samzapo/primordia.git`, privately owned by `samzapo`. Verify destinations before network operations. Public documentation and explicit public dependencies remain allowed except anything owned by Eka-Robotics. Do not enumerate unrelated chats, projects, organizations or repositories.

The project-local `.codex/config.toml` requests disabling generated-memory input/output and account app connectors by default for future sessions that load trusted project configuration. It is not a filesystem sandbox or an organization credential restriction; do not claim complete technical isolation without verifying those separately. App-managed conversation history remains app-managed.

Read `docs/DESIGN.md` before changing gameplay, `docs/REVISION_12.md` for starting networks and music, `docs/REVISION_11.md` for current cell controls and inspection, `docs/REVISION_10.md` for the art direction, and `docs/REVISION_9.md` for run rules (earlier revision documents are historical). Do not treat proposed details or open questions as settled requirements. Preserve no direct cell control, the current documented anatomy, particle-driven interactions, and the bright vector-style cellular art direction.

The user runs Godot through Steam on a separate Linux machine. Keep Steam discovery as the default in both launchers; support custom libraries and Flatpak. The prototype was validated with Godot 4.7.2. Run `tools/test.sh`; `GODOT_BIN` is an optional explicit override. Tests must fail on script errors even when the Godot process exits zero. For launcher changes, also run `python3 tests/test_launchers.py` (isolated fixtures; never alter a real Steam install). Keep the simulation independent of scene-tree and rendering code.

Do not commit `.godot/`, exported builds, downloaded engine binaries, captures, or logs. Keep authored sources and stable Godot `.uid` identifiers. Generated imports must be recreated automatically.

Record scientific abstractions honestly. Do not describe the current reaction rules as molecular chemistry, circular collision proxies as full soft-body contact, or local reproducibility as cross-platform determinism.

For every new biological or physical mechanic, maintain at least one source for its real-world motivating phenomenon in `references.md`. Prefer primary research or authoritative technical documentation; distinguish evidence, modeled rule and game simplification. Explicit user direction, October 4, 2026.

The widest playable view is now 80% (owner correction, October 5, 2026), including after growth/build fitting. Performance acceptance must include that play limit, dense particle clusters and large cells. Keep historical half, quarter and 0.15 zoom fixtures as explicitly marked diagnostic stress workloads, not playable camera settings. Close-view timings alone are insufficient. Keep independent benchmark switches for native kernels, fluid work, spatial queries, scheduling and native rendering. Report CPU ticks separately from rendered frame intervals and GPU transport-only throughput. Do not enable an experimental backend by default solely because its isolated kernel is faster. Run native and GDScript suites; the native suite includes differential chemistry/transport/field checks. Preserve explicit CPU fallback and Steam discovery. Generated libraries, dependency source caches and binding output stay in ignored build/; keep the pinned build recipe.

Procedural generation and finite fractals are core visual requirements. Preserve seeded radial plant obstacles, spatially varied water, cached artwork and readable function colors. Validate geometry/contact independently of art, and benchmark obstacle work and rendering separately at wide zoom.

The current player interface has fixed-size organ construction, no Undo/redo/discard-plan controls, and no persistent HUD/build panes. Preserve cell-local factories/resources, direct anatomy editing, nucleus/offspring decisions and the nonphysical particle magnifier. Microtubules remain edit-only; wheel zoom must never resize an organ.

Engaging original progressive techno is a core design requirement. Preserve anatomy/proximity/biomass sonification, the independent audio sample clock, bounded mixing and separate volume/visual-response controls. Audio and beat shaders must never mutate ecology or gate gameplay on the beat. Keep synthesized banks/previews generated from source rather than checked in. Benchmark audio on/off at the widest playable view.
