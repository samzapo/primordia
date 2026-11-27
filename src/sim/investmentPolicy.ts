import { TAU, posmod } from './constants.ts';
import type { Cell, OrganKind } from './cell.ts';
import { isOffensiveKind, isReceptorKind, organUpkeepEstimate } from './cell.ts';
import type { Evolution } from './evolution.ts';

export const INVESTMENT_STRATEGIES = [
  'manual',
  'balanced',
  'hunter',
  'parasite',
  'producer',
  'grazer',
  'custom',
] as const;

export type InvestmentStrategy = (typeof INVESTMENT_STRATEGIES)[number];
export type RoleName = 'hunter' | 'parasite' | 'grazer' | 'producer';

export const MIX: Record<RoleName, number> = {
  hunter: 2,
  parasite: 4,
  grazer: 10,
  producer: 20,
};
export const MIX_TOTAL = 36;
export const OPERATING_BIOMASS = 12.0;

export const ROLE_VARIANTS: Record<RoleName, [OrganKind[], OrganKind[]]> = {
  hunter: [
    [
      'hunting',
      'propulsion',
      'feeding',
      'poreforming',
      'toxin',
      'sensing',
      'protection',
      'mitochondrion',
      'regenerative',
    ],
    [
      'hunting',
      'propulsion',
      'feeding',
      'poreforming',
      'cilia',
      'counterattack',
      'protection',
      'neutralizing',
      'mitochondrion',
      'regenerative',
      'toxin_sac',
      'family_toward',
    ],
  ],
  parasite: [
    [
      'hunting',
      'sensing',
      'propulsion',
      'proboscis',
      'mitochondrion',
      'regenerative',
      'protection',
      'family_away',
    ],
    [
      'hunting',
      'sensing',
      'propulsion',
      'proboscis',
      'neutralizing',
      'mitochondrion',
      'protection',
      'regenerative',
      'toxin_sac',
    ],
  ],
  producer: [
    [
      'photosynthesis',
      'protection',
      'regenerative',
      'mitochondrion',
      'neutralizing',
      'cilia',
      'sensing',
      'family_away',
      'toxin_sac',
    ],
    [
      'photosynthesis',
      'cilia',
      'neutralizing',
      'mitochondrion',
      'regenerative',
      'protection',
      'sensing',
      'family_toward',
      'toxin_sac',
    ],
  ],
  grazer: [
    [
      'cilia',
      'mitochondrion',
      'regenerative',
      'sensing',
      'feeding',
      'protection',
      'neutralizing',
      'family_toward',
    ],
    [
      'cilia',
      'neutralizing',
      'regenerative',
      'acidifying',
      'mitochondrion',
      'feeding',
      'sensing',
      'protection',
      'family_away',
    ],
  ],
};

export interface TemplatePart {
  kind: OrganKind;
  scale: number;
  mutation: string;
}

export interface InvestmentState {
  lineages: Map<number, InvestmentStrategy>;
  cells: Map<number, InvestmentStrategy>;
  templates: Map<number, TemplatePart[]>;
  cellTemplates: Map<number, Map<number, TemplatePart[]>>;
  completedTemplates: Map<number, string>;
}

export function createInvestmentState(): InvestmentState {
  return {
    lineages: new Map(),
    cells: new Map(),
    templates: new Map(),
    cellTemplates: new Map(),
    completedTemplates: new Map(),
  };
}

export type BuildDecision =
  | { action: 'remove'; id: number }
  | { action: 'adapt'; id: number; gene: string }
  | { action: 'install'; kind: OrganKind; mutation?: string }
  | null;

export interface InvestmentSim {
  seedValue: number;
  player: Cell;
  cells: Cell[];
  automaticReproduction: boolean;
  managedCells: Set<number>;
  investment: InvestmentState;
  lightAt(at: { x: number; y: number }): number;
  divisionQuote(cell: Cell, mode: 'mitosis' | 'budding'): { material: number; energy: number };
}

export function pathAtTicket(ticket: number): RoleName {
  let slot = posmod(ticket, MIX_TOTAL);
  for (const role of ['hunter', 'parasite', 'grazer', 'producer'] as RoleName[]) {
    if (slot < MIX[role]) return role;
    slot -= MIX[role];
  }
  return 'producer';
}

