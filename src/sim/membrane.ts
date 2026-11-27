import { TAU, clamp, lerp, posmod, wrapAngle, type Vec2 } from './constants.ts';
import { Cytoskeleton } from './cytoskeleton.ts';

export const MEMBRANE_COUNT = 28;

export class Membrane {
  readonly COUNT = MEMBRANE_COUNT;
  skeleton = new Cytoskeleton();
  maximumRadius = 47.0;
  oralAngle = Number.NaN;
  cellWall = false;
  hunterAngle = Number.NaN;
  parasiteAngle = Number.NaN;

  points: Vec2[] = [];
  previous: Vec2[] = [];
  readonly edgeLambda = new Float32Array(MEMBRANE_COUNT);
  areaLambda = 0.0;
  readonly normals: Vec2[] = [];
  readonly restPoints: Vec2[] = [];
  readonly restLengths = new Float32Array(MEMBRANE_COUNT);
  readonly gradients: Vec2[] = [];
  readonly arcs = new Float32Array(MEMBRANE_COUNT + 1);
  cachedOutline: Vec2[] = [];
  geometryDirty = true;
  outlineDirty = true;

  constructor(radius = 47.0, anatomySeed = -1, initializeRing = true) {
    for (let i = 0; i < MEMBRANE_COUNT; i++) {
      const a = (TAU * i) / MEMBRANE_COUNT;
      const n = { x: Math.cos(a), y: Math.sin(a) };
      this.normals.push(n);
      this.restPoints.push({ x: n.x * radius, y: n.y * radius });
      this.gradients.push({ x: 0, y: 0 });
    }
    if (!initializeRing) return;
    this.maximumRadius = radius;
    for (let i = 0; i < MEMBRANE_COUNT; i++) {
      const n = this.normals[i];
      this.points.push({ x: n.x * radius, y: n.y * radius });
      this.previous.push({ x: n.x * radius, y: n.y * radius });
    }
    if (anatomySeed >= 0) {
      this.skeleton.seedLayout(anatomySeed, this, radius);
    }
  }

  clone(): Membrane {
    const m = new Membrane(this.maximumRadius, -1, false);
    m.skeleton = this.skeleton.clone();
    m.maximumRadius = this.maximumRadius;
    m.oralAngle = this.oralAngle;
    m.cellWall = this.cellWall;
    m.hunterAngle = this.hunterAngle;
    m.parasiteAngle = this.parasiteAngle;
    m.points = this.points.map((p) => ({ ...p }));
    m.previous = this.previous.map((p) => ({ ...p }));
    m.edgeLambda.set(this.edgeLambda);
    m.areaLambda = this.areaLambda;
    for (let i = 0; i < MEMBRANE_COUNT; i++) {
      m.restPoints[i] = { ...this.restPoints[i] };
    }
    m.restLengths.set(this.restLengths);
    m.arcs.set(this.arcs);
    m.cachedOutline = this.cachedOutline.map((p) => ({ ...p }));
    m.geometryDirty = this.geometryDirty;
    m.outlineDirty = this.outlineDirty;
    return m;
  }

  static hunterProfile(angle: number): number {
    const half = Math.PI / 6.0;
    const phi = posmod(angle, TAU / 6.0) - half;
    const tangent = Math.tan(phi);
    const outer = 1.75;
    const control = outer * 0.1;
    const forward = (outer * Math.cos(half) + control) * 0.5;
    const curve = (outer * Math.cos(half) - control) * 0.5;
    const side = outer * Math.sin(half);
    const disc = Math.max(0, side * side - 4 * tangent * tangent * curve * forward);
    const u = (2 * tangent * forward) / (side + Math.sqrt(disc));
    return Math.hypot(forward + curve * u * u, side * u);
  }

  static parasiteProfile(angle: number): number {
    const ca = Math.cos(angle);
    const sa = Math.sin(angle);
    return (
      Math.pow(Math.pow(Math.abs(ca) / 1.65, 2.6) + Math.pow(Math.abs(sa) / 0.68, 2.6), -1.0 / 2.6) *
      (1.0 + 0.05 * ca)
    );
  }

  static hunterNodeAngle(index: number, axis: number): number {
    const nominal = (TAU * index) / MEMBRANE_COUNT;
    const tip = axis + Math.round((nominal - axis) / (TAU / 6.0)) * (TAU / 6.0);
    const mapped = posmod(Math.round((posmod(tip, TAU) / TAU) * MEMBRANE_COUNT), MEMBRANE_COUNT);
    return mapped === index ? tip : nominal;
  }

