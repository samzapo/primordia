# Revision78 — reduce mobile view work

The main phone report showed about10FPS and32ms view sync. A bounded offline
replay of52current-class cells and2,851external packets, with1.4second snapshots,
identified current visualization as a substantial client cost. Removing it for
diagnosis reduced field sync from21ms to under1ms. The shipped repair keeps it.

Reuse unchanged field textures and avoid sampling both endpoints at completed
blends. When all drawing slots are occupied, refresh only admitted dense seeds;
full source enumeration returns when a slot becomes free. Source weights retain
the same torus and offset rules. Mobile curve integration uses16segments; the
existing display mesh receives linear samples of that same admitted polyline,
so display interpolation cannot introduce a crossing. Geometry refresh is10Hz
on touch, with an anchored deadline and no catch-up burst; movement/fades stay
on the render clock. Camera/style/field changes still trigger immediate work.
The collision-admission margin uses the longer refresh horizon.

Tiny distant nuclei use runtime textures generated from the existing vector art
and lineage colors. Close/selected artwork and all fixed-size deformable anchors
are retained. No generated textures are committed. There are no ecology, packet,
physical-current, balance, protocol or authority-cadence changes. Keep main's pond
and experimental's stopped saved state.

Focused curve/cache invariants and the shared interface check cover correctness;
o new broad fixture campaign or redundant live restart. Offline hardware WebGL
with CPU throttling measures a relative improvement, not physical-phone FPS.
