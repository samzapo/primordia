import { ORGAN_KINDS, type OrganKind } from '../sim/cell.ts';
import { SeededRng } from '../sim/rng.ts';
import { TAU, type Vec2, clamp } from '../sim/constants.ts';

export interface LineagePalette {
  edge: string;
  body: string;
  gel: string;
  rim: string;
  shine: string;
  nucleus: string;
  nucShine: string;
}

export interface RGB {
  r: number;
  g: number;
  b: number;
}

export const LINEAGE_PALETTE_PRESETS: readonly LineagePalette[] = [
  {
    edge: '#211344',
    body: '#813dc3',
    gel: '#512b86',
    rim: '#df64d8',
    shine: '#ffc0ec',
    nucleus: '#27c4ec',
    nucShine: '#a4f4ff',
  },
  {
    edge: '#101947',
    body: '#245dd6',
    gel: '#18358b',
    rim: '#39bce8',
    shine: '#9cf3ff',
    nucleus: '#ffb62e',
    nucShine: '#fff18a',
  },
  {
    edge: '#062c39',
    body: '#128b83',
    gel: '#10535f',
    rim: '#41d4b2',
    shine: '#b9f5b0',
    nucleus: '#ffac45',
    nucShine: '#ffe887',
  },
  {
    edge: '#571338',
    body: '#ef5144',
    gel: '#bd2f52',
    rim: '#ff953b',
    shine: '#fff18c',
    nucleus: '#268fd6',
    nucShine: '#83e7ff',
  },
  {
    edge: '#351543',
    body: '#b73987',
    gel: '#732c69',
    rim: '#f373ae',
    shine: '#ffc7c9',
    nucleus: '#39b5e9',
    nucShine: '#b8f1ff',
  },
  {
    edge: '#211d4c',
    body: '#6856cb',
    gel: '#3d398f',
    rim: '#ac85ef',
    shine: '#ded1ff',
    nucleus: '#f6a942',
    nucShine: '#ffe980',
  },
] as const;

export const UI_COLORS = {
  atpGold: '#ffd34f',
  atpBright: '#fff19c',
  biomassMint: '#5ef2c2',
  healthMint: '#64f09d',
  hurtRed: '#ff4b5c',
  starveAmber: '#ff9a38',
  acidRose: '#fa557c',
  neutralCream: '#e8edbc',
  baseViolet: '#7861b5',
  vacuoleFoodRim: '#7ff7c9',
  vacuoleWasteRim: '#f48aa4',
  oxygenCyan: '#6be5ff',
  carbonSlate: '#8fa7be',
} as const;

export const ORGAN_COLORS: Record<OrganKind, string> = {
  propulsion: '#56d8ff',
  protection: '#83b8f2',
  poreforming: '#f26b8a',
  regenerative: '#60e8a8',
  feeding: '#ffbe4f',
  sensing: '#e377ff',
  photosynthesis: '#54df7d',
  toxin: '#ff5268',
  neutralizing: '#4fe6d2',
  acidifying: '#ff7d6b',
  hunting: '#ff903f',
  cilia: '#76e8ff',
  mitochondrion: '#ffd859',
  counterattack: '#ff6e9c',
  toxin_sac: '#d94d78',
  family_toward: '#79f29c',
  family_away: '#f4b366',
  proboscis: '#e85d99',
};

