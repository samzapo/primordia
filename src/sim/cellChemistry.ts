import { ECOLOGY } from './catalog.ts';
import { TAU, clamp, wrapAngle, type Vec2 } from './constants.ts';
import { mutationFactor } from './mutations.ts';

export const ACTIVE_SPECIES = ['food', 'waste', 'oxygen', 'carbon'] as const;
export type InternalSpecies = (typeof ACTIVE_SPECIES)[number];

export const MAX_VACUOLES = 12;
export const MAX_GAS = 6;
export const MAX_PACKETS = 36;
export const REACTION_REACH = 20.0;
export const DIGESTION_RATE = 1.8;
export const ENERGY_DENSITY = 40.0;
export const AEROBIC_ATP = ENERGY_DENSITY * 2.25; // 90.0
export const FERMENT_ATP = ENERGY_DENSITY; // 40.0
export const RESERVE_ATP = ENERGY_DENSITY; // 40.0
export const FOOD_FUEL = ENERGY_DENSITY * 18.0; // 720.0
export const TISSUE_FUEL = ENERGY_DENSITY * 7.5; // 300.0
export const RESIDENCE_SECONDS = 10.0;
export const BIOMASS_YIELD = 0.7;

export const LEAF_BIOMASS = 0.035;
export const LEAF_FOOD = 0.965;
export const MAX_LEAF_FIXATION = 0.7;
export const LEAF_ATP_YIELD = 4.0;
export const MIN_LEAF_LIGHT = 0.08;
export const LEAF_SOLAR_WORK = LEAF_BIOMASS * TISSUE_FUEL + LEAF_FOOD * FOOD_FUEL + LEAF_ATP_YIELD;

export interface InternalPacket {
  id: number;
  species: InternalSpecies;
  amount: number;
  fuel: number;
  nutrition: number;
  p: Vec2;
  previousP: Vec2;
  v: Vec2;
  angle: number;
  age: number;
  source: number;
  compartment: number;
  alive: boolean;
}

export function vacuoleVisualRadius(
  species: InternalSpecies,
  amount: number,
  cellRadius = 47.0,
): number {
  const isGas = species === 'oxygen' || species === 'carbon';
  const baseR = isGas
    ? clamp(2.0 + Math.sqrt(Math.max(0, amount)) * 2.0, 2.0, 5.0)
    : clamp(2.6 + Math.sqrt(Math.max(0, amount)) * 3.0, 2.5, 8.5);
  return Math.min(baseR, Math.max(2.0, cellRadius * 0.24));
}

export interface VacuoleSummary {
  id: number;
  p: Vec2;
  species: InternalSpecies;
  contents: number;
  acid: number;
  age: number;
  radius: number;
  angle: number;
  compartment: number;
  food: number;
  waste: number;
}

export interface ChemistryCell {
  id: number;
  position: Vec2;
  angle: number;
  radius: number;
  biomass: number;
  energy: number;
  substrate: number;
  waste: number;
  oxygen: number;
  carbon: number;
  organs: Array<{ id: number; kind: string; a: number; scale: number; hp: number; maxHp: number; mutation: string; photoElapsed: number }>;
  synergy(): string;
  growthScale(): number;
  mitochondrialEfficiency(): number;
  excretionAngle(): number;
  localPoint(a: number): Vec2;
  organPosition(organ: { a: number }): Vec2;
  organNormal(organ: { a: number }): Vec2;
  gainEnergy(amount: number): void;
  spendWork(dt: number, organ: { id: number } | null, category: string): number;
  operatingBudget(): { steady: number };
  atpDecayRate(): number;
  support(localAngle: number): number;
  supportLocal(localAngle: number): number;
}

export interface ChemistryEmitter {
  emitExternal(kindKey: 'nutrient' | 'waste' | 'oxygen' | 'carbon', at: Vec2, vel: Vec2, amount: number, owner: number, capacity?: number): void;
  lightAt(at: Vec2): number;
  investmentStrategy(cell: ChemistryCell): string;
}

