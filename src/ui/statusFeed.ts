import type { Cell } from '../sim/cell.ts';
import type { Lineage } from '../sim/lineage.ts';

interface ToastEntry {
  text: string;
  expiresAt: number;
}

function describeInstinct(cell: Cell, paused: boolean): string {
  if (paused) return 'Paused — edit cell anatomy or resume pond';
  if (cell.dead) return 'Cell lysed — selecting successor';
  switch (cell.targetMode) {
    case 'acid':
      return 'Evading acidic plume';
    case 'toxin':
    case 'flee':
      return 'Fleeing threat / predator';
    case 'hunt':
      return 'Tracking smaller prey pheromone';
    case 'graze':
      return 'Foraging nutrient patch';
    case 'kin_toward':
    case 'family_toward':
      return 'Staying near family lineage';
    case 'kin_away':
    case 'family_away':
      return 'Dispersing from crowding kin';
    default:
      return cell.driveActive ? 'Exploring pond currents' : 'Conserving ATP / drifting';
  }
}

export class StatusFeed {
  readonly root: HTMLDivElement;
  private readonly toastBox: HTMLDivElement;
  private readonly starveBanner: HTMLDivElement;
  private readonly instinctPill: HTMLDivElement;
  private readonly instinctLabel: HTMLSpanElement;

  private toasts: ToastEntry[] = [];
  private seenNotices = new Set<string>();

  constructor(parent: HTMLElement) {
    this.root = document.createElement('div');
    this.root.className = 'status-feed';

    this.toastBox = document.createElement('div');
    this.toastBox.className = 'status-feed';

    this.starveBanner = document.createElement('div');
    this.starveBanner.className = 'status-starving';
    this.starveBanner.textContent = 'STARVING — No usable ATP reserves remaining';
    this.starveBanner.hidden = true;

    this.instinctPill = document.createElement('div');
    this.instinctPill.className = 'status-instinct';
    const spinner = document.createElement('span');
    spinner.className = 'instinct-spinner';
    this.instinctLabel = document.createElement('span');
    this.instinctPill.append(spinner, this.instinctLabel);

    this.root.append(this.toastBox, this.starveBanner, this.instinctPill);
    parent.appendChild(this.root);
  }

  pushNotice(text: string, nowPerf: number): void {
    const clean = text.trim();
    if (!clean) return;
    if (this.toasts.some((t) => t.text === clean && t.expiresAt > nowPerf)) return;
    this.toasts.push({ text: clean, expiresAt: nowPerf + 3.0 });
    while (this.toasts.length > 3) this.toasts.shift();
  }

  update(focusCell: Cell, lineage: Lineage, paused: boolean, nowPerf: number): void {
    for (const msg of lineage.notices) {
      if (!this.seenNotices.has(msg)) {
        this.seenNotices.add(msg);
        this.pushNotice(msg, nowPerf);
      }
    }

    const beforeLen = this.toasts.length;
    this.toasts = this.toasts.filter((t) => t.expiresAt > nowPerf);
    if (this.toasts.length !== beforeLen || this.toastBox.childElementCount !== this.toasts.length) {
      this.toastBox.replaceChildren(
        ...this.toasts.map((t) => {
          const el = document.createElement('div');
          el.className = 'status-toast';
          el.textContent = t.text;
          return el;
        }),
      );
    }

    this.starveBanner.hidden = focusCell.energy > 0.05 || focusCell.dead;
    this.instinctLabel.textContent = describeInstinct(focusCell, paused);
  }
}
