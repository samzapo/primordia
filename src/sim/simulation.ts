import {
  BASAL_UPKEEP,
  CILIA_FLOW,
  CILIA_MOTION,
  CILIA_PUMP,
  CILIA_REACH,
  CILIA_THRUST,
  Cell,
  LINEAR_RESPONSE,
  MOTION_UPKEEP,
  ORAL_FLOW,
  PUMP_UPKEEP,
  SECRETION_COST,
  SWIM_SPEED_GAIN,
  TURN_GAIN,
  TURN_RESPONSE,
  TURN_SPEED,
  type Organ,
  type SignalReport,
  type SignalReportEntry,
  isReceptorKind,
} from './cell.ts';
import {
  behaviorPriority,
  escapeDirection,
  fallbackBehavior,
  isCellSated,
  updateBehaviorLatches,
} from './cellBehavior.ts';
import {
  CellChemistry,
  FOOD_FUEL,
  RESERVE_ATP,
  TISSUE_FUEL,
  type ChemistryEmitter,
} from './cellChemistry.ts';
import {
  COMBAT,
  ECOLOGY,
  bindingThreshold,
  materialWeight,
  mergeLimit,
  nutrientCapacity,
  particleDiameter,
  particleRadius,
  particleScale,
} from './catalog.ts';
import {
  MAX_LIVE_CELLS,
  MIN_LIVING_CELLS,
  PHEROMONE_DECAY,
  PHEROMONE_RATE,
  SPECIES,
  TAU,
  WORLD_H,
  WORLD_W,
  clamp,
  lerp,
  offsetVec,
  wrapAngle,
  wrapPos,
  type Vec2,
} from './constants.ts';
import { contactPair } from './contacts.ts';
import { Acidity } from './acidity.ts';
import { updateEnvironmentCycle, type EnvironmentState } from './environmentCycle.ts';
import { Evolution } from './evolution.ts';
import {
  mergeCandidates,
  rememberMergeCues,
  requestFamilyMerge,
  type MergeBurst,
} from './familyMerging.ts';
import { Habitat, type ContactHelper } from './habitat.ts';
import { InducedCurrents } from './inducedCurrents.ts';
import {
  balancedPath,
  balancedPondRole,
  createInvestmentState,
  investmentPlacementAngle,
  retireInvestment,
  stepAutonomousBuilds,
  type BuildDecision,
  type InvestmentState,
  type RoleName,
} from './investmentPolicy.ts';
import {
  divisionQuote,
  reproduceCell,
  stepLifecycle,
  stepLifecyclePhysiology,
  type DivisionQuote,
} from './cellLifecycle.ts';
import { lightDirection, sampleLightField } from './lightField.ts';
import { Lineage } from './lineage.ts';
import { Medium } from './medium.ts';
import { availableMutationsForOrgan } from './mutations.ts';
import { stepProboscis, type ProboscisContactVisual } from './proboscis.ts';
import { SeededRng, hash32 } from './rng.ts';
import { surfaceMaterial } from './surfaceChemistry.ts';
import { fillToxinSacs } from './toxinSac.ts';

export const MAX_QUERIES_PER_TICK = 1024;
export const MAX_FEEDS_PER_TICK = 256;
export const MAX_EMISSIONS_PER_TICK = 512;
export const MAX_DECOYS_PER_TICK = 1024;
export const MAX_HITS_PER_BODY = 64;
export const MAX_REACTION_SPARKS = 128;

export interface CpuParticle {
  id: number;
  kind: number;
  p: Vec2;
  previous: Vec2;
  v: Vec2;
  angle: number;
  previousAngle: number;
  spin: number;
  amount: number;
  capacity: number;
  age: number;
  alive: boolean;
  owner: number;
  lineage: number;
  expiresAt: number;
  report: SignalReport | null;
}

export interface QueuedEmission {
  kind: number;
  x: number;
  y: number;
  vx: number;
  vy: number;
  angle: number;
  spin: number;
  amount: number;
  capacity: number;
  owner: number;
  lineage: number;
  expiresAt: number;
  report: SignalReport | null;
}

export interface GpuBodyDesc {
  cell: Cell;
  visualOutline: Vec2[];
  physicalPoints: Vec2[];
  gutRoom: number;
  oxygenRoom: number;
  carbonRoom: number;
  hasSurfaceComplexes: boolean;
}

export interface GpuFeedDesc {
  centerX: number;
  centerY: number;
  reach: number;
  kind: 'mouth' | 'oxygen' | 'carbon';
  bodyIndex: number;
  organId: number;
  cellId: number;
  capacity: number;
}

export interface GpuQueryDesc {
  atX: number;
  atY: number;
  reach: number;
  mass: number;
  cellId: number;
  lineage: number;
  targetId: number;
  mode: number; // 0=hunt, 1=flee, 2=graze, 3=waste, 4=toxin, 5=inspect, 6=family, 7=danger
  incumbent: number;
  organId: number;
  cellIndex: number;
  isCounterAttack?: boolean;
}

export interface GpuDecoyDesc {
  atX: number;
  atY: number;
  normX: number;
  normY: number;
  reach: number;
  bodyIndex: number;
  cellId: number;
  organId: number;
}

export interface GpuStepInput {
  dt: number;
  time: number;
  revision: number;
  seedValue: number;
  stepAcidityField: boolean;
  ambientGasGroup: number; // -1 if none this tick, else 0..19
  ambientGasElapsed: number;
  bodies: GpuBodyDesc[];
  feeds: GpuFeedDesc[];
  queries: GpuQueryDesc[];
  emissions: QueuedEmission[];
  decoys: GpuDecoyDesc[];
  inspectCursor: {
    active: boolean;
    x: number;
    y: number;
    maxRadius: number;
    trackedSlot: number;
    trackedGen: number;
    epoch: number;
  };
}

export interface GpuReceipts {
  revision: number;
  inspectEpoch?: number;
  inspectSeq?: number;
  bodyIntakes: Array<{ food: number; oxygen: number; carbon: number }>;
  feedResults: Array<{ taken: number; fuel: number; momentX: number; momentY: number }>;
  queryResults: Array<{
    found: boolean;
    atX: number;
    atY: number;
    score: number;
    dist: number;
    reportId: number;
    lineage: number;
    emittedAt: number;
    expiresAt: number;
    mass: number;
    radius: number;
    hostile: boolean;
    defended: boolean;
  }>;
  exposureHits: Array<{
    bodyIndex: number;
    amount: number;
    angle: number;
    kind: number;
    owner: number;
  }>;
  decoyHits: number[];
  reactionSparks: Array<{ x: number; y: number; cue: number }>;
  census: {
    alive: number;
    pheromones: number;
    material: number;
    oxygen: number;
    decays: number;
    materialLoss: number;
    recycled: number;
    reactions: number;
  };
  inspected: {
    valid: boolean;
    slot: number;
    gen: number;
    kind: number;
    x: number;
    y: number;
    angle: number;
    amount: number;
    capacity: number;
    owner: number;
    lineage: number;
    report: SignalReport | null;
    expiresAt: number;
  } | null;
  acidField: Float32Array;
}

export interface DeathBurst {
  serial: number;
  id: number;
  time: number;
  at: Vec2;
  radius: number;
  angle: number;
  outline: Vec2[];
  lineage: number;
  isPlayer: boolean;
}

export interface ReactionSpark {
  at: Vec2;
  time: number;
  serial: number;
}

export interface SoundEvent {
  sequence: number;
  kind: string;
  at: Vec2;
  source: number;
  amount: number;
  time: number;
}

export interface SimEvent {
  type: string;
  time: number;
  [key: string]: unknown;
}

const QUERY_MODE_CODE: Record<string, number> = {
  hunt: 0,
  flee: 1,
  graze: 2,
  waste: 3,
  toxin: 4,
  inspect: 5,
  family_toward: 6,
  family_away: 6,
  kin_toward: 6,
  kin_away: 6,
  danger: 7,
};

export class Simulation implements ChemistryEmitter {
  seedValue: number;
  habitat: number; // 0: Balanced Tide, 1: Lean Hunting Grounds, 2: Rich / Armored Hunters
  rng: SeededRng;
  ecologyRng: SeededRng;
  evolution: Evolution;
  lineage = new Lineage();
  familyLedgers: Lineage[] = [];
  investment: InvestmentState = createInvestmentState();

  time = 0.0;
  revision = 0;
  nextId = 1;
  nextAttackOwner = 2147483640;

  fluid = new Medium();
  acidity = new Acidity();
  induced = new InducedCurrents();
  habitatGeometry!: Habitat;
  environment: EnvironmentState = {
    hour: -1,
    utc: '',
    weather: 'Clear',
    light: 1.0,
    flowVersion: 0,
    flowAngle: 0,
    flowStrength: 1.0,
  };

  cells: Cell[] = [];
  player!: Cell;
  managedCells = new Set<number>();

  // Accounting & lifecycle timers
  automaticReproduction = true;
  lifecycleDue = 1.0;
  autonomousBuildRetryAt = 2.0;
  replaceDue = 0.5;
  autolysisAfter = new Map<number, number>();
  externalInput = 0;
  respirationLoss = 0;
  recycled = 0;
  kills = 0;

  // Ambient carbon/oxygen scheduling (20 staggered groups over 5s = 0.25s cadence)
  ambientCarbonDue = 0.25;
  ambientCarbonPhase = 0;
  ambientCarbonTimes = new Float64Array(20);

  // Combat & lineage caches
  attackAliases = new Map<string, number>();
  attackSources = new Map<number, { source: number; root: number; selective: boolean; noDamage?: boolean }>();
  inheritedLineages = new Map<number, number>();
  lineageColors = new Map<number, string>();
  lineageNames = new Map<number, string>();

  // Visual & audio event buffers
  deathSerial = 0;
  deathBursts: DeathBurst[] = [];
  mergeSerial = 0;
  mergeBursts: MergeBurst[] = [];
  reactionSerial = 0;
  reactionSparks: ReactionSpark[] = [];
  soundSequence = 0;
  soundEvents: SoundEvent[] = [];
  soundRecent = new Map<string, SoundEvent>();
  proboscisContacts: ProboscisContactVisual[] = [];
  events: SimEvent[] = [];

  // GPU vs headless particle management
  useGpuParticles: boolean;
  pendingEmissions: QueuedEmission[] = [];
  cpuParticles: CpuParticle[] = [];
  private nextCpuParticleId = 1;

  // Cached GPU census & query responses
  gpuCensus = {
    alive: 0,
    pheromones: 0,
    material: 0,
    oxygen: 0,
    decays: 0,
    materialLoss: 0,
    recycled: 0,
    reactions: 0,
  };
  private pendingStepsByRev = new Map<
    number,
    {
      feeds: GpuFeedDesc[];
      queries: GpuQueryDesc[];
      bodyIds: number[];
      decoys: GpuDecoyDesc[];
    }
  >();
  private secretionNeeded = new Set<string>(); // `${cellId}:${organId}`
  lastInspected: GpuReceipts['inspected'] = null;
  private lastInspectSeq = -1;
  inspectCursor = {
    active: false,
    x: 0,
    y: 0,
    maxRadius: 24,
    trackedSlot: -1,
    trackedGen: 0,
    epoch: 0,
  };

