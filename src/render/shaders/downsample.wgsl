@group(0) @binding(0) var srcTex: texture_2d<f32>;
@group(0) @binding(1) var srcSampler: sampler;

struct VSOut {
  @builtin(position) pos: vec4f,
  @location(0) uv: vec2f,
};

@vertex
fn vsMain(@builtin(vertex_index) vid: u32) -> VSOut {
  var corners = array<vec2f, 3>(
    vec2f(-1.0, -1.0),
    vec2f(3.0, -1.0),
    vec2f(-1.0, 3.0),
  );
  let ndc = corners[vid];
  var out: VSOut;
  out.pos = vec4f(ndc, 0.0, 1.0);
  out.uv = vec2f(ndc.x * 0.5 + 0.5, 0.5 - ndc.y * 0.5);
  return out;
}

@fragment
fn fsMain(in: VSOut) -> @location(0) vec4f {
  let dims = vec2f(textureDimensions(srcTex));
  let d = vec2f(1.0) / max(dims, vec2f(1.0));
  var sum = textureSampleLevel(srcTex, srcSampler, in.uv + vec2f(-d.x, -d.y), 0.0).rgb;
  sum += textureSampleLevel(srcTex, srcSampler, in.uv + vec2f(d.x, -d.y), 0.0).rgb;
  sum += textureSampleLevel(srcTex, srcSampler, in.uv + vec2f(-d.x, d.y), 0.0).rgb;
  sum += textureSampleLevel(srcTex, srcSampler, in.uv + vec2f(d.x, d.y), 0.0).rgb;
  return vec4f(sum * 0.25, 1.0);
}
