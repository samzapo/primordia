@group(0) @binding(0) var<uniform> u: SimUniforms;
@group(0) @binding(1) var<storage, read> particles: array<Particle>;
@group(0) @binding(2) var<storage, read> reports: array<Report>;
@group(0) @binding(3) var<storage, read> binOffsets: array<u32>;
@group(0) @binding(4) var<storage, read> sortedSlots: array<u32>;
@group(0) @binding(5) var<storage, read> queries: array<QueryGPU>;
@group(0) @binding(6) var<storage, read_write> receipts: Receipts;

const GRAZE_BINS: u32 = 128u;

var<workgroup> wgBestScore: array<f32, 64>;
var<workgroup> wgBestSlot: array<u32, 64>;
var<workgroup> wgBestDist: array<f32, 64>;

var<workgroup> binMass: array<f32, 128>;
var<workgroup> binMomX: array<f32, 128>;
var<workgroup> binMomY: array<f32, 128>;
var<workgroup> binNearDist: array<f32, 128>;
var<workgroup> binNearX: array<f32, 128>;
var<workgroup> binNearY: array<f32, 128>;
var<workgroup> binKeyX: array<i32, 128>;
var<workgroup> binKeyY: array<i32, 128>;
var<workgroup> binKeyFlag: array<u32, 128>;

fn clearResult(qIdx: u32) {
  receipts.queryResults[qIdx * 3u] = vec4f(0.0);
  receipts.queryResults[qIdx * 3u + 1u] = vec4f(0.0);
  receipts.queryResults[qIdx * 3u + 2u] = vec4f(0.0);
}