export class CellChemistry {
  particles: InternalPacket[] = [];
  nextPacket = 1;
  nextCompartment = 1;
  heat = 0;
  solarWork = 0;
  expelled = 0;
  reactorMass = 0;
  excretionCredit = 0;
  gasCredit = 0;
  lightFlux = 0;
  simulatedTime = 0;

  totals: Record<InternalSpecies, number> = { food: 0, waste: 0, oxygen: 0, carbon: 0 };
  vacuoles: VacuoleSummary[] = [];

  clone(): CellChemistry {
    const c = new CellChemistry();
    c.nextPacket = this.nextPacket;
    c.nextCompartment = this.nextCompartment;
    c.heat = this.heat;
    c.solarWork = this.solarWork;
    c.expelled = this.expelled;
    c.reactorMass = this.reactorMass;
    c.excretionCredit = this.excretionCredit;
    c.gasCredit = this.gasCredit;
    c.lightFlux = this.lightFlux;
    c.simulatedTime = this.simulatedTime;
    c.particles = this.particles.map((p) => ({
      ...p,
      p: { ...p.p },
      previousP: { ...p.previousP },
      v: { ...p.v },
    }));
    c.refresh();
    return c;
  }

  amount(species: InternalSpecies): number {
    return this.totals[species] || 0;
  }

  material(): number {
    return this.totals.food + this.totals.waste + this.totals.carbon;
  }

  syncCell(cell: ChemistryCell): void {
    cell.substrate = this.totals.food;
    cell.waste = this.totals.waste;
    cell.oxygen = this.totals.oxygen;
    cell.carbon = this.totals.carbon;
  }

  refresh(): void {
    this.totals.food = 0;
    this.totals.waste = 0;
    this.totals.oxygen = 0;
    this.totals.carbon = 0;

    const compMap = new Map<number, VacuoleSummary>();
    const gasList: VacuoleSummary[] = [];

    for (const p of this.particles) {
      if (!p.alive || p.amount <= 1e-12) {
        p.alive = false;
        continue;
      }
      this.totals[p.species] += p.amount;
      if (p.species === 'oxygen' || p.species === 'carbon') {
        gasList.push({
          id: p.id,
          p: { ...p.p },
          species: p.species,
          contents: p.amount,
          acid: 0,
          age: p.age,
          radius: 1.4,
          angle: p.angle,
          compartment: p.compartment,
          food: 0,
          waste: 0,
        });
      } else {
        let entry = compMap.get(p.compartment);
        if (!entry) {
          entry = {
            id: p.id,
            p: { ...p.p },
            species: p.species,
            contents: 0,
            acid: 0,
            age: p.age,
            radius: 7.0,
            angle: p.angle,
            compartment: p.compartment,
            food: 0,
            waste: 0,
          };
          compMap.set(p.compartment, entry);
        }
        if (p.species === 'food') {
          entry.food += p.amount;
          entry.species = 'food';
          entry.p = { ...p.p };
        } else {
          entry.waste += p.amount;
        }
        entry.contents = entry.food + entry.waste;
        entry.age = Math.max(entry.age, p.age);
      }
    }

    this.vacuoles.length = 0;
    for (const v of compMap.values()) {
      v.acid = v.contents > 1e-9 ? v.waste / v.contents : 0;
      this.vacuoles.push(v);
    }
    for (const g of gasList) this.vacuoles.push(g);
    this.particles = this.particles.filter((p) => p.alive);
  }

