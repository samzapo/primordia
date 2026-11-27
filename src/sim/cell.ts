import {
  TAU,
  clamp,
  lerp,
  posmod,
  wrapAngle,
  type Vec2,
} from './constants.ts';
import { CellChemistry, RESERVE_ATP, TISSUE_FUEL } from './cellChemistry.ts';
import { EnergyBudget } from './energyBudget.ts';
import { MEMBRANE_COUNT, Membrane } from './membrane.ts';
import { mutationFactor } from './mutations.ts';
import {
  acceptSurfacePacket,
  advanceSurfaceComplexes,
  surfaceMaterial,
  type SurfaceComplex,
} from './surfaceChemistry.ts';
import { TOXIN_SAC_BIOMASS_FLOOR, toxinSacFraction } from './toxinSac.ts';

export const ORGAN_KINDS = [
  'propulsion',
  'protection',
  'poreforming',
  'regenerative',
  'feeding',
  'sensing',
  'photosynthesis',
  'toxin',
  'neutralizing',
  'acidifying',
  'hunting',
  'cilia',
  'mitochondrion',
  'counterattack',
  'toxin_sac',
  'family_toward',
  'family_away',
  'proboscis',
] as const;

export type OrganKind = (typeof ORGAN_KINDS)[number];

export const ORGAN_TITLES: Record<OrganKind, string> = {
  propulsion: 'Flagellum',
  protection: 'Protective cortex',
  poreforming: 'Pore-forming gland',
  regenerative: 'Buffer / repair gland',
  feeding: 'Oral groove',
  sensing: 'Flight receptor',
  photosynthesis: 'Photosynthesis',
  toxin: 'Toxin gland',
  neutralizing: 'Toxin neutralizer',
  acidifying: 'Acid gland',
  hunting: 'Hunting receptor',
  cilia: 'Cilia',
  mitochondrion: 'Mitochondrion',
  counterattack: 'Counterattack gland',
  toxin_sac: 'Toxin sac',
  family_toward: 'Toward family receptor',
  family_away: 'Away from family receptor',
  proboscis: 'Feeding proboscis',
};

export const ORGAN_SUMMARIES: Record<OrganKind, string> = {
  propulsion: 'Strong axial thrust and quick steering torque.',
  protection: 'Absorbs hits across its cortex patch.',
  poreforming: 'Fires surface tags and pore subunits toward a target report.',
  regenerative: 'Repairs membrane and organs, removes pores, and secretes buffer.',
  feeding: 'Pulls nearby food while grazing, absorbs food, and secretes enzyme.',
  sensing: 'Free receptor: flees toxins, high acid, and armed non-family cells.',
  photosynthesis: 'Uses dissolved CO₂ and light to make food, O₂, biomass, and ATP.',
  toxin: 'Fires damaging toxin and receptor-blocking decoys at a target report.',
  neutralizing: 'Secretes antitoxin when chemical threats are nearby.',
  acidifying: 'Secretes acid parcels that boost binding or stress rivals.',
  hunting: 'Free receptor: tracks any non-family pheromone report.',
  cilia: 'Swims gently and pumps local water currents past the cell.',
  mitochondrion: 'Recovers up to 5× ATP from food or biomass with oxygen.',
  counterattack: 'Fires selective toxin at armed cells that spares unarmed cells.',
  toxin_sac: 'Stores toxin from surplus biomass; releases all on death.',
  family_toward: 'Free receptor: swims toward same-family pheromone trails.',
  family_away: 'Free receptor: spreads away from same-family pheromone trails.',
  proboscis: 'Extracts stored biomass as food from touched living cells.',
};

export const ORGAN_COST: Record<OrganKind, number> = {
  propulsion: 8.0,
  protection: 10.0,
  poreforming: 12.0,
  regenerative: 10.0,
  feeding: 8.0,
  sensing: 0.0,
  photosynthesis: 12.0,
  toxin: 12.0,
  neutralizing: 10.0,
  acidifying: 12.0,
  hunting: 0.0,
  cilia: 8.0,
  mitochondrion: 10.0,
  counterattack: 12.0,
  toxin_sac: 10.0,
  family_toward: 0.0,
  family_away: 0.0,
  proboscis: 12.0,
};

export const ORGAN_WIDTH: Record<OrganKind, number> = {
  propulsion: 19.0,
  protection: 34.0,
  poreforming: 26.0,
  regenerative: 27.0,
  feeding: 36.0,
  sensing: 20.0,
  photosynthesis: 30.0,
  toxin: 26.0,
  neutralizing: 26.0,
  acidifying: 26.0,
  hunting: 20.0,
  cilia: 24.0,
  mitochondrion: 0.0,
  counterattack: 24.0,
  toxin_sac: 0.0,
  family_toward: 20.0,
  family_away: 20.0,
  proboscis: 24.0,
};

export const RECEPTOR_KINDS = new Set<string>([
  'sensing',
  'hunting',
  'family_toward',
  'family_away',
]);

export const INTERNAL_ORGANS = new Set<string>(['mitochondrion', 'toxin_sac']);

export const BASELINE_RADIUS = 47.0;
export const BASELINE_VOLUME = 78.0;
export const TISSUE_AREA =
  (MEMBRANE_COUNT * 0.5 * Math.sin(TAU / MEMBRANE_COUNT) * BASELINE_RADIUS * BASELINE_RADIUS) /
  BASELINE_VOLUME;

export const BASAL_UPKEEP = 0.18;
export const MOTION_UPKEEP = 0.2;
export const PUMP_UPKEEP = 0.1;
export const SECRETION_COST = 0.1;
export const CILIA_THRUST = 1800.0;
export const CILIA_MOTION = 0.16;
export const CILIA_PUMP = 0.08;
export const CILIA_REACH = 170.0;
export const CILIA_FLOW = 52.0;
export const ORAL_FLOW = 300.0;

