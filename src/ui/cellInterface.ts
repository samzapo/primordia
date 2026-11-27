import {
  ORGAN_KINDS,
  ORGAN_SUMMARIES,
  ORGAN_TITLES,
  organUpkeepEstimate,
  type Cell,
  type Organ,
  type OrganKind,
} from '../sim/cell.ts';
import { divisionQuote } from '../sim/cellLifecycle.ts';
import { offsetVec, wrapAngle } from '../sim/constants.ts';
import { availableMutationsForOrgan, MUTATION_DATA } from '../sim/mutations.ts';
import type { Simulation } from '../sim/simulation.ts';
import { computeInteriorLandmarks, type InteriorLandmark, type LandmarkKind } from '../render/factoryLayout.ts';
import type { PondCamera } from './camera.ts';

export type HitItem =
  | { kind: 'organ'; organ: Organ; label: string; sx: number; sy: number }
  | { kind: 'scar'; scar: Organ; label: string; sx: number; sy: number }
  | { kind: 'landmark'; landmark: InteriorLandmark; label: string; sx: number; sy: number };

export interface InterfaceModalHooks {
  onOpenFamily(): void;
  onOpenPalette(): void;
  onOpenInvestment(): void;
  onNotice(msg: string): void;
  onEditOccurred(): void;
}

const ASSEMBLY_ORGANS: readonly OrganKind[] = [
  'feeding',
  'propulsion',
  'cilia',
  'protection',
  'toxin',
  'poreforming',
  'counterattack',
];

const CHEMISTRY_ORGANS: readonly OrganKind[] = [
  'photosynthesis',
  'mitochondrion',
  'regenerative',
  'neutralizing',
  'acidifying',
  'toxin_sac',
  'proboscis',
];

const RECEPTOR_ORGANS: readonly OrganKind[] = [
  'sensing',
  'hunting',
  'family_toward',
  'family_away',
];

const HIT_RADIUS_PX = 24; // >= 44 CSS px diameter touch target

export class CellInterface {
  private readonly trayEl: HTMLDivElement;
  private readonly descBarEl: HTMLDivElement;
  private readonly descTitleEl: HTMLDivElement;
  private readonly descSubEl: HTMLDivElement;
  private readonly descActionsEl: HTMLDivElement;
  private readonly cancelBtn: HTMLButtonElement;
  private readonly overlapEl: HTMLDivElement;

  private readonly organIcons: Map<OrganKind, string>;
  private readonly hooks: InterfaceModalHooks;

  active = false;
  selectedMode:
    | { type: 'none' }
    | { type: 'category'; cat: 'assembly' | 'chemistry' | 'receptors' }
    | { type: 'organ'; organId: number }
    | { type: 'scar'; scarId: number }
    | { type: 'landmark'; landmarkKind: LandmarkKind } = { type: 'none' };

  placingKind: OrganKind | null = null;
  previewAngle = 0;
  previewValid = true;
  private lastBuildKey = '';
  private lastSim: Simulation | null = null;
  private lastFocus: Cell | null = null;

  private syncRender(): void {
    if (this.lastSim && this.lastFocus) {
      this.render(this.lastSim, this.lastFocus);
    }
  }

