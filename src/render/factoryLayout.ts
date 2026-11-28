import type { Cell } from '../sim/cell.ts';
import { type Vec2, clamp } from '../sim/constants.ts';

export type LandmarkKind = 'nucleus' | 'assembly' | 'chemistry' | 'receptors' | 'bud' | 'atp';

export interface InteriorLandmark {
  kind: LandmarkKind;
  local: Vec2;
  world: Vec2;
  radius: number;
  label: string;
}

export const LANDMARK_RADII: Record<LandmarkKind, number> = {
  nucleus: 9.5,
  assembly: 8.0,
  chemistry: 8.0,
  receptors: 8.0,
  bud: 8.0,
  atp: 8.0,
};

const LANDMARK_LABELS: Record<LandmarkKind, string> = {
  nucleus: 'Nucleus',
  assembly: 'Assembly Site',
  chemistry: 'Metabolic Lab',
  receptors: 'Receptor Hub',
  bud: 'Division Bud',
  atp: 'ATP Sac',
};

function pointInsideOutline(outline: Vec2[], pt: Vec2): boolean {
  let inside = false;
  for (let i = 0, j = outline.length - 1; i < outline.length; j = i++) {
    const xi = outline[i].x;
    const yi = outline[i].y;
    const xj = outline[j].x;
    const yj = outline[j].y;
    const intersect = yi > pt.y !== yj > pt.y && pt.x < ((xj - xi) * (pt.y - yi)) / (yj - yi + 1e-12) + xi;
    if (intersect) inside = !inside;
  }
  return inside;
}

function minOutlineClearance(outline: Vec2[], pt: Vec2): number {
  let minD2 = Infinity;
  for (let i = 0; i < outline.length; i++) {
    const dx = outline[i].x - pt.x;
    const dy = outline[i].y - pt.y;
    const d2 = dx * dx + dy * dy;
    if (d2 < minD2) minD2 = d2;
  }
  return Math.sqrt(minD2);
}

const ANCHOR_ORDER: readonly LandmarkKind[] = [
  'nucleus',
  'atp',
  'assembly',
  'chemistry',
  'receptors',
  'bud',
];

const ANCHOR_BIAS: Record<LandmarkKind, Vec2> = {
  nucleus: { x: 0.0, y: 0.0 },
  atp: { x: -0.36, y: 0.34 },
  assembly: { x: 0.36, y: -0.32 },
  chemistry: { x: -0.38, y: -0.3 },
  receptors: { x: 0.38, y: 0.32 },
  bud: { x: 0.02, y: -0.52 },
};

export function computeInteriorLandmarks(cell: Cell): InteriorLandmark[] {
  const outline = cell.membrane.outline();
  const ext = cell.extent();
  const candidates: Vec2[] = [];

  // 9x9 deterministic grid across cell interior
  const span = ext * 0.72;
  for (let gx = 0; gx < 9; gx++) {
    for (let gy = 0; gy < 9; gy++) {
      const fx = gx / 4 - 1;
      const fy = gy / 4 - 1;
      const pt = { x: fx * span, y: fy * span };
      if (pointInsideOutline(outline, pt)) {
        candidates.push(pt);
      }
    }
  }
  if (candidates.length === 0) {
    candidates.push({ x: 0, y: 0 });
  }

  const placed: InteriorLandmark[] = [];
  const cos = Math.cos(cell.angle);
  const sin = Math.sin(cell.angle);

  const sizeScale = clamp(cell.radius / 38.0, 0.55, 1.0);
  for (const kind of ANCHOR_ORDER) {
    const baseR = LANDMARK_RADII[kind] * sizeScale;
    const r =
      kind === 'atp'
        ? baseR * clamp(0.75 + 0.45 * (cell.energy / Math.max(1, cell.energyReference())), 0.7, 1.32)
        : baseR;
    const bias = ANCHOR_BIAS[kind];
    const targetX = bias.x * ext * 0.65;
    const targetY = bias.y * ext * 0.65;

    let bestPt = { x: 0, y: 0 };
    let bestScore = -Infinity;

    for (const c of candidates) {
      const clearance = minOutlineClearance(outline, c);
      if (clearance < r + 4 && placed.length > 0 && kind !== 'nucleus') {
        // Prefer interior points with comfortable membrane margin
      }
      let overlapPenalty = 0;
      for (const prev of placed) {
        const minSep = r + prev.radius + 5.5;
        const d = Math.hypot(c.x - prev.local.x, c.y - prev.local.y);
        if (d < minSep) {
          overlapPenalty += (minSep - d) * 14.0;
        }
      }
      const distToBias = Math.hypot(c.x - targetX, c.y - targetY);
      const wallMargin = Math.min(20, clearance - r);
      const score = wallMargin * 2.2 - distToBias * 0.8 - overlapPenalty;
      if (score > bestScore) {
        bestScore = score;
        bestPt = c;
      }
    }

    const world = {
      x: cell.position.x + bestPt.x * cos - bestPt.y * sin,
      y: cell.position.y + bestPt.x * sin + bestPt.y * cos,
    };

    placed.push({
      kind,
      local: { x: bestPt.x, y: bestPt.y },
      world,
      radius: r,
      label: LANDMARK_LABELS[kind],
    });
  }

  return placed;
}
