@group(0) @binding(0) var<uniform> u: SimUniforms;
@group(0) @binding(1) var<storage, read_write> particles: array<Particle>;
@group(0) @binding(2) var<storage, read> binOffsets: array<u32>;
@group(0) @binding(3) var<storage, read> sortedSlots: array<u32>;
@group(0) @binding(4) var<storage, read> feeds: array<FeedGPU>;
@group(0) @binding(5) var<storage, read> bodies: array<BodyGPU>;
@group(0) @binding(6) var<storage, read_write> receipts: Receipts;

@compute @workgroup_size(1)
fn main() {
  let bodyCount = min(64u, u32(u.params1.y + 0.5));
  let feedCount = min(256u, u32(u.params1.z + 0.5));

  var bodyRooms: array<vec4f, 64>;
  for (var b = 0u; b < bodyCount; b++) {
    bodyRooms[b] = bodies[b].rooms;
  }

  for (var f = 0u; f < feedCount; f++) {
    let fd = feeds[f];
    let center = fd.geom.xy;
    let reach = fd.geom.z;
    let kindCode = fd.ids.x;
    let bodyIdx = fd.ids.y;
    let cellId = fd.ids.w;
    if (bodyIdx >= bodyCount) {
      receipts.feedResults[f] = vec4f(0.0);
      continue;
    }

    var room: f32 = 0.0;
    var wantedKind: u32 = SP_NUTRIENT;
    if (kindCode == 0u) {
      room = bodyRooms[bodyIdx].x;
      wantedKind = SP_NUTRIENT;
    } else if (kindCode == 1u) {
      room = bodyRooms[bodyIdx].y;
      wantedKind = SP_OXYGEN;
    } else {
      room = bodyRooms[bodyIdx].z;
      wantedKind = SP_CARBON;
    }

    if (room <= 1e-6) {
      receipts.feedResults[f] = vec4f(0.0);
      continue;
    }

    let wp = wrapPos(center);
    let loX = i32(floor((wp.x - reach) / BIN_SIZE));
    let hiX = i32(floor((wp.x + reach) / BIN_SIZE));
    let loY = i32(floor((wp.y - reach) / BIN_SIZE));
    let hiY = i32(floor((wp.y + reach) / BIN_SIZE));
    let reachSq = reach * reach;

    var takenTotal: f32 = 0.0;
    var fuelTotal: f32 = 0.0;

    for (var by = loY; by <= hiY; by++) {
      for (var bx = loX; bx <= hiX; bx++) {
        if (room <= 1e-6) { break; }
        let bin = binIndexFromCoord(bx, by);
        let start = binOffsets[bin];
        let end = binOffsets[bin + 1u];
        for (var idx = start; idx < end; idx++) {
          if (room <= 1e-6) { break; }
          let slot = sortedSlots[idx];
          var p = particles[slot];
          if (p.motion.w < -0.5) { continue; }
          let pk = u32(p.motion.w + 0.5);
          if (pk != wantedKind) { continue; }
          if (kindCode == 0u && p.ids.y == cellId && p.motion.z < 1.5) { continue; }
          let d = offsetVec(center, p.pose.xy);
          if (dot(d, d) > reachSq) { continue; }

          let oldAmt = p.matter.y;
          if (oldAmt <= 1e-9) { continue; }
          let take = min(room, oldAmt);
          let fuelShare = p.matter.z * (take / oldAmt);

          p.matter.y = oldAmt - take;
          p.matter.z = max(0.0, p.matter.z - fuelShare);
          if (p.matter.y <= 1e-7) {
            p.motion.w = -1.0;
            p.matter.y = 0.0;
            p.matter.z = 0.0;
          } else {
            p.matter.x = 2.0 * particleRadius(u, pk, p.matter.y);
          }
          particles[slot] = p;

          takenTotal += take;
          fuelTotal += fuelShare;
          room -= take;
        }
      }
    }

    if (kindCode == 0u) {
      bodyRooms[bodyIdx].x = room;
    } else if (kindCode == 1u) {
      bodyRooms[bodyIdx].y = room;
    } else {
      bodyRooms[bodyIdx].z = room;
    }
    receipts.feedResults[f] = vec4f(takenTotal, fuelTotal, 0.0, 0.0);
  }
}
