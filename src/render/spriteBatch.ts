import renderCommonWgsl from './shaders/renderCommon.wgsl?raw';
import spriteWgsl from './shaders/sprite.wgsl?raw';

export interface SpriteDrawCmd {
  start: number;
  count: number;
  atlasKey: 'plants' | 'organs' | 'nuclei' | 'landmarks' | 'vacuoles' | 'speciesDetailed' | 'speciesSimple';
}

const FLOATS_PER_INST = 12; // x, y, halfW, halfH, angle, layer, isScreen, lensClip, r, g, b, a
const MAX_INSTS = 8192;

export class SpriteBatch {
  private readonly device: GPUDevice;
  private readonly iBuffer: GPUBuffer;
  private readonly data = new Float32Array(MAX_INSTS * FLOATS_PER_INST);
  private instCursor = 0;
  private uploadCursor = 0;

  readonly bindGroupLayout: GPUBindGroupLayout;
  private readonly rgba8Pipe: GPURenderPipeline;
  private readonly swapPipe: GPURenderPipeline;

  constructor(device: GPUDevice, presentationFormat: GPUTextureFormat) {
    this.device = device;
    this.iBuffer = device.createBuffer({
      label: 'spriteInstances',
      size: MAX_INSTS * FLOATS_PER_INST * 4,
      usage: GPUBufferUsage.VERTEX | GPUBufferUsage.COPY_DST,
    });

    this.bindGroupLayout = device.createBindGroupLayout({
      label: 'spriteBGL',
      entries: [
        { binding: 0, visibility: GPUShaderStage.VERTEX | GPUShaderStage.FRAGMENT, buffer: { type: 'uniform' } },
        { binding: 1, visibility: GPUShaderStage.FRAGMENT, texture: { sampleType: 'float', viewDimension: '2d-array' } },
        { binding: 2, visibility: GPUShaderStage.FRAGMENT, sampler: { type: 'filtering' } },
      ],
    });
    const layout = device.createPipelineLayout({ bindGroupLayouts: [this.bindGroupLayout] });
    const module = device.createShaderModule({ code: `${renderCommonWgsl}\n${spriteWgsl}` });

    const buffers: GPUVertexBufferLayout[] = [
      {
        arrayStride: FLOATS_PER_INST * 4,
        stepMode: 'instance',
        attributes: [
          { shaderLocation: 0, offset: 0, format: 'float32x4' },
          { shaderLocation: 1, offset: 16, format: 'float32x4' },
          { shaderLocation: 2, offset: 32, format: 'float32x4' },
        ],
      },
    ];

    const blend: GPUBlendState = {
      color: { srcFactor: 'src-alpha', dstFactor: 'one-minus-src-alpha', operation: 'add' },
      alpha: { srcFactor: 'one', dstFactor: 'one-minus-src-alpha', operation: 'add' },
    };

    this.rgba8Pipe = device.createRenderPipeline({
      label: 'sprite_rgba8',
      layout,
      vertex: { module, entryPoint: 'vsMain', buffers },
      fragment: { module, entryPoint: 'fsMain', targets: [{ format: 'rgba8unorm', blend }] },
      primitive: { topology: 'triangle-list' },
    });

    this.swapPipe = device.createRenderPipeline({
      label: 'sprite_swap',
      layout,
      vertex: { module, entryPoint: 'vsMain', buffers },
      fragment: { module, entryPoint: 'fsMain', targets: [{ format: presentationFormat, blend }] },
      primitive: { topology: 'triangle-list' },
    });
  }

  beginFrame(): void {
    this.instCursor = 0;
    this.uploadCursor = 0;
  }

  mark(): number {
    return this.instCursor;
  }

  finishRange(start: number, atlasKey: SpriteDrawCmd['atlasKey']): SpriteDrawCmd | null {
    const count = this.instCursor - start;
    if (count <= 0) return null;
    return { start, count, atlasKey };
  }

  push(
    x: number,
    y: number,
    halfW: number,
    halfH: number,
    angle: number,
    layer: number,
    rgba: [number, number, number, number] = [1, 1, 1, 1],
    isScreen = false,
    lensClip = false,
  ): void {
    if (this.instCursor >= MAX_INSTS) return;
    const o = this.instCursor * FLOATS_PER_INST;
    this.data[o + 0] = x;
    this.data[o + 1] = y;
    this.data[o + 2] = halfW;
    this.data[o + 3] = halfH;
    this.data[o + 4] = angle;
    this.data[o + 5] = layer;
    this.data[o + 6] = isScreen ? 1 : 0;
    this.data[o + 7] = lensClip ? 1 : 0;
    this.data[o + 8] = rgba[0];
    this.data[o + 9] = rgba[1];
    this.data[o + 10] = rgba[2];
    this.data[o + 11] = rgba[3];
    this.instCursor++;
  }

  uploadPending(): void {
    if (this.instCursor <= this.uploadCursor) return;
    const countFloats = (this.instCursor - this.uploadCursor) * FLOATS_PER_INST;
    const byteOff = this.uploadCursor * FLOATS_PER_INST * 4;
    this.device.queue.writeBuffer(
      this.iBuffer,
      byteOff,
      this.data,
      this.uploadCursor * FLOATS_PER_INST,
      countFloats,
    );
    this.uploadCursor = this.instCursor;
  }

  encodeDraws(
    pass: GPURenderPassEncoder,
    bindGroups: Record<SpriteDrawCmd['atlasKey'], GPUBindGroup>,
    cmds: SpriteDrawCmd[],
    targetIsSwapchain: boolean,
  ): void {
    if (cmds.length === 0) return;
    pass.setPipeline(targetIsSwapchain ? this.swapPipe : this.rgba8Pipe);
    pass.setVertexBuffer(0, this.iBuffer);
    for (const cmd of cmds) {
      pass.setBindGroup(0, bindGroups[cmd.atlasKey]);
      pass.draw(6, cmd.count, 0, cmd.start);
    }
  }
}
