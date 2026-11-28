import { type Vec2, clamp } from './constants.ts';

export type LandmarkKind = 'nucleus' | 'assembly' | 'chemistry' | 'receptors' | 'bud' | 'atp';

export interface CytoplasmSpringState {
  x: number;
  y: number;
  vx: number;
  vy: number;
}

export interface InteriorLandmark {
  kind: LandmarkKind;
  local: Vec2;
  world: Vec2;
  restLocal: Vec2;
  radius: number;
  label: string;
}

export interface InteriorSpringCell {
  position: Vec2;
  angle: number;
  radius: number;
  energy: number;
  shapeAcceleration: Vec2;
  angularVelocity: number;
  cytoplasmSprings: Map<LandmarkKind, CytoplasmSpringState>;
  energyReference(): number;
  supportLocal(localAngle: number): number;
}

export const LANDMARK_RADII: Record<LandmarkKind, number> = {
  nucleus: 9.5,
  assembly: 7.4,
  chemistry: 7.4,
  receptors: 7.4,
  bud: 7.4,
  atp: 7.4,
};

const LANDMARK_LABELS: Record<LandmarkKind, string> = {
  nucleus: 'Nucleus',
  assembly: 'Assembly Site',
  chemistry: 'Metabolic Lab',
  receptors: 'Receptor Hub',
  bud: 'Division Bud',
  atp: 'ATP Sac',
};

const ANCHOR_ORDER: readonly LandmarkKind[] = [
  'nucleus',
  'atp',
  'assembly',
  'chemistry',
  'receptors',
  'bud',
];

const ANCHOR_POLAR: Record<LandmarkKind, { angle: number; radialFrac: number }> = {
  nucleus: { angle: 0.0, radialFrac: 0.0 },
  assembly: { angle: -0.68, radialFrac: 0.42 },
  chemistry: { angle: -2.44, radialFrac: 0.42 },
  receptors: { angle: 0.72, radialFrac: 0.42 },
  atp: { angle: 2.38, radialFrac: 0.42 },
  bud: { angle: -1.56, radialFrac: 0.50 },
};

const SPRING_STIFFNESS = 26.0;
const SPRING_DAMPING = 5.4;

function landmarkRadius(cell: InteriorSpringCell, kind: LandmarkKind, sizeScale: number): number {
  const baseR = LANDMARK_RADII[kind] * sizeScale;
  if (kind !== 'atp') return baseR;
  return baseR * clamp(0.75 + 0.45 * (cell.energy / Math.max(1, cell.energyReference())), 0.7, 1.32);
}

function landmarkRestLocal(
  cell: InteriorSpringCell,
  kind: LandmarkKind,
  radius: number,
  nucRadius: number,
): Vec2 {
  if (kind === 'nucleus') return { x: 0, y: 0 };
  const anchor = ANCHOR_POLAR[kind];
  const wallR = cell.supportLocal(anchor.angle);
  const nucClear = nucRadius + radius + Math.max(1.2, cell.radius * 0.07);
  const maxReach = Math.max(1.5, wallR - radius - Math.max(1.8, cell.radius * 0.09));
  const dist =
    maxReach <= nucClear
      ? Math.max(1.2, maxReach * 0.85)
      : clamp(wallR * anchor.radialFrac, nucClear, maxReach);
  return {
    x: Math.cos(anchor.angle) * dist,
    y: Math.sin(anchor.angle) * dist,
  };
}

export function stepInteriorSprings(cell: InteriorSpringCell, dt: number): void {
  const safeDt = clamp(dt, 0, 0.04);
  if (safeDt <= 1e-6) return;

  const sizeScale = clamp(cell.radius / 38.0, 0.38, 1.0);
  const nucRadius = landmarkRadius(cell, 'nucleus', sizeScale);
  const rc = Math.cos(-cell.angle);
  const rs = Math.sin(-cell.angle);
  const axLocal = cell.shapeAcceleration.x * rc - cell.shapeAcceleration.y * rs;
  const ayLocal = cell.shapeAcceleration.x * rs + cell.shapeAcceleration.y * rc;
  const radiusGain = clamp(cell.radius / 47.0, 0.38, 1.35);

  for (const kind of ANCHOR_ORDER) {
    const r = kind === 'nucleus' ? nucRadius : landmarkRadius(cell, kind, sizeScale);
    const rest = landmarkRestLocal(cell, kind, r, nucRadius);
    let st = cell.cytoplasmSprings.get(kind);
    if (!st) {
      st = { x: rest.x, y: rest.y, vx: 0, vy: 0 };
      cell.cytoplasmSprings.set(kind, st);
    }

    const lagGain = (kind === 'nucleus' ? 0.32 : 0.44) * radiusGain;
    // Centrifugal/rotational cytoplasmic shear + linear inertial lag
    const omegaSq = cell.angularVelocity * cell.angularVelocity;
    const fx =
      -SPRING_STIFFNESS * (st.x - rest.x) -
      SPRING_DAMPING * st.vx -
      axLocal * lagGain +
      st.x * omegaSq * 0.25;
    const fy =
      -SPRING_STIFFNESS * (st.y - rest.y) -
      SPRING_DAMPING * st.vy -
      ayLocal * lagGain +
      st.y * omegaSq * 0.25;

    st.vx += fx * safeDt;
    st.vy += fy * safeDt;
    st.x += st.vx * safeDt;
    st.y += st.vy * safeDt;

    // Contain strictly within the current living membrane wall
    const curDist = Math.hypot(st.x, st.y);
    const curAngle = curDist > 1e-5 ? Math.atan2(st.y, st.x) : ANCHOR_POLAR[kind].angle;
    const curWall = cell.supportLocal(curAngle);
    const maxR = Math.max(1.0, curWall - r - Math.max(1.2, cell.radius * 0.06));
    if (curDist > maxR && curDist > 1e-5) {
      const nx = st.x / curDist;
      const ny = st.y / curDist;
      st.x = nx * maxR;
      st.y = ny * maxR;
      const outward = st.vx * nx + st.vy * ny;
      if (outward > 0) {
        st.vx -= nx * outward * 1.15;
        st.vy -= ny * outward * 1.15;
      }
    }
  }
}

export function computeInteriorLandmarks(cell: InteriorSpringCell): InteriorLandmark[] {
  const sizeScale = clamp(cell.radius / 38.0, 0.38, 1.0);
  const nucRadius = landmarkRadius(cell, 'nucleus', sizeScale);
  const cos = Math.cos(cell.angle);
  const sin = Math.sin(cell.angle);
  const result: InteriorLandmark[] = [];

  for (const kind of ANCHOR_ORDER) {
    const r = kind === 'nucleus' ? nucRadius : landmarkRadius(cell, kind, sizeScale);
    const rest = landmarkRestLocal(cell, kind, r, nucRadius);
    const spring = cell.cytoplasmSprings.get(kind);
    const local = spring ? { x: spring.x, y: spring.y } : rest;
    const world = {
      x: cell.position.x + local.x * cos - local.y * sin,
      y: cell.position.y + local.x * sin + local.y * cos,
    };
    result.push({
      kind,
      local,
      world,
      restLocal: rest,
      radius: r,
      label: LANDMARK_LABELS[kind],
    });
  }

  return result;
}
