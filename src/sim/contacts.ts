import { clamp, offsetVec, wrapPos, type Vec2 } from './constants.ts';
import type { Cell } from './cell.ts';
import type { HabitatCell } from './habitat.ts';

export const RESTITUTION = 0.12;
export const FRICTION = 0.38;

export function cellSurfaceAt(cell: Cell, dir: Vec2): { at: Vec2; normal: Vec2 } {
  const localAngle = Math.atan2(dir.y, dir.x) - cell.angle;
  const param = cell.surfaceParameter(localAngle);
  const lp = cell.localPoint(param);
  const ln = cell.localNormal(param);
  const c = Math.cos(cell.angle);
  const s = Math.sin(cell.angle);
  return {
    at: { x: cell.position.x + lp.x * c - lp.y * s, y: cell.position.y + lp.x * s + lp.y * c },
    normal: { x: ln.x * c - ln.y * s, y: ln.x * s + ln.y * c },
  };
}

export function velocityAt(cell: HabitatCell, at: Vec2): Vec2 {
  if (cell.activity <= 0) return { x: 0, y: 0 };
  const arm = offsetVec(cell.position, at);
  return {
    x: cell.velocity.x - arm.y * cell.angularVelocity,
    y: cell.velocity.y + arm.x * cell.angularVelocity,
  };
}

export function applyImpulse(cell: HabitatCell, impulse: Vec2, at: Vec2): void {
  if (cell.activity <= 0) return;
  const invM = cell.activity / cell.mass;
  const invI = cell.activity / cell.inertia;
  cell.velocity.x += impulse.x * invM;
  cell.velocity.y += impulse.y * invM;
  const arm = offsetVec(cell.position, at);
  cell.angularVelocity += (arm.x * impulse.y - arm.y * impulse.x) * invI;
}

export function solveContact(
  a: HabitatCell,
  b: HabitatCell | null,
  at: Vec2,
  normal: Vec2,
  penetration: number,
): number {
  const ia = a.activity / a.mass;
  const ib = b ? b.activity / b.mass : 0;
  const ra = offsetVec(a.position, at);
  const rb = b ? offsetVec(b.position, at) : { x: 0, y: 0 };
  const aa = a.activity / a.inertia;
  const ab = b ? b.activity / b.inertia : 0;

  const va = velocityAt(a, at);
  const vb = b ? velocityAt(b, at) : { x: 0, y: 0 };
  const relX = vb.x - va.x;
  const relY = vb.y - va.y;
  const closing = relX * normal.x + relY * normal.y;

  const raCrossN = ra.x * normal.y - ra.y * normal.x;
  const rbCrossN = rb.x * normal.y - rb.y * normal.x;
  const denom = ia + ib + raCrossN * raCrossN * aa + rbCrossN * rbCrossN * ab;
  if (denom <= 0) return 0;

  const e = closing < -6 ? 1 + RESTITUTION : 1;
  const impulse = Math.max(0, (-closing * e) / denom);
  applyImpulse(a, { x: -normal.x * impulse, y: -normal.y * impulse }, at);
  if (b) applyImpulse(b, { x: normal.x * impulse, y: normal.y * impulse }, at);

  // Tangent perpendicular: matches Godot normal.orthogonal() = (normal.y, -normal.x)
  const tx = normal.y;
  const ty = -normal.x;
  const va2 = velocityAt(a, at);
  const vb2 = b ? velocityAt(b, at) : { x: 0, y: 0 };
  const rel2X = vb2.x - va2.x;
  const rel2Y = vb2.y - va2.y;
  const raCrossT = ra.x * ty - ra.y * tx;
  const rbCrossT = rb.x * ty - rb.y * tx;
  const tangMass = ia + ib + raCrossT * raCrossT * aa + rbCrossT * rbCrossT * ab;
  const friction = clamp(
    -(rel2X * tx + rel2Y * ty) / Math.max(tangMass, 1e-6),
    -impulse * FRICTION,
    impulse * FRICTION,
  );
  applyImpulse(a, { x: -tx * friction, y: -ty * friction }, at);
  if (b) applyImpulse(b, { x: tx * friction, y: ty * friction }, at);

  const corr = Math.max(0, penetration - 0.03) / Math.max(ia + ib, 1e-6);
  a.position = wrapPos({ x: a.position.x - normal.x * corr * ia, y: a.position.y - normal.y * corr * ia });
  if (b) {
    b.position = wrapPos({ x: b.position.x + normal.x * corr * ib, y: b.position.y + normal.y * corr * ib });
  }
  return impulse;
}

export function dentCell(cell: Cell, at: Vec2, depth: number): void {
  if (cell.activity <= 0 || depth <= 0.001) return;
  const off = offsetVec(cell.position, at);
  const localAngle = Math.atan2(off.y, off.x) - cell.angle;
  cell.membrane.compress(localAngle, Math.min(depth, cell.radius * 0.075), cell.radius);
  cell.renderRevision++;
}

export function contactPair(a: Cell, b: Cell, dt: number, deform: boolean): boolean {
  const delta = offsetVec(a.position, b.position);
  const maxR = a.extent() + b.extent() + 0.2;
  const dSq = delta.x * delta.x + delta.y * delta.y;
  if (dSq > maxR * maxR) return false;

  const dl = Math.hypot(delta.x, delta.y);
  const radial: Vec2 = dl > 1e-3 ? { x: delta.x / dl, y: delta.y / dl } : { x: 1, y: 0 };
  const sa = cellSurfaceAt(a, radial);
  const sb = cellSurfaceAt(b, { x: -radial.x, y: -radial.y });
  const gap = offsetVec(sa.at, sb.at);
  if (gap.x * radial.x + gap.y * radial.y > 0.15) return false;

  let nx = sa.normal.x - sb.normal.x;
  let ny = sa.normal.y - sb.normal.y;
  const nl = Math.hypot(nx, ny);
  if (nl > 1e-6) {
    nx /= nl;
    ny /= nl;
  } else {
    nx = radial.x;
    ny = radial.y;
  }
  if (nx * radial.x + ny * radial.y < 0.65) {
    nx = radial.x;
    ny = radial.y;
  }
  const normal: Vec2 = { x: nx, y: ny };
  const at: Vec2 = { x: sa.at.x + gap.x * 0.5, y: sa.at.y + gap.y * 0.5 };
  const depth = Math.max(0, -(gap.x * nx + gap.y * ny));
  const va = velocityAt(a, at);
  const vb = velocityAt(b, at);
  const closing = Math.max(0, -((vb.x - va.x) * nx + (vb.y - va.y) * ny));

  solveContact(a, b, at, normal, depth);
  if (deform) {
    const compression = Math.min(
      Math.min(a.radius, b.radius) * 0.06,
      depth * 0.18 + closing * dt * 0.65,
    );
    dentCell(a, sa.at, compression);
    dentCell(b, sb.at, compression);
  }
  return true;
}