export const LOW_POWER_ATP = 12.0;
export const POWER_RECOVERY_ATP = 18.0;
export const LOW_POWER_CAPACITY = 0.25;
export const ATP_TURNOVER = 0.002;
export const STARVATION_GRACE = 300.0;
export const STARVATION_DAMAGE = 0.1;

export const SWIM_SPEED_GAIN = 1.12;
export const LINEAR_RESPONSE = 0.22;
export const LINEAR_ACCELERATION = 180.0;
export const TURN_GAIN = 1.8;
export const TURN_SPEED = 1.6;
export const TURN_RESPONSE = 0.55;
export const TURN_ACCELERATION = 1.5;

export interface Organ {
  id: number;
  kind: OrganKind;
  a: number;
  mode: string;
  scale: number;
  hp: number;
  maxHp: number;
  material: number;
  maxMaterial: number;
  paidMaterial: number;
  mutation: string;
  blocked: number;
  burstClock: number;
  photoElapsed: number;
  storedToxin: number;
  consumeFlash: number;
  chargeFlash: number;
  emissionAge: number;
  feeding: boolean;
  counterReport: SignalReportEntry | null;
}

export interface SignalReport {
  id: number;
  lineage: number;
  at: Vec2;
  mass: number;
  radius: number;
  hostile: boolean;
  defended: boolean;
  emittedAt: number;
}

export interface SignalReportEntry {
  report: SignalReport;
  distance: number;
  expiresAt: number;
}

export interface Hole {
  a: number;
  size: number;
  stress?: boolean;
}

export interface LeakEvent {
  a: number;
  amount: number;
}

export interface PendingSignal {
  organId: number;
  mode: string;
  id: number;
  lineage: number;
  at: Vec2;
  p: Vec2;
  score: number;
  sampleAt: number;
  expiresAt: number;
}

export interface CellBehaviorState {
  lowEnergy: boolean;
  lowMass: boolean;
  burnReserves: boolean;
  reserveElapsed: number;
  reserveProducts: number;
  woundedUntil: number;
  woundDirection: Vec2;
  weaponCue: (SignalReport & { organId: number; expiresAt: number }) | null;
  familyCues: Map<number, SignalReportEntry>;
  mergeCues: Map<number, SignalReportEntry>;
  crowdedSince: number;
  autolysisCheck: number;
  autolysisAt: number;
  stress: boolean;
  leakElapsed: number;
}

export interface CombatContext {
  sources: Map<number, { source: number; root: number; selective: boolean; noDamage?: boolean }>;
}

export function isReceptorKind(kind: string): boolean {
  return RECEPTOR_KINDS.has(kind);
}

export function isInternalOrgan(kind: string): boolean {
  return INTERNAL_ORGANS.has(kind);
}

export function isOffensiveKind(kind: string): boolean {
  return kind === 'toxin' || kind === 'poreforming' || kind === 'acidifying' || kind === 'proboscis';
}

export function organMaxHp(kind: OrganKind, scale = 1.0, mutation = ''): number {
  const base = kind === 'protection' ? 70.0 : 25.0;
  return base * scale * scale * mutationFactor(mutation, 'health');
}

export function organWidth(organ: Pick<Organ, 'kind' | 'scale'>): number {
  if (isInternalOrgan(organ.kind)) return 0.0;
  return ORGAN_WIDTH[organ.kind] * organ.scale + 4.0;
}

export function organCost(kind: OrganKind, scale = 1.0): number {
  return ORGAN_COST[kind] * scale * scale;
}

export function metabolicUpkeep(organ: { kind: string; scale: number; mutation: string }): number {
  let base = 0.35;
  if (organ.kind === 'feeding') base = 0.0;
  else if (organ.kind === 'photosynthesis' || organ.kind === 'mitochondrion') base = 0.04;
  return (base + mutationFactor(organ.mutation, 'upkeep')) * organ.scale * organ.scale;
}

export function organUpkeepEstimate(organ: Pick<Organ, 'kind' | 'scale' | 'hp' | 'mutation'>): number {
  if (organ.hp <= 0) return 0.0;
  let rate = metabolicUpkeep(organ);
  const s2 = organ.scale * organ.scale;
  if (organ.kind === 'propulsion') {
    rate += MOTION_UPKEEP * s2 * mutationFactor(organ.mutation, 'motion_cost');
  } else if (organ.kind === 'cilia') {
    rate += (CILIA_MOTION + CILIA_PUMP) * s2 * mutationFactor(organ.mutation, 'motion_cost');
  } else if (organ.kind === 'feeding') {
    rate +=
      PUMP_UPKEEP * s2 +
      0.35 * s2 * mutationFactor(organ.mutation, 'secretion') * SECRETION_COST * mutationFactor(organ.mutation, 'secretion_cost');
  } else if (organ.kind === 'regenerative' || organ.kind === 'neutralizing' || organ.kind === 'acidifying') {
    rate +=
      2.0 * s2 * mutationFactor(organ.mutation, 'secretion') * SECRETION_COST * mutationFactor(organ.mutation, 'secretion_cost');
  } else if (organ.kind === 'toxin_sac') {
    rate += 0.04 * s2;
  }
  return rate;
}

export function tissueRadius(volume: number): number {
  return BASELINE_RADIUS * Math.sqrt(Math.max(0, volume) / BASELINE_VOLUME);
}

export class Cell {
  id: number;
  position: Vec2;
  previousPosition: Vec2;
  velocity: Vec2 = { x: 0, y: 0 };
  angle = 0;
  previousAngle = 0;
  angularVelocity = 0;

  body = 60.0;
  biomass = 36.0;
  substrate = 0.0;
  waste = 0.0;
  oxygen = 0.0;
  carbon = 0.0;
  energy = 72.0;
  health = 100.0;
  acidStress = 0.0;
  starvationSeconds = 0.0;
  dead = false;
  deathHint = 'Cell membrane failed';

  role = 'player';
  lineage = 0;
  generation = 0;
  activity = 1.0;
  age = 0.0;

  radius = BASELINE_RADIUS;
  mass = 40.0;
  inertia = 20000.0;

