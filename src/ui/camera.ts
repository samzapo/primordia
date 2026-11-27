import type { Cell } from '../sim/cell.ts';
import {
  MAX_INTERO_ZOOM,
  MAX_ZOOM,
  VIEW_H,
  VIEW_W,
  type Vec2,
  WORLD_H,
  WORLD_W,
  clamp,
  lerp,
  lerpAngle,
  offsetVec,
  wrapAngle,
  wrapPos,
} from '../sim/constants.ts';

export const WRAP_ZOOM_MARGIN = 0.96;

/** Minimum zoom that keeps the rotated viewport strictly inside the toroidal wraparound span. */
export function wraparoundMinZoom(viewW: number, viewH: number, rotation = 0): number {
  if (viewW <= 0 || viewH <= 0) return 0.1;
  const c = Math.abs(Math.cos(rotation));
  const s = Math.abs(Math.sin(rotation));
  const spanX = viewW * c + viewH * s;
  const spanY = viewW * s + viewH * c;
  return Math.max(0.05, spanX / (WORLD_W * WRAP_ZOOM_MARGIN), spanY / (WORLD_H * WRAP_ZOOM_MARGIN));
}

interface CameraMotion {
  startX: number;
  startY: number;
  startZoom: number;
  startRot: number;
  endX: number;
  endY: number;
  endZoom: number;
  endRot: number;
  elapsed: number;
  duration: number;
}

export class PondCamera {
  x = WORLD_W * 0.5;
  y = WORLD_H * 0.5;
  zoom = 1.65;
  rotation = 0;

  follow = true;
  interoception = false;
  focusCellId = 0;

  private motion: CameraMotion | null = null;
  private lastViewW = VIEW_W;
  private lastViewH = VIEW_H;
  deathFocusUntil = -1;
  deathSite: Vec2 = { x: WORLD_W * 0.5, y: WORLD_H * 0.5 };

  setViewport(viewW: number, viewH: number): void {
    if (viewW > 0 && viewH > 0) {
      this.lastViewW = viewW;
      this.lastViewH = viewH;
    }
  }

  minZoom(viewW = this.lastViewW, viewH = this.lastViewH, rotation = this.rotation): number {
    return wraparoundMinZoom(viewW, viewH, rotation);
  }

  setFocusCell(cell: Cell, animate = true): void {
    this.focusCellId = cell.id;
    this.follow = true;
    if (animate) {
      this.startMotion(cell.position.x, cell.position.y, this.clampZoom(this.zoom), this.interoception ? cell.angle : 0, 0.65);
    } else {
      this.x = cell.position.x;
      this.y = cell.position.y;
    }
  }

  clampZoom(z: number, viewW = this.lastViewW, viewH = this.lastViewH, rotation = this.rotation): number {
    const lo = this.minZoom(viewW, viewH, rotation);
    const hi = this.interoception ? MAX_INTERO_ZOOM : MAX_ZOOM;
    return clamp(z, lo, Math.max(lo, hi));
  }

  toggleFollow(focusCell: Cell): void {
    this.follow = !this.follow;
    if (this.follow && !focusCell.dead) {
      this.startMotion(focusCell.position.x, focusCell.position.y, this.clampZoom(this.zoom), this.rotation, 0.55);
    }
  }

  toggleInteroception(focusCell: Cell): void {
    this.interoception = !this.interoception;
    if (this.interoception) {
      this.follow = true;
      const lo = this.minZoom(this.lastViewW, this.lastViewH, focusCell.angle);
      const targetZ = clamp(Math.max(this.zoom, 4.2), lo, Math.max(lo, MAX_INTERO_ZOOM));
      this.startMotion(focusCell.position.x, focusCell.position.y, targetZ, focusCell.angle, 0.65);
    } else {
      const targetZ = this.clampZoom(Math.min(this.zoom, 2.2), this.lastViewW, this.lastViewH, 0);
      this.startMotion(focusCell.position.x, focusCell.position.y, targetZ, 0, 0.65);
    }
  }

  frameMergeNeighborhood(focus: Cell, candidates: Cell[], viewW: number, viewH: number): void {
    if (candidates.length === 0) return;
    this.setViewport(viewW, viewH);
    let maxD = focus.extent() * 2.5;
    for (const c of candidates) {
      const d = offsetVec(focus.position, c.position);
      maxD = Math.max(maxD, Math.hypot(d.x, d.y) + c.extent() * 2);
    }
    const minSpan = Math.max(120, Math.min(viewW, viewH) * 0.42);
    const fitZoom = this.clampZoom(minSpan / Math.max(1, maxD), viewW, viewH, 0);
    this.follow = true;
    this.interoception = false;
    this.startMotion(focus.position.x, focus.position.y, fitZoom, 0, 0.65);
  }