  constructor(seedNumber = 20261004, profile = 0, useGpuParticles = true) {
    this.seedValue = seedNumber | 0;
    this.habitat = clamp(Math.floor(profile), 0, 2);
    this.useGpuParticles = useGpuParticles;
    this.rng = new SeededRng(this.seedValue);
    this.ecologyRng = new SeededRng((this.seedValue ^ 0x719ab) | 0);
    this.evolution = new Evolution(this.seedValue);
    this.lineage.progression = this.evolution;
    this.ambientCarbonTimes.fill(0);

    // Create player starter cell (id 0)
    this.player = new Cell(0, { x: 2048, y: 1280 }, Math.abs((this.seedValue * 1000003) | 0));
    this.player.role = 'player';
    this.player.body = 60.0;
    this.player.biomass = 36.0;
    this.player.energy = 72.0;
    this.player.health = 100.0;
    this.player.updateGeometry();
    this.player.addOrgan('feeding', 0, 'graze', false);
    this.player.addOrgan('photosynthesis', Math.PI, 'graze', false);
    this.cells.push(this.player);
    this.inheritedLineages.set(0, 0);
    this.investment.lineages.set(0, 'balanced');

    // Create initial pond NPCs across the balanced role mix with minimal synergy starter sets
    for (let i = 0; i < 18; i++) {
      const dist = i % 5 === 3 ? 1050 + i * 45 : i === 0 ? 220 : 340 + i * 94;
      const angle = i * 2.4;
      const p = wrapPos({
        x: this.player.position.x + Math.cos(angle) * dist,
        y: this.player.position.y + Math.sin(angle) * dist,
      });
      this.makeCell(p, balancedPondRole(this.seedValue, i));
    }

    this.habitatGeometry = new Habitat(this.seedValue, this.cells);
    this.fluid.setPlants(this.habitatGeometry);

    for (const cell of this.cells) {
      this.seedCellProducts(cell);
    }

    this.lineage.initialize(this.player, this.time);
    this.familyLedgers.push(this.lineage);
    updateEnvironmentCycle(
      this.seedValue,
      this.environment,
      this.induced,
      this.fluid,
      Math.floor(Date.now() / 1000),
    );
  }

  private makeCell(p: Vec2, role: RoleName): Cell {
    const id = this.nextId++;
    const cell = new Cell(id, p, Math.abs((this.seedValue * 1000003 + id * 9176) | 0));
    cell.role = role;
    cell.angle = this.rng.randf() * TAU;
    cell.body = role === 'hunter' ? 135.0 : this.rng.randRange(14, 32);
    cell.biomass = role === 'hunter' ? (this.habitat === 2 ? 90.0 : 35.0) : role === 'producer' ? 24.0 : 20.0;
    cell.energy = 70.0;
    cell.updateGeometry();

    if (role === 'hunter') {
      cell.addOrgan('hunting', 0.48, 'hunt', false);
      cell.addOrgan('propulsion', Math.PI, 'graze', false);
      cell.addOrgan('feeding', 1.1, 'graze', false);
      cell.addOrgan('poreforming', 0, 'graze', false);
    } else if (role === 'parasite') {
      cell.addOrgan('hunting', 0.48, 'hunt', false);
      cell.addOrgan('sensing', -0.48, 'flee', false);
      cell.addOrgan('propulsion', Math.PI, 'graze', false);
      cell.addOrgan('proboscis', 0, 'graze', false);
    } else if (role === 'producer') {
      cell.addOrgan('photosynthesis', 0, 'graze', false);
      cell.addOrgan('photosynthesis', Math.PI, 'graze', false);
      cell.addOrgan('mitochondrion', 0.5, 'graze', false);
    } else {
      cell.addOrgan('feeding', 0, 'graze', false);
      cell.addOrgan('cilia', Math.PI, 'graze', false);
    }

    cell.updateGeometry();
    cell.previousAngle = cell.angle;
    cell.senseClock = (cell.id % 9) / 60.0;
    this.cells.push(cell);
    this.inheritedLineages.set(cell.id, cell.lineageId());
    this.investment.lineages.set(cell.lineageId(), 'balanced');
    return cell;
  }

  private seedCellProducts(cell: Cell): void {
    const foodCount = this.habitat !== 1 ? 55 : 14;
    const parcelScale = ECOLOGY.parcel_scale;
    const total = foodCount + 180;
    for (let i = 0; i < total; i++) {
      const kind =
        i < foodCount ? SPECIES.NUTRIENT : i < foodCount + 60 ? SPECIES.CARBON : SPECIES.OXYGEN;
      let amount = (kind !== SPECIES.CARBON ? 0.3 : 0.4) * parcelScale;
      if (kind === SPECIES.NUTRIENT) amount *= ECOLOGY.seed_food_scale;
      const dir = this.rng.randf() * TAU;
      const dist = cell.radius + 12.0 + this.rng.randf() * 160.0;
      const at = wrapPos({
        x: cell.position.x + Math.cos(dir) * dist,
        y: cell.position.y + Math.sin(dir) * dist,
      });
      this.spawnParticle(kind, at, { x: 0, y: 0 }, amount, cell.id);
    }
  }

  familyLedger(cell: Cell): Lineage {
    const root = cell.lineageId();
    if (this.lineage.rootId === root) return this.lineage;
    let found = this.familyLedgers.find((l) => l.rootId === root);
    if (!found) {
      found = new Lineage();
      found.rootId = root;
      found.progression = new Evolution(this.seedValue ^ root);
      found.register(cell, -1, cell.generation, 'living', this.time);
      this.familyLedgers.push(found);
    }
    return found;
  }

  lightAt(at: Vec2): number {
    const field = sampleLightField(this.seedValue, at.x, at.y);
    const mult = this.habitat === 1 ? 0.5 : this.habitat === 2 ? 1.25 : 1.0;
    return clamp(field * mult * this.environment.light, 0.02, 1.0);
  }

  lightDir(at: Vec2): Vec2 {
    return lightDirection(this.seedValue, at.x, at.y);
  }

  investmentStrategy(cell: Cell): string {
    return this.investment.cells.get(cell.id) ?? this.investment.lineages.get(cell.lineageId()) ?? 'balanced';
  }

  divisionQuote(cell: Cell, mode: 'mitosis' | 'budding'): DivisionQuote {
    return divisionQuote(this, cell, mode);
  }

  private enqueueEmission(q: QueuedEmission): void {
    if (this.useGpuParticles) {
      this.pendingEmissions.push(q);
      return;
    }
    const p: CpuParticle = {
      id: this.nextCpuParticleId++,
      kind: q.kind,
      p: { x: q.x, y: q.y },
      previous: { x: q.x, y: q.y },
      v: { x: q.vx, y: q.vy },
      angle: q.angle,
      previousAngle: q.angle,
      spin: q.spin,
      amount: q.amount,
      capacity: q.capacity,
      age: 0,
      alive: true,
      owner: q.owner,
      lineage: q.lineage,
      expiresAt: q.expiresAt,
      report: q.report,
    };
    this.cpuParticles.push(p);
  }

  spawnParticle(
    kind: number,
    pos: Vec2,
    vel: Vec2,
    amount: number,
    owner = -1,
    capacity = -1,
  ): void {
    if (amount <= 0) return;
    const wp = wrapPos(pos);
    const angle = kind === SPECIES.PHEROMONE ? 0 : this.rng.randf() * TAU;
    const spin = kind === SPECIES.PHEROMONE ? 0 : this.rng.randNormal(0, 0.8);
    const lin = this.inheritedLineages.get(owner) ?? owner;
    const expiresAt =
      kind === SPECIES.PHEROMONE
        ? this.time - Math.log(Math.max(this.rng.randf(), 1e-9)) / PHEROMONE_DECAY
        : 0;
    this.enqueueEmission({
      kind,
      x: wp.x,
      y: wp.y,
      vx: kind === SPECIES.PHEROMONE ? 0 : vel.x,
      vy: kind === SPECIES.PHEROMONE ? 0 : vel.y,
      angle,
      spin,
      amount,
      capacity: capacity >= 0 ? capacity : amount,
      owner,
      lineage: lin,
      expiresAt,
      report: null,
    });
  }

  spawnNutrientWithCapacity(
    pos: Vec2,
    vel: Vec2,
    amount: number,
    owner: number,
    capacity: number,
  ): void {
    this.spawnParticle(SPECIES.NUTRIENT, pos, vel, amount, owner, capacity);
  }

  emitExternal(
    kindKey: 'nutrient' | 'waste' | 'oxygen' | 'carbon',
    at: Vec2,
    vel: Vec2,
    amount: number,
    owner: number,
    capacity?: number,
  ): void {
    const kind =
      kindKey === 'nutrient'
        ? SPECIES.NUTRIENT
        : kindKey === 'waste'
          ? SPECIES.WASTE
          : kindKey === 'oxygen'
            ? SPECIES.OXYGEN
            : SPECIES.CARBON;
    this.spawnParticle(kind, at, vel, amount, owner, capacity ?? amount);
  }

  private emitAimed(
    kind: number,
    at: Vec2,
    aim: Vec2,
    speed: number,
    quantity: number,
    owner: number,
  ): void {
    if (quantity <= 0) return;
    const wp = wrapPos(at);
    const angle = Math.atan2(aim.y, aim.x);
    const lin = this.inheritedLineages.get(owner) ?? owner;
    this.enqueueEmission({
      kind,
      x: wp.x,
      y: wp.y,
      vx: aim.x * speed,
      vy: aim.y * speed,
      angle,
      spin: this.rng.randNormal(0, 0.8),
      amount: quantity,
      capacity: quantity,
      owner,
      lineage: lin,
      expiresAt: 0,
      report: null,
    });
  }

  private emitMaterial(kind: number, at: Vec2, amount: number, vel: Vec2, owner: number): void {
    const q = ECOLOGY.packet_quantum;
    const count = Math.max(1, Math.ceil(amount / q));
    for (let i = 0; i < count; i++) {
      const part = amount / count;
      const cap = kind === SPECIES.NUTRIENT ? (part * TISSUE_FUEL) / FOOD_FUEL : part;
      this.spawnParticle(kind, at, vel, part, owner, cap);
    }
  }

  private emitPheromone(cell: Cell): void {
    const dir = this.rng.randf() * TAU;
    const lp = cell.localPoint(dir);
    const c = Math.cos(cell.angle);
    const s = Math.sin(cell.angle);
    const at = wrapPos({
      x: cell.position.x + lp.x * c - lp.y * s,
      y: cell.position.y + lp.x * s + lp.y * c,
    });
    let hostile = false;
    let armored = false;
    for (const o of cell.organs) {
      if (o.hp <= 0) continue;
      if (o.kind === 'poreforming' || o.kind === 'toxin' || o.kind === 'acidifying' || o.kind === 'proboscis') {
        hostile = true;
      }
      if (o.kind === 'protection' || o.kind === 'neutralizing') armored = true;
      if (o.kind === 'toxin_sac' && o.storedToxin > 0) armored = true;
    }
    const expiresAt = this.time - Math.log(Math.max(this.rng.randf(), 1e-9)) / PHEROMONE_DECAY;
    const report: SignalReport = {
      id: cell.id,
      lineage: cell.lineageId(),
      at: { ...cell.position },
      mass: cell.organicMass(),
      radius: cell.radius,
      hostile,
      defended: hostile || armored,
      emittedAt: this.time,
    };
    this.enqueueEmission({
      kind: SPECIES.PHEROMONE,
      x: at.x,
      y: at.y,
      vx: 0,
      vy: 0,
      angle: 0,
      spin: 0,
      amount: 0.2,
      capacity: 0.2,
      owner: cell.id,
      lineage: cell.lineageId(),
      expiresAt,
      report,
    });
  }

  private attackOwner(cell: Cell, selective = false): number {
    if (!selective) return cell.id;
    const key = `${cell.id}:selective`;
    const existing = this.attackAliases.get(key);
    if (existing !== undefined) return existing;
    const alias = this.nextAttackOwner--;
    this.attackAliases.set(key, alias);
    this.attackSources.set(alias, {
      source: cell.id,
      root: cell.lineageId(),
      selective: true,
    });
    this.inheritedLineages.set(alias, cell.lineageId());
    return alias;
  }

  recordSound(kind: string, at: Vec2, source: number, amount = 1.0): void {
    const key = `${kind}:${source}`;
    const prev = this.soundRecent.get(key);
    if (prev && this.time - prev.time < 0.1) {
      prev.amount = Math.min(8, prev.amount + amount);
      return;
    }
    this.soundSequence++;
    const ev: SoundEvent = {
      sequence: this.soundSequence,
      kind,
      at: wrapPos(at),
      source,
      amount,
      time: this.time,
    };
    this.soundEvents.push(ev);
    if (this.soundEvents.length > 64) this.soundEvents.shift();
    this.soundRecent.set(key, ev);
  }

