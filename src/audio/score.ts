import type { Cell } from '../sim/cell.ts';
import { SeededRng } from '../sim/rng.ts';
import { clamp, offsetVec } from '../sim/constants.ts';
import type { Simulation } from '../sim/simulation.ts';
import type { SynthVoice } from './synthBank.ts';

export const BPM = 128;
export const STEPS_PER_BAR = 16;
export const CYCLE_BARS = 64;
export const STEP_SECONDS = 60.0 / BPM / 4.0;
export const SWING_AMOUNT = 0.055;

// D minor progressive progression: Dm - Bb - F - C (relative semitones from D)
export const PROGRESSION_ROOTS = [0, 8, 3, 10] as const;
// D Aeolian scale intervals
export const SCALE_AEOLIAN = [0, 2, 3, 5, 7, 8, 10] as const;

export type CycleSection = 'emerge' | 'groove' | 'lift' | 'break' | 'build' | 'return';

export interface ScheduledNote {
  lane: number; // 0..6
  voice: SynthVoice;
  semitonesFromRef: number;
  pitchSemitones: number; // for wave ripple visualization
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
  const rng = new SeededRng((seedValue ^ Math.imul(lineage | 0, 1640531527)) | 0);
  const motif: number[] = [];
  for (let i = 0; i < 6; i++) {
    motif.push(rng.nextUint() % SCALE_AEOLIAN.length);
  }
  return motif;
}

function panFromFocus(focus: Cell, atX: number, atY: number): number {
  const dx = offsetVec(focus.position, { x: atX, y: atY }).x;
  return clamp(dx / 360, -0.85, 0.85);
}

export class ProgressiveScore {
  private lastSoundSeq = 0;
  private lastSparkSerial = 0;

  resetHistory(sim: Simulation): void {
    this.lastSoundSeq = sim.soundSequence;
    this.lastSparkSerial = sim.reactionSerial;
  }

