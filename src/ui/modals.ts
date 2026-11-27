import playerGuideJson from '../data/player_guide.json' with { type: 'json' };
import { drawOrganIcon2D } from '../render/atlasGenerator.ts';
import {
  LINEAGE_PALETTE_PRESETS,
  hsvToRgb,
  lineagePalette,
  ORGAN_COLORS,
  parseHex,
  rgbToHex,
  rgbToHsv,
} from '../render/palette.ts';
import type { Cell, OrganKind } from '../sim/cell.ts';
import { TAU } from '../sim/constants.ts';
import type { InvestmentStrategy, RoleName } from '../sim/investmentPolicy.ts';
import { rawStrategyForCell } from '../sim/investmentPolicy.ts';
import { MUTATION_DATA } from '../sim/mutations.ts';
import type { Simulation } from '../sim/simulation.ts';

export type ModalKind =
  | 'none'
  | 'settings'
  | 'family'
  | 'palette'
  | 'investment'
  | 'guide'
  | 'vacuoles'
  | 'mutation_offer';

export interface VisualPrefs {
  bloomEnabled: boolean;
  ripplesEnabled: boolean;
  blurEnabled: boolean;
  simpleParticles: boolean;
}

export interface ModalCallbacks {
  getVisualPrefs(): VisualPrefs;
  setVisualPrefs(next: Partial<VisualPrefs>): void;
  onNewExpedition(seed: number, habitat: number): void;
  onResetPrefs(): void;
  onEnterMergeMode(): void;
  onFollowCell(cell: Cell): void;
  onLineageStyleChanged(lineageId: number, hex?: string, name?: string): void;
  onNotice(msg: string): void;
  onResumeRequest(): void;
}

interface GuideEntry {
  id: string;
  title: string;
  text: string;
  sources: Array<{ title: string; url: string }>;
}

interface GuideDoc {
  gameplay: { common: GuideEntry[]; desktop: GuideEntry[]; touch: GuideEntry[] };
  mechanics: Array<{ id: string; title: string; items: GuideEntry[] }>;
}

const GUIDE_DATA = playerGuideJson as GuideDoc;

function makeCellPortrait(
  seed: number,
  cell: Cell,
  customHex: string | undefined,
  size: number,
): HTMLCanvasElement {
  const c = document.createElement('canvas');
  c.width = size;
  c.height = size;
  const ctx = c.getContext('2d')!;
  const half = size * 0.5;
  const pal = lineagePalette(seed, cell.lineageId(), customHex);
  const pts = cell.membrane.outline();
  let maxR = 1;
  for (const p of pts) maxR = Math.max(maxR, Math.hypot(p.x, p.y));
  const sc = (size * 0.36) / maxR;

  ctx.save();
  ctx.translate(half, half);
  ctx.rotate(cell.angle * 0.25);
  ctx.beginPath();
  for (let i = 0; i < pts.length; i++) {
    const x = pts[i].x * sc;
    const y = pts[i].y * sc;
    if (i === 0) ctx.moveTo(x, y);
    else ctx.lineTo(x, y);
  }
  ctx.closePath();

  const grad = ctx.createRadialGradient(-size * 0.1, -size * 0.1, size * 0.04, 0, 0, size * 0.42);
  grad.addColorStop(0, pal.shine);
  grad.addColorStop(0.55, pal.body);
  grad.addColorStop(1, pal.gel);
  ctx.fillStyle = grad;
  ctx.fill();
  ctx.lineWidth = 2.4;
  ctx.strokeStyle = pal.edge;
  ctx.stroke();

  // Nucleus
  ctx.fillStyle = pal.nucleus;
  ctx.beginPath();
  ctx.arc(0, 0, size * 0.11, 0, TAU);
  ctx.fill();

  // Exterior organ beads
  for (const o of cell.organs) {
    const lp = cell.localPoint(o.a);
    ctx.fillStyle = ORGAN_COLORS[o.kind];
    ctx.beginPath();
    ctx.arc(lp.x * sc, lp.y * sc, Math.max(2.5, size * 0.055), 0, TAU);
    ctx.fill();
  }
  ctx.restore();
  return c;
}