export function balancedPath(seedValue: number, cell: Cell): RoleName {
  const ticket = (Math.imul(cell.id, 19349663) ^ Math.imul(seedValue, 83492791)) | 0;
  return pathAtTicket(ticket);
}

export function rawStrategyForCell(state: InvestmentState, cell: Cell): InvestmentStrategy {
  return state.cells.get(cell.id) ?? state.lineages.get(cell.lineageId()) ?? 'balanced';
}

export function resolvedStrategyForCell(
  seedValue: number,
  state: InvestmentState,
  cell: Cell,
): InvestmentStrategy {
  const chosen = rawStrategyForCell(state, cell);
  return chosen === 'balanced' ? balancedPath(seedValue, cell) : chosen;
}

export function inheritInvestmentStrategy(state: InvestmentState, parent: Cell, child: Cell): void {
  const parentExplicit = state.cells.get(parent.id);
  if (parentExplicit) {
    state.cells.set(child.id, parentExplicit);
  }
  const root = parent.lineageId();
  const rootTemplates = state.cellTemplates.get(root);
  const parentTemplate = rootTemplates?.get(parent.id);
  if (parentTemplate && rootTemplates) {
    rootTemplates.set(
      child.id,
      parentTemplate.map((p) => ({ ...p })),
    );
  }
}

export function retireInvestment(state: InvestmentState, cell: Cell): void {
  state.cells.delete(cell.id);
  state.completedTemplates.delete(cell.id);
  const root = cell.lineageId();
  const map = state.cellTemplates.get(root);
  if (map) {
    map.delete(cell.id);
    if (map.size === 0) state.cellTemplates.delete(root);
  }
}

function workingCount(cell: Cell, kind: OrganKind): number {
  return cell.working(kind);
}

function hunterWeaponCount(cell: Cell): number {
  return (
    workingCount(cell, 'poreforming') +
    workingCount(cell, 'toxin') +
    workingCount(cell, 'counterattack')
  );
}

function anyWeaponWorking(cell: Cell): number {
  return hunterWeaponCount(cell) + workingCount(cell, 'proboscis');
}

function synergyBlocker(cell: Cell, policy: RoleName): BuildDecision {
  if (cell.unattendedProtected) return null;
  for (const organ of cell.organs) {
    if (
      policy === 'parasite' &&
      (organ.kind === 'feeding' ||
        organ.kind === 'photosynthesis' ||
        organ.kind === 'poreforming' ||
        organ.kind === 'toxin' ||
        organ.kind === 'counterattack' ||
        organ.kind === 'acidifying')
    ) {
      return { action: 'remove', id: organ.id };
    }
    if (
      ((policy === 'hunter' || policy === 'grazer') && organ.kind === 'photosynthesis') ||
      ((policy === 'producer' || policy === 'grazer') &&
        (isOffensiveKind(organ.kind) && organ.kind !== 'acidifying' || organ.kind === 'counterattack')) ||
      (policy === 'producer' && organ.kind === 'feeding')
    ) {
      return { action: 'remove', id: organ.id };
    }
  }
  return null;
}

function missingSynergyPart(cell: Cell, policy: RoleName): OrganKind | '' {
  if (policy === 'hunter') {
    if (workingCount(cell, 'hunting') === 0) return 'hunting';
    if (workingCount(cell, 'propulsion') === 0) return 'propulsion';
    if (workingCount(cell, 'feeding') === 0) return 'feeding';
    if (hunterWeaponCount(cell) === 0 && cell.count('photosynthesis') === 0) return 'poreforming';
  } else if (policy === 'parasite') {
    for (const k of ['hunting', 'sensing', 'propulsion', 'proboscis'] as OrganKind[]) {
      if (workingCount(cell, k) === 0) return k;
    }
  } else if (policy === 'producer') {
    if (workingCount(cell, 'mitochondrion') === 0 && cell.energy < 18 && cell.substrate > 0.1 && cell.oxygen > 0.1) {
      return 'mitochondrion';
    }
    if (workingCount(cell, 'photosynthesis') < 2) return 'photosynthesis';
    if (workingCount(cell, 'mitochondrion') === 0) return 'mitochondrion';
  } else if (policy === 'grazer') {
    if (workingCount(cell, 'feeding') === 0) return 'feeding';
    if (workingCount(cell, 'cilia') === 0) return 'cilia';
  }
  return '';
}

