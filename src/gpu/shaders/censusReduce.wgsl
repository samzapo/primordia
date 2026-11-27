@group(0) @binding(0) var<uniform> u: SimUniforms;
@group(0) @binding(1) var<storage, read> particles: array<Particle>;
@group(0) @binding(2) var<storage, read> acidField: array<f32>;
@group(0) @binding(3) var<storage, read> atomicStats: array<u32>;
@group(0) @binding(4) var<storage, read_write> receipts: Receipts;

var<workgroup> shAlive: array<u32, 256>;
var<workgroup> shPhero: array<u32, 256>;
var<workgroup> shMat: array<u32, 256>;
var<workgroup> shOxy: array<u32, 256>;

@compute @workgroup_size(256)
fn main(@builtin(local_invocation_id) lid: vec3u) {
  let lane = lid.x;
  let maxP = u32(u.params1.x + 0.5);
  var alive = 0u;
  var pheromones = 0u;
  var materialCount = 0u;
  var oxygenCount = 0u;

  for (var i = lane; i < maxP; i += 256u) {
    let p = particles[i];
    if (p.motion.w < -0.5) { continue; }
    alive += 1u;
    let kind = u32(p.motion.w + 0.5);
    if (kind == SP_PHEROMONE) {
      pheromones += 1u;
    } else if (kind == SP_OXYGEN) {
      oxygenCount += 1u;
    }
    if (speciesMaterial(u, kind) > 0.5) {
      materialCount += 1u;
    }
  }

  shAlive[lane] = alive;
  shPhero[lane] = pheromones;
  shMat[lane] = materialCount;
  shOxy[lane] = oxygenCount;
  workgroupBarrier();

  for (var stride = 128u; stride > 0u; stride >>= 1u) {
    if (lane < stride) {
      shAlive[lane] += shAlive[lane + stride];
      shPhero[lane] += shPhero[lane + stride];
      shMat[lane] += shMat[lane + stride];
      shOxy[lane] += shOxy[lane + stride];
    }
    workgroupBarrier();
  }

  if (lane == 0u) {
    receipts.stats[0] = vec4u(shAlive[0], shPhero[0], shMat[0], shOxy[0]);
    receipts.stats[1] = vec4u(atomicStats[4], atomicStats[5], atomicStats[6], atomicStats[7]);
    receipts.stats[2] = vec4u(min(128u, atomicStats[9]), atomicStats[8], 0u, 0u);
  }

  for (var k = lane; k < FIELD_COUNT; k += 256u) {
    receipts.acidField[k] = acidField[k];
  }
}
