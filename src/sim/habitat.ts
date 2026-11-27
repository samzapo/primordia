import {
  TAU,
  WORLD_H,
  WORLD_W,
  clamp,
  lerp,
  offsetVec,
  posmod,
  wrapPos,
  type Vec2,
} from './constants.ts';
import { SeededRng } from './rng.ts';

export const HABITAT_BIN = 128.0;
export const HABITAT_COLS = 32;
export const HABITAT_ROWS = 20;

export type PlantKind = 'fern' | 'radial' | 'fan' | 'spiral';
export type LeafShape = 'blade' | 'oval' | 'bud';

export interface PlantBranch {
  a: Vec2;
  b: Vec2;
  r: number;
  depth: number;
}

export interface PlantForm {
  kind: PlantKind;
  arms: number;
  turn: number;
  branches: PlantBranch[];
  palette: number;
  root: Vec2;
  rootRadius: number;
  leaf: LeafShape;
}

export interface PlantColony {
  p: Vec2;
  radius: number;
  form: number;
  angle: number;
}

export interface HabitatSegment {
  a: Vec2;
  b: Vec2;
  r: number;
}

export interface HabitatCell {
  position: Vec2;
  velocity: Vec2;
  angularVelocity: number;
  radius: number;
  mass: number;
  inertia: number;
  activity: number;
  extent(): number;
  support(worldAngle: number): number;
}

export interface ContactHelper {
  velocityAt(cell: HabitatCell, at: Vec2): Vec2;
  solveStatic(cell: HabitatCell, at: Vec2, normal: Vec2, penetration: number): void;
  dent(cell: HabitatCell, at: Vec2, depth: number): void;
}

function addStem(output: PlantBranch[], a: Vec2, b: Vec2, r: number, depth: number): void {
  output.push({ a, b, r, depth });
}

function addBranch(
  output: PlantBranch[],
  a: Vec2,
  angle: number,
  length: number,
  width: number,
  depth: number,
  turn: number,
): void {
  const b: Vec2 = { x: a.x + Math.cos(angle) * length, y: a.y + Math.sin(angle) * length };
  output.push({ a, b, r: width, depth });
  if (depth === 0) return;
  for (const fraction of [0.5, 0.82]) {
    const mid: Vec2 = { x: lerp(a.x, b.x, fraction), y: lerp(a.y, b.y, fraction) };
    for (const sgn of [-1, 1]) {
      addBranch(output, mid, angle + sgn * turn, length * 0.39, width * 0.49, depth - 1, turn);
    }
  }
}

function addFork(
  output: PlantBranch[],
  a: Vec2,
  angle: number,
  length: number,
  width: number,
  depth: number,
  turn: number,
): void {
  const b: Vec2 = { x: a.x + Math.cos(angle) * length, y: a.y + Math.sin(angle) * length };
  addStem(output, a, b, width, depth);
  if (depth === 0) return;
  for (const sgn of [-1, 1]) {
    addFork(output, b, angle + sgn * turn, length * 0.63, width * 0.66, depth - 1, turn * 0.93);
  }
}

function buildFern(output: PlantBranch[], variant: number, turn: number): void {
  let prev: Vec2 = { x: 0, y: 82 };
  for (let i = 1; i <= 10; i++) {
    const t = i / 10.0;
    const p: Vec2 = {
      x: Math.sin(t * Math.PI) * (variant === 0 ? -8 : 13),
      y: 82 - t * 170,
    };
    addStem(output, prev, p, lerp(4.5, 1.1, t), 2);
    if (i < 10) {
      const span = (variant === 0 ? 48 : 38) * Math.sin(Math.PI * Math.pow(t, 0.72)) + 5;
      for (const side of [-1, 1]) {
        const ax = side;
        const ay = -0.32 - t * 0.55;
        addBranch(output, p, Math.atan2(ay, ax), span, lerp(2.3, 1.1, t), 1, turn);
      }
    }
    prev = p;
  }
}