  recordReaction(at: Vec2): void {
    this.reactionSerial++;
    const ev: ReactionSpark = { at: wrapPos(at), time: this.time, serial: this.reactionSerial };
    if (this.reactionSparks.length < MAX_REACTION_SPARKS) {
      this.reactionSparks.push(ev);
    } else {
      this.reactionSparks[this.reactionSerial % MAX_REACTION_SPARKS] = ev;
    }
  }

  flushReserveProducts(cell: Cell, force = false): void {
    const products = cell.behavior.reserveProducts;
    if (products > 0 && (force || products >= 0.1 || cell.biomass <= 0)) {
      cell.behavior.reserveProducts = 0;
      const exPos = cell.excretionPosition();
      this.spawnParticle(SPECIES.CARBON, exPos, { x: 0, y: 0 }, products * 0.1, cell.id);
      this.spawnParticle(SPECIES.WASTE, exPos, { x: 0, y: 0 }, products * 0.9, cell.id);
    }
  }

  birthPosition(parent: Cell, child: Cell): Vec2 {
    let best = wrapPos({
      x: parent.position.x + Math.cos(parent.angle) * (parent.extent() + child.extent() + 4),
      y: parent.position.y + Math.sin(parent.angle) * (parent.extent() + child.extent() + 4),
    });
    let bestScore = Infinity;
    for (let i = 0; i < 32; i++) {
      const a = parent.angle + (TAU * i) / 32;
      const at = wrapPos({
        x: parent.position.x + Math.cos(a) * (parent.extent() + child.extent() + 4),
        y: parent.position.y + Math.sin(a) * (parent.extent() + child.extent() + 4),
      });
      let overlap = this.habitatGeometry.clearAt(at, child.extent()) ? 0 : child.extent() * 2;
      for (const other of this.cells) {
        if (other.dead) continue;
        const d = offsetVec(other.position, at);
        overlap += Math.max(0, other.extent() + child.extent() - Math.hypot(d.x, d.y));
      }
      if (overlap < bestScore) {
        bestScore = overlap;
        best = at;
      }
    }
    return best;
  }

  private safeBirthPosition(at: Vec2, radius: number): boolean {
    if (!this.habitatGeometry.clearAt(at, radius)) return false;
    for (const c of this.cells) {
      if (c.dead) continue;
      const d = offsetVec(c.position, at);
      if (Math.hypot(d.x, d.y) < c.extent() + radius + 20) return false;
    }
    return true;
  }

  // Player editing commands
  installOrgan(kind: Organ['kind'], localAngle: number, mode = 'graze'): boolean {
    if (this.player.dead) return false;
    const cost = this.player.constructionPrice(kind);
    if (this.player.biomass < cost) return false;
    if (!this.player.addOrgan(kind, localAngle, mode, true, 1.0)) return false;
    this.externalInput += Math.max(0, this.player.organs[this.player.organs.length - 1].material - cost);
    this.player.updateGeometry();
    return true;
  }

  recycleFor(cell: Cell, index: number): boolean {
    const debris = cell.recycle(index);
    if (debris < 0) return false;
    if (debris > 0) {
      this.spawnParticle(SPECIES.WASTE, cell.position, { x: 0, y: 0 }, debris, cell.id);
    }
    return true;
  }

  removeOrgan(index: number): boolean {
    return this.recycleFor(this.player, index);
  }

  restoreOrgan(id: number): boolean {
    const scar = this.player.lostOrgans.find((o) => o.id === id);
    if (!scar) return false;
    const cost = this.player.constructionPrice(scar.kind);
    if (this.player.biomass < cost) return false;
    if (!this.player.restoreOrgan(id, true)) return false;
    this.externalInput += Math.max(0, this.player.organs[this.player.organs.length - 1].material - cost);
    this.player.updateGeometry();
    return true;
  }

  mutateOrgan(id: number, gene: string): boolean {
    const organ = this.player.organById(id);
    if (!organ) return false;
    const avail = availableMutationsForOrgan(organ.kind, organ.mutation, this.evolution.learned);
    if (!avail.includes(gene)) return false;
    return this.player.specialize(id, gene);
  }

  applyBuildChoice(cell: Cell, choice: NonNullable<BuildDecision>): boolean {
    const ledger = this.familyLedger(cell);
    if (choice.action === 'adapt') {
      return cell.specialize(choice.id, choice.gene);
    }
    if (choice.action === 'remove') {
      const idx = cell.organs.findIndex((o) => o.id === choice.id);
      return idx >= 0 ? this.recycleFor(cell, idx) : false;
    }
    const cost = cell.constructionPrice(choice.kind);
    if (cell.biomass < cost) return false;
    const angle = investmentPlacementAngle(this, cell, choice.kind);
    if (!cell.addOrgan(choice.kind, angle, 'graze', true, 1.0)) return false;
    this.externalInput += Math.max(0, cell.organs[cell.organs.length - 1].material - cost);
    cell.updateGeometry();
    if (choice.mutation && ledger.progression) {
      cell.specialize(cell.organs[cell.organs.length - 1].id, choice.mutation);
    }
    return true;
  }

  divideLineage(mode: 'mitosis' | 'budding', follow = true): boolean {
    return reproduceCell(this, this.player, this.lineage, mode, follow);
  }

  followFamily(identity: number): boolean {
    const target = this.lineage.activeFamily(this.cells).find((c) => c.id === identity);
    if (!target || target === this.player) return false;
    this.lineage.adopted(target, this);
    return true;
  }

  requestMerge(donorId: number): boolean {
    return requestFamilyMerge(this, donorId);
  }

  mergeCandidatesForPlayer(): Map<number, number> {
    return mergeCandidates(this, this.player);
  }

  acceptDivisionMutation(gene: string): boolean {
    return this.evolution.acceptDivisionOffer(gene);
  }

  private die(cell: Cell): void {
    if (cell.dead) return;
    this.flushReserveProducts(cell, true);
    for (const l of this.familyLedgers) l.died(cell);

    this.deathSerial++;
    this.deathBursts.push({
      serial: this.deathSerial,
      id: cell.id,
      time: this.time,
      at: { ...cell.position },
      radius: cell.radius,
      angle: cell.angle,
      outline: cell.membrane.outline().map((p) => ({ ...p })),
      lineage: cell.lineageId(),
      isPlayer: cell === this.player,
    });
    if (this.deathBursts.length > 32) this.deathBursts.shift();

    cell.dead = true;
    retireInvestment(this.investment, cell);
    cell.health = 0;

    // Release toxin_sac contents
    for (const o of cell.organs) {
      if (o.kind !== 'toxin_sac' || o.storedToxin <= 1e-6) continue;
      const count = clamp(Math.ceil(o.storedToxin / 0.08), 1, 32);
      const each = o.storedToxin / count;
      const dist = cell.extent() + 12.0;
      for (let i = 0; i < count; i++) {
        const a = (TAU * i) / count;
        const dir = { x: Math.cos(a), y: Math.sin(a) };
        this.emitAimed(
          SPECIES.TOXIN,
          { x: cell.position.x + dir.x * dist, y: cell.position.y + dir.y * dist },
          dir,
          35.0 + Math.hypot(cell.velocity.x, cell.velocity.y),
          each,
          cell.id,
        );
      }
      o.storedToxin = 0;
    }

    const surf = surfaceMaterial(cell);
    if (surf > 0) this.emitMaterial(SPECIES.WASTE, cell.position, surf, { x: 0, y: 0 }, cell.id);

    const structural = Math.max(0, cell.body + cell.biomass + cell.organMass() + cell.chemistry.reactorMass);
    if (structural > 0) {
      const count = Math.max(1, Math.ceil(structural / ECOLOGY.packet_quantum));
      for (let i = 0; i < count; i++) {
        const a = (TAU * i) / count;
        const dir = { x: Math.cos(a), y: Math.sin(a) };
        const part = structural / count;
        this.spawnNutrientWithCapacity(
          { x: cell.position.x + dir.x * cell.radius * 0.9, y: cell.position.y + dir.y * cell.radius * 0.9 },
          { x: dir.x * 24.0, y: dir.y * 24.0 },
          part,
          cell.id,
          (part * TISSUE_FUEL) / FOOD_FUEL,
        );
      }
    }

    const c = Math.cos(cell.angle);
    const s = Math.sin(cell.angle);
    for (const p of cell.chemistry.particles) {
      if (!p.alive) continue;
      const kind =
        p.species === 'food'
          ? SPECIES.NUTRIENT
          : p.species === 'waste'
            ? SPECIES.WASTE
            : p.species === 'oxygen'
              ? SPECIES.OXYGEN
              : SPECIES.CARBON;
      const len = Math.hypot(p.p.x, p.p.y) || 1;
      const lx = p.p.x / len;
      const ly = p.p.y / len;
      const nx = lx * c - ly * s;
      const ny = lx * s + ly * c;
      const at = wrapPos({
        x: cell.position.x + p.p.x * c - p.p.y * s,
        y: cell.position.y + p.p.x * s + p.p.y * c,
      });
      let cap = p.amount;
      if (kind === SPECIES.NUTRIENT) {
        cap = clamp(p.fuel / FOOD_FUEL, 0, p.amount);
        if (cap >= p.amount) {
          cap += clamp(p.nutrition, 0, p.amount * ECOLOGY.nutrient_bonus_limit);
        }
      }
      this.spawnParticle(kind, at, { x: nx * 24, y: ny * 24 }, p.amount, cell.id, cap);
      p.alive = false;
    }

    cell.chemistry.particles.length = 0;
    cell.chemistry.refresh();
    cell.surfaceComplexes.length = 0;
    cell.body = 0;
    cell.biomass = 0;
    cell.organs.length = 0;
    this.events.push({ type: 'death', id: cell.id, time: this.time });
    if (this.events.length > 128) this.events.shift();

    if (cell !== this.player) {
      this.kills++;
      const idx = this.cells.indexOf(cell);
      if (idx >= 0) this.cells.splice(idx, 1);
    }
  }

  private replenishPopulation(): void {
    const living = this.cells.filter((c) => !c.dead && c.health > 0);
    // Recover player lineage or introduce a fresh starter if entire lineage died
    if (this.player.dead || this.player.health <= 0) {
      if (!this.player.dead) this.die(this.player);
      if (!this.lineage.recover(this)) {
        // Introduce new player founder
        const idx = this.cells.indexOf(this.player);
        if (idx >= 0) this.cells.splice(idx, 1);
        for (let attempt = 0; attempt < 256; attempt++) {
          const at: Vec2 = { x: this.rng.randf() * WORLD_W, y: this.rng.randf() * WORLD_H };
          if (this.safeBirthPosition(at, 55)) {
            const id = this.nextId++;
            const founder = new Cell(id, at, Math.abs((this.seedValue * 1000003 + id * 9176) | 0));
            founder.role = 'player';
            founder.body = 60.0;
            founder.biomass = 36.0;
            founder.energy = 72.0;
            founder.health = 100.0;
            founder.updateGeometry();
            founder.addOrgan('feeding', 0, 'graze', false);
            founder.addOrgan('photosynthesis', Math.PI, 'graze', false);
            this.cells.push(founder);
            this.player = founder;
            this.inheritedLineages.set(founder.id, founder.lineageId());
            this.lineage = new Lineage();
            this.lineage.progression = this.evolution;
            this.lineage.initialize(founder, this.time);
            this.familyLedgers.push(this.lineage);
            this.seedCellProducts(founder);
            this.lineage.notify('Lineage lost · a new starter cell entered the pond.');
            break;
          }
        }
      }
    }

    // Maintain 15 living cells minimum floor
    let currentLiving = this.cells.filter((c) => !c.dead && c.health > 0).length;
    while (currentLiving < MIN_LIVING_CELLS && this.cells.length < MAX_LIVE_CELLS) {
      let placed = false;
      for (let attempt = 0; attempt < 128; attempt++) {
        const at: Vec2 = { x: this.rng.randf() * WORLD_W, y: this.rng.randf() * WORLD_H };
        if (!this.safeBirthPosition(at, 48)) continue;
        const c = this.makeCell(at, balancedPath(this.seedValue, { id: this.nextId } as Cell));
        this.seedCellProducts(c);
        placed = true;
        currentLiving++;
        break;
      }
      if (!placed) break;
    }
    void living;
  }

