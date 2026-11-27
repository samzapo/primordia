import renderCommonWgsl from './shaders/renderCommon.wgsl?raw';
import vectorWgsl from './shaders/vector.wgsl?raw';
import { TAU, type Vec2 } from '../sim/constants.ts';

export type VectorMode = 'worldAlpha' | 'worldAdd' | 'worldMask' | 'screenAlpha';

export interface VectorDrawCmd {
  start: number;
  count: number;
  mode: VectorMode;
}

const FLOATS_PER_VERT = 8; // x, y, r, g, b, a, edgeX, feather
const MAX_VERTS = 262144;

export class VectorBatch {
  private readonly device: GPUDevice;
  private readonly vBuffer: GPUBuffer;
  private readonly data = new Float32Array(MAX_VERTS * FLOATS_PER_VERT);
  private vertCursor = 0;
  private uploadCursor = 0;

  readonly bindGroupLayout: GPUBindGroupLayout;
  private readonly worldAlphaPipe: GPURenderPipeline;
  private readonly worldAddPipe: GPURenderPipeline;
  private readonly worldMaskPipe: GPURenderPipeline;
  private readonly screenAlphaPipe: GPURenderPipeline;

  constructor(device: GPUDevice, presentationFormat: GPUTextureFormat) {
    this.device = device;
    this.vBuffer = device.createBuffer({
      label: 'vectorVertices',
      size: MAX_VERTS * FLOATS_PER_VERT * 4,
      usage: GPUBufferUsage.VERTEX | GPUBufferUsage.COPY_DST,
    });

    this.bindGroupLayout = device.createBindGroupLayout({
      label: 'vectorBGL',
      entries: [
        { binding: 0, visibility: GPUShaderStage.VERTEX | GPUShaderStage.FRAGMENT, buffer: { type: 'uniform' } },
      ],
    });
    const layout = device.createPipelineLayout({ bindGroupLayouts: [this.bindGroupLayout] });
    const module = device.createShaderModule({ code: `${renderCommonWgsl}\n${vectorWgsl}` });

    const buffers: GPUVertexBufferLayout[] = [
      {
        arrayStride: FLOATS_PER_VERT * 4,
        stepMode: 'vertex',
        attributes: [
          { shaderLocation: 0, offset: 0, format: 'float32x2' },
          { shaderLocation: 1, offset: 8, format: 'float32x4' },
          { shaderLocation: 2, offset: 24, format: 'float32x2' },
        ],
      },
    ];

    const alphaBlend: GPUBlendState = {
      color: { srcFactor: 'src-alpha', dstFactor: 'one-minus-src-alpha', operation: 'add' },
      alpha: { srcFactor: 'one', dstFactor: 'one-minus-src-alpha', operation: 'add' },
    };
    const addBlend: GPUBlendState = {
      color: { srcFactor: 'src-alpha', dstFactor: 'one', operation: 'add' },
      alpha: { srcFactor: 'one', dstFactor: 'one', operation: 'add' },
    };

    this.worldAlphaPipe = device.createRenderPipeline({
      label: 'vecWorldAlpha_rgba8',
      layout,
      vertex: { module, entryPoint: 'vsWorld', buffers },
      fragment: { module, entryPoint: 'fsColor', targets: [{ format: 'rgba8unorm', blend: alphaBlend }] },
      primitive: { topology: 'triangle-list' },
    });

    this.worldAddPipe = device.createRenderPipeline({
      label: 'vecWorldAdd_swap',
      layout,
      vertex: { module, entryPoint: 'vsWorld', buffers },
      fragment: { module, entryPoint: 'fsColor', targets: [{ format: presentationFormat, blend: addBlend }] },
      primitive: { topology: 'triangle-list' },
    });

    this.worldMaskPipe = device.createRenderPipeline({
      label: 'vecWorldMask_r8',
      layout,
      vertex: { module, entryPoint: 'vsWorld', buffers },
      fragment: { module, entryPoint: 'fsMask', targets: [{ format: 'r8unorm' }] },
      primitive: { topology: 'triangle-list' },
    });

    this.screenAlphaPipe = device.createRenderPipeline({
      label: 'vecScreenAlpha_swap',
      layout,
      vertex: { module, entryPoint: 'vsScreen', buffers },
      fragment: { module, entryPoint: 'fsColor', targets: [{ format: presentationFormat, blend: alphaBlend }] },
      primitive: { topology: 'triangle-list' },
    });

    this.worldAlphaSwapPipe = device.createRenderPipeline({
      label: 'vecWorldAlpha_swap',
      layout,
      vertex: { module, entryPoint: 'vsWorld', buffers },
      fragment: { module, entryPoint: 'fsColor', targets: [{ format: presentationFormat, blend: alphaBlend }] },
      primitive: { topology: 'triangle-list' },
    });
  }

