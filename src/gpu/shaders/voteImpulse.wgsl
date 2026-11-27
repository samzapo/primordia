@group(0) @binding(0) var<uniform> u: SimUniforms;
@group(0) @binding(1) var<storage, read> particles: array<Particle>;
@group(0) @binding(2) var<storage, read> binOffsets: array<u32>;
@group(0) @binding(3) var<storage, read> sortedSlots: array<u32>;
@group(0) @binding(4) var<storage, read> degrees: array<u32>;
@group(0) @binding(5) var<storage, read> acidField: array<f32>;
@group(0) @binding(6) var<storage, read_write> impulses: array<vec4f>;
@group(0) @binding(7) var<storage, read_write> votes: array<u32>;

fn canReact(aKind: u32, aAmt: f32, bKind: u32, bAmt: f32, acid: f32) -> bool {
  if ((aKind == SP_ENZYME && bKind == SP_WASTE) || (aKind == SP_WASTE && bKind == SP_ENZYME)) {
    return acid < 0.9;
  }
  if ((aKind == SP_ANTITOXIN && (bKind == SP_TOXIN || bKind == SP_TAG || bKind == SP_PORE)) ||
      (bKind == SP_ANTITOXIN && (aKind == SP_TOXIN || aKind == SP_TAG || aKind == SP_PORE))) {
    return true;
  }
  if ((aKind == SP_ACID && bKind == SP_BUFFER) || (aKind == SP_BUFFER && bKind == SP_ACID)) {
    return true;
  }
  if (aKind == SP_WASTE && bKind == SP_OXYGEN) {
    return bAmt >= aAmt * 0.15 && acid < 0.8;
  }
  if (bKind == SP_WASTE && aKind == SP_OXYGEN) {
    return aAmt >= bAmt * 0.15 && acid < 0.8;
  }
  if ((aKind == SP_NUTRIENT && bKind == SP_TOXIN) || (aKind == SP_TOXIN && bKind == SP_NUTRIENT)) {
    return true;
  }
  if (aKind == bKind &&
      (aKind == SP_NUTRIENT || aKind == SP_WASTE || aKind == SP_CARBON || aKind == SP_OXYGEN)) {
    return aAmt + bAmt <= mergeLimit(aKind);
  }
  return false;
}

@compute @workgroup_size(128)
fn main(@builtin(global_invocation_id) gid: vec3u) {
  let i = gid.x;
  let maxP = u32(u.params1.x + 0.5);
  if (i >= maxP) { return; }

  impulses[i] = vec4f(0.0, 0.0, 0.0, 0.0);
  votes[i] = 0xffffffffu;

  let p = particles[i];
  if (p.motion.w < -0.5) { return; }
  let kindI = u32(p.motion.w + 0.5);
  if (kindI == SP_PHEROMONE) { return; }

  let ri = p.matter.x * 0.5;
  let reach = ri + 8.501;
  let wp = wrapPos(p.pose.xy);
  let loX = i32(floor((wp.x - reach) / BIN_SIZE));
  let hiX = i32(floor((wp.x + reach) / BIN_SIZE));
  let loY = i32(floor((wp.y - reach) / BIN_SIZE));
  let hiY = i32(floor((wp.y + reach) / BIN_SIZE));

  let degI = degrees[i];
  let dirI = vec2f(cos(p.pose.z), sin(p.pose.z));
  let tick = u32(u.params0.z + 0.5);
  let acid = sampleAcid(&acidField, p.pose.xy);

  var dv = vec2f(0.0, 0.0);
  var bestJ = 0xffffffffu;
  var bestScore = 0u;
  var bestTie = 0u;

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
        let kindJ = u32(q.motion.w + 0.5);
        if (kindJ == SP_PHEROMONE) { continue; }

        let d = offsetVec(p.pose.xy, q.pose.xy);
        let dSq = dot(d, d);
        let contact = ri + q.matter.x * 0.5;
        if (dSq > contact * contact) { continue; }

        let dist = sqrt(dSq);
        let n = select(vec2f(1.0, 0.0), d / dist, dist > 1e-6);

        // Soft repulsion impulse
        if (dist < contact) {
          let denom = f32(max(1u, max(degI, degrees[j])));
          dv -= n * ((contact - dist) * 2.0 / denom);
        }

        // Oriented reaction candidate scoring
        if (!canReact(kindI, p.matter.y, kindJ, q.matter.y, acid)) { continue; }
        let dirJ = vec2f(cos(q.pose.z), sin(q.pose.z));
        let alignI = dot(dirI, n);
        let alignJ = dot(dirJ, -n);
        let thresh = bindingThreshold(kindI, kindJ, acid);
        if (alignI < thresh || alignJ < thresh) { continue; }

        let score = u32(clamp(min(alignI, alignJ), 0.0, 1.0) * 1024.0) + 1u;
        let lo = min(i, j);
        let hi = max(i, j);
        let tie = hash32(lo ^ hash32(hi) ^ hash32(tick));
        if (score > bestScore || (score == bestScore && (tie > bestTie || (tie == bestTie && j < bestJ)))) {
          bestScore = score;
          bestTie = tie;
          bestJ = j;
        }
      }
    }
  }

  impulses[i] = vec4f(dv, 0.0, 0.0);
  votes[i] = bestJ;
}