  constrain(cell: ChemistryCell, p: Vec2, r: number): Vec2 {
    const angle = Math.atan2(p.y, p.x);
    const maxR = Math.max(0.5, cell.supportLocal(angle) - r - 2.0);
    const len = Math.hypot(p.x, p.y);
    let x = p.x;
    let y = p.y;
    if (len > maxR && len > 1e-8) {
      x = (x / len) * maxR;
      y = (y / len) * maxR;
    }
    // Exclude nucleus disc while strictly respecting the outer membrane wall
    const nx = -0.12 * cell.radius;
    const ny = -0.1 * cell.radius;
    const nr = Math.min(0.22 * cell.radius + r, Math.max(1.5, maxR * 0.55));
    const dx = x - nx;
    const dy = y - ny;
    const nd = Math.hypot(dx, dy);
    if (nd < nr) {
      if (nd > 1e-6) {
        x = nx + (dx / nd) * nr;
        y = ny + (dy / nd) * nr;
      } else {
        x = nx + nr;
        y = ny;
      }
    }
    const afterMaxR = Math.max(0.5, cell.supportLocal(Math.atan2(y, x)) - r - 2.0);
    const afterLen = Math.hypot(x, y);
    if (afterLen > afterMaxR && afterLen > 1e-8) {
      x = (x / afterLen) * afterMaxR;
      y = (y / afterLen) * afterMaxR;
    }
    return { x, y };
  }

  emit(
    cell: ChemistryCell,
    species: InternalSpecies,
    amount: number,
    localPos: Vec2,
    source = 0,
    compartment = -1,
    fuel = -1,
    nutrition = 0,
  ): number {
    if (amount <= 1e-12) return compartment;
    const comp = compartment > 0 ? compartment : this.nextCompartment++;
    const resolvedFuel =
      fuel >= 0 ? fuel : species === 'food' ? amount * FOOD_FUEL : 0;
    const r = vacuoleVisualRadius(species, amount, cell.radius);
    const constrained = this.constrain(cell, localPos, r);

    // Coalesce if matching packet exists in same compartment, or young packet within 14 units, or over cap
    for (const p of this.particles) {
      if (!p.alive || p.species !== species) continue;
      const sameComp = p.compartment === comp && (species === 'food' || species === 'waste');
      const dSq = (p.p.x - constrained.x) ** 2 + (p.p.y - constrained.y) ** 2;
      const nearYoung = p.age < 1.0 && dSq <= 196.0 && (species === 'oxygen' || species === 'carbon');
      if (sameComp || nearYoung) {
        p.amount += amount;
        p.fuel += resolvedFuel;
        p.nutrition += amount * nutrition;
        if (species === 'food') p.age = Math.min(p.age, 0.5);
        this.refresh();
        return p.compartment;
      }
    }

    const cap = species === 'oxygen' || species === 'carbon' ? MAX_GAS : MAX_VACUOLES;
    const sameSpecies = this.particles.filter((p) => p.alive && p.species === species);
    if (sameSpecies.length >= cap) {
      let target = sameSpecies[0];
      let bestDist = Infinity;
      for (const p of sameSpecies) {
        const dSq = (p.p.x - constrained.x) ** 2 + (p.p.y - constrained.y) ** 2;
        if (dSq < bestDist) {
          bestDist = dSq;
          target = p;
        }
      }
      target.amount += amount;
      target.fuel += resolvedFuel;
      target.nutrition += amount * nutrition;
      this.refresh();
      return target.compartment;
    }

    const speed = Math.max(6.0, cell.radius * 0.22);
    const id = this.nextPacket++;
    const dirAngle = ((id * 2.399963) % TAU) - Math.PI;
    this.particles.push({
      id,
      species,
      amount,
      fuel: resolvedFuel,
      nutrition: amount * nutrition,
      p: constrained,
      previousP: { ...constrained },
      v: { x: Math.cos(dirAngle) * speed, y: Math.sin(dirAngle) * speed },
      angle: dirAngle,
      age: 0,
      source,
      compartment: comp,
      alive: true,
    });
    this.refresh();
    return comp;
  }

  consumeOxygen(amount: number, at: Vec2, reach = REACTION_REACH): number {
    if (amount <= 1e-12) return 0;
    const reachSq = reach * reach;
    let remaining = amount;
    let used = 0;

    // Sort by squared distance
    const oxygens = this.particles
      .filter((p) => p.alive && p.species === 'oxygen')
      .map((p) => ({ p, dSq: (p.p.x - at.x) ** 2 + (p.p.y - at.y) ** 2 }))
      .filter((item) => item.dSq <= reachSq)
      .sort((a, b) => a.dSq - b.dSq);

    for (const item of oxygens) {
      if (remaining <= 1e-12) break;
      const take = Math.min(remaining, item.p.amount);
      item.p.amount -= take;
      remaining -= take;
      used += take;
      if (item.p.amount <= 1e-12) item.p.alive = false;
    }
    if (used > 0) this.refresh();
    return used;
  }