  step(
    dt: number,
    radius: number,
    acceleration: Vec2,
    time: number,
    traction?: Vec2[],
  ): void {
    if (dt < 1e-6) return;
    this.invalidate();
    const hasHunter = Number.isFinite(this.hunterAngle);
    const hasParasite = Number.isFinite(this.parasiteAngle);

    for (let i = 0; i < MEMBRANE_COUNT; i++) {
      const a = (TAU * i) / MEMBRANE_COUNT;
      const contraction =
        (1.0 + 0.14 * Math.sin(a * 3 + time * 0.48) + 0.075 * Math.sin(a * 5 - time * 0.71)) / 1.006;
      this.restPoints[i].x = this.normals[i].x * radius * contraction;
      this.restPoints[i].y = this.normals[i].y * radius * contraction;
      if (hasHunter) {
        const polar = Membrane.hunterNodeAngle(i, this.hunterAngle);
        const prof = radius * Membrane.hunterProfile(polar - this.hunterAngle);
        this.restPoints[i].x = Math.cos(polar) * prof;
        this.restPoints[i].y = Math.sin(polar) * prof;
      }
      if (hasParasite) {
        const prof = radius * Membrane.parasiteProfile(a - this.parasiteAngle);
        this.restPoints[i].x = this.normals[i].x * prof;
        this.restPoints[i].y = this.normals[i].y * prof;
      }
      if (this.cellWall) {
        const ax = Math.abs(this.normals[i].x);
        const ay = Math.abs(this.normals[i].y);
        const wallScale = radius / Math.pow(Math.pow(ax, 8) + Math.pow(ay, 8), 1.0 / 8.0);
        this.restPoints[i].x = this.normals[i].x * wallScale;
        this.restPoints[i].y = this.normals[i].y * wallScale;
      }
    }

    if (this.cellWall || hasHunter || hasParasite) {
      let area = 0;
      for (let i = 0; i < MEMBRANE_COUNT; i++) {
        const next = this.restPoints[(i + 1) % MEMBRANE_COUNT];
        area += (this.restPoints[i].x * next.y - this.restPoints[i].y * next.x) * 0.5;
      }
      const targetArea = MEMBRANE_COUNT * radius * radius * Math.sin(TAU / MEMBRANE_COUNT) * 0.5;
      const scale = Math.sqrt(targetArea / Math.max(1e-6, area));
      for (let i = 0; i < MEMBRANE_COUNT; i++) {
        this.restPoints[i].x *= scale;
        this.restPoints[i].y *= scale;
      }
    }

    for (let i = 0; i < MEMBRANE_COUNT; i++) {
      const next = this.restPoints[(i + 1) % MEMBRANE_COUNT];
      this.restLengths[i] = Math.hypot(next.x - this.restPoints[i].x, next.y - this.restPoints[i].y);
    }

    const damping = this.cellWall ? 0.35 : 0.84;
    const softness = this.cellWall ? 0.12 : 1.0;
    const restBlend = this.cellWall ? 1 - Math.exp(-dt * 8) : dt * 0.85;
    for (let i = 0; i < MEMBRANE_COUNT; i++) {
      const px = this.points[i].x;
      const py = this.points[i].y;
      const mx = (px - this.previous[i].x) * damping;
      const my = (py - this.previous[i].y) * damping;
      this.previous[i].x = px;
      this.previous[i].y = py;
      this.points[i].x +=
        mx + (this.restPoints[i].x - px) * restBlend - acceleration.x * dt * dt * 0.18 * softness;
      this.points[i].y +=
        my + (this.restPoints[i].y - py) * restBlend - acceleration.y * dt * dt * 0.18 * softness;
      if (traction && traction.length === MEMBRANE_COUNT) {
        this.points[i].x += traction[i].x * dt * dt * 22.0 * softness;
        this.points[i].y += traction[i].y * dt * dt * 22.0 * softness;
      }
    }

    this.skeleton.begin(radius);
    this.edgeLambda.fill(0);
    this.areaLambda = 0;
    const edgeAlpha = (this.cellWall ? 0.00008 : 0.0008) / (dt * dt);
    const areaAlpha = 0.00001 / (dt * dt);
    const targetArea = MEMBRANE_COUNT * radius * radius * Math.sin(TAU / MEMBRANE_COUNT) * 0.5;

    for (let iter = 0; iter < 6; iter++) {
      for (let i = 0; i < MEMBRANE_COUNT; i++) {
        const j = (i + 1) % MEMBRANE_COUNT;
        const dx = this.points[j].x - this.points[i].x;
        const dy = this.points[j].y - this.points[i].y;
        const length = Math.hypot(dx, dy);
        if (length < 0.0001) continue;
        const dl = (-(length - this.restLengths[i]) - edgeAlpha * this.edgeLambda[i]) / (2 + edgeAlpha);
        this.edgeLambda[i] += dl;
        const ux = (dx / length) * dl;
        const uy = (dy / length) * dl;
        this.points[i].x -= ux;
        this.points[i].y -= uy;
        this.points[j].x += ux;
        this.points[j].y += uy;
      }

      if (!this.cellWall) {
        this.skeleton.solve(this, dt, radius);
      }

      let denom = areaAlpha;
      let area = 0;
      for (let i = 0; i < MEMBRANE_COUNT; i++) {
        const next = this.points[(i + 1) % MEMBRANE_COUNT];
        const prev = this.points[(i - 1 + MEMBRANE_COUNT) % MEMBRANE_COUNT];
        area += (this.points[i].x * next.y - this.points[i].y * next.x) * 0.5;
        const gx = (next.y - prev.y) * 0.5;
        const gy = (prev.x - next.x) * 0.5;
        this.gradients[i].x = gx;
        this.gradients[i].y = gy;
        denom += gx * gx + gy * gy;
      }
      const dl = (-(area - targetArea) - areaAlpha * this.areaLambda) / Math.max(denom, 0.0001);
      this.areaLambda += dl;
      for (let i = 0; i < MEMBRANE_COUNT; i++) {
        this.points[i].x += this.gradients[i].x * dl;
        this.points[i].y += this.gradients[i].y * dl;
      }
    }

    const sectorHalf = (TAU / MEMBRANE_COUNT) * 0.38;
    const maxLen = radius * (hasHunter || hasParasite ? 2.1 : 1.48);
    const minLen = radius * 0.58;
    for (let i = 0; i < MEMBRANE_COUNT; i++) {
      const nominal = (TAU * i) / MEMBRANE_COUNT;
      let p = this.points[i];
      if (!Number.isFinite(p.x) || !Number.isFinite(p.y)) {
        p = this.restPoints[i];
      }
      const angle = nominal + clamp(wrapAngle(Math.atan2(p.y, p.x) - nominal), -sectorHalf, sectorHalf);
      const len = clamp(Math.hypot(p.x, p.y), minLen, maxLen);
      const sx = Math.cos(angle) * len;
      const sy = Math.sin(angle) * len;
      if (Number.isFinite(this.points[i].x) && Number.isFinite(this.points[i].y)) {
        this.previous[i].x += sx - this.points[i].x;
        this.previous[i].y += sy - this.points[i].y;
      }
      if (!Number.isFinite(this.previous[i].x) || !Number.isFinite(this.previous[i].y)) {
        this.previous[i].x = sx;
        this.previous[i].y = sy;
      }
      this.points[i].x = sx;
      this.points[i].y = sy;
    }

    const lengths = new Float32Array(MEMBRANE_COUNT);
    for (let i = 0; i < MEMBRANE_COUNT; i++) {
      lengths[i] = Math.hypot(this.points[i].x, this.points[i].y);
    }
    for (let i = 0; i < MEMBRANE_COUNT; i++) {
      const l =
        lengths[i] * 0.6 +
        (lengths[(i - 1 + MEMBRANE_COUNT) % MEMBRANE_COUNT] + lengths[(i + 1) % MEMBRANE_COUNT]) * 0.2;
      const curLen = lengths[i] || 1;
      const cx = (this.points[i].x / curLen) * l;
      const cy = (this.points[i].y / curLen) * l;
      this.previous[i].x += cx - this.points[i].x;
      this.previous[i].y += cy - this.points[i].y;
      this.points[i].x = cx;
      this.points[i].y = cy;
    }

    if (this.cellWall) {
      for (let i = 0; i < MEMBRANE_COUNT; i++) {
        const restL = Math.hypot(this.restPoints[i].x, this.restPoints[i].y);
        const clamped = clamp(Math.hypot(this.points[i].x, this.points[i].y), restL * 0.98, restL * 1.02);
        const cx = this.normals[i].x * clamped;
        const cy = this.normals[i].y * clamped;
        this.previous[i].x += cx - this.points[i].x;
        this.previous[i].y += cy - this.points[i].y;
        this.points[i].x = cx;
        this.points[i].y = cy;
      }
    }
    if (hasParasite) {
      for (let i = 0; i < MEMBRANE_COUNT; i++) {
        const restL = Math.hypot(this.restPoints[i].x, this.restPoints[i].y);
        const clamped = clamp(Math.hypot(this.points[i].x, this.points[i].y), restL * 0.94, restL * 1.06);
        const cx = this.normals[i].x * clamped;
        const cy = this.normals[i].y * clamped;
        this.previous[i].x += cx - this.points[i].x;
        this.previous[i].y += cy - this.points[i].y;
        this.points[i].x = cx;
        this.points[i].y = cy;
      }
    }
    if (hasHunter) {
      for (let i = 0; i < MEMBRANE_COUNT; i++) {
        const restL = Math.hypot(this.restPoints[i].x, this.restPoints[i].y) || 1;
        const clamped = clamp(Math.hypot(this.points[i].x, this.points[i].y), restL * 0.98, restL * 1.02);
        const cx = (this.restPoints[i].x / restL) * clamped;
        const cy = (this.restPoints[i].y / restL) * clamped;
        this.previous[i].x += cx - this.points[i].x;
        this.previous[i].y += cy - this.points[i].y;
        this.points[i].x = cx;
        this.points[i].y = cy;
      }
    }

    if (Number.isFinite(this.oralAngle)) {
      for (let i = 0; i < MEMBRANE_COUNT; i++) {
        const direction = hasHunter ? Math.atan2(this.points[i].y, this.points[i].x) : (TAU * i) / MEMBRANE_COUNT;
        const distance = Math.abs(wrapAngle(direction - this.oralAngle));
        if (distance > 0.5) continue;
        const weight = Math.pow(0.5 + 0.5 * Math.cos((Math.PI * distance) / 0.5), 1.5);
        const curLen = Math.hypot(this.points[i].x, this.points[i].y) || 1;
        const targetLen = Math.min(curLen, radius * (1 - 0.36 * weight));
        const cx = (this.points[i].x / curLen) * targetLen;
        const cy = (this.points[i].y / curLen) * targetLen;
        this.previous[i].x += cx - this.points[i].x;
        this.previous[i].y += cy - this.points[i].y;
        this.points[i].x = cx;
        this.points[i].y = cy;
      }
    }

    let enclosed = 0;
    for (let i = 0; i < MEMBRANE_COUNT; i++) {
      const next = this.points[(i + 1) % MEMBRANE_COUNT];
      enclosed += (this.points[i].x * next.y - this.points[i].y * next.x) * 0.5;
    }
    const pressureScale = Math.sqrt(targetArea / Math.max(0.001, enclosed));
    this.maximumRadius = 0;
    for (let i = 0; i < MEMBRANE_COUNT; i++) {
      const cx = this.points[i].x * pressureScale;
      const cy = this.points[i].y * pressureScale;
      this.maximumRadius = Math.max(this.maximumRadius, Math.hypot(cx, cy));
      this.previous[i].x += cx - this.points[i].x;
      this.previous[i].y += cy - this.points[i].y;
      this.points[i].x = cx;
      this.points[i].y = cy;
    }
  }

