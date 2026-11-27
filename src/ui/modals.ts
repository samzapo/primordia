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
import { rolePreviewGeometry, type RolePreviewGeometry } from '../sim/membrane.ts';
import { MUTATION_DATA } from '../sim/mutations.ts';
import type { Simulation } from '../sim/simulation.ts';
import { bindHoldTooltip, hideHoldTooltip } from './tooltip.ts';

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

const ROLE_PREVIEW_CACHE = new Map<RoleName, RolePreviewGeometry>();

function getRoleGeometry(role: RoleName): RolePreviewGeometry {
  let cached = ROLE_PREVIEW_CACHE.get(role);
  if (!cached) {
    cached = rolePreviewGeometry(role, 47);
    ROLE_PREVIEW_CACHE.set(role, cached);
  }
  return cached;
}

function drawRoleSketch(ctx: CanvasRenderingContext2D, role: RoleName, cx: number, cy: number, r: number): void {
  const palette: Record<
    RoleName,
    {
      body: string;
      rim: string;
      nucleus: string;
      organs: Array<{ kind: OrganKind; angle: number }>;
    }
  > = {
    grazer: {
      body: '#24829c',
      rim: '#6ae8cf',
      nucleus: '#144d63',
      organs: [
        { kind: 'feeding', angle: 0 },
        { kind: 'cilia', angle: Math.PI * 0.55 },
        { kind: 'regenerative', angle: Math.PI * 1.05 },
        { kind: 'sensing', angle: -Math.PI * 0.5 },
      ],
    },
    producer: {
      body: '#1f8a5b',
      rim: '#8af59b',
      nucleus: '#0e4c36',
      organs: [
        { kind: 'photosynthesis', angle: -Math.PI * 0.25 },
        { kind: 'photosynthesis', angle: Math.PI * 0.75 },
        { kind: 'protection', angle: Math.PI * 0.25 },
        { kind: 'mitochondrion', angle: -Math.PI * 0.75 },
      ],
    },
    hunter: {
      body: '#c94148',
      rim: '#ffa452',
      nucleus: '#5e1424',
      organs: [
        { kind: 'feeding', angle: -Math.PI * 0.5 },
        { kind: 'poreforming', angle: 0 },
        { kind: 'toxin', angle: Math.PI / 3 },
        { kind: 'propulsion', angle: Math.PI },
        { kind: 'hunting', angle: -Math.PI / 3 },
      ],
    },
    parasite: {
      body: '#8938b5',
      rim: '#f078e2',
      nucleus: '#3c1361',
      organs: [
        { kind: 'proboscis', angle: 0 },
        { kind: 'hunting', angle: Math.PI * 0.45 },
        { kind: 'propulsion', angle: Math.PI },
        { kind: 'sensing', angle: -Math.PI * 0.45 },
      ],
    },
  };
  const spec = palette[role];
  const geom = getRoleGeometry(role);
  const pts = geom.outline;
  let maxR = 1;
  for (const p of pts) maxR = Math.max(maxR, Math.hypot(p.x, p.y));
  const sc = (r * 1.08) / maxR;

  ctx.save();
  ctx.translate(cx, cy);
  if (role === 'grazer' && pts.length >= 12) {
    const hairLen = Math.max(3.5, r * 0.24);
    ctx.save();
    ctx.strokeStyle = spec.rim;
    ctx.globalAlpha = 0.85;
    ctx.lineWidth = Math.max(1.0, r * 0.06);
    ctx.lineCap = 'round';
    ctx.beginPath();
    const nOut = pts.length;
    for (let i = 0; i < nOut; i += 4) {
      const pPrev = pts[(i - 1 + nOut) % nOut];
      const pCur = pts[i];
      const pNext = pts[(i + 1) % nOut];
      const tx = pNext.x - pPrev.x;
      const ty = pNext.y - pPrev.y;
      const tLen = Math.hypot(tx, ty) || 1;
      let nx = ty / tLen;
      let ny = -tx / tLen;
      if (pCur.x * nx + pCur.y * ny < 0) {
        nx = -nx;
        ny = -ny;
      }
      const x0 = pCur.x * sc;
      const y0 = pCur.y * sc;
      ctx.moveTo(x0, y0);
      ctx.lineTo(x0 + nx * hairLen, y0 + ny * hairLen);
    }
    ctx.stroke();
    ctx.restore();
  }
  const g = ctx.createRadialGradient(-r * 0.22, -r * 0.22, r * 0.08, 0, 0, r * 1.08);
  g.addColorStop(0, spec.rim);
  g.addColorStop(0.62, spec.body);
  g.addColorStop(1, '#10203a');
  ctx.fillStyle = g;
  ctx.beginPath();
  for (let i = 0; i < pts.length; i++) {
    const x = pts[i].x * sc;
    const y = pts[i].y * sc;
    if (i === 0) ctx.moveTo(x, y);
    else ctx.lineTo(x, y);
  }
  ctx.closePath();
  ctx.fill();
  ctx.lineWidth = role === 'producer' ? Math.max(2.2, r * 0.14) : 2;
  ctx.strokeStyle = spec.rim;
  ctx.stroke();

  // Inner nucleus silhouette matching cell portraits
  ctx.fillStyle = spec.nucleus;
  ctx.beginPath();
  ctx.arc(0, 0, Math.max(2.5, r * 0.24), 0, TAU);
  ctx.fill();

  const iconSize = Math.max(12, Math.round(r * 0.54));
  const tmp = document.createElement('canvas');
  tmp.width = iconSize;
  tmp.height = iconSize;
  const tctx = tmp.getContext('2d')!;
  for (const entry of spec.organs) {
    const anchor = geom.pointAt(entry.angle);
    tctx.clearRect(0, 0, iconSize, iconSize);
    drawOrganIcon2D(tctx, entry.kind, iconSize);
    ctx.drawImage(tmp, anchor.x * sc - iconSize * 0.5, anchor.y * sc - iconSize * 0.5);
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
    hideHoldTooltip();
    this.activeModal = kind;
    this.backdrop.hidden = kind === 'none';
    if (kind !== 'none') {
      this.render(sim);
    }
  }

  close(): void {
    hideHoldTooltip();
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
    bindHoldTooltip(closeBtn, () => ({
      title: 'Close',
      body: 'Close this dialog and return to the pond.',
    }));
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
    bindHoldTooltip(resumeBtn, () => ({
      title: 'Resume Pond',
      body: 'Close settings and resume the live simulation.',
    }));
    resumeBtn.addEventListener('click', () => this.close());
    nodes.push(resumeBtn);

    const mkToggle = (label: string, tipBody: string, val: boolean, onChange: (v: boolean) => void) => {
      const row = document.createElement('label');
      row.className = 'setting-row';
      bindHoldTooltip(row, () => ({ title: label, body: tipBody }));
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
      mkToggle(
        'Sunlit Bloom',
        'Enable soft sunlight optical glow over sunlit particles and membranes.',
        prefs.bloomEnabled,
        (v) => this.cb.setVisualPrefs({ bloomEnabled: v }),
      ),
      mkToggle(
        'Water Caustics',
        'Show animated sunlit Voronoi ripple caustics on the pond surface.',
        prefs.ripplesEnabled,
        (v) => this.cb.setVisualPrefs({ ripplesEnabled: v }),
      ),
      mkToggle(
        'Peripheral Microscope Blur',
        'Apply subtle depth-of-field blur around the outer perimeter of the lens view.',
        prefs.blurEnabled,
        (v) => this.cb.setVisualPrefs({ blurEnabled: v }),
      ),
      mkToggle(
        'Simplified Molecule Shapes',
        'Render smaller, crisp simplified chemical markers across the pond.',
        prefs.simpleParticles,
        (v) => this.cb.setVisualPrefs({ simpleParticles: v }),
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
    bindHoldTooltip(randBtn, () => ({
      title: 'Random Seed',
      body: 'Generate a new random pond seed number for habitat plants, currents, and initial ecology.',
    }));
    randBtn.addEventListener('click', () => {
      seedInput.value = String(Math.floor(Math.random() * 9000000) + 100000);
    });

    const launchBtn = document.createElement('button');
    launchBtn.type = 'button';
    launchBtn.className = 'hud-btn is-active';
    launchBtn.textContent = 'Start New Pond';
    bindHoldTooltip(launchBtn, () => ({
      title: 'Start New Pond',
      body: 'Reset the current pond and generate a fresh ecosystem with the selected seed and habitat profile.',
    }));
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
    bindHoldTooltip(guideBtn, () => ({
      title: 'Gameplay & Science Guide',
      body: 'Open controls help and scientific documentation of cellular metabolism and ecology.',
    }));
    guideBtn.addEventListener('click', () => this.open('guide', sim));

    const resetBtn = document.createElement('button');
    resetBtn.type = 'button';
    resetBtn.className = 'hud-btn is-danger';
    resetBtn.textContent = 'Reset UI Preferences';
    bindHoldTooltip(resetBtn, () => ({
      title: 'Reset UI Preferences',
      body: 'Restore default visual, audio, and local UI preferences.',
    }));
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
      bindHoldTooltip(card, () => ({ title: item.title, subtitle: 'Lineage Strategy', body: item.desc }));
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
    bindHoldTooltip(mergeBtn, () => ({
      title: 'Merge Relative',
      body: 'Absorb a consenting nearby cell of your lineage into the active cell to pool organs and mass.',
    }));
    mergeBtn.addEventListener('click', () => {
      this.close();
      this.cb.onEnterMergeMode();
    });

    const colorBtn = document.createElement('button');
    colorBtn.type = 'button';
    colorBtn.className = 'hud-btn';
    colorBtn.textContent = 'Lineage Colors & Name';
    bindHoldTooltip(colorBtn, () => ({
      title: 'Lineage Colors & Name',
      body: 'Open the hue ring and name editor for this lineage.',
    }));
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
      bindHoldTooltip(card, () => ({
        title: `Generation ${c.generation} Cell`,
        subtitle: c === sim.player ? 'Currently Focused' : `${c.organs.length} organs`,
        body: 'Tap to focus and take control of this living member of your lineage.',
      }));
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
      bindHoldTooltip(sBtn, () => ({
        title: 'Preset Swatch',
        body: `Select palette ${p.body} on the color wheel.`,
      }));
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
    bindHoldTooltip(resetBtn, () => ({
      title: 'Default Seed Color',
      body: 'Reset the lineage palette back to its seeded pond colors.',
    }));
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
    bindHoldTooltip(applyBtn, () => ({
      title: 'Save Style',
      body: 'Save your chosen membrane color and lineage name for this session and future ponds.',
    }));
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
      bindHoldTooltip(b, () => ({
        title: label,
        body: id === 'gameplay' ? 'View desktop, keyboard, and touch controls.' : 'View cellular biology, metabolism, and chemistry details.',
      }));
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
      bindHoldTooltip(card, () => ({
        title: def?.title ?? gene,
        subtitle: 'Heritable Lineage Adaptation',
        body: def?.summary ?? 'Unlock this trait for future organelles of this type.',
      }));
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
