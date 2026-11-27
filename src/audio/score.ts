import type { Cell } from '../sim/cell.ts';
import { SeededRng } from '../sim/rng.ts';
import { clamp, offsetVec } from '../sim/constants.ts';
import type { Simulation } from '../sim/simulation.ts';
import { VOICE_BASE_NOTE, type SynthVoice } from './synthBank.ts';

export const BPM = 128;
export const STEPS_PER_BAR = 16;
export const CYCLE_BARS = 64;
export const STEP_SECONDS = 60.0 / BPM / 4.0;
export const SWING_AMOUNT = 0.055;

// D minor -> B-flat major -> F major -> C major (2 bars per chord)
export const PROGRESSION_ROOTS = [0, 8, 3, 10] as const;
// Legacy Aeolian intervals exported cleanly for harmonic compatibility
export const SCALE_AEOLIAN = [0, 2, 3, 5, 7, 8, 10] as const;

export const MOTIF_BEATS = [0, 3, 6, 10, 12, 15] as const;

const TRACKED_KINDS = [
  'propulsion',
  'protection',
  'poreforming',
  'regenerative',
  'feeding',
  'sensing',
  'photosynthesis',
  'toxin',
  'neutralizing',
  'acidifying',
  'hunting',
  'cilia',
] as const;

const ORGAN_VOICES: readonly SynthVoice[] = [
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
  'perc',
  'cilia',
];

const ORGAN_PATTERNS: readonly (readonly number[])[] = [
  [2, 6, 10, 14],
  [0, 7, 12],
  [0, 3, 6, 10, 14],
  [3, 11],
  [0, 3, 8, 10, 14],
  [1, 4, 9, 12],
  [0, 2, 5, 8, 10, 13],
  [3, 6, 11, 14],
  [5, 13],
  [0, 3, 7, 10, 15],
  [2, 5, 8, 14],
  [1, 3, 5, 9, 11, 13],
];

const ORGAN_DEGREES: readonly number[] = [0, 7, 0, 12, 3, 10, 7, 0, 12, 3, 5, 2];

export type CycleSection = 'emerge' | 'groove' | 'lift' | 'break' | 'build' | 'return';

export interface ScheduledNote {
  lane: number; // 0..6
  voice: SynthVoice;
  semitonesFromRef: number;
  pitchSemitones: number; // MIDI - 36 for wave ripple color
  gain: number;
  pan: number;
  audioTime: number;
  cellId: number;
  x: number;
  y: number;
  cutoffHz: number;
  acidDrive: number;
}

export function sectionForBar(bar: number): CycleSection {
  const b = ((bar % CYCLE_BARS) + CYCLE_BARS) % CYCLE_BARS;
  if (b < 8) return 'emerge';
  if (b < 24) return 'groove';
  if (b < 40) return 'lift';
  if (b < 48) return 'break';
  if (b < 60) return 'build';
  return 'return';
}

export function biomassTransposition(organicMass: number): number {
  if (organicMass <= 100) return 0;
  const doublings = Math.log2(organicMass / 100);
  const steps = Math.floor(doublings) * 3;
  return -clamp(steps, 0, 12);
}

export function lineageMelodyDegrees(seedValue: number, lineage: number): number[] {
  const rng = new SeededRng((Math.imul(seedValue | 0, 65537) ^ Math.imul(lineage | 0, 104729)) | 0);
  const choices = [0, 3, 5, 7, 10, 12];
  const contour = [0, 7, 12, 3, 10, 7];
  for (let i = 1; i < 5; i++) {
    contour[i] = choices[rng.nextUint() % choices.length];
  }
  return contour;
}

function panFromFocus(focus: Cell, atX: number, atY: number): number {
  const dx = offsetVec(focus.position, { x: atX, y: atY }).x;
  return clamp(dx / 360, -0.85, 0.85);
}

interface ObservedSource {
  cell: Cell;
  lane: number;
  gain: number;
  pan: number;
  mass: number;
  counts: Float32Array;
  motif: number[];
  light: number;
  acid: number;
  rank: number;
}

export class ProgressiveScore {
  private lastSoundSeq = 0;
  private channelCellIds: number[] = [-1, -1, -1, -1, -1, -1, -1];

  resetHistory(sim: Simulation): void {
    this.lastSoundSeq = sim.soundSequence;
  }

