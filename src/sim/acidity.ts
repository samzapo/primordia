import {
  FIELD_COUNT,
  GRID_COLS,
  GRID_ROWS,
  GRID_SIZE,
  clamp,
  lerp,
  posmod,
  wrapX,
  wrapY,
} from './constants.ts';
import type { Medium } from './medium.ts';

export const ACID_DIFFUSION = 0.12;
export const ACID_NEUTRALIZATION = 0.08;
export const EXCESS_MOLAR = 0.001; // 1 unit = 1 mmol/L
export const WATER_KW = 1e-14;

export function phFromAcid(acid: number): number {
  const excess = Math.abs(acid) * EXCESS_MOLAR;
  const major = 0.5 * (excess + Math.sqrt(excess * excess + 4.0 * WATER_KW));
  const hPlus = acid >= 0 ? major : WATER_KW / Math.max(major, 1e-20);
  return clamp(-Math.log10(Math.max(hPlus, 1e-20)), 0.0, 14.0);
}

export class Acidity {
  readonly values = new Float32Array(FIELD_COUNT);
  private readonly next = new Float32Array(FIELD_COUNT);

  static index(x: number, y: number): number {
    return posmod(y, GRID_ROWS) * GRID_COLS + posmod(x, GRID_COLS);
  }

  sample(px: number, py: number): number {
    const qx = wrapX(px) / GRID_SIZE - 0.5;
    const qy = wrapY(py) / GRID_SIZE - 0.5;
    const x = Math.floor(qx);
    const y = Math.floor(qy);
    const fx = qx - x;
    const fy = qy - y;

    const v00 = this.values[Acidity.index(x, y)];
    const v10 = this.values[Acidity.index(x + 1, y)];
    const v01 = this.values[Acidity.index(x, y + 1)];
    const v11 = this.values[Acidity.index(x + 1, y + 1)];
    return lerp(lerp(v00, v10, fx), lerp(v01, v11, fx), fy);
  }

  phAt(px: number, py: number): number {
    return phFromAcid(this.sample(px, py));
  }

  exchange(px: number, py: number, delta: number): number {
    const gx = posmod(Math.floor(px / GRID_SIZE), GRID_COLS);
    const gy = posmod(Math.floor(py / GRID_SIZE), GRID_ROWS);
    const idx = gy * GRID_COLS + gx;
    const before = this.values[idx];
    const after = clamp(before + delta, 0.0, 1.0);
    this.values[idx] = after;
    return after - before;
  }

  step(dt: number, medium: Medium): void {
    const diffBlend = Math.min(1.0, dt * ACID_DIFFUSION);
    const decay = Math.exp(-dt * ACID_NEUTRALIZATION);

    for (let y = 0; y < GRID_ROWS; y++) {
      for (let x = 0; x < GRID_COLS; x++) {
        const i = y * GRID_COLS + x;
        const vx = medium.velocity[i * 2];
        const vy = medium.velocity[i * 2 + 1];
        const ux = (x + 0.5) * GRID_SIZE - vx * dt;
        const uy = (y + 0.5) * GRID_SIZE - vy * dt;
        const upstream = this.sample(ux, uy);

        const avg4 =
          0.25 *
          (this.values[Acidity.index(x - 1, y)] +
            this.values[Acidity.index(x + 1, y)] +
            this.values[Acidity.index(x, y - 1)] +
            this.values[Acidity.index(x, y + 1)]);
        const mixed = lerp(upstream, avg4, diffBlend);
        this.next[i] = clamp(mixed * decay, 0.0, 1.0);
      }
    }
    this.values.set(this.next);
  }
}
