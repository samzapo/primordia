import test from 'node:test';
import assert from 'node:assert/strict';
import { Cell } from '../src/sim/cell.ts';
import { SPECIES } from '../src/sim/constants.ts';
import { Simulation } from '../src/sim/simulation.ts';
import { PondCamera } from '../src/ui/camera.ts';
import { LENS_RADIUS_PX, ParticleInspector } from '../src/ui/inspector.ts';

function circleBoxGap(rx, ry, rw, rh, cx, cy) {
  const nx = Math.max(rx, Math.min(cx, rx + rw));
  const ny = Math.max(ry, Math.min(cy, ry + rh));
  return Math.hypot(cx - nx, cy - ny);
}

function makeMockElement() {
  const el = {
    className: '',
    hidden: false,
    textContent: '',
    children: [],
    style: { left: '', top: '', color: '' },
    appendChild(child) {
      this.children.push(child);
      return child;
    },
    replaceChildren(...nodes) {
      this.children = nodes;
    },
    getBoundingClientRect() {
      return { width: 220, height: 84 };
    },
  };
  return el;
}

function makeMockSim(focus) {
  return {
    time: 12.4,
    cells: [focus],
    lineageNames: new Map([[focus.lineage, 'Lineage 0']]),
    acidity: { sample: () => 0.1 },
    inspectCursor: { active: false, x: 0, y: 0, maxRadius: 40, trackedSlot: -1, trackedGen: 0, epoch: 0 },
    lastInspected: null,
  };
}

test('ParticleInspector centers optical magnification on drifting particle while keeping tooltip stationary', () => {
  const prevDocument = globalThis.document;
  globalThis.document = { createElement: () => makeMockElement() };
  try {
    const parent = makeMockElement();
    const inspector = new ParticleInspector(parent);
    const cam = new PondCamera();
    const focus = new Cell(1, { x: 2048, y: 1280 });
    cam.setFocusCell(focus, false);
    cam.zoom = 2.0;

    const viewW = 412;
    const viewH = 915;
    const pokeX = 120;
    const pokeY = 700;
    const sim = makeMockSim(focus);

    // Trigger touch poke on open water away from cell
    inspector.triggerTouchHold(pokeX, pokeY, 1.0, sim);

    // Before first GPU inspection readback completes: query runs, lens stays hidden so no empty circle renders
    const preReadback = inspector.update(sim, focus, cam, pokeX, pokeY, true, true, false, viewW, viewH, 1.02);
    assert.equal(sim.inspectCursor.active, true);
    assert.equal(preReadback.active, false);
    assert.equal(preReadback.radiusPx, 0);

    // Particle detected near tap and drifts 40px right / 30px up across subsequent frames
    const firstWorld = cam.screenToWorld(pokeX + 8, pokeY - 6, viewW, viewH);
    sim.lastInspected = {
      valid: true,
      slot: 42,
      gen: 3,
      kind: SPECIES.NUTRIENT,
      x: firstWorld.x,
      y: firstWorld.y,
      amount: 0.41,
      capacity: 0.61,
      expiresAt: 0,
      report: null,
    };
    const match1 = inspector.update(sim, focus, cam, pokeX, pokeY, true, true, false, viewW, viewH, 1.05);
    assert.equal(match1.active, true);
    assert.equal(match1.radiusPx, LENS_RADIUS_PX);
    assert.ok(Math.abs(match1.screenX - (pokeX + 8)) < 1e-3);
    assert.ok(Math.abs(match1.screenY - (pokeY - 6)) < 1e-3);
    const tipLeft1 = inspector.tooltipEl.style.left;
    const tipTop1 = inspector.tooltipEl.style.top;
    assert.equal(inspector.tooltipEl.hidden, false);

    // Particle drifts gently away from tooltip while tooltip remains strictly stationary
    const driftedAway = cam.screenToWorld(pokeX + 20, pokeY - 12, viewW, viewH);
    sim.lastInspected = {
      ...sim.lastInspected,
      x: driftedAway.x,
      y: driftedAway.y,
    };
    const match2 = inspector.update(sim, focus, cam, pokeX, pokeY, true, true, false, viewW, viewH, 1.8);
    assert.equal(match2.active, true);
    assert.equal(sim.inspectCursor.trackedSlot, 42);
    assert.ok(Math.abs(match2.screenX - (pokeX + 20)) < 1e-3);
    assert.ok(Math.abs(match2.screenY - (pokeY - 12)) < 1e-3);
    assert.equal(inspector.tooltipEl.style.left, tipLeft1);
    assert.equal(inspector.tooltipEl.style.top, tipTop1);

    // Particle drifts into tooltip zone -> tooltip relocates so magnification is never behind it
    const driftedIntoTip = cam.screenToWorld(pokeX + 20, pokeY + 18, viewW, viewH);
    sim.lastInspected = {
      ...sim.lastInspected,
      x: driftedIntoTip.x,
      y: driftedIntoTip.y,
    };
    const match3 = inspector.update(sim, focus, cam, pokeX, pokeY, true, true, false, viewW, viewH, 2.25);
    assert.equal(match3.active, true);
    const tx3 = parseFloat(inspector.tooltipEl.style.left);
    const ty3 = parseFloat(inspector.tooltipEl.style.top);
    assert.ok(circleBoxGap(tx3, ty3, 220, 84, match3.screenX, match3.screenY) >= LENS_RADIUS_PX + 8);

    // Expire touch hold
    const expired = inspector.update(sim, focus, cam, pokeX, pokeY, true, true, false, viewW, viewH, 5.0);
    assert.equal(expired.active, false);
    assert.equal(inspector.tooltipEl.hidden, true);
  } finally {
    globalThis.document = prevDocument;
  }
});

