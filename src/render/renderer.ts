import type { ParticleEngine } from '../gpu/particleEngine.ts';
import {
  ORGAN_TITLES,
  type Cell,
  type OrganKind,
  ORGAN_KINDS,
  isInternalOrgan,
} from '../sim/cell.ts';
import { clamp, offsetVec, SPECIES, type Vec2, WORLD_H, WORLD_W, wrapPos } from '../sim/constants.ts';
import { LIGHT_COLS, LIGHT_ROWS, getLightGrid, lightDirection } from '../sim/lightField.ts';
import { SPECIES_RADII, particleRadius } from '../sim/catalog.ts';
import { vacuoleVisualRadius } from '../sim/cellChemistry.ts';
import { proboscisTip } from '../sim/proboscis.ts';
import type { Simulation } from '../sim/simulation.ts';
import {
  LANDMARK_SPRITE_KINDS,
  generatePlantAtlas,
  generateProceduralAtlases,
  type ProceduralAtlases,
} from './atlasGenerator.ts';
import { CellMotionTracker, type CellMotionTransform } from './cellMotion.ts';
import { computeInteriorLandmarks, type LandmarkKind } from './factoryLayout.ts';
import { buildFlowCurves } from './flowCurves.ts';
import {
  hexToRgba,
  lineagePalette,
  mixRgb,
  nucleusForm,
  ORGAN_COLORS,
  parseHex,
  pitchWaveColor,
  signalColorForLineage,
} from './palette.ts';
import downsampleWgsl from './shaders/downsample.wgsl?raw';
import microscopeWgsl from './shaders/microscope.wgsl?raw';
import particlesWgsl from './shaders/particles.wgsl?raw';
import renderCommonWgsl from './shaders/renderCommon.wgsl?raw';
import waterWgsl from './shaders/water.wgsl?raw';
import { SpriteBatch, type SpriteDrawCmd } from './spriteBatch.ts';
import { VectorBatch, type VectorDrawCmd } from './vectorBatch.ts';

export interface AudioWaveVisual {
  x: number;
  y: number;
  semitones: number;
  radius: number;
  alpha: number;
}

export interface InspectorRenderState {
  active: boolean;
  screenX: number; // CSS px
  screenY: number; // CSS px
  radiusPx: number; // CSS px
}

export interface RenderFrameState {
  camX: number;
  camY: number;
  zoom: number; // CSS px zoom
  rotation: number;
  dpr: number;
  screenCssW: number;
  screenCssH: number;
  interoception: boolean;
  focusCellId: number;
  mergeSelecting: boolean;
  mergeCandidateIds: ReadonlySet<number>;
  editingCellId: number | null;
  selectedOrganId: number | null;
  previewPlacement: { kind: OrganKind; angle: number; valid: boolean; pulse: number } | null;
  inspector: InspectorRenderState;
  audioWaves: readonly AudioWaveVisual[];
  bloomEnabled: boolean;
  ripplesEnabled: boolean;
  blurEnabled: boolean;
  simpleParticles: boolean;
  paused: boolean;
  frameDt: number;
}

type LayerCmd = { kind: 'vec'; cmd: VectorDrawCmd } | { kind: 'spr'; cmd: SpriteDrawCmd };

const ORGAN_LAYER_INDEX = new Map<OrganKind, number>(ORGAN_KINDS.map((k, i) => [k, i]));
const LANDMARK_LAYER_INDEX = new Map<LandmarkKind, number>(LANDMARK_SPRITE_KINDS.map((k, i) => [k, i]));

export class Renderer {
  readonly device: GPUDevice;
  readonly context: GPUCanvasContext;
  readonly format: GPUTextureFormat;
  private readonly atlases: ProceduralAtlases;
  private readonly vectorBatch: VectorBatch;
  private readonly spriteBatch: SpriteBatch;
  private readonly motionTracker = new CellMotionTracker();

  // Camera & Particle LUT Uniforms
  private readonly camUniformBuf: GPUBuffer;
  private readonly camUniformF32 = new Float32Array(24);
  private readonly lutUniformBuf: GPUBuffer;
  private readonly lutUniformF32 = new Float32Array(64 * 4);

  // Light Field 128x80 r8unorm texture
  private readonly lightTex: GPUTexture;
  private readonly lightBytes = new Uint8Array(LIGHT_COLS * LIGHT_ROWS);
  private readonly lightSampler: GPUSampler;

  // Offscreen render targets (recreated on canvas size change)
  private rtWidth = 0;
  private rtHeight = 0;
  private sceneTex!: GPUTexture;
  private sceneMipViews: GPUTextureView[] = [];
  private focusMaskTex!: GPUTexture;
  private focusMaskView!: GPUTextureView;

  // Pipelines & Bind Groups
  private readonly waterPipe: GPURenderPipeline;
  private readonly waterBG: GPUBindGroup;
  private readonly particlesPipe: GPURenderPipeline;
  private readonly particlesDetailedBG: GPUBindGroup;
  private readonly particlesSimpleBG: GPUBindGroup;
  private readonly downsamplePipe: GPURenderPipeline;
  private readonly downsampleBGL: GPUBindGroupLayout;
  private downsampleBGs: GPUBindGroup[] = [];
  private readonly microscopePipe: GPURenderPipeline;
  private readonly microscopeBGL: GPUBindGroupLayout;
  private microscopeBG!: GPUBindGroup;

  private readonly vectorBG: GPUBindGroup;
  private readonly spriteBGs: Record<
    'plants' | 'organs' | 'nuclei' | 'landmarks' | 'vacuoles' | 'speciesDetailed' | 'speciesSimple',
    GPUBindGroup
  >;
  private readonly clampSampler: GPUSampler;

