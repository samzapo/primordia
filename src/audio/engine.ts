import type { Cell } from '../sim/cell.ts';
import { clamp } from '../sim/constants.ts';
import type { Simulation } from '../sim/simulation.ts';
import type { AudioWaveVisual } from '../render/renderer.ts';
import {
  ProgressiveScore,
  STEP_SECONDS,
  SWING_AMOUNT,
  type ScheduledNote,
} from './score.ts';
import {
  SYNTH_SAMPLE_RATE,
  SYNTH_VOICES,
  buildSynthBank,
  type SynthBank,
  type SynthVoice,
} from './synthBank.ts';

interface LaneNodes {
  filter: BiquadFilterNode;
  shaper: WaveShaperNode;
  panner: StereoPannerNode;
}

interface ActiveVoiceRecord {
  stopAt: number;
}

interface TriggeredWave {
  cellId: number;
  x: number;
  y: number;
  semitones: number;
  startAudioTime: number;
  duration: number;
}

const MAX_ACTIVE_VOICES = 40;
const SCHEDULE_AHEAD = 0.09;

function makeDriveCurve(drive: number): Float32Array<ArrayBuffer> {
  const n = 256;
  const buf = new ArrayBuffer(n * 4);
  const curve = new Float32Array(buf);
  const k = 1 + drive * 6;
  for (let i = 0; i < n; i++) {
    const x = (i * 2) / (n - 1) - 1;
    curve[i] = Math.tanh(x * k) / Math.tanh(k);
  }
  return curve;
}

export class AudioEngine {
  private ctx: AudioContext | null = null;
  private masterGain: GainNode | null = null;
  private delayNode: DelayNode | null = null;
  private lanes: LaneNodes[] = [];
  private buffers = new Map<SynthVoice, AudioBuffer>();
  private bank: SynthBank | null = null;
  private readonly score = new ProgressiveScore();

  private muted = false;
  private volume = 0.75;
  private unlocked = false;
  private startedClock = false;
  private nextStepTime = 0;
  private stepIndex = 0;
  private activeVoices: ActiveVoiceRecord[] = [];
  private waveHistory: TriggeredWave[] = [];
  private cleanCurve = makeDriveCurve(0);
  private acidCurve = makeDriveCurve(0.65);

  get isMuted(): boolean {
    return this.muted;
  }

  get currentVolume(): number {
    return this.volume;
  }

  get isUnlocked(): boolean {
    return this.unlocked;
  }

  unlock(): void {
    if (!this.ctx) {
      const AC =
        window.AudioContext ||
        (window as unknown as { webkitAudioContext?: typeof AudioContext }).webkitAudioContext;
      if (!AC) return;
      try {
        this.ctx = new AC({ sampleRate: SYNTH_SAMPLE_RATE });
      } catch {
        this.ctx = new AC();
      }
      this.buildGraph(this.ctx);
    }
    if (this.ctx.state === 'suspended') {
      void this.ctx.resume().then(() => {
        this.unlocked = true;
      });
    } else {
      this.unlocked = true;
    }
  }

  private buildGraph(ctx: AudioContext): void {
    this.bank = buildSynthBank(SYNTH_SAMPLE_RATE);
    for (const voice of SYNTH_VOICES) {
      const pcm = this.bank[voice];
      const ab = ctx.createBuffer(1, pcm.length, SYNTH_SAMPLE_RATE);
      ab.copyToChannel(new Float32Array(pcm), 0);
      this.buffers.set(voice, ab);
    }

    this.masterGain = ctx.createGain();
    this.masterGain.gain.value = this.muted ? 0 : this.volume;

    // 3/16 tempo-synced stereo dub delay send (0.18 send, bright open high end)
    this.delayNode = ctx.createDelay(1.0);
    this.delayNode.delayTime.value = STEP_SECONDS * 3;
    const delayFb = ctx.createGain();
    delayFb.gain.value = 0.26;
    const delayLp = ctx.createBiquadFilter();
    delayLp.type = 'lowpass';
    delayLp.frequency.value = 4800;
    const delayWet = ctx.createGain();
    delayWet.gain.value = 0.18;

    this.delayNode.connect(delayLp);
    delayLp.connect(delayFb);
    delayFb.connect(this.delayNode);
    delayLp.connect(delayWet);
    delayWet.connect(this.masterGain);

    this.masterGain.connect(ctx.destination);

    this.lanes = [];
    for (let i = 0; i < 7; i++) {
      const filter = ctx.createBiquadFilter();
      filter.type = 'lowpass';
      filter.frequency.value = i === 0 ? 7500 : 6200;
      filter.Q.value = 0.7;

      const shaper = ctx.createWaveShaper();
      shaper.curve = this.cleanCurve;

      const panner = ctx.createStereoPanner();
      panner.pan.value = 0;

      filter.connect(shaper);
      shaper.connect(panner);
      panner.connect(this.masterGain);
      if (i >= 1) {
        panner.connect(this.delayNode);
      }
      this.lanes.push({ filter, shaper, panner });
    }
  }