test('ParticleInspector never places magnification behind tooltip across mobile corners or tall tooltips', () => {
  const prevDocument = globalThis.document;
  globalThis.document = {
    createElement: () => {
      const el = makeMockElement();
      el.getBoundingClientRect = () => ({ width: 256, height: 132 });
      return el;
    },
  };
  try {
    const parent = makeMockElement();
    const inspector = new ParticleInspector(parent);
    const cam = new PondCamera();
    const focus = new Cell(1, { x: 2048, y: 1280 });
    cam.setFocusCell(focus, false);
    cam.zoom = 2.0;

    const viewW = 412;
    const viewH = 915;
    const sim = makeMockSim(focus);

    // Test awkward mobile positions near bottom, top, left, right edges
    const spots = [
      [140, 760],
      [140, 700],
      [200, 90],
      [350, 820],
      [60, 450],
    ];
    for (let i = 0; i < spots.length; i++) {
      const [sx, sy] = spots[i];
      inspector.triggerTouchHold(sx, sy, 1.0 + i, sim);
      const wp = cam.screenToWorld(sx, sy - 10, viewW, viewH);
      sim.lastInspected = {
        valid: true,
        slot: 100 + i,
        gen: 1,
        kind: SPECIES.PHEROMONE,
        x: wp.x,
        y: wp.y,
        amount: 1.0,
        capacity: 1.0,
        expiresAt: 45,
        report: {
          id: 9,
          lineage: 0,
          at: wp,
          mass: 307.5,
          radius: 10,
          hostile: false,
          defended: false,
          emittedAt: 10,
        },
      };
      const st = inspector.update(sim, focus, cam, sx, sy, true, true, false, viewW, viewH, 1.05 + i);
      assert.equal(st.active, true);
      const tx = parseFloat(inspector.tooltipEl.style.left);
      const ty = parseFloat(inspector.tooltipEl.style.top);
      const gap = circleBoxGap(tx, ty, 256, 132, st.screenX, st.screenY);
      assert.ok(gap >= LENS_RADIUS_PX + 8, `spot (${sx},${sy}) gap=${gap.toFixed(1)} overlapped lens at (${st.screenX},${st.screenY}) tip=(${tx},${ty})`);
    }
  } finally {
    globalThis.document = prevDocument;
  }
});

test('ParticleInspector epoch + sequence guards prevent flickering back to previous particle', () => {
  const prevDocument = globalThis.document;
  globalThis.document = { createElement: () => makeMockElement() };
  try {
    const sim = new Simulation(20261004, 0, false);
    const parent = makeMockElement();
    const inspector = new ParticleInspector(parent);
    const cam = new PondCamera();
    cam.setFocusCell(sim.player, false);

    // Hold spot A and receive particle slot 10 at epoch 0
    inspector.triggerTouchHold(80, 700, 1.0, sim);
    inspector.update(sim, sim.player, cam, 80, 700, true, true, false, 412, 915, 1.01);
    const epochA = sim.inspectCursor.epoch;

    const receiptA = {
      revision: -1,
      inspectEpoch: epochA,
      inspectSeq: 10,
      bodyIntakes: [],
      feedResults: [],
      queryResults: [],
      exposureHits: [],
      decoyHits: [],
      reactionSparks: [],
      census: { alive: 0, pheromones: 0, material: 0, oxygen: 0, decays: 0, materialLoss: 0, recycled: 0, reactions: 0 },
      inspected: {
        valid: true,
        slot: 10,
        gen: 1,
        kind: SPECIES.NUTRIENT,
        x: 500,
        y: 500,
        amount: 1,
        capacity: 1,
        expiresAt: 0,
        report: null,
      },
      acidField: new Float32Array(0),
    };
    sim.applyInspectReceipt(receiptA);
    assert.equal(sim.lastInspected?.slot, 10);

    // Tap spot B: epoch advances and cursor deactivates until inspector.update recomputes wp
    inspector.triggerTouchHold(300, 200, 1.2, sim);
    assert.ok(sim.inspectCursor.epoch > epochA);
    assert.equal(sim.inspectCursor.active, false);
    assert.equal(sim.lastInspected, null);

    // Stale in-flight GPU receipt from epochA MUST be rejected cleanly
    sim.applyInspectReceipt({ ...receiptA, inspectSeq: 11 });
    assert.equal(sim.lastInspected, null);

    // Update prepares new cursor for epochB, receives slot 25 seq 13, and rejects older seq 12
    inspector.update(sim, sim.player, cam, 300, 200, true, true, false, 412, 915, 1.21);
    const epochB = sim.inspectCursor.epoch;
    sim.applyInspectReceipt({
      ...receiptA,
      inspectEpoch: epochB,
      inspectSeq: 13,
      inspected: { ...receiptA.inspected, slot: 25 },
    });
    assert.equal(sim.lastInspected?.slot, 25);

    sim.applyInspectReceipt({
      ...receiptA,
      inspectEpoch: epochB,
      inspectSeq: 12,
      inspected: { ...receiptA.inspected, slot: 10 },
    });
    assert.equal(sim.lastInspected?.slot, 25);
  } finally {
    globalThis.document = prevDocument;
  }
});