  private readonly worldAlphaSwapPipe: GPURenderPipeline;

  beginFrame(): void {
    this.vertCursor = 0;
    this.uploadCursor = 0;
  }

  mark(): number {
    return this.vertCursor;
  }

  finishRange(start: number, mode: VectorMode): VectorDrawCmd | null {
    const count = this.vertCursor - start;
    if (count <= 0) return null;
    return { start, count, mode };
  }

  uploadPending(): void {
    if (this.vertCursor <= this.uploadCursor) return;
    const countFloats = (this.vertCursor - this.uploadCursor) * FLOATS_PER_VERT;
    const byteOff = this.uploadCursor * FLOATS_PER_VERT * 4;
    this.device.queue.writeBuffer(
      this.vBuffer,
      byteOff,
      this.data,
      this.uploadCursor * FLOATS_PER_VERT,
      countFloats,
    );
    this.uploadCursor = this.vertCursor;
  }

  encodeDraws(
    pass: GPURenderPassEncoder,
    bindGroup: GPUBindGroup,
    cmds: VectorDrawCmd[],
    targetIsSwapchain: boolean,
  ): void {
    if (cmds.length === 0) return;
    pass.setVertexBuffer(0, this.vBuffer);
    pass.setBindGroup(0, bindGroup);
    let lastPipe: GPURenderPipeline | null = null;

    for (const cmd of cmds) {
      let pipe: GPURenderPipeline;
      if (cmd.mode === 'worldMask') pipe = this.worldMaskPipe;
      else if (cmd.mode === 'worldAdd') pipe = this.worldAddPipe;
      else if (cmd.mode === 'screenAlpha') pipe = this.screenAlphaPipe;
      else pipe = targetIsSwapchain ? this.worldAlphaSwapPipe : this.worldAlphaPipe;

      if (pipe !== lastPipe) {
        pass.setPipeline(pipe);
        lastPipe = pipe;
      }
      pass.draw(cmd.count, 1, cmd.start, 0);
    }
  }

  private pushVert(
    x: number,
    y: number,
    r: number,
    g: number,
    b: number,
    a: number,
    edgeX = 0,
    feather = 0,
  ): void {
    if (this.vertCursor >= MAX_VERTS) return;
    const o = this.vertCursor * FLOATS_PER_VERT;
    this.data[o + 0] = x;
    this.data[o + 1] = y;
    this.data[o + 2] = r;
    this.data[o + 3] = g;
    this.data[o + 4] = b;
    this.data[o + 5] = a;
    this.data[o + 6] = edgeX;
    this.data[o + 7] = feather;
    this.vertCursor++;
  }

  addTriangle(
    ax: number,
    ay: number,
    ac: [number, number, number, number],
    bx: number,
    by: number,
    bc: [number, number, number, number],
    cx: number,
    cy: number,
    cc: [number, number, number, number],
  ): void {
    if (this.vertCursor + 3 > MAX_VERTS) return;
    this.pushVert(ax, ay, ac[0], ac[1], ac[2], ac[3]);
    this.pushVert(bx, by, bc[0], bc[1], bc[2], bc[3]);
    this.pushVert(cx, cy, cc[0], cc[1], cc[2], cc[3]);
  }

  addStarPoly(
    center: Vec2,
    ringPts: Vec2[],
    centerColor: [number, number, number, number],
    edgeColor: [number, number, number, number],
  ): void {
    const n = ringPts.length;
    if (n < 3) return;
    for (let i = 0; i < n; i++) {
      const a = ringPts[i];
      const b = ringPts[(i + 1) % n];
      this.addTriangle(center.x, center.y, centerColor, a.x, a.y, edgeColor, b.x, b.y, edgeColor);
    }
  }

  addRingBand(
    innerPts: Vec2[],
    outerPts: Vec2[],
    innerColors: [number, number, number, number][],
    outerColors: [number, number, number, number][],
  ): void {
    const n = innerPts.length;
    if (n < 3 || outerPts.length !== n) return;
    for (let i = 0; i < n; i++) {
      const ni = (i + 1) % n;
      const i0 = innerPts[i];
      const i1 = innerPts[ni];
      const o0 = outerPts[i];
      const o1 = outerPts[ni];
      const ic0 = innerColors[i];
      const ic1 = innerColors[ni];
      const oc0 = outerColors[i];
      const oc1 = outerColors[ni];
      this.addTriangle(i0.x, i0.y, ic0, o0.x, o0.y, oc0, o1.x, o1.y, oc1);
      this.addTriangle(i0.x, i0.y, ic0, o1.x, o1.y, oc1, i1.x, i1.y, ic1);
    }
  }

