import test from 'node:test';
import assert from 'node:assert/strict';
import { MEMBRANE_COUNT, Membrane, rolePreviewGeometry } from '../src/sim/membrane.ts';
import { Habitat } from '../src/sim/habitat.ts';
import { Cell } from '../src/sim/cell.ts';
import { contactPair } from '../src/sim/contacts.ts';

test('Membrane maintains 28-node XPBD stability and 112-vertex smooth outline', () => {
  const m = new Membrane(45, 777, true);
  m.step(1 / 60, 45, { x: 0, y: 0 }, 0.1);
  const beforeOutline = m.outline();
  assert.equal(beforeOutline.length, MEMBRANE_COUNT * 4);
  assert.equal(m.points.length, MEMBRANE_COUNT);

  m.compress(0.5, 4.0, 45);
  m.step(1 / 60, 45, { x: 10, y: 0 }, 0.2);
  const afterOutline = m.outline();
  assert.equal(afterOutline.length, MEMBRANE_COUNT * 4);
  for (const pt of afterOutline) {
    assert.ok(Number.isFinite(pt.x) && Number.isFinite(pt.y));
  }
});

test('Membrane shape profiles modulate hunter, parasite and protected producer geometry', () => {
  const hPos = Membrane.hunterProfile(0);
  const pPos = Membrane.parasiteProfile(0);
  assert.ok(hPos > 1.0);
  assert.ok(pPos > 1.0);

  const cell = new Cell(1, { x: 200, y: 200 }, 11);
  cell.addOrgan('photosynthesis', 0, 'graze', false);
  cell.addOrgan('photosynthesis', Math.PI, 'graze', false);
  cell.addOrgan('mitochondrion', 0.5, 'graze', false);
  cell.updateGeometry();
  assert.equal(cell.membrane.cellWall, true);
});

test('Habitat plant obstacle contacts and cell-cell sequential contacts conserve finite coordinates', () => {
  const hab = new Habitat(20261004, []);
  const cellA = new Cell(1, { x: 1000, y: 1000 }, 1);
  const cellB = new Cell(2, { x: 1020, y: 1000 }, 2);
  contactPair(cellA, cellB, 1 / 60, true);
  assert.ok(Number.isFinite(cellA.position.x) && Number.isFinite(cellB.position.x));
  assert.equal(hab.plants.length, 10);
});

test('rolePreviewGeometry produces distinct synergy-matched silhouettes', () => {
  const radius = 47;
  const producer = rolePreviewGeometry('producer', radius);
  const hunter = rolePreviewGeometry('hunter', radius);
  const parasite = rolePreviewGeometry('parasite', radius);
  const grazer = rolePreviewGeometry('grazer', radius);

  assert.equal(producer.outline.length, MEMBRANE_COUNT * 4);
  assert.equal(hunter.outline.length, MEMBRANE_COUNT * 4);
  assert.equal(parasite.outline.length, MEMBRANE_COUNT * 4);
  assert.equal(grazer.outline.length, MEMBRANE_COUNT * 4);

  // Producer cell wall extends farther along diagonals (corners) than cardinal axes
  const corner = producer.pointAt(Math.PI * 0.25);
  const axis = producer.pointAt(0);
  assert.ok(Math.hypot(corner.x, corner.y) > Math.hypot(axis.x, axis.y) * 1.12);

  // Parasite profile is strongly elongated horizontally along proboscis axis
  let minX = Infinity, maxX = -Infinity, minY = Infinity, maxY = -Infinity;
  for (const p of parasite.outline) {
    if (p.x < minX) minX = p.x;
    if (p.x > maxX) maxX = p.x;
    if (p.y < minY) minY = p.y;
    if (p.y > maxY) maxY = p.y;
  }
  assert.ok((maxX - minX) / (maxY - minY) > 1.85);

  // Hunter 6-pointed star has sharp ratio between peaks and valleys
  let minR = Infinity, maxR = 0;
  for (const p of hunter.outline) {
    const r = Math.hypot(p.x, p.y);
    if (r < minR) minR = r;
    if (r > maxR) maxR = r;
  }
  assert.ok(maxR / minR > 1.6);
});

test('Membrane deforms smoothly under acceleration and bounces elastically across all cell modes', () => {
  for (const wall of [false, true]) {
    const m = new Membrane(47, -1, true);
    m.cellWall = wall;
    for (let s = 0; s < 20; s++) {
      m.step(1 / 60, 47, { x: 0, y: 0 }, s * 0.016);
    }
    const baseFront = Math.hypot(m.points[0].x, m.points[0].y);
    const baseRear = Math.hypot(m.points[MEMBRANE_COUNT / 2].x, m.points[MEMBRANE_COUNT / 2].y);

    // Accelerate strongly along +X: front flattens, rear stretches/lags backward
    for (let s = 0; s < 18; s++) {
      m.step(1 / 60, 47, { x: 350, y: 0 }, 0.35 + s * 0.016);
    }
    const accFront = Math.hypot(m.points[0].x, m.points[0].y);
    const accRear = Math.hypot(m.points[MEMBRANE_COUNT / 2].x, m.points[MEMBRANE_COUNT / 2].y);
    assert.ok(
      accRear - accFront > baseRear - baseFront + (wall ? 1.2 : 3.5),
      `Expected visible acceleration bulge difference for cellWall=${wall}`,
    );

    // Elastic impact bounces inward and rebounds back smoothly
    const preHit = Math.hypot(m.points[7].x, m.points[7].y);
    m.bounceAt(Math.PI * 0.5, 5.5, 47);
    const dented = Math.hypot(m.points[7].x, m.points[7].y);
    assert.ok(dented < preHit - (wall ? 1.0 : 3.0));
    m.step(1 / 60, 47, { x: 0, y: 0 }, 0.8);
    assert.ok(Number.isFinite(m.points[7].x) && Number.isFinite(m.points[7].y));
  }
});
