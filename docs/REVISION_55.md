# Revision 55 — diffuse, irregular pond illumination

The old light field was the sum of three horizontal and three vertical waves.
Its repeated Cartesian peaks looked like a grid when zoomed out. Replace it with
a pond-seeded, smoothly domain-warped periodic field containing broad oblique
modes. At the retained 0.2um/unit display calibration, variations span roughly
100um to the whole 819.2x512um pond. A 1000um region would span this whole habitat;
this update does not resize or reset the world.

Cache a derived 128x80 float field (32 world units / 6.4um per sample), bounded
to four seeds. No simulation RNG, saved field migration, new particles or per-tick
noise generation. Normalize the unscaled mean to 0.5, retain broad bright and dark
regions, and preserve existing habitat/weather multipliers and bounds.
Photosynthesis and light-seeking query this same bilinearly sampled field.

Display it as a normalized R8 texture, which retains ordinary linear filtering
without depending on phone support for filtering float textures. Water and bloom
share the texture; acidity remains unchanged. The source texture upload has the same byte size
as the previous 64x40 RF texture and is rebuilt only at existing refresh points.

Validate continuity across wrapping edges, seeded variation, mean/range, local
direction versus the sampled light field, spatial scale, unchanged RNG and saved
seed restoration. Render actual shader pixels under Vulkan and Compatibility,
checking visible contrast and wrap continuity; retain whole-pond diagnostic
captures for visual review. No rendering-speed benchmark is added.
