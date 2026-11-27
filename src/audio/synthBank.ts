import { SeededRng } from '../sim/rng.ts';
import { TAU, clamp, lerp } from '../sim/constants.ts';

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

// Authoritative reference MIDI notes (36 = C2, 60 = C4) aligned with Primordia's tropical synthesis bank
export const VOICE_BASE_NOTE: Record<SynthVoice, number> = {
  kick: 36,
  hat: 60,
  clap: 60,
  sub: 36,
  flagellum: 60,
  pad: 60,
  pore: 60,
  enzyme: 60,
  graze: 60,
  perc: 60,
  photo: 60,
  toxin: 60,
  antitoxin: 60,
  acid: 60,
  mitosis: 60,
  death: 36,
  cilia: 60,
};

const VOICE_LENGTH: Record<SynthVoice, number> = {
  kick: 0.42,
  hat: 0.09,
  clap: 0.20,
  sub: 0.42,
  flagellum: 0.48,
  pad: 0.82,
  pore: 0.38,
  enzyme: 1.25,
  graze: 0.55,
  perc: 0.50,
  photo: 0.92,
  toxin: 0.64,
  antitoxin: 1.10,
  acid: 0.46,
  mitosis: 2.30,
  death: 2.20,
  cilia: 0.38,
};

// Generation order matches original RNG consumption order (0..16)
const SYNTH_ORDER: readonly SynthVoice[] = [
  'kick',
  'hat',
  'clap',
  'sub',
  'flagellum',
  'pad',
  'pore',
  'enzyme',
  'graze',
  'perc',
  'photo',
  'toxin',
  'antitoxin',
  'acid',
  'mitosis',
  'death',
  'cilia',
];