  private collectSources(sim: Simulation, focus: Cell, paused: boolean): ObservedSource[] {
    const candidates: ObservedSource[] = [];
    for (const c of sim.cells) {
      if (c.dead) continue;
      const off = offsetVec(focus.position, c.position);
      const dist = Math.hypot(off.x, off.y);
      const prox = c === focus ? 1.0 : Math.pow(clamp(1 - dist / (700 + c.extent()), 0, 1), 1.65);
      if (prox < 0.005) continue;

      const counts = new Float32Array(TRACKED_KINDS.length);
      for (const organ of c.organs) {
        if (organ.hp <= 0) continue;
        const vKind = organ.kind === 'toxin_sac' ? 'toxin' : organ.kind;
        const kIdx = TRACKED_KINDS.indexOf(vKind as (typeof TRACKED_KINDS)[number]);
        if (kIdx >= 0) {
          counts[kIdx] += 0.35 + 0.65 * clamp(organ.hp / Math.max(organ.maxHp, 0.01), 0, 1);
        }
      }
      // Circulating digestive vacuoles softly trigger feeding marimba mallets
      if (c.substrate > 0.05 && counts[4] < 0.8) {
        counts[4] = Math.max(counts[4], 1.0);
      }
      const weight = c.organicMass();
      const baseGain = prox * (c === focus ? 0.62 : 0.1) * (paused ? 0.65 : 1.0);
      candidates.push({
        cell: c,
        lane: 1,
        gain: baseGain,
        pan: panFromFocus(focus, c.position.x, c.position.y),
        mass: weight,
        counts,
        motif: lineageMelodyDegrees(sim.seedValue, c.lineageId()),
        light: c === focus ? sim.lightAt(c.position) : sim.lightAt(c.position) * 0.25 + 0.3,
        acid: Math.abs(sim.acidity.sample(c.position.x, c.position.y)),
        rank: prox * (1 + Math.min(2, weight / 180) * 0.3),
      });
    }

    candidates.sort((a, b) => (Math.abs(b.rank - a.rank) > 1e-5 ? b.rank - a.rank : a.cell.id - b.cell.id));
    if (candidates.length > 6) {
      const fIdx = candidates.findIndex((s) => s.cell.id === focus.id);
      const top = candidates.slice(0, 6);
      if (fIdx >= 6) top[5] = candidates[fIdx];
      candidates.length = 0;
      candidates.push(...top);
    }

    const used = new Set<number>();
    for (const s of candidates) {
      let matched = -1;
      for (let lane = 1; lane <= 6; lane++) {
        if (this.channelCellIds[lane] === s.cell.id) {
          matched = lane;
          break;
        }
      }
      if (matched >= 1) {
        s.lane = matched;
        used.add(matched);
      } else {
        s.lane = -1;
      }
    }
    for (const s of candidates) {
      if (s.lane >= 1) continue;
      for (let lane = 1; lane <= 6; lane++) {
        if (!used.has(lane)) {
          s.lane = lane;
          used.add(lane);
          break;
        }
      }
      if (s.lane < 1) s.lane = 1;
    }

    this.channelCellIds.fill(-1);
    this.channelCellIds[0] = focus.id;
    for (const s of candidates) {
      this.channelCellIds[s.lane] = s.cell.id;
    }
    return candidates;
  }

