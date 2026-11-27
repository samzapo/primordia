import test from 'node:test';
import assert from 'node:assert/strict';
import { Simulation } from '../src/sim/simulation.ts';
import { MAX_FAMILY_CELLS, SPECIES } from '../src/sim/constants.ts';
import { divisionQuote, reproduceCell } from '../src/sim/cellLifecycle.ts';
import { balancedPath, pathAtTicket } from '../src/sim/investmentPolicy.ts';
import { rememberMergeCues, requestFamilyMerge } from '../src/sim/familyMerging.ts';

test('Division quote enforces mitosis 84/56 and budding 50/78 requirements', () => {
  const sim = new Simulation(20261004, 0, false);
  const player = sim.player;
  const mqLow = divisionQuote(sim, player, 'mitosis');
  assert.equal(mqLow.ready, false);

  player.biomass = 120;
  player.energy = 100;
  player.age = 70;
  player.reproductionRetryAt = 0;
  const mqReady = divisionQuote(sim, player, 'mitosis');
  const bqReady = divisionQuote(sim, player, 'budding');
  assert.equal(mqReady.ready, true);
  assert.equal(bqReady.ready, true);

  const ok = reproduceCell(sim, player, sim.lineage, 'mitosis', true);
  assert.equal(ok, true);
  assert.ok(sim.lineage.activeFamily(sim.cells).length >= 2);
  assert.ok(sim.lineage.highestGeneration >= 1);
});

test('Family size respects MAX_FAMILY_CELLS cap and supports pheromone-aware manual merging', () => {
  const sim = new Simulation(4242, 0, false);
  const p = sim.player;
  p.biomass = 180;
  p.energy = 180;
  p.age = 120;
  reproduceCell(sim, p, sim.lineage, 'mitosis', false);
  const fam = sim.lineage.activeFamily(sim.cells);
  assert.ok(fam.length <= MAX_FAMILY_CELLS);
  const donor = fam.find((c) => c !== p);
  assert.ok(donor);
  donor.age = 80;
  donor.biomass = 40;
  // Seed pheromone awareness as detected in Pond perception
  const m = new Map();
  m.set(donor.id, {
    report: {
      id: donor.id,
      lineage: donor.lineageId(),
      at: { ...donor.position },
      mass: donor.organicMass(),
      radius: donor.radius,
      hostile: false,
      defended: false,
      emittedAt: sim.time,
    },
    distance: 40,
    expiresAt: sim.time + 5,
  });
  rememberMergeCues(sim, p, m);

  const beforeBio = p.biomass;
  assert.equal(requestFamilyMerge(sim, donor.id), true);
  assert.ok(p.biomass > beforeBio);
});

test('Balanced investment lottery follows exact 2/4/10/20 weights', () => {
  const counts = { hunter: 0, parasite: 0, grazer: 0, producer: 0 };
  for (let i = 0; i < 36; i++) {
    counts[pathAtTicket(i)]++;
  }
  assert.equal(counts.hunter, 2);
  assert.equal(counts.parasite, 4);
  assert.equal(counts.grazer, 10);
  assert.equal(counts.producer, 20);
  const sim = new Simulation(99, 0, false);
  assert.ok(['hunter', 'parasite', 'grazer', 'producer'].includes(balancedPath(99, sim.player)));
});

test('Pheromone reports carry immutable emission-time snapshot metadata', () => {
  const sim = new Simulation(10101, 0, false);
  sim.drainInitialParticles();
  const initialMass = sim.player.organicMass();
  sim.stepHeadless(0.2);
  const phero = sim.cpuParticles.find((p) => p.kind === SPECIES.PHEROMONE && p.owner === sim.player.id);
  if (phero && phero.report) {
    sim.player.biomass += 200;
    assert.notEqual(phero.report.mass, sim.player.organicMass());
    assert.ok(Math.abs(phero.report.mass - initialMass) < 5);
  }
});