  // =========================================================================
  // GPU Receipt Application & Step Pipeline
  // =========================================================================

  private applyInspectedFromReceipt(receipts: GpuReceipts): void {
    const epoch = receipts.inspectEpoch ?? this.inspectCursor.epoch;
    const seq = receipts.inspectSeq ?? this.lastInspectSeq + 1;
    if (epoch !== this.inspectCursor.epoch || seq < this.lastInspectSeq) {
      return;
    }
    this.lastInspectSeq = seq;
    this.lastInspected = receipts.inspected;
  }

  applyInspectReceipt(receipts: GpuReceipts | null): void {
    if (!receipts) return;
    this.applyInspectedFromReceipt(receipts);
  }

  applyGpuReceipts(receipts: GpuReceipts | null): void {
    if (!receipts) return;
    if (receipts.revision < 0) {
      this.applyInspectedFromReceipt(receipts);
      return;
    }

    this.acidity.values.set(receipts.acidField);
    this.gpuCensus = { ...receipts.census };
    this.recycled += receipts.census.recycled;
    this.respirationLoss += receipts.census.materialLoss;
    this.applyInspectedFromReceipt(receipts);

    for (const spark of receipts.reactionSparks) {
      if (spark.cue > 0) {
        this.recordReaction({ x: spark.x, y: spark.y });
      }
    }

    let stepMeta = this.pendingStepsByRev.get(receipts.revision);
    if (!stepMeta) {
      let latestRev = -1;
      for (const [rev, val] of this.pendingStepsByRev) {
        if (rev > latestRev) {
          latestRev = rev;
          stepMeta = val;
        }
      }
    }
    for (const rev of [...this.pendingStepsByRev.keys()]) {
      if (rev <= receipts.revision) {
        this.pendingStepsByRev.delete(rev);
      }
    }
    const feedInputs = stepMeta?.feeds ?? [];
    const queryInputs = stepMeta?.queries ?? [];
    const bodyIds = stepMeta?.bodyIds ?? [];
    const decoyInputs = stepMeta?.decoys ?? [];

    // 1. Feed intakes
    for (let i = 0; i < feedInputs.length && i < receipts.feedResults.length; i++) {
      const desc = feedInputs[i];
      const res = receipts.feedResults[i];
      if (res.taken <= 1e-8) continue;
      const cell = this.cells.find((c) => c.id === desc.cellId && !c.dead);
      if (!cell) continue;
      const organ = cell.organById(desc.organId);

      if (desc.kind === 'mouth') {
        const room = Math.max(0, cell.gutCapacity() - cell.substrate);
        const take = Math.min(room, res.taken);
        if (take > 1e-8) {
          const fuelRatio = res.fuel / Math.max(1e-8, res.taken);
          const nutritionBonus = clamp(fuelRatio - 1.0, 0, ECOLOGY.nutrient_bonus_limit);
          const unitFuel = clamp(fuelRatio, 0, 1.0) * FOOD_FUEL;
          const lp = organ ? cell.organLocalPosition(organ) : { x: 0, y: 0 };
          cell.chemistry.emit(
            cell,
            'food',
            take,
            { x: lp.x * 0.72, y: lp.y * 0.72 },
            desc.cellId,
            -1,
            take * unitFuel,
            nutritionBonus,
          );
          if (organ) {
            organ.consumeFlash = 1.0;
            cell.emitted(organ);
          }
          cell.chemistry.syncCell(cell);
          cell.updateGeometry();
        }
      } else if (desc.kind === 'oxygen') {
        cell.chemistry.emit(cell, 'oxygen', res.taken, { x: 0, y: 0 }, desc.cellId, -1, 0, 0);
        cell.chemistry.syncCell(cell);
      } else if (desc.kind === 'carbon') {
        cell.chemistry.emit(cell, 'carbon', res.taken, { x: 0, y: 0 }, desc.cellId, -1, 0, 0);
        cell.chemistry.syncCell(cell);
      }
    }

    // 2. Perception queries
    this.secretionNeeded.clear();
    const cuesByCell = new Map<number, Map<number, { mode: string; organId: number; q: GpuReceipts['queryResults'][0] }[]>>();
    for (let i = 0; i < queryInputs.length && i < receipts.queryResults.length; i++) {
      const qDesc = queryInputs[i];
      const qRes = receipts.queryResults[i];
      if (!qRes.found) continue;
      if (qDesc.mode === 3 || qDesc.mode === 4) {
        // secretion demand (waste for enzyme / toxin for antitoxin)
        this.secretionNeeded.add(`${qDesc.cellId}:${qDesc.organId}`);
        continue;
      }
      const cell = this.cells.find((c) => c.id === qDesc.cellId && !c.dead);
      if (!cell) continue;
      if (qDesc.isCounterAttack) {
        const organ = cell.organById(qDesc.organId);
        if (organ && qRes.hostile && qRes.lineage !== cell.lineageId() && qRes.expiresAt > this.time) {
          organ.counterReport = {
            report: {
              id: qRes.reportId,
              lineage: qRes.lineage,
              at: { x: qRes.atX, y: qRes.atY },
              mass: qRes.mass,
              radius: qRes.radius,
              hostile: qRes.hostile,
              defended: qRes.defended,
              emittedAt: qRes.emittedAt,
            },
            distance: qRes.dist,
            expiresAt: qRes.expiresAt,
          };
        }
        continue;
      }

      if (qDesc.mode === 0 || qDesc.mode === 1 || qDesc.mode === 6) {
        if (qRes.lineage === cell.lineageId() && qRes.reportId !== cell.id) {
          const entry: SignalReportEntry = {
            report: {
              id: qRes.reportId,
              lineage: qRes.lineage,
              at: { x: qRes.atX, y: qRes.atY },
              mass: qRes.mass,
              radius: qRes.radius,
              hostile: qRes.hostile,
              defended: qRes.defended,
              emittedAt: qRes.emittedAt,
            },
            distance: qRes.dist,
            expiresAt: qRes.expiresAt,
          };
          cell.behavior.familyCues.set(qRes.reportId, entry);
          const m = new Map<number, SignalReportEntry>();
          m.set(qRes.reportId, entry);
          rememberMergeCues(this, cell, m);
        }
      }

      const modeName =
        qDesc.mode === 0
          ? 'hunt'
          : qDesc.mode === 1
            ? 'flee'
            : qDesc.mode === 2
              ? 'graze'
              : qDesc.mode === 7
                ? 'toxin'
                : cell.organById(qDesc.organId)?.kind === 'family_toward'
                  ? 'kin_toward'
                  : 'kin_away';

      if (!cuesByCell.has(cell.id)) cuesByCell.set(cell.id, new Map());
      const perCell = cuesByCell.get(cell.id)!;
      if (!perCell.has(qDesc.organId)) perCell.set(qDesc.organId, []);
      perCell.get(qDesc.organId)!.push({ mode: modeName, organId: qDesc.organId, q: qRes });
    }

    for (const [cellId, orgMap] of cuesByCell) {
      const cell = this.cells.find((c) => c.id === cellId && !c.dead);
      if (!cell) continue;
      for (const list of orgMap.values()) {
        for (const item of list) {
          const organ = cell.organById(item.organId);
          if (!organ || organ.hp <= 0) continue;
          const qr = item.q;
          if (item.mode === 'hunt' && qr.lineage === cell.lineageId()) continue;
          if (item.mode === 'flee' && (qr.lineage === cell.lineageId() || !qr.hostile)) continue;

          if ((item.mode === 'hunt' || item.mode === 'flee') && qr.lineage !== cell.lineageId()) {
            const cue = {
              id: qr.reportId,
              lineage: qr.lineage,
              at: { x: qr.atX, y: qr.atY },
              mass: qr.mass,
              radius: qr.radius,
              hostile: qr.hostile,
              defended: qr.defended,
              emittedAt: qr.emittedAt,
              organId: organ.id,
              expiresAt: qr.expiresAt,
            };
            if (!cell.behavior.weaponCue || item.mode === 'hunt') {
              cell.behavior.weaponCue = cue;
            }
          }

          this.enqueueCellSignal(cell, organ, item.mode, {
            id: qr.reportId,
            lineage: qr.lineage,
            at: { x: qr.atX, y: qr.atY },
            score: qr.score,
            expiresAt: qr.expiresAt > 0 ? qr.expiresAt : this.time + 1.2,
          });
        }
      }
    }

    // 3. Exposure hits
    for (const hit of receipts.exposureHits) {
      const cellId = bodyIds[hit.bodyIndex];
      if (cellId === undefined) continue;
      const cell = this.cells.find((c) => c.id === cellId && !c.dead);
      if (!cell) continue;
      if (hit.kind === SPECIES.TOXIN) {
        cell.waste +=
          cell.damage(hit.amount * COMBAT.toxin_damage_per_unit, hit.angle, hit.owner) +
          hit.amount;
        cell.deathHint = 'Membrane failed after toxin exposure';
        if (hit.owner === this.player.id) {
          this.evolution.record('toxin', hit.amount * COMBAT.toxin_damage_per_unit);
        }
      } else if (hit.kind === SPECIES.TAG || hit.kind === SPECIES.PORE || hit.kind === SPECIES.ANTITOXIN) {
        cell.acceptSurface(hit.kind, hit.amount, hit.angle, hit.owner);
      }
    }

    // 4. Decoy hits
    for (let i = 0; i < decoyInputs.length && i < receipts.decoyHits.length; i++) {
      const count = receipts.decoyHits[i];
      if (count <= 0) continue;
      const desc = decoyInputs[i];
      const cell = this.cells.find((c) => c.id === desc.cellId && !c.dead);
      if (!cell) continue;
      const organ = cell.organById(desc.organId);
      if (!organ) continue;
      organ.blocked = clamp(organ.blocked + count * 0.65, 0, 1);
      cell.renderRevision++;
    }
  }

  private enqueueCellSignal(
    cell: Cell,
    organ: Organ | null,
    mode: string,
    payload: { id: number; lineage: number; at: Vec2; score: number; expiresAt: number },
  ): void {
    const start = organ ? cell.localPoint(organ.a) : { x: 0, y: 0 };
    const incumbent =
      cell.targetMemory > 0 &&
      (organ ? organ.id : -1) === cell.targetOrganId &&
      mode === cell.targetMode &&
      payload.id === cell.targetId;
    const score = payload.score * (incumbent ? 1.2 : 1.0);
    cell.signals.push({
      organId: organ ? organ.id : -1,
      mode,
      id: payload.id,
      lineage: payload.lineage,
      at: { ...payload.at },
      p: { x: start.x * 0.75, y: start.y * 0.75 },
      score,
      sampleAt: this.time,
      expiresAt: payload.expiresAt,
    });
  }

  private acceptSignal(cell: Cell, packet: Cell['signals'][0]): boolean {
    const incomingPrio = behaviorPriority(cell, packet.mode);
    const heldPrio = behaviorPriority(cell, cell.targetMode);
    if (incomingPrio <= 0) return false;
    if (cell.targetMemory <= 0) return true;
    if (incomingPrio !== heldPrio) return incomingPrio > heldPrio;
    if (
      packet.organId === cell.targetOrganId &&
      packet.id === cell.targetId &&
      packet.mode === cell.targetMode
    ) {
      return packet.sampleAt >= cell.targetSampleAt;
    }
    return packet.score > cell.targetScore * 1.2;
  }

