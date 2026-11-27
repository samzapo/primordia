@group(0) @binding(0) var<storage, read> binCounts: array<u32>;
@group(0) @binding(1) var<storage, read_write> binOffsets: array<u32>;
@group(0) @binding(2) var<storage, read_write> blockTotals: array<u32>;

const BIN_COUNT_U32: u32 = 40960u;
const WG_SIZE: u32 = 256u;

var<workgroup> temp: array<u32, 256>;
var<workgroup> spineTemp: array<u32, 256>;

@compute @workgroup_size(256)
fn reduceBlocks(
  @builtin(workgroup_id) wgid: vec3u,
  @builtin(local_invocation_id) lid: vec3u,
  @builtin(global_invocation_id) gid: vec3u,
) {
  let idx = gid.x;
  var val = 0u;
  if (idx < BIN_COUNT_U32) {
    val = binCounts[idx];
  }
  temp[lid.x] = val;
  workgroupBarrier();

  var offset = 1u;
  while (offset < WG_SIZE) {
    var prev = 0u;
    if (lid.x >= offset) {
      prev = temp[lid.x - offset];
    }
    workgroupBarrier();
    temp[lid.x] += prev;
    workgroupBarrier();
    offset <<= 1u;
  }

  let inclusive = temp[lid.x];
  let exclusive = inclusive - val;
  if (idx < BIN_COUNT_U32) {
    binOffsets[idx] = exclusive;
  }
  if (lid.x == WG_SIZE - 1u) {
    blockTotals[wgid.x] = inclusive;
  }
}

@compute @workgroup_size(256)
fn scanSpine(@builtin(local_invocation_id) lid: vec3u) {
  let numBlocks = 160u;
  var val = 0u;
  if (lid.x < numBlocks) {
    val = blockTotals[lid.x];
  }
  spineTemp[lid.x] = val;
  workgroupBarrier();

  var offset = 1u;
  while (offset < WG_SIZE) {
    var prev = 0u;
    if (lid.x >= offset) {
      prev = spineTemp[lid.x - offset];
    }
    workgroupBarrier();
    spineTemp[lid.x] += prev;
    workgroupBarrier();
    offset <<= 1u;
  }

  if (lid.x < numBlocks) {
    blockTotals[lid.x] = spineTemp[lid.x] - val;
  }
  if (lid.x == numBlocks - 1u) {
    binOffsets[BIN_COUNT_U32] = spineTemp[lid.x];
  }
}

@compute @workgroup_size(256)
fn addOffsets(
  @builtin(workgroup_id) wgid: vec3u,
  @builtin(global_invocation_id) gid: vec3u,
) {
  let idx = gid.x;
  if (idx < BIN_COUNT_U32) {
    binOffsets[idx] += blockTotals[wgid.x];
  }
}
