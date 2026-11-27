const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;
const WORLD_W: f32 = 4096.0;
const WORLD_H: f32 = 2560.0;
const GRID_COLS: u32 = 64u;
const GRID_ROWS: u32 = 40u;
const GRID_SIZE: f32 = 64.0;

struct CameraUniforms {
  view0: vec4f,   // (camX, camY, zoom, rotation)
  view1: vec4f,   // (screenW, screenH, time, illumScale)
  lens0: vec4f,   // (lensX, lensY, lensR, lensActive)
  modes0: vec4f,  // (interoception, mergeSelecting, bloomEnabled, ripplesEnabled)
  modes1: vec4f,  // (blurEnabled, simpleParticles, focusX, focusY)
  modes2: vec4f,  // (worldW, worldH, plantAlpha, 0.0)
};

fn posmodR(a: f32, n: f32) -> f32 {
  let m = a - floor(a / n) * n;
  return select(m, m + n, m < 0.0);
}

fn wrapWorld(p: vec2f) -> vec2f {
  return vec2f(posmodR(p.x, WORLD_W), posmodR(p.y, WORLD_H));
}

fn wrapDelta(camPos: vec2f, dst: vec2f) -> vec2f {
  var d = dst - camPos;
  if (d.x > WORLD_W * 0.5) { d.x -= WORLD_W; }
  if (d.x < -WORLD_W * 0.5) { d.x += WORLD_W; }
  if (d.y > WORLD_H * 0.5) { d.y -= WORLD_H; }
  if (d.y < -WORLD_H * 0.5) { d.y += WORLD_H; }
  return d;
}

fn camRelToScreenPx(relPos: vec2f, cam: CameraUniforms) -> vec2f {
  let rot = -cam.view0.w;
  let c = cos(rot);
  let s = sin(rot);
  let r = vec2f(relPos.x * c - relPos.y * s, relPos.x * s + relPos.y * c);
  return cam.view1.xy * 0.5 + r * cam.view0.z;
}

fn worldToScreenPx(worldPos: vec2f, cam: CameraUniforms) -> vec2f {
  return camRelToScreenPx(wrapDelta(cam.view0.xy, worldPos), cam);
}

fn screenPxToClip(px: vec2f, cam: CameraUniforms) -> vec4f {
  let x = (px.x / max(1.0, cam.view1.x)) * 2.0 - 1.0;
  let y = 1.0 - (px.y / max(1.0, cam.view1.y)) * 2.0;
  return vec4f(x, y, 0.0, 1.0);
}

fn camRelToClip(relPos: vec2f, cam: CameraUniforms) -> vec4f {
  return screenPxToClip(camRelToScreenPx(relPos, cam), cam);
}

fn worldToClip(worldPos: vec2f, cam: CameraUniforms) -> vec4f {
  return screenPxToClip(worldToScreenPx(worldPos, cam), cam);
}

fn screenPxToWorld(px: vec2f, cam: CameraUniforms) -> vec2f {
  let v = (px - cam.view1.xy * 0.5) / max(0.001, cam.view0.z);
  let rot = cam.view0.w;
  let c = cos(rot);
  let s = sin(rot);
  let d = vec2f(v.x * c - v.y * s, v.x * s + v.y * c);
  return wrapWorld(cam.view0.xy + d);
}
