import { clamp } from './constants.ts';

export const BUDGET_WINDOW = 3.0;

interface BudgetSample {
  epoch: number;
  produced: number;
  stored: number;
  spent: number;
  organs: Map<number, number>;
  categories: Map<string, number>;
}

export interface BudgetRates {
  production: number;
  stored: number;
  spent: number;
  net: number;
  reserveNet: number;
  overflow: number;
  seconds: number;
  sampled: boolean;
  organs: Map<number, number>;
  categories: Map<string, number>;
}

export class EnergyBudget {
  private samples: BudgetSample[] = [];
  private startedAt = -1.0;
  enabled = true;

  clone(): EnergyBudget {
    const b = new EnergyBudget();
    b.startedAt = this.startedAt;
    b.enabled = this.enabled;
    b.samples = this.samples.map((s) => ({
      epoch: s.epoch,
      produced: s.produced,
      stored: s.stored,
      spent: s.spent,
      organs: new Map(s.organs),
      categories: new Map(s.categories),
    }));
    return b;
  }

  record(
    clock: number,
    produced: number,
    stored: number,
    spent: number,
    organId: number,
    category: string,
    shares?: Map<number, number>,
  ): void {
    if (!this.enabled) return;
    if (this.startedAt < 0) this.startedAt = clock;
    const epoch = Math.floor(clock * 4);
    while (this.samples.length > 0 && this.samples[0].epoch < epoch - 11) {
      this.samples.shift();
    }
    if (this.samples.length === 0 || this.samples[this.samples.length - 1].epoch !== epoch) {
      this.samples.push({
        epoch,
        produced: 0,
        stored: 0,
        spent: 0,
        organs: new Map(),
        categories: new Map(),
      });
    }
    const bucket = this.samples[this.samples.length - 1];
    bucket.produced += produced;
    bucket.stored += stored;
    bucket.spent += spent;

    if (spent > 0) {
      let total = 0;
      if (shares) {
        for (const v of shares.values()) total += Math.max(0, v);
      }
      if (shares && total > 0) {
        for (const [k, v] of shares) {
          bucket.organs.set(k, (bucket.organs.get(k) ?? 0) + (spent * Math.max(0, v)) / total);
        }
      } else {
        bucket.organs.set(organId, (bucket.organs.get(organId) ?? 0) + spent);
      }
      bucket.categories.set(category, (bucket.categories.get(category) ?? 0) + spent);
    }
  }

  rates(clock: number): BudgetRates {
    const duration = clamp(clock - Math.max(0, this.startedAt), 0.25, BUDGET_WINDOW);
    const organs = new Map<number, number>();
    const categories = new Map<string, number>();
    let production = 0;
    let stored = 0;
    let spent = 0;
    let sampled = false;
    const epoch = Math.floor(clock * 4);

    for (const bucket of this.samples) {
      if (bucket.epoch < epoch - 11) continue;
      sampled = true;
      production += bucket.produced / duration;
      stored += bucket.stored / duration;
      spent += bucket.spent / duration;
      for (const [k, v] of bucket.organs) {
        organs.set(k, (organs.get(k) ?? 0) + v / duration);
      }
      for (const [k, v] of bucket.categories) {
        categories.set(k, (categories.get(k) ?? 0) + v / duration);
      }
    }

    return {
      production,
      stored,
      spent,
      net: production - spent,
      reserveNet: stored - spent,
      overflow: Math.max(0, production - stored),
      seconds: duration,
      sampled,
      organs,
      categories,
    };
  }
}