  organs: Organ[] = [];
  lostOrgans: Organ[] = [];
  nextOrganId = 1;
  membrane: Membrane;
  chemistry = new CellChemistry();
  budget = new EnergyBudget();
  surfaceComplexes: SurfaceComplex[] = [];
  holes: Hole[] = [];
  leaks: LeakEvent[] = [];

  target: Vec2 = { x: 0, y: 0 };
  facing: Vec2 = { x: 1, y: 0 };
  threat: Vec2 = { x: 0, y: 0 };
  targetMode = 'explore';
  targetId = -1;
  targetOrganId = -1;
  targetScore = 0;
  targetSampleAt = -1;
  targetMemory = 0;
  targetPosition: Vec2 = { x: 0, y: 0 };
  targetMouth = 0;
  driveActive = false;
  state = 'EXPLORING';

  senseClock = 0;
  emissionClock = 0;
  signals: PendingSignal[] = [];
  shapeAcceleration: Vec2 = { x: 0, y: 0 };

  automaticDivision = true;
  automaticBudding = true;
  reproductionRetryAt = 0;
  investmentRetryAt = 0;
  mergeAfter = 0;

  hurtFlash = 0;
  reactionFlash = 0;
  reserveActivity = 0;
  renderRevision = 0;
  feedingFeedback = '';
  unattendedProtected = false;

  combatContext: CombatContext | null = null;
  private lowPowerLatched = false;

  behavior: CellBehaviorState = {
    lowEnergy: false,
    lowMass: false,
    burnReserves: false,
    reserveElapsed: 0,
    reserveProducts: 0,
    woundedUntil: -10,
    woundDirection: { x: 0, y: 0 },
    weaponCue: null,
    familyCues: new Map(),
    mergeCues: new Map(),
    crowdedSince: -1,
    autolysisCheck: 0,
    autolysisAt: -1,
    stress: false,
    leakElapsed: 0,
  };

  constructor(id = 0, pos: Vec2 = { x: 2048, y: 1280 }, anatomySeed = -1) {
    this.id = id;
    this.lineage = id;
    this.position = { ...pos };
    this.previousPosition = { ...pos };
    this.membrane = new Membrane(this.radius, anatomySeed, true);
    this.updateGeometry();
  }

  lineageId(): number {
    return this.lineage;
  }

  genesFactor(organ: Pick<Organ, 'mutation'>, stat: string): number {
    return mutationFactor(organ.mutation, stat);
  }

  count(kind: OrganKind): number {
    let n = 0;
    for (const o of this.organs) if (o.kind === kind) n++;
    return n;
  }

  working(kind: OrganKind): number {
    let n = 0;
    for (const o of this.organs) if (o.kind === kind && o.hp > 0) n++;
    return n;
  }

  organById(id: number): Organ | undefined {
    return this.organs.find((o) => o.id === id);
  }

  private nonReceptorCount(): number {
    let n = 0;
    for (const o of this.organs) if (!isReceptorKind(o.kind)) n++;
    return n;
  }

  constructionPrice(kind: OrganKind): number {
    if (isReceptorKind(kind)) return 0;
    const n = this.nonReceptorCount();
    if (n < 2) return 0;
    let a = 1;
    let b = 1;
    for (let i = 2; i < n; i++) {
      const next = Math.min(1e15, a + b);
      a = b;
      b = next;
    }
    return a * 10;
  }

  synergy(): '' | 'parasite' | 'hunter' | 'producer' | 'grazer' {
    const hasProb = this.working('proboscis') > 0;
    const hasProp = this.working('propulsion') > 0;
    const hasHunt = this.working('hunting') > 0;
    const hasSens = this.working('sensing') > 0;
    const hasFeed = this.working('feeding') > 0;
    const hasCilia = this.working('cilia') > 0;
    const hasLeaf2 = this.working('photosynthesis') >= 2;
    const hasMito = this.working('mitochondrion') > 0;

    const anyLeaf = this.count('photosynthesis') > 0;
    const anyFeed = this.count('feeding') > 0;
    const anyProb = this.count('proboscis') > 0;
    const anyOffenseCount =
      this.count('poreforming') +
      this.count('toxin') +
      this.count('counterattack') +
      this.count('acidifying');
    const workingWeapon =
      this.working('poreforming') +
      this.working('toxin') +
      this.working('counterattack') +
      this.working('proboscis');

    if (hasProb && hasProp && hasHunt && hasSens && !anyFeed && !anyLeaf && anyOffenseCount === 0) {
      return 'parasite';
    }
    if (
      hasFeed &&
      hasHunt &&
      hasProp &&
      !anyLeaf &&
      this.working('poreforming') + this.working('toxin') + this.working('counterattack') > 0
    ) {
      return 'hunter';
    }
    if (hasLeaf2 && hasMito && workingWeapon === 0 && !anyProb && !anyFeed) {
      return 'producer';
    }
    if (hasFeed && hasCilia && !anyLeaf && workingWeapon === 0 && !anyProb) {
      return 'grazer';
    }
    return '';
  }

  mitochondrialEfficiency(): number {
    let strength = 0;
    for (const o of this.organs) {
      if (o.kind === 'mitochondrion' && o.hp > 0 && o.maxHp > 0) {
        strength += o.scale * o.scale * (o.hp / o.maxHp);
      }
    }
    return 1.0 + Math.min(4.0, strength * 0.5);
  }

  organMass(): number {
    let total = 0;
    for (const o of this.organs) total += o.material + o.storedToxin;
    return total;
  }

  organicMass(): number {
    return (
      this.body +
      this.biomass +
      this.organMass() +
      this.chemistry.material() +
      surfaceMaterial(this) +
      this.behavior.reserveProducts
    );
  }

