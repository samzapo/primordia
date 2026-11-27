import {
  SPECIES_DECAY,
  SPECIES_MATERIAL,
  SPECIES_RADII,
  particleDiameter,
} from '../sim/catalog.ts';
import { BIN_COUNT, FIELD_COUNT, MAX_LIVE_CELLS, SPECIES_COUNT } from '../sim/constants.ts';
import { MAX_ATTRACTORS, type Medium } from '../sim/medium.ts';
import {
  MAX_DECOYS_PER_TICK,
  MAX_EMISSIONS_PER_TICK,
  MAX_FEEDS_PER_TICK,
  MAX_HITS_PER_BODY,
  MAX_QUERIES_PER_TICK,
  type GpuReceipts,
  type GpuStepInput,
  type QueuedEmission,
} from '../sim/simulation.ts';
import {
  BODY_BYTES,
  BODY_FLOATS,
  DECOY_BYTES,
  DECOY_FLOATS,
  EMISSION_BYTES,
  EMISSION_FLOATS,
  FEED_BYTES,
  FEED_FLOATS,
  GPU_MAX_AMBIENT_SPAWNS,
  GPU_MAX_BODY_POINTS,
  GPU_MAX_PARTICLES,
  PARTICLE_BYTES,
  PARTICLE_FLOATS,
  QUERY_BYTES,
  QUERY_FLOATS,
  RECEIPT_ACID_OFFSET,
  RECEIPT_BYTES,
  RECEIPT_DECOY_OFFSET,
  RECEIPT_EXP_COUNT_OFFSET,
  RECEIPT_EXP_HIT_OFFSET,
  RECEIPT_FEED_OFFSET,
  RECEIPT_INSPECT_OFFSET,
  RECEIPT_QUERY_OFFSET,
  RECEIPT_SPARK_OFFSET,
  RECEIPT_STATS_OFFSET,
  REPORT_BYTES,
  REPORT_FLOATS,
  UNIFORM_BYTES,
  UNIFORM_FLOATS,
} from './types.ts';

import commonWgsl from './shaders/common.wgsl?raw';
import transportWgsl from './shaders/transport.wgsl?raw';
import gridCountWgsl from './shaders/gridCount.wgsl?raw';
import prefixSumWgsl from './shaders/prefixSum.wgsl?raw';
import gridScatterWgsl from './shaders/gridScatter.wgsl?raw';
import acidUnaryWgsl from './shaders/acidUnary.wgsl?raw';
import acidStepWgsl from './shaders/acidStep.wgsl?raw';
import decayUnaryWgsl from './shaders/decayUnary.wgsl?raw';
import overlapDegreeWgsl from './shaders/overlapDegree.wgsl?raw';
import voteImpulseWgsl from './shaders/voteImpulse.wgsl?raw';
import reactionCommitWgsl from './shaders/reactionCommit.wgsl?raw';
import ambientGasWgsl from './shaders/ambientGas.wgsl?raw';
import feedConsumeWgsl from './shaders/feedConsume.wgsl?raw';
import emitSpawnWgsl from './shaders/emitSpawn.wgsl?raw';
import perceptionWgsl from './shaders/perception.wgsl?raw';
import exposureNominateWgsl from './shaders/exposureNominate.wgsl?raw';
import exposureCollectWgsl from './shaders/exposureCollect.wgsl?raw';
import projectBodiesWgsl from './shaders/projectBodies.wgsl?raw';
import censusReduceWgsl from './shaders/censusReduce.wgsl?raw';

export class ParticleEngine {
  readonly device: GPUDevice;
  readonly maxParticles = GPU_MAX_PARTICLES;

  // Authoritative simulation buffers (also read directly by WebGPU render passes)
  readonly particlesBuffer: GPUBuffer;
  readonly reportsBuffer: GPUBuffer;
  readonly acidFieldBuffer: GPUBuffer;
  private readonly acidScratchBuffer: GPUBuffer;
  private readonly flowBuffer: GPUBuffer;
  private readonly uniformBuffer: GPUBuffer;

  // Spatial grid & interaction buffers
  private readonly binCountsBuffer: GPUBuffer;
  private readonly binOffsetsBuffer: GPUBuffer;
  private readonly blockTotalsBuffer: GPUBuffer;
  private readonly binCursorsBuffer: GPUBuffer;
  private readonly sortedSlotsBuffer: GPUBuffer;
  private readonly degreesBuffer: GPUBuffer;
  private readonly impulsesBuffer: GPUBuffer;
  private readonly votesBuffer: GPUBuffer;
  private readonly nominationsBuffer: GPUBuffer;

  // Per-tick CPU -> GPU batch buffers
  private readonly bodiesBuffer: GPUBuffer;
  private readonly bodyPointsBuffer: GPUBuffer;
  private readonly feedsBuffer: GPUBuffer;
  private readonly queriesBuffer: GPUBuffer;
  private readonly decoysBuffer: GPUBuffer;
  private readonly emissionsBuffer: GPUBuffer;
  private readonly ambientSpawnsBuffer: GPUBuffer;

  // Receipt & double-buffered async staging readback
  private readonly atomicStatsBuffer: GPUBuffer;
  private readonly receiptBuffer: GPUBuffer;
  private readonly stagingBuffers: [GPUBuffer, GPUBuffer];
  private stagingSlot = 0;
  private stagingReady: [GpuReceipts | null, GpuReceipts | null] = [null, null];
  private stagingInFlight: [boolean, boolean] = [false, false];
  private stagingRevision: [number, number] = [0, 0];
  private stagingCounts: [
    { feeds: number; queries: number; bodies: number; decoys: number },
    { feeds: number; queries: number; bodies: number; decoys: number },
  ] = [
    { feeds: 0, queries: 0, bodies: 0, decoys: 0 },
    { feeds: 0, queries: 0, bodies: 0, decoys: 0 },
  ];
  private pendingCopySlot = -1;

