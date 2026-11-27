@group(0) @binding(0) var<uniform> u: SimUniforms;
@group(0) @binding(1) var<storage, read_write> particles: array<Particle>;
@group(0) @binding(2) var<storage, read_write> atomicStats: array<atomic<u32>>;

fn atomicAddFloat(idx: u32, delta: f32) {
  if (delta == 0.0) { return; }
  var oldVal = atomicLoad(&atomicStats[idx]);
  loop {
    let newBits = bitcast<u32>(bitcast<f32>(oldVal) + delta);
    let res = atomicCompareExchangeWeak(&atomicStats[idx], oldVal, newBits);
    if (res.exchanged) { break; }
    oldVal = res.old_value;
  }
}

@compute @workgroup_size(128)
fn main(@builtin(global_invocation_id) gid: vec3u) {
  let i = gid.x;
  let maxP = u32(u.params1.x + 0.5);
  if (i >= maxP) { return; }

  var p = particles[i];
  if (p.motion.w < -0.5) { return; }
  let kind = u32(p.motion.w + 0.5);
  if (kind == SP_PHEROMONE) { return; }

  let dt = u.params0.x;
  let rate = speciesDecay(u, kind);
  let prob = 1.0 - exp(-rate * dt);
  let tick = u32(u.params0.z + 0.5);
  let r = hashFloat((i * 19349663u) ^ (tick * 83492791u) ^ (u32(u.params0.w) * 2654435761u));

  if (r < prob) {
    let loss = p.matter.y * speciesMaterial(u, kind);
    p.motion.w = -1.0;
    p.matter.y = 0.0;
    particles[i] = p;
    atomicAdd(&atomicStats[4], 1u);
    atomicAddFloat(5u, loss);
  }
}