  storageVolume(spentBiomass = 0): number {
    const syn = this.synergy();
    const tissueFactor = syn === 'grazer' || syn === 'parasite' ? 0.4 : 0.12;
    const foodFactor = syn === 'hunter' ? 0.025 : 0.15;
    const fitted = BASELINE_VOLUME * Math.pow((this.occupied() * 1.1) / (TAU * BASELINE_RADIUS), 2);
    const v =
      this.body +
      Math.max(0, this.biomass - spentBiomass) * tissueFactor +
      this.substrate * foodFactor +
      (this.waste + this.carbon) * 0.08;
    return Math.max(8.0, fitted, v);
  }

  growthScale(): number {
    return Math.pow(Math.max(1.0, this.storageVolume() / BASELINE_VOLUME), 2.0 / 3.0);
  }

  gutCapacity(): number {
    const syn = this.synergy();
    const mult = syn === 'hunter' ? 480.0 : syn === 'grazer' || syn === 'parasite' ? 120.0 : 72.0;
    return mult * this.growthScale();
  }

  oxygenCapacity(): number {
    return 56.0 * this.growthScale();
  }

  carbonCapacity(): number {
    return this.working('photosynthesis') > 0 ? 120.0 * this.growthScale() : 0.0;
  }

  energyReference(): number {
    return 100.0 * this.growthScale();
  }

  atpDecayRate(): number {
    return (ATP_TURNOVER * this.energy * this.energy) / Math.max(1e-6, this.energyReference());
  }

  fluidDrag(): number {
    return (90.0 * this.radius) / BASELINE_RADIUS;
  }

  extent(): number {
    return Math.max(this.radius, this.membrane.maximumRadius);
  }

  surfaceParameter(localAngle: number): number {
    const a = posmod(localAngle, TAU);
    return a;
  }

  localPoint(localAngle: number): Vec2 {
    const phase = (posmod(localAngle, TAU) / TAU) * MEMBRANE_COUNT;
    const i = Math.floor(phase) % MEMBRANE_COUNT;
    const j = (i + 1) % MEMBRANE_COUNT;
    const f = phase - Math.floor(phase);
    const pa = this.membrane.points[i];
    const pb = this.membrane.points[j];
    return { x: lerp(pa.x, pb.x, f), y: lerp(pa.y, pb.y, f) };
  }

  localNormal(localAngle: number): Vec2 {
    const phase = (posmod(localAngle, TAU) / TAU) * MEMBRANE_COUNT;
    const i = Math.floor(phase) % MEMBRANE_COUNT;
    const j = (i + 1) % MEMBRANE_COUNT;
    const pa = this.membrane.points[i];
    const pb = this.membrane.points[j];
    const dx = pb.x - pa.x;
    const dy = pb.y - pa.y;
    const len = Math.hypot(dx, dy);
    if (len < 1e-6) return { x: Math.cos(localAngle), y: Math.sin(localAngle) };
    // Counterclockwise ring points: outward normal is (dy, -dx)
    return { x: dy / len, y: -dx / len };
  }

  organNormal(organ: Pick<Organ, 'kind' | 'a'>): Vec2 {
    return this.localNormal(organ.a);
  }

  organLocalPosition(organ: Pick<Organ, 'kind' | 'a' | 'scale'>): Vec2 {
    const base = this.localPoint(organ.a);
    if (isInternalOrgan(organ.kind)) {
      return { x: base.x * 0.55, y: base.y * 0.55 };
    }
    const n = this.localNormal(organ.a);
    return { x: base.x + n.x * 5 * organ.scale, y: base.y + n.y * 5 * organ.scale };
  }

  organPosition(organ: Pick<Organ, 'kind' | 'a' | 'scale'>): Vec2 {
    const lp = this.organLocalPosition(organ);
    const c = Math.cos(this.angle);
    const s = Math.sin(this.angle);
    return { x: this.position.x + lp.x * c - lp.y * s, y: this.position.y + lp.x * s + lp.y * c };
  }

  excretionAngle(): number {
    const base = Number.isFinite(this.membrane.oralAngle) ? this.membrane.oralAngle : 0.0;
    return wrapAngle(base + Math.PI * 0.85);
  }

  excretionPosition(): Vec2 {
    const lp = this.localPoint(this.excretionAngle());
    const n = this.localNormal(this.excretionAngle());
    const c = Math.cos(this.angle);
    const s = Math.sin(this.angle);
    const lx = lp.x + n.x * 8;
    const ly = lp.y + n.y * 8;
    return { x: this.position.x + lx * c - ly * s, y: this.position.y + lx * s + ly * c };
  }

  feedingAxis(fallbackAngle = 0): number {
    for (const o of this.organs) {
      if (o.kind === 'proboscis' && o.hp > 0) return o.a;
    }
    for (const o of this.organs) {
      if (o.kind === 'feeding' && o.hp > 0) return o.a;
    }
    return fallbackAngle;
  }

  oralReach(organ: Pick<Organ, 'scale'>): number {
    return clamp((110.0 * this.radius) / BASELINE_RADIUS, 48.0, 192.0) * Math.sqrt(organ.scale);
  }

  oralPumping(organ: Pick<Organ, 'kind' | 'id'>): boolean {
    return (
      organ.kind === 'feeding' &&
      this.driveActive &&
      this.targetMode === 'graze' &&
      this.targetOrganId === organ.id &&
      this.substrate < this.gutCapacity() - 1e-6
    );
  }

  poreCenter(organ: Pick<Organ, 'kind' | 'a' | 'scale'>): Vec2 {
    const p = this.localPoint(organ.a);
    const n = this.localNormal(organ.a);
    const c = Math.cos(this.angle);
    const s = Math.sin(this.angle);
    const lx = p.x + n.x * 6 * organ.scale;
    const ly = p.y + n.y * 6 * organ.scale;
    return { x: this.position.x + lx * c - ly * s, y: this.position.y + lx * s + ly * c };
  }

  support(worldAngle: number): number {
    return this.supportLocal(worldAngle - this.angle);
  }

  supportLocal(localAngle: number): number {
    const p = this.localPoint(localAngle);
    return Math.hypot(p.x, p.y);
  }

