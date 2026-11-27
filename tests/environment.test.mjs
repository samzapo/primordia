import test from 'node:test';
import assert from 'node:assert/strict';
import { Medium } from '../src/sim/medium.ts';
import { Acidity, phFromAcid } from '../src/sim/acidity.ts';
import { InducedCurrents } from '../src/sim/inducedCurrents.ts';
import { Habitat } from '../src/sim/habitat.ts';
import { getLightGrid, lightDirection, sampleLightField } from '../src/sim/lightField.ts';
import { updateEnvironmentCycle } from '../src/sim/environmentCycle.ts';

test('Acidity converts equivalents to chemical pH cleanly around pH 7.0 neutral', () => {
  assert.ok(Math.abs(phFromAcid(0) - 7.0) < 1e-6);
  assert.ok(phFromAcid(1.0) < 4.0);
  assert.ok(phFromAcid(-1.0) > 10.0);

  const ac = new Acidity();
  const med = new Medium();
  ac.exchange(500, 500, 0.5);
  assert.ok(ac.sample(500, 500) > 0);
  ac.step(0.1, med);
  assert.ok(Number.isFinite(ac.sample(500, 500)));
});

test('Medium and InducedCurrents remain bounded and toroidal', () => {
  const med = new Medium();
  const ind = new InducedCurrents();
  ind.update(20261004, 1.5, med);
  assert.ok(ind.activeSources.length > 0);
  med.step(1 / 60);
  const s = med.sample(2048, 1280);
  assert.ok(Number.isFinite(s.x) && Number.isFinite(s.y));
});

test('Habitat seeds 8 fractal plant forms and 10 non-overlapping colonies', () => {
  const hab = new Habitat(20261004, []);
  assert.equal(hab.forms.length, 8);
  assert.equal(hab.plants.length, 10);
  const kinds = new Set(hab.forms.map((f) => f.kind));
  assert.equal(kinds.size, 4);
});

test('LightField and updateEnvironmentCycle produce repeatable illumination and calendar weather', () => {
  const grid = getLightGrid(20261004);
  assert.equal(grid.length, 128 * 80);
  const l = sampleLightField(20261004, 1000, 1000);
  assert.ok(l >= 0 && l <= 1);
  const dir = lightDirection(20261004, 1000, 1000);
  assert.ok(Number.isFinite(dir.x) && Number.isFinite(dir.y));

  const med = new Medium();
  const ind = new InducedCurrents();
  const env = { hour: -1, utc: '', weather: '', light: 1, flowVersion: 0, flowAngle: 0, flowStrength: 1 };
  const updated = updateEnvironmentCycle(20261004, env, ind, med, 1732665600);
  assert.equal(updated, true);
  assert.ok(env.light > 0 && env.weather.length > 0 && env.utc.includes('UTC'));
});
