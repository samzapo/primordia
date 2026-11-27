import { TAU } from './constants.ts';

export function hash32(x: number): number {
  let h = x >>> 0;
  h ^= h >>> 16;
  h = Math.imul(h, 0x7feb352d) >>> 0;
  h ^= h >>> 15;
  h = Math.imul(h, 0x846ca68b) >>> 0;
  h ^= h >>> 16;
  return h >>> 0;
}

export class SeededRng {
  private state: number;

  constructor(seed = 20261004) {
    this.state = (seed | 0) >>> 0 || 1;
  }

  reseed(seed: number): void {
    this.state = (seed | 0) >>> 0 || 1;
  }

  nextUint(): number {
    this.state = (this.state + 0x6d2b79f5) >>> 0;
    let t = Math.imul(this.state ^ (this.state >>> 15), 1 | this.state);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return (t ^ (t >>> 14)) >>> 0;
  }

  randf(): number {
    return this.nextUint() / 4294967296.0;
  }

  randRange(lo: number, hi: number): number {
    return lo + (hi - lo) * this.randf();
  }

  randiRange(lo: number, hiInclusive: number): number {
    if (hiInclusive <= lo) return lo;
    const span = hiInclusive - lo + 1;
    return lo + (this.nextUint() % span);
  }

  randNormal(mean = 0, std = 1): number {
    const u1 = Math.max(1e-7, this.randf());
    const u2 = this.randf();
    const z = Math.sqrt(-2.0 * Math.log(u1)) * Math.cos(TAU * u2);
    return mean + z * std;
  }
}
