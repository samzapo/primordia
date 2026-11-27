import './style.css';
import { AudioEngine } from './audio/engine.ts';
import { ParticleEngine } from './gpu/particleEngine.ts';
import { Renderer } from './render/renderer.ts';
import { DT } from './sim/constants.ts';
import { Simulation } from './sim/simulation.ts';
import { PondCamera } from './ui/camera.ts';
import { CellInterface } from './ui/cellInterface.ts';
import { Hud } from './ui/hud.ts';
import { InputController } from './ui/input.ts';
import { ParticleInspector } from './ui/inspector.ts';
import { ModalManager, type VisualPrefs } from './ui/modals.ts';

interface SavedPrefs extends VisualPrefs {
  musicMuted: boolean;
  musicVolume: number;
  lineageColor?: string;
  lineageName?: string;
}

const PREFS_KEY = 'primordia_prefs_v1';

const DEFAULT_PREFS: SavedPrefs = {
  bloomEnabled: true,
  ripplesEnabled: true,
  blurEnabled: true,
  simpleParticles: false,
  musicMuted: false,
  musicVolume: 0.72,
};

function loadPrefs(): SavedPrefs {
  try {
    const raw = localStorage.getItem(PREFS_KEY);
    if (!raw) return { ...DEFAULT_PREFS };
    return { ...DEFAULT_PREFS, ...(JSON.parse(raw) as Partial<SavedPrefs>) };
  } catch {
    return { ...DEFAULT_PREFS };
  }
}

function savePrefs(p: SavedPrefs): void {
  try {
    localStorage.setItem(PREFS_KEY, JSON.stringify(p));
  } catch {
    // ignore storage restrictions
  }
}

function setSplashError(message: string): void {
  const label = document.getElementById('loading-label');
  const prog = document.getElementById('loading-progress');
  const err = document.getElementById('load-error');
  const retry = document.getElementById('retry');
  if (label) label.hidden = true;
  if (prog) prog.hidden = true;
  if (err) {
    err.textContent = message;
    err.hidden = false;
  }
  if (retry) {
    retry.hidden = false;
    retry.addEventListener('click', () => window.location.reload(), { once: true });
  }
}

