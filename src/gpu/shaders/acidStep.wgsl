@group(0) @binding(0) var<uniform> u: SimUniforms;
@group(0) @binding(1) var<storage, read> flow: array<vec4f>;
@group(0) @binding(2) var<storage, read> acidIn: array<f32>;
@group(0) @binding(3) var<storage, read_write> acidOut: array<f32>;

@compute @workgroup_size(128)
fn main(@builtin(global_invocation_id) gid: vec3u) {
  let k = gid.x;
  if (k >= FIELD_COUNT) { return; }

  let x = i32(k % GRID_COLS);
  let y = i32(k / GRID_COLS);
  let dt = u.params0.x * 6.0;
  let vel = flow[k].xy;
  let ux = (f32(x) + 0.5) * GRID_SIZE - vel.x * dt;
  let uy = (f32(y) + 0.5) * GRID_SIZE - vel.y * dt;
  let upstream = sampleAcid(&acidIn, vec2f(ux, uy));

  let avg4 = 0.25 * (
    acidIn[fieldIndex(x - 1, y)] +
    acidIn[fieldIndex(x + 1, y)] +
    acidIn[fieldIndex(x, y - 1)] +
    acidIn[fieldIndex(x, y + 1)]
  );
  let diffBlend = min(1.0, dt * 0.12);
  let mixed = mix(upstream, avg4, diffBlend);
  acidOut[k] = clamp(mixed * exp(-dt * 0.08), 0.0, 1.0);
}