  // Scratch typed arrays for zero-GC uploads
  private readonly uniformF32 = new Float32Array(UNIFORM_FLOATS);
  private readonly flowF32 = new Float32Array((FIELD_COUNT + MAX_ATTRACTORS) * 4);
  private readonly bodyBuf = new ArrayBuffer(MAX_LIVE_CELLS * BODY_BYTES);
  private readonly bodyF32 = new Float32Array(this.bodyBuf);
  private readonly bodyU32 = new Uint32Array(this.bodyBuf);
  private readonly bodyPointsF32 = new Float32Array(GPU_MAX_BODY_POINTS * 2);
  private readonly feedBuf = new ArrayBuffer(MAX_FEEDS_PER_TICK * FEED_BYTES);
  private readonly feedF32 = new Float32Array(this.feedBuf);
  private readonly feedU32 = new Uint32Array(this.feedBuf);
  private readonly queryBuf = new ArrayBuffer(MAX_QUERIES_PER_TICK * QUERY_BYTES);
  private readonly queryF32 = new Float32Array(this.queryBuf);
  private readonly queryI32 = new Int32Array(this.queryBuf);
  private readonly queryU32 = new Uint32Array(this.queryBuf);
  private readonly decoyF32 = new Float32Array(MAX_DECOYS_PER_TICK * DECOY_FLOATS);
  private readonly emitBuf = new ArrayBuffer(MAX_EMISSIONS_PER_TICK * EMISSION_BYTES);
  private readonly emitF32 = new Float32Array(this.emitBuf);
  private readonly emitU32 = new Uint32Array(this.emitBuf);

  // Compute pipelines & bind groups
  private readonly transportPipe: GPUComputePipeline;
  private readonly gridCountPipe: GPUComputePipeline;
  private readonly reduceBlocksPipe: GPUComputePipeline;
  private readonly scanSpinePipe: GPUComputePipeline;
  private readonly addOffsetsPipe: GPUComputePipeline;
  private readonly gridScatterPipe: GPUComputePipeline;
  private readonly acidUnaryPipe: GPUComputePipeline;
  private readonly acidStepPipe: GPUComputePipeline;
  private readonly decayUnaryPipe: GPUComputePipeline;
  private readonly overlapDegreePipe: GPUComputePipeline;
  private readonly voteImpulsePipe: GPUComputePipeline;
  private readonly applyImpulsesPipe: GPUComputePipeline;
  private readonly commitPairsPipe: GPUComputePipeline;
  private readonly ambientGasPipe: GPUComputePipeline;
  private readonly feedConsumePipe: GPUComputePipeline;
  private readonly emitSpawnPipe: GPUComputePipeline;
  private readonly perceptionPipe: GPUComputePipeline;
  private readonly inspectPipe: GPUComputePipeline;
  private readonly exposureNominatePipe: GPUComputePipeline;
  private readonly exposureCollectPipe: GPUComputePipeline;
  private readonly projectBodiesPipe: GPUComputePipeline;
  private readonly censusReducePipe: GPUComputePipeline;

  private readonly transportBG: GPUBindGroup;
  private readonly gridCountBG: GPUBindGroup;
  private readonly prefixSumBG: GPUBindGroup;
  private readonly gridScatterBG: GPUBindGroup;
  private readonly acidUnaryBG: GPUBindGroup;
  private readonly acidStepBG: GPUBindGroup;
  private readonly decayUnaryBG: GPUBindGroup;
  private readonly overlapDegreeBG: GPUBindGroup;
  private readonly voteImpulseBG: GPUBindGroup;
  private readonly reactionCommitBG: GPUBindGroup;
  private readonly ambientGasBG: GPUBindGroup;
  private readonly feedConsumeBG: GPUBindGroup;
  private readonly emitSpawnBG: GPUBindGroup;
  private readonly perceptionBG: GPUBindGroup;
  private readonly exposureNominateBG: GPUBindGroup;
  private readonly exposureCollectBG: GPUBindGroup;
  private readonly projectBodiesBG: GPUBindGroup;
  private readonly censusReduceBG: GPUBindGroup;