export function buildSynthBank(sampleRate = SYNTH_SAMPLE_RATE, seed = SYNTH_SEED): SynthBank {
  const rng = new SeededRng(seed);
  const bank = {} as Record<SynthVoice, Float32Array>;

  for (let idx = 0; idx < SYNTH_ORDER.length; idx++) {
    const voice = SYNTH_ORDER[idx];
    const lenSec = VOICE_LENGTH[voice];
    const baseNote = VOICE_BASE_NOTE[voice];
    const count = Math.ceil(lenSec * sampleRate);
    const data = new Float32Array(count);
    const f = 440.0 * Math.pow(2, (baseNote - 69) / 12.0);
    let filtered = 0.0;
    let noisePrevious = 0.0;

    for (let i = 0; i < count; i++) {
      const t = i / sampleRate;
      const p = TAU * f * t;
      const noise = rng.randf() * 2 - 1;
      let value = 0.0;
      let attack = Math.min(1.0, t / 0.006);
      let end = Math.min(1.0, (lenSec - t) / 0.035);

      switch (idx) {
        case 0: {
          // Rounded kick, swept body and short click
          const phase = TAU * (44 * t + 74 * 0.026 * (1 - Math.exp(-t / 0.026)));
          value = Math.sin(phase) * Math.exp(-t * 10) + noise * Math.exp(-t * 160) * 0.2;
          attack = Math.min(1.0, t / 0.0015);
          break;
        }
        case 1:
          // Crisp high-passed noise hat
          value = (noise - noisePrevious) * 0.35 * Math.exp(-t * 48);
          attack = Math.min(1.0, t / 0.001);
          break;
        case 2: {
          // Three short clap impulses over a soft body
          let bursts = Math.exp(-t * 75);
          if (t >= 0.011) bursts += Math.exp(-(t - 0.011) * 75) * 0.6;
          if (t >= 0.023) bursts += Math.exp(-(t - 0.023) * 75) * 0.6;
          value = noise * bursts * 0.55 + Math.sin(TAU * 180 * t) * Math.exp(-t * 32) * 0.16;
          break;
        }
        case 3:
          // Warm plucked tropical deep-house bass
          value = (Math.sin(p) + 0.25 * Math.sin(p * 2) + 0.12 * Math.sin(p * 3)) * Math.exp(-t * 9) * 0.72;
          break;
        case 4:
          // Propulsion bright pluck
          value = (Math.sin(p) + 0.35 * Math.sin(p * 2) + 0.18 * Math.sin(p * 3)) * Math.exp(-t * 7) * 0.68;
          break;
        case 5:
          // Cortex warm chorus brass
          value = (Math.sin(p) + 0.22 * Math.sin(p * 1.003) + 0.25 * Math.sin(p * 2)) * Math.exp(-t * 4) * 0.65;
          break;
        case 6:
          // Spike FM bite
          value = Math.sin(p + 2.4 * Math.exp(-t * 12) * Math.sin(p * 2)) * Math.exp(-t * 9) * 0.75;
          break;
        case 7:
          // Repair steel-bell chime
          value = (Math.sin(p) + 0.35 * Math.sin(p * 2.001) * Math.exp(-t * 5)) * Math.exp(-t * 3.7) * 0.64;
          break;
        case 8:
          // Feeding bright marimba mallet
          value = Math.sin(p + 1.2 * Math.exp(-t * 18) * Math.sin(p * 3)) * Math.exp(-t * 8) * 0.8;
          break;
        case 9:
          // Flight & hunting crystal signal
          value = (Math.sin(p) + 0.25 * Math.sin(p * 3) + 0.1 * Math.sin(p * 5)) * Math.exp(-t * 8) * 0.68;
          break;
        case 10:
          // Light glass marimba shimmer
          value = (Math.sin(p) + 0.28 * Math.sin(p * 2) + 0.12 * Math.sin(p * 4)) * Math.exp(-t * 4.8) * 0.65;
          break;
        case 11:
          // Toxin deep FM growl
          value = Math.sin(p + 1.8 * Math.sin(p * 0.5) * Math.exp(-t * 3)) * Math.exp(-t * 5) * 0.65;
          break;
        case 12:
          // Neutralizer clean chime
          value = (Math.sin(p) + 0.18 * Math.sin(p * 3)) * Math.exp(-t * 3.4) * 0.7;
          break;
        case 13:
          // Bright acid harmonic chirp
          value =
            (Math.sin(p) + Math.sin(p * 2) * Math.exp(-t * 15) * 0.55 + Math.sin(p * 3) * Math.exp(-t * 20) * 0.3) *
            Math.exp(-t * 8) *
            0.6;
          break;
        case 14:
          value = (Math.sin(p) + Math.sin(p * 1.004) * 0.35 + Math.sin(p * 0.998) * 0.35 + Math.sin(p * 2) * 0.12) * 0.39;
          attack = Math.min(1.0, t / 0.22);
          end = Math.min(end, (lenSec - t) / 0.55);
          break;
        case 15:
          value = (Math.sin(p) + 0.26 * Math.sin(p * 0.5) + 0.23 * Math.sin(p * 1.006)) * 0.63;
          attack = Math.min(1.0, t / 0.13);
          end = Math.min(end, (lenSec - t) / 0.6);
          break;
        case 16:
          // Ciliary airy flutter
          value = (Math.sin(p) + 0.28 * Math.sin(p * 4)) * Math.exp(-t * 10) * (0.7 + 0.3 * Math.cos(TAU * 19 * t)) * 0.65;
          break;
      }

      filtered = lerp(filtered, value, idx === 1 || idx === 2 ? 0.74 : 0.55);
      data[i] = filtered * attack * clamp(end, 0, 1);
      noisePrevious = noise;
    }
    let maxAbs = 0;
    for (let i = 0; i < count; i++) {
      maxAbs = Math.max(maxAbs, Math.abs(data[i]));
    }
    if (maxAbs > 0.98) {
      const inv = 0.96 / maxAbs;
      for (let i = 0; i < count; i++) data[i] *= inv;
    }
    bank[voice] = data;
  }

  return bank;
}
