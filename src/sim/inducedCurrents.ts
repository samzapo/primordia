import {
  GRID_COLS,
  GRID_ROWS,
  GRID_SIZE,
  TAU,
  UNITS_PER_UM,
  WORLD_H,
  WORLD_W,
  offsetX,
  offsetY,
  smoothstep,
  wrapPos,
  type Vec2,
} from './constants.ts';
import { Medium } from './medium.ts';
import { SeededRng } from './rng.ts';

export const INDUCED_PERIOD = 20.0;
const LANE_COLS = 8;
const LANE_ROWS = 4;
const LANE_COUNT = LANE_COLS * LANE_ROWS; // 32
const LANE_W = WORLD_W / LANE_COLS;
const LANE_H = WORLD_H / LANE_ROWS;

export interface InducedSource {
  x: number;
  y: number;
  radius: number;
  strength: number;
  mode: 'directional' | 'spiral';
  spin: number;
  headingX: number;
  headingY: number;
  envelope: number;
}

export class InducedCurrents {
  private lastRefresh = -1.0;
  readonly baseTide = new Float32Array(GRID_COLS * GRID_ROWS * 2);
  activeSources: InducedSource[] = [];

  constructor() {
    this.resetBase();
  }

  resetBase(): void {
    for (let y = 0; y < GRID_ROWS; y++) {
      for (let x = 0; x < GRID_COLS; x++) {
        const i = (y * GRID_COLS + x) * 2;
        const c = Medium.baseCurrent((x + 0.5) * GRID_SIZE, (y + 0.5) * GRID_SIZE);
        this.baseTide[i] = c.x;
        this.baseTide[i + 1] = c.y;
      }
    }
  }

  private sampleLane(
    seedValue: number,
    lane: number,
    now: number,
  ): InducedSource | null {
    const offset = (lane * INDUCED_PERIOD) / LANE_COUNT;
    const shifted = now + offset;
    const episode = Math.floor(shifted / INDUCED_PERIOD);
    const localTime = shifted - episode * INDUCED_PERIOD;

    const rng = new SeededRng((seedValue ^ (lane * 91771 + episode * 1000003 + 0x6ed1)) | 0);
    const continuous = lane === 0 || lane === 16;
    const duration = continuous ? INDUCED_PERIOD : rng.randRange(1.0, INDUCED_PERIOD);
    if (localTime >= duration) return null;

    const ramp = Math.min(0.5, duration * 0.2);
    const envelope = smoothstep(0.0, ramp, localTime) * (1.0 - smoothstep(duration - ramp, duration, localTime));
    if (envelope <= 0.001) return null;

    const lx = (lane % LANE_COLS + rng.randf()) * LANE_W;
    const ly = (Math.floor(lane / LANE_COLS) + rng.randf()) * LANE_H;
    const diameterUm = rng.randRange(30.0, 100.0);
    const radius = diameterUm * 0.5 * UNITS_PER_UM; // 75..250
    const headingAngle = rng.randf() * TAU;
    const headingX = Math.cos(headingAngle);
    const headingY = Math.sin(headingAngle);
    const migrationSpeed = rng.randRange(10.0, 50.0) * UNITS_PER_UM; // 50..250
    const pos: Vec2 = wrapPos({
      x: lx + headingX * migrationSpeed * localTime,
      y: ly + headingY * migrationSpeed * localTime,
    });
    const mode = rng.randf() < 0.5 ? 'directional' : 'spiral';
    const spin = rng.randf() < 0.5 ? -1 : 1;
    const strength = rng.randRange(12.0, 24.0);

    return {
      x: pos.x,
      y: pos.y,
      radius,
      strength,
      mode,
      spin,
      headingX,
      headingY,
      envelope,
    };
  }

  update(seedValue: number, time: number, medium: Medium): void {
    if (this.lastRefresh >= 0 && time - this.lastRefresh < 0.1) return;
    this.lastRefresh = time;

    const sources: InducedSource[] = [];
    for (let lane = 0; lane < LANE_COUNT; lane++) {
      const src = this.sampleLane(seedValue, lane, time);
      if (src) sources.push(src);
    }
    this.activeSources = sources;

    for (let y = 0; y < GRID_ROWS; y++) {
      for (let x = 0; x < GRID_COLS; x++) {
        const idx = y * GRID_COLS + x;
        const i2 = idx * 2;
        const px = (x + 0.5) * GRID_SIZE;
        const py = (y + 0.5) * GRID_SIZE;

        let sumFade = 0;
        let forceX = 0;
        let forceY = 0;

        for (let s = 0; s < sources.length; s++) {
          const src = sources[s];
          const dx = offsetX(src.x, px);
          const dy = offsetY(src.y, py);
          const dSq = dx * dx + dy * dy;
          if (dSq >= src.radius * src.radius) continue;
          const qSq = dSq / (src.radius * src.radius);
          const fade = (1.0 - qSq) * (1.0 - qSq) * src.envelope;
          if (fade <= 0) continue;

          let fx = 0;
          let fy = 0;
          if (src.mode === 'directional') {
            fx = src.headingX * src.strength;
            fy = src.headingY * src.strength;
          } else {
            fx = (-dy * src.spin * 2.0 - dx * 0.35) * (src.strength / src.radius);
            fy = (dx * src.spin * 2.0 - dy * 0.35) * (src.strength / src.radius);
          }

          forceX += fx * fade;
          forceY += fy * fade;
          sumFade += fade;
        }

        const norm = Math.max(1.0, sumFade);
        medium.tide[i2] = this.baseTide[i2] + forceX / norm;
        medium.tide[i2 + 1] = this.baseTide[i2 + 1] + forceY / norm;
      }
    }
  }

  reset(): void {
    this.lastRefresh = -1.0;
    this.activeSources = [];
  }
}