  constructor(device: GPUDevice) {
    this.device = device;

    const RW = GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_SRC | GPUBufferUsage.COPY_DST;
    this.particlesBuffer = device.createBuffer({ size: GPU_MAX_PARTICLES * PARTICLE_BYTES, usage: RW, label: 'particles' });
    this.reportsBuffer = device.createBuffer({ size: GPU_MAX_PARTICLES * REPORT_BYTES, usage: RW, label: 'reports' });
    this.acidFieldBuffer = device.createBuffer({ size: FIELD_COUNT * 4, usage: RW, label: 'acidField' });
    this.acidScratchBuffer = device.createBuffer({ size: FIELD_COUNT * 4, usage: RW, label: 'acidScratch' });
    this.flowBuffer = device.createBuffer({ size: (FIELD_COUNT + MAX_ATTRACTORS) * 16, usage: RW, label: 'flow' });
    this.uniformBuffer = device.createBuffer({
      size: UNIFORM_BYTES,
      usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST,
      label: 'simUniforms',
    });

    this.binCountsBuffer = device.createBuffer({ size: BIN_COUNT * 4, usage: RW, label: 'binCounts' });
    this.binOffsetsBuffer = device.createBuffer({ size: (BIN_COUNT + 1) * 4, usage: RW, label: 'binOffsets' });
    this.blockTotalsBuffer = device.createBuffer({ size: 256 * 4, usage: RW, label: 'blockTotals' });
    this.binCursorsBuffer = device.createBuffer({ size: BIN_COUNT * 4, usage: RW, label: 'binCursors' });
    this.sortedSlotsBuffer = device.createBuffer({ size: GPU_MAX_PARTICLES * 4, usage: RW, label: 'sortedSlots' });
    this.degreesBuffer = device.createBuffer({ size: GPU_MAX_PARTICLES * 4, usage: RW, label: 'degrees' });
    this.impulsesBuffer = device.createBuffer({ size: GPU_MAX_PARTICLES * 16, usage: RW, label: 'impulses' });
    this.votesBuffer = device.createBuffer({ size: GPU_MAX_PARTICLES * 4, usage: RW, label: 'votes' });
    this.nominationsBuffer = device.createBuffer({ size: GPU_MAX_PARTICLES * 16, usage: RW, label: 'nominations' });

    this.bodiesBuffer = device.createBuffer({ size: MAX_LIVE_CELLS * BODY_BYTES, usage: RW, label: 'bodies' });
    this.bodyPointsBuffer = device.createBuffer({ size: GPU_MAX_BODY_POINTS * 8, usage: RW, label: 'bodyPoints' });
    this.feedsBuffer = device.createBuffer({ size: MAX_FEEDS_PER_TICK * FEED_BYTES, usage: RW, label: 'feeds' });
    this.queriesBuffer = device.createBuffer({ size: MAX_QUERIES_PER_TICK * QUERY_BYTES, usage: RW, label: 'queries' });
    this.decoysBuffer = device.createBuffer({ size: MAX_DECOYS_PER_TICK * DECOY_BYTES, usage: RW, label: 'decoys' });
    this.emissionsBuffer = device.createBuffer({ size: MAX_EMISSIONS_PER_TICK * EMISSION_BYTES, usage: RW, label: 'emissions' });
    this.ambientSpawnsBuffer = device.createBuffer({ size: GPU_MAX_AMBIENT_SPAWNS * EMISSION_BYTES, usage: RW, label: 'ambientSpawns' });

    this.atomicStatsBuffer = device.createBuffer({ size: 64, usage: RW, label: 'atomicStats' });
    this.receiptBuffer = device.createBuffer({ size: RECEIPT_BYTES, usage: RW, label: 'receipts' });
    this.stagingBuffers = [
      device.createBuffer({ size: RECEIPT_BYTES, usage: GPUBufferUsage.MAP_READ | GPUBufferUsage.COPY_DST, label: 'staging0' }),
      device.createBuffer({ size: RECEIPT_BYTES, usage: GPUBufferUsage.MAP_READ | GPUBufferUsage.COPY_DST, label: 'staging1' }),
    ];

    const makePipe = (wgsl: string, entryPoint = 'main', prefix = true): GPUComputePipeline => {
      const code = prefix ? `${commonWgsl}\n${wgsl}` : wgsl;
      const module = device.createShaderModule({ code });
      return device.createComputePipeline({ layout: 'auto', compute: { module, entryPoint } });
    };

    const prefixMod = device.createShaderModule({ code: prefixSumWgsl });
    const reactionMod = device.createShaderModule({ code: `${commonWgsl}\n${reactionCommitWgsl}` });
    const perceptionMod = device.createShaderModule({ code: `${commonWgsl}\n${perceptionWgsl}` });

    const prefixBGL = device.createBindGroupLayout({
      label: 'prefixSumBGL',
      entries: [
        { binding: 0, visibility: GPUShaderStage.COMPUTE, buffer: { type: 'read-only-storage' } },
        { binding: 1, visibility: GPUShaderStage.COMPUTE, buffer: { type: 'storage' } },
        { binding: 2, visibility: GPUShaderStage.COMPUTE, buffer: { type: 'storage' } },
      ],
    });
    const prefixLayout = device.createPipelineLayout({ bindGroupLayouts: [prefixBGL] });

    const reactionBGL = device.createBindGroupLayout({
      label: 'reactionCommitBGL',
      entries: [
        { binding: 0, visibility: GPUShaderStage.COMPUTE, buffer: { type: 'uniform' } },
        { binding: 1, visibility: GPUShaderStage.COMPUTE, buffer: { type: 'storage' } },
        { binding: 2, visibility: GPUShaderStage.COMPUTE, buffer: { type: 'read-only-storage' } },
        { binding: 3, visibility: GPUShaderStage.COMPUTE, buffer: { type: 'read-only-storage' } },
        { binding: 4, visibility: GPUShaderStage.COMPUTE, buffer: { type: 'read-only-storage' } },
        { binding: 5, visibility: GPUShaderStage.COMPUTE, buffer: { type: 'storage' } },
        { binding: 6, visibility: GPUShaderStage.COMPUTE, buffer: { type: 'storage' } },
      ],
    });
    const reactionLayout = device.createPipelineLayout({ bindGroupLayouts: [reactionBGL] });

    const perceptionBGL = device.createBindGroupLayout({
      label: 'perceptionBGL',
      entries: [
        { binding: 0, visibility: GPUShaderStage.COMPUTE, buffer: { type: 'uniform' } },
        { binding: 1, visibility: GPUShaderStage.COMPUTE, buffer: { type: 'read-only-storage' } },
        { binding: 2, visibility: GPUShaderStage.COMPUTE, buffer: { type: 'read-only-storage' } },
        { binding: 3, visibility: GPUShaderStage.COMPUTE, buffer: { type: 'read-only-storage' } },
        { binding: 4, visibility: GPUShaderStage.COMPUTE, buffer: { type: 'read-only-storage' } },
        { binding: 5, visibility: GPUShaderStage.COMPUTE, buffer: { type: 'read-only-storage' } },
        { binding: 6, visibility: GPUShaderStage.COMPUTE, buffer: { type: 'storage' } },
      ],
    });
    const perceptionLayout = device.createPipelineLayout({ bindGroupLayouts: [perceptionBGL] });

    this.transportPipe = makePipe(transportWgsl);
    this.gridCountPipe = makePipe(gridCountWgsl);
    this.reduceBlocksPipe = device.createComputePipeline({ layout: prefixLayout, compute: { module: prefixMod, entryPoint: 'reduceBlocks' } });
    this.scanSpinePipe = device.createComputePipeline({ layout: prefixLayout, compute: { module: prefixMod, entryPoint: 'scanSpine' } });
    this.addOffsetsPipe = device.createComputePipeline({ layout: prefixLayout, compute: { module: prefixMod, entryPoint: 'addOffsets' } });
    this.gridScatterPipe = makePipe(gridScatterWgsl);
    this.acidUnaryPipe = makePipe(acidUnaryWgsl);
    this.acidStepPipe = makePipe(acidStepWgsl);
    this.decayUnaryPipe = makePipe(decayUnaryWgsl);
    this.overlapDegreePipe = makePipe(overlapDegreeWgsl);
    this.voteImpulsePipe = makePipe(voteImpulseWgsl);
    this.applyImpulsesPipe = device.createComputePipeline({ layout: reactionLayout, compute: { module: reactionMod, entryPoint: 'applyImpulses' } });
    this.commitPairsPipe = device.createComputePipeline({ layout: reactionLayout, compute: { module: reactionMod, entryPoint: 'commitPairs' } });
    this.ambientGasPipe = makePipe(ambientGasWgsl);
    this.feedConsumePipe = makePipe(feedConsumeWgsl);
    this.emitSpawnPipe = makePipe(emitSpawnWgsl);
    this.perceptionPipe = device.createComputePipeline({ layout: perceptionLayout, compute: { module: perceptionMod, entryPoint: 'queryMain' } });
    this.inspectPipe = device.createComputePipeline({ layout: perceptionLayout, compute: { module: perceptionMod, entryPoint: 'inspectMain' } });
    this.exposureNominatePipe = makePipe(exposureNominateWgsl, 'nominateMain');
    this.exposureCollectPipe = makePipe(exposureCollectWgsl, 'collectMain');
    this.projectBodiesPipe = makePipe(projectBodiesWgsl);
    this.censusReducePipe = makePipe(censusReduceWgsl);

    const bg = (pipe: GPUComputePipeline, buffers: GPUBuffer[]): GPUBindGroup =>
      device.createBindGroup({
        layout: pipe.getBindGroupLayout(0),
        entries: buffers.map((buffer, binding) => ({ binding, resource: { buffer } })),
      });
    const bgWithLayout = (layout: GPUBindGroupLayout, buffers: GPUBuffer[]): GPUBindGroup =>
      device.createBindGroup({
        layout,
        entries: buffers.map((buffer, binding) => ({ binding, resource: { buffer } })),
      });

    this.transportBG = bg(this.transportPipe, [this.uniformBuffer, this.particlesBuffer, this.reportsBuffer, this.flowBuffer]);
    this.gridCountBG = bg(this.gridCountPipe, [this.uniformBuffer, this.particlesBuffer, this.binCountsBuffer]);
    this.prefixSumBG = bgWithLayout(prefixBGL, [this.binCountsBuffer, this.binOffsetsBuffer, this.blockTotalsBuffer]);
    this.gridScatterBG = bg(this.gridScatterPipe, [this.uniformBuffer, this.particlesBuffer, this.binOffsetsBuffer, this.binCursorsBuffer, this.sortedSlotsBuffer]);
    this.acidUnaryBG = bg(this.acidUnaryPipe, [this.uniformBuffer, this.particlesBuffer, this.binOffsetsBuffer, this.sortedSlotsBuffer, this.acidFieldBuffer]);
    this.acidStepBG = bg(this.acidStepPipe, [this.uniformBuffer, this.flowBuffer, this.acidFieldBuffer, this.acidScratchBuffer]);
    this.decayUnaryBG = bg(this.decayUnaryPipe, [this.uniformBuffer, this.particlesBuffer, this.atomicStatsBuffer]);
    this.overlapDegreeBG = bg(this.overlapDegreePipe, [this.uniformBuffer, this.particlesBuffer, this.binOffsetsBuffer, this.sortedSlotsBuffer, this.degreesBuffer]);
    this.voteImpulseBG = bg(this.voteImpulsePipe, [this.uniformBuffer, this.particlesBuffer, this.binOffsetsBuffer, this.sortedSlotsBuffer, this.degreesBuffer, this.acidFieldBuffer, this.impulsesBuffer, this.votesBuffer]);
    this.reactionCommitBG = bgWithLayout(reactionBGL, [this.uniformBuffer, this.particlesBuffer, this.acidFieldBuffer, this.impulsesBuffer, this.votesBuffer, this.receiptBuffer, this.atomicStatsBuffer]);
    this.ambientGasBG = bg(this.ambientGasPipe, [this.uniformBuffer, this.particlesBuffer, this.binOffsetsBuffer, this.sortedSlotsBuffer, this.flowBuffer, this.ambientSpawnsBuffer, this.atomicStatsBuffer]);
    this.feedConsumeBG = bg(this.feedConsumePipe, [this.uniformBuffer, this.particlesBuffer, this.binOffsetsBuffer, this.sortedSlotsBuffer, this.feedsBuffer, this.bodiesBuffer, this.receiptBuffer]);
    this.emitSpawnBG = bg(this.emitSpawnPipe, [this.uniformBuffer, this.particlesBuffer, this.reportsBuffer, this.emissionsBuffer, this.ambientSpawnsBuffer, this.atomicStatsBuffer]);
    this.perceptionBG = bgWithLayout(perceptionBGL, [this.uniformBuffer, this.particlesBuffer, this.reportsBuffer, this.binOffsetsBuffer, this.sortedSlotsBuffer, this.queriesBuffer, this.receiptBuffer]);
    this.exposureNominateBG = bg(this.exposureNominatePipe, [this.uniformBuffer, this.particlesBuffer, this.bodiesBuffer, this.bodyPointsBuffer, this.decoysBuffer, this.nominationsBuffer]);
    this.exposureCollectBG = bg(this.exposureCollectPipe, [this.uniformBuffer, this.particlesBuffer, this.bodiesBuffer, this.binOffsetsBuffer, this.sortedSlotsBuffer, this.nominationsBuffer, this.receiptBuffer]);
    this.projectBodiesBG = bg(this.projectBodiesPipe, [this.uniformBuffer, this.particlesBuffer, this.bodiesBuffer, this.bodyPointsBuffer]);
    this.censusReduceBG = bg(this.censusReducePipe, [this.uniformBuffer, this.particlesBuffer, this.acidFieldBuffer, this.atomicStatsBuffer, this.receiptBuffer]);

    // Initialize constant species arrays in uniformF32
    for (let s = 0; s < SPECIES_COUNT; s++) {
      this.uniformF32[20 + s] = SPECIES_RADII[s];
      this.uniformF32[48 + s] = SPECIES_DECAY[s];
      this.uniformF32[76 + s] = SPECIES_MATERIAL[s];
    }
  }