  visibleSupport(localAngle: number): number {
    const outline = this.membrane.outline();
    if (outline.length === 0) return this.radius;
    const a = posmod(localAngle, TAU);
    // Find ray intersection or nearest angular sample on outline
    const idxFloat = (a / TAU) * outline.length;
    const i = Math.floor(idxFloat) % outline.length;
    const j = (i + 1) % outline.length;
    const f = idxFloat - Math.floor(idxFloat);
    const r0 = Math.hypot(outline[i].x, outline[i].y);
    const r1 = Math.hypot(outline[j].x, outline[j].y);
    return lerp(r0, r1, f);
  }

  perimeter(): number {
    this.membrane.refreshArcs();
    return this.membrane.arcs[MEMBRANE_COUNT] || TAU * this.radius;
  }

  occupied(): number {
    let sum = 0;
    for (const o of this.organs) sum += organWidth(o);
    return sum;
  }

  updateGeometry(): void {
    this.chemistry.syncCell(this);
    const syn = this.synergy();
    this.membrane.cellWall = syn === 'producer';

    let oral = Number.NaN;
    let hunter = Number.NaN;
    let parasite = Number.NaN;
    for (const o of this.organs) {
      if (o.kind === 'feeding') oral = o.a;
      if (syn === 'parasite' && o.kind === 'proboscis' && o.hp > 0) parasite = o.a;
    }
    if (syn === 'hunter' && Number.isFinite(oral)) {
      hunter = oral + Math.PI * 0.5;
    }
    this.membrane.oralAngle = oral;
    this.membrane.hunterAngle = hunter;
    this.membrane.parasiteAngle = parasite;

    const vol = this.storageVolume();
    this.radius = tissueRadius(vol);
    this.mass = Math.max(4.0, (vol + this.organMass() + surfaceMaterial(this)) * 0.45);

    let rotSum = vol * this.radius * this.radius * 0.5;
    for (const o of this.organs) {
      const lp = this.organLocalPosition(o);
      const rSq = lp.x * lp.x + lp.y * lp.y;
      rotSum += o.material * rSq + o.storedToxin * rSq;
    }
    this.inertia = Math.max(50.0, 0.22 * rotSum);
  }

  canFit(kind: OrganKind, _angle: number, size = 1.0, checkBiomass = true): boolean {
    if (size !== 1.0) return false;
    if (kind === 'feeding' && this.count('feeding') >= 1) return false;
    const cost = this.constructionPrice(kind);
    if (checkBiomass && this.biomass < cost) return false;

    const postVolume = this.storageVolume(checkBiomass ? cost : 0);
    const postPerimeter =
      this.perimeter() * Math.sqrt(Math.max(8.0, postVolume) / Math.max(1e-6, this.storageVolume()));

    if (isInternalOrgan(kind)) {
      if (this.count(kind) >= Math.max(1, Math.floor(this.growthScale() * 3))) return false;
      return this.occupied() <= postPerimeter;
    }
    return this.occupied() + organWidth({ kind, scale: size }) <= postPerimeter;
  }

  private makeRoom(newOrgan: Organ): void {
    const ext = this.organs.filter((o) => !isInternalOrgan(o.kind));
    if (ext.length <= 1) return;
    const perim = Math.max(1.0, this.perimeter());
    const minSpacingRad = ext.map((o) => (organWidth(o) / perim) * TAU);
    // Keep newOrgan at its desired angle and push neighbors around it
    ext.sort((a, b) => posmod(a.a - newOrgan.a, TAU) - posmod(b.a - newOrgan.a, TAU));
    const n = ext.length;
    for (let pass = 0; pass < 4; pass++) {
      for (let i = 0; i < n; i++) {
        const cur = ext[i];
        const next = ext[(i + 1) % n];
        const minGap = 0.5 * (minSpacingRad[i] + minSpacingRad[(i + 1) % n]);
        const diff = posmod(next.a - cur.a, TAU);
        if (diff < minGap) {
          const push = minGap - diff;
          if (next === newOrgan) {
            cur.a = wrapAngle(cur.a - push);
          } else {
            next.a = wrapAngle(next.a + push);
          }
        }
      }
    }
  }

  addOrgan(
    kind: OrganKind,
    localAngle: number,
    mode = 'graze',
    paid = true,
    size = 1.0,
  ): boolean {
    if (!this.canFit(kind, localAngle, size, paid)) return false;
    const cost = paid ? this.constructionPrice(kind) : 0.0;
    const tissue = Math.max(organCost(kind, size), cost);
    if (paid) this.biomass = Math.max(0, this.biomass - cost);

    const hpMax = organMaxHp(kind, size, '');
    const organ: Organ = {
      id: this.nextOrganId++,
      kind,
      a: wrapAngle(localAngle),
      mode,
      scale: size,
      hp: hpMax,
      maxHp: hpMax,
      material: tissue,
      maxMaterial: tissue,
      paidMaterial: paid ? cost : 0.0,
      mutation: '',
      blocked: 0,
      burstClock: 0,
      photoElapsed: 0,
      storedToxin: 0,
      consumeFlash: 0,
      chargeFlash: 0,
      emissionAge: -100,
      feeding: false,
      counterReport: null,
    };
    this.organs.push(organ);
    if (!isInternalOrgan(kind)) {
      this.makeRoom(organ);
    }
    this.updateGeometry();
    return true;
  }

  constructionRefund(organ: Organ): number {
    return Math.min(organ.material, organ.paidMaterial) * 0.5 + organ.storedToxin * 0.5;
  }

  recycle(index: number): number {
    if (this.dead || this.unattendedProtected || index < 0 || index >= this.organs.length) {
      return -1;
    }
    const organ = this.organs[index];
    this.organs.splice(index, 1);
    const refund = this.constructionRefund(organ);
    const debris = Math.max(0, organ.material + organ.storedToxin - refund);
    this.biomass += refund;
    if (organ.kind === 'feeding') {
      // Clear center oral cytoskeleton strand if any existed
    }
    this.updateGeometry();
    this.renderRevision++;
    return debris;
  }