  digestionRate(cell: ChemistryCell, dt: number): number {
    const food = this.amount('food');
    if (food <= 1e-12) return 0;
    const syn = cell.synergy();
    if (syn === 'parasite') return food / Math.max(1e-6, dt);
    if (syn === 'grazer') return 0.2 * cell.growthScale();
    const o2Ratio = clamp(this.amount('oxygen') / Math.max(0.001, food), 0, 1);
    const yieldPerUnit =
      FERMENT_ATP + (AEROBIC_ATP * cell.mitochondrialEfficiency() - FERMENT_ATP) * o2Ratio;
    const demand = Math.max(
      0,
      cell.operatingBudget().steady - cell.atpDecayRate() + (100.0 - cell.energy) / 12.0,
    );
    return Math.min(DIGESTION_RATE * cell.growthScale(), demand / Math.max(1.0, yieldPerUnit));
  }

  advance(cell: ChemistryCell, dt: number): void {
    if (dt <= 0) return;
    this.simulatedTime += dt;

    // 1. Move internal packets
    const substeps = Math.min(64, Math.max(1, Math.ceil(dt / 0.05)));
    const h = dt / substeps;
    const speed = Math.max(6.0, cell.radius * 0.22);
    const outletAngle = cell.excretionAngle();
    const outletBase = cell.localPoint(outletAngle);
    const outletBaseLen = Math.hypot(outletBase.x, outletBase.y) || 1;
    const exitSpeed = Math.max(10.0, cell.radius * 0.4);

    // Track compartments still containing food
    const foodComps = new Set<number>();
    const foodPosByComp = new Map<number, Vec2>();
    for (const p of this.particles) {
      if (p.alive && p.species === 'food') {
        foodComps.add(p.compartment);
        foodPosByComp.set(p.compartment, p.p);
      }
    }

    for (const p of this.particles) {
      if (!p.alive) continue;
      p.previousP.x = p.p.x;
      p.previousP.y = p.p.y;
      p.age += dt;
      if (p.species === 'waste' && foodComps.has(p.compartment)) {
        const fp = foodPosByComp.get(p.compartment)!;
        p.p.x = fp.x;
        p.p.y = fp.y;
        continue;
      }
      const r = vacuoleVisualRadius(p.species, p.amount, cell.radius);
      const isPureExitingWaste =
        p.species === 'waste' && !foodComps.has(p.compartment) && p.age >= RESIDENCE_SECONDS;

      for (let s = 0; s < substeps; s++) {
        if (isPureExitingWaste) {
          const outR = Math.max(0.5, cell.supportLocal(outletAngle) - r - 2.0);
          const ox = Math.cos(outletAngle) * Math.min(outR, outletBaseLen * 0.88);
          const oy = Math.sin(outletAngle) * Math.min(outR, outletBaseLen * 0.88);
          const dx = ox - p.p.x;
          const dy = oy - p.p.y;
          const d = Math.hypot(dx, dy);
          if (d > 1e-4) {
            p.v.x = (dx / d) * exitSpeed;
            p.v.y = (dy / d) * exitSpeed;
          }
        }
        p.p.x += p.v.x * h;
        p.p.y += p.v.y * h;
        const maxR = Math.max(0.5, cell.supportLocal(Math.atan2(p.p.y, p.p.x)) - r - 2.0);
        const len = Math.hypot(p.p.x, p.p.y);
        if (len > maxR && len > 1e-6) {
          const nx = p.p.x / len;
          const ny = p.p.y / len;
          p.p.x = nx * maxR;
          p.p.y = ny * maxR;
          const vn = p.v.x * nx + p.v.y * ny;
          if (vn > 0) {
            p.v.x -= 2 * vn * nx;
            p.v.y -= 2 * vn * ny;
          }
          const vl = Math.hypot(p.v.x, p.v.y) || 1;
          p.v.x = (p.v.x / vl) * speed;
          p.v.y = (p.v.y / vl) * speed;
        }
        // Bounce off nucleus without ever pushing outside membrane wall
        const ncx = -0.12 * cell.radius;
        const ncy = -0.1 * cell.radius;
        const nr = Math.min(0.22 * cell.radius + r, Math.max(1.5, maxR * 0.55));
        const ndx = p.p.x - ncx;
        const ndy = p.p.y - ncy;
        const nd = Math.hypot(ndx, ndy);
        if (nd < nr && nd > 1e-6) {
          const nx = ndx / nd;
          const ny = ndy / nd;
          p.p.x = ncx + nx * nr;
          p.p.y = ncy + ny * nr;
          const vn = p.v.x * nx + p.v.y * ny;
          if (vn < 0) {
            p.v.x -= 2 * vn * nx;
            p.v.y -= 2 * vn * ny;
          }
        }
        const postMaxR = Math.max(0.5, cell.supportLocal(Math.atan2(p.p.y, p.p.x)) - r - 2.0);
        const postLen = Math.hypot(p.p.x, p.p.y);
        if (postLen > postMaxR && postLen > 1e-6) {
          p.p.x = (p.p.x / postLen) * postMaxR;
          p.p.y = (p.p.y / postLen) * postMaxR;
        }
      }
      p.angle = wrapAngle(Math.atan2(p.v.y, p.v.x));
    }

    // 2. Digest food vacuoles
    let budget = this.digestionRate(cell, dt) * dt;
    if (budget > 1e-12) {
      const mitoGain = cell.mitochondrialEfficiency();
      const syn = cell.synergy();
      for (const p of this.particles.slice()) {
        if (!p.alive || p.species !== 'food' || budget <= 1e-12) continue;
        const used = Math.min(budget, p.amount);
        budget -= used;
        const fuel = (p.fuel * used) / p.amount;
        const nutrition = (p.nutrition * used) / p.amount;
        p.amount -= used;
        p.fuel -= fuel;
        p.nutrition -= nutrition;
        if (p.amount <= 1e-12) p.alive = false;

        const aerobic = this.consumeOxygen(used, p.p, REACTION_REACH);
        const anaerobic = used - aerobic;
        const fueled = Math.min(used, fuel / TISSUE_FUEL);
        let tissue = fueled * ((0.7 * aerobic + 0.3 * anaerobic) / used);
        let work = Math.min(
          Math.max(0, fuel - tissue * TISSUE_FUEL),
          fueled * ((AEROBIC_ATP * aerobic + FERMENT_ATP * anaerobic) / used),
        );

        const bonus = clamp(nutrition / used, 0, ECOLOGY.nutrient_bonus_limit);
        if (bonus > 0 && work > 0) {
          const extra = Math.min(work * bonus, Math.max(0, fuel - work));
          const recoveredHeat = Math.max(0, fuel - tissue * TISSUE_FUEL - work);
          if (extra > recoveredHeat) {
            tissue = Math.max(0, tissue - (extra - recoveredHeat) / TISSUE_FUEL);
          }
          work += extra;
        }

        const mitoExtra =
          work * Math.max(0, mitoGain - 1.0) * (aerobic / used) +
          (syn === 'grazer' ? work * 0.15 : 0);
        const maxFromHeat = Math.max(0, fuel - tissue * TISSUE_FUEL - work);
        work += Math.min(mitoExtra, maxFromHeat);

        cell.biomass += tissue;
        cell.gainEnergy(work);
        this.heat += Math.max(0, fuel - tissue * TISSUE_FUEL - work);

        const carbonOut = used * 0.1;
        const wasteOut = Math.max(0, used - tissue - carbonOut);
        if (carbonOut > 1e-9) {
          this.emit(cell, 'carbon', carbonOut, p.p, p.source, -1, 0, 0);
        }
        if (wasteOut > 1e-9) {
          this.emit(cell, 'waste', wasteOut, p.p, p.source, p.compartment, 0, 0);
        }
      }
    }

    this.refresh();
    this.syncCell(cell);
  }