function drawRoleSketch(ctx: CanvasRenderingContext2D, role: RoleName, cx: number, cy: number, r: number): void {
  const palette: Record<RoleName, { body: string; rim: string; organs: OrganKind[] }> = {
    grazer: { body: '#24829c', rim: '#6ae8cf', organs: ['feeding', 'cilia', 'regenerative', 'sensing'] },
    producer: { body: '#1f8a5b', rim: '#8af59b', organs: ['photosynthesis', 'photosynthesis', 'mitochondrion', 'protection'] },
    hunter: { body: '#c94148', rim: '#ffa452', organs: ['hunting', 'poreforming', 'toxin', 'propulsion', 'feeding'] },
    parasite: { body: '#8938b5', rim: '#f078e2', organs: ['proboscis', 'hunting', 'sensing', 'mitochondrion'] },
  };
  const spec = palette[role];
  ctx.save();
  const g = ctx.createRadialGradient(cx - r * 0.25, cy - r * 0.25, r * 0.1, cx, cy, r);
  g.addColorStop(0, spec.rim);
  g.addColorStop(0.65, spec.body);
  g.addColorStop(1, '#10203a');
  ctx.fillStyle = g;
  ctx.beginPath();
  const lob = role === 'hunter' ? 6 : role === 'parasite' ? 4 : 12;
  for (let i = 0; i < 36; i++) {
    const a = (TAU * i) / 36;
    const w = 1 + (role === 'hunter' ? 0.14 : 0.06) * Math.cos(a * lob);
    const x = cx + Math.cos(a) * r * w;
    const y = cy + Math.sin(a) * r * w;
    if (i === 0) ctx.moveTo(x, y);
    else ctx.lineTo(x, y);
  }
  ctx.closePath();
  ctx.fill();
  ctx.lineWidth = 2;
  ctx.strokeStyle = spec.rim;
  ctx.stroke();

  const iconSize = Math.max(12, Math.round(r * 0.55));
  const tmp = document.createElement('canvas');
  tmp.width = iconSize;
  tmp.height = iconSize;
  const tctx = tmp.getContext('2d')!;
  for (let i = 0; i < spec.organs.length; i++) {
    const a = (TAU * i) / spec.organs.length;
    drawOrganIcon2D(tctx, spec.organs[i], iconSize);
    ctx.drawImage(tmp, cx + Math.cos(a) * r * 0.85 - iconSize * 0.5, cy + Math.sin(a) * r * 0.85 - iconSize * 0.5);
  }
  ctx.restore();
}

function makeRolePortrait(role: RoleName | 'balanced', size = 84): HTMLCanvasElement {
  const c = document.createElement('canvas');
  c.width = size;
  c.height = size;
  const ctx = c.getContext('2d')!;
  if (role === 'balanced') {
    const q = size * 0.25;
    drawRoleSketch(ctx, 'grazer', q, q, size * 0.17);
    drawRoleSketch(ctx, 'producer', size - q, q, size * 0.17);
    drawRoleSketch(ctx, 'hunter', q, size - q, size * 0.17);
    drawRoleSketch(ctx, 'parasite', size - q, size - q, size * 0.17);
  } else {
    drawRoleSketch(ctx, role, size * 0.5, size * 0.5, size * 0.34);
  }
  return c;
}

// Shirley-Chiu disc <-> square warp so the inner SV square fills the disc seamlessly
function discToSquare(u: number, v: number): [number, number] {
  const r2 = u * u + v * v;
  if (r2 < 1e-8) return [0, 0];
  const r = Math.sqrt(r2);
  let x = 0;
  let y = 0;
  if (Math.abs(u) > Math.abs(v)) {
    const phi = (Math.PI / 4) * (v / u);
    x = u > 0 ? r : -r;
    y = x * (phi / (Math.PI / 4));
  } else {
    const phi = (Math.PI / 4) * (u / v);
    y = v > 0 ? r : -r;
    x = y * (phi / (Math.PI / 4));
  }
  return [x, y];
}

export class ModalManager {
  private readonly backdrop: HTMLDivElement;
  private readonly card: HTMLDivElement;
  private readonly cb: ModalCallbacks;

  activeModal: ModalKind = 'none';
  private guideTab: 'gameplay' | 'mechanics' = 'gameplay';
  private selectedHex = '';

