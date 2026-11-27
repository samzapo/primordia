import { SeededRng } from '../sim/rng.ts';
import type { Habitat } from '../sim/habitat.ts';
import type { InducedCurrents } from '../sim/inducedCurrents.ts';
import type { Medium } from '../sim/medium.ts';
import { WORLD_H, WORLD_W, type Vec2, clamp, offsetVec, wrapPos } from '../sim/constants.ts';

export interface FlowCurve {
  points: Vec2[]; // Already camera-relative unwrapped coordinates
  kind: 'crest' | 'gold' | 'wake';
  alpha: number;
  width: number;
  speed: number;
}

const STREAM_POINT_COUNT = 33;
const MAX_PLANT_WAKES = 30;

export function buildFlowCurves(
  seed: number,
  time: number,
  medium: Medium,
  induced: InducedCurrents,
  habitat: Habitat,
  viewCenter: Vec2,
  viewHalfW: number,
  viewHalfH: number,
): FlowCurve[] {
  const curves: FlowCurve[] = [];
  const stepDist = 11.0;
  const maxSpan = Math.hypot(viewHalfW, viewHalfH) + 320;

  // Ambient flow crests & streamlines emitted relative to viewCenter
  const tile = 220;
  const gx0 = Math.floor(-maxSpan / tile);
  const gx1 = Math.ceil(maxSpan / tile);
  const gy0 = Math.floor(-maxSpan / tile);
  const gy1 = Math.ceil(maxSpan / tile);
  const camTileX = Math.floor(viewCenter.x / tile);
  const camTileY = Math.floor(viewCenter.y / tile);
  const cols = Math.ceil(WORLD_W / tile);
  const rows = Math.ceil(WORLD_H / tile);

  for (let dgy = gy0; dgy <= gy1; dgy++) {
    for (let dgx = gx0; dgx <= gx1; dgx++) {
      const gx = camTileX + dgx;
      const gy = camTileY + dgy;
      const wx = ((gx % cols) + cols) % cols;
      const wy = ((gy % rows) + rows) % rows;
      const rng = new SeededRng((seed ^ Math.imul(wx + 31, 73856093) ^ Math.imul(wy + 17, 19349663)) | 0);
      const baseX = (gx + 0.2 + 0.6 * rng.randf()) * tile;
      const baseY = (gy + 0.2 + 0.6 * rng.randf()) * tile;
      const sampleAt = wrapPos({ x: baseX, y: baseY });
      const rel0 = offsetVec(viewCenter, sampleAt);
      if (Math.hypot(rel0.x, rel0.y) > maxSpan) continue;

      const v0 = medium.sample(sampleAt.x, sampleAt.y);
      const speed = Math.hypot(v0.x, v0.y);
      if (speed < 3.0) continue;

      const phase = (time * (0.28 + speed * 0.008) + rng.randf()) % 1.0;
      const pts: Vec2[] = [];
      let cx = rel0.x;
      let cy = rel0.y;
      const half = (STREAM_POINT_COUNT - 1) >> 1;
      for (let s = 0; s < half; s++) {
        const v = medium.sample(viewCenter.x + cx, viewCenter.y + cy);
        const l = Math.hypot(v.x, v.y);
        if (l < 1.0) break;
        cx -= (v.x / l) * stepDist;
        cy -= (v.y / l) * stepDist;
      }
      for (let i = 0; i < STREAM_POINT_COUNT; i++) {
        pts.push({ x: cx, y: cy });
        const v = medium.sample(viewCenter.x + cx, viewCenter.y + cy);
        const l = Math.hypot(v.x, v.y);
        if (l < 1.0) break;
        cx += (v.x / l) * stepDist;
        cy += (v.y / l) * stepDist;
      }
      if (pts.length < 8) continue;

      curves.push({
        points: pts,
        kind: 'crest',
        alpha: clamp(0.14 + (speed / 45) * 0.22, 0.1, 0.36) * Math.sin(phase * Math.PI),
        width: 1.5,
        speed,
      });
    }
  }

  // Gold streamlines emitted by induced current sources within viewport
  for (let sIdx = 0; sIdx < induced.activeSources.length; sIdx++) {
    const src = induced.activeSources[sIdx];
    if (curves.length >= 220) break;
    const srcRel = offsetVec(viewCenter, src);
    if (Math.hypot(srcRel.x, srcRel.y) > maxSpan + 240) continue;
    const baseAngle = Math.atan2(src.headingY, src.headingX);
    for (let strand = 0; strand < 2; strand++) {
      const ang = baseAngle + (strand - 0.5) * 0.8 + (src.mode === 'spiral' ? src.spin * 0.5 : 0);
      let cx = srcRel.x + Math.cos(ang) * (18 + strand * 20);
      let cy = srcRel.y + Math.sin(ang) * (18 + strand * 20);
      const pts: Vec2[] = [];
      for (let i = 0; i < 24; i++) {
        pts.push({ x: cx, y: cy });
        const v = medium.sample(viewCenter.x + cx, viewCenter.y + cy);
        const l = Math.hypot(v.x, v.y);
        if (l < 1.5) break;
        cx += (v.x / l) * 12.0;
        cy += (v.y / l) * 12.0;
      }
      if (pts.length >= 6) {
        const pulse = 0.45 + 0.55 * Math.sin(time * 2.4 + sIdx * 1.1 + strand);
        curves.push({
          points: pts,
          kind: 'gold',
          alpha: 0.4 * src.envelope * clamp(src.strength / 24, 0.4, 1.0) * pulse,
          width: 2.1,
          speed: src.strength,
        });
      }
    }
  }

  // Up to 30 downstream plant wakes behind thick fractal stems
  let wakeCount = 0;
  for (const plant of habitat.plants) {
    if (wakeCount >= MAX_PLANT_WAKES) break;
    const plantRel = offsetVec(viewCenter, plant.p);
    if (Math.hypot(plantRel.x, plantRel.y) > maxSpan + plant.radius) continue;

    const form = habitat.forms[plant.form];
    if (!form) continue;
    const scale = plant.radius / 100.0;
    const cos = Math.cos(plant.angle);
    const sin = Math.sin(plant.angle);

    for (let b = 0; b < form.branches.length && wakeCount < MAX_PLANT_WAKES; b += 3) {
      const br = form.branches[b];
      const rad = br.r * scale;
      if (br.depth > 1 || rad < 4.5) continue;
      const ax = plantRel.x + (br.a.x * cos - br.a.y * sin) * scale;
      const ay = plantRel.y + (br.a.x * sin + br.a.y * cos) * scale;
      const bx = plantRel.x + (br.b.x * cos - br.b.y * sin) * scale;
      const by = plantRel.y + (br.b.x * sin + br.b.y * cos) * scale;
      const midX = (ax + bx) * 0.5;
      const midY = (ay + by) * 0.5;
      const v = medium.sample(viewCenter.x + midX, viewCenter.y + midY);
      const speed = Math.hypot(v.x, v.y);
      if (speed < 4.5) continue;
      const dirX = v.x / speed;
      const dirY = v.y / speed;
      const perpX = -dirY;
      const perpY = dirX;
      const span = clamp(speed * 1.4, 18, 65);
      for (const side of [-1, 1]) {
        const pts: Vec2[] = [];
        for (let s = 0; s < 10; s++) {
          const u = s / 9;
          const ripple = Math.sin(time * 4.5 - u * 5.0 + side) * 2.0 * u;
          pts.push({
            x: midX + dirX * (rad + u * span) + perpX * (side * (rad * 0.6 + u * 10) + ripple),
            y: midY + dirY * (rad + u * span) + perpY * (side * (rad * 0.6 + u * 10) + ripple),
          });
        }
        curves.push({
          points: pts,
          kind: 'wake',
          alpha: clamp(speed / 50, 0.08, 0.24),
          width: 1.4,
          speed,
        });
      }
      wakeCount++;
    }
  }

  return curves;
}
