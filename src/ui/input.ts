import { offsetVec } from '../sim/constants.ts';
import type { Simulation } from '../sim/simulation.ts';
import type { PondCamera } from './camera.ts';
import type { CellInterface } from './cellInterface.ts';
import type { ParticleInspector } from './inspector.ts';

export interface InputCallbacks {
  getSim(): Simulation;
  getMergeMode(): boolean;
  setMergeMode(v: boolean): void;
  isModalOpen(): boolean;
  onUserGesture(): void;
  onTogglePause(): void;
  onToggleFollow(): void;
  onToggleIntero(): void;
  onToggleMute(): void;
  onToggleTelemetry(): void;
  onOpenGuide(): void;
  onOpenSettings(): void;
  onEscape(): void;
  onNotice(msg: string): void;
  onEditOccurred(): void;
}

interface ActiveTouch {
  id: number;
  x: number;
  y: number;
}

export class InputController {
  private readonly canvas: HTMLCanvasElement;
  private readonly camera: PondCamera;
  private readonly cellUI: CellInterface;
  private readonly inspector: ParticleInspector;
  private readonly cb: InputCallbacks;

  pointerX = 0;
  pointerY = 0;
  pointerInside = false;
  lastInputIsTouch = false;

  private dragging = false;
  private dragMoved = false;
  private downX = 0;
  private downY = 0;
  private prevX = 0;
  private prevY = 0;

  private touches = new Map<number, ActiveTouch>();
  private prevPinchDist = 0;
  private prevPinchAngle = 0;
  private prevPinchMidX = 0;
  private prevPinchMidY = 0;

  private touchHoldTimer: number | null = null;
  private lastTapTime = 0;
  private lastTapCellId = -1;

  constructor(
    canvas: HTMLCanvasElement,
    camera: PondCamera,
    cellUI: CellInterface,
    inspector: ParticleInspector,
    cb: InputCallbacks,
  ) {
    this.canvas = canvas;
    this.camera = camera;
    this.cellUI = cellUI;
    this.inspector = inspector;
    this.cb = cb;

    this.bindEvents();
  }

  private isUiTarget(target: EventTarget | null): boolean {
    if (!(target instanceof Element)) return false;
    return target.closest('.interactive') !== null;
  }

  private clearHoldTimer(): void {
    if (this.touchHoldTimer !== null) {
      window.clearTimeout(this.touchHoldTimer);
      this.touchHoldTimer = null;
    }
  }