  constructor(parent: HTMLElement, organIcons: Map<OrganKind, string>, hooks: InterfaceModalHooks) {
    this.organIcons = organIcons;
    this.hooks = hooks;

    this.cancelBtn = document.createElement('button');
    this.cancelBtn.type = 'button';
    this.cancelBtn.className = 'hud-btn cancel-placement-btn interactive is-danger';
    this.cancelBtn.textContent = 'Cancel Placement (Esc)';
    this.cancelBtn.hidden = true;
    this.cancelBtn.addEventListener('click', (e) => {
      e.stopPropagation();
      this.cancelPlacement();
    });

    this.trayEl = document.createElement('div');
    this.trayEl.className = 'action-tray hud-panel interactive';
    this.trayEl.hidden = true;

    this.descBarEl = document.createElement('div');
    this.descBarEl.className = 'bottom-desc-bar hud-panel interactive';
    this.descBarEl.hidden = true;
    const textCol = document.createElement('div');
    textCol.style.flex = '1';
    this.descTitleEl = document.createElement('div');
    this.descTitleEl.style.fontWeight = '700';
    this.descTitleEl.style.color = '#80efce';
    this.descSubEl = document.createElement('div');
    this.descSubEl.style.fontSize = '12px';
    this.descSubEl.style.color = '#c7e3ec';
    textCol.append(this.descTitleEl, this.descSubEl);
    this.descActionsEl = document.createElement('div');
    this.descActionsEl.style.display = 'flex';
    this.descActionsEl.style.gap = '6px';
    this.descActionsEl.style.flexWrap = 'wrap';
    this.descBarEl.append(textCol, this.descActionsEl);

    this.overlapEl = document.createElement('div');
    this.overlapEl.className = 'overlap-picker hud-panel interactive';
    this.overlapEl.hidden = true;

    parent.append(this.cancelBtn, this.trayEl, this.descBarEl, this.overlapEl);
  }

  get selectedOrganId(): number | null {
    return this.selectedMode.type === 'organ' ? this.selectedMode.organId : null;
  }

  cancelPlacement(): void {
    this.placingKind = null;
    this.cancelBtn.hidden = true;
    this.lastBuildKey = '';
    this.syncRender();
  }

  close(): void {
    this.active = false;
    this.placingKind = null;
    this.selectedMode = { type: 'none' };
    this.cancelBtn.hidden = true;
    this.trayEl.hidden = true;
    this.descBarEl.hidden = true;
    this.overlapEl.hidden = true;
    this.lastBuildKey = '';
  }

  openCategory(cat: 'assembly' | 'chemistry' | 'receptors'): void {
    this.active = true;
    this.placingKind = null;
    this.selectedMode = { type: 'category', cat };
    this.overlapEl.hidden = true;
    this.lastBuildKey = '';
    this.syncRender();
  }

  hitTest(cell: Cell, sx: number, sy: number, camera: PondCamera, viewW: number, viewH: number): HitItem[] {
    if (cell.dead) return [];
    const hits: HitItem[] = [];
    const r2 = HIT_RADIUS_PX * HIT_RADIUS_PX;

    for (const organ of cell.organs) {
      const wp = cell.organPosition(organ);
      const sp = camera.worldToScreen(wp.x, wp.y, viewW, viewH);
      const dx = sp.x - sx;
      const dy = sp.y - sy;
      if (dx * dx + dy * dy <= r2) {
        hits.push({
          kind: 'organ',
          organ,
          label: `${ORGAN_TITLES[organ.kind]} (HP ${organ.hp.toFixed(0)})`,
          sx: sp.x,
          sy: sp.y,
        });
      }
    }

    for (const scar of cell.lostOrgans) {
      const c = Math.cos(cell.angle);
      const s = Math.sin(cell.angle);
      const lp = cell.localPoint(scar.a);
      const wp = { x: cell.position.x + lp.x * c - lp.y * s, y: cell.position.y + lp.x * s + lp.y * c };
      const sp = camera.worldToScreen(wp.x, wp.y, viewW, viewH);
      const dx = sp.x - sx;
      const dy = sp.y - sy;
      if (dx * dx + dy * dy <= r2) {
        hits.push({
          kind: 'scar',
          scar,
          label: `Lost ${ORGAN_TITLES[scar.kind]} (Restore)`,
          sx: sp.x,
          sy: sp.y,
        });
      }
    }

    for (const lm of computeInteriorLandmarks(cell)) {
      const sp = camera.worldToScreen(lm.world.x, lm.world.y, viewW, viewH);
      const dx = sp.x - sx;
      const dy = sp.y - sy;
      if (dx * dx + dy * dy <= r2) {
        hits.push({
          kind: 'landmark',
          landmark: lm,
          label: lm.label,
          sx: sp.x,
          sy: sp.y,
        });
      }
    }

    return hits;
  }

