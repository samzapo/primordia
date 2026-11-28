import test from 'node:test';
import assert from 'node:assert/strict';
import {
  EXTERNAL_SPECIES,
  SPECIES_DECAY,
  SPECIES_MATERIAL,
  SPECIES_NAMES,
  SPECIES_RADII,
  bindingThreshold,
  materialWeight,
  mergeLimit,
  nutrientCapacity,
  particleDiameter,
  particleRadius,
  particleScale,
} from '../src/sim/catalog.ts';
import { SPECIES, SPECIES_COUNT } from '../src/sim/constants.ts';
import { Cell } from '../src/sim/cell.ts';
import { CellChemistry, vacuoleVisualRadius } from '../src/sim/cellChemistry.ts';

test('species catalog defines all 26 external species cleanly', () => {
  assert.equal(EXTERNAL_SPECIES.length, 26);
  assert.equal(SPECIES_COUNT, 26);
  assert.equal(SPECIES_RADII.length, 26);
  assert.equal(SPECIES_DECAY.length, 26);
  assert.equal(SPECIES_MATERIAL.length, 26);
  assert.equal(SPECIES_NAMES[SPECIES.NUTRIENT], 'Nutrient');
  assert.equal(SPECIES_NAMES[SPECIES.PHEROMONE], 'Pheromone');
  assert.equal(materialWeight(SPECIES.PHEROMONE), 0);
  assert.equal(materialWeight(SPECIES.NUTRIENT), 1);
});

test('particle scaling and merge limits match biological constraints', () => {
  assert.equal(particleScale(0.3), 1.0);
  assert.equal(particleScale(0.01), 0.8);
  assert.equal(particleScale(3.0), 1.7);
  assert.equal(particleDiameter(SPECIES.NUTRIENT, 0.3), particleRadius(SPECIES.NUTRIENT, 0.3) * 2);
  assert.equal(mergeLimit(SPECIES.NUTRIENT), 200.0);
  assert.equal(mergeLimit(SPECIES.WASTE), 5.0);
});

test('nutrientCapacity adds acidity-sensitive bonus up to 50% cap', () => {
  const neutralCap = nutrientCapacity(1.0, 1.0, 1.0, 1.0, 0.25);
  assert.ok(neutralCap > 2.0 && neutralCap <= 3.0);
  const harshCap = nutrientCapacity(1.0, 1.0, 1.0, 1.0, 0.9);
  assert.ok(neutralCap > harshCap);
  const starvedCap = nutrientCapacity(1.0, 0.2, 1.0, 0.3, 0.25);
  assert.equal(starvedCap, 0.5);
});

test('bindingThreshold tightens enzyme-waste and nutrient-nutrient away from acid=0.25', () => {
  const opt = bindingThreshold(SPECIES.ENZYME, SPECIES.WASTE, 0.25);
  const extreme = bindingThreshold(SPECIES.ENZYME, SPECIES.WASTE, 0.8);
  assert.equal(opt, 0.5);
  assert.ok(extreme > opt && extreme <= 0.96);
  assert.equal(bindingThreshold(SPECIES.ANTITOXIN, SPECIES.TOXIN, 0.9), 0.5);
});

test('CellChemistry bounded intracellular carriers digest aerobically and anaerobically', () => {
  const cell = new Cell(1, { x: 100, y: 100 }, 42);
  const emitted = [];
  const emitter = {
    time: 0,
    lightAt: () => 0.8,
    emitExternal: (kindKey, at, vel, amount, owner) => {
      emitted.push({ kindKey, at, vel, amount, owner });
    },
    recordSound: () => {},
  };

  for (let i = 0; i < 16; i++) {
    cell.chemistry.emit(cell, 'food', 0.4, { x: 0, y: 0 }, 1);
  }
  const foodCount = cell.chemistry.particles.filter((p) => p.alive && p.species === 'food').length;
  assert.ok(foodCount <= 12);

  const atpBefore = cell.energy;
  for (let i = 0; i < 60; i++) {
    emitter.time += 0.25;
    cell.chemistry.advance(cell, 0.25);
  }
  assert.ok(cell.energy > atpBefore || cell.biomass > 36);
  assert.ok(cell.chemistry instanceof CellChemistry);
});

test('CellChemistry keeps internal bubbles strictly within membrane across rotation and shrinkage while venting', () => {
  const cell = new Cell(2, { x: 400, y: 400 }, 99);
  cell.biomass = 0.7;
  cell.angle = 1.45;
  cell.addOrgan('feeding', 0, 'graze', false);
  cell.updateGeometry();
  for (let s = 0; s < 15; s++) {
    cell.membrane.step(0.05, cell.radius, { x: 0, y: 0 }, 0.5);
  }

  for (let i = 0; i < 6; i++) {
    cell.chemistry.emit(cell, 'food', 0.8, { x: 25 * Math.cos(i), y: 25 * Math.sin(i) }, 1);
    cell.chemistry.emit(cell, 'oxygen', 0.9, { x: 30 * Math.cos(i + 0.5), y: 30 * Math.sin(i + 0.5) }, 1);
    cell.chemistry.emit(cell, 'waste', 0.8, { x: 28, y: 0 }, 1);
  }

  const emitted = [];
  const emitter = {
    time: 0,
    lightAt: () => 0.8,
    emitExternal: (kindKey, at, vel, amount, owner) => emitted.push({ kindKey, at, vel, amount, owner }),
    investmentStrategy: () => 'balanced',
  };

  for (let t = 0; t < 50; t++) {
    cell.chemistry.advance(cell, 0.25);
    cell.chemistry.excrete(emitter, cell, 0.25);
    for (const p of cell.chemistry.particles) {
      if (!p.alive) continue;
      const edge = cell.supportLocal(Math.atan2(p.p.y, p.p.x));
      const visR = vacuoleVisualRadius(p.species, p.amount, cell.radius);
      const reach = Math.hypot(p.p.x, p.p.y) + visR;
      assert.ok(reach <= edge + 1e-3, `${p.species} bubble exceeded membrane: ${reach.toFixed(2)} > ${edge.toFixed(2)}`);
    }
  }
  assert.ok(emitted.length > 0, 'expected bubbles to still vent materials to environment');
});
