import { clamp, offsetVec, type Vec2 } from './constants.ts';
import type { Cell, Organ } from './cell.ts';
import { isCellSated } from './cellBehavior.ts';
import { TISSUE_FUEL } from './cellChemistry.ts';

export const PROBOSCIS_RATE = 2.0;
export const PROBOSCIS_TOUCH_TOL = 6.0;

export function proboscisReach(cell: Cell, organ: Organ): number {
  const lp = cell.organLocalPosition(organ);
  const n = cell.organNormal(organ);
  const dot = lp.x * n.x + lp.y * n.y;
  return Math.max(27.0 * organ.scale, cell.extent() - dot + 8.0 * organ.scale);
}

export function proboscisTip(cell: Cell, organ: Organ): Vec2 {
  const base = cell.organPosition(organ);
  const n = cell.organNormal(organ);
  const c = Math.cos(cell.angle);
  const s = Math.sin(cell.angle);
  const nx = n.x * c - n.y * s;
  const ny = n.x * s + n.y * c;
  const reach = proboscisReach(cell, organ);
  return { x: base.x + nx * reach, y: base.y + ny * reach };
}

function pointInPolygon(px: number, py: number, poly: Vec2[]): boolean {
  let inside = false;
  for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    const xi = poly[i].x;
    const yi = poly[i].y;
    const xj = poly[j].x;
    const yj = poly[j].y;
    if (yi > py !== yj > py && px < ((xj - xi) * (py - yi)) / (yj - yi + 1e-12) + xi) {
      inside = !inside;
    }
  }
  return inside;
}

export function proboscisTouches(donor: Cell, tip: Vec2, tolerance: number): boolean {
  const delta = offsetVec(donor.position, tip);
  const maxR = donor.extent() + tolerance;
  if (delta.x * delta.x + delta.y * delta.y > maxR * maxR) return false;
  const c = Math.cos(-donor.angle);
  const s = Math.sin(-donor.angle);
  const lx = delta.x * c - delta.y * s;
  const ly = delta.x * s + delta.y * c;
  const outline = donor.membrane.outline();
  if (pointInPolygon(lx, ly, outline)) return true;

  const tolSq = tolerance * tolerance;
  for (let i = 0; i < outline.length; i++) {
    const a = outline[i];
    const b = outline[(i + 1) % outline.length];
    const ex = b.x - a.x;
    const ey = b.y - a.y;
    const lenSq = Math.max(ex * ex + ey * ey, 1e-8);
    const t = clamp(((lx - a.x) * ex + (ly - a.y) * ey) / lenSq, 0, 1);
    const cx = a.x + ex * t;
    const cy = a.y + ey * t;
    if ((lx - cx) * (lx - cx) + (ly - cy) * (ly - cy) <= tolSq) return true;
  }
  return false;
}

export interface ProboscisContactVisual {
  feederId: number;
  organId: number;
  donorId: number;
  amount: number;
  at: Vec2;
  tip: Vec2;
}

export function stepProboscis(
  cell: Cell,
  cells: Cell[],
  dt: number,
  outContacts: ProboscisContactVisual[],
): void {
  const sated = isCellSated(cell);
  for (const organ of cell.organs) {
    if (organ.kind !== 'proboscis') continue;
    organ.feeding = false;
    if (organ.hp <= 0 || sated) continue;
    const room = Math.max(0, cell.gutCapacity() - cell.substrate);
    if (room <= 1e-6) continue;

    const tip = proboscisTip(cell, organ);
    const tol = PROBOSCIS_TOUCH_TOL * organ.scale;
    let bestDonor: Cell | null = null;
    let bestDistSq = Infinity;

    for (const donor of cells) {
      if (
        donor === cell ||
        donor.dead ||
        donor.health <= 0 ||
        donor.unattendedProtected ||
        donor.biomass <= 1e-6 ||
        !donor.acceptsAttack(cell.id)
      ) {
        continue;
      }
      if (!proboscisTouches(donor, tip, tol)) continue;
      const d = offsetVec(donor.position, tip);
      const dSq = d.x * d.x + d.y * d.y;
      if (dSq < bestDistSq) {
        bestDistSq = dSq;
        bestDonor = donor;
      }
    }

    if (!bestDonor) continue;

    const cap = cell.workCapacity();
    const health = organ.maxHp > 0 ? organ.hp / organ.maxHp : 1;
    const maxExtract = Math.min(
      bestDonor.biomass,
      room,
      PROBOSCIS_RATE * organ.scale * organ.scale * health * dt * cap,
    );
    const unitCost = 0.5 + (0.35 * organ.scale * organ.scale) / (2.0 * organ.scale * organ.scale);
    const affordable = Math.min(
      maxExtract,
      Math.max(0, (cell.energy + cell.biomass * 40.0) / Math.max(1e-6, unitCost)),
    );
    if (affordable <= 1e-7) continue;

    bestDonor.biomass -= affordable;
    cell.spendEnergy(affordable * unitCost, organ, 'feeding');
    const localIn = cell.organLocalPosition(organ);
    cell.chemistry.emit(
      cell,
      'food',
      affordable,
      { x: localIn.x * 0.72, y: localIn.y * 0.72 },
      bestDonor.id,
      -1,
      affordable * TISSUE_FUEL,
      0,
    );
    cell.chemistry.syncCell(cell);
    bestDonor.updateGeometry();
    cell.updateGeometry();
    organ.feeding = true;
    organ.consumeFlash = 1.0;

    outContacts.push({
      feederId: cell.id,
      organId: organ.id,
      donorId: bestDonor.id,
      amount: affordable,
      at: cell.organPosition(organ),
      tip,
    });
  }
}
