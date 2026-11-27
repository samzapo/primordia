import test from 'node:test';
import assert from 'node:assert/strict';
import { SYNTH_VOICES, buildSynthBank } from '../src/audio/synthBank.ts';
import {
  BPM,
  ProgressiveScore,
  biomassTransposition,
  lineageMelodyDegrees,
  sectionForBar,
} from '../src/audio/score.ts';
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
});
