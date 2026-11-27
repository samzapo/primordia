import { TAU, offsetVec, posmod, type Vec2 } from './constants.ts';
import type { Cell, SignalReportEntry } from './cell.ts';

export const BEHAVIOR_DESCRIPTION =
  'Escape harmful acid or an attack first. Use only locally received chemical, light and acidity cues. With low ATP, find food or useful light; rest if food is already digesting. With little biomass, forage or follow prey traces. Hunters with a stored meal and parasites with biomass reserves rest rather than pursuing another kill; otherwise seek food, useful light or explore. Under attack, nearby family traces help the cell spread out. Family receptors can follow relatives or spread away from their received chemical trails; survival needs take priority. Organs determine the senses and movement available.';

export function updateBehaviorLatches(cell: Cell): void {
  const scale = cell.growthScale();
  let lowEnergy = cell.behavior.lowEnergy;
  let lowMass = cell.behavior.lowMass;

  if (cell.energy < 18 * scale) lowEnergy = true;
  else if (cell.energy > 36 * scale) lowEnergy = false;

  if (cell.biomass < Math.max(4, cell.body * 0.1)) lowMass = true;
  else if (cell.biomass > Math.max(8, cell.body * 0.22)) lowMass = false;

  cell.behavior.lowEnergy = lowEnergy;
  cell.behavior.lowMass = lowMass;
}

export function isCellSated(cell: Cell): boolean {
  const syn = cell.synergy();
  if (syn === 'parasite') {
    return cell.biomass >= Math.max(84, cell.body * 0.75);
  }
  return syn === 'hunter' && cell.substrate >= 20 * cell.growthScale() && cell.biomass >= 8;
}

export function isDigesting(cell: Cell): boolean {
  return cell.substrate > Math.max(1, 2 * cell.growthScale());
}

export function behaviorPriority(cell: Cell, mode: string): number {
  switch (mode) {
    case 'acid':
      return 1000;
    case 'evade':
      return 950;
    case 'toxin':
      return 920;
    case 'flee':
      return 900;
    case 'kin_toward':
    case 'kin_away':
      return cell.behavior.lowEnergy || cell.behavior.lowMass ? 100 : 280;
    case 'graze':
      if (cell.behavior.lowEnergy) return 800;
      if (cell.behavior.lowMass) return 600;
      return cell.substrate < 18 * cell.growthScale() ? 300 : 0;
    case 'light':
      return cell.behavior.lowEnergy ? 700 : cell.behavior.lowMass ? 400 : 250;
    case 'hunt':
      if (isCellSated(cell)) return 0;
      if (cell.behavior.lowEnergy) return isDigesting(cell) ? 0 : 350;
      return cell.behavior.lowMass ? 550 : 500;
    default:
      return 0;
  }
}

export function fallbackBehavior(
  cell: Cell,
  seedValue: number,
): { direction: Vec2; state: string } {
  if (isCellSated(cell)) {
    return { direction: { x: 0, y: 0 }, state: 'RESTING · STORED MEAL' };
  }
  if (cell.behavior.lowEnergy && isDigesting(cell)) {
    return { direction: { x: 0, y: 0 }, state: 'RESTING · DIGESTING FOOD' };
  }
  const ticket = (Math.imul(cell.id, 19349663) ^ Math.imul(seedValue, 83492791)) | 0;
  const phase = (TAU * posmod(ticket, 65521)) / 65521.0;
  const heading =
    phase +
    cell.age * 0.045 +
    Math.sin(cell.age * 0.13 + phase) * 0.65 +
    Math.sin(cell.age * 0.37 + phase * 0.7) * 0.35;
  const state = cell.behavior.lowEnergy
    ? 'SEARCHING FOR FOOD'
    : cell.behavior.lowMass
      ? 'SEARCHING FOR FOOD OR PREY'
      : 'EXPLORING';
  return {
    direction: { x: Math.cos(heading), y: Math.sin(heading) },
    state,
  };
}

export function escapeDirection(
  away: Vec2,
  families: Map<number, SignalReportEntry>,
  cell: Cell,
  now: number,
): { direction: Vec2; expiresAt: number } {
  const awayLen = Math.hypot(away.x, away.y) || 1;
  const ax = away.x / awayLen;
  const ay = away.y / awayLen;

  let nearest: SignalReportEntry | null = null;
  for (const detected of families.values()) {
    const r = detected.report;
    if (detected.expiresAt <= now || r.lineage !== cell.lineageId() || r.id === cell.id) continue;
    if (
      !nearest ||
      detected.distance < nearest.distance ||
      (detected.distance === nearest.distance && r.id < nearest.report.id)
    ) {
      nearest = detected;
    }
  }

  if (!nearest) return { direction: { x: ax, y: ay }, expiresAt: Infinity };
  const delta = offsetVec(cell.position, nearest.report.at);
  const dl = Math.hypot(delta.x, delta.y);
  if (dl * dl < 0.0001) return { direction: { x: ax, y: ay }, expiresAt: Infinity };

  const dx = delta.x / dl;
  const dy = delta.y / dl;
  const bx = ax * 2.0 - dx;
  const by = ay * 2.0 - dy;
  const bl = Math.hypot(bx, by) || 1;
  return { direction: { x: bx / bl, y: by / bl }, expiresAt: nearest.expiresAt };
}

export function behaviorSummary(cell: Cell): string {
  if (!cell.state) return 'Exploring';
  return cell.state.charAt(0).toUpperCase() + cell.state.slice(1).toLowerCase();
}
