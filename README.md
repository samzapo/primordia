# Primordia

A client-side WebGPU physics, chemistry, and cellular ecology simulation game. Eat, adapt, divide, and survive predation across a living pond. **You never steer the cell directly:** its anatomy and local chemical signals drive its behavior.

Live static hosting: **https://samzapo.github.io/primordia/** (runs completely in your browser with no backend server; reloading the page resets the pond while UI, visual, audio, and lineage style preferences persist locally).

## Unified WebGPU Architecture

All external chemical molecules and pheromones across the entire **4096 × 2560** toroidal pond (up to **32,768** particles across 26 species) simulate directly in WebGPU compute shaders (`src/gpu/`) and render directly from GPU storage buffers (`src/render/`), eliminating any foreground/background CPU–GPU particle split:

- **Compute pipeline (`src/gpu/particleEngine.ts`)**: `transport.wgsl` (advection, oral suction, $\sqrt{\mathrm{d}t}$ diffusion, pheromone expiry), two-pass uniform grid prefix scan (`gridCount`, `prefixSum`, `gridScatter`), unary acidity exchange & 6-tick semi-Lagrangian acidity PDE (`acidUnary`, `acidStep`), stochastic decay, mutual-vote oriented reactions + soft collisions (`overlapDegree`, `voteImpulse`, `reactionCommit`), ambient gas equilibrium (`ambientGas`), ordered cellular intake (`feedConsume`, `emitSpawn`), receptor perception & particle inspection (`perception`), hazard/decoy exposure & membrane projection (`exposureNominate`, `exposureCollect`, `projectBodies`), and parallel workgroup census readback (`censusReduce`).
- **Render pipeline (`src/render/renderer.ts`)**:
  - Sunlit pond depth (`128 × 80` light field), animated Voronoi caustics, and 16-tap cubic B-spline pH watercolor reconstruction (`water.wgsl`).
  - Non-overlapping current streamlines and plant wakes (`flowCurves.ts`).
  - Seeded finite fractal plants (`fern`, `radial`, `fan`, `spiral`) across 10 non-overlapping colonies (`habitat.ts`, `atlasGenerator.ts`).
  - Directly instanced WebGPU particles (`particles.wgsl`) with lineage-tinted translucent pheromones.
  - All cell wakes drawn strictly beneath cell bodies, followed by 4-ring dome-shaded deformable 112-vertex membranes (`membrane.ts`), edit-only microtubules, exterior organelles, cytoplasmic vacuoles & gas bubbles, and compact interior landmarks (`factoryLayout.ts`).
  - Microscope post-processing pass (`microscope.wgsl`) with a 3.5× circular magnifying inspector lens, toggleable sunlit bloom, peripheral mipmap blur, and exterior greyscale dim during interoception or relative merge selection.
- **Procedural progressive audio (`src/audio/`)**: 17 deterministic waveforms generated from source at 22,050 Hz, 128 BPM 64-bar progressive synthesizer across 7 stereo/filtered/delay Web Audio lanes with biomass transposition, inherited 6-note lineage melodies, environmental pH/light filtering, and pitch-colored sound ripples.

## Controls

- **Left-click / Tap focused cell or interior landmark**: Open top circular Action Tray and Bottom Description Bar (`P`/`Space` also pauses/resumes; edits work live or while paused).
- **Select organelle icon -> Click membrane**: Place fixed-size organelle cleanly around the perimeter (`Esc` or top-left **Cancel Placement** cancels).
- **Hover / Tap-hold (`2.5s`) particles or internal vacuoles**: Open the 3.5× circular microscope magnifier & metadata readout (pheromones display immutable emission-time snapshot metadata only).
- **Left-drag / One-finger drag**: Pan freely across the toroidal pond; **Follow (`F`)** recenters the camera on your active cell.
- **Wheel / Two-finger pinch, pan & twist / `+` `-`**: Zoom from the **80% widest playable pond view** up to `12×` outdoors or `120×` in **Interoception (`I` / `Tab`)**.
- **Double-tap living relative or open `Family`**: Switch active lineage member or merge an eligible relative into your cell.
- **`Colors`**: Customize lineage name and primary palette via HSV hue ring + Shirley-Chiu saturation/value disc.
- **`F3`**: Toggle live FPS, tick timing, GPU particle census, reaction counts, and pond UTC/weather telemetry.
- **`M`**: Mute/unmute audio (`F1` / `?` opens the built-in Gameplay & Science Guide; `Esc` opens Menu / New Pond Expedition).

## Development

Prerequisites: Node 22+ and a WebGPU-capable browser (Chromium/Chrome 113+, Edge, or Firefox with WebGPU).

```sh
npm install
npm run dev      # Start Vite dev server
npm test         # Run headless Node simulation, biology & audio unit tests
npm run lint     # ESLint typechecked lint check
npm run build    # TypeScript check + production bundle in dist/
npm run preview  # Preview production dist/ bundle locally
```

Push to `main` triggers [`.github/workflows/deploy.yml`](.github/workflows/deploy.yml), publishing `dist/` automatically to GitHub Pages.

## Scientific Honesty

Primordia models simplified biological and physicochemical analogies rather than full molecular kinetics, true soft-body continuum mechanics, or cross-hardware floating-point determinism. Real-world motivating sources for each mechanic are tracked in [`references.md`](references.md) and inside the in-app Science Guide.
