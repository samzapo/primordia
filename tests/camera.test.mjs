import test from 'node:test';
import assert from 'node:assert/strict';
import { Cell } from '../src/sim/cell.ts';
import { offsetVec } from '../src/sim/constants.ts';
import { PondCamera } from '../src/ui/camera.ts';

test('PondCamera two-finger clockwise twist rotates world points clockwise around touch midpoint', () => {
  const cam = new PondCamera();
  const focus = new Cell(1, { x: 2048, y: 1280 });
  cam.setFocusCell(focus, false);
  const viewW = 400;
  const viewH = 800;

  const p0 = { x: 150, y: 400 };
  const p1 = { x: 250, y: 400 };
  const anchors = cam.capturePairAnchors(p0, p1, viewW, viewH);

  // Rotate fingers clockwise by +90 degrees around midpoint (200, 400) while scaling 2x
  const cur0 = { x: 200, y: 300 };
  const cur1 = { x: 200, y: 500 };
  cam.applyAnchoredPairGesture(
    anchors.anchorA,
    anchors.anchorB,
    anchors.startZoom,
    anchors.startDist,
    cur0,
    cur1,
    viewW,
    viewH,
  );

  assert.ok(Math.abs(cam.zoom - 3.3) < 1e-4);
  const screenA = cam.worldToScreen(anchors.anchorA.x, anchors.anchorA.y, viewW, viewH);
  const screenB = cam.worldToScreen(anchors.anchorB.x, anchors.anchorB.y, viewW, viewH);
  assert.ok(Math.hypot(screenA.x - cur0.x, screenA.y - cur0.y) < 1e-3);
  assert.ok(Math.hypot(screenB.x - cur1.x, screenB.y - cur1.y) < 1e-3);
});

test('PondCamera single-finger pan keeps grabbed world point under pointer even while rotated', () => {
  const cam = new PondCamera();
  cam.follow = false;
  cam.rotation = 0.75;
  cam.zoom = 1.8;
  const viewW = 400;
  const viewH = 800;

  const grabbedWorld = cam.screenToWorld(230, 310, viewW, viewH);
  cam.panByScreenDelta(42, -26);
  const afterScreen = cam.worldToScreen(grabbedWorld.x, grabbedWorld.y, viewW, viewH);
  const err = offsetVec({ x: 272, y: 284 }, afterScreen);
  assert.ok(Math.hypot(afterScreen.x - 272, afterScreen.y - 284) < 1e-3, `unexpected drift: ${err.x}, ${err.y}`);
});
