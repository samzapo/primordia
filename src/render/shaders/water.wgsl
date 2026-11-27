@group(0) @binding(0) var<uniform> cam: CameraUniforms;
@group(0) @binding(1) var<storage, read> acidField: array<f32>;
@group(0) @binding(2) var lightTex: texture_2d<f32>;
@group(0) @binding(3) var lightSampler: sampler;

struct VSOut {
  @builtin(position) pos: vec4f,
  @location(0) screenPx: vec2f,
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
  let uv = vec2f(ndc.x * 0.5 + 0.5, 0.5 - ndc.y * 0.5);
  out.screenPx = uv * cam.view1.xy;
  return out;
}

fn fieldIdxW(x: i32, y: i32) -> u32 {
  let wx = ((x % i32(GRID_COLS)) + i32(GRID_COLS)) % i32(GRID_COLS);
  let wy = ((y % i32(GRID_ROWS)) + i32(GRID_ROWS)) % i32(GRID_ROWS);
  return u32(wy) * GRID_COLS + u32(wx);
}

fn bsplineWeights(t: f32) -> vec4f {
  let u = 1.0 - t;
  return vec4f(
    u * u * u * (1.0 / 6.0),
    (3.0 * t * t * t - 6.0 * t * t + 4.0) * (1.0 / 6.0),
    (-3.0 * t * t * t + 3.0 * t * t + 3.0 * t + 1.0) * (1.0 / 6.0),
    t * t * t * (1.0 / 6.0),
  );
}

fn sampleAcidBicubic(worldPos: vec2f) -> f32 {
  let q = worldPos / GRID_SIZE - vec2f(0.5, 0.5);
  let ix = i32(floor(q.x));
  let iy = i32(floor(q.y));
  let fx = q.x - f32(ix);
  let fy = q.y - f32(iy);
  let wx = bsplineWeights(fx);
  let wy = bsplineWeights(fy);

  var acc: f32 = 0.0;
  for (var dy = -1; dy <= 2; dy++) {
    let wyVal = wy[u32(dy + 1)];
    var row: f32 = 0.0;
    row += acidField[fieldIdxW(ix - 1, iy + dy)] * wx.x;
    row += acidField[fieldIdxW(ix + 0, iy + dy)] * wx.y;
    row += acidField[fieldIdxW(ix + 1, iy + dy)] * wx.z;
    row += acidField[fieldIdxW(ix + 2, iy + dy)] * wx.w;
    acc += row * wyVal;
  }
  return acc;
}

fn phPaletteColor(ph: f32) -> vec3f {
  var stops = array<vec3f, 15>(
    vec3f(0.937, 0.220, 0.635), // 0  #ef38a2
    vec3f(0.961, 0.184, 0.510), // 1  #f52f82
    vec3f(0.980, 0.333, 0.486), // 2  #fa557c
    vec3f(1.000, 0.588, 0.227), // 3  #ff963a
    vec3f(1.000, 0.886, 0.471), // 4  #ffe278
    vec3f(0.875, 0.914, 0.612), // 5  #dfe99c
    vec3f(0.910, 0.929, 0.737), // 6  #e8edbc
    vec3f(0.910, 0.929, 0.737), // 7  neutral #e8edbc
    vec3f(0.749, 0.851, 0.267), // 8  #bfd944
    vec3f(0.090, 0.710, 0.271), // 9  #17b545
    vec3f(0.188, 0.655, 0.561), // 10 #30a78f
    vec3f(0.459, 0.847, 0.922), // 11 #75d8eb
    vec3f(0.141, 0.663, 0.776), // 12 #24a9c6
    vec3f(0.471, 0.380, 0.710), // 13 #7861b5
    vec3f(0.455, 0.169, 0.816)  // 14 #742bd0
  );
  let clamped = clamp(ph, 0.0, 14.0);
  let i0 = u32(floor(clamped));
  let i1 = min(14u, i0 + 1u);
  let f = clamped - f32(i0);
  return mix(stops[i0], stops[i1], f);
}

fn voronoiHash(p: vec2f) -> vec2f {
  let k = vec2f(dot(p, vec2f(127.1, 311.7)), dot(p, vec2f(269.5, 183.3)));
  return fract(sin(k) * 43758.5453);
}

fn causticPattern(wp: vec2f, t: f32) -> f32 {
  let scale = vec2f(26.0 / WORLD_W, 16.0 / WORLD_H);
  let p = wp * scale;
  let ip = floor(p);
  let fp = fract(p);
  var md1: f32 = 8.0;
  var md2: f32 = 8.0;

  for (var j = -1; j <= 1; j++) {
    for (var i = -1; i <= 1; i++) {
      let g = vec2f(f32(i), f32(j));
      let cell = vec2f(posmodR(ip.x + g.x, 26.0), posmodR(ip.y + g.y, 16.0));
      let o = voronoiHash(cell);
      let anim = 0.5 + 0.5 * sin(t * 0.85 + o * TAU);
      let r = g + anim - fp;
      let d = dot(r, r);
      if (d < md1) {
        md2 = md1;
        md1 = d;
      } else if (d < md2) {
        md2 = d;
      }
    }
  }
  let ridge = clamp(1.0 - sqrt(md2) + sqrt(md1), 0.0, 1.0);
  return pow(ridge, 3.2);
}

@fragment
fn fsMain(in: VSOut) -> @location(0) vec4f {
  let wp = screenPxToWorld(in.screenPx, cam);
  let uv = vec2f(wp.x / WORLD_W, wp.y / WORLD_H);
  let light = textureSampleLevel(lightTex, lightSampler, uv, 0.0).r;
  let illumScale = max(0.06, cam.view1.w);
  let sunlit = smoothstep(0.18, 0.78, light / illumScale);
  let daylight = 0.55 + 0.45 * sqrt(clamp(cam.view1.w, 0.0, 2.0));

  var col = mix(vec3f(0.008, 0.013, 0.048), vec3f(0.055, 0.38, 0.44), sunlit) * daylight;

  // Subtle multi-harmonic pond depth shimmer
  let wave = sin(wp.x * 0.0055 + cam.view1.z * 0.25) * cos(wp.y * 0.007 - cam.view1.z * 0.18);
  col += vec3f(0.01, 0.04, 0.05) * wave * (0.25 + 0.75 * sunlit);

  if (cam.modes0.w > 0.5) {
    let caust = causticPattern(wp, cam.view1.z);
    col += vec3f(0.08, 0.22, 0.24) * caust * (0.2 + 0.8 * sunlit) * daylight;
  }

  // Bicubic pH watercolor veil
  let acid = sampleAcidBicubic(wp);
  let excess = abs(acid) * 0.001;
  let major = 0.5 * (excess + sqrt(excess * excess + 4e-14));
  let hPlus = select(1e-14 / max(major, 1e-20), major, acid >= 0.0);
  let ph = clamp(-log2(max(hPlus, 1e-20)) / log2(10.0), 0.0, 14.0);
  let phWeight = smoothstep(0.25, 2.0, abs(ph - 7.0)) * 0.82;
  let phCol = phPaletteColor(ph);
  col = mix(col, phCol, phWeight);

  return vec4f(col, 1.0);
}
