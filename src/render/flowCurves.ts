import { SeededRng } from '../sim/rng.ts';
import type { Habitat } from '../sim/habitat.ts';
import type { InducedCurrents } from '../sim/inducedCurrents.ts';
import type { Medium } from '../sim/medium.ts';
import { WORLD_H, WORLD_W, type Vec2, clamp, wrapPos } from '../sim/constants.ts';

export interface FlowCurve {
  points: Vec2[];
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

  // Ambient flow crests & streamlines tiled cleanly inside viewport
  const tile = 220;
  const minX = viewCenter.x - viewHalfW - tile;
  const maxX = viewCenter.x + viewHalfW + tile;
  const minY = viewCenter.y - viewHalfH - tile;
  const maxY = viewCenter.y + viewHalfH + tile;
  const gx0 = Math.floor(minX / tile);
  const gx1 = Math.ceil(maxX / tile);
  const gy0 = Math.floor(minY / tile);
  const gy1 = Math.ceil(maxY / tile);

  for (let gy = gy0; gy <= gy1; gy++) {
    for (let gx = gx0; gx <= gx1; gx++) {
      const wx = ((gx % Math.ceil(WORLD_W / tile)) + Math.ceil(WORLD_W / tile)) % Math.ceil(WORLD_W / tile);
      const wy = ((gy % Math.ceil(WORLD_H / tile)) + Math.ceil(WORLD_H / tile)) % Math.ceil(WORLD_H / tile);
      const rng = new SeededRng((seed ^ Math.imul(wx + 31, 73856093) ^ Math.imul(wy + 17, 19349663)) | 0);
      const baseX = (gx + 0.2 + 0.6 * rng.randf()) * tile;
      const baseY = (gy + 0.2 + 0.6 * rng.randf()) * tile;
      const sampleAt = wrapPos({ x: baseX, y: baseY });
      const v0 = medium.sample(sampleAt.x, sampleAt.y);
      const speed = Math.hypot(v0.x, v0.y);
      if (speed < 3.0) continue;

      const phase = (time * (0.28 + speed * 0.008) + rng.randf()) % 1.0;
      const pts: Vec2[] = [];
      let cx = sampleAt.x;
      let cy = sampleAt.y;
      const half = (STREAM_POINT_COUNT - 1) >> 1;
      for (let s = 0; s < half; s++) {
        const v = medium.sample(cx, cy);
        const l = Math.hypot(v.x, v.y);
        if (l < 1.0) break;
        cx -= (v.x / l) * stepDist;
        cy -= (v.y / l) * stepDist;
      }
      for (let i = 0; i < STREAM_POINT_COUNT; i++) {
        pts.push({ x: cx, y: cy });
        const v = medium.sample(cx, cy);
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

  // Gold streamlines emitted by induced current sources
  for (let sIdx = 0; sIdx < induced.activeSources.length; sIdx++) {
    const src = induced.activeSources[sIdx];
    if (curves.length >= 220) break;
    const baseAngle = Math.atan2(src.headingY, src.headingX);
    for (let strand = 0; strand < 2; strand++) {
      const ang = baseAngle + (strand - 0.5) * 0.8 + (src.mode === 'spiral' ? src.spin * 0.5 : 0);
      let cx = src.x + Math.cos(ang) * (18 + strand * 20);
      let cy = src.y + Math.sin(ang) * (18 + strand * 20);
      const pts: Vec2[] = [];
      for (let i = 0; i < 24; i++) {
        pts.push({ x: cx, y: cy });
        const v = medium.sample(cx, cy);
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
    const dx = Math.abs(((plant.p.x - viewCenter.x + WORLD_W * 1.5) % WORLD_W) - WORLD_W * 0.5);
    const dy = Math.abs(((plant.p.y - viewCenter.y + WORLD_H * 1.5) % WORLD_H) - WORLD_H * 0.5);
    if (dx > viewHalfW + 360 || dy > viewHalfH + 360) continue;

    const form = habitat.forms[plant.form];
    if (!form) continue;
    const scale = plant.radius / 100.0;
    const cos = Math.cos(plant.angle);
    const sin = Math.sin(plant.angle);

    for (let b = 0; b < form.branches.length && wakeCount < MAX_PLANT_WAKES; b += 3) {
      const br = form.branches[b];
      const rad = br.r * scale;
      if (br.depth > 1 || rad < 4.5) continue;
      const ax = plant.p.x + (br.a.x * cos - br.a.y * sin) * scale;
      const ay = plant.p.y + (br.a.x * sin + br.a.y * cos) * scale;
      const bx = plant.p.x + (br.b.x * cos - br.b.y * sin) * scale;
      const by = plant.p.y + (br.b.x * sin + br.b.y * cos) * scale;
      const midX = (ax + bx) * 0.5;
      const midY = (ay + by) * 0.5;
      const v = medium.sample(midX, midY);
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
