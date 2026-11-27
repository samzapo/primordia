@group(0) @binding(0) var<uniform> u: SimUniforms;
@group(0) @binding(1) var<storage, read> particles: array<Particle>;
@group(0) @binding(2) var<storage, read> binOffsets: array<u32>;
@group(0) @binding(3) var<storage, read_write> binCursors: array<atomic<u32>>;
@group(0) @binding(4) var<storage, read_write> sortedSlots: array<u32>;

@compute @workgroup_size(128)
fn main(@builtin(global_invocation_id) gid: vec3u) {
  let i = gid.x;
  let maxP = u32(u.params1.x + 0.5);
  if (i >= maxP) { return; }

  let p = particles[i];
  if (p.motion.w < -0.5) { return; }

  let b = binIndex(p.pose.xy);
  let baseOffset = binOffsets[b];
  let localOffset = atomicAdd(&binCursors[b], 1u);
  let pos = baseOffset + localOffset;
  if (pos < maxP) {
    sortedSlots[pos] = i;
  }
}