  constructor(
    device: GPUDevice,
    context: GPUCanvasContext,
    format: GPUTextureFormat,
    sim: Simulation,
    particleEngine: ParticleEngine,
  ) {
    this.device = device;
    this.context = context;
    this.format = format;
    this.atlases = generateProceduralAtlases(device, sim.habitatGeometry.forms);
    this.vectorBatch = new VectorBatch(device, format);
    this.spriteBatch = new SpriteBatch(device, format);

    this.camUniformBuf = device.createBuffer({
      label: 'cameraUniforms',
      size: 24 * 4,
      usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST,
    });
    this.lutUniformBuf = device.createBuffer({
      label: 'lineageLut',
      size: 64 * 4 * 4,
      usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST,
    });

    this.lightTex = device.createTexture({
      label: 'lightFieldTex',
      size: [LIGHT_COLS, LIGHT_ROWS, 1],
      format: 'r8unorm',
      usage: GPUTextureUsage.TEXTURE_BINDING | GPUTextureUsage.COPY_DST,
    });
    const lightGrid = getLightGrid(sim.seedValue);
    for (let i = 0; i < lightGrid.length; i++) {
      this.lightBytes[i] = Math.round(clamp(lightGrid[i], 0, 1) * 255);
    }
    device.queue.writeTexture(
      { texture: this.lightTex },
      this.lightBytes,
      { bytesPerRow: LIGHT_COLS },
      [LIGHT_COLS, LIGHT_ROWS, 1],
    );
    this.lightSampler = device.createSampler({
      magFilter: 'linear',
      minFilter: 'linear',
      addressModeU: 'repeat',
      addressModeV: 'repeat',
    });
    this.clampSampler = device.createSampler({
      magFilter: 'linear',
      minFilter: 'linear',
      mipmapFilter: 'linear',
      addressModeU: 'clamp-to-edge',
      addressModeV: 'clamp-to-edge',
    });

    this.vectorBG = device.createBindGroup({
      layout: this.vectorBatch.bindGroupLayout,
      entries: [{ binding: 0, resource: { buffer: this.camUniformBuf } }],
    });

    const mkSpriteBG = (tex: GPUTexture): GPUBindGroup =>
      device.createBindGroup({
        layout: this.spriteBatch.bindGroupLayout,
        entries: [
          { binding: 0, resource: { buffer: this.camUniformBuf } },
          { binding: 1, resource: tex.createView({ dimension: '2d-array' }) },
          { binding: 2, resource: this.atlases.sampler },
        ],
      });

    this.spriteBGs = {
      plants: mkSpriteBG(this.atlases.plants),
      organs: mkSpriteBG(this.atlases.organs),
      nuclei: mkSpriteBG(this.atlases.nuclei),
      landmarks: mkSpriteBG(this.atlases.landmarks),
      vacuoles: mkSpriteBG(this.atlases.vacuoles),
      speciesDetailed: mkSpriteBG(this.atlases.speciesDetailed),
      speciesSimple: mkSpriteBG(this.atlases.speciesSimple),
    };

    // Water pipeline
    const waterBGL = device.createBindGroupLayout({
      label: 'waterBGL',
      entries: [
        { binding: 0, visibility: GPUShaderStage.VERTEX | GPUShaderStage.FRAGMENT, buffer: { type: 'uniform' } },
        { binding: 1, visibility: GPUShaderStage.FRAGMENT, buffer: { type: 'read-only-storage' } },
        { binding: 2, visibility: GPUShaderStage.FRAGMENT, texture: { sampleType: 'float' } },
        { binding: 3, visibility: GPUShaderStage.FRAGMENT, sampler: { type: 'filtering' } },
      ],
    });
    const waterMod = device.createShaderModule({ code: `${renderCommonWgsl}\n${waterWgsl}` });
    this.waterPipe = device.createRenderPipeline({
      label: 'waterPipe',
      layout: device.createPipelineLayout({ bindGroupLayouts: [waterBGL] }),
      vertex: { module: waterMod, entryPoint: 'vsMain' },
      fragment: { module: waterMod, entryPoint: 'fsMain', targets: [{ format: 'rgba8unorm' }] },
      primitive: { topology: 'triangle-list' },
    });
    this.waterBG = device.createBindGroup({
      layout: waterBGL,
      entries: [
        { binding: 0, resource: { buffer: this.camUniformBuf } },
        { binding: 1, resource: { buffer: particleEngine.acidFieldBuffer } },
        { binding: 2, resource: this.lightTex.createView() },
        { binding: 3, resource: this.lightSampler },
      ],
    });

    // GPU Instanced Particles pipeline (reads particlesBuffer directly)
    const particlesBGL = device.createBindGroupLayout({
      label: 'particlesBGL',
      entries: [
        { binding: 0, visibility: GPUShaderStage.VERTEX | GPUShaderStage.FRAGMENT, buffer: { type: 'uniform' } },
        { binding: 1, visibility: GPUShaderStage.VERTEX, buffer: { type: 'read-only-storage' } },
        { binding: 2, visibility: GPUShaderStage.VERTEX, buffer: { type: 'read-only-storage' } },
        { binding: 3, visibility: GPUShaderStage.VERTEX, buffer: { type: 'uniform' } },
        { binding: 4, visibility: GPUShaderStage.FRAGMENT, texture: { sampleType: 'float', viewDimension: '2d-array' } },
        { binding: 5, visibility: GPUShaderStage.FRAGMENT, sampler: { type: 'filtering' } },
      ],
    });
    const particlesMod = device.createShaderModule({ code: `${renderCommonWgsl}\n${particlesWgsl}` });
    this.particlesPipe = device.createRenderPipeline({
      label: 'particlesPipe',
      layout: device.createPipelineLayout({ bindGroupLayouts: [particlesBGL] }),
      vertex: { module: particlesMod, entryPoint: 'vsMain' },
      fragment: {
        module: particlesMod,
        entryPoint: 'fsMain',
        targets: [
          {
            format: 'rgba8unorm',
            blend: {
              color: { srcFactor: 'src-alpha', dstFactor: 'one-minus-src-alpha', operation: 'add' },
              alpha: { srcFactor: 'one', dstFactor: 'one-minus-src-alpha', operation: 'add' },
            },
          },
        ],
      },
      primitive: { topology: 'triangle-list' },
    });

    const mkParticlesBG = (tex: GPUTexture): GPUBindGroup =>
      device.createBindGroup({
        layout: particlesBGL,
        entries: [
          { binding: 0, resource: { buffer: this.camUniformBuf } },
          { binding: 1, resource: { buffer: particleEngine.particlesBuffer } },
          { binding: 2, resource: { buffer: particleEngine.reportsBuffer } },
          { binding: 3, resource: { buffer: this.lutUniformBuf } },
          { binding: 4, resource: tex.createView({ dimension: '2d-array' }) },
          { binding: 5, resource: this.atlases.sampler },
        ],
      });
    this.particlesDetailedBG = mkParticlesBG(this.atlases.speciesDetailed);
    this.particlesSimpleBG = mkParticlesBG(this.atlases.speciesSimple);

    // Downsample mipmap pipeline
    this.downsampleBGL = device.createBindGroupLayout({
      label: 'downsampleBGL',
      entries: [
        { binding: 0, visibility: GPUShaderStage.FRAGMENT, texture: { sampleType: 'float' } },
        { binding: 1, visibility: GPUShaderStage.FRAGMENT, sampler: { type: 'filtering' } },
      ],
    });
    const dsMod = device.createShaderModule({ code: downsampleWgsl });
    this.downsamplePipe = device.createRenderPipeline({
      label: 'downsamplePipe',
      layout: device.createPipelineLayout({ bindGroupLayouts: [this.downsampleBGL] }),
      vertex: { module: dsMod, entryPoint: 'vsMain' },
      fragment: { module: dsMod, entryPoint: 'fsMain', targets: [{ format: 'rgba8unorm' }] },
      primitive: { topology: 'triangle-list' },
    });

    // Microscope post-process pipeline -> swapchain
    this.microscopeBGL = device.createBindGroupLayout({
      label: 'microscopeBGL',
      entries: [
        { binding: 0, visibility: GPUShaderStage.VERTEX | GPUShaderStage.FRAGMENT, buffer: { type: 'uniform' } },
        { binding: 1, visibility: GPUShaderStage.FRAGMENT, texture: { sampleType: 'float' } },
        { binding: 2, visibility: GPUShaderStage.FRAGMENT, texture: { sampleType: 'float' } },
        { binding: 3, visibility: GPUShaderStage.FRAGMENT, sampler: { type: 'filtering' } },
      ],
    });
    const micMod = device.createShaderModule({ code: `${renderCommonWgsl}\n${microscopeWgsl}` });
    this.microscopePipe = device.createRenderPipeline({
      label: 'microscopePipe',
      layout: device.createPipelineLayout({ bindGroupLayouts: [this.microscopeBGL] }),
      vertex: { module: micMod, entryPoint: 'vsMain' },
      fragment: { module: micMod, entryPoint: 'fsMain', targets: [{ format }] },
      primitive: { topology: 'triangle-list' },
    });
  }

  get organIcons2D(): Map<OrganKind, string> {
    return this.atlases.organIcons2D;
  }

