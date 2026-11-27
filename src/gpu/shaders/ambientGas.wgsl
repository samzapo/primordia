@group(0) @binding(0) var<uniform> u: SimUniforms;
@group(0) @binding(1) var<storage, read_write> particles: array<Particle>;
@group(0) @binding(2) var<storage, read> binOffsets: array<u32>;
@group(0) @binding(3) var<storage, read> sortedSlots: array<u32>;
@group(0) @binding(4) var<storage, read> flow: array<vec4f>;
@group(0) @binding(5) var<storage, read_write> ambientSpawns: array<EmissionGPU>;
@group(0) @binding(6) var<storage, read_write> atomicStats: array<atomic<u32>>;

fn serviceSpecies(
  k: u32,
  cx: u32,
  cy: u32,
  kind: u32,
  goalMass: f32,
  factor: f32,
  seed: u32,
  tick: u32,
) {
  var totalMass: f32 = 0.0;
  var lowestSlot: u32 = 0xffffffffu;

  for (var dy = 0u; dy < 4u; dy++) {
    for (var dx = 0u; dx < 4u; dx++) {
      let b = (cy * 4u + dy) * BIN_COLS + (cx * 4u + dx);
      let start = binOffsets[b];
      let end = binOffsets[b + 1u];
      for (var idx = start; idx < end; idx++) {
        let slot = sortedSlots[idx];
        let p = particles[slot];
        if (p.motion.w < -0.5) { continue; }
        if (u32(p.motion.w + 0.5) != kind) { continue; }
        totalMass += p.matter.y;
        lowestSlot = min(lowestSlot, slot);
      }
    }
  }

  if (totalMass > goalMass) {
    let ratio = 1.0 - factor * (1.0 - goalMass / totalMass);
    for (var dy = 0u; dy < 4u; dy++) {
      for (var dx = 0u; dx < 4u; dx++) {
        let b = (cy * 4u + dy) * BIN_COLS + (cx * 4u + dx);
        let start = binOffsets[b];
        let end = binOffsets[b + 1u];
        for (var idx = start; idx < end; idx++) {
          let slot = sortedSlots[idx];
          var p = particles[slot];
          if (p.motion.w < -0.5 || u32(p.motion.w + 0.5) != kind) { continue; }
          p.matter.y *= ratio;
          p.matter.z *= ratio;
          p.matter.x = 2.0 * particleRadius(u, kind, p.matter.y);
          particles[slot] = p;
        }
      }
    }
  } else if (totalMass < goalMass) {
    let add = (goalMass - totalMass) * factor;
    if (add <= 1e-6) { return; }
    if (lowestSlot != 0xffffffffu) {
      var p = particles[lowestSlot];
      p.matter.y += add;
      p.matter.z += add;
      p.matter.x = 2.0 * particleRadius(u, kind, p.matter.y);
      particles[lowestSlot] = p;
    } else if (binOffsets[BIN_COUNT] < 20000u) {
      let idx = atomicAdd(&atomicStats[8], 1u);
      if (idx < 512u) {
        let s = (k * 73856093u) ^ (tick * 19349663u) ^ seed ^ (kind * 9176u);
        let px = (f32(cx) + hashFloat(s + 1u)) * GRID_SIZE;
        let py = (f32(cy) + hashFloat(s + 2u)) * GRID_SIZE;
        let ang = hashFloat(s + 3u) * TAU;
        var e: EmissionGPU;
        e.pose = vec4f(px, py, ang, 0.0);
        e.motion = vec4f(0.0, 0.0, f32(kind), 0.0);
        e.matter = vec4f(2.0 * particleRadius(u, kind, add), add, add, 0.0);
        e.ids = vec4u(0xffffffffu, 0u, 0u, 0u);
        e.reportGeom = vec4f(0.0);
        e.reportInfo = vec4u(0u);
        e.reportTiming = vec4f(0.0);
        ambientSpawns[idx] = e;
      }
    }
  }
}

@compute @workgroup_size(128)
fn main(@builtin(global_invocation_id) gid: vec3u) {
  let k = gid.x;
  if (k >= FIELD_COUNT) { return; }

  let group = i32(u.params2.z + 0.5);
  if (group < 0) { return; }

  let seed = u32(u.params0.w);
  let nodeGroup = (k * 17u + (seed % 20u)) % 20u;
  if (nodeGroup != u32(group)) { return; }

  let cx = k % GRID_COLS;
  let cy = k / GRID_COLS;
  let elapsed = u.params2.w;
  if (elapsed <= 0.0) { return; }

  let speedFactor = 1.0 + length(flow[k].xy) / 20.0;
  let fCarbon = 1.0 - exp(-elapsed * speedFactor / 10.0);
  let fOxygen = 1.0 - exp(-elapsed * speedFactor / 60.0);
  let tick = u32(u.params0.z + 0.5);

  serviceSpecies(k, cx, cy, SP_CARBON, 32.0, fCarbon, seed, tick);
  serviceSpecies(k, cx, cy, SP_OXYGEN, 2.0, fOxygen, seed, tick);
}