  constructor(parent: HTMLElement, cb: ModalCallbacks) {
    this.cb = cb;
    this.backdrop = document.createElement('div');
    this.backdrop.className = 'modal-backdrop interactive';
    this.backdrop.hidden = true;
    this.backdrop.addEventListener('click', (e) => {
      if (e.target === this.backdrop) {
        this.close();
      }
    });

    this.card = document.createElement('div');
    this.card.className = 'modal-card hud-panel';
    this.card.addEventListener('click', (e) => e.stopPropagation());
    this.backdrop.appendChild(this.card);
    parent.appendChild(this.backdrop);
  }

  get isOpen(): boolean {
    return this.activeModal !== 'none';
  }

  open(kind: ModalKind, sim: Simulation): void {
    this.activeModal = kind;
    this.backdrop.hidden = kind === 'none';
    if (kind !== 'none') {
      this.render(sim);
    }
  }

  close(): void {
    const wasSettings = this.activeModal === 'settings';
    this.activeModal = 'none';
    this.backdrop.hidden = true;
    if (wasSettings) this.cb.onResumeRequest();
  }

  private headerRow(title: string): HTMLDivElement {
    const h = document.createElement('div');
    h.className = 'modal-header';
    const h2 = document.createElement('h2');
    h2.textContent = title;
    const closeBtn = document.createElement('button');
    closeBtn.type = 'button';
    closeBtn.className = 'hud-btn';
    closeBtn.textContent = 'Close';
    closeBtn.addEventListener('click', () => this.close());
    h.append(h2, closeBtn);
    return h;
  }

  render(sim: Simulation): void {
    switch (this.activeModal) {
      case 'settings':
        this.renderSettings(sim);
        break;
      case 'family':
        this.renderFamily(sim);
        break;
      case 'palette':
        this.renderPalette(sim);
        break;
      case 'investment':
        this.renderInvestment(sim);
        break;
      case 'guide':
        this.renderGuide();
        break;
      case 'vacuoles':
        this.renderVacuoles(sim);
        break;
      case 'mutation_offer':
        this.renderMutationOffer(sim);
        break;
      default:
        break;
    }
  }