  photosynthesize(
    emitter: ChemistryEmitter,
    cell: ChemistryCell,
    organ: { id: number; kind: string; a: number; scale: number; hp: number; maxHp: number; mutation: string; photoElapsed: number },
    dt: number,
  ): void {
    const rateScale = cell.synergy() === 'producer' ? 1.15 : 1.0;
    organ.photoElapsed += dt * rateScale;
    if (organ.photoElapsed < 0.25) return;
    const stepDt = organ.photoElapsed;
    organ.photoElapsed = 0;

    if (this.totals.carbon <= 1e-7) return;
    const worldAt = cell.organPosition(organ);
    const light = emitter.lightAt(worldAt);
    const geneFactor = mutationFactor(organ.mutation, light >= 0.5 ? 'sun' : 'shade');
    const response = Math.max(MIN_LEAF_LIGHT, light * geneFactor);
    const health = organ.maxHp > 0 ? organ.hp / organ.maxHp : 1;
    const budget = Math.min(MAX_LEAF_FIXATION, 3.5 * response) * organ.scale * organ.scale * health * stepDt;
    if (budget <= 1e-9) return;

    const baseLocal = cell.localPoint(organ.a);
    const site: Vec2 = { x: baseLocal.x * 0.72, y: baseLocal.y * 0.72 };
    const reachSq = 24.0 * 24.0;
    let remaining = budget;
    let used = 0;

    const carbons = this.particles
      .filter((p) => p.alive && p.species === 'carbon')
      .map((p) => ({ p, dSq: (p.p.x - site.x) ** 2 + (p.p.y - site.y) ** 2 }))
      .filter((item) => item.dSq <= reachSq)
      .sort((a, b) => a.dSq - b.dSq);

    for (const item of carbons) {
      if (remaining <= 1e-12) break;
      const take = Math.min(remaining, item.p.amount);
      item.p.amount -= take;
      remaining -= take;
      used += take;
      if (item.p.amount <= 1e-12) item.p.alive = false;
    }

    if (used <= 1e-12) return;

    const strategy = emitter.investmentStrategy(cell);
    const foodShare = strategy === 'producer' || cell.synergy() === 'producer' ? 1.0 : 0.25;
    const totalFood = used * LEAF_FOOD;
    const exportedFood = totalFood * foodShare;
    const internalFood = totalFood - exportedFood;

    if (exportedFood > 1e-9) {
      const normal = cell.organNormal(organ);
      const rotC = Math.cos(cell.angle);
      const rotS = Math.sin(cell.angle);
      const nx = normal.x * rotC - normal.y * rotS;
      const ny = normal.x * rotS + normal.y * rotC;
      emitter.emitExternal(
        'nutrient',
        { x: worldAt.x + nx * 12, y: worldAt.y + ny * 12 },
        { x: nx * 12, y: ny * 12 },
        exportedFood,
        cell.id,
        exportedFood,
      );
    }
    if (internalFood > 1e-9) {
      this.emit(cell, 'food', internalFood, site, cell.id, -1, internalFood * FOOD_FUEL, 0);
    }
    this.emit(cell, 'oxygen', used * 2.5, site, cell.id, -1, 0, 0);
    cell.biomass += used * LEAF_BIOMASS;
    cell.gainEnergy(used * LEAF_ATP_YIELD);
    this.solarWork += used * LEAF_SOLAR_WORK;
    this.lightFlux += used / stepDt;
    cell.spendWork((stepDt * used) / budget, organ, 'photosynthesis');
    this.refresh();
    this.syncCell(cell);
  }

