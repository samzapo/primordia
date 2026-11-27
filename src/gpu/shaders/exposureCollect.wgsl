@group(0) @binding(0) var<uniform> u: SimUniforms;
@group(0) @binding(1) var<storage, read_write> particles: array<Particle>;
@group(0) @binding(2) var<storage, read> bodies: array<BodyGPU>;
@group(0) @binding(3) var<storage, read> binOffsets: array<u32>;
@group(0) @binding(4) var<storage, read> sortedSlots: array<u32>;
@group(0) @binding(5) var<storage, read> nominations: array<vec4u>;
@group(0) @binding(6) var<storage, read_write> receipts: Receipts;

@compute @workgroup_size(1)
fn collectMain(@builtin(workgroup_id) wgid: vec3u) {
  let b = wgid.x;
  let bodyCount = min(64u, u32(u.params1.y + 0.5));
  if (b >= bodyCount) { return; }

  let body = bodies[b];
  let reach = body.pos.w + 20.0;
  let wp = wrapPos(body.pos.xy);
  let loX = i32(floor((wp.x - reach) / BIN_SIZE));
  let hiX = i32(floor((wp.x + reach) / BIN_SIZE));
  let loY = i32(floor((wp.y - reach) / BIN_SIZE));
  let hiY = i32(floor((wp.y + reach) / BIN_SIZE));

  var hitCount = 0u;
  var deferred = 0u;

  for (var by = loY; by <= hiY; by++) {
    for (var bx = loX; bx <= hiX; bx++) {
      let bin = binIndexFromCoord(bx, by);
      let start = binOffsets[bin];
      let end = binOffsets[bin + 1u];
      for (var idx = start; idx < end; idx++) {
        let slot = sortedSlots[idx];
        let nom = nominations[slot];
        if (nom.w == 0u || nom.x != b) { continue; }

        var p = particles[slot];
        if (p.motion.w < -0.5) { continue; }

        if (nom.w == 2u) {
          let dIdx = nom.y;
          if (dIdx < 1024u) {
            receipts.decoyCounts[dIdx] += 1u;
          }
          p.motion.w = -1.0;
          p.matter.y = 0.0;
          particles[slot] = p;
        } else if (nom.w == 1u) {
          if (hitCount < 64u) {
            let delta = offsetVec(body.pos.xy, p.pose.xy);
            let ang = atan2(delta.y, delta.x);
            receipts.exposureHits[b * 64u + hitCount] = vec4f(
              p.matter.y,
              ang,
              bitcast<f32>(nom.z),
              bitcast<f32>(p.ids.y),
            );
            hitCount += 1u;
            p.motion.w = -1.0;
            p.matter.y = 0.0;
            particles[slot] = p;
          } else {
            deferred += 1u;
          }
        }
      }
    }
  }

  receipts.exposureCounts[b] = vec4u(hitCount, deferred, 0u, 0u);
}