  syncWorld(sim: Simulation): void {
    const lightGrid = getLightGrid(sim.seedValue);
    for (let i = 0; i < lightGrid.length; i++) {
      this.lightBytes[i] = Math.round(clamp(lightGrid[i], 0, 1) * 255);
    }
    this.device.queue.writeTexture(
      { texture: this.lightTex },
      this.lightBytes,
      { bytesPerRow: LIGHT_COLS },
      [LIGHT_COLS, LIGHT_ROWS, 1],
    );

    const oldPlants = this.atlases.plants;
    const nextPlants = generatePlantAtlas(this.device, sim.habitatGeometry.forms);
    this.atlases.plants = nextPlants;
    this.spriteBGs.plants = this.device.createBindGroup({
      layout: this.spriteBatch.bindGroupLayout,
      entries: [
        { binding: 0, resource: { buffer: this.camUniformBuf } },
        { binding: 1, resource: nextPlants.createView({ dimension: '2d-array' }) },
        { binding: 2, resource: this.atlases.sampler },
      ],
    });
    oldPlants.destroy();
  }

  private ensureTargets(w: number, h: number): void {
    const safeW = Math.max(2, w | 0);
    const safeH = Math.max(2, h | 0);
    if (safeW === this.rtWidth && safeH === this.rtHeight) return;

    this.sceneTex?.destroy();
    this.focusMaskTex?.destroy();

    this.rtWidth = safeW;
    this.rtHeight = safeH;
    this.sceneTex = this.device.createTexture({
      label: 'sceneTex',
      size: [safeW, safeH, 1],
      mipLevelCount: 5,
      format: 'rgba8unorm',
      usage: GPUTextureUsage.RENDER_ATTACHMENT | GPUTextureUsage.TEXTURE_BINDING,
    });
    this.sceneMipViews = [];
    for (let mip = 0; mip < 5; mip++) {
      this.sceneMipViews.push(
        this.sceneTex.createView({ baseMipLevel: mip, mipLevelCount: 1 }),
      );
    }

    this.focusMaskTex = this.device.createTexture({
      label: 'focusMaskTex',
      size: [safeW, safeH, 1],
      format: 'r8unorm',
      usage: GPUTextureUsage.RENDER_ATTACHMENT | GPUTextureUsage.TEXTURE_BINDING,
    });
    this.focusMaskView = this.focusMaskTex.createView();

    this.downsampleBGs = [];
    for (let mip = 0; mip < 4; mip++) {
      this.downsampleBGs.push(
        this.device.createBindGroup({
          layout: this.downsampleBGL,
          entries: [
            { binding: 0, resource: this.sceneMipViews[mip] },
            { binding: 1, resource: this.clampSampler },
          ],
        }),
      );
    }

    this.microscopeBG = this.device.createBindGroup({
      layout: this.microscopeBGL,
      entries: [
        { binding: 0, resource: { buffer: this.camUniformBuf } },
        { binding: 1, resource: this.sceneTex.createView() },
        { binding: 2, resource: this.focusMaskView },
        { binding: 3, resource: this.clampSampler },
      ],
    });
  }

  private updateUniforms(sim: Simulation, state: RenderFrameState, focusPos: Vec2): void {
    const effZoom = state.zoom * state.dpr;
    const w = this.rtWidth;
    const h = this.rtHeight;

    this.camUniformF32[0] = state.camX;
    this.camUniformF32[1] = state.camY;
    this.camUniformF32[2] = effZoom;
    this.camUniformF32[3] = state.rotation;

    this.camUniformF32[4] = w;
    this.camUniformF32[5] = h;
    this.camUniformF32[6] = sim.time;
    this.camUniformF32[7] = sim.environment.light;

    this.camUniformF32[8] = state.inspector.screenX * state.dpr;
    this.camUniformF32[9] = state.inspector.screenY * state.dpr;
    this.camUniformF32[10] = state.inspector.radiusPx * state.dpr;
    this.camUniformF32[11] = state.inspector.active ? 1 : 0;

    this.camUniformF32[12] = state.interoception ? 1 : 0;
    this.camUniformF32[13] = state.mergeSelecting ? 1 : 0;
    this.camUniformF32[14] = state.bloomEnabled ? 1 : 0;
    this.camUniformF32[15] = state.ripplesEnabled ? 1 : 0;

    this.camUniformF32[16] = state.blurEnabled ? 1 : 0;
    this.camUniformF32[17] = state.simpleParticles ? 1 : 0;
    this.camUniformF32[18] = focusPos.x;
    this.camUniformF32[19] = focusPos.y;

    this.camUniformF32[20] = WORLD_W;
    this.camUniformF32[21] = WORLD_H;
    this.camUniformF32[22] = state.interoception ? 0.42 : 0.88;
    this.camUniformF32[23] = 0;

    this.device.queue.writeBuffer(this.camUniformBuf, 0, this.camUniformF32);

    // Update 64-slot lineage color LUT for GPU pheromone particles
    for (let slot = 0; slot < 64; slot++) {
      const hex = signalColorForLineage(sim.seedValue, slot, sim.lineageColors.get(slot));
      const rgb = parseHex(hex);
      this.lutUniformF32[slot * 4 + 0] = rgb.r;
      this.lutUniformF32[slot * 4 + 1] = rgb.g;
      this.lutUniformF32[slot * 4 + 2] = rgb.b;
      this.lutUniformF32[slot * 4 + 3] = 1;
    }
    for (const c of sim.cells) {
      const lin = c.lineageId();
      const slot = ((lin % 64) + 64) % 64;
      const hex = signalColorForLineage(sim.seedValue, lin, sim.lineageColors.get(lin));
      const rgb = parseHex(hex);
      this.lutUniformF32[slot * 4 + 0] = rgb.r;
      this.lutUniformF32[slot * 4 + 1] = rgb.g;
      this.lutUniformF32[slot * 4 + 2] = rgb.b;
      this.lutUniformF32[slot * 4 + 3] = 1;
    }
    this.device.queue.writeBuffer(this.lutUniformBuf, 0, this.lutUniformF32);
  }

  private isRelVisible(rel: Vec2, margin: number, state: RenderFrameState, effHalfW: number, effHalfH: number): boolean {
    const c = Math.cos(-state.rotation);
    const s = Math.sin(-state.rotation);
    const sx = rel.x * c - rel.y * s;
    const sy = rel.x * s + rel.y * c;
    return Math.abs(sx) <= effHalfW + margin && Math.abs(sy) <= effHalfH + margin;
  }

  private relOutlineOf(cell: Cell, tr: CellMotionTransform, baseRel: Vec2): Vec2[] {
    const localPts = cell.membrane.outline();
    const c = Math.cos(cell.angle);
    const s = Math.sin(cell.angle);
    const maxR = Math.max(80, cell.radius * 3.0);
    const out: Vec2[] = [];
    for (let i = 0; i < localPts.length; i++) {
      let d = this.motionTracker.applyDeform(localPts[i], tr, cell.angle);
      const r = Math.hypot(d.x, d.y);
      if (!Number.isFinite(r) || r > maxR) {
        const fallbackA = (Math.PI * 2 * i) / Math.max(1, localPts.length);
        const safeR = Math.min(cell.radius, maxR);
        d = { x: Math.cos(fallbackA) * safeR, y: Math.sin(fallbackA) * safeR };
      }
      out.push({
        x: baseRel.x + d.x * c - d.y * s,
        y: baseRel.y + d.x * s + d.y * c,
      });
    }
    return out;
  }

  private localToRel(cell: Cell, local: Vec2, tr: CellMotionTransform, baseRel: Vec2): Vec2 {
    const d = this.motionTracker.applyDeform(local, tr, cell.angle);
    const c = Math.cos(cell.angle);
    const s = Math.sin(cell.angle);
    return {
      x: baseRel.x + d.x * c - d.y * s,
      y: baseRel.y + d.x * s + d.y * c,
    };
  }