  compress(localAngle: number, depth: number, radius: number): void {
    if (this.cellWall) depth *= 0.12;
    let beforeArea = 0;
    for (let i = 0; i < MEMBRANE_COUNT; i++) {
      const next = this.points[(i + 1) % MEMBRANE_COUNT];
      beforeArea += (this.points[i].x * next.y - this.points[i].y * next.x) * 0.5;
    }
    for (let i = 0; i < MEMBRANE_COUNT; i++) {
      const pt = this.points[i];
      const ang = Math.atan2(pt.y, pt.x);
      const distance = Math.abs(wrapAngle(ang - localAngle));
      if (distance >= 0.65) continue;
      const weight = 0.5 + 0.5 * Math.cos((Math.PI * distance) / 0.65);
      const curLen = Math.hypot(pt.x, pt.y) || 1;
      const nextLen = Math.max(radius * 0.58, curLen - depth * weight);
      const cx = (pt.x / curLen) * nextLen;
      const cy = (pt.y / curLen) * nextLen;
      this.previous[i].x += cx - pt.x;
      this.previous[i].y += cy - pt.y;
      pt.x = cx;
      pt.y = cy;
    }
    let area = 0;
    for (let i = 0; i < MEMBRANE_COUNT; i++) {
      const next = this.points[(i + 1) % MEMBRANE_COUNT];
      area += (this.points[i].x * next.y - this.points[i].y * next.x) * 0.5;
    }
    const scale = Math.sqrt(Math.max(0.001, beforeArea) / Math.max(0.001, area));
    this.maximumRadius = 0;
    for (let i = 0; i < MEMBRANE_COUNT; i++) {
      const cx = this.points[i].x * scale;
      const cy = this.points[i].y * scale;
      this.previous[i].x += cx - this.points[i].x;
      this.previous[i].y += cy - this.points[i].y;
      this.points[i].x = cx;
      this.points[i].y = cy;
      this.maximumRadius = Math.max(this.maximumRadius, Math.hypot(cx, cy));
    }
    this.invalidate();
  }