  restoreOrgan(identity: number, paid = true): boolean {
    const idx = this.lostOrgans.findIndex((o) => o.id === identity);
    if (idx < 0) return false;
    const scar = this.lostOrgans[idx];
    if (!this.addOrgan(scar.kind, scar.a, scar.mode, paid, scar.scale)) return false;
    this.lostOrgans.splice(idx, 1);
    if (scar.mutation) {
      this.specialize(this.organs[this.organs.length - 1].id, scar.mutation);
    }
    return true;
  }

  specialize(organId: number, gene: string): boolean {
    const organ = this.organById(organId);
    if (!organ) return false;
    if (organ.kind === 'photosynthesis') {
      if (gene !== 'sun_leaf' && gene !== 'shade_leaf') return false;
      organ.mutation = gene;
      this.renderRevision++;
      return true;
    }
    if (organ.mutation) return false;
    organ.mutation = gene;
    const newMax = organMaxHp(organ.kind, organ.scale, gene);
    const ratio = organ.maxHp > 0 ? organ.hp / organ.maxHp : 1;
    organ.maxHp = newMax;
    organ.hp = newMax * ratio;
    this.renderRevision++;
    return true;
  }

  gainEnergy(amount: number): void {
    if (amount <= 0) return;
    this.energy += amount;
    this.budget.record(this.age, amount, amount, 0, -1, 'production');
  }

  decayEnergy(dt: number): void {
    if (this.energy <= 0 || dt <= 0) return;
    const ref = this.energyReference();
    const before = this.energy;
    this.energy = before / (1.0 + ATP_TURNOVER * (before / Math.max(1e-6, ref)) * dt);
    const lost = Math.max(0, before - this.energy);
    if (lost > 0) this.budget.record(this.age, 0, 0, lost, -1, 'turnover');
  }

  updatePowerState(): void {
    if (this.energy < LOW_POWER_ATP) this.lowPowerLatched = true;
    else if (this.energy >= POWER_RECOVERY_ATP) this.lowPowerLatched = false;
  }

  workCapacity(required = 0): number {
    if (this.biomass > 0 && this.energy + this.biomass * RESERVE_ATP + 1e-7 >= required) {
      return 1.0;
    }
    if (this.lowPowerLatched || this.energy < required) {
      return LOW_POWER_CAPACITY;
    }
    return 1.0;
  }

  burnBiomass(quantity: number): number {
    const used = Math.min(quantity, this.biomass);
    if (used <= 1e-12) return 0;
    this.biomass -= used;
    const eff = this.mitochondrialEfficiency();
    const aerobic = eff > 1.0 ? this.chemistry.consumeOxygen(used, { x: 0, y: 0 }, this.radius * 2) : 0;
    const work = RESERVE_ATP * (used + aerobic * (eff - 1));
    this.gainEnergy(work);
    this.chemistry.heat += Math.max(0, used * TISSUE_FUEL - work);
    this.behavior.reserveProducts += used;
    this.reserveActivity = 0.6;
    return work;
  }

  spendEnergy(
    amount: number,
    organ: Pick<Organ, 'id'> | null = null,
    category = 'upkeep',
  ): number {
    if (amount <= 0) return 0;
    if (this.energy < amount && this.biomass > 0) {
      this.burnBiomass((amount - this.energy) / RESERVE_ATP);
    }
    const spent = Math.min(this.energy, amount);
    this.energy -= spent;
    if (spent > 0) {
      this.budget.record(this.age, 0, 0, spent, organ ? organ.id : -1, category);
    }
    return spent;
  }

  spendWork(
    dt: number,
    organ: { id: number; kind: string; scale: number; mutation: string } | null,
    category = 'upkeep',
  ): number {
    if (!organ || dt <= 0) return 0;
    return this.spendEnergy(dt * metabolicUpkeep(organ), organ, category);
  }

  operatingBudget(): { steady: number; categories: Record<string, number> } {
    let steady = BASAL_UPKEEP * this.growthScale() + this.atpDecayRate();
    const cats: Record<string, number> = { maintenance: BASAL_UPKEEP * this.growthScale(), upkeep: 0 };
    for (const o of this.organs) {
      const est = organUpkeepEstimate(o);
      steady += est;
      cats.upkeep += est;
    }
    return { steady, categories: cats };
  }

  sensoryOutput(organ: Organ, activeWork = true): number {
    if (organ.hp <= 0) return 0;
    const block = 1.0 - organ.blocked * 0.65;
    const gene = mutationFactor(organ.mutation, 'sense');
    const cap = activeWork ? 1.0 : 1.0;
    return block * gene * cap;
  }

  emitted(organ: Organ): void {
    organ.emissionAge = this.age;
  }

  animateResources(dt: number): void {
    for (const o of this.organs) {
      o.consumeFlash = Math.max(0, o.consumeFlash - dt * 2.5);
      o.chargeFlash = Math.max(0, o.chargeFlash - dt * 2.0);
    }
  }

  acceptsAttack(source: number): boolean {
    if (!this.combatContext) return true;
    const info = this.combatContext.sources.get(source);
    if (!info) return true;
    if (info.noDamage) return false;
    if (!info.selective) return true;
    for (const o of this.organs) {
      if (o.hp > 0 && isOffensiveKind(o.kind)) return true;
    }
    return false;
  }

  acceptSurface(kind: number, amount: number, worldAngle: number, source: number): boolean {
    return acceptSurfacePacket(this, kind, amount, worldAngle, source, this.angle, () => {
      this.renderRevision++;
    });
  }

