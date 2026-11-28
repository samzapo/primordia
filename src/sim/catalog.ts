import chemistryJson from '../data/chemistry.json' with { type: 'json' };
import { SPECIES, SPECIES_COUNT, clamp } from './constants.ts';

export interface ExternalSpeciesDef {
  id: number;
  key: string;
  name: string;
  radius: number;
  decay: number;
  color: string;
}

export const EXTERNAL_SPECIES: readonly ExternalSpeciesDef[] = chemistryJson.external_species;
export const ECOLOGY = chemistryJson.ecology;
export const COMBAT = chemistryJson.combat;

const ZERO_MATERIAL_IDS = new Set<number>([
  SPECIES.OXYGEN,
  SPECIES.PHEROMONE,
  SPECIES.NAD,
  SPECIES.NADH,
  SPECIES.ATP,
  SPECIES.ADP,
  SPECIES.WATER,
]);

export const SPECIES_RADII = new Float32Array(SPECIES_COUNT);
export const SPECIES_DECAY = new Float32Array(SPECIES_COUNT);
export const SPECIES_MATERIAL = new Float32Array(SPECIES_COUNT);
export const SPECIES_COLORS: string[] = new Array(SPECIES_COUNT);
export const SPECIES_NAMES: string[] = new Array(SPECIES_COUNT);
export const SPECIES_KEYS: string[] = new Array(SPECIES_COUNT);
export const KEY_TO_SPECIES = new Map<string, number>();

for (const s of EXTERNAL_SPECIES) {
  SPECIES_RADII[s.id] = s.radius;
  SPECIES_DECAY[s.id] = s.decay;
  SPECIES_MATERIAL[s.id] = ZERO_MATERIAL_IDS.has(s.id) ? 0.0 : 1.0;
  SPECIES_COLORS[s.id] = `#${s.color}`;
  SPECIES_NAMES[s.id] = s.name;
  SPECIES_KEYS[s.id] = s.key;
  KEY_TO_SPECIES.set(s.key, s.id);
}

export function particleScale(amount: number): number {
  return clamp(Math.sqrt(Math.max(0, amount) / 0.3), 0.8, 1.7);
}

export function particleRadius(kind: number, amount = 0.3): number {
  const base = kind >= 0 && kind < SPECIES_COUNT ? SPECIES_RADII[kind] : 3.0;
  return base * particleScale(amount);
}

export function particleDiameter(kind: number, amount: number): number {
  return 2.0 * particleRadius(kind, amount);
}

export function materialWeight(kind: number): number {
  return kind >= 0 && kind < SPECIES_COUNT ? SPECIES_MATERIAL[kind] : 0.0;
}

export function mergeLimit(kind: number): number {
  return kind === SPECIES.NUTRIENT ? ECOLOGY.nutrient_merge_limit : ECOLOGY.merge_limit;
}

export function nutrientCapacity(
  a: number,
  ac: number,
  b: number,
  bc: number,
  acid: number,
): number {
  const total = a + b;
  const fuel = Math.min(a, Math.max(0, ac)) + Math.min(b, Math.max(0, bc));
  if (fuel < total - 1e-6) {
    return fuel;
  }
  const bonusA = Math.max(0, ac - a);
  const bonusB = Math.max(0, bc - b);
  const acidAffinity = 1.0 + Math.max(0.0, 1.0 - Math.abs(acid - 0.25) / 0.25);
  const pairBonus = Math.min(a, b) * ECOLOGY.nutrient_binding_bonus * acidAffinity;
  const maxBonus = total * ECOLOGY.nutrient_bonus_limit;
  return total + Math.min(maxBonus, bonusA + bonusB + pairBonus);
}

export function bindingThreshold(a: number, b: number, acid: number): number {
  if (
    (a === SPECIES.ENZYME && b === SPECIES.WASTE) ||
    (a === SPECIES.WASTE && b === SPECIES.ENZYME) ||
    (a === SPECIES.NUTRIENT && b === SPECIES.NUTRIENT)
  ) {
    const dev = clamp(Math.abs(acid - 0.25) / 0.25, 0.0, 1.0);
    return 0.5 + 0.46 * dev * dev;
  }
  if ((a === SPECIES.WASTE && b === SPECIES.OXYGEN) || (a === SPECIES.OXYGEN && b === SPECIES.WASTE)) {
    return 0.88;
  }
  return 0.5;
}