  setVolume(vol: number): void {
    this.volume = clamp(vol, 0, 1);
    if (this.masterGain && this.ctx) {
      this.masterGain.gain.setTargetAtTime(this.muted ? 0 : this.volume, this.ctx.currentTime, 0.03);
    }
  }

  setMuted(mute: boolean, sim?: Simulation): void {
    this.muted = mute;
    if (sim) this.score.resetHistory(sim);
    if (this.masterGain && this.ctx) {
      this.masterGain.gain.setTargetAtTime(this.muted ? 0 : this.volume, this.ctx.currentTime, 0.03);
    }
  }

  resetForNewPond(sim: Simulation): void {
    this.score.resetHistory(sim);
    this.waveHistory.length = 0;
    if (this.ctx) {
      this.nextStepTime = this.ctx.currentTime + 0.06;
    }
    this.stepIndex = 0;
  }

  onEdit(sim: Simulation): void {
    this.score.resetHistory(sim);
  }

  update(sim: Simulation, focus: Cell, paused: boolean): void {
    if (!this.ctx || !this.unlocked || this.muted || this.volume <= 0.005) {
      this.startedClock = false;
      if (this.muted) this.score.resetHistory(sim);
      return;
    }
    if (this.ctx.state === 'suspended') return;

    const now = this.ctx.currentTime;
    if (!this.startedClock || now - this.nextStepTime > 0.5) {
      this.nextStepTime = now + 0.03;
      this.startedClock = true;
      this.score.resetHistory(sim);
    }

    // Prune retired active voices & stale visual waves
    this.activeVoices = this.activeVoices.filter((v) => v.stopAt > now);
    this.waveHistory = this.waveHistory.filter((w) => now - w.startAudioTime < w.duration);

    let guard = 0;
    while (this.nextStepTime < now + SCHEDULE_AHEAD && guard < 8) {
      guard++;
      const swingOffset = this.stepIndex % 2 === 1 ? STEP_SECONDS * SWING_AMOUNT : 0;
      const playAt = Math.max(now + 0.005, this.nextStepTime + swingOffset);
      const beatPhase = (this.stepIndex % 4) * STEP_SECONDS + swingOffset;
      const duck = 0.42 + 0.58 * clamp(beatPhase / 0.18, 0, 1);
      const notes = this.score.evaluateStep(this.stepIndex, playAt, sim, focus, paused);
      for (const note of notes) {
        this.triggerNote(note, focus, note.lane >= 1 ? duck : 1.0);
      }
      this.stepIndex++;
      this.nextStepTime += STEP_SECONDS;
    }
  }

  private triggerNote(note: ScheduledNote, focus: Cell, duck = 1.0): void {
    if (!this.ctx) return;
    if (this.activeVoices.length >= MAX_ACTIVE_VOICES) return;
    const buf = this.buffers.get(note.voice);
    const lane = this.lanes[note.lane];
    if (!buf || !lane) return;

    const src = this.ctx.createBufferSource();
    src.buffer = buf;
    src.playbackRate.value = Math.pow(2, clamp(note.semitonesFromRef, -24, 24) / 12);

    const g = this.ctx.createGain();
    g.gain.value = clamp(note.gain * duck, 0, 1);

    lane.filter.frequency.setTargetAtTime(note.cutoffHz, note.audioTime, 0.04);
    lane.panner.pan.setTargetAtTime(clamp(note.pan, -1, 1), note.audioTime, 0.03);
    if (note.lane >= 1) {
      lane.shaper.curve = note.acidDrive > 0.22 ? this.acidCurve : this.cleanCurve;
    }

    src.connect(g);
    g.connect(lane.filter);

    const dur = buf.duration / src.playbackRate.value;
    src.start(note.audioTime);
    src.stop(note.audioTime + dur + 0.02);
    this.activeVoices.push({ stopAt: note.audioTime + dur + 0.02 });

    if (note.gain >= 0.14) {
      this.waveHistory.push({
        cellId: note.cellId,
        x: note.x || focus.position.x,
        y: note.y || focus.position.y,
        semitones: note.pitchSemitones,
        startAudioTime: note.audioTime,
        duration: 0.72,
      });
    }
  }

  activeWaves(sim: Simulation): AudioWaveVisual[] {
    if (!this.ctx || this.muted || !this.unlocked) return [];
    const now = this.ctx.currentTime;
    const out: AudioWaveVisual[] = [];
    for (const w of this.waveHistory) {
      const age = now - w.startAudioTime;
      if (age < 0 || age > w.duration) continue;
      const cell = sim.cells.find((c) => c.id === w.cellId && !c.dead);
      const baseR = cell ? cell.extent() : 32;
      const cx = cell ? cell.position.x : w.x;
      const cy = cell ? cell.position.y : w.y;
      const t = age / w.duration;
      out.push({
        x: cx,
        y: cy,
        semitones: w.semitones,
        radius: baseR + t * 56,
        alpha: (1 - t) * 0.42,
      });
    }
    return out;
  }
}
