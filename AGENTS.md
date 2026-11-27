# Primordia Development Guidelines

## Project isolation

Explicit owner instruction, October 5, 2026: Primordia is isolated from all other chats and projects, including Deployment and Weft. Do not list, read, search, import, reuse or send context across that boundary in either direction. Keep Primordia decisions and memory inside its project directories; never write them into global memory or unrelated projects. Earlier external-project references in historical chat text do not authorize access.

Never access the Eka-Robotics GitHub organization through any tool, browser, API, CLI or local checkout, including read-only operations and discovery. The only project repository is `https://github.com/samzapo/primordia.git`, privately owned by `samzapo`. Verify destinations before network operations. Public documentation and explicit public dependencies remain allowed except anything owned by Eka-Robotics. Do not enumerate unrelated chats, projects, organizations or repositories.

The project-local `.codex/config.toml` requests disabling generated-memory input/output and account app connectors by default for future sessions that load trusted project configuration. It is not a filesystem sandbox or an organization credential restriction; do not claim complete technical isolation without verifying those separately. App-managed conversation history remains app-managed.

## Core Architecture & Design Invariants

- **Static client-side WebGPU pond**: Runs standalone in the browser with Vite + TypeScript + WebGPU (`https://samzapo.github.io/primordia/`), single-player only, with no backend server. Page reload starts a fresh pond; only UI, visual, audio, and lineage style preferences persist in `localStorage`.
- **Unified GPU particle simulation**: All external particles across the `4096 × 2560` toroidal world (`MAX_PARTICLES = 32768`) are owned, transported, collided, reacted, queried, and rendered in WebGPU compute/render buffers (`src/gpu/`, `src/render/`). Keep `src/sim/` independent of DOM and WebGPU APIs so headless Node tests remain fast and portable.
- **No direct cell control**: Anatomy, receptor queries, pheromone reports, and evolutionary policies govern cell behavior.
- **Pheromones are emission-time snapshots**: Never resolve emitted source IDs into live target position, mass, hostility, or survival during perception or particle inspection. Point pheromones diffuse, follow water current, expire over elapsed simulation time, and ignore physical particle/solid collisions.
- **Biological & UI constraints**:
  - Preserve fixed-size organ placement, Fibonacci non-receptor pricing, cell-local editing menus, overlap picking for `>= 44 CSS px` targets, and edit-only microtubules (no undo/redo/resizing/AP cluster).
  - Preserve `MIN_ZOOM = 0.8` (80% widest playable pond view), `12×` exteroception cap, and `120×` cell-attached interoception zoom.
  - Keep all cell wakes drawn below cell bodies using relative fluid velocity, seeded fractal plant obstacles (`fern`, `radial`, `fan`, `spiral`) porous to chemicals, and pH bicubic watercolor without scene warp.
  - Keep all synthesized audio waves generated procedurally from source (`src/audio/synthBank.ts`), never mutating simulation state, and never replaying stale history across mute, restart, or editing. Particle beat pulsing stays removed.
- **Scientific honesty**: Record abstractions honestly in `references.md` and `src/data/player_guide.json`; do not describe reaction rules as full molecular kinetics, circular collision proxies as soft-body physics, or local runs as cross-platform determinism. For every new biological or physical mechanic, maintain at least one primary or authoritative technical source in `references.md`.
- **Build & Verification Hygiene**: Never commit `node_modules/`, `dist/`, `build/`, captures, or logs. Clean up any background preview or test processes before finishing. Run `npm test`, `npm run lint`, and `npm run build` before pushing verified changes to `main`.