  invalidate(): void {
    this.geometryDirty = true;
    this.outlineDirty = true;
  }

  refreshArcs(): void {
    if (!this.geometryDirty) return;
    this.arcs[0] = 0;
    for (let i = 0; i < MEMBRANE_COUNT; i++) {
      const a = this.points[i];
      const b = this.points[(i + 1) % MEMBRANE_COUNT];
      this.arcs[i + 1] = this.arcs[i] + Math.hypot(b.x - a.x, b.y - a.y);
    }
    this.geometryDirty = false;
  }

  outline(): Vec2[] {
    if (!this.outlineDirty) return this.cachedOutline;
    if (Number.isFinite(this.hunterAngle)) {
      this.cachedOutline = this.hunterOutline();
      this.outlineDirty = false;
      return this.cachedOutline;
    }
    const curve: Vec2[] = [];
    const angles = Membrane.orderedAngles(this.points);
    for (let i = 0; i < MEMBRANE_COUNT; i++) {
      const pBefore = this.points[(i - 1 + MEMBRANE_COUNT) % MEMBRANE_COUNT];
      const pStart = this.points[i];
      const pEnd = this.points[(i + 1) % MEMBRANE_COUNT];
      const pAfter = this.points[(i + 2) % MEMBRANE_COUNT];
      const before = Math.hypot(pBefore.x, pBefore.y);
      const start = Math.hypot(pStart.x, pStart.y);
      const end = Math.hypot(pEnd.x, pEnd.y);
      const after = Math.hypot(pAfter.x, pAfter.y);
      const angle = angles[i];
      const angleDelta = posmod(angles[(i + 1) % MEMBRANE_COUNT] - angle, TAU);
      for (let j = 0; j < 4; j++) {
        const t = j / 4.0;
        let r =
          0.5 *
          (2 * start +
            (-before + end) * t +
            (2 * before - 5 * start + 4 * end - after) * t * t +
            (-before + 3 * start - 3 * end + after) * t * t * t);
        r = clamp(r, Math.max(0.1, Math.min(start, end) * 0.95), Math.max(start, end) * 1.05);
        const a = angle + angleDelta * t;
        curve.push({ x: Math.cos(a) * r, y: Math.sin(a) * r });
      }
    }
    this.cachedOutline = curve;
    this.outlineDirty = false;
    return this.cachedOutline;
  }

