# Proposal — the cell becomes the interface

Status: proposed replacement for the current HUD and assembly panels. The camera/scale/preview fixes below are implemented separately; the factories and resource displays described here are not yet implemented.

## Observe, then enter the cell

Normal play shows the full habitat, the cell and the small micrometer scale. Remove the top and bottom panels and the persistent YOUR CELL label. Cell-local cues carry resource state; brief notices appear only for a new tide, a blueprint, critical danger or an outcome. F3 remains an optional performance diagnostic. Escape retains settings, fullscreen, text sizing and Quit.

Tab pauses and enters anatomical editing. Highlight interactive structures inside the player's cell and smoothly move to a useful close view. Allow up to 12× magnification, with cursor-centered zoom and camera panning; preserve the 80% widest view. Restore the previous observation view when leaving. Giant cells can be panned across rather than forcing a view below the owner's minimum. Camera motion never steers the organism.

A first-use hint introduces Tab and the highlighted factory; it disappears after use and remains available in settings. Hover names and short action hints explain each target without a permanent legend.

## Places to click

| Structure | Interaction |
| --- | --- |
| Assembly factory, a folded ribbon with budding vesicles | A local fan of six illustrated choices: flagellum, cortex, spike, repair body, grazing pore and flight receptor. |
| Chemistry factory, a cluster of rounded chambers | Four illustrated choices: photosynthesis, toxin, neutralizer and acid gland. |
| An installed membrane organelle | Local Move, Resize, Recycle and Specialize actions. Damaged attachment scars offer Restore. No anatomy list. |
| Nucleus | Current blueprint draft and unlocked specializations. A small six-part rim indicates tide progress; hovering previews the next pressure and time remaining. |
| Offspring bud | Allocate or reclaim the existing reproductive reserves. Show material and energy readiness separately; after division this becomes a viability cue on the offspring. |
| Empty membrane or microtubule | Drag to add a tension element; hover and scroll to set tension. Editing remains paused/build-only. |

Factories are permanent interface anchors available to every starting cell. They add no organ type, unlock requirement, damage target, upkeep or production timer in this first replacement. The two groupings organize the existing ten organs rather than expanding the economy. Their positions follow the deforming body but settle during editing, so targets do not drift beneath the pointer.

Click a factory, choose a picture, then carry its ghost to the membrane. The wheel sizes the pending organ; neighbors move aside during placement. Hovering an existing organ selects it directly. Right-click cancels a held ghost; recycling is an explicit local action to prevent accidental deletion.

Clickable organs and internal structures take precedence over microtubule endpoints, which take precedence over blank-cell gestures. A selected organ's resize action captures the wheel; otherwise hovering a tube changes tension, and the wheel elsewhere zooms. Pan with middle-drag to keep that gesture distinct.

## Resources are visible anatomy

**ATP:** a translucent internal sac with a fixed capacity outline. Its fill represents current ATP divided by capacity: empty means zero. Existing energy-transfer packets visibly leave it when resources are spent. Low ATP causes a restrained pulse; hovering exposes exact values for diagnosis. This is a visual metaphor, not an ATP-containing organ added to the simulation.

**Biomass:** body volume remains the main indicator. Placement previews the resulting smaller membrane so cost is visible before committing. Existing rules distinguish usable reserves, structural body tissue and material already committed to organs or offspring; a large cell is not automatically able to spend all its mass. A blocked ghost should show the protected body outline and a short “needs usable tissue” cue. Do not silently change conservation, recycling yields or that reserve distinction just to remove a number. Exact tissue cost can appear beside the pending ghost.

**AP:** one spinning coin-like token per available action point, held in a loose internal cluster. Ghost coins stream toward the selected factory during a cost preview; spent tokens disappear on placement and return on Undo. Coins are interface artwork, never chemical particles, collision bodies or food. Keep their shape distinct from nutrient glyphs. Hover reveals the exact balance.

**Health:** membrane holes, torn organ silhouettes and repair traffic carry damage state. Give severe damage a brief cell-local warning, with optional exact health on hover. Preserve role-independent body colors.

Visible factory choices show the current AP/tissue cost only while considering an action. Unaffordable options remain inspectable; highlighting the insufficient sac, coin cluster or tissue outline explains why they cannot be used.

## Editing without Update/Apply

Changes appear immediately in the paused cell. Maintain the existing transactional simulation snapshot beneath the interface, with per-action Undo/Redo and a local Discard plan action on the nucleus. Tab or Enter commits and resumes; the old Apply button disappears. Escape opens settings while preserving the paused plan. Restart/quit explicitly discard that session's uncommitted plan.

Genome choices, specialization and offspring allocations participate in the same undoable plan. Previewing cannot advance chemistry, replenish ATP, earn AP or run the tide clock. Retain the existing prevention of resize/refund exploits.

## Readability and delivery

At observation scale, simplify the sacs and coin cluster but preserve low-resource cues. At close scale, reveal factory choices and annotations. Screen-space minimum click targets, configurable text size and keyboard cycling let small cells remain usable. Anchor overlays to the cell but keep text upright, unclipped and sharp through peripheral blur.

Deliver in three connected steps:

1. ATP sac, AP tokens, camera focus and the two factories, with complete placement/cost/undo behavior.
2. Local organ modification, scars, microtubule hit priorities, nucleus drafts, offspring reserves, forecasts and win/loss feedback.
3. Remove the legacy panes once all existing actions have equivalents; inspect the result at 80%, ordinary editing magnification and 12×, with enlarged text and a giant cell.

Acceptance requires immediate add/remove/resize feedback before resuming, complete keyboard access, preserved resource accounting and frozen biology, correct scale during focus/pan/resize, and no panels left during observation. Measure native and GDScript behavior and rendered frame intervals at the actual 80% play limit, including dense particles and large cells. Historical wider benchmarks stay explicit stress diagnostics.

## Scientific motivation

Cellular protein and membrane production motivates the factory metaphor; it does not imply that real cells manufacture every organelle at one station. The ATP sac and AP coins are interface metaphors. See [microscope scale and proposed cellular controls](../references.md#microscope-scale-and-proposed-cellular-controls) for sources and the limits of these abstractions.
