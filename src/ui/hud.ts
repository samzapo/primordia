import type { AudioEngine } from '../audio/engine.ts';
import { phFromAcid } from '../sim/acidity.ts';
import type { Cell } from '../sim/cell.ts';
import { MICROMETERS_PER_UNIT } from '../sim/constants.ts';
import type { Simulation } from '../sim/simulation.ts';
import type { PondCamera } from './camera.ts';
import { StatusFeed } from './statusFeed.ts';
import { bindHoldTooltip } from './tooltip.ts';

export interface HudCallbacks {
  onTogglePause(): void;
  onZoomStep(factor: number): void;
  onToggleFollow(): void;
  onToggleIntero(): void;
  onOpenFamily(): void;
  onOpenPalette(): void;
  onOpenGuide(): void;
  onOpenSettings(): void;
  onOpenVacuoles(): void;
  onToggleMute(): void;
  onVolumeChange(v: number): void;
}

const NICE_MICROMETERS = [0.2, 0.5, 1, 2, 5, 10, 20, 50, 100, 200] as const;

export class Hud {
  readonly statusFeed: StatusFeed;

  private readonly rightRail: HTMLDivElement;
  private readonly pauseBtn: HTMLButtonElement;
  private readonly zoomOutBtn: HTMLButtonElement;
  private readonly zoomInBtn: HTMLButtonElement;
  private readonly followBtn: HTMLButtonElement;
  private readonly viewBtn: HTMLButtonElement;
  private readonly familyBtn: HTMLButtonElement;
  private readonly colorBtn: HTMLButtonElement;
  private readonly guideBtn: HTMLButtonElement;
  private readonly settingsBtn: HTMLButtonElement;
  private readonly muteBtn: HTMLButtonElement;
  private readonly volSlider: HTMLInputElement;
  private readonly stateBadge: HTMLDivElement;

  private readonly bottomLeft: HTMLDivElement;
  private readonly resourcesCard: HTMLDivElement;
  private readonly summaryRow: HTMLDivElement;
  private readonly detailsGrid: HTMLDivElement;
  private resourcesExpanded = false;

  private readonly scaleLine: HTMLDivElement;
  private readonly scaleLabel: HTMLSpanElement;
  readonly telemetryEl: HTMLDivElement;
  telemetryVisible = false;

