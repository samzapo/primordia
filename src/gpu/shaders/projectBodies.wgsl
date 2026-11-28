@group(0) @binding(0) var<uniform> u: SimUniforms;
@group(0) @binding(1) var<storage, read_write> particles: array<Particle>;
@group(0) @binding(2) var<storage, read> bodies: array<BodyGPU>;
@group(0) @binding(3) var<storage, read> bodyPoints: array<vec2f>;
@group(0) @binding(4) var<storage, read_write> bodyImpacts: array<atomic<i32>>;

fn surfaceWorldNormal(start: u32, count: u32, localAngle: f32, bodyAngle: f32, radial: vec2f) -> vec2f {
  if (count < 4u) { return radial; }
  let a = posmodf(localAngle, TAU);
  let idxF = (a / TAU) * f32(count);
  let i = u32(floor(idxF)) % count;
  let iPrev = (i + count - 1u) % count;
  let iNext = (i + 1u) % count;
  let tang = bodyPoints[start + iNext] - bodyPoints[start + iPrev];
  let tLen = length(tang);
  if (tLen < 1e-4) { return radial; }
  let localN = vec2f(tang.y, -tang.x) / tLen;
  let ca = cos(bodyAngle);
  let sa = sin(bodyAngle);
  let worldN = vec2f(localN.x * ca - localN.y * sa, localN.x * sa + localN.y * ca);
  let blended = worldN * 0.65 + radial * 0.35;
  let bLen = length(blended);
  return select(radial, blended / bLen, bLen > 1e-4);
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

  let bodyCount = min(64u, u32(u.params1.y + 0.5));
  var pos = p.pose.xy;
  let pRad = max(1.2, p.matter.x * 0.5 + 0.5);
  let matW = speciesMaterial(u, kind);
  let pMass = clamp(p.matter.y * (0.16 + 0.84 * matW), 0.02, 12.0);
  let massFrac = clamp(pMass / (pMass + 0.65), 0.04, 1.0);
  var bounced = false;

  for (var iter = 0u; iter < 3u; iter++) {
    var moved = false;
    for (var b = 0u; b < bodyCount; b++) {
      let body = bodies[b];
      let off = offsetVec(body.pos.xy, pos);
      let maxR = body.pos.w + pRad + 2.0;
      if (dot(off, off) > maxR * maxR) { continue; }

      let dLen = length(off);
      let angle = select(f32(i) * 2.4, atan2(off.y, off.x), dLen > 0.0001);
      let localAngle = angle - body.pos.z;
      let edge = polygonSupport(&bodyPoints, body.ranges.x, body.ranges.y, localAngle) + pRad;
      if (dLen < edge - 0.001) {
        let radial = vec2f(cos(angle), sin(angle));
        let pen = edge - dLen;
        if (!bounced) {
          bounced = true;
          let n = surfaceWorldNormal(body.ranges.x, body.ranges.y, localAngle, body.pos.z, radial);
          let vRel = p.motion.xy - body.vel.xy;
          let vn = dot(vRel, n);
          let isWall = body.vel.w > 0.5;
          let restitution = mix(0.18, 1.22, massFrac) * select(1.0, 0.85, isWall);
          let penBoost = min(72.0, pen * (3.0 + 16.0 * massFrac));
          let normalDv = max(-(1.0 + restitution) * min(vn, 0.0), penBoost);
          p.motion.x += n.x * normalDv;
          p.motion.y += n.y * normalDv;
          let mLen = length(p.motion.xy);
          if (mLen > 280.0) {
            p.motion.x = (p.motion.x / mLen) * 280.0;
            p.motion.y = (p.motion.y / mLen) * 280.0;
          }
          let tanVec = vec2f(-n.y, n.x);
          p.pose.w = clamp(p.pose.w + dot(vRel, tanVec) * 0.025 * massFrac, -6.0, 6.0);

          let sec = u32(floor((posmodf(localAngle, TAU) / TAU) * 14.0)) % 14u;
          let dent = clamp((0.28 + min(abs(vn), 120.0) * 0.022 + pen * 0.24) * massFrac, 0.0, 3.0);
          atomicAdd(&bodyImpacts[b * 16u + sec], i32(dent * 256.0));
          let dvCell = -n * (normalDv * clamp(pMass / max(16.0, body.vel.z * 4.5), 0.0, 0.032));
          atomicAdd(&bodyImpacts[b * 16u + 14u], i32(clamp(dvCell.x, -8.0, 8.0) * 256.0));
          atomicAdd(&bodyImpacts[b * 16u + 15u], i32(clamp(dvCell.y, -8.0, 8.0) * 256.0));
        }
        pos = wrapPos(body.pos.xy + radial * (edge + 0.15 * massFrac));
        moved = true;
      }
    }
    if (!moved) { break; }
  }

  p.pose.x = pos.x;
  p.pose.y = pos.y;
  particles[i] = p;
}