  private bindEvents(): void {
    window.addEventListener('keydown', (e) => {
      if (e.target instanceof HTMLInputElement || e.target instanceof HTMLSelectElement || e.target instanceof HTMLTextAreaElement) {
        return;
      }
      this.cb.onUserGesture();
      const k = e.key.toLowerCase();
      if (k === ' ' || k === 'p') {
        e.preventDefault();
        this.cb.onTogglePause();
      } else if (k === 'f') {
        e.preventDefault();
        this.cb.onToggleFollow();
      } else if (k === 'i' || e.key === 'Tab') {
        e.preventDefault();
        this.cb.onToggleIntero();
      } else if (k === 'm') {
        e.preventDefault();
        this.cb.onToggleMute();
      } else if (e.key === 'F3') {
        e.preventDefault();
        this.cb.onToggleTelemetry();
      } else if (e.key === 'F1' || k === '?') {
        e.preventDefault();
        this.cb.onOpenGuide();
      } else if (k === '=' || k === '+') {
        e.preventDefault();
        const sim = this.cb.getSim();
        this.camera.zoomAtScreenPoint(1.25, this.canvas.clientWidth * 0.5, this.canvas.clientHeight * 0.5, this.canvas.clientWidth, this.canvas.clientHeight, sim.player);
      } else if (k === '-' || k === '_') {
        e.preventDefault();
        const sim = this.cb.getSim();
        this.camera.zoomAtScreenPoint(1 / 1.25, this.canvas.clientWidth * 0.5, this.canvas.clientHeight * 0.5, this.canvas.clientWidth, this.canvas.clientHeight, sim.player);
      } else if (e.key === 'Escape') {
        e.preventDefault();
        this.cb.onEscape();
      }
    });

    this.canvas.addEventListener('contextmenu', (e) => {
      if (this.cellUI.placingKind) {
        e.preventDefault();
        this.cellUI.cancelPlacement();
      } else if (this.cb.getMergeMode()) {
        e.preventDefault();
        this.cb.setMergeMode(false);
      }
    });

    this.canvas.addEventListener('wheel', (e) => {
      e.preventDefault();
      this.cb.onUserGesture();
      if (this.cb.isModalOpen()) return;
      const factor = Math.exp(-e.deltaY * 0.0014);
      const sim = this.cb.getSim();
      const focus = sim.cells.find((c) => c.id === this.camera.focusCellId && !c.dead) ?? sim.player;
      this.camera.zoomAtScreenPoint(factor, e.clientX, e.clientY, this.canvas.clientWidth, this.canvas.clientHeight, focus);
    }, { passive: false });

    this.canvas.addEventListener('pointerdown', (e) => {
      this.cb.onUserGesture();
      if (this.isUiTarget(e.target) || this.cb.isModalOpen()) return;

      this.lastInputIsTouch = e.pointerType === 'touch';
      this.pointerX = e.clientX;
      this.pointerY = e.clientY;
      this.pointerInside = true;

      if (e.pointerType === 'touch') {
        this.touches.set(e.pointerId, { id: e.pointerId, x: e.clientX, y: e.clientY });
        try { this.canvas.setPointerCapture(e.pointerId); } catch { /* synthetic event */ }
        if (this.touches.size === 1) {
          this.downX = e.clientX;
          this.downY = e.clientY;
          this.prevX = e.clientX;
          this.prevY = e.clientY;
          this.dragMoved = false;
          this.clearHoldTimer();
          this.touchHoldTimer = window.setTimeout(() => {
            if (!this.dragMoved && this.touches.size === 1) {
              this.inspector.triggerTouchHold(e.clientX, e.clientY, performance.now() / 1000);
            }
          }, 2500);
        } else if (this.touches.size === 2) {
          this.clearHoldTimer();
          const pts = [...this.touches.values()];
          this.prevPinchDist = Math.hypot(pts[1].x - pts[0].x, pts[1].y - pts[0].y);
          this.prevPinchAngle = Math.atan2(pts[1].y - pts[0].y, pts[1].x - pts[0].x);
          this.prevPinchMidX = (pts[0].x + pts[1].x) * 0.5;
          this.prevPinchMidY = (pts[0].y + pts[1].y) * 0.5;
        }
        return;
      }

      if (e.button === 0 || e.button === 1) {
        this.dragging = true;
        this.dragMoved = false;
        this.downX = e.clientX;
        this.downY = e.clientY;
        this.prevX = e.clientX;
        this.prevY = e.clientY;
        try { this.canvas.setPointerCapture(e.pointerId); } catch { /* synthetic event */ }
      }
    });

    this.canvas.addEventListener('pointermove', (e) => {
      this.lastInputIsTouch = e.pointerType === 'touch';
      this.pointerX = e.clientX;
      this.pointerY = e.clientY;
      this.pointerInside = true;

      const sim = this.cb.getSim();
      const focus = sim.cells.find((c) => c.id === this.camera.focusCellId && !c.dead) ?? sim.player;

      if (this.cellUI.placingKind && !focus.dead) {
        const wp = this.camera.screenToWorld(e.clientX, e.clientY, this.canvas.clientWidth, this.canvas.clientHeight);
        this.cellUI.updatePreviewAngle(focus, wp);
      }

      if (e.pointerType === 'touch') {
        const t = this.touches.get(e.pointerId);
        if (!t) return;
        t.x = e.clientX;
        t.y = e.clientY;

        if (this.touches.size === 2) {
          const pts = [...this.touches.values()];
          const midX = (pts[0].x + pts[1].x) * 0.5;
          const midY = (pts[0].y + pts[1].y) * 0.5;
          const dist = Math.hypot(pts[1].x - pts[0].x, pts[1].y - pts[0].y);
          const ang = Math.atan2(pts[1].y - pts[0].y, pts[1].x - pts[0].x);
          const panDx = midX - this.prevPinchMidX;
          const panDy = midY - this.prevPinchMidY;
          const pinchFactor = this.prevPinchDist > 4 ? dist / this.prevPinchDist : 1;
          let twist = ang - this.prevPinchAngle;
          if (twist > Math.PI) twist -= Math.PI * 2;
          if (twist < -Math.PI) twist += Math.PI * 2;
          this.camera.applyTwoFingerGesture(
            panDx,
            panDy,
            pinchFactor,
            twist,
            midX,
            midY,
            this.canvas.clientWidth,
            this.canvas.clientHeight,
            focus,
          );
          this.prevPinchMidX = midX;
          this.prevPinchMidY = midY;
          this.prevPinchDist = dist;
          this.prevPinchAngle = ang;
          this.dragMoved = true;
        } else if (this.touches.size === 1) {
          const dx = e.clientX - this.prevX;
          const dy = e.clientY - this.prevY;
          if (Math.hypot(e.clientX - this.downX, e.clientY - this.downY) > 7) {
            this.dragMoved = true;
            this.clearHoldTimer();
          }
          if (this.dragMoved) this.camera.panByScreenDelta(dx, dy);
          this.prevX = e.clientX;
          this.prevY = e.clientY;
        }
        return;
      }

      if (this.dragging) {
        const dx = e.clientX - this.prevX;
        const dy = e.clientY - this.prevY;
        if (Math.hypot(e.clientX - this.downX, e.clientY - this.downY) > 5) {
          this.dragMoved = true;
        }
        if (this.dragMoved) {
          this.camera.panByScreenDelta(dx, dy);
        }
        this.prevX = e.clientX;
        this.prevY = e.clientY;
      }
    });

    const handleUp = (e: PointerEvent) => {
      if (e.pointerType === 'touch') {
        this.clearHoldTimer();
        const wasSingle = this.touches.size === 1;
        this.touches.delete(e.pointerId);
        if (wasSingle && !this.dragMoved && !this.cb.isModalOpen()) {
          this.handleTapOrClick(e.clientX, e.clientY);
        }
        return;
      }
      if (!this.dragging) return;
      this.dragging = false;
      if (!this.dragMoved && e.button === 0 && !this.cb.isModalOpen()) {
        this.handleTapOrClick(e.clientX, e.clientY);
      }
    };

    this.canvas.addEventListener('pointerup', handleUp);
    this.canvas.addEventListener('pointercancel', handleUp);
    this.canvas.addEventListener('pointerleave', () => {
      this.pointerInside = false;
      this.dragging = false;
    });
  }

