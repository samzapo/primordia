import type { Cell } from '../sim/cell.ts';
import { type Vec2, clamp, wrapAngle } from '../sim/constants.ts';

export interface CellMotionTransform {
  squashAngle: number;
  sx: number;
  sy: number;
  smoothAccelX: number;
  smoothAccelY: number;
  phase: number;
}

interface InternalMotionState {
  phase: number;
  smoothAx: number;
  smoothAy: number;
  slotOffsets: Map<string, number>;
}

const LANDMARK_EASE_RATE = 12.0;

export class CellMotionTracker {
  private readonly states = new Map<number, InternalMotionState>();

  update(cells: Cell[], dt: number, paused: boolean): void {
    const aliveIds = new Set<number>();
    const safeDt = Math.max(0, Math.min(0.1, dt));
    const accelBlend = 1 - Math.exp(-8.0 * safeDt);

    for (const cell of cells) {
      if (cell.dead) continue;
      aliveIds.add(cell.id);
      let st = this.states.get(cell.id);
      if (!st) {
        st = {
          phase: (cell.id * 1.37) % (Math.PI * 2),
          smoothAx: 0,
          smoothAy: 0,
          slotOffsets: new Map<string, number>(),
        };
        this.states.set(cell.id, st);
      }

      if (!paused) {
        const speed = Math.hypot(cell.velocity.x, cell.velocity.y);
        const drive = cell.driveActive ? 1.0 : 0.35;
        st.phase += safeDt * (2.6 + drive * 1.6 + Math.min(2.5, speed * 0.04));
        st.smoothAx += (cell.shapeAcceleration.x - st.smoothAx) * accelBlend;
        st.smoothAy += (cell.shapeAcceleration.y - st.smoothAy) * accelBlend;
      }
    }

    for (const id of [...this.states.keys()]) {
      if (!aliveIds.has(id)) {
        this.states.delete(id);
      }
    }
  }

  transformFor(cell: Cell): CellMotionTransform {
    const st = this.states.get(cell.id);
    if (!st) {
      return { squashAngle: cell.angle, sx: 1, sy: 1, smoothAccelX: 0, smoothAccelY: 0, phase: 0 };
    }
    const accelMag = Math.hypot(st.smoothAx, st.smoothAy);
    const speed = Math.hypot(cell.velocity.x, cell.velocity.y);
    const speedAmp = clamp(speed / 160, 0, 0.032);
    const accelRatio = clamp(accelMag / 420, 0, 1);
    const accelStretch = accelRatio * 0.068 + accelRatio * 0.022 * Math.sin(st.phase * 1.4);
    // Area-preserving organic breathing + inertial acceleration squash/stretch
    const breathe = 0.014 * Math.sin(st.phase);
    const sx = clamp(1 + breathe + speedAmp + accelStretch, 0.89, 1.13);
    const sy = 1 / sx;

    let squashAngle = cell.angle;
    if (accelMag > 8) {
      squashAngle = Math.atan2(st.smoothAy, st.smoothAx);
    } else if (speed > 2) {
      squashAngle = Math.atan2(cell.velocity.y, cell.velocity.x);
    }

    return {
      squashAngle,
      sx,
      sy,
      smoothAccelX: st.smoothAx,
      smoothAccelY: st.smoothAy,
      phase: st.phase,
    };
  }

  easeSlot(cellId: number, key: string, target: number, dt: number): number {
    let st = this.states.get(cellId);
    if (!st) {
      st = { phase: 0, smoothAx: 0, smoothAy: 0, slotOffsets: new Map<string, number>() };
      this.states.set(cellId, st);
    }
    const prev = st.slotOffsets.get(key);
    if (prev === undefined) {
      st.slotOffsets.set(key, target);
      return target;
    }
    const diff = wrapAngle(target - prev);
    const blend = 1 - Math.exp(-LANDMARK_EASE_RATE * Math.max(0, dt));
    const next = prev + diff * blend;
    st.slotOffsets.set(key, next);
    return next;
  }

  applyDeform(pt: Vec2, tr: CellMotionTransform, cellAngle: number): Vec2 {
    const relA = tr.squashAngle - cellAngle;
    const c = Math.cos(relA);
    const s = Math.sin(relA);
    const rx = pt.x * c + pt.y * s;
    const ry = -pt.x * s + pt.y * c;
    const sx = rx * tr.sx;
    const sy = ry * tr.sy;
    return {
      x: sx * c - sy * s,
      y: sx * s + sy * c,
    };
  }
}
