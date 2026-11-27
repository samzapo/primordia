import type { Cell } from '../sim/cell.ts';
import { SPECIES_NAMES } from '../sim/catalog.ts';
import { SPECIES, type Vec2, offsetVec } from '../sim/constants.ts';
import type { Simulation } from '../sim/simulation.ts';
import type { InspectorRenderState } from '../render/renderer.ts';
import type { PondCamera } from './camera.ts';

export const LENS_RADIUS_PX = 68;

interface InternalInspectResult {
  species: string;
  amount: number;
  age: number;
  fuel: number;
  nutrition: number;
}

export class ParticleInspector {
  readonly tooltipEl: HTMLDivElement;

  active = false;
  screenX = 0;
  screenY = 0;
  radiusPx = LENS_RADIUS_PX;

  private touchHoldUntil = -1;
  private trackUntil = -1;
  private internalHit: InternalInspectResult | null = null;

  constructor(parent: HTMLElement) {
    this.tooltipEl = document.createElement('div');
    this.tooltipEl.className = 'inspector-tip hud-panel';
    this.tooltipEl.hidden = true;
    parent.appendChild(this.tooltipEl);
  }

  triggerTouchHold(sx: number, sy: number, nowPerf: number): void {
    this.screenX = sx;
    this.screenY = sy;
    this.touchHoldUntil = nowPerf + 2.5;
    this.active = true;
  }

  cancel(): void {
    this.active = false;
    this.touchHoldUntil = -1;
    this.trackUntil = -1;
    this.internalHit = null;
    this.tooltipEl.hidden = true;
  }

  update(
    sim: Simulation,
    focus: Cell,
    camera: PondCamera,
    pointerX: number,
    pointerY: number,
    pointerInsideCanvas: boolean,
    isTouch: boolean,
    blockedByUi: boolean,
    viewW: number,
    viewH: number,
    nowPerf: number,
  ): InspectorRenderState {
    if (blockedByUi) {
      this.active = false;
      sim.inspectCursor.active = false;
      this.tooltipEl.hidden = true;
      return { active: false, screenX: 0, screenY: 0, radiusPx: 0 };
    }

    if (isTouch) {
      if (nowPerf > this.touchHoldUntil) {
        this.active = false;
      }
    } else if (pointerInsideCanvas) {
      this.screenX = pointerX;
      this.screenY = pointerY;
      this.active = true;
    } else {
      this.active = false;
    }

    const wp = camera.screenToWorld(this.screenX, this.screenY, viewW, viewH);

    // Exteroception: suppress immediately when pointer is over or near any living cell
    if (!camera.interoception && this.active) {
      for (const c of sim.cells) {
        if (c.dead) continue;
        const d = offsetVec(c.position, wp);
        const tol = c.extent() + 8 / Math.max(0.8, camera.zoom);
        if (Math.hypot(d.x, d.y) <= tol) {
          this.active = false;
          sim.inspectCursor.active = false;
          sim.inspectCursor.trackedSlot = -1;
          this.trackUntil = -1;
          this.tooltipEl.hidden = true;
          return { active: false, screenX: this.screenX, screenY: this.screenY, radiusPx: 0 };
        }
      }
    }

    if (!this.active) {
      sim.inspectCursor.active = false;
      sim.inspectCursor.trackedSlot = -1;
      this.tooltipEl.hidden = true;
      return { active: false, screenX: this.screenX, screenY: this.screenY, radiusPx: 0 };
    }

    // Interoception: check internal cytoplasmic vacuoles & gases inside focus cell
    this.internalHit = null;
    if (camera.interoception && !focus.dead) {
      const d = offsetVec(focus.position, wp);
      const ca = Math.cos(-focus.angle);
      const sa = Math.sin(-focus.angle);
      const local: Vec2 = { x: d.x * ca - d.y * sa, y: d.x * sa + d.y * ca };
      let bestDist = 14 / Math.max(1, camera.zoom);
      for (const p of focus.chemistry.particles) {
        if (!p.alive) continue;
        const pd = Math.hypot(p.p.x - local.x, p.p.y - local.y);
        if (pd < bestDist) {
          bestDist = pd;
          this.internalHit = {
            species: p.species,
            amount: p.amount,
            age: p.age,
            fuel: p.fuel,
            nutrition: p.nutrition,
          };
        }
      }
    }

    // Sync external particle query tracking (0.9s identity lock)
    const worldRadius = LENS_RADIUS_PX / Math.max(0.8, camera.zoom);
    sim.inspectCursor.active = true;
    sim.inspectCursor.x = wp.x;
    sim.inspectCursor.y = wp.y;
    sim.inspectCursor.maxRadius = Math.min(85, worldRadius);

    const ins = sim.lastInspected;
    if (ins && ins.valid) {
      if (nowPerf <= this.trackUntil || sim.inspectCursor.trackedSlot === ins.slot) {
        sim.inspectCursor.trackedSlot = ins.slot;
        sim.inspectCursor.trackedGen = ins.gen;
        if (nowPerf > this.trackUntil) this.trackUntil = nowPerf + 0.9;
      } else {
        sim.inspectCursor.trackedSlot = ins.slot;
        sim.inspectCursor.trackedGen = ins.gen;
        this.trackUntil = nowPerf + 0.9;
      }
    } else {
      sim.inspectCursor.trackedSlot = -1;
    }

    // Render informative tooltip anchored just right of the lens
    this.renderTooltip(sim, camera.interoception, ins, viewW, viewH);

    return {
      active: true,
      screenX: this.screenX,
      screenY: this.screenY,
      radiusPx: LENS_RADIUS_PX,
    };
  }

