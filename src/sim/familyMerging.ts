import { MAX_FAMILY_CELLS, SPECIES, offsetVec, type Vec2 } from './constants.ts';
import type { Cell } from './cell.ts';
import type { Lineage } from './lineage.ts';
import { retireInvestment, type InvestmentState } from './investmentPolicy.ts';
import { surfaceMaterial } from './surfaceChemistry.ts';

export const MERGE_MIN_AGE = 60.0;
export const MERGE_COOLDOWN = 120.0;
export const MERGE_RECENT_SECONDS = 5.0;
export const MERGE_MAX_RECENT = 64;

export interface MergeBurst {
  serial: number;
  time: number;
  donorId: number;
  receiverId: number;
  at: Vec2;
  to: Vec2;
  reason: 'manual' | 'capacity';
  donorRadius: number;
  donorAngle: number;
  donorOutline: Vec2[];
  donorLineage: number;
  donorSynergy: string;
}

export interface MergeSim {
  time: number;
  player: Cell;
  cells: Cell[];
  managedCells: Set<number>;
  investment: InvestmentState;
  mergeSerial: number;
  mergeBursts: MergeBurst[];
  familyLedger(cell: Cell): Lineage;
  recycleFor(cell: Cell, index: number): boolean;
  spawnParticle(kind: number, pos: Vec2, vel: Vec2, amount: number, owner: number): void;
  flushReserveProducts(cell: Cell, force: boolean): void;
}

export function isCellManaged(sim: Pick<MergeSim, 'managedCells' | 'player'>, cell: Cell): boolean {
  return sim.managedCells.has(cell.id) || cell === sim.player;
}

export function isMergeEligible(sim: MergeSim, receiver: Cell, donor: Cell): boolean {
  return (
    receiver !== donor &&
    !receiver.dead &&
    receiver.health > 0 &&
    !donor.dead &&
    donor.health > 0 &&
    receiver.lineageId() === donor.lineageId() &&
    !isCellManaged(sim, donor) &&
    !donor.unattendedProtected
  );
}

export function rememberMergeCues(
  sim: { time: number },
  receiver: Cell,
  received: Map<number, { report: { id: number; lineage: number; at: Vec2; mass: number; radius: number; hostile: boolean; defended: boolean; emittedAt: number }; expiresAt: number; distance: number }>,
): void {
  const memory = receiver.behavior.mergeCues;
  for (const [id, entry] of memory) {
    if (entry.expiresAt <= sim.time) memory.delete(id);
  }
  for (const [id, cue] of received) {
    const r = cue.report;
    if (cue.expiresAt <= sim.time || r.id !== id || id === receiver.id || r.lineage !== receiver.lineageId()) {
      continue;
    }
    memory.set(id, {
      report: { ...r, at: { ...r.at } },
      distance: cue.distance,
      expiresAt: sim.time + MERGE_RECENT_SECONDS,
    });
  }
  while (memory.size > MERGE_MAX_RECENT) {
    let oldestId = -1;
    let oldestTime = Infinity;
    for (const [id, entry] of memory) {
      if (entry.report.emittedAt < oldestTime) {
        oldestTime = entry.report.emittedAt;
        oldestId = id;
      }
    }
    if (oldestId >= 0) memory.delete(oldestId);
    else break;
  }
}

export function mergeCue(sim: { time: number }, receiver: Cell, donorId: number) {
  for (const signals of [receiver.behavior.mergeCues, receiver.behavior.familyCues]) {
    const item = signals.get(donorId);
    if (
      item &&
      item.expiresAt > sim.time &&
      item.report.id === donorId &&
      item.report.lineage === receiver.lineageId()
    ) {
      return item;
    }
  }
  return null;
}

export function isMergeDetected(sim: { time: number }, receiver: Cell, donorId: number): boolean {
  if (!mergeCue(sim, receiver, donorId)) return false;
  return receiver.organs.some(
    (o) =>
      o.hp > 0 &&
      (o.kind === 'feeding' ||
        o.kind === 'hunting' ||
        o.kind === 'sensing' ||
        o.kind === 'counterattack' ||
        o.kind === 'family_toward' ||
        o.kind === 'family_away'),
  );
}

export function mergeCandidates(sim: MergeSim, receiver: Cell): Map<number, number> {
  const result = new Map<number, number>();
  for (const donor of sim.cells) {
    if (isMergeEligible(sim, receiver, donor) && isMergeDetected(sim, receiver, donor.id)) {
      const cue = mergeCue(sim, receiver, donor.id)!;
      result.set(donor.id, cue.expiresAt);
    }
  }
  return result;
}

export function mergeNeighborhood(receiver: Cell): number {
  let reach = 90.0;
  for (const o of receiver.organs) {
    if (
      o.hp > 0 &&
      (o.kind === 'feeding' ||
        o.kind === 'hunting' ||
        o.kind === 'sensing' ||
        o.kind === 'counterattack' ||
        o.kind === 'family_toward' ||
        o.kind === 'family_away')
    ) {
      const base = o.kind === 'hunting' ? 120.0 : 90.0;
      reach = Math.max(reach, base * Math.sqrt(o.scale) * receiver.sensoryOutput(o, true));
    }
  }
  return Math.max(receiver.extent() * 3.0, receiver.extent() + reach + 32.0);
}

export function livingFamilies(cells: Cell[]): Map<number, Cell[]> {
  const families = new Map<number, Cell[]>();
  for (const cell of cells) {
    if (cell.dead || cell.health <= 0) continue;
    const root = cell.lineageId();
    let list = families.get(root);
    if (!list) {
      list = [];
      families.set(root, list);
    }
    list.push(cell);
  }
  return families;
}