@compute @workgroup_size(64)
fn queryMain(
  @builtin(workgroup_id) wgid: vec3u,
  @builtin(local_invocation_id) lid: vec3u,
) {
  let qIdx = wgid.x;
  let queryCount = u32(u.params2.x + 0.5);
  if (qIdx >= queryCount) { return; }

  let q = queries[qIdx];
  let center = q.geom.xy;
  let reach = q.geom.z;
  let mode = u32(q.info.w);
  let cellId = q.info.x;
  let lineage = q.info.y;
  let now = u.params0.y;
  let lane = lid.x;

  // Initialize shared bins unconditionally so workgroupBarrier() stays in uniform control flow
  binMass[lane] = 0.0;
  binMomX[lane] = 0.0;
  binMomY[lane] = 0.0;
  binNearDist[lane] = 1e9;
  binNearX[lane] = 0.0;
  binNearY[lane] = 0.0;
  binKeyFlag[lane] = 0u;

  binMass[lane + 64u] = 0.0;
  binMomX[lane + 64u] = 0.0;
  binMomY[lane + 64u] = 0.0;
  binNearDist[lane + 64u] = 1e9;
  binNearX[lane + 64u] = 0.0;
  binNearY[lane + 64u] = 0.0;
  binKeyFlag[lane + 64u] = 0u;
  workgroupBarrier();

  let wp = wrapPos(center);
  let loX = i32(floor((wp.x - reach) / BIN_SIZE));
  let hiX = i32(floor((wp.x + reach) / BIN_SIZE));
  let loY = i32(floor((wp.y - reach) / BIN_SIZE));
  let hiY = i32(floor((wp.y + reach) / BIN_SIZE));
  let spanX = max(1, hiX - loX + 1);
  let spanY = max(1, hiY - loY + 1);
  let totalBins = u32(spanX * spanY);
  let reachSq = reach * reach;

  // Parallel scan state (used when mode != 2u)
  var localBestScore: f32 = -1.0;
  var localBestSlot: u32 = 0xffffffffu;
  var localBestDist: f32 = 1e9;

  // Mode 2: patch-aware food foraging (serialized bin accumulation on lane 0)
  if (mode == 2u) {
    if (lane == 0u) {
      let patchSize = max(80.0, reach * 0.25);
      for (var bIdx = 0u; bIdx < totalBins; bIdx++) {
        let bx = loX + i32(bIdx % u32(spanX));
        let by = loY + i32(bIdx / u32(spanX));
        let bin = binIndexFromCoord(bx, by);
        let start = binOffsets[bin];
        let end = binOffsets[bin + 1u];
        for (var idx = start; idx < end; idx++) {
          let slot = sortedSlots[idx];
          let p = particles[slot];
          if (p.motion.w < -0.5 || u32(p.motion.w + 0.5) != SP_NUTRIENT) { continue; }
          if (i32(p.ids.y) == cellId && p.motion.z < 1.5) { continue; }
          let d = offsetVec(center, p.pose.xy);
          let dSq = dot(d, d);
          if (dSq > reachSq) { continue; }
          let dist = sqrt(dSq);
          let px = i32(floor(d.x / patchSize));
          let py = i32(floor(d.y / patchSize));
          let h = (u32(px * 73856093) ^ u32(py * 19349663)) & 127u;
          for (var probe = 0u; probe < 128u; probe++) {
            let slotH = (h + probe) & 127u;
            if (binKeyFlag[slotH] == 0u || (binKeyX[slotH] == px && binKeyY[slotH] == py)) {
              binKeyFlag[slotH] = 1u;
              binKeyX[slotH] = px;
              binKeyY[slotH] = py;
              binMass[slotH] += p.matter.y;
              binMomX[slotH] += d.x * p.matter.y;
              binMomY[slotH] += d.y * p.matter.y;
              if (dist < binNearDist[slotH]) {
                binNearDist[slotH] = dist;
                binNearX[slotH] = d.x;
                binNearY[slotH] = d.y;
              }
              break;
            }
          }
        }
      }

      var bestScore: f32 = -1.0;
      var bestAt = vec2f(0.0, 0.0);
      var bestMass: f32 = 0.0;
      for (var i = 0u; i < 128u; i++) {
        if (binKeyFlag[i] == 0u) { continue; }
        let kx = binKeyX[i];
        let ky = binKeyY[i];
        var totMass: f32 = 0.0;
        var mom = vec2f(0.0, 0.0);
        var nearD: f32 = 1e9;
        var nearV = vec2f(0.0, 0.0);

        for (var j = 0u; j < 128u; j++) {
          if (binKeyFlag[j] == 0u) { continue; }
          if (abs(binKeyX[j] - kx) <= 1 && abs(binKeyY[j] - ky) <= 1) {
            totMass += binMass[j];
            mom += vec2f(binMomX[j], binMomY[j]);
            if (binNearDist[j] < nearD) {
              nearD = binNearDist[j];
              nearV = vec2f(binNearX[j], binNearY[j]);
            }
          }
        }
        if (totMass <= 0.0) { continue; }
        let cVec = mom / totMass;
        let cLen = length(cVec);
        let sc = totMass / (1.0 + cLen / max(1.0, reach));
        if (sc > bestScore) {
          bestScore = sc;
          bestMass = totMass;
          let inner = max(70.0, q.geom.w);
          let chosen = select(cVec, nearV, cLen <= inner);
          bestAt = wrapPos(center + chosen);
        }
      }

      if (bestScore > 0.0) {
        receipts.queryResults[qIdx * 3u] = vec4f(1.0, bestAt.x, bestAt.y, bestScore);
        receipts.queryResults[qIdx * 3u + 1u] = vec4f(length(offsetVec(center, bestAt)), 0.0, 0.0, now);
        receipts.queryResults[qIdx * 3u + 2u] = vec4f(now + 1.2, bestMass, 0.0, 0.0);
      } else {
        clearResult(qIdx);
      }
    }
  } else {
    // Parallel scan across bounding bins for modes 0, 1, 3, 4, 6, 7
    for (var bIdx = lane; bIdx < totalBins; bIdx += 64u) {
      let bx = loX + i32(bIdx % u32(spanX));
      let by = loY + i32(bIdx / u32(spanX));
      let bin = binIndexFromCoord(bx, by);
      let start = binOffsets[bin];
      let end = binOffsets[bin + 1u];

      for (var idx = start; idx < end; idx++) {
        let slot = sortedSlots[idx];
        let p = particles[slot];
        if (p.motion.w < -0.5) { continue; }
        let pk = u32(p.motion.w + 0.5);
        let d = offsetVec(center, p.pose.xy);
        let dSq = dot(d, d);
        if (dSq > reachSq) { continue; }
        let dist = sqrt(dSq);

        if (mode == 3u) {
          if (pk != SP_WASTE) { continue; }
          let sc = 1.0 / (1.0 + dist);
          if (sc > localBestScore) {
            localBestScore = sc;
            localBestSlot = slot;
            localBestDist = dist;
          }
        } else if (mode == 4u) {
          if (pk != SP_TOXIN && pk != SP_TAG && pk != SP_PORE) { continue; }
          let sc = 1.0 / (1.0 + dist);
          if (sc > localBestScore) {
            localBestScore = sc;
            localBestSlot = slot;
            localBestDist = dist;
          }
        } else if (mode == 7u) {
          if (pk != SP_TOXIN) { continue; }
          let sc = 100.0 / (1.0 + dist);
          if (sc > localBestScore) {
            localBestScore = sc;
            localBestSlot = slot;
            localBestDist = dist;
          }
        } else if (mode == 0u || mode == 1u || mode == 6u) {
          if (pk != SP_PHEROMONE) { continue; }
          let rep = reports[slot];
          if (rep.timing.z < 0.5 || rep.timing.y <= now) { continue; }
          let rId = i32(rep.info.x);
          let rLin = i32(rep.info.y);
          if (rId == cellId) { continue; }
          if (mode == 0u && rLin == lineage) { continue; }
          if (mode == 1u && (rLin == lineage || rep.info.z == 0u)) { continue; }
          if (mode == 6u && rLin != lineage) { continue; }

          let freshness = max(0.0, 1.0 - (now - rep.timing.x) / 15.0);
          let sc = (1.0 / (1.0 + dist / max(1.0, reach))) * (0.5 + 0.5 * freshness);
          if (sc > localBestScore) {
            localBestScore = sc;
            localBestSlot = slot;
            localBestDist = dist;
          }
        }
      }
    }
  }

  wgBestScore[lane] = localBestScore;
  wgBestSlot[lane] = localBestSlot;
  wgBestDist[lane] = localBestDist;
  workgroupBarrier();

  for (var stride = 32u; stride > 0u; stride >>= 1u) {
    if (lane < stride) {
      if (wgBestScore[lane + stride] > wgBestScore[lane]) {
        wgBestScore[lane] = wgBestScore[lane + stride];
        wgBestSlot[lane] = wgBestSlot[lane + stride];
        wgBestDist[lane] = wgBestDist[lane + stride];
      }
    }
    workgroupBarrier();
  }

  if (lane == 0u && mode != 2u) {
    let winSlot = wgBestSlot[0];
    if (winSlot == 0xffffffffu || wgBestScore[0] <= 0.0) {
      clearResult(qIdx);
    } else if (mode == 3u || mode == 4u || mode == 7u) {
      let p = particles[winSlot];
      receipts.queryResults[qIdx * 3u] = vec4f(1.0, p.pose.x, p.pose.y, wgBestScore[0]);
      receipts.queryResults[qIdx * 3u + 1u] = vec4f(wgBestDist[0], 0.0, 0.0, now);
      receipts.queryResults[qIdx * 3u + 2u] = vec4f(now + 0.8, p.matter.y, 0.0, 0.0);
    } else {
      let rep = reports[winSlot];
      let flags = f32(rep.info.z + rep.info.w * 2u);
      receipts.queryResults[qIdx * 3u] = vec4f(1.0, rep.geom.x, rep.geom.y, wgBestScore[0]);
      receipts.queryResults[qIdx * 3u + 1u] = vec4f(
        wgBestDist[0],
        bitcast<f32>(rep.info.x),
        bitcast<f32>(rep.info.y),
        rep.timing.x,
      );
      receipts.queryResults[qIdx * 3u + 2u] = vec4f(rep.timing.y, rep.geom.z, rep.geom.w, flags);
    }
  }
}

