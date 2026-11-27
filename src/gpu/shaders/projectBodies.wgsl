@group(0) @binding(0) var<uniform> u: SimUniforms;
@group(0) @binding(1) var<storage, read_write> particles: array<Particle>;
@group(0) @binding(2) var<storage, read> bodies: array<BodyGPU>;
@group(0) @binding(3) var<storage, read> bodyPoints: array<vec2f>;

@compute @workgroup_size(128)
fn main(@builtin(global_invocation_id) gid: vec3u) {
  let i = gid.x;
  let maxP = u32(u.params1.x + 0.5);
  if (i >= maxP) { return; }

  var p = particles[i];
  if (p.motion.w < -0.5) { return; }
  let kind = u32(p.motion.w + 0.5);
  if (kind == SP_PHEROMONE) { return; }

  let bodyCount = min(64u, u32(u.params1.y + 0.5));
  var pos = p.pose.xy;

  for (var iter = 0u; iter < 3u; iter++) {
    var moved = false;
    for (var b = 0u; b < bodyCount; b++) {
      let body = bodies[b];
      let off = offsetVec(body.pos.xy, pos);
      let maxR = body.pos.w + 8.0;
      if (dot(off, off) > maxR * maxR) { continue; }

      let dLen = length(off);
      let angle = select(f32(i) * 2.4, atan2(off.y, off.x), dLen > 0.0001);
      let edge = polygonSupport(&bodyPoints, body.ranges.x, body.ranges.y, angle - body.pos.z) + 7.0;
      if (dLen < edge - 0.001) {
        pos = wrapPos(body.pos.xy + vec2f(cos(angle), sin(angle)) * edge);
        moved = true;
      }
    }
    if (!moved) { break; }
  }

  p.pose.x = pos.x;
  p.pose.y = pos.y;
  particles[i] = p;
}