  excrete(emitter: ChemistryEmitter, cell: ChemistryCell, dt: number): void {
    const scale = cell.growthScale();
    this.excretionCredit = Math.min(8.0 * scale, this.excretionCredit + 4.0 * scale * dt);
    this.gasCredit = Math.min(8.0 * scale, this.gasCredit + 6.0 * scale * dt);

    const foodComps = new Set<number>();
    for (const p of this.particles) {
      if (p.alive && p.species === 'food') foodComps.add(p.compartment);
    }

    const outletAngle = cell.excretionAngle();
    const outletBase = cell.localPoint(outletAngle);
    const outletLen = Math.hypot(outletBase.x, outletBase.y) || 1;
    const cos = Math.cos(cell.angle);
    const sin = Math.sin(cell.angle);

    for (const p of this.particles) {
      if (!p.alive) continue;
      const visR = vacuoleVisualRadius(p.species, p.amount, cell.radius);
      if (p.species === 'waste' && !foodComps.has(p.compartment) && p.age >= RESIDENCE_SECONDS) {
        const clampedOut = Math.max(0.5, Math.min(outletLen * 0.88, outletLen - visR - 2.0));
        const ox = (outletBase.x / outletLen) * clampedOut;
        const oy = (outletBase.y / outletLen) * clampedOut;
        const exitTol = Math.max(3.0, cell.radius * 0.12);
        if (Math.hypot(p.p.x - ox, p.p.y - oy) <= exitTol && this.excretionCredit > 0) {
          const drop = Math.min(p.amount, 1.8, this.excretionCredit);
          if (drop > 1e-9) {
            p.amount -= drop;
            this.excretionCredit -= drop;
            this.expelled += drop;
            if (p.amount <= 1e-12) p.alive = false;
            const wx = cell.position.x + (p.p.x * cos - p.p.y * sin);
            const wy = cell.position.y + (p.p.x * sin + p.p.y * cos);
            const dir = Math.atan2(p.p.y, p.p.x) + cell.angle;
            emitter.emitExternal(
              'waste',
              { x: wx, y: wy },
              { x: Math.cos(dir) * 14, y: Math.sin(dir) * 14 },
              drop,
              cell.id,
            );
          }
        }
      } else if ((p.species === 'oxygen' || p.species === 'carbon') && p.amount >= 0.3) {
        const edge = cell.supportLocal(Math.atan2(p.p.y, p.p.x));
        if (Math.hypot(p.p.x, p.p.y) >= Math.max(1.0, edge - visR - 6.0) && this.gasCredit > 0) {
          const drop = Math.min(p.amount, 1.8, this.gasCredit);
          if (drop > 1e-9) {
            p.amount -= drop;
            this.gasCredit -= drop;
            this.expelled += drop;
            if (p.amount <= 1e-12) p.alive = false;
            const wx = cell.position.x + (p.p.x * cos - p.p.y * sin);
            const wy = cell.position.y + (p.p.x * sin + p.p.y * cos);
            const dir = Math.atan2(p.p.y, p.p.x) + cell.angle;
            emitter.emitExternal(
              p.species,
              { x: wx, y: wy },
              { x: Math.cos(dir) * 12, y: Math.sin(dir) * 12 },
              drop,
              cell.id,
            );
          }
        }
      }
    }

    this.refresh();
    this.syncCell(cell);
  }

  partition(parentChem: CellChemistry, fraction: number): void {
    for (const p of parentChem.particles) {
      if (!p.alive || p.amount <= 1e-12) continue;
      const take = p.amount * fraction;
      const fuel = p.fuel * fraction;
      const nutrition = p.nutrition * fraction;
      p.amount -= take;
      p.fuel -= fuel;
      p.nutrition -= nutrition;
      if (p.amount <= 1e-12) p.alive = false;
      this.particles.push({
        id: this.nextPacket++,
        species: p.species,
        amount: take,
        fuel,
        nutrition,
        p: { ...p.p },
        previousP: { ...p.p },
        v: { ...p.v },
        angle: p.angle,
        age: p.age,
        source: p.source,
        compartment: p.compartment,
        alive: true,
      });
      this.nextCompartment = Math.max(this.nextCompartment, p.compartment + 1);
    }
    parentChem.refresh();
    this.refresh();
  }
}