function makeForm(kind: PlantKind, variant: number, turn: number): PlantForm {
  const form: PlantForm = {
    kind,
    arms: 1,
    turn,
    branches: [],
    palette: 0,
    root: { x: 0, y: 0 },
    rootRadius: 7.0,
    leaf: 'oval',
  };

  if (kind === 'radial') {
    form.arms = 5 + variant * 2;
    form.palette = 2;
    for (let arm = 0; arm < form.arms; arm++) {
      addBranch(form.branches, { x: 0, y: 0 }, (TAU * arm) / form.arms, 61.0, 7.0, 2, turn);
    }
  } else if (kind === 'fern') {
    form.root = { x: 0, y: 82 };
    form.rootRadius = 4.5;
    form.leaf = 'blade';
    form.palette = 0;
    buildFern(form.branches, variant, turn);
  } else if (kind === 'fan') {
    form.root = { x: 0, y: 76 };
    form.rootRadius = 5.0;
    form.palette = 1;
    form.leaf = 'bud';
    addStem(form.branches, { x: form.root.x, y: form.root.y }, { x: 0, y: 48 }, 5.0, 4);
    for (const side of [-1, 0, 1]) {
      addFork(
        form.branches,
        { x: 0, y: 48 },
        -Math.PI * 0.5 + side * (0.6 + variant * 0.1),
        42,
        3.5,
        3,
        turn * 0.53,
      );
    }
  } else {
    form.arms = 3 + variant;
    form.palette = 3;
    form.rootRadius = 5.0;
    for (let arm = 0; arm < form.arms; arm++) {
      let a: Vec2 = { x: 0, y: 0 };
      for (let i = 1; i <= 8; i++) {
        const phase = (TAU * arm) / form.arms + (i / 8.0) * (1.8 + turn * 0.4);
        const b: Vec2 = { x: Math.cos(phase) * (i * 9.2), y: Math.sin(phase) * (i * 9.2) };
        addStem(form.branches, a, b, lerp(4.8, 1.8, i / 8.0), 1);
        if (i > 1) {
          const ang = Math.atan2(b.y - a.y, b.x - a.x) - 0.9;
          addBranch(form.branches, b, ang, 15 * (1 - i / 12.0), 1.2, 1, 0.75);
        }
        a = b;
      }
    }
  }

  let extent = 0;
  for (const br of form.branches) {
    extent = Math.max(
      extent,
      Math.max(Math.hypot(br.a.x, br.a.y), Math.hypot(br.b.x, br.b.y)) + Math.max(br.r, 5.5),
    );
  }
  if (extent > 96) {
    const s = 96.0 / extent;
    for (const br of form.branches) {
      br.a.x *= s;
      br.a.y *= s;
      br.b.x *= s;
      br.b.y *= s;
      br.r *= s;
    }
    form.root.x *= s;
    form.root.y *= s;
    form.rootRadius *= s;
  }

  return form;
}

export class Habitat {
  readonly forms: PlantForm[] = [];
  readonly plants: PlantColony[] = [];
  readonly segments: HabitatSegment[] = [];
  readonly bins = new Map<number, number[]>();
  enabled = true;
  flowRevision = 0;

