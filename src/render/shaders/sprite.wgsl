@group(0) @binding(0) var<uniform> cam: CameraUniforms;
@group(0) @binding(1) var spriteTex: texture_2d_array<f32>;
@group(0) @binding(2) var spriteSampler: sampler;

struct SpriteInst {
  @location(0) geom: vec4f,   // (x, y, halfW, halfH)
  @location(1) xform: vec4f,  // (angle, layer_f32, isScreen, lensClip)
  @location(2) color: vec4f,  // (r, g, b, a)
};

struct VSOut {
  @builtin(position) pos: vec4f,
  @location(0) uv: vec2f,
  @location(1) @interpolate(flat) layer: u32,
  @location(2) color: vec4f,
  @location(3) screenPx: vec2f,
  @location(4) @interpolate(flat) lensClip: f32,
};

@vertex
fn vsMain(
  @builtin(vertex_index) vid: u32,
  inst: SpriteInst,
) -> VSOut {
  var corners = array<vec2f, 6>(
    vec2f(-1.0, -1.0),
    vec2f(1.0, -1.0),
    vec2f(1.0, 1.0),
    vec2f(-1.0, -1.0),
    vec2f(1.0, 1.0),
    vec2f(-1.0, 1.0),
  );
  let cPos = corners[vid];
  let isScreen = inst.xform.z > 0.5;
  let ang = select(inst.xform.x - cam.view0.w, inst.xform.x, isScreen);
  let c = cos(ang);
  let s = sin(ang);
  let scale = select(cam.view0.z, 1.0, isScreen);
  let centerPx = select(worldToScreenPx(inst.geom.xy, cam), inst.geom.xy, isScreen);
  let localPx = vec2f(cPos.x * inst.geom.z, cPos.y * inst.geom.w) * scale;
  let rPx = vec2f(localPx.x * c - localPx.y * s, localPx.x * s + localPx.y * c);
  let finalPx = centerPx + rPx;

  var out: VSOut;
  out.pos = screenPxToClip(finalPx, cam);
  out.uv = cPos * 0.5 + 0.5;
  out.layer = u32(max(0.0, inst.xform.y + 0.5));
  out.color = inst.color;
  out.screenPx = finalPx;
  out.lensClip = inst.xform.w;
  return out;
}

@fragment
fn fsMain(in: VSOut) -> @location(0) vec4f {
  if (in.lensClip > 0.5 && cam.lens0.w > 0.5) {
    let d = length(in.screenPx - cam.lens0.xy);
    if (d > cam.lens0.z - 1.5) { discard; }
  }
  let tex = textureSampleLevel(spriteTex, spriteSampler, in.uv, in.layer, 0.0);
  let a = tex.a * in.color.a;
  if (a < 0.004) { discard; }
  return vec4f(tex.rgb * in.color.rgb, a);
}