  handleCanvasClick(
    sim: Simulation,
    cell: Cell,
    sx: number,
    sy: number,
    camera: PondCamera,
    viewW: number,
    viewH: number,
  ): boolean {
    this.overlapEl.hidden = true;
    if (cell !== sim.player || cell.dead) return false;
    this.lastSim = sim;
    this.lastFocus = cell;

    const worldClick = camera.screenToWorld(sx, sy, viewW, viewH);

    // Active organ placement mode
    if (this.placingKind) {
      this.updatePreviewAngle(cell, worldClick);
      if (!this.previewValid) {
        this.hooks.onNotice('Not enough biomass or no free membrane space at this angle');
        return true;
      }
      const installed = sim.installOrgan(this.placingKind, this.previewAngle, 'graze');
      if (installed) {
        this.hooks.onNotice(`Built ${ORGAN_TITLES[this.placingKind]}`);
        this.hooks.onEditOccurred();
        this.cancelPlacement();
      } else {
        this.hooks.onNotice('Could not install organ at this spot');
      }
      this.lastBuildKey = '';
      this.syncRender();
      return true;
    }

    const hits = this.hitTest(cell, sx, sy, camera, viewW, viewH);
    if (hits.length > 1) {
      this.active = true;
      this.lastBuildKey = '';
      this.showOverlapPicker(hits, sx, sy, viewW, viewH);
      this.syncRender();
      return true;
    }
    if (hits.length === 1) {
      this.activateHit(hits[0]);
      return true;
    }

    // Check if user tapped anywhere inside cell body to open root tray
    const d = offsetVec(cell.position, worldClick);
    if (Math.hypot(d.x, d.y) <= cell.extent() + 12) {
      this.active = true;
      this.selectedMode = { type: 'category', cat: 'assembly' };
      this.lastBuildKey = '';
      this.syncRender();
      return true;
    }

    if (this.active) {
      this.close();
      return true;
    }
    return false;
  }

  private activateHit(hit: HitItem): void {
    this.active = true;
    this.overlapEl.hidden = true;
    this.lastBuildKey = '';
    if (hit.kind === 'organ') {
      this.selectedMode = { type: 'organ', organId: hit.organ.id };
    } else if (hit.kind === 'scar') {
      this.selectedMode = { type: 'scar', scarId: hit.scar.id };
    } else {
      const k = hit.landmark.kind;
      if (k === 'assembly' || k === 'chemistry' || k === 'receptors') {
        this.selectedMode = { type: 'category', cat: k };
      } else {
        this.selectedMode = { type: 'landmark', landmarkKind: k };
      }
    }
    this.syncRender();
  }

  private showOverlapPicker(hits: HitItem[], sx: number, sy: number, viewW: number, viewH: number): void {
    const btns = hits.map((h) => {
      const b = document.createElement('button');
      b.type = 'button';
      b.className = 'hud-btn';
      b.style.justifyContent = 'flex-start';
      b.textContent = h.label;
      b.addEventListener('click', (e) => {
        e.stopPropagation();
        this.activateHit(h);
      });
      return b;
    });
    this.overlapEl.replaceChildren(...btns);
    this.overlapEl.style.left = `${Math.round(Math.min(viewW - 220, Math.max(12, sx + 10)))}px`;
    this.overlapEl.style.top = `${Math.round(Math.min(viewH - 200, Math.max(12, sy - 20)))}px`;
    this.overlapEl.hidden = false;
  }

  updatePreviewAngle(cell: Cell, worldCursor: { x: number; y: number }): void {
    const d = offsetVec(cell.position, worldCursor);
    this.previewAngle = wrapAngle(Math.atan2(d.y, d.x) - cell.angle);
    if (this.placingKind) {
      const cost = cell.constructionPrice(this.placingKind);
      this.previewValid = cell.biomass >= cost;
    }
  }

