# Revision 54 — continuous browser presentation

The phone can show good average speed while appearing to stop and jump.
The former client restarted an arrival-driven blend at every snapshot and
clamped it at the target pose when delivery exceeded the estimated interval.
Rebasing from a partially drawn pose also changed velocity at each arrival.

Browser/native network clients now keep at most eight received frames and
interpolate actual consecutive authority endpoints on a monotonic host capture
clock. Typical buffering is two update periods, adaptively bounded to 120–750ms.
Small bounded playback-rate corrections absorb jitter. Long suspensions skip
obsolete history; unavailable future states are never extrapolated. Server time,
chemistry, conservation, RNG, particle limits and resident GPU ownership remain
authoritative and unchanged. The optional presentation_usec wire field is not a
new saved-world field; older clients ignore it.

Cells, external particles, cytoplasmic origins and the Follow/interoception camera
share one interpolation fraction. Water presentation time also advances between
network updates. Death events remain independent of buffered poses. Pause retains
the exact displayed pose; Resume discards old queued history and rejoins live
updates. Reconnect and perception changes reset the appropriate presentation
buffer. Snapshot acknowledgement remains bounded, and each render loop decodes at
most one potentially large snapshot instead of unpacking a burst in one frame.

Particle texture packing writes directly into numeric buffers, avoiding twelve
temporary arrays per particle per upload. GPU presentation still draws the real
server particle states; this does not add a local particle simulator.

Validation: deterministic uneven delivery with constant captured motion, bounded
memory/no extrapolation, independent simulation/wall clocks, wrapped cell poses,
pause/resume, existing camera/perception/death and network/persistence checks.
Exported mobile-browser correctness is distinct from physical phone acceptance.
This revision does not assert a sustained rendered FPS target. Broad rendering
benchmarks remain held; only the requested presentation-pacing diagnosis resumes.
