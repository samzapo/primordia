import test from 'node:test';
import assert from 'node:assert/strict';
import { MEMBRANE_COUNT, Membrane } from '../src/sim/membrane.ts';
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