  private renderSettings(sim: Simulation): void {
    const prefs = this.cb.getVisualPrefs();
    const nodes: HTMLElement[] = [this.headerRow('Pond Menu & Settings')];

    const resumeBtn = document.createElement('button');
    resumeBtn.type = 'button';
    resumeBtn.className = 'hud-btn is-active';
    resumeBtn.textContent = 'Resume Pond';
    resumeBtn.addEventListener('click', () => this.close());
    nodes.push(resumeBtn);

    const mkToggle = (label: string, val: boolean, onChange: (v: boolean) => void) => {
      const row = document.createElement('label');
      row.className = 'setting-row';
      const span = document.createElement('span');
      span.textContent = label;
      const chk = document.createElement('input');
      chk.type = 'checkbox';
      chk.checked = val;
      chk.addEventListener('change', () => onChange(chk.checked));
      row.append(span, chk);
      return row;
    };

    nodes.push(
      mkToggle('Sunlit Bloom', prefs.bloomEnabled, (v) => this.cb.setVisualPrefs({ bloomEnabled: v })),
      mkToggle('Water Caustics', prefs.ripplesEnabled, (v) => this.cb.setVisualPrefs({ ripplesEnabled: v })),
      mkToggle('Peripheral Microscope Blur', prefs.blurEnabled, (v) => this.cb.setVisualPrefs({ blurEnabled: v })),
      mkToggle('Simplified Molecule Shapes', prefs.simpleParticles, (v) =>
        this.cb.setVisualPrefs({ simpleParticles: v }),
      ),
    );

    // New Expedition section
    const expBox = document.createElement('div');
    expBox.style.padding = '12px';
    expBox.style.borderRadius = '12px';
    expBox.style.border = '1px solid rgba(102,165,204,0.3)';
    expBox.style.display = 'flex';
    expBox.style.flexDirection = 'column';
    expBox.style.gap = '8px';

    const expTitle = document.createElement('strong');
    expTitle.textContent = 'New Pond Expedition';
    const seedRow = document.createElement('div');
    seedRow.style.display = 'flex';
    seedRow.style.gap = '8px';
    seedRow.style.flexWrap = 'wrap';

    const seedInput = document.createElement('input');
    seedInput.type = 'number';
    seedInput.value = String(sim.seedValue);
    seedInput.className = 'hud-btn';
    seedInput.style.width = '140px';

    const habSelect = document.createElement('select');
    habSelect.className = 'hud-btn';
    for (const [val, text] of [
      ['0', 'Balanced Tide'],
      ['1', 'Lean Hunting Grounds'],
      ['2', 'Rich / Armored Hunters'],
    ]) {
      const opt = document.createElement('option');
      opt.value = val;
      opt.textContent = text;
      if (Number(val) === sim.habitat) opt.selected = true;
      habSelect.appendChild(opt);
    }

    const randBtn = document.createElement('button');
    randBtn.type = 'button';
    randBtn.className = 'hud-btn';
    randBtn.textContent = 'Random Seed';
    randBtn.addEventListener('click', () => {
      seedInput.value = String(Math.floor(Math.random() * 9000000) + 100000);
    });

    const launchBtn = document.createElement('button');
    launchBtn.type = 'button';
    launchBtn.className = 'hud-btn is-active';
    launchBtn.textContent = 'Start New Pond';
    launchBtn.addEventListener('click', () => {
      const s = Number(seedInput.value) || 20261004;
      const h = Number(habSelect.value) || 0;
      this.close();
      this.cb.onNewExpedition(s, h);
    });

    seedRow.append(seedInput, habSelect, randBtn, launchBtn);
    expBox.append(expTitle, seedRow);
    nodes.push(expBox);

    const footer = document.createElement('div');
    footer.style.display = 'flex';
    footer.style.gap = '8px';
    footer.style.justifyContent = 'space-between';
    const guideBtn = document.createElement('button');
    guideBtn.type = 'button';
    guideBtn.className = 'hud-btn';
    guideBtn.textContent = 'Gameplay & Science Guide';
    guideBtn.addEventListener('click', () => this.open('guide', sim));

    const resetBtn = document.createElement('button');
    resetBtn.type = 'button';
    resetBtn.className = 'hud-btn is-danger';
    resetBtn.textContent = 'Reset UI Preferences';
    resetBtn.addEventListener('click', () => {
      this.cb.onResetPrefs();
      this.render(sim);
    });
    footer.append(guideBtn, resetBtn);
    nodes.push(footer);

    this.card.replaceChildren(...nodes);
  }

  private renderInvestment(sim: Simulation): void {
    const focus = sim.player;
    const cur = rawStrategyForCell(sim.investment, focus);
    const nodes: HTMLElement[] = [this.headerRow('Lineage Daughter Strategy')];

    const sub = document.createElement('p');
    sub.style.margin = '0';
    sub.style.fontSize = '13px';
    sub.style.color = '#a9c7d0';
    sub.textContent =
      'Choose how autonomous offspring of your lineage prioritize biomass builds and organelle adaptations.';
    nodes.push(sub);

    const grid = document.createElement('div');
    grid.className = 'modal-grid';
    const items: Array<{ id: InvestmentStrategy; title: string; role: RoleName | 'balanced'; desc: string }> = [
      { id: 'balanced', title: 'Balanced Ecosystem', role: 'balanced', desc: 'Mixes 2 Hunter : 4 Parasite : 10 Grazer : 20 Producer' },
      { id: 'grazer', title: 'Motile Grazer', role: 'grazer', desc: 'Oral grooves, cilia & fast digestive enzymes' },
      { id: 'producer', title: 'Solar Producer', role: 'producer', desc: 'Thylakoid light absorption & thick protection' },
      { id: 'hunter', title: 'Armored Hunter', role: 'hunter', desc: 'Pore-forming bursts, toxin lances & hunting receptors' },
      { id: 'parasite', title: 'Siphon Parasite', role: 'parasite', desc: 'Long proboscis extraction & stealth mobility' },
    ];

    for (const item of items) {
      const card = document.createElement('button');
      card.type = 'button';
      card.className = `choice-card ${cur === item.id ? 'is-active' : ''}`;
      card.appendChild(makeRolePortrait(item.role, 80));
      const t = document.createElement('strong');
      t.textContent = item.title;
      const d = document.createElement('span');
      d.style.fontSize = '12px';
      d.style.color = '#b2cdd4';
      d.textContent = item.desc;
      card.append(t, d);
      card.addEventListener('click', () => {
        sim.investment.lineages.set(focus.lineageId(), item.id);
        sim.investment.cells.set(focus.id, item.id);
        this.cb.onNotice(`Lineage role set to ${item.title}`);
        this.close();
      });
      grid.appendChild(card);
    }

    nodes.push(grid);
    this.card.replaceChildren(...nodes);
  }

