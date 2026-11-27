import { MAX_FAMILY_CELLS, MAX_LIVE_CELLS, SPECIES, clamp, type Vec2 } from './constants.ts';
import { Cell } from './cell.ts';
import { FOOD_FUEL, TISSUE_FUEL } from './cellChemistry.ts';
import { enforceFamilyLimit, isCellManaged, type MergeSim } from './familyMerging.ts';
import { inheritInvestmentStrategy } from './investmentPolicy.ts';
import type { Lineage } from './lineage.ts';
import type { SeededRng } from './rng.ts';

export const LIFECYCLE_PERIOD = 1.0;
export const REPRODUCTION_COOLDOWN = 60.0;
export const VENT_BIOMASS = 500.0;
export const VENT_RATE = 0.01;
export const VENT_NUTRIENT_SHARE = 0.7;

export interface DivisionQuote {
  cell: number;
  mode: 'mitosis' | 'budding';
  ready: boolean;
  progress: number;
  automatic: boolean;
  automaticBudding: boolean;
  reason: string;
  cooldown: number;
  material: number;
  energy: number;
  donation: number;
  childBiomass: number;
  childAtp: number;
}

export interface LifecycleSim extends MergeSim {
  nextId: number;
  seedValue: number;
  automaticReproduction: boolean;
  lifecycleDue: number;
  ecologyRng: SeededRng;
  autolysisAfter: Map<number, number>;
  externalInput: number;
  events: Array<Record<string, unknown>>;
  birthPosition(parent: Cell, child: Cell): Vec2;
  recordSound(kind: string, at: Vec2, source: number): void;
  spawnNutrientWithCapacity(pos: Vec2, vel: Vec2, amount: number, owner: number, capacity: number): void;
}

export function populationCensus(cells: Cell[]): { living: number; families: Map<number, number> } {
  let living = 0;
  const families = new Map<number, number>();
  for (const c of cells) {
    if (c.dead || c.health <= 0) continue;
    living++;
    const root = c.lineageId();
    families.set(root, (families.get(root) ?? 0) + 1);
  }
  return { living, families };
}

export function divisionQuote(
  sim: { time: number; cells: Cell[] },
  parent: Cell,
  mode: 'mitosis' | 'budding',
  census?: { living: number; families: Map<number, number> },
): DivisionQuote {
  const cooldown = Math.max(0, parent.reproductionRetryAt - sim.time);
  const material = mode === 'mitosis' ? 84.0 : 50.0;
  const energy = mode === 'mitosis' ? 56.0 : 78.0;
  const donation = mode === 'mitosis' ? parent.biomass * 0.5 : 42.0;
  const childBiomass = donation - 30.0;
  const childAtp = mode === 'mitosis' ? (parent.energy - 20.0) * 0.5 : 40.0;
  const progress = Math.min(
    clamp(parent.biomass / material, 0, 1),
    clamp(parent.energy / energy, 0, 1),
    clamp(1.0 - cooldown / REPRODUCTION_COOLDOWN, 0, 1),
  );

  const c = census ?? populationCensus(sim.cells);
  const famCount = c.families.get(parent.lineageId()) ?? 0;
  const label = mode === 'mitosis' ? 'Mitosis' : 'Budding';

  let ready = false;
  let reason = '';
  if (parent.dead || parent.health <= 0) {
    reason = 'Only a living cell can reproduce.';
  } else if (cooldown > 0) {
    reason = `Resting: ${Math.ceil(cooldown)}s until reproduction.`;
  } else if (famCount >= MAX_FAMILY_CELLS) {
    reason = `Family full: ${MAX_FAMILY_CELLS} living cells. Division waits for room.`;
  } else if (c.living >= MAX_LIVE_CELLS) {
    reason = `Pond full: ${MAX_LIVE_CELLS} living cells. Division waits for room.`;
  } else if (
    parent.working('feeding') === 0 &&
    parent.working('photosynthesis') === 0 &&
    parent.working('proboscis') === 0
  ) {
    reason = 'Build an oral groove, proboscis or leaf first.';
  } else if (parent.biomass < material || parent.energy < energy) {
    reason = `${label} needs ${material.toFixed(0)} biomass and ${energy.toFixed(0)} ATP, including survival reserves.`;
  } else {
    ready = true;
    reason = `${label} ready. No clear water is required.`;
  }

  return {
    cell: parent.id,
    mode,
    ready,
    progress,
    automatic: parent.automaticDivision,
    automaticBudding: parent.automaticBudding,
    reason,
    cooldown,
    material,
    energy,
    donation,
    childBiomass,
    childAtp,
  };
}

