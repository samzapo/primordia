import {
  GRID_COLS,
  GRID_ROWS,
  GRID_SIZE,
  TAU,
  clamp,
} from './constants.ts';
import type { InducedCurrents } from './inducedCurrents.ts';
import { Medium } from './medium.ts';
import { SeededRng } from './rng.ts';

export const FLOW_VERSION = 4;
export const AMBIENT_STRENGTH = 2.0;

export interface EnvironmentState {
  hour: number;
  utc: string;
  weather: string;
  light: number;
  flowVersion: number;
  flowAngle: number;
  flowStrength: number;
}

const CLOUDS: Array<[string, number]> = [
  ['Clear', 1.05],
  ['Hazy', 0.85],
  ['Cloudy', 0.65],
  ['Overcast', 0.45],
];

export function updateEnvironmentCycle(
  seedValue: number,
  env: EnvironmentState,
  induced: InducedCurrents,
  medium: Medium,
  unixSeconds: number,
): boolean {
  const hourKey = Math.floor(unixSeconds / 3600.0);
  if (env.hour === hourKey && env.flowVersion >= FLOW_VERSION) return false;

  const date = new Date(hourKey * 3600 * 1000);
  const rng = new SeededRng((seedValue ^ (hourKey * 1000003)) | 0);
  const weather = CLOUDS[rng.randiRange(0, CLOUDS.length - 1)];

  const utcHour = date.getUTCHours();
  const utcMonth = date.getUTCMonth() + 1;
  const day = Math.max(0.0, Math.sin(((utcHour - 6.0) / 24.0) * TAU));
  const season = 0.85 + 0.15 * Math.cos(((utcMonth - 6.0) / 12.0) * TAU);
  const light = clamp((0.22 + 0.78 * day) * season * weather[1], 0.12, 1.1);

  const angle = rng.randRange(-0.7, 0.7);
  const strength = rng.randRange(0.65, 1.3) * AMBIENT_STRENGTH;
  const pad2 = (n: number) => String(n).padStart(2, '0');

  env.hour = hourKey;
  env.utc = `${date.getUTCFullYear()}-${pad2(utcMonth)}-${pad2(date.getUTCDate())} ${pad2(utcHour)}:00 UTC`;
  env.weather = weather[0];
  env.light = light;
  env.flowVersion = FLOW_VERSION;
  env.flowAngle = angle;
  env.flowStrength = strength;

  const c = Math.cos(angle);
  const s = Math.sin(angle);
  for (let y = 0; y < GRID_ROWS; y++) {
    for (let x = 0; x < GRID_COLS; x++) {
      const i = (y * GRID_COLS + x) * 2;
      const base = Medium.baseCurrent((x + 0.5) * GRID_SIZE, (y + 0.5) * GRID_SIZE);
      const rx = (base.x * c - base.y * s) * strength;
      const ry = (base.x * s + base.y * c) * strength;
      induced.baseTide[i] = rx;
      induced.baseTide[i + 1] = ry;
      medium.tide[i] = rx;
      medium.tide[i + 1] = ry;
    }
  }
  induced.reset();
  return true;
}