  private handleTapOrClick(sx: number, sy: number): void {
    const sim = this.cb.getSim();
    const viewW = this.canvas.clientWidth;
    const viewH = this.canvas.clientHeight;
    const wp = this.camera.screenToWorld(sx, sy, viewW, viewH);

    // Handle active family merge donor click
    if (this.cb.getMergeMode()) {
      const cands = sim.mergeCandidatesForPlayer();
      for (const donorId of cands.keys()) {
        const c = sim.cells.find((x) => x.id === donorId && !x.dead);
        if (!c) continue;
        const d = offsetVec(c.position, wp);
        if (Math.hypot(d.x, d.y) <= c.extent() + 14) {
          if (sim.requestMerge(donorId)) {
            this.cb.onNotice('Merged family cell into current cell');
            this.cb.onEditOccurred();
          }
          this.cb.setMergeMode(false);
          return;
        }
      }
      this.cb.setMergeMode(false);
      return;
    }

    const focus = sim.cells.find((c) => c.id === this.camera.focusCellId && !c.dead) ?? sim.player;

    // Double-tap / double-click living family relative -> switch to it
    const now = performance.now();
    for (const c of sim.cells) {
      if (c.dead || c === sim.player || c.lineageId() !== sim.player.lineageId()) continue;
      const d = offsetVec(c.position, wp);
      if (Math.hypot(d.x, d.y) <= c.extent() + 10) {
        if (now - this.lastTapTime <= 400 && this.lastTapCellId === c.id) {
          sim.followFamily(c.id);
          this.camera.setFocusCell(c, true);
          this.cellUI.close();
          this.lastTapTime = 0;
          this.lastTapCellId = -1;
          return;
        }
        this.lastTapTime = now;
        this.lastTapCellId = c.id;
        return;
      }
    }

    // Normal focus cell interaction / organ placement
    this.cellUI.handleCanvasClick(sim, focus, sx, sy, this.camera, viewW, viewH);
  }
}