  constructor(parent: HTMLElement, cb: HudCallbacks, audio: AudioEngine) {
    // Right rail
    this.rightRail = document.createElement('div');
    this.rightRail.className = 'hud-right-rail';

    const mkBtn = (
      label: string,
      title: string,
      tipBody: string,
      onClick: () => void,
    ): HTMLButtonElement => {
      const b = document.createElement('button');
      b.type = 'button';
      b.className = 'hud-btn interactive';
      b.textContent = label;
      b.setAttribute('aria-label', title);
      bindHoldTooltip(b, () => ({ title: b.textContent || title, body: tipBody }));
      b.addEventListener('click', (e) => {
        e.stopPropagation();
        onClick();
      });
      return b;
    };

    const row1 = document.createElement('div');
    row1.className = 'rail-row';
    this.pauseBtn = mkBtn(
      'Pause',
      'Pause or resume (P)',
      'Pause or resume the biological simulation. Camera inspection and cell editing stay active while paused.',
      cb.onTogglePause,
    );
    this.settingsBtn = mkBtn(
      'Menu',
      'Pond menu & settings (Esc)',
      'Open settings to toggle visual effects, view controls, or start a new seeded pond expedition.',
      cb.onOpenSettings,
    );
    row1.append(this.pauseBtn, this.settingsBtn);

    const row2 = document.createElement('div');
    row2.className = 'rail-row';
    this.zoomOutBtn = mkBtn('−', 'Zoom out (-)', 'Zoom out up to the full pond view just short of wraparound (keyboard: -).', () =>
      cb.onZoomStep(1 / 1.25),
    );
    this.zoomInBtn = mkBtn('+', 'Zoom in (+)', 'Zoom closer to inspect membranes, organs, and chemical molecules (keyboard: +).', () =>
      cb.onZoomStep(1.25),
    );
    this.followBtn = mkBtn(
      'Follow',
      'Follow focused cell (F)',
      'Switch between following your focused cell and moving the camera freely across the pond (keyboard: F).',
      cb.onToggleFollow,
    );
    row2.append(this.zoomOutBtn, this.zoomInBtn, this.followBtn);

    const row3 = document.createElement('div');
    row3.className = 'rail-row';
    this.viewBtn = mkBtn(
      'Internal',
      'Toggle Internal / External view (I)',
      'Switch between Exteroception (pond view, max 12×) and Interoception (120× cytoplasm & vacuole interior view).',
      cb.onToggleIntero,
    );
    this.familyBtn = mkBtn(
      'Family',
      'Family members & cell merging',
      'Inspect living relatives in your lineage, switch control between cells, or merge an eligible relative.',
      cb.onOpenFamily,
    );
    row3.append(this.viewBtn, this.familyBtn);

    const row4 = document.createElement('div');
    row4.className = 'rail-row';
    this.colorBtn = mkBtn(
      'Colors',
      'Lineage colors & name',
      'Customize your lineage membrane palette and signal name. Saved locally across ponds.',
      cb.onOpenPalette,
    );
    this.guideBtn = mkBtn(
      'Guide',
      'Gameplay & science guide (F1)',
      'Open the interactive Biology, Chemistry, and Controls guide with scientific references.',
      cb.onOpenGuide,
    );
    row4.append(this.colorBtn, this.guideBtn);

    const rowAudio = document.createElement('div');
    rowAudio.className = 'volume-wrap interactive';
    this.muteBtn = mkBtn(
      'Music',
      'Mute / unmute progressive audio (M)',
      'Toggle procedural tropical Web Audio driven by cell organelles and sunlight (keyboard: M).',
      cb.onToggleMute,
    );
    this.muteBtn.style.minHeight = '34px';
    this.muteBtn.style.padding = '3px 9px';
    this.volSlider = document.createElement('input');
    this.volSlider.type = 'range';
    this.volSlider.min = '0';
    this.volSlider.max = '100';
    this.volSlider.value = String(Math.round(audio.currentVolume * 100));
    this.volSlider.ariaLabel = 'Music volume';
    bindHoldTooltip(this.volSlider, () => ({
      title: 'Music Volume',
      body: 'Adjust procedural music loudness without muting simulation activity.',
    }));
    this.volSlider.addEventListener('input', () => {
      cb.onVolumeChange(Number(this.volSlider.value) / 100);
    });
    rowAudio.append(this.muteBtn, this.volSlider);

    this.stateBadge = document.createElement('div');
    this.stateBadge.className = 'rail-badge';

    this.rightRail.append(row1, row2, row3, row4, rowAudio, this.stateBadge);
    parent.appendChild(this.rightRail);

    // Bottom-left feed + collapsible resources pill
    this.bottomLeft = document.createElement('div');
    this.bottomLeft.className = 'hud-bottom-left';
    this.statusFeed = new StatusFeed(this.bottomLeft);

    this.resourcesCard = document.createElement('div');
    this.resourcesCard.className = 'resources-pill hud-panel interactive';
    this.summaryRow = document.createElement('div');
    this.summaryRow.className = 'resources-summary';
    this.summaryRow.setAttribute('aria-label', 'Internal resources summary');
    bindHoldTooltip(this.summaryRow, () => ({
      title: 'Cell Resources',
      body: 'Tap to expand or collapse Gut food, Waste, O₂, CO₂, water pH, organ count, and local light.',
    }));
    this.summaryRow.addEventListener('click', (e) => {
      e.stopPropagation();
      this.resourcesExpanded = !this.resourcesExpanded;
      this.detailsGrid.hidden = !this.resourcesExpanded;
    });

    this.detailsGrid = document.createElement('div');
    this.detailsGrid.className = 'res-details';
    this.detailsGrid.hidden = true;
    const vacBtn = mkBtn(
      'Inspect Vacuoles',
      'Inspect internal cytoplasm reserves',
      'Open a detailed list of all active food vacuoles, waste parcels, O₂, and CO₂ droplets inside the focused cell.',
      cb.onOpenVacuoles,
    );
    vacBtn.style.minHeight = '34px';
    vacBtn.style.gridColumn = 'span 2';
    this.detailsGrid.appendChild(vacBtn);

    this.resourcesCard.append(this.summaryRow, this.detailsGrid);
    this.bottomLeft.appendChild(this.resourcesCard);
    parent.appendChild(this.bottomLeft);

    // Left-center ScaleBar
    const scaleWrap = document.createElement('div');
    scaleWrap.className = 'scale-bar-wrap';
    this.scaleLine = document.createElement('div');
    this.scaleLine.className = 'scale-bar-line';
    this.scaleLabel = document.createElement('span');
    scaleWrap.append(this.scaleLine, this.scaleLabel);
    parent.appendChild(scaleWrap);

    // F3 Telemetry Overlay
    this.telemetryEl = document.createElement('div');
    this.telemetryEl.className = 'telemetry-panel hud-panel';
    this.telemetryEl.hidden = true;
    parent.appendChild(this.telemetryEl);
  }

