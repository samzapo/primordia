import type { Cell, Organ, OrganKind } from '../sim/cell.ts';
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

interface OrganMusicProfile {
  voice: SynthVoice;
  pattern: readonly number[];
  degrees: readonly number[];
}

export const ORGAN_MUSIC: Record<OrganKind, OrganMusicProfile> = {
  propulsion: { voice: 'flagellum', pattern: [2, 6, 10, 14], degrees: [0, 7, 12, 7] },
  protection: { voice: 'pad', pattern: [0, 7, 12], degrees: [7, 12, 3, 10] },
  poreforming: { voice: 'pore', pattern: [0, 3, 6, 10, 14], degrees: [0, 12, 7, 3] },
  regenerative: { voice: 'enzyme', pattern: [3, 11], degrees: [12, 7, 10, 3] },
  feeding: { voice: 'graze', pattern: [0, 3, 8, 10, 14], degrees: [0, 3, 7, 12] },
  sensing: { voice: 'perc', pattern: [1, 4, 9, 12], degrees: [10, 7, 12, 3] },
  photosynthesis: { voice: 'photo', pattern: [0, 2, 5, 8, 10, 13], degrees: [0, 7, 12, 3] },
  toxin: { voice: 'toxin', pattern: [3, 6, 11, 14], degrees: [0, 3, 7, 10] },
  neutralizing: { voice: 'antitoxin', pattern: [5, 13], degrees: [12, 7, 3, 10] },
  acidifying: { voice: 'acid', pattern: [0, 3, 7, 10, 15], degrees: [0, 7, 3, 12] },
  hunting: { voice: 'perc', pattern: [2, 5, 8, 14], degrees: [5, 12, 7, 3] },
  cilia: { voice: 'cilia', pattern: [1, 3, 5, 9, 11, 13], degrees: [2, 7, 12, 10] },
  mitochondrion: { voice: 'enzyme', pattern: [4, 12], degrees: [7, 12, 15, 12] },
  counterattack: { voice: 'pore', pattern: [6, 14], degrees: [3, 10, 7, 12] },
  toxin_sac: { voice: 'toxin', pattern: [1, 9], degrees: [0, 10, 7, 3] },
  family_toward: { voice: 'antitoxin', pattern: [2, 10], degrees: [7, 10, 12, 7] },
  family_away: { voice: 'cilia', pattern: [6, 15], degrees: [12, 10, 7, 5] },
  proboscis: { voice: 'acid', pattern: [1, 7, 11], degrees: [3, 7, 10, 12] },
};

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
  organId: number | null;
  isBackground?: boolean;
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

interface ActiveOrganVoice {
  organ: Organ;
  kindIndex: number;
  slotIndex: number;
  profile: OrganMusicProfile;
  weight: number;
}

interface ObservedSource {
  cell: Cell;
  lane: number;
  gain: number;
  pan: number;
  mass: number;
  activeOrgans: ActiveOrganVoice[];
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

      const activeOrgans: ActiveOrganVoice[] = [];
      const seenPerKind = new Map<OrganKind, number>();
      for (const organ of c.organs) {
        if (organ.hp <= 0) continue;
        const profile = ORGAN_MUSIC[organ.kind];
        if (!profile) continue;
        const kindIndex = seenPerKind.get(organ.kind) ?? 0;
        seenPerKind.set(organ.kind, kindIndex + 1);
        activeOrgans.push({
          organ,
          kindIndex,
          slotIndex: activeOrgans.length,
          profile,
          weight: 0.35 + 0.65 * clamp(organ.hp / Math.max(organ.maxHp, 0.01), 0, 1),
        });
      }

