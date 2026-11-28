@group(0) @binding(0) var<uniform> u: SimUniforms;
@group(0) @binding(1) var<storage, read_write> particles: array<Particle>;
@group(0) @binding(2) var<storage, read> acidField: array<f32>;
@group(0) @binding(3) var<storage, read> impulses: array<vec4f>;
@group(0) @binding(4) var<storage, read> votes: array<u32>;
@group(0) @binding(5) var<storage, read_write> receipts: Receipts;
@group(0) @binding(6) var<storage, read_write> atomicStats: array<atomic<u32>>;

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

fn recordSpark(at: vec2f, cue: f32) {
  let slot = atomicAdd(&atomicStats[9], 1u);
  if (slot < 128u) {
    receipts.reactionSparks[slot] = vec4f(at.x, at.y, cue, 0.0);
  }
}

@compute @workgroup_size(128)
fn applyImpulses(@builtin(global_invocation_id) gid: vec3u) {
  let i = gid.x;
  let maxP = u32(u.params1.x + 0.5);
  if (i >= maxP) { return; }
  var p = particles[i];
  if (p.motion.w < -0.5) { return; }
  let imp = impulses[i].xy;
  p.motion.x += imp.x;
  p.motion.y += imp.y;
  particles[i] = p;
}

@compute @workgroup_size(128)
fn commitPairs(@builtin(global_invocation_id) gid: vec3u) {
  let i = gid.x;
  let maxP = u32(u.params1.x + 0.5);
  if (i >= maxP) { return; }

  let j = votes[i];
  if (j == 0xffffffffu || i >= j || j >= maxP) { return; }
  if (votes[j] != i) { return; }

  var a = particles[i];
  var b = particles[j];
  if (a.motion.w < -0.5 || b.motion.w < -0.5) { return; }

  let ka = u32(a.motion.w + 0.5);
  let kb = u32(b.motion.w + 0.5);
  let acid = sampleAcid(&acidField, a.pose.xy);
  let mid = wrapPos(a.pose.xy + offsetVec(a.pose.xy, b.pose.xy) * 0.5);
  var reacted = false;
  var sparkCue: f32 = 1.0;

  if (ka == SP_ENZYME && kb == SP_WASTE && acid < 0.9) {
    b.motion.w = f32(SP_NUTRIENT);
    b.matter.z = 0.0;
    b.matter.x = 2.0 * particleRadius(u, SP_NUTRIENT, b.matter.y);
    atomicAddFloat(6u, b.matter.y);
    reacted = true;
  } else if (kb == SP_ENZYME && ka == SP_WASTE && acid < 0.9) {
    a.motion.w = f32(SP_NUTRIENT);
    a.matter.z = 0.0;
    a.matter.x = 2.0 * particleRadius(u, SP_NUTRIENT, a.matter.y);
    atomicAddFloat(6u, a.matter.y);
    reacted = true;
  } else if (ka == SP_ANTITOXIN && (kb == SP_TOXIN || kb == SP_TAG || kb == SP_PORE)) {
    a.motion.w = f32(SP_WASTE);
    a.matter.y += b.matter.y;
    a.matter.x = 2.0 * particleRadius(u, SP_WASTE, a.matter.y);
    b.motion.w = -1.0;
    b.matter.y = 0.0;
    sparkCue = 2.0;
    reacted = true;
  } else if (kb == SP_ANTITOXIN && (ka == SP_TOXIN || ka == SP_TAG || ka == SP_PORE)) {
    b.motion.w = f32(SP_WASTE);
    b.matter.y += a.matter.y;
    b.matter.x = 2.0 * particleRadius(u, SP_WASTE, b.matter.y);
    a.motion.w = -1.0;
    a.matter.y = 0.0;
    sparkCue = 2.0;
    reacted = true;
  } else if ((ka == SP_ACID && kb == SP_BUFFER) || (ka == SP_BUFFER && kb == SP_ACID)) {
    let used = min(a.matter.z, b.matter.z);
    a.matter.z = max(0.0, a.matter.z - used);
    b.matter.z = max(0.0, b.matter.z - used);
    if (a.matter.z <= 1e-6) {
      a.motion.w = f32(SP_WASTE);
      a.matter.x = 2.0 * particleRadius(u, SP_WASTE, a.matter.y);
    }
    if (b.matter.z <= 1e-6) {
      b.motion.w = f32(SP_WASTE);
      b.matter.x = 2.0 * particleRadius(u, SP_WASTE, b.matter.y);
    }
    reacted = true;
  } else if (ka == SP_WASTE && kb == SP_OXYGEN && b.matter.y >= a.matter.y * 0.45 && acid < 0.8) {
    let amt = a.matter.y;
    a.motion.w = f32(SP_NUTRIENT);
    a.matter.z = 0.0;
    a.matter.y = amt * 0.6;
    a.matter.x = 2.0 * particleRadius(u, SP_NUTRIENT, a.matter.y);
    b.motion.w = f32(SP_CARBON);
    b.matter.y = amt * 0.4;
    b.matter.z = b.matter.y;
    b.matter.x = 2.0 * particleRadius(u, SP_CARBON, b.matter.y);
    atomicAddFloat(6u, amt * 0.6);
    reacted = true;
  } else if (kb == SP_WASTE && ka == SP_OXYGEN && a.matter.y >= b.matter.y * 0.45 && acid < 0.8) {
    let amt = b.matter.y;
    b.motion.w = f32(SP_NUTRIENT);
    b.matter.z = 0.0;
    b.matter.y = amt * 0.6;
    b.matter.x = 2.0 * particleRadius(u, SP_NUTRIENT, b.matter.y);
    a.motion.w = f32(SP_CARBON);
    a.matter.y = amt * 0.4;
    a.matter.z = a.matter.y;
    a.matter.x = 2.0 * particleRadius(u, SP_CARBON, a.matter.y);
    atomicAddFloat(6u, amt * 0.6);
    reacted = true;
  } else if (ka == SP_NUTRIENT && kb == SP_TOXIN) {
    a.motion.w = f32(SP_WASTE);
    a.matter.x = 2.0 * particleRadius(u, SP_WASTE, a.matter.y);
    reacted = true;
  } else if (kb == SP_NUTRIENT && ka == SP_TOXIN) {
    b.motion.w = f32(SP_WASTE);
    b.matter.x = 2.0 * particleRadius(u, SP_WASTE, b.matter.y);
    reacted = true;
  } else if (ka == kb && (ka == SP_NUTRIENT || ka == SP_WASTE || ka == SP_CARBON || ka == SP_OXYGEN)) {
    let total = a.matter.y + b.matter.y;
    if (total > 0.0 && total <= mergeLimit(ka)) {
      let t = b.matter.y / total;
      a.motion.x = mix(a.motion.x, b.motion.x, t);
      a.motion.y = mix(a.motion.y, b.motion.y, t);
      if (ka == SP_NUTRIENT) {
        a.matter.z = nutrientCapacity(a.matter.y, a.matter.z, b.matter.y, b.matter.z, acid);
      } else {
        a.matter.z = a.matter.z + b.matter.z;
      }
      a.matter.y = total;
      a.matter.x = 2.0 * particleRadius(u, ka, total);
      b.motion.w = -1.0;
      b.matter.y = 0.0;
      reacted = true;
    }
  }

  if (reacted) {
    particles[i] = a;
    particles[j] = b;
    atomicAdd(&atomicStats[7], 1u);
    recordSpark(mid, sparkCue);
  }
}
