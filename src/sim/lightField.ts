import {
  TAU,
  WORLD_H,
  WORLD_W,
  lerp,
  posmod,
  wrapX,
  wrapY,
  type Vec2,
} from './constants.ts';

export const LIGHT_COLS = 128;
export const LIGHT_ROWS = 80;
export const LIGHT_SIZE = 32.0;

const cache = new Map<number, Float32Array>();

export function getLightGrid(seedValue: number): Float32Array {
  const existing = cache.get(seedValue);
  if (existing) return existing;

  const grid = new Float32Array(LIGHT_COLS * LIGHT_ROWS);
  const px = posmod(posmod(seedValue, 104729) * 0.6180339887, TAU);
  const py = posmod(posmod(seedValue, 130363) * 0.4142135623, TAU);

  let sum = 0;
  for (let y = 0; y < LIGHT_ROWS; y++) {
    const v = ((y + 0.5) / LIGHT_ROWS) * TAU;
    for (let x = 0; x < LIGHT_COLS; x++) {
      const u = ((x + 0.5) / LIGHT_COLS) * TAU;
      const a = u + 0.6 * Math.sin(v + py) + 0.32 * Math.sin(u - v + px);
      const b = v + 0.55 * Math.sin(u + px) + 0.25 * Math.cos(u + v + py);
      const raw =
        0.54 * Math.sin(a + px) +
        0.38 * Math.cos(b + py) +
        0.24 * Math.sin(a + b + 0.7 * px) +
        0.16 * Math.cos(2 * a - b + py) +
        0.08 * Math.sin(3 * a + 2 * b + px);
      const i = y * LIGHT_COLS + x;
      grid[i] = raw;
      sum += raw;
    }
  }

  const mean = sum / grid.length;
  let maxAbs = 1e-6;
  for (let i = 0; i < grid.length; i++) {
    maxAbs = Math.max(maxAbs, Math.abs(grid[i] - mean));
  }
  for (let i = 0; i < grid.length; i++) {
    grid[i] = 0.5 + (0.45 * (grid[i] - mean)) / maxAbs;
  }

  if (cache.size > 16) cache.clear();
  cache.set(seedValue, grid);
  return grid;
}

export function sampleLightField(seedValue: number, px: number, py: number): number {
  const grid = getLightGrid(seedValue);
  const qx = wrapX(px) / LIGHT_SIZE - 0.5;
  const qy = wrapY(py) / LIGHT_SIZE - 0.5;
  const x = Math.floor(qx);
  const y = Math.floor(qy);
  const fx = qx - x;
  const fy = qy - y;

  const x0 = posmod(x, LIGHT_COLS);
  const x1 = posmod(x + 1, LIGHT_COLS);
  const y0 = posmod(y, LIGHT_ROWS);
  const y1 = posmod(y + 1, LIGHT_ROWS);

  const v00 = grid[y0 * LIGHT_COLS + x0];
  const v10 = grid[y0 * LIGHT_COLS + x1];
  const v01 = grid[y1 * LIGHT_COLS + x0];
  const v11 = grid[y1 * LIGHT_COLS + x1];

  return lerp(lerp(v00, v10, fx), lerp(v01, v11, fx), fy);
}

export function lightDirection(seedValue: number, px: number, py: number): Vec2 {
  const step = 32.0;
  const dx =
    sampleLightField(seedValue, (px + step) % WORLD_W, py) -
    sampleLightField(seedValue, (px - step + WORLD_W) % WORLD_W, py);
  const dy =
    sampleLightField(seedValue, px, (py + step) % WORLD_H) -
    sampleLightField(seedValue, px, (py - step + WORLD_H) % WORLD_H);
  const l = Math.hypot(dx, dy);
  return l > 1e-8 ? { x: dx / l, y: dy / l } : { x: 0, y: 0 };
}
