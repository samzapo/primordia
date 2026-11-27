import test from 'node:test';
import assert from 'node:assert/strict';
import { Cell } from '../src/sim/cell.ts';
import { SPECIES } from '../src/sim/constants.ts';
import { PondCamera } from '../src/ui/camera.ts';
import { LENS_RADIUS_PX, ParticleInspector } from '../src/ui/inspector.ts';

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
    inspectCursor: { active: false, x: 0, y: 0, maxRadius: 40, trackedSlot: -1, trackedGen: 0 },
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

    // Particle drifts significantly across viewport (>1s hold, still inside 3.5s touchHoldUntil)
    const driftedWorld = cam.screenToWorld(pokeX + 48, pokeY - 36, viewW, viewH);
    sim.lastInspected = {
      ...sim.lastInspected,
      x: driftedWorld.x,
      y: driftedWorld.y,
    };
    const match2 = inspector.update(sim, focus, cam, pokeX, pokeY, true, true, false, viewW, viewH, 2.25);
    assert.equal(match2.active, true);
    assert.equal(sim.inspectCursor.trackedSlot, 42);
    assert.ok(Math.abs(match2.screenX - (pokeX + 48)) < 1e-3);
    assert.ok(Math.abs(match2.screenY - (pokeY - 36)) < 1e-3);
    // Description tooltip remains completely stationary where the user poked
    assert.equal(inspector.tooltipEl.style.left, tipLeft1);
    assert.equal(inspector.tooltipEl.style.top, tipTop1);

    // Expire touch hold
    const expired = inspector.update(sim, focus, cam, pokeX, pokeY, true, true, false, viewW, viewH, 5.0);
    assert.equal(expired.active, false);
    assert.equal(inspector.tooltipEl.hidden, true);
  } finally {
    globalThis.document = prevDocument;
  }
});
