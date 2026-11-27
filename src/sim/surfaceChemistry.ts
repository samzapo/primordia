import { COMBAT } from './catalog.ts';
import { SPECIES, wrapAngle } from './constants.ts';

export const PORE_REQUIRED = 4;
export const PORE_LIFETIME = 20.0;
export const PORE_REPAIR_COST = 2.0;
export const MAX_SURFACE_COMPLEXES = 64;

export interface SurfaceComplex {
  a: number;
  tag: number;
  units: number;
  material: number;
  capped: boolean;
  age: number;
  repair: number;
  source: number;
}

export interface SurfaceCellLike {
  id: number;
  dead: boolean;
  unattendedProtected: boolean;
  surfaceComplexes: SurfaceComplex[];
  organs: Array<{ id: number; kind: string; hp: number }>;
  synergy(): string;
  workCapacity(required?: number): number;
  spendEnergy(amount: number, organ?: { id: number } | null, category?: string): number;
  damage(amount: number, worldAngle: number, source: number): number;
  acceptsAttack(source: number): boolean;
  deathHint: string;
}

export function surfaceMaterial(cell: SurfaceCellLike): number {
  let total = 0;
  for (const c of cell.surfaceComplexes) total += c.material;
  return total;
}

export function acceptSurfacePacket(
  cell: SurfaceCellLike,
  kind: number,
  amount: number,
  worldAngle: number,
  source: number,
  cellAngle: number,
  onBlocked: () => void,
): boolean {
  if (cell.dead || cell.unattendedProtected) return false;
  if (kind !== SPECIES.ANTITOXIN && !cell.acceptsAttack(source)) return false;

  const localAngle = wrapAngle(worldAngle - cellAngle);
  let target: SurfaceComplex | null = null;
  let best = 0.3;

  for (const c of cell.surfaceComplexes) {
    const d = Math.abs(wrapAngle(c.a - localAngle));
    if (d <= best) {
      best = d;
      target = c;
    }
  }

  if (kind === SPECIES.TAG) {
    if (target) return false;
    if (cell.surfaceComplexes.length >= MAX_SURFACE_COMPLEXES) return false;
    cell.surfaceComplexes.push({
      a: localAngle,
      tag: amount,
      units: 0,
      material: amount,
      capped: false,
      age: 0,
      repair: 0,
      source,
    });
    return true;
  }

  if (kind === SPECIES.PORE) {
    if (!target || target.capped || target.units >= PORE_REQUIRED) return false;
    target.units += 1;
    target.material += amount;
    target.age = 0;
    target.source = source;
    return true;
  }

  if (kind === SPECIES.ANTITOXIN) {
    if (!target || target.capped || target.units >= PORE_REQUIRED) return false;
    target.capped = true;
    target.material += amount;
    target.age = Math.max(target.age, PORE_LIFETIME - 2.5);
    onBlocked();
    return true;
  }

  return false;
}

export function advanceSurfaceComplexes(
  cell: SurfaceCellLike,
  dt: number,
  cellAngle: number,
  onExpire: (amount: number, localAngle: number) => void,
  onKilledByPore: () => void,
): void {
  if (cell.surfaceComplexes.length === 0) return;
  const repairGlands = cell.organs.filter((o) => o.kind === 'regenerative' && o.hp > 0);
  const repair = repairGlands.length;
  const immunity = cell.synergy() === 'hunter';
  const kept: SurfaceComplex[] = [];

  for (const c of cell.surfaceComplexes) {
    c.age += dt;
    if (c.units >= PORE_REQUIRED && !c.capped && !(immunity && c.source === cell.id)) {
      const dmg = COMBAT.pore_damage_per_second * dt;
      cell.damage(dmg, cellAngle + c.a, c.source);
      cell.deathHint = 'Membrane ruptured by pore-forming secretion';
      onKilledByPore();
    }
    if (repair > 0 && c.units >= PORE_REQUIRED && !c.capped) {
      const shares = new Map<number, number>();
      for (const g of repairGlands) shares.set(g.id, 1);
      const spent = cell.spendEnergy(dt * 0.25 * repair * cell.workCapacity(), null, 'repair');
      c.repair += spent * 4.0;
    }
    if (c.age >= PORE_LIFETIME || c.repair >= PORE_REPAIR_COST) {
      onExpire(c.material, c.a);
    } else {
      kept.push(c);
    }
  }

  cell.surfaceComplexes = kept;
}
