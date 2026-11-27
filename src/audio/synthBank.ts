import { SeededRng } from '../sim/rng.ts';
import { TAU } from '../sim/constants.ts';

export const SYNTH_SAMPLE_RATE = 22050;
export const SYNTH_SEED = 1282026;

export const SYNTH_VOICES = [
  'kick',
  'sub',
  'hat',
  'clap',
  'perc',
  'graze',
  'cilia',
  'flagellum',
  'toxin',
  'pore',
  'photo',
  'acid',
  'enzyme',
  'antitoxin',
  'mitosis',
  'death',
  'pad',
] as const;

export type SynthVoice = (typeof SYNTH_VOICES)[number];
export type SynthBank = Record<SynthVoice, Float32Array>;

function makeSamples(
  durationSec: number,
  sampleRate: number,
  fill: (i: number, t: number, len: number, rng: SeededRng) => number,
  rng: SeededRng,
): Float32Array {
  const len = Math.max(64, Math.floor(durationSec * sampleRate));
  const out = new Float32Array(len);
  let maxAbs = 0;
  for (let i = 0; i < len; i++) {
    const t = i / sampleRate;
    const v = fill(i, t, len, rng);
    out[i] = v;
    if (Math.abs(v) > maxAbs) maxAbs = Math.abs(v);
  }
  if (maxAbs > 1.0) {
    const inv = 0.96 / maxAbs;
    for (let i = 0; i < len; i++) out[i] *= inv;
  }
  // Short fade-in/out to prevent clicks
  const fade = Math.min(48, len >> 2);
  for (let i = 0; i < fade; i++) {
    const u = i / fade;
    out[i] *= u;
    out[len - 1 - i] *= u;
  }
  return out;
}

