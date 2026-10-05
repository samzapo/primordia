# Primordia development

Read `docs/DESIGN.md` before changing gameplay, and `docs/REVISION_6.md` for the current revision (earlier revision documents are historical). Do not treat proposed details or open questions as settled requirements. Preserve no direct cell control, the current documented anatomy, particle-driven interactions, and the bright vector-style cellular art direction.

The user runs Godot through Steam on a separate Linux machine. Keep Steam discovery as the default in both launchers; support custom libraries and Flatpak. The prototype was validated with Godot 4.7.2. Run `tools/test.sh`; `GODOT_BIN` is an optional explicit override. Tests must fail on script errors even when the Godot process exits zero. For launcher changes, also run `python3 tests/test_launchers.py` (isolated fixtures; never alter a real Steam install). Keep the simulation independent of scene-tree and rendering code.

Do not commit `.godot/`, exported builds, downloaded engine binaries, captures, or logs. Keep authored sources and stable Godot `.uid` identifiers. Generated imports must be recreated automatically.

Record scientific abstractions honestly. Do not describe the current reaction rules as molecular chemistry, circular collision proxies as full soft-body contact, or local reproducibility as cross-platform determinism.

For every new biological or physical mechanic, maintain at least one source for its real-world motivating phenomenon in `references.md`. Prefer primary research or authoritative technical documentation; distinguish evidence, modeled rule and game simplification. Explicit user direction, October 4, 2026.
