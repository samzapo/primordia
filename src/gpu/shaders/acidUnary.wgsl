@group(0) @binding(0) var<uniform> u: SimUniforms;
@group(0) @binding(1) var<storage, read_write> particles: array<Particle>;
@group(0) @binding(2) var<storage, read> binOffsets: array<u32>;
@group(0) @binding(3) var<storage, read> sortedSlots: array<u32>;
@group(0) @binding(4) var<storage, read_write> acidField: array<f32>;

@compute @workgroup_size(128)
fn main(@builtin(global_invocation_id) gid: vec3u) {
  let k = gid.x;
  if (k >= FIELD_COUNT) { return; }

  let cx = k % GRID_COLS;
  let cy = k / GRID_COLS;
  let dt = u.params0.x;
  var acidVal = acidField[k];

  // Iterate 4x4 spatial bins inside this 64x64 field node
  for (var dy = 0u; dy < 4u; dy++) {
    for (var dx = 0u; dx < 4u; dx++) {
      let b = (cy * 4u + dy) * BIN_COLS + (cx * 4u + dx);
      let start = binOffsets[b];
      let end = binOffsets[b + 1u];
      for (var idx = start; idx < end; idx++) {
        let slot = sortedSlots[idx];
        var p = particles[slot];
        if (p.motion.w < -0.5) { continue; }
        let kind = u32(p.motion.w + 0.5);
        if (kind != SP_ACID && kind != SP_BUFFER) { continue; }

        let sgn = select(-1.0, 1.0, kind == SP_ACID);
        let cap = p.matter.z;
        let nextAcid = clamp(acidVal + sgn * min(cap, dt * 0.2), 0.0, 1.0);
        let used = abs(nextAcid - acidVal);
        acidVal = nextAcid;
        let remCap = max(0.0, cap - used);
        p.matter.z = remCap;
        if (remCap <= 1e-6) {
          p.motion.w = f32(SP_WASTE);
          p.matter.x = 2.0 * particleRadius(u, SP_WASTE, p.matter.y);
        }
        particles[slot] = p;
      }
    }
  }

  acidField[k] = acidVal;
}