  private stepLocalSignals(cell: Cell, dt: number): void {
    updateBehaviorLatches(cell);
    cell.targetMemory = Math.max(0, cell.targetMemory - dt);

    // Acid stress flee trigger (local acidity field)
    const acidHere = this.acidity.sample(cell.position.x, cell.position.y);
    if (acidHere >= 0.5 || cell.acidStress >= 0.25) {
      const sensing = cell.organs.find((o) => o.kind === 'sensing' && o.hp > 0);
      if (sensing) {
        const s = 64.0;
        const gx =
          this.acidity.sample(cell.position.x + s, cell.position.y) -
          this.acidity.sample(cell.position.x - s, cell.position.y);
        const gy =
          this.acidity.sample(cell.position.x, cell.position.y + s) -
          this.acidity.sample(cell.position.x, cell.position.y - s);
        const gl = Math.hypot(gx, gy);
        const dir = gl > 1e-6 ? { x: -gx / gl, y: -gy / gl } : { x: Math.cos(cell.angle + Math.PI), y: Math.sin(cell.angle + Math.PI) };
        this.enqueueCellSignal(cell, sensing, 'acid', {
          id: -2,
          lineage: -1,
          at: { x: cell.position.x + dir.x * 120, y: cell.position.y + dir.y * 120 },
          score: 100.0 * (1 + acidHere),
          expiresAt: this.time + 0.6,
        });
      }
    }

    // Wounded reflex evade trigger
    if (cell.behavior.woundedUntil > this.time) {
      const mover = cell.organs.find(
        (o) =>
          o.hp > 0 &&
          (o.kind === 'propulsion' || o.kind === 'cilia' || o.kind === 'sensing' || o.kind === 'hunting'),
      );
      if (mover) {
        const away = cell.behavior.woundDirection;
        this.enqueueCellSignal(cell, mover, 'evade', {
          id: -3,
          lineage: -1,
          at: { x: cell.position.x - away.x * 140, y: cell.position.y - away.y * 140 },
          score: 90.0,
          expiresAt: cell.behavior.woundedUntil,
        });
      }
    }

    // Light sensing trigger
    for (const o of cell.organs) {
      if (o.kind !== 'photosynthesis' || o.hp <= 0) continue;
      const receptor = cell.organPosition(o);
      const light = this.lightAt(receptor);
      let sign = 1.0;
      if (o.mutation === 'shade_leaf') {
        if (light >= 0.35 && light <= 0.45) continue;
        if (light > 0.45) sign = -1.0;
      } else if (light >= 0.98) {
        continue;
      }
      const dir = this.lightDir(receptor);
      if (dir.x * dir.x + dir.y * dir.y < 1e-6) continue;
      this.enqueueCellSignal(cell, o, 'light', {
        id: -4,
        lineage: -1,
        at: { x: cell.position.x + dir.x * sign * 160, y: cell.position.y + dir.y * sign * 160 },
        score: 25.0,
        expiresAt: this.time + 0.5,
      });
    }

    // Advance internal signal packets to cell center
    const speed = 220.0 + cell.radius * 2.0;
    const kept: Cell['signals'] = [];
    for (const sig of cell.signals) {
      if (sig.expiresAt <= this.time) continue;
      const dist = Math.hypot(sig.p.x, sig.p.y);
      if (dist <= 5.0 || dist <= speed * dt) {
        if (this.acceptSignal(cell, sig)) {
          cell.targetMode = sig.mode;
          cell.targetOrganId = sig.organId;
          cell.targetId = sig.id;
          cell.targetScore = sig.score;
          cell.targetSampleAt = sig.sampleAt;
          cell.targetMemory = Math.min(1.2, sig.expiresAt - this.time);
          cell.targetPosition = { ...sig.at };
        }
      } else {
        const s = Math.max(0, dist - speed * dt) / dist;
        sig.p.x *= s;
        sig.p.y *= s;
        kept.push(sig);
      }
    }
    cell.signals = kept;

    // Resolve target direction and state readout
    if (cell.targetMemory > 0 && behaviorPriority(cell, cell.targetMode) > 0) {
      const organ = cell.organById(cell.targetOrganId);
      const d = offsetVec(cell.position, cell.targetPosition);
      const dl = Math.hypot(d.x, d.y);
      if (dl > 1e-4) {
        let dir = { x: d.x / dl, y: d.y / dl };
        if (cell.targetMode === 'flee' || cell.targetMode === 'evade') {
          const esc = escapeDirection(dir, cell.behavior.familyCues, cell, this.time);
          dir = esc.direction;
        } else if (cell.targetMode === 'kin_away') {
          dir = { x: -dir.x, y: -dir.y };
        }
        cell.target = dir;
        cell.facing = dir;
        cell.driveActive = true;
        cell.targetMouth =
          cell.targetMode === 'hunt'
            ? cell.feedingAxis(organ ? organ.a : 0)
            : organ
              ? organ.a
              : 0;
        cell.state =
          cell.targetMode === 'flee' || cell.targetMode === 'evade' || cell.targetMode === 'toxin' || cell.targetMode === 'acid'
            ? 'ESCAPING DANGER'
            : cell.targetMode === 'hunt'
              ? 'HUNTING PREY'
              : cell.targetMode === 'graze'
                ? 'FORAGING FOOD'
                : cell.targetMode === 'light'
                  ? 'SEEKING LIGHT'
                  : cell.targetMode === 'kin_toward'
                    ? 'APPROACHING FAMILY'
                    : 'SPREADING FROM FAMILY';
        return;
      }
    }

    const fb = fallbackBehavior(cell, this.seedValue);
    cell.target = fb.direction;
    cell.facing = fb.direction.x * fb.direction.x + fb.direction.y * fb.direction.y > 0.01 ? fb.direction : cell.facing;
    cell.driveActive = false;
    cell.state = fb.state;
  }

  private clearReceptors(cell: Cell, dt: number): void {
    cell.updatePowerState();
    let repairCount = 0;
    for (const o of cell.organs) if (o.kind === 'regenerative' && o.hp > 0) repairCount++;
    for (const o of cell.organs) {
      if (o.blocked <= 0) continue;
      o.blocked = Math.max(0, o.blocked - dt * 0.045);
      const cleared = Math.min(o.blocked, dt * 0.18 * (1 + repairCount * 1.5) * cell.workCapacity());
      cell.spendEnergy(cleared * 1.2, o, 'receptor cleaning');
      o.blocked = Math.max(0, o.blocked - cleared);
    }
  }

  private suctionCell(cell: Cell, dt: number): void {
    cell.updatePowerState();
    for (const organ of cell.organs) {
      if ((organ.kind !== 'feeding' && organ.kind !== 'cilia') || organ.hp <= 0) continue;
      const ciliary = organ.kind === 'cilia';
      if (!ciliary && !cell.oralPumping(organ)) continue;
      const cost = dt * (ciliary ? CILIA_PUMP : PUMP_UPKEEP) * organ.scale * organ.scale;
      const health = organ.maxHp > 0 ? organ.hp / organ.maxHp : 1;
      const power =
        (ciliary ? CILIA_FLOW : ORAL_FLOW) * organ.scale * health * cell.genesFactor(organ, 'suction');
      const cap = cell.workCapacity(cost);
      cell.spendEnergy(cost * cap, organ, 'pumping');
      cell.spendWork(dt * cap, organ, 'pumping');
      if (!ciliary) continue; // Oral groove is particle attractor on GPU
      const n = cell.organNormal(organ);
      const c = Math.cos(cell.angle);
      const s = Math.sin(cell.angle);
      const op = cell.organPosition(organ);
      const atX = op.x + (n.x * c - n.y * s) * 8;
      const atY = op.y + (n.x * s + n.y * c) * 8;
      this.fluid.suction(cell, atX, atY, CILIA_REACH * Math.sqrt(organ.scale), power * cap, dt, cell.target);
    }
  }

  private acidStressCell(cell: Cell, dt: number): void {
    if (cell.unattendedProtected) return;
    const exposure = this.acidity.sample(cell.position.x, cell.position.y);
    const demand = Math.max(0, exposure - 0.4) * dt * 5.0 * cell.growthScale();
    const spent = cell.spendEnergy(demand, null, 'acid stress');
    const overload = Math.max(0, exposure - 0.5) * 0.8 + ((demand - spent) * 0.15) / Math.max(dt, 1e-5);
    cell.acidStress = clamp(cell.acidStress + (overload - 0.12) * dt, 0, 1);
    if (cell.acidStress > 0.6) {
      cell.health = Math.max(0, cell.health - dt * (cell.acidStress - 0.6) * 8.0);
      cell.deathHint = 'Acid stress overwhelmed the membrane';
    }
  }

  private metabolizeCell(cell: Cell, dt: number): void {
    stepLifecyclePhysiology(this, cell, dt);
    cell.reserveActivity = Math.max(0, cell.reserveActivity - dt);

    if (cell.energy < 12) cell.behavior.burnReserves = true;
    else if (cell.energy >= 18) cell.behavior.burnReserves = false;

    if (cell.behavior.burnReserves) {
      const maint = BASAL_UPKEEP * cell.growthScale();
      const rate = Math.max(0.5 * cell.growthScale(), maint + 0.25 * cell.growthScale());
      cell.behavior.reserveElapsed += dt;
      if (cell.behavior.reserveElapsed >= 0.5) {
        const elapsed = cell.behavior.reserveElapsed;
        cell.behavior.reserveElapsed = 0;
        const used = Math.min(
          cell.biomass * RESERVE_ATP,
          Math.min(Math.max(0, 18 - cell.energy), elapsed * rate),
        );
        if (used > 0) cell.burnBiomass(used / RESERVE_ATP);
      }
    } else {
      cell.behavior.reserveElapsed = 0;
    }

    this.flushReserveProducts(cell, false);
    cell.chemistry.advance(cell, dt);
    cell.advanceSurface(
      dt,
      (amount, localAngle) => {
        const c = Math.cos(cell.angle);
        const s = Math.sin(cell.angle);
        const lp = cell.localPoint(localAngle);
        this.spawnParticle(
          SPECIES.WASTE,
          { x: cell.position.x + lp.x * c - lp.y * s, y: cell.position.y + lp.x * s + lp.y * c },
          { x: 0, y: 0 },
          amount,
          cell.id,
        );
      },
      () => {},
    );
    cell.decayEnergy(dt);
    cell.spendEnergy(dt * BASAL_UPKEEP * cell.growthScale(), null, 'maintenance');

    const receptor = cell.organById(cell.targetOrganId);
    if (receptor && isReceptorKind(receptor.kind) && receptor.hp > 0 && cell.driveActive && cell.targetMemory > 0) {
      cell.spendWork(dt, receptor, 'sensing');
    }

    if (cell.energy <= 0) {
      const before = cell.starvationSeconds;
      cell.starvationSeconds += dt;
      const starvingDt =
        Math.max(0, cell.starvationSeconds - 300.0) - Math.max(0, before - 300.0);
      if (!cell.unattendedProtected && starvingDt > 0) {
        cell.health = Math.max(0, cell.health - starvingDt * 0.1);
        cell.deathHint = 'Prolonged starvation; no usable food or ATP reserves remained';
      }
    } else {
      cell.starvationSeconds = Math.max(0, cell.starvationSeconds - dt * 4.0);
    }
  }

