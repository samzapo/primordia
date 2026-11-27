@group(0) @binding(0) var<uniform> u: SimUniforms;
@group(0) @binding(1) var<storage, read> particles: array<Particle>;
@group(0) @binding(2) var<storage, read> bodies: array<BodyGPU>;
@group(0) @binding(3) var<storage, read> bodyPoints: array<vec2f>;
@group(0) @binding(4) var<storage, read> decoys: array<DecoyGPU>;
@group(0) @binding(5) var<storage, read_write> nominations: array<vec4u>;

@compute @workgroup_size(128)
fn nominateMain(@builtin(global_invocation_id) gid: vec3u) {
  let i = gid.x;
  let maxP = u32(u.params1.x + 0.5);
  if (i >= maxP) { return; }

  nominations[i] = vec4u(0u);
  let p = particles[i];
  if (p.motion.w < -0.5) { return; }

  let kind = u32(p.motion.w + 0.5);
  if (kind != SP_TOXIN && kind != SP_ANTITOXIN && kind != SP_DECOY && kind != SP_TAG && kind != SP_PORE) {
    return;
  }

  let pDir = vec2f(cos(p.pose.z), sin(p.pose.z));

  if (kind == SP_DECOY) {
    let decoyCount = min(1024u, u32(u.params2.y + 0.5));
    let pRad = p.matter.x * 0.5;
    for (var dIdx = 0u; dIdx < decoyCount; dIdx++) {
      let dec = decoys[dIdx];
      let delta = offsetVec(dec.geom.xy, p.pose.xy);
      let dLen = length(delta);
      let reach = dec.ids.x + pRad;
      if (dLen > reach || dLen < 1e-6) { continue; }
      let normal = delta / dLen;
      if (dot(dec.geom.zw, normal) < 0.25 || dot(pDir, -normal) < 0.5) { continue; }
      let bIdx = u32(dec.ids.y + 0.5);
      nominations[i] = vec4u(bIdx, dIdx, kind, 2u);
      return;
    }
    return;
  }

  let bodyCount = min(64u, u32(u.params1.y + 0.5));
  for (var b = 0u; b < bodyCount; b++) {
    let body = bodies[b];
    if (body.flags.w != 0u) { continue; }
    if (kind == SP_ANTITOXIN && body.flags.z == 0u) { continue; }

    let delta = offsetVec(body.pos.xy, p.pose.xy);
    let maxR = body.pos.w + 6.0;
    if (dot(delta, delta) > maxR * maxR) { continue; }
    let dist = length(delta);
    let worldAngle = atan2(delta.y, delta.x);
    let sup = physicalSupport(&bodyPoints, body.ranges.z, body.ranges.w, worldAngle - body.pos.z) + 5.0;
    if (dist > sup) { continue; }

    if (kind != SP_TOXIN && dist > 1e-6) {
      let n = delta / dist;
      if (dot(pDir, -n) < 0.5) { continue; }
    }

    nominations[i] = vec4u(b, 0u, kind, 1u);
    return;
  }
}