async function boot(): Promise<void> {
  const statusEl = document.getElementById('status');
  const loadingLabel = document.getElementById('loading-label');
  const loadingProgress = document.getElementById('loading-progress') as HTMLProgressElement | null;
  const canvas = document.getElementById('canvas') as HTMLCanvasElement | null;
  const hudRoot = document.getElementById('hud');

  if (!canvas || !hudRoot) return;

  if (!navigator.gpu) {
    setSplashError('WebGPU is not available in this browser. Open Primordia in Chromium/Chrome 113+ or Edge/Firefox with WebGPU enabled.');
    return;
  }

  if (loadingLabel) loadingLabel.textContent = 'Requesting WebGPU adapter…';
  if (loadingProgress) loadingProgress.value = 0.25;

  const adapter = await navigator.gpu.requestAdapter({ powerPreference: 'high-performance' });
  if (!adapter) {
    setSplashError('No compatible GPU adapter found for WebGPU.');
    return;
  }

  const device = await adapter.requestDevice();
  device.addEventListener('uncapturederror', (ev) => {
    console.error('[WebGPU uncapturederror]', ev.error.message);
  });
  void device.lost.then((info) => {
    if (info.reason !== 'destroyed') {
      console.error('[WebGPU device lost]', info.reason, info.message);
    }
  });
  const context = canvas.getContext('webgpu');
  if (!context) {
    setSplashError('Could not acquire a WebGPU canvas context.');
    return;
  }

  const format = navigator.gpu.getPreferredCanvasFormat();
  const configureCanvas = () => {
    const dpr = Math.min(2, window.devicePixelRatio || 1);
    const w = Math.max(2, Math.round(window.innerWidth * dpr));
    const h = Math.max(2, Math.round(window.innerHeight * dpr));
    if (canvas.width !== w || canvas.height !== h) {
      canvas.width = w;
      canvas.height = h;
      context.configure({ device, format, alphaMode: 'opaque' });
    }
    return dpr;
  };
  let curDpr = configureCanvas();
  window.addEventListener('resize', () => {
    curDpr = configureCanvas();
  });

  if (loadingLabel) loadingLabel.textContent = 'Seeding pond ecosystem…';
  if (loadingProgress) loadingProgress.value = 0.6;

  let prefs = loadPrefs();
  let sim = new Simulation(20261004, 0, true);
  if (prefs.lineageColor) sim.lineageColors.set(sim.player.lineageId(), prefs.lineageColor);
  if (prefs.lineageName) sim.lineageNames.set(sim.player.lineageId(), prefs.lineageName);

  const particleEngine = new ParticleEngine(device);
  particleEngine.seedInitialParticles(sim.drainInitialParticles(), sim.fluid);

  const renderer = new Renderer(device, context, format, sim, particleEngine);
  const audio = new AudioEngine();
  audio.setVolume(prefs.musicVolume);
  audio.setMuted(prefs.musicMuted, sim);

  const camera = new PondCamera();
  camera.setFocusCell(sim.player, false);

  let userPaused = false;
  let mergeSelecting = false;
  let lastPlayerId = sim.player.id;
  let lastOfferCount = 0;

  const inspector = new ParticleInspector(hudRoot);

  const cellUI = new CellInterface(hudRoot, renderer.organIcons2D, {
    onOpenFamily: () => modals.open('family', sim),
    onOpenPalette: () => modals.open('palette', sim),
    onOpenInvestment: () => modals.open('investment', sim),
    onNotice: (msg) => hud.statusFeed.pushNotice(msg, performance.now() / 1000),
    onEditOccurred: () => audio.onEdit(sim),
  });

  const hud = new Hud(
    hudRoot,
    {
      onTogglePause: () => {
        userPaused = !userPaused;
        hud.syncToggles(camera, audio, userPaused || modals.isOpen);
      },
      onZoomStep: (factor) => {
        const focus = sim.cells.find((c) => c.id === camera.focusCellId && !c.dead) ?? sim.player;
        camera.zoomAtScreenPoint(factor, canvas.clientWidth * 0.5, canvas.clientHeight * 0.5, canvas.clientWidth, canvas.clientHeight, focus);
      },
      onToggleFollow: () => {
        const focus = sim.cells.find((c) => c.id === camera.focusCellId && !c.dead) ?? sim.player;
        camera.toggleFollow(focus);
        hud.syncToggles(camera, audio, userPaused || modals.isOpen);
      },
      onToggleIntero: () => {
        const focus = sim.cells.find((c) => c.id === camera.focusCellId && !c.dead) ?? sim.player;
        camera.toggleInteroception(focus);
        hud.syncToggles(camera, audio, userPaused || modals.isOpen);
      },
      onOpenFamily: () => modals.open('family', sim),
      onOpenPalette: () => modals.open('palette', sim),
      onOpenGuide: () => modals.open('guide', sim),
      onOpenSettings: () => modals.open('settings', sim),
      onOpenVacuoles: () => modals.open('vacuoles', sim),
      onToggleMute: () => {
        audio.unlock();
        audio.setMuted(!audio.isMuted, sim);
        prefs.musicMuted = audio.isMuted;
        savePrefs(prefs);
        hud.syncToggles(camera, audio, userPaused || modals.isOpen);
      },
      onVolumeChange: (v) => {
        audio.unlock();
        audio.setVolume(v);
        if (audio.isMuted && v > 0.01) audio.setMuted(false, sim);
        prefs.musicVolume = v;
        prefs.musicMuted = audio.isMuted;
        savePrefs(prefs);
        hud.syncToggles(camera, audio, userPaused || modals.isOpen);
      },
    },
    audio,
  );

  const modals = new ModalManager(hudRoot, {
    getVisualPrefs: () => ({
      bloomEnabled: prefs.bloomEnabled,
      ripplesEnabled: prefs.ripplesEnabled,
      blurEnabled: prefs.blurEnabled,
      simpleParticles: prefs.simpleParticles,
    }),
    setVisualPrefs: (next) => {
      prefs = { ...prefs, ...next };
      savePrefs(prefs);
    },
    onNewExpedition: (seed, habitat) => {
      sim = new Simulation(seed, habitat, true);
      if (prefs.lineageColor) sim.lineageColors.set(sim.player.lineageId(), prefs.lineageColor);
      if (prefs.lineageName) sim.lineageNames.set(sim.player.lineageId(), prefs.lineageName);
      particleEngine.seedInitialParticles(sim.drainInitialParticles(), sim.fluid);
      renderer.syncWorld(sim);
      audio.resetForNewPond(sim);
      camera.interoception = false;
      camera.follow = true;
      camera.setFocusCell(sim.player, false);
      cellUI.close();
      inspector.cancel();
      mergeSelecting = false;
      userPaused = false;
      lastPlayerId = sim.player.id;
      lastOfferCount = 0;
      hud.statusFeed.pushNotice(`New Pond seeded (#${seed})`, performance.now() / 1000);
    },
    onResetPrefs: () => {
      prefs = { ...DEFAULT_PREFS };
      savePrefs(prefs);
      audio.setVolume(prefs.musicVolume);
      audio.setMuted(prefs.musicMuted, sim);
    },
    onEnterMergeMode: () => {
      const cands = sim.mergeCandidatesForPlayer();
      const candCells = sim.cells.filter((c) => !c.dead && cands.has(c.id));
      if (candCells.length > 0) {
        mergeSelecting = true;
        camera.frameMergeNeighborhood(sim.player, candCells, canvas.clientWidth, canvas.clientHeight);
        hud.statusFeed.pushNotice('Tap a highlighted relative to merge into this cell', performance.now() / 1000);
      }
    },
    onFollowCell: (c) => {
      camera.setFocusCell(c, true);
    },
    onLineageStyleChanged: (_linId, hex, name) => {
      prefs.lineageColor = hex;
      prefs.lineageName = name;
      savePrefs(prefs);
    },
    onNotice: (msg) => hud.statusFeed.pushNotice(msg, performance.now() / 1000),
    onResumeRequest: () => {
      userPaused = false;
    },
  });

  const input = new InputController(canvas, camera, cellUI, inspector, {
    getSim: () => sim,
    getMergeMode: () => mergeSelecting,
    setMergeMode: (v) => {
      mergeSelecting = v;
    },
    isModalOpen: () => modals.isOpen,
    onUserGesture: () => audio.unlock(),
    onTogglePause: () => {
      userPaused = !userPaused;
    },
    onToggleFollow: () => {
      const focus = sim.cells.find((c) => c.id === camera.focusCellId && !c.dead) ?? sim.player;
      camera.toggleFollow(focus);
    },
    onToggleIntero: () => {
      const focus = sim.cells.find((c) => c.id === camera.focusCellId && !c.dead) ?? sim.player;
      camera.toggleInteroception(focus);
    },
    onToggleMute: () => {
      audio.unlock();
      audio.setMuted(!audio.isMuted, sim);
      prefs.musicMuted = audio.isMuted;
      savePrefs(prefs);
    },
    onToggleTelemetry: () => {
      hud.telemetryVisible = !hud.telemetryVisible;
      hud.telemetryEl.hidden = !hud.telemetryVisible;
    },
    onOpenGuide: () => modals.open('guide', sim),
    onOpenSettings: () => modals.open('settings', sim),
    onEscape: () => {
      if (modals.isOpen) modals.close();
      else if (mergeSelecting) mergeSelecting = false;
      else if (cellUI.placingKind) cellUI.cancelPlacement();
      else if (cellUI.active) cellUI.close();
      else modals.open('settings', sim);
    },
    onNotice: (msg) => hud.statusFeed.pushNotice(msg, performance.now() / 1000),
    onEditOccurred: () => audio.onEdit(sim),
  });

  if (loadingLabel) loadingLabel.textContent = 'Starting WebGPU pipeline…';
  if (loadingProgress) loadingProgress.value = 0.9;

  let splashDismissed = false;
  let lastFrameMs = performance.now();
  let accumulator = 0;
  let fpsSmooth = 60;
  let simMsSmooth = 1.5;

  const frame = (nowMs: number) => {
    const rawDt = Math.min(0.05, Math.max(0.0005, (nowMs - lastFrameMs) / 1000));
    lastFrameMs = nowMs;
    fpsSmooth = fpsSmooth * 0.92 + (1 / Math.max(0.001, rawDt)) * 0.08;

    const paused = userPaused || modals.isOpen;
    const mergeCands = mergeSelecting ? sim.mergeCandidatesForPlayer() : new Map<number, number>();

    const encoder = device.createCommandEncoder({ label: 'frameEncoder' });

    if (!paused) {
      accumulator += rawDt;
      let steps = 0;
      const t0 = performance.now();
      while (accumulator >= DT && steps < 2) {
        const receipts = particleEngine.pollReceipts();
        const gpuInput = sim.step(DT, receipts);
        particleEngine.encodeTick(encoder, gpuInput, sim.fluid);
        accumulator -= DT;
        steps++;
      }
      if (steps > 0) {
        simMsSmooth = simMsSmooth * 0.88 + (performance.now() - t0) * 0.12;
      }
      if (accumulator > DT * 2) accumulator = DT;

      // Detect succession / death camera framing
      if (sim.player.id !== lastPlayerId) {
        lastPlayerId = sim.player.id;
        camera.setFocusCell(sim.player, true);
        cellUI.close();
      }
      if (sim.player.dead && sim.deathBursts.length > 0 && camera.deathFocusUntil < sim.time) {
        camera.triggerDeathFraming(sim.deathBursts[sim.deathBursts.length - 1].at, sim.time);
      }
      if (sim.evolution.divisionOffers.length > lastOfferCount && !modals.isOpen) {
        lastOfferCount = sim.evolution.divisionOffers.length;
        modals.open('mutation_offer', sim);
      } else {
        lastOfferCount = sim.evolution.divisionOffers.length;
      }
    }

    const activeFocus = sim.cells.find((c) => c.id === camera.focusCellId && !c.dead) ?? sim.player;
    camera.update(rawDt, activeFocus, sim.time);
    audio.update(sim, activeFocus, paused);

    const inspectState = inspector.update(
      sim,
      activeFocus,
      camera,
      input.pointerX,
      input.pointerY,
      input.pointerInside,
      input.lastInputIsTouch,
      modals.isOpen || mergeSelecting || cellUI.placingKind !== null,
      canvas.clientWidth,
      canvas.clientHeight,
      nowMs / 1000,
    );

    const mergeIds = new Set<number>(mergeCands.keys());

    renderer.render(encoder, sim, {
      camX: camera.x,
      camY: camera.y,
      zoom: camera.zoom,
      rotation: camera.rotation,
      dpr: curDpr,
      screenCssW: canvas.clientWidth,
      screenCssH: canvas.clientHeight,
      interoception: camera.interoception,
      focusCellId: activeFocus.id,
      mergeSelecting,
      mergeCandidateIds: mergeIds,
      editingCellId: cellUI.active ? activeFocus.id : null,
      selectedOrganId: cellUI.selectedOrganId,
      previewPlacement: cellUI.placingKind
        ? {
            kind: cellUI.placingKind,
            angle: cellUI.previewAngle,
            valid: cellUI.previewValid,
            pulse: sim.time,
          }
        : null,
      inspector: inspectState,
      audioWaves: audio.activeWaves(sim),
      bloomEnabled: prefs.bloomEnabled,
      ripplesEnabled: prefs.ripplesEnabled,
      blurEnabled: prefs.blurEnabled,
      simpleParticles: prefs.simpleParticles,
      paused,
      frameDt: rawDt,
    });

    device.queue.submit([encoder.finish()]);
    if (!paused) {
      particleEngine.afterSubmit();
    }

    cellUI.render(sim, activeFocus);
    hud.update(sim, activeFocus, camera, audio, paused, fpsSmooth, simMsSmooth, nowMs / 1000);

    if (!splashDismissed) {
      splashDismissed = true;
      if (loadingProgress) loadingProgress.value = 1;
      statusEl?.classList.add('is-ready');
      window.setTimeout(() => {
        if (statusEl) statusEl.hidden = true;
      }, 260);
    }

    requestAnimationFrame(frame);
  };

  requestAnimationFrame(frame);
}

void boot();
