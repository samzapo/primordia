import { FIELD_COUNT, MAX_PARTICLES } from '../sim/constants.ts';
import {
  MAX_DECOYS_PER_TICK,
  MAX_FEEDS_PER_TICK,
  MAX_HITS_PER_BODY,
  MAX_QUERIES_PER_TICK,
  MAX_REACTION_SPARKS,
} from '../sim/simulation.ts';

export const PARTICLE_FLOATS = 16; // 64 bytes (4 x vec4)
export const PARTICLE_BYTES = PARTICLE_FLOATS * 4;

export const REPORT_FLOATS = 12; // 48 bytes (3 x vec4)
export const REPORT_BYTES = REPORT_FLOATS * 4;

export const BODY_FLOATS = 20; // 80 bytes (5 x vec4)
export const BODY_BYTES = BODY_FLOATS * 4;

export const BODY_IMPACT_SECTORS = 14;
export const BODY_IMPACT_STRIDE = 16; // 14 sectors + recoilX + recoilY
export const BODY_IMPACTS_LEN = 64 * BODY_IMPACT_STRIDE; // 1024 ints (4096 bytes)

export const FEED_FLOATS = 8; // 32 bytes (2 x vec4)
export const FEED_BYTES = FEED_FLOATS * 4;

export const QUERY_FLOATS = 12; // 48 bytes (3 x vec4)
export const QUERY_BYTES = QUERY_FLOATS * 4;

export const DECOY_FLOATS = 8; // 32 bytes (2 x vec4)
export const DECOY_BYTES = DECOY_FLOATS * 4;

export const EMISSION_FLOATS = 28; // 112 bytes (7 x vec4)
export const EMISSION_BYTES = EMISSION_FLOATS * 4;

export const UNIFORM_FLOATS = 104; // 26 x vec4 = 416 bytes
export const UNIFORM_BYTES = UNIFORM_FLOATS * 4;

export const RECEIPT_FEED_OFFSET = 0; // 256 * 4 floats
export const RECEIPT_QUERY_OFFSET = RECEIPT_FEED_OFFSET + MAX_FEEDS_PER_TICK * 4;
export const RECEIPT_EXP_COUNT_OFFSET = RECEIPT_QUERY_OFFSET + MAX_QUERIES_PER_TICK * 12;
export const RECEIPT_EXP_HIT_OFFSET = RECEIPT_EXP_COUNT_OFFSET + 64 * 4;
export const RECEIPT_DECOY_OFFSET = RECEIPT_EXP_HIT_OFFSET + 64 * MAX_HITS_PER_BODY * 4;
export const RECEIPT_SPARK_OFFSET = RECEIPT_DECOY_OFFSET + MAX_DECOYS_PER_TICK;
export const RECEIPT_INSPECT_OFFSET = RECEIPT_SPARK_OFFSET + MAX_REACTION_SPARKS * 4;
export const RECEIPT_STATS_OFFSET = RECEIPT_INSPECT_OFFSET + 6 * 4;
export const RECEIPT_ACID_OFFSET = RECEIPT_STATS_OFFSET + 4 * 4;
export const RECEIPT_IMPACTS_OFFSET = RECEIPT_ACID_OFFSET + FIELD_COUNT;
export const RECEIPT_TOTAL_FLOATS = RECEIPT_IMPACTS_OFFSET + BODY_IMPACTS_LEN;
export const RECEIPT_BYTES = RECEIPT_TOTAL_FLOATS * 4;

export const GPU_MAX_PARTICLES = MAX_PARTICLES;
export const GPU_MAX_BODY_POINTS = 64 * 144; // 9216
export const GPU_MAX_AMBIENT_SPAWNS = 512;