  private renderTooltip(
    sim: Simulation,
    intero: boolean,
    ins: Simulation['lastInspected'],
    viewW: number,
    viewH: number,
  ): void {
    const lines: Array<{ text: string; bold?: boolean }> = [];
    if (this.internalHit) {
      const h = this.internalHit;
      lines.push({ text: `Internal ${h.species.toUpperCase()}`, bold: true });
      lines.push({ text: `Amount: ${h.amount.toFixed(2)} units` });
      if (h.species === 'food') {
        lines.push({
          text: `Energy Reserve: ${h.fuel.toFixed(1)} ATP · +${h.nutrition.toFixed(2)} nutrition`,
        });
      }
      lines.push({ text: `Residence: ${h.age.toFixed(1)}s` });
    } else if (ins && ins.valid && (!intero || ins.kind === SPECIES.PHEROMONE)) {
      const name = SPECIES_NAMES[ins.kind] ?? `Species ${ins.kind}`;
      lines.push({ text: name, bold: true });
      if (ins.kind === SPECIES.PHEROMONE && ins.report) {
        const rep = ins.report;
        const age = Math.max(0, sim.time - rep.emittedAt).toFixed(1);
        const rem = Math.max(0, ins.expiresAt - sim.time).toFixed(1);
        const linLabel = sim.lineageNames.get(rep.lineage) ?? `Lineage ${rep.lineage}`;
        lines.push({ text: `${linLabel} · Snapshot Mass ${rep.mass.toFixed(1)}` });
        lines.push({ text: `Emitted ${age}s ago · decays in ${rem}s` });
        if (rep.hostile || rep.defended) {
          lines.push({
            text: `${rep.hostile ? 'Offensive organs' : ''}${rep.hostile && rep.defended ? ' · ' : ''}${rep.defended ? 'Defended' : ''}`,
          });
        }
      } else {
        lines.push({ text: `Amount: ${ins.amount.toFixed(2)} units` });
        if (ins.capacity > 0.01) {
          lines.push({
            text:
              ins.kind === SPECIES.NUTRIENT
                ? `Fuel Capacity: ${ins.capacity.toFixed(2)}`
                : `Reactive Charge: ${ins.capacity.toFixed(2)}`,
          });
        }
      }
    } else {
      this.tooltipEl.hidden = true;
      return;
    }

    const nodes = lines.map((entry) => {
      const row = document.createElement('div');
      if (entry.bold) {
        const strong = document.createElement('strong');
        strong.textContent = entry.text;
        row.appendChild(strong);
      } else {
        row.textContent = entry.text;
      }
      return row;
    });
    this.tooltipEl.replaceChildren(...nodes);
    this.tooltipEl.hidden = false;
    const tipX = Math.min(viewW - 270, Math.max(12, this.screenX + LENS_RADIUS_PX + 12));
    const tipY = Math.min(viewH - 110, Math.max(12, this.screenY - 24));
    this.tooltipEl.style.left = `${Math.round(tipX)}px`;
    this.tooltipEl.style.top = `${Math.round(tipY)}px`;
  }
}