function isEssential(cell: Cell, policy: string, kind: OrganKind): boolean {
  if (kind === 'photosynthesis') {
    return workingCount(cell, kind) < 2 || (policy === 'producer' && cell.energy < 18);
  }
  if (kind === 'mitochondrion') {
    return workingCount(cell, kind) === 0 || (policy === 'producer' && cell.energy < 18 && workingCount(cell, kind) < 2);
  }
  if (kind === 'feeding') {
    return workingCount(cell, 'feeding') === 0 && (policy === 'grazer' || policy === 'hunter' || workingCount(cell, 'photosynthesis') === 0);
  }
  if (kind === 'regenerative' && cell.health < 70) return workingCount(cell, kind) === 0;
  if (policy === 'parasite' && (kind === 'hunting' || kind === 'sensing' || kind === 'propulsion' || kind === 'proboscis')) {
    return workingCount(cell, kind) === 0;
  }
  if (policy === 'hunter') {
    if (kind === 'hunting' || kind === 'propulsion') return workingCount(cell, kind) === 0;
    if (kind === 'poreforming' || kind === 'toxin' || kind === 'counterattack') {
      return hunterWeaponCount(cell) === 0;
    }
  }
  return policy === 'grazer' && kind === 'cilia' && workingCount(cell, kind) === 0;
}

function canPurchase(sim: InvestmentSim, cell: Cell, policy: string, kind: OrganKind): boolean {
  const cost = cell.constructionPrice(kind);
  const core = isEssential(cell, policy, kind);
  let reserve = OPERATING_BIOMASS;
  let energyFloor = 18.0;

  if (sim.automaticReproduction && !core) {
    if (cell.automaticDivision) {
      const q = sim.divisionQuote(cell, 'mitosis');
      reserve = Math.max(reserve, q.material);
      energyFloor = Math.max(energyFloor, q.energy);
    }
    if (cell.automaticBudding) {
      const q = sim.divisionQuote(cell, 'budding');
      reserve = Math.max(reserve, q.material);
      energyFloor = Math.max(energyFloor, q.energy);
    }
  }
  if (cost > 0 && cell.biomass - cost < reserve) return false;
  if ((kind === 'photosynthesis' || kind === 'mitochondrion') && core) return true;
  const upkeep = organUpkeepEstimate({ kind, scale: 1.0, hp: 1.0, mutation: '' });
  return cell.energy >= energyFloor + 60.0 * upkeep;
}

function shedSupport(cell: Cell, policy: RoleName): BuildDecision {
  if (cell.unattendedProtected) return null;
  let worst: BuildDecision = null;
  let largest = 0;
  for (const o of cell.organs) {
    if (o.hp > 0) {
      if (
        o.kind === 'feeding' ||
        o.kind === 'photosynthesis' ||
        o.kind === 'mitochondrion' ||
        isReceptorKind(o.kind)
      ) {
        continue;
      }
      if (o.kind === 'regenerative' && cell.health < 70) continue;
      if (
        policy === 'parasite' &&
        (o.kind === 'hunting' || o.kind === 'sensing' || o.kind === 'propulsion' || o.kind === 'proboscis') &&
        workingCount(cell, o.kind) <= 1
      ) {
        continue;
      }
      if (
        policy === 'hunter' &&
        ((o.kind !== 'proboscis' && anyWeaponWorking(cell) > 0 && hunterWeaponCount(cell) <= 1 && (o.kind === 'poreforming' || o.kind === 'toxin' || o.kind === 'counterattack')) ||
          (o.kind === 'propulsion' && workingCount(cell, 'propulsion') <= 1))
      ) {
        continue;
      }
      if (policy === 'grazer' && o.kind === 'cilia' && workingCount(cell, 'cilia') <= 1) {
        continue;
      }
    }
    const upkeep = organUpkeepEstimate(o);
    if (o.hp <= 0 || upkeep > largest) {
      worst = { action: 'remove', id: o.id };
      largest = upkeep;
    }
  }
  return worst;
}

