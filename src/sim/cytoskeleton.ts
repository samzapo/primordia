import { TAU, clamp, lerp, posmod, type Vec2 } from './constants.ts';
import { SeededRng } from './rng.ts';

export type Anchor =
  | { kind: 'center' }
  | { kind: 'point'; p: Vec2 }
  | { kind: 'membrane'; a: number }
  | { kind: 'junction'; id: number }
  | { kind: 'link'; id: number; t: number };

export interface CytoskeletonLink {
  id: number;
  group: number;
  a: Anchor;
  b: Anchor;
  tension: number;
  length: number;
  radius: number;
  lambda: number;
}

export interface CytoskeletonJunction {
  p: Vec2;
  previous: Vec2;
}

export interface MembraneLike {
  readonly COUNT: number;
  points: Vec2[];
}

export class Cytoskeleton {
  links: CytoskeletonLink[] = [];
  junctions = new Map<number, CytoskeletonJunction>();
  nextLink = 0;
  nextGroup = 0;
  nextJunction = 0;
  lastRadius = 0;

  clone(): Cytoskeleton {
    const c = new Cytoskeleton();
    c.nextLink = this.nextLink;
    c.nextGroup = this.nextGroup;
    c.nextJunction = this.nextJunction;
    c.lastRadius = this.lastRadius;
    for (const [id, j] of this.junctions) {
      c.junctions.set(id, { p: { ...j.p }, previous: { ...j.previous } });
    }
    for (const l of this.links) {
      c.links.push({
        id: l.id,
        group: l.group,
        a: Cytoskeleton.cloneAnchor(l.a),
        b: Cytoskeleton.cloneAnchor(l.b),
        tension: l.tension,
        length: l.length,
        radius: l.radius,
        lambda: l.lambda,
      });
    }
    return c;
  }

  private static cloneAnchor(a: Anchor): Anchor {
    if (a.kind === 'point') return { kind: 'point', p: { ...a.p } };
    return { ...a };
  }

  point(anchor: Anchor, membrane: MembraneLike): Vec2 {
    if (anchor.kind === 'center') return { x: 0, y: 0 };
    if (anchor.kind === 'point') return anchor.p;
    if (anchor.kind === 'junction') {
      const j = this.junctions.get(anchor.id);
      return j ? j.p : { x: 0, y: 0 };
    }
    if (anchor.kind === 'link') {
      const link = this.linkById(anchor.id);
      if (!link) return { x: 0, y: 0 };
      const pa = this.point(link.a, membrane);
      const pb = this.point(link.b, membrane);
      return { x: lerp(pa.x, pb.x, anchor.t), y: lerp(pa.y, pb.y, anchor.t) };
    }
    const phase = (posmod(anchor.a, TAU) / TAU) * membrane.COUNT;
    const i = Math.floor(phase) % membrane.COUNT;
    const j = (i + 1) % membrane.COUNT;
    const f = phase - Math.floor(phase);
    return {
      x: lerp(membrane.points[i].x, membrane.points[j].x, f),
      y: lerp(membrane.points[i].y, membrane.points[j].y, f),
    };
  }

  linkById(id: number): CytoskeletonLink | undefined {
    return this.links.find((l) => l.id === id);
  }

  valid(anchor: Anchor): boolean {
    if (anchor.kind === 'center') return true;
    if (anchor.kind === 'point') return Number.isFinite(anchor.p.x) && Number.isFinite(anchor.p.y);
    if (anchor.kind === 'membrane') return Number.isFinite(anchor.a);
    if (anchor.kind === 'junction') return this.junctions.has(anchor.id);
    if (anchor.kind === 'link') {
      return (
        this.linkById(anchor.id) !== undefined &&
        Number.isFinite(anchor.t) &&
        anchor.t >= 0 &&
        anchor.t <= 1
      );
    }
    return false;
  }

  private addSegment(
    a: Anchor,
    b: Anchor,
    tension: number,
    length: number,
    radius: number,
    group: number,
  ): number {
    const id = this.nextLink++;
    this.links.push({
      id,
      group,
      a: Cytoskeleton.cloneAnchor(a),
      b: Cytoskeleton.cloneAnchor(b),
      tension,
      length,
      radius,
      lambda: 0,
    });
    return id;
  }

  connectPoints(
    start: Anchor,
    end: Anchor,
    tension: number,
    membrane: MembraneLike,
    radius: number,
  ): number {
    if (!this.valid(start) || !this.valid(end) || !Number.isFinite(tension)) return -1;
    const pStart = this.point(start, membrane);
    const pEnd = this.point(end, membrane);
    const distance = Math.hypot(pEnd.x - pStart.x, pEnd.y - pStart.y);
    if (distance < 6) return -1;

    const anchors: Anchor[] = [Cytoskeleton.cloneAnchor(start), Cytoskeleton.cloneAnchor(end)];
    const splitIds: number[] = [];
    for (const anchor of anchors) {
      if (anchor.kind === 'link' && !splitIds.includes(anchor.id)) {
        splitIds.push(anchor.id);
      }
    }

    for (const id of splitIds) {
      const link = this.linkById(id);
      if (!link) continue;
      const cuts = anchors.filter(
        (a): a is Extract<Anchor, { kind: 'link' }> => a.kind === 'link' && a.id === id,
      );
      cuts.sort((a, b) => a.t - b.t);
      let prior = link.a;
      let prevT = 0;

      for (const cut of cuts) {
        const t = cut.t;
        let endpoint: Anchor;
        if (t < 0.001) {
          endpoint = Cytoskeleton.cloneAnchor(link.a);
        } else if (t > 0.999) {
          endpoint = Cytoskeleton.cloneAnchor(link.b);
        } else {
          const at = this.point(cut, membrane);
          const jid = this.nextJunction++;
          this.junctions.set(jid, { p: { ...at }, previous: { ...at } });
          endpoint = { kind: 'junction', id: jid };
          this.addSegment(prior, endpoint, link.tension, link.length * (t - prevT), link.radius, link.group);
          prior = endpoint;
          prevT = t;
        }
        const idx = anchors.indexOf(cut);
        if (idx >= 0) anchors[idx] = Cytoskeleton.cloneAnchor(endpoint);
      }

      if (prevT < 0.999) {
        this.addSegment(prior, link.b, link.tension, link.length * (1 - prevT), link.radius, link.group);
      }
      this.links = this.links.filter((l) => l.id !== link.id);
    }

    for (let k = 0; k < anchors.length; k++) {
      const anchor = anchors[k];
      if (anchor.kind === 'point') {
        const jid = this.nextJunction++;
        this.junctions.set(jid, { p: { ...anchor.p }, previous: { ...anchor.p } });
        anchors[k] = { kind: 'junction', id: jid };
      }
    }

    const group = this.nextGroup++;
    this.addSegment(anchors[0], anchors[1], clamp(tension, 0, 1), distance, radius, group);
    return group;
  }

