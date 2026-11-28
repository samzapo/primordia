const WORLD_W: f32 = 4096.0;
const WORLD_H: f32 = 2560.0;
const GRID_COLS: u32 = 64u;
const GRID_ROWS: u32 = 40u;
const GRID_SIZE: f32 = 64.0;
const FIELD_COUNT: u32 = 2560u;

const BIN_SIZE: f32 = 16.0;
const BIN_COLS: u32 = 256u;
const BIN_ROWS: u32 = 160u;
const BIN_COUNT: u32 = 40960u;

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

const SP_NUTRIENT: u32 = 0u;
const SP_OXYGEN: u32 = 1u;
const SP_WASTE: u32 = 2u;
const SP_PHEROMONE: u32 = 3u;
const SP_TOXIN: u32 = 4u;
const SP_CARBON: u32 = 5u;
const SP_ENZYME: u32 = 6u;
const SP_ANTITOXIN: u32 = 7u;
const SP_ACID: u32 = 8u;
const SP_BUFFER: u32 = 9u;
const SP_DECOY: u32 = 10u;
const SP_TAG: u32 = 11u;
const SP_PORE: u32 = 12u;

struct SimUniforms {
  params0: vec4f, // (dt, time, tick, seed)
  params1: vec4f, // (maxParticles, bodyCount, feedCount, emitCount)
  params2: vec4f, // (queryCount, decoyCount, ambientGroup, ambientElapsed)
  params3: vec4f, // (stepAcid, inspectActive, inspectX, inspectY)
  params4: vec4f, // (inspectMaxR, trackedSlot, trackedGen, mouthCount)
  radii: array<vec4f, 7>,
  decay: array<vec4f, 7>,
  material: array<vec4f, 7>,
};

struct Particle {
  pose: vec4f,   // (x, y, angle, spin)
  motion: vec4f, // (vx, vy, age, kind_f32; < -0.5 is dead)
  matter: vec4f, // (diameter, amount, capacity, reserve)
  ids: vec4u,    // (generation, owner, lineage, flags)
};

struct Report {
  geom: vec4f,   // (atX, atY, mass, radius)
  info: vec4u,   // (id, lineage, hostile, defended)
  timing: vec4f, // (emittedAt, expiresAt, valid, sourceSlot)
};

struct BodyGPU {
  pos: vec4f,    // (x, y, angle, extent)
  ranges: vec4u, // (visStart, visCount, physStart, physCount)
  rooms: vec4f,  // (gutRoom, oxygenRoom, carbonRoom, cellId_f32)
  flags: vec4u,  // (cellId, lineage, hasSurfaceComplexes, unattendedProtected)
  vel: vec4f,    // (vx, vy, mass, isCellWall)
};

struct FeedGPU {
  geom: vec4f, // (centerX, centerY, reach, capacity)
  ids: vec4u,  // (kindCode: 0=mouth,1=O2,2=C, bodyIndex, organId, cellId)
};

struct QueryGPU {
  geom: vec4f,  // (atX, atY, reach, mass)
  info: vec4i,  // (cellId, lineage, targetId, mode)
  extra: vec4u, // (incumbent, organId, cellIndex, isCounter)
};

struct DecoyGPU {
  geom: vec4f, // (atX, atY, normX, normY)
  ids: vec4f,  // (reach, bodyIndex_f32, organId_f32, 0)
};

struct EmissionGPU {
  pose: vec4f,         // (x, y, angle, spin)
  motion: vec4f,       // (vx, vy, kind_f32, expiresAt)
  matter: vec4f,       // (diameter, amount, capacity, 0)
  ids: vec4u,          // (owner, lineage, hasReport, 0)
  reportGeom: vec4f,   // (atX, atY, mass, radius)
  reportInfo: vec4u,   // (id, lineage, hostile, defended)
  reportTiming: vec4f, // (emittedAt, expiresAt, valid, 0)
};

