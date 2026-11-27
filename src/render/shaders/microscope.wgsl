@group(0) @binding(0) var<uniform> cam: CameraUniforms;
@group(0) @binding(1) var sceneTex: texture_2d<f32>;
@group(0) @binding(2) var focusMaskTex: texture_2d<f32>;
@group(0) @binding(3) var sceneSampler: sampler;

struct VSOut {
  @builtin(position) pos: vec4f,
  @location(0) uv: vec2f,
  @location(1) screenPx: vec2f,
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
  out.screenPx = out.uv * cam.view1.xy;
  return out;
}

@fragment
fn fsMain(in: VSOut) -> @location(0) vec4f {
  var uv = in.uv;
  var lensWeight: f32 = 0.0;

  // 3.5x inspector circular lens UV warp
  if (cam.lens0.w > 0.5 && cam.lens0.z > 2.0) {
    let delta = in.screenPx - cam.lens0.xy;
    let d = length(delta);
    let r = cam.lens0.z;
    if (d < r) {
      let n = d / r;
      let mag = mix(1.0 / 3.5, 0.55, pow(n, 3.0));
      let warpedPx = cam.lens0.xy + delta * mag;
      uv = clamp(warpedPx / max(cam.view1.xy, vec2f(1.0)), vec2f(0.001), vec2f(0.999));
      lensWeight = smoothstep(r, r - 6.0, d);
    }
  }

  let sharp = textureSampleLevel(sceneTex, sceneSampler, uv, 0.0).rgb;
  var col = sharp;

  // Peripheral mipmap blur (coupled solely to screen edge & off during active lens)
  if (cam.modes1.x > 0.5) {
    let centered = (in.uv - vec2f(0.5)) * 2.0;
    let edgeLen = length(centered);
    let fringe = smoothstep(0.66, 1.05, edgeLen) * (1.0 - lensWeight);
    if (fringe > 0.001) {
      let blurred = textureSampleLevel(sceneTex, sceneSampler, uv, fringe * 3.5).rgb;
      col = mix(col, blurred, clamp(fringe * 0.85, 0.0, 0.85));
    }
  }

  // Toggleable 9-tap sunlit bloom
  if (cam.modes0.z > 0.5) {
    let px = vec2f(2.2) / max(cam.view1.xy, vec2f(1.0));
    var bloomAcc = vec3f(0.0);
    for (var oy = -1; oy <= 1; oy++) {
      for (var ox = -1; ox <= 1; ox++) {
        let s = textureSampleLevel(sceneTex, sceneSampler, uv + vec2f(f32(ox), f32(oy)) * px, 1.5).rgb;
        let lum = dot(s, vec3f(0.299, 0.587, 0.114));
        let hi = max(0.0, lum - 0.58);
        bloomAcc += s * hi;
      }
    }
    col += (bloomAcc / 9.0) * 0.42;
  }

  // Exterior greyscale dim in interoception or merge selection mode
  if (cam.modes0.x > 0.5 || cam.modes0.y > 0.5) {
    let inside = textureSampleLevel(focusMaskTex, sceneSampler, uv, 0.0).r;
    let grey = dot(col, vec3f(0.299, 0.587, 0.114)) * 0.35;
    col = mix(vec3f(grey), col, inside);
  }

  // Subtle microscope edge vignette
  let vigD = length((in.uv - vec2f(0.5)) * vec2f(1.12, 1.0));
  let vig = 1.0 - smoothstep(0.55, 1.15, vigD) * 0.22;
  col *= vig;

  // Lens optical tint inside rim
  if (lensWeight > 0.01) {
    col = mix(col, col * 1.05 + vec3f(0.01, 0.03, 0.04), lensWeight * 0.35);
  }

  return vec4f(clamp(col, vec3f(0.0), vec3f(1.0)), 1.0);
}