  triggerDeathFraming(at: Vec2, simTime: number): void {
    this.deathSite = { ...at };
    this.deathFocusUntil = simTime + 1.8;
    this.follow = false;
    this.interoception = false;
    this.startMotion(at.x, at.y, this.clampZoom(Math.min(this.zoom, 2.5), this.lastViewW, this.lastViewH, 0), 0, 0.55);
  }

  startMotion(endX: number, endY: number, endZoom: number, endRot: number, duration = 0.65): void {
    this.motion = {
      startX: this.x,
      startY: this.y,
      startZoom: this.zoom,
      startRot: this.rotation,
      endX,
      endY,
      endZoom: this.clampZoom(endZoom),
      endRot: wrapAngle(endRot),
      elapsed: 0,
      duration,
    };
  }

  panByScreenDelta(dxScreen: number, dyScreen: number): void {
    if (this.interoception) return;
    this.follow = false;
    this.motion = null;
    const c = Math.cos(this.rotation);
    const s = Math.sin(this.rotation);
    const invZ = 1 / Math.max(0.01, this.zoom);
    const wx = (dxScreen * c - dyScreen * s) * invZ;
    const wy = (dxScreen * s + dyScreen * c) * invZ;
    const p = wrapPos({ x: this.x - wx, y: this.y - wy });
    this.x = p.x;
    this.y = p.y;
  }

  zoomAtScreenPoint(factor: number, sx: number, sy: number, viewW: number, viewH: number, focusCell: Cell): void {
    this.setViewport(viewW, viewH);
    const before = this.follow ? focusCell.position : this.screenToWorld(sx, sy, viewW, viewH);
    this.zoom = this.clampZoom(this.zoom * factor, viewW, viewH, this.rotation);
    this.motion = null;
    if (this.follow && !focusCell.dead) {
      this.x = focusCell.position.x;
      this.y = focusCell.position.y;
    } else {
      const after = this.screenToWorld(sx, sy, viewW, viewH);
      const corr = offsetVec(after, before);
      const p = wrapPos({ x: this.x + corr.x, y: this.y + corr.y });
      this.x = p.x;
      this.y = p.y;
    }
  }

  screenDeltaToWorld(dx: number, dy: number): Vec2 {
    const invZ = 1 / Math.max(0.001, this.zoom);
    const vx = dx * invZ;
    const vy = dy * invZ;
    const c = Math.cos(this.rotation);
    const s = Math.sin(this.rotation);
    return {
      x: vx * c - vy * s,
      y: vx * s + vy * c,
    };
  }

  capturePairAnchors(
    p0: Vec2,
    p1: Vec2,
    viewW: number,
    viewH: number,
  ): { anchorA: Vec2; anchorB: Vec2; startZoom: number; startDist: number } {
    this.setViewport(viewW, viewH);
    const anchorA = this.screenToWorld(p0.x, p0.y, viewW, viewH);
    const sep = this.screenDeltaToWorld(p1.x - p0.x, p1.y - p0.y);
    return {
      anchorA,
      anchorB: { x: anchorA.x + sep.x, y: anchorA.y + sep.y },
      startZoom: this.zoom,
      startDist: Math.hypot(p1.x - p0.x, p1.y - p0.y),
    };
  }

  applyAnchoredPairGesture(
    anchorA: Vec2,
    anchorB: Vec2,
    startZoom: number,
    startDist: number,
    cur0: Vec2,
    cur1: Vec2,
    viewW: number,
    viewH: number,
  ): void {
    this.setViewport(viewW, viewH);
    const tgtX = cur1.x - cur0.x;
    const tgtY = cur1.y - cur0.y;
    const tgtLen = Math.hypot(tgtX, tgtY);
    if (tgtLen < 4) return;

    if (this.interoception) {
      if (startDist > 4) {
        this.zoom = this.clampZoom(startZoom * (tgtLen / startDist), viewW, viewH, this.rotation);
      }
      this.motion = null;
      this.follow = true;
      return;
    }

    const srcX = anchorB.x - anchorA.x;
    const srcY = anchorB.y - anchorA.y;
    const srcLen = Math.hypot(srcX, srcY);
    if (srcLen < 1e-4) return;

    const nextRot = wrapAngle(Math.atan2(srcY, srcX) - Math.atan2(tgtY, tgtX));
    const nextZoom = this.clampZoom(tgtLen / srcLen, viewW, viewH, nextRot);
    const midWX = (anchorA.x + anchorB.x) * 0.5;
    const midWY = (anchorA.y + anchorB.y) * 0.5;
    const midSX = (cur0.x + cur1.x) * 0.5;
    const midSY = (cur0.y + cur1.y) * 0.5;

    const vx = (midSX - viewW * 0.5) / Math.max(0.001, nextZoom);
    const vy = (midSY - viewH * 0.5) / Math.max(0.001, nextZoom);
    const c = Math.cos(nextRot);
    const s = Math.sin(nextRot);
    const offX = vx * c - vy * s;
    const offY = vx * s + vy * c;

    const cam = wrapPos({ x: midWX - offX, y: midWY - offY });
    this.x = cam.x;
    this.y = cam.y;
    this.zoom = nextZoom;
    this.rotation = nextRot;
    this.follow = false;
    this.motion = null;
  }