export function parseHex(hex: string): RGB {
  const clean = hex.trim().replace(/^#/, '');
  if (clean.length === 3) {
    const r = parseInt(clean[0] + clean[0], 16) || 0;
    const g = parseInt(clean[1] + clean[1], 16) || 0;
    const b = parseInt(clean[2] + clean[2], 16) || 0;
    return { r: r / 255, g: g / 255, b: b / 255 };
  }
  const v = parseInt(clean.slice(0, 6), 16);
  if (Number.isNaN(v)) return { r: 0.5, g: 0.5, b: 0.5 };
  return {
    r: ((v >> 16) & 0xff) / 255,
    g: ((v >> 8) & 0xff) / 255,
    b: (v & 0xff) / 255,
  };
}

export function rgbToHex(r: number, g: number, b: number): string {
  const ir = Math.round(clamp(r, 0, 1) * 255);
  const ig = Math.round(clamp(g, 0, 1) * 255);
  const ib = Math.round(clamp(b, 0, 1) * 255);
  return `#${ir.toString(16).padStart(2, '0')}${ig.toString(16).padStart(2, '0')}${ib.toString(16).padStart(2, '0')}`;
}

export function normalizeHex(hex: string): string {
  const { r, g, b } = parseHex(hex);
  return rgbToHex(r, g, b);
}

export function mixRgb(a: RGB, b: RGB, t: number): RGB {
  const u = clamp(t, 0, 1);
  return {
    r: a.r + (b.r - a.r) * u,
    g: a.g + (b.g - a.g) * u,
    b: a.b + (b.b - a.b) * u,
  };
}

export function darkenHex(hex: string, amount: number): string {
  const c = parseHex(hex);
  const u = clamp(amount, 0, 1);
  return rgbToHex(c.r * (1 - u), c.g * (1 - u), c.b * (1 - u));
}

export function lightenHex(hex: string, amount: number): string {
  const c = parseHex(hex);
  const u = clamp(amount, 0, 1);
  return rgbToHex(c.r + (1 - c.r) * u, c.g + (1 - c.g) * u, c.b + (1 - c.b) * u);
}

export function hexToRgba(hex: string, alpha = 1): [number, number, number, number] {
  const c = parseHex(hex);
  return [c.r, c.g, c.b, alpha];
}

export function hsvToRgb(h: number, s: number, v: number): RGB {
  const hh = ((h % 1) + 1) % 1;
  const i = Math.floor(hh * 6);
  const f = hh * 6 - i;
  const p = v * (1 - s);
  const q = v * (1 - f * s);
  const t = v * (1 - (1 - f) * s);
  switch (i % 6) {
    case 0:
      return { r: v, g: t, b: p };
    case 1:
      return { r: q, g: v, b: p };
    case 2:
      return { r: p, g: v, b: t };
    case 3:
      return { r: p, g: q, b: v };
    case 4:
      return { r: t, g: p, b: v };
    default:
      return { r: v, g: p, b: q };
  }
}

export function rgbToHsv(r: number, g: number, b: number): [number, number, number] {
  const max = Math.max(r, g, b);
  const min = Math.min(r, g, b);
  const d = max - min;
  let h = 0;
  if (d > 1e-6) {
    if (max === r) h = ((g - b) / d + (g < b ? 6 : 0)) / 6;
    else if (max === g) h = ((b - r) / d + 2) / 6;
    else h = ((r - g) / d + 4) / 6;
  }
  const s = max <= 1e-6 ? 0 : d / max;
  return [h, s, max];
}

export function lineagePalette(seed: number, lineage: number, customHex?: string): LineagePalette {
  const mixedSeed = (seed ^ Math.imul(lineage | 0, 1640531527)) | 0;
  const rng = new SeededRng(mixedSeed);
  const baseIdx = rng.nextUint() % LINEAGE_PALETTE_PRESETS.length;
  const preset = LINEAGE_PALETTE_PRESETS[baseIdx];
  if (!customHex) {
    return preset;
  }
  const base = normalizeHex(customHex);
  return {
    edge: darkenHex(base, 0.72),
    body: base,
    gel: darkenHex(base, 0.38),
    rim: lightenHex(base, 0.28),
    shine: lightenHex(base, 0.72),
    nucleus: preset.nucleus,
    nucShine: preset.nucShine,
  };
}

export function signalColorForLineage(seed: number, lineage: number, customHex?: string): string {
  const pal = lineagePalette(seed, lineage, customHex);
  return lightenHex(pal.rim, 0.2);
}

export function nucleusForm(seed: number, lineage: number): number {
  const mixed = (seed ^ Math.imul(lineage | 0, 2654435761)) | 0;
  const rng = new SeededRng(mixed);
  return rng.nextUint() % 3;
}

export function nucleusOutline(seed: number, lineage: number, radius: number): Vec2[] {
  const mixed = (seed ^ Math.imul(lineage | 0, 2654435761)) | 0;
  const rng = new SeededRng(mixed);
  const form = rng.nextUint() % 3;
  const phase = rng.randf() * TAU;
  const pts: Vec2[] = [];
  const steps = 32;
  for (let i = 0; i < steps; i++) {
    const a = (TAU * i) / steps;
    let rx = radius;
    let ry = radius;
    if (form === 0) {
      rx = radius * 1.06;
      ry = radius * 0.91;
    } else if (form === 1) {
      const m = 1 + 0.18 * Math.cos(3 * a + phase);
      rx = radius * m;
      ry = radius * m;
    } else {
      const m = 1 + 0.16 * Math.cos(2 * a + phase) - 0.12 * Math.cos(a - phase);
      rx = radius * m;
      ry = radius * m;
    }
    pts.push({ x: Math.cos(a) * rx, y: Math.sin(a) * ry });
  }
  return pts;
}

export function pitchWaveColor(semitones: number): [number, number, number, number] {
  const norm = clamp((semitones + 24) / 48, 0, 1);
  const hue = (0.55 - norm * 0.42 + 1) % 1;
  const c = hsvToRgb(hue, 0.72, 0.96);
  return [c.r, c.g, c.b, 0.75];
}

export function organColor(kind: string): string {
  if ((ORGAN_KINDS as readonly string[]).includes(kind)) {
    return ORGAN_COLORS[kind as OrganKind];
  }
  return '#a8c8f0';
}