function isOlderCell(a: Cell, b: Cell): boolean {
  if (a.generation !== b.generation) return a.generation < b.generation;
  if (a.age !== b.age) return a.age > b.age;
  return a.id < b.id;
}

export function touchingCells(a: Cell, b: Cell): boolean {
  const d = offsetVec(a.position, b.position);
  const dist = Math.hypot(d.x, d.y);
  const angle = Math.atan2(d.y, d.x);
  return dist <= a.support(angle) + b.support(angle + Math.PI) + 8.0;
}

export function commitMerge(
  sim: MergeSim,
  receiver: Cell,
  donor: Cell,
  fromSelection = false,
  forCapacity = false,
): boolean {
  if (!isMergeEligible(sim, receiver, donor)) return false;
  if (forCapacity) {
    const fam = livingFamilies(sim.cells).get(receiver.lineageId()) ?? [];
    if (!isOlderCell(receiver, donor) || fam.length <= MAX_FAMILY_CELLS) return false;
  } else {
    if (!isMergeDetected(sim, receiver, donor.id)) return false;
    if (!fromSelection && !touchingCells(receiver, donor)) return false;
  }

  const donorOutline = donor.membrane.outline().map((p) => ({ ...p }));
  const donorRadius = donor.radius;
  const donorAngle = donor.angle;
  const donorLineage = donor.lineageId();
  const donorSynergy = donor.synergy();

  sim.flushReserveProducts(donor, true);
  const ledger = sim.familyLedger(donor);

  for (let i = donor.organs.length - 1; i >= 0; i--) {
    if (!sim.recycleFor(donor, i)) return false;
  }

  const solids = donor.body + donor.biomass + surfaceMaterial(donor);
  receiver.biomass += solids * 0.9;
  if (solids > 0) {
    sim.spawnParticle(SPECIES.WASTE, receiver.excretionPosition(), { x: 0, y: 0 }, solids * 0.1, receiver.id);
  }
  const available = donor.energy;
  receiver.energy += available * 0.9;
  receiver.chemistry.heat += available * 0.1;

  // Transfer intracellular packets
  const compMap = new Map<number, number>();
  const dc = Math.cos(donor.angle);
  const ds = Math.sin(donor.angle);
  const rc = Math.cos(-receiver.angle);
  const rs = Math.sin(-receiver.angle);

  for (const packet of donor.chemistry.particles) {
    if (!packet.alive) continue;
    const wx = donor.position.x + packet.p.x * dc - packet.p.y * ds;
    const wy = donor.position.y + packet.p.x * ds + packet.p.y * dc;
    const off = offsetVec(receiver.position, { x: wx, y: wy });
    const lx = off.x * rc - off.y * rs;
    const ly = off.x * rs + off.y * rc;
    const nutrition = packet.nutrition / Math.max(1e-9, packet.amount);
    let targetComp = compMap.get(packet.compartment);
    if (targetComp === undefined) {
      targetComp = receiver.chemistry.nextCompartment++;
      compMap.set(packet.compartment, targetComp);
    }
    receiver.chemistry.emit(
      receiver,
      packet.species,
      packet.amount,
      { x: lx, y: ly },
      packet.source,
      targetComp,
      packet.fuel,
      nutrition,
    );
  }

  receiver.mergeAfter = sim.time + MERGE_COOLDOWN;
  receiver.updateGeometry();
  receiver.renderRevision++;

  sim.mergeSerial++;
  sim.mergeBursts.push({
    serial: sim.mergeSerial,
    time: sim.time,
    donorId: donor.id,
    receiverId: receiver.id,
    at: { ...donor.position },
    to: { ...receiver.position },
    reason: forCapacity ? 'capacity' : 'manual',
    donorRadius,
    donorAngle,
    donorOutline,
    donorLineage,
    donorSynergy,
  });
  if (sim.mergeBursts.length > 32) sim.mergeBursts.shift();

  donor.dead = true;
  donor.energy = 0;
  donor.chemistry.particles.length = 0;
  donor.chemistry.refresh();
  const cIdx = sim.cells.indexOf(donor);
  if (cIdx >= 0) sim.cells.splice(cIdx, 1);
  const rec = ledger.recordFor(donor.id);
  if (rec) {
    const rIdx = ledger.records.indexOf(rec);
    if (rIdx >= 0) ledger.records.splice(rIdx, 1);
  }
  retireInvestment(sim.investment, donor);
  ledger.notify('Family cells merged. Organelles reabsorbed; resources combined.');
  return true;
}

export function enforceFamilyLimit(sim: MergeSim): void {
  const families = livingFamilies(sim.cells);
  for (const family of families.values()) {
    if (family.length <= MAX_FAMILY_CELLS) continue;
    family.sort((a, b) => (isOlderCell(a, b) ? -1 : isOlderCell(b, a) ? 1 : 0));
    const donors = family.slice().reverse();
    for (const donor of donors) {
      if (family.length <= MAX_FAMILY_CELLS) break;
      if (isCellManaged(sim, donor)) continue;
      const record = sim.familyLedger(donor).recordFor(donor.id);
      let receiver: Cell | null = null;
      for (const rel of family) {
        if (rel === donor || !isOlderCell(rel, donor)) continue;
        if (!receiver) receiver = rel;
        if (record && rel.id === record.parent) {
          receiver = rel;
          break;
        }
      }
      if (receiver && commitMerge(sim, receiver, donor, false, true)) {
        const idx = family.indexOf(donor);
        if (idx >= 0) family.splice(idx, 1);
      }
    }
  }
}

export function requestFamilyMerge(sim: MergeSim, donorId: number): boolean {
  const receiver = sim.player;
  const donor = sim.cells.find((c) => c.id === donorId);
  if (!donor) return false;
  return commitMerge(sim, receiver, donor, true, false);
}