function candidateForRole(
  sim: InvestmentSim,
  cell: Cell,
  policy: RoleName,
): { kind: OrganKind; mutation?: string } | null {
  if (cell.synergy() !== policy) {
    const core = missingSynergyPart(cell, policy);
    if (core && cell.canFit(core, 0, 1, false)) {
      if (core === 'photosynthesis') {
        return {
          kind: core,
          mutation: sim.lightAt(cell.position) < 0.5 ? 'shade_leaf' : 'sun_leaf',
        };
      }
      return { kind: core };
    }
    return null;
  }

  if (policy === 'producer' && cell.energy < 18) {
    if (cell.substrate > 0.1 && cell.oxygen > 0.1 && workingCount(cell, 'mitochondrion') < 2 && cell.canFit('mitochondrion', 0, 1, false)) {
      return { kind: 'mitochondrion' };
    }
    if (workingCount(cell, 'photosynthesis') < 4 && (workingCount(cell, 'photosynthesis') === 0 || cell.carbon > 0.001) && cell.canFit('photosynthesis', 0, 1, false)) {
      return {
        kind: 'photosynthesis',
        mutation: sim.lightAt(cell.position) < 0.5 ? 'shade_leaf' : 'sun_leaf',
      };
    }
  }

  const ticket = (Math.imul(cell.id, 19349663) ^ Math.imul(sim.seedValue, 83492791)) | 0;
  const variant = posmod(ticket, 2);
  const priorities = ROLE_VARIANTS[policy][variant];
  let best: { kind: OrganKind; mutation?: string } | null = null;
  let bestScore = -Infinity;

  for (let i = 0; i < priorities.length; i++) {
    const kind = priorities[i];
    const count = workingCount(cell, kind);
    const limit =
      kind === 'photosynthesis'
        ? 4
        : kind === 'feeding' || kind === 'cilia' || kind === 'protection' || kind === 'mitochondrion'
          ? 2
          : 1;
    if (count >= limit || !cell.canFit(kind, 0, 1, false)) continue;

    let value = (priorities.length - i) / Math.pow(1 + count, 1.7);
    if (workingCount(cell, priorities[0]) === 0 && i === 0) value += 100;
    if (i > 0 && count === 0) value += 12;

    if (policy === 'hunter' && workingCount(cell, 'hunting') > 0) {
      if (hunterWeaponCount(cell) === 0 && (kind === 'toxin' || kind === 'poreforming' || kind === 'counterattack')) {
        value += 70;
      }
      if (workingCount(cell, 'propulsion') + workingCount(cell, 'cilia') === 0 && (kind === 'propulsion' || kind === 'cilia')) {
        value += 50;
      }
    }
    if (cell.health < 70 || cell.acidStress > 0.25) {
      if (kind === 'regenerative' && count === 0) value += 40;
      if (kind === 'sensing' && count === 0) value += 25;
    }
    if (kind === 'mitochondrion' && cell.oxygen < 0.1 && workingCount(cell, 'photosynthesis') === 0) {
      value *= 0.25;
    }
    if (kind === 'mitochondrion' && count === 0 && cell.workCapacity() < 1 && cell.substrate > 0 && cell.oxygen > 0.1) {
      value += 18;
    }
    if (kind === 'acidifying' && workingCount(cell, 'regenerative') === 0) continue;

    if (value > bestScore) {
      bestScore = value;
      best =
        kind === 'photosynthesis'
          ? { kind, mutation: sim.lightAt(cell.position) < 0.5 ? 'shade_leaf' : 'sun_leaf' }
          : { kind };
    }
  }
  return best;
}