  private renderFamily(sim: Simulation): void {
    const family = sim.lineage.activeFamily(sim.cells);
    const mergeCands = sim.mergeCandidatesForPlayer();
    const nodes: HTMLElement[] = [this.headerRow(`Lineage Family (${family.length} living)`)];

    const topActions = document.createElement('div');
    topActions.style.display = 'flex';
    topActions.style.gap = '8px';
    topActions.style.flexWrap = 'wrap';

    const mergeBtn = document.createElement('button');
    mergeBtn.type = 'button';
    mergeBtn.className = 'hud-btn is-active';
    mergeBtn.textContent =
      mergeCands.size > 0
        ? `Merge a relative into this cell (${mergeCands.size} eligible)`
        : 'Merge a relative into this cell (none eligible yet)';
    mergeBtn.disabled = mergeCands.size === 0;
    mergeBtn.addEventListener('click', () => {
      this.close();
      this.cb.onEnterMergeMode();
    });

    const colorBtn = document.createElement('button');
    colorBtn.type = 'button';
    colorBtn.className = 'hud-btn';
    colorBtn.textContent = 'Lineage Colors & Name';
    colorBtn.addEventListener('click', () => this.open('palette', sim));
    topActions.append(mergeBtn, colorBtn);
    nodes.push(topActions);

    const grid = document.createElement('div');
    grid.className = 'modal-grid';
    for (const c of family) {
      const card = document.createElement('button');
      card.type = 'button';
      card.className = `choice-card ${c === sim.player ? 'is-active' : ''}`;
      card.appendChild(makeCellPortrait(sim.seedValue, c, sim.lineageColors.get(c.lineageId()), 78));
      const t = document.createElement('strong');
      t.textContent = `${c === sim.player ? '★ Current · ' : ''}Gen ${c.generation}`;
      const info = document.createElement('span');
      info.style.fontSize = '12px';
      info.style.color = '#b7d4dc';
      info.textContent = `Biomass ${c.biomass.toFixed(0)} · ATP ${c.energy.toFixed(0)} · HP ${c.health.toFixed(0)}%`;
      card.append(t, info);
      card.addEventListener('click', () => {
        if (c !== sim.player) {
          sim.followFamily(c.id);
        }
        this.close();
        this.cb.onFollowCell(c);
      });
      grid.appendChild(card);
    }

    nodes.push(grid);
    this.card.replaceChildren(...nodes);
  }