  private hunterOutline(): Vec2[] {
    const curve: Vec2[] = [];
    const angles = Membrane.orderedAngles(this.points);
    for (let i = 0; i < MEMBRANE_COUNT; i++) {
      const next = (i + 1) % MEMBRANE_COUNT;
      const angle = angles[i];
      const delta = posmod(angles[next] - angle, TAU);
      const start =
        Math.hypot(this.points[i].x, this.points[i].y) /
        Membrane.hunterProfile(angle - this.hunterAngle);
      const end =
        Math.hypot(this.points[next].x, this.points[next].y) /
        Membrane.hunterProfile(angles[next] - this.hunterAngle);
      for (let j = 0; j < 4; j++) {
        const t = j / 4.0;
        const at = angle + delta * t;
        const r = Membrane.hunterProfile(at - this.hunterAngle) * lerp(start, end, t);
        curve.push({ x: Math.cos(at) * r, y: Math.sin(at) * r });
      }
    }
    return curve;
  }

  static orderedAngles(nodes: Vec2[]): number[] {
    const angles = nodes.map((p) => Math.atan2(p.y, p.x));
    let turn = 0;
    let ordered = true;
    for (let i = 0; i < angles.length; i++) {
      const step = posmod(angles[(i + 1) % angles.length] - angles[i], TAU);
      turn += step;
      if (step < 1e-6 || step > Math.PI) ordered = false;
    }
    if (ordered && Math.abs(turn - TAU) < 0.001) return angles;
    const sector = TAU / Math.max(1, nodes.length);
    for (let i = 0; i < angles.length; i++) {
      const nominal = sector * i;
      angles[i] = nominal + clamp(wrapAngle(angles[i] - nominal), -sector * 0.38, sector * 0.38);
    }
    return angles;
  }
}
