# Revision 11 — the cell becomes the interface

The approved cell-interface plan is implemented with the owner's subsequent corrections: **no Undo control and no organ resizing**. The old top/bottom panels, build/modify lists and Apply button are removed. Fixed-size factory construction, direct anatomy controls and local particle inspection now share the full-screen habitat.

## Anatomy as the interface

Tab pauses and smoothly zooms into the cell. The view reaches 12× and never widens below 80%; it no longer automatically hides growth by pulling the play camera farther back. Wheel zoom stays anchored under the cursor. Middle-drag pans within editing or free view; Space reattaches position-follow. Finishing an edit restores the observation camera.

Folded assembly ribbons open six illustrated choices; chemistry chambers open four. These are permanent interface anchors, not purchasable organs, production timers or simulated mass. New organs always use their standard size. Size variation in existing NPC anatomy and inherited/restored organs remains part of the simulation; players cannot resize it.

Select an installed organ to move, recycle or use a matching learned blueprint. Scars restore damaged-away anatomy. Factories, organs and scars have priority over tension-link gestures. Empty membrane/interior/link points retain direct microtubule dragging and hover-wheel tension. These actions remain edit-only.

The nucleus holds blueprint choices, optional growth/stability challenges and tide forecasts. The offspring bud allocates or reclaims existing reproductive tissue and ATP, then shows viability after division. Prices, reserve accounting, chemistry, maintenance, resistance and the lineage win condition remain governed by revision nine.

Edits appear immediately while paused. Tab, or Enter with no active choice/placement, commits and resumes. Escape preserves edits while opening settings. Right-click cancels a held ghost/move or closes local choices. There is no user-accessible Undo, redo or discard-plan action. Recycling consumes the existing half-material penalty and does not refund AP. Restarting or quitting still ends the unsaved run.

## Visible resources

- The ATP sac keeps a visible capacity boundary and fills according to current energy/capacity. Yellow spending packets leave that sac; repair packets still leave the nucleus.
- One spinning token represents each AP. Spent tokens briefly travel toward a factory. These are bounded decorative drawings, not chemical particles or collectible objects.
- Body size represents biomass. A membrane outline previews construction shrinkage; a blocked placement identifies missing AP, usable tissue or surface area. Structural and reproductive tissue remain protected from ordinary construction.
- Wounds, damaged-organ marks and repair traffic show health. Hovering the membrane reveals health, acid stress and local light; the ATP sac exposes stored food, oxygen and an approximate active-upkeep estimate.
- The offspring bud has separate tissue-fill and energy-rim indicators. The nucleus rim shows tide progression and a bright dot marks an available blueprint.

Ordinary play has no resource bars or numeric biomass counter. Settings and optional diagnostics remain available. Small hover descriptions and brief notifications convey danger, transitions and outcomes.

## Particle inspection

Hovering a particle produces a softly bounded, 3.5× optical lens around the cursor and a small local name/role tooltip. The shared postprocessing shader magnifies nearby water and artwork; a clipped full-resolution version of the selected glyph keeps branches and binding direction sharp even when the underlying packet occupies only a few pixels. The lens fades out on mouse leave and is suppressed by settings, dragging, held construction and open local choices.

Picking uses one neighboring-bucket query from the existing chemistry grid. It follows interpolated positions/orientation, invisible map wrapping and rendered membrane exclusion. Covered particles are not selected through the cell. Particle state, amount, velocity, lifetime, reaction orientation and simulation activity are unchanged by inspection.

The micrometer marker applies to the ordinary camera image outside this temporary lens. Glyphs remain coarse packets rather than literal molecule-scale illustrations.

## Accessibility and performance boundaries

Local choices use scalable screen-space targets and remain upright. Text/interaction sizing and settings persist. Bracket keys cycle cell targets; Enter activates choices; arrow keys navigate choices or membrane placement. Microtubules retain mouse-based construction and tension gestures.

Only the player's internal controls redraw each frame. Existing cached cell art and batched particle rendering remain. The inspection lens reuses the existing screen copy and one cached glyph; it does not create a second world viewport. The remaining wide-view simulation bottleneck is not solved by this interface revision.

Scientific motivation and distinctions between real biology and UI metaphors remain in [references.md](../references.md#microscope-scale-and-proposed-cellular-controls).

## Validation

Godot 4.7.2: the native suite passed **1,827 assertions** and the independent GDScript suite passed **773**, with no failures. The 98 interface checks cover paid construction/recycling, camera limits, paused geometry, controls, keyboard access, all eleven chemical names/orientations, wrapped particle picking and offscreen resource-art suppression. Import and whitespace checks passed.

Rendered checks passed **17/17 on both Vulkan Mobile (RTX 5080) and OpenGL Compatibility (llvmpipe)**. These include actual mouse dispatch through factory choices, membrane placement and Recycle before resuming; lens activation/dismissal; empty and very small resource fills; and the largest text setting. Selected captures were visually inspected. Compatibility was a software-rendered check, not an NVIDIA OpenGL performance result.

### Frame-cost comparison at the play limit

Same workstation, 1440×900 Xvfb, Vulkan Mobile, native simulation, 80% camera, same seeded normal/dense/growth fixtures as the preceding checkpoint. Each sample uses 12 warm-up frames and 36 measured live frames; the dense fixture starts with four times the packets, while growth starts with 256 times the player's unspent biomass. Ordinary UI is hidden by this existing benchmark, while player resource artwork remains in the world.

| Fixture | Bloom | Before median (ms) | After median (ms) | After p95 (ms) | After CPU tick (ms) |
| --- | --- | ---: | ---: | ---: | ---: |
| Normal | Off | 23.798 | 26.111 | 27.636 | 3.41 |
| Normal | On | 24.613 | 25.976 | 27.254 | 3.44 |
| Dense | Off | 46.273 | 47.417 | 50.233 | 7.53 |
| Dense | On | 52.397 | 52.661 | 62.074 | 7.70 |
| Growth | Off | 34.542 | 35.068 | 38.650 | 3.47 |
| Growth | On | 34.547 | 34.435 | 37.892 | 3.42 |

The normal case costs roughly 1.4–2.3 ms more in these short samples; dense/growth medians are close. This revision does **not** establish a performance improvement or meet the 16.7 ms/60 FPS goal. CPU tick time alone is not frame time.

A separate frozen, UI-visible lens test at the same camera and bloom setting queried 119 nearby candidates out of 3,731 packets. Two alternating off/on pairs (60 measured frames each) gave median frame intervals of **18.145/18.299 ms** and **20.740/24.929 ms**. This drift prevents a reliable fixed overhead estimate; no claim of negligible GPU cost is made. Both the world postprocess and selected sharp glyph are included.

These are workstation checks (Ryzen 9 9950X / RTX 5080), not measurements on the owner's Steam/RTX 3090/Threadripper machine. Longer owner playtesting, dense-scene profiling and interface usability feedback remain useful.