struct Receipts {
  feedResults: array<vec4f, 256>,
  queryResults: array<vec4f, 3072>,
  exposureCounts: array<vec4u, 64>,
  exposureHits: array<vec4f, 4096>,
  decoyCounts: array<u32, 1024>,
  reactionSparks: array<vec4f, 128>,
  inspected: array<vec4f, 6>,
  stats: array<vec4u, 4>,
  acidField: array<f32, 2560>,
  bodyImpacts: array<i32, 1024>,
};

fn speciesRadius(u: SimUniforms, kind: u32) -> f32 {
  if (kind >= 26u) { return 3.0; }
  return u.radii[kind >> 2u][kind & 3u];
}

fn speciesDecay(u: SimUniforms, kind: u32) -> f32 {
  if (kind >= 26u) { return 0.005; }
  return u.decay[kind >> 2u][kind & 3u];
}

fn speciesMaterial(u: SimUniforms, kind: u32) -> f32 {
  if (kind >= 26u) { return 0.0; }
  return u.material[kind >> 2u][kind & 3u];
}

fn particleScale(amount: f32) -> f32 {
  return clamp(sqrt(max(0.0, amount) / 0.3), 0.8, 1.7);
}

fn particleRadius(u: SimUniforms, kind: u32, amount: f32) -> f32 {
  return speciesRadius(u, kind) * particleScale(amount);
}

fn posmodf(a: f32, n: f32) -> f32 {
  let m = a - floor(a / n) * n;
  return select(m, m + n, m < 0.0);
}

fn wrapPos(p: vec2f) -> vec2f {
  return vec2f(posmodf(p.x, WORLD_W), posmodf(p.y, WORLD_H));
}

fn wrapAngle(a: f32) -> f32 {
  return posmodf(a + PI, TAU) - PI;
}

fn offsetVec(a: vec2f, b: vec2f) -> vec2f {
  var d = b - a;
  if (d.x > WORLD_W * 0.5) { d.x -= WORLD_W; }
  if (d.x < -WORLD_W * 0.5) { d.x += WORLD_W; }
  if (d.y > WORLD_H * 0.5) { d.y -= WORLD_H; }
  if (d.y < -WORLD_H * 0.5) { d.y += WORLD_H; }
  return d;
}

fn binCoord(p: vec2f) -> vec2i {
  let wp = wrapPos(p);
  let bx = i32(clamp(floor(wp.x / BIN_SIZE), 0.0, f32(BIN_COLS - 1u)));
  let by = i32(clamp(floor(wp.y / BIN_SIZE), 0.0, f32(BIN_ROWS - 1u)));
  return vec2i(bx, by);
}

fn binIndexFromCoord(bx: i32, by: i32) -> u32 {
  let wx = ((bx % i32(BIN_COLS)) + i32(BIN_COLS)) % i32(BIN_COLS);
  let wy = ((by % i32(BIN_ROWS)) + i32(BIN_ROWS)) % i32(BIN_ROWS);
  return u32(wy) * BIN_COLS + u32(wx);
}

fn binIndex(p: vec2f) -> u32 {
  let c = binCoord(p);
  return u32(c.y) * BIN_COLS + u32(c.x);
}

fn fieldIndex(x: i32, y: i32) -> u32 {
  let wx = ((x % i32(GRID_COLS)) + i32(GRID_COLS)) % i32(GRID_COLS);
  let wy = ((y % i32(GRID_ROWS)) + i32(GRID_ROWS)) % i32(GRID_ROWS);
  return u32(wy) * GRID_COLS + u32(wx);
}

fn sampleFieldVec(field: ptr<storage, array<vec4f>, read>, p: vec2f) -> vec2f {
  let wp = wrapPos(p);
  let q = wp / GRID_SIZE - vec2f(0.5, 0.5);
  let ix = i32(floor(q.x));
  let iy = i32(floor(q.y));
  let fx = q.x - f32(ix);
  let fy = q.y - f32(iy);
  let v00 = (*field)[fieldIndex(ix, iy)].xy;
  let v10 = (*field)[fieldIndex(ix + 1, iy)].xy;
  let v01 = (*field)[fieldIndex(ix, iy + 1)].xy;
  let v11 = (*field)[fieldIndex(ix + 1, iy + 1)].xy;
  return mix(mix(v00, v10, fx), mix(v01, v11, fx), fy);
}