function decisionForRole(sim: InvestmentSim, cell: Cell, policy: RoleName): BuildDecision {
  const blocker = synergyBlocker(cell, policy);
  if (blocker) return blocker;

  const choice = candidateForRole(sim, cell, policy);
  if (
    cell.energy < 18 &&
    (!choice || !isEssential(cell, policy, choice.kind) || !canPurchase(sim, cell, policy, choice.kind))
  ) {
    const recovery = shedSupport(cell, policy);
    if (recovery) return recovery;
  }
  if (choice && canPurchase(sim, cell, policy, choice.kind)) {
    return { action: 'install', ...choice };
  }

  const ticket = (Math.imul(cell.id, 19349663) ^ Math.imul(sim.seedValue, 83492791)) | 0;
  const priorities = ROLE_VARIANTS[policy][posmod(ticket, 2)];
  const missingCore = cell.synergy() !== policy;

  for (const o of cell.organs) {
    if (cell.unattendedProtected) continue;
    if (
      o.hp > 0 &&
      (o.kind === 'feeding' || o.kind === 'photosynthesis' || o.kind === 'mitochondrion') &&
      workingCount(cell, o.kind) <= 1
    ) {
      continue;
    }
    if (
      o.hp > 0 &&
      (o.kind === 'protection' || o.kind === 'regenerative' || o.kind === 'neutralizing') &&
      workingCount(cell, o.kind) <= 1
    ) {
      continue;
    }
    if (
      o.hp > 0 &&
      policy === 'parasite' &&
      (o.kind === 'hunting' || o.kind === 'sensing' || o.kind === 'propulsion' || o.kind === 'proboscis') &&
      workingCount(cell, o.kind) <= 1
    ) {
      continue;
    }
    if (
      o.hp > 0 &&
      policy === 'hunter' &&
      (((o.kind === 'poreforming' || o.kind === 'toxin' || o.kind === 'counterattack') && hunterWeaponCount(cell) <= 1) ||
        (o.kind === 'propulsion' && workingCount(cell, 'propulsion') <= 1))
    ) {
      continue;
    }
    if (o.hp > 0 && policy === 'grazer' && o.kind === 'cilia' && workingCount(cell, 'cilia') <= 1) {
      continue;
    }
    const limit =
      o.kind === 'photosynthesis'
        ? 4
        : o.kind === 'feeding' || o.kind === 'cilia' || o.kind === 'protection' || o.kind === 'mitochondrion'
          ? 2
          : 1;
    const excess = workingCount(cell, o.kind) > limit;
    const unsuitable =
      missingCore && !priorities.includes(o.kind) && !(policy === 'hunter' && o.kind === 'proboscis');
    if (o.hp <= 0 || excess || unsuitable) {
      return { action: 'remove', id: o.id };
    }
  }
  return null;
}

function templateDecision(sim: InvestmentSim, cell: Cell): BuildDecision {
  const root = cell.lineageId();
  const target =
    sim.investment.cellTemplates.get(root)?.get(cell.id) ?? sim.investment.templates.get(root);
  if (!target || target.length === 0) return null;

  const sig = JSON.stringify(target);
  if (sim.investment.completedTemplates.get(cell.id) === sig) {
    const fallback = balancedPath(sim.seedValue, cell);
    const res = decisionForRole(sim, cell, fallback);
    if (res && res.action === 'remove') {
      const organ = cell.organById(res.id);
      if (organ && target.filter((p) => p.kind === organ.kind).length >= cell.count(organ.kind)) {
        return null;
      }
    }
    return res;
  }

  const used = new Set<number>();
  for (const wanted of target) {
    const found = cell.organs.find((o) => o.kind === wanted.kind && !used.has(o.id));
    if (found) {
      used.add(found.id);
      if (wanted.mutation && found.mutation !== wanted.mutation) {
        return { action: 'adapt', id: found.id, gene: wanted.mutation };
      }
    } else if (cell.canFit(wanted.kind, 0, 1, false) && canPurchase(sim, cell, 'custom', wanted.kind)) {
      return wanted.mutation
        ? { action: 'install', kind: wanted.kind, mutation: wanted.mutation }
        : { action: 'install', kind: wanted.kind };
    } else {
      return null;
    }
  }

  for (const o of cell.organs) {
    if (used.has(o.id) || cell.unattendedProtected) continue;
    return { action: 'remove', id: o.id };
  }

  sim.investment.completedTemplates.set(cell.id, sig);
  return decisionForRole(sim, cell, balancedPath(sim.seedValue, cell));
}