export function buildSynthBank(sampleRate = SYNTH_SAMPLE_RATE, seed = SYNTH_SEED): SynthBank {
  const rng = new SeededRng(seed);

  // 1. Kick (D2-centric punch with fast pitch sweep & soft clip)
  let kickPhase = 0;
  const kick = makeSamples(
    0.42,
    sampleRate,
    (_i, t) => {
      const freq = 42 + 125 * Math.exp(-t * 36) + 28 * Math.exp(-t * 9);
      kickPhase += (TAU * freq) / sampleRate;
      const body = Math.sin(kickPhase) * Math.exp(-t * 6.5);
      const click = (rng.randf() * 2 - 1) * Math.exp(-t * 160) * 0.35;
      return Math.tanh((body + click) * 1.45) * 0.92;
    },
    rng,
  );

  // 2. Sub bass (reference pitch 55 Hz A1 / 73.42 Hz D2-tunable)
  const subRef = 73.416;
  const sub = makeSamples(
    0.45,
    sampleRate,
    (_i, t) => {
      const env = Math.min(1, t / 0.008) * Math.exp(-t * 4.2);
      const fund = Math.sin(TAU * subRef * t);
      const warm = Math.sin(TAU * subRef * 2 * t) * 0.18 * Math.exp(-t * 8);
      return (fund + warm) * env * 0.85;
    },
    rng,
  );

  // 3. Hat (crispy metallic partials + high-passed noise)
  let prevNoise = 0;
  const hat = makeSamples(
    0.11,
    sampleRate,
    (_i, t) => {
      const n = rng.randf() * 2 - 1;
      const hp = n - prevNoise * 0.86;
      prevNoise = n;
      const metal =
        Math.sin(TAU * 4850 * t) * 0.22 +
        Math.sin(TAU * 6310 * t) * 0.18 +
        Math.sin(TAU * 7920 * t) * 0.14;
      return (hp * 0.55 + metal) * Math.exp(-t * 42) * 0.72;
    },
    rng,
  );

  // 4. Clap (micro-bursts + diffused snappy tail)
  let clapLp = 0;
  const clap = makeSamples(
    0.22,
    sampleRate,
    (_i, t) => {
      const n = rng.randf() * 2 - 1;
      clapLp = clapLp * 0.45 + n * 0.55;
      const bp = clapLp - (clapLp * 0.35);
      const bursts =
        Math.exp(-Math.pow((t - 0.0) * 180, 2)) +
        Math.exp(-Math.pow((t - 0.011) * 180, 2)) +
        Math.exp(-Math.pow((t - 0.021) * 160, 2));
      const tail = Math.exp(-Math.max(0, t - 0.022) * 18) * 0.55;
      return bp * (bursts * 0.6 + tail) * 0.78;
    },
    rng,
  );

  // 5. Perc (organic wood/membrane tom)
  let percPhase = 0;
  const perc = makeSamples(
    0.15,
    sampleRate,
    (_i, t) => {
      const f = 146.83 * (1 + 0.85 * Math.exp(-t * 48));
      percPhase += (TAU * f) / sampleRate;
      const fm = Math.sin(TAU * f * 1.5 * t) * 0.6 * Math.exp(-t * 32);
      return Math.sin(percPhase + fm) * Math.exp(-t * 22) * 0.78;
    },
    rng,
  );

  // 6. Graze (tuned 293.66 Hz D4 gentle nutrient chime)
  const refD4 = 293.665;
  const graze = makeSamples(
    0.24,
    sampleRate,
    (_i, t) => {
      const env = Math.min(1, t / 0.005) * Math.exp(-t * 14);
      const s =
        Math.sin(TAU * refD4 * t) +
        Math.sin(TAU * refD4 * 2 * t) * 0.32 * Math.exp(-t * 18) +
        Math.sin(TAU * refD4 * 3 * t) * 0.12 * Math.exp(-t * 28);
      return s * env * 0.65;
    },
    rng,
  );

  // 7. Cilia (airy swept sheen)
  const cilia = makeSamples(
    0.20,
    sampleRate,
    (_i, t) => {
      const n = rng.randf() * 2 - 1;
      const env = Math.sin(Math.min(Math.PI, (t / 0.2) * Math.PI));
      const shimmer = Math.sin(TAU * (587.33 + 120 * Math.sin(t * 28)) * t);
      return (shimmer * 0.45 + n * 0.25) * env * 0.45;
    },
    rng,
  );

  // 8. Flagellum (undulating soft pulse at D3 = 146.83 Hz)
  const flagellum = makeSamples(
    0.28,
    sampleRate,
    (_i, t) => {
      const lfo = 1 + 0.06 * Math.sin(TAU * 12 * t);
      const env = Math.sin(Math.min(Math.PI, (t / 0.28) * Math.PI));
      return (Math.sin(TAU * 146.83 * lfo * t) + 0.3 * Math.sin(TAU * 293.66 * t)) * env * 0.58;
    },
    rng,
  );

  // 9. Toxin (edgy FM squelch)
  const toxin = makeSamples(
    0.26,
    sampleRate,
    (_i, t) => {
      const f = 146.83 * (1 - 0.25 * t);
      const mod = Math.sin(TAU * f * 2.41 * t) * (1.8 * Math.exp(-t * 9));
      const env = Math.exp(-t * 10);
      return Math.tanh(Math.sin(TAU * f * t + mod) * 1.4) * env * 0.65;
    },
    rng,
  );

  // 10. Pore (hollow resonant bell)
  const pore = makeSamples(
    0.24,
    sampleRate,
    (_i, t) => {
      const env = Math.exp(-t * 13);
      return (Math.sin(TAU * 293.665 * t) * 0.6 + Math.sin(TAU * 293.665 * 2.756 * t) * 0.35) * env * 0.62;
    },
    rng,
  );

  // 11. Photo (luminous major add9 sparkle centered D4)
  const photo = makeSamples(
    0.48,
    sampleRate,
    (_i, t) => {
      const env = Math.min(1, t / 0.04) * Math.exp(-t * 4.5);
      const c =
        Math.sin(TAU * 293.665 * t) +
        Math.sin(TAU * 440.0 * t) * 0.6 +
        Math.sin(TAU * 659.25 * t) * 0.35;
      return c * env * 0.42;
    },
    rng,
  );

  // 12. Acid (303-like resonant sweep D3)
  let acPhase = 0;
  const acid = makeSamples(
    0.24,
    sampleRate,
    (_i, t) => {
      const base = 146.83;
      const sweep = base * (1 + 2.5 * Math.exp(-t * 18));
      acPhase += (TAU * sweep) / sampleRate;
      const saw = ((base * t) % 1) * 2 - 1;
      return Math.tanh((saw * 0.45 + Math.sin(acPhase) * 0.75) * 1.5) * Math.exp(-t * 11) * 0.62;
    },
    rng,
  );

  // 13. Enzyme (bubbly catalytic pitch bend D4)
  let enzPhase = 0;
  const enzyme = makeSamples(
    0.20,
    sampleRate,
    (_i, t) => {
      const f = 293.665 * (0.7 + 0.65 * (1 - Math.exp(-t * 22)));
      enzPhase += (TAU * f) / sampleRate;
      return Math.sin(enzPhase) * Math.exp(-t * 13) * 0.65;
    },
    rng,
  );

  // 14. Antitoxin (clean fifth swell)
  const antitoxin = makeSamples(
    0.28,
    sampleRate,
    (_i, t) => {
      const env = Math.min(1, t / 0.03) * Math.exp(-t * 6.5);
      return (Math.sin(TAU * 293.665 * t) + Math.sin(TAU * 440 * t) * 0.65) * env * 0.55;
    },
    rng,
  );

  // 15. Mitosis (dual-tone octave harmonic bloom)
  const mitosis = makeSamples(
    0.65,
    sampleRate,
    (_i, t) => {
      const env = Math.min(1, t / 0.03) * Math.exp(-t * 3.8);
      const a = Math.sin(TAU * 293.665 * t);
      const b = Math.sin(TAU * 587.33 * (1 + 0.003 * Math.sin(t * 14)) * t);
      const c = Math.sin(TAU * 440.0 * t) * 0.5;
      return (a + b * 0.7 + c) * env * 0.48;
    },
    rng,
  );

  // 16. Death (descending glassy sigh)
  let dPhase = 0;
  const death = makeSamples(
    0.75,
    sampleRate,
    (_i, t) => {
      const f = 329.63 * Math.exp(-t * 1.6);
      dPhase += (TAU * f) / sampleRate;
      return (Math.sin(dPhase) + 0.35 * Math.sin(dPhase * 2.01)) * Math.exp(-t * 3.2) * 0.58;
    },
    rng,
  );

  // 17. Pad (rich detuned chorus voice at D3 = 146.83 Hz)
  const pad = makeSamples(
    0.95,
    sampleRate,
    (_i, t) => {
      const env = Math.sin(Math.min(Math.PI, (t / 0.95) * Math.PI));
      const f1 = 146.83 * 0.996;
      const f2 = 146.83 * 1.004;
      const f3 = 220.0;
      const v =
        Math.sin(TAU * f1 * t) +
        Math.sin(TAU * f2 * t) +
        0.45 * Math.sin(TAU * f3 * t) +
        0.2 * Math.sin(TAU * 293.665 * t);
      return v * env * 0.34;
    },
    rng,
  );

  return {
    kick,
    sub,
    hat,
    clap,
    perc,
    graze,
    cilia,
    flagellum,
    toxin,
    pore,
    photo,
    acid,
    enzyme,
    antitoxin,
    mitosis,
    death,
    pad,
  };
}