fn sampleAcid(acidField: ptr<storage, array<f32>, read>, p: vec2f) -> f32 {
  let wp = wrapPos(p);
  let q = wp / GRID_SIZE - vec2f(0.5, 0.5);
  let ix = i32(floor(q.x));
  let iy = i32(floor(q.y));
  let fx = q.x - f32(ix);
  let fy = q.y - f32(iy);
  let v00 = (*acidField)[fieldIndex(ix, iy)];
  let v10 = (*acidField)[fieldIndex(ix + 1, iy)];
  let v01 = (*acidField)[fieldIndex(ix, iy + 1)];
  let v11 = (*acidField)[fieldIndex(ix + 1, iy + 1)];
  return mix(mix(v00, v10, fx), mix(v01, v11, fx), fy);
}

fn acidNodeIndex(p: vec2f) -> u32 {
  let wp = wrapPos(p);
  let gx = i32(floor(wp.x / GRID_SIZE));
  let gy = i32(floor(wp.y / GRID_SIZE));
  return fieldIndex(gx, gy);
}

fn hash32(v: u32) -> u32 {
  var x = v;
  x ^= x >> 16u;
  x *= 0x7feb352du;
  x ^= x >> 15u;
  x *= 0x846ca68bu;
  x ^= x >> 16u;
  return x;
}

fn hashFloat(v: u32) -> f32 {
  return (f32(hash32(v) >> 8u) + 0.5) / 16777216.0;
}

fn boxMuller(seed0: u32, seed1: u32) -> vec2f {
  let u1 = max(1e-6, hashFloat(seed0));
  let u2 = hashFloat(seed1);
  let r = sqrt(-2.0 * log(u1));
  let th = TAU * u2;
  return vec2f(r * cos(th), r * sin(th));
}

fn bindingThreshold(a: u32, b: u32, acid: f32) -> f32 {
  if (((a == SP_ENZYME && b == SP_WASTE) || (a == SP_WASTE && b == SP_ENZYME)) ||
      (a == SP_NUTRIENT && b == SP_NUTRIENT)) {
    let dev = clamp(abs(acid - 0.25) / 0.25, 0.0, 1.0);
    return 0.5 + 0.46 * dev * dev;
  }
  return 0.5;
}

fn mergeLimit(kind: u32) -> f32 {
  return select(5.0, 200.0, kind == SP_NUTRIENT);
}

fn nutrientCapacity(a: f32, ac: f32, b: f32, bc: f32, acid: f32) -> f32 {
  let total = a + b;
  let fuel = min(a, max(0.0, ac)) + min(b, max(0.0, bc));
  if (fuel < total - 1e-6) {
    return fuel;
  }
  let bonusA = max(0.0, ac - a);
  let bonusB = max(0.0, bc - b);
  let acidAffinity = 1.0 + max(0.0, 1.0 - abs(acid - 0.25) / 0.25);
  let pairBonus = min(a, b) * 0.4 * acidAffinity;
  let maxBonus = total * 0.5;
  return total + min(maxBonus, bonusA + bonusB + pairBonus);
}

fn polygonSupport(
  points: ptr<storage, array<vec2f>, read>,
  start: u32,
  count: u32,
  localAngle: f32,
) -> f32 {
  if (count == 0u) { return 47.0; }
  let a = posmodf(localAngle, TAU);
  let idxF = (a / TAU) * f32(count);
  let i = u32(floor(idxF)) % count;
  let j = (i + 1u) % count;
  let f = idxF - floor(idxF);
  let r0 = length((*points)[start + i]);
  let r1 = length((*points)[start + j]);
  return mix(r0, r1, f);
}

fn physicalSupport(
  points: ptr<storage, array<vec2f>, read>,
  start: u32,
  count: u32,
  localAngle: f32,
) -> f32 {
  if (count == 0u) { return 47.0; }
  let a = posmodf(localAngle, TAU);
  let phase = (a / TAU) * f32(count);
  let i = u32(floor(phase)) % count;
  let j = (i + 1u) % count;
  let f = phase - floor(phase);
  let pt = mix((*points)[start + i], (*points)[start + j], f);
  return length(pt);
}