  constructor(seedNumber = 0, occupied: Array<{ position: Vec2; extent(): number }> = []) {
    const rng = new SeededRng((seedNumber ^ 0x62ab91) | 0);
    const kinds: PlantKind[] = ['fern', 'radial', 'fan', 'spiral'];
    for (let i = 0; i < 8; i++) {
      this.forms.push(makeForm(kinds[i % 4], Math.floor(i / 4), rng.randRange(0.6, 0.86)));
    }

    for (let i = 0; i < 10; i++) {
      for (let attempt = 0; attempt < 120; attempt++) {
        let radius = rng.randRange(185, 275);
        let pos: Vec2 = { x: rng.randf() * WORLD_W, y: rng.randf() * WORLD_H };
        if (i % 3 !== 0 && this.plants.length > 0 && attempt < 80) {
          const anchor = this.plants[Math.min(this.plants.length - 1, Math.floor(i / 3) * 3)];
          const heading = rng.randf() * TAU;
          const sep = radius + anchor.radius + rng.randRange(110, 210);
          pos = wrapPos({
            x: anchor.p.x + Math.cos(heading) * sep,
            y: anchor.p.y + Math.sin(heading) * sep,
          });
        }
        if (i === 0 && attempt === 0) {
          radius = 190;
          pos = { x: 1580, y: 1340 };
        }
        let clear = true;
        for (const cell of occupied) {
          const d = offsetVec(pos, cell.position);
          if (Math.hypot(d.x, d.y) < radius + cell.extent() + 35) {
            clear = false;
            break;
          }
        }
        if (!clear) continue;
        for (const plant of this.plants) {
          const d = offsetVec(pos, plant.p);
          if (Math.hypot(d.x, d.y) < radius + plant.radius + 90) {
            clear = false;
            break;
          }
        }
        if (!clear) continue;
        this.plants.push({
          p: pos,
          radius,
          form: i % this.forms.length,
          angle: rng.randf() * TAU,
        });
        break;
      }
    }

    this.rebuild();
  }

  rebuild(): void {
    this.flowRevision++;
    this.segments.length = 0;
    this.bins.clear();

    for (const plant of this.plants) {
      const scale = plant.radius / 100.0;
      const cos = Math.cos(plant.angle);
      const sin = Math.sin(plant.angle);
      for (const branch of this.forms[plant.form].branches) {
        if (branch.depth === 0) continue;
        const a: Vec2 = {
          x: plant.p.x + (branch.a.x * cos - branch.a.y * sin) * scale,
          y: plant.p.y + (branch.a.x * sin + branch.a.y * cos) * scale,
        };
        const b: Vec2 = {
          x: plant.p.x + (branch.b.x * cos - branch.b.y * sin) * scale,
          y: plant.p.y + (branch.b.x * sin + branch.b.y * cos) * scale,
        };
        const r = branch.r * scale;
        const id = this.segments.length;
        this.segments.push({ a, b, r });

        const reach = r + 8;
        const loX = Math.floor((Math.min(a.x, b.x) - reach) / HABITAT_BIN);
        const loY = Math.floor((Math.min(a.y, b.y) - reach) / HABITAT_BIN);
        const hiX = Math.floor((Math.max(a.x, b.x) + reach) / HABITAT_BIN);
        const hiY = Math.floor((Math.max(a.y, b.y) + reach) / HABITAT_BIN);

        for (let y = loY; y <= hiY; y++) {
          for (let x = loX; x <= hiX; x++) {
            const key = posmod(y, HABITAT_ROWS) * HABITAT_COLS + posmod(x, HABITAT_COLS);
            let list = this.bins.get(key);
            if (!list) {
              list = [];
              this.bins.set(key, list);
            }
            list.push(id);
          }
        }
      }
    }
  }

  private static binKey(p: Vec2): number {
    return (
      posmod(Math.floor(p.y / HABITAT_BIN), HABITAT_ROWS) * HABITAT_COLS +
      posmod(Math.floor(p.x / HABITAT_BIN), HABITAT_COLS)
    );
  }

  query(start: Vec2, end: Vec2, radius: number): number[] {
    if (!this.enabled) return [];
    const d = offsetVec(start, end);
    const ex = start.x + d.x;
    const ey = start.y + d.y;
    if (radius <= 7 && Habitat.binKey(start) === Habitat.binKey({ x: ex, y: ey })) {
      return this.bins.get(Habitat.binKey({ x: ex, y: ey })) ?? [];
    }
    const loX = Math.floor((Math.min(start.x, ex) - radius) / HABITAT_BIN);
    const loY = Math.floor((Math.min(start.y, ey) - radius) / HABITAT_BIN);
    const hiX = Math.floor((Math.max(start.x, ex) + radius) / HABITAT_BIN);
    const hiY = Math.floor((Math.max(start.y, ey) + radius) / HABITAT_BIN);

    const seen = new Set<number>();
    for (let y = loY; y <= Math.min(hiY, loY + HABITAT_ROWS - 1); y++) {
      for (let x = loX; x <= Math.min(hiX, loX + HABITAT_COLS - 1); x++) {
        const key = posmod(y, HABITAT_ROWS) * HABITAT_COLS + posmod(x, HABITAT_COLS);
        const list = this.bins.get(key);
        if (!list) continue;
        for (let k = 0; k < list.length; k++) seen.add(list[k]);
      }
    }
    return Array.from(seen);
  }