  private renderPalette(sim: Simulation): void {
    const lin = sim.player.lineageId();
    const curHex = sim.lineageColors.get(lin) ?? lineagePalette(sim.seedValue, lin).body;
    if (!this.selectedHex) this.selectedHex = curHex;
    const rgb = parseHex(this.selectedHex);
    const [initH, initS, initV] = rgbToHsv(rgb.r, rgb.g, rgb.b);
    let hue = initH;
    let sat = initS;
    let val = Math.max(0.25, initV);

    const nodes: HTMLElement[] = [this.headerRow('Lineage Color & Name')];

    const nameRow = document.createElement('div');
    nameRow.style.display = 'flex';
    nameRow.style.gap = '8px';
    nameRow.style.alignItems = 'center';
    const nameLbl = document.createElement('span');
    nameLbl.textContent = 'Lineage Name:';
    const nameInput = document.createElement('input');
    nameInput.type = 'text';
    nameInput.maxLength = 28;
    nameInput.className = 'hud-btn';
    nameInput.style.flex = '1';
    nameInput.value = sim.lineageNames.get(lin) ?? `Lineage ${lin}`;
    nameRow.append(nameLbl, nameInput);
    nodes.push(nameRow);

    // HSV Hue Ring + Shirley-Chiu Disc SV Canvas
    const wheelSize = 220;
    const wheelCanvas = document.createElement('canvas');
    wheelCanvas.width = wheelSize;
    wheelCanvas.height = wheelSize;
    wheelCanvas.style.alignSelf = 'center';
    wheelCanvas.style.cursor = 'crosshair';
    const ctx = wheelCanvas.getContext('2d')!;
    const cx = wheelSize * 0.5;
    const outerR = wheelSize * 0.47;
    const innerR = wheelSize * 0.34;

    const previewChip = document.createElement('div');
    previewChip.style.height = '28px';
    previewChip.style.borderRadius = '8px';
    previewChip.style.border = '1px solid rgba(255,255,255,0.28)';

    const redrawWheel = () => {
      const img = ctx.createImageData(wheelSize, wheelSize);
      for (let py = 0; py < wheelSize; py++) {
        for (let px = 0; px < wheelSize; px++) {
          const dx = px - cx;
          const dy = py - cx;
          const d = Math.hypot(dx, dy);
          const off = (py * wheelSize + px) * 4;
          if (d >= innerR + 3 && d <= outerR) {
            const h = ((Math.atan2(dy, dx) / TAU) + 1) % 1;
            const c = hsvToRgb(h, 0.9, 0.95);
            img.data[off + 0] = Math.round(c.r * 255);
            img.data[off + 1] = Math.round(c.g * 255);
            img.data[off + 2] = Math.round(c.b * 255);
            img.data[off + 3] = 255;
          } else if (d < innerR - 2) {
            const u = dx / (innerR - 2);
            const v = dy / (innerR - 2);
            const [sx, sy] = discToSquare(u, v);
            const c = hsvToRgb(hue, (sx + 1) * 0.5, (1 - sy) * 0.5);
            img.data[off + 0] = Math.round(c.r * 255);
            img.data[off + 1] = Math.round(c.g * 255);
            img.data[off + 2] = Math.round(c.b * 255);
            img.data[off + 3] = 255;
          }
        }
      }
      ctx.putImageData(img, 0, 0);

      // Hue indicator
      const hx = cx + Math.cos(hue * TAU) * ((innerR + outerR) * 0.5);
      const hy = cx + Math.sin(hue * TAU) * ((innerR + outerR) * 0.5);
      ctx.strokeStyle = '#ffffff';
      ctx.lineWidth = 2.5;
      ctx.beginPath();
      ctx.arc(hx, hy, 7, 0, TAU);
      ctx.stroke();

      const c = hsvToRgb(hue, sat, val);
      this.selectedHex = rgbToHex(c.r, c.g, c.b);
      previewChip.style.background = this.selectedHex;
    };
    redrawWheel();

    let dragMode: 'none' | 'hue' | 'sv' = 'none';
    const pickAt = (ev: PointerEvent, start = false) => {
      const rect = wheelCanvas.getBoundingClientRect();
      const dx = ((ev.clientX - rect.left) / rect.width) * wheelSize - cx;
      const dy = ((ev.clientY - rect.top) / rect.height) * wheelSize - cx;
      const d = Math.hypot(dx, dy);
      if (start) {
        dragMode = d >= innerR ? 'hue' : 'sv';
      }
      if (dragMode === 'hue') {
        hue = ((Math.atan2(dy, dx) / TAU) + 1) % 1;
      } else if (dragMode === 'sv') {
        const len = Math.max(1e-5, d);
        const cap = Math.min(len, innerR - 3) / len;
        const u = (dx * cap) / (innerR - 2);
        const v = (dy * cap) / (innerR - 2);
        const [sx, sy] = discToSquare(u, v);
        sat = Math.max(0.05, Math.min(1, (sx + 1) * 0.5));
        val = Math.max(0.2, Math.min(1, (1 - sy) * 0.5));
      }
      redrawWheel();
    };
    wheelCanvas.addEventListener('pointerdown', (e) => {
      try { wheelCanvas.setPointerCapture(e.pointerId); } catch { /* synthetic event */ }
      pickAt(e, true);
    });
    wheelCanvas.addEventListener('pointermove', (e) => {
      if (dragMode !== 'none') pickAt(e, false);
    });
    wheelCanvas.addEventListener('pointerup', () => {
      dragMode = 'none';
    });

    nodes.push(wheelCanvas, previewChip);

    // Preset swatches
    const swatches = document.createElement('div');
    swatches.style.display = 'flex';
    swatches.style.gap = '10px';
    swatches.style.justifyContent = 'center';
    for (const p of LINEAGE_PALETTE_PRESETS) {
      const sBtn = document.createElement('button');
      sBtn.type = 'button';
      sBtn.style.width = '34px';
      sBtn.style.height = '34px';
      sBtn.style.borderRadius = '50%';
      sBtn.style.border = '2px solid #fff';
      sBtn.style.background = p.body;
      sBtn.style.cursor = 'pointer';
      sBtn.addEventListener('click', () => {
        const pr = parseHex(p.body);
        const [nh, ns, nv] = rgbToHsv(pr.r, pr.g, pr.b);
        hue = nh;
        sat = ns;
        val = nv;
        redrawWheel();
      });
      swatches.appendChild(sBtn);
    }
    nodes.push(swatches);

    const actions = document.createElement('div');
    actions.style.display = 'flex';
    actions.style.gap = '8px';
    actions.style.justifyContent = 'flex-end';

    const resetBtn = document.createElement('button');
    resetBtn.type = 'button';
    resetBtn.className = 'hud-btn';
    resetBtn.textContent = 'Default Seed Color';
    resetBtn.addEventListener('click', () => {
      sim.lineageColors.delete(lin);
      const cleanName = nameInput.value.trim() || `Lineage ${lin}`;
      sim.lineageNames.set(lin, cleanName);
      this.cb.onLineageStyleChanged(lin, undefined, cleanName);
      this.selectedHex = '';
      this.close();
    });

    const applyBtn = document.createElement('button');
    applyBtn.type = 'button';
    applyBtn.className = 'hud-btn is-active';
    applyBtn.textContent = 'Save Style';
    applyBtn.addEventListener('click', () => {
      const cleanName = nameInput.value.trim() || `Lineage ${lin}`;
      sim.lineageColors.set(lin, this.selectedHex);
      sim.lineageNames.set(lin, cleanName);
      this.cb.onLineageStyleChanged(lin, this.selectedHex, cleanName);
      this.selectedHex = '';
      this.close();
    });

    actions.append(resetBtn, applyBtn);
    nodes.push(actions);
    this.card.replaceChildren(...nodes);
  }