  damage(amount: number, worldAngle: number, source = -1): number {
    if (this.dead || this.unattendedProtected || amount <= 0 || !this.acceptsAttack(source)) {
      return 0;
    }
    this.behavior.woundedUntil = this.age + 3.0;
    this.behavior.woundDirection = { x: Math.cos(worldAngle), y: Math.sin(worldAngle) };

    const localAngle = wrapAngle(worldAngle - this.angle);
    const perim = Math.max(1.0, this.perimeter());
    let hitOrgan: Organ | null = null;
    let bestDist = Infinity;

    for (const o of this.organs) {
      if (isInternalOrgan(o.kind) || o.kind === 'feeding' || o.hp <= 0) continue;
      const halfArc = ((organWidth(o) * 0.6) / perim) * TAU;
      const d = Math.abs(wrapAngle(o.a - localAngle));
      if (d <= halfArc && d < bestDist) {
        bestDist = d;
        hitOrgan = o;
      }
    }

    let remaining = amount;
    let lostOrganWaste = 0;

    if (hitOrgan) {
      const absorbed = Math.min(hitOrgan.hp, remaining);
      const frac = hitOrgan.maxHp > 0 ? absorbed / hitOrgan.maxHp : 1;
      const lostMat = Math.min(hitOrgan.material, hitOrgan.maxMaterial * frac);
      hitOrgan.hp -= absorbed;
      hitOrgan.material = Math.max(0, hitOrgan.material - lostMat);
      hitOrgan.paidMaterial = Math.max(0, hitOrgan.paidMaterial - hitOrgan.paidMaterial * frac);
      lostOrganWaste += lostMat;
      remaining -= absorbed;

      if (hitOrgan.hp <= 0.001) {
        const idx = this.organs.indexOf(hitOrgan);
        if (idx >= 0) this.organs.splice(idx, 1);
        lostOrganWaste += hitOrgan.material + hitOrgan.storedToxin;
        hitOrgan.material = 0;
        hitOrgan.storedToxin = 0;
        this.lostOrgans.push(hitOrgan);
      }
    }

    if (remaining > 0) {
      this.health = Math.max(0, this.health - remaining);
      this.hurtFlash = Math.min(1.0, this.hurtFlash + Math.min(0.9, remaining / 25.0));
      const existing = this.holes.find((h) => !h.stress && Math.abs(wrapAngle(h.a - localAngle)) < 0.2);
      if (existing) {
        existing.size = Math.min(1.2, existing.size + remaining / 16.0);
      } else {
        this.holes.push({ a: localAngle, size: Math.min(1.2, remaining / 16.0) });
      }
    }

    this.renderRevision++;
    return lostOrganWaste;
  }

  heal(dt: number): void {
    this.leaks.length = 0;
    let repair = 1.0;
    for (const o of this.organs) {
      if (o.kind === 'regenerative' && o.hp > 0) {
        repair += 2.0 * o.scale * o.scale * mutationFactor(o.mutation, 'repair');
      }
    }
    const repairCost = 1.0;
    const cap = this.workCapacity();

    // Non-stress holes leak and shrink
    const keptHoles: Hole[] = [];
    for (const h of this.holes) {
      if (h.stress) {
        keptHoles.push(h);
        continue;
      }
      if (!this.unattendedProtected) {
        let leak = h.size * 7.0 * dt;
        const fromBiomass = Math.min(this.biomass, leak);
        this.biomass -= fromBiomass;
        leak -= fromBiomass;
        if (leak > 0) {
          const fromBody = Math.min(Math.max(0, this.body - 4.0), leak);
          this.body -= fromBody;
          if (this.body <= 4.01) {
            this.health = 0;
            this.deathHint = 'Membrane ruptured by unhealed damage';
          }
        }
        const totalOut = fromBiomass + leak;
        if (totalOut > 1e-6) {
          this.leaks.push({ a: h.a, amount: totalOut });
        }
      }
      h.size -= dt * 1.1 * (1.0 + (repair - 1.0) * cap);
      if (h.size > 0.02) keptHoles.push(h);
    }
    this.holes = keptHoles;

    if (this.energy > 0 || repair > 1.0) {
      let didRepair = false;
      if (this.health < 100.0 && this.biomass > 0) {
        const healAmt = Math.min(100.0 - this.health, 8.0 * repair * dt * cap, this.biomass / 0.05);
        if (healAmt > 1e-6) {
          this.health += healAmt;
          this.biomass -= healAmt * 0.05;
          this.body += healAmt * 0.05;
          this.spendEnergy(healAmt * 0.2 * repairCost, null, 'repair');
          didRepair = true;
        }
      }
      for (const o of this.organs) {
        if (o.hp >= o.maxHp) continue;
        const unit = o.maxHp > 0 ? o.maxMaterial / o.maxHp : 0;
        const maxByBiomass = unit > 0 ? this.biomass / unit : Infinity;
        const restore = Math.min(o.maxHp - o.hp, dt * 1.3 * repair * cap, maxByBiomass);
        if (restore > 1e-6) {
          o.hp += restore;
          if (unit > 0) {
            this.biomass -= restore * unit;
            o.material += restore * unit;
            o.paidMaterial += restore * unit;
          }
          this.spendEnergy(restore * 0.15 * repairCost, o, 'repair');
          didRepair = true;
        }
      }
      if (didRepair) {
        for (const o of this.organs) {
          if (o.kind === 'regenerative' && o.hp > 0) {
            this.spendWork(dt * cap, o, 'repair');
          }
        }
      }
    }
  }

  advanceSurface(
    dt: number,
    onExpire: (amount: number, localAngle: number) => void,
    onKilledByPore: () => void,
  ): void {
    advanceSurfaceComplexes(this, dt, this.angle, onExpire, onKilledByPore);
  }

  limitMotion(beforeVel: Vec2, beforeTurn: number, dt: number): void {
    const maxDv = LINEAR_ACCELERATION * dt;
    const dvx = this.velocity.x - beforeVel.x;
    const dvy = this.velocity.y - beforeVel.y;
    const dvLen = Math.hypot(dvx, dvy);
    if (dvLen > maxDv && dvLen > 1e-8) {
      const s = maxDv / dvLen;
      this.velocity.x = beforeVel.x + dvx * s;
      this.velocity.y = beforeVel.y + dvy * s;
    }
    const maxDw = TURN_ACCELERATION * dt;
    const dw = this.angularVelocity - beforeTurn;
    if (Math.abs(dw) > maxDw) {
      this.angularVelocity = beforeTurn + Math.sign(dw) * maxDw;
    }
  }