  static closest(p: Vec2, a: Vec2, b: Vec2): Vec2 {
    const ex = b.x - a.x;
    const ey = b.y - a.y;
    const lenSq = Math.max(ex * ex + ey * ey, 1e-5);
    const t = clamp(((p.x - a.x) * ex + (p.y - a.y) * ey) / lenSq, 0, 1);
    return { x: a.x + ex * t, y: a.y + ey * t };
  }

  clearAt(p: Vec2, radius: number): boolean {
    const ids = this.query(p, p, radius);
    for (const id of ids) {
      const s = this.segments[id];
      const d = offsetVec(p, s.a);
      const a: Vec2 = { x: p.x + d.x, y: p.y + d.y };
      const b: Vec2 = { x: a.x + (s.b.x - s.a.x), y: a.y + (s.b.y - s.a.y) };
      const c = Habitat.closest(p, a, b);
      if (Math.hypot(p.x - c.x, p.y - c.y) < radius + s.r + 0.1) return false;
    }
    return true;
  }

  static circleHit(p: Vec2, travel: Vec2, center: Vec2, radius: number): number {
    const dx = p.x - center.x;
    const dy = p.y - center.y;
    const a = travel.x * travel.x + travel.y * travel.y;
    const b = dx * travel.x + dy * travel.y;
    const c = dx * dx + dy * dy - radius * radius;
    if (c <= 0) return b < 0 ? 0.0 : 2.0;
    const disc = b * b - a * c;
    if (a < 1e-6 || disc < 0) return 2.0;
    const t = (-b - Math.sqrt(disc)) / a;
    return t >= 0 && t <= 1 ? t : 2.0;
  }

  static capsuleHit(p: Vec2, travel: Vec2, a: Vec2, b: Vec2, radius: number): number {
    let t = Math.min(Habitat.circleHit(p, travel, a, radius), Habitat.circleHit(p, travel, b, radius));
    const abx = b.x - a.x;
    const aby = b.y - a.y;
    const abLen = Math.hypot(abx, aby);
    if (abLen < 1e-8) return t;
    const axisX = abx / abLen;
    const axisY = aby / abLen;
    const normX = -axisY;
    const normY = axisX;
    const side = (p.x - a.x) * normX + (p.y - a.y) * normY;
    const speed = travel.x * normX + travel.y * normY;
    if (Math.abs(speed) > 1e-6) {
      for (const sgn of [-1, 1]) {
        if (speed * sgn >= 0) continue;
        const hit = (sgn * radius - side) / speed;
        const px = p.x + travel.x * hit;
        const py = p.y + travel.y * hit;
        const along = (px - a.x) * axisX + (py - a.y) * axisY;
        if (hit >= 0 && hit <= 1 && along >= 0 && along <= abLen) {
          t = Math.min(t, hit);
        }
      }
    }
    return t;
  }

