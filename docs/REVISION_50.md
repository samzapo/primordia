# Revision 50 — longer-lived vacuoles and mobile editing

## Internal carriers

Food vacuoles retain an actual simulation-time age. Their per-carrier digestion rate spreads remaining food over at least ten seconds, with the existing per-cell capacity as a shared upper bound. Large meals can take longer. Nutrient material, fuel, numeric ATP and biomass yields remain conservative; there is no added food or passive energy. Intakes near the oral entry batch into a young carrier. Bounded overflow retains paid quantities.

A compartment is one integrated particle: its food row supplies its motion while food remains, and its waste row takes over afterward. These are finite content stocks, not separate colliding particles. Waste shares the carrier's position, velocity and clock. Carriers move and bounce against the membrane/nucleus; waste-only carriers travel to the cytoproct after residence. No illustrated content has an independent pose or simulation step.

Each carrier draws a translucent membrane and up to seven representative nutrient/waste shapes. Individual contents use half the matching external glyph radius at the same illustrated dose; the illustration does not claim one visible shape per physical amount. Native resident rendering, detached browser instances and the inspection lens share the same artwork. Hover picking uses the existing compact carrier receipt rather than exporting the resident pool. The rendering count follows compartments rather than content-row count. Compatibility-renderer pixel checks verify every pictured food/waste item and the QuadMesh-to-Sprite vertical coordinate mapping. Per-carrier metadata uses custom attributes rather than color modulation.

A double-precision residence clock extends the resident record to 96 bytes. Visible stock/pose authority remains on the GPU without a CPU mirror. Snapshot columns retain age losslessly and decode old wire formats. Old saved rows start with age zero on restore; current checkpoints retain elapsed residence. Existing keys, pond and numerical resource stocks are unchanged.

## Camera

Interoception always follows the selected living cell and removes its interpolated heading from the camera. Two-finger gestures preserve cell-local anchors while changing a relative offset, rotation and scale. The same frame persists as the cell translates/turns. Wheel and middle-drag use that frame too; Follow recenters it instead of unlocking.

The internal maximum is 120x, ten times the normal 12x closest view. Leaving interoception returns to the normal maximum 12x, centered and upright. The observed cell retains full membrane/body fidelity while unrequested exterior chemistry stays coarse. The widest 80% external view and fixed simulation detail footprint remain unchanged.

## Mobile menus and feedback

Every cell action context uses a top tray on touch devices, including construction, installed organs, scars and nucleus/family choices. Available choices are all present, wrapping/scrolling when needed. Placement remains the existing membrane selection. Desktop menus remain local.

The existing Pause/zoom/Follow/perception/music controls use 70% of their previous dimensions. An open tray moves those utility controls below it. A mobile resource strip shows current available biomass, AP and numeric ATP without hovering, including during placement; a small button hides/restores it. Desktop gains no permanent resource panel.

Notifications use a readable 22 CSS-pixel equivalent, scaled for canvas density and the user's text preference. The bundled OFL Comic Neue font supplies portable comic-style text on Android/Web. It is a substitute for proprietary Comic Sans MS, not that exact font.

## Test policy

The owner explicitly restored gameplay and balance tests on October 15. Both policy flags are enabled, including objectives/survival. Historical respiration, fermentation and emergency tissue-burning expectations are updated to the current direct food-vacuole model. Finite fixture meals account for the removal of emergency tissue fuel; no production free-food grant is introduced.

Conservation, ten-second residence, shared carrier motion, checkpoint clocks, native/reference feeding, GPU ownership, shaped rendering, camera anchors, mobile layout/resources, real-time authority, saved restart and rendered-frame performance checks remain active.

## Validation

Native core: 84,999 assertions passed with gameplay/balance/objective suites enabled. GDScript reference core: 3,606 passed. Both include a funded chemical hunt and a 90-second ecosystem run; these are seeded fixtures rather than a broad difficulty calibration.

On the RTX5080 workstation, real 1440×900, widest 80% view with music: exterior59.97FPS/p9518.48ms/.9994simulation-wall; interior59.97FPS/p9518.89ms/.9996. The existing20.5ms p95 and real-time gates remain unchanged. Native resident inventory, rendering/inspection, mobile camera/menu/resources and compatibility-renderer pixels have separate checks. These measurements do not establish physical phone frame rate.