      const weight = c.organicMass();
      const baseGain = prox * (c === focus ? 0.62 : 0.1) * (paused ? 0.65 : 1.0);
      candidates.push({
        cell: c,
        lane: 1,
        gain: baseGain,
        pan: panFromFocus(focus, c.position.x, c.position.y),
        mass: weight,
        activeOrgans,
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

    // Lane 0: Nucleus baseline pulse (sub-bass, bassline groove & warm background pad)
    if (!focus.dead) {
      if (beat % 4 === 0 && (!broken || beat === 0 || beat === 8)) {
        notes.push({
          lane: 0,
          voice: 'kick',
          semitonesFromRef: 0, // base note 36
          pitchSemitones: 0,
          gain: broken ? 0.34 : 0.68,
          pan: 0,
          audioTime,
          cellId: focus.id,
          organId: null,
          x: focus.position.x,
          y: focus.position.y,
          cutoffHz: 6500,
          acidDrive: 0,
        });
      }

      // Deep sub-bass root anchor from the nucleus
      if (beat === 0 || (!broken && beat === 8)) {
        const subMidi = clamp(root - 12, 26, 48);
        notes.push({
          lane: 0,
          voice: 'sub',
          semitonesFromRef: subMidi - VOICE_BASE_NOTE.sub,
          pitchSemitones: subMidi - 36,
          gain: broken ? 0.28 : 0.44,
          pan: 0,
          audioTime,
          cellId: focus.id,
          organId: null,
          isBackground: true,
          x: focus.position.x,
          y: focus.position.y,
          cutoffHz: 1800,
          acidDrive: 0,
        });
      }

      // Warm melodic bassline groove from the nucleus
      if (!broken && (beat === 2 || beat === 6 || beat === 10 || beat === 14)) {
        const bassDeg = beat === 6 || beat === 14 ? 7 : beat === 10 ? third : 0;
        const bassMidi = clamp(root - 12 + bassDeg, 28, 55);
        notes.push({
          lane: 0,
          voice: 'sub',
          semitonesFromRef: bassMidi - VOICE_BASE_NOTE.sub,
          pitchSemitones: bassMidi - 36,
          gain: 0.32,
          pan: 0,
          audioTime,
          cellId: focus.id,
          organId: null,
          x: focus.position.x,
          y: focus.position.y,
          cutoffHz: 2800,
          acidDrive: 0,
        });
      }

      // Soft warm harmonic chord background pad (no motif ring when nucleus-only)
      if (beat === 0 || (!opening && beat === 8)) {
        const padMidi = root + (beat === 8 ? third : 0);
        notes.push({
          lane: 1,
          voice: 'pad',
          semitonesFromRef: padMidi - VOICE_BASE_NOTE.pad,
          pitchSemitones: padMidi - 36,
          gain: broken ? 0.08 : 0.13,
          pan: 0,
          audioTime,
          cellId: focus.id,
          organId: null,
          isBackground: true,
          x: focus.position.x,
          y: focus.position.y,
          cutoffHz: clamp(cutoffHz * 0.75, 500, 4800),
          acidDrive: acidDrive * 0.5,
        });
      }
    }

    // Lead lineage bright tropical motif (only when focus cell has non-nucleus active organelles)
    const motifBeatIdx = MOTIF_BEATS.indexOf(beat as (typeof MOTIF_BEATS)[number]);
    const lead = sources.find((s) => s.cell.id === leadId);
    if (
      !focus.dead &&
      lead &&
      lead.activeOrgans.length > 0 &&
      motifBeatIdx >= 0 &&
      (!broken || beat === 0 || beat === 10) &&
      (!opening || beat === 0 || beat === 10)
    ) {
      const chosen = lead.activeOrgans[Math.floor(bar / 2) % lead.activeOrgans.length];
      const organWorld = lead.cell.organPosition(chosen.organ);
      let deg = lead.motif[motifBeatIdx];
      if (deg === 3) deg = third;
      const midiNote = root + 12 + deg;
      const vGain = (section === 'lift' || section === 'return' ? 0.22 : 0.16) * lead.gain * 1.35;
      notes.push({
        lane: lead.lane,
        voice: chosen.profile.voice,
        semitonesFromRef: midiNote - VOICE_BASE_NOTE[chosen.profile.voice],
        pitchSemitones: midiNote - 36,
        gain: clamp(vGain, 0.08, 0.38),
        pan: panFromFocus(focus, organWorld.x, organWorld.y),
        audioTime,
        cellId: lead.cell.id,
        organId: chosen.organ.id,
        x: organWorld.x,
        y: organWorld.y,
        cutoffHz: clamp(400 + 6100 * Math.pow(lead.light, 1.4), 500, 7500),
        acidDrive: clamp(lead.acid * 0.8, 0, 0.7),
      });
    }

    // Polyphonic per-organelle motif layer: each additional organelle adds its own motif & emits waves from itself
    let totalMotifOrgans = 0;
    for (const s of sources) totalMotifOrgans += s.activeOrgans.length;
    let allowance = Math.min(12, Math.max(6, totalMotifOrgans));
    const organAtten = totalMotifOrgans > 2 ? 1 / Math.sqrt(totalMotifOrgans / 2) : 1.0;

    for (const s of sources) {
      if (s.activeOrgans.length === 0) continue;
      let hits = 0;
      const limit = s.cell.id === leadId ? Math.min(8, s.activeOrgans.length) : s.gain > 0.35 ? 2 : 1;
      for (let shift = 0; shift < s.activeOrgans.length; shift++) {
        const entry = s.activeOrgans[(shift + Math.floor(stepIndex / 4)) % s.activeOrgans.length];
        const pat = entry.profile.pattern;
        // Phase-shift duplicate/additional organelles so every added organelle contributes distinct steps & harmony
        const localBeat = (beat - entry.kindIndex * 2 + entry.slotIndex * 0 + STEPS_PER_BAR) % STEPS_PER_BAR;
        if (!pat.includes(localBeat)) continue;
        if (s.cell.id !== leadId && (bar + s.cell.id + entry.slotIndex) % 2 !== 0) continue;
        if (s.gain < 0.2 && (bar + s.cell.id) % 3 !== 0) continue;
        if (broken && beat !== 0 && beat !== 8 && beat !== 11 && beat !== 13) continue;
        if (allowance <= 0 || hits >= limit) break;

        const register =
          -12 * clamp(Math.floor(Math.log(Math.max(1, s.mass / 100)) / Math.log(4)), 0, 2) +
          (entry.kindIndex % 2 === 1 ? 12 : 0);
        const degs = entry.profile.degrees;
        let deg = degs[(Math.floor(stepIndex / 2) + entry.slotIndex + entry.kindIndex + bar) % degs.length];
        if (deg === 3) deg = third;

        const midiNote = clamp(root + 12 + register + deg, 31, 90);
        const noteGain = clamp(
          0.24 * entry.weight * organAtten * (opening ? 0.75 : 1.0) * (s.cell.id === leadId ? 0.92 : 0.42),
          0.05,
          0.34,
        );
        const organWorld = s.cell.organPosition(entry.organ);

        notes.push({
          lane: s.lane,
          voice: entry.profile.voice,
          semitonesFromRef: midiNote - VOICE_BASE_NOTE[entry.profile.voice],
          pitchSemitones: midiNote - 36,
          gain: noteGain,
          pan: panFromFocus(focus, organWorld.x, organWorld.y),
          audioTime,
          cellId: s.cell.id,
          organId: entry.organ.id,
          x: organWorld.x,
          y: organWorld.y,
          cutoffHz: clamp(400 + 6100 * Math.pow(s.light, 1.4), 500, 7500),
          acidDrive: clamp(s.acid * 0.8, 0, 0.7),
        });
        allowance--;
        hits++;
      }
    }

    // Percussion sparkle accents activate only once organelles are present beyond nucleus
    if (
      totalMotifOrgans > 0 &&
      !broken &&
      (section === 'groove' || section === 'lift' || section === 'build' || section === 'return')
    ) {
      const percAnchor = lead && lead.activeOrgans.length > 0 ? lead.activeOrgans[0].organ : null;
      const percPos = percAnchor && lead ? lead.cell.organPosition(percAnchor) : focus.position;
      if (beat % 4 === 2) {
        notes.push({
          lane: 3,
          voice: 'hat',
          semitonesFromRef: 0,
          pitchSemitones: 24,
          gain: section === 'lift' ? 0.14 : 0.1,
          pan: 0.18,
          audioTime,
          cellId: focus.id,
          organId: percAnchor ? percAnchor.id : null,
          isBackground: true,
          x: percPos.x,
          y: percPos.y,
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
          gain: 0.14,
          pan: -0.14,
          audioTime,
          cellId: focus.id,
          organId: percAnchor ? percAnchor.id : null,
          isBackground: true,
          x: percPos.x,
          y: percPos.y,
          cutoffHz: 6800,
          acidDrive: 0,
        });
      }
    }

    this.lastSoundSeq = Math.max(this.lastSoundSeq, sim.soundSequence);
    return notes;
  }
}