  removeGroup(group: number): void {
    this.links = this.links.filter((l) => l.group !== group);
    const used = new Set<number>();
    for (const l of this.links) {
      if (l.a.kind === 'junction') used.add(l.a.id);
      if (l.b.kind === 'junction') used.add(l.b.id);
    }
    for (const id of this.junctions.keys()) {
      if (!used.has(id)) this.junctions.delete(id);
    }
  }

  begin(radius: number): void {
    const growth = this.lastRadius > 0 ? radius / this.lastRadius : 1.0;
    this.lastRadius = radius;
    for (const j of this.junctions.values()) {
      j.p.x *= growth;
      j.p.y *= growth;
      j.previous.x *= growth;
      j.previous.y *= growth;
      const ox = j.p.x;
      const oy = j.p.y;
      j.p.x += (j.p.x - j.previous.x) * 0.8;
      j.p.y += (j.p.y - j.previous.y) * 0.8;
      j.previous.x = ox;
      j.previous.y = oy;
    }
    for (const l of this.links) l.lambda = 0.0;
  }

  private inverseMass(anchor: Anchor, count: number): number {
    if (anchor.kind === 'center') return 0.0;
    if (anchor.kind === 'junction') return 1.5;
    if (anchor.kind !== 'membrane') return 0.0;
    let frac = (posmod(anchor.a, TAU) / TAU) * count;
    frac -= Math.floor(frac);
    return (1 - frac) * (1 - frac) + frac * frac;
  }

  private moveAnchor(anchor: Anchor, dx: number, dy: number, membrane: MembraneLike): void {
    if (anchor.kind === 'center') return;
    if (anchor.kind === 'junction') {
      const j = this.junctions.get(anchor.id);
      if (j) {
        j.p.x += dx * 1.5;
        j.p.y += dy * 1.5;
      }
      return;
    }
    if (anchor.kind !== 'membrane') return;
    const phase = (posmod(anchor.a, TAU) / TAU) * membrane.COUNT;
    const i = Math.floor(phase) % membrane.COUNT;
    const f = phase - Math.floor(phase);
    const j = (i + 1) % membrane.COUNT;
    membrane.points[i].x += dx * (1 - f);
    membrane.points[i].y += dy * (1 - f);
    membrane.points[j].x += dx * f;
    membrane.points[j].y += dy * f;
  }

  solve(membrane: MembraneLike, dt: number, radius: number): void {
    const compliance = 0.00012 / (dt * dt);
    for (const link of this.links) {
      const pa = this.point(link.a, membrane);
      const pb = this.point(link.b, membrane);
      const dx = pb.x - pa.x;
      const dy = pb.y - pa.y;
      const length = Math.hypot(dx, dy);
      const rest = ((link.length * radius) / link.radius) * (1 - link.tension * 0.65);
      if (length < 0.0001 || length <= rest) continue;
      const denom =
        this.inverseMass(link.a, membrane.COUNT) +
        this.inverseMass(link.b, membrane.COUNT) +
        compliance;
      const dl = (-(length - rest) - compliance * link.lambda) / denom;
      link.lambda += dl;
      const ux = (dx / length) * dl;
      const uy = (dy / length) * dl;
      this.moveAnchor(link.a, -ux, -uy, membrane);
      this.moveAnchor(link.b, ux, uy, membrane);
    }
  }

  seedLayout(seedNumber: number, membrane: MembraneLike, radius: number): void {
    const rng = new SeededRng((seedNumber ^ 0x4d595df4) | 0);
    const count = rng.randiRange(0, 4);
    for (let i = 0; i < count; i++) {
      for (let attempt = 0; attempt < 32; attempt++) {
        const a = this.seedAnchor(rng);
        const b = this.seedAnchor(rng);
        const pa = this.point(a, membrane);
        const pb = this.point(b, membrane);
        if (Math.hypot(pb.x - pa.x, pb.y - pa.y) < Math.max(6, radius * 0.3)) continue;
        if (this.connectPoints(a, b, rng.randf(), membrane, radius) >= 0) break;
      }
    }
  }

  private seedAnchor(rng: SeededRng): Anchor {
    if (this.links.length > 0 && rng.randf() < 0.45) {
      const link = this.links[rng.randiRange(0, this.links.length - 1)];
      return { kind: 'link', id: link.id, t: rng.randRange(0.15, 0.85) };
    }
    return { kind: 'membrane', a: rng.randf() * TAU };
  }
}