  seedInitialParticles(emissions: QueuedEmission[], medium: Medium): void {
    const pBuf = new ArrayBuffer(GPU_MAX_PARTICLES * PARTICLE_BYTES);
    const pF32 = new Float32Array(pBuf);
    const pU32 = new Uint32Array(pBuf);
    const rBuf = new ArrayBuffer(GPU_MAX_PARTICLES * REPORT_BYTES);
    const rF32 = new Float32Array(rBuf);
    const rU32 = new Uint32Array(rBuf);

    for (let i = 0; i < GPU_MAX_PARTICLES; i++) {
      pF32[i * PARTICLE_FLOATS + 7] = -1.0; // dead sentinel
    }

    const count = Math.min(GPU_MAX_PARTICLES, emissions.length);
    for (let i = 0; i < count; i++) {
      const e = emissions[i];
      const b = i * PARTICLE_FLOATS;
      pF32[b + 0] = e.x;
      pF32[b + 1] = e.y;
      pF32[b + 2] = e.angle;
      pF32[b + 3] = e.spin;
      pF32[b + 4] = e.vx;
      pF32[b + 5] = e.vy;
      pF32[b + 6] = 0;
      pF32[b + 7] = e.kind;
      pF32[b + 8] = particleDiameter(e.kind, e.amount);
      pF32[b + 9] = e.amount;
      pF32[b + 10] = e.capacity;
      pF32[b + 11] = 0;
      pU32[b + 12] = 1; // generation
      pU32[b + 13] = e.owner >>> 0;
      pU32[b + 14] = e.lineage >>> 0;
      pU32[b + 15] = 0;

      if (e.report) {
        const rb = i * REPORT_FLOATS;
        rF32[rb + 0] = e.report.at.x;
        rF32[rb + 1] = e.report.at.y;
        rF32[rb + 2] = e.report.mass;
        rF32[rb + 3] = e.report.radius;
        rU32[rb + 4] = e.report.id >>> 0;
        rU32[rb + 5] = e.report.lineage >>> 0;
        rU32[rb + 6] = e.report.hostile ? 1 : 0;
        rU32[rb + 7] = e.report.defended ? 1 : 0;
        rF32[rb + 8] = e.report.emittedAt;
        rF32[rb + 9] = e.expiresAt;
        rF32[rb + 10] = 1.0;
        rF32[rb + 11] = i;
      }
    }

    this.device.queue.writeBuffer(this.particlesBuffer, 0, pBuf);
    this.device.queue.writeBuffer(this.reportsBuffer, 0, rBuf);
    this.device.queue.writeBuffer(this.acidFieldBuffer, 0, new Float32Array(FIELD_COUNT));
    this.uploadFlow(medium);

    this.stagingReady = [null, null];
    this.stagingCounts = [
      { feeds: 0, queries: 0, bodies: 0, decoys: 0 },
      { feeds: 0, queries: 0, bodies: 0, decoys: 0 },
    ];
  }

