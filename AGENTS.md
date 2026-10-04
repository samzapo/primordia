# Primordia development

Read `docs/DESIGN.md` before changing gameplay. Preserve no direct cell control, all six organelle categories, particle-driven interactions, and the bright vector-style cellular art direction.

Use Godot 4.7.2 (standard build). Run `tools/test.sh` with `GODOT_BIN` if Godot is not on PATH. Tests must fail on script errors even when the Godot process exits zero. Keep the simulation independent of scene-tree and rendering code.

Do not commit `.godot/`, exported builds, downloaded engine binaries, captures, or logs. Keep authored sources and stable Godot `.uid` identifiers. Generated imports must be recreated automatically.

Record scientific abstractions honestly. Do not describe the current reaction rules as molecular chemistry, circular collision proxies as full soft-body contact, or local reproducibility as cross-platform determinism.