  render(sim: Simulation, focus: Cell): void {
    this.lastSim = sim;
    this.lastFocus = focus;
    if (!this.active || focus !== sim.player || focus.dead) {
      this.trayEl.hidden = true;
      this.descBarEl.hidden = true;
      this.cancelBtn.hidden = true;
      return;
    }

    this.cancelBtn.hidden = !this.placingKind;
    this.trayEl.hidden = false;
    this.descBarEl.hidden = false;

    const buildKey = JSON.stringify({
      m: this.selectedMode,
      p: this.placingKind,
      oLen: focus.organs.length,
      sLen: focus.lostOrgans.length,
      bio: Math.floor(focus.biomass),
      atp: Math.floor(focus.energy),
      mut: sim.evolution.learned.length,
    });
    if (buildKey === this.lastBuildKey) return;
    this.lastBuildKey = buildKey;

    this.rebuildTray(focus);
    this.rebuildDescriptionBar(sim, focus);
  }

  private rebuildTray(cell: Cell): void {
    const nodes: HTMLElement[] = [];

    // Top-level category tabs
    const cats: Array<{ cat: 'assembly' | 'chemistry' | 'receptors'; icon: OrganKind; title: string }> = [
      { cat: 'assembly', icon: 'feeding', title: 'Structural & Motile Organs' },
      { cat: 'chemistry', icon: 'photosynthesis', title: 'Metabolic & Chemical Glands' },
      { cat: 'receptors', icon: 'sensing', title: 'Receptors & Navigation' },
    ];
    for (const c of cats) {
      const b = document.createElement('button');
      b.type = 'button';
      b.className = 'tray-slot';
      if (this.selectedMode.type === 'category' && this.selectedMode.cat === c.cat) {
        b.classList.add('is-selected');
      }
      b.title = c.title;
      const img = document.createElement('img');
      img.src = this.organIcons.get(c.icon) ?? '';
      img.alt = c.title;
      b.appendChild(img);
      b.addEventListener('click', (e) => {
        e.stopPropagation();
        this.openCategory(c.cat);
      });
      nodes.push(b);
    }

    // Divider spacer
    const sep = document.createElement('div');
    sep.style.width = '1px';
    sep.style.height = '34px';
    sep.style.alignSelf = 'center';
    sep.style.background = 'rgba(120,175,210,0.35)';
    nodes.push(sep);

    // Context organelle buttons when a category is open, OR landmark quick slots
    const list: readonly OrganKind[] =
      this.selectedMode.type === 'category'
        ? this.selectedMode.cat === 'assembly'
          ? ASSEMBLY_ORGANS
          : this.selectedMode.cat === 'chemistry'
            ? CHEMISTRY_ORGANS
            : RECEPTOR_ORGANS
        : ORGAN_KINDS.slice(0, 5);

    for (const kind of list) {
      const price = cell.constructionPrice(kind);
      const slot = document.createElement('button');
      slot.type = 'button';
      slot.className = 'tray-slot';
      if (cell.biomass < price) slot.classList.add('is-unaffordable');
      if (this.placingKind === kind) slot.classList.add('is-selected');
      slot.dataset.organ = kind;
      slot.title = `${ORGAN_TITLES[kind]} (${price} biomass)`;

      const img = document.createElement('img');
      img.src = this.organIcons.get(kind) ?? '';
      img.alt = ORGAN_TITLES[kind];
      const badge = document.createElement('span');
      badge.className = 'tray-price';
      badge.textContent = String(price);
      slot.append(img, badge);

      slot.addEventListener('click', (e) => {
        e.stopPropagation();
        if (cell.biomass < price) {
          this.hooks.onNotice(`Need ${price} biomass for ${ORGAN_TITLES[kind]}`);
          return;
        }
        this.placingKind = kind;
        this.lastBuildKey = '';
        this.syncRender();
      });
      nodes.push(slot);
    }

    // Landmark shortcut buttons (Nucleus, Divide, ATP)
    const quick: Array<{ k: LandmarkKind; label: string; title: string }> = [
      { k: 'nucleus', label: 'Nuc', title: 'Nucleus & Family / Strategy' },
      { k: 'bud', label: 'Div', title: 'Mitosis & Budding' },
      { k: 'atp', label: 'ATP', title: 'Energy Budget Breakdown' },
    ];
    for (const q of quick) {
      const b = document.createElement('button');
      b.type = 'button';
      b.className = 'tray-slot';
      if (this.selectedMode.type === 'landmark' && this.selectedMode.landmarkKind === q.k) {
        b.classList.add('is-selected');
      }
      b.title = q.title;
      b.style.fontSize = '11px';
      b.style.fontWeight = '700';
      b.style.color = q.k === 'atp' ? '#ffd466' : '#80efce';
      b.textContent = q.label;
      b.addEventListener('click', (e) => {
        e.stopPropagation();
        this.placingKind = null;
        this.selectedMode = { type: 'landmark', landmarkKind: q.k };
        this.lastBuildKey = '';
        this.syncRender();
      });
      nodes.push(b);
    }

    this.trayEl.replaceChildren(...nodes);
  }

