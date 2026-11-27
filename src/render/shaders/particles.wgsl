struct Particle {
  pose: vec4f,   // (x, y, angle, spin)
  motion: vec4f, // (vx, vy, age, kind_f32)
  matter: vec4f, // (diameter, amount, capacity, reserve)
  ids: vec4u,    // (generation, owner, lineage, flags)
};

struct Report {
  geom: vec4f,
  info: vec4u,
  timing: vec4f,
};

struct LineageLut {
  colors: array<vec4f, 64>,
};

@group(0) @binding(0) var<uniform> cam: CameraUniforms;
@group(0) @binding(1) var<storage, read> particles: array<Particle>;
@group(0) @binding(2) var<storage, read> reports: array<Report>;
@group(0) @binding(3) var<uniform> lut: LineageLut;
@group(0) @binding(4) var speciesTex: texture_2d_array<f32>;
@group(0) @binding(5) var texSampler: sampler;

struct VSOut {
  @builtin(position) pos: vec4f,
  @location(0) uv: vec2f,
  @location(1) @interpolate(flat) layer: u32,
  @location(2) tint: vec4f,
};

@vertex
fn vsMain(
  @builtin(vertex_index) vid: u32,
  @builtin(instance_index) iid: u32,
) -> VSOut {
  var out: VSOut;
  let p = particles[iid];
  if (p.motion.w < -0.5) {
    out.pos = vec4f(2.0, 2.0, 0.0, 1.0);
    return out;
  }

  let kind = u32(p.motion.w + 0.5);
  let intero = cam.modes0.x > 0.5;
  // Hide external molecules during interoception, except cell pheromones
  if (intero && kind != 3u) {
    out.pos = vec4f(2.0, 2.0, 0.0, 1.0);
    return out;
  }

  var corners = array<vec2f, 6>(
    vec2f(-1.0, -1.0),
    vec2f(1.0, -1.0),
    vec2f(1.0, 1.0),
    vec2f(-1.0, -1.0),
    vec2f(1.0, 1.0),
    vec2f(-1.0, 1.0),
  );
  let cPos = corners[vid];
  let screenCenter = worldToScreenPx(p.pose.xy, cam);
  let visRad = max(2.2, p.matter.x * 0.5 * 1.45 * cam.view0.z);

  if (screenCenter.x + visRad < -16.0 || screenCenter.x - visRad > cam.view1.x + 16.0 ||
      screenCenter.y + visRad < -16.0 || screenCenter.y - visRad > cam.view1.y + 16.0) {
    out.pos = vec4f(2.0, 2.0, 0.0, 1.0);
    return out;
  }

  let ang = p.pose.z - cam.view0.w;
  let ca = cos(ang);
  let sa = sin(ang);
  let rOff = vec2f(cPos.x * ca - cPos.y * sa, cPos.x * sa + cPos.y * ca) * visRad;

  var tint = vec4f(1.0, 1.0, 1.0, 1.0);
  if (kind == 3u) {
    let rep = reports[iid];
    if (rep.timing.z < 0.5 || rep.timing.y <= cam.view1.z) {
      out.pos = vec4f(2.0, 2.0, 0.0, 1.0);
      return out;
    }
    let life = clamp((rep.timing.y - cam.view1.z) / 15.0, 0.0, 1.0);
    let linCol = lut.colors[rep.info.y % 64u].rgb;
    tint = vec4f(linCol, 0.65 * sqrt(life));
  } else {
    let alpha = select(0.92, 0.72, intero);
    tint = vec4f(1.0, 1.0, 1.0, alpha);
  }

  out.pos = screenPxToClip(screenCenter + rOff, cam);
  out.uv = cPos * 0.5 + 0.5;
  out.layer = min(kind, 25u);
  out.tint = tint;
  return out;
}

@fragment
fn fsMain(in: VSOut) -> @location(0) vec4f {
  let tex = textureSampleLevel(speciesTex, texSampler, in.uv, in.layer, 0.0);
  let a = tex.a * in.tint.a;
  if (a < 0.005) { discard; }
  return vec4f(tex.rgb * in.tint.rgb, a);
}
