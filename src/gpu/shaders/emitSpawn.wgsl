@group(0) @binding(0) var<uniform> u: SimUniforms;
@group(0) @binding(1) var<storage, read_write> particles: array<Particle>;
@group(0) @binding(2) var<storage, read_write> reports: array<Report>;
@group(0) @binding(3) var<storage, read> emissions: array<EmissionGPU>;
@group(0) @binding(4) var<storage, read> ambientSpawns: array<EmissionGPU>;
@group(0) @binding(5) var<storage, read_write> atomicStats: array<atomic<u32>>;

@compute @workgroup_size(1)
fn main() {
  let maxP = u32(u.params1.x + 0.5);
  let emitCount = min(512u, u32(u.params1.w + 0.5));
  let ambRaw = atomicLoad(&atomicStats[8]);
  let ambCount = min(512u, ambRaw);
  let totalWanted = emitCount + ambCount;
  if (totalWanted == 0u) { return; }

  let tick = u32(u.params0.z + 0.5);
  var cursor = (tick * 257u) % maxP;
  var spawned = 0u;
  var scanned = 0u;

  while (spawned < totalWanted && scanned < maxP) {
    let slot = cursor;
    cursor = (cursor + 1u) % maxP;
    scanned += 1u;

    var p = particles[slot];
    if (p.motion.w >= -0.5) { continue; }

    var em: EmissionGPU;
    if (spawned < emitCount) {
      em = emissions[spawned];
    } else {
      em = ambientSpawns[spawned - emitCount];
    }
    spawned += 1u;

    let nextGen = p.ids.x + 1u;
    p.pose = em.pose;
    p.motion = vec4f(em.motion.xy, 0.0, em.motion.z);
    p.matter = em.matter;
    p.ids = vec4u(nextGen, em.ids.x, em.ids.y, 0u);
    particles[slot] = p;

    var rep: Report;
    rep.geom = em.reportGeom;
    rep.info = em.reportInfo;
    rep.timing = vec4f(em.reportTiming.x, em.reportTiming.y, f32(em.ids.z), f32(slot));
    reports[slot] = rep;
  }
}