  private renderGuide(): void {
    const nodes: HTMLElement[] = [this.headerRow('Primordia Guide')];

    const tabs = document.createElement('div');
    tabs.style.display = 'flex';
    tabs.style.gap = '8px';
    const mkTab = (id: 'gameplay' | 'mechanics', label: string) => {
      const b = document.createElement('button');
      b.type = 'button';
      b.className = `hud-btn ${this.guideTab === id ? 'is-active' : ''}`;
      b.textContent = label;
      b.addEventListener('click', () => {
        this.guideTab = id;
        this.renderGuide();
      });
      return b;
    };
    tabs.append(mkTab('gameplay', 'Controls & Gameplay'), mkTab('mechanics', 'Biology & Chemistry'));
    nodes.push(tabs);

    const body = document.createElement('div');
    body.style.display = 'flex';
    body.style.flexDirection = 'column';
    body.style.gap = '12px';

    const appendEntries = (heading: string, entries: GuideEntry[]) => {
      const h3 = document.createElement('h3');
      h3.style.margin = '6px 0 2px';
      h3.style.color = '#ffd466';
      h3.textContent = heading;
      body.appendChild(h3);
      for (const item of entries) {
        const box = document.createElement('div');
        box.style.padding = '10px 12px';
        box.style.borderRadius = '10px';
        box.style.background = 'rgba(18, 37, 66, 0.72)';
        box.style.border = '1px solid rgba(98, 155, 195, 0.25)';
        const t = document.createElement('strong');
        t.textContent = item.title;
        const p = document.createElement('p');
        p.style.margin = '4px 0 0';
        p.style.fontSize = '13px';
        p.style.color = '#c7e3ec';
        p.textContent = item.text;
        box.append(t, p);
        if (item.sources && item.sources.length > 0) {
          const refs = document.createElement('div');
          refs.style.marginTop = '6px';
          refs.style.display = 'flex';
          refs.style.flexWrap = 'wrap';
          refs.style.gap = '10px';
          for (const s of item.sources) {
            const a = document.createElement('a');
            a.className = 'guide-link';
            a.href = s.url;
            a.target = '_blank';
            a.rel = 'noopener noreferrer';
            a.textContent = s.title;
            refs.appendChild(a);
          }
          box.appendChild(refs);
        }
        body.appendChild(box);
      }
    };

    if (this.guideTab === 'gameplay') {
      appendEntries('Shared Controls', GUIDE_DATA.gameplay.common);
      appendEntries('Desktop Keyboard & Mouse', GUIDE_DATA.gameplay.desktop);
      appendEntries('Touch Screen Gestures', GUIDE_DATA.gameplay.touch);
    } else {
      for (const sec of GUIDE_DATA.mechanics) {
        appendEntries(sec.title, sec.items);
      }
    }

    nodes.push(body);
    this.card.replaceChildren(...nodes);
  }

