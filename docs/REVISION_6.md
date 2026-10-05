# Revision 6 — brighter cells and directional particle shapes

The owner requested visibly oriented, forked and branched particles using complement illustrations as a visual reference, then a brighter graphics revision. The owner explicitly selected luminous colors like a bright coral reef. This pass changes presentation; existing chemistry, particle contact radii, resource rules and build-only microtubule controls remain.

## Implemented art direction

- Blue/teal water has a brighter minimum value and a readable indigo microscope fringe. The background still samples the actual light field: a bright presentation does not increase photosynthesis or eliminate shade. Acidity directly shifts water toward rose/magenta with increasing field strength; buffering reverses that tint.
- Cell bodies share a periwinkle/cyan palette regardless of occupation, with substantial membrane rims and layered nuclei. Decorative cytoplasm stays within that palette. Only the player retains an identity label; no hunter/grazer labels prescribe a profession. Functional color lives on actual anatomy and its products: digestion gold, photosynthesis green/cyan, toxins coral, neutralizers blue, acid glands magenta and repair/buffers mint.
- Organelles have stronger colors and clearer dark/light separation. Feeding openings remain visibly hollow; flagella have an edge that separates them from the water.
- Particle species use original rounded vector glyphs: nutrient forks, oxygen linked lobes, waste zigzags, cell-trace stems, toxin tridents, branched carbon packets, enzyme combs, antitoxin pincers, acid branches, buffer hooks and decoy keys.
- Bright terminal marks show the forward axis. Glyphs rotate with the same interpolated angle used by the authoritative particles; forks and hooks no longer look stationary as they tumble. Cell traces show heading but do not participate in pair chemistry.
- A bounded screen-space bloom follows light-rich regions and highlights bright world details. The HUD renders afterward and remains sharp. Settings include a persistent Light bloom toggle.
- Panels use readable blue tones. Health/ATP, font scaling, fullscreen and illustrated organ cards remain.

The shapes are symbolic, not diagrams of the named chemicals. Decorative branches do not introduce extra binding sites or rigid-body collisions. A contact still uses the existing radius and facing-angle gate.

## Rendering and validation

Authored SVG path strings live in `scripts/particle_art.gd`. Godot rasterizes eleven glyph textures and generates mipmaps once, caching them for reuse. The existing eleven species MultiMeshes share a simple unshaded material. No per-particle nodes, per-frame SVG rasterization or generated texture files are added to Git.

Godot 4.7.2 validation on the workstation:

- **445 assertions pass**, including visible forward-axis interpolation, a quarter-turn changing the rendered direction, distinct species textures, bloom setting toggling/persistence, and all prior chemistry, physics and build-only editing checks.
- Gameplay, a populated close-up, matched sunlit bloom-on/off views with an acidic patch, assembly, 175% settings and an eleven-species rotation key rendered without script or shader errors. Gameplay, close-up, settings and the key were visually inspected.
- The 600-frame, 1440 × 900 live software-rendered profile measured **32.529 ms median / 42.574 ms p95** frame intervals, with end-of-run averages of **2.801 ms simulation / 0.931 ms frame preparation**. Bloom was enabled. This software-rendered run showed slow frames; it is not evidence of smooth 60 FPS. Disable Light bloom in settings when its rendering cost is too high.
- Before bloom was added, a controlled frozen-world comparison with **406 active particles** alternated the old round shader and new glyphs in one process: round medians **16.183 / 15.976 ms**, glyph medians **16.113 / 16.045 ms**. Corresponding p95 values were **17.886 / 16.802 ms** and **17.011 / 16.477 ms**. This isolates glyph rendering and shows no meaningful added cost in that fixture; it does not explain all live-simulation slow frames.
- Rendering uses Mesa llvmpipe with two threads for validation. The owner's RTX 3090 remains unavailable. The driver reports unsupported VSync switching. Prior timings are not a controlled comparison.

Authored screenshots and concise reports remain outside source control. Textures regenerate from source automatically.

## Suggested next graphics changes

1. **Reaction docking feedback:** show a brief contact highlight or two pieces joining when a reaction actually occurs. Keep it tied to authoritative reaction events; use a bounded effect pool.
2. **More anatomy-derived silhouettes:** emphasize the actual locations of cortex, flagella and weapons, and use the existing membrane deformation for variety. Avoid decorative spines that imply nonexistent weapons.
3. **A more compact observation HUD:** preserve the health/ATP bars and scalable fonts, but move secondary instructions into contextual hints so the microscope occupies more of the view.

Keep the requested bloom restrained; avoid additional screen-wide distortion or persistent effects on every particle. The color and shape language should remain readable in crowded chemistry.

## Complement-inspired gameplay

The [complement proposal](COMPLEMENT_PROPOSAL.md) recommends surface tags, orientation-dependent pore assembly and protective inhibitors, with optional local amplification later. It is a proposal, not enabled gameplay. [references.md](../references.md) records the supporting biological phenomena and the differences from the suggested game rules.
