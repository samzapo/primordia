import test from 'node:test';
import assert from 'node:assert/strict';
import { SYNTH_VOICES, buildSynthBank } from '../src/audio/synthBank.ts';
import {
  BPM,
  ORGAN_MUSIC,
  ProgressiveScore,
  biomassTransposition,
  lineageMelodyDegrees,
  sectionForBar,
} from '../src/audio/score.ts';
import { resolveWaveOrigin } from '../src/audio/engine.ts';
import { ORGAN_KINDS } from '../src/sim/cell.ts';
import { Simulation } from '../src/sim/simulation.ts';

test('SynthBank deterministically generates all 17 finite non-silent waveforms at 22050 Hz', () => {
  const bankA = buildSynthBank();
  const bankB = buildSynthBank();
  for (const voice of SYNTH_VOICES) {
    const a = bankA[voice];
    const b = bankB[voice];
    assert.ok(a instanceof Float32Array && a.length >= 64);
    let maxAbs = 0;
    for (let i = 0; i < a.length; i++) {
      assert.equal(a[i], b[i]);
      assert.ok(Number.isFinite(a[i]));
      maxAbs = Math.max(maxAbs, Math.abs(a[i]));
    }
    assert.ok(maxAbs > 0.05 && maxAbs <= 1.0, `voice ${voice} amplitude out of range: ${maxAbs}`);
  }
});

test('ProgressiveScore structure runs 128 BPM 64-bar sections, biomass transposition and zero anonymous notes', () => {
  assert.equal(BPM, 128);
  assert.equal(sectionForBar(0), 'emerge');
  assert.equal(sectionForBar(12), 'groove');
  assert.equal(sectionForBar(28), 'lift');
  assert.equal(sectionForBar(42), 'break');
  assert.equal(sectionForBar(52), 'build');
  assert.equal(sectionForBar(62), 'return');

  assert.equal(biomassTransposition(80), 0);
  assert.equal(biomassTransposition(200), -3);
  assert.equal(biomassTransposition(1600), -12);

  const sim = new Simulation(20261004, 0, false);
  const mel = lineageMelodyDegrees(sim.seedValue, sim.player.lineageId());
  assert.equal(mel.length, 6);

  const score = new ProgressiveScore();
  score.resetHistory(sim);
  const notes = score.evaluateStep(128, 1.0, sim, sim.player);
  assert.ok(notes.length > 0);
  for (const n of notes) {
    assert.ok(SYNTH_VOICES.includes(n.voice));
    assert.ok(n.cellId >= 0);
  }

  // Verify 2-bar tropical Dm -> Bb Major chord root shift in groove section (bar 8 step 128 vs bar 10 step 160)
  sim.player.addOrgan('feeding', 0, 'graze', false);
  const dmNotes = score.evaluateStep(128, 1.0, sim, sim.player);
  const bbNotes = score.evaluateStep(160, 2.0, sim, sim.player);
  assert.ok(dmNotes.length >= 1 && bbNotes.length >= 1);
  const dmPitch = dmNotes.find((n) => n.lane > 0);
  const bbPitch = bbNotes.find((n) => n.lane > 0);
  assert.ok(dmPitch && bbPitch);
  assert.equal(((bbPitch.pitchSemitones - dmPitch.pitchSemitones) % 12 + 12) % 12, 8);
});

test('Nucleus-only cells play bassline/sub-bass/background only; added organelles add motifs and radiate waves from each organ', () => {
  for (const kind of ORGAN_KINDS) {
    assert.ok(SYNTH_VOICES.includes(ORGAN_MUSIC[kind].voice));
  }

  const sim = new Simulation(20261004, 0, false);
  // Isolate player cell with only its nucleus (zero installed organelles)
  sim.cells = [sim.player];
  sim.player.organs = [];
  sim.player.biomass = 120;
  sim.player.updateGeometry();

  const score = new ProgressiveScore();
  score.resetHistory(sim);

  const nucleusOnlyVoices = new Set();
  for (let step = 128; step < 144; step++) {
    for (const n of score.evaluateStep(step, step * 0.1, sim, sim.player)) {
      nucleusOnlyVoices.add(n.voice);
      assert.equal(n.organId, null);
    }
  }
  assert.deepEqual([...nucleusOnlyVoices].sort(), ['kick', 'pad', 'sub']);

  // Adding 1st, 2nd, 3rd organelles sequentially adds motif notes keyed to each organelle's id & world position
  assert.ok(sim.player.addOrgan('feeding', 0, 'graze', false));
  const feedingOrgan = sim.player.organs[0];
  const oneOrganIds = new Set();
  for (let step = 128; step < 144; step++) {
    for (const n of score.evaluateStep(step, step * 0.1, sim, sim.player)) {
      if (n.organId !== null) oneOrganIds.add(n.organId);
    }
  }
  assert.ok(oneOrganIds.has(feedingOrgan.id));

  assert.ok(sim.player.addOrgan('photosynthesis', Math.PI * 0.65, 'graze', false));
  assert.ok(sim.player.addOrgan('photosynthesis', -Math.PI * 0.65, 'graze', false));
  assert.ok(sim.player.addOrgan('propulsion', Math.PI, 'graze', false));

  const multiOrganNotes = [];
  for (let step = 128; step < 144; step++) {
    for (const n of score.evaluateStep(step, step * 0.1, sim, sim.player)) {
      if (n.organId !== null && !n.isBackground) multiOrganNotes.push(n);
    }
  }
  const heardOrganIds = new Set(multiOrganNotes.map((n) => n.organId));
  for (const organ of sim.player.organs) {
    assert.ok(heardOrganIds.has(organ.id), `expected motif notes from organ ${organ.kind}#${organ.id}`);
  }

  // Wave origins track each individual emitting organelle instead of jumping to cell center
  sim.player.angle = 0.85;
  for (const organ of sim.player.organs) {
    const expectedPos = sim.player.organPosition(organ);
    const origin = resolveWaveOrigin(sim, {
      cellId: sim.player.id,
      organId: organ.id,
      x: 0,
      y: 0,
    });
    assert.ok(origin);
    assert.ok(Math.hypot(origin.x - expectedPos.x, origin.y - expectedPos.y) < 1e-4);
    assert.ok(origin.baseR < sim.player.extent());
  }
});