  private emitAndAttackCell(cell: Cell, dt: number): void {
    cell.updatePowerState();
    fillToxinSacs(cell, dt);

    cell.emissionClock -= dt;
    while (cell.emissionClock <= 0) {
      cell.emissionClock += 1.0 / PHEROMONE_RATE;
      this.emitPheromone(cell);
    }

    for (const organ of cell.organs) {
      const kind =
        organ.kind === 'feeding'
          ? SPECIES.ENZYME
          : organ.kind === 'neutralizing'
            ? SPECIES.ANTITOXIN
            : organ.kind === 'acidifying'
              ? SPECIES.ACID
              : organ.kind === 'regenerative'
                ? SPECIES.BUFFER
                : -1;
      if (kind < 0 || organ.hp <= 0 || cell.biomass < 0.06) continue;
      const rate = kind === SPECIES.ENZYME ? 0.35 : 2.0;
      const secRate = rate * organ.scale * organ.scale * cell.genesFactor(organ, 'secretion');
      const energyCost =
        SECRETION_COST * cell.genesFactor(organ, 'secretion_cost') +
        ((organ.kind === 'feeding' ? 0 : 0.35) * organ.scale * organ.scale) / Math.max(1e-6, secRate);
      const cap = cell.workCapacity(energyCost);
      const prob = 1.0 - Math.exp(-secRate * cap * dt);
      if (this.rng.randf() >= prob) continue;
      if (!this.isSecretionNeeded(cell, organ, kind)) continue;
      if (cell.biomass < 0.06 + Math.max(0, energyCost - cell.energy) / RESERVE_ATP) continue;

      cell.biomass -= 0.06;
      cell.spendEnergy(energyCost, organ, 'secretion');
      const n = cell.organNormal(organ);
      const c = Math.cos(cell.angle);
      const s = Math.sin(cell.angle);
      const dir = { x: n.x * c - n.y * s, y: n.x * s + n.y * c };
      const op = cell.organPosition(organ);
      const disp = 18.0 * cell.genesFactor(organ, 'dispersal');
      const secretCap =
        kind === SPECIES.ACID
          ? COMBAT.acid_secretion_capacity
          : kind === SPECIES.BUFFER
            ? 0.25
            : 0.06;
      this.spawnParticle(
        kind,
        { x: op.x + dir.x * 10, y: op.y + dir.y * 10 },
        { x: dir.x * disp, y: dir.y * disp },
        0.06,
        cell.id,
        secretCap,
      );
      organ.chargeFlash = 1.0;
      cell.emitted(organ);
      if (cell === this.player && kind === SPECIES.ACID) this.evolution.record('acid', 0.06);
    }

    if (cell.health < 90 && cell.biomass > 0.08 && this.rng.randf() < 1.0 - Math.exp(-0.6 * dt)) {
      cell.biomass -= 0.08;
      const a = this.rng.randf() * TAU;
      const dir = { x: Math.cos(a), y: Math.sin(a) };
      this.spawnParticle(
        SPECIES.TOXIN,
        { x: cell.position.x + dir.x * (cell.radius + 12), y: cell.position.y + dir.y * (cell.radius + 12) },
        { x: dir.x * 24, y: dir.y * 24 },
        0.08,
        this.attackOwner(cell, false),
      );
    }

    const sated = isCellSated(cell);
    for (const organ of cell.organs) {
      if (
        (organ.kind !== 'toxin' && organ.kind !== 'poreforming' && organ.kind !== 'counterattack') ||
        organ.hp <= 0
      ) {
        continue;
      }
      const burst = organ.scale * organ.scale * cell.genesFactor(organ, 'burst');
      const energyCost =
        2.0 * burst +
        0.75 * cell.genesFactor(organ, 'cooldown') * (0.35 * organ.scale * organ.scale);
      const cap = cell.workCapacity(energyCost);
      organ.burstClock = Math.max(0, organ.burstClock - dt * cap);

      let aim: Vec2 | null = null;
      const op = cell.organPosition(organ);
      if (organ.kind === 'counterattack') {
        const det = organ.counterReport;
        if (!det || det.expiresAt <= this.time || !det.report.hostile) continue;
        const d = offsetVec(op, det.report.at);
        const dl = Math.hypot(d.x, d.y);
        if (dl > 0.1) aim = { x: d.x / dl, y: d.y / dl };
      } else {
        if (sated) continue;
        const cue = cell.behavior.weaponCue;
        const rec = cue ? cell.organById(cue.organId) : undefined;
        if (!cue || cue.expiresAt <= this.time || !rec || rec.hp <= 0 || cue.lineage === cell.lineageId()) {
          continue;
        }
        const d = offsetVec(op, cue.at);
        const dl = Math.hypot(d.x, d.y);
        if (dl > 0.1) aim = { x: d.x / dl, y: d.y / dl };
      }

      if (!aim || organ.burstClock > 0) continue;
      if (cell.biomass < 0.18 * burst + Math.max(0, energyCost - cell.energy) / RESERVE_ATP) continue;

      cell.spendEnergy(energyCost, organ, 'combat');
      const source = this.attackOwner(cell, organ.kind === 'counterattack');
      if (organ.kind === 'poreforming') {
        this.emitAimed(SPECIES.TAG, op, aim, 155, 0.03 * burst, source);
        for (let u = 0; u < 4; u++) {
          this.emitAimed(SPECIES.PORE, op, aim, 155 + u * 4, 0.0375 * burst, source);
        }
      } else if (organ.kind === 'counterattack') {
        this.emitAimed(SPECIES.TOXIN, op, aim, 170, 0.18 * burst, source);
      } else {
        this.emitAimed(SPECIES.DECOY, op, aim, 145, 0.03 * burst, source);
        this.emitAimed(SPECIES.TOXIN, op, aim, 170, 0.15 * burst, source);
      }
      cell.biomass -= 0.18 * burst;
      organ.consumeFlash = 1.0;
      cell.emitted(organ);
      organ.burstClock = 0.75 * cell.genesFactor(organ, 'cooldown');
    }
  }

  private isSecretionNeeded(cell: Cell, organ: Organ, kind: number): boolean {
    if (kind === SPECIES.BUFFER) {
      const pos = cell.organPosition(organ);
      return this.acidity.sample(pos.x, pos.y) > 0.4 || cell.acidStress > 0.03;
    }
    if (kind !== SPECIES.ENZYME && kind !== SPECIES.ANTITOXIN) return true;
    if (this.useGpuParticles) {
      return this.secretionNeeded.has(`${cell.id}:${organ.id}`);
    }
    const at = cell.organPosition(organ);
    const reachSq = 140 * 140 * organ.scale;
    for (const p of this.cpuParticles) {
      if (!p.alive) continue;
      if (kind === SPECIES.ENZYME && p.kind !== SPECIES.WASTE) continue;
      if (
        kind === SPECIES.ANTITOXIN &&
        p.kind !== SPECIES.TOXIN &&
        p.kind !== SPECIES.TAG &&
        p.kind !== SPECIES.PORE
      ) {
        continue;
      }
      const d = offsetVec(at, p.p);
      if (d.x * d.x + d.y * d.y <= reachSq) return true;
    }
    return false;
  }

  private motionCell(cell: Cell, localDt: number): void {
    cell.updatePowerState();
    const prevPos = { ...cell.position };
    const beforeVel = { ...cell.velocity };
    const beforeTurn = cell.angularVelocity;
    let steeringPower = 0;
    let driftX = 0;
    let driftY = 0;
    const tLenSq = cell.target.x * cell.target.x + cell.target.y * cell.target.y;

    if (tLenSq >= 0.0001) {
      const syn = cell.synergy();
      const synPow = syn === 'hunter' || syn === 'parasite' ? 1.15 : 1.0;
      const synCost = syn === 'hunter' || syn === 'parasite' ? 0.75 : 1.0;
      const c = Math.cos(cell.angle);
      const s = Math.sin(cell.angle);

      for (const organ of cell.organs) {
        if (organ.hp <= 0) continue;
        const pursuing =
          (organ.kind === 'hunting' || organ.kind === 'photosynthesis') &&
          organ.id === cell.targetOrganId &&
          cell.driveActive &&
          cell.targetMemory > 0 &&
          (cell.targetMode === 'hunt' || cell.targetMode === 'light');
        if (organ.kind !== 'propulsion' && organ.kind !== 'cilia' && !pursuing) continue;

        const basePower =
          organ.kind === 'propulsion' ? 13000.0 : organ.kind === 'cilia' ? CILIA_THRUST : 1100.0;
        const health = organ.maxHp > 0 ? organ.hp / organ.maxHp : 1;
        let power =
          basePower * organ.scale * organ.scale * health * cell.genesFactor(organ, 'thrust');
        let cost =
          localDt *
          (organ.kind === 'cilia' ? CILIA_MOTION : MOTION_UPKEEP) *
          organ.scale *
          organ.scale *
          cell.genesFactor(organ, 'motion_cost');
        const cap = cell.workCapacity(cost);
        power *= cap * synPow;
        cost *= synCost;

        const n = cell.organNormal(organ);
        let tx = n.x * c - n.y * s;
        let ty = n.x * s + n.y * c;
        if ((organ.kind === 'propulsion' || organ.kind === 'cilia') && tx * cell.target.x + ty * cell.target.y < 0) {
          tx = -tx;
          ty = -ty;
        }
        const drag = cell.fluidDrag();
        driftX += (tx * power * SWIM_SPEED_GAIN) / drag;
        driftY += (ty * power * SWIM_SPEED_GAIN) / drag;
        steeringPower += power;
        cell.spendEnergy(cost * cap, organ, 'movement');
        if (organ.kind === 'propulsion') cell.spendWork(localDt * cap, organ, 'movement');
      }
    }

    const response = 1.0 - Math.exp(-localDt / LINEAR_RESPONSE);
    const flow = this.fluid.sample(cell.position.x, cell.position.y);
    cell.velocity.x = flow.x + lerp(cell.velocity.x - flow.x, driftX, response);
    cell.velocity.y = flow.y + lerp(cell.velocity.y - flow.y, driftY, response);

    const armLen = cell.radius * 0.8;
    const armX = Math.cos(cell.angle) * armLen;
    const armY = Math.sin(cell.angle) * armLen;
    const tanX = -armY;
    const tanY = armX;
    const fp = this.fluid.sample(cell.position.x + armX, cell.position.y + armY);
    const fm = this.fluid.sample(cell.position.x - armX, cell.position.y - armY);
    const waterTurn = ((fp.x - fm.x) * tanX + (fp.y - fm.y) * tanY) / (2.0 * (armX * armX + armY * armY));
    let desiredTurn = waterTurn;
    if (steeringPower > 0) {
      const faceAng = Math.atan2(cell.facing.y, cell.facing.x);
      const err = wrapAngle(faceAng - cell.targetMouth - cell.angle);
      desiredTurn += clamp(err * TURN_GAIN, -TURN_SPEED, TURN_SPEED);
    }
    cell.angularVelocity = lerp(cell.angularVelocity, desiredTurn, 1.0 - Math.exp(-localDt / TURN_RESPONSE));
    cell.limitMotion(beforeVel, beforeTurn, localDt);

    cell.angle = wrapAngle(cell.angle + (beforeTurn + cell.angularVelocity) * 0.5 * localDt);
    const dispX = (beforeVel.x + cell.velocity.x) * 0.5 * localDt;
    const dispY = (beforeVel.y + cell.velocity.y) * 0.5 * localDt;
    const contactHelper: ContactHelper = {
      velocityAt: (c, at) => {
        const arm = offsetVec(c.position, at);
        return { x: c.velocity.x - arm.y * c.angularVelocity, y: c.velocity.y + arm.x * c.angularVelocity };
      },
      solveStatic: (c, at, normal, penetration) => {
        const invM = c.activity / c.mass;
        const invI = c.activity / c.inertia;
        const r = offsetVec(c.position, at);
        const va = contactHelper.velocityAt(c, at);
        const closing = -va.x * normal.x - va.y * normal.y;
        const rCrossN = r.x * normal.y - r.y * normal.x;
        const denom = invM + rCrossN * rCrossN * invI;
        if (denom > 0) {
          const e = closing < -6 ? 1.12 : 1.0;
          const imp = Math.max(0, (-closing * e) / denom);
          c.velocity.x -= normal.x * imp * invM;
          c.velocity.y -= normal.y * imp * invM;
          c.angularVelocity -= rCrossN * imp * invI;
        }
        const corr = Math.max(0, penetration - 0.03);
        c.position = wrapPos({ x: c.position.x - normal.x * corr, y: c.position.y - normal.y * corr });
      },
      dent: (c, at, depth) => {
        const cc = c as Cell;
        const off = offsetVec(cc.position, at);
        cc.membrane.compress(Math.atan2(off.y, off.x) - cc.angle, Math.min(depth, cc.radius * 0.075), cc.radius);
      },
    };

    this.habitatGeometry.moveCell(
      cell,
      prevPos,
      wrapPos({ x: prevPos.x + dispX, y: prevPos.y + dispY }),
      localDt,
      contactHelper,
    );

    // Swept cell-cell anti-tunneling
    for (const other of this.cells) {
      if (other === cell || other.dead) continue;
      const start = offsetVec(other.position, prevPos);
      const travel = offsetVec(prevPos, cell.position);
      const travelLen = Math.hypot(travel.x, travel.y);
      if (Math.hypot(start.x, start.y) > cell.extent() + other.extent() + travelLen) continue;
      const dist =
        cell.support(Math.atan2(-start.y, -start.x)) + other.support(Math.atan2(start.y, start.x));
      if (Math.hypot(start.x, start.y) < dist - 0.2 || travelLen * travelLen < 1e-5) continue;
      const a = travelLen * travelLen;
      const b = 2 * (start.x * travel.x + start.y * travel.y);
      const c = start.x * start.x + start.y * start.y - dist * dist;
      const t = clamp(-(start.x * travel.x + start.y * travel.y) / a, 0, 1);
      if (Math.hypot(start.x + travel.x * t, start.y + travel.y * t) < dist) {
        const hit = (-b - Math.sqrt(Math.max(0, b * b - 4 * a * c))) / (2 * a);
        if (hit >= 0 && hit <= 1) {
          cell.position = wrapPos({ x: prevPos.x + travel.x * hit, y: prevPos.y + travel.y * hit });
        }
      }
    }

    cell.limitMotion(beforeVel, beforeTurn, localDt);
  }