  private uploadFlow(medium: Medium): void {
    for (let i = 0; i < FIELD_COUNT; i++) {
      this.flowF32[i * 4 + 0] = medium.velocity[i * 2];
      this.flowF32[i * 4 + 1] = medium.velocity[i * 2 + 1];
      this.flowF32[i * 4 + 2] = 0;
      this.flowF32[i * 4 + 3] = 0;
    }
    const mouthCount = Math.min(MAX_ATTRACTORS, medium.attractorCount);
    for (let m = 0; m < mouthCount; m++) {
      const dst = (FIELD_COUNT + m) * 4;
      const src = m * 4;
      this.flowF32[dst + 0] = medium.attractors[src + 0];
      this.flowF32[dst + 1] = medium.attractors[src + 1];
      this.flowF32[dst + 2] = medium.attractors[src + 2];
      this.flowF32[dst + 3] = medium.attractors[src + 3];
    }
    this.device.queue.writeBuffer(this.flowBuffer, 0, this.flowF32, 0, (FIELD_COUNT + mouthCount) * 4);
  }

  pollReceipts(): GpuReceipts | null {
    for (let i = 0; i < 2; i++) {
      const ready = this.stagingReady[i];
      if (ready) {
        this.stagingReady[i] = null;
        return ready;
      }
    }
    return null;
  }

  encodeInspectOnly(
    encoder: GPUCommandEncoder,
    inspectCursor: GpuStepInput['inspectCursor'],
    time: number,
  ): void {
    this.uniformF32[1] = time;
    this.uniformF32[4] = GPU_MAX_PARTICLES;
    this.uniformF32[13] = inspectCursor.active ? 1.0 : 0.0;
    this.uniformF32[14] = inspectCursor.x;
    this.uniformF32[15] = inspectCursor.y;
    this.uniformF32[16] = inspectCursor.maxRadius;
    this.uniformF32[17] = inspectCursor.trackedSlot;
    this.uniformF32[18] = Math.max(0, inspectCursor.trackedGen);
    this.device.queue.writeBuffer(this.uniformBuffer, 0, this.uniformF32);

    const pass = encoder.beginComputePass();
    pass.setPipeline(this.inspectPipe);
    pass.setBindGroup(0, this.perceptionBG);
    pass.dispatchWorkgroups(1, 1, 1);
    pass.end();

    const slot = this.stagingSlot;
    if (!this.stagingInFlight[slot]) {
      encoder.copyBufferToBuffer(this.receiptBuffer, 0, this.stagingBuffers[slot], 0, RECEIPT_BYTES);
      this.pendingCopySlot = slot;
      this.stagingRevision[slot] = -1;
      this.stagingCounts[slot] = { feeds: 0, queries: 0, bodies: 0, decoys: 0 };
      this.stagingSlot = 1 - slot;
    } else {
      this.pendingCopySlot = -1;
    }
  }