  private rebuildDescriptionBar(sim: Simulation, cell: Cell): void {
    this.descActionsEl.replaceChildren();
    const mkAct = (label: string, onClick: () => void, cls = ''): HTMLButtonElement => {
      const b = document.createElement('button');
      b.type = 'button';
      b.className = `hud-btn ${cls}`;
      b.style.minHeight = '36px';
      b.style.padding = '4px 10px';
      b.textContent = label;
      b.addEventListener('click', (e) => {
        e.stopPropagation();
        onClick();
      });
      return b;
    };

    if (this.placingKind) {
      const price = cell.constructionPrice(this.placingKind);
      this.descTitleEl.textContent = `Placing ${ORGAN_TITLES[this.placingKind]} · Cost ${price} biomass`;
      this.descSubEl.textContent = `Click around the cell membrane to place. ${ORGAN_SUMMARIES[this.placingKind]}`;
      return;
    }

    if (this.selectedMode.type === 'organ') {
      const organ = cell.organById(this.selectedMode.organId);
      if (!organ) {
        this.selectedMode = { type: 'category', cat: 'assembly' };
        this.lastBuildKey = '';
        return;
      }
      const upkeep = organUpkeepEstimate(organ);
      const mut = organ.mutation ? ` [${MUTATION_DATA[organ.mutation]?.short ?? organ.mutation}]` : '';
      this.descTitleEl.textContent = `${ORGAN_TITLES[organ.kind]}${mut} · HP ${organ.hp.toFixed(0)} · ${upkeep.toFixed(2)} ATP/s`;
      this.descSubEl.textContent = ORGAN_SUMMARIES[organ.kind];

      const avail = availableMutationsForOrgan(organ.kind, organ.mutation, sim.evolution.learned);
      for (const gene of avail) {
        const gLabel = MUTATION_DATA[gene]?.short ?? gene;
        this.descActionsEl.appendChild(
          mkAct(`Adapt: ${gLabel}`, () => {
            if (sim.mutateOrgan(organ.id, gene)) {
              this.hooks.onNotice(`Adapted ${ORGAN_TITLES[organ.kind]} -> ${gLabel}`);
              this.hooks.onEditOccurred();
              this.lastBuildKey = '';
            }
          }),
        );
      }

      const idx = cell.organs.indexOf(organ);
      this.descActionsEl.appendChild(
        mkAct(
          `Recycle (+${cell.constructionRefund(organ).toFixed(1)})`,
          () => {
            if (idx >= 0 && sim.removeOrgan(idx)) {
              this.hooks.onNotice(`Recycled ${ORGAN_TITLES[organ.kind]}`);
              this.hooks.onEditOccurred();
              this.selectedMode = { type: 'category', cat: 'assembly' };
              this.lastBuildKey = '';
            }
          },
          'is-danger',
        ),
      );
      return;
    }

    if (this.selectedMode.type === 'scar') {
      const targetId = this.selectedMode.scarId;
      const scar = cell.lostOrgans.find((s) => s.id === targetId);
      if (!scar) {
        this.selectedMode = { type: 'category', cat: 'assembly' };
        this.lastBuildKey = '';
        return;
      }
      const cost = cell.constructionPrice(scar.kind);
      this.descTitleEl.textContent = `Damaged ${ORGAN_TITLES[scar.kind]} Scar · Rebuild ${cost} biomass`;
      this.descSubEl.textContent = 'Restore lost organelle cleanly into its original cytoskeletal socket.';
      this.descActionsEl.appendChild(
        mkAct(`Restore (${cost})`, () => {
          if (sim.restoreOrgan(scar.id)) {
            this.hooks.onNotice(`Restored ${ORGAN_TITLES[scar.kind]}`);
            this.hooks.onEditOccurred();
            this.selectedMode = { type: 'organ', organId: scar.id };
            this.lastBuildKey = '';
          } else {
            this.hooks.onNotice(`Need ${cost} biomass to restore`);
          }
        }),
      );
      return;
    }

    if (this.selectedMode.type === 'landmark') {
      const lk = this.selectedMode.landmarkKind;
      if (lk === 'nucleus') {
        this.descTitleEl.textContent = `Cell Nucleus · Generation ${cell.generation}`;
        this.descSubEl.textContent = 'Manage lineage colors, inspect or merge relatives, or pick autonomous daughter strategy.';
        this.descActionsEl.append(
          mkAct('Family & Merge', () => this.hooks.onOpenFamily()),
          mkAct('Colors & Name', () => this.hooks.onOpenPalette()),
          mkAct('Role Strategy', () => this.hooks.onOpenInvestment()),
        );
        return;
      }
      if (lk === 'bud') {
        const mq = divisionQuote(sim, cell, 'mitosis');
        const bq = divisionQuote(sim, cell, 'budding');
        this.descTitleEl.textContent = 'Cell Division Bud · Mitosis vs Budding';
        this.descSubEl.textContent = mq.ready
          ? 'Ready for symmetric mitosis or fertile unequal budding!'
          : `Mitosis needs ${mq.material} biomass / ${mq.energy} ATP · Budding needs ${bq.material} / ${bq.energy}`;
        this.descActionsEl.append(
          mkAct(
            mq.ready ? 'Divide (Mitosis)' : `Mitosis (${Math.round(mq.progress * 100)}%)`,
            () => {
              if (sim.divideLineage('mitosis', true)) {
                this.hooks.onNotice('Divided via mitosis!');
                this.hooks.onEditOccurred();
              } else {
                this.hooks.onNotice(mq.reason || 'Not ready for mitosis');
              }
            },
            mq.ready ? 'is-active' : '',
          ),
          mkAct(
            bq.ready ? 'Bud Offspring' : `Bud (${Math.round(bq.progress * 100)}%)`,
            () => {
              if (sim.divideLineage('budding', true)) {
                this.hooks.onNotice('Budded daughter cell!');
                this.hooks.onEditOccurred();
              } else {
                this.hooks.onNotice(bq.reason || 'Not ready for budding');
              }
            },
            bq.ready ? 'is-active' : '',
          ),
        );
        return;
      }
      if (lk === 'atp') {
        const r = cell.budget.rates(sim.time);
        const topCats = [...r.categories.entries()]
          .sort((a, b) => b[1] - a[1])
          .slice(0, 4)
          .map(([k, v]) => `${k} ${v.toFixed(2)}`)
          .join(' · ');
        this.descTitleEl.textContent = `ATP Sac: ${cell.energy.toFixed(1)} ATP (+${r.production.toFixed(2)}/s, -${r.spent.toFixed(2)}/s)`;
        this.descSubEl.textContent = topCats ? `Top drains (ATP/s): ${topCats}` : 'Metabolic income & basal upkeep steady.';
        return;
      }
    }

    this.descTitleEl.textContent = 'Cell Organ Tray';
    this.descSubEl.textContent = 'Select an organelle icon above to build on the membrane, or click any installed organ to inspect & mutate it.';
  }
}