  private drawCellWake(cell: Cell, sim: Simulation, baseRel: Vec2): void {
    const fluid = sim.fluid.sample(cell.position.x, cell.position.y);
    const relX = cell.velocity.x - fluid.x;
    const relY = cell.velocity.y - fluid.y;
    const speed = Math.hypot(relX, relY);
    if (speed < 4.0) return;

    const dirX = relX / speed;
    const dirY = relY / speed;
    const perpX = -dirY;
    const perpY = dirX;
    const ext = cell.extent();
    const len = clamp(speed * 1.15, 16, 72);
    const strength = clamp((speed - 4) / 55, 0.1, 0.34);

    for (const side of [-1, 1]) {
      const pts: Vec2[] = [];
      for (let i = 0; i < 8; i++) {
        const u = i / 7;
        const back = ext * 0.45 + u * len;
        const spread = ext * 0.65 + u * (14 + speed * 0.25);
        pts.push({
          x: baseRel.x - dirX * back + perpX * side * spread,
          y: baseRel.y - dirY * back + perpY * side * spread,
        });
      }
      this.vectorBatch.addPolyline(pts, 2.2, [0.8, 0.96, 1.0, strength], 2.0, false, true);
    }
  }

  private drawCellBodyAndExterior(
    cell: Cell,
    tr: CellMotionTransform,
    sim: Simulation,
    state: RenderFrameState,
    baseRel: Vec2,
    relOutline: Vec2[],
    cmds: LayerCmd[],
  ): void {
    const pal = lineagePalette(sim.seedValue, cell.lineageId(), sim.lineageColors.get(cell.lineageId()));
    const edgeRgb = parseHex(pal.edge);
    const gelRgb = parseHex(pal.gel);
    const bodyRgb = parseHex(pal.body);
    const rimRgb = parseHex(pal.rim);
    const shineRgb = parseHex(pal.shine);

    const flashMix = clamp(cell.hurtFlash * 0.65, 0, 0.75);
    const hurtRgb = { r: 1, g: 0.22, b: 0.28 };
    const reactMix = clamp(cell.reactionFlash * 0.55, 0, 0.6);
    const reactRgb = { r: 0.45, g: 1.0, b: 0.78 };

    const tintMix = (c: { r: number; g: number; b: number }) => {
      let r = mixRgb(c, hurtRgb, flashMix);
      r = mixRgb(r, reactRgb, reactMix);
      return r;
    };

    const gCol = tintMix(gelRgb);
    const bCol = tintMix(bodyRgb);
    const rCol = tintMix(rimRgb);
    const eCol = tintMix(edgeRgb);

    const isFocused = cell.id === state.focusCellId;
    const intero = state.interoception && isFocused;
    const fillAlpha = intero ? 0.52 : 0.88;

    // Step A: Exterior motility & surface organs under membrane rim
    const vStartA = this.vectorBatch.mark();
    const syn = cell.synergy();
    const lightDir = lightDirection(sim.seedValue, cell.position.x, cell.position.y);
    const cAng = cell.angle;
    const cosA = Math.cos(cAng);
    const sinA = Math.sin(cAng);

    if (syn === 'grazer' && relOutline.length >= 12) {
      const nOut = relOutline.length;
      const hairLen = clamp(cell.radius * 0.22, 6.5, 11.5);
      const hairCol = mixRgb(eCol, shineRgb, 0.48);
      for (let i = 0; i < nOut; i += 3) {
        const pPrev = relOutline[(i - 1 + nOut) % nOut];
        const pCur = relOutline[i];
        const pNext = relOutline[(i + 1) % nOut];
        const tx = pNext.x - pPrev.x;
        const ty = pNext.y - pPrev.y;
        const tLen = Math.hypot(tx, ty) || 1;
        let nx = ty / tLen;
        let ny = -tx / tLen;
        if ((pCur.x - baseRel.x) * nx + (pCur.y - baseRel.y) * ny < 0) {
          nx = -nx;
          ny = -ny;
        }
        const sweep = Math.sin(sim.time * 10.5 - i * 0.42 + cell.id * 1.1) * 0.32;
        const ca = Math.cos(sweep);
        const sa = Math.sin(sweep);
        const hx = nx * ca - ny * sa;
        const hy = nx * sa + ny * ca;
        this.vectorBatch.addPolyline(
          [
            { x: pCur.x - nx * 1.4, y: pCur.y - ny * 1.4 },
            { x: pCur.x + hx * hairLen, y: pCur.y + hy * hairLen },
          ],
          0.85,
          [hairCol.r, hairCol.g, hairCol.b, 0.78],
          1.2,
        );
      }
    }

    for (const organ of cell.organs) {
      if (isInternalOrgan(organ.kind)) continue;
      const baseLocal = cell.localPoint(organ.a);
      const baseRelPos = this.localToRel(cell, baseLocal, tr, baseRel);
      const ln = cell.localNormal(organ.a);
      const nx = ln.x * cosA - ln.y * sinA;
      const ny = ln.x * sinA + ln.y * cosA;
      const col = parseHex(ORGAN_COLORS[organ.kind]);
      const sc = organ.scale;
      const hpAlpha = organ.hp > 0 ? 1 : 0.3;

      if (organ.kind === 'propulsion') {
        const pts: Vec2[] = [];
        const segs = 12;
        const speed = Math.hypot(cell.velocity.x, cell.velocity.y);
        const freq = 10 + speed * 0.12;
        for (let i = 0; i <= segs; i++) {
          const u = i / segs;
          const back = u * (24 * sc);
          const wave = Math.sin(sim.time * freq - u * 4.5 + organ.id) * 5.2 * u * sc;
          pts.push({
            x: baseRelPos.x + nx * back - ny * wave,
            y: baseRelPos.y + ny * back + nx * wave,
          });
        }
        this.vectorBatch.addPolyline(pts, 2.2 * sc, [col.r, col.g, col.b, 0.92 * hpAlpha], 1.6, false, true);
      } else if (organ.kind === 'cilia') {
        for (let k = -2; k <= 2; k++) {
          const fan = k * 0.28 + Math.sin(sim.time * 13 + k * 0.9 + organ.id) * 0.24;
          const ca = Math.cos(fan);
          const sa = Math.sin(fan);
          const dx = nx * ca - ny * sa;
          const dy = nx * sa + ny * ca;
          this.vectorBatch.addPolyline(
            [baseRelPos, { x: baseRelPos.x + dx * 13 * sc, y: baseRelPos.y + dy * 13 * sc }],
            1.4,
            [col.r, col.g, col.b, 0.85 * hpAlpha],
            1.4,
          );
        }
      } else if (organ.kind === 'proboscis' && organ.hp > 0) {
        const tip = proboscisTip(cell, organ);
        const organWorld = cell.organPosition(organ);
        const tipDelta = offsetVec(organWorld, tip);
        const unwrappedTip = {
          x: baseRelPos.x + tipDelta.x,
          y: baseRelPos.y + tipDelta.y,
        };
        this.vectorBatch.addPolyline([baseRelPos, unwrappedTip], 1.8 * sc, [col.r, col.g, col.b, 0.88], 1.6);
        const hit = sim.proboscisContacts.find((pc) => pc.feederId === cell.id && pc.organId === organ.id);
        if (hit) {
          this.vectorBatch.addCircleFilled(unwrappedTip.x, unwrappedTip.y, 4.4, [1.0, 0.42, 0.65, 0.95], 12);
        }
      }
    }

    // Step B: 4-Ring explicit mesh dome shading from the real deformed outline
    const n = relOutline.length;
    const ringInner: Vec2[] = [];
    const ringMid: Vec2[] = [];
    const innerColors: [number, number, number, number][] = [];
    const midColors: [number, number, number, number][] = [];
    const outerColors: [number, number, number, number][] = [];
    const centerShift = {
      x: baseRel.x - lightDir.x * cell.radius * 0.22,
      y: baseRel.y - lightDir.y * cell.radius * 0.22,
    };

    for (let i = 0; i < n; i++) {
      const ow = relOutline[i];
      const dx = ow.x - baseRel.x;
      const dy = ow.y - baseRel.y;
      const len = Math.hypot(dx, dy) || 1;
      const nx = dx / len;
      const ny = dy / len;
      const lit = clamp(0.5 - 0.5 * (nx * lightDir.x + ny * lightDir.y), 0, 1);

      ringInner.push({
        x: centerShift.x + (ow.x - centerShift.x) * 0.52,
        y: centerShift.y + (ow.y - centerShift.y) * 0.52,
      });
      ringMid.push({
        x: baseRel.x + dx * 0.84,
        y: baseRel.y + dy * 0.84,
      });

      const midMix = mixRgb(bCol, shineRgb, lit * 0.32);
      const rimMix = mixRgb(gCol, rCol, 0.45 + 0.55 * lit);
      innerColors.push([bCol.r, bCol.g, bCol.b, fillAlpha]);
      midColors.push([midMix.r, midMix.g, midMix.b, fillAlpha * 0.96]);
      outerColors.push([rimMix.r, rimMix.g, rimMix.b, clamp(fillAlpha + 0.1, 0, 1)]);
    }

    this.vectorBatch.addStarPoly(centerShift, ringInner, [gCol.r, gCol.g, gCol.b, fillAlpha], innerColors[0]);
    this.vectorBatch.addRingBand(ringInner, ringMid, innerColors, midColors);
    this.vectorBatch.addRingBand(ringMid, relOutline, midColors, outerColors);

    // Synergy cellular signature
    if (syn === 'producer') {
      this.vectorBatch.addCircleFilled(baseRel.x, baseRel.y, cell.radius * 0.45, [0.35, 0.92, 0.55, 0.14], 20);
    } else if (syn === 'hunter') {
      this.vectorBatch.addCircleStroke(baseRel.x, baseRel.y, cell.radius * 0.72, 1.3, [1, 0.62, 0.25, 0.35], 24);
    } else if (syn === 'parasite') {
      this.vectorBatch.addCircleStroke(baseRel.x, baseRel.y, cell.radius * 0.76, 1.4, [0.95, 0.35, 0.62, 0.42], 24);
    }

    // Crisp outer membrane wall + inner highlight rim
    const hasWall = cell.organs.some((o) => o.kind === 'protection' && o.hp > 0);
    this.vectorBatch.addPolyline(
      relOutline,
      hasWall ? 2.6 : 1.7,
      [eCol.r, eCol.g, eCol.b, 0.95],
      1.6,
      true,
    );
    this.vectorBatch.addPolyline(
      ringMid,
      1.1,
      [shineRgb.r, shineRgb.g, shineRgb.b, intero ? 0.25 : 0.42],
      1.5,
      true,
    );

    // Merge candidate selection ring
    if (state.mergeSelecting && state.mergeCandidateIds.has(cell.id)) {
      const pulse = 0.6 + 0.4 * Math.sin(sim.time * 5);
      this.vectorBatch.addCircleStroke(baseRel.x, baseRel.y, cell.extent() + 9, 2.2, [0.4, 0.95, 0.85, pulse], 36);
    }

    // Microtubules (editing-only!)
    if (cell.id === state.editingCellId) {
      for (const organ of cell.organs) {
        const ow = this.localToRel(cell, cell.localPoint(organ.a), tr, baseRel);
        this.vectorBatch.addPolyline(
          [baseRel, ow],
          0.95,
          [shineRgb.r, shineRgb.g, shineRgb.b, 0.28],
          1.4,
        );
      }
    }

    // Surface complement tags, membrane pores & antitoxin shields
    for (const cpx of cell.surfaceComplexes) {
      const wp = this.localToRel(cell, cell.localPoint(cpx.a), tr, baseRel);
      if (cpx.capped) {
        this.vectorBatch.addCircleStroke(wp.x, wp.y, 5.2, 1.8, [0.3, 0.92, 0.82, 0.95], 12);
      } else if (cpx.units > 0) {
        this.vectorBatch.addCircleStroke(wp.x, wp.y, 5.2, 1.8, [0.92, 0.2, 0.48, 0.95], 12);
      } else if (cpx.tag > 0) {
        this.vectorBatch.addCircleFilled(wp.x, wp.y, 4.2, [1.0, 0.58, 0.22, 0.9], 10);
      }
    }

    // Exterior membrane socket cradles & scars (leave organelle glyphs unoccluded)
    for (const organ of cell.organs) {
      if (isInternalOrgan(organ.kind)) continue;
      const wp = this.localToRel(cell, cell.organLocalPosition(organ), tr, baseRel);
      const rad = 5.4 * organ.scale;
      this.vectorBatch.addCircleFilled(wp.x, wp.y, rad * 0.72, [eCol.r, eCol.g, eCol.b, 0.26], 14);
      if (organ.blocked > 0.05) {
        this.vectorBatch.addCircleStroke(wp.x, wp.y, rad + 3.4, 1.6, [1.0, 0.72, 0.24, organ.blocked], 14);
      }
      if (state.selectedOrganId === organ.id && cell.id === state.editingCellId) {
        this.vectorBatch.addCircleStroke(wp.x, wp.y, rad + 4.8, 1.9, [1, 1, 1, 0.92], 18);
      }
    }

    for (const scar of cell.lostOrgans) {
      const wp = this.localToRel(cell, cell.localPoint(scar.a), tr, baseRel);
      this.vectorBatch.addCircleStroke(wp.x, wp.y, 4.5, 1.3, [0.95, 0.55, 0.55, 0.65], 10);
    }

    const vecCmdA = this.vectorBatch.finishRange(vStartA, 'worldAlpha');
    if (vecCmdA) cmds.push({ kind: 'vec', cmd: vecCmdA });

    const toSpriteWorld = (relPt: Vec2): Vec2 => wrapPos({ x: state.camX + relPt.x, y: state.camY + relPt.y });

    // Step C: Organ sprite glyphs along perimeter + internal organs
    const sOrgStart = this.spriteBatch.mark();
    for (const organ of cell.organs) {
      const layer = ORGAN_LAYER_INDEX.get(organ.kind) ?? 0;
      const sw = toSpriteWorld(this.localToRel(cell, cell.organLocalPosition(organ), tr, baseRel));
      const hw = (isInternalOrgan(organ.kind) ? 8.4 : 7.8) * organ.scale;
      this.spriteBatch.push(sw.x, sw.y, hw, hw, cell.angle + organ.a, layer, [1, 1, 1, organ.hp > 0 ? 0.96 : 0.35]);
    }
    const sprOrgCmd = this.spriteBatch.finishRange(sOrgStart, 'organs');
    if (sprOrgCmd) cmds.push({ kind: 'spr', cmd: sprOrgCmd });

    // Step D: Cytoplasm vacuoles & gases (for focused cell / high detail view)
    if (isFocused) {
      const vacStart = this.spriteBatch.mark();
      for (const ip of cell.chemistry.particles) {
        if (!ip.alive) continue;
        const sw = toSpriteWorld(this.localToRel(cell, ip.p, tr, baseRel));
        const layer =
          ip.species === 'food'
            ? 0
            : ip.species === 'waste'
              ? 1
              : ip.species === 'oxygen'
                ? 2
                : 3;
        const r = vacuoleVisualRadius(ip.species, ip.amount, cell.radius);
        this.spriteBatch.push(sw.x, sw.y, r, r, ip.angle, layer, [1, 1, 1, intero ? 0.96 : 0.58]);
      }
      const vacCmd = this.spriteBatch.finishRange(vacStart, 'vacuoles');
      if (vacCmd) cmds.push({ kind: 'spr', cmd: vacCmd });
    }

    // Step E: Cytoplasm organelle landmarks (ER, Golgi, Centrosome, ATP crystals, Division bud) & Nucleus
    const landmarks = isFocused ? computeInteriorLandmarks(cell) : null;
    if (landmarks) {
      const compactScale = clamp(1 / Math.sqrt(Math.max(1, state.zoom / 1.5)), 0.35, 1.0);
      const lmSprStart = this.spriteBatch.mark();
      let lmIdx = 0;
      for (const lm of landmarks) {
        if (lm.kind === 'nucleus') continue;
        lmIdx++;
        const layer = LANDMARK_LAYER_INDEX.get(lm.kind);
        if (layer === undefined) continue;
        // Subtle cytoplasmic thermal sway clamped safely with local deformation
        const driftPhase = sim.time * 1.15 + cell.id * 0.7 + lmIdx * 1.9;
        const driftAmp = clamp(cell.radius * 0.025, 0.4, 1.3);
        const driftedLocal = {
          x: lm.local.x + Math.sin(driftPhase) * driftAmp,
          y: lm.local.y + Math.cos(driftPhase * 0.83) * driftAmp,
        };
        const sw = toSpriteWorld(this.localToRel(cell, driftedLocal, tr, baseRel));
        const hw = lm.radius * compactScale * 1.12;
        const starveTint: [number, number, number, number] =
          lm.kind === 'atp' && cell.energy < 10
            ? [1.0, 0.52, 0.42, 0.65 + 0.3 * Math.sin(sim.time * 8)]
            : [1.0, 1.0, 1.0, intero ? 0.9 : 0.66];
        const rot = cell.angle + Math.atan2(lm.local.y, lm.local.x) * 0.25 + Math.sin(driftPhase * 0.45) * 0.14;
        this.spriteBatch.push(sw.x, sw.y, hw, hw, rot, layer, starveTint);
      }
      const lmSprCmd = this.spriteBatch.finishRange(lmSprStart, 'landmarks');
      if (lmSprCmd) cmds.push({ kind: 'spr', cmd: lmSprCmd });
    }

    const nucForm = nucleusForm(sim.seedValue, cell.lineageId());
    const nucLm = landmarks?.find((l) => l.kind === 'nucleus');
    const nucLocal = nucLm
      ? {
          x: nucLm.local.x + Math.sin(sim.time * 0.9 + cell.id) * 0.65,
          y: nucLm.local.y + Math.cos(sim.time * 0.78 + cell.id) * 0.65,
        }
      : { x: 0, y: 0 };
    const nucSw = toSpriteWorld(this.localToRel(cell, nucLocal, tr, baseRel));
    const nucR = clamp(cell.radius * 0.25, 6.5, 13.5);
    const nucStart = this.spriteBatch.mark();
    const nucRgb = parseHex(pal.nucleus);
    this.spriteBatch.push(
      nucSw.x,
      nucSw.y,
      nucR,
      nucR,
      cell.angle + Math.sin(sim.time * 0.6 + cell.id) * 0.08,
      nucForm,
      [nucRgb.r, nucRgb.g, nucRgb.b, intero ? 0.95 : 0.88],
    );
    const nucCmd = this.spriteBatch.finishRange(nucStart, 'nuclei');
    if (nucCmd) cmds.push({ kind: 'spr', cmd: nucCmd });

    if (isFocused) {
      const lmVecStart = this.vectorBatch.mark();
      if (landmarks && cell.energy < 10) {
        const atpLm = landmarks.find((l) => l.kind === 'atp');
        if (atpLm) {
          const atpRel = this.localToRel(cell, atpLm.local, tr, baseRel);
          const pulse = 0.5 + 0.5 * Math.sin(sim.time * 8);
          this.vectorBatch.addCircleStroke(atpRel.x, atpRel.y, atpLm.radius * 1.15, 1.4, [1.0, 0.36, 0.32, pulse], 18);
        }
      }

      // Placement preview ghost when adding an organelle
      if (state.previewPlacement && cell.id === state.editingCellId) {
        const pv = state.previewPlacement;
        const ghostLocal = cell.localPoint(pv.angle);
        const ln = cell.localNormal(pv.angle);
        const dist = isInternalOrgan(pv.kind) ? 0.6 : 1.02;
        const wp = this.localToRel(
          cell,
          { x: ghostLocal.x * dist + ln.x * 4, y: ghostLocal.y * dist + ln.y * 4 },
          tr,
          baseRel,
        );
        const gCol = pv.valid ? [0.42, 0.98, 0.72, 0.85] : [1.0, 0.38, 0.42, 0.85];
        const ringR = 11 + Math.sin(sim.time * 6) * 2;
        this.vectorBatch.addCircleStroke(wp.x, wp.y, ringR, 1.8, gCol as [number, number, number, number], 20);
        this.vectorBatch.addCircleFilled(wp.x, wp.y, 6, gCol as [number, number, number, number], 16);
        void ORGAN_TITLES[pv.kind];
      }

      // Lower-left status badges
      const hasPore = cell.surfaceComplexes.some((s) => !s.capped && s.units > 0);
      if (cell.energy <= 0 || hasPore || cell.acidStress > 0.2) {
        const badgePos = { x: baseRel.x - cell.extent() * 0.78, y: baseRel.y + cell.extent() * 0.78 };
        if (cell.energy <= 0) {
          this.vectorBatch.addCircleFilled(badgePos.x, badgePos.y, 4.5, [1.0, 0.56, 0.2, 0.92], 12);
        }
        if (hasPore) {
          this.vectorBatch.addCircleFilled(badgePos.x + 11, badgePos.y, 4.5, [0.95, 0.25, 0.42, 0.92], 12);
        }
      }

      const lmVecCmd = this.vectorBatch.finishRange(lmVecStart, 'worldAlpha');
      if (lmVecCmd) cmds.push({ kind: 'vec', cmd: lmVecCmd });
    }
  }