  organStatus(
    organ: Organ,
    time: number,
    lightAt: (at: Vec2) => number,
    sated: boolean,
  ): { label: string; depleted: boolean; progress: number; capacity: number } {
    const result = { label: 'Ready', depleted: false, progress: -1, capacity: 1.0 };
    const kind = organ.kind;
    if (organ.hp <= 0) {
      result.label = 'Damaged';
      return result;
    }
    if (kind === 'photosynthesis') {
      if (this.carbon <= 1e-7) {
        result.label = 'Waiting for CO₂';
        return result;
      }
      const site = this.localPoint(organ.a);
      const sx = site.x * 0.72;
      const sy = site.y * 0.72;
      const hasNearCarbon = this.chemistry.vacuoles.some(
        (v) => v.species === 'carbon' && (v.p.x - sx) ** 2 + (v.p.y - sy) ** 2 <= 24 * 24,
      );
      if (!hasNearCarbon) {
        result.label = 'Waiting for CO₂ to reach the leaf';
        return result;
      }
      const l = lightAt(this.organPosition(organ));
      const g = mutationFactor(organ.mutation, l >= 0.5 ? 'sun' : 'shade');
      if (l * g < 0.08) {
        result.label = 'Collecting diffuse light';
        return result;
      }
      result.label = 'Collecting light';
      result.progress = clamp(organ.photoElapsed / 0.25, 0, 1);
      return result;
    }
    if (kind === 'proboscis') {
      if (sated) {
        result.label = 'Resting · stored meal';
        return result;
      }
      result.label = organ.feeding
        ? 'Feeding · 0.5 ATP / biomass'
        : 'Waiting for contact with a living cell';
      if (this.energy + this.biomass <= 0) {
        result.label = 'Waiting for ATP or reserve biomass';
      } else if (this.substrate >= this.gutCapacity()) {
        result.label = 'Digesting a full meal';
      }
      return result;
    }
    if (kind === 'toxin_sac') {
      result.progress = toxinSacFraction(organ);
      result.capacity = this.workCapacity();
      result.depleted = result.capacity < 1;
      if (result.progress >= 0.999999) result.label = 'Full · releases toxin on death';
      else if (this.biomass <= TOXIN_SAC_BIOMASS_FLOOR) result.label = 'Waiting for surplus biomass';
      else if (result.capacity < 1) result.label = 'Low ATP · 25% filling rate';
      else result.label = 'Storing toxin';
      return result;
    }
    if (kind === 'mitochondrion') {
      const eff = this.mitochondrialEfficiency().toFixed(2);
      const suffix =
        this.substrate <= 1e-7 && this.biomass <= 1e-7
          ? 'Waiting for food'
          : this.oxygen <= 1e-7
            ? 'Waiting for oxygen'
            : 'Recovering energy from food or biomass and oxygen';
      result.label = `${eff}× ATP yield · ${suffix}`;
      return result;
    }
    if (kind === 'toxin' || kind === 'poreforming' || kind === 'counterattack') {
      if (kind !== 'counterattack' && sated) {
        result.label = 'Resting · stored meal';
        return result;
      }
      const burst = organ.scale * organ.scale * mutationFactor(organ.mutation, 'burst');
      const cap = this.workCapacity(2 * burst);
      result.capacity = cap;
      result.depleted = cap < 1;
      if (this.biomass < 0.18 * burst) {
        result.label = 'Waiting for biomass';
        return result;
      }
      if (organ.burstClock > 0) {
        const secs = (organ.burstClock / cap).toFixed(1);
        result.label =
          cap < 1 ? `Low ATP · 25% capacity · recharging ${secs}s` : `Recharging · ${secs}s`;
        result.progress = clamp(
          1 - organ.burstClock / (0.75 * mutationFactor(organ.mutation, 'cooldown')),
          0,
          1,
        );
        return result;
      }
      if (kind === 'counterattack') {
        if (!organ.counterReport || organ.counterReport.expiresAt <= time) {
          result.label = 'Waiting for an armed cell’s chemical signal';
          return result;
        }
      } else {
        const hasSensor = this.organs.some(
          (o) => o.hp > 0 && (o.kind === 'hunting' || (o.kind === 'sensing' && (o.mode === 'hunt' || o.mode === 'flee'))),
        );
        if (!hasSensor) {
          result.label = 'Needs a hunting receptor';
          return result;
        }
        const cue = this.behavior.weaponCue;
        const receptor = cue ? this.organById(cue.organId) : undefined;
        if (!cue || cue.expiresAt <= time || !receptor || receptor.hp <= 0) {
          result.label = 'No eligible chemical target';
          return result;
        }
      }
      result.label = cap < 1 ? 'Low ATP · 25% capacity' : 'Ready';
      result.progress = 1;
      return result;
    }
    if (kind === 'feeding' && !this.oralPumping(organ)) {
      result.label = 'Suction off';
      return result;
    }
    if (
      kind === 'feeding' ||
      kind === 'acidifying' ||
      kind === 'neutralizing' ||
      kind === 'regenerative' ||
      kind === 'propulsion' ||
      kind === 'cilia'
    ) {
      const cap = this.workCapacity();
      result.capacity = cap;
      result.depleted = cap < 1;
      if (
        (kind === 'acidifying' || kind === 'neutralizing' || kind === 'regenerative') &&
        this.biomass < 0.06
      ) {
        result.label = 'Waiting for biomass';
        return result;
      }
      if (cap < 1) {
        result.label = 'Low ATP · 25% capacity';
        return result;
      }
    }
    if (this.age - organ.emissionAge < 0.28) {
      result.label = 'Producing';
    }
    return result;
  }
}
