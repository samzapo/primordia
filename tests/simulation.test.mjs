import test from 'node:test';
import assert from 'node:assert/strict';
import { DT, MIN_LIVING_CELLS, SPECIES } from '../src/sim/constants.ts';
import { Simulation } from '../src/sim/simulation.ts';

test('Pond simulation initializes cleanly with seed ecosystem and runs 60 ticks without NaNs', () => {
  const sim = new Simulation(20261004, 0, false);
  sim.drainInitialParticles();

  const simGpu = new Simulation(20261004, 0, true);
  const gpuSeed = simGpu.drainInitialParticles();
  assert.ok(gpuSeed.length > 100);

  for (let tick = 0; tick < 60; tick++) {
    sim.stepHeadless(DT);
  }

  assert.ok(sim.cells.length >= MIN_LIVING_CELLS);
  assert.ok(sim.cpuParticles.length > 0);
  for (const c of sim.cells) {
    assert.ok(Number.isFinite(c.position.x) && Number.isFinite(c.position.y));
    assert.ok(Number.isFinite(c.energy) && Number.isFinite(c.biomass) && Number.isFinite(c.health));
  }
});

test('Family navigation receptors map into valid GPU query inputs', () => {
  const sim = new Simulation(777, 0, true);
  sim.drainInitialParticles();
  sim.player.addOrgan('family_toward', 0.4, 'graze', false);
  sim.player.addOrgan('family_away', -0.4, 'graze', false);
  sim.player.senseClock = 0;
  const input = sim.step(DT, null);
  const famQueries = input.queries.filter((q) => q.cellId === sim.player.id && q.mode === 6);
  assert.equal(famQueries.length, 2);
});

test('Player editing commands install, mutate, restore and recycle cleanly', () => {
  const sim = new Simulation(888, 0, false);
  sim.player.biomass = 120;
  assert.equal(sim.installOrgan('cilia', 1.5), true);
  assert.ok(sim.player.organs.length >= 3);
  const cilia = sim.player.organs[sim.player.organs.length - 1];
  // Recycle voluntarily refunds biomass
  assert.equal(sim.removeOrgan(sim.player.organs.length - 1), true);
  assert.equal(sim.player.organById(cilia.id), undefined);

  // Damage leaves a scar in lostOrgans, which restoreOrgan rebuilds
  assert.equal(sim.installOrgan('toxin', 1.5), true);
  const tox = sim.player.organs[sim.player.organs.length - 1];
  sim.player.damage(60, sim.player.angle + tox.a, 999);
  if (sim.player.lostOrgans.length > 0) {
    assert.equal(sim.restoreOrgan(sim.player.lostOrgans[0].id), true);
  }

  const photo = sim.player.organs.find((o) => o.kind === 'photosynthesis');
  assert.ok(photo);
  assert.equal(sim.mutateOrgan(photo.id, 'sun_leaf'), true);
  assert.equal(photo.mutation, 'sun_leaf');
  assert.equal(SPECIES.NUTRIENT, 0);
});
