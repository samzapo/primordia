import { MUTATION_DATA, LIGHT_ADAPTATIONS } from './mutations.ts';
import { SeededRng } from './rng.ts';

export class Evolution {
  enabled = true;
  sandbox = true;
  clock = 0.0;
  learned: string[] = [];
  divisionOffers: string[] = [];
  divisionCount = 0;
  random: SeededRng;
  status = 'growing';
  ending = '';
  lightFactor = 1.0;
  exposures = { toxin: 0, pore: 0, acid: 0, photo: 0 };

  constructor(seedNumber = 0) {
    this.random = new SeededRng((seedNumber ^ 0x46ac71) | 0);
  }

  terminal(): boolean {
    return false;
  }

  divided(): boolean {
    this.divisionCount++;
    if (this.random.randf() >= 0.1) return false;
    const pool = Object.keys(MUTATION_DATA).filter(
      (g) =>
        !(LIGHT_ADAPTATIONS as readonly string[]).includes(g) &&
        !this.learned.includes(g) &&
        !this.divisionOffers.includes(g),
    );
    if (pool.length === 0) return false;
    const pick = pool[this.random.randiRange(0, pool.length - 1)];
    this.divisionOffers.push(pick);
    return true;
  }

  acceptDivisionOffer(gene: string): boolean {
    const idx = this.divisionOffers.indexOf(gene);
    if (idx < 0 || !MUTATION_DATA[gene]) return false;
    this.divisionOffers.splice(idx, 1);
    if (!this.learned.includes(gene)) this.learned.push(gene);
    return true;
  }

  record(kind: 'toxin' | 'pore' | 'acid' | 'photo', amount: number): void {
    this.exposures[kind] += Math.max(0, amount);
  }

  advance(dt: number): void {
    this.clock += dt;
  }

  objective(): string {
    return 'Build, feed and grow your family.';
  }
}