@compute @workgroup_size(1)
fn inspectMain() {
  if (u.params3.y < 0.5) {
    receipts.inspected[0] = vec4f(0.0);
    return;
  }

  let maxP = u32(u.params1.x + 0.5);
  let trackedSlot = i32(u.params4.y);
  let trackedGen = u32(u.params4.z + 0.5);
  let now = u.params0.y;
  var winSlot = 0xffffffffu;

  if (trackedSlot >= 0 && u32(trackedSlot) < maxP) {
    let p = particles[u32(trackedSlot)];
    if (p.motion.w >= -0.5 && p.ids.x == trackedGen) {
      let pk = u32(p.motion.w + 0.5);
      if (pk != SP_PHEROMONE || reports[u32(trackedSlot)].timing.y > now) {
        winSlot = u32(trackedSlot);
      }
    }
  }

  if (winSlot == 0xffffffffu) {
    let cursor = vec2f(u.params3.z, u.params3.w);
    let maxR = u.params4.x;
    let wp = wrapPos(cursor);
    let loX = i32(floor((wp.x - maxR) / BIN_SIZE));
    let hiX = i32(floor((wp.x + maxR) / BIN_SIZE));
    let loY = i32(floor((wp.y - maxR) / BIN_SIZE));
    let hiY = i32(floor((wp.y + maxR) / BIN_SIZE));
    var bestD = maxR + 1.0;

    for (var by = loY; by <= hiY; by++) {
      for (var bx = loX; bx <= hiX; bx++) {
        let bin = binIndexFromCoord(bx, by);
        let start = binOffsets[bin];
        let end = binOffsets[bin + 1u];
        for (var idx = start; idx < end; idx++) {
          let slot = sortedSlots[idx];
          let p = particles[slot];
          if (p.motion.w < -0.5) { continue; }
          let pk = u32(p.motion.w + 0.5);
          if (pk == SP_PHEROMONE && reports[slot].timing.y <= now) { continue; }
          let d = length(offsetVec(cursor, p.pose.xy));
          let rad = p.matter.x * 0.5;
          let effD = max(0.0, d - rad);
          if (d <= maxR + rad && effD < bestD) {
            bestD = effD;
            winSlot = slot;
          }
        }
      }
    }
  }

  if (winSlot == 0xffffffffu) {
    receipts.inspected[0] = vec4f(0.0);
    return;
  }

  let p = particles[winSlot];
  let rep = reports[winSlot];
  receipts.inspected[0] = vec4f(1.0, bitcast<f32>(winSlot), bitcast<f32>(p.ids.x), p.motion.w);
  receipts.inspected[1] = vec4f(p.pose.x, p.pose.y, p.pose.z, p.matter.y);
  receipts.inspected[2] = vec4f(
    p.matter.z,
    bitcast<f32>(p.ids.y),
    bitcast<f32>(p.ids.z),
    rep.timing.y,
  );
  receipts.inspected[3] = rep.geom;
  receipts.inspected[4] = vec4f(
    bitcast<f32>(rep.info.x),
    bitcast<f32>(rep.info.y),
    rep.timing.x,
    f32(rep.info.z + rep.info.w * 2u),
  );
}
