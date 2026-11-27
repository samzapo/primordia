import { COMBAT } from './catalog.ts';
import { clamp } from './constants.ts';

export const TOXIN_SAC_CAPACITY = COMBAT.toxin_sac.capacity; // 2.0
export const TOXIN_SAC_FILL_RATE = COMBAT.toxin_sac.fill_rate; // 0.04
export const TOXIN_SAC_ATP_PER_UNIT = COMBAT.toxin_sac.atp_per_unit; // 1.0
export const TOXIN_SAC_BIOMASS_FLOOR = COMBAT.toxin_sac.biomass_floor; // 12.0

export interface ToxinSacOrgan {
  kind: string;
  scale: number;
  hp: number;
  maxHp: number;
  storedToxin: number;
  chargeFlash: number;
  id: number;
  mutation: string;
}

export function toxinSacCapacity(organ: Pick<ToxinSacOrgan, 'scale'>): number {
  return TOXIN_SAC_CAPACITY * organ.scale * organ.scale;
}

export function toxinSacFraction(organ: Pick<ToxinSacOrgan, 'kind' | 'scale' | 'storedToxin'>): number {
  if (organ.kind !== 'toxin_sac') return 0.0;
  return clamp((organ.storedToxin || 0) / Math.max(1e-6, toxinSacCapacity(organ)), 0, 1);
}

export function fillToxinSacs(
  cell: {
    biomass: number;
    energy: number;
    organs: ToxinSacOrgan[];
    workCapacity(required?: number): number;
    spendEnergy(amount: number, organ: ToxinSacOrgan, category: string): number;
    spendWork(dt: number, organ: ToxinSacOrgan, category: string): number;
  },
  dt: number,
): void {
  for (const organ of cell.organs) {
    if (organ.kind !== 'toxin_sac' || organ.hp <= 0) continue;
    const maxCap = toxinSacCapacity(organ);
    const room = Math.max(0, maxCap - organ.storedToxin);
    const surplus = Math.max(0, cell.biomass - TOXIN_SAC_BIOMASS_FLOOR);
    if (room <= 1e-8 || surplus <= 1e-8) continue;

    const rate = TOXIN_SAC_FILL_RATE * organ.scale * organ.scale;
    const capacity = cell.workCapacity(rate * dt * TOXIN_SAC_ATP_PER_UNIT);
    const wanted = Math.min(room, surplus, rate * dt * capacity);
    if (wanted <= 1e-8) continue;

    const affordable = Math.min(wanted, Math.max(0, cell.energy / TOXIN_SAC_ATP_PER_UNIT));
    if (affordable <= 1e-8) continue;

    const spent = cell.spendEnergy(affordable * TOXIN_SAC_ATP_PER_UNIT, organ, 'secretion');
    const added = Math.min(affordable, spent / TOXIN_SAC_ATP_PER_UNIT);
    if (added <= 1e-8) continue;

    cell.biomass -= added;
    organ.storedToxin += added;
    cell.spendWork((dt * added) / Math.max(1e-8, rate), organ, 'secretion');
    organ.chargeFlash = Math.min(1.0, organ.chargeFlash + 0.5);
  }
}
