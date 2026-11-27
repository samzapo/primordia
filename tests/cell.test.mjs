import test from 'node:test';
import assert from 'node:assert/strict';
import {
  Cell,
  ORGAN_KINDS,
  ORGAN_COST,
  ORGAN_TITLES,
  isReceptorKind,
  organUpkeepEstimate,
} from '../src/sim/cell.ts';
import { PORE_REQUIRED, acceptSurfacePacket, advanceSurfaceComplexes } from '../src/sim/surfaceChemistry.ts';
import { fillToxinSacs } from '../src/sim/toxinSac.ts';

test('all 18 organ kinds define titles, costs and Fibonacci non-receptor pricing', () => {
  assert.equal(ORGAN_KINDS.length, 18);
  const cell = new Cell(10, { x: 500, y: 500 }, 123);
  cell.biomass = 200;
  assert.equal(cell.constructionPrice('sensing'), 0);
  assert.ok(isReceptorKind('hunting'));
  assert.equal(cell.constructionPrice('feeding'), 0);
  assert.ok(cell.addOrgan('feeding', 0, 'graze', false));
  assert.equal(cell.constructionPrice('propulsion'), 0);
  assert.ok(cell.addOrgan('propulsion', Math.PI, 'graze', false));
  // Fibonacci x 10 after 2 free slots: 10, 10, 20, 30...
  assert.equal(cell.constructionPrice('protection'), 10);
  assert.ok(cell.addOrgan('protection', 1.2, 'graze', false));
  assert.equal(cell.constructionPrice('toxin'), 10);
  assert.ok(cell.addOrgan('toxin', -1.2, 'graze', false));
  assert.equal(cell.constructionPrice('cilia'), 20);
  assert.ok(ORGAN_TITLES.proboscis.length > 0);
  assert.ok(ORGAN_COST.cilia > 0);
});

test('cellular synergy detection follows parasite -> hunter -> producer -> grazer precedence', () => {
  const producer = new Cell(1, { x: 0, y: 0 }, 1);
  producer.addOrgan('photosynthesis', 0, 'graze', false);
  producer.addOrgan('photosynthesis', Math.PI, 'graze', false);
  producer.addOrgan('mitochondrion', 0.5, 'graze', false);
  assert.equal(producer.synergy(), 'producer');

  const grazer = new Cell(2, { x: 0, y: 0 }, 2);
  grazer.addOrgan('feeding', 0, 'graze', false);
  grazer.addOrgan('cilia', Math.PI, 'graze', false);
  assert.equal(grazer.synergy(), 'grazer');

  const hunter = new Cell(3, { x: 0, y: 0 }, 3);
  hunter.addOrgan('hunting', 0, 'graze', false);
  hunter.addOrgan('propulsion', Math.PI, 'graze', false);
  hunter.addOrgan('feeding', 0.5, 'graze', false);
  hunter.addOrgan('poreforming', -0.5, 'graze', false);
  assert.equal(hunter.synergy(), 'hunter');

  const parasite = new Cell(4, { x: 0, y: 0 }, 4);
  parasite.addOrgan('hunting', 0, 'graze', false);
  parasite.addOrgan('sensing', 0.5, 'graze', false);
  parasite.addOrgan('proboscis', 1.0, 'graze', false);
  parasite.addOrgan('propulsion', Math.PI, 'graze', false);
  assert.equal(parasite.synergy(), 'parasite');
});

test('ATP low-power latch hysteresis (12/18) and organ upkeep calculation', () => {
  const cell = new Cell(5, { x: 0, y: 0 }, 5);
  cell.addOrgan('feeding', 0, 'graze', false);
  cell.addOrgan('cilia', 1, 'graze', false);
  assert.ok(organUpkeepEstimate(cell.organs[0]) > 0);
  assert.ok(organUpkeepEstimate(cell.organs[1]) > 0);

  cell.energy = 10;
  cell.updatePowerState();
  assert.equal(cell.lowPowerLatched, true);
  cell.energy = 15;
  cell.updatePowerState();
  assert.equal(cell.lowPowerLatched, true);
  cell.energy = 20;
  cell.updatePowerState();
  assert.equal(cell.lowPowerLatched, false);
});

test('surface chemistry assembles pores (1 tag + 4 pore units) and caps with antitoxin', () => {
  const cell = new Cell(6, { x: 200, y: 200 }, 6);
  acceptSurfacePacket(cell, 11, 0.06, 0.2, 99, 0, () => {}); // TAG
  assert.equal(cell.surfaceComplexes.length, 1);
  for (let i = 0; i < PORE_REQUIRED; i++) {
    acceptSurfacePacket(cell, 12, 0.06, 0.22, 99, 0, () => {}); // PORE
  }
  assert.ok(cell.surfaceComplexes[0].units >= PORE_REQUIRED);

  const hpBefore = cell.health;
  advanceSurfaceComplexes(cell, 0.5, 0, () => {}, () => {});
  assert.ok(cell.health < hpBefore);

  // Antitoxin caps assembling pores (< PORE_REQUIRED)
  const cellB = new Cell(8, { x: 240, y: 240 }, 8);
  acceptSurfacePacket(cellB, 11, 0.06, 0.2, 99, 0, () => {});
  acceptSurfacePacket(cellB, 12, 0.06, 0.21, 99, 0, () => {});
  assert.equal(acceptSurfacePacket(cellB, 7, 0.06, 0.21, 8, 0, () => {}), true);
  assert.equal(cellB.surfaceComplexes[0].capped, true);
});

test('toxin sac stores venom capacity steadily from ATP & biomass', () => {
  const cell = new Cell(7, { x: 0, y: 0 }, 7);
  cell.addOrgan('toxin_sac', 0, 'graze', false);
  const sac = cell.organs[0];
  fillToxinSacs(cell, 1.0);
  assert.ok(sac.storedToxin > 0);
});
