import {
  FIELD_COUNT,
  GRID_COLS,
  GRID_ROWS,
  GRID_SIZE,
  TAU,
  WORLD_H,
  WORLD_W,
  clamp,
  offsetX,
  offsetY,
  posmod,
  wrapX,
  wrapY,
  type Vec2,
} from './constants.ts';

export const NODE_MASS = 22.0;
export const PLANT_DAMPING = 0.5;
export const MAX_ATTRACTORS = 64;

export interface AttractorCell {
  id: number;
  dead: boolean;
  substrate: number;
  gutCapacity(): number;
  organs: Array<{ kind: string; scale: number; hp: number; maxHp: number; id: number; mutation: string }>;
  oralPumping(organ: { kind: string; id: number }): boolean;
  poreCenter(organ: { kind: string; scale: number }): Vec2;
  oralReach(organ: { scale: number }): number;
  workCapacity(required?: number): number;
  genesFactor(organ: { mutation: string }, stat: string): number;
}

export interface SuctionBody {
  position: Vec2;
  velocity: Vec2;
  angularVelocity: number;
  radius: number;
  mass: number;
  inertia: number;
}

export interface HabitatLike {
  enabled: boolean;
  flowRevision: number;
  plants: Array<{ p: Vec2; radius: number; form: number; angle: number }>;
  forms: Array<{ branches: Array<{ a: Vec2; b: Vec2; r: number; depth: number }> }>;
}

export class Medium {
  readonly velocity = new Float32Array(FIELD_COUNT * 2);
  readonly tide = new Float32Array(FIELD_COUNT * 2);
  readonly plantDrag = new Float32Array(FIELD_COUNT);
  readonly changes = new Float32Array(FIELD_COUNT * 2);

  // Packed (center.x, center.y, reach, power) * MAX_ATTRACTORS
  readonly attractors = new Float32Array(MAX_ATTRACTORS * 4);
  attractorCount = 0;

  driven = true;
  private plantRevision = -1;
  private plantEnabled = false;

  constructor() {
    for (let y = 0; y < GRID_ROWS; y++) {
      for (let x = 0; x < GRID_COLS; x++) {
        const i = y * GRID_COLS + x;
        const c = Medium.baseCurrent((x + 0.5) * GRID_SIZE, (y + 0.5) * GRID_SIZE);
        this.velocity[i * 2] = c.x;
        this.velocity[i * 2 + 1] = c.y;
        this.tide[i * 2] = c.x;
        this.tide[i * 2 + 1] = c.y;
      }
    }
  }

  static index(x: number, y: number): number {
    return posmod(y, GRID_ROWS) * GRID_COLS + posmod(x, GRID_COLS);
  }

  static baseCurrent(px: number, py: number): Vec2 {
    return {
      x: 11.0 + 17.0 * Math.sin((TAU * py * 4.0) / WORLD_H),
      y: 15.0 * Math.sin((TAU * px * 4.0) / WORLD_W),
    };
  }

  sample(px: number, py: number): Vec2 {
    const qx = wrapX(px) / GRID_SIZE - 0.5;
    const qy = wrapY(py) / GRID_SIZE - 0.5;
    const x = Math.floor(qx);
    const y = Math.floor(qy);
    const fx = qx - x;
    const fy = qy - y;
    const i00 = Medium.index(x, y) * 2;
    const i10 = Medium.index(x + 1, y) * 2;
    const i01 = Medium.index(x, y + 1) * 2;
    const i11 = Medium.index(x + 1, y + 1) * 2;

    const topX = this.velocity[i00] + (this.velocity[i10] - this.velocity[i00]) * fx;
    const topY = this.velocity[i00 + 1] + (this.velocity[i10 + 1] - this.velocity[i00 + 1]) * fx;
    const botX = this.velocity[i01] + (this.velocity[i11] - this.velocity[i01]) * fx;
    const botY = this.velocity[i01 + 1] + (this.velocity[i11 + 1] - this.velocity[i01 + 1]) * fx;

    return {
      x: topX + (botX - topX) * fy,
      y: topY + (botY - topY) * fy,
    };
  }

  transportSample(px: number, py: number, kind: number): Vec2 {
    const flow = this.sample(px, py);
    if (kind === 3) return flow;
    let pullX = 0;
    let pullY = 0;
    let strongest = -1.0;
    for (let i = 0; i < this.attractorCount; i++) {
      const base = i * 4;
      const mx = this.attractors[base];
      const my = this.attractors[base + 1];
      const reach = this.attractors[base + 2];
      const power = this.attractors[base + 3];
      const dx = offsetX(px, mx);
      const dy = offsetY(py, my);
      const d = Math.hypot(dx, dy);
      if (d >= reach || d < 1e-6) continue;
      const speed = power * (1.0 - d / reach) * Math.min(1.0, d / 24.0);
      if (speed > strongest + 0.0001) {
        strongest = speed;
        pullX = (dx / d) * speed;
        pullY = (dy / d) * speed;
      }
    }
    const mult = kind === 0 ? 1.0 : 0.2;
    return { x: flow.x + pullX * mult, y: flow.y + pullY * mult };
  }