  evaluateStep(
    stepIndex: number,
    audioTime: number,
    sim: Simulation,
    focus: Cell,
    paused = false,
  ): ScheduledNote[] {
    const notes: ScheduledNote[] = [];
    const bar = Math.floor(stepIndex / STEPS_PER_BAR) % CYCLE_BARS;
    const beat = stepIndex % STEPS_PER_BAR;
    const section = sectionForBar(bar);
    const trans = biomassTransposition(focus.organicMass());

    // Two bars per chord: Dm (minor 3rd) -> Bb Maj (major 3rd) -> F Maj -> C Maj
    const chord = Math.floor(bar / 2) % PROGRESSION_ROOTS.length;
    const third = chord === 0 ? 3 : 4;
    const root = 50 + PROGRESSION_ROOTS[chord] + trans;

    const broken = section === 'break' || paused || focus.dead;
    const opening = section === 'emerge' && bar % 8 < 4;

    const lightHere = clamp(sim.lightAt(focus.position), 0.08, 1.35);
    const acidHere = Math.abs(sim.acidity.sample(focus.position.x, focus.position.y));
    const cutoffHz = clamp(400 + 6100 * Math.pow(lightHere, 1.4), 450, 7500);
    const acidDrive = clamp(acidHere * 0.85, 0, 0.75);

    const sources = this.collectSources(sim, focus, paused);
    const leadId = focus && !focus.dead ? focus.id : (sources[0]?.cell.id ?? -1);

    // Lane 0: Crisp rounded four-on-the-floor kick
    if (!focus.dead && beat % 4 === 0 && (!broken || beat === 0 || beat === 8)) {
      notes.push({
        lane: 0,
        voice: 'kick',
        semitonesFromRef: 0, // base note 36
        pitchSemitones: 0,
        gain: broken ? 0.36 : 0.72,
        pan: 0,
        audioTime,
        cellId: focus.id,
        x: focus.position.x,
        y: focus.position.y,
        cutoffHz: 6500,
        acidDrive: 0,
      });
    }

    // Lead lineage bright tropical motif (played by focus cell's active organs)
    const motifBeatIdx = MOTIF_BEATS.indexOf(beat as (typeof MOTIF_BEATS)[number]);
    if (
      !focus.dead &&
      motifBeatIdx >= 0 &&
      (!broken || beat === 0 || beat === 10) &&
      (!opening || beat === 0 || beat === 10)
    ) {
      const lead = sources.find((s) => s.cell.id === leadId);
      if (lead) {
        const availVoices: SynthVoice[] = [];
        for (let k = 0; k < TRACKED_KINDS.length; k++) {
          if (lead.counts[k] > 0) availVoices.push(ORGAN_VOICES[k]);
        }
        if (availVoices.length === 0) availVoices.push('graze');
        let deg = lead.motif[motifBeatIdx];
        if (deg === 3) deg = third;
        const voice = availVoices[Math.floor(bar / 2) % availVoices.length];
        const midiNote = root + 12 + deg;
        const vGain = (section === 'lift' || section === 'return' ? 0.24 : 0.18) * lead.gain * 1.45;
        notes.push({
          lane: lead.lane,
          voice,
          semitonesFromRef: midiNote - VOICE_BASE_NOTE[voice],
          pitchSemitones: midiNote - 36,
          gain: clamp(vGain, 0.08, 0.42),
          pan: lead.pan,
          audioTime,
          cellId: lead.cell.id,
          x: lead.cell.position.x,
          y: lead.cell.position.y,
          cutoffHz: clamp(400 + 6100 * Math.pow(lead.light, 1.4), 500, 7500),
          acidDrive: clamp(lead.acid * 0.8, 0, 0.7),
        });
      }
    }

    // Polyphonic organ-driven arpeggios & percussion across local cells (cap at 6 notes/step)
    let allowance = 6;
    for (const s of sources) {
      let hits = 0;
      const limit = s.gain > 0.4 ? 2 : 1;
      for (let shift = 0; shift < TRACKED_KINDS.length; shift++) {
        const k = (shift + Math.floor(stepIndex / 4)) % TRACKED_KINDS.length;
        const count = s.counts[k];
        if (count <= 0) continue;
        if (!ORGAN_PATTERNS[k].includes(beat)) continue;
        if (s.cell.id !== leadId && (bar + s.cell.id) % 2 !== 0) continue;
        if (s.gain < 0.2 && (bar + s.cell.id) % 3 !== 0) continue;
        if (opening && beat !== 0 && beat !== 8) continue;
        if (broken && beat !== 0 && beat !== 8 && beat !== 11 && beat !== 13) continue;
        if (allowance <= 0 || hits >= limit) break;

        const voice = ORGAN_VOICES[k];
        const register = -12 * clamp(Math.floor(Math.log(Math.max(1, s.mass / 100)) / Math.log(4)), 0, 2);
        let deg = ORGAN_DEGREES[k];
        if (k === 4) deg = [0, third, 7, 12][((Math.floor(stepIndex / 2) + s.cell.id) >>> 0) % 4];
        if (k === 6) deg = [0, 7, 12, third + 12][((Math.floor(stepIndex / 2) + bar) >>> 0) % 4];
        if (k === 9) deg = [0, 7, third, 12][((stepIndex + bar) >>> 0) % 4];

        const midiNote = clamp(root + 12 + register + deg, 29, 88);
        const noteGain = clamp(0.26 * Math.min(1.5, Math.sqrt(count)) * (opening ? 0.72 : 1.0) * (s.cell.id === leadId ? 0.88 : 0.45), 0.04, 0.36);

        notes.push({
          lane: s.lane,
          voice,
          semitonesFromRef: midiNote - VOICE_BASE_NOTE[voice],
          pitchSemitones: midiNote - 36,
          gain: noteGain,
          pan: s.pan,
          audioTime,
          cellId: s.cell.id,
          x: s.cell.position.x,
          y: s.cell.position.y,
          cutoffHz: clamp(400 + 6100 * Math.pow(s.light, 1.4), 500, 7500),
          acidDrive: clamp(s.acid * 0.8, 0, 0.7),
        });
        allowance--;
        hits++;
      }
    }

    // Subtle lift/build percussive hat & clap sparkles synced to section
    if (!broken && (section === 'groove' || section === 'lift' || section === 'build' || section === 'return')) {
      if (beat % 4 === 2) {
        notes.push({
          lane: 3,
          voice: 'hat',
          semitonesFromRef: 0,
          pitchSemitones: 24,
          gain: section === 'lift' ? 0.16 : 0.11,
          pan: 0.18,
          audioTime,
          cellId: focus.id,
          x: focus.position.x,
          y: focus.position.y,
          cutoffHz: 7500,
          acidDrive: 0,
        });
      }
      if ((section === 'lift' || section === 'build') && (beat === 4 || beat === 12)) {
        notes.push({
          lane: 3,
          voice: 'clap',
          semitonesFromRef: 0,
          pitchSemitones: 18,
          gain: 0.16,
          pan: -0.14,
          audioTime,
          cellId: focus.id,
          x: focus.position.x,
          y: focus.position.y,
          cutoffHz: 6800,
          acidDrive: 0,
        });
      }
    }

    this.lastSoundSeq = Math.max(this.lastSoundSeq, sim.soundSequence);
    void cutoffHz;
    void acidDrive;
    return notes;
  }
}