export function reproduceCell(
  sim: LifecycleSim,
  parent: Cell,
  ledger: Lineage,
  mode: 'mitosis' | 'budding',
  follow = false,
): boolean {
  const q = divisionQuote(sim, parent, mode);
  if (!q.ready) return false;

  const childId = sim.nextId++;
  const child = new Cell(
    childId,
    parent.position,
    Math.abs((sim.seedValue * 1000003 + childId * 9176) | 0),
  );
  child.body = 30.0;
  child.biomass = q.childBiomass;
  child.energy = q.childAtp;
  child.role = 'descendant';
  child.generation = parent.generation + 1;
  child.lineage = parent.lineageId();
  child.addOrgan('feeding', 0, 'graze', false);
  child.addOrgan('photosynthesis', Math.PI, 'graze', false);
  child.automaticDivision = parent.automaticDivision;
  child.automaticBudding = parent.automaticBudding;
  child.reproductionRetryAt = sim.time + REPRODUCTION_COOLDOWN;
  parent.reproductionRetryAt = sim.time + REPRODUCTION_COOLDOWN;

  child.position = sim.birthPosition(parent, child);
  child.previousPosition = { ...child.position };
  child.angle = parent.angle;
  child.previousAngle = child.angle;

  child.chemistry.partition(parent.chemistry, mode === 'mitosis' ? 0.5 : 0.25);
  parent.biomass -= q.donation;
  parent.spendEnergy(20.0 + q.childAtp, null, 'reproduction');
  parent.updateGeometry();
  child.updateGeometry();
  parent.renderRevision++;
  sim.externalInput += 20.0;

  inheritInvestmentStrategy(sim.investment, parent, child);
  ledger.births++;
  ledger.register(child, parent.id, child.generation, 'living', sim.time);
  if (ledger.progression) {
    ledger.progression.divided();
  }

  sim.cells.push(child);
  sim.recordSound('division', parent.position, parent.id);
  sim.events.push({ type: 'division', id: child.id, parent: parent.id, mode, time: sim.time });
  if (sim.events.length > 128) sim.events.shift();

  if (follow) {
    ledger.adopted(child, sim);
  }
  const label = mode === 'mitosis' ? 'Mitosis' : 'Budding';
  ledger.notify(`${label}: a daughter joined the family.`);
  return true;
}

function checkCrowding(sim: LifecycleSim, cell: Cell): void {
  if (cell.unattendedProtected || isCellManaged(sim, cell) || cell.behavior.autolysisAt >= 0) {
    return;
  }
  const reports = new Set<number>();
  for (const collection of [cell.behavior.familyCues, cell.behavior.mergeCues]) {
    for (const [id, cue] of collection) {
      if (cue.expiresAt > sim.time && id !== cell.id && cue.report.id === id && cue.report.lineage === cell.lineageId()) {
        reports.add(id);
      }
    }
  }
  if (reports.size <= 6) {
    cell.behavior.crowdedSince = -1;
    return;
  }
  if (cell.behavior.crowdedSince < 0) cell.behavior.crowdedSince = sim.time;
  if (sim.time - cell.behavior.crowdedSince < 10.0 || sim.time < cell.behavior.autolysisCheck) {
    return;
  }
  const due = cell.behavior.autolysisCheck > 0 ? cell.behavior.autolysisCheck : cell.behavior.crowdedSince + 10.0;
  cell.behavior.autolysisCheck = due + Math.floor((sim.time - due) / 5.0 + 1) * 5.0;
  const key = cell.lineageId();
  if (sim.time < (sim.autolysisAfter.get(key) ?? 0)) return;
  if (sim.ecologyRng.randf() < Math.min(0.01, 0.002 * (reports.size - 6))) {
    cell.behavior.autolysisAt = sim.time + 3.0;
    sim.autolysisAfter.set(key, sim.time + 60.0);
  }
}

