@group(0) @binding(0) var<uniform> cam: CameraUniforms;

struct VSIn {
  @location(0) pos: vec2f,
  @location(1) color: vec4f,
  @location(2) edge: vec2f, // edge.x = AA signed distance metric (-1..1 for stroke, 0 for interior), edge.y = featherPx
};

struct VSOut {
  @builtin(position) pos: vec4f,
  @location(0) color: vec4f,
  @location(1) edge: vec2f,
};

@vertex
fn vsWorld(in: VSIn) -> VSOut {
  var out: VSOut;
  out.pos = worldToClip(in.pos, cam);
  out.color = in.color;
  out.edge = in.edge;
  return out;
}

@vertex
fn vsScreen(in: VSIn) -> VSOut {
  var out: VSOut;
  out.pos = screenPxToClip(in.pos, cam);
  out.color = in.color;
  out.edge = in.edge;
  return out;
}

@fragment
fn fsColor(in: VSOut) -> @location(0) vec4f {
  var alpha = in.color.a;
  if (in.edge.y > 0.001) {
    let aa = clamp((1.0 - abs(in.edge.x)) * in.edge.y, 0.0, 1.0);
    alpha *= aa;
  }
  if (alpha < 0.002) { discard; }
  return vec4f(in.color.rgb, alpha);
}

@fragment
fn fsMask(in: VSOut) -> @location(0) vec4f {
  return vec4f(1.0, 1.0, 1.0, 1.0);
}