  prepareAttractors(cells: AttractorCell[]): void {
    const ordered = cells.slice().sort((a, b) => a.id - b.id);
    let count = 0;
    for (const cell of ordered) {
      if (cell.dead || cell.substrate >= cell.gutCapacity() - 1e-6) continue;
      for (const organ of cell.organs) {
        if (!cell.oralPumping(organ)) continue;
        if (count >= MAX_ATTRACTORS) break;
        const center = cell.poreCenter(organ);
        const reach = cell.oralReach(organ);
        const health = organ.maxHp > 0 ? organ.hp / organ.maxHp : 1;
        const power = Math.min(
          300.0,
          300.0 * organ.scale * health * cell.genesFactor(organ, 'suction') * cell.workCapacity(),
        );
        const b = count * 4;
        this.attractors[b] = center.x;
        this.attractors[b + 1] = center.y;
        this.attractors[b + 2] = reach;
        this.attractors[b + 3] = power;
        count++;
      }
      if (count >= MAX_ATTRACTORS) break;
    }
    this.attractorCount = count;
  }

  setPlants(habitat: HabitatLike | null): void {
    const enabled = habitat !== null && habitat.enabled;
    const rev = habitat !== null ? habitat.flowRevision : 0;
    if (rev === this.plantRevision && enabled === this.plantEnabled) return;
    this.plantRevision = rev;
    this.plantEnabled = enabled;
    this.plantDrag.fill(0);
    if (!enabled || !habitat) return;

    const halo = GRID_SIZE * 0.55; // 35.2
    for (const plant of habitat.plants) {
      const scale = plant.radius / 100.0;
      const cos = Math.cos(plant.angle);
      const sin = Math.sin(plant.angle);
      for (const branch of habitat.forms[plant.form].branches) {
        const ax = plant.p.x + (branch.a.x * cos - branch.a.y * sin) * scale;
        const ay = plant.p.y + (branch.a.x * sin + branch.a.y * cos) * scale;
        const bx = plant.p.x + (branch.b.x * cos - branch.b.y * sin) * scale;
        const by = plant.p.y + (branch.b.x * sin + branch.b.y * cos) * scale;
        const radius = branch.r * scale;
        const reach = radius + halo;
        const loX = Math.ceil((Math.min(ax, bx) - reach) / GRID_SIZE - 0.5);
        const loY = Math.ceil((Math.min(ay, by) - reach) / GRID_SIZE - 0.5);
        const hiX = Math.floor((Math.max(ax, bx) + reach) / GRID_SIZE - 0.5);
        const hiY = Math.floor((Math.max(ay, by) + reach) / GRID_SIZE - 0.5);
        const ex = bx - ax;
        const ey = by - ay;
        const lenSq = Math.max(ex * ex + ey * ey, 1e-5);
        const diamFactor = Math.min(1.0, (2.0 * radius) / GRID_SIZE);

        for (let gy = loY; gy <= hiY; gy++) {
          for (let gx = loX; gx <= hiX; gx++) {
            const atX = (gx + 0.5) * GRID_SIZE;
            const atY = (gy + 0.5) * GRID_SIZE;
            const t = clamp(((atX - ax) * ex + (atY - ay) * ey) / lenSq, 0, 1);
            const cx = ax + ex * t;
            const cy = ay + ey * t;
            const d = Math.hypot(atX - cx, atY - cy);
            const coverage = clamp((radius + halo - d) / halo, 0, 1);
            const idx = Medium.index(gx, gy);
            this.plantDrag[idx] = Math.min(
              2.0 * PLANT_DAMPING,
              this.plantDrag[idx] + 0.9 * PLANT_DAMPING * diamFactor * coverage,
            );
          }
        }
      }
    }
  }