  render(encoder: GPUCommandEncoder, sim: Simulation, state: RenderFrameState): void {
    const canvas = this.context.canvas as HTMLCanvasElement;
    this.ensureTargets(canvas.width, canvas.height);

    this.motionTracker.update(sim.cells, state.frameDt, state.paused);
    this.vectorBatch.beginFrame();
    this.spriteBatch.beginFrame();

    const camPos = { x: state.camX, y: state.camY };
    const focusCell = sim.cells.find((c) => c.id === state.focusCellId && !c.dead) ?? sim.player;

    this.updateUniforms(sim, state, focusCell.position);

    const effHalfW = (state.screenCssW / Math.max(0.1, state.zoom)) * 0.5 + 120;
    const effHalfH = (state.screenCssH / Math.max(0.1, state.zoom)) * 0.5 + 120;

    const foregroundIds = new Set<number>([focusCell.id]);
    if (state.mergeSelecting) {
      for (const id of state.mergeCandidateIds) foregroundIds.add(id);
    }

    const outlinesByCell = new Map<number, { tr: CellMotionTransform; baseRel: Vec2; outline: Vec2[] }>();
    for (const c of sim.cells) {
      if (c.dead) continue;
      const baseRel = offsetVec(camPos, c.position);
      if (!this.isRelVisible(baseRel, c.extent() + 160, state, effHalfW, effHalfH)) continue;
      const tr = this.motionTracker.transformFor(c);
      outlinesByCell.set(c.id, { tr, baseRel, outline: this.relOutlineOf(c, tr, baseRel) });
    }

    // =========================================================================
    // PASS A: Focus Mask (`r8unorm`) when interoception or merge selection active
    // =========================================================================
    let maskCmd: VectorDrawCmd | null = null;
    if (state.interoception || state.mergeSelecting) {
      const mStart = this.vectorBatch.mark();
      const white: [number, number, number, number] = [1, 1, 1, 1];
      const focusEntry = outlinesByCell.get(focusCell.id);
      if (!focusCell.dead && focusEntry) {
        this.vectorBatch.addStarPoly(focusEntry.baseRel, focusEntry.outline, white, white);
      }
      if (state.mergeSelecting) {
        for (const id of state.mergeCandidateIds) {
          const entry = outlinesByCell.get(id);
          if (entry) {
            this.vectorBatch.addStarPoly(entry.baseRel, entry.outline, white, white);
          }
        }
      }
      maskCmd = this.vectorBatch.finishRange(mStart, 'worldMask');
    }

    this.vectorBatch.uploadPending();
    if (maskCmd) {
      const passA = encoder.beginRenderPass({
        label: 'passA_focusMask',
        colorAttachments: [
          {
            view: this.focusMaskView,
            clearValue: { r: 0, g: 0, b: 0, a: 1 },
            loadOp: 'clear',
            storeOp: 'store',
          },
        ],
      });
      this.vectorBatch.encodeDraws(passA, this.vectorBG, [maskCmd], false);
      passA.end();
    }

    // =========================================================================
    // PASS B: World Exterior Scene (`sceneTex` mip 0)
    // =========================================================================
    const passBCmdsPreParticles: LayerCmd[] = [];
    const passBCmdsPostParticles: LayerCmd[] = [];

    const curves = buildFlowCurves(
      sim.seedValue,
      sim.time,
      sim.fluid,
      sim.induced,
      sim.habitatGeometry,
      camPos,
      effHalfW,
      effHalfH,
    );

    // B2: Ambient flow crests & downstream plant wakes
    const flowStart = this.vectorBatch.mark();
    for (const c of curves) {
      if (c.kind === 'gold') continue;
      this.vectorBatch.addPolyline(c.points, c.width * 0.5, [0.78, 0.95, 1.0, c.alpha], 1.6, false, true);
    }
    const flowPreCmd = this.vectorBatch.finishRange(flowStart, 'worldAlpha');
    if (flowPreCmd) passBCmdsPreParticles.push({ kind: 'vec', cmd: flowPreCmd });

    // B3: 10 Fractal Plant Colonies (wrapped relative to camera)
    const plantStart = this.spriteBatch.mark();
    const plantAlpha = state.interoception ? 0.35 : 0.92;
    for (const plant of sim.habitatGeometry.plants) {
      const rel = offsetVec(camPos, plant.p);
      if (!this.isRelVisible(rel, plant.radius * 1.6, state, effHalfW, effHalfH)) {
        continue;
      }
      const hw = plant.radius * 1.35;
      this.spriteBatch.push(plant.p.x, plant.p.y, hw, hw, plant.angle, plant.form % 8, [1, 1, 1, plantAlpha]);
    }
    const plantCmd = this.spriteBatch.finishRange(plantStart, 'plants');
    if (plantCmd) passBCmdsPreParticles.push({ kind: 'spr', cmd: plantCmd });

    // B4: Gold Eddy Streams above plants
    const goldStart = this.vectorBatch.mark();
    for (const c of curves) {
      if (c.kind !== 'gold') continue;
      this.vectorBatch.addPolyline(c.points, c.width * 0.55, [1.0, 0.86, 0.45, c.alpha], 1.6, false, true);
    }
    const goldCmd = this.vectorBatch.finishRange(goldStart, 'worldAlpha');
    if (goldCmd) passBCmdsPreParticles.push({ kind: 'vec', cmd: goldCmd });

    // B6: ALL Cell Wakes strictly below ALL cell bodies (visible cells only)
    const wakeStart = this.vectorBatch.mark();
    for (const c of sim.cells) {
      if (c.dead) continue;
      const entry = outlinesByCell.get(c.id);
      if (!entry) continue;
      this.drawCellWake(c, sim, entry.baseRel);
    }
    const wakeCmd = this.vectorBatch.finishRange(wakeStart, 'worldAlpha');
    if (wakeCmd) passBCmdsPostParticles.push({ kind: 'vec', cmd: wakeCmd });

    // B7: Non-focused exterior cells (visible cells only)
    for (const c of sim.cells) {
      if (c.dead || foregroundIds.has(c.id)) continue;
      const entry = outlinesByCell.get(c.id);
      if (!entry) continue;
      this.drawCellBodyAndExterior(c, entry.tr, sim, state, entry.baseRel, entry.outline, passBCmdsPostParticles);
    }

    this.vectorBatch.uploadPending();
    this.spriteBatch.uploadPending();

    const passB = encoder.beginRenderPass({
      label: 'passB_scene',
      colorAttachments: [
        {
          view: this.sceneMipViews[0],
          clearValue: { r: 0.02, g: 0.08, b: 0.12, a: 1 },
          loadOp: 'clear',
          storeOp: 'store',
        },
      ],
    });

    // B1: Water + caustics + pH watercolor
    passB.setPipeline(this.waterPipe);
    passB.setBindGroup(0, this.waterBG);
    passB.draw(3, 1, 0, 0);

    // B2-B4: Flow curves, fractal plants, gold eddies
    for (const cmd of passBCmdsPreParticles) {
      if (cmd.kind === 'vec') this.vectorBatch.encodeDraws(passB, this.vectorBG, [cmd.cmd], false);
      else this.spriteBatch.encodeDraws(passB, this.spriteBGs, [cmd.cmd], false);
    }

    // B5: GPU Instanced Particles (all 32,768 slots straight from GPU)
    passB.setPipeline(this.particlesPipe);
    passB.setBindGroup(0, state.simpleParticles ? this.particlesSimpleBG : this.particlesDetailedBG);
    passB.draw(6, sim.useGpuParticles ? 32768 : 0, 0, 0);

    // B6-B7: All cell wakes & non-focused cells
    for (const cmd of passBCmdsPostParticles) {
      if (cmd.kind === 'vec') this.vectorBatch.encodeDraws(passB, this.vectorBG, [cmd.cmd], false);
      else this.spriteBatch.encodeDraws(passB, this.spriteBGs, [cmd.cmd], false);
    }
    passB.end();

    // =========================================================================
    // PASS C: Mipmap Downsample (`sceneTex` mip 0 -> 1 -> 2 -> 3 -> 4)
    // =========================================================================
    for (let mip = 0; mip < 4; mip++) {
      const dsPass = encoder.beginRenderPass({
        label: `passC_ds${mip}`,
        colorAttachments: [
          {
            view: this.sceneMipViews[mip + 1],
            loadOp: 'clear',
            storeOp: 'store',
            clearValue: { r: 0, g: 0, b: 0, a: 1 },
          },
        ],
      });
      dsPass.setPipeline(this.downsamplePipe);
      dsPass.setBindGroup(0, this.downsampleBGs[mip]);
      dsPass.draw(3, 1, 0, 0);
      dsPass.end();
    }

    // =========================================================================
    // PASS D & E: Microscope Composite + Crisp Foreground Overlay on Swapchain
    // =========================================================================
    const fgCmds: LayerCmd[] = [];

    // Focused cell & merge candidates (frustum-culled cleanly too!)
    for (const c of sim.cells) {
      if (c.dead || !foregroundIds.has(c.id)) continue;
      const entry = outlinesByCell.get(c.id);
      if (!entry) continue;
      this.drawCellBodyAndExterior(c, entry.tr, sim, state, entry.baseRel, entry.outline, fgCmds);
    }

    // Audio pitch waves & death/merge bursts (camera-relative)
    const fxStart = this.vectorBatch.mark();
    for (const wave of state.audioWaves) {
      const rel = offsetVec(camPos, wave);
      if (!this.isRelVisible(rel, wave.radius + 20, state, effHalfW, effHalfH)) continue;
      const wc = pitchWaveColor(wave.semitones);
      this.vectorBatch.addCircleStroke(rel.x, rel.y, wave.radius, 1.4, [wc[0], wc[1], wc[2], wave.alpha], 36);
    }
    for (const burst of sim.deathBursts) {
      const age = sim.time - burst.time;
      if (age < 0 || age > 1.8) continue;
      const rel = offsetVec(camPos, burst.at);
      if (!this.isRelVisible(rel, burst.radius * 2.5, state, effHalfW, effHalfH)) continue;
      const t = age / 1.8;
      const col = hexToRgba(lineagePalette(sim.seedValue, burst.lineage, sim.lineageColors.get(burst.lineage)).rim, 1 - t);
      this.vectorBatch.addCircleStroke(rel.x, rel.y, burst.radius * (0.6 + t * 1.4), 2.5 * (1 - t), col, 32);
    }
    for (const mb of sim.mergeBursts) {
      const age = sim.time - mb.time;
      if (age < 0 || age > 1.2) continue;
      const t = age / 1.2;
      const fromRel = offsetVec(camPos, mb.at);
      const delta = offsetVec(mb.at, mb.to);
      const ease = 1 - (1 - t) * (1 - t);
      const curRel = { x: fromRel.x + delta.x * ease, y: fromRel.y + delta.y * ease };
      if (!this.isRelVisible(curRel, mb.donorRadius + 20, state, effHalfW, effHalfH)) continue;
      const linCol = hexToRgba(
        lineagePalette(sim.seedValue, mb.donorLineage, sim.lineageColors.get(mb.donorLineage)).rim,
        (1 - t) * 0.72,
      );
      this.vectorBatch.addCircleFilled(curRel.x, curRel.y, mb.donorRadius * (1 - 0.5 * t), linCol, 20);
    }
    const fxCmd = this.vectorBatch.finishRange(fxStart, 'worldAlpha');
    if (fxCmd) fgCmds.push({ kind: 'vec', cmd: fxCmd });

    // Additive 4-point reaction sparks (0.24s window, camera-relative)
    const spStart = this.vectorBatch.mark();
    for (const spark of sim.reactionSparks) {
      const age = sim.time - spark.time;
      if (age < 0 || age > 0.24) continue;
      const rel = offsetVec(camPos, spark.at);
      if (!this.isRelVisible(rel, 24, state, effHalfW, effHalfH)) continue;
      const t = age / 0.24;
      const r = 10.5 * Math.sin(t * Math.PI);
      this.vectorBatch.addSpark4Pt(rel.x, rel.y, r, spark.serial * 0.7 + t * 1.2, [1.0, 0.94, 0.65, 1 - t]);
    }
    const spCmd = this.vectorBatch.finishRange(spStart, 'worldAdd');
    if (spCmd) fgCmds.push({ kind: 'vec', cmd: spCmd });

    // Magnified inspector glyph + lens bezel in screen space
    if (state.inspector.active && state.inspector.radiusPx > 4) {
      const lx = state.inspector.screenX * state.dpr;
      const ly = state.inspector.screenY * state.dpr;
      const lr = state.inspector.radiusPx * state.dpr;

      if (sim.lastInspected?.valid && (!state.interoception || sim.lastInspected.kind === SPECIES.PHEROMONE)) {
        const ins = sim.lastInspected;
        const dx = offsetVec({ x: state.camX, y: state.camY }, { x: ins.x, y: ins.y });
        const cr = Math.cos(-state.rotation);
        const sr = Math.sin(-state.rotation);
        const effZoom = state.zoom * state.dpr;
        const pxX = this.rtWidth * 0.5 + (dx.x * cr - dx.y * sr) * effZoom;
        const pxY = this.rtHeight * 0.5 + (dx.x * sr + dx.y * cr) * effZoom;
        const magX = lx + (pxX - lx) * 3.5;
        const magY = ly + (pxY - ly) * 3.5;
        const baseRad = ins.kind < SPECIES_RADII.length ? particleRadius(ins.kind, ins.amount) : 4.0;
        const sprR = Math.max(8, baseRad * effZoom * 3.5 * 1.45);
        const isSprStart = this.spriteBatch.mark();
        let tint: [number, number, number, number] = [1, 1, 1, 0.95];
        if (ins.kind === SPECIES.PHEROMONE) {
          const hex = signalColorForLineage(sim.seedValue, ins.lineage, sim.lineageColors.get(ins.lineage));
          const rgb = parseHex(hex);
          tint = [rgb.r, rgb.g, rgb.b, 0.8];
        }
        this.spriteBatch.push(magX, magY, sprR, sprR, ins.angle - state.rotation, ins.kind, tint, true, true);
        const isSprCmd = this.spriteBatch.finishRange(isSprStart, state.simpleParticles ? 'speciesSimple' : 'speciesDetailed');
        if (isSprCmd) fgCmds.push({ kind: 'spr', cmd: isSprCmd });
      }

      const bezelStart = this.vectorBatch.mark();
      this.vectorBatch.addCircleStroke(lx, ly, lr, 2.2 * state.dpr, [0.76, 0.94, 1.0, 0.85], 48);
      this.vectorBatch.addCircleStroke(lx, ly, lr - 4 * state.dpr, 1.0 * state.dpr, [0.1, 0.25, 0.34, 0.5], 48);
      const bezelCmd = this.vectorBatch.finishRange(bezelStart, 'screenAlpha');
      if (bezelCmd) fgCmds.push({ kind: 'vec', cmd: bezelCmd });
    }

    this.vectorBatch.uploadPending();
    this.spriteBatch.uploadPending();

    const swapView = this.context.getCurrentTexture().createView();
    const passFinal = encoder.beginRenderPass({
      label: 'passDE_microscopeAndForeground',
      colorAttachments: [
        {
          view: swapView,
          clearValue: { r: 0.01, g: 0.03, b: 0.06, a: 1 },
          loadOp: 'clear',
          storeOp: 'store',
        },
      ],
    });

    passFinal.setPipeline(this.microscopePipe);
    passFinal.setBindGroup(0, this.microscopeBG);
    passFinal.draw(3, 1, 0, 0);

    for (const cmd of fgCmds) {
      if (cmd.kind === 'vec') this.vectorBatch.encodeDraws(passFinal, this.vectorBG, [cmd.cmd], true);
      else this.spriteBatch.encodeDraws(passFinal, this.spriteBGs, [cmd.cmd], true);
    }

    passFinal.end();
  }
}
