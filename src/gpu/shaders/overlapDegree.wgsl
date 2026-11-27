@group(0) @binding(0) var<uniform> u: SimUniforms;
@group(0) @binding(1) var<storage, read> particles: array<Particle>;
@group(0) @binding(2) var<storage, read> binOffsets: array<u32>;
@group(0) @binding(3) var<storage, read> sortedSlots: array<u32>;
@group(0) @binding(4) var<storage, read_write> degrees: array<u32>;

@compute @workgroup_size(128)
fn main(@builtin(global_invocation_id) gid: vec3u) {
  let i = gid.x;
  let maxP = u32(u.params1.x + 0.5);
  if (i >= maxP) { return; }

  degrees[i] = 0u;
  let p = particles[i];
  if (p.motion.w < -0.5) { return; }
  let kind = u32(p.motion.w + 0.5);
  if (kind == SP_PHEROMONE) { return; }

  let ri = p.matter.x * 0.5;
  let reach = ri + 8.501;
  let wp = wrapPos(p.pose.xy);
  let loX = i32(floor((wp.x - reach) / BIN_SIZE));
  let hiX = i32(floor((wp.x + reach) / BIN_SIZE));
  let loY = i32(floor((wp.y - reach) / BIN_SIZE));
  let hiY = i32(floor((wp.y + reach) / BIN_SIZE));

  var deg = 0u;
  for (var by = loY; by <= hiY; by++) {
    for (var bx = loX; bx <= hiX; bx++) {
      let b = binIndexFromCoord(bx, by);
      let start = binOffsets[b];
      let end = binOffsets[b + 1u];
      for (var idx = start; idx < end; idx++) {
        let j = sortedSlots[idx];
        if (j == i) { continue; }
        let q = particles[j];
        if (q.motion.w < -0.5) { continue; }
        let qk = u32(q.motion.w + 0.5);
        if (qk == SP_PHEROMONE) { continue; }
        let d = offsetVec(p.pose.xy, q.pose.xy);
        let contact = ri + q.matter.x * 0.5;
        if (dot(d, d) < contact * contact) {
          deg += 1u;
        }
      }
    }
  }
  degrees[i] = deg;
}
