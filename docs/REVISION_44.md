# Revision 44 — persistent multiplayer and a browser client

This revision runs one private, authoritative native GPU world on `samzapo-desktop`. The browser presents real server state with WebGL 2. Transport, external reactions, intracellular cycles, paid emissions, physiology and offscreen ecology keep their existing particle ownership rules. The browser never advances biology or supplies resource values.

## Accepted direction

Gameplay objectives, timed expedition endings and progression design are deferred. The shared service uses the sandbox evolution mode, continues after the selected cell dies, and does not introduce scripted replacement populations. Objective and balance tests are held until the owner asks to restore them. Physical, conservation, networking, recovery and rendering checks remain enabled.

Every active camera contributes its fixed widest-view detail footprint. Native transport, cell activity, fluid activity and GPU exchange use the union. Streaming adds the existing chunk/halo preparation; regions outside every camera use the existing cold/coarse methods. The world continues with no clients. Missing view updates expire after ten seconds, so an inactive tab cannot retain detailed simulation indefinitely. Display zoom does not improve feeding. Camera movement waits for prepared particle ownership before publishing detailed water.

Opening assembly or chemistry editors never pauses the shared world. Edits run on the authority at a tick boundary, validate lineage ownership and epoch/edit versions, use ordinary tissue/AP costs, and retain bounded idempotency receipts. Successful edits and receipts are checkpointed together before acknowledgement. Local single-player retains its existing assembly pause; the October 14 resident-default direction supersedes its original CPU default.

A powered-off host does no simulation. Restart restores the last valid checkpoint and continues from that simulation time, without wall-time catch-up or free resource accrual.

## State and network contracts

At most eight players connect simultaneously. Owner-issued personal access keys claim distinct existing living lineages; creation does not grant a new cell or resource stock. Each key belongs to one persistent identity. A remembered browser bearer resumes it; entering the key on another browser rotates that bearer and disconnects the previous session. Only hashes of keys and bearer tokens are retained by the authority. Key-account binding and token rotation are checkpointed before welcome. Account ledgers, selection, command sequence, random streams, cell chemistry, skeletons, membranes, cold packets, GPU-owned packets and emission/transfer escrow are saved as a data-only object graph with shared references preserved. Clients send bounded JSON actions; the server never deserializes client objects.

Two SHA-256 checked checkpoint generations use fsync, atomic rename and directory fsync. A corrupt newer generation falls back to the older valid one. Existing invalid storage fails closed rather than creating a replacement world. Persistent formats are versioned; future incompatible code needs an explicit migration. The private state directory must be retained separately from releases.

The GPU publishes a deduplicated view union at up to ten updates per second with one asynchronous compact pose gather in flight. Browser shaders interpolate real particle position/angle and exclude visual interpolation from membranes. The existing procedural particle atlas, cell art, water and chemistry editors are reused. Ordinary publication does not export chemical metadata or checkpoint the full world. Checkpoints deliberately reconcile complete ownership. Client outbound queues and frame sizes are bounded; slow clients can skip visual snapshots while the world keeps advancing.

## Deployment

`tools/deploy.py` creates a task-owned revision branch/worktree from committed authored source in a private release and builds native libraries and browser assets on the target. Checksum-pinned Godot 4.7.2 and its web templates live in a private runtime. Generated libraries, imported projects, browser packages and caches stay out of Git and are never copied from a CI checkout into releases. Wired routes and aggregate memory/build pressure are checked before and during long provisioning/build steps.

The independent user service is `primordia.service`; it supervises a private Xvfb display, the real Vulkan GPU authority and the HTTPS/WebSocket gateway. Port **8766** serves a plain HTTP certificate setup page and the HTTPS browser, `/ws`, `/health`, `/metrics` and `/api/network`. The world socket is **8767**, bound only to loopback. GSOC remains on 8765. User-manager lingering permits startup and continued operation without an interactive login. A service lock prevents two authorities from writing the same world.

The deployment workflow targets the authorized working branch. It performs native compilation, checkpoint/network checks, real GPU integration under its unattended display, web export, candidate health checks and a separate post-job verification. Candidate failure restores the prior code/service while preserving saves. The host telemetry workflow includes read-only world metrics.

## Practical bounds

This remains one bounded 4096 by 2560 toroidal habitat with at most eight camera regions and 100,000 GPU slots. Capacity, frame sizes, cell renderer bounds and preparation queues are explicit. Larger/unbounded worlds, load distribution, host-downtime catch-up, browser-side compute and cross-platform bitwise equivalence are future work.

The service uses the same private LAN host requested for GSOC, with TLS on Primordia’s independent port. Godot 4.7.2 requires a secure browser context; each device installs the retained private LAN CA once. Certificate name constraints exclude public hostnames; server certificates renew automatically for physical-interface private addresses. Invitations and saved identities travel through HTTPS/WSS. Public Internet access still needs a separate access policy and trusted public hostname. See `docs/deployment.md` for phone setup.

Measure actual simulation/wall ratio and view load. Passing short integration checks establishes ownership and service operation, not sustained 50k/60 FPS or phone performance. Checkpointing can pause a frame; the latest telemetry reports its cost.

## October 14 — touch zoom and local view pause

The initial phone controls provide two-finger pinch/spread zoom, touch-sized −/+ buttons and Pause/Resume. The owner explicitly chose freezing only their own view while the shared world continues. Networking remains active during a view pause, keeps one latest snapshot and returns directly to it on Resume. Frozen views cannot submit edits. Zoom changes magnification within existing bounds and never changes organ size, chemistry or simulation density. Native local Pause stops actual local time/transport. Gameplay objectives, balance acceptance and broader touch editing remain deferred.

## October 14 — anchored two-finger camera manipulation

The owner chose a combined two-finger touch/drag/pinch/twist gesture: the contacted world points remain fixed and the camera resolves their misalignment. Capture two unwrapped world anchors at touch-down and solve one similarity transform for translation, rotation and scale. Keep midpoint anchoring at zoom bounds, stop when a finger lifts, and preserve GUI routing and single-finger cell taps. A touch-sized Following cell / Free view toggle unlocks or restores upright cell-centered framing; reconnects also reset follow state. Coarse server cells use the same interpolated pose for camera, visibility and artwork, and selected-cell data remains drawable after a distant camera snapshot. Rotated drawing, world fields, picking and view/detail bounds agree; no cell movement, chemistry, clocks or resource commands are generated by camera gestures. Pause remains local to the client's view.