  encodeTick(encoder: GPUCommandEncoder, input: GpuStepInput, medium: Medium): void {
    this.uploadFlow(medium);

    const bodyCount = Math.min(MAX_LIVE_CELLS, input.bodies.length);
    const feedCount = Math.min(MAX_FEEDS_PER_TICK, input.feeds.length);
    const emitCount = Math.min(MAX_EMISSIONS_PER_TICK, input.emissions.length);
    const queryCount = Math.min(MAX_QUERIES_PER_TICK, input.queries.length);
    const decoyCount = Math.min(MAX_DECOYS_PER_TICK, input.decoys.length);
    const mouthCount = Math.min(MAX_ATTRACTORS, medium.attractorCount);

    // Pack uniforms
    this.uniformF32[0] = input.dt;
    this.uniformF32[1] = input.time;
    this.uniformF32[2] = input.revision;
    this.uniformF32[3] = (input.seedValue >>> 0) & 0xffffff;
    this.uniformF32[4] = GPU_MAX_PARTICLES;
    this.uniformF32[5] = bodyCount;
    this.uniformF32[6] = feedCount;
    this.uniformF32[7] = emitCount;
    this.uniformF32[8] = queryCount;
    this.uniformF32[9] = decoyCount;
    this.uniformF32[10] = input.ambientGasGroup;
    this.uniformF32[11] = input.ambientGasElapsed;
    this.uniformF32[12] = input.stepAcidityField ? 1.0 : 0.0;
    this.uniformF32[13] = input.inspectCursor.active ? 1.0 : 0.0;
    this.uniformF32[14] = input.inspectCursor.x;
    this.uniformF32[15] = input.inspectCursor.y;
    this.uniformF32[16] = input.inspectCursor.maxRadius;
    this.uniformF32[17] = input.inspectCursor.trackedSlot;
    this.uniformF32[18] = Math.max(0, input.inspectCursor.trackedGen);
    this.uniformF32[19] = mouthCount;
    this.device.queue.writeBuffer(this.uniformBuffer, 0, this.uniformF32);

    // Pack bodies & points
    let ptCursor = 0;
    for (let b = 0; b < bodyCount; b++) {
      const desc = input.bodies[b];
      const visStart = ptCursor;
      const visCount = Math.min(desc.visualOutline.length, GPU_MAX_BODY_POINTS - ptCursor);
      for (let k = 0; k < visCount; k++) {
        this.bodyPointsF32[(ptCursor + k) * 2 + 0] = desc.visualOutline[k].x;
        this.bodyPointsF32[(ptCursor + k) * 2 + 1] = desc.visualOutline[k].y;
      }
      ptCursor += visCount;
      const physStart = ptCursor;
      const physCount = Math.min(desc.physicalPoints.length, GPU_MAX_BODY_POINTS - ptCursor);
      for (let k = 0; k < physCount; k++) {
        this.bodyPointsF32[(ptCursor + k) * 2 + 0] = desc.physicalPoints[k].x;
        this.bodyPointsF32[(ptCursor + k) * 2 + 1] = desc.physicalPoints[k].y;
      }
      ptCursor += physCount;

      const off = b * BODY_FLOATS;
      this.bodyF32[off + 0] = desc.cell.position.x;
      this.bodyF32[off + 1] = desc.cell.position.y;
      this.bodyF32[off + 2] = desc.cell.angle;
      this.bodyF32[off + 3] = desc.cell.extent();
      this.bodyU32[off + 4] = visStart;
      this.bodyU32[off + 5] = visCount;
      this.bodyU32[off + 6] = physStart;
      this.bodyU32[off + 7] = physCount;
      this.bodyF32[off + 8] = desc.gutRoom;
      this.bodyF32[off + 9] = desc.oxygenRoom;
      this.bodyF32[off + 10] = desc.carbonRoom;
      this.bodyF32[off + 11] = desc.cell.id;
      this.bodyU32[off + 12] = desc.cell.id >>> 0;
      this.bodyU32[off + 13] = desc.cell.lineageId() >>> 0;
      this.bodyU32[off + 14] = desc.hasSurfaceComplexes ? 1 : 0;
      this.bodyU32[off + 15] = desc.cell.unattendedProtected ? 1 : 0;
    }
    if (bodyCount > 0) {
      this.device.queue.writeBuffer(this.bodiesBuffer, 0, this.bodyBuf, 0, bodyCount * BODY_BYTES);
    }
    if (ptCursor > 0) {
      this.device.queue.writeBuffer(this.bodyPointsBuffer, 0, this.bodyPointsF32, 0, ptCursor * 2);
    }

    // Pack feeds
    for (let f = 0; f < feedCount; f++) {
      const fd = input.feeds[f];
      const off = f * FEED_FLOATS;
      this.feedF32[off + 0] = fd.centerX;
      this.feedF32[off + 1] = fd.centerY;
      this.feedF32[off + 2] = fd.reach;
      this.feedF32[off + 3] = fd.capacity;
      this.feedU32[off + 4] = fd.kind === 'mouth' ? 0 : fd.kind === 'oxygen' ? 1 : 2;
      this.feedU32[off + 5] = fd.bodyIndex >>> 0;
      this.feedU32[off + 6] = fd.organId >>> 0;
      this.feedU32[off + 7] = fd.cellId >>> 0;
    }
    if (feedCount > 0) {
      this.device.queue.writeBuffer(this.feedsBuffer, 0, this.feedBuf, 0, feedCount * FEED_BYTES);
    }

    // Pack queries
    for (let q = 0; q < queryCount; q++) {
      const qd = input.queries[q];
      const off = q * QUERY_FLOATS;
      this.queryF32[off + 0] = qd.atX;
      this.queryF32[off + 1] = qd.atY;
      this.queryF32[off + 2] = qd.reach;
      this.queryF32[off + 3] = qd.mass;
      this.queryI32[off + 4] = qd.cellId | 0;
      this.queryI32[off + 5] = qd.lineage | 0;
      this.queryI32[off + 6] = qd.targetId | 0;
      this.queryI32[off + 7] = qd.mode | 0;
      this.queryU32[off + 8] = qd.incumbent >>> 0;
      this.queryU32[off + 9] = qd.organId >>> 0;
      this.queryU32[off + 10] = qd.cellIndex >>> 0;
      this.queryU32[off + 11] = qd.isCounterAttack ? 1 : 0;
    }
    if (queryCount > 0) {
      this.device.queue.writeBuffer(this.queriesBuffer, 0, this.queryBuf, 0, queryCount * QUERY_BYTES);
    }

    // Pack decoys
    for (let d = 0; d < decoyCount; d++) {
      const dd = input.decoys[d];
      const off = d * DECOY_FLOATS;
      this.decoyF32[off + 0] = dd.atX;
      this.decoyF32[off + 1] = dd.atY;
      this.decoyF32[off + 2] = dd.normX;
      this.decoyF32[off + 3] = dd.normY;
      this.decoyF32[off + 4] = dd.reach;
      this.decoyF32[off + 5] = dd.bodyIndex;
      this.decoyF32[off + 6] = dd.organId;
      this.decoyF32[off + 7] = 0;
    }
    if (decoyCount > 0) {
      this.device.queue.writeBuffer(this.decoysBuffer, 0, this.decoyF32, 0, decoyCount * DECOY_BYTES);
    }

    // Pack emissions
    for (let e = 0; e < emitCount; e++) {
      const em = input.emissions[e];
      const off = e * EMISSION_FLOATS;
      this.emitF32[off + 0] = em.x;
      this.emitF32[off + 1] = em.y;
      this.emitF32[off + 2] = em.angle;
      this.emitF32[off + 3] = em.spin;
      this.emitF32[off + 4] = em.vx;
      this.emitF32[off + 5] = em.vy;
      this.emitF32[off + 6] = em.kind;
      this.emitF32[off + 7] = em.expiresAt;
      this.emitF32[off + 8] = particleDiameter(em.kind, em.amount);
      this.emitF32[off + 9] = em.amount;
      this.emitF32[off + 10] = em.capacity;
      this.emitF32[off + 11] = 0;
      this.emitU32[off + 12] = em.owner >>> 0;
      this.emitU32[off + 13] = em.lineage >>> 0;
      this.emitU32[off + 14] = em.report ? 1 : 0;
      this.emitU32[off + 15] = 0;
      if (em.report) {
        this.emitF32[off + 16] = em.report.at.x;
        this.emitF32[off + 17] = em.report.at.y;
        this.emitF32[off + 18] = em.report.mass;
        this.emitF32[off + 19] = em.report.radius;
        this.emitU32[off + 20] = em.report.id >>> 0;
        this.emitU32[off + 21] = em.report.lineage >>> 0;
        this.emitU32[off + 22] = em.report.hostile ? 1 : 0;
        this.emitU32[off + 23] = em.report.defended ? 1 : 0;
        this.emitF32[off + 24] = em.report.emittedAt;
        this.emitF32[off + 25] = em.expiresAt;
        this.emitF32[off + 26] = 1.0;
        this.emitF32[off + 27] = 0;
      }
    }
    if (emitCount > 0) {
      this.device.queue.writeBuffer(this.emissionsBuffer, 0, this.emitBuf, 0, emitCount * EMISSION_BYTES);
    }

    // Clear counters before compute passes
    encoder.clearBuffer(this.atomicStatsBuffer, 0, 64);
    encoder.clearBuffer(this.receiptBuffer, RECEIPT_EXP_COUNT_OFFSET * 4, 64 * 4 * 4);
    encoder.clearBuffer(this.receiptBuffer, RECEIPT_DECOY_OFFSET * 4, MAX_DECOYS_PER_TICK * 4);

    const pGroups = Math.ceil(GPU_MAX_PARTICLES / 128);
    const fieldGroups = Math.ceil(FIELD_COUNT / 128);

    const runPass = (pipe: GPUComputePipeline, bg: GPUBindGroup, x: number, y = 1, z = 1): void => {
      if (x <= 0) return;
      const pass = encoder.beginComputePass();
      pass.setPipeline(pipe);
      pass.setBindGroup(0, bg);
      pass.dispatchWorkgroups(x, y, z);
      pass.end();
    };

    const rebuildGrid = (): void => {
      encoder.clearBuffer(this.binCountsBuffer, 0, BIN_COUNT * 4);
      encoder.clearBuffer(this.binCursorsBuffer, 0, BIN_COUNT * 4);
      runPass(this.gridCountPipe, this.gridCountBG, pGroups);
      runPass(this.reduceBlocksPipe, this.prefixSumBG, 160);
      runPass(this.scanSpinePipe, this.prefixSumBG, 1);
      runPass(this.addOffsetsPipe, this.prefixSumBG, 160);
      runPass(this.gridScatterPipe, this.gridScatterBG, pGroups);
    };

    // 1. Transport & Pheromone expiry
    runPass(this.transportPipe, this.transportBG, pGroups);

    // 2. Spatial Grid #1
    rebuildGrid();

    // 3. Unary Acidity exchange + 6-tick field PDE + Stochastic Decay
    runPass(this.acidUnaryPipe, this.acidUnaryBG, fieldGroups);
    if (input.stepAcidityField) {
      runPass(this.acidStepPipe, this.acidStepBG, fieldGroups);
      encoder.copyBufferToBuffer(this.acidScratchBuffer, 0, this.acidFieldBuffer, 0, FIELD_COUNT * 4);
    }
    runPass(this.decayUnaryPipe, this.decayUnaryBG, pGroups);

    // 4. Pair Collisions & Mutual-Vote Reactions
    runPass(this.overlapDegreePipe, this.overlapDegreeBG, pGroups);
    runPass(this.voteImpulsePipe, this.voteImpulseBG, pGroups);
    runPass(this.applyImpulsesPipe, this.reactionCommitBG, pGroups);
    runPass(this.commitPairsPipe, this.reactionCommitBG, pGroups);

    // 5. Ambient CO2 / O2 surface exchange
    if (input.ambientGasGroup >= 0) {
      runPass(this.ambientGasPipe, this.ambientGasBG, fieldGroups);
    }

    // 6. Ordered Feeding & New Emissions
    if (feedCount > 0) {
      runPass(this.feedConsumePipe, this.feedConsumeBG, 1);
    }
    runPass(this.emitSpawnPipe, this.emitSpawnBG, 1);

    // 7. Spatial Grid #2 (includes freshly emitted pheromones & combat projectiles)
    rebuildGrid();

    // 8. Perception & Inspection
    if (queryCount > 0) {
      runPass(this.perceptionPipe, this.perceptionBG, queryCount);
    }
    runPass(this.inspectPipe, this.perceptionBG, 1);

    // 9. Hazard & Decoy Exposure
    if (bodyCount > 0) {
      runPass(this.exposureNominatePipe, this.exposureNominateBG, pGroups);
      runPass(this.exposureCollectPipe, this.exposureCollectBG, bodyCount);
      runPass(this.projectBodiesPipe, this.projectBodiesBG, pGroups);
    }

    // 10. Census & Acid Readback Pack
    runPass(this.censusReducePipe, this.censusReduceBG, 1);

    // Copy to available staging buffer for non-blocking post-submit mapAsync
    const slot = this.stagingSlot;
    if (!this.stagingInFlight[slot]) {
      encoder.copyBufferToBuffer(this.receiptBuffer, 0, this.stagingBuffers[slot], 0, RECEIPT_BYTES);
      this.pendingCopySlot = slot;
      this.stagingRevision[slot] = input.revision;
      this.stagingCounts[slot] = {
        feeds: feedCount,
        queries: queryCount,
        bodies: bodyCount,
        decoys: decoyCount,
      };
      this.stagingSlot = 1 - slot;
    } else {
      this.pendingCopySlot = -1;
    }
  }

