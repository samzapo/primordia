import test from 'node:test';
import assert from 'node:assert/strict';
import { Cell } from '../src/sim/cell.ts';
import { WORLD_H, WORLD_W, offsetVec } from '../src/sim/constants.ts';
import { PondCamera, wraparoundMinZoom } from '../src/ui/camera.ts';

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

test('PondCamera allows zooming out until just short of toroidal wraparound dimensions', () => {
  const cam = new PondCamera();
  const focus = new Cell(1, { x: WORLD_W * 0.5, y: WORLD_H * 0.5 });

  // Mobile portrait (412x915): can zoom out well past 0.8 until height is just short of WORLD_H (2560)
  cam.setViewport(412, 915);
  const mobileMin = cam.minZoom();
  assert.ok(mobileMin < 0.45 && mobileMin > 0.3);
  const visibleMobileH = 915 / mobileMin;
  assert.ok(visibleMobileH < WORLD_H && visibleMobileH > WORLD_H * 0.94);

  cam.zoom = 1.0;
  cam.zoomAtScreenPoint(0.1, 206, 457, 412, 915, focus);
  assert.ok(Math.abs(cam.zoom - mobileMin) < 1e-6);

  // Desktop landscape (1280x720): unrotated zoom stops just short of WORLD_W (4096)
  const deskMin = wraparoundMinZoom(1280, 720, 0);
  assert.ok(deskMin < 0.38);
  const visibleDeskW = 1280 / deskMin;
  assert.ok(visibleDeskW < WORLD_W && visibleDeskW > WORLD_W * 0.94);

  // Rotated 90 deg landscape keeps 1280 span strictly below WORLD_H (2560)
  const rotatedDeskMin = wraparoundMinZoom(1280, 720, Math.PI * 0.5);
  assert.ok(rotatedDeskMin > deskMin);
  assert.ok(1280 / rotatedDeskMin < WORLD_H);
});
