import { offsetVec, type Vec2 } from '../sim/constants.ts';
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
  private lastTouchAtMs = -10000;

  private dragging = false;
  private dragMoved = false;
  private downX = 0;
  private downY = 0;
  private prevX = 0;
  private prevY = 0;

  private touches = new Map<number, ActiveTouch>();
  private pairAnchor: {
    anchorA: Vec2;
    anchorB: Vec2;
    startZoom: number;
    startDist: number;
  } | null = null;

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

  private captureTouchPair(): void {
    const pts = [...this.touches.values()];
    if (pts.length < 2) {
      this.pairAnchor = null;
      return;
    }
    this.pairAnchor = this.camera.capturePairAnchors(
      pts[0],
      pts[1],
      this.canvas.clientWidth,
      this.canvas.clientHeight,
    );
  }

  private bindEvents(): void {
    window.addEventListener('blur', () => {
      this.touches.clear();
      this.pairAnchor = null;
      this.dragging = false;
      this.pointerInside = false;
    });

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
      e.preventDefault();
      if (this.cellUI.placingKind) {
        this.cellUI.cancelPlacement();
      } else if (this.cb.getMergeMode()) {
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

      if (e.pointerType === 'touch') {
        this.lastTouchAtMs = performance.now();
        this.lastInputIsTouch = true;
      } else {
        // Ignore compatibility mouse events synthesized immediately after touch input
        if (this.lastInputIsTouch && performance.now() - this.lastTouchAtMs < 900) return;
        this.lastInputIsTouch = false;
      }
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
          this.pairAnchor = null;
          if (!this.cb.getMergeMode() && !this.cellUI.placingKind) {
            this.inspector.triggerTouchHold(
              e.clientX,
              e.clientY,
              performance.now() / 1000,
              this.cb.getSim(),
            );
          }
        } else if (this.touches.size === 2) {
          this.dragMoved = true;
          this.inspector.cancel(this.cb.getSim());
          this.captureTouchPair();
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
      if (e.pointerType === 'touch') {
        this.lastTouchAtMs = performance.now();
        this.lastInputIsTouch = true;
      } else {
        if (this.lastInputIsTouch && performance.now() - this.lastTouchAtMs < 900) return;
        this.lastInputIsTouch = false;
      }
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

        if (this.touches.size >= 2) {
          if (!this.pairAnchor) this.captureTouchPair();
          const pts = [...this.touches.values()];
          if (this.pairAnchor) {
            this.camera.applyAnchoredPairGesture(
              this.pairAnchor.anchorA,
              this.pairAnchor.anchorB,
              this.pairAnchor.startZoom,
              this.pairAnchor.startDist,
              pts[0],
              pts[1],
              this.canvas.clientWidth,
              this.canvas.clientHeight,
            );
          }
          this.dragMoved = true;
          this.inspector.cancel(sim);
        } else if (this.touches.size === 1) {
          const dx = e.clientX - this.prevX;
          const dy = e.clientY - this.prevY;
          if (!this.dragMoved && Math.hypot(e.clientX - this.downX, e.clientY - this.downY) > 8) {
            this.dragMoved = true;
            this.inspector.cancel(sim);
          }
          if (this.dragMoved) {
            this.camera.panByScreenDelta(dx, dy);
          }
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
        this.lastTouchAtMs = performance.now();
        const wasSingle = this.touches.size === 1;
        this.touches.delete(e.pointerId);
        if (this.touches.size === 2) {
          this.captureTouchPair();
        } else if (this.touches.size === 1) {
          // Reset single-finger delta anchor to remaining finger so releasing a pinch never jumps
          const rem = [...this.touches.values()][0];
          this.prevX = rem.x;
          this.prevY = rem.y;
          this.downX = rem.x;
          this.downY = rem.y;
          this.pairAnchor = null;
          this.dragMoved = true;
        } else {
          this.pairAnchor = null;
        }
        if (wasSingle && !this.dragMoved && e.type === 'pointerup' && !this.cb.isModalOpen()) {
          this.handleTapOrClick(e.clientX, e.clientY);
        }
        return;
      }
      if (!this.dragging) return;
      this.dragging = false;
      if (!this.dragMoved && e.button === 0 && e.type === 'pointerup' && !this.cb.isModalOpen()) {
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
          this.inspector.cancel(sim);
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
    const handledCell = this.cellUI.handleCanvasClick(sim, focus, sx, sy, this.camera, viewW, viewH);
    if (handledCell) {
      if (this.cellUI.active || this.cellUI.placingKind) {
        this.inspector.cancel(sim);
      } else if (this.lastInputIsTouch) {
        this.inspector.triggerTouchHold(sx, sy, performance.now() / 1000, sim);
      }
      return;
    }

    // Open-water / vacuole poke: keep optical particle lens & info box visible
    if (this.lastInputIsTouch) {
      this.inspector.triggerTouchHold(sx, sy, performance.now() / 1000, sim);
    }
  }
}