  private stepCellMotion(dt: number): void {
    const beforeVel = new Map<number, Vec2>();
    for (const c of this.cells) beforeVel.set(c.id, { ...c.velocity });

    for (let sub = 0; sub < 3; sub++) {
      for (const c of this.cells) {
        if (!c.dead && c.activity > 0) this.motionCell(c, (dt * c.activity) / 3.0);
      }
      for (let iter = 0; iter < 5; iter++) {
        for (let i = 0; i < this.cells.length; i++) {
          const a = this.cells[i];
          if (a.dead) continue;
          for (let j = i + 1; j < this.cells.length; j++) {
            const b = this.cells[j];
            if (b.dead) continue;
            contactPair(a, b, dt / 3.0, iter === 0);
          }
        }
      }
    }

    for (const c of this.cells) {
      const bv = beforeVel.get(c.id) ?? c.velocity;
      const ax = (c.velocity.x - bv.x) / dt;
      const ay = (c.velocity.y - bv.y) / dt;
      const al = Math.hypot(ax, ay);
      if (al > 600) {
        c.shapeAcceleration = { x: (ax / al) * 600, y: (ay / al) * 600 };
      } else {
        c.shapeAcceleration = { x: ax, y: ay };
      }
    }
  }

  step(dt: number, receipts: GpuReceipts | null = null): GpuStepInput {
    this.applyGpuReceipts(receipts);

    this.time += dt;
    this.revision++;

    this.induced.update(this.seedValue, this.time, this.fluid);
    this.fluid.setPlants(this.habitatGeometry);
    this.fluid.step(dt);

    for (const cell of this.cells) {
      cell.previousPosition = { ...cell.position };
      cell.previousAngle = cell.angle;
      cell.activity = cell.dead ? 0 : 1.0;
      if (!cell.dead) {
        cell.age += dt;
        cell.hurtFlash = Math.max(0, cell.hurtFlash - dt * 2.0);
        cell.reactionFlash = Math.max(0, cell.reactionFlash - dt * 2.0);
        this.stepLocalSignals(cell, dt);
        cell.animateResources(dt);
        this.clearReceptors(cell, dt);
        this.suctionCell(cell, dt);
      }
    }

    this.fluid.prepareAttractors(this.cells);

    // Proboscis extraction & post-feed physiology
    this.proboscisContacts.length = 0;
    for (const cell of this.cells) {
      if (cell.dead) continue;
      stepProboscis(cell, this.cells, dt, this.proboscisContacts);
      this.acidStressCell(cell, dt);
      cell.chemistry.lightFlux = 0;
      for (const organ of cell.organs) {
        if (organ.kind === 'photosynthesis' && organ.hp > 0) {
          cell.chemistry.photosynthesize(this, cell, organ, dt);
        }
      }
      this.metabolizeCell(cell, dt);
      cell.heal(dt);
      for (const leak of cell.leaks) {
        const ln = cell.localNormal(leak.a);
        const c = Math.cos(cell.angle);
        const s = Math.sin(cell.angle);
        const nx = ln.x * c - ln.y * s;
        const ny = ln.x * s + ln.y * c;
        const lp = cell.localPoint(leak.a);
        this.emitMaterial(
          SPECIES.NUTRIENT,
          { x: cell.position.x + lp.x * c - lp.y * s + nx * 12, y: cell.position.y + lp.x * s + lp.y * c + ny * 12 },
          leak.amount,
          { x: nx * 12, y: ny * 12 },
          cell.id,
        );
      }
      cell.chemistry.excrete(this, cell, dt);
      cell.updateGeometry();

      // Shed crowded organs if cell shrank
      while (!cell.unattendedProtected && cell.occupied() > cell.perimeter() && cell.organs.length > 0) {
        const idx = cell.organs.length - 1;
        const organ = cell.organs.splice(idx, 1)[0];
        const mat = organ.material + organ.storedToxin;
        const scar = { ...organ, storedToxin: 0 };
        cell.lostOrgans.push(scar);
        this.spawnParticle(SPECIES.WASTE, cell.organPosition(organ), { x: 0, y: 0 }, mat, cell.id);
        cell.updateGeometry();
      }

      // Compute fluid traction for membrane points
      const c = Math.cos(cell.angle);
      const s = Math.sin(cell.angle);
      const rc = Math.cos(-cell.angle);
      const rs = Math.sin(-cell.angle);
      const traction: Vec2[] = [];
      for (const pt of cell.membrane.points) {
        const ax = pt.x * c - pt.y * s;
        const ay = pt.x * s + pt.y * c;
        const fl = this.fluid.sample(cell.position.x + ax, cell.position.y + ay);
        const relX = fl.x - cell.velocity.x + ay * cell.angularVelocity;
        const relY = fl.y - cell.velocity.y - ax * cell.angularVelocity;
        const lx = relX * rc - relY * rs;
        const ly = relX * rs + relY * rc;
        const l = Math.hypot(lx, ly);
        if (l > 90) {
          traction.push({ x: (lx / l) * 90, y: (ly / l) * 90 });
        } else {
          traction.push({ x: lx, y: ly });
        }
      }
      const acc = {
        x: cell.shapeAcceleration.x * rc - cell.shapeAcceleration.y * rs,
        y: cell.shapeAcceleration.x * rs + cell.shapeAcceleration.y * rc,
      };
      cell.membrane.step(dt, cell.radius, acc, cell.age + cell.id * 1.7, traction);
      cell.renderRevision++;
      this.emitAndAttackCell(cell, dt);
    }

    this.stepCellMotion(dt);

    // Check dead cells & lifecycle
    for (const cell of this.cells.slice()) {
      if (!cell.dead && cell.health <= 0) this.die(cell);
    }

    stepAutonomousBuilds(this);
    stepLifecycle(this);

    if (this.time >= this.replaceDue) {
      this.replaceDue = this.time + 0.5;
      this.replenishPopulation();
    }
    this.evolution.advance(dt);

    // Build GPU input batch
    return this.buildGpuStepInput(dt);
  }

  private buildGpuStepInput(dt: number): GpuStepInput {
    const bodies: GpuBodyDesc[] = [];
    const feeds: GpuFeedDesc[] = [];
    const queries: GpuQueryDesc[] = [];
    const decoys: GpuDecoyDesc[] = [];
    const bodyIds: number[] = [];

    for (const cell of this.cells) {
      if (cell.dead || bodies.length >= MAX_LIVE_CELLS) continue;
      const bodyIdx = bodies.length;
      bodyIds.push(cell.id);
      const visualOutline = cell.membrane.outline().map((p) => ({ ...p }));
      const physicalPoints = cell.membrane.points.map((p) => ({ ...p }));
      const gutRoom = Math.max(0, cell.gutCapacity() - cell.substrate);
      const oxygenRoom = Math.max(0, cell.oxygenCapacity() - cell.oxygen);
      const carbonRoom = Math.max(0, cell.carbonCapacity() - cell.carbon);

      bodies.push({
        cell,
        visualOutline,
        physicalPoints,
        gutRoom,
        oxygenRoom,
        carbonRoom,
        hasSurfaceComplexes: cell.surfaceComplexes.some((c) => !c.capped && c.units < 4),
      });

      // Feeds
      if (oxygenRoom > 1e-6 && feeds.length < MAX_FEEDS_PER_TICK) {
        feeds.push({
          centerX: cell.position.x,
          centerY: cell.position.y,
          reach: cell.extent() + 14.0,
          kind: 'oxygen',
          bodyIndex: bodyIdx,
          organId: -1,
          cellId: cell.id,
          capacity: oxygenRoom,
        });
      }
      if (carbonRoom > 1e-6 && feeds.length < MAX_FEEDS_PER_TICK) {
        feeds.push({
          centerX: cell.position.x,
          centerY: cell.position.y,
          reach: cell.extent() + 14.0,
          kind: 'carbon',
          bodyIndex: bodyIdx,
          organId: -1,
          cellId: cell.id,
          capacity: carbonRoom,
        });
      }
      for (const organ of cell.organs) {
        if (organ.kind === 'feeding' && organ.hp > 0 && gutRoom > 1e-6 && feeds.length < MAX_FEEDS_PER_TICK) {
          const pc = cell.poreCenter(organ);
          const poreRadius = 18.0 * organ.scale * cell.genesFactor(organ, 'intake');
          feeds.push({
            centerX: pc.x,
            centerY: pc.y,
            reach: poreRadius + 8.0,
            kind: 'mouth',
            bodyIndex: bodyIdx,
            organId: organ.id,
            cellId: cell.id,
            capacity: gutRoom,
          });
        }
      }

      // Decoys
      const cos = Math.cos(cell.angle);
      const sin = Math.sin(cell.angle);
      for (const organ of cell.organs) {
        if (
          organ.kind !== 'feeding' &&
          organ.kind !== 'sensing' &&
          organ.kind !== 'hunting' &&
          organ.kind !== 'family_toward' &&
          organ.kind !== 'family_away'
        ) {
          continue;
        }
        if (decoys.length >= MAX_DECOYS_PER_TICK) break;
        const pos = cell.organPosition(organ);
        const ln = cell.organNormal(organ);
        decoys.push({
          atX: pos.x,
          atY: pos.y,
          normX: ln.x * cos - ln.y * sin,
          normY: ln.x * sin + ln.y * cos,
          reach: 12.0 * organ.scale,
          bodyIndex: bodyIdx,
          cellId: cell.id,
          organId: organ.id,
        });
      }

      // Sensing queries (staggered every 0.15s)
      cell.senseClock -= dt;
      if (cell.senseClock <= 0) {
        cell.senseClock += 0.15;
        const mass = cell.organicMass();
        for (const organ of cell.organs) {
          if (organ.hp <= 0 || queries.length >= MAX_QUERIES_PER_TICK) continue;
          const op = cell.organPosition(organ);
          const reachMult = Math.sqrt(organ.scale) * cell.sensoryOutput(organ, true);
          if (organ.kind === 'hunting') {
            queries.push({
              atX: op.x,
              atY: op.y,
              reach: 120.0 * reachMult,
              mass,
              cellId: cell.id,
              lineage: cell.lineageId(),
              targetId: cell.targetId,
              mode: QUERY_MODE_CODE.hunt,
              incumbent: cell.targetMemory > 0 && cell.targetOrganId === organ.id ? 1 : 0,
              organId: organ.id,
              cellIndex: bodyIdx,
            });
          } else if (organ.kind === 'sensing') {
            queries.push({
              atX: op.x,
              atY: op.y,
              reach: 90.0 * reachMult,
              mass,
              cellId: cell.id,
              lineage: cell.lineageId(),
              targetId: cell.targetId,
              mode: QUERY_MODE_CODE.flee,
              incumbent: cell.targetMemory > 0 && cell.targetOrganId === organ.id ? 1 : 0,
              organId: organ.id,
              cellIndex: bodyIdx,
            });
            queries.push({
              atX: op.x,
              atY: op.y,
              reach: 90.0 * reachMult,
              mass,
              cellId: cell.id,
              lineage: cell.lineageId(),
              targetId: cell.targetId,
              mode: QUERY_MODE_CODE.danger,
              incumbent: 0,
              organId: organ.id,
              cellIndex: bodyIdx,
            });
          } else if (organ.kind === 'family_toward' || organ.kind === 'family_away') {
            queries.push({
              atX: op.x,
              atY: op.y,
              reach: 90.0 * reachMult,
              mass,
              cellId: cell.id,
              lineage: cell.lineageId(),
              targetId: cell.targetId,
              mode: QUERY_MODE_CODE[organ.kind],
              incumbent: cell.targetMemory > 0 && cell.targetOrganId === organ.id ? 1 : 0,
              organId: organ.id,
              cellIndex: bodyIdx,
            });
          } else if (organ.kind === 'feeding') {
            queries.push({
              atX: op.x,
              atY: op.y,
              reach: 310.0 * reachMult,
              mass: cell.extent() + 22.0,
              cellId: cell.id,
              lineage: cell.lineageId(),
              targetId: cell.targetId,
              mode: QUERY_MODE_CODE.graze,
              incumbent: cell.targetMemory > 0 && cell.targetOrganId === organ.id ? 1 : 0,
              organId: organ.id,
              cellIndex: bodyIdx,
            });
            if (queries.length < MAX_QUERIES_PER_TICK) {
              queries.push({
                atX: op.x,
                atY: op.y,
                reach: 140.0 * Math.sqrt(organ.scale),
                mass,
                cellId: cell.id,
                lineage: cell.lineageId(),
                targetId: -1,
                mode: QUERY_MODE_CODE.waste,
                incumbent: 0,
                organId: organ.id,
                cellIndex: bodyIdx,
              });
            }
          } else if (organ.kind === 'neutralizing') {
            queries.push({
              atX: op.x,
              atY: op.y,
              reach: 140.0 * Math.sqrt(organ.scale),
              mass,
              cellId: cell.id,
              lineage: cell.lineageId(),
              targetId: -1,
              mode: QUERY_MODE_CODE.toxin,
              incumbent: 0,
              organId: organ.id,
              cellIndex: bodyIdx,
            });
          } else if (organ.kind === 'counterattack') {
            queries.push({
              atX: op.x,
              atY: op.y,
              reach: 90.0 * reachMult,
              mass,
              cellId: cell.id,
              lineage: cell.lineageId(),
              targetId: -1,
              mode: QUERY_MODE_CODE.flee,
              incumbent: 0,
              organId: organ.id,
              cellIndex: bodyIdx,
              isCounterAttack: true,
            });
          }
        }
      }
    }

    // Ambient carbon/oxygen schedule (0.25s per group of 20)
    let ambientGasGroup = -1;
    let ambientGasElapsed = 0;
    if (this.time >= this.ambientCarbonDue) {
      const phase = this.ambientCarbonPhase;
      ambientGasElapsed = Math.max(0, this.time - this.ambientCarbonTimes[phase]);
      this.ambientCarbonTimes[phase] = this.time;
      this.ambientCarbonPhase = (phase + 1) % 20;
      this.ambientCarbonDue = this.time + 0.25;
      ambientGasGroup = phase;
    }

    const emissions = this.pendingEmissions.splice(0, MAX_EMISSIONS_PER_TICK);
    this.pendingStepsByRev.set(this.revision, { feeds, queries, bodyIds, decoys });
    for (const rev of [...this.pendingStepsByRev.keys()]) {
      if (rev < this.revision - 8) {
        this.pendingStepsByRev.delete(rev);
      }
    }

    return {
      dt,
      time: this.time,
      revision: this.revision,
      seedValue: this.seedValue,
      stepAcidityField: this.revision % 6 === 0,
      ambientGasGroup,
      ambientGasElapsed,
      bodies,
      feeds,
      queries,
      emissions,
      decoys,
      inspectCursor: { ...this.inspectCursor },
    };
  }