  afterSubmit(): void {
    const slot = this.pendingCopySlot;
    this.pendingCopySlot = -1;
    if (slot < 0 || this.stagingInFlight[slot]) return;

    this.stagingInFlight[slot] = true;
    const rev = this.stagingRevision[slot];
    const counts = { ...this.stagingCounts[slot] };
    const buf = this.stagingBuffers[slot];

    buf
      .mapAsync(GPUMapMode.READ)
      .then(() => {
        const range = buf.getMappedRange();
        const receipts = this.decodeReceipts(range, rev, counts.feeds, counts.queries, counts.bodies, counts.decoys);
        buf.unmap();
        this.stagingInFlight[slot] = false;
        this.stagingReady[slot] = receipts;
      })
      .catch((err) => {
        console.error('[ParticleEngine mapAsync]', err);
        this.stagingInFlight[slot] = false;
      });
  }

  private decodeReceipts(
    buffer: ArrayBuffer,
    revision: number,
    feedCount: number,
    queryCount: number,
    bodyCount: number,
    decoyCount: number,
  ): GpuReceipts {
    const f32 = new Float32Array(buffer);
    const u32 = new Uint32Array(buffer);
    const i32 = new Int32Array(buffer);

    const feedResults: GpuReceipts['feedResults'] = [];
    for (let i = 0; i < feedCount; i++) {
      const o = RECEIPT_FEED_OFFSET + i * 4;
      feedResults.push({
        taken: f32[o],
        fuel: f32[o + 1],
        momentX: f32[o + 2],
        momentY: f32[o + 3],
      });
    }

    const queryResults: GpuReceipts['queryResults'] = [];
    for (let i = 0; i < queryCount; i++) {
      const o = RECEIPT_QUERY_OFFSET + i * 12;
      const flags = Math.round(f32[o + 11]);
      queryResults.push({
        found: f32[o] > 0.5,
        atX: f32[o + 1],
        atY: f32[o + 2],
        score: f32[o + 3],
        dist: f32[o + 4],
        reportId: i32[o + 5],
        lineage: i32[o + 6],
        emittedAt: f32[o + 7],
        expiresAt: f32[o + 8],
        mass: f32[o + 9],
        radius: f32[o + 10],
        hostile: (flags & 1) !== 0,
        defended: (flags & 2) !== 0,
      });
    }

    const exposureHits: GpuReceipts['exposureHits'] = [];
    for (let b = 0; b < bodyCount; b++) {
      const hitCount = Math.min(MAX_HITS_PER_BODY, u32[RECEIPT_EXP_COUNT_OFFSET + b * 4]);
      for (let h = 0; h < hitCount; h++) {
        const o = RECEIPT_EXP_HIT_OFFSET + (b * MAX_HITS_PER_BODY + h) * 4;
        exposureHits.push({
          bodyIndex: b,
          amount: f32[o],
          angle: f32[o + 1],
          kind: u32[o + 2],
          owner: i32[o + 3],
        });
      }
    }

    const decoyHits: number[] = [];
    for (let d = 0; d < decoyCount; d++) {
      decoyHits.push(u32[RECEIPT_DECOY_OFFSET + d]);
    }

    const sparkCount = Math.min(128, u32[RECEIPT_STATS_OFFSET + 8]);
    const reactionSparks: GpuReceipts['reactionSparks'] = [];
    for (let s = 0; s < sparkCount; s++) {
      const o = RECEIPT_SPARK_OFFSET + s * 4;
      reactionSparks.push({ x: f32[o], y: f32[o + 1], cue: f32[o + 2] });
    }

    let inspected: GpuReceipts['inspected'] = null;
    if (f32[RECEIPT_INSPECT_OFFSET] > 0.5) {
      const o = RECEIPT_INSPECT_OFFSET;
      const kind = Math.round(f32[o + 3]);
      const repId = i32[o + 16];
      const repFlags = Math.round(f32[o + 19]);
      const report =
        kind === 3 && repId >= 0
          ? {
              id: repId,
              lineage: i32[o + 17],
              at: { x: f32[o + 12], y: f32[o + 13] },
              mass: f32[o + 14],
              radius: f32[o + 15],
              hostile: (repFlags & 1) !== 0,
              defended: (repFlags & 2) !== 0,
              emittedAt: f32[o + 18],
            }
          : null;
      inspected = {
        valid: true,
        slot: u32[o + 1],
        gen: u32[o + 2],
        kind,
        x: f32[o + 4],
        y: f32[o + 5],
        angle: f32[o + 6],
        amount: f32[o + 7],
        capacity: f32[o + 8],
        owner: i32[o + 9],
        lineage: i32[o + 10],
        expiresAt: f32[o + 11],
        report,
      };
    }

    const statsBase = RECEIPT_STATS_OFFSET;
    const census = {
      alive: u32[statsBase + 0],
      pheromones: u32[statsBase + 1],
      material: u32[statsBase + 2],
      oxygen: u32[statsBase + 3],
      decays: u32[statsBase + 4],
      materialLoss: f32[statsBase + 5],
      recycled: f32[statsBase + 6],
      reactions: u32[statsBase + 7],
    };

    const acidField = new Float32Array(FIELD_COUNT);
    acidField.set(f32.subarray(RECEIPT_ACID_OFFSET, RECEIPT_ACID_OFFSET + FIELD_COUNT));

    const bodyIntakes = new Array(bodyCount).fill(null).map(() => ({ food: 0, oxygen: 0, carbon: 0 }));

    return {
      revision,
      bodyIntakes,
      feedResults,
      queryResults,
      exposureHits,
      decoyHits,
      reactionSparks,
      census,
      inspected,
      acidField,
    };
  }
}
