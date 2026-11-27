export const WORLD_W = 4096.0;
export const WORLD_H = 2560.0;
export const GRID_COLS = 64;
export const GRID_ROWS = 40;
export const GRID_SIZE = 64.0;
export const FIELD_COUNT = GRID_COLS * GRID_ROWS; // 2560

export const BIN_SIZE = 16.0;
export const BIN_COLS = 256;
export const BIN_ROWS = 160;
export const BIN_COUNT = BIN_COLS * BIN_ROWS; // 40960

export const VIEW_W = 1016.0;
export const VIEW_H = 632.0;
export const MIN_ZOOM = 0.8;
export const MAX_ZOOM = 12.0;
export const MAX_INTERO_ZOOM = 120.0;

export const DT = 1.0 / 60.0;
export const MICROMETERS_PER_UNIT = 0.2;
export const UNITS_PER_UM = 5.0;

export const MAX_LIVE_CELLS = 64;
export const MAX_FAMILY_CELLS = 12;
export const MIN_LIVING_CELLS = 15;

export const MAX_PARTICLES = 32768;
export const PHEROMONE_RATE = 8.0;
export const PHEROMONE_DECAY = 1.0 / 15.0;

export const SPECIES_COUNT = 26;
export const SPECIES = {
  NUTRIENT: 0,
  OXYGEN: 1,
  WASTE: 2,
  PHEROMONE: 3,
  TOXIN: 4,
  CARBON: 5,
  ENZYME: 6,
  ANTITOXIN: 7,
  ACID: 8,
  BUFFER: 9,
  DECOY: 10,
  TAG: 11,
  PORE: 12,
  GLUCOSE: 13,
  PYRUVATE: 14,
  LACTATE: 15,
  PRECURSOR: 16,
  SALVAGE: 17,
  CATALYST_A: 18,
  CATALYST_B: 19,
  NAD: 20,
  NADH: 21,
  ATP: 22,
  ADP: 23,
  CATALYST: 24,
  WATER: 25,
} as const;

export const TAU = Math.PI * 2;

export interface Vec2 {
  x: number;
  y: number;
}

export function vec2(x = 0, y = 0): Vec2 {
  return { x, y };
}

export function posmod(a: number, n: number): number {
  const m = a % n;
  return m < 0 ? m + n : m;
}

export function clamp(v: number, lo: number, hi: number): number {
  return v < lo ? lo : v > hi ? hi : v;
}

export function lerp(a: number, b: number, t: number): number {
  return a + (b - a) * t;
}

export function smoothstep(edge0: number, edge1: number, x: number): number {
  const t = clamp((x - edge0) / (edge1 - edge0), 0, 1);
  return t * t * (3 - 2 * t);
}

export function wrapX(x: number): number {
  return posmod(x, WORLD_W);
}

export function wrapY(y: number): number {
  return posmod(y, WORLD_H);
}

export function wrapPos(p: Vec2): Vec2 {
  return { x: posmod(p.x, WORLD_W), y: posmod(p.y, WORLD_H) };
}

export function wrapf(v: number, lo: number, hi: number): number {
  const span = hi - lo;
  return lo + posmod(v - lo, span);
}

export function wrapAngle(a: number): number {
  return wrapf(a, -Math.PI, Math.PI);
}

export function lerpAngle(a: number, b: number, t: number): number {
  return wrapAngle(a + wrapAngle(b - a) * t);
}

export function offsetX(ax: number, bx: number): number {
  return wrapf(bx - ax, -WORLD_W * 0.5, WORLD_W * 0.5);
}

export function offsetY(ay: number, by: number): number {
  return wrapf(by - ay, -WORLD_H * 0.5, WORLD_H * 0.5);
}

export function offsetVec(a: Vec2, b: Vec2): Vec2 {
  return { x: offsetX(a.x, b.x), y: offsetY(a.y, b.y) };
}

export function vecLenSq(v: Vec2): number {
  return v.x * v.x + v.y * v.y;
}

export function vecLen(v: Vec2): number {
  return Math.hypot(v.x, v.y);
}

export function vecNorm(v: Vec2): Vec2 {
  const l = Math.hypot(v.x, v.y);
  return l > 1e-8 ? { x: v.x / l, y: v.y / l } : { x: 1, y: 0 };
}

export function vecRot(v: Vec2, angle: number): Vec2 {
  const c = Math.cos(angle);
  const s = Math.sin(angle);
  return { x: v.x * c - v.y * s, y: v.x * s + v.y * c };
}

export function vecCross(a: Vec2, b: Vec2): number {
  return a.x * b.y - a.y * b.x;
}

export function vecDot(a: Vec2, b: Vec2): number {
  return a.x * b.x + a.y * b.y;
}

export function vecFromAngle(a: number, len = 1): Vec2 {
  return { x: Math.cos(a) * len, y: Math.sin(a) * len };
}

export function vecLimit(v: Vec2, maxLen: number): Vec2 {
  const l = Math.hypot(v.x, v.y);
  if (l <= maxLen || l <= 1e-12) return { x: v.x, y: v.y };
  const s = maxLen / l;
  return { x: v.x * s, y: v.y * s };
}