  moveCell(cell: HabitatCell, start: Vec2, end: Vec2, dt: number, contacts: ContactHelper): void {
    if (!this.enabled) {
      cell.position = wrapPos(end);
      return;
    }
    const ids = this.query(start, end, cell.extent() + 1);
    cell.position = { x: start.x, y: start.y };
    let travel = offsetVec(start, end);
    let remaining = dt;

    for (let iter = 0; iter < 4; iter++) {
      let earliest = 2.0;
      let hitNormX = 0;
      let hitNormY = 0;
      let hitPoint: Vec2 = { x: 0, y: 0 };

      for (const id of ids) {
        const seg = this.segments[id];
        const da = offsetVec(cell.position, seg.a);
        const a: Vec2 = { x: cell.position.x + da.x, y: cell.position.y + da.y };
        const b: Vec2 = { x: a.x + (seg.b.x - seg.a.x), y: a.y + (seg.b.y - seg.a.y) };
        const reach = cell.extent() + seg.r + 0.2;
        const finX = cell.position.x + travel.x;
        const finY = cell.position.y + travel.y;
        if (
          Math.max(cell.position.x, finX) < Math.min(a.x, b.x) - reach ||
          Math.min(cell.position.x, finX) > Math.max(a.x, b.x) + reach ||
          Math.max(cell.position.y, finY) < Math.min(a.y, b.y) - reach ||
          Math.min(cell.position.y, finY) > Math.max(a.y, b.y) + reach
        ) {
          continue;
        }

        const near = Habitat.closest(cell.position, a, b);
        let tox = near.x - cell.position.x;
        let toy = near.y - cell.position.y;
        const distance = Math.hypot(tox, toy);
        if (distance * distance < 1e-5) {
          tox = -(b.y - a.y);
          toy = b.x - a.x;
        }
        const tl = Math.hypot(tox, toy) || 1;
        let nx = tox / tl;
        let ny = toy / tl;
        let radius = cell.support(Math.atan2(ny, nx));
        const overlap = radius + seg.r - distance;

        if (overlap > 0) {
          const at: Vec2 = { x: cell.position.x + nx * radius, y: cell.position.y + ny * radius };
          const velAt = contacts.velocityAt(cell, at);
          const speed = Math.max(0, velAt.x * nx + velAt.y * ny);
          contacts.solveStatic(cell, at, { x: nx, y: ny }, overlap);
          contacts.dent(cell, at, Math.min(radius * 0.06, overlap * 0.12 + speed * dt * 0.65));
          const dotT = travel.x * nx + travel.y * ny;
          if (dotT > 0) {
            travel = { x: travel.x - nx * dotT, y: travel.y - ny * dotT };
          }
          continue;
        }

        let t = Habitat.capsuleHit(cell.position, travel, a, b, cell.extent() + seg.r);
        if (t > 1) continue;
        for (let refine = 0; refine < 3; refine++) {
          const cx = cell.position.x + travel.x * t;
          const cy = cell.position.y + travel.y * t;
          const nNear = Habitat.closest({ x: cx, y: cy }, a, b);
          const nl = Math.hypot(nNear.x - cx, nNear.y - cy) || 1;
          nx = (nNear.x - cx) / nl;
          ny = (nNear.y - cy) / nl;
          radius = cell.support(Math.atan2(ny, nx));
          t = Habitat.capsuleHit(cell.position, travel, a, b, radius + seg.r + 0.05);
          if (t > 1) break;
        }
        if (t < earliest) {
          earliest = t;
          hitNormX = nx;
          hitNormY = ny;
          hitPoint = {
            x: cell.position.x + travel.x * t + nx * radius,
            y: cell.position.y + travel.y * t + ny * radius,
          };
        }
      }

      if (earliest > 1) {
        cell.position = wrapPos({
          x: cell.position.x + travel.x,
          y: cell.position.y + travel.y,
        });
        break;
      }

      cell.position = wrapPos({
        x: cell.position.x + travel.x * earliest - hitNormX * 0.05,
        y: cell.position.y + travel.y * earliest - hitNormY * 0.05,
      });
      const velAt = contacts.velocityAt(cell, hitPoint);
      const speed = Math.max(0, velAt.x * hitNormX + velAt.y * hitNormY);
      contacts.solveStatic(cell, hitPoint, { x: hitNormX, y: hitNormY }, 0);
      contacts.dent(cell, hitPoint, speed * dt * 0.65);
      remaining *= 1 - earliest;
      travel = { x: cell.velocity.x * remaining, y: cell.velocity.y * remaining };
      if (travel.x * travel.x + travel.y * travel.y < 1e-6) break;
    }

    cell.position = wrapPos(cell.position);
  }
}
