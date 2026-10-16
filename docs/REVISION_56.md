# Revision 56 — clear sun/shade and rippling caustics

Revision 55 changed the actual light field but left an independent fractal
highlight pass in the background shader. Its repeated spots remained visible,
and absolute brightness thresholds hid almost all contrast during dim weather.
The owner's phone screenshot and confirmation invalidate the earlier visual
acceptance. Preserve the existing seeded field and photosynthesis/phototaxis.

Remove that independent highlight pass. Render broad deep-indigo shade and
turquoise sunlight from the same normalized R8 light map. Divide display-only
spatial exposure by the existing habitat/weather multiplier, then dim the
overall water with that multiplier. This keeps bright/shady places readable
without increasing the light available to cells. Existing bloom still reads
actual light. Low-amplitude seamless hue variation adds no extra light sources.

In sunlit water, draw an animated irregular network of caustic-like curves.
A bounded nine-neighbour cellular distance calculation with periodic moving
seeds and smooth domain warping gives curved focusing edges instead of sine
stripes or point glows. The animation is world-anchored and uses the existing
display world clock, including exact view pause. Water-ripple preferences
disable it. Acid tint composes afterward, and buffering restores neutral water.
Nothing samples/warps the scene, advances chemistry or consumes ecology RNG.

Validate actual normal shader pixels under Vulkan and Compatibility, including
strong spatial contrast, caustic temporal changes confined to lit water, dim
weather, wrapping, and exact stillness when ripples are disabled. Inspect both
whole-pond and portrait artwork, then the real exported touch client. This is
render correctness and visual review, not a resumed rendering-speed benchmark.
Keep the persistent pond, all saved cell identities/anatomy, accounts, five-key
registry and private feedback through the normal deployment/restart checks.
Append player notes and keep Pause → Mechanics current.