export function stepLifecycle(sim: LifecycleSim): void {
  if (sim.time < sim.lifecycleDue) return;
  enforceFamilyLimit(sim);
  sim.lifecycleDue += Math.floor((sim.time - sim.lifecycleDue) / LIFECYCLE_PERIOD + 1) * LIFECYCLE_PERIOD;

  const census = populationCensus(sim.cells);
  for (const cell of sim.cells.slice()) {
    if (cell.dead || cell.health <= 0) continue;
    checkCrowding(sim, cell);
    if (!sim.automaticReproduction || sim.time < cell.reproductionRetryAt) continue;

    const hostile =
      cell.behavior.weaponCue !== null ||
      cell.threat.x * cell.threat.x + cell.threat.y * cell.threat.y > 0.01;
    const mode: 'mitosis' | 'budding' =
      hostile && cell.automaticBudding
        ? 'budding'
        : cell.automaticDivision
          ? 'mitosis'
          : 'budding';
    if ((mode === 'budding' && !cell.automaticBudding) || (mode === 'mitosis' && !cell.automaticDivision)) {
      continue;
    }
    if (!divisionQuote(sim, cell, mode, census).ready) continue;
    const prob = hostile ? 0.1 : 0.05;
    if (sim.ecologyRng.randf() < prob && reproduceCell(sim, cell, sim.familyLedger(cell), mode, false)) {
      census.living++;
      census.families.set(cell.lineageId(), (census.families.get(cell.lineageId()) ?? 0) + 1);
    }
  }
}

export function stepLifecyclePhysiology(sim: LifecycleSim, cell: Cell, dt: number): void {
  if (cell.unattendedProtected) {
    cell.behavior.autolysisAt = -1;
  } else if (cell.behavior.autolysisAt >= 0 && sim.time >= cell.behavior.autolysisAt) {
    cell.health = 0;
    cell.deathHint = 'Crowding autolysis';
    return;
  }

  const surplus = Math.max(0, cell.biomass - VENT_BIOMASS);
  if (cell.unattendedProtected || surplus <= 0) {
    cell.behavior.stress = false;
    cell.behavior.leakElapsed = 0;
    cell.holes = cell.holes.filter((h) => !h.stress);
    return;
  }

  cell.behavior.stress = true;
  if (!cell.holes.some((h) => h.stress)) {
    cell.holes.push({ a: Math.PI, size: 0.15, stress: true });
  }
  cell.behavior.leakElapsed += dt;
  if (cell.behavior.leakElapsed < 0.5) return;

  const elapsed = cell.behavior.leakElapsed;
  cell.behavior.leakElapsed = 0;
  const amount = surplus * (1.0 - Math.exp(-VENT_RATE * elapsed));
  if (amount <= 0) return;

  cell.biomass -= amount;
  const ln = cell.localNormal(Math.PI);
  const c = Math.cos(cell.angle);
  const s = Math.sin(cell.angle);
  const nx = ln.x * c - ln.y * s;
  const ny = ln.x * s + ln.y * c;
  const lp = cell.localPoint(Math.PI);
  const wx = cell.position.x + lp.x * c - lp.y * s + nx * 12;
  const wy = cell.position.y + lp.x * s + lp.y * c + ny * 12;

  const nutrients = amount * VENT_NUTRIENT_SHARE;
  const waste = amount - nutrients;
  const cap = Math.min(nutrients, (amount * TISSUE_FUEL) / FOOD_FUEL);
  sim.spawnNutrientWithCapacity(
    { x: wx, y: wy },
    { x: cell.velocity.x + nx * 18, y: cell.velocity.y + ny * 18 },
    nutrients,
    cell.id,
    cap,
  );
  sim.spawnParticle(
    SPECIES.WASTE,
    { x: wx + nx * 3, y: wy + ny * 3 },
    { x: cell.velocity.x + nx * 14, y: cell.velocity.y + ny * 14 },
    waste,
    cell.id,
  );
  cell.updateGeometry();
}