  evaluateStep(stepIndex: number, audioTime: number, sim: Simulation, focus: Cell): ScheduledNote[] {
    const notes: ScheduledNote[] = [];
    const bar = Math.floor(stepIndex / STEPS_PER_BAR) % CYCLE_BARS;
    const step = stepIndex % STEPS_PER_BAR;
    const section = sectionForBar(bar);
    const chordIdx = Math.floor(bar / 4) % PROGRESSION_ROOTS.length;
    const rootSemi = PROGRESSION_ROOTS[chordIdx];

    const acidHere = Math.abs(sim.acidity.sample(focus.position.x, focus.position.y));
    const lightHere = clamp(sim.lightAt(focus.position), 0.15, 1.4);
    const cutoffHz = clamp(900 + lightHere * 4200 + (section === 'lift' ? 1800 : 0) - acidHere * 900, 650, 9500);
    const acidDrive = clamp(acidHere * 0.9, 0.0, 0.85);
    const trans = biomassTransposition(focus.organicMass());

    // Neighbor census for organic density modulation
    let nearbyLiving = 0;
    let totalNearbyActivity = 0;
    let nearestOther: Cell | null = null;
    let nearestDist = Infinity;
    for (const c of sim.cells) {
      if (c.dead) continue;
      const d = offsetVec(focus.position, c.position);
      const dist = Math.hypot(d.x, d.y);
      if (c !== focus && dist < 520) {
        nearbyLiving++;
        totalNearbyActivity += clamp(Math.hypot(c.velocity.x, c.velocity.y) / 40, 0.2, 1.2);
        if (dist < nearestDist) {
          nearestDist = dist;
          nearestOther = c;
        }
      }
    }

    const activeEnergy = clamp(focus.energy / Math.max(1, focus.energyReference()), 0.2, 1.2);
    const hasPropulsion = focus.organs.some((o) => o.kind === 'propulsion' && o.hp > 0);
    const hasCilia = focus.organs.some((o) => o.kind === 'cilia' && o.hp > 0);
    const hasPhoto = focus.organs.some((o) => o.kind === 'photosynthesis' && o.hp > 0);
    const hasWeapon = focus.organs.some(
      (o) => (o.kind === 'toxin' || o.kind === 'poreforming' || o.kind === 'acidifying') && o.hp > 0,
    );

    // Lane 0: Four-on-the-floor progressive kick (suppressed in break, light filter in emerge)
    if (section !== 'break' && step % 4 === 0) {
      const kickGain = section === 'emerge' ? 0.36 : section === 'return' ? 0.55 : 0.72;
      notes.push({
        lane: 0,
        voice: 'kick',
        semitonesFromRef: 0,
        pitchSemitones: -18,
        gain: kickGain,
        pan: 0,
        audioTime,
        cellId: focus.id,
        x: focus.position.x,
        y: focus.position.y,
        cutoffHz: section === 'emerge' ? 420 : 12000,
        acidDrive: 0,
      });
    }

    // Build snare/percussion ramp in bar 48..59
    if (section === 'build' && ((step % 4 === 2 && bar >= 48) || (bar >= 56 && step % 2 === 1))) {
      notes.push({
        lane: 3,
        voice: 'perc',
        semitonesFromRef: rootSemi + trans,
        pitchSemitones: rootSemi + trans,
        gain: 0.28,
        pan: step % 2 === 0 ? -0.18 : 0.18,
        audioTime,
        cellId: focus.id,
        x: focus.position.x,
        y: focus.position.y,
        cutoffHz,
        acidDrive,
      });
    }

    // Lane 1: Rolling sub bass
    const bassPattern = section === 'emerge' ? [0, 8] : [2, 6, 10, 14];
    if (bassPattern.includes(step) || (hasPropulsion && focus.driveActive && step % 4 === 3)) {
      const octaveDrop = focus.organicMass() > 140 ? -12 : 0;
      const subGain = section === 'break' ? 0.28 : 0.42 * (0.65 + 0.35 * activeEnergy);
      notes.push({
        lane: 1,
        voice: 'sub',
        semitonesFromRef: rootSemi + trans + octaveDrop,
        pitchSemitones: rootSemi + trans - 12,
        gain: subGain,
        pan: 0,
        audioTime,
        cellId: focus.id,
        x: focus.position.x,
        y: focus.position.y,
        cutoffHz: Math.min(cutoffHz, 1200),
        acidDrive: acidDrive * 0.4,
      });
    }

    // Lane 2: Inherited 6-note lineage melody on focused cell
    const melody = lineageMelodyDegrees(sim.seedValue, focus.lineageId());
    const melodySteps = section === 'lift' || section === 'groove' ? [0, 3, 6, 10, 12, 14] : [0, 6, 12];
    const mIdx = melodySteps.indexOf(step);
    if (mIdx >= 0 && (focus.driveActive || hasPhoto || section === 'lift' || section === 'break')) {
      const deg = melody[(mIdx + bar) % melody.length];
      const semi = SCALE_AEOLIAN[deg] + rootSemi + trans;
      const vel = clamp(0.18 + activeEnergy * 0.16 + (section === 'lift' ? 0.08 : 0), 0.14, 0.42);
      notes.push({
        lane: 2,
        voice: hasPhoto ? 'photo' : 'graze',
        semitonesFromRef: semi,
        pitchSemitones: semi,
        gain: vel,
        pan: 0.08 * Math.sin(bar * 0.6 + mIdx),
        audioTime,
        cellId: focus.id,
        x: focus.position.x,
        y: focus.position.y,
        cutoffHz,
        acidDrive,
      });
    }

    // Lane 3: Hat & cilia pulse driven by motility + nearby cell crowd
    if (section !== 'emerge') {
      const isOffbeatHat = step % 4 === 2;
      const denseHat = (hasCilia || nearbyLiving >= 3 || section === 'lift') && step % 2 === 1;
      if (isOffbeatHat || denseHat) {
        notes.push({
          lane: 3,
          voice: isOffbeatHat ? 'hat' : 'cilia',
          semitonesFromRef: isOffbeatHat ? 0 : trans * 0.5,
          pitchSemitones: 14,
          gain: isOffbeatHat ? 0.24 : clamp(0.1 + totalNearbyActivity * 0.04, 0.1, 0.2),
          pan: isOffbeatHat ? 0.2 : -0.22,
          audioTime,
          cellId: focus.id,
          x: focus.position.x,
          y: focus.position.y,
          cutoffHz: cutoffHz + 1500,
          acidDrive: 0,
        });
      }
      if ((section === 'lift' || section === 'groove') && (step === 4 || step === 12)) {
        notes.push({
          lane: 3,
          voice: 'clap',
          semitonesFromRef: 0,
          pitchSemitones: 10,
          gain: 0.28,
          pan: -0.1,
          audioTime,
          cellId: focus.id,
          x: focus.position.x,
          y: focus.position.y,
          cutoffHz,
          acidDrive: 0,
        });
      }
    }

    // Lane 4: Acid/Enzyme texture & neighbor counter-motif (proximity sonification)
    if (nearestOther && (step === 2 || step === 9 || (hasWeapon && step === 15))) {
      const otherMel = lineageMelodyDegrees(sim.seedValue, nearestOther.lineageId());
      const semi = SCALE_AEOLIAN[otherMel[(step + bar) % otherMel.length]] + rootSemi + trans;
      const prox = clamp(1 - nearestDist / 520, 0.15, 1);
      const voice: SynthVoice = acidHere > 0.25 ? 'acid' : hasWeapon ? 'toxin' : 'enzyme';
      notes.push({
        lane: 4,
        voice,
        semitonesFromRef: semi,
        pitchSemitones: semi,
        gain: 0.12 + 0.18 * prox,
        pan: panFromFocus(focus, nearestOther.position.x, nearestOther.position.y),
        audioTime,
        cellId: nearestOther.id,
        x: nearestOther.position.x,
        y: nearestOther.position.y,
        cutoffHz,
        acidDrive,
      });
    }

    // Lane 5: Sunlight & Photosynthesis warm harmonic pad on bar downbeat
    if (step === 0 && bar % 2 === 0) {
      notes.push({
        lane: 5,
        voice: 'pad',
        semitonesFromRef: rootSemi + trans,
        pitchSemitones: rootSemi + trans - 5,
        gain: clamp(0.16 + lightHere * 0.14 + (hasPhoto ? 0.08 : 0), 0.14, 0.36),
        pan: 0,
        audioTime,
        cellId: focus.id,
        x: focus.position.x,
        y: focus.position.y,
        cutoffHz: cutoffHz * 0.85,
        acidDrive: 0,
      });
    }

    // Lane 6: Local Simulation Event Accents (never replayed across mute/restart)
    let eventCount = 0;
    for (const ev of sim.soundEvents) {
      if (ev.sequence <= this.lastSoundSeq) continue;
      if (eventCount >= 3) break;
      const voiceMap: Record<string, SynthVoice> = {
        eat: 'graze',
        feed: 'graze',
        photosynthesis: 'photo',
        mitosis: 'mitosis',
        division: 'mitosis',
        death: 'death',
        toxin: 'toxin',
        pore: 'pore',
        enzyme: 'enzyme',
        antitoxin: 'antitoxin',
        acid: 'acid',
        cilia: 'cilia',
        propulsion: 'flagellum',
      };
      const voice = voiceMap[ev.kind] ?? 'perc';
      const semi = SCALE_AEOLIAN[ev.sequence % SCALE_AEOLIAN.length] + rootSemi + trans;
      notes.push({
        lane: 6,
        voice,
        semitonesFromRef: semi,
        pitchSemitones: semi,
        gain: clamp(0.16 + ev.amount * 0.06, 0.15, 0.34),
        pan: panFromFocus(focus, ev.at.x, ev.at.y),
        audioTime: audioTime + eventCount * 0.015,
        cellId: ev.source,
        x: ev.at.x,
        y: ev.at.y,
        cutoffHz,
        acidDrive,
      });
      eventCount++;
    }
    this.lastSoundSeq = Math.max(this.lastSoundSeq, sim.soundSequence);

    // Bounded local spark chime (max 1 per step)
    if (sim.reactionSerial > this.lastSparkSerial && sim.reactionSparks.length > 0) {
      const sp = sim.reactionSparks[sim.reactionSparks.length - 1];
      if (sp.serial > this.lastSparkSerial) {
        const d = offsetVec(focus.position, sp.at);
        if (Math.hypot(d.x, d.y) < 480) {
          notes.push({
            lane: 6,
            voice: 'enzyme',
            semitonesFromRef: 12 + rootSemi + trans,
            pitchSemitones: 12 + rootSemi + trans,
            gain: 0.14,
            pan: panFromFocus(focus, sp.at.x, sp.at.y),
            audioTime,
            cellId: focus.id,
            x: sp.at.x,
            y: sp.at.y,
            cutoffHz,
            acidDrive,
          });
        }
      }
      this.lastSparkSerial = sim.reactionSerial;
    }

    return notes;
  }
}
