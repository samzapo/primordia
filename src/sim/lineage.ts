import type { Cell } from './cell.ts';
import type { Evolution } from './evolution.ts';

export interface LineageRecord {
  id: number;
  parent: number;
  generation: number;
  state: 'active' | 'living' | 'dead';
  born: number;
}

export class Lineage {
  rootId = 0;
  records: LineageRecord[] = [];
  notices: string[] = [];
  serial = 0;
  progression: Evolution | null = null;
  births = 0;
  deaths = 0;
  totalCells = 0;
  highestGeneration = 0;

  initialize(player: Cell, now: number): void {
    this.rootId = player.lineageId();
    this.register(player, -1, 0, 'active', now);
  }

  activeFamily(cells: Cell[]): Cell[] {
    return cells.filter((c) => !c.dead && c.health > 0 && c.lineageId() === this.rootId);
  }

  register(
    cell: Cell,
    parentId: number,
    generation: number,
    state: 'active' | 'living',
    now: number,
  ): void {
    cell.generation = generation;
    if (this.recordFor(cell.id)) return;
    this.totalCells++;
    this.highestGeneration = Math.max(this.highestGeneration, generation);
    this.records.push({ id: cell.id, parent: parentId, generation, state, born: now });
  }

  recordFor(id: number): LineageRecord | undefined {
    return this.records.find((r) => r.id === id);
  }

  notify(text: string): void {
    this.serial++;
    this.notices.push(text);
    if (this.notices.length > 8) this.notices.shift();
  }

  died(cell: Cell): void {
    if (cell.lineageId() !== this.rootId) return;
    const rec = this.recordFor(cell.id);
    if (!rec) return;
    const idx = this.records.indexOf(rec);
    if (idx >= 0) this.records.splice(idx, 1);
    this.deaths++;
    this.notify(`Generation ${cell.generation} lost · ${cell.deathHint}`);
  }

  adopted(
    cell: Cell,
    sim: {
      player: Cell;
      cells: Cell[];
      recordSound(kind: string, at: { x: number; y: number }, source: number): void;
    },
  ): void {
    if (sim.player.dead) {
      const idx = sim.cells.indexOf(sim.player);
      if (idx >= 0) sim.cells.splice(idx, 1);
    } else {
      sim.player.role = 'ancestor';
      const prev = this.recordFor(sim.player.id);
      if (prev) prev.state = 'living';
    }
    sim.player = cell;
    cell.role = 'player';
    cell.activity = 1.0;
    cell.previousPosition = { ...cell.position };
    cell.previousAngle = cell.angle;
    const rec = this.recordFor(cell.id);
    if (rec) rec.state = 'active';
    this.notify(`Family continues · generation ${cell.generation}`);
    sim.recordSound('division', cell.position, cell.id);
  }

  recover(sim: {
    player: Cell;
    cells: Cell[];
    recordSound(kind: string, at: { x: number; y: number }, source: number): void;
  }): boolean {
    if (!sim.player.dead && sim.player.health > 0) return true;
    const family = this.activeFamily(sim.cells);
    if (family.length > 0) {
      family.sort((a, b) => (a.generation !== b.generation ? b.generation - a.generation : b.health - a.health));
      this.adopted(family[0], sim);
      return true;
    }
    return false;
  }

  summary(cells: Cell[]): string {
    return `Highest generation ${this.highestGeneration} · ${this.totalCells} cells ever · ${this.activeFamily(cells).length} living`;
  }
}