  syncToggles(camera: PondCamera, audio: AudioEngine, paused: boolean): void {
    this.pauseBtn.textContent = paused ? 'Resume' : 'Pause';
    this.pauseBtn.classList.toggle('is-active', paused);
    this.followBtn.textContent = camera.follow ? 'Following' : 'Free Cam';
    this.followBtn.classList.toggle('is-active', camera.follow);
    this.viewBtn.textContent = camera.interoception ? 'External' : 'Internal';
    this.viewBtn.classList.toggle('is-active', camera.interoception);
    this.muteBtn.textContent = audio.isMuted ? 'Muted' : 'Music';
    this.muteBtn.classList.toggle('is-danger', audio.isMuted);
    this.volSlider.value = String(Math.round(audio.currentVolume * 100));
  }

  update(
    sim: Simulation,
    focus: Cell,
    camera: PondCamera,
    audio: AudioEngine,
    paused: boolean,
    fps: number,
    simMs: number,
    nowPerf: number,
  ): void {
    this.statusFeed.update(focus, sim.lineage, paused, nowPerf);
    this.syncToggles(camera, audio, paused);

    const famCount = sim.lineage.activeFamily(sim.cells).length;
    this.familyBtn.textContent = `Family (${famCount})`;

    const linName = sim.lineageNames.get(focus.lineageId()) ?? `Lineage ${focus.lineageId()}`;
    const syn = focus.synergy();
    this.stateBadge.textContent = `${linName} · Gen ${focus.generation}${syn ? ` · ${syn}` : ''}`;

    // Resources pill (no AP metric)
    const br = focus.budget.rates(sim.time);
    const sign = br.net >= 0 ? '+' : '';
    const ph = phFromAcid(sim.acidity.sample(focus.position.x, focus.position.y));
    const bioChip = `Biomass ${focus.biomass.toFixed(1)}`;
    const atpChip = `ATP ${focus.energy.toFixed(0)} (${sign}${br.net.toFixed(1)}/s)`;
    const hpChip = `HP ${focus.health.toFixed(0)}%`;

    this.summaryRow.textContent = `${bioChip}  ·  ${atpChip}  ·  ${hpChip} ${this.resourcesExpanded ? '▾' : '▸'}`;

    if (this.resourcesExpanded) {
      const cells = [
        `Gut: ${focus.substrate.toFixed(1)} / ${focus.gutCapacity().toFixed(1)}`,
        `Waste: ${focus.waste.toFixed(1)}`,
        `O₂: ${focus.oxygen.toFixed(1)} · CO₂: ${focus.carbon.toFixed(1)}`,
        `Water pH: ${ph.toFixed(1)}`,
        `Organs: ${focus.organs.length} (${focus.lostOrgans.length} scars)`,
        `Light: ${(sim.lightAt(focus.position) * 100).toFixed(0)}%`,
      ];
      const existingAction = this.detailsGrid.lastElementChild!;
      const rows = cells.map((t) => {
        const d = document.createElement('div');
        d.textContent = t;
        return d;
      });
      this.detailsGrid.replaceChildren(...rows, existingAction);
    }

    // Dynamic micrometer ScaleBar
    const umPerScreenPx = MICROMETERS_PER_UNIT / Math.max(0.1, camera.zoom);
    const targetUm = 84 * umPerScreenPx;
    let chosenUm: number = NICE_MICROMETERS[NICE_MICROMETERS.length - 1];
    for (const u of NICE_MICROMETERS) {
      chosenUm = u;
      if (u >= targetUm * 0.72) break;
    }
    const barPx = Math.max(24, Math.min(130, chosenUm / umPerScreenPx));
    this.scaleLine.style.height = `${Math.round(barPx)}px`;
    this.scaleLabel.textContent = `${chosenUm} μm`;

    if (this.telemetryVisible) {
      const living = sim.cells.filter((c) => !c.dead && c.health > 0).length;
      this.telemetryEl.replaceChildren(
        ...([
          `FPS: ${fps.toFixed(0)} · Sim tick: ${simMs.toFixed(2)} ms`,
          `Zoom: ${(camera.zoom * 100).toFixed(0)}% (min ${(camera.minZoom() * 100).toFixed(0)}%) · View: ${camera.interoception ? 'Interoception' : 'Exteroception'}`,
          `Living cells: ${living} · Family: ${famCount} · Kills: ${sim.kills}`,
          `GPU Particles: ${sim.gpuCensus.alive} / 32768 (Phero: ${sim.gpuCensus.pheromones}, O₂: ${sim.gpuCensus.oxygen})`,
          `Reactions: ${sim.gpuCensus.reactions} · Recycled: ${sim.recycled.toFixed(1)}`,
          `Pond: ${sim.time.toFixed(1)}s · ${sim.environment.utc || 'UTC'} · ${sim.environment.weather}`,
        ].map((line) => {
          const d = document.createElement('div');
          d.textContent = line;
          return d;
        })),
      );
    }
  }
}