  step(dt: number): void {
    this.changes.fill(0);
    const amount = Math.min(dt * 0.8, 0.2);
    const tideBlend = this.driven ? 1.0 - Math.exp(-dt * 0.12) : 0.0;

    for (let y = 0; y < GRID_ROWS; y++) {
      for (let x = 0; x < GRID_COLS; x++) {
        const i = y * GRID_COLS + x;
        const i2 = i * 2;
        const vx = this.velocity[i2];
        const vy = this.velocity[i2 + 1];

        const right = (y * GRID_COLS + ((x + 1) % GRID_COLS)) * 2;
        const down = (((y + 1) % GRID_ROWS) * GRID_COLS + x) * 2;

        const exR = (this.velocity[right] - vx) * amount;
        const eyR = (this.velocity[right + 1] - vy) * amount;
        this.changes[i2] += exR;
        this.changes[i2 + 1] += eyR;
        this.changes[right] -= exR;
        this.changes[right + 1] -= eyR;

        const exD = (this.velocity[down] - vx) * amount;
        const eyD = (this.velocity[down + 1] - vy) * amount;
        this.changes[i2] += exD;
        this.changes[i2 + 1] += eyD;
        this.changes[down] -= exD;
        this.changes[down + 1] -= eyD;

        if (this.driven) {
          this.changes[i2] += (this.tide[i2] - vx) * tideBlend;
          this.changes[i2 + 1] += (this.tide[i2 + 1] - vy) * tideBlend;
        }
      }
    }

    for (let i = 0; i < FIELD_COUNT; i++) {
      const i2 = i * 2;
      const drag = Math.exp(-this.plantDrag[i] * dt);
      this.velocity[i2] = (this.velocity[i2] + this.changes[i2]) * drag;
      this.velocity[i2 + 1] = (this.velocity[i2 + 1] + this.changes[i2 + 1]) * drag;
    }
  }

  suction(
    body: SuctionBody,
    mouthX: number,
    mouthY: number,
    reach: number,
    power: number,
    dt: number,
    inflowAxis: Vec2,
  ): void {
    const loX = Math.floor((mouthX - reach) / GRID_SIZE);
    const hiX = Math.floor((mouthX + reach) / GRID_SIZE);
    const loY = Math.floor((mouthY - reach) / GRID_SIZE);
    const hiY = Math.floor((mouthY + reach) / GRID_SIZE);
    const hasAxis = inflowAxis.x * inflowAxis.x + inflowAxis.y * inflowAxis.y > 0.01;
    let axNormX = 0;
    let axNormY = 0;
    if (hasAxis) {
      const al = Math.hypot(inflowAxis.x, inflowAxis.y);
      axNormX = inflowAxis.x / al;
      axNormY = inflowAxis.y / al;
    }

    const minArmSq = body.radius * 0.65 * (body.radius * 0.65);

    for (let gy = loY; gy <= Math.min(hiY, loY + GRID_ROWS - 1); gy++) {
      for (let gx = loX; gx <= Math.min(hiX, loX + GRID_COLS - 1); gx++) {
        const i = Medium.index(gx, gy);
        const atX = (posmod(gx, GRID_COLS) + 0.5) * GRID_SIZE;
        const atY = (posmod(gy, GRID_ROWS) + 0.5) * GRID_SIZE;
        const dx = offsetX(atX, mouthX);
        const dy = offsetY(atY, mouthY);
        const distance = Math.hypot(dx, dy);
        if (distance < 4.0 || distance >= reach) continue;

        const armX = offsetX(body.position.x, atX);
        const armY = offsetY(body.position.y, atY);
        if (armX * armX + armY * armY < minArmSq) continue;

        let falloff = Math.pow(1.0 - distance / reach, 2.0);
        if (hasAxis) {
          const dirDot = (-dx / distance) * axNormX + (-dy / distance) * axNormY;
          falloff *= 0.15 + 0.85 * Math.max(0.0, dirDot);
        }

        const surfVx = body.velocity.x - armY * body.angularVelocity;
        const surfVy = body.velocity.y + armX * body.angularVelocity;
        const i2 = i * 2;
        const corrX = (dx / distance) * power - (this.velocity[i2] - surfVx);
        const corrY = (dy / distance) * power - (this.velocity[i2 + 1] - surfVy);
        const corrLen = Math.hypot(corrX, corrY);
        if (corrLen < 1e-8) continue;

        const ax = corrX / corrLen;
        const ay = corrY / corrLen;
        const armCrossAxis = armX * ay - armY * ax;
        const invMass =
          1.0 / NODE_MASS + 1.0 / body.mass + (armCrossAxis * armCrossAxis) / body.inertia;
        const k = (1.0 - Math.exp(-dt * 2.2 * falloff)) / invMass;
        const jx = corrX * k;
        const jy = corrY * k;

        this.velocity[i2] += jx / NODE_MASS;
        this.velocity[i2 + 1] += jy / NODE_MASS;
        body.velocity.x -= jx / body.mass;
        body.velocity.y -= jy / body.mass;
        body.angularVelocity -= (armX * jy - armY * jx) / body.inertia;
      }
    }
  }

  momentum(): Vec2 {
    let sx = 0;
    let sy = 0;
    for (let i = 0; i < FIELD_COUNT; i++) {
      sx += this.velocity[i * 2] * NODE_MASS;
      sy += this.velocity[i * 2 + 1] * NODE_MASS;
    }
    return { x: sx, y: sy };
  }
}