  // Headless CPU particle fallback (used exclusively in automated Node unit tests)
  stepHeadless(dt: number): void {
    const input = this.step(dt, null);
    this.advanceCpuParticles(input);
  }

  private advanceCpuParticles(input: GpuStepInput): void {
    const dt = input.dt;
    for (const q of input.emissions) {
      this.cpuParticles.push({
        id: this.nextCpuParticleId++,
        kind: q.kind,
        p: { x: q.x, y: q.y },
        previous: { x: q.x, y: q.y },
        v: { x: q.vx, y: q.vy },
        angle: q.angle,
        previousAngle: q.angle,
        spin: q.spin,
        amount: q.amount,
        capacity: q.capacity,
        age: 0,
        alive: true,
        owner: q.owner,
        lineage: q.lineage,
        expiresAt: q.expiresAt,
        report: q.report,
      });
    }

    // Transport + unary acidity/decay
    for (const p of this.cpuParticles) {
      if (!p.alive) continue;
      if (p.kind === SPECIES.PHEROMONE && p.expiresAt <= this.time) {
        p.alive = false;
        continue;
      }
      p.previous.x = p.p.x;
      p.previous.y = p.p.y;
      p.previousAngle = p.angle;
      p.age += dt;
      const flow = this.fluid.transportSample(p.p.x, p.p.y, p.kind);
      const diff = p.kind === SPECIES.PHEROMONE ? 240.0 : 12.0;
      const dStd = Math.sqrt(diff * dt);
      p.p = wrapPos({
        x: p.p.x + (p.v.x + flow.x) * dt + this.rng.randNormal(0, dStd),
        y: p.p.y + (p.v.y + flow.y) * dt + this.rng.randNormal(0, dStd),
      });
      if (p.kind !== SPECIES.PHEROMONE) {
        const damp = Math.exp(-0.8 * dt);
        p.v.x *= damp;
        p.v.y *= damp;
        p.angle = wrapAngle(p.angle + p.spin * dt + this.rng.randNormal(0, Math.sqrt(1.2 * dt)));
      }
      if (p.kind === SPECIES.ACID || p.kind === SPECIES.BUFFER) {
        const sgn = p.kind === SPECIES.ACID ? 1 : -1;
        const used = Math.abs(this.acidity.exchange(p.p.x, p.p.y, sgn * Math.min(p.capacity, dt * 0.2)));
        p.capacity = Math.max(0, p.capacity - used);
        if (p.capacity <= 1e-6) p.kind = SPECIES.WASTE;
      }
      if (p.kind !== SPECIES.PHEROMONE) {
        const rate = particleRadius(p.kind) > 0 ? (p.kind === SPECIES.TOXIN ? 0.1 : 0.005) : 0;
        if (this.rng.randf() < 1 - Math.exp(-rate * dt)) {
          this.respirationLoss += p.amount * materialWeight(p.kind);
          p.alive = false;
        }
      }
    }

    if (input.stepAcidityField) {
      this.acidity.step(dt * 6, this.fluid);
    }

    // Simple pair reactions on live CPU particles (for unit testing)
    for (let i = 0; i < this.cpuParticles.length; i++) {
      const a = this.cpuParticles[i];
      if (!a.alive || a.kind === SPECIES.PHEROMONE) continue;
      const ra = particleRadius(a.kind, a.amount);
      for (let j = i + 1; j < this.cpuParticles.length; j++) {
        const b = this.cpuParticles[j];
        if (!b.alive || b.kind === SPECIES.PHEROMONE) continue;
        const d = offsetVec(a.p, b.p);
        const contact = ra + particleRadius(b.kind, b.amount);
        const dSq = d.x * d.x + d.y * d.y;
        if (dSq > contact * contact) continue;
        const dl = Math.sqrt(dSq) || 1;
        const nx = d.x / dl;
        const ny = d.y / dl;
        const acid = this.acidity.sample(a.p.x, a.p.y);
        const thresh = bindingThreshold(a.kind, b.kind, acid);
        const dirAx = Math.cos(a.angle);
        const dirAy = Math.sin(a.angle);
        const dirBx = Math.cos(b.angle);
        const dirBy = Math.sin(b.angle);
        if (dirAx * nx + dirAy * ny >= thresh && dirBx * -nx + dirBy * -ny >= thresh) {
          if (this.reactCpuPair(a, b, acid)) break;
        }
      }
    }

    this.cpuParticles = this.cpuParticles.filter((p) => p.alive);
  }

  private reactCpuPair(a: CpuParticle, b: CpuParticle, acid: number): boolean {
    if (b.kind === SPECIES.ENZYME && a.kind === SPECIES.WASTE) return this.reactCpuPair(b, a, acid);
    if (a.kind === SPECIES.ENZYME && b.kind === SPECIES.WASTE && acid < 0.9) {
      b.kind = SPECIES.NUTRIENT;
      b.capacity = 0;
      this.recycled += b.amount;
      return true;
    }
    if (b.kind === SPECIES.ANTITOXIN && (a.kind === SPECIES.TOXIN || a.kind === SPECIES.TAG || a.kind === SPECIES.PORE)) {
      return this.reactCpuPair(b, a, acid);
    }
    if (a.kind === SPECIES.ANTITOXIN && (b.kind === SPECIES.TOXIN || b.kind === SPECIES.TAG || b.kind === SPECIES.PORE)) {
      a.kind = SPECIES.WASTE;
      a.amount += b.amount;
      b.alive = false;
      return true;
    }
    if ((a.kind === SPECIES.ACID && b.kind === SPECIES.BUFFER) || (a.kind === SPECIES.BUFFER && b.kind === SPECIES.ACID)) {
      const used = Math.min(a.capacity, b.capacity);
      a.capacity -= used;
      b.capacity -= used;
      if (a.capacity <= 1e-6) a.kind = SPECIES.WASTE;
      if (b.capacity <= 1e-6) b.kind = SPECIES.WASTE;
      return true;
    }
    if (b.kind === SPECIES.WASTE && a.kind === SPECIES.OXYGEN) return this.reactCpuPair(b, a, acid);
    if (a.kind === SPECIES.WASTE && b.kind === SPECIES.OXYGEN && b.amount >= a.amount * 0.15 && acid < 0.8) {
      const amt = a.amount;
      a.kind = SPECIES.NUTRIENT;
      a.capacity = 0;
      a.amount = amt * 0.6;
      b.kind = SPECIES.CARBON;
      b.amount = amt * 0.4;
      this.recycled += amt * 0.6;
      return true;
    }
    if (a.kind === SPECIES.TOXIN && b.kind === SPECIES.NUTRIENT) return this.reactCpuPair(b, a, acid);
    if (a.kind === SPECIES.NUTRIENT && b.kind === SPECIES.TOXIN) {
      a.kind = SPECIES.WASTE;
      return true;
    }
    if (
      a.kind === b.kind &&
      (a.kind === SPECIES.NUTRIENT || a.kind === SPECIES.WASTE || a.kind === SPECIES.CARBON || a.kind === SPECIES.OXYGEN) &&
      a.amount + b.amount <= mergeLimit(a.kind)
    ) {
      const total = a.amount + b.amount;
      const t = b.amount / total;
      a.v.x = lerp(a.v.x, b.v.x, t);
      a.v.y = lerp(a.v.y, b.v.y, t);
      a.capacity =
        a.kind === SPECIES.NUTRIENT
          ? nutrientCapacity(a.amount, a.capacity, b.amount, b.capacity, acid)
          : a.capacity + b.capacity;
      a.amount = total;
      b.alive = false;
      return true;
    }
    return false;
  }

  // Helper for initial GPU seeding directly from Simulation's queued emissions
  drainInitialParticles(): QueuedEmission[] {
    return this.pendingEmissions.splice(0, this.pendingEmissions.length);
  }

  // Dummy references to keep type imports useful
  static readonly _unused = { CellChemistry, hash32, particleDiameter, particleScale };
}