export function investmentDecision(sim: InvestmentSim, cell: Cell): BuildDecision {
  if (sim.managedCells.has(cell.id)) return null;
  const policy = resolvedStrategyForCell(sim.seedValue, sim.investment, cell);
  if (policy === 'custom') return templateDecision(sim, cell);
  if (policy === 'manual' || policy === 'balanced') return null;
  return decisionForRole(sim, cell, policy);
}

export function investmentPlacementAngle(
  sim: InvestmentSim,
  cell: Cell,
  kind: OrganKind,
): number {
  const policy = resolvedStrategyForCell(sim.seedValue, sim.investment, cell);
  if (policy !== 'parasite') {
    return posmod(cell.id * 2.399963 + cell.organs.length, TAU);
  }
  let front = posmod(cell.id * 2.399963, TAU);
  for (const o of cell.organs) {
    if (o.kind === 'propulsion' && o.hp > 0) {
      front = posmod(o.a - Math.PI, TAU);
      break;
    }
  }
  for (const o of cell.organs) {
    if (o.kind === 'proboscis' && o.hp > 0) {
      front = o.a;
      break;
    }
  }
  if (kind === 'propulsion') return front + Math.PI;
  if (kind === 'proboscis') return front;
  if (kind === 'hunting') return front + 0.85;
  if (kind === 'sensing') return front - 0.85;
  return posmod(cell.id * 2.399963 + cell.organs.length, TAU);
}

export function setInvestmentStrategy(
  sim: InvestmentSim,
  scope: 'cell' | 'lineage' | 'family_adopt',
  value: InvestmentStrategy | 'inherit',
): boolean {
  if (sim.player.dead) return false;
  const root = sim.player.lineageId();
  if (scope === 'family_adopt') {
    for (const member of sim.cells) {
      if (member.lineageId() === root) sim.investment.cells.delete(member.id);
    }
    return true;
  }
  if (scope === 'cell') {
    if (value === 'inherit') sim.investment.cells.delete(sim.player.id);
    else sim.investment.cells.set(sim.player.id, value);
    return true;
  }
  if (value !== 'inherit') {
    sim.investment.lineages.set(root, value);
    return true;
  }
  return false;
}

export function saveInvestmentTemplate(
  sim: InvestmentSim,
  scope: 'cell' | 'lineage',
  modelCellId: number,
): boolean {
  const model = sim.cells.find(
    (c) => c.id === modelCellId && !c.dead && c.lineageId() === sim.player.lineageId(),
  );
  if (!model) return false;
  const template: TemplatePart[] = model.organs.map((o) => ({
    kind: o.kind,
    scale: o.scale,
    mutation: o.mutation,
  }));
  const root = sim.player.lineageId();
  if (scope === 'lineage') {
    sim.investment.templates.set(root, template);
  } else {
    let cellMap = sim.investment.cellTemplates.get(root);
    if (!cellMap) {
      cellMap = new Map();
      sim.investment.cellTemplates.set(root, cellMap);
    }
    cellMap.set(sim.player.id, template);
  }
  return setInvestmentStrategy(sim, scope, 'custom');
}

export function stepAutonomousBuilds(
  sim: InvestmentSim & {
    time: number;
    autonomousBuildRetryAt: number;
    applyBuildChoice(cell: Cell, choice: NonNullable<BuildDecision>): boolean;
  },
): void {
  if (sim.time < sim.autonomousBuildRetryAt) return;
  sim.autonomousBuildRetryAt += Math.floor((sim.time - sim.autonomousBuildRetryAt) / 2.0 + 1) * 2.0;

  for (const cell of sim.cells) {
    if (cell.dead || cell.health <= 0 || sim.time < cell.investmentRetryAt) continue;
    const choice = investmentDecision(sim, cell);
    if (!choice) continue;
    if (sim.applyBuildChoice(cell, choice)) {
      cell.investmentRetryAt = sim.time + 60.0;
    }
  }
}

export type _EvolutionUnused = Evolution;