  applyTwoFingerGesture(
    panDx: number,
    panDy: number,
    pinchFactor: number,
    twistDelta: number,
    midX: number,
    midY: number,
    viewW: number,
    viewH: number,
    focusCell: Cell,
  ): void {
    if (!this.interoception && (Math.abs(panDx) > 0.5 || Math.abs(panDy) > 0.5)) {
      this.panByScreenDelta(panDx, panDy);
    }
    if (Math.abs(pinchFactor - 1) > 0.001) {
      this.zoomAtScreenPoint(pinchFactor, midX, midY, viewW, viewH, focusCell);
    }
    if (!this.interoception && Math.abs(twistDelta) > 0.001) {
      this.rotation = wrapAngle(this.rotation - twistDelta);
      this.zoom = this.clampZoom(this.zoom, viewW, viewH, this.rotation);
    }
  }

  update(dt: number, focusCell: Cell, simTime: number): void {
    this.zoom = this.clampZoom(this.zoom);

    if (simTime < this.deathFocusUntil && !this.motion) {
      const d = offsetVec({ x: this.x, y: this.y }, this.deathSite);
      this.x = wrapPos({ x: this.x + d.x * Math.min(1, dt * 6), y: this.y + d.y * Math.min(1, dt * 6) }).x;
      this.y = wrapPos({ x: this.x + d.x * Math.min(1, dt * 6), y: this.y + d.y * Math.min(1, dt * 6) }).y;
      return;
    }

    if (this.motion) {
      this.motion.elapsed += dt;
      const t = clamp(this.motion.elapsed / Math.max(0.01, this.motion.duration), 0, 1);
      const ease = t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2;

      const targetX = this.follow && !focusCell.dead ? focusCell.position.x : this.motion.endX;
      const targetY = this.follow && !focusCell.dead ? focusCell.position.y : this.motion.endY;
      const targetRot = this.interoception && !focusCell.dead ? focusCell.angle : this.motion.endRot;

      const d = offsetVec({ x: this.motion.startX, y: this.motion.startY }, { x: targetX, y: targetY });
      const p = wrapPos({
        x: this.motion.startX + d.x * ease,
        y: this.motion.startY + d.y * ease,
      });
      this.x = p.x;
      this.y = p.y;
      this.zoom = lerp(this.motion.startZoom, this.motion.endZoom, ease);
      this.rotation = lerpAngle(this.motion.startRot, targetRot, ease);
      if (t >= 1) this.motion = null;
      return;
    }

    if (this.interoception && !focusCell.dead) {
      this.x = focusCell.position.x;
      this.y = focusCell.position.y;
      this.rotation = focusCell.angle;
      return;
    }

    if (this.follow && !focusCell.dead) {
      this.x = focusCell.position.x;
      this.y = focusCell.position.y;
    }
  }

  screenToWorld(sx: number, sy: number, viewW: number, viewH: number): Vec2 {
    const vx = (sx - viewW * 0.5) / Math.max(0.001, this.zoom);
    const vy = (sy - viewH * 0.5) / Math.max(0.001, this.zoom);
    const c = Math.cos(this.rotation);
    const s = Math.sin(this.rotation);
    return wrapPos({
      x: this.x + (vx * c - vy * s),
      y: this.y + (vx * s + vy * c),
    });
  }

  worldToScreen(wx: number, wy: number, viewW: number, viewH: number): Vec2 {
    const d = offsetVec({ x: this.x, y: this.y }, { x: wx, y: wy });
    const c = Math.cos(-this.rotation);
    const s = Math.sin(-this.rotation);
    return {
      x: viewW * 0.5 + (d.x * c - d.y * s) * this.zoom,
      y: viewH * 0.5 + (d.x * s + d.y * c) * this.zoom,
    };
  }
}
