import type { Cell } from '../sim/cell.ts';
import { phFromAcid } from '../sim/acidity.ts';
import { SPECIES_NAMES } from '../sim/catalog.ts';
import { MICROMETERS_PER_UNIT, SPECIES, type Vec2, offsetVec } from '../sim/constants.ts';
import type { Simulation } from '../sim/simulation.ts';
import type { InspectorRenderState } from '../render/renderer.ts';
import type { PondCamera } from './camera.ts';

export const LENS_RADIUS_PX = 68;
const CURSOR_RELEASE_PX = 24;

const SPECIES_DETAILS: readonly string[] = [
  'Food collected by grazing pores. Binding improves ATP yield; mild acid helps it bind.',
  'Supports efficient cellular respiration.',
  'Enzymes convert waste into food.',
  'Drifting cell report. Hunting & flight receptors read last-known location, size, and hostility.',
  'Damages any cell it contacts, including relatives; antitoxin can neutralize it.',
  'Photosynthesis uses dissolved CO₂ in bright water.',
  'Reuses waste as food when its binding face aligns.',
  'Binds toxin into harmless waste.',
  'Helps nutrients bind, but excessive acidity damages cells.',
  'Reduces local acidity.',
  'Temporarily competes for sensing receptors.',
];

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
  private cursorAnchorX = 0;
  private cursorAnchorY = 0;
  private internalHit: InternalInspectResult | null = null;

  constructor(parent: HTMLElement) {
    this.tooltipEl = document.createElement('div');
    this.tooltipEl.className = 'inspector-tip hud-panel';
    this.tooltipEl.hidden = true;
    parent.appendChild(this.tooltipEl);
  }

  triggerTouchHold(sx: number, sy: number, nowPerf: number, sim?: Simulation): void {
    const wasActive = this.active;
    const moved = Math.hypot(sx - this.screenX, sy - this.screenY) > 16;
    this.screenX = sx;
    this.screenY = sy;
    this.cursorAnchorX = sx;
    this.cursorAnchorY = sy;
    this.touchHoldUntil = nowPerf + 3.5;
    this.active = true;
    if (moved || !wasActive) {
      this.trackUntil = -1;
      if (sim) {
        sim.inspectCursor.trackedSlot = -1;
        sim.inspectCursor.trackedGen = 0;
        sim.lastInspected = null;
      }
    }
  }

  cancel(sim?: Simulation): void {
    this.active = false;
    this.touchHoldUntil = -1;
    this.trackUntil = -1;
    this.internalHit = null;
    this.tooltipEl.hidden = true;
    if (sim) {
      sim.inspectCursor.active = false;
      sim.inspectCursor.trackedSlot = -1;
      sim.lastInspected = null;
    }
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
      if (Math.hypot(pointerX - this.cursorAnchorX, pointerY - this.cursorAnchorY) > CURSOR_RELEASE_PX) {
        this.trackUntil = -1;
        sim.inspectCursor.trackedSlot = -1;
        this.cursorAnchorX = pointerX;
        this.cursorAnchorY = pointerY;
      }
      this.screenX = pointerX;
      this.screenY = pointerY;
      this.active = true;
    } else {
      this.active = false;
    }

    const wp = camera.screenToWorld(this.screenX, this.screenY, viewW, viewH);

    // Exteroception: suppress when poking/hovering directly over or near any living cell
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
      let bestDist = Math.max(14, 18 / Math.max(1, camera.zoom));
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

    // Render informative tooltip anchored cleanly near lens
    this.renderTooltip(sim, wp, camera.interoception, ins, viewW, viewH);

    return {
      active: true,
      screenX: this.screenX,
      screenY: this.screenY,
      radiusPx: LENS_RADIUS_PX,
    };
  }

  private renderTooltip(
    sim: Simulation,
    wp: Vec2,
    intero: boolean,
    ins: Simulation['lastInspected'],
    viewW: number,
    viewH: number,
  ): void {
    const lines: Array<{ text: string; bold?: boolean }> = [];
    if (this.internalHit) {
      const h = this.internalHit;
      lines.push({ text: `Internal ${h.species.toUpperCase()}`, bold: true });
      if (h.species === 'food') {
        lines.push({ text: 'Food vacuole · respires with O₂ or ferments to ATP & biomass.' });
        lines.push({
          text: `Amount: ${h.amount.toFixed(2)} · Reserve: ${h.fuel.toFixed(1)} ATP · +${h.nutrition.toFixed(2)} nutrition`,
        });
      } else if (h.species === 'waste') {
        lines.push({ text: 'Waste vacuole · carried toward excretion pore.' });
        lines.push({ text: `Amount: ${h.amount.toFixed(2)} units` });
      } else {
        lines.push({ text: `Amount: ${h.amount.toFixed(2)} units` });
      }
      lines.push({ text: `Residence: ${h.age.toFixed(1)}s` });
    } else if (ins && ins.valid && (!intero || ins.kind === SPECIES.PHEROMONE)) {
      const name = SPECIES_NAMES[ins.kind] ?? `Species ${ins.kind}`;
      lines.push({ text: name, bold: true });
      if (ins.kind >= 0 && ins.kind < SPECIES_DETAILS.length) {
        lines.push({ text: SPECIES_DETAILS[ins.kind] });
      }
      if (ins.kind === SPECIES.PHEROMONE && ins.report) {
        const rep = ins.report;
        const age = Math.max(0, sim.time - rep.emittedAt).toFixed(1);
        const rem = Math.max(0, ins.expiresAt - sim.time).toFixed(1);
        const linLabel = sim.lineageNames.get(rep.lineage) ?? `Lineage ${rep.lineage}`;
        const acrossUm = Math.round(rep.radius * 2 * MICROMETERS_PER_UNIT);
        lines.push({ text: `${linLabel} · Reported ${acrossUm} μm across · Mass ${rep.mass.toFixed(1)}` });
        lines.push({
          text: `${rep.hostile ? 'Armed' : 'Unarmed'} · ${rep.defended ? 'Defended' : 'Undefended'} at emission`,
        });
        lines.push({ text: `Emitted ${age}s ago · decays in ${rem}s` });
      } else {
        lines.push({ text: `Amount: ${ins.amount.toFixed(2)} units` });
        if (ins.kind === SPECIES.NUTRIENT && ins.amount > 1e-8) {
          const bonusPct = Math.round(Math.max(0, Math.min(0.5, ins.capacity / ins.amount - 1)) * 100);
          lines.push({ text: `Binding: +${bonusPct}% ATP yield` });
        } else if (ins.kind === SPECIES.ACID || ins.kind === SPECIES.BUFFER) {
          const ph = phFromAcid(sim.acidity.sample(wp.x, wp.y));
          lines.push({ text: `Local water pH ${ph.toFixed(1)}` });
        } else if (ins.capacity > 0.01) {
          lines.push({ text: `Reactive Charge: ${ins.capacity.toFixed(2)}` });
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
        strong.style.color = '#80efce';
        strong.textContent = entry.text;
        row.appendChild(strong);
      } else {
        row.textContent = entry.text;
      }
      return row;
    });
    this.tooltipEl.replaceChildren(...nodes);
    this.tooltipEl.hidden = false;
    const tipRect = this.tooltipEl.getBoundingClientRect();
    const tipW = Math.max(200, tipRect.width || 250);
    const tipH = Math.max(64, tipRect.height || 96);

    let tipX = this.screenX + LENS_RADIUS_PX + 12;
    let tipY = this.screenY - tipH * 0.5;
    if (tipX + tipW + 12 > viewW) {
      tipX = this.screenX - LENS_RADIUS_PX - tipW - 12;
    }
    if (tipX < 10) {
      // Narrow mobile viewport: place cleanly above or below lens
      tipX = Math.max(10, Math.min(viewW - tipW - 10, this.screenX - tipW * 0.5));
      tipY = this.screenY > tipH + LENS_RADIUS_PX + 24
        ? this.screenY - LENS_RADIUS_PX - tipH - 12
        : this.screenY + LENS_RADIUS_PX + 12;
    }
    tipX = Math.min(viewW - tipW - 10, Math.max(10, tipX));
    tipY = Math.min(viewH - tipH - 12, Math.max(12, tipY));
    this.tooltipEl.style.left = `${Math.round(tipX)}px`;
    this.tooltipEl.style.top = `${Math.round(tipY)}px`;
  }
}
