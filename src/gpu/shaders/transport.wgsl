@group(0) @binding(0) var<uniform> u: SimUniforms;
@group(0) @binding(1) var<storage, read_write> particles: array<Particle>;
@group(0) @binding(2) var<storage, read_write> reports: array<Report>;
@group(0) @binding(3) var<storage, read> flow: array<vec4f>;

@compute @workgroup_size(128)
fn main(@builtin(global_invocation_id) gid: vec3u) {
  let i = gid.x;
  let maxP = u32(u.params1.x + 0.5);
  if (i >= maxP) { return; }

  var p = particles[i];
  if (p.motion.w < -0.5) { return; }

  let kind = u32(p.motion.w + 0.5);
  let dt = u.params0.x;
  let now = u.params0.y;
  let tick = u32(u.params0.z + 0.5);

  if (kind == SP_PHEROMONE) {
    let rep = reports[i];
    if (rep.timing.y <= now || rep.timing.z < 0.5) {
      p.motion.w = -1.0;
      p.matter.y = 0.0;
      particles[i] = p;
      return;
    }
  }

  let baseFlow = sampleFieldVec(&flow, p.pose.xy);
  var vel = baseFlow;

  if (kind != SP_PHEROMONE) {
    let mouthCount = u32(u.params4.w + 0.5);
    var pull = vec2f(0.0, 0.0);
    var strongest: f32 = -1.0;
    for (var m = 0u; m < mouthCount; m++) {
      let desc = flow[FIELD_COUNT + m];
      let delta = offsetVec(p.pose.xy, desc.xy);
      let d = length(delta);
      let reach = desc.z;
      if (d >= reach || d < 1e-6) { continue; }
      let speed = desc.w * (1.0 - d / reach) * min(1.0, d / 24.0);
      if (speed > strongest + 0.0001) {
        strongest = speed;
        pull = (delta / d) * speed;
      }
    }
    let mult = select(0.2, 1.0, kind == SP_NUTRIENT);
    vel += pull * mult;
  }

  let seedBase = (i * 747796405u) ^ (tick * 2891336453u) ^ (u32(u.params0.w) * 1640531527u);
  let bm = boxMuller(seedBase + 1u, seedBase + 2u);
  let diff = select(12.0, 240.0, kind == SP_PHEROMONE);
  let diffStd = sqrt(diff * dt);

  var nextPos = p.pose.xy + (p.motion.xy + vel) * dt + bm * diffStd;
  nextPos = wrapPos(nextPos);
  p.pose.x = nextPos.x;
  p.pose.y = nextPos.y;

  if (kind == SP_PHEROMONE) {
    p.motion.x = 0.0;
    p.motion.y = 0.0;
    p.pose.z = 0.0;
    p.pose.w = 0.0;
  } else {
    let damp = exp(-0.8 * dt);
    p.motion.x *= damp;
    p.motion.y *= damp;
    let rNoise = boxMuller(seedBase + 3u, seedBase + 4u).x * sqrt(1.2 * dt);
    p.pose.z = wrapAngle(p.pose.z + p.pose.w * dt + rNoise);
  }

  p.motion.z += dt;
  particles[i] = p;
}