  addPolyline(
    points: Vec2[],
    halfWidth: number,
    rgba: [number, number, number, number],
    feather = 1.8,
    closed = false,
    taperEnds = false,
  ): void {
    const n = points.length;
    if (n < 2) return;
    const segCount = closed ? n : n - 1;
    const r = rgba[0];
    const g = rgba[1];
    const b = rgba[2];
    const a = rgba[3];

    for (let i = 0; i < segCount; i++) {
      const p0 = points[i];
      const p1 = points[(i + 1) % n];
      const dx = p1.x - p0.x;
      const dy = p1.y - p0.y;
      const len = Math.hypot(dx, dy);
      if (len < 1e-4) continue;
      const nx = -dy / len;
      const ny = dx / len;

      const t0 = taperEnds ? Math.sin(((i + 0.0) / segCount) * Math.PI) : 1;
      const t1 = taperEnds ? Math.sin(((i + 1.0) / segCount) * Math.PI) : 1;
      const w0 = halfWidth * (0.25 + 0.75 * t0);
      const w1 = halfWidth * (0.25 + 0.75 * t1);

      const ax = p0.x + nx * w0;
      const ay = p0.y + ny * w0;
      const bx = p0.x - nx * w0;
      const by = p0.y - ny * w0;
      const cx = p1.x + nx * w1;
      const cy = p1.y + ny * w1;
      const dxp = p1.x - nx * w1;
      const dyp = p1.y - ny * w1;

      if (this.vertCursor + 6 > MAX_VERTS) return;
      this.pushVert(ax, ay, r, g, b, a, 1, feather);
      this.pushVert(bx, by, r, g, b, a, -1, feather);
      this.pushVert(cx, cy, r, g, b, a, 1, feather);

      this.pushVert(bx, by, r, g, b, a, -1, feather);
      this.pushVert(dxp, dyp, r, g, b, a, -1, feather);
      this.pushVert(cx, cy, r, g, b, a, 1, feather);
    }
  }

  addCircleFilled(
    cx: number,
    cy: number,
    radius: number,
    rgba: [number, number, number, number],
    segments = 24,
  ): void {
    const pts: Vec2[] = [];
    for (let i = 0; i < segments; i++) {
      const a = (TAU * i) / segments;
      pts.push({ x: cx + Math.cos(a) * radius, y: cy + Math.sin(a) * radius });
    }
    this.addStarPoly({ x: cx, y: cy }, pts, rgba, rgba);
  }

  addCircleStroke(
    cx: number,
    cy: number,
    radius: number,
    halfWidth: number,
    rgba: [number, number, number, number],
    segments = 28,
    feather = 1.8,
  ): void {
    const pts: Vec2[] = [];
    for (let i = 0; i < segments; i++) {
      const a = (TAU * i) / segments;
      pts.push({ x: cx + Math.cos(a) * radius, y: cy + Math.sin(a) * radius });
    }
    this.addPolyline(pts, halfWidth, rgba, feather, true, false);
  }

  addArc(
    cx: number,
    cy: number,
    radius: number,
    startAng: number,
    endAng: number,
    halfWidth: number,
    rgba: [number, number, number, number],
    segments = 16,
    feather = 1.8,
  ): void {
    const pts: Vec2[] = [];
    for (let i = 0; i <= segments; i++) {
      const a = startAng + ((endAng - startAng) * i) / segments;
      pts.push({ x: cx + Math.cos(a) * radius, y: cy + Math.sin(a) * radius });
    }
    this.addPolyline(pts, halfWidth, rgba, feather, false, false);
  }

  addSpark4Pt(
    cx: number,
    cy: number,
    radius: number,
    angle: number,
    rgba: [number, number, number, number],
  ): void {
    const core = radius * 0.22;
    const pts: Vec2[] = [];
    for (let i = 0; i < 8; i++) {
      const a = angle + (TAU * i) / 8;
      const r = i % 2 === 0 ? radius : core;
      pts.push({ x: cx + Math.cos(a) * r, y: cy + Math.sin(a) * r });
    }
    this.addStarPoly({ x: cx, y: cy }, pts, [1, 1, 1, rgba[3]], [rgba[0], rgba[1], rgba[2], 0]);
  }
}