  private renderVacuoles(sim: Simulation): void {
    const c = sim.player;
    const nodes: HTMLElement[] = [this.headerRow('Cytoplasm & Vacuole Summary')];

    const summary = document.createElement('div');
    summary.style.fontSize = '13px';
    summary.style.color = '#c7e3ec';
    summary.textContent = `Food vacuoles: ${c.substrate.toFixed(1)} / ${c.gutCapacity().toFixed(1)} · Waste: ${c.waste.toFixed(1)} · O₂: ${c.oxygen.toFixed(1)} · CO₂: ${c.carbon.toFixed(1)} · Surface Complexes: ${c.surfaceComplexes.length}`;
    nodes.push(summary);

    const list = document.createElement('div');
    list.style.display = 'flex';
    list.style.flexDirection = 'column';
    list.style.gap = '6px';
    for (const p of c.chemistry.particles) {
      if (!p.alive) continue;
      const row = document.createElement('div');
      row.style.padding = '7px 10px';
      row.style.borderRadius = '8px';
      row.style.background = 'rgba(20, 42, 74, 0.72)';
      row.style.fontSize = '12px';
      row.textContent = `${p.species.toUpperCase()} · ${p.amount.toFixed(2)} units · Age ${p.age.toFixed(1)}s${p.species === 'food' ? ` · Reserve ${p.fuel.toFixed(1)} ATP` : ''}`;
      list.appendChild(row);
    }
    if (list.childElementCount === 0) {
      const empty = document.createElement('div');
      empty.style.color = '#9ec0c9';
      empty.textContent = 'No active cytoplasmic droplets right now — swim near nutrients or oxygen to feed.';
      list.appendChild(empty);
    }
    nodes.push(list);
    this.card.replaceChildren(...nodes);
  }

  private renderMutationOffer(sim: Simulation): void {
    const offers = sim.evolution.divisionOffers;
    const nodes: HTMLElement[] = [this.headerRow('Genetic Trait Offered!')];
    if (offers.length === 0) {
      this.close();
      return;
    }
    const sub = document.createElement('p');
    sub.style.margin = '0';
    sub.style.fontSize = '13px';
    sub.style.color = '#c7e3ec';
    sub.textContent = 'Cell division uncovered a beneficial heritable adaptation you can unlock for this lineage:';
    nodes.push(sub);

    const grid = document.createElement('div');
    grid.className = 'modal-grid';
    for (const gene of offers) {
      const def = MUTATION_DATA[gene];
      const card = document.createElement('button');
      card.type = 'button';
      card.className = 'choice-card';
      const t = document.createElement('strong');
      t.textContent = def?.title ?? gene;
      const s = document.createElement('span');
      s.style.fontSize = '12px';
      s.style.color = '#b2cdd4';
      s.textContent = def?.summary ?? '';
      card.append(t, s);
      card.addEventListener('click', () => {
        sim.acceptDivisionMutation(gene);
        this.cb.onNotice(`Unlocked ${def?.title ?? gene} adaptation!`);
        this.close();
      });
      grid.appendChild(card);
    }
    nodes.push(grid);
    this.card.replaceChildren(...nodes);
  }
}
