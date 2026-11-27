import type { Cell } from '../sim/cell.ts';
import {
  MAX_INTERO_ZOOM,
  MAX_ZOOM,
  MIN_ZOOM,
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
  deathFocusUntil = -1;
  deathSite: Vec2 = { x: WORLD_W * 0.5, y: WORLD_H * 0.5 };

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

  clampZoom(z: number): number {
    const hi = this.interoception ? MAX_INTERO_ZOOM : MAX_ZOOM;
    return clamp(z, MIN_ZOOM, hi);
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
      const targetZ = clamp(Math.max(this.zoom, 4.2), MIN_ZOOM, MAX_INTERO_ZOOM);
      this.startMotion(focusCell.position.x, focusCell.position.y, targetZ, focusCell.angle, 0.65);
    } else {
      const targetZ = clamp(Math.min(this.zoom, 2.2), MIN_ZOOM, MAX_ZOOM);
      this.startMotion(focusCell.position.x, focusCell.position.y, targetZ, 0, 0.65);
    }
  }

  frameMergeNeighborhood(focus: Cell, candidates: Cell[], viewW: number, viewH: number): void {
    if (candidates.length === 0) return;
    let maxD = focus.extent() * 2.5;
    for (const c of candidates) {
      const d = offsetVec(focus.position, c.position);
      maxD = Math.max(maxD, Math.hypot(d.x, d.y) + c.extent() * 2);
    }
    const minSpan = Math.max(120, Math.min(viewW, viewH) * 0.42);
    const fitZoom = this.clampZoom(minSpan / Math.max(1, maxD));
    this.follow = true;
    this.interoception = false;
    this.startMotion(focus.position.x, focus.position.y, Math.max(MIN_ZOOM, fitZoom), 0, 0.65);
  }

  triggerDeathFraming(at: Vec2, simTime: number): void {
    this.deathSite = { ...at };
    this.deathFocusUntil = simTime + 1.8;
    this.follow = false;
    this.interoception = false;
    this.startMotion(at.x, at.y, clamp(this.zoom, MIN_ZOOM, 2.5), 0, 0.55);
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
    const before = this.follow ? focusCell.position : this.screenToWorld(sx, sy, viewW, viewH);
    this.zoom = this.clampZoom(this.zoom * factor);
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
      this.rotation = wrapAngle(this.rotation + twistDelta);
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
